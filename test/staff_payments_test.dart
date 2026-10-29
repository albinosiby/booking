import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/staff_cash/cubit/staff_cash_cubits.dart';
import 'package:eden_booking/modules/staff_cash/models/staff_cash_models.dart';
import 'package:eden_booking/modules/staff_cash/screens/staff_cash_screen.dart';
import 'package:eden_booking/modules/staff_cash/repositories/rest_staff_cash_repository.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/modules/workspace/models/workspace_navigation.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'package:dio/dio.dart';
import 'access_navigation_test.dart' show AccessRepository, staff;
import 'cached_transport_test.dart' show TestAuth, TestAdapter;
import 'staff_cash_test.dart' show FakeStaffCash;

StaffCashTransaction transaction(String id) => StaffCashTransaction(
  id: id,
  kind: 'booking_collection',
  reason: '',
  space: 'Main pool',
  staffName: 'Asha',
  mine: true,
  time: '2026-10-29 9:00 AM',
  netMinor: 250000,
  cashMinor: 250000,
  customer: 'Student $id',
  reference: 'BK-$id',
  methods: const ['cash'],
);
StaffCashSettlement handover(String id) => StaffCashSettlement(
  id: id,
  staffName: 'Asha',
  direction: 'collect',
  amountMinor: 300000,
  balanceAfterMinor: 150000,
  note: 'Confirmed by owner',
  settledAt: DateTime(2026, 10, 29, 12),
);
StaffCashDay day({
  String date = '2026-10-29',
  int? next,
  int? nextHandover,
  List<StaffCashTransaction>? activity,
  List<StaffCashSettlement>? handovers,
}) => StaffCashDay(
  date: date,
  today: '2026-10-29',
  collectedMinor: 700000,
  refundedMinor: 0,
  expensesMinor: 50000,
  cashMinor: 500000,
  upiMinor: 200000,
  cardMinor: 0,
  bankMinor: 200000,
  holdingMinor: 150000,
  handedOverMinor: 300000,
  transactions: activity ?? [transaction('one')],
  settlements: handovers ?? [handover('one')],
  nextCursor: next,
  nextSettlementCursor: nextHandover,
);

typedef PageCall = ({String? date, int cursor, int settlementCursor});

class PersonalCash extends FakeStaffCash {
  final updates = StreamController<void>.broadcast();
  final calls = <PageCall>[];
  Future<StaffCashDay> Function(PageCall)? respond;
  @override
  Stream<void> get changes => updates.stream;
  @override
  Future<StaffCashDay> me({
    String? date,
    int cursor = 0,
    int settlementCursor = 0,
  }) async {
    final call = (
      date: date,
      cursor: cursor,
      settlementCursor: settlementCursor,
    );
    calls.add(call);
    return respond == null ? day(date: date ?? '2026-10-29') : respond!(call);
  }
}

Future<WorkspaceCubit> session() async {
  final s = WorkspaceCubit(
    AccessRepository()..next = staff(['collect_payments']),
  );
  await s.load();
  addTearDown(s.close);
  return s;
}

Future<void> capture(GlobalKey key, String name, WidgetTester tester) async {
  if (!const bool.fromEnvironment('STAFF_PAYMENTS_PREVIEWS')) return;
  await tester.runAsync(() async {
    final render =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = File('.local/staff-payments-previews/$name.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('STAFF_PAYMENTS_PREVIEWS')) return;
    const directory = String.fromEnvironment('STAFF_PAYMENTS_FONT_DIR');
    for (final item in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File('$directory/${item.value}').readAsBytes();
      await (FontLoader(
        item.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  tearDown(getIt.reset);

  test(
    'pagination merges each history independently, keeps totals and deduplicates taps',
    () async {
      final s = await session();
      final repo = PersonalCash();
      addTearDown(repo.updates.close);
      repo.respond = (c) async => day(next: 1, nextHandover: 1);
      final cubit = StaffCashCubit(repo, session: s);
      addTearDown(cubit.close);
      await cubit.load();
      final gate = Completer<StaffCashDay>();
      repo.respond = (_) => gate.future;
      final loading = cubit.loadMore();
      await cubit.loadMore();
      expect(repo.calls.length, 2);
      gate.complete(day(activity: [transaction('one'), transaction('two')]));
      await loading;
      expect(cubit.state.day!.transactions.map((t) => t.id), ['one', 'two']);
      expect(cubit.state.day!.nextSettlementCursor, 1);
      expect(cubit.state.day!.handedOverMinor, 300000);
      repo.respond = (_) async =>
          day(handovers: [handover('one'), handover('two')]);
      await cubit.loadMore(settlements: true);
      expect(repo.calls.last.settlementCursor, 1);
      expect(cubit.state.day!.transactions.length, 2);
      expect(cubit.state.day!.settlements.map((t) => t.id), ['one', 'two']);
      expect(cubit.state.day!.nextCursor, isNull);
      expect(cubit.state.day!.nextSettlementCursor, isNull);
    },
  );

  test(
    'changing dates discards late history; access errors clear financial data',
    () async {
      final s = await session(), repo = PersonalCash();
      addTearDown(repo.updates.close);
      repo.respond = (_) async => day(next: 1);
      final cubit = StaffCashCubit(repo, session: s);
      addTearDown(cubit.close);
      await cubit.load();
      final gate = Completer<StaffCashDay>();
      repo.respond = (_) => gate.future;
      final loading = cubit.loadMore();
      repo.respond = (c) async => day(date: c.date!);
      await cubit.load(date: '2026-10-28');
      gate.complete(day(activity: [transaction('late')]));
      await loading;
      expect(cubit.state.day!.date, '2026-10-28');
      expect(cubit.state.day!.transactions.map((t) => t.id), ['one']);
      repo.respond = (_) async =>
          throw const AppException('Offline', code: 'NETWORK');
      await cubit.load();
      expect(cubit.state.day, isNotNull);
      repo.respond = (_) async =>
          throw const AppException('Forbidden', code: 'FORBIDDEN');
      await cubit.load();
      expect(cubit.state.day, isNull);
    },
  );

  test(
    'revocation clears retained amounts and ignores in-flight results',
    () async {
      final source = AccessRepository()..next = staff(['collect_payments']);
      final s = WorkspaceCubit(source);
      await s.load();
      addTearDown(s.close);
      final repo = PersonalCash();
      addTearDown(repo.updates.close);
      final cubit = StaffCashCubit(repo, session: s);
      addTearDown(cubit.close);
      await cubit.load();
      final gate = Completer<StaffCashDay>();
      repo.respond = (_) => gate.future;
      final loading = cubit.load();
      source.next = staff([]);
      await s.refreshAccess();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.day, isNull);
      gate.complete(day());
      await loading;
      expect(cubit.state.day, isNull);
      await cubit.load();
      expect(repo.calls.length, 2);
    },
  );

  test(
    'permitted assignment changes refresh retained payments under the new scope',
    () async {
      final source = AccessRepository()..next = staff(['collect_payments']);
      final s = WorkspaceCubit(source);
      await s.load();
      addTearDown(s.close);
      final repo = PersonalCash();
      addTearDown(repo.updates.close);
      final cubit = StaffCashCubit(repo, session: s);
      addTearDown(cubit.close);
      await cubit.load();
      source.next = staff(['collect_payments', 'view_finance']);
      await s.refreshAccess();
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls.length, 2);
      expect(cubit.state.day, isNotNull);
    },
  );

  test(
    'transport keeps date and independent cursors and never maps bank balances',
    () async {
      final auth = TestAuth();
      final adapter = TestAdapter();
      final payload = {
        'date': '2026-10-29',
        'today': '2026-10-29',
        'handed_over_minor': 300000,
        'received_from_owner_minor': 0,
        'cash_holding_minor': 150000,
        'by_method': {'cash': 500000, 'upi': 200000, 'bank_transfer': 1000},
        'transactions': [],
        'settlements': [],
        'next_cursor': 100,
        'next_settlement_cursor': null,
      };
      adapter.pending = Completer<ResponseBody>()
        ..complete(
          ResponseBody.fromString(
            jsonEncode(payload),
            200,
            headers: {
              'content-type': ['application/json'],
              'cache-control': ['private, no-store'],
            },
          ),
        );
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      final api = RestApiService(auth, dio: dio);
      final repo = RestStaffCashRepository(api);
      final result = await repo.me(
        date: '2026-10-29',
        cursor: 50,
        settlementCursor: 20,
      );
      expect(adapter.lastOptions!.uri.queryParameters, {
        'date': '2026-10-29',
        'cursor': '50',
        'settlement_cursor': '20',
      });
      expect(result.nextCursor, 100);
      expect(result.bankTransferMinor, 1000);
      expect(result.handedOverMinor, 300000);
      await api.dispose();
      await auth.events.close();
    },
  );

  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets(
      'personal Payments fits ${width.toInt()}px and date filter preserves current balance',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final s = await session(), repo = PersonalCash();
        addTearDown(repo.updates.close);
        getIt.registerFactoryParam<StaffCashCubit, WorkspaceSession, void>(
          (session, _) => StaffCashCubit(repo, session: session),
        );
        final key = GlobalKey();
        ThemeData buildTheme() {
          final theme = AppTheme.build(
            width == 1440 ? Brightness.dark : Brightness.light,
          );
          return theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
          );
        }

        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => BlocProvider.value(
              value: s,
              child: MaterialApp(
                theme: buildTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(width == 320 ? 1.4 : 1),
                  ),
                  child: RepaintBoundary(key: key, child: child!),
                ),
                home: Scaffold(
                  body: const StaffCashScreen(asTab: true),
                  bottomNavigationBar: AppBottomNavBar(
                    index: 3,
                    branches: WorkspaceNavigation(s.state.data).branches,
                    staffPayments: true,
                    onTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        addTearDown(() => tester.pumpWidget(const SizedBox()));
        expect(find.text('Payments'), findsNWidgets(2));
        expect(find.byTooltip('Accounts and reports'), findsNothing);
        expect(find.text('Cash to hand over'), findsOneWidget);
        expect(find.text('Given to owner · all time'), findsOneWidget);
        expect(find.text('₹ 1500.00'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(key, 'summary-${width.toInt()}', tester);
        await tester.tap(find.byTooltip('Choose collection date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('28').last);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(repo.calls.last.date, '2026-10-28');
        expect(find.text('₹ 1500.00'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Student one'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('BK-one'), findsOneWidget);
        await capture(key, 'activity-${width.toInt()}', tester);
        await tester.scrollUntilVisible(
          find.textContaining('Given to owner · ₹'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Confirmed by owner'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

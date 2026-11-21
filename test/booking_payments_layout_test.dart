import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_list_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_list_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_payments_view.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

const balance = BookingOutstanding(
  id: 'balance',
  reference: '#BK-SAMPLE-001',
  status: 'confirmed',
  customer: 'Sample customer',
  business: 'Turf',
  space: 'Main Ground · Half A',
  localStart: '2026-11-18T19:00',
  balance: 90000,
  refund: 0,
);
const refund = BookingOutstanding(
  id: 'refund',
  reference: '#BK-LONG-REFERENCE-2026-SAMPLE-002',
  status: 'refund_due',
  customer: 'Another customer with a longer name',
  business: 'Sports and recreation centre',
  space: 'Main Ground · Full Ground',
  localStart: '2026-11-18T20:00',
  balance: 0,
  refund: 125050,
);
const payment = BookingPayment(
  id: 'payment',
  kind: 'collection',
  method: 'upi',
  amount: 150000,
  reference: 'EXAMPLE-UTR',
  localReceived: '2026-11-18T18:00',
  collector: 'Sample staff member',
  reason: '',
);

class PaymentsRepository extends FakeBookingRepository {
  final requests = <({bool due, String? date, String? business, int cursor})>[];
  bool denyViewing = false;
  bool fail = false;
  @override
  Future<BookingCatalog> catalog() async =>
      denyViewing ? const BookingCatalog(canCollect: true) : super.catalog();
  @override
  Future<OutstandingPage> outstanding({
    String? date,
    String? businessId,
    int cursor = 0,
  }) async {
    requests.add((due: true, date: date, business: businessId, cursor: cursor));
    if (fail) throw Exception('Synthetic refresh failure');
    return const OutstandingPage([balance, refund], null, 5190000, 125050);
  }

  @override
  Future<CollectionPage> collections({
    String? date,
    String? businessId,
    int cursor = 0,
  }) async {
    requests.add((
      due: false,
      date: date,
      business: businessId,
      cursor: cursor,
    ));
    return const CollectionPage(
      [
        CollectionEntry(
          'balance',
          '#BK-SAMPLE-001',
          'Sample customer',
          payment,
        ),
      ],
      null,
      [
        CollectionTotal('collection', 'cash', 100000),
        CollectionTotal('refund', 'cash', 5000),
        CollectionTotal('collection', 'upi', 150000),
      ],
    );
  }
}

Future<({BookingListCubit cubit, PaymentsRepository repo, GlobalKey preview})>
mount(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool dark = true,
  bool due = true,
  bool canView = true,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final workspace = WorkspaceCubit(BookingSource());
  await workspace.load();
  final repo = PaymentsRepository()..denyViewing = !canView;
  final cubit = BookingListCubit(workspace, repo, BookingListMode.payments);
  if (due) cubit.dueView(true);
  await cubit.load();
  addTearDown(cubit.close);
  addTearDown(workspace.close);
  addTearDown(repo.events.close);
  final preview = GlobalKey();
  final router = GoRouter(
    initialLocation: '/payments',
    routes: [
      GoRoute(
        path: '/payments',
        builder: (_, _) => BlocBuilder<BookingListCubit, BookingListModel>(
          bloc: cubit,
          builder: (_, state) =>
              BookingPaymentsView(state: state, cubit: cubit, back: true),
        ),
      ),
      GoRoute(
        path: '/booking/:id',
        builder: (_, state) =>
            Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    BlocProvider.value(
      value: workspace,
      child: ScreenUtilInit(
        designSize: Size(width >= 900 ? 1440 : 390, width >= 900 ? 1000 : 844),
        builder: (_, _) => MaterialApp.router(
          theme: previewTheme(dark),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: preview, child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (cubit: cubit, repo: repo, preview: preview);
}

ThemeData previewTheme(bool dark) {
  final theme = dark ? darkTheme() : lightTheme();
  if (!const bool.fromEnvironment('PAYMENTS_PREVIEWS')) return theme;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'Roboto'),
  );
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('PAYMENTS_PREVIEWS')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = File('/private/tmp/booking-payments-layout/$name.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('PAYMENTS_PREVIEWS')) return;
    const directory = String.fromEnvironment('PAYMENTS_FONT_DIR');
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File('$directory/${font.value}').readAsBytes();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  for (final size in [
    (width: 390.0, scale: 1.0, dark: true),
    (width: 320.0, scale: 2.0, dark: true),
    (width: 390.0, scale: 1.0, dark: false),
    (width: 1200.0, scale: 1.0, dark: true),
  ]) {
    testWidgets(
      'balance cards fill ${size.width}px content at ${size.scale}x text, dark=${size.dark}',
      (tester) async {
        final app = await mount(
          tester,
          width: size.width,
          scale: size.scale,
          dark: size.dark,
        );
        final picker = tester.getRect(find.byType(AppPicker));
        for (final key in [
          'payments-balance-summary',
          'payment-balance-balance',
          'payment-balance-refund',
        ]) {
          final card = tester.getRect(find.byKey(ValueKey(key)));
          expect(card.left, closeTo(picker.left, .1));
          expect(card.right, closeTo(picker.right, .1));
        }
        expect(find.text('All dates'), findsNothing);
        expect(find.text('Date · All dates'), findsOneWidget);
        final viewLabel = tester.renderObject<RenderParagraph>(
          find.text('Balances & refunds'),
        );
        expect(viewLabel.didExceedMaxLines, isFalse);
        expect(
          tester.getRect(find.text('Balances & refunds')).bottom,
          lessThanOrEqualTo(
            tester
                .getRect(find.byKey(const ValueKey('payments-view-balances')))
                .bottom,
          ),
        );

        expect(find.text('INR 51900.00'), findsOneWidget);
        expect(find.text('INR 1250.50'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          app.preview,
          'balances-${size.width.toInt()}-${size.scale}-${size.dark}',
        );
      },
    );
  }

  testWidgets('Collections wraps at 320px with double-size text', (
    tester,
  ) async {
    final app = await mount(tester, width: 320, scale: 2, due: false);
    for (final key in [
      'payments-collection-summary',
      'payment-collection-payment',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))).width,
        tester.getSize(find.byType(AppPicker)).width,
      );
    }
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Balances & refunds'))
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('payment-collection-payment')),
    );
    await tester.pumpAndSettle();
    await capture(tester, app.preview, 'collections-320-large-text');
  });

  testWidgets(
    'Collections uses full-width cards, correct net totals and date reset',
    (tester) async {
      final app = await mount(tester);
      await tester.tap(find.byKey(const ValueKey('payments-view-collections')));
      await tester.pumpAndSettle();
      expect(
        find.text('Manually recorded collections and refunds.'),
        findsOneWidget,
      );
      expect(
        find.text('Current outstanding balances and refunds.'),
        findsNothing,
      );
      expect(find.text('INR 950.00'), findsOneWidget);
      expect(find.text('INR 1500.00'), findsNWidgets(3));
      for (final key in [
        'payments-collection-summary',
        'payment-collection-payment',
      ]) {
        expect(
          tester.getSize(find.byKey(ValueKey(key))).width,
          tester.getSize(find.byType(AppPicker)).width,
        );
      }
      expect(find.text('All dates'), findsOneWidget);
      await tester.tap(find.text('All dates'));
      await tester.pumpAndSettle();
      expect(app.cubit.state.date, isNull);
      expect(app.repo.requests.last.date, isNull);
      expect(find.text('All dates'), findsNothing);
      expect(find.text('Date · All dates'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, app.preview, 'collections-390');
    },
  );

  testWidgets(
    'refresh and business filter retain their requests; cards open details',
    (tester) async {
      final app = await mount(tester);
      await tester.tap(find.byType(AppPicker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Badminton'));
      await tester.pumpAndSettle();
      expect(app.cubit.state.businessId, 'business');
      expect(app.repo.requests.last.business, 'business');
      final before = app.repo.requests.length;
      await tester.tap(find.widgetWithText(TextButton, 'Refresh'));
      await tester.pumpAndSettle();
      expect(app.repo.requests.length, before + 1);
      await tester.ensureVisible(find.text('Sample customer'));
      await tester.tap(find.text('Sample customer'));
      await tester.pumpAndSettle();
      expect(find.text('Opened balance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('payment-only access does not expose booking navigation', (
    tester,
  ) async {
    await mount(tester, canView: false);
    expect(
      tester
          .widget<AppCard>(
            find.byKey(const ValueKey('payment-balance-balance')),
          )
          .onTap,
      isNull,
    );
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('failed refresh keeps the existing balances visible with retry', (
    tester,
  ) async {
    final app = await mount(tester);
    app.repo.fail = true;
    await app.cubit.load();
    await tester.pumpAndSettle();
    expect(find.byType(AppErrorWidget), findsOneWidget);
    expect(find.text('INR 51900.00'), findsOneWidget);
    expect(find.text('Sample customer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

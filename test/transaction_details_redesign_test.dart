import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/accounts/models/accounts_screen_models.dart';
import 'package:eden_booking/modules/accounts/widgets/transaction_details_content.dart';
import 'package:eden_booking/modules/accounts/cubit/accounts_cubits.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'booking_module_test.dart' show BookingSource;
import 'accounts_module_test.dart' show FakeAccountsRepository;

FinanceTransaction entry(
  String kind,
  List<FinanceLine> lines, {
  bool booking = false,
}) => FinanceTransaction(
  id: 'entry',
  kind: kind,
  reason: 'Payment for evening session',
  category: '',
  date: '2030-06-04T18:00',
  staff: 'Owner',
  reference: 'UPI-123',
  bookingId: booking ? 'booking' : null,
  bookingReference: booking ? 'BK-123' : null,
  customer: booking ? 'Customer One' : null,
  tariff: booking ? 65000 : null,
  lines: lines,
);

class ReversalRepository extends FakeAccountsRepository {
  int reversals = 0;
  @override
  Future<void> reverse(String id, Map<String, Object?> request) async {
    reversals++;
  }
}

void main() {
  test(
    'receipt models preserve signs, transfer amount and category meaning',
    () {
      final expense = TransactionDetailsModel(
        entry('expense', const [FinanceLine('cash', 'Cash', 'cash', -65000)]),
      );
      expect(expense.displayAmount, 65000);
      expect(expense.categoryLabel, 'Not specified');
      final reverse = TransactionDetailsModel(
        entry('reversal', const [
          FinanceLine('cash', 'Cash', 'cash', 50000),
          FinanceLine('bank', 'Bank', 'bank_transfer', -50000),
        ]),
      );
      expect(reverse.displayAmount, 50000);
      expect(reverse.typeLabel, 'Transfer reversal');
      expect(reverse.isTransfer, isTrue);
      expect(reverse.reversibleKind, isFalse);
      expect(
        TransactionDetailsModel(
          entry('booking_collection', [], booking: true),
        ).categoryLabel,
        'Booking',
      );
    },
  );
  test(
    'reversal retains owner permission and refuses booking payment reversal',
    () async {
      final source = BookingSource(),
          w = WorkspaceCubit(BookingSource()),
          r = ReversalRepository();
      await w.load();
      final booking = TransactionDetailsCubit(
        w,
        r,
        entry('booking_collection', [], booking: true),
      );
      await booking.reverse('Correction');
      expect(r.reversals, 0);
      await booking.close();
      final expense = TransactionDetailsCubit(
        w,
        r,
        entry('expense', const [FinanceLine('cash', 'Cash', 'cash', -500)]),
      );
      await expense.reverse('Correction');
      expect(r.reversals, 1);
      expect(expense.state.reversed, isTrue);
      await expense.reverse('Again');
      expect(r.reversals, 1);
      await expense.close();
      await w.close();
      source.value = Workspace(
        organization: source.value.organization,
        membership: const {
          'role': 'staff',
          'permissions': ['view_finance'],
        },
      );
      final staff = WorkspaceCubit(source);
      await staff.load();
      final detail = TransactionDetailsCubit(staff, r, entry('expense', []));
      await detail.reverse('Correction');
      expect(r.reversals, 1);
      await detail.close();
      await staff.close();
      await r.events.close();
    },
  );
  for (final dark in [false, true]) {
    testWidgets('receipt copy and booking link work at 320px ($dark)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'];
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: SingleChildScrollView(
                child: TransactionDetailsContent(
                  model: TransactionDetailsModel(
                    entry('booking_collection', const [
                      FinanceLine('bank', 'Primary bank', 'upi', 50000),
                      FinanceLine('cash', 'Cash in hand', 'cash', 15000),
                    ], booking: true),
                  ),
                  currency: 'INR',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/booking/:id',
            builder: (_, state) =>
                const Scaffold(body: Text('Booking destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp.router(
            routerConfig: router,
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Booking payment'), findsOneWidget);
      expect(find.text('Payment breakdown'), findsOneWidget);
      expect(find.text('Primary bank'), findsOneWidget);
      expect(find.text('Cash in hand'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Copy reference'));
      await tester.tap(find.byTooltip('Copy reference'));
      await tester.pumpAndSettle();
      expect(clipboard, 'UPI-123');
      await tester.ensureVisible(find.text('BK-123'));
      await tester.tap(find.text('BK-123'));
      await tester.pumpAndSettle();
      expect(find.text('Booking destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

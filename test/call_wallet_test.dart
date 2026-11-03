import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/call_wallet/cubit/call_wallet_cubit.dart';
import 'package:eden_booking/modules/call_wallet/repositories/call_wallet_repository.dart';
import 'package:eden_booking/modules/call_wallet/screens/recharge_screen.dart';
import 'package:eden_booking/modules/notifications/models/booking_notification.dart';
import 'package:eden_booking/modules/call_wallet/models/call_wallet_models.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/cashfree_checkout_service.dart';
import 'agent_calls_test.dart' show workspace;
import 'call_wallet_fakes.dart';

void main() {
  test('rupees uses Indian grouping and drops zero paise', () {
    expect(rupees(50000), '₹500');
    expect(rupees(12345678), '₹1,23,456.78');
    expect(rupees(-1000), '-₹10');
    expect(rupees(500), '₹5');
  });

  test('wallet entries describe calls and recharges', () {
    final call = WalletEntry.fromJson({
      'id': '1',
      'kind': 'call_charge',
      'amount_paise': -1000,
      'balance_after_paise': 9000,
      'call_seconds': 75,
      'created_at': '2026-11-02T10:00:00Z',
    });
    expect(call.title, 'Call · 1m 15s');
    final recharge = WalletEntry.fromJson({
      'id': '2',
      'kind': 'recharge',
      'amount_paise': 10000,
      'balance_after_paise': 10000,
      'payment_method': 'upi',
      'created_at': '2026-11-02T10:00:00Z',
    });
    expect(recharge.title, 'Recharge · UPI');
    final added = WalletEntry.fromJson({
      'id': '3',
      'kind': 'adjustment',
      'amount_paise': 50000,
      'balance_after_paise': 60000,
      'payment_method': 'bank_transfer',
      'external_reference': 'RCPT-9',
      'note': 'Paid by bank',
      'created_at': '2026-11-02T10:00:00Z',
    });
    expect(added.title, 'Balance added · Bank transfer');
    expect(added.details, 'RCPT-9 · Paid by bank');
    final fix = WalletEntry.fromJson({
      'id': '4',
      'kind': 'adjustment',
      'amount_paise': -500,
      'balance_after_paise': 59500,
      'created_at': '2026-11-02T10:00:00Z',
    });
    expect(fix.title, 'Balance correction');
    final free = WalletEntry.fromJson({
      'id': '5',
      'kind': 'adjustment',
      'amount_paise': 50000,
      'balance_after_paise': 109500,
      'note': 'Launch offer',
      'created_at': '2026-11-02T10:00:00Z',
    });
    expect(free.title, 'Free credit');
    expect(free.details, 'Launch offer');
  });

  test('wallet reads admin plans, custom limits and the low threshold', () {
    final w = CallWallet.fromJson(walletJson(24000));
    expect(w.plansPaise, [25000, 50000, 75000, 100000]);
    expect(w.customEnabled, isTrue);
    expect(w.low, isTrue);
    expect(w.empty, isFalse);
    expect(w.minutesFor(25000), 50);
    expect(w.customError(100000), contains('at least ₹1,001'));
    expect(w.customError(100100), isNull);
    expect(w.customError(6000000), contains('at most ₹50,000'));
    expect(CallWallet.fromJson(walletJson(30000)).low, isFalse);
    expect(CallWallet.fromJson(walletJson(0)).empty, isTrue);
  });

  test('wallet alerts parse without a booking and open the wallet', () {
    final n = BookingNotification.fromData({
      'event_id': '11111111-1111-4111-8111-111111111111',
      'event_type': 'call_wallet_low',
      'recipient_user_id': 'user-1',
    });
    expect(n, isNotNull);
    expect(n!.callWallet, isTrue);
    expect(n.route, '/profile/agent-calls/wallet');
    expect(n.toData().containsKey('booking_id'), isFalse);
    expect(
      BookingNotification.fromData({
        'event_id': '11111111-1111-4111-8111-111111111111',
        'event_type': 'created',
        'recipient_user_id': 'user-1',
      }),
      isNull,
    );
  });

  test('a paid recharge updates the balance from the server', () async {
    final repo = FakeWalletRepository()
      ..verifyStatuses.addAll(['pending', 'paid']);
    final checkout = FakeCheckout(CheckoutOutcome.completed);
    final cubit = CallWalletCubit(
      await workspace(),
      repo,
      checkout,
      retryDelay: Duration.zero,
    );
    await cubit.load();
    expect(cubit.state.wallet.balancePaise, 0);
    await cubit.recharge(100000);
    expect(checkout.opened, 'booking_test_order');
    expect(repo.verified.length, 2);
    expect(cubit.state.phase, RechargePhase.idle);
    expect(cubit.state.wallet.balancePaise, 100000);
    expect(cubit.state.notice!.success, isTrue);
    expect(cubit.state.notice!.message, contains('₹1,000 was added'));
    await cubit.close();
  });

  test(
    'a closed checkout is verified once and reports not completed',
    () async {
      final repo = FakeWalletRepository()..verifyStatuses.add('pending');
      final cubit = CallWalletCubit(
        await workspace(),
        repo,
        FakeCheckout(CheckoutOutcome.closed),
        retryDelay: Duration.zero,
      );
      await cubit.recharge(100000);
      expect(repo.verified.length, 1);
      expect(cubit.state.notice!.status, RechargeStatus.pending);
      expect(cubit.state.notice!.message, contains('not completed'));
      expect(cubit.state.wallet.balancePaise, 0);
      await cubit.close();
    },
  );

  test('a failed payment and API errors are shown', () async {
    final repo = FakeWalletRepository()..verifyStatuses.add('failed');
    final cubit = CallWalletCubit(
      await workspace(),
      repo,
      FakeCheckout(CheckoutOutcome.closed),
      retryDelay: Duration.zero,
    );
    await cubit.recharge(100000);
    expect(cubit.state.notice!.message, contains('failed'));
    repo.createError = const AppException(
      'Online recharge is not available yet.',
    );
    await cubit.recharge(100000);
    expect(cubit.state.error, 'Online recharge is not available yet.');
    expect(cubit.state.recharging, isFalse);
    await cubit.close();
  });

  test('web checkout return confirms the order', () async {
    final repo = FakeWalletRepository()..verifyStatuses.add('paid');
    final cubit = CallWalletCubit(
      await workspace(),
      repo,
      FakeCheckout(CheckoutOutcome.completed),
      retryDelay: Duration.zero,
    );
    await cubit.confirmReturn('booking_test_order');
    expect(cubit.state.wallet.balancePaise, 100000);
    expect(cubit.state.loading, isFalse);
    await cubit.close();
  });

  test('only owners can recharge', () async {
    final repo = FakeWalletRepository()..verifyStatuses.add('paid');
    final checkout = FakeCheckout(CheckoutOutcome.completed);
    final cubit = CallWalletCubit(
      await workspace(owner: false),
      repo,
      checkout,
    );
    await cubit.recharge(100000);
    expect(checkout.opened, isNull);
    await cubit.close();
  });

  group('Recharge page', () {
    tearDown(() => getIt.reset());
    Future<(FakeWalletRepository, FakeCheckout)> pump(
      WidgetTester tester, {
      bool custom = true,
    }) async {
      final w = await workspace();
      final repo = FakeWalletRepository()
        ..custom = custom
        ..verifyStatuses.add('paid');
      final checkout = FakeCheckout(CheckoutOutcome.completed);
      registerFeatureDependencies(getIt);
      await getIt.unregister<CallWalletRepository>();
      getIt.registerSingleton<CallWalletRepository>(repo);
      await getIt.unregister<PaymentCheckout>();
      getIt.registerSingleton<PaymentCheckout>(checkout);
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (c, _) => MaterialApp.router(
              theme: lightTheme(),
              routerConfig: GoRouter(
                routes: [
                  GoRoute(path: '/', builder: (c, s) => const RechargeScreen()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (repo, checkout);
    }

    testWidgets('pays the chosen plan', (tester) async {
      final (repo, checkout) = await pump(tester);
      expect(tester.takeException(), isNull);
      for (final plan in ['₹250', '₹500', '₹750', '₹1,000']) {
        expect(find.text(plan), findsOneWidget);
      }
      expect(find.text('Pay ₹500'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('recharge-plan-100000')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pay ₹1,000'));
      await tester.tap(find.text('Pay ₹1,000'));
      await tester.pumpAndSettle();
      expect(repo.created, [100000]);
      expect(checkout.opened, 'booking_test_order');
      expect(find.textContaining('was added'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('checks a custom amount before paying', (tester) async {
      final (repo, _) = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('recharge-plan-custom')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recharge-amount')),
        '500',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pay ₹500'));
      await tester.tap(find.text('Pay ₹500'));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least ₹1,001'), findsOneWidget);
      expect(repo.created, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('recharge-amount')),
        '1500',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pay ₹1,500'));
      await tester.tap(find.text('Pay ₹1,500'));
      await tester.pumpAndSettle();
      expect(repo.created, [150000]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('hides the custom amount when the admin turned it off', (
      tester,
    ) async {
      await pump(tester, custom: false);
      expect(find.byKey(const ValueKey('recharge-plan-custom')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

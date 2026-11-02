import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/call_wallet/cubit/call_wallet_cubit.dart';
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
}

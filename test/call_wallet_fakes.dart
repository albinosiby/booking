import 'package:eden_booking/modules/call_wallet/models/call_wallet_models.dart';
import 'package:eden_booking/modules/call_wallet/repositories/call_wallet_repository.dart';
import 'package:eden_booking/utils/services/cashfree_checkout_service.dart';

Map<String, dynamic> walletJson(int balance, {List<Map>? entries}) => {
  'balance_paise': balance,
  'rate_paise_per_minute': 500,
  'minutes_left': balance > 0 ? balance ~/ 500 : 0,
  'recharge': {
    'enabled': true,
    'min_paise': 10000,
    'max_paise': 5000000,
    'presets_paise': [50000, 100000],
  },
  'transactions': entries ?? const [],
  'next_offset': null,
};

class FakeWalletRepository implements CallWalletRepository {
  int balance = 0;
  final verifyStatuses = <String>[];
  final verified = <String>[];
  Object? createError;
  @override
  Future<CallWallet> wallet() async => CallWallet.fromJson(walletJson(balance));
  @override
  Future<WalletPage> transactions({int offset = 0}) async =>
      const WalletPage([], null);
  @override
  Future<RechargeOrder> createOrder(int amountPaise) async {
    if (createError != null) throw createError!;
    return RechargeOrder(
      orderId: 'booking_test_order',
      paymentSessionId: 'session',
      production: false,
      amountPaise: amountPaise,
    );
  }

  @override
  Future<RechargeResult> verify(String orderId) async {
    verified.add(orderId);
    final status = verifyStatuses.length > 1
        ? verifyStatuses.removeAt(0)
        : verifyStatuses.first;
    if (status == 'paid') balance = 100000;
    return RechargeResult.fromJson({
      'order_id': orderId,
      'status': status,
      'amount_paise': 100000,
      'wallet': walletJson(balance),
    });
  }
}

class FakeCheckout implements PaymentCheckout {
  FakeCheckout(this.outcome);
  final CheckoutOutcome outcome;
  String? opened;
  @override
  Future<CheckoutOutcome> pay({
    required String orderId,
    required String paymentSessionId,
    required bool production,
  }) async {
    opened = orderId;
    return outcome;
  }
}

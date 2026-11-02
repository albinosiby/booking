import '../models/call_wallet_models.dart';

abstract interface class CallWalletRepository {
  Future<CallWallet> wallet();
  Future<WalletPage> transactions({int offset = 0});

  /// Creates a Cashfree order through the BookingOS API.
  Future<RechargeOrder> createOrder(int amountPaise);

  /// Asks the API to confirm the order with Cashfree; never trusts the SDK.
  Future<RechargeResult> verify(String orderId);
}

import '../../../utils/services/rest_api_service.dart';
import '../models/call_wallet_models.dart';
import 'call_wallet_repository.dart';

class RestCallWalletRepository implements CallWalletRepository {
  RestCallWalletRepository(this.api);
  final RestApiService api;
  Map<String, dynamic> _map(Object? data) =>
      Map<String, dynamic>.from(data as Map);

  // Balances are always read fresh: a recharge or call changes them at any time.
  @override
  Future<CallWallet> wallet() async =>
      CallWallet.fromJson(_map(await api.request('/call-wallet')));
  @override
  Future<WalletPage> transactions({int offset = 0}) async =>
      WalletPage.fromJson(
        _map(
          await api.request(
            Uri(
              path: '/call-wallet/transactions',
              queryParameters: {'offset': '$offset'},
            ).toString(),
          ),
        ),
      );
  @override
  Future<RechargeOrder> createOrder(int amountPaise) async =>
      RechargeOrder.fromJson(
        _map(
          await api.request(
            '/call-wallet/orders',
            method: 'POST',
            data: {'amount_paise': amountPaise},
          ),
        ),
      );
  @override
  Future<RechargeResult> verify(String orderId) async =>
      RechargeResult.fromJson(
        _map(
          await api.request(
            '/call-wallet/orders/${Uri.encodeComponent(orderId)}/verify',
            method: 'POST',
          ),
        ),
      );
}

import '../../accounts/models/accounts_models.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/staff_cash_models.dart';
import 'staff_cash_repository.dart';

class RestStaffCashRepository implements IStaffCashRepository {
  RestStaffCashRepository(this.api);
  final RestApiService api;
  @override
  Stream<void> get changes => api.readUpdates
      .where(
        (key) =>
            key == '*' ||
            key.startsWith('/staff-cash') ||
            key.startsWith('/accounts') ||
            key.startsWith('/bookings') ||
            key.startsWith('/admissions'),
      )
      .map((_) {});
  // Cash balances must be fresh: no stale-while-revalidate for the amount owed.
  @override
  Future<StaffCashDay> me({
    String? date,
    int cursor = 0,
    int settlementCursor = 0,
  }) async => StaffCashDay.fromJson(
    financeMap(
      await api.request(
        Uri(
          path: '/staff-cash/me',
          queryParameters: {
            'date': ?date,
            if (cursor != 0) 'cursor': '$cursor',
            if (settlementCursor != 0) 'settlement_cursor': '$settlementCursor',
          },
        ).toString(),
      ),
    ),
  );
  @override
  Future<List<StaffCashMember>> overview() async => [
    for (final s
        in financeMap(await api.request('/staff-cash/overview'))['staff']
            as List)
      StaffCashMember.fromJson(financeMap(s)),
  ];
  @override
  Future<List<StaffCashSettlement>> history(String from, String until) async =>
      [
        for (final s
            in financeMap(
                  await api.request(
                    Uri(
                      path: '/staff-cash/history',
                      queryParameters: {'from': from, 'until': until},
                    ).toString(),
                  ),
                )['items']
                as List)
          StaffCashSettlement.fromJson(financeMap(s)),
      ];
  @override
  Future<int> settle(
    String membershipId,
    StaffCashSettleRequest request,
  ) async {
    final r = financeMap(
      await api.request(
        '/staff-cash/$membershipId/settle',
        method: 'POST',
        data: request.toJson(),
      ),
    );
    api.invalidateReads();
    return (r['balance_after_minor'] as num).toInt();
  }
}

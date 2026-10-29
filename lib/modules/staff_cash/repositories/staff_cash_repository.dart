import '../models/staff_cash_models.dart';

abstract interface class IStaffCashRepository {
  Stream<void> get changes;
  Future<StaffCashDay> me({
    String? date,
    int cursor = 0,
    int settlementCursor = 0,
  });
  Future<List<StaffCashMember>> overview();
  Future<List<StaffCashSettlement>> history(String from, String until);
  Future<int> settle(String membershipId, StaffCashSettleRequest request);
}

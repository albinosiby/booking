import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/staff_cash/cubit/staff_cash_cubits.dart';
import 'package:eden_booking/modules/staff_cash/models/staff_cash_models.dart';
import 'package:eden_booking/modules/staff_cash/repositories/staff_cash_repository.dart';
import 'package:eden_booking/modules/staff_cash/widgets/staff_cash_widgets.dart';

class FakeStaffCash implements IStaffCashRepository {
  List<StaffCashMember> staff = const [
    StaffCashMember(
      id: 's1',
      name: 'Asha',
      spaces: ['Pool'],
      holdingMinor: 18000,
    ),
    StaffCashMember(
      id: 's2',
      name: 'Ravi',
      spaces: ['Pool'],
      holdingMinor: -3000,
    ),
  ];
  StaffCashSettleRequest? last;
  bool fail = false;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<StaffCashDay> me({
    String? date,
    int cursor = 0,
    int settlementCursor = 0,
  }) => throw UnimplementedError();
  @override
  Future<List<StaffCashMember>> overview() async => staff;
  @override
  Future<List<StaffCashSettlement>> history(String from, String until) async =>
      const [];
  @override
  Future<int> settle(String id, StaffCashSettleRequest r) async {
    if (fail) throw StateError('stale');
    last = r;
    final m = staff.firstWhere((s) => s.id == id);
    return m.holdingMinor +
        (r.direction == 'collect' ? -r.amountMinor : r.amountMinor);
  }
}

void main() {
  test('partial collect leaves the remainder visible to the owner', () async {
    final repo = FakeStaffCash();
    final cubit = OwnerStaffCashCubit(repo);
    await cubit.load();
    final after = await cubit.settle(cubit.state.staff.first, 8000);
    expect(after, 10000);
    expect(repo.last?.direction, 'collect');
    expect(repo.last?.expectedBalanceMinor, 18000);
    expect(cubit.state.staff.first.holdingMinor, 10000);
    await cubit.close();
  });

  test('negative balance settles as give', () async {
    final repo = FakeStaffCash();
    final cubit = OwnerStaffCashCubit(repo);
    await cubit.load();
    final after = await cubit.settle(cubit.state.staff.last, 1000);
    expect(repo.last?.direction, 'give');
    expect(after, -2000);
    await cubit.close();
  });

  test('failed settle keeps balance and reports an error', () async {
    final repo = FakeStaffCash()..fail = true;
    final cubit = OwnerStaffCashCubit(repo);
    await cubit.load();
    expect(await cubit.settle(cubit.state.staff.first, 100), isNull);
    expect(cubit.state.error, isNotNull);
    await cubit.close();
  });

  test('remaining text covers hand over, owed and settled', () {
    expect(staffCashRemaining(0, 'INR'), 'Fully settled');
    expect(staffCashRemaining(5000, 'INR'), contains('hand over'));
    expect(staffCashRemaining(-5000, 'INR'), contains('owed'));
  });
}

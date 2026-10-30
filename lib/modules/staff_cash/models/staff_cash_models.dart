import 'package:equatable/equatable.dart';
import '../../accounts/models/accounts_models.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

class StaffCashHandoverInput {
  const StaffCashHandoverInput(this.amountMinor, this.note);
  final int amountMinor;
  final String note;
}

class StaffCashSettlement extends Equatable {
  const StaffCashSettlement({
    required this.id,
    required this.staffName,
    required this.direction,
    required this.amountMinor,
    required this.balanceAfterMinor,
    required this.note,
    required this.settledAt,
  });
  factory StaffCashSettlement.fromJson(Map<String, dynamic> j) =>
      StaffCashSettlement(
        id: j['id'] as String,
        staffName: (j['staff_name'] ?? '') as String,
        direction: j['direction'] as String,
        amountMinor: _int(j['amount_minor']),
        balanceAfterMinor: _int(j['balance_after_minor']),
        note: (j['note'] ?? '') as String,
        settledAt: DateTime.parse(j['settled_at'] as String).toLocal(),
      );
  final String id, staffName, direction, note;
  final int amountMinor, balanceAfterMinor;
  final DateTime settledAt;
  bool get collected => direction == 'collect';
  @override
  List<Object?> get props => [id, direction, amountMinor, balanceAfterMinor];
}

class StaffCashTransaction extends Equatable {
  const StaffCashTransaction({
    required this.id,
    required this.kind,
    required this.reason,
    required this.space,
    required this.staffName,
    required this.mine,
    required this.time,
    required this.netMinor,
    required this.cashMinor,
    this.customer = '',
    this.reference = '',
    this.methods = const [],
  });
  factory StaffCashTransaction.fromJson(Map<String, dynamic> j) {
    final lines = ((j['lines'] ?? const []) as List)
        .map((l) => financeMap(l))
        .toList();
    return StaffCashTransaction(
      id: j['id'] as String,
      kind: j['kind'] as String,
      reason: (j['reason'] ?? '') as String,
      space: (j['space_name'] ?? j['business_name'] ?? '') as String,
      staffName: (j['staff_name'] ?? '') as String,
      mine: j['mine'] == true,
      time: financeStamp((j['local_time'] ?? '') as String),
      netMinor: lines.fold(0, (a, l) => a + _int(l['amount_minor'])),
      customer: (j['customer_name'] ?? '') as String,
      reference: (j['reference'] ?? '') as String,
      methods: List.unmodifiable(
        lines.map((l) => l['method'] as String).toSet(),
      ),
      cashMinor: lines
          .where((l) => l['is_cash'] == true)
          .fold(0, (a, l) => a + _int(l['amount_minor'])),
    );
  }
  final String id, kind, reason, space, staffName, time;
  final String customer, reference;
  final List<String> methods;
  final bool mine;
  final int netMinor, cashMinor;
  @override
  List<Object?> get props => [
    id,
    kind,
    reason,
    space,
    staffName,
    mine,
    time,
    netMinor,
    cashMinor,
    customer,
    reference,
    methods,
  ];
}

class StaffCashDay extends Equatable {
  const StaffCashDay({
    required this.date,
    required this.collectedMinor,
    required this.refundedMinor,
    required this.expensesMinor,
    required this.cashMinor,
    required this.upiMinor,
    required this.cardMinor,
    required this.bankMinor,
    required this.holdingMinor,
    required this.transactions,
    required this.settlements,
    required this.today,
    this.handedOverMinor = 0,
    this.receivedFromOwnerMinor = 0,
    this.nextCursor,
    this.nextSettlementCursor,
    this.bankTransferMinor = 0,
  });
  factory StaffCashDay.fromJson(Map<String, dynamic> j) {
    final m = financeMap(j['by_method']);
    return StaffCashDay(
      date: j['date'] as String,
      today: j['today'] as String,
      handedOverMinor: (j['handed_over_minor'] as num).toInt(),
      receivedFromOwnerMinor: (j['received_from_owner_minor'] as num).toInt(),
      bankTransferMinor: _int(m['bank_transfer']),
      nextCursor: (j['next_cursor'] as num?)?.toInt(),
      nextSettlementCursor: (j['next_settlement_cursor'] as num?)?.toInt(),
      collectedMinor: _int(j['collected_minor']),
      refundedMinor: _int(j['refunded_minor']),
      expensesMinor: _int(j['expenses_minor']),
      cashMinor: _int(m['cash']),
      upiMinor: _int(m['upi']),
      cardMinor: _int(m['card']),
      bankMinor: _int(j['bank_minor']),
      holdingMinor: _int(j['cash_holding_minor']),
      transactions: [
        for (final t in j['transactions'] as List)
          StaffCashTransaction.fromJson(financeMap(t)),
      ],
      settlements: [
        for (final s in j['settlements'] as List)
          StaffCashSettlement.fromJson(financeMap(s)),
      ],
    );
  }
  final String date, today;
  final int handedOverMinor, receivedFromOwnerMinor, bankTransferMinor;
  final int? nextCursor, nextSettlementCursor;
  final int collectedMinor,
      refundedMinor,
      expensesMinor,
      cashMinor,
      upiMinor,
      cardMinor,
      bankMinor,
      holdingMinor;
  final List<StaffCashTransaction> transactions;
  final List<StaffCashSettlement> settlements;

  StaffCashDay withHistory({
    required List<StaffCashTransaction> transactions,
    required List<StaffCashSettlement> settlements,
    required int? nextCursor,
    required int? nextSettlementCursor,
  }) => StaffCashDay(
    date: date,
    today: today,
    collectedMinor: collectedMinor,
    refundedMinor: refundedMinor,
    expensesMinor: expensesMinor,
    cashMinor: cashMinor,
    upiMinor: upiMinor,
    cardMinor: cardMinor,
    bankMinor: bankMinor,
    holdingMinor: holdingMinor,
    handedOverMinor: handedOverMinor,
    receivedFromOwnerMinor: receivedFromOwnerMinor,
    bankTransferMinor: bankTransferMinor,
    transactions: List.unmodifiable(transactions),
    settlements: List.unmodifiable(settlements),
    nextCursor: nextCursor,
    nextSettlementCursor: nextSettlementCursor,
  );
  @override
  List<Object?> get props => [
    date,
    today,
    collectedMinor,
    refundedMinor,
    expensesMinor,
    cashMinor,
    upiMinor,
    cardMinor,
    bankMinor,
    handedOverMinor,
    receivedFromOwnerMinor,
    bankTransferMinor,
    nextCursor,
    nextSettlementCursor,
    holdingMinor,
    transactions,
    settlements,
  ];
}

class StaffCashMember extends Equatable {
  const StaffCashMember({
    required this.id,
    required this.name,
    required this.spaces,
    required this.holdingMinor,
  });
  factory StaffCashMember.fromJson(Map<String, dynamic> j) => StaffCashMember(
    id: j['membership_id'] as String,
    name: j['name'] as String,
    spaces: [for (final s in j['spaces'] as List) '$s'],
    holdingMinor: _int(j['holding_minor']),
  );
  final String id, name;
  final List<String> spaces;
  final int holdingMinor;
  @override
  List<Object?> get props => [id, holdingMinor, spaces];
}

/// Result of an owner settlement; [afterMinor] is what remains to collect (or give).
class StaffCashSettleRequest {
  const StaffCashSettleRequest({
    required this.commandKey,
    required this.direction,
    required this.amountMinor,
    required this.expectedBalanceMinor,
    this.note = '',
  });
  final String commandKey, direction, note;
  final int amountMinor, expectedBalanceMinor;
  Map<String, Object?> toJson() => {
    'command_key': commandKey,
    'direction': direction,
    'amount_minor': amountMinor,
    'expected_balance_minor': expectedBalanceMinor,
    'note': note,
  };
}

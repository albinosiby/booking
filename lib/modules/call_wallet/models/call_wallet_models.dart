import 'package:equatable/equatable.dart';

/// Formats whole paise as rupees, e.g. 123450 → "₹1,234.50", 50000 → "₹500".
String rupees(int paise) {
  final negative = paise < 0;
  final abs = paise.abs();
  final whole = (abs ~/ 100).toString();
  final fraction = abs % 100;
  // Indian grouping: last three digits, then pairs.
  var grouped = whole;
  if (whole.length > 3) {
    final head = whole.substring(0, whole.length - 3);
    final pairs = <String>[];
    for (var end = head.length; end > 0; end -= 2) {
      pairs.insert(0, head.substring(end - 2 < 0 ? 0 : end - 2, end));
    }
    grouped = '${pairs.join(',')},${whole.substring(whole.length - 3)}';
  }
  final cents = fraction == 0 ? '' : '.${fraction.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}₹$grouped$cents';
}

enum WalletEntryKind {
  recharge('Recharge'),
  callCharge('Call charge'),
  adjustment('Adjustment'),
  refund('Refund');

  const WalletEntryKind(this.label);
  final String label;
  static WalletEntryKind parse(Object? value) => switch (value) {
    'recharge' => recharge,
    'call_charge' => callCharge,
    'refund' => refund,
    _ => adjustment,
  };
}

class WalletEntry extends Equatable {
  const WalletEntry({
    required this.id,
    required this.kind,
    required this.amountPaise,
    required this.balanceAfterPaise,
    required this.createdAt,
    this.callSeconds,
    this.ratePaisePerMinute,
    this.paymentMethod = '',
    this.externalReference = '',
    this.note = '',
  });
  factory WalletEntry.fromJson(Map<String, dynamic> j) => WalletEntry(
    id: '${j['id']}',
    kind: WalletEntryKind.parse(j['kind']),
    amountPaise: (j['amount_paise'] as num).toInt(),
    balanceAfterPaise: (j['balance_after_paise'] as num).toInt(),
    callSeconds: (j['call_seconds'] as num?)?.toInt(),
    ratePaisePerMinute: (j['rate_paise_per_minute'] as num?)?.toInt(),
    paymentMethod: '${j['payment_method'] ?? ''}',
    externalReference: '${j['external_reference'] ?? ''}',
    note: '${j['note'] ?? ''}',
    createdAt: DateTime.parse('${j['created_at']}').toLocal(),
  );
  final String id, paymentMethod, externalReference, note;
  final WalletEntryKind kind;
  final int amountPaise, balanceAfterPaise;
  final int? callSeconds, ratePaisePerMinute;
  final DateTime createdAt;

  String get title => switch (kind) {
    WalletEntryKind.callCharge when callSeconds != null =>
      'Call · ${callDuration(callSeconds!)}',
    WalletEntryKind.recharge when paymentMethod.isNotEmpty =>
      'Recharge · ${_method(paymentMethod)}',
    WalletEntryKind.adjustment when amountPaise >= 0 =>
      paymentMethod.isEmpty
          ? 'Free credit'
          : 'Balance added · ${_method(paymentMethod)}',
    WalletEntryKind.adjustment => 'Balance correction',
    _ => kind.label,
  };

  /// Receipt number and the support note, when the balance was changed by hand.
  String get details =>
      [externalReference, note].where((s) => s.isNotEmpty).join(' · ');

  static String _method(String m) => switch (m) {
    'upi' => 'UPI',
    'bank_transfer' => 'Bank transfer',
    'cash' => 'Cash',
    'cheque' => 'Cheque',
    'other' => 'Other',
    _ => m.replaceAll('_', ' ').toUpperCase(),
  };

  @override
  List<Object?> get props => [id, amountPaise, balanceAfterPaise];
}

String callDuration(int seconds) {
  final m = seconds ~/ 60, s = seconds % 60;
  return m == 0 ? '${s}s' : (s == 0 ? '${m}m' : '${m}m ${s}s');
}

class CallWallet extends Equatable {
  const CallWallet({
    this.balancePaise = 0,
    this.ratePaisePerMinute = 0,
    this.rateSet = false,
    this.minutesLeft = 0,
    this.lowBalancePaise = 0,
    this.rechargeEnabled = false,
    this.plansPaise = const [],
    this.customEnabled = false,
    this.customMinPaise = 10000,
    this.customMaxPaise = 5000000,
    this.entries = const [],
    this.nextOffset,
  });
  factory CallWallet.fromJson(Map<String, dynamic> j) {
    final recharge = Map<String, dynamic>.from(j['recharge'] as Map? ?? {});
    int n(Object? v, int fallback) => (v as num? ?? fallback).toInt();
    return CallWallet(
      balancePaise: n(j['balance_paise'], 0),
      ratePaisePerMinute: n(j['rate_paise_per_minute'], 0),
      rateSet: j['rate_set'] != false,
      minutesLeft: n(j['minutes_left'], 0),
      lowBalancePaise: n(j['low_balance_paise'], 0),
      rechargeEnabled: recharge['enabled'] == true,
      plansPaise: [
        for (final p
            in recharge['plans_paise'] as List? ??
                recharge['presets_paise'] as List? ??
                const [])
          (p as num).toInt(),
      ],
      customEnabled: recharge['custom_enabled'] == true,
      customMinPaise: n(recharge['custom_min_paise'], 10000),
      customMaxPaise: n(recharge['custom_max_paise'], 5000000),
      entries: [
        for (final e in j['transactions'] as List? ?? const [])
          WalletEntry.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      nextOffset: (j['next_offset'] as num?)?.toInt(),
    );
  }
  final int balancePaise, ratePaisePerMinute, minutesLeft, lowBalancePaise;
  final bool rateSet, rechargeEnabled, customEnabled;

  /// Plans the admin set for this client, smallest first.
  final List<int> plansPaise;

  /// Custom amounts are whole rupees from [customMinPaise] to [customMaxPaise].
  final int customMinPaise, customMaxPaise;
  final List<WalletEntry> entries;
  final int? nextOffset;

  bool get empty => balancePaise <= 0;
  bool get low => empty || balancePaise < lowBalancePaise;

  /// Roughly how many minutes [paise] buys at this client's rate.
  int minutesFor(int paise) =>
      ratePaisePerMinute > 0 ? paise ~/ ratePaisePerMinute : 0;

  /// Why a custom amount is refused, or null when the server will accept it.
  String? customError(int? paise) {
    if (paise == null) return 'Enter an amount in rupees.';
    if (paise < customMinPaise) {
      return 'Enter at least ${rupees(customMinPaise)}, or choose a plan.';
    }
    if (paise > customMaxPaise) {
      return 'Recharge at most ${rupees(customMaxPaise)}.';
    }
    return null;
  }

  CallWallet copyWith({
    List<WalletEntry>? entries,
    int? Function()? nextOffset,
  }) => CallWallet(
    balancePaise: balancePaise,
    ratePaisePerMinute: ratePaisePerMinute,
    rateSet: rateSet,
    minutesLeft: minutesLeft,
    lowBalancePaise: lowBalancePaise,
    rechargeEnabled: rechargeEnabled,
    plansPaise: plansPaise,
    customEnabled: customEnabled,
    customMinPaise: customMinPaise,
    customMaxPaise: customMaxPaise,
    entries: entries ?? this.entries,
    nextOffset: nextOffset != null ? nextOffset() : this.nextOffset,
  );

  @override
  List<Object?> get props => [
    balancePaise,
    ratePaisePerMinute,
    rateSet,
    minutesLeft,
    lowBalancePaise,
    rechargeEnabled,
    plansPaise,
    customEnabled,
    customMinPaise,
    customMaxPaise,
    entries,
    nextOffset,
  ];
}

class WalletPage {
  const WalletPage(this.entries, this.nextOffset);
  factory WalletPage.fromJson(Map<String, dynamic> j) => WalletPage([
    for (final e in j['items'] as List? ?? const [])
      WalletEntry.fromJson(Map<String, dynamic>.from(e as Map)),
  ], (j['next_offset'] as num?)?.toInt());
  final List<WalletEntry> entries;
  final int? nextOffset;
}

class RechargeOrder extends Equatable {
  const RechargeOrder({
    required this.orderId,
    required this.paymentSessionId,
    required this.production,
    required this.amountPaise,
  });
  factory RechargeOrder.fromJson(Map<String, dynamic> j) => RechargeOrder(
    orderId: '${j['order_id']}',
    paymentSessionId: '${j['payment_session_id']}',
    production: j['environment'] == 'production',
    amountPaise: (j['amount_paise'] as num).toInt(),
  );
  final String orderId, paymentSessionId;
  final bool production;
  final int amountPaise;
  @override
  List<Object?> get props => [orderId];
}

/// Server-confirmed recharge state. `created`/`pending` mean not yet settled.
enum RechargeStatus {
  paid,
  pending,
  failed,
  cancelled,
  expired;

  static RechargeStatus parse(Object? value) => switch (value) {
    'paid' => paid,
    'failed' => failed,
    'cancelled' => cancelled,
    'expired' => expired,
    _ => pending,
  };
}

class RechargeResult extends Equatable {
  const RechargeResult({
    required this.orderId,
    required this.status,
    required this.amountPaise,
    required this.wallet,
  });
  factory RechargeResult.fromJson(Map<String, dynamic> j) => RechargeResult(
    orderId: '${j['order_id']}',
    status: RechargeStatus.parse(j['status']),
    amountPaise: (j['amount_paise'] as num).toInt(),
    wallet: CallWallet.fromJson(Map<String, dynamic>.from(j['wallet'] as Map)),
  );
  final String orderId;
  final RechargeStatus status;
  final int amountPaise;
  final CallWallet wallet;
  @override
  List<Object?> get props => [orderId, status, wallet];
}

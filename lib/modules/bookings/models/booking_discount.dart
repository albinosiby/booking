import 'package:equatable/equatable.dart';

class BookingDiscount extends Equatable {
  const BookingDiscount({
    this.type = 'amount',
    this.value = '',
    this.reason = '',
  });
  final String type, value, reason;
  int? get units {
    if (value.trim().length > 13) return null;
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value.trim())) return null;
    final parts = value.trim().split('.');
    return int.parse(parts[0]) * 100 +
        int.parse(parts.length == 1 ? '00' : parts[1].padRight(2, '0'));
  }

  String? validate(int? subtotal) {
    final n = units;
    if (n == null || n < 0 || n > 100000000) return 'Enter a valid discount.';
    if (type == 'percent' && n > 10000) return 'Discount cannot exceed 100%.';
    if (type == 'amount' && subtotal != null && n > subtotal) {
      return 'Discount cannot exceed the subtotal.';
    }
    if (reason.trim().length > 200) {
      return 'Keep the reason within 200 characters.';
    }
    return null;
  }

  int reduction(int subtotal) => type == 'percent'
      ? (subtotal * (units ?? 0) / 10000).round()
      : units ?? 0;
  Map<String, dynamic> toJson() => {
    'type': type,
    'value': units,
    'reason': reason.trim(),
  };
  factory BookingDiscount.fromJson(Map<String, dynamic> j) => BookingDiscount(
    type: j['type'],
    value: ((j['value'] as num) / 100).toStringAsFixed(2),
    reason: j['reason'] ?? '',
  );
  BookingDiscount copyWith({String? type, String? value, String? reason}) =>
      BookingDiscount(
        type: type ?? this.type,
        value: value ?? this.value,
        reason: reason ?? this.reason,
      );
  @override
  List<Object?> get props => [type, value, reason];
}

import 'package:equatable/equatable.dart';
import 'booking_models.dart';

/// Shared presentation for a booking or an outstanding-payment result.
class CompactBookingModel extends Equatable {
  const CompactBookingModel({
    required this.id,
    required this.reference,
    required this.customer,
    required this.business,
    required this.space,
    required this.start,
    required this.status,
    required this.balance,
    this.phone = '',
    this.end,
    this.option,
    this.total,
    this.refund = 0,
    this.admissionId,
    this.admissionAttendance,
  });
  factory CompactBookingModel.booking(BookingRecord b) => CompactBookingModel(
    phone: b.customer.phone,
    admissionId: b.admissionId,
    admissionAttendance: b.admissionAttendance,
    id: b.id,
    reference: b.reference,
    customer: b.customer.name,
    business: b.businessName,
    space: b.spaceName,
    option: b.optionName,
    start: b.localStart,
    end: b.localEnd,
    status: b.status,
    balance: b.balance,
    total: b.total,
    refund: b.refundDue,
  );
  factory CompactBookingModel.outstanding(BookingOutstanding b) =>
      CompactBookingModel(
        id: b.id,
        reference: b.reference,
        customer: b.customer,
        phone: b.phone,
        end: b.localEnd,
        total: b.total,
        option: b.option,
        business: b.business,
        space: b.space,
        start: b.localStart,
        status: b.status,
        balance: b.balance,
        refund: b.refund,
      );
  final String id, reference, customer, business, space, start, status, phone;
  final String? end, option, admissionId, admissionAttendance;
  final int balance, refund;
  final int? total;
  bool get collectible => balance > 0 && status != 'cancelled';
  @override
  List<Object?> get props => [
    admissionId,
    admissionAttendance,
    id,
    reference,
    customer,
    phone,
    business,
    space,
    start,
    end,
    option,
    status,
    balance,
    refund,
    total,
  ];
}

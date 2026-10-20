import 'package:equatable/equatable.dart';
import '../../bookings/models/booking_models.dart';

class CustomerSummary extends Equatable {
  const CustomerSummary({
    required this.id,
    required this.name,
    required this.phone,
    this.recordCount = 1,
  });
  final String id, name, phone;
  final int recordCount;
  factory CustomerSummary.fromJson(Map<String, dynamic> j) => CustomerSummary(
    id: j['id'],
    name: j['name'],
    phone: j['phone'],
    recordCount: j['record_count'] ?? 1,
  );
  @override
  List<Object?> get props => [id, name, phone, recordCount];
}

class CustomerPage {
  CustomerPage(Iterable<CustomerSummary> items, this.next)
    : items = List.unmodifiable(items);
  final List<CustomerSummary> items;
  final String? next;
}

class CustomerHistoryPage {
  CustomerHistoryPage({
    required this.customer,
    required this.currency,
    required Iterable<BookingRecord> items,
    this.next,
  }) : items = List.unmodifiable(items);
  final CustomerSummary customer;
  final String currency;
  final List<BookingRecord> items;
  final String? next;
}

class CustomerListModel extends Equatable {
  CustomerListModel({
    this.query = '',
    Iterable<CustomerSummary> items = const [],
    this.next,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  }) : items = List.unmodifiable(items);
  final String query;
  final List<CustomerSummary> items;
  final String? next, error;
  final bool loading, loadingMore;
  @override
  List<Object?> get props => [query, items, next, loading, loadingMore, error];
}

class CustomerDetailModel extends Equatable {
  CustomerDetailModel({
    this.customer,
    this.currency = 'INR',
    Iterable<BookingRecord> bookings = const [],
    this.next,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  }) : bookings = List.unmodifiable(bookings);
  final CustomerSummary? customer;
  final String currency;
  final List<BookingRecord> bookings;
  final String? next, error;
  final bool loading, loadingMore;
  @override
  List<Object?> get props => [
    customer,
    currency,
    bookings,
    next,
    loading,
    loadingMore,
    error,
  ];
}

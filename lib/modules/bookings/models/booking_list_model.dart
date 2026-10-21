import 'package:equatable/equatable.dart';
import 'booking_models.dart';

enum BookingListMode { bookings, calendar, payments }

class BookingSpaceFilter extends Equatable {
  const BookingSpaceFilter(this.businessId, this.spaceId, this.label);
  final String businessId, spaceId, label;
  @override
  List<Object?> get props => [businessId, spaceId, label];
}

class BookingListModel extends Equatable {
  BookingListModel({
    this.catalog = const BookingCatalog(),
    Map<String, int> dateCounts = const {},
    this.countsLoading = false,
    this.countsError,
    Iterable<BookingRecord> bookings = const [],
    Iterable<CollectionEntry> collections = const [],
    Iterable<CollectionTotal> totals = const [],
    this.loading = true,
    bool? hasLoaded,
    this.loadingMore = false,
    this.businessId,
    this.spaceId,
    this.dueView = false,
    Iterable<BookingOutstanding> outstanding = const [],
    this.balanceTotal = 0,
    this.refundTotal = 0,
    this.date,
    this.status,
    this.query = '',
    this.next,
    this.error,
  }) : hasLoaded = hasLoaded ?? !loading,
       dateCounts = Map.unmodifiable(dateCounts),
       outstanding = List.unmodifiable(outstanding),
       bookings = List.unmodifiable(bookings),
       collections = List.unmodifiable(collections),
       totals = List.unmodifiable(totals);
  final BookingCatalog catalog;
  List<BookingSpaceFilter> get spaceFilters {
    final counts = <String, int>{};
    for (final business in catalog.filters) {
      for (final space in business.spaces) {
        counts.update(space.name, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return List.unmodifiable([
      for (final business in catalog.filters)
        for (final space in business.spaces)
          BookingSpaceFilter(
            business.id,
            space.id,
            counts[space.name]! > 1
                ? '${business.name} · ${space.name}'
                : space.name,
          ),
    ]);
  }

  final Map<String, int> dateCounts;
  final bool countsLoading;
  final String? countsError;
  final List<BookingRecord> bookings;
  final List<CollectionEntry> collections;
  final List<CollectionTotal> totals;
  final bool loading, loadingMore, hasLoaded;
  final String? businessId, spaceId, date, status, error;
  final bool dueView;
  final List<BookingOutstanding> outstanding;
  final int balanceTotal, refundTotal;
  final String query;
  final int? next;
  BookingListModel copyWith({
    BookingCatalog? catalog,
    Map<String, int>? dateCounts,
    bool? countsLoading,
    String? countsError,
    Iterable<BookingRecord>? bookings,
    Iterable<CollectionEntry>? collections,
    Iterable<CollectionTotal>? totals,
    bool? loading,
    bool? loadingMore,
    bool? hasLoaded,
    String? businessId,
    String? spaceId,
    bool clearSpace = false,
    bool? dueView,
    List<BookingOutstanding>? outstanding,
    int? balanceTotal,
    int? refundTotal,
    bool clearBusiness = false,
    String? date,
    bool clearDate = false,
    String? status,
    bool clearStatus = false,
    String? query,
    int? next,
    bool clearNext = false,
    String? error,
  }) => BookingListModel(
    catalog: catalog ?? this.catalog,
    dateCounts: dateCounts ?? this.dateCounts,
    countsLoading: countsLoading ?? this.countsLoading,
    countsError: countsError,
    bookings: bookings ?? this.bookings,
    collections: collections ?? this.collections,
    totals: totals ?? this.totals,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    businessId: clearBusiness ? null : businessId ?? this.businessId,
    spaceId: clearSpace ? null : spaceId ?? this.spaceId,
    dueView: dueView ?? this.dueView,
    outstanding: outstanding ?? this.outstanding,
    balanceTotal: balanceTotal ?? this.balanceTotal,
    refundTotal: refundTotal ?? this.refundTotal,
    date: clearDate ? null : date ?? this.date,
    status: clearStatus ? null : status ?? this.status,
    query: query ?? this.query,
    next: clearNext ? null : next ?? this.next,
    error: error,
  );
  @override
  List<Object?> get props => [
    catalog,
    dateCounts,
    countsLoading,
    countsError,
    bookings,
    collections,
    totals,
    loading,
    loadingMore,
    hasLoaded,
    businessId,
    spaceId,
    dueView,
    outstanding,
    balanceTotal,
    refundTotal,
    date,
    status,
    query,
    next,
    error,
  ];
}

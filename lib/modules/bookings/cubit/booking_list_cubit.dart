import '../../../utils/exceptions/app_exception.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/booking_models.dart';
import '../models/booking_list_model.dart';
import '../repositories/booking_repository.dart';
import '../../workspace/repositories/refreshable_reads.dart';
import '../../workspace/cubit/workspace_state.dart' show LoadStatus;
import 'booking_form_cubit.dart';

class BookingListCubit extends Cubit<BookingListModel> {
  BookingListCubit(this.session, this.repository, this.mode)
    : super(
        BookingListModel(
          date: mode == BookingListMode.bookings
              ? null
              : bookingDate(DateTime.now()),
        ),
      ) {
    scope = bookingScope(session);
    subscription = session.snapshots.listen((_) {
      if (bookingScope(session) != scope) {
        scope = bookingScope(session);
        generation++;
        countGeneration++;
        countWindow = null;
        loadedFilter = null;
        emit(
          BookingListModel(
            loading: false,
            date: mode == BookingListMode.calendar
                ? bookingDate(DateTime.now())
                : null,
            error: 'Your account or access changed. Refresh to continue.',
          ),
        );
        if (session.state.status == LoadStatus.ready &&
            session.state.data.organization != null) {
          load();
        }
      }
    });
    changes = repository.changes.listen((_) {
      refreshCounts();
      load();
    });
  }
  final WorkspaceSession session;
  final BookingRepository repository;
  final BookingListMode mode;
  late String scope;
  late StreamSubscription subscription, changes;
  int generation = 0, countGeneration = 0;
  String? loadedFilter;
  String resultKey(BookingListModel s) =>
      '$scope/${s.date}/${s.businessId}/${s.spaceId}/${s.status}/${s.query}/${s.dueView}';
  Future<void> refresh() async {
    await session.load();
    final source = repository;
    if (source is RefreshableReads) {
      (source as RefreshableReads).invalidateReads();
    }
    return load();
  }

  Timer? countTimer;
  (String, String)? countWindow;
  String? countFilter;
  String countScope(BookingListModel s) =>
      '$scope/${s.businessId}/${s.spaceId}/${s.status}/${s.query}';
  void countRange(String from, String until) {
    if (mode != BookingListMode.calendar) return;
    final window = (from, until), filter = countScope(state);
    if (countWindow == window &&
        countFilter == filter &&
        state.countsError == null) {
      return;
    }
    final retainCounts = countWindow == window && countFilter == filter;
    countTimer?.cancel();
    countWindow = window;
    countFilter = filter;
    final g = ++countGeneration, captured = state;
    emit(
      state.copyWith(
        dateCounts: retainCounts ? null : const {},
        countsLoading: true,
      ),
    );
    countTimer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final counts = await repository.dateCounts(
          date: from,
          dateUntil: until,
          businessId: captured.businessId,
          spaceId: captured.spaceId,
          query: captured.query.isEmpty ? null : captured.query,
          status: captured.status,
        );
        if (!isClosed && g == countGeneration && countScope(state) == filter) {
          emit(state.copyWith(dateCounts: counts, countsLoading: false));
        }
      } catch (e) {
        if (!isClosed && g == countGeneration && countScope(state) == filter) {
          emit(
            state.copyWith(countsLoading: false, countsError: bookingError(e)),
          );
        }
      }
    });
  }

  void refreshCounts() {
    final window = countWindow;
    countFilter = null;
    if (window != null) {
      // Trigger a new count request without clearing the displayed counts.
      final retained = state.dateCounts;
      countRange(window.$1, window.$2);
      emit(state.copyWith(dateCounts: retained));
    }
  }

  Future<void> load({bool more = false}) async {
    if (more && (state.loadingMore || state.next == null)) return;
    final g = ++generation, filter = state;
    final retain = more || loadedFilter == resultKey(filter);
    if (!more && mode == BookingListMode.calendar) refreshCounts();
    emit(
      state.copyWith(
        loading: !more,
        hasLoaded: retain && state.hasLoaded,
        loadingMore: more,
        bookings: retain ? null : const [],
        collections: retain ? null : const [],
        outstanding: retain ? null : const [],
        clearNext: !more,
        error: null,
      ),
    );
    try {
      final catalog = await repository.catalog();
      if (mode != BookingListMode.payments && !catalog.canView) {
        throw const AppException(
          'Booking viewing permission is required.',
          code: 'FORBIDDEN',
        );
      }
      if (mode == BookingListMode.payments) {
        if (filter.dueView) {
          final p = await repository.outstanding(
            date: filter.date,
            businessId: filter.businessId,
            cursor: more ? filter.next! : 0,
          );
          if (!isClosed && g == generation) {
            loadedFilter = resultKey(filter);
            emit(
              state.copyWith(
                catalog: catalog,
                outstanding: List.unmodifiable(
                  more ? [...filter.outstanding, ...p.items] : p.items,
                ),
                balanceTotal: p.balance,
                refundTotal: p.refund,
                next: p.next,
                clearNext: p.next == null,
                loading: false,
                hasLoaded: true,
                loadingMore: false,
              ),
            );
          }
          return;
        }
        final p = await repository.collections(
          date: filter.date,
          businessId: filter.businessId,
          cursor: more ? filter.next! : 0,
        );
        if (!isClosed && g == generation) {
          loadedFilter = resultKey(filter);
          emit(
            state.copyWith(
              catalog: catalog,
              collections: more ? [...filter.collections, ...p.items] : p.items,
              totals: p.totals,
              next: p.next,
              clearNext: p.next == null,
              loading: false,
              hasLoaded: true,
              loadingMore: false,
            ),
          );
        }
      } else {
        final p = await repository.list(
          date: filter.date,
          spaceId: filter.spaceId,
          overlap: mode == BookingListMode.calendar,
          businessId: filter.businessId,
          query: filter.query.isEmpty ? null : filter.query,
          status: filter.status,
          cursor: more ? filter.next! : 0,
        );
        if (!isClosed && g == generation) {
          loadedFilter = resultKey(filter);
          emit(
            state.copyWith(
              catalog: catalog,
              bookings: more ? [...filter.bookings, ...p.items] : p.items,
              next: p.next,
              clearNext: p.next == null,
              loading: false,
              hasLoaded: true,
              loadingMore: false,
            ),
          );
        }
      }
    } catch (e) {
      if (!isClosed && g == generation) {
        if (accessFailure(e)) {
          loadedFilter = null;
          emit(BookingListModel(loading: false, error: bookingError(e)));
          return;
        }
        emit(
          state.copyWith(
            loading: false,
            loadingMore: false,
            error: bookingError(e),
          ),
        );
      }
    }
  }

  void business(String? id) {
    emit(
      state.copyWith(
        businessId: id,
        clearBusiness: id == null,
        clearSpace: true,
      ),
    );
    load();
  }

  void filters({
    String? businessId,
    String? spaceId,
    String? status,
    String? query,
    bool updateSearch = false,
  }) {
    emit(
      state.copyWith(
        businessId: businessId,
        clearBusiness: businessId == null,
        spaceId: spaceId,
        clearSpace: spaceId == null,
        status: updateSearch ? status : state.status,
        clearStatus: updateSearch && status == null,
        query: updateSearch ? query ?? '' : state.query,
      ),
    );
    load();
  }

  void dueView(bool value) {
    emit(
      state.copyWith(
        dueView: value,
        clearNext: true,
        clearDate: value,
        date: value ? null : bookingDate(DateTime.now()),
      ),
    );
    load();
  }

  void space(String? id) {
    emit(state.copyWith(spaceId: id, clearSpace: id == null));
    load();
  }

  void date(String? d) {
    emit(state.copyWith(date: d, clearDate: d == null));
    load();
  }

  void status(String? s) {
    emit(state.copyWith(status: s, clearStatus: s == null));
    load();
  }

  void query(String q) {
    emit(state.copyWith(query: q));
  }

  void search() => load();
  @override
  Future<void> close() async {
    generation++;
    countGeneration++;
    countTimer?.cancel();
    await subscription.cancel();
    await changes.cancel();
    return super.close();
  }
}

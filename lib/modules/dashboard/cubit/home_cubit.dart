import '../../accounts/repositories/accounts_repository.dart';
import '../../bookings/repositories/booking_repository.dart';
import '../../../utils/exceptions/app_exception.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/home_screen_model.dart';
import '../repositories/dashboard_repository.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/repositories/refreshable_reads.dart';
import '../../booking_website/repositories/website_image_events.dart';
import '../repositories/home_hero_repository.dart';

class HomeCubit extends Cubit<HomeScreenModel> {
  HomeCubit(
    this.repository, [
    this.bookings,
    this.accounts,
    this.hero,
    this.imageEvents,
  ]) : super(HomeScreenModel.fromSnapshot(repository.current)) {
    _subscription = repository.changes.listen((snapshot) {
      if (isClosed) return;
      final scopeChanged =
          workspaceAccessScope(snapshot.data) !=
          workspaceAccessScope(state.data);
      final refresh = snapshot.data.withLogo(null) != state.data.withLogo(null);
      if (!isClosed) {
        emit(
          scopeChanged
              ? HomeScreenModel.fromSnapshot(snapshot)
              : state.copyWith(snapshot: snapshot),
        );
      }
      if (scopeChanged) {
        _generation++;
        _dueGeneration++;
        _accountGeneration++;
        _heroGeneration++;
        unawaited(loadHero());
      }
      if (refresh) {
        loadBookings();
        loadAccountSetup();
      }
    });
    _bookingSubscription = bookings?.changes.listen((_) {
      loadBookings();
    });
    _accountSubscription = accounts?.changes.listen((_) => loadAccountSetup());
    _imageSubscription = imageEvents?.changes.listen((_) => loadHero());
    loadBookings();
    loadAccountSetup();
    unawaited(loadHero());
  }
  final DashboardRepository repository;
  final BookingRepository? bookings;
  final AccountsRepository? accounts;
  final HomeHeroRepository? hero;
  final WebsiteImageEvents? imageEvents;
  StreamSubscription<void>? _imageSubscription;
  int _heroGeneration = 0;

  Future<void> loadHero() async {
    final source = hero, organization = state.data.organization?.id;
    final g = ++_heroGeneration;
    if (source == null || organization == null) return;
    try {
      final image = await source.load();
      if (!isClosed &&
          g == _heroGeneration &&
          organization == state.data.organization?.id) {
        emit(state.copyWith(heroImage: image, clearHeroImage: image == null));
      }
    } catch (error) {
      if (!isClosed && g == _heroGeneration && accessFailure(error)) {
        emit(state.copyWith(clearHeroImage: true));
      }
      // The bundled background remains available when an optional photo fails.
    }
  }

  StreamSubscription? _accountSubscription;
  int _accountGeneration = 0;

  Future<void> loadAccountSetup() async {
    final g = ++_accountGeneration;
    if (accounts == null ||
        !state.data.isOwner ||
        state.data.organization == null) {
      return;
    }
    final scope = workspaceAccessScope(state.data);
    try {
      final catalog = await accounts!.catalog();
      if (!isClosed &&
          g == _accountGeneration &&
          scope == workspaceAccessScope(state.data)) {
        emit(
          state.copyWith(
            accountConfigured: catalog.accounts.any(
              (a) => a.kind == 'bank' && a.active,
            ),
          ),
        );
      }
    } catch (e) {
      if (!isClosed && g == _accountGeneration && accessFailure(e)) {
        emit(state.copyWith(clearAccountConfigured: true));
      }
      // A failed read is not evidence that setup is missing.
    }
  }

  StreamSubscription? _bookingSubscription;
  int _generation = 0, _dueGeneration = 0;
  late final StreamSubscription<Object?> _subscription;
  Future<void> loadBookings() async {
    await Future.wait([loadDashboard(), loadDue()]);
  }

  Future<void> loadDashboard() async {
    final g = ++_generation;
    if (bookings == null ||
        state.data.organization == null ||
        ![
          'view_bookings',
          'manage_bookings',
          'collect_payments',
          'view_finance',
        ].any(state.data.hasPermission)) {
      return;
    }
    final org = state.data.organization?.id;
    emit(state.copyWith(bookingLoading: true, clearBookingError: true));
    try {
      final data = await bookings!.dashboard();
      if (!isClosed && g == _generation && org == state.data.organization?.id) {
        emit(state.copyWith(dashboard: data, bookingLoading: false));
      }
    } catch (e) {
      if (!isClosed && g == _generation) {
        emit(
          state.copyWith(
            bookingLoading: false,
            clearDashboard: accessFailure(e),
            bookingError: e is AppException
                ? e.message
                : 'Could not load bookings.',
          ),
        );
      }
    }
  }

  Future<void> loadDue({bool more = false}) async {
    final g = ++_dueGeneration;
    if (bookings == null ||
        state.data.organization == null ||
        !['view_finance', 'collect_payments'].any(state.data.hasPermission)) {
      return;
    }
    final cursor = more ? state.dueNext : 0;
    if (cursor == null) return;
    final org = state.data.organization!.id;
    emit(state.copyWith(dueLoading: true, clearDueError: true));
    try {
      final page = await bookings!.outstanding(cursor: cursor);
      if (isClosed ||
          g != _dueGeneration ||
          org != state.data.organization?.id) {
        return;
      }
      emit(
        state.copyWith(
          dueBookings: [
            if (more) ...state.dueBookings,
            ...page.items.where(
              (b) => b.balance > 0 && b.status != 'cancelled',
            ),
          ],
          dueTotal: page.balance,
          dueNext: page.next,
          clearDueNext: page.next == null,
          dueLoading: false,
        ),
      );
    } catch (e) {
      if (!isClosed && g == _dueGeneration) {
        emit(
          state.copyWith(
            dueBookings: accessFailure(e) ? const [] : null,
            clearDueTotal: accessFailure(e),
            clearDueNext: accessFailure(e),
            dueLoading: false,
            dueError: e is AppException
                ? e.message
                : 'Could not load payments to collect.',
          ),
        );
      }
    }
  }

  Future<void> refreshBookings() async {
    await repository.refresh();
    final source = bookings;
    if (source is RefreshableReads) {
      (source as RefreshableReads).invalidateReads();
    }
    await Future.wait([loadBookings(), loadAccountSetup(), loadHero()]);
  }

  Future<void> reload() => refreshBookings();

  @override
  Future<void> close() async {
    _generation++;
    _dueGeneration++;
    _accountGeneration++;
    _heroGeneration++;
    await _accountSubscription?.cancel();
    await _imageSubscription?.cancel();
    await _subscription.cancel();
    await _bookingSubscription?.cancel();
    return super.close();
  }
}

import '../../bookings/models/booking_models.dart';
import '../../workspace/models/workspace_state.dart';

class HomeScreenModel extends WorkspaceState {
  HomeScreenModel.fromSnapshot(
    WorkspaceState snapshot, {
    this.dashboard,
    this.accountConfigured,
    this.bookingLoading = false,
    this.bookingError,
    Iterable<BookingOutstanding> dueBookings = const [],
    this.dueTotal,
    this.dueNext,
    this.dueLoading = false,
    this.dueError,
  }) : dueBookings = List.unmodifiable(dueBookings),
       super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  final BookingDashboard? dashboard;
  final bool? accountConfigured;
  bool get needsAccountSetup => data.isOwner && accountConfigured == false;
  final bool bookingLoading;
  final String? bookingError;
  final List<BookingOutstanding> dueBookings;
  final int? dueTotal, dueNext;
  final bool dueLoading;
  final String? dueError;

  HomeScreenModel copyWith({
    WorkspaceState? snapshot,
    bool? accountConfigured,
    bool clearAccountConfigured = false,
    BookingDashboard? dashboard,
    bool clearDashboard = false,
    bool? bookingLoading,
    String? bookingError,
    bool clearBookingError = false,
    Iterable<BookingOutstanding>? dueBookings,
    int? dueTotal,
    bool clearDueTotal = false,
    int? dueNext,
    bool clearDueNext = false,
    bool? dueLoading,
    String? dueError,
    bool clearDueError = false,
  }) => HomeScreenModel.fromSnapshot(
    snapshot ?? this,
    accountConfigured: clearAccountConfigured
        ? null
        : accountConfigured ?? this.accountConfigured,
    dashboard: clearDashboard ? null : dashboard ?? this.dashboard,
    bookingLoading: bookingLoading ?? this.bookingLoading,
    bookingError: clearBookingError ? null : bookingError ?? this.bookingError,
    dueBookings: dueBookings ?? this.dueBookings,
    dueTotal: clearDueTotal ? null : dueTotal ?? this.dueTotal,
    dueNext: clearDueNext ? null : dueNext ?? this.dueNext,
    dueLoading: dueLoading ?? this.dueLoading,
    dueError: clearDueError ? null : dueError ?? this.dueError,
  );

  @override
  List<Object?> get props => [
    ...super.props,
    dashboard,
    accountConfigured,
    bookingLoading,
    bookingError,
    dueBookings,
    dueTotal,
    dueNext,
    dueLoading,
    dueError,
  ];
}

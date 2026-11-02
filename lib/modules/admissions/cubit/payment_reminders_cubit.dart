import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../bookings/models/booking_models.dart';
import '../models/admission_models.dart';
import '../repositories/admission_repository.dart';
import 'admission_cubit.dart' show admissionError;

class PaymentRemindersState extends Equatable {
  const PaymentRemindersState({
    this.items = const [],
    this.next,
    this.loading = false,
    this.error,
    this.collectingId,
    this.uncertainId,
    this.notice,
  });
  final List<Admission> items;
  final int? next;
  final bool loading;
  final String? error;

  /// The admission whose collection is being sent.
  final String? collectingId;

  /// A collection whose outcome is unknown; retry reuses its command key.
  final String? uncertainId;
  final String? notice;
  PaymentRemindersState copyWith({
    List<Admission>? items,
    int? next,
    bool clearNext = false,
    bool? loading,
    String? error,
    String? collectingId,
    String? uncertainId,
    String? notice,
  }) => PaymentRemindersState(
    items: items ?? this.items,
    next: clearNext ? null : next ?? this.next,
    loading: loading ?? this.loading,
    error: error,
    collectingId: collectingId,
    uncertainId: uncertainId,
    notice: notice,
  );
  @override
  List<Object?> get props => [
    items,
    next,
    loading,
    error,
    collectingId,
    uncertainId,
    notice,
  ];
}

/// One Home reminder group: `due_soon` (next month) or `unpaid` (ended terms).
class PaymentRemindersCubit extends Cubit<PaymentRemindersState> {
  PaymentRemindersCubit(this.repository, this.group)
    : super(const PaymentRemindersState()) {
    subscription = repository.changes.listen((_) => load());
  }
  final MembershipActions repository;
  final String group;
  late final StreamSubscription<void> subscription;
  int generation = 0;
  Future<void> Function()? _pending;
  String key = const Uuid().v4();

  Future<void> load({bool more = false}) async {
    if (isClosed || more && (state.loading || state.next == null)) return;
    final request = ++generation;
    final previous = more ? state.items : <Admission>[];
    emit(
      state.copyWith(
        loading: true,
        collectingId: state.collectingId,
        uncertainId: state.uncertainId,
        notice: state.notice,
      ),
    );
    try {
      final page = await repository.paymentReminders(
        group,
        cursor: more ? state.next! : 0,
      );
      if (isClosed || request != generation) return;
      final items = {
        for (final admission in [...previous, ...page.items])
          admission.id: admission,
      };
      emit(
        state.copyWith(
          items: List.unmodifiable(items.values),
          next: page.next,
          clearNext: page.next == null,
          loading: false,
          collectingId: state.collectingId,
          uncertainId: state.uncertainId,
          notice: state.notice,
        ),
      );
    } catch (error) {
      if (!isClosed && request == generation) {
        emit(
          accessFailure(error)
              ? const PaymentRemindersState(
                  error: 'Access denied. Reopen this page.',
                )
              : state.copyWith(
                  loading: false,
                  error: admissionError(error),
                  uncertainId: state.uncertainId,
                ),
        );
      }
    }
  }

  /// Records [payments] for [admission]; any amount up to its balance.
  Future<void> collect(
    Admission admission,
    List<BookingPaymentDraft> payments,
  ) async {
    // An unconfirmed payment must be retried before a new one is sent.
    if (state.uncertainId != null) return;
    final k = key;
    return _send(
      admission.id,
      () => repository.collectDue(admission, payments, k),
    );
  }

  /// Resends an unknown outcome with the same command key.
  Future<void> retry() async {
    final id = state.uncertainId, action = _pending;
    if (id != null && action != null) await _send(id, action);
  }

  Future<void> _send(String id, Future<void> Function() action) async {
    if (isClosed || state.collectingId != null) return;
    _pending = action;
    emit(state.copyWith(collectingId: id, uncertainId: state.uncertainId));
    try {
      await action();
      if (isClosed) return;
      _pending = null;
      key = const Uuid().v4();
      emit(state.copyWith(notice: 'Payment recorded.'));
      await load();
    } catch (e) {
      if (isClosed) return;
      final definitive =
          e is AppException &&
          [
            'VALIDATION_ERROR',
            'REQUEST_ERROR',
            'CONFLICT',
            'FORBIDDEN',
            'UNAUTHENTICATED',
          ].contains(e.code);
      if (definitive) {
        _pending = null;
        key = const Uuid().v4();
        // Reload first so the refusal stays visible afterwards.
        await load();
        if (isClosed) return;
      }
      emit(
        state.copyWith(
          error: admissionError(e),
          uncertainId: definitive ? null : id,
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    await super.close();
  }
}

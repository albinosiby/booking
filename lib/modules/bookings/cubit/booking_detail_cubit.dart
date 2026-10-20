import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/booking_models.dart';
import '../models/booking_detail_model.dart';
import '../repositories/booking_repository.dart';
import 'booking_form_cubit.dart';

class BookingDetailCubit extends Cubit<BookingDetailModel> {
  BookingDetailCubit(this.session, this.repository, this.id)
    : super(BookingDetailModel()) {
    scope = bookingScope(session);
    subscription = session.snapshots.listen((_) {
      if (bookingScope(session) != scope) {
        scope = bookingScope(session);
        generation++;
        emit(
          BookingDetailModel(
            loading: false,
            error: 'Your account or access changed. Reopen this booking.',
          ),
        );
      }
    });
    changes = repository.changes.listen((_) {
      if (!state.loading &&
          !state.locked &&
          state.action == BookingDetailAction.none) {
        load();
      }
    });
  }
  final WorkspaceSession session;
  final BookingRepository repository;
  final String id;
  late String scope;
  late StreamSubscription subscription, changes;
  int generation = 0;
  bool valid(int g) => !isClosed && g == generation;
  Future<void> load() async {
    final g = ++generation;
    emit(state.copyWith(loading: true));
    try {
      final results = await Future.wait<Object>([
        repository.catalog(),
        repository.detail(id),
      ]);
      final catalog = results[0] as BookingCatalog,
          record = results[1] as BookingRecord;
      if (valid(g)) {
        emit(
          BookingDetailModel(catalog: catalog, record: record, loading: false),
        );
      }
    } catch (e) {
      if (valid(g)) {
        emit(
          accessFailure(e)
              ? BookingDetailModel(loading: false, error: bookingError(e))
              : state.copyWith(loading: false, error: bookingError(e)),
        );
      }
    }
  }

  void begin(BookingDetailAction a) {
    if (state.locked || state.record == null) return;
    final b = state.record!;
    if (a == BookingDetailAction.collection && !state.canCollectPending) return;
    if ((a == BookingDetailAction.collection ||
            a == BookingDetailAction.refund) &&
        !state.catalog.canCollect) {
      return;
    }
    if (a == BookingDetailAction.refund && !state.catalog.canRefund) return;
    if (![
          BookingDetailAction.collection,
          BookingDetailAction.refund,
        ].contains(a) &&
        !state.catalog.canManage) {
      return;
    }
    emit(
      state.copyWith(
        action: a,
        customer: b.customer,
        notes: b.notes,
        reason: '',
        payments: [BookingPaymentDraft()],
      ),
    );
  }

  void cancelEdit() {
    if (!state.locked) {
      emit(state.copyWith(action: BookingDetailAction.none, payments: []));
    }
  }

  void reason(String v) {
    if (!state.locked) emit(state.copyWith(reason: v));
  }

  void customerName(String v) {
    if (!state.locked) {
      emit(state.copyWith(customer: state.customer.copyWith(name: v)));
    }
  }

  void customerPhone(String v) {
    if (!state.locked) {
      emit(state.copyWith(customer: state.customer.copyWith(phone: v)));
    }
  }

  void customerEmail(String v) {
    if (!state.locked) {
      emit(state.copyWith(customer: state.customer.copyWith(email: v)));
    }
  }

  void notes(String v) {
    if (!state.locked) emit(state.copyWith(notes: v));
  }

  void addPayment() {
    if (!state.locked && state.payments.length < 20) {
      emit(
        state.copyWith(
          payments: [
            ...state.payments,
            BookingPaymentDraft(
              amount: (state.paymentEntry.remaining ?? 0) > 0
                  ? (state.paymentEntry.remaining! / 100).toStringAsFixed(2)
                  : '',
            ),
          ],
        ),
      );
    }
  }

  void updatePayment(
    String id,
    BookingPaymentDraft Function(BookingPaymentDraft) update,
  ) {
    if (!state.locked) {
      emit(
        state.copyWith(
          payments: state.payments.map((p) => p.id == id ? update(p) : p),
        ),
      );
    }
  }

  void payBalance(String id) {
    final balance = state.paymentBalance(id);
    if (balance == null || balance <= 0) return;
    updatePayment(
      id,
      (p) => p.copyWith(amount: (balance / 100).toStringAsFixed(2)),
    );
  }

  void removePayment(String id) {
    if (!state.locked) {
      emit(
        state.copyWith(
          payments: state.payments.length == 1
              ? [BookingPaymentDraft()]
              : state.payments.where((p) => p.id != id),
        ),
      );
    }
  }

  Future<void> submit() async {
    if (state.saving || state.record == null) return;
    if (state.pending != null) {
      await _send(state.pending!);
      return;
    }
    final b = state.record!, a = state.action;
    if (a == BookingDetailAction.none) return;
    final key = const Uuid().v4();
    BookingCommand command;
    if (a == BookingDetailAction.collection ||
        a == BookingDetailAction.refund) {
      if (state.paymentEntry.recorded.isEmpty) {
        emit(state.copyWith(error: 'Add at least one payment.'));
        return;
      }
      for (final p in state.paymentEntry.recorded) {
        if (p.validate() != null) {
          emit(state.copyWith(error: p.validate()));
          return;
        }
      }
      final amount = state.payments.fold(0, (n, p) => n + (p.minor ?? 0));
      if (amount >
          (a == BookingDetailAction.refund ? b.refundDue : b.balance)) {
        emit(
          state.copyWith(error: 'Amount exceeds the balance or refund due.'),
        );
        return;
      }
      if (a == BookingDetailAction.refund && state.reason.trim().length < 2) {
        emit(state.copyWith(error: 'Enter a refund reason.'));
        return;
      }
      command = BookingCommand(key, '/bookings/$id/payments', {
        'version': b.version,
        'payments': state.paymentEntry.recorded.map((p) => p.toJson()).toList(),
        'kind': a == BookingDetailAction.refund ? 'refund' : 'collection',
        'reason': state.reason.trim(),
      });
    } else if (a == BookingDetailAction.customer) {
      final error = state.customer.validate();
      if (error != null) {
        emit(state.copyWith(error: error));
        return;
      }
      command = BookingCommand(key, '/bookings/$id/customer', {
        'version': b.version,
        'customer': state.customer.toJson(),
        'notes': state.notes,
      });
    } else {
      if (state.reason.trim().length < 2) {
        emit(state.copyWith(error: 'Enter a reason for this change.'));
        return;
      }
      command = BookingCommand(key, '/bookings/$id/status', {
        'version': b.version,
        'status': a == BookingDetailAction.noShow ? 'no_show' : a.name,
        'reason': state.reason.trim(),
      });
    }
    await _send(command);
  }

  Future<void> _send(BookingCommand c) async {
    final g = generation;
    emit(state.copyWith(saving: true, pending: c));
    try {
      await repository.submit(c);
      if (valid(g)) await load();
    } catch (e) {
      if (!valid(g)) return;
      if (e is AppException && e.code == 'NETWORK') {
        try {
          final result = await repository.commandResult(c.key);
          if (result != null && valid(g)) {
            await load();
            return;
          }
        } catch (_) {}
        if (valid(g)) {
          emit(
            state.copyWith(
              saving: false,
              error:
                  'The outcome could not be verified. Retry this action to recover it safely.',
            ),
          );
        }
      } else {
        emit(
          state.copyWith(
            saving: false,
            clearPending: true,
            error: bookingError(e),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    await changes.cancel();
    return super.close();
  }
}

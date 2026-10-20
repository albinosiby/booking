import '../../accounts/models/accounts_models.dart';
import 'dart:async';
import 'dart:typed_data';
import '../../accounts/cubit/accounts_cubits.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../repositories/expenses_repository.dart';
import '../models/expense_models.dart';
import 'expenses_state.dart';

class ExpenseDetailCubit extends FinanceCubit<ExpenseDetailState> {
  ExpenseDetailCubit(
    WorkspaceSession session,
    this.repository,
    this.picker,
    this.id,
  ) : super(session, const ExpenseDetailState()) {
    changes = repository.changes.listen((_) {
      if (!state.loading && !state.busy) unawaited(load());
    });
  }
  late final StreamSubscription<void> changes;
  @override
  Future<void> close() {
    changes.cancel();
    return super.close();
  }

  final ExpensesRepository repository;
  final InvoicePicker picker;
  final String id;
  @override
  void onAccessChanged() => emit(
    const ExpenseDetailState(
      error: 'Your access changed. Reopen this expense.',
    ),
  );
  Future<void> load() async {
    if (!authorized) return;
    final g = ++epoch;
    emit(state.copy(loading: true));
    try {
      final results = await Future.wait<Object>([
        repository.financeCatalog(),
        repository.detail(id),
      ]);
      final catalog = results[0] as FinanceCatalog,
          detail = results[1] as ExpenseDetail;
      if (current(g)) {
        emit(ExpenseDetailState(catalog: catalog, detail: detail));
      }
    } catch (e) {
      if (current(g)) emit(state.copy(loading: false, error: financeError(e)));
    }
  }

  Future<Uint8List?> preview(ExpenseInvoice file) async {
    if (!authorized || state.busy) return null;
    final g = epoch;
    emit(state.copy(busy: true));
    try {
      final b = await repository.invoice(id, file.id);
      if (current(g)) {
        emit(state.copy(busy: false));
        return b;
      }
    } catch (e) {
      if (current(g)) emit(state.copy(busy: false, error: financeError(e)));
    }
    return null;
  }

  Future<void> add({ExpenseInvoice? pending}) async {
    if (!authorized || state.busy) return;
    final g = epoch;
    emit(state.copy(busy: true));
    try {
      final files = await picker.pick();
      if (!current(g)) return;
      if (pending != null && files.length != 1) {
        throw Exception('Choose the original invoice file.');
      }
      if (pending == null &&
          files.length + (state.detail?.invoices.length ?? 0) > 10) {
        throw Exception('An expense can have up to 10 invoices.');
      }
      for (final file in files) {
        if (!current(g)) return;
        var chosen = file;
        if (pending != null) {
          if (file.invoice.name != pending.name ||
              file.invoice.size != pending.size ||
              file.invoice.type != pending.type) {
            throw Exception(
              'Choose the same original file to retry, or remove the pending invoice first.',
            );
          }
          chosen = ExpensePickedInvoice(pending, file.bytes);
        }
        await repository.upload(id, chosen);
      }
      if (current(g)) {
        emit(state.copy(busy: false));
        await load();
      }
    } catch (e) {
      if (current(g)) {
        emit(
          state.copy(
            busy: false,
            error: e is Exception
                ? e.toString().replaceFirst('Exception: ', '')
                : financeError(e),
          ),
        );
      }
    }
  }

  Future<void> remove(ExpenseInvoice file) async {
    if (!authorized || state.busy) return;
    final g = epoch;
    emit(state.copy(busy: true));
    try {
      await repository.discardPending(id, file.id);
      if (current(g)) {
        emit(state.copy(busy: false));
        await load();
      }
    } catch (e) {
      if (current(g)) emit(state.copy(busy: false, error: financeError(e)));
    }
  }
}

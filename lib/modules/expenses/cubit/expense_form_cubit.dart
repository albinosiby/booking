import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../accounts/cubit/accounts_cubits.dart';
import '../../accounts/models/accounts_models.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../../../utils/helpers/validation.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../repositories/expenses_repository.dart';
import '../models/expense_models.dart';
import 'expenses_state.dart';

class ExpenseFormCubit extends FinanceCubit<ExpenseFormState> {
  ExpenseFormCubit(WorkspaceSession session, this.repository, this.picker)
    : super(session, ExpenseFormState());
  final ExpensesRepository repository;
  final InvoicePicker picker;
  final command = const Uuid().v4();
  ExpenseDraft? pending;
  bool get editable =>
      authorized && !state.busy && state.savedId == null && pending == null;
  @override
  void onAccessChanged() =>
      emit(ExpenseFormState(error: 'Your access changed. Reopen this form.'));
  Future<void> load() async {
    if (!authorized) return;
    final g = ++epoch;
    emit(state.copy(loading: true));
    try {
      final results = await Future.wait<Object>([
        repository.financeCatalog(),
        repository.categories(),
      ]);
      final catalog = results[0] as FinanceCatalog,
          categories = results[1] as List<ExpenseCategory>;
      if (current(g)) {
        emit(
          state.copy(
            loading: false,
            catalog: catalog,
            categories: categories,
            date: DateTime.now(),
            lines: [
              FinanceDraftLine(
                id: const Uuid().v4(),
                accountId: catalog.destination('cash', null, null),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (current(g)) emit(state.copy(loading: false, error: financeError(e)));
    }
  }

  void fields({
    String? reason,
    String? reference,
    String? categoryId,
    DateTime? date,
  }) {
    if (editable) {
      emit(
        state.copy(
          reason: reason,
          reference: reference,
          categoryId: categoryId,
          date: date,
        ),
      );
    }
  }

  void scope(String? business, String? space) {
    if (editable) {
      emit(state.copy(businessId: business, spaceId: space, clearScope: true));
    }
  }

  void line(int i, FinanceDraftLine l) {
    if (editable) {
      final lines = [...state.lines];
      lines[i] = l;
      emit(state.copy(lines: lines));
    }
  }

  void method(int i, String method) => line(
    i,
    state.lines[i].copyWith(
      method: method,
      accountId: state.catalog?.destination(
        method,
        state.businessId,
        state.spaceId,
      ),
      clearAccount:
          state.catalog?.destination(method, state.businessId, state.spaceId) ==
          null,
    ),
  );
  void addLine() {
    if (editable && state.lines.length < 20) {
      emit(
        state.copy(
          lines: [
            ...state.lines,
            FinanceDraftLine(
              id: const Uuid().v4(),
              accountId: state.catalog?.destination('cash', null, null),
            ),
          ],
        ),
      );
    }
  }

  void removeLine(int i) {
    if (editable && state.lines.length > 1) {
      emit(state.copy(lines: [...state.lines]..removeAt(i)));
    }
  }

  int get total =>
      state.lines.fold(0, (n, l) => n + (Validation.priceMinor(l.amount) ?? 0));
  Future<void> pick({bool camera = false, bool photos = false}) async {
    if (!editable || state.picking) return;
    final g = epoch;
    emit(state.copy(picking: true));
    try {
      final files = await picker.pick(camera: camera, photos: photos);
      if (!current(g)) return;
      if (state.files.length + files.length > 10) {
        throw const AppException('An expense can have up to 10 invoices.');
      }
      emit(state.copy(picking: false, files: [...state.files, ...files]));
    } catch (e) {
      if (current(g)) emit(state.copy(picking: false, error: financeError(e)));
    }
  }

  void removeFile(int i) {
    if (editable) emit(state.copy(files: [...state.files]..removeAt(i)));
  }

  Future<void> save() async {
    if (!authorized || state.busy || state.picking || state.catalog == null) {
      return;
    }
    if (state.savedId == null && pending == null) {
      final category = state.categories
          .where((c) => c.id == state.categoryId && c.active)
          .firstOrNull;
      if (category == null ||
          state.reason.trim().length < 2 ||
          state.lines.isEmpty ||
          state.lines.any(
            (l) =>
                l.accountId == null ||
                (Validation.priceMinor(l.amount) ?? 0) <= 0,
          )) {
        emit(
          state.copy(
            error:
                'Choose a category, enter a reason, and provide a positive amount and account for every payment.',
          ),
        );
        return;
      }
      pending = ExpenseDraft(
        commandId: command,
        categoryId: category.id,
        categoryName: category.name,
        reason: state.reason.trim(),
        reference: state.reference.trim(),
        businessId: state.businessId,
        spaceId: state.spaceId,
        occurredAt: state.date ?? DateTime.now(),
        payments: [
          for (final l in state.lines)
            ExpensePayment(
              accountId: l.accountId!,
              method: l.method,
              amount: Validation.priceMinor(l.amount)!,
            ),
        ],
      );
    }
    final g = ++epoch;
    emit(state.copy(busy: true));
    try {
      var id = state.savedId;
      if (id == null) {
        id = await repository.create(pending!);
        if (!current(g)) return;
        emit(state.copy(savedId: id));
      }
      for (var i = 0; i < state.files.length; i++) {
        if (!current(g)) return;
        final f = state.files[i];
        if (f.uploaded) continue;
        try {
          await repository.upload(id, f);
          if (!current(g)) return;
          final files = [...state.files];
          files[i] = f.copy(uploaded: true);
          emit(state.copy(files: files));
        } catch (e) {
          if (!current(g)) return;
          final files = [...state.files];
          files[i] = f.copy(error: financeError(e));
          emit(state.copy(files: files));
        }
      }
      if (current(g)) {
        final failed = state.files.any((f) => !f.uploaded);
        emit(
          state.copy(
            busy: false,
            complete: !failed,
            error: failed
                ? 'Expense saved. Some invoices need another try. Tap Retry invoices.'
                : null,
          ),
        );
      }
    } catch (e) {
      if (current(g)) {
        if (e is AppException && e.code != 'NETWORK') pending = null;
        emit(state.copy(busy: false, error: financeError(e)));
      }
    }
  }
}

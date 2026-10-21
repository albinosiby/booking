import '../../accounts/models/accounts_models.dart';
import 'dart:async';
import '../../accounts/cubit/accounts_cubits.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../repositories/expenses_repository.dart';
import '../models/expense_models.dart';
import 'expenses_state.dart';

class ExpensesCubit extends FinanceCubit<ExpensesState> {
  ExpensesCubit(WorkspaceSession session, this.repository, this.saver)
    : super(
        session,
        ExpensesState(filter: ExpenseFilter(anchor: DateTime.now())),
      ) {
    changes = repository.changes.listen((_) {
      if (!state.loading && !state.more) unawaited(load());
    });
  }
  final ExpensesRepository repository;
  final ReportSaver saver;
  late final StreamSubscription<void> changes;
  bool initialized = false;
  @override
  bool get followsAccessChanges => true;
  @override
  void onAccessChanged() {
    initialized = false;
    emit(
      ExpensesState(
        filter: ExpenseFilter(anchor: DateTime.now()),
        error: 'Your access changed.',
      ),
    );
  }

  @override
  void onAccessRestored() => unawaited(load());
  Future<void> load({bool refresh = false, ExpenseFilter? filter}) async {
    if (!authorized) return;
    final g = ++epoch;
    if (refresh) repository.refresh();
    emit(
      filter == null
          ? state.copy(loading: true)
          // Keep the previous figures visible (faded) until the new period
          // arrives, instead of collapsing the page to a loader.
          : ExpensesState(
              filter: filter,
              catalog: state.catalog,
              categories: state.categories,
              summary: state.summary,
              items: state.items,
              loading: true,
              exporting: state.exporting,
            ),
    );
    try {
      final results = await Future.wait<Object>([
        repository.financeCatalog(),
        repository.categories(),
      ]);
      final catalog = results[0] as FinanceCatalog,
          categories = results[1] as List<ExpenseCategory>;
      final f = !initialized && filter == null
          ? state.filter.copy(
              anchor: DateTime.tryParse(catalog.today) ?? DateTime.now(),
            )
          : state.filter;
      initialized = true;
      if (!catalog.canView) {
        if (current(g)) {
          emit(
            ExpensesState(filter: f, catalog: catalog, categories: categories),
          );
        }
        return;
      }
      final result = await Future.wait([
        repository.overview(f),
        repository.list(f),
      ]);
      if (current(g)) {
        final page = result[1] as ExpensePage;
        emit(
          ExpensesState(
            filter: f,
            catalog: catalog,
            categories: categories,
            summary: result[0] as ExpenseSummary,
            items: page.items,
            next: page.next,
            exporting: state.exporting,
          ),
        );
        unawaited(prefetch(f));
      }
    } catch (e) {
      if (current(g)) {
        // Figures from another period must not stay under the new title.
        emit(
          filter == null
              ? state.copy(loading: false, error: financeError(e))
              : ExpensesState(
                  filter: state.filter,
                  catalog: state.catalog,
                  categories: state.categories,
                  exporting: state.exporting,
                  error: financeError(e),
                ),
        );
      }
    }
  }

  /// Warms the cache for the previous period so stepping back is instant.
  Future<void> prefetch(ExpenseFilter f) async {
    final previous = f.copy(
      anchor: f.yearly
          ? DateTime(f.anchor.year - 1)
          : DateTime(f.anchor.year, f.anchor.month - 1),
    );
    try {
      await Future.wait([
        repository.overview(previous),
        repository.list(previous),
      ]);
    } catch (_) {
      // Only a cache warm-up; the real load reports its own errors.
    }
  }

  void setFilter(ExpenseFilter f) => unawaited(load(filter: f));
  Future<void> more() async {
    if (state.next == null || state.more || state.loading || !authorized) {
      return;
    }
    final g = epoch;
    emit(state.copy(more: true));
    try {
      final p = await repository.list(state.filter, cursor: state.next!);
      if (current(g)) {
        emit(
          state.copy(
            more: false,
            items: [...state.items, ...p.items],
            next: p.next,
            clearNext: true,
          ),
        );
      }
    } catch (e) {
      if (current(g)) emit(state.copy(more: false, error: financeError(e)));
    }
  }

  Future<void> category(String name, {String? id, bool active = true}) async {
    if (!authorized) return;
    try {
      await repository.saveCategory(name, id: id, active: active);
      await load(refresh: true);
    } catch (e) {
      if (!isClosed && authorized) emit(state.copy(error: financeError(e)));
    }
  }

  Future<void> export(String format) async {
    if (state.exporting || !authorized) return;
    final f = state.filter, scope = accessScope;
    emit(state.copy(exporting: true));
    try {
      final bytes = await repository.report(f, format);
      if (isClosed || !authorized || accessScope != scope) return;
      final saved = await saver.save(
        bytes,
        'expenses-${f.from}-${f.until}${f.categoryId == null ? '' : '-category'}.$format',
      );
      if (!isClosed && authorized && accessScope == scope) {
        emit(
          state.copy(
            exporting: false,
            message: saved ? 'Report downloaded.' : 'Download cancelled.',
          ),
        );
      }
    } catch (e) {
      if (!isClosed && authorized && accessScope == scope) {
        emit(state.copy(exporting: false, error: financeError(e)));
      }
    }
  }

  @override
  Future<void> close() {
    changes.cancel();
    return super.close();
  }
}

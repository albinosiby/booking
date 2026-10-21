import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../accounts/models/accounts_models.dart';
import '../../accounts/widgets/accounts_widgets.dart';
import '../../accounts/widgets/accounts_overview_widgets.dart';
import '../../accounts/widgets/finance_ledger_widgets.dart';
import '../../accounts/widgets/finance_period_widgets.dart';
import '../cubit/expenses_cubit.dart';
import '../cubit/expenses_state.dart';
import '../models/expense_models.dart';
import '../widgets/expenses_widgets.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late final cubit = getIt<ExpensesCubit>(
    param1: context.read<WorkspaceCubit>(),
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> export() async {
    final format = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download expense report',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${cubit.state.filter.from} – ${cubit.state.filter.until}\nIncludes the selected category and filters.',
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF report'),
              onTap: () => Navigator.pop(c, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Excel workbook'),
              onTap: () => Navigator.pop(c, 'xlsx'),
            ),
          ],
        ),
      ),
    );
    if (format != null) await cubit.export(format);
  }

  Future<void> categoryDialog({ExpenseCategory? category}) async {
    final controller = TextEditingController(text: category?.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(category == null ? 'New category' : 'Edit category'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 2) {
                Navigator.pop(c, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) {
      await cubit.category(
        name,
        id: category?.id,
        active: category?.active ?? true,
      );
    }
  }

  Future<void> manageCategories() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .65,
        builder: (c, controller) => BlocBuilder<ExpensesCubit, ExpensesState>(
          bloc: cubit,
          builder: (c, s) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Expense categories',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add category'),
                onTap: () => categoryDialog(),
              ),
              for (final category in s.categories)
                ListTile(
                  leading: Icon(expenseCategoryIcon(category.name)),
                  title: Text(category.name),
                  subtitle: category.active
                      ? null
                      : const Text('Archived · history preserved'),
                  onTap: () => categoryDialog(category: category),
                  trailing: IconButton(
                    tooltip: category.active
                        ? 'Archive category'
                        : 'Restore category',
                    icon: Icon(
                      category.active
                          ? Icons.archive_outlined
                          : Icons.unarchive_outlined,
                    ),
                    onPressed: () => cubit.category(
                      category.name,
                      id: category.id,
                      active: !category.active,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> filters() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => BlocBuilder<ExpensesCubit, ExpensesState>(
        bloc: cubit,
        builder: (c, s) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter expenses', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 20),
              if (s.catalog != null)
                FinanceScopePicker(
                  catalog: s.catalog!,
                  business: s.filter.businessId,
                  space: s.filter.spaceId,
                  onChanged: (b, r) => cubit.setFilter(
                    s.filter.copy(businessId: b, spaceId: r, clearScope: true),
                  ),
                ),
              const SizedBox(height: 16),
              AppPicker(
                label: 'Paid from',
                value: s.filter.accountId ?? '',
                items: [
                  const PickerItem('', 'All accounts'),
                  ...s.catalog!.accounts.map((a) => PickerItem(a.id, a.name)),
                ],
                onChanged: (v) => cubit.setFilter(
                  s.filter.copy(accountId: v, clearAccount: v.isEmpty),
                ),
              ),
              const SizedBox(height: 20),
              AppButton(label: 'Done', onPressed: () => Navigator.pop(c)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<ExpensesCubit, ExpensesState>(
    bloc: cubit,
    listener: (c, s) {
      if (s.message != null) showMessage(c, s.message!);
    },
    builder: (c, s) {
      final catalog = s.catalog, f = s.filter, summary = s.summary;
      final category = s.categories
          .where((c) => c.id == f.categoryId)
          .firstOrNull;
      final filtered =
          (f.businessId != null ? 1 : 0) + (f.accountId != null ? 1 : 0);
      return AppPage(
        title: 'Expenses',
        back: true,
        showAppBar: true,
        compactHeader: true,
        scrollId: 'expenses',
        actions: [
          if (catalog?.canView == true && summary != null)
            IconButton(
              tooltip: 'Download report',
              onPressed: s.exporting ? null : export,
              icon: s.exporting
                  ? const AppSavingDots()
                  : const Icon(Icons.download_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: s.loading ? null : () => cubit.load(refresh: true),
            icon: const Icon(Icons.refresh),
          ),
          if (catalog?.canManage == true)
            IconButton(
              tooltip: 'Manage categories',
              onPressed: manageCategories,
              icon: const Icon(Icons.category_outlined),
            ),
        ],
        floatingActionButton: catalog?.canExpense == true
            ? FloatingActionButton.extended(
                onPressed: () async {
                  await c.push('/expenses/new');
                  await cubit.load(refresh: true);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add expense'),
              )
            : null,
        children: [
          if (s.loading && summary == null)
            const AppLoadingState(initial: true, label: 'Loading expenses…'),
          if (s.error != null)
            AppErrorWidget(
              message: s.error!,
              onRetry: () => cubit.load(refresh: true),
            ),
          if (catalog != null && !catalog.canView)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'You can record expenses. Ask the owner for finance access to view reports and expense history.',
              ),
            ),
          if (catalog?.canView == true) ...[
            FinancePeriodBar(
              anchor: f.anchor,
              yearly: f.yearly,
              onChanged: (anchor, yearly) =>
                  cubit.setFilter(f.copy(anchor: anchor, yearly: yearly)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FinanceFilterChip(
                  icon: Icons.category_outlined,
                  label: category?.name ?? 'All categories',
                  tooltip: 'Choose category',
                  active: f.categoryId != null,
                  onTap: pickCategory,
                  onClear: f.categoryId == null
                      ? null
                      : () => cubit.setFilter(f.copy(clearCategory: true)),
                ),
                FinanceFilterChip(
                  icon: Icons.tune,
                  label: filtered == 0 ? 'Filters' : 'Filters · $filtered',
                  tooltip: 'Filter expenses',
                  active: filtered > 0,
                  onTap: filters,
                ),
              ],
            ),
            // Fixed height so the page does not jump while loading.
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 3,
                child: s.loading && summary != null
                    ? const LinearProgressIndicator(minHeight: 3)
                    : null,
              ),
            ),
            if (summary != null)
              AnimatedOpacity(
                opacity: s.loading ? .45 : 1,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: s.loading,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 13),
                      FinanceTotalCard(
                        label: category?.name ?? 'Total expenses',
                        amount: summary.total,
                        currency: catalog!.currency,
                        inverse: true,
                        subtitle:
                            '${summary.count} ${summary.count == 1 ? 'entry' : 'entries'} · ${financeRangeLabel(FinanceFilter(from: f.from, until: f.until))}',
                        stats: [
                          financeAverage(
                            summary.total,
                            f.anchor,
                            f.yearly,
                            catalog.today,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        child: ExpenseChart(
                          values: summary.bars(f),
                          filter: f,
                          currency: catalog.currency,
                          onMonth: (m) => cubit.setFilter(
                            f.copy(
                              anchor: DateTime(f.anchor.year, m),
                              yearly: false,
                            ),
                          ),
                        ),
                      ),
                      if (summary.categories.isNotEmpty) ...[
                        const FinanceSection('By category'),
                        FinanceBreakdown(
                          shares: [
                            for (final c in summary.categories)
                              FinanceShare(
                                c.id,
                                c.name,
                                c.total,
                                expenseCategoryIcon(c.name),
                              ),
                          ],
                          currency: catalog.currency,
                          selected: f.categoryId,
                          onSelect: (id) =>
                              cubit.setFilter(f.copy(categoryId: id)),
                        ),
                      ],
                      const FinanceSection('All expenses'),
                      if (s.items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 36),
                                SizedBox(height: 12),
                                Text('No expenses in this period'),
                                SizedBox(height: 6),
                                Text(
                                  'Choose another period or add an expense.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        FinanceDayGroups<ExpenseItem>(
                          items: s.items,
                          dayOf: (i) => i.date,
                          amountOf: (i) => i.amount,
                          currency: catalog.currency,
                          today: catalog.today,
                          builder: (item) => ExpenseTile(
                            item: item,
                            currency: catalog.currency,
                            onTap: () => c.push(
                              '/expenses/${item.originalId ?? item.id}',
                            ),
                          ),
                        ),
                      if (s.next != null)
                        Center(
                          child: TextButton(
                            onPressed: s.more ? null : cubit.more,
                            child: Text(s.more ? 'Loading…' : 'Load more'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );

  Future<void> pickCategory() async {
    final s = cubit.state;
    final id = await showFinanceOptions(
      context,
      title: 'Category',
      selected: s.filter.categoryId ?? '',
      options: [
        const FinanceOption('', 'All categories', icon: Icons.all_inclusive),
        for (final c in s.categories)
          FinanceOption(
            c.id,
            c.name,
            icon: expenseCategoryIcon(c.name),
            note: c.active ? null : 'Archived',
          ),
      ],
    );
    if (id != null) {
      cubit.setFilter(s.filter.copy(categoryId: id, clearCategory: id.isEmpty));
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../accounts/models/accounts_models.dart';
import '../../accounts/widgets/accounts_widgets.dart';
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

  Future<void> period() async {
    final f = cubit.state.filter;
    final d = await showDatePicker(
      context: context,
      initialDate: f.anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: f.yearly
          ? 'Choose a date in the year'
          : 'Choose a date in the month',
    );
    if (d != null) cubit.setFilter(f.copy(anchor: d));
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
      return AppPage(
        title: 'Expenses',
        back: true,
        showAppBar: true,
        compactHeader: true,
        scrollId: 'expenses',
        actions: [
          if (catalog?.canView == true)
            IconButton(
              tooltip: 'Filter expenses',
              onPressed: filters,
              icon: const Icon(Icons.tune),
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
          if (s.loading)
            AppLoadingState(
              initial: summary == null,
              label: summary == null ? 'Loading expenses…' : null,
            ),
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
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Monthly')),
                      ButtonSegment(value: true, label: Text('Yearly')),
                    ],
                    selected: {f.yearly},
                    onSelectionChanged: (v) =>
                        cubit.setFilter(f.copy(yearly: v.first)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Choose period',
                  onPressed: period,
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous period',
                  onPressed: () => cubit.setFilter(
                    f.copy(
                      anchor: f.yearly
                          ? DateTime(f.anchor.year - 1)
                          : DateTime(f.anchor.year, f.anchor.month - 1),
                    ),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    f.yearly
                        ? '${f.anchor.year}'
                        : '${expenseMonths[f.anchor.month - 1]} ${f.anchor.year}',
                    textAlign: TextAlign.center,
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next period',
                  onPressed: () => cubit.setFilter(
                    f.copy(
                      anchor: f.yearly
                          ? DateTime(f.anchor.year + 1)
                          : DateTime(f.anchor.year, f.anchor.month + 1),
                    ),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppPicker(
              label: 'Category',
              value: f.categoryId ?? '',
              items: [
                const PickerItem('', 'All categories'),
                ...s.categories.map(
                  (c) => PickerItem(
                    c.id,
                    '${c.name}${c.active ? '' : ' (archived)'}',
                  ),
                ),
              ],
              onChanged: (v) => cubit.setFilter(
                f.copy(categoryId: v, clearCategory: v.isEmpty),
              ),
            ),
            if (summary != null) ...[
              const SizedBox(height: 20),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category?.name ?? 'Total expenses',
                      style: Theme.of(c).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      financeMoney(summary.total, catalog!.currency),
                      style: Theme.of(c).textTheme.headlineLarge,
                    ),
                    Text(
                      '${summary.count} entries · ${f.from} – ${f.until}',
                      style: Theme.of(c).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 22),
                    ExpenseChart(
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
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: s.exporting ? null : export,
                icon: s.exporting
                    ? const AppSavingDots()
                    : const Icon(Icons.download_outlined),
                label: Text(
                  s.exporting ? 'Preparing report…' : 'Download PDF / Excel',
                ),
              ),
              if (summary.categories.isNotEmpty) ...[
                const FinanceSection('By category'),
                for (final category in summary.categories)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(expenseCategoryIcon(category.name)),
                    title: Text(category.name),
                    trailing: Text(
                      financeMoney(category.total, catalog.currency),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: category.id == null
                        ? null
                        : () =>
                              cubit.setFilter(f.copy(categoryId: category.id)),
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
                        Text('Choose another period or add an expense.'),
                      ],
                    ),
                  ),
                ),
              for (final item in s.items)
                ExpenseTile(
                  item: item,
                  currency: catalog.currency,
                  onTap: () =>
                      c.push('/expenses/${item.originalId ?? item.id}'),
                ),
              if (s.next != null)
                Center(
                  child: TextButton(
                    onPressed: s.more ? null : cubit.more,
                    child: Text(s.more ? 'Loading…' : 'Load more'),
                  ),
                ),
            ],
          ],
        ],
      );
    },
  );
}

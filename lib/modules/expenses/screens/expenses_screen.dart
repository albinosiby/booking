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
import '../widgets/expense_daily_breakdown.dart';
import '../widgets/expense_report_sheet.dart';
import '../widgets/finance_desktop_widgets.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final search = TextEditingController();
  late final cubit = getIt<ExpensesCubit>(
    param1: context.read<WorkspaceCubit>(),
  )..load();
  @override
  void dispose() {
    search.dispose();
    cubit.close();
    super.dispose();
  }

  Future<void> export({String format = 'pdf'}) async {
    final state = cubit.state;
    final selection = await showAdaptiveSheet<ExpenseReportSelection>(
      context: context,
      builder: (c) => ExpenseReportSheet(
        initialAnchor: state.filter.anchor,
        catalog: state.catalog!,
        categories: state.categories,
        initialFormat: format,
      ),
    );
    if (selection != null && mounted) {
      showMessage(context, 'Preparing the expense report…');
      await cubit.export(selection.format, filter: selection.filter);
    }
  }

  Future<void> categoryDialog({ExpenseCategory? category}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (c) => _ExpenseCategoryNameDialog(category: category),
    );
    if (name != null) {
      await cubit.category(
        name,
        id: category?.id,
        active: category?.active ?? true,
      );
    }
  }

  Future<void> manageCategories() async {
    await showAdaptiveSheet<void>(
      context: context,
      scrollable: false,
      builder: (c) => AdaptiveSheetBody(
        builder: (c, controller, shrink) =>
            BlocBuilder<ExpensesCubit, ExpensesState>(
              bloc: cubit,
              builder: (c, s) => ListView(
                controller: controller,
                shrinkWrap: shrink,
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Expense categories',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                  if (s.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      s.error!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                  ],
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
    await showAdaptiveSheet<void>(
      context: context,
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

  Future<void> addExpense({DateTime? date}) async {
    await context.push('/expenses/new', extra: date);
    await cubit.load(refresh: true);
  }

  Future<void> exportDay() async {
    final state = cubit.state, day = state.selectedDay;
    if (day == null || state.exporting || state.catalog?.canView != true) {
      return;
    }
    final filter = state.filter.copy(day: day);
    final format = await showFinanceOptions(
      context,
      title: 'Download ${filter.from} expenses',
      selected: 'pdf',
      options: const [
        FinanceOption('pdf', 'PDF report', icon: Icons.picture_as_pdf_outlined),
        FinanceOption(
          'xlsx',
          'Excel workbook',
          icon: Icons.table_chart_outlined,
        ),
      ],
    );
    if (format == null || !mounted) return;
    showMessage(context, 'Preparing the day report…');
    await cubit.export(format, filter: filter);
  }

  Widget categoryChips(ExpensesState s) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (id, label) in <(String?, String)>[
          (null, 'All categories'),
          for (final category in s.categories)
            (
              category.id,
              category.active ? category.name : '${category.name} · archived',
            ),
        ]) ...[
          ChoiceChip(
            key: ValueKey('expense-category-${id ?? 'all'}'),
            label: Text(label),
            selected: s.filter.categoryId == id,
            onSelected: (_) => cubit.setFilter(
              s.filter.copy(categoryId: id, clearCategory: id == null),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );

  Widget searchAndFilters(ExpensesState s) {
    final f = s.filter, catalog = s.catalog;
    final business = catalog?.businesses
        .where((item) => item.id == f.businessId)
        .firstOrNull;
    final space = business?.spaces
        .where((item) => item.id == f.spaceId)
        .firstOrNull;
    final account = catalog?.accounts
        .where((item) => item.id == f.accountId)
        .firstOrNull;
    final hasFilters =
        f.categoryId != null ||
        f.businessId != null ||
        f.accountId != null ||
        f.query.trim().isNotEmpty ||
        s.selectedDay != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('expense-search'),
          controller: search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search reason or reference',
            suffixIcon: f.query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      search.clear();
                      cubit.setFilter(f.copy(query: ''));
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          onSubmitted: (value) => cubit.setFilter(f.copy(query: value.trim())),
        ),
        if (hasFilters) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (f.businessId != null)
                InputChip(
                  label: Text(business?.name ?? 'Business'),
                  onDeleted: () => cubit.setFilter(
                    f.copy(businessId: null, spaceId: null, clearScope: true),
                  ),
                ),
              if (f.spaceId != null)
                InputChip(
                  label: Text(space?.name ?? 'Space'),
                  onDeleted: () =>
                      cubit.setFilter(f.copy(spaceId: null, clearScope: true)),
                ),
              if (f.accountId != null)
                InputChip(
                  label: Text(account?.name ?? 'Account'),
                  onDeleted: () => cubit.setFilter(f.copy(clearAccount: true)),
                ),
              if (s.selectedDay != null)
                InputChip(
                  label: Text('Day ${s.selectedDay}'),
                  onDeleted: () => cubit.selectDay(null),
                ),
              if (f.query.trim().isNotEmpty)
                InputChip(
                  label: Text('Search: ${f.query.trim()}'),
                  onDeleted: () {
                    search.clear();
                    cubit.setFilter(f.copy(query: ''));
                  },
                ),
              TextButton(
                onPressed: () {
                  search.clear();
                  cubit.load(
                    filter: ExpenseFilter(anchor: f.anchor, yearly: f.yearly),
                    clearDay: true,
                  );
                },
                child: const Text('Clear filters'),
              ),
            ],
          ),
        ],
      ],
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
      if (isDesktopWidth(c)) return _desktop(c, s);
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
                onPressed: addExpense,
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
                  icon: Icons.tune,
                  label: filtered == 0 ? 'Filters' : 'Filters · $filtered',
                  tooltip: 'Filter expenses',
                  active: filtered > 0,
                  onTap: filters,
                ),
              ],
            ),
            categoryChips(s),
            searchAndFilters(s),
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
                        amount: summary.gross,
                        currency: catalog!.currency,
                        inverse: true,
                        subtitle:
                            '${summary.count} ${summary.count == 1 ? 'entry' : 'entries'} · ${financeRangeLabel(FinanceFilter(from: f.from, until: f.until))}',
                        stats: [
                          if (summary.reversals != 0) ...[
                            ('Reversals', summary.reversals),
                            ('Net spent', summary.total),
                          ],
                          (
                            'Net cash spent',
                            summary.methodBreakdownAvailable
                                ? summary.cash
                                : null,
                          ),
                          (
                            'Net bank spent',
                            summary.methodBreakdownAvailable
                                ? summary.bank
                                : null,
                          ),
                          () {
                            final (label, value) = financeAverage(
                              summary.total,
                              f.anchor,
                              f.yearly,
                              catalog.today,
                            );
                            return ('$label (net)', value);
                          }(),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        child: f.yearly
                            ? const Text(
                                'Select a month in View trend to see daily expenses.',
                              )
                            : ExpenseDailyBreakdown(
                                summary: summary,
                                anchor: f.anchor,
                                currency: catalog.currency,
                                selectedDay: s.selectedDay,
                                onDay: cubit.selectDay,
                                onClearDay: () => cubit.selectDay(null),
                                onAddExpense:
                                    catalog.canExpense && s.selectedDay != null
                                    ? () => addExpense(
                                        date: DateTime(
                                          f.anchor.year,
                                          f.anchor.month,
                                          s.selectedDay!,
                                          12,
                                        ),
                                      )
                                    : null,
                                onDownloadDay: s.selectedDay == null
                                    ? null
                                    : exportDay,
                                exporting: s.exporting,
                              ),
                      ),
                      const SizedBox(height: 8),
                      AppCard(
                        child: ExpansionTile(
                          key: const ValueKey('expense-view-trend'),
                          title: const Text('View trend'),
                          children: [
                            ExpenseChart(
                              values: summary.bars(f),
                              selectedDay: s.selectedDay,
                              onDay: cubit.selectDay,
                              onClearDay: () => cubit.selectDay(null),
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
                      FinanceSection(
                        s.selectedDay == null
                            ? 'All expenses'
                            : 'Selected day’s expenses',
                      ),
                      if (s.items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 36),
                                SizedBox(height: 12),
                                Text(
                                  s.selectedDay == null
                                      ? 'No expenses in this period'
                                      : 'No expenses on this day',
                                ),
                                SizedBox(height: 6),
                                Text(
                                  s.selectedDay == null
                                      ? 'Choose another period or add an expense.'
                                      : 'Select another day or show all days.',
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

  // Wide web windows: toolbar, headline figures, then chart and ledger beside
  // the category breakdown.
  Widget _desktop(BuildContext c, ExpensesState s) {
    final catalog = s.catalog, f = s.filter, summary = s.summary;
    final scheme = Theme.of(c).colorScheme;
    final category = s.categories
        .where((c) => c.id == f.categoryId)
        .firstOrNull;
    final filtered =
        (f.businessId != null ? 1 : 0) + (f.accountId != null ? 1 : 0);
    final range = financeRangeLabel(
      FinanceFilter(from: f.from, until: f.until),
    );
    final canView = catalog?.canView == true;
    String money(int n) => financeMoney(n, catalog?.currency ?? 'INR');
    final top = summary == null || summary.categories.isEmpty
        ? null
        : summary.categories.reduce((a, b) => b.total > a.total ? b : a);
    return AppPage(
      title: 'Expenses',
      back: true,
      scrollId: 'expenses',
      maxWidth: 1240,
      header: FinanceDesktopHeader(
        title: 'Expenses',
        subtitle: canView
            ? 'Spending by category, business and account · $range'
            : 'Record expenses for your organization',
        actions: [
          if (canView && summary != null)
            IconButton.outlined(
              tooltip: 'Download report',
              onPressed: s.exporting ? null : export,
              icon: s.exporting
                  ? const AppSavingDots()
                  : const Icon(Icons.download_outlined),
            ),
          IconButton.outlined(
            tooltip: 'Refresh',
            onPressed: s.loading ? null : () => cubit.load(refresh: true),
            icon: const Icon(Icons.refresh),
          ),
          if (catalog?.canManage == true)
            IconButton.outlined(
              tooltip: 'Manage categories',
              onPressed: manageCategories,
              icon: const Icon(Icons.category_outlined),
            ),
        ],
      ),
      children: [
        AppToolbar(
          leading: canView
              ? Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FinanceDesktopPeriod(
                      anchor: f.anchor,
                      yearly: f.yearly,
                      onChanged: (anchor, yearly) => cubit.setFilter(
                        f.copy(anchor: anchor, yearly: yearly),
                      ),
                    ),
                    FinanceFilterChip(
                      icon: Icons.tune,
                      label: filtered == 0 ? 'Filters' : 'Filters · $filtered',
                      tooltip: 'Filter expenses',
                      active: filtered > 0,
                      onTap: filters,
                    ),
                  ],
                )
              : null,
          actions: [
            if (catalog?.canExpense == true)
              FilledButton.icon(
                onPressed: addExpense,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add expense'),
              ),
          ],
        ),
        if (canView) categoryChips(s),
        if (canView) searchAndFilters(s),
        // Fixed height so the page does not jump while loading.
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
          child: SizedBox(
            height: 3,
            child: s.loading && summary != null
                ? const LinearProgressIndicator(minHeight: 3)
                : null,
          ),
        ),
        if (s.loading && summary == null)
          const AppLoadingState(initial: true, label: 'Loading expenses…'),
        if (s.error != null)
          AppErrorWidget(
            message: s.error!,
            onRetry: () => cubit.load(refresh: true),
          ),
        if (catalog != null && !catalog.canView)
          const FinanceEmptyCard(
            icon: Icons.lock_outline,
            title: 'Finance reports are restricted',
            message:
                'You can record expenses. Ask the owner for finance access to view reports and expense history.',
          ),
        if (canView && summary != null)
          AnimatedOpacity(
            opacity: s.loading ? .45 : 1,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: s.loading,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppStatRow(
                    children: [
                      AppStatTile(
                        highlight: true,
                        icon: Icons.north_east_rounded,
                        label: category?.name ?? 'Total expenses',
                        value: money(summary.gross),
                        caption: range,
                      ),
                      AppStatTile(
                        icon: Icons.undo_rounded,
                        accent: scheme.primary,
                        label: 'Reversals',
                        value: money(summary.reversals),
                        caption: summary.reversals == 0
                            ? 'No reversals this period'
                            : 'Returned to accounts',
                      ),
                      AppStatTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Net spent',
                        value: money(summary.total),
                        caption: 'Expenses less reversals',
                      ),
                      AppStatTile(
                        icon: top == null
                            ? Icons.category_outlined
                            : expenseCategoryIcon(top.name),
                        accent: scheme.error,
                        label: 'Top category',
                        value: top == null ? '—' : money(top.total),
                        caption: top == null
                            ? 'No spending yet'
                            : summary.total <= 0
                            ? top.name
                            : '${top.name} · ${(top.total / summary.total * 100).round()}% of spending',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppStatRow(
                    children: [
                      AppStatTile(
                        icon: Icons.payments_outlined,
                        label: 'Net cash spent',
                        value: summary.methodBreakdownAvailable
                            ? money(summary.cash)
                            : '—',
                        caption: 'After cash reversals',
                      ),
                      AppStatTile(
                        icon: Icons.account_balance_outlined,
                        label: 'Net bank spent',
                        value: summary.methodBreakdownAvailable
                            ? money(summary.bank)
                            : '—',
                        caption: 'UPI, card and bank transfers',
                      ),
                      () {
                        final (label, value) = financeAverage(
                          summary.total,
                          f.anchor,
                          f.yearly,
                          catalog!.today,
                        );
                        return AppStatTile(
                          icon: Icons.show_chart_rounded,
                          label: '$label (net)',
                          value: money(value),
                          caption: f.yearly
                              ? 'Across elapsed months'
                              : 'Across elapsed days',
                        );
                      }(),
                    ],
                  ),
                  const SizedBox(height: 32),
                  AppTwoPane(
                    primary: [
                      AppPanel(
                        title: 'Trend',
                        subtitle: f.yearly
                            ? 'Select a month to explore it'
                            : range,
                        child: AppCard(
                          child: Column(
                            children: [
                              ExpenseChart(
                                values: summary.bars(f),
                                selectedDay: s.selectedDay,
                                onDay: cubit.selectDay,
                                onClearDay: () => cubit.selectDay(null),
                                filter: f,
                                currency: catalog!.currency,
                                onMonth: (m) => cubit.setFilter(
                                  f.copy(
                                    anchor: DateTime(f.anchor.year, m),
                                    yearly: false,
                                  ),
                                ),
                              ),
                              if (!f.yearly) ...[
                                const Divider(height: 26),
                                ExpenseDailyBreakdown(
                                  summary: summary,
                                  anchor: f.anchor,
                                  currency: catalog.currency,
                                  selectedDay: s.selectedDay,
                                  onDay: cubit.selectDay,
                                  onClearDay: () => cubit.selectDay(null),
                                  onAddExpense:
                                      catalog.canExpense &&
                                          s.selectedDay != null
                                      ? () => addExpense(
                                          date: DateTime(
                                            f.anchor.year,
                                            f.anchor.month,
                                            s.selectedDay!,
                                            12,
                                          ),
                                        )
                                      : null,
                                  onDownloadDay: s.selectedDay == null
                                      ? null
                                      : exportDay,
                                  exporting: s.exporting,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      AppPanel(
                        title: s.selectedDay == null
                            ? 'All expenses'
                            : 'Selected day’s expenses',
                        subtitle:
                            '${s.items.length} shown${s.next != null ? ' · more available' : ''}',
                        child: s.items.isEmpty
                            ? FinanceEmptyCard(
                                icon: Icons.receipt_long_outlined,
                                title: s.selectedDay == null
                                    ? 'No expenses in this period'
                                    : 'No expenses on this day',
                                message: s.selectedDay == null
                                    ? 'Choose another period or add an expense.'
                                    : 'Select another day or show all days.',
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  FinanceDayGroups<ExpenseItem>(
                                    items: s.items,
                                    dayOf: (i) => i.date,
                                    amountOf: (i) => i.amount,
                                    currency: catalog.currency,
                                    today: catalog.today,
                                    builder: (item) => ExpenseTile(
                                      wide: true,
                                      item: item,
                                      currency: catalog.currency,
                                      onTap: () => c.push(
                                        '/expenses/${item.originalId ?? item.id}',
                                      ),
                                    ),
                                  ),
                                  if (s.next != null)
                                    Center(
                                      child: OutlinedButton(
                                        onPressed: s.more ? null : cubit.more,
                                        child: Text(
                                          s.more ? 'Loading…' : 'Load more',
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ],
                    secondary: [
                      AppPanel(
                        title: 'By category',
                        subtitle: f.categoryId == null
                            ? 'Select a category to filter'
                            : 'Filtered to ${category?.name ?? 'one category'}',
                        child: summary.categories.isEmpty
                            ? const FinanceEmptyCard(
                                icon: Icons.pie_chart_outline,
                                title: 'No categories yet',
                                message:
                                    'Spending by category appears once recorded.',
                              )
                            : FinanceShareList(
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
                      ),
                      AppPanel(
                        title: 'Reports',
                        child: FinanceExportCard(
                          note:
                              'Choose the period and category for this download.',
                          exporting: s.exporting,
                          onExport: (format) => export(format: format),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ExpenseCategoryNameDialog extends StatefulWidget {
  const _ExpenseCategoryNameDialog({this.category});
  final ExpenseCategory? category;

  @override
  State<_ExpenseCategoryNameDialog> createState() =>
      _ExpenseCategoryNameDialogState();
}

class _ExpenseCategoryNameDialogState
    extends State<_ExpenseCategoryNameDialog> {
  late final controller = TextEditingController(text: widget.category?.name);
  bool invalid = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.category == null ? 'New category' : 'Edit category'),
    content: TextField(
      controller: controller,
      maxLength: 80,
      autofocus: true,
      decoration: InputDecoration(
        labelText: 'Category name',
        errorText: invalid ? 'Name must be at least 2 characters.' : null,
      ),
      onChanged: (_) {
        if (invalid) setState(() => invalid = false);
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final name = controller.text.trim();
          if (name.length < 2) {
            setState(() => invalid = true);
            return;
          }
          Navigator.pop(context, name);
        },
        child: const Text('Save'),
      ),
    ],
  );
}

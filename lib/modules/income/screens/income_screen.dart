import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../accounts/models/accounts_models.dart';
import '../../accounts/widgets/accounts_overview_widgets.dart';
import '../../accounts/widgets/accounts_widgets.dart';
import '../../accounts/widgets/finance_ledger_widgets.dart';
import '../../accounts/widgets/finance_period_widgets.dart';
import '../../expenses/widgets/finance_desktop_widgets.dart';
import '../cubit/income_cubit.dart';
import '../cubit/income_state.dart';
import '../models/income_models.dart';
import '../widgets/income_desktop_widgets.dart';
import '../widgets/income_daily_breakdown.dart';
import '../widgets/income_report_sheet.dart';

IconData incomeSourceIcon(String? id, String name) {
  if (id == incomeBookings) return Icons.event_available_outlined;
  if (id == incomeAdmissions) return Icons.school_outlined;
  final n = name.toLowerCase();
  if (n.contains('sponsor')) return Icons.handshake_outlined;
  if (n.contains('event')) return Icons.celebration_outlined;
  if (n.contains('rent')) return Icons.home_work_outlined;
  if (n.contains('coach')) return Icons.sports_outlined;
  if (n.contains('food')) return Icons.restaurant_outlined;
  if (n.contains('merch')) return Icons.storefront_outlined;
  if (n.contains('park')) return Icons.local_parking_outlined;
  return Icons.payments_outlined;
}

class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});
  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  late final cubit = getIt<IncomeCubit>(param1: context.read<WorkspaceCubit>())
    ..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> export() async {
    if (cubit.state.catalog?.canView != true || cubit.state.exporting) return;
    final selection = await showAdaptiveSheet<IncomeReportSelection>(
      context: context,
      scrollable: false,
      maxWidth: 560,
      builder: (c) => IncomeReportSheet(
        initialAnchor: cubit.state.filter.anchor,
        categories: cubit.state.categories,
      ),
    );
    if (selection == null || !mounted) return;
    showMessage(context, 'Preparing the income report…');
    await cubit.export(selection.format, filter: selection.filter);
  }

  Future<void> categoryDialog({IncomeCategory? category}) async {
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
    await showAdaptiveSheet<void>(
      context: context,
      scrollable: false,
      builder: (c) => AdaptiveSheetBody(
        builder: (c, controller, shrink) =>
            BlocBuilder<IncomeCubit, IncomeState>(
              bloc: cubit,
              builder: (c, s) => ListView(
                controller: controller,
                shrinkWrap: shrink,
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Income categories',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Booking and admission payments are grouped automatically.',
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Add category'),
                    onTap: () => categoryDialog(),
                  ),
                  for (final category in s.categories)
                    ListTile(
                      leading: Icon(
                        incomeSourceIcon(category.id, category.name),
                      ),
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
      builder: (c) => BlocBuilder<IncomeCubit, IncomeState>(
        bloc: cubit,
        builder: (c, s) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter income', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 20),
              if (s.catalog != null) ...[
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
                  label: 'Received into',
                  value: s.filter.accountId ?? '',
                  items: [
                    const PickerItem('', 'All accounts'),
                    ...s.catalog!.accounts.map((a) => PickerItem(a.id, a.name)),
                  ],
                  onChanged: (v) => cubit.setFilter(
                    s.filter.copy(accountId: v, clearAccount: v.isEmpty),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              AppButton(label: 'Done', onPressed: () => Navigator.pop(c)),
            ],
          ),
        ),
      ),
    );
  }

  Widget sourceChips(IncomeState s) {
    final options = <(String?, String)>[
      (null, 'All sources'),
      (incomeBookings, 'Bookings'),
      (incomeAdmissions, 'Admissions'),
      for (final category in s.categories)
        (
          category.id,
          category.active ? category.name : '${category.name} · archived',
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (id, label) in options) ...[
            ChoiceChip(
              key: ValueKey('income-source-${id ?? 'all'}'),
              label: Text(label),
              selected: s.filter.source == id,
              onSelected: (_) => cubit.setFilter(
                s.filter.copy(source: id, clearSource: id == null),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Future<void> addIncome({DateTime? date}) async {
    await context.push('/accounts/entry/income', extra: date);
    await cubit.load(refresh: true);
  }

  Future<void> exportDay() async {
    final state = cubit.state, day = cubit.state.selectedDay;
    if (day == null || state.exporting || state.catalog?.canView != true) {
      return;
    }
    final filter = state.filter.copy(day: day);
    final format = await showFinanceOptions(
      context,
      title: 'Download ${filter.from} income',
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

  @override
  Widget build(BuildContext context) => BlocConsumer<IncomeCubit, IncomeState>(
    bloc: cubit,
    listener: (c, s) {
      if (s.message != null) showMessage(c, s.message!);
    },
    builder: (c, s) {
      if (isDesktopWidth(c)) return _desktop(c, s);
      final catalog = s.catalog, f = s.filter, summary = s.summary;
      final filtered =
          (f.businessId != null ? 1 : 0) + (f.accountId != null ? 1 : 0);
      return AppPage(
        title: 'Income',
        back: true,
        showAppBar: true,
        compactHeader: true,
        scrollId: 'income',
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
        ],
        floatingActionButton: catalog?.canIncome == true
            ? FloatingActionButton.extended(
                onPressed: () => addIncome(),
                icon: const Icon(Icons.add),
                label: const Text('Add income'),
              )
            : null,
        children: [
          if (s.loading && summary == null)
            const AppLoadingState(initial: true, label: 'Loading income…'),
          if (s.error != null)
            AppErrorWidget(
              message: s.error!,
              onRetry: () => cubit.load(refresh: true),
            ),
          if (catalog != null && !catalog.canView)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'You can record extra income. Ask the owner for finance access to view reports and income history.',
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
                  tooltip: 'Filter income',
                  active: filtered > 0,
                  onTap: filters,
                ),
              ],
            ),
            sourceChips(s),
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
                        label: s.sourceName ?? 'Total income',
                        amount: summary.total,
                        currency: catalog!.currency,
                        subtitle:
                            '${summary.count} ${summary.count == 1 ? 'entry' : 'entries'} · ${financeRangeLabel(FinanceFilter(from: f.from, until: f.until))}',
                        stats: [
                          if (summary.refunds != 0) ...[
                            ('Refunds', summary.refunds),
                            ('Net after refunds', summary.net),
                          ],
                          (
                            'Net cash received',
                            summary.methodBreakdownAvailable
                                ? summary.cash
                                : null,
                          ),
                          (
                            'Net bank received',
                            summary.methodBreakdownAvailable
                                ? summary.bank
                                : null,
                          ),
                          () {
                            final (label, value) = financeAverage(
                              summary.net,
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
                        child: Column(
                          children: [
                            FinancePeriodChart(
                              values: summary.bars(f),
                              selectedDay: s.selectedDay,
                              onDay: cubit.selectDay,
                              anchor: f.anchor,
                              yearly: f.yearly,
                              currency: catalog.currency,
                              yearlyTitle:
                                  'Monthly income · tap a month to explore',
                              monthlyTitle: 'Daily income',
                              onMonth: (m) => cubit.setFilter(
                                f.copy(
                                  anchor: DateTime(f.anchor.year, m),
                                  yearly: false,
                                ),
                              ),
                            ),
                            if (!f.yearly)
                              IncomeDailyBreakdown(
                                summary: summary,
                                anchor: f.anchor,
                                currency: catalog.currency,
                                selectedDay: s.selectedDay,
                                onDay: cubit.selectDay,
                                onClearDay: () => cubit.selectDay(null),
                                onAddIncome:
                                    catalog.canIncome && s.selectedDay != null
                                    ? () => addIncome(
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
                        ),
                      ),
                      FinanceSection(
                        s.selectedDay == null
                            ? 'All income'
                            : 'Selected day’s income',
                      ),
                      if (s.items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.savings_outlined, size: 36),
                                SizedBox(height: 12),
                                Text(
                                  s.selectedDay == null
                                      ? 'No income in this period'
                                      : 'No income on this day',
                                ),
                                SizedBox(height: 6),
                                Text(
                                  s.selectedDay == null
                                      ? 'Choose another period or add income.'
                                      : 'Select another day or show all days.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        FinanceDayGroups<IncomeItem>(
                          items: s.items,
                          dayOf: (i) => i.entry.date,
                          currency: catalog.currency,
                          today: catalog.today,
                          builder: (i) => FinanceTransactionTile(
                            entry: i.entry,
                            currency: catalog.currency,
                            label: i.refund ? '${i.source} refund' : i.source,
                            onTap: () =>
                                c.push('/accounts/transaction', extra: i.entry),
                          ),
                        ),
                      if (s.next != null)
                        Center(
                          child: TextButton(
                            onPressed: s.more ? null : cubit.more,
                            child: Text(s.more ? 'Loading…' : 'Load more'),
                          ),
                        ),
                      if (summary.sources.isNotEmpty) ...[
                        const FinanceSection('By source'),
                        FinanceBreakdown(
                          shares: [
                            for (final source in summary.sources)
                              FinanceShare(
                                source.id,
                                source.name,
                                source.total,
                                incomeSourceIcon(source.id, source.name),
                              ),
                          ],
                          currency: catalog.currency,
                          selected: f.source,
                          onSelect: (id) => cubit.setFilter(f.copy(source: id)),
                        ),
                      ],
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
  // the source breakdown.
  Widget _desktop(BuildContext c, IncomeState s) {
    final catalog = s.catalog, f = s.filter, summary = s.summary;
    final scheme = Theme.of(c).colorScheme;
    final filtered =
        (f.businessId != null ? 1 : 0) + (f.accountId != null ? 1 : 0);
    final range = financeRangeLabel(
      FinanceFilter(from: f.from, until: f.until),
    );
    final canView = catalog?.canView == true;
    String money(int n) => financeMoney(n, catalog?.currency ?? 'INR');
    return AppPage(
      title: 'Income',
      back: true,
      scrollId: 'income',
      maxWidth: 1240,
      header: FinanceDesktopHeader(
        title: 'Income',
        subtitle: canView
            ? 'Bookings, admissions and extra income · $range'
            : 'Record extra income for your organization',
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
                      tooltip: 'Filter income',
                      active: filtered > 0,
                      onTap: filters,
                    ),
                  ],
                )
              : null,
          actions: [
            if (catalog?.canIncome == true)
              FilledButton.icon(
                onPressed: () => addIncome(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add income'),
              ),
          ],
        ),
        if (canView) sourceChips(s),
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
          const AppLoadingState(initial: true, label: 'Loading income…'),
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
                'You can record extra income. Ask the owner for finance access to view reports and income history.',
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
                        icon: Icons.south_west_rounded,
                        label: s.sourceName ?? 'Total income',
                        value: money(summary.total),
                        caption:
                            '${summary.count} ${summary.count == 1 ? 'entry' : 'entries'} · $range',
                      ),
                      AppStatTile(
                        icon: Icons.undo_rounded,
                        accent: scheme.error,
                        label: 'Refunds',
                        value: money(summary.refunds),
                        caption: summary.refunds == 0
                            ? 'No refunds this period'
                            : 'Returned to customers',
                      ),
                      AppStatTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Net after refunds',
                        value: money(summary.net),
                        caption: 'Income less refunds',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppStatRow(
                    children: [
                      AppStatTile(
                        icon: Icons.payments_outlined,
                        label: 'Net cash received',
                        value: summary.methodBreakdownAvailable
                            ? money(summary.cash)
                            : '—',
                        caption: 'After cash refunds',
                      ),
                      AppStatTile(
                        icon: Icons.account_balance_outlined,
                        label: 'Net bank received',
                        value: summary.methodBreakdownAvailable
                            ? money(summary.bank)
                            : '—',
                        caption: 'UPI, card and bank transfers',
                      ),
                      () {
                        final (label, value) = financeAverage(
                          summary.net,
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
                              FinancePeriodChart(
                                values: summary.bars(f),
                                selectedDay: s.selectedDay,
                                onDay: cubit.selectDay,
                                anchor: f.anchor,
                                yearly: f.yearly,
                                currency: catalog!.currency,
                                yearlyTitle:
                                    'Monthly income · tap a month to explore',
                                monthlyTitle: 'Daily income',
                                onMonth: (m) => cubit.setFilter(
                                  f.copy(
                                    anchor: DateTime(f.anchor.year, m),
                                    yearly: false,
                                  ),
                                ),
                              ),
                              if (!f.yearly)
                                IncomeDailyBreakdown(
                                  summary: summary,
                                  anchor: f.anchor,
                                  currency: catalog.currency,
                                  selectedDay: s.selectedDay,
                                  onDay: cubit.selectDay,
                                  onClearDay: () => cubit.selectDay(null),
                                  onAddIncome:
                                      catalog.canIncome && s.selectedDay != null
                                      ? () => addIncome(
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
                          ),
                        ),
                      ),
                      AppPanel(
                        title: s.selectedDay == null
                            ? 'All income'
                            : 'Selected day’s income',
                        subtitle:
                            '${s.items.length} shown${s.next != null ? ' · more available' : ''}',
                        child: s.items.isEmpty
                            ? FinanceEmptyCard(
                                icon: Icons.savings_outlined,
                                title: s.selectedDay == null
                                    ? 'No income in this period'
                                    : 'No income on this day',
                                message: s.selectedDay == null
                                    ? 'Choose another period or add income.'
                                    : 'Select another day or show all days.',
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  FinanceDayGroups<IncomeItem>(
                                    items: s.items,
                                    dayOf: (i) => i.entry.date,
                                    currency: catalog.currency,
                                    today: catalog.today,
                                    builder: (i) => IncomeLedgerRow(
                                      item: i,
                                      currency: catalog.currency,
                                      icon: incomeSourceIcon(
                                        i.entry.kind == 'booking_collection'
                                            ? incomeBookings
                                            : null,
                                        i.source,
                                      ),
                                      onTap: () => c.push(
                                        '/accounts/transaction',
                                        extra: i.entry,
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
                        title: 'By source',
                        subtitle: f.source == null
                            ? 'Select a source to filter'
                            : 'Filtered to ${s.sourceName ?? 'one source'}',
                        child: summary.sources.isEmpty
                            ? const FinanceEmptyCard(
                                icon: Icons.pie_chart_outline,
                                title: 'No sources yet',
                                message: 'Income sources appear once recorded.',
                              )
                            : FinanceShareList(
                                shares: [
                                  for (final source in summary.sources)
                                    FinanceShare(
                                      source.id,
                                      source.name,
                                      source.total,
                                      incomeSourceIcon(source.id, source.name),
                                    ),
                                ],
                                currency: catalog.currency,
                                selected: f.source,
                                onSelect: (id) =>
                                    cubit.setFilter(f.copy(source: id)),
                              ),
                      ),
                      AppPanel(
                        title: 'Reports',
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Download a complete month or year, for all income or one source.',
                              ),
                              const SizedBox(height: 14),
                              AppButton(
                                key: const ValueKey('income-report-open'),
                                label: 'Choose report',
                                icon: Icons.download_outlined,
                                busy: s.exporting,
                                busyLabel: 'Preparing report…',
                                onPressed: export,
                              ),
                            ],
                          ),
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

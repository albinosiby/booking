import '../widgets/monthly_finance_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/accounts_cubits.dart';
import '../models/accounts_models.dart';
import '../models/accounts_screen_models.dart';
import '../widgets/accounts_dashboard_widgets.dart';
import '../widgets/accounts_overview_widgets.dart';
import '../widgets/accounts_widgets.dart';
import '../../staff_cash/widgets/staff_cash_owner_section.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, this.back = false});
  final bool back;
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late final cubit = getIt<AccountsOverviewCubit>(
    param1: context.read<WorkspaceCubit>(),
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> _open(String route, {Object? extra}) async {
    await context.push(route, extra: extra);
    if (mounted) cubit.refresh();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AccountsOverviewCubit, AccountsOverviewModel>(
        bloc: cubit,
        builder: (c, s) {
          final catalog = s.catalog;
          final actions = [
            if (catalog?.canExpense == true)
              FinanceAction(
                Icons.shopping_cart_outlined,
                'Expense',
                () => _open('/expenses/new'),
              ),
            if (catalog?.canIncome == true)
              FinanceAction(
                Icons.add_card_outlined,
                'Income',
                () => _open('/accounts/entry/income'),
              ),
            if (catalog?.canManage == true)
              FinanceAction(
                Icons.swap_horiz,
                'Transfer',
                () => _open('/accounts/entry/transfer'),
              ),
            if (catalog != null && catalog.canManage != true)
              FinanceAction(
                Icons.account_balance_wallet_outlined,
                'My cash',
                () => _open('/staff-cash'),
              ),
            if (catalog?.canView == true)
              FinanceAction(
                Icons.download_outlined,
                'Reports',
                () => c.push('/accounts/reports', extra: s.filter),
              ),
          ];
          return LayoutBuilder(
            builder: (c, box) => box.maxWidth >= 1000
                ? _dashboard(c, s, actions)
                : _column(c, s, actions),
          );
        },
      );

  // Mobile and narrow windows: one scrolling column.
  Widget _column(
    BuildContext c,
    AccountsOverviewModel s,
    List<FinanceAction> actions,
  ) {
    final catalog = s.catalog, o = s.overview;
    final currency = catalog?.currency ?? 'INR';
    String money(int n) => financeMoney(n, currency);
    Widget dim(List<Widget> children) => _dim(s, children);
    return AppPage(
      title: 'Accounts',
      back: widget.back,
      showAppBar: true,
      compactHeader: true,
      maxWidth: 760,
      actions: [
        IconButton(
          tooltip: 'Refresh accounts',
          onPressed: s.loading ? null : cubit.refresh,
          icon: const Icon(Icons.refresh),
        ),
        if (catalog?.canManage == true)
          IconButton(
            tooltip: 'Account settings',
            onPressed: () => c.push('/accounts/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
      ],
      children: [
        if (catalog != null && catalog.canView) ...[
          FinanceFilterBar(
            catalog: catalog,
            filter: s.filter,
            onChanged: (f) => cubit.load(filter: f),
          ),
          // Fixed height so the page does not jump while loading.
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 13),
            child: SizedBox(
              height: 3,
              child: s.loading && o != null
                  ? const LinearProgressIndicator(minHeight: 3)
                  : null,
            ),
          ),
        ],
        if (s.loading && o == null) ...[
          const AppLoadingState(initial: true, label: 'Loading accounts…'),
          const SizedBox(height: 12),
        ],
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.refresh),
        if (o != null)
          dim([
            FinanceNetCard(
              totals: o.selected,
              period: financeRangeLabel(s.filter),
              currency: currency,
            ),
            const SizedBox(height: 12),
            FinanceDuesBanner(amount: o.outstanding, currency: currency),
          ]),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          FinanceQuickActions(actions),
        ],
        if (catalog != null && !catalog.canView && !s.loading)
          const AppEmptyState(
            title: 'Record payments with bookings',
            message:
                'Your access allows assigned payment or expense entries. Ask the owner for access to financial reports.',
          ),
        if (o != null)
          dim([
            const FinanceSection("Today's collection"),
            FinanceMethodSplit(
              title: 'Booking collections today',
              total: o.today.collections,
              methods: o.today.methods,
              currency: currency,
            ),
            if (catalog?.canManage == true)
              StaffCashOwnerSection(currency: currency),
            FinanceSection(
              'Income by payment method',
              action: 'View all',
              onTap: () => c.push('/income'),
            ),
            FinanceMethodSplit(
              title: 'Total income · collections and extra income',
              total: o.selected.income,
              methods: o.selected.allMethods,
              currency: currency,
              footer: [
                FinanceAmountRow('Extra income', money(o.selected.extra)),
                FinanceAmountRow('Expenses', money(o.selected.expenses)),
                FinanceAmountRow('Refunds', money(o.selected.refunds)),
              ],
            ),
            const FinanceSection('Income & expenses'),
            MonthlyFinancePanel(
              model: s,
              currency: catalog!.currency,
              onMonth: cubit.selectMonth,
            ),
            if (catalog.canManage) ...[
              FinanceSection(
                'Your accounts',
                action: 'Manage',
                onTap: () => c.push('/accounts/settings'),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'Recorded balances · Whole organization',
                  style: Theme.of(c).textTheme.bodySmall,
                ),
              ),
              FinanceAccountsList(
                accounts: o.accounts.where((a) => a.active).toList(),
                currency: currency,
                onTap: (a) => c.push(
                  '/accounts/transactions',
                  extra: FinanceFilter(
                    from: s.filter.from,
                    until: s.filter.until,
                    accountId: a.id,
                  ),
                ),
              ),
            ],
            FinanceSection(
              'Recent activity',
              action: 'View all',
              onTap: () => c.push('/accounts/transactions', extra: s.filter),
            ),
            if (s.transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No transactions in this period.')),
              )
            else
              FinanceTransactionGroups(
                entries: s.transactions,
                currency: currency,
                today: catalog.today,
                onTap: (e) => c.push('/accounts/transaction', extra: e),
              ),
            const SizedBox(height: 24),
          ]),
      ],
    );
  }

  // Previous figures stay readable but faded while a new period loads.
  Widget _dim(AccountsOverviewModel s, List<Widget> children) =>
      AnimatedOpacity(
        opacity: s.loading ? .45 : 1,
        duration: const Duration(milliseconds: 150),
        child: IgnorePointer(
          ignoring: s.loading,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );

  // Wide web windows: headline figures, then a two-column dashboard.
  Widget _dashboard(
    BuildContext c,
    AccountsOverviewModel s,
    List<FinanceAction> actions,
  ) {
    final catalog = s.catalog, o = s.overview;
    final currency = catalog?.currency ?? 'INR';
    final scheme = Theme.of(c).colorScheme;
    String money(int n) => financeMoney(n, currency);
    final period = financeRangeLabel(s.filter);
    return AppPage(
      title: 'Accounts',
      back: widget.back,
      maxWidth: 1240,
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Accounts', style: Theme.of(c).textTheme.headlineLarge),
                const SizedBox(height: 6),
                Text(
                  'Cash flow, collections and balances · $period',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: .65),
                  ),
                ),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: 'Refresh accounts',
            onPressed: s.loading ? null : cubit.refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (catalog?.canManage == true) ...[
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Account settings',
              onPressed: () => c.push('/accounts/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ],
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: catalog != null && catalog.canView
                  ? FinanceFilterBar(
                      catalog: catalog,
                      filter: s.filter,
                      onChanged: (f) => cubit.load(filter: f),
                    )
                  : const SizedBox.shrink(),
            ),
            if (actions.isNotEmpty) FinanceActionButtons(actions),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 18),
          child: SizedBox(
            height: 3,
            child: s.loading && o != null
                ? const LinearProgressIndicator(minHeight: 3)
                : null,
          ),
        ),
        if (s.loading && o == null) ...[
          const AppLoadingState(initial: true, label: 'Loading accounts…'),
          const SizedBox(height: 12),
        ],
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.refresh),
        if (catalog != null && !catalog.canView && !s.loading)
          const AppEmptyState(
            title: 'Record payments with bookings',
            message:
                'Your access allows assigned payment or expense entries. Ask the owner for access to financial reports.',
          ),
        if (o != null)
          _dim(s, [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: FinanceStatTile(
                      highlight: true,
                      icon: Icons.insights_rounded,
                      label: 'Net cash flow',
                      value: money(o.selected.net),
                      caption: period,
                      change: financeChange(o.selected.net, o.previous.net),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FinanceStatTile(
                      icon: Icons.south_west_rounded,
                      label: 'Income',
                      value: money(o.selected.income),
                      caption: 'Collections and extra income',
                      change: financeChange(
                        o.selected.income,
                        o.previous.income,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FinanceStatTile(
                      icon: Icons.north_east_rounded,
                      accent: scheme.error,
                      label: 'Out',
                      value: money(o.selected.expenses + o.selected.refunds),
                      caption: 'Expenses and refunds',
                      higherIsBetter: false,
                      change: financeChange(
                        o.selected.expenses + o.selected.refunds,
                        o.previous.expenses + o.previous.refunds,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FinanceStatTile(
                      icon: o.outstanding > 0
                          ? Icons.receipt_long_rounded
                          : Icons.check_circle_outline_rounded,
                      accent: o.outstanding > 0 ? financeAmber : null,
                      label: 'Booking dues',
                      value: money(o.outstanding),
                      caption: o.outstanding > 0
                          ? 'Outstanding at period end'
                          : 'No booking dues',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FinancePanel(
                        title: 'Income & expenses',
                        subtitle: 'Tap a month to see its breakdown',
                        child: MonthlyFinancePanel(
                          model: s,
                          currency: currency,
                          onMonth: cubit.selectMonth,
                        ),
                      ),
                      FinancePanel(
                        title: 'Recent activity',
                        action: 'View all',
                        onAction: () =>
                            c.push('/accounts/transactions', extra: s.filter),
                        child: s.transactions.isEmpty
                            ? const AppCard(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                    child: Text(
                                      'No transactions in this period.',
                                    ),
                                  ),
                                ),
                              )
                            : FinanceTransactionGroups(
                                entries: s.transactions,
                                currency: currency,
                                today: catalog!.today,
                                onTap: (e) =>
                                    c.push('/accounts/transaction', extra: e),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FinancePanel(
                        title: "Today's collection",
                        child: FinanceMethodSplit(
                          title: 'Booking collections today',
                          total: o.today.collections,
                          methods: o.today.methods,
                          currency: currency,
                        ),
                      ),
                      if (catalog?.canManage == true)
                        StaffCashOwnerSection(currency: currency),
                      FinancePanel(
                        title: 'Income by payment method',
                        action: 'View all',
                        onAction: () => c.push('/income'),
                        child: FinanceMethodSplit(
                          title: 'Total income · collections and extra income',
                          total: o.selected.income,
                          methods: o.selected.allMethods,
                          currency: currency,
                          footer: [
                            FinanceAmountRow(
                              'Extra income',
                              money(o.selected.extra),
                            ),
                            FinanceAmountRow(
                              'Expenses',
                              money(o.selected.expenses),
                            ),
                            FinanceAmountRow(
                              'Refunds',
                              money(o.selected.refunds),
                            ),
                          ],
                        ),
                      ),
                      if (catalog?.canManage == true)
                        FinancePanel(
                          title: 'Your accounts',
                          subtitle: 'Recorded balances · Whole organization',
                          action: 'Manage',
                          onAction: () => c.push('/accounts/settings'),
                          child: FinanceAccountsList(
                            accounts: o.accounts
                                .where((a) => a.active)
                                .toList(),
                            currency: currency,
                            onTap: (a) => c.push(
                              '/accounts/transactions',
                              extra: FinanceFilter(
                                from: s.filter.from,
                                until: s.filter.until,
                                accountId: a.id,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ]),
      ],
    );
  }
}

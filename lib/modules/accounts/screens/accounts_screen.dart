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
import '../widgets/accounts_overview_widgets.dart';
import '../widgets/accounts_widgets.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});
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
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AccountsOverviewCubit, AccountsOverviewModel>(
    bloc: cubit,
    builder: (c, s) {
      final catalog = s.catalog,
          o = s.overview,
          currency = catalog?.currency ?? 'INR';
      String money(int n) => financeMoney(n, currency);
      // Previous figures stay readable but faded while a new period loads.
      Widget dim(List<Widget> children) => AnimatedOpacity(
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
        if (catalog?.canView == true)
          FinanceAction(
            Icons.download_outlined,
            'Reports',
            () => c.push('/accounts/reports', extra: s.filter),
          ),
      ];
      return AppPage(
        title: 'Accounts',
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
    },
  );
}

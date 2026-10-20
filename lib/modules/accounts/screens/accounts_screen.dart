import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/accounts_cubits.dart';
import '../models/accounts_models.dart';
import '../models/accounts_screen_models.dart';
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
          if (catalog?.canView == true)
            IconButton(
              tooltip: 'Download reports',
              onPressed: () => c.push('/accounts/reports', extra: s.filter),
              icon: const Icon(Icons.download_outlined),
            ),
          if (catalog?.canManage == true)
            IconButton(
              tooltip: 'Account settings',
              onPressed: () => c.push('/accounts/settings'),
              icon: const Icon(Icons.account_balance_outlined),
            ),
        ],
        floatingActionButton:
            catalog != null && (catalog.canIncome || catalog.canManage)
            ? FloatingActionButton.extended(
                backgroundColor: Theme.of(c).colorScheme.primary,
                foregroundColor: Theme.of(c).colorScheme.onPrimary,
                onPressed: () => openFinanceActions(c, catalog),
                icon: const Icon(Icons.add),
                label: const Text('Add entry'),
              )
            : null,
        children: [
          if (catalog != null && catalog.canView) ...[
            FinanceScopePicker(
              catalog: catalog,
              business: s.filter.businessId,
              space: s.filter.spaceId,
              onChanged: (b, r) => cubit.load(filter: s.filter.scope(b, r)),
            ),
            const SizedBox(height: 12),
            FinancePeriodPicker(
              filter: s.filter,
              today: catalog.today,
              onChanged: (f) => cubit.load(filter: f),
            ),
          ],
          if (s.loading) ...[
            const SizedBox(height: 20),
            AppLoadingState(
              initial: s.overview == null,
              label: s.overview == null ? 'Loading accounts…' : null,
            ),
          ],
          if (s.error != null)
            AppErrorWidget(message: s.error!, onRetry: cubit.refresh),
          if (catalog != null && !catalog.canView && !s.loading)
            const AppEmptyState(
              title: 'Record payments with bookings',
              message:
                  'Your access allows assigned payment or expense entries. Ask the owner for access to financial reports.',
            ),
          if (o != null) ...[
            const FinanceSection("Today's collection"),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Theme.of(c).colorScheme.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: DefaultTextStyle(
                style: TextStyle(color: Theme.of(c).colorScheme.onPrimary),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BOOKING COLLECTIONS',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      money(o.today.collections),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 18,
                      runSpacing: 10,
                      children: [
                        for (final method in [
                          'cash',
                          'upi',
                          'card',
                          'bank_transfer',
                        ])
                          Text(
                            '${financeLabel(method)}  ${money(o.today.methods[method] ?? 0)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const FinanceSection('Selected period'),
            Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: FinanceStat(
                          'Total income',
                          money(o.selected.income),
                          icon: Icons.south_west,
                          note: 'Collections + extra income',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FinanceStat(
                          'Expenses',
                          money(o.selected.expenses),
                          icon: Icons.north_east,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: FinanceStat(
                          'Net cash flow',
                          money(o.selected.net),
                          icon: Icons.swap_vert,
                          note: 'After expenses and refunds',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FinanceStat(
                          'Booking dues',
                          money(o.outstanding),
                          icon: Icons.receipt_long_outlined,
                          note: 'Outstanding at period end',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const FinanceSection('Income by payment method'),
            AppCard(
              child: Column(
                children: [
                  for (final method in ['cash', 'upi', 'card', 'bank_transfer'])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Expanded(child: Text(financeLabel(method))),
                          Text(
                            money(o.selected.allMethods[method] ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  _amount('Extra income', money(o.selected.extra)),
                  _amount('Refunds', money(o.selected.refunds)),
                ],
              ),
            ),
            const FinanceSection('Income growth'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.growth == null
                        ? 'No previous-period baseline'
                        : '${o.growth! >= 0 ? '+' : ''}${o.growth!.toStringAsFixed(1)}%',
                    style: Theme.of(c).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Compared with ${o.previousFrom} → ${o.previousUntil}',
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                  if (o.trend.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    for (final t in o.trend) ...[
                      Row(
                        children: [
                          Expanded(child: Text(t.month)),
                          Text(money(t.income)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value:
                            o.trend
                                    .map((x) => x.income)
                                    .reduce((a, b) => a > b ? a : b) ==
                                0
                            ? 0
                            : (t.income /
                                      o.trend
                                          .map((x) => x.income)
                                          .reduce((a, b) => a > b ? a : b))
                                  .clamp(0, 1),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            ),
            if (catalog!.canManage) ...[
              FinanceSection(
                'Your accounts',
                action: 'Manage',
                onTap: () => c.push('/accounts/settings'),
              ),
              Text(
                'Recorded balances · Whole organization',
                style: Theme.of(c).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              for (final a in o.accounts.where((a) => a.active))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    onTap: () => c.push(
                      '/accounts/transactions',
                      extra: FinanceFilter(
                        from: s.filter.from,
                        until: s.filter.until,
                        accountId: a.id,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          a.kind == 'cash'
                              ? Icons.payments_outlined
                              : a.kind == 'clearing'
                              ? Icons.pending_outlined
                              : Icons.account_balance_outlined,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.name),
                              if (a.primary)
                                const Text(
                                  'Primary',
                                  style: TextStyle(
                                    color: AppColors.lime,
                                    fontSize: 12,
                                  ),
                                ),
                              if (a.kind == 'clearing')
                                const Text(
                                  'Allocate to the bank that received these funds',
                                  style: TextStyle(fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            money(a.balance ?? 0),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
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
              ),
            for (final e in s.transactions)
              FinanceTransactionTile(
                entry: e,
                currency: currency,
                onTap: () => c.push('/accounts/transaction', extra: e),
              ),
          ],
        ],
      );
    },
  );
  Widget _amount(String label, String amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(amount),
      ],
    ),
  );
}

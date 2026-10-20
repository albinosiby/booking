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

class AccountsTransactionsScreen extends StatefulWidget {
  const AccountsTransactionsScreen({super.key, required this.filter});
  final FinanceFilter filter;
  @override
  State<AccountsTransactionsScreen> createState() =>
      _AccountsTransactionsScreenState();
}

class _AccountsTransactionsScreenState
    extends State<AccountsTransactionsScreen> {
  late final cubit = getIt<TransactionsCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.filter,
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<TransactionsCubit, TransactionsModel>(
        bloc: cubit,
        builder: (c, s) => AppPage(
          title: 'Transactions',
          back: true,
          showAppBar: true,
          compactHeader: true,
          actions: [
            IconButton(
              tooltip: 'Change dates',
              onPressed: () async {
                final f = await chooseFinanceDates(c, s.filter);
                if (f != null) cubit.load(filter: f);
              },
              icon: const Icon(Icons.calendar_today_outlined),
            ),
            IconButton(
              tooltip: 'Refresh transactions',
              onPressed: cubit.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
          children: [
            Text(
              '${s.filter.from} → ${s.filter.until}',
              style: Theme.of(c).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: s.filter.query,
              decoration: const InputDecoration(
                labelText: 'Search reason, booking or customer',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onFieldSubmitted: (v) =>
                  cubit.load(filter: s.filter.search(v, s.filter.kind)),
            ),
            const SizedBox(height: 12),
            AppPicker(
              label: 'Transaction type',
              value: s.filter.kind ?? '',
              items: [
                const PickerItem('', 'All transactions'),
                ...[
                  'booking_collection',
                  'booking_refund',
                  'income',
                  'expense',
                  'transfer',
                  'reversal',
                ].map((v) => PickerItem(v, financeLabel(v))),
              ],
              onChanged: (v) => cubit.load(
                filter: s.filter.search(s.filter.query, v.isEmpty ? null : v),
              ),
            ),
            const SizedBox(height: 20),
            if (s.loading)
              AppLoadingState(
                initial: s.items.isEmpty,
                label: s.items.isEmpty ? 'Loading transactions…' : null,
              ),
            if (s.error != null)
              AppErrorWidget(message: s.error!, onRetry: cubit.refresh),
            if (!s.loading && s.error == null && s.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: Text('No matching transactions.')),
              ),
            for (final e in s.items)
              FinanceTransactionTile(
                entry: e,
                currency:
                    c
                        .read<WorkspaceCubit>()
                        .state
                        .data
                        .organization
                        ?.currency ??
                    'INR',
                onTap: () async {
                  await c.push('/accounts/transaction', extra: e);
                  if (mounted) cubit.load();
                },
              ),
            if (s.next != null)
              AppButton(
                label: 'Load more',
                secondary: true,
                busy: s.loading,
                onPressed: () => cubit.load(more: true),
              ),
          ],
        ),
      );
}

class AccountsTransactionScreen extends StatefulWidget {
  const AccountsTransactionScreen({super.key, required this.entry});
  final FinanceTransaction entry;
  @override
  State<AccountsTransactionScreen> createState() =>
      _AccountsTransactionScreenState();
}

class _AccountsTransactionScreenState extends State<AccountsTransactionScreen> {
  late final cubit = getIt<TransactionDetailsCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.entry,
  );
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<TransactionDetailsCubit, TransactionDetailsModel>(
    bloc: cubit,
    builder: (c, s) {
      final e = s.transaction, w = c.watch<WorkspaceCubit>().state.data;
      if (!cubit.authorized) {
        return AppPage(
          title: 'Transaction details',
          back: true,
          children: [
            AppErrorWidget(message: s.error ?? 'Your access changed.'),
          ],
        );
      }
      String money(int n) => financeMoney(n, w.organization?.currency ?? 'INR');
      return AppPage(
        title: 'Transaction details',
        back: true,
        showAppBar: true,
        compactHeader: true,
        children: [
          Text(money(e.amount), style: Theme.of(c).textTheme.headlineLarge),
          const SizedBox(height: 8),
          Text(financeLabel(e.kind)),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.reason, style: Theme.of(c).textTheme.titleMedium),
                const SizedBox(height: 12),
                Text(
                  'Category: ${e.category.isEmpty ? 'Booking' : e.category}',
                ),
                Text(
                  'Scope: ${e.business ?? 'Shared / organization'}${e.space == null ? '' : ' / ${e.space}'}',
                ),
                Text('Date: ${financeStamp(e.date)}'),
                Text('Recorded by: ${e.staff}'),
                if (e.reference.isNotEmpty) Text('Reference: ${e.reference}'),
              ],
            ),
          ),
          if (e.bookingId != null) ...[
            const FinanceSection('Booking'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.bookingReference ?? ''),
                  if (e.customer != null) Text(e.customer!),
                  if (e.tariff != null) Text('Tariff: ${money(e.tariff!)}'),
                  TextButton(
                    onPressed: () => c.push('/booking/${e.bookingId}'),
                    child: const Text('Open booking'),
                  ),
                ],
              ),
            ),
          ],
          const FinanceSection('Account movements'),
          for (final l in e.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.accountName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text('${financeLabel(l.method)} · ${money(l.amount)}'),
                  ],
                ),
              ),
            ),
          if (s.error != null) AppErrorWidget(message: s.error!),
          if (s.reversed)
            const Text(
              'Reversal recorded. The original entry remains in history.',
            ),
          if (w.isOwner &&
              ['income', 'expense', 'transfer'].contains(e.kind) &&
              !s.reversed)
            AppButton(
              label: 'Reverse entry',
              secondary: true,
              busy: s.busy,
              onPressed: () async {
                final input = TextEditingController();
                final reason = await showDialog<String>(
                  context: c,
                  builder: (d) => AlertDialog(
                    title: const Text('Reverse this entry?'),
                    content: TextField(
                      controller: input,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Reason for correction',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {
                          if (input.text.trim().length >= 2) {
                            Navigator.pop(d, input.text.trim());
                          }
                        },
                        child: const Text('Record reversal'),
                      ),
                    ],
                  ),
                );
                input.dispose();
                if (reason != null) cubit.reverse(reason);
              },
            ),
        ],
      );
    },
  );
}

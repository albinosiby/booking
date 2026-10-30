import 'package:eden_booking/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/staff_cash_cubits.dart';
import '../widgets/staff_cash_widgets.dart';

/// Personal payment activity and the current cash balance owed to/from the owner.
class StaffCashScreen extends StatefulWidget {
  const StaffCashScreen({super.key, this.asTab = false});
  final bool asTab;
  @override
  State<StaffCashScreen> createState() => _StaffCashScreenState();
}

class _StaffCashScreenState extends State<StaffCashScreen> {
  late final cubit = getIt<StaffCashCubit>(
    param1: context.read<WorkspaceCubit>(),
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> _pickDate(String current, String today) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(current),
      firstDate: DateTime(2020),
      lastDate: DateTime.parse(today),
    );
    if (d != null && mounted) {
      cubit.load(
        date:
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
    }
  }

  Widget amounts(
    List<(String, int)> entries,
    String currency, {
    double minimumWidth = 150,
  }) => LayoutBuilder(
    builder: (context, box) {
      final columns = (box.maxWidth / minimumWidth).floor().clamp(
        1,
        entries.length < 4 ? entries.length : 4,
      );
      final width = (box.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final entry in entries)
            SizedBox(
              width: width,
              child: StaffCashAmountTile(entry.$1, entry.$2, currency),
            ),
        ],
      );
    },
  );

  Widget heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<WorkspaceCubit>().state.data;
    final currency = workspace.organization?.currency ?? 'INR';
    return BlocBuilder<StaffCashCubit, StaffCashState>(
      bloc: cubit,
      builder: (c, s) {
        final d = s.day;
        return AppPage(
          title: widget.asTab ? 'Payments' : 'My collections',
          subtitle: 'Your collections and cash handovers.',
          back: !widget.asTab,
          showAppBar: true,
          compactHeader: true,
          maxWidth: 1200,
          scrollId: 'staff-payments',
          actions: [
            if (workspace.hasPermission('view_finance'))
              IconButton(
                tooltip: 'Accounts and reports',
                onPressed: () => context.push('/accounts/overview'),
                icon: const Icon(Icons.assessment_outlined),
              ),
            IconButton(
              tooltip: 'Choose collection date',
              onPressed: d == null || s.loading
                  ? null
                  : () => _pickDate(d.date, d.today),
              icon: const Icon(Icons.calendar_today_outlined),
            ),
            IconButton(
              tooltip: 'Refresh payments',
              onPressed: s.loading ? null : () => cubit.load(date: d?.date),
              icon: const Icon(Icons.refresh),
            ),
          ],
          slivers: d == null
              ? null
              : [
                  SliverList.builder(
                    itemCount: d.transactions.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppCard(
                        child: StaffCashTransactionTile(
                          item: d.transactions[index],
                          currency: currency,
                        ),
                      ),
                    ),
                  ),
                  if (d.nextCursor != null)
                    SliverToBoxAdapter(
                      child: TextButton.icon(
                        key: const ValueKey('staff-payments-more'),
                        onPressed: s.loading || s.loadingMore
                            ? null
                            : () => cubit.loadMore(),
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load more activity'),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: heading('Confirmed handovers · all dates'),
                  ),
                  if (d.settlements.isEmpty)
                    const SliverToBoxAdapter(
                      child: AppEmptyState(
                        showCard: false,
                        title: 'No handovers yet',
                        message:
                            'Handovers appear here after the owner confirms receiving or giving cash.',
                      ),
                    ),
                  SliverList.builder(
                    itemCount: d.settlements.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppCard(
                        child: StaffCashSettlementTile(
                          item: d.settlements[index],
                          currency: currency,
                          personal: true,
                        ),
                      ),
                    ),
                  ),
                  if (d.nextSettlementCursor != null)
                    SliverToBoxAdapter(
                      child: TextButton.icon(
                        key: const ValueKey('staff-handovers-more'),
                        onPressed: s.loading || s.loadingMore
                            ? null
                            : () => cubit.loadMore(settlements: true),
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load more handovers'),
                      ),
                    ),
                  if (s.loadingMore)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                ],
          children: [
            if (s.loading && d == null)
              const AppLoadingState(initial: true, label: 'Loading payments…'),
            if (s.error != null) ...[
              AppErrorWidget(
                message: s.error!,
                onRetry: () => cubit.load(date: d?.date),
              ),
              if (d != null)
                const Text(
                  'Showing previously loaded amounts. Refresh to confirm the current balance.',
                ),
            ],
            if (d != null) ...[
              if (s.loading) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              StaffCashHoldingCard(
                holdingMinor: d.holdingMinor,
                currency: currency,
              ),
              const SizedBox(height: 12),
              amounts(
                [
                  ('Given to owner · all time', d.handedOverMinor),
                ],
                currency,
                minimumWidth: 230,
              ),
              const SizedBox(height: 12),
              const Text(
                'The owner confirms each cash handover. Digital payments received directly by the business are excluded from cash to hand over.',
              ),
              heading('Collections on ${d.date}'),
              amounts([
                ('Total collected', d.collectedMinor),
                ('Cash', d.cashMinor),
                ('UPI', d.upiMinor),
                ('Card', d.cardMinor),
                ('Bank transfer', d.bankTransferMinor),
                ('Refunds', d.refundedMinor),
                ('Expenses paid', d.expensesMinor),
              ], currency),
              heading('Your payment activity'),
              if (d.transactions.isEmpty)
                const AppEmptyState(
                  showCard: false,
                  title: 'No payment activity',
                  message:
                      'Your payments, refunds and expenses for this date will appear here.',
                ),
            ],
          ],
        );
      },
    );
  }
}

import 'package:eden_booking/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../di/injection.dart';
import '../../accounts/models/accounts_models.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/staff_cash_cubits.dart';
import '../widgets/staff_cash_widgets.dart';

/// Staff payments dashboard: today's collections, cash to hand over, day's transactions.
class StaffCashScreen extends StatefulWidget {
  const StaffCashScreen({super.key});
  @override
  State<StaffCashScreen> createState() => _StaffCashScreenState();
}

class _StaffCashScreenState extends State<StaffCashScreen> {
  late final cubit = getIt<StaffCashCubit>()..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> _pickDate(String current) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      cubit.load(
        date:
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        context.watch<WorkspaceCubit>().state.data.organization?.currency ??
        'INR';
    return BlocBuilder<StaffCashCubit, StaffCashState>(
      bloc: cubit,
      builder: (c, s) {
        final d = s.day;
        return AppPage(
          title: 'My collections',
          back: true,
          showAppBar: true,
          compactHeader: true,
          actions: [
            IconButton(
              tooltip: 'Choose date',
              onPressed: d == null ? null : () => _pickDate(d.date),
              icon: const Icon(Icons.calendar_today_outlined),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: s.loading ? null : () => cubit.load(date: d?.date),
              icon: const Icon(Icons.refresh),
            ),
          ],
          children: [
            if (s.loading && d == null)
              const AppLoadingState(initial: true, label: 'Loading…'),
            if (s.error != null) AppErrorWidget(message: s.error!),
            if (d != null) ...[
              StaffCashHoldingCard(
                holdingMinor: d.holdingMinor,
                currency: currency,
              ),
              const SizedBox(height: 20),
              Text(
                'Collected on ${d.date}',
                style: Theme.of(
                  c,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: [
                  StaffCashAmountTile('Total', d.collectedMinor, currency),
                  StaffCashAmountTile('Cash', d.cashMinor, currency),
                  StaffCashAmountTile('UPI', d.upiMinor, currency),
                  StaffCashAmountTile('Card', d.cardMinor, currency),
                  StaffCashAmountTile('In bank', d.bankMinor, currency),
                  StaffCashAmountTile(
                    'Expenses paid',
                    d.expensesMinor,
                    currency,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Transactions',
                style: Theme.of(
                  c,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (d.transactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No transactions on this day.')),
                ),
              for (final t in d.transactions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    t.reason.isEmpty ? financeLabel(t.kind) : t.reason,
                  ),
                  subtitle: Text(
                    '${t.space.isEmpty ? '' : '${t.space} · '}${t.time} · ${t.mine ? 'You' : t.staffName}',
                  ),
                  trailing: Text(
                    financeMoney(t.netMinor, currency),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: t.netMinor < 0
                          ? Theme.of(c).colorScheme.error
                          : null,
                    ),
                  ),
                ),
              if (d.settlements.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Cash handovers',
                  style: Theme.of(c).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final x in d.settlements)
                  StaffCashSettlementTile(item: x, currency: currency),
              ],
            ],
          ],
        );
      },
    );
  }
}

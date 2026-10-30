import 'package:eden_booking/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../di/injection.dart';
import '../../accounts/models/accounts_models.dart';
import '../cubit/staff_cash_cubits.dart';
import '../models/staff_cash_models.dart';
import 'staff_cash_widgets.dart';
import 'staff_cash_settlement_sheet.dart';

/// Owner section on the Accounts page: cash each staff member holds, with collect/give.
class StaffCashOwnerSection extends StatefulWidget {
  const StaffCashOwnerSection({super.key, required this.currency});
  final String currency;
  @override
  State<StaffCashOwnerSection> createState() => _StaffCashOwnerSectionState();
}

class _StaffCashOwnerSectionState extends State<StaffCashOwnerSection> {
  late final cubit = getIt<OwnerStaffCashCubit>()..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> _settle(StaffCashMember m) async {
    final collect = m.holdingMinor > 0;
    final input = await showAdaptiveSheet<StaffCashHandoverInput>(
      context: context,
      scrollable: false,
      showClose: false,
      builder: (_) =>
          StaffCashSettlementSheet(member: m, currency: widget.currency),
    );
    if (input == null || !mounted) return;
    final minor = input.amountMinor;
    final after = await cubit.settle(m, minor, note: input.note);
    if (!mounted) return;
    final err = cubit.state.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          after == null
              ? err ?? 'Could not record handover.'
              : '${collect ? 'Collected' : 'Gave'} ${financeMoney(minor, widget.currency)} ${collect ? 'from' : 'to'} ${m.name} successfully. ${staffCashRemaining(after, widget.currency)}',
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<OwnerStaffCashCubit, OwnerStaffCashState>(
    bloc: cubit,
    builder: (c, s) {
      if (s.loaded && s.staff.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text(
              'Staff cash to collect',
              style: Theme.of(
                c,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (s.error != null && !s.loaded) AppErrorWidget(message: s.error!),
          for (final m in s.staff)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(m.name),
              subtitle: Text(
                m.holdingMinor == 0
                    ? 'Settled'
                    : m.holdingMinor > 0
                    ? 'To collect ${financeMoney(m.holdingMinor, widget.currency)}'
                    : 'To give ${financeMoney(-m.holdingMinor, widget.currency)}',
              ),
              trailing: m.holdingMinor == 0
                  ? null
                  : FilledButton.tonal(
                      onPressed: s.settling ? null : () => _settle(m),
                      child: Text(m.holdingMinor > 0 ? 'Collect' : 'Give'),
                    ),
            ),
        ],
      );
    },
  );
}

/// Handover entries shown with the owner's transaction history (informational; they never move ledger balances).
class StaffCashHistorySection extends StatefulWidget {
  const StaffCashHistorySection({
    super.key,
    required this.from,
    required this.until,
    required this.currency,
  });
  final String from, until, currency;
  @override
  State<StaffCashHistorySection> createState() =>
      _StaffCashHistorySectionState();
}

class _StaffCashHistorySectionState extends State<StaffCashHistorySection> {
  late final cubit = getIt<StaffCashHistoryCubit>()
    ..load(widget.from, widget.until);
  @override
  void didUpdateWidget(StaffCashHistorySection old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.until != widget.until) {
      cubit.load(widget.from, widget.until);
    }
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<StaffCashHistoryCubit, StaffCashHistoryState>(
        bloc: cubit,
        builder: (c, s) => s.items.isEmpty
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Staff cash handovers',
                    style: Theme.of(c).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final i in s.items)
                    StaffCashSettlementTile(item: i, currency: widget.currency),
                  const SizedBox(height: 16),
                ],
              ),
      );
}

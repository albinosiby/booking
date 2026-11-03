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
            padding: const EdgeInsets.only(top: 28, bottom: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.groups_2_outlined,
                  color: AppColors.lime,
                  size: 25,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Staff cash to collect',
                    style: Theme.of(c).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (s.error != null && !s.loaded) AppErrorWidget(message: s.error!),
          for (final m in s.staff)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(c).brightness == Brightness.dark
                      ? const Color(0xFF242424)
                      : Theme.of(c).colorScheme.surface,
                  border: Border.all(
                    color: Theme.of(
                      c,
                    ).colorScheme.outline.withValues(alpha: .35),
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final compact = box.maxWidth < 320;
                    final action = m.holdingMinor == 0
                        ? null
                        : FilledButton.icon(
                            onPressed: s.settling ? null : () => _settle(m),
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 17,
                            ),
                            label: Text(
                              m.holdingMinor > 0 ? 'Collect' : 'Give',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.lime,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          );
                    final summary = Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF267E18),
                          child: Text(
                            m.name.trim().isEmpty
                                ? '?'
                                : m.name.trim()[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                m.holdingMinor == 0
                                    ? 'Settled'
                                    : m.holdingMinor > 0
                                    ? 'To collect ${financeMoney(m.holdingMinor, widget.currency)}'
                                    : 'To give ${financeMoney(-m.holdingMinor, widget.currency)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(c).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (!compact && action != null) ...[
                          const SizedBox(width: 8),
                          action,
                        ],
                      ],
                    );
                    if (!compact || action == null) return summary;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        summary,
                        const SizedBox(height: 10),
                        Align(alignment: Alignment.centerRight, child: action),
                      ],
                    );
                  },
                ),
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

import 'package:eden_booking/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../di/injection.dart';
import '../../accounts/models/accounts_models.dart';
import '../cubit/staff_cash_cubits.dart';
import '../models/staff_cash_models.dart';
import 'staff_cash_widgets.dart';

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
    final input = TextEditingController(
      text: (m.holdingMinor.abs() / 100).toStringAsFixed(2),
    );
    final note = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (d) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(d).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (d, set) {
            final minor = financeOpeningMinor(input.text.trim());
            final valid =
                minor != null && minor > 0 && minor <= m.holdingMinor.abs();
            final after = valid
                ? m.holdingMinor + (collect ? -minor : minor)
                : m.holdingMinor;
            return Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collect
                        ? 'Collect cash from ${m.name}'
                        : 'Give cash to ${m.name}',
                    style: Theme.of(d).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${collect ? 'Staff holds' : 'Owner owes'} ${financeMoney(m.holdingMinor.abs(), widget.currency)}',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: input,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: collect ? 'Amount collected' : 'Amount given',
                      errorText: valid || input.text.isEmpty
                          ? null
                          : 'Enter an amount up to ${financeMoney(m.holdingMinor.abs(), widget.currency)}',
                    ),
                    onChanged: (_) => set(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                  ),
                  Text(
                    'Remaining: ${staffCashRemaining(after, widget.currency)}',
                    style: Theme.of(d).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: collect ? 'Confirm collected' : 'Confirm given',
                    onPressed: valid ? () => Navigator.pop(d, true) : null,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    final minor = financeOpeningMinor(input.text.trim());
    final text = note.text.trim();
    input.dispose();
    note.dispose();
    if (ok != true || minor == null) return;
    final after = await cubit.settle(m, minor, note: text);
    if (!mounted) return;
    final err = cubit.state.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          after == null
              ? err ?? 'Could not record handover.'
              : staffCashRemaining(after, widget.currency),
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

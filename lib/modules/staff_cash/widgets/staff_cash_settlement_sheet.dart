import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../accounts/models/accounts_models.dart';
import '../models/staff_cash_models.dart';
import 'staff_cash_widgets.dart';

/// Owns editing controllers until the closing sheet has actually unmounted.
class StaffCashSettlementSheet extends StatefulWidget {
  const StaffCashSettlementSheet({
    super.key,
    required this.member,
    required this.currency,
  });
  final StaffCashMember member;
  final String currency;
  @override
  State<StaffCashSettlementSheet> createState() =>
      _StaffCashSettlementSheetState();
}

class _StaffCashSettlementSheetState extends State<StaffCashSettlementSheet> {
  late final input = TextEditingController(
    text: (widget.member.holdingMinor.abs() / 100).toStringAsFixed(2),
  );
  final note = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member, currency = widget.currency;
    final collect = member.holdingMinor > 0;
    final minor = financeOpeningMinor(input.text.trim());
    final valid =
        minor != null && minor > 0 && minor <= member.holdingMinor.abs();
    final after = valid
        ? member.holdingMinor + (collect ? -minor : minor)
        : member.holdingMinor;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    collect
                        ? 'Collect cash from ${member.name}'
                        : 'Give cash to ${member.name}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${collect ? 'Staff holds' : 'Owner owes'} ${financeMoney(member.holdingMinor.abs(), currency)}',
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
                    : 'Enter an amount up to ${financeMoney(member.holdingMinor.abs(), currency)}',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            Text(
              'Remaining: ${staffCashRemaining(after, currency)}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: collect ? 'Confirm collected' : 'Confirm given',
              onPressed: !valid
                  ? null
                  : () => Navigator.pop(
                      context,
                      StaffCashHandoverInput(minor, note.text.trim()),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

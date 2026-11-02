import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../design_system/design_system.dart';
import '../models/call_wallet_models.dart';

/// Returns the chosen amount in paise, or null when dismissed.
Future<int?> showRechargeSheet(BuildContext context, CallWallet wallet) =>
    showAdaptiveSheet<int>(
      context: context,
      builder: (_) => RechargeSheet(wallet: wallet),
    );

class RechargeSheet extends StatefulWidget {
  const RechargeSheet({super.key, required this.wallet});
  final CallWallet wallet;
  @override
  State<RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends State<RechargeSheet> {
  final amount = TextEditingController();
  final form = GlobalKey<FormState>();
  int? get paise {
    final rupees = int.tryParse(amount.text.trim());
    return rupees == null ? null : rupees * 100;
  }

  @override
  void initState() {
    super.initState();
    final presets = widget.wallet.presetsPaise;
    if (presets.length > 1) amount.text = '${presets[1] ~/ 100}';
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  String? validate(String? _) {
    final w = widget.wallet, value = paise;
    if (value == null) return 'Enter an amount in rupees.';
    if (value < w.minRechargePaise) {
      return 'Recharge at least ${rupees(w.minRechargePaise)}.';
    }
    if (value > w.maxRechargePaise) {
      return 'Recharge at most ${rupees(w.maxRechargePaise)}.';
    }
    return null;
  }

  void submit() {
    if (form.currentState!.validate()) Navigator.pop(context, paise);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context), w = widget.wallet, value = paise;
    final minutes = value != null && w.ratePaisePerMinute > 0
        ? value ~/ w.ratePaisePerMinute
        : 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Recharge call wallet', style: t.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Calls are charged ${rupees(w.ratePaisePerMinute)} per started minute.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in w.presetsPaise)
                  ChoiceChip(
                    label: Text(rupees(preset)),
                    selected: value == preset,
                    onSelected: (_) =>
                        setState(() => amount.text = '${preset ~/ 100}'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('recharge-amount'),
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
              ),
              validator: validate,
              onChanged: (_) => setState(() {}),
              onFieldSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 8),
            Text(
              minutes > 0
                  ? 'About $minutes minutes of calls.'
                  : 'Enter between ${rupees(w.minRechargePaise)} and ${rupees(w.maxRechargePaise)}.',
              style: t.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            AppButton(
              key: const ValueKey('recharge-pay'),
              label: value == null ? 'Pay' : 'Pay ${rupees(value)}',
              icon: Icons.lock_outline_rounded,
              onPressed: submit,
            ),
            const SizedBox(height: 8),
            Text(
              'Payments are processed securely by Cashfree.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

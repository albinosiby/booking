import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../../utils/helpers/time_format.dart';
import '../models/booking_models.dart';
import '../models/booking_payment_entry_model.dart';

class BookingPaymentEditor extends StatelessWidget {
  const BookingPaymentEditor({
    super.key,
    required this.payments,
    this.catalog = const BookingCatalog(),
    this.businessId,
    this.spaceId,
    required this.enabled,
    required this.currency,
    required this.onAdd,
    this.remainingFor,
    this.paymentError,
    this.onPayBalance,
    this.entrySummary,
    this.refund = false,
    this.addLabel = 'Add other payment',
    required this.onRemove,
    required this.onUpdate,
  });
  final List<BookingPaymentDraft> payments;
  final BookingCatalog catalog;
  final String? businessId, spaceId;
  final bool enabled;
  final String currency;
  final VoidCallback onAdd;
  final BookingPaymentEntryModel? entrySummary;
  final bool refund;
  final String addLabel;
  final int? Function(String)? remainingFor;
  final String? Function(BookingPaymentDraft)? paymentError;
  final ValueChanged<String>? onPayBalance;
  final ValueChanged<String> onRemove;
  final void Function(String, BookingPaymentDraft Function(BookingPaymentDraft))
  onUpdate;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (entrySummary != null) ...[
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            for (final item in [
              (refund ? 'Refund due' : 'Balance due', entrySummary!.total),
              (refund ? 'Refund amount' : 'Collecting', entrySummary!.received),
              ('Remaining', entrySummary!.remaining),
            ])
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.$1, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    item.$2 == null ? '—' : bookingMoney(item.$2!, currency),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      if (payments.isEmpty)
        const Text(
          'No money recorded. You can confirm unpaid and collect later.',
        ),
      for (final p in payments)
        Padding(
          key: ValueKey('payment-row-${p.id}'),
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Payment ${payments.indexOf(p) + 1}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove payment',
                    onPressed: enabled ? () => onRemove(p.id) : null,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConfigurationField(
                          key: ValueKey('payment-amount-${p.id}'),
                          label: 'Amount · $currency',
                          value: p.amount,
                          numeric: true,
                          enabled: enabled,
                          onChanged: (v) =>
                              onUpdate(p.id, (p) => p.copyWith(amount: v)),
                        ),
                        if (paymentError?.call(p) != null)
                          Text(
                            paymentError!(p)!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: AppPicker(
                      label: 'Payment method',
                      value: p.method,
                      items: const [
                        PickerItem('cash', 'Cash'),
                        PickerItem('upi', 'UPI'),
                        PickerItem('card', 'Card'),
                        PickerItem('bank_transfer', 'Bank transfer'),
                      ],
                      enabled: enabled,
                      onChanged: (v) =>
                          onUpdate(p.id, (p) => p.copyWith(method: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (onPayBalance != null && (remainingFor?.call(p.id) ?? 0) > 0)
                TextButton.icon(
                  onPressed: enabled ? () => onPayBalance!(p.id) : null,
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: Text(refund ? 'Refund balance' : 'Pay balance'),
                ),
              if (p.method != 'cash') _destination(context, p),
              ReviewMore(
                title: 'Reference & payment date · optional',
                children: [
                  ConfigurationField(
                    key: ValueKey('payment-reference-${p.id}'),
                    label: 'Reference · optional',
                    value: p.reference,
                    enabled: enabled,
                    onChanged: (v) =>
                        onUpdate(p.id, (p) => p.copyWith(reference: v)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Received ${bookingDate(p.receivedAt.toLocal())} ${TimeFormat.display('${p.receivedAt.toLocal().hour.toString().padLeft(2, '0')}:${p.receivedAt.toLocal().minute.toString().padLeft(2, '0')}')} · device local time',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Wrap(
                    spacing: 10,
                    children: [
                      TextButton(
                        onPressed: enabled
                            ? () async {
                                final current = p.receivedAt.toLocal(),
                                    d = await showDatePicker(
                                      context: context,
                                      initialDate: current,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime.now(),
                                    );
                                if (d != null) {
                                  onUpdate(
                                    p.id,
                                    (p) => p.copyWith(
                                      receivedAt: DateTime(
                                        d.year,
                                        d.month,
                                        d.day,
                                        current.hour,
                                        current.minute,
                                      ),
                                    ),
                                  );
                                }
                              }
                            : null,
                        child: const Text('Change payment date'),
                      ),
                      TextButton(
                        onPressed: enabled
                            ? () async {
                                final current = p.receivedAt.toLocal(),
                                    t = await showAppTimePicker(
                                      context: context,
                                      initialTime:
                                          '${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}',
                                    );
                                if (t != null) {
                                  final parts = t.split(':');
                                  onUpdate(
                                    p.id,
                                    (p) => p.copyWith(
                                      receivedAt: DateTime(
                                        current.year,
                                        current.month,
                                        current.day,
                                        int.parse(parts[0]),
                                        int.parse(parts[1]),
                                      ),
                                    ),
                                  );
                                }
                              }
                            : null,
                        child: const Text('Change payment time'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      AppButton(
        label: addLabel,
        secondary: true,
        icon: Icons.add,
        onPressed: enabled && payments.length < 20 ? onAdd : null,
      ),
    ],
  );
  Widget _destination(BuildContext context, BookingPaymentDraft p) {
    final id =
        p.accountId ??
        catalog.paymentDestination(p.method, businessId, spaceId);
    final banks = catalog.paymentAccounts
        .where((a) => a.kind == 'bank')
        .toList();
    final bank = banks.where((a) => a.id == id).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.account_balance_outlined, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${refund ? 'From' : 'To'}: ${bank?.name ?? 'Unassigned bank'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (banks.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Change receiving account',
              enabled: enabled,
              onSelected: (v) =>
                  onUpdate(p.id, (p) => p.copyWith(accountId: v)),
              itemBuilder: (_) => [
                for (final b in banks)
                  PopupMenuItem(value: b.id, child: Text(b.name)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Text(
                  'Change',
                  style: TextStyle(
                    color: enabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).disabledColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../models/booking_discount.dart';
import '../models/booking_form_model.dart';
import '../models/booking_models.dart';

class BookingDiscountEditor extends StatelessWidget {
  const BookingDiscountEditor({
    super.key,
    required this.model,
    required this.onChanged,
  });
  final BookingFormModel model;
  final ValueChanged<BookingDiscount?> onChanged;
  @override
  Widget build(BuildContext context) {
    final d = model.draft.discount;
    final subtotal = model.quote?.subtotal ?? model.estimatedSubtotal;
    final total = model.displayedTotal;
    final received = model.draft.received;
    final enabled = !model.locked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            if (d != null) _amount(context, 'Subtotal', subtotal),
            if (d != null)
              _amount(
                context,
                'Discount',
                subtotal == null ? null : d.reduction(subtotal),
              ),
            _amount(
              context,
              model.quote == null ? 'Estimated total' : 'Final total',
              total,
            ),
            _amount(context, 'Received', received),
            _amount(
              context,
              'Balance due',
              total == null ? null : (total - received).clamp(0, total),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (d == null)
          TextButton.icon(
            onPressed: enabled
                ? () => onChanged(const BookingDiscount())
                : null,
            icon: const Icon(Icons.local_offer_outlined),
            label: const Text('Add discount'),
          )
        else ...[
          Row(
            children: [
              const Icon(Icons.local_offer_outlined, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('Discount')),
              TextButton(
                onPressed: enabled ? () => onChanged(null) : null,
                child: const Text('Remove'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final type in ['amount', 'percent'])
                ChoiceChip(
                  label: Text(type == 'amount' ? '₹ Amount' : 'Percentage'),
                  selected: d.type == type,
                  onSelected: enabled
                      ? (_) => onChanged(d.copyWith(type: type, value: ''))
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
          ConfigurationField(
            key: ValueKey('discount-${d.type}'),
            label: d.type == 'amount'
                ? 'Discount amount'
                : 'Discount percentage',
            value: d.value,
            numeric: true,
            enabled: enabled,
            onChanged: (v) => onChanged(d.copyWith(value: v)),
          ),
          if (d.value.isNotEmpty && d.validate(subtotal) != null)
            Text(
              d.validate(subtotal)!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          ConfigurationField(
            label: 'Discount reason · optional',
            value: d.reason,
            enabled: enabled,
            onChanged: (v) => onChanged(d.copyWith(reason: v)),
          ),
        ],
        const Divider(height: 28),
      ],
    );
  }

  Widget _amount(BuildContext context, String label, int? value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(
        value == null ? '—' : bookingMoney(value, model.catalog.currency),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

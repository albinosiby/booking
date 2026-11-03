import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/widgets/booking_widgets.dart';

/// Collects or refunds up to [limit]; pops with the payments and reason.
/// Staff may enter any amount up to the limit, so part payments leave the
/// rest due.
class AdmissionPaymentSheet extends StatefulWidget {
  const AdmissionPaymentSheet({
    super.key,
    required this.refund,
    required this.currency,
    required this.limit,
    this.title,
    this.subtitle,
  });
  final bool refund;
  final String currency;
  final int limit;

  /// Defaults to the admission payment or refund title.
  final String? title;
  final String? subtitle;
  @override
  State<AdmissionPaymentSheet> createState() => AdmissionPaymentSheetState();
}

class AdmissionPaymentSheetState extends State<AdmissionPaymentSheet> {
  late List<BookingPaymentDraft> payments;
  String reason = '', error = '';
  @override
  void initState() {
    super.initState();
    payments = [
      BookingPaymentDraft(
        amount: widget.refund ? '' : (widget.limit / 100).toStringAsFixed(2),
      ),
    ];
  }

  void addPayment() {
    final remaining =
        widget.limit -
        payments.fold<int>(
          0,
          (amount, payment) => amount + (payment.minor ?? 0),
        );
    setState(
      () => payments = [
        ...payments,
        BookingPaymentDraft(
          amount: !widget.refund && remaining > 0
              ? (remaining / 100).toStringAsFixed(2)
              : '',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        24,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title ??
                (widget.refund
                    ? 'Record admission refund'
                    : 'Collect admission payment'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (widget.subtitle != null) Text(widget.subtitle!),
          const SizedBox(height: 16),
          Text('Maximum ${bookingMoney(widget.limit, widget.currency)}'),
          if (!widget.refund)
            Text(
              key: const ValueKey('admission-payment-remaining'),
              'Remaining after this: ${bookingMoney((widget.limit - payments.fold<int>(0, (n, p) => n + (p.minor ?? 0))).clamp(0, widget.limit), widget.currency)}',
            ),
          BookingPaymentEditor(
            payments: payments,
            enabled: true,
            currency: widget.currency,
            refund: widget.refund,
            onAdd: addPayment,
            onRemove: (id) => setState(
              () => payments = payments.where((p) => p.id != id).toList(),
            ),
            onUpdate: (id, change) => setState(
              () => payments = payments
                  .map((p) => p.id == id ? change(p) : p)
                  .toList(),
            ),
          ),
          if (widget.refund)
            ConfigurationField(
              label: 'Refund reason',
              value: reason,
              onChanged: (v) => reason = v,
            ),
          if (error.isNotEmpty) Text(error),
          const SizedBox(height: 16),
          AppButton(
            label: 'Save',
            onPressed: () {
              final selected = payments.where((p) => !p.isBlank).toList();
              final validation = selected.isEmpty
                  ? 'Enter at least one payment.'
                  : selected
                        .map((p) => p.validate())
                        .whereType<String>()
                        .firstOrNull;
              if (validation != null ||
                  selected.fold(0, (n, p) => n + (p.minor ?? 0)) >
                      widget.limit ||
                  (widget.refund && reason.trim().length < 2)) {
                setState(
                  () => error =
                      validation ??
                      (widget.refund
                          ? 'Check the amount and provide a refund reason.'
                          : 'Check the amount collected.'),
                );
                return;
              }
              Navigator.pop(context, (selected, reason.trim()));
            },
          ),
        ],
      ),
    ),
  );
}

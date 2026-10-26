import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../bookings/models/booking_models.dart' show bookingMoney;
import '../cubit/invoice_cubits.dart';
import '../models/invoice_models.dart';

String invoiceStamp(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Download / share actions and the immutable invoice history for one booking.
class BookingInvoicesCard extends StatelessWidget {
  const BookingInvoicesCard({super.key, required this.cubit});
  final BookingInvoicesCubit cubit;
  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<BookingInvoicesCubit, BookingInvoicesModel>(
    bloc: cubit,
    listenWhen: (a, b) => b.message != null && a.message != b.message,
    listener: (context, s) => showMessage(context, s.message!),
    builder: (context, s) {
      if (!s.enabled && !s.loading && s.error == null) {
        return const SizedBox.shrink();
      }
      final generating = s.workingOn == BookingInvoicesModel.newInvoice;
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Invoice', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                'Uses the booking\'s current amount paid and balance due. Each new invoice is saved below and never changes.',
              ),
              if (s.loading && s.invoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (s.error != null)
                AppErrorWidget(
                  message: s.error!,
                  onRetry: s.enabled ? null : cubit.load,
                ),
              if (s.enabled) ...[
                const SizedBox(height: 12),
                AppButton(
                  key: const ValueKey('invoice-download'),
                  label: 'Download invoice',
                  icon: Icons.download_outlined,
                  busy: generating,
                  onPressed: s.busy ? null : cubit.download,
                ),
                const SizedBox(height: 8),
                AppButton(
                  key: const ValueKey('invoice-share'),
                  label: 'Share invoice',
                  icon: Icons.share_outlined,
                  secondary: true,
                  onPressed: s.busy ? null : cubit.share,
                ),
              ],
              if (s.invoices.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Invoice history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final i in s.invoices)
                  ListTile(
                    key: ValueKey('invoice-${i.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(i.number),
                    subtitle: Text(
                      '${invoiceStamp(i.generatedAt)} · ${i.generatedByName}\n'
                      'Total ${bookingMoney(i.totalMinor, i.currency)} · Paid ${bookingMoney(i.paidMinor, i.currency)} · Due ${bookingMoney(i.balanceMinor, i.currency)}',
                    ),
                    isThreeLine: true,
                    trailing: s.workingOn == i.id
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Download ${i.number}',
                                icon: const Icon(Icons.download_outlined),
                                onPressed: s.busy
                                    ? null
                                    : () => cubit.download(i),
                              ),
                              IconButton(
                                tooltip: 'Share ${i.number}',
                                icon: const Icon(Icons.share_outlined),
                                onPressed: s.busy ? null : () => cubit.share(i),
                              ),
                            ],
                          ),
                  ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Loads its cubit from [create] once; hides itself when invoices are unavailable.
class BookingInvoicesSection extends StatefulWidget {
  const BookingInvoicesSection({super.key, required this.create});
  final BookingInvoicesCubit Function() create;
  @override
  State<BookingInvoicesSection> createState() => _BookingInvoicesSectionState();
}

class _BookingInvoicesSectionState extends State<BookingInvoicesSection> {
  late final cubit = widget.create()..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BookingInvoicesCard(cubit: cubit);
}

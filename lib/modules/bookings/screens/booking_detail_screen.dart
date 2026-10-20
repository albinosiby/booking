import '../widgets/booking_history_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../models/booking_models.dart';
import '../models/booking_detail_model.dart';
import '../cubit/booking_detail_cubit.dart';
import '../widgets/booking_widgets.dart';

class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({
    super.key,
    required this.id,
    this.collectOnOpen = false,
    this.justCreated = false,
  });
  final String id;
  final bool collectOnOpen;
  final bool justCreated;
  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  late final cubit = getIt<BookingDetailCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.id,
  );
  final paymentEditorKey = GlobalKey();
  void collect() {
    if (cubit.state.locked || !cubit.state.canCollectPending) return;
    if (cubit.state.action != BookingDetailAction.collection) {
      cubit.begin(BookingDetailAction.collection);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = paymentEditorKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: .05,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await cubit.load();
    if (mounted &&
        widget.collectOnOpen &&
        cubit.state.record != null &&
        cubit.state.record!.balance > 0 &&
        cubit.state.record!.status != 'cancelled') {
      collect();
    }
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<BookingDetailCubit, BookingDetailModel>(
    bloc: cubit,
    builder: (context, s) {
      final b = s.record,
          editing = s.action != BookingDetailAction.none,
          enabled = !s.locked;
      return PopScope(
        canPop: !s.locked,
        child: AppPage(
          back: true,
          onBack: () => s.locked
              ? showMessage(
                  context,
                  'Retry this action to verify its outcome before leaving.',
                )
              : bookingBack(context),
          title: b?.reference ?? 'Booking details',
          actions: [
            if (b != null)
              IconButton(
                tooltip: 'Share booking',
                icon: const Icon(Icons.share_outlined),
                onPressed: enabled
                    ? () => context.push('/booking/${b.id}/share')
                    : null,
              ),
          ],
          scrollId: 'booking-detail-${widget.id}',
          maxWidth: 760,
          children: [
            if (s.loading)
              AppLoadingState(
                initial: s.record == null,
                label: s.record == null ? 'Loading booking…' : null,
              ),
            if (s.error != null) ...[
              AppErrorWidget(
                message: s.error!,
                onRetry: s.locked ? null : load,
              ),
              const SizedBox(height: 16),
            ],
            if (b != null) ...[
              if (widget.justCreated && b.status == 'confirmed') ...[
                Text(
                  'Booking confirmed',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: 'Share on WhatsApp',
                  icon: Icons.share_outlined,
                  onPressed: enabled
                      ? () => context.push('/booking/${b.id}/share')
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${b.businessName} · ${b.spaceName}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(b.optionName),
                    const SizedBox(height: 10),
                    Text(
                      '${bookingLocal(b.localStart)} → ${bookingLocal(b.localEnd)}',
                    ),
                    Text(b.timezone),
                    const SizedBox(height: 8),
                    Text('Cleanup time: ${b.cleanupMinutes} minutes'),
                    const Text(
                      'Internal only · does not block the next booking.',
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        Chip(label: Text(paymentLabel(b.status))),
                        Chip(label: Text(paymentLabel(b.paymentStatus))),
                      ],
                    ),
                    Text('${b.customer.name} · ${b.customer.phone}'),
                    if (b.customer.email.isNotEmpty) Text(b.customer.email),
                    if (b.notes.isNotEmpty) Text(b.notes),
                    const Divider(),
                    if (b.discountMinor > 0) ...[
                      Text(
                        'Subtotal: ${bookingMoney(b.subtotal ?? b.total + b.discountMinor, s.catalog.currency)}',
                      ),
                      Text(
                        'Discount: ${bookingMoney(b.discountMinor, s.catalog.currency)}',
                      ),
                      if (b.selection.discount?.reason.isNotEmpty == true)
                        Text(b.selection.discount!.reason),
                    ],
                    Text(
                      'Booking total: ${bookingMoney(b.total, s.catalog.currency)}',
                    ),
                    Text(
                      'Net received: ${bookingMoney(b.netPaid, s.catalog.currency)}',
                    ),
                    Text(
                      'Balance due: ${bookingMoney(b.balance, s.catalog.currency)}',
                    ),
                    if (b.refundDue > 0)
                      Text(
                        'Refund due: ${bookingMoney(b.refundDue, s.catalog.currency)}',
                      ),
                    if (b.status == 'cancelled')
                      const Text(
                        'Cancellation does not automatically refund payments.',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!editing) ...[
                if (s.catalog.canManage && b.status == 'confirmed')
                  AppButton(
                    label: 'Reschedule',
                    icon: Icons.event_repeat,
                    onPressed: enabled
                        ? () => context.push('/booking/${b.id}/reschedule')
                        : null,
                  ),
                const SizedBox(height: 12),
                if (s.canCollectPending)
                  AppButton(
                    label: 'Record payment',
                    secondary: true,
                    onPressed: enabled ? collect : null,
                  ),
                if (s.catalog.canRefund && b.refundDue > 0)
                  AppButton(
                    label: 'Record refund',
                    secondary: true,
                    onPressed: enabled
                        ? () => cubit.begin(BookingDetailAction.refund)
                        : null,
                  ),
                if (s.catalog.canManage) ...[
                  TextButton(
                    onPressed: enabled
                        ? () => cubit.begin(BookingDetailAction.customer)
                        : null,
                    child: const Text('Edit customer & notes'),
                  ),
                  if (b.status == 'confirmed') ...[
                    TextButton(
                      onPressed: enabled
                          ? () => cubit.begin(BookingDetailAction.cancelled)
                          : null,
                      child: const Text('Cancel booking'),
                    ),
                    if (!DateTime.parse(b.endsAt).isAfter(DateTime.now()))
                      TextButton(
                        onPressed: enabled
                            ? () => cubit.begin(BookingDetailAction.completed)
                            : null,
                        child: const Text('Mark completed'),
                      ),
                    if (!DateTime.parse(b.startsAt).isAfter(DateTime.now()))
                      TextButton(
                        onPressed: enabled
                            ? () => cubit.begin(BookingDetailAction.noShow)
                            : null,
                        child: const Text('Mark no-show'),
                      ),
                  ],
                ],
              ] else
                AppCard(
                  key: paymentEditorKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.action == BookingDetailAction.customer
                            ? 'Edit customer details'
                            : s.action == BookingDetailAction.collection
                            ? 'Record split payment'
                            : s.action == BookingDetailAction.refund
                            ? 'Record refund'
                            : 'Confirm ${paymentLabel(s.action.name)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      if (s.action == BookingDetailAction.collection ||
                          s.action == BookingDetailAction.refund)
                        BookingPaymentEditor(
                          catalog: s.catalog,
                          businessId: s.record?.selection.businessId,
                          spaceId: s.record?.selection.resourceId,
                          payments: s.payments,
                          enabled: enabled,
                          currency: s.catalog.currency,
                          onAdd: cubit.addPayment,
                          entrySummary: s.paymentEntry,
                          refund: s.action == BookingDetailAction.refund,
                          remainingFor: s.paymentBalance,
                          paymentError: s.paymentError,
                          onPayBalance: cubit.payBalance,
                          onRemove: cubit.removePayment,
                          onUpdate: cubit.updatePayment,
                        ),
                      if (s.action == BookingDetailAction.customer)
                        BookingCustomerFields(
                          customer: s.customer,
                          notes: s.notes,
                          enabled: enabled,
                          onName: cubit.customerName,
                          onPhone: cubit.customerPhone,
                          onEmail: cubit.customerEmail,
                          onNotes: cubit.notes,
                        ),
                      if (s.action != BookingDetailAction.customer) ...[
                        const SizedBox(height: 16),
                        ConfigurationField(
                          label: s.action == BookingDetailAction.collection
                              ? 'Payment note · optional'
                              : 'Reason',
                          value: s.reason,
                          enabled: enabled,
                          onChanged: cubit.reason,
                        ),
                      ],
                      const SizedBox(height: 16),
                      AppButton(
                        label: s.pending == null
                            ? 'Save changes'
                            : 'Retry action',
                        busy: s.saving,
                        onPressed: s.saving ? null : cubit.submit,
                      ),
                      TextButton(
                        onPressed: enabled ? cubit.cancelEdit : null,
                        child: const Text('Back to booking'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              BookingPaymentHistory(
                payments: s.paymentHistory,
                currency: s.catalog.currency,
                collectAmount: s.canCollectPending ? b.balance : null,
                onCollect: enabled ? collect : null,
              ),
              const SizedBox(height: 24),
              BookingActivityHistory(events: s.bookingHistory),
            ],
          ],
        ),
      );
    },
  );
}

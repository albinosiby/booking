import '../widgets/booking_payment_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../models/booking_detail_model.dart';
import '../models/booking_models.dart' show BookingRecord, bookingMoney;
import '../cubit/booking_detail_cubit.dart';
import '../widgets/booking_widgets.dart';
import '../../invoices/repositories/invoice_repository.dart';
import '../../invoices/cubit/invoice_cubits.dart';
import '../../invoices/widgets/booking_invoices_card.dart';

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
  bool paymentSheetOpen = false;
  bool closingPaymentSheet = false;
  void collect() {
    if (cubit.state.locked || !cubit.state.canCollectPending) return;
    if (cubit.state.action != BookingDetailAction.collection) {
      cubit.begin(BookingDetailAction.collection);
    }
  }

  void revealEditor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = paymentEditorKey.currentContext;
      if (mounted && target != null && target.mounted) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: .05,
        );
      }
    });
  }

  bool isPaymentAction(BookingDetailAction action) =>
      action == BookingDetailAction.collection ||
      action == BookingDetailAction.refund;

  void openPaymentSheet() {
    if (!mounted || paymentSheetOpen) return;
    paymentSheetOpen = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (sheetContext) => BlocConsumer<BookingDetailCubit, BookingDetailModel>(
        bloc: cubit,
        listenWhen: (previous, next) =>
            isPaymentAction(previous.action) && !isPaymentAction(next.action),
        listener: (context, _) {
          if (paymentSheetOpen && !closingPaymentSheet) {
            closingPaymentSheet = true;
            Navigator.of(sheetContext).pop();
          }
        },
        builder: (context, state) => PopScope(
          canPop: !state.locked,
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .86,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                state.action == BookingDetailAction.refund
                                    ? 'Record refund'
                                    : state.payments.length > 1
                                    ? 'Split payment'
                                    : 'Collect payment',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close payment form',
                              onPressed: state.locked
                                  ? null
                                  : () {
                                      closingPaymentSheet = true;
                                      Navigator.of(sheetContext).pop();
                                    },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          children: [
                            Text('For ${state.record?.reference ?? 'booking'}'),
                            const SizedBox(height: 16),
                            if (state.action == BookingDetailAction.refund)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Text(
                                  'Return the money outside Booking OS, then record the amount and method here.',
                                ),
                              ),
                            BookingPaymentEditor(
                              catalog: state.catalog,
                              businessId: state.record?.selection.businessId,
                              spaceId: state.record?.selection.resourceId,
                              payments: state.payments,
                              enabled: !state.locked,
                              currency: state.catalog.currency,
                              onAdd: cubit.addPayment,
                              entrySummary: state.paymentEntry,
                              refund:
                                  state.action == BookingDetailAction.refund,
                              remainingFor: state.paymentBalance,
                              paymentError: state.paymentError,
                              onPayBalance: cubit.payBalance,
                              onRemove: cubit.removePayment,
                              onUpdate: cubit.updatePayment,
                              addLabel: 'Add another payment method',
                            ),
                            const SizedBox(height: 16),
                            ConfigurationField(
                              label: state.action == BookingDetailAction.refund
                                  ? 'Refund reason'
                                  : 'Payment note · optional',
                              value: state.reason,
                              enabled: !state.locked,
                              onChanged: cubit.reason,
                            ),
                            if (state.error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                state.error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: AppButton(
                          key: const ValueKey('booking-payment-submit'),
                          label: state.pending != null
                              ? 'Retry payment safely'
                              : state.action == BookingDetailAction.refund
                              ? 'Record ${bookingMoney(state.paymentEntry.received, state.catalog.currency)} refund'
                              : 'Record ${bookingMoney(state.paymentEntry.received, state.catalog.currency)} payment',
                          busy: state.saving,
                          onPressed: state.saving ? null : cubit.submit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      paymentSheetOpen = false;
      if (mounted &&
          isPaymentAction(cubit.state.action) &&
          !cubit.state.locked) {
        cubit.cancelEdit();
      }
      closingPaymentSheet = false;
    });
  }

  Future<void> showMoreActions(BookingDetailModel state) async {
    final b = state.record;
    if (b == null || state.locked) return;
    final action = await showModalBottomSheet<BookingDetailAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.catalog.canManage)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit customer & notes'),
                onTap: () =>
                    Navigator.pop(context, BookingDetailAction.customer),
              ),
            if (state.catalog.canManage && b.status == 'confirmed')
              ListTile(
                key: const ValueKey('booking-cancel-action'),
                leading: Icon(
                  Icons.event_busy_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  state.canCancelAndRefund
                      ? 'Cancel & refund'
                      : 'Cancel booking',
                ),
                onTap: () => Navigator.pop(
                  context,
                  state.canCancelAndRefund
                      ? BookingDetailAction.cancelAndRefund
                      : BookingDetailAction.cancelled,
                ),
              ),
          ],
        ),
      ),
    );
    if (mounted && action != null) cubit.begin(action);
  }

  String bookingSchedule(BuildContext context, BookingRecord b) {
    final start = DateTime.tryParse(b.localStart);
    final end = DateTime.tryParse(b.localEnd);
    if (start == null || end == null) {
      return '${bookingLocal(b.localStart)} → ${bookingLocal(b.localEnd)}';
    }
    final localizations = MaterialLocalizations.of(context);
    String time(DateTime date) => localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    return '${localizations.formatMediumDate(start)} · ${time(start)}–${sameDay ? '' : '${localizations.formatMediumDate(end)} '}${time(end)}';
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
  ) => BlocConsumer<BookingDetailCubit, BookingDetailModel>(
    bloc: cubit,
    listenWhen: (previous, next) =>
        previous.action != next.action &&
        next.action != BookingDetailAction.none &&
        !next.loading,
    listener: (_, state) =>
        isPaymentAction(state.action) ? openPaymentSheet() : revealEditor(),
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
          title: 'Booking details',
          showAppBar: true,
          compactHeader: true,
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
          header: b == null
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        SelectableText(
                          b.reference,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        BookingStatusChip(status: b.status),
                        if (b.checkedIn)
                          Chip(
                            label: Text(
                              b.automaticallyCheckedIn
                                  ? 'Auto checked in'
                                  : 'Checked in',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
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
                      b.spaceName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (b.optionName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(b.optionName),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      bookingSchedule(context, b),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(b.businessName),
                    const SizedBox(height: 4),
                    Text(b.customer.name),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              BookingPaymentSummary(
                booking: b,
                currency: s.catalog.currency,
                onCollect: s.canCollectPending && enabled ? collect : null,
                onRefund:
                    s.catalog.canRefund &&
                        s.catalog.canCollect &&
                        b.refundDue > 0 &&
                        enabled
                    ? () => cubit.begin(BookingDetailAction.refund)
                    : null,
              ),
              if (b.websitePayment != null) ...[
                const SizedBox(height: 12),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unverified website payment',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        'Transaction ID: ${b.websitePayment!['transaction_id']}',
                      ),
                      const Text(
                        'Check your bank before recording this payment. The submitted reference does not change the balance.',
                      ),
                      ReviewMore(
                        title: 'Submitted payment details',
                        children: [
                          Text(
                            'Submitted: ${b.websitePayment!['percentage']}% · ${bookingMoney(b.websitePayment!['amount_minor'] as int, s.catalog.currency)}',
                          ),
                          SelectableText(
                            'UPI ID: ${b.websitePayment!['upi_id']}',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (!editing && s.catalog.canManage) ...[
                const SizedBox(height: 16),
                Text('Actions', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (s.canCheckIn) ...[
                  AppButton(
                    label: 'Check in',
                    icon: Icons.how_to_reg_outlined,
                    secondary: true,
                    onPressed: enabled
                        ? () => cubit.begin(BookingDetailAction.checkedIn)
                        : null,
                  ),
                  const SizedBox(height: 8),
                ],
                if (b.status == 'confirmed') ...[
                  AppButton(
                    label: 'Reschedule',
                    icon: Icons.event_repeat,
                    secondary: true,
                    onPressed: enabled
                        ? () => context.push('/booking/${b.id}/reschedule')
                        : null,
                  ),
                  const SizedBox(height: 8),
                ],
                AppButton(
                  label: 'More actions',
                  icon: Icons.more_horiz,
                  secondary: true,
                  onPressed: enabled ? () => showMoreActions(s) : null,
                ),
              ],
              const SizedBox(height: 12),
              AppCard(
                child: ExpansionTile(
                  key: PageStorageKey('booking-details-${b.id}'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  title: const Text('Details'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${b.customer.name} · ${b.customer.phone}'),
                          if (b.customer.email.isNotEmpty)
                            Text(b.customer.email),
                          Text('Time zone: ${b.timezone}'),
                          Text('Cleanup time: ${b.cleanupMinutes} minutes'),
                          const Text(
                            'Internal only · does not block the next booking.',
                          ),
                          if (b.notes.isNotEmpty) Text('Notes: ${b.notes}'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!editing && invoicesAvailable(getIt)) ...[
                const SizedBox(height: 12),
                BookingInvoicesSection(
                  key: ValueKey('invoices-${b.id}'),
                  create: () => getIt<BookingInvoicesCubit>(param1: b.id),
                ),
              ],
              const SizedBox(height: 12),
              if (editing && !isPaymentAction(s.action))
                AppCard(
                  key: paymentEditorKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.action == BookingDetailAction.customer
                            ? 'Edit customer details'
                            : s.action == BookingDetailAction.cancelAndRefund
                            ? 'Cancel & refund'
                            : s.action == BookingDetailAction.checkedIn
                            ? 'Check in customer'
                            : 'Confirm ${paymentLabel(s.action.name)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      if (s.action == BookingDetailAction.cancelAndRefund)
                        Text(
                          'Cancel this booking and release its slot. Then record a refund up to ${bookingMoney(b.netPaid, s.catalog.currency)}. No refund is recorded until you save the refund form.',
                        ),
                      if (s.action == BookingDetailAction.checkedIn)
                        const Text(
                          'Confirm the customer has arrived. This keeps the booking confirmed and does not change payments.',
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
                          label: s.action == BookingDetailAction.checkedIn
                              ? 'Arrival note · optional'
                              : s.action == BookingDetailAction.cancelAndRefund
                              ? 'Cancellation reason'
                              : 'Reason',
                          value: s.reason,
                          enabled: enabled,
                          onChanged: cubit.reason,
                        ),
                      ],
                      const SizedBox(height: 16),
                      AppButton(
                        label: s.pending == null
                            ? (s.action == BookingDetailAction.checkedIn
                                  ? 'Confirm check in'
                                  : s.action ==
                                        BookingDetailAction.cancelAndRefund
                                  ? 'Confirm cancellation'
                                  : 'Save changes')
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
            ],
          ],
        ),
      );
    },
  );
}

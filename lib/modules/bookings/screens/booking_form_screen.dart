import '../widgets/booking_discount_editor.dart';
import '../../../utils/helpers/time_format.dart';
import '../../workspace/widgets/workspace_business_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../models/booking_models.dart';
import '../models/booking_form_model.dart';
import '../cubit/booking_form_cubit.dart';
import '../widgets/booking_widgets.dart';
import '../widgets/booking_form_sections.dart';
import '../widgets/booking_space_selection.dart';

class BookingFormScreen extends StatefulWidget {
  const BookingFormScreen({super.key, this.launch = const BookingLaunch()});
  final BookingLaunch launch;
  @override
  State<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  late final cubit = getIt<BookingFormCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.launch,
  );
  bool leaving = false;
  @override
  void initState() {
    super.initState();
    cubit.load();
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  void back() {
    if (cubit.state.locked) {
      showMessage(
        context,
        'Retry confirmation to verify the booking before leaving.',
      );
      return;
    }
    bookingBack(context);
  }

  Future<void> pickDate(BookingFormModel s) async {
    final today = DateTime.parse(s.business!.today),
        last = DateTime(2100, 12, 31);
    var initial = DateTime.tryParse(s.draft.date) ?? today;
    if (initial.isBefore(today)) initial = today;
    if (initial.isAfter(last)) initial = last;
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: last,
    );
    if (value != null && !cubit.isClosed) cubit.date(bookingDate(value));
  }

  Widget customerSection(BookingFormModel s) => BookingFormSection(
    number: 1,
    title: 'Customer',
    children: s.original != null
        ? [
            Text(
              s.draft.customer.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(s.draft.customer.phone),
            const SizedBox(height: 8),
            const Text('Customer details and existing payments stay attached.'),
          ]
        : [
            BookingCustomerFields(
              compact: true,
              customer: s.draft.customer,
              notes: s.draft.notes,
              enabled: !s.locked,
              onName: cubit.customerName,
              onPhone: cubit.customerPhone,
              onEmail: cubit.customerEmail,
              onNotes: cubit.notes,
            ),
            for (final customer
                in s.draft.customer.name.trim().isEmpty
                    ? s.customers
                    : <BookingCustomer>[])
              ListTile(
                title: Text(customer.name),
                subtitle: Text(customer.phone),
                onTap: s.locked ? null : () => cubit.chooseCustomer(customer),
              ),
          ],
  );
  Widget spaceSection(BookingFormModel s) => BookingSpaceSelection(
    model: s,
    businesses: s.original == null
        ? orderedWorkspaceBusinesses(context, s.catalog.businesses, (b) => b.id)
        : [if (s.business != null) s.business!],
    onBusiness: cubit.chooseBusiness,
    onSport: cubit.chooseSport,
    onSpace: cubit.chooseSpace,
    onOption: cubit.chooseOption,
  );
  Widget timeSection(BookingFormModel s) => BookingFormSection(
    number: 3,
    title: 'Date & time',
    summary: s.business == null ? null : 'Times use ${s.business!.timezone}',
    children: [
      if (s.business != null)
        BookingDateRow(
          date: s.draft.date,
          today: s.business!.today,
          enabled: !s.locked,
          onSelected: cubit.date,
          onPick: () => pickDate(s),
        ),
      if (s.option?.minimumDuration != null) ...[
        Text('Minimum booking: ${s.option!.minimumDuration} minutes'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final value in [
              ('Start', s.choosingEnd ? TimeFormat.display(s.draft.time) : '—'),
              (
                'End',
                s.rangeComplete
                    ? '${TimeFormat.display(s.draft.endTime)}${s.draft.endsNextDay ? ' +1 day' : ''}'
                    : '—',
              ),
              ('Duration', s.rangeComplete ? '${s.draft.duration} min' : '—'),
            ])
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value.$1,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value.$2,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ] else if (s.option != null)
        Text('Fixed duration: ${s.option!.defaultDuration} min'),
      if (s.business?.type == 'pool' || s.business?.type == 'hall') ...[
        ConfigurationField(
          label: s.business!.type == 'pool'
              ? 'Number of swimmers'
              : 'Expected guests',
          value: s.draft.people,
          numeric: true,
          enabled: !s.locked && s.option?.groupMode != 'exact',
          onChanged: cubit.people,
        ),
        if (s.option?.groupMode != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.option!.groupExplanation),
          ),
        const SizedBox(height: 16),
      ],
      Row(
        children: [
          Expanded(
            child: Text(
              s.option?.minimumDuration == null
                  ? 'Choose your time'
                  : 'Choose start & end',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: 'Refresh availability',
            onPressed: s.locked || s.slotsLoading || s.draft.selection == null
                ? null
                : cubit.slots,
            icon: s.slotsLoading
                ? const AppRefreshIndicator(
                    label: 'Checking availability…',
                    iconOnly: true,
                  )
                : const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      Text(
        s.option?.fixedTime != null
            ? 'This session has a fixed start and finish time.'
            : 'Tap start and end. Tap a selected boundary again to clear it.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      if (s.slotsLoading && !s.slotsLoaded)
        const AppLoadingState(initial: true, label: 'Checking availability…'),
      if (s.slotsError != null)
        AppErrorWidget(
          message: s.slotsError!,
          onRetry: s.locked ? null : cubit.slots,
        ),
      if (s.slots.isNotEmpty || s.endSlots.isNotEmpty)
        BookingTimeGrid(
          slots: s.slots,
          cells: s.option?.minimumDuration == null ? null : s.timeCells,
          pool: s.business?.type == 'pool',
          selected: s.choosingEnd
              ? (s.rangeComplete ? s.draft.endTime : null)
              : (s.quote != null || s.checking ? s.draft.time : null),
          choosingEnd: s.choosingEnd,
          minimumDuration: s.option?.minimumDuration,
          selectedDate: s.draft.date,
          enabled: !s.locked,
          onSelected: cubit.chooseSlot,
        )
      else if (!s.slotsLoading)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            s.slotsLoaded
                ? 'No priced slots for these choices. Choose another date, duration or space.'
                : 'Choose a space and booking option to see available times.',
            textAlign: TextAlign.center,
          ),
        ),
      if (s.option != null &&
          s.option!.minimumDuration == null &&
          s.option!.fixedTime == null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: s.locked
                ? null
                : () async {
                    final value = await showAppTimePicker(
                      context: context,
                      initialTime: s.draft.time,
                    );
                    if (value != null && !cubit.isClosed) cubit.time(value);
                  },
            icon: const Icon(Icons.edit_calendar_outlined, size: 18),
            label: const Text('Enter an exact time'),
          ),
        ),
      if (s.checking)
        const AppRefreshIndicator(label: 'Checking availability & price…'),
      if (s.quote != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${bookingLocal(s.quote!.localStart)} → ${bookingLocal(s.quote!.localEnd)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );
  Widget paymentSection(BookingFormModel s) => BookingFormSection(
    number: 4,
    title: 'Payments',
    summary: s.draft.recordedPayments.isEmpty
        ? 'Optional · You can confirm unpaid'
        : '${s.draft.recordedPayments.length} entries · ${bookingMoney(s.draft.received, s.catalog.currency)} received',
    expanded: s.activeSection == 3,
    onToggle: s.locked
        ? null
        : () => cubit.section(s.activeSection == 3 ? -1 : 3),
    children: s.catalog.canCollect
        ? [
            BookingDiscountEditor(model: s, onChanged: cubit.discount),
            BookingPaymentEditor(
              catalog: s.catalog,
              businessId: s.draft.businessId,
              spaceId: s.draft.spaceId,
              payments: s.draft.editablePayments,
              enabled: !s.locked,
              currency: s.catalog.currency,
              onAdd: cubit.addPayment,
              remainingFor: s.paymentBalance,
              paymentError: s.paymentError,
              onPayBalance: cubit.payBalance,
              onRemove: cubit.removePayment,
              onUpdate: cubit.updatePayment,
            ),
          ]
        : [
            const Text(
              'You can confirm unpaid. Ask an authorized staff member to record collections.',
            ),
          ],
  );
  Widget review(BookingFormModel s) {
    final d = s.draft, q = s.quote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReviewTag(
                q == null ? 'Verifying booking' : 'Ready to confirm',
                active: q != null,
              ),
              const SizedBox(height: 16),
              Text(
                q?.spaceName ?? s.space?.name ?? '',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${q?.businessName ?? s.business?.name ?? ''} · ${q?.optionName ?? s.option?.name ?? ''}',
              ),
              const SizedBox(height: 14),
              ReviewDetail(
                label: 'Date & time',
                value: q == null
                    ? '${d.date} · ${d.time} → ${d.endTime}'
                    : '${bookingLocal(q.localStart)} → ${bookingLocal(q.localEnd)}',
              ),
              if (q != null)
                Text(q.timezone, style: Theme.of(context).textTheme.bodySmall),
              if (s.checking)
                const AppRefreshIndicator(
                  label: 'Verifying price & availability…',
                ),
              if (s.business?.type == 'pool' || s.business?.type == 'hall')
                Text('${d.people} participants / guests'),
              if (d.discount != null) ...[
                const Divider(height: 24),
                ReviewDetail(
                  label: 'Discount',
                  value: d.discount!.type == 'percent'
                      ? '${d.discount!.value}%'
                      : bookingMoney(
                          d.discount!.units ?? 0,
                          s.catalog.currency,
                        ),
                ),
                if (d.discount!.reason.trim().isNotEmpty)
                  Text(d.discount!.reason),
              ],
              const Divider(height: 24),
              ReviewDetail(
                label: 'Customer',
                value: '${d.customer.name}\n${d.customer.phone}',
              ),
              if (d.notes.isNotEmpty) Text(d.notes),
              if (s.original != null) ...[
                const Divider(height: 24),
                Text('Previously ${bookingLocal(s.original!.localStart)}'),
                Text(
                  'Previous price ${bookingMoney(s.original!.total, s.catalog.currency)}',
                ),
                Text('Reason: ${d.reason}'),
                if ((s.refund ?? 0) > 0)
                  const ReviewNote(
                    'A refund is due and must be recorded separately after rescheduling.',
                  ),
              ] else ...[
                const Divider(height: 24),
                for (final p in d.recordedPayments)
                  ReviewRate(
                    label: paymentLabel(p.method),
                    price: bookingMoney(p.minor ?? 0, s.catalog.currency),
                  ),
                if (d.recordedPayments.isEmpty) const Text('Confirming unpaid'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: s.locked ? null : cubit.editReview,
          child: const Text('Edit booking details'),
        ),
      ],
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<BookingFormCubit, BookingFormModel>(
    bloc: cubit,
    listener: (context, s) {
      if (s.resultId != null) {
        if (s.original != null && context.canPop()) {
          setState(() => leaving = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.pop();
          });
        } else {
          context.replace('/booking/${s.resultId}?created=1');
        }
      }
    },
    builder: (context, s) => PopScope(
      canPop: leaving || !s.locked,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) back();
      },
      child: AppPage(
        showAppBar: true,
        compactHeader: true,
        title: s.original == null ? 'New booking' : 'Reschedule booking',
        scrollId: 'booking-form',
        maxWidth: 760,
        actions: [
          IconButton(
            tooltip: 'Close booking',
            onPressed: back,
            icon: const Icon(Icons.close),
          ),
        ],
        bottomBar:
            s.loading || !s.catalog.canManage || s.catalog.businesses.isEmpty
            ? null
            : BookingConfirmBar(
                model: s,
                onReview: cubit.review,
                onConfirm: cubit.confirm,
              ),
        children: [
          if (s.loading)
            const AppLoadingState(
              initial: true,
              label: 'Loading booking options…',
            ),
          if (s.error != null) ...[
            AppErrorWidget(
              message: s.error!,
              onRetry: s.catalog.businesses.isEmpty ? cubit.load : null,
            ),
            const SizedBox(height: 16),
          ],
          if (!s.loading && s.catalog.businesses.isEmpty)
            const AppEmptyState(
              showCard: false,
              title: 'No bookable businesses',
              message:
                  'Activate a business with configured spaces first, or ask the owner for access.',
            ),
          if (!s.loading &&
              s.catalog.canManage &&
              s.catalog.businesses.isNotEmpty)
            if (s.review)
              review(s)
            else ...[
              customerSection(s),
              spaceSection(s),
              timeSection(s),
              if (s.original == null)
                paymentSection(s)
              else
                BookingFormSection(
                  number: 4,
                  title: 'Reschedule reason',
                  summary: 'Existing payments stay attached to this booking.',
                  children: [
                    ConfigurationField(
                      label: 'Reschedule reason',
                      value: s.draft.reason,
                      enabled: !s.locked,
                      onChanged: cubit.reason,
                    ),
                  ],
                ),
            ],
        ],
      ),
    ),
  );
}

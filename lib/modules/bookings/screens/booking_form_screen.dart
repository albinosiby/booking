import 'dart:async';
import '../../admissions/widgets/admission_form_fields.dart';
import '../../admissions/cubit/admission_cubit.dart';
import '../../admissions/cubit/admission_state.dart';
import '../../admissions/models/admission_models.dart';
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
  bool switchingPool = false;
  AdmissionCubit? admission;
  AdmissionDraft? admissionBaseline;
  @override
  void initState() {
    super.initState();
    cubit.load();
  }

  @override
  void dispose() {
    admission?.close();
    cubit.close();
    super.dispose();
  }

  Future<void> poolMode(PoolBookingMode mode) async {
    final s = cubit.state, a = admission;
    if (switchingPool ||
        mode == s.poolMode ||
        s.locked ||
        a?.state.loading == true ||
        a?.state.busy == true ||
        a?.state.locked == true) {
      return;
    }
    switchingPool = true;
    try {
      final dirty = s.poolMode == PoolBookingMode.singleVisit
          ? s.rangeComplete ||
                s.draft.recordedPayments.isNotEmpty ||
                s.draft.discount != null
          : admissionBaseline != null &&
                a != null &&
                a.state.draft.copyWith(customer: admissionBaseline!.customer) !=
                    admissionBaseline;
      if (dirty) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(
              s.business?.type == 'pool'
                  ? 'Change pool option?'
                  : 'Change booking option?',
            ),
            content: Text(
              'The current schedule, plan and payment entries will be cleared. Your customer and selected ${s.business?.type == 'pool' ? 'pool' : 'court'} will stay.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Change option'),
              ),
            ],
          ),
        );
        if (discard != true || !mounted || cubit.isClosed) return;
      }
      if (!mounted ||
          cubit.isClosed ||
          cubit.state.draft.businessId != s.draft.businessId ||
          cubit.state.draft.spaceId != s.draft.spaceId ||
          cubit.state.poolMode != s.poolMode ||
          (a != null && !a.authorized)) {
        return;
      }
      final customer = s.poolMode == PoolBookingMode.singleVisit
          ? s.draft.customer
          : a?.state.draft.customer ?? s.draft.customer;
      if (mode == PoolBookingMode.singleVisit) {
        cubit.poolMode(mode, customer: customer);
        admission = null;
        admissionBaseline = null;
        if (a != null) unawaited(a.close());
      } else {
        final controller = getIt<AdmissionCubit>(
          param1: context.read<WorkspaceCubit>(),
        );
        admission = controller;
        admissionBaseline = null;
        final loading = controller.loadForm(
          cachedCatalog: a?.reusableCatalog,
          cachedAt: a?.catalogLoadedAt,
          businessId: s.draft.businessId,
          poolId: s.draft.spaceId,
          date: s.draft.date,
          customer: customer,
          // Court businesses sell `play` plans where pools sell swimming plans.
          formKind:
              mode == PoolBookingMode.swimming && s.business?.type != 'pool'
              ? 'play'
              : mode.name,
          strictLocation: true,
        );
        cubit.poolMode(mode, customer: customer);
        if (a != null) unawaited(a.close());
        await loading;
        if (mounted && !controller.isClosed) {
          admissionBaseline = controller.state.draft;
        }
      }
    } finally {
      switchingPool = false;
    }
  }

  Widget poolOptions(BookingFormModel s, {bool enabled = true}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in PoolBookingMode.values)
              ChoiceChip(
                label: Text(switch (mode) {
                  PoolBookingMode.singleVisit =>
                    s.business?.type == 'pool'
                        ? 'Single visit'
                        : 'Court booking',
                  PoolBookingMode.swimming =>
                    s.business?.type == 'pool' ? 'Swimming plan' : 'Court plan',
                  PoolBookingMode.coaching => 'Coaching',
                }),
                selected: s.poolMode == mode,
                onSelected: enabled ? (_) => poolMode(mode) : null,
              ),
          ],
        ),
      ],
    ),
  );

  void back() {
    if (cubit.state.locked ||
        admission?.state.locked == true ||
        admission?.state.busy == true) {
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

  Widget customerSection(BookingFormModel s, [AdmissionState? a]) {
    final customer = a?.draft.customer ?? s.draft.customer;
    final enabled =
        !(s.locked ||
            a?.loading == true ||
            a?.busy == true ||
            a?.locked == true);
    return BookingFormSection(
      number: 1,
      title: 'Customer',
      children: s.original != null
          ? [
              Text(
                customer.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(customer.phone),
              const SizedBox(height: 8),
              const Text(
                'Customer details and existing payments stay attached.',
              ),
            ]
          : [
              BookingCustomerFields(
                compact: true,
                customer: customer,
                notes: s.draft.notes,
                showNotes: a == null,
                enabled: enabled,
                onName: a == null
                    ? cubit.customerName
                    : (v) => admission!.update(
                        a.draft.copyWith(
                          customer: customer.copyWith(name: v, clearId: true),
                        ),
                      ),
                onPhone: a == null
                    ? cubit.customerPhone
                    : admission!.customerPhone,
                onEmail: a == null
                    ? cubit.customerEmail
                    : (v) => admission!.update(
                        a.draft.copyWith(customer: customer.copyWith(email: v)),
                      ),
                onNotes: cubit.notes,
              ),
              if (customer.name.trim().isEmpty)
                for (final match in a?.customers ?? s.customers)
                  ListTile(
                    title: Text(match.name),
                    subtitle: Text(match.phone),
                    onTap: !enabled
                        ? null
                        : () => a == null
                              ? cubit.chooseCustomer(match)
                              : admission!.chooseCustomer(match),
                  ),
            ],
    );
  }

  Future<void> location(String id, {bool space = false}) async {
    if (id ==
        (space ? cubit.state.draft.spaceId : cubit.state.draft.businessId)) {
      return;
    }
    final a = admission;
    if (a == null) {
      space ? cubit.chooseSpace(id) : cubit.chooseBusiness(id);
      return;
    }
    if (a.state.loading || a.state.busy || a.state.locked) return;
    final mode = cubit.state.poolMode;
    await poolMode(PoolBookingMode.singleVisit);
    if (!mounted || cubit.state.poolMode != PoolBookingMode.singleVisit) return;
    space ? cubit.chooseSpace(id) : cubit.chooseBusiness(id);
    if (admissionBusinessTypes.contains(cubit.state.business?.type) &&
        cubit.state.space != null) {
      await poolMode(mode);
    }
  }

  Widget spaceSection(BookingFormModel s, [AdmissionState? a]) =>
      BookingSpaceSelection(
        model: s.copyWith(
          saving:
              s.saving ||
              a?.loading == true ||
              a?.busy == true ||
              a?.locked == true,
        ),
        businesses: s.original == null
            ? orderedWorkspaceBusinesses(
                context,
                s.catalog.businesses,
                (b) => b.id,
              )
            : [if (s.business != null) s.business!],
        onBusiness: (id) => location(id),
        onSport: cubit.chooseSport,
        onSpace: (id) => location(id, space: true),
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
          showDayOffset: !s.open24Hours,
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

  Widget admissionSection(BookingFormModel s, AdmissionState a) =>
      BookingFormSection(
        number: 3,
        title: s.poolMode == PoolBookingMode.coaching
            ? 'Coaching plan'
            : s.business?.type == 'pool'
            ? 'Swimming plan'
            : 'Court plan',
        children: [
          if (a.loading) const AppLoadingState(initial: false),
          if (a.error != null) AppErrorWidget(message: a.error!),
          if (!a.loading && a.availablePlans.isEmpty) ...[
            const AppEmptyState(
              showCard: false,
              title: 'No matching plans',
              message: 'Configure a plan for this space to continue.',
            ),
            if (a.catalog.owner)
              TextButton(
                onPressed: () =>
                    context.push('/businesses/${s.draft.businessId}/settings'),
                child: const Text('Configure plans'),
              ),
          ] else if (!a.loading) ...[
            if (a.preview != null) ...[
              AdmissionReviewSummary(state: a),
              TextButton(
                onPressed: a.locked || a.busy ? null : admission!.edit,
                child: const Text('Edit admission details'),
              ),
            ] else
              AdmissionScheduleFields(cubit: admission!, state: a),
          ],
        ],
      );
  Widget admissionPayments(AdmissionState a) => BookingFormSection(
    number: 4,
    title: 'Payments',
    summary: 'Optional · you can confirm unpaid',
    children: [
      if (a.loading)
        const Text('Loading payment settings…')
      else if (a.catalog.canCollect)
        AdmissionPaymentFields(cubit: admission!, state: a)
      else
        const Text(
          'You can confirm unpaid. Payment collection requires permission.',
        ),
    ],
  );
  Widget admissionConfirm(AdmissionState a) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL'),
                Text(
                  a.plan == null
                      ? '—'
                      : bookingMoney(
                          a.paymentEntry.total ?? 0,
                          a.catalog.currency,
                        ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: AppButton(
              label: a.locked
                  ? 'Retry confirmation'
                  : a.preview == null
                  ? 'Review admission'
                  : 'Confirm admission',
              busy: a.busy,
              onPressed:
                  a.loading || a.busy || !a.catalog.canManage || a.plan == null
                  ? null
                  : a.locked
                  ? admission!.retry
                  : a.preview == null
                  ? admission!.review
                  : admission!.create,
            ),
          ),
        ],
      ),
    ),
  );

  Widget page(BookingFormModel s, [AdmissionState? a]) {
    final locked = s.locked || a?.busy == true || a?.locked == true;
    // Desktop web: details on the left, payment beside them.
    final wide = isDesktopWidth(context);
    return PopScope(
      canPop: leaving || !locked,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) back();
      },
      child: AppPage(
        showAppBar: true,
        compactHeader: true,
        title: s.original == null ? 'New booking' : 'Reschedule booking',
        scrollId: 'booking-form',
        maxWidth: wide ? 1180 : 760,
        actions: [
          IconButton(
            tooltip: 'Close booking',
            onPressed: back,
            icon: const Icon(Icons.close),
          ),
        ],
        bottomBar:
            s.loading ||
                !s.catalog.canManage ||
                s.catalog.businesses.isEmpty ||
                (wide && !s.review && a == null)
            ? null
            : a != null
            ? admissionConfirm(a)
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
            if (s.review && a == null)
              wide
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: review(s),
                      ),
                    )
                  : review(s)
            else if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: details(s, a, locked),
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        settlement(s, a),
                        if (a == null) ...[
                          const SizedBox(height: 16),
                          BookingConfirmBar(
                            model: s,
                            onReview: cubit.review,
                            onConfirm: cubit.confirm,
                            inline: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              ...details(s, a, locked),
              settlement(s, a),
            ],
        ],
      ),
    );
  }

  List<Widget> details(BookingFormModel s, AdmissionState? a, bool locked) => [
    customerSection(s, a),
    spaceSection(s, a),
    if (s.original == null &&
        admissionBusinessTypes.contains(s.business?.type) &&
        s.space != null)
      poolOptions(s, enabled: !locked && a?.loading != true),
    if (a == null) timeSection(s) else admissionSection(s, a),
  ];

  Widget settlement(BookingFormModel s, AdmissionState? a) => s.original == null
      ? a == null
            ? paymentSection(s)
            : admissionPayments(a)
      : BookingFormSection(
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
        );

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<BookingFormCubit, BookingFormModel>(
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
        builder: (context, s) =>
            s.poolMode != PoolBookingMode.singleVisit && admission != null
            ? BlocConsumer<AdmissionCubit, AdmissionState>(
                key: ObjectKey(admission),
                bloc: admission,
                listenWhen: (p, n) => p.savedId != n.savedId,
                listener: (context, a) {
                  if (a.savedId != null) {
                    context.replace('/admissions/${a.savedId}');
                  }
                },
                builder: (context, a) => page(s, a),
              )
            : page(s),
      );
}

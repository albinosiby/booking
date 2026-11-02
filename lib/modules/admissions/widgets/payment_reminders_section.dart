import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../utils/helpers/subscription_labels.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/models/slot_holder.dart' show weekdayNames;
import '../cubit/payment_reminders_cubit.dart';
import '../models/admission_models.dart';
import '../repositories/admission_repository.dart';
import 'admission_payment_sheet.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `2026-10-04` → `Oct 2026`, naming the term a due amount belongs to.
String termMonth(String date) {
  final d = DateTime.tryParse(date);
  return d == null ? date : '${_months[d.month - 1]} ${d.year}';
}

/// Home reminders: next month due soon, and money still owed after a term ends.
class PaymentRemindersSection extends StatelessWidget {
  const PaymentRemindersSection({
    super.key,
    required this.repository,
    required this.canRenew,
    required this.canCollect,
    required this.showAmounts,
    required this.currency,
  });
  final MembershipActions repository;
  final bool canRenew, canCollect, showAmounts;
  final String currency;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ReminderGroup(
        key: const ValueKey('payment-reminders-due-soon'),
        repository: repository,
        group: 'due_soon',
        canRenew: canRenew,
        canCollect: canCollect,
        showAmounts: showAmounts,
        currency: currency,
      ),
      if (showAmounts)
        _ReminderGroup(
          key: const ValueKey('payment-reminders-unpaid'),
          repository: repository,
          group: 'unpaid',
          canRenew: canRenew,
          canCollect: canCollect,
          showAmounts: showAmounts,
          currency: currency,
        ),
    ],
  );
}

class _ReminderGroup extends StatefulWidget {
  const _ReminderGroup({
    super.key,
    required this.repository,
    required this.group,
    required this.canRenew,
    required this.canCollect,
    required this.showAmounts,
    required this.currency,
  });
  final MembershipActions repository;
  final String group;
  final bool canRenew, canCollect, showAmounts;
  final String currency;
  @override
  State<_ReminderGroup> createState() => _ReminderGroupState();
}

class _ReminderGroupState extends State<_ReminderGroup>
    with WidgetsBindingObserver {
  late final cubit = PaymentRemindersCubit(widget.repository, widget.group)
    ..load();
  Timer? timer;
  bool foreground = true;
  bool get dueSoon => widget.group == 'due_soon';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (foreground) cubit.load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) cubit.load();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    cubit.close();
    super.dispose();
  }

  Future<void> open(String path) async {
    await context.push(path);
    if (mounted) cubit.load();
  }

  Future<void> collect(Admission a) async {
    final result = await showAdaptiveSheet<(List<BookingPaymentDraft>, String)>(
      context: context,
      scrollable: false,
      showDragHandle: false,
      builder: (_) => AdmissionPaymentSheet(
        refund: false,
        currency: widget.currency,
        limit: due(a),
        title: 'Collect from ${a.customer.name}',
        subtitle:
            '${bookingMoney(due(a), widget.currency)} due · ${a.planName}',
      ),
    );
    if (result != null && mounted) await act(() => cubit.collect(a, result.$1));
  }

  /// Home shows no inline errors: a failed action is reported once.
  Future<void> act(Future<void> Function() action) async {
    await action();
    final error = cubit.state.error;
    if (mounted && error != null) showMessage(context, error);
  }

  /// What to collect now: started subscription months, or a plan's balance.
  int due(Admission a) => a.subscription == null ? a.balance : a.owedNow;

  String schedule(Admission a) => a.membershipOnly
      ? 'Membership'
      : [
          if (a.weekdays.isNotEmpty) weekdayNames(a.weekdays),
          hoursLabel(a.duration),
        ].join(' · ');

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<PaymentRemindersCubit, PaymentRemindersState>(
    bloc: cubit,
    builder: (context, state) {
      // Hidden until there is something to collect; loads update in place.
      if (state.uncertainId == null && state.items.isEmpty) {
        return const SizedBox.shrink();
      }
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dueSoon ? 'Due soon' : 'Collect now',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: dueSoon
                        ? 'Refresh next month due'
                        : 'Refresh unpaid amounts',
                    onPressed: state.loading ? null : () => cubit.load(),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Text(
                dueSoon
                    ? 'Next monthly fees and plans ending in the next few days.'
                    : 'Subscription months that have started, and plans with money still owed. Enter any amount; the rest stays here until paid.',
              ),
              if (state.uncertainId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'We could not confirm the last payment. Retry sends the same payment once.',
                        ),
                      ),
                      TextButton(
                        onPressed: state.collectingId != null
                            ? null
                            : () => act(cubit.retry),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              if (state.notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    state.notice!,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ),
              for (final a in state.items)
                Padding(
                  key: ValueKey('${widget.group}-${a.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.customer.name, style: theme.textTheme.titleMedium),
                      Text(
                        '${a.planName} · ${schedule(a)} · ${a.businessName}',
                      ),
                      if (dueSoon && a.nextDueOn != null)
                        Text(
                          widget.showAmounts && a.nextDue != null
                              ? 'Next month ${bookingMoney(a.nextDue!, widget.currency)} due ${a.nextDueOn}'
                              : 'Next month due ${a.nextDueOn}',
                        )
                      else
                        Text(
                          a.today.isNotEmpty && a.today.compareTo(a.expiry) > 0
                              ? 'Ended ${a.expiry}'
                              : 'Ends ${a.expiry}',
                        ),
                      if (widget.showAmounts && due(a) > 0)
                        Text(
                          a.subscription == null
                              ? '${bookingMoney(due(a), widget.currency)} due for ${termMonth(a.start)}'
                              : '${bookingMoney(due(a), widget.currency)} due now',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          if (dueSoon &&
                              widget.canRenew &&
                              a.canRenew &&
                              a.nextDueOn == null)
                            FilledButton.icon(
                              onPressed: () => open(
                                '/admissions/new?renewal_id=${a.id}${widget.canCollect ? '&collect=true' : ''}',
                              ),
                              icon: const Icon(Icons.autorenew),
                              label: Text(
                                widget.canCollect ? 'Renew & collect' : 'Renew',
                              ),
                            ),
                          if (widget.canCollect && due(a) > 0)
                            OutlinedButton.icon(
                              key: ValueKey('collect-${a.id}'),
                              // An unconfirmed payment must be retried first.
                              onPressed:
                                  state.collectingId != null ||
                                      state.uncertainId != null
                                  ? null
                                  : () => collect(a),
                              icon: const Icon(Icons.payments_outlined),
                              label: Text(
                                state.collectingId == a.id
                                    ? 'Collecting…'
                                    : 'Collect',
                              ),
                            ),
                          TextButton(
                            onPressed: () => open('/admissions/${a.id}'),
                            child: Text(
                              a.subscription == null
                                  ? 'View membership'
                                  : 'View subscription',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (state.next != null)
                OutlinedButton(
                  onPressed: state.loading
                      ? null
                      : () => cubit.load(more: true),
                  child: const Text('Load more'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

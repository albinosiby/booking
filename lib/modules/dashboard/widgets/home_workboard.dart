import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../utils/helpers/subscription_labels.dart';
import '../../admissions/cubit/expired_members_cubit.dart';
import '../../admissions/cubit/payment_reminders_cubit.dart';
import '../../admissions/models/admission_models.dart';
import '../../admissions/repositories/admission_repository.dart';
import '../../admissions/widgets/admission_payment_sheet.dart';
import '../../bookings/models/booking_models.dart';
import '../../workspace/models/workspace.dart';
import '../../workspace/models/workspace_navigation.dart';
import '../cubit/home_cubit.dart';
import '../models/home_screen_model.dart';
import 'home_parts.dart';

/// Home below the status cards: Collect payments, Today's schedule and
/// Renewals. Each card is a list of rows with one clear action.
class HomeWorkboard extends StatefulWidget {
  const HomeWorkboard({
    super.key,
    required this.model,
    required this.cubit,
    this.memberships,
  });
  final HomeScreenModel model;
  final HomeCubit cubit;
  final MembershipActions? memberships;
  @override
  State<HomeWorkboard> createState() => _HomeWorkboardState();
}

class _HomeWorkboardState extends State<HomeWorkboard>
    with WidgetsBindingObserver {
  Workspace get workspace => widget.model.data;
  bool can(String permission) => workspace.hasPermission(permission);
  bool get canCollect => can('collect_payments');
  bool get canRenew => can('manage_subscriptions');
  bool get showAmounts => can('view_finance') || canCollect;
  bool get members =>
      widget.memberships != null &&
      [
        'manage_subscriptions',
        'collect_payments',
        'view_bookings',
        'manage_bookings',
      ].any(can);
  bool get ready => workspace.businesses.any((b) => b.ready);
  bool get bookings => ready && WorkspaceNavigation(workspace).bookings;
  bool get bookingDues => ready && showAmounts;
  String get currency => workspace.organization?.currency ?? 'INR';

  PaymentRemindersCubit? unpaid, dueSoon;
  ExpiredMembersCubit? expired;
  Timer? timer;
  bool foreground = true;

  @override
  void initState() {
    super.initState();
    if (members) {
      dueSoon = PaymentRemindersCubit(widget.memberships!, 'due_soon')..load();
      if (showAmounts) {
        unpaid = PaymentRemindersCubit(widget.memberships!, 'unpaid')..load();
      }
      expired = ExpiredMembersCubit(widget.memberships!)..load();
      WidgetsBinding.instance.addObserver(this);
      timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (foreground) reloadReminders();
      });
    }
  }

  void reloadReminders() {
    unpaid?.load();
    dueSoon?.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) reloadReminders();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unpaid?.close();
    dueSoon?.close();
    expired?.close();
    super.dispose();
  }

  Future<void> open(String path) async {
    await context.push(path);
    if (!mounted) return;
    reloadReminders();
    expired?.load();
  }

  /// Home shows no inline errors: an action reports its outcome once.
  Future<void> act(Future<void> Function() action) async {
    await action();
    final s = unpaid?.state;
    if (!mounted || s == null) return;
    final message = s.error ?? s.notice;
    if (message != null) showMessage(context, message);
  }

  Future<void> collect(Admission a) async {
    final result = await showAdaptiveSheet<(List<BookingPaymentDraft>, String)>(
      context: context,
      scrollable: false,
      showDragHandle: false,
      builder: (_) => AdmissionPaymentSheet(
        refund: false,
        currency: currency,
        limit: a.collectNow,
        title: 'Collect from ${a.customer.name}',
        subtitle: '${bookingMoney(a.collectNow, currency)} due · ${a.planName}',
      ),
    );
    if (result != null && mounted) {
      await act(() => unpaid!.collect(a, result.$1));
    }
  }

  String place(Admission a) =>
      a.poolName.isEmpty ? a.businessName : '${a.poolName} · ${a.businessName}';

  @override
  Widget build(BuildContext context) => _Listen(
    blocs: [unpaid, dueSoon, expired],
    builder: (context) {
      final collect = showAmounts && (bookingDues || unpaid != null)
          ? collectCard(context)
          : null;
      final schedule = bookings ? scheduleCard(context) : null;
      final renewals = renewalsCard(context);
      return LayoutBuilder(
        builder: (context, constraints) {
          final side = [?collect, ?renewals];
          if (constraints.maxWidth >= 900 &&
              MediaQuery.textScalerOf(context).scale(14) <= 21 &&
              schedule != null &&
              side.isNotEmpty) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: schedule),
                SizedBox(width: 20),
                Expanded(flex: 2, child: _stack(side)),
              ],
            );
          }
          return _stack([?collect, ?schedule, ?renewals]);
        },
      );
    },
  );

  Widget _stack(List<Widget> cards) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final card in cards) ...[card, SizedBox(height: 16)],
    ],
  );

  Widget collectCard(BuildContext context) {
    final s = widget.model, u = unpaid?.state;
    final scheme = Theme.of(context).colorScheme;
    final owed = AppColors.owed(context);
    final members = u?.items.where((a) => a.collectNow > 0).toList() ?? [];
    final dues = bookingDues ? s.dueBookings : const <BookingOutstanding>[];
    final total =
        members.fold<int>(0, (n, a) => n + a.collectNow) +
        (bookingDues
            ? s.dueTotal ?? dues.fold<int>(0, (n, b) => n + b.balance)
            : 0);
    final settled =
        (u == null || !u.loading) &&
        (!bookingDues || s.dueTotal != null || s.dueError != null);
    final failed =
        (u?.error != null || s.dueError != null) &&
        members.isEmpty &&
        dues.isEmpty;
    final busy = u?.collectingId != null || u?.uncertainId != null;
    return HomeSection(
      key: const ValueKey('home-collect'),
      icon: Icons.payments_outlined,
      title: 'Collect payments',
      summary: total > 0 ? homeMoney(total, currency) : null,
      footer: [
        if (u?.next != null)
          TextButton(
            onPressed: u!.loading ? null : () => unpaid!.load(more: true),
            child: const Text('Show more memberships'),
          ),
        if (bookingDues && s.dueNext != null)
          TextButton(
            onPressed: s.dueLoading
                ? null
                : () => widget.cubit.loadDue(more: true),
            child: const Text('Show more bookings'),
          ),
      ],
      children: [
        if (u?.uncertainId != null)
          HomeTaskRow(
            leading: Icon(Icons.sync_problem_outlined, color: scheme.error),
            title: 'Payment not confirmed',
            subtitle: 'Retry sends the same payment once.',
            action: HomeRowAction(
              label: 'Retry',
              onPressed: u!.collectingId != null
                  ? null
                  : () => act(unpaid!.retry),
            ),
          ),
        for (final a in members)
          HomeTaskRow(
            key: ValueKey('unpaid-${a.id}'),
            title: a.customer.name,
            subtitle: '${a.planName} · ${place(a)}',
            meta: a.subscription == null
                ? 'Plan for ${termMonth(a.start)}'
                : 'Monthly fee due now',
            amount: homeMoney(a.collectNow, currency),
            amountColor: owed,
            onTap: () => open('/admissions/${a.id}'),
            action: canCollect
                ? HomeRowAction(
                    key: ValueKey('collect-${a.id}'),
                    label: u!.collectingId == a.id ? 'Collecting…' : 'Collect',
                    // An unconfirmed payment must be retried first.
                    onPressed: busy ? null : () => collect(a),
                  )
                : null,
          ),
        for (final b in dues)
          HomeTaskRow(
            key: ValueKey('due-${b.id}'),
            title: b.customer,
            subtitle: '${b.space} · ${b.business}',
            meta:
                'Booking ${homeDate(b.localStart.split('T').first)} · ${homeTime(b.localStart.split('T').last)}',
            amount: homeMoney(b.balance, currency),
            amountColor: owed,
            onTap: () => context.push('/booking/${b.id}'),
            action: canCollect && b.status != 'cancelled'
                ? HomeRowAction(
                    label: 'Collect',
                    onPressed: () =>
                        context.push('/booking/${b.id}?action=collect'),
                  )
                : null,
          ),
        if (members.isEmpty && dues.isEmpty && u?.uncertainId == null)
          if (failed && settled)
            AppSectionFallback(
              message: 'Couldn’t load payments to collect right now.',
              onRetry: () {
                unpaid?.load();
                if (bookingDues) widget.cubit.loadDue();
              },
            )
          else if (settled)
            const HomeEmptyLine(message: 'Nothing to collect. All paid up.'),
      ],
    );
  }

  Widget scheduleCard(BuildContext context) {
    final s = widget.model;
    final scheme = Theme.of(context).colorScheme;
    final list = [...?s.dashboard?.upcoming]
      ..sort((a, b) => a.localStart.compareTo(b.localStart));
    return HomeSection(
      key: const ValueKey('home-schedule'),
      icon: Icons.event_note_outlined,
      title: 'Today’s schedule',
      summary: list.isEmpty ? null : '${list.length} upcoming',
      children: [
        for (final b in list)
          HomeTaskRow(
            key: ValueKey('schedule-${b.id}'),
            leading: HomeTimeTile(b.localStart.split('T').last),
            title: b.customer.name,
            subtitle: '${b.spaceName} · ${b.businessName}',
            meta:
                '${homeTime(b.localStart.split('T').last)} – ${homeTime(b.localEnd.split('T').last)}',
            amount: !showAmounts
                ? null
                : b.balance > 0
                ? '${homeMoney(b.balance, currency)} due'
                : 'Paid',
            amountColor: b.balance > 0
                ? AppColors.owed(context)
                : scheme.primary,
            onTap: () => context.push('/booking/${b.id}'),
          ),
        if (list.isEmpty)
          if (s.dashboard == null &&
              s.bookingError != null &&
              !s.bookingLoading)
            AppSectionFallback(
              message: 'Couldn’t load bookings right now.',
              onRetry: widget.cubit.loadDashboard,
            )
          else if (s.dashboard != null)
            const HomeEmptyLine(
              message: 'No more bookings today.',
              icon: Icons.event_available_outlined,
            ),
      ],
    );
  }

  Widget? renewalsCard(BuildContext context) {
    final soon = dueSoon?.state.items ?? const <Admission>[];
    final ended = expired?.state.items ?? const <Admission>[];
    if (soon.isEmpty && ended.isEmpty) return null;
    String renewLabel() => canCollect ? 'Renew & collect' : 'Renew';
    String renewPath(Admission a) =>
        '/admissions/new?renewal_id=${a.id}${canCollect ? '&collect=true' : ''}';
    return HomeSection(
      key: const ValueKey('home-renewals'),
      icon: Icons.autorenew,
      title: 'Renewals',
      summary: '${soon.length + ended.length}',
      footer: [
        if (expired?.state.next != null)
          TextButton(
            onPressed: expired!.state.loading
                ? null
                : () => expired!.load(more: true),
            child: const Text('Show more expired members'),
          ),
      ],
      children: [
        for (final a in soon)
          HomeTaskRow(
            key: ValueKey('due_soon-${a.id}'),
            title: a.customer.name,
            subtitle: '${a.planName} · ${place(a)}',
            meta: a.nextDueOn != null
                ? 'Next fee ${homeDate(a.nextDueOn!, today: a.today)}'
                : 'Plan ends ${homeDate(a.expiry, today: a.today)}',
            amount: showAmounts && a.nextDue != null
                ? homeMoney(a.nextDue!, currency)
                : null,
            onTap: () => open('/admissions/${a.id}'),
            longAction: true,
            action: canRenew && a.canRenew && a.nextDueOn == null
                ? HomeRowAction(
                    label: renewLabel(),
                    onPressed: () => open(renewPath(a)),
                  )
                : null,
          ),
        for (final a in ended)
          HomeTaskRow(
            key: ValueKey('expired-${a.id}'),
            title: a.customer.name,
            subtitle:
                '${a.planName} · ${a.kind == 'coaching' ? 'Coaching' : 'Plan'} · ${a.businessName}',
            meta: 'Expired ${homeDate(a.expiry, today: a.today)}',
            amount: showAmounts && a.balance > 0
                ? '${homeMoney(a.balance, currency)} due'
                : null,
            amountColor: AppColors.owed(context),
            onTap: () => open('/admissions/${a.id}'),
            longAction: true,
            action: canRenew && a.canRenew
                ? HomeRowAction(
                    label: renewLabel(),
                    onPressed: () => open(renewPath(a)),
                  )
                : canCollect && a.balance > 0
                ? HomeRowAction(
                    label: 'Collect amount',
                    primary: false,
                    onPressed: () => open('/admissions/${a.id}?collect=true'),
                  )
                : null,
          ),
      ],
    );
  }
}

/// Rebuilds when any of the given cubits emits.
class _Listen extends StatelessWidget {
  const _Listen({required this.blocs, required this.builder});
  final List<BlocBase<Object?>?> blocs;
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) {
    Widget wrap(int i) {
      if (i == blocs.length) return Builder(builder: builder);
      final bloc = blocs[i];
      if (bloc == null) return wrap(i + 1);
      return BlocBuilder<BlocBase<Object?>, Object?>(
        bloc: bloc,
        builder: (context, _) => wrap(i + 1),
      );
    }

    return wrap(0);
  }
}

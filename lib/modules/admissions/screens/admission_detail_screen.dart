import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/widgets/booking_widgets.dart';
import '../models/admission_models.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_state.dart';
import '../widgets/admission_cards.dart';
import '../../../utils/helpers/time_format.dart';

class AdmissionDetailScreen extends StatefulWidget {
  const AdmissionDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<AdmissionDetailScreen> createState() => _AdmissionDetailScreenState();
}

class _AdmissionDetailScreenState extends State<AdmissionDetailScreen> {
  late final cubit = getIt<AdmissionCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  @override
  void initState() {
    super.initState();
    cubit.loadDetail(widget.id);
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<String?> reason(String title) async {
    String value = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          onChanged: (v) => value = v,
          autofocus: true,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Reason (required)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (value.trim().length >= 2) {
                Navigator.pop(context, value.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> attendance(AdmissionVisit v, String value) async {
    final a = cubit.state.detail!;
    final correction =
        v.attendance != 'unmarked' ||
        a.mode == 'flexible' ||
        DateTime.parse(
          v.endsAt,
        ).isBefore(DateTime.now().subtract(const Duration(days: 1)));
    final why = correction ? await reason('Correct attendance') : '';
    if (why != null && mounted) await cubit.attendance(v, value, why);
  }

  Future<void> checkIn() async {
    // Refresh first so timezone-local date and optimistic version are current.
    await cubit.loadDetail(widget.id);
    if (!mounted) return;
    final a = cubit.state.detail;
    if (a == null || !a.canCheckIn) return;
    final local = DateTime.tryParse(a.localNow) ?? DateTime.now();
    final time = await showTimePicker(
      context: context,
      helpText: 'Visit start time (must include now)',
      initialTime: TimeOfDay(hour: local.hour, minute: local.minute),
    );
    if (time != null && mounted) {
      await cubit.checkIn(
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        a.duration,
      );
    }
  }

  Future<void> payment(bool refund) async {
    final a = cubit.state.detail!;
    final result =
        await showModalBottomSheet<(List<BookingPaymentDraft>, String)>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => _AdmissionPaymentSheet(
            refund: refund,
            currency: cubit.state.catalog.currency,
            limit: refund ? a.paid : a.balance,
          ),
        );
    if (result != null && mounted) {
      await cubit.collect(
        result.$1,
        refund ? 'refund' : 'collection',
        result.$2,
      );
    }
  }

  Future<void> changeSession(AdmissionVisit visit, String action) async {
    final a = cubit.state.detail!;
    String? date, time;
    if (action == 'reschedule') {
      final today = DateTime.parse(a.today), expiry = DateTime.parse(a.expiry);
      if (expiry.isBefore(today)) return;
      final initial = DateTime.parse(visit.start.substring(0, 10));
      final chosen = await showDatePicker(
        context: context,
        initialDate: initial.isBefore(today) ? today : initial,
        firstDate: today,
        lastDate: expiry,
      );
      if (chosen == null || !mounted) return;
      final selected = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: int.parse(visit.start.substring(11, 13)),
          minute: int.parse(visit.start.substring(14, 16)),
        ),
      );
      if (selected == null || !mounted) return;
      date = bookingDate(chosen);
      time =
          '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    }
    final why = await reason(
      action == 'waive'
          ? 'Restore this session credit'
          : action == 'cancel'
          ? 'Cancel this session'
          : 'Reschedule this session',
    );
    if (why != null && mounted) {
      await cubit.sessionChange(visit, action, why, date: date, time: time);
    }
  }

  Future<void> cancelAdmission() async {
    final why = await reason('Cancel admission');
    if (why != null && mounted) await cubit.cancel(why);
  }

  Future<void> renew(Admission a) async {
    await context.push('/admissions/new?renewal_id=${a.id}');
    if (mounted) cubit.loadDetail(widget.id);
  }

  Widget section(String title, {String? trailing}) => Padding(
    padding: EdgeInsets.only(top: 24.h, bottom: 10.h),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing != null)
          Text(trailing, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );

  Widget summary(Admission a, AdmissionState s) {
    final theme = Theme.of(context),
        scheme = theme.colorScheme,
        muted = scheme.onSurface.withValues(alpha: .65),
        unit = a.kind == 'coaching' ? 'classes' : 'days',
        status = admissionStatusColor(context, a.status);
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.planName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      a.reference,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              AdmissionTag(admissionStatusLabel(a.status), color: status),
            ],
          ),
          SizedBox(height: 18.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${a.remaining}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: status,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'of ${a.allowance} $unit left',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      '${a.used} used · ${a.attended} present',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: a.allowance == 0 ? 0 : a.used / a.allowance,
              color: status,
              backgroundColor: scheme.outline.withValues(alpha: .35),
            ),
          ),
          SizedBox(height: 16.h),
          _InfoRow(Icons.phone_outlined, a.customer.phone),
          _InfoRow(
            Icons.place_outlined,
            [a.poolName, a.businessName].where((v) => v.isNotEmpty).join(' · '),
          ),
          _InfoRow(
            Icons.event_outlined,
            '${a.start} → ${a.expiry} (inclusive)',
          ),
          _InfoRow(
            a.mode == 'fixed' ? Icons.event_repeat : Icons.how_to_reg_outlined,
            a.mode == 'fixed'
                ? 'Fixed schedule · sessions count after they end'
                : 'Flexible · one deduction per attendance date',
          ),
          if (a.kind == 'coaching')
            _InfoRow(Icons.person_outline, 'Coach · ${a.coach}'),
          if (a.status == 'expired')
            Padding(
              padding: EdgeInsets.only(top: 8.h),
              child: AdmissionTag(
                '${a.remaining} unused $unit expired · no carry-forward',
                color: admissionStatusColor(context, 'expired'),
                icon: Icons.info_outline,
              ),
            ),
        ],
      ),
    );
  }

  Widget money(Admission a, String currency) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    Widget cell(String label, int value, {Color? color}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: .65),
            ),
          ),
          SizedBox(height: 4.h),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              bookingMoney(value, currency),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          cell('Total', a.total),
          cell('Paid', a.paid, color: scheme.primary),
          cell('Due', a.balance, color: a.balance > 0 ? scheme.error : null),
        ],
      ),
    );
  }

  Widget visit(Admission a, AdmissionVisit v, AdmissionState s, bool enabled) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final (label, color) = v.status == 'cancelled'
        ? ('Cancelled', scheme.error)
        : v.waived
        ? ('Credit restored', const Color(0xFF64B5F6))
        : switch (v.attendance) {
            'present' => ('Present', scheme.primary),
            'absent' => ('Absent', const Color(0xFFFFB74D)),
            _ => (
              v.hasStarted ? 'Unmarked' : 'Upcoming',
              scheme.onSurface.withValues(alpha: .7),
            ),
          };
    final actions = <Widget>[
      if (a.mode == 'fixed' &&
          a.status != 'cancelled' &&
          s.catalog.canManage) ...[
        if (!v.hasStarted || (v.waived && v.replacementId == null)) ...[
          TextButton(
            onPressed: enabled ? () => changeSession(v, 'reschedule') : null,
            child: Text(
              v.waived
                  ? 'Schedule replacement'
                  : v.status == 'cancelled'
                  ? 'Replace session'
                  : 'Reschedule',
            ),
          ),
          if (v.status != 'cancelled' && !v.hasStarted)
            TextButton(
              onPressed: enabled ? () => changeSession(v, 'cancel') : null,
              child: const Text('Cancel session'),
            ),
        ],
        if (v.status != 'cancelled' &&
            !v.waived &&
            s.catalog.owner &&
            DateTime.parse(v.endsAt).isBefore(DateTime.now()))
          TextButton(
            onPressed: enabled ? () => changeSession(v, 'waive') : null,
            child: const Text('Restore credit'),
          ),
      ],
      if (v.status != 'cancelled' &&
          a.status != 'cancelled' &&
          v.hasStarted &&
          s.catalog.canAttend) ...[
        if (v.attendance == 'unmarked' || s.catalog.owner) ...[
          if (v.attendance != 'present')
            TextButton.icon(
              onPressed: enabled ? () => attendance(v, 'present') : null,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Present'),
            ),
          if (v.attendance != 'absent')
            TextButton.icon(
              onPressed: enabled ? () => attendance(v, 'absent') : null,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Absent'),
            ),
        ],
        if (v.attendance != 'unmarked' && s.catalog.owner)
          TextButton(
            onPressed: enabled ? () => attendance(v, 'unmarked') : null,
            child: const Text('Clear'),
          ),
      ],
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.event_outlined, size: 20, color: color),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    '${bookingLocal(v.start)} – ${v.end.length >= 16 ? TimeFormat.display(v.end.substring(11, 16)) : v.end}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AdmissionTag(label, color: color),
                ),
              ],
            ),
            if (actions.isNotEmpty)
              Wrap(spacing: 4.w, children: actions)
            else
              SizedBox(height: 6.h),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AdmissionCubit, AdmissionState>(
    bloc: cubit,
    builder: (context, s) {
      final a = s.detail, enabled = !s.loading && !s.busy && !s.locked;
      final theme = Theme.of(context), scheme = theme.colorScheme;
      final currency = s.catalog.currency;
      final canCancel =
          a != null &&
          ['active', 'upcoming'].contains(a.status) &&
          s.catalog.canManage;
      return PopScope(
        canPop: !s.busy && !s.locked,
        child: AppPage(
          title: a?.customer.name ?? 'Admission',
          back: true,
          scrollId: 'admission-${widget.id}',
          actions: [
            IconButton(
              tooltip: 'Refresh admission',
              onPressed: enabled ? () => cubit.loadDetail(widget.id) : null,
              icon: const Icon(Icons.refresh),
            ),
            if (canCancel)
              PopupMenuButton<String>(
                tooltip: 'More actions',
                enabled: enabled,
                onSelected: (_) => cancelAdmission(),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'cancel',
                    child: Text('Cancel admission'),
                  ),
                ],
              ),
          ],
          children: [
            if (s.loading) AppLoadingState(initial: a == null),
            if (s.error != null) AppErrorWidget(message: s.error!),
            if (s.locked && !s.busy)
              AppButton(label: 'Retry action', onPressed: cubit.retry),
            if (a != null) ...[
              summary(a, s),
              SizedBox(height: 12.h),
              money(a, currency),
              SizedBox(height: 16.h),
              if (a.canCheckIn && s.catalog.canAttend) ...[
                AppButton(
                  label: 'Mark present',
                  icon: Icons.how_to_reg,
                  onPressed: enabled ? checkIn : null,
                ),
                SizedBox(height: 10.h),
              ],
              if (a.canRenew && s.catalog.canManage) ...[
                AppButton(
                  label: 'Renew plan',
                  icon: Icons.autorenew,
                  onPressed: enabled ? () => renew(a) : null,
                ),
                SizedBox(height: 10.h),
              ],
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  if (a.renewalId != null)
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/admissions/${a.renewalId}'),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('View renewal'),
                    ),
                  if (a.balance > 0 && s.catalog.canCollect)
                    OutlinedButton.icon(
                      onPressed: enabled ? () => payment(false) : null,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Collect payment'),
                    ),
                  if (a.paid > 0 && s.catalog.owner)
                    OutlinedButton.icon(
                      onPressed: enabled ? () => payment(true) : null,
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Record refund'),
                    ),
                ],
              ),
              if (s.busy) const AppLoadingState(initial: false),
              section(
                'Sessions & attendance',
                trailing: a.visits.isEmpty ? null : '${a.visits.length}',
              ),
              if (a.visits.isEmpty)
                AppCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_busy_outlined,
                        color: scheme.onSurface.withValues(alpha: .6),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Text(
                          a.mode == 'flexible'
                              ? 'No visits yet. Tap Mark present when the student arrives.'
                              : 'No sessions scheduled.',
                        ),
                      ),
                    ],
                  ),
                ),
              for (final v in a.visits) visit(a, v, s, enabled),
              section(
                'Payments',
                trailing: a.payments.isEmpty ? null : '${a.payments.length}',
              ),
              if (a.payments.isEmpty)
                const AppCard(child: Text('No payments recorded yet.'))
              else
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final (i, p) in a.payments.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                (p.kind == 'refund'
                                        ? scheme.error
                                        : scheme.primary)
                                    .withValues(alpha: .14),
                            child: Icon(
                              p.kind == 'refund'
                                  ? Icons.north_east
                                  : Icons.south_west,
                              size: 18,
                              color: p.kind == 'refund'
                                  ? scheme.error
                                  : scheme.primary,
                            ),
                          ),
                          title: Text(
                            '${p.kind == 'refund' ? 'Refund' : 'Collected'} · ${admissionMethod(p.method)}',
                          ),
                          subtitle: Text(
                            [
                              admissionTime(p.localReceived),
                              if (p.reason.isNotEmpty) p.reason,
                            ].join('\n'),
                          ),
                          trailing: Text(
                            '${p.kind == 'refund' ? '−' : '+'}${bookingMoney(p.amount, currency)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: p.kind == 'refund'
                                  ? scheme.error
                                  : scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              section('History'),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, e) in a.history.reversed.indexed)
                      _HistoryEntry(
                        title: admissionAction(e.action),
                        time: admissionTime(e.at),
                        reason: e.reason,
                        last: i == a.history.length - 1,
                      ),
                    if (a.history.isEmpty) const Text('No history yet.'),
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

/// Formats an API timestamp in the device's local time.
String admissionTime(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final local = parsed.isUtc ? parsed.toLocal() : parsed;
  return bookingLocal(local.toIso8601String());
}

String admissionMethod(String method) => switch (method) {
  'upi' => 'UPI',
  'card' => 'Card',
  'bank_transfer' => 'Bank transfer',
  _ => 'Cash',
};

String admissionAction(String action) => switch (action) {
  'created' => 'Admission created',
  'renewed' => 'Renewed from previous plan',
  'checked_in' => 'Marked present',
  'attendance' => 'Attendance updated',
  'collection' => 'Payment collected',
  'refund' => 'Refund recorded',
  'cancelled' => 'Admission cancelled',
  'session_cancel' => 'Session cancelled',
  'session_reschedule' => 'Session rescheduled',
  'session_waive' => 'Session credit restored',
  _ =>
    action
        .replaceAll('_', ' ')
        .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase()),
};

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: .65);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({
    required this.title,
    required this.time,
    required this.reason,
    required this.last,
  });
  final String title, time, reason;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: scheme.outline.withValues(alpha: .5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    time,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: .65),
                    ),
                  ),
                  if (reason.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(reason, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdmissionPaymentSheet extends StatefulWidget {
  const _AdmissionPaymentSheet({
    required this.refund,
    required this.currency,
    required this.limit,
  });
  final bool refund;
  final String currency;
  final int limit;
  @override
  State<_AdmissionPaymentSheet> createState() => _AdmissionPaymentSheetState();
}

class _AdmissionPaymentSheetState extends State<_AdmissionPaymentSheet> {
  List<BookingPaymentDraft> payments = [BookingPaymentDraft()];
  String reason = '', error = '';
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
            widget.refund
                ? 'Record admission refund'
                : 'Collect admission payment',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Text('Maximum ${bookingMoney(widget.limit, widget.currency)}'),
          BookingPaymentEditor(
            payments: payments,
            enabled: true,
            currency: widget.currency,
            refund: widget.refund,
            onAdd: () =>
                setState(() => payments = [...payments, BookingPaymentDraft()]),
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
                      'Check the amount and provide a refund reason.',
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

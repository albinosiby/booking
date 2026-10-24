import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/agent_call_cubits.dart';
import '../models/agent_call_models.dart';

String clock(BuildContext context, DateTime time) => MaterialLocalizations.of(
  context,
).formatTimeOfDay(TimeOfDay.fromDateTime(time));

class CallLogsScreen extends StatefulWidget {
  const CallLogsScreen({super.key});
  @override
  State<CallLogsScreen> createState() => _CallLogsScreenState();
}

class _CallLogsScreenState extends State<CallLogsScreen> {
  late final cubit = getIt<CallLogsCubit>(
    param1: context.read<WorkspaceCubit>(),
  );

  /// Call shown in the desktop detail pane.
  String? selected;
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

  Future<void> pickDay(DateTime day) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) cubit.load(picked);
  }

  void open(AgentCall call) {
    final workspace = context.read<WorkspaceCubit>();
    if (MediaQuery.sizeOf(context).width < adaptiveSheetDialogWidth) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => BlocProvider.value(
            value: workspace,
            child: Scaffold(
              body: SafeArea(
                child: CallDetailSheet(call: call, fullScreen: true),
              ),
            ),
          ),
        ),
      );
      return;
    }
    showAdaptiveSheet<void>(
      context: context,
      scrollable: false,
      showClose: false,
      showDragHandle: false,
      maxWidth: 640,
      builder: (_) => BlocProvider.value(
        value: workspace,
        child: CallDetailSheet(call: call),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => BlocBuilder<CallLogsCubit, CallLogsState>(
      bloc: cubit,
      builder: (context, s) {
        if (isDesktopWidth(context) && box.maxWidth >= AppPage.wideWidth) {
          return desktop(context, s);
        }
        final t = Theme.of(context);
        return AppPage(
          title: 'Call logs',
          subtitle: 'Conversations handled by your call service.',
          back: true,
          showAppBar: true,
          compactHeader: true,
          scrollId: 'agent-call-logs',
          actions: [
            IconButton(
              tooltip: 'Refresh calls',
              onPressed: s.loading ? null : () => cubit.load(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          children: [
            dayChips(context, s),
            const SizedBox(height: 16),
            if (s.page.items.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    Text(
                      '${s.page.total} ${s.page.total == 1 ? 'call' : 'calls'}',
                      style: t.textTheme.titleMedium,
                    ),
                    Text(
                      '${talkTime(s.page.items.fold<double>(0, (sum, call) => sum + call.durationSeconds))} talk time in calls shown',
                      style: t.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (s.loading) const AppRefreshIndicator(label: 'Loading calls…'),
            if (s.page.warning.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(s.page.warning),
              ),
            if (s.page.nextOffset != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppButton(
                  label: 'Load more calls',
                  secondary: true,
                  busy: s.loading,
                  onPressed: s.loading ? null : cubit.loadMore,
                ),
              ),
            if (s.error != null)
              AppErrorWidget(message: s.error!, onRetry: () => cubit.load()),
            if (!s.loading && s.error == null && s.page.items.isEmpty)
              const AppEmptyState(
                title: 'No calls',
                message: 'No calls were recorded on this day.',
                icon: Icons.phone_disabled_outlined,
              ),
            if (!s.loading && s.page.total > s.page.items.length)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Showing ${s.page.items.length} of ${s.page.total} calls.',
                  style: t.textTheme.bodySmall,
                ),
              ),
            for (final call in s.page.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  key: ValueKey('mobile-call-${call.id}'),
                  padding: EdgeInsets.zero,
                  child: callRow(context, call, false, onTap: () => open(call)),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget dayChips(BuildContext context, CallLogsState s) {
    final today = DateUtils.dateOnly(DateTime.now());
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Today'),
          selected: s.day == today,
          onSelected: (_) => cubit.load(today),
        ),
        ChoiceChip(
          label: const Text('Yesterday'),
          selected: s.day == today.subtract(const Duration(days: 1)),
          onSelected: (_) =>
              cubit.load(today.subtract(const Duration(days: 1))),
        ),
        ActionChip(
          avatar: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(
            MaterialLocalizations.of(context).formatMediumDate(s.day),
          ),
          onPressed: () => pickDay(s.day),
        ),
      ],
    );
  }

  String meta(BuildContext context, AgentCall call) => [
    if (call.startedAt != null) clock(context, call.startedAt!),
    call.duration,
    call.language,
  ].where((v) => v.isNotEmpty).join(' · ');

  static String talkTime(double seconds) {
    final total = seconds.round();
    final h = total ~/ 3600, m = total % 3600 ~/ 60, sec = total % 60;
    if (h > 0) return '${h}h ${m}m';
    return m > 0 ? '${m}m ${sec}s' : '${sec}s';
  }

  // Wide web windows: call list beside the selected call's transcript.
  Widget desktop(BuildContext context, CallLogsState s) {
    final t = Theme.of(context), c = t.colorScheme;
    final calls = s.page.items;
    final current = calls.where((x) => x.id == selected).firstOrNull;
    final inbound = calls.where((x) => x.direction != 'outbound').length;
    final languages = {
      for (final x in calls)
        if (x.language.isNotEmpty) x.language,
    };
    final day = MaterialLocalizations.of(context).formatMediumDate(s.day);
    return AppPage(
      title: 'Call logs',
      back: true,
      showAppBar: true,
      maxWidth: 1320,
      scrollId: 'agent-call-logs',
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Call logs', style: t.textTheme.headlineLarge),
                const SizedBox(height: 6),
                Text(
                  'Conversations handled by your call service.',
                  style: TextStyle(color: c.onSurface.withValues(alpha: .65)),
                ),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: 'Refresh calls',
            onPressed: s.loading ? null : () => cubit.load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      children: [
        AppToolbar(
          leading: Align(
            alignment: Alignment.centerLeft,
            child: dayChips(context, s),
          ),
          actions: [
            if (!s.loading && s.page.total > calls.length)
              Text(
                'Showing ${calls.length} of ${s.page.total} calls.',
                style: t.textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (s.loading) const AppRefreshIndicator(label: 'Loading calls…'),
        if (s.page.warning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(s.page.warning),
          ),
        if (s.page.nextOffset != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppButton(
              label: 'Load more calls',
              secondary: true,
              busy: s.loading,
              onPressed: s.loading ? null : cubit.loadMore,
            ),
          ),
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: () => cubit.load()),
        if (!s.loading && s.error == null && calls.isEmpty)
          const AppEmptyState(
            title: 'No calls',
            message: 'No calls were recorded on this day.',
            icon: Icons.phone_disabled_outlined,
          ),
        if (calls.isNotEmpty) ...[
          AppStatRow(
            children: [
              AppStatTile(
                icon: Icons.call_outlined,
                label: 'Calls',
                value: '${s.page.total}',
                caption: day,
                highlight: true,
              ),
              AppStatTile(
                icon: Icons.timer_outlined,
                label: 'Talk time shown',
                value: talkTime(
                  calls.fold<double>(0, (sum, x) => sum + x.durationSeconds),
                ),
                caption:
                    'Across ${calls.length} ${calls.length == 1 ? 'call' : 'calls'} shown',
              ),
              AppStatTile(
                icon: Icons.call_received_rounded,
                label: 'Inbound · outbound',
                value: '$inbound · ${calls.length - inbound}',
                caption: 'Across the calls shown',
              ),
              AppStatTile(
                icon: Icons.translate_rounded,
                label: 'Languages',
                value: '${languages.length}',
                caption: languages.isEmpty
                    ? 'Not reported in calls shown'
                    : languages.join(', '),
              ),
            ],
          ),
          const SizedBox(height: 28),
          AppTwoPane(
            secondaryWidth: 440,
            primary: [
              AppPanel(
                title: 'Calls',
                subtitle: 'Summaries, outcomes and conversation history',
                child: AppListCard(
                  children: [
                    for (final call in calls)
                      callRow(context, call, call.id == current?.id),
                  ],
                ),
              ),
            ],
            secondary: [
              AppPanel(
                title: 'Call details',
                subtitle: current == null
                    ? 'Nothing selected'
                    : 'What the agent understood',
                child: current == null
                    ? AppCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 36),
                          child: Column(
                            children: [
                              Icon(
                                Icons.forum_outlined,
                                size: 36,
                                color: c.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Select a call',
                                style: t.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Its summary, details, recording and transcript appear here.',
                                textAlign: TextAlign.center,
                                style: t.textTheme.bodySmall?.copyWith(
                                  color: c.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : AppCard(
                        padding: const EdgeInsets.all(20),
                        child: CallDetailSheet(
                          key: ValueKey('call-detail-${current.id}'),
                          call: current,
                          embedded: true,
                          onClose: () => setState(() => selected = null),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget callRow(
    BuildContext context,
    AgentCall call,
    bool active, {
    VoidCallback? onTap,
  }) {
    final t = Theme.of(context), c = t.colorScheme;
    return Material(
      color: active ? c.primary.withValues(alpha: .07) : Colors.transparent,
      child: InkWell(
        key: ValueKey('call-row-${call.id}'),
        onTap: onTap ?? () => setState(() => selected = call.id),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: active ? c.primary : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(17, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: c.primary.withValues(alpha: .1),
                child: Icon(
                  call.direction == 'outbound'
                      ? Icons.call_made_rounded
                      : Icons.call_received_rounded,
                  size: 19,
                  color: c.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call.title,
                      style: t.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        AppStatusBadge(
                          label: call.direction == 'outbound'
                              ? 'Outbound'
                              : 'Inbound',
                          icon: call.direction == 'outbound'
                              ? Icons.call_made_rounded
                              : Icons.call_received_rounded,
                        ),
                        if (call.disposition.isNotEmpty)
                          AppStatusBadge(
                            label: call.disposition.replaceAll('_', ' '),
                            icon: Icons.notes_rounded,
                            color: c.onSurfaceVariant,
                          ),
                      ],
                    ),
                    if (call.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        call.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      meta(context, call),
                      style: t.textTheme.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: active ? c.primary : c.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CallDetailSheet extends StatefulWidget {
  const CallDetailSheet({
    super.key,
    required this.call,
    this.embedded = false,
    this.fullScreen = false,
    this.onClose,
  });
  final AgentCall call;

  /// Desktop side pane: a plain column instead of a draggable sheet.
  final bool embedded;
  final bool fullScreen;
  final VoidCallback? onClose;
  @override
  State<CallDetailSheet> createState() => _CallDetailSheetState();
}

class _CallDetailSheetState extends State<CallDetailSheet> {
  late final cubit = getIt<CallDetailCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.call,
  );
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

  @override
  Widget build(BuildContext context) {
    final call = widget.call, t = Theme.of(context), c = t.colorScheme;
    final facts = [
      ('Caller', call.contact),
      ('Name given', call.callerName),
      ('Enquiry', call.enquiryType.replaceAll('_', ' ')),
      ('Requested', call.requestedFacility),
      ('Preferred time', call.preferredDatetime),
      ('Outcome', call.disposition.replaceAll('_', ' ')),
      ('Language', call.language),
    ].where((f) => f.$2.isNotEmpty);
    return BlocConsumer<CallDetailCubit, CallDetailState>(
      bloc: cubit,
      listenWhen: (a, b) =>
          (b.notice != null && b.notice != a.notice) ||
          (b.error != null && !b.loading && a.saving),
      listener: (context, s) => showMessage(context, s.notice ?? s.error!),
      builder: (context, s) {
        final children = <Widget>[
          Row(
            children: [
              Expanded(child: Text(call.title, style: t.textTheme.titleLarge)),
              IconButton(
                tooltip: 'Close',
                onPressed: widget.embedded
                    ? widget.onClose
                    : () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (call.startedAt != null)
            Text(
              '${MaterialLocalizations.of(context).formatMediumDate(call.startedAt!)}, '
              '${clock(context, call.startedAt!)} · ${call.duration}',
              style: t.textTheme.bodySmall,
            ),
          if (call.summary.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: .07),
                border: Border.all(color: c.primary.withValues(alpha: .18)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Call summary',
                    style: t.textTheme.titleSmall?.copyWith(color: c.primary),
                  ),
                  const SizedBox(height: 8),
                  Text(call.summary),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Details below are what the agent understood. Check the booking '
            'list for what was actually booked.',
            style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final (label, value) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: t.textTheme.labelMedium?.copyWith(
                      color: c.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SelectableText(value, style: t.textTheme.bodyMedium),
                ],
              ),
            ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Save recording',
            busyLabel: 'Downloading…',
            icon: Icons.download_rounded,
            secondary: true,
            busy: s.saving,
            onPressed: s.saving ? null : cubit.saveRecording,
          ),
          const SizedBox(height: 20),
          Text('Transcript', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (s.loading)
            const AppRefreshIndicator(label: 'Loading transcript…'),
          if (s.error != null && s.lines.isEmpty && !s.loading)
            AppErrorWidget(message: s.error!, onRetry: cubit.load),
          if (!s.loading && s.error == null && s.lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('No transcript is available for this call yet.'),
            ),
          for (final line in s.lines)
            Align(
              alignment: line.agent
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: line.agent
                      ? c.surfaceContainerHighest
                      : c.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.unattributed
                          ? 'Transcript'
                          : line.agent
                          ? 'Agent'
                          : 'Caller',
                      style: t.textTheme.labelSmall,
                    ),
                    Text(line.text),
                  ],
                ),
              ),
            ),
        ];
        if (widget.embedded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        }
        if (widget.fullScreen) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: children,
          );
        }
        return AdaptiveSheetBody(
          initialChildSize: .85,
          maxChildSize: .95,
          builder: (context, scroll, shrink) => ListView(
            controller: scroll,
            shrinkWrap: shrink,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: children,
          ),
        );
      },
    );
  }
}

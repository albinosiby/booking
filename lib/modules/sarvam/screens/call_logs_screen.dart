import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/sarvam_cubits.dart';
import '../models/sarvam_models.dart';

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

  void open(SarvamCall call) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BlocProvider.value(
      value: context.read<WorkspaceCubit>(),
      child: CallDetailSheet(call: call),
    ),
  );

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<CallLogsCubit, CallLogsState>(
        bloc: cubit,
        builder: (context, s) {
          final t = Theme.of(context), c = t.colorScheme;
          final today = DateUtils.dateOnly(DateTime.now());
          return AppPage(
            title: 'Call logs',
            subtitle: 'Calls answered by your Sarvam voice agent.',
            back: true,
            showAppBar: true,
            compactHeader: true,
            scrollId: 'sarvam-call-logs',
            actions: [
              IconButton(
                tooltip: 'Refresh calls',
                onPressed: s.loading ? null : () => cubit.load(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
              ),
              const SizedBox(height: 16),
              if (s.loading) const AppRefreshIndicator(label: 'Loading calls…'),
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
                    onTap: () => open(call),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              call.direction == 'outbound'
                                  ? Icons.call_made_rounded
                                  : Icons.call_received_rounded,
                              size: 18,
                              color: c.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                call.title,
                                style: t.textTheme.titleSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (call.summary.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            call.summary,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (call.startedAt != null)
                              clock(context, call.startedAt!),
                            call.duration,
                            call.language,
                            call.disposition.replaceAll('_', ' '),
                          ].where((v) => v.isNotEmpty).join(' · '),
                          style: t.textTheme.bodySmall?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class CallDetailSheet extends StatefulWidget {
  const CallDetailSheet({super.key, required this.call});
  final SarvamCall call;
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
      builder: (context, s) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(call.title, style: t.textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
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
              const SizedBox(height: 12),
              Text(call.summary),
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
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$label: ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: value),
                    ],
                  ),
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
                        line.agent ? 'Agent' : 'Caller',
                        style: t.textTheme.labelSmall,
                      ),
                      Text(line.text),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

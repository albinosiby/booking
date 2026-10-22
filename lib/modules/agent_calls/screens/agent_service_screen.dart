import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../config/routes/routes.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/agent_call_cubits.dart';
import '../models/agent_call_models.dart';
import '../widgets/agent_request_progress.dart';

class AgentServiceScreen extends StatefulWidget {
  const AgentServiceScreen({super.key});
  @override
  State<AgentServiceScreen> createState() => _AgentServiceScreenState();
}

class _AgentServiceScreenState extends State<AgentServiceScreen> {
  late final cubit = getIt<AgentServiceCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  final note = TextEditingController();

  @override
  void initState() {
    super.initState();
    cubit.load();
  }

  @override
  void dispose() {
    note.dispose();
    cubit.close();
    super.dispose();
  }

  Widget overview(AgentServiceState s) {
    final t = Theme.of(context), c = t.colorScheme;
    final status = s.status;
    final paused = status.status == 'paused' || status.status == 'rejected';
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.support_agent_rounded,
              size: 32,
              color: c.primary,
            ),
          ),
          const SizedBox(height: 20),
          AppStatusBadge(
            label: agentStatusLabel(status),
            icon: paused
                ? Icons.pause_circle_outline
                : Icons.phone_in_talk_outlined,
            color: paused ? c.error : null,
          ),
          const SizedBox(height: 16),
          Text(
            'A helping hand for every call.',
            style: t.textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            agentStatusDescription(status),
            style: t.textTheme.bodyLarge?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          for (final item in [
            (
              Icons.event_available_outlined,
              'Bookings by phone',
              'Help callers book, reschedule or cancel.',
            ),
            (
              Icons.forum_outlined,
              'Every conversation, organised',
              'Review call summaries and transcripts.',
            ),
            (
              Icons.tune_rounded,
              'You stay in control',
              'Turn answering on or off when the service is ready.',
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.$1, size: 21, color: c.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$2, style: t.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          item.$3,
                          style: t.textTheme.bodySmall?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget request(AgentServiceState s) => AppCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.status.status == 'rejected'
              ? 'Send a new request'
              : 'Let’s set up your agent',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Tell us about your venue’s call needs. You can track setup here after requesting.',
        ),
        if (s.status.message.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(s.status.message),
        ],
        const SizedBox(height: 24),
        TextField(
          controller: note,
          minLines: 3,
          maxLines: 5,
          maxLength: 2000,
          enabled: !s.busy,
          decoration: const InputDecoration(
            labelText: 'Anything we should know? (optional)',
            hintText:
                'For example, your busy hours or common caller questions.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        AppButton(
          label: s.status.status == 'rejected'
              ? 'Request again'
              : 'Request service',
          icon: Icons.arrow_forward_rounded,
          busy: s.busy,
          onPressed: s.busy ? null : () => cubit.request(note.text.trim()),
        ),
      ],
    ),
  );

  Widget controls(AgentServiceState s) {
    final t = Theme.of(context), c = t.colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Call service', style: t.textTheme.titleLarge),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Answer calls automatically'),
            subtitle: Text(
              s.status.enabled
                  ? 'Callers can book, reschedule and cancel by phone.'
                  : 'Turned off. Callers will not reach the agent.',
            ),
            value: s.status.enabled,
            onChanged: s.busy ? null : cubit.setEnabled,
          ),
          if (s.busy) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Icon(Icons.history_rounded, color: c.primary, size: 28),
          const SizedBox(height: 12),
          Text(
            'Your conversations, in one place',
            style: t.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'See who called, what they needed and how the conversation went.',
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'Call logs',
            icon: Icons.arrow_forward_rounded,
            secondary: true,
            onPressed: () => context.push(Routes.callLogs),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AgentServiceCubit, AgentServiceState>(
    bloc: cubit,
    builder: (context, s) {
      final st = s.status.status;
      final ready = st == 'active' && s.status.ready;
      final canRequest = st == 'none' || st == 'rejected';
      final content = canRequest ? request(s) : controls(s);
      final secondary = canRequest || ready
          ? content
          : AgentRequestProgress(status: s.status);
      return AppPage(
        title: 'Agent call service',
        subtitle: 'Manage your phone assistant and follow its setup.',
        back: true,
        showAppBar: true,
        compactHeader: true,
        maxWidth: 1200,
        scrollId: 'agent-service',
        actions: [
          IconButton(
            tooltip: 'Refresh service status',
            onPressed: s.loading || s.busy ? null : cubit.load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        children: [
          if (s.loading) const AppRefreshIndicator(label: 'Loading service…'),
          if (!s.loading && !cubit.owner)
            const AppEmptyState(
              title: 'Owner access required',
              message: 'Only the owner can manage the agent call service.',
              icon: Icons.lock_outline,
            ),
          if (!s.loading && cubit.owner) ...[
            if (s.error != null) ...[
              AppErrorWidget(
                message: s.error!,
                onRetry: s.busy ? null : cubit.load,
              ),
              const SizedBox(height: 20),
            ],
            LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth >= AppPage.wideWidth) {
                  return AppTwoPane(
                    primary: [overview(s)],
                    secondaryFlex: 3,
                    secondary: [secondary],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Put the next action or current request first on a phone.
                    secondary,
                    const SizedBox(height: 20),
                    overview(s),
                  ],
                );
              },
            ),
          ],
        ],
      );
    },
  );
}

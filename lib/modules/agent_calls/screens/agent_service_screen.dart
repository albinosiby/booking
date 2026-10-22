import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../config/routes/routes.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/agent_call_cubits.dart';
import '../models/agent_call_models.dart';

const _steps = [
  ('requested', 'Request received'),
  ('in_review', 'Under review'),
  ('setting_up', 'Being set up'),
  ('active', 'Ready to use'),
];

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

  Widget intro(AgentServiceState s, {required bool again}) => AppPanel(
    title: 'Agent call service',
    subtitle:
        'An automated agent that answers your phone calls, takes bookings and keeps a log of every call.',
    child: AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (again && s.status.message.isNotEmpty) ...[
            Text(s.status.message),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: note,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Anything we should know? (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          AppButton(
            label: again ? 'Request again' : 'Request service',
            icon: Icons.support_agent_outlined,
            busy: s.busy,
            onPressed: s.busy ? null : () => cubit.request(note.text.trim()),
          ),
        ],
      ),
    ),
  );

  Widget progress(AgentServiceState s) {
    final current = _steps.indexWhere((e) => e.$1 == s.status.status);
    return AppPanel(
      title: 'Request status',
      subtitle: 'We will update this page as your service is set up.',
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _steps.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  i < current || (i == current && s.status.status == 'active')
                      ? Icons.check_circle
                      : i == current
                      ? Icons.timelapse
                      : Icons.radio_button_unchecked,
                  color: i <= current ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(_steps[i].$2),
              ),
            if (s.status.message.isNotEmpty) ...[
              const Divider(),
              Text(s.status.message),
            ],
            if (s.status.status == 'paused') ...[
              const Divider(),
              const Text('The service is paused. Contact support for details.'),
            ],
          ],
        ),
      ),
    );
  }

  Widget controls(AgentServiceState s) => AppPanel(
    title: 'Call service',
    child: AppCard(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Answer calls automatically'),
            subtitle: Text(
              s.status.enabled
                  ? 'Callers can book, reschedule and cancel by phone.'
                  : 'Turned off. Callers will not reach the agent.',
            ),
            value: s.status.enabled,
            onChanged: s.busy ? null : cubit.setEnabled,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Call logs'),
            subtitle: const Text('Calls, summaries, transcripts and recordings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.callLogs),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => BlocConsumer<AgentServiceCubit, AgentServiceState>(
    bloc: cubit,
    listener: (context, s) {
      if (s.error != null && !s.loading) showMessage(context, s.error!);
    },
    builder: (context, s) {
      final st = s.status.status;
      return AppPage(
        title: 'Agent call service',
        subtitle: 'Request, track and control automated call answering.',
        back: true,
        showAppBar: true,
        maxWidth: 800,
        scrollId: 'agent-service',
        children: [
          if (s.loading) const AppRefreshIndicator(label: 'Loading…'),
          if (!s.loading && !cubit.owner)
            const AppEmptyState(
              title: 'Owner access required',
              message: 'Only the owner can manage the agent call service.',
            ),
          if (!s.loading && cubit.owner) ...[
            if (st == 'none') intro(s, again: false),
            if (st == 'rejected') intro(s, again: true),
            if (['requested', 'in_review', 'setting_up', 'paused'].contains(st))
              progress(s),
            if (st == 'active' && !s.status.ready) progress(s),
            if (st == 'active' && s.status.ready) controls(s),
          ],
        ],
      );
    },
  );
}

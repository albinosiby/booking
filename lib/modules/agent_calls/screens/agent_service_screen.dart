import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Widget serviceChips(List<CallService> services) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      for (final service in services) Chip(label: Text(service.label)),
    ],
  );
  Widget overview(AgentServiceState s) {
    final t = Theme.of(context), status = s.status;
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.support_agent_rounded,
            size: 36,
            color: t.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          AppStatusBadge(
            label: agentStatusLabel(status),
            icon: status.enabled
                ? Icons.phone_in_talk_outlined
                : Icons.phone_outlined,
          ),
          const SizedBox(height: 16),
          Text(
            'Your venue, a phone call away.',
            style: t.textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(agentStatusDescription(status)),
          const SizedBox(height: 24),
          for (final item in const [
            (
              Icons.checklist_rounded,
              'Choose the help your callers need',
              'Request booking, rescheduling, enquiries or cancellation.',
            ),
            (
              Icons.tune_rounded,
              'Choose your spaces',
              'You decide which spaces are available through the call service.',
            ),
            (
              Icons.history_rounded,
              'Follow every conversation',
              'Review call details and transcripts from your call history.',
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.$1, size: 22, color: t.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$2, style: t.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(item.$3),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (status.requestedServices.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 12),
            Text('Requested services', style: t.textTheme.titleSmall),
            const SizedBox(height: 8),
            serviceChips(status.requestedServices),
          ],
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
              ? 'Request a new connection'
              : 'Set up your call service',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose what your callers should be able to do. Our team will set up the connection and assign your booking number.',
        ),
        if (s.status.message.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(s.status.message),
        ],
        const SizedBox(height: 20),
        for (final service in CallService.values)
          CheckboxListTile(
            key: ValueKey('request-service-${service.id}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(service.label),
            subtitle: Text(service.description),
            value: s.selectedServices.contains(service),
            onChanged: s.busy
                ? null
                : (selected) => cubit.selectService(service, selected == true),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: note,
          minLines: 2,
          maxLines: 4,
          maxLength: 2000,
          enabled: !s.busy,
          decoration: const InputDecoration(
            labelText: 'Anything we should know? (optional)',
            hintText: 'Languages, busy hours or common questions',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
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
  Future<void> copyNumber(String number) async {
    try {
      await Clipboard.setData(ClipboardData(text: number));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Booking number copied.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not copy. Select the number to copy it.'),
          ),
        );
      }
    }
  }

  Widget controls(AgentServiceState s) {
    final status = s.status, t = Theme.of(context);
    final readySpaces = status.spaces
        .where((space) => space.enabled && space.ready)
        .length;
    final businesses = {
      for (final space in status.spaces) space.businessId: space.businessName,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your booking number', style: t.textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SelectableText(
                    status.phoneNumber,
                    style: t.textTheme.headlineSmall,
                  ),
                  TextButton.icon(
                    onPressed: status.phoneNumber.isEmpty
                        ? null
                        : () => copyNumber(status.phoneNumber),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy number'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Share this number with customers who want to contact your venue.',
              ),
              const SizedBox(height: 20),
              Text('Activated services', style: t.textTheme.titleSmall),
              const SizedBox(height: 8),
              serviceChips(status.approvedServices),
              const Divider(height: 32),
              SwitchListTile.adaptive(
                key: const ValueKey('call-service-enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable call service'),
                subtitle: Text(
                  status.enabled
                      ? 'Callers can use the activated services for your selected spaces.'
                      : 'Service actions are off. Choose spaces below, then enable the service.',
                ),
                value: status.enabled,
                onChanged: s.busy || (!status.enabled && readySpaces == 0)
                    ? null
                    : cubit.setEnabled,
              ),
              if (readySpaces == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Select at least one ready space to enable the service.',
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Turning this off blocks service actions. Contact support if you also want the phone line to stop answering.',
                style: t.textTheme.bodySmall,
              ),
              if (status.message.isNotEmpty) ...[
                const Divider(height: 24),
                Text(status.message),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Spaces available by phone', style: t.textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Changes are saved immediately. New spaces stay off until you select them.',
              ),
              if (s.busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (status.spaces.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Create and configure a space to make it available here.',
                  ),
                ),
              for (final business in businesses.entries) ...[
                const SizedBox(height: 20),
                Text(business.value, style: t.textTheme.titleMedium),
                for (final space in status.spaces.where(
                  (space) => space.businessId == business.key,
                ))
                  SwitchListTile.adaptive(
                    key: ValueKey('call-space-${space.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(space.name),
                    subtitle: Text(
                      space.ready
                          ? (space.enabled
                                ? 'Available through the call service'
                                : 'Not available by phone')
                          : 'Finish this business’s setup to accept bookings.',
                    ),
                    value: space.enabled,
                    onChanged: s.busy || (!space.ready && !space.enabled)
                        ? null
                        : (enabled) => cubit.setSpace(space, enabled),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget logs() => AppCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Call history', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Review calls, summaries and transcripts. Your history remains available when the service is off.',
        ),
        const SizedBox(height: 16),
        AppButton(
          label: 'Call logs',
          icon: Icons.history_rounded,
          secondary: true,
          onPressed: () => context.push(Routes.callLogs),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AgentServiceCubit, AgentServiceState>(
        bloc: cubit,
        builder: (context, s) {
          final canRequest =
              s.status.status == 'none' || s.status.status == 'rejected';
          final action = canRequest
              ? request(s)
              : s.status.ready
              ? controls(s)
              : AgentRequestProgress(status: s.status);
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              action,
              if (s.status.callLogsAvailable) ...[
                const SizedBox(height: 20),
                logs(),
              ],
            ],
          );
          return AppPage(
            title: 'Call booking',
            subtitle: 'Manage your call service, spaces and conversations.',
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
              if (s.loading)
                const AppRefreshIndicator(label: 'Loading service…'),
              if (!s.loading && !cubit.owner)
                const AppEmptyState(
                  title: 'Owner access required',
                  message: 'Only the owner can manage the call service.',
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
                  builder: (context, box) => box.maxWidth >= AppPage.wideWidth
                      ? AppTwoPane(
                          primary: [overview(s)],
                          secondaryFlex: 3,
                          secondary: [details],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            details,
                            const SizedBox(height: 20),
                            overview(s),
                          ],
                        ),
                ),
              ],
            ],
          );
        },
      );
}

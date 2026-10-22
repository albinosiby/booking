import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../config/routes/routes.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/sarvam_cubits.dart';
import '../models/sarvam_models.dart';

class SarvamSettingsScreen extends StatefulWidget {
  const SarvamSettingsScreen({super.key});
  @override
  State<SarvamSettingsScreen> createState() => _SarvamSettingsScreenState();
}

class _SarvamSettingsScreenState extends State<SarvamSettingsScreen>
    with WidgetsBindingObserver {
  late final cubit = getIt<SarvamSettingsCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  final apiKey = TextEditingController();
  String? deployment;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cubit.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        cubit.state.saved.status == 'authorization_required') {
      cubit.continueSetup();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    apiKey.dispose();
    cubit.close();
    super.dispose();
  }

  Future<void> publish(SarvamSettings settings, String id) async {
    if (await confirmAction(
      context,
      'Publish booking changes?',
      'Publish agent version ${settings.draftVersion} to the selected phone deployment. This replaces its booking instructions and tools. Existing bookings remain unchanged.',
    )) {
      await cubit.publish(id);
    }
  }

  Widget connection(SarvamSettingsState s) => AppPanel(
    title: 'Connect Sarvam',
    subtitle: 'Connect your workspace and authorize automatic booking setup.',
    child: AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Sarvam API key',
            controller: apiKey,
            password: true,
            hint: s.saved.hasCredentials
                ? 'Saved key ending ${s.saved.apiKeyLast4}. Leave empty to keep.'
                : 'Paste your workspace API key',
            prefixIcon: Icons.key_outlined,
            onChanged: (v) => cubit.update(apiKey: v),
          ),
          const SizedBox(height: 14),
          ConfigurationField(
            label: 'Organization ID',
            value: s.orgId,
            onChanged: (v) => cubit.update(orgId: v),
          ),
          const SizedBox(height: 14),
          ConfigurationField(
            label: 'Workspace ID',
            value: s.workspaceId,
            onChanged: (v) => cubit.update(workspaceId: v),
          ),
          const SizedBox(height: 14),
          ConfigurationField(
            label: 'App ID',
            value: s.appId,
            onChanged: (v) => cubit.update(appId: v),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: s.saved.status == 'failed' ? 'Reconnect' : 'Connect',
            icon: Icons.link_rounded,
            busy: s.busy,
            onPressed: s.busy || s.saved.status == 'cleanup_pending'
                ? null
                : cubit.connect,
          ),
          const SizedBox(height: 10),
          const Text(
            'Sarvam sign-in authorizes setup. The agent stays on its current published version until you choose Publish changes.',
          ),
        ],
      ),
    ),
  );
  Widget booking(SarvamSettingsState s) => AppPanel(
    title: 'Phone bookings',
    subtitle: 'Choose which businesses callers may book.',
    child: AppCard(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Accept phone bookings'),
            subtitle: Text(
              s.saved.enabled
                  ? 'Callers can book, reschedule and cancel.'
                  : 'Phone booking actions are blocked. General enquiries can continue.',
            ),
            value: s.saved.enabled,
            onChanged: s.saved.enabled || !s.busy && s.saved.canEnableBookings
                ? cubit.setBookingEnabled
                : null,
          ),
          if (!s.saved.canEnableBookings && !s.saved.enabled)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Connect and publish before turning phone bookings on.',
              ),
            ),
          const Divider(height: 1),
          for (final b in s.saved.businesses)
            CheckboxListTile(
              title: Text(b.name),
              subtitle: b.ready ? null : const Text('Not active yet'),
              value: s.businessIds.contains(b.id),
              onChanged: s.busy
                  ? null
                  : (v) => cubit.toggleBusiness(b.id, v == true),
            ),
          if (s.saved.businesses.isEmpty)
            const ListTile(title: Text('Add a business before connecting.')),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Business selection changes take effect when you Connect and Publish changes. Turning bookings off takes effect immediately.',
            ),
          ),
        ],
      ),
    ),
  );
  Widget status(SarvamSettingsState s) {
    final saved = s.saved;
    final ids = saved.deployments.map((d) => d.id).toSet();
    final selected = ids.contains(deployment)
        ? deployment
        : saved.deployments.length == 1
        ? saved.deployments.single.id
        : null;
    return AppPanel(
      title: 'Connection status',
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              saved.statusLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (s.busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (saved.progressLabel.isNotEmpty &&
                saved.status != 'configured') ...[
              const SizedBox(height: 10),
              Text(saved.progressLabel),
            ],
            if (s.error != null || saved.setupError.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                s.error ?? saved.setupError,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (saved.status == 'authorization_required') ...[
              const SizedBox(height: 16),
              AppButton(
                label: 'Authorize with Sarvam',
                icon: Icons.open_in_new_rounded,
                onPressed: s.busy ? null : cubit.authorize,
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Continue setup',
                secondary: true,
                onPressed: s.busy ? null : cubit.continueSetup,
              ),
            ],
            if (saved.needsWork && !s.busy) ...[
              const SizedBox(height: 16),
              AppButton(
                label: saved.status == 'cleanup_pending'
                    ? 'Retry cleanup'
                    : 'Retry setup',
                onPressed: cubit.continueSetup,
              ),
            ],
            if (saved.connected) ...[
              const SizedBox(height: 16),
              if (saved.awaitingPublish)
                const Text(
                  'Booking setup is ready. Review and test the draft in Sarvam before publishing.',
                ),
              if (saved.deployments.isEmpty)
                const Text(
                  'Set up a phone deployment for this agent in Sarvam, then Connect again to refresh it.',
                ),
              if (saved.deployments.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Phone deployment',
                  ),
                  items: [
                    for (final d in saved.deployments)
                      DropdownMenuItem(
                        value: d.id,
                        child: Text(d.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: s.busy
                      ? null
                      : (v) => setState(() => deployment = v),
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Publish changes',
                  icon: Icons.publish_rounded,
                  onPressed:
                      s.busy ||
                          s.dirty ||
                          selected == null ||
                          !saved.awaitingPublish
                      ? null
                      : () => publish(saved, selected),
                ),
              ],
            ],
            if (saved.callLogsAvailable) ...[
              const SizedBox(height: 16),
              AppButton(
                label: 'Test call log connection',
                secondary: true,
                onPressed: s.busy ? null : cubit.test,
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'View call logs',
                secondary: true,
                icon: Icons.call_outlined,
                onPressed: () => context.push(Routes.callLogs),
              ),
            ],
            if (saved.status != 'disconnected' || saved.hasCredentials) ...[
              const SizedBox(height: 16),
              AppButton(
                label: 'Disconnect Sarvam',
                secondary: true,
                icon: Icons.link_off_rounded,
                onPressed: saved.status == 'cleanup_pending'
                    ? null
                    : () async {
                        if (await confirmAction(
                          context,
                          'Disconnect Sarvam?',
                          'Turn off phone bookings and revoke booking access. Existing bookings are preserved.',
                        )) {
                          await cubit.disconnect();
                        }
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<SarvamSettingsCubit, SarvamSettingsState>(
    bloc: cubit,
    listener: (context, s) {
      if (s.apiKey.isEmpty) apiKey.clear();
      if (s.notice != null) showMessage(context, s.notice!);
    },
    builder: (context, s) => AppPage(
      title: 'Automated Call Bookings',
      subtitle: 'Automatic setup, phone booking controls and call logs.',
      back: true,
      showAppBar: true,
      maxWidth: 1200,
      scrollId: 'sarvam-settings',
      children: [
        if (s.loading)
          const AppRefreshIndicator(label: 'Loading Sarvam settings…'),
        if (!s.loading && !cubit.owner)
          const AppEmptyState(
            title: 'Owner access required',
            message: 'Only the owner can manage the Sarvam voice agent.',
          ),
        if (!s.loading &&
            cubit.owner &&
            s.saved.version == 0 &&
            s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.load),
        if (!s.loading && cubit.owner) ...[
          if (s.dirty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Connect to apply the edited credentials or business selection.',
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [connection(s), status(s), booking(s)],
                );
              }
              return AppTwoPane(
                primaryFlex: 3,
                secondaryFlex: 2,
                primary: [connection(s)],
                secondary: [status(s), booking(s)],
              );
            },
          ),
        ],
      ],
    ),
  );
}

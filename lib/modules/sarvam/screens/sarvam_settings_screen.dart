import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _SarvamSettingsScreenState extends State<SarvamSettingsScreen> {
  late final cubit = getIt<SarvamSettingsCubit>(
    param1: context.read<WorkspaceCubit>(),
  );
  final apiKey = TextEditingController();
  @override
  void initState() {
    super.initState();
    cubit.load();
  }

  @override
  void dispose() {
    apiKey.dispose();
    cubit.close();
    super.dispose();
  }

  Future<void> copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showMessage(context, '$label copied.');
  }

  Future<void> rotate(SarvamSettings saved) async {
    if (saved.hasToolKey &&
        !await confirmAction(
          context,
          'Replace the voice tool key?',
          'The current key stops working immediately. Update it in every Sarvam tool afterwards.',
        )) {
      return;
    }
    await cubit.rotateToolKey();
  }

  Future<void> showToolKey(String key) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      scrollable: true,
      title: const Text('Voice tool key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Copy it now and paste it into each Sarvam API tool as an API key '
            'header named X-API-Key. It will not be shown again.',
          ),
          const SizedBox(height: 12),
          SelectableText(key, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: key));
            if (c.mounted) showMessage(c, 'Tool key copied.');
          },
          child: const Text('Copy key'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Done'),
        ),
      ],
    ),
  );

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<SarvamSettingsCubit, SarvamSettingsState>(
    bloc: cubit,
    listenWhen: (a, b) =>
        b.newToolKey != null || b.notice != null || b.error != null,
    listener: (context, s) {
      if (s.newToolKey != null) {
        showToolKey(s.newToolKey!);
      } else if (s.notice != null) {
        apiKey.clear();
        showMessage(context, s.notice!);
      } else if (s.error != null && !s.loading && s.saved.version > 0) {
        showMessage(context, s.error!);
      }
    },
    builder: (context, s) {
      final t = Theme.of(context), c = t.colorScheme;
      final saved = s.saved;
      final loadFailed = s.error != null && saved.version == 0 && !s.busy;
      return AppPage(
        title: 'Sarvam voice agent',
        subtitle: 'Phone bookings, cancellations and call logs.',
        back: true,
        showAppBar: true,
        compactHeader: true,
        scrollId: 'sarvam-settings',
        bottomBar: cubit.owner && !s.loading && !loadFailed
            ? Material(
                elevation: 8,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: AppButton(
                      label: 'Save settings',
                      icon: Icons.check_rounded,
                      busy: s.busy,
                      onPressed: s.busy || !s.dirty ? null : cubit.save,
                    ),
                  ),
                ),
              )
            : null,
        children: [
          if (s.loading)
            const AppRefreshIndicator(label: 'Loading Sarvam settings…'),
          if (loadFailed && !s.loading)
            AppErrorWidget(message: s.error!, onRetry: cubit.load),
          if (!s.loading && !loadFailed && cubit.owner) ...[
            Text('Connect Sarvam', style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Used to show call logs, transcripts and recordings. '
              'Find these in Sarvam under your app’s API settings.',
              style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    label: 'Sarvam API key',
                    controller: apiKey,
                    password: true,
                    hint: saved.connected
                        ? 'Saved key ending ${saved.apiKeyLast4}. Type to replace.'
                        : 'Paste your Sarvam API key',
                    prefixIcon: Icons.key_outlined,
                    onChanged: (v) => cubit.update(apiKey: v),
                  ),
                  const SizedBox(height: 12),
                  ConfigurationField(
                    label: 'Organization ID',
                    value: s.orgId,
                    onChanged: (v) => cubit.update(orgId: v),
                  ),
                  const SizedBox(height: 12),
                  ConfigurationField(
                    label: 'Workspace ID',
                    value: s.workspaceId,
                    onChanged: (v) => cubit.update(workspaceId: v),
                  ),
                  const SizedBox(height: 12),
                  ConfigurationField(
                    label: 'App ID',
                    value: s.appId,
                    onChanged: (v) => cubit.update(appId: v),
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Test connection',
                    icon: Icons.wifi_tethering_rounded,
                    secondary: true,
                    onPressed: saved.connected && !s.dirty && !s.busy
                        ? cubit.test
                        : null,
                  ),
                  const SizedBox(height: 8),
                  AppButton(
                    label: 'View call logs',
                    icon: Icons.call_outlined,
                    secondary: true,
                    onPressed: saved.connected && !s.dirty
                        ? () => context.push(Routes.callLogs)
                        : null,
                  ),
                  if (saved.connected && s.dirty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Save your changes to test them.',
                        style: t.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Voice booking', style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Callers can book, and change or cancel bookings made from '
              'their own phone number. Bookings are confirmed instantly '
              'and paid at the venue.',
              style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Accept phone bookings'),
                    subtitle: Text(
                      s.enabled
                          ? 'The voice agent can book selected businesses.'
                          : 'Voice tool calls are refused.',
                    ),
                    value: s.enabled,
                    onChanged: s.busy ? null : (v) => cubit.update(enabled: v),
                  ),
                  const Divider(height: 1),
                  for (final b in saved.businesses)
                    CheckboxListTile(
                      title: Text(b.name),
                      subtitle: b.ready ? null : const Text('Not active yet'),
                      value: s.businessIds.contains(b.id),
                      onChanged: s.busy
                          ? null
                          : (v) => cubit.toggleBusiness(b.id, v == true),
                    ),
                  if (saved.businesses.isEmpty)
                    const ListTile(
                      title: Text('Add a business before enabling.'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Sarvam tool setup', style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'In Sarvam, add an API tool for each URL below: method POST, '
              'auth “API key” with header X-API-Key, and pass the caller’s '
              'User Identifier as caller_phone and Interaction ID as '
              'interaction_id.',
              style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.vpn_key_outlined),
                    title: const Text('Voice tool key'),
                    subtitle: Text(
                      saved.hasToolKey
                          ? 'Starts with ${saved.toolKeyPrefix}…'
                          : 'Not generated yet',
                    ),
                    trailing: TextButton(
                      onPressed: s.busy ? null : () => rotate(saved),
                      child: Text(saved.hasToolKey ? 'Replace' : 'Generate'),
                    ),
                  ),
                  const Divider(height: 1),
                  for (final (path, label) in voiceTools)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(label, style: t.textTheme.bodyMedium),
                                Text(
                                  '${saved.toolBaseUrl}/$path',
                                  style: t.textTheme.bodySmall?.copyWith(
                                    color: c.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy $label URL',
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: () =>
                                copy('${saved.toolBaseUrl}/$path', 'URL'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (!s.loading && !cubit.owner)
            const Text('Only the owner can manage the Sarvam voice agent.'),
        ],
      );
    },
  );
}

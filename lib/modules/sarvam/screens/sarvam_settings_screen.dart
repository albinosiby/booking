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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) =>
        BlocConsumer<SarvamSettingsCubit, SarvamSettingsState>(
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
          builder: (context, s) =>
              isDesktopWidth(context) && box.maxWidth >= AppPage.wideWidth
              ? desktop(context, s)
              : narrow(context, s),
        ),
  );

  bool loadFailed(SarvamSettingsState s) =>
      s.error != null && s.saved.version == 0 && !s.busy;

  Widget saveButton(SarvamSettingsState s) => AppButton(
    label: 'Save settings',
    icon: Icons.check_rounded,
    busy: s.busy,
    onPressed: s.busy || !s.dirty ? null : cubit.save,
  );

  Widget testButton(SarvamSettingsState s) => AppButton(
    label: 'Test connection',
    icon: Icons.wifi_tethering_rounded,
    secondary: true,
    onPressed: s.saved.connected && !s.dirty && !s.busy ? cubit.test : null,
  );

  Widget callLogsButton(SarvamSettingsState s) => AppButton(
    label: 'View call logs',
    icon: Icons.call_outlined,
    secondary: true,
    onPressed: s.saved.connected && !s.dirty
        ? () => context.push(Routes.callLogs)
        : null,
  );

  Widget apiKeyField(SarvamSettings saved) => AppTextField(
    label: 'Sarvam API key',
    controller: apiKey,
    password: true,
    hint: saved.connected
        ? 'Saved key ending ${saved.apiKeyLast4}. Type to replace.'
        : 'Paste your Sarvam API key',
    prefixIcon: Icons.key_outlined,
    onChanged: (v) => cubit.update(apiKey: v),
  );

  List<Widget> idFields(SarvamSettingsState s) => [
    ConfigurationField(
      label: 'Organization ID',
      value: s.orgId,
      onChanged: (v) => cubit.update(orgId: v),
    ),
    ConfigurationField(
      label: 'Workspace ID',
      value: s.workspaceId,
      onChanged: (v) => cubit.update(workspaceId: v),
    ),
    ConfigurationField(
      label: 'App ID',
      value: s.appId,
      onChanged: (v) => cubit.update(appId: v),
    ),
  ];

  Widget? saveHint(BuildContext context, SarvamSettingsState s) =>
      s.saved.connected && s.dirty
      ? Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Save your changes to test them.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        )
      : null;

  Widget bookingCard(SarvamSettingsState s) => AppCard(
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
          const ListTile(title: Text('Add a business before enabling.')),
      ],
    ),
  );

  Widget toolCard(BuildContext context, SarvamSettingsState s) {
    final t = Theme.of(context), c = t.colorScheme, saved = s.saved;
    return AppCard(
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
                    onPressed: () => copy('${saved.toolBaseUrl}/$path', 'URL'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const connectNote =
      'Used to show call logs, transcripts and recordings. '
      'Find these in Sarvam under your app’s API settings.';
  static const bookingNote =
      'Callers can book, and change or cancel bookings made from '
      'their own phone number. Bookings are confirmed instantly '
      'and paid at the venue.';
  static const toolNote =
      'In Sarvam, add an API tool for each URL below: method POST, '
      'auth “API key” with header X-API-Key, and pass the caller’s '
      'User Identifier as caller_phone and Interaction ID as '
      'interaction_id.';

  Widget narrow(BuildContext context, SarvamSettingsState s) {
    final t = Theme.of(context), c = t.colorScheme;
    final failed = loadFailed(s);
    final note = t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant);
    return AppPage(
      title: 'Sarvam voice agent',
      subtitle: 'Phone bookings, cancellations and call logs.',
      back: true,
      showAppBar: true,
      compactHeader: true,
      scrollId: 'sarvam-settings',
      bottomBar: cubit.owner && !s.loading && !failed
          ? Material(
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: saveButton(s),
                ),
              ),
            )
          : null,
      children: [
        if (s.loading)
          const AppRefreshIndicator(label: 'Loading Sarvam settings…'),
        if (failed && !s.loading)
          AppErrorWidget(message: s.error!, onRetry: cubit.load),
        if (!s.loading && !failed && cubit.owner) ...[
          Text('Connect Sarvam', style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(connectNote, style: note),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                apiKeyField(s.saved),
                for (final field in idFields(s)) ...[
                  const SizedBox(height: 12),
                  field,
                ],
                const SizedBox(height: 12),
                testButton(s),
                const SizedBox(height: 8),
                callLogsButton(s),
                ?saveHint(context, s),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Voice booking', style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(bookingNote, style: note),
          const SizedBox(height: 12),
          bookingCard(s),
          const SizedBox(height: 24),
          Text('Sarvam tool setup', style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(toolNote, style: note),
          const SizedBox(height: 12),
          toolCard(context, s),
          const SizedBox(height: 24),
        ],
        if (!s.loading && !cubit.owner)
          const Text('Only the owner can manage the Sarvam voice agent.'),
      ],
    );
  }

  // Wide web windows: status figures, then settings panels side by side.
  Widget desktop(BuildContext context, SarvamSettingsState s) {
    final t = Theme.of(context), c = t.colorScheme, saved = s.saved;
    final failed = loadFailed(s);
    final ready = !s.loading && !failed && cubit.owner;
    final assigned = saved.businesses.where((b) => b.assigned).length;
    return AppPage(
      title: 'Sarvam voice agent',
      back: true,
      showAppBar: true,
      maxWidth: 1200,
      scrollId: 'sarvam-settings',
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sarvam voice agent', style: t.textTheme.headlineLarge),
                const SizedBox(height: 6),
                Text(
                  'Phone bookings, cancellations and call logs.',
                  style: TextStyle(color: c.onSurface.withValues(alpha: .65)),
                ),
              ],
            ),
          ),
          if (ready) ...[
            SizedBox(width: 190, child: callLogsButton(s)),
            const SizedBox(width: 10),
            SizedBox(width: 190, child: saveButton(s)),
          ],
        ],
      ),
      children: [
        if (s.loading)
          const AppRefreshIndicator(label: 'Loading Sarvam settings…'),
        if (failed && !s.loading)
          AppErrorWidget(message: s.error!, onRetry: cubit.load),
        if (ready) ...[
          AppStatRow(
            children: [
              AppStatTile(
                icon: Icons.link_rounded,
                label: 'Sarvam connection',
                value: saved.connected ? 'Connected' : 'Not connected',
                caption: saved.connected
                    ? 'API key ending ${saved.apiKeyLast4}'
                    : 'Add your Sarvam API key',
                highlight: saved.connected,
              ),
              AppStatTile(
                icon: Icons.phone_in_talk_outlined,
                label: 'Phone bookings',
                value: saved.enabled ? 'On' : 'Off',
                caption: saved.enabled
                    ? 'Voice agent can book'
                    : 'Voice tool calls are refused',
              ),
              AppStatTile(
                icon: Icons.storefront_outlined,
                label: 'Bookable businesses',
                value: '$assigned of ${saved.businesses.length}',
                caption: 'Selected for voice booking',
              ),
              AppStatTile(
                icon: Icons.vpn_key_outlined,
                label: 'Voice tool key',
                value: saved.hasToolKey ? 'Generated' : 'Not set',
                caption: saved.hasToolKey
                    ? 'Starts with ${saved.toolKeyPrefix}…'
                    : 'Generate one for Sarvam tools',
              ),
            ],
          ),
          if (s.dirty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                children: [
                  Icon(Icons.edit_note_rounded, size: 18, color: c.primary),
                  const SizedBox(width: 6),
                  Text(
                    'You have unsaved changes.',
                    style: t.textTheme.bodySmall?.copyWith(color: c.primary),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 28),
          AppTwoPane(
            primaryFlex: 3,
            secondaryFlex: 2,
            primary: [
              AppPanel(
                title: 'Connect Sarvam',
                subtitle: connectNote,
                child: AppCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      apiKeyField(saved),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, field) in idFields(s).indexed) ...[
                            if (i > 0) const SizedBox(width: 12),
                            Expanded(child: field),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          SizedBox(width: 220, child: testButton(s)),
                          const SizedBox(width: 12),
                          Expanded(
                            child:
                                saveHint(context, s) ?? const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AppPanel(
                title: 'Sarvam tool setup',
                subtitle: toolNote,
                child: toolCard(context, s),
              ),
            ],
            secondary: [
              AppPanel(
                title: 'Voice booking',
                subtitle: bookingNote,
                child: bookingCard(s),
              ),
            ],
          ),
        ],
        if (!s.loading && !cubit.owner)
          const AppEmptyState(
            title: 'Owner access required',
            message: 'Only the owner can manage the Sarvam voice agent.',
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/message_cubits.dart';
import '../models/message_template.dart';
import '../models/message_screen_models.dart';
import '../widgets/message_chat_preview.dart';
import '../widgets/message_phone_preview.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  late final cubit = getIt<TemplatesCubit>(
    param1: context.read<WorkspaceCubit>(),
  );

  /// Template shown in the desktop preview pane.
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

  Future<void> edit([MessageTemplate? template]) async {
    final saved = await context.push<bool>(
      '/profile/message-templates/edit',
      extra: template,
    );
    if (saved == true && mounted) cubit.load(refresh: true);
  }

  void preview(MessageTemplate template) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: MessageChatPreview(
                    sample: true,
                    message: template.render({
                      ...sampleMessageFields,
                      'website': template.website,
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> remove(MessageTemplate template) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text(
          template.primary
              ? 'The predefined template will become primary.'
              : 'This removes this saved template.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) cubit.remove(template.id);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => BlocBuilder<TemplatesCubit, TemplatesState>(
      bloc: cubit,
      builder: (context, s) {
        if (isDesktopWidth(context) && box.maxWidth >= AppPage.wideWidth) {
          return desktop(context, s);
        }
        final t = Theme.of(context), c = t.colorScheme;
        return AppPage(
          title: 'Templates',
          subtitle: 'Booking messages. Tap a template to preview.',
          back: true,
          showAppBar: true,
          compactHeader: true,
          scrollId: 'message-templates',
          actions: [
            if (cubit.owner)
              IconButton(
                tooltip: 'Create template',
                onPressed: s.busy ? null : () => edit(),
                icon: const Icon(Icons.add_rounded),
              ),
          ],
          children: [
            if (s.loading)
              const AppRefreshIndicator(label: 'Loading templates…'),
            if (s.busy)
              const AppRefreshIndicator(label: 'Saving template settings…'),
            if (s.error != null)
              AppErrorWidget(
                message: s.error!,
                onRetry: () => cubit.load(refresh: true),
              ),
            if (cubit.owner)
              for (final item in s.catalog.templates.indexed) ...[
                if (item.$1 > 0) const Divider(height: 1),
                ListTile(
                  key: ValueKey('template-tile-${item.$2.id}'),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  onTap: () => preview(item.$2),
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: c.primary.withValues(alpha: .1),
                    child: Icon(
                      item.$2.primary
                          ? Icons.mark_chat_read_outlined
                          : Icons.chat_bubble_outline_rounded,
                      size: 20,
                      color: c.primary,
                    ),
                  ),
                  title: Tooltip(
                    message: item.$2.name,
                    child: Text(
                      item.$2.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.titleSmall,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        item.$2.body.replaceAll(RegExp(r'\s+'), ' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall,
                      ),
                      if (item.$2.primary || item.$2.builtin) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            if (item.$2.primary)
                              Text(
                                'Primary',
                                style: t.textTheme.labelSmall?.copyWith(
                                  color: c.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (item.$2.builtin)
                              Text(
                                'Predefined',
                                style: t.textTheme.labelSmall?.copyWith(
                                  color: c.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Template options',
                    enabled: !s.busy,
                    onSelected: (action) {
                      switch (action) {
                        case 'edit':
                          edit(item.$2);
                        case 'primary':
                          cubit.primary(item.$2.id);
                        case 'delete':
                          remove(item.$2);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit as new template'),
                      ),
                      if (!item.$2.primary)
                        const PopupMenuItem(
                          value: 'primary',
                          child: Text('Set as primary'),
                        ),
                      if (!item.$2.builtin)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                    ],
                  ),
                ),
              ],
          ],
        );
      },
    ),
  );

  // Wide web windows: template list beside a phone preview of the selection.
  Widget desktop(BuildContext context, TemplatesState s) {
    final t = Theme.of(context), c = t.colorScheme;
    final templates = s.catalog.templates;
    final current =
        templates.where((x) => x.id == selected).firstOrNull ??
        templates.where((x) => x.primary).firstOrNull ??
        templates.firstOrNull;
    return AppPage(
      title: 'Templates',
      back: true,
      showAppBar: true,
      maxWidth: 1200,
      scrollId: 'message-templates',
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Templates', style: t.textTheme.headlineLarge),
                const SizedBox(height: 6),
                Text(
                  'Booking messages shared on WhatsApp. Select a template to preview it.',
                  style: TextStyle(color: c.onSurface.withValues(alpha: .65)),
                ),
              ],
            ),
          ),
          if (cubit.owner)
            Tooltip(
              message: 'Create template',
              child: FilledButton.icon(
                onPressed: s.busy ? null : () => edit(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New template'),
              ),
            ),
        ],
      ),
      children: [
        if (s.loading) const AppRefreshIndicator(label: 'Loading templates…'),
        if (s.busy)
          const AppRefreshIndicator(label: 'Saving template settings…'),
        if (s.error != null)
          AppErrorWidget(
            message: s.error!,
            onRetry: () => cubit.load(refresh: true),
          ),
        if (!cubit.owner && !s.loading)
          const AppEmptyState(
            title: 'Owner access required',
            message: 'Only the owner can manage message templates.',
          ),
        if (cubit.owner && templates.isNotEmpty)
          AppTwoPane(
            secondaryWidth: 400,
            primary: [
              AppPanel(
                title: 'Your templates',
                subtitle:
                    '${templates.length} ${templates.length == 1 ? 'template' : 'templates'} · the primary template is used when sharing a booking',
                child: AppListCard(
                  children: [
                    for (final item in templates)
                      desktopTile(context, s, item, item.id == current?.id),
                  ],
                ),
              ),
              AppPanel(
                title: 'Booking fields',
                subtitle:
                    'Placeholders filled from each booking when you share it',
                child: AppCard(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final f in messageFields.entries)
                        Tooltip(
                          message: '{${f.key}}',
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(f.value),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            secondary: [
              if (current != null)
                AppPanel(
                  title: 'Preview',
                  subtitle: current.name,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MessagePhonePreview(
                        key: ValueKey('template-phone-${current.id}'),
                        sample: true,
                        message: current.render({
                          ...sampleMessageFields,
                          'website': current.website,
                        }),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Sample values replace booking fields. Your saved message keeps its placeholders.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: s.busy ? null : () => edit(current),
                              icon: const Icon(
                                Icons.copy_all_outlined,
                                size: 18,
                              ),
                              label: const Text('Edit as new'),
                            ),
                          ),
                          if (!current.primary) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: s.busy
                                    ? null
                                    : () => cubit.primary(current.id),
                                icon: const Icon(
                                  Icons.check_circle_outline,
                                  size: 18,
                                ),
                                label: const Text('Make primary'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget desktopTile(
    BuildContext context,
    TemplatesState s,
    MessageTemplate item,
    bool active,
  ) {
    final t = Theme.of(context), c = t.colorScheme;
    return Material(
      color: active ? c.primary.withValues(alpha: .07) : Colors.transparent,
      child: InkWell(
        key: ValueKey('template-tile-${item.id}'),
        onTap: () => setState(() => selected = item.id),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: active ? c.primary : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(17, 16, 8, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: c.primary.withValues(alpha: .1),
                child: Icon(
                  item.primary
                      ? Icons.mark_chat_read_outlined
                      : Icons.chat_bubble_outline_rounded,
                  size: 20,
                  color: c.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Tooltip(
                            message: item.name,
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.titleSmall,
                            ),
                          ),
                        ),
                        if (item.primary) ...[
                          const SizedBox(width: 8),
                          _Badge('Primary', c.primary),
                        ],
                        if (item.builtin) ...[
                          const SizedBox(width: 8),
                          _Badge('Predefined', c.onSurfaceVariant),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.body.replaceAll(RegExp(r'\s+'), ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Template options',
                enabled: !s.busy,
                onSelected: (action) {
                  switch (action) {
                    case 'preview':
                      preview(item);
                    case 'edit':
                      edit(item);
                    case 'primary':
                      cubit.primary(item.id);
                    case 'delete':
                      remove(item);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'preview',
                    child: Text('Open preview'),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit as new template'),
                  ),
                  if (!item.primary)
                    const PopupMenuItem(
                      value: 'primary',
                      child: Text('Set as primary'),
                    ),
                  if (!item.builtin)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

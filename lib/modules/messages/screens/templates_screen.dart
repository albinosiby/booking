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

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  late final cubit = getIt<TemplatesCubit>(
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
  Widget build(BuildContext context) =>
      BlocBuilder<TemplatesCubit, TemplatesState>(
        bloc: cubit,
        builder: (context, s) {
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
      );
}

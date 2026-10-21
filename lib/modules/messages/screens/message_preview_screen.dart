import '../widgets/message_chat_preview.dart';
import '../widgets/message_phone_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/message_cubits.dart';
import '../models/message_screen_models.dart';

class MessagePreviewScreen extends StatefulWidget {
  const MessagePreviewScreen({super.key, required this.bookingId});
  final String bookingId;
  @override
  State<MessagePreviewScreen> createState() => _MessagePreviewScreenState();
}

class _MessagePreviewScreenState extends State<MessagePreviewScreen> {
  late final cubit = getIt<MessagePreviewCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.bookingId,
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) =>
        BlocBuilder<MessagePreviewCubit, MessagePreviewState>(
          bloc: cubit,
          builder: (context, s) =>
              isDesktopWidth(context) && box.maxWidth >= AppPage.wideWidth
              ? desktop(context, s)
              : AppPage(
                  title: 'Share booking',
                  subtitle:
                      'Review the message, then send it manually in WhatsApp.',
                  back: true,
                  scrollId: 'booking-message-${widget.bookingId}',
                  children: [
                    if (s.loading)
                      AppLoadingState(
                        initial: s.message.isEmpty,
                        label: 'Preparing message…',
                      ),
                    if (s.error != null)
                      AppErrorWidget(
                        message: s.error!,
                        onRetry: s.busy ? null : cubit.load,
                      ),
                    if (s.notice != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(s.notice!),
                      ),
                    if (s.message.isNotEmpty) ...[
                      Text(
                        'Template · ${s.templateName}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 12),
                      MessageChatPreview(message: s.message),
                      const SizedBox(height: 16),
                      AppButton(
                        label: 'Share on WhatsApp',
                        icon: Icons.share_outlined,
                        busy: s.busy,
                        onPressed: s.loading || s.busy ? null : cubit.share,
                      ),
                      const SizedBox(height: 8),
                      AppButton(
                        label: 'Copy message',
                        secondary: true,
                        icon: Icons.copy_outlined,
                        onPressed: s.loading || s.busy ? null : cubit.copy,
                      ),
                      TextButton(
                        onPressed: s.busy ? null : cubit.load,
                        child: const Text('Refresh saved booking & template'),
                      ),
                    ],
                  ],
                ),
        ),
  );

  // Wide web windows: phone preview beside the share actions.
  Widget desktop(BuildContext context, MessagePreviewState s) {
    final t = Theme.of(context), c = t.colorScheme;
    return AppPage(
      title: 'Share booking',
      subtitle: 'Review the message, then send it manually in WhatsApp.',
      back: true,
      maxWidth: 1000,
      scrollId: 'booking-message-${widget.bookingId}',
      children: [
        if (s.loading)
          AppLoadingState(
            initial: s.message.isEmpty,
            label: 'Preparing message…',
          ),
        if (s.error != null)
          AppErrorWidget(
            message: s.error!,
            onRetry: s.busy ? null : cubit.load,
          ),
        if (s.notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(s.notice!),
          ),
        if (s.message.isNotEmpty)
          AppTwoPane(
            secondaryWidth: 380,
            primary: [
              AppPanel(
                title: 'Message preview',
                subtitle: 'Template · ${s.templateName}',
                child: MessagePhonePreview(message: s.message, height: 640),
              ),
            ],
            secondary: [
              AppPanel(
                title: 'Send',
                subtitle: 'Nothing is sent automatically',
                child: AppCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: c.primary.withValues(alpha: .1),
                            child: Icon(
                              Icons.mark_chat_read_outlined,
                              size: 20,
                              color: c.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.templateName,
                                  style: t.textTheme.titleSmall,
                                ),
                                Text(
                                  'Filled with this booking’s saved details',
                                  style: t.textTheme.bodySmall?.copyWith(
                                    color: c.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      AppButton(
                        label: 'Share on WhatsApp',
                        icon: Icons.share_outlined,
                        busy: s.busy,
                        onPressed: s.loading || s.busy ? null : cubit.share,
                      ),
                      const SizedBox(height: 10),
                      AppButton(
                        label: 'Copy message',
                        secondary: true,
                        icon: Icons.copy_outlined,
                        onPressed: s.loading || s.busy ? null : cubit.copy,
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: s.busy ? null : cubit.load,
                        child: const Text('Refresh saved booking & template'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

import '../widgets/message_chat_preview.dart';
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
  Widget build(BuildContext context) =>
      BlocBuilder<MessagePreviewCubit, MessagePreviewState>(
        bloc: cubit,
        builder: (context, s) => AppPage(
          title: 'Share booking',
          subtitle: 'Review the message, then send it manually in WhatsApp.',
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
      );
}

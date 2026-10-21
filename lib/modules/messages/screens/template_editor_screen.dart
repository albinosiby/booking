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
import '../widgets/template_field_picker.dart';

class TemplateEditorScreen extends StatefulWidget {
  const TemplateEditorScreen({super.key, this.source});
  final MessageTemplate? source;
  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  late final cubit = getIt<TemplateEditorCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.source,
  );
  late final body = TextEditingController(text: cubit.state.body);
  final bodyFocus = FocusNode();
  @override
  void dispose() {
    body.dispose();
    bodyFocus.dispose();
    cubit.close();
    super.dispose();
  }

  Future<void> pickField() async {
    if (cubit.lockedDraft) return;
    final selection = body.selection;
    final field = await showAdaptiveSheet<String>(
      context: context,
      scrollable: false,
      showClose: false,
      showDragHandle: false,
      maxWidth: 480,
      builder: (_) => const TemplateFieldPicker(),
    );
    if (!mounted || field == null || cubit.lockedDraft || !cubit.owner) return;
    final token = '{$field}';
    final start = selection.isValid ? selection.start : body.text.length,
        end = selection.isValid ? selection.end : body.text.length;
    final text = body.text.replaceRange(start, end, token);
    if (text.length > 6000) return;
    body.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    cubit.update(body: text);
    bodyFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) =>
        BlocConsumer<TemplateEditorCubit, TemplateEditorState>(
          bloc: cubit,
          listenWhen: (previous, current) =>
              previous.saved != current.saved ||
              previous.error != current.error,
          listener: (context, s) {
            if (s.saved) {
              context.pop(true);
            } else if (s.error != null) {
              showMessage(context, s.error!);
            }
          },
          builder: (context, s) =>
              isDesktopWidth(context) && box.maxWidth >= AppPage.wideWidth
              ? desktop(context, s)
              : narrow(context, s),
        ),
  );

  String get title => widget.source == null ? 'Create template' : 'Edit a copy';

  Widget saveButton(TemplateEditorState s) => AppButton(
    label: cubit.pending == null ? 'Save template' : 'Retry save',
    icon: Icons.check_rounded,
    busy: s.busy,
    onPressed: s.busy ? null : cubit.save,
  );

  Widget nameField(TemplateEditorState s) => ConfigurationField(
    label: 'Template name',
    value: s.name,
    enabled: !cubit.lockedDraft,
    onChanged: (v) => cubit.update(name: v),
  );

  List<Widget> messageInput(
    BuildContext context,
    TemplateEditorState s, {
    int minLines = 10,
  }) => [
    Row(
      children: [
        Expanded(
          child: Text('Message', style: Theme.of(context).textTheme.titleSmall),
        ),
        TextButton.icon(
          key: const ValueKey('insert-template-field'),
          onPressed: cubit.lockedDraft ? null : pickField,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Insert field'),
        ),
      ],
    ),
    const SizedBox(height: 8),
    TextField(
      key: const ValueKey('template-message-input'),
      controller: body,
      focusNode: bodyFocus,
      enabled: !cubit.lockedDraft,
      minLines: minLines,
      maxLines: 18,
      maxLength: 6000,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
      decoration: InputDecoration(
        hintText: 'Dear {customer_name},\nYour booking has been confirmed…',
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
        alignLabelWithHint: true,
        errorText: s.body.isNotEmpty ? validateMessageBody(s.body) : null,
      ),
      onChanged: (v) => cubit.update(body: v),
    ),
  ];

  Widget website(TemplateEditorState s) => ReviewMore(
    title: 'Venue website · optional',
    children: [
      ConfigurationField(
        label: 'Website URL',
        value: s.website,
        enabled: !cubit.lockedDraft,
        onChanged: (v) => cubit.update(website: v),
      ),
    ],
  );

  static const help = ReviewMore(
    title: 'How to write a template',
    children: [
      Text(
        'Write normally. Use Insert field to add live booking information at the cursor.',
      ),
      Text(
        'Keep placeholders unchanged, for example {customer_name} and {balance_due}.',
      ),
      Text(
        'Use *text* for bold and _text_ for italic in WhatsApp. Use new lines to separate sections.',
      ),
      Text(
        'Avoid fixed customer names, prices and booking times. Dates use the venue timezone; times use 24-hour format.',
      ),
      Text(
        'The total includes any discount. Received means net payments; pending is the outstanding balance.',
      ),
      Text(
        'Use {booking_status} for messages shared after cancellation or rescheduling. Website is blank unless supplied above.',
      ),
    ],
  );

  Widget? bodyError(BuildContext context, TemplateEditorState s) =>
      s.body.isNotEmpty && validateMessageBody(s.body) != null
      ? Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            validateMessageBody(s.body)!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        )
      : null;

  Widget narrow(BuildContext context, TemplateEditorState s) => AppPage(
    title: title,
    back: true,
    showAppBar: true,
    compactHeader: true,
    scrollId: 'template-editor',
    bottomBar: !cubit.owner
        ? null
        : Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 580),
                    child: saveButton(s),
                  ),
                ),
              ),
            ),
          ),
    children: [
      if (s.error != null) AppErrorWidget(message: s.error!),
      if (!cubit.owner)
        const Text('Only the owner can manage message templates.')
      else ...[
        if (widget.source != null) ...[
          Text(
            'A new copy of “${widget.source!.name}”.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
        ],
        nameField(s),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TemplateEditorTab>(
            segments: const [
              ButtonSegment(
                value: TemplateEditorTab.write,
                icon: Icon(Icons.edit_outlined),
                label: Text('Write'),
              ),
              ButtonSegment(
                value: TemplateEditorTab.preview,
                icon: Icon(Icons.visibility_outlined),
                label: Text('Preview'),
              ),
            ],
            selected: {s.tab},
            showSelectedIcon: false,
            onSelectionChanged: (tabs) {
              FocusScope.of(context).unfocus();
              cubit.selectTab(tabs.single);
            },
          ),
        ),
        const SizedBox(height: 20),
        if (s.tab == TemplateEditorTab.write) ...[
          ...messageInput(context, s),
          const SizedBox(height: 8),
          website(s),
          help,
        ] else ...[
          ?bodyError(context, s),
          MessageChatPreview(
            key: const ValueKey('template-live-preview'),
            sample: true,
            message: s.preview,
          ),
        ],
      ],
    ],
  );

  // Wide web windows: fields on the left, live phone preview on the right.
  Widget desktop(BuildContext context, TemplateEditorState s) {
    final t = Theme.of(context), c = t.colorScheme;
    return AppPage(
      title: title,
      back: true,
      showAppBar: true,
      maxWidth: 1200,
      scrollId: 'template-editor',
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.textTheme.headlineLarge),
                const SizedBox(height: 6),
                Text(
                  widget.source != null
                      ? 'A new copy of “${widget.source!.name}”. The original stays unchanged.'
                      : 'Write a booking message. The preview updates as you type.',
                  style: TextStyle(color: c.onSurface.withValues(alpha: .65)),
                ),
              ],
            ),
          ),
          if (cubit.owner) SizedBox(width: 200, child: saveButton(s)),
        ],
      ),
      children: [
        if (s.error != null) AppErrorWidget(message: s.error!),
        if (!cubit.owner)
          const Text('Only the owner can manage message templates.')
        else
          AppTwoPane(
            secondaryWidth: 400,
            primary: [
              AppPanel(
                title: 'Message',
                subtitle: 'Use Insert field to add live booking details',
                child: AppCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      nameField(s),
                      const SizedBox(height: 20),
                      ...messageInput(context, s, minLines: 14),
                      const SizedBox(height: 4),
                      website(s),
                    ],
                  ),
                ),
              ),
              AppPanel(
                title: 'Writing tips',
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: help,
                ),
              ),
            ],
            secondary: [
              AppPanel(
                title: 'Live preview',
                subtitle: 'How customers see it in WhatsApp',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?bodyError(context, s),
                    MessagePhonePreview(
                      key: const ValueKey('template-live-preview'),
                      sample: true,
                      message: s.preview,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Sample values replace booking fields. Your saved message keeps its placeholders.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

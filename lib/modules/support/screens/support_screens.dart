import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../config/routes/routes.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../support_module.dart';

String _when(DateTime? t) => t == null
    ? ''
    : '${t.day}/${t.month}/${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final cubit = SupportListCubit(getIt<SupportRepository>())..load();
  final subject = TextEditingController(), message = TextEditingController();
  String category = 'other';
  bool sending = false;

  @override
  void dispose() {
    subject.dispose();
    message.dispose();
    cubit.close();
    super.dispose();
  }

  Future<void> send() async {
    if (subject.text.trim().length < 3 || message.text.trim().length < 5) {
      showMessage(context, 'Add a short title and describe the issue.');
      return;
    }
    setState(() => sending = true);
    try {
      final thread = await getIt<SupportRepository>().create(
        category,
        subject.text.trim(),
        message.text.trim(),
      );
      if (!mounted) return;
      subject.clear();
      message.clear();
      showMessage(context, 'Sent. We will reply here.');
      cubit.load();
      context.push('${Routes.support}/${thread.ticket.id}');
    } catch (e) {
      if (mounted) showMessage(context, supportError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Widget form() => AppPanel(
    title: 'Report an issue',
    subtitle: 'Describe what went wrong and we will get back to you.',
    child: AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Topic'),
            items: [
              for (final e in supportCategories.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => category = v ?? 'other'),
          ),
          const SizedBox(height: 14),
          AppTextField(label: 'Title', controller: subject),
          const SizedBox(height: 14),
          TextField(
            controller: message,
            minLines: 4,
            maxLines: 8,
            maxLength: 4000,
            decoration: const InputDecoration(
              labelText: 'What happened?',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Send',
            icon: Icons.send_rounded,
            busy: sending,
            onPressed: sending ? null : send,
          ),
        ],
      ),
    ),
  );

  Widget history(SupportListState s) => AppPanel(
    title: 'Your requests',
    child: s.loading && s.tickets.isEmpty
        ? const AppRefreshIndicator(label: 'Loading…')
        : s.tickets.isEmpty
        ? const AppEmptyState(
            title: 'No requests yet',
            message: 'Issues you report will appear here with our replies.',
          )
        : Column(
            children: [
              for (final t in s.tickets)
                AppCard(
                  child: ListTile(
                    title: Text(t.subject),
                    subtitle: Text(
                      '${supportStatusLabels[t.status] ?? t.status} · ${_when(t.updatedAt)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context
                        .push('${Routes.support}/${t.id}')
                        .then((_) => cubit.load()),
                  ),
                ),
            ],
          ),
  );

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SupportListCubit, SupportListState>(
        bloc: cubit,
        builder: (context, s) => AppPage(
          title: 'Help & support',
          subtitle: 'Report a problem and follow our replies.',
          back: true,
          showAppBar: true,
          maxWidth: 900,
          scrollId: 'support',
          children: [
            if (s.error != null)
              AppErrorWidget(message: s.error!, onRetry: cubit.load),
            form(),
            history(s),
          ],
        ),
      );
}

class SupportThreadScreen extends StatefulWidget {
  const SupportThreadScreen({required this.id, super.key});
  final String id;
  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<SupportThreadScreen> {
  late final cubit = SupportThreadCubit(getIt<SupportRepository>(), widget.id)
    ..load();
  final reply = TextEditingController();

  @override
  void dispose() {
    reply.dispose();
    cubit.close();
    super.dispose();
  }

  Future<void> send() async {
    final text = reply.text.trim();
    if (text.isEmpty) return;
    if (await cubit.reply(text)) reply.clear();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<SupportThreadCubit, SupportThreadState>(
    bloc: cubit,
    listener: (context, s) {
      if (s.error != null && s.thread != null) showMessage(context, s.error!);
    },
    builder: (context, s) {
      final t = s.thread;
      return AppPage(
        title: t?.ticket.subject ?? 'Request',
        subtitle: t == null
            ? null
            : supportStatusLabels[t.ticket.status] ?? t.ticket.status,
        back: true,
        showAppBar: true,
        maxWidth: 800,
        scrollId: 'support-thread-${widget.id}',
        children: [
          if (s.loading) const AppRefreshIndicator(label: 'Loading…'),
          if (!s.loading && t == null)
            AppErrorWidget(
              message: s.error ?? 'Not found.',
              onRetry: cubit.load,
            ),
          if (t != null) ...[
            for (final m in t.messages)
              Align(
                alignment: m.fromSupport
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${m.fromSupport ? 'Support' : 'You'} · ${_when(m.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(m.body),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: reply,
              minLines: 2,
              maxLines: 6,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Reply',
                border: OutlineInputBorder(),
              ),
            ),
            AppButton(
              label: 'Send reply',
              icon: Icons.send_rounded,
              busy: s.busy,
              onPressed: s.busy ? null : send,
            ),
          ],
        ],
      );
    },
  );
}

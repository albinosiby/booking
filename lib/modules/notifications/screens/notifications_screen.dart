import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../auth/repositories/auth_repository_interface.dart';
import '../repositories/notification_inbox_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final repository = NotificationInboxRepository(getIt());
  final userId = getIt<AuthRepository>().currentUser?.id;
  List<InboxNotification> items = const [];
  String? nextCursor;
  Object? error;
  bool loading = true, loadingMore = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  bool get sameUser =>
      mounted && getIt<AuthRepository>().currentUser?.id == userId;

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await repository.load();
      if (!sameUser) return;
      setState(() {
        items = page.items;
        nextCursor = page.nextCursor;
        loading = false;
      });
    } catch (e) {
      if (!sameUser) return;
      setState(() {
        loading = false;
        error = e;
      });
    }
  }

  Future<void> loadMore() async {
    final cursor = nextCursor;
    if (cursor == null || loadingMore) return;
    setState(() => loadingMore = true);
    try {
      final page = await repository.load(before: cursor);
      if (!sameUser || nextCursor != cursor) return;
      setState(() {
        items = [...items, ...page.items];
        nextCursor = page.nextCursor;
        loadingMore = false;
        error = null;
      });
    } catch (e) {
      if (!sameUser) return;
      setState(() {
        loadingMore = false;
        error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPage(
      title: 'Notifications',
      subtitle: 'Updates for your current workspace',
      back: true,
      onRefresh: refresh,
      actions: [
        IconButton(
          tooltip: 'Refresh notifications',
          onPressed: loading ? null : refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      children: [
        if (loading && items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 72),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (error != null && items.isEmpty) ...[
          const AppEmptyState(
            title: 'Could not load notifications',
            message: 'Check your connection and try again.',
          ),
          Center(
            child: TextButton(
              onPressed: refresh,
              child: const Text('Try again'),
            ),
          ),
        ] else if (items.isEmpty)
          const AppEmptyState(
            title: 'No notifications yet',
            message: 'Booking, payment and account updates will appear here.',
          )
        else ...[
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push(item.route),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
                          child: Icon(_icon(item.kind), size: 21),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.body,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${MaterialLocalizations.of(context).formatMediumDate(item.createdAt)}, ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(item.createdAt))}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (error != null)
            Center(
              child: TextButton(
                onPressed: loadMore,
                child: const Text('Could not load more · Try again'),
              ),
            ),
          if (nextCursor != null && error == null)
            Center(
              child: TextButton(
                onPressed: loadingMore ? null : loadMore,
                child: loadingMore
                    ? const CircularProgressIndicator()
                    : const Text('Load more'),
              ),
            ),
        ],
      ],
    );
  }

  IconData _icon(String kind) => switch (kind) {
    'created' => Icons.event_available_outlined,
    'cancelled' => Icons.event_busy_outlined,
    'rescheduled' => Icons.update_outlined,
    'staff_cash_collected' => Icons.payments_outlined,
    'subscription_fee_due' => Icons.receipt_long_outlined,
    _ => Icons.notifications_outlined,
  };
}

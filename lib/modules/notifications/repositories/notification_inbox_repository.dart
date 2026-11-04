import '../../../utils/services/rest_api_service.dart';

class InboxNotification {
  const InboxNotification({
    required this.id,
    required this.createdAt,
    required this.kind,
    required this.title,
    required this.body,
    required this.route,
  });
  final String id, kind, title, body, route;
  final DateTime createdAt;

  factory InboxNotification.fromJson(Map<String, dynamic> json) =>
      InboxNotification(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        kind: json['kind'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        route: json['route'] as String,
      );
}

class NotificationInboxPage {
  const NotificationInboxPage(this.items, this.nextCursor);
  final List<InboxNotification> items;
  final String? nextCursor;
}

class NotificationInboxRepository {
  const NotificationInboxRepository(this.api);
  final RestApiService api;

  Future<NotificationInboxPage> load({String? before}) async {
    final path = before == null
        ? '/notifications/inbox'
        : '/notifications/inbox?before=${Uri.encodeQueryComponent(before)}';
    final data = Map<String, dynamic>.from(await api.request(path) as Map);
    return NotificationInboxPage(
      (data['items'] as List)
          .map(
            (item) => InboxNotification.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      data['next_cursor'] as String?,
    );
  }
}

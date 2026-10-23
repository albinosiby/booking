import 'workspace.dart';

/// Shared visibility and direct-route policy. Backend checks remain authoritative.
class WorkspaceNavigation {
  const WorkspaceNavigation(this.workspace);
  final Workspace workspace;
  bool any(List<String> permissions) =>
      permissions.any(workspace.hasPermission);
  bool get bookings =>
      any(['view_bookings', 'manage_bookings', 'collect_payments']);
  bool get finance => workspace.hasPermission('view_finance');
  bool get customers => bookings;
  bool get admissions => any([
    'view_bookings',
    'manage_bookings',
    'manage_subscriptions',
    if (!workspace.isCoach) ...['mark_attendance', 'manage_attendance'],
    'collect_payments',
  ]);
  bool get expenses => any(['view_finance', 'record_expenses']);

  // Indices refer to GoRouter branches, never to the filtered visual positions.
  List<int> get branches => [
    0,
    if (bookings) ...[1, 2],
    if (finance) 3,
    if (workspace.isCoach) 5,
    4,
  ];

  bool reducedFrom(Workspace previous) {
    if (previous.organization?.id != workspace.organization?.id) return true;
    if (previous.isOwner && !workspace.isOwner) return true;
    final permissions =
        (previous.membership?['permissions'] as List? ?? const []);
    if (permissions.any(
      (p) => p == 'coach'
          ? !workspace.isCoach
          : !workspace.hasPermission(p as String),
    )) {
      return true;
    }
    for (final old in previous.businesses) {
      final current = workspace.businesses
          .where((b) => b.id == old.id)
          .firstOrNull;
      if (current == null ||
          old.resources.any(
            (r) => !current.resources.any((n) => n.id == r.id),
          )) {
        return true;
      }
    }
    return false;
  }

  bool allows(String path) {
    if (path == '/coaching/classes') return workspace.isCoach;
    if (workspace.isOwner) return true;
    if (path.startsWith('/team') ||
        path.startsWith('/businesses') ||
        path.startsWith('/organization/') ||
        path.startsWith('/onboarding') ||
        path.startsWith('/profile/agent-calls') ||
        path.startsWith('/profile/booking-website') ||
        path.startsWith('/profile/message-templates') ||
        path.startsWith('/accounts/settings') ||
        path.startsWith('/accounts/bank') ||
        path.startsWith('/accounts/cash')) {
      return false;
    }
    if (path == '/payments' ||
        path.startsWith('/accounts/reports') ||
        path.startsWith('/accounts/transaction')) {
      return finance;
    }
    if (path.startsWith('/accounts/entry/expense')) {
      return workspace.hasPermission('record_expenses');
    }
    if (path.startsWith('/accounts/entry/income')) {
      return workspace.hasPermission('collect_payments');
    }
    if (path.startsWith('/accounts/')) return finance;
    if (path.startsWith('/income')) return finance;
    if (path == '/expenses/new') {
      return workspace.hasPermission('record_expenses');
    }
    if (path.startsWith('/expenses')) return expenses;
    if (path.startsWith('/customers')) return customers;
    if (path == '/admissions/new' || path.endsWith('/renew')) {
      return workspace.hasPermission('manage_subscriptions');
    }
    if (path.startsWith('/admissions')) return admissions;
    if (path == '/booking/new' ||
        path.endsWith('/reschedule') ||
        path.startsWith('/bookings/blocks')) {
      return workspace.hasPermission('manage_bookings');
    }
    if (path == '/calendar' ||
        path.startsWith('/bookings') ||
        path.startsWith('/booking/')) {
      return bookings;
    }
    return true;
  }
}

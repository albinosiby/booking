import '../../admissions/repositories/admission_repository.dart';
import 'dart:async';
import '../models/workspace.dart';
import '../models/workspace_access.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/repositories/booking_repository.dart';
import '../../accounts/models/accounts_models.dart';
import '../../accounts/repositories/accounts_repository.dart';
import '../../expenses/models/expense_models.dart';
import '../../expenses/repositories/expenses_repository.dart';
import '../../team/repositories/team_repository.dart';

/// Warms the exact first-page repository reads used by screens. Never fetches
/// quotes, attachments, reports, or an unbounded history.
class WorkspacePreloader {
  WorkspacePreloader(
    this.bookings,
    this.accounts,
    this.expenses,
    this.team, {
    this.admissions,
  });
  final AdmissionRepository? admissions;
  final BookingRepository bookings;
  final AccountsRepository accounts;
  final ExpensesRepository expenses;
  final TeamRepository team;
  String? _scope;
  DateTime? _last;

  void reset() {
    _scope = null;
    _last = null;
  }

  Future<void> warm(Workspace workspace, bool Function() current) async {
    if (workspace.organization == null) return;
    final scope = workspaceAccessScope(workspace), now = DateTime.now();
    if (_scope == scope &&
        _last != null &&
        now.difference(_last!) < const Duration(minutes: 10)) {
      return;
    }
    // Give Home time to paint and issue its priority requests first.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!current()) return;

    final jobs = <Future<void> Function()>[];
    void add(Future<Object?> Function() job) {
      jobs.add(() async {
        await job();
      });
    }

    final today = bookingDate(now);
    if (workspace.hasPermission('view_bookings') ||
        workspace.hasPermission('manage_bookings') ||
        workspace.hasPermission('collect_payments')) {
      add(bookings.catalog);
      if (workspace.hasPermission('view_bookings') ||
          workspace.hasPermission('manage_bookings')) {
        add(() => bookings.list());
        add(() => bookings.list(date: today, overlap: true));
        final utc = DateTime.utc(now.year, now.month, now.day);
        add(
          () => bookings.dateCounts(
            date: bookingDate(utc.subtract(const Duration(days: 15))),
            dateUntil: bookingDate(utc.add(const Duration(days: 15))),
          ),
        );
      }
    }
    if (admissions != null &&
        workspace.hasPermission('manage_bookings') &&
        workspace.businesses.any(
          (b) => b.type == BusinessType.pool && b.status == 'ready',
        )) {
      add(admissions!.warmPlans);
    }
    // Catalog permissions are authoritative and determine which financial
    // reads may be added. Each queue job performs only one network operation.
    if (workspace.hasPermission('view_finance') ||
        workspace.hasPermission('collect_payments') ||
        workspace.hasPermission('record_expenses')) {
      jobs.add(() async {
        final catalog = await accounts.catalog();
        if (!current() || !catalog.canView) return;
        final date = DateTime.parse(catalog.today);
        final finance = FinanceFilter.month(date);
        final expense = ExpenseFilter(anchor: date);
        add(() => accounts.overview(finance));
        add(() => accounts.transactions(finance));
        add(expenses.categories);
        add(() => expenses.overview(expense));
        add(() => expenses.list(expense));
      });
    }
    if (workspace.isOwner) add(team.load);
    var next = 0;
    Future<void> worker() async {
      while (current() && next < jobs.length) {
        final job = jobs[next++];
        try {
          await job();
        } catch (_) {
          // A failed optional warm-up must not disrupt navigation. Pages retain
          // their normal error/retry behavior and access checks.
        }
      }
    }

    await Future.wait([worker(), worker()]);
    if (current()) {
      _scope = scope;
      _last = now;
    }
  }
}

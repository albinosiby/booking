import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_form_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_preloader.dart';
import 'package:eden_booking/modules/accounts/repositories/accounts_repository.dart';
import 'package:eden_booking/modules/expenses/repositories/expenses_repository.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

class Customers extends FakeBookingRepository {
  final searches = <String>[];
  final pending = <Completer<List<BookingCustomer>>>[];
  @override
  Future<List<BookingCustomer>> customers(String phone) {
    searches.add(phone);
    final c = Completer<List<BookingCustomer>>();
    pending.add(c);
    return c.future;
  }
}

class NoAccounts extends Fake implements AccountsRepository {}

class NoExpenses extends Fake implements ExpensesRepository {}

class NoTeam extends Fake implements TeamRepository {}

class WarmBookings extends FakeBookingRepository {
  int active = 0, maximum = 0, reads = 0;
  Future<T> gate<T>(Future<T> Function() action) async {
    active++;
    reads++;
    if (active > maximum) maximum = active;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    try {
      return await action();
    } finally {
      active--;
    }
  }

  @override
  Future<BookingCatalog> catalog() => gate(super.catalog);
  @override
  Future<BookingPageResult> list({
    String? date,
    String? dateUntil,
    bool overlap = false,
    String? spaceId,
    String? businessId,
    String? query,
    String? status,
    int cursor = 0,
  }) => gate(() => super.list(date: date, overlap: overlap));
}

void main() {
  test(
    'phone suggestions debounce, allow same-number names and reject late results',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = Customers();
      final form = BookingFormCubit(w, r, const BookingLaunch());
      await form.load();
      form.customerPhone('987');
      form.customerPhone('9876543210');
      await Future<void>.delayed(const Duration(milliseconds: 340));
      expect(r.searches, ['9876543210']);
      const a = BookingCustomer(id: 'a', name: 'Abin', phone: '9876543210');
      const b = BookingCustomer(id: 'b', name: 'Arun', phone: '9876543210');
      r.pending[0].complete([a, b]);
      await Future<void>.delayed(Duration.zero);
      expect(form.state.customers.length, 2);
      form.customerPhone('9876543');
      expect(form.state.customers.map((c) => c.name), ['Abin', 'Arun']);
      expect(r.searches.length, 1); // Local matches need no network round trip.
      form.chooseCustomer(a);
      expect(form.state.draft.customer.name, 'Abin');
      expect(form.state.customers, isEmpty);
      form.customerName('Another name');
      expect(form.state.draft.customer.id, isNull);
      form.customerName('');
      await Future<void>.delayed(const Duration(milliseconds: 340));
      form.customerName('Manual name');
      r.pending[1].complete([b]);
      await Future<void>.delayed(Duration.zero);
      expect(form.state.draft.customer.name, 'Manual name');
      expect(form.state.customers, isEmpty);
      await form.close();
      await w.close();
    },
  );
  test('warm-up is bounded, scope guarded, and resets after signout', () async {
    final w = WorkspaceCubit(BookingSource());
    await w.load();
    final r = WarmBookings(),
        p = WorkspacePreloader(
          WarmBookings(),
          NoAccounts(),
          NoExpenses(),
          NoTeam(),
        );
    final warm = WorkspacePreloader(r, NoAccounts(), NoExpenses(), NoTeam());
    await warm.warm(w.state.data, () => true);
    expect(r.maximum, lessThanOrEqualTo(2));
    expect(r.reads, greaterThan(1));
    final reads = r.reads;
    await warm.warm(w.state.data, () => true);
    expect(r.reads, reads);
    warm.reset();
    await warm.warm(w.state.data, () => true);
    expect(r.reads, greaterThan(reads));
    final denied = WarmBookings();
    final restricted = Workspace(
      organization: w.state.data.organization,
      membership: const {'role': 'staff', 'permissions': <String>[]},
    );
    await WorkspacePreloader(
      denied,
      NoAccounts(),
      NoExpenses(),
      NoTeam(),
    ).warm(restricted, () => true);
    expect(denied.reads, 0);
    var current = true;
    final cancelled = p.warm(w.state.data, () => current);
    current = false;
    await cancelled;
    expect((p.bookings as WarmBookings).reads, 0);
    await w.close();
  });
}

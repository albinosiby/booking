import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/workspace/repositories/rest_workspace_repository.dart';
import 'package:eden_booking/modules/dashboard/cubit/home_cubit.dart';
import 'package:eden_booking/modules/dashboard/repositories/dashboard_repository.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

class LogoSource extends BookingSource implements WorkspaceLogoRepository {
  LogoSource() {
    value = Workspace(
      organization: const Organization(
        id: 'org',
        name: 'Eden',
        phone: '9876543210',
        currency: 'INR',
        logoKey: 'logo-1',
      ),
      membership: value.membership,
      businesses: value.businesses,
      locations: value.locations,
    );
  }
  Completer<Uint8List?> image = Completer<Uint8List?>();
  Completer<Workspace>? access;
  @override
  Future<Workspace> load() async =>
      access == null ? value : await access!.future;
  @override
  Future<Uint8List?> loadLogo() => image.future;
}

class UpdatingLogoSource extends LogoSource implements WorkspaceLogoEvents {
  final updates = StreamController<void>.broadcast();
  @override
  Stream<void> get logoChanges => updates.stream;
}

class CountBookings extends FakeBookingRepository {
  int dashboardCalls = 0, dueCalls = 0;
  @override
  Future<BookingDashboard> dashboard({String? businessId}) {
    dashboardCalls++;
    return super.dashboard(businessId: businessId);
  }

  @override
  Future<OutstandingPage> outstanding({
    String? date,
    String? businessId,
    int cursor = 0,
  }) {
    dueCalls++;
    return super.outstanding(
      date: date,
      businessId: businessId,
      cursor: cursor,
    );
  }
}

class StartupApi extends Fake implements RestApiService {
  final authorization = Completer<void>();
  int logoRequests = 0;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    dynamic data,
    bool readOnly = false,
  }) async => {
    'organization': {
      'id': 'org',
      'name': 'Eden',
      'contact_phone': '9876543210',
      'currency': 'INR',
      'logo_storage_key': 'logo-1',
    },
    'membership': {'role': 'owner'},
    'businesses': [],
    'locations': [],
  };
  @override
  Future<void> authorizeReads(Map<String, dynamic> workspace) =>
      authorization.future;
  @override
  Future<List<int>> retainedBytes(String path) async {
    logoRequests++;
    return [1, 2, 3];
  }
}

void main() {
  test(
    'background logo cache updates are rendered and subscription closes safely',
    () async {
      final source = UpdatingLogoSource();
      final w = WorkspaceCubit(source);
      await w.load();
      source.image.complete(Uint8List.fromList([1]));
      await Future<void>.delayed(Duration.zero);
      source.image = Completer<Uint8List?>();
      source.updates.add(null);
      await Future<void>.delayed(Duration.zero);
      source.image.complete(Uint8List.fromList([2]));
      await Future<void>.delayed(Duration.zero);
      expect(w.state.data.logo, [2]);
      await w.close();
      source.updates.add(null);
      await source.updates.close();
    },
  );
  test(
    'workspace repository returns after verified access without fetching branding',
    () async {
      final api = StartupApi();
      // Use one explicitly scoped API for both authorization and optional branding.
      final source = RestWorkspaceRepository(api);
      var completed = false;
      final pending = source.load().then((v) {
        completed = true;
        return v;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      api.authorization.complete();
      final data = await pending;
      expect(data.organization!.id, 'org');
      expect(data.logo, isNull);
      expect(api.logoRequests, 0);
      expect(await source.loadLogo(), [1, 2, 3]);
      expect(api.logoRequests, 1);
    },
  );
  test(
    'slow logo never blocks ready state; cached logo and content survive revalidation',
    () async {
      final source = LogoSource();
      final cubit = WorkspaceCubit(source);
      await cubit.load();
      expect(cubit.state.status, LoadStatus.ready);
      expect(cubit.state.data.logo, isNull);
      source.image.complete(Uint8List.fromList([1, 2]));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.data.logo, [1, 2]);
      source.image = Completer<Uint8List?>();
      source.access = Completer<Workspace>();
      final loading = cubit.load();
      expect(cubit.state.data.organization!.id, 'org');
      expect(cubit.state.data.logo, [1, 2]);
      source.access!.complete(source.value);
      await loading;
      expect(cubit.state.data.logo, [1, 2]);
      source.image.completeError(Exception('Logo unavailable'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.status, LoadStatus.ready);
      expect(cubit.state.data.logo, [1, 2]);
      await cubit.close();
    },
  );
  test(
    'logo-only updates do not duplicate dashboard requests or clear cached figures',
    () async {
      final source = LogoSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final bookings = CountBookings();
      final home = HomeCubit(SessionDashboardRepository(workspace), bookings);
      await Future<void>.delayed(Duration.zero);
      final figures = home.state.dashboard;
      expect(figures, isNotNull);
      expect(bookings.dashboardCalls, 1);
      expect(bookings.dueCalls, 1);
      source.image.complete(Uint8List.fromList([1]));
      await Future<void>.delayed(Duration.zero);
      expect(home.state.data.logo, [1]);
      expect(home.state.dashboard, same(figures));
      expect(bookings.dashboardCalls, 1);
      expect(bookings.dueCalls, 1);
      source.access = Completer<Workspace>();
      final refresh = workspace.load();
      await Future<void>.delayed(Duration.zero);
      expect(home.state.dashboard, same(figures));
      source.access!.complete(source.value);
      await refresh;
      await Future<void>.delayed(Duration.zero);
      expect(bookings.dashboardCalls, 1);
      expect(bookings.dueCalls, 1);
      await home.close();
      await workspace.close();
    },
  );
  test(
    'late branding is ignored after signout and access denial clears retained content',
    () async {
      final source = LogoSource();
      final w = WorkspaceCubit(source);
      await w.load();
      w.clear();
      source.image.complete(Uint8List.fromList([1]));
      await Future<void>.delayed(Duration.zero);
      expect(w.state.data.organization, isNull);
      expect(w.state.data.logo, isNull);
      source.image = Completer<Uint8List?>();
      await w.load();
      source.access = Completer<Workspace>();
      final denied = w.load();
      source.access!.completeError(
        const AppException('Denied', code: 'FORBIDDEN'),
      );
      await denied;
      expect(w.state.data.organization, isNull);
      await w.close();
    },
  );
}

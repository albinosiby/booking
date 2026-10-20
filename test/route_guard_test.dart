import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/config/routes/route_guard.dart';
import 'package:eden_booking/modules/auth/cubit/auth_state.dart';
import 'package:eden_booking/modules/auth/models/app_user.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_state.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';

const signedIn = AuthState(
  status: AuthStatus.signedIn,
  user: AppUser(
    id: 'owner',
    email: 'owner@example.com',
    name: 'Owner',
    verified: true,
  ),
);
const owner = WorkspaceState(
  status: LoadStatus.ready,
  data: Workspace(
    organization: Organization(
      id: 'org',
      name: 'Eden',
      phone: '123456789',
      currency: 'INR',
    ),
    membership: {'role': 'owner'},
    businesses: [
      Business(
        id: 'b',
        name: 'Turf',
        type: BusinessType.turf,
        status: 'draft',
        locationId: 'l',
        version: 1,
        resources: [],
      ),
    ],
  ),
);
void main() {
  test('turf setup deep link is restored after startup', () {
    const target = '/businesses/b/setup';
    final loading = routeRedirect(
      const AuthState(),
      const WorkspaceState(),
      Uri.parse(target),
      requireVerification: false,
    )!;
    expect(Uri.parse(loading).queryParameters['from'], target);
    expect(
      routeRedirect(
        signedIn,
        owner,
        Uri.parse(loading),
        requireVerification: false,
      ),
      target,
    );
  });
  test('protected deep links survive session and workspace initialization', () {
    final loading = routeRedirect(
      const AuthState(),
      const WorkspaceState(),
      Uri.parse('/team/invite'),
      requireVerification: false,
    )!;
    expect(Uri.parse(loading).path, '/loading');
    expect(Uri.parse(loading).queryParameters['from'], '/team/invite');
    expect(
      routeRedirect(
        signedIn,
        owner,
        Uri.parse(loading),
        requireVerification: false,
      ),
      '/team/invite',
    );
  });
  test(
    'unauthenticated deep links keep a safe destination through sign-in',
    () {
      final location = routeRedirect(
        const AuthState(status: AuthStatus.signedOut),
        const WorkspaceState(),
        Uri.parse('/profile'),
        requireVerification: false,
      )!;
      expect(Uri.parse(location).path, '/sign-in');
      expect(Uri.parse(location).queryParameters['from'], '/profile');
      expect(
        routeRedirect(
          signedIn,
          owner,
          Uri.parse(location),
          requireVerification: false,
        ),
        '/profile',
      );
    },
  );
  test('an invitation token survives loading and sign-in', () {
    final loading = routeRedirect(
      const AuthState(),
      const WorkspaceState(),
      Uri.parse('/invite?token=private-token'),
      requireVerification: false,
    )!;
    final signin = routeRedirect(
      const AuthState(status: AuthStatus.signedOut),
      const WorkspaceState(),
      Uri.parse(loading),
      requireVerification: false,
    )!;
    expect(Uri.parse(signin).queryParameters['invite'], 'private-token');
    expect(
      routeRedirect(
        signedIn,
        owner,
        Uri.parse(signin),
        requireVerification: false,
      ),
      '/invite?token=private-token',
    );
  });
  test(
    'a failed workspace refresh retains the current page when data exists',
    () {
      final retained = WorkspaceState(
        status: LoadStatus.failure,
        data: owner.data,
        error: 'Offline',
      );
      expect(
        routeRedirect(
          signedIn,
          retained,
          Uri.parse('/accounts/settings'),
          requireVerification: false,
        ),
        isNull,
      );
      expect(
        routeRedirect(
          signedIn,
          const WorkspaceState(status: LoadStatus.failure),
          Uri.parse('/accounts/settings'),
          requireVerification: false,
        ),
        startsWith('/loading'),
      );
    },
  );
  test('external return URLs are never followed', () {
    for (final target in ['https://example.com', '//example.com', '/loading']) {
      expect(
        routeRedirect(
          signedIn,
          owner,
          Uri(path: '/loading', queryParameters: {'from': target}),
          requireVerification: false,
        ),
        '/home',
      );
    }
  });
  test('restored destinations still enforce staff restrictions', () {
    const staff = WorkspaceState(
      status: LoadStatus.ready,
      data: Workspace(
        organization: Organization(
          id: 'org',
          name: 'Eden',
          phone: '123456789',
          currency: 'INR',
        ),
        membership: {'role': 'staff'},
      ),
    );
    expect(
      routeRedirect(
        signedIn,
        staff,
        Uri.parse('/team/invite'),
        requireVerification: false,
      ),
      '/home',
    );
  });
}

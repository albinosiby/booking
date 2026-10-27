import 'package:eden_booking/config/routes/route_guard.dart';
import 'package:eden_booking/config/routes/routes.dart';
import 'package:eden_booking/modules/auth/cubit/auth_state.dart';
import 'package:eden_booking/modules/auth/models/app_user.dart';
import 'package:eden_booking/modules/auth/models/auth_continuation.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_state.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

const _token =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

AuthState signedIn({bool verified = true, bool recovery = false}) => AuthState(
  status: AuthStatus.signedIn,
  user: AppUser(
    id: 'u',
    email: 'u@example.com',
    name: 'U',
    verified: verified,
    passwordRecovery: recovery,
  ),
);

const signedOut = AuthState(status: AuthStatus.signedOut);

const _org = Organization(
  id: 'org',
  name: 'Eden',
  phone: '9876543210',
  currency: 'INR',
);
const _business = Business(
  id: 'b',
  name: 'Turf',
  type: BusinessType.turf,
  status: 'ready',
  locationId: 'l',
  version: 1,
  resources: [],
);

WorkspaceState ready({
  String role = 'owner',
  List<String> permissions = const [],
  bool withOrg = true,
  bool withBusiness = true,
}) => WorkspaceState(
  status: LoadStatus.ready,
  data: Workspace(
    organization: withOrg ? _org : null,
    membership: {'role': role, 'permissions': permissions},
    businesses: withBusiness ? const [_business] : const [],
  ),
);

String? redirect(
  AuthState auth,
  WorkspaceState ws,
  String location, {
  bool verify = false,
  AuthContinuation? continuation,
}) => routeRedirect(
  auth,
  ws,
  Uri.parse(location),
  requireVerification: verify,
  continuation: continuation,
);

/// A confirmed defect, kept but skipped. The id is in the test name.
void bug(String id, String name, void Function() body) =>
    test('[$id] $name', body, skip: true);

void main() {
  group('signed out', () {
    test('every protected path goes to sign-in and remembers the path', () {
      for (final path in [
        '/home',
        '/bookings',
        '/team',
        '/team/edit',
        '/businesses/b/setup',
        '/profile/support',
        '/organization/details/edit',
        '/profile/agent-calls',
        '/anything/unknown',
      ]) {
        final out = redirect(signedOut, const WorkspaceState(), path)!;
        final uri = Uri.parse(out);
        expect(uri.path, Routes.signIn, reason: path);
        expect(uri.queryParameters['from'], path, reason: path);
      }
    });

    test('sign-in and register are reachable without a redirect', () {
      expect(redirect(signedOut, const WorkspaceState(), '/sign-in'), isNull);
      expect(redirect(signedOut, const WorkspaceState(), '/register'), isNull);
      expect(
        redirect(
          signedOut,
          const WorkspaceState(),
          '/register?invite=$_token&from=/home',
        ),
        isNull,
      );
    });

    test(
      'query on the auth pages is kept when bounced from protected page',
      () {
        final out = redirect(
          signedOut,
          const WorkspaceState(),
          '/invite?token=$_token',
        )!;
        final uri = Uri.parse(out);
        expect(uri.path, Routes.signIn);
        expect(uri.queryParameters['invite'], _token);
      },
    );

    test('a hostile from value is dropped, not echoed', () {
      for (final from in [
        'https://evil.example',
        '//evil.example',
        r'/\evil.example',
        'javascript:alert(1)',
        '/sign-in',
      ]) {
        final out = redirect(
          signedOut,
          const WorkspaceState(),
          Uri(path: '/home', queryParameters: {'from': from}).toString(),
        )!;
        // The visited in-app URL is the destination; the hostile value is
        // inert query data and can never become the navigation target.
        final dest = Uri.parse(Uri.parse(out).queryParameters['from']!);
        expect(dest.path, '/home', reason: from);
        expect(dest.hasScheme || dest.hasAuthority, isFalse, reason: from);
      }
    });

    test('emoji, unicode and encoded characters survive the round trip', () {
      const path = '/bookings?customer=ഏബിൻ%20😀&note=a%26b';
      final out = redirect(signedOut, const WorkspaceState(), path)!;
      final restored = routeRedirect(
        signedIn(),
        ready(),
        Uri.parse(out),
        requireVerification: false,
      );
      expect(restored, isNotNull);
      expect(Uri.parse(restored!).path, '/bookings');
      expect(Uri.parse(restored).queryParameters['note'], 'a&b');
    });
  });

  group('startup and loading', () {
    test('unknown auth status shows the loading route once', () {
      expect(
        Uri.parse(
          redirect(const AuthState(), const WorkspaceState(), '/home')!,
        ).path,
        Routes.loading,
      );
      expect(
        redirect(const AuthState(), const WorkspaceState(), '/loading'),
        isNull,
      );
    });

    test('signed in with workspace not loaded waits on loading', () {
      for (final status in [LoadStatus.initial, LoadStatus.loading]) {
        final out = redirect(
          signedIn(),
          WorkspaceState(status: status),
          '/team',
        )!;
        expect(Uri.parse(out).path, Routes.loading);
        expect(Uri.parse(out).queryParameters['from'], '/team');
      }
      // a failed first load must not strand the user on a feature page
      final failed = redirect(
        signedIn(),
        const WorkspaceState(status: LoadStatus.failure, error: 'offline'),
        '/home',
      )!;
      expect(Uri.parse(failed).path, Routes.loading);
    });

    test('a refresh with an existing organization does not flash loading', () {
      final refreshing = WorkspaceState(
        status: LoadStatus.loading,
        data: ready().data,
      );
      expect(redirect(signedIn(), refreshing, '/home'), isNull);
    });

    test('loading route leaves for the restored destination when ready', () {
      expect(
        redirect(signedIn(), ready(), '/loading?from=%2Fbookings'),
        '/bookings',
      );
      expect(redirect(signedIn(), ready(), '/loading'), Routes.home);
    });

    bug(
      'BUG-12',
      'a busy auth action on an authenticated page does not unmount it',
      () {
        // e.g. saving a new password or resending verification keeps the form.
        const busy = AuthState(
          status: AuthStatus.signedIn,
          user: AppUser(
            id: 'u',
            email: 'u@example.com',
            name: 'U',
            verified: true,
            passwordRecovery: true,
          ),
          busy: true,
        );
        expect(redirect(busy, ready(), '/update-password'), isNull);
        expect(redirect(busy, ready(), '/verify'), isNull);
      },
    );
  });

  group('organization and onboarding guard', () {
    test('signed in without an organization is held on /organization', () {
      final ws = ready(withOrg: false);
      expect(
        Uri.parse(redirect(signedIn(), ws, '/home')!).path,
        Routes.organization,
      );
      expect(redirect(signedIn(), ws, '/organization'), isNull);
    });

    test('owner without businesses is held on onboarding', () {
      final ws = ready(withBusiness: false);
      expect(
        Uri.parse(redirect(signedIn(), ws, '/home')!).path,
        Routes.onboarding,
      );
      expect(redirect(signedIn(), ws, Routes.onboarding), isNull);
    });

    test('staff without businesses is not held on owner onboarding', () {
      final ws = ready(
        role: 'staff',
        permissions: const ['view_bookings'],
        withBusiness: false,
      );
      expect(redirect(signedIn(), ws, '/home'), isNull);
      expect(redirect(signedIn(), ws, Routes.onboarding), Routes.home);
    });

    test('auth pages bounce an authenticated owner to home or destination', () {
      expect(redirect(signedIn(), ready(), '/sign-in'), Routes.home);
      expect(redirect(signedIn(), ready(), '/register'), Routes.home);
      expect(
        redirect(signedIn(), ready(), '/sign-in?from=%2Fbookings'),
        '/bookings',
      );
      expect(redirect(signedIn(), ready(), '/organization'), Routes.home);
    });
  });

  group('verification and password recovery', () {
    test('unverified users are held on /verify and keep the destination', () {
      final out = redirect(
        signedIn(verified: false),
        ready(),
        '/bookings',
        verify: true,
      )!;
      expect(Uri.parse(out).path, '/verify');
      expect(Uri.parse(out).queryParameters['from'], '/bookings');
      expect(
        redirect(signedIn(verified: false), ready(), '/verify', verify: true),
        isNull,
      );
    });

    test('verification is not enforced when the config disables it', () {
      expect(redirect(signedIn(verified: false), ready(), '/home'), isNull);
    });

    test('verified users leave /verify', () {
      expect(
        redirect(signedIn(), ready(), '/verify', verify: true),
        Routes.home,
      );
    });

    test('password recovery wins over every other page and invitation', () {
      for (final path in [
        '/home',
        '/team',
        '/verify',
        '/invite?token=$_token',
      ]) {
        expect(
          redirect(signedIn(recovery: true), ready(), path, verify: true),
          '/update-password',
          reason: path,
        );
      }
      expect(
        redirect(signedIn(recovery: true), ready(), '/update-password'),
        isNull,
      );
    });

    test('update-password is unreachable without a recovery session', () {
      expect(redirect(signedIn(), ready(), '/update-password'), Routes.home);
      expect(
        Uri.parse(
          redirect(signedOut, const WorkspaceState(), '/update-password')!,
        ).path,
        Routes.signIn,
      );
    });
  });

  group('invitation links', () {
    test('signed-in user with an invite token is sent to /invite', () {
      final out = redirect(signedIn(), ready(), '/sign-in?invite=$_token')!;
      expect(Uri.parse(out).path, Routes.invite);
      expect(Uri.parse(out).queryParameters['token'], _token);
    });

    test('/invite itself is allowed for a signed-in user', () {
      expect(redirect(signedIn(), ready(), '/invite?token=$_token'), isNull);
    });

    test('invite survives verification', () {
      final out = redirect(
        signedIn(verified: false),
        ready(),
        '/invite?token=$_token',
        verify: true,
      )!;
      expect(Uri.parse(out).path, '/verify');
      expect(Uri.parse(out).queryParameters['invite'], _token);
    });

    test('a valid continuation restores token and destination at callback', () {
      final continuation = AuthContinuation(
        createdAt: DateTime.now(),
        invitationToken: _token,
        returnTo: '/bookings',
      );
      final out = redirect(
        signedIn(),
        ready(),
        '/auth-callback',
        continuation: continuation,
      )!;
      expect(Uri.parse(out).path, Routes.invite);
      expect(Uri.parse(out).queryParameters['token'], _token);
    });

    test('an expired continuation is ignored', () {
      final continuation = AuthContinuation(
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        invitationToken: _token,
        returnTo: '/bookings',
      );
      expect(
        redirect(
          signedIn(),
          ready(),
          '/auth-callback',
          continuation: continuation,
        ),
        Routes.home,
      );
    });

    bug(
      'BUG-13',
      'an empty ?invite= value is not treated as an invitation',
      () {
        expect(redirect(signedIn(), ready(), '/sign-in?invite='), Routes.home);
        expect(redirect(signedIn(), ready(), '/invite?token='), isNot(isNull));
      },
    );

    bug(
      'BUG-14',
      'a malformed invite token is rejected at the router, not sent to the server',
      () {
        final out = redirect(
          signedIn(),
          ready(),
          '/sign-in?invite=%3Cscript%3E',
        );
        expect(out, Routes.home);
      },
    );
  });

  group('role based path guard', () {
    final staff = ready(role: 'staff', permissions: const ['view_bookings']);
    test('staff cannot open owner-only pages', () {
      for (final path in [
        '/team',
        '/team/edit',
        '/team/coaches',
        '/businesses',
        '/businesses/add',
        '/businesses/b/setup',
        '/profile/agent-calls',
        '/profile/agent-calls/calls',
        '/organization/details',
        '/organization/details/edit',
        '/profile/booking-website',
        '/profile/message-templates',
        '/accounts/settings',
        '/accounts/bank',
        '/accounts/cash',
      ]) {
        expect(redirect(signedIn(), staff, path), Routes.home, reason: path);
      }
    });

    test('staff keep shared pages such as support and profile', () {
      for (final path in [
        '/home',
        '/profile',
        '/profile/support',
        '/bookings',
      ]) {
        expect(redirect(signedIn(), staff, path), isNull, reason: path);
      }
    });

    test('permissions gate finance and customer pages', () {
      final none = ready(role: 'staff');
      for (final path in ['/payments', '/income', '/customers', '/bookings']) {
        expect(redirect(signedIn(), none, path), Routes.home, reason: path);
      }
      final finance = ready(role: 'staff', permissions: const ['view_finance']);
      expect(redirect(signedIn(), finance, '/payments'), isNull);
      expect(redirect(signedIn(), finance, '/income'), isNull);
    });

    test('owner reaches every page including owner-only', () {
      for (final path in [
        '/team',
        '/businesses/add',
        '/profile/agent-calls',
        '/organization/details/edit',
        '/payments',
      ]) {
        expect(redirect(signedIn(), ready(), path), isNull, reason: path);
      }
    });

    test(
      'coaching classes require the coach permission even for the owner',
      () {
        expect(redirect(signedIn(), ready(), '/coaching/classes'), Routes.home);
        expect(
          redirect(
            signedIn(),
            ready(role: 'staff', permissions: const ['coach']),
            '/coaching/classes',
          ),
          isNull,
        );
      },
    );

    test('a role downgrade mid-session pushes the user off owner pages', () {
      expect(redirect(signedIn(), ready(), '/team'), isNull);
      expect(redirect(signedIn(), staff, '/team'), Routes.home);
    });

    test('manager is not treated as owner', () {
      final manager = ready(
        role: 'manager',
        permissions: const ['view_bookings', 'manage_bookings'],
      );
      expect(redirect(signedIn(), manager, '/team'), Routes.home);
      expect(redirect(signedIn(), manager, '/bookings'), isNull);
    });
  });

  group('safe return path is aligned with real routes', () {
    bug(
      'BUG-11',
      'the real onboarding route is excluded from return paths',
      () {
        // safeReturnPath blocks "/onboarding" but the route is
        // "/onboarding/businesses".
        final out = redirect(
          signedOut,
          const WorkspaceState(),
          '/sign-in?from=${Uri.encodeComponent(Routes.onboarding)}',
        );
        expect(out, isNull);
        expect(
          redirect(
            signedIn(),
            ready(),
            '/sign-in?from=${Uri.encodeComponent(Routes.onboarding)}',
          ),
          Routes.home,
        );
      },
    );
  });
}

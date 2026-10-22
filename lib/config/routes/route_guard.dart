import '../../modules/auth/cubit/auth_state.dart';
import '../../modules/workspace/cubit/workspace_state.dart';
import 'routes.dart';

String? _safeDestination(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !value.startsWith('/') ||
      value.startsWith('//')) {
    return null;
  }
  if ([
    Routes.register,
    Routes.signIn,
    Routes.loading,
    Routes.organization,
    Routes.onboarding,
    Routes.invite,
    '/verify',
    '/auth-callback',
    '/auth-callback/',
    '/update-password',
  ].contains(uri.path)) {
    return null;
  }
  return uri.toString();
}

String? routeRedirect(
  AuthState auth,
  WorkspaceState workspace,
  Uri uri, {
  required bool requireVerification,
}) {
  final path = uri.path;
  final invite =
      uri.queryParameters['invite'] ??
      (path == Routes.invite ? uri.queryParameters['token'] : null);
  final destination =
      _safeDestination(uri.queryParameters['from']) ??
      _safeDestination(uri.toString());
  String navigate(String target) => Uri(
    path: target,
    queryParameters: {'from': ?destination, 'invite': ?invite},
  ).toString();
  if (auth.busy && (path == Routes.register || path == Routes.signIn)) {
    return null;
  }
  if (auth.status == AuthStatus.loading || auth.busy) {
    return path == Routes.loading ? null : navigate(Routes.loading);
  }
  if (auth.status == AuthStatus.signedOut) {
    return path == Routes.register || path == Routes.signIn
        ? null
        : navigate(Routes.signIn);
  }
  if (auth.user?.passwordRecovery == true) {
    return path == '/update-password' ? null : '/update-password';
  }
  if (requireVerification && auth.user?.verified != true) {
    return path == '/verify' ? null : navigate('/verify');
  }
  if (invite != null && path != Routes.invite) {
    return Uri(
      path: Routes.invite,
      queryParameters: {'token': invite},
    ).toString();
  }
  if (path == Routes.invite) return null;
  if (workspace.status == LoadStatus.initial ||
      workspace.status == LoadStatus.loading &&
          workspace.data.organization == null ||
      workspace.status == LoadStatus.failure &&
          workspace.data.organization == null) {
    return path == Routes.loading ? null : navigate(Routes.loading);
  }
  if (workspace.data.organization == null) {
    return path == Routes.organization ? null : navigate(Routes.organization);
  }
  if (workspace.data.isOwner && workspace.data.businesses.isEmpty) {
    return path == Routes.onboarding ? null : navigate(Routes.onboarding);
  }
  if ([
    Routes.register,
    Routes.signIn,
    Routes.loading,
    Routes.organization,
    '/verify',
    '/auth-callback',
    '/auth-callback/',
    '/update-password',
  ].contains(path)) {
    return destination ?? Routes.home;
  }
  if (!workspace.data.isOwner &&
      (path.startsWith('/team') ||
          path.startsWith(Routes.agentCalls) ||
          path.startsWith('/businesses') ||
          path == Routes.organizationDetails ||
          path == Routes.organizationEdit ||
          path == Routes.onboarding)) {
    return Routes.home;
  }
  return null;
}

/// Only application-relative destinations may survive an authentication round trip.
String? safeReturnPath(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !value.startsWith('/') ||
      value.startsWith('//') ||
      value.contains(r'\')) {
    return null;
  }
  if (const {
    '/register',
    '/sign-in',
    '/loading',
    '/organization',
    '/onboarding',
    '/invite',
    '/verify',
    '/auth-callback',
    '/auth-callback/',
    '/update-password',
  }.contains(uri.path)) {
    return null;
  }
  return uri.toString();
}

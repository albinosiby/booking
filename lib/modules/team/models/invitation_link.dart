/// A validated app invitation, independent of any platform deep-link client.
class InvitationLink {
  const InvitationLink(this.token);
  const InvitationLink.signIn() : token = null;
  final String? token;
  bool get isSignIn => token == null;
  String get route => isSignIn
      ? '/sign-in'
      : Uri(path: '/invite', queryParameters: {'token': token!}).toString();
  static InvitationLink? fromUri(Uri? uri) {
    if (uri?.scheme == 'bookingservice.tatos.tech' &&
        uri?.host == 'login' &&
        uri?.path == '/sign-in' &&
        uri!.query.isEmpty &&
        uri.fragment.isEmpty) {
      return const InvitationLink.signIn();
    }
    if (uri == null ||
        !{
          'com.bookingos.app',
          'bookingservice.tatos.tech',
        }.contains(uri.scheme) ||
        uri.host != 'invite' ||
        uri.path != '/invite') {
      return null;
    }
    final token = uri.queryParameters['token'];
    return token != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(token)
        ? InvitationLink(token)
        : null;
  }
}

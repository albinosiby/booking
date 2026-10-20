/// A validated app invitation, independent of any platform deep-link client.
class InvitationLink {
  const InvitationLink(this.token);
  final String token;
  static InvitationLink? fromUri(Uri? uri) {
    if (uri == null ||
        uri.scheme != 'com.bookingos.app' ||
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

import 'package:app_links/app_links.dart';
import '../models/invitation_link.dart';

abstract interface class InvitationLinkRepository {
  Future<InvitationLink?> initial();
  Stream<InvitationLink> get links;
}

class DeviceInvitationLinkRepository implements InvitationLinkRepository {
  DeviceInvitationLinkRepository(this.client);
  final AppLinks client;
  @override
  Future<InvitationLink?> initial() async =>
      InvitationLink.fromUri(await client.getInitialLink());
  @override
  Stream<InvitationLink> get links => client.uriLinkStream
      .map(InvitationLink.fromUri)
      .where((link) => link != null)
      .cast<InvitationLink>();
}

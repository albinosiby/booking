import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/team/models/invitation_link.dart';
import 'package:eden_booking/modules/team/repositories/invitation_link_repository.dart';
import 'package:eden_booking/modules/team/cubit/invitation_link_cubit.dart';

class Links implements InvitationLinkRepository {
  final events = StreamController<InvitationLink>.broadcast();
  Completer<InvitationLink?>? pending;
  bool fail = false;
  @override
  Stream<InvitationLink> get links => events.stream;
  @override
  Future<InvitationLink?> initial() async {
    if (fail) throw StateError('Platform unavailable');
    return pending?.future;
  }
}

void main() {
  test(
    'only valid app invitation links enter the existing acceptance flow',
    () {
      final token = 'a' * 64;
      expect(
        InvitationLink.fromUri(
          Uri.parse('com.bookingos.app://invite/invite?token=$token'),
        )!.token,
        token,
      );
      expect(
        InvitationLink.fromUri(
          Uri.parse('bookingservice.tatos.tech://login/sign-in'),
        )!.route,
        '/sign-in',
      );
      expect(
        InvitationLink.fromUri(
          Uri.parse('bookingservice.tatos.tech://invite/invite?token=$token'),
        )!.token,
        token,
      );
      for (final uri in [
        'https://example.com/invite?token=$token',
        'bookingservice.tatos.tech://auth-callback/?token=$token',
        'com.bookingos.app://auth-callback/?token=$token',
        'com.bookingos.app://invite/invite?token=invalid',
        'bookingservice.tatos.tech://login/sign-in?from=https://evil.example',
        'bookingservice.tatos.tech://login/other',
      ]) {
        expect(InvitationLink.fromUri(Uri.parse(uri)), isNull);
      }
    },
  );
  test('new invitation wins over a late initial platform link', () async {
    final repo = Links()..pending = Completer<InvitationLink?>();
    final cubit = InvitationLinkCubit(repo);
    final start = cubit.start();
    repo.events.add(const InvitationLink('new'));
    await Future<void>.delayed(Duration.zero);
    repo.pending!.complete(const InvitationLink('old'));
    await start;
    expect(cubit.state!.token, 'new');
    await cubit.close();
    await repo.events.close();
  });
  test(
    'initial platform failure leaves later invitation events usable',
    () async {
      final repo = Links()..fail = true;
      final cubit = InvitationLinkCubit(repo);
      await cubit.start();
      repo.events.add(const InvitationLink('later'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state!.token, 'later');
      await cubit.close();
      await repo.events.close();
    },
  );
  test('closing discards a pending initial link', () async {
    final repo = Links()..pending = Completer<InvitationLink?>();
    final cubit = InvitationLinkCubit(repo);
    final start = cubit.start();
    await cubit.close();
    repo.pending!.complete(const InvitationLink('late'));
    await start;
    expect(cubit.state, isNull);
    await repo.events.close();
  });
}

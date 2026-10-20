import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/invitation_link.dart';
import '../repositories/invitation_link_repository.dart';

class InvitationLinkCubit extends Cubit<InvitationLink?> {
  InvitationLinkCubit(this.repository) : super(null);
  final InvitationLinkRepository repository;
  StreamSubscription<InvitationLink>? subscription;
  int received = 0;
  bool closing = false;
  Future<void> start() async {
    if (subscription != null || isClosed || closing) return;
    subscription = repository.links.listen((link) {
      received++;
      if (!isClosed && !closing) emit(link);
    }, onError: (Object _) {});
    final before = received;
    try {
      final link = await repository.initial();
      if (!isClosed && !closing && received == before && link != null) {
        emit(link);
      }
    } catch (_) {
      /* Platforms without link support remain usable. */
    }
  }

  @override
  Future<void> close() async {
    closing = true;
    await subscription?.cancel();
    await super.close();
  }
}

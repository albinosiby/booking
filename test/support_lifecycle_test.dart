import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/support/support_module.dart';

SupportThread thread(String subject) => SupportThread(
  SupportTicket(
    id: 'ticket',
    subject: subject,
    category: 'other',
    status: 'open',
    updatedAt: null,
  ),
  const [],
);

class SupportSource implements SupportRepository {
  final lists = <Completer<List<SupportTicket>>>[];
  final reads = <Completer<SupportThread>>[];
  final replies = <Completer<SupportThread>>[];
  @override
  Future<List<SupportTicket>> tickets() {
    final pending = Completer<List<SupportTicket>>();
    lists.add(pending);
    return pending.future;
  }

  @override
  Future<SupportThread> thread(String id) {
    final pending = Completer<SupportThread>();
    reads.add(pending);
    return pending.future;
  }

  @override
  Future<SupportThread> reply(String id, String message) {
    final pending = Completer<SupportThread>();
    replies.add(pending);
    return pending.future;
  }

  @override
  Future<SupportThread> create(
    String category,
    String subject,
    String message,
  ) => Future.value(thread('Created'));
}

void main() {
  test(
    'support list ignores older responses and loads after disposal',
    () async {
      final source = SupportSource();
      final cubit = SupportListCubit(source);
      final older = cubit.load();
      final newer = cubit.load();
      source.lists[1].complete([thread('Latest').ticket]);
      await newer;
      source.lists[0].complete([thread('Stale').ticket]);
      await older;
      expect(cubit.state.tickets.single.subject, 'Latest');
      await cubit.close();
      await cubit.load();
      expect(source.lists, hasLength(2));
    },
  );

  test('reply excludes duplicate sends and supersedes pending reads', () async {
    final source = SupportSource();
    final cubit = SupportThreadCubit(source, 'ticket');
    final reading = cubit.load();
    final sending = cubit.reply('Reply');
    expect(await cubit.reply('Duplicate'), isFalse);
    expect(source.replies, hasLength(1));
    source.replies.single.complete(thread('With reply'));
    expect(await sending, isTrue);
    source.reads.single.complete(thread('Before reply'));
    await reading;
    expect(cubit.state.thread!.ticket.subject, 'With reply');
    await cubit.close();
    expect(await cubit.reply('After disposal'), isFalse);
    await cubit.load();
    expect(source.reads, hasLength(1));
  });

  test('thread retry shows loading and clears previous load error', () async {
    final source = SupportSource();
    final cubit = SupportThreadCubit(source, 'ticket');
    final failed = cubit.load();
    source.reads.single.completeError(Exception('offline'));
    await failed;
    expect(cubit.state.error, isNotNull);
    final retry = cubit.load();
    expect(cubit.state.loading, isTrue);
    expect(cubit.state.error, isNull);
    source.reads.last.complete(thread('Recovered'));
    await retry;
    expect(cubit.state.loading, isFalse);
    await cubit.close();
  });
}

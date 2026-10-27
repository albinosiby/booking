// Field-value tests for lib/modules/notifications: push payload parsing and
// account-state edge cases.
import 'dart:convert';
import 'package:eden_booking/modules/auth/models/app_user.dart';
import 'package:eden_booking/modules/notifications/cubit/notification_cubit.dart';
import 'package:eden_booking/modules/notifications/models/booking_notification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'notification_lifecycle_test.dart'
    show NotificationAuthFake, PushFake, drain, userA;

const event = '00000000-0000-4000-8000-000000000001';
const booking = '00000000-0000-4000-8000-000000000002';

Map<String, dynamic> data({
  Object? e = event,
  Object? b = booking,
  Object? u = 'user-1',
  Object? k = 'created',
}) => {'event_id': e, 'booking_id': b, 'recipient_user_id': u, 'event_type': k};

void main() {
  group('BookingNotification.fromData', () {
    test('accepts valid payloads, any uuid case, all kinds', () {
      for (final k in ['created', 'cancelled', 'rescheduled']) {
        expect(BookingNotification.fromData(data(k: k))?.kind, k);
      }
      expect(
        BookingNotification.fromData(data(e: event.toUpperCase()))?.eventId,
        event.toUpperCase(),
      );
      expect(BookingNotification.fromData(data(u: 'x'))?.userId, 'x');
      expect(
        BookingNotification.fromData(data(u: '😀 user'))?.userId,
        '😀 user',
      );
      final n = BookingNotification.fromData(
        data(),
        title: 'T' * 5000,
        body: '😀',
      );
      expect(n!.title!.length, 5000);
    });
    test('rejects malformed ids', () {
      for (final bad in [
        '',
        ' ',
        'not-a-uuid',
        '00000000-0000-4000-8000-00000000000',
        '00000000-0000-4000-8000-0000000000012',
        '0000000000004000800000000000001',
        '{00000000-0000-4000-8000-000000000001}',
        ' 00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000001 ',
        '00000000-0000-4000-8000-000000000001\n',
        '00000000-0000-4000-8000-00000000000g',
        '00000000-0000-4000-8000-00000000000١',
        '😀',
      ]) {
        expect(
          BookingNotification.fromData(data(e: bad)),
          isNull,
          reason: 'event "$bad"',
        );
        expect(
          BookingNotification.fromData(data(b: bad)),
          isNull,
          reason: 'booking "$bad"',
        );
      }
    });
    test('rejects wrong types, nulls, empty user and unknown kinds', () {
      for (final bad in [
        null,
        5,
        true,
        <String>[],
        {'a': 1},
      ]) {
        expect(BookingNotification.fromData(data(e: bad)), isNull);
        expect(BookingNotification.fromData(data(b: bad)), isNull);
        expect(BookingNotification.fromData(data(u: bad)), isNull);
        expect(BookingNotification.fromData(data(k: bad)), isNull);
      }
      expect(BookingNotification.fromData(data(u: '')), isNull);
      for (final k in [
        '',
        'CREATED',
        ' created',
        'created ',
        'deleted',
        'paid',
        '😀',
      ]) {
        expect(
          BookingNotification.fromData(data(k: k)),
          isNull,
          reason: '"$k"',
        );
      }
      expect(BookingNotification.fromData(const {}), isNull);
    });
    test(
      'BUG-21 a whitespace-only recipient id is refused',
      () {
        expect(BookingNotification.fromData(data(u: '   ')), isNull);
      },
      skip:
          'BUG-21: recipient_user_id only checked with isEmpty, "   " is accepted',
    );
    test('toData round trips through JSON', () {
      final n = BookingNotification.fromData(data())!;
      final back = BookingNotification.fromData(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(n.toData())) as Map),
      );
      expect(back, n.copyWithoutText());
    });
  });

  group('notification cubit account states', () {
    test(
      'unverified and password-recovery users are never registered',
      () async {
        final auth = NotificationAuthFake()
          ..user = const AppUser(
            id: 'u',
            email: 'e',
            name: 'n',
            verified: false,
          );
        final repo = PushFake();
        final cubit = NotificationCubit(repo, auth);
        await cubit.start();
        await drain();
        expect(repo.registrations, isEmpty);
        auth.change(
          const AppUser(
            id: 'u',
            email: 'e',
            name: 'n',
            verified: true,
            passwordRecovery: true,
          ),
        );
        await drain();
        expect(repo.registrations, isEmpty);
        auth.change(userA);
        await drain();
        expect(repo.registrations, ['a']);
        await cubit.close();
        await auth.events.close();
      },
    );

    test(
      'registration failure reports an error and keeps the app usable',
      () async {
        final auth = NotificationAuthFake();
        final repo = PushFake()..fail = true;
        final cubit = NotificationCubit(repo, auth);
        await cubit.start();
        await drain();
        expect(cubit.state.error, isNotNull);
        expect(cubit.state.registered, isFalse);
        await cubit.close();
        await auth.events.close();
      },
    );

    test(
      'push for another user and 150 distinct events do not throw',
      () async {
        final auth = NotificationAuthFake();
        final repo = PushFake();
        final cubit = NotificationCubit(repo, auth);
        await cubit.start();
        await drain();
        repo.foreground.add(
          BookingNotification.fromData(data(u: 'someone-else'))!,
        );
        for (var i = 0; i < 150; i++) {
          final id = '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
          repo.foreground.add(
            BookingNotification.fromData(data(e: id, u: 'a'))!,
          );
        }
        await drain();
        expect(repo.shown, hasLength(150));
        await cubit.close();
        await auth.events.close();
      },
    );
  });
}

extension on BookingNotification {
  BookingNotification copyWithoutText() => BookingNotification(
    eventId: eventId,
    bookingId: bookingId,
    userId: userId,
    kind: kind,
  );
}

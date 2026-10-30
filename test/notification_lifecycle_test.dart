import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/auth/cubit/auth_cubit.dart';
import 'package:eden_booking/modules/auth/models/app_user.dart';
import 'package:eden_booking/modules/auth/repositories/auth_repository_interface.dart';
import 'package:eden_booking/modules/notifications/cubit/notification_cubit.dart';
import 'package:eden_booking/modules/notifications/models/booking_notification.dart';
import 'package:eden_booking/modules/notifications/repositories/notification_repository.dart';

const userA = AppUser(
  id: 'a',
  email: 'a@example.com',
  name: 'A',
  verified: true,
);
const userB = AppUser(
  id: 'b',
  email: 'b@example.com',
  name: 'B',
  verified: true,
);
const notification = BookingNotification(
  eventId: '00000000-0000-4000-8000-000000000001',
  bookingId: '00000000-0000-4000-8000-000000000002',
  userId: 'a',
  kind: 'created',
);
Future<void> drain() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class NotificationAuthFake extends Fake implements AuthRepository {
  AppUser? user = userA;
  final events = StreamController<AppUser?>.broadcast();
  final actions = <String>[];
  @override
  Stream<AppUser?> get changes => events.stream;
  @override
  AppUser? get currentUser => user;
  void change(AppUser? value) {
    user = value;
    events.add(value);
  }

  @override
  Future<void> signOut() async {
    actions.add('auth-signout');
    change(null);
  }
}

class PushFake implements NotificationRepository {
  final tokens = StreamController<void>.broadcast();
  final foreground = StreamController<BookingNotification>.broadcast();
  final opened = StreamController<BookingNotification>.broadcast();
  final registrations = <String>[];
  final shown = <BookingNotification>[];
  final actions = <String>[];
  BookingNotification? initial;
  Completer<void>? registering, unlinking;
  Completer<void>? initializing;
  bool permission = true, fail = false, failInit = false;
  int unlinks = 0;
  @override
  Future<bool> initialize() async {
    await initializing?.future;
    if (failInit) throw StateError('No Firebase config');
    return true;
  }

  @override
  Stream<void> get tokenChanges => tokens.stream;
  @override
  Stream<BookingNotification> get foregroundMessages => foreground.stream;
  @override
  Stream<BookingNotification> get openedMessages => opened.stream;
  @override
  Future<BookingNotification?> initialMessage() async => initial;
  @override
  Future<bool> register(String userId) async {
    registrations.add(userId);
    await registering?.future;
    if (fail) throw StateError('Offline');
    return permission;
  }

  @override
  Future<void> unregister() async {
    unlinks++;
    await unlinking?.future;
    actions.add('unlinked');
  }

  @override
  Future<void> show(BookingNotification message) async {
    shown.add(message);
  }

  @override
  Future<void> dispose() async {
    await tokens.close();
    await foreground.close();
    await opened.close();
  }
}

void main() {
  test(
    'cash confirmation parses a settlement, deduplicates delivery and opens Payments for the signed-in recipient',
    () async {
      final auth = NotificationAuthFake(), repo = PushFake();
      final cubit = NotificationCubit(repo, auth);
      await cubit.start();
      await drain();
      final payload = {
        'event_id': '00000000-0000-4000-8000-000000000001',
        'settlement_id': '00000000-0000-4000-8000-000000000003',
        'recipient_user_id': 'a',
        'event_type': 'staff_cash_collected',
      };
      final cash = BookingNotification.fromData(
        payload,
        title: 'Cash collection confirmed',
        body: '₹1,500.00 collected',
      )!;
      expect(cash.route, '/payments');
      expect(cash.bookingId, isEmpty);
      expect(
        BookingNotification.fromData(cash.toData())?.settlementId,
        cash.settlementId,
      );
      expect(
        BookingNotification.fromData({...payload, 'settlement_id': 'invalid'}),
        isNull,
      );
      repo.foreground.add(cash);
      repo.foreground.add(cash);
      await drain();
      expect(repo.shown.length, 1);
      repo.opened.add(cash);
      await drain();
      expect(cubit.state.pending?.route, '/payments');
      auth.change(userB);
      await drain();
      repo.opened.add(cash);
      await drain();
      expect(cubit.state.pending, isNull);
      await cubit.close();
      await auth.events.close();
    },
  );

  test(
    'initialization and late auth refresh cannot re-register during logout',
    () async {
      final auth = NotificationAuthFake(),
          repo = PushFake()..initializing = Completer<void>(),
          cubit = NotificationCubit(repo, auth);
      final starting = cubit.start();
      await drain();
      await cubit.signOut();
      auth.change(userA);
      cubit.resumed();
      await drain();
      repo.initializing!.complete();
      await starting;
      await drain();
      expect(repo.registrations, isEmpty);
      expect(cubit.state.registered, false);
      auth.change(null);
      await drain();
      auth.change(userB);
      await drain();
      expect(repo.registrations, ['b']);
      await cubit.close();
      await auth.events.close();
    },
  );
  test(
    'restored login registers; token refresh re-registers; foreground events are deduplicated',
    () async {
      final auth = NotificationAuthFake(),
          repo = PushFake(),
          cubit = NotificationCubit(repo, auth);
      await cubit.start();
      await drain();
      expect(repo.registrations, ['a']);
      expect(cubit.state.registered, true);
      repo.tokens.add(null);
      await drain();
      expect(repo.registrations, ['a', 'a']);
      repo.foreground.add(notification);
      repo.foreground.add(notification);
      await drain();
      expect(repo.shown, [notification]);
      await cubit.close();
      await auth.events.close();
    },
  );
  test(
    'account switch suppresses previous foreground messages and pending taps',
    () async {
      final auth = NotificationAuthFake(),
          repo = PushFake()..initial = notification,
          cubit = NotificationCubit(repo, auth);
      await cubit.start();
      await drain();
      expect(cubit.state.pending, notification);
      auth.change(userB);
      await drain();
      expect(cubit.state.pending, isNull);
      repo.foreground.add(notification);
      repo.opened.add(notification);
      await drain();
      expect(repo.shown, isEmpty);
      expect(cubit.state.pending, isNull);
      expect(repo.registrations.last, 'b');
      await cubit.close();
      await auth.events.close();
    },
  );
  test(
    'signout waits for in-flight registration and unlink before clearing auth credentials',
    () async {
      final auth = NotificationAuthFake(),
          repo = PushFake()
            ..registering = Completer<void>()
            ..unlinking = Completer<void>(),
          cubit = NotificationCubit(repo, auth);
      final authCubit = AuthCubit(auth, beforeSignOut: cubit.signOut);
      await cubit.start();
      await drain();
      final logout = authCubit.signOut();
      await drain();
      expect(auth.actions, isEmpty);
      expect(repo.unlinks, 0);
      repo.registering!.complete();
      await drain();
      expect(repo.unlinks, 1);
      expect(auth.actions, isEmpty);
      repo.unlinking!.complete();
      await logout;
      await drain();
      expect(auth.actions, ['auth-signout']);
      expect(cubit.state.registered, false);
      await authCubit.close();
      await cubit.close();
      await auth.events.close();
    },
  );
  test(
    'denied permission leaves login usable, and resume recovers temporary registration failure',
    () async {
      final auth = NotificationAuthFake(),
          repo = PushFake()..permission = false,
          cubit = NotificationCubit(repo, auth);
      await cubit.start();
      await drain();
      expect(cubit.state.registered, false);
      expect(auth.currentUser, userA);
      repo.permission = true;
      repo.fail = true;
      await cubit.refresh();
      expect(cubit.state.error, isNotNull);
      repo.fail = false;
      cubit.resumed();
      await drain();
      expect(cubit.state.registered, true);
      expect(cubit.state.error, isNull);
      await cubit.close();
      await auth.events.close();
    },
  );
  test(
    'initial tap waits for login and is retained only for its recipient',
    () async {
      final auth = NotificationAuthFake()..user = null,
          repo = PushFake()..initial = notification,
          cubit = NotificationCubit(repo, auth);
      await cubit.start();
      await drain();
      expect(cubit.state.pending, notification);
      auth.change(userA);
      await drain();
      expect(cubit.state.pending, notification);
      cubit.consume();
      expect(cubit.state.pending, isNull);
      await cubit.close();
      await auth.events.close();
    },
  );
  test(
    'missing Firebase config is isolated from auth and retries on resume',
    () async {
      final auth = NotificationAuthFake(),
          repo = PushFake()..failInit = true,
          cubit = NotificationCubit(repo, auth);
      await cubit.start();
      expect(cubit.state.error, isNotNull);
      expect(auth.currentUser, userA);
      repo.failInit = false;
      cubit.resumed();
      await drain();
      expect(cubit.state.registered, true);
      await cubit.close();
      await auth.events.close();
    },
  );
  test(
    'notification payload parser rejects arbitrary routes and malformed IDs',
    () {
      expect(
        BookingNotification.fromData({'route': 'https://other.example'}),
        isNull,
      );
      expect(
        BookingNotification.fromData({
          ...notification.toData(),
          'booking_id': '../admin',
        }),
        isNull,
      );
      expect(BookingNotification.fromData(notification.toData()), notification);
    },
  );
}

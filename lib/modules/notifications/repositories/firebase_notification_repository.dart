import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../../../config/app_config.dart';
import '../../../utils/services/rest_api_service.dart';
import '../../auth/repositories/auth_repository_interface.dart';
import '../models/booking_notification.dart';
import 'notification_repository.dart';

@pragma('vm:entry-point')
Future<void> bookingMessagingBackgroundHandler(RemoteMessage message) async {
  // Notification payloads are displayed by the OS. Never show a second copy here.
  await Firebase.initializeApp();
}

class FirebaseNotificationRepository implements NotificationRepository {
  FirebaseNotificationRepository(
    this._api,
    this._auth, [
    this._storage = const FlutterSecureStorage(),
  ]);
  final RestApiService _api;
  final AuthRepository _auth;
  final FlutterSecureStorage _storage;
  final _local = FlutterLocalNotificationsPlugin();
  final _tokens = StreamController<void>.broadcast();
  final _foreground = StreamController<BookingNotification>.broadcast();
  final _opened = StreamController<BookingNotification>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _initialized = false;
  BookingNotification? _localLaunch;
  Map<String, dynamic>? _installation;
  static const _storageKey = 'booking_push_installation_v1';
  // Android channel sounds are immutable. Use a new ID for existing installs.
  static const _channelId = 'booking_orders_bell_v2';
  static const _sound = RawResourceAndroidNotificationSound('new_booking_bell');
  static const _channel = AndroidNotificationChannel(
    _channelId,
    'Booking orders',
    description: 'Placed, cancelled and rescheduled bookings',
    importance: Importance.high,
    playSound: true,
    sound: _sound,
  );
  bool get _supported =>
      !kIsWeb &&
      AppConfig.useSupabase &&
      const [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  @override
  Stream<void> get tokenChanges => _tokens.stream;
  @override
  Stream<BookingNotification> get foregroundMessages => _foreground.stream;
  @override
  Stream<BookingNotification> get openedMessages => _opened.stream;

  @override
  Future<bool> initialize() async {
    if (!_supported) return false;
    if (_initialized) return true;
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(bookingMessagingBackgroundHandler);
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_booking'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final value = _decode(response.payload);
        if (value != null) _opened.add(value);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    // Present foreground messages ourselves on both platforms, after checking the active account.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _localLaunch = _decode(launch?.notificationResponse?.payload);
    }
    _subscriptions.add(
      _messaging.onTokenRefresh.listen(
        (_) => _tokens.add(null),
        onError: (Object e) =>
            _tokens.addError(StateError('Token refresh unavailable')),
      ),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessage.listen((message) {
        final value = BookingNotification.fromData(
          message.data,
          title: message.notification?.title,
          body: message.notification?.body,
        );
        if (value != null) _foreground.add(value);
      }),
    );
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final value = BookingNotification.fromData(message.data);
        if (value != null) _opened.add(value);
      }),
    );
    _initialized = true;
    return true;
  }

  BookingNotification? _decode(String? raw) {
    try {
      return raw == null
          ? null
          : BookingNotification.fromData(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<BookingNotification?> initialMessage() async {
    final local = _localLaunch;
    _localLaunch = null;
    final message = await _messaging.getInitialMessage();
    return local ??
        (message == null ? null : BookingNotification.fromData(message.data));
  }

  Future<Map<String, dynamic>> _identity() async {
    if (_installation != null) return _installation!;
    final raw = await _storage.read(key: _storageKey);
    if (raw != null) {
      // Fail closed on corrupt storage: do not replace a proof that may own an existing target.
      final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (value['id'] is! String ||
          value['secret'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['secret'] as String)) {
        throw StateError('Notification installation storage is invalid');
      }
      return _installation = value;
    }
    final random = Random.secure();
    final value = <String, dynamic>{
      'id': const Uuid().v4(),
      'secret': List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      'cleanup': false,
    };
    await _storage.write(key: _storageKey, value: jsonEncode(value));
    return _installation = value;
  }

  Future<void> _save(Map<String, dynamic> value) async {
    await _storage.write(key: _storageKey, value: jsonEncode(value));
    _installation = value;
  }

  Future<void> _cleanup(Map<String, dynamic> identity) async {
    await _api.request(
      '/notifications/installations/revoke',
      method: 'POST',
      readOnly:
          true, // Installation writes do not invalidate retained booking data.
      data: {
        'installation_id': identity['id'],
        'installation_secret': identity['secret'],
      },
    );
  }

  @override
  Future<bool> register(String userId) async {
    if (!_initialized || _auth.currentUser?.id != userId) return false;
    var identity = await _identity();
    if (identity['cleanup'] == true ||
        identity['user'] != null && identity['user'] != userId) {
      await _cleanup(identity);
      await _messaging.deleteToken();
      await _save({...identity, 'cleanup': false, 'user': null});
      identity = await _identity();
    }
    if (_auth.currentUser?.id != userId) return false;
    final permission = await _messaging.requestPermission();
    if (!const [
      AuthorizationStatus.authorized,
      AuthorizationStatus.provisional,
    ].contains(permission.authorizationStatus)) {
      await unregister();
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await _messaging.getAPNSToken() == null) {
      throw StateError('APNs token is not ready');
    }
    await _messaging.setAutoInitEnabled(true);
    final token = await _messaging.getToken();
    if (token == null) throw StateError('Notification token is not ready');
    if (_auth.currentUser?.id != userId) return false;
    // Persist cleanup intent before the request, including uncertain network outcomes.
    await _save({...identity, 'user': userId, 'cleanup': true});
    await _api.request(
      '/notifications/devices',
      method: 'POST',
      readOnly:
          true, // Installation writes do not invalidate retained booking data.
      data: {
        'installation_id': identity['id'],
        'installation_secret': identity['secret'],
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'token': token,
      },
    );
    if (_auth.currentUser?.id != userId) {
      await unregister();
      return false;
    }
    await _save({...identity, 'user': userId, 'cleanup': false});
    return true;
  }

  @override
  Future<void> unregister() async {
    if (!_supported) return;
    final identity = await _identity();
    await _save({...identity, 'cleanup': true});
    Object? failure;
    try {
      await _cleanup(identity);
    } catch (e) {
      failure = e;
    }
    if (_initialized) {
      await _local.cancelAll();
      await _messaging.setAutoInitEnabled(false);
      try {
        await _messaging.deleteToken();
      } catch (e) {
        failure ??= e;
      }
    }
    if (failure != null) throw StateError('Notification cleanup will retry');
    if (_initialized) {
      await _save({...identity, 'cleanup': false, 'user': null});
    }
  }

  @override
  Future<void> show(BookingNotification notification) async {
    if (_auth.currentUser?.id != notification.userId) return;
    await _local.show(
      id: notification.eventId.hashCode & 0x7fffffff,
      title: notification.title ?? 'Booking updated',
      body: notification.body ?? 'Open Booking OS for details.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Booking orders',
          channelDescription: 'Placed, cancelled and rescheduled bookings',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_booking',
          playSound: true,
          sound: _sound,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(notification.toData()),
    );
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _tokens.close();
    await _foreground.close();
    await _opened.close();
  }
}

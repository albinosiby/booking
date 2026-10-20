import 'package:flutter/foundation.dart';

class AppConfig {
  static const authProvider = String.fromEnvironment(
    'AUTH_PROVIDER',
    defaultValue: 'supabase',
  );
  static bool get useSupabase => authProvider == 'supabase';
  static bool get requireEmailVerification => useSupabase || !useAuthEmulator;
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://scwwkaywewecspsrskft.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_d6iVFApYyh41BlF9GkTsgw_h0d-chZN',
  );
  static const authRedirectUrl = 'com.bookingos.app://auth-callback/';
  static const useAuthEmulator = bool.fromEnvironment(
    'USE_AUTH_EMULATOR',
    defaultValue: true,
  );
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue:
        'https://scwwkaywewecspsrskft.supabase.co/functions/v1/booking-api/v1',
  );
  static const emulatorHost = String.fromEnvironment(
    'AUTH_EMULATOR_HOST',
    defaultValue: 'localhost',
  );
  static const firebaseProject = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'demo-eden-booking',
  );
  static const firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'demo-key',
  );
  static const firebaseAppId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:123456789:web:edenbooking',
  );
  static const senderId = String.fromEnvironment(
    'FIREBASE_SENDER_ID',
    defaultValue: '123456789',
  );
  static void validate() {
    if (!['firebase', 'supabase'].contains(authProvider)) {
      throw StateError('Unsupported authentication provider.');
    }
    if (useSupabase &&
        (!supabaseUrl.startsWith('https://') ||
            !supabasePublishableKey.startsWith('sb_publishable_'))) {
      throw StateError('Configure Supabase URL and publishable key.');
    }
    if (kReleaseMode &&
        (!apiUrl.startsWith('https://') ||
            (!useSupabase &&
                (useAuthEmulator || firebaseProject.startsWith('demo-'))))) {
      throw StateError(
        'Configure cloud authentication and an HTTPS API before a release build.',
      );
    }
  }
}

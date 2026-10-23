import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:eden_booking/modules/auth/repositories/supabase_auth_repository.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

void main() {
  late sb.SupabaseClient client;
  tearDown(() async => client.dispose());
  test(
    'Google launch uses PKCE, the registered callback and account selection',
    () async {
      final storage = MemoryPkceStorage();
      client = sb.SupabaseClient(
        'https://project.supabase.co',
        'sb_publishable_test',
        authOptions: sb.AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: sb.AuthFlowType.pkce,
          pkceAsyncStorage: storage,
        ),
        httpClient: MockClient(
          (_) async => throw StateError(
            'OAuth launch must not send credentials to the API',
          ),
        ),
      );
      Uri? launched;
      final repository = SupabaseAuthRepository(
        client.auth,
        launchOAuth: (url) async {
          launched = url;
          return true;
        },
      );
      await repository.signInWithGoogle();
      expect(launched!.host, 'project.supabase.co');
      expect(launched!.path, '/auth/v1/authorize');
      expect(launched!.queryParameters['provider'], 'google');
      expect(
        launched!.queryParameters['redirect_to'],
        'bookingservice.tatos.tech://auth-callback/',
      );
      expect(launched!.queryParameters['prompt'], 'select_account');
      expect(launched!.queryParameters['code_challenge_method'], 's256');
      expect(launched!.queryParameters['code_challenge'], isNotEmpty);
      expect(launched!.queryParameters.containsKey('invite'), isFalse);
      expect(storage.values, isNotEmpty);
      expect(
        repository.currentUser,
        isNull,
        reason: 'Opening a browser must not authenticate anyone',
      );
    },
  );
  test('failed browser launch provides a retryable error', () async {
    client = sb.SupabaseClient(
      'https://project.supabase.co',
      'sb_publishable_test',
      authOptions: sb.AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: MemoryPkceStorage(),
      ),
    );
    final repository = SupabaseAuthRepository(
      client.auth,
      launchOAuth: (_) async => false,
    );
    await expectLater(
      repository.signInWithGoogle(),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          'GOOGLE_LAUNCH_FAILED',
        ),
      ),
    );
    expect(repository.currentUser, isNull);
  });
  test(
    'Google callbacks keep the web mount without forwarding private query data',
    () {
      client = sb.SupabaseClient(
        'https://project.supabase.co',
        'sb_publishable_test',
        authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
      );
      for (final route in ['sign-in', 'register']) {
        expect(
          googleOAuthRedirect(
            isWeb: true,
            webUri: Uri.parse(
              'https://bookingos.online/app/$route?invite=private&from=%2Fprofile#secret',
            ),
          ),
          'https://bookingos.online/app/auth-callback',
        );
        expect(
          googleOAuthRedirect(
            isWeb: true,
            webUri: Uri.parse('https://app.bookingos.online/$route'),
          ),
          'https://app.bookingos.online/auth-callback',
        );
      }
    },
  );
  test(
    'email-confirmation signup stays signed out with a useful next step',
    () async {
      client = sb.SupabaseClient(
        'https://project.supabase.co',
        'sb_publishable_test',
        authOptions: sb.AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: MemoryPkceStorage(),
        ),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/signup');
          final body = jsonDecode(request.body) as Map;
          expect(body['email'], 'owner@example.com');
          expect(body['data']['full_name'], 'Owner');
          return http.Response(
            jsonEncode({
              'id': '00000000-0000-4000-8000-000000000001',
              'email': 'owner@example.com',
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'x-supabase-api-version': '2024-01-01',
            },
          );
        }),
      );
      final repository = SupabaseAuthRepository(client.auth);
      await expectLater(
        repository.register(
          ' Owner ',
          ' owner@example.com ',
          'private-test-password',
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            'EMAIL_CONFIRMATION_REQUIRED',
          ),
        ),
      );
      expect(repository.currentUser, isNull);
      expect(await repository.token(), isNull);
    },
  );
  test(
    'invalid credentials map to a specific message without backend details',
    () async {
      client = sb.SupabaseClient(
        'https://project.supabase.co',
        'sb_publishable_test',
        authOptions: sb.AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: MemoryPkceStorage(),
        ),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'code': 'invalid_credentials',
              'msg': 'Invalid login credentials',
            }),
            400,
            headers: {
              'content-type': 'application/json',
              'x-supabase-api-version': '2024-01-01',
            },
          ),
        ),
      );
      await expectLater(
        SupabaseAuthRepository(
          client.auth,
        ).signIn('owner@example.com', 'wrong'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            'Email or password is incorrect.',
          ),
        ),
      );
    },
  );
}

class MemoryPkceStorage extends sb.GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

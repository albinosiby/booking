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

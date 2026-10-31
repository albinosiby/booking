import 'dart:async';
import 'dart:convert';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'retained_read_cache.dart';
import 'package:dio/dio.dart';
import '../../config/app_config.dart';
import '../../modules/auth/repositories/auth_repository_interface.dart';
import '../exceptions/app_exception.dart';

class RestApiService {
  RestApiService(this.auth, {this.readCache, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiUrl,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
            ),
          ) {
    _httpStore = MemCacheStore(maxSize: 1024 * 1024, maxEntrySize: 128 * 1024);
    _dio.interceptors.add(
      DioCacheInterceptor(
        options: CacheOptions(
          store: _httpStore,
          // Explicit repository snapshots implement app retention. HTTP caching
          // still honors server no-store and never falls back on authentication errors.
          policy: CachePolicy.request,
          keyBuilder: ({required url, headers, body}) =>
              '${auth.currentUser?.id ?? 'public'}:${CacheOptions.defaultCacheKeyBuilder(url: url)}',
          hitCacheOnNetworkFailure: false,
          maxStale: const Duration(hours: 1),
        ),
      ),
    );
    var user = auth.currentUser?.id;
    _authChanges = auth.changes.listen(
      (next) {
        if (next?.id != user) {
          user = next?.id;
          _requestEpoch++;
          _readsInFlight.clear();
          readCache?.lock();
          unawaited(_httpStore.clean());
        }
      },
      onError: (Object error, StackTrace stack) {
        // AuthCubit presents session-refresh errors. Keep valid page state while
        // connectivity recovers instead of leaking a second unhandled stream error.
      },
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final target = options.uri;
            if (AppConfig.useSupabase &&
                target.host == Uri.parse(AppConfig.supabaseUrl).host &&
                target.path.startsWith('/functions/v1/')) {
              options.headers['apikey'] = AppConfig.supabasePublishableKey;
              if (AppConfig.functionRegion.isNotEmpty) {
                options.headers['x-region'] = AppConfig.functionRegion;
              }
            }
            final token = await auth.token();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
            handler.next(options);
          } catch (e) {
            handler.reject(
              DioException(
                requestOptions: options,
                error: const AppException(
                  'Your session could not be refreshed. Sign in again.',
                ),
              ),
            );
          }
        },
      ),
    );
  }
  final Dio _dio;
  Future<void> Function()? recoverAccess;
  Future<void>? _accessRecovery;
  Future<void> _reconcileAccess() async {
    final recover = recoverAccess;
    if (recover == null) return;
    final pending = _accessRecovery ??= recover();
    try {
      await pending;
    } catch (_) {
      // Preserve the original typed access failure if the refresh is offline.
    } finally {
      if (identical(_accessRecovery, pending)) _accessRecovery = null;
    }
  }

  final _readsInFlight = <String, Future<dynamic>>{};
  int _requestEpoch = 0;
  final AuthRepository auth;
  final RetainedReadCache? readCache;
  late final MemCacheStore _httpStore;
  late final StreamSubscription _authChanges;
  Stream<String> get readUpdates => readCache?.updates ?? const Stream.empty();

  Future<void> authorizeReads(Map<String, dynamic> workspace) async {
    Object? canonical(Object? value) {
      if (value is Map) {
        final keys = value.keys.map((k) => k.toString()).toList()..sort();
        return {for (final key in keys) key: canonical(value[key])};
      }
      if (value is List) return value.map(canonical).toList();
      return value;
    }

    await readCache?.authorize(
      jsonEncode(
        canonical({
          'backend': AppConfig.apiUrl,
          'user': auth.currentUser?.id,
          'organization': workspace['organization']?['id'],
          'membership': workspace['membership'],
          'businesses': {
            for (final business in workspace['businesses'] as List? ?? [])
              business['id']: {
                'status': business['status'],
                'resources':
                    (business['resources'] as List? ?? [])
                        .map((r) => r['id'].toString())
                        .toList()
                      ..sort(),
              },
          },
        }),
      ),
    );
  }

  Future<dynamic> retainedRead(
    String path, {
    Duration freshFor = const Duration(seconds: 20),
    Duration retainFor = const Duration(minutes: 15),
  }) =>
      readCache?.read(
        path,
        () => request(path),
        freshFor: freshFor,
        retainFor: retainFor,
      ) ??
      request(path);

  Future<List<int>> retainedBytes(String path) async {
    final value =
        await (readCache?.read(
              path,
              () => bytes(path),
              freshFor: const Duration(hours: 1),
              retainFor: const Duration(days: 1),
            ) ??
            bytes(path));
    return List<int>.from(value as List);
  }

  void revalidateReads() => readCache?.revalidate();

  void invalidateReads({bool notify = true, bool preserveSetup = false}) {
    _requestEpoch++;
    _readsInFlight.clear();
    readCache?.invalidate(
      notify: notify,
      keep: preserveSetup
          ? (key) {
              final path = Uri.parse(key).path;
              return path == '/catalog' ||
                  path.startsWith('/catalog/states/') ||
                  path == '/bookings/catalog' ||
                  path == '/admissions/catalog' ||
                  path == '/organization/logo';
            }
          : null,
    );
    unawaited(_httpStore.clean());
  }

  Future<void> dispose() async {
    _readsInFlight.clear();
    await _authChanges.cancel();
    await _httpStore.close();
    await readCache?.dispose();
    _dio.close();
  }

  /// Share concurrent identical GETs only. Results are not retained here;
  /// freshness and persistence remain explicit repository snapshot policies.
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool readOnly = false,
  }) async {
    if (method != 'GET' || data != null) {
      return _request(path, method: method, data: data, readOnly: readOnly);
    }
    final key = jsonEncode([auth.currentUser?.id, _requestEpoch, path]);
    final pending = _readsInFlight.putIfAbsent(key, () => _request(path));
    try {
      final value = await pending;
      // Each repository receives an isolated JSON object.
      return value is Map || value is List
          ? jsonDecode(jsonEncode(value))
          : value;
    } finally {
      if (identical(_readsInFlight[key], pending)) _readsInFlight.remove(key);
    }
  }

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Object? data,
    bool readOnly = false,
  }) async {
    final requestUser = auth.currentUser?.id;
    final write = method != 'GET' && !readOnly;
    final endpoint = Uri.parse(path).path;
    final preserveSetup =
        RegExp(
          r'^/(bookings|booking-blocks|admissions|expenses)(/|$)',
        ).hasMatch(endpoint) ||
        endpoint == '/accounts/entries';
    if (write) invalidateReads(notify: false, preserveSetup: preserveSetup);
    try {
      final emptyJson =
          data == null &&
          const ['POST', 'PATCH', 'PUT'].contains(method.toUpperCase());
      final response = await _dio.request<dynamic>(
        path,
        data: emptyJson ? const <String, Object?>{} : data,
        options: Options(
          method: method,
          contentType: emptyJson ? Headers.jsonContentType : null,
          receiveTimeout:
              write &&
                  (endpoint == '/team' ||
                      RegExp(
                        r'^/invitations/[^/]+/(email|access)$',
                      ).hasMatch(endpoint))
              ? const Duration(seconds: 45)
              : null,
        ),
      );
      if (requestUser != auth.currentUser?.id) {
        throw const AppException(
          'Your account changed. Reopen this page.',
          code: 'CANCELLED',
        );
      }
      if (write) invalidateReads(preserveSetup: preserveSetup);
      return response.data;
    } on DioException catch (e) {
      if (requestUser != auth.currentUser?.id) {
        throw const AppException(
          'Your account changed. Reopen this page.',
          code: 'CANCELLED',
        );
      }
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        final denied = AppException(
          'Your access has changed.',
          code: e.response?.statusCode == 401 ? 'UNAUTHENTICATED' : 'FORBIDDEN',
        );
        readCache?.lock(error: denied);
        unawaited(_httpStore.clean());
        if (!endpoint.startsWith('/workspace')) await _reconcileAccess();
        throw denied;
      }
      if (e.error is AppException) throw e.error!;
      final body = e.response?.data;
      if (body is Map) {
        throw AppException(
          body['message']?.toString() ?? 'Request failed.',
          code: body['code']?.toString() ?? 'REQUEST_ERROR',
        );
      }
      throw const AppException(
        'Cannot reach the server. Check your connection and try again.',
        code: 'NETWORK',
      );
    }
  }

  Future<List<int>> bytes(
    String path, {
    String errorMessage = 'Could not load the organization logo.',
  }) async {
    final requestUser = auth.currentUser?.id;
    try {
      final response = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      if (requestUser != auth.currentUser?.id) {
        throw const AppException(
          'Your account changed. Reopen this page.',
          code: 'CANCELLED',
        );
      }
      return response.data ?? const <int>[];
    } on DioException catch (e) {
      if (requestUser != auth.currentUser?.id) {
        throw const AppException(
          'Your account changed. Reopen this page.',
          code: 'CANCELLED',
        );
      }
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        final denied = AppException(
          'Your access has changed.',
          code: e.response?.statusCode == 401 ? 'UNAUTHENTICATED' : 'FORBIDDEN',
        );
        readCache?.lock(error: denied);
        unawaited(_httpStore.clean());
        await _reconcileAccess();
        throw denied;
      }
      try {
        final data = e.response?.data;
        final body = data is List<int> ? jsonDecode(utf8.decode(data)) : data;
        if (body is Map) {
          throw AppException(
            body['message']?.toString() ?? errorMessage,
            code: body['code']?.toString() ?? 'REQUEST_ERROR',
          );
        }
      } on AppException {
        rethrow;
      } catch (_) {}
      throw AppException(errorMessage);
    }
  }
}

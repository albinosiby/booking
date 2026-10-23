import '../modules/notifications/cubit/notification_cubit.dart';
import '../modules/notifications/repositories/notification_repository.dart';
import '../modules/notifications/repositories/firebase_notification_repository.dart';
import '../modules/workspace/repositories/workspace_preloader.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../modules/auth/repositories/supabase_auth_repository.dart';
import '../modules/auth/repositories/auth_continuation_repository.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/settings/application_setting.dart';
import '../modules/auth/cubit/auth_cubit.dart';
import '../modules/auth/repositories/auth_repository_interface.dart';
import '../modules/auth/repositories/firebase_auth_repository.dart';
import '../modules/workspace/cubit/workspace_cubit.dart';
import '../modules/workspace/repositories/workspace_repository_interface.dart';
import '../modules/workspace/repositories/rest_workspace_repository.dart';
import '../utils/services/rest_api_service.dart';
import '../utils/services/logo_picker_service.dart';

import 'feature_injection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/services/retained_read_cache.dart';

final getIt = GetIt.instance;
Future<void> configureDependencies() async {
  getIt.registerSingleton<SharedPreferences>(
    await SharedPreferences.getInstance(),
  );
  getIt.registerLazySingleton<AuthRepository>(
    () => AppConfig.useSupabase
        ? SupabaseAuthRepository(Supabase.instance.client.auth)
        : FirebaseAuthRepository(
            FirebaseAuth.instanceFor(app: Firebase.app('booking-auth')),
          ),
  );
  getIt.registerLazySingleton<RestApiService>(
    () => RestApiService(
      getIt(),
      readCache: RetainedReadCache(
        store: const SecureReadSnapshotStore(FlutterSecureStorage()),
        identity: () => getIt<AuthRepository>().currentUser?.id,
      ),
    ),
  );
  getIt.registerLazySingleton<WorkspaceRepository>(
    () => RestWorkspaceRepository(getIt()),
  );
  registerFeatureDependencies(getIt);
  getIt.registerLazySingleton<LogoPickerService>(() => LogoPickerService());
  getIt.registerLazySingleton<AuthContinuationRepository>(
    () => SecureAuthContinuationRepository(AppConfig.supabaseUrl),
  );
  getIt.registerLazySingleton<NotificationRepository>(
    () => FirebaseNotificationRepository(getIt(), getIt()),
  );
  getIt.registerLazySingleton<NotificationCubit>(
    () => NotificationCubit(getIt(), getIt()),
  );
  getIt.registerFactory<AuthCubit>(
    () => AuthCubit(
      getIt(),
      beforeSignOut: () => getIt<NotificationCubit>().signOut(),
      continuations: AppConfig.useSupabase
          ? getIt<AuthContinuationRepository>()
          : null,
    ),
  );
  getIt.registerLazySingleton<WorkspacePreloader>(
    () => WorkspacePreloader(
      getIt(),
      getIt(),
      getIt(),
      getIt(),
      admissions: getIt(),
    ),
  );
  getIt.registerFactory<WorkspaceCubit>(
    () => WorkspaceCubit(getIt(), preloader: getIt()),
  );
  getIt.registerFactory<SettingsCubit>(() => SettingsCubit(getIt()));
}

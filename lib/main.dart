import 'modules/notifications/cubit/notification_cubit.dart';
import 'modules/notifications/models/notification_state.dart';
import 'modules/team/cubit/invitation_link_cubit.dart';
import 'modules/team/models/invitation_link.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'utils/services/supabase_session_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'config/app_config.dart';
import 'config/routes/routes_config.dart';
import 'core/settings/application_setting.dart';
import 'di/injection.dart';
import 'modules/auth/cubit/auth_cubit.dart';
import 'modules/workspace/cubit/workspace_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  try {
    AppConfig.validate();
    if (AppConfig.useSupabase) {
      await sb.Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
        authOptions: sb.FlutterAuthClientOptions(
          localStorage: SupabaseSessionStorage(AppConfig.supabaseUrl),
        ),
      );
    } else {
      final authApp = await Firebase.initializeApp(
        name: 'booking-auth',
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.senderId,
          projectId: AppConfig.firebaseProject,
        ),
      );
      if (AppConfig.useAuthEmulator) {
        await FirebaseAuth.instanceFor(app: authApp).useAuthEmulator(
          AppConfig.emulatorHost,
          9099,
          automaticHostMapping: false,
        );
      }
    }
    await configureDependencies();
    runApp(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => getIt<AuthCubit>(), lazy: false),
          BlocProvider(create: (_) => getIt<WorkspaceCubit>()),
          BlocProvider(create: (_) => getIt<SettingsCubit>()),
        ],
        child: const BookingApp(),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Unable to initialize Booking OS. Check authentication and API configuration, then restart the app.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BookingApp extends StatefulWidget {
  const BookingApp({super.key});
  @override
  State<BookingApp> createState() => _BookingAppState();
}

class _BookingAppState extends State<BookingApp> with WidgetsBindingObserver {
  late final AuthCubit auth = context.read<AuthCubit>();
  late final WorkspaceCubit workspace = context.read<WorkspaceCubit>();
  late final RouterRefresh refresh = RouterRefresh([
    auth.stream,
    workspace.stream,
  ]);
  late final GoRouter router = createRouter(auth, workspace, refresh);
  StreamSubscription<AuthState>? subscription;
  InvitationLinkCubit? invitationLinks;
  StreamSubscription<InvitationLink?>? invitationSubscription;
  late final NotificationCubit notifications = getIt<NotificationCubit>();
  StreamSubscription<NotificationState>? notificationSubscription;
  StreamSubscription<WorkspaceState>? notificationWorkspaceSubscription;
  String? loadedUser;
  DateTime? lastResume;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    subscription = auth.stream.listen(sync);
    sync(auth.state);
    notificationSubscription = notifications.stream.listen(
      (_) => openNotification(),
    );
    notificationWorkspaceSubscription = workspace.stream.listen(
      (_) => openNotification(),
    );
    unawaited(notifications.start());
    if (!kIsWeb) {
      invitationLinks = getIt<InvitationLinkCubit>();
      invitationSubscription = invitationLinks!.stream.listen((link) {
        if (link != null && mounted) {
          if (link.isSignIn && auth.state.status == AuthStatus.signedIn) {
            unawaited(
              workspace.load().then((_) {
                if (mounted) router.go('/home');
              }),
            );
          } else {
            router.go(link.route);
          }
        }
      });
      unawaited(invitationLinks!.start());
    }
  }

  void openNotification() {
    final pending = notifications.state.pending;
    if (pending == null ||
        !mounted ||
        auth.state.busy ||
        workspace.state.busy ||
        workspace.state.status != LoadStatus.ready ||
        workspace.state.data.organization == null ||
        auth.state.status != AuthStatus.signedIn) {
      return;
    }
    notifications.consume();
    if (auth.state.user?.id != pending.userId ||
        auth.state.user?.passwordRecovery == true ||
        !workspace.state.data.hasPermission('manage_bookings')) {
      return;
    }
    // BookingDetail's repository fetch enforces current organization/resource access.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && auth.state.user?.id == pending.userId) {
        router.go('/booking/${pending.bookingId}');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) notifications.resumed();
    if (state != AppLifecycleState.resumed ||
        loadedUser == null ||
        workspace.state.busy) {
      return;
    }
    final now = DateTime.now();
    if (lastResume != null &&
        now.difference(lastResume!) < const Duration(seconds: 30)) {
      return;
    }
    lastResume = now;
    // Re-check permission changes from another device without replacing pages.
    unawaited(
      workspace.load().then((_) => workspace.revalidateRetainedPages()),
    );
  }

  void sync(AuthState s) {
    if (s.busy) return;
    if (s.status == AuthStatus.signedOut) {
      loadedUser = null;
      workspace.clear();
    } else if (s.status == AuthStatus.signedIn &&
        (!AppConfig.requireEmailVerification || s.user!.verified) &&
        !s.user!.passwordRecovery &&
        loadedUser != s.user!.id) {
      if (loadedUser != null) workspace.clear();
      loadedUser = s.user!.id;
      workspace.load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notificationSubscription?.cancel();
    notificationWorkspaceSubscription?.cancel();
    unawaited(notifications.close());
    invitationSubscription?.cancel();
    invitationLinks?.close();
    subscription?.cancel();
    router.dispose();
    refresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => app(
      // Phone layouts scale from the 390pt design; wide web windows render 1:1.
      constraints.maxWidth < 600
          ? const Size(390, 844)
          : Size(constraints.maxWidth, constraints.maxHeight),
    ),
  );

  Widget app(Size designSize) => ScreenUtilInit(
    designSize: designSize,
    minTextAdapt: true,
    splitScreenMode: true,
    builder: (context, child) => BlocBuilder<SettingsCubit, ThemeMode>(
      builder: (context, mode) => MaterialApp.router(
        title: 'Booking OS',
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        darkTheme: darkTheme(),
        themeMode: mode,
        routerConfig: router,
        scrollBehavior: const AppScrollBehavior(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: !AppConfig.useSupabase && AppConfig.useAuthEmulator && kIsWeb
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 64),
                  child: child,
                )
              : child!,
        ),
      ),
    ),
  );
}

/// Lets mouse and trackpad drags scroll lists on web and desktop, such as the
/// calendar date strip, in addition to touch.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

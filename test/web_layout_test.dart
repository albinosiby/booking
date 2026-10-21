import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/core/settings/application_setting.dart';
import 'package:eden_booking/modules/auth/cubit/auth_cubit.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_repository.dart';
import 'package:eden_booking/modules/bookings/screens/booking_form_screen.dart';
import 'package:eden_booking/modules/profile/screens/profile_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;
import 'business_management_test.dart' show ManagementSource, ProfileAuth;

Future<void> pumpPage(
  WidgetTester tester,
  Widget Function(Widget app) wrap,
  Widget page, {
  Size size = const Size(1180, 1100),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (c, s) => page)],
  );
  await tester.pumpWidget(
    wrap(
      ScreenUtilInit(
        designSize: size,
        builder: (c, _) {
          final theme = AppTheme.build(Brightness.dark);
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: theme,
            routerConfig: router,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() async {
    await getIt.reset();
  });
  testWidgets('new booking puts payment and summary beside the form', (
    tester,
  ) async {
    final source = BookingSource();
    getIt.registerSingleton<WorkspaceRepository>(source);
    registerFeatureDependencies(getIt);
    await getIt.unregister<BookingRepository>();
    getIt.registerSingleton<BookingRepository>(
      FakeBookingRepository(flexible: true),
    );
    final w = WorkspaceCubit(source);
    await w.load();
    await pumpPage(
      tester,
      (app) => BlocProvider.value(value: w, child: app),
      const BookingFormScreen(),
      size: const Size(1440, 1300),
    );
    expect(find.byKey(const ValueKey('booking-summary-card')), findsOneWidget);
    expect(find.text('New booking'), findsOneWidget);
    await w.close();
  });
  testWidgets('profile shows destination tiles on desktop', (tester) async {
    final source = ManagementSource()..owner = true;
    getIt.registerSingleton<WorkspaceRepository>(source);
    registerFeatureDependencies(getIt);
    final w = WorkspaceCubit(source);
    await w.load();
    addTearDown(w.close);
    final auth = AuthCubit(ProfileAuth());
    addTearDown(auth.close);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsCubit(await SharedPreferences.getInstance());
    addTearDown(settings.close);
    await pumpPage(
      tester,
      (app) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: w),
          BlocProvider.value(value: auth),
          BlocProvider.value(value: settings),
        ],
        child: app,
      ),
      const ProfileScreen(),
    );
    expect(find.text('Workspace management'), findsOneWidget);
    expect(find.text('Team & access'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });
}

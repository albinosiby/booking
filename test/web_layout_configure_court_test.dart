import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/court/repositories/court_repository.dart';
import 'package:eden_booking/modules/court/screens/court_setup_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'court_setup_test.dart' show CourtSource, FakeCourtRepository;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => getIt.reset());
  testWidgets('court configure page uses the desktop workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = CourtSource();
    getIt.registerSingleton<WorkspaceRepository>(source);
    registerFeatureDependencies(getIt);
    await getIt.unregister<CourtRepository>();
    getIt.registerSingleton<CourtRepository>(FakeCourtRepository(source));
    final workspace = WorkspaceCubit(source);
    await workspace.load();
    addTearDown(workspace.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: workspace,
        child: ScreenUtilInit(
          designSize: const Size(1440, 1000),
          builder: (context, child) => MaterialApp(
            theme: darkTheme(),
            home: const CourtSetupScreen(businessId: 'courts'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('configuration-workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('configuration-actions')), findsOneWidget);
    expect(find.text('Court settings'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('court-nav-pricing')));
    await tester.pumpAndSettle();
    expect(find.text('Timing & pricing'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('court-nav-overview')));
    await tester.pumpAndSettle();
    expect(find.text('Court settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

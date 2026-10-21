import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/hall/repositories/hall_repository.dart';
import 'package:eden_booking/modules/hall/screens/hall_setup_screen.dart';
import 'package:eden_booking/modules/pool/repositories/pool_repository.dart';
import 'package:eden_booking/modules/pool/screens/pool_setup_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'hall_setup_test.dart' show HallSource, FakeHallRepository;
import 'pool_setup_test.dart' show PoolSource, FakePoolRepository;

Future<void> pumpSetup(
  WidgetTester tester,
  WorkspaceRepository source,
  Widget home, {
  Size size = const Size(1440, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final workspace = WorkspaceCubit(source);
  await workspace.load();
  addTearDown(workspace.close);
  await tester.pumpWidget(
    BlocProvider.value(
      value: workspace,
      child: ScreenUtilInit(
        designSize: size,
        builder: (context, child) =>
            MaterialApp(theme: darkTheme(), home: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> registerPool(PoolSource source) async {
  getIt.registerSingleton<WorkspaceRepository>(source);
  registerFeatureDependencies(getIt);
  await getIt.unregister<PoolRepository>();
  getIt.registerSingleton<PoolRepository>(FakePoolRepository(source));
}

Future<void> registerHall(HallSource source) async {
  getIt.registerSingleton<WorkspaceRepository>(source);
  registerFeatureDependencies(getIt);
  await getIt.unregister<HallRepository>();
  getIt.registerSingleton<HallRepository>(FakeHallRepository(source));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => getIt.reset());
  const workspaceKey = ValueKey('configuration-workspace');

  testWidgets('pool configure page uses the desktop workspace', (tester) async {
    final source = PoolSource();
    await registerPool(source);
    await pumpSetup(
      tester,
      source,
      const PoolSetupScreen(businessId: 'swimming'),
    );
    expect(find.byKey(workspaceKey), findsOneWidget);
    expect(find.byKey(const ValueKey('configuration-actions')), findsOneWidget);
    expect(find.text('Pool settings'), findsOneWidget);
    for (final name in [
      'overview',
      'pools',
      'pricing',
      'groups',
      'coaching',
      'plans',
      'review',
    ]) {
      expect(find.byKey(ValueKey('pool-nav-$name')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('pool-nav-groups')));
    await tester.pumpAndSettle();
    expect(find.text('Group offers'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('pool-nav-review')));
    await tester.pumpAndSettle();
    expect(find.text('Review your pools'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('pool-nav-overview')));
    await tester.pumpAndSettle();
    expect(find.text('Pool settings'), findsOneWidget);

    // The step-by-step add flow locks the rail until the pool is complete.
    await tester.tap(find.text('Add pool'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 1 OF 2 · DETAILS'), findsOneWidget);
    expect(
      tester
          .widget<InkWell>(find.byKey(const ValueKey('pool-nav-review')))
          .onTap,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pool configure page keeps the phone layout', (tester) async {
    final source = PoolSource();
    await registerPool(source);
    await pumpSetup(
      tester,
      source,
      const PoolSetupScreen(businessId: 'swimming'),
      size: const Size(390, 844),
    );
    expect(find.byKey(workspaceKey), findsNothing);
    expect(find.byKey(const ValueKey('pool-section-pools')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hall configure page uses the desktop workspace', (tester) async {
    final source = HallSource();
    await registerHall(source);
    await pumpSetup(tester, source, const HallSetupScreen(businessId: 'halls'));
    expect(find.byKey(workspaceKey), findsOneWidget);
    expect(find.byKey(const ValueKey('configuration-actions')), findsOneWidget);
    expect(find.text('Hall settings'), findsOneWidget);
    for (final name in ['overview', 'halls', 'pricing', 'review']) {
      expect(find.byKey(ValueKey('hall-nav-$name')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('hall-nav-pricing')));
    await tester.pumpAndSettle();
    expect(find.text('Booking options & pricing'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('hall-nav-halls')));
    await tester.pumpAndSettle();
    expect(find.text('Your halls'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('hall-nav-overview')));
    await tester.pumpAndSettle();
    expect(find.text('Hall settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hall configure page keeps the phone layout', (tester) async {
    final source = HallSource();
    await registerHall(source);
    await pumpSetup(
      tester,
      source,
      const HallSetupScreen(businessId: 'halls'),
      size: const Size(390, 844),
    );
    expect(find.byKey(workspaceKey), findsNothing);
    expect(find.byKey(const ValueKey('hall-section-halls')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

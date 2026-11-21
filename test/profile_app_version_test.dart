import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eden_booking/core/settings/application_setting.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/auth/cubit/auth_cubit.dart';
import 'package:eden_booking/modules/businesses/repositories/business_repository.dart';
import 'package:eden_booking/modules/organization/repositories/organization_repository.dart';
import 'package:eden_booking/modules/profile/cubit/profile_cubit.dart';
import 'package:eden_booking/modules/profile/repositories/profile_repository.dart';
import 'package:eden_booking/modules/profile/screens/profile_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'business_management_test.dart' show ProfileAuth;
import 'organization_details_test.dart'
    show DetailsRepository, DetailsSource, fixture;

class OrganizationStub extends Fake implements OrganizationRepository {}

class BusinessStub extends Fake implements BusinessRepository {}

class VersionRepository extends DetailsRepository {
  Future<String> Function() read = () async => '2.7.1 (build 64)';
  @override
  Future<String> appVersion() => read();
}

void platformVersion({String version = '2.7.1', String build = '64'}) =>
    PackageInfo.setMockInitialValues(
      appName: 'Booking OS',
      packageName: 'bookingservice.tatos.tech',
      version: version,
      buildNumber: build,
      buildSignature: '',
    );

void main() {
  tearDown(getIt.reset);

  test(
    'reads runtime version/build instead of the source pubspec defaults',
    () async {
      platformVersion();
      final repo = OrganizationProfileRepository(
        OrganizationStub(),
        BusinessStub(),
      );
      expect(await repo.appVersion(), '2.7.1 (build 64)');
      platformVersion(version: '2.7.2', build: '');
      expect(await repo.appVersion(), '2.7.2');
    },
  );

  test(
    'a metadata response preserves workspace changes and survives later refreshes',
    () async {
      final source = DetailsSource(),
          repo = VersionRepository(),
          version = Completer<String>();
      repo.read = () => version.future;
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final cubit = ProfileCubit(workspace, repo);
      final pending = cubit.loadAppVersion();
      expect(cubit.state.appVersionLoading, isTrue);
      source.value = fixture(owner: false);
      await workspace.load();
      await Future<void>.delayed(Duration.zero);
      version.complete('2.7.1 (build 64)');
      await pending;
      expect(cubit.state.roleLabel, 'Staff');
      expect(cubit.state.appVersion, '2.7.1 (build 64)');
      await workspace.load();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.appVersion, '2.7.1 (build 64)');
      await cubit.close();
      await workspace.close();
    },
  );

  test('metadata errors do not block Profile, and retry can recover', () async {
    final repo = VersionRepository()
      ..read = () => Future.error(StateError('Metadata unavailable'));
    final workspace = WorkspaceCubit(DetailsSource());
    await workspace.load();
    final cubit = ProfileCubit(workspace, repo);
    await cubit.loadAppVersion();
    expect(cubit.state.appVersion, isNull);
    expect(cubit.state.appVersionLoading, isFalse);
    expect(cubit.state.error, isNull);
    expect(cubit.state.data.organization, isNotNull);
    repo.read = () async => '2.7.1 (build 64)';
    await cubit.loadAppVersion();
    expect(cubit.state.appVersion, '2.7.1 (build 64)');
    await cubit.close();
    await workspace.close();
  });

  for (final size in [const Size(320, 1000), const Size(1280, 1000)]) {
    testWidgets(
      'Profile shows installed version under Preferences at ${size.width}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        platformVersion();
        SharedPreferences.setMockInitialValues({});
        final workspace = WorkspaceCubit(DetailsSource());
        await workspace.load();
        addTearDown(workspace.close);
        final auth = AuthCubit(ProfileAuth());
        addTearDown(auth.close);
        final settings = SettingsCubit(await SharedPreferences.getInstance());
        addTearDown(settings.close);
        final repo = OrganizationProfileRepository(
          OrganizationStub(),
          BusinessStub(),
        );
        getIt.registerFactoryParam<ProfileCubit, WorkspaceSession, void>(
          (session, _) => ProfileCubit(session, repo),
        );
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider.value(value: workspace),
              BlocProvider.value(value: auth),
              BlocProvider.value(value: settings),
            ],
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp(
                theme: darkTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(size.width < 600 ? 1.5 : 1),
                  ),
                  child: child!,
                ),
                home: const ProfileScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('App version'));
        await tester.pumpAndSettle();
        final row = find.widgetWithText(ListTile, 'App version');
        expect(
          find.descendant(of: row, matching: find.text('2.7.1 (build 64)')),
          findsOneWidget,
        );
        expect(find.text('Loading version…'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

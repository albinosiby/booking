import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/businesses/cubit/businesses_cubit.dart';
import 'package:eden_booking/modules/businesses/repositories/business_repository.dart';
import 'package:eden_booking/modules/businesses/screens/businesses_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

class SelectionSource extends Fake implements WorkspaceRepository {
  final businesses = <Business>[];
  final attempts = <String>[];
  bool failPool = false;
  bool losePoolResponse = false;
  @override
  Future<Workspace> load() async => Workspace(
    organization: const Organization(
      id: 'o',
      name: 'Eden',
      phone: '12345678',
      currency: 'INR',
    ),
    membership: const {'role': 'owner'},
    locations: const [
      {'id': 'location'},
    ],
    businesses: List.unmodifiable(businesses),
  );
  @override
  Future<void> addBusiness(Map<String, dynamic> data) async {
    attempts.add(data['type']);
    if (data['type'] == 'pool' && failPool) {
      throw AppException('Pool save failed.', code: 'NETWORK');
    }
    businesses.add(
      Business(
        id: '${businesses.length}',
        name: data['name'],
        type: BusinessType.fromCode(data['type']),
        status: 'draft',
        locationId: data['location_id'],
        version: 1,
        resources: const [],
      ),
    );
    if (data['type'] == 'pool' && losePoolResponse) {
      throw AppException('Response lost.', code: 'NETWORK');
    }
  }
}

void main() {
  tearDown(() async {
    await getIt.reset();
  });
  test(
    'multi-select saves all chosen services and clears acknowledged selections',
    () async {
      final source = SelectionSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final cubit = BusinessesCubit(
        workspace,
        LocalApiBusinessRepository(source),
      );
      cubit.toggleService(BusinessType.turf);
      cubit.toggleService(BusinessType.pool);
      cubit.nameService(BusinessType.turf, 'Eden Football');
      expect(await cubit.addSelected(), true);
      await Future<void>.delayed(Duration.zero);
      expect(source.attempts, ['turf', 'pool']);
      expect(source.businesses.map((b) => b.name), [
        'Eden Football',
        'Eden Swimming Pool',
      ]);
      expect(cubit.state.selected, isEmpty);
      expect(cubit.state.adding, false);
      await cubit.close();
      await workspace.close();
    },
  );
  test(
    'partial failure retains unsaved services and does not repeat successful saves',
    () async {
      final source = SelectionSource()..failPool = true;
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final cubit = BusinessesCubit(
        workspace,
        LocalApiBusinessRepository(source),
      );
      cubit.toggleService(BusinessType.turf);
      cubit.toggleService(BusinessType.pool);
      cubit.toggleService(BusinessType.hall);
      expect(await cubit.addSelected(), false);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.selected, {BusinessType.pool, BusinessType.hall});
      expect(cubit.state.adding, false);
      expect(cubit.state.error, isNotNull);
      source.failPool = false;
      expect(await cubit.addSelected(), true);
      expect(source.attempts.where((type) => type == 'turf').length, 1);
      expect(source.businesses.length, 3);
      await cubit.close();
      await workspace.close();
    },
  );
  test(
    'lost response reconciles newly saved business before offering a retry',
    () async {
      final source = SelectionSource()..losePoolResponse = true;
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final cubit = BusinessesCubit(
        workspace,
        LocalApiBusinessRepository(source),
      );
      cubit.toggleService(BusinessType.pool);
      cubit.toggleService(BusinessType.hall);
      expect(await cubit.addSelected(), false);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.selected, {BusinessType.hall});
      expect(source.businesses.length, 1);
      expect(await cubit.addSelected(), true);
      expect(source.attempts.where((type) => type == 'pool').length, 1);
      expect(source.businesses.length, 2);
      await cubit.close();
      await workspace.close();
    },
  );
  testWidgets(
    'all six cards support multi-selection at narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = SelectionSource();
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, _) => MaterialApp(
              theme: darkTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.6)),
                child: child!,
              ),
              home: const BusinessesScreen(onboarding: true),
            ),
          ),
        ),
      );
      for (final type in BusinessType.values) {
        expect(
          find.byKey(ValueKey('service-card-${type.code}')),
          findsOneWidget,
        );
      }
      for (final type in [BusinessType.turf, BusinessType.pool]) {
        final card = find.byKey(ValueKey('service-card-${type.code}'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pump();
      }
      expect(find.text('Turf name'), findsOneWidget);
      expect(find.text('Swimming Pool name'), findsOneWidget);
      final add = find.text('Add selected businesses (2)');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(source.businesses.length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await workspace.close();
    },
  );
}

import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/team/screens/staff_assignment_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';

class StaffRepository extends Fake implements WorkspaceRepository {
  Map<String, dynamic>? invitation;
  @override
  Future<Workspace> load() async => const Workspace(
    organization: Organization(
      id: 'o',
      name: 'Eden',
      phone: '123456789',
      currency: 'INR',
    ),
    membership: {'role': 'owner'},
    businesses: [
      Business(
        id: 'b',
        name: 'Eden Turf',
        type: BusinessType.turf,
        status: 'ready',
        locationId: 'l',
        version: 1,
        resources: [Resource(id: 'r', name: 'Turf 1', capacity: 1)],
      ),
    ],
  );
  @override
  Future<String> invite(Map<String, dynamic> data) async {
    invitation = data;
    return 'http://localhost/invite?token=test';
  }
}

void main() {
  tearDown(() async {
    await getIt.reset();
  });
  testWidgets(
    'staff form preserves selected resources and leaves financial reports disabled',
    (tester) async {
      final repository = StaffRepository();
      getIt.registerSingleton<WorkspaceRepository>(repository);
      registerFeatureDependencies(getIt);
      final workspace = WorkspaceCubit(repository);
      await workspace.load();
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, child) => MaterialApp(
              theme: darkTheme(),
              home: const StaffAssignmentScreen(),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Test Staff');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'staff@example.com',
      );
      final business = find.widgetWithText(CheckboxListTile, 'Eden Turf');
      await tester.ensureVisible(business);
      await tester.tap(business);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(business).value, true);
      final restrict = find.widgetWithText(
        SwitchListTile,
        'Restrict to selected resources',
      );
      await tester.ensureVisible(restrict);
      await tester.tap(restrict);
      await tester.pump();
      final resource = find.widgetWithText(CheckboxListTile, 'Turf 1');
      await tester.ensureVisible(resource);
      await tester.tap(resource);
      await tester.pump();
      final submit = find.text('Create invitation');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repository.invitation, isNotNull);
      expect(repository.invitation!['assignments'], [
        {
          'business_id': 'b',
          'resource_ids': ['r'],
        },
      ]);
      expect(
        repository.invitation!['permissions'],
        isNot(contains('view_finance')),
      );
      expect(find.text('Invitation ready'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await workspace.close();
    },
  );
}

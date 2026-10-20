import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/profile/cubit/profile_cubit.dart';
import 'package:eden_booking/modules/profile/models/organization_details_model.dart';
import 'package:eden_booking/modules/profile/repositories/profile_repository.dart';
import 'package:eden_booking/modules/profile/repositories/organization_details_mapper.dart';
import 'package:eden_booking/modules/profile/screens/organization_details_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';

Workspace fixture({
  bool owner = true,
  String line2 = 'Near the community park',
}) => Workspace(
  organization: const Organization(
    id: 'org',
    name: 'Eden Sports and Leisure Organization',
    phone: '9876543210',
    currency: 'INR',
  ),
  membership: {
    'id': 'member',
    'role': owner ? 'owner' : 'staff',
    'display_name': 'Alex Thomas',
    'email': 'alex@example.com',
  },
  locations: [
    {
      'id': 'location',
      'name': 'Eden Sports Arena',
      'address_line_1': '14 Garden Road',
      'address_line_2': line2,
      'city': 'Kochi',
      'state_code': 'KL',
      'country_code': 'IN',
      'postal_code': '068201',
      'timezone': 'Asia/Kolkata',
    },
  ],
);

class DetailsSource extends Fake implements WorkspaceRepository {
  Workspace value = fixture();
  Completer<Workspace>? next;
  @override
  Future<Workspace> load() => next?.future ?? Future.value(value);
}

class DetailsRepository extends Fake implements ProfileRepository {
  Completer<OrganizationLogoSelection?>? picker;
  int pickCalls = 0;
  @override
  OrganizationDetailsModel details(Workspace s) => mapOrganizationDetails(s);
  @override
  Future<OrganizationLogoSelection?> selectLogo() {
    pickCalls++;
    return picker?.future ?? Future.value(null);
  }

  @override
  Future<void> uploadLogo(Uint8List bytes, String contentType) async {}
}

void main() {
  test(
    'address fields preserve boundaries, whitespace and leading-zero pincodes',
    () {
      final d = mapOrganizationDetails(fixture(line2: '   '));
      final l = d.locations.single;
      expect(l.addressLine1, '14 Garden Road');
      expect(l.addressLine2, isEmpty);
      expect(l.pincode, '068201');
      expect(l.timezone, 'Asia/Kolkata');
      expect(l.state, 'KL');
      expect(d.ownerEmail, 'alex@example.com');
      expect(() => d.locations.clear(), throwsUnsupportedError);
      final staff = mapOrganizationDetails(fixture(owner: false));
      expect(staff.locations, isEmpty);
      expect(staff.ownerEmail, isEmpty);
    },
  );
  test('logo selection is discarded when workspace access changes', () async {
    final source = DetailsSource(), repo = DetailsRepository();
    final w = WorkspaceCubit(source);
    await w.load();
    final c = ProfileCubit(w, repo);
    repo.picker = Completer();
    final future = c.selectLogo();
    final expectation = expectLater(future, throwsA(isA<Exception>()));
    source.value = fixture(owner: false);
    await w.load();
    await Future<void>.delayed(Duration.zero);
    repo.picker!.complete(OrganizationLogoSelection(Uint8List(0), 'image/png'));
    await expectation;
    await c.close();
    await w.close();
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'field-by-field details fit 320px with larger text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = DetailsSource(), repo = DetailsRepository();
        final session = WorkspaceCubit(source);
        await session.load();
        await getIt.reset();
        getIt.registerFactoryParam<ProfileCubit, WorkspaceSession, void>(
          (s, _) => ProfileCubit(s, repo),
        );
        await tester.pumpWidget(
          BlocProvider.value(
            value: session,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (c, _) => MaterialApp(
                theme: AppTheme.build(brightness),
                home: const OrganizationDetailsScreen(),
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(
                    c,
                  ).copyWith(textScaler: const TextScaler.linear(1.4)),
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Organization details'), findsOneWidget);
        expect(find.text('Add logo'), findsOneWidget);
        for (final label in [
          'Phone number',
          'Currency',
          'Location name',
          'Address line 1',
          'Address line 2',
          'City',
          'State',
          'Country',
          'Pincode',
          'Timezone',
          'Full name',
          'Email address',
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.text('068201'), findsOneWidget);
        expect(find.text('Asia/Kolkata'), findsOneWidget);
        source.next = Completer();
        final refresh = session.load();
        await tester.pump();
        expect(find.text('Address line 1'), findsOneWidget);
        expect(find.text('14 Garden Road'), findsOneWidget);
        source.next!.complete(source.value);
        await refresh;
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await session.close();
        await getIt.reset();
      },
    );
  }
  testWidgets(
    'empty optional address is hidden and staff cannot view owner details',
    (tester) async {
      final source = DetailsSource()..value = fixture(line2: ' '),
          repo = DetailsRepository(),
          w = WorkspaceCubit(source);
      await w.load();
      await getIt.reset();
      getIt.registerFactoryParam<ProfileCubit, WorkspaceSession, void>(
        (s, _) => ProfileCubit(s, repo),
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (c, _) => MaterialApp(
              theme: AppTheme.build(Brightness.light),
              home: const OrganizationDetailsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Address line 2'), findsNothing);
      source.value = fixture(owner: false);
      await w.load();
      await tester.pumpAndSettle();
      expect(
        find.text('Only the owner can manage organization details.'),
        findsOneWidget,
      );
      expect(find.text('Email address'), findsNothing);
      expect(find.text('Address line 1'), findsNothing);
      expect(find.text('Add logo'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await w.close();
      await getIt.reset();
    },
  );
}

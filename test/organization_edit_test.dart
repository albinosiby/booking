import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/profile/cubit/organization_edit_cubit.dart';
import 'package:eden_booking/modules/profile/models/organization_edit_model.dart';
import 'package:eden_booking/modules/profile/repositories/organization_edit_repository.dart';
import 'package:eden_booking/modules/profile/screens/organization_edit_screen.dart';
import 'package:eden_booking/modules/organization/models/location_catalog.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource;

OrganizationEditDraft fixture() => OrganizationEditDraft(
  revision: 'revision-one',
  name: 'Eden',
  phone: '9876543210',
  currency: 'INR',
  locations: const [
    OrganizationEditLocation(
      id: 'site',
      name: 'Main arena',
      line1: '14 Garden Road',
      line2: '',
      city: 'Kochi',
      stateCode: 'KL',
      countryCode: 'IN',
      pincode: '682001',
      timezone: 'Asia/Kolkata',
    ),
  ],
);

class EditRepository extends Fake implements OrganizationEditRepository {
  final writes = <OrganizationEditDraft>[];
  AppException? fail;
  Completer<List<CatalogOption>>? delayedUS;
  OrganizationEditDraft value = fixture();
  @override
  Future<OrganizationEditDraft> load() async => value;
  @override
  Future<LocationCatalog> catalog() async => LocationCatalog(
    countries: const [
      CatalogOption('IN', 'India'),
      CatalogOption('US', 'United States'),
    ],
    timezones: const ['Asia/Kolkata'],
  );
  @override
  Future<List<CatalogOption>> states(String country) =>
      country == 'US' && delayedUS != null
      ? delayedUS!.future
      : Future.value(
          country == 'IN'
              ? const [
                  CatalogOption('KL', 'Kerala'),
                  CatalogOption('TN', 'Tamil Nadu'),
                ]
              : const [CatalogOption('NY', 'New York')],
        );
  @override
  Future<OrganizationEditDraft> save(OrganizationEditDraft draft) async {
    writes.add(draft);
    if (fail != null) throw fail!;
    value = OrganizationEditDraft(
      revision: 'revision-two',
      name: draft.name,
      phone: draft.phone,
      currency: draft.currency,
      locations: draft.locations,
    );
    return value;
  }
}

Future<WorkspaceCubit> session() async {
  final w = WorkspaceCubit(BookingSource());
  await w.load();
  return w;
}

void main() {
  test(
    'failed save retains edits, conflict reload and success have explicit states',
    () async {
      final w = await session(),
          r = EditRepository(),
          c = OrganizationEditCubit(w, r);
      await c.load();
      expect(c.state.canSave, false);
      c.fields(name: 'Updated Eden');
      c.locationFields(0, line1: 'New road', line2: 'Near park');
      r.fail = const AppException('Network failed', code: 'NETWORK');
      await c.save();
      expect(c.state.draft!.name, 'Updated Eden');
      expect(c.state.draft!.locations.single.line2, 'Near park');
      expect(c.state.dirty, true);
      r.fail = const AppException('Changed elsewhere', code: 'CONFLICT');
      await c.save();
      expect(c.state.conflict, true);
      expect(c.state.canSave, false);
      await c.load();
      expect(c.state.dirty, false);
      c.fields(name: 'Eden updated again');
      r.fail = null;
      await c.save();
      expect(c.state.saved, true);
      expect(c.state.dirty, false);
      await c.close();
      await w.close();
    },
  );
  test(
    'country clears state and late state responses cannot overwrite current selection',
    () async {
      final w = await session(),
          r = EditRepository(),
          c = OrganizationEditCubit(w, r);
      await c.load();
      await c.country(0, 'IN');
      expect(c.state.draft!.locations.single.stateCode, 'KL');
      expect(c.state.dirty, false);
      r.delayedUS = Completer();
      final pending = c.country(0, 'US');
      expect(c.state.draft!.locations.single.stateCode, '');
      expect(c.state.canSave, false);
      await c.country(0, 'IN');
      c.locationFields(0, stateCode: 'KL');
      r.delayedUS!.complete(const [CatalogOption('NY', 'New York')]);
      await pending;
      expect(c.state.draft!.locations.single.countryCode, 'IN');
      expect(c.state.draft!.locations.single.stateCode, 'KL');
      expect(c.state.draft!.locations.single.timezone, 'Asia/Kolkata');
      c.fields(phone: 'abc');
      await c.save();
      expect(c.state.errors['phone'], isNotNull);
      expect(r.writes, isEmpty);
      await c.close();
      await w.close();
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'edit fields fit 320px in $brightness and warn before discarding',
      (tester) async {
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final w = await session(), r = EditRepository();
        await getIt.reset();
        getIt.registerFactoryParam<
          OrganizationEditCubit,
          WorkspaceSession,
          void
        >((s, _) => OrganizationEditCubit(s, r));
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (c, s) =>
                  const Scaffold(body: Text('Organization details')),
            ),
            GoRoute(
              path: '/edit',
              builder: (c, s) => const OrganizationEditScreen(),
            ),
          ],
        );
        await tester.pumpWidget(
          BlocProvider.value(
            value: w,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (c, _) => MaterialApp.router(
                theme: AppTheme.build(brightness),
                routerConfig: router,
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
        unawaited(router.push<void>('/edit'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final name = find.byType(TextFormField).first;
        await tester.enterText(name, 'Updated organization');
        for (final label in [
          'Address line 1',
          'Address line 2 (optional)',
          'City',
          'Country',
          'State',
          'Pincode',
          'Timezone',
        ]) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(find.text('Updated organization'), findsOneWidget);
        if (brightness == Brightness.light) {
          await tester.tap(find.text('Save changes'));
          await tester.pumpAndSettle();
          expect(find.text('Organization details'), findsOneWidget);
          expect(r.writes.single.name, 'Updated organization');
        } else {
          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Discard'));
          await tester.pumpAndSettle();
          expect(find.text('Organization details'), findsOneWidget);
          expect(r.writes, isEmpty);
        }
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await w.close();
        await getIt.reset();
      },
    );
  }
}

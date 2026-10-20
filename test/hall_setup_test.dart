import 'package:eden_booking/modules/hall/screens/hall_resources_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/hall/models/hall_configuration.dart';
import 'package:eden_booking/modules/hall/models/hall_screen_models.dart';
import 'package:eden_booking/modules/hall/cubit/hall_setup_cubit.dart';
import 'package:eden_booking/modules/hall/repositories/hall_repository.dart';
import 'package:eden_booking/modules/hall/screens/hall_setup_screen.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

class HallSource extends Fake implements WorkspaceRepository {
  Map<String, dynamic>? configuration;
  int version = 1;
  String status = 'draft';
  @override
  Future<Workspace> load() async => Workspace(
    organization: const Organization(
      id: 'org',
      name: 'Eden',
      phone: '12345678',
      currency: 'INR',
    ),
    membership: const {'role': 'owner'},
    businesses: [
      Business(
        id: 'halls',
        name: 'Eden Swimming',
        type: BusinessType.hall,
        status: status,
        locationId: 'location',
        version: version,
        resources: (configuration?['halls'] as List? ?? [])
            .map((p) => Resource(id: p['id'], name: p['name'], capacity: 1))
            .toList(),
        configuration: configuration,
      ),
    ],
  );
}

class FakeHallRepository implements HallRepository {
  FakeHallRepository(this.source);
  final HallSource source;
  int writes = 0, activations = 0;
  bool loseSave = false, loseActivation = false, failActivation = false;
  @override
  Future<void> save(String id, int version, HallConfiguration config) async {
    writes++;
    if (version != source.version) {
      throw const AppException('Version conflict.', code: 'CONFLICT');
    }
    final json = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(config.toJson())),
    );
    source.configuration = {
      for (final k in json.keys.toList().reversed) k: json[k],
    };
    source.version++;
    source.status = 'draft';
    if (loseSave) {
      throw const AppException('Save response lost.', code: 'NETWORK');
    }
  }

  @override
  Future<void> activate(String id) async {
    activations++;
    if (failActivation) {
      throw const AppException('Activation failed.', code: 'NETWORK');
    }
    source.status = 'ready';
    source.version++;
    if (loseActivation) {
      throw const AppException('Activation response lost.', code: 'NETWORK');
    }
  }
}

void priceHall(HallSetupCubit c, String id) {
  c.addTariff(id);
  final p = c.state.draft.halls.firstWhere((p) => p.id == id);
  c.tariffPrice(id, p.tariffs.first.id, 60, '1000');
  for (final option in [...p.sessions, p.fullDay]) {
    c.enablePackage(id, option.id, true);
    final updated = c.state.draft.halls.firstWhere((p) => p.id == id);
    final o = [
      updated.fullDay,
      ...updated.sessions,
    ].firstWhere((o) => o.id == option.id);
    c.updatePackagePrice(
      id,
      o.id,
      o.prices.first.id,
      (r) => r.copyWith(price: option.id == p.fullDay.id ? '18000' : '5000'),
    );
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => getIt.reset());
  test(
    'hall options and separate package totals round-trip without changing resource identity',
    () async {
      final source = HallSource(), w = WorkspaceCubit(source);
      await w.load();
      final c = HallSetupCubit(w, FakeHallRepository(source), 'halls');
      c.addHall();
      final id = c.state.selectedId!;
      priceHall(c, id);
      final config = c.state.draft;
      expect(config.validate(complete: true), isNull);
      expect(
        HallConfiguration.fromJson(config.toJson()).toJson(),
        config.toJson(),
      );
      expect(config.halls.single.fullDay.prices.single.price, '18000');
      expect(config.halls.single.tariffs.single.rates.single.price, '1000');
      await c.close();
      await w.close();
    },
  );
  test(
    'copy includes all booking options while preserving target capacities and independent IDs',
    () async {
      final source = HallSource(), w = WorkspaceCubit(source);
      await w.load();
      final c = HallSetupCubit(w, FakeHallRepository(source), 'halls');
      c.addHall();
      final a = c.state.selectedId!;
      priceHall(c, a);
      c.addHall();
      final b = c.state.selectedId!;
      c.updateHall(
        b,
        (p) => p.copyWith(
          name: 'Garden Hall',
          capacity: '300',
          seated: '250',
          amenities: 'Parking',
          environment: 'outdoor',
        ),
      );
      c.copyPricing(a, [b]);
      final target = c.state.draft.halls.last,
          first = c.state.draft.halls.first;
      expect(target.id, b);
      expect(target.capacity, '300');
      expect(target.seated, '250');
      expect(target.name, 'Garden Hall');
      expect(target.amenities, 'Parking');
      expect(target.environment, 'outdoor');
      expect(target.fullDay.id, isNot(first.fullDay.id));
      expect(
        target.fullDay.prices.first.id,
        isNot(first.fullDay.prices.first.id),
      );
      expect(target.sessions.first.id, isNot(first.sessions.first.id));
      expect(target.tariffs.first.id, isNot(first.tariffs.first.id));
      c.updatePackage(b, target.fullDay.id, (o) => o.copyWith(enabled: false));
      expect(c.state.draft.halls.first.fullDay.enabled, isTrue);
      await c.close();
      await w.close();
    },
  );
  test(
    'validation requires selected option prices and enforces capacities with informational cleanup',
    () {
      final p = HallResource(
        id: 'hall',
        name: 'Main hall',
        hourlyEnabled: false,
      );
      var c = HallConfiguration(halls: [p]);
      expect(c.validate(complete: true), contains('Enable at least one'));
      final o = p.fullDay.copyWith(enabled: true);
      c = HallConfiguration(halls: [p.copyWith(fullDay: o)]);
      expect(c.validate(complete: true), contains('Complete prices'));
      final priced = o.copyWith(
        prices: [HallPackagePrice(id: 'price', price: '18000')],
      );
      expect(
        HallConfiguration(
          halls: [p.copyWith(fullDay: priced)],
        ).validate(complete: true),
        isNull,
      );
      expect(
        HallConfiguration(
          halls: [p.copyWith(fullDay: priced, after: 30)],
        ).validate(),
        isNull,
      );
      expect(
        HallConfiguration(halls: [p.copyWith(seated: '101')]).validate(),
        contains('capacities'),
      );
    },
  );
  test(
    'package price rules allow seasonal precedence but reject same-tier overlap',
    () {
      final h = HallResource(
        id: 'hall',
        name: 'Main hall',
        hourlyEnabled: false,
      );
      final r = HallPackagePrice(id: 'r', price: '18000');
      final o = h.fullDay.copyWith(
        enabled: true,
        prices: [
          r,
          r.copyWith(
            id: 'seasonal',
            window: HallHours(dateFrom: '2026-12-01', dateUntil: '2026-12-31'),
          ),
        ],
      );
      expect(
        HallConfiguration(
          halls: [h.copyWith(fullDay: o)],
        ).validate(complete: true),
        isNull,
      );
      expect(
        HallConfiguration(
          halls: [
            h.copyWith(
              fullDay: o.copyWith(
                prices: [
                  r,
                  r.copyWith(id: 'duplicate'),
                ],
              ),
            ),
          ],
        ).validate(),
        contains('overlap'),
      );
    },
  );
  test(
    'hall lost-save recovery, active edits and explicit conflict reload retain valid versions',
    () async {
      final source = HallSource(), w = WorkspaceCubit(source);
      await w.load();
      final r = FakeHallRepository(source), c = HallSetupCubit(w, r, 'halls');
      c.addHall();
      final id = c.state.selectedId!;
      priceHall(c, id);
      r.loseSave = true;
      r.loseActivation = true;
      expect(await c.activate(), isTrue);
      expect(c.state.version, 3);
      r.loseSave = false;
      r.loseActivation = false;
      c.updateHall(id, (p) => p.copyWith(name: 'Updated hall'));
      expect(await c.saveChanges(), isTrue);
      c.updateHall(id, (p) => p.copyWith(amenities: 'AC'));
      expect(await c.saveChanges(), isTrue);
      expect(c.state.version, 7);
      expect(source.status, 'ready');
      source.version++;
      c.updateHall(id, (p) => p.copyWith(name: 'Local edit'));
      expect(await c.saveChanges(), isFalse);
      expect(c.state.dirty, isTrue);
      await c.reloadSaved();
      expect(c.state.draft.halls.single.name, 'Updated hall');
      expect(c.state.dirty, isFalse);
      await c.close();
      await w.close();
    },
  );
  test('legacy hall capacity, IDs and hourly prices survive import', () {
    final b = Business(
      id: 'hall',
      name: 'Main hall',
      type: BusinessType.hall,
      status: 'ready',
      locationId: 'location',
      version: 4,
      resources: const [
        Resource(id: 'old-id', name: 'Original hall', capacity: 200),
      ],
      configuration: const {
        'days': [1, 2, 3, 4, 5, 6, 7],
        'opens_at': '06:00',
        'closes_at': '00:00',
        'duration_minutes': 60,
        'buffer_minutes': 0,
        'price_minor': 100000,
      },
    );
    final c = HallConfiguration.initial(b);
    expect(c.halls.single.id, 'old-id');
    expect(c.halls.single.capacity, '200');
    expect(c.halls.single.seated, '200');
    expect(c.halls.single.hourlyEnabled, isTrue);
    expect(c.halls.single.fullDay.enabled, isFalse);
    expect(c.validate(complete: true), isNull);
  });
  testWidgets(
    'hall setup configures all three options and active direct edits at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = HallSource();
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      await getIt.unregister<HallRepository>();
      getIt.registerSingleton<HallRepository>(FakeHallRepository(source));
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      addTearDown(workspace.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, child) => MaterialApp(
              theme: darkTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: const HallSetupScreen(businessId: 'halls'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tapFinder(Finder f) async {
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> tap(String s) => tapFinder(find.text(s));
      Future<void> enter(String label, String value) async {
        final f = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is ConfigurationField && w.label == label,
          ),
          matching: find.byType(TextFormField),
        );
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.enterText(f, value);
        await tester.pump();
      }

      Future<void> section(HallSection s) =>
          tapFinder(find.byKey(ValueKey('hall-section-${s.name}')));
      await section(HallSection.halls);
      await tap('Add hall');
      await enter('Hall name', 'Main Hall');
      await enter('Maximum guests', '200');
      await enter('Seated capacity', '150');
      await tap('Continue');
      expect(source.configuration, isNull);
      final id = tester
          .widget<HallResourcesScreen>(find.byType(HallResourcesScreen))
          .cubit
          .state
          .draft
          .halls
          .first
          .id;
      await tap('All Hall settings');
      Future<void> selectHall() async {
        await tapFinder(find.byKey(ValueKey('hall-item-$id')));
      }

      await section(HallSection.pricing);
      await selectHall();
      await tap('Configure hourly pricing');
      await tap('Add time-based price');
      await enter('60-minute price per hall · INR', '1000');
      await tap('Continue');
      for (final name in ['Morning', 'Evening']) {
        await selectHall();
        await tap('Offer $name session');
        await tap('Configure $name');
        await enter(
          'Total package price · INR',
          name == 'Morning' ? '5000' : '7000',
        );
        await tap('Continue');
      }
      await selectHall();
      await tap('Offer full-day package');
      await tap('Configure full-day package');
      await enter('Total package price · INR', '18000');
      await tap('Continue');
      await tap('All Hall settings');
      await section(HallSection.review);
      await tap('Activate halls');
      expect(source.status, 'ready');
      final p = source.configuration!['halls'][0];
      expect(p['hourly_enabled'], isTrue);
      expect(p['sessions'].where((s) => s['enabled'] == true).length, 2);
      expect(p['full_day']['prices'][0]['price_minor'], 1800000);
      await section(HallSection.pricing);
      await selectHall();
      await tap('Configure full-day package');
      await enter('Total package price · INR', '20000');
      await tap('Continue');
      await tap('All Hall settings');
      await tap('Save changes');
      expect(source.status, 'ready');
      expect(
        source
            .configuration!['halls'][0]['full_day']['prices'][0]['price_minor'],
        2000000,
      );
      expect(
        source
            .configuration!['halls'][0]['tariffs'][0]['rates'][0]['price_minor'],
        100000,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

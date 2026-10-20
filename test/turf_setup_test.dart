import 'package:eden_booking/modules/turf/screens/turf_rules_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:eden_booking/modules/turf/models/turf_setup_state.dart';
import 'package:go_router/go_router.dart';
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
import 'package:eden_booking/modules/turf/models/turf_configuration.dart';
import 'package:eden_booking/modules/turf/cubit/turf_setup_cubit.dart';
import 'package:eden_booking/modules/turf/repositories/turf_repository.dart';
import 'package:eden_booking/modules/turf/screens/turf_setup_screen.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

class TurfSource extends Fake implements WorkspaceRepository {
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
        id: 'turf',
        name: 'Eden Turf',
        type: BusinessType.turf,
        status: status,
        locationId: 'location',
        version: version,
        resources: configuration == null
            ? []
            : (configuration!['layouts'] as List)
                  .map(
                    (l) => Resource(id: l['id'], name: l['name'], capacity: 1),
                  )
                  .toList(),
        configuration: configuration,
      ),
    ],
  );
}

class FakeTurfRepository implements TurfRepository {
  FakeTurfRepository(this.source);
  final TurfSource source;
  int writes = 0, activations = 0;
  bool loseResponse = false,
      failActivation = false,
      loseActivationResponse = false;
  @override
  Future<void> save(String id, int version, TurfConfiguration draft) async {
    writes++;
    if (version != source.version) {
      throw const AppException(
        'Setup changed on another device.',
        code: 'CONFLICT',
      );
    }
    // PostgreSQL JSONB sorts object keys: compare typed serialization, not raw maps.
    final json = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(draft.toJson())),
    );
    source.configuration = {
      for (final key in json.keys.toList().reversed) key: json[key],
    };
    source.version++;
    source.status = 'draft';
    if (loseResponse) {
      throw const AppException('Response lost.', code: 'NETWORK');
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
    if (loseActivationResponse) {
      throw const AppException('Activation response lost.', code: 'NETWORK');
    }
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() async {
    await getIt.reset();
  });
  for (final linked in [false, true]) {
    test(
      'midnight repair extends Half A, preserves other hours and persists canonical times; cricket linked=$linked',
      () async {
        final source = TurfSource();
        final session = WorkspaceCubit(source);
        await session.load();
        final repository = FakeTurfRepository(source);
        final c = TurfSetupCubit(session, repository, 'turf');
        addTearDown(c.close);
        addTearDown(session.close);
        final football = c.state.draft.offerings
            .where((o) => o.sport == TurfSport.football)
            .toList();
        for (final offer in football) {
          c.price(offer.id, 60, '600');
        }
        if (linked) c.useFootballForCricket(true);
        final target = c.state.draft.offerings.firstWhere(
          (o) => o.id == football.first.id,
        );
        final band = target.pricingRules.single;
        c.priceBand(target.id, band.id, closes: '00:00');
        expect(c.state.draft.validate(), contains('23:00'));
        expect(c.state.draft.validate(), contains('24:00'));
        c.extendClosingForBand(target.id, band.id);
        final config = c.state.draft;
        expect(config.operating.closes, '00:00');
        expect(config.validate(), isNull);
        for (final offer in config.offerings) {
          final followsTarget =
              offer.id == target.id ||
              (linked &&
                  offer.sport == TurfSport.cricket &&
                  offer.layoutId == target.layoutId);
          expect(
            (offer.hoursOverride ?? config.operating).closes,
            followsTarget ? '00:00' : '23:00',
          );
        }
        expect(repository.writes, 0);
        expect(await c.saveProgress(), isTrue);
        final restored = TurfConfiguration.fromJson(source.configuration!);
        expect(restored.operating.closes, '00:00');
        expect(
          restored.offerings
              .firstWhere((o) => o.id == target.id)
              .hoursOverride!
              .closes,
          '00:00',
        );
        c.extendClosingForBand(target.id, band.id);
        expect(c.state.draft, restored);
      },
    );
  }
  test(
    'closing repair handles overnight hours and does not reinterpret earlier openings or closed weekdays',
    () {
      final hours = TurfHours(opens: '18:00', closes: '02:00', days: [1]);
      final change = turfClosingExtension(
        hours,
        hours,
        TurfHours(opens: '20:00', closes: '03:00', days: [1]),
      );
      expect(change!.offering.closes, '03:00');
      expect(
        turfClosingExtension(
          hours,
          hours,
          TurfHours(opens: '06:00', closes: '00:00', days: [1]),
        ),
        isNull,
      );
      expect(
        turfClosingExtension(
          hours,
          hours,
          TurfHours(opens: '20:00', closes: '03:00', days: [2]),
        ),
        isNull,
      );
    },
  );
  testWidgets(
    'midnight mismatch can be repaired beside its price rule at 320px with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = TurfSource();
      final session = WorkspaceCubit(source);
      await session.load();
      final repository = FakeTurfRepository(source);
      final c = TurfSetupCubit(session, repository, 'turf');
      addTearDown(c.close);
      addTearDown(session.close);
      final target = c.state.draft.offerings.first;
      c.price(target.id, 60, '600');
      final band = c.state.draft.offerings.first.pricingRules.single;
      c.priceBand(target.id, band.id, closes: '00:00');
      c.selectPricingOffering(target.id);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            theme: darkTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: BlocBuilder<TurfSetupCubit, TurfSetupState>(
                    bloc: c,
                    builder: (context, state) => TurfRulesScreen(
                      model: state.rulesModel,
                      cubit: c,
                      disabled: state.disabled,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.text('Extend this space to 24:00');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(action, findsNothing);
      expect(find.textContaining('Available 06:00–24:00'), findsOneWidget);
      expect(repository.writes, 0);
      expect(c.state.draft.validate(), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'turf pricing expansions do not read scroll offsets and stay independent per offering',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = TurfSource();
      final session = WorkspaceCubit(source);
      await session.load();
      final repository = FakeTurfRepository(source);
      final c = TurfSetupCubit(session, repository, 'turf');
      addTearDown(c.close);
      addTearDown(session.close);
      c.selectPricingSport(TurfSport.football);
      final bucket = PageStorageBucket();
      var seeded = false;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            theme: darkTheme(),
            home: Scaffold(
              body: PageStorage(
                bucket: bucket,
                child: SizedBox(
                  key: const PageStorageKey('pricing-page'),
                  child: Builder(
                    builder: (context) {
                      // Reproduce the nonzero scroll offset saved by the wizard.
                      if (!seeded) {
                        bucket.writeState(context, 120.0);
                        seeded = true;
                      }
                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: BlocBuilder<TurfSetupCubit, TurfSetupState>(
                            bloc: c,
                            builder: (context, state) => TurfRulesScreen(
                              model: state.rulesModel,
                              cubit: c,
                              disabled: state.disabled,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final shared = find.text('Shared opening hours');
      await tester.ensureVisible(shared);
      await tester.tap(shared);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final offers = c.state.draft.offerings
          .where((o) => o.sport == TurfSport.football)
          .toList();
      c.selectPricingOffering(offers.first.id);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final buffers = find.text('Preparation and cleanup (informational)');
      await tester.ensureVisible(buffers);
      await tester.tap(buffers);
      await tester.pumpAndSettle();
      expect(find.text('Preparation before booking'), findsOneWidget);
      c.selectPricingOffering(offers[1].id);
      await tester.pumpAndSettle();
      expect(find.text('Preparation before booking'), findsNothing);
      expect(tester.takeException(), isNull);
      c.selectPricingOffering(offers.first.id);
      await tester.pumpAndSettle();
      expect(find.text('Preparation before booking'), findsOneWidget);
      c.pricingSpaces();
      await tester.pumpAndSettle();
      expect(find.text('Shared opening hours'), findsOneWidget);
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'two halves and full ground share occupancy for six football/cricket offerings',
    () {
      final config = TurfConfiguration.initial(null), layouts = config.layouts;
      expect(config.grounds.single.sections.length, 2);
      expect(config.offerings.length, 6);
      expect(
        config.offerings
            .where((o) => o.sport == TurfSport.football)
            .map((o) => o.format),
        ['5s', '5s', '7s'],
      );
      expect(config.overlaps(layouts[0].id, layouts[1].id), false);
      expect(config.overlaps(layouts[2].id, layouts[0].id), true);
      expect(config.overlaps(layouts[2].id, layouts[1].id), true);
      final separate = config.addGround('Other Ground', TurfArrangement.single);
      expect(separate.overlaps(layouts[0].id, separate.layouts.last.id), false);
    },
  );
  test(
    'incomplete draft restores stable IDs and cannot activate until all prices exist',
    () async {
      final source = TurfSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final repository = FakeTurfRepository(source);
      final cubit = TurfSetupCubit(workspace, repository, 'turf');
      final ids = cubit.state.draft.layouts.map((l) => l.id).toList();
      expect(await cubit.saveDraft(), true);
      expect(await cubit.activate(), false);
      expect(repository.activations, 0);
      final restored = TurfSetupCubit(workspace, repository, 'turf');
      expect(restored.state.draft.layouts.map((l) => l.id), ids);
      for (final offer in restored.state.draft.offerings) {
        restored.price(offer.id, 60, '1500');
      }
      expect(await restored.activate(), true);
      expect(source.status, 'ready');
      expect(restored.state.dirty, false);
      await cubit.close();
      await restored.close();
      await workspace.close();
    },
  );
  test(
    'half settings copy to the matching sport only and cricket can be disabled',
    () async {
      final source = TurfSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final cubit = TurfSetupCubit(
        workspace,
        FakeTurfRepository(source),
        'turf',
      );
      final a = cubit.state.draft.offerings.firstWhere(
        (o) => o.sport == TurfSport.football,
      );
      cubit.price(a.id, 60, '1200');
      cubit.buffers(a.id, before: 10, after: 15);
      cubit.copyToOtherHalf(a.id);
      final football = cubit.state.draft.offerings
          .where((o) => o.sport == TurfSport.football)
          .toList();
      expect(football[1].rates.single.minor, 120000);
      expect(football[1].bufferBefore, 10);
      expect(football[2].rates.single.minor, null);
      expect(
        cubit.state.draft.offerings
            .where((o) => o.sport == TurfSport.cricket)
            .every((o) => o.rates.single.minor == null),
        true,
      );
      cubit.sport(TurfSport.cricket, false);
      expect(
        cubit.state.draft.offerings
            .where((o) => o.sport == TurfSport.cricket)
            .every((o) => !o.enabled),
        true,
      );
      await cubit.close();
      await workspace.close();
    },
  );
  test(
    'lost save response reconciles committed JSONB draft without retrying the write',
    () async {
      final source = TurfSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final session = workspace;
      final repository = FakeTurfRepository(source)..loseResponse = true;
      final cubit = TurfSetupCubit(session, repository, 'turf');
      cubit.groundName(cubit.state.draft.grounds.first.id, 'Shared Ground');
      expect(await cubit.saveDraft(), false);
      await Future<void>.delayed(Duration.zero);
      expect(repository.writes, 1);
      expect(cubit.state.version, 2);
      expect(cubit.state.dirty, false);
      expect(cubit.state.saving, false);
      expect(cubit.state.message, isNotNull);
      await cubit.close();
      await session.close();
    },
  );
  test('concurrent edits preserve local draft until explicit reload', () async {
    final source = TurfSource();
    final workspace = WorkspaceCubit(source);
    await workspace.load();
    await workspace.close();
    final session = WorkspaceCubit(source);
    await session.load();
    final repository = FakeTurfRepository(source);
    final cubit = TurfSetupCubit(session, repository, 'turf');
    cubit.groundName(cubit.state.draft.grounds.first.id, 'Local name');
    source.configuration = TurfConfiguration.initial(null).toJson();
    source.version = 2;
    expect(await cubit.saveDraft(), false);
    expect(cubit.state.dirty, true);
    expect(cubit.state.version, 1);
    expect(cubit.state.draft.grounds.first.name, 'Local name');
    await cubit.refreshSaved();
    expect(cubit.state.version, 2);
    expect(cubit.state.dirty, false);
    expect(cubit.state.draft.grounds.first.name, 'Main Ground');
    await cubit.close();
    await session.close();
  });
  test('legacy independent resources stay independent when imported', () {
    const business = Business(
      id: 'turf',
      name: 'Turf',
      type: BusinessType.turf,
      status: 'ready',
      locationId: 'l',
      version: 4,
      resources: [
        Resource(id: 'a', name: 'Court A', capacity: 1),
        Resource(id: 'b', name: 'Court B', capacity: 1),
      ],
    );
    final draft = TurfConfiguration.initial(business);
    expect(draft.grounds.length, 2);
    expect(draft.layouts.map((l) => l.id), ['a', 'b']);
    expect(draft.overlaps('a', 'b'), false);
  });
  test(
    'adding a ground after deletion keeps generated space names unique',
    () async {
      final source = TurfSource(), session = WorkspaceCubit(TurfSource());
      await session.load();
      final cubit = TurfSetupCubit(session, FakeTurfRepository(source), 'turf');
      cubit.addGround();
      cubit.addGround();
      cubit.removeGround(cubit.state.draft.grounds[1].id);
      cubit.addGround();
      expect(
        cubit.state.draft.layouts.map((layout) => layout.name).toSet().length,
        cubit.state.draft.layouts.length,
      );
      expect(cubit.state.draft.validate(), null);
      await cubit.close();
      await session.close();
    },
  );
  test(
    'flat prices migrate into stable all-day rules without changing their amounts',
    () {
      final raw = TurfConfiguration.initial(null).toJson();
      for (final offer in raw['offerings']) {
        offer.remove('pricing_rules');
        offer.remove('pricing_basis');
        offer.remove('default_duration_minutes');
        offer['rates'][0]['price_minor'] = 60000;
      }
      final converted = TurfConfiguration.fromJson(raw),
          again = TurfConfiguration.fromJson(raw);
      expect(
        converted.offerings.every(
          (offer) => offer.pricingRules.single.rates.single.minor == 60000,
        ),
        true,
      );
      expect(
        converted.offerings.first.pricingRules.single.id,
        again.offerings.first.pricingRules.single.id,
      );
      expect(converted.validate(complete: true), null);
    },
  );
  test(
    'Continue validates the chosen space locally without requiring other spaces yet',
    () async {
      final source = TurfSource(), workspace = WorkspaceCubit(TurfSource());
      await workspace.load();
      await workspace.close();
      final session = WorkspaceCubit(source);
      await session.load();
      final repository = FakeTurfRepository(source);
      final cubit = TurfSetupCubit(session, repository, 'turf');
      cubit.step(4);
      final offer = cubit.state.draft.offerings.first;
      cubit.selectPricingOffering(offer.id);
      cubit.addPriceBand(offer.id);
      var bands = cubit.state.draft.offerings.first.pricingRules;
      cubit.bandPrice(offer.id, bands.first.id, 60, '600');
      cubit.addPriceBand(offer.id);
      bands = cubit.state.draft.offerings.first.pricingRules;
      cubit.bandPrice(offer.id, bands.last.id, 60, '700');
      expect(await cubit.continueSetup(), false);
      expect(repository.writes, 0);
      expect(cubit.state.message, contains('overlap'));
      cubit.priceBand(offer.id, bands.first.id, days: [6, 7]);
      cubit.priceBand(offer.id, bands.last.id, days: [1, 2, 3, 4, 5]);
      expect(await cubit.continueSetup(), true);
      expect(repository.writes, 0);
      expect(cubit.state.pricingOfferingId, null);
      expect(cubit.state.step, 4);
      expect(
        cubit.state.draft.offerings
            .skip(1)
            .every((offer) => offer.pricingRules.isEmpty),
        true,
      );
      await cubit.close();
      await session.close();
    },
  );
  test(
    'Football checkbox copies matching spaces, follows edits, persists and unlinks safely',
    () async {
      final source = TurfSource();
      final session = WorkspaceCubit(source);
      await session.load();
      final repository = FakeTurfRepository(source);
      final cubit = TurfSetupCubit(session, repository, 'turf');
      cubit.useFootballForCricket(true);
      expect(cubit.state.draft.cricketUsesFootball, false);
      final football = cubit.state.draft.offerings
          .where((o) => o.sport == TurfSport.football)
          .toList();
      for (var i = 0; i < football.length; i++) {
        cubit.price(football[i].id, 60, '${600 + i * 100}');
        cubit.buffers(football[i].id, before: 5, after: 10);
      }
      final originalCricket = cubit.state.draft.offerings
          .where((o) => o.sport == TurfSport.cricket)
          .toList();
      cubit.useFootballForCricket(true);
      expect(cubit.state.draft.cricketUsesFootball, true);
      expect(cubit.state.draft.validate(complete: true), isNull);
      for (final cricket in cubit.state.draft.offerings.where(
        (o) => o.sport == TurfSport.cricket,
      )) {
        final original = originalCricket.firstWhere((o) => o.id == cricket.id);
        final paired = cubit.state.draft.offerings.firstWhere(
          (o) =>
              o.sport == TurfSport.football && o.layoutId == cricket.layoutId,
        );
        expect(cricket.sameTimingAndPricing(paired), true);
        expect(cricket.name, original.name);
        expect(cricket.format, original.format);
        expect(
          cricket.pricingRules.first.id,
          isNot(paired.pricingRules.first.id),
        );
      }
      final firstCricket = cubit.state.draft.offerings.firstWhere(
        (o) => o.sport == TurfSport.cricket,
      );
      final cricketBandId = firstCricket.pricingRules.first.id;
      cubit.price(firstCricket.id, 60, '999');
      expect(
        cubit.state.draft.offerings
            .firstWhere((o) => o.id == firstCricket.id)
            .rates
            .first
            .price,
        '600',
      );
      cubit.price(football.first.id, 60, '650');
      expect(
        cubit.state.draft.offerings
            .firstWhere((o) => o.id == firstCricket.id)
            .rates
            .first
            .price,
        '650',
      );
      expect(
        cubit.state.draft.offerings
            .firstWhere((o) => o.id == firstCricket.id)
            .pricingRules
            .first
            .id,
        cricketBandId,
      );
      expect(await cubit.saveProgress(), true);
      cubit.restoreSaved();
      expect(cubit.state.draft.cricketUsesFootball, true);
      cubit.useFootballForCricket(false);
      cubit.price(firstCricket.id, 60, '750');
      expect(
        cubit.state.draft.offerings
            .firstWhere((o) => o.id == football.first.id)
            .rates
            .first
            .minor,
        65000,
      );
      expect(
        cubit.state.draft.offerings
            .firstWhere((o) => o.id == firstCricket.id)
            .rates
            .first
            .minor,
        75000,
      );
      expect(await cubit.saveProgress(), true);
      expect(source.configuration!['cricket_uses_football'], false);
      await cubit.close();
      await session.close();
    },
  );
  test(
    'Cricket link requires an enabled Football counterpart and legacy setups stay independent',
    () {
      final config = TurfConfiguration.initial(null);
      expect(
        TurfConfiguration.fromJson(
          config.toJson()..remove('cricket_uses_football'),
        ).cricketUsesFootball,
        false,
      );
      final cricket = config.offerings.firstWhere(
        (o) => o.sport == TurfSport.cricket,
      );
      final missing = config.copyWith(
        offerings: config.offerings.map(
          (o) => o.layoutId == cricket.layoutId && o.sport == TurfSport.football
              ? o.copyWith(enabled: false)
              : o,
        ),
      );
      expect(missing.hasMatchingFootballSpaces, false);
      expect(
        missing
            .copyWith(cricketUsesFootball: true)
            .synchronizeCricket()
            .cricketUsesFootball,
        false,
      );
    },
  );
  test(
    'settings jump to any section and retry activation without repeating a saved write',
    () async {
      var config = TurfConfiguration.initial(null);
      config = config.copyWith(
        offerings: config.offerings.map(
          (o) => o.copyWith(
            rates: [const TurfRate(60, '600')],
            pricingRules: [
              TurfPriceBand(
                id: o.id,
                days: [1, 2, 3, 4, 5, 6, 7],
                opens: '06:00',
                closes: '23:00',
                rates: [const TurfRate(60, '600')],
              ),
            ],
          ),
        ),
      );
      final source = TurfSource()
        ..configuration = config.toJson()
        ..status = 'ready';
      final session = WorkspaceCubit(source);
      await session.load();
      final repository = FakeTurfRepository(source)..failActivation = true;
      final cubit = TurfSetupCubit(session, repository, 'turf');
      cubit.beginEditing();
      expect(cubit.state.settingsOverview, true);
      cubit.openSettingsSection(4);
      expect(cubit.state.step, 4);
      expect(cubit.state.settingsOverview, false);
      final offer = cubit.state.draft.offerings.first;
      cubit.price(offer.id, 60, '700');
      expect(await cubit.saveSettings(), false);
      expect(repository.writes, 1);
      expect(cubit.state.dirty, false);
      expect(cubit.state.editingReady, true);
      expect(cubit.state.business!.ready, false);
      repository.failActivation = false;
      repository.loseActivationResponse = true;
      expect(await cubit.saveSettings(), true);
      repository.loseActivationResponse = false;
      expect(repository.writes, 1);
      expect(repository.activations, 2);
      expect(cubit.state.business!.ready, true);
      expect(cubit.state.settingsOverview, true);
      cubit.openSettingsSection(2);
      expect(cubit.state.step, 2);
      cubit.spaceName(cubit.state.draft.layouts.first.id, 'Updated Half A');
      cubit.showSettingsOverview();
      expect(cubit.state.dirty, true);
      cubit.openSettingsSection(2);
      expect(cubit.state.draft.layouts.first.name, 'Updated Half A');
      expect(await cubit.saveSettings(), true);
      expect(repository.writes, 2);
      expect(repository.activations, 3);
      expect(cubit.state.version, cubit.state.business!.version);
      expect(cubit.state.business!.ready, true);
      await cubit.close();
      await session.close();
    },
  );
  testWidgets(
    'Turf settings overview opens pricing directly and saves without setup steps at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = TurfSource();
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      await getIt.unregister<TurfRepository>();
      getIt.registerSingleton<TurfRepository>(FakeTurfRepository(source));
      final session = WorkspaceCubit(source);
      await session.load();
      addTearDown(session.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: session,
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
              home: const TurfSetupScreen(businessId: 'turf', editMode: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Turf settings'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(find.text('1. Sports'), findsNothing);
      final pricing = find.byKey(const ValueKey('turf-settings-section-4'));
      await tester.ensureVisible(pricing);
      await tester.tap(pricing);
      await tester.pumpAndSettle();
      expect(find.text('Timing & pricing.'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
      final all = find.text('All Turf settings');
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      final spaces = find.byKey(const ValueKey('turf-settings-section-2'));
      await tester.ensureVisible(spaces);
      await tester.tap(spaces);
      await tester.pumpAndSettle();
      expect(find.text('Bookable spaces.'), findsOneWidget);
      final field = find.byType(TextFormField).first;
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Renamed Half A');
      await tester.pump();
      final save = find.text('Save changes');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Turf settings'), findsOneWidget);
      expect(
        (source.configuration!['layouts'] as List).first['name'],
        'Renamed Half A',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'six-step turf setup renders with large text and saves/activates at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = TurfSource();
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      await getIt.unregister<TurfRepository>();
      getIt.registerSingleton<TurfRepository>(FakeTurfRepository(source));
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const TurfSetupScreen(businessId: 'turf'),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) =>
                const Scaffold(body: Text('Home after activation')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, child) => MaterialApp.router(
              routerConfig: router,
              theme: darkTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.6)),
                child: child!,
              ),
            ),
          ),
        ),
      );
      for (var step = 0; step < 4; step++) {
        final next = find.text('Continue');
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Timing & pricing.'), findsOneWidget);
      expect(find.text('Save draft'), findsNothing);
      expect(source.configuration, isNull);
      final localCubit = tester
          .widget<TurfRulesScreen>(find.byType(TurfRulesScreen))
          .cubit;
      final layouts = localCubit.state.draft.toJson()['layouts'] as List;
      for (final sport in ['football']) {
        final sportChip = find.byKey(ValueKey('pricing-sport-$sport'));
        await tester.ensureVisible(sportChip);
        await tester.tap(sportChip);
        await tester.pumpAndSettle();
        for (final layout in layouts) {
          final space = find.byKey(ValueKey('pricing-space-${layout['id']}'));
          await tester.ensureVisible(space);
          await tester.tap(space);
          await tester.pumpAndSettle();
          final add = find.text('Add time-based price');
          await tester.ensureVisible(add);
          await tester.tap(add);
          await tester.pumpAndSettle();
          final field = find.byType(TextFormField);
          expect(field, findsOneWidget);
          await tester.ensureVisible(field);
          await tester.enterText(field, '1500');
          await tester.pump();
          final next = find.text('Continue');
          await tester.ensureVisible(next);
          await tester.tap(next);
          await tester.pumpAndSettle();
          expect(find.text('Choose a sport'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      expect(
        (localCubit.state.draft.toJson()['offerings'] as List)
            .where((offer) => offer['sport'] == 'football')
            .every((offer) => offer['pricing_rules'].length == 1),
        true,
      );
      final copyCheckbox = find.byKey(
        const ValueKey('use-football-for-cricket'),
      );
      await tester.ensureVisible(copyCheckbox);
      expect(
        tester.widget<CheckboxListTile>(copyCheckbox).onChanged,
        isNotNull,
      );
      final checkboxControl = find.descendant(
        of: copyCheckbox,
        matching: find.byType(Checkbox),
      );
      await tester.ensureVisible(checkboxControl);
      await tester.tap(checkboxControl);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(copyCheckbox).value, true);
      expect(tester.takeException(), isNull);
      final next = find.text('Continue');
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Review your turf.'), findsOneWidget);
      expect(localCubit.state.draft.cricketUsesFootball, true);
      expect(source.configuration, isNull);
      expect(
        (localCubit.state.draft.toJson()['offerings'] as List).every(
          (offer) => offer['pricing_rules'].length == 1,
        ),
        true,
      );
      expect(find.text('Save draft'), findsNothing);
      final activate = find.text('Activate turf');
      await tester.ensureVisible(activate);
      await tester.tap(activate);
      await tester.pumpAndSettle();
      expect(source.status, 'ready');
      expect(find.text('Home after activation'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await workspace.close();
    },
  );
}

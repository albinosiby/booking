import 'package:eden_booking/modules/court/screens/court_resources_screen.dart';
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
import 'package:eden_booking/modules/court/models/court_configuration.dart';
import 'package:eden_booking/modules/court/models/court_screen_models.dart';
import 'package:eden_booking/modules/court/cubit/court_setup_cubit.dart';
import 'package:eden_booking/modules/court/repositories/court_repository.dart';
import 'package:eden_booking/modules/court/screens/court_setup_screen.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

class CourtSource extends Fake implements WorkspaceRepository {
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
        id: 'courts',
        name: 'Eden Swimming',
        type: BusinessType.badminton,
        status: status,
        locationId: 'location',
        version: version,
        resources: (configuration?['courts'] as List? ?? [])
            .map((p) => Resource(id: p['id'], name: p['name'], capacity: 1))
            .toList(),
        configuration: configuration,
      ),
    ],
  );
}

class FakeCourtRepository implements CourtRepository {
  FakeCourtRepository(this.source);
  final CourtSource source;
  int writes = 0, activations = 0;
  bool loseSave = false, loseActivation = false, failActivation = false;
  @override
  Future<void> save(String id, int version, CourtConfiguration config) async {
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

void priceCourt(CourtSetupCubit c, String id, String value) {
  c.addTariff(id);
  c.tariffPrice(
    id,
    c.state.draft.courts.firstWhere((p) => p.id == id).tariffs.first.id,
    60,
    value,
  );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => getIt.reset());
  test(
    'court flow keeps selection, validates completion and adds another without a cloud save',
    () async {
      final source = CourtSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final repository = FakeCourtRepository(source);
      final c = CourtSetupCubit(workspace, repository, 'courts');
      addTearDown(c.close);
      addTearDown(workspace.close);
      c.addCourt();
      final first = c.state.selectedId!;
      expect(c.state.resourceFlow, isTrue);
      expect(await c.finishResource(addAnother: true), isFalse);
      expect(repository.writes, 0);
      expect(c.state.draft.courts, hasLength(1));
      priceCourt(c, first, '400');
      c.continueResource();
      expect(c.state.section, CourtSection.pricing);
      expect(c.state.selectedId, first);
      c.back();
      expect(c.state.section, CourtSection.courts);
      expect(c.state.selectedId, first);
      c.continueResource();
      expect(await c.finishResource(addAnother: true), isTrue);
      final second = c.state.selectedId!;
      expect(second, isNot(first));
      expect(repository.writes, 0);
      expect(source.configuration, isNull);
      expect(c.state.section, CourtSection.courts);
      expect(c.state.resourceFlow, isTrue);
      priceCourt(c, second, '600');
      c.continueResource();
      // Continuing remains local, even if a newer cloud version exists.
      source.version++;
      expect(await c.finishResource(addAnother: true), isTrue);
      expect(c.state.draft.courts, hasLength(3));
      expect(repository.writes, 0);
      // Final Save detects the conflict and keeps all local resources.
      expect(await c.saveChanges(), isFalse);
      expect(c.state.draft.courts, hasLength(3));
    },
  );

  test(
    'court copies preserve identities and metadata; duration and tariff edits remain independent',
    () async {
      final source = CourtSource(), w = WorkspaceCubit(CourtSource());
      await w.load();
      final c = CourtSetupCubit(w, FakeCourtRepository(source), 'courts');
      c.addCourt();
      final a = c.state.selectedId!;
      priceCourt(c, a, '400');
      c.updateCourt(
        a,
        (p) => p.copyWith(hours: p.hours.copyWith(closes: '00:00')),
      );
      c.addCourt();
      final b = c.state.selectedId!;
      c.updateCourt(
        b,
        (p) => p.copyWith(
          name: 'Outdoor court',
          environment: 'outdoor',
          surface: 'Concrete',
        ),
      );
      c.copyPricing(a, [b]);
      var target = c.state.draft.courts.last;
      expect(target.id, b);
      expect(target.name, 'Outdoor court');
      expect(target.surface, 'Concrete');
      expect(target.environment, 'outdoor');
      expect(target.hours.closes, '00:00');
      expect(
        target.tariffs.first.id,
        isNot(c.state.draft.courts.first.tariffs.first.id),
      );
      c.tariffPrice(b, target.tariffs.first.id, 60, '600');
      expect(c.state.draft.courts.first.tariffs.first.rates.first.price, '400');
      c.duration(b, 90, true);
      expect(
        c.state.draft.validate(complete: true),
        contains('Complete prices'),
      );
      expect(c.state.draft.courts.first.durations, [60]);
      final restored = CourtConfiguration.fromJson(c.state.draft.toJson());
      expect(restored.toJson(), c.state.draft.toJson());
      await c.close();
      await w.close();
    },
  );
  test('court rules reject same-tier overlaps but allow dated overrides', () {
    final h = CourtHours(closes: '00:00');
    final t = CourtTariff(
      id: 'band',
      hours: h,
      rates: const [CourtRate(60, '400')],
    );
    final p = CourtResource(
      id: 'court',
      name: 'Court 1',
      hours: h,
      tariffs: [t],
    );
    expect(CourtConfiguration(courts: [p]).validate(complete: true), isNull);
    expect(
      CourtConfiguration(
        courts: [
          p.copyWith(
            tariffs: [
              t,
              t.copyWith(id: 'second'),
            ],
          ),
        ],
      ).validate(),
      contains('overlap'),
    );
    expect(
      CourtConfiguration(
        courts: [
          p.copyWith(
            tariffs: [
              t,
              t.copyWith(
                id: 'seasonal',
                hours: h.copyWith(
                  dateFrom: '2026-12-01',
                  dateUntil: '2026-12-31',
                ),
              ),
            ],
          ),
        ],
      ).validate(),
      isNull,
    );
  });
  test(
    'court saves recover lost responses and preserve versions across consecutive active edits',
    () async {
      final source = CourtSource(), w = WorkspaceCubit(source);
      await w.load();
      final r = FakeCourtRepository(source),
          c = CourtSetupCubit(w, r, 'courts');
      c.addCourt();
      final id = c.state.selectedId!;
      priceCourt(c, id, '400');
      r.loseSave = true;
      r.loseActivation = true;
      expect(await c.activate(), isTrue);
      expect(c.state.version, 3);
      r.loseSave = false;
      r.loseActivation = false;
      c.updateCourt(id, (p) => p.copyWith(name: 'Renamed Court'));
      expect(await c.saveChanges(), isTrue);
      c.updateCourt(id, (p) => p.copyWith(surface: 'Wood'));
      expect(await c.saveChanges(), isTrue);
      expect(c.state.version, 7);
      expect(source.status, 'ready');
      expect(source.configuration!['courts'][0]['surface'], 'Wood');
      expect(r.writes, 3);
      await c.close();
      await w.close();
    },
  );
  test('court conflicts retain local edits until explicit reload', () async {
    final source = CourtSource(), w = WorkspaceCubit(source);
    await w.load();
    final c = CourtSetupCubit(w, FakeCourtRepository(source), 'courts');
    c.addCourt();
    final id = c.state.selectedId!;
    priceCourt(c, id, '400');
    expect(await c.saveChanges(), isTrue);
    source.version++;
    c.updateCourt(id, (p) => p.copyWith(name: 'Local name'));
    expect(await c.saveChanges(), isFalse);
    expect(c.state.dirty, isTrue);
    expect(c.state.draft.courts.single.name, 'Local name');
    await c.reloadSaved();
    expect(c.state.dirty, isFalse);
    expect(c.state.draft.courts.single.name, 'Court 1');
    await c.close();
    await w.close();
  });
  test('legacy court identifiers and price survive adoption', () {
    final b = Business(
      id: 'business',
      name: 'Tennis',
      type: BusinessType.tennis,
      status: 'ready',
      locationId: 'location',
      version: 4,
      resources: const [
        Resource(id: 'original', name: 'Tennis 1', capacity: 1),
      ],
      configuration: const {
        'days': [1, 2, 3, 4, 5, 6, 7],
        'opens_at': '06:00',
        'closes_at': '00:00',
        'duration_minutes': 60,
        'buffer_minutes': 5,
        'price_minor': 45000,
      },
    );
    final c = CourtConfiguration.initial(b);
    expect(c.courts.single.id, 'original');
    expect(c.courts.single.tariffs.single.rates.single.minor, 45000);
    expect(c.validate(complete: true), isNull);
  });
  testWidgets(
    'Court configuration edits every section and activates three independent courts at 320px with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = CourtSource();
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      await getIt.unregister<CourtRepository>();
      final repository = FakeCourtRepository(source);
      getIt.registerSingleton<CourtRepository>(repository);
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
              home: const CourtSetupScreen(businessId: 'courts'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String text) async {
        final f = find.text(text);
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

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

      Future<void> section(CourtSection s) async {
        final f = find.byKey(ValueKey('court-section-${s.name}'));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await section(CourtSection.courts);
      for (var i = 0; i < 3; i++) {
        if (i == 0) await tap('Add court');
        final f = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is ConfigurationField && w.label == 'Court name',
          ),
          matching: find.byType(TextFormField),
        );
        final element = tester.element(f);
        await enter('Court name', 'Court ${i + 1}');
        expect(identical(tester.element(f), element), isTrue);
        await tap('Continue to timing & pricing');
        expect(find.text('Minimum booking duration'), findsOneWidget);
        expect(find.text('Your courts'), findsNothing);
        await tap('Add time-based price');
        await enter('60-minute price per court · INR', i == 0 ? '400' : '600');
        await tap(i == 2 ? 'Continue' : 'Continue & add another court');
        expect(source.configuration, isNull);
        expect(
          tester
              .widget<CourtResourcesScreen>(find.byType(CourtResourcesScreen))
              .cubit
              .state
              .draft
              .courts
              .length,
          i == 2 ? 3 : i + 2,
        );
      }
      final localConfiguration = tester
          .widget<CourtResourcesScreen>(find.byType(CourtResourcesScreen))
          .cubit
          .state
          .draft
          .toJson();
      await tap('All Court settings');
      final ids = (localConfiguration['courts'] as List)
          .map((p) => p['id'] as String)
          .toList();
      await section(CourtSection.review);
      await tap('Activate courts');
      expect(source.status, 'ready');
      await section(CourtSection.courts);
      final existingId = source.configuration!['courts'][0]['id'];
      final existing = find.byKey(ValueKey('court-item-$existingId'));
      await tester.ensureVisible(existing);
      await tester.pumpAndSettle();
      await tester.tap(existing);
      await tester.pumpAndSettle();
      expect(find.text('Continue to timing & pricing'), findsNothing);
      expect(find.text('Edit timing & pricing'), findsOneWidget);
      await enter('Surface type · optional', 'Wooden');
      await tap('Continue');
      await tap('All Court settings');
      await tap('Save changes');
      expect(source.status, 'ready');

      expect(source.configuration!['courts'].length, 3);
      await section(CourtSection.pricing);
      final item = find.byKey(ValueKey('court-item-${ids.last}'));
      await tester.ensureVisible(item);
      await tester.pumpAndSettle();
      await tester.tap(item);
      await tester.pumpAndSettle();
      await enter('60-minute price per court · INR', '750');
      await tap('Continue');
      await tap('All Court settings');
      await tap('Save changes');
      expect(source.status, 'ready');
      expect(
        source
            .configuration!['courts'][2]['tariffs'][0]['rates'][0]['price_minor'],
        75000,
      );
      expect(
        source
            .configuration!['courts'][0]['tariffs'][0]['rates'][0]['price_minor'],
        40000,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

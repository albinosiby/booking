import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/pool/screens/pool_resources_screen.dart';
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
import 'package:eden_booking/modules/pool/models/pool_configuration.dart';
import 'package:eden_booking/modules/pool/models/pool_screen_models.dart';
import 'package:eden_booking/modules/pool/cubit/pool_setup_cubit.dart';
import 'package:eden_booking/modules/pool/repositories/pool_repository.dart';
import 'package:eden_booking/modules/pool/screens/pool_setup_screen.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

class PoolSource extends Fake implements WorkspaceRepository {
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
        id: 'swimming',
        name: 'Eden Swimming',
        type: BusinessType.pool,
        status: status,
        locationId: 'location',
        version: version,
        resources: (configuration?['pools'] as List? ?? [])
            .map(
              (p) => Resource(
                id: p['id'],
                name: p['name'],
                capacity: p['capacity'],
              ),
            )
            .toList(),
        configuration: configuration,
      ),
    ],
  );
}

class FakePoolRepository implements PoolRepository {
  FakePoolRepository(this.source);
  final PoolSource source;
  int writes = 0, activations = 0;
  bool loseSave = false, loseActivation = false, failActivation = false;
  @override
  Future<List<PoolCoach>> loadCoaches(String id) async => [];
  @override
  Future<void> save(String id, int version, PoolConfiguration config) async {
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

void configurePool(
  PoolSetupCubit c,
  String id, {
  String capacity = '20',
  String price = '200',
}) {
  c.updatePool(
    id,
    (p) => p.copyWith(capacity: capacity, minDepth: '3', maxDepth: '5'),
  );
  c.addTariff(id);
  final tariff = c.state.draft.pools
      .firstWhere((p) => p.id == id)
      .tariffs
      .first;
  c.tariffPrice(id, tariff.id, 60, price);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => getIt.reset());
  test(
    'Plan validity uses calendar months and years, preserves drafts and rejects zero',
    () {
      final pool = PoolResource(
        id: 'pool',
        name: 'Pool A',
        capacity: '20',
        minDepth: '3',
        maxDepth: '5',
      );
      final original = PoolPlan(
        id: 'plan',
        kind: 'coaching',
        poolIds: ['pool'],
        price: '1000',
      );
      for (final mode in ['after_start', 'after_months', 'after_years']) {
        final plan = original.copyWith(expiryMode: mode).withValidityCount('2');
        final restored = PoolPlan.fromJson(plan.toJson());
        expect(restored.expiryMode, mode);
        expect(restored.validityCount, '2');
        expect(
          PoolConfiguration(pools: [pool], plans: [plan]).validate(),
          isNull,
        );
        expect(
          PoolConfiguration(
            pools: [pool],
            plans: [plan.withValidityCount('0')],
          ).validate(),
          contains('expiry'),
        );
        expect(
          PoolPlan.fromJson(
            plan.withValidityCount('').toJson(localDraft: true),
          ).validityCount,
          '',
        );
      }
      expect(
        original
            .copyWith(expiryMode: 'after_months')
            .expiryFrom(DateTime(2026, 1, 31)),
        DateTime(2026, 2, 28),
      );
      expect(
        original
            .copyWith(expiryMode: 'after_months')
            .expiryFrom(DateTime(2024, 1, 31)),
        DateTime(2024, 2, 29),
      );
      expect(
        original
            .copyWith(expiryMode: 'after_years')
            .expiryFrom(DateTime(2024, 2, 29)),
        DateTime(2025, 2, 28),
      );
      expect(PoolPlan.fromJson(original.toJson()).expiryDays, '45');
    },
  );
  test(
    'plan-only pool can finish its setup before products are added; activation still requires one',
    () async {
      final source = PoolSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final repository = FakePoolRepository(source);
      final c = PoolSetupCubit(workspace, repository, 'swimming');
      addTearDown(c.close);
      addTearDown(workspace.close);
      c.addPool();
      final id = c.state.selectedId!;
      c.continueResource();
      expect(c.state.section, PoolSection.pools);
      expect(c.state.message, contains('depths'));
      c.updatePool(id, (p) => p.copyWith(minDepth: '5', maxDepth: '3'));
      c.continueResource();
      expect(c.state.section, PoolSection.pools);
      expect(c.state.message, contains('depth'));
      c.updatePool(
        id,
        (p) => p.copyWith(minDepth: '3', maxDepth: '5', regularSwimming: false),
      );
      c.continueResource();
      expect(c.state.section, PoolSection.pricing);
      expect(await c.finishResource(), isTrue);
      expect(repository.writes, 0);
      expect(source.configuration, isNull);
      expect(c.state.resourceFlow, isFalse);
      expect(await c.activate(), isFalse);
      expect(repository.activations, 0);
      expect(c.state.message, contains('group offer or a plan'));
    },
  );

  test(
    'pool flow keeps selection, validates completion and adds another without a cloud save',
    () async {
      final source = PoolSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final repository = FakePoolRepository(source);
      final c = PoolSetupCubit(workspace, repository, 'swimming');
      addTearDown(c.close);
      addTearDown(workspace.close);
      c.addPool();
      final first = c.state.selectedId!;
      expect(c.state.resourceFlow, isTrue);
      expect(await c.finishResource(addAnother: true), isFalse);
      expect(repository.writes, 0);
      expect(c.state.draft.pools, hasLength(1));
      configurePool(c, first);
      c.continueResource();
      expect(c.state.section, PoolSection.pricing);
      expect(c.state.selectedId, first);
      c.back();
      expect(c.state.section, PoolSection.pools);
      expect(c.state.selectedId, first);
      c.continueResource();
      expect(await c.finishResource(addAnother: true), isTrue);
      final second = c.state.selectedId!;
      expect(second, isNot(first));
      expect(repository.writes, 0);
      expect(source.configuration, isNull);
      expect(c.state.section, PoolSection.pools);
      expect(c.state.resourceFlow, isTrue);
      configurePool(c, second);
      c.continueResource();
      // Continuing remains local, even if a newer cloud version exists.
      source.version++;
      expect(await c.finishResource(addAnother: true), isTrue);
      expect(c.state.draft.pools, hasLength(3));
      expect(repository.writes, 0);
      // Final Save detects the conflict and keeps all local resources.
      expect(await c.saveChanges(), isFalse);
      expect(c.state.draft.pools, hasLength(3));
    },
  );

  test('Booking group bounds match the pool offer rules', () {
    BookingOption option(String mode) => BookingOption(
      id: 'offer',
      name: 'Group',
      kind: 'group',
      durations: const [60],
      defaultDuration: 60,
      groupMode: mode,
      groupPeople: 15,
    );
    expect(option('at_least').acceptsPeople(14), isFalse);
    expect(option('at_least').acceptsPeople(15), isTrue);
    expect(option('at_least').acceptsPeople(20), isTrue);
    expect(option('exact').acceptsPeople(16), isFalse);
    expect(option('up_to').acceptsPeople(14), isTrue);
    expect(option('up_to').acceptsPeople(16), isFalse);
  });
  test(
    'Group sizes preserve all modes and reject minimum above pool capacity',
    () {
      final pool = PoolResource(
        id: 'pool',
        name: 'Pool A',
        capacity: '20',
        minDepth: '3',
        maxDepth: '5',
      );
      for (final mode in ['exact', 'up_to', 'at_least']) {
        final offer = PoolGroupOffer(
          id: 'group',
          poolIds: ['pool'],
          mode: mode,
          people: '15',
          price: '2500',
        );
        final config = PoolConfiguration(pools: [pool], offers: [offer]);
        expect(config.validate(), isNull);
        final restored = PoolConfiguration.fromJson(config.toJson());
        expect(restored.offers.single.mode, mode);
        if (mode == 'at_least') {
          expect(restored.offers.single.sizeLabel, '15+ people');
          expect(
            restored.offers.single.sizeExplanation,
            contains('15 or more'),
          );
          expect(
            PoolConfiguration(
              pools: [pool],
              offers: [offer.copyWith(people: '21')],
            ).validate(),
            contains('capacity'),
          );
        }
      }
    },
  );
  test(
    'Pool graph round trips custom attendance allowances, separate expiry and group modes',
    () {
      final pool = PoolResource(
        id: 'pool',
        name: 'Pool A',
        capacity: '20',
        minDepth: '3',
        maxDepth: '5',
      );
      final c = PoolConfiguration(
        pools: [pool],
        offers: [
          PoolGroupOffer(
            id: 'offer',
            poolIds: ['pool'],
            mode: 'exact',
            people: '15',
            price: '2500',
          ),
        ],
        plans: [
          PoolPlan(
            id: 'plan',
            kind: 'swimming',
            poolIds: ['pool'],
            allowance: '12',
            expiryMode: 'fixed_date',
            expiryDate: '2030-12-31',
            price: '3000',
          ),
        ],
      );
      final restored = PoolConfiguration.fromJson(c.toJson());
      expect(restored.plans.single.allowance, '12');
      expect(restored.plans.single.expiryDate, '2030-12-31');
      expect(restored.plans.single.toJson()['expiry_days'], isNull);
      expect(restored.plans.single.toJson()['renewal'], 'none');
      expect(restored.offers.single.mode, 'exact');
      expect(restored.offers.single.toJson()['price_minor'], 250000);
      expect(restored.pools.single.capacity, '20');
    },
  );
  test(
    'Pool copy changes only timing/pricing and preserves capacities, depths and independent IDs',
    () async {
      final source = PoolSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final c = PoolSetupCubit(
        workspace,
        FakePoolRepository(source),
        'swimming',
      );
      c.addPool();
      final first = c.state.selectedPool!.id;
      configurePool(c, first);
      c.addPool();
      final second = c.state.selectedPool!.id;
      c.updatePool(
        second,
        (p) => p.copyWith(capacity: '50', minDepth: '4', maxDepth: '8'),
      );
      c.copyPricing(first, [second]);
      final a = c.state.draft.pools.first, b = c.state.draft.pools.last;
      expect(b.capacity, '50');
      expect(b.minDepth, '4');
      expect(b.maxDepth, '8');
      expect(b.tariffs.single.rates.single.minor, 20000);
      expect(b.tariffs.single.id, isNot(a.tariffs.single.id));
      expect(c.state.draft.validate(complete: true), isNull);
      await c.close();
      await workspace.close();
    },
  );
  test(
    'Pool validation distinguishes seasonal overrides from conflicting rules and rejects excessive groups',
    () {
      final hours = PoolHours();
      final tariff = PoolTariff(
        id: 'weekly',
        hours: hours,
        rates: const [PoolRate(60, '200')],
      );
      final pool = PoolResource(
        id: 'pool',
        name: 'Pool A',
        minDepth: '3',
        maxDepth: '5',
        tariffs: [tariff],
      );
      final seasonal = tariff.copyWith(
        id: 'seasonal',
        hours: hours.copyWith(dateFrom: '2026-10-17', dateUntil: '2026-10-18'),
      );
      var c = PoolConfiguration(
        pools: [
          pool.copyWith(tariffs: [tariff, seasonal]),
        ],
      );
      expect(c.validate(complete: true), isNull);
      c = c.copyWith(
        pools: [
          pool.copyWith(
            tariffs: [
              tariff,
              tariff.copyWith(id: 'duplicate'),
            ],
          ),
        ],
      );
      expect(c.validate(), contains('overlap'));
      c = PoolConfiguration(
        pools: [pool],
        offers: [
          PoolGroupOffer(
            id: 'group',
            poolIds: ['pool'],
            people: '21',
            price: '2500',
          ),
        ],
      );
      expect(c.validate(), contains('capacity'));
      expect(
        PoolConfiguration(pools: [pool.copyWith(minDepth: '7')]).validate(),
        contains('depth'),
      );
    },
  );
  test(
    'Legacy import retains resource IDs and does not turn subscription prices into admission prices',
    () {
      final b = Business(
        id: 'legacy',
        name: 'Swimming',
        type: BusinessType.pool,
        status: 'ready',
        locationId: 'loc',
        version: 2,
        resources: const [
          Resource(id: 'existing', name: 'Original Pool', capacity: 50),
        ],
        configuration: const {
          'opens_at': '06:00',
          'closes_at': '23:00',
          'days': [1, 2, 3, 4, 5, 6, 7],
          'plan_name': 'Old unlimited',
          'price_minor': 150000,
          'validity_days': 30,
          'entitlement': 'unlimited',
          'visit_limit': null,
        },
      );
      final c = PoolConfiguration.initial(b);
      expect(c.pools.single.id, 'existing');
      expect(c.pools.single.capacity, '50');
      expect(c.pools.single.tariffs, isEmpty);
      expect(c.plans.single.price, '1500.00');
      expect(c.plans.single.enabled, false);
      expect(c.validate(complete: true), contains('depth'));
    },
  );
  test(
    'Pool saves reconcile lost responses and consecutive active edits use current versions',
    () async {
      final source = PoolSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final repository = FakePoolRepository(source)..loseSave = true;
      final c = PoolSetupCubit(workspace, repository, 'swimming');
      c.addPool();
      final id = c.state.selectedPool!.id;
      configurePool(c, id);
      expect(await c.saveChanges(), true);
      expect(repository.writes, 1);
      expect(c.state.dirty, false);
      repository.loseSave = false;
      repository.loseActivation = true;
      expect(await c.activate(), true);
      repository.loseActivation = false;
      expect(c.state.business!.ready, true);
      c.updatePool(id, (p) => p.copyWith(capacity: '50'));
      expect(await c.saveChanges(), true);
      expect(c.state.version, c.state.business!.version);
      c.updatePool(id, (p) => p.copyWith(name: 'Renamed Pool'));
      expect(await c.saveChanges(), true);
      expect(repository.writes, 3);
      expect(repository.activations, 3);
      expect(c.state.business!.ready, true);
      await c.close();
      await workspace.close();
    },
  );
  test('Pool conflicts keep edits until an explicit reload', () async {
    final source = PoolSource();
    final session = WorkspaceCubit(source);
    await session.load();
    final c = PoolSetupCubit(session, FakePoolRepository(source), 'swimming');
    c.addPool();
    configurePool(c, c.state.selectedPool!.id);
    expect(await c.saveChanges(), true);
    c.updatePool(
      c.state.draft.pools.first.id,
      (p) => p.copyWith(name: 'Local edit'),
    );
    source.version++;
    expect(await c.saveChanges(), false);
    expect(c.state.dirty, true);
    expect(c.state.draft.pools.first.name, 'Local edit');
    await c.reloadSaved();
    expect(c.state.dirty, false);
    expect(c.state.draft.pools.first.name, 'Pool 1');
    await c.close();
    await session.close();
  });
  testWidgets(
    'Pool configuration edits every section and activates at 320px with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = PoolSource();
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      await getIt.unregister<PoolRepository>();
      final repository = FakePoolRepository(source);
      getIt.registerSingleton<PoolRepository>(repository);
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
              home: const PoolSetupScreen(businessId: 'swimming'),
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

      Future<void> section(PoolSection s) async {
        final f = find.byKey(ValueKey('pool-section-${s.name}'));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await section(PoolSection.pools);
      await tap('Add pool');
      await enter('Minimum depth · feet', '3');
      await enter('Maximum depth · feet', '5');
      await tap('Continue to timing & pricing');
      await tap('Add time-based price');
      await enter('60-minute price per person · INR', '200');
      await tap('Continue & add another pool');
      expect(source.configuration, isNull);
      await enter('Maximum people at the same time', '50');
      await enter('Minimum depth · feet', '4');
      await enter('Maximum depth · feet', '8');
      await tap('Continue to timing & pricing');
      await tap('Add time-based price');
      await enter('60-minute price per person · INR', '200');
      await tap('Continue');
      expect(source.configuration, isNull);
      expect(
        tester
            .widget<PoolResourcesScreen>(find.byType(PoolResourcesScreen))
            .cubit
            .state
            .draft
            .pools
            .length,
        2,
      );
      await tap('All Pool settings');
      await section(PoolSection.groups);
      await tap('Add group offer');
      final nameField = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is ConfigurationField && w.label == 'Group offer name',
        ),
        matching: find.byType(TextFormField),
      );
      final nameElement = tester.element(nameField);
      await enter('Group offer name', 'F');
      expect(identical(tester.element(nameField), nameElement), isTrue);
      await enter('Group offer name', 'Family 15');
      expect(identical(tester.element(nameField), nameElement), isTrue);
      await enter('Total group price · INR', '2500');
      await tap('Continue');
      await tap('All Pool settings');
      await section(PoolSection.plans);
      await tap('Add swimming plan');
      final allowance = find.descendant(
        of: find.byWidgetPredicate(
          (w) =>
              w is ConfigurationField &&
              w.label == 'Attendance days · custom count',
        ),
        matching: find.byType(TextFormField),
      );
      expect(tester.widget<TextFormField>(allowance).controller!.text, '25');
      await enter('Attendance days · custom count', '12');
      await enter('Number of days', '60');
      await enter('Total plan price · INR', '3000');
      await tap('Continue');
      await tap('All Pool settings');
      await section(PoolSection.coaching);
      await tap('Add coaching plan');
      await enter('Number of classes', '10');
      await tap('Days from activation');
      await tap('Months from activation');
      await enter('Number of months', '3');
      await enter('Total plan price · INR', '4000');
      expect(find.text('Add coach'), findsNothing);
      expect(find.text('Unassigned'), findsOneWidget);

      await tap('Continue');
      await tap('All Pool settings');
      await section(PoolSection.review);
      await tap('Activate pools');
      expect(source.status, 'ready');
      await section(PoolSection.pools);
      final existingId = source.configuration!['pools'][0]['id'];
      final existing = find.byKey(ValueKey('pool-item-$existingId'));
      await tester.ensureVisible(existing);
      await tester.pumpAndSettle();
      await tester.tap(existing);
      await tester.pumpAndSettle();
      expect(find.text('Continue to timing & pricing'), findsNothing);
      expect(find.text('Edit timing & pricing'), findsOneWidget);
      await enter('Pool name', 'Main pool');
      await tap('Continue');
      expect(source.status, 'ready');
      await tap('All Pool settings');

      await tap('Save changes');
      expect(source.configuration!['pools'].length, 2);
      expect(source.configuration!['pools'][0]['name'], 'Main pool');
      expect(source.configuration!['plans'].length, 2);
      expect(source.configuration!['plans'][0]['allowance'], 12);
      expect(source.configuration!['plans'][0]['expiry_days'], 60);
      expect(source.configuration!['group_offers'][0]['price_minor'], 250000);
      expect(repository.activations, 2);
    },
  );
}

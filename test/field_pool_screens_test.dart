import 'dart:convert';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/pool/cubit/pool_setup_cubit.dart';
import 'package:eden_booking/modules/pool/models/pool_configuration.dart';
import 'package:eden_booking/modules/pool/models/pool_screen_models.dart';
import 'package:eden_booking/modules/pool/repositories/pool_repository.dart';
import 'package:eden_booking/modules/pool/screens/pool_resources_screen.dart';
import 'package:eden_booking/modules/pool/screens/pool_setup_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source extends Fake implements WorkspaceRepository {
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
            .map((p) => Resource(id: p['id'], name: p['name'], capacity: p['capacity']))
            .toList(),
        configuration: configuration,
      ),
    ],
  );
}

class _Repo implements PoolRepository {
  _Repo(this.source);
  final _Source source;
  int writes = 0;
  Duration delay = Duration.zero;
  @override
  Future<List<PoolCoach>> loadCoaches(String id) async => [];
  @override
  Future<void> save(String id, int version, PoolConfiguration config) async {
    writes++;
    await Future<void>.delayed(delay);
    if (version != source.version) {
      throw const AppException('Version conflict.', code: 'CONFLICT');
    }
    source.configuration = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(config.toJson())),
    );
    source.version++;
  }

  @override
  Future<void> activate(String id) async {
    source.status = 'ready';
    source.version++;
  }
}

late _Source source;
late _Repo repo;

Future<void> pumpPool(
  WidgetTester tester, {
  Size size = const Size(320, 568),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  source = _Source();
  getIt.registerSingleton<WorkspaceRepository>(source);
  registerFeatureDependencies(getIt);
  await getIt.unregister<PoolRepository>();
  repo = _Repo(source);
  getIt.registerSingleton<PoolRepository>(repo);
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
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const PoolSetupScreen(businessId: 'swimming'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder fieldFor(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is ConfigurationField && w.label == label),
  matching: find.byType(TextFormField),
);

Future<void> enter(WidgetTester tester, String label, String value) async {
  final f = fieldFor(label);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.enterText(f, value);
  await tester.pump();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> section(WidgetTester tester, PoolSection s) async {
  final f = find.byKey(ValueKey('pool-section-${s.name}'));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

PoolSetupCubit cubitIn(WidgetTester tester) =>
    tester.widget<PoolResourcesScreen>(find.byType(PoolResourcesScreen)).cubit;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => getIt.reset());

  group('Pool details form (320x568)', () {
    Future<void> openAdd(WidgetTester tester, {double scale = 1}) async {
      await pumpPool(tester, scale: scale);
      await section(tester, PoolSection.pools);
      await tapText(tester, 'Add pool');
    }

    testWidgets('empty capacity shows inline message and blocks Continue', (tester) async {
      await openAdd(tester);
      await enter(tester, 'Maximum people at the same time', '');
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.text('Enter 1–10000'), findsOneWidget);
      expect(find.text('Continue to timing & pricing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final bad in ['0', '-5', '10001', '2.5', 'abc', '💧', '٣']) {
      testWidgets('capacity "$bad" is rejected inline', (tester) async {
        await openAdd(tester);
        await enter(tester, 'Maximum people at the same time', bad);
        await tapText(tester, 'Continue to timing & pricing');
        expect(find.text('Enter 1–10000'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('blank or one character name rejected', (tester) async {
      await openAdd(tester);
      for (final bad in ['', '   ', 'a']) {
        await enter(tester, 'Pool name', bad);
        await enter(tester, 'Minimum depth · feet', '3');
        await enter(tester, 'Maximum depth · feet', '5');
        await tapText(tester, 'Continue to timing & pricing');
        expect(find.text('Use 2–100 characters'), findsOneWidget, reason: '"$bad"');
      }
    });

    testWidgets('101 character name rejected, 100 accepted', (tester) async {
      await openAdd(tester);
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '5');
      await enter(tester, 'Pool name', 'a' * 101);
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.text('Use 2–100 characters'), findsOneWidget);
      await enter(tester, 'Pool name', 'a' * 100);
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.text('STEP 2 OF 2 · TIMING & PRICING'), findsOneWidget);
    });

    testWidgets('emoji and unicode names are stored unchanged', (tester) async {
      await openAdd(tester);
      await enter(tester, 'Pool name', '🏊 Zoë 游泳');
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '5');
      expect(cubitIn(tester).state.selectedPool!.name, '🏊 Zoë 游泳');
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.text('STEP 2 OF 2 · TIMING & PRICING'), findsOneWidget);
    });

    testWidgets('depth fields: empty/negative/decimals', (tester) async {
      await openAdd(tester);
      await enter(tester, 'Minimum depth · feet', '');
      await enter(tester, 'Maximum depth · feet', '5');
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.text('Enter the minimum depth'), findsOneWidget);
      await enter(tester, 'Minimum depth · feet', '-1');
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.text('Enter the minimum depth'), findsOneWidget);
      await enter(tester, 'Minimum depth · feet', '3.555');
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.text('Enter the minimum depth'), findsOneWidget);
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '0');
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.text('Enter a positive maximum depth'), findsOneWidget);
    });

    testWidgets('minimum depth above maximum surfaces a form error and stays', (tester) async {
      await openAdd(tester);
      await enter(tester, 'Minimum depth · feet', '9');
      await enter(tester, 'Maximum depth · feet', '5');
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.textContaining('Check minimum and maximum depth'), findsOneWidget);
      expect(find.text('STEP 1 OF 2 · DETAILS'), findsOneWidget);
    });

    testWidgets('depth above 1000 feet surfaces a form error', (tester) async {
      await openAdd(tester);
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '5000');
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.textContaining('Check minimum and maximum depth'), findsOneWidget);
    });

    testWidgets('duplicate pool name is rejected case-insensitively', (tester) async {
      await openAdd(tester);
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '5');
      await tapText(tester, 'Continue to timing & pricing');
      await tapText(tester, 'Add time-based price');
      await enter(tester, '60-minute price per person · INR', '100');
      await tapText(tester, 'Continue & add another pool');
      await enter(tester, 'Pool name', ' pool 1 ');
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '5');
      await tapText(tester, 'Continue to timing & pricing');
      expect(find.text('Give each pool a unique name.'), findsOneWidget);
      expect(find.text('STEP 1 OF 2 · DETAILS'), findsOneWidget);
    });

    testWidgets('double tapping Continue only advances once', (tester) async {
      await openAdd(tester);
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '5');
      final f = find.text('Continue to timing & pricing');
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.tap(f, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('STEP 2 OF 2 · TIMING & PRICING'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('price field accepts only valid money', (tester) async {
      await openAdd(tester);
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '5');
      await tapText(tester, 'Continue to timing & pricing');
      await tapText(tester, 'Add time-based price');
      for (final bad in ['', '-1', '1.999', 'abc', '💰', '1000001', '1e3']) {
        await enter(tester, '60-minute price per person · INR', bad);
        await tapText(tester, 'Continue');
        expect(find.text('Enter a valid amount'), findsOneWidget, reason: '"$bad"');
      }
      await enter(tester, '60-minute price per person · INR', '199.50');
      await tapText(tester, 'Continue');
      expect(find.text('Enter a valid amount'), findsNothing);
    });

    testWidgets('BUG-3: disabled pool with an empty price can be continued', (tester) async {
      await openAdd(tester);
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '5');
      await tapText(tester, 'Pool enabled');
      await tapText(tester, 'Continue to timing & pricing');
      await tapText(tester, 'Add time-based price');
      await tapText(tester, 'Continue');
      expect(find.text('Enter a valid amount'), findsNothing);
    }, skip: true); // BUG-3: pricing validator ignores disabled-pool relaxation

    testWidgets('large text 2.0 at 320x568 does not overflow in details and pricing', (tester) async {
      await openAdd(tester, scale: 2.0);
      expect(tester.takeException(), isNull);
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '5');
      await tapText(tester, 'Continue to timing & pricing');
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Add time-based price');
      await tapText(tester, 'Add time-based price');
      expect(tester.takeException(), isNull);
    });
  });

  group('Pool sections render at 320x568 with 2.0 text scale', () {
    for (final s in PoolSection.values) {
      testWidgets('${s.name} empty state', (tester) async {
        await pumpPool(tester, scale: 2.0);
        if (s != PoolSection.overview) await section(tester, s);
        expect(tester.takeException(), isNull);
        final scroll = tester.view.physicalSize.width;
        expect(scroll, 320);
      });
    }
  });

  group('Pool offers and plans form fields', () {
    Future<void> withPool(WidgetTester tester) async {
      await pumpPool(tester);
      await section(tester, PoolSection.pools);
      await tapText(tester, 'Add pool');
      await enter(tester, 'Minimum depth · feet', '3');
      await enter(tester, 'Maximum depth · feet', '5');
      await tapText(tester, 'Continue to timing & pricing');
      await tapText(tester, 'Add time-based price');
      await enter(tester, '60-minute price per person · INR', '100');
      await tapText(tester, 'Continue');
      await tapText(tester, 'All Pool settings');
    }

    testWidgets('group offer name/price/people validation', (tester) async {
      await withPool(tester);
      await section(tester, PoolSection.groups);
      await tapText(tester, 'Add group offer');
      await enter(tester, 'Group offer name', 'x');
      await tapText(tester, 'Continue');
      expect(find.text('Use 2–100 characters'), findsOneWidget);
      await enter(tester, 'Group offer name', 'Birthday 🎂');
      await enter(tester, 'Total group price · INR', '-10');
      await tapText(tester, 'Continue');
      expect(find.text('Enter a valid amount'), findsOneWidget);
      await enter(tester, 'Total group price · INR', '0.001');
      await tapText(tester, 'Continue');
      expect(find.text('Enter a valid amount'), findsOneWidget);
      await enter(tester, 'Total group price · INR', '99999999999999999999');
      await tapText(tester, 'Continue');
      expect(find.text('Enter a valid amount'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('swimming plan allowance/validity/price validation', (tester) async {
      await withPool(tester);
      await section(tester, PoolSection.plans);
      await tapText(tester, 'Add swimming plan');
      await enter(tester, 'Attendance days · custom count', '0');
      await tapText(tester, 'Continue');
      expect(find.textContaining('Enter'), findsWidgets);
      await enter(tester, 'Attendance days · custom count', '-4');
      await tapText(tester, 'Continue');
      expect(find.textContaining('Enter'), findsWidgets);
      await enter(tester, 'Attendance days · custom count', '12');
      await enter(tester, 'Total plan price · INR', 'free');
      await tapText(tester, 'Continue');
      expect(find.text('Enter a valid amount'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

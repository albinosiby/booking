import 'package:eden_booking/modules/businesses/cubit/business_management_cubit.dart';
import 'package:eden_booking/modules/businesses/repositories/business_repository.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/businesses/screens/business_detail_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'business_management_test.dart' show ManagementSource;
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/businesses/repositories/business_details_mapper.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';

Business business(String kind, {Map<String, dynamic>? configuration}) =>
    Business(
      id: 'business',
      name: 'Eden $kind',
      type: switch (kind) {
        'court' => BusinessType.badminton,
        'pool' => BusinessType.pool,
        'hall' => BusinessType.hall,
        _ => BusinessType.turf,
      },
      status: 'ready',
      locationId: 'location',
      version: 1,
      resources: const [
        Resource(id: 'space', name: 'Saved space', capacity: 20),
      ],
      configuration: configuration,
    );
Map<String, dynamic> config(String kind) => Map<String, dynamic>.from(
  jsonDecode(
    File('backend/examples/$kind-configuration.json').readAsStringSync(),
  )['configuration'],
);
void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('BUSINESS_DETAIL_PREVIEWS')) {
      for (final font in [
        ('DetailPreview', 'backend/assets/fonts/NotoSans-Regular.ttf'),
        ('Roboto', '/tmp/home-preview-fonts/Roboto-Regular.ttf'),
        ('MaterialIcons', '/tmp/home-preview-fonts/MaterialIcons-Regular.otf'),
      ]) {
        final file = File(font.$2);
        if (file.existsSync()) {
          final loader = FontLoader(font.$1)
            ..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            );
          await loader.load();
        }
      }
    }
  });
  for (final kind in ['court', 'pool', 'hall', 'turf']) {
    testWidgets('$kind business details expand at accessible sizes', (
      tester,
    ) async {
      final width = kind == 'turf' ? 1200.0 : 320.0;
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await getIt.reset();
      final saved = business(kind, configuration: config(kind));
      final source = ManagementSource()..businesses = [saved];
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      final session = WorkspaceCubit(source);
      await session.load();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const BusinessDetailScreen(id: 'business'),
          ),
          GoRoute(
            path: '/businesses/:id/settings',
            builder: (_, _) =>
                const Scaffold(body: Text('Configuration destination')),
          ),
        ],
      );
      final boundary = GlobalKey();
      ThemeData theme() {
        final base = AppTheme.build(
          kind == 'pool' ? Brightness.dark : Brightness.light,
        );
        return const bool.fromEnvironment('BUSINESS_DETAIL_PREVIEWS')
            ? base.copyWith(
                textTheme: base.textTheme.apply(fontFamily: 'DetailPreview'),
                filledButtonTheme: FilledButtonThemeData(
                  style: base.filledButtonTheme.style?.copyWith(
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              )
            : base;
      }

      await tester.pumpWidget(
        BlocProvider.value(
          value: session,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp.router(
              theme: theme(),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
                ),
                child: RepaintBoundary(key: boundary, child: child!),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('BUSINESS_DETAIL_PREVIEWS')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/business-details-$kind.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final entry = find.byType(ExpansionTile).first;
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('BUSINESS_DETAIL_PREVIEWS')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/business-details-$kind-expanded.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.text('Opening hours'), findsWidgets);
      expect(find.text('Business information'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (kind == 'court') {
        await tester.ensureVisible(find.text('Rename business'));
        await tester.tap(find.text('Rename business'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Renamed court');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(source.businesses.single.name, 'Renamed court');
        await tester.ensureVisible(find.text('Configure business'));
        await tester.tap(find.text('Configure business'));
        await tester.pumpAndSettle();
        expect(find.text('Configuration destination'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await session.close();
      await getIt.reset();
    });
  }

  for (final kind in ['court', 'pool', 'hall', 'turf']) {
    test('$kind details display saved spaces, schedules and prices', () {
      final details = describeBusiness(
        business(kind, configuration: config(kind)),
        'INR',
      );
      expect(details.notice, isNull);
      expect(details.spaceCount, greaterThan(0));
      final entries = details.sections.expand((s) => s.entries).toList();
      expect(entries, isNotEmpty);
      expect(
        entries.expand((e) => e.fields).any((f) => f.label.contains('hours')),
        isTrue,
      );
      final prices = entries
          .expand((e) => e.prices)
          .expand((g) => g.rates)
          .toList();
      expect(prices, isNotEmpty);
      expect(prices.any((r) => r.value.contains('₹')), isTrue);
    });
  }
  test(
    'detail state refreshes saved configuration and clears when owner access is lost',
    () async {
      final source = ManagementSource()
        ..businesses = [business('court', configuration: config('court'))];
      final session = WorkspaceCubit(source);
      await session.load();
      final cubit = BusinessManagementCubit(
        session,
        LocalApiBusinessRepository(source),
      );
      expect(cubit.state.details, isEmpty);
      cubit.showDetails('business');
      expect(cubit.state.details['business']!.spaceCount, 3);
      source.businesses = [business('pool', configuration: config('pool'))];
      await cubit.reload();
      await Future<void>.delayed(Duration.zero);
      expect(
        cubit.state.details['business']!.sections.first.title,
        'Pools & admission prices',
      );
      source.owner = false;
      await cubit.reload();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.details, isEmpty);
      await cubit.close();
      await session.close();
    },
  );
  test(
    'pool offers and plans retain allowance, expiry and capacity details',
    () {
      final details = describeBusiness(
        business('pool', configuration: config('pool')),
        'INR',
      );
      final fields = details.sections
          .expand((s) => s.entries)
          .expand((e) => e.fields)
          .toList();
      expect(fields.any((f) => f.label == 'Depth'), isTrue);
      expect(fields.any((f) => f.label == 'Expiry'), isTrue);
      expect(fields.any((f) => f.label == 'Group size'), isTrue);
    },
  );
  test(
    'disabled courts and seasonal prices remain visible without changing configuration',
    () {
      final c = config('court');
      final before = jsonEncode(c);
      final courts = c['courts'] as List;
      courts.first['enabled'] = false;
      final snapshot = jsonEncode(c);
      final details = describeBusiness(
        business('court', configuration: c),
        'AED',
      );
      expect(details.sections.first.entries.first.enabled, isFalse);
      expect(details.enabledCount, details.spaceCount - 1);
      expect(
        details.sections.first.entries.first.prices.first.rates.first.value,
        startsWith('AED '),
      );
      expect(jsonEncode(c), snapshot);
      expect(before, isNot(snapshot));
    },
  );
  test(
    'missing, unsupported and malformed configurations do not invent operating hours or prices',
    () {
      for (final c in [
        null,
        <String, dynamic>{'kind': 'legacy'},
        <String, dynamic>{'kind': 'pool_v1', 'pools': 'invalid'},
      ]) {
        final details = describeBusiness(
          business('pool', configuration: c),
          'INR',
        );
        expect(details.notice, isNotNull);
        expect(details.sections.first.entries.single.name, 'Saved space');
        expect(details.sections.first.entries.single.prices, isEmpty);
        expect(
          details.sections.first.entries.single.fields.any(
            (f) => f.label == 'Opening hours',
          ),
          isFalse,
        );
      }
    },
  );
}

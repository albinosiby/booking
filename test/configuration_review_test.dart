import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/turf/models/turf_configuration.dart';
import 'package:eden_booking/modules/turf/models/turf_step_models.dart';
import 'package:eden_booking/modules/turf/screens/turf_review_screen.dart';
import 'package:eden_booking/modules/turf/widgets/football_ground_diagram.dart';
import 'package:eden_booking/modules/turf/widgets/cricket_ground_diagram.dart';
import 'package:eden_booking/modules/court/models/court_configuration.dart';
import 'package:eden_booking/modules/court/models/court_screen_models.dart';
import 'package:eden_booking/modules/court/screens/court_review_screen.dart';
import 'package:eden_booking/modules/pool/models/pool_configuration.dart';
import 'package:eden_booking/modules/pool/models/pool_screen_models.dart';
import 'package:eden_booking/modules/pool/screens/pool_review_screen.dart';
import 'package:eden_booking/modules/hall/models/hall_configuration.dart';
import 'package:eden_booking/modules/hall/models/hall_screen_models.dart';
import 'package:eden_booking/modules/hall/screens/hall_review_screen.dart';

const previewKey = ValueKey('review-preview');
Future<void> pumpReview(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(320, 800),
  double scale = 1.7,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(
        theme: const bool.fromEnvironment('REVIEW_PREVIEWS')
            ? darkTheme().copyWith(
                textTheme: darkTheme().textTheme.apply(fontFamily: 'Roboto'),
              )
            : darkTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: RepaintBoundary(
            key: previewKey,
            child: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> preview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('REVIEW_PREVIEWS')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(previewKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.local/review-previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

TurfConfiguration sampleTurf() {
  final config = TurfConfiguration.initial(null);
  return config.copyWith(
    operating: TurfHours(opens: '00:00', closes: '00:00', allDay: true),
    offerings: config.offerings.map(
      (o) => o.copyWith(
        rates: const [TurfRate(60, '600')],
        pricingRules: [
          TurfPriceBand(
            id: 'band-${o.id}',
            days: const [1, 2, 3, 4, 5, 6, 7],
            opens: '00:00',
            closes: '00:00',
            allDay: true,
            rates: const [TurfRate(60, '600')],
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    // Optional local visual previews use SDK fonts; ordinary tests stay portable.
    final fontDir = Platform.environment['REVIEW_FONT_DIR'];
    if (!const bool.fromEnvironment('REVIEW_PREVIEWS') || fontDir == null) {
      return;
    }
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File('$fontDir/${entry.value}').readAsBytes();
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  testWidgets(
    'sport diagrams describe split and single arrangements accessibly at narrow widths',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpReview(
        tester,
        const Column(
          children: [
            FootballGroundDiagram(split: true),
            CricketGroundDiagram(split: true),
            FootballGroundDiagram(split: false),
            CricketGroundDiagram(split: false),
          ],
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Football ground: Half A and Half B combine into Full Ground',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Cricket ground: one undivided ground'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await pumpReview(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Football · two halves + full ground'),
            const SizedBox(height: 12),
            const FootballGroundDiagram(split: true),
            const SizedBox(height: 24),
            const Text('Cricket · two halves + full ground'),
            const SizedBox(height: 12),
            const CricketGroundDiagram(split: true),
            const SizedBox(height: 24),
            const Text('Single grounds · no half-court markings'),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: FootballGroundDiagram(split: false)),
                SizedBox(width: 16),
                Expanded(child: CricketGroundDiagram(split: false)),
              ],
            ),
          ],
        ),
        size: const Size(540, 1160),
        scale: 1,
      );
      await preview(tester, 'sport-grounds');
    },
  );

  testWidgets(
    'turf review shows full-day prices and direct editing without mutating configuration',
    (tester) async {
      final c = sampleTurf();
      final before = c.toJson();
      String? edited;
      final screen = TurfReviewScreen(
        model: TurfReviewScreenModel(c),
        currency: 'INR',
        businessName: 'Eden Turf',
        onEditOffering: (id) => edited = id,
      );
      await pumpReview(tester, screen);
      expect(find.text('Ready to apply'), findsOneWidget);
      expect(find.text('Every day · Open 24 hours'), findsWidgets);
      expect(find.textContaining('24:00–24:00'), findsNothing);
      expect(find.text('₹ 600'), findsWidgets);
      final edit = find.byTooltip(
        'Edit ${c.layouts.first.name} · ${c.offerings.first.format}',
      );
      await tester.ensureVisible(edit.first);
      await tester.tap(edit.first);
      await tester.pumpAndSettle();
      expect(edited, c.offerings.first.id);
      expect(c.toJson(), before);
      expect(tester.takeException(), isNull);
      await pumpReview(tester, screen, size: const Size(390, 844), scale: 1);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 10000),
      );
      await tester.pumpAndSettle();
      await preview(tester, 'turf-summary');
    },
  );

  testWidgets(
    'court pool and hall summaries fit large text and preserve distinct price units',
    (tester) async {
      final hours = CourtHours(opens: '00:00', closes: '00:00', allDay: true);
      String? edited;
      await pumpReview(
        tester,
        CourtReviewScreen(
          model: CourtReviewModel(
            CourtConfiguration(
              courts: [
                CourtResource(
                  id: 'court',
                  name: 'Basketball Court 1',
                  environment: 'outdoor',
                  hours: hours,
                  tariffs: [
                    CourtTariff(
                      id: 't',
                      hours: hours,
                      rates: const [CourtRate(60, '650')],
                    ),
                  ],
                ),
              ],
            ),
            'INR',
          ),
          onEditPricing: (id) => edited = id,
        ),
      );
      expect(find.text('Price per court'), findsOneWidget);
      expect(find.text('Every day · Open 24 hours'), findsWidgets);
      await tester.ensureVisible(find.byTooltip('Edit Opening hours'));
      await tester.tap(find.byTooltip('Edit Opening hours'));
      expect(edited, 'court');
      expect(tester.takeException(), isNull);
      final poolHours = PoolHours(
        opens: '00:00',
        closes: '00:00',
        allDay: true,
      );
      final pool = PoolConfiguration(
        pools: [
          PoolResource(
            id: 'pool',
            name: 'Main Pool',
            minDepth: '3',
            maxDepth: '6',
            hours: poolHours,
            tariffs: [
              PoolTariff(
                id: 'pool-t',
                hours: poolHours,
                rates: const [PoolRate(60, '100')],
              ),
            ],
          ),
        ],
      );
      await pumpReview(
        tester,
        PoolReviewScreen(model: PoolReviewModel(pool, 'INR')),
      );
      expect(find.text('Price per person'), findsOneWidget);
      expect(find.text('₹ 100'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final hall = HallConfiguration(
        halls: [
          HallResource(
            id: 'hall',
            name: 'Garden Hall',
            tariffs: [
              HallTariff(
                id: 'hall-t',
                hours: HallHours(),
                rates: const [HallRate(60, '1000')],
              ),
            ],
            fullDay: HallPackage(
              id: 'full',
              name: 'Full day',
              enabled: true,
              hours: HallHours(opens: '09:00', closes: '23:00'),
              prices: [HallPackagePrice(id: 'full-rate', price: '15000')],
            ),
          ),
        ],
      );
      await pumpReview(
        tester,
        HallReviewScreen(model: HallReviewModel(hall, 'INR')),
      );
      expect(find.text('Hourly · price per hall'), findsOneWidget);
      expect(find.text('₹ 15000'), findsOneWidget);
      expect(find.text('Package total'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pool summary keeps attendance allowance expiry and group size separate',
    (tester) async {
      final c = PoolConfiguration(
        pools: [
          PoolResource(
            id: 'pool',
            name: 'Main Pool',
            minDepth: '3',
            maxDepth: '6',
            regularSwimming: false,
          ),
        ],
        offers: [
          PoolGroupOffer(
            id: 'group',
            name: 'Friends offer',
            poolIds: const ['pool'],
            mode: 'exact',
            people: '15',
            price: '2500',
          ),
        ],
        plans: [
          PoolPlan(
            id: 'plan',
            kind: 'swimming',
            poolIds: const ['pool'],
            allowance: '25',
            expiryDays: '45',
            price: '2000',
          ),
        ],
      );
      String? selected;
      await pumpReview(
        tester,
        PoolReviewScreen(
          model: PoolReviewModel(c, 'INR'),
          onEditPlan: (id) => selected = id,
        ),
      );
      expect(find.text('25 attendance days'), findsOneWidget);
      expect(find.text('45 calendar days from activation'), findsOneWidget);
      expect(find.text('Exactly 15 people · 60 min'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Edit Swimming plan'));
      await tester.tap(find.byTooltip('Edit Swimming plan'));
      expect(selected, 'plan');
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';

Widget scene(
  Widget child, {
  bool reduced = false,
  bool enabled = true,
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, _) => MaterialApp(
    theme: AppTheme.build(brightness).copyWith(
      textTheme: AppTheme.build(
        brightness,
      ).textTheme.apply(fontFamily: 'Roboto'),
    ),
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduced,
        textScaler: TextScaler.linear(scale),
      ),
      child: TickerMode(
        enabled: enabled,
        child: Scaffold(
          body: Center(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final bytes = await File(
      'backend/assets/fonts/NotoSans-Regular.ttf',
    ).readAsBytes();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
  testWidgets(
    'reduced motion keeps all loading labels and has no active ticker',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        scene(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLoadingState(initial: true),
              AppRefreshIndicator(),
              AppSavingIndicator(),
            ],
          ),
          reduced: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Getting things ready'), findsOneWidget);
      expect(find.text('Refreshing…'), findsOneWidget);
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.bySemanticsLabel('Refreshing…'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      semantics.dispose();
    },
  );

  testWidgets('inactive tabs stop motion and active tabs resume', (
    tester,
  ) async {
    await tester.pumpWidget(scene(const AppOrbitLoader()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(scene(const AppOrbitLoader(), enabled: false));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(scene(const AppOrbitLoader()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'busy actions show dots, keep their label and prevent duplicate taps',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        scene(
          AppButton(
            label: 'Confirm booking',
            busyLabel: 'Saving booking…',
            busy: true,
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(AppSavingDots), findsOneWidget);
      expect(find.text('Saving booking…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Saving booking…'));
      expect(taps, 0);
      await tester.pumpWidget(
        scene(AppButton(label: 'Confirm booking', onPressed: () => taps++)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm booking'));
      expect(taps, 1);
    },
  );

  testWidgets(
    'all variants fit narrow screens and enlarged text in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          scene(
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppLoadingState(initial: true),
                AppRefreshIndicator(),
                AppSavingIndicator(label: 'Saving bank account settings…'),
                AppButton(
                  label: 'Continue',
                  busyLabel: 'Saving booking…',
                  busy: true,
                ),
              ],
            ),
            reduced: true,
            brightness: brightness,
            scale: 1.8,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Refreshing…'), findsOneWidget);
      }
    },
  );

  testWidgets('orbit paints different frames without replacing page content', (
    tester,
  ) async {
    const key = ValueKey('motion-paint');
    await tester.pumpWidget(
      scene(const RepaintBoundary(key: key, child: AppOrbitLoader())),
    );
    await tester.pump();
    Future<List<int>> pixels() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    final before = await tester.runAsync(pixels);
    await tester.pump(const Duration(milliseconds: 225));
    final after = await tester.runAsync(pixels);
    expect(after, isNot(equals(before)));
  });

  testWidgets('render approved animation showcase for visual inspection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const key = ValueKey('animation-showcase');
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        scene(
          RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: brightness == Brightness.dark
                  ? const Color(0xFF0F0F0F)
                  : const Color(0xFFF8F8F8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppLoadingState(initial: true),
                    const SizedBox(height: 20),
                    const AppRefreshIndicator(),
                    const ListTile(
                      title: Text('Court 1 · Badminton'),
                      subtitle: Text('18:00 – 19:00 · Confirmed'),
                    ),
                    const SizedBox(height: 28),
                    const AppButton(
                      label: 'Confirm booking',
                      busyLabel: 'Saving booking…',
                      busy: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
          brightness: brightness,
        ),
      );
      await tester.pump(const Duration(milliseconds: 225));
      await tester.pump();
      await tester.runAsync(() async {
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final path = '.local/animation-previews/${brightness.name}.png';
        await File(path).parent.create(recursive: true);
        await File(path).writeAsBytes(data!.buffer.asUint8List());
      });
      expect(tester.takeException(), isNull);
    }
  });
}

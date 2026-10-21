import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';

Future<void> pumpHost(
  WidgetTester tester,
  Size size,
  Future<void> Function(BuildContext) onOpen,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onOpen(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('phones get a bottom sheet', (tester) async {
    String? result;
    await pumpHost(tester, const Size(390, 800), (context) async {
      result = await showAdaptiveSheet<String>(
        context: context,
        builder: (c) => ListTile(
          title: const Text('Pick me'),
          onTap: () => Navigator.pop(c, 'picked'),
        ),
      );
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('adaptive-sheet-dialog')), findsNothing);
    await tester.tap(find.text('Pick me'));
    await tester.pumpAndSettle();
    expect(result, 'picked');
  });

  testWidgets('wide windows get a dialog with a close button', (tester) async {
    String? result = 'unset';
    await pumpHost(tester, const Size(1200, 800), (context) async {
      result = await showAdaptiveSheet<String>(
        context: context,
        builder: (c) => ListTile(
          title: const Text('Pick me'),
          onTap: () => Navigator.pop(c, 'picked'),
        ),
      );
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('adaptive-sheet-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('adaptive-sheet-close')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick me'));
    await tester.pumpAndSettle();
    expect(result, 'picked');
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-dismissible dialogs ignore the barrier and have no close', (
    tester,
  ) async {
    await pumpHost(tester, const Size(1200, 800), (context) async {
      await showAdaptiveSheet<void>(
        context: context,
        isDismissible: false,
        builder: (c) => TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Done'),
        ),
      );
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('adaptive-sheet-close')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);
  });

  for (final size in const [Size(390, 800), Size(1200, 800)]) {
    testWidgets('AdaptiveSheetBody scrolls long lists at ${size.width}px', (
      tester,
    ) async {
      await pumpHost(tester, size, (context) async {
        await showAdaptiveSheet<void>(
          context: context,
          scrollable: false,
          builder: (c) => AdaptiveSheetBody(
            builder: (c, controller, shrink) => ListView(
              controller: controller,
              shrinkWrap: shrink,
              children: [
                for (var i = 0; i < 60; i++) ListTile(title: Text('Item $i')),
              ],
            ),
          ),
        );
      });
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 59'), findsNothing);
      await tester.scrollUntilVisible(find.text('Item 59'), 300);
      expect(find.text('Item 59'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'short AdaptiveSheetBody lists size to their content in a dialog',
    (tester) async {
      await pumpHost(tester, const Size(1200, 800), (context) async {
        await showAdaptiveSheet<void>(
          context: context,
          scrollable: false,
          builder: (c) => AdaptiveSheetBody(
            builder: (c, controller, shrink) => ListView(
              controller: controller,
              shrinkWrap: shrink,
              children: const [ListTile(title: Text('Only item'))],
            ),
          ),
        );
      });
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final height = tester
          .getSize(
            find
                .descendant(
                  of: find.byKey(const ValueKey('adaptive-sheet-dialog')),
                  matching: find.byType(Material),
                )
                .first,
          )
          .height;
      expect(height, lessThan(200));
    },
  );
}

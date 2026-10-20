import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/utils/helpers/time_format.dart';
import 'package:eden_booking/modules/turf/models/turf_configuration.dart';
import 'package:eden_booking/modules/turf/widgets/turf_hours_editor.dart';

void main() {
  test('midnight alias normalizes without accepting times past midnight', () {
    expect(TimeFormat.normalize('24:00'), '00:00');
    expect(TimeFormat.normalize('0:0'), '00:00');
    expect(TimeFormat.normalize('9:12'), '09:12');
    expect(TimeFormat.normalize('12:00'), '12:00');
    for (final value in ['24:01', '24:30', '25:00', '23:60', '-1:00', '24']) {
      expect(TimeFormat.normalize(value), isNull);
    }
    expect(TimeFormat.display('00:00'), '24:00');
    expect(TimeFormat.display('00:12'), '00:12');
  });

  testWidgets('24:00 input returns canonical midnight and rejects 24:15', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? saved;
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
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await showAppTimePicker(
                    context: context,
                    initialTime: '23:00',
                  );
                },
                child: const Text('Pick time'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick time'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '24');
    await tester.enterText(fields.at(1), '15');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('Use 00–23, or 24 with minute 00.'), findsOneWidget);
    await tester.enterText(fields.at(1), '00');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(saved, '00:00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved canonical midnight displays and reopens as 24:00', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          theme: darkTheme(),
          home: Scaffold(
            body: TurfHoursEditor(
              hours: TurfHours(closes: '00:00'),
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Closes · 24:00'), findsOneWidget);
    await tester.tap(find.text('Closes · 24:00'));
    await tester.pumpAndSettle();
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields[0].controller!.text, '24');
    expect(fields[1].controller!.text, '00');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

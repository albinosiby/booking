import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/layouts/app_page.dart';

void main() {
  testWidgets(
    'desktop designer title shares Back row and gives editor more height',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(1440, 900),
          builder: (_, _) => MaterialApp(
            home: AppPage(
              title: 'Design website',
              subtitle: 'Make your booking website feel like your venue.',
              back: true,
              onBack: () {},
              showAppBar: true,
              compactHeader: true,
              inlineDesktopTitle: true,
              fixedBody: const ColoredBox(
                key: ValueKey('editor'),
                color: Colors.black,
              ),
              children: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Design website'), findsOneWidget);
      expect(
        find.text('Make your booking website feel like your venue.'),
        findsNothing,
      );
      expect(
        tester.getCenter(find.text('Design website')).dy,
        closeTo(tester.getCenter(find.text('Back')).dy, 2),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('editor'))).dy,
        lessThan(100),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('editor'))).height,
        greaterThan(780),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

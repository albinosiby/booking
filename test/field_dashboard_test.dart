// Field-value tests for lib/modules/dashboard: greeting name/organization
// handling, small-screen and large-text layout of the greeting card.
import 'package:eden_booking/modules/dashboard/widgets/home_greeting_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mount(
  WidgetTester tester,
  Widget card, {
  Size size = const Size(320, 568),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (c, app) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: app!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );
  await tester.pump();
}

void main() {
  const greetings = ['Good morning', 'Good afternoon', 'Good evening'];
  Finder greeting(String suffix) => find.byWidgetPredicate(
    (w) =>
        w is Text &&
        w.data != null &&
        greetings.any((g) => w.data == '$g$suffix'),
  );

  testWidgets('first name is the first whitespace-separated word', (
    tester,
  ) async {
    await mount(
      tester,
      const HomeGreetingCard(name: '  Albino   Siby  ', organization: 'Eden'),
    );
    expect(greeting(', Albino'), findsOneWidget);
  });

  for (final name in ['', '   ', '\n\t']) {
    testWidgets('blank name "${name.trim()}" shows greeting without a comma', (
      tester,
    ) async {
      await mount(tester, HomeGreetingCard(name: name, organization: 'Eden'));
      expect(greeting(''), findsOneWidget);
    });
  }

  for (final scale in [1.0, 2.0]) {
    for (final name in [
      'அபிநவ் குமார்',
      '😀 Fun',
      'A' * 300,
      'محمد علي',
      'O\'Brien',
    ]) {
      testWidgets(
        'name "${name.length > 12 ? '${name.substring(0, 12)}…' : name}" at 320x568 scale $scale',
        (tester) async {
          await mount(
            tester,
            HomeGreetingCard(name: name, organization: 'Org ${'X' * 200} 😀'),
            scale: scale,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('empty organization, wide screen and huge text do not overflow', (
    tester,
  ) async {
    await mount(
      tester,
      const HomeGreetingCard(name: 'Al', organization: ''),
      size: const Size(1440, 900),
      scale: 3,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt logo bytes fall back to the placeholder icon', (
    tester,
  ) async {
    await mount(
      tester,
      HomeGreetingCard(
        name: 'Al',
        organization: 'Eden',
        logo: Uint8List.fromList([1, 2, 3]),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.business_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home hero uses the bundled image with a translucent overlay', (
    tester,
  ) async {
    await mount(
      tester,
      const HomeGreetingCard(name: 'Al', organization: 'Eden'),
    );
    expect(find.byKey(const ValueKey('home-hero-fallback')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-hero-uploaded')), findsNothing);
    final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
    expect(opacity.opacity, greaterThan(0));
    expect(opacity.opacity, lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved website hero replaces the bundled background', (
    tester,
  ) async {
    final image = await rootBundle.load('assets/branding/booking_os_mark.png');
    await mount(
      tester,
      HomeGreetingCard(
        name: 'Al',
        organization: 'Eden',
        heroImage: image.buffer.asUint8List(),
      ),
    );
    expect(find.byKey(const ValueKey('home-hero-uploaded')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-hero-fallback')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

import 'package:eden_booking/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(
        theme: darkTheme(),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('AppTextField', () {
    testWidgets('validator runs through Form and shows the message', (
      tester,
    ) async {
      final key = GlobalKey<FormState>();
      final c = TextEditingController();
      await _mount(
        tester,
        Form(
          key: key,
          child: AppTextField(
            label: 'Name',
            controller: c,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
        ),
      );
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '   ');
      expect(key.currentState!.validate(), isFalse);
      await tester.enterText(find.byType(TextFormField), 'ഏബിൻ 😀');
      expect(key.currentState!.validate(), isTrue);
      expect(c.text, 'ഏബിൻ 😀');
    });

    testWidgets('password field hides text, disables suggestions, toggles', (
      tester,
    ) async {
      final c = TextEditingController();
      await _mount(
        tester,
        AppTextField(label: 'Pw', controller: c, password: true),
      );
      EditableText e() =>
          tester.widget<EditableText>(find.byType(EditableText));
      expect(e().obscureText, isTrue);
      expect(e().enableSuggestions, isFalse);
      expect(e().autocorrect, isFalse);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(e().obscureText, isFalse);
    });

    testWidgets('disabled field ignores input', (tester) async {
      final c = TextEditingController(text: 'keep');
      await _mount(
        tester,
        AppTextField(label: 'X', controller: c, enabled: false),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('onChanged fires for paste with spaces and newlines', (
      tester,
    ) async {
      final seen = <String>[];
      await _mount(
        tester,
        AppTextField(
          label: 'X',
          controller: TextEditingController(),
          onChanged: seen.add,
        ),
      );
      await tester.enterText(find.byType(TextFormField), '  a b \n');
      expect(seen.last.contains('\n'), isFalse);
      expect(seen.last.trim(), 'a b');
    });

    testWidgets('very long unbroken text and 3x scale do not overflow 320px', (
      tester,
    ) async {
      final c = TextEditingController(text: 'W' * 400);
      await _mount(
        tester,
        AppTextField(label: 'A long label ' * 4, controller: c, hint: 'hint'),
        size: const Size(320, 568),
        scale: 3,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AppButton', () {
    testWidgets('busy disables presses and shows the busy label', (
      tester,
    ) async {
      var taps = 0;
      await _mount(
        tester,
        AppButton(
          label: 'Save',
          busyLabel: 'Saving…',
          busy: true,
          onPressed: () => taps++,
        ),
      );
      expect(find.text('Saving…'), findsOneWidget);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('null onPressed is disabled; secondary busy also disabled', (
      tester,
    ) async {
      await _mount(tester, const AppButton(label: 'Go'));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await _mount(
        tester,
        AppButton(label: 'Go', secondary: true, busy: true, onPressed: () {}),
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    });

    testWidgets('long and emoji labels wrap at 320px and 3x text', (
      tester,
    ) async {
      await _mount(
        tester,
        AppButton(
          label: 'Create account 😀 ${'very long ' * 8}',
          icon: Icons.add,
          onPressed: () {},
        ),
        size: const Size(320, 568),
        scale: 3,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AppPicker', () {
    Widget picker({
      String? value,
      bool required = false,
      bool enabled = true,
      ValueChanged<String>? on,
    }) => Form(
      child: AppPicker(
        label: 'Role',
        items: const [PickerItem('a', 'Alpha'), PickerItem('b', 'Beta 😀')],
        value: value,
        required: required,
        enabled: enabled,
        onChanged: on ?? (_) {},
      ),
    );

    testWidgets('shows placeholder, selects, filters by search', (
      tester,
    ) async {
      String? chosen;
      await _mount(tester, picker(on: (v) => chosen = v));
      expect(find.text('Select Role'), findsOneWidget);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  ');
      await tester.pump();
      expect(find.text('No matching options'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'BETA');
      await tester.pump();
      expect(find.text('Alpha'), findsNothing);
      await tester.tap(find.text('Beta 😀'));
      await tester.pumpAndSettle();
      expect(chosen, 'b');
    });

    testWidgets('disabled picker does not open', (tester) async {
      await _mount(tester, picker(enabled: false));
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.text('Search'), findsNothing);
    });

    testWidgets('required picker with no value fails validation', (
      tester,
    ) async {
      final key = GlobalKey<FormState>();
      await _mount(
        tester,
        Form(
          key: key,
          child: AppPicker(
            label: 'Role',
            required: true,
            items: const [],
            onChanged: (_) {},
          ),
        ),
      );
      expect(key.currentState!.validate(), isFalse);
    });

    testWidgets('sheet fits 320x568 at 2x text', (tester) async {
      await _mount(tester, picker(), size: const Size(320, 568), scale: 2);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide screens open the picker as a dialog', (tester) async {
      await _mount(tester, picker(), size: const Size(1200, 800));
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('adaptive-sheet-dialog')),
        findsOneWidget,
      );
    });
  });

  group('feedback widgets', () {
    testWidgets('error widget shows message and retry only when given', (
      tester,
    ) async {
      var retries = 0;
      await _mount(
        tester,
        AppErrorWidget(message: 'Boom', onRetry: () => retries++),
      );
      await tester.tap(find.text('Try again'));
      expect(retries, 1);
      await _mount(tester, const AppErrorWidget(message: 'Boom'));
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('empty state and long messages fit 320px at 3x', (
      tester,
    ) async {
      await _mount(
        tester,
        AppEmptyState(title: 'T' * 100, message: 'M ' * 150),
        size: const Size(320, 568),
        scale: 3,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirmAction returns true, false and false on dismiss', (
      tester,
    ) async {
      final results = <bool>[];
      await _mount(
        tester,
        Builder(
          builder: (c) => TextButton(
            onPressed: () async =>
                results.add(await confirmAction(c, 'Sure?', 'msg')),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(results, [true, false, false]);
    });

    testWidgets('showMessage with a very long text does not overflow', (
      tester,
    ) async {
      await _mount(
        tester,
        Builder(
          builder: (c) => TextButton(
            onPressed: () => showMessage(c, 'x ' * 400),
            child: const Text('go'),
          ),
        ),
        size: const Size(320, 568),
        scale: 2,
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

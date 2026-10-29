import 'package:eden_booking/design_system/layouts/app_page.dart';
import 'package:eden_booking/design_system/layouts/app_resume_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

void main() {
  testWidgets(
    'Android resume clears stale keyboard gap and retains form state',
    (tester) async {
      final controller = TextEditingController(text: '700');
      final focus = FocusNode();
      addTearDown(() {
        tester.view.reset();
        controller.dispose();
        focus.dispose();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            ScreenUtil.init(context, designSize: const Size(390, 844));
            return AppResumeLayout(child: child!);
          },
          home: AppPage(
            title: 'Pricing',
            children: [
              TextField(controller: controller, focusNode: focus),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      );
      final scroll = find.byType(SingleChildScrollView);
      final fullHeight = tester.getSize(scroll).height;
      await tester.tap(find.byType(TextField));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.getSize(scroll).height, fullHeight - 300);
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      position.jumpTo(80);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      // Transient inactive states (permission dialogs, system shade) keep focus.
      expect(focus.hasFocus, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      // Reproduce the Android failure: native inset is still 300, keyboard is gone.
      expect(tester.view.viewInsets.bottom, 300);
      expect(tester.getSize(scroll).height, fullHeight);
      expect(focus.hasFocus, isFalse);
      expect(controller.text, '700');
      expect(position.pixels, 80);
      // Opening the keyboard again must resize normally, even before a new metric.
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.getSize(scroll).height, fullHeight - 300);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(tester.getSize(scroll).height, fullHeight);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

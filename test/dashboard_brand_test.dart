import 'package:eden_booking/constants/asset_path.dart';
import 'package:eden_booking/design_system/layouts/adaptive_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final extended in [true, false]) {
    testWidgets('dashboard uses real logo with extended=$extended', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                AppSideNav(index: 0, onTap: (_) {}, extended: extended),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, AssetPath.bookingLogo);
      expect(image.semanticLabel, 'Booking OS');
      expect(tester.takeException(), isNull);
    });
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:eden_booking/modules/accounts/repositories/website_payment_repository.dart';
import 'package:eden_booking/modules/accounts/widgets/website_payment_settings_card.dart';
import 'package:eden_booking/modules/booking_website/widgets/website_spaces_settings.dart';
import 'package:eden_booking/modules/booking_website/models/website_settings.dart';
import 'package:eden_booking/utils/services/logo_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'booking_website_test.dart' show TestWebsiteRepository;

class PaymentRepository implements WebsitePaymentRepository {
  WebsitePaymentDetails value = const WebsitePaymentDetails(
    version: 0,
    upiId: '',
  );
  int saves = 0;
  @override
  Future<WebsitePaymentDetails> websitePayments() async => value;
  @override
  Future<WebsitePaymentDetails> saveWebsitePayments(
    int version,
    String upiId,
    LogoSelection? qr,
  ) async {
    saves++;
    return value = WebsitePaymentDetails(
      version: version + 1,
      upiId: upiId,
      qr: qr,
    );
  }
}

Future<void> mount(WidgetTester tester, Widget child) => tester.pumpWidget(
  ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, _) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);
void main() {
  testWidgets(
    'UPI validation and QR upload save and removal persist through repository',
    (tester) async {
      final repository = PaymentRepository();
      final qr = LogoSelection(
        Uint8List.fromList(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=',
          ),
        ),
        'image/png',
      );
      await mount(
        tester,
        WebsitePaymentSettingsCard(
          repository: repository,
          pickImage: () async => qr,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'invalid');
      await tester.ensureVisible(find.text('Save payment details'));
      await tester.tap(find.text('Save payment details'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid UPI ID.'), findsOneWidget);
      expect(repository.saves, 0);
      await tester.enterText(find.byType(TextFormField), 'venue@bank');
      await tester.ensureVisible(find.text('Upload QR code'));
      await tester.tap(find.text('Upload QR code'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.ensureVisible(find.text('Save payment details'));
      await tester.tap(find.text('Save payment details'));
      await tester.pumpAndSettle();
      expect(repository.value.upiId, 'venue@bank');
      expect(repository.value.qr, qr);
      await tester.ensureVisible(find.text('Remove QR code'));
      await tester.tap(find.text('Remove QR code'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save payment details'));
      await tester.tap(find.text('Save payment details'));
      await tester.pumpAndSettle();
      expect(repository.value.qr, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'space payment toggle supports half, full and a custom percentage',
    (tester) async {
      var settings = TestWebsiteRepository().value;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, update) => WebsiteSpacesSettings(
            settings: settings,
            busy: false,
            onToggleBusiness: (_, _) {},
            onBusiness: (_, _) {},
            onCopyRules: (_) {},
            onUpload: (_, _, _) {},
            onRemovePhoto: (_) {},
            onSpace: (businessId, space) => update(() {
              settings = settings.copyWith(
                businesses: [
                  for (final business in settings.businesses)
                    business.id == businessId
                        ? business.copyWith(
                            spaces: [
                              for (final current in business.spaces)
                                current.id == space.id ? space : current,
                            ],
                          )
                        : business,
                ],
              );
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Court 1'));
      await tester.tap(find.text('Court 1'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Collect payment mandatory').first);
      await tester.tap(find.text('Collect payment mandatory').first);
      await tester.pumpAndSettle();
      WebsiteSpace space() => settings.businesses.first.spaces.first;
      expect(space().paymentRequired, true);
      expect(space().paymentPercentages, [50, 100]);
      await tester.ensureVisible(find.text('Full (100%)').first);
      await tester.tap(find.text('Full (100%)').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Custom payment percentage').first,
        '25',
      );
      await tester.pumpAndSettle();
      expect(space().paymentPercentages, [25, 50]);
      expect(tester.takeException(), isNull);
    },
  );
}

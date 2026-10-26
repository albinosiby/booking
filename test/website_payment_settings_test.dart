import 'package:image/image.dart' as image_data;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/modules/accounts/cubit/website_payment_settings_cubit.dart';
import 'package:eden_booking/modules/accounts/models/website_payment_settings_model.dart';
import 'dart:typed_data';
import 'package:eden_booking/modules/accounts/repositories/website_payment_repository.dart';
import 'package:eden_booking/modules/accounts/widgets/website_payment_settings_card.dart';
import 'package:eden_booking/modules/booking_website/widgets/website_spaces_settings.dart';
import 'package:eden_booking/modules/booking_website/models/website_settings.dart';
import 'package:eden_booking/modules/booking_website/cubit/website_settings_cubit.dart';
import 'package:eden_booking/modules/booking_website/cubit/website_settings_state.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/utils/services/logo_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'booking_website_test.dart' show TestWebsiteRepository;
import 'booking_module_test.dart' show BookingSource;

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
          image_data.encodePng(image_data.Image(width: 8, height: 8)),
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
      await tester.pump();
      await tester.ensureVisible(find.text('Save payment details'));
      await tester.tap(find.text('Save payment details'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid UPI ID.'), findsOneWidget);
      expect(repository.saves, 0);
      await tester.enterText(find.byType(TextFormField), 'venue@bank');
      await tester.pump();
      await tester.ensureVisible(find.text('Upload QR code'));
      await tester.runAsync(() async {
        final view = tester
            .widget<
              BlocConsumer<
                WebsitePaymentSettingsCubit,
                WebsitePaymentSettingsModel
              >
            >(
              find.byWidgetPredicate(
                (w) =>
                    w
                        is BlocConsumer<
                          WebsitePaymentSettingsCubit,
                          WebsitePaymentSettingsModel
                        >,
              ),
            );
        final picked = view.bloc!.stream
            .firstWhere((s) => !s.picking)
            .timeout(const Duration(seconds: 5));
        await tester.tap(find.text('Upload QR code'));
        await picked;
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-qr-preview')), findsOneWidget);
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
    'space payment toggle and percentage choices copy to all spaces and save',
    (tester) async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repository = TestWebsiteRepository();
      final cubit = WebsiteSettingsCubit(workspace, repository);
      await cubit.load();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await cubit.close();
        await workspace.close();
      });
      await mount(
        tester,
        BlocBuilder<WebsiteSettingsCubit, WebsiteSettingsState>(
          bloc: cubit,
          builder: (context, state) => KeyedSubtree(
            key: ValueKey(state.revision),
            child: WebsiteSpacesSettings(
              settings: state.draft!,
              busy: false,
              onToggleBusiness: (_, _) {},
              onBusiness: (_, _) {},
              onCopyRules: cubit.copyRulesToAll,
              onUpload: (_, _, _) {},
              onRemovePhoto: (_) {},
              onSpace: cubit.updateSpace,
            ),
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
      WebsiteSpace space() => cubit.state.draft!.businesses.first.spaces.first;
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
      final copy = find.text('Copy these rules to all spaces').first;
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      for (final business in cubit.state.draft!.businesses) {
        for (final space in business.spaces) {
          expect(space.paymentRequired, isTrue);
          expect(space.paymentPercentages, [25, 50]);
        }
      }
      await tester.ensureVisible(find.text('Court 2'));
      await tester.tap(find.text('Court 2'));
      await tester.pumpAndSettle();
      final target = find.byKey(
        const PageStorageKey('website-space-expansion-business-court-2'),
      );
      final toggle = find.descendant(
        of: target,
        matching: find.widgetWithText(
          SwitchListTile,
          'Collect payment mandatory',
        ),
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      final percentage = find.byKey(
        const PageStorageKey('website-payment-percentage-business-court-2'),
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: percentage,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '25',
      );
      await cubit.save();
      await cubit.load();
      await tester.pumpAndSettle();
      expect(repository.saves, 1);
      for (final business in repository.value.businesses) {
        for (final space in business.spaces) {
          expect(space.paymentRequired, isTrue);
          expect(space.paymentPercentages, [25, 50]);
        }
      }
      expect(tester.takeException(), isNull);
    },
  );
}

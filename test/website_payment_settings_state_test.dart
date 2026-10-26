import 'package:image/image.dart' as image_data;
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/accounts/cubit/website_payment_settings_cubit.dart';
import 'package:eden_booking/modules/accounts/repositories/website_payment_qr_repository.dart';
import 'package:eden_booking/modules/accounts/repositories/website_payment_repository.dart';
import 'package:eden_booking/modules/accounts/widgets/website_payment_settings_card.dart';
import 'package:eden_booking/utils/services/logo_picker_service.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/modules/accounts/models/website_payment_settings_model.dart';

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
      upiId: upiId.trim(),
      qr: qr,
    );
  }
}

Future<void> mount(WidgetTester tester, Widget child) => tester.pumpWidget(
  ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, _) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

class Images extends Fake implements WebsitePaymentQrRepository {
  Completer<LogoSelection?>? pending;
  LogoSelection? image;
  @override
  Future<LogoSelection?> pick() async => pending?.future ?? image;
}

void main() {
  testWidgets(
    'valid QR previews on a white surface and Save is disabled after saving',
    (tester) async {
      final r = PaymentRepository();
      final image = LogoSelection(
        Uint8List.fromList(
          image_data.encodePng(image_data.Image(width: 8, height: 8)),
        ),
        'image/png',
      );
      await mount(
        tester,
        WebsitePaymentSettingsCard(repository: r, pickImage: () async => image),
      );
      await tester.pumpAndSettle();
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
        final ready = view.bloc!.stream
            .firstWhere((s) => !s.picking)
            .timeout(const Duration(seconds: 5));
        await tester.tap(find.text('Upload QR code'));
        await ready;
      });
      await tester.pumpAndSettle();
      final preview = tester.widget<Container>(
        find.byKey(const ValueKey('payment-qr-preview')),
      );
      expect((preview.decoration as BoxDecoration).color, Colors.white);
      expect(find.byType(Image), findsOneWidget);
      expect(r.saves, 0);
      await tester.ensureVisible(find.text('Save payment details'));
      await tester.tap(find.text('Save payment details'));
      await tester.pumpAndSettle();
      expect(r.saves, 1);
      expect(r.value.qr, image);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save payment details'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await mount(tester, const SizedBox());
      await mount(
        tester,
        WebsitePaymentSettingsCard(
          key: const ValueKey('revisit'),
          repository: r,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payment-qr-preview')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save payment details'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  test(
    'Save needs changed details; opening or cancelling the picker never saves or dirties the form',
    () async {
      final repository = PaymentRepository(), images = Images();
      final c = WebsitePaymentSettingsCubit(repository, images);
      await c.load();
      expect(c.state.canSave, isFalse);
      images.pending = Completer();
      final picking = c.pick();
      expect(c.state.picking, isTrue);
      expect(c.state.saving, isFalse);
      await c.save();
      expect(repository.saves, 0);
      images.pending!.complete(null);
      await picking;
      expect(c.state.canSave, isFalse);
      expect(c.state.dirty, isFalse);
      images.pending = null;
      images.image = LogoSelection(Uint8List.fromList([1]), 'image/png');
      await c.pick();
      expect(c.state.canSave, isTrue);
      expect(repository.saves, 0);
      await c.save();
      expect(repository.saves, 1);
      expect(c.state.canSave, isFalse);
      images.image = LogoSelection(Uint8List.fromList([1]), 'image/png');
      await c.pick();
      expect(
        c.state.dirty,
        isFalse,
        reason: 'identical file bytes are not a change',
      );
      c.removeQr();
      expect(c.state.canSave, isTrue);
      await c.save();
      expect(repository.value.qr, isNull);
      await c.close();
    },
  );
  test(
    'QR selection preserves edited UPI; reverting edits disables Save',
    () async {
      final r = PaymentRepository(), images = Images();
      final c = WebsitePaymentSettingsCubit(r, images);
      await c.load();
      c.upiChanged('venue@bank');
      expect(c.state.canSave, isTrue);
      await c.pick();
      expect(c.state.upiId, 'venue@bank');
      expect(c.state.canSave, isTrue);
      c.upiChanged('');
      expect(c.state.canSave, isFalse);
      c.upiChanged('invalid');
      await c.save();
      expect(r.saves, 0);
      expect(c.state.error, 'Enter a valid UPI ID.');
      await c.close();
    },
  );
  testWidgets('cancelled picker never enables Save or displays Saving', (
    tester,
  ) async {
    final picked = Completer<LogoSelection?>(),
        repository = PaymentRepository();
    await mount(
      tester,
      WebsitePaymentSettingsCard(
        repository: repository,
        pickImage: () => picked.future,
      ),
    );
    await tester.pumpAndSettle();
    FilledButton save() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save payment details'),
    );
    expect(save().onPressed, isNull);
    await tester.tap(find.text('Upload QR code'));
    await tester.pump();
    expect(find.text('Choosing QR image…'), findsOneWidget);
    expect(find.text('Saving…'), findsNothing);
    expect(save().onPressed, isNull);
    picked.complete(null);
    await tester.pumpAndSettle();
    expect(save().onPressed, isNull);
    expect(repository.saves, 0);
  });
  testWidgets(
    'invalid and oversized files are rejected by the local QR repository',
    (tester) async {
      final bad = DeviceWebsitePaymentQrRepository(
        picker: () async =>
            LogoSelection(Uint8List.fromList([1, 2, 3]), 'image/png'),
      );
      await tester.runAsync(() async {
        await expectLater(bad.pick(), throwsA(isA<AppException>()));
        final large = DeviceWebsitePaymentQrRepository(
          picker: () async =>
              LogoSelection(Uint8List(1024 * 1024 + 1), 'image/png'),
        );
        await expectLater(
          large.pick(),
          throwsA(
            isA<AppException>().having(
              (e) => e.message,
              'message',
              contains('1 MB'),
            ),
          ),
        );
      });
    },
  );
}

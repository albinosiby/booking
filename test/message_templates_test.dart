import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:eden_booking/modules/messages/widgets/message_chat_preview.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/messages/cubit/message_cubits.dart';
import 'package:eden_booking/modules/messages/models/message_template.dart';
import 'package:eden_booking/modules/messages/repositories/message_repository.dart';
import 'package:eden_booking/modules/messages/screens/template_editor_screen.dart';
import 'package:eden_booking/modules/messages/screens/templates_screen.dart';
import 'package:eden_booking/modules/messages/screens/message_preview_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

class TestMessages implements MessageRepository {
  TestMessages(this.record);
  BookingRecord record;
  MessageTemplateCatalog value = MessageTemplateCatalog(canManage: true);
  final creates = <Map<String, String>>[];
  Completer<BookingRecord>? delayedBooking;
  Object? catalogError;
  bool failSave = false;
  @override
  Future<MessageTemplateCatalog> catalog({bool refresh = false}) async {
    if (catalogError != null) throw catalogError!;
    return value;
  }

  @override
  Future<BookingRecord> booking(String id) async =>
      delayedBooking == null ? record : await delayedBooking!.future;
  @override
  Future<void> create({
    required String key,
    required String name,
    required String body,
    required String website,
  }) async {
    creates.add({'key': key, 'name': name, 'body': body, 'website': website});
    if (failSave) throw const AppException('Offline', code: 'NETWORK');
  }

  @override
  Future<void> primary(String id) async {
    value = MessageTemplateCatalog(
      canManage: true,
      templates: [
        for (final t in value.templates)
          MessageTemplate(
            id: t.id,
            name: t.name,
            body: t.body,
            website: t.website,
            builtin: t.builtin,
            primary: t.id == id,
          ),
      ],
    );
  }

  @override
  Future<void> remove(String id) async {}
}

class TestShare implements MessageShareGateway {
  final messages = <String>[], copies = <String>[];
  bool opens = true;
  @override
  Future<bool> whatsapp(String message) async {
    messages.add(message);
    return opens;
  }

  @override
  Future<void> copy(String message) async {
    copies.add(message);
  }
}

Future<(BookingSource, WorkspaceCubit, TestMessages)> fixture() async {
  final source = BookingSource();
  final workspace = WorkspaceCubit(source);
  await workspace.load();
  final b = FakeBookingRepository();
  final selection = const BookingSelection(
    businessId: 'business',
    resourceId: 'space',
    optionId: 'court',
    date: '2030-06-04',
    time: '09:00',
    duration: 60,
    people: 1,
  );
  b.records['booking'] = b.row(
    'booking',
    selection,
    const BookingCustomer(name: 'Abin', phone: '9876543210'),
  );
  final record = await b.detail('booking');
  return (source, workspace, TestMessages(record));
}

ThemeData templateReviewTheme(bool dark) {
  var theme = dark ? darkTheme() : lightTheme();
  if (const bool.fromEnvironment('MESSAGE_PREVIEWS')) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
      filledButtonTheme: FilledButtonThemeData(
        style: theme.filledButtonTheme.style?.copyWith(
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Roboto',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
  return theme;
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('MESSAGE_PREVIEWS')) return;
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final data = await File(
        '/tmp/booking-review-fonts/${font.value}',
      ).readAsBytes();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    }
  });
  test(
    'preview formatting preserves plain text and styles nested bold and italic',
    () {
      final span = messagePreviewSpan('Hello *bold _italic_* and _soft_');
      expect(span.toPlainText(), 'Hello bold italic and soft');
      final bold = span.children![1] as TextSpan;
      expect(bold.style!.fontWeight, FontWeight.w700);
      final italic = bold.children![1] as TextSpan;
      expect(italic.style!.fontStyle, FontStyle.italic);
      expect(
        messagePreviewSpan('Unclosed *word').toPlainText(),
        'Unclosed *word',
      );
    },
  );
  tearDown(() => getIt.reset());
  test(
    'placeholder validation rejects malformed fields and renders each occurrence only once',
    () {
      for (final text in [
        '',
        '{bad}',
        '{customer_name',
        '{{customer_name}}',
        '{}',
      ]) {
        expect(validateMessageBody(text), isNotNull);
      }
      expect(validateMessageBody(defaultMessageBody), isNull);
      const t = MessageTemplate(
        id: 'a',
        name: 'Test',
        body: '{customer_name}: {balance_due} / {balance_due}',
      );
      expect(
        t.render({'customer_name': 'Name {website}', 'balance_due': '₹100'}),
        'Name {website}: ₹100 / ₹100',
      );
      expect(
        MessageTemplate.predefined.render(sampleMessageFields),
        contains('Slot Amount: *₹650*'),
      );
    },
  );
  test(
    'share uses the primary template and saved balance, and never sends automatically',
    () async {
      final (_, w, r) = await fixture();
      final share = TestShare();
      r.value = MessageTemplateCatalog(
        templates: const [
          MessageTemplate(
            id: 'custom',
            name: 'Short',
            body: 'Hi {customer_name}, pending {balance_due}',
            primary: true,
          ),
        ],
      );
      final c = MessagePreviewCubit(w, r, share, 'booking');
      await c.load();
      expect(c.state.templateName, 'Short');
      expect(c.state.message, 'Hi Abin, pending ₹500');
      expect(share.messages, isEmpty);
      await c.copy();
      expect(share.copies.single, c.state.message);
      await c.share();
      expect(share.messages.single, c.state.message);
      share.opens = false;
      await c.share();
      expect(c.state.notice, contains('Copy message'));
      await c.close();
      await w.close();
    },
  );
  test(
    'saving a copy freezes uncertain payload and retries the same command',
    () async {
      final (_, w, r) = await fixture();
      r.failSave = true;
      final c = TemplateEditorCubit(w, r, MessageTemplate.predefined);
      expect(c.state.body, defaultMessageBody);
      c.update(name: 'My template');
      await c.save();
      c.update(body: 'Changed');
      expect(c.state.body, defaultMessageBody);
      r.failSave = false;
      await c.save();
      expect(c.state.saved, isTrue);
      expect(r.creates[0], r.creates[1]);
      expect(MessageTemplate.predefined.body, defaultMessageBody);
      await c.close();
      await w.close();
    },
  );
  test(
    'unknown placeholders cannot be saved and only owner can manage templates',
    () async {
      final (source, w, r) = await fixture();
      final c = TemplateEditorCubit(w, r, null);
      c.update(name: 'Invalid', body: 'Hi {bad}');
      await c.save();
      expect(r.creates, isEmpty);
      source.value = Workspace(
        organization: source.value.organization,
        membership: const {
          'role': 'staff',
          'permissions': ['view_bookings'],
        },
        businesses: source.value.businesses,
      );
      await w.load();
      await Future<void>.delayed(Duration.zero);
      c.update(body: defaultMessageBody);
      await c.save();
      expect(r.creates, isEmpty);
      await c.close();
      await w.close();
    },
  );
  test(
    'fallback template is explicit; unauthorized or failed booking reads never reveal a message',
    () async {
      final (_, w, r) = await fixture();
      final share = TestShare();
      r.catalogError = const AppException('Offline', code: 'NETWORK');
      final c = MessagePreviewCubit(w, r, share, 'booking');
      await c.load();
      expect(c.state.notice, contains('predefined'));
      expect(c.state.message, isNotEmpty);
      r.catalogError = const AppException('Denied', code: 'FORBIDDEN');
      await c.load();
      expect(c.state.message, isEmpty);
      await c.share();
      expect(share.messages, isEmpty);
      await c.close();
      await w.close();
    },
  );
  test(
    'late preview responses are discarded after workspace access changes',
    () async {
      final (source, w, r) = await fixture();
      final share = TestShare();
      r.delayedBooking = Completer<BookingRecord>();
      final c = MessagePreviewCubit(w, r, share, 'booking');
      final loading = c.load();
      source.value = const Workspace();
      await w.load();
      await Future<void>.delayed(Duration.zero);
      r.delayedBooking!.complete(r.record);
      await loading;
      expect(c.state.message, isEmpty);
      await c.share();
      expect(share.messages, isEmpty);
      await c.close();
      await w.close();
    },
  );
  for (final page in ['editor', 'list', 'share']) {
    testWidgets('$page screen fits a narrow screen with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (_, w, r) = await fixture();
      if (page == 'list') {
        r.value = MessageTemplateCatalog(
          canManage: true,
          templates: const [
            MessageTemplate.predefined,
            MessageTemplate(
              id: 'custom',
              name: 'Quick reminder',
              body: 'Hi {customer_name}, pending {balance_due}.',
            ),
          ],
        );
      }
      final boundaryKey = GlobalKey();
      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('MESSAGE_PREVIEWS')) return;
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('/tmp/message-template-previews');
          await dir.create(recursive: true);
          await File(
            '${dir.path}/${const bool.fromEnvironment('MESSAGE_DARK') ? 'dark' : 'light'}-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      registerFeatureDependencies(getIt);
      await getIt.unregister<MessageRepository>();
      getIt.registerSingleton<MessageRepository>(r);
      await getIt.unregister<MessageShareGateway>();
      getIt.registerSingleton<MessageShareGateway>(TestShare());
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (c, s) => switch (page) {
              'editor' => const TemplateEditorScreen(
                source: MessageTemplate.predefined,
              ),
              'list' => const TemplatesScreen(),
              _ => const MessagePreviewScreen(bookingId: 'booking'),
            },
          ),
        ],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (c, _) => MaterialApp.router(
              theme: templateReviewTheme(false),
              darkTheme: templateReviewTheme(true),
              themeMode: const bool.fromEnvironment('MESSAGE_DARK')
                  ? ThemeMode.dark
                  : ThemeMode.light,
              routerConfig: router,
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: RepaintBoundary(key: boundaryKey, child: child!),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(page);
      if (page == 'list') {
        expect(find.byType(AppCard), findsNothing);
        expect(find.byTooltip('Create template'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('template-tile-default')));
        await tester.pumpAndSettle();
        expect(find.byType(MessageChatPreview), findsOneWidget);
        await tester.tap(find.byTooltip('Close preview'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Template options').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Set as primary'));
        await tester.pumpAndSettle();
        expect(r.value.primary.id, 'custom');
      }
      if (page == 'editor') {
        final field = find.byKey(const ValueKey('template-message-input'));
        await tester.enterText(field, 'Hello _world_ {customer_name}');
        final controller = tester.widget<TextField>(field).controller!;
        controller.selection = const TextSelection.collapsed(offset: 6);
        await tester.ensureVisible(find.text('Preview'));
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
        expect(find.byType(MessageChatPreview), findsOneWidget);
        await capture('editor-preview');
        final preview = tester.widget<SelectableText>(
          find.descendant(
            of: find.byType(MessageChatPreview),
            matching: find.byType(SelectableText),
          ),
        );
        expect(preview.textSpan!.toPlainText(), 'Hello world Abin');
        expect(find.text('Save template').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Write'));
        await tester.pumpAndSettle();
        expect(controller.text, 'Hello _world_ {customer_name}');
        expect(controller.selection.baseOffset, 6);
        await tester.tap(find.byKey(const ValueKey('insert-template-field')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'pending');
        await tester.pumpAndSettle();
        expect(find.text('Pending'), findsOneWidget);
        await tester.tap(find.text('Pending'));
        await tester.pumpAndSettle();
        expect(controller.text, 'Hello {balance_due}_world_ {customer_name}');
        expect(controller.selection.baseOffset, 6 + '{balance_due}'.length);
        await tester.ensureVisible(find.text('How to write a template'));
        await tester.tap(find.text('How to write a template'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Keep placeholders unchanged'),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await w.close();
    });
  }
}

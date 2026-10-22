import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/accounts/repositories/accounts_repository.dart';
import 'package:eden_booking/modules/accounts/screens/account_settings_screen.dart';
import 'package:eden_booking/modules/messages/models/message_template.dart';
import 'package:eden_booking/modules/messages/repositories/message_repository.dart';
import 'package:eden_booking/modules/messages/screens/message_preview_screen.dart';
import 'package:eden_booking/modules/messages/screens/template_editor_screen.dart';
import 'package:eden_booking/modules/messages/screens/templates_screen.dart';
import 'package:eden_booking/modules/messages/widgets/message_chat_preview.dart';
import 'package:eden_booking/modules/messages/widgets/message_phone_preview.dart';
import 'package:eden_booking/modules/sarvam/repositories/sarvam_repository.dart';
import 'package:eden_booking/modules/sarvam/screens/call_logs_screen.dart';
import 'package:eden_booking/modules/sarvam/screens/sarvam_settings_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'accounts_module_test.dart' show FakeAccountsRepository;
import 'booking_module_test.dart' show BookingSource;
import 'message_templates_test.dart' show TestMessages, TestShare, fixture;
import 'sarvam_test.dart' show TestSarvam, TestSaver;

/// Pumps [page] in a 1440x1000 desktop window.
Future<void> pumpDesktop(
  WidgetTester tester,
  WorkspaceCubit w,
  Widget page,
) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (c, s) => page)],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    BlocProvider.value(
      value: w,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (c, _) => MaterialApp.router(
          theme: AppTheme.build(Brightness.light),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<WorkspaceCubit> session() async {
  final w = WorkspaceCubit(BookingSource());
  await w.load();
  return w;
}

Future<(WorkspaceCubit, TestMessages, TestShare)> messages() async {
  final (_, w, r) = await fixture();
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
  final share = TestShare();
  registerFeatureDependencies(getIt);
  await getIt.unregister<MessageRepository>();
  getIt.registerSingleton<MessageRepository>(r);
  await getIt.unregister<MessageShareGateway>();
  getIt.registerSingleton<MessageShareGateway>(share);
  return (w, r, share);
}

Future<(WorkspaceCubit, TestSaver)> sarvam() async {
  final w = await session(), saver = TestSaver();
  registerFeatureDependencies(getIt);
  await getIt.unregister<SarvamRepository>();
  getIt.registerSingleton<SarvamRepository>(TestSarvam());
  await getIt.unregister<RecordingSaver>();
  getIt.registerSingleton<RecordingSaver>(saver);
  return (w, saver);
}

void main() {
  tearDown(() => getIt.reset());

  testWidgets('account settings shows the account grid and routing panel', (
    tester,
  ) async {
    final w = await session(), r = FakeAccountsRepository();
    addTearDown(w.close);
    registerFeatureDependencies(getIt);
    getIt.unregister<AccountsRepository>();
    getIt.registerSingleton<AccountsRepository>(r);
    await pumpDesktop(tester, w, const AccountSettingsScreen());
    expect(tester.takeException(), isNull);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Money accounts'), findsOneWidget);
    expect(find.text('Payment routing'), findsOneWidget);
    expect(find.text('In bank accounts'), findsOneWidget);
    expect(find.text('Primary bank'), findsOneWidget);
    expect(find.byType(AppStatTile), findsNWidgets(4));
    expect(find.text('Add bank account'), findsOneWidget);
    expect(find.text('Add another bank account'), findsOneWidget);
    expect(find.text('Transfer money'), findsOneWidget);
    // Routing panel sits to the right of the account grid.
    expect(
      tester.getTopLeft(find.text('Payment routing')).dx,
      greaterThan(tester.getTopLeft(find.text('Money accounts')).dx + 400),
    );
    expect(find.byType(AppPicker), findsNWidgets(3));
    await tester.tap(find.text('Court 1'));
    await tester.pumpAndSettle();
    expect(find.byType(AppPicker), findsNWidgets(6));
    await tester.tap(find.byTooltip('Manage HDFC Business'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Set as primary'), findsNothing);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Rename bank account'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(r.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('templates list sits beside a phone preview of the selection', (
    tester,
  ) async {
    final (w, r, _) = await messages();
    addTearDown(w.close);
    await pumpDesktop(tester, w, const TemplatesScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Your templates'), findsOneWidget);
    expect(find.text('Booking fields'), findsOneWidget);
    expect(find.byTooltip('Create template'), findsOneWidget);
    expect(find.byType(MessagePhonePreview), findsOneWidget);
    expect(
      find.byKey(const ValueKey('template-phone-default')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('template-tile-custom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('template-phone-custom')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    final bubble = tester.widget<SelectableText>(
      find.descendant(
        of: find.byType(MessagePhonePreview),
        matching: find.byType(SelectableText),
      ),
    );
    expect(bubble.textSpan!.toPlainText(), startsWith('Hi '));
    await tester.tap(find.byTooltip('Template options').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageChatPreview), findsOneWidget);
    await tester.tap(find.byTooltip('Close preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make primary'));
    await tester.pumpAndSettle();
    expect(r.value.primary.id, 'custom');
    expect(find.text('Make primary'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('template editor shows fields and a live phone preview', (
    tester,
  ) async {
    final (w, _, _) = await messages();
    addTearDown(w.close);
    await pumpDesktop(
      tester,
      w,
      const TemplateEditorScreen(source: MessageTemplate.predefined),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SegmentedButton<Object>), findsNothing);
    final field = find.byKey(const ValueKey('template-message-input'));
    final preview = find.byKey(const ValueKey('template-live-preview'));
    expect(field, findsOneWidget);
    expect(preview, findsOneWidget);
    expect(
      tester.getTopLeft(preview).dx,
      greaterThan(tester.getTopRight(field).dx),
    );
    expect(find.text('Save template').hitTestable(), findsOneWidget);
    await tester.enterText(field, 'Hello _world_ {customer_name}');
    await tester.pumpAndSettle();
    final bubble = tester.widget<SelectableText>(
      find.descendant(of: preview, matching: find.byType(SelectableText)),
    );
    expect(bubble.textSpan!.toPlainText(), 'Hello world Abin');
    await tester.tap(find.byKey(const ValueKey('insert-template-field')));
    await tester.pumpAndSettle();
    expect(find.text('Insert field'), findsWidgets);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('share booking shows the phone preview beside the actions', (
    tester,
  ) async {
    final (w, _, share) = await messages();
    addTearDown(w.close);
    await pumpDesktop(
      tester,
      w,
      const MessagePreviewScreen(bookingId: 'booking'),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(MessagePhonePreview), findsOneWidget);
    expect(find.text('Template · Booking confirmation'), findsOneWidget);
    await tester.tap(find.text('Copy message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share on WhatsApp'));
    await tester.pumpAndSettle();
    expect(share.copies, hasLength(1));
    expect(share.messages.single, share.copies.single);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Sarvam settings show automatic setup and separate booking controls',
    (tester) async {
      final (w, _) = await sarvam();
      addTearDown(w.close);
      await pumpDesktop(tester, w, const SarvamSettingsScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('Configured — awaiting publish'), findsOneWidget);
      expect(find.text('Connect Sarvam'), findsOneWidget);
      expect(find.text('Phone bookings'), findsOneWidget);
      expect(find.text('Connection status'), findsOneWidget);
      expect(find.text('Accept phone bookings'), findsOneWidget);
      expect(find.text('Publish changes'), findsOneWidget);
      expect(find.text('Disconnect Sarvam'), findsOneWidget);
      expect(find.text('Generate'), findsNothing);
      expect(find.text('Replace'), findsNothing);
      await tester.tap(find.text('Badminton'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Connect to apply the edited credentials or business selection.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('call logs open the transcript in a side pane', (tester) async {
    final (w, saver) = await sarvam();
    addTearDown(w.close);
    await pumpDesktop(tester, w, const CallLogsScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Talk time'), findsOneWidget);
    expect(find.text('2m 18s'), findsOneWidget);
    expect(find.text('Select a call'), findsOneWidget);
    expect(find.byTooltip('Refresh calls'), findsOneWidget);
    await tester.tap(find.text('Ebin'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Hi, this is Eden Sports.'), findsOneWidget);
    expect(find.text('Book a court for 8 PM.'), findsOneWidget);
    await tester.tap(find.text('Save recording'));
    await tester.pumpAndSettle();
    expect(saver.names.single, 'call-20260920-a71c352f-11-03-08-e6013eb8.wav');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Select a call'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

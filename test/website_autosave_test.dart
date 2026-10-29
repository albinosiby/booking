import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/booking_website/cubit/website_settings_cubit.dart';
import 'package:eden_booking/modules/booking_website/models/website_autosave.dart';
import 'package:eden_booking/modules/booking_website/models/website_content.dart';
import 'package:eden_booking/modules/booking_website/models/website_settings.dart';
import 'package:eden_booking/modules/booking_website/screens/website_settings_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/services/logo_picker_service.dart';
import 'booking_module_test.dart' show BookingSource;
import 'booking_website_test.dart' show TestWebsiteRepository;

Future<void> tick(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump();
}

void main() {
  tearDown(() => getIt.reset());
  testWidgets(
    'debounces edits, retains typing during save, serializes newer version',
    (tester) async {
      final session = WorkspaceCubit(BookingSource());
      await session.load();
      final repo = TestWebsiteRepository();
      final cubit = WebsiteSettingsCubit(
        session,
        repo,
        autosaveDelay: const Duration(milliseconds: 700),
      );
      await cubit.load();
      cubit.update(cubit.state.draft!.copyWith(title: 'First edit'));
      await tester.pump(const Duration(milliseconds: 400));
      cubit.update(cubit.state.draft!.copyWith(title: 'Second edit'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.saves, 0);
      repo.delayedSave = Completer<void>();
      await tick(tester);
      expect(repo.saves, 1);
      expect(cubit.state.autosaving, isTrue);
      expect(cubit.state.busy, isFalse);
      cubit.update(
        cubit.state.draft!.copyWith(
          title: 'Typing continues',
          description: 'New description',
        ),
      );
      await tick(tester);
      expect(repo.saves, 1);
      repo.delayedSave!.complete();
      await tester.pump();
      expect(cubit.state.draft!.title, 'Typing continues');
      expect(cubit.state.dirty, isTrue);
      repo.delayedSave = null;
      await tick(tester);
      expect(repo.saves, 2);
      expect(repo.writeVersions, [1, 2]);
      expect(repo.value.title, 'Typing continues');
      expect(cubit.state.dirty, isFalse);
      expect(repo.actions, isEmpty);
      await tester.runAsync(() async {
        await cubit.close();
        await session.close();
      });
    },
  );
  testWidgets(
    'invalid values wait, failure retains edits, explicit retry succeeds',
    (tester) async {
      final session = WorkspaceCubit(BookingSource());
      await session.load();
      final repo = TestWebsiteRepository();
      final auto = WebsiteSettingsCubit(
        session,
        repo,
        autosaveDelay: const Duration(milliseconds: 700),
      );
      await auto.load();
      auto.update(auto.state.draft!.copyWith(title: ''));
      await tick(tester);
      expect(repo.saves, 0);
      expect(auto.pendingValidation, isNotNull);
      repo.saveError = 'Offline';
      auto.update(auto.state.draft!.copyWith(title: 'Retained title'));
      await tick(tester);
      expect(auto.state.draft!.title, 'Retained title');
      expect(auto.state.error, contains('Offline'));
      expect(auto.state.autosaving, isFalse);
      await tick(tester);
      expect(repo.saves, 1);
      repo.saveError = null;
      expect(await auto.flushAutosave(), isTrue);
      expect(repo.value.title, 'Retained title');
      await tester.runAsync(() async {
        await auto.close();
        await session.close();
      });
    },
  );
  testWidgets('photo upload and removal autosave without publication', (
    tester,
  ) async {
    final session = WorkspaceCubit(BookingSource());
    await session.load();
    final repo = TestWebsiteRepository()
      ..selectedPhoto = LogoSelection(
        Uint8List.fromList([1, 2, 3]),
        'image/jpeg',
      );
    final auto = WebsiteSettingsCubit(
      session,
      repo,
      autosaveDelay: const Duration(milliseconds: 700),
    );
    await auto.load();
    await auto.photo(kind: 'hero');
    await tick(tester);
    expect(repo.uploads, 1);
    expect(auto.state.dirty, isFalse);
    expect(auto.state.draft!.images.single.pending, isFalse);
    await auto.photo(removeId: auto.state.draft!.images.single.id);
    await tick(tester);
    expect(repo.removals, 1);
    expect(auto.state.dirty, isFalse);
    expect(repo.actions, isEmpty);
    await tester.runAsync(() async {
      await auto.close();
      await session.close();
    });
  });
  testWidgets('close cancels scheduled writes', (tester) async {
    final source = BookingSource();
    final active = WorkspaceCubit(source);
    await active.load();
    final repo = TestWebsiteRepository();
    final auto = WebsiteSettingsCubit(
      active,
      repo,
      autosaveDelay: const Duration(milliseconds: 700),
    );
    await auto.load();
    auto.update(auto.state.draft!.copyWith(title: 'Cancelled'));
    await tester.runAsync(auto.close);
    await tick(tester);
    expect(repo.saves, 0);
    await tester.runAsync(active.close);
  });

  testWidgets(
    'workspace change cancels queued work and ignores in-flight results',
    (tester) async {
      final source = BookingSource(), repo = TestWebsiteRepository();
      final session = WorkspaceCubit(source);
      await session.load();
      final auto = WebsiteSettingsCubit(
        session,
        repo,
        autosaveDelay: const Duration(milliseconds: 700),
      );
      await auto.load();
      repo.delayedSave = Completer<void>();
      auto.update(auto.state.draft!.copyWith(title: 'Old organization'));
      await tick(tester);
      expect(repo.saves, 1);
      source.value = const Workspace();
      await session.load();
      await tester.pump();
      repo.delayedSave!.complete();
      await tester.pump();
      await tick(tester);
      expect(auto.state.draft, isNull);
      expect(repo.saves, 1);
      expect(repo.actions, isEmpty);
      await tester.runAsync(() async {
        await auto.close();
        await session.close();
      });
    },
  );
  testWidgets('publication waits for autosave and persists newer edits first', (
    tester,
  ) async {
    final session = WorkspaceCubit(BookingSource());
    await session.load();
    final repo = TestWebsiteRepository();
    final auto = WebsiteSettingsCubit(
      session,
      repo,
      autosaveDelay: const Duration(milliseconds: 700),
    );
    await auto.load();
    repo.delayedSave = Completer<void>();
    auto.update(auto.state.draft!.copyWith(title: 'First'));
    await tick(tester);
    auto.update(auto.state.draft!.copyWith(title: 'Latest'));
    final publication = auto.save(action: 'publish');
    expect(repo.actions, isEmpty);
    repo.delayedSave!.complete();
    await tester.pump();
    await publication;
    expect(repo.value.title, 'Latest');
    expect(repo.saves, 2);
    expect(repo.actions, ['publish']);
    expect(auto.state.dirty, isFalse);
    await tester.runAsync(() async {
      await auto.close();
      await session.close();
    });
  });
  test('server business metadata rebases while newer business text stays', () {
    final initial = TestWebsiteRepository().value;
    final latest = initial.copyWith(
      businesses: [
        initial.businesses.first.copyWith(description: 'New text'),
        initial.businesses.last,
      ],
    );
    final original = initial.businesses.first;
    final saved = initial.copyWith(
      version: 2,
      businesses: [
        WebsiteBusiness(
          id: original.id,
          name: original.name,
          type: original.type,
          status: 'paused',
          enabled: false,
          spaces: original.spaces,
        ),
        initial.businesses.last,
      ],
    );
    final result = rebaseWebsiteSave(initial, latest, saved);
    expect(result.businesses.first.description, 'New text');
    expect(result.businesses.first.status, 'paused');
    expect(result.businesses.first.enabled, isFalse);
    expect(result.version, 2);
  });
  testWidgets('editor autosaves without losing focus and flushes on back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = WorkspaceCubit(BookingSource());
    await session.load();
    final repo = TestWebsiteRepository();
    getIt.registerFactoryParam<WebsiteSettingsCubit, WorkspaceSession, void>(
      (s, _) => WebsiteSettingsCubit(
        s,
        repo,
        autosaveDelay: const Duration(milliseconds: 700),
      ),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/design'),
              child: const Text('Open designer'),
            ),
          ),
        ),
        GoRoute(
          path: '/design',
          builder: (_, _) => const WebsiteSettingsScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: session,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.tap(find.text('Open designer'));
    await tester.pumpAndSettle();
    TextFormField contentField(String label) => tester.widget<TextFormField>(
      find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is InputDecorator && w.decoration.labelText == label,
          skipOffstage: false,
        ),
        matching: find.byType(TextFormField, skipOffstage: false),
      ),
    );
    expect(
      contentField('Hero heading').initialValue,
      defaultWebsiteHeroHeading,
    );
    expect(
      contentField('Description').initialValue,
      defaultWebsiteDescription('Eden Sports'),
    );
    final field = find.byKey(const ValueKey('website-address-save'));
    expect(field, findsOneWidget);
    final address = find.byType(TextFormField).first;
    await tester.enterText(address, 'new-venue');
    await tick(tester);
    expect(repo.value.slug, 'new-venue');
    final editable = tester.widget<EditableText>(
      find.descendant(of: address, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.controller.text, 'new-venue');
    await tester.enterText(address, 'final-venue');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(repo.value.slug, 'final-venue');
    expect(find.text('Open designer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await tester.runAsync(session.close);
  });
}

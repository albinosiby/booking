import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/booking_website/cubit/website_photo_cubit.dart';
import 'package:eden_booking/modules/booking_website/cubit/website_settings_cubit.dart';
import 'package:eden_booking/modules/booking_website/repositories/rest_website_repository.dart';
import 'package:eden_booking/modules/booking_website/screens/website_settings_screen.dart';
import 'package:eden_booking/modules/booking_website/widgets/website_photo_settings.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'package:eden_booking/utils/services/logo_picker_service.dart';
import 'booking_module_test.dart' show BookingSource;

class PhotoApi extends Fake implements RestApiService {
  Map<String, dynamic> value = {
    'id': 'site-one',
    'version': 1,
    'slug': 'eden-sports',
    'title': 'Eden Sports',
    'description': '',
    'contact_phone': '+919876543210',
    'instructions': '',
    'cancellation_policy': '',
    'status': 'draft',
    'publish_logo': false,
    'notice_minutes': 0,
    'advance_days': 30,
    'businesses': [],
    'images': [
      {'id': 'hero', 'kind': 'hero'},
    ],
  };
  final reads = <String>[];
  int writes = 0;
  Completer<List<int>>? delayedPhoto;
  String? photoError;
  List<int> image = img.encodePng(img.Image(width: 4, height: 4));

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool readOnly = false,
  }) async {
    if (method != 'GET') {
      writes++;
      if (method == 'PUT') value.addAll(Map<String, dynamic>.from(data as Map));
      if (path == '/booking-website/images') {
        final upload = data as Map;
        value['images'] = [
          {
            'id': 'uploaded',
            'kind': upload['kind'],
            'business_id': upload['business_id'],
            'resource_id': upload['resource_id'],
          },
        ];
      }
      value['version'] = (value['version'] as int) + 1;
    }
    return {...value};
  }

  @override
  Future<List<int>> bytes(
    String path, {
    String errorMessage = 'Could not load the organization logo.',
  }) async {
    reads.add(path);
    if (photoError != null) throw AppException(photoError!);
    return delayedPhoto?.future ?? image;
  }
}

void main() {
  tearDown(() => getIt.reset());

  test(
    'settings and mutations complete while an image request is blocked or fails',
    () async {
      final api = PhotoApi()..delayedPhoto = Completer();
      final repository = RestWebsiteRepository(api);
      final initial = await repository.settings();
      expect(api.reads, isEmpty);
      expect(initial.images.single.bytes, isNull);
      final failedPhoto = expectLater(
        repository.photoBytes('hero'),
        throwsA(isA<AppException>()),
      );
      final saved = await repository.save(
        initial.copyWith(title: 'Edited while photo loads'),
      );
      await repository.publication('publish', saved.version);
      expect(api.writes, 2);
      expect(saved.title, 'Edited while photo loads');
      expect(saved.images.single.bytes, isNull);
      api.delayedPhoto!.completeError(const AppException('Photo offline'));
      await failedPhoto;
      expect((await repository.settings()).title, 'Edited while photo loads');
    },
  );

  test(
    'photo requests deduplicate, reuse cached bytes and support explicit retry',
    () async {
      final api = PhotoApi()..delayedPhoto = Completer();
      final repository = RestWebsiteRepository(api);
      await repository.settings();
      final first = repository.photoBytes('hero');
      final duplicate = repository.photoBytes('hero');
      await Future<void>.delayed(Duration.zero);
      expect(api.reads, hasLength(1));
      api.delayedPhoto!.complete(api.image);
      expect(await first, orderedEquals(api.image));
      expect(await duplicate, orderedEquals(api.image));
      final settings = await repository.settings();
      expect(
        settings.images.single.bytes,
        isNull,
        reason: 'Loading a preview must not hydrate editable models',
      );
      await repository.photoBytes('hero');
      expect(api.reads, hasLength(1));
      api.delayedPhoto = null;
      await repository.photoBytes('hero', refresh: true);
      expect(api.reads, hasLength(2));
    },
  );

  test('failed photos can retry without reloading settings', () async {
    final api = PhotoApi()..photoError = 'Photo offline';
    final repository = RestWebsiteRepository(api);
    await repository.settings();
    await expectLater(
      repository.photoBytes('hero'),
      throwsA(isA<AppException>()),
    );
    api.photoError = null;
    expect(await repository.photoBytes('hero'), isNotEmpty);
    expect(api.reads, hasLength(2));
  });

  test(
    'a successful upload retains its local preview without downloading it again',
    () async {
      final api = PhotoApi();
      final repository = RestWebsiteRepository(api);
      final saved = await repository.settings();
      final photo = LogoSelection(Uint8List.fromList(api.image), 'image/png');
      final result = await repository.uploadImage(
        photo,
        saved.version,
        kind: 'hero',
      );
      expect(result.images.single.id, 'uploaded');
      expect(result.images.single.bytes, isNull);
      expect(
        await repository.photoBytes('uploaded'),
        orderedEquals(photo.bytes),
      );
      expect(api.reads, isEmpty);
    },
  );

  for (final change in ['website', 'removed', 'disposed']) {
    test('late photo responses are rejected when $change', () async {
      final api = PhotoApi()..delayedPhoto = Completer();
      final repository = RestWebsiteRepository(api);
      await repository.settings();
      final rejected = expectLater(
        repository.photoBytes('hero'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'CANCELLED')),
      );
      await Future<void>.delayed(Duration.zero);
      if (change == 'disposed') {
        repository.clearPhotoCache();
      } else {
        if (change == 'website') api.value['id'] = 'site-two';
        if (change == 'removed') api.value['images'] = [];
        await repository.settings();
      }
      api.delayedPhoto!.complete(api.image);
      await rejected;
      if (change != 'website') {
        await expectLater(
          repository.photoBytes('hero'),
          throwsA(isA<AppException>()),
        );
      } else {
        api.delayedPhoto = null;
        await repository.photoBytes('hero');
        expect(
          api.reads,
          hasLength(2),
          reason: 'An old response must not populate the new website cache',
        );
      }
    });
  }

  test(
    'original-image cache stays bounded and evicts the least recently used photo',
    () async {
      final api = PhotoApi()..image = Uint8List(1024 * 1024);
      api.value['images'] = [
        for (var i = 0; i < 9; i++) {'id': 'photo-$i', 'kind': 'space'},
      ];
      final repository = RestWebsiteRepository(api);
      await repository.settings();
      for (var i = 0; i < 9; i++) {
        await repository.photoBytes('photo-$i');
      }
      await repository.photoBytes('photo-8');
      expect(api.reads, hasLength(9));
      await repository.photoBytes('photo-0');
      expect(api.reads, hasLength(10));
    },
  );

  test(
    'photo completion never overwrites typing or schedules autosave',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final api = PhotoApi()..delayedPhoto = Completer();
      final repository = RestWebsiteRepository(api);
      final editor = WebsiteSettingsCubit(
        workspace,
        repository,
        autosaveDelay: const Duration(milliseconds: 700),
      );
      await editor.load();
      final photo = WebsitePhotoCubit(workspace, repository, 'hero');
      final download = photo.load();
      await Future<void>.delayed(Duration.zero);
      editor.update(editor.state.draft!.copyWith(title: 'Keep my typing'));
      final draft = editor.state.draft;
      api.delayedPhoto!.complete(api.image);
      await download;
      expect(editor.state.draft, same(draft));
      expect(editor.state.dirty, isTrue);
      await editor.stream
          .firstWhere((state) => !state.dirty)
          .timeout(const Duration(seconds: 2));
      expect(api.writes, 1);
      expect(editor.state.dirty, isFalse);
      await photo.load();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(api.writes, 1, reason: 'Refreshing a preview is not a form edit');
      await photo.close();
      await editor.close();
      await workspace.close();
    },
  );

  for (final close in [false, true]) {
    test(
      'photo Cubit ignores a late result after ${close ? 'closing' : 'workspace removal'}',
      () async {
        final source = BookingSource();
        final workspace = WorkspaceCubit(source);
        await workspace.load();
        final api = PhotoApi()..delayedPhoto = Completer();
        final repository = RestWebsiteRepository(api);
        await repository.settings();
        final photo = WebsitePhotoCubit(workspace, repository, 'hero');
        final download = photo.load();
        if (close) {
          await photo.close();
        } else {
          source.value = const Workspace();
          await workspace.load();
        }
        api.delayedPhoto!.complete(api.image);
        await download;
        expect(photo.state.bytes, isNull);
        if (!close) {
          expect(photo.state.error, contains('workspace changed'));
          await photo.close();
        }
        await workspace.close();
      },
    );
  }

  testWidgets(
    'gallery and removed-space panels defer photos and retain pending downloads on reopen',
    (tester) async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final api = PhotoApi()..delayedPhoto = Completer();
      api.value['businesses'] = [
        {
          'id': 'business',
          'name': 'Court',
          'type': 'badminton',
          'status': 'active',
          'enabled': true,
          'resources': [
            {'id': 'court', 'name': 'Court one'},
          ],
        },
      ];
      api.value['images'] = [
        for (final id in ['one', 'two'])
          {
            'id': id,
            'kind': 'space',
            'business_id': 'business',
            'resource_id': 'court',
          },
        {
          'id': 'unused',
          'kind': 'space',
          'business_id': 'business',
          'resource_id': 'removed',
        },
      ];
      final repository = RestWebsiteRepository(api);
      final editor = WebsiteSettingsCubit(workspace, repository);
      await editor.load();
      final settings = editor.state.draft!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await editor.close();
        await workspace.close();
      });
      await tester.pumpWidget(
        BlocProvider.value(
          value: editor,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  key: const PageStorageKey('photo-test-scroll'),
                  child: Column(
                    children: [
                      WebsiteSpaceGallery(
                        settings: settings,
                        businessId: 'business',
                        spaceId: 'court',
                        disabled: false,
                        onUpload: () {},
                        onRemove: (_) {},
                      ),
                      WebsiteUnusedPhotos(
                        settings: settings,
                        disabled: false,
                        onRemove: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.reads, isEmpty);
      final gallery = find.text('Booking page photos');
      await tester.tap(gallery);
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.reads, hasLength(2));
      await tester.tap(gallery);
      await tester.pump(const Duration(milliseconds: 400));
      api.delayedPhoto!.complete(api.image);
      await tester.pumpAndSettle();
      api.delayedPhoto = null;
      await tester.tap(gallery);
      await tester.pumpAndSettle();
      expect(api.reads, hasLength(2));
      final removed = find.text('Photos of removed spaces');
      await tester.ensureVisible(removed);
      await tester.tap(removed);
      await tester.pumpAndSettle();
      expect(api.reads, hasLength(3));
      expect(editor.state.dirty, isFalse);
      expect(api.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'editor opens before photos and retries a photo locally at $width pixels',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final workspace = WorkspaceCubit(BookingSource());
        await workspace.load();
        final api = PhotoApi()..delayedPhoto = Completer();
        final repository = RestWebsiteRepository(api);
        late WebsiteSettingsCubit editor;
        getIt
            .registerFactoryParam<WebsiteSettingsCubit, WorkspaceSession, void>(
              (session, _) =>
                  editor = WebsiteSettingsCubit(session, repository),
            );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await workspace.close();
        });
        await tester.pumpWidget(
          BlocProvider.value(
            value: workspace,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) =>
                  MaterialApp(home: const WebsiteSettingsScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(editor.state.loading, isFalse);
        expect(editor.state.dirty, isFalse);
        expect(
          api.reads,
          isEmpty,
          reason: 'Collapsed panels must not fetch images',
        );
        final brand = width >= 1180
            ? find.byKey(const ValueKey('website-nav-1'))
            : find.text('Brand & homepage');
        await tester.ensureVisible(brand);
        await tester.tap(brand);
        await tester.pumpAndSettle();
        expect(api.reads, isEmpty);
        final hero = find.text('Hero image');
        await tester.ensureVisible(hero);
        await tester.tap(hero);
        await tester.pump(const Duration(milliseconds: 400));
        expect(api.reads, hasLength(1));
        expect(find.bySemanticsLabel('Loading photo'), findsOneWidget);
        final title = find.widgetWithText(TextFormField, 'Website title');
        await tester.ensureVisible(title);
        await tester.enterText(title, 'Typing while photo is offline');
        api.delayedPhoto!.completeError(const AppException('Photo offline'));
        await tester.pumpAndSettle();
        expect(editor.state.error, isNull);
        expect(editor.state.draft!.title, 'Typing while photo is offline');
        expect(api.writes, 0);
        final retry = find.text('Retry photo');
        await tester.ensureVisible(retry);
        api.delayedPhoto = null;
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(api.reads, hasLength(2));
        expect(find.text('Retry photo'), findsNothing);
        await tester.ensureVisible(hero);
        await tester.tap(hero);
        await tester.pumpAndSettle();
        await tester.tap(hero);
        await tester.pumpAndSettle();
        expect(
          api.reads,
          hasLength(2),
          reason: 'Reopening a panel should use the session cache',
        );
        expect(editor.state.draft!.title, 'Typing while photo is offline');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

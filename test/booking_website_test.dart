import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:eden_booking/modules/booking_website/repositories/website_photo_encoder.dart';
import 'package:eden_booking/utils/services/logo_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/booking_website/cubit/website_settings_cubit.dart';
import 'package:eden_booking/modules/booking_website/models/website_settings.dart';
import 'package:eden_booking/modules/booking_website/repositories/website_repository.dart';
import 'package:eden_booking/modules/booking_website/repositories/rest_website_repository.dart';
import 'package:eden_booking/modules/booking_website/screens/website_settings_screen.dart';
import 'package:eden_booking/modules/booking_website/widgets/website_editor_section.dart';
import 'package:eden_booking/modules/booking_website/widgets/website_photo_settings.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource;

class TestWebsiteRepository implements WebsiteRepository {
  TestWebsiteRepository({bool pathLinks = false})
    : value = WebsiteSettings(
        version: 1,
        slug: 'eden-sports',
        title: 'Eden Sports',
        description: '',
        phone: '+919876543210',
        instructions: '',
        cancellationPolicy: '',
        status: 'draft',
        publishLogo: false,
        noticeMinutes: 0,
        advanceDays: 30,
        businesses: const [
          WebsiteBusiness(
            id: 'business',
            name: 'Badminton',
            type: 'badminton',
            status: 'ready',
            enabled: true,
            spaces: [
              WebsiteSpace(id: 'court-1', name: 'Court 1'),
              WebsiteSpace(id: 'court-2', name: 'Court 2'),
            ],
          ),
          WebsiteBusiness(
            id: 'pool',
            name: 'Pool',
            type: 'pool',
            status: 'ready',
            enabled: true,
            spaces: [WebsiteSpace(id: 'lane', name: 'Lane')],
          ),
        ],
        businessIds: const ['business', 'pool'],
        domain: pathLinks ? null : 'bookingos.online',
        url: pathLinks
            ? 'https://venues.example.test/eden-sports'
            : 'https://eden-sports.bookingos.online',
      );
  WebsiteSettings value;
  int reads = 0, saves = 0, uploads = 0, picks = 0, removals = 0;
  String? saveError;
  String? pickError;
  int? failUploadAt;
  final writeVersions = <int>[];
  final photoWrites = <WebsiteImage>[];
  final photoOperations = <String>[];
  Completer<void>? delayedSave;
  Completer<void>? delayedUpload;
  String? uploadedBusiness, uploadedResource, uploadedKind;
  Completer<LogoSelection?>? delayedPick;
  LogoSelection? selectedPhoto;
  final actions = <String>[];
  Completer<WebsiteSettings>? delayed;
  @override
  Future<WebsiteSettings> settings() async {
    reads++;
    return delayed?.future ?? value;
  }

  @override
  Future<WebsiteSettings> save(WebsiteSettings draft) async {
    saves++;
    writeVersions.add(draft.version);
    if (delayedSave != null) await delayedSave!.future;
    if (saveError != null) throw AppException(saveError!);
    value = draft.copyWith(
      images: value.images,
      version: value.version + 1,
      url: draft.domain == null
          ? Uri.parse(value.url!).replace(path: '/${draft.slug}').toString()
          : draft.draftUrl,
    );
    return value;
  }

  @override
  Future<WebsiteSettings> publication(String action, int version) async {
    actions.add(action);
    return value;
  }

  @override
  Future<LogoSelection?> pickImage() async {
    picks++;
    if (pickError != null) throw AppException(pickError!);
    return delayedPick?.future ?? selectedPhoto;
  }

  @override
  Future<WebsiteSettings> uploadImage(
    LogoSelection image,
    int version, {
    required String kind,
    String? businessId,
    String? resourceId,
  }) async {
    uploads++;
    photoOperations.add('upload:$kind');
    writeVersions.add(version);
    expect(version, value.version);
    if (uploads == failUploadAt) {
      throw const AppException('Photo upload failed.', code: 'REQUEST_ERROR');
    }
    if (delayedUpload != null) await delayedUpload!.future;
    uploadedKind = kind;
    uploadedBusiness = businessId;
    uploadedResource = resourceId;
    final photo = WebsiteImage(
      id: 'saved-photo-$uploads',
      kind: kind,
      businessId: businessId,
      resourceId: resourceId,
      bytes: image.bytes,
    );
    photoWrites.add(photo);
    value = value.copyWith(
      version: value.version + 1,
      images: [
        for (final current in value.images)
          if (kind == 'space' ||
              current.kind != kind ||
              current.businessId != businessId ||
              current.resourceId != resourceId)
            current,
        photo,
      ],
    );
    return value;
  }

  @override
  Future<WebsiteSettings> removeImage(String id, int version) async {
    removals++;
    photoOperations.add('remove:$id');
    writeVersions.add(version);
    expect(version, value.version);
    value = value.copyWith(
      version: value.version + 1,
      images: [
        for (final image in value.images)
          if (image.id != id) image,
      ],
    );
    return value;
  }

  @override
  Future<String> preview() async => '${value.url}?preview=test';
  @override
  Future<void> open(String url) async {}
  @override
  Future<void> copy(String url) async {}
}

void main() {
  tearDown(() => getIt.reset());
  test(
    'owner edits and publication save the draft before publishing',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository();
      final settings = WebsiteSettingsCubit(workspace, repo);
      await settings.load();
      settings.update(settings.state.draft!.copyWith(title: 'Updated venue'));
      expect(settings.state.dirty, isTrue);
      await settings.save(action: 'publish');
      expect(repo.saves, 1);
      expect(repo.value.title, 'Updated venue');
      expect(repo.actions, ['publish']);
      expect(settings.state.dirty, isFalse);
      await settings.close();
      await workspace.close();
    },
  );
  test(
    'address save updates a published URL and retains other unsaved design edits',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository();
      repo.value = repo.value.copyWith(status: 'published');
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      cubit.update(
        cubit.state.draft!.copyWith(slug: 'New-Venue', title: 'Unsaved title'),
      );
      await cubit.saveAddress();
      expect(repo.value.slug, 'new-venue');
      expect(repo.value.title, 'Eden Sports');
      expect(repo.value.status, 'published');
      expect(cubit.state.saved!.url, 'https://new-venue.bookingos.online');
      expect(cubit.state.draft!.url, cubit.state.saved!.url);
      expect(cubit.state.draft!.title, 'Unsaved title');
      expect(cubit.state.draft!.version, cubit.state.saved!.version);
      expect(cubit.state.addressDirty, isFalse);
      expect(cubit.state.dirty, isTrue);
      await cubit.save();
      expect(repo.value.title, 'Unsaved title');
      expect(repo.value.slug, 'new-venue');
      expect(cubit.state.dirty, isFalse);
    },
  );

  test(
    'invalid and conflicting addresses retain the saved link and can be corrected',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository();
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      final original = cubit.state.saved!.url;
      cubit.update(cubit.state.draft!.copyWith(slug: 'bad--name'));
      await cubit.saveAddress();
      expect(repo.saves, 0);
      expect(cubit.state.addressError, contains('single hyphens'));
      repo.saveError = 'This website address is already taken. Choose another.';
      cubit.update(cubit.state.draft!.copyWith(slug: 'another-venue'));
      await cubit.saveAddress();
      expect(cubit.state.saved!.url, original);
      expect(cubit.state.draft!.slug, 'another-venue');
      expect(cubit.state.addressError, contains('already taken'));
      expect(cubit.state.busy, isFalse);
      repo.saveError = null;
      await cubit.saveAddress();
      expect(cubit.state.saved!.url, 'https://another-venue.bookingos.online');
      expect(cubit.state.addressError, isNull);
      expect(cubit.state.dirty, isFalse);
    },
  );

  test(
    'address save ignores a response after workspace access changes',
    () async {
      final source = BookingSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final repo = TestWebsiteRepository()..delayedSave = Completer<void>();
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      cubit.update(cubit.state.draft!.copyWith(slug: 'changed-address'));
      final saving = cubit.saveAddress();
      await cubit.saveAddress();
      expect(repo.saves, 1);
      source.value = const Workspace();
      await workspace.load();
      repo.delayedSave!.complete();
      await saving;
      expect(cubit.state.saved, isNull);
      expect(cubit.state.draft, isNull);
    },
  );

  test('staff cannot read or edit website settings', () async {
    final source = BookingSource();
    source.value = Workspace(
      organization: source.value.organization,
      membership: const {
        'role': 'staff',
        'permissions': ['view_bookings'],
      },
      businesses: source.value.businesses,
    );
    final workspace = WorkspaceCubit(source);
    await workspace.load();
    final repo = TestWebsiteRepository();
    final settings = WebsiteSettingsCubit(workspace, repo);
    await settings.load();
    expect(settings.state.saved, isNull);
    expect(settings.state.error, contains('Only the owner'));
    expect(repo.reads, 0);
    await settings.close();
    await workspace.close();
  });
  test(
    'a delayed owner response is discarded after workspace access changes',
    () async {
      final source = BookingSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final repo = TestWebsiteRepository()
        ..delayed = Completer<WebsiteSettings>();
      final settings = WebsiteSettingsCubit(workspace, repo);
      final request = settings.load();
      source.value = const Workspace();
      await workspace.load();
      repo.delayed!.complete(repo.value);
      await request;
      expect(settings.state.saved, isNull);
      expect(settings.state.error, contains("workspace changed"));
      await settings.close();
      await workspace.close();
    },
  );
  test(
    'all photo kinds stay local alongside text edits until Save changes',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository()
        ..selectedPhoto = LogoSelection(
          Uint8List.fromList([1, 2, 3]),
          'image/jpeg',
        );
      final cubit = WebsiteSettingsCubit(workspace, repo);
      await cubit.load();
      cubit.update(cubit.state.draft!.copyWith(title: 'Unsaved title'));
      await cubit.photo();
      await cubit.photo(businessId: 'business', resourceId: 'court-1');
      await cubit.photo(kind: 'card', businessId: 'pool');
      await cubit.photo(kind: 'logo');
      expect(repo.picks, 4);
      expect(repo.saves, 0);
      expect(repo.uploads, 0);
      expect(repo.value.images, isEmpty);
      expect(repo.value.title, 'Eden Sports');
      expect(cubit.state.draft!.title, 'Unsaved title');
      expect(cubit.state.draft!.images, hasLength(4));
      expect(cubit.state.draft!.images.every((i) => i.pending), isTrue);
      expect(cubit.state.dirty, isTrue);
      await cubit.save();
      expect(repo.saves, 1);
      expect(repo.uploads, 4);
      expect(repo.photoWrites.map((i) => i.kind), [
        'hero',
        'space',
        'card',
        'logo',
      ]);
      expect(repo.photoWrites[1].businessId, 'business');
      expect(repo.photoWrites[1].resourceId, 'court-1');
      expect(repo.photoWrites[2].businessId, 'pool');
      expect(repo.photoWrites[2].resourceId, isNull);
      expect(repo.writeVersions, [1, 2, 3, 4, 5]);
      expect(repo.uploadedKind, 'logo');
      expect(repo.uploadedBusiness, isNull);
      expect(cubit.state.saved!.images.every((i) => !i.pending), isTrue);
      expect(cubit.state.message, 'Website settings saved.');
      expect(cubit.state.dirty, isFalse);
      expect(cubit.state.busy, isFalse);
      await cubit.close();
      await workspace.close();
    },
  );
  test(
    'workspace change while choosing a photo cannot upload into another workspace',
    () async {
      final source = BookingSource();
      final scopedWorkspace = WorkspaceCubit(source);
      await scopedWorkspace.load();
      final repo = TestWebsiteRepository()
        ..delayedPick = Completer<LogoSelection?>();
      final cubit = WebsiteSettingsCubit(scopedWorkspace, repo);
      await cubit.load();
      final picking = cubit.photo();
      source.value = const Workspace();
      await scopedWorkspace.load();
      repo.delayedPick!.complete(
        LogoSelection(Uint8List.fromList([1]), 'image/jpeg'),
      );
      await picking;
      expect(repo.uploads, 0);
      expect(cubit.state.saved, isNull);
      await cubit.close();
      await scopedWorkspace.close();
    },
  );
  test(
    'replacing a logo twice uploads only the final selection on save',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository();
      repo.value = repo.value.copyWith(
        images: const [WebsiteImage(id: 'old-logo', kind: 'logo')],
      );
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      repo.selectedPhoto = LogoSelection(Uint8List.fromList([1]), 'image/jpeg');
      await cubit.photo(kind: 'logo');
      repo.selectedPhoto = LogoSelection(Uint8List.fromList([2]), 'image/jpeg');
      await cubit.photo(kind: 'logo');
      expect(cubit.state.draft!.images, hasLength(1));
      expect(repo.value.images.single.id, 'old-logo');
      expect(repo.uploads, 0);
      expect(cubit.state.settingsDirty, isFalse);
      await cubit.save();
      expect(repo.saves, 0);
      expect(repo.removals, 0);
      expect(repo.uploads, 1);
      expect(repo.value.images.single.bytes, [2]);
      expect(cubit.state.dirty, isFalse);
    },
  );

  test(
    'removals stay local and removing a new selection cancels its upload',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository();
      repo.value = repo.value.copyWith(
        images: const [WebsiteImage(id: 'old-logo', kind: 'logo')],
      );
      repo.selectedPhoto = LogoSelection(Uint8List.fromList([1]), 'image/jpeg');
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      await cubit.photo();
      await cubit.photo(removeId: cubit.state.draft!.image('hero')!.id);
      expect(cubit.state.dirty, isFalse);
      await cubit.photo(removeId: 'old-logo');
      expect(repo.value.images, hasLength(1));
      expect(repo.removals, 0);
      expect(cubit.state.dirty, isTrue);
      await cubit.save();
      expect(repo.removals, 1);
      expect(repo.uploads, 0);
      expect(repo.saves, 0);
      expect(repo.value.images, isEmpty);
      expect(cubit.state.dirty, isFalse);
    },
  );

  test(
    'failed photo save retains remaining changes without repeating acknowledged writes',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository()
        ..selectedPhoto = LogoSelection(Uint8List.fromList([1]), 'image/jpeg')
        ..failUploadAt = 2;
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      cubit.update(
        cubit.state.draft!.copyWith(title: 'Saved after explicit click'),
      );
      await cubit.photo();
      await cubit.photo(kind: 'logo');
      await cubit.save();
      expect(repo.saves, 1);
      expect(repo.value.images.map((i) => i.kind), ['hero']);
      expect(
        cubit.state.draft!.images.where((i) => i.pending).map((i) => i.kind),
        ['logo'],
      );
      expect(cubit.state.dirty, isTrue);
      expect(cubit.state.settingsDirty, isFalse);
      expect(cubit.state.error, contains('Photo upload failed'));
      expect(cubit.state.busy, isFalse);
      repo.failUploadAt = null;
      await cubit.save();
      expect(repo.saves, 1);
      expect(repo.photoWrites.map((i) => i.kind), ['hero', 'logo']);
      expect(repo.value.images, hasLength(2));
      expect(cubit.state.dirty, isFalse);
    },
  );

  test(
    'address-only save preserves pending photos and other design edits',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository()
        ..selectedPhoto = LogoSelection(Uint8List.fromList([1]), 'image/jpeg');
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      cubit.update(
        cubit.state.draft!.copyWith(slug: 'new-name', title: 'Not saved yet'),
      );
      await cubit.photo(kind: 'logo');
      await cubit.saveAddress();
      expect(repo.value.slug, 'new-name');
      expect(repo.value.title, 'Eden Sports');
      expect(repo.value.images, isEmpty);
      expect(repo.uploads, 0);
      expect(cubit.state.draft!.images.single.pending, isTrue);
      expect(cubit.state.draft!.title, 'Not saved yet');
      expect(cubit.state.dirty, isTrue);
      await cubit.save();
      expect(repo.value.title, 'Not saved yet');
      expect(repo.uploads, 1);
      expect(cubit.state.dirty, isFalse);
    },
  );
  test(
    'saving a gallery replacement frees the persisted slot before uploading',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository()
        ..selectedPhoto = LogoSelection(Uint8List.fromList([1]), 'image/jpeg');
      repo.value = repo.value.copyWith(
        images: [
          for (var i = 0; i < 4; i++)
            WebsiteImage(
              id: 'saved-$i',
              kind: 'space',
              businessId: 'business',
              resourceId: 'court-1',
            ),
        ],
      );
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      await cubit.photo(removeId: 'saved-0');
      await cubit.photo(businessId: 'business', resourceId: 'court-1');
      expect(repo.value.images, hasLength(4));
      expect(repo.removals, 0);
      expect(repo.uploads, 0);
      await cubit.save();
      expect(repo.removals, 1);
      expect(repo.uploads, 1);
      expect(repo.writeVersions, [1, 2]);
      expect(repo.photoOperations, ['remove:saved-0', 'upload:space']);
      expect(repo.value.images, hasLength(4));
      expect(repo.value.images.any((i) => i.id == 'saved-0'), isFalse);
      expect(cubit.state.dirty, isFalse);
    },
  );

  test(
    'workspace changes during save stop the remaining photo uploads and publication',
    () async {
      final source = BookingSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final repo = TestWebsiteRepository()
        ..selectedPhoto = LogoSelection(Uint8List.fromList([1]), 'image/jpeg')
        ..delayedUpload = Completer<void>();
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      await cubit.photo();
      await cubit.photo(kind: 'logo');
      final saving = cubit.save(action: 'publish');
      await cubit.save(action: 'publish');
      expect(repo.uploads, 1);
      source.value = const Workspace();
      await workspace.load();
      repo.delayedUpload!.complete();
      await saving;
      expect(repo.uploads, 1);
      expect(repo.actions, isEmpty);
      expect(cubit.state.saved, isNull);
      expect(cubit.state.draft, isNull);
    },
  );

  test(
    'local gallery selection enforces the four-photo limit and frees removed slots',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository()
        ..selectedPhoto = LogoSelection(Uint8List.fromList([1]), 'image/jpeg');
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      for (var i = 0; i < 5; i++) {
        await cubit.photo(businessId: 'business', resourceId: 'court-1');
      }
      expect(repo.picks, 4);
      expect(repo.uploads, 0);
      expect(cubit.state.draft!.images, hasLength(4));
      expect(cubit.state.error, contains('Photo limit'));
      await cubit.photo(removeId: cubit.state.draft!.images.first.id);
      await cubit.photo(businessId: 'business', resourceId: 'court-1');
      expect(repo.picks, 5);
      await cubit.save();
      expect(repo.value.images, hasLength(4));
      expect(repo.uploads, 4);
      expect(cubit.state.dirty, isFalse);
    },
  );

  test(
    'cancelling photo selection keeps existing text edits without writing',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository();
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      cubit.update(cubit.state.draft!.copyWith(title: 'Keep this edit'));
      await cubit.photo();
      expect(cubit.state.draft!.title, 'Keep this edit');
      expect(cubit.state.draft!.images, isEmpty);
      expect(repo.saves, 0);
      expect(repo.uploads, 0);
      expect(cubit.state.busy, isFalse);
      expect(cubit.state.dirty, isTrue);
    },
  );
  test(
    'the total draft photo limit allows replacing an existing single-photo slot',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository()
        ..selectedPhoto = LogoSelection(Uint8List.fromList([1]), 'image/jpeg');
      repo.value = repo.value.copyWith(
        images: [
          const WebsiteImage(id: 'hero', kind: 'hero'),
          for (var i = 1; i < websitePhotoLimit; i++)
            WebsiteImage(
              id: 'photo-$i',
              kind: 'space',
              businessId: 'business',
              resourceId: 'space-$i',
            ),
        ],
      );
      final cubit = WebsiteSettingsCubit(workspace, repo);
      addTearDown(() async {
        await cubit.close();
        await workspace.close();
      });
      await cubit.load();
      await cubit.photo(kind: 'logo');
      expect(repo.picks, 0);
      expect(cubit.state.error, contains('Photo limit'));
      await cubit.photo();
      expect(repo.picks, 1);
      expect(cubit.state.draft!.images, hasLength(websitePhotoLimit));
      await cubit.save();
      expect(repo.uploads, 1);
      expect(repo.removals, 0);
      expect(cubit.state.dirty, isFalse);
    },
  );

  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'logo selection stays unsaved until the save button at $width pixels',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final workspace = WorkspaceCubit(BookingSource());
        await workspace.load();
        final repo = TestWebsiteRepository()
          ..selectedPhoto = LogoSelection(
            Uint8List.fromList(img.encodeJpg(img.Image(width: 4, height: 4))),
            'image/jpeg',
          );
        getIt
            .registerFactoryParam<WebsiteSettingsCubit, WorkspaceSession, void>(
              (s, _) => WebsiteSettingsCubit(s, repo),
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
        final editor = find.byKey(
          const PageStorageKey('website-editor-content'),
        );
        final brand = width >= 1180
            ? find.byKey(const ValueKey('website-nav-1'))
            : find.descendant(
                of: editor,
                matching: find.text('Brand & homepage'),
              );
        await tester.ensureVisible(brand);
        await tester.tap(brand);
        await tester.pumpAndSettle();
        final title = find.widgetWithText(TextFormField, 'Website title');
        await tester.ensureVisible(title);
        await tester.enterText(title, 'Venue with a pending logo');
        await tester.pumpAndSettle();
        final slot = find.ancestor(
          of: find.text('Website logo'),
          matching: find.byType(WebsitePhotoSlot),
        );
        final upload = find.descendant(
          of: slot,
          matching: find.widgetWithText(OutlinedButton, 'Upload photo'),
        );
        await tester.ensureVisible(upload);
        await tester.tap(upload);
        await tester.pumpAndSettle();
        expect(repo.picks, 1);
        expect(repo.saves, 0);
        expect(repo.uploads, 0);
        expect(repo.value.images, isEmpty);
        expect(find.text('Not saved yet'), findsOneWidget);
        expect(find.text('You have unsaved changes'), findsOneWidget);
        final save = find.widgetWithText(AppButton, 'Save changes');
        expect(tester.widget<AppButton>(save).onPressed, isNotNull);
        expect(
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, 'Preview'))
              .onPressed,
          isNull,
        );
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repo.saves, 1);
        expect(repo.uploads, 1);
        expect(repo.value.title, 'Venue with a pending logo');
        expect(repo.value.images.single.kind, 'logo');
        expect(find.text('Not saved yet'), findsNothing);
        expect(find.text('All changes saved'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (width, existingPhotos, selectionFails) in [
    (390.0, 0, false),
    (1440.0, 0, false),
    (390.0, 1, false),
    (1440.0, 1, false),
    (390.0, 0, true),
    (1440.0, 0, true),
  ]) {
    testWidgets(
      'space image selection displays preview or error at $width pixels with $existingPhotos existing photos (failure: $selectionFails)',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final workspace = WorkspaceCubit(BookingSource());
        await workspace.load();
        final repo = TestWebsiteRepository()
          ..selectedPhoto = LogoSelection(
            Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8))),
            'image/jpeg',
          );
        if (selectionFails) repo.pickError = 'Choose an image up to 10 MB.';
        repo.value = repo.value.copyWith(
          images: [
            for (var index = 0; index < existingPhotos; index++)
              WebsiteImage(
                id: 'existing-photo-$index',
                kind: 'space',
                businessId: 'business',
                resourceId: 'court-1',
                bytes: repo.selectedPhoto!.bytes,
              ),
          ],
        );
        getIt
            .registerFactoryParam<WebsiteSettingsCubit, WorkspaceSession, void>(
              (session, _) => WebsiteSettingsCubit(session, repo),
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
        final editor = find.byKey(
          const PageStorageKey('website-editor-content'),
        );
        final section = width >= 1180
            ? find.byKey(const ValueKey('website-nav-2'))
            : find.descendant(
                of: editor,
                matching: find.text('Services & spaces'),
              );
        await tester.ensureVisible(section);
        await tester.tap(section);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Court 1'));
        await tester.tap(find.text('Court 1'));
        await tester.pumpAndSettle();
        final upload = find.text('Add space photo ($existingPhotos/4)').first;
        await tester.ensureVisible(upload);
        await tester.tap(upload);
        await tester.pumpAndSettle();
        expect(repo.picks, 1);
        expect(repo.uploads, 0);
        if (selectionFails) {
          final feedback = find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('Choose an image up to 10 MB.'),
          );
          expect(feedback, findsOneWidget);
          expect(
            tester.getRect(feedback).overlaps(Rect.fromLTWH(0, 0, width, 1000)),
            isTrue,
          );
          expect(find.text('Not saved yet'), findsNothing);
          expect(
            tester
                .widget<AppButton>(
                  find.widgetWithText(AppButton, 'Save changes'),
                )
                .onPressed,
            isNull,
          );
          expect(tester.takeException(), isNull);
          return;
        }
        expect(find.text('Not saved yet'), findsOneWidget);
        final thumbnail = find.ancestor(
          of: find.text('Not saved yet'),
          matching: find.byType(WebsitePhotoTile),
        );
        expect(thumbnail, findsOneWidget);
        expect(
          tester.getRect(thumbnail).overlaps(Rect.fromLTWH(0, 0, width, 1000)),
          isTrue,
        );
        final image = tester.widget<WebsitePhotoTile>(thumbnail).image;
        expect(image.kind, 'space');
        expect(image.businessId, 'business');
        expect(image.resourceId, 'court-1');
        expect(image.bytes, isNotEmpty);
        final displayedImage = find.descendant(
          of: thumbnail,
          matching: find.byType(Image),
        );
        expect(displayedImage, findsOneWidget);
        expect(
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, 'Save changes'))
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'one space\'s booking and payment rules copy to every space and persist after reload',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository();
      final cubit = WebsiteSettingsCubit(workspace, repo);
      await cubit.load();
      final source = cubit.state.draft!.businesses.first.spaces.first.copyWith(
        noticeMinutes: () => 60,
        advanceDays: () => 7,
        rules: 'Non-marking shoes only.',
        paymentRequired: true,
        paymentPercentages: [25, 50],
      );
      cubit.updateSpace('business', source);
      cubit.updateSpace(
        'business',
        cubit.state.draft!.businesses.first.spaces.last.copyWith(
          visible: false,
        ),
      );
      final revision = cubit.state.revision;
      cubit.copyRulesToAll(source);
      expect(cubit.state.revision, revision + 1);
      final spaces = [
        for (final b in cubit.state.draft!.businesses) ...b.spaces,
      ];
      expect(spaces.map((s) => s.advanceDays), everyElement(7));
      expect(spaces.map((s) => s.noticeMinutes), everyElement(60));
      expect(
        spaces.map((s) => s.rules),
        everyElement('Non-marking shoes only.'),
      );
      expect(spaces.map((s) => s.paymentRequired), everyElement(isTrue));
      for (final space in spaces) {
        expect(space.paymentPercentages, [25, 50]);
      }
      // Visibility is a per-space choice and is not copied.
      expect(spaces.where((s) => !s.visible).map((s) => s.id), ['court-2']);
      await cubit.save();
      expect(repo.value.businesses.last.spaces.single.advanceDays, 7);
      await cubit.load();
      for (final business in cubit.state.draft!.businesses) {
        for (final space in business.spaces) {
          expect(space.paymentRequired, isTrue);
          expect(space.paymentPercentages, [25, 50]);
        }
      }
      expect(cubit.state.dirty, isFalse);
      await cubit.close();
      await workspace.close();
    },
  );
  test(
    'copying optional payment clears mandatory payment and choices across all spaces',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = TestWebsiteRepository();
      repo.value = repo.value.copyWith(
        businesses: [
          for (final business in repo.value.businesses)
            business.copyWith(
              spaces: [
                for (final space in business.spaces)
                  space.copyWith(
                    paymentRequired: true,
                    paymentPercentages: [50, 100],
                  ),
              ],
            ),
        ],
      );
      final cubit = WebsiteSettingsCubit(workspace, repo);
      await cubit.load();
      final source = cubit.state.draft!.businesses.first.spaces.first.copyWith(
        paymentRequired: false,
        paymentPercentages: [],
      );
      cubit.updateSpace('business', source);
      cubit.copyRulesToAll(source);
      for (final business in cubit.state.draft!.businesses) {
        for (final space in business.spaces) {
          expect(space.paymentRequired, isFalse);
          expect(space.paymentPercentages, isEmpty);
        }
      }
      await cubit.save();
      await cubit.load();
      for (final business in cubit.state.draft!.businesses) {
        for (final space in business.spaces) {
          expect(space.paymentRequired, isFalse);
          expect(space.paymentPercentages, isEmpty);
        }
      }
      expect(cubit.state.dirty, isFalse);
      await cubit.close();
      await workspace.close();
    },
  );
  test('social links accept pasted addresses without a scheme', () {
    expect(
      normaliseSocialLink(' instagram.com/eden '),
      'https://instagram.com/eden',
    );
    expect(normaliseSocialLink('https://wa.me/91900'), 'https://wa.me/91900');
    expect(normaliseSocialLink('  '), '');
  });
  test('photo encoding resizes images and strips camera metadata', () {
    final original = img.Image(width: 2000, height: 20);
    original.exif.imageIfd.make = 'Private camera';
    final source = Uint8List.fromList(img.encodeJpg(original));
    expect(img.decodeJpg(source)!.exif.imageIfd.make, 'Private camera');
    final bytes = encodeWebsitePhoto(LogoSelection(source, 'image/jpeg'));
    final decoded = img.decodeJpg(bytes)!;
    expect(decoded.width, 1920);
    expect(decoded.exif.isEmpty, isTrue);
    expect(bytes.length, lessThanOrEqualTo(1024 * 1024));
  });
  test('photo encoding rejects corrupt image data', () {
    expect(
      () => encodeWebsitePhoto(
        LogoSelection(Uint8List.fromList([1, 2, 3]), 'image/jpeg'),
      ),
      throwsA(isA<Exception>()),
    );
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets(
      'published address edits save and update the header at $width pixels',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final workspace = WorkspaceCubit(BookingSource());
        await workspace.load();
        final repo = TestWebsiteRepository();
        repo.value = repo.value.copyWith(status: 'published');
        getIt
            .registerFactoryParam<WebsiteSettingsCubit, WorkspaceSession, void>(
              (s, _) => WebsiteSettingsCubit(s, repo),
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
              builder: (_, _) => MaterialApp(
                home: const WebsiteSettingsScreen(),
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(
                    textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                  ),
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final name = find.widgetWithText(TextFormField, 'Website name');
        final save = find.byKey(const ValueKey('website-address-save'));
        final header = find.byKey(const ValueKey('website-saved-url'));
        expect(
          tester.widget<SelectableText>(header).data,
          'https://eden-sports.bookingos.online',
        );
        await tester.ensureVisible(name);
        await tester.enterText(name, '');
        await tester.pumpAndSettle();
        // The fixed parts stay visible even when the editable name is empty.
        expect(find.text('https://').hitTestable(), findsOneWidget);
        expect(find.text('.bookingos.online'), findsOneWidget);
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repo.saves, 0);
        expect(find.textContaining('Use 3–63'), findsOneWidget);
        await tester.ensureVisible(name);
        await tester.enterText(name, 'renamed-venue');
        await tester.pumpAndSettle();
        expect(
          tester.widget<SelectableText>(header).data,
          'https://eden-sports.bookingos.online',
        );
        repo.saveError =
            'This website address is already taken. Choose another.';
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.textContaining('already taken'), findsOneWidget);
        expect(find.text('Reload settings'), findsOneWidget);
        expect(
          tester.widget<SelectableText>(header).data,
          'https://eden-sports.bookingos.online',
        );
        repo.saveError = null;
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SelectableText>(header).data,
          'https://renamed-venue.bookingos.online',
        );
        expect(repo.value.status, 'published');
        expect(
          tester.getTopLeft(header).dy,
          lessThan(
            tester
                .getTopLeft(
                  find.descendant(
                    of: find.byType(WebsiteEditorSection).first,
                    matching: find.text('Website address'),
                  ),
                )
                .dy,
          ),
        );
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'path-hosted editor keeps URL parts and sidebar summary visible at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final workspace = WorkspaceCubit(BookingSource());
        await workspace.load();
        final repo = TestWebsiteRepository(pathLinks: true);
        repo.value = repo.value.copyWith(status: 'published');
        getIt
            .registerFactoryParam<WebsiteSettingsCubit, WorkspaceSession, void>(
              (s, _) => WebsiteSettingsCubit(s, repo),
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
              builder: (_, _) => MaterialApp(
                theme: darkTheme(),
                home: const WebsiteSettingsScreen(),
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(
                    textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                  ),
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final summary = find.byKey(const ValueKey('website-saved-url'));
        final live = find.byKey(const ValueKey('website-current-live-url'));
        final name = find.widgetWithText(TextFormField, 'Website name');
        final save = find.byKey(const ValueKey('website-address-save'));
        expect(
          tester.widget<SelectableText>(summary).data,
          'https://eden-sports.bookingos.online',
        );
        expect(
          tester.widget<SelectableText>(live).data,
          'https://venues.example.test/eden-sports',
        );
        await tester.ensureVisible(name);
        await tester.enterText(name, '');
        await tester.pumpAndSettle();
        expect(find.text('https://').hitTestable(), findsOneWidget);
        expect(find.text('.bookingos.online'), findsOneWidget);
        await tester.enterText(name, 'updated-venue');
        await tester.pumpAndSettle();
        expect(
          tester.widget<SelectableText>(summary).data,
          'https://eden-sports.bookingos.online',
        );
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SelectableText>(summary).data,
          'https://updated-venue.bookingos.online',
        );
        expect(
          tester.widget<SelectableText>(live).data,
          'https://venues.example.test/updated-venue',
        );
        expect(repo.value.domain, isNull);
        if (width >= 1180) {
          await tester.tap(find.byKey(const ValueKey('website-nav-1')));
          await tester.pumpAndSettle();
          expect(summary.hitTestable(), findsNothing);
          // Scrolling without using the sidebar must update its selection too.
          await tester.ensureVisible(
            find.widgetWithText(TextFormField, 'Card description').first,
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<ListTile>(find.byKey(const ValueKey('website-nav-2')))
                .selected,
            isTrue,
          );
          await tester.tap(find.byKey(const ValueKey('website-nav-0')));
          await tester.pumpAndSettle();
          expect(summary.hitTestable(), findsOneWidget);
          expect(live.hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [390.0, 1440.0]) {
    testWidgets('website settings render without overflow at $width pixels', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repository = TestWebsiteRepository();
      getIt.registerFactoryParam<WebsiteSettingsCubit, WorkspaceSession, void>(
        (s, _) => WebsiteSettingsCubit(s, repository),
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, _) =>
                const MaterialApp(home: WebsiteSettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editor = find.byKey(const PageStorageKey('website-editor-content'));
      final list = find
          .descendant(of: editor, matching: find.byType(Scrollable))
          .first;
      Finder heading(String label) =>
          find.descendant(of: editor, matching: find.text(label));
      expect(find.text('Design website'), findsOneWidget);
      expect(heading('Website address'), findsOneWidget);
      expect(find.text('.bookingos.online'), findsOneWidget);
      expect(heading('Brand & homepage'), findsOneWidget);
      expect(heading('Services & spaces'), findsOneWidget);
      await tester.ensureVisible(heading('Services & spaces'));
      if (width < 1180) {
        await tester.tap(heading('Services & spaces'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Homepage card'), findsNWidgets(2));
      await tester.scrollUntilVisible(
        find.text('Court 1'),
        300,
        scrollable: list,
      );
      await tester.ensureVisible(find.text('Court 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Court 1'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Copy these rules to all spaces'),
        300,
        scrollable: list,
      );
      expect(find.text('Copy these rules to all spaces'), findsOneWidget);
      await tester.scrollUntilVisible(
        heading('Social media'),
        300,
        scrollable: list,
      );
      if (width < 1180) {
        await tester.tap(heading('Social media'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Instagram'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await workspace.close();
    });
  }
  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'service spaces survive enabling after scroll and saving at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final workspace = WorkspaceCubit(BookingSource());
        await workspace.load();
        final repo = TestWebsiteRepository();
        repo.value = repo.value.copyWith(businessIds: []);
        getIt
            .registerFactoryParam<WebsiteSettingsCubit, WorkspaceSession, void>(
              (s, _) => WebsiteSettingsCubit(s, repo),
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
              builder: (_, _) => MaterialApp(
                theme: darkTheme(),
                home: const WebsiteSettingsScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final editor = find.byKey(
          const PageStorageKey('website-editor-content'),
        );
        if (width >= 1180) {
          await tester.tap(find.byKey(const ValueKey('website-nav-2')));
        } else {
          final heading = find.descendant(
            of: editor,
            matching: find.text('Services & spaces'),
          );
          await tester.ensureVisible(heading);
          await tester.pumpAndSettle();
          await tester.tap(heading);
        }
        await tester.pumpAndSettle();
        final badminton = find.widgetWithText(CheckboxListTile, 'Badminton');
        await tester.ensureVisible(badminton);
        await tester.pumpAndSettle();
        // A nonzero scroll offset is now persisted before the space tiles mount.
        final scroll = tester.widget<SingleChildScrollView>(editor);
        expect(
          Scrollable.of(tester.element(badminton)).position.pixels,
          greaterThan(0),
        );
        expect(scroll.key, const PageStorageKey('website-editor-content'));
        await tester.tap(badminton);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final court = find.widgetWithText(ExpansionTile, 'Court 1');
        await tester.ensureVisible(court);
        await tester.tap(find.text('Court 1'));
        await tester.pumpAndSettle();
        final rules = find.widgetWithText(
          TextFormField,
          'Space rules for visitors',
        );
        await tester.ensureVisible(rules);
        await tester.enterText(rules, 'Wear court shoes.');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(AppButton, 'Save changes'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          repo.value.businesses.first.spaces.first.rules,
          'Wear court shoes.',
        );
        expect(
          tester.widget<TextFormField>(rules).initialValue,
          'Wear court shoes.',
        );
        expect(find.byType(ErrorWidget), findsNothing);
        // The rebuilt scroll view must still restore a number, not expansion state.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          BlocProvider.value(
            value: workspace,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp(
                theme: darkTheme(),
                home: const WebsiteSettingsScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'editor retains edits and reveals invalid collapsed fields at $width pixels',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final workspace = WorkspaceCubit(BookingSource());
        await workspace.load();
        final repo = TestWebsiteRepository();
        getIt
            .registerFactoryParam<WebsiteSettingsCubit, WorkspaceSession, void>(
              (s, _) => WebsiteSettingsCubit(s, repo),
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
              builder: (_, _) => MaterialApp(
                theme: darkTheme(),
                home: const WebsiteSettingsScreen(),
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(
                    c,
                  ).copyWith(textScaler: const TextScaler.linear(1.3)),
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final editor = find.byKey(
          const PageStorageKey('website-editor-content'),
        );
        Finder heading(String text) =>
            find.descendant(of: editor, matching: find.text(text));
        Future<void> open(int index, String label) async {
          if (width >= 1180) {
            final nav = find.byKey(ValueKey('website-nav-$index'));
            if (nav.hitTestable().evaluate().isEmpty) {
              await tester.ensureVisible(nav);
            }
            await tester.tap(nav);
          } else {
            await tester.ensureVisible(heading(label));
            await tester.tap(heading(label));
          }
          await tester.pumpAndSettle();
        }

        final save = find.widgetWithText(AppButton, 'Save changes');
        final saveTop = tester.getTopLeft(save);
        await open(1, 'Brand & homepage');
        final title = find.widgetWithText(TextFormField, 'Website title');
        await tester.ensureVisible(title);
        await tester.enterText(title, 'Fresh venue');
        await tester.pumpAndSettle();
        final phone = find.widgetWithText(
          TextFormField,
          'Public contact phone',
        );
        await tester.ensureVisible(phone);
        await tester.enterText(phone, 'bad');
        await tester.pumpAndSettle();
        expect(find.text('You have unsaved changes'), findsOneWidget);
        expect(
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, 'Preview'))
              .onPressed,
          isNull,
        );
        if (width < 1180) {
          await tester.ensureVisible(heading('Brand & homepage'));
          await tester.tap(heading('Brand & homepage'));
          await tester.pumpAndSettle();
          expect(title, findsNothing);
        } else {
          final nav = find.byKey(const ValueKey('website-nav-3'));
          await tester.ensureVisible(nav);
          await tester.pumpAndSettle();
          final navTop = tester.getTopLeft(nav);
          await tester.tap(nav);
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(nav), navTop);
          expect(
            find.widgetWithText(TextFormField, 'Instagram').hitTestable(),
            findsOneWidget,
          );
        }
        expect(tester.getTopLeft(save), saveTop);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repo.saves, 0);
        expect(
          find.text('Enter a valid phone number.').hitTestable(),
          findsOneWidget,
        );
        final titleField = tester.widget<TextFormField>(title);
        expect(titleField.initialValue, 'Fresh venue');
        await tester.enterText(phone, '+919876543210');
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repo.saves, 1);
        expect(repo.value.title, 'Fresh venue');
        expect(find.text('All changes saved'), findsOneWidget);
        expect(
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, 'Preview'))
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

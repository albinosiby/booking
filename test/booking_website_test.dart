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
import 'package:eden_booking/modules/booking_website/screens/website_settings_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'booking_module_test.dart' show BookingSource;

class TestWebsiteRepository implements WebsiteRepository {
  WebsiteSettings value = const WebsiteSettings(
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
    addressLocked: false,
    businesses: [
      WebsiteBusiness(
        id: 'business',
        name: 'Badminton',
        type: 'badminton',
        status: 'ready',
        enabled: true,
        spaces: [WebsiteSpace(id: 'court-1', name: 'Court 1')],
      ),
    ],
    businessIds: ['business'],
    url: 'http://localhost:3000/eden-sports',
  );
  int reads = 0, saves = 0, uploads = 0, picks = 0;
  String? uploadedBusiness, uploadedResource;
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
    value = draft;
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
    return delayedPick?.future ?? selectedPhoto;
  }

  @override
  Future<WebsiteSettings> uploadImage(
    LogoSelection image,
    int version, {
    String? businessId,
    String? resourceId,
  }) async {
    uploads++;
    uploadedBusiness = businessId;
    uploadedResource = resourceId;
    return value;
  }

  @override
  Future<WebsiteSettings> removeImage(String id, int version) async => value;
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
    'photo upload is scoped to a space and blocked until edits are saved',
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
      expect(repo.picks, 0);
      await cubit.save();
      await cubit.photo(businessId: 'business', resourceId: 'court-1');
      expect(repo.uploads, 1);
      expect(repo.uploadedBusiness, 'business');
      expect(repo.uploadedResource, 'court-1');
      expect(cubit.state.message, 'Website photo saved.');
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
      expect(find.text('Booking website'), findsOneWidget);
      expect(find.text('Businesses available online'), findsOneWidget);
      expect(find.text('Upload hero image'), findsOneWidget);
      expect(find.text('Booking space photos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await workspace.close();
    });
  }
}

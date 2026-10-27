import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/organization/cubit/location_catalog_cubit.dart';
import 'package:eden_booking/modules/organization/cubit/organization_cubit.dart';
import 'package:eden_booking/modules/organization/models/location_catalog.dart';
import 'package:eden_booking/modules/organization/models/organization_draft.dart';
import 'package:eden_booking/modules/organization/repositories/organization_repository.dart';
import 'package:eden_booking/modules/organization/screens/organization_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/logo_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _Workspace extends Fake implements WorkspaceRepository {
  @override
  Future<Workspace> load() async => const Workspace();
}

class _OrgRepo extends Fake implements OrganizationRepository {
  final created = <OrganizationDraft>[];
  final logos = <(Uint8List, String)>[];
  Completer<void>? wait;
  Object? createFailure, catalogFailure, statesFailure;
  @override
  Future<void> create(OrganizationDraft draft) async {
    created.add(draft);
    await wait?.future;
    if (createFailure != null) throw createFailure!;
  }

  @override
  Future<void> uploadLogo(Uint8List bytes, String contentType) async {
    logos.add((bytes, contentType));
  }

  @override
  Future<LocationCatalog> catalog() async {
    if (catalogFailure != null) throw catalogFailure!;
    return LocationCatalog(
      countries: const [
        CatalogOption('IN', 'India'),
        CatalogOption('US', 'United States'),
      ],
      timezones: const ['Asia/Kolkata', 'America/New_York'],
    );
  }

  @override
  Future<List<CatalogOption>> states(String country) async {
    if (statesFailure != null) throw statesFailure!;
    return country == 'IN'
        ? const [
            CatalogOption('KL', 'Kerala'),
            CatalogOption('TN', 'Tamil Nadu'),
          ]
        : const [];
  }
}

class _Picker extends LogoPickerService {
  LogoSelection? selection;
  Object? failure;
  @override
  Future<LogoSelection?> pick({int maxBytes = 0}) async {
    if (failure != null) throw failure!;
    return selection;
  }
}

/// A confirmed defect, kept but skipped. The id is in the test name.
void bugWidgets(String bug, String name, WidgetTesterCallback body) =>
    testWidgets('[$bug] $name', body, skip: true);

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<_OrgRepo> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  _Picker? picker,
  void Function(_OrgRepo)? setup,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await getIt.reset();
  addTearDown(getIt.reset);
  final repo = _OrgRepo();
  setup?.call(repo);
  getIt.registerFactoryParam<OrganizationCubit, WorkspaceSession, void>(
    (s, _) => OrganizationCubit(s, repo),
  );
  getIt.registerFactory<LocationCatalogCubit>(() => LocationCatalogCubit(repo));
  getIt.registerLazySingleton<LogoPickerService>(() => picker ?? _Picker());
  final workspace = WorkspaceCubit(_Workspace());
  addTearDown(workspace.close);
  await workspace.load();
  await tester.pumpWidget(
    BlocProvider.value(
      value: workspace,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: darkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const OrganizationScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _text(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), value);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, String label, String option) async {
  final picker = find.widgetWithText(InputDecorator, label);
  await tester.ensureVisible(picker.first);
  await tester.pumpAndSettle();
  await tester.tap(picker.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> _fillValid(
  WidgetTester tester, {
  String org = 'Eden Sports',
  String phone = '9876543210',
  String branch = 'Eden Arena, Kochi',
  String line1 = '14 Garden Road',
  String line2 = '',
  String city = 'Kochi',
  String pin = '682001',
  bool chooseState = true,
}) async {
  await _text(tester, 'Organization name', org);
  await _text(tester, 'Contact number', phone);
  await _text(tester, 'Property / branch name', branch);
  await _text(tester, 'Address line 1', line1);
  if (line2.isNotEmpty) await _text(tester, 'Address line 2 · optional', line2);
  await _text(tester, 'City', city);
  await _text(tester, 'Pincode / postal code', pin);
  if (chooseState) await _pick(tester, 'State / province', 'Kerala');
}

Future<void> _continue(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Continue');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

void main() {
  group('required and format validation', () {
    testWidgets('empty submit lists every required field and sends nothing', (
      tester,
    ) async {
      final repo = await _mount(tester);
      await _continue(tester);
      expect(find.text('Enter at least two characters'), findsNWidgets(4));
      expect(find.text('Enter a valid contact number'), findsOneWidget);
      expect(find.text('Enter a six-digit Indian pincode'), findsOneWidget);
      expect(find.text('Select State / province'), findsWidgets);
      expect(repo.created, isEmpty);
    });

    testWidgets('whitespace-only values are treated as empty', (tester) async {
      final repo = await _mount(tester);
      await _fillValid(
        tester,
        org: '   ',
        phone: '      ',
        branch: '   ',
        line1: '    ',
        city: '   ',
        pin: '      ',
      );
      await _continue(tester);
      expect(repo.created, isEmpty);
      expect(find.text('Enter a valid contact number'), findsOneWidget);
      expect(find.text('Enter at least two characters'), findsNWidgets(4));
    });

    for (final bad in ['1', '12345', '12 34', '     5']) {
      testWidgets('contact number "$bad" is too short', (tester) async {
        final repo = await _mount(tester);
        await _fillValid(tester, phone: bad);
        await _continue(tester);
        expect(find.text('Enter a valid contact number'), findsOneWidget);
        expect(repo.created, isEmpty);
      });
    }

    for (final good in [
      '9876543210',
      '+91 98765 43210',
      '(0484) 123-4567',
      '  9876543210  ',
    ]) {
      testWidgets('contact number "$good" is accepted and trimmed', (
        tester,
      ) async {
        final repo = await _mount(tester);
        await _fillValid(tester, phone: good);
        await _continue(tester);
        await tester.pumpAndSettle();
        expect(repo.created, hasLength(1));
        expect(repo.created.single.phone, good.trim());
      });
    }

    for (final bad in [
      'abcdefgh',
      '!!!!!!!',
      'call me later',
      '😀😀😀😀😀😀',
    ]) {
      bugWidgets(
        'BUG-15',
        'letters, symbols or emoji "$bad" are not a phone number',
        (tester) async {
          final repo = await _mount(tester);
          await _fillValid(tester, phone: bad);
          await _continue(tester);
          expect(repo.created, isEmpty);
        },
      );
    }

    bugWidgets('BUG-15', 'a 60 digit contact number is rejected', (
      tester,
    ) async {
      final repo = await _mount(tester);
      await _fillValid(tester, phone: '9' * 60);
      await _continue(tester);
      expect(repo.created, isEmpty);
    });

    bugWidgets(
      'BUG-15',
      'creation rules for phone match the edit screen rules (6-15 digits)',
      (tester) async {
        final repo = await _mount(tester);
        // Accepted here but rejected by OrganizationEditCubit.validate.
        await _fillValid(tester, phone: '-----6');
        await _continue(tester);
        expect(repo.created, isEmpty);
      },
    );

    for (final bad in [
      '12345',
      '012345',
      '1234567',
      '12 3456',
      'ABCDEF',
      '68200a',
    ]) {
      testWidgets('Indian pincode "$bad" is rejected', (tester) async {
        final repo = await _mount(tester);
        await _fillValid(tester, pin: bad);
        await _continue(tester);
        expect(find.text('Enter a six-digit Indian pincode'), findsOneWidget);
        expect(repo.created, isEmpty);
      });
    }

    testWidgets('pincode pasted with surrounding spaces is trimmed', (
      tester,
    ) async {
      final repo = await _mount(tester);
      await _fillValid(tester, pin: '  682001 \n');
      await _continue(tester);
      await tester.pumpAndSettle();
      expect(repo.created.single.location.postalCode, '682001');
    });

    testWidgets('non-Indian postal codes only need to be non-empty', (
      tester,
    ) async {
      final repo = await _mount(tester);
      await _text(tester, 'Organization name', 'Eden US');
      await _text(tester, 'Contact number', '2125551234');
      await _text(tester, 'Property / branch name', 'Brooklyn site');
      await _text(tester, 'Address line 1', '1 Main St');
      await _text(tester, 'City', 'New York');
      await _pick(tester, 'Country', 'United States');
      await _text(tester, 'Pincode / postal code', 'SW1A 1AA');
      await _continue(tester);
      await tester.pumpAndSettle();
      expect(repo.created.single.location.countryCode, 'US');
      expect(repo.created.single.location.stateCode, isNull);
      expect(repo.created.single.location.postalCode, 'SW1A 1AA');
    });

    testWidgets('organization name length limits and unicode', (tester) async {
      final repo = await _mount(tester);
      await _fillValid(tester, org: 'a' * 121);
      await _continue(tester);
      expect(find.text('Use 120 characters or fewer'), findsOneWidget);
      expect(repo.created, isEmpty);
      await _text(tester, 'Organization name', 'ഏബിൻ Sports & Co. 🏸');
      await _continue(tester);
      await tester.pumpAndSettle();
      expect(repo.created.single.name, 'ഏബിൻ Sports & Co. 🏸');
    });

    bugWidgets('BUG-1', 'an organization name of 61 emoji is accepted', (
      tester,
    ) async {
      final repo = await _mount(tester);
      await _fillValid(tester, org: '🏸' * 61);
      await _continue(tester);
      await tester.pumpAndSettle();
      expect(repo.created, hasLength(1));
    });

    bugWidgets(
      'BUG-16',
      'address and city have the same limits as the edit screen (200/120)',
      (tester) async {
        final repo = await _mount(tester);
        // The edit screen limits line1 to 200 characters; creation accepts 120.
        await _fillValid(tester, line1: 'x' * 190);
        await _continue(tester);
        await tester.pumpAndSettle();
        expect(repo.created, hasLength(1));
      },
    );

    testWidgets('address line 2 is optional and sent as null when blank', (
      tester,
    ) async {
      final repo = await _mount(tester);
      await _fillValid(tester);
      await _text(tester, 'Address line 2 · optional', '   ');
      await _continue(tester);
      await tester.pumpAndSettle();
      expect(repo.created.single.location.line2, isNull);
    });

    testWidgets('submitted values are trimmed and carry the chosen state', (
      tester,
    ) async {
      final repo = await _mount(tester);
      await _fillValid(
        tester,
        org: '  Eden Sports  ',
        branch: ' Eden Arena ',
        line1: ' 14 Garden Road ',
        line2: ' Near the park ',
        city: ' Kochi ',
      );
      await _continue(tester);
      await tester.pumpAndSettle();
      final d = repo.created.single;
      expect(d.name, 'Eden Sports');
      expect(d.location.name, 'Eden Arena');
      expect(d.location.line1, '14 Garden Road');
      expect(d.location.line2, 'Near the park');
      expect(d.location.city, 'Kochi');
      expect(d.location.stateCode, 'KL');
      expect(d.location.countryCode, 'IN');
      expect(d.currency, 'INR');
      expect(d.location.timezone, 'Asia/Kolkata');
    });

    testWidgets('state must be chosen when the country has states', (
      tester,
    ) async {
      final repo = await _mount(tester);
      await _fillValid(tester, chooseState: false);
      await _continue(tester);
      expect(find.text('Select State / province'), findsWidgets);
      expect(repo.created, isEmpty);
    });
  });

  group('double submit, loading, errors', () {
    testWidgets('double tap on Continue creates exactly one organization', (
      tester,
    ) async {
      final repo = await _mount(tester, setup: (r) => r.wait = Completer());
      await _fillValid(tester);
      final button = find.widgetWithText(FilledButton, 'Continue');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(repo.created, hasLength(1));
      repo.wait!.complete();
      await tester.pumpAndSettle();
      expect(repo.created, hasLength(1));
    });

    testWidgets('failed create shows the server message and keeps the form', (
      tester,
    ) async {
      final repo = await _mount(
        tester,
        setup: (r) =>
            r.createFailure = const AppException('Name already used.'),
      );
      await _fillValid(tester);
      await _continue(tester);
      await tester.pumpAndSettle();
      expect(find.text('Name already used.'), findsOneWidget);
      expect(find.text('Eden Sports'), findsOneWidget);
      repo.createFailure = null;
      await _continue(tester);
      await tester.pumpAndSettle();
      expect(repo.created, hasLength(2));
    });

    testWidgets('unexpected failure shows a generic message', (tester) async {
      await _mount(
        tester,
        setup: (r) => r.createFailure = StateError('db password=hunter2'),
      );
      await _fillValid(tester);
      await _continue(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('hunter2'), findsNothing);
      expect(find.textContaining('Could not save'), findsOneWidget);
    });

    testWidgets('catalog failure blocks Continue and offers retry', (
      tester,
    ) async {
      final repo = await _mount(
        tester,
        setup: (r) => r.catalogFailure = const AppException('Offline'),
      );
      expect(find.text('Offline'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNull,
      );
      repo.catalogFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNotNull,
      );
    });
  });

  group('logo selection', () {
    testWidgets('chosen logo uploads after the organization is created', (
      tester,
    ) async {
      final picker = _Picker()..selection = LogoSelection(_png, 'image/png');
      final repo = await _mount(tester, picker: picker);
      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();
      expect(find.text('Change image'), findsOneWidget);
      await _fillValid(tester);
      await _continue(tester);
      await tester.pumpAndSettle();
      expect(repo.created, hasLength(1));
      expect(repo.logos.single.$2, 'image/png');
    });

    testWidgets('picker rejection is shown and the form stays usable', (
      tester,
    ) async {
      final picker = _Picker()
        ..failure = const AppException('Choose an image up to 2 MB.');
      await _mount(tester, picker: picker);
      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();
      expect(find.text('Choose an image up to 2 MB.'), findsOneWidget);
      expect(find.text('Choose image'), findsOneWidget);
    });

    testWidgets('cancelled picker keeps the placeholder', (tester) async {
      await _mount(tester, picker: _Picker());
      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();
      expect(find.text('Change image'), findsNothing);
    });
  });

  group('small screen and large text', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('form fits 320x568 at text scale $scale with all errors', (
        tester,
      ) async {
        await _mount(tester, size: const Size(320, 568), scale: scale);
        await _continue(tester);
        expect(tester.takeException(), isNull);
        await _fillValid(
          tester,
          org: 'N' * 120,
          branch: 'B' * 120,
          line1: 'L' * 110,
          city: 'C' * 110,
        );
        await _continue(tester);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    bugWidgets(
      'BUG-17',
      'picker sheet (AppPicker) does not overflow at 320x568 and 3x text',
      (tester) async {
        await _mount(tester, size: const Size(320, 568), scale: 3);
        await _text(tester, 'Pincode / postal code', '682001');
        final state = find.widgetWithText(InputDecorator, 'State / province');
        await tester.ensureVisible(state.first);
        await tester.pumpAndSettle();
        await tester.tap(state.first, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('Search'), findsOneWidget, reason: 'sheet is open');
        expect(tester.takeException(), isNull);
      },
    );
  });
}

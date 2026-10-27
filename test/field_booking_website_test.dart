// Field-value tests for lib/modules/booking_website: website address, title,
// phone, social links, notice/advance numbers, photo size, double submit and
// small-screen / large-text rendering. Real defects are skipped as `BUG-<n>`.
import 'dart:typed_data';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/booking_website/cubit/website_settings_cubit.dart';
import 'package:eden_booking/modules/booking_website/models/website_settings.dart';
import 'package:eden_booking/modules/booking_website/repositories/rest_website_repository.dart'
    show normaliseSocialLink;
import 'package:eden_booking/modules/booking_website/screens/website_settings_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/services/logo_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'booking_module_test.dart' show BookingSource;
import 'booking_website_test.dart' show TestWebsiteRepository;
import 'dart:async';

void main() {
  group('websiteAddressError', () {
    test('accepts valid slugs (case and surrounding space are normalised)', () {
      for (final v in [
        'abc',
        'a-b-c',
        'abc123',
        '123',
        'a1b',
        'a' * 63,
        'ABC',
        ' abc ',
        'Eden-Sports',
      ]) {
        expect(websiteAddressError(v), isNull, reason: '"$v"');
      }
    });
    test('rejects invalid slugs', () {
      for (final v in [
        null,
        '',
        ' ',
        'a',
        'ab',
        'a' * 64,
        '-abc',
        'abc-',
        'a--b',
        'a_b',
        'a b',
        'a.b',
        'a/b',
        'a@b',
        'é-test',
        'அபி-test',
        '😀😀😀',
        'abc\nabc',
        'abc%20',
        '../x',
      ]) {
        expect(websiteAddressError(v), isNotNull, reason: '"$v"');
      }
    });
    test(
      'BUG-15 reserved or confusing slugs are refused before save',
      () {
        for (final v in ['www', 'admin', 'api', 'app', 'mail']) {
          expect(websiteAddressError(v), isNotNull, reason: v);
        }
      },
      skip:
          'BUG-15: reserved hostnames (www, api, admin, mail) pass client validation; only the server can refuse them',
    );
  });

  group('normaliseSocialLink', () {
    test('adds https only when no scheme is present', () {
      expect(normaliseSocialLink(''), '');
      expect(normaliseSocialLink('   '), '');
      expect(
        normaliseSocialLink(' instagram.com/x '),
        'https://instagram.com/x',
      );
      expect(normaliseSocialLink('https://x.com/a'), 'https://x.com/a');
      expect(normaliseSocialLink('http://x.com/a'), 'http://x.com/a');
      expect(
        normaliseSocialLink('javascript:alert(1)'),
        'https://javascript:alert(1)',
      );
      expect(normaliseSocialLink('ftp://x.com'), 'ftp://x.com');
      expect(normaliseSocialLink('😀'), 'https://😀');
    });
  });

  group('WebsiteSettings model', () {
    test('websiteAddress uses http for localhost and https otherwise', () {
      const base = WebsiteSettings(
        version: 1,
        slug: 'eden',
        title: 't',
        description: '',
        phone: '',
        instructions: '',
        cancellationPolicy: '',
        status: 'draft',
        publishLogo: false,
        noticeMinutes: 0,
        advanceDays: 1,
        businesses: [],
        businessIds: [],
      );
      expect(base.websiteAddress, 'https://eden.bookingos.online');
      expect(
        base.copyWith(slug: 'x').websiteAddress,
        'https://x.bookingos.online',
      );
      expect(base.draftUrl, isNull);
    });
    test('space customised flag and rule copying', () {
      const plain = WebsiteSpace(id: 's', name: 'S');
      expect(plain.customised, isFalse);
      expect(plain.copyWith(rules: ' ').customised, isTrue);
      expect(plain.copyWith(noticeMinutes: () => 0).customised, isTrue);
      expect(plain.copyWith(visible: false).customised, isTrue);
      final copied = const WebsiteSpace(id: 'other', name: 'O').withRulesOf(
        plain.copyWith(noticeMinutes: () => 30, rules: 'No shoes 😀'),
      );
      expect(copied.id, 'other');
      expect(copied.noticeMinutes, 30);
      expect(copied.rules, 'No shoes 😀');
    });
  });

  group('website settings cubit', () {
    Future<(WorkspaceCubit, TestWebsiteRepository, WebsiteSettingsCubit)>
    make() async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = TestWebsiteRepository();
      final c = WebsiteSettingsCubit(w, r);
      await c.load();
      return (w, r, c);
    }

    test('invalid address never reaches the repository', () async {
      final (w, r, c) = await make();
      for (final slug in ['', 'ab', 'a--b', '-ab', 'a_b', '😀😀😀', 'a' * 64]) {
        c.update(c.state.draft!.copyWith(slug: slug));
        await c.saveAddress();
        expect(c.state.addressError, isNotNull, reason: '"$slug"');
        expect(r.saves, 0);
      }
      await c.close();
      await w.close();
    });

    test(
      'valid address is lowercased and trimmed, double tap saves once',
      () async {
        final (w, r, c) = await make();
        r.delayedSave = Completer<void>();
        c.update(c.state.draft!.copyWith(slug: '  New-Name  '));
        final a = c.saveAddress(), b = c.saveAddress();
        await Future<void>.delayed(Duration.zero);
        r.delayedSave!.complete();
        await Future.wait([a, b]);
        expect(r.saves, 1);
        expect(c.state.saved!.slug, 'new-name');
        await c.close();
        await w.close();
      },
    );

    test(
      'server rejection of a taken address is surfaced and edits kept',
      () async {
        final (w, r, c) = await make();
        r.saveError = 'That website name is taken.';
        c.update(c.state.draft!.copyWith(slug: 'taken'));
        await c.saveAddress();
        expect(c.state.addressError, 'That website name is taken.');
        expect(c.state.draft!.slug, 'taken');
        expect(c.state.busy, isFalse);
        await c.close();
        await w.close();
      },
    );

    test('double tap on save sends one write', () async {
      final (w, r, c) = await make();
      r.delayedSave = Completer<void>();
      c.update(c.state.draft!.copyWith(title: 'New title'));
      final a = c.save(), b = c.save();
      await Future<void>.delayed(Duration.zero);
      r.delayedSave!.complete();
      await Future.wait([a, b]);
      expect(r.saves, 1);
      await c.close();
      await w.close();
    });

    test('edits are ignored while busy or loading', () async {
      final (w, r, c) = await make();
      r.delayedSave = Completer<void>();
      c.update(c.state.draft!.copyWith(title: 'A title'));
      final save = c.save();
      await Future<void>.delayed(Duration.zero);
      c.update(c.state.draft!.copyWith(title: 'Edited while busy'));
      expect(c.state.draft!.title, 'A title');
      r.delayedSave!.complete();
      await save;
      await c.close();
      await w.close();
    });

    test('photo size boundaries: empty, exactly 1 MB, 1 MB + 1', () async {
      final (w, r, c) = await make();
      r.selectedPhoto = LogoSelection(Uint8List(0), 'image/jpeg');
      await c.photo();
      expect(c.state.error, 'Choose an image up to 1 MB.');
      r.selectedPhoto = LogoSelection(Uint8List(1024 * 1024 + 1), 'image/jpeg');
      await c.photo();
      expect(c.state.error, 'Choose an image up to 1 MB.');
      expect(c.state.draft!.images, isEmpty);
      r.selectedPhoto = LogoSelection(Uint8List(1024 * 1024), 'image/jpeg');
      await c.photo();
      expect(c.state.draft!.images, hasLength(1));
      expect(c.state.draft!.images.single.pending, isTrue);
      await c.close();
      await w.close();
    });

    test('photo picker failure and cancel leave the draft untouched', () async {
      final (w, r, c) = await make();
      r.pickError = 'Photos access denied.';
      await c.photo();
      expect(c.state.error, 'Photos access denied.');
      expect(c.state.busy, isFalse);
      r.pickError = null;
      r.selectedPhoto = null;
      await c.photo();
      expect(c.state.draft!.images, isEmpty);
      expect(c.state.busy, isFalse);
      await c.close();
      await w.close();
    });

    test('non-AppException failures use a generic message', () async {
      final (w, r, c) = await make();
      r.delayedSave = null;
      final bad = _Throwing();
      final c2 = WebsiteSettingsCubit(w, bad);
      await c2.load();
      expect(c2.state.error, 'Could not complete this action. Please retry.');
      expect(c2.state.loading, isFalse);
      await c2.close();
      await c.close();
      await w.close();
      expect(r.saves, 0);
    });
  });

  group('settings screen', () {
    final listFinder = find.byKey(
      const PageStorageKey('website-editor-content'),
    );

    Future<(TestWebsiteRepository, WorkspaceCubit)> open(
      WidgetTester tester, {
      Size size = const Size(1440, 1000),
      double scale = 1,
      TestWebsiteRepository? repo,
    }) async {
      await getIt.reset();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final workspace = WorkspaceCubit(BookingSource());
      await tester.runAsync(workspace.load);
      final r = repo ?? TestWebsiteRepository();
      getIt.registerFactoryParam<WebsiteSettingsCubit, WorkspaceSession, void>(
        (s, _) => WebsiteSettingsCubit(s, r),
      );
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpWidget(const SizedBox());
        await getIt.reset();
        await workspace.close();
      });
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              theme: AppTheme.build(Brightness.light),
              builder: (context, app) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: app!,
              ),
              home: const WebsiteSettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (r, workspace);
    }

    Future<void> edit(WidgetTester tester, String label, String text) async {
      final f = find.widgetWithText(TextFormField, label);
      final scrollable = find
          .descendant(of: listFinder, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(f, 300, scrollable: scrollable);
      await tester.enterText(f, text);
      await tester.pump();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
    }

    String fieldText(WidgetTester tester, String label) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.widgetWithText(TextFormField, label),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;

    testWidgets('title: empty, whitespace and one character are refused', (
      tester,
    ) async {
      final (r, _) = await open(tester);
      for (final v in ['', '   ', 'A']) {
        await edit(tester, 'Website title', v);
        await save(tester);
        expect(find.text('Enter a title.'), findsOneWidget, reason: '"$v"');
        expect(r.saves, 0);
      }
      await edit(tester, 'Website title', '😀😀');
      await save(tester);
      expect(r.saves, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('title and description are clipped to their maxLength', (
      tester,
    ) async {
      await open(tester);
      await edit(tester, 'Website title', 'T' * 200);
      expect(fieldText(tester, 'Website title').length, 120);
      await edit(tester, 'Description', 'd' * 1500);
      expect(fieldText(tester, 'Description').length, 1200);
      await edit(tester, 'Website title', '❤️' * 130);
      expect(
        fieldText(tester, 'Website title').characters.length,
        lessThanOrEqualTo(120),
      );
    });

    testWidgets('public phone: digit count 7-15 and allowed characters', (
      tester,
    ) async {
      final (r, _) = await open(tester);
      final invalid = ['', '123456', '1' * 16, 'abcdefg', '-------'];
      for (final v in invalid) {
        await edit(tester, 'Public contact phone', v);
        await save(tester);
        expect(
          find.text('Enter a valid phone number.'),
          findsOneWidget,
          reason: '"$v"',
        );
        expect(r.saves, 0, reason: '"$v"');
      }
      var saves = 0;
      for (final v in ['+91 98765 43210', '1' * 15]) {
        await edit(tester, 'Public contact phone', v);
        await save(tester);
        expect(
          find.text('Enter a valid phone number.'),
          findsNothing,
          reason: '"$v"',
        );
        expect(r.saves, ++saves, reason: '"$v"');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'social links accept full https links and bare hostnames only',
      (tester) async {
        final (r, _) = await open(tester);
        const message =
            'Enter a full link, e.g. https://instagram.com/yourvenue';
        for (final v in [
          'http://x.com/a',
          'javascript:alert(1)',
          'https://nodot',
          '😀',
        ]) {
          await edit(tester, 'Instagram', v);
          await save(tester);
          expect(find.text(message), findsOneWidget, reason: '"$v"');
          expect(r.saves, 0, reason: '"$v"');
        }
        var saves = 0;
        for (final v in ['instagram.com/venue', '    ']) {
          await edit(tester, 'Instagram', v);
          // Keep the form dirty even when the value equals the previous one.
          await edit(tester, 'Website title', 'Eden ${saves + 1}');
          await save(tester);
          expect(find.text(message), findsNothing, reason: '"$v"');
          expect(r.saves, ++saves, reason: '"$v"');
        }
      },
    );

    group(
      'BUG-14',
      () {
        testWidgets('social link with an empty hostname label is refused', (
          tester,
        ) async {
          final (r, _) = await open(tester);
          for (final v in ['https://..', 'https://.com', 'https://a b.com']) {
            await edit(tester, 'Instagram', v);
            await save(tester);
            expect(
              find.text(
                'Enter a full link, e.g. https://instagram.com/yourvenue',
              ),
              findsOneWidget,
              reason: v,
            );
            expect(r.saves, 0);
          }
        });
      },
      skip:
          'BUG-14: validator only checks host.contains(".") so "https://.." and "https://.com" are saved',
    );

    testWidgets('minimum notice minutes: boundaries and non-numbers', (
      tester,
    ) async {
      final (r, _) = await open(tester);
      var n = 0;
      Future<void> dirty() => edit(tester, 'Website title', 'Eden ${++n}');
      for (final v in ['', 'abc', '-1', '10081', '1.5']) {
        await dirty();
        await edit(tester, 'Minimum notice (minutes)', v);
        await save(tester);
        expect(
          find.text('Enter 0–10080 minutes.'),
          findsOneWidget,
          reason: '"$v"',
        );
        expect(r.saves, 0, reason: '"$v"');
      }
      var saves = 0;
      for (final v in ['0', '10080']) {
        await dirty();
        await edit(tester, 'Minimum notice (minutes)', v);
        await save(tester);
        expect(
          find.text('Enter 0–10080 minutes.'),
          findsNothing,
          reason: '"$v"',
        );
        expect(r.saves, ++saves, reason: '"$v"');
      }
    });

    testWidgets('advance window days: boundaries and non-numbers', (
      tester,
    ) async {
      final (r, _) = await open(tester);
      var n = 0;
      Future<void> dirty() => edit(tester, 'Website title', 'Eden ${++n}');
      for (final v in ['', '0', '366']) {
        await dirty();
        await edit(tester, 'Advance booking window (days)', v);
        await save(tester);
        expect(find.text('Enter 1–365 days.'), findsOneWidget, reason: '"$v"');
        expect(r.saves, 0, reason: '"$v"');
      }
      var saves = 0;
      for (final v in ['1', '365']) {
        await dirty();
        await edit(tester, 'Advance booking window (days)', v);
        await save(tester);
        expect(r.saves, ++saves, reason: '"$v"');
      }
    });

    group(
      'BUG-13',
      () {
        testWidgets(
          'an invalid number is flagged immediately, not silently dropped',
          (tester) async {
            await open(tester);
            await edit(tester, 'Minimum notice (minutes)', 'abc');
            await tester.pumpAndSettle();
            expect(find.text('Enter 0–10080 minutes.'), findsOneWidget);
          },
        );
      },
      skip:
          'BUG-13: onChanged drops invalid numbers and validation only runs on save, so Save stays disabled with no error shown',
    );

    testWidgets('double tap on Save changes saves once', (tester) async {
      final r = TestWebsiteRepository()..delayedSave = Completer<void>();
      await open(tester, repo: r);
      await edit(tester, 'Website title', 'Double tap');
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.tap(find.text('Save changes'), warnIfMissed: false);
      await tester.pump();
      expect(r.saves, 1);
      r.delayedSave!.complete();
      await tester.pumpAndSettle();
      expect(r.saves, 1);
    });

    testWidgets('save failure keeps the typed values and shows the error', (
      tester,
    ) async {
      final r = TestWebsiteRepository()
        ..saveError = 'Website could not be saved.';
      await open(tester, repo: r);
      await edit(tester, 'Website title', 'Kept title');
      await save(tester);
      expect(find.textContaining('Website could not be saved.'), findsWidgets);
      expect(fieldText(tester, 'Website title'), 'Kept title');
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 2.0]) {
      group(
        'long values scale $scale',
        () {
          testWidgets(
            'long values render at 320x568 without overflow, scale $scale',
            (tester) async {
              final r = TestWebsiteRepository();
              r.value = r.value.copyWith(
                title: 'Very long venue name ${'X' * 90} 😀',
                heroHeading: 'H' * 120,
                description: 'Long description ${'word ' * 230}',
                phone: '+91 (98765) 43210-123',
                instructions: 'I' * 2000,
                cancellationPolicy: 'C' * 2000,
                socialLinks: {
                  for (final k in websiteSocialNetworks.keys)
                    k: 'https://example.com/${'p' * 270}',
                },
              );
              await open(
                tester,
                size: const Size(320, 568),
                scale: scale,
                repo: r,
              );
              expect(find.text('Design website'), findsOneWidget);
              final scrollable = find
                  .descendant(of: listFinder, matching: find.byType(Scrollable))
                  .first;
              for (final section in [
                'Brand & homepage',
                'Services & spaces',
                'Social media',
                'Booking policies',
              ]) {
                final heading = find.descendant(
                  of: listFinder,
                  matching: find.text(section),
                );
                await tester.scrollUntilVisible(
                  heading,
                  300,
                  scrollable: scrollable,
                );
                await tester.tap(heading);
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull, reason: section);
              }
              await tester.scrollUntilVisible(
                find.widgetWithText(TextFormField, 'Cancellation policy'),
                300,
                scrollable: scrollable,
              );
              expect(tester.takeException(), isNull);
            },
          );
        },
        skip: scale == 2.0
            ? 'BUG-20: website settings overflow at 320x568 with 2.0 text scale (36px with long values, 64px in the load-error state)'
            : false,
      );
    }

    group(
      'load error state at scale 2',
      () {
        testWidgets('loading failure shows an error instead of the form', (
          tester,
        ) async {
          final r = _Throwing();
          await open(
            tester,
            repo: r as dynamic,
            size: const Size(320, 568),
            scale: 2,
          );
          expect(find.text('Save changes'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      },
      skip:
          'BUG-20: website settings overflow at 320x568 with 2.0 text scale (36px with long values, 64px in the load-error state)',
    );
  });
}

class _Throwing extends TestWebsiteRepository {
  @override
  Future<WebsiteSettings> settings() async => throw StateError('boom');
}

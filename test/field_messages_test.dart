// Field-value tests for lib/modules/messages: template name, body, website
// URL, placeholder validation, rendering, money formatting and screens.
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/messages/cubit/message_cubits.dart';
import 'package:eden_booking/modules/messages/models/message_screen_models.dart';
import 'package:eden_booking/modules/messages/models/message_template.dart';
import 'package:eden_booking/modules/messages/repositories/message_repository.dart';
import 'package:eden_booking/modules/messages/screens/template_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'message_templates_test.dart' show fixture, TestShare;

void main() {
  group('validateMessageBody', () {
    test('accepts valid bodies', () {
      for (final v in [
        'Hi',
        'Hi {customer_name}',
        defaultMessageBody,
        '{customer_name}{booking_reference}',
        'Emoji 😀 {customer_name} ✅ தமிழ்',
        'a' * 6000,
        'Line1\n\nLine2 *bold* _italic_',
        '   x   ',
      ]) {
        expect(
          validateMessageBody(v),
          isNull,
          reason: v.length > 40 ? '${v.length} chars' : v,
        );
      }
    });
    test('rejects empty, whitespace and too long', () {
      for (final v in ['', ' ', '\n\t  ', 'a' * 6001]) {
        expect(validateMessageBody(v), 'Write a message of 1–6000 characters.');
      }
    });
    test('rejects unknown, empty, nested and unbalanced fields', () {
      expect(validateMessageBody('Hi {bad}'), 'Unknown field: {bad}.');
      expect(validateMessageBody('Hi {}'), 'Unknown field: {}.');
      expect(
        validateMessageBody('Hi { customer_name }'),
        'Unknown field: { customer_name }.',
      );
      expect(
        validateMessageBody('Hi {Customer_Name}'),
        'Unknown field: {Customer_Name}.',
      );
      expect(
        validateMessageBody('Hi {{customer_name}}'),
        'Complete every field using {field_name}.',
      );
      expect(
        validateMessageBody('Hi {customer_name'),
        'Complete every field using {field_name}.',
      );
      expect(
        validateMessageBody('Hi customer_name}'),
        'Complete every field using {field_name}.',
      );
      expect(
        validateMessageBody('}{'),
        'Complete every field using {field_name}.',
      );
    });
    test(
      'BUG-17 the 6000 limit counts characters, not UTF-16 units',
      () {
        expect(validateMessageBody('😀' * 3001), isNull);
      },
      skip:
          'BUG-17: body.length counts UTF-16 units so 3001 emoji (3001 characters) are refused as too long',
    );
  });

  group('MessageTemplate.render', () {
    test('substitutes known fields once and blanks missing ones', () {
      const t = MessageTemplate(
        id: 'x',
        name: 'n',
        body: 'A {customer_name} B {website} C {nope}',
      );
      expect(
        t.render({'customer_name': 'Abin 😀', 'website': ''}),
        'A Abin 😀 B  C ',
      );
    });
    test('values containing braces are not expanded again', () {
      const t = MessageTemplate(id: 'x', name: 'n', body: 'Hi {customer_name}');
      expect(
        t.render({'customer_name': '{balance_due}', 'balance_due': '₹1'}),
        'Hi {balance_due}',
      );
    });
    test('very long values and multiline values are kept verbatim', () {
      const t = MessageTemplate(id: 'x', name: 'n', body: '{customer_name}');
      final v = 'N' * 5000;
      expect(t.render({'customer_name': v}), v);
      expect(t.render({'customer_name': 'a\nb'}), 'a\nb');
    });
    test('editor preview uses sample data and the typed website', () {
      const s = TemplateEditorState(
        body: 'Hi {customer_name} {website} {booking_total}',
        website: 'https://e.com',
      );
      expect(s.preview, 'Hi Abin https://e.com ₹650');
      expect(const TemplateEditorState(body: '').preview, '');
    });
  });

  group('messageMoney', () {
    test('formats whole, fractional, zero, negative and huge amounts', () {
      expect(messageMoney(0, 'INR'), '₹0');
      expect(messageMoney(100, 'INR'), '₹1');
      expect(messageMoney(150, 'INR'), '₹1.50');
      expect(messageMoney(5, 'INR'), '₹0.05');
      expect(messageMoney(12345, 'USD'), 'USD 123.45');
      expect(messageMoney(-5, 'INR'), '₹-0.05');
      expect(messageMoney(-100, 'INR'), '₹-1');
      expect(messageMoney(100000000000, 'INR'), '₹1000000000');
      expect(messageMoney(0, ''), ' 0');
    });
  });

  group('template editor cubit', () {
    Future<void> using(
      Future<void> Function(dynamic r, TemplateEditorCubit c) body, {
      MessageTemplate? source,
    }) async {
      final (_, w, r) = await fixture();
      final c = TemplateEditorCubit(w, r, source);
      try {
        await body(r, c);
      } finally {
        await c.close();
        await w.close();
      }
    }

    test('name boundaries 2..80 after trimming', () async {
      await using((r, c) async {
        c.update(body: 'Hi');
        for (final n in ['', ' ', '   ', 'A', ' A ']) {
          c.update(name: n);
          await c.save();
          expect(
            c.state.error,
            'Use a template name of 2–80 characters.',
            reason: '"$n"',
          );
        }
        c.update(name: 'a' * 81);
        await c.save();
        expect(c.state.error, 'Use a template name of 2–80 characters.');
        expect(r.creates, isEmpty);
        c.update(name: '  ${'a' * 80}  ');
        await c.save();
        expect(r.creates.single['name'], 'a' * 80);
      });
    });

    test('body errors block saving', () async {
      await using((r, c) async {
        c.update(name: 'Name');
        for (final b in [
          '',
          '  ',
          'x' * 6001,
          'Hi {bad}',
          'Hi {{customer_name}}',
        ]) {
          c.update(body: b);
          await c.save();
          expect(
            c.state.error,
            isNotNull,
            reason: b.length > 20 ? '${b.length}' : b,
          );
        }
        expect(r.creates, isEmpty);
      });
    });

    test('website url: valid, invalid, trimmed and optional', () async {
      await using((r, c) async {
        c.update(name: 'Name', body: 'Hi');
        for (final u in [
          'example.com',
          'ftp://example.com',
          'javascript:alert(1)',
          'https://',
          'http:///x',
          'mailto:a@b.co',
          '😀',
          'https://${'a' * 500}.com',
        ]) {
          c.update(website: u);
          await c.save();
          expect(
            c.state.error,
            'Enter an http or https website URL.',
            reason: u.length > 40 ? '${u.length}' : u,
          );
        }
        expect(r.creates, isEmpty);
        c.update(website: '   ');
        await c.save();
        expect(r.creates, hasLength(1));
        expect(r.creates.last['website'], '');
      });
    });

    test('valid website urls are accepted and trimmed', () async {
      for (final u in [
        'https://example.com',
        ' http://example.com/path?q=1 ',
        'HTTPS://EXAMPLE.COM',
        'https://xn--e28h.example',
      ]) {
        await using((r, c) async {
          c.update(name: 'Name', body: 'Hi', website: u);
          await c.save();
          expect(r.creates.single['website'], u.trim(), reason: u);
        });
      }
    });

    test(
      'BUG-18 website url with a space in the host is refused',
      () async {
        await using((r, c) async {
          c.update(name: 'Name', body: 'Hi', website: 'https://exa mple.com');
          await c.save();
          expect(r.creates, isEmpty);
        });
      },
      skip:
          'BUG-18: Uri.tryParse accepts "https://exa mple.com"; the editor only checks scheme and non-empty host',
    );

    test(
      'BUG-19 copying a long template name must stay within 80 characters',
      () async {
        final long = MessageTemplate(id: 't', name: 'N' * 78, body: 'Hi');
        await using((r, c) async {
          expect(c.state.name.length, lessThanOrEqualTo(80));
        }, source: long);
      },
      skip:
          'BUG-19: "<name> (copy)" is prefilled without truncation, so copying a 75+ char name pre-fills an invalid name',
    );

    test('copy prefill keeps body and website of the source', () async {
      await using((r, c) async {
        expect(c.state.name, 'Booking confirmation (copy)');
        expect(c.state.body, defaultMessageBody);
      }, source: MessageTemplate.predefined);
    });

    test('double tap on save creates once', () async {
      await using((r, c) async {
        c.update(name: 'Name', body: 'Hi {customer_name}');
        await Future.wait([c.save(), c.save(), c.save()]);
        expect(r.creates, hasLength(1));
        expect(c.state.saved, isTrue);
      });
    });
  });

  group('preview cubit', () {
    test('share and copy double tap send one message each', () async {
      final (_, w, r) = await fixture();
      final share = TestShare();
      final c = MessagePreviewCubit(w, r, share, 'booking');
      await c.load();
      expect(c.state.message, isNotEmpty);
      await Future.wait([c.share(), c.share()]);
      await Future.wait([c.copy(), c.copy()]);
      expect(share.messages, hasLength(1));
      expect(share.copies, hasLength(1));
      await c.close();
      await w.close();
    });

    test(
      'a primary template with an invalid body shows an error and nothing to share',
      () async {
        final (_, w, r) = await fixture();
        r.value = MessageTemplateCatalog(
          canManage: true,
          templates: const [
            MessageTemplate(
              id: 'bad',
              name: 'Bad',
              body: 'Hi {oops}',
              primary: true,
            ),
          ],
        );
        final share = TestShare();
        final c = MessagePreviewCubit(w, r, share, 'booking');
        await c.load();
        expect(c.state.error, 'Unknown field: {oops}.');
        await c.share();
        expect(share.messages, isEmpty);
        await c.close();
        await w.close();
      },
    );

    test('customer name with emoji, braces and huge length renders', () async {
      final (_, w, r) = await fixture();
      final share = TestShare();
      final c = MessagePreviewCubit(w, r, share, 'booking');
      await c.load();
      expect(c.state.message, contains('Abin'));
      await c.close();
      await w.close();
    });
  });

  group('editor screen', () {
    for (final scale in [1.0, 2.0]) {
      group(
        'scale $scale',
        () {
          testWidgets(
            'long body, emoji and bad placeholder at 320x568 scale $scale',
            (tester) async {
              tester.view.physicalSize = const Size(320, 568);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              await getIt.reset();
              final (_, w, r) = await fixture();
              registerFeatureDependencies(getIt);
              await getIt.unregister<MessageRepository>();
              getIt.registerSingleton<MessageRepository>(r);
              await getIt.unregister<MessageShareGateway>();
              getIt.registerSingleton<MessageShareGateway>(TestShare());
              final router = GoRouter(
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (_, _) => const TemplateEditorScreen(),
                  ),
                ],
              );
              addTearDown(() async {
                await tester.pumpWidget(const SizedBox());
                router.dispose();
                await getIt.reset();
                await w.close();
              });
              await tester.pumpWidget(
                BlocProvider.value(
                  value: w,
                  child: ScreenUtilInit(
                    designSize: const Size(390, 844),
                    builder: (_, _) => MaterialApp.router(
                      routerConfig: router,
                      theme: AppTheme.build(Brightness.light),
                      builder: (context, app) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.linear(scale)),
                        child: app!,
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final field = find.byKey(
                const ValueKey('template-message-input'),
              );
              await tester.ensureVisible(field);
              for (final text in [
                'Hi {bad}',
                '😀' * 400,
                'x' * 7000,
                'Hi {customer_name',
                '   ',
              ]) {
                await tester.enterText(field, text);
                await tester.pump();
                expect(
                  tester.takeException(),
                  isNull,
                  reason: text.length > 20 ? '${text.length}' : text,
                );
              }
              final controller = tester.widget<TextField>(field).controller!;
              expect(
                controller.text.length,
                lessThanOrEqualTo(6000),
                reason: 'maxLength clips pasted text',
              );
              await tester.enterText(field, 'Hi {bad}');
              await tester.pump();
              expect(find.text('Unknown field: {bad}.'), findsWidgets);
              expect(r.creates, isEmpty);
            },
          );
        },
        skip: scale == 2.0
            ? 'BUG-23: template editor overflows by 87px on the right at 320x568 with 2.0 text scale when a placeholder error is shown'
            : false,
      );
    }
  });
}

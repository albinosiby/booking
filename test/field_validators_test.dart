import 'package:eden_booking/modules/auth/models/auth_continuation.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/helpers/safe_return_path.dart';
import 'package:eden_booking/utils/helpers/validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validation.required', () {
    test('rejects null, empty and whitespace-only input', () {
      for (final v in [null, '', ' ', '   ', '\t', '\n', '   ']) {
        expect(Validation.required(v), isNotNull, reason: 'value=$v');
      }
    });
    test('accepts text, unicode and emoji', () {
      for (final v in ['a', ' a ', 'ഏബിൻ', '李', '😀', 'Court 1']) {
        expect(Validation.required(v), isNull, reason: 'value=$v');
      }
    });
  });

  group('Validation.name', () {
    test('empty, whitespace and one character fail', () {
      for (final v in [null, '', '  ', 'A', '  A  ']) {
        expect(Validation.name(v), isNotNull, reason: 'value=$v');
      }
    });
    test('two characters, padded and unicode names pass', () {
      for (final v in ['Al', '  Al  ', 'José Müller', 'ഏബിൻ', "O'Brien-Smith"]) {
        expect(Validation.name(v), isNull, reason: 'value=$v');
      }
    });
    test('120 characters pass and 121 fail, padding is ignored', () {
      expect(Validation.name('a' * 120), isNull);
      expect(Validation.name('  ${'a' * 120}  '), isNull);
      expect(Validation.name('a' * 121), isNotNull);
    });
    test('pasted text with inner newline is not rejected as too short', () {
      expect(Validation.name('Eden\nArena'), isNull);
    });
    test(
      'a name made of 61 emoji is within 120 characters',
      () {
        // 61 user-visible characters. Dart String.length counts UTF-16 units.
        expect(Validation.name('😀' * 61), isNull);
      },
      skip:
          'BUG-1: Validation.name counts UTF-16 code units, so 61 emoji are rejected as "120 characters or fewer"',
    );
    test(
      'a single emoji is one character and is rejected as too short',
      () {
        expect(Validation.name('😀'), isNotNull);
      },
      skip:
          'BUG-1: one emoji is two UTF-16 code units and passes the two character minimum',
    );
    test(
      'a single-character CJK name is accepted',
      () {
        expect(Validation.name('李'), isNull);
      },
      skip:
          'BUG-2: single-character personal names (for example 李) are rejected by the two character minimum',
    );
  });

  group('Validation.email', () {
    test('valid addresses pass', () {
      for (final v in [
        'a@b.co',
        'first.last+tag@example.com',
        '  owner@example.com  ',
        'owner@example.com\n',
        'UPPER@EXAMPLE.COM',
        'o\'brien@example.ie',
        'user@sub.domain.example.com',
        'user@xn--bcher-kva.example',
      ]) {
        expect(Validation.email(v), isNull, reason: 'value=$v');
      }
    });
    test('empty, whitespace and malformed formats fail', () {
      for (final v in [
        null,
        '',
        '   ',
        'plain',
        'a@b',
        '@b.co',
        'a@',
        'a@@b.co',
        'a@b@c.co',
        'a b@c.co',
        'a@b .co',
        'a@.co',
        'a@b.',
        'a@b.co, c@d.co',
      ]) {
        expect(Validation.email(v), isNotNull, reason: 'value=$v');
      }
    });
    test('internal whitespace from a paste is rejected', () {
      expect(Validation.email('own er@example.com'), isNotNull);
      expect(Validation.email('owner@exam ple.com'), isNotNull);
      expect(Validation.email('owner@example.com owner2@example.com'),
          isNotNull);
    });
    test(
      'consecutive dots in the domain are invalid',
      () {
        expect(Validation.email('a@b..co'), isNotNull);
        expect(Validation.email('a@example..com'), isNotNull);
      },
      skip: 'BUG-3: Validation.email accepts consecutive dots in the domain',
    );
    test(
      'domain label may not start or end with a hyphen or dot',
      () {
        expect(Validation.email('a@-b.com'), isNotNull);
        expect(Validation.email('a@b-.com'), isNotNull);
        expect(Validation.email('a@.b.com'), isNotNull);
      },
      skip:
          'BUG-3: Validation.email only checks "something@something.something"',
    );
    test(
      'addresses longer than 254 characters are rejected',
      () {
        expect(Validation.email('${'a' * 250}@example.com'), isNotNull);
      },
      skip:
          'BUG-4: Validation.email has no maximum length; backend or Supabase rejects it later with a generic error',
    );
    test(
      'zero-width and other invisible pasted characters are rejected',
      () {
        expect(Validation.email('owner@example.com​'), isNotNull);
        expect(Validation.email('​owner@example.com'), isNotNull);
      },
      skip:
          'BUG-5: zero-width space survives trim() and \\s, so a pasted address with it validates but can never sign in',
    );
  });

  group('Validation.password', () {
    test('null, empty and seven characters fail', () {
      for (final v in [null, '', 'a', '1234567', '       ']) {
        // seven spaces: still too short
        expect(Validation.password(v), isNotNull, reason: 'value=$v');
      }
    });
    test('eight characters, unicode and long passphrases pass', () {
      for (final v in [
        '12345678',
        'pässwörd1',
        'correct horse battery staple',
        'a' * 64,
      ]) {
        expect(Validation.password(v), isNull, reason: 'value=$v');
      }
    });
    test('leading and trailing spaces are significant and count', () {
      expect(Validation.password(' 123456 '), isNull);
    });
    test(
      'eight spaces are not an acceptable password',
      () {
        expect(Validation.password('        '), isNotNull);
      },
      skip: 'BUG-6: Validation.password accepts a password of only whitespace',
    );
    test(
      'passwords above the provider limit are rejected before the request',
      () {
        expect(Validation.password('a' * 200), isNotNull);
      },
      skip:
          'BUG-7: no maximum password length; GoTrue/bcrypt rejects >72 bytes with a generic error',
    );
  });

  group('Validation.priceMinor', () {
    test('valid amounts convert to minor units', () {
      expect(Validation.priceMinor('0'), 0);
      expect(Validation.priceMinor('0.5'), 50);
      expect(Validation.priceMinor('0.05'), 5);
      expect(Validation.priceMinor('10'), 1000);
      expect(Validation.priceMinor('10.25'), 1025);
      expect(Validation.priceMinor('  499.00  '), 49900);
      expect(Validation.priceMinor('1000000'), 100000000);
      expect(Validation.priceMinor('1000000.00'), 100000000);
    });
    test('invalid formats return null', () {
      for (final v in [
        '',
        ' ',
        'abc',
        '-1',
        '+1',
        '1.234',
        '1,000',
        '1 000',
        '.5',
        '5.',
        '1e3',
        '1..2',
        '١٢٣',
        '12.5.0',
        '😀',
      ]) {
        expect(Validation.priceMinor(v), isNull, reason: 'value="$v"');
      }
    });
    test('above the cap returns null', () {
      expect(Validation.priceMinor('1000000.01'), isNull);
      expect(Validation.priceMinor('1000001'), isNull);
      expect(Validation.priceMinor('99999999999999999999'), isNull);
    });
    test(
      'paste with a comma decimal separator is understood',
      () {
        expect(Validation.priceMinor('10,50'), 1050);
      },
      skip:
          'BUG-8: priceMinor rejects "10,50" and "1,000" (common keyboard/locale paste) with only a generic message',
    );
  });

  group('safeReturnPath', () {
    test('keeps in-app paths and queries', () {
      expect(safeReturnPath('/home'), '/home');
      expect(safeReturnPath('/bookings?day=2026-10-27'),
          '/bookings?day=2026-10-27');
      expect(safeReturnPath('/businesses/b/setup'), '/businesses/b/setup');
    });
    test('rejects null, empty and relative values', () {
      for (final v in [null, '', 'home', ' /home', 'bookings/1']) {
        expect(safeReturnPath(v), isNull, reason: 'value=$v');
      }
    });
    test('rejects absolute urls, schemes, protocol-relative and backslashes',
        () {
      for (final v in [
        'https://evil.example',
        'http://evil.example/home',
        'javascript:alert(1)',
        'com.bookingos.app://invite',
        '//evil.example',
        '//evil.example/home',
        r'/\evil.example',
        r'/home\..\x',
        '/\\evil.example',
      ]) {
        expect(safeReturnPath(v), isNull, reason: 'value=$v');
      }
    });
    test('never returns an auth route, even with a query', () {
      for (final v in [
        '/register',
        '/sign-in',
        '/sign-in?from=/home',
        '/loading',
        '/organization',
        '/onboarding',
        '/invite?token=x',
        '/verify',
        '/auth-callback',
        '/auth-callback/',
        '/update-password',
      ]) {
        expect(safeReturnPath(v), isNull, reason: 'value=$v');
      }
    });
    test('control characters are not echoed raw', () {
      for (final v in ['/home\n/x', '/\t/evil.example', '/home\r\nLocation: x']) {
        final result = safeReturnPath(v);
        if (result != null) {
          expect(result.contains(RegExp(r'[\r\n\t]')), isFalse,
              reason: 'value=$v result=$result');
          expect(result.startsWith('//'), isFalse);
        }
      }
    });
    test('unicode and emoji paths are percent-encoded or kept as in-app', () {
      final result = safeReturnPath('/bookings/😀');
      expect(result, isNotNull);
      expect(result!.startsWith('/'), isTrue);
    });
    test(
      'auth routes are blocked case-insensitively and with trailing slash',
      () {
        expect(safeReturnPath('/Sign-In'), isNull);
        expect(safeReturnPath('/sign-in/'), isNull);
        expect(safeReturnPath('/register/'), isNull);
      },
      skip:
          'BUG-9: blocklist is exact-match; /sign-in/ and /Sign-In slip through as a return path (router may then bounce back to itself)',
    );
  });

  group('AuthContinuation', () {
    final token = 'a' * 64;
    final now = DateTime.utc(2026, 10, 27, 12);
    test('valid within 30 minutes', () {
      expect(AuthContinuation(createdAt: now, invitationToken: token)
          .isValidAt(now.add(const Duration(minutes: 29))), isTrue);
    });
    test('expires after 30 minutes and rejects a future clock', () {
      expect(AuthContinuation(createdAt: now)
          .isValidAt(now.add(const Duration(minutes: 30))), isFalse);
      expect(AuthContinuation(createdAt: now)
          .isValidAt(now.subtract(const Duration(seconds: 1))), isFalse);
    });
    test('invalid, uppercase, short and padded tokens are rejected', () {
      for (final t in ['abc', 'A' * 64, '${'a' * 63}g', ' ${'a' * 63}', '']) {
        expect(AuthContinuation(createdAt: now, invitationToken: t)
            .isValidAt(now), isFalse, reason: 'token=$t');
      }
    });
    test('unsafe return path is rejected', () {
      expect(AuthContinuation(createdAt: now, returnTo: 'https://x.test')
          .isValidAt(now), isFalse);
      expect(AuthContinuation(createdAt: now, returnTo: '/sign-in')
          .isValidAt(now), isFalse);
      expect(AuthContinuation(createdAt: now, returnTo: '/home')
          .isValidAt(now), isTrue);
    });
    test('json round trip and corrupt json', () {
      final c = AuthContinuation(
        createdAt: now,
        invitationToken: token,
        returnTo: '/home',
      );
      final back = AuthContinuation.fromJson(c.toJson());
      expect(back.invitationToken, token);
      expect(back.returnTo, '/home');
      expect(back.createdAt, now);
      expect(() => AuthContinuation.fromJson({'created_at': 'nope'}),
          throwsFormatException);
    });
  });

  group('AppException', () {
    test('toString is the user message and access failures are typed', () {
      const e = AppException('Nope', code: 'FORBIDDEN');
      expect(e.toString(), 'Nope');
      expect(accessFailure(e), isTrue);
      expect(accessFailure(const AppException('x', code: 'UNAUTHENTICATED')),
          isTrue);
      expect(accessFailure(const AppException('x')), isFalse);
      expect(accessFailure(StateError('x')), isFalse);
    });
  });
}

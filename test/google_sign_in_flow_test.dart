import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:eden_booking/config/routes/route_guard.dart';
import 'package:eden_booking/modules/auth/cubit/auth_cubit.dart';
import 'package:eden_booking/modules/auth/models/app_user.dart';
import 'package:eden_booking/modules/auth/models/auth_continuation.dart';
import 'package:eden_booking/modules/auth/repositories/auth_continuation_repository.dart';
import 'package:eden_booking/modules/auth/repositories/auth_repository_interface.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_state.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

const googleUser = AppUser(
  id: 'google-user',
  email: 'staff@example.com',
  name: 'Staff',
  verified: true,
);
final invitationToken = 'a' * 64;
Future<void> drainAuthEvents() => Future<void>.delayed(Duration.zero);

class GoogleAuthFake extends Fake
    implements AuthRepository, GoogleSignInRepository {
  final events = StreamController<AppUser?>.broadcast();
  AppUser? user;
  Completer<void>? launching;
  Object? launchError;
  int launches = 0, passwordSignIns = 0;
  @override
  Stream<AppUser?> get changes => events.stream;
  @override
  AppUser? get currentUser => user;
  @override
  Future<void> signInWithGoogle() async {
    launches++;
    if (launchError != null) throw launchError!;
    await launching?.future;
  }

  @override
  Future<void> signIn(String email, String password) async {
    passwordSignIns++;
  }

  @override
  Future<void> signOut() async {
    user = null;
  }
}

class MemoryContinuationRepository implements AuthContinuationRepository {
  AuthContinuation? value;
  Completer<void>? reading;
  bool failWrite = false;
  @override
  Future<AuthContinuation?> read() async {
    await reading?.future;
    return value;
  }

  @override
  Future<void> write(AuthContinuation value) async {
    if (failWrite) throw StateError('Storage unavailable');
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'invitation is saved before launch and restored before cold-start sign-in',
    () async {
      final store = MemoryContinuationRepository();
      final source = GoogleAuthFake();
      final first = AuthCubit(source, continuations: store);
      await first.signInWithGoogle(invitationToken: invitationToken);
      expect(source.launches, 1);
      expect(store.value!.invitationToken, invitationToken);
      expect(first.state.status, AuthStatus.signedOut);
      await first.close();
      await source.events.close();

      store.reading = Completer<void>();
      final returnedSource = GoogleAuthFake()..user = googleUser;
      final returned = AuthCubit(returnedSource, continuations: store);
      returnedSource.events.add(googleUser);
      await drainAuthEvents();
      expect(returned.state.status, AuthStatus.loading);
      store.reading!.complete();
      await drainAuthEvents();
      expect(returned.state.status, AuthStatus.signedIn);
      expect(
        routeRedirect(
          returned.state,
          const WorkspaceState(),
          Uri.parse('/auth-callback?code=private-code'),
          requireVerification: true,
          continuation: returned.continuation,
        ),
        '/invite?token=$invitationToken',
      );
      returned.consumeContinuation();
      await drainAuthEvents();
      expect(returned.continuation, isNull);
      expect(store.value, isNull);
      await returned.close();
      await returnedSource.events.close();
    },
  );
  test(
    'failed launch clears saved context and duplicate taps do not launch twice',
    () async {
      final source = GoogleAuthFake()..launching = Completer<void>();
      final store = MemoryContinuationRepository();
      final auth = AuthCubit(source, continuations: store);
      final pending = auth.signInWithGoogle(invitationToken: invitationToken);
      await drainAuthEvents();
      await auth.signInWithGoogle();
      expect(source.launches, 1);
      source.launching!.completeError(
        const AppException('Could not open Google sign-in.'),
      );
      await pending;
      expect(auth.state.busy, isFalse);
      expect(auth.state.error, contains('Could not open Google'));
      expect(store.value, isNull);
      await auth.close();
      await source.events.close();
    },
  );
  test(
    'failed context storage stops launch; unsafe return URLs are dropped',
    () async {
      final source = GoogleAuthFake();
      final store = MemoryContinuationRepository()..failWrite = true;
      final auth = AuthCubit(source, continuations: store);
      await auth.signInWithGoogle(invitationToken: invitationToken);
      expect(source.launches, 0);
      expect(auth.state.error, isNotNull);
      store.failWrite = false;
      await auth.signInWithGoogle(returnTo: 'https://attacker.invalid');
      expect(store.value!.returnTo, isNull);
      await auth.signIn('staff@example.com', 'password');
      expect(store.value, isNull);
      expect(source.passwordSignIns, 1);
      await auth.close();
      await source.events.close();
    },
  );
  test(
    'cancelled callback leaves sign-in usable and retains the invitation',
    () async {
      final source = GoogleAuthFake();
      final store = MemoryContinuationRepository()
        ..value = AuthContinuation(
          createdAt: DateTime.now(),
          invitationToken: invitationToken,
        );
      final auth = AuthCubit(source, continuations: store);
      source.events.addError(
        const AppException(
          'Google sign-in was cancelled. You can try again.',
          code: 'AUTH_CALLBACK',
        ),
      );
      await drainAuthEvents();
      expect(auth.state.status, AuthStatus.signedOut);
      expect(auth.state.error, contains('cancelled'));
      final redirect = routeRedirect(
        auth.state,
        const WorkspaceState(),
        Uri.parse('/auth-callback'),
        requireVerification: true,
        continuation: auth.continuation,
      )!;
      expect(Uri.parse(redirect).path, '/sign-in');
      expect(Uri.parse(redirect).queryParameters['invite'], invitationToken);
      await auth.signOut();
      expect(store.value, isNull);
      await auth.close();
      await source.events.close();
    },
  );
  test(
    'stored context expires, rejects corrupt/unsafe data and is project scoped',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      var now = DateTime.now();
      final store = SecureAuthContinuationRepository(
        'https://project.supabase.co',
        now: () => now,
      );
      final other = SecureAuthContinuationRepository(
        'https://other.supabase.co',
        now: () => now,
      );
      await store.write(
        AuthContinuation(
          createdAt: now,
          invitationToken: invitationToken,
          returnTo: '/profile',
        ),
      );
      expect((await store.read())!.invitationToken, invitationToken);
      expect(await other.read(), isNull);
      now = now.add(AuthContinuation.lifetime);
      expect(await store.read(), isNull);
      await store.write(
        AuthContinuation(createdAt: now, returnTo: '//attacker.invalid'),
      );
      expect(await store.read(), isNull);
      await const FlutterSecureStorage().write(
        key: 'booking.oauth.project.supabase.co',
        value: 'corrupt-json',
      );
      expect(await store.read(), isNull);
    },
  );
}

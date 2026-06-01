// T38 RED — SCENARIO-552, SCENARIO-553 + credential builder tests
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:treino/features/auth/data/apple_sign_in_gateway.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/profile/data/user_repository.dart';

// --- Mocks ---
class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

class MockUserRepository extends Mock implements UserRepository {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class MockGoogleSignInAuthorizationClient extends Mock
    implements GoogleSignInAuthorizationClient {}

class MockAppleSignInGateway extends Mock implements AppleSignInGateway {}

class FakeAuthCredential extends Fake implements AuthCredential {
  // Stubbed for the Apple-sentinel short-circuit check in reauthenticate.
  // A non-sentinel providerId routes the call down the normal path.
  @override
  String get providerId => 'password';
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAuthCredential());
    registerFallbackValue(<AppleIDAuthorizationScopes>[]);
    registerFallbackValue(OAuthProvider('apple.com'));
  });

  late MockFirebaseAuth fbAuth;
  late MockUser user;
  late MockUserRepository mockRepo;
  late MockGoogleSignIn googleSignIn;
  late MockAppleSignInGateway appleGateway;
  late AuthService sut;

  setUp(() {
    fbAuth = MockFirebaseAuth();
    user = MockUser();
    mockRepo = MockUserRepository();
    googleSignIn = MockGoogleSignIn();
    appleGateway = MockAppleSignInGateway();

    when(() => user.uid).thenReturn('uid-test');
    when(() => user.email).thenReturn('test@example.com');

    sut = AuthService(
      firebaseAuth: fbAuth,
      userRepository: mockRepo,
      googleSignIn: googleSignIn,
      appleGateway: appleGateway,
    );
  });

  // SCENARIO-552
  group('AuthService.reauthenticate', () {
    test(
        'SCENARIO-552: reauthenticate with valid credential calls '
        'currentUser.reauthenticateWithCredential', () async {
      final credential = FakeAuthCredential();
      final mockUserCred = MockUserCredential();

      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.reauthenticateWithCredential(any()))
          .thenAnswer((_) async => mockUserCred);

      await expectLater(sut.reauthenticate(credential), completes);

      verify(() => user.reauthenticateWithCredential(credential)).called(1);
    });

    // SCENARIO-553
    test(
        'SCENARIO-553: wrong-password FirebaseAuthException becomes '
        'AuthFailure.reAuthFailed', () async {
      final credential = FakeAuthCredential();

      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.reauthenticateWithCredential(any())).thenThrow(
        FirebaseAuthException(code: 'wrong-password'),
      );

      await expectLater(
        () => sut.reauthenticate(credential),
        throwsA(isA<AuthFailure>()),
      );
    });

    test(
        'invalid-credential FirebaseAuthException becomes AuthFailure.reAuthFailed',
        () async {
      final credential = FakeAuthCredential();

      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.reauthenticateWithCredential(any())).thenThrow(
        FirebaseAuthException(code: 'invalid-credential'),
      );

      await expectLater(
        () => sut.reauthenticate(credential),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('throws AuthFailure.userNotFound when no current user', () async {
      final credential = FakeAuthCredential();
      when(() => fbAuth.currentUser).thenReturn(null);

      await expectLater(
        () => sut.reauthenticate(credential),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('AuthService.getPasswordCredential', () {
    test('returns EmailAuthProvider credential built from current user email',
        () async {
      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.email).thenReturn('user@example.com');

      final credential = await sut.getPasswordCredential(password: 'Pass1234');

      // EmailAuthProvider.credential returns an AuthCredential
      expect(credential, isA<AuthCredential>());
    });

    test('throws AuthFailure.reAuthFailed when no current user', () async {
      when(() => fbAuth.currentUser).thenReturn(null);

      await expectLater(
        () => sut.getPasswordCredential(password: 'pass'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('throws AuthFailure.reAuthFailed when current user email is null',
        () async {
      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.email).thenReturn(null);

      await expectLater(
        () => sut.getPasswordCredential(password: 'pass'),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('AuthService.getGoogleCredential', () {
    late MockGoogleSignInAccount googleAccount;
    late MockGoogleSignInAuthorizationClient authzClient;

    setUp(() {
      googleAccount = MockGoogleSignInAccount();
      authzClient = MockGoogleSignInAuthorizationClient();

      when(() => googleAccount.authentication).thenReturn(
        const GoogleSignInAuthentication(idToken: 'id-token-stub'),
      );
      when(() => googleAccount.authorizationClient).thenReturn(authzClient);
      when(() => authzClient.authorizeScopes(any())).thenAnswer(
        (_) async => const GoogleSignInClientAuthorization(
          accessToken: 'access-token-stub',
        ),
      );
    });

    test(
        'triggers google_sign_in flow and returns GoogleAuthProvider credential',
        () async {
      when(() => googleSignIn.authenticate())
          .thenAnswer((_) async => googleAccount);

      final credential = await sut.getGoogleCredential();

      expect(credential, isA<AuthCredential>());
      verify(() => googleSignIn.authenticate()).called(1);
    });

    test('user cancels → throws AuthFailure.signInCancelled', () async {
      when(() => googleSignIn.authenticate()).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'cancelled',
        ),
      );

      await expectLater(
        () => sut.getGoogleCredential(),
        throwsA(const AuthFailure.signInCancelled()),
      );
    });
  });

  group('AuthService.getAppleCredential', () {
    // The Apple re-auth path was refactored 2026-06-01 to delegate to
    // Firebase's `User.reauthenticateWithProvider(OAuthProvider('apple.com'))`
    // because sign_in_with_apple's native iOS sheet returns a cached
    // identityToken on re-auth whose nonce no longer matches our fresh
    // rawNonce, causing Firebase to reject with `missing-or-invalid-nonce`.
    // getAppleCredential now performs the reauth internally and returns a
    // sentinel credential that reauthenticate() short-circuits on.

    test(
        'reauths via Firebase reauthenticateWithProvider and returns sentinel '
        'credential', () async {
      final mockUserCred = MockUserCredential();
      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.reauthenticateWithProvider(any()))
          .thenAnswer((_) async => mockUserCred);

      final credential = await sut.getAppleCredential();

      expect(credential, isA<AuthCredential>());
      // The sentinel providerId signals reauthenticate() to skip the
      // redundant reauthenticateWithCredential call.
      expect(credential.providerId, '__apple_reauth_done_sentinel__');
      verify(() => user.reauthenticateWithProvider(any())).called(1);
    });

    test('user cancels → throws AuthFailure.signInCancelled', () async {
      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.reauthenticateWithProvider(any())).thenThrow(
        FirebaseAuthException(
          code: 'web-context-cancelled',
          message: 'cancelled',
        ),
      );

      await expectLater(
        () => sut.getAppleCredential(),
        throwsA(const AuthFailure.signInCancelled()),
      );
    });

    test('reauthenticate short-circuits on the Apple sentinel credential',
        () async {
      // Build a sentinel credential by running getAppleCredential, then pass
      // it through reauthenticate — it must NOT call reauthenticateWithCredential.
      final mockUserCred = MockUserCredential();
      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.reauthenticateWithProvider(any()))
          .thenAnswer((_) async => mockUserCred);

      final sentinel = await sut.getAppleCredential();

      // Reset mocks: any subsequent call would now fail if reauthenticate
      // dispatched it down the credential path.
      reset(user);

      await sut.reauthenticate(sentinel);

      verifyNever(() => user.reauthenticateWithCredential(any()));
    });
  });
}

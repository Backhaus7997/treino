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

class FakeAuthCredential extends Fake implements AuthCredential {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAuthCredential());
    registerFallbackValue(<AppleIDAuthorizationScopes>[]);
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
    test(
        'triggers sign_in_with_apple flow and returns OAuthProvider credential',
        () async {
      when(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer(
        (_) async => const AuthorizationCredentialAppleID(
          userIdentifier: 'apple-uid',
          givenName: null,
          familyName: null,
          email: null,
          identityToken: 'apple-id-token',
          authorizationCode: 'apple-auth-code',
          state: null,
        ),
      );

      final credential = await sut.getAppleCredential();

      expect(credential, isA<AuthCredential>());
      verify(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).called(1);
    });

    test('user cancels → throws AuthFailure.signInCancelled', () async {
      when(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenThrow(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'cancelled',
        ),
      );

      await expectLater(
        () => sut.getAppleCredential(),
        throwsA(const AuthFailure.signInCancelled()),
      );
    });
  });
}

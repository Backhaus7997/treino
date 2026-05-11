import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:treino/features/auth/data/apple_sign_in_gateway.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/data/nonce_helpers.dart' as nonce_helpers;
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/auth/domain/auth_outcome.dart';

// --- Mocks ---
class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

class MockAdditionalUserInfo extends Mock implements AdditionalUserInfo {}

class MockAppleSignInGateway extends Mock implements AppleSignInGateway {}

class FakeAuthCredential extends Fake implements AuthCredential {}

AuthorizationCredentialAppleID _makeAppleCred({
  String? givenName,
  String? familyName,
  String identityToken = 'fake_id_token',
}) =>
    AuthorizationCredentialAppleID(
      userIdentifier: 'apple_user_id',
      givenName: givenName,
      familyName: familyName,
      email: 'user@apple.com',
      authorizationCode: 'auth_code',
      identityToken: identityToken,
      state: null,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAuthCredential());
  });

  late MockFirebaseAuth fbAuth;
  late MockUserCredential cred;
  late MockUser user;
  late MockAdditionalUserInfo additionalUserInfo;
  late MockAppleSignInGateway appleGateway;
  late AuthService sut;

  setUp(() {
    fbAuth = MockFirebaseAuth();
    cred = MockUserCredential();
    user = MockUser();
    additionalUserInfo = MockAdditionalUserInfo();
    appleGateway = MockAppleSignInGateway();
    when(() => cred.user).thenReturn(user);
    sut = AuthService(firebaseAuth: fbAuth, appleGateway: appleGateway);
  });

  // ---------------------------------------------------------------------------
  // T-2.3 — Nonce helpers
  // ---------------------------------------------------------------------------
  group('Nonce helpers', () {
    test('sha256OfString("abc") produces known SHA-256 hex', () {
      expect(
        nonce_helpers.sha256OfString('abc'),
        equals(
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
      );
    });

    test('generateNonce() returns a 32-char string by default', () {
      final nonce = nonce_helpers.generateNonce();
      expect(nonce.length, equals(32));
    });

    test('generateNonce() with length=16 returns 16-char string', () {
      expect(nonce_helpers.generateNonce(16).length, equals(16));
    });

    test('two calls to generateNonce() produce different values', () {
      final n1 = nonce_helpers.generateNonce();
      final n2 = nonce_helpers.generateNonce();
      expect(n1, isNot(equals(n2)));
    });
  });

  // ---------------------------------------------------------------------------
  // signUpWithEmail
  // ---------------------------------------------------------------------------
  group('AuthService.signUpWithEmail', () {
    test(
        'T-4.3 / scenario 1.2 — returns AuthOutcome? with user on success and calls sendEmailVerification',
        () async {
      when(
        () => fbAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);
      when(() => additionalUserInfo.isNewUser).thenReturn(true);
      when(() => cred.additionalUserInfo).thenReturn(additionalUserInfo);
      when(() => user.sendEmailVerification()).thenAnswer((_) async {});

      final result = await sut.signUpWithEmail(
        email: 'a@b.c',
        password: 'Pass1234',
      );

      expect(result, isA<AuthOutcome>());
      expect(result?.user, user);
      expect(result?.isNewUser, isTrue);
      verify(() => user.sendEmailVerification()).called(1);
    });

    test('D03 — displayName provided: calls updateDisplayName', () async {
      when(
        () => fbAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);
      when(() => user.updateDisplayName(any())).thenAnswer((_) async {});
      when(() => user.sendEmailVerification()).thenAnswer((_) async {});

      await sut.signUpWithEmail(
        email: 'a@b.c',
        password: 'Pass1234',
        displayName: 'Ana Núñez',
      );

      verify(() => user.updateDisplayName('Ana Núñez')).called(1);
    });

    test('D03 — displayName null: updateDisplayName NOT called', () async {
      when(
        () => fbAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);
      when(() => user.sendEmailVerification()).thenAnswer((_) async {});

      await sut.signUpWithEmail(email: 'a@b.c', password: 'Pass1234');

      verifyNever(() => user.updateDisplayName(any()));
    });

    test('scenario 5.2 — maps email-already-in-use to emailAlreadyInUse',
        () async {
      when(
        () => fbAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      expect(
        () => sut.signUpWithEmail(email: 'a@b.c', password: 'Pass1234'),
        throwsA(const AuthFailure.emailAlreadyInUse()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // signInWithEmail
  // ---------------------------------------------------------------------------
  group('AuthService.signInWithEmail', () {
    test('T-4.1 / scenario 6.2 — returns AuthOutcome? with user on success',
        () async {
      when(
        () => fbAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);
      when(() => additionalUserInfo.isNewUser).thenReturn(false);
      when(() => cred.additionalUserInfo).thenReturn(additionalUserInfo);

      final result = await sut.signInWithEmail(
        email: 'a@b.c',
        password: 'Pass1234',
      );

      expect(result, isA<AuthOutcome>());
      expect(result?.user, user);
      expect(result?.isNewUser, isFalse);
    });

    test('scenario 7.2 — maps wrong-password to wrongPassword', () async {
      when(
        () => fbAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'wrong-password'));

      expect(
        () => sut.signInWithEmail(email: 'a@b.c', password: 'wrong'),
        throwsA(const AuthFailure.wrongPassword()),
      );
    });

    test('scenario 7.3 — maps invalid-credential to wrongPassword', () async {
      when(
        () => fbAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'invalid-credential'));

      expect(
        () => sut.signInWithEmail(email: 'a@b.c', password: 'wrong'),
        throwsA(const AuthFailure.wrongPassword()),
      );
    });

    test('scenario 8.2 — maps user-not-found to userNotFound', () async {
      when(
        () => fbAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'user-not-found'));

      expect(
        () => sut.signInWithEmail(email: 'a@b.c', password: 'Pass1234'),
        throwsA(const AuthFailure.userNotFound()),
      );
    });

    test('scenario 9.1 — maps too-many-requests to tooManyRequests', () async {
      when(
        () => fbAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(FirebaseAuthException(code: 'too-many-requests'));

      expect(
        () => sut.signInWithEmail(email: 'a@b.c', password: 'Pass1234'),
        throwsA(const AuthFailure.tooManyRequests()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // sendPasswordResetEmail
  // ---------------------------------------------------------------------------
  group('AuthService.sendPasswordResetEmail', () {
    test('scenario 10.2 — completes without error on happy path', () async {
      when(
        () => fbAuth.sendPasswordResetEmail(email: any(named: 'email')),
      ).thenAnswer((_) async {});

      await expectLater(
        sut.sendPasswordResetEmail(email: 'a@b.c'),
        completes,
      );
    });

    test('maps user-not-found to userNotFound (screen masks this)', () async {
      when(
        () => fbAuth.sendPasswordResetEmail(email: any(named: 'email')),
      ).thenThrow(FirebaseAuthException(code: 'user-not-found'));

      expect(
        () => sut.sendPasswordResetEmail(email: 'notexist@b.c'),
        throwsA(const AuthFailure.userNotFound()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // signOut
  // ---------------------------------------------------------------------------
  group('AuthService.signOut', () {
    test('scenario 12.1 — completes without error', () async {
      when(() => fbAuth.signOut()).thenAnswer((_) async {});

      await expectLater(sut.signOut(), completes);
      verify(() => fbAuth.signOut()).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // sendEmailVerification
  // ---------------------------------------------------------------------------
  group('AuthService.sendEmailVerification', () {
    test('scenario 14.1 — calls user.sendEmailVerification', () async {
      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.sendEmailVerification()).thenAnswer((_) async {});

      await sut.sendEmailVerification();

      verify(() => user.sendEmailVerification()).called(1);
    });

    test('no-op when no current user', () async {
      when(() => fbAuth.currentUser).thenReturn(null);

      await expectLater(sut.sendEmailVerification(), completes);
    });
  });

  // ---------------------------------------------------------------------------
  // reloadUser
  // ---------------------------------------------------------------------------
  group('AuthService.reloadUser', () {
    test('calls user.reload and returns refreshed user', () async {
      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.reload()).thenAnswer((_) async {});

      final result = await sut.reloadUser();

      verify(() => user.reload()).called(1);
      expect(result, user);
    });

    test('returns null when no current user', () async {
      when(() => fbAuth.currentUser).thenReturn(null);

      final result = await sut.reloadUser();
      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // authStateChanges
  // ---------------------------------------------------------------------------
  group('AuthService.authStateChanges', () {
    test('returns stream from FirebaseAuth.authStateChanges', () {
      final controller = Stream<User?>.fromIterable([user, null]);
      when(() => fbAuth.authStateChanges()).thenAnswer((_) => controller);

      expect(sut.authStateChanges(), isA<Stream<User?>>());
      verify(() => fbAuth.authStateChanges()).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 3 — AuthService.signInWithApple (T-3.1 through T-3.6)
  // ---------------------------------------------------------------------------
  group('AuthService.signInWithApple', () {
    // T-3.1 — Happy path: new user
    test(
        'T-3.1 — happy path new user: returns AuthOutcome(isNewUser=true) and calls updateDisplayName',
        () async {
      when(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer(
        (_) async => _makeAppleCred(givenName: 'Ana', familyName: 'García'),
      );
      when(
        () => fbAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => cred);
      when(() => additionalUserInfo.isNewUser).thenReturn(true);
      when(() => cred.additionalUserInfo).thenReturn(additionalUserInfo);
      when(() => user.updateDisplayName(any())).thenAnswer((_) async {});

      final result = await sut.signInWithApple();

      expect(result, isA<AuthOutcome>());
      expect(result!.user, user);
      expect(result.isNewUser, isTrue);
      verify(() => user.updateDisplayName('Ana García')).called(1);
    });

    // T-3.2 — Happy path: returning user
    test(
        'T-3.2 — returning user: returns AuthOutcome(isNewUser=false) and does NOT call updateDisplayName',
        () async {
      when(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer(
        (_) async => _makeAppleCred(givenName: null, familyName: null),
      );
      when(
        () => fbAuth.signInWithCredential(any()),
      ).thenAnswer((_) async => cred);
      when(() => additionalUserInfo.isNewUser).thenReturn(false);
      when(() => cred.additionalUserInfo).thenReturn(additionalUserInfo);

      final result = await sut.signInWithApple();

      expect(result, isA<AuthOutcome>());
      expect(result!.isNewUser, isFalse);
      verifyNever(() => user.updateDisplayName(any()));
    });

    // T-3.3 — Cancel path
    test('T-3.3 — cancel: returns null without calling signInWithCredential',
        () async {
      when(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenThrow(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'User canceled',
        ),
      );

      final result = await sut.signInWithApple();

      expect(result, isNull);
      verifyNever(() => fbAuth.signInWithCredential(any()));
    });

    // T-3.4 — Apple SDK error (non-cancel)
    test(
        'T-3.4 — Apple SDK unknown error: throws AuthFailure.appleSignInFailed',
        () async {
      when(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenThrow(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.unknown,
          message: 'Unknown error',
        ),
      );

      expect(
        () => sut.signInWithApple(),
        throwsA(const AuthFailure.appleSignInFailed()),
      );
    });

    // T-3.5 — Firebase collision
    test(
        'T-3.5 — Firebase account-exists collision: throws accountExistsWithDifferentCredential',
        () async {
      when(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer(
        (_) async => _makeAppleCred(),
      );
      when(
        () => fbAuth.signInWithCredential(any()),
      ).thenThrow(
        FirebaseAuthException(
          code: 'account-exists-with-different-credential',
        ),
      );
      when(() => additionalUserInfo.isNewUser).thenReturn(false);
      when(() => cred.additionalUserInfo).thenReturn(additionalUserInfo);

      expect(
        () => sut.signInWithApple(),
        throwsA(const AuthFailure.accountExistsWithDifferentCredential()),
      );
    });

    // T-3.6 — Nonce direction
    test(
        'T-3.6 — nonce direction: Apple receives hash, Firebase receives raw nonce',
        () async {
      final capturedNonces = <String>[];
      final capturedCredentials = <AuthCredential>[];

      when(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer((inv) async {
        capturedNonces.add(inv.namedArguments[#nonce] as String);
        return _makeAppleCred();
      });
      when(
        () => fbAuth.signInWithCredential(any()),
      ).thenAnswer((inv) async {
        capturedCredentials.add(inv.positionalArguments[0] as AuthCredential);
        return cred;
      });
      when(() => additionalUserInfo.isNewUser).thenReturn(false);
      when(() => cred.additionalUserInfo).thenReturn(additionalUserInfo);

      await sut.signInWithApple();

      expect(capturedNonces.length, 1);
      expect(capturedCredentials.length, 1);

      final appleNonce = capturedNonces[0];
      final oauthCred = capturedCredentials[0] as OAuthCredential;
      final firebaseRawNonce = oauthCred.rawNonce!;

      // Apple received the HASH of rawNonce
      expect(
          appleNonce, equals(nonce_helpers.sha256OfString(firebaseRawNonce)));
      // Firebase received the RAW nonce
      expect(firebaseRawNonce, isNot(equals(appleNonce)));

      // SUGG-1: explicit direction — sha256(rawNonce) == appleNonce (bidirectional)
      expect(
        nonce_helpers.sha256OfString(firebaseRawNonce),
        equals(appleNonce),
      );
      // explicit defense-in-depth: raw and hash are never accidentally identical
      expect(firebaseRawNonce, isNot(equals(appleNonce)));
    });

    // W-2 — Apple path: network-request-failed maps to AuthFailure.networkError
    test('maps network-request-failed to AuthFailure.network on Apple path',
        () async {
      when(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer(
        (_) async => _makeAppleCred(),
      );
      when(
        () => fbAuth.signInWithCredential(any()),
      ).thenThrow(
        FirebaseAuthException(code: 'network-request-failed'),
      );

      expect(
        () => sut.signInWithApple(),
        throwsA(const AuthFailure.networkError()),
      );
    });

    // Batch 4 — invalid-credential on Apple path must NOT map to wrongPassword
    test(
        'maps invalid-credential to AuthFailure.appleSignInFailed on Apple path (NOT wrongPassword)',
        () async {
      when(
        () => appleGateway.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer(
        (_) async => _makeAppleCred(),
      );
      when(
        () => fbAuth.signInWithCredential(any()),
      ).thenThrow(
        FirebaseAuthException(code: 'invalid-credential'),
      );

      expect(
        () => sut.signInWithApple(),
        throwsA(const AuthFailure.appleSignInFailed()),
      );
    });
  });
}

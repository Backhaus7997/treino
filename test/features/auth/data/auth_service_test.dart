import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// --- Mocks ---
class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

class MockUserRepository extends Mock implements UserRepository {}

class FakeAuthCredential extends Fake implements AuthCredential {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class MockGoogleSignInAuthorizationClient extends Mock
    implements GoogleSignInAuthorizationClient {}

// Fake UserProfile used as stub return value — displayName remains null until
// ProfileSetup (Etapa 6) populates it.
final _fakeProfile = UserProfile(
  uid: 'uid-fake',
  email: 'a@b.c',
  displayName: null,
  role: UserRole.athlete,
  createdAt: DateTime.utc(2026, 5, 11),
  updatedAt: DateTime.utc(2026, 5, 11),
);

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAuthCredential());
  });

  late MockFirebaseAuth fbAuth;
  late MockUserCredential cred;
  late MockUser user;
  late MockUserRepository mockRepo;
  late MockGoogleSignIn googleSignIn;
  late AuthService sut;

  setUp(() {
    fbAuth = MockFirebaseAuth();
    cred = MockUserCredential();
    user = MockUser();
    mockRepo = MockUserRepository();
    googleSignIn = MockGoogleSignIn();

    when(() => cred.user).thenReturn(user);
    when(() => user.uid).thenReturn('uid-test');
    when(() => user.email).thenReturn('a@b.c');
    when(() => user.displayName).thenReturn('Ana');

    // Default stubs so existing tests that don't care about repo still work
    when(
      () => mockRepo.getOrCreate(
        uid: any(named: 'uid'),
        email: any(named: 'email'),
      ),
    ).thenAnswer((_) async => _fakeProfile);
    when(
      () => mockRepo.createIfAbsent(
        uid: any(named: 'uid'),
        email: any(named: 'email'),
      ),
    ).thenAnswer((_) async {});

    sut = AuthService(
      firebaseAuth: fbAuth,
      userRepository: mockRepo,
      googleSignIn: googleSignIn,
    );
  });

  // ---------------------------------------------------------------------------
  // signUpWithEmail
  // ---------------------------------------------------------------------------
  group('AuthService.signUpWithEmail', () {
    test(
        'scenario 1.2 — returns User on success and calls sendEmailVerification',
        () async {
      when(
        () => fbAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);
      when(() => user.sendEmailVerification()).thenAnswer((_) async {});

      final result = await sut.signUpWithEmail(
        email: 'a@b.c',
        password: 'Pass1234',
      );

      expect(result, user);
      verify(() => user.sendEmailVerification()).called(1);
    });

    test('D03 — signUp never calls updateDisplayName (deferred to Etapa 6)',
        () async {
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

    // T29: SCENARIO-020 — happy path call order (no displayName work)
    test(
        'SCENARIO-020: signup happy path calls sendEmailVerification and getOrCreate; never updateDisplayName',
        () async {
      when(
        () => fbAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);
      when(() => user.sendEmailVerification()).thenAnswer((_) async {});

      await sut.signUpWithEmail(email: 'a@b.c', password: 'Pass1234');

      verifyNever(() => user.updateDisplayName(any()));
      verify(() => user.sendEmailVerification()).called(1);
      verify(
        () => mockRepo.getOrCreate(
          uid: any(named: 'uid'),
          email: any(named: 'email'),
        ),
      ).called(1);
    });

    // T30: SCENARIO-021 — rollback: getOrCreate throws → user.delete() called
    test(
        'SCENARIO-021: getOrCreate throws → user.delete() called → profileCreateFailed thrown',
        () async {
      when(
        () => fbAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);
      when(() => user.sendEmailVerification()).thenAnswer((_) async {});
      when(() => user.delete()).thenAnswer((_) async {});
      when(
        () => mockRepo.getOrCreate(
          uid: any(named: 'uid'),
          email: any(named: 'email'),
        ),
      ).thenThrow(Exception('firestore down'));

      await expectLater(
        () => sut.signUpWithEmail(email: 'a@b.c', password: 'Pass1234'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.map(
              invalidEmail: (_) => false,
              userDisabled: (_) => false,
              userNotFound: (_) => false,
              wrongPassword: (_) => false,
              emailAlreadyInUse: (_) => false,
              weakPassword: (_) => false,
              tooManyRequests: (_) => false,
              networkError: (_) => false,
              signInCancelled: (_) => false,
              accountExistsWithDifferentCredential: (_) => false,
              unknown: (_) => false,
              profileCreateFailed: (_) => true,
            ),
            'is profileCreateFailed',
            isTrue,
          ),
        ),
      );

      verify(() => user.delete()).called(1);
    });

    // T30: SCENARIO-022 — rollback: getOrCreate throws AND user.delete throws
    test(
        'SCENARIO-022: getOrCreate throws AND user.delete throws → profileCreateFailed still thrown',
        () async {
      when(
        () => fbAuth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);
      when(() => user.sendEmailVerification()).thenAnswer((_) async {});
      when(() => user.delete()).thenThrow(Exception('delete failed'));
      when(
        () => mockRepo.getOrCreate(
          uid: any(named: 'uid'),
          email: any(named: 'email'),
        ),
      ).thenThrow(Exception('firestore down'));

      // Must throw profileCreateFailed, NOT the delete exception
      await expectLater(
        () => sut.signUpWithEmail(email: 'a@b.c', password: 'Pass1234'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.map(
              invalidEmail: (_) => false,
              userDisabled: (_) => false,
              userNotFound: (_) => false,
              wrongPassword: (_) => false,
              emailAlreadyInUse: (_) => false,
              weakPassword: (_) => false,
              tooManyRequests: (_) => false,
              networkError: (_) => false,
              signInCancelled: (_) => false,
              accountExistsWithDifferentCredential: (_) => false,
              unknown: (_) => false,
              profileCreateFailed: (_) => true,
            ),
            'is profileCreateFailed',
            isTrue,
          ),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // signInWithEmail
  // ---------------------------------------------------------------------------
  group('AuthService.signInWithEmail', () {
    test('scenario 6.2 — returns User on success', () async {
      when(
        () => fbAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);

      final result = await sut.signInWithEmail(
        email: 'a@b.c',
        password: 'Pass1234',
      );

      expect(result, user);
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

    // T31: SCENARIO-023 — createIfAbsent called once on sign-in
    test('SCENARIO-023: signInWithEmail calls createIfAbsent exactly once',
        () async {
      when(
        () => fbAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);

      await sut.signInWithEmail(email: 'a@b.c', password: 'Pass1234');

      verify(
        () => mockRepo.createIfAbsent(
          uid: any(named: 'uid'),
          email: any(named: 'email'),
        ),
      ).called(1);
    });

    // T31: SCENARIO-024 — sign-in twice → createIfAbsent called twice
    test('SCENARIO-024: signInWithEmail twice → createIfAbsent called twice',
        () async {
      when(
        () => fbAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);

      await sut.signInWithEmail(email: 'a@b.c', password: 'Pass1234');
      await sut.signInWithEmail(email: 'a@b.c', password: 'Pass1234');

      verify(
        () => mockRepo.createIfAbsent(
          uid: any(named: 'uid'),
          email: any(named: 'email'),
        ),
      ).called(2);
    });

    // T31: REQ-PROF-037 — createIfAbsent throws → sign-in still succeeds
    test('REQ-PROF-037: createIfAbsent throws → sign-in still returns user',
        () async {
      when(
        () => fbAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);
      when(
        () => mockRepo.createIfAbsent(
          uid: any(named: 'uid'),
          email: any(named: 'email'),
        ),
      ).thenThrow(Exception('Firestore down'));

      final result = await sut.signInWithEmail(
        email: 'a@b.c',
        password: 'Pass1234',
      );
      expect(result, user);
    });

    // signIn backfill no longer synthesizes a displayName from the email
    test(
        'sign-in backfill never derives displayName from email or Firebase user',
        () async {
      when(() => user.displayName).thenReturn(null);
      when(
        () => fbAuth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => cred);

      await sut.signInWithEmail(email: 'alice@example.com', password: 'P1234');

      // createIfAbsent must be called with only uid + email — no displayName at all.
      verify(
        () => mockRepo.createIfAbsent(
          uid: 'uid-test',
          email: 'alice@example.com',
        ),
      ).called(1);
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
  // signInWithGoogle
  // ---------------------------------------------------------------------------
  group('AuthService.signInWithGoogle', () {
    late MockGoogleSignInAccount googleAccount;
    late MockGoogleSignInAuthorizationClient authzClient;

    setUp(() {
      googleAccount = MockGoogleSignInAccount();
      authzClient = MockGoogleSignInAuthorizationClient();
      // 7.x: account.authentication is a sync getter returning idToken only.
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

    test('happy path — returns User after Firebase credential exchange',
        () async {
      when(() => googleSignIn.authenticate())
          .thenAnswer((_) async => googleAccount);
      when(() => fbAuth.signInWithCredential(any()))
          .thenAnswer((_) async => cred);

      final result = await sut.signInWithGoogle();

      expect(result, user);
      verify(() => googleSignIn.authenticate()).called(1);
      verify(() => authzClient.authorizeScopes(const <String>['email']))
          .called(1);
      verify(() => fbAuth.signInWithCredential(any())).called(1);
    });

    test('user dismisses picker → throws AuthFailure.signInCancelled',
        () async {
      when(() => googleSignIn.authenticate()).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'user cancelled',
        ),
      );

      expect(
        () => sut.signInWithGoogle(),
        throwsA(const AuthFailure.signInCancelled()),
      );
    });

    test(
        'PlatformException from google_sign_in → AuthFailure.unknown with code',
        () async {
      when(() => googleSignIn.authenticate()).thenThrow(
        PlatformException(code: 'network_error'),
      );

      expect(
        () => sut.signInWithGoogle(),
        throwsA(const AuthFailure.unknown('network_error')),
      );
    });

    test(
        'non-cancel GoogleSignInException from authenticate → AuthFailure.unknown with code',
        () async {
      when(() => googleSignIn.authenticate()).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.interrupted,
          description: 'lost connection',
        ),
      );

      expect(
        () => sut.signInWithGoogle(),
        throwsA(const AuthFailure.unknown('interrupted')),
      );
    });

    test('user cancels scope authorization → AuthFailure.signInCancelled',
        () async {
      when(() => googleSignIn.authenticate())
          .thenAnswer((_) async => googleAccount);
      when(() => authzClient.authorizeScopes(any())).thenThrow(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: 'user dismissed consent',
        ),
      );

      expect(
        () => sut.signInWithGoogle(),
        throwsA(const AuthFailure.signInCancelled()),
      );
    });

    test(
        'FirebaseAuthException during credential exchange is mapped via fromFirebase',
        () async {
      when(() => googleSignIn.authenticate())
          .thenAnswer((_) async => googleAccount);
      when(() => fbAuth.signInWithCredential(any())).thenThrow(
        FirebaseAuthException(code: 'account-exists-with-different-credential'),
      );

      expect(
        () => sut.signInWithGoogle(),
        throwsA(const AuthFailure.accountExistsWithDifferentCredential()),
      );
    });

    // SCENARIO-025 — Google sign-in backfills users/{uid} via createIfAbsent
    test(
        'SCENARIO-025: signInWithGoogle backfills users/{uid} via createIfAbsent (REQ-PROF-036/037)',
        () async {
      when(() => googleSignIn.authenticate())
          .thenAnswer((_) async => googleAccount);
      when(() => fbAuth.signInWithCredential(any()))
          .thenAnswer((_) async => cred);

      await sut.signInWithGoogle();

      verify(
        () => mockRepo.createIfAbsent(
          uid: 'uid-test',
          email: 'a@b.c',
        ),
      ).called(1);
    });

    test('signInWithGoogle: createIfAbsent throwing does NOT fail the sign-in',
        () async {
      when(() => googleSignIn.authenticate())
          .thenAnswer((_) async => googleAccount);
      when(() => fbAuth.signInWithCredential(any()))
          .thenAnswer((_) async => cred);
      when(
        () => mockRepo.createIfAbsent(
          uid: any(named: 'uid'),
          email: any(named: 'email'),
        ),
      ).thenThrow(Exception('Firestore down'));

      final result = await sut.signInWithGoogle();

      expect(result, user);
    });
  });

  // ---------------------------------------------------------------------------
  // signOut
  // ---------------------------------------------------------------------------
  group('AuthService.signOut', () {
    test('scenario 12.1 — completes without error', () async {
      when(() => googleSignIn.signOut()).thenAnswer((_) async {});
      when(() => fbAuth.signOut()).thenAnswer((_) async {});

      await expectLater(sut.signOut(), completes);
      verify(() => fbAuth.signOut()).called(1);
    });

    test('also signs out from Google to force account picker on next signIn',
        () async {
      when(() => googleSignIn.signOut()).thenAnswer((_) async {});
      when(() => fbAuth.signOut()).thenAnswer((_) async {});

      await sut.signOut();

      verify(() => googleSignIn.signOut()).called(1);
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
}

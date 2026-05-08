import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';

// --- Mocks ---
class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

class FakeAuthCredential extends Fake implements AuthCredential {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAuthCredential());
  });

  late MockFirebaseAuth fbAuth;
  late MockUserCredential cred;
  late MockUser user;
  late AuthService sut;

  setUp(() {
    fbAuth = MockFirebaseAuth();
    cred = MockUserCredential();
    user = MockUser();
    when(() => cred.user).thenReturn(user);
    sut = AuthService(firebaseAuth: fbAuth);
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
}

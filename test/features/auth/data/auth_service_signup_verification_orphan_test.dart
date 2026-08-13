import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// Regression test for: "signUpWithEmail leaves an orphan Auth user if
// sendEmailVerification throws". A rate-limit (too-many-requests) failure on
// the verification email must be non-fatal — the Auth user stays, the Firestore
// profile is created, and signup succeeds. Verification can be resent later.

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

class MockUserRepository extends Mock implements UserRepository {}

final _fakeProfile = UserProfile(
  uid: 'uid-fake',
  email: 'a@b.c',
  displayName: null,
  role: UserRole.athlete,
  createdAt: DateTime.utc(2026, 5, 11),
  updatedAt: DateTime.utc(2026, 5, 11),
);

void main() {
  late MockFirebaseAuth fbAuth;
  late MockUserCredential cred;
  late MockUser user;
  late MockUserRepository mockRepo;
  late AuthService sut;

  setUp(() {
    fbAuth = MockFirebaseAuth();
    cred = MockUserCredential();
    user = MockUser();
    mockRepo = MockUserRepository();

    when(() => cred.user).thenReturn(user);
    when(() => user.uid).thenReturn('uid-test');
    when(() => user.email).thenReturn('a@b.c');
    // termsAcceptedAt must be matched too — signUpWithEmail always passes it
    // now (QA-AUTH-001, issue #434).
    when(
      () => mockRepo.getOrCreate(
        uid: any(named: 'uid'),
        email: any(named: 'email'),
        termsAcceptedAt: any(named: 'termsAcceptedAt'),
      ),
    ).thenAnswer((_) async => _fakeProfile);

    sut = AuthService(firebaseAuth: fbAuth, userRepository: mockRepo);
  });

  test(
      'sendEmailVerification too-many-requests is non-fatal: no orphan delete, '
      'profile created, signup returns user', () async {
    when(
      () => fbAuth.createUserWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => cred);
    when(() => user.sendEmailVerification())
        .thenThrow(FirebaseAuthException(code: 'too-many-requests'));
    when(() => user.delete()).thenAnswer((_) async {});

    final result =
        await sut.signUpWithEmail(email: 'a@b.c', password: 'Pass1234');

    // Signup succeeds despite the verification-email failure.
    expect(result, user);
    // The orphan Auth user must NOT be deleted on a verification failure.
    verifyNever(() => user.delete());
    // The Firestore profile is still created.
    verify(
      () => mockRepo.getOrCreate(
        uid: 'uid-test',
        email: 'a@b.c',
        termsAcceptedAt: any(named: 'termsAcceptedAt'),
      ),
    ).called(1);
  });
}

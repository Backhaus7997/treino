import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// Regression test for: "signUpWithEmail leaves an orphan Auth user if
// sendEmailVerification throws". Un fallo al mandar el mail de verificacion
// tiene que ser NO FATAL — el usuario de Auth queda, el perfil de Firestore se
// crea, y el alta devuelve el usuario. La verificacion se reenvia despues.
//
// ─── Por que el catch de signup atrapa TODO ─────────────────────────────────
//
// El rollback que borra al usuario huerfano vive DENTRO del try de
// `getOrCreate`. O sea: una excepcion que se escapa del bloque de verificacion
// no dispara el rollback — saltea la creacion del perfil Y el rollback. El
// usuario queda en Auth, sin doc en Firestore, y sin nadie que lo limpie.
//
// El catch original era `on FirebaseAuthException`, mas angosto que la promesa
// del comentario que tenia arriba. Ahora el mail sale por el callable
// `requestEmailVerification` (outbox + Resend), asi que la superficie de
// fallo es otra: FirebaseFunctionsException, AuthFailure, red. De ahi que los
// casos de abajo prueben las TRES formas, no solo la de Firebase Auth.

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

class MockUserRepository extends Mock implements UserRepository {}

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockCallableResult extends Mock
    implements HttpsCallableResult<Map<String, dynamic>> {}

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
  late MockFirebaseFunctions functions;
  late MockHttpsCallable callable;
  late AuthService sut;

  setUp(() {
    fbAuth = MockFirebaseAuth();
    cred = MockUserCredential();
    user = MockUser();
    mockRepo = MockUserRepository();
    functions = MockFirebaseFunctions();
    callable = MockHttpsCallable();

    when(() => cred.user).thenReturn(user);
    when(() => user.uid).thenReturn('uid-test');
    when(() => user.email).thenReturn('a@b.c');
    when(() => user.delete()).thenAnswer((_) async {});
    // termsAcceptedAt must be matched too — signUpWithEmail always passes it
    // now (QA-AUTH-001, issue #434).
    when(
      () => mockRepo.getOrCreate(
        uid: any(named: 'uid'),
        email: any(named: 'email'),
        termsAcceptedAt: any(named: 'termsAcceptedAt'),
        acceptedTermsVersion: any(named: 'acceptedTermsVersion'),
        acceptedPrivacyVersion: any(named: 'acceptedPrivacyVersion'),
      ),
    ).thenAnswer((_) async => _fakeProfile);

    when(
      () => fbAuth.createUserWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => cred);
    // El callable exige auth; despues del alta el usuario YA esta firmado.
    when(() => fbAuth.currentUser).thenReturn(user);
    when(() => functions.httpsCallable(any())).thenReturn(callable);

    sut = AuthService(
      firebaseAuth: fbAuth,
      userRepository: mockRepo,
      functions: functions,
    );
  });

  /// Corre el alta con el callable de verificacion fallando de una forma dada,
  /// y afirma lo unico que importa: el alta igual termina bien y limpia.
  Future<void> expectSignupSurvives(Object error) async {
    when(() => callable.call<Map<String, dynamic>>(any())).thenThrow(error);

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
        acceptedTermsVersion: any(named: 'acceptedTermsVersion'),
        acceptedPrivacyVersion: any(named: 'acceptedPrivacyVersion'),
      ),
    ).called(1);
  }

  test('un rate-limit del callable es no fatal', () async {
    await expectSignupSurvives(
      FirebaseFunctionsException(
        code: 'resource-exhausted',
        message: 'too many requests',
      ),
    );
  });

  // Este es el caso que el catch angosto dejaba pasar. Un corte de red al
  // invocar el callable no es un FirebaseAuthException ni un
  // FirebaseFunctionsException: es una excepcion cualquiera. Con
  // `on FirebaseAuthException` se escapaba y dejaba al usuario huerfano.
  test('una excepcion cualquiera tampoco deja huerfano al usuario', () async {
    await expectSignupSurvives(Exception('la red se cayo'));
  });

  // AuthService envuelve los fallos del callable en AuthFailure. Como el try
  // externo de signUpWithEmail tiene `on AuthFailure { rethrow }`, un catch
  // angosto acá haria que el alta FALLE — con el usuario ya creado en Auth.
  test('el AuthFailure que arma el propio AuthService no propaga', () async {
    await expectSignupSurvives(
      FirebaseFunctionsException(code: 'internal', message: 'boom'),
    );
  });

  test('en el camino feliz el mail sale por el callable, no por Firebase',
      () async {
    when(() => callable.call<Map<String, dynamic>>(any()))
        .thenAnswer((_) async => MockCallableResult());

    await sut.signUpWithEmail(email: 'a@b.c', password: 'Pass1234');

    verify(() => functions.httpsCallable('requestEmailVerification')).called(1);
    verifyNever(() => user.sendEmailVerification());
  });
}

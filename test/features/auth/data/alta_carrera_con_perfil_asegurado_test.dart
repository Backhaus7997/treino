// La carrera del alta por mail, medida en producción (oct-2026).
//
// Apenas `createUserWithEmailAndPassword` vuelve, el router manda a
// `/profile-setup` y `perfilAseguradoProvider` dispara un `createIfAbsent`
// (perfil vacío, sin consentimiento) MIENTRAS `signUpWithEmail` está en su
// `getOrCreate`. Si el `createIfAbsent` aterrizaba entre la lectura y el
// commit del registro, el `set` sin merge del registro llegaba como UPDATE
// con otro `createdAt`, el pin de la regla lo rechazaba y el rollback BORRABA
// la cuenta de Auth: «Hubo un problema creando tu perfil», con docs huérfanos.
//
// Acá corren el `AuthService` y el `UserRepository` reales sobre un Firestore
// falso que reproduce esa carrera: el primer batch (el del registro) deja
// pasar al `createIfAbsent` competidor y después rebota como lo hace la regla.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/profile/data/user_repository.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

const _uid = 'uid-carrera';

/// Firestore falso donde el PRIMER batch pierde la carrera: al commitear,
/// primero corre [competidor] (el `createIfAbsent` de `perfilAsegurado`) y
/// después rebota con `permission-denied`, sin escribir nada — lo mismo que
/// hace la regla real con un `set` sin merge que cambia `createdAt`.
///
/// Con [competidor] en null el primer batch falla sin que nadie cree el doc:
/// es un fallo genuino.
class _FirestoreConCarrera extends FakeFirebaseFirestore {
  Future<void> Function()? competidor;
  bool _primero = true;

  @override
  WriteBatch batch() {
    final real = super.batch();
    if (!_primero) return real;
    _primero = false;
    return _BatchQuePierde(real, () async {
      await competidor?.call();
    });
  }
}

class _BatchQuePierde implements WriteBatch {
  _BatchQuePierde(this._real, this._antesDeRebotar);

  final WriteBatch _real;
  final Future<void> Function() _antesDeRebotar;

  @override
  Future<void> commit() async {
    await _antesDeRebotar();
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
  }

  @override
  void delete(DocumentReference document) => _real.delete(document);

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) =>
      _real.set(document, data, options);

  @override
  void update(DocumentReference document, Map<String, dynamic> data) =>
      _real.update(document, data);
}

void main() {
  late _FirestoreConCarrera firestore;
  late UserRepository repo;
  late _MockFirebaseAuth fbAuth;
  late _MockUser user;
  late AuthService sut;
  late List<String> reportados;

  setUp(() {
    firestore = _FirestoreConCarrera();
    repo = UserRepository(
      firestore: firestore,
      gyms: GymRepository(firestore: firestore),
    );
    fbAuth = _MockFirebaseAuth();
    user = _MockUser();
    final cred = _MockUserCredential();
    when(() => cred.user).thenReturn(user);
    when(() => user.uid).thenReturn(_uid);
    when(() => user.email).thenReturn('a@b.c');
    when(() => user.delete()).thenAnswer((_) async {});
    when(
      () => fbAuth.createUserWithEmailAndPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => cred);

    reportados = <String>[];
    sut = AuthService(
      firebaseAuth: fbAuth,
      userRepository: repo,
      googleSignIn: _MockGoogleSignIn(),
      nonFatalReporter: (error, stack, {required reason}) async =>
          reportados.add(reason),
    );
  });

  Future<Map<String, dynamic>?> doc() async =>
      (await firestore.collection('users').doc(_uid).get()).data();

  test(
      'createIfAbsent gana entre la lectura y el commit del registro → la '
      'cuenta NO se borra y queda con el consentimiento', () async {
    firestore.competidor = () => repo.createIfAbsent(uid: _uid, email: 'a@b.c');

    final result =
        await sut.signUpWithEmail(email: 'a@b.c', password: 'Pass1234');

    expect(result, same(user));
    verifyNever(() => user.delete());

    final data = await doc();
    expect(data, isNotNull);
    expect(data!['termsAcceptedAt'], isA<Timestamp>());
    expect(data['acceptedTermsVersion'], kTermsVersion);
    expect(data['acceptedPrivacyVersion'], kPrivacyVersion);
    // El público lo dejó el ganador; el registro no lo necesita reescribir.
    final pub =
        await firestore.collection('userPublicProfiles').doc(_uid).get();
    expect(pub.exists, isTrue);
  });

  test('fallo genuino sin doc → el rollback borra la cuenta, como antes',
      () async {
    firestore.competidor = null;

    await expectLater(
      () => sut.signUpWithEmail(email: 'a@b.c', password: 'Pass1234'),
      throwsA(isA<AuthFailure>()),
    );
    verify(() => user.delete()).called(1);
    expect(await doc(), isNull);
  });

  group('UserRepository.getOrCreate sobre un doc que ya existe', () {
    setUp(() => firestore._primero = false);

    test(
        'sin consentimiento (el createIfAbsent ganó antes de la lectura) → '
        'lo estampa', () async {
      await repo.createIfAbsent(uid: _uid, email: 'a@b.c');
      final antes = await doc();

      final aceptado = DateTime.utc(2026, 10, 8, 12);
      final perfil = await repo.getOrCreate(
        uid: _uid,
        email: 'a@b.c',
        termsAcceptedAt: aceptado,
        acceptedTermsVersion: kTermsVersion,
        acceptedPrivacyVersion: kPrivacyVersion,
      );

      expect(perfil.termsAcceptedAt, aceptado);
      final data = await doc();
      expect(
          (data!['termsAcceptedAt'] as Timestamp).toDate().toUtc(), aceptado);
      expect(data['acceptedTermsVersion'], kTermsVersion);
      expect(data['createdAt'], antes!['createdAt']);
    });

    test('con consentimiento previo → no lo pisa', () async {
      final original = DateTime.utc(2026, 1, 1);
      await repo.createIfAbsent(
        uid: _uid,
        email: 'a@b.c',
        termsAcceptedAt: original,
        acceptedTermsVersion: 1,
        acceptedPrivacyVersion: 1,
      );

      await repo.getOrCreate(
        uid: _uid,
        email: 'a@b.c',
        termsAcceptedAt: DateTime.utc(2026, 10, 8),
        acceptedTermsVersion: kTermsVersion,
        acceptedPrivacyVersion: kPrivacyVersion,
      );

      final data = await doc();
      expect(
          (data!['termsAcceptedAt'] as Timestamp).toDate().toUtc(), original);
      expect(data['acceptedTermsVersion'], 1);
    });
  });
}

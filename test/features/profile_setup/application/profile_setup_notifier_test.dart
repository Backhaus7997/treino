import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart'
    show authStateChangesProvider, firebaseAuthProvider;
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider, userProfileProvider, userRepositoryProvider;
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/data/avatar_upload_service.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _FakeAvatarUploadService implements AvatarUploadService {
  _FakeAvatarUploadService({this.error});

  /// QA-PRO-106: when set, [upload] throws it instead of returning a URL.
  /// Mutable on purpose — the retry scenario flips a failing service into a
  /// succeeding one between two submits of the SAME container.
  Object? error;

  @override
  Future<String> upload(String localPath) async {
    final e = error;
    if (e != null) throw e;
    return 'https://fake.url/avatar.jpg';
  }
}

/// Fecha de nacimiento válida para el gate de edad mínima.
///
/// Fija y bien lejos del borde a propósito: estos tests miden el SUBMIT, no el
/// cálculo de la edad. Ese tiene su propia suite en
/// `profile_setup_validators_test.dart`, con los bordes y el 29 de febrero.
final _adultBornAt = DateTime.utc(1990, 5, 20);

void main() {
  late FakeFirebaseFirestore firestore;
  late _MockFirebaseAuth mockAuth;
  late _MockUser mockUser;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    mockAuth = _MockFirebaseAuth();
    mockUser = _MockUser();

    when(() => mockUser.uid).thenReturn('u1');
    when(() => mockUser.email).thenReturn('test@test.com');
    when(() => mockAuth.currentUser).thenReturn(mockUser);
  });

  /// Seeds the users/{uid} doc so submit() can call update() on it.
  ///
  /// Por default es una cuenta de EMAIL: el registro ya estampó
  /// `termsAcceptedAt`, así que el alta no pide el checkbox. Antes este doc se
  /// sembraba sin el campo y los tests pasaban igual, porque la regla era
  /// «perfil existente = ya consintió». Así es exactamente como nace el doc de
  /// un alta con Google/Apple, y la regla la dejaba sin consentimiento: esa
  /// forma ahora se siembra explícita con `conConsentimiento: false`.
  Future<void> seedUserDoc(String uid, {bool conConsentimiento = true}) async {
    final now = DateTime.now().toUtc();
    await firestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'test@test.com',
      'displayName': null,
      'role': 'athlete',
      'createdAt': now,
      'updatedAt': now,
      if (conConsentimiento)
        'termsAcceptedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1, 12)),
    });
  }

  /// [perfilObservado] reemplaza lo que la app OBSERVA del perfil (el stream
  /// de `userProfileProvider`, que puede venir de la caché local) sin tocar
  /// lo que hay en el "servidor" (`firestore`). Por default, el stream sale
  /// del mismo firestore y los dos coinciden.
  ProviderContainer makeContainer({
    AvatarUploadService? avatarService,
    Stream<UserProfile?> Function()? perfilObservado,
  }) {
    return ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(firestore),
      userRepositoryProvider.overrideWithValue(
        UserRepository(firestore: firestore),
      ),
      firebaseAuthProvider.overrideWithValue(mockAuth),
      // El notifier ata su estado al uid logueado (ver su build()).
      authStateChangesProvider.overrideWith((ref) => Stream.value(mockUser)),
      avatarUploadServiceProvider
          .overrideWithValue(avatarService ?? _FakeAvatarUploadService()),
      // QA-AUTH-001 (issue #434): submit() now reads userProfileProvider to
      // decide whether Terms consent is required. Route it through the same
      // fake-firestore-backed repo used everywhere else in this file —
      // mirrors production (userProfileProvider watches repo.watch(uid))
      // instead of wiring the real authStateChanges() stream chain.
      userProfileProvider.overrideWith(
        (ref) =>
            perfilObservado?.call() ??
            ref.watch(userRepositoryProvider).watch('u1'),
      ),
    ]);
  }

  /// Un perfil observado que no emite nunca: queda en AsyncLoading, o sea
  /// «todavía no se sabe» si hay consentimiento.
  Stream<UserProfile?> nuncaEmite() => StreamController<UserProfile?>().stream;

  /// Primes [userProfileProvider] so its `.valueOrNull` is resolved (not
  /// AsyncLoading) by the time `submit()` reads it synchronously — mirrors
  /// how, in production, the router's authRedirect already resolved this
  /// provider before ever landing the user on ProfileSetup.
  Future<void> primeUserProfile(ProviderContainer container) =>
      container.read(userProfileProvider.future);

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-265: submit writes both users and userPublicProfiles
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-265: submit writes both users and userPublicProfiles',
      () async {
    await seedUserDoc('u1');
    final container = makeContainer();
    addTearDown(container.dispose);
    await primeUserProfile(container);

    final notifier = container.read(profileSetupNotifierProvider.notifier);
    notifier.updateUsername('Carlos');
    notifier.updateBornAt(_adultBornAt);

    await notifier.submit();

    final usersSnap = await firestore.collection('users').doc('u1').get();
    final pubSnap =
        await firestore.collection('userPublicProfiles').doc('u1').get();

    expect(usersSnap.data()!['displayName'], equals('Carlos'));
    expect(pubSnap.exists, isTrue);
    expect(pubSnap.data()!['displayName'], equals('Carlos'));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-266: submit derives displayNameLowercase automatically
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-266: submit derives displayNameLowercase automatically',
      () async {
    await seedUserDoc('u1');
    final container = makeContainer();
    addTearDown(container.dispose);
    await primeUserProfile(container);

    final notifier = container.read(profileSetupNotifierProvider.notifier);
    notifier.updateUsername('Carlos');
    notifier.updateBornAt(_adultBornAt);

    await notifier.submit();

    final pubSnap =
        await firestore.collection('userPublicProfiles').doc('u1').get();
    expect(pubSnap.data()!['displayNameLowercase'], equals('carlos'));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-268: submit self-heals when the base docs do not exist yet.
  // Repro del bug real: una sesión restaurada (login cacheado) nunca corre
  // createIfAbsent, así que una cuenta sin users/{uid} llegaba al submit y el
  // update() era un CREATE denegado por las rules (sin uid/role).
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-268: submit creates users + userPublicProfiles when neither '
      'exists yet (self-heal de sesión restaurada / datos borrados)', () async {
    // Intencionalmente NO seedeamos el doc — simula la cuenta autenticada cuyos
    // docs nunca se crearon o se borraron en dev.
    final container = makeContainer();
    addTearDown(container.dispose);
    await primeUserProfile(container);

    final notifier = container.read(profileSetupNotifierProvider.notifier);
    notifier.updateUsername('Carlos');
    notifier.updateBornAt(_adultBornAt);
    // QA-AUTH-001 (issue #434): sin `users/{uid}`, userProfileProvider
    // resuelve null — desde el código esto es indistinguible de una cuenta
    // OAuth nueva, así que ahora también exige el checkbox. Es el
    // comportamiento correcto: sin el doc no hay evidencia de consentimiento
    // previo, así que se vuelve a pedir.
    notifier.updateTermsAccepted(true);

    await notifier.submit();

    final usersSnap = await firestore.collection('users').doc('u1').get();
    final pubSnap =
        await firestore.collection('userPublicProfiles').doc('u1').get();

    expect(usersSnap.exists, isTrue);
    // uid + role sólo los aporta createIfAbsent: el partial sanitizado de
    // update() los filtra. Si el self-heal no corriera, faltarían y la regla
    // de create los rechazaría.
    expect(usersSnap.data()!['uid'], equals('u1'));
    expect(usersSnap.data()!['role'], equals('athlete'));
    expect(usersSnap.data()!['displayName'], equals('Carlos'));
    // The gate above also means this self-heal path now records consent.
    expect(usersSnap.data()!['termsAcceptedAt'], isNotNull);

    expect(pubSnap.exists, isTrue);
    expect(pubSnap.data()!['uid'], equals('u1'));
    expect(pubSnap.data()!['displayName'], equals('Carlos'));
  });

  // TODO: SCENARIO-267 — submit failure leaves both docs unchanged.
  // Deferred: simulating a commit failure is not reliably reproducible
  // with fake_cloud_firestore. Covered by manual T35-style emulator session.

  // ──────────────────────────────────────────────────────────────────────────
  // QA-AUTH-001 (issue #434) — Terms consent gate for OAuth-new accounts.
  // ──────────────────────────────────────────────────────────────────────────
  group('QA-AUTH-001: terms consent gate', () {
    test(
        'OAuth new user (no profile yet) without accepting terms — submit '
        'throws, sets submitError, and writes nothing', () async {
      // Doc intencionalmente NO seedeado — userProfileProvider resuelve null,
      // igual que una cuenta OAuth recién creada por Google/Apple.
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);
      // termsAccepted se queda en su default (false) — checkbox sin marcar.

      await expectLater(
        notifier.submit(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'terms-not-accepted',
          ),
        ),
      );

      final state = container.read(profileSetupNotifierProvider);
      expect(state.submitError, isA<StateError>());
      expect(state.isSubmitting, isFalse);

      // Nada se escribió — el throw corta antes de createIfAbsent/update.
      final usersSnap = await firestore.collection('users').doc('u1').get();
      expect(usersSnap.exists, isFalse);
    });

    test(
        'OAuth new user with terms accepted — partial includes '
        'termsAcceptedAt', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);
      notifier.updateTermsAccepted(true);

      await notifier.submit();

      final usersSnap = await firestore.collection('users').doc('u1').get();
      expect(usersSnap.exists, isTrue);
      expect(usersSnap.data()!['termsAcceptedAt'], isNotNull);
    });

    // consentimiento-legal-versionado (R3): el mismo checkbox de OAuth
    // acepta las 2 versiones vigentes — el partial que estampa
    // termsAcceptedAt debe llevar también acceptedTermsVersion/
    // acceptedPrivacyVersion.
    test(
        'OAuth new user with terms accepted — partial also includes '
        'acceptedTermsVersion/acceptedPrivacyVersion', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);
      notifier.updateTermsAccepted(true);

      await notifier.submit();

      final usersSnap = await firestore.collection('users').doc('u1').get();
      expect(usersSnap.data()!['acceptedTermsVersion'], equals(kTermsVersion));
      expect(
        usersSnap.data()!['acceptedPrivacyVersion'],
        equals(kPrivacyVersion),
      );
    });

    test(
        'email flow (profile already exists) does not require the checkbox '
        'and does not overwrite the original termsAcceptedAt evidence',
        () async {
      final originalAcceptedAt = DateTime.utc(2026, 1, 1, 12);
      final now = DateTime.now().toUtc();
      await firestore.collection('users').doc('u1').set({
        'uid': 'u1',
        'email': 'test@test.com',
        'displayName': null,
        'role': 'athlete',
        'createdAt': now,
        'updatedAt': now,
        'termsAcceptedAt': Timestamp.fromDate(originalAcceptedAt),
      });
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);
      // termsAccepted se queda en false — un perfil existente NO exige el
      // checkbox (ya aceptó en Register).

      await notifier.submit();

      final usersSnap = await firestore.collection('users').doc('u1').get();
      final stored = usersSnap.data()!['termsAcceptedAt'] as Timestamp;
      // Timestamp.toDate() returns a LOCAL DateTime — .toUtc() normalizes it
      // before comparing against the UTC fixture (mirrors TimestampConverter).
      expect(stored.toDate().toUtc(), equals(originalAcceptedAt));
    });

    // EL caso del bug. Así nace el doc de un alta con Google/Apple cuando el
    // create del login anda: existe y no tiene `termsAcceptedAt`. Con la regla
    // anterior («perfil existente = ya consintió») este submit pasaba sin el
    // checkbox y la cuenta quedaba sin consentimiento. En producción, 2 de las
    // 5 altas OAuth del 16 al 22/09.
    test(
        'OAuth con doc creado en el login (sin termsAcceptedAt) y sin marcar '
        'el checkbox — submit tira terms-not-accepted y no escribe', () async {
      await seedUserDoc('u1', conConsentimiento: false);
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);

      await expectLater(
        notifier.submit(),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', 'terms-not-accepted'),
        ),
      );

      final usersSnap = await firestore.collection('users').doc('u1').get();
      expect(usersSnap.data()!['displayName'], isNull);
      expect(usersSnap.data()!['termsAcceptedAt'], isNull);
    });

    test(
        'OAuth con doc creado en el login y con el checkbox — estampa '
        'termsAcceptedAt y las dos versiones', () async {
      await seedUserDoc('u1', conConsentimiento: false);
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);
      notifier.updateTermsAccepted(true);

      await notifier.submit();

      final data =
          (await firestore.collection('users').doc('u1').get()).data()!;
      expect(data['termsAcceptedAt'], isNotNull);
      expect(data['acceptedTermsVersion'], equals(kTermsVersion));
      expect(data['acceptedPrivacyVersion'], equals(kPrivacyVersion));
    });

    // «No sé» no se trata como «hace falta» ni como «no hace falta»: se le
    // pregunta al servidor. Leerlo como «hace falta» le pisaría a esta cuenta
    // de email la evidencia original con un timestamp de hoy.
    test(
        'perfil sin cargar + cuenta de email — resuelve contra el servidor: '
        'no exige el checkbox ni pisa la evidencia', () async {
      await seedUserDoc('u1');
      final container = makeContainer(perfilObservado: nuncaEmite);
      addTearDown(container.dispose);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);

      await notifier.submit();

      final data =
          (await firestore.collection('users').doc('u1').get()).data()!;
      expect(data['displayName'], equals('Carlos'));
      expect(
        (data['termsAcceptedAt'] as Timestamp).toDate().toUtc(),
        equals(DateTime.utc(2026, 1, 1, 12)),
      );
    });

    // Hallazgo de Codex en #1228. Lo que la app observa (la caché local) es
    // una versión vieja del doc SIN `termsAcceptedAt`, pero el servidor sí lo
    // tiene. La pantalla muestra el checkbox y la persona lo tilda: estampar
    // sobre lo observado pisaría la evidencia original con la de hoy.
    test(
        'la caché dice que falta el consentimiento pero el servidor lo tiene '
        '— no se pisa la evidencia', () async {
      await seedUserDoc('u1');
      final container = makeContainer(
        perfilObservado: () => Stream.value(
          UserProfile(
            uid: 'u1',
            email: 'test@test.com',
            displayName: null,
            role: UserRole.athlete,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
      );
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);
      notifier.updateTermsAccepted(true);

      await notifier.submit();

      final data =
          (await firestore.collection('users').doc('u1').get()).data()!;
      expect(data['displayName'], equals('Carlos'));
      expect(
        (data['termsAcceptedAt'] as Timestamp).toDate().toUtc(),
        equals(DateTime.utc(2026, 1, 1, 12)),
      );
      expect(data.containsKey('acceptedTermsVersion'), isFalse);
    });

    test(
        'perfil sin cargar + cuenta sin consentimiento — resuelve contra el '
        'servidor y exige el checkbox', () async {
      await seedUserDoc('u1', conConsentimiento: false);
      final container = makeContainer(perfilObservado: nuncaEmite);
      addTearDown(container.dispose);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);

      await expectLater(
        notifier.submit(),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', 'terms-not-accepted'),
        ),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // QA-PRO-106 (issue #430): avatar upload failure must not be silent
  // ──────────────────────────────────────────────────────────────────────────

  group('QA-PRO-106: avatar upload failure surfaces via avatarUploadFailed',
      () {
    test(
        'FirebaseException during upload: profile persists without avatar, '
        'submit does not throw, flag is set', () async {
      await seedUserDoc('u1');
      final avatar = _FakeAvatarUploadService(
        error: FirebaseException(plugin: 'firebase_storage', code: 'unknown'),
      );
      final container = makeContainer(avatarService: avatar);
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);
      notifier.updateAvatarLocalPath('/tmp/pic.jpg');

      await notifier.submit(); // must NOT throw — best-effort policy stands

      final state = container.read(profileSetupNotifierProvider);
      expect(state.avatarUploadFailed, isTrue,
          reason: 'The lost avatar must be reported, not swallowed');
      expect(state.submitError, isNull);

      final usersSnap = await firestore.collection('users').doc('u1').get();
      expect(usersSnap.data()!['displayName'], equals('Carlos'),
          reason: 'Profile still persists — only the photo failed');
      expect(usersSnap.data()!.containsKey('avatarUrl'), isFalse);
    });

    test('generic error during upload: same contract as FirebaseException',
        () async {
      await seedUserDoc('u1');
      final avatar = _FakeAvatarUploadService(error: StateError('disk full'));
      final container = makeContainer(avatarService: avatar);
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);
      notifier.updateAvatarLocalPath('/tmp/pic.jpg');

      await notifier.submit();

      expect(container.read(profileSetupNotifierProvider).avatarUploadFailed,
          isTrue);
    });

    test('successful upload keeps the flag off and persists avatarUrl',
        () async {
      await seedUserDoc('u1');
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);
      notifier.updateAvatarLocalPath('/tmp/pic.jpg');

      await notifier.submit();

      expect(container.read(profileSetupNotifierProvider).avatarUploadFailed,
          isFalse);
      final usersSnap = await firestore.collection('users').doc('u1').get();
      expect(usersSnap.data()!['avatarUrl'],
          equals('https://fake.url/avatar.jpg'));
    });

    test('retry resets the flag: failed submit then successful one', () async {
      await seedUserDoc('u1');
      final avatar = _FakeAvatarUploadService(
        error: FirebaseException(plugin: 'firebase_storage', code: 'unknown'),
      );
      final container = makeContainer(avatarService: avatar);
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);
      notifier.updateAvatarLocalPath('/tmp/pic.jpg');

      await notifier.submit();
      expect(container.read(profileSetupNotifierProvider).avatarUploadFailed,
          isTrue);

      avatar.error = null; // the network came back
      await notifier.submit();

      expect(container.read(profileSetupNotifierProvider).avatarUploadFailed,
          isFalse,
          reason: 'A retry that uploads fine must clear the previous failure');
      final usersSnap = await firestore.collection('users').doc('u1').get();
      expect(usersSnap.data()!['avatarUrl'],
          equals('https://fake.url/avatar.jpg'));
    });
  });
  // ──────────────────────────────────────────────────────────────────────────
  // Gate de edad mínima en el submit
  //
  // El validador del paso 2 corre cuando el usuario elige la fecha, pero el
  // draft se puede editar volviendo atrás con VOLVER. Esta es la red de
  // seguridad, igual que la revalidación de unicidad del username.
  // ──────────────────────────────────────────────────────────────────────────
  group('gate de edad mínima en submit', () {
    test('un menor de la edad mínima no se persiste y submit tira', () async {
      await seedUserDoc('u1');
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      // ~10 años, relativo a hoy para que el test no envejezca.
      notifier.updateBornAt(DateTime.utc(DateTime.now().year - 10, 1, 1));

      await expectLater(notifier.submit(), throwsStateError);

      final usersSnap = await firestore.collection('users').doc('u1').get();
      expect(usersSnap.data()!['displayName'], isNull,
          reason: 'un submit rechazado no debe escribir NADA del perfil');
      expect(container.read(profileSetupNotifierProvider).isSubmitting, isFalse,
          reason: 'el spinner tiene que cortarse, no quedar colgado');
    });

    test('sin fecha tampoco persiste — el campo es obligatorio', () async {
      await seedUserDoc('u1');
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos'); // sin updateBornAt a propósito

      await expectLater(notifier.submit(), throwsStateError);

      final usersSnap = await firestore.collection('users').doc('u1').get();
      expect(usersSnap.data()!['displayName'], isNull);
    });

    test('una fecha válida sí se persiste en users/{uid}', () async {
      await seedUserDoc('u1');
      final container = makeContainer();
      addTearDown(container.dispose);
      await primeUserProfile(container);

      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateUsername('Carlos');
      notifier.updateBornAt(_adultBornAt);

      await notifier.submit();

      final stored = (await firestore.collection('users').doc('u1').get())
          .data()!['bornAt'];
      final storedDate =
          stored is Timestamp ? stored.toDate() : stored as DateTime;
      expect(storedDate.toUtc(), equals(_adultBornAt));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // El alta es de UNA cuenta: el estado no sobrevive al cambio de cuenta.
  //
  // Hallazgo de la revisión del cambio de Términos: el provider es de raíz y
  // «Cancelar cuenta» / «Cerrar sesión» no lo reiniciaban. La cuenta siguiente
  // en la misma sesión de la app heredaba el checkbox tildado, y su EMPEZAR
  // estampaba un consentimiento que nunca dio. Los tests del grupo de arriba
  // no podían verlo: cada uno arma un contenedor nuevo.
  // ──────────────────────────────────────────────────────────────────────────
  group('el alta es de UNA cuenta', () {
    late StreamController<User?> auth;
    late ProviderContainer container;

    User usuario(String uid) {
      final u = _MockUser();
      when(() => u.uid).thenReturn(uid);
      return u;
    }

    setUp(() {
      auth = StreamController<User?>();
      container = ProviderContainer(overrides: [
        authStateChangesProvider.overrideWith((ref) => auth.stream),
      ]);
      // Vivo durante todo el test, como lo mantiene la pantalla del alta.
      container.listen(profileSetupNotifierProvider, (_, __) {});
    });

    tearDown(() async {
      container.dispose();
      await auth.close();
    });

    Future<void> tildaLosTerminos(User cuenta) async {
      auth.add(cuenta);
      await pumpEventQueue();
      final notifier = container.read(profileSetupNotifierProvider.notifier);
      notifier.updateBornAt(_adultBornAt);
      notifier.updateTermsAccepted(true);
      expect(
          container.read(profileSetupNotifierProvider).termsAccepted, isTrue);
    }

    test(
        'cancelar la cuenta o cerrar sesión reinicia el checkbox y el borrador',
        () async {
      await tildaLosTerminos(usuario('cuenta-a'));

      auth.add(null); // cancelOnboarding / signOut
      await pumpEventQueue();

      final estado = container.read(profileSetupNotifierProvider);
      expect(estado.termsAccepted, isFalse);
      expect(estado.draft.bornAt, isNull);
      expect(estado.currentStep, 0);
    });

    test('la cuenta siguiente NO hereda el tilde de la anterior', () async {
      await tildaLosTerminos(usuario('cuenta-a'));

      auth.add(usuario('cuenta-b'));
      await pumpEventQueue();

      expect(
          container.read(profileSetupNotifierProvider).termsAccepted, isFalse);
    });

    // Control: la escucha es por uid y no por evento. Firebase re-emite al
    // usuario al refrescar el token; si eso reiniciara el alta, se perdería el
    // borrador en el medio del onboarding.
    test('el mismo uid re-emitido (refresh del token) NO reinicia el alta',
        () async {
      await tildaLosTerminos(usuario('cuenta-a'));

      auth.add(usuario('cuenta-a'));
      await pumpEventQueue();

      final estado = container.read(profileSetupNotifierProvider);
      expect(estado.termsAccepted, isTrue);
      expect(estado.draft.bornAt, equals(_adultBornAt));
    });
  });
}

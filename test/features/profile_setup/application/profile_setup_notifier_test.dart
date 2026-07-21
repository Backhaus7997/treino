import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart'
    show firebaseAuthProvider;
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider, userProfileProvider, userRepositoryProvider;
import 'package:treino/features/profile/data/user_repository.dart';
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
  Future<void> seedUserDoc(String uid) async {
    final now = DateTime.now().toUtc();
    await firestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'test@test.com',
      'displayName': null,
      'role': 'athlete',
      'createdAt': now,
      'updatedAt': now,
    });
  }

  ProviderContainer makeContainer({AvatarUploadService? avatarService}) {
    return ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(firestore),
      userRepositoryProvider.overrideWithValue(
        UserRepository(firestore: firestore),
      ),
      firebaseAuthProvider.overrideWithValue(mockAuth),
      avatarUploadServiceProvider
          .overrideWithValue(avatarService ?? _FakeAvatarUploadService()),
      // QA-AUTH-001 (issue #434): submit() now reads userProfileProvider to
      // decide whether Terms consent is required. Route it through the same
      // fake-firestore-backed repo used everywhere else in this file —
      // mirrors production (userProfileProvider watches repo.watch(uid))
      // instead of wiring the real authStateChanges() stream chain.
      userProfileProvider.overrideWith(
        (ref) => ref.watch(userRepositoryProvider).watch('u1'),
      ),
    ]);
  }

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
      notifier.updateTermsAccepted(true);

      await notifier.submit();

      final usersSnap = await firestore.collection('users').doc('u1').get();
      expect(usersSnap.exists, isTrue);
      expect(usersSnap.data()!['termsAcceptedAt'], isNotNull);
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
      // termsAccepted se queda en false — un perfil existente NO exige el
      // checkbox (ya aceptó en Register).

      await notifier.submit();

      final usersSnap = await firestore.collection('users').doc('u1').get();
      final stored = usersSnap.data()!['termsAcceptedAt'] as Timestamp;
      // Timestamp.toDate() returns a LOCAL DateTime — .toUtc() normalizes it
      // before comparing against the UTC fixture (mirrors TimestampConverter).
      expect(stored.toDate().toUtc(), equals(originalAcceptedAt));
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
}

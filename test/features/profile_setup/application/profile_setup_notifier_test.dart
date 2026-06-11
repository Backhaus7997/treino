import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart'
    show firebaseAuthProvider;
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider, userRepositoryProvider;
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/data/avatar_upload_service.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _FakeAvatarUploadService implements AvatarUploadService {
  @override
  Future<String> upload(String localPath) async =>
      'https://fake.url/avatar.jpg';
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

  ProviderContainer makeContainer() {
    return ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(firestore),
      userRepositoryProvider.overrideWithValue(
        UserRepository(firestore: firestore),
      ),
      firebaseAuthProvider.overrideWithValue(mockAuth),
      avatarUploadServiceProvider.overrideWithValue(_FakeAvatarUploadService()),
    ]);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-265: submit writes both users and userPublicProfiles
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-265: submit writes both users and userPublicProfiles',
      () async {
    await seedUserDoc('u1');
    final container = makeContainer();
    addTearDown(container.dispose);

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

    final notifier = container.read(profileSetupNotifierProvider.notifier);
    notifier.updateUsername('Carlos');

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

    expect(pubSnap.exists, isTrue);
    expect(pubSnap.data()!['uid'], equals('u1'));
    expect(pubSnap.data()!['displayName'], equals('Carlos'));
  });

  // TODO: SCENARIO-267 — submit failure leaves both docs unchanged.
  // Deferred: simulating a commit failure is not reliably reproducible
  // with fake_cloud_firestore. Covered by manual T35-style emulator session.
}

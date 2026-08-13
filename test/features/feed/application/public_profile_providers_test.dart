import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/public_profile_providers.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfileRepositoryProvider;
import 'package:treino/features/profile/data/user_public_profile_repository.dart';

class _MockUser extends Mock implements User {}

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

/// Siembra una arista dirigida en `follows`. El doc id NO se ordena.
Future<void> _seedEdge(
  FakeFirebaseFirestore firestore,
  String follower,
  String followee,
  FollowStatus status,
) async {
  final id = '${follower}_$followee';
  await firestore.collection('follows').doc(id).set({
    'id': id,
    'followerUid': follower,
    'followeeUid': followee,
    'status': status.toJson(),
    'members': [follower, followee],
    'createdAt': Timestamp.now(),
  });
}

void main() {
  // ────────────────────────────────────────────────────────────────────
  // firstPostByAuthorProvider
  // ────────────────────────────────────────────────────────────────────

  group('firstPostByAuthorProvider', () {
    test('SCENARIO-200: returns most recent post by authorUid', () async {
      final firestore = FakeFirebaseFirestore();
      // Older post
      await firestore.collection('posts').doc('p_old').set({
        'id': 'p_old',
        'authorUid': 'target',
        'authorDisplayName': 'Old Name',
        'authorAvatarUrl': null,
        'authorGymId': null,
        'text': 'Old',
        'routineTag': null,
        'privacy': PostPrivacy.public.toJson(),
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });
      // Newer post (has the latest fields)
      await firestore.collection('posts').doc('p_new').set({
        'id': 'p_new',
        'authorUid': 'target',
        'authorDisplayName': 'Tincho Latest',
        'authorAvatarUrl': 'https://avatar.com/x.jpg',
        'authorGymId': 'la-fuerza',
        'text': 'New',
        'routineTag': null,
        'privacy': PostPrivacy.public.toJson(),
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 1)),
      });

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(firstPostByAuthorProvider('target').future);

      expect(result, isNotNull);
      expect(result!.authorDisplayName, equals('Tincho Latest'));
      expect(result.authorGymId, equals('la-fuerza'));
    });

    test('SCENARIO-201: returns null when author has no posts', () async {
      final firestore = FakeFirebaseFirestore();

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(firstPostByAuthorProvider('no-posts').future);

      expect(result, isNull);
    });

    test('SCENARIO-202: returns null when unauthenticated', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('posts').doc('p1').set({
        'id': 'p1',
        'authorUid': 'target',
        'authorDisplayName': 'X',
        'authorAvatarUrl': null,
        'authorGymId': null,
        'text': 'x',
        'routineTag': null,
        'privacy': PostPrivacy.public.toJson(),
        'createdAt': Timestamp.now(),
      });

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(firstPostByAuthorProvider('target').future);
      expect(result, isNull);
    });

    test(
        'SCENARIO-202b: injects doc id for seed-written posts missing id in body',
        () async {
      final firestore = FakeFirebaseFirestore();
      // Seed-written doc: `id` is stored only as the doc ID, NOT in the body.
      await firestore.collection('posts').doc('seed_post_1').set({
        'authorUid': 'target',
        'authorDisplayName': 'Seeded',
        'authorAvatarUrl': null,
        'authorGymId': null,
        'text': 'seeded',
        'routineTag': null,
        'privacy': PostPrivacy.public.toJson(),
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
      });

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(firstPostByAuthorProvider('target').future);

      expect(result, isNotNull);
      expect(result!.id, equals('seed_post_1'));
      expect(result.authorDisplayName, equals('Seeded'));
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // publicProfileViewProvider
  // ────────────────────────────────────────────────────────────────────

  // ──────────────────────────────────────────────────────────────────────────
  // publicProfileViewProvider
  //
  // SCENARIO-203..205 fixtures now seed `userPublicProfiles` (NOT `posts`).
  // Assertions remain behaviorally equivalent per REQ-UPP-020 / SCENARIO-273.
  // ──────────────────────────────────────────────────────────────────────────
  group('publicProfileViewProvider', () {
    // SCENARIO-326d: publicProfileViewProvider passes counter fields through
    test(
        'SCENARIO-326d: publicProfileViewProvider sources 4 counter fields from userPublicProfile',
        () async {
      final firestore = FakeFirebaseFirestore();
      // Seed with counter fields
      await firestore.collection('userPublicProfiles').doc('target').set({
        'uid': 'target',
        'displayName': 'Ana',
        'displayNameLowercase': 'ana',
        'avatarUrl': null,
        'gymId': null,
        'workoutsCount': 89,
        'racha': 23,
        'followersCount': 412,
        'followingCount': 284,
      });

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        userPublicProfileRepositoryProvider.overrideWithValue(
          UserPublicProfileRepository(firestore: firestore),
        ),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final view =
          await container.read(publicProfileViewProvider('target').future);

      expect(view.workoutsCount, equals(89));
      expect(view.racha, equals(23));
      expect(view.followersCount, equals(412));
      expect(view.followingCount, equals(284));
    });

    // SCENARIO-326e: counter fields are null when userPublicProfile has no counters
    test(
        'SCENARIO-326e: counter fields are null when userPublicProfile has no counters',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('userPublicProfiles').doc('target').set({
        'uid': 'target',
        'displayName': 'Ana',
        'displayNameLowercase': 'ana',
        'avatarUrl': null,
        'gymId': null,
      });

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        userPublicProfileRepositoryProvider.overrideWithValue(
          UserPublicProfileRepository(firestore: firestore),
        ),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final view =
          await container.read(publicProfileViewProvider('target').future);

      expect(view.workoutsCount, isNull);
      expect(view.racha, isNull);
      expect(view.followersCount, isNull);
      expect(view.followingCount, isNull);
    });

    test(
        'SCENARIO-203: compone userPublicProfile + las DOS aristas; isSelf=false',
        () async {
      final firestore = FakeFirebaseFirestore();
      // Seed userPublicProfiles (NOT posts) — REQ-UPP-020
      await firestore.collection('userPublicProfiles').doc('target').set({
        'uid': 'target',
        'displayName': 'Tincho',
        'displayNameLowercase': 'tincho',
        'avatarUrl': 'https://x.com/y.jpg',
        'gymId': 'la-fuerza',
      });
      // Par mutuo: las DOS aristas.
      await _seedEdge(firestore, 'viewer', 'target', FollowStatus.accepted);
      await _seedEdge(firestore, 'target', 'viewer', FollowStatus.accepted);

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        userPublicProfileRepositoryProvider.overrideWithValue(
          UserPublicProfileRepository(firestore: firestore),
        ),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final view =
          await container.read(publicProfileViewProvider('target').future);

      expect(view.authorDisplayName, equals('Tincho'));
      expect(view.authorAvatarUrl, equals('https://x.com/y.jpg'));
      expect(view.authorGymId, equals('la-fuerza'));
      expect(view.outgoingFollow, isNotNull);
      expect(view.outgoingFollow!.status, equals(FollowStatus.accepted));
      expect(view.incomingFollow, isNotNull);
      expect(view.incomingFollow!.status, equals(FollowStatus.accepted));
      expect(view.isSelf, isFalse);
    });

    // SCENARIO-822 — LA PRUEBA DE QUE SON DOS LISTENERS Y NO UNO.
    //
    // Sólo existe la arista ENTRANTE: el del perfil sigue al que mira, pero no
    // al revés. Si el notifier compusiera un solo documento —como hacía con
    // `friendshipByPairProvider`— este caso saldría idéntico al mutuo, y el
    // perfil mostraría "SIGUIENDO" sobre alguien a quien no seguís.
    test('SCENARIO-822: sólo la arista entrante → outgoing null, incoming no',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('userPublicProfiles').doc('target').set({
        'uid': 'target',
        'displayName': 'Tincho',
        'displayNameLowercase': 'tincho',
        'avatarUrl': null,
        'gymId': null,
      });
      await _seedEdge(firestore, 'target', 'viewer', FollowStatus.accepted);

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        userPublicProfileRepositoryProvider.overrideWithValue(
          UserPublicProfileRepository(firestore: firestore),
        ),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final view =
          await container.read(publicProfileViewProvider('target').future);

      expect(view.outgoingFollow, isNull,
          reason: 'el viewer no sigue al target');
      expect(view.incomingFollow, isNotNull,
          reason: 'el target sí sigue al viewer');
    });

    // SCENARIO-822 — el espejo del anterior.
    test('SCENARIO-822: sólo la arista saliente → incoming null, outgoing no',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('userPublicProfiles').doc('target').set({
        'uid': 'target',
        'displayName': 'Tincho',
        'displayNameLowercase': 'tincho',
        'avatarUrl': null,
        'gymId': null,
      });
      await _seedEdge(firestore, 'viewer', 'target', FollowStatus.pending);

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        userPublicProfileRepositoryProvider.overrideWithValue(
          UserPublicProfileRepository(firestore: firestore),
        ),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final view =
          await container.read(publicProfileViewProvider('target').future);

      expect(view.outgoingFollow!.status, equals(FollowStatus.pending));
      expect(view.incomingFollow, isNull);
    });

    test(
        'SCENARIO-204: no userPublicProfile doc → authorDisplayName falls back to "Anónimo"',
        () async {
      final firestore = FakeFirebaseFirestore();
      // No doc seeded in userPublicProfiles for 'target'

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        userPublicProfileRepositoryProvider.overrideWithValue(
          UserPublicProfileRepository(firestore: firestore),
        ),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final view =
          await container.read(publicProfileViewProvider('target').future);

      expect(view.authorDisplayName, equals('Anónimo'));
      expect(view.authorAvatarUrl, isNull);
      expect(view.authorGymId, isNull);
      expect(view.outgoingFollow, isNull);
      expect(view.incomingFollow, isNull);
      expect(view.isSelf, isFalse);
    });

    test('SCENARIO-205: self-visit → isSelf=true y las dos aristas en null',
        () async {
      final firestore = FakeFirebaseFirestore();
      // Seed userPublicProfiles for self (NOT posts) — REQ-UPP-020
      await firestore.collection('userPublicProfiles').doc('me').set({
        'uid': 'me',
        'displayName': 'Yo',
        'displayNameLowercase': 'yo',
        'avatarUrl': null,
        'gymId': null,
      });

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        userPublicProfileRepositoryProvider.overrideWithValue(
          UserPublicProfileRepository(firestore: firestore),
        ),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('me'))),
      ]);
      addTearDown(container.dispose);

      final view = await container.read(publicProfileViewProvider('me').future);

      expect(view.isSelf, isTrue);
      expect(view.authorDisplayName, equals('Yo'));
      expect(view.outgoingFollow, isNull);
      expect(view.incomingFollow, isNull);
    });
  });
}

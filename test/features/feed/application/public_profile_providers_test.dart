import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/public_profile_providers.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
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

void main() {
  // ────────────────────────────────────────────────────────────────────
  // friendshipByPairProvider
  // ────────────────────────────────────────────────────────────────────

  group('friendshipByPairProvider', () {
    test('SCENARIO-197: returns existing friendship doc for the pair',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('friendships').doc('a_b').set({
        'id': 'a_b',
        'uidA': 'a',
        'uidB': 'b',
        'status': FriendshipStatus.accepted.toJson(),
        'requesterId': 'a',
        'members': ['a', 'b'],
        'createdAt': Timestamp.now(),
      });

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('a'))),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(
        friendshipByPairProvider(
          (viewerUid: 'a', targetUid: 'b'),
        ).future,
      );

      expect(result, isNotNull);
      expect(result!.status, equals(FriendshipStatus.accepted));
    });

    test('SCENARIO-198: returns null when no doc exists for the pair',
        () async {
      final firestore = FakeFirebaseFirestore();

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('a'))),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(
        friendshipByPairProvider(
          (viewerUid: 'a', targetUid: 'z'),
        ).future,
      );

      expect(result, isNull);
    });

    test('SCENARIO-199: returns null when unauthenticated', () async {
      final firestore = FakeFirebaseFirestore();

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(
        friendshipByPairProvider(
          (viewerUid: 'a', targetUid: 'b'),
        ).future,
      );

      expect(result, isNull);
    });
  });

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
    test('SCENARIO-203: composes userPublicProfile + friendship; isSelf=false',
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
      await firestore.collection('friendships').doc('target_viewer').set({
        'id': 'target_viewer',
        'uidA': 'target',
        'uidB': 'viewer',
        'status': FriendshipStatus.accepted.toJson(),
        'requesterId': 'viewer',
        'members': ['target', 'viewer'],
        'createdAt': Timestamp.now(),
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

      expect(view.authorDisplayName, equals('Tincho'));
      expect(view.authorAvatarUrl, equals('https://x.com/y.jpg'));
      expect(view.authorGymId, equals('la-fuerza'));
      expect(view.friendship, isNotNull);
      expect(view.friendship!.status, equals(FriendshipStatus.accepted));
      expect(view.isSelf, isFalse);
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
      expect(view.friendship, isNull);
      expect(view.isSelf, isFalse);
    });

    test('SCENARIO-205: self-visit → isSelf=true and friendship is null',
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
      expect(view.friendship, isNull);
    });
  });
}

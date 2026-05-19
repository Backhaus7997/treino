import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserPublicProfileRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserPublicProfileRepository(firestore: firestore);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-254: get returns null for missing doc
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-254: get returns null for missing doc', () async {
    final result = await repo.get('u99');
    expect(result, isNull);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-255: set + get round-trip
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-255: set then get returns the same profile', () async {
    const profile = UserPublicProfile(
      uid: 'u1',
      displayName: 'Ana',
      displayNameLowercase: 'ana',
      avatarUrl: null,
      gymId: 'g1',
    );

    await repo.set(profile);
    final result = await repo.get('u1');

    expect(result, isNotNull);
    expect(result!.uid, equals('u1'));
    expect(result.displayName, equals('Ana'));
    expect(result.displayNameLowercase, equals('ana'));
    expect(result.gymId, equals('g1'));
    expect(result.avatarUrl, isNull);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-256: searchByDisplayName prefix match
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-256: searchByDisplayName returns prefix matches', () async {
    await firestore.collection('userPublicProfiles').doc('a').set({
      'uid': 'a',
      'displayName': 'Martín',
      'displayNameLowercase': 'martín',
      'avatarUrl': null,
      'gymId': null,
    });
    await firestore.collection('userPublicProfiles').doc('b').set({
      'uid': 'b',
      'displayName': 'Marta',
      'displayNameLowercase': 'marta',
      'avatarUrl': null,
      'gymId': null,
    });
    await firestore.collection('userPublicProfiles').doc('c').set({
      'uid': 'c',
      'displayName': 'Carlos',
      'displayNameLowercase': 'carlos',
      'avatarUrl': null,
      'gymId': null,
    });

    final results = await repo.searchByDisplayName('mar');

    expect(results.length, equals(2));
    final uids = results.map((p) => p.uid).toSet();
    expect(uids, containsAll(['a', 'b']));
    expect(uids, isNot(contains('c')));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-257: searchByDisplayName respects 20-result limit
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-257: searchByDisplayName returns at most 20 results',
      () async {
    // Seed 25 docs whose displayNameLowercase starts with 'test'
    for (var i = 0; i < 25; i++) {
      await firestore.collection('userPublicProfiles').doc('test$i').set({
        'uid': 'test$i',
        'displayName': 'Test$i',
        'displayNameLowercase': 'test$i',
        'avatarUrl': null,
        'gymId': null,
      });
    }

    final results = await repo.searchByDisplayName('test');
    expect(results.length, equals(20));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-258: searchByDisplayName returns empty list for blank query
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-258: searchByDisplayName returns [] for blank/whitespace query',
      () async {
    // Seed a doc to ensure the repo doesn't hit Firestore
    await firestore.collection('userPublicProfiles').doc('u1').set({
      'uid': 'u1',
      'displayName': 'Ana',
      'displayNameLowercase': 'ana',
      'avatarUrl': null,
      'gymId': null,
    });

    final resultsBlank = await repo.searchByDisplayName('');
    expect(resultsBlank, isEmpty);

    final resultsWhitespace = await repo.searchByDisplayName('   ');
    expect(resultsWhitespace, isEmpty);
  });
}

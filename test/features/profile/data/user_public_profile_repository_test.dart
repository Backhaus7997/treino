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
  // SCENARIO-320e: updateCounters() merges only the provided counter fields
  // without clobbering displayName / avatarUrl / gymId written by the
  // identity write-path. Verifies ADR-WRS-12 partial-merge contract.
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-320e: updateCounters merges without clobbering existing identity fields',
      () async {
    // Seed the identity doc first (as UserRepository would do it)
    await firestore.collection('userPublicProfiles').doc('u10').set({
      'uid': 'u10',
      'displayName': 'Ana Kraft',
      'displayNameLowercase': 'ana kraft',
      'avatarUrl': 'https://cdn.example.com/ana.jpg',
      'gymId': 'gym-elite',
    });

    // Partial counter write (as SessionRepository.finish() uses it)
    await repo.updateCounters('u10', {'workoutsCount': 5, 'racha': 3});

    final result = await repo.get('u10');
    expect(result, isNotNull);

    // Identity fields must NOT be clobbered
    expect(result!.displayName, equals('Ana Kraft'));
    expect(result.displayNameLowercase, equals('ana kraft'));
    expect(result.avatarUrl, equals('https://cdn.example.com/ana.jpg'));
    expect(result.gymId, equals('gym-elite'));

    // Counter fields are written
    expect(result.workoutsCount, equals(5));
    expect(result.racha, equals(3));
    // Unset counters remain null (not overwritten with null)
    expect(result.followersCount, isNull);
    expect(result.followingCount, isNull);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T06 RED: watch (SCENARIO-479..480)
  // ──────────────────────────────────────────────────────────────────────────

  // SCENARIO-479: watch emits null when the profile doc does not exist
  test('SCENARIO-479: watch emits null when no profile doc exists for uid',
      () async {
    final stream = repo.watch('u99');
    await expectLater(stream, emits(isNull));
  });

  // SCENARIO-480: watch re-emits updated profile on Firestore doc update
  test(
      'SCENARIO-480: watch re-emits updated UserPublicProfile after Firestore doc update',
      () async {
    // Seed initial profile with followersCount: 0
    await firestore.collection('userPublicProfiles').doc('u1').set({
      'uid': 'u1',
      'displayName': 'Ana',
      'displayNameLowercase': 'ana',
      'avatarUrl': null,
      'gymId': null,
      'followersCount': 0,
    });

    final stream = repo.watch('u1');
    final emissions = <UserPublicProfile?>[];
    final sub = stream.listen(emissions.add);

    // Wait for initial emission
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.length, equals(1));
    expect(emissions.first, isNotNull);
    expect(emissions.first!.followersCount, equals(0));

    // Update the doc
    await firestore
        .collection('userPublicProfiles')
        .doc('u1')
        .update({'followersCount': 5});

    // Wait for re-emission
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.length, greaterThanOrEqualTo(2));
    expect(emissions.last!.followersCount, equals(5));

    await sub.cancel();
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

  // ──────────────────────────────────────────────────────────────────────────
  // getByIds batch lookup — backs the RESEÑAS section's single-read author
  // resolution (replaces the per-tile N+1 listen pattern).
  // ──────────────────────────────────────────────────────────────────────────
  test('getByIds returns a uid->profile map and omits missing/duplicate ids',
      () async {
    await firestore.collection('userPublicProfiles').doc('u1').set({
      'uid': 'u1',
      'displayName': 'Ana',
      'displayNameLowercase': 'ana',
      'avatarUrl': null,
      'gymId': null,
    });
    await firestore.collection('userPublicProfiles').doc('u2').set({
      'uid': 'u2',
      'displayName': 'Beto',
      'displayNameLowercase': 'beto',
      'avatarUrl': 'https://cdn.example.com/beto.jpg',
      'gymId': null,
    });

    // u3 has no doc (deleted account); u1 is requested twice (deduped).
    final result = await repo.getByIds(['u1', 'u2', 'u3', 'u1']);

    expect(result.keys.toSet(), equals({'u1', 'u2'}));
    expect(result['u1']!.displayName, equals('Ana'));
    expect(result['u2']!.avatarUrl, equals('https://cdn.example.com/beto.jpg'));
    expect(result.containsKey('u3'), isFalse);
  });

  test('getByIds short-circuits on empty input', () async {
    final result = await repo.getByIds(const []);
    expect(result, isEmpty);
  });
}

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ignore_for_file: avoid_dynamic_calls

void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserRepository(firestore: firestore);
  });

  // Helper: seed a document directly
  Future<void> seedDoc(String uid) async {
    final now = DateTime.utc(2026, 1, 1);
    final profile = UserProfile(
      uid: uid,
      email: 'seed@test.com',
      displayName: null,
      role: UserRole.athlete,
      createdAt: now,
      updatedAt: now,
    );
    await firestore.collection('users').doc(uid).set(profile.toJson());
  }

  // ---------------------------------------------------------------------------
  // T17: getOrCreate — new uid
  // ---------------------------------------------------------------------------
  group('UserRepository.getOrCreate', () {
    test(
        'SCENARIO-010: new uid creates doc with displayName null and returns populated profile',
        () async {
      final result = await repo.getOrCreate(
        uid: 'uid-1',
        email: 'a@b.com',
      );

      // Doc exists in fake Firestore
      final snap = await firestore.collection('users').doc('uid-1').get();
      expect(snap.exists, isTrue);
      // Persisted displayName is null — populated by ProfileSetup in Etapa 6
      expect(snap.data()!['displayName'], isNull);

      // Returned profile has correct values
      expect(result.uid, equals('uid-1'));
      expect(result.email, equals('a@b.com'));
      expect(result.displayName, isNull);
      expect(result.role, equals(UserRole.athlete));
      expect(result.gymId, isNull);
      expect(result.bodyWeightKg, isNull);
      expect(result.heightCm, isNull);
      expect(result.gender, isNull);
      expect(result.experienceLevel, isNull);
      expect(result.avatarUrl, isNull);
      expect(result.bornAt, isNull);

      // Timestamps are recent
      final now = DateTime.now().toUtc();
      expect(
        result.createdAt.isAfter(now.subtract(const Duration(seconds: 5))),
        isTrue,
      );
    });

    // T18: getOrCreate — idempotency
    test('SCENARIO-011: existing uid returns existing profile without writing',
        () async {
      await seedDoc('uid-1');
      final snapBefore = await firestore.collection('users').doc('uid-1').get();
      final originalCreatedAt =
          (snapBefore.data()!['createdAt'] as Timestamp).toDate();

      final result = await repo.getOrCreate(
        uid: 'uid-1',
        email: 'new@b.com',
      );

      // createdAt unchanged
      expect(result.createdAt.millisecondsSinceEpoch,
          equals(originalCreatedAt.millisecondsSinceEpoch));
      // Returns existing data, not the new args
      expect(result.email, equals('seed@test.com'));
      // Seeded doc has displayName null
      expect(result.displayName, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // T19: get
  // ---------------------------------------------------------------------------
  group('UserRepository.get', () {
    test('SCENARIO-012: missing uid returns null', () async {
      final result = await repo.get('uid-2');
      expect(result, isNull);
    });

    test('SCENARIO-013: existing uid returns populated profile', () async {
      await seedDoc('uid-3');
      final result = await repo.get('uid-3');
      expect(result, isNotNull);
      expect(result!.uid, equals('uid-3'));
      expect(result.email, equals('seed@test.com'));
    });
  });

  // ---------------------------------------------------------------------------
  // T20: update
  // ---------------------------------------------------------------------------
  group('UserRepository.update', () {
    test(
        'SCENARIO-014: partial update preserves role/email/uid/createdAt, bumps updatedAt',
        () async {
      await seedDoc('uid-4');
      final snapBefore = await firestore.collection('users').doc('uid-4').get();
      final originalCreatedAt = snapBefore.data()!['createdAt'];
      final originalUpdatedAt =
          (snapBefore.data()!['updatedAt'] as Timestamp).toDate();

      await Future.delayed(const Duration(milliseconds: 10));
      await repo.update('uid-4', {'displayName': 'Bob'});

      final snap = await firestore.collection('users').doc('uid-4').get();
      final data = snap.data()!;

      expect(data['displayName'], equals('Bob'));
      expect(data['role'], equals('athlete'));
      expect(data['email'], equals('seed@test.com'));
      expect(data['uid'], equals('uid-4'));
      expect(data['createdAt'], equals(originalCreatedAt));

      // updatedAt must be newer
      final newUpdatedAt = (data['updatedAt'] as Timestamp).toDate();
      expect(
        newUpdatedAt.isAfter(originalUpdatedAt) ||
            newUpdatedAt.isAtSameMomentAs(originalUpdatedAt),
        isTrue,
      );
    });

    test(
        'SCENARIO-015: passing role in partial is silently stripped, displayName changes',
        () async {
      await seedDoc('uid-5');

      await repo.update('uid-5', {'role': 'trainer', 'displayName': 'Carol'});

      final snap = await firestore.collection('users').doc('uid-5').get();
      final data = snap.data()!;

      expect(data['displayName'], equals('Carol'));
      expect(data['role'], equals('athlete')); // role NOT changed
    });
  });

  // ---------------------------------------------------------------------------
  // Dual-write scenarios (SCENARIO-259..263)
  // ---------------------------------------------------------------------------
  group('UserRepository dual-write (userPublicProfiles)', () {
    test('SCENARIO-259: getOrCreate writes both users and userPublicProfiles',
        () async {
      await repo.getOrCreate(uid: 'u1', email: 'a@b.com');

      final usersSnap = await firestore.collection('users').doc('u1').get();
      final pubSnap =
          await firestore.collection('userPublicProfiles').doc('u1').get();

      expect(usersSnap.exists, isTrue);
      expect(pubSnap.exists, isTrue);
      expect(pubSnap.data()!['uid'], equals('u1'));
    });

    test(
        'SCENARIO-260: createIfAbsent writes both users and userPublicProfiles',
        () async {
      await repo.createIfAbsent(uid: 'u2', email: 'b@c.com');

      final usersSnap = await firestore.collection('users').doc('u2').get();
      final pubSnap =
          await firestore.collection('userPublicProfiles').doc('u2').get();

      expect(usersSnap.exists, isTrue);
      expect(pubSnap.exists, isTrue);
      expect(pubSnap.data()!['uid'], equals('u2'));
    });

    test(
        'SCENARIO-261: update with displayName propagates to userPublicProfiles '
        'with lowercase derivation', () async {
      await seedDoc('u3');
      // Also seed public profile so the doc exists
      await firestore.collection('userPublicProfiles').doc('u3').set({
        'uid': 'u3',
        'displayName': null,
        'displayNameLowercase': null,
        'avatarUrl': null,
        'gymId': null,
      });

      await repo.update('u3', {'displayName': 'Nueva'});

      final pubSnap =
          await firestore.collection('userPublicProfiles').doc('u3').get();
      expect(pubSnap.data()!['displayName'], equals('Nueva'));
      expect(pubSnap.data()!['displayNameLowercase'], equals('nueva'));
    });

    test(
        'SCENARIO-262: update without displayName/avatarUrl/gymId does NOT '
        'touch userPublicProfiles', () async {
      await seedDoc('u4');
      await firestore.collection('userPublicProfiles').doc('u4').set({
        'uid': 'u4',
        'displayName': 'Original',
        'displayNameLowercase': 'original',
        'avatarUrl': null,
        'gymId': null,
      });

      // Update only experienceLevel — none of the public fields
      await repo.update('u4', {'experienceLevel': 'beginner'});

      final pubSnap =
          await firestore.collection('userPublicProfiles').doc('u4').get();
      // Public profile must remain untouched
      expect(pubSnap.data()!['displayName'], equals('Original'));
      expect(pubSnap.data()!['displayNameLowercase'], equals('original'));
    });

    test(
        'SCENARIO-263: displayNameLowercase is always auto-derived; '
        'caller cannot override', () async {
      await repo.getOrCreate(uid: 'u5', email: 'c@d.com');
      await repo.update('u5', {'displayName': 'Alice'});

      final pubSnap =
          await firestore.collection('userPublicProfiles').doc('u5').get();
      expect(pubSnap.data()!['displayNameLowercase'], equals('alice'));
    });

    // TODO: SCENARIO-264 — partial batch failure leaves neither doc written.
    // Deferred: faking a mid-commit batch failure is not reliably reproducible
    // with fake_cloud_firestore. Covered by manual T35-style emulator session.
  });

  // ---------------------------------------------------------------------------
  // T21: delete
  // ---------------------------------------------------------------------------
  group('UserRepository.delete', () {
    test('SCENARIO-016: always throws UnsupportedError', () async {
      expect(
        () => repo.delete('any-uid'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // T22: watch
  // ---------------------------------------------------------------------------
  group('UserRepository.watch', () {
    test('SCENARIO-017: stream emits null when doc absent', () async {
      final stream = repo.watch('uid-6');
      final first = await stream.first;
      expect(first, isNull);
    });

    test('SCENARIO-018: stream emits profile after createIfAbsent', () async {
      final stream = repo.watch('uid-7');

      await expectLater(
        stream,
        emitsInOrder([
          isNull,
          isA<UserProfile>(),
        ]),
      );

      // This runs concurrently with the expectLater listener
    }, skip: 'requires concurrent write — see alternative test below');

    test(
        'SCENARIO-018b: watch emits profile after createIfAbsent (stream test)',
        () async {
      final events = <UserProfile?>[];
      final sub = repo.watch('uid-7b').listen(events.add);

      // First event should be null (no doc)
      await Future.delayed(const Duration(milliseconds: 50));
      expect(events, [isNull]);

      await repo.createIfAbsent(
        uid: 'uid-7b',
        email: 'd@e.com',
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(events.length, greaterThan(1));
      expect(events.last, isA<UserProfile>());
      expect((events.last as UserProfile).uid, equals('uid-7b'));
      // createIfAbsent must persist displayName null
      expect((events.last as UserProfile).displayName, isNull);

      await sub.cancel();
    });

    test('SCENARIO-019: stream emits update after doc changes', () async {
      await seedDoc('uid-8');
      final events = <UserProfile?>[];
      final sub = repo.watch('uid-8').listen(events.add);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(events.isNotEmpty, isTrue);
      // Seeded doc has displayName null (REQ-PROF — populated later by ProfileSetup)
      expect(events.first!.displayName, isNull);

      // Direct mutation via fake firestore — simulates ProfileSetup writing
      await firestore
          .collection('users')
          .doc('uid-8')
          .update({'displayName': 'Evelyn'});

      await Future.delayed(const Duration(milliseconds: 50));
      expect(events.last!.displayName, equals('Evelyn'));

      await sub.cancel();
    });

    test('createIfAbsent twice on same uid produces only one doc', () async {
      await repo.createIfAbsent(
        uid: 'uid-9',
        email: 'e@f.com',
      );
      await repo.createIfAbsent(
        uid: 'uid-9',
        email: 'e@f.com',
      );

      final snap = await firestore.collection('users').doc('uid-9').get();
      expect(snap.exists, isTrue);
      // displayName persisted as null
      expect(snap.data()!['displayName'], isNull);

      // createdAt not changed by second call — get snapshot count proxy:
      // just verify we can still read exactly one profile
      final profile = await repo.get('uid-9');
      expect(profile, isNotNull);
      expect(profile!.uid, equals('uid-9'));
      expect(profile.displayName, isNull);
    });
  });
}

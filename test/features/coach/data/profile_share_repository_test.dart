import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/profile_share_repository.dart';
import 'package:treino/features/coach/domain/profile_share.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/gender.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ProfileShareRepository repo;

  const athleteId = 'athlete-001';
  const trainerId = 'trainer-001';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ProfileShareRepository(firestore: firestore);
  });

  group('ProfileShareRepository.grant', () {
    test('writes trainerId + snapshot fields to profile_shares/{athleteId}',
        () async {
      final bornAt = DateTime.utc(1995, 6, 20);
      final updatedAt = DateTime.utc(2026, 7, 6);

      await repo.grant(
        athleteId: athleteId,
        trainerId: trainerId,
        phone: '+54 9 11 1234-5678',
        bornAt: bornAt,
        heightCm: 170,
        bodyWeightKg: 65.5,
        gender: Gender.female,
        experienceLevel: ExperienceLevel.intermediate,
        updatedAt: updatedAt,
      );

      final snap =
          await firestore.collection('profile_shares').doc(athleteId).get();

      expect(snap.exists, isTrue);
      final data = snap.data()!;
      expect(data['trainerId'], trainerId);
      expect(data['phone'], '+54 9 11 1234-5678');
      expect(data['heightCm'], 170);
      expect(data['bodyWeightKg'], 65.5);
      expect(data['gender'], 'female');
      expect(data['experienceLevel'], 'intermediate');
    });

    test('grant with null fields writes only trainerId + updatedAt', () async {
      final updatedAt = DateTime.utc(2026, 7, 6);

      await repo.grant(
        athleteId: athleteId,
        trainerId: trainerId,
        updatedAt: updatedAt,
      );

      final snap =
          await firestore.collection('profile_shares').doc(athleteId).get();

      expect(snap.exists, isTrue);
      final data = snap.data()!;
      expect(data['trainerId'], trainerId);
      expect(data.containsKey('phone'), isFalse);
      expect(data.containsKey('heightCm'), isFalse);
    });

    test('grant replaces existing doc (re-grant snapshot refresh)', () async {
      // First grant
      await repo.grant(
        athleteId: athleteId,
        trainerId: trainerId,
        heightCm: 170,
        updatedAt: DateTime.utc(2026, 7, 1),
      );

      // Second grant — new height + new updatedAt
      final newUpdatedAt = DateTime.utc(2026, 7, 6);
      await repo.grant(
        athleteId: athleteId,
        trainerId: trainerId,
        heightCm: 175,
        updatedAt: newUpdatedAt,
      );

      final snap =
          await firestore.collection('profile_shares').doc(athleteId).get();
      final data = snap.data()!;
      expect(data['heightCm'], 175);
    });
  });

  group('ProfileShareRepository.revoke', () {
    test('deletes the doc when it exists', () async {
      // Seed the doc first
      await firestore.collection('profile_shares').doc(athleteId).set({
        'trainerId': trainerId,
      });

      await repo.revoke(athleteId);

      final snap =
          await firestore.collection('profile_shares').doc(athleteId).get();
      expect(snap.exists, isFalse);
    });

    test('revoke on non-existent doc does not throw', () async {
      // Should not throw even when doc is already absent
      await expectLater(repo.revoke(athleteId), completes);
    });
  });

  group('ProfileShareRepository.watchForAthlete', () {
    test('emits null when doc does not exist', () async {
      final stream = repo.watchForAthlete(athleteId);
      expect(await stream.first, isNull);
    });

    test('emits ProfileShare when doc exists with all fields', () async {
      final bornAt = DateTime.utc(1995, 6, 20);
      final updatedAt = DateTime.utc(2026, 7, 1);

      await firestore.collection('profile_shares').doc(athleteId).set({
        'trainerId': trainerId,
        'phone': '+54 9 11 9876-5432',
        'bornAt': Timestamp.fromDate(bornAt),
        'heightCm': 170,
        'bodyWeightKg': 65.0,
        'gender': 'female',
        'experienceLevel': 'beginner',
        'updatedAt': Timestamp.fromDate(updatedAt),
      });

      final share = await repo.watchForAthlete(athleteId).first;

      expect(share, isNotNull);
      expect(share!.trainerId, trainerId);
      expect(share.phone, '+54 9 11 9876-5432');
      expect(share.bornAt, bornAt);
      expect(share.heightCm, 170);
      expect(share.bodyWeightKg, 65.0);
      expect(share.gender, Gender.female);
      expect(share.experienceLevel, ExperienceLevel.beginner);
      expect(share.updatedAt, updatedAt);
    });

    test('emits null then ProfileShare after doc is created', () async {
      // Collect first 2 emissions via take(2).toList() — note that
      // FakeFirebaseFirestore replays the current state synchronously for each
      // new listener, so we set up the stream first (null emission), then write
      // the doc and let the stream re-emit the updated state.
      final emissions = <ProfileShare?>[];
      final sub = repo.watchForAthlete(athleteId).listen(emissions.add);

      // First emission: doc doesn't exist yet → null
      await Future<void>.delayed(Duration.zero);
      expect(emissions, [null]);

      // Write the doc
      await firestore.collection('profile_shares').doc(athleteId).set({
        'trainerId': trainerId,
      });
      await Future<void>.delayed(Duration.zero);

      expect(emissions.length, 2);
      expect(emissions[1], isNotNull);
      expect(emissions[1]!.trainerId, trainerId);

      await sub.cancel();
    });

    test('emits ProfileShare with only trainerId (minimal doc)', () async {
      await firestore.collection('profile_shares').doc(athleteId).set({
        'trainerId': trainerId,
      });

      final share = await repo.watchForAthlete(athleteId).first;

      expect(share, isNotNull);
      expect(share!.trainerId, trainerId);
      expect(share.phone, isNull);
      expect(share.heightCm, isNull);
      expect(share.bodyWeightKg, isNull);
      expect(share.gender, isNull);
      expect(share.experienceLevel, isNull);
    });

    test('returns null for unparseable doc without throwing', () async {
      // Write a doc with an invalid gender wire value — fromJson will throw
      // and the repository should catch + return null (same pattern as
      // AthleteNoteRepository).
      await firestore.collection('profile_shares').doc(athleteId).set({
        'trainerId': trainerId,
        'gender': 'INVALID_VALUE',
      });

      final share = await repo.watchForAthlete(athleteId).first;
      expect(share, isNull);
    });
  });
}

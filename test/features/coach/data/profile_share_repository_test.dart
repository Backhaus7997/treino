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

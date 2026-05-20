import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/trainer_public_profile_repository.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';

// ignore_for_file: avoid_dynamic_calls

void main() {
  late FakeFirebaseFirestore firestore;
  late TrainerPublicProfileRepository repo;

  // Helper: seed a trainer doc directly into Firestore.
  Future<void> seedTrainer({
    required String uid,
    required String displayName,
    String? trainerGeohash,
    TrainerSpecialty? specialty,
    int? hourlyRate,
  }) async {
    final doc = TrainerPublicProfile(
      uid: uid,
      displayName: displayName,
      displayNameLowercase: displayName.trim().toLowerCase(),
      trainerGeohash: trainerGeohash,
      trainerSpecialty: specialty,
      trainerMonthlyRate: hourlyRate,
    );
    await firestore
        .collection('trainerPublicProfiles')
        .doc(uid)
        .set(doc.toJson());
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = TrainerPublicProfileRepository(firestore: firestore);
  });

  // ─── listByGeohashPrefix ──────────────────────────────────────────────────

  group('TrainerPublicProfileRepository.listByGeohashPrefix', () {
    test(
        'SCENARIO-411: returns trainers whose trainerGeohash starts with prefix',
        () async {
      await seedTrainer(uid: 't1', displayName: 'Ana', trainerGeohash: 's621h');
      await seedTrainer(uid: 't2', displayName: 'Bob', trainerGeohash: 's621k');
      await seedTrainer(uid: 't3', displayName: 'Car', trainerGeohash: 'u33dc');

      final result = await repo.listByGeohashPrefix('s621h');

      // t1 exactly matches; t2 matches same-length prefix if > = 's621h' and < 's621h￿'
      // For this test we seed 's621h' prefix — only docs starting with 's621h' match.
      expect(result.map((t) => t.uid), contains('t1'));
      expect(result.map((t) => t.uid), isNot(contains('t3')));
    });

    test(
        'SCENARIO-412: listByGeohashPrefix excludes docs with non-matching prefix',
        () async {
      await seedTrainer(
          uid: 'ta', displayName: 'Alpha', trainerGeohash: 'aaaaa');
      await seedTrainer(
          uid: 'tb', displayName: 'Beta', trainerGeohash: 'bbbbb');

      final result = await repo.listByGeohashPrefix('aaaaa');

      expect(result.map((t) => t.uid), contains('ta'));
      expect(result.map((t) => t.uid), isNot(contains('tb')));
    });

    test(
        'SCENARIO-413: returns empty list when no trainerGeohash matches prefix',
        () async {
      await seedTrainer(
          uid: 'tx', displayName: 'Xavier', trainerGeohash: 'zzzzz');

      final result = await repo.listByGeohashPrefix('aaaaa');

      expect(result, isEmpty);
    });

    test('listByGeohashPrefix with specialty filter excludes non-matching',
        () async {
      await seedTrainer(
        uid: 'ts1',
        displayName: 'Spec1',
        trainerGeohash: 's621h',
        specialty: TrainerSpecialty.yoga,
      );
      await seedTrainer(
        uid: 'ts2',
        displayName: 'Spec2',
        trainerGeohash: 's621h',
        specialty: TrainerSpecialty.running,
      );

      final result = await repo.listByGeohashPrefix(
        's621h',
        specialty: TrainerSpecialty.yoga,
      );

      expect(result.map((t) => t.uid), contains('ts1'));
      expect(result.map((t) => t.uid), isNot(contains('ts2')));
    });
  });

  // ─── listAll ──────────────────────────────────────────────────────────────

  group('TrainerPublicProfileRepository.listAll', () {
    test(
        'SCENARIO-414: returns all trainers ordered by displayNameLowercase ASC',
        () async {
      await seedTrainer(uid: 'u3', displayName: 'Zeta');
      await seedTrainer(uid: 'u1', displayName: 'Alpha');
      await seedTrainer(uid: 'u2', displayName: 'Beta');

      final result = await repo.listAll();

      expect(result.length, greaterThanOrEqualTo(3));
      final names = result.map((t) => t.displayNameLowercase).toList();
      final sorted = [...names]..sort();
      expect(names, equals(sorted));
    });

    test('listAll returns empty list when no trainers exist', () async {
      final result = await repo.listAll();
      expect(result, isEmpty);
    });

    test('listAll with specialty filter returns only matching trainers',
        () async {
      await seedTrainer(
        uid: 'sa1',
        displayName: 'Alpha',
        specialty: TrainerSpecialty.yoga,
      );
      await seedTrainer(
        uid: 'sa2',
        displayName: 'Beta',
        specialty: TrainerSpecialty.running,
      );

      final result = await repo.listAll(specialty: TrainerSpecialty.yoga);

      expect(result.map((t) => t.uid), contains('sa1'));
      expect(result.map((t) => t.uid), isNot(contains('sa2')));
    });
  });

  // ─── getById ──────────────────────────────────────────────────────────────

  group('TrainerPublicProfileRepository.getById', () {
    test('SCENARIO-415: getById returns null when document does not exist',
        () async {
      final result = await repo.getById('nonexistent-uid');
      expect(result, isNull);
    });

    test('getById returns trainer when document exists', () async {
      await seedTrainer(uid: 'found-uid', displayName: 'Found Trainer');

      final result = await repo.getById('found-uid');

      expect(result, isNotNull);
      expect(result!.uid, equals('found-uid'));
      expect(result.displayName, equals('Found Trainer'));
    });
  });
}

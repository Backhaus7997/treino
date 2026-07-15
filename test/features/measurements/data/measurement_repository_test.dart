import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/measurements/data/measurement_repository.dart';
import 'package:treino/features/measurements/domain/measurement.dart';

/// [MeasurementRepository.watchSelfLoggedForAthlete] — Q2 of the trainer
/// vantage (athlete-self-measurements, T4). Must match ONLY self-logged docs
/// (`recordedBy == athleteId`), never a trainer-recorded one — otherwise a
/// previous trainer's doc would enter the query and deny the whole list under
/// the read rule (design R4 / ADR-ASM-5).
void main() {
  test(
      'watchSelfLoggedForAthlete returns only self-logged docs, excludes '
      'trainer-recorded ones', () async {
    final firestore = FakeFirebaseFirestore();
    final repo = MeasurementRepository(firestore: firestore);

    // Self-logged: recordedBy == athleteId.
    await repo.add(Measurement(
      id: '',
      athleteId: 'athleteX',
      recordedBy: 'athleteX',
      recordedAt: DateTime.utc(2026, 1, 1),
      weightKg: 78,
    ));
    // Trainer-recorded for the same athlete: recordedBy != athleteId.
    await repo.add(Measurement(
      id: '',
      athleteId: 'athleteX',
      recordedBy: 'coach',
      recordedAt: DateTime.utc(2026, 2, 1),
      weightKg: 80,
    ));
    // Another athlete's self-logged doc: must never leak.
    await repo.add(Measurement(
      id: '',
      athleteId: 'athleteY',
      recordedBy: 'athleteY',
      recordedAt: DateTime.utc(2026, 3, 1),
      weightKg: 70,
    ));

    final result = await repo.watchSelfLoggedForAthlete('athleteX').first;

    expect(result, hasLength(1));
    expect(result.single.recordedBy, 'athleteX');
    expect(result.single.athleteId, 'athleteX');
    expect(result.single.weightKg, 78);
  });
}

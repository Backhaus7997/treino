import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/data/measurement_repository.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

void main() {
  // ---------------------------------------------------------------------------
  // The athlete view must surface the FULL measurement history for an athlete,
  // regardless of which trainer recorded each entry (reassignment / co-trainer).
  // Previously the provider queried by `recordedBy` == current trainer, so any
  // measurement logged by another trainer was silently invisible.
  // ---------------------------------------------------------------------------
  test(
    'measurementsForAthleteProvider returns measurements recorded by other '
    'trainers, not just the current one',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repo = MeasurementRepository(firestore: firestore);

      const athleteId = 'athlete1';
      const currentTrainer = 'trainerT2';
      const previousTrainer = 'trainerT1';

      // Logged by a previous/other trainer for the same athlete.
      await repo.add(
        Measurement(
          id: '',
          athleteId: athleteId,
          recordedBy: previousTrainer,
          recordedAt: DateTime.utc(2026, 1, 1),
          weightKg: 80,
        ),
      );
      // Logged by the current trainer.
      await repo.add(
        Measurement(
          id: '',
          athleteId: athleteId,
          recordedBy: currentTrainer,
          recordedAt: DateTime.utc(2026, 2, 1),
          weightKg: 79,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue(currentTrainer),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(measurementsForAthleteProvider(athleteId).stream)
          .first;

      // Both measurements are visible and sorted by recordedAt ascending.
      expect(result.map((m) => m.recordedBy), [previousTrainer, currentTrainer]);
    },
  );
}

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/data/performance_test_repository.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

void main() {
  // ---------------------------------------------------------------------------
  // The athlete view must surface the FULL performance-test history for an
  // athlete, regardless of which trainer recorded each entry (reassignment /
  // co-trainer). Previously the provider queried by `recordedBy` == current
  // trainer (over-reading the whole trainer-wide collection), so any test
  // logged by another trainer was silently invisible.
  // ---------------------------------------------------------------------------
  test(
    'performanceTestsForAthleteProvider returns tests recorded by other '
    'trainers, not just the current one',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repo = PerformanceTestRepository(firestore: firestore);

      const athleteId = 'athlete1';
      const currentTrainer = 'trainerT2';
      const previousTrainer = 'trainerT1';

      // Logged by a previous/other trainer for the same athlete.
      await repo.add(
        PerformanceTest(
          id: '',
          athleteId: athleteId,
          recordedBy: previousTrainer,
          recordedAt: DateTime.utc(2026, 1, 1),
          cmjCm: 32,
        ),
      );
      // Logged by the current trainer.
      await repo.add(
        PerformanceTest(
          id: '',
          athleteId: athleteId,
          recordedBy: currentTrainer,
          recordedAt: DateTime.utc(2026, 2, 1),
          cmjCm: 34,
        ),
      );
      // Logged for a DIFFERENT athlete — must NOT leak into this athlete's view.
      await repo.add(
        PerformanceTest(
          id: '',
          athleteId: 'athlete2',
          recordedBy: currentTrainer,
          recordedAt: DateTime.utc(2026, 3, 1),
          cmjCm: 99,
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
          .read(performanceTestsForAthleteProvider(athleteId).stream)
          .first;

      // Only this athlete's tests, sorted by recordedAt ascending, with the
      // entry from the previous trainer included.
      expect(result.map((t) => t.recordedBy), [previousTrainer, currentTrainer]);
    },
  );
}

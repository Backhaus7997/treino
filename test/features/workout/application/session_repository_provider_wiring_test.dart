import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show sessionRepositoryProvider;

void main() {
  // REGRESSION: sessionRepositoryProvider MUST wire publicProfileRepository so
  // SessionRepository.finish() can recompute the public workoutsCount/racha
  // counters. The provider previously omitted it, so finish() hit
  // `if (pubRepo == null) return;` and the counters silently never updated —
  // the Coach header showed "Sesiones 0" even after the athlete completed a
  // real workout. A direct-injection repo test cannot catch this; only a test
  // that builds the repo FROM the provider can.
  test(
    'sessionRepositoryProvider wires publicProfileRepository so finish() '
    'updates workoutsCount',
    () async {
      final firestore = FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [firestoreProvider.overrideWithValue(firestore)],
      );
      addTearDown(container.dispose);

      final repo = container.read(sessionRepositoryProvider);

      const uid = 'wiring-user-001';
      final session = await repo.create(
        uid: uid,
        routineId: 'routine-fuerza',
        routineName: 'fuerza',
        startedAt: DateTime.utc(2026, 6, 29, 8, 0, 0),
      );
      await repo.finish(
        uid: uid,
        sessionId: session.id,
        finishedAt: DateTime.utc(2026, 6, 29, 9, 0, 0),
        totalVolumeKg: 1100.0,
        durationMin: 60,
        wasFullyCompleted: true,
      );

      final profileSnap =
          await firestore.collection('userPublicProfiles').doc(uid).get();
      expect(
        profileSnap.exists,
        isTrue,
        reason: 'finish() should have written the public profile counters; '
            'if this fails, the provider is not wiring publicProfileRepository',
      );
      expect(profileSnap.data()!['workoutsCount'], equals(1));
      // `racha` is computed by computeStreak() using DateTime.now() — finish()
      // exposes no injectable clock — so its exact value depends on how many
      // days ago the hardcoded session date is relative to the wall clock
      // (1 only when run on the session's local day). Asserting equals(1) made
      // this test pass only on the day #199 merged (2026-06-29) and rot the
      // next day. Mirror the canonical SCENARIO-321 contract
      // (session_repository_test.dart): the wiring is proven by the counter
      // write above; for racha we only assert it round-tripped as an int.
      expect(profileSnap.data()!['racha'], isA<int>());
    },
  );
}

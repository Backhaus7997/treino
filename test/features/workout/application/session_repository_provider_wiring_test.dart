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
      expect(profileSnap.data()!['racha'], equals(1));
    },
  );
}

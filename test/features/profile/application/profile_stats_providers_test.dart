import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

ProviderContainer _makeContainer({
  required MockSessionRepository repo,
  String? uid,
}) {
  return ProviderContainer(
    overrides: [
      currentUidProvider.overrideWithValue(uid),
      sessionRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

void main() {
  late MockSessionRepository repo;

  setUpAll(() {
    registerFallbackValue(makeSession());
  });

  setUp(() {
    repo = MockSessionRepository();
  });

  group('userSessionStatsProvider (SCENARIO-311..312)', () {
    // SCENARIO-311: Provider returns correct totals for a user with sessions
    test(
        'SCENARIO-311: finished sessions → correct totalSessions, totalVolumeKg, streak',
        () async {
      final now = DateTime.now().toLocal();
      final today = DateTime(now.year, now.month, now.day, 10);
      final yesterday = today.subtract(const Duration(days: 1));

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              startedAt: today,
              status: SessionStatus.finished,
              wasFullyCompleted: true,
              totalVolumeKg: 1200.0,
            ),
            makeSession(
              id: 's2',
              startedAt: yesterday,
              status: SessionStatus.finished,
              wasFullyCompleted: true,
              totalVolumeKg: 800.0,
            ),
          ]);

      final container = _makeContainer(repo: repo, uid: 'u1');
      addTearDown(container.dispose);

      final result = await container.read(userSessionStatsProvider.future);

      expect(result.totalSessions, 2);
      expect(result.totalVolumeKg, 2000.0);
      expect(result.streak, 2); // today + yesterday = 2-day streak
    });

    // SCENARIO-311 extension: only finished sessions count
    test('finished-only filter: active sessions are excluded from totals',
        () async {
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
              id: 's1',
              status: SessionStatus.finished,
              wasFullyCompleted: true,
              totalVolumeKg: 500.0,
            ),
            makeSession(
              id: 's2',
              status: SessionStatus.active, // should be excluded
              totalVolumeKg: 300.0,
            ),
          ]);

      final container = _makeContainer(repo: repo, uid: 'u1');
      addTearDown(container.dispose);

      final result = await container.read(userSessionStatsProvider.future);

      expect(result.totalSessions, 1); // only finished
      expect(result.totalVolumeKg, 500.0);
    });

    // SCENARIO-312: Provider returns zero totals for new user
    test('SCENARIO-312: new user with no sessions → all zeros', () async {
      when(() => repo.listByUid('u1')).thenAnswer((_) async => []);

      final container = _makeContainer(repo: repo, uid: 'u1');
      addTearDown(container.dispose);

      final result = await container.read(userSessionStatsProvider.future);

      expect(result.totalSessions, 0);
      expect(result.totalVolumeKg, 0.0);
      expect(result.streak, 0);
    });

    // null uid → zeros (unauthenticated user)
    test('null uid → returns zero stats without calling repo', () async {
      final container = _makeContainer(repo: repo, uid: null);
      addTearDown(container.dispose);

      final result = await container.read(userSessionStatsProvider.future);

      expect(result.totalSessions, 0);
      expect(result.totalVolumeKg, 0.0);
      expect(result.streak, 0);
      verifyNever(() => repo.listByUid(any()));
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/insights/application/workout_days_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
  });

  group('athleteWorkoutDaysProvider', () {
    test('empty uid → empty trained days, zero streak, no repo call', () async {
      final repo = MockSessionRepository();

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(
        athleteWorkoutDaysProvider(
          (uid: '', month: DateTime(2026, 6)),
        ).future,
      );

      expect(result.trainedDays, isEmpty);
      expect(result.streak, 0);
      verifyNever(() => repo.listByUid(any()));
    });

    test('marks exactly the trained days of the selected month', () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            // [#379] Real UTC instants at NOON → unambiguous Argentina days
            // (Jun 1 / Jun 30); day-boundary LOCAL midnights would shift −3h
            // into the previous day/month under toArgentina.
            makeSession(
              id: 's1',
              startedAt: DateTime.utc(2026, 6, 1, 12),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            makeSession(
              id: 's2',
              startedAt: DateTime.utc(2026, 6, 30, 12),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
            // Outside the selected month → excluded.
            makeSession(
              id: 's3',
              startedAt: DateTime(2026, 5, 15),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
          ]);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(
        athleteWorkoutDaysProvider(
          (uid: 'u1', month: DateTime(2026, 6)),
        ).future,
      );

      expect(result.trainedDays, {
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 30),
      });
    });

    test('streak value comes from computeStreak over the FULL session list',
        () async {
      final repo = MockSessionRepository();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      when(() => repo.listByUid('u1')).thenAnswer((_) async => [
            makeSession(
                id: 's1',
                startedAt: today,
                status: SessionStatus.finished,
                wasFullyCompleted: true),
            makeSession(
              id: 's2',
              startedAt: today.subtract(const Duration(days: 1)),
              status: SessionStatus.finished,
              wasFullyCompleted: true,
            ),
          ]);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(
        athleteWorkoutDaysProvider(
          (uid: 'u1', month: DateTime(today.year, today.month)),
        ).future,
      );

      expect(result.streak, 2);
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/insights/application/day_insights_providers.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

Exercise _ex({required String id, required String muscleGroup}) => Exercise(
      id: id,
      name: 'Exercise',
      muscleGroup: muscleGroup,
      category: 'compound',
    );

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  group('athleteDayInsightsProvider', () {
    test(
        'SCENARIO-DAY-PROV-01: returns empty DayInsights when uid has no '
        'sessions on that day', () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => const []);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
      ]);
      addTearDown(container.dispose);

      final day = DateTime(2026, 7, 6);
      final result = await container.read(
        athleteDayInsightsProvider((uid: 'u1', day: day)).future,
      );

      expect(result.isEmpty, isTrue);
      expect(result.day, day);
    });

    test(
        'SCENARIO-DAY-PROV-02: chest Monday + legs Tuesday — querying Tuesday '
        'must NOT include Monday\'s chest (the exact regression this PR fixes)',
        () async {
      final repo = MockSessionRepository();
      final monday = DateTime(2026, 7, 6, 10);
      final tuesday = DateTime(2026, 7, 7, 10);

      final mondaySession = makeSession(
        id: 's-mon',
        startedAt: monday,
        status: SessionStatus.finished,
        routineId: 'r1',
      );
      final tuesdaySession = makeSession(
        id: 's-tue',
        startedAt: tuesday,
        status: SessionStatus.finished,
        routineId: 'r1',
      );

      when(() => repo.listByUid('u1'))
          .thenAnswer((_) async => [tuesdaySession, mondaySession]);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-mon')).thenAnswer(
          (_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-tue')).thenAnswer(
          (_) async => [makeSetLog(id: 'l2', exerciseId: 'e-legs')]);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => [
              _ex(id: 'e-chest', muscleGroup: 'chest'),
              _ex(id: 'e-legs', muscleGroup: 'quads'),
            ]),
        routineByIdProvider('r1').overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);

      final tuesdayResult = await container.read(
        athleteDayInsightsProvider((uid: 'u1', day: DateTime(2026, 7, 7)))
            .future,
      );

      expect(tuesdayResult.setsByGroup[MuscleGroupDisplay.cuadriceps], 1);
      expect(
        tuesdayResult.setsByGroup.containsKey(MuscleGroupDisplay.pecho),
        isFalse,
      );
    });

    test('SCENARIO-DAY-PROV-03: returns empty DayInsights for empty uid',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = await container.read(
        athleteDayInsightsProvider((uid: '', day: DateTime(2026, 7, 6))).future,
      );

      expect(result.isEmpty, isTrue);
    });
  });

  group('athleteLast7DaysInsightsProvider', () {
    test(
        'SCENARIO-DAY-PROV-04: returns 7 DayInsights entries, oldest first, '
        'anchored at today', () async {
      final repo = MockSessionRepository();
      when(() => repo.listByUid('u1')).thenAnswer((_) async => const []);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(
        athleteLast7DaysInsightsProvider('u1').future,
      );

      expect(result.length, 7);
      final today = DateTime.now();
      expect(result.last.day, DateTime(today.year, today.month, today.day));
    });
  });
}

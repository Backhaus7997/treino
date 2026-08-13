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
        wasFullyCompleted: true,
        routineId: 'r1',
      );
      final tuesdaySession = makeSession(
        id: 's-tue',
        startedAt: tuesday,
        status: SessionStatus.finished,
        wasFullyCompleted: true,
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
        visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
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

    test(
        'SCENARIO-DAY-PROV-05: a routine that is GONE does NOT fail the whole '
        'day tile — catalog mapping still resolves', () async {
      // Regression (#479): a day session pointing at a routine that is gone
      // (deleted, or a trainer-template whose owner revoked athlete sharing).
      // The read comes back as an error, the unguarded Future.wait over
      // routineByIdProvider propagated it, and the WHOLE day tile errored.
      final repo = MockSessionRepository();
      final session = makeSession(
        id: 's-gone',
        startedAt: DateTime(2026, 7, 6, 10),
        status: SessionStatus.finished,
        wasFullyCompleted: true,
        routineId: 'r-gone',
      );

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [session]);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-gone'))
          .thenAnswer((_) async => [
                makeSetLog(id: 'l1', exerciseId: 'e-chest'),
                makeSetLog(id: 'l2', exerciseId: 'e-custom'),
              ]);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith(
            (ref) async => [_ex(id: 'e-chest', muscleGroup: 'chest')]),
        // Tripwire (#479): the old unguarded path watched routineByIdProvider,
        // so a gone routine surfaced as an error that killed the whole tile.
        // If the provider ever watches it again, this test fails loudly.
        routineByIdProvider('r-gone').overrideWith(
          (ref) async =>
              throw StateError('routineByIdProvider must not be watched'),
        ),
        visibleRoutineByIdProvider('r-gone').overrideWith((ref) async => null),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(
        athleteDayInsightsProvider((uid: 'u1', day: DateTime(2026, 7, 6)))
            .future,
      );

      // The catalog exercise still renders; the custom one (whose only
      // mapping lived in the gone routine) degrades instead of failing the
      // tile.
      expect(result.setsByGroup, {MuscleGroupDisplay.pecho: 1});
      expect(result.sessionsCount, 1);
    });

    test(
        'SCENARIO-DAY-PROV-06: a TRANSIENT routine failure propagates — never '
        'a silently wrong heat-map', () async {
      // The other half of the [slotMuscleGroupsForSessions] contract: a
      // network blip must surface as a retryable error state, not silently
      // drop the routine's custom-exercise sets from the silhouette.
      final repo = MockSessionRepository();
      final session = makeSession(
        id: 's1',
        startedAt: DateTime(2026, 7, 6, 10),
        status: SessionStatus.finished,
        wasFullyCompleted: true,
        routineId: 'r1',
      );

      when(() => repo.listByUid('u1')).thenAnswer((_) async => [session]);
      when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1')).thenAnswer(
          (_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);

      final container = ProviderContainer(overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => const <Exercise>[]),
        visibleRoutineByIdProvider('r1').overrideWith(
          (ref) async => throw StateError('network blip'),
        ),
      ]);
      addTearDown(container.dispose);

      await expectLater(
        container.read(
          athleteDayInsightsProvider((uid: 'u1', day: DateTime(2026, 7, 6)))
              .future,
        ),
        throwsA(isA<StateError>()),
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

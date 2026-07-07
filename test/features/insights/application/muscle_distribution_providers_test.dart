import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/features/insights/application/muscle_distribution_providers.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/insights/domain/radar_axis.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockSessionRepository extends Mock implements SessionRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

Session _s(String id, DateTime dt, {String routineId = 'r'}) => Session(
      id: id,
      uid: 'a1',
      routineId: routineId,
      routineName: 'R',
      startedAt: dt,
      status: SessionStatus.finished,
      durationMin: 30,
      totalVolumeKg: 500,
    );

SetLog _log(String sessionId, String exId, {int setNum = 1}) => SetLog(
      id: '${sessionId}_$setNum',
      exerciseId: exId,
      exerciseName: exId,
      setNumber: setNum,
      reps: 8,
      weightKg: 50,
      completedAt: DateTime(2025, 1, 1),
    );

void main() {
  late _MockSessionRepository repo;

  setUp(() {
    repo = _MockSessionRepository();
  });

  test('empty uid → empty insights, zero Firestore reads', () async {
    final container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        sessionsByUidProvider('').overrideWith((ref) async => []),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      muscleDistributionInsightsProvider((uid: '', period: ChartPeriod.last30d))
          .future,
    );

    expect(result.isEmpty, isTrue);
    verifyNever(() => repo.listSetLogs(
        uid: any(named: 'uid'), sessionId: any(named: 'sessionId')));
  });

  test('resolves muscleGroup via catalog and folds sets to RadarAxis',
      () async {
    // Dates relative to `DateTime.now()` — must fall inside the default
    // last30d window regardless of when this test runs (same convention as
    // exercise_progression_providers_test.dart).
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final session = _s('s1', todayDate);

    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's1'))
        .thenAnswer((_) async => [_log('s1', 'chest')]);

    final container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        sessionsByUidProvider('a1').overrideWith((ref) async => [session]),
        exercisesProvider.overrideWith((ref) async => [
              const Exercise(
                id: 'chest',
                name: 'Press banca',
                muscleGroup: 'chest',
                category: 'compound',
              ),
            ]),
        routineByIdProvider('r').overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      muscleDistributionInsightsProvider(
          (uid: 'a1', period: ChartPeriod.last30d)).future,
    );

    expect(result.currentSetsByAxis[RadarAxis.chest], 1);
    expect(result.currentWorkouts, 1);
  });

  test('scans at most 60 sessions (bounded scan)', () async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final sessions = List.generate(
      65,
      (i) => _s(
          's$i', DateTime(todayDate.year, todayDate.month, todayDate.day - i)),
    );

    when(() => repo.listSetLogs(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'))).thenAnswer((_) async => []);

    final container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        sessionsByUidProvider('a1').overrideWith((ref) async => sessions),
        exercisesProvider.overrideWith((ref) async => []),
        routineByIdProvider('r').overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await container.read(
      muscleDistributionInsightsProvider(
          (uid: 'a1', period: ChartPeriod.last30d)).future,
    );

    verify(() => repo.listSetLogs(
        uid: any(named: 'uid'), sessionId: any(named: 'sessionId'))).called(60);
  });
}

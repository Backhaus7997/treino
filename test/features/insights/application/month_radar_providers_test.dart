import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/features/insights/application/month_radar_providers.dart';
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
      athleteMonthRadarInsightsProvider(
        (uid: '', month: DateTime(2026, 6)),
      ).future,
    );

    expect(result.isEmpty, isTrue);
    verifyNever(() => repo.listSetLogs(
        uid: any(named: 'uid'), sessionId: any(named: 'sessionId')));
  });

  test(
      'aggregates the SELECTED calendar month as current + the immediately '
      'preceding month as previous — NOT anchored to DateTime.now()', () async {
    // Selected month is June 2026; "now" (at test run time) could be any
    // month — the provider must resolve the window from `key.month`, never
    // from DateTime.now(), or this test would be flaky.
    final juneSession = _s('s1', DateTime(2026, 6, 15));
    final maySession = _s('s2', DateTime(2026, 5, 10));
    final farPastSession = _s('s3', DateTime(2020, 1, 1));

    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's1'))
        .thenAnswer((_) async => [_log('s1', 'chest')]);
    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's2'))
        .thenAnswer((_) async => [_log('s2', 'quads')]);
    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's3'))
        .thenAnswer((_) async => []);

    final container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        sessionsByUidProvider('a1').overrideWith(
          (ref) async => [juneSession, maySession, farPastSession],
        ),
        exercisesProvider.overrideWith((ref) async => [
              const Exercise(
                id: 'chest',
                name: 'Press banca',
                muscleGroup: 'chest',
                category: 'compound',
              ),
              const Exercise(
                id: 'quads',
                name: 'Sentadilla',
                muscleGroup: 'quads',
                category: 'compound',
              ),
            ]),
        routineByIdProvider('r').overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      athleteMonthRadarInsightsProvider(
        (uid: 'a1', month: DateTime(2026, 6, 1)),
      ).future,
    );

    expect(result.currentSetsByAxis[RadarAxis.chest], 1);
    expect(result.currentWorkouts, 1);
    expect(result.previousSetsByAxis[RadarAxis.legs], 1);
    expect(result.previousWorkouts, 1);
  });

  test(
      'reads the FULL session list (no bounded 60-scan) — same convention '
      'as athleteMonthlyReportProvider/athleteWorkoutDaysProvider', () async {
    // 65 sessions all in June 2026 — a bounded 60-scan would silently drop
    // 5 of them for an active athlete, same design risk flagged for the
    // monthly report aggregator.
    final sessions = List.generate(
      65,
      (i) => _s('s$i', DateTime(2026, 6, 1 + (i % 28))),
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

    final result = await container.read(
      athleteMonthRadarInsightsProvider(
        (uid: 'a1', month: DateTime(2026, 6, 1)),
      ).future,
    );

    expect(result.currentWorkouts, 65);
    verify(() => repo.listSetLogs(
        uid: any(named: 'uid'), sessionId: any(named: 'sessionId'))).called(65);
  });
}

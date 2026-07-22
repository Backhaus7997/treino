import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/workout/application/exercise_frequency_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show sessionsByUidProvider, sessionRepositoryProvider;
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockSessionRepository extends Mock implements SessionRepository {}

// ── Helpers ──────────────────────────────────────────────────────────────────

// #372: the frequency aggregator now counts only `countsAsWorkout` sessions
// (finished AND wasFullyCompleted). These fixtures are COMPLETED workouts, so
// set `wasFullyCompleted: true` — the default (false) would exclude them.
Session _s(String id, DateTime dt) => Session(
      id: id,
      uid: 'a1',
      routineId: 'r',
      routineName: 'R',
      startedAt: dt,
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

SetLog _log(String sessionId, String exId, String exName, {int setNum = 1}) =>
    SetLog(
      id: '${sessionId}_$setNum',
      exerciseId: exId,
      exerciseName: exName,
      setNumber: setNum,
      reps: 5,
      weightKg: 50,
      completedAt: DateTime(2025, 1, 1),
    );

ProviderContainer _container({
  required SessionRepository repo,
  required List<Session> sessions,
}) {
  return ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      sessionsByUidProvider('a1').overrideWith((ref) async => sessions),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _MockSessionRepository repo;

  setUp(() {
    repo = _MockSessionRepository();
  });

  test('SCENARIO-FREQ-PROV-01: empty athleteUid returns empty list, zero reads',
      () async {
    final container = _container(repo: repo, sessions: const []);
    addTearDown(container.dispose);

    final result = await container.read(exerciseFrequencyProvider((
      athleteUid: '',
      period: ChartPeriod.defaultPeriod,
    )).future);

    expect(result, isEmpty);
    verifyNever(() => repo.listSetLogs(
        uid: any(named: 'uid'), sessionId: any(named: 'sessionId')));
  });

  test('SCENARIO-FREQ-PROV-02: ranks exercises across scanned sessions',
      () async {
    // [AD7] Dates relative to `DateTime.now()` — must fall inside the
    // default period's (last30d) window.
    final today = DateTime.now();
    final s1 = _s('s1', today.subtract(const Duration(days: 5)));
    final s2 = _s('s2', today.subtract(const Duration(days: 2)));

    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's1'))
        .thenAnswer((_) async => [_log('s1', 'squat', 'Sentadilla')]);
    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's2'))
        .thenAnswer((_) async => [
              _log('s2', 'squat', 'Sentadilla'),
              _log('s2', 'bench', 'Press banca'),
            ]);

    final container = _container(repo: repo, sessions: [s2, s1]);
    addTearDown(container.dispose);

    final result = await container.read(exerciseFrequencyProvider((
      athleteUid: 'a1',
      period: ChartPeriod.defaultPeriod,
    )).future);

    expect(result, hasLength(2));
    expect(result[0].exerciseId, 'squat');
    expect(result[0].sessionCount, 2);
    expect(result[1].exerciseId, 'bench');
    expect(result[1].sessionCount, 1);
  });

  test(
      'SCENARIO-FREQ-PROV-03: scans at most 60 sessions (listSetLogs call count)',
      () async {
    final sessions = List.generate(
      65,
      (i) => _s('s$i', DateTime(2025, 1, 1).add(Duration(days: 64 - i))),
    );

    when(() => repo.listSetLogs(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'))).thenAnswer((_) async => []);

    final container = _container(repo: repo, sessions: sessions);
    addTearDown(container.dispose);

    await container.read(exerciseFrequencyProvider((
      athleteUid: 'a1',
      period: ChartPeriod.defaultPeriod,
    )).future);

    verify(() => repo.listSetLogs(
        uid: any(named: 'uid'), sessionId: any(named: 'sessionId'))).called(60);
  });
}

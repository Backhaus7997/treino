import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/workout/application/exercise_progression_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show sessionsByUidProvider, sessionRepositoryProvider;
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockSessionRepository extends Mock implements SessionRepository {}

// ── Helpers ──────────────────────────────────────────────────────────────────

// #372: the progression aggregator now counts only `countsAsWorkout` sessions
// (finished AND wasFullyCompleted). These fixtures are COMPLETED workouts, so
// set `wasFullyCompleted: true` — the default (false) would exclude them.
Session _s(String id, DateTime dt, {bool wasFullyCompleted = true}) => Session(
      id: id,
      uid: 'a1',
      routineId: 'r',
      routineName: 'R',
      startedAt: dt,
      status: SessionStatus.finished,
      wasFullyCompleted: wasFullyCompleted,
    );

/// [#377] Instante UTC-flagged al MEDIODÍA del día calendario ART de hace
/// [daysBack] días. Anclado a [argentinaNow] y no a `DateTime.now()`: entre
/// 21:00 y 23:59 ART el día UTC ya es "mañana", y un fixture derivado del día
/// UTC caería fuera de la ventana actual (que termina en el día ART de hoy).
/// Mediodía para que el shift −3h de [toArgentina] nunca cruce el borde de
/// día.
DateTime _artDay(int daysBack) {
  final today = argentinaNow();
  return DateTime.utc(today.year, today.month, today.day - daysBack, 12);
}

SetLog _log(String sessionId, String exId, String exName, int reps, double kg,
        {int setNum = 1}) =>
    SetLog(
      id: '${sessionId}_$setNum',
      exerciseId: exId,
      exerciseName: exName,
      setNumber: setNum,
      reps: reps,
      weightKg: kg,
      completedAt: DateTime(2025, 1, 1),
    );

ProviderContainer _container({
  required SessionRepository repo,
  required List<Session> sessions,
}) {
  final container = ProviderContainer(
    overrides: [
      sessionRepositoryProvider.overrideWithValue(repo),
      sessionsByUidProvider('a1').overrideWith(
        (ref) async => sessions,
      ),
    ],
  );
  return container;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _MockSessionRepository repo;

  setUp(() {
    repo = _MockSessionRepository();
  });

  // T7 — 60-bound: provider only calls listSetLogs for at most 60 sessions
  test('SCENARIO-PROG-04A: scans at most 60 sessions (listSetLogs call count)',
      () async {
    // 65 sessions DESC
    final sessions = List.generate(
      65,
      (i) => _s('s$i', DateTime(2025, 1, 1).add(Duration(days: 64 - i))),
    );

    // Mock: return empty setLogs for all sessions
    when(() => repo.listSetLogs(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'))).thenAnswer((_) async => []);

    final container = _container(repo: repo, sessions: sessions);
    addTearDown(container.dispose);

    await container.read(exerciseProgressionProvider((
      athleteUid: 'a1',
      exerciseId: 'squat',
      period: ChartPeriod.defaultPeriod
    )).future);

    // Should only call listSetLogs for the first 60 sessions (most-recent)
    verify(() => repo.listSetLogs(
        uid: any(named: 'uid'), sessionId: any(named: 'sessionId'))).called(60);
  });

  // T8 — empty uid → zero reads
  test('SCENARIO-T8: empty athleteUid returns empty, zero Firestore reads',
      () async {
    final container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        sessionsByUidProvider('').overrideWith((ref) async => []),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(exerciseProgressionProvider((
      athleteUid: '',
      exerciseId: 'squat',
      period: ChartPeriod.defaultPeriod
    )).future);

    expect(result.heaviestWeightSeries, isEmpty);
    verifyNever(() => repo.listSetLogs(
        uid: any(named: 'uid'), sessionId: any(named: 'sessionId')));
  });

  // T9 — dedupe + order for exercise list provider
  test('SCENARIO-PROG-05A/B: exercise list deduplicated, most-recent first',
      () async {
    // s1 (older) has squat + bench; s2 (newer) has squat + deadlift
    final s1 = _s('s1', DateTime(2025, 1, 5));
    final s2 = _s('s2', DateTime(2025, 1, 15));
    final sessions = [s2, s1]; // DESC

    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's2'))
        .thenAnswer((_) async => [
              _log('s2', 'squat', 'Sentadilla', 5, 90),
              _log('s2', 'deadlift', 'Peso muerto', 3, 100, setNum: 2),
            ]);
    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's1'))
        .thenAnswer((_) async => [
              _log('s1', 'squat', 'Sentadilla', 5, 80),
              _log('s1', 'bench', 'Press banca', 5, 60, setNum: 2),
            ]);

    final container = _container(repo: repo, sessions: sessions);
    addTearDown(container.dispose);

    final list = await container.read(athleteExerciseListProvider('a1').future);

    // Deduplicated: squat, deadlift, bench (squat appears in both but once)
    expect(list.map((e) => e.exerciseId).toSet().length, list.length);
    // Most-recent-first: s2's exercises come before s1's
    // First entry must be from s2 (squat or deadlift)
    expect(['squat', 'deadlift'].contains(list.first.exerciseId), isTrue);
    // Bench (only in s1, older) must come after deadlift
    final benchIdx = list.indexWhere((e) => e.exerciseId == 'bench');
    final deadliftIdx = list.indexWhere((e) => e.exerciseId == 'deadlift');
    expect(deadliftIdx, lessThan(benchIdx));
  });

  // Happy path: Heaviest Weight aggregated correctly through provider
  test(
      'SCENARIO-PROG-01A via provider: Heaviest Weight series correctly aggregated',
      () async {
    // [AD7] Dates relative to `DateTime.now()` — must fall inside the
    // default last30d window regardless of when this test runs.
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final s1 =
        _s('s1', DateTime(todayDate.year, todayDate.month, todayDate.day - 10));
    final s2 =
        _s('s2', DateTime(todayDate.year, todayDate.month, todayDate.day - 5));
    final sessions = [s2, s1]; // DESC

    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's2'))
        .thenAnswer((_) async => [_log('s2', 'squat', 'Sentadilla', 3, 95)]);
    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's1'))
        .thenAnswer((_) async => [_log('s1', 'squat', 'Sentadilla', 5, 80)]);

    final container = _container(repo: repo, sessions: sessions);
    addTearDown(container.dispose);

    final result = await container.read(exerciseProgressionProvider((
      athleteUid: 'a1',
      exerciseId: 'squat',
      period: ChartPeriod.defaultPeriod
    )).future);

    expect(result, isA<ExerciseProgression>());
    expect(result.heaviestWeightSeries.length, 2);
    // ASC: s1 first (80), s2 second (95)
    expect(result.heaviestWeightSeries[0].value, 80.0);
    expect(result.heaviestWeightSeries[1].value, 95.0);
  });

  // [AD7] The scan bound must never silently truncate sessions that fall
  // inside the selected period's window — if more than
  // [kProgressionSessionScan] sessions are within the window, the scan is
  // widened to cover all of them (the cap remains a genuine safety bound
  // for sessions OUTSIDE the window, not a silent data-loss trigger).
  test(
      '[AD7] scan bound widens beyond 60 when the period window needs more sessions',
      () async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // last30d's `previousStart` is 59 days back. 2 sessions/day for those
    // 60 days (indices 0..59) yields 120 sessions strictly within the
    // window — genuinely exceeding kProgressionSessionScan (60), which a
    // naive 1-per-day scan could never trigger.
    final sessions = List.generate(
      120,
      (i) => _s(
          's$i',
          DateTime(todayDate.year, todayDate.month,
              todayDate.day - (i ~/ 2))), // DESC, 2 per day
    );

    when(() => repo.listSetLogs(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'))).thenAnswer((_) async => []);

    final container = _container(repo: repo, sessions: sessions);
    addTearDown(container.dispose);

    await container.read(exerciseProgressionProvider((
      athleteUid: 'a1',
      exerciseId: 'squat',
      period: ChartPeriod.last30d,
    )).future);

    // All 65 sessions are within the last30d window (0..29 days back would
    // be the strict window, but even beyond that the scan must not stop at
    // exactly 60 when window-relevant sessions exist past that point).
    verify(() => repo.listSetLogs(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'))).called(greaterThan(60));
  });

  // ── #377 — periodsWithData: la preselección acotada por período ────────────

  group('#377 periodsWithData', () {
    test(
        'marca los períodos cuya ventana actual tiene sets con peso; '
        'un ejercicio fuera de toda ventana queda EN la lista sin flags',
        () async {
      // "Hoy" (ART) cae siempre dentro de las ventanas actuales de los 3
      // períodos; hace 40 días cae siempre fuera de las 3 (last30d = 29 días
      // atrás, thisWeek ≤ 6, month ≤ 30).
      final sToday = _s('sToday', _artDay(0));
      final sOld = _s('sOld', _artDay(40));
      final sessions = [sToday, sOld]; // DESC

      when(() => repo.listSetLogs(uid: 'a1', sessionId: 'sToday')).thenAnswer(
          (_) async => [_log('sToday', 'squat', 'Sentadilla', 5, 80)]);
      when(() => repo.listSetLogs(uid: 'a1', sessionId: 'sOld')).thenAnswer(
          (_) async => [_log('sOld', 'bench', 'Press banca', 5, 60)]);

      final container = _container(repo: repo, sessions: sessions);
      addTearDown(container.dispose);

      final list =
          await container.read(athleteExerciseListProvider('a1').future);

      final squat = list.firstWhere((e) => e.exerciseId == 'squat');
      expect(squat.periodsWithData, ChartPeriod.values.toSet());

      // Membership intacta: bench sigue en el picker, pero sin datos en
      // ningún período seleccionable.
      final bench = list.firstWhere((e) => e.exerciseId == 'bench');
      expect(bench.periodsWithData, isEmpty);
    });

    test('sets con weightKg = 0 no marcan período (espejo de #368)', () async {
      // Dominadas al peso corporal: el player las loguea con 0kg y el chart
      // las excluye de las 4 series → un período con SOLO sets 0kg rendiría
      // "Sin datos para este ejercicio." y no debe marcar flag.
      final sToday = _s('sToday', _artDay(0));

      when(() => repo.listSetLogs(uid: 'a1', sessionId: 'sToday'))
          .thenAnswer((_) async => [
                _log('sToday', 'pullup', 'Dominadas', 10, 0),
                _log('sToday', 'squat', 'Sentadilla', 5, 80, setNum: 2),
              ]);

      final container = _container(repo: repo, sessions: [sToday]);
      addTearDown(container.dispose);

      final list =
          await container.read(athleteExerciseListProvider('a1').future);

      final pullup = list.firstWhere((e) => e.exerciseId == 'pullup');
      expect(pullup.periodsWithData, isEmpty);
      final squat = list.firstWhere((e) => e.exerciseId == 'squat');
      expect(squat.periodsWithData, isNotEmpty);
    });

    test('sesiones abandonadas no marcan período (espejo de #372)', () async {
      // countsAsWorkout == false: el aggregator la excluye de las series, así
      // que tampoco puede sostener la preselección.
      final sAbandoned = _s('sAbandoned', _artDay(0), wasFullyCompleted: false);

      when(() => repo.listSetLogs(uid: 'a1', sessionId: 'sAbandoned'))
          .thenAnswer(
              (_) async => [_log('sAbandoned', 'squat', 'Sentadilla', 5, 80)]);

      final container = _container(repo: repo, sessions: [sAbandoned]);
      addTearDown(container.dispose);

      final list =
          await container.read(athleteExerciseListProvider('a1').future);

      final squat = list.firstWhere((e) => e.exerciseId == 'squat');
      expect(squat.periodsWithData, isEmpty);
    });

    test(
        'el scan de la lista se ensancha más allá de 60 para cubrir la '
        'ventana del período (mismo contrato AD7 del provider de progresión)',
        () async {
      // 3 sesiones/día durante los 30 días de la ventana last30d = 90
      // sesiones dentro de la ventana — supera el cap de 60. La ÚNICA sesión
      // con 'old-ex' es la más vieja (día 29, índice 89): con el cap plano de
      // antes ni siquiera se escaneaba, y el ejercicio perdía flag y entrada.
      final sessions = List.generate(
        90,
        (i) => _s('s$i', _artDay(i ~/ 3)), // DESC, 3 por día
      );

      when(() => repo.listSetLogs(
          uid: any(named: 'uid'),
          sessionId: any(named: 'sessionId'))).thenAnswer((_) async => []);
      when(() => repo.listSetLogs(uid: 'a1', sessionId: 's89')).thenAnswer(
          (_) async => [_log('s89', 'old-ex', 'Remo con barra', 5, 70)]);

      final container = _container(repo: repo, sessions: sessions);
      addTearDown(container.dispose);

      final list =
          await container.read(athleteExerciseListProvider('a1').future);

      verify(() => repo.listSetLogs(
          uid: any(named: 'uid'),
          sessionId: any(named: 'sessionId'))).called(90);

      final oldEx = list.firstWhere((e) => e.exerciseId == 'old-ex');
      expect(oldEx.periodsWithData, contains(ChartPeriod.last30d));
    });
  });
}

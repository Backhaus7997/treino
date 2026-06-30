import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/exercise_progression_aggregator.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Session _session(String id, DateTime startedAt) => Session(
      id: id,
      uid: 'athlete1',
      routineId: 'r1',
      routineName: 'Rutina A',
      startedAt: startedAt,
      status: SessionStatus.finished,
    );

SetLog _log({
  required String sessionId,
  required String exerciseId,
  required String exerciseName,
  required int reps,
  required double weightKg,
  int setNumber = 1,
}) =>
    SetLog(
      id: '${sessionId}_${exerciseId}_$setNumber',
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      completedAt: DateTime(2025, 1, 1),
    );

// Sessions ordered DESC (most-recent first) — matches sessionsByUidProvider
final _s1 = _session('s1', DateTime(2025, 1, 5));
final _s2 = _session('s2', DateTime(2025, 1, 10));
final _s3 = _session('s3', DateTime(2025, 1, 15));

// sessionsDesc: most-recent first
final _sessionsDesc = [_s3, _s2, _s1];

// SetLogs map
final _logsBySession = <String, List<SetLog>>{
  's1': [
    _log(
        sessionId: 's1',
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        reps: 5,
        weightKg: 80,
        setNumber: 1),
    _log(
        sessionId: 's1',
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        reps: 3,
        weightKg: 90,
        setNumber: 2),
    _log(
        sessionId: 's1',
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        reps: 4,
        weightKg: 85,
        setNumber: 3),
    _log(
        sessionId: 's1',
        exerciseId: 'bench',
        exerciseName: 'Press banca',
        reps: 5,
        weightKg: 60),
  ],
  's2': [
    _log(
        sessionId: 's2',
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        reps: 3,
        weightKg: 95,
        setNumber: 1),
    _log(
        sessionId: 's2',
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        reps: 2,
        weightKg: 92,
        setNumber: 2),
  ],
  's3': [],
};

void main() {
  group('aggregateExerciseProgression', () {
    // T1 — PR series
    test(
        'SCENARIO-PROG-01A: PR per session — max weightKg per session, ASC order',
        () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );

      expect(result.prSeries.length, 2);
      // s1 PR = max(80, 90, 85) = 90, s2 PR = max(95, 92) = 95
      expect(result.prSeries[0].value, 90.0); // s1 (earlier)
      expect(result.prSeries[1].value, 95.0); // s2 (later)
      // ASC by date
      expect(result.prSeries[0].date.isBefore(result.prSeries[1].date), isTrue);
    });

    test('SCENARIO-PROG-01B: PR with single set per session', () {
      final sessions = [_session('sx', DateTime(2025, 1, 20))];
      final logs = {
        'sx': [
          _log(
              sessionId: 'sx',
              exerciseId: 'squat',
              exerciseName: 'S',
              reps: 5,
              weightKg: 70)
        ],
      };
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: sessions,
        logsBySession: logs,
        now: DateTime(2025, 2, 1),
      );
      expect(result.prSeries.length, 1);
      expect(result.prSeries.first.value, 70.0);
    });

    test('SCENARIO-PROG-01C: PR excludes sets for other exercises', () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      // bench sets in s1 should NOT influence squat PR
      // squat s1 max = 90 (not 60 from bench)
      expect(result.prSeries[0].value, 90.0);
      // no bench points
      expect(result.prSeries.every((p) => p.value != 60.0), isTrue);
    });

    // T2 — Volumen series
    test('SCENARIO-PROG-02A: Volumen = Σ(reps×weightKg) per session', () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      // s1: 5×80 + 3×90 + 4×85 = 400 + 270 + 340 = 1010
      // s2: 3×95 + 2×92 = 285 + 184 = 469
      expect(result.volumeSeries[0].value, closeTo(1010.0, 0.01));
      expect(result.volumeSeries[1].value, closeTo(469.0, 0.01));
    });

    test('SCENARIO-PROG-02B: Volumen ordered ASC by startedAt', () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      expect(
        result.volumeSeries[0].date.isBefore(result.volumeSeries[1].date),
        isTrue,
      );
    });

    // T3 — Frecuencia
    test('SCENARIO-PROG-03A: Frecuencia counts sessions within 56 days', () {
      final now = DateTime(2025, 3, 1);
      // s3=Jan15 (45d ago ✓), s2=Jan10 (50d ago ✓), s1=Jan5 (55d ago ✓)
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: now,
      );
      // s1(55d), s2(50d), s3(45d) all within 56d; s3 has no squat sets
      // frecuencia counts sessions WITH squat sets in window
      expect(result.frequencyLast8Weeks, 2); // s1 and s2 have squat sets
    });

    test('SCENARIO-PROG-03A-outside: session older than 56 days excluded', () {
      final now = DateTime(2025, 3, 5);
      // s1=Jan5 is 59d ago → outside window
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: now,
      );
      // s1 (59d ago) excluded, s2 (54d ✓), s3 (45d but no squat sets)
      expect(result.frequencyLast8Weeks, 1); // only s2
    });

    test(
        'SCENARIO-PROG-03B: Frecuencia boundary — session at exactly 56 days is included',
        () {
      final now = DateTime(2025, 3, 2, 0, 0, 0);
      final edge = now.subtract(const Duration(days: 56)); // exactly 56d ago
      final sEdge = _session('sEdge', edge);
      final logs = {
        'sEdge': [
          _log(
              sessionId: 'sEdge',
              exerciseId: 'squat',
              exerciseName: 'S',
              reps: 3,
              weightKg: 80)
        ],
      };
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: [sEdge],
        logsBySession: logs,
        now: now,
      );
      expect(result.frequencyLast8Weeks, 1); // inclusive lower bound
    });

    // T5 — Filter + empty key
    test('T6-empty-key: empty exerciseId returns empty progression', () {
      final result = aggregateExerciseProgression(
        exerciseId: '',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      expect(result.prSeries, isEmpty);
      expect(result.volumeSeries, isEmpty);
      expect(result.frequencyLast8Weeks, 0);
    });

    // T5 — exerciseName from SetLog
    test('T5-name: exerciseName is taken from SetLog, not hardcoded', () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      expect(result.exerciseName, 'Sentadilla');
    });

    // NEVER weekNumber — T4 compliance
    test('T4-startedAt: progression is computed from startedAt, not weekNumber',
        () {
      // weekNumber is @Default(0) on both sessions — if we used weekNumber,
      // Frecuencia would be wrong. Only startedAt matters.
      final now = DateTime(2025, 1, 20);
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: now,
      );
      // s1=Jan5 (15d ✓), s2=Jan10 (10d ✓), s3 has no squat sets
      expect(result.frequencyLast8Weeks, 2);
    });

    test(
        'No sets for exercise → empty prSeries and volumeSeries, zero frecuencia',
        () {
      final result = aggregateExerciseProgression(
        exerciseId: 'deadlift',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      expect(result.prSeries, isEmpty);
      expect(result.volumeSeries, isEmpty);
      expect(result.frequencyLast8Weeks, 0);
    });
  });
}

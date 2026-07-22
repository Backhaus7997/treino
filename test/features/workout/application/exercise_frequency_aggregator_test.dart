import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/workout/application/exercise_frequency_aggregator.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

// #372: the aggregator now counts only `countsAsWorkout` sessions (finished
// AND wasFullyCompleted). These fixtures represent COMPLETED workouts, so they
// set `wasFullyCompleted: true` explicitly — otherwise the default (false)
// would make them abandoned and they'd be excluded.
Session _session(String id, DateTime startedAt) => Session(
      id: id,
      uid: 'athlete1',
      routineId: 'r1',
      routineName: 'Rutina A',
      startedAt: startedAt,
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

// #372: an ABANDONED session (finished but wasFullyCompleted=false) — its sets
// must NOT count toward the frequency ranking.
Session _abandoned(String id, DateTime startedAt) => Session(
      id: id,
      uid: 'athlete1',
      routineId: 'r1',
      routineName: 'Rutina A',
      startedAt: startedAt,
      status: SessionStatus.finished,
      wasFullyCompleted: false,
    );

SetLog _log({
  required String sessionId,
  required String exerciseId,
  required String exerciseName,
  int setNumber = 1,
}) =>
    SetLog(
      id: '${sessionId}_${exerciseId}_$setNumber',
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      reps: 5,
      weightKg: 50,
      completedAt: DateTime(2025, 1, 1),
    );

void main() {
  group('aggregateExerciseFrequency', () {
    test('SCENARIO-FREQ-01A: ranks exercises by distinct session count, desc',
        () {
      final s1 = _session('s1', DateTime(2025, 1, 5));
      final s2 = _session('s2', DateTime(2025, 1, 10));
      final s3 = _session('s3', DateTime(2025, 1, 15));

      final logsBySession = {
        's1': [
          _log(
              sessionId: 's1', exerciseId: 'squat', exerciseName: 'Sentadilla'),
          _log(
              sessionId: 's1',
              exerciseId: 'bench',
              exerciseName: 'Press banca'),
        ],
        's2': [
          _log(
              sessionId: 's2', exerciseId: 'squat', exerciseName: 'Sentadilla'),
        ],
        's3': [
          _log(
              sessionId: 's3', exerciseId: 'squat', exerciseName: 'Sentadilla'),
          _log(
              sessionId: 's3',
              exerciseId: 'bench',
              exerciseName: 'Press banca'),
        ],
      };

      final result = aggregateExerciseFrequency(
        sessions: [s3, s2, s1],
        logsBySession: logsBySession,
      );

      expect(result, hasLength(2));
      expect(result[0].exerciseId, 'squat');
      expect(result[0].sessionCount, 3);
      expect(result[1].exerciseId, 'bench');
      expect(result[1].sessionCount, 2);
    });

    test(
        'SCENARIO-FREQ-01B: multiple sets of same exercise in one session count as ONE session',
        () {
      final s1 = _session('s1', DateTime(2025, 1, 5));

      final logsBySession = {
        's1': [
          _log(
              sessionId: 's1',
              exerciseId: 'squat',
              exerciseName: 'Sentadilla',
              setNumber: 1),
          _log(
              sessionId: 's1',
              exerciseId: 'squat',
              exerciseName: 'Sentadilla',
              setNumber: 2),
          _log(
              sessionId: 's1',
              exerciseId: 'squat',
              exerciseName: 'Sentadilla',
              setNumber: 3),
        ],
      };

      final result = aggregateExerciseFrequency(
        sessions: [s1],
        logsBySession: logsBySession,
      );

      expect(result, hasLength(1));
      expect(result[0].sessionCount, 1);
    });

    test('REGRESSION-372: abandoned sessions do NOT count toward frequency',
        () {
      // 2 completed squat sessions + 1 ABANDONED session that also logged squat
      // and a deadlift only ever seen in that abandoned session.
      final s1 = _session('s1', DateTime(2025, 1, 5));
      final s2 = _session('s2', DateTime(2025, 1, 10));
      final sAband = _abandoned('s-aband', DateTime(2025, 1, 12));

      final logsBySession = {
        's1': [
          _log(sessionId: 's1', exerciseId: 'squat', exerciseName: 'Sentadilla')
        ],
        's2': [
          _log(sessionId: 's2', exerciseId: 'squat', exerciseName: 'Sentadilla')
        ],
        's-aband': [
          _log(
              sessionId: 's-aband',
              exerciseId: 'squat',
              exerciseName: 'Sentadilla'),
          _log(
              sessionId: 's-aband',
              exerciseId: 'deadlift',
              exerciseName: 'Peso muerto'),
        ],
      };

      final result = aggregateExerciseFrequency(
        sessions: [sAband, s2, s1], // DESC
        logsBySession: logsBySession,
      );

      // squat counted only in the 2 COMPLETED sessions (not 3); deadlift — only
      // ever in the abandoned session — is absent entirely.
      expect(result, hasLength(1));
      expect(result[0].exerciseId, 'squat');
      expect(result[0].sessionCount, 2);
      expect(result.where((e) => e.exerciseId == 'deadlift'), isEmpty);
    });

    test('SCENARIO-FREQ-02: filters sessions outside the period window', () {
      final now = DateTime(2025, 2, 1);
      final window = ChartPeriod.last30d.windowFor(now);

      // Inside window (last 30 days ending 2025-02-01)
      final sIn = _session('sIn', DateTime(2025, 1, 20));
      // Outside window (way before)
      final sOut = _session('sOut', DateTime(2024, 10, 1));

      final logsBySession = {
        'sIn': [
          _log(
              sessionId: 'sIn',
              exerciseId: 'squat',
              exerciseName: 'Sentadilla'),
        ],
        'sOut': [
          _log(
              sessionId: 'sOut',
              exerciseId: 'deadlift',
              exerciseName: 'Peso muerto'),
        ],
      };

      final result = aggregateExerciseFrequency(
        sessions: [sIn, sOut],
        logsBySession: logsBySession,
        periodWindow: window,
      );

      expect(result, hasLength(1));
      expect(result[0].exerciseId, 'squat');
    });

    test('SCENARIO-FREQ-03: ties broken by most-recently-logged exercise first',
        () {
      final s1 = _session('s1', DateTime(2025, 1, 5));
      final s2 = _session('s2', DateTime(2025, 1, 10));

      // Both exercises appear once (tie) — squat logged in the more recent
      // session (s2, DESC-first in the input list) should win the tiebreak.
      final logsBySession = {
        's1': [
          _log(
              sessionId: 's1',
              exerciseId: 'bench',
              exerciseName: 'Press banca'),
        ],
        's2': [
          _log(
              sessionId: 's2', exerciseId: 'squat', exerciseName: 'Sentadilla'),
        ],
      };

      final result = aggregateExerciseFrequency(
        sessions: [s2, s1], // DESC — most-recent first
        logsBySession: logsBySession,
      );

      expect(result, hasLength(2));
      expect(result[0].exerciseId, 'squat');
      expect(result[1].exerciseId, 'bench');
    });

    test('SCENARIO-FREQ-04: zero sessions with logs returns empty list', () {
      final result = aggregateExerciseFrequency(
        sessions: const [],
        logsBySession: const {},
      );

      expect(result, isEmpty);
    });

    test('SCENARIO-FREQ-05: sessions with no matching logs are skipped', () {
      final s1 = _session('s1', DateTime(2025, 1, 5));

      final result = aggregateExerciseFrequency(
        sessions: [s1],
        logsBySession: const {'s1': []},
      );

      expect(result, isEmpty);
    });
  });
}

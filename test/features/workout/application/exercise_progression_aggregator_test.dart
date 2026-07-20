import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/workout/application/exercise_progression_aggregator.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

// #372: the aggregator now counts only `countsAsWorkout` sessions (finished
// AND wasFullyCompleted). These fixtures represent COMPLETED workouts, so they
// set `wasFullyCompleted: true` explicitly — otherwise the default (false)
// would make them abandoned and they'd be excluded from every series.
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
// must NOT feed any progression series, the PRs, or the frecuencia-8-weeks stat.
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
  group('calculateOneRepMax [AD2]', () {
    test('Epley formula: weight * (1 + reps/30.0)', () {
      // 100kg x 5 reps -> 100 * (1 + 5/30) = 116.666...
      expect(
          calculateOneRepMax(weightKg: 100, reps: 5), closeTo(116.6667, 0.001));
    });

    test('1 rep returns weight * (1 + 1/30.0)', () {
      expect(
          calculateOneRepMax(weightKg: 80, reps: 1), closeTo(82.6667, 0.001));
    });

    test('full double precision — no rounding applied internally', () {
      final result = calculateOneRepMax(weightKg: 90, reps: 3);
      expect(result, 90 * (1 + 3 / 30.0));
    });

    test('reps <= 0 returns null (skip — not a valid set)', () {
      expect(calculateOneRepMax(weightKg: 100, reps: 0), isNull);
      expect(calculateOneRepMax(weightKg: 100, reps: -1), isNull);
    });
  });

  group('roundToNearestHalfKg [AD2 display rounding]', () {
    test('rounds to nearest 0.5kg', () {
      expect(roundToNearestHalfKg(116.6667), 116.5);
      expect(roundToNearestHalfKg(82.6667), 82.5);
      expect(roundToNearestHalfKg(100.24), 100.0);
      expect(roundToNearestHalfKg(100.26), 100.5);
      expect(roundToNearestHalfKg(100.76), 101.0);
    });
  });

  group('aggregateExerciseProgression [AD3 — 4 series]', () {
    // T1 — Heaviest Weight series (renamed from prSeries)
    test(
        'SCENARIO-PROG-01A: Heaviest Weight per session — max weightKg, ASC order',
        () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );

      expect(result.heaviestWeightSeries.length, 2);
      // s1 heaviest = max(80, 90, 85) = 90, s2 heaviest = max(95, 92) = 95
      expect(result.heaviestWeightSeries[0].value, 90.0); // s1 (earlier)
      expect(result.heaviestWeightSeries[1].value, 95.0); // s2 (later)
      // ASC by date
      expect(
        result.heaviestWeightSeries[0].date
            .isBefore(result.heaviestWeightSeries[1].date),
        isTrue,
      );
    });

    test('SCENARIO-PROG-01B: Heaviest Weight with single set per session', () {
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
      expect(result.heaviestWeightSeries.length, 1);
      expect(result.heaviestWeightSeries.first.value, 70.0);
    });

    test('SCENARIO-PROG-01C: Heaviest Weight excludes sets for other exercises',
        () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      // bench sets in s1 should NOT influence squat heaviest weight
      expect(result.heaviestWeightSeries[0].value, 90.0);
      expect(result.heaviestWeightSeries.every((p) => p.value != 60.0), isTrue);
    });

    test('REGRESSION-372: abandoned sessions feed NO series, PR, or frecuencia',
        () {
      // A COMPLETED session at 70kg + an ABANDONED session at 200kg — the 200kg
      // set would be a bogus all-time PR if the abandoned session counted.
      final sOk = _session('s-ok', DateTime(2025, 1, 20));
      final sAband = _abandoned('s-aband', DateTime(2025, 1, 25));
      final logs = {
        's-ok': [
          _log(
              sessionId: 's-ok',
              exerciseId: 'squat',
              exerciseName: 'S',
              reps: 5,
              weightKg: 70),
        ],
        's-aband': [
          _log(
              sessionId: 's-aband',
              exerciseId: 'squat',
              exerciseName: 'S',
              reps: 5,
              weightKg: 200),
        ],
      };

      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: [sAband, sOk], // DESC
        logsBySession: logs,
        now: DateTime(2025, 2, 1),
      );

      // Only the completed session feeds the series → the 200kg abandoned set is
      // absent from every series (and therefore from the derived PRs).
      expect(result.heaviestWeightSeries.length, 1);
      expect(result.heaviestWeightSeries.single.value, 70.0);
      expect(
          result.heaviestWeightSeries.every((p) => p.value != 200.0), isTrue);
      // frecuencia-8-weeks counts only the completed session.
      expect(result.frequencyLast8Weeks, 1);
    });

    // T2 — Best Session Volume series (renamed from volumeSeries)
    test(
        'SCENARIO-PROG-02A: Best Session Volume = Σ(reps×weightKg) per session',
        () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      // s1: 5×80 + 3×90 + 4×85 = 400 + 270 + 340 = 1010
      // s2: 3×95 + 2×92 = 285 + 184 = 469
      expect(result.bestSessionVolumeSeries[0].value, closeTo(1010.0, 0.01));
      expect(result.bestSessionVolumeSeries[1].value, closeTo(469.0, 0.01));
    });

    test('SCENARIO-PROG-02B: Best Session Volume ordered ASC by startedAt', () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      expect(
        result.bestSessionVolumeSeries[0].date
            .isBefore(result.bestSessionVolumeSeries[1].date),
        isTrue,
      );
    });

    // AD3 — Best Set Volume (NEW): max(reps*weightKg) of a single set
    test('AD3: Best Set Volume = max(reps×weightKg) of a single set', () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      // s1 sets: 5×80=400, 3×90=270, 4×85=340 -> max = 400
      // s2 sets: 3×95=285, 2×92=184 -> max = 285
      expect(result.bestSetVolumeSeries[0].value, closeTo(400.0, 0.01));
      expect(result.bestSetVolumeSeries[1].value, closeTo(285.0, 0.01));
    });

    // AD2 — 1RM series (NEW): Epley per session, taking the max across sets
    test('AD2: 1RM series uses Epley formula, max per session', () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      // s1: candidates 80*(1+5/30)=93.333, 90*(1+3/30)=99.0, 85*(1+4/30)=96.333
      //     -> max = 99.0
      expect(result.oneRepMaxSeries[0].value, closeTo(99.0, 0.001));
      // s2: 95*(1+3/30)=104.5, 92*(1+2/30)=98.133 -> max = 104.5
      expect(result.oneRepMaxSeries[1].value, closeTo(104.5, 0.001));
    });

    test('AD2: sets with reps<=0 are skipped in 1RM computation', () {
      final sessions = [_session('sx', DateTime(2025, 1, 20))];
      final logs = {
        'sx': [
          SetLog(
            id: 'sx_squat_1',
            exerciseId: 'squat',
            exerciseName: 'Sentadilla',
            setNumber: 1,
            reps: 0, // invalid — should be skipped
            weightKg: 200,
            completedAt: DateTime(2025, 1, 1),
          ),
          _log(
              sessionId: 'sx',
              exerciseId: 'squat',
              exerciseName: 'Sentadilla',
              reps: 5,
              weightKg: 80),
        ],
      };
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: sessions,
        logsBySession: logs,
        now: DateTime(2025, 2, 1),
      );
      // Only the valid set (80kg x5 -> 93.333) should count — the reps=0 set
      // must never produce Infinity/NaN nor dominate the max.
      expect(result.oneRepMaxSeries.length, 1);
      expect(result.oneRepMaxSeries.first.value, closeTo(93.333, 0.01));
    });

    test('1RM series omits a session entirely if ALL its sets have reps<=0',
        () {
      final sessions = [_session('sx', DateTime(2025, 1, 20))];
      final logs = {
        'sx': [
          SetLog(
            id: 'sx_squat_1',
            exerciseId: 'squat',
            exerciseName: 'Sentadilla',
            setNumber: 1,
            reps: 0,
            weightKg: 200,
            completedAt: DateTime(2025, 1, 1),
          ),
        ],
      };
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: sessions,
        logsBySession: logs,
        now: DateTime(2025, 2, 1),
      );
      expect(result.oneRepMaxSeries, isEmpty);
      // Heaviest Weight / volumes still populate from the (reps=0) set since
      // those metrics don't depend on reps>0 the same way 1RM does.
      expect(result.heaviestWeightSeries, isNotEmpty);
    });

    // T3 — Frecuencia (unchanged behavior, still keyed off Heaviest Weight
    // presence per session)
    test('SCENARIO-PROG-03A: Frecuencia counts sessions within 56 days', () {
      final now = DateTime(2025, 3, 1);
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: now,
      );
      expect(result.frequencyLast8Weeks, 2); // s1 and s2 have squat sets
    });

    test('SCENARIO-PROG-03A-outside: session older than 56 days excluded', () {
      final now = DateTime(2025, 3, 5);
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: now,
      );
      expect(result.frequencyLast8Weeks, 1); // only s2
    });

    test(
        'SCENARIO-PROG-03B: Frecuencia boundary — session at exactly 56 days is included',
        () {
      // [#379] `now` is the Argentina-framed reference (as argentinaNow()
      // provides in production): UTC-flagged wall-clock. Sessions are stored as
      // real UTC instants. The 56-day cutoff lives in the ART frame, and the
      // filter compares `toArgentina(startedAt)` against it — so a session whose
      // ART instant is EXACTLY the cutoff must be INCLUDED (inclusive lower
      // bound). Since ART = UTC - offset, the real UTC startedAt is
      // `cutoff + offset`. All UTC-flagged → TZ-independent (local UTC-3 == CI
      // UTC).
      final now = DateTime.utc(2025, 3, 2, 12);
      final cutoffArt = now.subtract(const Duration(days: 56));
      final sEdge = _session('sEdge', cutoffArt.add(argentinaUtcOffset));
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
      expect(result.heaviestWeightSeries, isEmpty);
      expect(result.oneRepMaxSeries, isEmpty);
      expect(result.bestSetVolumeSeries, isEmpty);
      expect(result.bestSessionVolumeSeries, isEmpty);
      expect(result.personalRecords, isEmpty);
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
      final now = DateTime(2025, 1, 20);
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: now,
      );
      expect(result.frequencyLast8Weeks, 2);
    });

    test(
        'No sets for exercise → all series empty, zero frecuencia, no personalRecords',
        () {
      final result = aggregateExerciseProgression(
        exerciseId: 'deadlift',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );
      expect(result.heaviestWeightSeries, isEmpty);
      expect(result.oneRepMaxSeries, isEmpty);
      expect(result.bestSetVolumeSeries, isEmpty);
      expect(result.bestSessionVolumeSeries, isEmpty);
      expect(result.personalRecords, isEmpty);
      expect(result.frequencyLast8Weeks, 0);
    });

    // AD3 — derivePersonalRecords is wired into the aggregator's output.
    test(
        'personalRecords contains first-achieved date per record type, in ASC session order',
        () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 2, 1),
      );

      final byType = {
        for (final r in result.personalRecords) r.recordType: r,
      };

      // Heaviest Weight PR is 95 (s2, later date) — first time 95 was reached.
      expect(byType[ProgressionRecordType.heaviestWeight]!.value, 95.0);
      expect(byType[ProgressionRecordType.heaviestWeight]!.achievedAt,
          _s2.startedAt);

      // 1RM PR is 104.5 (s2).
      expect(
          byType[ProgressionRecordType.oneRepMax]!.value, closeTo(104.5, 0.01));
      expect(
          byType[ProgressionRecordType.oneRepMax]!.achievedAt, _s2.startedAt);

      // Best Set Volume PR is 400 (s1, first session chronologically).
      expect(byType[ProgressionRecordType.bestSetVolume]!.value,
          closeTo(400.0, 0.01));
      expect(byType[ProgressionRecordType.bestSetVolume]!.achievedAt,
          _s1.startedAt);

      // Best Session Volume PR is 1010 (s1).
      expect(byType[ProgressionRecordType.bestSessionVolume]!.value,
          closeTo(1010.0, 0.01));
      expect(byType[ProgressionRecordType.bestSessionVolume]!.achievedAt,
          _s1.startedAt);
    });
  });

  group('derivePersonalRecords [AD3 — pure fn, first-achieved date]', () {
    test('empty series → empty personal records', () {
      expect(derivePersonalRecords(const []), isEmpty);
    });

    test('single point → that point is the record', () {
      final dt = DateTime(2025, 1, 1);
      final records = derivePersonalRecords(
        [ProgressionPoint(date: dt, value: 90.0)],
      );
      expect(records, hasLength(1));
      expect(records.first.value, 90.0);
      expect(records.first.achievedAt, dt);
    });

    test('returns the FIRST date the max value was reached, not the last', () {
      final d1 = DateTime(2025, 1, 1);
      final d2 = DateTime(2025, 1, 10);
      final d3 = DateTime(2025, 1, 20);
      // Max (100) is reached at d2 AND d3 — record must point to d2 (first).
      final records = derivePersonalRecords([
        ProgressionPoint(date: d1, value: 80.0),
        ProgressionPoint(date: d2, value: 100.0),
        ProgressionPoint(date: d3, value: 100.0),
      ]);
      expect(records.first.value, 100.0);
      expect(records.first.achievedAt, d2);
    });

    test('monotonically increasing series → record is the last (highest) point',
        () {
      final d1 = DateTime(2025, 1, 1);
      final d2 = DateTime(2025, 1, 10);
      final d3 = DateTime(2025, 1, 20);
      final records = derivePersonalRecords([
        ProgressionPoint(date: d1, value: 80.0),
        ProgressionPoint(date: d2, value: 90.0),
        ProgressionPoint(date: d3, value: 95.0),
      ]);
      expect(records.first.value, 95.0);
      expect(records.first.achievedAt, d3);
    });
  });

  group('[AD7] periodWindow filtering', () {
    // Sessions on Jan 5 / Jan 10 / Jan 15 (s3/Jan 15 has NO squat logs in the
    // shared fixture). A window covering ONLY Jan 8..20 must exclude Jan 5's
    // session (s1) from every series — only s2 (Jan 10) has squat data left.
    test('sessions outside the period window are excluded from all series', () {
      final window = ChartPeriodWindow(
        currentStart: DateTime(2025, 1, 8),
        currentEnd: DateTime(2025, 1, 20),
        previousStart: DateTime(2024, 12, 1),
        previousEnd: DateTime(2025, 1, 7),
      );

      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 1, 20),
        periodWindow: window,
      );

      expect(result.heaviestWeightSeries.length, 1);
      expect(result.heaviestWeightSeries.single.date, _s2.startedAt);
    });

    // [#379] Boundary tests are self-contained with UTC-flagged fixtures: the
    // shared _sN fixtures use LOCAL midnight, whose Argentina calendar day under
    // `toArgentina` is TZ-dependent (Jan 5 on UTC-3, Jan 4 on UTC) — fatal for a
    // day-boundary assertion. Sessions here are real UTC instants at NOON so
    // their ART day (09:00) is unambiguous, and windows are UTC-flagged exactly
    // as ChartPeriod.windowFor emits.
    test('a window boundary day (currentStart) is INCLUSIVE', () {
      final sA = _session('sA', DateTime.utc(2025, 1, 5, 12)); // ART day Jan 5
      final sB =
          _session('sB', DateTime.utc(2025, 1, 10, 12)); // ART day Jan 10
      final logs = <String, List<SetLog>>{
        'sA': [
          _log(
              sessionId: 'sA',
              exerciseId: 'squat',
              exerciseName: 'S',
              reps: 5,
              weightKg: 80)
        ],
        'sB': [
          _log(
              sessionId: 'sB',
              exerciseId: 'squat',
              exerciseName: 'S',
              reps: 5,
              weightKg: 85)
        ],
      };
      final window = ChartPeriodWindow(
        currentStart: DateTime.utc(2025, 1, 5), // exactly sA's ART day
        currentEnd: DateTime.utc(2025, 1, 20),
        previousStart: DateTime.utc(2024, 12, 1),
        previousEnd: DateTime.utc(2025, 1, 4),
      );

      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: [sB, sA],
        logsBySession: logs,
        now: DateTime.utc(2025, 1, 20, 12),
        periodWindow: window,
      );

      // sA (boundary day) + sB are INCLUDED.
      expect(result.heaviestWeightSeries.length, 2);
    });

    test('a window boundary day (currentEnd) is INCLUSIVE', () {
      final sA = _session('sA', DateTime.utc(2025, 1, 5, 12)); // ART day Jan 5
      final sB =
          _session('sB', DateTime.utc(2025, 1, 10, 12)); // ART day Jan 10
      final logs = <String, List<SetLog>>{
        'sA': [
          _log(
              sessionId: 'sA',
              exerciseId: 'squat',
              exerciseName: 'S',
              reps: 5,
              weightKg: 80)
        ],
        'sB': [
          _log(
              sessionId: 'sB',
              exerciseId: 'squat',
              exerciseName: 'S',
              reps: 5,
              weightKg: 85)
        ],
      };
      final window = ChartPeriodWindow(
        currentStart: DateTime.utc(2025, 1, 1),
        currentEnd: DateTime.utc(2025, 1, 10), // exactly sB's ART day
        previousStart: DateTime.utc(2024, 12, 1),
        previousEnd: DateTime.utc(2024, 12, 31),
      );

      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: [sB, sA],
        logsBySession: logs,
        now: DateTime.utc(2025, 1, 20, 12),
        periodWindow: window,
      );

      // sA + sB (boundary day) are INCLUDED.
      expect(result.heaviestWeightSeries.length, 2);
    });

    test('null periodWindow (default) keeps ALL sessions — backward compat',
        () {
      final result = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 1, 20),
      );

      // s1 + s2 have squat logs; s3's logs list is empty (fixture data).
      expect(result.heaviestWeightSeries.length, 2);
    });

    test(
        'frequencyLast8Weeks is unaffected by periodWindow (still uses the '
        '56-day `now`-relative cutoff, not the period window)', () {
      final window = ChartPeriodWindow(
        currentStart: DateTime(2025, 1, 8),
        currentEnd: DateTime(2025, 1, 20),
        previousStart: DateTime(2024, 12, 1),
        previousEnd: DateTime(2025, 1, 7),
      );

      final withWindow = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 1, 20),
        periodWindow: window,
      );
      final withoutWindow = aggregateExerciseProgression(
        exerciseId: 'squat',
        sessionsDesc: _sessionsDesc,
        logsBySession: _logsBySession,
        now: DateTime(2025, 1, 20),
      );

      // Frecuencia counts sessions regardless of the display period window —
      // it is an independent "last 8 weeks" stat, not filtered by the chart
      // period selector.
      expect(withWindow.frequencyLast8Weeks, withoutWindow.frequencyLast8Weeks);
    });
  });
}

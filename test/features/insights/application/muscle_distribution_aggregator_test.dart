import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/application/muscle_distribution_aggregator.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/insights/domain/radar_axis.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Session _session(
  String id,
  DateTime startedAt, {
  SessionStatus status = SessionStatus.finished,
  int durationMin = 45,
  double totalVolumeKg = 1000,
}) =>
    Session(
      id: id,
      uid: 'athlete1',
      routineId: 'r1',
      routineName: 'Rutina A',
      startedAt: startedAt,
      status: status,
      wasFullyCompleted: status == SessionStatus.finished,
      durationMin: durationMin,
      totalVolumeKg: totalVolumeKg,
    );

SetLog _log(String exerciseId, {int setNumber = 1}) => SetLog(
      id: 'log_${exerciseId}_$setNumber',
      exerciseId: exerciseId,
      exerciseName: exerciseId,
      setNumber: setNumber,
      reps: 8,
      weightKg: 50,
      completedAt: DateTime(2025, 1, 1),
    );

void main() {
  // Fixed "now" so ChartPeriod.last30d windows are deterministic.
  final now = DateTime(2025, 3, 1);
  final window = ChartPeriod.last30d.windowFor(now);

  // [#379] windowFor emits UTC-flagged ART-day boundaries, and the aggregator
  // buckets sessions via `toArgentina(startedAt)` (−3h). A session whose
  // startedAt is EXACTLY a boundary midnight would shift OUT of the window, so
  // place fixtures at NOON of the boundary day (→ 09:00 ART) — comfortably
  // inside, and fully TZ-independent (all UTC-flagged, no device offset).
  final inCurrent = window.currentStart.add(const Duration(hours: 12));
  final inPrevious = window.previousStart.add(const Duration(hours: 12));

  group('aggregateMuscleDistribution', () {
    test('folds setLogs into current/previous RadarAxis buckets', () {
      // currentStart..currentEnd (last30d window ending 2025-03-01)
      final currentSession = _session('s1', inCurrent);
      // previousStart..previousEnd
      final previousSession = _session('s2', inPrevious);

      final result = aggregateMuscleDistribution(
        periodWindow: window,
        sessionsDesc: [currentSession, previousSession],
        logsBySession: {
          's1': [_log('chest'), _log('back'), _log('back', setNumber: 2)],
          's2': [_log('quads')],
        },
        muscleGroupByExerciseId: const {
          'chest': 'chest',
          'back': 'back',
          'quads': 'quads',
        },
      );

      expect(result.currentSetsByAxis[RadarAxis.chest], 1);
      expect(result.currentSetsByAxis[RadarAxis.back], 2);
      expect(result.previousSetsByAxis[RadarAxis.legs], 1);
      expect(result.currentWorkouts, 1);
      expect(result.previousWorkouts, 1);
    });

    test('sums durationMin and totalVolumeKg per window', () {
      final s1 = _session('s1', inCurrent, durationMin: 40, totalVolumeKg: 800);
      final s2 = _session('s2', inCurrent, durationMin: 30, totalVolumeKg: 600);
      final s3 =
          _session('s3', inPrevious, durationMin: 20, totalVolumeKg: 300);

      final result = aggregateMuscleDistribution(
        periodWindow: window,
        sessionsDesc: [s1, s2, s3],
        logsBySession: const {},
        muscleGroupByExerciseId: const {},
      );

      expect(result.currentDurationMin, 70);
      expect(result.currentVolumeKg, 1400);
      expect(result.previousDurationMin, 20);
      expect(result.previousVolumeKg, 300);
    });

    test('excludes non-finished sessions', () {
      final active = _session(
        's1',
        inCurrent,
        status: SessionStatus.active,
      );

      final result = aggregateMuscleDistribution(
        periodWindow: window,
        sessionsDesc: [active],
        logsBySession: {
          's1': [_log('chest')],
        },
        muscleGroupByExerciseId: const {'chest': 'chest'},
      );

      expect(result.currentWorkouts, 0);
      expect(result.currentSetsByAxis, isEmpty);
    });

    test('excludes sessions outside both windows', () {
      final farPast = _session('s1', DateTime(2020, 1, 1));

      final result = aggregateMuscleDistribution(
        periodWindow: window,
        sessionsDesc: [farPast],
        logsBySession: {
          's1': [_log('chest')],
        },
        muscleGroupByExerciseId: const {'chest': 'chest'},
      );

      expect(result.currentWorkouts, 0);
      expect(result.previousWorkouts, 0);
      expect(result.isEmpty, isTrue);
    });

    test('unknown/legacy muscleGroup strings are skipped silently', () {
      final s1 = _session('s1', inCurrent);

      final result = aggregateMuscleDistribution(
        periodWindow: window,
        sessionsDesc: [s1],
        logsBySession: {
          's1': [_log('legacyExercise')],
        },
        muscleGroupByExerciseId: const {'legacyExercise': 'brazos'},
      );

      expect(result.currentSetsByAxis, isEmpty);
      // Still counts as a workout/session even if its sets don't map.
      expect(result.currentWorkouts, 1);
    });

    test('cardio/full_body sets are excluded from radar axes', () {
      final s1 = _session('s1', inCurrent);

      final result = aggregateMuscleDistribution(
        periodWindow: window,
        sessionsDesc: [s1],
        logsBySession: {
          's1': [_log('run'), _log('burpees')],
        },
        muscleGroupByExerciseId: const {
          'run': 'cardio',
          'burpees': 'full_body',
        },
      );

      expect(result.currentSetsByAxis, isEmpty);
      expect(result.currentSets, 2);
    });

    test('totalSets counts every logged set regardless of axis mapping', () {
      final s1 = _session('s1', inCurrent);

      final result = aggregateMuscleDistribution(
        periodWindow: window,
        sessionsDesc: [s1],
        logsBySession: {
          's1': [_log('chest'), _log('unknown')],
        },
        muscleGroupByExerciseId: const {'chest': 'chest'},
      );

      expect(result.currentSets, 2);
    });

    test('no sessions in either window → isEmpty true', () {
      final result = aggregateMuscleDistribution(
        periodWindow: window,
        sessionsDesc: const [],
        logsBySession: const {},
        muscleGroupByExerciseId: const {},
      );

      expect(result.isEmpty, isTrue);
    });
  });
}

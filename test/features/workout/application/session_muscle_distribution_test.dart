import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/features/insights/domain/radar_axis.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_muscle_distribution.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

SetLog _log(
  String exerciseId, {
  int setNumber = 1,
  int reps = 10,
  double weightKg = 50,
}) =>
    SetLog(
      id: '${exerciseId}_$setNumber',
      exerciseId: exerciseId,
      exerciseName: exerciseId,
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      completedAt: DateTime.utc(2026, 7, 20, 12),
    );

Session _session({String routineId = 'r1'}) => Session(
      id: 's1',
      uid: 'u1',
      routineId: routineId,
      routineName: 'Push',
      startedAt: DateTime.utc(2026, 7, 20, 12),
      finishedAt: DateTime.utc(2026, 7, 20, 13),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      durationMin: 60,
      totalVolumeKg: 1000,
    );

// ── Pure aggregator ───────────────────────────────────────────────────────────

void main() {
  group('aggregateSessionMuscleDistribution', () {
    test('varied session → sets and volume folded per radar axis', () {
      final result = aggregateSessionMuscleDistribution(
        setLogs: [
          _log('bench', setNumber: 1, reps: 10, weightKg: 60),
          _log('bench', setNumber: 2, reps: 8, weightKg: 60),
          _log('curl', reps: 12, weightKg: 15),
          _log('pushdown', reps: 12, weightKg: 20),
          _log('squat', reps: 5, weightKg: 100),
          _log('hip-thrust', reps: 10, weightKg: 80),
        ],
        muscleGroupByExerciseId: const {
          'bench': 'chest',
          'curl': 'biceps',
          'pushdown': 'triceps',
          'squat': 'quads',
          'hip-thrust': 'glutes',
        },
      );

      expect(result.setsByAxis, {
        RadarAxis.chest: 2,
        RadarAxis.arms: 2, // biceps + triceps fold into ARMS
        RadarAxis.legs: 2, // quads + glutes fold into LEGS
      });
      expect(result.volumeKgByAxis[RadarAxis.chest], 10 * 60 + 8 * 60);
      expect(result.volumeKgByAxis[RadarAxis.arms], 12 * 15 + 12 * 20);
      expect(result.volumeKgByAxis[RadarAxis.legs], 5 * 100 + 10 * 80);
    });

    test('leg-day session folds every group into the single LEGS axis', () {
      final result = aggregateSessionMuscleDistribution(
        setLogs: [
          _log('squat'),
          _log('leg-curl'),
          _log('hip-thrust'),
          _log('calf-raise'),
        ],
        muscleGroupByExerciseId: const {
          'squat': 'quads',
          'leg-curl': 'hamstrings',
          'hip-thrust': 'glutes',
          'calf-raise': 'calves',
        },
      );

      expect(result.setsByAxis.keys, [RadarAxis.legs]);
      expect(result.setsByAxis[RadarAxis.legs], 4);
    });

    test('empty setLogs → empty maps, no NaN', () {
      final result = aggregateSessionMuscleDistribution(
        setLogs: const [],
        muscleGroupByExerciseId: const {'bench': 'chest'},
      );

      expect(result.setsByAxis, isEmpty);
      expect(result.volumeKgByAxis, isEmpty);
    });

    test(
        'unmapped exerciseId, cardio and full_body are skipped silently — '
        'same exclusion rule as the Insights radar', () {
      final result = aggregateSessionMuscleDistribution(
        setLogs: [
          _log('mystery'), // not in the map at all
          _log('run'), // cardio → toDisplayGroup() null
          _log('burpee'), // full_body → toDisplayGroup() null
          _log('bench'),
        ],
        muscleGroupByExerciseId: const {
          'run': 'cardio',
          'burpee': 'full_body',
          'bench': 'chest',
        },
      );

      expect(result.setsByAxis, {RadarAxis.chest: 1});
    });

    test('legacy Spanish muscleGroup strings are canonicalized (#384)', () {
      final result = aggregateSessionMuscleDistribution(
        setLogs: [_log('viejo')],
        muscleGroupByExerciseId: const {'viejo': 'Pecho'},
      );

      expect(result.setsByAxis, {RadarAxis.chest: 1});
    });

    test('bodyweight sets (0 kg) count the set but add no volume', () {
      final result = aggregateSessionMuscleDistribution(
        setLogs: [
          _log('pull-up', reps: 10, weightKg: 0),
          _log('row', reps: 10, weightKg: 40),
        ],
        muscleGroupByExerciseId: const {'pull-up': 'back', 'row': 'back'},
      );

      expect(result.setsByAxis[RadarAxis.back], 2);
      expect(result.volumeKgByAxis[RadarAxis.back], 400);
    });
  });

  // ── Provider ────────────────────────────────────────────────────────────────

  group('sessionMuscleDistributionProvider', () {
    test('empty uid → empty distribution without reading anything', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = await container.read(
        sessionMuscleDistributionProvider(
          (uid: '', sessionId: 's1'),
        ).future,
      );

      expect(result.setsByAxis, isEmpty);
    });

    test('session not found → empty distribution', () async {
      final container = ProviderContainer(
        overrides: [
          sessionSummaryProvider.overrideWith(
            (ref, key) async => (session: null, setLogs: <SetLog>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        sessionMuscleDistributionProvider(
          (uid: 'u1', sessionId: 'missing'),
        ).future,
      );

      expect(result.setsByAxis, isEmpty);
    });

    test(
        'catalog resolves stock exercises; routine-slot fallback resolves '
        'custom ones — catalog wins on conflict', () async {
      const customRoutine = Routine(
        id: 'r1',
        name: 'Push custom',
        split: null,
        level: ExperienceLevel.beginner,
        days: [
          RoutineDay(
            dayNumber: 1,
            name: 'Día 1',
            slots: [
              RoutineSlot(
                exerciseId: 'custom-press',
                exerciseName: 'Press casero',
                muscleGroup: 'shoulders',
                targetSets: 3,
                targetRepsMin: 8,
                targetRepsMax: 12,
                restSeconds: 60,
              ),
              // Same id as a catalog exercise but a DIFFERENT group — the
              // catalog must win (same precedence as the Insights radar).
              RoutineSlot(
                exerciseId: 'bench',
                exerciseName: 'Press banca',
                muscleGroup: 'back',
                targetSets: 3,
                targetRepsMin: 8,
                targetRepsMax: 12,
                restSeconds: 60,
              ),
            ],
          ),
        ],
        source: RoutineSource.userCreated,
        visibility: RoutineVisibility.private,
      );

      final container = ProviderContainer(
        overrides: [
          sessionSummaryProvider.overrideWith(
            (ref, key) async => (
              session: _session(),
              setLogs: [_log('bench'), _log('custom-press')],
            ),
          ),
          exercisesProvider.overrideWith((ref) async => [
                const Exercise(
                  id: 'bench',
                  name: 'Press banca',
                  muscleGroup: 'chest',
                  category: 'compound',
                ),
              ]),
          visibleRoutineByIdProvider('r1')
              .overrideWith((ref) async => customRoutine),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        sessionMuscleDistributionProvider(
          (uid: 'u1', sessionId: 's1'),
        ).future,
      );

      expect(result.setsByAxis, {
        RadarAxis.chest: 1, // bench via catalog ('chest'), NOT slot ('back')
        RadarAxis.shoulders: 1, // custom-press via routine slot
      });
    });

    test(
        'all-stock session skips the routine-slot fetch entirely — '
        'visibleRoutineByIdProvider is NOT overridden, so touching it would '
        'fail this test', () async {
      final container = ProviderContainer(
        overrides: [
          sessionSummaryProvider.overrideWith(
            (ref, key) async => (
              session: _session(),
              setLogs: [
                _log('bench', setNumber: 1),
                _log('bench', setNumber: 2)
              ],
            ),
          ),
          exercisesProvider.overrideWith((ref) async => [
                const Exercise(
                  id: 'bench',
                  name: 'Press banca',
                  muscleGroup: 'chest',
                  category: 'compound',
                ),
              ]),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        sessionMuscleDistributionProvider(
          (uid: 'u1', sessionId: 's1'),
        ).future,
      );

      expect(result.setsByAxis, {RadarAxis.chest: 2});
    });

    test('a routine that is GONE degrades to catalog-only, never throws',
        () async {
      final container = ProviderContainer(
        overrides: [
          sessionSummaryProvider.overrideWith(
            (ref, key) async => (
              session: _session(routineId: 'deleted'),
              setLogs: [_log('bench'), _log('custom-press')],
            ),
          ),
          exercisesProvider.overrideWith((ref) async => [
                const Exercise(
                  id: 'bench',
                  name: 'Press banca',
                  muscleGroup: 'chest',
                  category: 'compound',
                ),
              ]),
          visibleRoutineByIdProvider('deleted')
              .overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        sessionMuscleDistributionProvider(
          (uid: 'u1', sessionId: 's1'),
        ).future,
      );

      expect(result.setsByAxis, {RadarAxis.chest: 1});
    });
  });
}

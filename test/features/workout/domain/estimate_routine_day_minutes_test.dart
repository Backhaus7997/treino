// Unit tests for `estimateRoutineDayMinutes` (#1562) — realistic duration:
// per-set work floor (setup included), default rest when none is authored,
// no rest after the last set of an exercise, transition between exercises.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_day_duration.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';

RoutineSlot _slot({
  int sets = 4,
  int reps = 9,
  int rest = 90,
  int? durationSeconds,
}) =>
    RoutineSlot(
      exerciseId: 'ex',
      exerciseName: 'Ejercicio',
      muscleGroup: 'chest',
      targetSets: sets,
      targetRepsMin: reps,
      targetRepsMax: reps,
      targetReps: List.filled(sets, reps),
      restSeconds: rest,
      durationSeconds: durationSeconds,
    );

RoutineDay _day(List<RoutineSlot> slots, {int? estimatedMinutes}) => RoutineDay(
      dayNumber: 1,
      name: 'Día 1',
      slots: slots,
      estimatedMinutes: estimatedMinutes,
    );

void main() {
  group('estimateRoutineDayMinutes (#1562)', () {
    test('6 exercises x 4 sets x 9 reps with 90s rest is a realistic session',
        () {
      final est = estimateRoutineDayMinutes(
        _day(List.generate(6, (_) => _slot())),
      );
      // work 24 * 36 = 864; rest 6 * 3 * 90 = 1620; transitions 5 * 75 = 375
      // = 2859 s -> 48 min.
      expect(est.authored, isFalse);
      expect(est.minutes, 48);
    });

    test('reported case: 2 exercises, 8 sets, 2 reps, 0s rest is not ~1 min',
        () {
      final est = estimateRoutineDayMinutes(
        _day([
          _slot(sets: 4, reps: 2, rest: 0),
          _slot(sets: 4, reps: 2, rest: 0),
        ]),
      );
      // work 8 * 25 = 200; rest 6 * 75 = 450; transition 75 = 725 s -> 12 min.
      expect(est.minutes, 12);
      expect(est.minutes!, greaterThanOrEqualTo(8));
    });

    test('durationSeconds replaces the rep-based work time', () {
      final est = estimateRoutineDayMinutes(
        _day([_slot(sets: 3, reps: 1, rest: 60, durationSeconds: 60)]),
      );
      // work 3 * 60 = 180; rest 2 * 60 = 120 = 300 s -> 5 min.
      expect(est.minutes, 5);
    });

    test('authored estimatedMinutes keeps priority', () {
      final est = estimateRoutineDayMinutes(
        _day([_slot()], estimatedMinutes: 30),
      );
      expect(est, (minutes: 30, authored: true));
    });

    test('single exercise, single set: no rest and no transition', () {
      final est = estimateRoutineDayMinutes(
        _day([_slot(sets: 1, reps: 10, rest: 90)]),
      );
      // work max(40, 25) = 40 s -> 1 min.
      expect(est.minutes, 1);
    });

    test('empty day yields no measurable minutes', () {
      expect(
        estimateRoutineDayMinutes(_day(const [])),
        (minutes: null, authored: false),
      );
    });
  });
}

// Unit tests for `estimateRoutineDayMinutes` (#1562) — realistic duration:
// per-set work floor (setup included), default rest when none is authored,
// no rest after the last set of a block, a fixed warm-up per day, a transition
// between blocks, supersets counted as one block, warm-up sets resting half.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_day_duration.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

RoutineSlot _slot({
  int sets = 4,
  int reps = 9,
  int rest = 90,
  int? durationSeconds,
  int? supersetGroup,
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
      supersetGroup: supersetGroup,
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
      // work 24 * 36 = 864; rest 6 * 3 * 90 = 1620; transitions 5 * 120 = 600;
      // warm-up 300 = 3384 s -> 56 min.
      expect(est.authored, isFalse);
      expect(est.minutes, 56);
    });

    group('reported case (ex. 1: 7 x 2 reps, ex. 2: 1 x 2 reps)', () {
      RoutineDay reported(int rest) => _day([
            _slot(sets: 7, reps: 2, rest: rest),
            _slot(sets: 1, reps: 2, rest: rest),
          ]);

      test('with 0s rest the default 75s applies -> ~18 min, not ~1', () {
        // work 8 * 25 = 200; rest 6 * 75 = 450 (ex. 2 has one set: none);
        // transition 120; warm-up 300 = 1070 s -> 18 min.
        expect(estimateRoutineDayMinutes(reported(0)).minutes, 18);
      });

      test('60s authored REPLACES the default, never adds to it -> ~16', () {
        // 200 + 6 * 60 + 120 + 300 = 980 s -> 16 min.
        expect(estimateRoutineDayMinutes(reported(60)).minutes, 16);
      });

      test('90s authored -> ~19', () {
        // 200 + 6 * 90 + 120 + 300 = 1160 s -> 19 min.
        expect(estimateRoutineDayMinutes(reported(90)).minutes, 19);
      });
    });

    test('durationSeconds replaces the rep-based work time', () {
      final est = estimateRoutineDayMinutes(
        _day([_slot(sets: 3, reps: 1, rest: 60, durationSeconds: 60)]),
      );
      // work 3 * 60 = 180; rest 2 * 60 = 120; warm-up 300 = 600 s -> 10 min.
      expect(est.minutes, 10);
    });

    test('authored estimatedMinutes keeps priority', () {
      final est = estimateRoutineDayMinutes(
        _day([_slot()], estimatedMinutes: 30),
      );
      expect(est, (minutes: 30, authored: true));
    });

    test('single exercise, single set: no rest, no transition, warm-up only',
        () {
      final est = estimateRoutineDayMinutes(
        _day([_slot(sets: 1, reps: 10, rest: 90)]),
      );
      // work max(40, 25) = 40; warm-up 300 = 340 s -> 6 min.
      expect(est.minutes, 6);
    });

    test('empty day yields no measurable minutes (no warm-up alone)', () {
      expect(
        estimateRoutineDayMinutes(_day(const [])),
        (minutes: null, authored: false),
      );
    });

    group('supersets', () {
      test('a superset is one block: one rest per round, no inner transition',
          () {
        final est = estimateRoutineDayMinutes(
          _day([
            _slot(sets: 3, reps: 10, rest: 0, supersetGroup: 1),
            _slot(sets: 3, reps: 10, rest: 60, supersetGroup: 1),
            _slot(sets: 3, reps: 10, rest: 90),
          ]),
        );
        // work 9 * 40 = 360; superset A: (3 - 1) * 60 (last slot's rest) = 120;
        // B: 2 * 90 = 180; ONE transition A -> B 120; warm-up 300
        // = 1080 s -> 18 min. Counted per exercise it would be 23.
        expect(est.minutes, 18);
      });

      test('rounds follow the longest member of the superset', () {
        final est = estimateRoutineDayMinutes(
          _day([
            _slot(sets: 4, reps: 10, rest: 90, supersetGroup: 1),
            _slot(sets: 2, reps: 10, rest: 40, supersetGroup: 1),
          ]),
        );
        // work 6 * 40 = 240; rounds 4 -> 3 * 40 = 120; warm-up 300
        // = 660 s -> 11 min.
        expect(est.minutes, 11);
      });

      test('the same group number split by another exercise is two blocks', () {
        final est = estimateRoutineDayMinutes(
          _day([
            _slot(sets: 2, reps: 10, rest: 60, supersetGroup: 1),
            _slot(sets: 2, reps: 10, rest: 60),
            _slot(sets: 2, reps: 10, rest: 60, supersetGroup: 1),
          ]),
        );
        // work 6 * 40 = 240; rest 3 * 60 = 180; transitions 2 * 120 = 240;
        // warm-up 300 = 960 s -> 16 min.
        expect(est.minutes, 16);
      });

      test(
          'an absent exercise is dropped BEFORE cutting blocks, like the player',
          () {
        final est = estimateRoutineDayMinutes(
          _day([
            _slot(sets: 2, reps: 10, rest: 60, supersetGroup: 1),
            _slot(sets: 2, reps: 10, rest: 60).copyWith(activeWeeks: const [1]),
            _slot(sets: 2, reps: 10, rest: 60, supersetGroup: 1),
          ]),
        );
        // Week 0: the middle one is absent, so the session player
        // (session_notifier filters presence first) runs the other two as ONE
        // superset: work 4 * 40 = 160; (2 - 1) * 60 = 60; warm-up 300
        // = 520 s -> 9 min. Cut over the whole day it would read 12.
        expect(est.minutes, 9);
      });
    });

    test('rest after a warm-up set counts half', () {
      const warm = SetSpec(type: SetType.warmup, reps: 10);
      const work = SetSpec(reps: 10);
      final est = estimateRoutineDayMinutes(
        _day([
          _slot(rest: 90).copyWith(sets: const [warm, warm, work, work, work]),
        ]),
      );
      // work 5 * 40 = 200; rest 45 + 45 + 90 + 90 = 270; warm-up 300
      // = 770 s -> 13 min (14 with full rest after the warm-up sets).
      expect(est.minutes, 13);
    });
  });
}

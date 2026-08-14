// Unit tests for `estimateRoutineSessionMinutes` (#639) — the per-session
// figure the routine cards show.
//
// Deliberately built on AUTHORED day durations: the computed branch is already
// exercised through `estimateRoutineDayMinutes`, and pinning the aggregation
// rules (which day counts, when `authored` survives, how it rounds) is what
// this function actually adds.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_day_duration.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';

RoutineSlot _slot() => const RoutineSlot(
      exerciseId: 'bench',
      exerciseName: 'Press de Banca',
      muscleGroup: 'chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
    );

RoutineDay _day({
  int dayNumber = 1,
  int? estimatedMinutes,
  int slots = 1,
}) =>
    RoutineDay(
      dayNumber: dayNumber,
      name: 'Día $dayNumber',
      slots: List.generate(slots, (_) => _slot()),
      estimatedMinutes: estimatedMinutes,
    );

Routine _routine({
  List<RoutineDay> days = const [],
  int? estimatedMinutesPerDay,
}) =>
    Routine(
      id: 'r1',
      name: 'Rutina',
      level: ExperienceLevel.beginner,
      days: days,
      estimatedMinutesPerDay: estimatedMinutesPerDay,
    );

void main() {
  group('estimateRoutineSessionMinutes', () {
    test('the routine-level authored value wins over the days', () {
      final r = _routine(
        estimatedMinutesPerDay: 60,
        days: [_day(estimatedMinutes: 10), _day(dayNumber: 2)],
      );
      expect(estimateRoutineSessionMinutes(r), (minutes: 60, authored: true));
    });

    test('averages the authored days when the routine has no value', () {
      final r = _routine(days: [
        _day(estimatedMinutes: 50),
        _day(dayNumber: 2, estimatedMinutes: 70),
      ]);
      expect(estimateRoutineSessionMinutes(r), (minutes: 60, authored: true));
    });

    test('rounds the average to the nearest minute', () {
      final r = _routine(days: [
        _day(estimatedMinutes: 50),
        _day(dayNumber: 2, estimatedMinutes: 55),
      ]);
      // 52.5 → 53
      expect(estimateRoutineSessionMinutes(r), (minutes: 53, authored: true));
    });

    test('one computed day makes the whole figure an estimate', () {
      final r = _routine(days: [
        _day(estimatedMinutes: 50),
        _day(dayNumber: 2), // no authored value → computed from its slots
      ]);
      final est = estimateRoutineSessionMinutes(r);
      expect(
        est.authored,
        isFalse,
        reason: 'mixing an authored day with a computed one must read as "~"',
      );
      expect(est.minutes, isNotNull);
    });

    test('days that yield nothing are skipped, not counted as zero', () {
      final r = _routine(days: [
        _day(estimatedMinutes: 40),
        _day(dayNumber: 2, slots: 0), // nothing measurable
      ]);
      expect(
        estimateRoutineSessionMinutes(r),
        (minutes: 40, authored: true),
        reason: 'an empty day must not drag the average down to 20',
      );
    });

    test('a routine with no days yields null, never 0', () {
      expect(
        estimateRoutineSessionMinutes(_routine()),
        (minutes: null, authored: false),
      );
    });

    test('a routine whose days are all empty yields null', () {
      final r = _routine(days: [_day(slots: 0), _day(dayNumber: 2, slots: 0)]);
      expect(
        estimateRoutineSessionMinutes(r),
        (minutes: null, authored: false),
      );
    });

    test('a zero routine-level value falls through to the days', () {
      final r = _routine(
        estimatedMinutesPerDay: 0,
        days: [_day(estimatedMinutes: 45)],
      );
      expect(
        estimateRoutineSessionMinutes(r),
        (minutes: 45, authored: true),
        reason: '0 is not a real duration — it must not shadow the days',
      );
    });
  });
}

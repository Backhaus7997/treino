// Tests 3.13 — derivePlanProgress pure function
// SCENARIO-030: no sessions → activeWeek=0 / activeDay=first dayNumber
// SCENARIO-031/032: mid-plan day unlocked after prev complete
// SCENARIO-033: all days of week 0 done → activeWeek=1
// SCENARIO-034: week partially done → still week 0
// SCENARIO-036: all weeks done → planComplete=true

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/plan_progress.dart';

void main() {
  group('derivePlanProgress', () {
    const dayNumbers = [1, 2, 3]; // 1-based

    // ── SCENARIO-030: no sessions ──────────────────────────────────────────
    test('SCENARIO-030: empty completed → activeWeek=0, activeDay=first day',
        () {
      final result = derivePlanProgress({}, dayNumbers, 4);
      expect(result.activeWeek, equals(0));
      expect(result.activeDay, equals(1));
      expect(result.planComplete, isFalse);
      expect(result.completed, isEmpty);
    });

    // ── SCENARIO-031/032: mid-plan, first day of week 0 done ──────────────
    test(
        'SCENARIO-031: day 1 of week 0 done → activeWeek=0, activeDay=2 (next incomplete)',
        () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      final result = derivePlanProgress(completed, dayNumbers, 4);
      expect(result.activeWeek, equals(0));
      expect(result.activeDay, equals(2));
      expect(result.planComplete, isFalse);
    });

    test('SCENARIO-032: days 1+2 of week 0 done → activeWeek=0, activeDay=3',
        () {
      final completed = <CompletedKey>{
        (week: 0, day: 1),
        (week: 0, day: 2),
      };
      final result = derivePlanProgress(completed, dayNumbers, 4);
      expect(result.activeWeek, equals(0));
      expect(result.activeDay, equals(3));
      expect(result.planComplete, isFalse);
    });

    // ── SCENARIO-033: all days of week 0 done → activeWeek=1 ─────────────
    test('SCENARIO-033: all days of week 0 done → activeWeek=1, activeDay=1',
        () {
      final completed = <CompletedKey>{
        (week: 0, day: 1),
        (week: 0, day: 2),
        (week: 0, day: 3),
      };
      final result = derivePlanProgress(completed, dayNumbers, 4);
      expect(result.activeWeek, equals(1));
      expect(result.activeDay, equals(1));
      expect(result.planComplete, isFalse);
    });

    // ── SCENARIO-034: week partially done → still week 0 ─────────────────
    test(
        'SCENARIO-034: only day 1 of week 1 done (but week 0 incomplete) → still week 0',
        () {
      final completed = <CompletedKey>{
        (
          week: 1,
          day: 1
        ), // out-of-order completion, ignored by sequential algo
      };
      final result = derivePlanProgress(completed, dayNumbers, 4);
      // Week 0 has no complete days yet → activeWeek=0, activeDay=1
      expect(result.activeWeek, equals(0));
      expect(result.activeDay, equals(1));
      expect(result.planComplete, isFalse);
    });

    // ── SCENARIO-036: all weeks done → planComplete=true ─────────────────
    test('SCENARIO-036: all weeks and days done → planComplete=true', () {
      final completed = <CompletedKey>{
        for (var w = 0; w < 2; w++)
          for (final d in dayNumbers) (week: w, day: d),
      };
      final result = derivePlanProgress(completed, dayNumbers, 2);
      expect(result.planComplete, isTrue);
      expect(result.activeWeek, equals(1)); // clamped to numWeeks-1
    });

    // ── Edge cases ─────────────────────────────────────────────────────────
    test('single-week plan: no sessions → activeWeek=0, activeDay=first', () {
      final result = derivePlanProgress({}, [1, 2], 1);
      expect(result.activeWeek, equals(0));
      expect(result.activeDay, equals(1));
      expect(result.planComplete, isFalse);
    });

    test('single-week plan: all done → planComplete=true', () {
      final completed = <CompletedKey>{(week: 0, day: 1), (week: 0, day: 2)};
      final result = derivePlanProgress(completed, [1, 2], 1);
      expect(result.planComplete, isTrue);
    });

    test('empty dayNumbers → activeDay defaults to 1 (guard)', () {
      final result = derivePlanProgress({}, [], 4);
      expect(result.activeDay, equals(1));
      expect(result.planComplete, isFalse);
    });
  });
}

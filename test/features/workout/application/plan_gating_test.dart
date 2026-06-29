// Tests for plan_gating after decision A1 (2026-06-29):
//   - isWeekUnlocked and isDayUnlocked always return true (every day of every
//     week is freely accessible to the athlete, including periodized plans).
//   - isStartable reduces to "not already completed" — the historical
//     sequential gate (all prior days/weeks done) was removed.
//
// The pre-A1 history (REQ-PERIOD-033/034 sequential lock, REQ-WPRES-022
// requiredPairs back-compat for the lock) is documented in the file header
// of plan_gating.dart. These tests pin the new always-unlock contract so a
// future regression that reintroduces the lock fails loudly.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/plan_gating.dart';
import 'package:treino/features/workout/application/plan_progress.dart';

void main() {
  const dayNumbers = [1, 2, 3];

  group('isWeekUnlocked — A1 always unlocked', () {
    test('week 0 unlocked with no completions', () {
      expect(isWeekUnlocked(0, {}, dayNumbers), isTrue);
    });

    test('week 1 unlocked even when week 0 is empty', () {
      expect(isWeekUnlocked(1, {}, dayNumbers), isTrue);
    });

    test('week 1 unlocked when week 0 is only partially done', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      expect(isWeekUnlocked(1, completed, dayNumbers), isTrue);
    });

    test('week 5 unlocked even with no prior progress (jumping ahead is OK)',
        () {
      expect(isWeekUnlocked(5, {}, dayNumbers), isTrue);
    });

    test('requiredPairs param ignored — week is unlocked regardless', () {
      // Before A1 this combination would have failed the lock because week 0
      // had required days not satisfied. Now it passes.
      final required = <CompletedKey>{
        (week: 0, day: 1),
        (week: 0, day: 2),
        (week: 0, day: 3),
      };
      expect(
        isWeekUnlocked(1, const {}, dayNumbers, requiredPairs: required),
        isTrue,
      );
    });
  });

  group('isDayUnlocked — A1 always unlocked', () {
    test('day 1 of week 0 unlocked with no completions', () {
      expect(isDayUnlocked(0, 1, {}, dayNumbers), isTrue);
    });

    test('day 3 of week 0 unlocked even when day 1 and day 2 are NOT done', () {
      // The motivating real-world case: athlete missed Día 1, opens Día 3.
      // Old logic locked it; A1 allows it.
      expect(isDayUnlocked(0, 3, const {}, dayNumbers), isTrue);
    });

    test('day in week 2 unlocked even when no prior week is done', () {
      expect(isDayUnlocked(2, 2, const {}, dayNumbers), isTrue);
    });
  });

  group('isStartable — only blocks already-completed (week, day)', () {
    test('startable when not completed', () {
      expect(isStartable(0, 1, const {}, dayNumbers), isTrue);
    });

    test('NOT startable when the same (week, day) is already completed', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      expect(isStartable(0, 1, completed, dayNumbers), isFalse);
    });

    test('completing day 1 does NOT block day 2 from starting', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      expect(isStartable(0, 2, completed, dayNumbers), isTrue);
    });

    test(
        'jumping to week 5 with zero progress is startable (no week lock '
        'anymore)', () {
      expect(isStartable(5, 1, const {}, dayNumbers), isTrue);
    });

    test(
        'completing all of week 0 does NOT change startability of week 1 days '
        '— they were already startable, still are', () {
      final completed = <CompletedKey>{
        (week: 0, day: 1),
        (week: 0, day: 2),
        (week: 0, day: 3),
      };
      expect(isStartable(1, 1, completed, dayNumbers), isTrue);
      expect(isStartable(1, 2, completed, dayNumbers), isTrue);
      expect(isStartable(1, 3, completed, dayNumbers), isTrue);
    });

    test(
        'requiredPairs param is accepted but irrelevant — only completion '
        'blocks startability', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      // Day 1 completed → not startable.
      expect(
        isStartable(0, 1, completed, dayNumbers,
            requiredPairs: const {(week: 0, day: 1)}),
        isFalse,
      );
      // Day 2 not completed → startable, no matter the requiredPairs map.
      expect(
        isStartable(0, 2, completed, dayNumbers,
            requiredPairs: const {(week: 0, day: 1)}),
        isTrue,
      );
    });
  });
}

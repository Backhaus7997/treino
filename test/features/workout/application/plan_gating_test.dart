// Tests 3.14 — isWeekUnlocked, isDayUnlocked, isStartable truth tables
// SCENARIO-038: numWeeks==1 callers bypass gating (all days always startable)

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/plan_gating.dart';
import 'package:treino/features/workout/application/plan_progress.dart';

void main() {
  const dayNumbers = [1, 2, 3];

  group('isWeekUnlocked', () {
    test('week 0 is always unlocked', () {
      expect(isWeekUnlocked(0, {}, dayNumbers), isTrue);
    });

    test('week 1 locked when week 0 has no completions', () {
      expect(isWeekUnlocked(1, {}, dayNumbers), isFalse);
    });

    test('week 1 locked when week 0 only partially done', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      expect(isWeekUnlocked(1, completed, dayNumbers), isFalse);
    });

    test('week 1 unlocked when all days of week 0 done', () {
      final completed = <CompletedKey>{
        (week: 0, day: 1),
        (week: 0, day: 2),
        (week: 0, day: 3),
      };
      expect(isWeekUnlocked(1, completed, dayNumbers), isTrue);
    });

    test('week 2 locked when week 1 is only partially done (1 of 3 days)', () {
      final completed = <CompletedKey>{
        (week: 0, day: 1),
        (week: 0, day: 2),
        (week: 0, day: 3),
        // week 1 incomplete — only day 1 done
        (week: 1, day: 1),
      };
      // week 1 not fully done → week 2 locked
      expect(isWeekUnlocked(2, completed, dayNumbers), isFalse);
    });
  });

  group('isDayUnlocked', () {
    test('day 1 of week 0 always unlocked (first day, first week)', () {
      expect(isDayUnlocked(0, 1, {}, dayNumbers), isTrue);
    });

    test('day 2 of week 0 locked when day 1 not done', () {
      expect(isDayUnlocked(0, 2, {}, dayNumbers), isFalse);
    });

    test('day 2 of week 0 unlocked when day 1 done', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      expect(isDayUnlocked(0, 2, completed, dayNumbers), isTrue);
    });

    test('day 3 of week 0 locked when only day 1 done', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      expect(isDayUnlocked(0, 3, completed, dayNumbers), isFalse);
    });

    test('day 1 of week 1 locked when week 0 not complete', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      expect(isDayUnlocked(1, 1, completed, dayNumbers), isFalse);
    });

    test('day 1 of week 1 unlocked when all week 0 done', () {
      final completed = <CompletedKey>{
        (week: 0, day: 1),
        (week: 0, day: 2),
        (week: 0, day: 3),
      };
      expect(isDayUnlocked(1, 1, completed, dayNumbers), isTrue);
    });
  });

  group('isStartable', () {
    test('first day of first week startable with no completions', () {
      expect(isStartable(0, 1, {}, dayNumbers), isTrue);
    });

    test('already-completed day NOT startable', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      expect(isStartable(0, 1, completed, dayNumbers), isFalse);
    });

    test('locked day NOT startable', () {
      expect(isStartable(0, 2, {}, dayNumbers), isFalse);
    });

    test('second day startable after first done', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      expect(isStartable(0, 2, completed, dayNumbers), isTrue);
    });

    test('first day of week 1 NOT startable when week 0 incomplete', () {
      final completed = <CompletedKey>{(week: 0, day: 1)};
      expect(isStartable(1, 1, completed, dayNumbers), isFalse);
    });
  });

  // SCENARIO-038: numWeeks==1 bypass — detail screen bypasses gating entirely.
  // We test that for week 0 / day 1 the gating fns always return true (which is
  // what the screen would call for single-week plans IF it called them at all,
  // but the screen branches at numWeeks>1 so these fns are NEVER called for
  // single-week plans — this is the safety net).
  group('SCENARIO-038: numWeeks==1 gating always passes for week 0', () {
    const singleDays = [1, 2, 3];

    test('isWeekUnlocked(0) is always true', () {
      expect(isWeekUnlocked(0, {}, singleDays), isTrue);
    });

    test('isDayUnlocked(0,1) is always true (no prior days)', () {
      expect(isDayUnlocked(0, 1, {}, singleDays), isTrue);
    });

    test('isStartable(0,1) with no completions is true', () {
      expect(isStartable(0, 1, {}, singleDays), isTrue);
    });
  });
}

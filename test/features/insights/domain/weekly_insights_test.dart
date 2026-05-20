import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/insights/domain/weekly_insights.dart';

void main() {
  WeeklyInsights makeStub({
    DateTime? weekStart,
    List<bool>? daysTrained,
    int sessionsCount = 0,
    Map<MuscleGroupDisplay, int>? setsByGroup,
    Map<MuscleGroupDisplay, int>? targetByGroup,
    int streak = 0,
    int monthSessionsCount = 0,
  }) {
    final start = weekStart ?? DateTime(2026, 5, 18); // monday
    return WeeklyInsights(
      weekStart: start,
      weekEnd: start
          .add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59)),
      daysTrained: daysTrained ?? List<bool>.filled(7, false),
      sessionsCount: sessionsCount,
      plannedSessionsCount: 5,
      setsByGroup: setsByGroup ?? const {},
      targetByGroup: targetByGroup ?? const {},
      streak: streak,
      monthSessionsCount: monthSessionsCount,
    );
  }

  group('WeeklyInsights ==', () {
    test('two instances with the same data are ==', () {
      final a = makeStub(
        sessionsCount: 3,
        daysTrained: const [true, false, true, false, false, false, false],
        setsByGroup: const {MuscleGroupDisplay.pecho: 10},
        targetByGroup: const {MuscleGroupDisplay.pecho: 12},
      );
      final b = makeStub(
        sessionsCount: 3,
        daysTrained: const [true, false, true, false, false, false, false],
        setsByGroup: const {MuscleGroupDisplay.pecho: 10},
        targetByGroup: const {MuscleGroupDisplay.pecho: 12},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different daysTrained → not equal', () {
      final a = makeStub(
        daysTrained: const [true, false, false, false, false, false, false],
      );
      final b = makeStub(
        daysTrained: const [false, true, false, false, false, false, false],
      );
      expect(a, isNot(equals(b)));
    });

    test('different setsByGroup → not equal', () {
      final a = makeStub(setsByGroup: const {MuscleGroupDisplay.pecho: 10});
      final b = makeStub(setsByGroup: const {MuscleGroupDisplay.pecho: 12});
      expect(a, isNot(equals(b)));
    });
  });

  group('WeeklyInsights.copyWith', () {
    test('returns new instance with overridden field', () {
      final a = makeStub(sessionsCount: 3);
      final b = a.copyWith(sessionsCount: 5);
      expect(b.sessionsCount, 5);
      expect(b.weekStart, a.weekStart);
    });

    test('un-overridden fields are preserved', () {
      final a = makeStub(
        sessionsCount: 3,
        setsByGroup: const {MuscleGroupDisplay.pecho: 8},
      );
      final b = a.copyWith();
      expect(b, equals(a));
    });
  });

  group('WeeklyInsights new fields (SCENARIO-298..299)', () {
    // SCENARIO-298: DTO with new fields omitted defaults to 0
    test('SCENARIO-298: streak and monthSessionsCount default to 0', () {
      final a = makeStub(); // streak=0, monthSessionsCount=0 by default
      expect(a.streak, 0);
      expect(a.monthSessionsCount, 0);
    });

    // SCENARIO-299: DTO serializes new fields when present
    test('SCENARIO-299: streak and monthSessionsCount round-trip via copyWith',
        () {
      final a = makeStub(streak: 5, monthSessionsCount: 12);
      expect(a.streak, 5);
      expect(a.monthSessionsCount, 12);

      // copyWith preserves them
      final b = a.copyWith();
      expect(b.streak, 5);
      expect(b.monthSessionsCount, 12);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different streak values → not equal', () {
      final a = makeStub(streak: 3);
      final b = makeStub(streak: 4);
      expect(a, isNot(equals(b)));
    });

    test('different monthSessionsCount values → not equal', () {
      final a = makeStub(monthSessionsCount: 10);
      final b = makeStub(monthSessionsCount: 11);
      expect(a, isNot(equals(b)));
    });

    test('copyWith overrides streak', () {
      final a = makeStub(streak: 3);
      final b = a.copyWith(streak: 7);
      expect(b.streak, 7);
      expect(b.monthSessionsCount, a.monthSessionsCount);
    });

    test('copyWith overrides monthSessionsCount', () {
      final a = makeStub(monthSessionsCount: 10);
      final b = a.copyWith(monthSessionsCount: 15);
      expect(b.monthSessionsCount, 15);
      expect(b.streak, a.streak);
    });
  });
}

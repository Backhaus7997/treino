import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/domain/day_insights.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';

void main() {
  group('DayInsights', () {
    test('SCENARIO-DAY-01: isEmpty is true when sessionsCount is 0', () {
      final insights = DayInsights(
        day: DateTime(2026, 7, 6),
        setsByGroup: const {},
        sessionsCount: 0,
      );
      expect(insights.isEmpty, isTrue);
    });

    test('SCENARIO-DAY-02: isEmpty is false when sessionsCount > 0', () {
      final insights = DayInsights(
        day: DateTime(2026, 7, 6),
        setsByGroup: const {MuscleGroupDisplay.pecho: 3},
        sessionsCount: 1,
      );
      expect(insights.isEmpty, isFalse);
    });

    test('SCENARIO-DAY-03: equality compares day + setsByGroup + sessionsCount',
        () {
      final a = DayInsights(
        day: DateTime(2026, 7, 6),
        setsByGroup: const {MuscleGroupDisplay.pecho: 3},
        sessionsCount: 1,
      );
      final b = DayInsights(
        day: DateTime(2026, 7, 6),
        setsByGroup: const {MuscleGroupDisplay.pecho: 3},
        sessionsCount: 1,
      );
      final differentDay = DayInsights(
        day: DateTime(2026, 7, 7),
        setsByGroup: const {MuscleGroupDisplay.pecho: 3},
        sessionsCount: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(differentDay)));
    });
  });
}

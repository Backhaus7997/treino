import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/home/widgets/esta_semana_card.dart';

// Unit tests for the ISO 8601 week-number helper used by the "Esta Semana"
// card header ("SEM N · MMM"). Guards the year-boundary edge cases where the
// naive formula returned 0 (-> "SEM 0") or overflowed to 53.
void main() {
  group('isoWeekNumber — ISO 8601 year boundaries', () {
    test('Jan 1 dates that belong to the previous year\'s last week', () {
      // Regression: these all returned 0 with the naive formula.
      expect(isoWeekNumber(DateTime(2027, 1, 1)), 53); // Fri -> 2026 W53
      expect(isoWeekNumber(DateTime(2021, 1, 1)), 53); // Fri -> 2020 W53
      expect(isoWeekNumber(DateTime(2023, 1, 1)), 52); // Sun -> 2022 W52
    });

    test('always within 1..53 (never 0)', () {
      final week = isoWeekNumber(DateTime(2023, 1, 1));
      expect(week, greaterThanOrEqualTo(1));
      expect(week, lessThanOrEqualTo(53));
    });

    test('late-December dates that belong to the next year\'s week 1', () {
      expect(isoWeekNumber(DateTime(2024, 12, 30)), 1); // Mon -> 2025 W1
    });

    test('known reference values', () {
      expect(isoWeekNumber(DateTime(2026, 1, 1)), 1); // Thu, starts W1
      expect(isoWeekNumber(DateTime(2020, 12, 31)), 53); // 2020 has 53 weeks
      expect(isoWeekNumber(DateTime(2015, 12, 31)), 53);
      expect(isoWeekNumber(DateTime(2016, 1, 4)), 1);
      expect(isoWeekNumber(DateTime(2026, 6, 16)), 25);
    });
  });

  group('isoWeeksInYear', () {
    test('years with 53 ISO weeks', () {
      expect(isoWeeksInYear(2020), 53);
      expect(isoWeeksInYear(2026), 53);
    });

    test('years with 52 ISO weeks', () {
      expect(isoWeeksInYear(2023), 52);
      expect(isoWeeksInYear(2022), 52);
    });
  });
}

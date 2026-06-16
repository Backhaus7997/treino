import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';

// Regression for the weekly double-billing bug across the ISO-year boundary.
//
// `isoWeekPeriodKey` must use the ISO week-OWNING year (the year of the
// Thursday in the same ISO week), NOT the calendar year. Otherwise the same
// physical ISO week gets two different `YYYY-Www` keys on either side of New
// Year, and the "already paid this week" check fails -> the athlete is charged
// a second time.
void main() {
  group('isoWeekPeriodKey — ISO-year boundary', () {
    test('same physical ISO week maps to one key across New Year', () {
      // ISO week Mon 2026-12-28 .. Sun 2027-01-03 is ISO week 53 of 2026.
      // Thu 2026-12-31 and Fri 2027-01-01 are in that same week.
      const expected = '2026-W53';
      expect(isoWeekPeriodKey(DateTime.utc(2026, 12, 31)), expected); // Thu
      expect(isoWeekPeriodKey(DateTime.utc(2027, 1, 1)), expected); // Fri
      expect(isoWeekPeriodKey(DateTime.utc(2027, 1, 3)), expected); // Sun
    });

    test('late-December dates belonging to next year\'s week 1', () {
      // Mon 2024-12-30 is ISO week 1 of 2025.
      expect(isoWeekPeriodKey(DateTime.utc(2024, 12, 30)), '2025-W01');
    });

    test('week number is zero-padded to two digits', () {
      // Thu 2026-01-01 starts ISO week 1 of 2026.
      expect(isoWeekPeriodKey(DateTime.utc(2026, 1, 1)), '2026-W01');
    });

    test('known mid-year reference value', () {
      // 2026-06-16 is ISO week 25 of 2026.
      expect(isoWeekPeriodKey(DateTime.utc(2026, 6, 16)), '2026-W25');
    });
  });
}

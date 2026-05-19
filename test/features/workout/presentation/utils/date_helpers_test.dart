// Tests for formatSessionDate helper — SCENARIO-379, SCENARIO-380
// REQ-HIST-021
// TDD RED: file compiles but formatSessionDate is undefined → tests fail with Error.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/utils/date_helpers.dart';

void main() {
  group('formatSessionDate', () {
    // SCENARIO-379: canonical mockup example
    test('canonical example: 2025-11-26 (Wednesday) → "Mié 26 nov"', () {
      final date = DateTime(2025, 11, 26);
      expect(formatSessionDate(date), equals('Mié 26 nov'));
    });

    // Weekday mappings: 1=Lun … 7=Dom
    test('Monday (weekday=1) → starts with "Lun"', () {
      // 2025-11-24 is a Monday
      final date = DateTime(2025, 11, 24);
      expect(formatSessionDate(date), startsWith('Lun'));
    });

    test('Tuesday (weekday=2) → starts with "Mar"', () {
      // 2025-11-25 is a Tuesday
      final date = DateTime(2025, 11, 25);
      expect(formatSessionDate(date), startsWith('Mar'));
    });

    test('Thursday (weekday=4) → starts with "Jue"', () {
      // 2025-11-27 is a Thursday
      final date = DateTime(2025, 11, 27);
      expect(formatSessionDate(date), startsWith('Jue'));
    });

    test('Friday (weekday=5) → starts with "Vie"', () {
      // 2025-11-28 is a Friday
      final date = DateTime(2025, 11, 28);
      expect(formatSessionDate(date), startsWith('Vie'));
    });

    test('Saturday (weekday=6) → starts with "Sáb"', () {
      // 2025-11-29 is a Saturday
      final date = DateTime(2025, 11, 29);
      expect(formatSessionDate(date), startsWith('Sáb'));
    });

    test('Sunday (weekday=7) → starts with "Dom"', () {
      // 2025-11-30 is a Sunday
      final date = DateTime(2025, 11, 30);
      expect(formatSessionDate(date), startsWith('Dom'));
    });

    // Month mapping checks
    test('January → ends with "ene"', () {
      // 2025-01-06 is a Monday
      final date = DateTime(2025, 1, 6);
      expect(formatSessionDate(date), endsWith('ene'));
    });

    test('March → ends with "mar"', () {
      // 2025-03-03 is a Monday
      final date = DateTime(2025, 3, 3);
      expect(formatSessionDate(date), endsWith('mar'));
    });

    test('December → ends with "dic"', () {
      // 2025-12-01 is a Monday
      final date = DateTime(2025, 12, 1);
      expect(formatSessionDate(date), endsWith('dic'));
    });

    // Single-digit day — no zero-padding
    test('single-digit day has no zero-padding: 2025-03-07 → "Vie 7 mar"', () {
      final date = DateTime(2025, 3, 7);
      expect(formatSessionDate(date), equals('Vie 7 mar'));
    });

    // SCENARIO-380: now parameter does not affect output
    test('now parameter does not affect output (SCENARIO-380)', () {
      final date = DateTime(2025, 11, 26);
      final result1 = formatSessionDate(date);
      final result2 = formatSessionDate(date, now: DateTime(2025, 11, 27));
      final result3 = formatSessionDate(date, now: DateTime(2020, 1, 1));
      expect(result1, equals(result2));
      expect(result1, equals(result3));
    });
  });
}

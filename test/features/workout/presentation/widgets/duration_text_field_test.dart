import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/widgets/duration_text_field.dart';

/// Pure unit tests for the duration formatting helpers.
/// Widget pump tests are omitted here because DurationTextField depends on
/// AppPalette (full theme) — those belong in golden / integration tests.
void main() {
  group('digitStringToSeconds', () {
    test('"" → 0', () => expect(digitStringToSeconds(''), equals(0)));
    test('"1" → 1 s (00:01)',
        () => expect(digitStringToSeconds('1'), equals(1)));
    test('"10" → 10 s (00:10)',
        () => expect(digitStringToSeconds('10'), equals(10)));
    test('"130" → 90 s (01:30)',
        () => expect(digitStringToSeconds('130'), equals(90)));
    test('"0140" → 100 s (01:40)',
        () => expect(digitStringToSeconds('0140'), equals(100)));
    test('"9959" → 5999 s (99:59)',
        () => expect(digitStringToSeconds('9959'), equals(5999)));
    // Overflow: minutes clamped to 99 (ignore leading digit if >4 chars).
    test('"99999" → last 4 digits "9999" → 99:59 = 5999',
        () => expect(digitStringToSeconds('99999'), equals(5999)));
  });

  group('secondsToMmss', () {
    test('0 → "00:00"', () => expect(secondsToMmss(0), equals('00:00')));
    test('1 → "00:01"', () => expect(secondsToMmss(1), equals('00:01')));
    test('10 → "00:10"', () => expect(secondsToMmss(10), equals('00:10')));
    test('90 → "01:30"', () => expect(secondsToMmss(90), equals('01:30')));
    test('100 → "01:40"', () => expect(secondsToMmss(100), equals('01:40')));
    test('5999 → "99:59"', () => expect(secondsToMmss(5999), equals('99:59')));
  });

  group('round-trip: digitStringToSeconds ↔ secondsToMmss', () {
    void roundTrip(String digits, int expectedSeconds, String expectedDisplay) {
      final seconds = digitStringToSeconds(digits);
      expect(seconds, equals(expectedSeconds),
          reason: 'digits "$digits" should give $expectedSeconds s');
      final display = secondsToMmss(seconds);
      expect(display, equals(expectedDisplay),
          reason: '$expectedSeconds s should display as "$expectedDisplay"');
    }

    test('"1" → 1 s → "00:01"', () => roundTrip('1', 1, '00:01'));
    test('"10" → 10 s → "00:10"', () => roundTrip('10', 10, '00:10'));
    test('"130" → 90 s → "01:30"', () => roundTrip('130', 90, '01:30'));
    test('"0140" → 100 s → "01:40"', () => roundTrip('0140', 100, '01:40'));
  });
}

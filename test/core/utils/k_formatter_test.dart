import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/k_formatter.dart';

void main() {
  group('kFormat (SCENARIO-313..315)', () {
    // SCENARIO-313: kFormat for value >= 1000
    test('SCENARIO-313: value >= 1000 → formatted as Xk', () {
      expect(kFormat(1000), '1k');
      expect(kFormat(1500),
          '2k'); // 1500/1000 = 1.5 → rounded to 2? NO — toStringAsFixed(0) rounds
      expect(kFormat(92000), '92k');
    });

    // SCENARIO-314: kFormat for value < 1000
    test('SCENARIO-314: value < 1000 → integer string', () {
      expect(kFormat(0), '0');
      expect(kFormat(999), '999');
      expect(kFormat(500), '500');
    });

    // SCENARIO-315: kFormat boundary at exactly 1000
    test('SCENARIO-315: exactly 1000 → 1k', () {
      expect(kFormat(1000), '1k');
    });

    // Extra boundaries from design (number_format_test coverage)
    test('boundary: 999 → integer', () {
      expect(kFormat(999), '999');
    });

    test('boundary: 1499 → 1k (floor/toStringAsFixed(0) truncates .499)', () {
      // (1499/1000).toStringAsFixed(0) → Dart rounds 1.499 → '1'
      expect(kFormat(1499), '1k');
    });

    test('boundary: 1500 → 2k (toStringAsFixed(0) rounds .5 up)', () {
      expect(kFormat(1500), '2k');
    });

    test('large value: 92000 → 92k', () {
      expect(kFormat(92000), '92k');
    });

    test('defensive: 0 → 0', () {
      expect(kFormat(0), '0');
    });

    test('defensive: negative values → integer string (no k suffix)', () {
      expect(kFormat(-1), '-1');
    });
  });

  group('kFormatMagnitude (never overstates — volume bug fix)', () {
    test('regression: 1500 → 1.5k (NOT 2k, must not inflate volume)', () {
      // kFormat(1500) rounds up to '2k'; volume headlines must not overstate.
      expect(kFormatMagnitude(1500), '1.5k');
      expect(kFormatMagnitude(1500), isNot('2k'));
    });

    test('floors toward zero — never higher than the real value', () {
      expect(kFormatMagnitude(1499), '1.4k'); // not '1.5k'
      expect(kFormatMagnitude(1999), '1.9k'); // not '2.0k'
    });

    test('boundary: exactly 1000 → 1.0k', () {
      expect(kFormatMagnitude(1000), '1.0k');
    });

    test('value < 1000 → integer string', () {
      expect(kFormatMagnitude(0), '0');
      expect(kFormatMagnitude(999), '999');
    });

    test('large value: 92000 → 92.0k', () {
      expect(kFormatMagnitude(92000), '92.0k');
    });

    test('defensive: negative values → integer string (no k suffix)', () {
      expect(kFormatMagnitude(-1), '-1');
    });
  });
}

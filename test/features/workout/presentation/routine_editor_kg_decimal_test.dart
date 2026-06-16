// Regression tests for decimal KG entry in the routine editor set-row.
// Covers the round-trip used by the KG field: parse text -> double, and
// seed double -> display text. SetSpec.weightKg is a double, so fractional
// loads (e.g. 17.5 kg) must be authorable and survive a reopen.
//
// Bug fixed: the KG field used int.tryParse + toStringAsFixed(0), which
// cleared "17.5" on entry and rendered an existing 17.5 kg slot as "17".

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';

void main() {
  group('parseEditorWeight', () {
    test('parses a decimal weight', () {
      expect(parseEditorWeight('17.5'), 17.5);
    });

    test('accepts comma as the decimal separator (iOS keypad)', () {
      expect(parseEditorWeight('17,5'), 17.5);
    });

    test('parses an integer weight as a double', () {
      expect(parseEditorWeight('60'), 60.0);
    });

    test('empty or invalid text → null', () {
      expect(parseEditorWeight(''), isNull);
      expect(parseEditorWeight('abc'), isNull);
    });
  });

  group('formatEditorWeight', () {
    test('keeps the fractional part of a decimal weight', () {
      expect(formatEditorWeight(17.5), '17.5');
    });

    test('drops the decimal for an integer weight', () {
      expect(formatEditorWeight(60.0), '60');
    });

    test('null → empty string', () {
      expect(formatEditorWeight(null), '');
    });
  });

  group('round-trip (seed → field → parse)', () {
    test('a 17.5 kg slot reopens as 17.5 and parses back to 17.5', () {
      const original = 17.5;
      final seeded = formatEditorWeight(original); // what the field displays
      expect(seeded, '17.5');
      expect(parseEditorWeight(seeded), original); // what gets saved on edit
    });
  });
}

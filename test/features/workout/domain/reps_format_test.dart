import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/reps_format.dart';

void main() {
  group('parseReps', () {
    test('single number returns one-element list', () {
      expect(parseReps('10'), equals([10]));
    });

    test('dash-separated sequence', () {
      expect(parseReps('6-8-10'), equals([6, 8, 10]));
    });

    test('spaces around dashes are tolerated', () {
      expect(parseReps('6 - 8 - 10'), equals([6, 8, 10]));
    });

    test('slash separator is tolerated', () {
      expect(parseReps('10/8/6'), equals([10, 8, 6]));
    });

    test('whitespace-only separator', () {
      expect(parseReps('6 8 10'), equals([6, 8, 10]));
    });

    test('empty string returns empty list', () {
      expect(parseReps(''), equals([]));
    });

    test('whitespace-only string returns empty list', () {
      expect(parseReps('   '), equals([]));
    });

    test('invalid (non-numeric) token returns empty list', () {
      expect(parseReps('abc'), equals([]));
    });

    test('mixed valid/invalid tokens returns empty list', () {
      expect(parseReps('6-abc-10'), equals([]));
    });

    test('zero is valid (0 reps)', () {
      expect(parseReps('0'), equals([0]));
    });

    test('single-element sequence with spaces', () {
      expect(parseReps('  12  '), equals([12]));
    });

    test('long sequence', () {
      expect(parseReps('5-5-5-5'), equals([5, 5, 5, 5]));
    });
  });

  group('formatReps', () {
    test('empty list → empty string', () {
      expect(formatReps([]), equals(''));
    });

    test('single-element list → plain number', () {
      expect(formatReps([10]), equals('10'));
    });

    test('multi-element list → dash-joined', () {
      expect(formatReps([6, 8, 10]), equals('6-8-10'));
    });

    test('round-trip: parseReps(formatReps) is identity for valid input', () {
      final original = [6, 8, 10];
      expect(parseReps(formatReps(original)), equals(original));
    });

    test('round-trip: formatReps(parseReps) is identity for valid string', () {
      const s = '6-8-10';
      expect(formatReps(parseReps(s)), equals(s));
    });
  });
}

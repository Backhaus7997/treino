import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/gym_name.dart';

void main() {
  group('gymNameFromId', () {
    test('SCENARIO-206: null → empty string (hide subtitle)', () {
      expect(gymNameFromId(null), equals(''));
    });

    test('SCENARIO-207: empty string → empty string (defensive)', () {
      expect(gymNameFromId(''), equals(''));
    });

    test('SCENARIO-208: kNoGymId sentinel → empty string', () {
      expect(gymNameFromId('no-gym'), equals(''));
    });

    test('SCENARIO-209: known id → resolved display name', () {
      expect(gymNameFromId('smart-fit-palermo'), equals('SMART FIT'));
      expect(gymNameFromId('sportclub-belgrano'), equals('SPORTCLUB'));
      expect(gymNameFromId('megatlon-recoleta'), equals('MEGATLON'));
    });

    test('SCENARIO-210: unknown id → toUpperCase fallback', () {
      expect(gymNameFromId('crossfit-pilar'), equals('CROSSFIT-PILAR'));
    });
  });
}

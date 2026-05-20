import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';

void main() {
  // SCENARIO-409: TrainerSpecialty has exactly 10 values.
  // SCENARIO-410: fromString case-insensitive + null for unknown.
  group('TrainerSpecialty', () {
    test('SCENARIO-409: enum has exactly 10 values', () {
      expect(TrainerSpecialty.values.length, equals(10));
    });

    test('SCENARIO-409: all expected specialties are present', () {
      const expectedWireValues = {
        'powerlifting',
        'crossfit',
        'bodybuilding',
        'hipertrofia',
        'wellness',
        'kinesiologia',
        'funcional',
        'running',
        'yoga',
        'calistenia',
      };
      final wireValues = TrainerSpecialty.values
          .map((s) => TrainerSpecialtyX.toWire(s))
          .toSet();
      expect(wireValues, equals(expectedWireValues));
    });

    group('TrainerSpecialty.fromString', () {
      test('SCENARIO-410: known wire value returns correct enum', () {
        expect(trainerSpecialtyFromString('powerlifting'),
            equals(TrainerSpecialty.powerlifting));
        expect(
            trainerSpecialtyFromString('yoga'), equals(TrainerSpecialty.yoga));
        expect(trainerSpecialtyFromString('hipertrofia'),
            equals(TrainerSpecialty.hipertrofia));
      });

      test('SCENARIO-410: case-insensitive lookup', () {
        expect(trainerSpecialtyFromString('Hipertrofia'),
            equals(TrainerSpecialty.hipertrofia));
        expect(
            trainerSpecialtyFromString('YOGA'), equals(TrainerSpecialty.yoga));
        expect(trainerSpecialtyFromString('CrossFit'),
            equals(TrainerSpecialty.crossfit));
      });

      test('SCENARIO-410: unknown string returns null (per D13)', () {
        expect(trainerSpecialtyFromString('unknown'), isNull);
        expect(trainerSpecialtyFromString(''), isNull);
        expect(trainerSpecialtyFromString('otros'), isNull);
        expect(trainerSpecialtyFromString('legacy_free_form_string'), isNull);
      });

      test('all wire values round-trip via trainerSpecialtyFromString', () {
        for (final specialty in TrainerSpecialty.values) {
          final wire = TrainerSpecialtyX.toWire(specialty);
          expect(trainerSpecialtyFromString(wire), equals(specialty));
        }
      });
    });
  });
}

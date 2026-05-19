import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';

void main() {
  group('MuscleGroupDisplay.displayLabel', () {
    test('returns UPPERCASE Spanish label for each value', () {
      expect(MuscleGroupDisplay.pecho.displayLabel, 'PECHO');
      expect(MuscleGroupDisplay.espalda.displayLabel, 'ESPALDA');
      expect(MuscleGroupDisplay.piernas.displayLabel, 'PIERNAS');
      expect(MuscleGroupDisplay.brazos.displayLabel, 'BRAZOS');
      expect(MuscleGroupDisplay.hombros.displayLabel, 'HOMBROS');
      expect(MuscleGroupDisplay.core.displayLabel, 'CORE');
    });
  });

  group('MuscleGroupDisplay.displayOrder', () {
    test('contains the 6 values in mockup order', () {
      expect(MuscleGroupDisplay.displayOrder, [
        MuscleGroupDisplay.pecho,
        MuscleGroupDisplay.espalda,
        MuscleGroupDisplay.piernas,
        MuscleGroupDisplay.brazos,
        MuscleGroupDisplay.hombros,
        MuscleGroupDisplay.core,
      ]);
    });
  });

  group('MuscleGroupMapping.toDisplayGroup', () {
    test('chest → pecho', () {
      expect('chest'.toDisplayGroup(), MuscleGroupDisplay.pecho);
    });

    test('back → espalda', () {
      expect('back'.toDisplayGroup(), MuscleGroupDisplay.espalda);
    });

    test('shoulders → hombros', () {
      expect('shoulders'.toDisplayGroup(), MuscleGroupDisplay.hombros);
    });

    test('quads/hamstrings/glutes/calves all map to piernas', () {
      expect('quads'.toDisplayGroup(), MuscleGroupDisplay.piernas);
      expect('hamstrings'.toDisplayGroup(), MuscleGroupDisplay.piernas);
      expect('glutes'.toDisplayGroup(), MuscleGroupDisplay.piernas);
      expect('calves'.toDisplayGroup(), MuscleGroupDisplay.piernas);
    });

    test('biceps and triceps both map to brazos', () {
      expect('biceps'.toDisplayGroup(), MuscleGroupDisplay.brazos);
      expect('triceps'.toDisplayGroup(), MuscleGroupDisplay.brazos);
    });

    test('core and abs both map to core', () {
      expect('core'.toDisplayGroup(), MuscleGroupDisplay.core);
      expect('abs'.toDisplayGroup(), MuscleGroupDisplay.core);
    });

    test('mixed case input is normalized', () {
      expect('Chest'.toDisplayGroup(), MuscleGroupDisplay.pecho);
      expect('GLUTES'.toDisplayGroup(), MuscleGroupDisplay.piernas);
    });

    test('unknown muscleGroup returns null (defensivo)', () {
      expect('forearms'.toDisplayGroup(), isNull);
      expect(''.toDisplayGroup(), isNull);
      expect('random'.toDisplayGroup(), isNull);
    });
  });
}

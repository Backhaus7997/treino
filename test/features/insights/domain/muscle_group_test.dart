import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';

void main() {
  group('MuscleGroupDisplay.displayLabel', () {
    test('returns UPPERCASE Spanish label for each value', () {
      expect(MuscleGroupDisplay.pecho.displayLabel, 'PECHO');
      expect(MuscleGroupDisplay.espalda.displayLabel, 'ESPALDA');
      expect(MuscleGroupDisplay.hombros.displayLabel, 'HOMBROS');
      expect(MuscleGroupDisplay.biceps.displayLabel, 'BÍCEPS');
      expect(MuscleGroupDisplay.triceps.displayLabel, 'TRÍCEPS');
      expect(MuscleGroupDisplay.cuadriceps.displayLabel, 'CUÁDRICEPS');
      expect(MuscleGroupDisplay.isquiotibiales.displayLabel, 'ISQUIOTIBIALES');
      expect(MuscleGroupDisplay.gluteos.displayLabel, 'GLÚTEOS');
      expect(MuscleGroupDisplay.pantorrilla.displayLabel, 'PANTORRILLA');
      expect(MuscleGroupDisplay.abdominales.displayLabel, 'ABDOMINALES');
    });
  });

  group('MuscleGroupDisplay.displayOrder', () {
    test('contains the 10 granular groups in canonical order', () {
      expect(MuscleGroupDisplay.displayOrder, const [
        MuscleGroupDisplay.pecho,
        MuscleGroupDisplay.espalda,
        MuscleGroupDisplay.hombros,
        MuscleGroupDisplay.biceps,
        MuscleGroupDisplay.triceps,
        MuscleGroupDisplay.cuadriceps,
        MuscleGroupDisplay.isquiotibiales,
        MuscleGroupDisplay.gluteos,
        MuscleGroupDisplay.pantorrilla,
        MuscleGroupDisplay.abdominales,
      ]);
    });
  });

  group('MuscleGroupMapping.toDisplayGroup — canonical keys', () {
    test('chest → pecho', () {
      expect('chest'.toDisplayGroup(), MuscleGroupDisplay.pecho);
    });

    test('back → espalda', () {
      expect('back'.toDisplayGroup(), MuscleGroupDisplay.espalda);
    });

    test('shoulders → hombros', () {
      expect('shoulders'.toDisplayGroup(), MuscleGroupDisplay.hombros);
    });

    test('biceps → biceps (granular, no longer collapsed into brazos)', () {
      expect('biceps'.toDisplayGroup(), MuscleGroupDisplay.biceps);
    });

    test('triceps → triceps (granular, no longer collapsed into brazos)', () {
      expect('triceps'.toDisplayGroup(), MuscleGroupDisplay.triceps);
    });

    test('quads → cuadriceps (granular, no longer collapsed into piernas)', () {
      expect('quads'.toDisplayGroup(), MuscleGroupDisplay.cuadriceps);
    });

    test(
        'hamstrings → isquiotibiales (granular, no longer collapsed into piernas)',
        () {
      expect('hamstrings'.toDisplayGroup(), MuscleGroupDisplay.isquiotibiales);
    });

    test('glutes → gluteos (granular, no longer collapsed into piernas)', () {
      expect('glutes'.toDisplayGroup(), MuscleGroupDisplay.gluteos);
    });

    test('calves → pantorrilla (granular, no longer collapsed into piernas)',
        () {
      expect('calves'.toDisplayGroup(), MuscleGroupDisplay.pantorrilla);
    });

    test('core and abs both map to abdominales', () {
      expect('core'.toDisplayGroup(), MuscleGroupDisplay.abdominales);
      expect('abs'.toDisplayGroup(), MuscleGroupDisplay.abdominales);
    });

    test('mixed case input is normalized', () {
      expect('Chest'.toDisplayGroup(), MuscleGroupDisplay.pecho);
      expect('GLUTES'.toDisplayGroup(), MuscleGroupDisplay.gluteos);
      expect('Hamstrings'.toDisplayGroup(), MuscleGroupDisplay.isquiotibiales);
    });
  });

  group('MuscleGroupMapping.toDisplayGroup — excluded by design', () {
    test('cardio → null (excluded from Insights, decision 1B)', () {
      expect('cardio'.toDisplayGroup(), isNull);
    });

    test('full_body and fullbody → null (not attributable to one group)', () {
      expect('full_body'.toDisplayGroup(), isNull);
      expect('fullbody'.toDisplayGroup(), isNull);
    });
  });

  group('MuscleGroupMapping.toDisplayGroup — legacy taxonomy strings cutoff 2B',
      () {
    test('legacy "brazos" → null (old rollup, NOT remapped to biceps/triceps)',
        () {
      expect('brazos'.toDisplayGroup(), isNull,
          reason: 'cutoff 2B: old rollup strings are dropped silently, not '
              'arbitrarily redistributed across new granular groups');
    });

    test(
        'legacy "piernas" → null (old rollup, NOT remapped to quads/hamstrings/glutes/calves)',
        () {
      expect('piernas'.toDisplayGroup(), isNull);
    });

    test('Spanish display labels stored as muscleGroup → null', () {
      expect('pecho'.toDisplayGroup(), isNull);
      expect('espalda'.toDisplayGroup(), isNull);
      expect('hombros'.toDisplayGroup(), isNull);
    });
  });

  group('MuscleGroupMapping.toDisplayGroup — defensive', () {
    test('unknown muscleGroup returns null', () {
      expect('forearms'.toDisplayGroup(), isNull);
      expect('random'.toDisplayGroup(), isNull);
    });

    test('empty string returns null', () {
      expect(''.toDisplayGroup(), isNull);
    });
  });

  group('MuscleGroupDisplay.frontMaskAssets — body highlighting', () {
    test('pecho → mask_front_chest', () {
      expect(MuscleGroupDisplay.pecho.frontMaskAssets,
          ['assets/body/mask_front_chest.png']);
    });

    test('hombros → mask_front_shoulders', () {
      expect(MuscleGroupDisplay.hombros.frontMaskAssets,
          ['assets/body/mask_front_shoulders.png']);
    });

    test('biceps → mask_front_biceps', () {
      expect(MuscleGroupDisplay.biceps.frontMaskAssets,
          ['assets/body/mask_front_biceps.png']);
    });

    test('cuadriceps → mask_front_quads', () {
      expect(MuscleGroupDisplay.cuadriceps.frontMaskAssets,
          ['assets/body/mask_front_quads.png']);
    });

    test('pantorrilla → mask_front_calves (also on back, see backMaskAssets)',
        () {
      expect(MuscleGroupDisplay.pantorrilla.frontMaskAssets,
          ['assets/body/mask_front_calves.png']);
    });

    test('abdominales → abs + obliques (decision 2: paint all masks)', () {
      expect(MuscleGroupDisplay.abdominales.frontMaskAssets, [
        'assets/body/mask_front_abs.png',
        'assets/body/mask_front_obliques.png',
      ]);
    });

    test('espalda → empty (back-only muscle, see backMaskAssets)', () {
      expect(MuscleGroupDisplay.espalda.frontMaskAssets, isEmpty);
    });

    test('isquiotibiales → empty (back-only muscle)', () {
      expect(MuscleGroupDisplay.isquiotibiales.frontMaskAssets, isEmpty);
    });

    test('gluteos → empty (back-only muscle)', () {
      expect(MuscleGroupDisplay.gluteos.frontMaskAssets, isEmpty);
    });

    test('triceps → empty (decision 1A: no mask asset yet)', () {
      expect(MuscleGroupDisplay.triceps.frontMaskAssets, isEmpty);
    });
  });

  group('MuscleGroupDisplay.backMaskAssets — body highlighting', () {
    test('espalda → back + lats + lowerback (decision 2: paint all 3 masks)',
        () {
      expect(MuscleGroupDisplay.espalda.backMaskAssets, [
        'assets/body/mask_back_back.png',
        'assets/body/mask_back_lats.png',
        'assets/body/mask_back_lowerback.png',
      ]);
    });

    test('hombros → mask_back_shoulders (also on front)', () {
      expect(MuscleGroupDisplay.hombros.backMaskAssets,
          ['assets/body/mask_back_shoulders.png']);
    });

    test('isquiotibiales → mask_back_hamstrings', () {
      expect(MuscleGroupDisplay.isquiotibiales.backMaskAssets,
          ['assets/body/mask_back_hamstrings.png']);
    });

    test('gluteos → mask_back_glutes', () {
      expect(MuscleGroupDisplay.gluteos.backMaskAssets,
          ['assets/body/mask_back_glutes.png']);
    });

    test('pantorrilla → mask_back_calves (also on front)', () {
      expect(MuscleGroupDisplay.pantorrilla.backMaskAssets,
          ['assets/body/mask_back_calves.png']);
    });

    test('pecho → empty (front-only muscle)', () {
      expect(MuscleGroupDisplay.pecho.backMaskAssets, isEmpty);
    });

    test('biceps → empty (front-only)', () {
      expect(MuscleGroupDisplay.biceps.backMaskAssets, isEmpty);
    });

    test('cuadriceps → empty (front-only)', () {
      expect(MuscleGroupDisplay.cuadriceps.backMaskAssets, isEmpty);
    });

    test('abdominales → empty (front-only)', () {
      expect(MuscleGroupDisplay.abdominales.backMaskAssets, isEmpty);
    });

    test('triceps → empty (decision 1A: no mask asset yet)', () {
      expect(MuscleGroupDisplay.triceps.backMaskAssets, isEmpty);
    });
  });
}

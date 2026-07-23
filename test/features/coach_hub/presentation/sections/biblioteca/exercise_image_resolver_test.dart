// Unit tests for exerciseImageUrl — pure name→URL resolver backed by
// exercise_media_catalog.dart (generated from docs/exercises_catalog.json).
//
// Cobertura: nombres reales del catálogo (ES con tilde, EN, mayúsculas,
// espacios extra) + casos sin match confiable → null. Ronda de revisión
// "imágenes de ejercicios en Biblioteca".

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/exercise_image_resolver.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/exercise_media_catalog.dart';

const _bicepCurlUrl =
    'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Dumbbell_Bicep_Curl/0.jpg';

void main() {
  group('exerciseImageUrl —', () {
    test('nombre ES exacto (con tilde) matchea', () {
      expect(exerciseImageUrl('Curl de bíceps'), _bicepCurlUrl);
    });

    test('nombre EN exacto matchea la MISMA url que el ES (dedupe)', () {
      expect(exerciseImageUrl('Bicep Curl'), _bicepCurlUrl);
      expect(
        exerciseImageUrl('Bicep Curl'),
        exerciseImageUrl('Curl de bíceps'),
      );
    });

    test('case-insensitive: mayúsculas/minúsculas no importan', () {
      expect(exerciseImageUrl('CURL DE BÍCEPS'), _bicepCurlUrl);
      expect(exerciseImageUrl('bicep curl'), _bicepCurlUrl);
      expect(exerciseImageUrl('BiCeP cUrL'), _bicepCurlUrl);
    });

    test('tolera espacios extra al borde y dobles espacios internos', () {
      expect(exerciseImageUrl('  Curl de bíceps  '), _bicepCurlUrl);
      expect(exerciseImageUrl('Curl   de   bíceps'), _bicepCurlUrl);
    });

    test(
        'tolera variantes de tildes en distintas vocales (otro ejercicio real)',
        () {
      // "Sentadilla" no está en el mapa como clave sola, pero "Press de
      // banca (Barra)" sí — confirma que el folding de tildes generaliza
      // más allá del fixture de bíceps.
      expect(
        exerciseImageUrl('Press de banca (Barra)'),
        exerciseMediaCatalog['press de banca (barra)'],
      );
      expect(exerciseMediaCatalog['press de banca (barra)'], isNotNull);
    });

    test(
        'ejercicio inexistente → null (fallback honesto, no imagen incorrecta)',
        () {
      expect(exerciseImageUrl('Ejercicio Ficticio Que No Existe'), isNull);
    });

    test('nombre custom del trainer → null', () {
      expect(exerciseImageUrl('Sentadilla Personalizada de Juan'), isNull);
    });

    test('string vacío o solo espacios → null', () {
      expect(exerciseImageUrl(''), isNull);
      expect(exerciseImageUrl('   '), isNull);
    });

    test(
        'ejercicio con media_confidence medium/low NO está en el catálogo '
        '(el generador filtra solo "high")', () {
      // "Bulgarian Split Squat" / "Sentadilla búlgara" es medium en el JSON
      // fuente — no debe aparecer en el mapa generado.
      expect(exerciseImageUrl('Sentadilla búlgara'), isNull);
      expect(exerciseImageUrl('Bulgarian Split Squat'), isNull);
    });

    test('el catálogo generado no está vacío (regresión de generación)', () {
      expect(exerciseMediaCatalog, isNotEmpty);
      expect(exerciseMediaCatalog.length, greaterThan(100));
    });
  });
}

// Unit tests for exerciseImageUrl — pure name→URL resolver backed by
// exercise_media_catalog.dart (generado desde docs/exercises_catalog.json
// filtrado por scripts/exercise_media_verified.json).
//
// Cobertura: nombres reales verificados VISUALMENTE (ES con tilde, EN,
// mayúsculas, espacios extra) + casos sin match confiable → null, incluidos
// ejercicios que antes matcheaban por `media_confidence` heurística
// (high/medium) pero que la verificación visual imagen-por-imagen determinó
// que la foto NO corresponde al ejercicio ("wrong"). Ronda 5 de revisión
// "imágenes de ejercicios en Biblioteca": solo lookup exacto, sin fallback
// por nombre base/variante de equipamiento (removido — inseguro).

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/exercise_image_resolver.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/exercise_media_catalog.dart';

// "Curl de bíceps" / "Bicep Curl" está en la lista "verified" de
// scripts/exercise_media_verified.json.
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
        'tolera variantes de tildes en distintas vocales (otro ejercicio real '
        'verificado)', () {
      // "Press de banca (Barra)" está en "verified".
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
        'ejercicio pineado como "wrong" por la verificación visual → null '
        '(pedido explícito del usuario)', () {
      // "Press de banca (Polea)" tenía media_confidence "high" en el JSON
      // fuente, pero la verificación visual imagen-por-imagen determinó que
      // la foto es la MISMA que "Press de banca (Barra)" — equipamiento
      // equivocado. Está en la lista "wrong" de exercise_media_verified.json
      // y NUNCA debe resolver una URL.
      expect(exerciseImageUrl('Press de banca (Polea)'), isNull);
      expect(exerciseImageUrl('Bench Press (Cable)'), isNull);
    });

    test(
        'ejercicio "medium" que matcheaba en la ronda anterior (por '
        'confianza heurística) ahora da null — la verificación visual lo '
        'marcó "wrong"', () {
      // "Sentadilla búlgara" / "Bulgarian Split Squat" era medium y
      // matcheaba en la ronda de cobertura previa (antes de la verificación
      // visual). La foto real resultó ser de un ejercicio distinto
      // (Smith_Single-Leg_Split_Squat) — quedó en "wrong".
      expect(exerciseImageUrl('Sentadilla búlgara'), isNull);
      expect(exerciseImageUrl('Bulgarian Split Squat'), isNull);
    });

    test(
        'sin fallback por variante de equipamiento (removido — inseguro): '
        'una variante NO verificada da null aunque otra variante de la MISMA '
        'base sí esté verificada', () {
      // "Press Arnold (Mancuerna)" SÍ está verificado, pero eso ya NO debe
      // hacer que otra variante de equipamiento distinta ("Polea", que ni
      // siquiera existe en el catálogo) resuelva ninguna imagen — el
      // resolver ya no tiene capa de fallback por base.
      expect(exerciseImageUrl('Press Arnold (Mancuerna)'), isNotNull);
      expect(exerciseImageUrl('Press Arnold (Polea)'), isNull);
      expect(exerciseImageUrl('Arnold Press (Cable)'), isNull);
    });

    test(
        'variante de equipamiento NO verificada de un ejercicio con OTRA '
        'variante sí verificada → null (ambigüedad real observada por la '
        'verificación visual)', () {
      // El catálogo tiene 7 variantes de "Curl de Bíceps"; solo "Curl de
      // bíceps" (sin equipamiento) y "Curl de bíceps (Mancuerna)" están en
      // "verified" — el resto ("Barra", "Polea", "Máquina", "TRX",
      // "Barra Z") están en "wrong" y deben dar null.
      expect(exerciseImageUrl('Curl de bíceps (Mancuerna)'), isNotNull);
      expect(exerciseImageUrl('Curl de bíceps (Barra)'), isNull);
      expect(exerciseImageUrl('Curl de bíceps (Polea)'), isNull);
      expect(exerciseImageUrl('Curl de bíceps (Máquina)'), isNull);
    });

    test('el catálogo generado no está vacío (regresión de generación)', () {
      expect(exerciseMediaCatalog, isNotEmpty);
      expect(exerciseMediaCatalog.length, greaterThan(50));
    });
  });
}

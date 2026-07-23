// Unit tests for exerciseImageUrl — pure name→URL resolver backed by
// exercise_media_catalog.dart (generated from docs/exercises_catalog.json).
//
// Cobertura: nombres reales del catálogo (ES con tilde, EN, mayúsculas,
// espacios extra) + casos sin match confiable → null. Ronda de revisión
// "imágenes de ejercicios en Biblioteca" (rondas 3 y 4: cobertura ampliada a
// media_confidence high+medium + fallback de variantes de equipamiento vía
// nombre base inequívoco).

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/exercise_image_resolver.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/exercise_media_catalog.dart';

const _bicepCurlUrl =
    'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Dumbbell_Bicep_Curl/0.jpg';

// "Sentadilla búlgara" / "Bulgarian Split Squat" es `media_confidence:
// "medium"` en el JSON fuente (sin sufijo de equipamiento) — cubre la capa
// (a) exacta ahora que el generador incluye high+medium.
const _bulgarianSplitSquatUrl =
    'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Smith_Single-Leg_Split_Squat/0.jpg';

// "Press Arnold (Mancuerna)" / "Arnold Press (Dumbbell)" es la ÚNICA entrada
// del catálogo para la base "press arnold" (high) — cubre la capa (b),
// fallback de variante de equipamiento vía base inequívoca.
const _arnoldPressUrl =
    'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Arnold_Dumbbell_Press/0.jpg';

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
        'ejercicio con media_confidence "medium" SÍ matchea (capa a — '
        'exacta, ronda 4 amplía el filtro de high a high+medium)', () {
      expect(exerciseImageUrl('Sentadilla búlgara'), _bulgarianSplitSquatUrl);
      expect(
          exerciseImageUrl('Bulgarian Split Squat'), _bulgarianSplitSquatUrl);
    });

    test('ejercicio con media_confidence "low" sigue excluido (nunca low/none)',
        () {
      // "Extensión de espalda" solo tiene entradas "low" en el catálogo
      // fuente (Hiperextensión / Máquina / Hiperextensión con peso) — ni la
      // clave exacta ni el fallback de base deben resolver nada acá.
      expect(exerciseImageUrl('Extensión de espalda (Hiperextensión)'), isNull);
      expect(exerciseImageUrl('Back Extension (Hyperextension)'), isNull);
      expect(exerciseImageUrl('Extensión de espalda (Barra)'), isNull);
    });

    test(
        'variante de equipamiento que no matchea exacto cae al fallback de '
        'base inequívoca (capa b)', () {
      // El catálogo curado SOLO tiene "Press Arnold (Mancuerna)" — es la
      // única entrada para la base "press arnold", así que un nombre de
      // Biblioteca con un equipamiento distinto ("Polea") igual matchea esa
      // imagen en vez de quedarse sin ninguna.
      expect(exerciseImageUrl('Press Arnold (Polea)'), _arnoldPressUrl);
      expect(exerciseImageUrl('Arnold Press (Cable)'), _arnoldPressUrl);
      // La entrada exacta con el equipamiento real del catálogo sigue
      // resolviendo por la capa (a), sin pasar por el fallback.
      expect(exerciseImageUrl('Press Arnold (Mancuerna)'), _arnoldPressUrl);
    });

    test(
        'base AMBIGUA (2+ ejercicios distintos comparten la base) → null, '
        'jamás una imagen que podría ser del equipamiento equivocado', () {
      // El catálogo tiene 7 variantes distintas de "Curl de Bíceps"
      // (Barra/Barra Z/Mancuerna/TRX/Máquina/Polea + sin equipamiento) — la
      // base "curl de biceps" es ambigua, así que un equipamiento no
      // catalogado ("Cuerda") NO debe resolver a ninguna de esas imágenes.
      expect(exerciseImageUrl('Curl de Bíceps (Cuerda)'), isNull);
      expect(exerciseImageUrl('Bicep Curl (Rope)'), isNull);
    });

    test(
        'nombre sin sufijo de equipamiento y sin match exacto → null (capa '
        'b no aplica, va directo a c)', () {
      expect(exerciseImageUrl('Ejercicio Totalmente Inventado'), isNull);
    });

    test('el catálogo generado no está vacío (regresión de generación)', () {
      expect(exerciseMediaCatalog, isNotEmpty);
      expect(exerciseMediaCatalog.length, greaterThan(100));
      expect(exerciseMediaBaseCatalog, isNotEmpty);
    });

    test(
        'el mapa de base NO contiene claves ya cubiertas por el mapa exacto '
        '(no aportan valor, ver generador)', () {
      for (final baseKeyEntry in exerciseMediaBaseCatalog.keys) {
        expect(
          exerciseMediaCatalog.containsKey(baseKeyEntry),
          isFalse,
          reason: '"$baseKeyEntry" ya está en el mapa exacto — redundante '
              'en el mapa base.',
        );
      }
    });
  });
}

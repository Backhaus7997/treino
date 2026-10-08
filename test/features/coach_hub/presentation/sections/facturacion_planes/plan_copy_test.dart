// plan_copy_test.dart — [ejerciciosTexto] es el ÚNICO lugar permitido para
// convertir `tier.customExerciseLimit` en texto (docs/limite-ejercicios-pf.md
// §PR5). El eje del archivo es que Plan 3 —`customExerciseLimit == null`—
// nunca renderiza la palabra «null»: es el mismo bug que ya se publicó una
// vez con `cupoTexto` («Hasta null alumnos»).

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_copy.dart';

void main() {
  group('ejerciciosTexto', () {
    test('Free → "20 ejercicios propios"', () {
      expect(ejerciciosTexto(SubscriptionTier.free), '20 ejercicios propios');
    });

    test('Plan 1 → "60 ejercicios propios"', () {
      expect(ejerciciosTexto(SubscriptionTier.plan1), '60 ejercicios propios');
    });

    test('Plan 2 → "120 ejercicios propios"', () {
      expect(ejerciciosTexto(SubscriptionTier.plan2), '120 ejercicios propios');
    });

    // El caso que importa: `kTierCustomExerciseLimits[plan3]` es `null` a
    // propósito. Si alguien interpola el límite a mano en vez de pasar por
    // esta función, el texto sale «null ejercicios propios».
    test('Plan 3 (sin límite) → "ejercicios propios sin límite", nunca null',
        () {
      final texto = ejerciciosTexto(SubscriptionTier.plan3);

      expect(texto, 'ejercicios propios sin límite');
      expect(texto.toLowerCase().contains('null'), isFalse);
    });

    test('nunca devuelve un string que contenga "null", para ningún tier', () {
      for (final tier in SubscriptionTier.values) {
        expect(
          ejerciciosTexto(tier).toLowerCase().contains('null'),
          isFalse,
          reason: 'ejerciciosTexto($tier) publicó la palabra "null"',
        );
      }
    });
  });

  // Mismo eje, para plantillas (docs/limite-plantillas-pf.md §3 PR5):
  // `tier.templateLimit == null` (todo lo que no sea Free) nunca renderiza
  // «null».
  group('plantillasTexto', () {
    test('Free → "3 plantillas"', () {
      expect(plantillasTexto(SubscriptionTier.free), '3 plantillas');
    });

    test('Plan 1 (sin límite) → "plantillas sin límite", nunca null', () {
      final texto = plantillasTexto(SubscriptionTier.plan1);

      expect(texto, 'plantillas sin límite');
      expect(texto.toLowerCase().contains('null'), isFalse);
    });

    test('Plan 2 (sin límite) → "plantillas sin límite"', () {
      expect(plantillasTexto(SubscriptionTier.plan2), 'plantillas sin límite');
    });

    test('Plan 3 (sin límite) → "plantillas sin límite"', () {
      expect(plantillasTexto(SubscriptionTier.plan3), 'plantillas sin límite');
    });

    test('nunca devuelve un string que contenga "null", para ningún tier', () {
      for (final tier in SubscriptionTier.values) {
        expect(
          plantillasTexto(tier).toLowerCase().contains('null'),
          isFalse,
          reason: 'plantillasTexto($tier) publicó la palabra "null"',
        );
      }
    });
  });

  // La fecha corta de «tu plan rige hasta el 15/10». Dos ejes que NO son el
  // mismo y que arreglar uno no arregla el otro: el HUSO (el día calendario se
  // lee en ART, no en UTC ni en el huso de quien corre el test) y el DÍA (el
  // borde de medianoche ART, que cae a las 03:00 UTC). Todos los instantes de
  // acá son UTC explícitos, así que el resultado no depende de la máquina.
  group('fechaDiaMesArg', () {
    test('mediodía ART: el día calendario es el mismo que en UTC', () {
      expect(fechaDiaMesArg(DateTime.utc(2026, 10, 15, 15)), '15/10');
    });

    // El caso que motivó el helper: entre las 21:00 y las 23:59 ART el día UTC
    // ya es el siguiente. Leer los campos crudos mostraría «16/10».
    test('22:30 ART (01:30 UTC del día siguiente) sigue siendo el día ART', () {
      expect(fechaDiaMesArg(DateTime.utc(2026, 10, 16, 1, 30)), '15/10');
    });

    test('el borde es medianoche ART: 02:59 UTC es ayer, 03:00 UTC es hoy', () {
      expect(fechaDiaMesArg(DateTime.utc(2026, 10, 16, 2, 59)), '15/10');
      expect(fechaDiaMesArg(DateTime.utc(2026, 10, 16, 3, 0)), '16/10');
    });

    test('cruza el borde del año: 01:00 UTC del 1/1 es el 31/12 en ART', () {
      expect(fechaDiaMesArg(DateTime.utc(2027, 1, 1, 1)), '31/12');
    });

    test('sin cero a la izquierda: «5/3», no «05/03»', () {
      expect(fechaDiaMesArg(DateTime.utc(2026, 3, 5, 15)), '5/3');
    });

    // `fromMillisecondsSinceEpoch` devuelve el MISMO instante con flag local.
    // La conversión a UTC adentro del helper existe para esto: si faltara,
    // el resultado dependería del huso del equipo que corre la suite.
    test('un instante con flag local da lo mismo que su equivalente UTC', () {
      final utc = DateTime.utc(2026, 10, 16, 1, 30);
      final local = DateTime.fromMillisecondsSinceEpoch(
        utc.millisecondsSinceEpoch,
      );

      expect(local.isUtc, isFalse);
      expect(fechaDiaMesArg(local), fechaDiaMesArg(utc));
    });
  });
}

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
}

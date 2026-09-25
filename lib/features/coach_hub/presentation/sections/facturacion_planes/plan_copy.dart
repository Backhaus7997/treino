import '../../../../coach/domain/subscription_tier.dart';

/// El texto del cupo de un plan, en UN solo lugar.
///
/// `weightLimit == null` (plan3) NO es un dato faltante: significa SIN LÍMITE.
/// Interpolarlo directo renderiza la palabra «null» — y eso fue exactamente lo
/// que se publicó: el upsell al plan más caro decía «Hasta null alumnos».
///
/// Este archivo existe porque esa promesa —«cualquier lugar que muestre el cupo
/// pasa por acá»— se rompió apenas una segunda pantalla necesitó el texto y lo
/// copió. Dos copias byte a byte no fallan hoy; fallan el día que alguien
/// arregla una. Si hace falta el cupo en un tercer lugar, se importa de acá.
String cupoTexto(SubscriptionTier tier) => tier.isUnlimited
    ? 'alumnos sin límite' // i18n: Fase W3
    : '${tier.weightLimit} alumnos'; // i18n: Fase W3

/// El texto del tope de EJERCICIOS PROPIOS de un plan, en UN solo lugar —
/// mismo motivo y misma promesa que [cupoTexto], y el mismo agujero que
/// existe para tapar: `tier.customExerciseLimit == null` (Plan 3 en la tabla
/// estática, docs/limite-ejercicios-pf.md §0) NO es un dato faltante, es SIN
/// LÍMITE.
/// Interpolarlo directo publica la palabra «null», la MISMA clase de bug que
/// [cupoTexto] ya documenta como publicada («Hasta null alumnos»).
///
/// docs/limite-ejercicios-pf.md §PR5: «Plan 3 dice "ejercicios propios sin
/// límite", nunca null.»
String ejerciciosTexto(SubscriptionTier tier) {
  final limit = tier.customExerciseLimit;
  return limit == null
      ? 'ejercicios propios sin límite' // i18n: Fase W3
      : '$limit ejercicios propios'; // i18n: Fase W3
}

/// El nombre visible de un plan **en prosa**, para cuando aparece dentro de una
/// oración: «tu Plan 2 incluye…».
///
/// OJO — `pricing_screen.dart` tiene a propósito su propia variante en
/// MAYÚSCULAS (`FREE`, `PLAN 1`), porque ahí el nombre es el título de una
/// tarjeta en Barlow Condensed, no parte de una frase. **No la unifiques con
/// esta**: unificarlas ya se intentó una vez y le cambió el copy a la pantalla
/// de precios en silencio. Son dos textos distintos que casualmente comparten
/// las mismas cuatro palabras.
String tierName(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'Free', // i18n: Fase W3
      SubscriptionTier.plan1 => 'Plan 1', // i18n: Fase W3
      SubscriptionTier.plan2 => 'Plan 2', // i18n: Fase W3
      SubscriptionTier.plan3 => 'Plan 3', // i18n: Fase W3
    };

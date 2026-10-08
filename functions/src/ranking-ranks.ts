/**
 * ranking-ranks — rangos de levantamiento de TREINO.
 *
 * Convierte el mejor peso de un atleta en sentadilla / banca / peso muerto en
 * un RANGO entero que la pestaña Rankings dibuja como insignia:
 *
 *   0 = sin rango · 1 Bronce · 2 Plata · 3 Oro · 4 Platino · 5 Diamante ·
 *   6 Campeón · 7 Titán · 8 Olímpico
 *
 * Esta es la ÚNICA fuente de la fórmula y de los umbrales. El cliente no
 * recalcula nada: sólo mapea el entero guardado en `userPublicProfiles/{uid}`
 * (`squatRank` / `benchRank` / `deadliftRank`) a una insignia. Así no se repite
 * la duplicación Dart/TS de `K_MAIN_LIFT_FAMILIES`, que no tiene test de
 * paridad. Tampoco se publica el peso corporal: el doc público guarda sólo el
 * entero, y el peso sale de `users/{uid}`, que es privado.
 *
 * De dónde salen los números:
 *   - ANCLA: la tabla de press de banca del video de referencia
 *     (tiktok.com/@liftoff_app), válida para 54 kg de peso corporal ("for
 *     120lbs bw"): 30 · 45 · 55 · 65 · 75 · 85 · 97 · 115 kg.
 *   - ESCALA POR PESO CORPORAL: coeficiente DOTS masculino (OpenPowerlifting,
 *     crates/coefficients/src/dots.rs). Un rango se alcanza cuando
 *     `peso × coef(bw) ≥ ancla × coef(54,4) × factor del lift`.
 *   - SENTADILLA y PESO MUERTO: ratios sobre la banca (≈1,35 y ≈1,6), medidos
 *     en las tablas de Strength Level; son estables entre 55 y 120 kg.
 *   - MUJER: un factor por lift sobre la escala masculina, calibrado contra las
 *     tablas femeninas de Strength Level ("Elite" a 55 kg: banca 84,
 *     sentadilla 123, peso muerto 143). No se usa el coeficiente DOTS femenino
 *     porque está calibrado para el total y regala demasiado en banca.
 *
 * Chequeo de cordura contra el "Elite" de Strength Level (el rango 8): hombre
 * de 80 kg banca 153 vs 151, sentadilla 207 vs 206, peso muerto 245 vs 239;
 * mujer de 55 kg banca 81 vs 84, sentadilla 122 vs 123, peso muerto 145 vs 143.
 * A 120 kg la vara queda ~10 % más baja que Strength Level (propio de DOTS).
 * Los casos están fijados en `__tests__/ranking-ranks.test.ts`.
 */

export type RankedLift = "squat" | "bench" | "deadlift";

/** Cantidad de rangos con insignia (1..8). El 0 es "sin rango". */
export const RANK_COUNT = 8;

/** Press de banca (kg) de cada rango, para un hombre de [REFERENCE_BODYWEIGHT_KG]. */
export const BENCH_ANCHOR_KG: readonly number[] = [30, 45, 55, 65, 75, 85, 97, 115];

/** 120 lb: el peso corporal para el que el video publica la tabla de banca. */
export const REFERENCE_BODYWEIGHT_KG = 54.4311;

/** Cuántas veces la banca es el umbral de cada lift en la escala masculina. */
export const LIFT_RATIO_TO_BENCH: Record<RankedLift, number> = {
  bench: 1,
  squat: 1.35,
  deadlift: 1.6,
};

/**
 * Multiplicador que se aplica ADEMÁS del anterior para la escala femenina:
 * el umbral de una mujer es el masculino del mismo lift por este factor.
 */
export const FEMALE_FACTOR: Record<RankedLift, number> = {
  bench: 0.7,
  squat: 0.78,
  deadlift: 0.78,
};

/** Peso corporal válido. Fuera de este rango el dato es un error de carga: no hay rango. */
export const MIN_BODYWEIGHT_KG = 30;
export const MAX_BODYWEIGHT_KG = 300;

/**
 * Tope de un peso creíble. Es el mismo `kMaxWeightKg` que el cliente le pone a
 * una serie (`lib/features/workout/domain/set_limits.dart`): un valor por
 * encima sólo puede venir de un cliente parcheado, así que no rankea.
 */
export const MAX_PLAUSIBLE_LIFT_KG = 500;

/** Tolerancia para no perder un rango por un error de redondeo de punto flotante. */
const EPSILON = 1e-9;

/**
 * Coeficiente DOTS masculino (OpenPowerlifting): `500 / poly4(bw)`. El peso
 * corporal se acota a 40–210 kg, igual que la implementación de referencia.
 */
export function dotsCoefficientMen(bodyWeightKg: number): number {
  const bw = Math.min(210, Math.max(40, bodyWeightKg));
  const denominator =
    -1.093e-6 * bw ** 4 +
    0.0007391293 * bw ** 3 -
    0.1918759221 * bw ** 2 +
    24.0900756 * bw -
    307.75076;
  return 500 / denominator;
}

function isValidBodyWeight(bodyWeightKg: unknown): bodyWeightKg is number {
  return (
    typeof bodyWeightKg === "number" &&
    Number.isFinite(bodyWeightKg) &&
    bodyWeightKg >= MIN_BODYWEIGHT_KG &&
    bodyWeightKg <= MAX_BODYWEIGHT_KG
  );
}

/** Sólo `female` usa la escala femenina; cualquier otro valor, o ninguno, la masculina. */
function liftFactor(lift: RankedLift, gender: unknown): number {
  const ratio = LIFT_RATIO_TO_BENCH[lift];
  return gender === "female" ? ratio * FEMALE_FACTOR[lift] : ratio;
}

/** Puntos DOTS que hay que juntar para el rango `rank` (1..8) de `lift`. */
function thresholdPoints(lift: RankedLift, rank: number, gender: unknown): number {
  return BENCH_ANCHOR_KG[rank - 1] * dotsCoefficientMen(REFERENCE_BODYWEIGHT_KG) * liftFactor(lift, gender);
}

/**
 * Kilos que hay que levantar para alcanzar `rank` (1..8) en `lift`, dado el peso
 * corporal y el sexo del atleta. `null` si el rango no existe o el peso corporal
 * no es válido. Sin redondear: quien lo muestre decide cuántos decimales.
 */
export function rankThresholdKg(
  lift: RankedLift,
  rank: number,
  bodyWeightKg: unknown,
  gender: unknown,
): number | null {
  if (!Number.isInteger(rank) || rank < 1 || rank > RANK_COUNT) return null;
  if (!isValidBodyWeight(bodyWeightKg)) return null;
  return thresholdPoints(lift, rank, gender) / dotsCoefficientMen(bodyWeightKg);
}

/**
 * Rango (0..8) de un atleta en `lift`, o `null` cuando no hay forma honesta de
 * calcularlo: sin peso levantado, peso levantado inverosímil, o sin peso
 * corporal válido. `0` significa "tiene datos pero no llega a Bronce".
 */
export function liftRankFor(
  lift: RankedLift,
  weightKg: unknown,
  bodyWeightKg: unknown,
  gender: unknown,
): number | null {
  if (typeof weightKg !== "number" || !Number.isFinite(weightKg)) return null;
  if (weightKg <= 0 || weightKg > MAX_PLAUSIBLE_LIFT_KG) return null;
  if (!isValidBodyWeight(bodyWeightKg)) return null;

  const points = weightKg * dotsCoefficientMen(bodyWeightKg);
  let rank = 0;
  for (let candidate = 1; candidate <= RANK_COUNT; candidate++) {
    if (points + EPSILON >= thresholdPoints(lift, candidate, gender)) rank = candidate;
  }
  return rank;
}

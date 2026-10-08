/**
 * Unit tests for `ranking-ranks.ts` — pure functions, no emulator.
 *
 * Las tablas de abajo son la tabla del plan de rangos (kg necesarios para cada
 * rango, de Bronce a Olímpico) y sirven de documentación ejecutable: si alguien
 * toca un ancla, un factor o la fórmula DOTS, el diff de este archivo muestra
 * qué le pasa a cada atleta.
 */

import {
  BENCH_ANCHOR_KG,
  MAX_PLAUSIBLE_LIFT_KG,
  RANK_COUNT,
  REFERENCE_BODYWEIGHT_KG,
  RankedLift,
  dotsCoefficientMen,
  liftRankFor,
  rankThresholdKg,
} from "../ranking-ranks";

const LIFTS: RankedLift[] = ["squat", "bench", "deadlift"];

/** Kg necesarios para los 8 rangos, redondeados al kilo. */
function thresholdsKg(
  lift: RankedLift,
  bodyWeightKg: number,
  gender: unknown,
): number[] {
  const out: number[] = [];
  for (let rank = 1; rank <= RANK_COUNT; rank++) {
    out.push(Math.round(rankThresholdKg(lift, rank, bodyWeightKg, gender) as number));
  }
  return out;
}

describe("dotsCoefficientMen", () => {
  it("coincide con OpenPowerlifting a 80 kg (≈0,6895)", () => {
    expect(dotsCoefficientMen(80)).toBeCloseTo(0.6895, 3);
  });

  it("acota el peso corporal a 40–210 kg", () => {
    expect(dotsCoefficientMen(35)).toBe(dotsCoefficientMen(40));
    expect(dotsCoefficientMen(250)).toBe(dotsCoefficientMen(210));
  });

  it("decrece con el peso corporal en todo el rango útil", () => {
    for (let bw = 41; bw <= 210; bw++) {
      expect(dotsCoefficientMen(bw)).toBeLessThan(dotsCoefficientMen(bw - 1));
    }
  });
});

describe("rankThresholdKg: la tabla del video y su escala", () => {
  it("a 54,4 kg la banca masculina es exactamente la tabla del video", () => {
    expect(thresholdsKg("bench", REFERENCE_BODYWEIGHT_KG, "male")).toEqual([...BENCH_ANCHOR_KG]);
  });

  it("hombre de 80 kg", () => {
    expect(thresholdsKg("bench", 80, "male")).toEqual([40, 60, 73, 87, 100, 113, 129, 153]);
    expect(thresholdsKg("squat", 80, "male")).toEqual([54, 81, 99, 117, 135, 153, 174, 207]);
    expect(thresholdsKg("deadlift", 80, "male")).toEqual([64, 96, 117, 138, 160, 181, 207, 245]);
  });

  it("hombre de 100 kg", () => {
    expect(thresholdsKg("bench", 100, "male")).toEqual([45, 67, 82, 97, 112, 127, 145, 172]);
  });

  it("mujer de 55 kg", () => {
    expect(thresholdsKg("bench", 55, "female")).toEqual([21, 32, 39, 46, 53, 60, 69, 81]);
    expect(thresholdsKg("squat", 55, "female")).toEqual([32, 48, 58, 69, 80, 90, 103, 122]);
    expect(thresholdsKg("deadlift", 55, "female")).toEqual([38, 57, 69, 82, 94, 107, 122, 145]);
  });

  it("mujer de 70 kg", () => {
    expect(thresholdsKg("bench", 70, "female")).toEqual([26, 38, 47, 56, 64, 73, 83, 98]);
    expect(thresholdsKg("squat", 70, "female")).toEqual([39, 58, 71, 84, 97, 109, 125, 148]);
    expect(thresholdsKg("deadlift", 70, "female")).toEqual([46, 69, 84, 99, 114, 130, 148, 175]);
  });

  it("los umbrales crecen con el rango", () => {
    for (const lift of LIFTS) {
      for (const gender of ["male", "female"]) {
        const kg = thresholdsKg(lift, 75, gender);
        for (let i = 1; i < kg.length; i++) expect(kg[i]).toBeGreaterThan(kg[i - 1]);
      }
    }
  });

  it("a igual rango, un atleta más pesado necesita levantar más", () => {
    for (const lift of LIFTS) {
      for (let rank = 1; rank <= RANK_COUNT; rank++) {
        const liviano = rankThresholdKg(lift, rank, 60, "male") as number;
        const pesado = rankThresholdKg(lift, rank, 90, "male") as number;
        expect(pesado).toBeGreaterThan(liviano);
      }
    }
  });

  it("la mujer necesita menos kilos que el hombre del mismo peso", () => {
    for (const lift of LIFTS) {
      for (let rank = 1; rank <= RANK_COUNT; rank++) {
        const mujer = rankThresholdKg(lift, rank, 65, "female") as number;
        const hombre = rankThresholdKg(lift, rank, 65, "male") as number;
        expect(mujer).toBeLessThan(hombre);
      }
    }
  });

  it("devuelve null para un rango inexistente o un peso corporal inválido", () => {
    expect(rankThresholdKg("bench", 0, 80, "male")).toBeNull();
    expect(rankThresholdKg("bench", 9, 80, "male")).toBeNull();
    expect(rankThresholdKg("bench", 1.5, 80, "male")).toBeNull();
    expect(rankThresholdKg("bench", 1, null, "male")).toBeNull();
    expect(rankThresholdKg("bench", 1, 29, "male")).toBeNull();
  });
});

describe("liftRankFor: asignación del rango", () => {
  it("recorre los 8 rangos de la tabla del video a 54,4 kg", () => {
    const bw = REFERENCE_BODYWEIGHT_KG;
    expect(liftRankFor("bench", 29, bw, "male")).toBe(0);
    BENCH_ANCHOR_KG.forEach((anchor, i) => {
      expect(liftRankFor("bench", anchor, bw, "male")).toBe(i + 1);
      expect(liftRankFor("bench", anchor + 0.5, bw, "male")).toBe(i + 1);
    });
    expect(liftRankFor("bench", 114, bw, "male")).toBe(7);
    expect(liftRankFor("bench", 200, bw, "male")).toBe(8);
  });

  it("54,4 kg de peso corporal con 55 kg de banca es Oro (3)", () => {
    expect(liftRankFor("bench", 55, 54.4, "male")).toBe(3);
  });

  it("hombre de 80 kg: el 'Elite' de Strength Level cae en Olímpico", () => {
    // El umbral exacto de banca es 153,11 kg: la tabla lo muestra redondeado.
    expect(liftRankFor("bench", 154, 80, "male")).toBe(8);
    expect(liftRankFor("bench", 153, 80, "male")).toBe(7);
    expect(liftRankFor("squat", 207, 80, "male")).toBe(8);
    expect(liftRankFor("squat", 206, 80, "male")).toBe(7);
    expect(liftRankFor("deadlift", 245, 80, "male")).toBe(8);
    expect(liftRankFor("deadlift", 244, 80, "male")).toBe(7);
  });

  it("mujer de 55 kg: banca 82 es Olímpico, 80 es Titán", () => {
    expect(liftRankFor("bench", 82, 55, "female")).toBe(8);
    expect(liftRankFor("bench", 80, 55, "female")).toBe(7);
  });

  it("el mismo peso rinde distinto rango según el sexo", () => {
    expect(liftRankFor("bench", 60, 60, "female")).toBeGreaterThan(liftRankFor("bench", 60, 60, "male") as number);
  });

  it("cada umbral es el primer kilo que cambia de rango", () => {
    for (const lift of LIFTS) {
      for (const gender of ["male", "female"]) {
        for (const bw of [45, 54.4311, 70, 95, 130]) {
          for (let rank = 1; rank <= RANK_COUNT; rank++) {
            const umbral = rankThresholdKg(lift, rank, bw, gender) as number;
            if (umbral + 0.01 > MAX_PLAUSIBLE_LIFT_KG) continue;
            expect(liftRankFor(lift, umbral + 0.01, bw, gender)).toBeGreaterThanOrEqual(rank);
            expect(liftRankFor(lift, umbral - 0.01, bw, gender)).toBeLessThan(rank);
          }
        }
      }
    }
  });

  it("todo género que no sea 'female' usa la escala masculina", () => {
    const masculino = liftRankFor("squat", 150, 85, "male");
    for (const gender of ["non_binary", "undisclosed", "", null, undefined, 42]) {
      expect(liftRankFor("squat", 150, 85, gender)).toBe(masculino);
    }
  });

  it("sin dato honesto no hay rango (null), y no es lo mismo que 0", () => {
    expect(liftRankFor("bench", null, 80, "male")).toBeNull();
    expect(liftRankFor("bench", undefined, 80, "male")).toBeNull();
    expect(liftRankFor("bench", Number.NaN, 80, "male")).toBeNull();
    expect(liftRankFor("bench", "100", 80, "male")).toBeNull();
    expect(liftRankFor("bench", 0, 80, "male")).toBeNull();
    expect(liftRankFor("bench", -20, 80, "male")).toBeNull();
    expect(liftRankFor("bench", 100, null, "male")).toBeNull();
    expect(liftRankFor("bench", 100, undefined, "male")).toBeNull();
    expect(liftRankFor("bench", 100, Number.NaN, "male")).toBeNull();
    expect(liftRankFor("bench", 100, "80", "male")).toBeNull();
    expect(liftRankFor("bench", 5, 80, "male")).toBe(0);
  });

  it("un peso por encima del tope creíble no rankea", () => {
    expect(liftRankFor("deadlift", MAX_PLAUSIBLE_LIFT_KG, 120, "male")).toBe(8);
    expect(liftRankFor("deadlift", MAX_PLAUSIBLE_LIFT_KG + 0.5, 120, "male")).toBeNull();
    expect(liftRankFor("bench", 999, 80, "male")).toBeNull();
  });

  it("acepta el peso corporal en 30–300 kg y rechaza lo de afuera", () => {
    expect(liftRankFor("bench", 60, 30, "male")).not.toBeNull();
    expect(liftRankFor("bench", 60, 300, "male")).not.toBeNull();
    expect(liftRankFor("bench", 60, 29.9, "male")).toBeNull();
    expect(liftRankFor("bench", 60, 300.1, "male")).toBeNull();
  });

  it("entre 30 y 40 kg (y sobre 210) usa el coeficiente acotado, como DOTS", () => {
    expect(liftRankFor("bench", 50, 35, "male")).toBe(liftRankFor("bench", 50, 40, "male"));
    expect(liftRankFor("bench", 180, 250, "male")).toBe(liftRankFor("bench", 180, 210, "male"));
  });
});

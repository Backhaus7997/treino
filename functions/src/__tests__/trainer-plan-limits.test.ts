/**
 * Unit tests for `resolvePlanLimits` / `customExerciseLimitFor` /
 * `templateLimitFor` (limite-ejercicios-pf.md y limite-plantillas-pf.md, PR1).
 * No infra — `recountCustomExercises` y `recountTemplates` necesitan
 * Firestore de verdad y se cubren en `custom-exercise-count.test.ts` y
 * `template-count.test.ts` (emulador), no aca.
 */

import {
  customExerciseLimitFor,
  PlanLimitSwitches,
  resolveAthleteLimits,
  resolvePlanLimits,
  templateLimitFor,
} from "../subscriptions/trainer-plan-limits";
import { effectiveWeightLimit, SubscriptionState } from "../subscriptions/effective-limit";

const NOW = 1_000_000;

const sub = (
  tier: SubscriptionState["tier"],
  status: SubscriptionState["status"],
  currentPeriodEndMs?: number | null,
): SubscriptionState => ({ tier, status, currentPeriodEndMs });

const OFF: PlanLimitSwitches = { customExercises: false, templates: false };
const SOLO_EJERCICIOS: PlanLimitSwitches = { customExercises: true, templates: false };
const SOLO_PLANTILLAS: PlanLimitSwitches = { customExercises: false, templates: true };
const ON: PlanLimitSwitches = { customExercises: true, templates: true };

describe("customExerciseLimitFor", () => {
  it("mapea cada tier a su tope", () => {
    expect(customExerciseLimitFor("free")).toBe(20);
    expect(customExerciseLimitFor("plan1")).toBe(60);
    expect(customExerciseLimitFor("plan2")).toBe(120);
    expect(customExerciseLimitFor("plan3")).toBeNull();
  });

  it("tier desconocido degrada a free (20)", () => {
    expect(customExerciseLimitFor("gold" as never)).toBe(20);
  });
});

describe("templateLimitFor", () => {
  it("free tiene tope 3; los pagos, sin tope", () => {
    expect(templateLimitFor("free")).toBe(3);
    expect(templateLimitFor("plan1")).toBeNull();
    expect(templateLimitFor("plan2")).toBeNull();
    expect(templateLimitFor("plan3")).toBeNull();
  });

  it("tier desconocido degrada a free (3), no a sin tope", () => {
    expect(templateLimitFor("gold" as never)).toBe(3);
  });

  it("un tier con el nombre de un metodo del prototipo tambien degrada a free", () => {
    // `hasOwnProperty` y no `in`: `"toString" in {...}` da true.
    expect(templateLimitFor("toString" as never)).toBe(3);
  });
});

describe("resolvePlanLimits — los dos apagados", () => {
  it("null en las dos claves para TODOS, sea cual sea el plan", () => {
    for (const tier of ["free", "plan1", "plan2", "plan3"] as const) {
      expect(resolvePlanLimits(sub(tier, "active"), false, NOW, OFF)).toEqual({
        customExercises: null,
        templates: null,
      });
    }
  });

  it("null incluso sin suscripcion", () => {
    expect(resolvePlanLimits(null, false, NOW, OFF)).toEqual({
      customExercises: null,
      templates: null,
    });
  });

  it("null incluso con degraded=true — apagado manda primero", () => {
    // El orden de los chequeos importa: con el interruptor apagado la
    // plomeria tiene que quedar observable SIEMPRE, incluso sobre un
    // documento roto, porque el valor que se escribe (null) no depende de
    // nada que se haya podido leer mal.
    expect(resolvePlanLimits(sub("plan2", "active"), true, NOW, OFF)).toEqual({
      customExercises: null,
      templates: null,
    });
  });
});

describe("resolvePlanLimits — ejercicios encendido", () => {
  const on = SOLO_EJERCICIOS;

  it("el numero que corresponde a cada plan", () => {
    expect(resolvePlanLimits(sub("free", "active"), false, NOW, on)).toEqual({
      customExercises: 20,
      templates: null,
    });
    expect(resolvePlanLimits(sub("plan1", "active"), false, NOW, on)).toEqual({
      customExercises: 60,
      templates: null,
    });
    expect(resolvePlanLimits(sub("plan2", "active"), false, NOW, on)).toEqual({
      customExercises: 120,
      templates: null,
    });
    expect(resolvePlanLimits(sub("plan3", "active"), false, NOW, on)).toEqual({
      customExercises: null,
      templates: null,
    });
  });

  it("sin suscripcion → free (20)", () => {
    expect(resolvePlanLimits(null, false, NOW, on)).toEqual({
      customExercises: 20,
      templates: null,
    });
  });

  it("pending/paused → free (20), aunque el tier nominal sea pago", () => {
    expect(resolvePlanLimits(sub("plan2", "pending"), false, NOW, on)).toEqual({
      customExercises: 20,
      templates: null,
    });
    expect(resolvePlanLimits(sub("plan3", "paused"), false, NOW, on)).toEqual({
      customExercises: 20,
      templates: null,
    });
  });

  it("cancelled antes de currentPeriodEnd → sigue en el tope pago", () => {
    expect(
      resolvePlanLimits(sub("plan2", "cancelled", NOW + 1000), false, NOW, on),
    ).toEqual({ customExercises: 120, templates: null });
  });

  it("cancelled despues de currentPeriodEnd → free (20)", () => {
    expect(
      resolvePlanLimits(sub("plan2", "cancelled", NOW - 1000), false, NOW, on),
    ).toEqual({ customExercises: 20, templates: null });
  });
});

describe("resolvePlanLimits — plantillas encendido", () => {
  const on = SOLO_PLANTILLAS;

  it("free → 3; los pagos, sin tope", () => {
    expect(resolvePlanLimits(sub("free", "active"), false, NOW, on)).toEqual({
      customExercises: null,
      templates: 3,
    });
    for (const tier of ["plan1", "plan2", "plan3"] as const) {
      expect(resolvePlanLimits(sub(tier, "active"), false, NOW, on)).toEqual({
        customExercises: null,
        templates: null,
      });
    }
  });

  it("sale del tier EFECTIVO: un plan pago vencido o pausado vuelve a 3", () => {
    expect(resolvePlanLimits(null, false, NOW, on)).toEqual({
      customExercises: null,
      templates: 3,
    });
    expect(resolvePlanLimits(sub("plan1", "paused"), false, NOW, on)).toEqual({
      customExercises: null,
      templates: 3,
    });
    expect(
      resolvePlanLimits(sub("plan1", "cancelled", NOW - 1000), false, NOW, on),
    ).toEqual({ customExercises: null, templates: 3 });
    expect(
      resolvePlanLimits(sub("plan1", "cancelled", NOW + 1000), false, NOW, on),
    ).toEqual({ customExercises: null, templates: null });
  });
});

describe("resolvePlanLimits — cada interruptor gobierna SOLO su clave", () => {
  // Los cuatro casos, con un PF Free (el unico que tiene numero en las dos
  // escaleras) para que un interruptor que se filtre a la otra clave se vea.
  const free = sub("free", "active");

  it("los dos apagados → las dos en null", () => {
    expect(resolvePlanLimits(free, false, NOW, OFF)).toEqual({
      customExercises: null,
      templates: null,
    });
  });

  it("los dos prendidos → los dos numeros", () => {
    expect(resolvePlanLimits(free, false, NOW, ON)).toEqual({
      customExercises: 20,
      templates: 3,
    });
  });

  it("solo ejercicios → plantillas en null aunque el Free tenga tope", () => {
    expect(resolvePlanLimits(free, false, NOW, SOLO_EJERCICIOS)).toEqual({
      customExercises: 20,
      templates: null,
    });
  });

  it("solo plantillas → ejercicios en null aunque el Free tenga tope", () => {
    expect(resolvePlanLimits(free, false, NOW, SOLO_PLANTILLAS)).toEqual({
      customExercises: null,
      templates: 3,
    });
  });
});

describe("resolvePlanLimits — degraded", () => {
  // Prendida + degraded = no tocar ESA clave. Apagada = null igual. Con una
  // prendida y otra apagada sale un mapa PARCIAL, que `sync-entitlements.ts`
  // escribe con `merge: true` (mergea mapas anidados campo por campo: probado
  // contra el emulador en `template-count.test.ts`).
  const plan2 = sub("plan2", "active");

  it("los dos prendidos → null: NO TOCA nada sobre un documento mal leido", () => {
    expect(resolvePlanLimits(plan2, true, NOW, ON)).toBeNull();
  });

  it("«no toca» tambien vale sin suscripcion previa", () => {
    expect(resolvePlanLimits(null, true, NOW, ON)).toBeNull();
  });

  it("solo ejercicios prendido → escribe plantillas en null y NO trae la clave de ejercicios", () => {
    const r = resolvePlanLimits(plan2, true, NOW, SOLO_EJERCICIOS);
    expect(r).toEqual({ templates: null });
    // `toEqual` ignora claves `undefined`: esto es lo que asegura que la
    // clave no viaja, que es lo que la deja intacta con `merge: true`.
    expect(r).not.toHaveProperty("customExercises");
  });

  it("solo plantillas prendido → escribe ejercicios en null y NO trae la clave de plantillas", () => {
    const r = resolvePlanLimits(plan2, true, NOW, SOLO_PLANTILLAS);
    expect(r).toEqual({ customExercises: null });
    expect(r).not.toHaveProperty("templates");
  });
});

describe("resolveAthleteLimits — el tope de alumnos que se publica en planLimits", () => {
  const ms = (t: { toMillis: () => number } | null) => (t ? t.toMillis() : null);

  it("degradado → null («no tocar»), nunca el fallback conservador", () => {
    expect(resolveAthleteLimits(sub("plan3", "active"), true, NOW)).toBeNull();
    expect(resolveAthleteLimits(null, true, NOW)).toBeNull();
  });

  it("sano: SIEMPRE las tres claves, con null explicito donde no hay valor", () => {
    const r = resolveAthleteLimits(sub("plan3", "active"), false, NOW)!;
    expect(Object.keys(r).sort()).toEqual(["athletes", "athletesDespues", "athletesHasta"]);
    expect(r.athletes).toBeNull(); // sin tope
    expect(r.athletesHasta).toBeNull();
    expect(r.athletesDespues).toBeNull();
  });

  it("sin suscripcion → Free (2)", () => {
    expect(resolveAthleteLimits(null, false, NOW)!.athletes).toBe(2);
  });

  it("coincide con effectiveWeightLimit en toda la matriz de estados", () => {
    // Oraculo: lo que se publica ES lo que el servidor enforza.
    const estados: SubscriptionState[] = [];
    for (const tier of ["free", "plan1", "plan2", "plan3"] as const) {
      for (const status of ["active", "grace", "pending", "paused", "cancelled"] as const) {
        for (const end of [NOW - 1, NOW + 1, null]) {
          for (const piso of [null, "plan1", "plan3"] as const) {
            estados.push({
              tier,
              status,
              currentPeriodEndMs: end,
              prepaidTier: piso,
              prepaidUntilMs: piso ? NOW + 5 : null,
            });
          }
        }
      }
    }
    for (const e of estados) {
      expect(resolveAthleteLimits(e, false, NOW)!.athletes).toBe(effectiveWeightLimit(e, NOW));
    }
  });

  it("con cambio por reloj: athletesHasta es un Timestamp en ese instante y athletesDespues el valor nuevo", () => {
    const r = resolveAthleteLimits(sub("plan2", "cancelled", NOW + 1000), false, NOW)!;
    expect(r.athletes).toBe(15);
    expect(ms(r.athletesHasta)).toBe(NOW + 1000);
    expect(r.athletesDespues).toBe(2);
  });

  it("el destino puede ser sin tope: athletesDespues null CON athletesHasta presente", () => {
    // Un cambio hacia ilimitado por reloj no existe hoy (el piso solo sostiene,
    // y vencer baja), pero el contrato lo tiene que decir: `athletesHasta` es la
    // unica clave que dice si hay cambio.
    const r = resolveAthleteLimits(
      { tier: "plan1", status: "paused", prepaidTier: "plan3", prepaidUntilMs: NOW + 10 },
      false,
      NOW,
    )!;
    expect(r.athletes).toBeNull();
    expect(ms(r.athletesHasta)).toBe(NOW + 10);
    expect(r.athletesDespues).toBe(2);
  });
});

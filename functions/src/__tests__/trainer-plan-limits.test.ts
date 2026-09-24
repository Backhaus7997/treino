/**
 * Unit tests for `resolvePlanLimits` / `customExerciseLimitFor`
 * (limite-ejercicios-pf.md, PR1). No infra — `recountCustomExercises`
 * necesita Firestore de verdad y se cubre en `custom-exercise-count.test.ts`
 * (emulador), no aca.
 */

import {
  customExerciseLimitFor,
  resolvePlanLimits,
} from "../subscriptions/trainer-plan-limits";
import { SubscriptionState } from "../subscriptions/effective-limit";

const NOW = 1_000_000;

const sub = (
  tier: SubscriptionState["tier"],
  status: SubscriptionState["status"],
  currentPeriodEndMs?: number | null,
): SubscriptionState => ({ tier, status, currentPeriodEndMs });

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

describe("resolvePlanLimits — apagado", () => {
  it("null para TODOS, sea cual sea el plan", () => {
    for (const tier of ["free", "plan1", "plan2", "plan3"] as const) {
      expect(
        resolvePlanLimits(sub(tier, "active"), false, NOW, false),
      ).toEqual({ customExercises: null });
    }
  });

  it("null incluso sin suscripcion", () => {
    expect(resolvePlanLimits(null, false, NOW, false)).toEqual({
      customExercises: null,
    });
  });

  it("null incluso con degraded=true — apagado manda primero", () => {
    // El orden de los chequeos importa: con el interruptor apagado la
    // plomeria tiene que quedar observable SIEMPRE, incluso sobre un
    // documento roto, porque el valor que se escribe (null) no depende de
    // nada que se haya podido leer mal.
    expect(resolvePlanLimits(sub("plan2", "active"), true, NOW, false)).toEqual(
      { customExercises: null },
    );
  });
});

describe("resolvePlanLimits — encendido", () => {
  const on = true;

  it("el numero que corresponde a cada plan", () => {
    expect(resolvePlanLimits(sub("free", "active"), false, NOW, on)).toEqual({
      customExercises: 20,
    });
    expect(resolvePlanLimits(sub("plan1", "active"), false, NOW, on)).toEqual({
      customExercises: 60,
    });
    expect(resolvePlanLimits(sub("plan2", "active"), false, NOW, on)).toEqual({
      customExercises: 120,
    });
    expect(resolvePlanLimits(sub("plan3", "active"), false, NOW, on)).toEqual({
      customExercises: null,
    });
  });

  it("sin suscripcion → free (20)", () => {
    expect(resolvePlanLimits(null, false, NOW, on)).toEqual({
      customExercises: 20,
    });
  });

  it("pending/paused → free (20), aunque el tier nominal sea pago", () => {
    expect(resolvePlanLimits(sub("plan2", "pending"), false, NOW, on)).toEqual(
      { customExercises: 20 },
    );
    expect(resolvePlanLimits(sub("plan3", "paused"), false, NOW, on)).toEqual({
      customExercises: 20,
    });
  });

  it("cancelled antes de currentPeriodEnd → sigue en el tope pago", () => {
    expect(
      resolvePlanLimits(sub("plan2", "cancelled", NOW + 1000), false, NOW, on),
    ).toEqual({ customExercises: 120 });
  });

  it("cancelled despues de currentPeriodEnd → free (20)", () => {
    expect(
      resolvePlanLimits(sub("plan2", "cancelled", NOW - 1000), false, NOW, on),
    ).toEqual({ customExercises: 20 });
  });
});

describe("resolvePlanLimits — degraded (encendido)", () => {
  it("devuelve null: NO TOCA — no se decide nada sobre un documento mal leido", () => {
    expect(resolvePlanLimits(sub("plan2", "active"), true, NOW, true)).toBeNull();
  });

  it("«no toca» tambien vale sin suscripcion previa", () => {
    expect(resolvePlanLimits(null, true, NOW, true)).toBeNull();
  });
});

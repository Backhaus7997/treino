/**
 * Unit tests for the effective-limit resolver (paywall PR1). No infra.
 */

import {
  effectiveWeightLimit,
  SubscriptionState,
  SubscriptionStatus,
  SUBSCRIPTION_STATUSES,
} from "../subscriptions/effective-limit";

const sub = (
  tier: SubscriptionState["tier"],
  status: SubscriptionState["status"],
  currentPeriodEndMs?: number | null,
): SubscriptionState => ({ tier, status, currentPeriodEndMs });

const NOW = 1_000_000;

describe("effectiveWeightLimit", () => {
  it("null subscription → Free (2), no backfill", () => {
    expect(effectiveWeightLimit(null, NOW)).toBe(2);
    expect(effectiveWeightLimit(undefined, NOW)).toBe(2);
  });

  it("active → the paid tier limit", () => {
    expect(effectiveWeightLimit(sub("plan1", "active"), NOW)).toBe(7);
    expect(effectiveWeightLimit(sub("plan2", "active"), NOW)).toBe(15);
  });

  it("grace → still the paid tier limit (MP retrying, ADR-3)", () => {
    expect(effectiveWeightLimit(sub("plan2", "grace"), NOW)).toBe(15);
  });

  it("pending → Free (2), no entitlement until webhook confirms", () => {
    expect(effectiveWeightLimit(sub("plan2", "pending"), NOW)).toBe(2);
  });

  it("paused → Free (2)", () => {
    expect(effectiveWeightLimit(sub("plan1", "paused"), NOW)).toBe(2);
  });

  it("cancelled before currentPeriodEnd → still paid tier", () => {
    expect(
      effectiveWeightLimit(sub("plan2", "cancelled", NOW + 1000), NOW),
    ).toBe(15);
  });

  it("cancelled after currentPeriodEnd → Free (2)", () => {
    expect(
      effectiveWeightLimit(sub("plan2", "cancelled", NOW - 1000), NOW),
    ).toBe(2);
  });

  it("cancelled with null currentPeriodEnd → Free (2)", () => {
    expect(effectiveWeightLimit(sub("plan2", "cancelled", null), NOW)).toBe(2);
  });
});

describe("plan3 — sin limite", () => {
  it("activo devuelve null (ilimitado)", () => {
    expect(effectiveWeightLimit({ tier: "plan3", status: "active" })).toBeNull();
  });

  it("grace tambien: MP reintenta, no se castiga al primer fallo", () => {
    expect(effectiveWeightLimit({ tier: "plan3", status: "grace" })).toBeNull();
  });

  it("paused cae a Free 2 aunque el tier sea ilimitado", () => {
    // El limite EFECTIVO manda sobre el nominal. Un plan3 impago no da
    // alumnos infinitos gratis.
    expect(effectiveWeightLimit({ tier: "plan3", status: "paused" })).toBe(2);
  });

  it("cancelled: ilimitado hasta currentPeriodEnd, Free despues", () => {
    const sub = {
      tier: "plan3" as const,
      status: "cancelled" as const,
      currentPeriodEndMs: 10_000,
    };
    expect(effectiveWeightLimit(sub, 9_000)).toBeNull();
    expect(effectiveWeightLimit(sub, 11_000)).toBe(2);
  });
});

/**
 * users/{uid}.subscription se escribe A MANO con el Admin SDK — no hay ninguna
 * Cloud Function que lo escriba. El tipo `SubscriptionStatus` es una promesa de
 * compilacion sobre un dato que nadie valida en runtime, asi que un typo es
 * plausible, no hipotetico. Estos casos fuerzan valores que el tipo prohibe.
 */
describe("valores desconocidos — el resolver nunca devuelve undefined", () => {
  const forged = (tier: string, status: string, currentPeriodEndMs?: number | null) =>
    ({ tier, status, currentPeriodEndMs } as unknown as SubscriptionState);

  it("status con typo ('canceled', una sola L) → Free (2)", () => {
    // Sin `default` en el switch esto devolvia undefined: el gate de
    // promote-link dejaba de denegar (`carga > undefined` es false) y el
    // barrido de sync-entitlements bloqueaba a TODOS (`carga <= undefined`
    // tambien es false). El mismo typo abria el paywall y vaciaba el padron.
    expect(effectiveWeightLimit(forged("plan2", "canceled"), NOW)).toBe(2);
  });

  it("status vacio → Free (2)", () => {
    expect(effectiveWeightLimit(forged("plan2", ""), NOW)).toBe(2);
  });

  it("tier desconocido con status valido → Free (2)", () => {
    expect(effectiveWeightLimit(forged("plan22", "active"), NOW)).toBe(2);
  });

  it("tier heredado del prototipo ('toString') → Free (2), no una funcion", () => {
    // `tier in TIER_WEIGHT_LIMITS` camina la cadena de prototipos:
    // `"toString" in {...}` da true y devolvia la FUNCION toString tipada como
    // number. Un limite que es una funcion rompe toda comparacion aguas abajo.
    expect(effectiveWeightLimit(forged("toString", "active"), NOW)).toBe(2);
  });

  it("tier desconocido + status desconocido → Free (2)", () => {
    expect(effectiveWeightLimit(forged("gold", "canceled"), NOW)).toBe(2);
  });
});

/**
 * El `default:` del switch salva el runtime pero se come la exhaustividad de
 * compilacion. En effective-limit.ts eso lo vuelve a atar el
 * `const _exhaustive: never = sub.status` — que rompe el BUILD si alguien
 * agrega un status a la union sin darle un `case`.
 *
 * Esta tabla es la segunda capa, y la que le explica el error a quien lo
 * provoque. El tipo `Record<SubscriptionStatus, ...>` obliga a declarar una
 * respuesta ESPERADA para cada miembro nuevo de la union: agregar "trialing" y
 * no tocar esto no compila en ts-jest. Sin la tabla, el escenario del enunciado
 * pasa entero — todo plan2 en trial resolveria a 2 alumnos sin error, sin test
 * rojo y sin warn (el status ES valido, asi que el mapper no lo degrada).
 *
 * Va sobre plan3 a proposito: es el unico tier donde "entitled" (null, sin
 * tope) y "no entitled" (2) no se confunden, asi que un status nuevo que caiga
 * en el default se ve como un 2 donde la tabla pedia null.
 */
describe("exhaustividad — cada status de la union tiene una respuesta DECIDIDA", () => {
  const PLAN3_POR_STATUS: Record<SubscriptionStatus, number | null> = {
    active: null,
    grace: null,
    // cancelled sin currentPeriodEnd = ya vencido ⇒ Free.
    cancelled: 2,
    pending: 2,
    paused: 2,
  };

  it.each(SUBSCRIPTION_STATUSES)("plan3 + %s", (status) => {
    expect(effectiveWeightLimit({ tier: "plan3", status }, NOW)).toBe(
      PLAN3_POR_STATUS[status],
    );
  });
});

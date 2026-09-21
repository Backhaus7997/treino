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

// ---------------------------------------------------------------------------
// EL PISO PREPAGO.
//
// Existe porque un PF que bajaba de plan3 (SIN TOPE) a plan1 (7) perdia el
// remanente que YA HABIA PAGADO: el reconciliador escribia el tier nuevo y el
// `currentPeriodEnd` del plan3 desaparecia del entitlement. El limite caia en el
// acto y el trigger le bloqueaba alumnos en la MISMA invocacion.
//
// Es un PISO, nunca un techo: solo puede SUBIR el limite. Esa asimetria es lo
// que hace seguro el cambio para los cuatro consumidores de este modulo — se
// puede regalar cupo, nunca sacarlo.
// ---------------------------------------------------------------------------

import {
  PisoPrepago,
  limitRank,
  resolverPisoPrepago,
  tierLimit,
} from "../subscriptions/effective-limit";

/** Una suscripcion con piso, que es lo que este bloque prueba. */
const conPiso = (
  tier: SubscriptionState["tier"],
  status: SubscriptionState["status"],
  piso: { tier: SubscriptionState["tier"]; untilMs: number } | null,
  currentPeriodEndMs: number | null = null,
): SubscriptionState => ({
  tier,
  status,
  currentPeriodEndMs,
  prepaidTier: piso === null ? null : piso.tier,
  prepaidUntilMs: piso === null ? null : piso.untilMs,
});

describe("effectiveWeightLimit — el piso prepago", () => {
  it("un piso plan3 sobre un plan1 activo da SIN TOPE, no 7", () => {
    // El caso que un `Math.max` a secas rompe en silencio: `null` es plan3 = SIN
    // TOPE, o sea el MAYOR, y crudo vale 0. Por eso la comparacion va por rango.
    expect(effectiveWeightLimit(
      conPiso("plan1", "active", { tier: "plan3", untilMs: NOW + 1 }), NOW))
      .toBeNull();
  });

  it("un piso VENCIDO no aporta nada", () => {
    expect(effectiveWeightLimit(
      conPiso("plan1", "active", { tier: "plan3", untilMs: NOW }), NOW)).toBe(7);
    expect(effectiveWeightLimit(
      conPiso("plan1", "active", { tier: "plan3", untilMs: NOW - 1 }), NOW))
      .toBe(7);
  });

  it("un piso MENOR que el plan vigente no baja nada — es piso, no techo", () => {
    expect(effectiveWeightLimit(
      conPiso("plan2", "active", { tier: "plan1", untilMs: NOW + 1 }), NOW))
      .toBe(15);
  });

  it("el piso NO pasa por el switch de status: un `pending` igual lo conserva", () => {
    // Un `pending` resuelve a Free. Si el piso pasara por el switch se perderia
    // justo cuando mas hace falta: el PF compro un plan que todavia no autorizo,
    // y mientras tanto conserva lo que ya pago.
    expect(effectiveWeightLimit(
      conPiso("plan1", "pending", { tier: "plan2", untilMs: NOW + 1 }), NOW))
      .toBe(15);
  });

  it("un `paused` con piso vivo tampoco cae a Free", () => {
    expect(effectiveWeightLimit(
      conPiso("plan1", "paused", { tier: "plan2", untilMs: NOW + 1 }), NOW))
      .toBe(15);
  });

  const incompletos: [string, Partial<SubscriptionState>][] = [
    ["solo tier", { prepaidTier: "plan3", prepaidUntilMs: null }],
    ["solo fecha", { prepaidTier: null, prepaidUntilMs: NOW + 1 }],
  ];
  for (const [caso, patch] of incompletos) {
    it(`un piso con ${caso} se ignora`, () => {
      expect(effectiveWeightLimit(
        { tier: "plan1", status: "active", ...patch }, NOW)).toBe(7);
    });
  }
});

describe("resolverPisoPrepago — que se conserva al cambiar de plan", () => {
  const vigente = (
    tier: SubscriptionState["tier"],
    hastaMs: number | null,
  ): SubscriptionState => ({
    tier, status: "active", currentPeriodEndMs: hastaMs,
  });

  it("el DOWNGRADE arma piso con lo que se estaba por pisar", () => {
    expect(resolverPisoPrepago(
      vigente("plan3", NOW + 1000), "plan1", "active", NOW))
      .toEqual<PisoPrepago>({ tier: "plan3", untilMs: NOW + 1000 });
  });

  it("el UPGRADE no arma piso: no hay nada que conservar", () => {
    expect(resolverPisoPrepago(
      vigente("plan1", NOW + 1000), "plan3", "active", NOW)).toBeNull();
  });

  it("reconciliar el MISMO plan no captura piso, y conserva el que habia", () => {
    // El bug de la version ingenua, que compara contra el limite EFECTIVO: ese
    // ya incluye el piso, asi que un plan1 con piso plan3 se veria a si mismo
    // como downgrade y capturaria un piso de plan1 CADA NOCHE. Escritura diaria
    // de `users/{uid}` = disparo diario del trigger que decide mails.
    const actual: SubscriptionState = {
      tier: "plan1",
      status: "active",
      currentPeriodEndMs: NOW + 500,
      prepaidTier: "plan3",
      prepaidUntilMs: NOW + 1000,
    };

    expect(resolverPisoPrepago(actual, "plan1", "active", NOW))
      .toEqual<PisoPrepago>({ tier: "plan3", untilMs: NOW + 1000 });
  });

  it("un piso vivo NUNCA se tira, aunque el plan nuevo sea mayor", () => {
    // Tirarlo BAJA el limite, y bajar el limite es revocar relaciones
    // existentes — lo que la politica de `subscription-state.ts` prohibe.
    const actual: SubscriptionState = {
      tier: "plan1",
      status: "active",
      currentPeriodEndMs: null,
      prepaidTier: "plan2",
      prepaidUntilMs: NOW + 1000,
    };

    expect(resolverPisoPrepago(actual, "plan3", "active", NOW))
      .toEqual<PisoPrepago>({ tier: "plan2", untilMs: NOW + 1000 });
  });

  it("un piso VENCIDO no se arrastra", () => {
    const actual: SubscriptionState = {
      tier: "plan1",
      status: "active",
      currentPeriodEndMs: null,
      prepaidTier: "plan3",
      prepaidUntilMs: NOW - 1,
    };

    expect(resolverPisoPrepago(actual, "plan1", "active", NOW)).toBeNull();
  });

  it("gana el piso de MAYOR tier, no el de fecha mas lejana", () => {
    const actual: SubscriptionState = {
      tier: "plan3",
      status: "active",
      currentPeriodEndMs: NOW + 10,
      prepaidTier: "plan2",
      prepaidUntilMs: NOW + 100_000,
    };

    expect(resolverPisoPrepago(actual, "plan1", "active", NOW))
      .toEqual<PisoPrepago>({ tier: "plan3", untilMs: NOW + 10 });
  });

  it("con el mismo tier gana la fecha mas lejana", () => {
    const actual: SubscriptionState = {
      tier: "plan2",
      status: "active",
      currentPeriodEndMs: NOW + 10,
      prepaidTier: "plan2",
      prepaidUntilMs: NOW + 100_000,
    };

    expect(resolverPisoPrepago(actual, "plan1", "active", NOW))
      .toEqual<PisoPrepago>({ tier: "plan2", untilMs: NOW + 100_000 });
  });

  it("sin `currentPeriodEnd` no hay piso que armar", () => {
    // Los PF sembrados a mano con el Admin SDK no lo tienen: degradan al
    // comportamiento de siempre, con un warn que los nombra en el reconciliador.
    expect(resolverPisoPrepago(
      vigente("plan3", null), "plan1", "active", NOW)).toBeNull();
  });

  it("un periodo YA VENCIDO no arma piso", () => {
    expect(resolverPisoPrepago(
      vigente("plan3", NOW), "plan1", "active", NOW)).toBeNull();
  });

  for (const entrante of ["pending", "paused", "cancelled"] as const) {
    it(`un \`${entrante}\` entrante NO captura piso nuevo`, () => {
      // Solo `active` y `grace` confirman una compra. Un `pending` no compro
      // nada todavia, y los terminales son otra politica.
      expect(resolverPisoPrepago(
        vigente("plan3", NOW + 1000), "plan1", entrante, NOW)).toBeNull();
    });
  }

  it("pero un `grace` SI: hay medio de pago y la nueva va a cobrar", () => {
    expect(resolverPisoPrepago(
      vigente("plan3", NOW + 1000), "plan1", "grace", NOW))
      .toEqual<PisoPrepago>({ tier: "plan3", untilMs: NOW + 1000 });
  });

  it("un `cancelled` vigente tambien es un periodo pago que se conserva", () => {
    // Se dio de baja de plan3 y despues compro plan1: le quedan meses de plan3
    // que pago. Sin esta rama tambien se le evaporaban.
    const actual: SubscriptionState = {
      tier: "plan3", status: "cancelled", currentPeriodEndMs: NOW + 1000,
    };

    expect(resolverPisoPrepago(actual, "plan1", "active", NOW))
      .toEqual<PisoPrepago>({ tier: "plan3", untilMs: NOW + 1000 });
  });

  it("sin suscripcion previa no hay piso", () => {
    expect(resolverPisoPrepago(null, "plan1", "active", NOW)).toBeNull();
    expect(resolverPisoPrepago(undefined, "plan1", "active", NOW)).toBeNull();
  });
});

describe("limitRank y tierLimit — la trampa de null=SIN TOPE, ya exportada", () => {
  it("null rankea por encima de cualquier numero", () => {
    expect(limitRank(null)).toBe(Number.POSITIVE_INFINITY);
    expect(limitRank(null) > limitRank(15)).toBe(true);
  });

  it("tierLimit no camina la cadena de prototipos", () => {
    expect(tierLimit("plan3")).toBeNull();
    expect(tierLimit("free")).toBe(2);
    // "toString" existe en el prototipo: con `in` devolvia una FUNCION tipada
    // como number|null y rompia toda comparacion aguas abajo, en silencio.
    expect(tierLimit("toString" as never)).toBe(2);
  });
});

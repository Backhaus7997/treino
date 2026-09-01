/**
 * Tests del canal de mail del paywall del PF (`subscriptions/subscription-mail`).
 *
 * Sin infra: las dos decisiones son puras y el enqueue se observa mockeando
 * `enqueueMail`. Lo que se protege acá es, en orden de cuanto duele si se rompe:
 *
 *   1. que el disparador sea la TRANSICION y no el estado — un disparador por
 *      estado le manda mail a todos los PF reales en el primer barrido;
 *   2. que la clave de dedupe distinga dos ciclos de facturacion de un
 *      re-disparo del mismo evento;
 *   3. que una suscripcion degradada no genere mail.
 */

import {
  decideExpiryMail,
  decideSubscriptionMail,
  enqueueSubscriptionMail,
} from "../subscriptions/subscription-mail";
import { SubscriptionState } from "../subscriptions/effective-limit";
import { MappedSubscription } from "../subscriptions/subscription-state";
import { enqueueMail } from "../mail/enqueue-mail";
import { APP_ENTRY_TRAINER } from "../mail/templates";

jest.mock("../mail/enqueue-mail", () => ({
  enqueueMail: jest.fn(async () => "queued-id"),
}));

const enqueueMock = enqueueMail as jest.MockedFunction<typeof enqueueMail>;

/** Un `MappedSubscription` sano. */
const ok = (
  tier: SubscriptionState["tier"],
  status: SubscriptionState["status"],
  currentPeriodEndMs: number | null = null,
): MappedSubscription => ({
  state: { tier, status, currentPeriodEndMs },
  degraded: false,
});

/** Sin mapa `subscription`: el PF free normal. NO es degradacion. */
const sinMapa: MappedSubscription = { state: null, degraded: false };

const NOW = 1_800_000_000_000; // 2027-01-15 aprox, ART
const DIA = 24 * 60 * 60 * 1000;

beforeEach(() => enqueueMock.mockClear());

// ---------------------------------------------------------------------------
// decideSubscriptionMail — la transicion de `subscription`
// ---------------------------------------------------------------------------
describe("decideSubscriptionMail", () => {
  it("no manda nada cuando la suscripcion no cambio", () => {
    expect(decideSubscriptionMail(ok("plan2", "active"), ok("plan2", "active"), NOW))
      .toBeNull();
  });

  it("entrar en grace manda el mail de grace", () => {
    const plan = decideSubscriptionMail(
      ok("plan2", "active", NOW + 30 * DIA),
      ok("plan2", "grace", NOW + 30 * DIA),
      NOW,
    );

    expect(plan?.kind).toBe("subscription-grace");
    // El limite que se anuncia es el PAGADO, no Free: grace conserva el tier.
    expect(plan?.params.limit).toBe(15);
    expect(plan?.params.tier).toBe("plan2");
  });

  // El re-disparo tiene el mismo before y after. `subscriptionChanged` ya lo
  // frena antes, pero la decision no puede depender de esa guarda: son dos
  // capas distintas y la de aca es la que sobrevive a un refactor del trigger.
  it("seguir en grace no vuelve a mandar", () => {
    expect(
      decideSubscriptionMail(ok("plan2", "grace"), ok("plan2", "grace"), NOW),
    ).toBeNull();
  });

  it("pausar manda el downgrade, con la causa y el limite nuevo", () => {
    const plan = decideSubscriptionMail(
      ok("plan2", "active"),
      ok("plan2", "paused"),
      NOW,
    );

    expect(plan?.kind).toBe("subscription-downgraded");
    expect(plan?.params.reason).toBe("paused");
    expect(plan?.params.limit).toBe(2);
  });

  // El caso que una lista de status se pierde: el status no cambia, cambia el
  // tier. 15 → 7 deja 8 alumnos en solo lectura sin que ninguna pantalla lo diga.
  it("bajar de tier sin cambiar de status tambien manda downgrade", () => {
    const plan = decideSubscriptionMail(
      ok("plan2", "active"),
      ok("plan1", "active"),
      NOW,
    );

    expect(plan?.kind).toBe("subscription-downgraded");
    expect(plan?.params.reason).toBe("tier-change");
    expect(plan?.params.limit).toBe(7);
  });

  // `null` = plan3 = SIN TOPE, o sea el limite MAS ALTO. Comparado como numero
  // crudo, `null > 15` es false y este downgrade —el del PF que mas paga—
  // pasaba de largo.
  it("bajar DESDE plan3 es un downgrade, no una subida", () => {
    const plan = decideSubscriptionMail(
      ok("plan3", "active"),
      ok("plan2", "active"),
      NOW,
    );

    expect(plan?.kind).toBe("subscription-downgraded");
    expect(plan?.params.limit).toBe(15);
  });

  it("subir de plan no manda nada", () => {
    expect(
      decideSubscriptionMail(ok("plan1", "active"), ok("plan2", "active"), NOW),
    ).toBeNull();
  });

  // El backfill que el diseño exige antes del enforcement: el PF pasa de no
  // tener mapa (Free 2) a tener plan2 (15). Es una SUBIDA y tiene que ser muda.
  it("provisionar la suscripcion a mano no dispara mail", () => {
    expect(decideSubscriptionMail(sinMapa, ok("plan2", "active"), NOW)).toBeNull();
  });

  // El limite NO baja al cancelar: baja en currentPeriodEnd. Anunciarlo acá
  // seria decirle Free a alguien que todavia tiene su plan pago — la
  // correccion que el PR #758 dejo pineada.
  it("cancelar con periodo vigente NO manda nada todavia", () => {
    expect(
      decideSubscriptionMail(
        ok("plan2", "active", NOW + 20 * DIA),
        ok("plan2", "cancelled", NOW + 20 * DIA),
        NOW,
      ),
    ).toBeNull();
  });

  it("cancelar con el periodo ya vencido si manda downgrade", () => {
    const plan = decideSubscriptionMail(
      ok("plan2", "active", NOW - DIA),
      ok("plan2", "cancelled", NOW - DIA),
      NOW,
    );

    expect(plan?.params.reason).toBe("cancelled-expired");
    expect(plan?.params.limit).toBe(2);
  });

  // Un solo hecho para el PF. De los dos mensajes, el de grace es el unico con
  // una accion que todavia evita la consecuencia.
  it("grace le gana al downgrade cuando pasan juntos", () => {
    const plan = decideSubscriptionMail(
      ok("plan3", "active"),
      ok("plan1", "grace"),
      NOW,
    );

    expect(plan?.kind).toBe("subscription-grace");
  });

  it("una suscripcion degradada no genera mail", () => {
    const roto: MappedSubscription = {
      state: { tier: "free", status: "paused", currentPeriodEndMs: null },
      degraded: true,
    };

    expect(decideSubscriptionMail(ok("plan2", "active"), roto, NOW)).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// El scope de dedupe — las dos mitades del requisito, que tiran para lados
// opuestos: un re-disparo NO puede mandar dos, dos ciclos SI.
// ---------------------------------------------------------------------------
describe("scope de dedupe", () => {
  const entrarEnGrace = (periodEnd: number, nowMs: number) =>
    decideSubscriptionMail(
      ok("plan2", "active", periodEnd),
      ok("plan2", "grace", periodEnd),
      nowMs,
    );

  it("el mismo ciclo colapsa aunque el evento se repita otro dia", () => {
    const a = entrarEnGrace(NOW + 5 * DIA, NOW);
    const b = entrarEnGrace(NOW + 5 * DIA, NOW + 2 * DIA);

    expect(a?.scope).toBe(b?.scope);
  });

  it("dos ciclos seguidos mandan dos mails", () => {
    const enero = entrarEnGrace(NOW, NOW);
    const febrero = entrarEnGrace(NOW + 30 * DIA, NOW + 30 * DIA);

    expect(enero?.scope).not.toBe(febrero?.scope);
  });

  // Sin esto, `plan2→plan1` y despues `plan1→paused` dentro del mismo ciclo
  // colapsan en un solo mail y el PF nunca se entera del segundo corte.
  it("dos downgrades distintos del mismo ciclo no colapsan", () => {
    const periodEnd = NOW + 10 * DIA;
    const aPlan1 = decideSubscriptionMail(
      ok("plan2", "active", periodEnd),
      ok("plan1", "active", periodEnd),
      NOW,
    );
    const aPausa = decideSubscriptionMail(
      ok("plan1", "active", periodEnd),
      ok("plan1", "paused", periodEnd),
      NOW,
    );

    expect(aPlan1?.scope).not.toBe(aPausa?.scope);
  });

  it("sin currentPeriodEnd cae al dia ART, que sigue acotando el re-disparo", () => {
    const a = entrarEnGrace(null as unknown as number, NOW);
    const b = entrarEnGrace(null as unknown as number, NOW + 60_000);

    expect(a?.scope).toBe(b?.scope);
    expect(a?.scope).toMatch(/^subgrace_\d{4}-\d{2}-\d{2}$/);
  });
});

// ---------------------------------------------------------------------------
// decideExpiryMail — la unica bajada de limite que no escribe un documento
// ---------------------------------------------------------------------------
describe("decideExpiryMail", () => {
  it("un cancelled recien vencido manda downgrade", () => {
    const plan = decideExpiryMail(ok("plan2", "cancelled", NOW - 60_000), NOW);

    expect(plan?.kind).toBe("subscription-downgraded");
    expect(plan?.params.reason).toBe("cancelled-expired");
    expect(plan?.params.limit).toBe(2);
  });

  it("un cancelled que todavia no vencio no manda nada", () => {
    expect(decideExpiryMail(ok("plan2", "cancelled", NOW + DIA), NOW)).toBeNull();
  });

  // El tope de la ventana existe para que un `cancelled` viejo no dispare un
  // aviso al primer barrido despues de un deploy — el mismo riesgo que motiva
  // disparar por transicion, entrando por la puerta donde no hay `before`.
  it("un cancelled vencido hace rato ya no es noticia", () => {
    expect(decideExpiryMail(ok("plan2", "cancelled", NOW - 5 * DIA), NOW)).toBeNull();
  });

  it("tolera un barrido perdido: 36h despues sigue avisando", () => {
    expect(
      decideExpiryMail(ok("plan2", "cancelled", NOW - 36 * 60 * 60 * 1000), NOW),
    ).not.toBeNull();
  });

  // Sin comparar los dos relojes, esto anunciaba un cambio que no ocurrio: un
  // `cancelled` de tier free vence de 2 a 2.
  it("un cancelled de tier free vence sin bajar nada: no manda", () => {
    expect(decideExpiryMail(ok("free", "cancelled", NOW - 60_000), NOW)).toBeNull();
  });

  it("ignora los status que no son cancelled", () => {
    expect(decideExpiryMail(ok("plan2", "paused", NOW - 60_000), NOW)).toBeNull();
    expect(decideExpiryMail(ok("plan2", "active", NOW - 60_000), NOW)).toBeNull();
  });

  it("una suscripcion degradada no genera mail", () => {
    expect(
      decideExpiryMail(
        { state: { tier: "plan2", status: "cancelled", currentPeriodEndMs: NOW - 1 },
          degraded: true },
        NOW,
      ),
    ).toBeNull();
  });

  // El barrido es diario y la ventana dura 48h, asi que dos corridas ven el
  // mismo vencimiento. Que colapsen depende de que el scope sea identico.
  it("dos barridos dentro de la ventana producen el mismo scope", () => {
    const end = NOW - 60_000;
    const hoy = decideExpiryMail(ok("plan2", "cancelled", end), NOW);
    const mañana = decideExpiryMail(ok("plan2", "cancelled", end), NOW + DIA);

    expect(hoy?.scope).toBe(mañana?.scope);
  });
});

// ---------------------------------------------------------------------------
// enqueueSubscriptionMail
// ---------------------------------------------------------------------------
describe("enqueueSubscriptionMail", () => {
  const app = {} as never;
  const plan = (kind: "subscription-grace" | "subscription-downgraded") => ({
    kind,
    scope: "s",
    params: { tier: "plan2", limit: 2 },
  });

  it("manda al PF, a su destino, y sin prefKey", async () => {
    await enqueueSubscriptionMail(app, "pf-1", plan("subscription-grace"), 0);

    const arg = enqueueMock.mock.calls[0][1];
    expect(arg.toUid).toBe("pf-1");
    expect(arg.params.ctaUrl).toBe(APP_ENTRY_TRAINER);
    // El PF no puede optar por no enterarse de que su servicio se corta.
    expect(arg.prefKey).toBeUndefined();
  });

  it("el downgrade lleva el conteo de bloqueados", async () => {
    await enqueueSubscriptionMail(app, "pf-1", plan("subscription-downgraded"), 5);

    expect(enqueueMock.mock.calls[0][1].params.blockedCount).toBe(5);
  });

  // En grace el limite no bajo, asi que no hay nadie bloqueado. Un `0` en los
  // params invita a que el template lo dibuje.
  it("el de grace no lleva conteo", async () => {
    await enqueueSubscriptionMail(app, "pf-1", plan("subscription-grace"), 3);

    expect(enqueueMock.mock.calls[0][1].params.blockedCount).toBeUndefined();
  });
});

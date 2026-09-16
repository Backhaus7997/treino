/**
 * El TERCER mail del paywall: el PF que nunca pago y choco el cupo Free.
 *
 * ── QUE CUIDA ESTE ARCHIVO ────────────────────────────────────────────────
 *
 * Tres clausulas, y las tres son la diferencia entre un mail y un incidente:
 *
 *   1. `degraded` → silencio. No le escribimos a nadie sobre plata en base a un
 *      documento que sabemos que leimos mal.
 *   2. `sub !== null` → silencio. Ese es CLIENTE, no prospecto: le hablan los
 *      otros dos mails, y con otras palabras. Decirle «llegaste al tope» a
 *      alguien cuya suscripcion se pauso es cambiarle el problema.
 *   3. **`blockedNow` vacio → silencio.** Esta es LA clausula. Sin ella el
 *      disparador pasa de ser por DELTA a ser por ESTADO, y «tiene alumnos
 *      bloqueados» es un estado que describe a media base: el mail le llega a
 *      todos de una. Es exactamente la trampa que documenta el encabezado de
 *      `subscription-mail.ts`.
 *
 * Cada una tiene su test, y cada test se verifico por MUTACION: sacando la
 * clausula, ESE test —y no otro— se pone rojo. Un test que pasa igual sin la
 * clausula no prueba nada.
 */

import { decideProspectMail, enqueueProspectMail } from "../subscriptions/subscription-mail";
import { SubscriptionState } from "../subscriptions/effective-limit";
import { enqueueMail } from "../mail/enqueue-mail";
import { linkLoadReconcileHandler } from "../subscriptions/link-load-reconcile";
import { syncTrainerEntitlements } from "../subscriptions/sync-entitlements";
import { trainerEntry } from "../mail/templates";
import { renderMail } from "../mail/templates";

jest.mock("../mail/enqueue-mail", () => ({
  enqueueMail: jest.fn(async () => "queued-id"),
}));

// Para el test de CABLEADO de abajo. Se mockean las DOS dependencias del
// handler y NADA mas: el camino `decideProspectMail` -> `enqueueProspectMail`
// -> `enqueueMail` corre de verdad, asi que este test prueba el cable entero y
// no un doble del cable.
jest.mock("../subscriptions/promote-link", () => ({
  syncTrainerLoad: jest.fn(async () => ({ weightedLoad: 3 })),
}));
jest.mock("../subscriptions/sync-entitlements", () => ({
  syncTrainerEntitlements: jest.fn(),
}));
jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

const enqueueMock = enqueueMail as jest.MockedFunction<typeof enqueueMail>;

// 2026-03-15T12:00:00Z = mediodia UTC, o sea las 09:00 ART del mismo dia. Se
// elige lejos de la medianoche a proposito: el scope lleva `artDateKey`, y un
// `nowMs` cerca del borde haria que el valor esperado dependiera de en que huso
// corre el test.
const AHORA = Date.parse("2026-03-15T12:00:00Z");

const pago = (
  tier: SubscriptionState["tier"],
  status: SubscriptionState["status"],
): SubscriptionState => ({ tier, status, currentPeriodEndMs: null });

const app = {} as never;

beforeEach(() => enqueueMock.mockClear());

describe("decideProspectMail", () => {
  it("el PF sin suscripcion que recien estaciona a alguien SI recibe el mail", () => {
    const plan = decideProspectMail(null, false, 2, ["atleta-3"], AHORA);

    expect(plan).not.toBeNull();
    expect(plan?.kind).toBe("limit-reached");
    expect(plan?.params.limit).toBe(2);
  });

  it("CLAUSULA 3 — sin estacionados en ESTA corrida no manda nada", () => {
    // El PF free con alumnos ya bloqueados de antes: su ESTADO dice que esta
    // sobre el tope, pero en esta corrida no se estaciono a nadie. Si esto
    // mandara mail, el disparador seria por estado y le llegaria a toda la base
    // en la primera corrida.
    expect(decideProspectMail(null, false, 2, [], AHORA)).toBeNull();
  });

  it("CLAUSULA 2 — el que TIENE suscripcion no es prospecto, aunque se estacione gente", () => {
    // Una pausa estaciona alumnos igual. Pero a este PF le habla
    // `subscription-downgraded`, que dice «poné tu suscripción al día» — una
    // frase que seria FALSA para alguien que nunca pago, y al reves tambien.
    expect(decideProspectMail(pago("plan2", "paused"), false, 2, ["a"], AHORA)).toBeNull();
    expect(decideProspectMail(pago("plan1", "active"), false, 7, ["a"], AHORA)).toBeNull();
  });

  it("CLAUSULA 1 — sobre un documento degradado no se manda nada", () => {
    expect(decideProspectMail(null, true, 2, ["a"], AHORA)).toBeNull();
  });

  it("el scope colapsa el mismo dia ART y separa dias distintos", () => {
    const hoy = decideProspectMail(null, false, 2, ["a"], AHORA);
    // El mismo dia ART, otro evento, otro conteo: MISMO scope ⇒ un solo mail.
    const mismoDia = decideProspectMail(null, false, 2, ["a", "b"], AHORA + 3600_000);
    // 24 h despues: scope distinto ⇒ el PF que vuelve a intentar crecer se
    // entera de nuevo. Sin esto seria UN mail en la vida.
    const otroDia = decideProspectMail(null, false, 2, ["a"], AHORA + 86_400_000);

    expect(mismoDia?.scope).toBe(hoy?.scope);
    expect(otroDia?.scope).not.toBe(hoy?.scope);
  });

  it("el limite viaja en el scope: dos topes distintos son dos hechos distintos", () => {
    const enDos = decideProspectMail(null, false, 2, ["a"], AHORA);
    const enSiete = decideProspectMail(null, false, 7, ["a"], AHORA);
    expect(enSiete?.scope).not.toBe(enDos?.scope);
  });
});

describe("enqueueProspectMail", () => {
  it("encola con el CTA a facturacion y el conteo de ESTADO, no el delta", async () => {
    const plan = decideProspectMail(null, false, 2, ["atleta-3"], AHORA)!;

    // 3 bloqueados en total aunque en esta corrida se haya estacionado UNO: el
    // mail describe como quedo la cuenta, no que cambio en este evento.
    await enqueueProspectMail(app, "pf-1", plan, 3);

    expect(enqueueMock).toHaveBeenCalledTimes(1);
    const arg = enqueueMock.mock.calls[0][1];
    expect(arg.toUid).toBe("pf-1");
    expect(arg.kind).toBe("limit-reached");
    expect(arg.params.blockedCount).toBe(3);
    expect(arg.params.ctaUrl).toBe(trainerEntry({ to: "facturacion" }));
    // Sin prefKey: el PF no puede optar por no enterarse de que choco el tope.
    expect(arg.prefKey).toBeUndefined();
  });
});

describe("el copy", () => {
  const render = (params: Record<string, string | number>) =>
    renderMail("limit-reached", { ctaUrl: trainerEntry({ to: "facturacion" }), ...params });

  it("NO usa el vocabulario de deuda de sus dos hermanos", () => {
    // Este PF no debe nada. «Regularizá» / «poné al día» / «no pudimos cobrar»
    // lo mandan a buscar un problema que no tiene, y encima son falsas.
    const m = render({ limit: 2, blockedCount: 3 });
    const todo = `${m.subject} ${m.text}`.toLowerCase();

    for (const prohibida of ["regulariz", "al día", "al dia", "cobrar", "vencid", "pago"]) {
      expect(todo).not.toContain(prohibida);
    }
  });

  it("dice el cupo, el conteo y que el alumno no perdio nada", () => {
    const m = render({ limit: 2, blockedCount: 3 });
    expect(m.text).toContain("2 alumnos");
    expect(m.text).toContain("3 alumnos quedaron en solo lectura");
    // La linea que el PR #758 nombra como la que nunca se recorta.
    expect(m.text).toContain("Tus alumnos no pierden nada");
    // La ETIQUETA del boton vive solo en el HTML: la parte de texto lleva la
    // URL pelada, que es lo que de verdad necesita quien lee en texto plano
    // (se aserta abajo, en su propio test).
    expect(m.html).toContain("VER LOS PLANES");
    // Y NO dice «AMPLIAR MI PLAN» ni «REGULARIZAR»: todavia no hay un plan que
    // ampliar ni nada que regularizar.
    expect(m.html).not.toContain("AMPLIAR MI PLAN");
    expect(m.html).not.toContain("REGULARIZAR");
  });

  it("singular cuando es uno solo", () => {
    expect(render({ limit: 2, blockedCount: 1 }).text).toContain("1 alumno quedó en solo lectura");
  });

  it("con blockedCount 0 la frase sigue siendo cierta y no nombra un numero", () => {
    // Alcanzable de verdad: el outbox re-renderiza al ENVIAR, y entre encolar y
    // enviar el PF puede haber sacado un alumno.
    const t = render({ limit: 2, blockedCount: 0 }).text;
    expect(t).toContain("Los alumnos que pasen ese tope quedan en solo lectura");
    expect(t).not.toContain("0 alumnos");
  });

  it("sin params no filtra undefined ni se rompe", () => {
    const m = render({});
    expect(`${m.subject} ${m.text}`).not.toMatch(/undefined|null|NaN/);
    expect(m.text).toContain("Llegaste al tope");
  });

  it("la URL del CTA viaja tambien en el texto plano", () => {
    // Un CTA que solo vive adentro de un <a> no existe para quien lee en texto.
    expect(render({ limit: 2, blockedCount: 1 }).text).toContain(
      trainerEntry({ to: "facturacion" }),
    );
  });
});

/**
 * EL CABLE, y por que tiene test propio.
 *
 * Los de arriba prueban el DECISOR, que es puro. Ninguno prueba que alguien lo
 * LLAME. Se descubrio por mutacion: sacando la llamada de
 * `linkLoadReconcileHandler`, la suite entera quedaba verde — o sea que se
 * podian borrar las seis lineas del enganche sin que nada chillara.
 *
 * Es la misma forma de falla que el guard anti-steering del PR #1141 y que los
 * tests de tap-to-load del #1137: el punto probado no era el punto.
 */
describe("el cable: linkLoadReconcileHandler encola de verdad", () => {
  const syncMock = syncTrainerEntitlements as jest.MockedFunction<
    typeof syncTrainerEntitlements
  >;

  const resultado = (over: Partial<Awaited<ReturnType<typeof syncTrainerEntitlements>>>) => ({
    trainerId: "pf-1",
    limit: 2 as number | null,
    blocked: [] as string[],
    unblocked: [] as string[],
    weightedLoad: 3,
    blockedAthleteIds: [] as string[],
    subscription: null,
    degraded: false,
    ...over,
  });

  beforeEach(() => {
    enqueueMock.mockClear();
    syncMock.mockReset();
    const { logger } = jest.requireMock("firebase-functions") as {
      logger: Record<string, jest.Mock>;
    };
    Object.values(logger).forEach((f) => f.mockClear());
  });

  it("el PF free que recien estaciona a alguien dispara el mail", async () => {
    syncMock.mockResolvedValue(
      resultado({ blocked: ["atleta-3"], blockedAthleteIds: ["atleta-3"] }),
    );

    await linkLoadReconcileHandler(app, "pf-1");

    expect(enqueueMock).toHaveBeenCalledTimes(1);
    expect(enqueueMock.mock.calls[0][1].kind).toBe("limit-reached");
    expect(enqueueMock.mock.calls[0][1].toUid).toBe("pf-1");
  });

  it("una reconciliacion que no estaciona a nadie NO manda nada", async () => {
    syncMock.mockResolvedValue(resultado({ blockedAthleteIds: ["ya-estaba"] }));

    await linkLoadReconcileHandler(app, "pf-1");

    expect(enqueueMock).not.toHaveBeenCalled();
  });

  it("si encolar explota: no relanza, y NO lo reporta como falla de reconciliacion", async () => {
    syncMock.mockResolvedValue(
      resultado({ blocked: ["atleta-3"], blockedAthleteIds: ["atleta-3"] }),
    );
    enqueueMock.mockRejectedValueOnce(new Error("firestore caido"));

    // El vinculo ya quedo reconciliado: un mail que no sale no puede hacer que
    // Eventarc reintente el evento entero.
    await expect(linkLoadReconcileHandler(app, "pf-1")).resolves.toBeUndefined();

    // Y va como `warn`, NO como `error`. El `error` de este handler significa
    // «hay UN documento roto que arreglar a mano»; si un mail fallido lo
    // dispara, alguien sale a buscar un documento que no existe y la señal de
    // los que SI estan rotos se diluye. Esto lo destapo un test que ya existia
    // (`acceptedAt mal tipado`), no una revision.
    const { logger } = jest.requireMock("firebase-functions") as {
      logger: { warn: jest.Mock; error: jest.Mock };
    };
    expect(logger.error).not.toHaveBeenCalled();
    expect(logger.warn).toHaveBeenCalledWith(
      expect.stringContaining("mail de tope alcanzado"),
      expect.objectContaining({ trainerId: "pf-1" }),
    );
  });
});

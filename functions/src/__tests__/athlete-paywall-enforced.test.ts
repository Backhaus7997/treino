/**
 * athlete-paywall-enforced.test.ts — guardas anti-loop, decision y barrido del
 * paywall del alumno. LOCAL — sin emulador.
 */

jest.mock("firebase-admin", () => {
  const firestore = jest.fn() as jest.Mock & Record<string, unknown>;
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ __fakeTimestampMs: ms, toMillis: () => ms }),
  };
  firestore.FieldValue = { delete: () => ({ __fakeFieldValue: "delete" }) };
  return { firestore, app: jest.fn(), initializeApp: jest.fn() };
});

jest.mock("firebase-admin/app", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).app());

// La puerta modular tiene que dar EL MISMO doble que la namespaced de arriba.
// Ver el encabezado de `firebase-admin-mock-surface.test.ts`.
jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeNamespaced());

import { App } from "firebase-admin/app";
import { DocumentData } from "firebase-admin/firestore";
import { dobleNamespaced } from "./helpers/modular-from-namespaced";
import {
  ATHLETE_PAYWALL_ENFORCEMENT_ENABLED,
  athletePaywallInputChanged,
  hasEntitlingSubscription,
  linkActivityChanged,
  resolveAthletePaywallEnforced,
  sweepAthletePaywallHandler,
  syncAthletePaywallEnforced,
} from "../subscriptions/athlete-paywall-enforced";

const APP = {} as App;

// ── El doble de Firestore ───────────────────────────────────────────────────
//
// Registra las escrituras Y las consultas a `trainer_links`. Las consultas se
// espian porque el costo del barrido es parte del contrato: con el interruptor
// apagado no se debe tocar esa coleccion ni una vez.

interface FakeUser {
  id: string;
  data: DocumentData;
}

interface FakeDbOpts {
  /** Los que devuelve la query del barrido. */
  athletes?: FakeUser[];
  /** Los que devuelve `doc(uid).get()`. Ausente = el doc no existe. */
  docs?: Record<string, DocumentData>;
  /** Alumnos con vinculo activo. */
  linked?: Set<string>;
  /** Alumnos cuyo `update` explota. */
  updateFails?: Set<string>;
}

function installDb(opts: FakeDbOpts) {
  const updates: Array<{ uid: string; data: DocumentData }> = [];
  const linkQueries: string[] = [];

  function usersQuery(list: FakeUser[], limitN?: number, afterId?: string) {
    const q = {
      limit: (n: number) => usersQuery(list, n, afterId),
      startAfter: (snap: { id: string }) =>
        usersQuery(list, limitN, snap.id),
      get: async () => {
        let rest = list;
        if (afterId !== undefined) {
          rest = rest.slice(rest.findIndex((u) => u.id === afterId) + 1);
        }
        const page = limitN === undefined ? rest : rest.slice(0, limitN);
        return {
          empty: page.length === 0,
          size: page.length,
          docs: page.map((u) => ({ id: u.id, data: () => u.data })),
        };
      },
    };
    return q;
  }

  function linksQuery(uid?: string) {
    const q = {
      where: () => linksQuery(uid),
      limit: () => linksQuery(uid),
      get: async () => {
        linkQueries.push(uid ?? "?");
        return { empty: !(opts.linked?.has(uid ?? "") ?? false) };
      },
    };
    return q;
  }

  (dobleNamespaced().firestore as unknown as jest.Mock).mockReturnValue({
    collection: (name: string) => {
      if (name === "users") {
        return {
          doc: (uid: string) => ({
            get: async () => ({
              exists: opts.docs?.[uid] !== undefined,
              data: () => opts.docs?.[uid],
            }),
            update: async (data: DocumentData) => {
              if (opts.updateFails?.has(uid)) throw new Error("doc corrupto");
              updates.push({ uid, data });
            },
          }),
          where: () => usersQuery(opts.athletes ?? []),
        };
      }
      if (name === "trainer_links") {
        return {
          where: (_f: string, _op: string, value: string) => linksQuery(value),
        };
      }
      throw new Error(`coleccion inesperada: ${name}`);
    },
  });

  return { updates, linkQueries };
}

const ALUMNO: DocumentData = { role: "athlete", uid: "a1" };

describe("el interruptor arranca apagado", () => {
  // Trinquete. Prenderlo sin resolver el grandfathering le rompe la edicion de
  // rutinas a todo alumno free que hoy tiene mas de 2 dias — ver el encabezado
  // del modulo. Si alguien lo prende, que rompa este test y lea el porque.
  it("ATHLETE_PAYWALL_ENFORCEMENT_ENABLED es false", () => {
    expect(ATHLETE_PAYWALL_ENFORCEMENT_ENABLED).toBe(false);
  });
});

describe("athletePaywallInputChanged — guarda anti-loop", () => {
  const sub = { status: "active" };

  it("una escritura de athletePaywallEnforced NO cuenta como cambio", () => {
    // ESTE es el test que importa. La CF escribe `athletePaywallEnforced` en
    // users/{uid}, o sea el MISMO doc que dispara su trigger. Si esto diera
    // true, cada corrida se auto-dispara para siempre.
    expect(
      athletePaywallInputChanged(
        { role: "athlete", athletePaywallEnforced: false },
        { role: "athlete", athletePaywallEnforced: true },
      ),
    ).toBe(false);
  });

  it("una escritura de weightedLoad ajena tampoco cuenta", () => {
    expect(
      athletePaywallInputChanged(
        { role: "athlete", weightedLoad: 3 },
        { role: "athlete", weightedLoad: 2 },
      ),
    ).toBe(false);
  });

  it("cambiar el status de la suscripcion SI cuenta", () => {
    expect(
      athletePaywallInputChanged(
        { athleteSubscription: { status: "active" } },
        { athleteSubscription: { status: "cancelled" } },
      ),
    ).toBe(true);
  });

  it("aparecer o desaparecer la suscripcion cuenta", () => {
    expect(athletePaywallInputChanged({}, { athleteSubscription: sub }))
      .toBe(true);
    expect(athletePaywallInputChanged({ athleteSubscription: sub }, {}))
      .toBe(true);
  });

  it("cambiar de rol cuenta", () => {
    expect(
      athletePaywallInputChanged({ role: "athlete" }, { role: "trainer" }),
    ).toBe(true);
  });

  it("el create SIEMPRE cuenta", () => {
    // Sin esta rama un alumno nuevo nace sin el campo, y para la regla ausente
    // significa NO enforced: se saltearia el paywall hasta tocar un vinculo.
    expect(athletePaywallInputChanged(undefined, { role: "athlete" }))
      .toBe(true);
  });

  it("un doc borrado no cuenta — no hay donde escribir", () => {
    expect(athletePaywallInputChanged({ role: "athlete" }, undefined))
      .toBe(false);
    expect(athletePaywallInputChanged(undefined, undefined)).toBe(false);
  });
});

describe("linkActivityChanged — guarda del trigger de vinculos", () => {
  it("una escritura de entitlement NO cuenta", () => {
    // linkLoadReconcile escribe `entitlement` en cada movimiento de carga del
    // PF. Sin este filtro cada una recalcularia el campo de un alumno cuya
    // situacion no cambio.
    expect(
      linkActivityChanged(
        { status: "active", entitlement: "entitled" },
        { status: "active", entitlement: "blocked" },
      ),
    ).toBe(false);
  });

  it("pending -> active cuenta", () => {
    expect(linkActivityChanged({ status: "pending" }, { status: "active" }))
      .toBe(true);
  });

  it("active -> terminated cuenta", () => {
    expect(linkActivityChanged({ status: "active" }, { status: "terminated" }))
      .toBe(true);
  });

  it("pending -> paused no cuenta: ninguno de los dos otorga", () => {
    expect(linkActivityChanged({ status: "pending" }, { status: "paused" }))
      .toBe(false);
  });

  it("alta y baja del doc cuentan solo si era o queda activo", () => {
    expect(linkActivityChanged(undefined, { status: "active" })).toBe(true);
    expect(linkActivityChanged(undefined, { status: "pending" })).toBe(false);
    expect(linkActivityChanged({ status: "active" }, undefined)).toBe(true);
  });
});

describe("hasEntitlingSubscription", () => {
  it("active y grace otorgan", () => {
    expect(hasEntitlingSubscription({ athleteSubscription: { status: "active" } }))
      .toBe(true);
    // grace es la ventana de reintento de cobro: cortarle las funciones ahi es
    // la peor forma de pedirle que actualice la tarjeta.
    expect(hasEntitlingSubscription({ athleteSubscription: { status: "grace" } }))
      .toBe(true);
  });

  it("cancelled y paused no otorgan", () => {
    expect(
      hasEntitlingSubscription({ athleteSubscription: { status: "cancelled" } }),
    ).toBe(false);
    expect(
      hasEntitlingSubscription({ athleteSubscription: { status: "paused" } }),
    ).toBe(false);
  });

  it("el campo ausente o basura no otorga y no revienta", () => {
    expect(hasEntitlingSubscription(undefined)).toBe(false);
    expect(hasEntitlingSubscription({})).toBe(false);
    expect(hasEntitlingSubscription({ athleteSubscription: null })).toBe(false);
    expect(hasEntitlingSubscription({ athleteSubscription: "active" }))
      .toBe(false);
    expect(hasEntitlingSubscription({ athleteSubscription: { status: 7 } }))
      .toBe(false);
  });
});

describe("resolveAthletePaywallEnforced", () => {
  it("con el interruptor apagado da false y NO consulta trainer_links", async () => {
    // El costo del barrido es parte del contrato: hoy son N lecturas y cero
    // queries. Si esta asercion cae, el barrido diario paso a costar el doble.
    const { linkQueries } = installDb({});
    await expect(resolveAthletePaywallEnforced(APP, "a1", ALUMNO, false))
      .resolves.toBe(false);
    expect(linkQueries).toEqual([]);
  });

  it("prendido: alumno sin suscripcion ni PF queda enforced", async () => {
    installDb({});
    await expect(resolveAthletePaywallEnforced(APP, "a1", ALUMNO, true))
      .resolves.toBe(true);
  });

  it("prendido: con suscripcion que otorga NO se consulta el vinculo", async () => {
    const { linkQueries } = installDb({});
    const data = { ...ALUMNO, athleteSubscription: { status: "active" } };
    await expect(resolveAthletePaywallEnforced(APP, "a1", data, true))
      .resolves.toBe(false);
    expect(linkQueries).toEqual([]);
  });

  it("prendido: con vinculo activo no se enforcea — su PF ya paga", async () => {
    installDb({ linked: new Set(["a1"]) });
    await expect(resolveAthletePaywallEnforced(APP, "a1", ALUMNO, true))
      .resolves.toBe(false);
  });

  it("prendido: un PF nunca se enforcea", async () => {
    const { linkQueries } = installDb({});
    await expect(
      resolveAthletePaywallEnforced(APP, "t1", { role: "trainer" }, true),
    ).resolves.toBe(false);
    expect(linkQueries).toEqual([]);
  });

  it("prendido: un doc legacy sin role falla ABIERTO", async () => {
    installDb({});
    await expect(resolveAthletePaywallEnforced(APP, "x", { uid: "x" }, true))
      .resolves.toBe(false);
  });
});

describe("syncAthletePaywallEnforced", () => {
  it("escribe cuando el campo esta ausente — este es el backfill", async () => {
    const { updates } = installDb({});
    const r = await syncAthletePaywallEnforced(APP, "a1", ALUMNO, false);
    expect(r).toEqual({ uid: "a1", value: false, changed: true });
    expect(updates).toEqual([
      { uid: "a1", data: { athletePaywallEnforced: false } },
    ]);
  });

  it("NO escribe si el valor ya es el correcto", async () => {
    // Segunda red contra el loop, independiente de la guarda de entrada: aun si
    // una escritura se colara, la segunda vuelta no escribe y el ciclo muere.
    const { updates } = installDb({});
    const data = { ...ALUMNO, athletePaywallEnforced: false };
    const r = await syncAthletePaywallEnforced(APP, "a1", data, false);
    expect(r).toEqual({ uid: "a1", value: false, changed: false });
    expect(updates).toEqual([]);
  });

  it("prendido: pasa un alumno de false a true", async () => {
    const { updates } = installDb({});
    const data = { ...ALUMNO, athletePaywallEnforced: false };
    const r = await syncAthletePaywallEnforced(APP, "a1", data, true);
    expect(r.changed).toBe(true);
    expect(updates).toEqual([
      { uid: "a1", data: { athletePaywallEnforced: true } },
    ]);
  });

  it("al pasar a PF LIMPIA el campo en vez de dejarlo pegado", async () => {
    // Los PF se aprovisionan con update({role:'trainer'}) sobre un doc que
    // nacio athlete. Si el campo quedara en true, la regla le gatearia la
    // rutina propia a un PF que se entrena a si mismo.
    const { updates } = installDb({});
    const data = { role: "trainer", athletePaywallEnforced: true };
    const r = await syncAthletePaywallEnforced(APP, "t1", data, true);
    expect(r).toEqual({ uid: "t1", value: false, changed: true });
    expect(updates).toEqual([
      { uid: "t1", data: { athletePaywallEnforced: false } },
    ]);
  });

  it("sin userData lo lee del doc", async () => {
    const { updates } = installDb({ docs: { a1: ALUMNO } });
    const r = await syncAthletePaywallEnforced(APP, "a1", undefined, false);
    expect(r.changed).toBe(true);
    expect(updates).toHaveLength(1);
  });

  it("un doc que no existe no se escribe", async () => {
    const { updates } = installDb({ docs: {} });
    const r = await syncAthletePaywallEnforced(APP, "fantasma", undefined);
    expect(r).toEqual({ uid: "fantasma", value: false, changed: false });
    expect(updates).toEqual([]);
  });
});

describe("sweepAthletePaywallHandler", () => {
  function alumnos(n: number, from = 0): FakeUser[] {
    return Array.from({ length: n }, (_, i) => ({
      id: `a${from + i}`,
      data: { role: "athlete" },
    }));
  }

  it("recorre a todos y cuenta los que cambiaron", async () => {
    const athletes = [
      { id: "a1", data: { role: "athlete" } },
      { id: "a2", data: { role: "athlete", athletePaywallEnforced: false } },
      { id: "a3", data: { role: "athlete" } },
    ];
    const { updates } = installDb({ athletes });

    const r = await sweepAthletePaywallHandler(APP, false);

    // a2 ya estaba en el valor correcto: se lee pero no se escribe.
    expect(r).toEqual({ scanned: 3, changed: 2 });
    expect(updates.map((u) => u.uid)).toEqual(["a1", "a3"]);
  });

  it("pagina: mas de una pagina se recorre entera", async () => {
    // 301 > SWEEP_PAGE_SIZE (300). Sin paginacion esto escaneaba 300 y dejaba
    // al ultimo alumno sin campo para siempre.
    const { updates } = installDb({ athletes: alumnos(301) });

    const r = await sweepAthletePaywallHandler(APP, false);

    expect(r).toEqual({ scanned: 301, changed: 301 });
    expect(updates).toHaveLength(301);
    expect(updates[300].uid).toBe("a300");
  });

  it("un alumno roto NO frena el barrido de los demas", async () => {
    const { updates } = installDb({
      athletes: [
        { id: "roto", data: { role: "athlete" } },
        { id: "sano", data: { role: "athlete" } },
      ],
      updateFails: new Set(["roto"]),
    });

    const r = await sweepAthletePaywallHandler(APP, false);

    expect(r).toEqual({ scanned: 2, changed: 1 });
    expect(updates.map((u) => u.uid)).toEqual(["sano"]);
  });

  it("sin alumnos no hace nada", async () => {
    const { updates } = installDb({ athletes: [] });
    await expect(sweepAthletePaywallHandler(APP, false))
      .resolves.toEqual({ scanned: 0, changed: 0 });
    expect(updates).toEqual([]);
  });
});

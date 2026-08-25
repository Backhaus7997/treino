/**
 * sync-entitlements.test.ts — el escritor de `entitlement` (downgrade).
 * LOCAL — sin emulador, con el mismo fake tx que promote-link.
 */

jest.mock("firebase-admin", () => {
  const firestore = jest.fn() as jest.Mock & Record<string, unknown>;
  const deleteSentinel = { __fakeFieldValue: "delete" };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ __fakeTimestampMs: ms, toMillis: () => ms }),
  };
  firestore.FieldValue = { delete: () => deleteSentinel };
  return { firestore };
});

// El barrido logea (error cuando saltea por degradacion). Sin este mock el
// suite escupe ruido y el test de la valvula no tendria como observarlo.
const errorSpy = jest.fn();
jest.mock("firebase-functions", () => ({
  logger: {
    warn: jest.fn(),
    info: jest.fn(),
    error: (...args: unknown[]) => errorSpy(...args),
  },
}));

import * as admin from "firebase-admin";

import { createFakeFirestore, FakeFirestoreState } from "./helpers/fake-tx-firestore";
import { syncTrainerEntitlements } from "../subscriptions/sync-entitlements";

const app = {} as admin.app.App;

function install(seed: Partial<FakeFirestoreState>) {
  const { db, state } = createFakeFirestore(seed);
  (admin.firestore as unknown as jest.Mock).mockReturnValue(db);
  return state;
}

const ts = (ms: number) => ({ __fakeTimestampMs: ms, toMillis: () => ms });

const lnk = (o: Record<string, unknown>) => ({
  trainerId: "t1",
  status: "active",
  entitlement: "entitled",
  acceptedAt: ts(1000),
  ...o,
});

beforeEach(() => jest.clearAllMocks());

describe("syncTrainerEntitlements", () => {
  it("sin suscripcion (Free 2) bloquea el excedente y deja los 2 mas antiguos", async () => {
    const state = install({
      users: { t1: {} },
      trainer_links: {
        L1: lnk({ athleteId: "a1", acceptedAt: ts(100) }),
        L2: lnk({ athleteId: "a2", acceptedAt: ts(200) }),
        L3: lnk({ athleteId: "a3", acceptedAt: ts(900) }),
        L4: lnk({ athleteId: "a4", acceptedAt: ts(800) }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.limit).toBe(2);
    expect(r.blocked.sort()).toEqual(["L3", "L4"]);
    expect(state.trainer_links.L3.entitlement).toBe("blocked");
    expect(state.trainer_links.L3.blockedReason).toBe("over-limit");
    expect(state.trainer_links.L1.entitlement).toBe("entitled");
    // weightedLoad refleja el estado YA reconciliado, no el previo.
    expect(state.users.t1.weightedLoad).toBe(2.0);
    // La lista denormalizada habla de ATLETAS, no de vinculos.
    expect(r.blockedAthleteIds).toEqual(["a3", "a4"]);
    expect(state.users.t1.blockedAthleteIds).toEqual(["a3", "a4"]);
  });

  it("plan1 activo (7) no bloquea a nadie", async () => {
    const state = install({
      users: { t1: { subscription: { tier: "plan1", status: "active" } } },
      trainer_links: {
        L1: lnk({ athleteId: "a1" }),
        L2: lnk({ athleteId: "a2" }),
        L3: lnk({ athleteId: "a3" }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.limit).toBe(7);
    expect(r.blocked).toEqual([]);
    expect(state.users.t1.weightedLoad).toBe(3.0);
    expect(state.users.t1.blockedAthleteIds).toEqual([]);
  });

  it("al volver a pagar devuelve a los bloqueados y limpia los campos", async () => {
    const state = install({
      users: {
        t1: {
          subscription: { tier: "plan1", status: "active" },
          blockedAthleteIds: ["a1"],
        },
      },
      trainer_links: {
        L1: lnk({
          athleteId: "a1",
          entitlement: "blocked",
          blockedAt: ts(1),
          blockedReason: "over-limit",
        }),
        L2: lnk({ athleteId: "a2" }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.unblocked).toEqual(["L1"]);
    expect(state.trainer_links.L1.entitlement).toBe("entitled");
    expect(state.trainer_links.L1.blockedAt).toBe(
      admin.firestore.FieldValue.delete(),
    );
    // El array anterior se REEMPLAZA entero: si sobreviviera al merge, el
    // enforcement futuro seguiria viendo bloqueado a alguien ya devuelto.
    expect(state.users.t1.blockedAthleteIds).toEqual([]);
  });

  it("cancelled: entitled hasta currentPeriodEnd, bloquea despues", async () => {
    const seed = () => ({
      users: {
        t1: {
          subscription: {
            tier: "plan1",
            status: "cancelled",
            currentPeriodEnd: ts(10_000),
          },
        },
      },
      trainer_links: {
        L1: lnk({ athleteId: "a1", acceptedAt: ts(100) }),
        L2: lnk({ athleteId: "a2", acceptedAt: ts(200) }),
        L3: lnk({ athleteId: "a3", acceptedAt: ts(300) }),
      },
    });

    install(seed());
    const antes = await syncTrainerEntitlements(app, "t1", 9_000);
    expect(antes.limit).toBe(7);
    expect(antes.blocked).toEqual([]);

    // Este es el disparador que NADIE detecta hoy: el limite cae solo por el
    // paso del tiempo, sin que se escriba un solo documento.
    install(seed());
    const despues = await syncTrainerEntitlements(app, "t1", 11_000);
    expect(despues.limit).toBe(2);
    // Cae el mas NUEVO: se conservan los dos que llegaron primero.
    expect(despues.blocked).toEqual(["L3"]);
    expect(despues.blockedAthleteIds).toEqual(["a3"]);
  });

  it("es idempotente: correr dos veces no genera cambios nuevos", async () => {
    const state = install({
      users: { t1: {} },
      trainer_links: {
        L1: lnk({ athleteId: "a1", acceptedAt: ts(100) }),
        L2: lnk({ athleteId: "a2", acceptedAt: ts(900) }),
        L3: lnk({ athleteId: "a3", acceptedAt: ts(800) }),
      },
    });

    const primera = await syncTrainerEntitlements(app, "t1", 5_000);
    expect(primera.blocked).toEqual(["L2"]);

    (admin.firestore as unknown as jest.Mock).mockReturnValue(
      createFakeFirestore(state).db,
    );
    const segunda = await syncTrainerEntitlements(app, "t1", 5_000);
    expect(segunda.blocked).toEqual([]);
    expect(segunda.unblocked).toEqual([]);
    // Sin delta, pero el estado sigue siendo el mismo estado.
    expect(segunda.blockedAthleteIds).toEqual(["a2"]);
  });
});

// ---------------------------------------------------------------------------
// `blockedAthleteIds` — la copia denormalizada en `users/{trainerId}`.
//
// INERTE: ninguna clausula de firestore.rules la lee hoy. Se escribe ya para
// que exista y sea CORRECTA antes de que el enforcement dependa de ella; estos
// tests pinean las dos formas de tenerla mal.
// ---------------------------------------------------------------------------

describe("syncTrainerEntitlements — blockedAthleteIds", () => {
  it("un alumno que se re-vinculo NO queda en la lista por su link viejo", async () => {
    // La forma ingenua (`after.filter(l => l.entitlement === "blocked")`)
    // arrastraria el `terminated` con su entitlement petrificado: ese link ya
    // no es candidato, asi que su valor no vuelve a evaluarse NUNCA y el alumno
    // quedaria bloqueado para siempre pese a tener un vinculo activo y sano.
    const state = install({
      users: { t1: { subscription: { tier: "plan1", status: "active" } } },
      trainer_links: {
        VIEJO: lnk({
          athleteId: "vuelve",
          status: "terminated",
          entitlement: "blocked",
          blockedAt: ts(1),
          blockedReason: "over-limit",
          acceptedAt: ts(100),
        }),
        NUEVO: lnk({ athleteId: "vuelve", acceptedAt: ts(900) }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.blockedAthleteIds).toEqual([]);
    expect(state.users.t1.blockedAthleteIds).toEqual([]);
    // El link terminated se deja como esta: no es candidato ni se toca.
    expect(state.trainer_links.VIEJO.entitlement).toBe("blocked");
  });

  it("VALVULA: con datos degradados la lista puede PERDER miembros, nunca ganarlos", async () => {
    // La valvula saltea `block` pero corre `unblock`. Si la lista se escribiera
    // fresca, los salteados entrarian igual por la puerta de atras — y ese
    // campo es justo el que va a leer el enforcement. Si se dejara la vieja,
    // seguiria nombrando a un alumno ya devuelto. Ninguna de las dos.
    const state = install({
      users: {
        t1: {
          // El typo: `cancelled` con una sola L. Degrada a free (2).
          subscription: { tier: "plan1", status: "canceled" },
          blockedAthleteIds: ["a1", "a4"],
        },
      },
      trainer_links: {
        L1: lnk({
          athleteId: "a1",
          entitlement: "blocked",
          blockedAt: ts(1),
          blockedReason: "over-limit",
          acceptedAt: ts(100),
        }),
        L2: lnk({ athleteId: "a2", acceptedAt: ts(200) }),
        L3: lnk({ athleteId: "a3", acceptedAt: ts(300) }),
        L4: lnk({
          athleteId: "a4",
          entitlement: "blocked",
          blockedAt: ts(1),
          blockedReason: "over-limit",
          acceptedAt: ts(400),
        }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.limit).toBe(2);
    // No se bloquea a nadie: L3 sobraba por limite, y se saltea.
    expect(r.blocked).toEqual([]);
    expect(r.unblocked).toEqual(["L1"]);
    // a1 sale (su vinculo volvio a entitled). a4 se queda: ya venia bloqueado y
    // sigue sin entrar. a3 NO entra: su vinculo no se toco, no puede aparecer.
    expect(r.blockedAthleteIds).toEqual(["a4"]);
    expect(state.users.t1.blockedAthleteIds).toEqual(["a4"]);
    expect(state.trainer_links.L3.entitlement).toBe("entitled");
    expect(state.trainer_links.L4.entitlement).toBe("blocked");
    // El desfasaje entre carga real y limite es lo que hace visible el doc roto.
    expect(r.weightedLoad).toBe(3);
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("se SALTEA el bloqueo"),
      expect.objectContaining({ trainerId: "t1", skippedBlock: ["L3"] }),
    );
  });

  it("la valvula es CONDICIONAL: con datos sanos la lista SI incorpora al salteado", async () => {
    // Mismo escenario, `status` bien escrito. Sin este control, "nunca sumar a
    // la lista" pasaria el test de arriba y el campo naceria muerto.
    const state = install({
      users: { t1: { subscription: { tier: "free", status: "active" } } },
      trainer_links: {
        L1: lnk({
          athleteId: "a1",
          entitlement: "blocked",
          blockedAt: ts(1),
          blockedReason: "over-limit",
          acceptedAt: ts(100),
        }),
        L2: lnk({ athleteId: "a2", acceptedAt: ts(200) }),
        L3: lnk({ athleteId: "a3", acceptedAt: ts(300) }),
        L4: lnk({
          athleteId: "a4",
          entitlement: "blocked",
          blockedAt: ts(1),
          blockedReason: "over-limit",
          acceptedAt: ts(400),
        }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.blocked).toEqual(["L3"]);
    expect(r.unblocked).toEqual(["L1"]);
    expect(r.blockedAthleteIds).toEqual(["a3", "a4"]);
    expect(state.users.t1.blockedAthleteIds).toEqual(["a3", "a4"]);
    expect(errorSpy).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// UN ATLETA CON VARIOS VINCULOS VIVOS, punta a punta.
//
// El duplicado es alcanzable desde el cliente: `trainer_link_repository.dart`
// crea con id autogenerado y no impide que un alumno ya vinculado vuelva a
// solicitar. Es la zona donde la decision (por atleta) y la escritura (por
// vinculo) pueden separarse — y donde el campo denormalizado se vuelve una
// afirmacion falsa sobre una PERSONA.
// ---------------------------------------------------------------------------

describe("syncTrainerEntitlements — vinculos duplicados", () => {
  const duplicados = (subscription?: Record<string, unknown>) => ({
    users: { t1: subscription ? { subscription } : {} },
    trainer_links: {
      LY: lnk({ athleteId: "aY", acceptedAt: ts(100) }),
      LZ: lnk({ athleteId: "aZ", acceptedAt: ts(200) }),
      LB: lnk({
        athleteId: "aX",
        entitlement: "blocked",
        blockedAt: ts(1),
        blockedReason: "over-limit",
        acceptedAt: ts(300),
      }),
      LP: lnk({ athleteId: "aX", status: "paused", acceptedAt: ts(400) }),
    },
  });

  it("bloquear a un atleta bloquea TODOS sus vinculos: la carga cierra con el limite", async () => {
    // El punto fijo roto: con el representante `LB` ya bloqueado el diff salia
    // vacio y `LP` seguia entitled contando 0.5. El PF quedaba en 2.5 con
    // limite 2 EN CADA CORRIDA, sin nada que escribir para arreglarlo, y
    // `blockedAthleteIds` publicaba a aX mientras su vinculo vivo decia lo
    // contrario. Cuando el enforcement lea ese campo, esa contradiccion la
    // paga el ALUMNO.
    const state = install(duplicados());

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.limit).toBe(2);
    expect(r.blocked).toEqual(["LP"]);
    expect(state.trainer_links.LP.entitlement).toBe("blocked");
    expect(state.trainer_links.LB.entitlement).toBe("blocked");
    expect(r.blockedAthleteIds).toEqual(["aX"]);
    // La cifra que delataba el bug: 2.5 con limite 2, para siempre.
    expect(state.users.t1.weightedLoad).toBe(2.0);
  });

  it("devolver a un atleta devuelve TODOS sus vinculos", async () => {
    const state = install(duplicados({ tier: "plan1", status: "active" }));

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.unblocked).toEqual(["LB"]);
    expect(state.trainer_links.LB.entitlement).toBe("entitled");
    expect(r.blockedAthleteIds).toEqual([]);
    expect(state.users.t1.weightedLoad).toBe(3.0);
  });

  it("VALVULA con duplicados: no publica a un atleta al que dejo a medio bloquear", async () => {
    // Degradado: `LP` se saltea, asi que aX conserva un vinculo entitled. La
    // resta de `skippedAthleteIds` lo tiene que sacar ENTERO de la lista — si
    // quedara, el campo diria "aX esta bloqueado" sobre alguien que sigue
    // dentro del cupo por el lado de trainer_links, que es justo la puerta de
    // atras que la valvula existe para cerrar.
    const state = install(duplicados({ tier: "plan1", status: "canceled" }));

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.limit).toBe(2);
    expect(r.blocked).toEqual([]);
    expect(state.trainer_links.LP.entitlement).toBe("entitled");
    expect(r.blockedAthleteIds).toEqual([]);
    expect(state.users.t1.blockedAthleteIds).toEqual([]);
    // Carga por encima del limite: la senal intencional de documento roto.
    expect(r.weightedLoad).toBe(2.5);
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("se SALTEA el bloqueo"),
      expect.objectContaining({ skippedBlock: ["LP"] }),
    );
  });
});

// ---------------------------------------------------------------------------
// DOCUMENTOS DEFECTUOSOS.
// ---------------------------------------------------------------------------

describe("syncTrainerEntitlements — trainer_link sin athleteId", () => {
  it("se saltea y se logea, en vez de voltear la reconciliacion entera", async () => {
    // Desde que `athleteId` viaja al array que se escribe en
    // `users/{trainerId}`, un `undefined` dejo de ser una clave fea de Map: el
    // Admin SDK rechaza `undefined` dentro de un array, asi que UN documento
    // roto tiraba toda la transaccion — ni entitlements ni `weightedLoad` — y
    // los dos llamadores hacen catch-and-log sin relanzar. Ese PF dejaba de
    // reconciliar PARA SIEMPRE con solo un warn en Cloud Logging.
    //
    // El fake tx de estos tests guarda objetos en memoria y no puede
    // reproducir el throw del SDK (eso se confirmo contra el emulador). Lo que
    // este test pinea es la conducta observable: el link roto no compite por
    // cupo, no ensucia la lista, y queda un `error` accionable. Si se
    // reintroduce el cast a ciegas, `ROTO` pasa a ser candidato, se lo bloquea
    // por exceso y `blockedAthleteIds` sale con un `undefined` adentro.
    const state = install({
      users: { t1: {} },
      trainer_links: {
        L1: lnk({ athleteId: "a1", acceptedAt: ts(100) }),
        L2: lnk({ athleteId: "a2", acceptedAt: ts(200) }),
        ROTO: lnk({ acceptedAt: ts(900) }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    expect(r.limit).toBe(2);
    expect(r.blocked).toEqual([]);
    expect(r.blockedAthleteIds).toEqual([]);
    expect(state.users.t1.blockedAthleteIds).toEqual([]);
    expect(state.users.t1.weightedLoad).toBe(2.0);
    // No se lo toca: no hay decision sensata sobre un vinculo sin duenio.
    expect(state.trainer_links.ROTO.entitlement).toBe("entitled");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("sin athleteId"),
      expect.objectContaining({ trainerId: "t1", skippedLinkIds: ["ROTO"] }),
    );
  });
});

describe("syncTrainerEntitlements — acceptedAt corrupto", () => {
  // Desde el slice 5 firestore.rules pinnea `acceptedAt` en los dos verbos del
  // cliente (create solo admite null, update lo congela equal-to-existing), asi
  // que hoy ningun member le mete un string. Este test NO es historia vieja: el
  // Admin SDK bypasea rules y los docs escritos ANTES del pin siguen en la
  // base, porque la regla vieja dejaba a cualquiera de los dos members
  // reescribir el campo por update. Con `acceptedAt.toMillis()` a secas eso
  // tiraba TypeError, volteaba la transaccion, y como los dos llamadores hacen
  // catch-and-log sin relanzar, el PF dejaba de reconciliar para TODOS sus
  // alumnos: un solo dato roto le apagaba el barrido al entrenador entero.
  it("un acceptedAt que no es Timestamp no voltea la reconciliacion", async () => {
    const state = install({
      users: { t1: {} },
      trainer_links: {
        VIEJO: lnk({ athleteId: "a1", acceptedAt: ts(100) }),
        MEDIO: lnk({ athleteId: "a2", acceptedAt: ts(200) }),
        // Un string donde iba un Timestamp.
        CORRUPTO: lnk({ athleteId: "a3", acceptedAt: "2026-01-01" }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    // La reconciliacion CORRE: sin la lectura defensiva, esto tiraba.
    expect(r.limit).toBe(2);
    expect(state.users.t1.weightedLoad).toBe(2.0);

    // Y falla del lado correcto: el faltante vale POSITIVE_INFINITY, o sea que
    // el vinculo con la fecha rota cae PRIMERO. Quien rompio su propio dato
    // paga el costo; los otros dos alumnos no se enteran.
    expect(r.blockedAthleteIds).toEqual(["a3"]);
    expect(state.trainer_links.CORRUPTO.entitlement).toBe("blocked");
    expect(state.trainer_links.VIEJO.entitlement).toBe("entitled");
    expect(state.trainer_links.MEDIO.entitlement).toBe("entitled");
  });

  it("acepta cualquier objeto con toMillis(), no solo la clase real", async () => {
    // El chequeo es por FORMA a proposito: `instanceof` se rompe contra los
    // dobles de test, y el cliente no puede escribir una funcion en Firestore.
    const state = install({
      users: { t1: {} },
      trainer_links: {
        L1: lnk({ athleteId: "a1", acceptedAt: ts(100) }),
        L2: lnk({ athleteId: "a2", acceptedAt: ts(200) }),
        L3: lnk({ athleteId: "a3", acceptedAt: ts(300) }),
      },
    });

    const r = await syncTrainerEntitlements(app, "t1", 5_000);

    // Si `toMillis` no se leyera, los tres serian POSITIVE_INFINITY y el
    // desempate por id decidiria: quedarian L1 y L2 igual, y el test no
    // discriminaria. Por eso el mas nuevo es L3 y ademas el ultimo por id.
    expect(r.blockedAthleteIds).toEqual(["a3"]);
    expect(state.trainer_links.L3.entitlement).toBe("blocked");
  });
});

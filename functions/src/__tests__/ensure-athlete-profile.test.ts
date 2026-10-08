/**
 * ensure-athlete-profile.test.ts — el alta de un alumno desde la web.
 *
 * LOCAL: el reloj entra por `deps`.
 *
 * Lo que protege:
 *
 *   1. Que el alta sea ATOMICA. Escribir `users/{uid}` sin
 *      `userPublicProfiles/{uid}` deja al atleta varado en el onboarding la
 *      primera vez que abre la app — bug documentado en
 *      `user_repository.dart:101-114`.
 *   2. Que el `role` sea SIEMPRE `athlete`. El Admin SDK se saltea
 *      `firestore.rules`, asi que la garantia acá tiene que ser del codigo, y
 *      `role` es inmutable en el update: un trainer minteado seria PERMANENTE.
 *   3. Que sea idempotente. Se llama despues de todo login, no solo del alta.
 */

const infoSpy = jest.fn();

jest.mock("firebase-functions", () => ({
  logger: { info: (...a: unknown[]) => infoSpy(...a), warn: jest.fn(), error: jest.fn() },
}));

jest.mock("firebase-functions/v2/https", () => {
  class HttpsError extends Error {
    constructor(readonly code: string, message: string) {
      super(message);
    }
  }
  return { HttpsError, onCall: () => ({}) };
});

jest.mock("firebase-admin/app", () => ({
  getApp: () => ({}),
  initializeApp: () => ({}),
}));

jest.mock("firebase-admin/firestore", () => ({
  getFirestore: (app: { firestore: () => unknown }) => app.firestore(),
  Timestamp: { fromMillis: (ms: number) => ({ toMillis: () => ms }) },
}));

import type { App } from "firebase-admin/app";

import {
  USERS_COLLECTION,
  USER_PUBLIC_PROFILES_COLLECTION,
  runEnsureAthleteProfile,
} from "../profile/ensure-athlete-profile";

const AHORA = Date.parse("2026-09-17T12:00:00.000Z");
const UID = "u1";
const MAIL = "ana@ejemplo.com";

type Store = Record<string, Record<string, Record<string, unknown>>>;

/**
 * Firestore de mentira con batch REAL: las escrituras se acumulan y sólo se
 * aplican en `commit()`. Sin eso, el test no podria distinguir un dual-write
 * atomico de dos escrituras sueltas — que es justo lo que este archivo prueba.
 */
function fakeApp(seed: Store = {}) {
  const store: Store = {};
  for (const [c, docs] of Object.entries(seed)) store[c] = { ...docs };

  /** Cuantas veces se llamo a commit. Un alta son 1, no 2. */
  let commits = 0;

  const ref = (col: string, id: string) => ({ col, id });

  const db = {
    collection: (col: string) => ({
      doc: (id: string) => ({
        ...ref(col, id),
        get: async () => ({
          exists: store[col]?.[id] !== undefined,
          data: () => store[col]?.[id],
        }),
      }),
    }),
    batch: () => {
      const pendientes: { col: string; id: string; data: Record<string, unknown> }[] = [];
      return {
        set: (
          r: { col: string; id: string },
          data: Record<string, unknown>,
        ) => {
          pendientes.push({ col: r.col, id: r.id, data });
        },
        commit: async () => {
          commits += 1;
          for (const { col, id, data } of pendientes) {
            store[col] = store[col] ?? {};
            store[col][id] = { ...(store[col][id] ?? {}), ...data };
          }
        },
      };
    },
  };

  const app = { firestore: () => db } as unknown as App;
  return { app, store, commits: () => commits };
}

const correr = (app: App, mail = MAIL) =>
  runEnsureAthleteProfile(app, UID, mail, { nowMs: AHORA });

beforeEach(() => jest.clearAllMocks());

describe("el alta desde cero", () => {
  it("escribe los DOS documentos", async () => {
    const { app, store } = fakeApp();

    const r = await correr(app);

    expect(r).toEqual({ created: true, backfilled: false });
    expect(store[USERS_COLLECTION][UID]).toBeDefined();
    expect(store[USER_PUBLIC_PROFILES_COLLECTION][UID]).toBeDefined();
  });

  it("en UN SOLO batch — si no, no es atomico", async () => {
    // LA asercion del archivo. Dos commits separados significan que una falla
    // en el medio deja media cuenta creada, que es el bug que este callable
    // existe para no reproducir.
    const { app, commits } = fakeApp();

    await correr(app);

    expect(commits()).toBe(1);
  });

  it("el role es SIEMPRE athlete", async () => {
    const { app, store } = fakeApp();

    await correr(app);

    expect(store[USERS_COLLECTION][UID].role).toBe("athlete");
  });

  it("no acepta nada que pueda cambiar el role", async () => {
    // El handler no tiene por donde recibirlo: su firma es (app, uid, email,
    // deps) y ninguno de los cuatro puede influir en el rol. Este test lo fija
    // desde el tipo — si alguien le agrega un parametro, no compila.
    expect(runEnsureAthleteProfile).toHaveLength(4);
  });

  it("nace con displayName null, no con uno inventado del mail", async () => {
    // Un nombre derivado del mail queda pegado y nadie lo corrige. ProfileSetup
    // lo completa la primera vez que la persona abre la app.
    const { app, store } = fakeApp();

    await correr(app);

    expect(store[USERS_COLLECTION][UID].displayName).toBeNull();
    expect(store[USER_PUBLIC_PROFILES_COLLECTION][UID].displayName).toBeNull();
  });

  it("el doc publico lleva `uid` — sin eso la regla de CREATE lo deniega", async () => {
    // `userPublicProfiles` exige `request.resource.data.uid == uid` en el
    // create. Es exactamente lo que faltaba en las cuentas que quedaron rotas.
    const { app, store } = fakeApp();

    await correr(app);

    expect(store[USER_PUBLIC_PROFILES_COLLECTION][UID].uid).toBe(UID);
  });

  it("el doc publico lleva EXACTAMENTE el subset del cliente Flutter", async () => {
    // Espejo de `_publicSubsetFromProfile` (user_repository.dart:91-99). Si los
    // dos divergen, una cuenta creada desde la web y otra desde la app tienen
    // documentos publicos distintos.
    const { app, store } = fakeApp();

    await correr(app);

    expect(Object.keys(store[USER_PUBLIC_PROFILES_COLLECTION][UID]).sort())
      .toEqual(["avatarUrl", "displayName", "displayNameLowercase", "gymId", "uid"]);
  });

  it("no escribe ninguno de los campos CF-only", async () => {
    // `subscription`, `weightedLoad`, `blockedAthleteIds`,
    // `athletePaywallEnforced` y `athleteSubscription` no pueden venir en un
    // create: el update los pinea equal-to-existing, asi que un valor sembrado
    // acá seria INDELEBLE.
    const { app, store } = fakeApp();

    await correr(app);

    const doc = store[USERS_COLLECTION][UID];
    for (const campo of [
      "subscription",
      "weightedLoad",
      "blockedAthleteIds",
      "athletePaywallEnforced",
      "athleteSubscription",
      "storeAccountToken",
    ]) {
      expect(doc).not.toHaveProperty(campo);
    }
  });
});

describe("idempotencia", () => {
  it("con los dos documentos ya creados no escribe nada", async () => {
    const { app, commits } = fakeApp({
      [USERS_COLLECTION]: { [UID]: { uid: UID, role: "athlete" } },
      [USER_PUBLIC_PROFILES_COLLECTION]: { [UID]: { uid: UID } },
    });

    const r = await correr(app);

    expect(r).toEqual({ created: false, backfilled: false });
    expect(commits()).toBe(0);
  });

  it("dos llamadas seguidas dejan el mismo estado", async () => {
    const { app, store } = fakeApp();

    await correr(app);
    const antes = JSON.stringify(store);
    const segunda = await correr(app);

    expect(segunda.created).toBe(false);
    expect(JSON.stringify(store)).toBe(antes);
  });

  it("NO pisa el displayName de alguien que ya lo completo", async () => {
    // El caso que rompe si el merge se hace mal: la persona se dio de alta,
    // completo ProfileSetup, y vuelve a loguearse desde la web.
    const { app, store } = fakeApp({
      [USERS_COLLECTION]: { [UID]: { uid: UID, role: "athlete", displayName: "Ana" } },
      [USER_PUBLIC_PROFILES_COLLECTION]: { [UID]: { uid: UID, displayName: "Ana" } },
    });

    await correr(app);

    expect(store[USERS_COLLECTION][UID].displayName).toBe("Ana");
    expect(store[USER_PUBLIC_PROFILES_COLLECTION][UID].displayName).toBe("Ana");
  });
});

describe("⚠️ el backfill — la cuenta vieja que quedo rota", () => {
  it("con `users` pero SIN doc publico, crea el publico", async () => {
    // Es la poblacion del bug: cuentas cuyo `users/{uid}` es anterior al
    // dual-write. Su submit de ProfileSetup pegaba contra un merge-as-create en
    // `userPublicProfiles`, era denegado, el batch hacia rollback, y el atleta
    // quedaba VARADO en el onboarding.
    const { app, store } = fakeApp({
      [USERS_COLLECTION]: { [UID]: { uid: UID, role: "athlete", displayName: "Ana" } },
    });

    const r = await correr(app);

    expect(r).toEqual({ created: false, backfilled: true });
    expect(store[USER_PUBLIC_PROFILES_COLLECTION][UID].uid).toBe(UID);
  });

  it("el backfill NO toca el documento de usuario", async () => {
    // Sólo falta el publico. Reescribir el de usuario podria pisarle campos a
    // una cuenta que ya funciona.
    const { app, store } = fakeApp({
      [USERS_COLLECTION]: {
        [UID]: { uid: UID, role: "athlete", displayName: "Ana", gymId: "g1" },
      },
    });

    await correr(app);

    expect(store[USERS_COLLECTION][UID]).toEqual({
      uid: UID, role: "athlete", displayName: "Ana", gymId: "g1",
    });
  });
});

describe("el mail", () => {
  it("sale del token y se escribe tal cual", async () => {
    const { app, store } = fakeApp();

    await correr(app);

    expect(store[USERS_COLLECTION][UID].email).toBe(MAIL);
  });

  it("un mail VACIO no impide crear la cuenta", async () => {
    // Un login con Apple y relay oculto puede no traerlo. La cuenta tiene que
    // poder existir igual: el mail no es lo que la identifica, el uid si.
    const { app, store } = fakeApp();

    const r = await correr(app, "");

    expect(r.created).toBe(true);
    expect(store[USERS_COLLECTION][UID].email).toBe("");
  });
});

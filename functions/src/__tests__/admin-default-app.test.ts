/**
 * admin-default-app.test.ts — ningun trigger depende de que OTRO haya
 * inicializado firebase-admin.
 *
 * LOCAL, sin emulador.
 *
 * El incidente: `index.ts` NO llama a `initializeApp()`. Cada modulo se lo
 * asegura solo con su `ensureApp()` (getApp, y si no hay, initializeApp). Las
 * cuarentenas de moderacion, `ensureStoreAccountToken` y
 * `propagateGymNameToProfiles` hacian `getFirestore()` SIN argumento, que
 * busca el app por defecto, y en produccion fallaban en CADA invocacion con
 * «The default Firebase app does not exist» desde el primer deploy. La
 * cuarentena de 1.2 no corrio nunca.
 *
 * Los tests de esos modulos no lo veian porque hacian `initializeApp()` ellos
 * mismos en el `beforeAll`: le daban al codigo justo lo que produccion no le
 * da.
 *
 * Dos capas:
 *
 *   1. RUNTIME: se invoca cada handler afectado en un proceso donde nadie
 *      inicializo nada, con el `getFirestore` REAL de firebase-admin (que es
 *      el que tira el error). Lo que devuelve se reemplaza por una base que
 *      explota con un centinela al primer uso: si el handler llega al
 *      centinela, ya paso el punto donde fallaba en produccion.
 *
 *   2. ESTATICO: ningun archivo de `src/` llama a un getter de firebase-admin
 *      sin pasarle el app. Cubre los modulos que se agreguen despues y que la
 *      capa 1 no enumera.
 */

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentWritten: (_opts: unknown, handler: unknown) => handler,
  onDocumentCreated: (_opts: unknown, handler: unknown) => handler,
}));
jest.mock("firebase-functions/v2/https", () => ({
  ...jest.requireActual("firebase-functions/v2/https"),
  onCall: (_opts: unknown, handler: unknown) => handler,
}));

const CENTINELA = "CENTINELA: el handler llego a usar la base";

jest.mock("firebase-admin/firestore", () => {
  const actual = jest.requireActual("firebase-admin/firestore");
  // Una base que explota al primer uso. `then` queda undefined para que un
  // `await` sobre ella no la confunda con una promesa.
  const explota = new Proxy(
    {},
    {
      get(_t, prop) {
        if (prop === "then") return undefined;
        throw new Error(CENTINELA);
      },
    },
  );
  return {
    ...actual,
    getFirestore: jest.fn((...args: unknown[]) => {
      // El getter REAL primero: sin app explicito y sin app por defecto, es
      // ESTE el que tira «The default Firebase app does not exist».
      actual.getFirestore(...args);
      return explota;
    }),
  };
});

import { readFileSync } from "fs";
import { join, relative } from "path";

import { deleteApp, getApps } from "firebase-admin/app";

import { propagateGymNameToProfiles } from "../gyms/propagate-gym-name";
import { notifyReportCreated } from "../moderation/notify-report-created";
import {
  quarantineChatMessage,
  quarantineDisplayNameOnWrite,
  quarantineGym,
  quarantinePost,
  quarantinePublicProfileName,
  quarantineReview,
  quarantineRoutine,
  quarantineTrainerProfileName,
} from "../moderation/quarantine-vetted-content";
import {
  listPendingReports,
  markReportViewed,
  moderationStats,
} from "../moderation/report-review";
import { ensureStoreAccountToken } from "../subscriptions/store-account-token";

const VETADO = "sos un hijo de puta";

/** Un snapshot armado a mano: lo minimo que leen los handlers. */
function snap(path: string, data: Record<string, unknown>) {
  return {
    exists: true,
    ref: { path },
    updateTime: { toMillis: () => 0 },
    get: (campo: string) => data[campo],
    data: () => data,
  };
}

function escritura(path: string, before: object, after: object) {
  return {
    data: { before: snap(path, { ...before }), after: snap(path, { ...after }) },
    params: {
      uid: "u1",
      gymId: "g1",
      reportId: "r1",
      routineId: "rt1",
      postId: "p1",
      reviewId: "rv1",
      chatId: "c1",
      messageId: "m1",
    },
  };
}

const moderador = {
  auth: { uid: "mod1", token: { moderator: true } },
  data: { reportId: "r1" },
};

type Handler = (arg: unknown) => Promise<unknown>;

const CASOS: Array<[string, unknown, unknown]> = [
  ["quarantineDisplayNameOnWrite", quarantineDisplayNameOnWrite,
    escritura("users/u1", {}, { displayName: VETADO })],
  ["quarantinePublicProfileName", quarantinePublicProfileName,
    escritura("userPublicProfiles/u1", {}, { displayName: VETADO })],
  ["quarantineTrainerProfileName", quarantineTrainerProfileName,
    escritura("trainerPublicProfiles/u1", {}, { displayName: VETADO })],
  ["quarantineChatMessage", quarantineChatMessage,
    escritura("chats/c1/messages/m1", {}, { text: VETADO })],
  ["quarantineGym", quarantineGym,
    escritura("gyms/g1", {}, { name: VETADO })],
  ["quarantineRoutine", quarantineRoutine,
    escritura("routines/rt1", {}, { name: VETADO, createdBy: "u1" })],
  ["quarantinePost", quarantinePost,
    escritura("posts/p1", {}, { text: VETADO, authorUid: "u1" })],
  ["quarantineReview", quarantineReview,
    escritura("reviews/rv1", {}, { comment: VETADO, athleteId: "u1" })],
  ["ensureStoreAccountToken", ensureStoreAccountToken,
    escritura("users/u1", {}, { role: "athlete" })],
  ["propagateGymNameToProfiles", propagateGymNameToProfiles,
    escritura("gyms/g1", { name: "Viejo" }, { name: "Nuevo" })],
  ["notifyReportCreated", notifyReportCreated, {
    data: snap("reports/r1", { targetKind: "post", reason: "spam" }),
    params: { reportId: "r1" },
  }],
  ["listPendingReports", listPendingReports, moderador],
  ["markReportViewed", markReportViewed, moderador],
  ["moderationStats", moderationStats, moderador],
];

/** Borra todo app de firebase-admin: cada handler arranca en frio. */
async function limpiarApps(): Promise<void> {
  await Promise.all(getApps().map((app) => deleteApp(app)));
}

// Sin esto, el primer caso que llama a `ensureApp()` deja el app por defecto
// registrado y todos los siguientes corren con la inicializacion global que
// este test dice excluir. Los modulos no cachean el App (getApp() en cada
// llamada), asi que borrarlo entre casos es seguro.
beforeEach(limpiarApps);
afterAll(limpiarApps);

describe("los triggers no dependen del app por defecto de otro modulo", () => {
  it("arranca SIN app inicializado (si no, el test no mide nada)", () => {
    expect(getApps()).toHaveLength(0);
  });

  it.each(CASOS)("%s llega a la base sin «default app does not exist»",
    async (_nombre, handler, evento) => {
      expect(getApps()).toHaveLength(0);
      await expect((handler as Handler)(evento)).rejects.toThrow(CENTINELA);
    });
});

describe("ningun getter de firebase-admin sin el app", () => {
  // `getFirestore()` vacio resuelve el app por defecto, que en produccion
  // NADIE crea. Siempre `getFirestore(ensureApp())` o el app que se recibio.
  const GETTERS = [
    "getFirestore", "getAuth", "getStorage", "getMessaging", "getAppCheck",
    "getDatabase", "getRemoteConfig", "getInstallations", "getFunctions",
    "getEventarc", "getSecurityRules", "getProjectManagement",
  ];
  // `\s` incluye saltos de linea: `getFirestore(\n)` tambien cuenta.
  const GETTER_SIN_APP = new RegExp(
    `\\b(${GETTERS.join("|")})\\s*\\(\\s*\\)`, "g");

  /**
   * Hallazgos de un fuente. Se quitan los comentarios CONSERVANDO los saltos
   * de linea (para que el numero de linea siga siendo el real) y se busca
   * sobre el archivo entero, no linea por linea.
   */
  function hallazgosEn(fuente: string): Array<{ linea: number; texto: string }> {
    const sinComentarios = fuente
      .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, " "))
      .replace(/\/\/[^\n]*/g, (m) => " ".repeat(m.length));
    return [...sinComentarios.matchAll(GETTER_SIN_APP)].map((m) => ({
      linea: sinComentarios.slice(0, m.index).split("\n").length,
      texto: m[0].replace(/\s+/g, " "),
    }));
  }

  function archivos(dir: string): string[] {
    const fs = jest.requireActual("fs") as typeof import("fs");
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
      const ruta = join(dir, e.name);
      if (e.isDirectory()) return e.name === "__tests__" ? [] : archivos(ruta);
      return e.name.endsWith(".ts") ? [ruta] : [];
    });
  }

  it("no hay ninguno en src/", () => {
    const src = join(__dirname, "..");
    const hallazgos = archivos(src).flatMap((f) =>
      hallazgosEn(readFileSync(f, "utf8")).map(
        ({ linea, texto }) => `${relative(src, f)}:${linea}: ${texto}`),
    );
    // Control: el escaneo tiene que haber visto archivos. Un glob roto da
    // cero hallazgos y sale verde sin haber mirado nada.
    expect(archivos(src).length).toBeGreaterThan(20);
    expect(hallazgos).toEqual([]);
  });

  // Control del escaneo mismo: si no detecta lo que dice detectar, el verde
  // de arriba no prueba nada.
  it("detecta getters vacios en una linea y en varias", () => {
    expect(hallazgosEn("const db = getFirestore();")).toHaveLength(1);
    expect(hallazgosEn("const db = getFirestore(\n);")).toHaveLength(1);
    expect(hallazgosEn("const db = getAuth (\n  \n  )")).toHaveLength(1);
    expect(hallazgosEn("x\ny\nconst db = getFirestore(\n);")[0].linea)
      .toBe(3);
  });

  it("no marca getters con app ni los nombrados en comentarios", () => {
    expect(hallazgosEn("getFirestore(app)")).toEqual([]);
    expect(hallazgosEn("getFirestore(ensureApp())")).toEqual([]);
    expect(hallazgosEn("// getFirestore()")).toEqual([]);
    expect(hallazgosEn("/* getFirestore(\n) */")).toEqual([]);
  });
});

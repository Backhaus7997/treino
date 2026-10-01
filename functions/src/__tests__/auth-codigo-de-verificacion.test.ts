/**
 * auth-codigo-de-verificacion.test.ts — el código de 6 dígitos que confirma el
 * mail.
 *
 * LOCAL: Firestore en memoria (con transacciones optimistas de verdad) y Auth
 * falso. El reloj y el generador del código entran por `deps`.
 *
 * Lo que protege, en orden de que tan caro sale:
 *
 *   1. Que nadie se marque verificado sin el código: ni adivinándolo (5
 *      intentos), ni reusando uno viejo, ni con el de otra cuenta.
 *   2. Que el mail que sale sea el del ROL correcto: el del alumno lleva al
 *      checkout de la landing; el del entrenador, a los planes del Coach Hub.
 *   3. Que el código nunca quede guardado en claro donde se verifica.
 *   4. Que un mail que no salió no deje al usuario esperando un cooldown.
 */

import { createHash } from "crypto";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), error: jest.fn(), warn: jest.fn() },
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

const ts = (ms: number) => ({ toMillis: () => ms, __ts: true });

jest.mock("firebase-admin/firestore", () => ({
  getFirestore: (app: { firestore: () => unknown }) => app.firestore(),
  FieldValue: { serverTimestamp: () => ({ __sentinel: "now" }) },
  Timestamp: {
    fromMillis: (ms: number) => ts(ms),
    fromDate: (d: Date) => ts(d.getTime()),
  },
}));

const mockEmails: Record<string, string> = {};
const mockUpdateUser = jest.fn<Promise<unknown>, unknown[]>(async () => ({}));

jest.mock("firebase-admin/auth", () => ({
  getAuth: () => ({
    getUser: async (uid: string) => ({ uid, email: mockEmails[uid] }),
    updateUser: (...a: unknown[]) => mockUpdateUser(...a),
  }),
}));

import {
  CODIGO_VIGENCIA_MS,
  MAX_INTENTOS,
  REENVIO_COOLDOWN_MS,
  VERIFICACIONES_COLLECTION,
  generarCodigo,
  runSolicitarCodigo,
  runVerificarCodigo,
} from "../auth/codigo-de-verificacion";
import { Store, fakeApp } from "./helpers/firestore-en-memoria";

const AHORA = Date.parse("2026-10-01T12:00:00.000Z");
const ALUMNA = "u1";
const PROFE = "t1";
const OTRA = "u2";

const sha = (s: string) => createHash("sha256").update(s).digest("hex");

const MUNDO = (): Store => ({
  users: {
    [ALUMNA]: { role: "athlete" },
    [PROFE]: { role: "trainer" },
    [OTRA]: { role: "athlete" },
  },
});

/**
 * Pide el código fijando cuál sale. `reenviar` = el botón «Reenviar»; sin él es
 * el pedido automático de la pantalla al abrirse.
 */
const pedir = (
  app: Parameters<typeof runSolicitarCodigo>[0], uid: string, codigo: string, nowMs = AHORA,
  reenviar = false,
) =>
  runSolicitarCodigo(app, uid, { nowMs, generarCodigo: () => codigo }, { reenviar });

const verificar = (
  app: Parameters<typeof runVerificarCodigo>[0], uid: string, codigo: unknown, nowMs = AHORA + 1_000,
) =>
  runVerificarCodigo(app, uid, codigo, { nowMs });

const mails = (store: Store) => Object.values(store.mail_queue ?? {});

beforeEach(() => {
  jest.clearAllMocks();
  for (const k of Object.keys(mockEmails)) delete mockEmails[k];
  mockEmails[ALUMNA] = "alumna@test.com";
  mockEmails[PROFE] = "profe@test.com";
  mockEmails[OTRA] = "otra@test.com";
  mockUpdateUser.mockImplementation(async () => ({}));
});

describe("generarCodigo", () => {
  it("son siempre 6 dígitos, con los ceros adelante", () => {
    for (let i = 0; i < 500; i++) expect(generarCodigo()).toMatch(/^\d{6}$/);
  });
});

describe("pedir el código", () => {
  it("manda el mail del ALUMNO con el código y guarda solo el hash", async () => {
    const { app, store } = fakeApp(MUNDO());

    const r = await pedir(app, ALUMNA, "048213");

    expect(r.estado).toBe("enviado");
    const [mail] = mails(store);
    expect(mails(store)).toHaveLength(1);
    expect(mail.kind).toBe("email-code-athlete");
    expect(mail.toUid).toBe(ALUMNA);
    expect((mail.params as Record<string, unknown>).codigo).toBe("048213");

    const v = store[VERIFICACIONES_COLLECTION][ALUMNA];
    expect(v.codigoHash).toBe(sha(`${ALUMNA}:048213`));
    expect(v.venceMs).toBe(AHORA + CODIGO_VIGENCIA_MS);
    expect(v.intentos).toBe(0);
    // En claro, NUNCA: ni en un campo ni adentro de otro.
    expect(JSON.stringify(v)).not.toContain("048213");
  });

  it("al entrenador le manda el mail del entrenador", async () => {
    const { app, store } = fakeApp(MUNDO());

    await pedir(app, PROFE, "111111");

    expect(mails(store)[0].kind).toBe("email-code-trainer");
  });

  it("si ya está verificado no manda nada", async () => {
    const mundo = MUNDO();
    mundo.users[ALUMNA].mailVerificadoAt = ts(AHORA - 1_000);
    const { app, store } = fakeApp(mundo);

    const r = await pedir(app, ALUMNA, "048213");

    expect(r.estado).toBe("ya-verificado");
    expect(mails(store)).toHaveLength(0);
  });

  it("sin rol todavía no manda: no sabemos qué mail le corresponde", async () => {
    const { app, store } = fakeApp({ users: { [ALUMNA]: {} } });

    const r = await pedir(app, ALUMNA, "048213");

    expect(r.estado).toBe("sin-perfil");
    expect(mails(store)).toHaveLength(0);
  });

  it("«Reenviar» dos veces en menos de 60 s manda UN solo mail", async () => {
    const { app, store } = fakeApp(MUNDO());

    await pedir(app, ALUMNA, "111111");
    const r = await pedir(app, ALUMNA, "222222", AHORA + 30_000, true);

    expect(r).toEqual({ estado: "enfriando", reintentarEnMs: REENVIO_COOLDOWN_MS - 30_000 });
    expect(mails(store)).toHaveLength(1);

    // Pasado el cooldown, sale.
    const r2 = await pedir(app, ALUMNA, "333333", AHORA + REENVIO_COOLDOWN_MS, true);
    expect(r2.estado).toBe("enviado");
    expect(mails(store)).toHaveLength(2);
  });

  it("abrir la pantalla de nuevo NO invalida el código que ya está en la bandeja", async () => {
    // El caso real: el usuario cierra la app para ir a buscar el mail y vuelve.
    // Si la pantalla pidiera otro código al abrirse, el que tiene ya no serviría.
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "111111");

    const r = await pedir(app, ALUMNA, "222222", AHORA + 5 * 60_000);

    expect(r.estado).toBe("vigente");
    expect(mails(store)).toHaveLength(1);
    expect((await verificar(app, ALUMNA, "111111", AHORA + 5 * 60_000 + 1)).estado)
      .toBe("verificado");
  });

  it("con el código vencido, el pedido automático manda uno nuevo", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "111111");

    const r = await pedir(app, ALUMNA, "222222", AHORA + CODIGO_VIGENCIA_MS + 1);

    expect(r.estado).toBe("enviado");
    expect(mails(store)).toHaveLength(2);
  });

  it("con los intentos agotados, el pedido automático manda uno nuevo", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "111111");
    for (let i = 0; i < MAX_INTENTOS; i++) await verificar(app, ALUMNA, "000000");

    const r = await pedir(app, ALUMNA, "222222", AHORA + 2 * 60_000);

    expect(r.estado).toBe("enviado");
    expect(mails(store)).toHaveLength(2);
    expect((await verificar(app, ALUMNA, "222222", AHORA + 2 * 60_000 + 1)).estado)
      .toBe("verificado");
  });

  it("un código nuevo reemplaza al anterior", async () => {
    const { app } = fakeApp(MUNDO());

    await pedir(app, ALUMNA, "111111");
    await pedir(app, ALUMNA, "222222", AHORA + REENVIO_COOLDOWN_MS, true);

    const viejo = await verificar(app, ALUMNA, "111111", AHORA + REENVIO_COOLDOWN_MS + 1);
    expect(viejo.estado).toBe("incorrecto");
    const nuevo = await verificar(app, ALUMNA, "222222", AHORA + REENVIO_COOLDOWN_MS + 2);
    expect(nuevo.estado).toBe("verificado");
  });

  it("si la cola de mails falla: error, y no queda ni el código ni el cooldown", async () => {
    const { app, store, control } = fakeApp(MUNDO());
    control.fallaCola = true;

    await expect(pedir(app, ALUMNA, "048213")).rejects.toMatchObject({ code: "unavailable" });
    expect(store[VERIFICACIONES_COLLECTION]?.[ALUMNA]).toBeUndefined();

    // Puede reintentar en el acto: el mail no salió, no hay nada que enfriar.
    control.fallaCola = false;
    const r = await pedir(app, ALUMNA, "048213", AHORA + 1_000);
    expect(r.estado).toBe("enviado");
  });
});

describe("validar el código", () => {
  it("el correcto marca mailVerificadoAt, borra el código y pone emailVerified", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");

    const r = await verificar(app, ALUMNA, "048213", AHORA + 60_000);

    expect(r).toEqual({ estado: "verificado" });
    const marca = store.users[ALUMNA].mailVerificadoAt as { toMillis: () => number };
    expect(marca.toMillis()).toBe(AHORA + 60_000);
    expect(store[VERIFICACIONES_COLLECTION]?.[ALUMNA]).toBeUndefined();
    expect(mockUpdateUser).toHaveBeenCalledWith(ALUMNA, { emailVerified: true });
  });

  it("acepta el código con espacios alrededor (pegado del mail)", async () => {
    const { app } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");

    expect((await verificar(app, ALUMNA, " 048213 ")).estado).toBe("verificado");
  });

  it("se usa una sola vez: el segundo canje no vuelve a marcar nada", async () => {
    const { app } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");
    await verificar(app, ALUMNA, "048213");

    // Un doble toque no es un error: la pantalla tiene que poder seguir.
    const r = await verificar(app, ALUMNA, "048213", AHORA + 5_000);

    expect(r.estado).toBe("verificado");
    expect(mockUpdateUser).toHaveBeenCalledTimes(1);
  });

  it("descuenta intentos y al quinto bloquea, aunque después ponga el correcto", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");

    for (let restantes = MAX_INTENTOS - 1; restantes >= 1; restantes--) {
      expect(await verificar(app, ALUMNA, "000000")).toEqual({
        estado: "incorrecto",
        intentosRestantes: restantes,
      });
    }
    expect((await verificar(app, ALUMNA, "000000")).estado).toBe("bloqueado");
    expect((await verificar(app, ALUMNA, "048213")).estado).toBe("bloqueado");
    expect(store.users[ALUMNA].mailVerificadoAt).toBeUndefined();
  });

  it("vencido no sirve", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");

    const r = await verificar(app, ALUMNA, "048213", AHORA + CODIGO_VIGENCIA_MS + 1);

    expect(r.estado).toBe("vencido");
    expect(store.users[ALUMNA].mailVerificadoAt).toBeUndefined();
  });

  it("un formato inválido no gasta intentos", async () => {
    const { app } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");

    for (const malo of ["12345", "1234567", "abcdef", "", 48213, null, undefined]) {
      expect((await verificar(app, ALUMNA, malo)).estado).toBe("formato-invalido");
    }
    // Siguen quedando todos: el próximo error descuenta recién el primero.
    expect(await verificar(app, ALUMNA, "000000")).toEqual({
      estado: "incorrecto",
      intentosRestantes: MAX_INTENTOS - 1,
    });
  });

  it("sin haber pedido código", async () => {
    const { app } = fakeApp(MUNDO());

    expect((await verificar(app, ALUMNA, "048213")).estado).toBe("sin-codigo");
  });

  it("el código de una cuenta no sirve en otra", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");
    await pedir(app, OTRA, "999999");

    expect((await verificar(app, OTRA, "048213")).estado).toBe("incorrecto");
    expect(store.users[OTRA].mailVerificadoAt).toBeUndefined();
  });

  it("dos canjes simultáneos del mismo código marcan UNA vez", async () => {
    const { app } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");

    const [a, b] = await Promise.all([
      verificar(app, ALUMNA, "048213"),
      verificar(app, ALUMNA, "048213"),
    ]);

    expect([a.estado, b.estado]).toEqual(["verificado", "verificado"]);
    expect(mockUpdateUser).toHaveBeenCalledTimes(1);
  });

  it("si Auth no deja marcar emailVerified, la verificación vale igual", async () => {
    // Lo que decide el acceso es `mailVerificadoAt`, no `emailVerified`.
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");
    mockUpdateUser.mockImplementation(async () => {
      throw new Error("auth caído");
    });

    const r = await verificar(app, ALUMNA, "048213");

    expect(r.estado).toBe("verificado");
    expect(store.users[ALUMNA].mailVerificadoAt).toBeDefined();
  });
});

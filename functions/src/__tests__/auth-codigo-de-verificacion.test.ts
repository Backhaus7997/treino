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
 *   5. Que la verificación sea POR ROL: a la alumna que pasa a entrenadora se le
 *      vuelve a pedir, y le llega el mail del entrenador.
 *   6. Que una cuenta no saque más de 5 mails por hora ni 10 por día, ni con
 *      pedidos en paralelo.
 *   7. Que el bloque de pagos del mail vaya solo a quien le sirve y lo aceptó.
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
  MAX_ENVIOS_POR_HORA,
  MAX_INTENTOS,
  REENVIO_COOLDOWN_MS,
  VERIFICACIONES_COLLECTION,
  decidirEnvio,
  generarCodigo,
  muestraPlanes,
  runSolicitarCodigo,
  runVerificarCodigo,
} from "../auth/codigo-de-verificacion";
import { ATHLETE_PAYWALL_ENFORCEMENT_ENABLED } from "../subscriptions/athlete-paywall-enforced";
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

/** Lo que `verificarCodigoDeMail` deja en `users/{uid}`. */
type PorRol = Record<string, { email: string; verifiedAt: { toMillis: () => number } }>;
const verificacion = (store: Store, uid: string) =>
  store.users[uid].emailVerification as PorRol | undefined;

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
    mundo.users[ALUMNA].emailVerification = {
      athlete: { email: "alumna@test.com", verifiedAt: ts(AHORA - 1_000) },
    };
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
  it("el correcto marca la entrada de SU rol, borra el código y pone emailVerified", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");

    const r = await verificar(app, ALUMNA, "048213", AHORA + 60_000);

    expect(r).toEqual({ estado: "verificado" });
    const marca = verificacion(store, ALUMNA);
    expect(Object.keys(marca ?? {})).toEqual(["athlete"]);
    expect(marca?.athlete.email).toBe("alumna@test.com");
    expect(marca?.athlete.verifiedAt.toMillis()).toBe(AHORA + 60_000);
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
    expect(verificacion(store, ALUMNA)).toBeUndefined();
  });

  it("vencido no sirve", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");

    const r = await verificar(app, ALUMNA, "048213", AHORA + CODIGO_VIGENCIA_MS + 1);

    expect(r.estado).toBe("vencido");
    expect(verificacion(store, ALUMNA)).toBeUndefined();
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
    expect(verificacion(store, OTRA)).toBeUndefined();
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
    // Lo que decide el acceso es `emailVerification`, no `emailVerified`.
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");
    mockUpdateUser.mockImplementation(async () => {
      throw new Error("auth caído");
    });

    const r = await verificar(app, ALUMNA, "048213");

    expect(r.estado).toBe("verificado");
    expect(verificacion(store, ALUMNA)?.athlete).toBeDefined();
  });
});

describe("por rol: la alumna que el equipo pasa a entrenadora", () => {
  /** Verificada como alumna y ya promovida: así la deja el script de promoción. */
  const PROMOVIDA = (): Store => ({
    users: {
      [ALUMNA]: {
        role: "trainer",
        emailVerification: { athlete: { email: "alumna@test.com", verifiedAt: ts(AHORA - 9_000) } },
      },
    },
  });

  it("vuelve a pedir el código, y le llega el mail del ENTRENADOR", async () => {
    const { app, store } = fakeApp(PROMOVIDA());

    const r = await pedir(app, ALUMNA, "777777");

    expect(r.estado).toBe("enviado");
    expect(mails(store).map((m) => m.kind)).toEqual(["email-code-trainer"]);
  });

  it("al verificar suma la entrada de entrenador sin perder la de alumna", async () => {
    const { app, store } = fakeApp(PROMOVIDA());
    await pedir(app, ALUMNA, "777777");

    expect((await verificar(app, ALUMNA, "777777")).estado).toBe("verificado");

    const marca = verificacion(store, ALUMNA);
    expect(marca?.trainer.email).toBe("alumna@test.com");
    expect(marca?.athlete.verifiedAt.toMillis()).toBe(AHORA - 9_000);
    expect((await pedir(app, ALUMNA, "888888", AHORA + REENVIO_COOLDOWN_MS)).estado)
      .toBe("ya-verificado");
  });

  it("el código que pidió como alumna no le sirve después de la promoción", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");
    store.users[ALUMNA].role = "trainer";

    // Ni para verificar —marcaría al entrenador con el mail del alumno—...
    expect((await verificar(app, ALUMNA, "048213")).estado).toBe("sin-codigo");
    expect(verificacion(store, ALUMNA)).toBeUndefined();

    // ...ni como «vigente»: el pedido automático manda el del entrenador.
    const r = await pedir(app, ALUMNA, "777777", AHORA + REENVIO_COOLDOWN_MS);
    expect(r.estado).toBe("enviado");
    expect(mails(store).map((m) => m.kind)).toEqual(["email-code-athlete", "email-code-trainer"]);
  });

  it("promovida a los segundos de pedir el de alumna: el del entrenador sale sin esperar", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");
    store.users[ALUMNA].role = "trainer";

    expect((await pedir(app, ALUMNA, "777777", AHORA + 1_000)).estado).toBe("enviado");
    expect(mails(store).map((m) => m.kind)).toEqual(["email-code-athlete", "email-code-trainer"]);
  });

  it("si el equipo le cambia el mail en Auth, el nuevo se verifica de nuevo", async () => {
    const mundo = MUNDO();
    mundo.users[ALUMNA].emailVerification = {
      athlete: { email: "vieja@test.com", verifiedAt: ts(AHORA - 9_000) },
    };
    const { app } = fakeApp(mundo);

    expect((await pedir(app, ALUMNA, "777777")).estado).toBe("enviado");

    // Mayúsculas o espacios no lo hacen otro mail.
    mockEmails[ALUMNA] = "  VIEJA@test.com ";
    expect((await pedir(app, ALUMNA, "888888", AHORA + REENVIO_COOLDOWN_MS)).estado)
      .toBe("ya-verificado");
  });

  it("el código mandado al mail anterior no verifica el nuevo", async () => {
    const { app, store } = fakeApp(MUNDO());
    await pedir(app, ALUMNA, "048213");
    mockEmails[ALUMNA] = "nueva@test.com";

    expect((await verificar(app, ALUMNA, "048213")).estado).toBe("sin-codigo");
    expect(verificacion(store, ALUMNA)).toBeUndefined();
  });
});

describe("decidirEnvio: cooldown y topes", () => {
  const MIN = 60_000;
  const H = 60 * MIN;
  const D = 24 * H;
  const P = { rol: "athlete" as const, email: "a@test.com", nowMs: AHORA, reenviar: true };
  /** Ya mandó `hora` en la hora y `dia` en el día; el último, hace 2 min. */
  const doc = (hora: number, dia: number, horaDesde = AHORA - 30 * MIN, diaDesde = AHORA - 5 * H) => ({
    rol: "athlete",
    email: "a@test.com",
    enviadoMs: AHORA - 2 * MIN,
    horaDesdeMs: horaDesde,
    enviosEnLaHora: hora,
    diaDesdeMs: diaDesde,
    enviosEnElDia: dia,
  });

  it("el primer envío abre las dos ventanas", () => {
    expect(decidirEnvio(undefined, P)).toEqual({
      estado: "enviar",
      ventanas: { horaDesdeMs: AHORA, enviosEnLaHora: 1, diaDesdeMs: AHORA, enviosEnElDia: 1 },
    });
  });

  it("el 5.º de la hora sale; el 6.º espera a que cierre la ventana", () => {
    expect(decidirEnvio(doc(4, 4), P)).toMatchObject({ estado: "enviar", ventanas: { enviosEnLaHora: 5 } });
    expect(decidirEnvio(doc(5, 5), P)).toEqual({ estado: "limitado", reintentarEnMs: 30 * MIN });
  });

  it("cerrada la ventana de la hora arranca otra, y el día sigue contando", () => {
    expect(decidirEnvio(doc(5, 5, AHORA - H), P)).toMatchObject({
      estado: "enviar",
      ventanas: { horaDesdeMs: AHORA, enviosEnLaHora: 1, enviosEnElDia: 6 },
    });
  });

  it("el 10.º del día sale; el 11.º espera a que cierre el día", () => {
    expect(decidirEnvio(doc(0, 9, AHORA - H), P)).toMatchObject({ estado: "enviar", ventanas: { enviosEnElDia: 10 } });
    expect(decidirEnvio(doc(0, 10, AHORA - H), P)).toEqual({ estado: "limitado", reintentarEnMs: D - 5 * H });
  });

  it("con las dos ventanas llenas espera la que cierra más tarde", () => {
    expect(decidirEnvio(doc(5, 10), P)).toEqual({ estado: "limitado", reintentarEnMs: D - 5 * H });
  });

  it("cerrado el día arranca otro", () => {
    expect(decidirEnvio(doc(0, 10, AHORA - H, AHORA - D), P)).toMatchObject({
      estado: "enviar",
      ventanas: { diaDesdeMs: AHORA, enviosEnElDia: 1 },
    });
  });

  it("el cooldown contesta antes que los topes: es la espera más corta", () => {
    const reciente = { ...doc(5, 5), enviadoMs: AHORA - 10_000 };
    expect(decidirEnvio(reciente, P)).toEqual({ estado: "enfriando", reintentarEnMs: 50_000 });
  });

  it("el recién promovido se saltea el cooldown, pero no los topes", () => {
    const reciente = { ...doc(5, 5), enviadoMs: AHORA - 10_000 };
    expect(decidirEnvio(reciente, { ...P, rol: "trainer" })).toMatchObject({ estado: "limitado" });
  });
});

describe("muestraPlanes: el bloque de pagos del mail", () => {
  const apagado = { notificationPrefs: { novedades_plan: { email: false } } };

  it.each([
    ["PF", "trainer", {}, false, true],
    // La oposición se mira al ENVIAR (`bloqueComercial`), no acá.
    ["PF que apagó novedades_plan: se decide al enviar", "trainer", apagado, true, true],
    ["alumno, con el interruptor apagado", "athlete", {}, false, false],
    ["alumno recién creado (sin el campo)", "athlete", {}, true, true],
    ["alumno al que el free le aplica", "athlete", { athletePaywallEnforced: true }, true, true],
    ["alumno que ya paga o tiene PF activo", "athlete", { athletePaywallEnforced: false }, true, false],
    ["alumno que apagó novedades_plan: se decide al enviar", "athlete", apagado, true, true],
  ] as const)("%s", (_, rol, usuario, prendido, esperado) => {
    expect(muestraPlanes(rol, usuario, prendido)).toBe(esperado);
  });
});

describe("de punta a punta", () => {
  it("dos «Reenviar» simultáneos mandan UN mail", async () => {
    const { app, store } = fakeApp(MUNDO());

    const rs = await Promise.all([
      pedir(app, ALUMNA, "111111", AHORA, true),
      pedir(app, ALUMNA, "222222", AHORA, true),
    ]);

    expect(rs.map((r) => r.estado).sort()).toEqual(["enfriando", "enviado"]);
    expect(mails(store)).toHaveLength(1);
  });

  it("pasado el tope de la hora, «Reenviar» contesta limitado y no manda", async () => {
    const { app, store } = fakeApp(MUNDO());
    for (let i = 0; i < MAX_ENVIOS_POR_HORA; i++) {
      expect((await pedir(app, ALUMNA, "111111", AHORA + i * REENVIO_COOLDOWN_MS, true)).estado)
        .toBe("enviado");
    }

    const r = await pedir(app, ALUMNA, "111111", AHORA + MAX_ENVIOS_POR_HORA * REENVIO_COOLDOWN_MS, true);

    expect(r).toEqual({ estado: "limitado", reintentarEnMs: 60 * 60_000 - MAX_ENVIOS_POR_HORA * REENVIO_COOLDOWN_MS });
    expect(mails(store)).toHaveLength(MAX_ENVIOS_POR_HORA);
  });

  it("con el bloque, el mail sale con bloqueComercial: la oposición la mira el envío", async () => {
    // El PF que se opuso igual sale con el bloque y `bloqueComercial`: es
    // `sendQueuedMail` el que lo saca al enviar (y si no se opuso, agrega el
    // pie de baja). Decidirlo acá dejaría el mail comercial sin pie.
    const mundo = MUNDO();
    mundo.users[OTRA] = { role: "trainer", notificationPrefs: { novedades_plan: { email: false } } };
    const { app, store } = fakeApp(mundo);

    await pedir(app, PROFE, "111111");
    await pedir(app, OTRA, "222222");

    for (const m of mails(store)) {
      expect((m.params as Record<string, unknown>).showPlans).toBe("1");
      expect(m.bloqueComercial).toBe("novedades_plan");
      expect(m.prefKey).toBeUndefined();
    }
  });

  it("sin el bloque no hay nada comercial: el mail sale sin bloqueComercial", async () => {
    // El alumno recién creado depende del interruptor del paywall.
    const { app, store } = fakeApp(MUNDO());

    await pedir(app, ALUMNA, "111111");

    const [m] = mails(store);
    const conPlanes = ATHLETE_PAYWALL_ENFORCEMENT_ENABLED;
    expect((m.params as Record<string, unknown>).showPlans).toBe(conPlanes ? "1" : "0");
    expect(m.bloqueComercial).toBe(conPlanes ? "novedades_plan" : undefined);
  });
});

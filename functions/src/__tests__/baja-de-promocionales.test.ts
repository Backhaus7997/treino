/**
 * baja-de-promocionales.test.ts — el link de baja de los correos comerciales.
 *
 * Dos mitades, con dos infraestructuras:
 *   - el TOKEN es puro (HMAC en memoria): ida y vuelta, y todo lo que tiene que
 *     rechazar;
 *   - la CALLABLE escribe de verdad en `users/{uid}`, así que corre contra el
 *     emulador de Firestore. Con `emulators:exec` el host llega por entorno; el
 *     `??=` respeta ese puerto, y sólo cae al 8080 cuando se corre a mano.
 *
 * Lo que protege, en orden de qué tan caro sale:
 *
 *   1. Que una firma ajena —alterada, de otro uid, de otra versión, de otra
 *      clave, o de una preferencia fuera de la allowlist— NUNCA escriba.
 *   2. Que el uid salga del token y que la baja NO cree el documento de una
 *      cuenta borrada (`update`, no `set`).
 *   3. Que un input gigante se corte ANTES de calcular el HMAC.
 *   4. Que el token no aparezca en ningún log.
 */

import { createHmac } from "crypto";

// Un wrapper que delega en el real, para poder CONTAR las llamadas. Se mockea el
// módulo y no se espía con `jest.spyOn`: con `esModuleInterop`, `import * as`
// entrega una copia y espiar la copia no toca lo que ve el módulo bajo prueba.
jest.mock("crypto", () => {
  const actual = jest.requireActual("crypto");
  return { ...actual, createHmac: jest.fn(actual.createHmac) };
});

// El logger real escribe a stdout; se reemplaza para poder leer qué se logueó.
jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { DocumentReference, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import {
  BajaDeCorreosResult,
  bajaDeCorreosPromocionales,
  firmarToken,
  prefTieneBaja,
  runBajaDeCorreosPromocionales,
  urlDeBaja,
  verificarToken,
} from "../mail/baja-de-promocionales";
import { ATHLETE_PROSPECT_PREF_KEY } from "../subscriptions/athlete-prospect-mail";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ??= "treino-dev";

const KEY = "clave-de-prueba-de-baja";
const OTRA_KEY = "otra-clave-de-prueba";
const PREF = ATHLETE_PROSPECT_PREF_KEY;
const hmacMock = createHmac as unknown as jest.Mock;

/** base64url, escrito a mano para no depender del código que se prueba. */
const b64 = (s: string) => Buffer.from(s, "utf8").toString("base64url");

/**
 * El esquema de §5 del diseño, reimplementado ACÁ y sin importar nada del
 * módulo: si `firmarToken` se desvía de la gramática, este espejo no.
 */
function tokenSegunElDiseno(prefKey: string, uid: string, key: string): string {
  const p = b64(prefKey);
  const u = b64(uid);
  const sig = createHmac("sha256", key)
    .update(`baja-promocionales/v1/${p}/${u}`)
    .digest("base64url");
  return `v1.${p}.${u}.${sig}`;
}

// ---------------------------------------------------------------------------
// El token
// ---------------------------------------------------------------------------
describe("token de baja: firmar y verificar", () => {
  it("ida y vuelta: devuelve el uid y la preferencia que se firmaron", () => {
    const token = firmarToken("uid-123", PREF, KEY);

    expect(verificarToken(token, KEY)).toEqual({ uid: "uid-123", prefKey: PREF });
  });

  it("la gramática es la del diseño, byte a byte", () => {
    // Un espejo independiente, y un vector FIJO: si cambia el formato, los links
    // ya enviados dejan de servir, y eso no puede pasar sin que un test lo grite.
    expect(firmarToken("uid-123", PREF, KEY)).toBe(tokenSegunElDiseno(PREF, "uid-123", KEY));
    expect(firmarToken("uid-123", PREF, KEY)).toBe(
      "v1.bm92ZWRhZGVzX3BsYW4.dWlkLTEyMw.TFz6oQGVUn0NjO-94kYeO3wnGQn47Pn9PjuF8nDaZS0",
    );
  });

  it("cumple la regex cerrada y el largo máximo", () => {
    const token = firmarToken("uid-123", PREF, KEY);

    expect(token).toMatch(
      /^v1\.[A-Za-z0-9_-]{1,64}\.[A-Za-z0-9_-]{1,200}\.[A-Za-z0-9_-]{43}$/,
    );
    expect(token.length).toBeLessThanOrEqual(320);
  });

  it("un uid con puntos hace la ida y vuelta (por eso va en base64url)", () => {
    // Un uid de Auth importado puede traer puntos. Sin codificar, el token
    // `v1.<p>.<uid>.<sig>` tendría más de cuatro segmentos y sería ambiguo.
    const uid = "tenant.user.01";
    const token = firmarToken(uid, PREF, KEY);

    expect(token.split(".")).toHaveLength(4);
    expect(token).toBe(
      "v1.bm92ZWRhZGVzX3BsYW4.dGVuYW50LnVzZXIuMDE.HKaobpXR01bUWPum5AQb4w4u1b1whFK95J0EDu5e0ug",
    );
    expect(verificarToken(token, KEY)).toEqual({ uid, prefKey: PREF });
  });

  it("un uid del largo máximo de Auth (128) entra en la gramática", () => {
    const uid = "u".repeat(128);

    expect(verificarToken(firmarToken(uid, PREF, KEY), KEY)?.uid).toBe(uid);
  });

  it("un uid con caracteres no ASCII hace la ida y vuelta", () => {
    const uid = "usuaria-ñandú-éxito";

    expect(verificarToken(firmarToken(uid, PREF, KEY), KEY)?.uid).toBe(uid);
  });

  describe("lo que tiene que rechazar", () => {
    const token = firmarToken("uid-123", PREF, KEY);
    const [v, p, u, sig] = token.split(".");

    it("una firma alterada", () => {
      // Cambia el PRIMER carácter de la firma: así no depende de los bits
      // sobrantes del último, que es otro caso (el siguiente).
      const alterada = `${v}.${p}.${u}.${sig[0] === "A" ? "B" : "A"}${sig.slice(1)}`;

      expect(verificarToken(alterada, KEY)).toBeNull();
    });

    it("la forma no canónica de una firma válida", () => {
      // El último carácter de 43 lleva 4 bits de relleno: decodificados, hasta
      // 4 strings distintos dan los mismos 32 bytes. Sólo la canónica verifica.
      const ultimo = sig[sig.length - 1];
      const alfabeto = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
      const variante = alfabeto
        .split("")
        .find((c) => c !== ultimo && Buffer.from(sig.slice(0, -1) + c, "base64url")
          .equals(Buffer.from(sig, "base64url")));

      expect(variante).toBeDefined();
      expect(verificarToken(`${v}.${p}.${u}.${sig.slice(0, -1)}${variante}`, KEY))
        .toBeNull();
    });

    it("un uid cambiado con la firma de otro", () => {
      // Es el ataque que importa: tomar el link propio y apuntarlo a otra cuenta.
      const deOtro = `${v}.${p}.${b64("uid-de-la-victima")}.${sig}`;

      expect(verificarToken(deOtro, KEY)).toBeNull();
    });

    it("una preferencia cambiada con la firma de otra", () => {
      expect(verificarToken(`${v}.${b64("otra_pref")}.${u}.${sig}`, KEY)).toBeNull();
    });

    it("una preferencia fuera de la allowlist, aunque la firma sea VÁLIDA", () => {
      // Firmado con la clave de verdad: la firma es perfecta y aun así no sirve.
      // La callable no escribe un campo que no esté en la lista.
      const fuera = firmarToken("uid-123", "nueva_solicitud", KEY);

      expect(fuera).toBe(tokenSegunElDiseno("nueva_solicitud", "uid-123", KEY));
      expect(verificarToken(fuera, KEY)).toBeNull();
    });

    it("otra versión", () => {
      expect(verificarToken(`v2.${p}.${u}.${sig}`, KEY)).toBeNull();
      expect(verificarToken(`V1.${p}.${u}.${sig}`, KEY)).toBeNull();
    });

    it.each([
      ["con barras (`a/b/c`)", "a/b/c"],
      ["con una barra al principio", "/a"],
      ["que es sólo una barra", "/"],
      ["que es `.`", "."],
      ["que es `..`", ".."],
      ["reservado por Firestore", "__reservado__"],
    ])("un uid %s, aunque la firma sea VÁLIDA", (_nombre, uid) => {
      // Firmado a mano con la clave de verdad: la firma es perfecta. Auth acepta
      // estos uids (sólo valida 1-128 caracteres) y Firestore leería `a/b/c`
      // como la ruta `users/a/b/c`: otro documento, en otra colección.
      const hecho = tokenSegunElDiseno(PREF, uid, KEY);

      expect(hecho).toMatch(/^v1\./);
      expect(verificarToken(hecho, KEY)).toBeNull();
      // Y tampoco se emite: no hay por qué firmar un link que se va a rechazar.
      expect(() => firmarToken(uid, PREF, KEY)).toThrow();
    });

    it("una firma hecha con otra clave", () => {
      expect(verificarToken(firmarToken("uid-123", PREF, OTRA_KEY), KEY)).toBeNull();
    });

    it("la clave vacía, aunque el token se haya firmado con la vacía", () => {
      // Node acepta un HMAC con clave vacía, y cualquiera podría forjarlo. Sin
      // clave, falla cerrado: no hay contra qué verificar.
      const conVacia = tokenSegunElDiseno(PREF, "uid-123", "");

      expect(verificarToken(conVacia, "")).toBeNull();
      expect(() => firmarToken("uid-123", PREF, "")).toThrow();
    });

    it.each([
      ["vacío", ""],
      ["una palabra", "hola"],
      ["cuatro segmentos vacíos", "..."],
      ["sin versión", `${p}.${u}.${sig}`],
      ["con un segmento de más", `${token}.x`],
      ["con un segmento de menos", `${v}.${p}.${u}`],
      ["con espacios", ` ${token} `],
      ["con salto de línea", `${token}\n`],
      ["con caracteres fuera de base64url", `${v}.${p}.${u}.${sig.slice(0, -1)}+`],
      ["la firma corta", `${v}.${p}.${u}.${sig.slice(0, 42)}`],
      ["la firma larga", `${v}.${p}.${u}.${sig}A`],
      ["un segmento de uid vacío", `${v}.${p}..${sig}`],
    ])("basura: %s", (_nombre, entrada) => {
      expect(verificarToken(entrada, KEY)).toBeNull();
    });

    it.each([
      ["undefined", undefined],
      ["null", null],
      ["un número", 42],
      ["un objeto", { token }],
      ["un array", [token]],
      ["un booleano", true],
    ])("un valor que no es string: %s", (_nombre, entrada) => {
      expect(verificarToken(entrada, KEY)).toBeNull();
    });
  });

  describe("la forma se chequea ANTES de calcular el HMAC", () => {
    beforeEach(() => hmacMock.mockClear());

    it("un token de 10 KB se rechaza sin tocar el HMAC", () => {
      // Con los caracteres BUENOS, para que no lo corte nada que no sea el largo.
      const enorme = `v1.${"A".repeat(5000)}.${"B".repeat(5000)}.${"C".repeat(43)}`;

      expect(enorme.length).toBeGreaterThan(10_000);
      expect(verificarToken(enorme, KEY)).toBeNull();
      expect(hmacMock).not.toHaveBeenCalled();
    });

    it("un segmento fuera de los topes de la regex tampoco llega al HMAC", () => {
      const prefLarga = `v1.${"A".repeat(65)}.${b64("uid")}.${"C".repeat(43)}`;
      const uidLargo = `v1.${b64(PREF)}.${"B".repeat(201)}.${"C".repeat(43)}`;

      expect(verificarToken(prefLarga, KEY)).toBeNull();
      expect(verificarToken(uidLargo, KEY)).toBeNull();
      expect(hmacMock).not.toHaveBeenCalled();
    });

    it("basura con la forma equivocada tampoco", () => {
      verificarToken("hola", KEY);
      verificarToken(undefined, KEY);

      expect(hmacMock).not.toHaveBeenCalled();
    });

    it("CONTROL: un token con la forma buena SÍ calcula el HMAC", () => {
      // Sin esto, los tres tests de arriba pasarían igual si el mock no
      // contara nada (por ejemplo, si el módulo usara otra referencia a crypto).
      verificarToken(firmarToken("uid-123", PREF, KEY), KEY);

      expect(hmacMock).toHaveBeenCalled();
    });
  });
});

describe("firmarToken: no emite un link muerto", () => {
  it("un uid que no entra en la gramática tira en vez de firmar", () => {
    // 150 bytes → 200 caracteres en base64url es el tope; 151 ya no entra.
    expect(() => firmarToken("u".repeat(151), PREF, KEY)).toThrow();
    expect(() => firmarToken("", PREF, KEY)).toThrow();
  });
});

describe("urlDeBaja", () => {
  it("apunta a la landing y lleva el token en el FRAGMENTO", () => {
    const url = urlDeBaja("uid-123", PREF, KEY);

    // El fragmento no viaja en el request HTTP: no queda en logs ni en Referer.
    expect(url.startsWith("https://gettreino.com/es/correos-promocionales/baja#t=")).toBe(true);
    expect(url).not.toContain("?");
  });

  it("el token del link verifica", () => {
    const url = urlDeBaja("uid-123", PREF, KEY);
    const token = url.split("#t=")[1];

    expect(verificarToken(token, KEY)).toEqual({ uid: "uid-123", prefKey: PREF });
  });
});

describe("allowlist de preferencias con baja", () => {
  it("es sólo `novedades_plan`, derivada de la constante de los productores", () => {
    expect(prefTieneBaja(PREF)).toBe(true);
    expect(prefTieneBaja("novedades_plan")).toBe(true);
  });

  it.each(["nueva_solicitud", "pago_recibido", "sesion_cancelada", "", "__proto__"])(
    "%s no tiene baja por link",
    (clave) => {
      expect(prefTieneBaja(clave)).toBe(false);
    },
  );

  // Cada fila va envuelta: `it.each` DESPLIEGA un array como argumentos, y la
  // fila `["novedades_plan"]` llamaría a la función con el string de adentro.
  it.each([[undefined], [null], [1], [{}], [["novedades_plan"]]])(
    "un valor que no es string (%p) no tiene baja",
    (valor) => {
      expect(prefTieneBaja(valor)).toBe(false);
    },
  );
});

// ---------------------------------------------------------------------------
// La callable (emulador de Firestore)
// ---------------------------------------------------------------------------
describe("runBajaDeCorreosPromocionales", () => {
  let app: App;
  const uids: string[] = [];

  /** Un uid propio de esta suite, para no pisar a otras corriendo en el mismo emulador. */
  const nuevoUid = (sufijo: string): string => {
    const uid = `baja-promo-${sufijo}-${Date.now()}-${uids.length}`;
    uids.push(uid);
    return uid;
  };
  const users = () => getFirestore(app).collection("users");
  const prefsDe = async (uid: string) => (await users().doc(uid).get()).data();

  beforeAll(() => {
    app = initializeApp({ projectId: "treino-dev" }, "baja-promocionales-test");
  });

  afterAll(async () => {
    await deleteApp(app);
  });

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(async () => {
    jest.restoreAllMocks();
    await Promise.all(uids.splice(0).map((uid) => users().doc(uid).delete()));
  });

  it("apaga el canal de mail de `novedades_plan` y contesta `listo`", async () => {
    const uid = nuevoUid("apaga");
    await users().doc(uid).set({ displayName: "Marta" });

    const out = await runBajaDeCorreosPromocionales(
      app,
      { token: firmarToken(uid, PREF, KEY) },
      KEY,
    );

    expect(out).toEqual({ status: "listo" });
    expect((await prefsDe(uid))?.notificationPrefs).toEqual({
      novedades_plan: { email: false },
    });
  });

  it("NO pisa las demás claves de `notificationPrefs` ni los otros campos", async () => {
    const uid = nuevoUid("no-pisa");
    await users().doc(uid).set({
      displayName: "Marta",
      notificationPrefs: {
        nueva_solicitud: { email: true, push: false },
        // El push de la MISMA preferencia tampoco se toca: la baja es del mail.
        novedades_plan: { push: true, email: true },
      },
    });

    await runBajaDeCorreosPromocionales(app, { token: firmarToken(uid, PREF, KEY) }, KEY);

    const data = await prefsDe(uid);
    expect(data?.notificationPrefs).toEqual({
      nueva_solicitud: { email: true, push: false },
      novedades_plan: { push: true, email: false },
    });
    expect(data?.displayName).toBe("Marta");
  });

  it("es idempotente: darse de baja dos veces es lo mismo que una", async () => {
    const uid = nuevoUid("idempotente");
    await users().doc(uid).set({ displayName: "Marta" });
    const input = { token: firmarToken(uid, PREF, KEY) };

    const primera = await runBajaDeCorreosPromocionales(app, input, KEY);
    const segunda = await runBajaDeCorreosPromocionales(app, input, KEY);

    expect(primera).toEqual({ status: "listo" });
    expect(segunda).toEqual({ status: "listo" });
    expect((await prefsDe(uid))?.notificationPrefs).toEqual({
      novedades_plan: { email: false },
    });
  });

  it("un uid con puntos escribe en SU documento", async () => {
    // Si el uid se interpretara como una ruta, apuntaría a otro lado.
    const uid = nuevoUid("con.puntos.01");
    await users().doc(uid).set({ displayName: "Marta" });

    const out = await runBajaDeCorreosPromocionales(
      app,
      { token: firmarToken(uid, PREF, KEY) },
      KEY,
    );

    expect(out.status).toBe("listo");
    expect((await prefsDe(uid))?.notificationPrefs).toEqual({
      novedades_plan: { email: false },
    });
  });

  describe("el replay de un token válido NO escribe", () => {
    // Un token válido no vence, así que uno filtrado se puede repetir sin fin. Si
    // cada llamada escribiera, cada una dispararía los triggers de `users`; el
    // costo del replay tiene que ser una LECTURA.
    const updateTimeDe = async (uid: string) => (await users().doc(uid).get()).updateTime;

    it("la segunda llamada con el MISMO token no escribe", async () => {
      const uid = nuevoUid("replay");
      await users().doc(uid).set({ displayName: "Marta" });
      const input = { token: firmarToken(uid, PREF, KEY) };
      const update = jest.spyOn(DocumentReference.prototype, "update");

      const primera = await runBajaDeCorreosPromocionales(app, input, KEY);
      const trasLaPrimera = await updateTimeDe(uid);
      const segunda = await runBajaDeCorreosPromocionales(app, input, KEY);
      const tercera = await runBajaDeCorreosPromocionales(app, input, KEY);

      expect([primera, segunda, tercera]).toEqual(Array(3).fill({ status: "listo" }));
      // UNA escritura en total, la primera.
      expect(update).toHaveBeenCalledTimes(1);
      expect((await updateTimeDe(uid))?.isEqual(trasLaPrimera!)).toBe(true);
      expect((await prefsDe(uid))?.notificationPrefs).toEqual({
        novedades_plan: { email: false },
      });
    });

    it("una preferencia que YA estaba apagada no se escribe ni una vez", async () => {
      const uid = nuevoUid("ya-apagada");
      await users().doc(uid).set({
        notificationPrefs: { novedades_plan: { email: false, push: true } },
      });
      const antes = await updateTimeDe(uid);
      const update = jest.spyOn(DocumentReference.prototype, "update");

      const out = await runBajaDeCorreosPromocionales(
        app,
        { token: firmarToken(uid, PREF, KEY) },
        KEY,
      );

      expect(out).toEqual({ status: "listo" });
      expect(update).not.toHaveBeenCalled();
      expect((await updateTimeDe(uid))?.isEqual(antes!)).toBe(true);
    });

    it("si `email` NO es `false` (ausente o `true`) sí escribe", async () => {
      // El cortocircuito es sólo para `=== false`: cualquier otra cosa se apaga.
      const ausente = nuevoUid("sin-email");
      const prendida = nuevoUid("email-true");
      await users().doc(ausente).set({ notificationPrefs: { novedades_plan: { push: true } } });
      await users().doc(prendida).set({ notificationPrefs: { novedades_plan: { email: true } } });
      const update = jest.spyOn(DocumentReference.prototype, "update");

      for (const uid of [ausente, prendida]) {
        await runBajaDeCorreosPromocionales(app, { token: firmarToken(uid, PREF, KEY) }, KEY);
      }

      expect(update).toHaveBeenCalledTimes(2);
      expect((await prefsDe(ausente))?.notificationPrefs?.novedades_plan).toEqual({
        push: true,
        email: false,
      });
      expect((await prefsDe(prendida))?.notificationPrefs?.novedades_plan).toEqual({
        email: false,
      });
    });

    it("una cuenta inexistente tampoco escribe", async () => {
      const uid = nuevoUid("replay-inexistente");
      const update = jest.spyOn(DocumentReference.prototype, "update");

      await runBajaDeCorreosPromocionales(app, { token: firmarToken(uid, PREF, KEY) }, KEY);

      expect(update).not.toHaveBeenCalled();
      expect((await users().doc(uid).get()).exists).toBe(false);
    });

    it("si la cuenta se borra ENTRE la lectura y la escritura contesta `listo`", async () => {
      const uid = nuevoUid("carrera");
      await users().doc(uid).set({ displayName: "Marta" });
      jest
        .spyOn(DocumentReference.prototype, "update")
        .mockRejectedValueOnce(Object.assign(new Error("not found"), { code: 5 }));

      const out = await runBajaDeCorreosPromocionales(
        app,
        { token: firmarToken(uid, PREF, KEY) },
        KEY,
      );

      expect(out).toEqual({ status: "listo" });
    });

    it("una falla al LEER tampoco contesta `listo`: tira", async () => {
      const uid = nuevoUid("falla-lectura");
      jest
        .spyOn(DocumentReference.prototype, "get")
        .mockRejectedValueOnce(Object.assign(new Error("unavailable"), { code: 14 }));

      await expect(
        runBajaDeCorreosPromocionales(app, { token: firmarToken(uid, PREF, KEY) }, KEY),
      ).rejects.toThrow("unavailable");
    });
  });

  it("un usuario inexistente contesta `listo` y NO crea el documento", async () => {
    // El caso que justifica `update` en vez de `set`: con `set` + merge, esto
    // dejaría `users/{uid}` creado, a medias, para una cuenta que ya no existe.
    const uid = nuevoUid("inexistente");

    const out = await runBajaDeCorreosPromocionales(
      app,
      { token: firmarToken(uid, PREF, KEY) },
      KEY,
    );

    expect(out).toEqual({ status: "listo" });
    expect((await users().doc(uid).get()).exists).toBe(false);
  });

  it("el `listo` de una cuenta viva y el de una borrada son indistinguibles", async () => {
    // Anti-enumeración: la respuesta no cuenta si la cuenta existe.
    const viva = nuevoUid("viva");
    const borrada = nuevoUid("borrada");
    await users().doc(viva).set({ displayName: "Marta" });

    const deLaViva = await runBajaDeCorreosPromocionales(
      app,
      { token: firmarToken(viva, PREF, KEY) },
      KEY,
    );
    const deLaBorrada = await runBajaDeCorreosPromocionales(
      app,
      { token: firmarToken(borrada, PREF, KEY) },
      KEY,
    );

    expect(deLaBorrada).toEqual(deLaViva);
  });

  describe("contesta `invalido` y NO escribe", () => {
    const invalido: BajaDeCorreosResult = { status: "invalido" };

    it("con una firma alterada", async () => {
      const uid = nuevoUid("alterada");
      await users().doc(uid).set({ displayName: "Marta" });
      const token = firmarToken(uid, PREF, KEY);
      const alterada = `${token.slice(0, -1)}${token.endsWith("A") ? "B" : "A"}`;

      expect(await runBajaDeCorreosPromocionales(app, { token: alterada }, KEY))
        .toEqual(invalido);
      expect((await prefsDe(uid))?.notificationPrefs).toBeUndefined();
    });

    it("con una preferencia fuera de la allowlist y la firma VÁLIDA", async () => {
      const uid = nuevoUid("ajena");
      await users().doc(uid).set({
        notificationPrefs: { nueva_solicitud: { email: true } },
      });

      const out = await runBajaDeCorreosPromocionales(
        app,
        { token: firmarToken(uid, "nueva_solicitud", KEY) },
        KEY,
      );

      expect(out).toEqual(invalido);
      // La callable no escribió un campo que no está en la lista.
      expect((await prefsDe(uid))?.notificationPrefs).toEqual({
        nueva_solicitud: { email: true },
      });
    });

    it("con el token de OTRA cuenta apuntado a ésta", async () => {
      const mia = nuevoUid("mia");
      const victima = nuevoUid("victima");
      await users().doc(victima).set({ displayName: "Víctima" });
      const [v, p, , sig] = firmarToken(mia, PREF, KEY).split(".");

      const out = await runBajaDeCorreosPromocionales(
        app,
        { token: `${v}.${p}.${b64(victima)}.${sig}` },
        KEY,
      );

      expect(out).toEqual(invalido);
      expect((await prefsDe(victima))?.notificationPrefs).toBeUndefined();
    });

    it("con la clave vacía en el servidor", async () => {
      const uid = nuevoUid("sin-clave");
      await users().doc(uid).set({ displayName: "Marta" });

      const out = await runBajaDeCorreosPromocionales(
        app,
        { token: firmarToken(uid, PREF, KEY) },
        "",
      );

      expect(out).toEqual(invalido);
      expect((await prefsDe(uid))?.notificationPrefs).toBeUndefined();
    });

    it.each([
      ["un string", "hola"],
      ["un número", 42],
      ["null", null],
      ["undefined", undefined],
      ["un array", ["x"]],
      ["un objeto sin token", {}],
      ["un token que no es string", { token: 42 }],
      ["un token de 10 KB", { token: "A".repeat(10_240) }],
    ])("con un input que no es lo esperado: %s", async (_nombre, entrada) => {
      // Y NO tira: cualquier otra forma contesta lo mismo, así no hay una rama
      // que el día de mañana alguien haga tirar distinto.
      await expect(runBajaDeCorreosPromocionales(app, entrada, KEY)).resolves.toEqual(invalido);
    });

    it("con un campo extra `uid` en el request: se ignora, el uid sale del token", async () => {
      const mia = nuevoUid("extra-mia");
      const victima = nuevoUid("extra-victima");
      await users().doc(mia).set({ displayName: "Marta" });
      await users().doc(victima).set({ displayName: "Víctima" });

      await runBajaDeCorreosPromocionales(
        app,
        { token: firmarToken(mia, PREF, KEY), uid: victima },
        KEY,
      );

      expect((await prefsDe(mia))?.notificationPrefs).toEqual({
        novedades_plan: { email: false },
      });
      expect((await prefsDe(victima))?.notificationPrefs).toBeUndefined();
    });
  });

  it("un uid con barras NO escribe en la ruta que forma: contesta `invalido`", async () => {
    // El ataque: Auth acepta `<uid>/b/c`, y `doc("<uid>/b/c")` apunta a
    // `users/<uid>/b/c`. Con la firma de un uid así, la callable escribiría ahí.
    const base = nuevoUid("barras");
    const uid = `${base}/b/c`;
    const ajeno = users().doc(base).collection("b").doc("c");
    await ajeno.set({ displayName: "No me toques" });

    try {
      const out = await runBajaDeCorreosPromocionales(
        app,
        { token: tokenSegunElDiseno(PREF, uid, KEY) },
        KEY,
      );

      expect(out).toEqual({ status: "invalido" });
      expect((await ajeno.get()).data()).toEqual({ displayName: "No me toques" });
    } finally {
      await ajeno.delete();
    }
  });

  it("una falla REAL de Firestore NO contesta `listo`: tira", async () => {
    // Decir `listo` sin haber escrito es prometer algo falso. La página tiene un
    // mensaje para «probá de nuevo con este mismo link»; necesita el error.
    const uid = nuevoUid("falla");
    await users().doc(uid).set({ displayName: "Marta" });
    jest
      .spyOn(DocumentReference.prototype, "update")
      .mockRejectedValueOnce(Object.assign(new Error("unavailable"), { code: 14 }));

    await expect(
      runBajaDeCorreosPromocionales(app, { token: firmarToken(uid, PREF, KEY) }, KEY),
    ).rejects.toThrow("unavailable");
    expect((await prefsDe(uid))?.notificationPrefs).toBeUndefined();
  });

  describe("logs", () => {
    /** Todo lo que se mandó a cualquier nivel del logger, aplanado. */
    const todoLoLogueado = () =>
      JSON.stringify(
        [logger.info, logger.warn, logger.error, logger.debug].flatMap(
          (fn) => (fn as jest.Mock).mock.calls,
        ),
      );

    it("loguea el uid, NUNCA el token", async () => {
      const uid = nuevoUid("log");
      await users().doc(uid).set({ displayName: "Marta" });
      const token = firmarToken(uid, PREF, KEY);

      await runBajaDeCorreosPromocionales(app, { token }, KEY);

      const logs = todoLoLogueado();
      expect(logs).toContain(uid);
      expect(logs).not.toContain(token);
      // Ni el pedazo que lleva el uid codificado, ni la firma.
      expect(logs).not.toContain(token.split(".")[2]);
      expect(logs).not.toContain(token.split(".")[3]);
    });

    it("un token inválido tampoco queda en el log", async () => {
      const basura = "v1.credencial-que-no-deberia-quedar.x.y";

      await runBajaDeCorreosPromocionales(app, { token: basura }, KEY);

      expect(todoLoLogueado()).not.toContain("credencial-que-no-deberia-quedar");
    });

    it("una falla de Firestore loguea el uid y no el token", async () => {
      const uid = nuevoUid("log-falla");
      await users().doc(uid).set({ displayName: "Marta" });
      const token = firmarToken(uid, PREF, KEY);
      jest
        .spyOn(DocumentReference.prototype, "update")
        .mockRejectedValueOnce(Object.assign(new Error("unavailable"), { code: 14 }));

      await runBajaDeCorreosPromocionales(app, { token }, KEY).catch(() => undefined);

      expect(todoLoLogueado()).toContain(uid);
      expect(todoLoLogueado()).not.toContain(token);
    });
  });
});

// ---------------------------------------------------------------------------
// La callable, tal como se despliega
// ---------------------------------------------------------------------------
describe("bajaDeCorreosPromocionales (el wrapper onCall)", () => {
  type Request = Parameters<typeof bajaDeCorreosPromocionales.run>[0];
  const uid = `baja-promo-wrapper-${Date.now()}`;
  let appPorDefecto: App;

  beforeAll(async () => {
    appPorDefecto = initializeApp({ projectId: "treino-dev" });
    process.env.BAJA_PROMOCIONALES_KEY = KEY;
    await getFirestore(appPorDefecto).collection("users").doc(uid).set({ displayName: "Marta" });
  });

  afterAll(async () => {
    delete process.env.BAJA_PROMOCIONALES_KEY;
    await getFirestore(appPorDefecto).collection("users").doc(uid).delete();
    await deleteApp(appPorDefecto);
  });

  it("lee la clave del secreto y da de baja con el token de `request.data`", async () => {
    const out = await bajaDeCorreosPromocionales.run({
      data: { token: firmarToken(uid, PREF, KEY) },
    } as unknown as Request);

    expect(out).toEqual({ status: "listo" });
    const data = (await getFirestore(appPorDefecto).collection("users").doc(uid).get()).data();
    expect(data?.notificationPrefs).toEqual({ novedades_plan: { email: false } });
  });

  it("sin datos en el request contesta `invalido`, no tira", async () => {
    const out = await bajaDeCorreosPromocionales.run({ data: undefined } as unknown as Request);

    expect(out).toEqual({ status: "invalido" });
  });

  it("está desplegada como se promete: region, tope de instancias y secreto", () => {
    const endpoint = bajaDeCorreosPromocionales.__endpoint;

    expect(endpoint.region).toEqual(["southamerica-east1"]);
    expect(endpoint.maxInstances).toBe(5);
    expect(endpoint.secretEnvironmentVariables).toEqual([
      { key: "BAJA_PROMOCIONALES_KEY" },
    ]);
    // Callable pública: sin App Check (la llama una página sin Firebase). La
    // exención está declarada en `appcheck-enforcement.test.ts`.
    expect(JSON.stringify(endpoint)).not.toContain("enforceAppCheck");
  });
});

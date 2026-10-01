/**
 * codigo-de-verificacion.ts — el código de 6 dígitos que confirma el mail.
 *
 * ── Para qué existe (no es solo verificar) ──
 *
 * Decisión de Martín, 2026-10-01: TODOS confirman su mail con un código antes
 * de usar la app, también quienes entran con Google o Apple. El mail que lleva
 * el código es además el que le dice al usuario que los pagos y sus
 * confirmaciones se hacen por mail, con un botón a los planes.
 *
 * Eso es justo lo que la app NO puede decir: un «te mandamos un mail con los
 * planes» impreso en el binario es un llamado a pagar afuera, y con eso se cae
 * la exención 3.1.3(f) (ver `superficie_de_cobro_alumno_test.dart` y
 * `anti_steering_movil_test.dart`). Afuera de la app, en cambio, se puede. Pedir
 * el código es lo que asegura que el mail se abra: sin abrirlo no se entra.
 *
 * ── Por qué un campo propio y no `emailVerified` de Firebase ──
 *
 * Las cuentas de Google y Apple ya vienen con `emailVerified: true`. Con ese
 * campo, justo los que entran con un botón se saltearían el mail, que es el que
 * les explica cómo se paga. `users/{uid}.emailVerification` lo escribe SOLO esta
 * función —está pineado en los dos verbos de `firestore.rules`—, así que no hay
 * forma de marcarse verificado desde el cliente. (El script de promoción borra
 * la entrada de entrenador, por Admin SDK: es lo que vuelve a pedir el código.)
 *
 * ── Por rol, y con el mail adentro ──
 *
 * `emailVerification` es `{ athlete?: {email, verifiedAt}, trainer?: {...} }`.
 * Al alumno que el equipo promueve a entrenador se le vuelve a pedir el código,
 * y el mail que le llega es el del entrenador: el que dice dónde paga un PF.
 * Con un solo flag para los dos roles, la verificación de alumno lo dejaba
 * pasar y ese mail no salía nunca. El mail va guardado porque si el equipo le
 * cambia el correo en Auth, al nuevo todavía no lo abrió nadie.
 *
 * ── Despliegue: el pin protege DESDE que está arriba ──
 *
 * La regla de `users` es por pines, no por lista blanca de claves: hasta que se
 * despliega el pin de `emailVerification`, el dueño puede escribírselo, y
 * después el mismo pin lo vuelve indeleble desde el cliente (mismo molde que
 * `athletePaywallEnforced` en `firestore.rules`). Por eso, en este orden:
 *
 *   1. Desplegar las reglas.
 *   2. Antes de que la app llame a `verificarCodigoDeMail`, contar los `users`
 *      con `emailVerification` (consola: filtro `emailVerification != null`).
 *      Hasta ahí nadie lo escribe, así que lo esperado es 0, y cualquiera que
 *      aparezca es falso: se borra por Admin SDK.
 *   3. Recién ahí desplegar las funciones y prender el gate.
 *
 * ── Seguridad ──
 *
 * - En `verificaciones_de_mail/{uid}` el código se guarda como hash
 *   (sha256 de `uid:código`), nunca en claro. En `mail_queue` viaja en claro
 *   hasta que sale —la plantilla se arma al enviar— y `sendQueuedMail` lo
 *   borra al cerrar el envío, igual que `actionLink`.
 * - 5 intentos por código. Pedir uno nuevo reemplaza al anterior y reinicia los
 *   intentos, pero hay un cooldown de 60 s entre envíos —el mismo que el botón
 *   «Reenviar» de la app; si este fuera más largo, el botón mentiría— y topes de
 *   5 envíos por hora y 10 por día (`decidirEnvio`). Las ventanas son fijas
 *   desde su primer envío, no móviles: en el borde entre dos pueden salir el
 *   doble seguidos.
 * - Fuerza bruta: 10 códigos por ventana de 24 h con 5 intentos cada uno son 50
 *   intentos contra 10^6 combinaciones, 1 en 20.000 por ventana (el doble en el
 *   borde entre dos).
 *
 * ── El bloque de pagos del mail ──
 *
 * Va solo si le sirve y si se puede decir: ver `muestraPlanes`.
 */

import { createHash, randomInt, timingSafeEqual } from "node:crypto";

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { enqueueMail } from "../mail/enqueue-mail";
import {
  ATHLETE_PAYWALL_ENFORCEMENT_ENABLED,
  ENFORCED_FIELD,
} from "../subscriptions/athlete-paywall-enforced";
import { ATHLETE_PROSPECT_PREF_KEY } from "../subscriptions/athlete-prospect-mail";

/** Un documento por usuario, con el código vigente. Solo servidor. */
export const VERIFICACIONES_COLLECTION = "verificaciones_de_mail";

/** El mapa de `users/{uid}` que dice para qué rol se confirmó el mail, y cuál. */
export const CAMPO_VERIFICACION = "emailVerification";

export const CODIGO_VIGENCIA_MS = 15 * 60 * 1000;

/**
 * Cooldown entre envíos. TIENE QUE SEGUIR ALINEADO con el del botón «Reenviar»
 * de la pantalla del código: si este fuera más largo, el usuario tocaría
 * Reenviar, vería que salió, y el mail no saldría.
 */
export const REENVIO_COOLDOWN_MS = 60 * 1000;

export const MAX_INTENTOS = 5;

/**
 * Topes de envíos por cuenta. El cooldown solo separa un envío del siguiente;
 * esto acota cuántos mails saca una cuenta contra la cuota de Resend, que el
 * día del encendido ya recibe uno por cada cuenta que abre la app.
 */
export const MAX_ENVIOS_POR_HORA = 5;
export const MAX_ENVIOS_POR_DIA = 10;
const HORA_MS = 60 * 60 * 1000;
const DIA_MS = 24 * HORA_MS;

const FORMA_DEL_CODIGO = /^\d{6}$/;

export type EstadoDeSolicitud =
  /** Se generó un código nuevo y quedó en la cola de mails. */
  | "enviado"
  /**
   * Ya hay un código sin vencer y con intentos: NO se manda otro. Lo contesta el
   * pedido automático de la pantalla (ver `SolicitudDeCodigoOpciones`).
   */
  | "vigente"
  /** El mail ya estaba confirmado: no hay nada que mandar. */
  | "ya-verificado"
  /** Hubo un envío hace menos de 60 s. `reintentarEnMs` dice cuánto falta. */
  | "enfriando"
  /** Llegó al tope de envíos de la hora o del día. `reintentarEnMs`, ídem. */
  | "limitado"
  /** La cuenta todavía no eligió rol: no sabemos qué mail mandarle. */
  | "sin-perfil"
  /** La cuenta no tiene mail (no debería pasar con los métodos de ingreso de hoy). */
  | "sin-email";

export interface SolicitudDeCodigoResult {
  estado: EstadoDeSolicitud;
  reintentarEnMs?: number;
}

export type EstadoDeVerificacion =
  | "verificado"
  /** No coincide. `intentosRestantes` dice cuántos quedan para ESTE código. */
  | "incorrecto"
  | "vencido"
  /** Se agotaron los intentos de este código: hay que pedir otro. */
  | "bloqueado"
  /**
   * Nunca se pidió un código, ya se usó, o es de otro rol (lo promovieron en el
   * medio) o de otro mail.
   */
  | "sin-codigo"
  /** No son 6 dígitos. No gasta intentos: es un error de tipeo, no un intento. */
  | "formato-invalido";

export interface VerificacionResult {
  estado: EstadoDeVerificacion;
  intentosRestantes?: number;
}

export interface SolicitudDeCodigoOpciones {
  /**
   * `true` solo desde el botón «Reenviar». La pantalla pide el código sola al
   * abrirse, y cada código nuevo invalida el anterior: sin esto, quien cierra la
   * app para ir a buscar el mail vuelve, la pantalla pide otro, y el que tiene en
   * la bandeja ya no sirve. Con `false`, si hay uno vigente se contesta `vigente`
   * y no se manda nada.
   */
  reenviar?: boolean;
}

export interface CodigoDeps {
  /** Reloj inyectable: el vencimiento y el cooldown se testean sin esperar. */
  nowMs: number;
  /** Generador inyectable, para que el test conozca el código. */
  generarCodigo?: () => string;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** 6 dígitos de un generador criptográfico. `000123` es un código válido. */
export function generarCodigo(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, "0");
}

/** Lo único que se guarda del código. Con el uid adentro, el mismo código da otro hash en otra cuenta. */
export function hashDelCodigo(uid: string, codigo: string): string {
  return createHash("sha256").update(`${uid}:${codigo}`).digest("hex");
}

function mismoHash(a: string, b: string): boolean {
  const x = Buffer.from(a, "hex");
  const y = Buffer.from(b, "hex");
  return x.length === y.length && x.length > 0 && timingSafeEqual(x, y);
}

type Rol = "athlete" | "trainer";

const esRol = (rol: unknown): rol is Rol => rol === "athlete" || rol === "trainer";

/** Auth y lo guardado pueden diferir en mayúsculas o espacios: no es otro mail. */
const normal = (email: unknown): string =>
  typeof email === "string" ? email.trim().toLowerCase() : "";

/**
 * Si `usuario` confirmó con código, para el rol que tiene HOY, el mail que Auth
 * tiene HOY. Ver el encabezado: por qué por rol y por qué con el mail.
 */
export function verificadoParaSuRol(
  usuario: Record<string, unknown> | undefined,
  email: string | undefined,
): boolean {
  const rol = usuario?.role;
  if (!esRol(rol)) return false;
  const porRol = usuario?.[CAMPO_VERIFICACION] as
    | Partial<Record<Rol, { email?: unknown }>>
    | undefined;
  const confirmado = normal(porRol?.[rol]?.email);
  return confirmado !== "" && confirmado === normal(email);
}

/** Las ventanas de los topes, tal como quedan escritas si el envío sale. */
export interface Ventanas {
  horaDesdeMs: number;
  enviosEnLaHora: number;
  diaDesdeMs: number;
  enviosEnElDia: number;
}

export type DecisionDeEnvio =
  | { estado: "enviar"; ventanas: Ventanas }
  | { estado: "vigente" }
  | { estado: "enfriando" | "limitado"; reintentarEnMs: number };

const num = (v: unknown): number | undefined => (typeof v === "number" ? v : undefined);

/**
 * Si sale un código nuevo, dado el documento anterior. En orden: un código
 * todavía útil no se pisa, el cooldown separa los envíos, y los topes de la
 * hora y del día acotan el total. Las ventanas son fijas desde su primer envío.
 */
export function decidirEnvio(
  previo: Record<string, unknown> | undefined,
  pedido: { rol: Rol; email: string; nowMs: number; reenviar: boolean },
): DecisionDeEnvio {
  const { nowMs } = pedido;
  // Un código emitido para el otro rol o para otro mail no le sirve a nadie: al
  // recién promovido le toca el mail del entrenador. No cuenta como vigente ni
  // lo frena el cooldown —el rol y el mail solo los cambia el equipo—. Los
  // topes sí corren: cuidan la cuota, no al usuario.
  const mismoPedido =
    previo?.rol === pedido.rol && normal(previo?.email) === normal(pedido.email);

  // Pedido automático con un código todavía útil: no se pisa. Ver
  // `SolicitudDeCodigoOpciones.reenviar`.
  const vence = num(previo?.venceMs);
  if (
    !pedido.reenviar && mismoPedido && vence !== undefined && nowMs <= vence &&
    (num(previo?.intentos) ?? 0) < MAX_INTENTOS
  ) {
    return { estado: "vigente" };
  }

  const enviado = num(previo?.enviadoMs);
  if (mismoPedido && enviado !== undefined && nowMs - enviado < REENVIO_COOLDOWN_MS) {
    return { estado: "enfriando", reintentarEnMs: REENVIO_COOLDOWN_MS - (nowMs - enviado) };
  }

  const ventana = (desde: unknown, envios: unknown, largo: number) => {
    const d = num(desde);
    return d !== undefined && nowMs - d < largo ?
      { desde: d, envios: num(envios) ?? 0, hasta: d + largo } :
      { desde: nowMs, envios: 0, hasta: nowMs + largo };
  };
  const hora = ventana(previo?.horaDesdeMs, previo?.enviosEnLaHora, HORA_MS);
  const dia = ventana(previo?.diaDesdeMs, previo?.enviosEnElDia, DIA_MS);
  const espera = Math.max(
    hora.envios >= MAX_ENVIOS_POR_HORA ? hora.hasta - nowMs : 0,
    dia.envios >= MAX_ENVIOS_POR_DIA ? dia.hasta - nowMs : 0,
  );
  if (espera > 0) return { estado: "limitado", reintentarEnMs: espera };

  return {
    estado: "enviar",
    ventanas: {
      horaDesdeMs: hora.desde,
      enviosEnLaHora: hora.envios + 1,
      diaDesdeMs: dia.desde,
      enviosEnElDia: dia.envios + 1,
    },
  };
}

/**
 * Si el mail del código lleva el bloque de pagos. Va sin él cuando:
 * - el usuario apagó lo comercial por mail (`novedades_plan`): la política de
 *   privacidad promete la oposición, y este mail es obligatorio;
 * - es alumno y el plan free no le aplica (`athletePaywallEnforced === false`:
 *   ya paga, tiene un PF activo, o el interruptor está apagado). Sin paywall, el
 *   checkout de la landing da 404.
 *
 * El campo AUSENTE cuenta como que aplica, al revés que en `firestore.rules`
 * (que lo lee como `false` para no bloquear de más): ausente es la cuenta recién
 * creada, a la que `syncAthletePaywallOnUser` todavía no le escribió nada, y que
 * todavía no tiene suscripción ni PF vinculado. Con el interruptor apagado no
 * aplica a nadie.
 */
export function muestraPlanes(
  rol: Rol,
  usuario: Record<string, unknown> | undefined,
  paywallDelAlumnoPrendido: boolean,
): boolean {
  const prefs = usuario?.notificationPrefs as
    | Record<string, { email?: unknown } | undefined>
    | undefined;
  if (prefs?.[ATHLETE_PROSPECT_PREF_KEY]?.email === false) return false;
  return rol === "trainer" || (paywallDelAlumnoPrendido && usuario?.[ENFORCED_FIELD] !== false);
}

/**
 * Genera un código y lo manda por mail. El mail depende del rol: el del
 * entrenador lo manda a los planes del Coach Hub; el del alumno, al checkout
 * de gettreino.com.
 */
export async function runSolicitarCodigo(
  app: App,
  uid: string,
  deps: CodigoDeps,
  opciones: SolicitudDeCodigoOpciones = {},
): Promise<SolicitudDeCodigoResult> {
  const db = getFirestore(app);
  const usuario = (await db.collection("users").doc(uid).get()).data();
  const rol = usuario?.role;
  if (!esRol(rol)) return { estado: "sin-perfil" };

  const { email } = await getAuth(app).getUser(uid);
  if (!email) return { estado: "sin-email" };
  if (verificadoParaSuRol(usuario, email)) return { estado: "ya-verificado" };

  const ref = db.collection(VERIFICACIONES_COLLECTION).doc(uid);
  const codigo = (deps.generarCodigo ?? generarCodigo)();

  // Transacción: dos pedidos simultáneos no pasan los dos el cooldown ni los
  // topes. Sin ella, una ráfaga de pedidos en paralelo saca un mail cada uno.
  const decision = await db.runTransaction(async (tx) => {
    const d = decidirEnvio((await tx.get(ref)).data(), {
      rol,
      email,
      nowMs: deps.nowMs,
      reenviar: opciones.reenviar === true,
    });
    if (d.estado === "enviar") {
      // El código nuevo REEMPLAZA al anterior: el viejo deja de servir y los
      // intentos vuelven a cero.
      tx.set(ref, {
        codigoHash: hashDelCodigo(uid, codigo),
        rol,
        email,
        venceMs: deps.nowMs + CODIGO_VIGENCIA_MS,
        intentos: 0,
        enviadoMs: deps.nowMs,
        ...d.ventanas,
      });
    }
    return d;
  });
  if (decision.estado !== "enviar") return decision;

  // `enqueueMail` no tira nunca: devuelve `null` si no pudo escribir. Con un
  // `scope` único por envío, `null` solo puede ser una falla.
  const encolado = await enqueueMail(app, {
    toUid: uid,
    kind: rol === "trainer" ? "email-code-trainer" : "email-code-athlete",
    scope: `${uid}_${deps.nowMs}`,
    params: {
      codigo,
      showPlans: muestraPlanes(rol, usuario, ATHLETE_PAYWALL_ENFORCEMENT_ENABLED) ? "1" : "0",
    },
  });
  if (encolado === null) {
    // Se borra el código: el mail no salió, así que ese código no le sirve a
    // nadie, y sin documento tampoco queda el cooldown —castigar al usuario con
    // 60 s de espera por una falla nuestra sería el botón que miente—. También
    // se reinician los topes, y eso no abre nada: la falla de la cola no la
    // provoca el usuario.
    await ref.delete().catch(() => undefined);
    logger.error("codigoDeVerificacion: no se pudo encolar el mail", { uid });
    throw new HttpsError("unavailable", "No pudimos mandar el código. Probá de nuevo.");
  }

  return { estado: "enviado" };
}

/**
 * Valida el código. Si coincide, marca `users/{uid}.emailVerification.<rol>` y
 * borra el código: se usa una sola vez.
 */
export async function runVerificarCodigo(
  app: App,
  uid: string,
  codigoCrudo: unknown,
  deps: CodigoDeps,
): Promise<VerificacionResult> {
  const codigo = typeof codigoCrudo === "string" ? codigoCrudo.trim() : "";
  if (!FORMA_DEL_CODIGO.test(codigo)) return { estado: "formato-invalido" };

  const db = getFirestore(app);
  const ref = db.collection(VERIFICACIONES_COLLECTION).doc(uid);
  const userRef = db.collection("users").doc(uid);
  // Afuera: el callback de la transacción se reintenta y Auth no es parte de
  // ella. Si el mail cambia en el medio, no coincide con el del código y falla
  // cerrado (`sin-codigo`).
  const { email } = await getAuth(app).getUser(uid);

  // Transacción: dos intentos simultaneos no pueden gastar el mismo intento, y
  // el código no puede canjearse dos veces.
  const r = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const usuario = (await tx.get(userRef)).data();
    const d = snap.data();
    const rol = usuario?.role;
    if (!d || !email || !esRol(rol) || d.rol !== rol || normal(d.email) !== normal(email)) {
      // Sin código pendiente, o con uno que ya no corresponde: de otro rol o de
      // otro mail. Si ya está verificado es un doble toque, no un error: la
      // pantalla tiene que poder seguir.
      return verificadoParaSuRol(usuario, email) ?
        { estado: "verificado" as const, recien: false } :
        { estado: "sin-codigo" as const, recien: false };
    }

    const intentos = typeof d.intentos === "number" ? d.intentos : 0;
    if (intentos >= MAX_INTENTOS) return { estado: "bloqueado" as const, recien: false };
    if (typeof d.venceMs !== "number" || deps.nowMs > d.venceMs) {
      return { estado: "vencido" as const, recien: false };
    }

    if (!mismoHash(String(d.codigoHash ?? ""), hashDelCodigo(uid, codigo))) {
      const usados = intentos + 1;
      tx.update(ref, { intentos: usados });
      const restantes = MAX_INTENTOS - usados;
      return restantes > 0 ?
        { estado: "incorrecto" as const, intentosRestantes: restantes, recien: false } :
        { estado: "bloqueado" as const, recien: false };
    }

    // El mapa entero, armado desde la lectura de esta misma transacción: la
    // entrada del otro rol sobrevive sin depender del merge profundo de `set`.
    const porRol = (usuario?.[CAMPO_VERIFICACION] ?? {}) as Record<string, unknown>;
    tx.update(userRef, {
      [CAMPO_VERIFICACION]: {
        ...porRol,
        [rol]: { email, verifiedAt: Timestamp.fromMillis(deps.nowMs) },
      },
    });
    tx.delete(ref);
    return { estado: "verificado" as const, recien: true };
  });

  if (r.recien) {
    // Para las cuentas con contraseña, que todavía tienen `emailVerified` en
    // false. No es lo que decide el acceso —eso es `emailVerification`—, así que
    // si falla se avisa y se sigue.
    await getAuth(app)
      .updateUser(uid, { emailVerified: true })
      .catch((error: unknown) => {
        logger.warn("codigoDeVerificacion: no se pudo marcar emailVerified", {
          uid,
          error: String(error),
        });
      });
  }

  return r.estado === "incorrecto" ?
    { estado: r.estado, intentosRestantes: r.intentosRestantes } :
    { estado: r.estado };
}

// ---------------------------------------------------------------------------
// onCall wrappers
//
// SIN `enforceAppCheck`, por el mismo motivo que `requestEmailVerification`:
// hoy una parte real de los Android no atesta, y con el flag este paso —que es
// OBLIGATORIO para entrar— dejaría a esas personas afuera para siempre. Lo que
// protege es que los dos exigen sesión y solo operan sobre el uid del token.
// Deuda declarada en el registry de `appcheck-enforcement.test.ts`.
// ---------------------------------------------------------------------------

/**
 * Callable: mandar el código. Requiere sesión. Body opcional `{reenviar: true}`,
 * solo desde el botón «Reenviar»: sin él, un código vigente no se pisa.
 */
export const solicitarCodigoDeVerificacion = functions.onCall(
  { region: "southamerica-east1" },
  async (request): Promise<SolicitudDeCodigoResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const reenviar = (request.data ?? {}).reenviar === true;
    return runSolicitarCodigo(ensureApp(), request.auth.uid, { nowMs: Date.now() }, { reenviar });
  },
);

/** Callable: validar el código. Requiere sesión. Body: `{codigo}`. */
export const verificarCodigoDeMail = functions.onCall(
  { region: "southamerica-east1" },
  async (request): Promise<VerificacionResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const codigo = (request.data ?? {}).codigo;
    return runVerificarCodigo(ensureApp(), request.auth.uid, codigo, { nowMs: Date.now() });
  },
);

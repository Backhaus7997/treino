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
 * ── Seguridad ──
 *
 * - En `verificaciones_de_mail/{uid}` el código se guarda como hash
 *   (sha256 de `uid:código`), nunca en claro. En `mail_queue` viaja en claro
 *   hasta que sale —la plantilla se arma al enviar— y `sendQueuedMail` lo
 *   borra al cerrar el envío, igual que `actionLink`.
 * - 5 intentos por código. Pedir uno nuevo reemplaza al anterior y reinicia los
 *   intentos, pero hay un cooldown de 60 s entre envíos —el mismo que el botón
 *   «Reenviar» de la app; si este fuera más largo, el botón mentiría—.
 * - Fuerza bruta: como mucho 5 intentos por minuto contra 10^6 combinaciones.
 *   En la vida de un código (15 min) eso es menos de 1 en 13.000.
 */

import { createHash, randomInt, timingSafeEqual } from "node:crypto";

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { enqueueMail } from "../mail/enqueue-mail";

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
  const previo = (await ref.get()).data();

  // Un código emitido para el otro rol o para otro mail no le sirve a nadie: al
  // recién promovido le toca el mail del entrenador. No cuenta como vigente ni
  // lo frena el cooldown —el rol y el mail solo los cambia el equipo—.
  const mismoPedido = previo?.rol === rol && normal(previo?.email) === normal(email);

  // Pedido automático con un código todavía útil: no se pisa. Ver
  // `SolicitudDeCodigoOpciones.reenviar`.
  const intentosPrevios = typeof previo?.intentos === "number" ? previo.intentos : 0;
  if (
    opciones.reenviar !== true &&
    mismoPedido &&
    typeof previo?.venceMs === "number" &&
    deps.nowMs <= previo.venceMs &&
    intentosPrevios < MAX_INTENTOS
  ) {
    return { estado: "vigente" };
  }

  const enviadoMs = previo?.enviadoMs;
  if (mismoPedido && typeof enviadoMs === "number" && deps.nowMs - enviadoMs < REENVIO_COOLDOWN_MS) {
    return {
      estado: "enfriando",
      reintentarEnMs: REENVIO_COOLDOWN_MS - (deps.nowMs - enviadoMs),
    };
  }

  // El código nuevo REEMPLAZA al anterior: el viejo deja de servir y los
  // intentos vuelven a cero.
  const codigo = (deps.generarCodigo ?? generarCodigo)();
  await ref.set({
    codigoHash: hashDelCodigo(uid, codigo),
    rol,
    email,
    venceMs: deps.nowMs + CODIGO_VIGENCIA_MS,
    intentos: 0,
    enviadoMs: deps.nowMs,
  });

  // `enqueueMail` no tira nunca: devuelve `null` si no pudo escribir. Con un
  // `scope` único por envío, `null` solo puede ser una falla.
  const encolado = await enqueueMail(app, {
    toUid: uid,
    kind: rol === "trainer" ? "email-code-trainer" : "email-code-athlete",
    scope: `${uid}_${deps.nowMs}`,
    params: { codigo },
  });
  if (encolado === null) {
    // Se borra el código: el mail no salió, así que ese código no le sirve a
    // nadie, y sin documento tampoco queda el cooldown —castigar al usuario con
    // 60 s de espera por una falla nuestra sería el botón que miente—.
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

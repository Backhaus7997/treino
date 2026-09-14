/**
 * sweep-inactive-accounts.ts — la baja automática de cuentas inactivas.
 *
 * Aviso por correo a los 24 meses, baja a los 36, con el mismo alcance de
 * borrado que una eliminación pedida por el usuario. El plazo lo decidió el
 * titular el 2026-09-14 y ya está escrito en `docs/legal/retencion-y-borrado.md`
 * §6; esto es el proceso que lo ejecuta. Spec:
 * `openspec/changes/baja-cuentas-inactivas/proposal.md`.
 *
 * ─── La señal de actividad, y por qué no vive en Firestore ──────────────────
 *
 * `UserProfile` tiene `createdAt` y `updatedAt`, y `updatedAt` se mueve cuando
 * se EDITA el perfil, no cuando la persona usa la app. Alguien que entrena
 * cinco veces por semana y nunca toca su perfil se ve idéntico a alguien que
 * no abre la app hace dos años. O sea: hoy no hay ninguna marca de última
 * actividad, y ésta es la primera cosa que hubo que resolver.
 *
 * Se usa `lastRefreshTime` de los metadatos de Firebase Auth (opción A del
 * spec §3). El token se refresca solo cada vez que la app corre con la sesión
 * abierta, así que es uso real, no toca el cliente, no agrega escrituras y no
 * abre nada en las reglas. Lo decisivo: **ya tiene historia**. Un campo nuevo
 * escrito por el cliente arrancaría el reloj el día del deploy y el primer
 * aviso legítimo saldría recién dentro de dos años.
 *
 * La contracara de esa historia es que **en la primera corrida real hay
 * backlog**: cuentas que ya pasaron los 24 meses y a las que el barrido les
 * mandaría el aviso todas juntas. Por eso `dryRun` y `maxPerRun` no son
 * adorno — ver el bloque de opciones.
 *
 * ─── Por qué el orden de las guardas NO contradice al spec §4.5 ─────────────
 *
 * El spec pide que las exclusiones —entrenador, suscripción vigente, vínculo
 * activo— se evalúen ANTES que la inactividad y saquen a la cuenta del barrido
 * entero: ni aviso ni baja. Acá la primera guarda es igual la inactividad, y
 * conviene dejar escrito por qué eso no cambia un solo resultado:
 *
 *   · Cuenta ACTIVA (< 24 meses): no le toca ni aviso ni baja, esté excluida o
 *     no. Las dos ramas terminan en lo mismo.
 *   · Cuenta INACTIVA y excluida: la exclusión se evalúa igual, antes de
 *     cualquier acción, y la saca del barrido entero.
 *
 * Lo que sí cambia es el COSTO. `hasActiveTrainerLink` es una query por cuenta:
 * evaluarla primero significaría consultar `trainer_links` una vez por cada
 * usuario de la base, todos los días, para decidir sobre cuentas que no van a
 * recibir nada. Con la guarda de inactividad adelante, el barrido en régimen
 * cuesta una `listUsers` y prácticamente nada más. Mismo criterio que las
 * salidas tempranas de `resolveAthletePaywallEnforced`.
 *
 * ─── La regla que no se negocia ─────────────────────────────────────────────
 *
 * NUNCA se borra sin un aviso previo REGISTRADO, por más años de inactividad
 * que tenga la cuenta. El registro vive en `retention_notices/{uid}` y es lo
 * único que habilita el paso a la baja.
 *
 * El piso del aviso es [MIN_NOTICE_AGE_DAYS] = 90 días, y ese número salió de
 * una decisión, no de una convención. Vale saber cuál, porque el candidato
 * obvio era otro.
 *
 * La tensión: `docs/legal` §6 decía que el aviso "llega con doce meses de
 * antelación a la baja". En régimen estable es cierto —se avisa a los 24 y se
 * borra a los 36— pero para el BACKLOG no: una cuenta que al encender el
 * barrido ya tiene 40 meses recibe el aviso tarde, y el hueco lo fija el piso.
 * Con los 30 días que pedía el spec §4.3 se borraba un mes después.
 *
 * **Por qué NO se subió el piso a 365**, que era la salida evidente: la
 * cláusula quedaría peleando contra su propia justificación. El último párrafo
 * de §6 invoca el art. 4 inc. 7 de la Ley 25.326 —los datos se destruyen cuando
 * dejan de ser necesarios— y con 365 estaríamos reteniendo doce meses MÁS las
 * medidas corporales, las fotos de dolor y los check-ins de ánimo de cuentas
 * que hace más de tres años que nadie toca. No por una necesidad real: para
 * honrar una frase escrita pensando sólo en el régimen estable. El backlog es
 * una transición de una sola vez, no una regla.
 *
 * **Por qué tampoco quedaron los 30**: nacieron como baranda técnica, para que
 * ninguna baja ocurra sin que el aviso haya tenido tiempo de llegar. Para una
 * cuenta que guarda datos de salud, 30 días como única garantía es flaco.
 *
 * 90 cierra las dos puntas con UNA constante y sin una rama especial para el
 * backlog —que es justo el código que después nadie se acuerda de sacar—, y la
 * frase legal ahora promete un piso en vez de un número fijo. Decisión del
 * 2026-09-14.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import {
  DocumentData,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { runDeleteAccount } from "../delete-account";
import { enqueueMail } from "../mail/enqueue-mail";
import { formatShortDateAR } from "../mail/format";
import { hasEntitlingSubscription } from "../subscriptions/athlete-paywall-enforced";
import { RETENTION_NOTICES_COLLECTION } from "./collection";

/**
 * Colección del registro de avisos. CF-only: `firestore.rules` la cierra en
 * los cuatro verbos y `retention-notices-rules.test.ts` lo fija.
 *
 * Se re-exporta para que los consumidores del barrido no tengan que conocer el
 * módulo de una sola línea que existe sólo para romper un ciclo de imports.
 */
export { RETENTION_NOTICES_COLLECTION };

/** Meses de inactividad que disparan el aviso por correo. */
export const NOTICE_AFTER_MONTHS = 24;

/** Meses de inactividad que habilitan la baja. */
export const DELETE_AFTER_MONTHS = 36;

/**
 * Días mínimos entre el aviso y la baja.
 *
 * NO es un detalle de implementación: es la mitad de una promesa escrita en
 * `docs/legal/retencion-y-borrado.md` §6 ("entre el aviso y la baja nunca pasan
 * menos de 90 días"). Cambiarlo sin cambiar esa frase publica una afirmación
 * falsa, y lo fija un test — ver `sweep-inactive-accounts.test.ts`.
 *
 * En régimen estable **no se activa nunca**: el hueco entre
 * [NOTICE_AFTER_MONTHS] y [DELETE_AFTER_MONTHS] ya es de doce meses. Sólo
 * muerde en el backlog, o sea las cuentas que al encender el barrido ya superan
 * los 24 meses y reciben el aviso tarde.
 */
export const MIN_NOTICE_AGE_DAYS = 90;

/**
 * El `provider` con el que la baja automática firma el registro de auditoría.
 *
 * `runDeleteAccount` usa el tercer parámetro sólo para `audit_log`, así que un
 * valor propio deja la baja por retención distinguible de una pedida por el
 * usuario cuando alguien lea ese log. Es también el único rastro que sobrevive
 * a la cascada: `retention_notices/{uid}` se borra con el resto.
 */
export const RETENTION_SWEEP_PROVIDER = "system:retention-sweep";

/** Máximo que acepta `listUsers` por página. */
const LIST_USERS_PAGE_SIZE = 1000;

/**
 * Tope de ACCIONES por corrida cuando nadie pasa uno.
 *
 * Acota avisos + bajas, no cuentas escaneadas: el escaneo es barato y saltearlo
 * a la mitad dejaría el barrido mirando siempre el mismo prefijo de la base.
 * Lo que hay que poder frenar es lo irreversible.
 */
export const DEFAULT_MAX_PER_RUN = 50;

/** Una cuenta y su señal de actividad ya resuelta. */
export interface AccountActivity {
  uid: string;
  lastActiveAt: Date;
}

/** Lo que devuelve una corrida. Todo lo que se loguea sale de acá. */
export interface SweepInactiveResult {
  dryRun: boolean;
  /** Cuentas de Auth miradas. */
  scanned: number;
  /** Inactivas ≥ 24 meses que sobrevivieron a las exclusiones. */
  inactive: number;
  /** Avisos encolados (o que se habrían encolado, en `dryRun`). */
  noticed: number;
  /** Bajas ejecutadas (o que se habrían ejecutado, en `dryRun`). */
  deleted: number;
  /** Entrenadores inactivos: NO se tocan, van al log para revisión manual. */
  excludedTrainers: number;
  excludedSubscription: number;
  excludedActiveLink: number;
  /** Usuarios de Auth sin `users/{uid}`. Se saltean: ver [evaluarCuenta]. */
  skippedNoUserDoc: number;
  /** Cuentas que explotaron. Una no frena a las demás. */
  errors: number;
  /** `true` si el tope cortó la corrida antes de terminar la base. */
  capped: boolean;
}

/** Parámetros del barrido. Todo inyectable: el spec §6 pide testearlo sin Auth. */
export interface SweepInactiveOptions {
  /**
   * No escribe NADA: cuenta, lista y loguea a quién le tocaría aviso y a quién
   * baja. **La primera corrida va en `dryRun` sí o sí** (spec §4.6), y se lee
   * el resultado antes de encenderlo. Con el backlog de la opción A eso no es
   * prudencia genérica: es la diferencia entre leer un número y mandar ese
   * número de mails.
   */
  dryRun?: boolean;
  /** Tope de acciones. Ver [DEFAULT_MAX_PER_RUN]. */
  maxPerRun?: number;
  /** Reloj inyectable. Sin esto no hay test de plazos posible. */
  now?: Date;
  /** Fuente de cuentas. Por default, `listUsers` paginado sobre Auth. */
  listAccounts?: (app: App) => AsyncIterable<AccountActivity>;
  /** La baja. Por default, la cascada real. Inyectable para no borrar en test. */
  deleteAccount?: (app: App, uid: string, provider: string) => Promise<unknown>;
}

/** Los metadatos de Auth que nos importan, en la forma en que llegan. */
export interface AuthUserMetadata {
  lastRefreshTime?: string | null;
  lastSignInTime?: string | null;
  creationTime?: string | null;
}

/**
 * La señal de actividad de una cuenta, con sus dos caídas.
 *
 * `lastRefreshTime` es la señal buena: el token se refresca cada vez que la app
 * corre con sesión abierta. Cuando viene vacío cae a `lastSignInTime`, y si
 * tampoco está, a `creationTime` — una cuenta recién creada que nunca entró es
 * inactiva desde su creación, no desde "nunca", que sería tratarla como activa
 * para siempre.
 *
 * Devuelve `null` sólo si NINGUNO de los tres sirve. Esa cuenta se saltea: sin
 * señal no se puede afirmar que esté inactiva, y ante la duda no se borra.
 */
export function resolveLastActiveAt(
  metadata: AuthUserMetadata | undefined,
): Date | null {
  const candidatos = [
    metadata?.lastRefreshTime,
    metadata?.lastSignInTime,
    metadata?.creationTime,
  ];
  for (const raw of candidatos) {
    if (typeof raw !== "string" || raw.length === 0) continue;
    const fecha = new Date(raw);
    if (!Number.isNaN(fecha.getTime())) return fecha;
  }
  return null;
}

/**
 * Suma meses en UTC, recortando el día cuando el mes destino es más corto.
 *
 * Sin el recorte, `setUTCMonth` desborda: 31 de enero menos un mes da 3 de
 * marzo, o sea una cuenta MENOS inactiva de lo que es. Es un error chico y
 * siempre en la misma dirección, que es justo la clase que nadie ve.
 */
export function addMonths(date: Date, months: number): Date {
  const dia = date.getUTCDate();
  const salida = new Date(date.getTime());
  salida.setUTCDate(1);
  salida.setUTCMonth(salida.getUTCMonth() + months);
  const ultimoDelMes = new Date(Date.UTC(
    salida.getUTCFullYear(),
    salida.getUTCMonth() + 1,
    0,
  )).getUTCDate();
  salida.setUTCDate(Math.min(dia, ultimoDelMes));
  return salida;
}

/** Suma días. Separado de [addMonths] porque un día siempre dura lo mismo. */
export function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

/** Si la cuenta lleva al menos `months` meses sin señal de uso. */
function inactivaHace(lastActiveAt: Date, now: Date, months: number): boolean {
  return lastActiveAt.getTime() <= addMonths(now, -months).getTime();
}

/**
 * La fecha REAL a partir de la cual esta cuenta puede darse de baja.
 *
 * Las DOS condiciones tienen que cumplirse, así que la fecha es la más tardía
 * de las dos: 36 meses desde la última actividad, y [MIN_NOTICE_AGE_DAYS] días
 * desde el aviso.
 *
 * Es el número que va al mail, y por eso se calcula acá en vez de escribir
 * "dentro de doce meses" en el copy. Para el backlog de la primera corrida esas
 * dos frases NO dicen lo mismo —una cuenta de 40 meses se borra al cumplirse el
 * piso, no en doce meses— y el mail que promete mal es exactamente lo que este
 * trabajo existe para no publicar (AGENTS.md §11.1).
 */
export function proyeccionDeBaja(lastActiveAt: Date, noticeSentAt: Date): Date {
  const porInactividad = addMonths(lastActiveAt, DELETE_AFTER_MONTHS);
  const porAviso = addDays(noticeSentAt, MIN_NOTICE_AGE_DAYS);
  return porInactividad.getTime() >= porAviso.getTime()
    ? porInactividad
    : porAviso;
}

/** `yyyyMM` en UTC. Scope de dedupe del mail: un aviso por cuenta por mes. */
export function mesDeDedupe(now: Date): string {
  const anio = now.getUTCFullYear();
  const mes = String(now.getUTCMonth() + 1).padStart(2, "0");
  return `${anio}${mes}`;
}

/** Lo que el barrido decidió hacer con una cuenta. */
type Decision =
  | { tipo: "activa" }
  | { tipo: "sin-doc" }
  | { tipo: "excluida"; motivo: "trainer" | "subscription" | "active-link" }
  | { tipo: "aviso" }
  | { tipo: "baja"; noticeSentAt: Date }
  | { tipo: "esperando" };

/** El registro de aviso de una cuenta, ya normalizado. */
interface AvisoRegistrado {
  noticeSentAt: Date | null;
}

async function leerAviso(
  app: App,
  uid: string,
): Promise<AvisoRegistrado | null> {
  const snap = await getFirestore(app)
    .collection(RETENTION_NOTICES_COLLECTION)
    .doc(uid)
    .get();
  if (!snap.exists) return null;
  const raw = snap.data()?.noticeSentAt;
  const fecha = raw instanceof Timestamp ? raw.toDate() : null;
  return { noticeSentAt: fecha };
}

/** Si el alumno tiene algún vínculo ACTIVO con un PF. */
async function tieneVinculoActivo(app: App, uid: string): Promise<boolean> {
  const snap = await getFirestore(app)
    .collection("trainer_links")
    .where("athleteId", "==", uid)
    .where("status", "==", "active")
    .limit(1)
    .get();
  return !snap.empty;
}

/**
 * Decide qué le toca a UNA cuenta. No escribe nada.
 *
 * Separado de la ejecución a propósito: es la mitad que tiene los plazos y las
 * exclusiones, o sea todo lo que hay que poder testear sin tocar la base, y es
 * también lo único que corre en `dryRun`.
 *
 * Una cuenta de Auth SIN `users/{uid}` se saltea. Sin ese documento no se puede
 * evaluar ninguna de las tres exclusiones —el rol, la suscripción y el vínculo
 * salen de ahí— y una baja es irreversible: ante la duda, no se toca. Queda
 * contada en `skippedNoUserDoc` para que el hueco se vea en el log en vez de
 * desaparecer.
 */
export async function evaluarCuenta(
  app: App,
  cuenta: AccountActivity,
  now: Date,
): Promise<Decision> {
  // Guarda barata primero. Ver el encabezado: no cambia ningún resultado.
  if (!inactivaHace(cuenta.lastActiveAt, now, NOTICE_AFTER_MONTHS)) {
    return { tipo: "activa" };
  }

  const snap = await getFirestore(app)
    .collection("users")
    .doc(cuenta.uid)
    .get();
  if (!snap.exists) return { tipo: "sin-doc" };
  const userData = snap.data() as DocumentData | undefined;

  // ── Exclusiones (spec §4.5). Sacan del barrido ENTERO: ni aviso ni baja ──
  //
  // También alcanzan al AVISO, y no sólo a la baja: el mail de los 24 meses
  // dice que a los 36 se da de baja la cuenta. Mandárselo a alguien que nunca
  // vamos a borrar sería la misma afirmación falsa que este trabajo existe para
  // evitar, del otro lado.
  if (userData?.role === "trainer") {
    return { tipo: "excluida", motivo: "trainer" };
  }
  if (hasEntitlingSubscription(userData)) {
    return { tipo: "excluida", motivo: "subscription" };
  }
  if (await tieneVinculoActivo(app, cuenta.uid)) {
    return { tipo: "excluida", motivo: "active-link" };
  }

  const aviso = await leerAviso(app, cuenta.uid);
  if (aviso === null) return { tipo: "aviso" };

  // Registro de aviso sin fecha: no se puede afirmar que cumpla el piso, así
  // que no habilita la baja. Falla cerrado, como todo lo de este módulo.
  if (aviso.noticeSentAt === null) return { tipo: "esperando" };

  const cumpleInactividad = inactivaHace(
    cuenta.lastActiveAt,
    now,
    DELETE_AFTER_MONTHS,
  );
  const avisoMaduro =
    addDays(aviso.noticeSentAt, MIN_NOTICE_AGE_DAYS).getTime() <= now.getTime();

  if (cumpleInactividad && avisoMaduro) {
    return { tipo: "baja", noticeSentAt: aviso.noticeSentAt };
  }
  return { tipo: "esperando" };
}

/**
 * Encola el aviso y registra que se mandó. En ese orden, y no es intercambiable.
 *
 * Si se registrara primero y el mail fallara, quedaría una cuenta habilitada
 * para la baja a los 36 meses SIN aviso previo real — exactamente lo que la
 * regla del encabezado prohíbe. Al revés el peor caso es un aviso de más, que
 * cuesta un mail.
 *
 * `enqueueMail` devuelve `null` tanto si el mail ya estaba encolado como si la
 * escritura falló, y no distingue los dos casos. Se trata a los dos igual —no
 * se registra— porque la rama que importa es la segunda. El costo es que un
 * reintento DENTRO del mismo mes calendario no registra (el scope de dedupe es
 * `yyyyMM`) y la cuenta espera al mes siguiente. Un aviso demorado un mes es
 * barato; una baja sin aviso, no.
 */
async function avisar(
  app: App,
  cuenta: AccountActivity,
  now: Date,
): Promise<boolean> {
  const proyectada = proyeccionDeBaja(cuenta.lastActiveAt, now);
  const queueId = await enqueueMail(app, {
    toUid: cuenta.uid,
    kind: "inactive-account-notice",
    scope: mesDeDedupe(now),
    params: { deleteOnLabel: formatShortDateAR(proyectada) },
    // SIN `prefKey` a propósito: es un aviso legal sobre la vida de la cuenta,
    // no una notificación de producto. No debe poder apagarse desde las
    // preferencias. Misma categoría que `payment-overdue`.
  });

  if (queueId === null) {
    logger.warn("sweepInactiveAccounts: no se encoló el aviso, no se registra", {
      uid: cuenta.uid,
    });
    return false;
  }

  await getFirestore(app)
    .collection(RETENTION_NOTICES_COLLECTION)
    .doc(cuenta.uid)
    .set({
      noticeSentAt: FieldValue.serverTimestamp(),
      // La señal al momento del aviso, congelada. Es lo que permite auditar
      // después por qué esta cuenta recibió el aviso este día y no otro.
      lastSeenAt: Timestamp.fromDate(cuenta.lastActiveAt),
    });
  return true;
}

/**
 * Ejecuta la baja.
 *
 * `deletedAt` se escribe ANTES de la cascada, no después, y esto es deliberado:
 * el paso 9 de `runDeleteAccount` borra `retention_notices/{uid}` con el resto
 * de los datos del usuario. Escribirlo después RESUCITARÍA un documento con el
 * uid de alguien que acaba de ser borrado — datos personales que la cascada
 * acababa de sacar. La auditoría de la baja ya vive en `audit_log/{uid}`, que
 * se retiene a propósito y lleva [RETENTION_SWEEP_PROVIDER] para distinguirla.
 *
 * Lo que sí gana el orden: si la cascada muere antes del paso 9, el documento
 * sobrevive CON `deletedAt` y la próxima corrida ve que esta cuenta ya entró en
 * baja en vez de volver a avisarle.
 */
async function darDeBaja(
  app: App,
  uid: string,
  deleteAccount: NonNullable<SweepInactiveOptions["deleteAccount"]>,
): Promise<void> {
  await getFirestore(app)
    .collection(RETENTION_NOTICES_COLLECTION)
    .doc(uid)
    .set({ deletedAt: FieldValue.serverTimestamp() }, { merge: true });
  await deleteAccount(app, uid, RETENTION_SWEEP_PROVIDER);
}

/** `listUsers` paginado, traducido a la señal de actividad. */
async function* listarCuentasDeAuth(app: App): AsyncIterable<AccountActivity> {
  const auth = getAuth(app);
  let pageToken: string | undefined;
  do {
    const page = await auth.listUsers(LIST_USERS_PAGE_SIZE, pageToken);
    for (const user of page.users) {
      const lastActiveAt = resolveLastActiveAt(user.metadata);
      // Sin señal no se puede afirmar inactividad. No se toca.
      if (lastActiveAt === null) continue;
      yield { uid: user.uid, lastActiveAt };
    }
    pageToken = page.pageToken;
  } while (pageToken);
}

/**
 * El barrido. Toda la lógica de negocio vive acá, fuera del arnés de
 * `onSchedule`, para poder testearla — mismo molde que
 * `sweepAthletePaywallHandler`.
 */
export async function sweepInactiveAccountsHandler(
  app: App,
  opts: SweepInactiveOptions = {},
): Promise<SweepInactiveResult> {
  const dryRun = opts.dryRun ?? true;
  const maxPerRun = opts.maxPerRun ?? DEFAULT_MAX_PER_RUN;
  const now = opts.now ?? new Date();
  const listAccounts = opts.listAccounts ?? listarCuentasDeAuth;
  const deleteAccount = opts.deleteAccount ?? runDeleteAccount;

  const r: SweepInactiveResult = {
    dryRun,
    scanned: 0,
    inactive: 0,
    noticed: 0,
    deleted: 0,
    excludedTrainers: 0,
    excludedSubscription: 0,
    excludedActiveLink: 0,
    skippedNoUserDoc: 0,
    errors: 0,
    capped: false,
  };

  for await (const cuenta of listAccounts(app)) {
    // El tope se chequea ANTES de contar la cuenta: `scanned` tiene que decir
    // cuántas se miraron de verdad. Contar la que corto la corrida deja un
    // número que no cuadra con la suma de las demás, y un contador que no
    // cuadra hace dudar del resto del log.
    if (r.noticed + r.deleted >= maxPerRun) {
      r.capped = true;
      break;
    }
    r.scanned++;

    let decision: Decision;
    try {
      decision = await evaluarCuenta(app, cuenta, now);
    } catch (err) {
      // Una cuenta con datos raros no puede frenar el barrido de las demás.
      r.errors++;
      logger.error("sweepInactiveAccounts: error evaluando una cuenta", {
        uid: cuenta.uid,
        err,
      });
      continue;
    }

    switch (decision.tipo) {
    case "activa":
    case "esperando":
      continue;

    case "sin-doc":
      r.skippedNoUserDoc++;
      continue;

    case "excluida":
      r.inactive++;
      if (decision.motivo === "trainer") {
        r.excludedTrainers++;
        // El ÚNICO caso que se loguea por cuenta. El spec §4.5 pide revisión
        // manual de los entrenadores inactivos, y una revisión manual sobre un
        // contador agregado no se puede hacer: hace falta el uid.
        logger.info("sweepInactiveAccounts: entrenador inactivo, revisión manual", {
          uid: cuenta.uid,
          lastActiveAt: cuenta.lastActiveAt.toISOString(),
        });
      } else if (decision.motivo === "subscription") {
        r.excludedSubscription++;
      } else {
        r.excludedActiveLink++;
      }
      continue;

    case "aviso":
      r.inactive++;
      if (dryRun) {
        r.noticed++;
        logger.info("sweepInactiveAccounts: [dryRun] avisaría", {
          uid: cuenta.uid,
          lastActiveAt: cuenta.lastActiveAt.toISOString(),
        });
        continue;
      }
      try {
        if (await avisar(app, cuenta, now)) r.noticed++;
      } catch (err) {
        r.errors++;
        logger.error("sweepInactiveAccounts: error avisando", {
          uid: cuenta.uid,
          err,
        });
      }
      continue;

    case "baja":
      r.inactive++;
      if (dryRun) {
        r.deleted++;
        logger.info("sweepInactiveAccounts: [dryRun] daría de baja", {
          uid: cuenta.uid,
          lastActiveAt: cuenta.lastActiveAt.toISOString(),
          noticeSentAt: decision.noticeSentAt.toISOString(),
        });
        continue;
      }
      try {
        await darDeBaja(app, cuenta.uid, deleteAccount);
        r.deleted++;
        logger.info("sweepInactiveAccounts: cuenta dada de baja", {
          uid: cuenta.uid,
        });
      } catch (err) {
        r.errors++;
        logger.error("sweepInactiveAccounts: error dando de baja", {
          uid: cuenta.uid,
          err,
        });
      }
      continue;
    }
  }

  return r;
}

/**
 * El interruptor del barrido.
 *
 * Arranca en `true` y así se despliega: la primera corrida en producción NO
 * escribe nada, deja el conteo del backlog en el log, y se lee ANTES de
 * apagarlo (spec §4.6). Prenderlo de verdad es cambiar este valor a `false` y
 * redeployar — un cambio de una línea que alguien tiene que hacer a propósito.
 */
export const RETENTION_SWEEP_DRY_RUN = true;

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

export const sweepInactiveAccounts = onSchedule(
  {
    // 05:00 ART: después de `reconcileMpSubscriptions` (03:00),
    // `sweepEntitlements` (04:00) y `sweepAthletePaywall` (04:30). Importa el
    // orden, no sólo la separación de logs: la exclusión por suscripción lee
    // `athleteSubscription`, y correr después de que los otros reconcilien
    // evita decidir una baja sobre un estado de cobro de ayer.
    schedule: "0 5 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
  },
  async () => {
    const r = await sweepInactiveAccountsHandler(ensureApp(), {
      dryRun: RETENTION_SWEEP_DRY_RUN,
    });
    logger.info("sweepInactiveAccounts: corrida diaria", r);
  },
);

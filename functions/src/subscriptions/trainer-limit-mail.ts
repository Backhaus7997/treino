/**
 * trainer-limit-mail.ts — el mail al PF que chocó un tope de su plan:
 * ejercicios propios (limite-ejercicios-pf.md, §3 PR4), plantillas
 * (limite-plantillas-pf.md, §3 PR4), o alumnos (el tope que aplica
 * `syncTrainerLoad` en `promote-link.ts` al aceptar o reanudar un vínculo).
 *
 * GENERALIZADO POR `kind`: cada tope tiene su propia clave de lectura del
 * límite/uso vigente y su propio `MailKind`, todo en `CAMPOS_POR_KIND` más
 * abajo. El resto del módulo —las cinco cláusulas, la ventana, el
 * enfriamiento— es idéntico para los tres, porque son la MISMA pregunta
 * ("¿sigue en el tope, y hace cuánto que no le avisamos POR ESTE TOPE?")
 * sobre datos distintos.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUE HACE FALTA UN MAIL
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * El PF que choca el tope desde el teléfono no tiene forma de enterarse ahí de
 * dónde se paga: el móvil sólo informa el ESTADO (E8 del plan), sin botón, sin
 * "web", sin "pasá a un plan" — mismo criterio que sostiene
 * `plan_limit_paywall.dart` desde el #1141. Sin este mail, ese funnel no tiene
 * por dónde salir. En la web el aviso SÍ lleva botón, así que este mail no es
 * el ÚNICO canal para todos, pero sí lo es para quien entró por el teléfono.
 *
 * Calcado de `free-limit-mail.ts` (#1149): estructura, horario relativo,
 * ventana de 36 horas y enfriamiento de 14 días. Difiere en UNA cosa: la
 * cláusula 3 no depende de una query aparte ("¿ya paga?") sino de los MISMOS
 * datos que ya lee la regla o el gate equivalente para cada tope —
 * `planLimits.<clave>` y `<campo de uso>.count` para ejercicios/plantillas, el
 * límite efectivo de `effective-limit.ts` y `weightedLoad` para alumnos, ver
 * `CAMPOS_POR_KIND`— así que la decisión entera es pura sobre el documento de
 * `users/{uid}`, sin una segunda lectura.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  LAS CLAUSULAS DEL SILENCIO (idénticas en espíritu a free-limit-mail)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   1. **Sin anotación → silencio.** `trainerLimitHitAt` no existe: el PF
 *      nunca chocó el tope, o el cliente/servidor todavía no lo anotó.
 *
 *   2. **Anotación vieja → silencio.** El mail vale porque llega CERCA del
 *      intento (ventana de 36 h, igual razón que en `free-limit-mail.ts`).
 *
 *   3. **Ya no está en el tope → silencio.** `count < limit`, o el límite del
 *      tope que chocó es `null`/ausente (sin tope, interruptor apagado, o el
 *      PF subió de plan y el barrido/la transacción ya lo reflejó).
 *      Escribirle "hay una salida" a quien ya la tiene es el mismo error caro
 *      que documenta `free-limit-mail.ts`.
 *
 *   4. **Suscripción inactiva → silencio.** Sumada por el hallazgo de Codex
 *      sobre #1267 (P1): `pending`/`paused`, o `cancelled` ya vencida —
 *      MISMO criterio que resuelve el límite efectivo a Free en
 *      `effective-limit.ts` (`suscripcionInactiva`). Ofrecer "un plan más
 *      grande" a quien ya pagó uno y sólo tiene el cobro atrasado es la
 *      misma mentira de producto que la cláusula 3 evita para quien ya no
 *      está en el tope. Ver `decideTrainerLimitMail` para qué mail SÍ cubre
 *      ese caso (y para lo que NO cubre ninguno).
 *
 *   5. **Enfriamiento de 14 días → silencio.** Un PF que sigue en el tope
 *      todos los días —porque no quiere pagar más, no porque no se dio
 *      cuenta— recibiría un mail diario sobre lo mismo sin esto.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  EL prefKey
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Este mail LE OFRECE un plan más caro a alguien que ya es cliente — es
 * comunicación comercial, no un aviso operativo. Mismo razonamiento textual
 * que `athlete-prospect-mail.ts` §"EL prefKey, Y POR QUE ESTE MAIL SI LO
 * LLEVA": `docs/legal/politica-de-privacidad.md` promete que para esas «la
 * oposición es ABSOLUTA». Reusa el MISMO valor de clave que
 * `ATHLETE_PROSPECT_PREF_KEY` ("novedades_plan") en vez de definir uno nuevo:
 * es la misma categoría de mensaje —novedades sobre el plan propio— y la
 * clave no está namespaceada por rol en ningún otro lugar del repo (el campo
 * vive en `notificationPrefs`, un mapa plano en `users/{uid}` que ya es
 * exclusivo de UN documento con UN rol). Compartir el string no puede generar
 * una colisión entre dos personas, y sí evita que el día que un `athlete` se
 * promueva a `trainer` (aprovisionamiento manual, ver comentario de
 * `firestore.rules` sobre `subscription`) pierda una preferencia que ya
 * había fijado sobre el mismo tipo de contenido.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  DOS CAMINOS: AL TOQUE, Y EL BARRIDO DE LAS 05:30 COMO RED
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Calcado de `free-limit-mail.ts` (#1149, y el trigger del 2026-09-25): el
 * camino principal es `sendTrainerLimitMailOnHit`, un trigger sobre
 * `users/{uid}` que encola apenas el cliente o el servidor anota
 * `trainerLimitHitAt`. El mail sale en segundos, mientras el PF todavía tiene
 * la pantalla del tope delante.
 *
 * **`sweepTrainerLimitMail` se queda, como red.** Si el trigger falla, el
 * barrido lo reintenta al otro día dentro de la ventana de 36 h. Los dos
 * caminos no se pisan y no pueden producir un mail doble PARA EL MISMO KIND:
 * comparten el enfriamiento de 14 días de ESE kind (`trainerLimitMailAt.<kind>`,
 * cláusula 5), y ESA clave es lo único que impide el doble mail — no la
 * dedupe de la cola, que dedupea por `kind` + `scope` + destinatario y con
 * kinds distintos no ve nada en común.
 *
 * ── POR QUÉ EL ENFRIAMIENTO ES POR KIND, Y NO COMPARTIDO ──
 *
 * Versión anterior de este módulo (#1258, #1264): un único `trainerLimitMailAt`
 * (un Timestamp suelto) compartido entre TODOS los topes, a propósito — la
 * intención declarada era "un PF que choca los dos topes recibe un solo mail
 * cada 14 días, no uno por tope". El dueño del producto pidió lo contrario:
 * cada restricción tiene que mandar su propio mail — chocar el tope de
 * ejercicios no puede silenciar el aviso de plantillas o de alumnos, que son
 * problemas de producto distintos con su propio "plan más grande" que
 * resuelve cada uno. Por eso `trainerLimitMailAt` pasó de un Timestamp suelto
 * a un MAPA `{customExercises?, templates?, students?}`: cada `kind` lee y
 * reserva SÓLO su propia clave.
 *
 * **Compatibilidad con el legado.** Ya hay `trainerLimitMailAt` en producción
 * con la forma vieja (un Timestamp suelto). Hasta acá este comentario decía
 * que `leerEnfriamiento` lo trataba como el enfriamiento de `customExercises`
 * —"el único kind que existía cuando ese campo se escribió así"— y eso era
 * FALSO (hallazgo de Codex, P2, sobre #1267): en `43888a21` (PR4, el commit
 * que generalizó este mail por `kind` y sumó `templates`) el campo YA se
 * escribía y leía como un escalar COMPARTIDO entre `customExercises` Y
 * `templates` — `enqueueTrainerLimitMail` hacía
 * `tx.set(ref, { [CAMPO_MAIL_AT]: Timestamp.fromMillis(nowMs) })` sin mirar
 * `plan.kind` — y siguió compartido así hasta que ESTA rama lo migró a mapa
 * (verificado: `git show 43888a21:functions/src/subscriptions/trainer-limit-mail.ts`).
 * O sea que cualquier `trainerLimitMailAt` legado que exista hoy en
 * producción puede venir de CUALQUIERA de los dos, nunca sólo de ejercicios.
 * `students` es distinto: se agregó (`5dd51e2a`) DESPUÉS de que el
 * enfriamiento ya fuera mapa (`6fed2bc2`), así que nunca escribió el
 * escalar — el legado no le pertenece.
 *
 * `leerEnfriamiento` trata un Timestamp suelto como el enfriamiento de
 * `customExercises` Y de `templates` a la vez —nunca de `students`—, y la
 * primera reserva que toca ese documento —de cualquier kind— lo migra a la
 * forma de mapa (`migrarMapaDeEnfriamiento`), preservando ese valor legado
 * bajo LAS DOS claves que lo compartían.
 *
 * **La carrera entre kinds YA NO es un problema a evitar.** Con el
 * enfriamiento compartido, dos toques casi simultáneos de kinds DISTINTOS
 * necesitaban serializarse para no mandar dos mails — eso es lo que documenta
 * el test "#1264" que sigue viviendo en `trainer-limit-mail.test.ts`, ahora
 * verificando que kinds distintos SÍ manden cada uno el suyo. Lo que la
 * transacción de `reservarEnfriamiento` sigue cerrando es la carrera dentro
 * del MISMO kind: dos toques casi simultáneos del mismo tope no pueden
 * producir dos mails de ese tope, y para eso `enqueueTrainerLimitMail` sigue
 * releyendo `users/{uid}` FRESCO y reservando dentro de una transacción de
 * Firestore, que serializa las que chocan sobre el mismo documento. Si el
 * encolado post-transacción falla de verdad, la reserva de ESE kind se
 * deshace (ver el docstring de `enqueueTrainerLimitMail`) para no dejar un
 * enfriamiento anotado sin mail alguno atrás — sin tocar el enfriamiento de
 * los demás kinds.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  EL KIND (Y EL AT, Y EL INCREMENTO) VIAJAN CON EL EVENTO — NO SE ADIVINAN
 *  DEL DOCUMENTO FRESCO
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Hallazgo de Codex sobre #1267. `reservarEnfriamiento` relee `users/{uid}`
 * FRESCO dentro de una transacción — necesario para que la cláusula 3 (¿sigue
 * en el tope?) y la 4 (enfriamiento) vean el dato más actual. El bug: ANTES
 * de este arreglo, `alTocarElTope` también usaba ESA MISMA relectura para
 * decidir QUÉ KIND evaluar (`userData[CAMPO_TOPE_KIND]`). Si dos toques de
 * KINDS DISTINTOS llegan casi juntos —`customExercises` a t0, `students` a
 * t0+50ms—, para cuando el trigger del PRIMERO hace su relectura, el
 * documento YA puede tener el kind del SEGUNDO. El primer trigger terminaba
 * evaluando el kind equivocado —el de OTRO evento— y el mail de SU PROPIO
 * tope no se mandaba nunca. El test "chocar los dos topes casi al mismo
 * tiempo" (`trainer-limit-mail-al-toque.test.ts`) medía exactamente este bug
 * con la aserción invertida: esperaba UN mail donde correspondían DOS.
 *
 * El arreglo: `alTocarElTope` arma un `EventoTope` con el kind, el `at` y
 * (para `students`) el incremento DEL SNAPSHOT `despues` que lo disparó —
 * antes de que `enqueueTrainerLimitMail` toque Firestore— y se lo pasa a
 * `decideTrainerLimitMail`. Adentro de la transacción, lo único que se sigue
 * releyendo FRESCO es lo que tiene que ser fresco PARA ESE KIND: si sigue en
 * el tope (cláusula 3) y su enfriamiento (cláusula 5). El barrido no tiene
 * evento propio — sigue derivando kind/at/incremento del documento, el más
 * reciente, como siempre.
 *
 * ── EL RIESGO QUE QUEDA ──
 *
 * El barrido de las 05:30 NO tiene esta protección: por diseño sólo ve el
 * ÚLTIMO kind/at/incremento que quedó escrito en el documento — no hay un
 * "evento" que leer ahí, sólo el estado actual. Si el trigger AL TOQUE de un
 * choque falla (la excepción que loguea `sendTrainerLimitMailOnHit` y delega
 * al barrido como red) Y, ANTES de que corra el barrido de mañana, el PF
 * choca un tope DISTINTO —que pisa `trainerLimitHitKind`/`trainerLimitHitAt`
 * con el kind nuevo—, el barrido ya no tiene forma de reconstruir cuál era
 * el kind del choque perdido: el mail del PRIMER tope no sale nunca. Es una
 * doble falla (el trigger Y una carrera contra otro choque distinto) y se
 * acepta así — capturar cada choque individual con su propio evento
 * persistido sería una cola, no un campo en el perfil, y es más estructura
 * de la que este mail comercial justifica. Se deja escrito acá en vez de
 * decir "cubierto" porque no lo está (AGENTS.md §11.1).
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  EL ANTI-LOOP DEL CAMINO AL TOQUE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * `enqueueTrainerLimitMail` escribe `trainerLimitMailAt` en el MISMO documento
 * que dispara el trigger. Esa escritura lo despertaría de nuevo si no se
 * filtrara: `esToqueNuevo` (calcado de `free-limit-mail.ts`) sólo devuelve
 * `true` cuando CAMBIA `trainerLimitHitAt` — la escritura del enfriamiento
 * deja ese campo igual, así que sale sin encolar nada. Cualquier otra
 * escritura del perfil (nombre, foto, preferencias) también sale ahí, sin
 * costo.
 *
 * El chequeo de `role == 'trainer'` es una red de más, en memoria: mismo
 * criterio defensivo que ya usa `barrerLimiteDeEjercicios` para el barrido —
 * `trainerLimitHitAt` sólo lo escribe el flujo del PF, así que en la práctica
 * ya es exclusivo de `trainer`, pero el chequeo no cuesta una query extra.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  EL HORARIO DEL BARRIDO — 05:30 ART
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Después del barrido de las 04:00 (`sweepEntitlements`, que recalcula
 * `planLimits`/`customExerciseUsage` para todo PF) y después de
 * `sweepAthletePaywall`/`sweepFreeLimitMail`, que corren a las 04:30 y 05:00.
 * Ese orden importa por la cláusula 3: correr ANTES del barrido de las 04:00
 * dejaría a este mail decidiendo sobre el `planLimits` de ayer para quien
 * cambió de plan durante la noche. Verificado contra el resto de los
 * schedules del repo (`rg 'schedule:' functions/src`) — no hay otro a las
 * 05:30.
 */

import { App } from "firebase-admin/app";
import {
  DocumentData,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { dedupeKey, enqueueMail } from "../mail/enqueue-mail";
import { MAIL_QUEUE_COLLECTION } from "../mail/types";
import { artDateKey } from "../mail/format";
import { trainerWebCheckout } from "../mail/templates";
import { effectiveWeightLimit, suscripcionInactiva } from "./effective-limit";
import { readTrainerLinks } from "./promote-link";
import { toSubscriptionState } from "./subscription-state";
import { WeightedLink, computeWeightedLoad } from "./weighted-load";

/** El campo que anota el cliente o el servidor al rebotar contra el tope (PR3, plan §2). */
export const CAMPO_TOPE_AT = "trainerLimitHitAt";
/** Qué tope se tocó: `"customExercises"`, `"templates"` o `"students"`. */
export const CAMPO_TOPE_KIND = "trainerLimitHitKind";
/**
 * El incremento que el intento RECHAZADO quería sumarle a `weightedLoad`.
 * Sólo lo escribe `registrarTopeDeAlumnos`, y sólo tiene sentido para el
 * kind `students` — los otros dos kinds nunca lo tocan. Ver `sigueEnElTope`,
 * sección "POR QUÉ `students` NO USA `count >= limit`", para el porqué.
 */
export const CAMPO_TOPE_INCREMENTO = "trainerLimitHitIncrement";
/**
 * El `id` de `trainer_links` que el intento RECHAZADO quería activar. Sólo lo
 * escribe `registrarTopeDeAlumnos`, y sólo tiene sentido para el kind
 * `students` — mismo criterio que `CAMPO_TOPE_INCREMENTO`.
 *
 * Hallazgo de Codex sobre #1267 (P2 de esta ronda). Sin esto, un reintento
 * EXITOSO del mismo accept/resume —el PF liberó lugar y el vínculo que había
 * rebotado ya está `active`— no tiene forma de distinguirse de un vínculo que
 * sigue en un estado intermedio: `sigueEnElTope` sumaba el incremento sobre
 * la carga en vivo SIN saber que ese vínculo específico ya estaba adentro de
 * esa carga, contándolo dos veces. Ver `sigueEnElTope`, sección "EL LINK ID".
 */
export const CAMPO_TOPE_LINK_ID = "trainerLimitHitLinkId";
/**
 * Cuándo se le escribió por última vez, POR KIND. Lo escribe este módulo.
 *
 * Forma nueva: un MAPA `{customExercises?: Timestamp, templates?: Timestamp,
 * students?: Timestamp}` — cada kind reserva y lee SÓLO su propia clave. Ver
 * el encabezado del módulo — "POR QUÉ EL ENFRIAMIENTO ES POR KIND" para el
 * porqué del cambio, y "Compatibilidad con el legado" para el Timestamp
 * suelto que puede seguir viviendo en producción bajo este mismo nombre de
 * campo.
 */
export const CAMPO_MAIL_AT = "trainerLimitMailAt";

/**
 * Qué mirar en `users/{uid}` para cada valor posible de `trainerLimitHitKind`.
 *
 * Un kind que no está acá (ausente, corrupto, o un valor que todavía no
 * existe) NO cae a `customExercises` — revisado por Codex (hilo
 * `01a0d934-760f-7763-9948-ba9bb43fe98a`): con UN solo tope posible,
 * "no sé cuál" y "es el único que existe" eran la misma cosa, pero con más de
 * uno dejaron de serlo. Adivinar `customExercises` para un PF que en realidad
 * chocó `templates` o `students` manda un mail que dice una mentira concreta
 * — "llegaste al tope de EJERCICIOS"—, y es el mismo error que AGENTS.md
 * §11.1 marca como peor que no decir nada. `decideTrainerLimitMail` falla
 * CERRADO (sin mail) para cualquier kind que esta tabla no reconoce.
 */
interface CamposDelTope {
  /**
   * Lee `{limit, count}` del documento FRESCO de `users/{uid}`. `limit`
   * `null` = sin tope (interruptor apagado, plan sin techo, o el PF subió de
   * plan). `trainerId` sólo lo necesita el kind `students` (para
   * `toSubscriptionState`, que lo exige para poder loguear un documento roto
   * con su uid) — los otros dos lo ignoran.
   */
  leerLimiteYUso: (
    userData: DocumentData | undefined,
    trainerId: string,
    nowMs: number,
  ) => { limit: number | null; count: number };
  /** El `MailKind` que corresponde a este tope. */
  mailKind: TrainerLimitMailKind;
}

export type TrainerLimitMailKind =
  | "exercise-limit-reached"
  | "template-limit-reached"
  | "student-limit-reached";

/**
 * Fábrica de `leerLimiteYUso` para los dos topes que leen `planLimits.<clave>`
 * / `<campo de uso>.count` — ejercicios propios y plantillas. Antes eran dos
 * ramas casi idénticas de `sigueEnElTope`; con el kind de alumnos —que lee de
 * un lugar totalmente distinto— la única forma de generalizar sin repetir
 * lógica era subir la LECTURA a `CAMPOS_POR_KIND`, no el nombre de dos campos.
 */
function leerPlanLimitYUso(
  limitField: "customExercises" | "templates",
  usageField: "customExerciseUsage" | "templateUsage",
): CamposDelTope["leerLimiteYUso"] {
  return (userData) => {
    const limitRaw = (userData?.planLimits as Record<string, unknown> | undefined)?.[
      limitField
    ];
    const limit =
      typeof limitRaw === "number" && Number.isFinite(limitRaw) ? limitRaw : null;

    const countRaw = (userData?.[usageField] as { count?: unknown } | undefined)
      ?.count;
    const count = typeof countRaw === "number" && Number.isFinite(countRaw) ? countRaw : 0;

    return { limit, count };
  };
}

/**
 * `leerLimiteYUso` del kind `students` — sólo el LÍMITE. El `count` que pide
 * la firma de `CamposDelTope` (para que los tres kinds compartan una sola
 * interfaz) NO aplica acá y se ignora siempre: ver `sigueEnElTope`, rama
 * `students`, y el porqué en la sección de abajo.
 *
 * El límite sale de la MISMA función que usa el gate del servidor
 * (`effectiveWeightLimit`, `effective-limit.ts`) sobre el MISMO estado de
 * suscripción (`toSubscriptionState`, `subscription-state.ts`) — no una tabla
 * propia que se pueda desincronizar de la que de verdad bloquea.
 *
 * ── POR QUÉ ALUMNOS NO USA `weightedLoad` (y los otros dos kinds sí usan su
 *    equivalente, `<campo de uso>.count`) ──
 *
 * Hallazgo de Codex sobre #1267 (P2). Hasta acá esta función leía
 * `userData.weightedLoad` para el uso — el MISMO campo que `promote-link.ts`
 * documenta, en mayúsculas, que NUNCA es gate input (REQ-PAYWALL-GATE-006):
 * "el gate siempre recomputa en vivo dentro de su propia transacción, nunca
 * confía en este campo". Es un valor de DISPLAY: lo escribe `syncTrainerLoad`
 * en cada promoción/reconciliación, pero `linkLoadReconcile` — el trigger que
 * dispara esa reconciliación cuando el cambio en `trainer_links` no vino del
 * propio gate (pausar, terminar, rechazar) — corre ASÍNCRONO sobre cada
 * escritura de esa colección: hay una ventana entre "el vínculo cambió" y
 * "`weightedLoad` ya lo refleja".
 *
 * Ese desfasaje rompía este mail en el caso exacto que motiva la existencia
 * del reconciliador: `weightedLoad` persistido en 1 (todavía no reconciliado),
 * vínculos en vivo que ya suman 2, el PF intenta sumar un tercero (+1) contra
 * un límite de 2. El GATE (`syncTrainerLoad`) recalcula en vivo dentro de su
 * transacción — 2 (vínculos) + 1 (intento) = 3 > 2 — y rechaza. Este mail,
 * leyendo el `weightedLoad` desactualizado, calculaba 1 (persistido) + 1
 * (intento) = 2, no > 2, y se quedaba mudo justo en el rechazo que se supone
 * que tiene que anunciar.
 *
 * `customExercises`/`templates` NO tienen este problema: su "uso"
 * (`<campo>.count`) lo recalcula EL MISMO barrido/trigger que escribe
 * `planLimits` (`trainer-plan-limits.ts`), sin un segundo campo denormalizado
 * de por medio que pueda quedar atrás — por eso siguen leyendo `userData`
 * fresco sin más, vía `leerPlanLimitYUso`.
 *
 * El arreglo: `sigueEnElTope` (rama `students`) y `reservarEnfriamiento` usan
 * la carga en vivo, calculada DENTRO de la transacción de la reserva con la
 * MISMA función que usa el gate (`computeWeightedLoad`, `weighted-load.ts`)
 * sobre los MISMOS vínculos (`readTrainerLinks`, extraída de `syncTrainerLoad`
 * en `promote-link.ts` para este propósito) — nunca sobre `weightedLoad`.
 */
function leerLimiteDeAlumnos(
  userData: DocumentData | undefined,
  trainerId: string,
  nowMs: number,
): { limit: number | null; count: number } {
  const { state } = toSubscriptionState(userData, trainerId);
  const limit = effectiveWeightLimit(state, nowMs);
  // El `count` de esta firma es de los otros dos kinds — ver el docblock.
  return { limit, count: 0 };
}

const CAMPOS_POR_KIND: Record<string, CamposDelTope> = {
  customExercises: {
    leerLimiteYUso: leerPlanLimitYUso("customExercises", "customExerciseUsage"),
    mailKind: "exercise-limit-reached",
  },
  templates: {
    leerLimiteYUso: leerPlanLimitYUso("templates", "templateUsage"),
    mailKind: "template-limit-reached",
  },
  students: {
    leerLimiteYUso: leerLimiteDeAlumnos,
    mailKind: "student-limit-reached",
  },
};

/** Ver el encabezado — "EL prefKey". Mismo valor que `athlete-prospect-mail.ts`. */
export const TRAINER_LIMIT_PREF_KEY = "novedades_plan";

/** Ventana de la cláusula 2. Misma razón que `free-limit-mail.ts`. */
export const VENTANA_MS = 36 * 60 * 60 * 1000;

/** Enfriamiento de la cláusula 5. Mismo valor y mismo motivo que su hermano. */
export const ENFRIAMIENTO_MS = 14 * 24 * 60 * 60 * 1000;

export interface TrainerLimitMailPlan {
  kind: TrainerLimitMailKind;
  scope: string;
  tope: string;
  /** El tope numérico vigente. Siempre un número: ver `sigueEnElTope`. */
  limit: number;
}

/** Lee un `Timestamp` de Firestore sin confiar en su forma. */
function msDe(valor: unknown): number | null {
  const c = valor as { toMillis?: unknown } | null | undefined;
  if (c == null || typeof c.toMillis !== "function") return null;
  const ms = (c.toMillis as () => number)();
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Lee el enfriamiento de UN kind desde `trainerLimitMailAt`, con
 * compatibilidad para el formato legado.
 *
 * Ver el encabezado del módulo — "Compatibilidad con el legado". Un
 * Timestamp SUELTO (la forma vieja) se lee como el enfriamiento de
 * `customExercises` Y de `templates` — los dos kinds que lo compartían
 * mientras se escribió así (`43888a21`→`6fed2bc2`, verificado en git) — y de
 * NINGÚN otro kind: adivinar para `students` lo bloquearía con un dato que
 * nunca le perteneció (se agregó después de que el enfriamiento ya fuera
 * mapa).
 */
function leerEnfriamiento(mailAt: unknown, kind: string): number | null {
  if (mailAt == null) return null;

  const suelto = msDe(mailAt);
  if (suelto !== null) {
    return kind === "customExercises" || kind === "templates" ? suelto : null;
  }

  if (typeof mailAt !== "object") return null;
  return msDe((mailAt as Record<string, unknown>)[kind]);
}

/**
 * El mapa de enfriamiento COMPLETO, migrado a la forma nueva.
 *
 * Lee lo que haya en `trainerLimitMailAt` —mapa nuevo, Timestamp legado, o
 * nada— y devuelve SIEMPRE un mapa `{kind: Timestamp}` con todas las claves
 * vigentes. El legado se migra acá, preservando su valor bajo LAS DOS claves
 * que lo compartían —`customExercises` y `templates`, ver "Compatibilidad con
 * el legado" en el encabezado—, nunca bajo `students`. Es la pieza que hace
 * que "reescribilo como mapa en la próxima reserva" (ver el encabezado) sea
 * real: cualquier reserva o rollback que pase por acá deja el campo en la
 * forma nueva, sin depender de qué kind disparó la escritura.
 */
function migrarMapaDeEnfriamiento(mailAt: unknown): Record<string, Timestamp> {
  if (mailAt == null) return {};

  const suelto = msDe(mailAt);
  if (suelto !== null) {
    const legado = Timestamp.fromMillis(suelto);
    return { customExercises: legado, templates: legado };
  }

  if (typeof mailAt !== "object") return {};

  const mapa: Record<string, Timestamp> = {};
  for (const [k, v] of Object.entries(mailAt as Record<string, unknown>)) {
    const ms = msDe(v);
    if (ms !== null) mapa[k] = Timestamp.fromMillis(ms);
  }
  return mapa;
}

/** Lee `trainerLimitHitIncrement` validando el tipo. Sólo relevante para `students`. */
function leerIncrementoDeAlumnos(userData: DocumentData | undefined): number | null {
  const raw = userData?.[CAMPO_TOPE_INCREMENTO];
  return typeof raw === "number" && Number.isFinite(raw) ? raw : null;
}

/** Lee `trainerLimitHitLinkId` validando el tipo. Sólo relevante para `students`. */
function leerLinkIdDeAlumnos(userData: DocumentData | undefined): string | null {
  const raw = userData?.[CAMPO_TOPE_LINK_ID];
  return typeof raw === "string" && raw ? raw : null;
}

/**
 * Si el PF SIGUE en el tope ahora mismo — la cláusula 3.
 *
 * Para `customExercises`/`templates`: delega la lectura del límite/uso a
 * `campos.leerLimiteYUso` (`CAMPOS_POR_KIND`). `limit` no numérico (null,
 * ausente, o corrupto) es SIN TOPE — nunca "sigue en el tope". `count <
 * limit` es "ya no está" — `count >= limit` es lo único que mantiene el mail
 * vivo (E6: en el tope exacto SÍ cuenta como "en el tope", porque ahí es
 * donde el próximo intento rebota).
 *
 * `students` es la EXCEPCIÓN, en dos sentidos, y tiene su propia rama:
 *
 * ── 1. NO USA `count >= limit` A SECAS ──
 *
 * Hallazgo de Codex sobre #1267 (P1 de esa ronda). Para los otros dos kinds,
 * `count` es la MISMA cantidad que el gate compara contra el límite (la
 * cuenta de ejercicios/plantillas ya creados). Para `students`, en cambio,
 * lo que el gate de verdad evalúa es `projectedLoad` (`promote-link.ts`): la
 * carga que el intento RECHAZADO hubiera dejado si se aprobaba, no la carga
 * ya aceptada. Un PF con 1 alumno activo + 1 pausado (carga 1,5) que intenta
 * aceptar a un tercero contra un límite de 2 rebota (`projectedLoad` = 2,5 >
 * 2) — pero la carga SOLA (1,5) nunca llega a `>= 2`, así que con el
 * criterio de los otros dos kinds el mail no salía nunca: quedaba ciego a la
 * mitad de los rechazos reales.
 *
 * El arreglo usa la MISMA desigualdad estricta que el gate
 * (`projectedLoad > limit`), reconstruyendo `projectedLoad` como
 * `carga(fresca) + incrementoAlumnos`, donde `incrementoAlumnos` es lo que
 * el intento rechazado quería sumar (`CAMPO_TOPE_INCREMENTO`, anotado por
 * `registrarTopeDeAlumnos` — ver esa función y `incrementoDeAlumnos`).
 * "Fresca" importa: si el PF liberó lugar desde el choque (pausó a alguien),
 * la carga ya lo refleja y el mail no sale de pedo.
 *
 * ── 2. LA "CARGA" NO ES `count` DE `campos.leerLimiteYUso` ──
 *
 * Hallazgo de Codex sobre #1267 (P2 de esta ronda, ver el porqué completo en
 * `leerLimiteDeAlumnos`). Viaja aparte, en `cargaEnVivoDeAlumnos` — calculada
 * por `reservarEnfriamiento` DENTRO de la transacción de la reserva, con la
 * MISMA función que usa el gate (`computeWeightedLoad`) sobre los vínculos
 * EN VIVO, nunca sobre `weightedLoad` persistido. `leerLimiteDeAlumnos`
 * devuelve `count: 0` a propósito — ese valor NUNCA se lee para este kind.
 *
 * `cargaEnVivoDeAlumnos === null` significa "no se pudo calcular" — no
 * debería pasar en producción (`reservarEnfriamiento` siempre la calcula
 * para este kind), pero si pasa, MISMO criterio fail-closed que el resto del
 * archivo: no hay forma confiable de saber si sigue en el tope, así que no
 * manda. Mandar de más es el error caro; mandar de menos, el aceptado.
 *
 * ── SIN INCREMENTO (choque legado, o `details` incompletos) ──
 *
 * Si no hay `trainerLimitHitIncrement` — un choque anotado por una versión
 * vieja de este código (compatibilidad, ver "EL TOPE DE ALUMNOS" más abajo),
 * o el caso defensivo donde `incrementoDeAlumnos` no pudo leer
 * `currentLoad`/`projectedLoad` de los `details` del error—, cae al MISMO
 * criterio que los otros dos kinds: `carga(fresca) >= limit`. Es MENOS
 * preciso (ciego al caso de arriba) pero MÁS conservador: nunca manda de más,
 * sólo puede mandar de menos — y mandar la oferta a quien YA no está en el
 * tope es el error caro que documenta la cláusula 3 del encabezado. Elegido
 * así a propósito, no por default: ver el describe "sin incremento" en
 * `trainer-limit-mail.test.ts`.
 *
 * ── 3. EL LINK ID — NO CONTAR DOS VECES UN VÍNCULO QUE YA SE ACTIVÓ ──
 *
 * Hallazgo de Codex sobre #1267 (P2 de esta ronda). Hasta acá, si después del
 * rechazo el PF liberaba un lugar y reintentaba el MISMO accept/resume CON
 * ÉXITO —antes de que corriera el trigger o el barrido, que puede tardar
 * hasta 36 h—, la carga en vivo YA incluía ese vínculo activo (peso 1.0) y
 * sumarle el incremento (pensado para llevarlo DE pending/paused A activo) lo
 * contaba dos veces: `carga(con el vínculo ya activo) + incremento > limit`
 * disparaba un mail que decía "no se pudo activar ese vínculo" siendo falso.
 *
 * `vinculoAlumnos` —calculado por `reservarEnfriamiento` sobre los MISMOS
 * vínculos en vivo que ya lee para la carga— resuelve esto en dos ramas:
 *
 *   - **El vínculo YA está `active`**: no manda. Ya no hay "un vínculo que no
 *     se pudo activar" — el reintento tuvo éxito, y decir lo contrario es la
 *     misma mentira de producto que la cláusula 3 general evita.
 *   - **No está activo** (sigue pending/paused, o cambió a otra cosa, o no se
 *     encuentra): la proyección es la carga en vivo SIN ESE vínculo más el
 *     incremento — así el peso que ese vínculo aporta HOY (si es que aporta
 *     alguno) nunca se suma dos veces junto con el incremento que ya lo
 *     contempla.
 *
 * `vinculoAlumnos` es `null`/`undefined` en el choque LEGADO (sin
 * `trainerLimitHitLinkId` — anotado antes de este fix, o `reservarEnfriamiento`
 * no lo calculó): cae al comportamiento de ANTES de este fix
 * (`cargaEnVivoDeAlumnos + incrementoAlumnos`), documentado arriba. No hay
 * forma de saber CUÁL vínculo excluir sin el id, así que no se inventa una.
 *
 * ⚠️ **"sin ese vínculo + incremento" no es exacto cuando el vínculo YA
 * pesaba algo (`paused`, 0.5) y SIGUE en ese mismo estado** — no se puede
 * decir "cubierto" sobre esto (AGENTS.md §11.1). El incremento es
 * `1.0 - pesoEnElMomentoDelRechazo`, no el peso completo hacia activo, así
 * que restar el peso ACTUAL (igual al de aquel momento, si nada cambió) y
 * sumar el incremento resta ese peso DOS VECES contra el projectedLoad que
 * recalcularía el gate ahora mismo: sale más bajo, nunca más alto. Mismo
 * signo que el resto del archivo — MENOS preciso, MÁS conservador, nunca
 * manda de más — así que se acepta a propósito: ver el describe "el vínculo
 * sigue paused" en `trainer-limit-mail.test.ts` para el caso concreto donde
 * esto haría que un mail que correspondería no salga.
 *
 * Devuelve el límite ya angosto a `number` para que el productor no tenga que
 * repetir el chequeo de tipo.
 */
function sigueEnElTope(
  userData: DocumentData | undefined,
  trainerId: string,
  nowMs: number,
  campos: CamposDelTope,
  tope: string,
  incrementoAlumnos: number | null,
  cargaEnVivoDeAlumnos: number | null,
  vinculoAlumnos: VinculoDeAlumnos | null,
): number | null {
  const { limit, count } = campos.leerLimiteYUso(userData, trainerId, nowMs);
  if (limit === null) return null;

  if (tope === "students") {
    if (cargaEnVivoDeAlumnos === null) return null; // ver "2." arriba

    if (vinculoAlumnos) {
      if (vinculoAlumnos.activo) return null; // reintento exitoso — ver "3."
      if (incrementoAlumnos !== null) {
        return vinculoAlumnos.cargaSinElVinculo + incrementoAlumnos > limit
          ? limit
          : null;
      }
      return cargaEnVivoDeAlumnos >= limit ? limit : null;
    }

    if (incrementoAlumnos !== null) {
      return cargaEnVivoDeAlumnos + incrementoAlumnos > limit ? limit : null;
    }
    return cargaEnVivoDeAlumnos >= limit ? limit : null;
  }

  return count >= limit ? limit : null;
}

/**
 * El evento puntual que originó ESTE llamado — el snapshot `despues` de UN
 * write sobre `users/{uid}`. Sólo lo arma el camino al toque
 * (`alTocarElTope`, vía `eventoTopeDeSnapshot`); el barrido no tiene un
 * evento propio y pasa `undefined`, así que sigue derivando kind/at/
 * incremento del documento FRESCO, el más reciente — ver el encabezado del
 * módulo, "EL KIND... VIAJAN CON EL EVENTO", incluido "EL RIESGO QUE QUEDA".
 */
interface EventoTope {
  /** `trainerLimitHitKind` de ESTE evento — no el más fresco del documento. */
  kind: string;
  /** `trainerLimitHitAt` de ESTE evento, en ms. */
  atMs: number | null;
  /** `trainerLimitHitIncrement` de ESTE evento. Sólo se usa para `students`. */
  incrementoAlumnos: number | null;
  /** `trainerLimitHitLinkId` de ESTE evento. Sólo se usa para `students`. */
  linkIdAlumnos: string | null;
}

/** Arma el `EventoTope` de un snapshot `despues`. Ver `EventoTope`. */
function eventoTopeDeSnapshot(despues: DocumentData | undefined): EventoTope {
  const kindRaw = despues?.[CAMPO_TOPE_KIND];
  return {
    kind: typeof kindRaw === "string" && kindRaw ? kindRaw : "desconocido",
    atMs: msDe(despues?.[CAMPO_TOPE_AT]),
    incrementoAlumnos: leerIncrementoDeAlumnos(despues),
    linkIdAlumnos: leerLinkIdDeAlumnos(despues),
  };
}

/**
 * El estado DENTRO de la transacción del vínculo puntual que chocó el tope de
 * alumnos — lo que `sigueEnElTope` necesita para no contarlo dos veces. Ver
 * esa función, sección "3. EL LINK ID". Lo arma `reservarEnfriamiento` sobre
 * los vínculos en vivo que ya lee para la carga; `null` cuando no hay
 * `linkId` (choque legado).
 */
export interface VinculoDeAlumnos {
  /** Si el vínculo YA está `active` ahora mismo — un reintento exitoso. */
  activo: boolean;
  /**
   * La carga en vivo, EXCLUYENDO ese vínculo puntual. Si el vínculo no se
   * encuentra más entre los vínculos vivos, es la carga en vivo completa —no
   * hay nada que excluir.
   */
  cargaSinElVinculo: number;
}

/**
 * Si corresponde escribirle a este PF, y con qué alcance de dedupe.
 *
 * Releyendo Firestore fresco (via `reservarEnfriamiento`) para lo que tiene
 * que ser fresco — la cláusula 3 y el enfriamiento — pero SIN adivinar el
 * kind de ese mismo documento fresco cuando hay un `evento` puntual: ver el
 * encabezado del módulo. Sin segunda query — a diferencia de
 * `free-limit-mail.ts`, que necesita `hasActiveTrainerLink`, acá no hay nada
 * más que consultar.
 *
 * `trainerId` es OBLIGATORIO —igual que en `toSubscriptionState`— porque el
 * kind `students` lo necesita para loguear un `subscription` roto con su uid.
 * Los otros dos kinds lo ignoran, pero la firma es una sola: no hay forma de
 * saber DESDE ACÁ qué kind trae `userData` antes de leerlo.
 *
 * @param userData - El documento de `users/{uid}` (FRESCO si viene de la transacción).
 * @param nowMs    - Reloj, inyectado.
 * @param trainerId- El uid del documento que se está leyendo.
 * @param evento   - El kind/at/incremento del evento puntual que disparó este
 *                   llamado (camino al toque). `undefined` en el barrido:
 *                   deriva los tres del documento, el más fresco.
 * @param cargaEnVivoDeAlumnos - SÓLO relevante si el kind es `students`: la
 *                   carga ponderada EN VIVO, calculada por
 *                   `reservarEnfriamiento` con `computeWeightedLoad` sobre los
 *                   vínculos frescos — ver `sigueEnElTope` y
 *                   `leerLimiteDeAlumnos` para el porqué de no usar
 *                   `weightedLoad`. Ignorado para los otros dos kinds.
 * @param vinculoAlumnos - SÓLO relevante si el kind es `students`: el estado
 *                   EN VIVO del vínculo puntual que chocó el tope (por
 *                   `trainerLimitHitLinkId`) — ver `sigueEnElTope`, sección
 *                   "3. EL LINK ID", y `VinculoDeAlumnos`. `null`/`undefined`
 *                   en el choque legado, sin id. Ignorado para los otros dos
 *                   kinds.
 */
export function decideTrainerLimitMail(
  userData: DocumentData | undefined,
  nowMs: number,
  trainerId: string,
  evento?: EventoTope,
  cargaEnVivoDeAlumnos?: number,
  vinculoAlumnos?: VinculoDeAlumnos | null,
): TrainerLimitMailPlan | null {
  const tocadoMs = evento ? evento.atMs : msDe(userData?.[CAMPO_TOPE_AT]);
  if (tocadoMs === null) return null; // clausula 1

  // El mail vale porque llega CERCA del intento. Ver la clausula 2.
  if (nowMs - tocadoMs > VENTANA_MS) return null;

  const topeRaw = evento ? evento.kind : userData?.[CAMPO_TOPE_KIND];
  const tope = typeof topeRaw === "string" && topeRaw ? topeRaw : "desconocido";
  const campos = CAMPOS_POR_KIND[tope];
  if (!campos) return null; // kind sin reconocer: no sabemos que tope mirar

  // Sólo `students` usa un incremento — para los otros dos kinds queda en
  // `null` a propósito, aunque el documento tuviera uno colgado de un choque
  // de alumnos anterior: `sigueEnElTope` no lo mira si el kind no es ese.
  const incrementoAlumnos =
    tope === "students"
      ? evento
        ? evento.incrementoAlumnos
        : leerIncrementoDeAlumnos(userData)
      : null;

  const limit = sigueEnElTope(
    userData,
    trainerId,
    nowMs,
    campos,
    tope,
    incrementoAlumnos,
    tope === "students" ? cargaEnVivoDeAlumnos ?? null : null,
    tope === "students" ? vinculoAlumnos ?? null : null,
  );
  if (limit === null) return null; // clausula 3

  // CLAUSULA NUEVA — SUSCRIPCIÓN INACTIVA. Hallazgo de Codex sobre #1267 (P1).
  //
  // Antes de esto, un PF con la suscripción `pending`/`paused`, o `cancelled`
  // y ya vencida, que chocaba un tope recibía el mismo mail de upsell que
  // cualquier otro — "VER LOS PLANES", ofreciendo un plan más grande. Para
  // ESE PF es una mentira de producto: no le falta plan, le falta pago al
  // día. Un plan3 pausado no tiene "plan más grande" que ofrecerle.
  //
  // `suscripcionInactiva` (`effective-limit.ts`) compara el tier EFECTIVO
  // (`effectiveTier`, que incluye el PISO PREPAGO) contra el tier NOMINAL de
  // la suscripción: "inactiva" es que el efectivo cayó por DEBAJO del
  // nominal. Un PF `pending`/`paused` con un piso prepago vigente del MISMO
  // plan sigue sostenido en su plan pago y NO es "inactiva" — el upsell le
  // sale, porque puede chocar (legítimamente) el tope de ESE plan. Hallazgo
  // de Codex sobre #1267 (P2 de esta ronda) — ver el docblock de
  // `suscripcionInactiva` para el porqué completo.
  // Aplica a LOS TRES kinds: un ejercicio o una plantilla de más también
  // pueden chocarse con el límite ya degradado a Free por la misma causa.
  //
  // `sub === null` (nunca se suscribió) NO entra acá — ver el porqué en
  // `suscripcionInactiva`: ese PF SÍ es el destinatario del upsell.
  //
  // ── QUÉ MAIL CUBRE, EN CAMBIO, "REGULARIZÁ TU PAGO" ──
  //
  // `subscription-downgraded`/`subscription-grace` (`subscription-mail.ts`,
  // disparados por `syncEntitlementsOnSubscription` en el INSTANTE de la
  // transición a `pending`/`paused`, o por `sweepEntitlements` dentro de la
  // ventana de 48h del vencimiento de un `cancelled` — `entitlement-triggers.ts`).
  // Esos SÍ dicen "actualizá tu método de pago"/"tu suscripción se pausó".
  //
  // OJO, esto NO es cobertura total y se deja escrito en vez de decir
  // "cubierto" (AGENTS.md §11.1): esos mails salen por TRANSICIÓN u
  // vencimiento reciente, una vez. Si el PF sigue inactivo semanas después y
  // recién ahí choca un tope, no hay ningún mail de ESTE módulo ni de
  // `subscription-mail.ts` que se lo recuerde en ese momento — silencio total
  // de este canal hasta que regularice. Aceptado así: inventar un recordatorio
  // periódico de cobro es un mail nuevo, no un fix de éste.
  // Y si `subscription` no se puede leer (`degraded`: un valor que no es
  // mapa, un tier desconocido), no se sabe si el PF paga: `state` puede venir
  // `null` y parecer un Free cualquiera. Mismo criterio que el mapper
  // (`subscription-state.ts`): sobre un estado pago ilegible no se manda un
  // mensaje de tope de plan. Falla cerrado, antes de encolar.
  const suscripcion = toSubscriptionState(userData, trainerId);
  if (suscripcion.degraded) return null; // clausula 4, ilegible
  if (suscripcionInactiva(suscripcion.state, nowMs)) {
    return null; // clausula 4
  }

  // EL ENFRIAMIENTO, POR KIND. Ver la clausula 5: sin esto, un PF que sigue
  // en el tope todos los dias recibe un mail diario sobre lo mismo — y con el
  // enfriamiento compartido de antes, chocar OTRO tope silenciaba el mail de
  // este, que es justo lo que se dejó de querer (ver el encabezado).
  const ultimoMs = leerEnfriamiento(userData?.[CAMPO_MAIL_AT], tope);
  if (ultimoMs !== null && nowMs - ultimoMs < ENFRIAMIENTO_MS) return null;

  return {
    kind: campos.mailKind,
    scope: `tope_${tope}_${artDateKey(nowMs)}`,
    tope,
    limit,
  };
}

/** Lo que devuelve la reserva: el plan a mandar y el enfriamiento previo (de ESE kind). */
interface Reserva {
  plan: TrainerLimitMailPlan;
  /** `trainerLimitMailAt.<kind>` ANTES de esta reserva. `null` si no había. */
  anteriorMailAtMs: number | null;
}

/**
 * Relee `users/{uid}` FRESCO dentro de una transacción, decide, y si
 * corresponde mandar, RESERVA el enfriamiento de ESE kind ahí mismo (escribe
 * `trainerLimitMailAt.<kind> = nowMs`, migrando el resto del mapa a la forma
 * nueva de paso) antes de que nadie encole nada.
 *
 * Esta es la pieza que cierra la carrera DENTRO del mismo kind (ver el
 * encabezado del módulo): dos transacciones sobre el MISMO documento se
 * serializan, así que la segunda de las dos siempre ve la reserva que dejó la
 * primera y sale por la cláusula 5 (`decideTrainerLimitMail` devuelve `null`),
 * sin importar qué snapshot tenía el llamador al entrar.
 *
 * Devuelve `null` cuando `decideTrainerLimitMail` dice que no corresponde —
 * ninguna de las cinco cláusulas se cumple, o esta transacción perdió la
 * carrera contra otra del MISMO kind.
 *
 * `evento`, si viene (camino al toque), fija el kind/at/incremento a evaluar
 * — ver `EventoTope` y el encabezado del módulo. `datosFrescos` se sigue
 * releyendo siempre: es lo que `decideTrainerLimitMail` usa para la
 * cláusula 3 y el enfriamiento de ESE kind.
 *
 * Para `students`, ADEMÁS lee los vínculos vivos del PF y calcula su carga
 * ponderada EN VIVO, DENTRO de esta misma transacción — ver
 * `leerLimiteDeAlumnos` y `sigueEnElTope` para el porqué (hallazgo de Codex
 * sobre #1267, P2: `weightedLoad` persistido puede estar desactualizado
 * mientras `linkLoadReconcile` todavía no corrió). El kind se mira ACÁ, antes
 * de llamar a la función pura, únicamente para decidir SI hace falta esa
 * query — para los otros dos kinds sería una lectura a Firestore de más.
 *
 * Sobre esos MISMOS vínculos —sin una segunda query— arma además
 * `vinculoAlumnos`: busca el `trainerLimitHitLinkId` del evento (o del
 * documento fresco, si no hay evento) entre los vínculos vivos, para que
 * `sigueEnElTope` sepa si ESE vínculo puntual ya está `active` (reintento
 * exitoso, no manda) o cuál es la carga en vivo sin él (hallazgo de Codex
 * sobre #1267, P2 de esta ronda — ver `sigueEnElTope`, sección "3. EL LINK
 * ID"). `null` cuando no hay `linkId` (choque legado).
 */
async function reservarEnfriamiento(
  app: App,
  trainerId: string,
  nowMs: number,
  evento?: EventoTope,
): Promise<Reserva | null> {
  const db = getFirestore(app);
  const ref = db.collection("users").doc(trainerId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const datosFrescos = snap.data();

    // Mismo criterio que dentro de `decideTrainerLimitMail` para elegir el
    // kind (evento primero, documento fresco si no hay evento) — replicado
    // acá porque hace falta ANTES de llamar a esa función pura, para saber si
    // corresponde la query de vínculos. `decideTrainerLimitMail` vuelve a
    // hacer el mismo cálculo; es una comparación de strings, no una lectura.
    const topeDeEsteLlamado = evento ? evento.kind : datosFrescos?.[CAMPO_TOPE_KIND];
    let cargaEnVivoDeAlumnos: number | undefined;
    let vinculoAlumnos: VinculoDeAlumnos | null = null;
    if (topeDeEsteLlamado === "students") {
      const links = (await readTrainerLinks(tx, db, trainerId)) as unknown as
        (WeightedLink & { id: string })[];
      cargaEnVivoDeAlumnos = computeWeightedLoad(links);

      // Ver el docblock de esta función — "vinculoAlumnos" — y `sigueEnElTope`,
      // sección "3. EL LINK ID". Sin `linkId` (choque legado) queda `null`.
      const linkId = evento ? evento.linkIdAlumnos : leerLinkIdDeAlumnos(datosFrescos);
      if (linkId !== null) {
        const vinculo = links.find((l) => l.id === linkId);
        vinculoAlumnos = {
          activo: vinculo?.status === "active",
          cargaSinElVinculo: computeWeightedLoad(
            links.filter((l) => l.id !== linkId),
          ),
        };
      }
    }

    const plan = decideTrainerLimitMail(
      datosFrescos,
      nowMs,
      trainerId,
      evento,
      cargaEnVivoDeAlumnos,
      vinculoAlumnos,
    );
    if (!plan) return null;

    const mailAtActual = datosFrescos?.[CAMPO_MAIL_AT];
    const anteriorMailAtMs = leerEnfriamiento(mailAtActual, plan.tope);

    const mapaMigrado = migrarMapaDeEnfriamiento(mailAtActual);
    mapaMigrado[plan.tope] = Timestamp.fromMillis(nowMs);
    tx.set(ref, { [CAMPO_MAIL_AT]: mapaMigrado }, { merge: true });

    return { plan, anteriorMailAtMs };
  });
}

/**
 * Deshace una reserva que quedó sin mail detrás (el encolado falló de
 * verdad). Vuelve `trainerLimitMailAt.<kind>` a `anteriorMailAtMs` (o borra
 * esa clave si no había ninguno) — PERO sólo si esa clave sigue valiendo
 * exactamente `nowMs`, es decir, sólo si sigue siendo ESTA reserva. Si otra
 * transacción posterior ya volvió a chocar el mismo tope y reservó de nuevo,
 * `trainerLimitMailAt.<kind>` ya no es `nowMs` y este rollback no toca nada
 * —ni esa clave ni las demás— pisar esa reserva más nueva silenciaría un
 * mail que sí va a salir.
 *
 * Las claves de los OTROS kinds nunca se tocan: el rollback de un kind no
 * puede revivir el enfriamiento de otro.
 */
async function deshacerReserva(
  app: App,
  trainerId: string,
  kind: string,
  nowMs: number,
  anteriorMailAtMs: number | null,
): Promise<void> {
  const ref = getFirestore(app).collection("users").doc(trainerId);
  await getFirestore(app).runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const mailAtActual = snap.data()?.[CAMPO_MAIL_AT];
    const actualMs = leerEnfriamiento(mailAtActual, kind);
    if (actualMs !== nowMs) return; // ya no es esta reserva, no tocar

    const mapa = migrarMapaDeEnfriamiento(mailAtActual);
    if (anteriorMailAtMs === null) {
      delete mapa[kind];
    } else {
      mapa[kind] = Timestamp.fromMillis(anteriorMailAtMs);
    }
    tx.set(ref, { [CAMPO_MAIL_AT]: mapa }, { merge: true });
  });
}

/**
 * El camino común del trigger y del barrido: decide, reserva, encola, y
 * deshace la reserva si el encolado falló de verdad.
 *
 * ORDEN (invertido respecto de una versión anterior de este módulo, que
 * anotaba el enfriamiento DESPUÉS de encolar — ver "DOS CAMINOS" en el
 * encabezado para el porqué):
 *
 *   1. `reservarEnfriamiento` relee el documento FRESCO dentro de una
 *      transacción, decide con `decideTrainerLimitMail`, y si corresponde
 *      mandar, escribe `trainerLimitMailAt.<kind> = nowMs` ahí mismo — la
 *      reserva. Si no corresponde (cualquiera de las cinco cláusulas,
 *      incluyendo haber perdido la carrera contra otra reserva del MISMO
 *      kind), no hay nada más que hacer.
 *   2. Con la reserva ya firme, se encola con `enqueueMail`. Nunca tira:
 *      devuelve `null` tanto si el mail YA estaba en la cola (reintento del
 *      barrido, sano) como si la escritura FALLÓ. Ante un `null`, se mira la
 *      cola: si el documento está, todo bien — la reserva queda como está.
 *   3. Si el documento NO está (el encolado falló de verdad), la reserva
 *      quedó sin mail detrás: `deshacerReserva` la revierte —para que el
 *      próximo choque de ESE tope no encuentre un enfriamiento anotado sobre
 *      un mail que nunca salió— y se tira, para que el barrido lo cuente
 *      como fallido.
 *
 * Tirar NO garantiza un reintento. El barrido es diario y la ventana es de
 * 36 h, así que la corrida de mañana sólo vuelve a ver los topes que hoy
 * tienen menos de 12 h. Uno más viejo sale de la query y no se reintenta: el
 * mail llega recién si el PF vuelve a chocar un tope. Se aceptó así porque la
 * falla es rara y el mail es comercial.
 *
 * `evento`, si viene, se lo pasa sin tocar a `reservarEnfriamiento` — ver
 * `EventoTope`.
 *
 * @returns el plan que se mandó, o `null` si no correspondía mandar nada.
 */
export async function enqueueTrainerLimitMail(
  app: App,
  trainerId: string,
  nowMs: number,
  evento?: EventoTope,
): Promise<TrainerLimitMailPlan | null> {
  const reserva = await reservarEnfriamiento(app, trainerId, nowMs, evento);
  if (!reserva) return null;
  const { plan, anteriorMailAtMs } = reserva;

  const queuedId = await enqueueMail(app, {
    toUid: trainerId,
    kind: plan.kind,
    scope: plan.scope,
    prefKey: TRAINER_LIMIT_PREF_KEY,
    params: {
      tope: plan.tope,
      limit: plan.limit,
      ctaUrl: trainerWebCheckout(),
    },
  });

  if (queuedId === null) {
    const enCola = await getFirestore(app)
      .collection(MAIL_QUEUE_COLLECTION)
      .doc(dedupeKey(plan.kind, plan.scope, trainerId))
      .get();
    if (!enCola.exists) {
      await deshacerReserva(app, trainerId, plan.tope, nowMs, anteriorMailAtMs);
      throw new Error("trainer-limit-mail: no se pudo encolar el mail");
    }
  }

  return plan;
}

export interface ResultadoDelBarrido {
  candidatos: number;
  enviados: number;
}

/**
 * Le escribe a los PF que chocaron un tope de su plan —ejercicios propios,
 * plantillas o alumnos— y siguen ahí. `enqueueTrainerLimitMail` es quien
 * decide —relee el documento fresco dentro de una transacción— cuál tope
 * mirar según `CAMPO_TOPE_KIND`; acá sólo se filtra por `role` antes de
 * intentarlo.
 *
 * ── La query, y por que trae tan poco ──
 *
 * `trainerLimitHitAt >= hace 36hs`, igual criterio que `free-limit-mail.ts`:
 * el campo sólo existe en quien chocó el tope, y la ventana lo acota a ayer.
 * No hace falta índice compuesto — Firestore indexa cada campo por su cuenta.
 *
 * ── Por que se revisa el rol acá y no en la query ──
 *
 * `trainerLimitHitAt` sólo lo escribe el flujo del PF (`registrarTopeDelPlanPf`
 * para ejercicios/plantillas, `registrarTopeDeAlumnos` para alumnos), así que
 * en la práctica el campo es exclusivo de `trainer`. El chequeo es una red de
 * más, en memoria y sin costo de query extra, por si algún día ese supuesto
 * deja de sostenerse — mismo criterio defensivo que
 * `custom-exercise-count.ts` aplica antes de recontar. Se lee del snapshot de
 * la query, no fresco — es sólo un filtro previo; la decisión que importa
 * (las cinco cláusulas) la hace `enqueueTrainerLimitMail` sobre el documento
 * fresco.
 *
 * ── Un fallo no frena a los demás ──
 *
 * Mismo criterio que `barrerTopesTocados`: un documento raro no puede dejar
 * sin mail a toda la cola.
 */
export async function barrerLimiteDeEjercicios(
  app: App,
  nowMs: number = Date.now(),
  logger: { info: (m: string, d?: unknown) => void; error: (m: string, d?: unknown) => void } = console,
): Promise<ResultadoDelBarrido> {
  const desde = Timestamp.fromMillis(nowMs - VENTANA_MS);
  const snap = await getFirestore(app)
    .collection("users")
    .where(CAMPO_TOPE_AT, ">=", desde)
    .get();

  let enviados = 0;
  for (const doc of snap.docs) {
    try {
      const data = doc.data();
      if (data.role !== "trainer") continue;

      const plan = await enqueueTrainerLimitMail(app, doc.id, nowMs);
      if (plan) enviados++;
    } catch (err) {
      logger.error("trainer-limit-mail: fallo un PF", { uid: doc.id, err });
    }
  }

  return { candidatos: snap.size, enviados };
}

/** Qué hizo el trigger con una escritura de `users/{uid}`. Para el log. */
export type ResultadoAlToque =
  | "sin-tope-nuevo"
  | "no-trainer"
  | "silencio"
  | "encolado";

/**
 * Si esta escritura es un tope NUEVO: `trainerLimitHitAt` aparece o cambia.
 *
 * ⚠️ **Es lo que evita el loop.** `enqueueTrainerLimitMail` escribe
 * `trainerLimitMailAt` en el MISMO documento que dispara el trigger. Esa
 * escritura vuelve a despertarlo, pero deja `trainerLimitHitAt` igual, así
 * que sale acá. Lo mismo con cualquier otra escritura del perfil —nombre,
 * foto, preferencias—, que son la enorme mayoría de las que llegan. Calcado
 * de `esToqueNuevo` en `free-limit-mail.ts`.
 */
export function esToqueNuevo(
  antes: DocumentData | undefined,
  despues: DocumentData | undefined,
): boolean {
  const despuesMs = msDe(despues?.[CAMPO_TOPE_AT]);
  if (despuesMs === null) return false;
  return despuesMs !== msDe(antes?.[CAMPO_TOPE_AT]);
}

/**
 * El camino al toque: las mismas cinco cláusulas que el barrido, para UN PF,
 * en el momento en que choca el tope.
 *
 * El chequeo de `role` va acá y no en la query del trigger (que no existe:
 * `onDocumentUpdated` no filtra por campo) — es la misma red defensiva que
 * `barrerLimiteDeEjercicios` aplica en memoria, sin costo de query extra. Se
 * lee de `despues`, el snapshot que trajo el evento — sólo un filtro previo;
 * la decisión que importa la hace `enqueueTrainerLimitMail` releyendo el
 * documento fresco dentro de una transacción. Ver el encabezado — "EL
 * ANTI-LOOP DEL CAMINO AL TOQUE", "DOS CAMINOS" y "EL KIND... VIAJAN CON EL
 * EVENTO".
 *
 * El `EventoTope` que arma acá —de `despues`, ANTES de tocar Firestore— es
 * lo que le fija a `enqueueTrainerLimitMail` cuál es SU kind: sin esto, dos
 * toques de kinds distintos casi simultáneos pueden hacer que este trigger
 * termine decidiendo sobre el kind que anotó EL OTRO. Ver el encabezado.
 */
export async function alTocarElTope(
  app: App,
  uid: string,
  antes: DocumentData | undefined,
  despues: DocumentData | undefined,
  nowMs: number,
): Promise<ResultadoAlToque> {
  if (!esToqueNuevo(antes, despues)) return "sin-tope-nuevo";
  if (despues?.role !== "trainer") return "no-trainer";

  const plan = await enqueueTrainerLimitMail(app, uid, nowMs, eventoTopeDeSnapshot(despues));
  return plan ? "encolado" : "silencio";
}

/**
 * El mail al toque. Ver «DOS CAMINOS» en el encabezado.
 *
 * `onDocumentUpdated` y no `Written`: la anotación sale de
 * `registrarTopeDelPlanPf` (ejercicios/plantillas) o `registrarTopeDeAlumnos`
 * (alumnos) sobre un `users/{uid}` que ya existe —el PF ya tiene sesión—, así
 * que un alta nunca trae un tope.
 *
 * Un fallo se loguea y no se relanza. Relanzar no reintentaría (el trigger no
 * tiene `retry`), y la red para ese caso ya existe: el barrido de las 05:30.
 */
export const sendTrainerLimitMailOnHit = onDocumentUpdated(
  { document: "users/{uid}", region: "southamerica-east1" },
  async (event) => {
    const antes = event.data?.before?.data();
    const despues = event.data?.after?.data();
    // Filtro barato ANTES de tocar el app: casi todas las escrituras de
    // `users/{uid}` no son un tope.
    if (!esToqueNuevo(antes, despues)) return;

    const { getApp, initializeApp } = await import("firebase-admin/app");
    let app: App;
    try {
      app = getApp();
    } catch {
      app = initializeApp();
    }
    const uid = event.params.uid;
    try {
      const r = await alTocarElTope(app, uid, antes, despues, Date.now());
      logger.info("sendTrainerLimitMailOnHit", { uid, resultado: r });
    } catch (err) {
      logger.error(
        "sendTrainerLimitMailOnHit: falló; lo reintenta el barrido",
        { uid, err },
      );
    }
  },
);

/**
 * 05:30 ART. Ver el encabezado — "EL HORARIO DEL BARRIDO".
 */
export const sweepTrainerLimitMail = onSchedule(
  {
    schedule: "30 5 * * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
  },
  async () => {
    const { getApp, initializeApp } = await import("firebase-admin/app");
    let app: App;
    try {
      app = getApp();
    } catch {
      app = initializeApp();
    }
    const r = await barrerLimiteDeEjercicios(app, Date.now(), logger);
    logger.info("sweepTrainerLimitMail: corrida diaria", r);
  },
);

// ═══════════════════════════════════════════════════════════════════════════
//  EL TOPE DE ALUMNOS — anotación server-side
// ═══════════════════════════════════════════════════════════════════════════
//
// A diferencia de ejercicios/plantillas, acá NO hay un cliente que anote
// `trainerLimitHitAt`: el tope de alumnos se decide 100% en el servidor,
// dentro de `syncTrainerLoad` (`promote-link.ts`), que tira `resource-exhausted`
// cuando aceptar o reanudar un vínculo superaría el límite efectivo. Nadie
// más anota nada — hace falta esta pieza para que `sendTrainerLimitMailOnHit`
// tenga algo que disparar.

/**
 * Si `err` es el `resource-exhausted` que tira `syncTrainerLoad` al chocar el
 * tope de PLAN de alumnos (`promote-link.ts`), y no otro `resource-exhausted`
 * — por ejemplo, una cuota de Firestore agotada, que también usa ese código
 * de error pero no trae el `details.reason` que sólo escribe
 * `promotionDenialReason` (D-2).
 *
 * ── HASTA #1267 LOS DOS `reason` POSIBLES CONTABAN IGUAL ACÁ. YA NO. ──
 *
 * Hallazgo de Codex sobre #1267 (P1). Este comentario decía que
 * `"plan-limit"` y `"subscription-inactive"` eran lo mismo para este mail —
 * "los dos representan que el servidor frenó al PF por el tope" — y eso
 * llevaba al mail EQUIVOCADO: un PF con un plan pago pero la suscripción
 * `pending`/`paused`/vencida (`subscription-inactive`, D-2) recibía el mismo
 * "VER LOS PLANES" que alguien en su tope de verdad, ofreciéndole comprar
 * algo que YA compró. Ver `promotionDenialReason` — `subscription-inactive`
 * es "no llegaste a pagar lo suficiente AHORA", un problema de cobro, no de
 * plan.
 *
 * Ahora SÓLO `"plan-limit"` cuenta como tope de alumnos: la MISMA distinción
 * que ya hace `promotionDenialReason`, no una nueva. `"subscription-inactive"`
 * no anota nada acá — ese caso lo cubre (parcialmente; ver
 * `decideTrainerLimitMail`, cláusula "SUSCRIPCIÓN INACTIVA") el canal de
 * `subscription-mail.ts`, disparado por la transición de `subscription`, no
 * por el intento de aceptar/reanudar un vínculo.
 */
export function esTopeDeAlumnos(err: unknown): boolean {
  if (!(err instanceof HttpsError)) return false;
  if (err.code !== "resource-exhausted") return false;
  const details = err.details as { reason?: unknown } | undefined;
  return details?.reason === "plan-limit";
}

/**
 * El incremento que el intento RECHAZADO quería sumarle a `weightedLoad`:
 * `projectedLoad - currentLoad`, tal como los escribió `syncTrainerLoad` en
 * los `details` del `resource-exhausted` (`promote-link.ts`). `null` si los
 * `details` no traen los dos números como números finitos — no debería pasar
 * en la práctica (`syncTrainerLoad` los escribe juntos, en el mismo throw,
 * siempre que `esTopeDeAlumnos(err)` es cierto: son la MISMA excepción), pero
 * es la misma postura fail-closed que `CAMPOS_POR_KIND` — "un kind sin
 * reconocer no manda": si no se puede leer con confianza, mejor un choque SIN
 * incremento (cae al criterio conservador de `sigueEnElTope`) que inventar un
 * número.
 *
 * Llamalo DESPUÉS de confirmar `esTopeDeAlumnos(err)` — no repite ese chequeo,
 * así que sobre un `err` que no es el tope de alumnos también puede devolver
 * `null` (o, en teoría, un número sin sentido si otro `resource-exhausted`
 * casualmente trae esos mismos nombres de campo) — el llamador ya filtró eso.
 */
export function incrementoDeAlumnos(err: unknown): number | null {
  if (!(err instanceof HttpsError)) return null;
  const details = err.details as
    | { currentLoad?: unknown; projectedLoad?: unknown }
    | undefined;
  const current = details?.currentLoad;
  const projected = details?.projectedLoad;
  if (typeof current !== "number" || !Number.isFinite(current)) return null;
  if (typeof projected !== "number" || !Number.isFinite(projected)) return null;
  return projected - current;
}

/**
 * Anota `trainerLimitHitKind: "students"` + `trainerLimitHitAt` (+ el
 * incremento rechazado y el `linkId` del vínculo, si se pudieron leer) en
 * `users/{trainerId}` cuando una promoción (`acceptTrainerLink` /
 * `resumeTrainerLink`) rebotó contra el tope de alumnos. Esa escritura
 * dispara `sendTrainerLimitMailOnHit`, igual que la anotación de
 * ejercicios/plantillas dispara ese mismo trigger.
 *
 * `incremento`: `projectedLoad - currentLoad` de los `details` del error (ver
 * `incrementoDeAlumnos`) — lo que `sigueEnElTope` necesita para reconstruir
 * `projectedLoad` sin repetir la transacción del gate. `null` cuando no se
 * pudo leer: esta función BORRA la clave (`FieldValue.delete()`) en vez de
 * omitirla, para que un incremento de un choque ANTERIOR nunca sobreviva
 * pegado a un `trainerLimitHitAt` nuevo — `sigueEnElTope` cae entonces al
 * criterio conservador documentado ahí, en vez de leer un número que ya no
 * describe a ESTE choque.
 *
 * `linkId`: el `id` de `trainer_links` que este intento quiso activar —
 * siempre lo tiene el llamador (es el mismo `linkId` que recibió el
 * callable), a diferencia del incremento, que depende de poder leer los
 * `details` del error. MISMO criterio de limpieza: `null` BORRA la clave, por
 * la misma razón — un `linkId` de un choque ANTERIOR pegado a un
 * `trainerLimitHitAt` nuevo haría que `sigueEnElTope` buscara el vínculo
 * EQUIVOCADO. Ver `sigueEnElTope`, sección "3. EL LINK ID" (hallazgo de Codex
 * sobre #1267, P2 de esta ronda).
 *
 * DELIBERADAMENTE simple: una escritura, sin transacción propia y sin
 * catch interno. `syncTrainerLoad` tira DENTRO de su propia transacción
 * (`promote-link.ts`), así que cualquier escritura hecha ahí se revertiría
 * junto con el resto en el momento del throw — por eso esta función corre
 * AFUERA, en el `catch` del callable, DESPUÉS de que esa transacción ya
 * abortó, y sobre su propia escritura sin transacción: no hay nada más con
 * lo que serializarla.
 *
 * El llamador (`acceptTrainerLink` / `resumeTrainerLink`) es quien decide
 * qué hacer si ESTA escritura falla — ver el criterio "best-effort" en esos
 * módulos: perder el mail es aceptable, perder el `resource-exhausted`
 * original que el paywall del cliente necesita parsear no lo es.
 */
export async function registrarTopeDeAlumnos(
  app: App,
  trainerId: string,
  nowMs: number,
  incremento: number | null,
  linkId: string | null,
): Promise<void> {
  await getFirestore(app)
    .collection("users")
    .doc(trainerId)
    .set(
      {
        [CAMPO_TOPE_KIND]: "students",
        [CAMPO_TOPE_AT]: Timestamp.fromMillis(nowMs),
        [CAMPO_TOPE_INCREMENTO]: incremento !== null ? incremento : FieldValue.delete(),
        [CAMPO_TOPE_LINK_ID]: linkId !== null ? linkId : FieldValue.delete(),
      },
      { merge: true },
    );
}

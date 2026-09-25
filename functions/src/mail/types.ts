/**
 * Shared types for the TREINO transactional email outbox.
 *
 * Design:
 *   - The outbox stores WHAT happened (kind + params), never rendered HTML.
 *     Templates are applied at send time by `send-queued-mail`, so a copy fix
 *     never requires re-enqueueing and a queue doc stays far below the 1MB
 *     Firestore limit (a branded HTML email is easily 50-100KB).
 *   - The recipient is stored as a uid, not an address. The address is
 *     resolved from Firebase Auth at SEND time so a user who changes their
 *     email between enqueue and send still receives the mail.
 *
 * See `enqueue-mail.ts` for the idempotency contract.
 */

/** Stable discriminator: selects the template and drives the dedupe key. */
export type MailKind =
  // Auth. Reemplazan las plantillas default de Firebase Auth: el link sigue
  // siendo el que genera el Admin SDK (apunta al action handler que Firebase
  // hostea), lo unico que cambia es quien manda el mail y como se ve.
  | "password-reset"
  // Se manda EN LUGAR de `password-reset` cuando la cuenta no tiene proveedor
  // de contraseña. No lleva `actionLink`: no hay contraseña que restablecer.
  | "federated-signin-hint"
  | "email-verification"
  | "appointment-confirmed"
  | "appointment-series-created"
  | "appointment-cancelled"
  | "appointment-series-cancelled"
  | "link-requested"
  | "link-accepted"
  | "payment-overdue"
  // El unico de estos mails con consecuencia FISICA: el alumno avisa que algo
  // le duele MIENTRAS entrena, y si el PF no tiene la app abierta se entera
  // tarde. Destinatario: el PF. Sin `prefKey` a proposito — ver `templates.ts`.
  | "discomfort-reported"
  // Aviso interno al buzon del equipo cuando entra un reporte. NO va a un
  // usuario: es el unico `kind` que viaja con `toAddress` en vez de `toUid`.
  // Sin el, la cola de revision existe pero nadie la mira, y las 24 horas que
  // promete `docs/legal/normas-de-comunidad.md:123` siguen siendo mentira.
  | "moderation-report-created"
  // Aviso al usuario reportado cuando un moderador resuelve el reporte con
  // "advertido". `resolveReport` guardaba solo la etiqueta y no avisaba a
  // nadie — esto es lo que la hace real.
  //
  // NO lleva el contenido reportado, ni el motivo textual del denunciante,
  // ni nada que lo identifique — mismo criterio que
  // `notify-report-created.ts:9-17`. Sin `prefKey`, como sus hermanos legales
  // (`moderation-report-created`, `payment-overdue`): no es una notificacion
  // de producto que se pueda apagar, es que se reviso contenido de la cuenta
  // y se tomo una medida.
  | "moderation-user-warned"
  // ── Suscripcion del PF a TREINO ─────────────────────────────────────────
  //
  // OJO — NO CONFUNDIR CON `payment-overdue`. Ese va al ATLETA y es sobre la
  // cuota que le paga a SU entrenador. Estos dos van al ENTRENADOR y son sobre
  // lo que EL le paga a TREINO. Son dos sistemas de plata distintos que en
  // castellano se dicen casi igual.
  //
  // Los produce `subscription-mail.ts`, y el criterio de por que existen ESTOS
  // y no otros vive alla; en una linea: el mail existe para llegar cuando el PF
  // NO esta mirando la app.
  //
  // NO son los unicos del paywall. El tercero es `limit-reached`, mas abajo:
  // va por otro disparador porque su destinatario no tiene `subscription` que
  // pueda transicionar.
  //
  // Se cobro mal y hay ventana para arreglarlo. `grace` conserva el limite
  // pagado, asi que NO se bloquea a nadie y NO rebota ninguna escritura: no
  // existe ninguna señal in-app. Este mail es el unico canal que hay.
  | "subscription-grace"
  // El limite efectivo BAJO y ya hay consecuencia. Cubre pausa, cancelacion
  // vencida y bajada de tier — el disparador es el limite, no el status.
  | "subscription-downgraded"
  // ── El PF que NUNCA pago y choco el cupo del plan Free ──────────────────
  //
  // El TERCERO del paywall, y el unico que no habla de una suscripcion que
  // existe: el destinatario no tiene `subscription` en su documento. Por eso
  // NO puede decir "regularizá" ni "poné al dia" — no hay nada atrasado. Dice
  // que llego al tope y que hay planes mas grandes.
  //
  // POR QUE ES UN MAIL Y NO UN CARTEL. Porque el cartel ya no se puede poner.
  // El 2026-09-15 (PR #1141) la app movil dejo de nombrar donde se paga, bajo
  // la Guideline 3.1.3(f) de Apple: un cartel que dice donde se paga YA es un
  // "call to action for purchase outside of the app", tappable o no. Lo que
  // Apple SI permite, y textual, es "send communications outside of the app to
  // their user base about purchasing methods other than in-app purchase".
  //
  // O sea que este mail no es un canal mas: **es el unico canal legal que le
  // queda al PF que entro por el telefono**. Si se saca, ese funnel no tiene
  // por donde salir.
  //
  // Los otros dos del paywall no lo cubren: los dos disparan por TRANSICION de
  // `subscription`, y el que nunca pago no transiciona nada.
  //
  // Sin `prefKey`, igual que sus dos hermanos: es la respuesta a algo que el PF
  // acaba de intentar hacer, no una novedad de producto.
  | "limit-reached"
  // ── El ALUMNO que se quedo sin cobertura ────────────────────────────────
  //
  // El equivalente de `limit-reached` para el otro rol, y por la misma razon
  // de fondo: la app no puede decirle donde se paga, asi que el mail es el
  // unico canal. Vale la misma cita textual de Apple de arriba.
  //
  // Lo produce `athlete-prospect-mail.ts`. Dispara cuando
  // `athletePaywallEnforced` PASA a `true` —el profe lo dio de baja, o su
  // propia suscripcion vencio— y nunca desde el barrido: ver alla por que esa
  // distincion es la diferencia entre un mail y mandarselo a la base entera.
  //
  // ⚠️ CON `prefKey`, y es el UNICO de los cuatro del paywall que lo lleva.
  // Los otros tres son transaccionales: le avisan a alguien que ya paga que
  // algo paso con su plata. Este le OFRECE un producto a alguien que no lo
  // compro, o sea que es una comunicacion comercial — y
  // `docs/legal/politica-de-privacidad.md` promete que para esas «la oposicion
  // es ABSOLUTA». Sin interruptor, esa linea seria mentira.
  | "athlete-coverage-lost"
  // ── El ALUMNO que choco un tope del plan free ───────────────────────────
  //
  // El hermano del de arriba, y el de mayor INTENCION de los cinco: aquel le
  // escribe al que PERDIO cobertura, este al que esta chocando contra una
  // pared MIENTRAS intenta hacer algo. Quiso una cuarta rutina, o una
  // plantilla paga, y la app le dijo que no.
  //
  // Lo produce `free-limit-mail.ts`, leyendo la anotacion que deja
  // `showFreePlanLimitSheet`. La HOJA no cambia ni una palabra: lo que se
  // anota es invisible, y un dato que el usuario no ve no es un llamado a
  // comprar. Un \«te mandamos un mail\» impreso ahi si lo seria.
  //
  // Comparte `prefKey` con `athlete-coverage-lost` a proposito: son
  // comunicacion comercial sobre lo mismo, y apagar uno y seguir recibiendo el
  // otro seria no haber apagado nada.
  | "free-limit-reached"
  // ── El PF que choco el tope de ejercicios propios de su plan ────────────
  //
  // limite-ejercicios-pf.md, PR4. El equivalente de `limit-reached` (alumnos)
  // pero para la OTRA cuota del PF: `planLimits.customExercises` /
  // `customExerciseUsage.count`, que ya escribe PR1 y ya lee la regla de PR2
  // en `firestore.rules`.
  //
  // Lo produce `trainer-limit-mail.ts`, leyendo `trainerLimitHitKind` /
  // `trainerLimitHitAt`, que anota el CLIENTE (`registrarTopeDelPlanPf`, el
  // tramo siguiente) cuando un create de `users/{uid}/customExercises`
  // rebota contra `customExerciseQuotaOk`.
  //
  // POR QUE ES UN MAIL: el movil solo informa el ESTADO, sin boton ni "pasa a
  // un plan" (E8 del plan, mismo criterio que sostiene `plan_limit_paywall.dart`
  // desde el #1141) — asi que para quien entro por el telefono este mail es el
  // UNICO canal que dice donde se paga.
  //
  // CON `prefKey`: ofrecerle un plan mas grande a quien ya es cliente es
  // comunicacion comercial, igual razonamiento que `athlete-coverage-lost` y
  // `free-limit-reached` (los otros dos que SI lo llevan).
  | "exercise-limit-reached"
  // ── El PF que choco el tope de plantillas de su plan ─────────────────────
  //
  // limite-plantillas-pf.md, PR4. El mismo molde que `exercise-limit-reached`
  // pero para la OTRA cuota nueva del PF: `planLimits.templates` /
  // `templateUsage.count`, que ya escribe PR1 y ya lee la regla de PR2 en
  // `firestore.rules` (`templateQuotaOk`).
  //
  // Lo produce el MISMO `trainer-limit-mail.ts`, generalizado por
  // `trainerLimitHitKind` (`CAMPOS_POR_KIND`): cuando ese campo vale
  // `"templates"`, decide sobre estos dos campos en vez de los de ejercicios.
  //
  // POR QUE ES UN MAIL y CON `prefKey`: mismo razonamiento que
  // `exercise-limit-reached` — el movil solo informa el ESTADO, y ofrecerle
  // un plan mas grande a quien ya es cliente es comunicacion comercial.
  //
  // COMPARTE EL ENFRIAMIENTO con `exercise-limit-reached`
  // (`trainerLimitMailAt`): un PF que choca los dos topes recibe un solo
  // mail cada 14 dias, no uno por tope.
  | "template-limit-reached"
  // ── Baja automatica por inactividad ─────────────────────────────────────
  //
  // El aviso de los 24 meses. Lo produce `sweepInactiveAccounts`, y es el
  // UNICO canal posible: el destinatario es, por definicion, alguien que no
  // abre la app. Un aviso in-app no llegaria nunca.
  //
  // Sin `prefKey`, como `payment-overdue` y `discomfort-reported`: es un aviso
  // legal sobre la vida de la cuenta, no una notificacion de producto. Que se
  // pueda apagar desde preferencias significaria borrar cuentas sin aviso.
  | "inactive-account-notice";

/**
 * Per-kind template parameters.
 *
 * Kept as a flat string/number map (not a discriminated union) because the
 * values round-trip through Firestore, which has no notion of TS unions. The
 * template layer validates what it needs and degrades gracefully on a missing
 * key rather than throwing mid-send.
 */
export type MailParams = Record<string, string | number>;

/** Lifecycle of a queued mail. Terminal states are `sent` and `failed`. */
export type MailStatus = "pending" | "sent" | "failed";

/** Shape of a `mail_queue/{dedupeKey}` document. */
export interface MailQueueDoc {
  /** Recipient uid. The address is resolved from Auth at send time. */
  toUid: string;
  /**
   * Direccion literal, para los mails que NO van a un usuario.
   *
   * Hoy la usa uno solo: el aviso de reporte nuevo, que va al buzon del equipo.
   * Cuando esta presente, el consumidor la usa tal cual y NO resuelve por uid
   * ni consulta `notificationPrefs` — un buzon de equipo no tiene preferencias
   * de notificacion que consultar, y `resolveAddress` sobre un uid que no
   * existe fallaria con "no email address for uid" sobre un mail que sí tiene
   * destino.
   */
  toAddress?: string;
  /** Selects the template. */
  kind: MailKind;
  /** Template parameters. */
  params: MailParams;
  /**
   * Optional `notificationPrefs` key. When present, the consumer skips the
   * send if the user turned the email channel off for that key. Transactional
   * mail (payment overdue, session confirmed) leaves this undefined — it is
   * service-critical and not subject to opt-out.
   */
  prefKey?: string;
  status: MailStatus;
  /** Incremented on every send attempt, successful or not. */
  attempts: number;
  createdAt: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
  sentAt?: FirebaseFirestore.FieldValue | FirebaseFirestore.Timestamp;
  /** Last failure message, kept for triage. Cleared on success. */
  lastError?: string;
}

/** Collection name — single source of truth, referenced by rules and tests. */
export const MAIL_QUEUE_COLLECTION = "mail_queue";

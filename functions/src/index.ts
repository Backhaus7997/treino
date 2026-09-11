/**
 * Entry point for TREINO Cloud Functions.
 * PR#1: exports the deleteAccount callable skeleton.
 * PR#1 (reviews): exports reviewAggregate trigger.
 * PR#1b (notifications): exports 4 FCM trigger functions. Fase 6 Etapa 2.
 * cleanupAssignedPlansOnUnlink: hard-deletes assigned plans when a link ends.
 * sdd/rankings-integrity Phase 1 (PR#1): exports rankingAggregateOnSession +
 * rankingAggregateOnOptIn — server-authoritative ranking-metric recompute.
 *
 * ⚠️ TODO `firebase deploy` de este archivo va a PRODUCCIÓN (#826).
 * `treino-dev` es el único proyecto Firebase de TREINO — el nombre dice "dev"
 * por historia, adentro viven los usuarios reales. Un `firebase deploy` PELADO,
 * sin `--project`, también va ahí: `.firebaserc` declara `"default":
 * "treino-dev"` y la CLI lo completa en silencio, así que el comando no nombra
 * al proyecto que está por tocar. Los comandos de abajo llevan `--project prod`
 * (alias del mismo project ID) para que el destino se vea en pantalla.
 * Ver AGENTS.md § Entornos antes de deployar.
 */

export { deleteAccountHandler as deleteAccount } from "./delete-account";
export { reviewAggregate } from "./review-aggregate";
// #388: denormalized athleteCount on trainerPublicProfiles (active links).
export { linkAggregate } from "./link-aggregate";
export {
  rankingAggregateOnSession,
  rankingAggregateOnOptIn,
} from "./ranking-aggregate";
// Fase W3 (template publishing): community-rating aggregate on the parent
// routine doc (ratingAvg/ratingsCount, CF-write-only fields).
export { templateRatingAggregate } from "./template-rating-aggregate";
export { notifyOnChatMessage } from "./notifications/notify-chat-message";
export { notifyOnAppointment } from "./notifications/notify-appointment";
export { notifyOnLinkChange } from "./notifications/notify-link-change";
// `follow-model` PR3a: notifyOnFriendship → notifyOnFollow (trigger repuntado
// a `follows/{followId}`). OJO en el deploy: un `--only functions:notifyOnFollow`
// CREA la función nueva y NO poda la vieja — `notifyOnFriendship` queda
// desplegada escuchando `friendships`. Queda inerte porque esa colección está
// congelada y el cascade dejó de escribirla, pero hay que borrarla a mano.
export { notifyOnFollow } from "./notifications/notify-friendship";
export { notifyOnReaction } from "./notifications/notify-reaction";
export { reassignFcmToken } from "./notifications/reassign-fcm-token";
export { notifyWearOnWorkoutStarted } from "./notifications/notify-wear-workout";
export { maintainFollowCounters } from "./social/maintain-follow-counters";
export { maintainReactionCounters } from "./social/maintain-reaction-counters";
export { notifyOnReview } from "./notifications/notify-review";
// #628: canal alumno → PF durante la sesión. Notifica SOLO cuando
// kind === 'discomfort' — un comment no debe vibrarle el teléfono al PF.
export { notifyOnExerciseFeedback } from "./notifications/notify-exercise-feedback";
export { cleanupAssignedPlansOnUnlink } from "./cleanup-assigned-plans";
export { addAlias } from "./add-alias";
export { syncSessionShareOnTrainerLink } from "./sync-session-share";
// generateDuePayments (auto-created mensual/semanal pending Payment docs) was
// removed — Slice 1 of the payments redesign makes billing 100% manual (the
// trainer creates/marks every charge by hand via "Registrar pago" / "Marcar
// pagado"). Redeploying functions (`firebase deploy --only functions --project
// prod`) prunes this function from the deployed set — ⚠️ en PRODUCCIÓN, y la
// poda es inmediata para los usuarios reales.
export { notifyOverduePayments } from "./payments/notify-overdue-payments";
export { notifyMonthlyReport } from "./notifications/notify-monthly-report";
// Email transaccional (Resend): consumer del outbox `mail_queue`. Los triggers
// de dominio NUNCA llaman a Resend — escriben una fila de cola con ID
// determinístico y esta función es la única que envía. Ver
// functions/src/mail/enqueue-mail.ts para el contrato de idempotencia.
// OJO en el deploy: necesita el secret RESEND_API_KEY
// (`firebase functions:secrets:set RESEND_API_KEY --project prod` — ⚠️ escribe
// en Secret Manager de PRODUCCIÓN, #826) y que el dominio del remitente esté
// verificado por DNS en Resend, o cada envío devuelve 403.
export { sendQueuedMail } from "./mail/send-queued-mail";
// Email de auth por Resend. `requestPasswordReset` es un endpoint SIN
// autenticar que escribe en Firestore; se despliega recien ahora porque
// `send.gettreino.com` ya esta verificado en Resend y el secret cargado — antes
// habria encolado mail que despues fallaba con 403.
//
// SIN App Check, y es DELIBERADO. App Check en Android no emite atestacion
// valida (iPhone 8 VALID / 2 INVALID, Android 1 VALID / 8 INVALID, medido el
// 2026-08-25), asi que el flag dejaria a los usuarios de Android sin poder
// resetear su contraseña. Misma deuda que `deleteAccount` y
// `mintWatchCredential`, con la misma condicion de salida. El motivo completo
// esta en el bloque de los onCall wrappers de `auth/request-auth-email.ts`, y
// la exencion declarada en `__tests__/appcheck-enforcement.test.ts`.
//
// EL CLIENTE TODAVIA NO LOS LLAMA. `AuthService.sendPasswordResetEmail` y
// `sendEmailVerification` (lib/features/auth/data/auth_service.dart:121 y :130)
// siguen yendo a FirebaseAuth directo, asi que los mails de recuperacion aun
// salen por las plantillas default. Se cambia en un PR aparte, DESPUES de
// verificar a mano que estos callables mandan bien — sobre un flujo donde el
// usuario ya esta afuera de su cuenta, primero se comprueba y despues se migra.
//
// ⚠️ EL DEPLOY TOCA PRODUCCIÓN (#826). No es algo que un agente corra solo:
// publica un endpoint SIN autenticar a los usuarios reales de `treino-dev`.
// Requiere OK explícito de un humano.
//   firebase deploy --only firestore:rules --project prod
//   firebase deploy --only functions --project prod
//
// Las REGLAS PRIMERO: `mail_queue` esta cerrada en los cuatro verbos y conviene
// que esa proteccion este arriba antes de que la coleccion empiece a existir.
//
// El `--project prod` no cambia el destino respecto del comando pelado — lo
// hace VISIBLE. `prod` y `treino-dev` son el mismo project ID; sin la flag,
// `.firebaserc` resuelve al mismo lugar sin que aparezca en pantalla. Ademas,
// un `--only functions` sin filtros PODA del set desplegado toda funcion
// ausente de este archivo.
export { requestPasswordReset, requestEmailVerification } from "./auth/request-auth-email";
export { syncSharedProfile } from "./profile/sync-shared-profile";
// Paywall Fase 7, PR4 (ISSUE-1): keeps users/{trainerId}.weightedLoad
// accurate for display after client-side pause/terminate/decline/cancel —
// the gate itself (syncTrainerLoad) never trusts this field.
export { linkLoadReconcile } from "./subscriptions/link-load-reconcile";
// Paywall Fase 7, PR4 (ISSUE-2): server-authoritative pending -> active.
// Replaces TrainerLinkRepository.accept(); firestore.rules locks the
// client-side path shut in slice 4, AFTER app adoption (see runbook M.4).
export { acceptTrainerLink } from "./subscriptions/accept-trainer-link";
// Paywall Fase 7, PR4 (ISSUE-3): server-authoritative paused -> active.
// Gating accept alone does NOT hold the limit — pause drops weight 1.0 -> 0.5,
// so pause 2 / accept 1 / resume 2 lands over the limit unseen. Both
// weight-raising transitions have to live behind the gate.
export { resumeTrainerLink } from "./subscriptions/resume-trainer-link";
// #637 (secuela): la marca de pre-consulta sólo se estampaba al CREAR el chat,
// y `firestore.rules` la tiene pineada como inmutable. Un chat social que ya
// existía entre el alumno y el PF dejaba al alumno sin poder escribirle NUNCA
// MÁS. El Admin SDK no pasa por rules, así que valida los mismos tres hechos
// que `chatCreateOk` y estampa — sin relajar el pin del cliente.
export { promoteChatToInquiry } from "./chat/promote-chat-to-inquiry";
// Paywall Fase 7 (downgrade): reconcilian `entitlement` cuando el PF queda
// por encima de su limite. Hacen falta LOS DOS — el trigger ve los cambios de
// suscripcion al instante, y el barrido ve lo que ningun trigger puede ver:
// el limite que cae solo por el paso del tiempo (cancelled + currentPeriodEnd
// vencido no escribe un solo documento).
export { syncEntitlementsOnSubscription, sweepEntitlements } from "./subscriptions/entitlement-triggers";
// Paywall del ALUMNO: mantienen `users/{uid}.athletePaywallEnforced`, que es
// el unico dato que firestore.rules NO puede calcular solo — el vinculo con el
// PF vive en `trainer_links` con ids autogenerados, y las reglas no hacen
// queries. Hacen falta LOS TRES: los dos triggers ven suscripcion y vinculo al
// instante, y el barrido hace el backfill de los alumnos que ya existian (a
// esos no los ve ningun trigger porque no escriben nada).
//
// Hoy escriben `false` en todos lados: el interruptor
// ATHLETE_PAYWALL_ENFORCEMENT_ENABLED arranca apagado. Ver el encabezado del
// modulo antes de prenderlo — falta el grandfathering.
export {
  syncAthletePaywallOnUser,
  syncAthletePaywallOnTrainerLink,
  sweepAthletePaywall,
} from "./subscriptions/athlete-paywall-enforced";
// SHELVED (gym-google-places, Plan B): resolveGymPlace cannot be deployed —
// GCP project treino-dev sits under org code-assurance.com, whose
// Domain-Restricted-Sharing policy blocks a publicly-invokable (allUsers)
// Cloud Function. Gym place resolution moved client-side
// (ResolveGymPlaceService,
// lib/features/gyms/data/resolve_gym_place_service.dart). Restore this
// export + redeploy if the org later allows public functions — see
// functions/src/places-search.ts header comment.
// export { resolveGymPlace } from "./places-search";

// Companion de Apple Watch (change watch-standalone-client, fase F1): entrega
// al reloj una credencial PROPIA y renovable. Necesaria porque
// `User.refreshToken` de firebase_auth es vacio en nativo, asi que el telefono
// no puede compartir la suya.
export { mintWatchCredential } from "./mint-watch-credential";

// Paywall del entrenador — el checkout de Mercado Pago. Es el UNICO punto de
// la app que abre un cobro. NO escribe `subscription`: crear el preapproval lo
// deja `pending` en MP hasta que el PF carga su medio de pago, y el tier lo
// escribe el reconciliador cuando MP diga `authorized`. Ver el encabezado de
// `subscriptions/mp/create-preapproval.ts`.
//
// Requiere el secreto MP_ACCESS_TOKEN:
//   firebase functions:secrets:set MP_ACCESS_TOKEN --project prod
export { createPreapproval } from "./subscriptions/mp/create-preapproval";

// Paywall del entrenador — el reconciliador. Es lo que hace que pagar
// SIGNIFIQUE algo: sin esto, `createPreapproval` abre un cobro y nadie se
// entera. Corre a las 03:00 ART, una hora ANTES que `sweepEntitlements`, para
// que el barrido decida bloqueos sobre datos de hoy y no de ayer.
export { reconcileMpSubscriptions } from "./subscriptions/mp/reconcile";

// Paywall del entrenador — la acreditacion EN EL ACTO. El barrido de arriba
// tarda hasta 24 horas, y esas son 24 horas de "pague y no paso nada" para el
// PF que acaba de comprar. Este callable reconcilia SOLO los planes del que
// llama, cuando vuelve del checkout de Mercado Pago.
//
// No reemplaza al barrido: es latencia, no correccion. El barrido sigue siendo
// lo que agarra al que paga y cierra la pestaña. Ver el encabezado de
// `subscriptions/mp/reconcile-my-checkout.ts`.
//
// Usa el mismo secreto MP_ACCESS_TOKEN que los dos de arriba.
export { reconcileMyCheckout } from "./subscriptions/mp/reconcile-my-checkout";

// Paywall del entrenador — la notificacion de Mercado Pago. **El PRIMER
// endpoint HTTP publico del repo**: todo lo demas es onCall con request.auth o
// un trigger de Firestore, esto lo puede POSTear cualquiera.
//
// Lo que lo hace seguro no es la firma —que puede no existir, ver el
// encabezado— sino que del evento se usa UN solo dato, el id, y la verdad se le
// pregunta a MP con nuestro token.
//
// Requiere DOS secretos. El de firma puede quedar vacio si MP no da uno para
// aplicaciones de Suscripciones, pero tiene que EXISTIR o el deploy falla:
//   firebase functions:secrets:set MP_WEBHOOK_SECRET --project prod
export { mpWebhook } from "./subscriptions/mp/webhook";

// El webhook de RevenueCat: el que le acredita la suscripcion al ALUMNO.
//
// Mismo principio que el de MP —del evento se usa el `app_user_id` y la verdad
// se le pregunta a RevenueCat con nuestra key— pero la POLITICA DE CODIGOS es
// la inversa, y esa es la parte que no se puede copiar: MP reintenta cada 15
// minutos para siempre, RevenueCat reintenta 5 veces y abandona. Aca un fallo
// transitorio SI tiene que contestar 5xx. Ver el encabezado del archivo.
//
// Requiere DOS secretos y una variable de entorno:
//   firebase functions:secrets:set RC_API_KEY         --project prod
//   firebase functions:secrets:set RC_WEBHOOK_SECRET  --project prod
//   RC_PROJECT_ID=proj...  (no es secreto)
export { rcWebhook } from "./subscriptions/rc/webhook";

// Un UUID v4 por usuario, que HOY NO SE USA PARA NADA. Es un seguro: el dia
// que se le hable directo a las tiendas hace falta un token propio para saber
// a quien acreditarle una compra —Google no manda ningun identificador de
// usuario y Apple consulta por transactionId— y `appAccountToken` TIENE que
// ser un UUID, cosa que el uid de Firebase no es.
//
// Su valor es retroactivo: el dia que haga falta se necesita para todo el que
// YA compro. Por eso se emite desde hoy. Ver el encabezado del archivo.
export { ensureStoreAccountToken } from "./subscriptions/store-account-token";

// Moderación (change `moderacion-reporte-y-bloqueo`): bloquear borra las
// aristas de follow en las dos direcciones, así que el tier `followers` de
// `posts` queda protegido por la regla de lectura que YA EXISTE
// (`followAccepted`) sin tocar `posts/{postId} allow read` — eso hubiera
// roto el feed entero (una regla de `list` rechaza la query COMPLETA si un
// solo doc del resultado no pasa). Ver el encabezado de
// `moderation/remove-follows-on-block.ts`.
export { removeFollowEdgesOnBlock } from "./moderation/remove-follows-on-block";

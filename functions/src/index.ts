/**
 * Entry point for TREINO Cloud Functions.
 * PR#1: exports the deleteAccount callable skeleton.
 * PR#1 (reviews): exports reviewAggregate trigger.
 * PR#1b (notifications): exports 4 FCM trigger functions. Fase 6 Etapa 2.
 * cleanupAssignedPlansOnUnlink: hard-deletes assigned plans when a link ends.
 * sdd/rankings-integrity Phase 1 (PR#1): exports rankingAggregateOnSession +
 * rankingAggregateOnOptIn — server-authoritative ranking-metric recompute.
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
export { maintainFollowCounters } from "./social/maintain-follow-counters";
export { maintainReactionCounters } from "./social/maintain-reaction-counters";
export { notifyOnReview } from "./notifications/notify-review";
export { cleanupAssignedPlansOnUnlink } from "./cleanup-assigned-plans";
export { addAlias } from "./add-alias";
export { syncSessionShareOnTrainerLink } from "./sync-session-share";
// generateDuePayments (auto-created mensual/semanal pending Payment docs) was
// removed — Slice 1 of the payments redesign makes billing 100% manual (the
// trainer creates/marks every charge by hand via "Registrar pago" / "Marcar
// pagado"). Redeploying functions (`firebase deploy --only functions`) prunes
// this function from the deployed set.
export { notifyOverduePayments } from "./payments/notify-overdue-payments";
// Email transaccional (Resend): consumer del outbox `mail_queue`. Los triggers
// de dominio NUNCA llaman a Resend — escriben una fila de cola con ID
// determinístico y esta función es la única que envía. Ver
// functions/src/mail/enqueue-mail.ts para el contrato de idempotencia.
// OJO en el deploy: necesita el secret RESEND_API_KEY
// (`firebase functions:secrets:set RESEND_API_KEY`) y que el dominio del
// remitente esté verificado por DNS en Resend, o cada envío devuelve 403.
export { sendQueuedMail } from "./mail/send-queued-mail";
// SHELVED (email de auth por Resend): requestPasswordReset y
// requestEmailVerification estan escritos y testeados pero NO se despliegan
// todavia. `requestPasswordReset` es un endpoint SIN autenticar que escribe en
// Firestore; activarlo antes de que el dominio del remitente este verificado
// por DNS en Resend deja superficie de abuso a cambio de nada, porque el mail
// se encola y despues falla con 403.
//
// PARA ACTIVAR, el mismo dia que el dominio quede verificado:
//   1. `firebase functions:secrets:set RESEND_API_KEY`
//   2. descomentar el export de abajo
//   3. cambiar AuthService.sendPasswordResetEmail / sendEmailVerification para
//      que llamen a estos callables en vez de a FirebaseAuth directo
//      (lib/features/auth/data/auth_service.dart:121 y :130)
//   4. `firebase deploy --only functions`
//
// Hasta el paso 3 los mails siguen saliendo por las plantillas default de
// Firebase, asi que el flujo de recuperacion NUNCA queda sin cobertura.
// export { requestPasswordReset, requestEmailVerification } from "./auth/request-auth-email";
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
// Paywall Fase 7 (downgrade): reconcilian `entitlement` cuando el PF queda
// por encima de su limite. Hacen falta LOS DOS — el trigger ve los cambios de
// suscripcion al instante, y el barrido ve lo que ningun trigger puede ver:
// el limite que cae solo por el paso del tiempo (cancelled + currentPeriodEnd
// vencido no escribe un solo documento).
export { syncEntitlementsOnSubscription, sweepEntitlements } from "./subscriptions/entitlement-triggers";
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

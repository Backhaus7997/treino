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
// Issue #628: pushes ONLY for kind: "discomfort" — a plain comment must not
// buzz the trainer's phone a dozen times per session.
export { notifyOnExerciseFeedback } from "./notifications/notify-exercise-feedback";
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
export { syncSharedProfile } from "./profile/sync-shared-profile";
// SHELVED (gym-google-places, Plan B): resolveGymPlace cannot be deployed —
// GCP project treino-dev sits under org code-assurance.com, whose
// Domain-Restricted-Sharing policy blocks a publicly-invokable (allUsers)
// Cloud Function. Gym place resolution moved client-side
// (ResolveGymPlaceService,
// lib/features/gyms/data/resolve_gym_place_service.dart). Restore this
// export + redeploy if the org later allows public functions — see
// functions/src/places-search.ts header comment.
// export { resolveGymPlace } from "./places-search";

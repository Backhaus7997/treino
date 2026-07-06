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
export {
  rankingAggregateOnSession,
  rankingAggregateOnOptIn,
} from "./ranking-aggregate";
export { notifyOnChatMessage } from "./notifications/notify-chat-message";
export { notifyOnAppointment } from "./notifications/notify-appointment";
export { notifyOnLinkChange } from "./notifications/notify-link-change";
export { notifyOnReview } from "./notifications/notify-review";
export { cleanupAssignedPlansOnUnlink } from "./cleanup-assigned-plans";
export { addAlias } from "./add-alias";
export { syncSessionShareOnTrainerLink } from "./sync-session-share";
export { generateDuePayments } from "./payments/generate-due-payments";
export { notifyOverduePayments } from "./payments/notify-overdue-payments";
// SHELVED (gym-google-places, Plan B): resolveGymPlace cannot be deployed —
// GCP project treino-dev sits under org code-assurance.com, whose
// Domain-Restricted-Sharing policy blocks a publicly-invokable (allUsers)
// Cloud Function. Gym place resolution moved client-side
// (ResolveGymPlaceService,
// lib/features/gyms/data/resolve_gym_place_service.dart). Restore this
// export + redeploy if the org later allows public functions — see
// functions/src/places-search.ts header comment.
// export { resolveGymPlace } from "./places-search";

/**
 * Entry point for TREINO Cloud Functions.
 * PR#1: exports the deleteAccount callable skeleton.
 * PR#1 (reviews): exports reviewAggregate trigger.
 */

export { deleteAccountHandler as deleteAccount } from "./delete-account";
export { reviewAggregate } from "./review-aggregate";

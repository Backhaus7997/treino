# Exploration: trainer-reviews

**Change**: trainer-reviews
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-02
**Phase**: Fase 6 Etapa 7
**Artifact store**: hybrid (openspec + engram mirror, obs #127)

---

## Scope Summary

Ship a 1–5 star + optional comment review system where athletes can rate their PF after terminating a vínculo or after ≥30 days from `link.acceptedAt`. One review per athlete/trainer pair (deterministic id `${linkId}_${athleteId}`, editable). Aggregate `averageRating` + `reviewCount` maintained on `trainerPublicProfiles/{uid}` via a CF `onDocumentWritten` trigger over `/reviews/{reviewId}`. Athlete-facing UI: write/edit bottom sheet (triggered on termination or 30-day check), star + count in `TrainerListTile`, and "Reseñas" section in `TrainerPublicProfileScreen`. PF-side mobile display is out of scope for initial delivery.

---

## Current State

### TrainerLink model
**File**: `lib/features/coach/domain/trainer_link.dart`
Fields: `id, trainerId, athleteId, status, requestedAt, acceptedAt?, terminatedAt?, terminationReason?, sharedWithTrainer`.
Lifecycle: `pending → active → terminated`.
`acceptedAt` is present — the 30-day trigger field is already there.
No `reviewPromptShownAt` flag — needs to be added (decision: Firestore vs SharedPreferences).

### TrainerPublicProfile model
**File**: `lib/features/coach/domain/trainer_public_profile.dart`
Current fields: `uid, displayName, displayNameLowercase, avatarUrl, trainerBio, trainerSpecialty, trainerGeohash* (deprecated), trainerLatitude*, trainerLongitude*, trainerMonthlyRate, trainerLocations, trainerGeohashes, trainerOffersOnline`.
`averageRating` and `reviewCount` are absent — need to be added (nullable/default 0).

### TrainersListScreen + TrainerListTile
**Files**: `lib/features/coach/presentation/trainers_list_screen.dart`, `lib/features/coach/presentation/widgets/trainer_list_tile.dart`
TrainerListTile right column: rate + distance/virtual badge. No rating display — new star + count row needed when reviewCount > 0.

### TrainerPublicProfileScreen
**File**: `lib/features/coach/presentation/trainer_public_profile_screen.dart`
Body: TrainerProfileHero, TrainerStatsRow, bio text, monthly rate row, TrainerContactCtaStub (PEDIR VÍNCULO / SOLICITUD PENDIENTE / TU PERSONAL TRAINER). "Reseñas" section needs to be added below. "EDITAR MI RESEÑA" CTA needs to be added when athlete already has a review for this trainer.

### TrainerStatsRow
**File**: `lib/features/coach/presentation/widgets/trainer_stats_row.dart`
RESEÑAS slot hardcoded stub returning "—". StatelessWidget with no params. Must be wired to real `averageRating` + `reviewCount`. Refactor needed: add `TrainerPublicProfile` parameter or convert to ConsumerWidget.

### Link termination trigger (hook point #1)
**File**: `lib/features/coach/athlete_coach_view.dart`, `_ActionRow._onTerminate()` ~line 249
Flow: confirm dialog → `TrainerLinkRepository.terminate()` → `ref.invalidate(currentAthleteLinkProvider)`.
After the successful `terminate()` call, before or after invalidate — THIS is the hook for the review bottom sheet.

### 30-day trigger (hook point #2)
**File**: `lib/features/coach/athlete_coach_view.dart`, `AthleteCoachView.build()` or a `ConsumerStatefulWidget` override of initState.
Currently no 30-day check exists anywhere. Needs a once-per-session gate using `bool _promptShown` local state (pattern: `_rationaleShown` in `TrainersListScreen`).

### Cloud Functions infra
**Files**: `functions/src/index.ts`, `functions/src/delete-account.ts`, `functions/src/cascade/trainer-links.ts`
Node 20, TypeScript, firebase-admin ^12, firebase-functions v5, Jest. Region: southamerica-east1. Full test infra exists. `onDocumentWritten` trigger requires only a new source file + export — no infra bootstrapping needed.

### Firestore rules
`/reviews/{reviewId}` collection does not exist. Patterns to follow: `/trainer_links` (resource==null branch for non-existent docs), `/trainerPublicProfiles` (any auth read, owner write). CF uses Admin SDK — bypasses rules for aggregate writes to trainerPublicProfiles.

### `cloud_functions` package
Already present: `cloud_functions: ^5.2.0` — no new Flutter dependency.

### Deleted-athlete fallback
account-deletion CF anonymizes posts to "Usuario eliminado". `userPublicProfileProvider(uid)` returning null must be handled in `ReviewTile` with the same "Usuario eliminado" pattern.

---

## What Needs to Be Built

### Data layer
- `Review` Freezed model (`lib/features/reviews/domain/review.dart`): `{id, linkId, athleteId, trainerId, rating (1-5), comment?, createdAt, updatedAt}`
- `ReviewRepository` (`lib/features/reviews/data/review_repository.dart`): `upsert()`, `getForPair(linkId, athleteId)`, `watchForTrainer(trainerId)`
- `TrainerPublicProfile` model: add `averageRating? (double)`, `reviewCount (int, @Default(0))`
- Firestore rules: `/reviews/{reviewId}` block (athlete create/update own doc, any auth read)
- `firestore.indexes.json`: composite `(trainerId ASC, createdAt DESC)`
- `functions/src/review-aggregate.ts`: `onDocumentWritten("/reviews/{reviewId}")` → recompute avg + count, update `trainerPublicProfiles/{trainerId}`
- `functions/src/index.ts`: add export

### Athlete write flow
- `ReviewBottomSheet` widget
- `ReviewNotifier` (AsyncNotifier): upsert + edit detection
- Trigger #1 hook: `AthleteCoachView._ActionRow._onTerminate()` after successful terminate
- Trigger #2 hook: `AthleteCoachView.build()` 30-day check with spam gate
- Spam gate: SharedPreferences key `review_prompt_shown_{linkId}` (recommendation) OR `users/{uid}.lastReviewPromptAt` Firestore field

### Athlete edit flow
- `userReviewForLinkProvider(linkId)`: `StreamProvider.autoDispose.family<Review?, String>`
- `TrainerPublicProfileScreen` CTA area: "EDITAR MI RESEÑA" button when athlete has existing review for this trainer's active link

### Discovery display
- `TrainerListTile`: add star + `averageRating` + `(reviewCount)` below specialty chip when `reviewCount > 0`

### Public profile display
- `TrainerPublicProfileScreen`: add "Reseñas" section + edit CTA
- New `TrainerReviewsSection` widget + `ReviewTile` widget (athlete avatar + name + stars + comment + date)
- `TrainerStatsRow`: wire RESEÑAS to real data

---

## Approach Options

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| **Option A — CF onDocumentWritten (PREFERRED)** | Real-time aggregate, no client blocking, idempotent, CF infra already bootstrapped (account-deletion SDD), no client transaction complexity | CF deploy required for new trigger, minor cold-start delay, Blaze plan (already active) | Medium — 1 new CF file + export |
| **Option B — Client-side Firestore transaction** | No CF changes needed, immediately consistent | Client blocks on transaction, O(N) review reads per submit (queries all reviews for trainer), races with simultaneous reviews | Low (no CF) but fragile at scale |
| **Option C — Nightly batch** | Cheapest compute, fully decoupled | 24h staleness — unacceptable UX for a feature athletes expect immediate feedback from | Medium — Cloud Scheduler |

**Recommendation: Option A.**

---

## Open Questions for Proposal

1. **Aggregate strategy (decision)**: CF trigger (recommended) vs client transaction — must lock before spec
2. **30-day spam gate storage (decision)**: SharedPreferences (recommended: no Firestore cost, simpler) vs `users/{uid}.lastReviewPromptAt` (survives reinstall) vs remove 30-day trigger from v1 scope entirely
3. **Edit vs new**: `userReviewForLinkProvider(linkId)` stream — null for no review, `Review` for existing. Pattern confirmed works.
4. **PF mobile view (confirm)**: PF does NOT see "Mis reseñas" in TrainerCoachView in v1
5. **Minimum time threshold (decision)**: none (simple) vs 7-day minimum from `acceptedAt` (requires Firestore rules timestamp check)
6. **Moderation/flag (decision)**: defer flag UI to follow-up, not v1 scope
7. **Bidirectionality (confirm locked)**: athlete → trainer ONLY
8. **Deleted athlete (confirm pattern)**: "Usuario eliminado" + placeholder avatar in ReviewTile
9. **Empty state copy (confirm)**: no star display in list tile when reviewCount == 0; "Sin reseñas todavía" muted in public profile section
10. **Delivery (decision)**: 3 PRs preferred (PR#1: data+CF, PR#2: athlete write flow, PR#3: display) vs 2 PRs

**CRITICAL OPEN QUESTION**: Is the review scoped to `linkId` (one review per link — multiple historical links = multiple reviews possible for same pair) or to `(athleteId, trainerId)` per-pair-all-time? Roadmap says `id: ${linkId}_${athleteId}` (per-linkId) but also "una sola review por par PF/atleta" (per-pair). This must be resolved in the proposal before spec is written. **Per-linkId is the recommended interpretation** because it aligns with the roadmap deterministic id and avoids a cross-collection uniqueness constraint.

---

## Risks

1. **CF aggregate on delete path**: `onDocumentWritten` fires on create, update, AND delete. Delete path must recompute correctly — query all remaining reviews, avg + count. Risk: medium, covered by emulator test.
2. **30-day trigger spam per tab rebuild**: `AthleteCoachView.build()` rebuilds on tab switch. Needs `bool _promptShown` local state (pattern from `_rationaleShown` in TrainersListScreen).
3. **Deterministic id scoping ambiguity**: per-linkId vs per-pair — must be locked before spec.
4. **Deleted athlete in review tile**: `userPublicProfileProvider(uid)` → null → "Usuario eliminado" pattern. Already established in codebase.
5. **TrainerPublicProfile dual-write guard**: `averageRating/reviewCount` must NOT be added to `UserRepository._trainerPublicFields`. The CF writes them via Admin SDK, never the profile editor.
6. **TrainerStatsRow refactor**: needs to accept `TrainerPublicProfile` as parameter (currently no-param StatelessWidget). `TrainerPublicProfileScreen` already has `profile` in scope.
7. **CF region**: must use `southamerica-east1` to match existing `deleteAccount` CF.

---

## Ready for Proposal

Yes — but one critical pre-spec decision must be locked: per-linkId vs per-pair review scoping.

# Design: trainer-reviews

**Change**: trainer-reviews
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-02
**Phase**: Fase 6 Etapa 7
**Artifact store**: hybrid (openspec + Engram `sdd/trainer-reviews/design`)
**Proposal ref**: `openspec/changes/trainer-reviews/proposal.md`
**Explore ref**: `openspec/changes/trainer-reviews/explore.md`

---

## 1. TL;DR

1–5 star reviews + optional comment scoped **per-linkId** (deterministic doc id `${linkId}_${athleteId}`). Athletes leave reviews via a `ReviewBottomSheet` triggered on link termination (Trigger #1) OR ≥30 days from `acceptedAt` with a per-link SharedPreferences spam gate (Trigger #2). A Cloud Function `onDocumentWritten` over `/reviews/{reviewId}` in `southamerica-east1` recomputes `averageRating + reviewCount` on `trainerPublicProfiles/{trainerId}` (Admin SDK, idempotent). Discovery and public profile consume those aggregates. Delivered as **3 chained PRs** (~250 / ~300 / ~350 LOC), all sub-budget. No new pub packages — `cloud_functions: ^5.2.0` is already present from the account-deletion SDD.

---

## 2. Architecture Overview

### High-level flow (write path)

```
AthleteCoachView._ActionRow._onTerminate()  ←─ Trigger #1
       │ after terminate() success
       ▼
AthleteCoachView (post-frame, 30d gate) ←──── Trigger #2
       │ daysSinceAcceptance >= 30 + no review yet + !prefs flag
       ▼
showModalBottomSheet → ReviewBottomSheet(linkId, trainerId, trainerName, existing?)
       │ stars + optional comment + ENVIAR
       ▼
ReviewNotifier.submit({rating, comment}) — AsyncNotifier<void>
       │
       ▼
ReviewRepository.upsert(Review)
       │ Firestore set(merge=false) to reviews/${linkId}_${athleteId}
       ▼
Firestore /reviews/{reviewId}
       │ onDocumentWritten
       ▼
┌──────────────────────────────────────────────────────────────┐
│ Cloud Function reviewAggregate (southamerica-east1)           │
│ 1. Extract trainerId from event.data.after ?? event.data.before│
│ 2. Query reviews where trainerId == X → count + sum(rating)    │
│ 3. Compute { averageRating, reviewCount }                      │
│ 4. set(trainerPublicProfiles/{trainerId}, …, {merge: true})    │
│ 5. Log + return (no rethrow)                                   │
└──────────────────────────────────────────────────────────────┘
       │
       ▼
trainerPublicProfiles/{trainerId}.{averageRating, reviewCount}
```

### High-level flow (read path)

```
TrainersListScreen
   └─ TrainerListTile(profile)
        └─ reviewCount > 0 ? star row : (hidden)

TrainerPublicProfileScreen(profile)
   ├─ TrainerStatsRow(profile)               ← consumes averageRating/reviewCount
   ├─ TrainerContactCta(profile, linkId?, existingReview?)
   │     └─ existingReview != null ? "EDITAR MI RESEÑA" : (existing CTA)
   └─ TrainerReviewsSection(trainerId)
        └─ trainerReviewsProvider(trainerId) → List<Review>
            └─ ReviewTile(review, athletePublicProfile?)
                 └─ profile == null ? "Usuario eliminado" fallback
```

### Streams / providers

| Provider | Type | Purpose |
|---|---|---|
| `userReviewForLinkProvider(linkId)` | `StreamProvider.autoDispose.family<Review?, String>` | Edit detection — null=new, present=edit |
| `trainerReviewsProvider(trainerId)` | `StreamProvider.autoDispose.family<List<Review>, String>` | Public profile section (capped at 10 most-recent) |
| `reviewNotifierProvider` | `AsyncNotifierProvider<ReviewNotifier, void>` | Submit/edit orchestration |

### Component / module table

| Layer | Component | Responsibility |
|---|---|---|
| Domain | `Review` (new) | Freezed model with deterministic id |
| Data | `ReviewRepository` (new) | upsert / getForPair / watchForTrainer |
| Data | CF `reviewAggregate` (new, TS) | Idempotent aggregate via Admin SDK |
| Application | `ReviewNotifier` (new) | AsyncNotifier — submit/edit |
| Application | `userReviewForLinkProvider` (new) | Edit-state detection |
| Application | `trainerReviewsProvider` (new) | Public profile section feed |
| Presentation | `ReviewBottomSheet` (new) | Write + edit sheet (single widget, branches) |
| Presentation | `StarRatingInput` (new) | 5 tappable stars |
| Presentation | `StarRatingDisplay` (new) | 5 read-only stars |
| Presentation | `TrainerReviewsSection` (new) | Section header + list + empty state |
| Presentation | `ReviewTile` (new) | Avatar + name + stars + comment + date + deleted-athlete fallback |
| Presentation | `TrainerListTile` (modified) | Conditional star + count line |
| Presentation | `TrainerStatsRow` (modified) | Consume real aggregates |
| Presentation | `TrainerPublicProfileScreen` (modified) | Reviews section + edit CTA branch |
| Presentation | `AthleteCoachView` (modified) | Trigger #1 + Trigger #2 hooks |

---

## 3. Architecture Decision Records (ADRs)

### ADR-RV-001 — CF `onDocumentWritten` over client transaction

**Decision**: Aggregate via Cloud Function `onDocumentWritten` trigger over `/reviews/{reviewId}` in `southamerica-east1`.

**Rationale**: CF infra is already bootstrapped from `account-deletion` SDD (Node 20, TS, jest emulator harness, Admin SDK). Real-time (<5s typical), idempotent, no client-side transaction surface, no UI blocking on submit. Aligns with how `account-deletion` shaped its trust boundary.

**Alternatives Considered**:
- **Client-side Firestore transaction** — rejected; O(N) read per submit, race-prone with concurrent reviews, client blocks.
- **Nightly batch** — rejected; 24h staleness unacceptable for review UX.

**Trade-offs**: Cold start ~1-3s on first invoke; mitigated because the athlete sees their own submitted review optimistically (already-rendered locally), and other viewers see updated aggregate within seconds.

**Implications**: New file `functions/src/review-aggregate.ts` + 1-line export in `functions/src/index.ts`. Jest emulator tests for create/update/delete paths.

---

### ADR-RV-002 — Per-linkId scoping (`${linkId}_${athleteId}`) over per-pair-all-time

**Decision**: One review per active link. Deterministic doc id is `${linkId}_${athleteId}`. If athlete terminates with PF X and later starts a NEW link with the same PF X (new `linkId`), they can leave a new review — both persist and both count.

**Rationale**: Roadmap explicitly specifies `id: ${linkId}_${athleteId}`. Avoids a cross-collection uniqueness constraint and cross-link migration on re-engagement. Each link is a discrete relationship; reviewing the new one is intentional UX, not duplication.

**Alternatives Considered**:
- **Per-pair-all-time `(athleteId, trainerId)`** — rejected; conflicts with the roadmap id, requires extra query on each submit, and erases the "new relationship = new opinion" signal.

**Trade-offs**: Same athlete can appear N times in a trainer's reviews list across N historical links. Documented as intentional in ADR-RV-014.

**Implications**: Repository `upsert` writes to `reviews/${linkId}_${athleteId}` using `set(..., merge: false)`. Edit path overwrites the same doc. `userReviewForLinkProvider(linkId)` keys on linkId — naturally yields `null` on a freshly created new link.

---

### ADR-RV-003 — TypeScript CF in `southamerica-east1`

**Decision**: Write `review-aggregate.ts` in TypeScript matching the `deleteAccount` shape, deployed to `southamerica-east1`.

**Rationale**: Codebase + tooling already standardized. Co-located region avoids cross-region latency that would compound the visible aggregate delay.

**Alternatives Considered**: us-central1 — rejected (latency from AR); JS — rejected (no type safety on Admin SDK shapes).

**Implications**: Use `firebase-functions/v2/firestore` import for `onDocumentWritten`. Function definition gets `region: "southamerica-east1"` option.

---

### ADR-RV-004 — Aggregate fields live ON `TrainerPublicProfile`

**Decision**: `averageRating? (double)` and `reviewCount (int, @Default(0))` are added directly to `TrainerPublicProfile` (Freezed model + Firestore doc shape). NO separate `trainerAggregates/{uid}` collection.

**Rationale**: Discovery list reads `TrainerPublicProfile` once per tile — single Firestore read for name+avatar+rate+rating. A separate collection would force a second read per tile (N tiles × 2 reads). Rating IS canonical public profile data and should travel with it.

**Alternatives Considered**: Separate `trainerAggregates` collection — rejected; doubles read fan-out on the list screen, no isolation benefit since both are public anyway.

**Trade-offs**: Dual-write surface area on `TrainerPublicProfile` — guarded by ADR-RV-005. Tradeoff accepted.

**Implications**: Regenerate `trainer_public_profile.freezed.dart` + `.g.dart` after adding fields. Document is now written by TWO sources: client (`UserRepository`) for trainer-specific fields, CF (Admin SDK) for aggregates.

---

### ADR-RV-005 — `_trainerPublicFields` MUST exclude aggregate fields (CF-write-only invariant)

**Decision**: `UserRepository._trainerPublicFields` (the dual-write whitelist) MUST NOT contain `averageRating` or `reviewCount`. Only the CF (Admin SDK) writes them.

**Rationale**: Without this guard, a future trainer self-edit propagating ANY whitelisted field would emit a batch including stale aggregate values — silently clobbering the CF's truthful value. This is exactly the class of bug that the `_trainerPublicFields` comment documents (the 2026-05-21 wire-real-stats fallout). Same shape, different field.

**Alternatives Considered**: Compute the diff client-side and exclude unchanged aggregates — rejected; complexity grows with every new aggregate field. Whitelist is the simpler invariant.

**Trade-offs**: Requires an explicit test in the data layer asserting the set excludes these two fields. Worth it.

**Implications**: Spec phase already locks this as a guarded invariant; tasks will add a test `_trainerPublicFields_excludes_aggregates` in `user_repository_test.dart` AND a code comment beside the constant pointing at this ADR.

---

### ADR-RV-006 — SharedPreferences for 30-day spam gate

**Decision**: Store the per-link prompt flag in SharedPreferences under key `review_prompt_shown_{linkId}`.

**Rationale**: Trigger #2 fires on every `AthleteCoachView` build with an active link past the 30-day mark. The check must be cheap and offline — Firestore read on every tab switch is wasteful. SharedPreferences is O(1) local, survives session restarts, and the key is naturally namespaced per link (no cross-link contamination).

**Alternatives Considered**:
- **`users/{uid}.lastReviewPromptAt` Firestore field** — rejected; adds a read on every coach tab open + a write per first prompt; also requires rules change for self-write.
- **In-memory only (`bool _promptShown`)** — rejected alone; resets on app restart so users see the prompt repeatedly on the same link across days. Combined with SharedPreferences as a session-level memoization is fine.

**Trade-offs**: Reinstall / clear-app-data wipes the flag and the athlete sees the prompt again. Acceptable — a user who reinstalled in month two arguably should be re-prompted.

**Implications**: New `SharedPreferences.getInstance()` call in the 30-day check helper. Per-link key. Set true on first display; never explicitly cleared.

---

### ADR-RV-007 — `ReviewBottomSheet` handles BOTH new + edit (single widget)

**Decision**: One `ReviewBottomSheet({required String linkId, required String trainerId, required String trainerName, Review? existing})`. Branches title + initial state on `existing == null`. Same submit path uses `ReviewRepository.upsert` (overwrites same doc id).

**Rationale**: New and edit share 95% of the UI surface (stars, comment, ENVIAR, CANCELAR). Two separate widgets duplicate copy, layout, validation, and tests. The `existing` param is the single visible branch.

**Alternatives Considered**: Two widgets `ReviewBottomSheet` + `EditReviewBottomSheet` — rejected; DRY violation, twice the widget tests.

**Trade-offs**: One widget tests both flows; tests parameterize on `existing`. Acceptable.

**Implications**: Title resolves via `existing == null ? review_sheet_title_new : review_sheet_title_edit`. Initial rating + comment hydrate from `existing` when present. Submit always calls `ReviewNotifier.submit` (which upserts).

---

### ADR-RV-008 — Trigger #2 spam gate persistence model

**Decision**: SharedPreferences key set the first time the prompt is shown for that linkId. The key persists across app restarts (SharedPreferences is durable). No expiration.

**Rationale**: "At most once per linkId" is the locked acceptance criterion. SharedPreferences without expiration meets it exactly. If the user dismisses without reviewing, they don't see the prompt again on that link — they can still leave a review proactively via the public profile CTA.

**Alternatives Considered**: Re-prompt every 60 days — rejected; not in scope, would feel naggy. Cap at session-only — rejected (see ADR-RV-006).

**Trade-offs**: User who hits CANCELAR doesn't get a second chance via auto-prompt. They retain the manual path (public profile → DEJAR RESEÑA). Acceptable.

**Implications**: Setter runs BEFORE `showModalBottomSheet` returns, so even if the user cancels, the flag is set. This matches the locked "at most once per linkId" semantics.

---

### ADR-RV-009 — ReviewTile uses established deleted-athlete fallback

**Decision**: When `userPublicProfileProvider(review.athleteId)` returns `null`, `ReviewTile` renders displayName="Usuario eliminado" + neutral avatar placeholder. Same copy and shape as the account-deletion SDD established for post anonymization.

**Rationale**: Pattern is already in production (chat sender fallback after account-deletion). Reusing the exact copy keeps the brand voice consistent.

**Alternatives Considered**: Render nothing — rejected; leaves stars + comment orphaned and confusing. Render "[Anónimo]" — rejected; "Usuario eliminado" is the locked canonical string.

**Implications**: ReviewTile consumes `userPublicProfileProvider(athleteId)` via `ref.watch` and renders fallback on null.

---

### ADR-RV-010 — Empty state asymmetry: hide on tile, show in section

**Decision**: When `reviewCount == 0`:
- `TrainerListTile` HIDES the star/count row entirely (clean tile).
- `TrainerPublicProfileScreen` SHOWS the "RESEÑAS" section header with body "Sin reseñas todavía" muted.

**Rationale**: List scanning UX punishes visual noise — a row showing "0 reseñas" or "—" on every new trainer pollutes the list. Detail page UX rewards explicitness — discoverability of the reviews feature is itself valuable on the public profile.

**Alternatives Considered**: Show "Sin reseñas" on both — rejected (list noise). Hide on both — rejected (athletes don't learn that reviews exist on the platform).

**Implications**: List tile renders the star row only when `profile.reviewCount > 0`. Public profile section always renders the header; body branches on `reviews.isEmpty`.

---

### ADR-RV-011 — averageRating display format

**Decision**: Format `averageRating` to 1 decimal place using `toStringAsFixed(1)` (e.g. "4.7"). When `averageRating == null` (reviewCount == 0), display "—" in any slot that must always render (e.g. `TrainerStatsRow`).

**Rationale**: One decimal is the App Store / Google Play industry convention — atletas reconocen el patrón. "—" is the project's existing empty-stat placeholder in `TrainerStatsRow`.

**Alternatives Considered**: Two decimals (e.g. "4.72") — rejected (precision implies false rigor over small samples). Round to nearest int — rejected (loses signal).

**Implications**: A tiny utility `formatRating(double?)` extension or static helper, used by `TrainerListTile`, `TrainerStatsRow`, and `TrainerReviewsSection` header. Unit-tested.

---

### ADR-RV-012 — Comment max 500 chars, validated client + CF

**Decision**: Comment is optional, max 500 characters. Validated client-side (TextField `maxLength: 500` + visual counter `"23/500"` muted right) AND server-side in CF + Firestore rules (`request.resource.data.comment.size() <= 500`).

**Rationale**: Locks the open question from the proposal. 500 chars is enough for a substantive review while bounded to defeat doc-bloat / abuse. Dual validation is the standard pattern (rules are the security boundary; client UX is the friendly guardrail).

**Alternatives Considered**: 280 (tweet) — rejected (too short for genuine feedback). 2000 — rejected (encourages essays nobody reads in a list).

**Trade-offs**: Client rejects with snackbar "Tu reseña es demasiado larga." (additional copy entry). Server rejects with `failed-precondition` — surfaced as the same snackbar.

**Implications**: Firestore rules `/reviews/{reviewId}` create+update branches enforce `request.resource.data.comment.size() <= 500`. `ReviewBottomSheet` enforces `maxLength: 500`. Spec already tracks REQ for both surfaces.

---

### ADR-RV-013 — Section caps at 10 most-recent reviews; pagination deferred

**Decision**: `trainerReviewsProvider(trainerId)` queries `reviews where trainerId == X order by createdAt desc limit 10`. No "Ver más" pagination in v1.

**Rationale**: Public profile is a glance — 10 reviews is enough to communicate signal + a few specific comments. Pagination is real engineering (cursor, state, infinite-scroll behavior) — deferring keeps PR#3 under budget.

**Alternatives Considered**: Show all + virtual list — rejected (no virtualization library standardized in this codebase yet for `ListView.builder` on dynamic-height tiles). Show 5 — rejected (too thin once you have a handful of reviewers).

**Trade-offs**: Trainers with 50+ reviews surface only the most recent 10 on mobile. PF web view (out of scope) can expose pagination later. Composite index `(trainerId ASC, createdAt DESC)` covers the query — same index unlocks future pagination.

**Implications**: `firestore.indexes.json` adds the composite index in PR#1. `trainerReviewsProvider` uses `.limit(10)`. No pagination UI work in v1.

---

### ADR-RV-014 — Per-linkId re-engagement semantics

**Decision**: If athlete A terminates link L1 with trainer T (review R1 persists), then forms a NEW link L2 with the same trainer T (new linkId), athlete A can leave a NEW review R2 on L2. Both reviews count in T's aggregate. R1 is NOT updated and NOT deleted.

**Rationale**: Direct corollary of ADR-RV-002. New link = new relationship = new evidence. Erasing the past would lie about historical satisfaction; merging them would conflate distinct experiences.

**Alternatives Considered**: Soft-delete R1 on L2 acceptance — rejected; loses historical signal and adds a CF hook to an unrelated event. Show only the most recent in UI — partially yes: the per-link limit naturally surfaces the most recent first, AND ADR-RV-013 caps display.

**Trade-offs**: Same athlete-name appears twice in T's public profile list (if both reviews are within the top 10). Acceptable — the createdAt dates are visible and clarify.

**Implications**: `userReviewForLinkProvider` keys on `linkId`, so the new link naturally returns `null` and unlocks the "DEJAR UNA RESEÑA" CTA. No cross-link migration logic anywhere.

---

## 4. File-by-file structure

### NEW files

| Path | Purpose | Public surface / shape | PR | LOC est. |
|---|---|---|---|---|
| `lib/features/reviews/domain/review.dart` | Freezed model | `class Review` with `id, linkId, athleteId, trainerId, rating, comment?, createdAt, updatedAt`; `Review.fromJson`/`toJson`; static `idFor(linkId, athleteId)` helper | 1 | ~70 |
| `lib/features/reviews/data/review_repository.dart` | Firestore access | `class ReviewRepository` with `upsert(Review)`, `getForPair(linkId, athleteId)`, `watchForLink(linkId)`, `watchForTrainer(trainerId, {limit=10})` | 1 | ~90 |
| `lib/features/reviews/application/review_providers.dart` | Riverpod surface | `reviewRepositoryProvider`, `userReviewForLinkProvider`, `trainerReviewsProvider` | 1 | ~50 |
| `functions/src/review-aggregate.ts` | CF aggregate | `export const reviewAggregate = onDocumentWritten({document, region}, handler)` + internal `recomputeAggregate(app, trainerId)` | 1 | ~110 |
| `functions/src/__tests__/review-aggregate.test.ts` | Jest emulator tests | Cases: create-first / create-additional / update-rating / delete-not-last / delete-last → null+0 / non-existent trainerPublicProfile (warn, no-op) | 1 | ~180 |
| `lib/features/reviews/application/review_notifier.dart` | AsyncNotifier | `class ReviewNotifier extends AsyncNotifier<void>` with `submit({linkId, trainerId, rating, comment, existing})` | 2 | ~90 |
| `lib/features/reviews/presentation/widgets/review_bottom_sheet.dart` | Write+edit sheet | `class ReviewBottomSheet extends ConsumerStatefulWidget` (linkId, trainerId, trainerName, existing?); shows title, stars, comment field, ENVIAR/CANCELAR | 2 | ~150 |
| `lib/features/reviews/presentation/widgets/star_rating_input.dart` | 5 tappable stars | `class StarRatingInput extends StatelessWidget` with `value`, `onChanged` | 2 | ~70 |
| `lib/features/reviews/presentation/widgets/star_rating_display.dart` | 5 read-only stars | `class StarRatingDisplay extends StatelessWidget` with `value` (double), `size` | 3 | ~50 |
| `lib/features/reviews/presentation/widgets/trainer_reviews_section.dart` | Public profile section | `class TrainerReviewsSection extends ConsumerWidget(trainerId)` header + list + empty state | 3 | ~110 |
| `lib/features/reviews/presentation/widgets/review_tile.dart` | Display tile | `class ReviewTile extends ConsumerWidget(review)` avatar + name + stars + comment + date + deleted-athlete fallback | 3 | ~110 |
| `test/features/reviews/data/review_repository_test.dart` | Repo tests | upsert sets correct doc id; getForPair returns or null; streams emit | 1 | ~120 |
| `test/features/reviews/application/review_notifier_test.dart` | Notifier tests | submit calls upsert with expected shape; error path → AsyncError | 2 | ~80 |
| `test/features/reviews/presentation/review_bottom_sheet_test.dart` | Widget tests | New vs edit branch, submit disabled until rating>0, max-length counter, success snackbar | 2 | ~120 |
| `test/features/reviews/presentation/trainer_reviews_section_test.dart` | Widget tests | Empty state copy; renders ReviewTiles; deleted-athlete fallback | 3 | ~100 |

### MODIFIED files

| Path | Change | PR | LOC est. (delta) |
|---|---|---|---|
| `lib/features/coach/domain/trainer_public_profile.dart` | Add `double? averageRating`, `@Default(0) int reviewCount`. Regenerate `.freezed.dart` + `.g.dart`. | 1 | +6 (model) + auto-gen |
| `lib/features/profile/data/user_repository.dart` | Confirm `_trainerPublicFields` does NOT include `averageRating` / `reviewCount`. Add inline comment pointing at ADR-RV-005. | 1 | +6 |
| `test/features/profile/data/user_repository_test.dart` | Add test `_trainerPublicFields_excludes_aggregates` asserting the set contents. | 1 | +18 |
| `firestore.rules` | Add `/reviews/{reviewId}` block: any-auth read; create allowed if `request.auth.uid == request.resource.data.athleteId` AND `rating in 1..5` AND `comment.size() <= 500`; update same; delete denied. | 1 | +22 |
| `firestore.indexes.json` | Add composite `(collection: reviews, fields: [trainerId ASC, createdAt DESC])`. | 1 | +12 |
| `functions/src/index.ts` | Add `export { reviewAggregate } from "./review-aggregate";`. | 1 | +1 |
| `lib/features/coach/athlete_coach_view.dart` | Convert `AthleteCoachView` to `ConsumerStatefulWidget` (for Trigger #2 post-frame check). Hook Trigger #1 in `_ActionRow._onTerminate()` AFTER `terminate()` succeeds. Hook Trigger #2 via `addPostFrameCallback` in `initState`. | 2 | +90 |
| `lib/features/coach/presentation/trainer_public_profile_screen.dart` | Branch CTA: existing review → "EDITAR MI RESEÑA" button opening `ReviewBottomSheet(existing: …)`. Add `TrainerReviewsSection` below stats row (PR#3 wire-up). | 2 (CTA) + 3 (section) | +30 (PR2) + +20 (PR3) |
| `lib/features/coach/presentation/widgets/trainer_contact_cta.dart` (or inline if no separate widget) | Add "DEJAR UNA RESEÑA" / "EDITAR MI RESEÑA" state when athlete is post-active or has an existing review for the active link. | 2 | +40 |
| `lib/features/coach/presentation/widgets/trainer_list_tile.dart` | Conditional star + averageRating + reviewCount row when `profile.reviewCount > 0`. Uses `StarRatingDisplay`. | 3 | +30 |
| `lib/features/coach/presentation/widgets/trainer_stats_row.dart` | Accept `TrainerPublicProfile profile` param. Wire RESEÑAS slot to `formatRating(profile.averageRating)` + count below. | 3 | +18 |
| `test/features/coach/presentation/trainer_list_tile_test.dart` | Add: shows star row when count>0; hides row when count==0; formats avg to 1 decimal. | 3 | +60 |
| `test/features/coach/presentation/trainer_stats_row_test.dart` | Updated to inject profile; assert "—" when null, "4.7" when present. | 3 | +30 |

### DELETED files

None.

### PR LOC summary

| PR | New | Modified | Total est. |
|---|---|---|---|
| PR#1 — Data + CF + rules | review.dart, review_repository.dart, review_providers.dart, review-aggregate.ts, review-aggregate.test.ts, review_repository_test.dart | trainer_public_profile.dart (+6), user_repository.dart (+6), user_repository_test.dart (+18), firestore.rules (+22), firestore.indexes.json (+12), index.ts (+1) | ~250 |
| PR#2 — Athlete write/edit flow | review_notifier.dart, review_bottom_sheet.dart, star_rating_input.dart, review_notifier_test.dart, review_bottom_sheet_test.dart | athlete_coach_view.dart (+90), trainer_public_profile_screen.dart CTA (+30), trainer_contact_cta.dart (+40) | ~300 |
| PR#3 — Discovery + public profile display | star_rating_display.dart, trainer_reviews_section.dart, review_tile.dart, trainer_reviews_section_test.dart | trainer_list_tile.dart (+30), trainer_stats_row.dart (+18), trainer_public_profile_screen.dart section (+20), trainer_list_tile_test.dart (+60), trainer_stats_row_test.dart (+30) | ~350 |

All three PRs sub-budget. No `size:exception` planned.

---

## 5. Cloud Function design details

### Handler signature (TypeScript)

```typescript
import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions/v2";

function getApp(): admin.app.App {
  try { return admin.app(); } catch { return admin.initializeApp(); }
}

export const reviewAggregate = onDocumentWritten(
  {
    document: "reviews/{reviewId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const app = getApp();
    const after = event.data?.after?.data();
    const before = event.data?.before?.data();
    const trainerId =
      (after?.trainerId as string | undefined) ??
      (before?.trainerId as string | undefined);

    if (!trainerId) {
      logger.warn("reviewAggregate: no trainerId on event", {
        path: event.document,
      });
      return;
    }
    await recomputeAggregate(app, trainerId);
  },
);

export async function recomputeAggregate(
  app: admin.app.App,
  trainerId: string,
): Promise<void> {
  const db = admin.firestore(app);
  try {
    const snap = await db
      .collection("reviews")
      .where("trainerId", "==", trainerId)
      .get();

    const count = snap.size;
    const update =
      count === 0
        ? { averageRating: null, reviewCount: 0 }
        : {
            averageRating:
              snap.docs.reduce(
                (sum, d) => sum + (d.data().rating as number),
                0,
              ) / count,
            reviewCount: count,
          };

    const profileRef = db.collection("trainerPublicProfiles").doc(trainerId);
    const profileSnap = await profileRef.get();
    if (!profileSnap.exists) {
      logger.warn("reviewAggregate: trainerPublicProfile missing", {
        trainerId,
      });
      return;
    }
    await profileRef.set(update, { merge: true });
  } catch (e: unknown) {
    logger.error("reviewAggregate failed", { trainerId, error: String(e) });
    // Do NOT rethrow — avoid CF retry storm on bad data.
  }
}
```

### Order of operations (per event)

1. Extract `trainerId` from `event.data.after` (create/update) OR `event.data.before` (delete).
2. Query `reviews where trainerId == X` → count + sum of ratings.
3. Build update payload: empty → `{averageRating: null, reviewCount: 0}`; else `{averageRating: avg, reviewCount: count}`.
4. Check `trainerPublicProfiles/{trainerId}` exists; if not, log warning and return (no-op — protects against orphaned reviews after a trainer self-deletion future feature).
5. `set(update, {merge: true})` via Admin SDK.
6. Catch + log any error; do NOT rethrow.

### Idempotency

- Re-firing with the same review data produces the same write (count + average deterministic given the same review set).
- The CF queries Firestore directly each time — no internal state to drift.
- Multiple concurrent writes to different reviews trigger multiple concurrent CF invocations; the last to commit wins, which is correct because the FINAL state read by the latest invocation reflects everyone's writes.

### Failure handling

- Per-event try/catch logs and swallows. Reasoning: if the doc is malformed (e.g., missing `trainerId` after a manual Firestore Console edit), retrying forever would queue dead-letter spam. Logging is enough — engineering can re-trigger manually.
- A failed write to `trainerPublicProfiles` (e.g., transient Firestore outage) leaves the aggregate stale by minutes; the next review write re-triggers the function and re-computes.

---

## 6. Bottom sheet UX details

### `ReviewBottomSheet` shape

```dart
class ReviewBottomSheet extends ConsumerStatefulWidget {
  const ReviewBottomSheet({
    super.key,
    required this.linkId,
    required this.trainerId,
    required this.trainerName,
    this.existing,
    this.triggerVariant = ReviewTriggerVariant.terminal,
  });
  final String linkId;
  final String trainerId;
  final String trainerName;
  final Review? existing;
  final ReviewTriggerVariant triggerVariant; // terminal | thirtyDay
}
```

### Title resolution

- `existing != null` → `review_sheet_title_edit` ("Editá tu reseña")
- `triggerVariant == thirtyDay && existing == null` → `review_30day_prompt_title` ("Ya llevás un mes entrenando con {trainerName}. ¿Cómo va?")
- otherwise → `review_sheet_title_new` ("¿Cómo fue tu experiencia con {trainerName}?")

### Body

- 5 large tappable stars via `StarRatingInput`. Hydrated from `existing?.rating ?? 0`.
- Optional `TextField`:
  - hint `review_sheet_comment_hint` ("Contanos cómo fue (opcional)")
  - `maxLength: 500`
  - counter visible muted right ("23/500")
  - Hydrated from `existing?.comment ?? ''`
- ENVIAR button:
  - Label `review_sheet_send` ("ENVIAR")
  - Disabled until `rating > 0`
  - Shows `CircularProgressIndicator` while `notifier.state.isLoading`
- CANCELAR button:
  - Label `review_sheet_cancel` ("CANCELAR")
  - Pops sheet without action

### Submit flow

```
onSubmit():
  state = AsyncLoading()
  try {
    await ref.read(reviewNotifierProvider.notifier).submit(
      linkId: linkId,
      trainerId: trainerId,
      rating: rating,
      comment: comment.trim().isEmpty ? null : comment.trim(),
      existing: existing,
    );
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(review_submit_success)),
      );
    }
  } on Object {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(review_submit_error)),
      );
    }
  }
```

No auto-retry; error snackbar clears the error and lets the user re-submit.

---

## 7. Trigger orchestration

### Trigger #1 — post-termination

In `_ActionRow._onTerminate()` after the existing `terminate()` + `invalidate(currentAthleteLinkProvider)`:

```dart
Future<void> _onTerminate(BuildContext context, WidgetRef ref) async {
  final confirmed = await _confirm(context, '…', '…');
  if (!confirmed) return;

  // capture container BEFORE await (dispose-safe per project pattern)
  final container = ProviderScope.containerOf(context, listen: false);
  final terminatedLinkId = link.id;
  final trainerId = link.trainerId;

  await ref
      .read(trainerLinkRepositoryProvider)
      .terminate(link.id, reason: 'athlete-terminated');
  container.invalidate(currentAthleteLinkProvider);

  if (!context.mounted) return;
  // Resolve trainer name from public profile (cached); existing review (rare in
  // termination flow but possible if athlete reviewed during 30-day prompt).
  final trainerProfile = container.read(userPublicProfileProvider(trainerId));
  final trainerName = trainerProfile.value?.displayName ?? '—';
  final existing = container
      .read(userReviewForLinkProvider(terminatedLinkId))
      .valueOrNull;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ReviewBottomSheet(
      linkId: terminatedLinkId,
      trainerId: trainerId,
      trainerName: trainerName,
      existing: existing,
      triggerVariant: ReviewTriggerVariant.terminal,
    ),
  );
}
```

The dispose-safe container capture follows the project's Riverpod pattern (see `friend_request_inbox_tile.dart` — the action triggers the parent stream to re-emit, pruning this widget mid-await).

### Trigger #2 — 30-day prompt

`AthleteCoachView` converts to `ConsumerStatefulWidget`:

```dart
class AthleteCoachView extends ConsumerStatefulWidget {
  const AthleteCoachView({super.key});
  @override
  ConsumerState<AthleteCoachView> createState() => _AthleteCoachViewState();
}

class _AthleteCoachViewState extends ConsumerState<AthleteCoachView> {
  bool _promptCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_promptCheckScheduled) return;
      _promptCheckScheduled = true;
      _maybeShow30DayPrompt();
    });
  }

  Future<void> _maybeShow30DayPrompt() async {
    if (!mounted) return;
    final linkAsync = ref.read(currentAthleteLinkProvider);
    final link = linkAsync.valueOrNull;
    if (link == null || link.status != TrainerLinkStatus.active) return;
    if (link.acceptedAt == null) return;
    final days = DateTime.now().difference(link.acceptedAt!).inDays;
    if (days < 30) return;

    final existing = ref
        .read(userReviewForLinkProvider(link.id))
        .valueOrNull;
    if (existing != null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'review_prompt_shown_${link.id}';
    if (prefs.getBool(key) ?? false) return;

    await prefs.setBool(key, true);
    if (!mounted) return;

    final trainerName = ref
        .read(userPublicProfileProvider(link.trainerId))
        .valueOrNull
        ?.displayName ?? '—';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReviewBottomSheet(
        linkId: link.id,
        trainerId: link.trainerId,
        trainerName: trainerName,
        triggerVariant: ReviewTriggerVariant.thirtyDay,
      ),
    );
  }

  @override
  Widget build(BuildContext context) { /* existing build moved here */ }
}
```

Key invariants:
- Post-frame callback ensures provider values are warm.
- `_promptCheckScheduled` guards against tab-rebuild double-fire within the same widget lifetime.
- Flag is set BEFORE the sheet opens so a cancel still counts as "shown once".
- Per ADR-RV-006, the SharedPreferences key persists across restarts.

---

## 8. Copy table (es-AR)

All strings marked `// i18n: Fase 6 Etapa 7` at source.

| Key | Spanish text | Used in |
|---|---|---|
| `review_sheet_title_new` | `¿Cómo fue tu experiencia con {trainerName}?` | `ReviewBottomSheet` title (new, terminal variant) |
| `review_sheet_title_edit` | `Editá tu reseña` | `ReviewBottomSheet` title (edit) |
| `review_30day_prompt_title` | `Ya llevás un mes entrenando con {trainerName}. ¿Cómo va?` | `ReviewBottomSheet` title (new, thirty-day variant) |
| `review_sheet_comment_hint` | `Contanos cómo fue (opcional)` | `ReviewBottomSheet` TextField hint |
| `review_sheet_send` | `ENVIAR` | `ReviewBottomSheet` primary |
| `review_sheet_cancel` | `CANCELAR` | `ReviewBottomSheet` secondary |
| `review_submit_success` | `¡Gracias por tu reseña!` | Snackbar on submit success |
| `review_submit_error` | `No pudimos guardar tu reseña. Probá de nuevo.` | Snackbar on submit error |
| `review_comment_too_long_error` | `Tu reseña es demasiado larga. Probá con menos texto.` | Snackbar when >500 chars (server-side rejection fallback) |
| `review_section_title` | `RESEÑAS` | Section header in `TrainerPublicProfileScreen` + `TrainerStatsRow` slot label |
| `review_section_empty` | `Sin reseñas todavía` | Empty body of section when reviewCount==0 |
| `review_edit_cta` | `EDITAR MI RESEÑA` | `TrainerPublicProfileScreen` CTA when existing != null |
| `review_new_cta` | `DEJAR UNA RESEÑA` | `TrainerPublicProfileScreen` CTA (post-active, no review) |
| `deleted_athlete_name` | `Usuario eliminado` | `ReviewTile` fallback when `userPublicProfileProvider` returns null |
| `review_count_label_one` | `{count} reseña` | `TrainerListTile` + section header (singular) |
| `review_count_label_other` | `{count} reseñas` | `TrainerListTile` + section header (plural) |
| `review_avg_empty_placeholder` | `—` | `TrainerStatsRow` when averageRating == null |

Theming: all colors via `AppPalette.of(context)` — zero HEX literals. Star icon: `TreinoIcon.starFill` / `TreinoIcon.starOutline` (add to icon registry if missing — small wrapper around the appropriate Phosphor icon, NEVER `PhosphorIcons.X` directly).

---

## 9. Test strategy

### Cloud Function (PR#1)

- **Runner**: `jest` + `firebase-functions-test` (online mode), Firebase emulator suite (Firestore only — no Auth/Storage needed for this CF).
- **Seed helper**: lightweight (4 trainers, deterministic ids; `trainerPublicProfiles/{tA..tD}` pre-created).
- **Cases**:
  - Create first review on trainerA → `averageRating == rating`, `reviewCount == 1`
  - Create second review with different rating → average is correct, count == 2
  - Update existing review's rating → average reflects new rating, count unchanged
  - Delete one review (not last) → average recomputed, count decremented
  - Delete last review → `averageRating == null`, `reviewCount == 0`
  - Write to `reviews/X` with `trainerId` pointing at a non-existent profile → warn-log + no-op (no crash)
  - Malformed doc missing `trainerId` → warn-log + early return

### Repo + providers (PR#1)

- `ReviewRepository` integration tests with `fake_cloud_firestore`:
  - `upsert` writes to `reviews/${linkId}_${athleteId}` (deterministic id check)
  - `watchForLink(linkId)` emits null then Review on later write
  - `watchForTrainer(trainerId, limit: 10)` orders by `createdAt desc` and caps at 10

- `_trainerPublicFields_excludes_aggregates` regression test in `user_repository_test.dart` (locks ADR-RV-005).

### Notifier (PR#2)

- `ReviewNotifier` unit tests with mocked `ReviewRepository`:
  - submit calls `upsert` with derived doc id; payload includes correct fields
  - submit error → `AsyncError` state surfaces
  - submit success → `AsyncData(null)`

### Widget (PR#2 + PR#3)

- `ReviewBottomSheet`:
  - New flow: title matches `review_sheet_title_new`, ENVIAR disabled until tap-star, comment counter renders
  - Edit flow with `existing`: title matches `review_sheet_title_edit`, hydrated rating + comment
  - Thirty-day variant: title matches `review_30day_prompt_title`
  - Submit success → sheet pops + snackbar
  - Submit error → snackbar + sheet stays
- `TrainerReviewsSection`:
  - Empty state copy renders
  - Renders ReviewTiles when data present
  - Deleted-athlete fallback ("Usuario eliminado") when `userPublicProfileProvider` returns null
- `TrainerListTile`:
  - Star row hidden when `reviewCount == 0`
  - Star row visible + "4.7" + "(3 reseñas)" when present
- `TrainerStatsRow`:
  - "—" when `averageRating == null`
  - "4.7" + count when present

### E2E smoke (manual, PR#3 close-out)

- Two test athletes + one test trainer on `treino-dev`.
- Athlete A terminates link → sheet opens → submit 5 stars + comment → CF runs → trainer's `TrainerPublicProfile` shows `averageRating: 5.0, reviewCount: 1` in Firestore Console within ~5s.
- Athlete B leaves a 3-star review → trainer profile shows avg 4.0, count 2.
- Athlete A edits review to 4 stars → trainer profile shows avg 3.5.
- Delete Athlete A's review via Firestore Console (admin) → trainer profile shows avg 3.0, count 1.
- Delete final review → trainer profile shows `averageRating: null, reviewCount: 0`; list tile hides star row; public profile section shows "Sin reseñas todavía".

---

## 10. Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| CF cold start (~1-3s) delays first aggregate update | Low | Acceptable UX — athlete sees their own submitted review optimistically (sheet pops, snackbar shown); other viewers see updated aggregate within seconds. |
| `_trainerPublicFields` accidentally includes aggregates in a future PR | High if missed | Locked test `_trainerPublicFields_excludes_aggregates` + inline code comment pointing at ADR-RV-005. |
| SharedPreferences key cleared on reinstall causes re-prompt | Low | Documented acceptable in ADR-RV-006. |
| Trigger #2 fires twice across rebuilds | Medium | `_promptCheckScheduled` widget-state guard + persistent SharedPreferences flag. Belt + suspenders. |
| Deleted athlete in ReviewTile crashes | Low | Pattern established by account-deletion SDD; `ReviewTile` consumes `userPublicProfileProvider(athleteId)` and renders fallback on null. |
| Per-linkId scoping causes confusion if same athlete reviews same trainer twice (across links) | Low | ADR-RV-014 documents the intentional behavior; createdAt dates disambiguate in the UI. |
| Composite index missing at deploy → query fails | Low | `firestore.indexes.json` ships in PR#1; PR description includes `firebase deploy --only firestore:indexes` step. |
| CF retries forever on a malformed doc | Low | Handler catches + swallows errors; logs only. Future ops doc can describe manual re-trigger. |
| Concurrent reviews race the aggregate | Low | CF re-queries Firestore on each invocation; last write wins with correct final state. |
| Dispose-safe orchestration in `_onTerminate` regresses (linkId becomes null on context.mounted = false) | Medium | Capture `terminatedLinkId` + `trainerId` to locals BEFORE await; use container.read after await per project pattern. Mirrors `friend_request_inbox_tile.dart`. |

---

## 11. Out of scope (explicit)

- PF mobile "Mis reseñas" view in `TrainerCoachView`
- PF flag / moderation flow
- PF response to reviews
- Multimedia reviews (photo/video)
- Bidirectional reviews (PF → athlete)
- Public/private review toggle
- Minimum time threshold before reviewing (e.g., 7 days from `acceptedAt`)
- Per-link review history view ("ver mis reseñas anteriores con este PF")
- Pagination beyond first 10 ("Ver más" follow-up)
- Aggregate analytics dashboard
- Multi-region CF deploy (only `southamerica-east1`)

---

## 12. Proposal open-question resolutions

| Open Question (proposal §13) | Resolution |
|---|---|
| CF cold-start latency target / SLO | No SLO for v1 — "best effort, typical <5s" (documented in Risks §10). |
| Comment max length | **500 characters**, validated client + Firestore rules (ADR-RV-012). |

---

## 13. Remaining open questions

1. **Star icon names in `TreinoIcon` registry** — verify `TreinoIcon.starFill` / `TreinoIcon.starOutline` exist; if not, add as a trivial wrapper around the matching Phosphor icon (PR#2 or PR#3, whichever introduces the widget first). Not blocking.

All other questions were closed in the proposal or in the ADRs above.

---

**Status**: Ready for `sdd-tasks`.

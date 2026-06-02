# Proposal: trainer-reviews

**Change**: trainer-reviews
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-02
**Phase**: Fase 6 Etapa 7
**Artifact store**: hybrid (openspec + engram)

---

## TL;DR

Ship a 1–5 stars + optional comment review system where athletes can rate their PF after terminating a vínculo or after ≥30 days from `link.acceptedAt`. Reviews are scoped **per-linkId** (one review per active link), editable until the link is reused. A Cloud Function `onDocumentWritten` trigger maintains `averageRating + reviewCount` on `trainerPublicProfiles/{uid}`. Athlete-facing UI: bottom sheet for write/edit, star + count badge in `TrainerListTile`, and a "RESEÑAS" section in `TrainerPublicProfileScreen`. PF-side mobile display is deferred. Delivery: 3 chained PRs (~900 LOC total, all sub-budget).

---

## Why

Two real user problems:

1. **Discovery friction**: athletes choose a PF blindly today. No social proof = lower conversion from list view to vínculo request, and overweights monthly rate as the only differentiator.
2. **No credibility signal for new PFs**: a competent PF who joins recently has no way to surface trust. Reviews compound over time and give new PFs a path to visibility beyond their bio + tarifa.

Adjacent payoff: post-termination reviews close the loop on a vínculo lifecycle that today ends silently — athletes finish without a reflection moment, PFs learn nothing about how they came across.

---

## Locked Decisions

| # | Question | Decision | Rationale |
|---|---|---|---|
| **0 (CRITICAL)** | per-linkId vs per-pair review scoping | **per-linkId** | Aligns with roadmap deterministic id `${linkId}_${athleteId}`. Re-establishing a vínculo with the same PF after termination = new experience, new review. Simpler, no cross-link uniqueness check. |
| 1 | Aggregate strategy | **CF `onDocumentWritten`** | CF infra exists from `account-deletion` SDD; one new file + export. Real-time, idempotent, no client blocking. |
| 2 | 30-day spam gate storage | **SharedPreferences** key `review_prompt_shown_{linkId}` | No Firestore read cost per app open; reinstall edge case is acceptable. |
| 3 | Edit detection | **`userReviewForLinkProvider(linkId)`** StreamProvider returning `Review?` | Pattern proven in codebase. |
| 4 | PF "Mis reseñas" mobile view | **OUT of v1** | Non-blocking; can land in Coach Hub web later. |
| 5 | Minimum time threshold before reviewing | **NONE for v1** | Simpler; trade-off accepted. |
| 6 | Moderation / flag UI | **OUT of v1** | Post-hoc handling, deferred. |
| 7 | Bidirectionality | **athlete → trainer ONLY** | Locked in roadmap. |
| 8 | Deleted athlete in review tile | **"Usuario eliminado" + null avatar** | Reuse pattern from `account-deletion` (chat sender fallback). |
| 9 | Empty state copy | **List tile**: no star/count row when `reviewCount == 0`. **Public profile**: render "RESEÑAS" section with "Sin reseñas todavía" muted body. | Clean tile; explicit empty in profile (discoverability over hiding). |
| 10 | Delivery strategy | **3 chained PRs** (~250 / ~300 / ~350 LOC) | Each sub-budget; mirrors `account-deletion` shape. |

---

## Scope

### In Scope

- `Review` Freezed model + repo + providers (read + write)
- `TrainerPublicProfile`: add `averageRating? (double)` + `reviewCount (int, @Default(0))` (with dual-write guard — NOT in `_trainerPublicFields`)
- `firestore.rules`: `/reviews/{reviewId}` block
- `firestore.indexes.json`: composite `(trainerId ASC, createdAt DESC)`
- CF `functions/src/review-aggregate.ts`: `onDocumentWritten` trigger in `southamerica-east1`
- Trigger #1 hook: `AthleteCoachView._ActionRow._onTerminate()` post-success
- Trigger #2 hook: `AthleteCoachView` 30-day check with SharedPreferences spam gate
- `ReviewBottomSheet` (write + edit)
- `userReviewForLinkProvider(linkId)` for edit detection
- "EDITAR MI RESEÑA" CTA in `TrainerPublicProfileScreen` when athlete has existing review
- `TrainerListTile`: star + averageRating + (reviewCount) when `reviewCount > 0`
- `TrainerPublicProfileScreen`: "RESEÑAS" section with empty state
- `TrainerReviewsSection` + `ReviewTile` widgets (deleted-athlete fallback)
- `TrainerStatsRow` refactor (consume real data via `TrainerPublicProfile` param)

### Out of Scope

- PF flag / moderation flow
- PF "Mis reseñas" mobile view in `TrainerCoachView`
- PF response to reviews (Booking/Airbnb pattern)
- Multimedia reviews (photo/video)
- Bidirectional reviews (PF rating athlete)
- Public/private review toggle
- Minimum time threshold before reviewing
- Per-link review history view ("ver mis reseñas anteriores con este PF")
- Aggregate dashboard analytics (avg over time, distribution histogram, etc.)

---

## Capabilities

### New Capabilities

- `trainer-reviews`: athlete-authored 1–5 star reviews of trainers, scoped per active link, with optional comment; backed by a CF aggregate that maintains `averageRating + reviewCount` on the trainer's public profile; surfaced in discovery (list tile) and public profile.

### Modified Capabilities

- `coach-discovery`: `TrainerListTile` and `TrainerPublicProfileScreen` consume new aggregate fields and add the reviews section + edit CTA.
- `coach-vinculo-lifecycle`: link termination flow gains a post-success review prompt; `AthleteCoachView` gains a 30-day prompt with spam gate.

---

## Approach Summary

**CF `onDocumentWritten` aggregate trigger** over `/reviews/{reviewId}`. On create/update/delete the function recomputes `averageRating` and `reviewCount` for the affected `trainerId` (query all remaining reviews → reduce → Admin SDK write to `trainerPublicProfiles/{trainerId}`). Idempotent, real-time (<5s typical), no client blocking, no client transaction surface area.

Client-side: per-linkId deterministic doc id `${linkId}_${athleteId}` ensures one logical review per link with natural edit semantics (overwrite same doc). `userReviewForLinkProvider` watches that doc — `null` → "DEJAR RESEÑA" flow, present → "EDITAR MI RESEÑA" flow.

Alternatives (client transaction, nightly batch) considered and rejected — see `explore.md` Approach Options table.

---

## Delivery Strategy

**3 chained PRs**, each ≤400 LOC, all sub-budget — no `size:exception` expected.

| PR | Title | Scope | Est. LOC |
|---|---|---|---|
| #1 | Data layer + CF aggregate + rules | Review model + repo + read providers, `TrainerPublicProfile` field additions, firestore.rules `/reviews/`, firestore.indexes.json composite, CF `review-aggregate.ts` + export + Jest emulator tests | ~250 |
| #2 | Athlete write/edit flow | `ReviewBottomSheet` + `ReviewNotifier` (AsyncNotifier), `userReviewForLinkProvider`, trigger #1 hook in `_onTerminate()`, trigger #2 hook in `AthleteCoachView` (30-day + SharedPreferences gate), "EDITAR MI RESEÑA" CTA, i18n markers, tests | ~300 |
| #3 | Discovery + public profile display | `TrainerListTile` star + count row, `TrainerPublicProfileScreen` "RESEÑAS" section, `TrainerReviewsSection`, `ReviewTile` (deleted-athlete fallback), `TrainerStatsRow` refactor, tests | ~350 |

**Risk mitigation**: PR#1 lands data layer + CF in isolation — verifiable independently via emulator before any UI work. PR#2 unblocks write flow without requiring discovery changes (athlete can review immediately even if list tile and public section still show stubs). PR#3 wraps presentation as a pure display layer over already-verified data.

Branch shape: feature branch chain (`feature/trainer-reviews` ← `feature/trainer-reviews-pr1` ← `feature/trainer-reviews-pr2` ← `feature/trainer-reviews-pr3`). Each child PR rebased clean against its parent before review.

---

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `lib/features/reviews/domain/review.dart` | New | Freezed model |
| `lib/features/reviews/data/review_repository.dart` | New | `upsert`, `getForPair`, `watchForTrainer` |
| `lib/features/reviews/application/` | New | `ReviewNotifier`, `userReviewForLinkProvider`, `trainerReviewsProvider` |
| `lib/features/reviews/presentation/review_bottom_sheet.dart` | New | Write/edit UI |
| `lib/features/reviews/presentation/widgets/review_tile.dart` | New | Display tile with deleted-athlete fallback |
| `lib/features/reviews/presentation/widgets/trainer_reviews_section.dart` | New | Public profile section |
| `lib/features/coach/domain/trainer_public_profile.dart` | Modified | Add `averageRating?`, `reviewCount` |
| `lib/features/coach/data/user_repository.dart` | Modified | Dual-write guard — exclude aggregate fields from `_trainerPublicFields` |
| `lib/features/coach/athlete_coach_view.dart` | Modified | Trigger #1 + #2 hooks, 30-day spam gate |
| `lib/features/coach/presentation/trainer_public_profile_screen.dart` | Modified | "RESEÑAS" section + "EDITAR MI RESEÑA" CTA |
| `lib/features/coach/presentation/widgets/trainer_list_tile.dart` | Modified | Star + count row |
| `lib/features/coach/presentation/widgets/trainer_stats_row.dart` | Modified | Accept `TrainerPublicProfile` param, consume real data |
| `firestore.rules` | Modified | `/reviews/{reviewId}` block |
| `firestore.indexes.json` | Modified | Composite `(trainerId ASC, createdAt DESC)` |
| `functions/src/review-aggregate.ts` | New | `onDocumentWritten` trigger |
| `functions/src/index.ts` | Modified | Export new trigger |
| `functions/test/review-aggregate.test.ts` | New | Jest emulator tests |

---

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| CF aggregate incorrect on delete path | Medium | `onDocumentWritten` handles create/update/delete uniformly: query all remaining reviews for trainerId, reduce, write. Emulator test for the delete branch (last review deleted → `averageRating: null`, `reviewCount: 0`). |
| 30-day prompt spams per tab rebuild | Medium | Local `bool _promptShown` flag in `AthleteCoachView` (pattern from `_rationaleShown` in `TrainersListScreen`) + SharedPreferences key `review_prompt_shown_{linkId}` for persistence across sessions. |
| Deleted athlete in review tile crashes UI | Low | `userPublicProfileProvider(uid)` returns `null` → `ReviewTile` falls back to "Usuario eliminado" + neutral avatar. Pattern already established by `account-deletion` SDD. |
| Per-linkId scoping creates duplicate-feeling reviews for re-established vínculos | Low | Accepted trade-off (locked decision #0). UX is intentional: a new vínculo is a new relationship. |
| `TrainerPublicProfile` dual-write overwrites CF aggregate | High if missed, Low if guarded | Hard guard: `averageRating` and `reviewCount` MUST NOT be in `UserRepository._trainerPublicFields`. CF Admin SDK writes only. Spec phase will codify this as an explicit invariant; design phase will encode in code review checklist. |
| CF cold start delays first aggregate update | Low | Acceptable — UI shows optimistic local state for the writer; other viewers see updated value within seconds. |
| Composite index missing at deploy time | Low | `firestore.indexes.json` added in PR#1; deploy via `firebase deploy --only firestore:indexes` documented in PR description. |

---

## Rollback Plan

- **PR#3 only**: revert the PR — discovery + profile return to stub state, reviews remain in DB and aggregate keeps updating silently. No data loss.
- **PR#2 only**: revert the PR — athletes lose write/edit UI but existing reviews persist and continue to drive aggregates. List tile + public profile display continues to work over historical data.
- **PR#1 (full rollback)**: revert all three PRs in reverse order, then:
  1. Disable CF: `firebase functions:delete reviewAggregate --region southamerica-east1`
  2. Optionally drop `/reviews` collection or leave for forensics
  3. `TrainerPublicProfile.averageRating` and `reviewCount` left in the model are safe (nullable / default 0) — no migration required

The Firestore composite index can remain in place even after rollback (cost is negligible and re-adding later is friction).

---

## Open Questions

1. **CF cold-start latency target** — is "best effort, typical <5s" acceptable, or do we need a documented SLO? Recommend: best-effort, no SLO for v1.
2. **Comment max length** — proposal locks 1–5 stars + optional comment but does not bound the comment string. Spec phase to lock (recommend 500 chars, validated client + CF).

---

## Success Criteria

- [ ] Athlete can leave a review via bottom sheet after terminating a vínculo (Trigger #1)
- [ ] Athlete sees the 30-day prompt at most once per linkId per device (Trigger #2 + spam gate)
- [ ] CF aggregate updates `averageRating + reviewCount` within ~5 seconds of write
- [ ] CF aggregate handles create, update, AND delete paths correctly (last-review-deleted → null avg, 0 count)
- [ ] `TrainerListTile` shows star + count when `reviewCount > 0`; renders cleanly with no row when `reviewCount == 0`
- [ ] `TrainerPublicProfileScreen` shows "RESEÑAS" section (empty state copy `Sin reseñas todavía` when none)
- [ ] Athlete sees "EDITAR MI RESEÑA" CTA on the public profile when they have an existing review for the active link
- [ ] Edit flow overwrites the same doc (deterministic id) — no duplicates
- [ ] Deleted athlete in `ReviewTile` shows "Usuario eliminado" + neutral avatar (no crash)
- [ ] `TrainerPublicProfile.averageRating` and `reviewCount` are NOT writable via `UserRepository` profile editor (dual-write guard)
- [ ] Firestore rules deny review writes from non-owner athletes; allow any-auth read
- [ ] All copy in es-AR with `// i18n: Fase 6 Etapa 7` markers
- [ ] `flutter analyze` 0 issues; `dart format .` clean; all tests passing
- [ ] CF Jest tests cover create / update / delete branches

---

## Non-Functional Requirements

- **TDD**: Strict TDD per project init — RED before GREEN for every public-API change
- **Copy**: es-AR, no neutral Spanish, no English literals in user-facing strings; markers `// i18n: Fase 6 Etapa 7`
- **Theming**: `AppPalette.of(context)` only — zero HEX literals; `TreinoIcon.X` only — no `PhosphorIcons.X` direct
- **Spacing**: 8/12/14/18/20 scale
- **Naming**: TREINO (brand), Coach (PF module), Entreno IA — NOT "Coach IA"
- **Out-of-scope guard**: no Ranking, Retos, Missions, Bets, Gamification
- **Commits**: conventional commits; NO Co-Authored-By / NO AI attribution
- **Region**: CF deployed to `southamerica-east1`
- **Tests**: `ProviderScope.overrides` + mocktail for repos; Jest + emulator for CF
- **Dependencies**: no new pub packages (`cloud_functions: ^5.2.0` already present)

---

## Dependencies

- `account-deletion` SDD must be merged (provides CF infra + "Usuario eliminado" fallback pattern) — already complete
- Firebase project on Blaze plan (already active for `deleteAccount` CF)
- `firebase deploy --only firestore:indexes,firestore:rules,functions` permissions for the deployer

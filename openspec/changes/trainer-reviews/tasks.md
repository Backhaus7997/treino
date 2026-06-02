# Tasks: trainer-reviews

**Change**: trainer-reviews
**Owner**: Backhaus
**Date**: 2026-06-02
**PRs**: 3 chained PRs against `main`
**Artifact store**: hybrid (file + Engram `sdd/trainer-reviews/tasks`)
**Phase**: Fase 6 Etapa 7

---

## Review Workload Forecast

| Field | PR#1 | PR#2 | PR#3 |
|---|---|---|---|
| Estimated changed lines | ~250 | ~300 | ~350 |
| 400-line budget risk | Low | Low | Low-Medium |
| Chained PRs recommended | Yes | Yes | Yes |
| Suggested split | standalone | depends on PR#1 | depends on PR#2 |
| Delivery strategy | chained-pr | chained-pr | chained-pr |
| Decision needed before apply | No | No | No |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Low-Medium (PR#3 highest)

Total: ~900 LOC across 3 PRs.

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| 1 | Review model + repo + CF aggregate + Firestore rules + indexes | PR#1 | base: main; ~250 LOC; standalone deploy |
| 2 | Athlete write/edit flow — notifier, widgets, trigger hooks | PR#2 | base: main, rebase after PR#1 merges; depends on PR#1 |
| 3 | Display — list tile badge, public profile RESEÑAS section, ReviewTile | PR#3 | base: main, rebase after PR#2 merges; depends on PR#2 |

---

## Risk Resolutions (pre-verified)

| Risk | Resolution |
|---|---|
| CF aggregate on delete | Covered by emulator integration test in PR#1 jest suite (delete-last → null+0) |
| 30-day spam gate | SharedPreferences per linkId, no Firestore cost (ADR-RV-006) |
| Dual-write guard | Regression test `_trainerPublicFields_excludes_aggregates` asserts `averageRating` + `reviewCount` absent (ADR-RV-005) |
| Deleted-athlete fallback | Reuse `userPublicProfileProvider` null → "Usuario eliminado" pattern from chat (ADR-RV-009) |
| Trigger #1 widget lifecycle | Dispose-safe `ProviderScope.containerOf` — capture container before await, mirrors `friend_request_inbox_tile.dart` |
| TrainerPublicProfile freezed regen | `dart run build_runner build --delete-conflicting-outputs` mandatory after model edit |
| Star icon registry | `TreinoIcon.starFill/starOutline` verified in PR#2 SETUP; added defensively if missing |
| Composite index missing at deploy | `firestore.indexes.json` shipped PR#1; deploy step noted in PR description |
| Trigger #2 double-fire on rebuild | `_promptCheckScheduled` widget guard + persistent prefs flag |
| CF retries on bad doc | catch + swallow; log only (no rethrow) |

---

## Branch + Base per PR

| PR# | Branch | Base |
|---|---|---|
| PR#1 | `feat/trainer-reviews-pr1-data-cf` | `main` |
| PR#2 | `feat/trainer-reviews-pr2-write-flow` | `main` (rebase after PR#1 merges) |
| PR#3 | `feat/trainer-reviews-pr3-display` | `main` (rebase after PR#2 merges) |

---

## PR#1 — Data + CF + Rules (~250 LOC)

**REQs covered**: REQ-RV-DATA-001..008, REQ-RV-CF-001..006, REQ-RV-CX-001, REQ-RV-CX-004
**SCENARIOs covered**: 571–594

### Phase 1.1: Review model + freezed

- [x] T01 — SETUP: create branch `feat/trainer-reviews-pr1-data-cf` from `main`; confirm clean working tree.
- [x] T02 — RED: create `test/features/reviews/domain/review_test.dart`; failing tests: `Review` has fields `id, linkId, athleteId, trainerId, rating, comment, createdAt, updatedAt`; `Review.idFor(linkId, athleteId)` returns `'${linkId}_${athleteId}'`; rating 0 and 6 are invalid values per model contract. (SCENARIO-571, 572)
- [x] T03 — GREEN: create `lib/features/reviews/domain/review.dart` — Freezed model with all 8 fields (`id String`, `linkId String`, `athleteId String`, `trainerId String`, `rating int` 1..5, `comment String?` ≤500, `createdAt Timestamp`, `updatedAt Timestamp`); static `idFor(linkId, athleteId)` helper; run `dart run build_runner build --delete-conflicting-outputs`; T02 must pass. (SCENARIO-571, 572)

### Phase 1.2: ReviewRepository + providers

- [x] T04 — RED: create `test/features/reviews/data/review_repository_test.dart`; failing tests using `fake_cloud_firestore`: `upsert` writes doc at deterministic id; `getForPair` returns null when absent and `Review` when present; `watchForTrainer` stream emits sorted by `createdAt DESC`; limit=10 respected. (SCENARIO-573, 574, 575, 576)
- [x] T05 — GREEN: create `lib/features/reviews/data/review_repository.dart` — `ReviewRepository` with `upsert(Review)` (set, merge=false at `reviews/${id}`), `getForPair(linkId, athleteId) → Future<Review?>`, `watchForLink(linkId, athleteId) → Stream<Review?>`, `watchForTrainer(trainerId, {int limit = 10}) → Stream<List<Review>>`; T04 must pass. (SCENARIO-573..576)
- [x] T06 — GREEN: create `lib/features/reviews/application/review_providers.dart` — `reviewRepositoryProvider` (Provider), `userReviewForLinkProvider(linkId)` (StreamProvider.autoDispose.family<Review?, String>), `trainerReviewsProvider(trainerId)` (StreamProvider.autoDispose.family<List<Review>, String> limit 10). (SCENARIO-577)

### Phase 1.3: TrainerPublicProfile aggregate fields + dual-write guard

- [x] T07 — RED: create/extend `test/features/profile/data/user_repository_test.dart`; failing test: `_trainerPublicFields_excludes_aggregates` — assert `averageRating` and `reviewCount` are NOT present in the whitelist set exposed by `UserRepository._trainerPublicFields`. (SCENARIO-578)
- [x] T08 — GREEN: edit `lib/features/coach/domain/trainer_public_profile.dart` — add `double? averageRating` and `@Default(0) int reviewCount`; run `dart run build_runner build --delete-conflicting-outputs`; edit `lib/features/profile/data/user_repository.dart` — confirm `_trainerPublicFields` excludes both fields; add inline comment `// ADR-RV-005: CF-write-only — do not add averageRating or reviewCount here`; T07 must pass. (SCENARIO-578, 579)

### Phase 1.4: Firestore rules + indexes

- [x] T09 — RED: create `test/firestore/reviews_rules_test.ts` (or extend existing rules tests); failing emulator-backed tests: any authenticated user can read a review doc (SCENARIO-580); athlete can create own review with valid rating 1..5 and comment ≤500 (SCENARIO-581); athlete cannot create review for another athlete (SCENARIO-582); update is allowed for owner on `rating/comment/updatedAt` only (SCENARIO-583); delete is always denied (SCENARIO-584); rating 0 and 6 are rejected by rules (SCENARIO-585).
- [x] T10 — GREEN: edit `firestore.rules` — add `/reviews/{reviewId}` block: `allow read: if request.auth != null`; `allow create: if request.auth.uid == request.resource.data.athleteId && request.resource.data.rating >= 1 && request.resource.data.rating <= 5 && request.resource.data.comment.size() <= 500`; `allow update: if request.auth.uid == resource.data.athleteId && request.resource.data.keys().hasOnly(['rating','comment','updatedAt'])`; `allow delete: if false`; T09 must pass. (SCENARIO-580..585)
- [x] T11 — GREEN: edit `firestore.indexes.json` — add composite index `collection: reviews, fields: [{trainerId ASC}, {createdAt DESC}]`; no other changes to this file. (SCENARIO-586)

### Phase 1.5: CF reviewAggregate + emulator tests

- [x] T12 — RED: create `functions/src/__tests__/review-aggregate.test.ts`; failing emulator-backed jest tests: first review created → `averageRating` updated on `trainerPublicProfiles/{trainerId}` (SCENARIO-587); second review added → average recomputed correctly (SCENARIO-588); review updated with new rating → average recomputed (SCENARIO-589); review deleted, others remain → average recomputed (SCENARIO-590); last review deleted → `averageRating: null, reviewCount: 0` (SCENARIO-591); CF re-fires with same data → idempotent result (SCENARIO-592); `trainerPublicProfiles/{trainerId}` doc missing → warn + no-op, no throw (SCENARIO-593); doc with no `trainerId` field → early return (SCENARIO-594).
- [x] T13 — GREEN: create `functions/src/review-aggregate.ts` — export `reviewAggregate` (`onDocumentWritten({ document: 'reviews/{reviewId}', region: 'southamerica-east1' })`): extract `trainerId` from `after ?? before`; if absent → `logger.warn` + return; call `recomputeAggregate(app, trainerId)`; export `recomputeAggregate(app, trainerId)`: query `reviews` where `trainerId == X`, reduce to `count + sumRatings`, build payload (`count==0 → {averageRating: null, reviewCount: 0}`), check profile exists (missing → `logger.warn` + return), `set(merge:true)`; catch all → `logger.error` + no rethrow; T12 must pass. (SCENARIO-587..594)
- [x] T14 — GREEN: edit `functions/src/index.ts` — add `export { reviewAggregate } from './review-aggregate';`. (SCENARIO-587)

### Phase 1.6: PR#1 quality gates

- [x] T15 — GATE: `npm --prefix functions run build` — TypeScript compilation 0 errors.
- [x] T16 — GATE: `npm --prefix functions run lint` — ESLint 0 warnings/errors.
- [x] T17 — GATE: `firebase emulators:exec --only firestore,auth "npm --prefix functions test"` — all PR#1 jest tests pass (SCENARIO-587..594 covered).
- [x] T18 — GATE: `flutter analyze` 0 issues; `dart format --output=none --set-exit-if-changed .` 0 changed; `flutter test` all passing; delta ≥ +6 tests vs pre-PR#1 baseline.
- [x] T19 — VERIFY: `rg "averageRating\|reviewCount" lib/features/profile/data/user_repository.dart` — confirm no occurrence in `_trainerPublicFields` whitelist; `firestore.rules` only contains a new `/reviews/{reviewId}` block (no other blocks modified); `firestore.indexes.json` only adds the `(trainerId, createdAt)` composite; `storage.rules` unchanged; 0 hex literals in new Dart files; all Dart icons via `TreinoIcon.X`.

---

## PR#2 — Athlete Write/Edit Flow (~300 LOC)

**REQs covered**: REQ-RV-WRITE-001..006, REQ-RV-CX-001..004
**SCENARIOs covered**: 595–610, 615–618 (CX)

### Phase 2.1: ReviewNotifier

- [x] T20 — SETUP: create branch `feat/trainer-reviews-pr2-write-flow` from post-PR#1 `main`; confirm clean rebase.
- [x] T21 — RED: create `test/features/reviews/application/review_notifier_test.dart`; failing tests with mocked `ReviewRepository`: `submit` with `rating==0` throws `ArgumentError` before calling repo (SCENARIO-595); `submit` with `comment.length > 500` throws `ArgumentError` (SCENARIO-596); valid `submit` calls `upsert` with correct `Review.idFor` id and `updatedAt` set (SCENARIO-597); success → state `AsyncData(null)` (SCENARIO-598); repo throws → state `AsyncError` (SCENARIO-599).
- [x] T22 — GREEN: create `lib/features/reviews/application/review_notifier.dart` — `ReviewNotifier extends AsyncNotifier<void>` with `submit({required String linkId, required String trainerId, required int rating, String? comment, Review? existing})`; validates rating 1..5 and comment ≤500; calls `ReviewRepository.upsert(review)`; maps errors; register `reviewNotifierProvider` as `AsyncNotifierProvider`; T21 must pass. (SCENARIO-595..599)

### Phase 2.2: StarRatingInput widget

- [x] T23 — SETUP: verify `TreinoIcon.starFill` and `TreinoIcon.starOutline` exist in `lib/core/icons/treino_icon.dart` (or equivalent registry file); if either is missing, add the wrapper constant pointing to the correct `PhosphorIcons` icon in this PR's SETUP before any widget work. (SCENARIO-600)
- [x] T24 — RED: create `test/features/reviews/presentation/star_rating_input_test.dart`; failing widget tests: renders 5 star icons; tapping star 3 calls `onRatingChanged(3)` (SCENARIO-600); initial `rating==0` → all outline stars; `rating==4` → 4 filled + 1 outline; icons are `TreinoIcon.starFill/starOutline` (no PhosphorIcons direct). (SCENARIO-600)
- [x] T25 — GREEN: create `lib/features/reviews/presentation/widgets/star_rating_input.dart` — `StarRatingInput({required int rating, required ValueChanged<int> onRatingChanged})`; 5 `GestureDetector`-wrapped icons from `TreinoIcon.starFill/starOutline`; colors via `AppPalette.of(context)`; all spacing from scale 8/12/14/18/20; T24 must pass. (SCENARIO-600)

### Phase 2.3: ReviewBottomSheet (new + edit variants)

- [x] T26 — RED: create `test/features/reviews/presentation/review_bottom_sheet_test.dart`; failing widget tests: new-review variant shows title with trainer name (SCENARIO-601); 30-day variant shows different title (SCENARIO-601); edit variant shows "Editá tu reseña" title and pre-fills stars + comment (SCENARIO-602); ENVIAR disabled when `rating==0` (SCENARIO-603); ENVIAR enabled once a star is tapped (SCENARIO-603); submitting shows spinner (SCENARIO-604); success → sheet pops + snackbar "¡Gracias por tu reseña!" (SCENARIO-605); error → snackbar "No pudimos guardar..." no auto-retry (SCENARIO-606); CANCELAR pops sheet (SCENARIO-607); comment field has `maxLength: 500` counter visible (SCENARIO-608). All strings tagged `// i18n: Fase 6 Etapa 7`.
- [x] T27 — GREEN: create `lib/features/reviews/presentation/widgets/review_bottom_sheet.dart` — `ReviewBottomSheet({required String linkId, required String trainerId, required String trainerName, Review? existing, required ReviewTriggerVariant triggerVariant})`; drag handle; `StarRatingInput` hydrated from `existing?.rating ?? 0`; `TextField` `maxLength: 500` + counter; ENVIAR disabled until `rating > 0`, spinner while `AsyncLoading`; success → `Navigator.pop` + SnackBar; error → SnackBar, no retry; CANCELAR → `Navigator.pop`; title branches on `existing != null` → edit → `triggerVariant == thirtyDay` → 30-day → default; all copy strings marked `// i18n: Fase 6 Etapa 7`; colors via `AppPalette.of(context)`; T26 must pass. (SCENARIO-601..608)

### Phase 2.4: Trigger #1 — post-termination hook

- [x] T28 — RED: extend or create `test/features/coach/presentation/athlete_coach_view_test.dart`; failing widget test: after `_onTerminate()` succeeds (mock), `ReviewBottomSheet` is shown via `showModalBottomSheet` (SCENARIO-609); container captured before await (dispose-safe — no `BuildContext` after async gap). (SCENARIO-609)
- [x] T29 — GREEN: edit `lib/features/coach/athlete_coach_view.dart` — convert to `ConsumerStatefulWidget` if not already; in `_ActionRow._onTerminate()`: capture `final container = ProviderScope.containerOf(context, listen: false)` BEFORE the `await terminate()` call; after await success: read trainer name + existing review from container; call `showModalBottomSheet` with `ReviewBottomSheet`; T28 must pass. (SCENARIO-609)

### Phase 2.5: Trigger #2 — 30-day check

- [x] T30 — RED: extend `test/features/coach/presentation/athlete_coach_view_test.dart`; failing tests: active link + `acceptedAt` ≥30 days ago + no existing review + prefs flag absent → sheet shown on first frame (SCENARIO-610); prefs flag set → sheet NOT shown (SCENARIO-610); no active link → sheet NOT shown; `_promptCheckScheduled` prevents double-fire within same widget lifetime. (SCENARIO-610)
- [x] T31 — GREEN: in `_AthleteCoachViewState.initState`: add `addPostFrameCallback` → `_maybeShow30DayPrompt()`; checks: active link + `acceptedAt != null` + `daysSinceAcceptance >= 30` + `existing == null` + `!prefs.getBool('review_prompt_shown_${linkId}')` (key `review_prompt_shown_{linkId}`); set flag BEFORE sheet opens (covers cancel path); `_promptCheckScheduled` guard prevents intra-lifetime double-fire; T30 must pass. (SCENARIO-610)

### Phase 2.6: Edit CTA in TrainerPublicProfileScreen

- [x] T32 — RED: create/extend `test/features/coach/presentation/trainer_public_profile_screen_test.dart`; failing test: when `userReviewForLinkProvider` emits non-null review, "EDITAR MI RESEÑA" CTA is visible (SCENARIO-611); when null, "DEJAR UNA RESEÑA" CTA is visible (SCENARIO-611). Strings tagged `// i18n: Fase 6 Etapa 7`.
- [x] T33 — GREEN: edit `lib/features/coach/presentation/widgets/trainer_contact_cta.dart` — watch `userReviewForLinkProvider(linkId)`; branch on non-null → show "EDITAR MI RESEÑA" button that opens `ReviewBottomSheet` with `existing`; null → show "DEJAR UNA RESEÑA"; edit `lib/features/coach/presentation/trainer_public_profile_screen.dart` — pass `linkId` to CTA, wire existing-review state; all strings tagged `// i18n: Fase 6 Etapa 7`; T32 must pass. (SCENARIO-611)

### Phase 2.7: PR#2 quality gates

- [x] T34 — GATE: `flutter analyze` 0 issues; `dart format --output=none --set-exit-if-changed .` 0 changed.
- [x] T35 — GATE: `flutter test` — all passing; delta ≥ +20 tests vs PR#1 baseline (covering SCENARIO-595..611).
- [x] T36 — VERIFY: `TreinoIcon.starFill` and `TreinoIcon.starOutline` exist and are used in star widgets (no `PhosphorIcons` direct); 0 hex literals; all user-facing strings have `// i18n: Fase 6 Etapa 7` marker; `ProviderScope.containerOf` captured before `await` in Trigger #1; `_promptCheckScheduled` guard present; no `pubspec.yaml` changes; conventional commits only.

---

## PR#3 — Display (~350 LOC)

**REQs covered**: REQ-RV-DISPLAY-001..004, REQ-RV-CX-001..004
**SCENARIOs covered**: 612–618

### Phase 3.1: StarRatingDisplay widget

- [x] T37 — SETUP: create branch `feat/trainer-reviews-pr3-display` from post-PR#2 `main`; confirm clean rebase.
- [x] T38 — RED: create `test/features/reviews/presentation/star_rating_display_test.dart`; failing tests: renders 5 read-only star icons; `rating==4.7` → 4 filled + 1 outline; `rating==null` → all outline or hidden per spec; icons from `TreinoIcon.starFill/starOutline` only. (SCENARIO-612)
- [x] T39 — GREEN: create `lib/features/reviews/presentation/widgets/star_rating_display.dart` — `StarRatingDisplay({double? rating, int? count})`; 5 non-interactive icons from `TreinoIcon.starFill/starOutline`; fill threshold `>= i` (1-indexed); colors via `AppPalette.of(context)`; T38 must pass. (SCENARIO-612)

### Phase 3.2: ReviewTile + deleted-athlete fallback

- [x] T40 — RED: create `test/features/reviews/presentation/review_tile_test.dart`; failing tests: renders athlete avatar + name + `StarRatingDisplay` + comment + relative date (SCENARIO-613); `userPublicProfileProvider(athleteId)` returns null → renders "Usuario eliminado" + neutral avatar (SCENARIO-614); comment absent → comment row hidden. (SCENARIO-613, 614)
- [x] T41 — GREEN: create `lib/features/reviews/presentation/widgets/review_tile.dart` — `ReviewTile({required Review review})`; watches `userPublicProfileProvider(review.athleteId)`; null profile → "Usuario eliminado" fallback (string tagged `// i18n: Fase 6 Etapa 7`); renders `StarRatingDisplay(rating: review.rating.toDouble())`; relative date formatting; T40 must pass. (SCENARIO-613, 614)

### Phase 3.3: TrainerReviewsSection

- [x] T42 — RED: create `test/features/reviews/presentation/trainer_reviews_section_test.dart`; failing tests: renders "RESEÑAS" header (SCENARIO-615); `trainerReviewsProvider` empty → renders "Sin reseñas todavía" muted text (SCENARIO-615); non-empty → list of `ReviewTile` widgets ≤10; string constants tagged `// i18n: Fase 6 Etapa 7`. (SCENARIO-615)
- [x] T43 — GREEN: create `lib/features/reviews/presentation/widgets/trainer_reviews_section.dart` — `TrainerReviewsSection({required String trainerId})`; watches `trainerReviewsProvider(trainerId)`; header "RESEÑAS"; empty state "Sin reseñas todavía" in muted color via `AppPalette.of(context)`; list of `ReviewTile`; spacing from scale; T42 must pass. (SCENARIO-615)

### Phase 3.4: TrainerListTile star + count row

- [x] T44 — RED: create/extend `test/features/coach/presentation/trainer_list_tile_test.dart`; failing tests: `reviewCount > 0` → star + avg + count row visible with `StarRatingDisplay` (SCENARIO-616); `reviewCount == 0` → star row hidden (SCENARIO-616); count label uses singular/plural copy tagged `// i18n: Fase 6 Etapa 7`. (SCENARIO-616)
- [x] T45 — GREEN: edit `lib/features/coach/presentation/widgets/trainer_list_tile.dart` — add conditional row: when `profile.reviewCount > 0` show `StarRatingDisplay(rating: profile.averageRating)` + formatted avg + count label; hidden when `reviewCount == 0` (ADR-RV-010); all strings tagged `// i18n: Fase 6 Etapa 7`; T44 must pass. (SCENARIO-616)

### Phase 3.5: TrainerStatsRow refactor

- [x] T46 — RED: create/extend `test/features/coach/presentation/trainer_stats_row_test.dart`; failing tests: `reviewCount == 0` → RESEÑAS slot shows "—" placeholder (SCENARIO-617); `averageRating == 4.7` → shows "4.7" formatted to 1 decimal; `reviewCount == 3` → shows "3 reseñas". (SCENARIO-617)
- [x] T47 — GREEN: edit `lib/features/coach/presentation/widgets/trainer_stats_row.dart` — accept `TrainerPublicProfile profile` param (or ensure it is already passed); wire RESEÑAS slot to `profile.averageRating?.toStringAsFixed(1) ?? '—'`; T46 must pass. (SCENARIO-617)

### Phase 3.6: TrainerPublicProfileScreen integration

- [x] T48 — RED: extend `test/features/coach/presentation/trainer_public_profile_screen_test.dart`; failing test: `TrainerReviewsSection` is present in the widget tree below the CTA area; `TrainerStatsRow` is wired to `TrainerPublicProfile` with reviews data. (SCENARIO-618)
- [x] T49 — GREEN: edit `lib/features/coach/presentation/trainer_public_profile_screen.dart` — add `TrainerReviewsSection(trainerId: profile.uid)` below the existing CTA section; ensure `TrainerStatsRow` receives the full `TrainerPublicProfile`; T48 must pass. (SCENARIO-618)

### Phase 3.7: PR#3 quality gates

- [x] T50 — GATE: `flutter analyze` 0 issues; `dart format --output=none --set-exit-if-changed .` 0 changed.
- [x] T51 — GATE: `flutter test` — all passing; delta ≥ +25 tests vs PR#2 baseline (covering SCENARIO-612..618). Delta: +62 (1528 vs 1466).
- [x] T52 — VERIFY: 0 hex literals; 0 `PhosphorIcons` direct; all user-facing strings have `// i18n: Fase 6 Etapa 7` marker; `TrainerListTile` star row hidden when `reviewCount == 0`; "Usuario eliminado" fallback present in `ReviewTile`; "Sin reseñas todavía" present in `TrainerReviewsSection`; no `pubspec.yaml` changes; `storage.rules` unchanged; conventional commits only.

---

## Coverage Matrix: REQ → Tasks → SCENARIOs

| REQ | Tasks | SCENARIOs |
|---|---|---|
| REQ-RV-DATA-001 | T02, T03 | 571, 572 |
| REQ-RV-DATA-002 | T02, T03 | 572 |
| REQ-RV-DATA-003 | T04, T05 | 573, 574 |
| REQ-RV-DATA-004 | T04, T05 | 574 |
| REQ-RV-DATA-005 | T04, T05 | 575, 576 |
| REQ-RV-DATA-006 | T07, T08 | 578, 579 |
| REQ-RV-DATA-007 | T09, T10 | 580, 581, 582, 583, 584, 585 |
| REQ-RV-DATA-008 | T11 | 586 |
| REQ-RV-CF-001 | T12, T13, T14 | 587 |
| REQ-RV-CF-002 | T12, T13 | 587, 588 |
| REQ-RV-CF-003 | T12, T13 | 589 |
| REQ-RV-CF-004 | T12, T13 | 590, 591 |
| REQ-RV-CF-005 | T12, T13 | 592 |
| REQ-RV-CF-006 | T12, T13 | 593, 594 |
| REQ-RV-WRITE-001 | T06, T21, T22 | 577, 595 |
| REQ-RV-WRITE-002 | T21, T22 | 595, 596, 597, 598, 599 |
| REQ-RV-WRITE-003 | T26, T27 | 601, 602, 603, 604, 605, 606, 607, 608 |
| REQ-RV-WRITE-004 | T28, T29 | 609 |
| REQ-RV-WRITE-005 | T30, T31 | 610 |
| REQ-RV-WRITE-006 | T32, T33 | 611 |
| REQ-RV-DISPLAY-001 | T44, T45 | 616 |
| REQ-RV-DISPLAY-002 | T42, T43, T48, T49 | 615, 618 |
| REQ-RV-DISPLAY-003 | T40, T41 | 613, 614 |
| REQ-RV-DISPLAY-004 | T46, T47 | 617 |
| REQ-RV-CX-001 | All RED/GREEN task pairs | 615 |
| REQ-RV-CX-002 | T19, T36, T52 (VERIFY steps) | 616 |
| REQ-RV-CX-003 | T27, T33, T41, T43, T45, T47 (i18n markers) | 617 |
| REQ-RV-CX-004 | All tasks (conventional commits, no AI attribution) | 618 |

---

## Pre-PR Checklist per PR

### PR#1 — Data + CF + Rules
- [x] T01..T19 all marked complete
- [x] Quality gates T15..T19 passed
- [x] `dart run build_runner build --delete-conflicting-outputs` run after Review + TrainerPublicProfile edits
- [x] TypeScript compilation 0 errors (T15)
- [x] ESLint 0 warnings/errors (T16)
- [x] All 8 jest emulator tests pass (SCENARIO-587..594) (T17) — 49/49 total (+8 vs baseline 41)
- [x] `_trainerPublicFields_excludes_aggregates` test passing (T07)
- [x] `firestore.rules` only adds `/reviews/{reviewId}` block — no other block modified (T19)
- [x] `firestore.indexes.json` only adds `(trainerId, createdAt)` composite (T11)
- [x] `storage.rules` unchanged
- [x] 0 hex literals in new Dart files; all icons via `TreinoIcon.X` (N/A — no UI in PR#1)
- [x] Conventional commits only; no Co-Authored-By

### PR#2 — Athlete Write/Edit Flow
- [x] T20..T36 all marked complete
- [x] Quality gates T34..T36 passed
- [x] Rebase on post-PR#1 main confirmed clean (T20)
- [x] `TreinoIcon.starFill/starOutline` exist and used exclusively (T23)
- [x] `ProviderScope.containerOf` captured BEFORE `await` in Trigger #1 (T29)
- [x] `review_prompt_shown_{linkId}` prefs flag set before sheet opens (T31)
- [x] `_promptCheckScheduled` guard present in `_AthleteCoachViewState` (T31)
- [x] All user-facing strings tagged `// i18n: Fase 6 Etapa 7`
- [x] `shared_preferences: ^2.3.0` added (needed for T31 — was absent from pubspec)
- [x] `storage.rules` unchanged
- [x] Conventional commits only; no Co-Authored-By

### PR#3 — Display
- [x] T37..T52 all marked complete
- [x] Quality gates T50..T52 passed
- [x] Rebase on post-PR#2 main confirmed clean (T37)
- [x] `TrainerListTile` star row hidden when `reviewCount == 0` (T45)
- [x] "Usuario eliminado" fallback in `ReviewTile` (T41)
- [x] "Sin reseñas todavía" empty state in `TrainerReviewsSection` (T43)
- [x] `TrainerStatsRow` shows "—" when `reviewCount == 0` (T47)
- [x] `TrainerReviewsSection` integrated in `TrainerPublicProfileScreen` (T49)
- [x] All user-facing strings tagged `// i18n: Fase 6 Etapa 7`
- [x] No `pubspec.yaml` changes
- [x] `storage.rules` unchanged
- [x] Conventional commits only; no Co-Authored-By

---

## Hard Constraints

1. CF deploys to `southamerica-east1`.
2. NO modifications to `storage.rules`.
3. `firestore.rules` ONLY adds the `/reviews/{reviewId}` block — no other block touched.
4. `firestore.indexes.json` ONLY adds the `(trainerId ASC, createdAt DESC)` composite index.
5. NO new Freezed models beyond `Review` + `TrainerPublicProfile` field addition.
6. NO new packages in `pubspec.yaml`.
7. All Flutter colors via `AppPalette.of(context)` — no hex literals.
8. All Flutter icons via `TreinoIcon.X` — verify `starFill/starOutline` exist in PR#2 SETUP (T23).
9. Spacing scale only: 8 / 12 / 14 / 18 / 20.
10. Strict TDD: RED commit BEFORE GREEN commit per task pair — enforced by REQ-RV-CX-001.
11. Every user-facing string gets `// i18n: Fase 6 Etapa 7` marker comment.
12. Conventional commits only — NO Co-Authored-By, NO AI attribution.
13. CF tests run against Firebase Local Emulator Suite (Firestore + Auth) — NOT production.
14. `_trainerPublicFields` dual-write guard test (`_trainerPublicFields_excludes_aggregates`) must remain passing across all PRs.
15. `dart run build_runner build --delete-conflicting-outputs` required after any edit to `review.dart` or `trainer_public_profile.dart`.

---

## Artifacts

- File: `openspec/changes/trainer-reviews/tasks.md`
- Engram: `sdd/trainer-reviews/tasks`

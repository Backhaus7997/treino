# Spec: trainer-reviews

**Change**: trainer-reviews
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-02
**Phase**: Fase 6 Etapa 7
**Artifact store**: hybrid (file + Engram `sdd/trainer-reviews/spec`)
**Proposal ref**: `openspec/changes/trainer-reviews/proposal.md`
**Scenario range**: SCENARIO-571..610

---

## Overview

Three capability areas delivered across 3 chained PRs:
1. `trainer-reviews` — Review data model + repo + CF aggregate + Firestore rules + indexes (PR#1)
2. `coach-vinculo-lifecycle` (modified) — Athlete write/edit flow, `ReviewBottomSheet`, trigger hooks (PR#2)
3. `coach-discovery` (modified) — Discovery list tile badge, public profile "RESEÑAS" section, `ReviewTile` (PR#3)

`trainer-reviews` is NEW. `coach-discovery` and `coach-vinculo-lifecycle` are MODIFIED capabilities.

All capabilities: NEW specs (no existing spec files to delta against for the new domain; modified capabilities receive delta treatment below).

---

## Requirements

---

### REQ-RV-DATA-001 — Review Freezed Model

The system MUST expose a `Review` Freezed/json_serializable model with fields: `id (String)`, `linkId (String)`, `athleteId (String)`, `trainerId (String)`, `rating (int)`, `comment (String?, nullable)`, `createdAt (DateTime)`, `updatedAt (DateTime)`. `rating` MUST be constrained to the range 1..5 (validated at the application layer before persistence). `comment` MUST be nullable and, when present, MUST NOT exceed 500 characters.

#### SCENARIO-571: Review model round-trips through JSON serialization
- **Given** a `Review` object with all fields populated (rating=4, comment="Great!")
- **When** it is serialized to JSON and deserialized back
- **Then** the resulting object equals the original in all fields
- **Test target**: `test/features/reviews/domain/review_test.dart`
- **REQ**: REQ-RV-DATA-001

#### SCENARIO-572: Review model accepts null comment
- **Given** a `Review` object constructed with `comment: null`
- **When** it is serialized to JSON
- **Then** the JSON does not include the `comment` key (or includes it as `null`)
- **And** deserialization reconstructs `comment` as `null`
- **Test target**: `test/features/reviews/domain/review_test.dart`
- **REQ**: REQ-RV-DATA-001

---

### REQ-RV-DATA-002 — Deterministic Review Document ID

The review document id MUST be computed as `${linkId}_${athleteId}`. This id MUST be used as the Firestore document path under `/reviews/{reviewId}`. This determinism MUST guarantee at most one review per athlete per link (overwrite = edit).

#### SCENARIO-573: Deterministic id matches expected pattern
- **Given** a `linkId` of `"abc123"` and an `athleteId` of `"uid456"`
- **When** the ReviewRepository constructs the document id for upsert
- **Then** the Firestore write targets `/reviews/abc123_uid456`
- **Test target**: `test/features/reviews/data/review_repository_test.dart`
- **REQ**: REQ-RV-DATA-002

---

### REQ-RV-DATA-003 — ReviewRepository upsert

`ReviewRepository` MUST expose `Future<void> upsert(Review review)` that writes the review to `/reviews/${review.id}` using `set()` with merge semantics. A second call with the same id MUST overwrite `rating`, `comment`, and `updatedAt` without creating a duplicate.

#### SCENARIO-574: upsert creates review on first call
- **Given** no document exists at `/reviews/abc123_uid456`
- **When** `ReviewRepository.upsert(review)` is called
- **Then** the document is created with the correct fields
- **Test target**: `test/features/reviews/data/review_repository_test.dart`
- **REQ**: REQ-RV-DATA-003

#### SCENARIO-575: upsert overwrites existing review on second call
- **Given** a document already exists at `/reviews/abc123_uid456` with `rating=3`
- **When** `ReviewRepository.upsert(review.copyWith(rating: 5))` is called
- **Then** the same document now has `rating=5` and no duplicate document exists
- **Test target**: `test/features/reviews/data/review_repository_test.dart`
- **REQ**: REQ-RV-DATA-003

---

### REQ-RV-DATA-004 — ReviewRepository getForPair

`ReviewRepository` MUST expose `Future<Review?> getForPair(String linkId, String athleteId)` that fetches `/reviews/${linkId}_${athleteId}` and returns `null` when the document does not exist.

#### SCENARIO-576: getForPair returns null when review absent
- **Given** no review document exists for `linkId="abc"` and `athleteId="uid"`
- **When** `ReviewRepository.getForPair("abc", "uid")` is called
- **Then** the method returns `null` without throwing
- **Test target**: `test/features/reviews/data/review_repository_test.dart`
- **REQ**: REQ-RV-DATA-004

#### SCENARIO-577: getForPair returns review when present
- **Given** a review document exists at `/reviews/abc_uid`
- **When** `ReviewRepository.getForPair("abc", "uid")` is called
- **Then** the method returns a `Review` object with matching fields
- **Test target**: `test/features/reviews/data/review_repository_test.dart`
- **REQ**: REQ-RV-DATA-004

---

### REQ-RV-DATA-005 — ReviewRepository watchForTrainer

`ReviewRepository` MUST expose `Stream<List<Review>> watchForTrainer(String trainerId)` that returns a live stream of all reviews for the given trainer, sorted by `createdAt DESC`. The stream MUST emit updated lists on real-time Firestore changes.

#### SCENARIO-578: watchForTrainer emits updated list on new review
- **Given** a stream is open for `trainerId="trainerX"`
- **When** a new review document with `trainerId="trainerX"` is written to Firestore
- **Then** the stream emits a new list containing the new review
- **Test target**: `test/features/reviews/data/review_repository_test.dart`
- **REQ**: REQ-RV-DATA-005

#### SCENARIO-579: watchForTrainer emits empty list when no reviews
- **Given** no review documents exist for `trainerId="trainerX"`
- **When** `watchForTrainer("trainerX")` is called
- **Then** the stream immediately emits an empty list
- **Test target**: `test/features/reviews/data/review_repository_test.dart`
- **REQ**: REQ-RV-DATA-005

---

### REQ-RV-DATA-006 — TrainerPublicProfile Aggregate Fields

`TrainerPublicProfile` Freezed model MUST gain two new fields: `averageRating (double?, nullable, @Default(null))` and `reviewCount (int, @Default(0))`. These fields MUST be present in the model's `fromJson`/`toJson`. They MUST NOT appear in `UserRepository._trainerPublicFields` — they are owned exclusively by the CF via Admin SDK.

#### SCENARIO-580: TrainerPublicProfile deserializes aggregate fields from Firestore snapshot
- **Given** a Firestore `trainerPublicProfiles/{uid}` document with `averageRating: 4.5` and `reviewCount: 12`
- **When** `TrainerPublicProfile.fromJson(snapshot.data())` is called
- **Then** the resulting object has `averageRating == 4.5` and `reviewCount == 12`
- **Test target**: `test/features/coach/domain/trainer_public_profile_test.dart`
- **REQ**: REQ-RV-DATA-006

#### SCENARIO-581: Dual-write guard — _trainerPublicFields excludes aggregate fields
- **Given** the `UserRepository._trainerPublicFields` constant or map
- **When** its keys are inspected
- **Then** neither `averageRating` nor `reviewCount` appear in the list
- **Test target**: `test/features/coach/data/user_repository_test.dart`
- **REQ**: REQ-RV-DATA-006

---

### REQ-RV-DATA-007 — Firestore Rules for /reviews/{reviewId}

`firestore.rules` MUST include a `/reviews/{reviewId}` block with:
- `read`: any authenticated user (`request.auth != null`)
- `create`: `request.auth.uid == request.resource.data.athleteId` AND `linkId` maps to an existing `trainer_links` document with `status in ['active', 'terminated']`
- `update`: `request.auth.uid == resource.data.athleteId` AND only `{rating, comment, updatedAt}` fields changed
- `delete`: `false` (reviews are immutable except via account-deletion CF)

#### SCENARIO-582: Authenticated user can read any review
- **Given** a review document exists and the caller is authenticated
- **When** a Firestore read is attempted on `/reviews/{reviewId}`
- **Then** the read is allowed
- **Test target**: Firestore rules test (emulator)
- **REQ**: REQ-RV-DATA-007

#### SCENARIO-583: Athlete can create review for their own active/terminated link
- **Given** caller is authenticated as `athleteId="uid"` and `trainer_links/{linkId}` has `athleteId="uid"` and `status="active"`
- **When** a create is attempted with `request.resource.data.athleteId="uid"`
- **Then** the create is allowed
- **Test target**: Firestore rules test (emulator)
- **REQ**: REQ-RV-DATA-007

#### SCENARIO-584: Athlete cannot create review for another athlete's link
- **Given** caller is authenticated as `uid="A"` but `request.resource.data.athleteId="B"`
- **When** a create is attempted
- **Then** the create is denied
- **Test target**: Firestore rules test (emulator)
- **REQ**: REQ-RV-DATA-007

#### SCENARIO-585: Athlete can update only rating/comment/updatedAt
- **Given** a review owned by `athleteId="uid"` exists and the caller is `uid`
- **When** an update only changes `rating`, `comment`, and `updatedAt`
- **Then** the update is allowed
- **Test target**: Firestore rules test (emulator)
- **REQ**: REQ-RV-DATA-007

#### SCENARIO-586: Delete is always denied
- **Given** any authenticated caller (including the owner athlete)
- **When** a delete is attempted on `/reviews/{reviewId}`
- **Then** the delete is denied
- **Test target**: Firestore rules test (emulator)
- **REQ**: REQ-RV-DATA-007

---

### REQ-RV-DATA-008 — Firestore Composite Index

`firestore.indexes.json` MUST include a composite index on the `reviews` collection with fields `trainerId ASC` and `createdAt DESC` to support the `watchForTrainer` query.

#### SCENARIO-587: watchForTrainer query executes without missing-index error
- **Given** the composite index `(trainerId ASC, createdAt DESC)` is deployed to the emulator
- **When** `ReviewRepository.watchForTrainer(trainerId)` is called
- **Then** the query returns results without a Firestore index error
- **Test target**: `test/features/reviews/data/review_repository_test.dart` (emulator)
- **REQ**: REQ-RV-DATA-008

---

### REQ-RV-CF-001 — reviewAggregate Cloud Function

The project MUST include a new Cloud Function `reviewAggregate` deployed in `southamerica-east1`, triggered by `onDocumentWritten("reviews/{reviewId}")`. It MUST be exported from `functions/src/index.ts`.

#### SCENARIO-588: CF triggers on review document write
- **Given** the emulator is running with `reviewAggregate` registered
- **When** a review document is written to `/reviews/{reviewId}`
- **Then** the CF handler executes without startup error
- **Test target**: `functions/test/review-aggregate.test.ts` (Jest + emulator)
- **REQ**: REQ-RV-CF-001

---

### REQ-RV-CF-002 — Aggregate Recomputation on Create

On a review document create event, the CF MUST query all reviews for the affected `trainerId`, compute the new `averageRating` (arithmetic mean, rounded to 2 decimal places) and `reviewCount`, then write both to `trainerPublicProfiles/{trainerId}` via Admin SDK.

#### SCENARIO-589: averageRating and reviewCount updated on first review
- **Given** `trainerPublicProfiles/{trainerId}` has `reviewCount: 0` and `averageRating: null`
- **When** a review with `rating=4` is created for that trainer
- **Then** `trainerPublicProfiles/{trainerId}` is updated to `averageRating: 4.0, reviewCount: 1`
- **Test target**: `functions/test/review-aggregate.test.ts`
- **REQ**: REQ-RV-CF-002

#### SCENARIO-590: averageRating recomputed correctly on second review
- **Given** one existing review with `rating=4` for a trainer
- **When** a second review with `rating=2` is created
- **Then** `trainerPublicProfiles/{trainerId}` is updated to `averageRating: 3.0, reviewCount: 2`
- **Test target**: `functions/test/review-aggregate.test.ts`
- **REQ**: REQ-RV-CF-002

---

### REQ-RV-CF-003 — Aggregate Recomputation on Update

On a review document update event, the CF MUST recompute `averageRating` and `reviewCount` using all current reviews (not the delta) and update `trainerPublicProfiles/{trainerId}`.

#### SCENARIO-591: averageRating updated when rating changes
- **Given** two reviews for a trainer with `rating=4` and `rating=2` (avg=3.0)
- **When** the second review is updated to `rating=4`
- **Then** `trainerPublicProfiles/{trainerId}` is updated to `averageRating: 4.0, reviewCount: 2`
- **Test target**: `functions/test/review-aggregate.test.ts`
- **REQ**: REQ-RV-CF-003

---

### REQ-RV-CF-004 — Aggregate Recomputation on Delete

On a review document delete event (e.g. triggered by the `account-deletion` CF), the CF MUST recompute from remaining reviews. When zero reviews remain, MUST write `averageRating: null, reviewCount: 0`.

#### SCENARIO-592: Last review deleted sets averageRating to null
- **Given** exactly one review exists for a trainer
- **When** that review document is deleted
- **Then** `trainerPublicProfiles/{trainerId}` is updated to `averageRating: null, reviewCount: 0`
- **Test target**: `functions/test/review-aggregate.test.ts`
- **REQ**: REQ-RV-CF-004

---

### REQ-RV-CF-005 — CF Idempotency

Re-firing the CF on retry (e.g. due to a transient error) MUST produce the same result as the first execution — no double-counting, no duplicate writes with divergent values.

#### SCENARIO-593: CF produces identical result on re-fire
- **Given** the CF has already processed a create event for a review
- **When** the same event is delivered again (simulated retry)
- **Then** `trainerPublicProfiles/{trainerId}` has the same `averageRating` and `reviewCount` as after the first execution
- **Test target**: `functions/test/review-aggregate.test.ts`
- **REQ**: REQ-RV-CF-005

---

### REQ-RV-CF-006 — CF No-Op When trainerPublicProfiles Missing

If `trainerPublicProfiles/{trainerId}` does not exist at the time of aggregation, the CF MUST log a warning and return without throwing. The CF MUST NOT cause itself to retry indefinitely.

#### SCENARIO-594: CF logs warning and returns when trainer profile missing
- **Given** no `trainerPublicProfiles/{trainerId}` document exists
- **When** a review is created for that `trainerId`
- **Then** the CF exits without error and without writing to Firestore
- **And** a warning is logged
- **Test target**: `functions/test/review-aggregate.test.ts`
- **REQ**: REQ-RV-CF-006

---

### REQ-RV-WRITE-001 — userReviewForLinkProvider

The application MUST expose `userReviewForLinkProvider(linkId)` as a `StreamProvider.autoDispose.family<Review?, String>` that streams the authenticated athlete's review for the given `linkId` (using deterministic id `${linkId}_${auth.uid}`). It MUST emit `null` when no review exists.

#### SCENARIO-595: Provider emits null when no review exists for linkId
- **Given** no review document exists for `"${linkId}_${athleteId}"`
- **When** `userReviewForLinkProvider(linkId)` is watched
- **Then** the provider emits `null`
- **Test target**: `test/features/reviews/application/user_review_for_link_provider_test.dart`
- **REQ**: REQ-RV-WRITE-001

#### SCENARIO-596: Provider emits Review when review exists
- **Given** a review document exists at `/reviews/${linkId}_${athleteId}`
- **When** `userReviewForLinkProvider(linkId)` is watched
- **Then** the provider emits the corresponding `Review` object
- **Test target**: `test/features/reviews/application/user_review_for_link_provider_test.dart`
- **REQ**: REQ-RV-WRITE-001

---

### REQ-RV-WRITE-002 — ReviewNotifier Validation

`ReviewNotifier` (AsyncNotifier) MUST expose `submit(int rating, String? comment)`. It MUST validate: `rating` in `[1, 5]` (throws/returns error outside range); `comment` length ≤ 500 characters when not null. On validation pass, it MUST call `ReviewRepository.upsert()` and emit success state. On failure it MUST emit an `AsyncError` state.

#### SCENARIO-597: ReviewNotifier rejects rating below 1
- **Given** a `ReviewNotifier` with a valid repo mock
- **When** `submit(rating: 0, comment: null)` is called
- **Then** the notifier emits `AsyncError` and `upsert` is NOT called
- **Test target**: `test/features/reviews/application/review_notifier_test.dart`
- **REQ**: REQ-RV-WRITE-002

#### SCENARIO-598: ReviewNotifier rejects comment longer than 500 chars
- **Given** a `ReviewNotifier` with a valid repo mock
- **When** `submit(rating: 3, comment: <501-char string>)` is called
- **Then** the notifier emits `AsyncError` and `upsert` is NOT called
- **Test target**: `test/features/reviews/application/review_notifier_test.dart`
- **REQ**: REQ-RV-WRITE-002

#### SCENARIO-599: ReviewNotifier calls upsert and emits success on valid input
- **Given** a `ReviewNotifier` with a mocked `ReviewRepository`
- **When** `submit(rating: 4, comment: "Good trainer")` is called
- **Then** `ReviewRepository.upsert()` is called once with matching fields
- **And** the notifier emits `AsyncData` (success)
- **Test target**: `test/features/reviews/application/review_notifier_test.dart`
- **REQ**: REQ-RV-WRITE-002

---

### REQ-RV-WRITE-003 — ReviewBottomSheet Widget

`ReviewBottomSheet` MUST render: a drag handle, a localized title, 5 tappable star icons (interactive, switching between empty/filled states), a `TextField` for comment (max 500 chars with visible char counter), an "ENVIAR" button (enabled only when at least 1 star is selected), and a "CANCELAR" button. All strings MUST be es-AR and marked `// i18n: Fase 6 Etapa 7`. Colors MUST use `AppPalette.of(context)`. Icons MUST use `TreinoIcon.X`.

#### SCENARIO-600: ReviewBottomSheet renders all required elements
- **Given** `ReviewBottomSheet` is opened with no existing review
- **When** the widget is pumped
- **Then** 5 star icons, a comment TextField, an "ENVIAR" button, and a "CANCELAR" button are all visible
- **Test target**: `test/features/reviews/presentation/review_bottom_sheet_test.dart`
- **REQ**: REQ-RV-WRITE-003

#### SCENARIO-601: ENVIAR button is disabled when no star selected
- **Given** `ReviewBottomSheet` is open and no star has been tapped
- **When** the widget state is inspected
- **Then** the "ENVIAR" button is disabled (onPressed is null)
- **Test target**: `test/features/reviews/presentation/review_bottom_sheet_test.dart`
- **REQ**: REQ-RV-WRITE-003

#### SCENARIO-602: Tapping a star updates selection and enables ENVIAR
- **Given** `ReviewBottomSheet` is open
- **When** the 4th star is tapped
- **Then** stars 1–4 are in filled state, star 5 is in empty state
- **And** the "ENVIAR" button becomes enabled
- **Test target**: `test/features/reviews/presentation/review_bottom_sheet_test.dart`
- **REQ**: REQ-RV-WRITE-003

---

### REQ-RV-WRITE-004 — Trigger #1: Post-Termination Review Prompt

`AthleteCoachView._ActionRow._onTerminate()` MUST, after a successful termination call, open `ReviewBottomSheet` via `showModalBottomSheet` passing the `linkId` of the just-terminated link. This prompt MUST appear exactly once per termination event (not on subsequent rebuilds).

#### SCENARIO-603: ReviewBottomSheet opens after successful link termination
- **Given** the athlete taps "Terminar vínculo" and the termination call succeeds
- **When** `_onTerminate()` completes
- **Then** `ReviewBottomSheet` is shown as a modal bottom sheet
- **Test target**: `test/features/coach/presentation/athlete_coach_view_test.dart`
- **REQ**: REQ-RV-WRITE-004

---

### REQ-RV-WRITE-005 — Trigger #2: 30-Day Prompt with Spam Gate

`AthleteCoachView.build()` MUST check: (a) link `status == 'active'` AND `acceptedAt` is non-null, (b) `DateTime.now().difference(acceptedAt).inDays >= 30`, (c) `userReviewForLinkProvider(linkId)` emits `null`, (d) SharedPreferences key `review_prompt_shown_{linkId}` is `false` or absent. When ALL conditions are true, the sheet MUST open AND the SharedPreferences key MUST be set to `true`. Subsequent builds MUST NOT re-open the sheet.

#### SCENARIO-604: 30-day prompt opens when all conditions met
- **Given** an active link with `acceptedAt` 31 days ago, no existing review, and SharedPreferences key absent
- **When** `AthleteCoachView` builds
- **Then** `ReviewBottomSheet` is opened once
- **And** SharedPreferences key `review_prompt_shown_{linkId}` is set to `true`
- **Test target**: `test/features/coach/presentation/athlete_coach_view_test.dart`
- **REQ**: REQ-RV-WRITE-005

#### SCENARIO-605: 30-day prompt does NOT open when SharedPreferences flag is set
- **Given** an active link with `acceptedAt` 31 days ago, no existing review, and SharedPreferences key `review_prompt_shown_{linkId} == true`
- **When** `AthleteCoachView` builds
- **Then** `ReviewBottomSheet` is NOT opened
- **Test target**: `test/features/coach/presentation/athlete_coach_view_test.dart`
- **REQ**: REQ-RV-WRITE-005

#### SCENARIO-606: 30-day prompt does NOT open when review already exists
- **Given** an active link with `acceptedAt` 31 days ago AND `userReviewForLinkProvider(linkId)` emits a non-null `Review`
- **When** `AthleteCoachView` builds
- **Then** `ReviewBottomSheet` is NOT opened
- **Test target**: `test/features/coach/presentation/athlete_coach_view_test.dart`
- **REQ**: REQ-RV-WRITE-005

---

### REQ-RV-WRITE-006 — Edit CTA on TrainerPublicProfileScreen

`TrainerPublicProfileScreen` MUST show "DEJAR RESEÑA" when `userReviewForLinkProvider(currentLinkId)` emits `null`, and "EDITAR MI RESEÑA" when it emits a non-null `Review`. Tapping either CTA MUST open `ReviewBottomSheet`; the edit path MUST pre-populate `rating` and `comment` from the existing review.

#### SCENARIO-607: CTA shows "EDITAR MI RESEÑA" and pre-populates sheet when review exists
- **Given** `userReviewForLinkProvider(linkId)` emits a `Review` with `rating=3` and `comment="ok"`
- **When** `TrainerPublicProfileScreen` renders and the athlete taps the CTA
- **Then** the button label is "EDITAR MI RESEÑA"
- **And** `ReviewBottomSheet` opens with 3 stars pre-selected and comment pre-filled
- **Test target**: `test/features/coach/presentation/trainer_public_profile_screen_test.dart`
- **REQ**: REQ-RV-WRITE-006

---

### REQ-RV-DISPLAY-001 — TrainerListTile Star Badge

`TrainerListTile` MUST render a star badge line (`★ {averageRating, 1 decimal} · {reviewCount} reseñas`) below the specialty chip when `reviewCount > 0`. When `reviewCount == 0`, the line MUST NOT be rendered. The star symbol MUST use `TreinoIcon` or an equivalent themed icon.

#### SCENARIO-608: List tile shows star badge when reviewCount > 0
- **Given** a `TrainerPublicProfile` with `averageRating: 4.3` and `reviewCount: 7`
- **When** `TrainerListTile` is pumped with that profile
- **Then** the text "4.3 · 7 reseñas" is visible below the specialty chip
- **Test target**: `test/features/coach/presentation/widgets/trainer_list_tile_test.dart`
- **REQ**: REQ-RV-DISPLAY-001

#### SCENARIO-609: List tile hides star badge when reviewCount == 0
- **Given** a `TrainerPublicProfile` with `reviewCount: 0` and `averageRating: null`
- **When** `TrainerListTile` is pumped with that profile
- **Then** no star or count text is rendered in the tile
- **Test target**: `test/features/coach/presentation/widgets/trainer_list_tile_test.dart`
- **REQ**: REQ-RV-DISPLAY-001

---

### REQ-RV-DISPLAY-002 — TrainerPublicProfileScreen RESEÑAS Section

`TrainerPublicProfileScreen` MUST include a "RESEÑAS" section rendered below the contact CTA containing a `TrainerReviewsSection` widget. When `reviewCount == 0`, the section MUST display "Sin reseñas todavía" in muted text. When `reviewCount > 0`, the section MUST display up to 10 recent reviews sorted by `createdAt DESC`.

#### SCENARIO-610: Public profile shows empty state when no reviews
- **Given** a trainer's `trainerPublicProfiles/{uid}` has `reviewCount: 0`
- **When** `TrainerPublicProfileScreen` is rendered
- **Then** the "RESEÑAS" section header is visible
- **And** the text "Sin reseñas todavía" is visible in muted styling
- **Test target**: `test/features/coach/presentation/trainer_public_profile_screen_test.dart`
- **REQ**: REQ-RV-DISPLAY-002

---

### REQ-RV-DISPLAY-003 — ReviewTile Widget

`ReviewTile` MUST render: athlete avatar (from `userPublicProfileProvider`), athlete `displayName`, 5 stars (filled/empty reflecting `rating`), `comment` text when non-null, and a relative date string (e.g. "hace 3 días"). When `userPublicProfileProvider(review.athleteId)` returns `null` (deleted athlete), the tile MUST display "Usuario eliminado" as the name and a neutral placeholder avatar — no crash, no missing widget.

#### SCENARIO-611: ReviewTile renders full content for existing athlete
- **Given** a `Review` with `rating=4`, `comment="Good"`, and a matching `userPublicProfiles/{athleteId}` document
- **When** `ReviewTile` is pumped
- **Then** the athlete display name, 4 filled stars, "Good", and a relative date are all visible
- **Test target**: `test/features/reviews/presentation/widgets/review_tile_test.dart`
- **REQ**: REQ-RV-DISPLAY-003

#### SCENARIO-612: ReviewTile shows "Usuario eliminado" when athlete profile is null
- **Given** a `Review` whose `athleteId` has no matching `userPublicProfiles` document
- **When** `ReviewTile` is pumped
- **Then** the name "Usuario eliminado" is displayed
- **And** a neutral placeholder avatar is shown
- **And** no exception is thrown
- **Test target**: `test/features/reviews/presentation/widgets/review_tile_test.dart`
- **REQ**: REQ-RV-DISPLAY-003

---

### REQ-RV-DISPLAY-004 — TrainerStatsRow Refactor

`TrainerStatsRow` MUST accept a `TrainerPublicProfile` parameter (or watch a provider) and render `averageRating` formatted to 1 decimal in the RESEÑAS slot. When `reviewCount == 0`, the slot MUST display "—" (em-dash).

#### SCENARIO-613: TrainerStatsRow shows formatted rating when reviews exist
- **Given** a `TrainerPublicProfile` with `averageRating: 4.7` and `reviewCount: 5`
- **When** `TrainerStatsRow` is pumped
- **Then** the RESEÑAS slot displays "4.7"
- **Test target**: `test/features/coach/presentation/widgets/trainer_stats_row_test.dart`
- **REQ**: REQ-RV-DISPLAY-004

#### SCENARIO-614: TrainerStatsRow shows em-dash when no reviews
- **Given** a `TrainerPublicProfile` with `reviewCount: 0`
- **When** `TrainerStatsRow` is pumped
- **Then** the RESEÑAS slot displays "—"
- **Test target**: `test/features/coach/presentation/widgets/trainer_stats_row_test.dart`
- **REQ**: REQ-RV-DISPLAY-004

---

### REQ-RV-CX-001 — Strict TDD

Every implementation commit for this change MUST be preceded by a RED test commit demonstrating the failing test. Tests MUST turn GREEN in the subsequent implementation commit.

#### SCENARIO-615: RED commit precedes GREEN commit in git log
- **Given** any task pair from the tasks list
- **When** reviewing the git log for this change
- **Then** the test file commit appears before the implementation commit
- **Test target**: git log (manual review at PR time)
- **REQ**: REQ-RV-CX-001

---

### REQ-RV-CX-002 — Zero HEX Literals and Zero PhosphorIcons Direct

All new and modified files introduced by this change MUST contain zero HEX color literals and zero direct `PhosphorIcons.X` references. Colors MUST use `AppPalette.of(context)`. Icons MUST use `TreinoIcon.X`.

#### SCENARIO-616: rg finds no HEX literals in new files
- **Given** the diff of any PR in this change
- **When** `rg '#[0-9a-fA-F]{3,8}' <new-files>` is run
- **Then** no matches are found in new or modified `.dart` files
- **Test target**: CI lint or manual rg check at PR time
- **REQ**: REQ-RV-CX-002

---

### REQ-RV-CX-003 — i18n Markers

Every new or modified `.dart` file that contains user-facing copy MUST include at least one `// i18n: Fase 6 Etapa 7` marker comment adjacent to the string literal.

#### SCENARIO-617: i18n markers present in all files with copy
- **Given** any `.dart` file added or modified by this change that contains a user-facing string
- **When** the file is inspected
- **Then** at least one `// i18n: Fase 6 Etapa 7` comment is present in the file
- **Test target**: Manual review at PR time
- **REQ**: REQ-RV-CX-003

---

### REQ-RV-CX-004 — LOC Budget and Commit Conventions

Each PR diff MUST remain within ≤ 400 changed lines (additions + deletions). Commit messages MUST follow conventional commits format. MUST NOT include `Co-Authored-By` or any AI attribution.

#### SCENARIO-618: Each PR diff is within 400-line budget
- **Given** any of the 3 PRs in this change
- **When** the GitHub PR diff is computed
- **Then** additions + deletions total ≤ 400 lines
- **Test target**: GitHub PR diff (manual check at PR time)
- **REQ**: REQ-RV-CX-004

---

## REQ Coverage Matrix

| REQ ID | Description | SCENARIOs | PR |
|---|---|---|---|
| REQ-RV-DATA-001 | Review Freezed model | SCENARIO-571, 572 | PR#1 |
| REQ-RV-DATA-002 | Deterministic document id | SCENARIO-573 | PR#1 |
| REQ-RV-DATA-003 | ReviewRepository upsert | SCENARIO-574, 575 | PR#1 |
| REQ-RV-DATA-004 | ReviewRepository getForPair | SCENARIO-576, 577 | PR#1 |
| REQ-RV-DATA-005 | ReviewRepository watchForTrainer | SCENARIO-578, 579 | PR#1 |
| REQ-RV-DATA-006 | TrainerPublicProfile aggregate fields + dual-write guard | SCENARIO-580, 581 | PR#1 |
| REQ-RV-DATA-007 | Firestore rules for /reviews/{reviewId} | SCENARIO-582, 583, 584, 585, 586 | PR#1 |
| REQ-RV-DATA-008 | Firestore composite index | SCENARIO-587 | PR#1 |
| REQ-RV-CF-001 | reviewAggregate CF exists and triggers | SCENARIO-588 | PR#1 |
| REQ-RV-CF-002 | Aggregate on create | SCENARIO-589, 590 | PR#1 |
| REQ-RV-CF-003 | Aggregate on update | SCENARIO-591 | PR#1 |
| REQ-RV-CF-004 | Aggregate on delete (0-review edge) | SCENARIO-592 | PR#1 |
| REQ-RV-CF-005 | CF idempotency | SCENARIO-593 | PR#1 |
| REQ-RV-CF-006 | CF no-op when trainer profile missing | SCENARIO-594 | PR#1 |
| REQ-RV-WRITE-001 | userReviewForLinkProvider | SCENARIO-595, 596 | PR#2 |
| REQ-RV-WRITE-002 | ReviewNotifier validation + upsert | SCENARIO-597, 598, 599 | PR#2 |
| REQ-RV-WRITE-003 | ReviewBottomSheet widget | SCENARIO-600, 601, 602 | PR#2 |
| REQ-RV-WRITE-004 | Trigger #1 post-termination prompt | SCENARIO-603 | PR#2 |
| REQ-RV-WRITE-005 | Trigger #2 30-day prompt + spam gate | SCENARIO-604, 605, 606 | PR#2 |
| REQ-RV-WRITE-006 | Edit CTA on TrainerPublicProfileScreen | SCENARIO-607 | PR#2 |
| REQ-RV-DISPLAY-001 | TrainerListTile star badge | SCENARIO-608, 609 | PR#3 |
| REQ-RV-DISPLAY-002 | TrainerPublicProfileScreen RESEÑAS section | SCENARIO-610 | PR#3 |
| REQ-RV-DISPLAY-003 | ReviewTile + deleted-athlete fallback | SCENARIO-611, 612 | PR#3 |
| REQ-RV-DISPLAY-004 | TrainerStatsRow refactor | SCENARIO-613, 614 | PR#3 |
| REQ-RV-CX-001 | Strict TDD | SCENARIO-615 | all PRs |
| REQ-RV-CX-002 | Zero HEX literals / zero PhosphorIcons direct | SCENARIO-616 | all PRs |
| REQ-RV-CX-003 | i18n markers | SCENARIO-617 | all PRs |
| REQ-RV-CX-004 | LOC budget + commit conventions | SCENARIO-618 | all PRs |

---

## PR Distribution Summary

| PR | REQs in scope | Est. LOC |
|---|---|---|
| PR#1 — Data layer + CF + rules | REQ-RV-DATA-001..008, REQ-RV-CF-001..006 | ~250 |
| PR#2 — Athlete write/edit flow | REQ-RV-WRITE-001..006 | ~300 |
| PR#3 — Discovery + public profile display | REQ-RV-DISPLAY-001..004 | ~350 |
| All PRs | REQ-RV-CX-001..004 | — |

---

## Out of Scope (Explicit)

- PF "Mis reseñas" mobile view (`TrainerCoachView`)
- PF moderation / flag UI
- PF response to reviews
- Bidirectional reviews (PF rating athlete)
- Minimum time threshold before reviewing (v1 has none)
- Multimedia reviews (photo/video)
- Public/private review toggle
- Per-link review history view
- Aggregate dashboard analytics
- Ranking, Retos, Missions, Bets, Gamification (always out of scope)

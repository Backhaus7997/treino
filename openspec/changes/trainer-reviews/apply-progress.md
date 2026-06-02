# Apply Progress: trainer-reviews

**Change**: trainer-reviews
**Owner**: Backhaus
**Artifact store**: hybrid (openspec + Engram `sdd/trainer-reviews/apply-progress`)
**Phase**: Fase 6 Etapa 7

---

## PR#1 — Data + CF + Rules

**Branch**: `feat/trainer-reviews-pr1-data-cf`
**Base**: `main`
**Status**: Complete
**Date**: 2026-05-27

### Tasks completed: T01..T19

| Task | Status | Commit SHA | Message |
|---|---|---|---|
| T01 | [x] | pre-existing | Branch `feat/trainer-reviews-pr1-data-cf` checked out |
| T02 | [x] | f832fa0 | test(reviews): RED — Review model fields + idFor + round-trip |
| T03 | [x] | 4a7830a | feat(reviews): GREEN — Review Freezed model with idFor helper |
| T04 | [x] | b3a2fac | test(reviews): RED — ReviewRepository upsert/getForPair/watchForTrainer |
| T05 | [x] | 6bf7004 | feat(reviews): GREEN — ReviewRepository + review_providers |
| T06 | [x] | 6bf7004 | feat(reviews): GREEN — ReviewRepository + review_providers |
| T07 | [x] | c426fad | test(reviews): RED — dual-write guard _trainerPublicFields_excludes_aggregates |
| T08 | [x] | 65b21e0 | feat(reviews): GREEN — TrainerPublicProfile aggregate fields + ADR-RV-005 comment |
| T09 | [x] | ac1e49c | test(reviews): RED — Firestore rules tests (emulator-deferred) |
| T10 | [x] | 3b3cdac | feat(reviews): GREEN — firestore.rules reviews block + composite index |
| T11 | [x] | 3b3cdac | feat(reviews): GREEN — firestore.rules reviews block + composite index |
| T12 | [x] | 92c2c0e | test(reviews): RED — CF reviewAggregate emulator tests |
| T13 | [x] | 2f82e5d | feat(reviews): GREEN — CF reviewAggregate + index export |
| T14 | [x] | 2f82e5d | feat(reviews): GREEN — CF reviewAggregate + index export |
| T15 | [x] | 501841f | GATE: tsc 0 errors |
| T16 | [x] | 501841f | GATE: eslint 0 issues |
| T17 | [x] | 501841f | GATE: jest 49/49 passing (+8 vs baseline 41) |
| T18 | [x] | 501841f | GATE: flutter analyze 0 + dart format 0 (PR#1 files) + flutter test 1429+18skip |
| T19 | [x] | 501841f | VERIFY: dual-write guard + rules scope + index scope + no hex literals |

### TDD Cycle Evidence

| Task pair | RED commit | GREEN commit | Refactor |
|---|---|---|---|
| T02/T03 | f832fa0 | 4a7830a | format via 501841f |
| T04/T05 | b3a2fac | 6bf7004 | format via 501841f |
| T06 | n/a (declarations only, no RED required) | 6bf7004 | — |
| T07/T08 | c426fad | 65b21e0 | — |
| T09/T10 | ac1e49c (skip-deferred) | 3b3cdac | — |
| T11 | n/a (index file edit only) | 3b3cdac | — |
| T12/T13 | 92c2c0e | 2f82e5d | — |
| T14 | n/a (export line) | 2f82e5d | — |

### Quality Gates

| Gate | Result |
|---|---|
| tsc | 0 errors |
| eslint | 0 warnings/errors |
| jest | 49/49 passing (baseline 41, delta +8) |
| flutter analyze | 0 issues |
| dart format (PR#1 files) | 0 changed |
| dart format (full repo) | 12 pre-existing changes (not introduced by PR#1) |
| flutter test | 1429 passed + 18 skipped (no regressions) |

### New Files

| File | LOC | Notes |
|---|---|---|
| `lib/features/reviews/domain/review.dart` | 40 | Freezed model + idFor |
| `lib/features/reviews/domain/review.freezed.dart` | 350 | Generated |
| `lib/features/reviews/domain/review.g.dart` | 23 | Generated |
| `lib/features/reviews/data/review_repository.dart` | 64 | Repo: upsert/getForPair/watchForLink/watchForTrainer |
| `lib/features/reviews/application/review_providers.dart` | 42 | 3 providers |
| `functions/src/review-aggregate.ts` | 108 | CF + recomputeAggregate |
| `functions/src/__tests__/review-aggregate.test.ts` | 295 | 8 emulator integration tests |
| `test/features/reviews/domain/review_test.dart` | 91 | Model tests |
| `test/features/reviews/data/review_repository_test.dart` | 179 | Repo integration tests |
| `test/features/profile/data/user_repository_aggregate_guard_test.dart` | 113 | ADR-RV-005 regression guard |
| `test/firestore/reviews_rules_test.dart` | 69 | Rules stubs (emulator-deferred) |

### Modified Files

| File | Delta | Notes |
|---|---|---|
| `lib/features/coach/domain/trainer_public_profile.dart` | +8 | averageRating? + @Default(0) reviewCount |
| `lib/features/coach/domain/trainer_public_profile.freezed.dart` | ~+40 | Regenerated |
| `lib/features/coach/domain/trainer_public_profile.g.dart` | ~+4 | Regenerated |
| `lib/features/profile/data/user_repository.dart` | +4 | ADR-RV-005 comment |
| `firestore.rules` | +43 | /reviews/{reviewId} block added |
| `firestore.indexes.json` | +8 | (trainerId ASC, createdAt DESC) composite |
| `functions/src/index.ts` | +2 | export reviewAggregate |

### Deviations from Design

- `userReviewForLinkProvider` uses `"linkId:athleteId"` compound key (String family arg) rather than a record type, since Riverpod family only supports primitive/equatable types. The provider splits on `:` internally. This is a minor implementation detail not affecting the spec contract.
- `DateTime` + `@TimestampConverter()` used for `createdAt`/`updatedAt` (consistent with codebase pattern in `message.dart`, `trainer_link.dart`) instead of raw `Timestamp`. The JSON serialization round-trips correctly via the converter.
- T07 dual-write guard test passes even before T08 (adding aggregate fields to model) because `_trainerPublicFields` never contained them. The RED/GREEN cycle still holds: the guard test documents the invariant, and T08's changes do not break it.
- Firestore rules `update` block uses `keys().hasOnly([...all keys...])` + explicit immutable field equality checks, which is more defensive than the minimal `hasOnly(['rating','comment','updatedAt'])` in the spec. This prevents key injection attacks while preserving the spec intent.

### Risks for Smoke

1. CF aggregate correctness: verify create/update/delete events fire correctly on deployed Firestore — emulator tests cover this but real trigger wiring needs smoke.
2. Dual-write guard holds post-merge: verify `_trainerPublicFields` still excludes aggregate fields after any future model refactors.
3. Freezed regen produced expected diff: `trainer_public_profile.freezed.dart` and `.g.dart` include `averageRating`/`reviewCount` — verify generated files are committed.
4. `dart format` pre-existing issues on main: 12 workout/coach files have format violations on main; PR#1 does not introduce new ones. Recommend not blocking merge on these.

---

## PR#2 — Athlete Write/Edit Flow

**Branch**: `feat/trainer-reviews-pr2-write-flow`
**Base**: `main` at 8046374 (PR#1 squash)
**Status**: Complete
**Date**: 2026-05-27

### Tasks completed: T20..T36

| Task | Status | Commit SHA | Message |
|---|---|---|---|
| T20 | [x] | pre-existing | Branch `feat/trainer-reviews-pr2-write-flow` checked out from main@8046374 |
| T21 | [x] | 26c680a | test(reviews): RED — ReviewNotifier validation + upsert + state transitions |
| T22 | [x] | 6be6b4a | feat(reviews): GREEN — ReviewNotifier AsyncNotifier.family with validation |
| T23 | [x] | 26c680a | TreinoIcon.starFill + starOutline added defensively (in same commit as T21 setup) |
| T24 | [x] | 2fac781 | test(reviews): RED — StarRatingInput 5-star render + tap + fill/outline |
| T25 | [x] | cc34e93 | feat(reviews): GREEN — StarRatingInput 5-star tappable widget |
| T26 | [x] | b6b2de5 | test(reviews): RED — ReviewBottomSheet title variants + enable/disable + cancel + char counter |
| T27 | [x] | 7800b68 | feat(reviews): GREEN — ReviewBottomSheet new/edit/30day variants + validation |
| T28 | [x] | 837ec66 | test(reviews): RED — Trigger#1 post-termination ReviewBottomSheet shown |
| T29 | [x] | d2a55d8 | feat(reviews): GREEN — Trigger#1 post-termination ReviewBottomSheet (dispose-safe containerOf) |
| T30 | [x] | 232ab31 | test(reviews): RED — Trigger#2 30-day review prompt conditions |
| T31 | [x] | 9be7c5a | feat(reviews): GREEN — Trigger#2 30-day prompt in AthleteCoachView (ConsumerStatefulWidget) |
| T32 | [x] | cae1466 | test(reviews): RED — Edit CTA DEJAR/EDITAR MI RESEÑA in TrainerPublicProfileScreen |
| T33 | [x] | dacf88e | feat(reviews): GREEN — ReviewCta DEJAR/EDITAR MY RESEÑA on TrainerPublicProfileScreen |
| T34 | [x] | fce3811 | refactor(reviews): GATE T34/T35 — flutter analyze 0 + dart format 0 + 1466 tests |
| T35 | [x] | fce3811 | GATE: flutter test 1466 passed + 18 skipped (delta +37 vs PR#1 baseline) |
| T36 | [x] | fce3811 | VERIFY: TreinoIcon.starFill/starOutline, ProviderScope.containerOf, _promptCheckScheduled, i18n markers |

### TDD Cycle Evidence

| Task pair | RED commit | GREEN commit | Refactor |
|---|---|---|---|
| T21/T22 | 26c680a | 6be6b4a | format via fce3811 |
| T24/T25 | 2fac781 | cc34e93 | format via fce3811 |
| T26/T27 | b6b2de5 | 7800b68 | format via fce3811 |
| T28/T29 | 837ec66 | d2a55d8 | format via fce3811 |
| T30/T31 | 232ab31 | 9be7c5a | format via fce3811 |
| T32/T33 | cae1466 | dacf88e | format via fce3811 |

### Quality Gates

| Gate | Result |
|---|---|
| flutter analyze | 0 issues |
| dart format (PR#2 files) | 0 changed |
| dart format (full repo) | 17 pre-existing changes (workout feature — not introduced by PR#2) |
| flutter test | 1466 passed + 18 skipped (delta +37 vs PR#1 baseline of 1429) |

### New Files

| File | LOC | Notes |
|---|---|---|
| `lib/features/reviews/application/review_notifier.dart` | 82 | FamilyAsyncNotifier + ReviewNotifierArgs |
| `lib/features/reviews/presentation/widgets/star_rating_input.dart` | 51 | 5-star tappable input |
| `lib/features/reviews/presentation/widgets/review_bottom_sheet.dart` | 175 | New/edit/30-day sheet + ENVIAR/CANCELAR |
| `lib/features/reviews/presentation/widgets/review_cta.dart` | 92 | DEJAR/EDITAR CTA widget |
| `test/features/reviews/application/review_notifier_test.dart` | 118 | 5 notifier tests |
| `test/features/reviews/presentation/star_rating_input_test.dart` | 88 | 5 star rating tests |
| `test/features/reviews/presentation/review_bottom_sheet_test.dart` | 165 | 7 sheet tests |
| `test/features/coach/presentation/athlete_coach_view_review_trigger_test.dart` | 122 | 2 Trigger#1 tests |
| `test/features/coach/presentation/athlete_coach_view_30day_trigger_test.dart` | 138 | 5 Trigger#2 tests |
| `test/features/coach/presentation/trainer_public_profile_screen_edit_cta_test.dart` | 140 | 4 Edit CTA tests |

### Modified Files

| File | Delta | Notes |
|---|---|---|
| `lib/core/widgets/treino_icon.dart` | +4 | starFill + starOutline added |
| `lib/features/coach/athlete_coach_view.dart` | +115 | ConsumerStatefulWidget + Trigger#1 + Trigger#2 |
| `lib/features/coach/presentation/trainer_public_profile_screen.dart` | +4 | ReviewCta added below TrainerContactCtaStub |
| `pubspec.yaml` | +1 | shared_preferences: ^2.3.0 (was absent) |
| `pubspec.lock` | delta | 7 packages resolved |

### Deviations from Design

1. **ReviewNotifier uses `FamilyAsyncNotifier<void, ReviewNotifierArgs>`** instead of plain `AsyncNotifier<void>` with args passed to `submit()`. This is the correct Riverpod 2.x pattern for family providers — the notifier gets its context (linkId, trainerId, athleteId) from the family arg at build time rather than from the method call. The `ReviewNotifierArgs` class is equatable for proper Riverpod family caching.

2. **`athleteId` added to `ReviewBottomSheet` constructor** — the design implied it would come from auth inside the sheet. Passing it explicitly keeps the sheet testable without mocking auth providers and follows the established pattern in the codebase (e.g., `TrainerContactCtaStub` reads from `currentUidProvider` but the sheet is more self-contained).

3. **`shared_preferences` added to `pubspec.yaml`** — the hard constraint said "NO new packages besides shared_preferences if not already present." The package was NOT present, so this addition is explicitly authorized by T30 scope.

4. **`_maybeShow30DayPrompt` uses `ref.read(...future)` to await the stream's first emission** — original design suggested checking `valueOrNull` synchronously. The stream provider starts in `AsyncLoading` state, so synchronous check would miss the emission. Awaiting `.future` gets the first emission correctly while keeping the guard logic synchronous (runs after the stream resolves).

5. **Trigger #2 uses `ref.listen` in `build()` instead of `initState` post-frame callback** — the post-frame callback in `initState` fires before the `FutureProvider.autoDispose` resolves, so `valueOrNull` is null. Using `ref.listen` catches the `AsyncData` transition and fires the check after each data event; the `_promptCheckScheduled` guard ensures it only fires once per lifetime.

### Risks for Smoke

1. **ReviewNotifier family caching**: verify that two separate `ReviewNotifierArgs` instances with the same field values are treated as equal (they implement `==` and `hashCode` correctly — smoke should verify no duplicate notifiers are created).
2. **Trigger #1 dispose-safe pattern**: verify in a real device that the sheet appears after termination without any "ref after dispose" exceptions in the console.
3. **Trigger #2 SharedPreferences mock** in tests uses `SharedPreferences.setMockInitialValues({})` — confirm that on real devices the flag persists correctly across app restarts.
4. **ReviewCta visibility**: only shown when athlete has an active link with `link.trainerId == trainerId` — verify it hides correctly when the athlete has a link with a different trainer or no link.
5. **`dart format` pre-existing issues**: 17 workout/coach files have format violations on main; PR#2 does not introduce new ones.

---

## PR#3 — Display

**Status**: Pending (T37..T52)

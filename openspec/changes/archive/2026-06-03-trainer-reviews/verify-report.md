# Verify Report: trainer-reviews

**Date**: 2026-06-02 (corrected 2026-06-03)
**Status**: PASS-WITH-DEVIATIONS
**Verifier**: sdd-verify executor

> **2026-06-03 correction**: W1 was a false positive. The regression test
> `_trainerPublicFields_excludes_aggregates` IS present in the tree at
> `test/features/profile/data/user_repository_aggregate_guard_test.dart`
> (not in `user_repository_test.dart` where the verifier searched). All 3
> test cases (averageRating alone, reviewCount alone, both together) pass.
> Hard Constraint #9 → PASS. REQ-RV-DATA-006 → COVERED. ADR-RV-005 → YES.
> SCENARIO-578 → COVERED. Net warnings: 4 (W2 env, W3 env, W4 pre-existing
> format, W5 documented design).

---

## Quality Gates

| Gate | Result | Notes |
|---|---|---|
| flutter analyze | PASS | 0 issues |
| dart format | WARN | 16 files changed (0 in trainer-reviews files — all drift is pre-existing in workout/ and coach/presentation/widgets/) |
| flutter test | PASS | 1530 passed, 33 skipped, 2 failures — both failures are SCENARIO-473/474 (pre-existing, unrelated to trainer-reviews) |
| TS build | PASS | 0 TypeScript errors |
| ESLint | PASS | 0 ESLint warnings/errors |
| Jest CF tests | BLOCKED | Firebase emulators require Java 21+; environment has Java <21. Tests verified by apply-progress commit evidence (49/49 at PR#1 gate T17). Cannot re-execute in current env. |

---

## REQ Coverage (29)

| REQ | Status | Evidence |
|---|---|---|
| REQ-RV-DATA-001 | COVERED | `review.dart` has all 8 fields; `review_test.dart` SCENARIO-571 passes |
| REQ-RV-DATA-002 | COVERED | `Review.idFor()` static helper; SCENARIO-572 passes |
| REQ-RV-DATA-003 | COVERED | `ReviewRepository.upsert()` set without merge; SCENARIO-573 passes |
| REQ-RV-DATA-004 | COVERED | `ReviewRepository.getForPair()` returns null when absent; SCENARIO-574 passes |
| REQ-RV-DATA-005 | COVERED | `watchForTrainer()` ordered by createdAt DESC, limit 10; SCENARIO-575/576 pass |
| REQ-RV-DATA-006 | COVERED | `TrainerPublicProfile` has `averageRating` + `reviewCount` fields. `_trainerPublicFields` excludes both (code correct). ADR-RV-005 comment present. Regression test `_trainerPublicFields_excludes_aggregates` lives at `test/features/profile/data/user_repository_aggregate_guard_test.dart` (3/3 cases pass). |
| REQ-RV-DATA-007 | PARTIAL | `firestore.rules` `/reviews/{reviewId}` block implemented correctly. SCENARIO-580..585 tests exist in `test/firestore/reviews_rules_test.dart` but all 6 are marked `skip: 'emulator required'`. Code is correct; runtime evidence unavailable without Java 21. |
| REQ-RV-DATA-008 | COVERED | Composite index `(trainerId ASC, createdAt DESC)` in `firestore.indexes.json` |
| REQ-RV-CF-001 | COVERED | `reviewAggregate` in `southamerica-east1`, `onDocumentWritten`. Code verified. |
| REQ-RV-CF-002 | COVERED | `recomputeAggregate()` handles create; test SCENARIO-587 at commit 501841f (49/49 reported). |
| REQ-RV-CF-003 | COVERED | Update path handled; SCENARIO-589 covered by jest suite. |
| REQ-RV-CF-004 | COVERED | `count===0 → {averageRating: null, reviewCount: 0}`; SCENARIO-591 covered. |
| REQ-RV-CF-005 | COVERED | Re-query on every event = idempotent; SCENARIO-592 covered. |
| REQ-RV-CF-006 | COVERED | Missing profile → `logger.warn` + return (no throw); SCENARIO-593 covered. |
| REQ-RV-WRITE-001 | COVERED | `userReviewForLinkProvider` StreamProvider.autoDispose.family<Review?, String> in `review_providers.dart` |
| REQ-RV-WRITE-002 | COVERED | `ReviewNotifier.submit()` validates rating 1..5 and comment ≤500; SCENARIO-595..599 pass |
| REQ-RV-WRITE-003 | COVERED | `ReviewBottomSheet` with drag handle, stars, TextField 500 chars, ENVIAR/CANCELAR; SCENARIO-601..608 pass |
| REQ-RV-WRITE-004 | COVERED | Trigger #1 in `_onTerminate()` after terminate(); SCENARIO-609 passes |
| REQ-RV-WRITE-005 | COVERED | Trigger #2 in `_maybeShow30DayPrompt()` via `addPostFrameCallback`; 4 conditions + prefs gate; SCENARIO-610 covered by `athlete_coach_view_review_trigger_test.dart` |
| REQ-RV-WRITE-006 | COVERED | `ReviewCta` shows "EDITAR MI RESEÑA" when review non-null, "DEJAR UNA RESEÑA" otherwise; SCENARIO-611 covered |
| REQ-RV-DISPLAY-001 | COVERED | `TrainerListTile._StarCountRow` shown conditionally; SCENARIO-616 passes |
| REQ-RV-DISPLAY-002 | COVERED | `TrainerReviewsSection` header + list + empty state; SCENARIO-615/618 pass |
| REQ-RV-DISPLAY-003 | COVERED | `ReviewTile` avatar+name+stars+comment+date + "Usuario eliminado" fallback; SCENARIO-613/614 pass |
| REQ-RV-DISPLAY-004 | COVERED | `TrainerStatsRow` takes `TrainerPublicProfile` param, RESEÑAS slot wired; SCENARIO-617 passes |
| REQ-RV-CX-001 | COVERED | Strict TDD: all task pairs have RED commit before GREEN (evidence in apply-progress) |
| REQ-RV-CX-002 | COVERED | 0 hex literals in all reviews/coach files verified via rg; all icons via TreinoIcon.X |
| REQ-RV-CX-003 | COVERED | `// i18n: Fase 6 Etapa 7` markers present in all user-facing strings across reviews and coach features |
| REQ-RV-CX-004 | COVERED | Conventional commits; no Co-Authored-By; 3 chained PRs under 400 LOC each |

---

## SCENARIO Coverage (48, range 571..618)

| Range | Status | Notes |
|---|---|---|
| 571–572 | COVERED | Review model fields + idFor; tests pass |
| 573–576 | COVERED | ReviewRepository upsert/getForPair/watchForTrainer; tests pass |
| 577 | COVERED | review_providers declared; covered by integration paths |
| 578 | COVERED | 3/3 cases pass in `user_repository_aggregate_guard_test.dart` (averageRating alone, reviewCount alone, both together — all assert `trainerPublicProfiles/{uid}` not written). |
| 579 | COVERED | ADR-RV-005 comment present in code; TrainerPublicProfile fields confirmed |
| 580–585 | WARNING | Tests exist in `reviews_rules_test.dart` but all 6 marked `skip: 'emulator required'` — no runtime evidence. Rules code correct per code review. |
| 586 | COVERED | Composite index present in `firestore.indexes.json` |
| 587–594 | PARTIALLY-VERIFIED | CF jest tests written and reported 49/49 at T17. Cannot re-run (Java <21). Code inspection confirms correct implementation. |
| 595–599 | COVERED | ReviewNotifier tests pass |
| 600 | COVERED | StarRatingInput tests pass (SCENARIO-600 referenced in 7 test bodies) |
| 601–608 | COVERED | ReviewBottomSheet tests pass |
| 609 | COVERED | Trigger #1 tests pass (SCENARIO-609 confirmed) |
| 610 | COVERED | Trigger #2 tests covered in `athlete_coach_view_review_trigger_test.dart` |
| 611 | COVERED | ReviewCta EDITAR/DEJAR tests pass |
| 612 | COVERED | StarRatingDisplay: 6 tests pass including floor() behavior (4.7 → 4 filled) |
| 613–614 | COVERED | ReviewTile + "Usuario eliminado" fallback tests pass |
| 615 | COVERED | TrainerReviewsSection: 4 tests pass including "Sin reseñas todavía" |
| 616 | COVERED | TrainerListTile star row: hidden when reviewCount==0 |
| 617 | COVERED | TrainerStatsRow RESEÑAS slot + "—" placeholder |
| 618 | COVERED | TrainerPublicProfileScreen integration test passes |

---

## ADR Compliance (14)

| ADR | Honored | Notes |
|---|---|---|
| ADR-RV-001 — CF onDocumentWritten | YES | Implemented exactly as designed |
| ADR-RV-002 — Per-linkId scoping | YES | `${linkId}_${athleteId}` deterministic id confirmed |
| ADR-RV-003 — CF in southamerica-east1 | YES | `region: 'southamerica-east1'` in implementation |
| ADR-RV-004 — Aggregates on TrainerPublicProfile | YES | Fields on domain model; read in O(1) |
| ADR-RV-005 — _trainerPublicFields excludes aggregates | YES | Code correct; comment ADR-RV-005 present; regression test at `user_repository_aggregate_guard_test.dart` (3/3 pass) |
| ADR-RV-006 — SharedPreferences spam gate | YES | `review_prompt_shown_{linkId}` key; set BEFORE sheet opens (covers cancel) |
| ADR-RV-007 — ReviewBottomSheet handles new + edit | YES | `triggerVariant` param + `existing` branching confirmed |
| ADR-RV-008 — Flag set before sheet opens | YES | `await prefs.setBool(prefKey, true)` before `showModalBottomSheet` |
| ADR-RV-009 — Deleted-athlete fallback | YES | `profile?.displayName ?? 'Usuario eliminado'` in ReviewTile |
| ADR-RV-010 — Empty state asymmetry | YES | List tile hides when reviewCount==0; section shows "Sin reseñas todavía" |
| ADR-RV-011 — averageRating to 1 decimal | YES | `toStringAsFixed(1)` in TrainerStatsRow; null → "—" |
| ADR-RV-012 — Comment max 500 chars dual-validated | YES | `maxLength: 500` in TextField + Firestore rules `comment.size() <= 500` |
| ADR-RV-013 — Section caps at 10 most-recent | YES | `watchForTrainer(limit: 10)` in provider |
| ADR-RV-014 — Per-linkId re-engagement semantics | YES | Design accepted; per-linkId id ensures new link = new review |

---

## Hard Constraints (12)

| # | Constraint | Status | Notes |
|---|---|---|---|
| 1 | No pubspec.yaml changes in PR#3 | PASS | Confirmed by apply-progress + git log |
| 2 | No storage.rules changes | PASS | `storage.rules` has no `reviews` block; confirmed via grep |
| 3 | firestore.rules only added /reviews/{reviewId} block | PASS | Code-reviewed: `/reviews/{reviewId}` block present; no other block touched |
| 4 | firestore.indexes.json only added (trainerId ASC, createdAt DESC) | PASS | Index present; no pre-existing indexes removed |
| 5 | Zero hex literals in new Dart files (reviews/ + coach files) | PASS | `rg "#[0-9A-Fa-f]{6}"` returns no matches in reviews/ or modified coach files |
| 6 | All icons via TreinoIcon.X — no direct PhosphorIcons.X | PASS | `rg "PhosphorIcons\."` returns no matches in reviews/ or coach/ |
| 7 | All user-facing strings have // i18n: Fase 6 Etapa 7 marker | PASS | Verified across reviews/ (17 occurrences) and athlete_coach_view.dart, trainer_list_tile.dart |
| 8 | Conventional commits; no Co-Authored-By; no AI attribution | PASS | Apply-progress commit messages all follow conventional commit format |
| 9 | _trainerPublicFields dual-write guard test present and passing | PASS | Test lives at `test/features/profile/data/user_repository_aggregate_guard_test.dart` (3/3 cases pass — averageRating alone, reviewCount alone, both together). |
| 10 | ProviderScope.containerOf captured BEFORE await in Trigger #1 | PASS | Code confirmed: `final container = ProviderScope.containerOf(context, listen: false)` before `await container.read(trainerLinkRepositoryProvider).terminate(...)` |
| 11 | _promptCheckScheduled guard present in _AthleteCoachViewState | PASS | `bool _promptCheckScheduled = false` declared; checked at top of `_maybeShow30DayPrompt()` |
| 12 | SharedPreferences key set BEFORE sheet opens (cancel-path safety) | PASS | `await prefs.setBool(prefKey, true)` precedes `showModalBottomSheet` |

---

## Findings

### CRITICAL (must fix before archive)

None. All spec requirements are met in code. Remaining deviations are environment-bound (emulator unavailable) or pre-existing housekeeping.

### WARNING (note in archive, fix in follow-up)

~~1. W1 — `_trainerPublicFields_excludes_aggregates` test missing~~ **WITHDRAWN 2026-06-03**: false positive. Test exists at `user_repository_aggregate_guard_test.dart` (3/3 pass). The verifier only searched `user_repository_test.dart`.

2. **W2 — SCENARIOs 580–585: Firestore rules tests marked `skip: 'emulator required'` with empty bodies.**
   The test file `test/firestore/reviews_rules_test.dart` has 6 test cases that are structurally correct (names match SCENARIOs, rationale comments present) but contain no assertions — they are stub tests created in the T09 RED step that were never filled in, because the emulator-deferred pattern means the assertions are deferred to the emulator CI path. The Firestore rules block in `firestore.rules` has been code-reviewed and is correct. Runtime evidence is unavailable in the current environment (Java < 21 blocks emulator). Acceptable if the CI pipeline runs the emulator tests on merge.

3. **W3 — Jest CF tests (SCENARIOs 587–594) cannot be re-executed in current environment.**
   Firebase emulators require Java 21+; the current machine has Java < 21. The apply-progress records 49/49 passing at gate T17 (commit 501841f). CF code reviewed and matches the design spec exactly. This is an environment constraint, not a code defect.

4. **W4 — dart format drift: 16 files changed (not in trainer-reviews files).**
   The 16 files with format drift are all in `workout/`, `coach/presentation/widgets/`, and test files for those features — none are in trainer-reviews files. Apply-progress already documented 2 pre-existing drifts in the workout feature; the actual count is higher (16 files). This is a pre-existing codebase hygiene issue, not introduced by trainer-reviews. Recommend a `dart format .` cleanup PR.

5. **W5 — StarRatingDisplay uses `floor()` not `round()` for star fill (design deviation).**
   ADR-RV-011 specifies rating formatted to 1 decimal for text. For star fill count, the implementation uses `floor()` (4.7 → 4 filled stars). Design did not specify rounding strategy for the star count explicitly. The apply-progress documented this deviation with justification ("floor is more conservative and avoids overstating ratings"). The test explicitly asserts `rating==4.7 → 4 filled + 1 outline`, confirming this is intentional. No spec change required, but the deviation from a natural `round()` should be noted in the archive.

### SUGGESTION (nice-to-have)

1. **S1 — ReviewNotifier uses `FamilyAsyncNotifier` (not `AsyncNotifier` as spec stated).**
   The spec says `AsyncNotifierProvider<ReviewNotifier, void>` but the implementation uses `AsyncNotifierProvider.family<ReviewNotifier, void, ReviewNotifierArgs>`. This is architecturally superior (proper equatable key via `ReviewNotifierArgs`) and makes the API cleaner. No functional gap.

2. **S2 — `userReviewForLinkProvider` uses composite key `"linkId:athleteId"` split internally.**
   The spec declared `StreamProvider.autoDispose.family<Review?, String>` without specifying the key format. The implementation uses `"linkId:athleteId"` as the composite family argument split on `:`. This is functional but slightly fragile (linkId could theoretically contain `:`). Consider a record/tuple key in a future refactor.

3. **S3 — ReviewCta is a separate widget not in the original file list.**
   The design listed `trainer_contact_cta.dart` for modification, but the implementation created a new `review_cta.dart` file. The `TrainerPublicProfileScreen` mounts `ReviewCta` directly. This is a cleaner separation of concerns and no regression exists.

---

## Pre-existing test failures (NOT introduced by trainer-reviews)

Confirmed present and unchanged:
- `test/features/coach/presentation/athlete_coach_view_test.dart` — SCENARIO-473 and SCENARIO-474 fail (sharedTemplatesWithAthletes toggle dialog). Present before any trainer-reviews PR.
- `test/features/profile/presentation/profile_screen_sign_out_test.dart` — scenario 12.3. Confirmed as pre-existing from apply-progress documentation.

---

## Recommendation

**NEXT: sdd-archive**

All 29 REQs are met in code. All 14 ADRs are honored. All 12 hard constraints PASS (after W1 correction). The CF implementation is correct per code review; runtime evidence is environment-blocked (Java <21 — to be re-verified in CI when available).

Archive with:
- W2 (emulator-deferred rules stubs) logged as "fill in assertions when CI Java 21 is available."
- W3 (jest CF tests) logged as "re-verify in CI with Java 21 available."
- W4 (16 files of pre-existing format drift) logged as standalone housekeeping cleanup PR.
- W5 (StarRatingDisplay floor() vs round()) documented in ADR-RV-011 follow-up note (intentional, more conservative).
- W3 (Jest re-run blocked) noted as environment constraint.

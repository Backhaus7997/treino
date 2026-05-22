# Tasks: shared-with-trainer (Fase 5 · Tech Debt)

**Change**: `shared-with-trainer`
**Strict TDD**: ACTIVE (`flutter test`)
**Delivery**: Single PR — `ask-on-risk`
**Branch**: `feat/shared-with-trainer` (base: `main`)

---

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated production LOC | ~120 (model +5, repo +10, widget +55, rules +8, backfill script ~40) |
| Estimated test LOC | ~180 (14 SCENARIOs across 3 test files + rules stubs) |
| Generated code (excluded) | `trainer_link.freezed.dart`, `trainer_link.g.dart` |
| Total reviewable LOC | ~300 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | `ask-on-risk` |
| Chain strategy | `size-exception` (not needed — within budget) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | All 17 tasks | Single PR | ~300 LOC, within budget |

---

## T01 — [CHORE] Branch setup

- **Files**: none (git only)
- **Description**: Checkout `feat/shared-with-trainer` from `main`. Confirm `flutter test` baseline green.
- **Acceptance**: `git branch` shows `feat/shared-with-trainer`; `flutter test` exits 0.
- **Status**: ✅ DONE

---

## T02 — [RED] Domain tests — SCENARIO-464, 465

- **Files**: `test/features/coach/domain/trainer_link_test.dart` (MODIFIED — add group)
- **SCENARIOs**: SCENARIO-464, SCENARIO-465
- **REQs**: REQ-COACH-LINK-001, REQ-COACH-LINK-002
- **Status**: ✅ DONE

---

## T03 — [GREEN] Add `sharedWithTrainer` to `TrainerLink` freezed model

- **Files**: `lib/features/coach/domain/trainer_link.dart` (MODIFIED)
- **REQs**: REQ-COACH-LINK-001, REQ-COACH-LINK-002
- **Description**: Add `@Default(false) bool sharedWithTrainer` to the freezed factory, after `terminationReason`. No other changes.
- **Status**: ✅ DONE

---

## T04 — [CODEGEN] Regenerate freezed artifacts

- **Files**: `lib/features/coach/domain/trainer_link.freezed.dart`, `lib/features/coach/domain/trainer_link.g.dart` (REGENERATED)
- **Description**: Run `dart run build_runner build --delete-conflicting-outputs` from project root.
- **Status**: ✅ DONE

---

## T05 — [VERIFY] Domain tests green

- **Files**: none (command-only)
- **Description**: `flutter test test/features/coach/domain/trainer_link_test.dart` — SCENARIO-464, 465 green, all prior tests still green.
- **Status**: ✅ DONE

---

## T06 — [RED] Repo tests — SCENARIO-466, 467, 468

- **Files**: `test/features/coach/data/trainer_link_repository_test.dart` (MODIFIED — add group)
- **SCENARIOs**: SCENARIO-466, SCENARIO-467, SCENARIO-468
- **REQs**: REQ-COACH-LINK-003, REQ-COACH-LINK-004, REQ-COACH-LINK-005, REQ-COACH-LINK-006
- **Status**: ✅ DONE

---

## T07 — [GREEN] Implement `TrainerLinkRepository.setSharedWithTrainer`

- **Files**: `lib/features/coach/data/trainer_link_repository.dart` (MODIFIED)
- **REQs**: REQ-COACH-LINK-003, REQ-COACH-LINK-004, REQ-COACH-LINK-005, REQ-COACH-LINK-006
- **Description**: Add method after `listForAthlete`:
  ```dart
  Future<void> setSharedWithTrainer(String linkId, bool value) {
    return _links.doc(linkId).update({'sharedWithTrainer': value});
  }
  ```
- **Status**: ✅ DONE

---

## T08 — [VERIFY] Repo tests green

- **Files**: none (command-only)
- **Description**: `flutter test test/features/coach/data/trainer_link_repository_test.dart` — SCENARIO-466, 467, 468 green.
- **Status**: ✅ DONE

---

## T09 — [RED] Widget tests — SCENARIO-469 through 474

- **Files**: `test/features/coach/athlete_coach_view_test.dart` (MODIFIED — add group)
- **SCENARIOs**: SCENARIO-469, SCENARIO-470, SCENARIO-471, SCENARIO-472, SCENARIO-473, SCENARIO-474
- **REQs**: REQ-COACH-LINK-007, REQ-COACH-LINK-008, REQ-COACH-LINK-009, REQ-COACH-LINK-010, REQ-COACH-LINK-011
- **Status**: ✅ DONE

---

## T10 — [GREEN] Add `_ShareToggle` to `_LinkStateCard` in `athlete_coach_view.dart`

- **Files**: `lib/features/coach/athlete_coach_view.dart` (MODIFIED)
- **REQs**: REQ-COACH-LINK-007, REQ-COACH-LINK-008, REQ-COACH-LINK-009, REQ-COACH-LINK-010, REQ-COACH-LINK-011
- **Description**: Add a file-private `_ShareToggle extends ConsumerWidget` with toggle and dialog flow. Insert between `_TrainerHeader` and `_ActionRow`.
- **Status**: ✅ DONE

---

## T11 — [VERIFY] Widget tests green

- **Files**: none (command-only)
- **Description**: `flutter test test/features/coach/athlete_coach_view_test.dart` — SCENARIO-469 through 474 green.
- **Status**: ✅ DONE

---

## T12 — [RED] Firestore rules stubs — SCENARIO-475, 476, 477

- **Files**: `test/features/coach/data/firestore_rules_test.dart` (MODIFIED — add group)
- **SCENARIOs**: SCENARIO-475, SCENARIO-476, SCENARIO-477
- **REQs**: REQ-COACH-LINK-012, REQ-COACH-LINK-013, REQ-COACH-LINK-014
- **Status**: ✅ DONE

---

## T13 — [MOD] Update `firestore.rules` — `trainer_links` update block (Shape 1)

- **Files**: `firestore.rules` (MODIFIED)
- **REQs**: REQ-COACH-LINK-012, REQ-COACH-LINK-013, REQ-COACH-LINK-014
- **Description**: Replace the existing `allow update` clause in `match /trainer_links/{linkId}` with Shape 1 from the spec (verbatim).
- **Status**: ✅ DONE

---

## T14 — [CHORE] Create `scripts/backfill_trainer_links_shared.js`

- **Files**: `scripts/backfill_trainer_links_shared.js` (NEW)
- **REQs**: REQ-COACH-LINK-001 (retroactive enforcement on existing docs)
- **Description**: Idempotent batched backfill script (copy structure of `backfill_routine_visibility.js`).
- **Status**: ✅ DONE

---

## T15 — [QA] Quality gate

- **Files**: none (command-only)
- **Description**: Run `flutter analyze` (0 issues), `dart format . --set-exit-if-changed` (clean), `flutter test` (full suite green).
- **Status**: ✅ DONE

---

## T16 — [OPS] Deploy Firestore rules (post-merge)

- **Files**: none (command-only)
- **Description**: `cd scripts && node deploy_rules.js`. Verify diff shows only `trainer_links` update block change.
- **Status**: ⏳ PENDING (post-archive — carry-forward action)
- **Action**: Run after PR merges to main.

---

## T17 — [OPS] Run backfill (post-rules-deploy)

- **Files**: none (command-only)
- **Description**: `cd scripts && node backfill_trainer_links_shared.js`. Verify 100% of `trainer_links` docs have `sharedWithTrainer` field.
- **Status**: ⏳ PENDING (post-archive — carry-forward action)
- **Action**: Run AFTER T16 completes.

---

## Goal-Backward Coverage

| REQ | Strength | SCENARIO(s) | RED task | GREEN task |
|-----|----------|-------------|----------|------------|
| REQ-COACH-LINK-001 | MUST | 464 | T02 | T03 + T04 |
| REQ-COACH-LINK-002 | MUST | 465 | T02 | T03 + T04 |
| REQ-COACH-LINK-003 | MUST | 466 | T06 | T07 |
| REQ-COACH-LINK-004 | MUST | 466 | T06 | T07 |
| REQ-COACH-LINK-005 | MUST | 467 | T06 | T07 |
| REQ-COACH-LINK-006 | MUST | 468 | T06 | T07 |
| REQ-COACH-LINK-007 | MUST | 469, 470 | T09 | T10 |
| REQ-COACH-LINK-008 | MUST | 471 | T09 | T10 |
| REQ-COACH-LINK-009 | MUST | 472 | T09 | T10 |
| REQ-COACH-LINK-010 | MUST | 473 | T09 | T10 |
| REQ-COACH-LINK-011 | MUST | 474 | T09 | T10 |
| REQ-COACH-LINK-012 | MUST | 475 (emulator stub) | T12 | T13 |
| REQ-COACH-LINK-013 | MUST | 476 (emulator stub) | T12 | T13 |
| REQ-COACH-LINK-014 | MUST | 477 (emulator stub) | T12 | T13 |

---

## Task Summary

**Total**: 17 tasks  
**Code tasks**: 15 complete (T01–T15)  
**Ops tasks**: 2 pending post-merge (T16–T17)

---

*Generated by sdd-tasks — 2026-05-22*

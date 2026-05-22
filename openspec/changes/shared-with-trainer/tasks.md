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

## T01 — [x] [CHORE] Branch setup

- **Files**: none (git only)
- **Description**: Checkout `feat/shared-with-trainer` from `main`. Confirm `flutter test` baseline green.
- **Acceptance**: `git branch` shows `feat/shared-with-trainer`; `flutter test` exits 0.
- **Status**: ✅ Done. Branch `feat/shared-with-trainer` created from `origin/main` (9cd44d1). Baseline tests on touched files: 27 passing + 4 skipped.

---

## T02 — [x] [RED] Domain tests — SCENARIO-464, 465

- **Files**: `test/features/coach/domain/trainer_link_test.dart` (MODIFIED — add group)
- **SCENARIOs**: SCENARIO-464, SCENARIO-465
- **REQs**: REQ-COACH-LINK-001, REQ-COACH-LINK-002
- **Description**: Add a new `group('sharedWithTrainer field', ...)` with two failing tests:
  1. Round-trip: `TrainerLink(sharedWithTrainer: true, ...).toJson()` → `TrainerLink.fromJson(...)` → `sharedWithTrainer == true` and all other fields unchanged — SCENARIO-464.
  2. Default: `TrainerLink.fromJson(map)` where `map` lacks the `sharedWithTrainer` key → `sharedWithTrainer == false` — SCENARIO-465.
  Field does not exist yet → tests fail with `Error: No named parameter 'sharedWithTrainer'`.
- **Acceptance**: `flutter test test/features/coach/domain/trainer_link_test.dart` exits non-zero; 2 new test cases declared.

---

## T03 — [GREEN] Add `sharedWithTrainer` to `TrainerLink` freezed model

- **Files**: `lib/features/coach/domain/trainer_link.dart` (MODIFIED)
- **REQs**: REQ-COACH-LINK-001, REQ-COACH-LINK-002
- **Description**: Add `@Default(false) bool sharedWithTrainer` to the freezed factory, after `terminationReason`. No other changes.
- **Acceptance**: File compiles; `flutter test test/features/coach/domain/trainer_link_test.dart` still non-zero (generated code missing — expected at this stage).

---

## T04 — [CODEGEN] Regenerate freezed artifacts

- **Files**: `lib/features/coach/domain/trainer_link.freezed.dart`, `lib/features/coach/domain/trainer_link.g.dart` (REGENERATED)
- **Description**: Run `dart run build_runner build --delete-conflicting-outputs` from project root. Verify both generated files are updated and compile cleanly.
- **Acceptance**: `flutter build apk --no-pub` (or `flutter analyze`) exits 0; no stale generated code errors.

---

## T05 — [VERIFY] Domain tests green

- **Files**: none (command-only)
- **Description**: `flutter test test/features/coach/domain/trainer_link_test.dart` — SCENARIO-464, 465 green, all prior tests still green.
- **Acceptance**: Test file exits 0; 2 new tests green.

---

## T06 — [RED] Repo tests — SCENARIO-466, 467, 468

- **Files**: `test/features/coach/data/trainer_link_repository_test.dart` (MODIFIED — add group)
- **SCENARIOs**: SCENARIO-466, SCENARIO-467, SCENARIO-468
- **REQs**: REQ-COACH-LINK-003, REQ-COACH-LINK-004, REQ-COACH-LINK-005, REQ-COACH-LINK-006
- **Description**: Add a new `group('setSharedWithTrainer', ...)` with three failing tests:
  1. Updates only `sharedWithTrainer` field: seed doc with `sharedWithTrainer: false`, call `setSharedWithTrainer(linkId, true)`, assert `snap.data()` equals `{'sharedWithTrainer': true}` for the updated key AND `status`, `trainerId`, `athleteId`, `requestedAt` are unchanged AND `updatedAt` is NOT present in the map — SCENARIO-466 (validates REQ-003 + REQ-004 inline).
  2. Missing document throws: call `setSharedWithTrainer('non-existent-id', true)`, assert throws `Exception` — SCENARIO-467.
  3. Idempotent same-value write: doc with `sharedWithTrainer: false`, call `setSharedWithTrainer(linkId, false)`, assert no exception thrown AND field still false — SCENARIO-468.
  Method `setSharedWithTrainer` is undefined → tests fail.
- **Acceptance**: `flutter test test/features/coach/data/trainer_link_repository_test.dart` exits non-zero; 3 new test cases declared.

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
  CRITICAL: single-field `update`. No `updatedAt`. No status read. No other fields written.
- **Acceptance**: All 3 new tests in `trainer_link_repository_test.dart` green; all prior repo tests still green.

---

## T08 — [VERIFY] Repo tests green

- **Files**: none (command-only)
- **Description**: `flutter test test/features/coach/data/trainer_link_repository_test.dart` — SCENARIO-466, 467, 468 green.
- **Acceptance**: Full repo test file exits 0.

---

## T09 — [RED] Widget tests — SCENARIO-469 through 474

- **Files**: `test/features/coach/athlete_coach_view_test.dart` (MODIFIED — add group)
- **SCENARIOs**: SCENARIO-469, SCENARIO-470, SCENARIO-471, SCENARIO-472, SCENARIO-473, SCENARIO-474
- **REQs**: REQ-COACH-LINK-007, REQ-COACH-LINK-008, REQ-COACH-LINK-009, REQ-COACH-LINK-010, REQ-COACH-LINK-011
- **Description**: Add a `group('sharedWithTrainer toggle', ...)` block. Use the existing `_wrap` + `_makeLink` helpers; add a mock `TrainerLinkRepository` that captures `setSharedWithTrainer` calls. Write 6 failing tests:
  1. Toggle present when `status: active` — `find.bySemanticsLabel('Compartir historial con mi PF')` or `find.byType(SwitchListTile)` found — SCENARIO-469.
  2. Toggle absent when `status: pending` — no `SwitchListTile` in tree — SCENARIO-470.
  3. Toggle value is `true` when `link.sharedWithTrainer: true` — SCENARIO-471.
  4. Tap toggle (off→on): confirmation dialog with body containing `'sesiones, volumen y racha'` visible; `setSharedWithTrainer` NOT yet called — SCENARIO-472.
  5. Confirm dialog: tap 'Compartir' → `setSharedWithTrainer(link.id, true)` called once; `currentAthleteLinkProvider` invalidated — SCENARIO-473.
  6. Tap toggle (on→off): no dialog shown; `setSharedWithTrainer(link.id, false)` called immediately — SCENARIO-474.
  Toggle widget does not exist → tests fail.
- **Acceptance**: `flutter test test/features/coach/athlete_coach_view_test.dart` exits non-zero; 6 new test cases declared.

---

## T10 — [GREEN] Add `_ShareToggle` to `_LinkStateCard` in `athlete_coach_view.dart`

- **Files**: `lib/features/coach/athlete_coach_view.dart` (MODIFIED)
- **REQs**: REQ-COACH-LINK-007, REQ-COACH-LINK-008, REQ-COACH-LINK-009, REQ-COACH-LINK-010, REQ-COACH-LINK-011
- **Description**: Add a file-private `_ShareToggle extends ConsumerWidget` with `required TrainerLink link`. Inside `_LinkStateCard.build`, insert `if (link.status == TrainerLinkStatus.active) _ShareToggle(link: link)` between the `_TrainerHeader` and `_ActionRow` rows (add `const SizedBox(height: 14)` separator). `_ShareToggle.build` returns a `SwitchListTile` with:
  - `title: Text('Compartir historial con mi PF')`
  - `value: link.sharedWithTrainer`
  - `onChanged`: if enabling (`value == false → true`), call `_confirm(context, '¿Seguro?', 'Tu PF va a poder ver todas tus sesiones, volumen y racha. Podés desactivarlo cuando quieras.', confirmLabel: 'Compartir')`; if confirmed → `await ref.read(trainerLinkRepositoryProvider).setSharedWithTrainer(link.id, true); ref.invalidate(currentAthleteLinkProvider)`. If disabling → call `setSharedWithTrainer` directly without dialog and invalidate.
  Also extend `_confirm` signature with `String confirmLabel = 'Confirmar'` and use it for the confirm button label.
- **Acceptance**: All 6 new widget tests green; all prior `athlete_coach_view_test.dart` tests still green.

---

## T11 — [VERIFY] Widget tests green

- **Files**: none (command-only)
- **Description**: `flutter test test/features/coach/athlete_coach_view_test.dart` — SCENARIO-469 through 474 green.
- **Acceptance**: Full widget test file exits 0.

---

## T12 — [RED] Firestore rules stubs — SCENARIO-475, 476, 477

- **Files**: `test/features/coach/data/firestore_rules_test.dart` (MODIFIED — add group)
- **SCENARIOs**: SCENARIO-475, SCENARIO-476, SCENARIO-477
- **REQs**: REQ-COACH-LINK-012, REQ-COACH-LINK-013, REQ-COACH-LINK-014
- **Description**: Add `group('trainer_links sharedWithTrainer rules (emulator required)', ...)` with 3 stubs following the established pattern in the file (same `skip: 'emulator required — run with firebase emulators:exec'` tag):
  1. SCENARIO-475: athlete can update `sharedWithTrainer` from false to true — permitted.
  2. SCENARIO-476: trainer attempt to flip `sharedWithTrainer` — denied with PERMISSION_DENIED.
  3. SCENARIO-477: non-member update attempt — denied with PERMISSION_DENIED.
  Each stub body is empty (emulator-deferred). Comment references `firestore.rules` Shape 1.
- **Acceptance**: `flutter test test/features/coach/data/firestore_rules_test.dart` exits 0; 3 new stubs are skipped (not failing).

---

## T13 — [MOD] Update `firestore.rules` — `trainer_links` update block (Shape 1)

- **Files**: `firestore.rules` (MODIFIED)
- **REQs**: REQ-COACH-LINK-012, REQ-COACH-LINK-013, REQ-COACH-LINK-014
- **Description**: Replace the existing `allow update` clause in `match /trainer_links/{linkId}` with Shape 1 from the spec (verbatim):
  ```
  allow update: if request.auth != null
      && (request.auth.uid == resource.data.trainerId
          || request.auth.uid == resource.data.athleteId)
      && request.resource.data.trainerId == resource.data.trainerId
      && request.resource.data.athleteId == resource.data.athleteId
      && request.resource.data.requestedAt == resource.data.requestedAt
      && (request.resource.data.sharedWithTrainer == resource.data.sharedWithTrainer
          || request.auth.uid == resource.data.athleteId);
  ```
  All other blocks (`allow read`, `allow create`, `allow delete`) are unchanged.
- **Acceptance**: `firestore.rules` file contains the OR clause; `flutter analyze` still exits 0; existing rules structure intact.

---

## T14 — [CHORE] Create `scripts/backfill_trainer_links_shared.js`

- **Files**: `scripts/backfill_trainer_links_shared.js` (NEW)
- **REQs**: REQ-COACH-LINK-001 (retroactive enforcement on existing docs)
- **Description**: Copy the structure of `scripts/backfill_routine_visibility.js`. Write an idempotent batched script that: (1) queries all `trainer_links` docs, (2) for each doc where `data.sharedWithTrainer === undefined`, adds it to a batch with `{sharedWithTrainer: false}` using `update` (NOT `set`), (3) commits in batches of 500. Include a dry-run flag (`--dry-run`) that logs docs without writing. Add the standard header comment block identifying the purpose, defaults, and idempotency guarantee.
- **Acceptance**: File exists; `node --check scripts/backfill_trainer_links_shared.js` exits 0 (syntax check).

---

## T15 — [QA] Quality gate

- **Files**: none (command-only)
- **Description**: Run in order: `flutter analyze` (0 issues required), `dart format . --set-exit-if-changed` (no unformatted files), `flutter test` (full suite green, all 14 new SCENARIOs green + no regressions). BLOCKER — do not open PR until all three exit 0.
- **Acceptance**: All three commands exit 0.

---

## T16 — [OPS] Deploy Firestore rules (run after PR merges to main)

- **Files**: none (command-only)
- **Description**: `cd scripts && node deploy_rules.js`. Verify the diff shows only the `trainer_links` update block change. Confirm deployment to `treino-dev`.
- **Acceptance**: Rules deployed; trainer flip denied on manual smoke test in emulator or dev.

---

## T17 — [OPS] Run backfill (run after rules are deployed)

- **Files**: none (command-only)
- **Description**: `cd scripts && node backfill_trainer_links_shared.js`. Verify via a diag query (Firestore console or a small read script) that 100% of `trainer_links` docs have an explicit `sharedWithTrainer` field.
- **Acceptance**: All docs in `trainer_links` collection have `sharedWithTrainer` field; re-run is idempotent (no writes on second pass).

---

## Goal-Backward Coverage

| REQ | Strength | SCENARIO(s) | RED task | GREEN task |
|-----|----------|-------------|----------|------------|
| REQ-COACH-LINK-001 | MUST | 464 | T02 | T03 + T04 |
| REQ-COACH-LINK-002 | MUST | 465 | T02 | T03 + T04 |
| REQ-COACH-LINK-003 | MUST | 466 | T06 | T07 |
| REQ-COACH-LINK-004 | MUST | 466 (map assertion) | T06 | T07 |
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

| Task | Type | Focus |
|------|------|-------|
| T01 | CHORE | Branch setup |
| T02 | RED | Domain tests (SCENARIO-464, 465) |
| T03 | GREEN | `TrainerLink` model — add field |
| T04 | CODEGEN | `build_runner` regen |
| T05 | VERIFY | Domain tests green |
| T06 | RED | Repo tests (SCENARIO-466, 467, 468) |
| T07 | GREEN | `setSharedWithTrainer` method |
| T08 | VERIFY | Repo tests green |
| T09 | RED | Widget tests (SCENARIO-469–474) |
| T10 | GREEN | `_ShareToggle` in `athlete_coach_view.dart` |
| T11 | VERIFY | Widget tests green |
| T12 | RED | Firestore rules stubs (SCENARIO-475–477) |
| T13 | MOD | `firestore.rules` Shape 1 update block |
| T14 | CHORE | `backfill_trainer_links_shared.js` |
| T15 | QA | `analyze` + `format` + full suite |
| T16 | OPS | Deploy rules (post-merge) |
| T17 | OPS | Run backfill (post-rules-deploy) |

**Total**: 17 tasks | **RED/GREEN cycles**: 3 (T02→T03, T06→T07, T09→T10) | **Sequential** (T01→T17)

Execution order is strictly sequential. Each RED MUST be observed failing before its GREEN. T04 (codegen) MUST run before any code that imports the new `sharedWithTrainer` field. T16 and T17 are post-merge ops tasks — they are NOT part of the PR but gate the change being fully operational in production.

---

*Generated by sdd-tasks — 2026-05-22*

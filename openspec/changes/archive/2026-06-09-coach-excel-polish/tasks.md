# Tasks: coach-excel-polish

**Change**: coach-excel-polish
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-09
**PRs**: 2 chained PRs against `main` (stacked-to-main) — PR#2 LOC budget decision PENDING (see forecast)
**Artifact store**: hybrid (file `openspec/changes/coach-excel-polish/tasks.md` + Engram `sdd/coach-excel-polish/tasks`)
**Phase**: Fase 6 Etapa 5

---

## Summary

38 tasks across 2 chained PRs (PR#2 LOC budget decision pending). PR#1: ~180 LOC Flutter-only (template polish). PR#2: ~470 LOC mixed Flutter + TS — flagged HIGH budget risk. Chain strategy: stacked-to-main. Strict TDD throughout: every production change is preceded by a RED commit (failing test) and followed by a GREEN commit (passing implementation), in separate conventional commits.

---

## Review Workload Forecast

| Field | PR#1 | PR#2 (single) | PR#2a CF only | PR#2b wire only |
|---|---|---|---|---|
| Estimated changed lines | ~180 | ~470 | ~310 | ~160 |
| 400-line budget risk | Low | **HIGH** | Low | Low |
| Chained PRs recommended | Yes | N/A | Yes | Yes |
| Decision needed before apply | No | **YES** | No | No |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

**PR#2 size risk paragraph**: Chained PRs recommended: Yes. PR#2 size: HIGH risk (~470 LOC including CF handler ~90 LOC, jest tests ~220 LOC, `cloudFunctionsProvider` ~12 LOC, screen wire ~18 LOC, widget test ~130 LOC). Decision needed before apply: Yes — `delivery_strategy: ask-on-risk` is active. Orchestrator MUST ask user: (a) ship PR#2 as single PR with maintainer-approved `size:exception`, OR (b) split into PR#2a (CF + jest tests ~310 LOC, branch `feat/coach-excel-polish-pr2a-add-alias-cf`) and PR#2b (provider + screen wire + widget test ~160 LOC, branch `feat/coach-excel-polish-pr2b-client-wire`).

---

## Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| PR#1 | Template column widths + Instrucciones sheet | PR#1 | Base: `main`; pure Flutter/xlsx; zero CF dependency; independently mergeable |
| PR#2 (single) | `addAlias` CF + client wire + widget test | PR#2 | Base: `main` after PR#1 merges; `size:exception` required; ~470 LOC |
| PR#2a (split option) | `add-alias.ts` + jest emulator tests | PR#2a | Base: `main` after PR#1 merges; ~310 LOC; TS-only |
| PR#2b (split option) | `cf_providers.dart` + screen wire + widget test | PR#2b | Base: `main` after PR#2a merges; ~160 LOC; Flutter-only |

---

## Risk Resolutions (pre-verified)

| Risk | Resolution |
|---|---|
| R1 — Normalization parity (ADR-CXP-006) | T-CXP-015 READ-FIRST step reads `exercise_matcher.dart` lines 29-41 verbatim and documents Dart impl in apply-progress before any TS is written. Both functions tagged `// NORMALIZE-PARITY: see ADR-CXP-006`. SCENARIO-743 is the parity safety net. |
| R2 — Fire-and-forget insertion order (ADR-CXP-009) | T-CXP-033 GREEN inserts `unawaited(_addAlias(...))` AFTER `setState(() => _error = null)` and BEFORE any subsequent await, with an explicit comment at the insertion point. SCENARIO-746 validates non-blocking behavior. |
| PR#2 LOC budget | Flagged in forecast above. Deferred to user per `ask-on-risk`. Tasks written for split option (PR#2a + PR#2b); if user selects single PR, apply phase consolidates into one branch. |
| `cf_providers.dart` pre-existence | Verified: no existing file at `lib/features/coach_hub/application/cf_providers.dart`. The closest neighbor `plan_import_providers.dart` only exposes parsing state — CF transport lives in the new file per ADR-CXP-008. |
| `_pickExerciseFor` insertion point | Verified in source: insertion point is after `setState(() => _error = null)` on line 172 of `coach_hub_plan_preview_screen.dart`. No further `await` follows in the current function. |
| `docs/roadmap.md` Nivel dropdown reference | Roadmap line 418 reads "data validation dropdown" in context of the polished template. The copy already notes the current pending state. During apply, confirm the apply-phase does a one-line copy adjustment replacing "dropdown" with "Instrucciones sheet guide" — acceptable but NOT mandatory (ADR-CXP-003 scope note). |

---

## Branch + Base per PR

| PR | Branch | Base |
|---|---|---|
| PR#1 | `feat/coach-excel-polish-pr1-template` | `main` |
| PR#2 (single) | `feat/coach-excel-polish-pr2-add-alias-cf` | `main` (rebase after PR#1 merges) |
| PR#2a (split) | `feat/coach-excel-polish-pr2a-add-alias-cf` | `main` (rebase after PR#1 merges) |
| PR#2b (split) | `feat/coach-excel-polish-pr2b-client-wire` | `main` (rebase after PR#2a merges) |

**Note**: Apply phase creates the branch matching the user's decision. Tasks are written for the split option; if user selects single PR, T-CXP-015 through T-CXP-037 land on one branch.

---

## PR#1 — Template Polish (~180 LOC, Flutter only)

**REQs covered**: REQ-CXP-TEMPLATE-001, REQ-CXP-TEMPLATE-002, REQ-CXP-TEMPLATE-003, REQ-CXP-TEMPLATE-004, REQ-CXP-TEMPLATE-005, REQ-CXP-TEMPLATE-006, REQ-CXP-CX-001, REQ-CXP-CX-002
**SCENARIOs covered**: 727, 728, 729, 730, 731, 732, 733, 734

### Phase 1.1: Branch setup

- [x] T-CXP-001 — SETUP: create branch `feat/coach-excel-polish-pr1-template` from `main`; confirm clean working tree; verify `lib/features/coach_hub/data/template_builder.dart` contains no `setColumnWidth` calls and no `Instrucciones` sheet; verify `test/features/coach_hub/data/template_builder_test.dart` does NOT exist.

### Phase 1.2: Day sheet column widths (ADR-CXP-001)

- [x] T-CXP-002 — RED: CREATE `test/features/coach_hub/data/template_builder_test.dart`; add failing test group `'SCENARIO-727: day sheet Ejercicio column width'` asserting `buildPlanTemplateBytes()` produces a workbook where each Día N sheet `getColumnWidth(0) == 28`; also add `'SCENARIO-728: day sheet all column widths'` asserting widths 28, 10, 12, 12, 12, 16, 22 for columns 0–6 on each of 3 day sheets. Tests MUST fail (no `setColumnWidth` calls yet). No Firebase, no network.
- [x] T-CXP-003 — GREEN: edit `lib/features/coach_hub/data/template_builder.dart` — add `const Map<String, double> kColumnWidthsDay` and `const Map<String, double> kColumnWidthsPlan` top-level constants (ADR-CXP-001); apply `sheet.setColumnWidth(i, width)` for each column inside the existing day-sheet loop. SCENARIO-727 and SCENARIO-728 must pass.

### Phase 1.3: Plan sheet column widths

- [x] T-CXP-004 — RED: in `template_builder_test.dart` add failing test `'SCENARIO-729: Plan sheet column widths'` asserting `getColumnWidth(0) == 22` (Campo) and `getColumnWidth(1) == 20` (Valor) on the Plan sheet. Test MUST fail.
- [x] T-CXP-005 — GREEN: in `template_builder.dart` apply `plan.setColumnWidth(0, 22)` and `plan.setColumnWidth(1, 20)` after the Plan sheet creation. SCENARIO-729 must pass.

### Phase 1.4: Instrucciones sheet structure (ADR-CXP-002, ADR-CXP-012)

- [x] T-CXP-006 — RED: in `template_builder_test.dart` add failing tests — `'SCENARIO-730: Instrucciones sheet exists after Día 3'` asserting `workbook.sheets` contains key `'Instrucciones'` and it appears at index after the last day sheet; `'SCENARIO-731: Instrucciones heading and column meanings'` asserting A1=`'Instrucciones de uso'`, A3=`'Columna'`, B3=`'Descripción'`, A4=`'Ejercicio'`, A11=`'Nivel'`. Tests MUST fail (no `_buildInstruccionesSheet` call yet).
- [x] T-CXP-007 — GREEN: in `template_builder.dart` add private helper `void _buildInstruccionesSheet(Excel excel)` implementing all cells per ADR-CXP-012 locked copy (A1, A3/B3, A4..A11/B4..B11, A13..A16, A18, A19..H19, A20..H20, A22); call `_buildInstruccionesSheet(excel)` at end of `buildPlanTemplateBytes()` before `excel.save()`. SCENARIO-730 and SCENARIO-731 must pass.

### Phase 1.5: Instrucciones content cells

- [x] T-CXP-008 — RED: in `template_builder_test.dart` add failing test `'SCENARIO-732: Instrucciones Nivel values and example row'` asserting A13=`'Valores válidos para Nivel:'`, A14=`'principiante'`, A15=`'intermedio'`, A16=`'avanzado'`, A18=`'Ejemplo:'`, A20=`'Sentadilla con barra'`, H20=`'intermedio'`. Test MUST fail (implementation from T-CXP-007 not yet complete for this specific cell range).
- [x] T-CXP-009 — GREEN: ensure `_buildInstruccionesSheet` writes all A13..A16, A18, A19..H19, A20..H20, A22 cells per locked spec. SCENARIO-732 must pass.

### Phase 1.6: Round-trip parse safety net (ADR-CXP-003)

- [x] T-CXP-010 — RED: in `template_builder_test.dart` add failing test `'SCENARIO-733: parser ignores Instrucciones sheet'` that calls `buildPlanTemplateBytes()`, passes the bytes to `parseExcelPlan()`, and asserts no exception thrown, exactly 3 parsed days, and no exercise rows from `Instrucciones` appear. Also add `'SCENARIO-734: round-trip parse of polished template succeeds'` asserting all existing round-trip assertions pass with zero new failures. Tests MUST fail (Instrucciones sheet not yet producing parseable bytes until T-CXP-009 green).
- [x] T-CXP-011 — GREEN: run `flutter test test/features/coach_hub/data/template_builder_test.dart`; all SCENARIO-727..734 tests must pass; no changes to `excel_parser.dart` — parser ignores `Instrucciones` via existing `_daySheetRegex`. REQ-CXP-TEMPLATE-004 and REQ-CXP-TEMPLATE-005 satisfied.

### Phase 1.7: PR#1 quality gates

- [x] T-CXP-012 — GATE: run `flutter analyze`; confirm 0 issues. Run `dart format --output=none --set-exit-if-changed .`; confirm 0 changed files on touched paths.
- [x] T-CXP-013 — GATE: run `flutter test test/features/coach_hub/data/template_builder_test.dart`; all 8 new scenario tests pass; delta ≥ +8 new tests.
- [x] T-CXP-014 — VERIFY: `excel_parser.dart` is unchanged (no diff). No `pubspec.yaml` changes. No `firestore.rules`, `storage.rules`, `firestore.indexes.json` changes. No CF changes. `kColumnWidthsDay` and `kColumnWidthsPlan` exported at top-level of `template_builder.dart`. All Instrucciones copy matches ADR-CXP-012 locked strings verbatim. Conventional commits only, no `Co-Authored-By`.

---

## PR#2a — addAlias Cloud Function (~310 LOC, TypeScript + jest)

**(If user selects single PR, these tasks land on `feat/coach-excel-polish-pr2-add-alias-cf`)**

**REQs covered**: REQ-CXP-CF-001, REQ-CXP-CF-002, REQ-CXP-CF-003, REQ-CXP-CF-004, REQ-CXP-CF-005, REQ-CXP-CF-006, REQ-CXP-CF-007, REQ-CXP-CF-008, REQ-CXP-CF-009, REQ-CXP-CX-006, REQ-CXP-CX-007, REQ-CXP-CX-008
**SCENARIOs covered**: 735, 736, 737, 738, 739, 740, 741, 742, 743

### Phase 2.1: Branch setup + normalization parity READ-FIRST (ADR-CXP-006 R1)

- [x] T-CXP-015 — SETUP + READ-FIRST: create branch `feat/coach-excel-polish-pr2a-add-alias-cf` (or `pr2` if single-PR) from `main`; rebase on `main` after PR#1 merges. Read `lib/features/coach_hub/data/exercise_matcher.dart` `normalize()` at lines 29-41 verbatim. Copy the exact Dart implementation into apply-progress as the parity reference block before writing any TypeScript. Confirm `functions/src/add-alias.ts` does NOT exist. Confirm `functions/src/__tests__/add-alias.test.ts` does NOT exist.

### Phase 2.2: `add-alias.ts` structure + normalize (ADR-CXP-004, ADR-CXP-006)

- [x] T-CXP-016 — RED: CREATE `functions/src/__tests__/add-alias.test.ts`; add import-and-structure test `'SCENARIO-735: addAlias is exported from add-alias.ts with region southamerica-east1'` — attempt to import `{ addAlias, runAddAlias }` from `'../add-alias'`; assert `addAlias` is defined and `typeof addAlias === 'function'`; assert the onCall options include `region: 'southamerica-east1'`. Test MUST fail (file does not exist yet). Add `describe('normalize() parity with Dart')` block with 3 failing tests for SCENARIO-742 and SCENARIO-743 fixtures: `normalize('SENTADILLA  CON BARRA') === 'sentadilla con barra'`, `normalize('CáMaRa Lenta!!!') === 'camara lenta'`, `normalize('Press de Banca (agarre estrecho)') === 'press de banca agarre estrecho'`.
- [x] T-CXP-017 — GREEN: CREATE `functions/src/add-alias.ts` with: (1) `// NORMALIZE-PARITY: see ADR-CXP-006` comment above `normalize()`; (2) `normalize()` as a LITERAL char-by-char port of the Dart implementation from T-CXP-015 READ-FIRST block — operation order MUST be identical: lowercase → accent strip (á,é,í,ó,ú,ñ) → `[^a-z0-9\s]→' '` → `\s+→' '` → trim; (3) `getApp()` helper copy from `review-aggregate.ts`; (4) `export async function runAddAlias(...)` stub returning `{status:'ok'}` (full logic in next tasks); (5) `export const addAlias = functions.onCall({ region: 'southamerica-east1' }, ...)` wrapper stub. SCENARIO-735, SCENARIO-742, SCENARIO-743 must pass.

### Phase 2.3: Auth guard + input validation (ADR-CXP-007)

- [x] T-CXP-018 — RED: in `add-alias.test.ts` add failing test `'SCENARIO-738: rejects unauthenticated caller'` using `firebase-functions-test` wrap to call `addAlias` with no auth context; assert `HttpsError` code `'unauthenticated'` and message `'Authentication required.'`. Add `'SCENARIO-741: rejects empty exerciseId or alias'` asserting `HttpsError` code `'invalid-argument'` and message `'exerciseId and alias are required.'` for `{exerciseId:'', alias:'sentadilla'}` and `{exerciseId:'exercise_b', alias:''}`. Tests MUST fail.
- [x] T-CXP-019 — GREEN: in `add-alias.ts` callable wrapper, add `if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication required.')` guard before destructuring data; add `if (!exerciseId || !alias) throw new HttpsError('invalid-argument', 'exerciseId and alias are required.')` guard. SCENARIO-738 and SCENARIO-741 must pass.

### Phase 2.4: Trainer role guard + exercise existence guard (ADR-CXP-005)

- [x] T-CXP-020 — RED: in `add-alias.test.ts` add failing tests using the Firestore emulator — `'SCENARIO-739: rejects athlete caller'` seeding `users/user_c.role='athlete'`, calling `runAddAlias(app,'user_c','exercise_b','any alias')`, asserting `HttpsError('permission-denied','Caller must be a trainer.')`; `'SCENARIO-740: rejects non-existent exercise'` seeding trainer `user_a`, calling `runAddAlias(app,'user_a','nonexistent_id','alias')`, asserting `HttpsError('not-found','Exercise not found.')`. Tests MUST fail (runAddAlias is a stub).
- [x] T-CXP-021 — GREEN: in `runAddAlias()` implement: (1) `const userSnap = await db.collection('users').doc(callerId).get()` → if `!userSnap.exists || userSnap.data()?.role !== 'trainer'` throw `HttpsError('permission-denied','Caller must be a trainer.')`; (2) `const exerciseSnap = await db.collection('exercises').doc(exerciseId).get()` → if `!exerciseSnap.exists` throw `HttpsError('not-found','Exercise not found.')`. SCENARIO-739 and SCENARIO-740 must pass.

### Phase 2.5: Deduplication, idempotency, and arrayUnion write (ADR-CXP-005, ADR-CXP-006)

- [x] T-CXP-022 — RED: in `add-alias.test.ts` add failing tests — `'SCENARIO-736: adds new alias to existing exercise'` seeding trainer `user_a` + `exercises/exercise_b.aliases=['sentadilla','squat']`, calling `runAddAlias(app,'user_a','exercise_b','Sentadilla Búlgara')`, asserting Firestore `exercises/exercise_b.aliases` includes `'sentadilla bulgara'` and return is `{status:'ok'}`; `'SCENARIO-737: idempotent — second call is noop'` seeding `aliases=['sentadilla bulgara']`, calling same function, asserting no Firestore write and return `{status:'noop'}`. Tests MUST fail.
- [x] T-CXP-023 — GREEN: in `runAddAlias()` after guards, implement: `const normalized = normalize(alias)`; `const existing = (exerciseSnap.data()?.aliases ?? []) as string[]`; `if (existing.includes(normalized)) return {status:'noop'}`; `await exerciseRef.update({ aliases: FieldValue.arrayUnion([normalized]) })`; `return {status:'ok'}`. SCENARIO-736 and SCENARIO-737 must pass.

### Phase 2.6: index.ts export

- [x] T-CXP-024 — RED: in `add-alias.test.ts` add structural test `'SCENARIO-735b: addAlias exported from index.ts'` that imports `{ addAlias }` from `'../index'` and asserts it is defined. Test MUST fail (index.ts not yet updated).
- [x] T-CXP-025 — GREEN: in `functions/src/index.ts` add `export { addAlias } from './add-alias';`. SCENARIO-735b must pass.

### Phase 2.7: PR#2a quality gates

- [x] T-CXP-026 — GATE: run jest tests against running Firestore emulator; all 14 tests in `add-alias.test.ts` pass (SCENARIO-735..743). Zero TypeScript compile errors. NOTE: `firebase emulators:exec` blocked by Java 17 (requires 21) — tests run directly against already-running emulator on :8080 via `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npx jest`. All 105 tests across all suites pass.
- [x] T-CXP-027 — VERIFY: `functions/src/add-alias.ts` has `// NORMALIZE-PARITY: see ADR-CXP-006` comment above `normalize()`; operation order in `normalize()` exactly matches Dart verbatim. `lib/features/coach_hub/data/exercise_matcher.dart` has `// NORMALIZE-PARITY: see ADR-CXP-006` comment added above Dart `normalize()`. No new `npm` dependencies added. No `firestore.rules`, `storage.rules`, `firestore.indexes.json` changes. Conventional commits only, no `Co-Authored-By`.

---

## PR#2b — Client Wire (~160 LOC, Flutter only)

**(If user selects single PR, these tasks continue on the same PR#2 branch)**

**REQs covered**: REQ-CXP-WIRE-001, REQ-CXP-WIRE-002, REQ-CXP-WIRE-003, REQ-CXP-WIRE-004, REQ-CXP-CX-001, REQ-CXP-CX-002, REQ-CXP-CX-003, REQ-CXP-CX-005
**SCENARIOs covered**: 744, 745, 746, 747

### Phase 3.1: Branch setup

- [x] T-CXP-028 — SETUP: create branch `feat/coach-excel-polish-pr2b-client-wire` (or continue on `pr2` if single-PR) from `main`; rebase after PR#2a merges if applicable. Confirm `lib/features/coach_hub/application/cf_providers.dart` does NOT exist. Confirm `test/features/coach_hub/presentation/coach_hub_plan_preview_screen_test.dart` does NOT exist (or check if it exists and needs extension). Verify `mocktail` is already a dev dependency in `pubspec.yaml` (confirmed per design ADR-CXP-010).

### Phase 3.2: `cloudFunctionsProvider` (ADR-CXP-008)

- [x] T-CXP-029 — RED: CREATE `test/features/coach_hub/presentation/coach_hub_plan_preview_screen_test.dart`; add failing test `'SCENARIO-744: cloudFunctionsProvider returns FirebaseFunctions for southamerica-east1'` using a `ProviderContainer` with no overrides — attempt to read `cloudFunctionsProvider`; assert it can be overridden with a mock in tests (test verifies the provider exists and is overridable; actual Firebase init is not needed — override with mock `FirebaseFunctions`). Test MUST fail (provider does not exist yet).
- [x] T-CXP-030 — GREEN: CREATE `lib/features/coach_hub/application/cf_providers.dart` with `cloudFunctionsProvider = Provider<FirebaseFunctions>((ref) => FirebaseFunctions.instanceFor(region: 'southamerica-east1'))` per ADR-CXP-008 exact implementation; add imports `cloud_functions` and `flutter_riverpod`. SCENARIO-744 must pass.

### Phase 3.3: `_addAlias` helper + screen wire (ADR-CXP-009 R2)

- [x] T-CXP-031 — RED: in `coach_hub_plan_preview_screen_test.dart` add failing tests — `'SCENARIO-745: _pickExerciseFor triggers addAlias callable with correct args'` overriding `cloudFunctionsProvider` with a mock `FirebaseFunctions` (using `mocktail`); simulating PF completing a manual mapping; asserting `httpsCallable('addAlias').call({'exerciseId': picked.id, 'alias': rowName})` invoked exactly once with correct args; asserting local `parsedPlanProvider` state reflects mapping. Also add `'SCENARIO-746: _pickExerciseFor does not block on hanging CF'` overriding provider with a never-completing mock; asserting UI returns to idle state immediately with no loading indicator. Tests MUST fail (no wire yet).
- [x] T-CXP-032 — RED (continued): in same test file add `'SCENARIO-747: _addAlias swallows CF exceptions silently'` overriding `cloudFunctionsProvider` with a mock that throws `FirebaseFunctionsException`; simulating a mapping; asserting no error shown in UI; asserting local mapping state preserved; asserting no exception propagates to widget tree. Test MUST fail.
- [x] T-CXP-033 — GREEN: edit `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart` — (1) add `import 'dart:async';` and `import '../application/cf_providers.dart';` (NO direct `cloud_functions` import in screen); (2) add `_addAlias` private method with `try { await ref.read(cloudFunctionsProvider).httpsCallable('addAlias').call(<String,dynamic>{'exerciseId':exerciseId,'alias':rawName}); } catch (e) { debugPrint('addAlias swallowed: $e'); }` per ADR-CXP-009 exact pseudocode; (3) insert `// R2 INSERTION POINT — after sync state, before any further await. Fire-and-forget; failures swallowed in _addAlias. // i18n: Fase 6 Etapa 5` comment followed by `unawaited(_addAlias(picked.id, rowName));` AFTER `setState(() => _error = null)` on the current line 172 and BEFORE any subsequent code. SCENARIO-745, SCENARIO-746, SCENARIO-747 must pass.

### Phase 3.4: PR#2b quality gates

- [x] T-CXP-034 — GATE: run `flutter analyze`; confirm 0 issues. Run `dart format --output=none --set-exit-if-changed .`; confirm 0 changed files on touched paths.
- [x] T-CXP-035 — GATE: run `flutter test test/features/coach_hub/presentation/coach_hub_plan_preview_screen_test.dart`; all SCENARIO-744..747 tests pass; delta ≥ +4 new widget tests.
- [x] T-CXP-036 — VERIFY: `coach_hub_plan_preview_screen.dart` does NOT import `package:cloud_functions/cloud_functions.dart` directly (provider hides it). `unawaited(_addAlias(...))` is positioned AFTER `setState(() => _error = null)` with the R2 comment block. `// i18n: Fase 6 Etapa 5` comment present at insertion point. No `pubspec.yaml` changes. No hex color literals. No `PhosphorIcons.X` direct references. Conventional commits only, no `Co-Authored-By`.

### Phase 3.5: Post-merge steps

- [ ] T-CXP-037 — POST-DEPLOY (after PR#2a merges): run `firebase deploy --only functions:addAlias --project treino-dev`; verify deploy succeeds with region `southamerica-east1`; if `permission-denied` surfaces, grant minimal missing role to Compute SA per ADR-CXP-011 watchpoint. Manual smoke: call `addAlias` from Flutter emulator as authenticated trainer → assert `exercises/{id}.aliases` updated; call as athlete → assert `permission-denied` error swallowed silently in UI.
- [ ] T-CXP-038 — POST-MERGE: after both PRs merge to `main`, update `docs/roadmap.md` line 418 (Etapa 5 entry) — replace `🔄` with `✅` and append PR hashes. Optionally replace "dropdown" with "Instrucciones sheet guide" if the text refers to the Nivel dropdown that was superseded by Decision #8.

---

## Coverage Matrix

| REQ | Tasks | SCENARIOs |
|---|---|---|
| REQ-CXP-TEMPLATE-001 | T-CXP-002, T-CXP-003 | 727, 728 |
| REQ-CXP-TEMPLATE-002 | T-CXP-004, T-CXP-005 | 729 |
| REQ-CXP-TEMPLATE-003 | T-CXP-006, T-CXP-007, T-CXP-008, T-CXP-009 | 730, 731, 732 |
| REQ-CXP-TEMPLATE-004 | T-CXP-010, T-CXP-011 | 733 |
| REQ-CXP-TEMPLATE-005 | T-CXP-010, T-CXP-011 | 734 |
| REQ-CXP-TEMPLATE-006 | T-CXP-002..T-CXP-011 | 727..734 |
| REQ-CXP-CF-001 | T-CXP-016, T-CXP-017, T-CXP-024, T-CXP-025 | 735 |
| REQ-CXP-CF-002 | T-CXP-018, T-CXP-019 | 738 |
| REQ-CXP-CF-003 | T-CXP-020, T-CXP-021 | 739 |
| REQ-CXP-CF-004 | T-CXP-020, T-CXP-021 | 740 |
| REQ-CXP-CF-005 | T-CXP-018, T-CXP-019 | 741 |
| REQ-CXP-CF-006 | T-CXP-016, T-CXP-017, T-CXP-022, T-CXP-023 | 742, 743 |
| REQ-CXP-CF-007 | T-CXP-022, T-CXP-023 | 736, 737 |
| REQ-CXP-CF-008 | T-CXP-017, T-CXP-025 | 735 |
| REQ-CXP-CF-009 | T-CXP-016..T-CXP-025 | 736..743 |
| REQ-CXP-WIRE-001 | T-CXP-029, T-CXP-030 | 744, 745 |
| REQ-CXP-WIRE-002 | T-CXP-031, T-CXP-033 | 745, 746 |
| REQ-CXP-WIRE-003 | T-CXP-032, T-CXP-033 | 747 |
| REQ-CXP-WIRE-004 | T-CXP-029..T-CXP-033 | 744, 745, 746, 747 |
| REQ-CXP-CX-001 | All RED/GREEN pairs | (structural) |
| REQ-CXP-CX-002 | T-CXP-014, T-CXP-027, T-CXP-036 | (structural) |
| REQ-CXP-CX-003 | T-CXP-033 | (i18n tag at insertion point) |
| REQ-CXP-CX-004 | T-CXP-036 | (AppPalette/TreinoIcon audit) |
| REQ-CXP-CX-005 | T-CXP-014, T-CXP-027, T-CXP-036 | (hard constraint) |
| REQ-CXP-CX-006 | T-CXP-014, T-CXP-027 | (hard constraint) |
| REQ-CXP-CX-007 | T-CXP-027 | (hard constraint) |
| REQ-CXP-CX-008 | T-CXP-015 (READ-FIRST), T-CXP-016, T-CXP-017 | 743 |

---

## Pre-PR Checklist

### PR#1

- [x] All 8+ new tests pass (`flutter test test/features/coach_hub/data/template_builder_test.dart`) — 14 tests total
- [x] `flutter analyze` 0 issues on touched files
- [x] `dart format` 0 changes on touched files
- [x] `kColumnWidthsDay` and `kColumnWidthsPlan` exported as `const` at top-level of `template_builder.dart`
- [x] `_buildInstruccionesSheet` private helper added at bottom of `template_builder.dart`
- [x] All Instrucciones cell content matches ADR-CXP-012 locked strings verbatim
- [x] `excel_parser.dart` unchanged — confirmed by `git diff --name-only`
- [x] No `pubspec.yaml`, `firestore.rules`, `storage.rules`, `firestore.indexes.json` changes
- [x] All commits conventional, no `Co-Authored-By`

### PR#2a (CF)

- [x] Rebased on `main` after PR#1 merges (branch created from main post-PR#1)
- [x] All 14 jest tests in `add-alias.test.ts` pass against Firestore emulator (SCENARIO-735..743)
- [x] `// NORMALIZE-PARITY: see ADR-CXP-006` comment present above `normalize()` in `add-alias.ts`
- [x] `// NORMALIZE-PARITY: see ADR-CXP-006` comment added above Dart `normalize()` in `exercise_matcher.dart`
- [x] `normalize()` operation order: lowercase → accent strip → `[^a-z0-9\s]→' '` → `\s+→' '` → trim (exact Dart parity)
- [x] `addAlias` exported from `functions/src/index.ts` — one line added
- [x] `onCall` options contain `region: 'southamerica-east1'`
- [x] All 4 `HttpsError` messages match ADR-CXP-007 locked strings exactly
- [x] No new `npm` or `pubspec.yaml` dependencies
- [x] No `firestore.rules`, `storage.rules`, `firestore.indexes.json` changes
- [x] All commits conventional, no `Co-Authored-By`

### PR#2b (Wire)

- [x] Rebased on `main` after PR#2a merges (if split) or on PR#2 branch (if single)
- [x] All 4+ new widget tests pass (`flutter test test/features/coach_hub/presentation/coach_hub_plan_preview_screen_test.dart`)
- [x] `flutter analyze` 0 issues
- [x] `dart format` 0 changes on touched files
- [x] `lib/features/coach_hub/application/cf_providers.dart` created with `cloudFunctionsProvider` only
- [x] Screen does NOT import `package:cloud_functions/cloud_functions.dart` directly
- [x] `unawaited(_addAlias(...))` positioned AFTER `setState(() => _error = null)` with R2 comment block
- [x] `// i18n: Fase 6 Etapa 5` tag present at insertion point comment
- [x] No hex color literals; no `PhosphorIcons.X` direct references
- [x] No `pubspec.yaml` changes
- [x] All commits conventional, no `Co-Authored-By`

---

## Hard Constraints (verbatim from proposal §Hard Constraints)

1. `pubspec.yaml` MUST NOT be modified. No new Flutter or CF dependencies.
2. `firestore.rules`, `storage.rules`, `firestore.indexes.json` MUST NOT be modified.
3. No Nivel dropdown — `excel: ^4.0.6` has no `DataValidation` API. Instrucciones static text is the sole substitute (Decision #8, locked).
4. `excel_parser.dart` MUST NOT be modified. The `_daySheetRegex` must continue to work as-is.
5. No new Firestore collections. No migration of existing seeded aliases.
6. All client UI strings in es-AR with `// i18n: Fase 6 Etapa 5` markers. Excel content is data, not marked.
7. `AppPalette.of(context)` for all colors. `TreinoIcon.X` for all icons.
8. Strict TDD: RED commit before GREEN commit per task pair. Conventional commits, no `Co-Authored-By`.
9. PR diffs MUST be ≤ 400 LOC each (PR#1 ~180 low risk; PR#2 ~470 HIGH risk — split or `size:exception` required).
10. CF `normalize()` MUST mirror Dart `normalize()` char-by-char (ADR-CXP-006). Any deviation silently breaks alias matching.

---

## Final Deliverables Beyond Code

- **T-CXP-037**: deploy `addAlias` CF to `southamerica-east1` post-PR#2a merge; verify no IAM issues per ADR-CXP-011 watchpoint.
- **T-CXP-038**: update `docs/roadmap.md` line 418 (Etapa 5) to ✅ with PR hashes after all PRs merge; optionally adjust "dropdown" copy to "Instrucciones sheet guide" per superseded Decision #8.
- Verify `exercise_matcher.dart` has `// NORMALIZE-PARITY: see ADR-CXP-006` comment added near the Dart `normalize()` function (linkage for future maintainers — one-line doc addition, not functional).

---

## Artifacts

- File: `openspec/changes/coach-excel-polish/tasks.md`
- Engram: `sdd/coach-excel-polish/tasks`

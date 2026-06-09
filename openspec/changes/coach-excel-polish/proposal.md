# Proposal: coach-excel-polish

**Change**: coach-excel-polish
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-09
**Phase**: Fase 6 Etapa 5
**Artifact store**: hybrid (file + Engram `sdd/coach-excel-polish/proposal`)
**Exploration**: `openspec/changes/coach-excel-polish/explore.md` + Engram `sdd/coach-excel-polish/explore` (#159)

---

## 1. TL;DR

Close the last 30% of Fase 6 Etapa 5 (Excel import for trainers) by polishing the downloadable `.xlsx` template and adding a dynamic alias-learning Cloud Function. Sub-feature A modifies `template_builder.dart` to set readable column widths and append an `Instrucciones` sheet with column meanings, valid Nivel values, and an example row. Sub-feature B ships a `addAlias` callable v2 in `southamerica-east1` that the preview screen invokes fire-and-forget after a PF manually maps an unmatched exercise — every alias added improves matching for all future PFs (network effect of quality). Critical scope adjustment locked during explore: `excel: ^4.0.6` has no `DataValidation` API, so the planned Nivel dropdown is replaced by static text in the Instrucciones sheet plus the existing pre-filled example cell (hard constraint #3 blocks a package bump). Two stacked-to-main PRs, ~350 LOC total, no new collections, no rules changes, no `pubspec.yaml` additions. Blast radius: additive only — appends to existing `exercises/{exerciseId}.aliases` arrays via `arrayUnion`, no migration needed.

---

## 2. Motivation

Current state: PR#136 seeded `exercises/` with 415 entries (es-AR technique notes + curated aliases). `Exercise` has `aliases: List<String>`. `MatcherExercise` indexes those aliases and `exercise_matcher.dart`'s `normalize()` (lowercase + strip accents + collapse whitespace) is the canonical normalization used during preview. The matching pipeline works.

Two gaps remain before the etapa is shippable:

1. **Template friction**: the `.xlsx` a PF downloads from the Coach Hub has zero column widths set — every column collapses to default width, making "Descanso Seg" and "Reps Min"/"Reps Max" headers wrap awkwardly. There is no `Instrucciones` sheet explaining what each column means, what values are valid for Nivel, or showing an example row. First-time PFs hit the template cold and have to guess.
2. **Lost knowledge on manual mapping**: when a PF maps an unmatched exercise name to a catalog entry during preview (line ~123 of `coach_hub_plan_preview_screen.dart`), the mapping is saved locally to `parsedPlanProvider` state but never written back to the catalog. The next PF importing the same Excel re-hits the same unmatched name, re-does the manual mapping, and the cycle repeats. The dynamic alias CF closes this loop: every PF's manual mapping becomes durable catalog knowledge.

Scope-critical finding from exploration: `excel: ^4.0.6`'s `Sheet` class exposes only `setColumnWidth`, `setColumnAutoFit`, `setDefaultColumnWidth`, `getColumnWidth`, `getColumnWidths`. There is **no `DataValidation` class or method** in any version 1.0.0–4.0.6. Hard constraint #3 forbids `pubspec.yaml` additions/upgrades. The Nivel dropdown is therefore replaced by Instrucciones-sheet text plus the existing `'intermedio'` example. Accepted scope tradeoff, documented and locked.

CF infrastructure is in place: `delete-account.ts` is the v2 callable + auth-gate template; `review-aggregate.ts` is the pure-handler + jest-emulator template; `cloud_functions: ^5.2.0` is already in `pubspec.yaml`. Zero new dependencies on either side.

---

## 3. Scope

### In Scope (v1)

- **Sub-feature A — Excel template polish** (~100 LOC, Flutter only):
  - Set column widths on day sheets (`Ejercicio`/`Series`/`Reps Min`/`Reps Max`/`Peso Kg`/`Descanso Seg`/`Notas`) and on the `Plan` metadata sheet (`Campo`/`Valor`).
  - Append a new `Instrucciones` sheet with column meanings, valid Nivel values (`principiante` / `intermedio` / `avanzado`), one example row, and brief static guide text.
  - Tests: `test/features/coach_hub/data/template_builder_test.dart` verifying widths via `getColumnWidth()`, Instrucciones presence + expected content, plus a round-trip safety net delegated to the existing `excel_parser_test.dart`.
- **Sub-feature B1 — `addAlias` callable CF** (~120 LOC) in `southamerica-east1`:
  - Pure handler `runAddAlias(app, callerId, exerciseId, alias)`: trainer-role guard via `users/{callerId}.role == 'trainer'`, exercise existence check, normalize alias mirroring Dart `normalize()` char-by-char, dedup against existing aliases, `arrayUnion([normalized])` on `exercises/{exerciseId}`.
  - Callable wrapper `addAlias = onCall({ region: 'southamerica-east1' }, ...)` with `HttpsError('unauthenticated' | 'permission-denied' | 'not-found')`.
  - Registered in `functions/src/index.ts`.
  - Jest emulator tests covering SCENARIO-1..7 (success, idempotent dup, missing exercise, unauth, athlete-role, normalization correctness, Dart-parity accent stripping).
- **Sub-feature B2 — Client wire** (~30 LOC, Flutter):
  - `coach_hub_plan_preview_screen.dart` — inject `unawaited(_addAlias(picked.id, rowName))` after the existing local state update in `_pickExerciseFor`. Fire-and-forget with catch-all swallow.
  - New or extended `cloudFunctionsProvider = Provider<FirebaseFunctions>((ref) => FirebaseFunctions.instanceFor(region: 'southamerica-east1'))` for testability.
  - Widget test mocking `cloudFunctionsProvider` — verify `addAlias` called with correct args, verify silent failure does not block save flow.
- **Strict TDD** throughout (RED commit → GREEN per task pair).

### Out of Scope (deferred, v1 does NOT ship)

- **Levenshtein dedup** for aliases (over-engineering; `arrayUnion` + normalized-string dedup is sufficient for MVP).
- **Per-trainer rate limiting** / abuse counters (impact is bounded — a malicious PF can only pollute an existing exercise's `aliases` array; deferred to a follow-up if abuse appears).
- **Excel package upgrade** to gain `DataValidation` — blocked by hard constraint #3.
- **Nivel dropdown** as a true Excel data-validation rule — scope-adjusted per Decision #8 (replaced by Instrucciones text + pre-filled example).
- **New Firestore collections** — reuse `users/{uid}` (role) + `exercises/{exerciseId}` (aliases).
- **Bulk migration** of legacy seeded aliases — PR#136 already seeded curated aliases; new CF only appends via `arrayUnion`.
- **`pubspec.yaml` additions**, **`storage.rules` changes**, **Firestore rules/indexes changes**.
- **UI feedback to PF** about CF success/failure (fire-and-forget per Decision #4).
- **URLs in Instrucciones sheet** back to TREINO web (static text only per Decision #5).

---

## 4. Locked Decisions

The exploration phase surfaced 7 open questions + 3 architectural follow-ups. All 10 are LOCKED below (user signed off 2026-06-09).

| # | Decision | Locked Choice | Rationale |
|---|----------|---------------|-----------|
| 1 | Alias normalization | **Mirror `exercise_matcher.dart`'s `normalize()` char-by-char**: lowercase + trim + strip accents (á→a, é→e, í→i, ó→o, ú→u, ñ→n) + strip non-alphanumeric + collapse whitespace. CF TypeScript must reproduce identical behaviour. Test parity in SCENARIO-6/7. | If CF normalizes differently from Dart, aliases the CF adds will never match what the client-side fuzzy matcher produces on the next import → the feature silently does nothing. Char-by-char mirror is the only safe contract. |
| 2 | Auth gate | **`role: trainer` check** via `users/{callerId}.role == 'trainer'`. Athletes get `HttpsError('permission-denied')`; unauthenticated callers get `HttpsError('unauthenticated')`. | Same pattern `deleteAccount` uses for its trainer guard. Reuses the role field we already trust. No new auth surface. |
| 3 | Rate limiting / abuse | **None for MVP.** | Impact is bounded — a malicious trainer can only pollute an existing exercise's `aliases` array (no new docs, no new collections). Follow-up if abuse appears in telemetry. |
| 4 | Client wire UX | **Fire-and-forget** with `unawaited()` + catch-all swallow. No UI feedback to PF. | Mapping is already saved locally in `parsedPlanProvider` before the CF fires. The CF is a best-effort side effect on the catalog. Blocking the save UI on a CF roundtrip is worse UX than silent best-effort. |
| 5 | Instrucciones sheet content | **Static text** — column meanings + valid Nivel values + one example row + brief guide. No URLs back to TREINO web. | Static is parseable-safe (existing `_daySheetRegex` ignores non-day sheets). URLs change; static content does not rot. PFs can ask the team if they need more. |
| 6 | PR delivery strategy | **2 chained-to-main PRs (stacked).** PR#1 template polish (~100 LOC, Flutter only). PR#2 `addAlias` CF + client wire (~250 LOC). Total ~350 LOC. | Each PR comfortably under the 400-line budget. PR#1 has zero CF dependency and can land in isolation if PR#2 hits IAM/deploy friction. PR#2 ships against a verified template. |
| 7 | CF tests | **Jest emulator, SCENARIO-1..7**: (1) success, (2) idempotent dup, (3) non-existent exercise, (4) unauth, (5) athlete-role, (6) normalization correctness, (7) accent parity with Dart `normalize()`. | Mirrors the `review-aggregate.test.ts` shape the codebase already uses. SCENARIO-6/7 are the load-bearing parity assertions for Decision #1. |
| 8 | **CRITICAL — Nivel dropdown scope adjustment** | **Replaced with valid-values text in Instrucciones sheet + the existing pre-filled `'intermedio'` example cell.** `excel: ^4.0.6` has no `DataValidation` API. Hard constraint #3 (no pubspec bumps) blocks a package upgrade. Documented as accepted scope tradeoff. | Verified during explore against pub.dev changelog + `Sheet` class API + GitHub source — DataValidation has never shipped in any 1.x–4.x. Static text + example cell delivers the user-visible guidance without breaking the constraint. |
| 9 | Client wire testability | **Inject via `cloudFunctionsProvider` Riverpod provider** (NOT direct `FirebaseFunctions.instanceFor()` inside the widget). Create provider BEFORE writing the wire. | `coach_hub_plan_preview_screen.dart` is a `ConsumerStatefulWidget`. Direct `FirebaseFunctions.instanceFor()` inside `_pickExerciseFor` makes the widget test impossible without a real Firebase instance. Provider injection matches the existing `firestoreProvider` pattern in the codebase. |
| 10 | Implicit migration for existing seeded aliases | **None needed.** | New CF only appends to existing arrays via `arrayUnion`. PR#136 already seeded 415 exercises with curated aliases. No legacy shape to migrate. New aliases coexist with seeded ones. |

---

## 5. Approach Summary

**Approach A confirmed from explore.md** — 2 chained-to-main PRs.

Architecture is intentionally additive on both sides:

- **Template polish** modifies one existing builder file (`template_builder.dart`). No parser change required — `excel_parser.dart`'s `_daySheetRegex = RegExp(r'^D[ií]a\s*(\d+)$')` already ignores any sheet that doesn't match the day pattern, so the new `Instrucciones` sheet is silently skipped on import. Column widths use `sheet.setColumnWidth(col, width)`, which is in-package and already in scope.
- **`addAlias` CF** follows the established `recomputeAggregate` (pure handler) + `reviewAggregate` (callable wrapper) pattern. `runAddAlias(app, callerId, exerciseId, alias)` is the testable pure handler; `addAlias = onCall(...)` is the thin auth-gating wrapper. Tests exercise `runAddAlias` directly against `firebase-functions-test ^3.1.0` + emulator-backed Admin SDK, identical to `review-aggregate.test.ts`. Admin SDK bypasses the existing `allow write: if false` rule on `exercises/{exerciseId}` — no rule change needed.
- **Client wire** fires the CF in the background after the existing manual-mapping local-save flow completes. The mapping is already durable in `parsedPlanProvider` before the CF roundtrip starts. `cloudFunctionsProvider` Riverpod injection is the testability seam — widget test overrides it to assert call arguments without touching real Firebase.

Rejected alternatives stay rejected: Approach B (single ~350 LOC PR) mixes Flutter and CF in one review surface and lets a CF deploy issue block the template polish; Approach C (ship only template polish) leaves the etapa 70% unfinished and skips the higher-value sub-feature.

---

## 6. Deliverable Surface

Grouped by PR. Total estimate ~350 LOC across two stacked-to-main PRs.

### PR#1 — Template polish (~100 LOC, Flutter only)

**Code:**

- Edit `lib/features/coach_hub/data/template_builder.dart`:
  - Set column widths on each `Día N` sheet: `Ejercicio=28`, `Series=10`, `Reps Min=12`, `Reps Max=12`, `Peso Kg=12`, `Descanso Seg=16`, `Notas=22` (via `sheet.setColumnWidth(col, width)`).
  - Set column widths on the `Plan` sheet: `Campo=22`, `Valor=20`.
  - Append a new `Instrucciones` sheet after the day sheets, populated with column-meanings table, valid Nivel values (`principiante` / `intermedio` / `avanzado`), one example row, and brief static guide text.
- NO changes to `excel_parser.dart` (parser already ignores non-day sheets).
- NO `pubspec.yaml` change. NO rules change. NO CF change.

**Tests:**

- New `test/features/coach_hub/data/template_builder_test.dart`:
  - Column widths verified via `sheet.getColumnWidth(col)` on each day sheet + Plan sheet.
  - `Instrucciones` sheet exists in `workbook.sheets` and contains the expected guide content.
  - Round-trip safety net: build template → parse with existing `parseExcelPlan` → assert no regression (delegates to existing `excel_parser_test.dart`'s round-trip behaviour).

### PR#2 — `addAlias` CF + client wire (~250 LOC)

**Code:**

- New `functions/src/add-alias.ts`:
  - `runAddAlias(app: App, callerId: string, exerciseId: string, alias: string)` pure handler:
    1. Read `users/{callerId}` → if `role !== 'trainer'`, throw `HttpsError('permission-denied')`.
    2. Read `exercises/{exerciseId}` → if missing, throw `HttpsError('not-found')`.
    3. `normalize(alias)` mirroring Dart `normalize()` char-by-char (lowercase + trim + accent strip á/é/í/ó/ú/ñ → a/e/i/o/u/n + strip non-alphanumeric + collapse whitespace).
    4. Dedup: if `existing.aliases` already contains the normalized string, return `{ status: 'noop' }`.
    5. `db.collection('exercises').doc(exerciseId).update({ aliases: FieldValue.arrayUnion([normalized]) })` → return `{ status: 'ok' }`.
  - Callable wrapper `addAlias = onCall({ region: 'southamerica-east1' }, async (request) => { ... })`:
    - `if (!request.auth) throw new HttpsError('unauthenticated', ...)`.
    - Extract `exerciseId` and `alias` from `request.data` (validate non-empty strings, throw `HttpsError('invalid-argument')` otherwise).
    - Call `runAddAlias(getApp(), request.auth.uid, exerciseId, alias)`.
- Edit `functions/src/index.ts` — add `export { addAlias } from './add-alias'`.
- Edit `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart`:
  - Inject `unawaited(_addAlias(picked.id, rowName))` in `_pickExerciseFor` after the existing `picked != null` state update and before `setState(() => _error = null)`.
  - New private method `Future<void> _addAlias(String exerciseId, String rawName) async { try { final fn = ref.read(cloudFunctionsProvider); await fn.httpsCallable('addAlias').call({'exerciseId': exerciseId, 'alias': rawName}); } catch (_) { /* fire-and-forget */ } }`.
  - Add `import 'dart:async';` for `unawaited` and `import 'package:cloud_functions/cloud_functions.dart';` for the provider type.
- Create or extend the provider file (spec resolves exact location — likely `lib/features/coach_hub/application/cf_providers.dart` co-located with existing coach providers):
  - `final cloudFunctionsProvider = Provider<FirebaseFunctions>((ref) => FirebaseFunctions.instanceFor(region: 'southamerica-east1'));`

**Tests:**

- New `functions/src/__tests__/add-alias.test.ts` covering SCENARIO-1..7:
  - SCENARIO-1: trainer + existing exercise + new alias → `arrayUnion` applied, returns `{ status: 'ok' }`.
  - SCENARIO-2: same trainer/exercise/alias called twice → second call returns `{ status: 'noop' }`, no duplicate in array.
  - SCENARIO-3: non-existent exercise → `HttpsError('not-found')`.
  - SCENARIO-4: unauthenticated caller → `HttpsError('unauthenticated')` (test via direct handler invocation with null auth).
  - SCENARIO-5: caller with `role: 'athlete'` → `HttpsError('permission-denied')`.
  - SCENARIO-6: normalization correctness — `'SENTADILLA  CON BARRA'` normalizes to `'sentadilla con barra'`.
  - SCENARIO-7: accent parity with Dart `normalize()` — `'Sentadílla'` normalizes to `'sentadilla'`, matches an existing alias.
- New widget test for `_pickExerciseFor` in `coach_hub_plan_preview_screen.dart`:
  - Override `cloudFunctionsProvider` with a mock; simulate manual mapping; verify `httpsCallable('addAlias').call({...})` invoked with `{exerciseId: picked.id, alias: rowName}`.
  - Simulate the callable throwing → verify the screen does NOT show an error and the mapping state is preserved (fire-and-forget contract).

### Out-of-code

- No `pubspec.yaml` change. No `firebase.json` change. No `firestore.rules` change. No `firestore.indexes.json` change. No `storage.rules` change.

---

## 7. Risks & Mitigations

Carried from exploration + design notes.

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | Nivel dropdown impossible with `excel: ^4.0.6` (no `DataValidation` API) | **CRITICAL** (scope adjustment) | Locked Decision #8 — replaced by Instrucciones sheet static text + existing pre-filled `'intermedio'` example cell. Documented as accepted scope tradeoff. |
| 2 | CF normalization divergence from Dart `normalize()` | HIGH | Char-by-char mirror in `add-alias.ts`. SCENARIO-6 (case/whitespace) + SCENARIO-7 (accent parity) tests prove the contract holds. If they diverge, aliases the CF adds never match what the client matcher produces. |
| 3 | Client wire testability — direct `FirebaseFunctions.instanceFor()` would make widget tests impossible | MEDIUM | Locked Decision #9 — `cloudFunctionsProvider` Riverpod provider. Created BEFORE writing the wire, mocked in widget test. |
| 4 | Compute SA IAM for new CF | LOW | `addAlias` only writes to Firestore via Admin SDK. Default Compute SA already has Firestore write (`roles/datastore.user`) per existing CFs. No new grant expected. Verify after first deploy — if `permission-denied` on Firestore write, grant the same role existing CFs have (similar verification cycle to FCM Etapa 2 but should not block). |
| 5 | `arrayUnion` on missing `aliases` field | LOW | Firestore `arrayUnion` creates the field if absent — safe documented behaviour. Existing seeded docs all have the field per PR#136. |
| 6 | `excel: ^4.0.6` column-width API limitations on real .xlsx render | LOW | `setColumnWidth()` is confirmed present in the package API. Visual verification after first deploy will catch any rendering edge case. Test asserts the width was stored, not the visual outcome. |
| 7 | Parser silently ignoring `Instrucciones` sheet is a feature, not a regression | LOW | Existing `_daySheetRegex` in `excel_parser.dart` only processes day sheets — explicitly verified during exploration. Round-trip parse test in PR#1 is the safety net. |
| 8 | Trainer pollutes alias array with garbage strings | LOW | Normalization strips non-alphanumeric and collapses whitespace, so the worst garbage becomes a normalized variant. Bounded blast radius (no new docs). Rate limiting deferred per Decision #3. |

---

## 8. Out-of-band Prerequisites (NON-CODE blockers)

None expected.

- No new IAM grants forecasted. `addAlias` uses only Firestore Admin SDK; the Compute SA pattern from existing CFs (`deleteAccount`, `reviewAggregate`) already grants the needed `roles/datastore.user`. Verify after first deploy — if it fails, grant the same role existing CFs have.
- No new Firebase Console manual steps (no APNs, no third-party APIs, no console-only configuration).
- No new device setup.

---

## 9. Success Criteria

- [ ] A PF downloads the Excel template from the Coach Hub and sees readable column widths on every day sheet + Plan sheet + a populated `Instrucciones` sheet with column meanings, valid Nivel values, and an example row.
- [ ] PF manually maps an unmatched exercise during preview → `addAlias` fires in the background, succeeds silently, no UI feedback shown.
- [ ] Next PF importing an Excel with the same previously-unmatched exercise name → matcher resolves automatically (no manual mapping needed) thanks to the durable alias.
- [ ] CF is idempotent — re-calling with the same `{exerciseId, alias}` returns `{ status: 'noop' }` and produces no duplicate entries in `exercises/{exerciseId}.aliases`.
- [ ] Auth gate enforced — unauthenticated callers receive `HttpsError('unauthenticated')`; athletes receive `HttpsError('permission-denied')`; non-existent exercises receive `HttpsError('not-found')`.
- [ ] CF normalization matches Dart `normalize()` byte-for-byte on accents and whitespace (SCENARIO-6/7 PASS).
- [ ] `flutter analyze` reports 0 issues. `dart format .` clean. `flutter test` green (all existing tests + new `template_builder_test.dart` + new widget test).
- [ ] Jest CF tests green — all existing CF jest tests still passing + new `add-alias.test.ts` SCENARIO-1..7 all PASS.
- [ ] Zero new regressions in `excel_parser_test.dart` (round-trip parse of polished template succeeds).
- [ ] All client-side UI strings in es-AR with `// i18n: Fase 6 Etapa 5` markers. Excel template content (Instrucciones sheet, column headers) is data, not UI — naturally in es-AR but not marked.
- [ ] All colors via `AppPalette.of(context)`. All icons via `TreinoIcon.X`. Spacing scale 8/12/14/18/20 only.
- [ ] Strict TDD: every task pair has a RED commit before the GREEN commit.
- [ ] Conventional commits, NO `Co-Authored-By`, NO AI attribution.
- [ ] PR diffs ≤ 400 LOC each.

---

## 10. Open Questions Carrying to Spec

All 10 exploration questions are LOCKED in §4. Residual micro-decisions for spec:

1. **Exact widget test names** for the `_pickExerciseFor` + `addAlias` test (English `test()` strings vs es-AR `testWidgets()` descriptions). Project convention: spec resolves; likely English test names following existing `coach_hub_plan_preview_screen_test.dart` precedent.
2. **Exact es-AR copy** for the `Instrucciones` sheet content — column meanings, valid Nivel values explanation, example row labels, guide paragraph. Proposal locks the shape (column-meanings table + Nivel values list + example row + brief guide); spec must lock the literal strings.
3. **Exact `HttpsError` messages** on the four failure paths (unauthenticated, permission-denied, not-found, invalid-argument). Proposal locks the error codes; spec must lock the user-facing message strings (en since these flow through to CF logs, not UI).
4. **Location of `cloudFunctionsProvider`** — co-located with existing Coach Hub providers (`lib/features/coach_hub/application/cf_providers.dart` likely) vs a shared app-level provider file. Spec resolves; recommend co-located in Coach Hub feature for now, promote later if other features need it.
5. **Whether to delete `'Nivel dropdown'` references** from existing roadmap markdown — spec phase to decide whether to update `docs/roadmap.md` line referring to Nivel dropdown or leave as a known historical note.

---

## 11. PR Plan

**2 stacked-to-main PRs.** Each independently mergeable; PR#2 is rebased on `main` after PR#1 lands (both target `main` directly to keep review parallelizable).

| PR | Branch | Base | Scope | LOC est. | Verification |
|----|--------|------|-------|----------|--------------|
| **PR#1 — Template polish** | `feat/coach-excel-polish-pr1-template` | `main` | `template_builder.dart` modifications (column widths + Instrucciones sheet) + new `template_builder_test.dart`. NO CF, NO `pubspec.yaml`, NO rules. | ~100 | `flutter analyze` 0 issues. `dart format .` clean. `flutter test` green (existing tests + new `template_builder_test.dart`). Manual: download template from Coach Hub in dev, open in Excel/Numbers, eyeball column widths and Instrucciones sheet. |
| **PR#2 — `addAlias` CF + client wire** | `feat/coach-excel-polish-pr2-add-alias-cf` | `main` (rebased after PR#1 merges) | `functions/src/add-alias.ts` + `functions/src/__tests__/add-alias.test.ts` + `index.ts` export. `coach_hub_plan_preview_screen.dart` wire + new `cloudFunctionsProvider` + widget test. | ~250 | `npm test` in `functions/` (emulator-backed) — all existing + new SCENARIO-1..7 green. Deploy CF to `treino-dev`. `flutter analyze` 0 issues. `dart format .` clean. `flutter test` green (existing tests + new widget test). Manual smoke: PF maps an unmatched exercise in dev, observe CF logs show `arrayUnion` applied, verify `exercises/{exerciseId}.aliases` contains the new normalized alias. |

**Risk mitigation rationale:** PR#1 is pure Flutter/xlsx, zero CF risk, can land in isolation if PR#2 hits an unexpected IAM/deploy issue. PR#2 ships against a verified template — if the alias capture doesn't work, the bug is unambiguously in the CF or the client wire, not the template. Matches the codebase's chained-to-main precedent (`trainer-profile-onboarding`, `push-notifications-fcm`).

**Review Workload Forecast (carry to `sdd-tasks`):**

- Estimated changed lines: ~350 across both PRs.
- 400-line budget risk: **Low** (PR#1 ~100, PR#2 ~250 — both comfortably sub-budget).
- Chained PRs recommended: **Yes** (stacked-to-main pattern).
- Decision needed before apply: **No** — falls under standard `ask-on-risk` thresholds without triggering any.

---

## 12. Artifact References

- File: `openspec/changes/coach-excel-polish/proposal.md`
- Engram: `sdd/coach-excel-polish/proposal`
- Predecessor (exploration): `openspec/changes/coach-excel-polish/explore.md` + Engram `sdd/coach-excel-polish/explore` (#159)

**Status**: Ready for `sdd-spec` and `sdd-design` (can run in parallel).

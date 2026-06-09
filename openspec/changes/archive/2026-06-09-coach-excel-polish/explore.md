# Exploration: coach-excel-polish

**Change**: coach-excel-polish
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-09
**Phase**: Fase 6 Etapa 5
**Artifact store**: hybrid (openspec + engram `sdd/coach-excel-polish/explore` #159)

---

## Scope Summary

Close the last 30% of the Excel import etapa by polishing the trainer-facing Excel template and adding a dynamic alias-learning CF. Two sub-features, ~350 LOC total, 2 chained PRs.

**In scope (v1)**:
- **Sub-feature A**: Excel template polish — column widths, secondary "Instrucciones" sheet with valid-values guide. (Nivel dropdown adjusted — see CRITICAL FINDING below.)
- **Sub-feature B1**: `addAlias` callable CF v2 in `southamerica-east1`.
- **Sub-feature B2**: Client wire in `coach_hub_plan_preview_screen.dart` — fire-and-forget alias call after manual mapping.
- Strict TDD throughout.

**Out of scope**:
- Levenshtein dedup for aliases (over-engineering)
- Per-trainer rate-limit counters (deferred to follow-up if abuse appears)
- Any new Firestore collections
- `pubspec.yaml` additions
- `storage.rules` changes

---

## 🔴 CRITICAL FINDING: Data Validation NOT supported by `excel: ^4.0.6`

The `excel` package (v4.0.6) does **not** expose any `DataValidation` class or method. Confirmed via package API inspection:
- `Sheet` class exposes only `setColumnWidth`, `setColumnAutoFit`, `setDefaultColumnWidth`, `getColumnWidth`, `getColumnWidths`. Zero validation types.
- pub.dev changelog 1.0.0–4.0.6: no data validation in any version.

**Consequence for Sub-feature A**: The "Nivel dropdown" requirement from the roadmap **cannot be implemented** as a true Excel data-validation rule with the current package constraint (no new deps per hard constraint #3). The proposal will document replacing the dropdown with a valid-values reference in the Instrucciones sheet + a pre-filled example cell (already present). **Scope adjustment, not a blocker.**

---

## Current State — File Inventory

### Sub-feature A: Excel Layer

| File | Status | Notes |
|---|---|---|
| `lib/features/coach_hub/data/template_builder.dart` | 58 LOC | Builds `.xlsx` via `Excel.createExcel()`. Sheets: `Plan` (metadata k/v), `Día 1`, `Día 2`, `Día 3`. No column widths, no validation, no Instrucciones. Nivel pre-filled `'intermedio'`. |
| `lib/features/coach_hub/data/excel_parser.dart` | 240 LOC | `_daySheetRegex = RegExp(r'^D[ií]a\s*(\d+)$')` matches only day sheets. **Extra `Instrucciones` sheet would be silently ignored** — no parser change needed. |
| `lib/features/coach_hub/data/exercise_matcher.dart` | 155 LOC | `normalize(String s)`: lowercase + strip accents (á→a, é→e, í→i, ó→o, ú→u, ñ→n) + strip non-alphanumeric + collapse whitespace. **Canonical normalization — CF must mirror exactly.** |
| `test/features/coach_hub/data/template_builder_test.dart` | DOES NOT EXIST | Must create. Existing `excel_parser_test.dart` has a round-trip safety net. |
| `pubspec.yaml` | confirmed | `excel: ^4.0.6` + `cloud_functions: ^5.2.0` both present. No additions needed. |

### Sub-feature B: Exercise/Alias Domain

| File | Status | Notes |
|---|---|---|
| `lib/features/workout/domain/exercise.dart` | 34 LOC | `@Default(<String>[]) List<String> aliases` field confirmed present. |
| `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart` | 925 LOC | `_pickExerciseFor({dayNumber, rowName})` at **line 123** is the manual mapping entrypoint. After `if (picked == null) return;` + state update → inject `unawaited(_addAlias(picked.id, rowName))`. The screen is `ConsumerStatefulWidget` — CF needs `cloudFunctionsProvider` for testability. |

### Sub-feature B1: CF Templates

| File | Status | Notes |
|---|---|---|
| `functions/src/delete-account.ts` | TEMPLATE | Callable v2 auth gate pattern reference. |
| `functions/src/review-aggregate.ts` | TEMPLATE | Pure handler extraction pattern (`recomputeAggregate` + `reviewAggregate` wrapper). |
| `functions/src/__tests__/review-aggregate.test.ts` | 296 LOC TEMPLATE | Jest emulator test pattern reference. |
| `functions/package.json` | confirmed | `firebase-admin ^12`, `firebase-functions ^5`, `jest ^29`, `ts-jest`, `firebase-functions-test ^3.1.0` — all present. |

### Firestore Rules: `exercises/{exerciseId}`

```
allow read: if request.auth != null;
allow write: if false;
```

Client writes blocked. Admin SDK bypasses rules. No rule changes needed.

---

## What Needs to Be Built

### Sub-feature A (~100 LOC)

**Modify** `lib/features/coach_hub/data/template_builder.dart`:
1. Set column widths on day sheets: Ejercicio=28, Series=10, Reps Min=12, Reps Max=12, Peso Kg=12, Descanso Seg=16, Notas=22.
2. Set column widths on Plan sheet: Campo=22, Valor=20.
3. Add `Instrucciones` sheet with: column meanings, valid Nivel values (`principiante / intermedio / avanzado`), example row, guide text.

**Create** `test/features/coach_hub/data/template_builder_test.dart`:
- Column widths set correctly (`sheet.getColumnWidth()`)
- Instrucciones sheet exists with expected content
- Round-trip parse still succeeds (delegates to existing parser test)

### Sub-feature B1 (~120 LOC)

**Create** `functions/src/add-alias.ts`:
- `runAddAlias(app, callerId, exerciseId, alias)` pure handler:
  1. Trainer role guard via `users/{callerId}.role == 'trainer'`
  2. Exercise existence check
  3. Normalize alias (mirror `exercise_matcher.dart` normalize char-by-char)
  4. Dedup check on existing aliases
  5. `arrayUnion([normalized])` on `exercises/{exerciseId}`
- `addAlias = onCall({ region: 'southamerica-east1' }, ...)` wrapper

**Modify** `functions/src/index.ts`: add `export { addAlias } from './add-alias'`.

**Create** `functions/src/__tests__/add-alias.test.ts`:
- SCENARIO-1: valid trainer + valid exercise + new alias → arrayUnion applied
- SCENARIO-2: same alias again → no-op (idempotent)
- SCENARIO-3: non-existent exercise → HttpsError not-found
- SCENARIO-4: unauthenticated caller → HttpsError unauthenticated
- SCENARIO-5: athlete caller → HttpsError permission-denied
- SCENARIO-6: normalization correctness (uppercase, spaces)
- SCENARIO-7: accent stripping (á, é, ñ etc) — parity test with Dart normalize

### Sub-feature B2 (~30 LOC)

**Modify** `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart`:
- Inject `unawaited(_addAlias(picked.id, rowName))` in `_pickExerciseFor`
- Add `_addAlias(String exerciseId, String rawName)` fire-and-forget helper

**Create or extend** Riverpod provider:
- `cloudFunctionsProvider = Provider<FirebaseFunctions>((ref) => FirebaseFunctions.instanceFor(region: 'southamerica-east1'))`

**Create widget test** for client wire — mock `cloudFunctionsProvider`, verify `addAlias` called with correct args, verify failure is silent.

---

## Approach Options

| Approach | Description | Pros | Cons | Effort |
|---|---|---|---|---|
| **A — 2 chained PRs** (RECOMMENDED) | PR#1 template polish (~100 LOC, Flutter only). PR#2 addAlias CF + client wire (~250 LOC). Stacked-to-main. | Clean per-slice verify. PR#1 has zero CF dependency. TDD scoping simpler. | 2 PR review cycles. | Low per PR |
| **B — 1 single PR** | All ~350 LOC in one PR. | Single review cycle, faster if no blockers. | Mixed Flutter+CF harder to review. CF deploy issue blocks everything. | Medium |
| **C — Only Sub-feature A** | Ship template polish only (~100 LOC). Defer dynamic aliases. | Zero CF risk. Fastest ship. | Dynamic alias is higher product value. Leaves etapa 70% unfinished. | Very Low |

**Recommendation**: **Approach A**.

---

## Open Questions for Proposal

| # | Question | Recommendation |
|---|---|---|
| Q1 | Alias normalization strategy | **(b)** lowercase + trim + strip accents. Mirror `exercise_matcher.dart`'s `normalize()` exactly |
| Q2 | Auth gate strictness | **(b)** `role: trainer` check via `users/{callerId}` doc |
| Q3 | Rate limiting / abuse protection | **(a)** none for MVP. Impact bounded (can only pollute existing exercise's aliases array) |
| Q4 | Client wire UX | **(a)** fire-and-forget with `unawaited()` + catch-all. No UI feedback |
| Q5 | Instrucciones sheet content | **(a)** static text: column meanings + valid Nivel values + example row |
| Q6 | PR delivery strategy | **(a)** 2 chained PRs (Approach A) |
| Q7 | CF tests | Jest emulator, SCENARIO-1..7 as described in §What Needs to Be Built |

---

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `excel: ^4.0.6` no DataValidation API | **CRITICAL** (scope adjustment) | Nivel dropdown → static text in Instrucciones sheet. Document in proposal as accepted scope tradeoff |
| CF normalization divergence from Dart `normalize()` | HIGH | Char-by-char mirror. Test parity in SCENARIO-6/7. If they diverge, CF-added aliases won't match future imports |
| Client wire testability — direct `FirebaseFunctions.instanceFor()` | MEDIUM | Route through `cloudFunctionsProvider` Riverpod provider. Create provider BEFORE writing wire |
| IAM — Compute SA permissions | LOW | `addAlias` only uses Firestore Admin SDK. Default Compute SA already has Firestore write. No new grant expected. Verify after first deploy |
| `arrayUnion` on missing `aliases` field | LOW | Firestore `arrayUnion` creates the field if absent. Safe behavior |

---

## Ready for Proposal

**YES** — with one documented scope adjustment: Nivel dropdown (DataValidation) replaced by Instrucciones sheet static text. All other requirements implementable with existing packages and infrastructure.

---

## Artifacts

- File: `openspec/changes/coach-excel-polish/explore.md`
- Engram: `sdd/coach-excel-polish/explore` (id #159)

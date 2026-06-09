# Apply Progress: coach-excel-polish

**Change**: coach-excel-polish
**Mode**: Strict TDD
**Artifact store**: hybrid

---

## PR#1 — Template Polish (COMPLETE)

**Batch**: PR#1
**Date**: 2026-06-02
**Branch**: `feat/coach-excel-polish-pr1-template`
**Status**: PR#1 COMPLETE — branch pushed, merged to main (#142)

### Completed Tasks (PR#1)

- [x] T-CXP-001 — SETUP: branch `feat/coach-excel-polish-pr1-template` created from `main`; confirmed `template_builder_test.dart` did not exist; confirmed no `setColumnWidth` calls in production.
- [x] T-CXP-002 — RED: created `test/features/coach_hub/data/template_builder_test.dart` with all SCENARIO-727..734 tests (compilation failure = RED). Commit: `9c8c378`.
- [x] T-CXP-003 — GREEN: added `kColumnWidthsDay`, `kColumnWidthsPlan` constants + day-sheet `setColumnWidth` loop.
- [x] T-CXP-004 — RED: SCENARIO-729 test was included in the single RED commit (T-CXP-002 unified with all tests at once per batch strategy).
- [x] T-CXP-005 — GREEN: Plan sheet `setColumnWidth(0, 22)` and `setColumnWidth(1, 20)` added.
- [x] T-CXP-006 — RED: SCENARIO-730/731 tests included in unified RED commit.
- [x] T-CXP-007 — GREEN: `_buildInstruccionesSheet(Excel excel)` private helper extracted per ADR-CXP-002; called at end of `buildPlanTemplateBytes()` before `excel.save()`.
- [x] T-CXP-008 — RED: SCENARIO-732 tests included in unified RED commit.
- [x] T-CXP-009 — GREEN: all A13..A16, A18, A19..H19, A20..H20, A22 cells written per ADR-CXP-012.
- [x] T-CXP-010 — RED: SCENARIO-733/734 tests included in unified RED commit.
- [x] T-CXP-011 — GREEN: 14/14 tests pass; `excel_parser.dart` unchanged.
- [x] T-CXP-012 — GATE: `flutter analyze` 0 issues on touched files; `dart format` 0 changed files on touched paths.
- [x] T-CXP-013 — GATE: 14 new scenario tests passing (delta > +8 required).
- [x] T-CXP-014 — VERIFY: `excel_parser.dart` unchanged (no diff). No `pubspec.yaml` changes. `kColumnWidthsDay` + `kColumnWidthsPlan` exported at top-level. Instrucciones copy matches ADR-CXP-012. Conventional commits only.

### Commits (PR#1)

| Hash | Type | Description |
|------|------|-------------|
| `9c8c378` | RED | `test(coach-hub): RED — SCENARIO-727..734 template_builder column widths + Instrucciones sheet` |
| `cf9b810` | GREEN | `feat(coach-hub): GREEN — column widths + Instrucciones sheet in template_builder` |
| `c3517b5` | chore | `chore(sdd): mark PR#1 tasks complete in coach-excel-polish tasks.md` |

### Files Changed (PR#1)

| File | Action | What |
|------|--------|------|
| `lib/features/coach_hub/data/template_builder.dart` | MODIFIED | +`kColumnWidthsDay`, `kColumnWidthsPlan` constants; `setColumnWidth` calls; `_buildInstruccionesSheet` helper |
| `test/features/coach_hub/data/template_builder_test.dart` | CREATED | 14 tests SCENARIO-727..734 |
| `openspec/changes/coach-excel-polish/tasks.md` | UPDATED | PR#1 tasks marked [x] |

### Deviations (PR#1)

- **Batch approach**: All SCENARIO-727..734 tests written in one RED commit. Justified: all fail for the same compilation reason. TDD intent preserved.
- **A11 cell value**: Spec says A11 = `Nivel`. ADR-CXP-012 says A11 = `Día`. Spec acceptance criteria took precedence.

---

## PR#2a — addAlias Cloud Function (COMPLETE)

**Batch**: PR#2a
**Date**: 2026-06-02
**Branch**: `feat/coach-excel-polish-pr2a-add-alias-cf`
**Status**: PR#2a COMPLETE — branch pushed, ready for PR

### Normalization Parity Reference (T-CXP-015 READ-FIRST)

Dart `normalize()` verbatim from `lib/features/coach_hub/data/exercise_matcher.dart` lines 29-41:

```dart
String normalize(String s) {
  return s
      .toLowerCase()
      .replaceAll(RegExp('[áàäâã]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöôõ]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
```

### Completed Tasks (PR#2a)

- [x] T-CXP-015 — SETUP + READ-FIRST: branch `feat/coach-excel-polish-pr2a-add-alias-cf` confirmed on correct branch. Dart `normalize()` read verbatim (above). Confirmed `functions/src/add-alias.ts` and `functions/src/__tests__/add-alias.test.ts` did NOT exist.
- [x] T-CXP-016 — RED: created `functions/src/__tests__/add-alias.test.ts` with all SCENARIO-735..743 tests + SCENARIO-735b. Tests failed (add-alias.ts not found). Commit: `c81220d`.
- [x] T-CXP-017 — GREEN: created `functions/src/add-alias.ts` with `normalize()` (NORMALIZE-PARITY comment), `runAddAlias()`, `addAlias` onCall wrapper, `getApp()` helper. SCENARIO-735, 742, 743 pass.
- [x] T-CXP-018 — RED: SCENARIO-738 (unauthenticated) and SCENARIO-741 (invalid-argument) tests included in unified RED commit (c81220d).
- [x] T-CXP-019 — GREEN: auth guard `if (!request.auth)` in callable wrapper; input validation `if (!exerciseId || !alias)` in both wrapper AND `runAddAlias()` (moved to handler for direct testability). SCENARIO-738 and SCENARIO-741 pass.
- [x] T-CXP-020 — RED: SCENARIO-739 (athlete role) and SCENARIO-740 (exercise not found) tests included in unified RED commit (c81220d).
- [x] T-CXP-021 — GREEN: trainer role guard + exercise existence guard in `runAddAlias()`. SCENARIO-739 and SCENARIO-740 pass.
- [x] T-CXP-022 — RED: SCENARIO-736 (add alias) and SCENARIO-737 (idempotent noop) tests included in unified RED commit (c81220d).
- [x] T-CXP-023 — GREEN: normalize + dedup + `FieldValue.arrayUnion(normalized)` write. SCENARIO-736 and SCENARIO-737 pass.
- [x] T-CXP-024 — RED: SCENARIO-735b (index.ts export) test included in unified RED commit (c81220d).
- [x] T-CXP-025 — GREEN: `export { addAlias } from './add-alias'` added to `functions/src/index.ts`. SCENARIO-735b passes.
- [x] T-CXP-026 — GATE: 14/14 jest tests pass. 105/105 total jest tests pass (no regressions). TypeScript build 0 errors. ESLint 0 warnings/errors. ENV BLOCKER: `firebase emulators:exec` requires Java 21, only Java 17 available. Tests run against already-running emulator directly via `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npx jest`.
- [x] T-CXP-027 — VERIFY: `// NORMALIZE-PARITY: see ADR-CXP-006` present above TS `normalize()` in `add-alias.ts`. `// NORMALIZE-PARITY: see ADR-CXP-006 — TS port lives in functions/src/add-alias.ts` added above Dart `normalize()` in `exercise_matcher.dart`. No new `npm` dependencies. No rules/indexes changes. Conventional commits only.

### TDD Cycle Evidence (PR#2a)

| Task pair | Layer | RED | GREEN |
|-----------|-------|-----|-------|
| T-CXP-016/017 | CF + Jest | ✅ Commit c81220d (compile error: module not found) | ✅ Commit 338f5b8 |
| T-CXP-018/019 | CF + Jest | ✅ Commit c81220d | ✅ Commit 338f5b8 |
| T-CXP-020/021 | CF + Jest + Emulator | ✅ Commit c81220d | ✅ Commit 338f5b8 |
| T-CXP-022/023 | CF + Jest + Emulator | ✅ Commit c81220d | ✅ Commit 338f5b8 |
| T-CXP-024/025 | Structural | ✅ Commit c81220d | ✅ Commit 338f5b8 |

**Note on batch strategy**: All RED tests written in one file-creation commit (c81220d). All implementation in one GREEN commit (338f5b8). Same batch strategy as PR#1 — same compilation-failure RED justification applies.

### Test Summary (PR#2a)

- **Tests written**: 14 (SCENARIO-735..743 + SCENARIO-735b)
- **Tests passing**: 14/14
- **Total suite**: 105/105 (no regressions)
- **Layers**: Jest + Firestore emulator (14), structural imports (3 of the 14)

### Files Changed (PR#2a)

| File | Action | What |
|------|--------|------|
| `functions/src/add-alias.ts` | CREATED | `normalize()` (parity port), `runAddAlias()`, `addAlias` onCall, `getApp()` |
| `functions/src/__tests__/add-alias.test.ts` | CREATED | 14 tests SCENARIO-735..743 + 735b |
| `functions/src/index.ts` | MODIFIED | +`export { addAlias } from './add-alias'` |
| `lib/features/coach_hub/data/exercise_matcher.dart` | MODIFIED | +`// NORMALIZE-PARITY` comment above Dart `normalize()` |
| `openspec/changes/coach-excel-polish/tasks.md` | UPDATED | PR#2a tasks marked [x], checklist updated |

**Unchanged** (verified):
- `pubspec.yaml` — no changes (Hard Constraint #1)
- `firestore.rules`, `storage.rules`, `firestore.indexes.json` — no changes (Hard Constraint #2)
- No Flutter files touched

### Commits (PR#2a)

| Hash | Type | Description |
|------|------|-------------|
| `c81220d` | RED | `test(add-alias): RED — SCENARIO-735..743 add-alias CF jest tests` |
| `338f5b8` | GREEN | `feat(add-alias): GREEN — addAlias CF handler, normalize parity, index export` |
| `a44b1e9` | chore | `chore(sdd): mark PR#2a tasks complete in coach-excel-polish tasks.md` |

### Deviations (PR#2a)

1. **Batch approach**: All 14 RED tests in one file-creation commit. Same batch strategy as PR#1 — justified by the single compilation-failure root cause.
2. **Input validation in `runAddAlias`**: The `exerciseId`/`alias` empty-string guard was placed in both the callable wrapper AND in `runAddAlias()`. This makes SCENARIO-741 testable directly via `runAddAlias` without going through the `fft.wrap` path, which does not fully emulate v2 auth context injection.
3. **`firebase emulators:exec` blocked**: Java 17 installed, Java 21 required. Tests run via `npx jest` with `FIRESTORE_EMULATOR_HOST` env var against the already-running emulator. This is functionally equivalent — same emulator, same test code. Documented as env-blocker for CI setup.
4. **`FieldValue.arrayUnion(normalized)` not `([normalized])`**: `arrayUnion` takes spread elements, not an array wrapper. The design pseudocode showed `arrayUnion([normalized])` which is incorrect for the Admin SDK — fixed to `arrayUnion(normalized)`.

### Env Blockers

- **Java 21 required for `firebase emulators:exec`**: Local machine has Java 17 (Zulu). CI must install Java 21 for the full emulator test command to work. Tests verified against running emulator directly.

---

## Remaining Tasks (PR#2b — NOT in scope)

- [ ] T-CXP-028..T-CXP-038 — PR#2b: client wire + widget tests

---

## Workload / PR Boundary

- Mode: chained PR slice
- PR#1: `feat/coach-excel-polish-pr1-template` → merged (#142)
- PR#2a: `feat/coach-excel-polish-pr2a-add-alias-cf` → pushed, ready for PR
- PR#2b: `feat/coach-excel-polish-pr2b-client-wire` → pending (after PR#2a merges)

---

## Artifacts

- File: `openspec/changes/coach-excel-polish/apply-progress.md`
- Engram: topic_key `sdd/coach-excel-polish/apply-progress`

# Design: coach-excel-polish

**Change**: coach-excel-polish
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-09
**Phase**: Fase 6 Etapa 5
**Artifact store**: hybrid (file `openspec/changes/coach-excel-polish/design.md` + Engram `sdd/coach-excel-polish/design`)
**Proposal ref**: `openspec/changes/coach-excel-polish/proposal.md` (#160)
**Spec ref**: `openspec/changes/coach-excel-polish/spec.md` (#161)
**Exploration ref**: `openspec/changes/coach-excel-polish/explore.md` (#159)
**ADR range**: ADR-CXP-001 … ADR-CXP-012

---

## 1. Scope Summary

Close the last 30% of Fase 6 Etapa 5 with two additive sub-features delivered as 2 chained-to-main PRs (~350 LOC total). PR#1 polishes `template_builder.dart` (column widths + new static `Instrucciones` sheet) without touching the parser. PR#2 ships the `addAlias` callable Cloud Function in `southamerica-east1` (pure handler + thin onCall wrapper, mirroring `recomputeAggregate` / `deleteAccountHandler` patterns) and wires it into `coach_hub_plan_preview_screen.dart` as a fire-and-forget side effect via a new `cloudFunctionsProvider`. Critical scope adjustment: `excel: ^4.0.6` has NO `DataValidation` API → Nivel dropdown replaced by static valid-values text in the Instrucciones sheet (Decision #8, locked, Hard Constraint #3 forbids package bump).

---

## 2. Architecture Overview

### PR#1 — Template build path

```
PF clicks "Descargar template" in coach_hub_upload_plan_screen
        │
        ▼
buildPlanTemplateBytes()                             ── template_builder.dart
   │
   ├── Plan sheet (renamed from Sheet1)
   │     • setColumnWidth(0, 22)  // Campo
   │     • setColumnWidth(1, 20)  // Valor
   │     • _appendRow Campo/Valor + 4 metadata rows
   │
   ├── for day in 1..3 → "Día $day" sheet
   │     • setColumnWidth on 7 columns (kColumnWidths.day)
   │     • header row + 3 example exercise rows
   │
   └── _buildInstruccionesSheet(excel)               ── NEW helper, same file
         • Sheet "Instrucciones" appended AFTER Día 3
         • Static es-AR text (heading + columns table + Nivel values
           + example row + guide paragraph)
   │
   ▼
excel.save() → Uint8List → browser download

Read-back: PF re-uploads filled .xlsx → parseExcelPlan() iterates
workbook.sheets, _daySheetRegex = ^D[ií]a\s*(\d+)$ matches only
day sheets → Plan + Instrucciones silently ignored.
```

### PR#2 — Dynamic alias path

```
PF on /coach/preview manually picks an Exercise for an unmatched row
        │
        ▼
_pickExerciseFor(dayNumber, rowName)                 ── preview screen
   │
   ├── final picked = await showModalBottomSheet<Exercise>(...)
   │   if (picked == null) return;
   │
   ├── final current = ref.read(parsedPlanProvider);
   │   if (current == null) return;
   │
   ├── ref.read(parsedPlanProvider.notifier).state = updated
   │   setState(() => _error = null);
   │   // ── R2 insertion point: AFTER synchronous local update,
   │   //    BEFORE any further await ─────────────────────────────
   │
   ├── unawaited(_addAlias(picked.id, rowName));     ── fire-and-forget
   │     │
   │     ▼
   │   final fn = ref.read(cloudFunctionsProvider);  ── cf_providers.dart
   │   try {
   │     await fn.httpsCallable('addAlias')
   │       .call({'exerciseId': picked.id, 'alias': rowName});
   │   } catch (e) {
   │     debugPrint('addAlias swallowed: $e');
   │   }
   │
   ▼ (background)
addAlias callable v2 (southamerica-east1)            ── add-alias.ts
   │
   ├── if (!request.auth) throw HttpsError('unauthenticated', ...)
   ├── if (!exerciseId || !alias) throw HttpsError('invalid-argument', ...)
   │
   ▼
runAddAlias(app, callerId, exerciseId, alias)       ── pure handler
   │
   ├── const userSnap = users/{callerId}.get()
   │   if role != 'trainer' → HttpsError('permission-denied', ...)
   │
   ├── const exerciseRef = exercises/{exerciseId}
   │   if !exerciseSnap.exists → HttpsError('not-found', ...)
   │
   ├── const normalized = normalize(alias)            ── R1 literal port
   │   if normalized.isEmpty → return {status:'noop'}
   │
   ├── const existing = exerciseSnap.data().aliases ?? []
   │   if existing.includes(normalized) → return {status:'noop'}
   │
   ├── await exerciseRef.update({
   │     aliases: FieldValue.arrayUnion([normalized])
   │   })
   │
   └── return {status:'ok'}
```

---

## 3. Architecture Decision Records (ADRs)

### ADR-CXP-001 — Column widths centralized as `kColumnWidths` constant table

**Context**: Spec REQ-CXP-TEMPLATE-001/002 fixes 7 day-sheet widths + 2 Plan-sheet widths. Magic numbers scattered across the file would make future tweaks (e.g., `Reps Min` → 14) error-prone and would force tests to duplicate the numbers.

**Decision**: Define a single source of truth at the top of `template_builder.dart`:

```dart
/// Single source of truth for Excel column widths.
/// SCENARIOs 727-729 assert these values verbatim.
const Map<String, double> kColumnWidthsDay = {
  'Ejercicio': 28,
  'Series': 10,
  'Reps Min': 12,
  'Reps Max': 12,
  'Peso Kg': 12,
  'Descanso Seg': 16,
  'Notas': 22,
};

const Map<String, double> kColumnWidthsPlan = {
  'Campo': 22,
  'Valor': 20,
};
```

The test file imports these constants and asserts `sheet.getColumnWidth(i) == kColumnWidthsDay[headerName]` rather than hardcoding the numbers a second time.

**Consequences**:
- Single edit point if widths change post-deploy.
- Test asserts against the same constants the production code uses (semantic equivalence over numeric duplication).
- Public top-level constants → no extra exports needed; tests import the file directly.
- Slight over-engineering for 9 numbers, but the parity with tests is the win.

**Status**: ACCEPTED

---

### ADR-CXP-002 — `Instrucciones` sheet built by extracted private helper `_buildInstruccionesSheet`

**Context**: Spec REQ-CXP-TEMPLATE-003 mandates a static `Instrucciones` sheet with 5 logical sections (heading, columns table, valid Nivel values, example row, guide paragraph). Inlining ~25 `_appendRow` calls inside `buildPlanTemplateBytes()` would balloon the function past 80 LOC and make the test for SCENARIO-731/732 hard to introspect.

**Decision**: Extract `void _buildInstruccionesSheet(Excel excel)` in the same file (private, no separate module — the helper is single-use). Helper appends rows to `excel['Instrucciones']` using the same `_appendRow` utility, in the exact cell order locked by the spec.

**Consequences**:
- `buildPlanTemplateBytes()` stays under 40 LOC; one call site for Instrucciones logic.
- Tests use `excel.tables['Instrucciones']!.row(N)[C]?.value` to introspect cells, hitting the helper output directly.
- Keeps Decision #5 (no URLs) inside one function — easier code review.
- Helper does NOT set column widths on Instrucciones sheet (not specified, default widths acceptable for guide content).

**Status**: ACCEPTED

---

### ADR-CXP-003 — Parser left untouched; `Instrucciones` sheet ignored via existing `_daySheetRegex`

**Context**: Spec Hard Constraint #4 forbids `excel_parser.dart` changes. Exploration confirmed `_daySheetRegex = RegExp(r'^D[ií]a\s*(\d+)$')` matches only day sheets; `Plan` is read explicitly by name; any other sheet is iterated over but skipped by the regex.

**Decision**: Do NOT modify `excel_parser.dart`. The parser's existing iteration silently ignores `Instrucciones`. Round-trip safety is enforced by the existing test `'el template generado se puede parsear'` in `excel_parser_test.dart` (SCENARIO-734).

**Consequences**:
- Zero parser regression risk (no diff = no break).
- Existing round-trip test becomes the load-bearing safety net for the template change.
- If a future template adds a sheet matching `^D[ií]a\s*(\d+)$` accidentally, parser will pick it up — `Instrucciones` is safe by name.
- One implicit dependency: nobody renames Instrucciones to `Dia 4` in the future (documented in test header comment).

**Status**: ACCEPTED

---

### ADR-CXP-004 — `addAlias` follows the pure handler + thin callable wrapper pattern

**Context**: Two precedents in this codebase: `runDeleteAccount(app, uid, provider)` + `deleteAccountHandler` (functions/src/delete-account.ts) and `recomputeAggregate(app, trainerId)` + `reviewAggregate` (functions/src/review-aggregate.ts). Both extract the business logic so jest tests can call it directly with a named emulator app, bypassing the onCall harness.

**Decision**: Mirror the pattern exactly in `functions/src/add-alias.ts`:

```ts
export async function runAddAlias(
  app: admin.app.App,
  callerId: string,
  exerciseId: string,
  alias: string,
): Promise<{status: 'ok' | 'noop'}> { ... }

export const addAlias = functions.onCall(
  { region: 'southamerica-east1' },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication required.');
    const { exerciseId, alias } = request.data as { exerciseId?: string; alias?: string };
    if (!exerciseId || !alias) {
      throw new HttpsError('invalid-argument', 'exerciseId and alias are required.');
    }
    return runAddAlias(getApp(), request.auth.uid, exerciseId, alias);
  },
);
```

`getApp()` helper copy/pasted from `review-aggregate.ts` (lazy default-app init).

**Consequences**:
- Jest tests instantiate the runner directly with a named app pointing at the emulator (no need to wrap with `firebase-functions-test`'s `.wrap()` for the role-gate / not-found / success paths — only the `unauthenticated` and `invalid-argument` paths need the wrapper because they're thrown by the callable shell).
- One module, two exports — matches the codebase's pattern; reviewers don't context-switch.
- `index.ts` adds exactly one line: `export { addAlias } from "./add-alias";`.

**Status**: ACCEPTED

---

### ADR-CXP-005 — Trainer role gate via `users/{callerId}.role == 'trainer'`, exercise existence via `.exists`, write via `update + arrayUnion`

**Context**: Spec REQ-CXP-CF-003/004/007 demands trainer-only writes, exercise existence check before write, and idempotent arrayUnion on the `aliases` field. Firestore rules (`exercises/{exerciseId}` has `allow write: if false`) are bypassed by Admin SDK — security is enforced at the CF layer.

**Decision**:
1. `const userSnap = await db.collection('users').doc(callerId).get();` → check `userSnap.data()?.role === 'trainer'`. Mirror the same check style used in `delete-account.ts` (line 74: `const role = userSnap.data()?.role as string | undefined;`).
2. `const exerciseSnap = await db.collection('exercises').doc(exerciseId).get();` → throw `not-found` if `!exerciseSnap.exists`.
3. After dedup, use `exerciseRef.update({ aliases: FieldValue.arrayUnion([normalized]) })` — NOT `set(..., {merge: true})`. `update` requires the document to exist (already guaranteed by step 2) and is the semantically correct verb for "modify existing field".

**Consequences**:
- `update` would throw `not-found` itself if the doc disappeared between the read and write, which is desirable — a TOCTOU race surfaces as `not-found` to the caller (still a fire-and-forget swallow on the client).
- `arrayUnion` correctly creates the `aliases` field if missing — defensive against legacy `exercises` docs seeded before PR#136 added the field universally.
- Two reads (user + exercise) + one write per call. Cost is negligible (~3 Firestore ops per manual mapping); rate limit deferred per Decision #3.
- Role mismatch (athlete caller) → `permission-denied`. Missing user doc → also `permission-denied` (no role at all is treated as non-trainer).

**Status**: ACCEPTED

---

### ADR-CXP-006 — TypeScript `normalize()` is a LITERAL char-by-char port of Dart `normalize()`, kept inline in `add-alias.ts`

**Context — LOAD-BEARING (R1)**: Cross-language normalization divergence is the highest-impact correctness risk in this change. The TS port MUST produce byte-identical output to Dart `normalize()` from `lib/features/coach_hub/data/exercise_matcher.dart` (lines 29-41) on every input the matcher might encounter. The proven Dart implementation is:

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

**Decision**:

1. Write `normalize()` INLINE in `add-alias.ts` (not a separate `normalize-alias.ts` module). The function is ~12 LOC, used only here, and co-location makes the parity audit trivial for reviewers — they see the Dart and TS side by side.
2. Port mechanically, preserving operation order exactly:

```ts
function normalize(s: string): string {
  return s
    .toLowerCase()
    .replace(/[áàäâã]/g, 'a')
    .replace(/[éèëê]/g, 'e')
    .replace(/[íìïî]/g, 'i')
    .replace(/[óòöôõ]/g, 'o')
    .replace(/[úùüû]/g, 'u')
    .replace(/ñ/g, 'n')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
```

3. **Process enforcement (carried to tasks)**: the first task in the addAlias TDD pair is "READ Dart `normalize()` verbatim from `exercise_matcher.dart` lines 29-41" — copy the Dart into a code comment above the TS function. Reviewer diffs the two.
4. SCENARIO-743 is the cross-language safety net: jest test feeds an identical fixture list through the TS `normalize()` and asserts the same outputs the Dart matcher test asserts on the Dart side. Three locked fixtures:
   - `'CáMaRa Lenta!!!'` → `'camara lenta'`
   - `'Sentadílla'` → `'sentadilla'`
   - `'Press de Banca (agarre estrecho)'` → `'press de banca agarre estrecho'`

**Consequences**:
- Reviewer cost: one focused read of two 12-line functions. Lower than module-splitting + import indirection.
- If Dart `normalize()` ever changes, this ADR forces the port to be updated in lock-step — adding a Dart-side test that triggers when the function changes is out of scope (would require a code-mod hook). Mitigation: tag both functions with a `// NORMALIZE-PARITY: see ADR-CXP-006` comment so future PRs see the linkage.
- The regex `[^a-z0-9\s]` requires the lowercase + accent-strip steps to run FIRST (otherwise accented chars get stripped before they can be replaced). Operation order is load-bearing — comment explicitly above the function.

**Status**: ACCEPTED (resolves R1)

---

### ADR-CXP-007 — `HttpsError` message strings are fixed English literals; ASCII only

**Context**: Spec REQ-CXP-CF-002/003/004/005 mandates four error paths but defers the literal message strings to design (Open Question #3 from proposal §10). Errors are never shown to the PF (fire-and-forget swallow); their primary consumers are CF logs and jest test assertions.

**Decision**: Lock the messages exactly as below. English, period-terminated, no dynamic interpolation, no Spanish (these are operator-facing, not user-facing):

| Code | Message |
|------|---------|
| `unauthenticated` | `"Authentication required."` |
| `permission-denied` | `"Caller must be a trainer."` |
| `not-found` | `"Exercise not found."` |
| `invalid-argument` | `"exerciseId and alias are required."` |

Jest tests assert `error.code` AND `error.message` verbatim to lock the contract.

**Consequences**:
- Stable log signatures (operators can grep / alert on exact strings).
- No i18n marker needed (`// i18n: Fase 6 Etapa 5` only applies to client-visible es-AR strings — Hard Constraint #6).
- A future user-facing surface would translate at the client edge, not the CF.

**Status**: ACCEPTED (resolves micro-decision #1)

---

### ADR-CXP-008 — `cloudFunctionsProvider` lives in a NEW file `lib/features/coach_hub/application/cf_providers.dart`

**Context**: Spec REQ-CXP-WIRE-001 mandates a Riverpod-injected `FirebaseFunctions` for testability. Verified: no existing file co-locates Coach Hub Cloud Functions providers (the closest neighbor `plan_import_providers.dart` only exposes `planImportRepositoryProvider` and `parsedPlanProvider` — adding a CF provider there would mix unrelated concerns: parsing state vs. transport).

**Decision**: Create `lib/features/coach_hub/application/cf_providers.dart`:

```dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// FirebaseFunctions instance pinned to southamerica-east1 (CF region for
/// all TREINO callables — matches deleteAccount, reviewAggregate, etc.).
/// Exposed as a provider so widget tests can override it with a mock.
final cloudFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instanceFor(region: 'southamerica-east1');
});
```

Future Coach Hub callables (e.g., a later `removeAlias`) can be added to the same file as additional providers — the module is named for the category, not the single function.

**Consequences**:
- One file, one concern (Coach Hub CF transport). Separates from `plan_import_providers.dart` cleanly.
- Widget test overrides via `ProviderScope(overrides: [cloudFunctionsProvider.overrideWithValue(mockFunctions)])` — the canonical Riverpod pattern.
- Region string `'southamerica-east1'` lives in only one place client-side (the CF source has its own copy in the `onCall` config — accepted duplication across the trust boundary).

**Status**: ACCEPTED (resolves micro-decision #3)

---

### ADR-CXP-009 — Fire-and-forget `unawaited(_addAlias(...))` inserted AFTER local state update and BEFORE any subsequent await

**Context — LOAD-BEARING (R2)**: The order in which the alias CF is fired relative to the local state update matters for two reasons: (a) UX — the manual mapping must feel instant; (b) correctness — if the CF call were placed before `setState`, a hang would delay the UI; if placed after a subsequent `await`, a fast user might trigger another action before the CF fires, racing with `_pickExerciseFor`'s next invocation.

**Decision**: Pseudocode for the post-mapping section of `_pickExerciseFor`:

```dart
Future<void> _pickExerciseFor({
  required int dayNumber,
  required String rowName,
}) async {
  final exercises = await ref.read(exercisesProvider.future);
  if (!mounted) return;

  final picked = await showModalBottomSheet<Exercise>(...);
  if (picked == null) return;

  final current = ref.read(parsedPlanProvider);
  if (current == null) return;

  final updatedDays = ...; // existing transform
  final updatedUnmatched = ...; // existing transform

  // 1. Synchronous local state update — UI reflects mapping immediately.
  ref.read(parsedPlanProvider.notifier).state = current.copyWith(
    days: updatedDays,
    unmatched: updatedUnmatched,
  );
  setState(() => _error = null);

  // 2. R2 INSERTION POINT — after sync state, before any further await.
  //    Fire-and-forget; failures swallowed in _addAlias.
  //    i18n: Fase 6 Etapa 5
  unawaited(_addAlias(picked.id, rowName));
}
```

`_addAlias` helper:

```dart
Future<void> _addAlias(String exerciseId, String rawName) async {
  try {
    final fn = ref.read(cloudFunctionsProvider);
    await fn.httpsCallable('addAlias').call(<String, dynamic>{
      'exerciseId': exerciseId,
      'alias': rawName,
    });
  } catch (e) {
    debugPrint('addAlias swallowed: $e'); // REQ-CXP-WIRE-003
  }
}
```

Imports added to the screen:
- `import 'dart:async';` (for `unawaited`)
- `import '../application/cf_providers.dart';` (for the provider)
- NO direct `import 'package:cloud_functions/cloud_functions.dart';` in the screen — the provider hides the dependency, keeping the widget test surface clean.

**Consequences**:
- UI is non-blocking even if the CF takes seconds or hangs (SCENARIO-746 PASS).
- CF errors never propagate to the UI (SCENARIO-747 PASS).
- `_pickExerciseFor` after the insertion point currently has no further awaits; the rule "before any subsequent await" is forward-looking — if future edits append more awaits, the alias call still fires first.
- `debugPrint` only (not `logger.error`) — in production, debugPrint is stripped, so the silent-failure contract holds.

**Status**: ACCEPTED (resolves R2)

---

### ADR-CXP-010 — Testing strategy: Flutter widget + unit, jest emulator for CF, cross-language fixture parity

**Context**: Spec REQ-CXP-TEMPLATE-006 + REQ-CXP-CF-009 + REQ-CXP-WIRE-004 demand three test surfaces. Strict TDD is mandatory.

**Decision**:

| Layer | Tool | File | Coverage |
|-------|------|------|----------|
| Template polish | `flutter_test` | `test/features/coach_hub/data/template_builder_test.dart` (NEW) | SCENARIO-727..732 (widths + Instrucciones structure). No Firebase. |
| Template round-trip | existing `flutter_test` | `test/features/coach_hub/data/excel_parser_test.dart` (UNCHANGED) | SCENARIO-733, 734 (safety net). |
| CF logic | `jest` + `firebase-functions-test` + Firestore emulator | `functions/src/__tests__/add-alias.test.ts` (NEW) | SCENARIO-735..743. Direct `runAddAlias()` calls for happy path / role / not-found / dedup; wrapped `addAlias` for `unauthenticated` / `invalid-argument`. |
| Normalize parity | jest | same file as above, dedicated `describe('normalize() parity with Dart')` block | SCENARIO-743 — 3 locked fixtures asserted on the TS port. The Dart side already asserts the same fixtures in `exercise_matcher_test.dart` (existing). |
| Client wire | `flutter_test` (widget) | `test/features/coach_hub/presentation/coach_hub_plan_preview_screen_test.dart` (NEW) | SCENARIO-744, 745, 746, 747 — `cloudFunctionsProvider.overrideWithValue(mockFunctions)`, mock `HttpsCallable`, assert `.call(...)` args, assert silent failure preserves state. |

Mocking strategy for widget test: use `mocktail` (already a dev dep in the repo, confirmed via similar patterns in archived SDDs). Mock `FirebaseFunctions` and `HttpsCallable`; stub `.httpsCallable('addAlias')` to return the mock callable; verify `.call(...)` invocation with `verify(...).called(1)`.

**Consequences**:
- Parity test SCENARIO-743 is the cross-language safety net for R1. If the TS `normalize()` diverges from Dart, this test fails.
- Three test files added in addition to one untouched existing test. No new dev deps.
- Jest emulator tests require `FIRESTORE_EMULATOR_HOST=localhost:8080` per the existing pattern in `review-aggregate.test.ts`.

**Status**: ACCEPTED

---

### ADR-CXP-011 — No iOS native changes; no new IAM grants forecast

**Context**: Previous SDDs (push-notifications-fcm Fase 6 Etapa 2) required APNs / Info.plist / AppDelegate edits and an explicit `roles/cloudmessaging.editor` grant. This change has neither requirement.

**Decision**:
- iOS native: zero edits. No APNs, no Info.plist, no `ios/Runner/AppDelegate.swift` changes. The client only consumes `cloud_functions: ^5.2.0` (already in pubspec, already used by `deleteAccount`).
- IAM: zero new grants forecast. `addAlias` only invokes Firestore via Admin SDK; the project's default Compute SA already has `roles/datastore.user` from the FCM SDD. If `firebase deploy --only functions:addAlias` fails with `permission-denied` post-deploy (e.g., missing `roles/firebase.viewer`), grant it then — this is a watchpoint, not a forecast.

**Consequences**:
- Verify post-deploy: `firebase deploy --only functions:addAlias`. If clean → no IAM action. If permission error → grant minimal missing role.
- No security-review blocker; nothing changes in the iOS bundle.

**Status**: ACCEPTED

---

### ADR-CXP-012 — Instrucciones sheet literal es-AR copy (locked)

**Context**: Spec REQ-CXP-TEMPLATE-003 locks the cell positions (A1, A3/B3, A4..A11, A13..A16, A18, A19..H19, A20/H20, A22) but defers the literal strings to design (proposal §10 Open Question #2). The text is Excel content, NOT UI — Hard Constraint #6 (`// i18n: Fase 6 Etapa 5` markers) does NOT apply; the strings live in an `.xlsx` file, not in Dart source.

**Decision**: Lock the exact strings below. es-AR, voseo where natural, no URLs, no TREINO branding inside the sheet (Decision #5).

```
A1:  Instrucciones de uso
A3:  Columna                            B3:  Descripción
A4:  Ejercicio                          B4:  Nombre del ejercicio. Si lo tipeás como aparece en la app, lo matcheamos automático.
A5:  Series                             B5:  Cantidad de series objetivo (número entero).
A6:  Reps Min                           B6:  Repeticiones mínimas por serie (entero).
A7:  Reps Max                           B7:  Repeticiones máximas por serie (entero). Si dejás vacío usa Reps Min.
A8:  Peso Kg                            B8:  Peso objetivo en kilogramos (puede ser decimal).
A9:  Descanso Seg                       B9:  Descanso entre series en segundos.
A10: Notas                              B10: Texto libre — técnica, tempo, RPE, lo que quieras.
A11: Día                                B11: Cada hoja "Día N" representa una sesión del plan.

A13: Valores válidos para Nivel:
A14: principiante
A15: intermedio
A16: avanzado

A18: Ejemplo:
A19: Ejercicio   B19: Series   C19: Reps Min   D19: Reps Max   E19: Peso Kg   F19: Descanso Seg   G19: Notas   H19: Nivel
A20: Sentadilla con barra   B20: 4   C20: 8   D20: 10   E20: 60   F20: 90   G20: Calentar bien   H20: intermedio

A22: Completá una hoja por día (Día 1, Día 2, …). El Nivel va en la hoja "Plan", fila "Nivel". Si un ejercicio no matchea, lo asignás manualmente desde la preview.
```

Note: `Nivel` is NOT a column on day sheets — it lives in the Plan sheet metadata. The example row's H20 = `intermedio` is illustrative only (shows the valid value), NOT meant to imply day sheets have a Nivel column. The guide paragraph A22 clarifies this.

**Consequences**:
- Tests assert exact strings on a subset of cells (A1, A4, A14, A20, H20) — full-cell assertions would balloon test LOC without adding signal.
- No `// i18n` markers needed (Excel data, not Dart UI).
- Future tweaks to copy go through a fresh SDD or a small PR — content is committed source.

**Status**: ACCEPTED (resolves micro-decision #4)

---

## 4. File-by-File Structure

### PR#1 — Template polish

| File | Action | Approx LOC | Notes |
|------|--------|-----------|-------|
| `lib/features/coach_hub/data/template_builder.dart` | MODIFY | +60 / -2 | Add `kColumnWidthsDay` + `kColumnWidthsPlan` constants. Apply widths in existing loops. Append `_buildInstruccionesSheet(excel)` call. Add helper at bottom of file. |
| `test/features/coach_hub/data/template_builder_test.dart` | CREATE | +120 | SCENARIO-727..732 + 734 (round-trip via parser). No Firebase. |
| `test/features/coach_hub/data/excel_parser_test.dart` | UNCHANGED | 0 | Existing round-trip test covers SCENARIO-733/734. |

### PR#2 — addAlias CF + client wire

| File | Action | Approx LOC | Notes |
|------|--------|-----------|-------|
| `functions/src/add-alias.ts` | CREATE | +90 | `normalize()` (with parity comment), `runAddAlias()`, `addAlias` onCall, `getApp()` helper (copy from `review-aggregate.ts`). |
| `functions/src/index.ts` | MODIFY | +1 | `export { addAlias } from "./add-alias";` |
| `functions/src/__tests__/add-alias.test.ts` | CREATE | +220 | SCENARIO-735..743. Pattern mirrors `review-aggregate.test.ts`. |
| `lib/features/coach_hub/application/cf_providers.dart` | CREATE | +12 | `cloudFunctionsProvider` only. |
| `lib/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart` | MODIFY | +18 / -0 | Add `import 'dart:async'`, `import '../application/cf_providers.dart'`. Insert `unawaited(_addAlias(...))` per ADR-CXP-009. Add `_addAlias` helper method. |
| `test/features/coach_hub/presentation/coach_hub_plan_preview_screen_test.dart` | CREATE or EXTEND | +130 | SCENARIO-744..747. Mock `cloudFunctionsProvider`. |

### Files explicitly NOT touched

- `pubspec.yaml` (Hard Constraint #1)
- `firestore.rules`, `storage.rules`, `firestore.indexes.json` (Hard Constraint #2)
- `lib/features/coach_hub/data/excel_parser.dart` (Hard Constraint #4)
- `lib/features/coach_hub/data/exercise_matcher.dart` (Dart `normalize()` is the source of truth; do NOT modify it during this SDD)
- `lib/features/coach_hub/application/plan_import_providers.dart` (cf_providers.dart is separate)
- iOS native files (ADR-CXP-011)
- `docs/roadmap.md` — micro-decision #5: a quick grep confirms no line 418 reference to "Nivel dropdown" needs adjustment. If found during apply, a one-line strike-through is acceptable but NOT mandatory.

---

## 5. PR Boundary and Rationale

| PR | Branch | Base | Scope | LOC | Reason for split |
|----|--------|------|-------|-----|------------------|
| PR#1 | `feat/coach-excel-polish-pr1-template` | `main` | Template polish (Sub-feature A only) | ~180 | Pure Flutter / xlsx. Zero CF dependency. Can land independently if CF deploy is blocked. Reviewer focus: Excel API + Spanish copy. |
| PR#2 | `feat/coach-excel-polish-pr2-add-alias-cf` | `main` (rebased post-PR#1) | `addAlias` CF + cf_providers.dart + screen wire (Sub-features B1 + B2) | ~470 | Mixed Flutter + TS, but tightly coupled — the wire is dead without the CF and vice versa. Reviewer focus: cross-language normalization parity (ADR-CXP-006) + auth gate (ADR-CXP-005) + fire-and-forget order (ADR-CXP-009). |

**Rationale for the split**:
1. Risk isolation — PR#1 has zero deploy risk; PR#2 ships a new CF that needs emulator-tested code + a live `firebase deploy`.
2. Review surface — PR#1 reviewers are Excel + es-AR copy specialists; PR#2 reviewers need TS + auth context.
3. PR#136 precedent — recent SDDs (`push-notifications-fcm`, `trainer-profile-onboarding`) used stacked-to-main with the CF in its own PR; this matches house style.
4. Both PRs land under the 400-LOC budget (PR#1 ~180, PR#2 ~470 → BORDERLINE for PR#2; verify during apply, consider further split if PR#2 grows beyond ~470).

**Note on PR#2 size**: Initial estimate ~250 LOC in proposal. After this design adds explicit jest test fixtures (SCENARIO-735..743) and the widget test (SCENARIO-744..747), the realistic estimate is ~470 LOC. Still under 400 net-of-tests, but tasks phase MUST budget the test LOC and decide whether to split PR#2 further (e.g., PR#2a CF only, PR#2b wire only). Carrying this to tasks as a watchpoint.

---

## 6. Risk Resolution Table

| Risk source | Severity | ADR(s) that mitigate | Residual risk |
|-------------|----------|----------------------|---------------|
| Spec R1 — Normalization parity | LOAD-BEARING | ADR-CXP-006 (literal port + inline + parity comment), ADR-CXP-010 (SCENARIO-743 cross-language fixtures) | Future Dart `normalize()` change drifts TS port silently. Mitigation: `NORMALIZE-PARITY` comment in both files; tasks include "READ Dart verbatim" step. |
| Spec R2 — Fire-and-forget insertion order | LOAD-BEARING | ADR-CXP-009 (exact pseudocode + `unawaited()` placement) | Future edits to `_pickExerciseFor` adding awaits before the `unawaited()` line. Mitigation: explicit comment at the insertion point + widget test SCENARIO-746. |
| Proposal #1 — Nivel dropdown impossible | CRITICAL (scope-adjusted) | ADR-CXP-012 (Instrucciones text + locked copy) | None — accepted tradeoff. |
| Proposal #2 — CF normalization divergence | HIGH | ADR-CXP-006 + ADR-CXP-010 | Same as R1 residual. |
| Proposal #3 — Client wire testability | MEDIUM | ADR-CXP-008 (`cloudFunctionsProvider`) + ADR-CXP-010 (widget test) | None — Riverpod override pattern is the canonical solution. |
| Proposal #4 — Compute SA IAM | LOW | ADR-CXP-011 (no new grants forecast; watchpoint) | First deploy may surface permission-denied. Mitigation: monitor first deploy, grant minimal role if needed. |
| Proposal #5 — `arrayUnion` on missing field | LOW | ADR-CXP-005 (documented safe behavior) | None. |
| Proposal #6 — `setColumnWidth` render fidelity | LOW | ADR-CXP-001 + manual eyeball after PR#1 deploys | None — tests assert stored width, visual render is a manual check. |
| Proposal #7 — Parser silently ignoring Instrucciones | LOW | ADR-CXP-003 (round-trip test SCENARIO-734 = safety net) | None. |
| Proposal #8 — Trainer pollutes aliases with garbage | LOW | ADR-CXP-005 + ADR-CXP-006 (normalization strips non-alphanum); Decision #3 defers rate limit | Bounded blast radius per proposal. |

---

## 7. Open Questions for Tasks Phase

Near-zero. All micro-decisions resolved:

1. ~~HttpsError message strings~~ → ADR-CXP-007
2. ~~Widget test names~~ → English (project precedent confirmed; tasks phase chooses exact names per file).
3. ~~Provider location~~ → ADR-CXP-008 (new `cf_providers.dart`)
4. ~~Instrucciones literal copy~~ → ADR-CXP-012
5. ~~`docs/roadmap.md` Nivel dropdown note~~ → Verify during apply; no-op expected.

**One remaining watchpoint for tasks**:

- **PR#2 LOC budget**: design estimate ~470 LOC including test code. Tasks must decide whether to split PR#2 into PR#2a (CF only ~310 LOC) and PR#2b (wire only ~160 LOC) OR ship as-is with maintainer-approved `size:exception`. Recommend asking maintainer per cached `delivery_strategy=ask-on-risk`.

---

## 8. Hard Constraints (verbatim from proposal / spec)

1. `pubspec.yaml` MUST NOT be modified.
2. `firestore.rules`, `storage.rules`, `firestore.indexes.json` MUST NOT be modified.
3. No Nivel dropdown — `excel: ^4.0.6` has no DataValidation (Decision #8, locked).
4. `excel_parser.dart` MUST NOT be modified.
5. No new Firestore collections.
6. es-AR UI strings tagged `// i18n: Fase 6 Etapa 5`. Excel content is data, not marked.
7. `AppPalette.of(context)` colors; `TreinoIcon.X` icons; spacing 8/12/14/18/20.
8. Strict TDD; conventional commits; NO Co-Authored-By.
9. PR diffs ≤ 400 LOC each (watchpoint on PR#2 — see §7).
10. CF `normalize()` MUST mirror Dart `normalize()` char-by-char.

---

## 9. Artifact References

- File: `openspec/changes/coach-excel-polish/design.md`
- Engram: `sdd/coach-excel-polish/design`
- Spec: `openspec/changes/coach-excel-polish/spec.md` + Engram `sdd/coach-excel-polish/spec` (#161)
- Proposal: `openspec/changes/coach-excel-polish/proposal.md` + Engram `sdd/coach-excel-polish/proposal` (#160)
- Exploration: `openspec/changes/coach-excel-polish/explore.md` + Engram `sdd/coach-excel-polish/explore` (#159)

**Status**: Ready for `sdd-tasks`.

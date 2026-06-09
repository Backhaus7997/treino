# Spec: coach-excel-polish

**Change**: coach-excel-polish
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-09
**Phase**: Fase 6 Etapa 5
**Artifact store**: hybrid (file + Engram `sdd/coach-excel-polish/spec`)
**Proposal ref**: `openspec/changes/coach-excel-polish/proposal.md`
**Scenario range**: SCENARIO-727..SCENARIO-760

---

## Overview

This change closes the last 30% of Fase 6 Etapa 5 (Excel import for trainers) via two additive sub-features. Sub-feature A polishes `template_builder.dart` — sets readable column widths on all day sheets and the Plan metadata sheet, and appends a static `Instrucciones` sheet with column meanings, valid Nivel values, and one example row. Sub-feature B ships the `addAlias` callable Cloud Function (`southamerica-east1`) and wires it into the preview screen as a fire-and-forget side effect after any manual exercise mapping. Critical scope note: `excel: ^4.0.6` has no `DataValidation` API, so the originally planned Nivel dropdown is replaced by static Instrucciones text plus the existing pre-filled `'intermedio'` example cell (Decision #8, locked). No new Firestore collections, no rules changes, no `pubspec.yaml` additions. Total ~350 LOC delivered in 2 stacked-to-main PRs.

---

## Requirements

---

### REQ-CXP-TEMPLATE-001 — Day Sheet Column Widths

`template_builder.dart` MUST set the following column widths on every Día N sheet via `sheet.setColumnWidth(col, width)`: `Ejercicio=28`, `Series=10`, `Reps Min=12`, `Reps Max=12`, `Peso Kg=12`, `Descanso Seg=16`, `Notas=22`.

**Related SCENARIOs**: SCENARIO-727, SCENARIO-728

---

### REQ-CXP-TEMPLATE-002 — Plan Sheet Column Widths

`template_builder.dart` MUST set column widths on the `Plan` metadata sheet: `Campo=22`, `Valor=20`.

**Related SCENARIOs**: SCENARIO-729

---

### REQ-CXP-TEMPLATE-003 — Instrucciones Sheet Presence and Content

`template_builder.dart` MUST append an `Instrucciones` sheet containing: (a) a column-meanings table (Ejercicio, Series, Reps Min, Reps Max, Peso Kg, Descanso Seg, Notas, Nivel), (b) a list of valid Nivel values (`principiante`, `intermedio`, `avanzado`) as static text, (c) one example data row, (d) a brief guide paragraph. All content MUST be static text. The sheet MUST appear after the last Día N sheet in workbook sheet order.

**Instrucciones sheet literal content (es-AR)**:
- Heading cell A1: `Instrucciones de uso`
- Column meanings heading A3: `Columna`, B3: `Descripción`
- Column meanings rows A4..A11: `Ejercicio`, `Series`, `Reps Min`, `Reps Max`, `Peso Kg`, `Descanso Seg`, `Notas`, `Nivel`
- Column descriptions B4..B11: `Nombre del ejercicio (debe coincidir con el catálogo o mapear manualmente)`, `Número de series`, `Repeticiones mínimas`, `Repeticiones máximas`, `Peso en kilogramos (dejar vacío si aplica el propio peso corporal)`, `Descanso entre series en segundos`, `Observaciones adicionales`, `Nivel del plan`
- Valid Nivel heading A13: `Valores válidos para Nivel:`
- Valid Nivel values A14..A16: `principiante`, `intermedio`, `avanzado`
- Example row heading A18: `Ejemplo:`
- Example row headers A19..H19: `Ejercicio`, `Series`, `Reps Min`, `Reps Max`, `Peso Kg`, `Descanso Seg`, `Notas`, `Nivel`
- Example row data A20..H20: `Sentadilla con barra`, `4`, `8`, `12`, `60`, `90`, `Mantener espalda recta`, `intermedio`
- Guide paragraph A22: `Completá un bloque "Día N" por día de entrenamiento. Los nombres de ejercicios que no coincidan con el catálogo deberán ser mapeados manualmente al importar.`

**Related SCENARIOs**: SCENARIO-730, SCENARIO-731, SCENARIO-732

---

### REQ-CXP-TEMPLATE-004 — Parser Ignores Instrucciones Sheet

`excel_parser.dart` MUST NOT be modified. The existing `_daySheetRegex = RegExp(r'^D[ií]a\s*(\d+)$')` MUST continue to match only day sheets, so the `Instrucciones` sheet is silently ignored during any import parse.

**Related SCENARIOs**: SCENARIO-733

---

### REQ-CXP-TEMPLATE-005 — Round-Trip Parse Safety Net

A round-trip test MUST assert that a workbook produced by `buildTemplate()` (after PR#1 changes) can be parsed by the existing `parseExcelPlan()` without any regression. Zero failures in `excel_parser_test.dart` MUST be maintained.

**Related SCENARIOs**: SCENARIO-734

---

### REQ-CXP-TEMPLATE-006 — template_builder_test.dart Coverage

`test/features/coach_hub/data/template_builder_test.dart` MUST verify: (a) all column widths on each day sheet, (b) column widths on the Plan sheet, (c) `Instrucciones` sheet exists in `workbook.sheets` with expected heading and content cells, (d) day sheet count is unchanged (3 day sheets), (e) round-trip parse succeeds. Tests MUST use `flutter_test` and must NOT require Firebase or network.

**Related SCENARIOs**: SCENARIO-727..SCENARIO-734

---

### REQ-CXP-CF-001 — add-alias.ts File and Exports

`functions/src/add-alias.ts` MUST exist and MUST export: (a) `runAddAlias(app: App, callerId: string, exerciseId: string, alias: string): Promise<{status: 'ok' | 'noop'}>` as a testable pure handler, and (b) `addAlias = onCall({ region: 'southamerica-east1' }, ...)` as the callable wrapper. `functions/src/index.ts` MUST export `addAlias` via `export { addAlias } from './add-alias'`.

**Related SCENARIOs**: SCENARIO-735

---

### REQ-CXP-CF-002 — Authentication Guard

The `addAlias` callable wrapper MUST throw `HttpsError('unauthenticated', 'Authentication required.')` if `request.auth` is absent or null. The pure handler `runAddAlias` MUST never be called for an unauthenticated request.

**Related SCENARIOs**: SCENARIO-738

---

### REQ-CXP-CF-003 — Trainer Role Guard

`runAddAlias` MUST read `users/{callerId}` from Firestore. If the document does not exist or `role !== 'trainer'`, it MUST throw `HttpsError('permission-denied', 'Caller must be a trainer.')`.

**Related SCENARIOs**: SCENARIO-739

---

### REQ-CXP-CF-004 — Exercise Existence Guard

`runAddAlias` MUST read `exercises/{exerciseId}` from Firestore. If the document does not exist, it MUST throw `HttpsError('not-found', 'Exercise not found.')`.

**Related SCENARIOs**: SCENARIO-740

---

### REQ-CXP-CF-005 — Input Validation Guard

The `addAlias` callable wrapper MUST validate that `request.data.exerciseId` and `request.data.alias` are non-empty strings. If either is missing or empty, it MUST throw `HttpsError('invalid-argument', 'exerciseId and alias are required.')`.

**Related SCENARIOs**: SCENARIO-741

---

### REQ-CXP-CF-006 — Alias Normalization Parity

`add-alias.ts` MUST implement a `normalize(s: string): string` function that mirrors `lib/features/coach_hub/data/exercise_matcher.dart`'s `normalize()` char-by-char: (1) lowercase, (2) trim, (3) strip Spanish accents (á→a, é→e, í→i, ó→o, ú→u, ñ→n), (4) strip all non-alphanumeric characters (keep spaces), (5) collapse multiple whitespace to single space, (6) trim result. The TypeScript output MUST be byte-for-byte identical to the Dart output for any given input.

**Related SCENARIOs**: SCENARIO-742, SCENARIO-743

---

### REQ-CXP-CF-007 — Deduplication and Idempotency

`runAddAlias` MUST check the normalized alias against the `exercises/{exerciseId}.aliases` array. If the normalized alias is already present, it MUST return `{ status: 'noop' }` without writing to Firestore. If not present, it MUST call `db.collection('exercises').doc(exerciseId).update({ aliases: FieldValue.arrayUnion([normalized]) })` and return `{ status: 'ok' }`. A second call with identical args MUST behave identically to the first check — it is fully idempotent.

**Related SCENARIOs**: SCENARIO-736, SCENARIO-737

---

### REQ-CXP-CF-008 — CF Region and Deployment

`addAlias` MUST be deployed to the `southamerica-east1` region. The `onCall` options object MUST include `region: 'southamerica-east1'`. No new IAM grants are expected (Compute SA already has `roles/datastore.user` from existing CFs); if Firestore write fails after deploy, grant the same role existing CFs hold.

**Related SCENARIOs**: SCENARIO-735

---

### REQ-CXP-CF-009 — Jest Emulator Tests

`functions/src/__tests__/add-alias.test.ts` MUST cover all 7 CF scenarios (SCENARIO-735..SCENARIO-743, excluding SCENARIO-735 which is structural). Tests MUST use `firebase-functions-test ^3.1.0` + emulator-backed Admin SDK, following the `review-aggregate.test.ts` shape.

**Related SCENARIOs**: SCENARIO-736..SCENARIO-743

---

### REQ-CXP-WIRE-001 — cloudFunctionsProvider

A Riverpod provider `cloudFunctionsProvider` MUST exist as `final cloudFunctionsProvider = Provider<FirebaseFunctions>((ref) => FirebaseFunctions.instanceFor(region: 'southamerica-east1'))`. Location: `lib/features/coach_hub/application/cf_providers.dart` (create file if absent). This provider MUST be created BEFORE writing the client wire in `coach_hub_plan_preview_screen.dart`.

**Related SCENARIOs**: SCENARIO-744

---

### REQ-CXP-WIRE-002 — Fire-and-Forget addAlias Wire

`coach_hub_plan_preview_screen.dart` `_pickExerciseFor` callback MUST invoke `unawaited(_addAlias(picked.id, rowName))` immediately after the existing local state update and before `setState(() => _error = null)` (or equivalent post-state-update position). The call MUST be fire-and-forget — it MUST NOT block the UI or the save flow.

**Related SCENARIOs**: SCENARIO-745, SCENARIO-746

---

### REQ-CXP-WIRE-003 — _addAlias Exception Swallow

The private `_addAlias(String exerciseId, String rawName)` method MUST catch all exceptions with a bare `catch (_)` block. On any exception it MUST call `debugPrint` with a log message and MUST NOT rethrow, show any UI feedback, or affect `parsedPlanProvider` state. A failure MUST be completely transparent to the PF.

**Related SCENARIOs**: SCENARIO-747

---

### REQ-CXP-WIRE-004 — Widget Test for Client Wire

A widget test for `coach_hub_plan_preview_screen.dart` MUST: (a) override `cloudFunctionsProvider` with a mock `FirebaseFunctions`, (b) simulate a PF completing a manual mapping, (c) verify `httpsCallable('addAlias').call({'exerciseId': picked.id, 'alias': rowName})` is invoked with the correct arguments, (d) simulate the callable throwing an exception, (e) verify the screen shows no error and the local mapping state is preserved. Test names MUST be in English following existing `coach_hub_plan_preview_screen_test.dart` precedent.

**Related SCENARIOs**: SCENARIO-745, SCENARIO-746, SCENARIO-747

---

### REQ-CXP-CX-001 — Strict TDD

Every implementation task pair MUST have a RED commit (failing test) before the GREEN commit (passing implementation), in separate conventional commits.

---

### REQ-CXP-CX-002 — Conventional Commits

All commits MUST use conventional commit format. NO `Co-Authored-By`. NO AI attribution in any commit message.

---

### REQ-CXP-CX-003 — i18n Markers

All es-AR user-facing strings introduced in client Dart code MUST be tagged `// i18n: Fase 6 Etapa 5`. Excel template content (Instrucciones sheet, column headers) is data, not UI — naturally in es-AR but NOT tagged.

---

### REQ-CXP-CX-004 — No Hex Colors, No Direct Icons

All colors in new client Dart code MUST use `AppPalette.of(context)`. No hex literals. All icons MUST use `TreinoIcon.X`. No direct `PhosphorIcons.X` references.

---

### REQ-CXP-CX-005 — pubspec.yaml Frozen

`pubspec.yaml` MUST NOT be modified. `excel: ^4.0.6` and `cloud_functions: ^5.2.0` are already present and sufficient.

---

### REQ-CXP-CX-006 — No Rules or Index Changes

`firestore.rules`, `storage.rules`, and `firestore.indexes.json` MUST NOT be modified. Admin SDK bypasses client-side Firestore rules.

---

### REQ-CXP-CX-007 — No New Collections

No new Firestore collections or sub-collections MUST be created. The CF appends to `exercises/{exerciseId}.aliases` on an existing document.

---

### REQ-CXP-CX-008 — Normalization Parity Enforcement

The TypeScript `normalize()` in `add-alias.ts` and the Dart `normalize()` in `exercise_matcher.dart` MUST produce identical output for the same input string. This parity MUST be verified by SCENARIO-743.

---

## Scenarios

---

### SCENARIO-727: Day sheet — Ejercicio column width
- **Given** `buildTemplate()` is called
- **When** the generated workbook is inspected
- **Then** each Día N sheet has `getColumnWidth(0)` (Ejercicio column) equal to `28`
- **Test target**: `test/features/coach_hub/data/template_builder_test.dart`
- **REQ**: REQ-CXP-TEMPLATE-001

---

### SCENARIO-728: Day sheet — all column widths set correctly
- **Given** `buildTemplate()` is called
- **When** each Día N sheet column widths are read
- **Then** column widths are: Ejercicio(0)=28, Series(1)=10, Reps Min(2)=12, Reps Max(3)=12, Peso Kg(4)=12, Descanso Seg(5)=16, Notas(6)=22
- **Test target**: `test/features/coach_hub/data/template_builder_test.dart`
- **REQ**: REQ-CXP-TEMPLATE-001

---

### SCENARIO-729: Plan sheet column widths set
- **Given** `buildTemplate()` is called
- **When** the `Plan` sheet column widths are read
- **Then** Campo(0)=22 and Valor(1)=20
- **Test target**: `test/features/coach_hub/data/template_builder_test.dart`
- **REQ**: REQ-CXP-TEMPLATE-002

---

### SCENARIO-730: Instrucciones sheet exists in workbook
- **Given** `buildTemplate()` is called
- **When** the generated workbook's sheet names are listed
- **Then** a sheet named `Instrucciones` exists
- **And** it appears after the last Día N sheet
- **Test target**: `test/features/coach_hub/data/template_builder_test.dart`
- **REQ**: REQ-CXP-TEMPLATE-003

---

### SCENARIO-731: Instrucciones sheet heading and column meanings present
- **Given** `buildTemplate()` is called
- **When** the `Instrucciones` sheet cells are read
- **Then** cell A1 contains `Instrucciones de uso`
- **And** cell A3 contains `Columna` and B3 contains `Descripción`
- **And** cells A4..A11 contain the 8 column names in order: Ejercicio, Series, Reps Min, Reps Max, Peso Kg, Descanso Seg, Notas, Nivel
- **Test target**: `test/features/coach_hub/data/template_builder_test.dart`
- **REQ**: REQ-CXP-TEMPLATE-003

---

### SCENARIO-732: Instrucciones sheet valid Nivel values and example row present
- **Given** `buildTemplate()` is called
- **When** the `Instrucciones` sheet cells are read
- **Then** cell A13 contains `Valores válidos para Nivel:`
- **And** cells A14, A15, A16 contain `principiante`, `intermedio`, `avanzado`
- **And** cell A20 contains `Sentadilla con barra` (example row)
- **And** cell H20 contains `intermedio` (example Nivel value)
- **Test target**: `test/features/coach_hub/data/template_builder_test.dart`
- **REQ**: REQ-CXP-TEMPLATE-003

---

### SCENARIO-733: Parser ignores Instrucciones sheet
- **Given** a workbook built by the updated `buildTemplate()` containing an `Instrucciones` sheet
- **When** `parseExcelPlan()` is called on the workbook bytes
- **Then** no error is thrown
- **And** the parsed plan contains exactly 3 days (Día 1, Día 2, Día 3)
- **And** no exercise rows from the `Instrucciones` sheet appear in the parsed output
- **Test target**: `test/features/coach_hub/data/excel_parser_test.dart` (round-trip safety net)
- **REQ**: REQ-CXP-TEMPLATE-004

---

### SCENARIO-734: Round-trip parse of polished template succeeds
- **Given** a workbook built by the updated `buildTemplate()` with column widths and `Instrucciones` sheet
- **When** the workbook bytes are passed to `parseExcelPlan()`
- **Then** all existing `excel_parser_test.dart` round-trip assertions pass with zero failures
- **And** no new assertion failures are introduced
- **Test target**: `test/features/coach_hub/data/excel_parser_test.dart`
- **REQ**: REQ-CXP-TEMPLATE-005

---

### SCENARIO-735: addAlias CF is registered and deployed to southamerica-east1
- **Given** `functions/src/add-alias.ts` exists
- **When** `functions/src/index.ts` is inspected
- **Then** `addAlias` is exported from `'./add-alias'`
- **And** the `onCall` options include `region: 'southamerica-east1'`
- **Test target**: structural / jest import verification
- **REQ**: REQ-CXP-CF-001, REQ-CXP-CF-008

---

### SCENARIO-736: addAlias success — new alias added to existing exercise
- **Given** authenticated user `user_a` with `users/user_a.role == 'trainer'`
- **And** `exercises/exercise_b` exists with `aliases: ['sentadilla', 'squat']`
- **When** `runAddAlias(app, 'user_a', 'exercise_b', 'Sentadilla Búlgara')` is called
- **Then** `exercises/exercise_b.aliases` includes `'sentadilla bulgara'` (normalized)
- **And** the function returns `{ status: 'ok' }`
- **Test target**: `functions/src/__tests__/add-alias.test.ts`
- **REQ**: REQ-CXP-CF-006, REQ-CXP-CF-007

---

### SCENARIO-737: addAlias idempotent — second call with same alias is a no-op
- **Given** `exercises/exercise_b.aliases` already contains `'sentadilla bulgara'`
- **When** `runAddAlias(app, 'user_a', 'exercise_b', 'SENTADILLA BÚLGARA')` is called
- **Then** `exercises/exercise_b.aliases` length is unchanged
- **And** no Firestore write occurs
- **And** the function returns `{ status: 'noop' }`
- **Test target**: `functions/src/__tests__/add-alias.test.ts`
- **REQ**: REQ-CXP-CF-007

---

### SCENARIO-738: addAlias rejects unauthenticated caller
- **Given** a call to `addAlias` with no auth context (`request.auth == null`)
- **When** the callable handler executes
- **Then** `HttpsError('unauthenticated', 'Authentication required.')` is thrown
- **And** `runAddAlias` is never invoked
- **Test target**: `functions/src/__tests__/add-alias.test.ts`
- **REQ**: REQ-CXP-CF-002

---

### SCENARIO-739: addAlias rejects athlete caller
- **Given** authenticated user `user_c` with `users/user_c.role == 'athlete'`
- **When** `runAddAlias(app, 'user_c', 'exercise_b', 'any alias')` is called
- **Then** `HttpsError('permission-denied', 'Caller must be a trainer.')` is thrown
- **And** no Firestore write occurs
- **Test target**: `functions/src/__tests__/add-alias.test.ts`
- **REQ**: REQ-CXP-CF-003

---

### SCENARIO-740: addAlias rejects non-existent exercise
- **Given** authenticated trainer `user_a`
- **And** `exercises/nonexistent_id` does not exist in Firestore
- **When** `runAddAlias(app, 'user_a', 'nonexistent_id', 'some alias')` is called
- **Then** `HttpsError('not-found', 'Exercise not found.')` is thrown
- **And** no Firestore write occurs
- **Test target**: `functions/src/__tests__/add-alias.test.ts`
- **REQ**: REQ-CXP-CF-004

---

### SCENARIO-741: addAlias rejects empty exerciseId or alias
- **Given** authenticated trainer `user_a`
- **When** the `addAlias` callable is invoked with `data = { exerciseId: '', alias: 'sentadilla' }`
- **Then** `HttpsError('invalid-argument', 'exerciseId and alias are required.')` is thrown
- **And** the same error is thrown when `alias` is the empty string
- **Test target**: `functions/src/__tests__/add-alias.test.ts`
- **REQ**: REQ-CXP-CF-005

---

### SCENARIO-742: normalize() — uppercase and whitespace
- **Given** the TypeScript `normalize()` function in `add-alias.ts`
- **When** `normalize('SENTADILLA  CON BARRA')` is evaluated
- **Then** the result is `'sentadilla con barra'`
- **Test target**: `functions/src/__tests__/add-alias.test.ts`
- **REQ**: REQ-CXP-CF-006

---

### SCENARIO-743: normalize() — accent parity with Dart normalize()
- **Given** the TypeScript `normalize()` in `add-alias.ts` and the Dart `normalize()` in `exercise_matcher.dart`
- **When** both functions are called with `'CáMaRa Lenta!!!'`
- **Then** both return `'camara lenta'`
- **And** when called with `'Sentadílla'`, both return `'sentadilla'`
- **And** when called with `'Press de Banca (agarre estrecho)'`, both return `'press de banca agarre estrecho'`
- **Test target**: `functions/src/__tests__/add-alias.test.ts` (TypeScript side); parity enforced by spec assertion
- **REQ**: REQ-CXP-CF-006, REQ-CXP-CX-008

---

### SCENARIO-744: cloudFunctionsProvider is injectable
- **Given** `lib/features/coach_hub/application/cf_providers.dart` exists
- **When** `cloudFunctionsProvider` is read in a `ProviderContainer` with no overrides
- **Then** it returns a `FirebaseFunctions` instance configured for `region: 'southamerica-east1'`
- **And** it can be overridden in widget tests without requiring a real Firebase instance
- **Test target**: `test/features/coach_hub/presentation/coach_hub_plan_preview_screen_test.dart`
- **REQ**: REQ-CXP-WIRE-001

---

### SCENARIO-745: _pickExerciseFor triggers addAlias callable with correct args
- **Given** `cloudFunctionsProvider` is overridden with a mock `FirebaseFunctions`
- **And** the mock callable records invocation arguments
- **When** a PF completes a manual exercise mapping (picks `exercise_b` for row name `'Sentadilla Búlgara'`)
- **Then** the mock callable `httpsCallable('addAlias').call({'exerciseId': 'exercise_b', 'alias': 'Sentadilla Búlgara'})` is invoked exactly once
- **And** the local `parsedPlanProvider` state reflects the mapping (existing save flow unaffected)
- **Test target**: `test/features/coach_hub/presentation/coach_hub_plan_preview_screen_test.dart`
- **REQ**: REQ-CXP-WIRE-001, REQ-CXP-WIRE-002, REQ-CXP-WIRE-004

---

### SCENARIO-746: _pickExerciseFor does not block on CF roundtrip
- **Given** `cloudFunctionsProvider` is overridden with a mock that never completes (hangs indefinitely)
- **When** a PF completes a manual exercise mapping
- **Then** the UI returns to the idle state immediately without waiting for the CF response
- **And** no loading indicator or error is shown to the PF
- **Test target**: `test/features/coach_hub/presentation/coach_hub_plan_preview_screen_test.dart`
- **REQ**: REQ-CXP-WIRE-002

---

### SCENARIO-747: _addAlias swallows CF exceptions silently
- **Given** `cloudFunctionsProvider` is overridden with a mock that throws `FirebaseFunctionsException`
- **When** a PF completes a manual exercise mapping
- **Then** no error message or snackbar is shown to the PF
- **And** the local mapping state in `parsedPlanProvider` is preserved unchanged
- **And** no exception propagates to the widget tree
- **Test target**: `test/features/coach_hub/presentation/coach_hub_plan_preview_screen_test.dart`
- **REQ**: REQ-CXP-WIRE-003

---

## Coverage Matrix

| REQ | Category | SCENARIOs |
|-----|----------|-----------|
| REQ-CXP-TEMPLATE-001 | Day sheet column widths | SCENARIO-727, SCENARIO-728 |
| REQ-CXP-TEMPLATE-002 | Plan sheet column widths | SCENARIO-729 |
| REQ-CXP-TEMPLATE-003 | Instrucciones sheet content | SCENARIO-730, SCENARIO-731, SCENARIO-732 |
| REQ-CXP-TEMPLATE-004 | Parser ignores Instrucciones | SCENARIO-733 |
| REQ-CXP-TEMPLATE-005 | Round-trip parse safety net | SCENARIO-734 |
| REQ-CXP-TEMPLATE-006 | template_builder_test.dart coverage | SCENARIO-727..SCENARIO-734 |
| REQ-CXP-CF-001 | add-alias.ts exports | SCENARIO-735 |
| REQ-CXP-CF-002 | Unauthenticated guard | SCENARIO-738 |
| REQ-CXP-CF-003 | Trainer role guard | SCENARIO-739 |
| REQ-CXP-CF-004 | Exercise existence guard | SCENARIO-740 |
| REQ-CXP-CF-005 | Input validation | SCENARIO-741 |
| REQ-CXP-CF-006 | Normalization parity | SCENARIO-742, SCENARIO-743 |
| REQ-CXP-CF-007 | Dedup and idempotency | SCENARIO-736, SCENARIO-737 |
| REQ-CXP-CF-008 | Region and deployment | SCENARIO-735 |
| REQ-CXP-CF-009 | Jest emulator test coverage | SCENARIO-736..SCENARIO-743 |
| REQ-CXP-WIRE-001 | cloudFunctionsProvider | SCENARIO-744, SCENARIO-745 |
| REQ-CXP-WIRE-002 | Fire-and-forget wire | SCENARIO-745, SCENARIO-746 |
| REQ-CXP-WIRE-003 | Exception swallow | SCENARIO-747 |
| REQ-CXP-WIRE-004 | Widget test | SCENARIO-745, SCENARIO-746, SCENARIO-747 |
| REQ-CXP-CX-001 | Strict TDD | (enforced via commit structure, no SCENARIO) |
| REQ-CXP-CX-002 | Conventional commits | (enforced via commit structure, no SCENARIO) |
| REQ-CXP-CX-003 | i18n markers | (enforced via code review, no SCENARIO) |
| REQ-CXP-CX-004 | AppPalette / TreinoIcon | (enforced via code review + `flutter analyze`) |
| REQ-CXP-CX-005 | pubspec.yaml frozen | (hard constraint, no SCENARIO) |
| REQ-CXP-CX-006 | Rules/indexes frozen | (hard constraint, no SCENARIO) |
| REQ-CXP-CX-007 | No new collections | (hard constraint, no SCENARIO) |
| REQ-CXP-CX-008 | Normalization parity enforcement | SCENARIO-743 |

---

## Open Questions for Design

None material. All 10 exploration questions are locked in the proposal. The following micro-decisions are resolved here:

1. **Widget test names**: English strings per existing `coach_hub_plan_preview_screen_test.dart` precedent.
2. **cloudFunctionsProvider location**: `lib/features/coach_hub/application/cf_providers.dart` (co-located in Coach Hub feature; promote later if other features need it).
3. **HttpsError messages**: Locked in REQ-CXP-CF-002..005 literal strings above.
4. **docs/roadmap.md**: Nivel dropdown reference SHOULD be noted as superseded by Decision #8 in a follow-up docs commit; out of scope for this change's PRs.

---

## Hard Constraints

1. `pubspec.yaml` MUST NOT be modified. No new Flutter or CF dependencies.
2. `firestore.rules`, `storage.rules`, `firestore.indexes.json` MUST NOT be modified.
3. `excel: ^4.0.6` has no `DataValidation` API. No Nivel dropdown via Excel data validation. Instrucciones static text is the sole substitute (Decision #8).
4. `excel_parser.dart` MUST NOT be modified. The `_daySheetRegex` must continue to work as-is.
5. No new Firestore collections. No migration of existing seeded aliases.
6. All client UI strings in es-AR with `// i18n: Fase 6 Etapa 5` markers.
7. `AppPalette.of(context)` for all colors. `TreinoIcon.X` for all icons.
8. Strict TDD: RED commit before GREEN commit per task pair. Conventional commits, no Co-Authored-By.
9. PR diffs MUST be ≤ 400 LOC each (PR#1 ~100, PR#2 ~250 — both under budget).
10. CF normalization (`add-alias.ts`) MUST mirror Dart `normalize()` char-by-char. Any deviation silently breaks the alias matching pipeline.

---

## Artifact References

- File: `openspec/changes/coach-excel-polish/spec.md`
- Engram: `sdd/coach-excel-polish/spec`
- Proposal: `openspec/changes/coach-excel-polish/proposal.md` + Engram `sdd/coach-excel-polish/proposal` (#160)
- Exploration: `openspec/changes/coach-excel-polish/explore.md` + Engram `sdd/coach-excel-polish/explore` (#159)

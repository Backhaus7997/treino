# Spec — exercise-notes

**Change**: `exercise-notes`
**Artifact store**: `hybrid` (engram topic `sdd/exercise-notes/spec` + this file)
**TDD**: Strict — each failing test MUST be written before the corresponding widget/function in the apply phase.
**Scenario numbering**: continues from SCENARIO-788 (last used in `i18n-localization` spec). Starts at SCENARIO-800 (safe gap).
**REQ namespace**: `REQ-EN-*`
**Last updated**: 2026-06-29

---

## Overview

This spec defines verifiable requirements for wiring `RoutineSlot.notes` end-to-end. The field already exists in the freezed model (`routine_slot.dart:46`, `String? notes`) but is a silent stub — never written, never hydrated, never displayed. This change wires it without touching the model, Firestore rules, or any repository.

**Delta only**: this spec does NOT re-describe existing `RoutineSlot`, `RoutineEditorMode`, `_isTrainerMode`, `ExerciseSlotRow`, or `session_player_screen.dart` behavior. It specifies only what MUST be true AFTER this change is applied.

**No model change**: `routine_slot.dart`, `firestore.rules`, and all repositories are unchanged. `notes` lives inside `days[].slots[].notes`; the `days` key is already an allowed update path.

**Affected files (production)**:
- `lib/features/workout/presentation/routine_editor_screen.dart` (editor input, build, hydration, bridge)
- `lib/features/workout/presentation/session_player_screen.dart` (player display)
- `lib/features/workout/presentation/widgets/exercise_slot_row.dart` (detail display)
- `lib/l10n/intl_es_AR.arb` + `lib/l10n/intl_en.arb` + generated `app_l10n_*.dart` (l10n keys)

**Affected files (test)**:
- `test/features/workout/presentation/routine_editor_screen_test.dart`
- `test/features/workout/presentation/session_player_screen_test.dart`
- `test/features/workout/presentation/widgets/exercise_slot_row_test.dart`

---

## Requirements

---

### REQ-EN-001 — `_EditableSlot` carries a nullable `notes` field

`_EditableSlot` (in `routine_editor_screen.dart`) MUST declare a `String? notes` field (or `String notes = ''` — implementation decides representation; the round-trip normalization in REQ-EN-003 is the contract regardless).

This field is the in-editor state holder for the PF coaching cue. Its value is sourced from the persisted `RoutineSlot.notes` on hydration (REQ-EN-005) and emitted to `RoutineSlot.notes` on build (REQ-EN-003).

No `RoutineSlot` model change is required. No freezed regen. No migration.

#### Scenarios

**SCENARIO-800** — `_EditableSlot` round-trip: note set on the editable slot survives `buildRoutineSlot`
- GIVEN `RoutineEditorTestBridge.buildSlotBridge` called with `notes: 'Bajá 3 seg excéntrica'`
- WHEN `buildRoutineSlot` is called on the resulting `_EditableSlot`
- THEN the returned `RoutineSlot.notes == 'Bajá 3 seg excéntrica'`

**SCENARIO-801** — Empty-string note normalizes to `null` in `buildRoutineSlot`
- GIVEN `RoutineEditorTestBridge.buildSlotBridge` called with `notes: ''`
- WHEN `buildRoutineSlot` is called
- THEN the returned `RoutineSlot.notes` is `null`

**SCENARIO-802** — Null note remains `null` in `buildRoutineSlot`
- GIVEN `RoutineEditorTestBridge.buildSlotBridge` called with `notes: null`
- WHEN `buildRoutineSlot` is called
- THEN the returned `RoutineSlot.notes` is `null`

---

### REQ-EN-002 — Note `TextField` is visible in trainer modes and absent in athlete mode

The note input widget (`TextField` or equivalent) MUST be rendered inside `_SlotEditor` / `_SlotEditorState` **only** when `_isTrainerMode` evaluates to `true`. `_isTrainerMode` is defined as `mode is TrainerAssigning || mode is TrainerTemplating` (existing getter, line ~662 — not redefined by this change).

In `SelfCreating` mode the note field MUST NOT appear anywhere in the slot card widget tree. No gating via opacity or disabled state is acceptable — the widget must be absent.

#### Scenarios

**SCENARIO-803** — Note `TextField` is present in `TrainerAssigning` mode
- GIVEN the routine editor pumped in `TrainerAssigning` mode with a `ProviderScope` override for the routine repository
- WHEN the slot card for any slot is inspected
- THEN a `TextField` (or `TextFormField`) associated with the note input is found in the widget tree

**SCENARIO-804** — Note `TextField` is present in `TrainerTemplating` mode
- GIVEN the routine editor pumped in `TrainerTemplating` mode
- WHEN the slot card for any slot is inspected
- THEN the note `TextField` is found in the widget tree

**SCENARIO-805** — Note `TextField` is absent in `SelfCreating` mode
- GIVEN the routine editor pumped in `SelfCreating` mode
- WHEN the slot card for any slot is inspected
- THEN no note `TextField` is found in the widget tree (widget must be absent, not hidden)

---

### REQ-EN-003 — `buildRoutineSlot` emits `notes`, normalizing `''` → `null`

`buildRoutineSlot` (in `routine_editor_screen.dart`) MUST include `notes: s.notes?.isEmpty == true ? null : s.notes` (or equivalent normalization) when constructing the `RoutineSlot` to persist.

Empty string MUST be stored as `null` so the display guard (`notes?.isNotEmpty == true`) is the single canonical check across all surfaces.

This requirement is verified by REQ-EN-001 scenarios (SCENARIO-800 through SCENARIO-802). No additional scenarios are added here.

---

### REQ-EN-004 — Note input enforces a 200-character hard cap

The note `TextField` MUST set `maxLength: 200` with `maxLengthEnforcement: MaxLengthEnforcement.enforced`. Characters beyond 200 MUST be rejected at input time — the user MUST NOT be able to type, paste, or programmatically set a note longer than 200 characters through the editor UI.

The character counter SHOULD be visible only when the field is focused or non-empty, to avoid visual noise on every slot card.

#### Scenarios

**SCENARIO-806** — Note `TextField` rejects input beyond 200 characters
- GIVEN the note `TextField` pumped in `TrainerAssigning` mode
- AND the field currently contains 200 characters
- WHEN `tester.enterText` attempts to add one more character (total 201)
- THEN the field value length remains `<= 200` (enforced, not truncated after the fact)

**SCENARIO-807** — Note `TextField` accepts exactly 200 characters
- GIVEN the note `TextField` pumped in `TrainerAssigning` mode
- WHEN `tester.enterText` sets a 200-character string
- THEN the field value has length `200` and no error is thrown

---

### REQ-EN-005 — `_loadExistingRoutine` restores `notes` from persisted `RoutineSlot` (bug fix)

`_loadExistingRoutine` (in `routine_editor_screen.dart`, line ~528) MUST restore `editableSlot.notes = slot.notes` for every `RoutineSlot` it hydrates into `_EditableSlot`. This closes the latent data-loss bug where a PF who opened and re-saved a plan would silently strip any notes already stored in Firestore.

This fix MUST land in the same commit as REQ-EN-003. Shipping the input without the hydration fix would introduce a known data-loss path.

#### Scenarios

**SCENARIO-808** — Notes survive a full build → save → hydrate → save round-trip
- GIVEN a `RoutineSlot` with `notes: 'RIR 2 · pausa abajo'` returned by the fake routine repository
- WHEN the editor is pumped in `TrainerAssigning` mode with that existing plan
- AND `_loadExistingRoutine` runs on pump
- THEN the editable slot's note field displays `'RIR 2 · pausa abajo'`

**SCENARIO-809** — Hydrating a slot with `notes: null` does not crash and leaves the note field empty
- GIVEN a `RoutineSlot` with `notes: null`
- WHEN the editor hydrates that slot via `_loadExistingRoutine`
- THEN the note field is empty and no exception is thrown

**SCENARIO-810** — Note written, plan saved, plan reopened, plan re-saved: note is preserved across both saves
- GIVEN the editor in `TrainerAssigning` mode
- AND the PF enters note `'Tempo 3-1-2'` and saves (first save)
- WHEN the editor is reopened for that same plan (second open)
- AND saved again without editing the note (second save)
- THEN the persisted `RoutineSlot.notes` after the second save is `'Tempo 3-1-2'` (not `null`)

---

### REQ-EN-006 — `RoutineEditorTestBridge.buildSlotBridge` accepts an optional `notes` parameter

`RoutineEditorTestBridge.buildSlotBridge` (in `routine_editor_screen.dart`, line ~3507) MUST accept an optional `String? notes` parameter. This parameter MUST be forwarded to the `_EditableSlot.notes` field.

Without this bridge extension, the round-trip in REQ-EN-001 and the hydration in REQ-EN-005 cannot be exercised at the unit level.

This requirement has no additional scenarios beyond those in REQ-EN-001 — the bridge extension is the mechanism, and SCENARIO-800 through SCENARIO-802 verify the outcome.

---

### REQ-EN-007 — Session player renders the PF note on the current exercise block only, read-only

`_ExerciseSection` (in `session_player_screen.dart`, line ~1152) MUST render `widget.slot.notes` as a muted inline text line in the exercise header region **only** when:
1. `slot.notes?.isNotEmpty == true`, AND
2. the section is the currently-active exercise block.

The note MUST be visually distinct from the catalog `techniqueInstructions` ⓘ bottom-sheet — the PF note is inline/muted in the header; the technique ⓘ affordance remains behind a tap-to-open sheet. No design change to the ⓘ affordance is required by this spec.

The note widget MUST be read-only. No edit control, no tap target, no gesture detector is introduced on the note text.

Zero new constructor parameters or provider reads are required — `widget.slot` is already passed.

#### Scenarios

**SCENARIO-811** — Player renders note for the current block when `slot.notes` is non-empty
- GIVEN `_ExerciseSection` pumped as the current block with `slot.notes: 'Bajá 3 seg excéntrica'`
- WHEN the widget tree is inspected
- THEN a `Text` widget containing `'Bajá 3 seg excéntrica'` is found in the section

**SCENARIO-812** — Player renders nothing for the note when `slot.notes` is null
- GIVEN `_ExerciseSection` pumped as the current block with `slot.notes: null`
- WHEN the widget tree is inspected
- THEN no widget displaying a PF note text is found (zero visual footprint)

**SCENARIO-813** — Player renders nothing for the note when `slot.notes` is empty string
- GIVEN `_ExerciseSection` pumped with `slot.notes: ''`
- WHEN the widget tree is inspected
- THEN no widget displaying a PF note text is found

**SCENARIO-814** — Player does NOT render the note on a non-current (done or pending) block
- GIVEN `_ExerciseSection` pumped as a non-current block with `slot.notes: 'Should not appear'`
- WHEN the widget tree is inspected
- THEN no widget displaying `'Should not appear'` is found

---

### REQ-EN-008 — Routine detail renders the PF note under each exercise that has one, read-only

`ExerciseSlotRow` (in `widgets/exercise_slot_row.dart`) MUST render `slot.notes` as a small muted/italic line below the exercise name when `slot.notes?.isNotEmpty == true`. When `slot.notes` is null or empty, the note line MUST NOT appear (no empty label, no spacer).

The note widget MUST be read-only. No edit control is introduced.

Zero signature changes to `ExerciseSlotRow` are required — `slot` is already passed as the full `RoutineSlot`.

#### Scenarios

**SCENARIO-815** — `ExerciseSlotRow` renders note line when `slot.notes` is non-empty
- GIVEN `ExerciseSlotRow` pumped with a `RoutineSlot` where `notes: 'RIR 2 · pausa abajo'`
- WHEN the widget tree is inspected
- THEN a `Text` widget containing `'RIR 2 · pausa abajo'` is found

**SCENARIO-816** — `ExerciseSlotRow` renders no note line when `slot.notes` is null
- GIVEN `ExerciseSlotRow` pumped with `slot.notes: null`
- WHEN the widget tree is inspected
- THEN no note text widget is found in the row

**SCENARIO-817** — `ExerciseSlotRow` renders no note line when `slot.notes` is empty string
- GIVEN `ExerciseSlotRow` pumped with `slot.notes: ''`
- WHEN the widget tree is inspected
- THEN no note text widget is found in the row

---

### REQ-EN-009 — Legacy plans without a `notes` key deserialize to `null` without crashing

A `RoutineSlot` deserialized from Firestore data that has no `notes` key MUST produce `notes: null`. No crash, no exception, no fallback sentinel value other than `null`.

This requirement validates the existing `fromJson` behavior of `RoutineSlot` (no code change needed — the freezed-generated `fromJson` already handles missing optional fields as null). The scenario is a regression guard.

#### Scenarios

**SCENARIO-818** — Missing `notes` key in Firestore document deserializes to `null`
- GIVEN a JSON map representing a `RoutineSlot` document that has no `'notes'` key
- WHEN `RoutineSlot.fromJson(map)` is called
- THEN `routineSlot.notes` is `null` AND no exception is thrown

**SCENARIO-819** — `ExerciseSlotRow` pumped with a legacy slot (notes null) renders without error
- GIVEN `ExerciseSlotRow` pumped with a `RoutineSlot` constructed from a legacy JSON map (no `notes` key)
- WHEN the widget tree is inspected
- THEN no exception is thrown AND no note line is rendered

---

### REQ-EN-010 — New l10n keys follow the `routineEditor*` namespace and are present in both ARB files

New user-facing strings for the note input (hint text, optional label) MUST be added to `lib/l10n/intl_es_AR.arb` and `lib/l10n/intl_en.arb`. Generated `app_l10n_*.dart` files MUST be regenerated.

Keys MUST follow the existing `routineEditor*` namespace (e.g., `routineEditorNoteHint`, `routineEditorNoteLabel`). No hardcoded Spanish strings are permitted in `routine_editor_screen.dart` — all copy goes through `AppL10n`.

The read-only display surfaces (player and detail) MAY use short text directly if the note is rendered as a raw `slot.notes` value (no label), but any label or accessibility text added to those surfaces MUST also be l10n-keyed.

#### Scenarios

**SCENARIO-820** — `intl_es_AR.arb` contains at least one new `routineEditorNote*` key
- GIVEN the file `lib/l10n/intl_es_AR.arb` after the change is applied
- WHEN its contents are inspected
- THEN at least one key matching `routineEditorNote*` exists with a non-empty Spanish value

**SCENARIO-821** — `intl_en.arb` contains the same `routineEditorNote*` key(s) as `intl_es_AR.arb`
- GIVEN both ARB files after the change
- WHEN their keys are compared
- THEN every `routineEditorNote*` key present in `intl_es_AR.arb` also exists in `intl_en.arb`

---

### REQ-EN-011 — No HEX literals, no direct `PhosphorIcons.*` usage in any modified file

All code added or modified in this change MUST:
- Use `AppPalette.of(context)` for ALL color values — no `Color(0xFFxxx)` or named color literals.
- Use `TreinoIcon.X` constants — no `PhosphorIconsRegular.X`, `PhosphorIconsFill.X`, or `PhosphorIconsBold.X` direct usage.

If any new `TreinoIcon` constant is required for the note display, it MUST be added to `lib/core/widgets/treino_icon.dart` before use.

#### Scenarios

**SCENARIO-822** — No `Color(0x...` or hex color literal appears in any file modified by this change
- GIVEN the diff of this change
- WHEN files are grepped for `Color(0x` or hex patterns in production code
- THEN zero matches are found in files added or modified by this PR

---

## Constraint summary

| Constraint | Enforced by |
|---|---|
| No change to `routine_slot.dart`, `firestore.rules`, repositories | Overview |
| Notes gated to `_isTrainerMode` only | REQ-EN-002 |
| Empty note normalizes to `null` | REQ-EN-001, REQ-EN-003 |
| Hard 200-char cap, enforced mode | REQ-EN-004 |
| Hydration fix MUST land with emit fix | REQ-EN-005 |
| Bridge extended with `notes` param | REQ-EN-006 |
| Player note: current block only | REQ-EN-007 |
| Both read surfaces: read-only, conditional | REQ-EN-007, REQ-EN-008 |
| PF note visually distinct from ⓘ technique | REQ-EN-007 |
| Legacy JSON: null, no crash | REQ-EN-009 |
| All copy via `AppL10n`, `routineEditor*` namespace | REQ-EN-010 |
| No HEX literals, no `PhosphorIcons.*` direct use | REQ-EN-011 |
| Tests written BEFORE each widget (Strict TDD) | Enforced by tasks phase |

---

## Out of scope (explicit)

The following MUST NOT appear in this PR. If found in a diff, the reviewer MUST reject it.

- Athlete-authored notes (input in `SelfCreating` mode)
- Per-set notes (note is per-slot, not per-set-row)
- Structured fields: tempo, RIR, pause as typed pickers
- Note surfacing in `ExerciseDetailScreen` (catalog screen — orthogonal)
- Any change to `treino-coach-hub/` or `treino-ajustes/` directories (stale clones)
- Any change to `routine_slot.dart` (field already exists)
- Any change to `firestore.rules` (covered by `days`)
- Any change to repository files (`createAssigned`, `updateAssigned`, `createTemplate`, `updateTemplate`, `assignTemplateToAthlete`)
- Dual-editor work (there is one editor: `routine_editor_screen.dart`)

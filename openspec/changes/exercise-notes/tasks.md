# Tasks — exercise-notes

**Change**: `exercise-notes`
**Artifact store**: hybrid (engram topic `sdd/exercise-notes/tasks` + this file)
**TDD mode**: Strict — RED (failing test) MUST be committed before the GREEN fix in every task.
**Scenario namespace**: SCENARIO-800 … SCENARIO-822
**Last updated**: 2026-06-29

---

## Review Workload Forecast

| Metric | Value |
|---|---|
| Production files changed | 4 (`routine_editor_screen.dart`, `session_player_screen.dart`, `exercise_slot_row.dart`, ARB x2) |
| Test files created/changed | 3 new files (`routine_editor_notes_test.dart`, `session_player_notes_test.dart`, `exercise_slot_row_test.dart` extended) |
| Estimated changed lines — production | ~95 |
| Estimated changed lines — tests | ~220 |
| Estimated total | ~315 lines |
| 400-line budget risk | **Low** |
| Chained PRs recommended | **No** |
| Decision needed before apply | **No** |

Single PR confirmed. All changes are in one feature slice, touch only the presentation layer, and carry no migration risk.

---

## Dependency order

```
TASK-1 (bridge + emit + hydrate invariant)
  └─> TASK-2 (SlotEditor input widget — needs _EditableSlot.notes in state)
        └─> TASK-3 (plumbing: _SlotEditor & _DayExpansionTile — needs isTrainerMode param)
TASK-4 (l10n keys — needed by TASK-2 & TASK-3 for label/hint)
TASK-5 (player display — reads slot.notes, no editor dependency)
TASK-6 (routine detail display — reads slot.notes, no editor dependency)
TASK-7 (quality gate — depends on all)
```

TASK-4 MUST land before TASK-2 (strings referenced in TextFormField). TASK-5 and TASK-6 can run in parallel with TASK-2/3 after TASK-4. TASK-1 unlocks everything.

---

## Group 1 — Emit + hydrate invariant + bridge (atomic, RED-locked)

### TASK-1 — `_EditableSlot.notes`, `buildRoutineSlot` emit, `_loadExistingRoutine` hydrate, `buildSlotBridge` param

**File**: `lib/features/workout/presentation/routine_editor_screen.dart`
**Test file (new)**: `test/features/workout/presentation/routine_editor_notes_test.dart`
**REQs**: REQ-EN-001, REQ-EN-003, REQ-EN-005, REQ-EN-006

**Strict TDD sequence**:

- [ ] **RED** — Write the failing test file with scenarios below. All four MUST fail (field does not exist yet).
  - SCENARIO-800: `buildSlotBridge(notes: 'Bajá 3 seg excéntrica')` → `slot.notes == 'Bajá 3 seg excéntrica'`
  - SCENARIO-801: `buildSlotBridge(notes: '')` → `slot.notes == null`
  - SCENARIO-802: `buildSlotBridge(notes: null)` → `slot.notes == null`
  - SCENARIO-808: editor pumped in `TrainerAssigning` with existing plan having `notes: 'RIR 2 · pausa abajo'` → note field displays that string
  - SCENARIO-809: hydrating `notes: null` slot → no crash, field empty
  - SCENARIO-810: note entered, save, reopen, save again → persisted note unchanged

- [ ] **GREEN** — Apply all four edits in one commit:
  1. `_EditableSlot` (~line 115): add `String? notes;`
  2. `buildRoutineSlot` (~line 293): add `notes: (s.notes?.trim().isNotEmpty ?? false) ? s.notes!.trim() : null` to the `RoutineSlot(...)` constructor call
  3. `_loadExistingRoutine` cascade (~line 542): append `..notes = slot.notes` after `..activeWeeks = slot.activeWeeks.toSet()`
  4. `buildSlotBridge` (~line 3507): add optional param `String? notes` + `..notes = notes` in the slot cascade

- [ ] **REFACTOR** — Verify no extraneous whitespace; confirm `buildSlotBridgeWeekly` does NOT need `notes` (it does not).

**Parallel eligibility**: TASK-1 is the root — must complete first.

---

## Group 2 — Trainer-gated input widget + plumbing

### TASK-2 — `TextFormField` notes input in `_SlotEditorState.build`

**File**: `lib/features/workout/presentation/routine_editor_screen.dart`
**Test file**: `test/features/workout/presentation/routine_editor_notes_test.dart`
**REQs**: REQ-EN-002, REQ-EN-004
**Depends on**: TASK-1 (needs `_EditableSlot.notes`), TASK-3 (needs `isTrainerMode` param on `_SlotEditor`), TASK-4 (needs l10n keys)

**Strict TDD sequence**:

- [ ] **RED** — Add to the test file:
  - SCENARIO-803: editor pumped in `TrainerAssigning` → `find.byKey(Key('slot_notes_field'))` finds one widget
  - SCENARIO-804: editor pumped in `TrainerTemplating` → same finder finds one widget
  - SCENARIO-805: editor pumped in `SelfCreating` → finder finds nothing
  - SCENARIO-806: 200-char cap enforced — attempt 201 chars → field value length `<= 200`
  - SCENARIO-807: exactly 200 chars accepted → length `== 200`

- [ ] **GREEN** — In `_SlotEditorState.build` (~line 2629), after the rest-duration Row (closes ~line 2764) and before `_SetTable` (~line 2768), insert:
  ```dart
  if (widget.isTrainerMode) ...[
    const SizedBox(height: 12),
    TextFormField(
      key: const Key('slot_notes_field'),
      initialValue: slot.notes,
      maxLength: 200,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      minLines: 1,
      maxLines: 3,
      counterText: '',
      decoration: InputDecoration(
        labelText: l10n.routineEditorNotesLabel,
        hintText: l10n.routineEditorNotesHint,
      ),
      onChanged: (v) {
        slot.notes = v.isEmpty ? null : v;
        widget.onChanged();
      },
    ),
  ],
  ```

- [ ] **REFACTOR** — Confirm `counterText: ''` hides the counter; confirm `initialValue` rebinds correctly with `ObjectKey(slot)` already applied at the call sites.

**Parallel eligibility**: Can run after TASK-1 + TASK-3 + TASK-4.

### TASK-3 — Thread `isTrainerMode` through `_DayExpansionTile` and both `_SlotEditor` call sites

**File**: `lib/features/workout/presentation/routine_editor_screen.dart`
**Test file**: `test/features/workout/presentation/routine_editor_notes_test.dart` (SCENARIO-803–805 gate this)
**REQs**: REQ-EN-002
**Depends on**: TASK-1

**Strict TDD sequence**:

- [ ] **RED** — SCENARIO-803/804/805 are already written in TASK-2 RED. They fail here because `_SlotEditor` has no `isTrainerMode` parameter yet.

- [ ] **GREEN** — Three edit points, one commit:
  1. `_SlotEditor` widget declaration (~line 2573): add `this.isTrainerMode = false` to the constructor with `final bool isTrainerMode;` field. Default `false` = fail-closed (REQ-EN-002).
  2. `_DayExpansionTile` widget declaration (~line 2096): add `this.isTrainerMode = false` with `final bool isTrainerMode;` field. Forward to both `_SlotEditor` call sites:
     - Standalone site (~line 2170): add `isTrainerMode: widget.isTrainerMode`
     - Superset site (~line 2473): add `isTrainerMode: isTrainerMode` (the tile receives it as a parameter via closure)
  3. Screen's `_DayExpansionTile` call site (~line 1767): add `isTrainerMode: _isTrainerMode`

- [ ] **REFACTOR** — Verify that omitting `isTrainerMode` from the two `_SlotEditor` sites (before the fix) would have defaulted to `false`, not to a compile error. Confirm the default is backward-compatible with all existing tests.

**Parallel eligibility**: TASK-3 can start immediately after TASK-1.

---

## Group 3 — L10n keys

### TASK-4 — Add `routineEditorNotesLabel` and `routineEditorNotesHint` to both ARB files + regen

**Files**: `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`
**Generated (do not hand-edit)**: `lib/l10n/app_l10n_*.dart`
**REQs**: REQ-EN-010
**Depends on**: nothing (can run in parallel with TASK-1 through TASK-3, but TASK-2 references the keys so must complete before TASK-2 GREEN)

**Strict TDD sequence**:

- [ ] **RED** — Add to `test/features/workout/presentation/routine_editor_notes_test.dart`:
  - SCENARIO-820: ARB file `intl_es_AR.arb` contains at least one key matching `routineEditorNote*` with non-empty Spanish value
  - SCENARIO-821: every `routineEditorNote*` key in `intl_es_AR.arb` also exists in `intl_en.arb`
  *(These are static file-content assertions, not widget tests — read the file content and `expect` via `String.contains`.)*

- [ ] **GREEN** — Insert after the last `routineEditor*` entry in each ARB (after `"routineEditorSetTypeFailure"` block, ~line 669 in `intl_es_AR.arb`):

  `intl_es_AR.arb`:
  ```json
  "routineEditorNotesLabel": "Nota para el alumno",
  "@routineEditorNotesLabel": {},
  "routineEditorNotesHint": "Técnica, tempo, RIR…",
  "@routineEditorNotesHint": {},
  "exerciseNoteFromCoachTag": "DEL COACH",
  "@exerciseNoteFromCoachTag": {}
  ```

  `intl_en.arb`:
  ```json
  "routineEditorNotesLabel": "Note for athlete",
  "routineEditorNotesHint": "Technique, tempo, RIR…",
  "exerciseNoteFromCoachTag": "FROM COACH"
  ```

  Then run `flutter gen-l10n`. Do NOT hand-edit `app_l10n.dart`.

- [ ] **REFACTOR** — Confirm the `exerciseNoteFromCoachTag` key is also present (used by TASK-5 and TASK-6).

**Parallel eligibility**: Can start in parallel with TASK-1; must complete before TASK-2 GREEN.

---

## Group 4 — Player read surface + "Del Coach" tag

### TASK-5 — Render PF note + "DEL COACH" tag in `_ExerciseSection` (current block only)

**File**: `lib/features/workout/presentation/session_player_screen.dart`
**Test file (new)**: `test/features/workout/presentation/session_player_notes_test.dart`
**REQs**: REQ-EN-007
**Depends on**: TASK-4 (needs `exerciseNoteFromCoachTag` l10n key)

**Strict TDD sequence**:

- [ ] **RED** — Create `test/features/workout/presentation/session_player_notes_test.dart`:
  - SCENARIO-811: `_ExerciseSection` as current block (`currentSetNumber: 1`) with `slot.notes: 'Bajá 3 seg excéntrica'` → `find.textContaining('Bajá 3 seg excéntrica')` finds one widget
  - SCENARIO-812: current block with `slot.notes: null` → no PF note text found
  - SCENARIO-813: current block with `slot.notes: ''` → no PF note text found
  - SCENARIO-814: non-current block (`currentSetNumber: null`) with `slot.notes: 'Should not appear'` → no such text found (widget renders `_CompletedBlockSummary` or `_FutureBlockPreview`, not `_ExerciseSection`)

  Note: SCENARIO-814 is validated by testing that the dispatch in `_SingleExerciseBlock.build` routes non-current blocks away from `_ExerciseSection` entirely — no note widget can be present.

- [ ] **GREEN** — In `_ExerciseSectionState.build`, after the header Row closes (~line 1365) and before `const SizedBox(height: 12)` (~line 1366):
  ```dart
  if (widget.slot.notes?.isNotEmpty == true) ...[
    const SizedBox(height: 8),
    Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            l10n.exerciseNoteFromCoachTag,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.8,
              color: palette.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.slot.notes!,
            style: GoogleFonts.barlow(
              fontStyle: FontStyle.italic,
              fontSize: 13,
              height: 1.3,
              color: palette.textMuted,
            ),
          ),
        ),
      ],
    ),
  ],
  ```

- [ ] **REFACTOR** — Confirm no hex literals; confirm the note renders only inside `_ExerciseSection`, not in `_CompletedBlockSummary` or `_FutureBlockPreview`.

**Parallel eligibility**: Can run in parallel with TASK-2/3 after TASK-4.

---

## Group 5 — Routine detail read surface + "Del Coach" tag

### TASK-6 — Render PF note + "DEL COACH" tag in `ExerciseSlotRow`

**File**: `lib/features/workout/presentation/widgets/exercise_slot_row.dart`
**Test file**: `test/features/workout/presentation/widgets/exercise_slot_row_test.dart` (extend existing)
**REQs**: REQ-EN-008, REQ-EN-009
**Depends on**: TASK-4

**Strict TDD sequence**:

- [ ] **RED** — Extend `exercise_slot_row_test.dart` with:
  - SCENARIO-815: `ExerciseSlotRow` with `slot.notes: 'RIR 2 · pausa abajo'` → `find.textContaining('RIR 2 · pausa abajo')` finds a widget
  - SCENARIO-816: `slot.notes: null` → no note text widget found
  - SCENARIO-817: `slot.notes: ''` → no note text widget found
  - SCENARIO-818: `RoutineSlot.fromJson` with no `'notes'` key → `slot.notes == null`, no exception (static/unit test, not widget test)
  - SCENARIO-819: `ExerciseSlotRow` with legacy-JSON slot (no `notes`) → no exception, no note line

  Update `_makeSlot` helper to accept optional `String? notes` and pass it through.

- [ ] **GREEN** — In `ExerciseSlotRow.build` (~line 148), inside the `Column` that ends ~line 256, append before the closing bracket:
  ```dart
  if (slot.notes?.isNotEmpty == true) ...[
    const SizedBox(height: 8),
    Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            AppL10n.of(context).exerciseNoteFromCoachTag,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 0.8,
              color: palette.accent,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            slot.notes!,
            style: GoogleFonts.barlow(
              fontStyle: FontStyle.italic,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: palette.textMuted,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  ],
  ```

- [ ] **REFACTOR** — Confirm SCENARIO-818 passes without code change (the existing `fromJson` generated code already handles missing key as `null`). If it fails, investigate — do NOT modify `routine_slot.dart`.

**Parallel eligibility**: Can run in parallel with TASK-5 after TASK-4.

---

## Group 6 — Quality gate

### TASK-7 — Quality gate: analyze, format, full test suite

**Files**: none (gate task)
**REQs**: REQ-EN-011 (no HEX, no `PhosphorIcons.*`)
**Depends on**: TASK-1 through TASK-6

**Strict TDD sequence**:

- [ ] **RED** — N/A (no new tests; this task validates the integration)

- [ ] **GREEN** — Run in order, all MUST pass with zero issues:
  1. `dart format . --set-exit-if-changed`
  2. `flutter analyze` (0 issues)
  3. `flutter test test/features/workout/presentation/routine_editor_notes_test.dart`
  4. `flutter test test/features/workout/presentation/session_player_notes_test.dart`
  5. `flutter test test/features/workout/presentation/widgets/exercise_slot_row_test.dart`
  6. `flutter test` (full suite — no regressions)

- [ ] **SCENARIO-822** — Grep production files touched by this change for `Color(0x`:
  ```
  rg "Color\(0x" lib/features/workout/presentation/routine_editor_screen.dart \
    lib/features/workout/presentation/session_player_screen.dart \
    lib/features/workout/presentation/widgets/exercise_slot_row.dart
  ```
  MUST return zero matches.

- [ ] **SCENARIO-822 (icon)** — Grep same files for `PhosphorIcons.`:
  ```
  rg "PhosphorIcons\." lib/features/workout/presentation/
  ```
  MUST return zero matches.

---

## Summary table

| Task | Group | Scenarios | REQs | Parallel? | Approx lines |
|---|---|---|---|---|---|
| TASK-1 | Emit+hydrate invariant+bridge | 800–802, 808–810 | EN-001, EN-003, EN-005, EN-006 | Root | ~25 prod / ~80 test |
| TASK-2 | Slot editor input widget | 803–807 | EN-002, EN-004 | After T1+T3+T4 | ~25 prod / ~60 test |
| TASK-3 | Plumbing isTrainerMode | 803–805 (same) | EN-002 | After T1, parallel T2 | ~20 prod |
| TASK-4 | L10n keys | 820–821 | EN-010 | Parallel with T1-T3 | ~12 arb / ~15 test |
| TASK-5 | Player note+tag | 811–814 | EN-007 | After T4 | ~25 prod / ~40 test |
| TASK-6 | Detail note+tag | 815–819 | EN-008, EN-009 | After T4, parallel T5 | ~25 prod / ~25 test |
| TASK-7 | Quality gate | 822 | EN-011 | After all | 0 prod |
| **Total** | | **23 scenarios** | **11 REQs** | | **~315 lines** |

---

## Files touched

### Production (4 files)
- `lib/features/workout/presentation/routine_editor_screen.dart`
- `lib/features/workout/presentation/session_player_screen.dart`
- `lib/features/workout/presentation/widgets/exercise_slot_row.dart`
- `lib/l10n/intl_es_AR.arb`
- `lib/l10n/intl_en.arb`

### Test (3 files — 2 new, 1 extended)
- `test/features/workout/presentation/routine_editor_notes_test.dart` — NEW
- `test/features/workout/presentation/session_player_notes_test.dart` — NEW
- `test/features/workout/presentation/widgets/exercise_slot_row_test.dart` — EXTENDED

### Generated (do not edit)
- `lib/l10n/app_l10n_*.dart` — regenerated by `flutter gen-l10n`

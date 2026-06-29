# Exploration: exercise-notes

## Current State

### Data Model (Routine → Day → Slot)

The hierarchy is: `Routine` → `List<RoutineDay>` → `List<RoutineSlot>`.

**`RoutineSlot`** (`lib/features/workout/domain/routine_slot.dart:36–88`) is the domain object for a per-exercise prescription inside a day. It already carries:

```dart
String? notes, // nullable free-form coaching notes (line 46)
```

This field EXISTS in the domain model but is **completely wired to nothing**: it is never written by the editors, never displayed to the athlete, and never surfaced in the session player. The field is defined in the freezed model but is a silent stub.

**`Exercise`** (`lib/features/workout/domain/exercise.dart`) is the catalog item — it does NOT carry per-routine notes, only `techniqueInstructions` (a shared list authored globally, not per-routine).

**`RoutineDay`** has no note field. **`Routine`** has no per-exercise note field.

### Assignment Flow (Critical)

Trainer-assigned plans are stored as **live Firestore documents** in the `routines/` collection. There is NO snapshot/copy on assignment — the athlete reads the document directly via `assignedTo` field. This means:

- A note written by the PF is immediately visible to the athlete — no propagation needed.
- Updating a note after assignment works: athlete reads the latest doc.
- This applies to both `TrainerAssigning` and `TrainerTemplating` modes. The `assignTemplateToAthlete` path copies the template into a new assigned doc (`routine_repository.dart:404`), so notes set in the template ARE carried through at assignment time.

### Editor (Mobile: `routine_editor_screen.dart`)

The mutable in-editor representation is `_EditableSlot` (lines 115–157). This class does NOT have a `notes` field. The `buildRoutineSlot` function (line 249) constructs a `RoutineSlot` from `_EditableSlot` but never populates `notes` — it silently drops it. The `_loadExistingRoutine` hydration (line 528) also never restores `notes` from Firestore into `_EditableSlot`.

The editor has three modes: `TrainerAssigning`, `TrainerTemplating`, `SelfCreating`. The note is PF-authored only, so it should only be editable in trainer modes.

The `buildRoutineSlot` function is a top-level testable helper shared between the submit path and tests.

### Editor (Web Coach Hub: `treino-coach-hub/lib/features/workout/presentation/routine_editor_screen.dart`)

The web Coach Hub has its own **separate copy** of the routine editor screen with its own `_EditableSlot` and `buildRoutineSlot`. Both must be updated in parallel. The web editor does not use `AppL10n` — it uses hardcoded Spanish strings with `// i18n` comments.

### Session Player (`presentation/session_player_screen.dart`)

The `_ExerciseSection` widget (line 1152) receives `slot` (a `RoutineSlot`) but never accesses `slot.notes`. It shows `techniqueInstructions` (from the Exercise catalog) via a `TechniqueSheet` bottom-sheet triggered by an ⓘ icon. The PF note would live at `slot.notes`, not `exercise.techniqueInstructions`.

### Routine Detail Screen (`presentation/routine_detail_screen.dart`)

Slots are rendered via `ExerciseSlotRow` widget. That widget shows exercise name, sets/reps summary, muscle group, rest, and ÚLTIMO weight — but not `slot.notes`.

### Firestore Rules

The `hasOnly` guards in `firestore.rules` check the top-level `Routine` document keys. Since `notes` lives inside `RoutineSlot` which is inside `RoutineDay.slots` (all serialized as the `days` array), it is automatically covered by the existing `'days'` key in all update path guards. **No Firestore rules changes needed.**

However, the `affectedKeys()` diff check on all UPDATE paths requires that `days` is listed as an allowed changed key — it already is. Any slot-level field inside `days` flows through transparently.

### Existing Free-Text Patterns

- `AthleteNote` (`coach/domain/athlete_note.dart`): a separate document with a single `String note` field. Stored as `athlete_notes/{trainerId}_{athleteId}`. This is a different scope (per-athlete, not per-exercise).
- `performanceLogNotesHint` (`intl_es_AR.arb:489`): a free-text textarea in the performance log form. Uses standard `TextField` with multiline.
- `Exercise.techniqueInstructions`: a `List<String>` displayed as numbered items via `TechniqueInstructionItem`. This is catalog-level, not plan-level.

### Back-compat / Migration

`RoutineSlot` is a freezed model. The `notes` field already exists with `String? notes` (no `@Default` annotation, meaning it defaults to `null` on deserialization when absent from Firestore). Existing documents that lack this field deserialize safely — `null` means "no note". No migration needed. No `@Default('')` required either; `null` is cleaner to test for "no note to show".

---

## Affected Areas

- `lib/features/workout/domain/routine_slot.dart` — field already present (`String? notes`); no model change needed
- `lib/features/workout/presentation/routine_editor_screen.dart` — add `notes` to `_EditableSlot`, hydrate it in `_loadExistingRoutine`, emit it in `buildRoutineSlot`, add TextField in trainer-mode slot card
- `treino-coach-hub/lib/features/workout/presentation/routine_editor_screen.dart` — same changes, parallel file
- `lib/features/workout/presentation/routine_detail_screen.dart` — surface note below exercise name in `ExerciseSlotRow` or after it in `_RoutineDetailContent`
- `lib/features/workout/presentation/session_player_screen.dart` — surface note in `_ExerciseSection` (visible during workout)
- `lib/features/workout/presentation/widgets/exercise_slot_row.dart` — optionally update widget signature to accept/render `slot.notes`
- `lib/l10n/intl_es_AR.arb` + `intl_en.arb` + generated `app_l10n_*.dart` — new string keys for the input hint, section label
- `firestore.rules` — no changes needed (notes is inside the `days` array)
- Tests for `routine_editor_screen.dart` (both apps), `exercise_slot_row.dart`, `session_player_screen.dart`

---

## Approaches

### Option A — Wire the existing `notes` field end-to-end (free text, no char limit, trainer-only edit)

Add `notes` to `_EditableSlot` in both editors. Hydrate in `_loadExistingRoutine`. Emit in `buildRoutineSlot`. Show a `TextField` (multiline, max 3–4 lines) below the set table in the trainer-mode slot card. Surface `slot.notes` as a quiet italic line in `ExerciseSlotRow` and in `_ExerciseSection` of the session player.

- Pros: minimal model change (field already exists), zero Firestore migration, natural fit for PF cues like tempo/RIR; works on both trainer-assigned and template flows automatically
- Cons: trainer-mode slot card is already dense; dual-editor sync (mobile + web coach hub) doubles the UI work; no char limit enforcement in this option
- Effort: Medium (two editors + two reader surfaces + l10n + tests)

### Option B — Free text with char limit (e.g. 200 chars), show char counter

Same as A but adds a `maxLength: 200` on the `TextField` and shows the built-in character counter. Matches `AthleteNote` pattern (that one has no limit but is analogous).

- Pros: prevents runaway notes from overflowing the UI; sets a clear scope for PF (a cue, not an essay)
- Cons: arbitrary limit may frustrate PFs with detailed technique cues; 200 is guesswork
- Effort: Medium (+2 lines over Option A)

### Option C — Separate "Nota" expandable sheet (bottom-sheet / modal)

Instead of inline text in the slot card, show a small "Nota del PF" chip/icon on the slot. Tapping it opens a bottom-sheet for editing (trainer) or reading (athlete). This avoids cluttering the already-dense slot card.

- Pros: clean slot card UI; note editing has more room; athlete read is explicit (not easy to miss)
- Cons: extra navigation layer; more widget code; chip may be missed by athlete; harder to discover for PF
- Effort: High

---

## Recommendation

**Option A with a 200-char soft limit (Option B).**

The field already exists — this is a wire-up, not a new model. A 200-character limit (roughly 2–3 training cues) is appropriate for "bajá 3 seg en la excéntrica · RIR 2 · pausa abajo" level notes. Use `maxLength` + `maxLengthEnforcement: MaxLengthEnforcement.enforced` to hard-cap it and show the counter only when note is non-empty (to avoid adding visual noise to slots without notes). On the reader side (detail screen + session player), render the note as a small italic text below the exercise name — conditionally rendered only when `slot.notes?.isNotEmpty == true`. The session player's `_ExerciseSection` already receives `slot` directly, so no new data plumbing is needed there.

For the editor, add the `TextField` only when `_isTrainerMode` is true (already gated consistently throughout the editor). The athlete (`SelfCreating`) never sees the note input. Since notes are PF-only authored but athlete-visible, athlete routines (`source == user-created`) will simply never have notes set; the display code renders nothing when `notes` is null.

**Surface in session player**: between the exercise name header and the first set row — a single muted italic line. This is the highest-value surface because the athlete reads it just before logging sets.

**Surface in routine detail**: below the exercise name in `ExerciseSlotRow`. A small `textMuted` italic line. Conditionally shown.

---

## Open Questions for Proposal Phase

1. **Should `SelfCreating` athletes be able to write notes to themselves?** The current spec says PF-authored only. If yes in the future, the gating must change. Decide now to lock scope.
2. **Char limit**: 200 hard-cap or soft-warn? Recommend hard-cap via `MaxLengthEnforcement.enforced` — prevents overflow bugs.
3. **Session player visibility**: show note only when block is `current` (athlete is actively doing the exercise), or also on `completed`/`future` blocks? Recommend `current` only to avoid information overload.
4. **Routine detail screen**: the note is on the slot (per-exercise), not shown in `ExerciseDetailScreen` (the catalog detail). Confirm this is correct — the catalog detail shows technique for ALL athletes, while the routine note is PF-specific to this plan. These are orthogonal.
5. **Web Coach Hub parity**: must both editors ship together, or can mobile ship first? Dual-editor is the main effort multiplier.

---

## Risks

- **Dual-editor maintenance**: both `treino` and `treino-coach-hub` have copies of `routine_editor_screen.dart` with their own `_EditableSlot`. Any note-related change must be applied to both. This is an existing structural risk, not created by this feature.
- **`buildRoutineSlot` note omission**: the function is top-level and tested by `RoutineEditorTestBridge`. Tests for the existing function do not test `notes`. New tests must cover the round-trip (set in `_EditableSlot` → persisted in `RoutineSlot`).
- **Hydration gap**: `_loadExistingRoutine` currently does not restore `slot.notes` into `_EditableSlot`. If a PF edits a routine that already had notes (written via another client), those notes would be silently dropped on save. The fix is to restore them in the hydration path — critical correctness requirement.
- **Firestore rules `affectedKeys()` diff**: the diff check only allows `['name', 'split', 'level', 'days', 'numWeeks']`. Since `notes` is inside a slot inside `days`, and `days` IS in the allowed set, this works without touching rules. Verified by reading the rules at lines 154–200.
- **No migration**: existing docs are compatible; `notes: null` on deserialization is the natural default. No Firestore migration scripts needed.
- **Web Coach Hub uses hardcoded Spanish**: the note input label/hint must be added as hardcoded Spanish with `// i18n` comment in the web editor, not via `AppL10n`.

---

## Ready for Proposal

Yes. The exploration is complete. The model field exists, the assignment flow is live (no snapshot), back-compat is automatic, and the two surfaces (detail screen + session player) are clearly identified. The dual-editor risk is known and scoped. The proposal phase should decide char limit, session player visibility gating, and dual-editor shipping order.

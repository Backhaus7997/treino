# Proposal: exercise-notes

> Status: proposed · Phase: propose · Change: `exercise-notes` · Project: treino
> Artifact store: hybrid (engram topic `sdd/exercise-notes/proposal` + this file)

## ⚠️ Exploration correction (authoritative override)

The exploration artifact (`sdd/exercise-notes/explore`) claims there are **two routine
editors in two repos** (`treino/` mobile + `treino-coach-hub/` web) and names
"dual-editor sync" the main effort multiplier. **This is factually wrong and is
overridden here.**

- `treino/`, `treino-coach-hub/`, and `treino-ajustes/` are **three clones of the SAME
  git repo** (`github.com/Backhaus7997/treino`) checked out to different branches.
  `treino-coach-hub/` and `treino-ajustes/` are **stale feature-branch clones**, not
  separate codebases or separate editors.
- The canonical repo (`treino/` on `main`) has **exactly ONE routine editor**:
  `lib/features/workout/presentation/routine_editor_screen.dart`, parametrized by
  `RoutineEditorMode` (`routine_editor_mode.dart`). The mobile app, the web Coach Hub
  entry (`lib/main_coach_hub.dart`), and the trainer "crear plan" flow
  (`lib/features/coach/presentation/athlete_detail_screen.dart`) all route to this same
  screen.
- ⇒ **There is NO dual-repo / dual-editor work. ONE editor. ONE PR in the `treino` repo.**
  Every "update both editors in parallel" and "dual-editor maintenance / shipping order"
  item from the explore is disregarded.

Everything else in the exploration (the `notes` field already exists, the live-document
assignment flow with no snapshot, automatic Firestore-rules coverage via the `days` key,
no migration needed) was independently re-verified against the code and holds.

---

## 1. Intent & motivation

**Problem.** A personal trainer (PF) prescribes exercises to athletes but has no
first-class place to attach a per-exercise coaching cue — technique reminders, tempo,
RIR/effort targets, pause/range-of-motion notes. Today the only channels are:

- `Exercise.techniqueInstructions` — catalog-level, shared across ALL athletes and ALL
  plans. Not plan-specific, not editable by the PF per prescription.
- Chat / `AthleteNote` — per-athlete, free-floating, not anchored to the exercise the
  athlete is about to perform. The cue is lost the moment the athlete opens the player.

The athlete reads prescriptions in the **session player** at the exact moment of
execution. That is precisely where a PF cue ("bajá 3 seg en la excéntrica · RIR 2 ·
pausa abajo") delivers its value, and precisely where today there is nothing.

**Why now.** The domain already carries the right field. `RoutineSlot.notes`
(`routine_slot.dart:46`, `String? notes`) exists in the freezed model but is wired to
**nothing** — never written by the editor, never hydrated on re-edit, never displayed.
It is a silent stub. Shipping the feature is a **wire-up, not a model change**: no
freezed change, no `json_serializable` regen of the shape, no Firestore migration, no
Firestore-rules change (notes lives inside `days[].slots[].notes`, and `days` is already
an allowed key on every update path). The cost/benefit ratio is unusually favorable.

There is also a **latent data-loss bug** riding on the same field (see §6) that this
change must close regardless — the field is half-present in a way that will silently drop
data the moment any client writes a note. Fixing it standalone would touch the exact same
code, so it belongs in this change.

**Success looks like.**
- A PF, while building or editing a plan, can type a short note under any exercise.
- The athlete sees that note (read-only) in the routine detail and, critically, in the
  session player at the moment of execution.
- Notes survive a re-edit round-trip (write → save → reopen → save again) with no loss.
- Athletes never author notes; the input does not appear in self-create mode.
- `flutter analyze` 0 issues, `dart format` clean, `flutter test` green (strict TDD).

---

## 2. Scope

### IN scope

1. **Note input per exercise in the editor**, gated to trainer/plan-building modes.
   - Add a `String? notes` (or `String notes = ''`) field to the in-editor `_EditableSlot`.
   - Render a multiline `TextField` in the slot card (`_SlotEditor` /
     `_SlotEditorState`, `routine_editor_screen.dart`) **only when `_isTrainerMode` is
     true**. `_isTrainerMode` is already the canonical trainer gate
     (`routine_editor_screen.dart:662` → `TrainerAssigning || TrainerTemplating`).
   - Emit `notes` in `buildRoutineSlot` (`routine_editor_screen.dart:293`) so it persists.

2. **Fix the hydration gap (latent data-loss bug — MUST be in this change).**
   - `_loadExistingRoutine` (`routine_editor_screen.dart:528`) rebuilds each
     `_EditableSlot` from the persisted `RoutineSlot` but **never restores `slot.notes`**.
     Combined with `buildRoutineSlot` not emitting it, any note written by any client is
     **silently dropped** the next time a PF opens and saves that plan. Restore
     `editableSlot.notes = slot.notes` in the hydration map.

3. **Read-only display in the session player.**
   - `_ExerciseSection` (`session_player_screen.dart:1152`) already receives the full
     `RoutineSlot` via `widget.slot` — `widget.slot.notes` is reachable with **zero new
     data plumbing**. Render the note as a muted line in the exercise header region
     (`session_player_screen.dart:~1300`), conditionally, when non-empty.

4. **Read-only display in the routine detail.**
   - `ExerciseSlotRow` (`widgets/exercise_slot_row.dart`) already receives the full
     `RoutineSlot`. Render the note as a small muted/italic line below the exercise name,
     conditionally, when non-empty. No signature change needed (slot is already passed).

5. **~200-character cap** on the input (see §5 for the exact value and enforcement mode).

6. **AppL10n keys** for any new mobile-facing labels (input hint, optional section
   label, char-counter semantics if surfaced). Mobile copy goes through `AppL10n`
   (`intl_es_AR.arb` + `intl_en.arb` + regenerated `app_l10n_*.dart`), following the
   existing `routineEditor*` namespace (e.g. `routineEditorAddExercise`,
   `routineEditorLevelLabel`). Because the editor is a SINGLE screen shared by mobile and
   the web Coach Hub entry, there is **no separate web editor file** to add hardcoded
   strings to — the `// i18n` hardcoded-Spanish convention does not apply here. (The
   `// i18n` rule still governs any genuinely web-only Coach Hub widgets, but the routine
   editor is not one of them.)

### OUT of scope (explicit)

- **Athlete-authored notes.** Notes are PF-authored only. `SelfCreating` athletes never
  see the input. A future change may add athlete self-notes; the gating is deliberately
  `_isTrainerMode` so that decision stays a one-line change later. Locked: NOT in scope.
- **Per-set notes.** The note is per-slot (per-exercise prescription), not per-set-row.
- **Structured fields** (tempo / RIR / pause as separate typed inputs or pickers). The
  note is a single free-text string. Structuring it later is a separate change.
- **Surfacing the note in `ExerciseDetailScreen`** (the catalog exercise detail). That
  screen shows catalog `techniqueInstructions` shared across athletes; the slot note is
  plan-specific and orthogonal. Not in scope.
- **Any change to `treino-coach-hub/` or `treino-ajustes/` clones.** They are stale
  branches of the same repo, not deliverables.

---

## 3. Approach

Wire the existing `RoutineSlot.notes` field end-to-end (the explore's **Option B**:
Option A wire-up + a character cap). No model change, no migration, no rules change.

### Touchpoints (all in `treino` on `main`)

| # | File | Change |
|---|------|--------|
| 1 | `routine_editor_screen.dart` — `_EditableSlot` (line ~115) | Add a `notes` field (`String? notes;` or `String notes = '';`). |
| 2 | `routine_editor_screen.dart` — `buildRoutineSlot` (line ~293) | Pass `notes: s.notes` (normalize empty→null) into the returned `RoutineSlot`. |
| 3 | `routine_editor_screen.dart` — `_loadExistingRoutine` (line ~528) | Restore `editableSlot.notes = slot.notes` during hydration (**bug fix**). |
| 4 | `routine_editor_screen.dart` — `_SlotEditorState.build` (line ~2629) | Add a multiline `TextField` with the char cap, wired to `slot.notes` via `onChanged` + `widget.onChanged`, rendered only when `_isTrainerMode`. Follow the existing controller/`_hydrating` dirty-guard pattern used by the name/split fields. |
| 5 | `routine_editor_screen.dart` — `RoutineEditorTestBridge.buildSlotBridge` (line ~3507) | Add an optional `notes` param so the round-trip can be unit-tested without the widget tree (closes the test gap in §6). |
| 6 | `session_player_screen.dart` — `_ExerciseSection.build` header (line ~1300) | Render `widget.slot.notes` as a muted line when non-empty. No new constructor param (slot already passed). |
| 7 | `widgets/exercise_slot_row.dart` — `build` (line ~196) | Render `slot.notes` as a muted/italic line below the exercise name when non-empty. No signature change. |
| 8 | `lib/l10n/intl_es_AR.arb` + `intl_en.arb` + generated `app_l10n_*.dart` | New `routineEditor*` keys for the note input hint/label. |

**No change** to: `routine_slot.dart` (field exists), `firestore.rules` (covered by
`days`), any repository (`createAssigned` / `updateAssigned` / `createTemplate` /
`updateTemplate` / `assignTemplateToAthlete` all serialize `days` wholesale, so `notes`
flows through automatically — including the template→assignment copy at
`routine_repository.dart:404`).

### RoutineEditorMode variants where the input appears (recommendation)

The enum (`routine_editor_mode.dart`) has three sealed variants:

- `TrainerAssigning` — PF builds a plan for a specific athlete → **SHOW input.**
- `TrainerTemplating` — PF builds a reusable template → **SHOW input.** Notes set on a
  template are carried into the assigned doc when `assignTemplateToAthlete` copies the
  template (verified: assignment copies `days`, and `notes` lives inside `days`).
- `SelfCreating` — athlete authors their own routine → **HIDE input.**

**Recommendation: gate on the existing `_isTrainerMode` getter** (`TrainerAssigning ||
TrainerTemplating`). It is already the consistent trainer-only gate throughout the editor
(used for the split field at line 706, and trainer-only UI blocks at lines 1657/1689), so
reusing it keeps the note input aligned with every other trainer-only affordance and
needs no new predicate. Athlete (`SelfCreating`) routines simply never carry notes; the
read-only surfaces render nothing for them because the note is null/empty.

---

## 4. Read-only display behavior

- **Session player** (`_ExerciseSection`): a single muted line in the exercise header,
  near the name and the ⓘ technique affordance. This is the highest-value surface — the
  athlete reads it immediately before logging the set. Distinguish it visually from the
  catalog `techniqueInstructions` (the ⓘ bottom-sheet) so the two are not confused: the
  PF note is the PF's plan-specific cue; technique instructions are catalog-wide.
- **Routine detail** (`ExerciseSlotRow`): a small muted/italic line below the exercise
  name, above or beside the sets·reps summary.
- Both surfaces render **conditionally** — only when `slot.notes?.isNotEmpty == true`.
  An empty/null note adds zero visual footprint (no empty label, no placeholder).

---

## 5. Micro-decisions (recommendations to lock in spec/design)

1. **Character cap: 200, hard-enforced.**
   Use `maxLength: 200` with `maxLengthEnforcement: MaxLengthEnforcement.enforced` on the
   `TextField`. 200 chars ≈ 2–3 training cues ("bajá 3 seg en la excéntrica · RIR 2 ·
   pausa abajo") — enough for real cues, short enough to prevent UI overflow on the
   compact player/detail rows. Hard-enforce (not soft-warn) to make overflow structurally
   impossible. Show the built-in counter **only while the field is non-empty / focused**
   to avoid adding noise to every slot card. Open to 240 if PF research pushes back, but
   200 is the recommended start.

2. **Player visibility: `current` block only (recommended), reconsider on feedback.**
   Show the note on the **currently-active** exercise section. Showing it on every
   completed/future block risks information overload in a long session. The note is a
   "do this now" cue; `current` is when it matters. (Implementation note: `_ExerciseSection`
   renders all blocks; the conditional can key off the section's active/expanded state.
   If product wants it always-visible, that is a trivial widening later — flag it as the
   one micro-decision most worth confirming with the user.)

3. **Empty-note rendering: hide entirely.**
   When `notes` is null or empty, render NOTHING on both read surfaces (no label, no
   spacer). Store empty input as `null` (normalize `''`→`null` in `buildRoutineSlot`) so
   "no note" is a single canonical state and the display guard is a clean
   `notes?.isNotEmpty == true`.

---

## 6. Risks (real ones only)

- **Latent data-loss bug (the reason the fix is mandatory).** `buildRoutineSlot` does not
  emit `notes` AND `_loadExistingRoutine` does not hydrate it. Today nothing writes the
  field so the bug is dormant. The moment this feature (or any other client) writes a
  note, the next PF "open plan → save" cycle silently strips it. Both halves
  (emit + hydrate) MUST land together; shipping the input without the hydration fix would
  ship a known data-loss path. Mitigation: touchpoints #2 and #3 are non-optional and
  covered by the round-trip test below.
- **Round-trip test gap in `RoutineEditorTestBridge`.** `buildSlotBridge` (line ~3507)
  constructs `_EditableSlot` with no `notes` parameter, so no existing test asserts
  `notes` survives the editor→slot derivation. Mitigation: extend the bridge with a
  `notes` param (touchpoint #5) and add a test asserting `notes` round-trips through
  `buildRoutineSlot`. Without bridge support, the bug fix is untestable at the unit level.
- **Player surface ambiguity with catalog technique instructions.** The player already
  shows catalog `techniqueInstructions` via the ⓘ sheet. The PF note is a *different*
  thing on the same screen. Mitigation: visually distinguish (the note is inline/muted;
  technique stays behind the ⓘ). Low risk, but a design call to make explicit.

> NOT a risk: dual-editor sync. There is one editor (see correction at top). Disregard
> every dual-editor / dual-repo / shipping-order concern from the exploration.

---

## 7. Testing / TDD

Strict TDD is active for this project — test runner `flutter test`. Write the failing
test first for each surface, then implement. Quality gate before commit: `flutter analyze`
0 issues + `dart format .` + `flutter test` green.

Test surfaces:

1. **Editor round-trip (unit, via `RoutineEditorTestBridge`).** With the bridge extended
   to accept `notes`: assert that a note set on `_EditableSlot` is present on the
   `RoutineSlot` returned by `buildRoutineSlot`, and that empty/whitespace normalizes to
   `null`. This is the primary guard for the data-loss bug.
2. **Hydration round-trip (widget or bridge-level).** Build → save → re-hydrate → save
   again, asserting the note survives both legs (directly exercises the
   `_loadExistingRoutine` fix). If a pure-unit hydration entry point does not exist, add a
   focused widget test that pumps the editor in `TrainerAssigning(existingPlanId: …)` mode
   against a fake repo returning a slot with notes.
3. **Trainer-only gating (widget).** Pump the editor in each `RoutineEditorMode`: assert
   the note `TextField` is present in `TrainerAssigning` and `TrainerTemplating`, and
   absent in `SelfCreating`.
4. **Player display (widget).** `_ExerciseSection` (or its host) renders the note when
   `slot.notes` is non-empty and renders nothing when null/empty; on the current block per
   §5.2.
5. **Routine detail display (widget).** `ExerciseSlotRow` renders the note line when
   non-empty and nothing when null/empty.
6. **Char cap (widget).** Input beyond 200 chars is rejected (enforced), confirming
   `maxLengthEnforcement`.

---

## 8. Review workload forecast

- **Estimated changed lines: ~150–230** across one production file cluster
  (`routine_editor_screen.dart` for the bulk: `_EditableSlot` field, `buildRoutineSlot`
  emit, `_loadExistingRoutine` hydrate, `_SlotEditor` TextField, bridge param), two small
  reader edits (`session_player_screen.dart`, `exercise_slot_row.dart`), and l10n keys —
  plus ~120–180 lines of tests across the surfaces above.
- **Single PR vs chained: SINGLE PR.** All edits are tightly coupled around one field in
  one feature, in one repo. Production changes comfortably fit under the 400-line budget;
  tests are additive. There is no dependency ordering that forces a split.
- **Decision needed before apply: No.** No `size:exception` expected. Chained PRs not
  recommended.

---

## 9. Next phases

`sdd-spec` and `sdd-design` can run **in parallel** off this proposal. Spec captures the
requirements/scenarios (PF authoring, athlete read-only, gating, char cap, round-trip,
display conditionals); design captures the touchpoint-level UI/state decisions and the
test-bridge extension.

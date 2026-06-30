# Design: exercise-notes (PF-authored per-exercise notes)

> Technical design (the architectural HOW). Implementation-ready for `sdd-tasks`.
> Source of truth: proposal `sdd/exercise-notes/proposal` (obs #105). Locked
> decisions there are NOT re-opened here. All line numbers below were
> re-verified against the working tree on 2026-06-29.

## 1. Executive summary

Wire the existing-but-dormant `RoutineSlot.notes` field end-to-end through the
single canonical routine editor and two read surfaces. No domain/model change,
no migration, no Firestore-rules change. The change is a **field-plumbing +
display** exercise plus a **latent data-loss bug fix** (emit + hydrate must land
together). One PR, well under the 400-line budget.

Architecture style stays as-is: feature-first, presentation widgets receive data
by constructor (no `ref.watch` in leaf widgets), Riverpod 2 at the screen level,
`AppPalette.of(context)` for color, `TreinoIcon.*` for icons, `AppL10n` for copy.

## 2. Component map & data flow

```
                         RoutineSlot.notes  (domain — UNCHANGED, routine_slot.dart:46)
                                   │
            WRITE PATH            ▼                         READ PATHS
  ┌──────────────────────────────────────────┐   ┌───────────────────────────────┐
  │ routine_editor_screen.dart                 │   │ session_player_screen.dart    │
  │  _EditableSlot.notes        (state)        │   │  _ExerciseSection (current     │
  │   ├─ emit  → buildRoutineSlot (line 293)   │   │   block ONLY — structural)     │
  │   ├─ hydrate ← _loadExistingRoutine (528)  │   │  renders widget.slot.notes     │
  │   └─ input → _SlotEditorState.build        │   └───────────────────────────────┘
  │              (gated _isTrainerMode)        │   ┌───────────────────────────────┐
  │  RoutineEditorTestBridge.buildSlotBridge   │   │ widgets/exercise_slot_row.dart │
  │   (line 3507 — add notes param for tests)  │   │  ExerciseSlotRow (always)      │
  └──────────────────────────────────────────┘   │  renders slot.notes            │
                                                   └───────────────────────────────┘
```

Persistence is free: repositories serialize `days` wholesale, and the
template→assignment copy at `routine_repository.dart:404` already carries
`notes` because it copies the whole `days[]` structure. NOTHING in the data layer
changes.

The write trio (`_EditableSlot` field + emit + hydrate) MUST ship together — see
§9 risk R1.

## 3. Editor (`lib/features/workout/presentation/routine_editor_screen.dart`)

### 3.1 State field — `_EditableSlot` (class at line 115, ctor at 156)

Add a nullable field alongside the other scalar slot fields:

```dart
class _EditableSlot {
  Exercise? exercise;
  ...
  int? supersetGroup;
  ...
  /// PF-authored coaching cue for this exercise (technique/tempo/RIR).
  /// Trainer-only input; null/empty when none. Mirrors RoutineSlot.notes.
  String? notes;
  ...
}
```

### 3.2 Emit — `buildRoutineSlot` (RoutineSlot ctor, line 293)

Add `notes:` to the returned `RoutineSlot`, normalizing empty → null so the
display guard stays a single `notes?.isNotEmpty == true` check:

```dart
return RoutineSlot(
  exerciseId: s.exercise!.id,
  ...
  supersetGroup: effectiveGroup,
  ...
  // Empty/whitespace normalizes to null so readers guard on isNotEmpty only.
  notes: (s.notes?.trim().isNotEmpty ?? false) ? s.notes!.trim() : null,
  ...
);
```

### 3.3 Hydrate — `_loadExistingRoutine` (cascade at lines 529–542) — BUG FIX

The `_EditableSlot()` cascade that rebuilds editor state from the persisted slot
omits `notes`, so re-editing a routine silently drops it on the next save. Add
one cascade line at the END of the existing cascade (after
`..activeWeeks = slot.activeWeeks.toSet()`, line 542):

```dart
final editableSlot = _EditableSlot()
  ..exercise = Exercise( ... )
  ..exerciseMode = slot.effectiveExerciseMode
  ..restSeconds = slot.restSeconds
  ..supersetGroup = slot.supersetGroup
  ..activeWeeks = slot.activeWeeks.toSet()
  ..notes = slot.notes; // hydrate PF note — closes latent data-loss gap
```

This runs identically for all three modes (the comment at line 504 confirms the
inverse-of-create path applies to SelfCreating / TrainerAssigning /
TrainerTemplating). Hydration is unconditional — gating is a display concern, not
a data-retention concern; an athlete who later self-edits a trainer plan must not
silently strip the coach's note.

### 3.4 Input widget — `_SlotEditorState.build` (build at line 2629)

Insert the notes field **after the rest-duration Row (closes at line 2764) and
before the `_SetTable` (line 2768)**, inside the existing slot-card `Column`
(opened at line 2654). Self-gate on trainer mode (see §3.5) — render nothing in
SelfCreating mode.

Widget shape — a `TextFormField` styled to match the card (no per-field box, same
muted palette as `DurationTextField`/set rows). 200-char HARD cap per locked
decision:

```dart
// ── PF coaching note (trainer modes only) ────────────────────────────────
if (widget.isTrainerMode) ...[
  const SizedBox(height: 12),
  TextFormField(
    key: const Key('slot_notes_field'),
    initialValue: slot.notes,
    maxLength: 200,
    maxLengthEnforcement: MaxLengthEnforcement.enforced,
    minLines: 1,
    maxLines: 3,
    textCapitalization: TextCapitalization.sentences,
    style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
    decoration: InputDecoration(
      labelText: l10n.routineEditorNotesLabel,
      hintText: l10n.routineEditorNotesHint,
      // Counter only matters near the cap; hide the always-on "0/200".
      counterText: '',
      labelStyle: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
      hintStyle: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
      isDense: true,
      border: const UnderlineInputBorder(),
    ),
    onChanged: (v) {
      slot.notes = v;          // store raw; ''→null normalization at emit (§3.2)
      widget.onChanged();      // same dirty-tracking path as restSeconds
    },
  ),
],
```

Notes on choices:
- `TextFormField` (not `TextField`) because the editor uses `initialValue`-style
  hydration for ephemeral fields and we do NOT want to own a controller lifecycle
  for a per-card field rebuilt under an `ObjectKey(slot)` (line 2171). The
  `ObjectKey` already rebinds State to the slot identity, so `initialValue`
  reflects the hydrated `slot.notes` correctly on (re)build.
- `counterText: ''` hides the permanent `0/200`; the hard `maxLengthEnforcement`
  still blocks the 201st char. (Locked decision said counter "only when
  non-empty/focused" — Flutter has no built-in focus-conditional counter without
  extra state; hiding it is the smallest correct choice and keeps the card clean.
  A focus-aware counter is explicitly OUT of scope — note for `sdd-tasks`.)
- `const SizedBox(height: 12)` matches the spacing rhythm used between the
  rest row and the set table.

### 3.5 Threading `isTrainerMode` into `_SlotEditor` (plumbing — REQUIRED)

`_SlotEditor` is a private widget instantiated in **two** places and does NOT
currently receive the trainer flag. The screen-level `_isTrainerMode` getter
(line 662 = `TrainerAssigning || TrainerTemplating`) is the canonical gate, but
it lives on `_RoutineEditorScreenState`. The widget chain is:

```
_RoutineEditorScreenState (_isTrainerMode @662)
  └─ _DayExpansionTile         (instantiated @1767 — add `isTrainerMode` param)
       └─ _SlotEditor          (standalone @2170)            ← add `isTrainerMode`
       └─ _SupersetBlock-style builder (@2473 _SlotEditor)   ← add `isTrainerMode`
```

Add a `final bool isTrainerMode;` constructor param (default `false`) to:
1. `_SlotEditor` (ctor at line 2574) — consumed in `build` (§3.4).
2. `_DayExpansionTile` (ctor at line 2097) — forwarded to BOTH `_SlotEditor`
   call sites (line 2170 and the superset builder at 2473; the superset rows are
   built by a method/widget that also needs the flag forwarded).
3. The screen passes `isTrainerMode: _isTrainerMode` at the `_DayExpansionTile`
   call site (line 1767).

Default `false` keeps the field hidden unless a trainer-mode screen explicitly
opts in — fail-safe: a missed wiring point hides the field rather than leaking it
to athletes. This is the SMALLEST plumbing that reaches both call sites without
introducing an InheritedWidget or provider (over-engineering for one bool).

### 3.6 Test bridge — `buildSlotBridge` (line 3507)

Add an optional `String? notes` param (default null) so unit tests can assert the
emit-normalization without pumping a widget. Backward-compatible: existing call
sites (set-table test lines 226, 260) pass no `notes` and keep compiling.

```dart
static RoutineSlot buildSlotBridge({
  required ExerciseMode exerciseMode,
  required RepMode repMode,
  required List<({...})> sets,
  String? notes,                 // NEW — exercises §3.2 normalization
}) {
  final slot = _EditableSlot()
    ..exercise = const Exercise(...)
    ..exerciseMode = exerciseMode
    ..repMode = repMode
    ..notes = notes              // NEW
    ..weeklySets = [ ... ];
  return buildRoutineSlot(slot, null);
}
```

## 4. Player (`lib/features/workout/presentation/session_player_screen.dart`)

### 4.1 Why "current block only" needs NO extra gate

`_ExerciseSection` is structurally rendered ONLY for the current block. The block
dispatcher (`build` at line 746) switches on a `BlockStatus` enum:
`completed → _CompletedBlockSummary`, `future → _FutureBlockPreview`,
`current → _ExerciseSection` (line 755). The superset layout (line 1087) builds
`_ExerciseSection` only inside the active block's entry list. Therefore placing
the note in `_ExerciseSection` ALREADY satisfies "current block only" — no
`isCurrent`/`currentSetNumber` check is required. Completed and future blocks use
different widgets that deliberately omit the note. This is documented so
`sdd-tasks` does NOT add a redundant guard.

### 4.2 Render location & shape

`_ExerciseSection.build` (line 1215). The header `Row` closes at line 1365,
followed by `const SizedBox(height: 12)` (1366) then `...rowWidgets`. Insert the
note **between the header row and the set rows** — directly after line 1365,
before the existing `SizedBox(height: 12)` — so it reads as a sub-caption of the
exercise name and sits above the sets:

```dart
Row( ... header with name + ⓘ + count ... ),   // closes @1365
if (widget.slot.notes?.isNotEmpty == true) ...[
  const SizedBox(height: 8),
  Text(
    widget.slot.notes!,
    style: GoogleFonts.barlow(
      fontSize: 13,
      height: 1.3,
      fontStyle: FontStyle.italic,           // muted italic — see §7 visual diff
      color: palette.textMuted,
    ),
  ),
],
const SizedBox(height: 12),                    // existing @1366
...rowWidgets,
```

The slot is already passed to `_ExerciseSection` (line 1088 / 760) — ZERO new
plumbing. Guard is the normalized `notes?.isNotEmpty == true`; empty/null renders
nothing.

## 5. Routine detail (`lib/features/workout/presentation/widgets/exercise_slot_row.dart`)

`ExerciseSlotRow.build` (line 148). The content `Column` (line 194) has: name
(197), sets·muscle Row (207), rest Row (238). The rest Row closes at line 255.
Insert the note as a final small muted line at the END of that Column — after the
rest Row (after line 255), before the Column closes (line 256–257):

```dart
Row( ... rest icon + "$restText descanso" ... ),  // closes @255
if (slot.notes?.isNotEmpty == true) ...[
  const SizedBox(height: 8),
  Text(
    slot.notes!,
    style: GoogleFonts.barlow(
      fontWeight: FontWeight.w400,
      fontSize: 12,
      fontStyle: FontStyle.italic,
      color: palette.textMuted,
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  ),
],
```

Always shown (per locked decision: routine detail shows note always, read-only),
guarded only by non-empty. `slot` is already a constructor field (line 24) —
zero new plumbing. `maxLines: 2 + ellipsis` keeps the list row from ballooning;
the full note is visible in the player. Update the row's `Semantics.label`
(line 154) is OPTIONAL and OUT of scope unless trivial — flag for `sdd-tasks` as
a nice-to-have, not a requirement.

## 6. l10n — new `AppL10n` keys

Four arb files carry strings; two generated dart files implement them
(`app_l10n_es.dart` holds BOTH `es` and `es_AR` override classes — keys must be
added in BOTH override blocks within that file, ~lines 1392-region and
3181-region). Run the standard codegen (`flutter gen-l10n` / build) — do NOT
hand-edit `app_l10n.dart` beyond what codegen produces.

New keys (camelCase `routineEditorNotes*` to match the existing
`routineEditor*` family at intl_es_AR.arb:655):

| Key | es / es_AR | en | Where used |
|-----|------------|----|------------|
| `routineEditorNotesLabel` | `Nota para el alumno` | `Note for athlete` | TextFormField `labelText` (§3.4) |
| `routineEditorNotesHint` | `Técnica, tempo, RIR…` | `Technique, tempo, RIR…` | TextFormField `hintText` (§3.4) |

A dedicated player section caption is NOT needed — the note renders inline under
the exercise name without a label (§4.2), so the visual distinction (italic +
muted, no ⓘ affordance) carries the meaning without extra copy. If usability
review later wants a "Del coach" / "From coach" tag, add
`sessionPlayerCoachNoteCaption` then — explicitly OUT of scope now to keep copy
minimal.

arb entries follow the existing stub style — add the `@key: {}` metadata stub
after each key (the `intl_es.arb` / `intl_es_AR.arb` files use bare `@key: {}`;
`intl_en.arb` carries the description). Mirror the existing convention per file.

## 7. Visual differentiation from `techniqueInstructions` ⓘ (locked requirement)

The catalog technique lives behind the ⓘ `TreinoIcon.infoCircle` button
(session_player line 1334) and opens a `TechniqueSheet` modal — it is a tappable
affordance for SHARED catalog content. The PF note is PLAN-SPECIFIC and must read
differently:

| Dimension | Catalog technique (`techniqueInstructions`) | PF note (`slot.notes`) |
|-----------|---------------------------------------------|------------------------|
| Trigger | ⓘ icon → modal bottom sheet (opt-in) | Always-inline text (no tap) |
| Placement | Behind icon in header row | Sub-caption directly under name |
| Style | Sheet body text | Muted **italic**, 13px, inline |
| Source meaning | Generic, exercise catalog | This coach, this plan |

The note is NEVER inside the technique sheet and NEVER behind an icon. Inline
italic-muted is the agreed visual signal. They can coexist (note inline + ⓘ in
header) without confusion because one is passive text and the other an explicit
affordance. No new color token — reuse `palette.textMuted` + `FontStyle.italic`
(no hex; AGENTS.md compliant).

## 8. Test plan (strict TDD: RED → GREEN)

Test runner: `flutter test`. Gate: `flutter analyze` 0 issues + `dart format .` +
all tests green. Each item below is a failing test FIRST.

| # | Test | File (existing harness) | Asserts |
|---|------|-------------------------|---------|
| T1 | Emit round-trip | `routine_editor_set_table_test.dart` (extend, uses `buildSlotBridge`) | `buildSlotBridge(notes: 'tempo 3-1-1')` → returned `RoutineSlot.notes == 'tempo 3-1-1'` |
| T2 | Empty→null normalization | same | `buildSlotBridge(notes: '')` and `'   '` → `RoutineSlot.notes == null` |
| T3 | Hydration round-trip (THE bug fix) | `routine_editor_trainer_edit_test.dart` (extend) | Load routine whose slot has `notes:'x'` → save again → saved slot still `notes:'x'` (would FAIL pre-fix because §3.3 missing) |
| T4 | Trainer-only gating | `routine_editor_athlete_mode_test.dart` (extend, `_pumpEditor(mode:)`) | `find.byKey(Key('slot_notes_field'))` present in `TrainerAssigning` + `TrainerTemplating`; absent in `SelfCreating` |
| T5 | 200-char hard cap | editor widget test or bridge | Typing 201 chars stops at 200 (`maxLengthEnforcement.enforced`) |
| T6 | Player current-block display | `session_player_*_test.dart` (locate existing) | Current block with `notes` non-empty renders the text; `_CompletedBlockSummary` / `_FutureBlockPreview` do NOT |
| T7 | Player empty→nothing | same | `notes == null` / `''` → no note `Text` in `_ExerciseSection` |
| T8 | Routine-detail display | `exercise_slot_row` widget test (locate/create) | `ExerciseSlotRow` with `notes` non-empty renders text; null → nothing |
| T9 | Legacy-null safety | T2/T7/T8 cover it | A slot from a legacy doc (`notes == null`) renders nothing and survives hydrate→save without error |

T1–T3 are unit-level via the bridge / repository mock (fast, no widget pump).
T4–T8 are widget tests using the existing `_pumpEditor` and session-player pump
harnesses. T3 is the regression lock for the §9-R1 data-loss bug — it must be
RED before §3.3 lands.

## 9. Sequencing & risks

- **R1 — Latent DATA-LOSS (highest).** §3.2 emit + §3.3 hydrate are two halves of
  one invariant. Shipping emit without hydrate strips notes on the next
  open→save. Shipping hydrate without emit is a no-op. They MUST land in the same
  work unit, locked by test T3 (RED first). `sdd-tasks` must keep §3.1/§3.2/§3.3
  in ONE task, not split them.
- **R2 — Plumbing reaches two call sites.** §3.5: `_SlotEditor` is built at lines
  2170 AND 2473. Both must receive `isTrainerMode`. The default `false` is the
  safety net — a missed site hides the field (fail-closed), caught by T4 on the
  superset path if a superset-mode test exists. `sdd-tasks` should verify both
  call sites compile-pass the flag.
- **R3 — Visual ambiguity vs ⓘ technique.** Resolved by §7: inline italic-muted
  note vs icon→sheet technique. No code coupling; just styling discipline.
- **R4 — Counter behavior.** Locked decision asked for focus-conditional counter;
  Flutter lacks a zero-cost way. Chosen: `counterText: ''` (hidden) + hard
  enforcement. Documented as an accepted deviation; focus-aware counter is OUT of
  scope.
- **const / perf.** All inserted spacers are `const SizedBox`. The note `Text`
  cannot be `const` (interpolates `slot.notes`). The `if (...) ...[]` collection-if
  adds zero widgets when the note is empty — no perf regression on the hot session
  path. `ExerciseSlotRow` stays `StatelessWidget`; `_ExerciseSection` stays as-is.
- **NOT a risk:** dual-editor sync. One editor (proposal correction, authoritative).

## 10. ADR-style decisions

- **ADR-EN-01 — No new domain field; wire `RoutineSlot.notes`.** Rejected:
  introducing a structured `CoachNote` value object or per-set notes. Rationale:
  field exists, requirement is one free-text cue per exercise; structure is
  premature (YAGNI). Persistence/rules already cover `days[]`.
- **ADR-EN-02 — Gate input on `_isTrainerMode`, thread via constructor bool.**
  Rejected: InheritedWidget / provider for the flag. Rationale: one boolean, two
  call sites, shallow tree — a constructor param (default false, fail-closed) is
  the smallest correct mechanism. Mirrors existing trainer-only gating at
  lines 706/1657/1689.
- **ADR-EN-03 — Note placement: inline sub-caption, not behind an affordance.**
  Rejected: a second ⓘ-style icon/sheet for the note. Rationale: the note is
  short, plan-specific, and must be seen at execution time without a tap;
  hiding it behind a sheet would bury coaching intent. Inline italic-muted also
  gives the §7 visual distinction for free.
- **ADR-EN-04 — Hydrate unconditionally; gate only the input.** Rejected:
  hydrating only in trainer modes. Rationale: data retention is mode-independent;
  an athlete editing a coach-assigned plan must not strip the coach's note. Gating
  is purely a write-affordance / display concern.
- **ADR-EN-05 — Hidden counter + hard 200 cap.** Rejected: always-on `n/200`
  counter; custom focus-aware counter widget. Rationale: hard enforcement gives
  the guarantee; a permanent counter clutters the card; focus-aware counter is
  unjustified complexity for a 200-char field.

## 11. Verified anchors (re-checked 2026-06-29)

| Anchor | Verified line |
|--------|--------------|
| `RoutineSlot.notes` field | routine_slot.dart:46 |
| `_EditableSlot` class / ctor | routine_editor_screen.dart:115 / 156 |
| `buildRoutineSlot` return | routine_editor_screen.dart:293 |
| `_loadExistingRoutine` slot cascade end | routine_editor_screen.dart:542 |
| `_isTrainerMode` getter | routine_editor_screen.dart:662 |
| `_DayExpansionTile` call site / ctor | routine_editor_screen.dart:1767 / 2097 |
| `_SlotEditor` call sites | routine_editor_screen.dart:2170, 2473 |
| `_SlotEditor` ctor | routine_editor_screen.dart:2574 |
| `_SlotEditorState.build` (rest row→set table seam) | routine_editor_screen.dart:2629 (insert ~2765) |
| `buildSlotBridge` | routine_editor_screen.dart:3507 |
| `_ExerciseSection` header row close | session_player_screen.dart:1365 |
| `BlockStatus` dispatch (current-only proof) | session_player_screen.dart:746-768 |
| `ExerciseSlotRow.build` rest-row close | exercise_slot_row.dart:255 |
| l10n family anchor | intl_es_AR.arb:655 ; app_l10n_es.dart:1392 & 3181 |

Next: `sdd-tasks` (after spec is ready). Slice §3 (write trio = one task incl.
R1), §3.5 plumbing, §3.6 bridge, §4 player, §5 detail, §6 l10n, §8 tests.

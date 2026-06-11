# SDD Design: Per-week exercise presence (`periodization-week-presence`)

Architecture-level HOW for Option A (per-week presence mask). Reads proposal #228 /
`openspec/changes/periodization-week-presence/proposal.md`. Builds on shipped
periodization Model B (#214-220). Branch `feat/periodization-week-presence`.

## Approach (one sentence)

Add an additive `RoutineSlot.activeWeeks: List<int>` presence mask (empty = present
in all weeks) that is resolved at exactly THREE consumer boundaries (detail render,
session-state construction in the notifier, plan-progress derivation) plus authored
in the editor, with `numWeeks == 1` short-circuiting every branch so the single-week
path stays byte-identical.

## Architectural principle: single resolution boundary per consumer

`activeWeeks` is presence; `weeklySets` is prescription. They are ORTHOGONAL and must
never be conflated. `effectiveSetsForWeek(w)` answers "what sets for week w" and stays
untouched. The new getter `isActiveInWeek(w)` answers "does this slot exist in week w".

Resolution is `day.slots.where((s) => s.isActiveInWeek(w))`. The design forces this
filter to live at as FEW points as possible so block-building, gating, and rendering
all see a consistent slot list. The chosen points:

| Consumer | Where the filter lives | Why |
| --- | --- | --- |
| Athlete detail | `_buildExerciseList(viewedWeek)` in `routine_detail_screen.dart` | View is week-driven; filter the flat list before block grouping |
| Player | `SessionState.day` construction in `session_notifier.dart` (`_buildFresh`/`_buildResume`) | ONE upstream filter → `buildBlocks`, `computeBlockStatuses`, `isFullyCompleted`, `_nextIncompleteIndex` all consume the already-filtered day |
| Gating / progress | `derivePlanProgress` gains a per-week required-days map | A day with zero present slots in week w must auto-satisfy without a session |
| Editor authoring | `_EditableSlot.activeWeeks` set + delete/add dialogs + `_isValid` + `buildRoutineSlot` | Source of truth while editing |

---

## 1. Domain — `RoutineSlot`

File: `lib/features/workout/domain/routine_slot.dart`.

### Field

Add as the last factory parameter, after `weeklySets` (L81):

```dart
/// Periodization presence MASK (Option A). 0-based week indices in which
/// this slot is PRESENT. Empty = present in ALL weeks (hard back-compat:
/// every legacy/single-week doc has no field → empty → present everywhere).
/// ORTHOGONAL to [weeklySets] (prescription). A flat List<int> — Firestore
/// stores it natively, NO converter needed (mirrors [targetReps]).
@Default(<int>[]) List<int> activeWeeks,
```

- **Type**: `List<int>` (0-based). Same shape as the already-serializing `targetReps`
  (L50) — `json_serializable` round-trips `List<int>` natively; Firestore stores a
  flat array of numbers with no nested-array problem. **No `@JsonConverter`** (unlike
  `weeklySets`, which needs `WeeklySetsConverter` ONLY because nested arrays are
  unpersistable).
- **Default**: `@Default(<int>[])` → empty → present in all weeks → zero migration.
- **Position**: last param keeps the freezed constructor diff minimal.

### Getter

Add to the derived getters section (after `effectiveSetsForWeek`, L149):

```dart
/// Whether this slot is present in 0-based [week]. Empty mask = present in
/// ALL weeks (back-compat). A negative or out-of-range [week] is treated by
/// the membership test directly: an empty mask is always true; a non-empty
/// mask returns whether [week] is listed. Never throws.
bool isActiveInWeek(int week) =>
    activeWeeks.isEmpty || activeWeeks.contains(week);
```

Semantics table (ADR-WPRES-01):

| `activeWeeks` | `isActiveInWeek(0)` | `isActiveInWeek(2)` | `isActiveInWeek(-1)` |
| --- | --- | --- | --- |
| `[]` (empty) | true | true | true |
| `[0,1]` | true | false | false |
| `[2]` | false | true | false |

Out-of-range week falls out of `contains` → false for a non-empty mask, true for empty.
That is the desired "vacío = todas, fuera de rango = ausente" semantics.

### Interaction with existing getters

`effectiveSetsForWeek(w)` and `weeklySets` are NOT touched. A slot can be absent in
week 2 (`activeWeeks` excludes 2) yet still hold a `weeklySets[2]` prescription — the
presence filter runs BEFORE any prescription read, so the orphan prescription is never
consulted. No coupling, no cleanup needed. This is deliberate: keeping them independent
means `_removeLastWeek` / index shifts only have to touch the mask, never the
prescription-resolution path.

### Wire / build_runner

- Regenerate `routine_slot.g.dart` + `routine_slot.freezed.dart` via
  `dart run build_runner build --delete-conflicting-outputs`. Generated files are
  COMMITTED (project convention).
- Repository (`routine_repository.dart`) needs NO change: the slot rides inside
  `days[].slots[]` via `RoutineDay.toJson` → `RoutineSlot.toJson`, which
  `json_serializable` now emits with the `activeWeeks` key automatically.

---

## 2. Editor — `routine_editor_screen.dart`

### 2.1 `_EditableSlot` presence (L108)

Add a mutable mask field:

```dart
/// 0-based weeks in which this slot is present. Empty = all weeks
/// (back-compat). Mirrors RoutineSlot.activeWeeks. Source of truth while
/// editing; index space is the SAME as weeklySets' outer index.
Set<int> activeWeeks = <int>{};
```

Use a `Set<int>` in-editor (cheap membership + add/remove, no dup), convert to a sorted
`List<int>` at `buildRoutineSlot`. The mask indexes the SAME 0-based week space as
`weeklySets` — every week operation that resizes `weeklySets` must keep the mask
consistent (see 2.4).

Add an in-editor presence helper mirroring the domain getter so the per-week UI can
ask "is this slot shown this week":

```dart
bool isPresentInWeek(int w) => activeWeeks.isEmpty || activeWeeks.contains(w);
```

### 2.2 DELETE — branch on `_numWeeks > 1`

Today the ⋮ menu "Eliminar" (L1937, `_SlotAction.remove`) calls `widget.onRemove()` →
`onRemoveSlot(idx)` → `_removeSlot(dayIndex, slotIndex)` (L563), which is a STRUCTURAL
removal (drops the slot from `day.slots` for the whole plan). This is the only delete
callsite.

New behavior (ADR-WPRES-02): the delete action routes through a new handler
`_onDeleteSlot(dayIndex, slotIndex)`:

- **`_numWeeks == 1`** → call `_removeSlot` directly (today's structural delete). No
  dialog. HARD INVARIANT: single-week editor unchanged.
- **`_numWeeks > 1`** → show a dialog (AppPalette + TreinoIcon) with two choices:
  - **"Quitar de esta semana"** (`_selectedWeek` only): set the slot's mask to "all
    weeks except `_selectedWeek`". Concretely, if mask is empty (= all), materialize
    it to `{0..numWeeks-1} \ {_selectedWeek}`; if non-empty, `mask.remove(_selectedWeek)`.
    THEN: if the resulting mask is empty (slot would be present in NO week → forbidden
    ghost, ADR-WPRES-03), route to a structural delete instead (`_removeSlot`). This is
    the "only-this-week delete on a slot present in just that week → all-weeks delete"
    rule from the proposal.
  - **"Eliminar de todas las semanas"** → `_removeSlot` (structural).

The dialog wiring threads `_selectedWeek` and `_numWeeks` down. The `_SlotEditor.onRemove`
callback signature stays `VoidCallback`; the screen-level handler reads
`_selectedWeek`/`_numWeeks` from state, so no extra plumbing into `_SlotEditor`.

### 2.3 ADD with scope

Slots are added in three places, all seeding `weeklySets = List.generate(_numWeeks, ...)`:
`_pickExercisesForDay` (L606), `_addSupersetForDay` (L630), `_addExerciseToGroup` (L659).

New behavior (ADR-WPRES-04):

- **`_numWeeks == 1`** → add with empty mask (present everywhere). Unchanged.
- **`_numWeeks > 1` AND `_selectedWeek > 0`** → after picking exercises, show a scope
  dialog: **"Agregar solo en esta semana"** (mask `{_selectedWeek}`) vs **"Agregar en
  todas las semanas"** (empty mask). When `_selectedWeek == 0` we keep the default
  empty mask (adding on week 1 implies the slot is a base movement); a coach who wants
  week-0-only can later use delete-this-week on the other weeks. This avoids a dialog on
  the most common add path.

New slots set `..activeWeeks = <int>{}` (all) or `..activeWeeks = {_selectedWeek}`
(this-week) accordingly. The scope prompt is shared across the three add paths via a
small `Future<_AddScope?> _promptAddScope()` helper returning all/this-week/cancel.

### 2.4 Week operations vs the mask — INDEX SHIFT (the dangerous part)

The mask indexes the same 0-based space as `weeklySets`. Each operation:

- **`_addWeek` (L495)**: appends week `_numWeeks` (new highest index). A slot with an
  EMPTY mask stays empty (= still all weeks, now including the new one). A slot with a
  NON-EMPTY mask: the new week is NOT added to the mask (a periodized slot does not
  silently appear in the freshly added empty week — consistent with `_addWeek` adding
  an EMPTY prescription week, ADR-PB-04). So `_addWeek` does NOT touch masks.
  - Preserve the `FocusManager.instance.primaryFocus?.unfocus()` (L497) IME fix.
- **`_removeLastWeek` (L511)**: drops the highest index `_numWeeks-1`. Every mask must
  drop that index if present: `slot.activeWeeks.remove(_numWeeks - 1)` for each slot
  (computed BEFORE decrementing `_numWeeks`). No lower index shifts because only the
  LAST week is removed — indices below it are stable. Edge: if removing the last week
  empties a non-empty mask (slot was present ONLY in the removed week), the mask becomes
  empty → "present in all remaining weeks". That is acceptable and matches the
  empty=all invariant; the slot reappears everywhere rather than becoming a ghost.
  This is documented in ADR-WPRES-05 as a deliberate non-ghost fallback.
  - Preserve the `unfocus()` IME fix (L513).
- **`_duplicateWeek` (L530)**: copies prescription from `_selectedWeek - 1` into
  `_selectedWeek`. Presence MUST be copied too (ADR-WPRES-06): the slot is present in
  the duplicated week iff it is present in the source week. Implementation: for each
  slot, set membership of `_selectedWeek` to match `_selectedWeek - 1`:
  `if (slot.isPresentInWeek(_selectedWeek - 1)) materializeAndAdd(_selectedWeek) else mask.remove(_selectedWeek)`.
  Care: "present in source" for an EMPTY mask is true → duplicate keeps the slot empty
  (still all weeks) — no materialization needed in that case. Only materialize when the
  source mask is non-empty and the membership differs.
  - Preserve the `unfocus()` IME fix (L532).

> CRITICAL: because only `_removeLastWeek` removes a week and it always removes the
> HIGHEST index, there is NO general "shift all indices > removed" case. The mask never
> needs a full reindex. If a future change adds "remove arbitrary middle week", the mask
> WOULD need `mask = {for (w in mask) w > removed ? w-1 : w}` — out of scope here, flagged.

### 2.5 Validation — `_isValid` / zero-presence

`_isValid` (L469) + `_invalidWeekFirstDay` (L452) currently validate that every week of
every slot has ≥1 valid set. Add a zero-presence guard (ADR-WPRES-03):

- A slot whose mask is non-empty and EXCLUDES every week (impossible to reach via UI
  but defensively rejected) → invalid.
- A DAY that has ≥1 slot but where, FOR SOME WEEK, NO slot is present → this is the
  empty-day case. It is NOT a validation error (it is auto-satisfied gating, see §3).
  But a SUPERSET group that APPEARS in a week must have ≥1 present member that week
  (ADR-WPRES-08) — covered structurally because a single remaining present member
  renders as a normal exercise; we additionally assert in `_isValid` that no slot ends
  with an all-excluding mask.

Concretely: extend the slot loop in `_isValid` to also reject
`slot.activeWeeks.isNotEmpty && slot.activeWeeks.every((w) => w < 0 || w >= _numWeeks)`
(mask references no in-range week). Set-based authoring can't normally produce this, but
hydration from a hand-edited doc could.

### 2.6 Hydration — `_loadExistingRoutine` (L365)

In the slot mapping (L391-418), after setting `weeklySets`, hydrate the mask:

```dart
..activeWeeks = slot.activeWeeks.toSet()
```

Legacy docs have empty `activeWeeks` → empty set → all weeks. Defensive clamp: after
`_normalizeSlotWeeks`, drop any mask index `>= _numWeeks` so a doc whose mask disagrees
with `numWeeks` can't carry a dangling index (mirrors the existing weeklySets
normalization at L349). Add to `_normalizeSlotWeeks`:
`slot.activeWeeks.removeWhere((w) => w < 0 || w >= _numWeeks);`

### 2.7 Save — `buildRoutineSlot` (L190)

Add the mask to the returned `RoutineSlot`:

```dart
activeWeeks: (s.activeWeeks.toList()..sort()),
```

Sorted for deterministic wire output (stable diffs / rules `affectedKeys` no-noise).
Empty set → empty list → empty field → present everywhere. Single-week save: mask is
always empty (no delete-this-week path reachable), so `activeWeeks: []` — the
single-week doc is byte-identical to today plus an empty array (which is the default,
so even re-reads are stable). Extend `RoutineEditorTestBridge.buildSlotBridge` /
`buildSlotBridgeWeekly` to accept an optional `activeWeeks` param for unit coverage.

---

## 3. Athlete consumers

### 3.1 Detail — `routine_detail_screen.dart`

`_buildExerciseList(int viewedWeek)` (L175) walks `day.slots` to build standalone rows
and `_SupersetBlock`s. Insert the presence filter at the TOP (ADR-WPRES-07):

```dart
final slots = [
  for (final s in day.slots) if (s.isActiveInWeek(viewedWeek)) s
];
```

Then the existing superset-grouping loop runs over the filtered list. Because filtering
happens before grouping:

- A superset member absent this week simply isn't in `slots`; the run-length check
  (`items.length >= 2`, L188) naturally renders a 1-member group as a standalone row
  (existing behavior for run length < 2). No orphan badge. (ADR-WPRES-08)
- `_totalSets` / `EJERCICIOS` stat (L158, L241) still count `day.slots` (all weeks).
  Decision: the stat header keeps showing the structural total; the per-week EXERCISES
  count in the list reflects presence. To keep the stat honest per week we change
  `StatTile EJERCICIOS` to count the filtered slots for `viewedWeek` (cheap, and matches
  what the athlete sees below). `SETS` stat likewise sums over the filtered slots using
  `effectiveSetsForWeek(viewedWeek).length`. For `numWeeks == 1`, `viewedWeek == 0` and
  empty masks → identical to today.

- **Empty day in this week** (all slots absent): `day.slots` filtered is empty → the
  existing `if (day.slots.isEmpty)` guard (L272) checks the UNFILTERED list, so add a
  parallel check on the filtered list and render an info message
  **"Sin ejercicios esta semana"** (info, NOT a lock). The CTA bar must treat this day
  as auto-satisfied (see §3.3).

`_WeekSelector` (L637) is unchanged — selecting a week drives `viewedWeek`, which now
also drives presence. `ExerciseSlotRow` already takes `week` (L18) for prescription; no
change there.

### 3.2 Player — filter in the NOTIFIER, not the render (decision + justification)

DECISION (ADR-WPRES-09): filter at `SessionState.day` construction in
`session_notifier.dart`, NOT in the player render.

Rationale: `SessionState.day` (a `RoutineDay`) is consumed by FOUR independent code
paths — `buildBlocks(state.day.slots)` (L244 player), `isFullyCompleted` (session_state
L36), `_nextIncompleteIndex` (notifier L281), and `completedExerciseCount`
(session_state L59). If we filtered only in the render (`_buildExerciseList`), then
`isFullyCompleted` would still require logging the ABSENT slot's sets → the player could
never reach "fully completed" for a week where a slot is absent → TERMINAR stays
disabled forever. Filtering once upstream makes all four consumers see exactly the
present slots, so completion math, next-index, and block status are automatically
correct.

Implementation: in `_buildFresh` (L56) and `_buildResume` (L124), after resolving
`day = routine.days.firstWhere(...)`, build a presence-filtered day for the session's
week:

```dart
final presentSlots = [
  for (final s in day.slots) if (s.isActiveInWeek(clampedWeek)) s
];
final sessionDay = day.copyWith(slots: presentSlots);
```

(`clampedWeek` in `_buildFresh`; `session.weekNumber` in `_buildResume`.) Pass
`sessionDay` to `SessionState(day: ...)`. `RoutineDay` is freezed → `copyWith` exists.
For `numWeeks == 1` the session week is 0 and masks are empty → `presentSlots ==
day.slots` → identical session to today. SetLogs key on `exerciseId`, so an absent slot
contributes no logs and no required count — consistent.

Edge: a session started for a (week, day) where the filtered day has ZERO slots should
never be reachable, because the detail CTA auto-satisfies that day and shows
"Sin ejercicios esta semana" instead of EMPTY (§3.1 + §3.3). Defensive: if a
hand-crafted URL starts such a session, `isFullyCompleted` over an empty slot list is
vacuously true (`.every` on empty = true) → TERMINAR is immediately enabled → the
athlete finishes a no-op session. Acceptable and non-corrupting.

### 3.3 Gating / progress — `derivePlanProgress` needs per-week required days

This is the subtle one. Gating today (`plan_gating.dart`, `plan_progress.dart`) assumes
EVERY day in `dayNumbers` is required in EVERY week. With presence, a day can be
ALL-ABSENT in a given week (every slot in that day excluded from week w) → no session
will ever be created for (w, day) → `completed` never contains (w, day) → `isWeekUnlocked`
for w+1 deadlocks, and `derivePlanProgress` parks `activeWeek` forever. (Risk #3.)

DECISION (ADR-WPRES-10): a (week, day) with ZERO present slots is AUTO-SATISFIED — it is
treated as required-and-already-done without any session. To compute this without a
session, `derivePlanProgress` and the gating functions must know, PER WEEK, which days
actually REQUIRE work.

Change the data flowing into the pure functions. The pure layer must stay Flutter-free,
so we pass a precomputed structure rather than the routine:

- New type in `plan_progress.dart`:
  `typedef RequiredDays = Set<CompletedKey>;` — the set of (week, day) pairs that have
  ≥1 present slot (i.e. actually require a completed session).
- `planProgressProvider` (`session_providers.dart` L92) computes it from the routine:

  ```dart
  final required = <({int week, int day})>{};
  for (var w = 0; w < routine.numWeeks; w++) {
    for (final d in routine.days) {
      final hasPresent = d.slots.any((s) => s.isActiveInWeek(w));
      if (hasPresent) required.add((week: w, day: d.dayNumber));
    }
  }
  ```

- `derivePlanProgress(completed, dayNumbers, numWeeks, required)` gains a `required`
  param. A (w, day) is "satisfied" iff `completed.contains((w,day)) || !required.contains((w,day))`.
  The active-week/active-day scan and `planComplete` use SATISFIED instead of raw
  `completed.contains`. Empty-day combos are satisfied automatically.
- `isWeekUnlocked` / `isDayUnlocked` / `isStartable` (`plan_gating.dart`) likewise gain
  a `required` param and replace `completed.contains((w,d))` with the satisfied test.
  An all-absent day never blocks the next day or week.

Back-compat: with all-empty masks, `required` = the full `numWeeks × dayNumbers` grid →
`!required.contains` is always false → behavior identical to today. For `numWeeks == 1`
the detail screen still BYPASSES gating entirely (HARD INVARIANT, L216 `isPeriodized`),
so the new param only matters for periodized plans. The detail `_PeriodizedCTABar`
(L686) must pass `required` into `isWeekUnlocked`/`isDayUnlocked`. The empty-day branch
in §3.1 ("Sin ejercicios esta semana") relies on this: such a day is satisfied, so its
CTA shows neither LOCK nor EMPEZAR — it shows an info/auto-done affordance.

> Justification for putting `required` in the pure layer rather than the provider doing
> the filtering: gating decisions (is w+1 unlocked) are CROSS-day and CROSS-week; they
> need the full required-grid, not just the current day. Keeping the pure functions
> total over (completed, required) keeps them exhaustively unit-testable (the existing
> SCENARIO-030..036 truth tables extend with required-grid cases) and Flutter-free.

---

## 4. Supersets

Already resolved by the §3.1 / §3.2 filtering happening BEFORE block grouping:

- Detail `_buildExerciseList`: filter → grouping loop → a group reduced to 1 present
  member hits `items.length >= 2` == false → renders as standalone `ExerciseSlotRow`.
  No orphan, no "superset of one". (ADR-WPRES-08)
- Player `buildBlocks(state.day.slots)` (session_providers L57): receives the
  already-filtered day from the notifier → a group reduced to 1 present member hits
  `members.length >= 2` == false → falls back to a standalone block (L75). So
  `computeBlockStatuses`, round-robin set counting (L944-956), and completion never see
  the absent member. NO change to `buildBlocks` itself.
- Validation (§2.5): a superset group that APPEARS in week w must keep ≥1 present
  member; structurally guaranteed because removing the last present member of a group in
  a week routes to the empty-day path, not a broken block.

So supersets need ZERO new filtering code — they inherit the single upstream filter.

---

## 5. Firestore rules

VERIFIED (not assumed): `activeWeeks` rides INSIDE `days[].slots[]`. It is NOT a
top-level routine key. Every UPDATE path (paths 2/3/4, `firestore.rules`
L135-242) guards top-level keys via:

- `request.resource.data.keys().hasOnly([... 'days' ...])` — `activeWeeks` is not a
  top-level key, so it does not need to be added to any `hasOnly` list.
- `affectedKeys().hasOnly(['name', 'level'/'split', 'days', 'numWeeks'])` — editing a
  slot's presence changes the `days` blob → `days` is in `affectedKeys` → already
  allowed.

CONCLUSION: NO rules change required. But the proposal mandates VERIFY-don't-assume, so
the design SPECIFIES a regression test in the existing harness
(`scripts/rules_test/rules.test.js`, run with the emulator, JDK 21):

- **Test WPRES-RULES-01**: owner updates their `user-created` routine, mutating only
  `days` (a slot gains `activeWeeks: [0]`) + `numWeeks` → must ALLOW. Proves a
  nested `activeWeeks` write passes the `hasOnly`/`affectedKeys` guards.
- **Test WPRES-RULES-02 (negative control)**: same update but ALSO adds a bogus
  top-level key → must DENY. Proves the guard still bites and we didn't loosen anything.
- Mirror WPRES-RULES-01 for the trainer-assigned path (path 3) to cover both editor
  modes.

If — and only if — the emulator shows a DENY on WPRES-RULES-01, the design's fallback is
NOT to add `activeWeeks` to `hasOnly` (it isn't top-level) but to investigate whether a
serializer emitted it at top level by mistake; rules stay unchanged otherwise.

---

## ADR-style decisions

- **ADR-WPRES-01 — `isActiveInWeek` empty=all semantics.** Empty mask = present in all
  weeks; non-empty mask = membership test; out-of-range/negative week = false for a
  non-empty mask. Rationale: zero migration, all legacy docs present everywhere.
  Rejected: nullable `List<int>?` (adds null-vs-empty ambiguity); a `presentInAllWeeks`
  bool flag (redundant with empty list, two sources of truth).

- **ADR-WPRES-02 — Delete branches on `_numWeeks > 1` via a screen-level handler.**
  Single-week → structural delete, no dialog (HARD INVARIANT). Multi-week → dialog with
  this-week vs all-weeks. Rejected: always show the dialog (regresses the single-week UX
  and breaks byte-identical guarantee); per-slot delete-mode toggle (more state, worse
  discoverability).

- **ADR-WPRES-03 — Zero-presence is FORBIDDEN; this-week-delete on a last-present-week
  slot routes to structural delete.** A non-empty mask that excludes every week is a
  ghost slot (renders nowhere, can't be edited). `_isValid` rejects it; the delete
  handler converts "remove last present week" into a full structural delete. Rejected:
  allowing zero-presence (creates invisible undeletable slots).

- **ADR-WPRES-04 — Add scope dialog only when `_numWeeks > 1 && _selectedWeek > 0`.**
  Week-0 add defaults to all-weeks (base movement); later weeks prompt this-week vs
  all-weeks. Rejected: always prompt (annoying on the common path); never prompt
  (no way to author a week-specific addition).

- **ADR-WPRES-05 — `_removeLastWeek` drops the highest mask index; emptied mask falls
  back to all-weeks.** Only the last week is removable, so no general reindex is needed.
  If the removed week was a slot's only present week, the mask empties → slot reappears
  in all remaining weeks (non-ghost fallback) rather than vanishing. Rejected:
  structurally deleting such slots on week removal (surprising data loss).

- **ADR-WPRES-06 — `_duplicateWeek` copies presence.** Presence is structural; the
  duplicated week mirrors the source week's membership. Rejected: copy prescription only
  (the duplicated week would show different exercises than the source — violates "exact
  copy" intent of REQ-PERIOD-014).

- **ADR-WPRES-07 — Detail filters `day.slots` before superset grouping.** One filter at
  the top of `_buildExerciseList`; grouping and stats consume the filtered list.
  Rejected: filter inside the grouping loop (duplicated logic, easy to desync block math
  from stats).

- **ADR-WPRES-08 — Absent superset member drops from that week; 1 remaining renders as
  normal exercise.** Inherited from the run-length `>= 2` check in both detail and
  player block builders — no new code, no orphan badge. Rejected: keeping a 1-member
  "superset" wrapper (visually wrong).

- **ADR-WPRES-09 — Player filters at `SessionState.day` construction in the notifier,
  NOT in the render.** A single upstream filter keeps `buildBlocks`, `isFullyCompleted`,
  `_nextIncompleteIndex`, and `completedExerciseCount` mutually consistent; render-only
  filtering would leave completion math requiring absent slots → TERMINAR never enables.
  Rejected: filter in `_buildExerciseList` render (completion deadlock).

- **ADR-WPRES-10 — Empty-day (zero present slots in a week) is AUTO-SATISFIED via a
  per-week `required` grid threaded into the pure gating/progress functions.** Keeps the
  pure layer Flutter-free and totally testable; cross-week unlock decisions need the full
  required grid. Rejected: synthesizing a fake completed session for empty days (pollutes
  session history, breaks analytics); filtering in the provider only (gating is cross-day
  so the current-day view is insufficient).

---

## Risks (with mitigation)

1. **Mask/`weeklySets` index desync on week ops** [Med] → only `_removeLastWeek` removes
   a week and always the highest index; documented no-reindex invariant + defensive
   `removeWhere(w >= _numWeeks)` in `_normalizeSlotWeeks`. Unit-test add/remove/duplicate
   against the mask.
2. **Gating deadlock on empty week/day** [Med] → `required`-grid auto-satisfaction in
   `derivePlanProgress` + gating fns; extend the SCENARIO-030..036 truth tables with
   empty-day cases.
3. **Player completion deadlock** [Med] → upstream filter in the notifier (ADR-WPRES-09);
   widget/unit test that a week missing a slot reaches `isFullyCompleted == true`.
4. **Rules reject nested `activeWeeks`** [Low] → emulator regression tests
   WPRES-RULES-01/02; design predicts ALLOW because `days` already covers it.
5. **Single-week regression** [Low] → every branch short-circuits on `_numWeeks == 1` /
   `viewedWeek == 0` / empty mask; assert byte-identical save (`activeWeeks: []`).
6. **IME unfocus fix broken by week-op edits** [Low] → explicitly preserve the
   `FocusManager...unfocus()` calls at L497/L513/L532 when adding mask handling inside
   `_addWeek`/`_removeLastWeek`/`_duplicateWeek`.
7. **Stat header drift (EJERCICIOS/SETS counting all weeks)** [Low] → recompute both
   stats over the presence-filtered slots for `viewedWeek` so the header matches the
   list.
8. **Duplicate-detection on add** [Low] → existing `existingIds` dedup is per-day across
   ALL weeks; a slot absent this week but present elsewhere still blocks re-adding the
   same exercise. Acceptable (one instance per day); flagged so apply doesn't "fix" it.

## Assumptions requiring validation

- `RoutineDay` is freezed with a working `copyWith(slots:)` (used in §3.2). Confirm
  during apply; if not freezed, construct a new `RoutineDay` explicitly.
- `derivePlanProgress` / gating fns are only called from `planProgressProvider` and
  `_PeriodizedCTABar`; the new `required` param has no other callers to update besides
  tests. Verify via grep during apply.

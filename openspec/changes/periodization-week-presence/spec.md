# Delta Spec: periodization-week-presence

Change: `periodization-week-presence`
Artifact store: hybrid
Builds on: `periodization-model-b` (REQ-PERIOD-001 … REQ-PERIOD-064, shipped).
This file describes WHAT must be true after the change — no implementation details.

---

## Requirement index

| ID | Area | Phase |
|---|---|---|
| REQ-WPRES-001 | Domain: RoutineSlot.activeWeeks field | 1 |
| REQ-WPRES-002 | Domain: isPresentInWeek getter | 1 |
| REQ-WPRES-003 | Domain: zero-presence forbidden | 1 |
| REQ-WPRES-004 | Serialization: List<int> round-trip | 1 |
| REQ-WPRES-005 | Rules: activeWeeks covered by existing days guard | 1 |
| REQ-WPRES-010 | Editor: delete dialog — multi-week plan | 2 |
| REQ-WPRES-011 | Editor: delete when slot present in one week only | 2 |
| REQ-WPRES-012 | Editor: add-exercise scope — week ≥ 2 | 2 |
| REQ-WPRES-013 | Editor: Duplicar-semana copies presence | 2 |
| REQ-WPRES-014 | Editor: validation guards zero-presence | 2 |
| REQ-WPRES-015 | Editor: numWeeks == 1 invariant — no dialog | 2 |
| REQ-WPRES-020 | Detail: filter slots by presence | 3 |
| REQ-WPRES-021 | Player: filter slots by presence | 3 |
| REQ-WPRES-022 | Gating: empty-day auto-satisfied | 3 |
| REQ-WPRES-023 | Supersets: absent member drops from week block | 3 |
| REQ-WPRES-030 | NFR: numWeeks == 1 hard invariant (no regression) | All |
| REQ-WPRES-031 | NFR: quality gate | All |

---

## ADDED Requirements

### REQ-WPRES-001 — RoutineSlot.activeWeeks field

`RoutineSlot` MUST have an `activeWeeks` field of type `List<int>` (0-based week indices), defaulting to `[]`.
`RoutineSlot` documents serialized without `activeWeeks` MUST deserialize as `activeWeeks = []`.
`[]` (empty) means the slot is present in ALL weeks; this is the backward-compatible default.
`[0, 2]` means present in weeks 0 and 2 only.

#### SCENARIO-WPRES-001 — Legacy doc deserializes with empty activeWeeks

- GIVEN a RoutineSlot document in Firestore written before this change (no `activeWeeks` field)
- WHEN the app deserializes it
- THEN `slot.activeWeeks == []`
- AND `slot.isPresentInWeek(0)` returns `true`

#### SCENARIO-WPRES-002 — Slot with explicit mask deserializes correctly

- GIVEN a RoutineSlot document with `activeWeeks: [0, 2]`
- WHEN the app deserializes it
- THEN `slot.activeWeeks == [0, 2]`

---

### REQ-WPRES-002 — isPresentInWeek getter

`RoutineSlot` MUST expose a `bool isPresentInWeek(int week)` getter with the rule:
`activeWeeks.isEmpty || activeWeeks.contains(week)`.
An empty mask MUST return `true` for any week index.
A non-empty mask MUST return `true` only for indices in the list.

#### SCENARIO-WPRES-003 — Empty mask → present in all weeks

- GIVEN a RoutineSlot with `activeWeeks == []`
- WHEN `isPresentInWeek` is called for week 0, 1, or 5
- THEN it returns `true` for each call

#### SCENARIO-WPRES-004 — Non-empty mask → present only in listed weeks

- GIVEN a RoutineSlot with `activeWeeks == [1, 3]`
- WHEN `isPresentInWeek(0)`, `isPresentInWeek(1)`, `isPresentInWeek(3)`, `isPresentInWeek(4)` are called
- THEN results are: false, true, true, false respectively

---

### REQ-WPRES-003 — Zero-presence is forbidden

A slot whose `activeWeeks` is non-empty AND excludes every week in `[0 .. numWeeks-1]` MUST NOT be persisted.
The editor MUST NOT allow this state: validation (`_isValid` or equivalent) MUST reject it.
An "only this week" delete that would leave the slot with zero active weeks MUST route to an all-weeks delete instead (structural removal).

#### SCENARIO-WPRES-005 — Validation rejects non-empty mask that excludes all weeks

- GIVEN a plan with `numWeeks == 3` and a slot with `activeWeeks == [5]`
- WHEN the editor validates the form
- THEN `_isValid` returns `false` and save is blocked

#### SCENARIO-WPRES-006 — Single-present-week delete routes to all-weeks delete

- GIVEN a plan with `numWeeks == 3` and a slot with `activeWeeks == [1]` (only week index 1)
- WHEN the coach chooses "only this week" delete while viewing week 1
- THEN the system performs an all-weeks (structural) delete instead, removing the slot entirely

---

### REQ-WPRES-004 — Serialization round-trip (List<int>)

`activeWeeks` MUST serialize as a JSON array of integers without any custom converter.
A round-trip (serialize → Firestore → deserialize) MUST produce a list deeply equal to the original.

#### SCENARIO-WPRES-007 — Round-trip with populated mask

- GIVEN a RoutineSlot with `activeWeeks == [0, 2]`
- WHEN it is serialized to JSON and deserialized back
- THEN `slot.activeWeeks == [0, 2]` (deeply equal, order preserved)

#### SCENARIO-WPRES-008 — Round-trip with empty mask

- GIVEN a RoutineSlot with `activeWeeks == []`
- WHEN it is serialized to JSON and deserialized back
- THEN `slot.activeWeeks == []`

---

### REQ-WPRES-005 — Firestore rules: activeWeeks covered by existing days guard

`activeWeeks` MUST serialize as a nested field within `days` (inside slot objects), not as a new top-level Routine field.
The existing Firestore rules `hasOnly` guard on `days` MUST cover `activeWeeks` writes without any rules modification.
A rules stub test MUST verify that a Routine update adding `activeWeeks` inside a slot is permitted.

#### SCENARIO-WPRES-009 — Rules allow writing activeWeeks (stub test)

- GIVEN a Firestore emulator with production rules and a user-owned Routine
- WHEN the owner sends an update that adds `activeWeeks` to a slot nested in `days`
- THEN the write is allowed (no permission-denied)

#### SCENARIO-WPRES-010 — activeWeeks is NOT a top-level field

- GIVEN a Routine update payload
- WHEN the payload is inspected
- THEN `activeWeeks` does not appear as a top-level key; it is nested under `days`

---

### REQ-WPRES-010 — Editor: delete dialog in multi-week plan

In a plan with `numWeeks > 1`, deleting an exercise slot MUST present a dialog with two options:
- "Only this week" — removes `_selectedWeek` from the slot's active weeks mask (materializing it to `[0..numWeeks-1]` minus the current week if it was empty)
- "All weeks" — structural removal (existing `_removeSlot` behavior)

When `numWeeks == 1`, NO dialog MUST be shown; the existing structural delete MUST execute immediately.

#### SCENARIO-WPRES-011 — Delete dialog shown in multi-week plan

- GIVEN a plan with `numWeeks == 3` and an exercise slot present in all weeks
- WHEN the coach deletes the exercise while viewing week 1
- THEN a dialog appears offering "only this week" and "all weeks"

#### SCENARIO-WPRES-012 — "Only this week" masks out current week

- GIVEN a plan with `numWeeks == 3`, slot with `activeWeeks == []` (all weeks), coach on week 1
- WHEN the coach selects "only this week"
- THEN `slot.activeWeeks == [0, 2]` (week 1 removed; mask materialized)
- AND the slot remains in the plan for weeks 0 and 2

#### SCENARIO-WPRES-013 — "All weeks" performs structural removal

- GIVEN a plan with `numWeeks == 3` and an exercise slot
- WHEN the coach selects "all weeks"
- THEN the slot is structurally removed from the plan (absent in all weeks)

#### SCENARIO-WPRES-014 — No dialog for single-week plan

- GIVEN a plan with `numWeeks == 1`
- WHEN the coach deletes an exercise
- THEN no dialog appears and the slot is removed immediately (identical to pre-change behavior)

---

### REQ-WPRES-011 — Editor: delete when slot has one active week

When the coach requests "only this week" delete on a slot that is currently present in exactly one week (i.e., removing it would yield an empty active set), the system MUST route to all-weeks (structural) delete automatically, without showing a second dialog.

#### SCENARIO-WPRES-015 — Auto-route to structural delete avoids zero-presence

- GIVEN a plan with `numWeeks == 3`, slot with `activeWeeks == [2]`, coach viewing week 2
- WHEN the coach taps delete and chooses "only this week"
- THEN the system deletes the slot structurally (no ghost slot; no second confirmation)

---

### REQ-WPRES-012 — Editor: add-exercise scope in week ≥ 2

When `numWeeks > 1` AND the coach is viewing a week with index ≥ 1 (i.e., "Sem 2" or later), adding an exercise MUST offer a scope choice:
- "Only this week" — seeds `activeWeeks = [_selectedWeek]`
- "All weeks" — seeds `activeWeeks = []` (empty = all weeks, existing behavior)

When `numWeeks == 1` or `_selectedWeek == 0`, no scope dialog MUST appear; the slot is added with `activeWeeks = []`.

#### SCENARIO-WPRES-016 — Scope dialog shown when adding on week ≥ 2

- GIVEN a plan with `numWeeks == 3`, coach viewing week 2 (index 1)
- WHEN the coach adds a new exercise
- THEN a scope dialog appears with "only this week" and "all weeks"

#### SCENARIO-WPRES-017 — "Only this week" seeds mask to current week

- GIVEN a plan with `numWeeks == 3`, coach on week 2 (index 1), scope = "only this week"
- WHEN the exercise is added
- THEN the new slot has `activeWeeks == [1]`

#### SCENARIO-WPRES-018 — "All weeks" seeds empty mask

- GIVEN a plan with `numWeeks == 3`, coach on week 2 (index 1), scope = "all weeks"
- WHEN the exercise is added
- THEN the new slot has `activeWeeks == []`

#### SCENARIO-WPRES-019 — No scope dialog when adding on week 1 or single-week plan

- GIVEN `numWeeks == 1` OR coach on "Sem 1" (index 0)
- WHEN the coach adds an exercise
- THEN no scope dialog appears and `activeWeeks == []`

---

### REQ-WPRES-013 — Editor: Duplicar-semana copies presence

"Duplicar semana" MUST copy the presence mask in addition to set prescriptions.
Every slot present in week `w` (i.e., `isPresentInWeek(w)` is true) MUST also be present in week `w+1` after duplication (add `w+1` to each such slot's effective mask).
Slots absent in week `w` MUST remain absent in week `w+1`.
The duplicated presence MUST be independent of the source week's mask (editing one MUST NOT affect the other).

#### SCENARIO-WPRES-020 — Duplicar copies presence from w to w+1

- GIVEN week 0 has slot A (`activeWeeks == []`) and slot B (`activeWeeks == [2]`); coach on week 1 (index 1)
- WHEN the coach taps "Duplicar semana"
- THEN slot A is present in week 1 (mask updated to include week 1 or stays empty = all)
- AND slot B remains absent in week 1 (mask still does NOT include week 1)

#### SCENARIO-WPRES-021 — Duplicar presence is independent

- GIVEN the coach duplicated week 0 into week 1, and slot A is present in both
- WHEN the coach performs "only this week" delete of slot A on week 1
- THEN slot A remains present on week 0 (unchanged)

---

### REQ-WPRES-014 — Editor: validation guards zero-presence per slot

The editor validation MUST check that no slot has a non-empty `activeWeeks` mask that excludes every week in `[0 .. numWeeks-1]`.

#### SCENARIO-WPRES-022 — Valid mask passes validation

- GIVEN a slot with `activeWeeks == [0, 1]` in a plan with `numWeeks == 2`
- WHEN validation runs
- THEN the slot passes (mask is a non-empty subset of valid weeks)

#### SCENARIO-WPRES-023 — Out-of-range mask fails validation

- GIVEN a slot with `activeWeeks == [3, 4]` in a plan with `numWeeks == 2` (weeks 0–1 only)
- WHEN validation runs
- THEN the save is blocked and the error references that slot

---

### REQ-WPRES-015 — Hard invariant: numWeeks == 1 — no dialog, no filter

When `numWeeks == 1`:
- The delete dialog MUST NOT appear.
- The add-scope dialog MUST NOT appear.
- No presence filtering MUST be applied to slot lists.
- `activeWeeks` MUST remain `[]` for all slots.
- Behavior MUST be byte-identical to pre-change.

#### SCENARIO-WPRES-024 — numWeeks == 1 detail screen is unchanged

- GIVEN a plan with `numWeeks == 1`
- WHEN the athlete opens the detail screen
- THEN all slots appear with no filtering and behavior is identical to pre-change

#### SCENARIO-WPRES-025 — numWeeks == 1 player is unchanged

- GIVEN a plan with `numWeeks == 1`
- WHEN the athlete starts and plays a session
- THEN the player renders all slots, no filtering applied, no deviation from pre-change behavior

---

### REQ-WPRES-020 — Athlete detail: filter slots by presence

`routine_detail_screen` and `exercise_slot_row` MUST filter the displayed slot list per day to only slots where `isPresentInWeek(viewedWeek)` is true.
The filter MUST apply before the list is rendered.
This MUST apply only when `numWeeks > 1`; single-week detail is not filtered.

#### SCENARIO-WPRES-026 — Detail shows only present slots for viewed week

- GIVEN a day with slot A (`activeWeeks == []`) and slot B (`activeWeeks == [2]`), athlete viewing week 0
- WHEN the detail screen renders that day
- THEN slot A appears and slot B does NOT appear

#### SCENARIO-WPRES-027 — Detail shows slot B when viewing its active week

- GIVEN the same setup as SCENARIO-WPRES-026, athlete switching to view week 2
- WHEN the detail screen renders
- THEN both slot A and slot B appear

#### SCENARIO-WPRES-028 — Detail with zero present slots shows info message

- GIVEN a day where all slots have `activeWeeks` that exclude the viewed week
- WHEN the athlete views that week/day combination
- THEN the day shows an informational "sin ejercicios esta semana" message (not a lock)

---

### REQ-WPRES-021 — Player: filter block list by session weekNumber

`session_player_screen` and `session_state` MUST filter the session's block list to only slots where `isPresentInWeek(session.weekNumber)` is true.
The filter MUST apply before building the block list used for player rendering and completion logic.

#### SCENARIO-WPRES-029 — Player shows only present slots for session week

- GIVEN a session with `weekNumber == 1`, a day with slot A (`activeWeeks == []`) and slot B (`activeWeeks == [0]`)
- WHEN the player builds its block list
- THEN slot A is included (empty mask = all) and slot B is NOT included (not present in week 1)

#### SCENARIO-WPRES-030 — Player with all slots present plays normally

- GIVEN a session where all slots have `activeWeeks == []`
- WHEN the player builds its block list
- THEN all slots are included (identical to pre-change behavior)

---

### REQ-WPRES-022 — Gating: empty-day auto-satisfied

A periodized day with zero present slots for the session's week MUST be treated as auto-satisfied by all gating and progress logic:
- `isDayUnlocked` / `isStartable` MUST skip the day (nothing to start).
- `derivePlanProgress` MUST count it as not-required so it never blocks week completion.
- No session is created for an empty day.

#### SCENARIO-WPRES-031 — Empty-presence day does not block week completion

- GIVEN a week with 3 days; day 2 has zero present slots for that week; days 1 and 3 have sessions finished
- WHEN `derivePlanProgress` is computed
- THEN the week is considered complete (day 2 auto-satisfied, not required)

#### SCENARIO-WPRES-032 — Empty-presence day shows info, not lock

- GIVEN a day with zero present slots for the viewed week
- WHEN the athlete views that day on the detail screen
- THEN the day displays "sin ejercicios esta semana" (informational); no locked affordance

---

### REQ-WPRES-023 — Supersets: absent member drops from week block

In a superset group, each member's presence is evaluated independently via `isPresentInWeek`.
Members absent for the viewed/played week MUST be excluded from the week's block.
If filtering leaves a group with exactly one member in a given week, it MUST render as a normal (non-superset) exercise for that week.
A superset group MUST have at least one present member per week it appears in; having zero present members in a week means the whole group is absent (auto-satisfied per REQ-WPRES-022).

#### SCENARIO-WPRES-033 — Absent superset member drops from that week

- GIVEN a superset with member A (`activeWeeks == []`) and member B (`activeWeeks == [0]`), player on week 1
- WHEN the player builds the block list
- THEN the block contains only member A; it renders as a normal exercise (not a superset-of-one)

#### SCENARIO-WPRES-034 — Full superset renders normally when all members present

- GIVEN a superset with members A and B, both with `activeWeeks == []`, player on any week
- WHEN the player builds the block list
- THEN the block renders as a full superset with both members

---

### REQ-WPRES-030 — Hard invariant: numWeeks == 1 produces no regression

Single-week routines (`numWeeks == 1`) MUST retain identical behavior across every screen and action:
editor (load, edit, save, delete, add), detail screen, session start, player, gating, progress derivation.
No dialog, no filter, no presence check MUST execute on a single-week plan.

#### SCENARIO-WPRES-035 — Single-week plan edit/save round-trip is unchanged

- GIVEN an existing routine with `numWeeks == 1`
- WHEN a coach opens, edits a set, and saves it
- THEN the saved document is structurally identical to pre-change (activeWeeks stays absent or empty in all slots; no new dialogs appear)

---

### REQ-WPRES-031 — Quality gate

After all implementation work for this change:
- `flutter analyze lib test` MUST report 0 issues.
- `dart format` MUST produce no changes.
- All existing and new tests MUST pass.
- `build_runner`-generated files (`.g.dart`, `.freezed.dart`) MUST be regenerated and committed.
- A Firestore rules stub test MUST confirm `activeWeeks` writes are permitted under the existing rules.

#### SCENARIO-WPRES-036 — Quality gate is green

- GIVEN all implementation tasks are complete
- WHEN `flutter analyze lib test` runs
- THEN exit code is 0, format is clean, all tests pass

---

## Spec-level assumptions

1. "Week index" is 0-based throughout; display label is `weekIndex + 1` (e.g., index 1 = "Sem 2"). Consistent with existing REQ-PERIOD-* convention.
2. "Only this week" delete materializes an empty mask to `[0..numWeeks-1]` before removing the current week. This is the only correct interpretation that avoids corrupting currently-all-weeks slots.
3. The scope dialog for "add exercise" is only shown when `_selectedWeek >= 1` (0-based), which corresponds to "Sem 2" and later. Adding on "Sem 1" always seeds `activeWeeks = []`.
4. Duplicar-semana: "slot present in w" = `isPresentInWeek(w)` returns true. If the source slot has `activeWeeks == []`, the duplicate also has `activeWeeks == []` (empty = all; no mask to copy). If source has `activeWeeks == [0, 1]` and we duplicate week 1 → week 2, we add week 2 to the mask: result `[0, 1, 2]`.
5. Firestore rules are expected to require NO change; the stub test is a verification artifact, not a planned modification.

# Proposal: Per-week exercise presence (periodization Option A)

## Intent

In the shipped periodization (Model B), the exercise STRUCTURE is shared across all weeks: `RoutineDay.slots` is a single list, and weeks only vary the prescription (`RoutineSlot.weeklySets`). Device testing surfaced the consequence — deleting an exercise from week 2 deletes it from the WHOLE plan. Coaches need exercises that exist in some weeks but not others (e.g. an accessory that appears only in an intensification block). The user chose **Option A — a per-week presence mask on the slot**: the structure stays shared, but each slot declares in which weeks it is present.

## Scope

### In Scope
- Domain: `RoutineSlot.activeWeeks: List<int>` (0-based). **Absent/empty = present in ALL weeks** (hard backward-compat: no existing doc changes behavior).
- Derived `bool isPresentInWeek(int week)` getter on `RoutineSlot`.
- Editor DELETE: in a multi-week plan, deleting an exercise prompts "only this week" (mask off for current week) vs "all weeks" (structural removal, current behavior).
- Editor ADD: adding an exercise while viewing week ≥2 lets the coach choose "only this week" vs "all weeks".
- Athlete DETAIL: per-week exercise list filters slots by presence.
- Athlete PLAYER: a week-N session filters slots by presence.
- Serialization: `List<int>` wire format (no nested-array problem — confirmed against `WeeklySetsConverter`; ints are primitives, ride inside `days`).
- Firestore rules: VERIFY no change needed (field nested in `days`, covered by existing `hasOnly` on `days`).

### Out of Scope
- Per-week REORDERING of slots (order stays shared).
- Migration/backfill of existing docs (none needed — empty mask = all weeks).
- Changing `numWeeks`, `weeklySets`, or gating semantics beyond presence filtering.
- Trainer-template vs assigned divergence (same model for all routine sources).

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `periodization` (or the spec name used by `periodization-model-b`): adds per-week slot presence to authoring (REQ-PERIOD-0xx series) and athlete consumption/gating.

## Approach

`activeWeeks` is an additive optional field. Resolution rule (single source of truth):
`isPresentInWeek(w) => activeWeeks.isEmpty || activeWeeks.contains(w)`.
This makes empty = present-everywhere, so legacy and all current single/multi-week docs keep playing unchanged with zero migration.

- Editor: presence is per (slot, week). The DELETE affordance branches on `_numWeeks > 1`: prompt only-this-week (drop `_selectedWeek` from the mask, materializing the mask to `[0..numWeeks-1]` minus current) vs all-weeks (existing `_removeSlot`). ADD on week ≥2 with "only this week" seeds the mask to `[_selectedWeek]`. Mirror the live-view model (ADR-PB-02): the mask is the source of truth; widgets receive resolved presence.
- Consumer: `routine_detail_screen` and `session_player_screen` already thread the viewed/active week (ADR-PB-05, query param). Filter `day.slots.where((s) => s.isPresentInWeek(week))` before rendering and before building the player block list.
- Hard invariant: with `numWeeks == 1`, `_numWeeks > 1` is false everywhere → no dialog, no filter, no behavior change. (Note: shipped editor saves `weeklySets=[[week0]]` even for single-week per ADR-PB-03, but `activeWeeks` stays empty for single-week, so presence resolution is a no-op.)

### Edge cases resolved
- **Slot with NO active weeks**: forbidden. Editor validation (extend `_isValid`) rejects a slot whose mask is non-empty AND excludes every week. "Only this week" delete on a slot already present in just that one week → offer all-weeks delete instead (cannot leave a ghost slot present in zero weeks). Empty mask is always legal (= all weeks).
- **Supersets**: presence is per-member. A superset member absent in week W simply drops out of that week's block. If filtering leaves a group with a single remaining member in some week, render it as a normal exercise that week (no orphan "superset of one" badge). Validation: a superset group must have ≥1 present member per week it appears in; deleting the last present member of a group in a week is an only-this-week delete of that member like any other.
- **"Duplicar semana"**: copies prescriptions (`weeklySets`). Presence is structural, not prescription — duplicating week w into w+1 must also COPY presence so the duplicated week is a faithful copy. Define: after duplicate, every slot present in w is present in w+1 (add w+1 to each present slot's effective mask). Slots absent in w stay absent in w+1.
- **Day empty in a week (all slots absent)**: a periodized day with zero present slots in week W. Gating treats it as auto-satisfied — `isDayUnlocked`/`isStartable` skip an empty day (nothing to start), and `derivePlanProgress` counts it as not-required so it never blocks week completion. Detail shows it as "sin ejercicios esta semana" (informational, not a lock). This keeps secuencial gating from deadlocking on a week the coach intentionally emptied.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/workout/domain/routine_slot.dart` | Modified | Add `activeWeeks` field + `isPresentInWeek` getter |
| `routine_slot.g.dart/.freezed.dart` | Modified | build_runner regen (List<int>, no converter) |
| `routine_editor_screen.dart` | Modified | Delete dialog, add-scope choice, mask plumbing, validation, Duplicar-semana copies presence |
| `routine_detail_screen.dart` + `exercise_slot_row` | Modified | Filter slots by `isPresentInWeek(viewedWeek)` |
| `session_player_screen.dart` + `session_state.dart` | Modified | Filter block list by presence for `session.weekNumber`; gating/progress treat empty day as satisfied |
| `firestore.rules` | Verify | Confirm `days` `hasOnly` already covers nested `activeWeeks` (likely zero change) |
| `routine_repository.dart` | Verify | `activeWeeks` rides via `days[].slots[]` toJson; update maps unchanged |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Rules reject the nested new field | Low | Field nested in `days`; rules enumerate `days` not slot keys — verify with a rules stub test on a save adding `activeWeeks`, do NOT assume |
| Zero-presence ghost slot | Med | Validation forbids non-empty mask excluding all weeks; only-this-week delete on single-present-week slot routes to all-weeks delete |
| Gating deadlock on intentionally-empty week/day | Med | Empty-presence day counts as auto-satisfied in `derivePlanProgress` + gating fns; unit-test the truth table |
| Single-week regression | Low | `numWeeks==1` short-circuits all presence UI and filters; mask stays empty; assert no behavior delta |
| Duplicar-semana drops presence | Med | Define duplicate to copy presence into target week; unit-test |
| Superset becomes orphan member in a week | Low | Render single present member as normal exercise that week; validate ≥1 present member per appearing group |

## Rollback Plan

`activeWeeks` is additive and defaults to empty (= all weeks). Reverting the feature branch removes the field and UI; any doc written with a non-empty mask is simply ignored by old code (unknown nested key) and the slot reverts to present-in-all-weeks — no data corruption, no migration to undo. Roll back by reverting `feat/periodization-week-presence`.

## Dependencies

- Builds on shipped `periodization-model-b` (numWeeks, weeklySets, weekNumber, effectiveSetsForWeek, week tabs, secuencial gating) — branch `feat/periodization-integration`.

## Success Criteria

- [ ] Deleting an exercise in week 2 of a multi-week plan can remove it from only that week or all weeks (coach choice).
- [ ] Adding an exercise on week ≥2 can target only that week.
- [ ] Athlete detail and player show only present slots per week.
- [ ] `numWeeks==1`: no dialog, no filter — byte-identical behavior to today.
- [ ] No existing doc changes behavior (empty mask = all weeks); zero migration.
- [ ] Edge cases (zero-presence forbidden, superset member absence, Duplicar copies presence, empty-day auto-satisfied gating) covered by tests.
- [ ] `flutter analyze lib test` 0 issues, `dart format` clean, tests green; build_runner committed.
- [ ] Firestore rules verified (stub test) — change only if verification shows it's required.

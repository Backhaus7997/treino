# Exploration — live-set-editing (add/remove sets en vivo)

Goal (corrected): ADD or REMOVE sets (series) of an exercise IN REAL TIME during the live session. (Editing a logged set's reps/weight already works for the current block — that was NOT the gap.)

## Does it exist today? — NO, at any layer

- **Add extra set**: no affordance. The row loop is hard-bounded: `for (idx=0; idx < totalSets; idx++)` where `totalSets = slot.effectiveSetsForWeek(week).length` (`session_player_screen.dart:1315,1322`) — derived purely from the routine plan, recomputed every build. No "+1", no button, no state. (`logSet` has no upper-bound guard, so a `setNumber > planned` write would persist — but nothing in the UI ever triggers it.)
- **Remove set**: no delete path anywhere. `SessionRepository` has only `addSetLog`/`updateSetLog`/`listSetLogs` — **no `deleteSetLog`**. `SessionNotifier` has no `removeSet`. No UI affordance.

## Root cause — planned sets are fixed, not session-mutable

`RoutineSlot.effectiveSetsForWeek(week)` (`routine_slot.dart:101-156`) is a read-only derived getter from the plan template. `SessionState` never copies it into mutable session state — it just holds `setLogs` and reads the plan's count fresh as the denominator. There is NO session-local concept of "this exercise got a bonus set today" or "set 2 removed today".

Precedent: `routine_editor_screen.dart` (pre-session builder) DOES treat sets as a mutable list (`weeklySets.add`/`removeLast`) — but only at authoring time, mutating the shared plan template (wrong place to touch live: would retroactively change every future week).

## What's needed (cross-cutting — NOT just a button)

1. **Session-local set-count override** — new `SessionState` field (e.g. per-exercise extra/removed count) folded into `totalSets` for rendering.
2. **`deleteSetLog`** — new repo method (real Firestore `.doc(id).delete()`, not soft-delete).
3. **Gating-math changes** — `isFullyCompleted`, `BlockStatus`, `_nextIncompleteIndex` all compare `loggedCount >= plan set count`. So: adding a 4th set to a 3-set exercise → it already reads "done" after set 3, block collapses (per the completed-block finding), 4th row unreachable. Removing → the "planned total" must drop or the progress ring waits forever. **Add/remove can't be a purely additive UI change without touching this math.**

## Persistence
- Add: reuse `logSet` (already writes a new setLog doc per set). Missing: the UI trigger + letting the render loop exceed `totalSets`.
- Remove: needs the new `deleteSetLog`. Real deletion (not soft) is correct: the server ranking trigger reads `setLogs` on finish and recomputes from whatever docs exist — a deleted doc is correctly absent. (Verify ranking-aggregate.ts tolerates mid-session deletes — flagged, out of this scope.)

## Approaches
1. **[RECOMMENDED] "+ Agregar serie" button per exercise + delete icon per logged-set row.** Maps to the row-based mental model; static icon > swipe for accessibility. The real cost is the shared core (session-local override + deleteSetLog + gating math), not the button.
2. Swipe-to-delete + add button — same core, less discoverable gesture.
3. Per-exercise "sets today" stepper on the header — one control instead of per-row; simpler UI, same gating/delete core; less granular.

## Open decisions for propose
1. **Scope**: add + remove together, or add-only first? (Remove is the harder half: delete path + renumbering + confirm dialog.)
2. **Reach**: only the CURRENT/reachable exercise, or also already-completed exercises? (The latter depends on the separate "make completed blocks reachable" gap.)
3. Renumber on delete (set 3 → set 2, extra writes) vs leave a gap ("SET 1, SET 3").
4. Added set: has a planned target (SetSpec) or a bare free-entry row?
5. Delete confirmation dialog (data-loss) vs quiet action.
6. Verify ranking-aggregate.ts tolerates mid-session setLog deletes.

## Size caveat
Materially bigger than value-editing: new session-local domain concept + repo delete + gating-math changes. NOT just a button.

## Relevant files
- `session_player_screen.dart` (row loop 1315-1322; gating; `_CompletedBlockSummary` 864-980)
- `session_notifier.dart` (logSet 200-253, updateSet 258-293; no removeSet), `session_state.dart` (no override), `session_repository.dart` (no deleteSetLog)
- `routine_slot.dart:101-156` (effectiveSetsForWeek — fixed plan getter), `routine_editor_screen.dart:772,790` (mutable-set precedent, authoring only)

Engram: `sdd/live-set-editing/explore`.

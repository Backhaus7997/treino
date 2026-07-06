# Design — live-set-editing

Add and remove sets (series) of the current/reachable exercise in real time during a live
session. Add + remove ship together (settled scope). Editing a logged set's reps/weight is
already covered by `updateSet`/`updateSetLog` and is out of scope.

## Executive summary

Introduce ONE session-local domain concept — a per-exercise absolute set-count override on
`SessionState` — and route EVERY denominator that today reads
`slot.effectiveSetsForWeek(week).length` through a single new resolver
`SessionState.plannedSetsFor(slot)`. Add persists via the existing `logSet` path (a
`setNumber` beyond the plan already writes correctly); remove adds a real
`SessionRepository.deleteSetLog` + a race-safe `SessionNotifier.removeSet` that deletes the
log, renumbers survivors, and updates the override. No Cloud Function change: the ranking
recompute is verified tolerant of mid-session setLog deletes.

## Technical approach

### The headline risk — gating math is NOT additive

The plan-set count (`effectiveSetsForWeek(week).length`) is read as the completion denominator
in **nine** places. If add/remove only touches the render loop, every one of these silently
disagrees with the on-screen row count:

| # | Site | File:line | Role |
|---|------|-----------|------|
| 1 | `isFullyCompleted` | `session_state.dart:38` | finish gate |
| 2 | `isExerciseDone` | `session_state.dart:55` | per-exercise done + `completedExerciseCount` |
| 3 | `_nextIncompleteIndex` | `session_notifier.dart:415` | navigation cursor |
| 4 | `isStandaloneBlockComplete` | `session_player_screen.dart:92` | block collapse (standalone) |
| 5 | `isSupersetBlockComplete` | `session_player_screen.dart:101` | block collapse (superset) |
| 6 | `_CompletedBlockSummary.totalSets` | `session_player_screen.dart:786` | collapsed "N/N" display |
| 7 | `_StandaloneBlock` render `totalSets`/`isDone`/`currentSetNumber` | `session_player_screen.dart:797,802` | interactive render + cursor |
| 8 | `_SupersetSection` maxRounds/round scan | `session_player_screen.dart:1155,1167` | superset round-robin cursor |
| 9 | `_ExerciseSection` render loop bound | `session_player_screen.dart:1315` | which rows draw |

The design's core move: **collapse all nine reads onto one resolver** so add/remove is a
single-source-of-truth change, not nine coordinated edits.

### Single resolver

```dart
// session_state.dart — the ONE place the plan count is turned into "sets today".
int plannedSetsFor(RoutineSlot slot) {
  final planned = slot.effectiveSetsForWeek(session.weekNumber).length;
  return setCountOverride[slot.exerciseId] ?? planned;   // absolute override wins
}
```

Sites 1–3 (state + notifier) call `plannedSetsFor(slot)` directly. Sites 4–9 live in
`session_player_screen.dart` and receive the resolved count threaded down from
`_buildExerciseList` (they already receive `week`; they will additionally receive the resolved
count, or an accessor, rather than recomputing from the slot). The free functions
`isStandaloneBlockComplete` / `isSupersetBlockComplete` / `computeBlockStatuses` gain a
`plannedSetsFor` count parameter (a `Map<String,int>` or an `int Function(RoutineSlot)`) instead
of reading the slot's plan getter internally.

## Architecture decisions

### AD-1 — Session-local set-count model: per-exercise ABSOLUTE override map

`SessionState` gains one field:

```dart
final Map<String, int> setCountOverride;   // exerciseId -> sets-today (absolute)
```

Default `const {}`. An entry is present ONLY for an exercise the athlete changed this session;
absent → fall back to the plan count. Add = `override[id] = plannedSetsFor(slot) + 1`;
remove = `override[id] = plannedSetsFor(slot) - 1` (floored at the number of *remaining* logs so
you can never render fewer rows than there are logs — see AD-5). `copyWith` and `==`/`hashCode`
(via `MapEquality`/`Object.hashAllUnordered`) extend to cover it.

**How the three cases resolve:**
- **Add** (3-set exercise, tap "+"): `override[id]=4`. `plannedSetsFor→4`. Render loop draws
  4 rows; row 4 has no `SetSpec` (AD-4). Gating needs 4 logs → not done until set 4 logged.
- **Remove an unlogged planned row** (3-set, 2 logged, drop the pending 3rd): `override[id]=2`.
  Render draws 2 rows, both logged → done. No Firestore write (nothing was logged).
- **Remove-after-logged** (3-set, all 3 logged, delete set 2): `override[id]=2`, delete set-2
  doc, renumber survivor set 3→2 (AD-3). Render draws 2 rows (set 1, set 2), both logged → done.

**Rejected — per-exercise delta `Map<String,int>` (+1 / −1):** the proposal floats it. Rejected
because a delta must be *reapplied against a possibly-changing base*. If a periodized plan's
week count ever re-resolves mid-session (it doesn't today, but the coupling is a latent trap), a
delta drifts. An absolute "sets today" is self-describing and matches `routine_editor`'s mental
model of a concrete list length. It also makes the floor invariant (never < logged count)
trivial to enforce at write time.

**Rejected — list of added `SetSpec`s + set of removed set-numbers:** most expressive (lets an
added set carry a target), but it's two structures to keep consistent, it entangles renumbering
with removed-index bookkeeping, and AD-4 settles that added sets are bare (no `SetSpec`), so the
extra expressiveness buys nothing. Overkill for a count change.

**Rejected — mutate the plan template (the `routine_editor` `weeklySets.add/removeLast`
precedent):** explicitly wrong per exploration — it retroactively rewrites every future week of
the shared routine. Session-local is the whole point.

### AD-2 — `deleteSetLog` + race-safe `removeSet`

**Repository** (`session_repository.dart`), mirroring `updateSetLog`'s shape:

```dart
Future<void> deleteSetLog({
  required String uid, required String sessionId, required String setLogId,
}) async {
  await _setLogs(uid, sessionId).doc(setLogId).delete();   // real delete, not soft
}
```

Real delete is correct and confirmed safe by AD-8: the ranking recompute reads whatever docs
exist. No soft-delete flag, no tombstone.

**Notifier** (`session_notifier.dart`) — `removeSet` follows the exact `updateSet` race
discipline (re-read `state.value` after every await; guard `_finalized`; emit failures on the
`_logSetError` channel, never flip to `AsyncError`):

```dart
Future<void> removeSet(RoutineSlot slot, SetLog? target) async {
  final current = state.value;
  if (current == null || _finalized) return;
  final uid = ref.read(currentUidProvider);
  if (uid == null) return;

  final exId = slot.exerciseId;
  // Renumber plan (AD-3): survivors with setNumber > target keep sequence dense.
  // Compute the delete + renumber writes from `current`, but APPLY to re-read state.
  try {
    if (target != null && target.id.isNotEmpty) {
      await repo.deleteSetLog(uid: uid, sessionId: current.session.id, setLogId: target.id);
      // Renumber survivors (bounded: only logs of this exercise above the gap).
      for (final survivor in survivorsAbove(current, exId, target.setNumber)) {
        await repo.updateSetLog(uid, sessionId, survivor.copyWith(setNumber: survivor.setNumber - 1));
      }
    }
    final latest = state.value ?? current;                 // re-read after awaits
    final newLogs = renumberedLocalLogs(latest, exId, target);
    final newOverride = {...latest.setCountOverride, exId: max(newCount, loggedNow)};
    final newIndex = _nextIncompleteIndex(latest.day, newLogs, latest.session.weekNumber);
    state = AsyncData(latest.copyWith(
      setLogs: newLogs, setCountOverride: newOverride, currentExerciseIndex: newIndex));
  } catch (e) {
    _logSetError.value = SessionLogError(action: SessionLogAction.remove, setLog: target ?? ...);
  }
}
```

`addSet` reuses `logSet`: bump `override[id]` to `plannedSetsFor+1`, then call the existing
`logSet` write path for `setNumber = <new count>`. `logSet`'s idempotency key
(`exerciseId + setNumber`, `session_notifier.dart:207`) already prevents a double-tap dupe on the
added row — no new guard needed. `SessionLogAction` gains a `remove` case so
`retryLastLogError` can re-dispatch a failed delete.

**Note (out of the happy path):** `deleteSetLog` on set 2 succeeds but a survivor renumber write
fails mid-loop → the gap is real in Firestore until retry. Because the DENOMINATOR is `count`,
not `max(setNumber)` (AD-3), and local state renumbers optimistically, the UI stays correct; the
retry re-runs the renumber idempotently. This is acceptable for a live session (same failure
posture as a failed `logSet`).

### AD-3 — Renumber on delete (chosen), NOT leave-a-gap

**Decision: RENUMBER survivors so `setNumber` stays dense (1..N).** Deleting set 2 of 3 →
delete set-2 doc, rewrite the surviving set-3 doc to `setNumber:2`.

- **Denominator is `count`, never `max(setNumber)`** — this is the invariant that keeps
  renumbering a pure *display/consistency* concern. `setsLoggedFor` already counts
  (`setLogs.where(...).length`), and `plannedSetsFor` returns the override count. Nothing gates
  on the max set number, so a transient gap can't deadlock completion.
- **Rewrite sequence (idempotent):** for every logged set of the exercise with
  `setNumber > deletedSetNumber`, in ascending order, `updateSetLog` with
  `setNumber := setNumber - 1`. Bounded to survivors above the gap (0..k−1 extra writes for a
  k-set exercise). Idempotent because re-running renumber on an already-dense sequence rewrites
  each doc to the value it already holds — a no-op-equivalent overwrite. The `logSet`
  idempotency key uses `exerciseId+setNumber`; after renumber the keys stay unique because the
  sequence stays dense.

**Rejected — leave a gap ("SET 1, SET 3"):** zero extra writes, but the row-based UI labels rows
`SET N` sequentially; a visible gap reads as a bug to the athlete and the render loop (indexed
`for idx`, `setNumber = idx+1`) would mislabel survivors OR require a parallel "logged-by-number"
lookup that reintroduces the max-vs-count ambiguity. The renumber writes are cheap, bounded, and
idempotent. Density wins.

### AD-4 — Added-set shape: BARE free-entry, SetLog-only, no SetSpec

**Confirmed: an added set has NO `SetSpec`.** It exists only as a `SetLog` doc once logged (and
as a rendered pending row before that, driven purely by the override bumping the loop bound). No
domain change to `SetLog` or `RoutineSlot`.

Render handling — the loop at `session_player_screen.dart:1322` currently does
`final spec = effectiveSets[idx];` which throws for `idx >= effectiveSets.length`. Change to:

```dart
final SetSpec? spec = idx < effectiveSets.length ? effectiveSets[idx] : null;
```

For a null spec (an added row): no planned target hint (no "10 reps" / "8–12" prescription
text), `plannedReps = 0`, `plannedWeight = 0`. Prefill from the previous logged set ONLY if the
existing add-row already does that (it does not today — pending rows preload the planned target,
`session_player_screen.dart:1365`); so an added row starts empty. The row still logs through the
same `onSetCheck` → `logSet` path. `_RepsSetRow`/`_DurationSetRow` must tolerate a null spec
(guard the `spec.durationSeconds`/`spec.weightKg`/`spec.type` reads).

**Rejected — synthesize a `SetSpec` (copy the last planned row's target):** inventing a
prescription for a set that is by definition outside the plan is guesswork and misrepresents the
plan. Bare is honest.

### AD-5 — Gating-math updates (the crux)

All nine sites switch from `slot.effectiveSetsForWeek(week).length` to the resolved count:

- **Sites 1–3** (`isFullyCompleted`, `isExerciseDone`, `_nextIncompleteIndex`): replace the
  inline `slot.effectiveSetsForWeek(session.weekNumber).length` with `plannedSetsFor(slot)`.
  `_nextIncompleteIndex` is a notifier method that receives `day` + `logs`; it will read the
  override from the current state (it already runs inside the notifier with `state.value`
  available) or take the override map as a parameter.
- **Sites 4–8** (block-status free fns + block widgets + superset scan): thread the resolved
  count down. `computeBlockStatuses` / `isStandaloneBlockComplete` / `isSupersetBlockComplete`
  take an `int Function(RoutineSlot) plannedSetsFor` (or a precomputed
  `Map<String,int>`). `_buildExerciseList` builds this once from `state` and passes it.
- **Site 9** (render loop): `totalSets = plannedSetsFor(slot)` (threaded via the section's
  props), so the loop draws exactly the override count.

**The two invariant cases both resolve:**
- **Added-beyond-plan** (add 4th to a 3-set): `plannedSetsFor→4` everywhere. After logging
  set 3, `isExerciseDone` needs 4 → false → block does NOT collapse, `_CompletedBlockSummary`
  does not trap it, row 4 stays reachable. After set 4: 4≥4 → done → collapses correctly.
- **Removed-below-logged**: enforce the write-time floor `override[id] = max(newCount,
  currentLoggedCount)`. You can never set the override below the number of logs that exist, so
  the render loop can't hide a logged row and gating can't wait forever on a row that isn't
  drawn. Removing a LOGGED set is a delete (AD-2) that reduces both logs and count together, so
  the floor holds.
- **Mid-add collapse guard:** because `_CompletedBlockSummary` / `computeBlockStatuses` now read
  the override count, an exercise mid-add (override=4, 3 logged) is `current`, not `completed` —
  it cannot be collapsed out from under the pending 4th row.

**Superset note:** the round-robin scan (site 8, `maxRounds`/`round > ...length`) also switches
to the resolved count. But per settled scope the add/remove AFFORDANCES render only for the
current/reachable STANDALONE-context exercise; superset add/remove UI is not in scope this
change. The gating switch to `plannedSetsFor` is applied uniformly for correctness (so an
override never desyncs the superset math), but no "+ agregar serie" button is placed inside a
superset block in this change. Flag if product wants superset add/remove.

### AD-6 — UI affordances

- **"+ agregar serie"** — a full-width subtle button appended AFTER the last row inside
  `_ExerciseSection`'s `Column` (`session_player_screen.dart` ~1385, after `rowWidgets`), shown
  ONLY when the section is interactive (current or hand-activated block) and NOT while a
  `logSet`/`removeSet` write is in flight (reuse the disabled-during-write posture). Icon
  `TreinoIcon.plus` (verify token name; use the registered add glyph — never `PhosphorIcons.X`).
  Copy: `agregar serie` (es-AR). Wires to a new `onAddSet(slot)` callback → `notifier.addSet`.
- **Per-row delete** — a trailing delete icon (`TreinoIcon.trash`, static, NOT swipe — matches
  the exploration's accessibility/discoverability rationale) on LOGGED rows of the interactive
  section, and on an added-but-unlogged pending row. Wires to `onRemoveSet(slot, log?)`.
- **Confirmation** — deleting a LOGGED set shows a lightweight confirm dialog (data loss),
  following existing app dialog patterns (same family as the abandon-session dialog). Copy:
  title `Eliminar serie`, body `Se va a borrar esta serie registrada.`, actions `Cancelar` /
  `Eliminar`. Deleting an EMPTY/unlogged added row is a single tap, no dialog.
- **Theme** — Mint Magenta dark-only, `AppPalette.of(context)`, spacing tokens 8·12·14·18·20,
  no HEX literals, `TreinoIcon.X` only.

### AD-7 — Test plan

Leverage the existing `MockSessionRepository` + `Completer` interleave pattern from
`session_notifier_updateset_race_test.dart`.

**Unit (notifier + state):**
- `plannedSetsFor` returns plan count with empty override, override value when present.
- `addSet` bumps override and calls `addSetLog` with `setNumber = planned+1`; second rapid tap
  is idempotent (existing key guard).
- `removeSet` on a logged set calls `deleteSetLog` with the right id, then `updateSetLog` for
  each survivor above the gap with `setNumber-1` (renumber), and updates override + logs.
- `removeSet` on an unlogged pending row does NOT call `deleteSetLog`, only lowers override.
- Write-time floor: `removeSet` cannot drop override below current logged count.
- Gating fns with override: `isFullyCompleted`/`isExerciseDone`/`_nextIncompleteIndex` honor the
  override (added-beyond-plan not done until extra logged; removed drops the denominator).
- **Race:** a `logSet` completing during a `removeSet` await survives (re-read-after-await), and
  vice versa — mirror the updateset race test.
- `deleteSetLog` repo test against `fake_cloud_firestore`: doc is gone after delete.

**Widget (`session_player_screen`):**
- "+ agregar serie" renders an extra row that logs; block stays current mid-add.
- Delete icon on a logged row → confirm dialog → confirm → row gone, count drops, gating
  updates (block can now complete/collapse if all remaining logged).
- Delete on an unlogged added row → no dialog, row gone.
- Deleting the LAST logged set of an otherwise-complete exercise reopens it (not `completed`).

### AD-8 — Ranking-trigger tolerance (open q #4) — VERIFIED SAFE, no CF change

Read `functions/src/ranking-aggregate.ts` end to end.

- The recompute trigger `rankingAggregateOnSession` fires on writes to
  `users/{uid}/sessions/{sessionId}` — NOT on `setLogs` subcollection writes. **A mid-session
  setLog delete does not even fire the trigger.**
- `recomputeMetrics` runs on finish (the session-doc `status→finished` write). It re-queries
  `setLogs` fresh per qualifying session (`doc.ref.collection("setLogs").get()`, line 189) and
  computes `lifetimeVolumeKg` from `session.totalVolumeKg` (line 181 — a session field, not a
  setLog count) and `best<Lift>Kg` via `familyMaxWeight` iterating whatever docs exist
  (lines 95–106).
- **No doc-count, no monotonic-growth, no snapshot/caching assumption anywhere.** A deleted
  setLog is simply absent from the recompute's iteration; a missing PR-weight doc lowers the max
  correctly.

**Verdict: fully tolerant. No `ranking-aggregate.ts` change. Not a scope risk.** (The only
subtlety: `totalVolumeKg` is written by the client at finish from `SessionState.totalVolumeKg`,
which sums the live `setLogs` list — so a removed set correctly lowers volume because it's gone
from `setLogs` before finish. Consistent end to end.)

## File-level change map

| File | Change |
|------|--------|
| `session_state.dart` | +`setCountOverride` field (+ copyWith/==/hashCode); +`plannedSetsFor(slot)`; sites 1–2 (`isFullyCompleted`, `isExerciseDone`) use it |
| `session_notifier.dart` | +`addSet(slot)` (reuses `logSet`); +`removeSet(slot, log?)` (race-safe, renumber); `_nextIncompleteIndex` honors override; `SessionLogAction.remove` + `retryLastLogError` case |
| `session_repository.dart` | +`deleteSetLog(uid, sessionId, setLogId)` (real `.doc(id).delete()`) |
| `session_player_screen.dart` | render loop bound → `plannedSetsFor`; null-safe `spec`; block-status fns + widgets take resolved count; "+ agregar serie" button; per-row delete icon; confirm dialog; new `onAddSet`/`onRemoveSet` callbacks threaded |
| `set_log.dart` / `routine_slot.dart` | NO change (AD-4 confirms no domain marker) |
| `functions/src/ranking-aggregate.ts` | NO change (AD-8 verified tolerant) |
| tests | new notifier/repo unit tests + widget tests + race tests (AD-7) |

## Riverpod state-graph delta

No new providers. `sessionNotifierProvider` unchanged. The only state-shape change is one field
on the `SessionState` value (`setCountOverride`). `addSet`/`removeSet` are new imperative methods
on the existing `SessionNotifier`, following the identical `state = AsyncData(latest.copyWith(...))`
race discipline as `logSet`/`updateSet`. The error channel (`_logSetError` `ValueNotifier`) is
reused for delete failures (new `SessionLogAction.remove`). Stream/timer lifecycle unchanged.

## Risks

- **HEADLINE — gating math is not additive.** Nine sites read the plan count as the completion
  denominator. Missing ANY one desyncs render vs completion (block collapses with a pending
  row, or the finish gate waits forever). Mitigation: single `plannedSetsFor` resolver + thread
  the resolved count through the block-status fns; AD-7 tests each invariant case. This is the
  make-or-break of the change.
- **Renumber partial failure** — delete succeeds, a survivor renumber write fails mid-loop
  leaves a transient Firestore gap. Acceptable because the denominator is count-not-max and the
  renumber is idempotent on retry; same failure posture as a failed `logSet`.
- **Superset scope ambiguity** — the round-robin scan reads the plan count too. Gating switches
  to the override uniformly for correctness, but no add/remove UI is placed in superset blocks
  this change. If product wants it, that's a follow-up (round-robin cursor math with per-member
  overrides is materially harder).
- **`SetSpec?` null-safety fan-out** — `_ExerciseSection`'s row builders assume a non-null spec
  today. Every `spec.` read on the added-row path must be guarded, or an added row throws.

## Chained-PR slices

- **PR 1 — add-set (lands the shared core).** `setCountOverride` field + `plannedSetsFor`
  resolver + all nine gating sites switched to it + null-safe `spec` + `SessionNotifier.addSet`
  (reuses `logSet`) + "+ agregar serie" button. This carries the entire risk-bearing gating-math
  change with the smaller, purely additive UI. Reviewable in isolation.
- **PR 2 — remove-set (builds on PR 1).** `SessionRepository.deleteSetLog` +
  `SessionNotifier.removeSet` (race-safe) + renumber-on-delete (AD-3) + per-row delete icon +
  confirm dialog + `SessionLogAction.remove`/retry + AD-8 verification note. Self-contained on
  top of the override from PR 1.

If the review-workload forecast allows, they may merge as a single PR — the slice is a review
convenience, not a hard split.

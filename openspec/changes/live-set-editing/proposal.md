# Proposal — live-set-editing

Add and remove sets (series) of an exercise in real time during a live workout session.

## Why

During a live session an athlete regularly deviates from the planned set count: they feel strong and want one more series, or they run out of time / energy and drop the last one. Today the app has **no affordance for this at any layer** — the set rows are hard-bounded by the plan template (`for (idx=0; idx < totalSets; idx++)` where `totalSets = RoutineSlot.effectiveSetsForWeek(week).length`, `session_player_screen.dart:1315,1322`), and `SessionRepository` exposes only `addSetLog` / `updateSetLog` / `listSetLogs` — there is **no `deleteSetLog`** and no `removeSet` on the notifier.

Important distinction: **editing a logged set's reps/weight already works** for the current block (`updateSet` → `updateSetLog`). That was never the gap. The real gap is changing the *number* of series on the fly.

The reason this is missing is structural, not cosmetic: `effectiveSetsForWeek(week)` is a read-only derived getter off the shared plan template. `SessionState` never copies it into mutable session state — it reads the plan count fresh as the denominator on every build. There is no session-local concept of "this exercise got a bonus set today" or "set 2 was dropped today". So the count cannot change during a session without introducing that concept. The `routine_editor_screen.dart` precedent (mutable `weeklySets.add`/`removeLast`) mutates the plan template itself — retroactively changing every future week — which is the wrong place to touch for a one-session change.

Now is the right time: this is task 3 of the 2026-07-06 feature batch, and it is independent of the concurrent rules-hardening audit (it touches `lib/features/workout`, not Firestore rules).

Success looks like: from the current/reachable exercise in a live session, the athlete can tap "+ agregar serie" to render and log an extra set beyond the plan, and can delete a logged set; block-completion, collapse, progress ring, and the next-incomplete navigation all stay correct against the new session-local count; the change persists (extra set = a real setLog doc; removed set = a real Firestore delete) and the server ranking recompute on finish reads whatever docs exist.

## What Changes

This is a cross-cutting change, not just a button. Sized around the shared core:

1. **Session-local set-count override (`session_state.dart`)** — new field on `SessionState` tracking a per-exercise delta (or explicit per-exercise "sets today" count) that overrides the plan-derived denominator. This is the load-bearing new domain concept: everything else folds into it.

2. **`totalSets` folds in the override (`session_player_screen.dart`)** — the render loop denominator changes from `RoutineSlot.effectiveSetsForWeek(week).length` to a session-local count that adds/subtracts the override. The `for (idx=0; idx < totalSets; idx++)` loop then renders extra rows / fewer rows automatically.

3. **`SessionNotifier.addSet` / `removeSet` (`session_notifier.dart`)** — new methods:
   - `addSet(slot)` bumps the session-local override up and logs the new set (reuses the existing `logSet` write path — `logSet` has no upper-bound guard, so a `setNumber > planned` write already persists correctly).
   - `removeSet(slot, setLog)` calls the new `deleteSetLog`, decrements the override, and (per an open question below) either renumbers survivors or leaves a gap.

4. **`SessionRepository.deleteSetLog` (`session_repository.dart`)** — new method doing a real `.doc(id).delete()` (not soft-delete). Real deletion is correct: the server ranking trigger reads `setLogs` on finish and recomputes from whatever docs exist, so a deleted doc is correctly absent.

5. **Gating-math updates (`session_state.dart` / `session_notifier.dart`)** — `isFullyCompleted`, `BlockStatus`, and `_nextIncompleteIndex` currently compare `loggedCount >= plan set count`. They MUST switch to the session-local count. Otherwise: adding a 4th set to a 3-set exercise reads "done" after set 3 (block collapses, 4th row unreachable); removing a set leaves the progress ring waiting forever. **Add/remove cannot be a purely additive UI change without touching this math** — this is the crux of the change.

6. **UI affordances (`session_player_screen.dart`)** — a "+ agregar serie" button per (reachable) exercise, and a per-row delete icon on logged-set rows. Static icons over swipe for accessibility and discoverability. Scoped to the current/reachable exercise only (see open question 5).

## Impact

Files expected to change:
- `session_player_screen.dart` — render-loop denominator, "+ agregar serie" button, per-row delete icon, reachability gate for the affordances.
- `session_notifier.dart` — `addSet` / `removeSet`; gating-math (`_nextIncompleteIndex`) alignment to session-local count.
- `session_state.dart` — new session-local override field; `isFullyCompleted` / `BlockStatus` alignment to session-local count.
- `session_repository.dart` — new `deleteSetLog`.
- `set_log` domain — only if the override design needs a marker on the model (e.g. distinguishing an added set); default assumption is no domain change is required.

No Cloud Function work: ranking metrics recompute server-side on finish from `setLogs`; a real client-side `deleteSetLog` is the only persistence change. (Open question 4 asks us to *verify* `ranking-aggregate.ts` tolerates mid-session deletes — verification, not modification.)

Standards: Mint Magenta dark-only, `AppPalette.of(context)`, `TreinoIcon.X`, spacing tokens 8·12·14·18·20, Riverpod 2 (cancel streams in `dispose()`), es-AR copy ("agregar serie", "eliminar serie"). Quality gate: `flutter analyze` 0 issues + `dart format .` + tests passing.

## Out of Scope

- **Editing a logged set's reps/weight** — already works via `updateSet` / `updateSetLog`.
- **Editing completed / past (collapsed) blocks** — reach is the current/reachable exercise only. Making completed blocks reachable is a separate gap ("make completed blocks reachable") and would balloon this change. Flag to design if a strong reason to include them surfaces.
- **RPE** and any per-set metadata beyond the existing set fields.
- **Cloud Function / ranking-aggregate.ts changes** — verification only; the real client `deleteSetLog` is sufficient.

## Open Questions (for spec / design)

1. **Renumber on delete vs leave a gap.** Deleting SET 2 of 3 → renumber survivors (SET 3 → SET 2, requires extra `updateSetLog` writes) or leave a gap (render "SET 1, SET 3")?
   *Lean:* **renumber**. The row-based UI shows sequential SET N labels and a gap reads like a bug to the athlete; the extra writes are cheap and bounded (only survivors after the deleted index). Spec/design should confirm the denominator uses count, not max(setNumber), so renumbering stays a display concern.

2. **Added set: planned target (SetSpec) vs bare free-entry.** Does the extra row carry a target (reps/weight suggestion from the plan) or start empty?
   *Lean:* **bare free-entry**. An added set is by definition outside the plan; inventing a target is guesswork. Prefill from the previous logged set only if that's already the existing add-row behavior — otherwise empty.

3. **Delete confirmation dialog.** Data-loss on a logged set — confirm dialog vs quiet action (optionally undoable)?
   *Lean:* **lightweight confirm dialog** for logged sets (they hold real data). Keep it a single tap for an empty/unlogged added row that was never filled. Follow existing app dialog patterns.

4. **Verify `functions/src/ranking-aggregate.ts` tolerates mid-session setLog deletes.** The finish trigger reads `setLogs` and recomputes — a deleted doc is correctly absent, but confirm there's no caching / count-snapshot assumption that a doc count only grows.
   *Lean:* **verify during design**; expected to be a no-op, but confirm before relying on it. If it fails, that's a scope flag, not a silent fix here.

5. **Confirm reach = current/reachable exercise only.** Assumed per settled scope.
   *Lean:* **current/reachable only.** Do not extend to completed/collapsed blocks — that pulls in the separate "make completed blocks reachable" gap.

## Suggested PR Slicing (chained)

Even though add + remove ship together, they can be reviewed as two chained PRs given remove's larger surface:

- **PR 1 — add-set slice.** Session-local override field + `totalSets` fold-in + gating-math alignment + `SessionNotifier.addSet` (reuses `logSet`) + "+ agregar serie" button. This lands the entire shared core (the override + gating math) — the hard part — with the smaller, purely additive UI.
- **PR 2 — remove-set slice.** `SessionRepository.deleteSetLog` + `SessionNotifier.removeSet` + per-row delete icon + renumber-or-gap decision + confirm dialog + the `ranking-aggregate.ts` verification. Builds on the override from PR 1; adds the delete path, renumbering, and confirmation surface.

Rationale: PR 1 carries the risk-bearing gating-math changes with a small UI delta (easier to review in isolation); PR 2 is self-contained on top of it. If the review-workload forecast allows a single PR, they can still merge together — the slicing is a review convenience, not a hard split.

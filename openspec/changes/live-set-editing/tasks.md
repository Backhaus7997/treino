# Tasks: live-set-editing — add/remove sets in a live session

> Decomposes `design.md` (AD-1..AD-8) into 2 chained, independently shippable PRs, in
> ship order per design's "Chained-PR slices": **PR1 (add-set, shared core) → PR2
> (remove-set, builds on PR1)**. Every behavior change follows RED (failing
> widget/unit test against current code) → GREEN (implement until RED passes) — Strict
> TDD, mirroring `rankings-integrity`/`rules-hardening`'s structure.
>
> Traceability tags: `[REQ:workout#<requirement>]` = spec requirement (see
> `specs/workout/spec.md`); `[AD-n]` = design.md Architecture Decision; `[SITE-n]` =
> design's 9-site gating-math table (Executive summary / AD-5).
>
> Files (confirmed against current source, all paths under
> `lib/features/workout/`):
> - `application/session_state.dart` — `isFullyCompleted` (:36-39), `isExerciseDone`
>   (:52-56), `copyWith`/`==`/`hashCode` (:64-99).
> - `application/session_notifier.dart` — `logSet` (:200-253), `updateSet` (:258-293),
>   `retryLastLogError` (:298-308), `_nextIncompleteIndex` (:411-418),
>   `SessionLogAction` enum (:427).
> - `data/session_repository.dart` — `addSetLog` (:262-271), `updateSetLog` (:278-283).
> - `presentation/session_player_screen.dart` — `isStandaloneBlockComplete` (:89-93),
>   `isSupersetBlockComplete` (:96-102), `computeBlockStatuses` (:108-115),
>   `_StandaloneBlock` (:758-799), `_CompletedBlockSummary` (:864-903),
>   `_SupersetSection` (:1132-1200, round scan :1155-1167), `_ExerciseSection`
>   (:1247-1454, render loop :1313-1322).
> - Tests: `test/features/workout/application/session_state_test.dart`,
>   `session_notifier_test.dart`, `session_notifier_updateset_race_test.dart` (race
>   pattern precedent — `Completer`-based interleave), `test/features/workout/data/
>   session_repository_test.dart`, `test/features/workout/presentation/
>   session_player_screen_test.dart`.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~520-650 total (2 slices) |
| 400-line budget risk | Medium (PR1 alone is ~300-360 LOC — the 9-site gating-math thread is inherently multi-file even though each individual diff is small) |
| Chained PRs recommended | Yes |
| Suggested split | PR1 (add-set + gating core) → PR2 (remove-set) — hard dependency: PR2's `removeSet`/renumber/floor invariant reads `setCountOverride` and `plannedSetsFor`, both introduced in PR1 |
| Delivery strategy | chained PRs, work-unit commits (tests+code together per RED/GREEN pair) |
| Decision needed before apply | Yes — PR1 touches 4 files across state/notifier/screen for a single conceptual change (the resolver); confirm whether to land PR1 as one commit-set or split further into 1a (state+notifier: override+resolver+addSet) / 1b (screen: 9-site thread+UI), given AD-5 explicitly frames the 9 sites as one make-or-break correctness unit that should not be reviewed piecemeal |

### Suggested Work Units

| Unit | Goal | Likely PR | Est. LOC | Notes |
|------|------|-----------|----------|-------|
| 1 | `setCountOverride` field + `plannedSetsFor` resolver + sites 1-3 (state+notifier) + `addSet` (reuses `logSet`) + unit tests | PR1 (or 1a) | ~140-170 | `session_state.dart` (+field, +resolver, ~20 lines), `session_notifier.dart` (+`addSet`, `_nextIncompleteIndex` override-aware, ~30 lines), `session_state_test.dart`/`session_notifier_test.dart` extensions (~90-120 lines) |
| 2 | Sites 4-9 (screen: block-status fns + widgets + superset scan + render loop) threaded to resolved count + null-safe `spec` + "+ agregar serie" button + widget tests | PR1 (or 1b) | ~160-190 | `session_player_screen.dart` (~70-90 lines across 6 call sites + new button), `session_player_screen_test.dart` extensions (~90-100 lines) |
| 3 | `SessionRepository.deleteSetLog` + `SessionNotifier.removeSet` (race-safe, renumber, floor invariant) + `SessionLogAction.remove`/retry + repo/notifier tests incl. race test | PR2 | ~150-190 | `session_repository.dart` (+~10 lines), `session_notifier.dart` (+`removeSet`, ~50-60 lines), `session_repository_test.dart`/`session_notifier_test.dart`/new race-test extension (~100-130 lines) |
| 4 | Per-row delete icon + confirm dialog + `onRemoveSet` wiring + widget tests + AD-8 ranking-tolerance verification note | PR2 | ~90-120 | `session_player_screen.dart` (~40-50 lines: icon, dialog, callback), `session_player_screen_test.dart` extensions (~50-70 lines), no `functions/` change (verification only) |

---

## Phase 0 — Pre-flight (read before writing any test)

- [x] **0.1** Confirm exact current line numbers for the 9 gating-math sites against
      the file paths listed above (they will drift slightly as PR1 lands edits) — do
      not trust design.md's cited line numbers as literal after any prior edit in this
      change lands; re-`Grep` before each site's task.
- [x] **0.2** Confirm `TreinoIcon.plus` and `TreinoIcon.trash` (or equivalent registered
      glyph names) exist in the icon token file before wiring AD-6's UI — if the exact
      names differ, use the actual registered names, never `PhosphorIcons.X` directly
      (per project standards). CONFIRMED: `TreinoIcon.plus` (:77) and `TreinoIcon.trash`
      (:51) both exist in `lib/core/widgets/treino_icon.dart`.
- [x] **0.3** `[AD-8]` Read `functions/src/ranking-aggregate.ts` end to end (already
      done in design.md — this task re-confirms at apply time in case the file changed
      since design) and record: (a) trigger fires on `users/{uid}/sessions/{sessionId}`
      writes only, NOT `setLogs` subcollection writes; (b) `recomputeMetrics` re-queries
      `setLogs` fresh per session at finish time; (c) no doc-count/monotonic-growth/
      snapshot-caching assumption exists. This is a READ-ONLY verification task — it
      produces a confirmation note in the PR2 description, not a code change (see task
      3.10). DEFERRED TO PR2 (task 2.18 re-confirms immediately before that merge; not
      required to gate PR1 since PR1 makes no functions/ change).
      VERIFIED at PR2 apply-time (2026-07-06): all 3 checks pass against the current
      file. VERDICT: fully tolerant, no CF change needed.

---

## PR1 — add-set (shared core: override + resolver + 9-site gating thread)

Traceability: `[REQ:workout#Add Set During Live Session]`,
`[REQ:workout#Session-Local Set Count Drives Completion Gating]`, `[AD-1]`, `[AD-4]`,
`[AD-5]`, `[AD-6 — "+ agregar serie" only]`.

### 1a — `setCountOverride` + `plannedSetsFor` resolver (state layer)

- [x] **1.1** RED `[AD-1]` `session_state_test.dart` — add a test asserting
      `SessionState.plannedSetsFor(slot)` (method does not exist yet — RED by
      construction, mirrors `ranking-aggregate.test.ts`'s import-before-implementation
      pattern) returns `slot.effectiveSetsForWeek(session.weekNumber).length` when
      `setCountOverride` is empty (default `const {}`).
- [x] **1.2** RED `[AD-1]` extend `session_state_test.dart` — `plannedSetsFor(slot)`
      returns the override value when `setCountOverride[slot.exerciseId]` is present,
      ignoring the plan count entirely (e.g. plan=3, override=5 → returns 5).
- [x] **1.3** GREEN `[AD-1]` `session_state.dart` — add `final Map<String, int>
      setCountOverride;` field (default `const {}` via constructor default), add
      `int plannedSetsFor(RoutineSlot slot) => setCountOverride[slot.exerciseId] ??
      slot.effectiveSetsForWeek(session.weekNumber).length;`. Extend `copyWith` with a
      `Map<String, int>? setCountOverride` param, extend `==` with `MapEquality().equals`
      (or `mapEquals` from `flutter/foundation.dart`, already imported) and `hashCode`
      with `Object.hashAllUnordered(setCountOverride.entries...)` or an equivalent stable
      unordered hash (design.md AD-1's stated approach — confirm which foundation helper
      is actually available and use it, do not hand-roll). Run 1.1-1.2 to GREEN.
- [x] **1.4** RED `[SITE-1][REQ:workout#Added set keeps the exercise incomplete until
      logged]` extend `session_state_test.dart` — `isFullyCompleted` with a 3-set
      exercise, all 3 logged, `setCountOverride[exerciseId]=4` → returns `false` (today's
      `isFullyCompleted` reads `slot.effectiveSetsForWeek(week).length` directly, ignoring
      any override — confirm this test currently fails against the unmodified getter, i.e.
      the RED state, before touching production code).
- [x] **1.5** RED `[SITE-2][REQ:workout#Removed set allows completion at the reduced
      count]` extend `session_state_test.dart` — `isExerciseDone(exerciseId)` with a
      3-set exercise, override=2, both remaining logged → returns `true`; and
      `completedExerciseCount` reflects it. Confirm RED against current code first.
- [x] **1.6** GREEN `[SITE-1][SITE-2][AD-5]` `session_state.dart` — replace the inline
      `slot.effectiveSetsForWeek(session.weekNumber).length` in `isFullyCompleted` (:38)
      and `isExerciseDone` (:55) with `plannedSetsFor(slot)`. Run 1.4-1.5 to GREEN;
      re-run 1.1-1.2 to confirm no regression.

### 1b — `_nextIncompleteIndex` honors override (notifier layer)

- [x] **1.7** RED `[SITE-3][REQ:workout#Next-incomplete navigation respects the
      session-local count]` extend `session_notifier_test.dart` — seed a state with an
      exercise at override=4 (plan=3), 3 sets logged for it, 0 for the next exercise;
      assert `_nextIncompleteIndex` (invoked indirectly via `logSet`'s post-write index
      update, or directly if the method is testable in isolation) still points at the
      4-set exercise's slot, not the following one. Confirm RED against current code
      (which computes `slot.effectiveSetsForWeek(weekNumber).length` inline at :415,
      blind to any override).
- [x] **1.8** GREEN `[SITE-3][AD-5]` `session_notifier.dart` — replace the inline
      `slot.effectiveSetsForWeek(weekNumber).length` at `_nextIncompleteIndex` (:415)
      with a call to the current state's `plannedSetsFor(slot)`. Because
      `_nextIncompleteIndex` is a private notifier method invoked with `day`/`logs`/
      `weekNumber` params (not the full state), thread the override through: either add
      a `Map<String, int> setCountOverride` (or the resolver itself) as a 4th parameter
      sourced from `state.value` at each call site (`logSet`, `updateSet`,
      new `addSet`/`removeSet`), or make it a `SessionState` extension method that closes
      over `latest`. Prefer the latter — keeps the signature stable and avoids drift if a
      5th caller is added later. Run 1.7 to GREEN.

### 1c — `SessionNotifier.addSet` (reuses `logSet`)

- [x] **1.9** RED `[REQ:workout#Logging the added set persists a new document]` extend
      `session_notifier_test.dart` — `addSet(slot)` on a 3-set exercise bumps
      `state.value.setCountOverride[slot.exerciseId]` to 4 (`plannedSetsFor(slot)+1`
      computed BEFORE the bump) and does not itself write a `setLog` (only the render
      loop + a subsequent explicit `logSet` call on the new row does that — confirm this
      matches AD-2's "`addSet` reuses `logSet`" framing: `addSet` only manages the
      override; the actual persisted write happens when the athlete fills in the new
      row and taps check, going through the existing `logSet(setLog)` with
      `setNumber = new count`). Method does not exist yet — RED by construction.
- [x] **1.10** RED `[AD-2 idempotency note]` extend `session_notifier_test.dart` — two
      rapid `addSet(slot)` calls followed by two rapid `logSet` calls for the same new
      `setNumber` result in exactly one persisted doc (existing `exerciseId+setNumber`
      idempotency key in `logSet`, :207, already covers this — this test proves the
      existing guard composes with the new override bump without a new guard needed).
- [x] **1.11** GREEN `[AD-1][AD-2]` `session_notifier.dart` — implement `addSet(RoutineSlot
      slot)`: re-read `state.value`, guard `null`/`_finalized` (mirror `logSet`'s early
      return), compute `newCount = current.plannedSetsFor(slot) + 1`, emit
      `state = AsyncData(current.copyWith(setCountOverride: {...current.setCountOverride,
      slot.exerciseId: newCount}))`. No Firestore write in this method — the write
      happens through the existing `logSet` path when the new row is filled in and
      logged. Run 1.9-1.10 to GREEN.

### 1d — Sites 4-9: thread resolved count through `session_player_screen.dart` + null-safe `spec`

- [x] **1.12** RED `[SITE-4][REQ:workout#Added set keeps the exercise incomplete until
      logged]` extend `session_player_screen_test.dart` — widget test: a 3-set exercise
      with override=4 (3 logged) renders as the CURRENT/interactive block, not collapsed
      into `_CompletedBlockSummary`. Confirm RED against current code (`
      isStandaloneBlockComplete` at :89-93 reads the raw plan count, would report
      "complete" and collapse the block after 3 logs regardless of the override).
- [x] **1.13** RED `[SITE-5]` extend `session_player_screen_test.dart` — superset
      variant: a superset member with override=4 (3 logged), other member 3/3 planned+
      logged → `isSupersetBlockComplete` reports `false` (block stays open) because the
      overridden member isn't done. Confirm RED against current code (:96-102 reads plan
      count for every member, blind to overrides).
- [x] **1.14** GREEN `[SITE-4][SITE-5][AD-5]` `session_player_screen.dart` — change
      `isStandaloneBlockComplete` (:89-93) and `isSupersetBlockComplete` (:96-102)
      signatures to accept a resolved-count accessor: `int Function(RoutineSlot)
      plannedSetsFor` (simplest: pass the `SessionState.plannedSetsFor` bound method, or
      a precomputed `Map<String, int>` built once in `_buildExerciseList` per design's
      AD-5 note — prefer the `Map<String,int>` for cheap equality/const-friendliness in a
      widget tree, but confirm which the existing `computeBlockStatuses` call site can
      supply most simply). Replace `slot.effectiveSetsForWeek(week).length` internals
      with a lookup through the new parameter. Update `computeBlockStatuses` (:108-115)
      to accept and forward the same parameter to both. Run 1.12-1.13 to GREEN.
- [x] **1.15** RED `[SITE-6]` extend `session_player_screen_test.dart` — a COLLAPSED
      completed block (override=2, both logged) shows "2/2" in
      `_CompletedBlockSummary`, not "3/3" (plan count). Confirm RED against current code
      (:786 reads `entry.slot.effectiveSetsForWeek(week).length` directly).
- [x] **1.16** GREEN `[SITE-6][AD-5]` `session_player_screen.dart` — `_StandaloneBlock`
      (:758-799) threads the resolved count into `_CompletedBlockSummary.totalSets`
      (:786) instead of the raw plan-count expression. Run 1.15 to GREEN.
- [x] **1.17** RED `[SITE-7]` extend `session_player_screen_test.dart` — the interactive
      `_ExerciseSection` for an override=4 exercise renders 4 rows (not 3), and
      `currentSetNumber`/`isDone` in `_StandaloneBlock` (:797-798,802) reflect the
      override. Confirm RED against current code.
- [x] **1.18** GREEN `[SITE-7][AD-5]` `session_player_screen.dart` — `_StandaloneBlock`'s
      `totalSets`/`isDone` (:797-798) switch from `entry.slot.effectiveSetsForWeek(week)
      .length` to the resolved count via the same accessor threaded in 1.14. Run 1.17 to
      GREEN.
- [x] **1.19** RED `[SITE-8]` extend `session_player_screen_test.dart` — superset
      round-robin: a member with override=4 renders a 4th round column/row for that
      member (the `maxRounds` scan, :1155-1156) without throwing, and the per-round scan
      (:1167) does not skip the 4th round for the overridden member. Confirm RED against
      current code (both lines read `e.slot.effectiveSetsForWeek(week).length` directly).
      Per settled scope (AD-5 superset note), this is a GATING-ONLY correctness fix — no
      add/remove UI is placed inside a superset block this change; the test only proves
      the math doesn't desync if an override happens to exist on a superset member via
      some other path (defensive correctness, not a reachable UI flow yet).
- [x] **1.20** GREEN `[SITE-8][AD-5]` `session_player_screen.dart` — `_SupersetSection`'s
      `maxRounds` fold (:1155-1156) and round-bound check (:1167) switch to the resolved
      count via the same accessor. Run 1.19 to GREEN.
- [x] **1.21** RED `[SITE-9][AD-4 null-safety]` extend `session_player_screen_test.dart`
      (or a new `_ExerciseSection`-focused test) — with override=4 on a 3-set exercise,
      the render loop draws a 4th row with no crash, no planned target text ("10 reps" /
      "8-12" style hint absent), and the row is bare/empty (reps=0, weight=0, no
      prefill). Confirm RED against current code — `final spec = effectiveSets[idx];` at
      :1322 throws a `RangeError` for `idx >= effectiveSets.length` today.
- [x] **1.22** GREEN `[SITE-9][AD-4]` `session_player_screen.dart` — `_ExerciseSectionState`
      (:1277-1454): (a) change `totalSets` (:1315) from `effectiveSets.length` to the
      resolved count (via the accessor/override lookup); (b) change the render loop
      (:1322) to `final SetSpec? spec = idx < effectiveSets.length ? effectiveSets[idx] :
      null;`; (c) guard every downstream `spec.` read in the row builders
      (`_RepsSetRow`/`_DurationSetRow` or wherever `spec.durationSeconds`/`spec.weightKg`/
      `spec.type` are read) to branch on `spec == null` → bare/empty target (`plannedReps
      = 0`, `plannedWeight = 0`, no prescription hint text), no crash. Run 1.21 to GREEN;
      re-run 1.17 to confirm the 4th row now actually renders (not just doesn't throw).
- [x] **1.23** `[AD-4 rejected-alternative regression guard]` extend
      `session_player_screen_test.dart` — an added (null-spec) row does NOT prefill from
      the previous logged set's reps/weight (confirms AD-4's "bare, not synthesized"
      decision — a plain assertion, not a RED/GREEN pair, since 1.22's implementation
      already produces this if done correctly; this task exists to make the invariant
      explicit and regression-proof).

### 1e — "+ agregar serie" UI affordance

- [x] **1.24** RED `[REQ:workout#Add button renders an extra loggable row]` extend
      `session_player_screen_test.dart` — tapping a "+ agregar serie" button (find by
      key or text `agregar serie`) on the current/reachable exercise section renders one
      new empty row below the last, numbered sequentially. Button does not exist yet —
      RED by construction.
- [x] **1.25** RED `[REQ:workout#Adding a set is only available on the current/reachable
      exercise]` extend `session_player_screen_test.dart` — a COMPLETED/collapsed block
      (rendered via `_CompletedBlockSummary`) does NOT show "+ agregar serie" anywhere in
      its subtree. Confirm RED is vacuous until 1.26 lands the button (i.e. this test
      should already pass trivially pre-GREEN since no button exists yet anywhere —
      note this explicitly in the test comment as a forward-guard, not a true RED; the
      real assertion value is proving 1.26 does not accidentally also add it to the
      collapsed summary).
- [x] **1.26** GREEN `[AD-6]` `session_player_screen.dart` — add a full-width subtle
      button appended after the last row inside `_ExerciseSection`'s `Column` (~after
      the row-widgets loop, :1385 region per design), rendered ONLY when the section is
      the interactive current/hand-activated block (never in `_CompletedBlockSummary`'s
      subtree) and disabled while a `logSet`/`addSet` write is in flight (reuse the
      existing disabled-during-write posture from the log button). Icon: the registered
      add glyph confirmed in task 0.2 (`TreinoIcon.plus` or actual name — never
      `PhosphorIcons.X`). Copy: `agregar serie` (es-AR). Wires a new `onAddSet(slot)`
      callback threaded down from `_buildExerciseList` to `notifier.addSet(slot)`. Theme:
      `AppPalette.of(context)`, spacing tokens 8·12·14·18·20, no HEX literals. Run
      1.24-1.25 to GREEN.

### PR1 gate

- [x] **1.27** `[GATE]` `flutter analyze lib test` — 0 new issues vs. this branch's
      pre-change baseline (record the baseline count before starting, per
      `rankings-integrity`'s precedent of stating the actual measured baseline rather
      than an estimate).
- [x] **1.28** `[GATE]` `dart format .` scoped to touched files (`session_state.dart`,
      `session_notifier.dart`, `session_player_screen.dart`, and the 3 touched test
      files) — full-repo format is out of scope per project convention (avoids drifting
      unrelated files).
- [x] **1.29** `[GATE]` `flutter test test/features/workout/application/
      session_state_test.dart test/features/workout/application/session_notifier_test.dart
      test/features/workout/presentation/session_player_screen_test.dart` — all green,
      including every RED case from 1.1-1.26 now passing and no regression in the
      existing (pre-change) test cases in those 3 files.
- [x] **1.30** `[GATE]` `flutter test` (full suite) — green, 0 new failures vs. the
      pre-change baseline (confirms the 9-site thread didn't silently break an unrelated
      screen/widget that also calls `effectiveSetsForWeek` in a way this change touched).
- [x] **1.31** Commit as one or two work-unit commits per the decision in the
      Review-Workload "Decision needed before apply" row (1a+1b+1c state/notifier layer,
      then 1d+1e screen layer — OR all as one commit if the reviewer confirms a single
      PR1 commit is preferred). Conventional commits, no AI attribution.

---

## PR2 — remove-set (builds on PR1's override + resolver)

Traceability: `[REQ:workout#Remove Set During Live Session]`,
`[REQ:workout#Server-Side Recompute Reads Surviving SetLogs Only]`, `[AD-2]`, `[AD-3]`,
`[AD-6 — delete icon + confirm dialog]`, `[AD-7]`, `[AD-8]`.

### 2a — `SessionRepository.deleteSetLog`

- [x] **2.1** RED `[AD-2][REQ:workout#Confirmed removal deletes the underlying
      document]` `session_repository_test.dart` — against `fake_cloud_firestore`, seed a
      `setLog` doc, call `deleteSetLog(uid:, sessionId:, setLogId:)` (method does not
      exist yet — RED by construction), assert the doc is gone via a subsequent
      `listSetLogs` or direct doc-get returning null/not-exists. Assert it is a HARD
      delete, not a soft-delete flag (no lingering doc with a `deleted:true` marker).
- [x] **2.2** GREEN `[AD-2]` `session_repository.dart` — add `Future<void> deleteSetLog({
      required String uid, required String sessionId, required String setLogId}) async =>
      _setLogs(uid, sessionId).doc(setLogId).delete();` mirroring `updateSetLog`'s shape
      (:278-283). Run 2.1 to GREEN.

### 2b — `SessionNotifier.removeSet` (race-safe, renumber, floor invariant)

- [x] **2.3** RED `[AD-2][REQ:workout#Removing an unlogged set requires no confirmation]`
      extend `session_notifier_test.dart` — `removeSet(slot, null)` (or however an
      unlogged-pending-row removal is signaled — target `SetLog?` is `null` or an
      unpersisted placeholder) on an exercise with override=4 (3 logged, 4th
      unlogged/pending) lowers `setCountOverride[exerciseId]` to 3 and does NOT call
      `repo.deleteSetLog` (nothing was persisted). Method does not exist yet — RED by
      construction.
- [x] **2.4** RED `[AD-2][AD-3][REQ:workout#Confirmed removal deletes the underlying
      document][REQ:workout#Removing a set renumbers surviving sets]` extend
      `session_notifier_test.dart` — `removeSet(slot, target)` where `target` is a real
      logged `SetLog` (setNumber=2 of 3 logged) calls `repo.deleteSetLog` with `target.id`,
      then calls `repo.updateSetLog` for the one survivor above the gap (old setNumber=3
      → new setNumber=2), and updates local `setLogs` + `setCountOverride[exerciseId]`
      to 2 in one state emission.
- [x] **2.5** RED `[AD-5 floor invariant][REQ:workout#Session-Local Set Count Drives
      Completion Gating]` extend `session_notifier_test.dart` — write-time floor: calling
      `removeSet` cannot drop `setCountOverride[exerciseId]` below the CURRENT logged
      count for that exercise after the removal completes (i.e.
      `override = max(newCount, loggedCountAfterRemoval)`) — construct a case that would
      violate the floor without the guard and assert the guard holds.
- [x] **2.6** RED `[AD-2 race discipline]` extend
      `session_notifier_updateset_race_test.dart` (or a new sibling
      `session_notifier_removeset_race_test.dart` mirroring its `Completer`-based
      interleave pattern) — a `logSet` completing DURING a `removeSet` await (or vice
      versa) survives: the later-resolving state emission re-reads `state.value` (not
      the stale `current` captured before the await) so neither write is silently lost.
      Mirror the exact interleave harness already proven in
      `session_notifier_updateset_race_test.dart`.
- [x] **2.7** GREEN `[AD-2][AD-3][AD-5]` `session_notifier.dart` — implement
      `removeSet(RoutineSlot slot, SetLog? target)` per design.md AD-2's sketch: re-read
      `state.value`, guard `null`/`_finalized`, resolve `uid`; if `target != null &&
      target.id.isNotEmpty`: call `repo.deleteSetLog`, then for every survivor of the
      same exercise with `setNumber > target.setNumber` (ascending order) call
      `repo.updateSetLog` with `setNumber - 1` (renumber, AD-3); re-read `state.value` as
      `latest` AFTER all awaits; compute `newLogs` (drop the deleted log id, apply
      renumber to survivors), `newCount = max(latest.plannedSetsFor(slot) - 1,
      loggedCountFor(exerciseId, newLogs))` (the floor), `newOverride = {...latest
      .setCountOverride, exerciseId: newCount}`, `newIndex = _nextIncompleteIndex(...)`;
      emit `state = AsyncData(latest.copyWith(setLogs: newLogs, setCountOverride:
      newOverride, currentExerciseIndex: newIndex))`. On any thrown error: do NOT flip
      `state` to `AsyncError` (mirror `logSet`/`updateSet`'s error-channel discipline) —
      emit `_logSetError.value = SessionLogError(action: SessionLogAction.remove,
      setLog: target ?? <sentinel/placeholder representing the pending row>)`. Run
      2.3-2.6 to GREEN.
- [x] **2.8** RED `[AD-2 retry]` extend `session_notifier_test.dart` —
      `retryLastLogError()` re-dispatches to `removeSet` when the pending error's
      `action == SessionLogAction.remove`. Confirm RED against current code (the
      `switch` in `retryLastLogError`, :302-307, has no `remove` case — this is a
      compile-time exhaustiveness gap once the enum gains a member, so this test also
      guards that the switch was updated, not just that it dispatches correctly).
- [x] **2.9** GREEN `[AD-2]` `session_notifier.dart` — add `remove` to the
      `SessionLogAction` enum (:427) and a `case SessionLogAction.remove: await
      removeSet(pending.slot, pending.setLog);` arm in `retryLastLogError`'s switch
      (:302-307) — note `SessionLogError` will need a `slot`/exercise reference alongside
      `setLog` if `removeSet` requires the `RoutineSlot`, not just the log; extend
      `SessionLogError`'s shape accordingly if the existing `log`/`update` cases don't
      already carry enough context (check `SessionLogError`'s current fields before
      assuming it needs no change). Run 2.8 to GREEN.

### 2c — Per-row delete icon + confirm dialog

- [x] **2.10** RED `[REQ:workout#Removing an unlogged set requires no confirmation]`
      extend `session_player_screen_test.dart` — tapping the delete icon on an
      added-but-unlogged pending row removes it immediately with NO dialog shown.
      Icon does not exist yet — RED by construction.
- [x] **2.11** RED `[REQ:workout#Removing a logged set surfaces a confirmation]` extend
      `session_player_screen_test.dart` — tapping the delete icon on a LOGGED row shows
      a confirm dialog (title `Eliminar serie`, body `Se va a borrar esta serie
      registrada.`, actions `Cancelar`/`Eliminar`) and does NOT call `removeSet` until
      `Eliminar` is tapped; tapping `Cancelar` leaves the row untouched.
- [x] **2.12** RED `[REQ:workout#Removing a set is only available on the current/
      reachable exercise]` extend `session_player_screen_test.dart` — a COMPLETED/
      collapsed block does not show the per-row delete icon anywhere in its subtree
      (mirrors 1.25's forward-guard structure for the add button).
- [x] **2.13** GREEN `[AD-6]` `session_player_screen.dart` — add a trailing delete icon
      (the registered trash glyph confirmed in 0.2, static, not swipe) to each row of the
      interactive section (both logged rows and an added-but-unlogged pending row), never
      rendered in `_CompletedBlockSummary`'s subtree. Wire `onRemoveSet(slot, log?)`:
      for a `null`/unlogged target, call `notifier.removeSet(slot, null)` directly (no
      dialog); for a logged target, show the confirm dialog first (existing app dialog
      pattern, same family as the abandon-session dialog) and call `notifier.removeSet
      (slot, log)` only on confirm. Theme: `AppPalette.of(context)`, spacing tokens,
      `TreinoIcon.X` only. Run 2.10-2.12 to GREEN.
- [x] **2.14** RED `[REQ:workout#Removing a set renumbers surviving sets]` extend
      `session_player_screen_test.dart` — after confirming removal of set 2 of a 3-logged
      exercise, the UI shows sets numbered 1 and 2 (no visible gap, no "SET 1, SET 3").
- [x] **2.15** GREEN — confirm 2.7's renumber (server-side via `updateSetLog`) plus
      1.22's render-loop-by-index (which draws `SET idx+1` sequentially regardless of
      the underlying doc's stored `setNumber`, since the row label is positional) already
      satisfies this with no additional code change. Run 2.14 to GREEN; if it fails,
      the render loop is reading `setNumber` instead of positional index somewhere —
      fix there, not by adding new renumber logic.
- [x] **2.16** RED `[AD-5 mid-remove reopen guard][REQ:workout#Removed set allows
      completion at the reduced count]` extend `session_player_screen_test.dart` —
      deleting the LAST logged set of an otherwise-fully-logged 3-set exercise (2
      remain logged, override drops to 2, both logged) keeps/returns the block to
      `current` (not `completed`) ONLY if the 2 remaining aren't both done yet; and
      separately, if both remaining ARE done, the block correctly shows `completed` at
      the reduced count (progress ring does not wait for a 3rd set that no longer
      exists). Cover both sub-cases explicitly — this is the AD-5 "removed-below-logged"
      invariant made visible in the widget layer, not just the notifier layer (2.4/2.5
      already cover the notifier side).
- [x] **2.17** GREEN — confirm PR1's threaded resolver (1.14/1.16/1.18) plus 2.7's floor
      invariant already produce this with no additional code change. Run 2.16 to GREEN;
      if it fails, trace which of the 9 sites is still reading a stale count.

### 2d — AD-8 ranking-tolerance verification (check, not code)

- [x] **2.18** `[VERIFY]` `[AD-8][REQ:workout#Finish recompute reflects added and removed
      sets]` Re-confirm task 0.3's read of `functions/src/ranking-aggregate.ts` against
      the state of that file AT THIS POINT in the change (PR2, immediately before merge)
      — no code in this repo touches that file during this change, so this task is a
      pass/fail documentation check: (a) the trigger does not fire on `setLogs` writes;
      (b) `recomputeMetrics` re-queries `setLogs` fresh at finish; (c) no count-snapshot
      assumption. Record the verdict ("VERIFIED SAFE, no CF change needed" per design.md
      AD-8) in the PR2 description. If ANY of the three checks fails against the
      current file state, STOP — this becomes a scope flag requiring a design amendment,
      not a silent fix inside this task.

### PR2 gate

- [x] **2.19** `[GATE]` `flutter analyze lib test` — 0 new issues vs. PR1's post-merge
      baseline.
- [x] **2.20** `[GATE]` `dart format .` scoped to touched files (`session_repository.dart`,
      `session_notifier.dart`, `session_player_screen.dart`, and the 4 touched/new test
      files).
- [x] **2.21** `[GATE]` `flutter test test/features/workout/data/session_repository_test.dart
      test/features/workout/application/session_notifier_test.dart
      test/features/workout/application/session_notifier_updateset_race_test.dart
      test/features/workout/presentation/session_player_screen_test.dart` (+ the new
      remove-race test file if created as a sibling rather than folded in) — all green.
- [x] **2.22** `[GATE]` `flutter test` (full suite) — green, 0 new failures vs. PR1's
      post-merge baseline.
- [x] **2.23** Commit as one or two work-unit commits (2a+2b notifier/repo layer, then
      2c+2d UI/verification layer — or as one commit per reviewer preference).
      Conventional commits, no AI attribution.

---

## Rules Applied

- Every GREEN task preceded by its RED (failing test) task, Strict TDD, mirroring
  `rankings-integrity`/`rules-hardening`'s structure. Tasks 2.15/2.17 are explicit
  "confirm no new code needed" checks, not silent skips — they exist because design.md's
  AD-3/AD-5 predict these invariants fall out of PR1's resolver + PR2's floor for free;
  if the RED test in the paired task fails, that prediction was wrong and needs a real
  fix, not a re-write of the test.
- The 9-site gating-math thread (PR1, tasks 1.4-1.22) is the headline risk per design.md
  — each site has its own RED/GREEN pair rather than one combined task, so a reviewer
  can verify render-vs-completion consistency site-by-site instead of trusting one
  broad "refactored gating" commit.
- `SetSpec?` null-safety guard (task 1.21-1.22) is treated as its own RED/GREEN pair,
  not folded into the render-loop-bound change, because it is a distinct failure mode
  (crash vs. silent miscount) called out explicitly in design.md's Risks section.
- AD-8's ranking-tolerance check (tasks 0.3, 2.18) is a verification task, not a code
  task — encoded as an explicit checklist item with a STOP condition if verification
  fails, per the SDD task instructions, rather than silently assumed safe.
- Quality gate per phase: `flutter analyze lib test` 0 new issues (baseline measured at
  phase start, not estimated), `dart format .` scoped to touched files, `flutter test`
  (scoped then full suite) green.
- Conventional commits, no AI attribution, work-unit commits (tests + implementation
  together per RED/GREEN pair, per delivery strategy).
- No `functions/` or `firestore.rules` changes in this entire task list — confirmed by
  design.md AD-8 and re-verified at tasks 0.3/2.18; if apply-time discovery contradicts
  this, STOP and flag rather than silently expanding scope.

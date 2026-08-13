# Design — Repetir plan completado (completion = signal, not lock)

Closes decision **A1** (`plan_gating.dart:20-24`, 2026-06-29) by removing the two
hard locks it left standing. Pure client-side UI + a deleted gating layer. No
model, no provider, no schema, no rule, no migration.

Read dependency: `proposal.md` (approved), engram `sdd/repetir-plan-completado/proposal`
(#497), `discovery/periodized-cta-gate-order` (#498). Source verified:
`routine_detail_screen.dart` (`_PeriodizedCTABar` L905-1115, `_StartSessionCTABar`
L1156-1219), `plan_gating.dart`, `plan_progress.dart`, `treino_icon.dart`,
`intl_{es_AR,es,en}.arb`, `routine_detail_periodized_test.dart`,
`plan_gating_test.dart`. Call sites grepped across `lib/`.

Product decision **D1 = (a)**: keep the completed badge/banner **and** add a
distinct REPETIR action. Closed by the user; scenarios may freeze.

---

## Technical Approach

`_PeriodizedCTABar.build` is today a chain of four early returns — `planComplete`
(L944) → `alreadyDone` (L1008) → `weekLocked || dayLocked` (L1040) → `EMPEZAR`
(L1074). Three of the four return **no action**. The device bug is not "one wrong
condition": it is that **any** upstream branch can silently swallow the only exit.

The restructure removes the chain, not a branch. The CTA becomes **two slots**:

- **SIGNAL** — 0 or 1 widget, precedence-ordered, purely informational.
- **ACTION** — exactly one button, **unconditional**, label keyed off `alreadyDone`.

`planComplete` and `alreadyDone` keep being computed **identically**
(`plan_progress.dart` untouched, `derivePlanProgress` untouched). They stop
*routing* and start *labelling*. That is the whole change.

---

## Architecture Decisions

### AD-1 — CTA shape: one signal slot + one unconditional action

**Decision.** Replace the four early returns with a single `Column` inside the
existing `Padding(vertical: 18)` (today that padding is copy-pasted into all four
branches — hoisting it removes the duplication):

```dart
data: (progress) {
  final alreadyDone =
      progress.completed.contains((week: viewedWeek, day: viewedDay));
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Column(
      children: [
        // SIGNAL — never gates. Plan-scoped wins over day-scoped.
        if (progress.planComplete)
          const _PlanCompleteBanner()
        else if (alreadyDone)
          const _CompletedDayChip(),
        if (progress.planComplete || alreadyDone) const SizedBox(height: 12),
        // ACTION — unconditional for athletes. No completion state removes it.
        _buildSessionCTA(context, ref, isRepeat: alreadyDone),
      ],
    ),
  );
}
```

**Why this shape.**
- **The button appears once**, so "don't duplicate it across 3 branches" is solved
  structurally, not by discipline. There is no branch to forget.
- **The invariant is local.** A reader sees, in one screen of code, that no
  completion state returns without an action. Today that question needs a trip to
  another file (`plan_gating.dart`) — the exact trip the exploration got wrong.
- **`if/else if` on the signal preserves today's mutual exclusion.** Banner XOR
  chip. That exclusion is currently an accident of the early-return order, but it
  is the right UX: "PLAN COMPLETADO" stacked above "COMPLETADO" is the same fact
  said twice. Making it explicit turns an accident into a decision.
- **Order: signal above, action below.** Reading order is state → action, and the
  button keeps the exact screen position it holds for a fresh day, so the primary
  action never moves between states.

**Extraction.** `_PlanCompleteBanner` and `_CompletedDayChip` become private
`StatelessWidget`s (no `ref` needed) — idiomatic for this file (20+ private
widgets) and it makes "signal" legible as a type, not a comment. The action stays
inline in `build`: it needs `ref` (analytics) and `context` (`push`), and it has
exactly one call site, so extracting it would buy nothing.

**Precise scope of "unconditional".** The trainer guard (L924), `loading`, and
`error` still return early. Those are **states, not gates** — a trainer is not an
athlete being blocked, and a CTA cannot render over data that has not arrived.

**Alternatives rejected.**
| Option | Why not |
|---|---|
| Keep early returns, add a button to each of the 3 branches | Same shape that produced the bug. Three copies of the exit = three chances to lose one. Loudly rejects the user's "no hidden locks" directive. |
| Render banner **and** chip when both are true | Redundant copy; adds a third stacked element to the common 9/9 case (R5 overflow surface). |
| Label keyed off `planComplete` | Wrong for the WPRES edge (below): a never-done day on a complete plan would read REPETIR while nothing was ever done. |

### AD-2 — ADR: completion is a **signal**, not a lock (closes A1)

**Decision.** A completed `(week, day)` — and a completed plan — MUST NOT remove,
disable, or hide the start action. Completion may only change **copy** (a badge,
a banner, a label). This is the canonical rule; it now has one enforcement point
(AD-1's unconditional action) and one regression net (T-4 below).

**This is not a new policy.** A1 already wrote it verbatim (`plan_gating.dart:20-24`):

> *"drop the lock entirely… The athlete is an adult and knows what they are doing…
> The only signal we keep is 'this day is already completed'* **(drives the
> 'ENTRENADO' badge, not a hard lock)**".

A1 then shipped `isWeekUnlocked`/`isDayUnlocked` as `=> true` but left
`alreadyDone` and `planComplete` early-returning in the CTA — locks contradicting
the sentence that removed the locks. **This change finishes A1; it does not
reverse it.** The proposal's §3 correction stands: both branches are independent
hard locks, `planComplete` fires first, and patching only `alreadyDone` ships
inert (verified: L944 early-returns before L1008 is reachable).

**Unchanged on purpose.** `derivePlanProgress` still computes `planComplete` and
`completed` exactly as today. `todaysRoutineProvider`'s infinite rollover was never
wrong — it was only *contradicted* by this screen. Both stay.

### AD-3 — Retire the gating layer entirely: delete `plan_gating.dart`

**SCOPE DELTA vs proposal §2**, surfaced here because the two decisions interact.
The proposal deletes `isStartable` and defers the `isWeekUnlocked`/`isDayUnlocked`
call-site cleanup. After AD-1 that deferral is no longer available: **it is the
last early return in the file.**

**Grepped facts (all of `lib/`, worktrees excluded):**
- `isStartable` — **0** call sites.
- `isWeekUnlocked`/`isDayUnlocked` — **exactly 2**, both in `_PeriodizedCTABar`
  (L989, L995). `plan_gating.dart` is imported by **one** file (L15).
- The widget's local `requiredPairs` loop (L978-986) feeds **only** those two
  calls. `alreadyDone` never reads it. (`session_providers.dart:226` computes its
  own — untouched.)

**Decision.** Delete the `weekLocked || dayLocked` branch, the two calls, the
`requiredPairs` loop, `plan_gating.dart`, and `plan_gating_test.dart`.

**Why the whole file, not just `isStartable`.** Once AD-1 lands, the file has zero
call sites. Keeping it means **2 dead functions + 8 tautology tests** — the
proposal's own "false-confidence mine" argument against `isStartable`, scaled up.
There is no half measure: either the locked branch survives (and the file lives to
serve it), or it does not (and the file is orphaned). Keeping a provably-dead
early return that returns no button, in the very change whose thesis is "no lock
sits upstream of the action", makes the invariant a **coincidence** — it holds
only because two functions in another file happen to return a literal — instead of
a **structural property** of the widget.

**Delete over repurpose.** Post-change, `isStartable`'s only honest body is
`=> true`. A function that returns a constant is not an abstraction, it is a
redirect. Same for the other two.

**Blast radius, priced honestly:**
| Loss | Replacement |
|---|---|
| 6 `isStartable` tests asserting `completed → not startable` | Nothing. They encode the **opposite** of the shipped policy — the proposal is right that they are a mine. |
| 8 `isWeekUnlocked`/`isDayUnlocked` tests ("always unlocked") | T-4. These 8 assert a literal (`expect(true, isTrue)`). They can only fail if someone edits the function — impossible once it is gone. T-4 asserts the **action exists**, which is strictly stronger than "no lock function returned false". |
| The A1 rationale (file header — currently its only written record, cited by the proposal) | Migrates to `openspec/specs/periodized-plan-repeat/spec.md` (the proposal already designates the spec as canonical home for these semantics) + AD-2 above. Net: the rationale gains a better home. |
| `routineDetailWeekLocked` / `routineDetailDayLocked` ARB keys lose their only render site | Delete the keys ×3 ARBs. They are the copy for a lock the product no longer has; leaving them invites someone to render them again. Low-stakes — if the regen diff argues otherwise, leaving them is acceptable. |

`flutter analyze` catches any missed reference (the unused `plan_gating.dart`
import and a possibly-unused `CompletedKey` import become warnings). **R2 confirmed
Low.**

### AD-4 — No new `TreinoIcon` token. No icon on REPETIR.

**Decision.** `treino_icon.dart` is **untouched** — dropped from the proposal's
affected-areas list.

**Why.** The proposal assumed a repeat/refresh token was needed. Reading the file
says otherwise: **neither** start button in this screen has ever had an icon —
`_StartSessionCTABar` (L1189-1213) and the periodized CTA (L1079-1107) are both a
bare `ElevatedButton` + `Text`. REPETIR occupies that same slot with the same
accent pill and the same `Size.fromHeight(56)`; only the label changes. Adding an
icon would make the repeat action **visually heavier than the primary action** it
mirrors, and would mint a `TreinoIcon` constant with exactly one use.

The completion *signal* already owns the iconography (`TreinoIcon.check` on both
banner and chip) — which is precisely AD-2's split: the icon says "done", the
button says "go".

### AD-5 — Copy & ARB

**New key: `routineDetailRepeat`.** Sibling of `routineDetailStart` — same
`routineDetail` + PascalCase-semantic pattern as `routineDetailCompleted` /
`routineDetailPlanComplete`, and it names the **action**, matching its neighbor.
`routineDetailRepeatDay` was rejected: the CTA is already day-scoped by context,
and the sibling is `…Start`, not `…StartDay`.

| File | Entry | Note |
|---|---|---|
| `intl_es_AR.arb` (template) | `"routineDetailRepeat": "REPETIR"` + `"@routineDetailRepeat": {}` | Follows the cluster's empty-metadata shape. |
| `intl_es.arb` | `"routineDetailRepeat": "REPETIR"` | **No `@key` entry** — this file has none. |
| `intl_en.arb` | `"routineDetailRepeat": "REPEAT"` + `"@routineDetailRepeat": {}` | **Filled, not `""`.** |

**Why EN gets a real string (R6).** The whole `routineDetail*` cluster is `""` in
EN — a pre-existing gap. Extending it here is not symmetric with the neighbors: a
blank *badge* is cosmetic, a blank *action button* is an unusable control. This
change exists to guarantee the athlete an exit; shipping `""` on the exit ships
the wall in EN. One filled key. The rest of the EN gap stays out of scope (filing
it, not silently widening it).

**"PLAN COMPLETADO" keeps its text. So does "COMPLETADO".** The banner states a
fact that is still true — the plan *is* complete — and states nothing about
finality: no "FIN", no "no hay más". Under AD-2 the signal's job is to state,
the action's job is to afford. Folding the affordance into the copy
(*"PLAN COMPLETADO — repetí cuando quieras"*) would re-merge the two concerns
this design just separated, and the REPETIR button already says it, in the one
place a user taps. **Bonus:** zero churn on existing keys ⇒ no regen risk on them,
and SCENARIO-036's `find.text('PLAN COMPLETADO')` stays valid.

**Label rule (single decision point):**
`alreadyDone ? l10n.routineDetailRepeat : l10n.routineDetailStart` — keyed off the
**day**, never the plan. See T-3.

---

## Data Flow

```
sessionsByUidProvider ──→ planProgressProvider ──→ PlanProgress
   (unchanged)              (unchanged)            (planComplete, completed)
                                                            │
                                                            ▼
                                              _PeriodizedCTABar.build
                                                            │
                     ┌──────────────────────────────────────┴──────────────────┐
                     ▼ SIGNAL (0 or 1, precedence)                             ▼ ACTION (always)
        planComplete → PLAN COMPLETADO banner                   alreadyDone ? REPETIR : EMPEZAR
        alreadyDone  → COMPLETADO chip                          → /workout/session/{id}/{day}?week=N
        neither      → nothing                                     (route unchanged)
```

No provider graph delta. No new watch, no new `select`, no rebuild-budget change.

---

## File-Level Change Map

| File | Action | Change |
|---|---|---|
| `lib/features/workout/presentation/routine_detail_screen.dart` | Modify | `_PeriodizedCTABar`: 4 early returns → signal `Column` + unconditional action (AD-1). Delete `requiredPairs` loop, both gating calls, the locked branch (AD-3). Drop `plan_gating.dart` import (+ `CompletedKey` if analyzer flags it). Add `_PlanCompleteBanner`, `_CompletedDayChip`. Update the class doc comment (`REQ-PERIOD-033/034` no longer apply; point at the new spec). |
| `lib/features/workout/application/plan_gating.dart` | **Delete** | Zero call sites post-AD-1/AD-3. A1 rationale migrates to the spec. |
| `test/features/workout/application/plan_gating_test.dart` | **Delete** | Tests a deleted file. |
| `lib/l10n/intl_es_AR.arb` · `intl_es.arb` · `intl_en.arb` | Modify | `+routineDetailRepeat`; `-routineDetailWeekLocked`, `-routineDetailDayLocked`. Regen `app_l10n*.dart`. |
| `test/features/workout/presentation/routine_detail_periodized_test.dart` | Modify | T-1..T-4 below. |
| `openspec/specs/periodized-plan-repeat/spec.md` | New (`sdd-spec`) | Canonical home for AD-2 + the orphaned `REQ-PERIOD-037` semantics + A1's rationale. |

**Untouched (verified):** `plan_progress.dart`, `todays_routine_provider.dart`,
`_StartSessionCTABar`, `session_notifier/init/providers`, `treino_icon.dart`
(AD-4), `firestore.rules`, `firestore.indexes.json`.

---

## Testing Strategy

Harness constraint (read, not assumed): `_wrap` mounts a bare
`MaterialApp(home: Scaffold(...))` — **no go_router**. A `tap → route` assertion
would need a new harness. Not worth it: assert the widget contract instead.

> `find.text('EMPEZAR')` `findsNothing` no longer means *"there is no action"* — it
> means *"the action is labelled REPETIR"*. Every rewritten test carries that
> `reason:` inline, or the next reader restores the old meaning in good faith.

| # | Test | Assertion |
|---|---|---|
| **T-1** | **SCENARIO-035 rewrite** — completed day, **incomplete** plan (1 of 4 sessions done) | `COMPLETADO` `findsOneWidget` (signal survives) · `REPETIR` `findsOneWidget` · `EMPEZAR` `findsNothing` (label switched) · **`onPressed != null`** on the button. |
| **T-2** | **SCENARIO-036 extension** — 4/4 done, `planComplete` — **the device repro** | Keep `PLAN COMPLETADO` `findsOneWidget` · **add** `REPETIR` `findsOneWidget` + `onPressed != null` · **add** `find.text('COMPLETADO')` `findsNothing` (pins AD-1's banner-XOR-chip; exact match, does not collide with `PLAN COMPLETADO`). **This is the only test on the true repro path — today it is blind to a missing button.** |
| **T-3** | **New** — `planComplete` + viewed day with **zero present slots** that week (WPRES edge, discovery #498) | banner renders · **`EMPEZAR`**, not `REPETIR` (`alreadyDone == false` — that day was never done). Pins AD-5's label rule to the day, not the plan. Fixtures exist inline (`slotPresentOnlyWeek2`, L422). |
| **T-4** | **New** — the AD-2 invariant, over all 3 completion states (fresh · day done · plan done) | An enabled `ElevatedButton` renders in **every** state. This is the net that replaces the 14 deleted `plan_gating` tests — and it is stronger: it asserts the **action exists**, where the old ones asserted a function returned a literal and the `BLOQUEADO findsNothing` test asserts *absence of copy* (which also passes when the widget renders blank). |

`onPressed != null` via
`tester.widget<ElevatedButton>(find.ancestor(of: find.text('REPETIR', skipOffstage: false), matching: find.byType(ElevatedButton)).first)`.
The CTA sits below the fold — `skipOffstage: false` everywhere, per the file's
existing convention.

**Unchanged:** `plan_progress_test.dart` (AD-2 — the derivation does not move).
The `BLOQUEADO/BLOQUEADA findsNothing` test (L306) stays green but becomes
tautological once the copy is gone; harmless, superseded by T-4 — deleting it is
optional cleanup, not this change's business.

**Gate:** `flutter analyze` 0 new issues (main baseline: 41) · `dart format .` ·
`flutter test` green (~3852 − 14 deleted + 2 new).

---

## Risks

| # | Risk | L | Mitigation |
|---|---|---|---|
| R1 | **Apply patches only `alreadyDone`; device bug survives** | **High** | AD-2 + AD-1 delete the chain wholesale — there is no `alreadyDone`-only patch to write. **T-2** is the net on the real repro path. |
| R2 | Deleting `plan_gating.dart` breaks a call site | Low | 0 for `isStartable`, 2 for the others, both deleted by AD-3. Import grep: 1 file. `flutter analyze` catches any miss. |
| R3 | Test rewrite rubber-stamps the diff | Med | Scenarios derive from the spec, authored pre-apply. T-4 is written against the **invariant** (AD-2), not the implementation. |
| R5 | Banner + button layout overflow (cf. the recent agenda 1px class) | Low | AD-1's XOR keeps the common 9/9 case at **2** stacked elements (banner + button), not 3. Widget tests pump the standard viewport. |
| R7 | *(new)* AD-3 scope delta lands with the proposal's "deferred cleanup" note stale | Low | AD-3 is flagged as a delta. If a reviewer insists on proposal scope, the fallback is to keep the locked branch — **but then AD-2's invariant is a coincidence, not a property**, and the file keeps a button-less early return. Say so explicitly in the PR rather than shipping it silently. |

**Non-goals** (all verified nil-risk in proposal §6, re-verified here):
`todays_routine_provider` · `_StartSessionCTABar` (single-week, already correct —
diff is entirely inside `numWeeks > 1`) · `session_notifier/init/providers` ·
`plan_progress.dart` · duplicate-session data risk (auto-id docs, no
`(routineId,week,day)` constraint; `completed` is a `Set` so `planComplete` is
stable under repeat; `workoutsCount` increments correctly; streak dedups by date).

---

## Open Questions

- [ ] **Pre-existing, out of scope:** a day with zero present slots that week shows
  a start CTA for an empty session. Already true today on incomplete plans (T-3
  only extends the same behavior to complete plans, it does not create it).
  REQ-WPRES-028's "no exercises this week" message renders above it. Flagged, not
  fixed here.
- [ ] **Pre-existing asymmetry, out of scope:** `_StartSessionCTABar` hides the CTA
  when viewing **another athlete's** `RoutineSource.userCreated` routine
  (L1176-1181). `_PeriodizedCTABar` has **no such guard** — a periodized public
  routine can be started against its owner. Orthogonal to this change; do **not**
  fold it in. Worth its own change.

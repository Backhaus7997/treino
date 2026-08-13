# Proposal: repetir-plan-completado

> Phase: propose · Change: `repetir-plan-completado` · Project: treino · Store: openspec
> Depends on: `sdd/repetir-plan-completado/explore` (Engram #496)
> Status: ready for `sdd-spec` + `sdd-design` (parallel). **Spec MUST close D1 (CTA shape) with the user before freezing scenarios.**
> ⚠️ This proposal CORRECTS the exploration's root-cause scoping — see §3.

---

## 1. Intent & motivation

**Problem.** An athlete who finishes a periodized (multi-week) plan hits a dead end. The home card (`todaysRoutineProvider`) offers "EMPEZAR ENTRENAMIENTO" — its day/week rollover is `(lastWeek + 1) % numWeeks`, an infinite cycle that never consults `planComplete`. The athlete taps, lands on the routine detail, and `_PeriodizedCTABar` shows a banner with **no button**. The app invites you in through one door and locks the other.

**Evidence.** Reproduced on device with real data: "UPPER B – TIRÓN" (`numWeeks: 3`, SEM 1/2/3 selector visible), 9/9 (week,day) combinations complete → `planComplete = true`.

**Who it hits.** Every athlete who *finishes* a periodized plan — the ones who did best. This is not an edge case; it is the success path terminating in a wall.

**This is not a new policy — it is finishing decision A1.** `plan_gating.dart:20-24` (2026-06-29) states verbatim: *"drop the lock entirely… The athlete is an adult and knows what they are doing… The only signal we keep is 'this day is already completed'* (**drives the 'ENTRENADO' badge, not a hard lock**)". A1 removed the week/day locks but left `alreadyDone` and `planComplete` as hard locks in the CTA bar — inconsistent with its own stated intent. **Option B closes that debt.**

**Success looks like.** An athlete on a completed periodized plan opens the routine detail and can start the session again. "Completed" reads as a badge, never as a wall.

---

## 2. Scope

### In scope

- **`_PeriodizedCTABar` (`lib/features/workout/presentation/routine_detail_screen.dart` ~L900-1113)** — the only production file needing UI change. **BOTH** gate branches (see §3): the `planComplete` branch (~L944-972) and the `alreadyDone` branch (~L1008-1037).
- **New ARB key** (e.g. `routineDetailRepeat`) across the 3 files: `intl_es_AR.arb` (template, with `@key` metadata), `intl_es.arb` (no `@key` entries — follow the file's existing shape), `intl_en.arb`.
- **New `TreinoIcon` token** for repeat/refresh — none exists today (grepped: no `repeat`/`clockwise`/`refresh`/`rotate` token).
- **Retire `isStartable`** (`plan_gating.dart:64-71`) + its 6 tests (§5).
- **Renegotiate `SCENARIO-035`**, extend `SCENARIO-036` (§5).

### Out of scope (explicit, all verified)

- `lib/features/home/application/todays_routine_provider.dart` — **no change**. Its infinite rollover is already the desired behavior under B; it was only *wrong* because the detail screen contradicted it.
- `lib/features/workout/application/plan_progress.dart` — `planComplete` keeps being computed **identically**. It stops being a *lock*; it does not stop being a *signal* (it still drives the banner).
- `_StartSessionCTABar` (`numWeeks == 1` path) — zero gating already; single-week plans work today.
- `session_notifier.dart` / `session_init.dart` / `session_providers.dart` — verified no gating; `_buildFresh` never checks completion.
- `isWeekUnlocked` / `isDayUnlocked` — already constant `true`; removing their dead call sites is separate cleanup.

---

## 3. ⚠️ Root-cause correction (exploration was wrong — verified in code)

The exploration (and the framing handed to this phase) claims: *"the real blocker is `alreadyDone`, NOT `planComplete`"*. **That is false for the reported repro**, and acting on it would ship a fix that fixes nothing.

Control flow in `_PeriodizedCTABar.build`:

| Line | Branch | Behavior |
|------|--------|----------|
| **L944** | `if (progress.planComplete)` | **early-returns** a banner — no button, for **every** day of **every** week |
| L1008 | `if (alreadyDone)` | early-returns a COMPLETADO chip — no button |

When the plan is complete, **L944 fires first and L1008 is unreachable**. Patching only `alreadyDone` leaves the exact device bug ("UPPER B", 9/9 done) fully intact.

**What is true:** `alreadyDone` is a *second, independent* hard lock — under `planComplete`, every required (week,day) is in `completed`, so removing only the `planComplete` branch would drop straight into the `alreadyDone` wall. **Both branches are hard locks; both must be renegotiated.** Neither one alone is "the" cause.

Note the exploration is internally inconsistent here: its own out-of-scope note ("`planComplete` stops being a lock") already contradicts its root-cause claim. The scoping to `_PeriodizedCTABar` is correct — the scoping to "just the `alreadyDone` block ~L1008-1037" is not.

**Design implication.** The cleanest restructure makes the `planComplete` branch stop early-returning: render the banner as an *informational header* and **fall through** to the day-level CTA logic, where `alreadyDone` now yields badge + REPETIR. One restructure, both locks dropped, banner preserved.

---

## 4. D1 — CTA shape (product decision, user confirms before spec freeze)

| # | Option | Upside | Tradeoff |
|---|--------|--------|----------|
| **(a)** | **Keep COMPLETADO badge + add distinct "REPETIR" button** ✅ *recommended* | Completed vs fresh days stay visually distinct; "repeat" is honest about what it does; badge (A1's kept signal) survives | New ARB key + new `TreinoIcon` token; two elements in the CTA slot |
| (b) | Reuse "EMPEZAR" on completed days | Zero new copy/tokens; simplest diff | Erases the completed/fresh distinction — deletes the badge signal A1 explicitly kept. Contradicts A1 while claiming to finish it |
| (c) | Badge stays, repeat lives behind a secondary/overflow affordance | Keeps CTA slot uncluttered; repeat framed as deliberate | Hides the *only* exit from the dead end behind a discovery step — reintroduces the wall for anyone who doesn't find it |

**Recommendation: (a).** It is the only option that satisfies both halves of A1's sentence — keep the completed *signal*, drop the *lock*. (b) drops the signal; (c) keeps a soft lock.

**Open for the user:** exact copy ("REPETIR" vs "REPETIR DÍA" vs "ENTRENAR DE NUEVO") and whether the plan-complete banner keeps its current text once it is no longer terminal. **`sdd-spec` must not freeze scenarios until this is confirmed.**

---

## 5. Test-contract renegotiation

**There is no live spec to delta.** `REQ-PERIOD-037` has **no `spec.md` anywhere** — `openspec/specs/` has no periodization capability, and `periodization-model-b` has no change folder (no archive). It survives only as inline comments in `plan_gating.dart`, `routine_detail_screen.dart`, `session_init.dart`. **`sdd-spec` writes a NEW capability spec, not a delta**, and must correct those now-stale inline references.

| Artifact | Today | Action |
|----------|-------|--------|
| `routine_detail_periodized_test.dart` **SCENARIO-035** (~L358) | `expect(find.text('EMPEZAR'), findsNothing)` on a completed day | **Rewrite** — head-on collision with B |
| `routine_detail_periodized_test.dart` **SCENARIO-036** (~L333) | Asserts only `find.text('PLAN COMPLETADO')` presence | **Extend.** It stays green either way — that is the problem: it is the *only* plan-complete test and it cannot see a missing button. Must assert the repeat CTA |
| `plan_gating_test.dart` — `isStartable` group (6 tests, L69-116) | Encodes `completed → not startable` | **Delete with the function** |
| `plan_progress_test.dart` | Pure `planComplete` logic | **No change** (§2) |

**`isStartable` is a false-confidence mine.** Zero production call sites (grepped all of `lib/`), yet 6 green tests assert the exact opposite of B. Left alone, the suite would keep certifying "completed → not startable" while the product ships "completed → repeatable". `plan_gating.dart:26-29` already flags it as deferred A1 cleanup. **Delete it** rather than repurpose: its only honest post-B body is `=> true`, which is not a function worth keeping.

---

## 6. Data risk: verified nil

| Concern | Finding |
|---------|---------|
| Duplicate session docs | Firestore auto-id (`_sessions(uid).doc()`); no composite key/index/rule on (routineId, week, day) — verified in `firestore.rules`, `firestore.indexes.json` |
| `planComplete` regression | `completed` is a `Set<CompletedKey>` — a repeat re-adds an existing key; stays `true` |
| `workoutsCount` | Increments correctly (`session_repository.finish`) — a repeat *is* a real workout |
| Racha | `streak_calculator` dedups by calendar date — no inflation |

No migration, no backfill, no rule change.

---

## 7. Capabilities

### New Capabilities
- `periodized-plan-repeat`: athlete-facing gating contract for periodized routine CTAs — completed day/plan as **badge, not lock**; repeat affordance; canonical home of the orphaned `REQ-PERIOD-037` semantics.

### Modified Capabilities
- None (no live spec exists to amend — see §5).

---

## 8. Affected areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/workout/presentation/routine_detail_screen.dart` | Modified | `_PeriodizedCTABar`: `planComplete` branch stops early-returning (§3); `alreadyDone` branch gains REPETIR |
| `lib/features/workout/application/plan_gating.dart` | Modified | Delete `isStartable`; update stale header comments |
| `lib/core/widgets/treino_icon.dart` | Modified | Add repeat/refresh token |
| `lib/l10n/intl_{es_AR,es,en}.arb` + generated | Modified | `routineDetailRepeat` (EN: note `routineDetailPlanComplete`/`Completed` are already empty strings — pre-existing gap) |
| `test/.../routine_detail_periodized_test.dart` | Modified | SCENARIO-035 rewrite, SCENARIO-036 extension |
| `test/.../plan_gating_test.dart` | Modified | Drop `isStartable` group |
| `openspec/specs/periodized-plan-repeat/spec.md` | New | First live spec for this behavior |

---

## 9. Risks

| # | Risk | Likelihood | Mitigation |
|---|------|------------|------------|
| R1 | **Fix targets only `alreadyDone`; device bug survives** | **High** (exploration says exactly this) | §3 is the mitigation. Apply MUST touch the `planComplete` branch. SCENARIO-036 extension is the regression net — it is the only test on the true repro path |
| R2 | Deleting `isStartable` breaks a call site | Low | Zero call sites in `lib/` (grepped). `flutter analyze` catches any miss |
| R3 | Test rewrite rubber-stamps the new behavior instead of testing it | Med | Scenarios derive from the spec (§5), authored before apply — not retro-fitted to the diff |
| R4 | Single-week regression | Low | `_StartSessionCTABar` untouched; diff is inside `numWeeks > 1` |
| R5 | Banner + CTA layout overflow (recent agenda 1px-overflow class of bug) | Low | Widget test at the test viewport; CTA already sits below the fold (`skipOffstage: false`) |
| R6 | EN ships blank copy | Low | EN already blank for neighbors; either fill all three or file the gap explicitly — do not silently extend it |

---

## 10. Rollback plan

Pure client-side UI + a deleted pure function. No schema, no rules, no migration, no writes changed in shape. Revert the feature branch and the CTA returns to banner/chip; sessions created by a repeat remain valid rows (indistinguishable from any other session — that is §6's point). Restore `isStartable` + its 6 tests from git history if the revert needs the file whole.

---

## 11. Review workload forecast

| Slice | Content | Est. |
|-------|---------|------|
| Single PR | CTA restructure (both branches), `isStartable` deletion, ARB×3 + regen, icon token, test rewrites | ~150-250 |

**Chained PRs recommended: No.** **400-line budget risk: Low.** **Decision needed before apply: Yes** — D1 (§4) gates the copy and the test assertions.

---

## 12. Success criteria

- [ ] Athlete on a **completed periodized plan** (repro: "UPPER B – TIRÓN", 3 weeks, 9/9 done) can start a session from routine detail — the home CTA no longer leads to a wall.
- [ ] The completed **signal survives**: COMPLETADO badge and PLAN COMPLETADO banner still render; neither blocks.
- [ ] A completed day on an **incomplete** plan is repeatable too (SCENARIO-035 path).
- [ ] `isStartable` and its 6 tests are gone; no test asserts "completed → not startable".
- [ ] `openspec/specs/periodized-plan-repeat/spec.md` exists; stale `REQ-PERIOD-037` inline comments point at it.
- [ ] Single-week plans byte-identical.
- [ ] `flutter analyze` 0 new issues (main baseline: 41 pre-existing) + `dart format .` + `flutter test` green (~3852).

---

## 13. Handoff

- **`sdd-spec`** — confirm **D1 (§4)** with the user FIRST, then write `openspec/specs/periodized-plan-repeat/spec.md`: completed-day-repeatable, completed-plan-repeatable (the untested repro), badge-not-lock, single-week unchanged. Rewrite SCENARIO-035, extend SCENARIO-036, correct the stale inline `REQ-PERIOD-037` references.
- **`sdd-design`** — rule the `_PeriodizedCTABar` restructure: banner-falls-through (§3) vs a flatter gate chain; where REPETIR sits relative to the badge; the `TreinoIcon` token choice.

Spec and design run in parallel; both depend only on this proposal.

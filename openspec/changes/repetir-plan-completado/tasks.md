# Tasks: repetir-plan-completado

**Change**: `repetir-plan-completado` · **Artifact store**: openspec
**TDD mode**: Strict — RED (test written, confirmed failing against CURRENT early-return code) before GREEN.
**Namespace**: REQ-REPEAT-001..006 / SCENARIO-REPEAT-001..010 (spec) · AD-1..AD-5, T-1..T-4 (design).
**Scope note**: Phase 2 is a **scope delta vs proposal §2** (which deferred `isWeekUnlocked`/`isDayUnlocked` cleanup). Kept as its own PR so a reviewer can revert it alone without touching Phase 1's fix.

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | PR1 ~450-500 (prod ~360-395, tests ~95) · PR2 ~193 (pure deletion) → **~650-690 total** |
| 400-line budget risk | Medium (PR1, borderline) / Low (PR2) — High combined |
| Chained PRs recommended | Yes |
| Suggested split | PR1 (AD-1 fix) → PR2 (AD-3 cleanup, sequential) |
| Delivery strategy | ask-on-risk (default — not specified by orchestrator) |
| Chain strategy | stacked-to-main |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| 1 | AD-1 CTA restructure + ARB×3 + T-1..T-4 tests | PR 1 | Base = feature branch off main. Ships the fix alone; independently revertible. |
| 2 | AD-3 scope delta — delete `plan_gating.dart` + its test | PR 2 | Base = main, after PR1 merges (needs PR1's call-site removal live to confirm 0 refs). Mechanical, pure deletion. |

**Why stacked-to-main, not feature-branch-chain**: PR1 alone is a complete, shippable fix (unblocks the athlete). PR2 is optional cleanup with zero functional effect — a tracker branch would delay a fix that stands on its own.

---

## Pre-flight

- [x] 0.1 *(Inspection)* Re-confirm `_PeriodizedCTABar` early returns still at L944 (`planComplete`), L1008 (`alreadyDone`), L1040 (`weekLocked||dayLocked`), L1074 (`EMPEZAR`) in `routine_detail_screen.dart` — unchanged since design.
- [x] 0.2 *(Inspection, `rg` across `lib/`)* Confirm `isWeekUnlocked`/`isDayUnlocked`/`isStartable`/`plan_gating` import have exactly the call sites design claims (2 gating calls, 1 importer file).

## Phase 1 — PR1: CTA restructure (AD-1) + copy + tests — REQ-REPEAT-001..005

- [x] 1.1 `[RED][TEST]` `[REQ-REPEAT-002][SCENARIO-REPEAT-003]` Rewrite "SCENARIO-035: completed day shows COMPLETADO state" (`test/features/workout/presentation/routine_detail_periodized_test.dart` ~L358-379): assert `COMPLETADO` findsOneWidget, `REPETIR` findsOneWidget, `EMPEZAR` findsNothing, `onPressed != null` on the button. Confirm FAILS today (no button in the `alreadyDone` branch).
- [x] 1.2 `[RED][TEST]` `[REQ-REPEAT-001][SCENARIO-REPEAT-001]` **Device repro.** Extend "SCENARIO-036" (~L333-356): keep `PLAN COMPLETADO` findsOneWidget; add `REPETIR` findsOneWidget + `onPressed != null`; add `find.text('COMPLETADO')` findsNothing (pins banner-XOR-chip). Confirm FAILS today.
- [x] 1.3 `[RED][TEST]` `[REQ-REPEAT-001][SCENARIO-REPEAT-002]` New test reusing `slotPresentOnlyWeek2` fixture (~L422): `planComplete=true`, viewed day has zero present slots that week (never in `completed`) → banner renders AND `EMPEZAR` (not `REPETIR`). Confirm FAILS today (banner-only early return).
- [x] 1.4 `[RED][TEST]` `[REQ-REPEAT-002][REQ-REPEAT-003][REQ-REPEAT-006]` New test: AD-2 invariant across all 3 states (fresh / day-done / plan-done) — an enabled `ElevatedButton` renders in every case. Replaces the 14 tests deleted in Phase 2. Confirm mixed RED (fresh passes today, other two fail).
- [x] 1.5 `[GATE]` Run 1.1-1.4 — confirm the RED/mixed state above, not a compile error.
- [x] 1.6 `[REQ-REPEAT-005][SCENARIO-REPEAT-007]` Add `routineDetailRepeat` to `intl_es_AR.arb` (`"REPETIR"` + `@routineDetailRepeat: {}`), `intl_es.arb` (`"REPETIR"`, no `@key`), `intl_en.arb` (**`"REPEAT"`** — filled, per D1/AD-5, not the cluster's usual `""`). Optionally drop orphaned `routineDetailWeekLocked`/`routineDetailDayLocked` keys from all 3 (design AD-3 file map; low-stakes, skip if regen diff argues otherwise).
- [x] 1.7 `[BUILD]` Run `flutter gen-l10n`; commit regenerated `lib/l10n/app_l10n*.dart` (tracked in git).
- [x] 1.8 `[GREEN]` `[AD-1][AD-2]` Restructure `_PeriodizedCTABar.build`'s `data:` callback in `routine_detail_screen.dart`: replace the 4 early returns with `if (planComplete) _PlanCompleteBanner() else if (alreadyDone) _CompletedDayChip()` + unconditional `_buildSessionCTA(context, ref, isRepeat: alreadyDone)`, hoisted into one `Padding(vertical: 18)`. Delete the `requiredPairs` loop, the `isWeekUnlocked`/`isDayUnlocked` calls, and the `weekLocked||dayLocked` branch (their only call site). Drop the `plan_gating.dart` import and the `CompletedKey` import if `flutter analyze` flags it unused. Add `_PlanCompleteBanner`/`_CompletedDayChip` as private `StatelessWidget`s. Label: `alreadyDone ? l10n.routineDetailRepeat : l10n.routineDetailStart`. Update the class doc comment (drop `REQ-PERIOD-033/034/037`, point at `periodized-plan-repeat`) and the L943 inline comment. Trainer guard (L924) and `loading`/`error` keep returning early — states, not gates. **No `TreinoIcon` change** (AD-4).
- [x] 1.9 `[SCENARIO-REPEAT-004]` *(Inspection only — harness has no go_router)* Confirm both labels share the same `_buildSessionCTA` call site, so the composed route (`/workout/session/${routine.id}/${day.dayNumber}?week=$viewedWeek`) is identical regardless of `isRepeat`.
- [x] 1.10 `[GATE]` Re-run 1.1-1.4 — all GREEN.
- [x] 1.11 `[GATE]` `flutter analyze lib test` → 0 new issues (baseline 41). `dart format` on touched files only. `flutter test` green for PR1 scope.

## Phase 2 — PR2 (scope delta, AD-3): retire `plan_gating.dart` — REQ-REPEAT-006

- [x] 2.1 *(Inspection)* `rg` `lib/` + `test/` for `isStartable`, `isWeekUnlocked`, `isDayUnlocked`, `plan_gating` — confirm 0 references now that 1.8 merged (SCENARIO-REPEAT-009 precondition).
- [x] 2.2 Delete `lib/features/workout/application/plan_gating.dart` entirely.
- [x] 2.3 Delete `test/features/workout/application/plan_gating_test.dart` entirely.
- [x] 2.4 `[GATE]` `flutter analyze lib test` → 0 new issues, `dart format`, `flutter test` green (~3852 − 14 deleted + 4 new: T-3 + 3×T-4, corrects the design's "+2" estimate). Confirms SCENARIO-REPEAT-009/010.

## Phase 3 — Spec sync (non-blocking, inspection only — does NOT gate `sdd-apply`)

- [x] 3.1 **Flag, don't silently fix**: `spec.md` REQ-REPEAT-005 ("MUST provide a `TreinoIcon` token…") and SCENARIO-REPEAT-008 contradicted design AD-4 (no new icon). Amended: REQ-REPEAT-005 now states no new `TreinoIcon` token is introduced; SCENARIO-REPEAT-008 now asserts absence of the token. `spec.md`'s Non-Goals bullet deferring `isWeekUnlocked`/`isDayUnlocked` cleanup replaced with a "Superseded note" explaining AD-3 folded that cleanup into REQ-REPEAT-006 instead of deferring it.

## Not in scope (do not touch)

`todays_routine_provider.dart`, `plan_progress.dart`, `_StartSessionCTABar`, `session_notifier`/`init`/`providers`, `treino_icon.dart` (AD-4).

## Quality gate reminder (both PRs)

`flutter analyze lib test` 0 new issues (baseline 41) · `dart format` on touched files only (global format reformats unrelated files) · `flutter test` green · `flutter gen-l10n` + commit generated files after any ARB touch.

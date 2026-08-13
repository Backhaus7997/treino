# periodized-plan-repeat Specification

> Change: `repetir-plan-completado` · Domain: `periodized-plan-repeat` (new capability — no existing `openspec/specs/` file to delta; `REQ-PERIOD-037` survived only as inline comments, now orphaned).
> Scope: `_PeriodizedCTABar` only (`numWeeks > 1`). `_StartSessionCTABar` (single-week) is unaffected — see REQ-REPEAT-004.
> D1 resolved: keep COMPLETADO chip / PLAN COMPLETADO banner, add a distinct "REPETIR" button (uppercase, consistent with EMPEZAR/COMPLETADO).

## Purpose

Completed (day or plan) is a **signal, never a hard lock** — finishing decision A1 (2026-06-29): the only surviving completion signal drives a badge, not a wall. Today two independent early-returns in `_PeriodizedCTABar` (`planComplete` then `alreadyDone`) contradict A1 by rendering badge/banner with no CTA. This spec closes both.

## Requirement index

| ID | Area |
|---|---|
| REQ-REPEAT-001 | Plan-complete banner is informational, never blocking |
| REQ-REPEAT-002 | Completed day shows badge + REPETIR, not a wall |
| REQ-REPEAT-003 | Not-yet-completed day unaffected (regression guard) |
| REQ-REPEAT-004 | Single-week plans byte-identical |
| REQ-REPEAT-005 | REPETIR copy & iconography contract |
| REQ-REPEAT-006 | Retire "completed blocks startability" contract |

## Requirements

### REQ-REPEAT-001 — Plan-complete banner is informational, never blocking

The system MUST render the "PLAN COMPLETADO" banner whenever `planProgress.planComplete` is true. The system MUST NOT use `planComplete` to withhold the day-level CTA (EMPEZAR, or COMPLETADO+REPETIR) for the currently viewed (week, day).

#### SCENARIO-REPEAT-001 — Plan complete, viewed day already done (the device repro)

- GIVEN a periodized routine where every required (week, day) is in `completed` (e.g. 9/9)
- WHEN the athlete opens routine detail on any (week, day)
- THEN the "PLAN COMPLETADO" banner renders
- AND a "COMPLETADO" chip and a "REPETIR" button also render for that day

#### SCENARIO-REPEAT-002 — Plan complete, viewed day is auto-satisfied (zero present slots)

- GIVEN `planComplete` is true but the viewed (week, day) has zero present slots and is absent from `completed` (REQ-WPRES-022)
- WHEN the athlete opens that (week, day)
- THEN the banner renders AND the "EMPEZAR" CTA is still available for that day (not blocked by the banner)

### REQ-REPEAT-002 — Completed day shows badge + REPETIR, not a wall

The system MUST render both a "COMPLETADO" chip and a "REPETIR" button whenever the viewed (week, day) is in `progress.completed`, independent of whether the whole plan is complete.

#### SCENARIO-REPEAT-003 — One of N days done, plan incomplete (renegotiates SCENARIO-035)

- GIVEN a multi-day periodized plan where only the viewed day is completed
- WHEN the athlete opens that (week, day)
- THEN "COMPLETADO" and "REPETIR" render
- AND "EMPEZAR" does NOT render

#### SCENARIO-REPEAT-004 — REPETIR starts a new session

- GIVEN the "REPETIR" button is visible for a completed (week, day)
- WHEN the athlete taps it
- THEN the app navigates to the workout session route for that exact (week, day) — the same entry point EMPEZAR uses for a startable day

### REQ-REPEAT-003 — Not-yet-completed day unaffected

The system MUST continue to render "EMPEZAR" and no completion badge when the viewed (week, day) is absent from `completed` and the plan is not complete.

#### SCENARIO-REPEAT-005 — Fresh day, no completions

- GIVEN a periodized plan with no completed sessions
- WHEN the athlete opens any (week, day)
- THEN "EMPEZAR" renders and neither "COMPLETADO", "PLAN COMPLETADO", nor "REPETIR" render

### REQ-REPEAT-004 — Single-week plans byte-identical

The system MUST NOT change any rendering, gating, or copy for `numWeeks == 1` routines (`_StartSessionCTABar`). This capability applies only to `_PeriodizedCTABar`.

#### SCENARIO-REPEAT-006 — Single-week regression guard

- GIVEN a routine with `numWeeks == 1`, completed or not
- WHEN the athlete opens routine detail
- THEN `_StartSessionCTABar` renders exactly as before this change — no REPETIR, no banner/chip changes

### REQ-REPEAT-005 — REPETIR copy contract

The system MUST expose a new ARB key (`routineDetailRepeat`) in `intl_es_AR.arb` (with `@key` metadata), `intl_es.arb`, and `intl_en.arb`, with ES/ES_AR value `"REPETIR"` (uppercase) and EN value `"REPEAT"` (filled — not blank like its sibling `routineDetail*` keys; a blank action button is an unusable control, see design AD-5). The system MUST NOT introduce a new `TreinoIcon` token for this button: neither start CTA in this screen (`_StartSessionCTABar` nor the periodized CTA) has ever had an icon, and the completion signal (banner/chip) already owns the iconography (`TreinoIcon.check`). This corrects an earlier draft of this requirement, which wrongly assumed an icon token was needed before the design phase inspected the file (design AD-4).

#### SCENARIO-REPEAT-007 — Copy key present in all three locales

- GIVEN the generated `AppL10n` after this change
- WHEN reading `routineDetailRepeat` for `es`/`es_AR`/`en`
- THEN `es`/`es_AR` return `"REPETIR"` and `en` returns `"REPEAT"`

#### SCENARIO-REPEAT-008 — No new icon token is introduced (corrected)

- GIVEN `TreinoIcon` after this change
- WHEN inspecting its static members
- THEN no repeat/restart token exists — the REPETIR button renders as bare text, matching its EMPEZAR sibling (design AD-4)

### REQ-REPEAT-006 — Retire "completed blocks startability" contract

The system MUST NOT contain any function or test asserting that a completed (week, day) is not startable. `isStartable` (`plan_gating.dart`) and its test group MUST be removed. Inline comments referencing the orphaned `REQ-PERIOD-037` MUST be corrected to reference this spec.

#### SCENARIO-REPEAT-009 — isStartable is gone

- GIVEN the codebase after this change
- WHEN searching `lib/` and `test/` for `isStartable`
- THEN no references remain

#### SCENARIO-REPEAT-010 — No dangling REQ-PERIOD-037 references

- GIVEN the codebase after this change
- WHEN searching for `REQ-PERIOD-037` in `plan_gating.dart`, `routine_detail_screen.dart`, `session_init.dart`
- THEN each reference either points at `periodized-plan-repeat` or is removed

## Non-Goals (Out of Scope)

- `todays_routine_provider.dart` rollover logic — already correct under this policy.
- `plan_progress.dart` — `planComplete` computation is unchanged; it stops being a lock, not a signal.
- `session_notifier.dart` / `session_init.dart` / `session_providers.dart` — verified no gating.

**Superseded note**: an earlier draft of this spec deferred `isWeekUnlocked`/`isDayUnlocked` cleanup as a separate change. Design phase (AD-3) found the two decisions interact — once REQ-REPEAT-001/002 remove the CTA's early returns, the locked branch becomes the last one standing, and deferring its removal would leave `plan_gating.dart` with zero call sites (a provably-dead branch) instead of a deleted file. REQ-REPEAT-006 now covers this cleanup in full; it is no longer deferred.

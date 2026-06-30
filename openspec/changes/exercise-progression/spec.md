# Exercise Progression Specification

> Phase: spec · Change: `exercise-progression` · Project: treino · Store: hybrid
> Status: ready for `sdd-design` + `sdd-tasks`

---

## Purpose

Define the requirements and acceptance scenarios for the PF-only, per-exercise progression feature: a bounded data provider, an exercise picker chip row, a line chart (PR / Volumen) with a Frecuencia stat, wired into both the mobile coach surface and the web Coach Hub.

---

## Requirements

### REQ-PROG-01: Provider aggregation — PR series

The `exerciseProgressionProvider(athleteUid, exerciseId)` MUST compute a PR data series where each point represents a single session and its value equals the **raw maximum `weightKg`** across all sets logged for that exercise in that session (`max(log.weightKg)`). Epley-estimated 1RM MUST NOT be used as the PR value.

#### SCENARIO-PROG-01A: PR per session (happy path)

- GIVEN an athlete has two sessions, each containing sets for `exerciseId="squat"`
- AND session S1 has sets with `weightKg` [80, 90, 85] and session S2 has sets with `weightKg` [95, 92]
- WHEN `exerciseProgressionProvider(athleteUid, "squat")` resolves
- THEN the PR series contains two points: S1 → 90.0, S2 → 95.0
- AND points are ordered ascending by `session.startedAt`

#### SCENARIO-PROG-01B: PR with single set per session

- GIVEN an athlete has one session with exactly one set for the target exercise (`weightKg` = 70)
- WHEN the provider resolves
- THEN the PR series contains one point with value 70.0

#### SCENARIO-PROG-01C: PR excludes sets for other exercises

- GIVEN a session contains sets for `exerciseId="squat"` and `exerciseId="bench"`
- WHEN the provider is called with `exerciseId="squat"`
- THEN only squat sets contribute to the PR value; bench sets are ignored

---

### REQ-PROG-02: Provider aggregation — Volumen series

The provider MUST compute a Volumen data series where each point equals `Σ(log.reps × log.weightKg)` across all sets for the target exercise in that session.

#### SCENARIO-PROG-02A: Volumen per session

- GIVEN session S1 has squat sets: {reps: 5, weightKg: 80}, {reps: 3, weightKg: 90}
- WHEN the provider resolves with `exerciseId="squat"`
- THEN the Volumen point for S1 equals 5×80 + 3×90 = 670.0

#### SCENARIO-PROG-02B: Volumen ordered by startedAt

- GIVEN multiple sessions with squat sets
- WHEN the provider resolves
- THEN the Volumen series is ordered ascending by `session.startedAt` (same ordering as PR series)

---

### REQ-PROG-03: Provider aggregation — Frecuencia stat

The provider MUST compute a single integer `frecuencia` equal to the count of sessions within the last **8 weeks (56 days)** relative to `DateTime.now()` that contain at least one set for the target exercise. Bucketing MUST use `Session.startedAt`. `Session.weekNumber` MUST NOT be used.

#### SCENARIO-PROG-03A: Frecuencia counts sessions in window

- GIVEN the athlete has 4 sessions with squat sets, 3 within the last 56 days and 1 at day -60
- WHEN the provider resolves with `exerciseId="squat"`
- THEN `frecuencia` equals 3

#### SCENARIO-PROG-03B: Frecuencia boundary — session exactly at edge

- GIVEN a session's `startedAt` equals exactly `now - 56 days` (to the second)
- WHEN the provider resolves
- THEN that session IS included in `frecuencia` (inclusive lower bound)

#### SCENARIO-PROG-03C: Frecuencia is independent of 60-session scan bound

- GIVEN an athlete has 70 sessions total; only the last 60 are scanned; 5 of those 60 are within 56 days
- WHEN the provider resolves
- THEN `frecuencia` reflects only the scanned 60 sessions (not all 70); the stat MUST surface the bound in UI copy

---

### REQ-PROG-04: Bounded scan

The provider MUST scan at most the **last 60 sessions** for the given athlete (DESC by `startedAt`, `.take(60)`). Sessions beyond position 60 MUST NOT be read or aggregated.

#### SCENARIO-PROG-04A: Scan respects 60-session bound

- GIVEN an athlete has 80 sessions total
- WHEN the provider resolves for any exercise
- THEN only the 60 most-recent sessions are considered; sessions 61–80 (oldest) are not read

#### SCENARIO-PROG-04B: Scan with fewer than 60 sessions

- GIVEN an athlete has 30 sessions
- WHEN the provider resolves
- THEN all 30 sessions are scanned (no truncation error)

---

### REQ-PROG-05: Exercise list provider

`athleteExerciseListProvider(athleteUid)` MUST return a deduplicated list of `(exerciseId, exerciseName)` pairs found across the same bounded scan (last 60 sessions). `exerciseName` MUST be read from the denormalized field on `SetLog`; no exercise-catalogue Firestore read is permitted. The list MUST be ordered so that the **most-recently-logged** exercise appears first.

#### SCENARIO-PROG-05A: Deduplication by exerciseId

- GIVEN the scan finds squat sets in sessions S1, S3, S5 and bench sets in S2, S4
- WHEN `athleteExerciseListProvider` resolves
- THEN the list contains exactly two entries: one for squat, one for bench (no duplicates)

#### SCENARIO-PROG-05B: Default selection is most-recently-logged

- GIVEN the most-recent session containing a set is S5 with `exerciseId="squat"`
- WHEN the picker renders
- THEN the squat chip is selected by default

#### SCENARIO-PROG-05C: exerciseName from SetLog (no catalogue lookup)

- GIVEN `SetLog.exerciseName` equals "Sentadilla"
- WHEN the exercise list is built
- THEN the chip label reads "Sentadilla" without any additional Firestore read

---

### REQ-PROG-06: Chart — metric chip selector

The chart widget MUST display a chip row with **PR** (selected by default) and **Volumen**. Selecting a chip MUST reflow the chart to display the corresponding data series. Frecuencia MUST appear as a separate stat (text/badge), NOT as a line on the chart.

#### SCENARIO-PROG-06A: PR chip selected by default

- GIVEN the chart widget receives a resolved `ExerciseProgressionData`
- WHEN it first renders
- THEN the PR chip is highlighted and the chart displays the PR series

#### SCENARIO-PROG-06B: Switching to Volumen

- GIVEN the chart is showing the PR series
- WHEN the user taps the Volumen chip
- THEN the chart reflows to display the Volumen series
- AND the Frecuencia stat remains visible and unchanged

#### SCENARIO-PROG-06C: Frecuencia displayed as a stat, not a chart line

- GIVEN `frecuencia` equals 5
- WHEN the chart widget renders
- THEN "5 sesiones en las últimas 8 semanas" (or equivalent) is shown as a text/badge element
- AND the fl_chart `LineChart` contains no data series for Frecuencia

---

### REQ-PROG-07: Chart — insufficient data states

When the selected exercise has fewer than 2 data points, the chart MUST NOT render a line. A single-point value MUST be displayed as a stat. A hint MUST inform the user that at least 2 sessions are needed to show a trend.

#### SCENARIO-PROG-07A: Zero data points (no sets logged for exercise)

- GIVEN the athlete has sessions but none contain sets for the selected `exerciseId`
- WHEN the chart widget renders for that exercise
- THEN no fl_chart `LineChart` is shown
- AND a "sin datos suficientes" or equivalent message is shown

#### SCENARIO-PROG-07B: Exactly one data point

- GIVEN the athlete has exactly one session with sets for the selected exercise
- WHEN the chart widget renders
- THEN no trend line is drawn
- AND the single PR (or Volumen) value is shown as a stat
- AND a hint reads "necesitás al menos 2 sesiones para ver la evolución" (mobile: via `AppL10n` key; web: hardcoded Spanish)

#### SCENARIO-PROG-07C: Two or more data points show the line

- GIVEN the athlete has at least 2 sessions with sets for the selected exercise
- WHEN the chart widget renders
- THEN a fl_chart `LineChart` is displayed with one point per session

---

### REQ-PROG-08: Empty state — no setLogs at all

When the bounded scan finds no `SetLog` records for the athlete, the exercise picker MUST NOT render, and a friendly "sin datos" message MUST be shown in its place. No chart is displayed.

#### SCENARIO-PROG-08A: Athlete with zero setLogs

- GIVEN `athleteExerciseListProvider` resolves to an empty list
- WHEN the progression section renders
- THEN the chip row is not shown
- AND a "sin registros de series" (or equivalent) empty-state message is displayed

---

### REQ-PROG-09: PF-only access gating

The progression section MUST only appear on PF-facing screens (`_EntrenamientosSection` on mobile, `_EntrenamientoTab` on web). It MUST NOT appear on any athlete-facing screen (e.g., `InsightsScreen`). The underlying Firestore read path (trainer reading athlete setLogs via `session_shares`) is already authorized; no new security rules are required.

#### SCENARIO-PROG-09A: PF views athlete progression [surface: mobile + web]

- GIVEN a PF is authenticated and has a `session_shares` grant for the athlete
- WHEN the PF opens the athlete detail screen (mobile `_EntrenamientosSection` or web `_EntrenamientoTab`)
- THEN the exercise picker and chart render correctly
- AND no additional authentication or permission check is performed at the widget layer

#### SCENARIO-PROG-09B: Athlete screen has no progression view

- GIVEN the athlete is authenticated and opens any athlete-facing screen
- WHEN the athlete navigates to their own training history
- THEN no exercise progression section, picker, or chart is rendered

---

### REQ-PROG-10: Mobile surface wiring [surface: mobile]

The progression section MUST be inserted into `athlete_detail_screen.dart → _EntrenamientosSection`, after the session-list card. All user-visible strings MUST use `AppL10n` (new ARB keys in `intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb`).

#### SCENARIO-PROG-10A: Mobile progression section renders [surface: mobile]

- GIVEN a PF opens the mobile athlete detail screen for an athlete who has setLogs
- WHEN `_EntrenamientosSection` builds
- THEN the exercise picker chip row appears below the session-list card
- AND the progression chart (with metric chips) renders beneath the picker
- AND the Frecuencia stat is visible

#### SCENARIO-PROG-10B: Mobile strings via AppL10n [surface: mobile]

- GIVEN the progression widget renders on mobile
- WHEN any user-visible label is shown (metric names, Frecuencia label, empty state, hint)
- THEN the string is sourced from `AppL10n` (no hardcoded Spanish strings in mobile widget code)

---

### REQ-PROG-11: Web surface wiring [surface: web]

The progression section MUST replace the placeholder `Text` at `alumno_detail_screen.dart:1516` in `_EntrenamientoTab`. All user-visible strings MUST be hardcoded Spanish with `// i18n: Fase W2` comments. fl_chart rendering on the web build MUST be verified via a spike before the web PR is merged (R2 gate).

#### SCENARIO-PROG-11A: Web progression section renders [surface: web]

- GIVEN the R2 fl_chart-web spike passes (LineChart renders in Flutter web build)
- AND a PF opens the web Coach Hub athlete detail for an athlete who has setLogs
- WHEN `_EntrenamientoTab` builds
- THEN the placeholder text is gone
- AND the exercise picker chip row and progression chart render within the existing `SingleChildScrollView > Column(crossAxisAlignment: stretch)` layout

#### SCENARIO-PROG-11B: Web strings hardcoded Spanish [surface: web]

- GIVEN the progression widget renders on web
- WHEN any user-visible label is shown
- THEN the string is a hardcoded Spanish literal with a `// i18n: Fase W2` comment; `AppL10n` is NOT called from the web widget path

#### SCENARIO-PROG-11C: One shared chart widget — labels injected as params [surface: mobile + web]

- GIVEN one `ExerciseProgressionChart` widget exists in the codebase
- WHEN it is instantiated from mobile (AppL10n labels) or from web (hardcoded labels)
- THEN the widget accepts chart labels as constructor parameters
- AND no platform-conditional import or `AppL10n` call exists inside the widget itself

---

### REQ-PROG-12: Provider value-object shape

The provider MUST return a typed value object (e.g., `ExerciseProgressionData`) that contains:
- `prSeries`: time-ordered list of `{date: DateTime, value: double}` (one point per session)
- `volumenSeries`: time-ordered list of `{date: DateTime, value: double}` (one point per session)
- `frecuencia`: `int` (session count in last 8 weeks)
- Both series MAY be empty; `frecuencia` MAY be 0.

#### SCENARIO-PROG-12A: Value object is immutable and typed

- GIVEN `exerciseProgressionProvider` resolves
- THEN the result type is a `freezed` data class (or equivalent immutable struct)
- AND accessing `prSeries`, `volumenSeries`, `frecuencia` requires no type casting

---

## Test Surface Map

| Requirement | Test Type | Runner |
|-------------|-----------|--------|
| REQ-PROG-01/02/03/04 | Unit — pure aggregation logic with fake SetLog/Session fixtures | `flutter test` |
| REQ-PROG-05 | Unit — provider dedupe + ordering | `flutter test` |
| REQ-PROG-06/07/08 | Widget test — chart states + chip toggle | `flutter test` |
| REQ-PROG-09B | Widget test — InsightsScreen has no progression section | `flutter test` |
| REQ-PROG-10/11 | Widget test — surface wiring (mock provider, assert section presence) | `flutter test` |
| REQ-PROG-12 | Unit — value object shape (compile-time + runtime assertions) | `flutter test` |

All tests MUST pass under `flutter analyze` (0 issues) + `dart format .` + `flutter test` before any PR is merged.

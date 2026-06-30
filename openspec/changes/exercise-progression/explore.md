# Exploration: exercise-progression

## Current State

### Data model

`SetLog` (`lib/features/workout/domain/set_log.dart` line 11):
```
id, exerciseId, exerciseName, setNumber, reps, weightKg, rpe?, completedAt (DateTime)
```

`Session` (`lib/features/workout/domain/session.dart` line 13):
```
id, uid, routineId, routineName, startedAt, finishedAt?, totalVolumeKg, durationMin,
status, dayNumber, weekNumber, wasFullyCompleted
```

Firestore path: `users/{uid}/sessions/{sessionId}/setLogs/{setLogId}`

### Firestore access (security rules — `firestore.rules` lines 500–520)

Sessions AND setLogs are readable by:
- The athlete (owner)
- The linked trainer whose uid matches `session_shares/{athleteId}.trainerId`

This is already validated and live: `coachSessionSetLogsProvider` reads any session's setLogs for the trainer. The comment in `alumno_detail_screen.dart` line 1452 ("setLogs que es owner-only") is stale and wrong — the rules grant trainer read access via session_shares.

### Existing providers

| Provider | File | What it does |
|----------|------|--------------|
| `sessionsByUidProvider` | `session_providers.dart:33` | All sessions for a uid, DESC by startedAt |
| `coachSessionSetLogsProvider` | `session_providers.dart:146` | SetLogs for one (athleteUid, sessionId) pair |
| `lastWeightByExerciseProvider` | `session_providers.dart:105` | Scans last 15 sessions, builds exerciseId→lastWeight map |
| `weeklyInsightsProvider` | `insights_providers.dart:14` | Reads all sessions for current week + their setLogs in parallel |

The pattern for cross-session setLog aggregation already exists in `lastWeightByExerciseProvider` (lines 105–137) and `weeklyInsightsProvider` (lines 78–93): fetch sessions → `Future.wait` on listSetLogs per session.

### Existing chart infrastructure

Both charts use **fl_chart** `LineChart` + `AppPalette.of(context)`. They are structurally identical:

| Widget | File | Pattern |
|--------|------|---------|
| `MeasurementProgressChart` | `measurements/presentation/widgets/measurement_progress_chart.dart` | StatefulWidget, chip selector, fl_chart LineChart, delta header, hardcoded Spanish month names |
| `PerformanceProgressChart` | `performance/presentation/widgets/performance_progress_chart.dart` | Same pattern, uses AppL10n for labels |

Both use `_ChartMetric` descriptors with `extractor` functions, a `_MetricChipRow` for selecting the active metric, and a `_ProgressLineChart` inner widget. The `PerformanceProgressChart` version is the more mature one (uses AppL10n, intl DateFormat). The new exercise chart can be a third widget following the same structure.

### The two placeholder locations

**Mobile (coach)**
- File: `lib/features/coach/presentation/athlete_detail_screen.dart`
- Widget: `_EntrenamientosSection` (line 1540)
- The section currently lists sessions as expandable rows (lines 1596–1611). There is NO single "Próximamente" text line in this file — the placeholder is the ABSENCE of a chart below the session list. The natural insertion point is after line 1611 (after the session-list card), inside `_EntrenamientosSection.build`.

**Web Coach Hub**
- File: `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart`
- Widget: `_EntrenamientoTab` (line 1454)
- Placeholder text at **line 1516**: `'Próximamente: evolución por ejercicio (PR, volumen, frecuencia).'`
- Natural insertion: replace that Text widget with the new chart section.

### Athlete-facing progress

There is no athlete-facing exercise-progression screen. `InsightsScreen` (`lib/features/insights/presentation/insights_screen.dart`) shows weekly muscle-group aggregates only. The placeholder is explicitly in the TRAINER (PF) views. Scope is PF-only for this change unless explicitly expanded.

### Metric definitions (proposed)

All derived from setLogs aggregated across sessions for ONE exerciseId:

**PR (Personal Record)**: `max(weightKg)` across all-time setLogs for that exercise.
- Alternative: Epley estimated 1RM = `weightKg * (1 + reps/30)`. More scientific but harder to explain and sensitive to reps entry. Recommend: show both — `weightKg` as the primary "PR levantado" line, with a secondary Epley 1RM stat in the chart header. OR start with raw max weight (simpler, defensible), add Epley as v2.

**Volumen**: `Σ (reps × weightKg)` per session (all sets of that exercise in a session). One data point per session containing that exercise.

**Frecuencia**: count of sessions containing that exercise per calendar week (or per N-day window). Can be rendered as a bar chart or as a trend line.

### Exercise picker (list of exercises an athlete has performed)

From aggregating setLogs across sessions:
1. Collect all `(exerciseId, exerciseName)` pairs across all sessions' setLogs.
2. Deduplicate by exerciseId.
3. Sort by frequency (descending) or by last-performed date.

The `exerciseName` is denormalized in SetLog — no need to hit the exercise catalogue. This is a client-side aggregation from the same sessions+setLogs already loaded.

### Perf / read cost

To build the exercise list AND the chart for any selected exercise, the provider must:
1. Fetch all sessions for the athlete → `sessionsByUidProvider` (1 Firestore query, already in use).
2. For each session, fetch its setLogs → N subcollection reads.

This is the same O(sessions) pattern as `lastWeightByExerciseProvider` and `weeklyInsightsProvider`. The key difference: progression needs ALL history, not just the last 15 sessions.

**Firestore cost flag**: for an athlete with 100 sessions, this is 100 Firestore reads per provider invocation. `weeklyInsightsProvider` does the same but is bounded to the current week. Progression is unbounded.

**Mitigation options**:
- Bounded window (e.g., last 90 days / last 50 sessions) — simplest, covers 95% of practical use.
- A denormalized `exerciseStats/{uid}/stats/{exerciseId}` document updated at session finish — optimal reads, requires a write-side change and migration.
- Recommended for V1: bounded window (last 60 sessions / 180 days, whichever is less). Flag the bound clearly in the UI ("Últimas 60 sesiones").

---

## Affected Areas

- `lib/features/workout/application/session_providers.dart` — new provider: `exerciseProgressionProvider` (family key: `(athleteUid, exerciseId)`) and `athleteExerciseListProvider` (family key: `athleteUid`)
- `lib/features/workout/data/session_repository.dart` — possibly a new `listSetLogsByExercise` query if Firestore collection-group queries are used (advanced path); otherwise no changes needed
- `lib/features/coach/presentation/athlete_detail_screen.dart` — insert `ExerciseProgressionSection` below the existing session list in `_EntrenamientosSection`
- `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` — replace placeholder text at line 1516 with the new section
- New widget file: `lib/features/workout/presentation/widgets/exercise_progression_chart.dart`
- New widget file (optional, if exercise picker is a separate widget): `lib/features/workout/presentation/widgets/exercise_picker_row.dart`
- l10n: `lib/l10n/intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb` — new keys for the progression section (mobile only; web uses hardcoded Spanish + `// i18n`)

---

## Approaches

### Option A — Single provider, bounded scan, in-memory aggregation (RECOMMENDED)

Create one new provider `exerciseProgressionProvider(athleteUid, exerciseId)` that:
1. Calls `sessionsByUidProvider(athleteUid)` (already cached).
2. Takes the last N sessions (N=60 or 180-day window).
3. `Future.wait` on `listSetLogs` for each session.
4. Filters setLogs where `log.exerciseId == exerciseId`.
5. Aggregates: PR series (max weightKg per session), volume series (Σ reps×weightKg per session), frequency (sessions per week).

Separate `athleteExerciseListProvider(athleteUid)` builds the exercise picker list from the same scan (same sessions, same setLogs batch — reuse the cache from `sessionsByUidProvider`).

UX: the exercise picker is a horizontal chip/scrollable list above the chart, defaulting to the most-recently-performed exercise. The chart has a metric selector chip row (PR / Volumen / Frecuencia) reusing the `_MetricChipRow` pattern.

- Pros: zero new Firestore indexes, reuses existing pattern (proven in `lastWeightByExerciseProvider`), easy to test, bounded reads.
- Cons: 60 setLog reads on first mount per athlete (manageable; same as insights does for weekly view). Cache hit on second open if autoDispose is NOT used (or use keepAlive).
- Effort: Medium (1 new provider file, 1 chart widget, 2 insertion points)

| Metric | Computation |
|--------|-------------|
| PR | `max(log.weightKg)` per session (take heaviest set in that session) → one data point per session |
| Volumen | `Σ(log.reps × log.weightKg)` per session → one data point per session |
| Frecuencia | count of sessions per calendar week containing the exercise → bar series or trend line |

### Option B — Firestore collection-group query

Use Firestore collection-group query `collectionGroup('setLogs').where('exerciseId', ==, exerciseId)` to fetch all setLogs for one exercise directly, across all sessions.

- Pros: one query instead of N per-session reads; no scan of unrelated exercises.
- Cons: requires a new Firestore index (collection group index on `exerciseId`); security rules must explicitly allow collection-group reads for trainers (currently rules are path-scoped); adds infra complexity; the exercise picker list still requires the full session scan (so you'd need two different query strategies).
- Effort: High (index deployment, rules change, new repo method, more test complexity)

### Option C — Denormalized exerciseStats document

At session finish, write/update a `exerciseStats/{uid}/exercises/{exerciseId}` doc with running PR, total volume, last session date, session count.

- Pros: O(1) read per exercise for the chart; fast even with large history.
- Cons: requires write-side change in `SessionRepository.finish` (or a Cloud Function); migration needed for existing history; more complexity; risk of drift if setLogs are edited after session.
- Effort: High (new collection, migration, write-side change, test suite expansion)

---

## Design Options (UX)

### UX-1 — Single chart with metric tabs (chip selector)
One chart widget with PR / Volumen / Frecuencia chips at the top. Default metric: PR (most actionable for a trainer). X-axis = session date. Uses exactly the same `_ChartMetric` + `_MetricChipRow` pattern as `MeasurementProgressChart` and `PerformanceProgressChart`.

- Pros: minimal surface area, reuses proven pattern, one widget to test.
- Cons: switching metrics re-renders the chart (minor). Frecuencia as a line chart is slightly odd (it's a per-week count, not a per-session value) — could use a bar series for it.

### UX-2 — Three separate cards (PR / Volumen / Frecuencia)
Three stacked cards, each always visible, no chips needed.

- Pros: all metrics visible simultaneously.
- Cons: much more vertical space; heavy for mobile; three charts × N exercises = N×3 widgets.

### UX-3 — PR only (V1), defer volumen and frecuencia
Ship only the PR line chart. Volumen and frecuencia are noted as future.

- Pros: smallest scope, fastest to ship and test, validates the pattern.
- Cons: the placeholder explicitly lists three metrics; the proposal will need to justify the scope reduction.

---

## Recommendation

**Option A + UX-1** (bounded scan, in-memory aggregation, single chart with metric chips).

Reasoning:
- Zero new Firestore infrastructure.
- Directly mirrors the existing `lastWeightByExerciseProvider` pattern — the team already validated this approach.
- The `PerformanceProgressChart` widget is a near-perfect structural template: copy, adapt extractors, rename.
- Bounded to 60 sessions: safe read cost, covers realistic training history.
- Start with all three metrics (PR / Volumen / Frecuencia) using chip selector. Use line chart for PR and Volumen (per-session data points). For Frecuencia, compute per-week count and render as a BarChart or a step-line — decide in proposal.

**PR definition recommendation**: use raw `max(weightKg)` per session as the primary series. Optionally show Epley 1RM = `w × (1 + r/30)` in the chart header as a secondary stat. Do NOT use estimated 1RM as the chart Y-axis for V1 — it conflates reps and weight in a way that's hard to explain to athletes and trainers.

**Exercise picker**: horizontal chip row above the chart, populated from the same bounded scan (no extra reads). Default to most recently performed exercise. The existing `exercise_picker_sheet.dart` is for routine editing — do NOT reuse it here; build a lightweight chip row.

---

## Risks

1. **Read cost without a bound**: unbounded history scan (N sessions × setLogs each) could hit Firestore read limits and slow down the UI for power users. Mitigation: enforce 60-session / 180-day cap in the provider.

2. **Web Coach Hub i18n gap**: the mobile surface uses `AppL10n` for all coach strings; the web surface uses hardcoded Spanish + `// i18n` comments. New strings for the web tab must be hardcoded Spanish and marked `// i18n: Fase W2` — do NOT use `AppL10n` there. Mobile strings need new ARB keys.

3. **Dual-surface parity**: the chart widget itself (fl_chart LineChart, `AppPalette.of`) works on both mobile and web (Flutter renders both). The insertion point differs: mobile is a `Column` section inside a `ListView`, web is a tab `SingleChildScrollView`. Risk is low if the widget is stateless and palette-driven.

4. **No athlete-facing scope clarification**: the placeholder is PF-only, but there's no athlete-facing exercise progress view in the app. If the athlete should also see their own progression, that's a separate surface (e.g., in InsightsScreen). This change should be PF-only unless explicitly decided otherwise.

5. **Firestore rules for web Coach Hub**: the web app already uses `sessionsByUidProvider` and the `coachSessionSetLogsProvider` pattern. The stale comment in `alumno_detail_screen.dart` line 1452 ("setLogs que es owner-only") is incorrect — rules grant trainer read. No rules change is needed.

6. **autoDispose vs keepAlive**: `sessionsByUidProvider` is autoDispose. The new progression provider should also be autoDispose + family, so each exercise's data is dropped when the user navigates away. This prevents memory growth when the PF browses multiple athletes.

---

## Open Questions for Proposal

1. **All 3 metrics in V1, or PR-only?** The placeholder says all three. Shipping all three is feasible with chip selector (UX-1), but Frecuencia requires a different chart type (bar vs line). Recommend: clarify before design phase.

2. **Athlete-facing?** Should the athlete see their own exercise progression (e.g., in a new tab in InsightsScreen)? Current scope is PF-only. This could be a quick win but doubles the surfaces.

3. **Bounded window size**: 60 sessions vs 90 days vs "all-time with a performance warning"? Recommend 60 sessions for V1.

4. **Epley 1RM in header**: show estimated 1RM alongside raw PR in the chart header? Cosmetic decision, no data-model impact.

5. **Exercise picker UX on web**: chips may overflow on narrow sidebar width. Consider a DropdownButton or a scrollable chip row with fade mask on web.

---

## Ready for Proposal

Yes. Data layer is clear (no new Firestore infra needed). Chart infra is proven (fl_chart, `AppPalette`). Both surfaces and their insertion points are identified with file:line refs. Pending decisions: metrics scope (all 3 vs PR-only), bounded window size, and whether to add athlete-facing view.

# Proposal: exercise-progression

> Phase: propose · Change: `exercise-progression` · Project: treino · Store: hybrid
> Depends on: `sdd/exercise-progression/explore` (read, full content)
> Status: ready for `sdd-spec` + `sdd-design` (parallel)

---

## 1. Intent & motivation

**Problem.** The PF (trainer) can see an athlete's session history per training day, but has no way to answer the most basic coaching question: *"is this athlete getting stronger on a given exercise?"* Right now the per-exercise evolution is an empty promise — a literal placeholder string in the web Coach Hub (`alumno_detail_screen.dart:1516`: `'Próximamente: evolución por ejercicio (PR, volumen, frecuencia).'`) and a missing section on mobile (`athlete_detail_screen.dart`, `_EntrenamientosSection`).

**Why now.** We just shipped the real-loads loop (athletes log actual `weightKg`/`reps` per set, denormalized into `SetLog`). That data is now flowing and trustworthy. The progression view is the payoff of that loop: it turns logged sets into a coaching signal. The placeholder explicitly commits to this; this change pays the debt.

**Success looks like.** Opening an athlete's training tab (web) or the entrenamientos section (mobile), the PF picks an exercise from a chip row and immediately sees:
- a line chart of **PR** (default) or **Volumen** (toggled via a metric chip), per session over time;
- a **Frecuencia** stat near the chart ("X sesiones en las últimas N semanas");
- graceful empty states when the athlete has no logs or the exercise has fewer than 2 data points.

No new Firestore infrastructure, no athlete-facing surface, no migration.

---

## 2. Scope

### In scope

**(a) Data provider — `exerciseProgressionProvider(athleteUid, exerciseId)`**
- New `FutureProvider.autoDispose.family` in `lib/features/workout/application/session_providers.dart`, modeled exactly on `lastWeightByExerciseProvider` (verified `session_providers.dart:105–137`: `ref.watch(sessionsByUidProvider(uid).future)` → `Future.wait(scanned.map(repo.listSetLogs(...)))`).
- **Bounded scan**: take the last **~60 sessions** from `sessionsByUidProvider` (already DESC by `startedAt`) via `.take(60)`. No unbounded history scan, no collectionGroup.
- Filter setLogs to `log.exerciseId == exerciseId`, then aggregate **per session**:
  - **PR** = `max(log.weightKg)` over that exercise's sets in the session → one point per session.
  - **Volumen** = `Σ(log.reps × log.weightKg)` over that exercise's sets in the session → one point per session.
  - **Frecuencia** = count of sessions containing the exercise within a fixed recent window (see §4).
- Returns a small value object (shape decided in `sdd-spec`/`sdd-design`): two time-ordered series (`{date, value}`) + a frequency summary. **No `weekNumber` reuse** — `Session.weekNumber` is periodization metadata, not a calendar week; Frecuencia must bucket by `startedAt`.

**(b) Exercise picker — built from the same scan**
- A lightweight horizontal chip row populated from the bounded scan: collect `(exerciseId, exerciseName)` across the scanned setLogs, dedupe by `exerciseId`. `exerciseName` is denormalized in `SetLog` (verified `set_log.dart:11`) — **no exercise-catalogue lookup, no Firestore reads beyond the scan already done**.
- **Do NOT reuse `exercise_picker_sheet.dart`** (that's for routine editing). Build a dedicated lightweight chip row.
- A second `autoDispose.family` provider (`athleteExerciseListProvider(athleteUid)`) feeds the picker, reusing the cached `sessionsByUidProvider` so the scan is not duplicated.

**(c) Progression chart widget**
- New widget `lib/features/workout/presentation/widgets/exercise_progression_chart.dart`, structurally templated on `PerformanceProgressChart` (verified `_ChartMetric { label(AppL10n), unit, extractor }` + `_MetricChipRow` + `_ProgressLineChart` pattern, fl_chart `LineChart`, `AppPalette.of(context)`, `intl.DateFormat('d MMM', locale)`).
- Two metrics in the chip row — **PR (default)** and **Volumen** — both rendered as fl_chart lines.
- **Frecuencia** is a **simple stat** (text/badge) above or beside the chart, NOT a line on the chart. It is a per-window count, not a per-session value — putting it on the same Y-axis is semantically wrong.

**(d) Wire into BOTH surfaces (PF-facing)**
- **Web Coach Hub** — `coach_hub/.../alumno_detail_screen.dart`, `_EntrenamientoTab` (verified `SingleChildScrollView > Column(crossAxisAlignment: stretch)`): replace the placeholder `Text` at line 1516 with the new section. Strings hardcoded Spanish + `// i18n: Fase W2`.
- **Mobile coach** — `coach/.../athlete_detail_screen.dart`, `_EntrenamientosSection`: insert the section after the session-list card (verified card `Column` closes ~line 1609–1612). Strings via `AppL10n` (new ARB keys).

**(e) Empty / degenerate states**
- Athlete with zero setLogs across the scan → no picker, friendly "sin datos" message.
- Selected exercise with **< 2 data points** → no trend line; show the single value (or a "necesitás al menos 2 sesiones" hint). Decided concretely in `sdd-design`.

### Out of scope (explicit)

- **Athlete-facing progression view.** PF-only. The athlete does not get this surface in this change (LOCKED with user). No changes to `InsightsScreen`.
- **Estimated 1RM (Epley) as the PR series.** PR uses raw `max(weightKg)` (see §4 recommendation). Epley is at most a header stat, deferred.
- **Firestore collectionGroup query** (explore Option B) and **denormalized `exerciseStats` doc** (explore Option C). No new index, no rules change, no write-side change, no migration.
- **Three-separate-cards UX** (explore UX-2) and **PR-only V1** (explore UX-3). We ship PR + Volumen chips + Frecuencia stat.
- New repository methods. `SessionRepository.listSetLogs` already covers the read; no `listSetLogsByExercise`.

---

## 3. Approach & rationale

**Chosen: explore Option A + UX-1 (bounded in-memory aggregation, single chart with metric chips).**

```
exerciseProgressionProvider(athleteUid, exerciseId)        athleteExerciseListProvider(athleteUid)
        │                                                          │
        └── sessionsByUidProvider(athleteUid)  ◄── shared cache ──┘
                    │  .take(60)
                    └── Future.wait(listSetLogs per session)
                              │
              filter exerciseId          collect (exerciseId, exerciseName), dedupe
                              │                            │
        PR series / Volumen series / Frecuencia      picker chips
```

Rationale:
- **Mirrors a proven, live pattern.** `lastWeightByExerciseProvider` already does session-fan-out + setLog aggregation in production. We are extending a validated approach, not inventing one. Lowest risk.
- **Zero new infrastructure.** No index deploy, no rules change (trainer read of athlete setLogs is already granted via `session_shares`, validated by the live `coachSessionSetLogsProvider`).
- **Chart template is near-perfect.** `PerformanceProgressChart` gives us the chip selector, line chart, palette wiring, and localized date axis for free.
- **Bounded reads** keep cost predictable (see risk #1).
- **Testable in isolation.** Aggregation is pure given a list of setLogs — trivial to unit-test (see §6).

---

## 4. Micro-decisions — RECOMMENDED (confirm/override in spec/design)

| # | Decision | Recommendation | Why |
|---|----------|----------------|-----|
| D1 | **PR metric** | **Raw `max(weightKg)` per session.** | Defensible, explainable to athlete/PF, no reps-entry sensitivity. Epley (`w·(1+r/30)`) conflates reps and weight and is hard to explain. Offer Epley later as an optional header stat, not the series. |
| D2 | **Frecuencia window** | **Last 8 weeks (≈56 days), bucketed by `startedAt`.** Render as a single stat: "N sesiones en las últimas 8 semanas". | 8 weeks is a meaningful training block; one number is honest for a count metric. Window is independent of the 60-session scan bound. |
| D3 | **Default selected exercise** | **Most-recently-logged** exercise (first hit when scanning DESC sessions). | Matches what the PF most likely wants to inspect; deterministic, free from the existing scan order. |
| D4 | **Chart with < 2 points** | **No line.** Show the single value as a stat + hint ("necesitás ≥ 2 sesiones para ver evolución"). | A 1-point line chart is misleading. Keep it honest. |
| D5 | **Provider lifecycle** | **`autoDispose` + family** (like `lastWeightByExerciseProvider` and `coachSessionSetLogsProvider`). | The PF browses many athletes; keepAlive would accumulate per-(athlete,exercise) caches and grow memory unbounded. `sessionsByUidProvider` is itself autoDispose and stays warm during the visit, so re-selecting exercises within one athlete view still hits its cache — the ~60 reads happen once per athlete visit, not per chip tap. autoDispose wins. |
| D6 | **Scan bound** | **`.take(60)` sessions** (no day cap for V1). | Simplest; 60 sessions ≈ a long training history. Surface the bound in copy if data looks clipped ("últimas 60 sesiones"). |

Net for the spec: PR = raw max weight, Frecuencia = 8-week count stat, default = most-recent exercise, `autoDispose`, 60-session bound, `<2` points → no line.

---

## 5. Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | **Read cost** — up to ~60 subcollection `listSetLogs` reads on mount per athlete visit. | Medium | Hard `.take(60)` bound; reads happen once per athlete visit (autoDispose keeps `sessionsByUidProvider` warm within the view, see D5); same pattern weekly insights already runs. If a power-PF cost shows up later, the documented escape hatch is the denormalized `exerciseStats` doc (explore Option C) — out of scope now. |
| R2 | **fl_chart on web is UNVERIFIED in THIS app's Coach Hub.** Grep confirms fl_chart `^1.2.0` is in pubspec and used in `performance`/`measurements`, but **never imported anywhere in `coach_hub`**. The explore *assumed* parity; it is not a proven fact for the web build. | **High / must-resolve** | `sdd-design` (or first `sdd-apply` slice) MUST run a thin spike: drop a minimal fl_chart `LineChart` into `_EntrenamientoTab` and confirm it renders in the Flutter **web** build (CanvasKit/HTML renderer) before committing to the chart on web. If it does not render cleanly, fall back to a web-only lightweight chart or defer the web surface. Do not assume parity. |
| R3 | **Dual-surface i18n divergence.** Mobile uses `AppL10n` (new ARB keys in `intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb`); web Coach Hub uses hardcoded Spanish + `// i18n: Fase W2` (verified throughout `_EntrenamientoTab`). | Medium | One shared widget, two string-source strategies. The chart widget takes its labels as parameters (or via an injected label resolver) so the SAME widget serves both surfaces. Never call `AppL10n` from inside the web path. |
| R4 | **Frecuencia semantics.** Using `Session.weekNumber` (periodization) instead of calendar weeks would silently corrupt the stat. | Medium | Bucket strictly by `startedAt` over a fixed day window (D2). Explicitly forbid `weekNumber` in the spec. |
| R5 | **Empty / single-point states** look broken if unhandled (blank chart). | Low | Scope item (e) + D4 make these first-class. |

Open question carried into design: **R2 spike outcome** — does fl_chart render in the web build? If NO, web surface scope may shrink. Everything else is decided.

---

## 6. Testing / TDD

**Strict TDD is active** (gate: `flutter analyze` 0 issues + `dart format .` + `flutter test`). Tests precede implementation.

Test surfaces:
1. **Provider aggregation (pure, highest value)** — feed fake `SetLog`/`Session` fixtures, assert:
   - PR series = `max(weightKg)` per session, time-ordered;
   - Volumen series = `Σ(reps×weightKg)` per session;
   - Frecuencia = correct count within the 8-week window (boundary cases: session exactly at window edge);
   - bound respected (>60 sessions → only last 60 scanned);
   - empty input → empty series.
2. **Exercise list provider** — dedupe by `exerciseId`, correct `exerciseName`, most-recent ordering (D3).
3. **Chart widget states** — golden/widget tests for: data (≥2 points), single point (no line, D4), empty (no chart). Metric chip toggles PR↔Volumen.
4. **Picker widget** — renders one chip per distinct exercise, selection callback fires, default = most-recent.

Repository/Firestore reads are mocked (fake repo returning fixture setLogs) — no live Firestore in tests.

---

## 7. Review Workload Forecast

| Item | Estimate |
|------|----------|
| New provider(s) in `session_providers.dart` | ~70–110 lines |
| New chart widget `exercise_progression_chart.dart` | ~220–300 lines (templated on PerformanceProgressChart) |
| Picker (chip row, may live in same file or own widget) | ~60–90 lines |
| Web wiring (`alumno_detail_screen.dart`) | ~30–50 lines |
| Mobile wiring (`athlete_detail_screen.dart`) | ~30–50 lines |
| ARB keys (3 files) | ~15–30 lines |
| Tests (provider + widget + picker) | ~200–300 lines |
| **Total (excl. generated/formatting)** | **~600–900 lines** |

**400-line budget risk: High.** **Chained PRs recommended: Yes.** Natural split mirrors the set-logs change:
- **PR 1 — data + chart + mobile surface**: provider(s) + tests + chart/picker widgets + mobile wiring + ARB keys. Self-contained and shippable (mobile lights up).
- **PR 2 — web surface**: web wiring, gated on the **R2 fl_chart-on-web spike**. If the spike fails, this PR pivots to a fallback or is deferred.

**Decision needed before apply: Yes** — `sdd-tasks`/orchestrator must confirm the chained split and surface the cached `delivery_strategy`. The R2 spike result is a hard gate for the web slice.

---

## 8. Handoff to next phases

- **`sdd-spec`** — formalize: provider value-object shape, exact metric formulas (PR/Volumen/Frecuencia with D1/D2 locked), empty/degenerate-state behavior (D4), exercise-list ordering (D3), bound (D6), required ARB keys.
- **`sdd-design`** — chart widget structure (label-injection so one widget serves both i18n strategies), picker layout (chip-row overflow on narrow web sidebar — explore open Q5), provider wiring/caching, and **run the R2 fl_chart-on-web spike**.

Spec and design can proceed in parallel; both depend only on this proposal.

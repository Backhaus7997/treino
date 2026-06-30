# Technical Design: exercise-progression

> Phase: design · Change: `exercise-progression` · Project: treino · Store: hybrid
> Depends on: `sdd/exercise-progression/proposal` (obs #111, read in full)
> Pairs with: `sdd/exercise-progression/spec` (REQ-PROG-*). Feeds: `sdd-tasks`.
> Locked decisions (D1–D6, scope) are NOT re-opened here. This is the HOW.

---

## 0. R2 VERDICT — fl_chart on web Coach Hub

**Verdict: SAFE.** Confidence: **High (~0.9).** No production-code spike performed (a full
`flutter build web` is too heavy for this phase, per instructions). The verdict rests on
direct evidence gathered this phase, not the explore's unverified parity assumption.

### Evidence

1. **fl_chart is pure-Flutter `CustomPaint`.** The live chart (`performance_progress_chart.dart:1`
   imports only `package:fl_chart/fl_chart.dart`; uses `LineChart` / `LineChartData` / `FlSpot` /
   `FlDotCirclePainter`). No `dart:io`, no platform channels, no native plugin registrant. Pure-Dart
   CustomPaint packages render identically across mobile and web (CanvasKit) — there is no
   platform-specific surface to fail.
2. **fl_chart `^1.2.0` (pubspec.yaml:59) officially supports web.** 1.x lists web as a supported
   platform; it has no conditional-import or FFI escape hatch that would degrade on web.
3. **The web entrypoint uses the modern loader** (`web/index.html:45` → `flutter_bootstrap.js`,
   Flutter ≥3.22). On desktop browsers this defaults to the **CanvasKit** renderer — the renderer
   where CustomPaint is most robust. No HTML-renderer pin, no custom renderer config that could
   strip canvas drawing.
4. **The web data path is ALREADY proven in production.** The explore/proposal flagged that fl_chart
   was "never imported in coach_hub" — true, but the *data* dependency (cross-user setLog reads) is
   the part that was genuinely unproven, and it is NOT unproven: `_SetLogsExpansion` on web
   (`alumno_detail_screen.dart:1731`) already calls `coachSessionSetLogsProvider` in the shipped
   Coach Hub. So the only new thing PR2 introduces on web is *a `LineChart` CustomPaint widget*, not
   a new data or permission path.

### What PR2 apply MUST verify before merge (gate, not a blocker)

A **5-minute web smoke check**, not a code spike:
- `flutter run -t lib/main_coach_hub.dart -d chrome` (the documented local command,
  `main_coach_hub.dart:18`), open an athlete's Entrenamiento tab, confirm the `LineChart` paints
  (axes, line, dots, tooltip on hover) and chip toggle works.
- If, against expectation, CanvasKit fails to paint the chart on the target browser, the documented
  fallback (proposal R2) is a web-only lightweight chart or deferral of the PR2 *chart* (the
  Frecuencia stat + picker are plain widgets and ship regardless). This is the ONLY web-specific
  risk and it is contained to PR2.

**Net:** PR1 (mobile) is unaffected by R2 and ships unconditionally. PR2 is SAFE to plan; its apply
opens with the smoke check.

### Bonus finding — R-RULES is RESOLVED, not a blocker

The web `_EntrenamientoTab` docstring (`alumno_detail_screen.dart:1452-1453`) claims per-exercise
evolution was deferred because "setLogs is owner-only in firestore.rules." **That comment is
STALE.** `firestore.rules:507-520` grants trainer **read** on `setLogs`, mirroring the session-share
predicate (owner OR linked trainer); write stays owner-only. Emulator scenarios E1/E2 (linked
reads/lists → allowed) confirm it, and the live web `_SetLogsExpansion` exercises exactly this path.
**No rules change is needed.** PR2 should delete/replace that stale docstring.

---

## 1. Architecture approach

**Pattern:** extend the existing **feature-first + Riverpod-derived-read** approach. No new layer, no
new repository method, no Firestore infra. Two new `autoDispose.family` providers in the workout
feature derive everything from the already-cached `sessionsByUidProvider`. One new presentation
widget (chart) + one small picker widget, both label-injected so a SINGLE widget serves both i18n
strategies (mobile AppL10n, web hardcoded).

```
                exerciseProgressionProvider(({athleteUid, exerciseId}))
                          │                         athleteExerciseListProvider(athleteUid)
                          │                                   │
                          └────── sessionsByUidProvider(athleteUid) ◄── shared autoDispose cache
                                            │  .take(60)   (DESC by startedAt)
                          ┌─────────────────┴──────────────────┐
                          │ Future.wait(repo.listSetLogs/session)│  (one fan-out, shared shape)
                          └─────────────────┬──────────────────┘
            ┌──────────────────────┬────────┴───────────────┬─────────────────────┐
       filter exerciseId      PR series              Volumen series          collect distinct
            │                 max(weightKg)/sess     Σ(reps·weightKg)/sess    (id,name) DESC → list
       Frecuencia(8wk count)        │                       │                        │
            └──────────► ExerciseProgression value object ◄─┘              ExerciseListEntry[]
                                    │                                                │
                          ExerciseProgressionChart (label-injected) ◄── picker chips (ExercisePickerRow)
                                    │
                ┌───────────────────┴───────────────────┐
        mobile: AppL10n labels                  web: hardcoded ES labels + // i18n
   athlete_detail_screen._EntrenamientosSection   alumno_detail_screen._EntrenamientoTab
```

**Layering / boundaries:**
- `application/` (providers) — pure aggregation, no widgets, no AppL10n. Unit-testable in isolation.
- `domain/` — value objects (`ExerciseProgression`, `ExerciseListEntry`) as freezed types.
- `presentation/widgets/` — `exercise_progression_chart.dart` (chart + Frecuencia stat + picker).
  Takes ALL display strings as parameters → **never imports AppL10n** → safe on web (R3).

---

## 2. Data layer — providers

### 2.1 Value objects (`lib/features/workout/domain/exercise_progression.dart`, freezed)

One immutable result type for the chart, one tiny entry type for the picker. Freezed is already the
project convention (`set_log.dart`, `session.dart`).

```dart
@freezed
class ExerciseProgression with _$ExerciseProgression {
  const factory ExerciseProgression({
    required String exerciseId,
    required String exerciseName,
    /// PR per session, ASC by date (oldest → newest). One point per session
    /// that contains the exercise. value = max(weightKg) in that session.
    required List<ProgressionPoint> prSeries,
    /// Volume per session, ASC by date. value = Σ(reps·weightKg) in that session.
    required List<ProgressionPoint> volumeSeries,
    /// Count of sessions containing the exercise within the last 8 weeks (D2),
    /// bucketed by Session.startedAt. NOT a line; rendered as a stat.
    required int frequencyLast8Weeks,
  }) = _ExerciseProgression;

  factory ExerciseProgression.empty(String exerciseId) => ExerciseProgression(
        exerciseId: exerciseId, exerciseName: '',
        prSeries: const [], volumeSeries: const [], frequencyLast8Weeks: 0,
      );
}

@freezed
class ProgressionPoint with _$ProgressionPoint {
  const factory ProgressionPoint({
    required DateTime date,   // Session.startedAt (UTC, render as-is — see §3.4)
    required double value,
  }) = _ProgressionPoint;
}

@freezed
class ExerciseListEntry with _$ExerciseListEntry {
  const factory ExerciseListEntry({
    required String exerciseId,
    required String exerciseName,
  }) = _ExerciseListEntry;
}
```

> Records vs freezed: chart result has 3+ fields consumed across widget rebuilds and asserted in many
> tests → freezed (stable `==`, named, codegen'd `copyWith`). `ProgressionPoint` could be a record but
> stays freezed for one consistent fixture type in tests. `ExerciseListEntry` likewise.

### 2.2 `athleteExerciseListProvider` — feeds the picker

`session_providers.dart` (new provider, beside `lastWeightByExerciseProvider`). Reuses the shared
`sessionsByUidProvider` cache and the SAME 60-session bound, so no duplicated scan.

```dart
const int _kProgressionSessionScan = 60; // D6. Shared by both providers.

/// Distinct exercises the athlete has logged in the last 60 sessions, ordered
/// MOST-RECENT FIRST (D3: first hit when scanning DESC sessions wins position).
/// exerciseName is denormalized in SetLog (set_log.dart:13) — no catalogue read.
final athleteExerciseListProvider = FutureProvider.autoDispose
    .family<List<ExerciseListEntry>, String>((ref, athleteUid) async {
  if (athleteUid.isEmpty) return const [];
  final sessions = await ref.watch(sessionsByUidProvider(athleteUid).future);
  final repo = ref.read(sessionRepositoryProvider);
  final scanned = sessions.take(_kProgressionSessionScan).toList(); // DESC
  final logsPerSession = await Future.wait(
    scanned.map((s) => repo.listSetLogs(uid: athleteUid, sessionId: s.id)),
  );
  // Preserve first-seen (most-recent) order via LinkedHashMap semantics.
  final seen = <String, ExerciseListEntry>{};
  for (final logs in logsPerSession) {           // sessions DESC
    for (final log in logs) {
      seen.putIfAbsent(log.exerciseId,
          () => ExerciseListEntry(
              exerciseId: log.exerciseId, exerciseName: log.exerciseName));
    }
  }
  return seen.values.toList(growable: false);
});
```

### 2.3 `exerciseProgressionProvider` — PR / Volumen / Frecuencia

`session_providers.dart` (new provider). Mirrors `lastWeightByExerciseProvider` exactly: watch the
shared sessions cache, `Future.wait` the per-session `listSetLogs`. **Aggregation logic is delegated
to a pure top-level function** so it is testable WITHOUT Riverpod (highest-value tests, §6).

```dart
typedef ExerciseProgressionKey = ({String athleteUid, String exerciseId});

final exerciseProgressionProvider = FutureProvider.autoDispose
    .family<ExerciseProgression, ExerciseProgressionKey>((ref, key) async {
  if (key.athleteUid.isEmpty || key.exerciseId.isEmpty) {
    return ExerciseProgression.empty(key.exerciseId);
  }
  final sessions = await ref.watch(sessionsByUidProvider(key.athleteUid).future);
  final repo = ref.read(sessionRepositoryProvider);
  final scanned = sessions.take(_kProgressionSessionScan).toList(); // DESC
  final logsPerSession = await Future.wait(
    scanned.map((s) => repo.listSetLogs(uid: key.athleteUid, sessionId: s.id)),
  );
  // Pair each session with its logs so aggregation can read startedAt.
  final pairs = <({Session session, List<SetLog> logs})>[
    for (var i = 0; i < scanned.length; i++)
      (session: scanned[i], logs: logsPerSession[i]),
  ];
  return aggregateExerciseProgression(
    exerciseId: key.exerciseId,
    sessionsDesc: pairs,
    now: DateTime.now().toUtc(), // injectable in tests for the 8-week window
  );
});
```

**Pure aggregator** (same file, top-level, `@visibleForTesting`-friendly):

```dart
ExerciseProgression aggregateExerciseProgression({
  required String exerciseId,
  required List<({Session session, List<SetLog> logs})> sessionsDesc,
  required DateTime now,
}) {
  const window = Duration(days: 56); // D2: 8 weeks ≈ 56 days, bucket by startedAt
  final cutoff = now.subtract(window);
  final pr = <ProgressionPoint>[];
  final vol = <ProgressionPoint>[];
  var freq = 0;
  String name = '';
  for (final p in sessionsDesc) {                       // DESC iteration
    final logs = p.logs.where((l) => l.exerciseId == exerciseId).toList();
    if (logs.isEmpty) continue;
    name = name.isEmpty ? logs.first.exerciseName : name;
    final maxW = logs.map((l) => l.weightKg).reduce((a, b) => a > b ? a : b); // D1
    final volume = logs.fold<double>(0, (s, l) => s + l.reps * l.weightKg);
    pr.add(ProgressionPoint(date: p.session.startedAt, value: maxW));
    vol.add(ProgressionPoint(date: p.session.startedAt, value: volume));
    if (!p.session.startedAt.isBefore(cutoff)) freq++;   // R4: startedAt, not weekNumber
  }
  // Provider receives DESC; chart wants ASC (oldest → newest). Reverse once here.
  return ExerciseProgression(
    exerciseId: exerciseId,
    exerciseName: name,
    prSeries: pr.reversed.toList(growable: false),
    volumeSeries: vol.reversed.toList(growable: false),
    frequencyLast8Weeks: freq,
  );
}
```

**Decisions baked in:**
- D1 PR = raw `max(weightKg)`. D2 Frecuencia = sessions with `startedAt >= now-56d`, counted on the
  bounded scan (window ⊆ scan in practice). R4 enforced: `Session.weekNumber` is NEVER read here.
- D6 bound `.take(60)` shared via `_kProgressionSessionScan`.
- Ordering: provider reverses DESC→ASC ONCE so the chart receives oldest→newest (matches
  `PerformanceProgressChart` contract: "sorted ascending by recordedAt").
- `now` is a parameter → window boundary cases are deterministic in tests (REQ-PROG edge scenarios).
- Empty athleteUid/exerciseId short-circuits with no Firestore read (mirrors
  `coachSessionSetLogsProvider:149`).

---

## 3. Chart widget — reuse strategy

### 3.1 Decision: COPY-AND-ADAPT, do NOT generalize the existing widget

`PerformanceProgressChart._ChartMetric.label` is typed `String Function(AppL10n)`
(`performance_progress_chart.dart:33`). Parametrizing the existing widget to also serve web would
force `AppL10n` (or a shim) into the web import graph — directly violating **R3** ("never call AppL10n
from inside the web path"). The chart-drawing internals (`_ProgressLineChart`, axis/tooltip/Y-padding
logic, `_labelIndices`) are ~180 lines of value-free geometry we DO want to reuse.

**Plan:** new file `lib/features/workout/presentation/widgets/exercise_progression_chart.dart` that
copies `_ProgressLineChart` + `_MetricChipRow` + `_Chip` + `_shortDate` + `_labelIndices` near-verbatim
(they already take `palette` + plain values), and replaces the metric model so **all strings are
`String` parameters**, never resolved from AppL10n. The data model is `ProgressionPoint`, not
`PerformanceTest`.

> Why copy and not import the private internals: they are file-private (`_`-prefixed) in the
> performance feature and tied to `PerformanceTest`. Cross-feature import of privates is impossible and
> a public extraction is out of scope (would touch the performance feature). Copy keeps the change
> contained to the workout feature. ~200 lines, as the proposal forecast.

### 3.2 Public API (label-injected — the R3 seam)

```dart
class ExerciseProgressionChart extends StatefulWidget {
  const ExerciseProgressionChart({
    super.key,
    required this.progression,        // ExerciseProgression value object
    required this.labels,             // ALL display strings (see below)
    required this.localeName,         // 'es' | 'es_AR' | 'en' for intl.DateFormat
  });
  final ExerciseProgression progression;
  final ExerciseProgressionChartLabels labels;
  final String localeName;
  ...
}

/// Plain string bag. Mobile builds it from AppL10n; web builds it from
/// hardcoded constants. The widget never knows which source it came from.
class ExerciseProgressionChartLabels {
  const ExerciseProgressionChartLabels({
    required this.prLabel,            // "PR"
    required this.volumeLabel,        // "Volumen"
    required this.prUnit,             // "kg"
    required this.volumeUnit,         // "kg" (volume is kg·reps; display "kg")
    required this.frequencyLabel,     // (int n) => "N sesiones en las últimas 8 semanas"
    required this.singlePointHint,    // "Necesitás ≥2 sesiones para ver evolución" (D4)
    required this.emptyHint,          // "Sin datos para este ejercicio"
  });
  final String prLabel, volumeLabel, prUnit, volumeUnit, singlePointHint, emptyHint;
  final String Function(int) frequencyLabel;
}
```

### 3.3 Internal structure & states (maps to REQ-PROG scenarios)

Metric model becomes a tiny local descriptor over the value object (NOT over AppL10n):

```dart
class _Metric {
  const _Metric({required this.label, required this.unit, required this.series});
  final String label; final String unit; final List<ProgressionPoint> series;
}
// built in build(): PR first (DEFAULT), then Volumen.
// _selected initialized to the PR metric (D-default = PR).
```

Render order inside the card `Column(crossAxisAlignment: start)`:
1. **Frecuencia stat** (badge/text): `labels.frequencyLabel(progression.frequencyLast8Weeks)`.
   Placement: a small stat row ABOVE the chip row (per proposal "above or beside"). Always shown when
   there is ≥1 point; hidden in the fully-empty state.
2. **Metric chip row** (`_MetricChipRow`, PR | Volumen). PR selected by default (D-default).
3. **Header** (current value + ▲/▼ delta + span) — only when selected series has ≥2 points (reuse
   `_ChartHeader` logic, strings from `labels`/computed).
4. **Chart / state**:
   - selected series **≥2 points** → `_ProgressLineChart` (line). [REQ-PROG data scenario]
   - selected series **==1 point** → single value text + `labels.singlePointHint`, **no line** (D4).
     [REQ-PROG single-point scenario]
   - both series empty (exercise had no qualifying logs) → `labels.emptyHint`, no chart.
     [REQ-PROG empty scenario]

> The fully-empty *athlete* case (zero exercises at all) is handled UPSTREAM by the wiring: if
> `athleteExerciseListProvider` returns `[]`, the surface shows a "sin datos" message and never mounts
> the picker/chart (scope item (e)). The chart's own `emptyHint` covers the narrower "selected
> exercise has no points" case.

### 3.4 Date convention (carry the existing rule)

`ProgressionPoint.date = Session.startedAt`. Render with `intl.DateFormat('d MMM', localeName)` reading
the DateTime's own fields, **no `.toLocal()`** — identical to `performance_progress_chart.dart:19-20`.
Consistent with every other `startedAt` reader in the app.

---

## 4. Exercise picker — chip-row widget

Same file (`exercise_progression_chart.dart`) or a sibling `exercise_picker_row.dart`; keep in the
same file to share the `_Chip` style and stay under the widget count. **Do NOT reuse
`exercise_picker_sheet.dart`** (routine-editing concern — proposal scope (b)).

```dart
class ExercisePickerRow extends StatelessWidget {
  const ExercisePickerRow({
    super.key,
    required this.exercises,          // List<ExerciseListEntry>, most-recent first (D3)
    required this.selectedId,
    required this.onSelect,           // ValueChanged<String> (exerciseId)
  });
  ...
}
```

- Horizontal `SingleChildScrollView` of pill chips (reuse `_Chip` visual: `palette.accent` when
  selected, `palette.border` otherwise). Handles narrow web sidebar overflow by scrolling (explore
  open Q5 — scroll, do not wrap, to match the existing `_MetricChipRow`).
- One chip per `ExerciseListEntry`; `selectedId` drives highlight; tap → `onSelect(id)`.
- Default selection (most-recent) is owned by the WIRING state, not the picker: the parent holds
  `selectedExerciseId`, initialized to `exercises.first.exerciseId` (D3).

---

## 5. Wiring

### 5.1 Mobile (PR1) — `coach/presentation/athlete_detail_screen.dart`

> NOTE: correct path is `lib/features/coach/presentation/athlete_detail_screen.dart` (NOT
> `.../screens/...`). `_EntrenamientosSection` is at **line 1540**, a `ConsumerWidget`; its `Column`
> closes ~line 1613 after the session-list card.

Insert a new section AFTER the session-list card (after line ~1611, inside the same `Column`):

```dart
const SizedBox(height: 20),
// Per-exercise progression (REQ-PROG). Reuses athleteExerciseListProvider +
// exerciseProgressionProvider. Stateful sub-widget owns the selected exercise.
_ProgressionSection(athleteId: athleteId),   // NEW ConsumerStatefulWidget, same file
```

`_ProgressionSection` (new, mobile-only, same file):
- `ref.watch(athleteExerciseListProvider(athleteId))`.
  - loading → `_card` spinner; error → existing `coachSessionSetLogsLoadError` / no-share copy;
    data `[]` → `_card` with `l10n.progressionEmpty` (sin datos).
  - data non-empty → hold `selectedExerciseId` (init `first.id`, D3); render
    `ExercisePickerRow` + `ExerciseProgressionChart`.
- `ref.watch(exerciseProgressionProvider((athleteUid: athleteId, exerciseId: selectedExerciseId)))`
  → on data, build `ExerciseProgressionChartLabels` from `AppL10n.of(context)` and pass in.
- Section header `Text('EVOLUCIÓN POR EJERCICIO' …)` via `l10n.progressionSectionTitle` (style mirrors
  the existing `HISTORIAL DE SESIONES` Barlow-condensed header at line 1556).

**New AppL10n keys** (add to `intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb` — three files, with
`@`-metadata blocks; `progressionFrequency` uses ICU plural like `performanceChartSpanWeeks`):

| Key | es_AR / es value | Notes |
|-----|------------------|-------|
| `progressionSectionTitle` | "EVOLUCIÓN POR EJERCICIO" | section header |
| `progressionMetricPr` | "PR" | chip + label |
| `progressionMetricVolume` | "Volumen" | chip + label |
| `progressionFrequency` | "{count} {count, plural, =1{sesión} other{sesiones}} en las últimas 8 semanas" | placeholder `count:int` |
| `progressionSinglePointHint` | "Necesitás al menos 2 sesiones para ver la evolución." | D4 |
| `progressionEmptyExercise` | "Sin datos para este ejercicio todavía." | selected-exercise empty |
| `progressionEmpty` | "Todavía no hay ejercicios registrados." | athlete has zero logs |

> `prUnit`/`volumeUnit` = "kg" — reuse literal "kg" (matches `_ChartMetric unit: 'kg'`), not a new key.

### 5.2 Web (PR2, gated on R2 smoke check) — `coach_hub/.../alumno_detail_screen.dart`

> `_EntrenamientoTab` is a `ConsumerWidget` at **line 1454**, body is
> `SingleChildScrollView > Column(crossAxisAlignment: stretch)`. Placeholder `Text` at **line 1516**.

- **Replace** the placeholder `Text` (lines 1515-1518) with the progression section.
- **Delete/replace** the stale deferral docstring (lines 1452-1453) — see §0 bonus finding.
- Build a web-local `_ProgressionTabSection` (same file) mirroring mobile's `_ProgressionSection` but:
  - strings are **hardcoded Spanish constants + `// i18n: Fase W2`** (matches the whole tab's
    convention, e.g. line 1470).
  - `ExerciseProgressionChartLabels` built from those constants; `localeName: 'es_AR'` hardcoded.
  - **never** imports/calls `AppL10n` (R3).
- Watches the SAME two providers (`athleteExerciseListProvider`, `exerciseProgressionProvider`) — data
  path already proven on web via `coachSessionSetLogsProvider` (§0 evidence #4).

Hardcoded web strings (constants): `'EVOLUCIÓN POR EJERCICIO'`, `'PR'`, `'Volumen'`,
`(n) => '$n ${n == 1 ? 'sesión' : 'sesiones'} en las últimas 8 semanas'`,
`'Necesitás al menos 2 sesiones para ver la evolución.'`, `'Sin datos para este ejercicio todavía.'`,
`'Todavía no hay ejercicios registrados.'` — each with `// i18n: Fase W2`.

---

## 6. Test plan (strict TDD — tests precede impl)

Gate: `flutter analyze` 0 issues + `dart format .` + `flutter test`. Repo/Firestore mocked
(`mocktail` / fake repo returning fixture setLogs) — no live Firestore. Fixtures: `Session` +
`SetLog` builders.

| # | Test (file) | Asserts | REQ scenario |
|---|-------------|---------|--------------|
| T1 | `aggregate_exercise_progression_test.dart` — PR series | `prSeries` = `max(weightKg)` per session, **ASC by date**; one point per session containing the exercise | REQ-PROG PR |
| T2 | same — Volumen series | `volumeSeries` = `Σ(reps·weightKg)` per session, ASC | REQ-PROG Volumen |
| T3 | same — Frecuencia window | count = sessions with `startedAt >= now-56d`; **boundary**: session exactly at `now-56d` is counted, at `now-56d-1s` is not; pass fixed `now` | REQ-PROG Frecuencia + edge |
| T4 | same — never uses weekNumber | sessions with same `startedAt` but different `weekNumber` collapse correctly; changing only `weekNumber` does NOT change Frecuencia | R4 / REQ-PROG |
| T5 | same — exercise filter & empty | logs of OTHER exercises ignored; exercise absent → empty series + freq 0 | REQ-PROG empty |
| T6 | same — name resolution | `exerciseName` = denormalized name from first (most-recent) matching log | REQ-PROG picker label |
| T7 | `exercise_progression_provider_test.dart` (ProviderContainer + fake repo) — bound | >60 sessions provided → only newest 60 scanned (`listSetLogs` called ≤60×) | D6 / REQ-PROG bound |
| T8 | same — empty key short-circuit | empty `athleteUid` or `exerciseId` → `.empty`, **zero** `listSetLogs` calls | guard |
| T9 | `athlete_exercise_list_provider_test.dart` — dedupe + order | distinct by `exerciseId`; most-recent-first ordering (D3); correct `exerciseName` | REQ-PROG picker |
| T10 | `exercise_progression_chart_test.dart` (widget) — data | ≥2 points → `LineChart` present; chip toggle PR↔Volumen switches series | REQ-PROG data |
| T11 | same — single point | 1 point → NO `LineChart`, single value + `singlePointHint` shown | D4 / REQ-PROG single |
| T12 | same — empty | both series empty → `emptyHint`, no chart, no header | REQ-PROG empty |
| T13 | same — Frecuencia stat | `frequencyLabel(n)` rendered; default selected metric == PR | D-default / Frecuencia |
| T14 | same — no AppL10n | widget renders with a plain `ExerciseProgressionChartLabels` and NO `Localizations` ancestor (proves R3 decoupling) | R3 |
| T15 | `exercise_picker_row_test.dart` (widget) | one chip per entry; tap fires `onSelect(id)`; `selectedId` highlights; default = first (most-recent) | REQ-PROG picker |

T1–T6 (pure aggregator) are the highest-value, fastest tests and gate the rest. T14 is the explicit
R3 guard. Golden tests optional — widget-state assertions are sufficient and cheaper.

---

## 7. PR split

**PR1 — data + provider + chart + picker + mobile + tests (SHIPPABLE ALONE).**
`exercise_progression.dart` (value objects) + `session_providers.dart` (2 providers + aggregator) +
`exercise_progression_chart.dart` (chart + `ExercisePickerRow`) + mobile wiring in
`coach/presentation/athlete_detail_screen.dart` + 3 ARB files + all tests (T1–T15). Lights up the
mobile coach surface end-to-end. **No web dependency.** R2 does not gate PR1.

**PR2 — web surface (GATED on R2 smoke check).**
Web wiring in `coach_hub/.../alumno_detail_screen.dart` (`_EntrenamientoTab`): replace placeholder
(line 1516), delete stale docstring (line 1452-1453), add web-local `_ProgressionTabSection` with
hardcoded strings. **Opens with the 5-minute `flutter run -d chrome` smoke check (§0).** Reuses ALL
PR1 widgets/providers unchanged → minimal diff (~30-50 lines). If the (unlikely) smoke check fails:
ship the Frecuencia stat + picker, defer only the chart, per proposal R2 fallback.

**Review Workload:** matches proposal forecast (~600-900 lines total, 400-line budget risk High,
chained PRs recommended). The chained split is confirmed correct and natural.

---

## 8. ADR-style decisions

| ADR | Decision | Rationale | Rejected alternative |
|-----|----------|-----------|----------------------|
| ADR-PROG-1 | **Copy-and-adapt** `PerformanceProgressChart` internals into a new workout-feature widget with **String-parameter labels**. | Generalizing the live widget forces `AppL10n` into the web import graph (violates R3); its internals are file-private and tied to `PerformanceTest` (can't import cross-feature). Copy contains the change to one feature. | (a) Parametrize/share the existing widget → R3 violation + cross-feature private import. (b) Public extraction to `_shared` → touches the performance feature, out of scope. |
| ADR-PROG-2 | **Pure top-level `aggregateExerciseProgression(...)`** separate from the provider; provider only fans out reads. | Aggregation is the highest-value logic; isolating it from Riverpod makes T1–T6 trivial, fast, container-free. | Inline aggregation in the provider body → forces `ProviderContainer` + fake repo for every formula assertion; slower, noisier tests. |
| ADR-PROG-3 | **Reverse DESC→ASC once in the aggregator**; provider receives `sessionsByUidProvider` order (DESC), chart consumes ASC. | Single, well-located transform; matches the existing chart contract ("ascending by recordedAt"). | Sort in the widget → re-sorts on every rebuild; or sort in provider after aggregation → two passes. |
| ADR-PROG-4 | **Frecuencia = `startedAt >= now-56d`, injectable `now`.** Never read `Session.weekNumber`. | D2 + R4. `weekNumber` is periodization metadata (`session.dart:25-27`), not calendar weeks — using it silently corrupts the stat. Injectable `now` makes boundary tests deterministic. | Use `weekNumber` → semantic corruption (R4). Hardcode `DateTime.now()` inside aggregator → untestable window boundaries. |
| ADR-PROG-5 | **Reuse `sessionsByUidProvider` + shared `_kProgressionSessionScan=60`** across BOTH new providers; `autoDispose.family`. | D5/D6. The cache stays warm during one athlete visit, so the ~60 reads happen once per visit, not per chip tap (proposal D5). autoDispose prevents per-(athlete,exercise) cache growth as the PF browses. | keepAlive → unbounded memory across athletes. Separate scan per provider → duplicate ~60 reads. collectionGroup/exerciseStats doc → new infra, out of scope. |
| ADR-PROG-6 | **No spike; R2 = SAFE with a PR2 apply-time smoke check.** | fl_chart is pure CustomPaint, officially supports web, CanvasKit loader in `index.html`; the web data path is already live via `coachSessionSetLogsProvider`. A full `flutter build web` is too heavy for this phase for marginal added confidence. | Run `flutter build web` spike now → heavy (CanvasKit fetch + full compile) for a near-certain SAFE outcome. Defer web entirely → unjustified given the evidence. |

---

## 9. Risks (design-level, post-R2)

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| RD1 | fl_chart web rendering edge case on the target browser (residual R2 tail). | Low | PR2 opens with the §0 smoke check; documented fallback (stat+picker, defer chart). |
| RD2 | Copy-paste drift: bug fixed in `PerformanceProgressChart` later won't propagate to the copy. | Low | Acceptable for V1 (contained, ~200 lines). Note in code that internals were templated from `performance_progress_chart.dart`; future shared extraction is the escape hatch. |
| RD3 | Stale web docstring (lines 1452-1453) misleads a future reader into thinking setLogs are owner-only. | Low | PR2 deletes/replaces it (§0 bonus, §5.2). |
| RD4 | Read cost: up to 60 `listSetLogs` per athlete visit (carry-over R1). | Medium | Hard `.take(60)`; reads shared across both providers via warm `sessionsByUidProvider`; once per visit. Escape hatch (exerciseStats doc) documented, out of scope. |
| RD5 | `volumeSeries` unit shown as "kg" though it is kg·reps. | Low | Display "kg" (PF reads it as load volume); spec may refine the unit label — strings are params, trivial to change without touching the widget. |

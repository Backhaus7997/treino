# Tasks — exercise-progression

**Change**: `exercise-progression`
**Artifact store**: hybrid (engram topic `sdd/exercise-progression/tasks` + this file)
**TDD mode**: Strict — RED (failing test) MUST be committed before the GREEN fix in every task.
**Scenario namespace**: SCENARIO-PROG-01A … SCENARIO-PROG-12A (spec IDs used verbatim)
**Last updated**: 2026-06-29

---

## Review Workload Forecast

| Metric | Value |
|---|---|
| **PR1 — Mobile** | |
| Production files created/changed | 5 new (`exercise_progression.dart`, `exercise_progression.freezed.dart` generated, `exercise_progression_aggregator.dart`, `exercise_progression_providers.dart`, `exercise_progression_chart.dart`) + 2 changed (`session_providers.dart`, `athlete_detail_screen.dart`) + 3 ARB files |
| Test files created | 4 new (`exercise_progression_aggregator_test.dart`, `exercise_progression_providers_test.dart`, `exercise_progression_chart_test.dart`, `athlete_detail_screen_progression_test.dart`) |
| Estimated changed lines — production | ~370 |
| Estimated changed lines — tests | ~310 |
| Estimated total PR1 | ~680 lines |
| 400-line budget risk (production only) | **Medium** (370 prod lines, just under 400; tests push total over) |
| **PR2 — Web** | |
| Production files changed | 1 (`alumno_detail_screen.dart`) |
| Test files changed | 1 (`alumno_detail_screen_test.dart`) |
| Estimated changed lines — production | ~50 |
| Estimated changed lines — tests | ~40 |
| Estimated total PR2 | ~90 lines |
| 400-line budget risk | **Low** |
| **Chained PRs recommended** | **Yes** (PR1 mobile shippable, PR2 web) |
| Decision needed before apply | **No** — chained mobile-first already decided |

---

## Dependency graph

```
PR1:
  TASK-1 (value objects — freezed)
    └─> TASK-2 (pure aggregator — RED-lock)
          └─> TASK-3 (providers — exercise list + progression)
                └─> TASK-4 (chart widget — label-injected)
                      └─> TASK-5 (exercise picker row)
  TASK-6 (AppL10n keys) [parallel after TASK-1, must precede TASK-7]
        └─> TASK-7 (mobile wiring — _ProgressionSection)
              └─> TASK-8 (PR1 quality gate)

PR2 (depends on PR1 merged):
  TASK-9 (R2 smoke check — flutter run -d chrome)
    └─> TASK-10 (web wiring — _ProgressionTabSection + delete stale docstring)
          └─> TASK-11 (PR2 quality gate)
```

TASK-2 is the RED-lock anchor; no provider or widget work begins until aggregator tests pass GREEN.
TASK-6 (ARB keys) can start in parallel with TASK-2/3 but MUST land before TASK-7.
TASK-4 and TASK-5 are sequential (chart uses `ProgressionPoint`; picker feeds chart selection).
TASK-9 through TASK-11 are entirely blocked on PR1 merge.

---

## PR1 GROUP — Mobile (shippable alone)

---

### TASK-1 — Value objects: `ExerciseProgression`, `ProgressionPoint`, `ExerciseListEntry` (freezed)

**Files to create**:
- `lib/features/workout/domain/exercise_progression.dart`

**Files generated** (run `dart run build_runner build --delete-conflicting-outputs`):
- `lib/features/workout/domain/exercise_progression.freezed.dart`

**Test file (new)**: `test/features/workout/domain/exercise_progression_test.dart`
**REQs satisfied**: REQ-PROG-12

**Strict TDD sequence**:

- [ ] **RED** — Write failing tests:
  - SCENARIO-PROG-12A: `ExerciseProgression.empty('squat', 'Sentadilla')` → `prSeries.isEmpty`, `volumeSeries.isEmpty`, `frequencyLast8Weeks == 0`
  - Compile-time check: `ExerciseProgression` fields (`exerciseId`, `exerciseName`, `prSeries`, `volumeSeries`, `frequencyLast8Weeks`) accessible without cast
  - `ProgressionPoint(date: now, value: 90.0).value` returns `double`

- [ ] **GREEN** — Create `exercise_progression.dart`:
  ```dart
  // lib/features/workout/domain/exercise_progression.dart
  // @freezed class ProgressionPoint { date: DateTime, value: double }
  // @freezed class ExerciseListEntry { exerciseId: String, exerciseName: String }
  // @freezed class ExerciseProgression {
  //   exerciseId, exerciseName,
  //   prSeries: List<ProgressionPoint>,
  //   volumeSeries: List<ProgressionPoint>,
  //   frequencyLast8Weeks: int
  //   factory ExerciseProgression.empty(exerciseId, exerciseName)
  // }
  ```
  Run `build_runner` to generate `.freezed.dart`.

- [ ] **REFACTOR** — Confirm `ProgressionPoint.date` stores UTC as-is (no `.toLocal()`) per design note. Confirm `.empty()` factory covers all fields with typed defaults.

**Parallel eligibility**: Root of PR1. Must complete before TASK-2, TASK-3, TASK-4, TASK-5, TASK-7.

---

### TASK-2 — Pure aggregator `aggregateExerciseProgression` (RED-lock)

**File to create**: `lib/features/workout/application/exercise_progression_aggregator.dart`
**Test file (new)**: `test/features/workout/application/exercise_progression_aggregator_test.dart`
**REQs satisfied**: REQ-PROG-01, REQ-PROG-02, REQ-PROG-03, REQ-PROG-04, REQ-PROG-05 (partial — name extraction)

This is the RED-lock task. NO provider or widget work proceeds until all aggregator tests pass GREEN.

**Function signature**:
```dart
ExerciseProgression aggregateExerciseProgression(
  String exerciseId,
  List<Session> sessionsDesc,   // already DESC by startedAt; caller passes .take(60)
  List<List<SetLog>> logsPerSession, // parallel to sessionsDesc
  DateTime now, // injectable for boundary tests
)
```

**Strict TDD sequence**:

- [ ] **RED** — Write ALL failing tests before any production code. Tests MUST fail (function does not exist yet).

  - SCENARIO-PROG-01A: Two squat sessions S1=[80,90,85], S2=[95,92] → prSeries = [90.0, 95.0] ASC by startedAt
  - SCENARIO-PROG-01B: One session, one set weightKg=70 → prSeries = [70.0]
  - SCENARIO-PROG-01C: Session has squat + bench sets, called with exerciseId="squat" → bench sets excluded from PR
  - SCENARIO-PROG-02A: S1 squat sets {reps:5, kg:80}, {reps:3, kg:90} → volumeSeries point = 670.0
  - SCENARIO-PROG-02B: Multiple sessions → volumeSeries ordered ASC by startedAt (same ordering as prSeries)
  - SCENARIO-PROG-03A: 4 sessions, 3 within 56 days, 1 at day -60 → frequencyLast8Weeks == 3
  - SCENARIO-PROG-03B: Session startedAt == now - 56 days exactly → included (inclusive lower bound)
  - SCENARIO-PROG-04A: 80 sessions provided but caller passes only first 60 (sessionsDesc.take(60)) → aggregator processes exactly the provided list; test verifies by checking prSeries.length == 60 when all have one squat set
  - T-extra: exerciseId is empty string → returns ExerciseProgression.empty immediately, logsPerSession NOT iterated (zero reads guard)
  - T-extra: no sets match exerciseId → prSeries.isEmpty, volumeSeries.isEmpty, frequencyLast8Weeks == 0

- [ ] **GREEN** — Implement `aggregateExerciseProgression`:
  1. Guard: if `exerciseId.isEmpty` return `ExerciseProgression.empty(exerciseId, '')` immediately
  2. Iterate `logsPerSession` (already parallel to `sessionsDesc`) — for each session, filter logs by exerciseId
  3. PR: `max(log.weightKg)` per session (skip sessions with no matching logs)
  4. Volumen: `Σ(log.reps * log.weightKg)` per session (skip sessions with no matching logs)
  5. Reverse DESC → ASC once (sessions come in DESC; reverse both series together to preserve alignment)
  6. Frecuencia: count sessions (from sessionsDesc) where `session.startedAt >= now.subtract(Duration(days: 56))` AND that session has at least one set for exerciseId; use `startedAt` NEVER `weekNumber`
  7. exerciseName: take from first matching SetLog encountered

- [ ] **REFACTOR** — Extract `_maxWeight`, `_totalVolume` as file-private helpers. Confirm injected `now` is used everywhere in Frecuencia window calculation.

**Parallel eligibility**: Blocked on TASK-1 (needs `ExerciseProgression` type). Unlocks TASK-3, TASK-4, TASK-5, TASK-7.

---

### TASK-3 — Riverpod providers: `athleteExerciseListProvider` + `exerciseProgressionProvider`

**File to create**: `lib/features/workout/application/exercise_progression_providers.dart`
**Test file (new)**: `test/features/workout/application/exercise_progression_providers_test.dart`
**REQs satisfied**: REQ-PROG-04, REQ-PROG-05, REQ-PROG-12

**Strict TDD sequence**:

- [ ] **RED** — Write failing tests (use `ProviderContainer` with mocked `SessionRepository`):

  - SCENARIO-PROG-04A: athlete has 80 sessions; mock `listSetLogs` is instrumented to count calls; provider calls it at most 60 times
  - SCENARIO-PROG-04B: athlete has 30 sessions → all 30 scanned (no crash, no truncation error)
  - SCENARIO-PROG-05A: scan finds squat sets in S1,S3,S5 and bench sets in S2,S4 → `athleteExerciseListProvider` resolves to list of length 2 (deduped by exerciseId)
  - SCENARIO-PROG-05B: most-recent session is S5 with exerciseId="squat" → first entry in list is squat
  - SCENARIO-PROG-05C: `SetLog.exerciseName == "Sentadilla"` → entry.exerciseName == "Sentadilla" (no Firestore catalogue read)
  - T-extra: athleteUid is empty string → `exerciseProgressionProvider` returns `ExerciseProgression.empty` without calling `listSetLogs`

- [ ] **GREEN** — Implement both providers in `exercise_progression_providers.dart`:
  ```dart
  // Shared scan constant (import or redeclare matching design)
  const int _kProgressionSessionScan = 60;

  // athleteExerciseListProvider(athleteUid) → AsyncValue<List<ExerciseListEntry>>
  //   - watch sessionsByUidProvider(uid)
  //   - take(_kProgressionSessionScan)
  //   - Future.wait listSetLogs for each scanned session
  //   - dedupe by exerciseId preserving most-recent-first order

  // exerciseProgressionProvider(({athleteUid, exerciseId})) → AsyncValue<ExerciseProgression>
  //   - guard: if either field empty → return ExerciseProgression.empty(exerciseId, '')
  //   - watch sessionsByUidProvider(athleteUid)
  //   - take(_kProgressionSessionScan)
  //   - Future.wait listSetLogs
  //   - delegate to aggregateExerciseProgression(exerciseId, sessions, logsPerSession, DateTime.now())
  ```
  Both providers: `autoDispose.family`, Dart record key for `exerciseProgressionProvider`.

- [ ] **REFACTOR** — Confirm both providers share the same `sessionsByUidProvider` cache watch (no duplicate Firestore reads). Confirm `autoDispose` is set on both.

**Parallel eligibility**: Blocked on TASK-1 + TASK-2.

---

### TASK-4 — Chart widget `ExerciseProgressionChart` + `ExerciseProgressionChartLabels` (label-injected, NEVER AppL10n inside widget)

**File to create**: `lib/features/workout/presentation/widgets/exercise_progression_chart.dart`
**Test file (new)**: `test/features/workout/presentation/widgets/exercise_progression_chart_test.dart`
**REQs satisfied**: REQ-PROG-06, REQ-PROG-07, REQ-PROG-08, REQ-PROG-11 (REQ-PROG-11C), REQ-PROG-12

**Design note**: Copy-and-adapt `PerformanceProgressChart` geometry helpers (`_ProgressLineChart`, `_MetricChipRow`, `_Chip`, `_shortDate`, `_labelIndices`) — swap `PerformanceTest` for `ProgressionPoint` and `String Function(AppL10n)` labels for plain `String` params. Widget MUST NOT import `app_l10n.dart`.

**Public API**:
```dart
class ExerciseProgressionChartLabels {
  final String prLabel;         // e.g. "PR"
  final String volumeLabel;     // e.g. "Volumen"
  final String volumeUnit;      // e.g. "kg·reps"  (RD5)
  final String prUnit;          // e.g. "kg"
  final String Function(int) frequencyLabel; // e.g. (n) => "$n sesiones en las últimas 8 semanas"
  final String singlePointHint; // e.g. "Necesitás al menos 2 sesiones..."
  final String emptyHint;       // e.g. "Sin datos suficientes"
}

class ExerciseProgressionChart extends StatefulWidget {
  final ExerciseProgression progression;
  final ExerciseProgressionChartLabels labels;
  final String localeName;      // e.g. 'es_AR' — passed to _shortDate
}
```

**Strict TDD sequence**:

- [ ] **RED** — Write failing widget tests (pump with `ProviderScope` + `MaterialApp`; provide `ExerciseProgression` directly — no real provider):

  - SCENARIO-PROG-06A: progression has prSeries with 2+ points → PR chip is highlighted on first render; `LineChart` is found in widget tree
  - SCENARIO-PROG-06B: tap Volumen chip → chart reflows to Volumen series; Frecuencia stat still visible
  - SCENARIO-PROG-06C: `frequencyLast8Weeks == 5` → widget tree contains text matching "5"; `LineChart` has no series containing Frecuencia data
  - SCENARIO-PROG-07A: progression has empty prSeries AND empty volumeSeries → no `LineChart` in widget tree; emptyHint text found
  - SCENARIO-PROG-07B: exactly one point in prSeries → no `LineChart`; single value displayed; singlePointHint text found
  - SCENARIO-PROG-07C: 2+ points → `LineChart` found
  - T-R3-guard (REQ-PROG-11C): `ExerciseProgressionChart` source file MUST NOT contain `import.*app_l10n` — assert via `grep` in test or add a compile-time comment-guard test

- [ ] **GREEN** — Implement widget:
  1. `ExerciseProgressionChartLabels` value bag (plain Dart class, no freezed needed)
  2. `ExerciseProgressionChart extends StatefulWidget` with `_selectedMetric` state (PR default)
  3. Frecuencia stat rendered ABOVE chip row (design decision)
  4. Chip row with PR / Volumen chips
  5. Body: if `activePoints.length >= 2` → `_ProgressLineChart(points, unit, localeName)`; if `== 1` → single value stat + singlePointHint; if `== 0` → emptyHint
  6. `_ProgressLineChart`: adapts fl_chart `LineChart`, copies `_labelIndices` + `_shortDate` from `PerformanceProgressChart`
  7. Volumen unit label MUST be "kg·reps" (or widget param `volumeUnit`) — NOT plain "kg" (RD5)
  8. NO import of `AppL10n` or `app_l10n.dart`

- [ ] **REFACTOR** — Confirm all file-private helpers are prefixed with `_`. Confirm `AppPalette.of(context)` used for all colors (no hex literals). Confirm `TreinoIcon.X` if any icons needed.

**Parallel eligibility**: Blocked on TASK-1 + TASK-2 (needs `ExerciseProgression` + `ProgressionPoint` types).

---

### TASK-5 — Exercise picker row `ExercisePickerRow` (horizontal scroll chips)

**File**: add to `lib/features/workout/presentation/widgets/exercise_progression_chart.dart` (same file, per design)
**Test file**: `test/features/workout/presentation/widgets/exercise_progression_chart_test.dart` (extend same test file)
**REQs satisfied**: REQ-PROG-05, REQ-PROG-06, REQ-PROG-08

**Design note**: Horizontal `SingleChildScrollView` pill chips (scroll, do NOT wrap). Do NOT reuse `exercise_picker_sheet.dart`. Default selection is owned by the caller (wiring) which passes `selectedId`. Picker exposes `onSelect(String exerciseId)`.

**Public API**:
```dart
class ExercisePickerRow extends StatelessWidget {
  final List<ExerciseListEntry> exercises;
  final String selectedId;
  final void Function(String exerciseId) onSelect;
}
```

**Strict TDD sequence**:

- [ ] **RED** — Write failing tests (extend TASK-4 test file):

  - SCENARIO-PROG-05B: pump `ExercisePickerRow` with exercises=[squat, bench], selectedId="squat" → squat chip is visually highlighted
  - SCENARIO-PROG-05C: chip label reads `entry.exerciseName` ("Sentadilla")
  - SCENARIO-PROG-08A: pump with `exercises == []` → no chip row rendered; caller's empty state message shown (test that `ExercisePickerRow` renders nothing / is empty when list is empty — the empty state message itself is in the wiring layer TASK-7)

- [ ] **GREEN** — Implement `ExercisePickerRow`:
  1. If `exercises.isEmpty`, return `const SizedBox.shrink()`
  2. `SingleChildScrollView(scrollDirection: Axis.horizontal)` wrapping a `Row` of chips
  3. Each chip: `FilterChip` or custom pill styled with `AppPalette.of(context)` (no hex), selectedId highlights chip
  4. Tap calls `onSelect(entry.exerciseId)`

- [ ] **REFACTOR** — Confirm chip horizontal scroll works on narrow web sidebar widths (no fixed width on chips — let content size them).

**Parallel eligibility**: Blocked on TASK-1 (needs `ExerciseListEntry`). Can run in parallel with TASK-4 if separate developer.

---

### TASK-6 — AppL10n keys (3 ARB files)

**Files to change**:
- `lib/l10n/intl_es_AR.arb`
- `lib/l10n/intl_es.arb`
- `lib/l10n/intl_en.arb`

**Test file (new)**: `test/app/l10n/exercise_progression_strings_test.dart`
**REQs satisfied**: REQ-PROG-10, REQ-PROG-10B

**Keys to add** (per design):

| Key | es_AR / es | en |
|-----|-----------|-----|
| `progressionSectionTitle` | "EVOLUCIÓN POR EJERCICIO" | "EXERCISE PROGRESSION" |
| `progressionMetricPr` | "PR" | "PR" |
| `progressionMetricVolume` | "Volumen" | "Volume" |
| `progressionFrequency` | ICU plural: `{count, plural, one{# sesión en las últimas 8 semanas} other{# sesiones en las últimas 8 semanas}}` | `{count, plural, one{# session in the last 8 weeks} other{# sessions in the last 8 weeks}}` |
| `progressionSinglePointHint` | "Necesitás al menos 2 sesiones para ver la evolución" | "You need at least 2 sessions to see a trend" |
| `progressionEmptyExercise` | "Sin datos suficientes para este ejercicio" | "Not enough data for this exercise" |
| `progressionEmpty` | "Sin registros de series todavía" | "No set logs recorded yet" |

**Strict TDD sequence**:

- [ ] **RED** — Write failing test that instantiates `AppL10n` (via `lookupAppL10n`) and asserts each new key resolves to a non-empty string for `es_AR`, `es`, and `en`.

- [ ] **GREEN** — Add all 7 keys to all 3 ARB files. Run `flutter gen-l10n` to regenerate `app_l10n.dart`. Verify compile succeeds.

- [ ] **REFACTOR** — Confirm ICU plural for `progressionFrequency` parses correctly (no syntax errors in `flutter gen-l10n` output).

**Parallel eligibility**: Can start in parallel with TASK-2/3 after TASK-1. MUST complete before TASK-7.

---

### TASK-7 — Mobile wiring: `_ProgressionSection` in `athlete_detail_screen.dart`

**File to change**: `lib/features/coach/presentation/athlete_detail_screen.dart`
**Test file (new)**: `test/features/coach/presentation/athlete_detail_screen_progression_test.dart`
**REQs satisfied**: REQ-PROG-06, REQ-PROG-08, REQ-PROG-09, REQ-PROG-10, REQ-PROG-10A, REQ-PROG-10B

**Insertion point**: After the closing brace of `_EntrenamientosSection.build` return (approx. line 1614), append `_ProgressionSection` as a new widget class in the same file. Then, inside `_EntrenamientosSection.build`, insert `_ProgressionSection(athleteId: athleteId)` after the session-list card widget (after the `sessionsAsync.when(...)` block closes, before the enclosing `Column`'s closing `]`).

**Widget structure**:
```dart
class _ProgressionSection extends ConsumerStatefulWidget {
  // athleteId: String
  // State watches:
  //   athleteExerciseListProvider(athleteId)
  //   exerciseProgressionProvider((athleteUid: athleteId, exerciseId: _selectedId))
  // _selectedId: String? (initialized to exercises.first.exerciseId on first data)
}
```

**Strict TDD sequence**:

- [ ] **RED** — Write failing widget tests (mock both providers via `ProviderScope` override):

  - SCENARIO-PROG-10A: pump `_EntrenamientosSection` with mocked providers returning a non-empty exercise list and progression → `ExercisePickerRow` found + `ExerciseProgressionChart` found + Frecuencia stat visible
  - SCENARIO-PROG-08A: mock `athleteExerciseListProvider` returning `[]` → chip row not found; progressionEmpty text found
  - SCENARIO-PROG-09B: `InsightsScreen` (or any athlete-facing screen widget test) does NOT contain `ExerciseProgressionChart` — add assertion to existing `insights_providers_test.dart` or new test (one-liner)
  - SCENARIO-PROG-10B: strings shown in widget tree come from `AppL10n` (assert `progressionSectionTitle` found, not a hardcoded literal)

- [ ] **GREEN** — Implement `_ProgressionSection(ConsumerStatefulWidget)`:
  1. Watch `athleteExerciseListProvider(athleteId)` — on `data`: if empty show `Text(l10n.progressionEmpty)`; else init `_selectedId` to `exercises.first.exerciseId` (most-recent)
  2. Watch `exerciseProgressionProvider((athleteUid: athleteId, exerciseId: _selectedId ?? ''))` — on `data`: build `ExercisePickerRow(exercises, selectedId: _selectedId, onSelect: (id) => setState(() => _selectedId = id))` + `ExerciseProgressionChart(progression, labels: _buildLabels(context), localeName: Localizations.localeOf(context).toString())`
  3. `_buildLabels(BuildContext context)` resolves all strings from `AppL10n.of(context)` — no hardcoded Spanish
  4. Loading state: `CircularProgressIndicator` or muted text consistent with rest of screen
  5. Error state: muted error text using `AppPalette.of(context).textMuted`
  6. Insert call to `_ProgressionSection` inside `_EntrenamientosSection.build` column children after session card (line ~1611)

- [ ] **REFACTOR** — Confirm section header "EVOLUCIÓN POR EJERCICIO" uses `GoogleFonts.barlowCondensed` + `palette.textMuted` (matching `_EntrenamientosSection` header style).

**Parallel eligibility**: Blocked on TASK-2 + TASK-3 + TASK-4 + TASK-5 + TASK-6. This is the final integration task for PR1.

---

### TASK-8 — PR1 Quality Gate

**No new files.** Run in CI / local before opening PR1.

- [ ] `flutter analyze` → 0 issues
- [ ] `dart format . --set-exit-if-changed` → 0 changes needed
- [ ] `flutter test test/features/workout/application/exercise_progression_aggregator_test.dart` → all GREEN
- [ ] `flutter test test/features/workout/application/exercise_progression_providers_test.dart` → all GREEN
- [ ] `flutter test test/features/workout/presentation/widgets/exercise_progression_chart_test.dart` → all GREEN
- [ ] `flutter test test/features/coach/presentation/athlete_detail_screen_progression_test.dart` → all GREEN
- [ ] `flutter test test/app/l10n/exercise_progression_strings_test.dart` → all GREEN
- [ ] `flutter test test/features/workout/domain/exercise_progression_test.dart` → all GREEN
- [ ] Full suite: `flutter test` → no regressions

**REQs gate**: REQ-PROG-01 through REQ-PROG-10 + REQ-PROG-12 fully covered before merge.

**Parallel eligibility**: Depends on all PR1 tasks. Sequential final step.

---

## PR2 GROUP — Web (blocked on PR1 merge, gated by R2 smoke check)

---

### TASK-9 — R2 Smoke Check (flutter run -d chrome)

**No code changes.** Manual verification gate.

- [ ] Run: `flutter run -t lib/main_coach_hub.dart -d chrome`
- [ ] Open web Coach Hub → navigate to an alumno detail → Entrenamiento tab
- [ ] Confirm: `LineChart` (fl_chart `CustomPaint`) paints without errors in Chrome DevTools console
- [ ] Confirm: PR/Volumen chip toggle reflows chart
- [ ] Confirm: no "Unsupported operation" or canvas errors

**Pass criterion**: `LineChart` renders correctly → proceed to TASK-10.
**Fail criterion (fallback)**: If `LineChart` fails on web, ship only `ExercisePickerRow` + Frecuencia stat in TASK-10, defer chart to W3. Document in PR2 description.

**Parallel eligibility**: First task of PR2. Blocks TASK-10.

---

### TASK-10 — Web wiring: `_ProgressionTabSection` in `alumno_detail_screen.dart` + delete stale docstring

**File to change**: `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart`
**Test file to change**: `test/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen_test.dart`
**REQs satisfied**: REQ-PROG-09, REQ-PROG-11, REQ-PROG-11A, REQ-PROG-11B, REQ-PROG-11C

**Changes**:

1. **Delete stale docstring** (~lines 1452-1453):
   ```
   // La evolución por ejercicio se difiere: depende de
   // `setLogs`, que es owner-only en firestore.rules.
   ```
   Replace with a brief accurate note: `// Evolución por ejercicio: wired in _ProgressionTabSection below.`

2. **Remove placeholder Text** at line 1516:
   ```dart
   Text(
     'Próximamente: evolución por ejercicio (PR, volumen, frecuencia).', // i18n: Fase W2
     style: TextStyle(color: palette.textMuted, fontSize: 12),
   ),
   ```

3. **Add `_ProgressionTabSection`** (new private class at bottom of file):
   ```dart
   class _ProgressionTabSection extends ConsumerStatefulWidget {
     // athleteId: String
     // Watches athleteExerciseListProvider + exerciseProgressionProvider
     // Builds ExercisePickerRow + ExerciseProgressionChart
     // ALL strings hardcoded Spanish + // i18n: Fase W2 comments
     // localeName: 'es_AR' hardcoded
     // NEVER calls AppL10n
   }
   ```

4. **Wire** `_ProgressionTabSection(athleteId: athleteId)` in `_EntrenamientoTab.build`, replacing the removed placeholder, inside the existing `SingleChildScrollView > Column(crossAxisAlignment: stretch)`.

**Strict TDD sequence**:

- [ ] **RED** — Add failing tests to `alumno_detail_screen_test.dart`:

  - SCENARIO-PROG-11A: pump `_EntrenamientoTab` with mocked providers (non-empty exercise list + progression) → `ExercisePickerRow` found + `ExerciseProgressionChart` found
  - SCENARIO-PROG-11B: placeholder text "Próximamente: evolución por ejercicio" NOT found in widget tree
  - T-stale-docstring: file-level assertion that `alumno_detail_screen.dart` does NOT contain "owner-only en firestore.rules" (string search in test setup or inline `expect`)
  - SCENARIO-PROG-11C (already covered by chart widget — confirm widget tree has one `ExerciseProgressionChart`, not two separate mobile/web widgets)

- [ ] **GREEN** — Apply all three changes (docstring delete, placeholder removal, `_ProgressionTabSection` + wiring). No `AppL10n` import needed — all strings hardcoded.

- [ ] **REFACTOR** — Confirm all strings in `_ProgressionTabSection` have `// i18n: Fase W2` inline comments. Confirm `localeName: 'es_AR'` is passed to `ExerciseProgressionChart`. Confirm `AppPalette.of(context)` used for colors.

**Parallel eligibility**: Blocked on TASK-9 (smoke check pass). Sequential within PR2.

---

### TASK-11 — PR2 Quality Gate

**No new files.** Run in CI / local before opening PR2.

- [ ] `flutter analyze` → 0 issues
- [ ] `dart format . --set-exit-if-changed` → 0 changes needed
- [ ] `flutter test test/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen_test.dart` → all GREEN (including new assertions)
- [ ] `flutter test` → full suite, no regressions
- [ ] R2 smoke check documented in PR2 description (pass or fallback decision recorded)

**Parallel eligibility**: Depends on TASK-10. Sequential final step of PR2.

---

## Design ↔ Test reconciliation (T1–T15 → TASK mapping)

| Design test ID | Spec scenario | Implemented in TASK |
|---|---|---|
| T1 | SCENARIO-PROG-01A, 01B, 01C | TASK-2 (aggregator test) |
| T2 | SCENARIO-PROG-02A, 02B | TASK-2 (aggregator test) |
| T3 | SCENARIO-PROG-03A, 03B, 03C | TASK-2 (aggregator test) |
| T4 | SCENARIO-PROG-04A, 04B | TASK-2 + TASK-3 (aggregator + provider call count) |
| T5 | SCENARIO-PROG-03B (never weekNumber) | TASK-2 (aggregator — assert startedAt used) |
| T6 | SCENARIO-PROG-01C, empty key guard | TASK-2 (aggregator test) |
| T7 | SCENARIO-PROG-04A (listSetLogs call count ≤ 60) | TASK-3 (provider test) |
| T8 | Empty athleteUid → zero reads | TASK-3 (provider test) |
| T9 | SCENARIO-PROG-05A, 05B, 05C | TASK-3 (exercise list provider test) |
| T10 | SCENARIO-PROG-07C (≥2 pts → LineChart) | TASK-4 (chart widget test) |
| T11 | SCENARIO-PROG-07B (1 pt → no line + hint) | TASK-4 (chart widget test) |
| T12 | SCENARIO-PROG-07A (0 pts → emptyHint) | TASK-4 (chart widget test) |
| T13 | SCENARIO-PROG-06C (Frecuencia stat visible + PR default) | TASK-4 (chart widget test) |
| T14 | SCENARIO-PROG-11C (no AppL10n import in widget — R3 guard) | TASK-4 (chart widget test) |
| T15 | SCENARIO-PROG-05B (picker default selection) | TASK-5 (picker test) |

---

## File manifest

### New files (PR1)
- `lib/features/workout/domain/exercise_progression.dart`
- `lib/features/workout/domain/exercise_progression.freezed.dart` (generated)
- `lib/features/workout/application/exercise_progression_aggregator.dart`
- `lib/features/workout/application/exercise_progression_providers.dart`
- `lib/features/workout/presentation/widgets/exercise_progression_chart.dart` (contains `ExerciseProgressionChart` + `ExercisePickerRow`)
- `test/features/workout/domain/exercise_progression_test.dart`
- `test/features/workout/application/exercise_progression_aggregator_test.dart`
- `test/features/workout/application/exercise_progression_providers_test.dart`
- `test/features/workout/presentation/widgets/exercise_progression_chart_test.dart`
- `test/features/coach/presentation/athlete_detail_screen_progression_test.dart`
- `test/app/l10n/exercise_progression_strings_test.dart`

### Changed files (PR1)
- `lib/features/workout/application/session_providers.dart` (add import of new providers or leave separate — no changes needed if providers in separate file)
- `lib/features/coach/presentation/athlete_detail_screen.dart` (add `_ProgressionSection`, insert call in `_EntrenamientosSection`)
- `lib/l10n/intl_es_AR.arb`
- `lib/l10n/intl_es.arb`
- `lib/l10n/intl_en.arb`

### Changed files (PR2)
- `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` (delete docstring, remove placeholder, add `_ProgressionTabSection`, wire)
- `test/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen_test.dart` (extend with progression assertions)

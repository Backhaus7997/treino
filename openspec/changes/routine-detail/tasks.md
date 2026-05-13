# Tasks — routine-detail

**Change**: `routine-detail`
**Fase / Etapa**: Fase 2 · Etapa 4
**Branch**: `feat/routine-detail`
**TDD**: Strict — every implementation task is preceded by a RED test task.
**Total tasks**: 28 (4 pre-verify + 5 leaf widget pairs + 2 screen pairs + 1 router pair + 3 quality gates)
**Scenario range**: SCENARIO-075..112 (spec.md is authoritative — design.md §9 ranges are WRONG, do not use them)

---

## Phase 0 — Pre-implementation verifications (NO code changes)

Run all four in order before touching any source file.

- [x] **TASK-000a — Verify `PhosphorIconsRegular.timer` compiles**
  - **REQ refs**: REQ-RDT-021
  - **Files**: `tmp_phosphor_check.dart` (create → analyze → delete, never commit)
  - **Done when**: Write `import 'package:phosphor_flutter/phosphor_flutter.dart'; void main() { final _ = PhosphorIconsRegular.timer; }` to `tmp_phosphor_check.dart`. Run `flutter analyze tmp_phosphor_check.dart`. If 0 issues → delete file, record `timer: OK` in apply-progress, proceed with `PhosphorIconsRegular.timer`. If compile error → test with `PhosphorIconsRegular.stopwatch`, then `PhosphorIconsRegular.hourglass` (DO NOT fall back to `clock`). Record chosen symbol in apply-progress. Delete `tmp_phosphor_check.dart` regardless of outcome.
  - **Notes**: phosphor_flutter `^2.1.0` locked in pubspec. `ph-timer` is a standard Phosphor icon since 1.x — high confidence. This verify task prevents a broken TASK-001b.

- [x] **TASK-000b — Verify `TreinoIcon.timer` does not already exist**
  - **REQ refs**: REQ-RDT-021 (SCENARIO-112)
  - **Files**: `lib/core/widgets/treino_icon.dart` (read-only)
  - **Done when**: `rg 'timer' lib/core/widgets/treino_icon.dart` returns no matches → proceed with TASK-001b. If a match is found → skip TASK-001b, record `TreinoIcon.timer: already exists` in apply-progress, reuse existing constant.
  - **Notes**: File confirmed clean at spec-writing time (clock is last in "Stats / tiempo" block, line 39). Guard anyway for branch safety.

- [x] **TASK-000c — Verify `TreinoBottomBar` class name in router**
  - **REQ refs**: REQ-RDT-020 (SCENARIO-110, SCENARIO-111)
  - **Files**: `lib/app/router.dart` (read-only)
  - **Done when**: `rg 'bottomNavigationBar' lib/app/router.dart` shows `TreinoBottomBar` as the widget class inside `_ShellScaffold`. Record the exact class name in apply-progress. Update all test fixtures (`find.byType(...)`) to use this class name.
  - **Notes**: Confirmed `TreinoBottomBar` at design time. This verify locks the name for test files written in Phase 2.

- [x] **TASK-000d — Confirm provider signatures for test overrides**
  - **REQ refs**: REQ-RDT-001, REQ-RDT-013
  - **Files**: `lib/features/workout/application/routine_providers.dart`, `lib/features/workout/application/exercise_providers.dart` (read-only)
  - **Done when**: `rg 'routineByIdProvider|exerciseByIdProvider' lib/features/workout/application/` confirms both are declared as `FutureProvider.family<Routine?, String>` and `FutureProvider.family<Exercise?, String>` respectively. Record the exact declaration lines in apply-progress. Override pattern in all tests uses `routineByIdProvider('test-id').overrideWith((ref) async => ...)` (NOT `routineByIdProvider.overrideWith`).
  - **Notes**: Signatures confirmed at spec-writing time. This verify ensures the test override pattern used throughout Phase 2 and Phase 3 is correct.

---

## Phase 1 — Leaf widgets (smallest, most reused, no UI dependencies)

Each pair: RED (failing test) → GREEN (implementation). `stat_tile` first because `ExerciseSlotRow` and both screens depend on it.

- [x] **TASK-001a — `StatTile`: test file (RED)**
  - **REQ refs**: REQ-RDT-012 (SCENARIO-095, SCENARIO-096)
  - **Files**: `test/features/workout/presentation/widgets/stat_tile_test.dart` — new file (~40 LOC)
  - **Done when**: File exists. Directory `test/features/workout/presentation/widgets/` created. `flutter test test/features/workout/presentation/widgets/stat_tile_test.dart` fails with import error (widget doesn't exist). Two tests: (1) `StatTile(label: 'EJERCICIOS', value: '6')` → `find.text('EJERCICIOS')` and `find.text('6')` each find one. (2) `StatTile(label: 'DURACIÓN', value: null)` → `find.text('—')` finds one, no exception.
  - **Notes**: Use `_wrap(Widget w)` helper per spec test convention. `value` is `String?` (design §3.3) — null renders `"—"`.

- [x] **TASK-001b — `StatTile`: widget implementation (GREEN)**
  - **REQ refs**: REQ-RDT-012 (SCENARIO-095, SCENARIO-096)
  - **Files**: `lib/features/workout/presentation/widgets/stat_tile.dart` — new file (~70 LOC)
  - **Done when**: `flutter test test/features/workout/presentation/widgets/stat_tile_test.dart` reports 2/2 green. `flutter analyze lib/features/workout/presentation/widgets/stat_tile.dart` 0 issues.
  - **Notes**: API: `StatTile({required String label, required String? value})`. Renders `value ?? '—'` as `GoogleFonts.barlowCondensed(fontWeight: FontWeight.w700, fontSize: 22, color: palette.textPrimary)`. Label in `GoogleFonts.barlowCondensed(fontWeight: FontWeight.w600, fontSize: 10, letterSpacing: 1.2, color: palette.textMuted)`. Column, crossAxisAlignment center. No HEX literals. No `PhosphorIcons.*` direct.

- [x] **TASK-002a — `TechniqueInstructionItem`: test file (RED)**
  - **REQ refs**: REQ-RDT-016 (SCENARIO-103, SCENARIO-104 — item widget only, not full screen)
  - **Files**: `test/features/workout/presentation/widgets/technique_instruction_item_test.dart` — new file (~40 LOC)
  - **Done when**: File exists. `flutter test` on this file fails (widget missing). Two tests: (1) `TechniqueInstructionItem(index: 1, text: 'Cue 1')` → `find.text('1')` and `find.text('Cue 1')` each find one. (2) `TechniqueInstructionItem(index: 3, text: 'Long cue text')` → `find.text('3')` finds one, no exception.
  - **Notes**: Can run in parallel with TASK-001a/001b (no cross-dependency).

- [x] **TASK-002b — `TechniqueInstructionItem`: widget implementation (GREEN)**
  - **REQ refs**: REQ-RDT-016 (SCENARIO-103, SCENARIO-104)
  - **Files**: `lib/features/workout/presentation/widgets/technique_instruction_item.dart` — new file (~60 LOC)
  - **Done when**: `flutter test test/features/workout/presentation/widgets/technique_instruction_item_test.dart` 2/2 green. `flutter analyze` 0 issues.
  - **Notes**: API: `TechniqueInstructionItem({required int index, required String text})`. Row with 28×28 circle Container (gradient `palette.accent → palette.highlight`) showing `'$index'` in `palette.bg`, then `Expanded(Text(text, GoogleFonts.barlow w400 14, palette.textPrimary, height 1.4))`. Gap between circle and text: `SizedBox(width: 12)`.

- [x] **TASK-003a — `ExerciseSlotRow`: test file (RED)**
  - **REQ refs**: REQ-RDT-008, REQ-RDT-010 (SCENARIO-088, SCENARIO-089, SCENARIO-093)
  - **Files**: `test/features/workout/presentation/widgets/exercise_slot_row_test.dart` — new file (~90 LOC)
  - **Done when**: File exists. `flutter test` on this file fails. Three tests: (1) render — `ExerciseSlotRow(slot: _makeSlot(), onTap: () {})` → `find.text('PRESS DE BANCA')` (or `find.textContaining('PRESS')`) finds one, `find.text('4 · 8–12')` finds one, `find.text('CHEST')` (or whatever `muscleGroup.toUpperCase()` yields) finds one. (2) badge — `find.text('ÚLTIMO')` finds one, `find.text('—')` finds ≥1. (3) tap callback — `bool tapped = false; ExerciseSlotRow(slot: _makeSlot(), onTap: () { tapped = true; })` → `tester.tap(find.byType(ExerciseSlotRow))` → `tapped == true`. Also: no `ref.watch` call (StatelessWidget — verify by absence of `Consumer` or `HookConsumerWidget` in type tree).
  - **Notes**: Depends on TASK-001b (StatelessWidget that doesn't use StatTile directly, but ensures `lib/features/workout/presentation/widgets/` exists). Define `_makeSlot()` fixture helper in the test file. SCENARIO-088 uses `exerciseName: 'Press de Banca'` — displayed as `.toUpperCase()` per design §3.3.

- [x] **TASK-003b — `ExerciseSlotRow`: widget implementation (GREEN)**
  - **REQ refs**: REQ-RDT-008, REQ-RDT-010 (SCENARIO-088, SCENARIO-089, SCENARIO-093)
  - **Files**: `lib/features/workout/presentation/widgets/exercise_slot_row.dart` — new file (~140 LOC)
  - **Done when**: `flutter test test/features/workout/presentation/widgets/exercise_slot_row_test.dart` 3/3 green. `flutter analyze` 0 issues.
  - **Notes**: API per design §3.3: `ExerciseSlotRow({required RoutineSlot slot, required VoidCallback onTap, String? lastWeightDisplay})`. No `ref.watch`/`ref.read`. Uses `TreinoIcon.timer` for rest indicator (verify TASK-000a chose a valid symbol). `Semantics(button: true, label: 'Ejercicio ${slot.exerciseName}, ...')` wrapping. Thumb 48×48, `TreinoIcon.tabWorkout`. `_UltimoBadge` private widget. Spacing all from `{8, 12, 14}` set.

---

## Checkpoint A — Leaf widget quality gate

- [x] **TASK-CKA — Checkpoint: leaf widgets green**
  - **REQ refs**: all REQ-RDT-008, REQ-RDT-010, REQ-RDT-012, REQ-RDT-016 (widget level)
  - **Done when**: (1) `flutter test test/features/workout/presentation/widgets/` → all tests green (7 tests across 3 files). (2) `flutter analyze` 0 issues on `lib/features/workout/presentation/widgets/`. (3) `dart format lib/features/workout/presentation/widgets/ test/features/workout/presentation/widgets/` produces 0 diff.
  - **Notes**: Do NOT proceed to Phase 2 until this checkpoint passes. Fix any failures here.

---

## Phase 1b — TreinoIcon.timer addition

- [x] **TASK-001c — Add `TreinoIcon.timer` to `treino_icon.dart`**
  - **REQ refs**: REQ-RDT-021 (SCENARIO-112)
  - **Files**: `lib/core/widgets/treino_icon.dart` — modify (add 1 line)
  - **Done when**: After line `static const IconData clock = PhosphorIconsRegular.clock;`, add `static const IconData timer = PhosphorIconsRegular.timer;` (or the fallback symbol determined in TASK-000a). `rg 'timer' lib/core/widgets/treino_icon.dart` finds exactly one match with `TreinoIcon.timer`. `rg 'PhosphorIcons\.timer' lib/features/' returns 0 matches (no direct Phosphor reference in new files).
  - **Notes**: Run after TASK-000a and TASK-000b. Skip this task entirely if TASK-000b found `TreinoIcon.timer` already exists. SCENARIO-112 requires the constant exists; `ExerciseSlotRow` depends on it (TASK-003b must come after this).

---

## Phase 2 — Screens

Both screens are independent of each other and can run in parallel. `ExerciseDetailScreen` first because it's a `ConsumerWidget` with no local state (simpler baseline). `RoutineDetailScreen` follows with `selectedDayIndex` and day selector logic.

- [x] **TASK-004a — `ExerciseDetailScreen`: test file (RED)**
  - **REQ refs**: REQ-RDT-013, REQ-RDT-014, REQ-RDT-015, REQ-RDT-016, REQ-RDT-017, REQ-RDT-018, REQ-RDT-019 (SCENARIO-097..109)
  - **Files**: `test/features/workout/presentation/exercise_detail_screen_test.dart` — new file (~160 LOC)
  - **Done when**: File exists. `flutter test` on this file fails (screen missing). Tests cover all 13 scenarios: (1) `AsyncData(exercise)` → no exception, exercise name found. (2) `AsyncLoading()` → skeleton found, name absent. (3) `AsyncError(...)` → no exception, error widget found. (4) `AsyncData(null)` → `'Ejercicio no encontrado'` found. (5) breadcrumb `'PECHO · COMPOUND'` and title `'PRESS DE BANCA'`. (6) exactly 3 `StatTile` widgets, all `value == null` renders `'—'`. (7) `techniqueInstructions: ['Cue 1','Cue 2','Cue 3']` → `find.text('TÉCNICA')` one, 3 `TechniqueInstructionItem`s. (8) `techniqueInstructions: null` → empty state text. (9) `techniqueInstructions: []` → same empty state. (10) `find.text('HISTORIAL')` one, `'Aún no entrenaste este ejercicio'` one. (11) `videoUrl: null` → no exception. (12) `videoUrl: 'https://...'` → `'Video próximamente'` found. (13) no `Scaffold`/`AppBackground`/`SafeArea` in own subtree (SCENARIO-109).
  - **Notes**: Depends on TASK-001b (StatTile) + TASK-002b (TechniqueInstructionItem) being green. Use `_wrapWithOverrides` helper. Override pattern: `exerciseByIdProvider('ex-id').overrideWith((ref) async => _makeExercise())`. Define `_makeExercise()` fixture locally. `ExerciseDetailScreen` is a `ConsumerWidget` — no `ConsumerStatefulWidget` needed.

- [x] **TASK-004b — `ExerciseDetailScreen`: widget implementation (GREEN)**
  - **REQ refs**: REQ-RDT-013..019 (SCENARIO-097..109)
  - **Files**: `lib/features/workout/presentation/exercise_detail_screen.dart` — new file (~220 LOC)
  - **Done when**: `flutter test test/features/workout/presentation/exercise_detail_screen_test.dart` all tests green. `flutter analyze` 0 issues.
  - **Notes**: `class ExerciseDetailScreen extends ConsumerWidget`. `ref.watch(exerciseByIdProvider(exerciseId))`. `CustomScrollView` with `SliverToBoxAdapter` hero placeholder (solid `palette.espresso`, centered `TreinoIcon.tabWorkout` at 50% opacity) + `SliverPadding(horizontal: 20) > SliverList`. Private widgets: `_HeroPlaceholder`, `_Breadcrumb`, `_ExerciseTitle`, `_StatRow`, `_SectionHeader`, `_EmptyState`, `_HistoryEmptyState`, `_NotFoundState`, `_ErrorState`, `_ExerciseLoadingSkeleton`, `_VideoComingSoon`. NO `Scaffold`, `AppBackground`, `SafeArea`. Comment at top of file per `home-shell` convention.

- [x] **TASK-005a — `RoutineDetailScreen`: test file (RED)**
  - **REQ refs**: REQ-RDT-001..011 (SCENARIO-075..094)
  - **Files**: `test/features/workout/presentation/routine_detail_screen_test.dart` — new file (~200 LOC)
  - **Done when**: File exists. `flutter test` on this file fails. Tests cover all 20 scenarios: (1) `AsyncData(routine)` → no exception, `ExerciseSlotRow` count matches slots, `TreinoBottomBar` found. (2) `AsyncLoading()` → skeleton found, `ExerciseSlotRow` absent. (3) `AsyncError(...)` → no exception, error widget found. (4) `AsyncData(null)` → `'Rutina no encontrada'` found. (5) hero gradient found, no `CachedNetworkImage` when `imageUrl == null`. (6) badge `'PPL · DÍA 1'`. (7) day title `'PUSH'` in uppercase. (8) stat tiles: `find.text('3')` in StatTile, `find.text('10')` in StatTile, `find.text('45')` in StatTile. (9) `estimatedMinutes: null` → `'—'` in third StatTile. (10) single-day routine → no day selector. (11) 3-day routine → 3 chips found, tapping chip 3 changes day name. (12) `'EJERCICIOS'` section header, 4 `ExerciseSlotRow` for 4-slot day. (13) empty slots → `'No hay ejercicios en este día'`. (14) `'EDITAR'` and `'EMPEZAR'` CTAs with `onPressed == null`. (15) tapping CTAs → no exception, no navigation. (16) CTAs opacity `0.4`. (17) tap on `ExerciseSlotRow` navigates to `/workout/exercise/:exerciseId` (GoRouter test). (18) no `Scaffold`/`AppBackground`/`SafeArea` in own subtree. Plus deep-link test per design §9.5.
  - **Notes**: Depends on TASK-001b (StatTile) + TASK-003b (ExerciseSlotRow) + TASK-001c (TreinoIcon.timer) being green. Define `_makeRoutine`, `_makeDay`, `_makeSlot` fixture helpers locally. Use `_wrapWithOverrides` with `routineByIdProvider('test-id').overrideWith((ref) async => _makeRoutine(id: 'test-id'))`.

- [x] **TASK-005b — `RoutineDetailScreen`: widget implementation (GREEN)**
  - **REQ refs**: REQ-RDT-001..011 (SCENARIO-075..094)
  - **Files**: `lib/features/workout/presentation/routine_detail_screen.dart` — new file (~280 LOC)
  - **Done when**: `flutter test test/features/workout/presentation/routine_detail_screen_test.dart` all tests green. `flutter analyze` 0 issues.
  - **Notes**: `class RoutineDetailScreen extends ConsumerStatefulWidget`. `int selectedDayIndex = 0` as local state in `ConsumerState` (NOT a Riverpod provider — ADR-RD-3). `CustomScrollView` + `SliverToBoxAdapter` hero + `SliverPadding(horizontal:20) > SliverList`. Private widgets: `_HeroStrip`, `_DayChipBadge`, `_DayTitle`, `_StatRow`, `_DaySelector` (conditional on `days.length > 1`), `_SectionHeader`, `_EmptyState`, `_DisabledCTABar` (2 CTAs `onPressed: null`, `Opacity(opacity: 0.4)`), `_NotFoundState`, `_ErrorState`, `_RoutineLoadingSkeleton`. `ExerciseSlotRow` tap calls `context.push('/workout/exercise/${slot.exerciseId}')` (NOT `context.go`). NO `Scaffold`, `AppBackground`, `SafeArea`.

---

## Checkpoint B — Screen quality gate

- [x] **TASK-CKB — Checkpoint: screens green**
  - **REQ refs**: all REQ-RDT-001..019
  - **Done when**: (1) `flutter test test/features/workout/presentation/` → all tests green. (2) `flutter analyze lib/features/workout/presentation/` → 0 issues. (3) `dart format lib/features/workout/presentation/ test/features/workout/presentation/` → 0 diff. (4) `rg '#[0-9a-fA-F]{6}' lib/features/workout/presentation/` → 0 matches. (5) `rg 'PhosphorIcons\.' lib/features/workout/presentation/` → 0 matches.
  - **Notes**: Do NOT proceed to Phase 3 until this checkpoint passes.

---

## Phase 3 — Router wiring

- [x] **TASK-006a — Router: test for deep-link routes (RED)**
  - **REQ refs**: REQ-RDT-020 (SCENARIO-110, SCENARIO-111)
  - **Files**: `test/app/router_workout_routes_test.dart` — new file (~80 LOC)
  - **Done when**: File exists. `flutter test` on this file fails (routes not yet added). Two tests per design §9.5: (1) deep-link `/workout/routine/test-id` → `find.byType(RoutineDetailScreen)` finds one (with `routineByIdProvider` override). (2) deep-link `/workout/exercise/ex-id` → `find.byType(ExerciseDetailScreen)` finds one (with `exerciseByIdProvider` override). Each test verifies `find.byType(TreinoBottomBar)` is present (shell visible).
  - **Notes**: Depends on TASK-004b + TASK-005b (screens must exist for `find.byType` to compile). Uses minimal `GoRouter` with only the target route — no shell needed for deep-link verification. Override both providers in `ProviderScope`.

- [x] **TASK-006b — Router: add two GoRoutes to `lib/app/router.dart` (GREEN)**
  - **REQ refs**: REQ-RDT-020 (SCENARIO-110, SCENARIO-111)
  - **Files**: `lib/app/router.dart` — modified (add ~15 lines + 2 imports)
  - **Done when**: `flutter test test/app/router_workout_routes_test.dart` all tests green. `flutter analyze lib/app/router.dart` 0 issues.
  - **Notes**: Add `routes: [GoRoute(path: 'routine/:routineId', pageBuilder: ...), GoRoute(path: 'exercise/:exerciseId', pageBuilder: ...)]` nested inside the existing `/workout` `GoRoute`. Paths are relative (no leading slash). Add imports at top: `import '../features/workout/presentation/exercise_detail_screen.dart'; import '../features/workout/presentation/routine_detail_screen.dart';`. `WorkoutScreen` MUST NOT be modified. `_ShellScaffold._currentIndex` already handles `startsWith('/workout')` — bottom bar stays visible. No `name:` on new GoRoutes (consistency with existing router).

---

## Phase 4 — Final quality gate

- [x] **TASK-007 — dart format (final)**
  - **REQ refs**: cross-cutting (CLAUDE.md quality gate)
  - **Done when**: `dart format . --output=none --set-exit-if-changed` exits 0, no diff. Run after TASK-006b. Fix any drift before TASK-008.

- [x] **TASK-008 — flutter analyze (final)**
  - **REQ refs**: cross-cutting (CLAUDE.md quality gate)
  - **Done when**: `flutter analyze` reports `No issues found!` (0 errors, 0 warnings, 0 infos introduced by this PR). Run after TASK-007. Additional grep constraints: `rg 'SizedBox\(height: 16' lib/features/workout/presentation/` and `rg 'SizedBox\(height: 24' lib/features/workout/presentation/` both return 0 matches (spacing allowed-set `{8,12,14,18,20}` only).

- [x] **TASK-009 — Full test suite + smoke (FINAL gate)**
  - **REQ refs**: all REQs (final verification pass)
  - **Done when**: (1) `flutter test` (full suite) exits 0 — no regressions in auth, profile, or workout domain tests. (2) `flutter test test/features/workout/presentation/ test/app/router_workout_routes_test.dart` exits 0. (3) Manual smoke: `flutter run` → deep-link `context.push('/workout/routine/ppl-beginner')` → verify bottom bar visible + hero gradient + day 1 selected + ~6 `ExerciseSlotRow`s → tap a slot → navigate to `/workout/exercise/<id>` → technique cues visible → back → `WorkoutScreen` placeholder shows, not the detail. Document result in apply-progress.
  - **Notes**: This is the PR-ready gate. Do not open the PR until all three criteria pass. Record smoke result in apply-progress as `smoke: PASS` or `smoke: FAIL (description)`.

---

## Dependency graph

```
TASK-000a/b/c/d (parallel, pre-verify)
    ↓
TASK-001c (TreinoIcon.timer)
    ↓ (also: TASK-001a/b, TASK-002a/b can run after 000 series)
TASK-001a → TASK-001b ──────────────────────────────────────────┐
TASK-002a → TASK-002b ──────────────────────┐                   │
TASK-001c ──────────────────────────────────┤                   │
                                             ↓                   ↓
                                        TASK-003a → TASK-003b   │
                                                          │      │
                                                          ↓      ↓
                                                       TASK-CKA (leaf gate)
                                                          ↓
                   ┌──────────────────────────────────────┤
                   ↓                                      ↓
            TASK-004a → TASK-004b               TASK-005a → TASK-005b
                          ↓                                   ↓
                       TASK-CKB ←─────────────────────────────┘
                          ↓
                   TASK-006a → TASK-006b
                                   ↓
                             TASK-007 → TASK-008 → TASK-009
```

**Parallelizable**: TASK-000a/b/c/d (all 4). After leaf gate: TASK-004a/b and TASK-005a/b. For a solo dev, the listed sequential order within each phase is optimal.

---

## Review Workload Forecast

| Metric | Value |
|---|---|
| Estimated production LOC | ~770 (5 new dart files ~770, +treino_icon.dart delta ~1, +router.dart delta ~15) |
| Estimated test LOC | ~610 (5 test files) |
| Total meaningful diff | ~1,385 LOC across ~13 files (10 new, 3 modified) |
| 400-LOC production budget | Met — production code is mechanical widget composition, no new logic or algorithms |
| Chained PRs | No — single PR `feat/routine-detail`. All files tightly coupled to the same visible screens. |

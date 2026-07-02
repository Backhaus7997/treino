# Tasks: coach-hub-biblioteca-web (Fase W5.3)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | PR1 ~355 net · PR2 ~200 |
| 400-line budget risk | Medium (PR1 near budget; picker edit is negative) |
| Chained PRs recommended | Yes |
| Suggested split | PR1 (extraction + Ejercicios tab) → PR2 (Templates tab + route swap) |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Filter extraction + Ejercicios tab | PR1 | Base = feature/coach-hub-biblioteca-web; route stays on ProximamenteScreen |
| 2 | Templates tab + route swap | PR2 | Base = PR1 branch; Biblioteca goes live atomically |

---

## PR1 — Filter Extraction + Ejercicios Tab

### Phase 1.1 — Pure filter library (foundation; everything else depends on this)

- [ ] 1.1.1 [RED — REQ-BIBW-08] Create `test/features/workout/application/exercise_filter_test.dart`: tests for `foldSearch` (diacritics + lowercase), `exerciseMatchesFilters` (empty query = pass, name match, alias match, primary-OR-secondary muscle, ADR-RER-05 null-equipment excluded when set non-empty, ADR-RER-05 null-equipment included when set empty, AND-across-dimensions). These tests MUST fail before 1.1.2. Covers SCENARIO-BIBW-08a, SCENARIO-BIBW-08b, SCENARIO-BIBW-05b, SCENARIO-BIBW-06b.
- [ ] 1.1.2 [GREEN — REQ-BIBW-08, ADR-BIBW-01] Create `lib/features/workout/application/exercise_filter.dart`: move `foldSearch` verbatim from `exercise_picker_sheet.dart`:36–47; add `exerciseMatchesFilters(Exercise e, {required String query, required Set<MuscleGroup> muscles, required Set<EquipmentType> equipment}) → bool` as a line-for-line lift of `_matches` (picker:103–125) with widget fields promoted to named params; add `customToExercise(CustomExercise) → Exercise` promoted from picker's `_toExercise`:883–895. Pure Dart, no Flutter/Riverpod. All 1.1.1 tests MUST go green.
- [ ] 1.1.3 [REFACTOR — REQ-BIBW-08] Edit `exercise_picker_sheet.dart`: delete local `foldSearch` (lines 36–47) + its doc comment; add `import '../../../workout/application/exercise_filter.dart';`; replace `_matches` body (102–126) with a 4-line delegate to `exerciseMatchesFilters(e, query: _query, muscles: _muscleFilters, equipment: _equipmentFilters)`. Zero behavior change. Gate: `exercise_picker_sheet_test.dart` MUST stay green (search filter test + Hombros secondary-muscle test + selection tests).

### Phase 1.2 — Web providers (depends on 1.1.2)

- [ ] 1.2.1 [RED — REQ-BIBW-03, REQ-BIBW-06] Create `test/features/coach_hub/presentation/sections/biblioteca/providers/biblioteca_providers_test.dart`: unit tests for `bibliotecaExercisesProvider` — catalog-loading → AsyncLoading, catalog-error → AsyncError, custom-stream error degrades to empty (catalog still shown), merge order (customs first), predicate applied (one exercise filtered out by name query). Use `ProviderContainer` with overrides; no pumpWidget.
- [ ] 1.2.2 [GREEN — REQ-BIBW-03, REQ-BIBW-06] Create `lib/features/coach_hub/presentation/sections/biblioteca/providers/biblioteca_providers.dart`: `bibliotecaQueryProvider` (StateProvider.autoDispose<String>), `bibliotecaMuscleFilterProvider` (StateProvider.autoDispose<Set<MuscleGroup>>), `bibliotecaEquipmentFilterProvider` (StateProvider.autoDispose<Set<EquipmentType>>), `bibliotecaExercisesProvider` (Provider.autoDispose<AsyncValue<List<Exercise>>>) folding `exercisesProvider` ∪ `customExercisesForTrainerStreamProvider(uid)` (via `customToExercise`) then applying `exerciseMatchesFilters`. Catalog is the spine (catalog loading/error = derived loading/error; custom-stream errors swallowed via `valueOrNull ?? []`). Custom entries prepended. trainerId from `currentUidProvider`. All 1.2.1 tests MUST go green.

### Phase 1.3 — Ejercicios tab widgets (depends on 1.2.2)

- [ ] 1.3.1 [RED — REQ-BIBW-04, REQ-BIBW-05, REQ-BIBW-06, REQ-BIBW-11] Create `test/features/coach_hub/presentation/sections/biblioteca/widgets/ejercicios_tab_test.dart`: smoke renders with mock providers (loading indicator when AsyncLoading, error text when AsyncError, grid when AsyncData); CUSTOM badge present on custom exercise card; no badge on catalog card; empty-state widget when merged list is empty. Covers SCENARIO-BIBW-03a, SCENARIO-BIBW-03b, SCENARIO-BIBW-11a.
- [ ] 1.3.2 [GREEN — REQ-BIBW-04] Create `lib/features/coach_hub/presentation/sections/biblioteca/widgets/exercise_grid_card.dart`: card with `AspectRatio`-header thumbnail (`Image.asset('assets/exercises/${e.id}.png')` + `errorBuilder` → `Icon(TreinoIcon.dumbbell)` fallback; custom exercises skip asset → dumbbell directly via `e.category == 'custom'`); name (`maxLines: 2`, bold); `"Músculo · Categoría"` subtitle; equipment chip (omit when null); rest badge (omit when null); "CUSTOM" badge (when `category == 'custom'`). Tap callback. All colors `AppPalette.of(context)`, icons `TreinoIcon`. Covers REQ-BIBW-04, SCENARIO-BIBW-04a, SCENARIO-BIBW-03a.
- [ ] 1.3.3 [GREEN — REQ-BIBW-05, REQ-BIBW-06] Create `lib/features/coach_hub/presentation/sections/biblioteca/widgets/biblioteca_filter_chips.dart`: `ConsumerWidget` with two `Wrap(spacing: 8, runSpacing: 8)` rows labeled "MÚSCULO" / "EQUIPAMIENTO"; muscle chips = `MuscleGroup.displayOrder` (12 items) + "TODOS" (clears set); equipment chips = `EquipmentType.values` (13 items) + "TODOS"; chips toggle membership in `bibliotecaMuscleFilterProvider` / `bibliotecaEquipmentFilterProvider`; active/idle visuals from picker `_FilterButton` token treatment (accent border + tint when active). No bottom sheet. Covers REQ-BIBW-06, SCENARIO-BIBW-06a, SCENARIO-BIBW-06b, SCENARIO-BIBW-06c, SCENARIO-BIBW-06d.
- [ ] 1.3.4 [GREEN — REQ-BIBW-03, REQ-BIBW-05, REQ-BIBW-11] Create `lib/features/coach_hub/presentation/sections/biblioteca/widgets/ejercicios_tab.dart`: `ConsumerWidget` watching `bibliotecaExercisesProvider`, `bibliotecaQueryProvider`, muscle/equipment providers; column layout: search `TextField` (updates `bibliotecaQueryProvider`) → `BibliotecaFilterChips` → `Expanded(GridView)` with `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, childAspectRatio: 0.82)`; `.when` → `CircularProgressIndicator` / error `Text` / grid of `ExerciseGridCard`; empty-list path → centered empty-state `Text`. Tap → `showExerciseDetailDialog`. All 1.3.1 tests MUST go green.

### Phase 1.4 — Exercise detail dialog (depends on 1.3.2)

- [ ] 1.4.1 [RED — REQ-BIBW-07] Add to `ejercicios_tab_test.dart`: tap exercise card → `AlertDialog` present; no `BottomSheet` in tree; dialog has technique instruction widget; dialog closes on dismiss. Covers SCENARIO-BIBW-07a, SCENARIO-BIBW-07b.
- [ ] 1.4.2 [GREEN — REQ-BIBW-07, ADR-BIBW-03] Create `lib/features/coach_hub/presentation/sections/biblioteca/widgets/exercise_detail_dialog.dart`: `ConsumerWidget` returning `AlertDialog` (`SizedBox(width: 520)`, `SingleChildScrollView`, `ConstrainedBox(maxHeight: 560)`, `RoundedRectangleBorder(radius: 20)`, `backgroundColor: palette.bgCard`); watches `slotExerciseProvider((exerciseId, ownerId: isCustom?uid:null, exerciseName))`; `.when` → spinner / error / content composing local header row + `ExerciseVideoPlayer(videoUrl:)` (omitted when null videoUrl) + `TechniqueInstructionItem` list; `actions: [TextButton('Cerrar')]`. Entry point: `showExerciseDetailDialog(BuildContext, {required String exerciseId, String? ownerId, String? exerciseName})`. NO bottom sheet, NO `context.push`. Covers SCENARIO-BIBW-07a, SCENARIO-BIBW-07b.

### Phase 1.5 — Screen shell PR1 (depends on 1.3.4, 1.4.2)

- [ ] 1.5.1 [RED — REQ-BIBW-02] Create `test/features/coach_hub/presentation/sections/biblioteca/biblioteca_web_screen_test.dart`: smoke test — mounted inside a mock `CoachHubScaffold` wrapper, NO `Scaffold` or `SafeArea` descendant of `BibliotecaWebScreen`; `TabBar` with exactly 2 tabs ("Ejercicios", "Templates Rutinas") present. Covers SCENARIO-BIBW-02a.
- [ ] 1.5.2 [GREEN — REQ-BIBW-02] Create `lib/features/coach_hub/presentation/sections/biblioteca/biblioteca_web_screen.dart`: `BibliotecaWebScreen` (`ConsumerStatefulWidget` + `SingleTickerProviderStateMixin`); `TabController(length: 2)`; top-level `Column` (NO Scaffold/SafeArea); header `Text('BIBLIOTECA' // i18n)` (same style as PagosScreen:121–129); `TabBar(isScrollable: false, labelColor: palette.accent, indicatorColor: palette.accent)` with tab labels `"Ejercicios · N"` (N = unfiltered catalog+custom count from `bibliotecaExercisesProvider.valueOrNull?.length` of a separate unfiltered watch, stable while filtering — see ADR note in design §6.1) and `"Templates Rutinas"`; `Expanded(TabBarView([EjerciciosTab(), _TemplatesPlaceholder()]))`. `_TemplatesPlaceholder` = centered `Text('Próximamente // i18n')` (inline, NOT `ProximamenteScreen`). All strings hardcoded es-AR + `// i18n`. All colors `AppPalette.of(context)`. All icons `TreinoIcon`. All 1.5.1 tests MUST go green.

### Phase 1.6 — PR1 gate

- [ ] 1.6.1 Run `flutter analyze` (0 issues), `dart format .`, `flutter test test/features/workout/application/exercise_filter_test.dart test/features/coach_hub/presentation/sections/biblioteca/ test/features/coach/presentation/widgets/exercise_picker_sheet_test.dart`. All MUST pass. Picker tests MUST stay green unchanged (no edits to picker test file).

---

## PR2 — Templates Tab + Section Shell Wiring

### Phase 2.1 — Templates tab widgets (base = PR1 branch)

- [ ] 2.1.1 [RED — REQ-BIBW-09, REQ-BIBW-10, REQ-BIBW-11] Create `test/features/coach_hub/presentation/sections/biblioteca/widgets/templates_tab_test.dart`: 3 template cards from mock provider → 3 rendered cards; each card shows name, días/sem·semanas subtitle, level; NO text matching "alumnos"; empty-list path → empty-state widget; loading → `CircularProgressIndicator`; error → error text. Tap card → `AlertDialog` present, no edit controls. Covers SCENARIO-BIBW-09a, SCENARIO-BIBW-09b, SCENARIO-BIBW-09c, SCENARIO-BIBW-10a, SCENARIO-BIBW-11b.
- [ ] 2.1.2 [GREEN — REQ-BIBW-09] Create `lib/features/coach_hub/presentation/sections/biblioteca/widgets/template_grid_card.dart`: grid card with tinted icon square (`TreinoIcon.tabWorkout` on accent-tint); `routine.name` (bold, `maxLines: 2`); `"${routine.days.length} días/sem · ${routine.numWeeks} semanas"` subtitle; `routine.level.displayNameEs` chip; NO alumnos count; tap → `showTemplateDetailDialog(context, routine)`. All colors `AppPalette.of(context)`, icons `TreinoIcon`. Covers REQ-BIBW-09, SCENARIO-BIBW-09a, SCENARIO-BIBW-09b.
- [ ] 2.1.3 [GREEN — REQ-BIBW-10] Create `lib/features/coach_hub/presentation/sections/biblioteca/widgets/template_detail_dialog.dart`: `showTemplateDetailDialog(BuildContext, Routine)` calls `showDialog` with an `AlertDialog` (read-only; name as title; level chip; días/sem·semanas; per-day slot-count summary from `routine.days`); NO edit controls; `actions: [TextButton('Cerrar')]`. No new provider, no navigation. ADR-CHW-005 compliant. Covers SCENARIO-BIBW-10a.
- [ ] 2.1.4 [GREEN — REQ-BIBW-09, REQ-BIBW-11] Create `lib/features/coach_hub/presentation/sections/biblioteca/widgets/templates_tab.dart`: `ConsumerWidget` watching `trainerTemplatesStreamProvider(uid)` (uid from `currentUidProvider`); `.when` → spinner / error `Text` / `GridView(SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 360, childAspectRatio: 1.6))` of `TemplateGridCard`; empty-list → centered `Text('Todavía no creaste plantillas. // i18n')`. All 2.1.1 tests MUST go green.

### Phase 2.2 — Swap shell placeholder + route wiring (depends on 2.1.4)

- [ ] 2.2.1 [GREEN — REQ-BIBW-02] Edit `biblioteca_web_screen.dart`: replace `_TemplatesPlaceholder` with `TemplatesTab()` in the `TabBarView`. Add import. ~5 lines changed.
- [ ] 2.2.2 [GREEN — REQ-BIBW-01] Edit `lib/features/coach_hub/presentation/sections/biblioteca/routes.dart`: replace `ProximamenteScreen` builder with `const BibliotecaWebScreen()`; add import; remove `ProximamenteScreen` import + `// TODO(W2+)` comment. Keep `bibliotecaSidebarItems` byte-for-byte (NO `badgeProvider`). ~5 lines changed. Covers SCENARIO-BIBW-01a.

### Phase 2.3 — PR2 gate

- [ ] 2.3.1 Verify `sidebar_registry_test.dart` passes unchanged (all items' `badgeProvider isNull`, including biblioteca). Covers SCENARIO-BIBW-01b.
- [ ] 2.3.2 Run `flutter analyze` (0 issues), `dart format .`, `flutter test`. All tests MUST pass: templates tab tests, screen smoke test (now with real TemplatesTab), sidebar registry test, picker tests. Full PR2 gate.

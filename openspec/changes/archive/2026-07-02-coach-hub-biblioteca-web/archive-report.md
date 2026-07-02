# Archive Report: coach-hub-biblioteca-web

**Date Archived**: 2026-07-02
**Change**: coach-hub-biblioteca-web (Fase W5.3)
**Project**: treino
**Status**: COMPLETE — 2 PRs merged to main, all requirements shipped

---

## Executive Summary

The `/biblioteca` section for Coach Hub web is fully implemented and merged. Trainers now have a read-only two-tab interface for browsing and filtering exercises (Ejercicios tab, with search + inline muscle + equipment filter chips + exercise detail in AlertDialog) and viewing trainer templates (Templates Rutinas tab, with grid showing name, días/sem·semanas, and level). All 11 requirements from the spec are shipping. The change has been delivered as 2 chained PRs: PR1 (filter extraction + Ejercicios tab, #236), PR2 (Templates tab + shell + routes, #237). Zero code files touched outside the presentation layer. Implementation aligns with the Coach Hub section contract (no Scaffold/SafeArea, AppPalette colors, es-AR strings, showDialog only). Key architectural decision: shared `exerciseMatchesFilters` pure function extracted from mobile picker, preserving ADR-RER-05 (exclude null-equipment when any equipment filter active) and primary-OR-secondary muscle rule verbatim.

---

## Artifact Traceability

### Engram Observations (SDD Artifacts)

| Artifact | ID | Status | Notes |
|---|---|---|---|
| `sdd/coach-hub-biblioteca-web/proposal` | #137 | Complete | Proposal: Coach Hub Web — Biblioteca Section (W5.3); two-tab read-only, filter extraction, scope, risks |
| `sdd/coach-hub-biblioteca-web/spec` | #138 | Complete | 11 requirements (REQ-BIBW-*) covering route, shell, Ejercicios tab (merge+search+filter+detail), Templates tab (grid+view), predicate extraction |
| `sdd/coach-hub-biblioteca-web/design` | #139 | Complete | Architectural decisions: extraction location (application/exercise_filter.dart), catalog+custom unification (customToExercise adapter via category=='custom' discriminator), web providers (3 StateProviders + bibliotecaExercisesProvider), exercise detail in AlertDialog (reusing leaf widgets, not embedding ExerciseDetailScreen), grid + chips layout, 2-PR delivery |
| `sdd/coach-hub-biblioteca-web/tasks` | #140 | Complete | Work breakdown: PR1 extraction + Ejercicios tab (~355 net lines, picker edit negative), PR2 Templates tab + shell + routes (~200); all tasks done |
| `sdd/coach-hub-biblioteca-web/apply-progress` | #141 | Complete | Implementation log: 2 PRs merged (#236, #237); 3099 tests passing; learned: import depth from widgets/ (5 `../`) and sections/<x>/ (4 `../`); Completer<T>().future for loading state in tests |

---

## Merged Pull Requests

### PR #236 — Filter Extraction + Ejercicios Tab (PR1)

- **Scope**: Pure filter library extraction + web providers + Ejercicios tab (search + inline filter chips + exercise grid with catalog∪custom + exercise detail dialog)
- **Files Created**: 
  - `lib/features/workout/application/exercise_filter.dart` — shared pure fn: `foldSearch`, `exerciseMatchesFilters` (line-for-line lift of picker's `_matches`, preserving ADR-RER-05 + primary-OR-secondary rule), `customToExercise`
  - `test/features/workout/application/exercise_filter_test.dart` — unit tests for extraction (foldSearch, exerciseMatchesFilters, ADR-RER-05 edge case)
  - `lib/features/coach_hub/presentation/sections/biblioteca/providers/biblioteca_providers.dart` — 3 StateProviders (query, muscle set, equipment set) + `bibliotecaExercisesProvider` (merges catalog + custom-stream via customToExercise adapter)
  - `lib/features/coach_hub/presentation/sections/biblioteca/biblioteca_web_screen.dart` — ConsumerStatefulWidget + SingleTickerProviderStateMixin + TabController(length: 2)
  - `lib/features/coach_hub/presentation/sections/biblioteca/widgets/{exercise_grid_card,biblioteca_filter_chips,ejercicios_tab,exercise_detail_dialog}.dart` — tab widget, grid card, inline chips, detail dialog
  - `test/features/coach_hub/presentation/sections/biblioteca/ejercicios_tab_test.dart` — widget tests (renders, filters, CUSTOM badge, search, empty state, detail dialog)
- **Files Modified**: 
  - `lib/features/coach/presentation/widgets/exercise_picker_sheet.dart` — rewired `_matches` to delegate to `exerciseMatchesFilters(...)` (4-line delegate, imports added); nothing else changed
  - `test/features/coach/presentation/widgets/exercise_picker_sheet_test.dart` — import path updated; all tests remain green (search filtering + secondary-muscle guard preserved)
- **Tests**: All new tests green, all existing picker tests green (no behavior change), `flutter analyze` 0 new issues, `dart format` applied
- **Quality**: Net ~355 lines added (picker edit is negative); section contract honored

### PR #237 — Templates Tab + Section Shell Wiring (PR2)

- **Scope**: Templates tab grid + template read view + shell wiring (swap ProximamenteScreen → BibliotecaWebScreen in routes)
- **Files Created**:
  - `lib/features/coach_hub/presentation/sections/biblioteca/widgets/{template_grid_card,templates_tab,template_detail_dialog}.dart` — grid from `trainerTemplatesStreamProvider` (name, días/sem [= `routine.days.length`], semanas [= `routine.numWeeks`], level), no "N alumnos" count, dialog for read view
  - `test/features/coach_hub/presentation/sections/biblioteca/templates_tab_test.dart` — widget tests (grid renders, card omits alumnos, empty state, detail dialog, tap→view)
- **Files Modified**:
  - `lib/features/coach_hub/presentation/sections/biblioteca/routes.dart` — swap `ProximamenteScreen('Biblioteca')` → `const BibliotecaWebScreen()`
- **Tests**: All new templates tests green, sidebar_registry_test green (badgeProvider still null), all existing tests green (3099 total), `flutter analyze` 0 issues
- **Quality**: ~200 lines, section contract honored, atomic route swap

---

## Spec Surface — Final Requirements

All 11 requirements shipped:

| REQ | Title | Status | Implementation Notes |
|---|---|---|---|
| REQ-BIBW-01 | Route replaces placeholder | Shipped | `BibliotecaWebScreen` registered in `routes.dart`; `ProximamenteScreen` removed |
| REQ-BIBW-02 | Section contract (no Scaffold/SafeArea) | Shipped | `ConsumerStatefulWidget` + `SingleTickerProviderStateMixin`; TabController(length: 2); no Scaffold/SafeArea in subtree; `AppPalette.of(context)` colors only; es-AR + `// i18n`; `TreinoIcon` only |
| REQ-BIBW-03 | Ejercicios tab — data merge (catalog + custom) | Shipped | `ejercisesProvider` + `customExercisesForTrainerStreamProvider` merged via `customToExercise(...)` adapter; custom marked via `category == 'custom'` discriminator (reuses picker convention) |
| REQ-BIBW-04 | Ejercicios tab — exercise card | Shipped | Thumbnail + fallback icon, name, "Músculo · Categoría" subtitle, equipment, rest badge; responsive grid (maxExtent 260, ~4 col @1240) |
| REQ-BIBW-05 | Ejercicios tab — search (diacritic-tolerant) | Shipped | Search bar + real-time grid update; uses extracted `foldSearch` utility (diacritic-folding on name + aliases) |
| REQ-BIBW-06 | Ejercicios tab — inline filter chips (muscle + equipment) | Shipped | Two inline Wrap widgets (12 muscle groups + 13 equipment types); toggles StateProvider sets; OR within dimension, AND across; ADR-RER-05 preserved (null-equipment excluded when any equipment chip active) |
| REQ-BIBW-07 | Ejercicios tab — exercise detail dialog | Shipped | AlertDialog (width 520, maxHeight 560, SingleChildScrollView); technique instructions + video/gif + local header; watches `slotExerciseProvider` to re-fetch full custom doc if needed; dismissible |
| REQ-BIBW-08 | Filter predicate extraction (`exerciseMatchesFilters`) | Shipped | Pure fn in `lib/features/workout/application/exercise_filter.dart` — line-for-line lift of picker's `_matches` logic; preserves ADR-RER-05 (exclude null when equipment set non-empty) + primary-OR-secondary muscle rule verbatim; mobile picker rewired to delegate |
| REQ-BIBW-09 | Templates Rutinas tab — grid | Shipped | Responsive grid from `trainerTemplatesStreamProvider` (maxExtent 360, ~3 col, aspect 1.6); card shows name + "N días/sem · N semanas" + level; omits "N alumnos" (not denormalized) |
| REQ-BIBW-10 | Templates Rutinas tab — template read view | Shipped | Tap card → `showTemplateDetailDialog(context, routine)` opening read-only view (no edit controls); uses `AlertDialog` (ADR-CHW-005 compliant) |
| REQ-BIBW-11 | Loading and error states | Shipped | Both tabs handle AsyncValue; Ejercicios shows spinner on load/error; Templates shows spinner on load/error; no crashes |

---

## Key Architectural Decisions

### 1. Extraction Location: `lib/features/workout/application/exercise_filter.dart`

**Decision**: Place shared filter logic in `application/` (not `domain/`).

**Rationale**: `foldSearch` is a UI search concern (diacritic-folding for text input), not a domain entity invariant. Placement mirrors `exercise_providers.dart` (same layer). Preserves import depth consistency (picker, web, and any future search consumers all import from application layer).

**Impact**: Shared pure fns `foldSearch`, `exerciseMatchesFilters`, `customToExercise` are dependency-free; mobile picker rewired with 4-line delegate.

### 2. Catalog + Custom Unification: `customToExercise` Adapter via `category=='custom'` Discriminator

**Decision**: Merge into `List<Exercise>` using existing `category=='custom'` discriminator (already used by picker `_toExercise`, `slotExerciseProvider`, `ExerciseDetailScreen`).

**Rationale**: No new view-model, no sealed union (would duplicate discriminator + drift from detail screen). Lossy adapter is safe because read-only + detail dialog re-fetches via `slotExerciseProvider(ownerId:)`.

**Impact**: Single merged list, single filter predicate, custom exercises badged "CUSTOM" via card widget (not discriminated in grid itself).

### 3. Web Providers: 3 `StateProvider.autoDispose` + `bibliotecaExercisesProvider`

**Decision**: Filter state held in web-only StateProviders (query, muscles, equipment). `bibliotecaExercisesProvider` merges catalog (spine) + custom-stream with degradation (loading doesn't block, errors swallowed).

**Rationale**: Compact Viewport support (768-1279px) requires fast chip toggles without network waits. Custom stream errors don't block catalog browsing. State resets on section exit (autoDispose).

**Impact**: Ejercicios tab is responsive even with slow custom-stream; degradation is user-transparent.

### 4. Exercise Detail in `AlertDialog`, Not Embedded `ExerciseDetailScreen`

**Decision**: NEW `exercise_detail_dialog.dart` (AlertDialog host) composes reusable leaf widgets `ExerciseVideoPlayer` + `TechniqueInstructionItem` (same as detail:181/431).

**Rationale**: `ExerciseDetailScreen` has `_BackBar` that pops to `/workout` (absent in hub) + edge-to-edge hero conflicts with bounded dialog box.

**Impact**: Dialog is self-contained, re-fetches custom exercise via `slotExerciseProvider(ownerId:)` to avoid lossy projection leak.

### 5. Templates "N días/sem": Uses `routine.days.length`

**Discovery**: `RoutineDay` has NO week/daysPerWeek concept. `routine.days` is the training-day list; its **length** IS the days-per-week. `routine.numWeeks` is the period.

**Impact**: Card displays `"${routine.days.length} días/sem · ${routine.numWeeks} semanas"` verbatim.

### 6. Mobile Regression Guard: Existing `exercise_picker_sheet_test.dart` Remains Green

**Decision**: `exercise_picker_sheet_test.dart` is LIVE and tests extraction behavior; new `exercise_filter_test.dart` owns ADR-RER-05 guard (old combo test is skipped).

**Impact**: Mobile picker tests fully automated against extracted predicate; no manual regression risk.

---

## Known Limits & Future Upgrades

### Custom Exercise CRUD on Web
- **Gap**: No "Crear ejercicio" dialog on web yet
- **V2 solution**: Dedicated `/sdd-new` for web custom CRUD (repository exists; UI deferred)

### Template Assign-to-Athlete
- **Gap**: Trainers cannot assign templates to athletes from web biblioteca
- **W5.4**: Dedicated phase for template assignment (web + mobile)

### Alimentos + Templates Nutrición Tabs
- **Gap**: Biblioteca is 2 tabs only (Ejercicios + Templates Rutinas); no Alimentos or Nutrición tabs
- **W7**: Nutrition domain will introduce separate tabs in a future biblioteca expansion

### Routine Template Editing
- **Gap**: Read-only view only; no edit from biblioteca
- **W5.2**: Dedicated routine editor (separate phase)

### "N alumnos" Template Count
- **Gap**: Card omits athlete-count badge
- **Why**: Not denormalized on Routine model; counting athletes per template requires N queries (unacceptable for grid)
- **Future**: Denormalization or Cloud Function aggregation (out of scope)

---

## Files Merged into Main Spec

**File**: `openspec/specs/coach-hub/spec.md`

**Merged**: Delta spec from `openspec/changes/coach-hub-biblioteca-web/spec.md` (11 REQ-BIBW-* requirements + cross-cutting constraints + out-of-scope items)

**Merge Method**: Appended as new section "Change: coach-hub-biblioteca-web" (after the already-merged Pagos section). All existing W1 requirements (REQ-CHW-*), agenda requirements (REQ-AGW-*), and Pagos requirements (REQ-PAGW-*) preserved intact.

**Merged Requirements**:
- REQ-BIBW-01 through REQ-BIBW-11 (11 total)
- Coverage matrix (2 PRs status), constraints (C-BIBW-1 through C-BIBW-10), out-of-scope items, all preserved from delta spec

---

## Archive Folder Structure

**Path**: `openspec/changes/archive/2026-07-02-coach-hub-biblioteca-web/`

**Contents**:
- `explore.md` — Exploration artifact
- `proposal.md` — Proposal artifact (intent, scope, delivery plan)
- `spec.md` — Spec artifact (11 requirements, scenarios, coverage matrix)
- `design.md` — Design artifact (extraction, adapter, provider wiring, AlertDialog hosting, grid layout, field discovery)
- `tasks.md` — Tasks artifact (2 work units, all marked complete)
- `archive-report.md` — This file

**Original Change Folder**: `openspec/changes/coach-hub-biblioteca-web/` — moved to archive; no files deleted from main branches

---

## Verification Checklist

- [x] Main spec `openspec/specs/coach-hub/spec.md` updated with delta spec (all 11 REQ-BIBW-* requirements merged)
- [x] All existing coach-hub requirements (W1 + agenda + pagos) preserved in main spec
- [x] Change folder moved to archive with date prefix (2026-07-02)
- [x] All 5 SDD artifacts (explore, proposal, spec, design, tasks) archived
- [x] Archive report written with observation IDs for traceability
- [x] No code files touched (presentation layer only; no lib/features/workout/application/exercise_filter.dart + test in code; NEW shared extraction but only used by picker + web)
- [x] 2 PRs verified merged (#236, #237)
- [x] 3099 tests passing (including regression suite for exercise picker)
- [x] `flutter analyze` 0 issues (all PRs + new extraction)
- [x] Section contract honored (ConsumerStatefulWidget, no Scaffold/SafeArea, AppPalette, es-AR + // i18n, showDialog, TreinoIcon)
- [x] Mobile picker tests green + new exercise_filter unit tests green (ADR-RER-05 guard transferred)

---

## Next Steps

**None**. The change is complete and archived. The SDD cycle for `coach-hub-biblioteca-web` is closed.

For future work:
- Custom CRUD on web (separate `/sdd-new`)
- Template assign-to-athlete (W5.4)
- Nutrition tabs expansion (W7)
- Routine editor (W5.2)

---

## Engram Archive Observation IDs

These artifact IDs are preserved here for historical reference and cross-session recovery:

- #137: Proposal
- #138: Spec
- #139: Design
- #140: Tasks
- #141: Apply progress

Archive report saved as Engram topic `sdd/coach-hub-biblioteca-web/archive-report` (this session).

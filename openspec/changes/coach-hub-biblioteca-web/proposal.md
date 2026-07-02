# Proposal: coach-hub-biblioteca-web

Fase **W5.3** — Coach Hub WEB **Biblioteca** section (route `/biblioteca`, sidebar group PLAN).

Status: proposed · Project: treino · Repo root: `C:\Users\Martin\Desktop\treino\treino`
Depends on: exploration `sdd/coach-hub-biblioteca-web/explore` (engram #136 / `explore.md`).

---

## 1. Problem

`/biblioteca` today renders a `ProximamenteScreen('Biblioteca')` placeholder
(`sections/biblioteca/routes.dart:16`). The sidebar item is already registered
(`sidebar_registry.dart:50`) and the whole read-side data layer already exists
and is battle-tested on mobile — but the trainer (PF) has **no way to browse or
search their exercise catalog or their routine templates from the web dashboard.**

The gap is 100% presentational. Everything the section needs is already shipped:

- `exercisesProvider` — full catalog (~793), `FutureProvider`, auth-gated
  (`exercise_providers.dart:21`).
- `customExercisesForTrainerStreamProvider` — trainer's custom exercises,
  `StreamProvider.autoDispose.family` (`custom_exercise_providers.dart:24`).
- `trainerTemplatesStreamProvider` — trainer's routine templates
  (`source == 'trainer-template'`), `StreamProvider.autoDispose.family`
  (`routine_providers.dart:28`).

The mobile exercise picker (`exercise_picker_sheet.dart`) already implements
diacritic-tolerant search (`foldSearch`, line 36-47) and the muscle/equipment
filter predicate (`_matches`, lines 102-126) — but that logic is **trapped as
private widget state inside a bottom-sheet widget**, and bottom sheets are
forbidden on web (ADR-CHW-005). So it cannot be reused as-is.

## 2. Goal

Replace the placeholder with a real **read-only** Biblioteca section: two tabs
(Ejercicios + Templates Rutinas) that let a trainer browse, search and filter
their exercises and templates from the web, reusing the existing data providers
and extracting the mobile filter logic into a shared, testable pure function +
web-scoped filter-state providers.

**Success looks like**: both tabs render inside `CoachHubScaffold`; the
Ejercicios grid shows catalog + custom exercises (custom badged), searchable and
filterable via inline chips; tapping an exercise opens a detail Dialog with
technique/video; the Templates grid shows the trainer's templates; the sidebar
item is live; `flutter analyze` = 0 issues and all tests green.

## 3. Scope

### In scope

1. **Section shell** — `BibliotecaWebScreen` (`ConsumerStatefulWidget` +
   `SingleTickerProviderStateMixin` + `TabController`, length 2). No
   Scaffold/SafeArea (ADR-CHW-005). Header title + two-tab `TabBar`.
2. **Ejercicios tab** — search bar + inline filter chips (muscle groups +
   equipment) + responsive grid of exercise cards. List = `exercisesProvider`
   catalog **merged with** `customExercisesForTrainerStreamProvider`; custom
   entries badged "CUSTOM". Card = thumbnail (`assets/exercises/{id}.png` + icon
   fallback) + name + "Músculo · Categoría" + equipment + rest badge. Tap → an
   **exercise detail Dialog** (`AlertDialog`) showing technique instructions +
   video/gif.
3. **Templates Rutinas tab** — grid of template cards from
   `trainerTemplatesStreamProvider`. Card = name + "N días/sem · N semanas" +
   level. Tap → a read view of the template.
4. **Extraction (the architectural core)** — pull `foldSearch` and the `_matches`
   predicate out of `exercise_picker_sheet.dart` into a **shared pure function**
   (e.g. `exerciseMatchesFilters(...)`) + **web-only `StateProvider`s** for the
   three filter dimensions (query, muscle set, equipment set). The mobile picker
   keeps its widget-local state; only the *predicate logic* is shared. ADR-RER-05
   (exclude null-equipment when any equipment filter is active) and the
   primary-OR-secondary muscle rule are preserved verbatim.
5. **Wiring** — register the real screen in `sections/biblioteca/routes.dart`
   (replace `ProximamenteScreen`). Keep `bibliotecaSidebarItems` as-is; do **NOT**
   add a `badgeProvider` (sidebar_registry_test asserts every item's
   `badgeProvider` is null — `sidebar_registry_test.dart:121-123`).

### Out of scope (explicit)

- **Custom exercise CRUD on web** — create/edit/delete of custom exercises.
  Follow-up change (data layer already exists via `CustomExerciseRepository`).
- **Template assign-to-athlete** — the "preview → assign" flow. That's **W5.4**.
- **Alimentos + Templates Nutrición tabs** — belong to the **W7 nutrition
  domain**. Not built here; not even placeholder tabs (2 tabs only).
- **Routine template EDITING** — that's the **W5.2** routine editor. Biblioteca
  must not re-implement it.
- **"N alumnos" template count** — not denormalized on `Routine`; computing it
  live = N Firestore queries per template. Omitted from the template card.
- **Live catalog sync** — `exercisesProvider` is a one-time `FutureProvider`.
  Correct for a static catalog; new seeds appear on next app start. Acceptable.

## 4. Approach (locked)

Read-only browse/search across two tabs. All data comes from the three existing
providers; the only new *logic* is the extracted filter predicate + three
`StateProvider`s holding filter state. The only new *widgets* are the section
shell, web grid cards (adapted from the mobile list rows), inline filter chips
(replacing the mobile bottom-sheet filters), and the exercise detail Dialog.

### 4.1 Reuse map (no re-implementation)

| Need | Reuse | Location |
|------|-------|----------|
| Full catalog list | `exercisesProvider` | `exercise_providers.dart:21` |
| Trainer custom exercises | `customExercisesForTrainerStreamProvider` | `custom_exercise_providers.dart:24` |
| Trainer templates | `trainerTemplatesStreamProvider` | `routine_providers.dart:28` |
| Diacritic-tolerant search | `foldSearch` → **extract to shared fn** | `exercise_picker_sheet.dart:36-47` |
| Filter predicate (query + muscle + equipment) | `_matches` → **extract to shared fn** | `exercise_picker_sheet.dart:102-126` |
| Thumbnail + icon fallback | `_ExerciseThumbnail` pattern | `exercise_picker_sheet.dart:589-658` |
| Card content (name/muscle/badge) | `_ExerciseRow` (adapt row → grid card) | `exercise_picker_sheet.dart:467-583` |
| Template card base | `_TrainerTemplateCard` (adapt row → grid card) | `trainer_templates_section.dart` |
| Section contract (no Scaffold, TabController, es-AR + `// i18n`) | `PagosScreen` sibling | `pagos_web_screen.dart:1-60` |
| Muscle/equipment enums + labels | `MuscleGroup`, `EquipmentType` | `muscle_group.dart`, `equipment_type.dart` |

### 4.2 The extraction (filter logic → shared fn + StateProviders)

The mobile picker holds filter state as private widget fields (`_query`,
`_muscleFilters`, `_equipmentFilters` — `exercise_picker_sheet.dart:77-79`) and
runs `_matches` (lines 102-126) against them. That predicate is the asset worth
sharing.

**Extract a pure function** — signature roughly:

```dart
bool exerciseMatchesFilters(
  Exercise e, {
  required String query,          // raw; foldSearch applied inside
  required Set<MuscleGroup> muscles,
  required Set<EquipmentType> equipment,
});
```

It folds the query, matches name/aliases, applies the muscle OR-across-
primary/secondary rule, and applies ADR-RER-05 (null-equipment excluded when any
equipment filter is active). `foldSearch` moves alongside it (shared utility).
The mobile picker's `_matches` is then rewritten to delegate to this function so
mobile and web share one predicate (single source of truth for the ADRs).

**Web filter state** lives in three lightweight `StateProvider`s (query String,
muscle `Set<MuscleGroup>`, equipment `Set<EquipmentType>`), scoped to the
Biblioteca subtree. This keeps the Ejercicios grid a stateless consumer that
`.watch`es the providers + the two data providers and derives the visible list —
easy to test, no `setState`. Autodispose/reset on tab teardown so re-entering
the section starts clean.

Rationale: extracting the predicate (not the whole sheet) is the minimal, safe
move — it shares the ADR-carrying logic without touching the mobile widget tree,
and it lets the web section be a pure declarative consumer instead of copy-paste.

### 4.3 Web adaptations vs mobile

- Mobile list rows → responsive grid cards (thumbnail-first).
- Mobile bottom-sheet filters (`showMuscleFilterSheet`) → **inline filter chips**
  (ADR-CHW-005 forbids bottom sheets). No `showModalBottomSheet` anywhere.
- Mobile `ExerciseDetailScreen` (expects a host SafeArea) → wrapped in an
  `AlertDialog` on web (`showDialog` only, ADR-CHW-005).
- File/class naming follows the newest sibling convention: file
  `biblioteca_web_screen.dart`, public class `BibliotecaWebScreen` (mirrors
  `agenda_web_screen.dart` / `pagos_web_screen.dart`).

## 5. Delivery plan (chained PRs, each ≤400 lines)

Split to keep each PR independently reviewable and under the 400-line budget.
Rough estimates; sdd-tasks will firm them up.

### PR1 — Extract filter logic + Ejercicios tab (~330-380 lines)

- Extract `foldSearch` + `exerciseMatchesFilters` into a shared location;
  rewire the mobile picker's `_matches` to delegate (net-neutral on the picker).
- Add the three web filter `StateProvider`s.
- `BibliotecaWebScreen` shell (header + 2-tab `TabBar`/`TabBarView`, no Scaffold).
- Ejercicios tab: search bar + inline muscle/equipment chips + exercise grid
  (catalog ∪ custom, custom badged) + exercise detail `AlertDialog`.
- Wire the real screen into `routes.dart` (replace `ProximamenteScreen`).
- Tests: shared-predicate unit tests (search, muscle OR rule, ADR-RER-05); a
  widget test that the Ejercicios grid renders + filters + shows the CUSTOM badge.

### PR2 — Templates Rutinas tab + template read view (~180-240 lines)

- Templates tab: grid of `_BibliotecaTemplateCard` from
  `trainerTemplatesStreamProvider` (name + "N días/sem · N semanas" + level; no
  alumnos count).
- Tap → read view of the template.
- Tests: templates grid renders from a fake provider; card omits alumnos count;
  empty state.

If PR1 trends over budget, peel the shared-predicate extraction + its unit tests
into a PR0 (~120 lines) so the tab UI lands clean on top.

## 6. Risks

1. **Compact-viewport chip overflow** — muscle + equipment chips in two rows may
   overflow at 768-1279px (sidebar-collapsed). Mitigate with `Wrap` /
   horizontal scroll respecting `CoachHubScaffold`'s `rsp.Viewport`.
2. **PNG asset coverage** — not all ~793 catalog ids have
   `assets/exercises/{id}.png`. Reuse the existing icon-fallback pattern
   (`_ExerciseThumbnail`, picker:589-658) on the web card.
3. **Exercise detail must be Dialog-hosted on web** — `ExerciseDetailScreen`
   assumes a host SafeArea; wrapping it in `AlertDialog` needs a sizing/scroll
   pass so long technique lists + video don't overflow.
4. **Two shared consumers of one predicate** — after extraction, mobile picker
   and web tab both depend on `exerciseMatchesFilters`. The mobile picker's
   existing tests must stay green (guards the ADR-RER-05 + muscle-OR behavior).
5. **Naming convention drift** — sibling sections mix `_web_screen.dart` and
   `_screen.dart`. Pinning `biblioteca_web_screen.dart` / `BibliotecaWebScreen`
   to match the two most recent sections; confirm no test globs on a stricter
   pattern.

## 7. Acceptance criteria

1. Both tabs render inside `CoachHubScaffold` (no self Scaffold/SafeArea).
2. Ejercicios: search (diacritic-tolerant) + muscle chips + equipment chips all
   filter the grid; muscle uses primary-OR-secondary; equipment excludes
   null-equipment when active (ADR-RER-05).
3. Custom exercises appear in the Ejercicios grid, badged "CUSTOM".
4. Tapping an exercise opens a detail Dialog showing technique instructions +
   video/gif (no bottom sheet).
5. Templates tab renders trainer templates (name + días/sem · semanas + level),
   with **no** alumnos count; tapping opens a read view.
6. Sidebar `/biblioteca` item routes to the real screen; `ProximamenteScreen`
   removed; `bibliotecaSidebarItems` still has null `badgeProvider`
   (sidebar_registry_test green).
7. `flutter analyze` = 0 issues; `dart format .` clean; all tests green.
8. No changes to domain, data, or any mobile screen behavior (mobile picker tests
   unchanged and green).

## 8. Next phases

- `sdd-spec` — requirements/scenarios (REQ-BIBW-*) for both tabs, filter
  behavior, detail dialog, template card fields, sidebar wiring.
- `sdd-design` — the extraction contract (shared fn signature + StateProvider
  shapes), grid layout/responsiveness, Dialog hosting, card widget structure.

(spec and design can run in parallel; both read this proposal.)

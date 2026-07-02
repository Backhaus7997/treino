# BibliotecaWebScreen — Delta Spec (coach-hub-biblioteca-web)

## Purpose

Defines the presentational and behavioral requirements for the `/biblioteca` route in Coach Hub web (Fase W5.3). This is a pure presentation change: NO new domain or data capabilities are introduced. All data providers, domain models, and CRUD repositories already exist and are mobile-tested. The delta covers route wiring, screen contract, filter-logic extraction, and the two-tab read-only UI.

**Domain-capability delta**: None. All capabilities (catalog query, custom exercise stream, trainer-template stream, search/filter predicate) exist. This spec is 100% presentational + behavioral.

---

## Requirements

### REQ-BIBW-01: Route replaces placeholder

The `/biblioteca` GoRoute MUST render `BibliotecaWebScreen` instead of `ProximamenteScreen`. The existing `bibliotecaSidebarItems` registration in `sidebar_registry.dart` MUST remain unchanged. The `badgeProvider` for the biblioteca sidebar item MUST remain `null`.

#### SCENARIO-BIBW-01a: Sidebar navigation reaches real screen

- GIVEN the trainer is authenticated in Coach Hub web
- WHEN they click the "Biblioteca" sidebar item under group PLAN
- THEN the router navigates to `/biblioteca` and renders `BibliotecaWebScreen` (not `ProximamenteScreen`)

#### SCENARIO-BIBW-01b: Badge provider remains null

- GIVEN the sidebar registry is loaded
- WHEN `sidebar_registry_test` iterates all sidebar items asserting `badgeProvider isNull`
- THEN the biblioteca item passes (no badge provider added)

---

### REQ-BIBW-02: Section contract

`BibliotecaWebScreen` MUST be a `ConsumerStatefulWidget` with `SingleTickerProviderStateMixin`. It MUST NOT declare its own `Scaffold` or `SafeArea` (the shell provides these per ADR-CHW-005). It MUST own a `TabController(length: 2)` for the two tabs. All dialogs MUST use `showDialog`/`AlertDialog`; `showModalBottomSheet` is MUST NOT be used. All string literals MUST be hardcoded es-AR with a `// i18n` comment. All colors MUST come from `AppPalette.of(context)`. All icons MUST use `TreinoIcon`.

#### SCENARIO-BIBW-02a: Screen renders without self Scaffold

- GIVEN `BibliotecaWebScreen` is mounted inside `CoachHubScaffold`
- WHEN the widget tree is inspected
- THEN no `Scaffold` or `SafeArea` widget is found as a descendant of `BibliotecaWebScreen` itself
- AND a `TabBar` with exactly 2 tabs is present ("Ejercicios", "Templates Rutinas")

---

### REQ-BIBW-03: Ejercicios tab — data merge

The Ejercicios tab MUST display a merged list of all catalog exercises (from `exercisesProvider`) and the trainer's custom exercises (from `customExercisesForTrainerStreamProvider`). Custom exercises MUST be visually distinguished with a "CUSTOM" badge. The merge MUST be performed at the presentation layer with no modification to either provider.

#### SCENARIO-BIBW-03a: Custom exercise shows CUSTOM badge

- GIVEN the trainer has at least one custom exercise
- WHEN the Ejercicios tab is displayed with no active filters
- THEN each custom exercise card carries a "CUSTOM" badge
- AND catalog exercises carry no such badge

#### SCENARIO-BIBW-03b: Empty catalog state

- GIVEN both `exercisesProvider` and `customExercisesForTrainerStreamProvider` return empty lists
- WHEN the Ejercicios tab renders
- THEN an empty-state widget is shown (no grid, no error)

---

### REQ-BIBW-04: Ejercicios tab — exercise card

Each exercise card in the grid MUST display: a thumbnail (`assets/exercises/{id}.png`) with an icon fallback if the asset is missing; the exercise name; a "Músculo · Categoría" subtitle; the equipment label; and a rest-seconds badge. Cards MUST be arranged in a responsive grid.

#### SCENARIO-BIBW-04a: Card renders with fallback icon

- GIVEN an exercise whose PNG asset does not exist
- WHEN its card is rendered
- THEN the thumbnail shows a fallback icon (no broken image)
- AND name, muscle, category, equipment, and rest badge are all visible

---

### REQ-BIBW-05: Ejercicios tab — search

The Ejercicios tab MUST provide a search bar. Search MUST be diacritic-tolerant (using the extracted `foldSearch` utility). The grid MUST update in real time as the trainer types. Search matches on exercise name and aliases.

#### SCENARIO-BIBW-05a: Search narrows the grid

- GIVEN the Ejercicios tab is rendered with at least 3 exercises
- WHEN the trainer types "bicep" in the search bar
- THEN only exercises whose name or alias diacritic-fold matches "bicep" remain visible

#### SCENARIO-BIBW-05b: Diacritic tolerance

- GIVEN an exercise named "Remo con Mancuerna"
- WHEN the trainer types "mancuerna" (no accent)
- THEN that exercise card remains visible in the grid

---

### REQ-BIBW-06: Ejercicios tab — inline filter chips

The Ejercicios tab MUST display inline filter chips for muscle groups and equipment types. Chips MUST NOT open any bottom sheet. Multiple chips within a dimension MAY be selected simultaneously (OR within dimension). Deselecting all chips in a dimension removes that dimension's filter. The active filter state MUST be held in web-only `StateProvider`s, not in bottom-sheet widget state.

#### SCENARIO-BIBW-06a: Muscle filter chip narrows the grid

- GIVEN the Ejercicios tab is visible with chips for "PECHO" and "ESPALDA"
- WHEN the trainer taps the "PECHO" chip
- THEN only exercises whose primary or secondary muscle group is Pecho remain visible
- AND no bottom sheet appears

#### SCENARIO-BIBW-06b: Equipment filter excludes null-equipment exercises (ADR-RER-05)

- GIVEN no equipment chips are selected (all equipment shown)
- WHEN the trainer activates any equipment chip (e.g., "MANCUERNA")
- THEN exercises with `equipment == null` are removed from the grid
- AND only exercises matching that equipment type are visible

#### SCENARIO-BIBW-06c: Combined search + filter (AND across dimensions)

- GIVEN a muscle chip "ESPALDA" is active AND the search bar contains "remo"
- WHEN the grid updates
- THEN only exercises that BOTH match the text "remo" AND have Espalda as primary or secondary muscle are shown

#### SCENARIO-BIBW-06d: Multiple chips in one dimension (OR within dimension)

- GIVEN "PECHO" and "HOMBROS" muscle chips are both active
- WHEN the grid renders
- THEN exercises for Pecho OR Hombros (primary or secondary) are shown

---

### REQ-BIBW-07: Ejercicios tab — exercise detail dialog

Tapping an exercise card MUST open an `AlertDialog` (not a bottom sheet, not a full-page route) containing the exercise's technique instructions and, if available, a video/gif. The dialog MUST be dismissible.

#### SCENARIO-BIBW-07a: Tapping card opens detail dialog with technique

- GIVEN an exercise card is visible
- WHEN the trainer taps it
- THEN an `AlertDialog` appears
- AND it displays the exercise's technique instructions
- AND no bottom sheet is shown

#### SCENARIO-BIBW-07b: Dialog without video

- GIVEN an exercise has no `videoUrl`
- WHEN the detail dialog opens
- THEN the video section is absent or shows a placeholder; no crash occurs

---

### REQ-BIBW-08: Filter predicate extraction

The `foldSearch` function and the `_matches` predicate logic MUST be extracted from `exercise_picker_sheet.dart` into a shared, pure, top-level function `exerciseMatchesFilters(Exercise e, {required String query, required Set<MuscleGroup> muscles, required Set<EquipmentType> equipment})`. The mobile picker's internal `_matches` MUST delegate to this extracted function. The ADR-RER-05 rule (exclude null-equipment exercises when any equipment filter is active) and the primary-OR-secondary muscle rule MUST be preserved verbatim.

#### SCENARIO-BIBW-08a: Extracted predicate matches mobile behavior

- GIVEN the same exercise list and the same filter state
- WHEN `exerciseMatchesFilters` is called vs the previous inlined `_matches`
- THEN results are identical (mobile picker tests remain green)

#### SCENARIO-BIBW-08b: ADR-RER-05 preserved in extraction

- GIVEN an exercise with `equipment == null`
- WHEN `exerciseMatchesFilters` is called with a non-empty equipment set
- THEN the function returns `false` for that exercise

---

### REQ-BIBW-09: Templates Rutinas tab — grid

The Templates Rutinas tab MUST display a responsive grid of template cards sourced from `trainerTemplatesStreamProvider`. Each card MUST show: template name; "N días/sem · N semanas" subtitle; and the training level. The card MUST NOT show an "N alumnos" count.

#### SCENARIO-BIBW-09a: Templates grid renders from provider

- GIVEN `trainerTemplatesStreamProvider` returns 3 templates
- WHEN the Templates Rutinas tab is displayed
- THEN 3 cards are rendered, each showing name, días/sem·semanas, and level

#### SCENARIO-BIBW-09b: Card omits alumnos count

- GIVEN a template card is rendered
- WHEN its widget tree is inspected
- THEN no text matching "alumnos" or athlete-count pattern is found on the card

#### SCENARIO-BIBW-09c: Empty templates state

- GIVEN `trainerTemplatesStreamProvider` returns an empty list
- WHEN the Templates Rutinas tab renders
- THEN an empty-state widget is shown (no grid, no error)

---

### REQ-BIBW-10: Templates Rutinas tab — template read view

Tapping a template card MUST open a read-only view of that template. Template editing is out of scope.

#### SCENARIO-BIBW-10a: Tapping template card opens read view

- GIVEN a template card is visible in the grid
- WHEN the trainer taps it
- THEN a read-only view of the template is shown
- AND no edit controls are presented

---

### REQ-BIBW-11: Loading and error states

Both tabs MUST handle loading and error states from their respective providers. A loading indicator MUST be shown while data is in flight. An error message MUST be shown if the provider returns an error.

#### SCENARIO-BIBW-11a: Loading state shown during data fetch

- GIVEN `exercisesProvider` is in the loading state
- WHEN the Ejercicios tab renders
- THEN a loading indicator is visible (no grid, no crash)

#### SCENARIO-BIBW-11b: Error state shown on provider failure

- GIVEN `trainerTemplatesStreamProvider` emits an error
- WHEN the Templates Rutinas tab renders
- THEN an error message is displayed (no crash)

---

## Out of Scope (recorded)

| Item | Reason |
|------|--------|
| Custom exercise CRUD on web | Follow-up; `CustomExerciseRepository` CRUD exists |
| Template assign-to-athlete | W5.4 |
| Alimentos + Templates Nutrición tabs | W7 nutrition domain; not built |
| Routine template editing | W5.2 routine editor |
| "N alumnos" template count | Not denormalized on Routine; omitted |
| Live catalog sync | `exercisesProvider` is one-time FutureProvider; acceptable |

---

## Coverage Matrix

| REQ | Happy Path | Edge Case | Error State |
|-----|-----------|-----------|-------------|
| REQ-BIBW-01 | SCENARIO-BIBW-01a | SCENARIO-BIBW-01b | — |
| REQ-BIBW-02 | SCENARIO-BIBW-02a | — | — |
| REQ-BIBW-03 | SCENARIO-BIBW-03a | SCENARIO-BIBW-03b | — |
| REQ-BIBW-04 | SCENARIO-BIBW-04a | — | — |
| REQ-BIBW-05 | SCENARIO-BIBW-05a | SCENARIO-BIBW-05b | — |
| REQ-BIBW-06 | SCENARIO-BIBW-06a | SCENARIO-BIBW-06b, 06c, 06d | — |
| REQ-BIBW-07 | SCENARIO-BIBW-07a | SCENARIO-BIBW-07b | — |
| REQ-BIBW-08 | SCENARIO-BIBW-08a | SCENARIO-BIBW-08b | — |
| REQ-BIBW-09 | SCENARIO-BIBW-09a | SCENARIO-BIBW-09b, 09c | — |
| REQ-BIBW-10 | SCENARIO-BIBW-10a | — | — |
| REQ-BIBW-11 | — | — | SCENARIO-BIBW-11a, 11b |

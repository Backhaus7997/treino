# Design: coach-hub-biblioteca-web

Fase **W5.3** — Coach Hub WEB Biblioteca section. Architecture / HOW at the
component level. Reads: proposal (`proposal.md`, engram #137) + exploration
(`explore.md`). Repo root `C:\Users\Martin\Desktop\treino\treino`.

Status: designed · Project: treino

This document defines the extraction contract, the catalog∪custom unification,
Dialog hosting, responsive grid layout, and the 2-PR split. It does NOT list
tasks (that is sdd-tasks). Every decision is grounded in real code (file:line
verified in this phase).

---

## 0. Architecture at a glance

```
 lib/features/workout/application/
   exercise_filter.dart            NEW (PR1) — pure predicate + foldSearch (moved)
       exerciseMatchesFilters(Exercise, {query, muscles, equipment}) -> bool
       foldSearch(String) -> String        (moved here from the picker)
              ▲                         ▲
              │ delegates               │ watches
   ┌──────────┘                         └─────────────────────────────┐
 lib/features/coach/presentation/widgets/         lib/features/coach_hub/presentation/sections/biblioteca/
   exercise_picker_sheet.dart  (MOBILE, edit)       biblioteca_web_screen.dart      NEW (PR1) shell + 2 tabs
     _matches() -> delegates to shared fn           providers/biblioteca_providers.dart NEW (PR1) StateProviders + merged list
     imports foldSearch from exercise_filter.dart   widgets/ejercicios_tab.dart     NEW (PR1)
     (NO behaviour change)                          widgets/exercise_grid_card.dart NEW (PR1)
                                                     widgets/biblioteca_filter_chips.dart NEW (PR1)
                                                     widgets/exercise_detail_dialog.dart NEW (PR1)
                                                     widgets/templates_tab.dart      NEW (PR2)
                                                     widgets/template_grid_card.dart NEW (PR2)
                                                     routes.dart                     EDIT (PR2) swap placeholder
```

Layering rule respected: `application/exercise_filter.dart` is
**platform-agnostic pure Dart** (no Flutter, no Riverpod, no BuildContext) so it
imports cleanly into both the mobile widget and the web tree. It sits next to
the existing `exercise_providers.dart` in the SAME `workout/application` layer —
that is where cross-feature, non-widget exercise logic already lives (the
providers, `slotExerciseProvider`, etc.). It is the natural home and keeps the
mobile picker's import depth unchanged (picker already imports from
`workout/application/`).

Data is 100% reuse (proposal §4.1, verified): `exercisesProvider`
(exercise_providers.dart:21), `customExercisesForTrainerStreamProvider`
(custom_exercise_providers.dart:24), `trainerTemplatesStreamProvider`
(routine_providers.dart:27). No new repositories, no new Cloud Functions, no
Firestore work. The ONLY change to shared/mobile code is the extraction.

---

## 1. Filter-logic extraction — the load-bearing decision (PR1)

### 1.1 Current state (verified)

`exercise_picker_sheet.dart`:
- `foldSearch(String)` — top-level fn, lines 36–47. Lowercases + strips Spanish
  diacritics. Already a free function; just needs to MOVE.
- `_matches(Exercise e)` — private method on `_ExercisePickerSheetContentState`,
  lines 102–126. Reads three widget fields (`_query` :77, `_muscleFilters` :78,
  `_equipmentFilters` :79) and encodes TWO ADRs:
  - **primary-OR-secondary muscle** (lines 109–118): matches if EITHER
    `MuscleGroup.fromKey(e.muscleGroup)` OR `.fromKey(e.secondaryMuscleGroup)`
    is in the muscle set. Comment on 109–111 is the canonical rationale.
  - **ADR-RER-05** (lines 119–124): when the equipment set is non-empty, an
    exercise with `equipment == null` is EXCLUDED; otherwise `equipment` must be
    in the set.
- Call sites of `_matches` inside the widget: lines 388 (`filteredCustoms`,
  via `_toExercise(c)`) and 389 (`filteredDefaults`).

### 1.2 New location + signature (RESOLVED)

**Location: `lib/features/workout/application/exercise_filter.dart`** (NEW).

Rationale for `application/` over `domain/`: `foldSearch` is a UI-facing search
utility (presentation concern, not an invariant of the `Exercise` entity), and
the predicate composes filter *state* against a domain object. It belongs with
the other exercise application logic, not in `domain/` (which holds the freezed
entities + enums only). It stays pure Dart regardless.

```dart
// lib/features/workout/application/exercise_filter.dart
import '../domain/equipment_type.dart';
import '../domain/exercise.dart';
import '../domain/muscle_group.dart';

/// Lowercases and strips Spanish diacritics so search tolerates accent/case
/// typos ("elevacion" matches "Elevación"). Applied to BOTH query and candidate
/// before matching. Moved verbatim from exercise_picker_sheet.dart (ADR-RER-01).
String foldSearch(String input) { /* verbatim body from picker:37-46 */ }

/// Single source of truth for the exercise filter predicate — shared by the
/// mobile picker (exercise_picker_sheet.dart) and the web Biblioteca Ejercicios
/// tab. Preserves ADR-RER-05 (exclude null-equipment when any equipment filter
/// is active) and the primary-OR-secondary muscle rule VERBATIM.
///
/// [query] is raw; foldSearch is applied inside. Empty query / empty sets = no
/// constraint on that dimension. AND across dimensions, OR within each set.
bool exerciseMatchesFilters(
  Exercise e, {
  required String query,
  required Set<MuscleGroup> muscles,
  required Set<EquipmentType> equipment,
}) {
  final q = foldSearch(query).trim();
  if (q.isNotEmpty) {
    final nameMatch = foldSearch(e.name).contains(q);
    final aliasMatch = e.aliases.any((a) => foldSearch(a).contains(q));
    if (!nameMatch && !aliasMatch) return false;
  }
  if (muscles.isNotEmpty) {
    final primary = MuscleGroup.fromKey(e.muscleGroup);
    final secondary = MuscleGroup.fromKey(e.secondaryMuscleGroup);
    final hit = (primary != null && muscles.contains(primary)) ||
        (secondary != null && muscles.contains(secondary));
    if (!hit) return false;
  }
  if (equipment.isNotEmpty) {
    if (e.equipment == null) return false;      // ADR-RER-05
    if (!equipment.contains(e.equipment)) return false;
  }
  return true;
}
```

The body is a **line-for-line lift** of `_matches` (picker:103–125) with the
three widget fields turned into named parameters. Zero logic change — this is
what guards the ADRs across both consumers.

### 1.3 Mobile picker rewire (no behaviour change)

In `exercise_picker_sheet.dart`:
1. DELETE the local `foldSearch` (lines 36–47) and its doc comment; add
   `import '../../../workout/application/exercise_filter.dart';`. (The picker
   already imports several `workout/application/*` files, lines 8–11, so this is
   the same relative depth.)
2. Rewrite `_matches` (102–126) to delegate:
   ```dart
   bool _matches(Exercise e) => exerciseMatchesFilters(
         e,
         query: _query,
         muscles: _muscleFilters,
         equipment: _equipmentFilters,
       );
   ```
3. Nothing else in the widget changes — `_query`/`_muscleFilters`/
   `_equipmentFilters` stay as widget-local state; call sites at 388–389 keep
   calling `_matches`. `foldSearch` is now re-exported transitively via the
   import (no other file imports `foldSearch` from the picker — verified: only
   the picker uses it internally).

### 1.4 Mobile picker tests that MUST stay green (regression guard)

Verified in `test/features/coach/presentation/widgets/`:
- **`exercise_picker_sheet_test.dart`** — LIVE (not skipped). The load-bearing
  guard:
  - `search filters list; selected count maintained` (line 170) — exercises the
    query branch of the predicate.
  - group `muscle filter (granular + secondary)` →
    `Hombros filter matches an exercise by its SECONDARY muscle` (line 207) —
    directly guards the **primary-OR-secondary** rule (lunge primary=quads,
    secondary=shoulders, must surface under Hombros).
  - core selection/confirm tests (74–168) — must remain green (they render the
    filtered list).
- **`exercise_picker_filter_combo_test.dart`** — ENTIRELY `skip:`-ped
  (line 71, "PR2 refinement: multi-select filter API; rewrite pending"),
  including the ADR-RER-05 null-equipment test (line 155). It does NOT run, so
  it is not a live guard — but the extraction preserves that behaviour anyway,
  and the NEW web predicate unit test (below) becomes the live ADR-RER-05 guard.

**Net**: after the rewire, `exercise_picker_sheet_test.dart` must pass unchanged.
No test file edits are required for the mobile side.

### 1.5 New unit tests for the extracted fn (PR1)

`test/features/workout/application/exercise_filter_test.dart` (NEW) — pure Dart,
no `pumpWidget`, no Firestore. These become the canonical ADR guards:
- foldSearch strips diacritics + lowercases ("Elevación" ~ "elevacion").
- query matches name OR alias; empty query = pass.
- muscle OR-within-set; **primary-OR-secondary** (lunge quads/shoulders matches
  {hombros}).
- **ADR-RER-05**: null-equipment excluded when equipment set non-empty; included
  when set empty; membership check when non-null.
- AND-across-dimensions (Pecho + Barra → only bench-press).

### 1.6 Web filter StateProviders (PR1)

`sections/biblioteca/providers/biblioteca_providers.dart` (NEW). Three
`autoDispose` `StateProvider`s scoped to the Biblioteca subtree so re-entering
the section starts clean (proposal §4.2):

```dart
final bibliotecaQueryProvider =
    StateProvider.autoDispose<String>((ref) => '');
final bibliotecaMuscleFilterProvider =
    StateProvider.autoDispose<Set<MuscleGroup>>((ref) => const {});
final bibliotecaEquipmentFilterProvider =
    StateProvider.autoDispose<Set<EquipmentType>>((ref) => const {});
```

`autoDispose` (not a raw `StateProvider`) is the deliberate choice: the section
is one route; on navigating away the filter resets, matching the mobile picker's
"fresh on open" semantics without a manual teardown listener. Precedent:
`customExercisesForTrainerStreamProvider` and `trainerTemplatesStreamProvider`
are both `.autoDispose`. The Ejercicios grid is then a pure consumer that
`.watch`es these three + the two data providers and derives the visible list —
no `setState`, easy to widget-test by overriding the providers.

---

## 2. Unifying catalog + custom exercises for the grid — CRITICAL (PR1)

### 2.1 Do they share a common type? (verified — NO)

`Exercise` (exercise.dart:12) and `CustomExercise` (custom_exercise.dart:23) are
two independent freezed classes. They overlap in fields (`id`, `name`,
`muscleGroup`, `secondaryMuscleGroup?`, `videoUrl?`, `defaultRestSeconds?`,
`equipment?`) but:
- `CustomExercise` has `ownerId`, `description`, `createdAt`, `updatedAt`; NO
  `category`, NO `aliases`, NO `techniqueInstructions`.
- `Exercise` has `category`, `aliases`, `techniqueInstructions?`; NO owner/timestamps.

There is NO shared interface/base class. The codebase already solves this exact
merge with a **lossy adapter**: `_toExercise(CustomExercise)` in the picker
(lines 883–895) projects a `CustomExercise` into an `Exercise` with
`category: 'custom'`, `techniqueInstructions: null`, `aliases: []` (default).
`slotExerciseProvider` (exercise_providers.dart:106–116) does the identical
projection. So the established convention is: **adapt CustomExercise → Exercise,
stamped `category: 'custom'`.**

### 2.2 Decision (RESOLVED): adapter → `Exercise`, `category=='custom'` discriminates

**Reuse the existing adapter pattern, do NOT introduce a new view-model or a
sealed union.** The merged web list is `List<Exercise>` where custom entries are
projected via a `customToExercise` adapter identical to the picker's
`_toExercise`. The "is this custom?" signal is `exercise.category == 'custom'`
— exactly what `ExerciseDetailScreen` already keys on (detail:144
`isCustom = category.toLowerCase() == 'custom'`) and what the grid card keys on
for the CUSTOM badge + thumbnail fallback.

Why not a sealed/union or a `BibliotecaEntry` view-model:
- The predicate (`exerciseMatchesFilters`) already takes `Exercise`; a union
  would force branching or an `.toExercise()` at the filter boundary anyway.
- `category == 'custom'` is already the app-wide discriminator (picker + detail
  + slotExerciseProvider). A new type would be a THIRD representation of the same
  concept — churn without payoff, and it would drift from the detail screen.
- Lossiness is acceptable and already accepted for read-only browse: the web
  section never writes custom exercises (out of scope), and the detail dialog
  re-fetches via `slotExerciseProvider(ownerId:)` (see §3) so the full custom
  doc (description, video) is available on tap regardless of the projection.

To avoid duplicating `_toExercise` logic, the adapter is **promoted to the
shared filter file** as a top-level `customToExercise(CustomExercise) ->
Exercise` (or a small `exercise_adapters.dart` next to it). The mobile picker
MAY later delegate its private `_toExercise` to it, but that is NOT required for
this change (keep the picker diff minimal — only `foldSearch` + `_matches`
change). Decision: put `customToExercise` in `exercise_filter.dart` alongside the
predicate; the web merged provider uses it; the picker is left untouched beyond
§1.3.

### 2.3 Merged provider (web-only, autoDispose)

`sections/biblioteca/providers/biblioteca_providers.dart`:

```dart
/// Catalog ∪ trainer-custom, projected to a single List<Exercise> with the
/// active filter predicate applied. Custom entries carry category=='custom'.
/// AsyncValue folding: pending if EITHER source is loading; error if the
/// catalog errors (custom stream errors degrade to empty — the catalog is the
/// spine, mirroring the picker which shows the catalog even if customs fail).
final bibliotecaExercisesProvider =
    Provider.autoDispose<AsyncValue<List<Exercise>>>((ref) {
  final uid = ref.watch(currentUidProvider) ?? '';
  final catalogAsync = ref.watch(exercisesProvider);          // FutureProvider
  final customsAsync = uid.isEmpty
      ? const AsyncValue<List<CustomExercise>>.data(<CustomExercise>[])
      : ref.watch(customExercisesForTrainerStreamProvider(uid)); // StreamProvider

  final query = ref.watch(bibliotecaQueryProvider);
  final muscles = ref.watch(bibliotecaMuscleFilterProvider);
  final equipment = ref.watch(bibliotecaEquipmentFilterProvider);

  // Fold the two AsyncValues. Catalog is authoritative for loading/error.
  return catalogAsync.whenData((catalog) {
    final customs = customsAsync.valueOrNull ?? const <CustomExercise>[];
    // Custom first (matches picker "Tus ejercicios" precedence), then catalog.
    final merged = <Exercise>[
      ...customs.map(customToExercise),
      ...catalog,
    ];
    return merged
        .where((e) => exerciseMatchesFilters(
              e,
              query: query,
              muscles: muscles,
              equipment: equipment,
            ))
        .toList();
  });
});
```

AsyncValue folding rules (explicit, since one source is a `FutureProvider` and
the other a `StreamProvider`):
- **loading**: `catalogAsync` loading → the derived value is loading (spinner).
  The custom stream loading does NOT block — `valueOrNull ?? []` degrades to an
  empty custom list until it arrives, then the provider recomputes and the
  customs pop in. This mirrors the mobile picker, which shows the catalog and
  layers customs on top (picker:210–211, 384–385).
- **error**: catalog error → derived error (grid shows "No pudimos cargar
  ejercicios."). Custom-stream error is swallowed via `valueOrNull` (catalog is
  the spine). Rationale: a trainer with zero/broken customs must still browse the
  full catalog.
- **data**: merged + filtered list. Custom precedence first (visual parity with
  the picker's "Tus ejercicios" above "Catálogo").

The Ejercicios tab watches ONLY `bibliotecaExercisesProvider` for the list and
the three StateProviders for the chip UI — a thin declarative consumer.

---

## 3. Exercise detail on web (PR1)

### 3.1 Constraint (verified)

`ExerciseDetailScreen` (exercise_detail_screen.dart:37) renders a `Stack` with a
`Positioned.fill` CustomScrollView + a floating `_BackBar` that calls
`context.pop()`/`context.go('/workout')` (line 118). It brings NO Scaffold/
SafeArea (doc 32–36) and its `_BackBar` assumes a poppable route + a `/workout`
fallback that does not exist in the Coach Hub router. The mobile picker itself
works around this by pushing the screen inside a throwaway `Scaffold` +
`SafeArea` via `Navigator.push` (picker:496–510) — NOT via `showDialog`. On web,
ADR-CHW-005 forbids bottom sheets and the section contract is `showDialog` only
(pagos/agenda precedent).

Reusing the WHOLE `ExerciseDetailScreen` inside an `AlertDialog` is awkward: the
`_BackBar`'s `/workout` fallback is wrong for the hub, and its edge-to-edge hero
Stack fights a bounded dialog. So:

### 3.2 Decision (RESOLVED): web-specific detail Dialog reusing the leaf content widgets

Build `sections/biblioteca/widgets/exercise_detail_dialog.dart` — a
`ConsumerWidget` returning an `AlertDialog` (backgroundColor `palette.bgCard`,
`RoundedRectangleBorder` radius 20, `SizedBox(width: 520)` content wrapped in
`SingleChildScrollView` + `ConstrainedBox(maxHeight: 560)`), mirroring the exact
hosting pattern of `AppointmentDetailDialog` (appointment_detail_dialog.dart:186,
227 `SizedBox(width: 480)` + `SingleChildScrollView`). It does NOT embed
`ExerciseDetailScreen`; it composes the same **leaf content widgets** that screen
uses, which are already reusable and Scaffold-free:
- `ExerciseVideoPlayer(videoUrl:)` (imported from
  `workout/presentation/widgets/exercise_video_player.dart`) — the screen uses it
  at detail:181; handles null/invalid/valid internally.
- `TechniqueInstructionItem(index:, text:)`
  (`workout/presentation/widgets/technique_instruction_item.dart`) — for the
  técnica list, same as detail:431.
- A local header row (breadcrumb `MÚSCULO · CATEGORÍA` + title) instead of the
  edge-to-edge `_HeroStrip` (the hero + `_BackBar` are screen-shell concerns; the
  dialog has a close button in `actions:` like the agenda dialog:425–436).

Data source: the dialog watches
`slotExerciseProvider((exerciseId: id, ownerId: isCustom ? uid : null, exerciseName: name))`
— the SAME provider the mobile detail screen uses (detail:60), which already has
the 3-tier fallback and, crucially, re-fetches the FULL `CustomExercise`
(description, videoUrl) for custom ids via Tier 3 (exercise_providers.dart:96–116).
This is why the lossy grid projection (§2.2) is safe: the dialog does not rely on
the projected `Exercise`; it re-resolves the real one. States: `.when` →
loading spinner / error text / content, same contract as the screen.

`showExerciseDetailDialog(BuildContext, {required String exerciseId, String? ownerId, String? exerciseName})`
is the entry point the grid card calls on tap. No `context.push`, no bottom
sheet, no `/workout` fallback — pure `showDialog`.

Rationale over embedding the full screen: avoids the wrong `/workout` pop
fallback and the edge-to-edge hero in a bounded box, while reusing the two
non-trivial widgets (video + technique) that actually carry the content. Total
new widget is small because the heavy lifting stays in the reused leaves.

---

## 4. Grids + filter chips (responsive) (PR1 grid/chips; PR2 template grid)

### 4.1 Responsive breakpoints (verified)

`responsive.dart`: `Viewport.compact = [768, 1280)` (sidebar force-collapsed),
`Viewport.desktop = >= 1280`. `< 768` never reaches the section (`MobileBanner`
replaces the whole shell — scaffold:32). Content is width-capped at 1240px by
`ContentMaxWidth` (scaffold:47). So the section only ever renders at **compact**
or **desktop**; both must be handled, mobile is out of the picture.

Grid column counts are driven off `LayoutBuilder` constraints (the actual
content width after the sidebar + 1240 cap), NOT `MediaQuery` — because the
available width differs between compact (sidebar collapsed) and desktop, and the
1240 cap means the content box tops out. Use `GridView` with
`SliverGridDelegateWithMaxCrossAxisExtent` so column count derives from a target
tile width and reflows automatically:

- **Exercise grid**: `maxCrossAxisExtent: 260` → ~4 columns at 1240px content,
  3 at compact (~900–1000px content). `childAspectRatio` ~0.82 (thumbnail-first
  card is taller than wide). Matches mockup "~4 col wide, fewer on compact".
- **Template grid**: `maxCrossAxisExtent: 360` → ~3 columns at 1240, 2 at
  compact. `childAspectRatio` ~1.6 (short wide card). Matches mockup "~3 col".

Using `maxCrossAxisExtent` (not a hard `crossAxisCount`) means no manual
breakpoint math and no overflow — Flutter picks the count. This is simpler and
more robust than branching on `rsp.viewportFor`.

### 4.2 Filter chips — compact viewport (Risk #1)

Two chip dimensions: muscle (12 `MuscleGroup.displayOrder`) + equipment (13
`EquipmentType.values`). Rendered as multi-select toggle chips. To avoid overflow
at compact (768–1279, sidebar collapsed):
- Each chip row is a `Wrap(spacing: 8, runSpacing: 8)` — wraps to N lines instead
  of overflowing. `Wrap` is chosen over horizontal `SingleChildScrollView`
  because on a mouse-first web viewport a horizontal scroll strip is a poor
  affordance (no visible scrollbar by default) and the chips are few enough that
  1–2 wrapped rows read cleanly. (Proposal Risk #1 allowed either; `Wrap` picked.)
- Muscle chips and equipment chips are two separate `Wrap`s under small section
  captions ("MÚSCULO" / "EQUIPAMIENTO"), each toggling membership in the
  corresponding `StateProvider` set. A "TODOS" affordance = clear-the-set
  (leading chip that, when tapped, sets the set to `const {}`; visually active
  when the set is empty).
- Chip visuals reuse the active/idle token treatment from the picker's
  `_FilterButton` (picker:753–806): active = `accent` border 1.5 + `accent`
  tint 0.12 + accent text; idle = `bgCard` + `border`. Extracted as a small
  `_FilterChip` inside `biblioteca_filter_chips.dart` (NOT importing the picker's
  private widget).

`biblioteca_filter_chips.dart` is a `ConsumerWidget` that reads/writes the three
StateProviders directly; it emits no callbacks (state lives in Riverpod).

### 4.3 Exercise grid card thumbnail (Risk #2)

Reuse the `assets/exercises/{id}.png` + icon-fallback pattern from the picker's
`_ExerciseThumbnail` (picker:589–658), adapted from 44×44 ClipOval to a full-
width card header (`AspectRatio` ~16/10, `Image.asset` with `errorBuilder` →
`Icon(TreinoIcon.dumbbell)` on `palette.bgCard`). Custom exercises
(`category == 'custom'`) skip the asset entirely and render the dumbbell icon
(same branch as picker:616–621), because customs never have a catalog PNG. This
is a NEW `exercise_grid_card.dart` widget (grid layout), not a reuse of the row
widget — but the fallback LOGIC is copied from the verified picker pattern.

Card content (mockup + proposal §3.2): thumbnail → name (bold, `maxLines: 2`
ellipsis) → `"Músculo · Categoría"` subtitle (`muscleGroupLabel(e.muscleGroup)` +
category ES map: compound→"Compuesto", isolation→"Aislamiento", custom→"Mío") →
equipment chip (`e.equipment?.label`, omitted when null) → rest badge
(`"${e.defaultRestSeconds} seg"`, accent, omitted when null). Custom card shows a
`"CUSTOM"` badge (reuse the `_Badge` visual token treatment; violet/accent per
mockup). Tap → `showExerciseDetailDialog(...)` (§3).

---

## 5. Templates tab (PR2)

### 5.1 Template card fields — where they come from (verified)

`Routine` (routine.dart:22) + `RoutineDay` (routine_day.dart:9):
- **name** → `routine.name` (direct).
- **"N días/sem"** → `routine.days.length`. Each `RoutineDay` is ONE training
  day of the weekly split; the count of days = days-per-week. (There is no
  separate "daysPerWeek" field — the list length IS it. Verified: RoutineDay has
  `dayNumber`, `name`, `slots`, `estimatedMinutes` — no week concept; the
  periodization week count lives on the parent as `numWeeks`.)
- **"N semanas"** → `routine.numWeeks` (routine.dart:42, `@Default(1)`).
- **nivel** → `routine.level.displayNameEs` (experience_level.dart:41 →
  Principiante / Intermedio / Avanzado), uppercased for the chip.

All three exist directly on the domain — no derivation gap, no extra query.
Subtitle string: `"${days.length} días/sem · ${numWeeks} semanas"`, level as a
separate chip. **OMIT "N alumnos"** (proposal out-of-scope: not denormalized on
Routine; computing = N Firestore queries).

### 5.2 Template grid + card

`templates_tab.dart` (`ConsumerWidget`) watches
`trainerTemplatesStreamProvider(uid)` (routine_providers.dart:27) via
`currentUidProvider`. `.when` → loading spinner / error text / grid. Empty state
= centered "Todavía no creaste plantillas." (no "Crear" CTA — creation is W5.2,
out of scope). Grid uses the §4.1 template delegate (~3 col).

`template_grid_card.dart` — adapted from `_TrainerTemplateCard`
(trainer_templates_section.dart:98) row → grid card: tinted icon square
(`TreinoIcon.tabWorkout` on accent-tint, same as :136), name (bold, `maxLines: 2`),
the días/sem·semanas subtitle, and the level chip. Tap → read view. The mobile
card pushes `/workout/routine/{id}` (line 113) which does NOT exist in the Coach
Hub router — so on web the tap opens a **read-only routine detail** consistent
with the section contract. For PR2 the simplest contract-compliant read view is
a routine detail `AlertDialog` (name + level + días/semanas + per-day slot
counts derived from `routine.days`), reusing `routineByIdProvider`
(routine_providers.dart:36) if a fresh fetch is wanted, or just the already-
streamed `Routine` object passed into the card (no extra fetch needed — the list
already has the full `Routine`). Decision: pass the in-hand `Routine` to a small
`showTemplateDetailDialog(context, routine)` — no new provider, no navigation,
ADR-CHW-005 compliant. (Full template preview/assign is W5.4, out of scope.)

---

## 6. Screen structure + PR split

### 6.1 `BibliotecaWebScreen` shell (PR1)

File: `sections/biblioteca/biblioteca_web_screen.dart`. Class
`BibliotecaWebScreen` (pins the naming to `agenda_web_screen.dart` /
`pagos_web_screen.dart`). `ConsumerStatefulWidget` +
`SingleTickerProviderStateMixin`, `TabController(length: 2)`. NO Scaffold, NO
SafeArea (ADR-CHW-005) — top-level `Column` exactly like `PagosScreen`
(pagos_web_screen.dart:38–113). Structure:
- Header row: `Text('BIBLIOTECA')` (uppercase, letterSpacing 1.2, `w700`,
  `palette.textPrimary`) — same style as `PagosScreen` header (pagos:121–129). No
  "+ CREAR NUEVO" button (creation out of scope).
- `TabBar` (2 tabs: "Ejercicios" · N / "Templates" · N), `isScrollable: false`
  (only 2 tabs — fits), `labelColor: palette.accent`,
  `indicatorColor: palette.accent`, listener → `setState` for count labels
  (mirrors pagos:54–55, 97–102). Counts: Ejercicios N from
  `bibliotecaExercisesProvider.valueOrNull?.length` (or the unfiltered catalog+
  custom count — use unfiltered so the tab label is stable while filtering);
  Templates N from `trainerTemplatesStreamProvider`.
- `Expanded(child: TabBarView(children: [EjerciciosTab(), TemplatesTab()]))`.

Strings: hardcoded es-AR + `// i18n` (constraint C-6, verified in pagos/agenda).
Colors: `AppPalette.of(context)` only. Icons: `TreinoIcon.*`.

### 6.2 Wiring (PR2 — see split rationale)

`sections/biblioteca/routes.dart`: replace the `ProximamenteScreen` builder
(routes.dart:16) with `const BibliotecaWebScreen()`, add the import, drop the
`ProximamenteScreen` import + the `TODO(W2+)` comment. `bibliotecaRoutes` is
already spread into `_signedInRoutes` (coach_hub_router.dart:109) — **no router
edit needed**. Keep `bibliotecaSidebarItems` byte-for-byte (routes.dart:22–30):
do NOT add `badgeProvider` — `sidebar_registry_test.dart:121-125` iterates ALL
registry items asserting `badgeProvider isNull`. The `SidebarItem` const stays as
is; only the route builder changes.

### 6.3 File-by-PR + line estimates

**PR1 — Extraction + Ejercicios tab (~355 lines, target ≤400)**
| File | Action | ~lines |
|------|--------|--------|
| `workout/application/exercise_filter.dart` | NEW (foldSearch moved + predicate + customToExercise) | 60 |
| `coach/presentation/widgets/exercise_picker_sheet.dart` | EDIT (delete foldSearch, delegate _matches, import) | −15 net |
| `test/features/workout/application/exercise_filter_test.dart` | NEW (predicate units + ADR-RER-05) | 90 |
| `sections/biblioteca/providers/biblioteca_providers.dart` | NEW (3 StateProviders + merged provider) | 55 |
| `sections/biblioteca/biblioteca_web_screen.dart` | NEW (shell + 2-tab TabBar; Templates tab = temporary placeholder body until PR2) | 70 |
| `sections/biblioteca/widgets/ejercicios_tab.dart` | NEW (consumes merged provider + chips + grid) | 55 |
| `sections/biblioteca/widgets/exercise_grid_card.dart` | NEW (thumbnail+fallback, name, subtitle, badges) | 65 |
| `sections/biblioteca/widgets/biblioteca_filter_chips.dart` | NEW (two Wraps, _FilterChip) | 60 |
| `sections/biblioteca/widgets/exercise_detail_dialog.dart` | NEW (AlertDialog reusing video+technique) | 70 |
| `test/features/coach_hub/.../ejercicios_tab_test.dart` | NEW (renders/filters/CUSTOM badge) | 60 |

PR1 note: to keep PR1 self-contained AND under budget, the shell renders the
Ejercicios tab fully and a minimal inline placeholder for the Templates tab
(a centered "Próximamente" `Text`, NOT `ProximamenteScreen`) so the screen is
already wired via routes only in PR2. **Split alternative (preferred if PR1
trends over 400)**: keep `routes.dart` on `ProximamenteScreen` through PR1 and
land Ejercicios behind the real screen only in PR2 — see PR2. The estimate above
(~355 net, since the picker edit is negative) fits; routes.dart swap is deferred
to PR2 so PR1 ships no user-visible route change (lower risk, extraction + tab
land first).

**PR2 — Templates tab + wiring (~200 lines, target ≤400)**
| File | Action | ~lines |
|------|--------|--------|
| `sections/biblioteca/widgets/templates_tab.dart` | NEW (stream + grid + empty) | 55 |
| `sections/biblioteca/widgets/template_grid_card.dart` | NEW (adapt row→card) | 55 |
| `sections/biblioteca/widgets/template_detail_dialog.dart` | NEW (read-only AlertDialog) | 45 |
| `sections/biblioteca/biblioteca_web_screen.dart` | EDIT (swap Templates placeholder → TemplatesTab) | 5 |
| `sections/biblioteca/routes.dart` | EDIT (ProximamenteScreen → BibliotecaWebScreen) | 5 |
| `test/features/coach_hub/.../templates_tab_test.dart` | NEW (renders, omits alumnos, empty) | 55 |

Both PRs land ≤400. PR1 is net-smaller than raw additions because the picker
edit removes lines. Fallback (proposal): if PR1 exceeds budget, peel
`exercise_filter.dart` + its unit test into a PR0 (~150) and let the tab land on
top.

---

## 7. ADRs

### ADR-BIBW-01 — Extraction location + signature
**Decision**: Put `foldSearch` + `exerciseMatchesFilters(Exercise, {query,
muscles, equipment})` + `customToExercise` in a NEW pure-Dart file
`lib/features/workout/application/exercise_filter.dart`. Rewire the mobile
picker's `_matches` to delegate; move `foldSearch` out of the picker.
**Rationale**: `workout/application` is where non-widget exercise logic already
lives (providers, slot resolution); the file stays free of Flutter/Riverpod so
both the mobile widget and the web tree import it at the same relative depth. One
predicate = one source of truth for ADR-RER-05 + the primary-OR-secondary rule.
**Rejected**: (a) `domain/exercise.dart` static method — `foldSearch` is a UI
search concern, not an entity invariant; pollutes the freezed model. (b) A web-
only copy of the predicate — duplicates the ADR logic, guaranteed to drift. (c)
Leaving it in the picker and importing the private method — impossible (private);
exposing the widget's private state is worse.

### ADR-BIBW-02 — Catalog + custom unification
**Decision**: Merge into `List<Exercise>` using the existing lossy adapter
(`customToExercise`, `category: 'custom'`); discriminate custom via
`category == 'custom'`. No new view-model, no sealed union.
**Rationale**: `category == 'custom'` is ALREADY the app-wide discriminator
(picker `_toExercise`, `slotExerciseProvider`, `ExerciseDetailScreen`). The
predicate takes `Exercise`. Reusing the convention avoids a third representation
and keeps the detail dialog (which re-fetches the real custom doc via
`slotExerciseProvider`) consistent. Lossiness is safe for read-only browse.
**Rejected**: (a) sealed `BibliotecaEntry { Catalog | Custom }` — forces
`.toExercise()` at the filter boundary anyway + duplicates the discriminator. (b)
new `ExerciseViewModel` — churn; drifts from the detail screen's `category`
check. (c) two separate lists/sections like the mobile picker — the mockup shows
ONE mixed grid with badges, not "Tus ejercicios"/"Catálogo" headers.

### ADR-BIBW-03 — Exercise detail Dialog host
**Decision**: A web-specific `exercise_detail_dialog.dart` (`AlertDialog`,
width 520, scroll, maxHeight 560) that composes the reusable leaf widgets
`ExerciseVideoPlayer` + `TechniqueInstructionItem` and watches
`slotExerciseProvider` — NOT an embed of the whole `ExerciseDetailScreen`.
**Rationale**: `ExerciseDetailScreen`'s `_BackBar` pops to `/workout` (nonexistent
in the hub) and its edge-to-edge hero Stack fights a bounded dialog; the mobile
picker only reuses it by pushing a throwaway Scaffold route (forbidden on web).
Composing the two content leaves reuses the non-trivial parts (video state
machine + technique list) while honoring ADR-CHW-005 (`showDialog` only) and the
pagos/agenda dialog precedent. The dialog re-fetches the full exercise (incl.
custom description/video) via `slotExerciseProvider`, so the grid's lossy
projection never leaks.
**Rejected**: (a) `AlertDialog(content: ExerciseDetailScreen(...))` — wrong pop
fallback + hero overflow in a box. (b) `context.push` to a routed detail —
ADR-CHW-005 wants dialogs for these overlays; no hub route exists.

### ADR-BIBW-04 — 2-PR split with deferred route swap
**Decision**: PR1 = extraction + StateProviders + shell + Ejercicios tab (route
still on `ProximamenteScreen`, Templates tab a temporary inline placeholder).
PR2 = Templates tab + template read dialog + swap `routes.dart` to the real
screen. Each ≤400 lines; PR1 net-smaller because the picker edit removes lines.
**Rationale**: keeps the user-visible route change atomic in PR2 (Biblioteca goes
live only when BOTH tabs are real), while PR1 lands the load-bearing extraction +
its unit tests first (guarded by the existing green picker test). Independent
reviewability; respects the 400-line budget without a forced `size:exception`.
**Rejected**: (a) single PR — ~555 lines, over budget, mixes shared-code
extraction with two tabs' UI. (b) route swap in PR1 — Biblioteca would go live
with a placeholder Templates tab (worse UX than staying "Próximamente" until
complete).

---

## 8. Constraints honored (recap)
- **Reuse-only for data**: no new repos/CFs; three existing providers only.
- **Extraction is the ONLY shared/mobile change**: picker loses `foldSearch` +
  gets a 4-line delegating `_matches`; nothing else in `lib/` outside
  `coach_hub/.../biblioteca/` + the new `exercise_filter.dart`.
- **Mobile picker must not regress**: `exercise_picker_sheet_test.dart` (live,
  incl. secondary-muscle + search) stays green unchanged; new
  `exercise_filter_test.dart` becomes the live ADR-RER-05 guard.
- **Coach Hub section contract (ADR-CHW-005)**: no Scaffold/SafeArea, `showDialog`
  only (no bottom sheets), es-AR hardcoded + `// i18n`, `AppPalette.of(context)`,
  `TreinoIcon.*`, TabController via `SingleTickerProviderStateMixin`.
- **Sidebar**: `bibliotecaSidebarItems` unchanged, no `badgeProvider`
  (sidebar_registry_test green).

## 9. Risks / open items for tasks + apply
- Card `childAspectRatio` (0.82 exercise / 1.6 template) is a first estimate —
  apply must tune against real content so names don't clip and rest/equipment
  badges fit. Low risk (widget test + visual pass).
- `bibliotecaExercisesProvider` swallows custom-stream errors by design; confirm
  in review this is the intended degradation (catalog is the spine).
- Tab count labels: using the UNFILTERED catalog∪custom count for the "Ejercicios
  · N" label (stable while filtering). Confirm with spec wording in tasks.
- `exercise_video_player.dart` + `technique_instruction_item.dart` are assumed
  Scaffold-free reusable leaves (they are used inside `ExerciseDetailScreen`'s
  sliver body, so they are context-agnostic) — apply should smoke-test them
  inside the dialog for sizing.

## 10. Next phase
`sdd-tasks` — read this design + the spec (`sdd/coach-hub-biblioteca-web/spec`)
and produce the ordered task breakdown per PR. Design (this) + spec run parallel;
tasks needs both.

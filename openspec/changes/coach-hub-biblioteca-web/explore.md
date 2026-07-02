# Exploration: coach-hub-biblioteca-web

Fase W5.3 — Biblioteca section of Coach Hub web dashboard.
Route `/biblioteca`, sidebar group PLAN.

---

## Current State

`lib/features/coach_hub/presentation/sections/biblioteca/routes.dart` declares:
- Route `/biblioteca` → `ProximamenteScreen(label: 'Biblioteca')` (placeholder, line 16)
- `bibliotecaSidebarItems` with `SidebarGroup.plan` and `TreinoIcon.sidebarBiblioteca` (line 22–30)
- `bibliotecaSidebarItems` already registered in `sidebar_registry.dart` (line 50)

---

## Data Surface (file:line, verified)

### 1. Exercise Domain Model

`lib/features/workout/domain/exercise.dart`:
- `Exercise` (freezed): `id`, `name`, `muscleGroup` (String, canonical key), `secondaryMuscleGroup?`, `category` ('compound'|'isolation'), `techniqueInstructions?` (List<String>?), `videoUrl?`, `defaultRestSeconds?`, `aliases` (List<String>), `equipment?` (EquipmentType?)

`lib/features/workout/domain/muscle_group.dart`:
- `MuscleGroup` enum: 12 groups — pecho, espalda, hombros, biceps, triceps, cuadriceps, isquiotibiales, gluteos, pantorrilla, abdominales, cardio, cuerpoCompleto
- Each has `key` (English, Firestore wire), `label` (Spanish), `assetPath?` (muscle illustration PNG)
- `MuscleGroup.displayOrder` = declaration order (line 41)
- `muscleGroupLabel(String? raw)` top-level function for display (line 95)

`lib/features/workout/domain/equipment_type.dart`:
- `EquipmentType` enum: 13 types — mancuerna, barra, maquina, cable, banda, pesoCorporal, cardio, pesaRusa, disco, trx, multipower, otro, ninguno
- Each has `label` (Spanish) and `jsonValue` (snake_case for Firestore)

### 2. Exercise Catalog — Where it lives

**Firestore collection `exercises`** — `ExerciseRepository` (`lib/features/workout/data/exercise_repository.dart`):
- `listAll()` → fetches ALL catalog exercises (no filter, single snapshot) (line 15)
- `getById(String id)` → single doc (line 20)
- `getByIds(List<String> ids)` → chunked batch, max 30 per `whereIn` (line 27)
- No stream — it's a static catalog (one-time fetch)

**Catalog size**: ~793 exercises per the change description (landed PRs #136/#216 expanded from 25 → 415 → 793). Lives in Firestore `exercises` collection, NOT an asset file.

**Provider** (`lib/features/workout/application/exercise_providers.dart`):
- `exerciseRepositoryProvider` (line 10)
- `exercisesProvider` → `FutureProvider<List<Exercise>>` — auth-gated full catalog load (line 21)
- `exerciseByIdProvider` → in-memory lookup derived from `exercisesProvider` (line 41)
- `slotExerciseProvider` → 3-tier fallback (catalog id → name/alias → custom exercises) (line 72)

**GAP CONFIRMED**: No `exerciseSearchProvider` or `exerciseFilterProvider` exists anywhere in the codebase. The picker filter logic is inlined in `_ExercisePickerSheetContent._matches()` at `lib/features/coach/presentation/widgets/exercise_picker_sheet.dart` line 102–126. A web-scoped filter/search provider needs to be created.

### 3. Custom Exercises

`lib/features/workout/domain/custom_exercise.dart`:
- `CustomExercise` (freezed): `id`, `ownerId`, `name`, `muscleGroup`, `secondaryMuscleGroup?`, `description`, `videoUrl?`, `defaultRestSeconds?`, `equipment?`, `createdAt`, `updatedAt`
- Lives at `users/{trainerId}/customExercises/{exId}` (line 22–26 of repo)

`lib/features/workout/data/custom_exercise_repository.dart`:
- `create()`, `update()`, `delete()`, `watchForTrainer(trainerId)` → live Stream ordered by name asc (line 103)
- `getById({trainerId, exerciseId})` (line 117)
- Full CRUD already implemented

`lib/features/workout/application/custom_exercise_providers.dart`:
- `customExerciseRepositoryProvider` (line 16)
- `customExercisesForTrainerStreamProvider` → `StreamProvider.autoDispose.family<List<CustomExercise>, String>` (line 24)

**Relation to catalog**: Custom exercises are SEPARATE from the catalog. `slotExerciseProvider` merges them in Tier 3. In the picker, they are displayed in a "Tus ejercicios" section above "Catálogo". The `_toExercise()` adapter projects `CustomExercise` into `Exercise` with `category: 'custom'` (line 883 of picker).

### 4. Routine Templates

`lib/features/workout/domain/routine.dart`:
- `Routine` (freezed): `id`, `name`, `split?`, `level` (ExperienceLevel), `days` (List<RoutineDay>), `estimatedMinutesPerDay?`, `imageUrl?`, `source` (RoutineSource), `assignedBy?`, `assignedTo?`, `visibility` (RoutineVisibility), `createdBy?`, `status` (RoutineStatus), `numWeeks`

`lib/features/workout/domain/routine_source.dart`:
- `RoutineSource` enum: `system`, `trainerTemplate`, `trainerAssigned`, `userCreated`
- **A TEMPLATE = `source == 'trainer-template'`** — no explicit boolean flag; the `source` field is the discriminator
- `assignedTo == null` for templates (no assigned athlete)
- `assignedBy == trainerId` (trainer owns the template)

`lib/features/workout/data/routine_repository.dart`:
- `watchTemplatesBy(trainerId)` → live stream of trainer's templates (`source == 'trainer-template'`, ordered by `createdAt DESC`) (line 374)
- `createTemplate(Routine)`, `updateTemplate({uid, draft})`, `deleteRoutine(id)`, `assignTemplateToAthlete({template, athleteId})` — full CRUD exists (lines 332–411)

`lib/features/workout/application/routine_providers.dart`:
- `trainerTemplatesStreamProvider` → `StreamProvider.autoDispose.family<List<Routine>, String>` (line 28) — direct reuse target

**CONFIRMED**: Data layer for listing templates is already complete. No new providers or Firestore work needed for read-only template browsing.

### 5. Existing Exercise-Browser UI (Reuse Target)

`lib/features/coach/presentation/widgets/exercise_picker_sheet.dart` — **primary reuse target**:
- `foldSearch(String input)` utility for diacritic-tolerant search (line 36) — reuse directly
- `_ExercisePickerSheetContent._matches(Exercise e)` filter logic: text query + muscle (OR) + equipment (OR, excludes null when any filter active per ADR-RER-05) (lines 102–126) — extract to a standalone function/provider
- `_ExerciseRow` widget: thumbnail (asset `assets/exercises/{id}.png` with error fallback), name, muscle subtitle, badge, detail button (lines 467–583)
- `_ExerciseThumbnail` widget: 44×44 ClipOval, `assets/exercises/{id}.png` with icon fallback (lines 589–658)
- `_FilterButton` widget: muscle and equipment filter buttons with count badge (lines 738–807)
- `_SectionHeader` widget: group header ("Tus ejercicios" / "Catálogo") (lines 809–830)

`lib/features/coach/presentation/widgets/muscle_filter_sheet.dart`:
- `showMuscleFilterSheet` (bottom sheet, multi-select) — **WEB CONSTRAINT: cannot reuse as bottom sheet (ADR-CHW-005 forbids bottom sheets); must adapt to inline filter chips or a Dialog**
- `_MuscleRow` widget with muscle illustration from `assets/muscles/{key}.png` — reusable

`lib/features/workout/presentation/my_exercises_screen.dart`:
- Mobile custom exercise library (list-only, no search/filter) — secondary reference
- `_ExerciseCard`: name + muscleGroupLabel + video indicator (lines 155–228)

`lib/features/workout/presentation/widgets/trainer_templates_section.dart`:
- `_TrainerTemplateCard`: compact row card with icon square + name + level·exercises subtitle — reusable as template card base

`lib/features/workout/presentation/widgets/routine_card.dart`:
- Full routine card for plantillas — check if it matches the mockup template card layout

**IMPORTANT WEB ADAPTATION**: The mobile picker uses `showModalBottomSheet` for muscle/equipment filters. On web (ADR-CHW-005), bottom sheets are forbidden. The filter UI must use inline filter chips (as seen in the mockup) or `showDialog`.

### 6. Mockup Layout Analysis

Source: `docs/web-trainer/screens/biblioteca/ejercicios.png` and `template-rutina.png`

**Biblioteca Screen Header**:
- Title "BIBLIOTECA" (top left)
- Subtitle: "472 ejercicios · 86 alimentos · 24 templates" (item counts per tab)
- Top-right: global search bar + notification bell + "+ CREAR NUEVO" button (green accent)

**Tab Bar** (4 tabs in mockup, but W5.3 scope is 2):
1. `EJERCICIOS · 472` (active)
2. `ALIMENTOS · 86` (out of scope for W5.3 — nutrition feature)
3. `TEMPLATES RUTINAS · 14` 
4. `TEMPLATES NUTRICIÓN · 10` (out of scope for W5.3)

**W5.3 scope: tabs 1 and 3 only. Tabs 2 and 4 render `ProximamenteScreen` placeholders.**

**Ejercicios Tab**:
- Search bar: "Buscar ejercicio..." (full width left side)
- Muscle filter chips row: TODOS | PECHO | ESPALDA | PIERNA | HOMBROS | BRAZOS | CORE | CARDIO (scrollable, single-select visual)
- Equipment filter chips row (right side of same row): MANCUERNA | BARRA | MÁQUINA | PESO CORPORAL
- Exercise card grid: **4 columns** on desktop
  - Card: large colored thumbnail (GIF/video preview or static image), exercise name (bold), muscle group + category subtitle (e.g. "Pecho · Tirón"), equipment chip (e.g. "Barra"), rest time badge (green, e.g. "90 seg")
  - Custom exercises have a "CUSTOM" badge (purple/violet)
  - Card hover likely shows more detail

**Templates Rutinas Tab**:
- No search bar visible
- Template card grid: **3 columns** on desktop
  - Card: colored background + bolt icon (colored per split type), template name (UPPERCASE, bold), days/weeks subtitle ("6 días/sem · 8 semanas"), level chip ("INTERMEDIO" / "PRINCIPIANTE"), athletes count badge (green, e.g. "6 ALUMNOS")
  - The "6 ALUMNOS" count = how many athletes are currently assigned this template (computed from `listAssignedTo` queries — this would be expensive; likely a mock or denormalized field for V1)

### 7. Section Contract (confirmed from sibling sections)

From `pagos_web_screen.dart` (lines 1–10) and `agenda_web_screen.dart` (lines 1–9):
```dart
// NO Scaffold, NO SafeArea (ADR-CHW-005 — shell provides it)
class BibliotecaWebScreen extends ConsumerStatefulWidget { ... }
// TabController with SingleTickerProviderStateMixin
// showDialog / AlertDialog — NOT showModalBottomSheet
// Strings: hardcoded es-AR + // i18n comment (NOT AppL10n)
// AppPalette.of(context) for all colors (NEVER HEX)
// TreinoIcon.X for all icons
```

From `biblioteca/routes.dart`:
- Route: `/biblioteca`
- `bibliotecaSidebarItems` const list — will gain a sub-route for the real screen

---

## Affected Areas

- `lib/features/coach_hub/presentation/sections/biblioteca/routes.dart` — replace `ProximamenteScreen` with real screen
- `lib/features/coach_hub/presentation/sections/biblioteca/biblioteca_web_screen.dart` — NEW: main screen file
- `lib/features/coach_hub/presentation/sections/biblioteca/widgets/` — NEW: exercise card, template card, filter chips
- `lib/features/workout/application/exercise_providers.dart` — possibly add `bibliotecaExerciseFilterProvider` (StateProvider for filter state)
- `lib/features/coach/presentation/widgets/exercise_picker_sheet.dart` — read-only: extract `foldSearch` + filter logic for reuse
- No changes to domain, data, or any mobile screen

---

## Gap Analysis

| Layer | Status | Notes |
|-------|--------|-------|
| `Exercise` domain model | COMPLETE | All needed fields present |
| `exercisesProvider` (full catalog) | COMPLETE | FutureProvider, auth-gated |
| `customExercisesForTrainerStreamProvider` | COMPLETE | StreamProvider.family |
| `trainerTemplatesStreamProvider` | COMPLETE | StreamProvider.family |
| Exercise search/filter provider (web) | **MISSING** | Filter logic is inlined in mobile picker; need `StateProvider`s for query + muscle filter + equipment filter |
| Template "ALUMNOS" count per template | **UNKNOWN** | Not denormalized on Routine. Computing live would require N queries. V1 scope decision needed |
| Exercise card (web, grid style) | MISSING | Mobile has list row (`_ExerciseRow`); web needs grid card (thumbnail-first layout) |
| Template card (web, grid style) | MISSING | `_TrainerTemplateCard` is a compact row; web needs larger grid card |
| Muscle/equipment filter chips (web inline) | MISSING | Mobile uses bottom sheets (forbidden on web per ADR-CHW-005) |
| No Scaffold/SafeArea | Enforced by convention | Confirmed from all sibling sections |
| es-AR strings + `// i18n` | Enforced by convention | Confirmed from pagos + agenda |

---

## Approaches

### Approach 1 — V1 Read-only browse/search (recommended)

Both tabs are browse-only:
- **Ejercicios tab**: search by name, filter by muscle group (inline chips), filter by equipment (inline chips), grid of exercise cards (catalog + custom mixed)
- **Templates tab**: list/grid of trainer's own templates, tap to open read-only `RoutineDetailScreen` (already exists)
- No create/edit/delete in Biblioteca itself

**Pros**:
- Fastest delivery (~3–4 PRs)
- Zero risk of breaking existing mobile flows
- Clean separation from W5.2 routine editor (which handles full editing)
- Reuses `exercisesProvider` + `trainerTemplatesStreamProvider` directly
- Filter state is local widget state (no new providers strictly needed, though a scoped StateProvider is cleaner)
- Template "alumnos count" can be omitted (show level + days instead) or shown as placeholder "—"

**Cons**:
- PF cannot create custom exercises from Biblioteca on web (must use mobile)
- Template cards won't show "ALUMNOS count" without extra work

**Effort**: Medium (2–3 PRs)

---

### Approach 2 — V1 browse + custom exercise CRUD on web

Adds create/edit/delete for custom exercises in the Ejercicios tab (matching `MyExercisesScreen` on mobile).

**Pros**:
- PF can manage their exercise library from web (natural workflow)
- `CustomExerciseRepository` CRUD already exists — just needs web UI
- No video upload needed for V1 (defer to V2)

**Cons**:
- Adds ~1 extra PR worth of work (editor dialog/panel)
- Video upload on web requires `CustomExerciseVideoUploadService` which has a web stub — needs verification
- Increases risk surface

**Effort**: Medium-High (3–4 PRs)

---

### Approach 3 — V1 browse + template open/duplicate

Adds the ability to open a template and immediately assign it to an athlete (using existing `RoutineRepository.assignTemplateToAthlete()`).

**Pros**:
- High value for trainer workflow ("preview template → assign to athlete")
- Repository method already exists

**Cons**:
- Opens a full athlete-picker UX gap (which athlete? → needs athlete list dialog)
- Overlaps with the Plans/Rutinas sections of Coach Hub
- Scope creep risk — template editing is W5.2 (separate change)

**Effort**: Medium-High (3–4 PRs) — lower value relative to effort vs Approach 1

---

## Recommendation

**Approach 1 (read-only browse/search) for W5.3 V1.**

The data layer is fully ready. The gap is entirely presentational: web-adapted exercise cards (grid, not list), inline filter chips (not bottom sheets), and a template card grid. The "ALUMNOS count" should be omitted from the template card in V1 (show level + split + numWeeks instead) to avoid N Firestore queries per template.

The filter state should be extracted into lightweight `StateProvider`s (scoped to the Biblioteca widget tree via `ProviderScope`) to keep the screen stateless and testable, reusing `foldSearch()` from the picker.

A second PR could add custom exercise CRUD (Approach 2) as a follow-up once V1 is stable.

---

## Scope Options for Proposal

| Option | Tabs included | Actions | Effort | Recommended for |
|--------|--------------|---------|--------|-----------------|
| **V1 Read-only** | Ejercicios + Templates Rutinas (browse/search/filter only) | View exercise detail (dialog), view template detail (RoutineDetailScreen push) | 2–3 PRs, ~350–500 LOC | W5.3 baseline |
| **V1 + Custom exercise create** | Same + custom exercise creation via Dialog | Create (no video) in Ejercicios tab | +1 PR (~150 LOC) | W5.3 extension |
| **V1 + Template assign** | Same + assign-to-athlete flow | Pick athlete → assign template | +1 PR (~200 LOC, needs athlete picker Dialog) | W5.4 separate |

Full routine template EDITING is W5.2 (routine editor). Biblioteca must NOT re-implement that.

---

## Risks

1. **"ALUMNOS count" per template**: The mockup shows it (e.g., "6 ALUMNOS"), but computing it requires querying all `routines` where `source == trainer-assigned` AND `assignedBy == trainerId` AND the template was the source. This is not denormalized. V1 should either omit the count or show it only after a secondary fetch (acceptable for small template counts).

2. **Exercise asset coverage**: Catalog images live at `assets/exercises/{id}.png`. Not all 793 exercises have a matching PNG. The `_ExerciseThumbnail` widget already handles this with an icon fallback — same pattern must apply to the web grid card.

3. **Filter chips width on compact viewport**: The mockup shows 8 muscle chips + 4 equipment chips in two separate scrollable rows. At 768–1279px (compact sidebar-collapsed mode), these may need wrapping or scrolling. The `CoachHubScaffold` already handles compact vs desktop via `rsp.Viewport` — the filter row must respect this.

4. **`exercisesProvider` is a FutureProvider (one-time fetch)**: The 793-exercise catalog is loaded once and cached by Riverpod. This is correct for a static catalog but means any new exercises seeded to Firestore after app start will not appear until the provider is invalidated or the app restarts. Acceptable for V1.

5. **GIF/video in exercise cards**: The mockup shows animated/colored backgrounds for exercise cards. The current `assets/exercises/{id}.png` are static PNGs. True GIF/video previews are not currently seeded. V1 grid cards should use the existing PNG assets (same as mobile) with the existing fallback.

6. **Template card "ALUMNOS count" source**: If implemented, it requires `RoutineRepository.listAssignedTo(athleteId)` per template reversed — no existing method for "given templateId, count assignments". This would require a new Firestore query or index. **Recommend deferring this to V2.**

---

## Open Questions

1. **W5.3 scope boundary**: Is the "CREAR NUEVO" button (top-right in mockup) part of W5.3? It appears global to the section (suggests create new exercise or template). Recommendation: include it only for custom exercise creation; template creation routes to the existing W5.2 editor.

2. **Alimentos and Templates Nutrición tabs**: These are visible in the mockup as additional tabs. For W5.3, they should render `ProximamenteScreen` placeholders. The tab count in the header subtitle ("472 ejercicios · 86 alimentos · 24 templates") should reflect real counts or be omitted until the other tabs are implemented.

3. **Exercise detail on web**: Should tapping an exercise card open the existing mobile `ExerciseDetailScreen` (which has no Scaffold of its own but expects SafeArea from its host) adapted to a web Dialog, or a new web-specific exercise detail panel? Recommendation: open in an `AlertDialog` wrapping `ExerciseDetailScreen` content for V1 (consistent with ADR-CHW-005).

4. **Custom exercises in Ejercicios tab**: Should custom exercises appear merged with the catalog (Approach 1) or only in a separate "Mis ejercicios" subsection? The mobile picker uses a "Tus ejercicios" header above "Catálogo". Recommend same pattern for V1.

---

## Ready for Proposal

Yes — data surface is fully mapped, mockup is clear, section contract is confirmed, reuse targets are identified. The proposal should define:
- 2-tab scope (Ejercicios + Templates Rutinas) with 2 placeholder tabs (Alimentos + Templates Nutrición)
- Filter state approach (local StateProviders vs widget state)
- Exercise detail interaction (Dialog vs panel)
- Template card fields for V1 (no alumnos count)
- PR breakdown (shell + Ejercicios tab + Templates tab)

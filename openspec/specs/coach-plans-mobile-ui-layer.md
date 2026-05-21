# Spec: Coach Plans Mobile — UI Layer

**Capability**: coach-plans-mobile-ui
**Layer**: workout + coach presentation
**Fase / Etapa**: 5 / 4
**SDD Cycle**: 2026-05-21
**Delivered by**: PR #70 (`feat/coach-plans-mobile-ui`) + PR #71 (`feat/coach-plans-mobile-ui-trainer`)
**Status**: ARCHIVED
**Related Specs**: coach-plans-mobile-data-layer.md, workout-application.md

---

## Overview

The coach-plans-mobile-ui layer closes the trainer-to-athlete plan delivery cycle at the UI level. The trainer gains `AthleteDetailScreen` (accessible from `_ActiveAlumnoCard` tap) and `RoutineEditorScreen` (full-screen plan builder with metadata, days, exercise picker, and submit). The athlete gains `MiPlanSection` replacing the `_TuRutinaSection` placeholder in `WorkoutScreen`. `RoutineDetailScreen` gains a conditional "Asignado por \<PF\>" chip. Two new routes enable navigation: `/coach/athlete/:athleteId` and `/workout/routine-editor/:athleteId`.

### Motivation

Fase 5 Etapa 1-3 established the coach infrastructure (fields, links, public profiles). Etapa 4 delivers the user-facing experience: trainers can create and assign plans, athletes can view and interact with assigned plans. This closes the loop from "Trainer creates a plan" to "Athlete sees it and uses it."

### Capabilities

| Capability | Provided by |
|------------|-------------|
| Athlete plan list with multi-plan support | `MiPlanSection` widget |
| Plan editor with form + exercise picker | `RoutineEditorScreen` |
| Trainer athlete discovery and plan creation | `AthleteDetailScreen` |
| "Asignado por \<PF\>" attribution on detail screen | `_AssignedByChip` in RoutineDetailScreen |
| Trainer athlete card tap-through | InkWell on `_ActiveAlumnoCard` |
| Route: `/coach/athlete/:athleteId` | Router registration |
| Route: `/workout/routine-editor/:athleteId` | Router registration |

---

## Requirements

| ID | Name | Strength |
|----|------|-------------|
| REQ-COACH-PLANS-012 | `MiPlanSection` replaces `_TuRutinaSection` in `WorkoutScreen` | MUST |
| REQ-COACH-PLANS-013 | `MiPlanSection` loading state | MUST |
| REQ-COACH-PLANS-014 | `MiPlanSection` error state | MUST |
| REQ-COACH-PLANS-015 | `MiPlanSection` empty state | MUST |
| REQ-COACH-PLANS-016 | `MiPlanSection` single-plan data state | MUST |
| REQ-COACH-PLANS-017 | `MiPlanSection` multi-plan data state | MUST |
| REQ-COACH-PLANS-018 | `MiPlanSection` "Plan finalizado" badge when link terminated | MUST |
| REQ-COACH-PLANS-019 | `RoutineDetailScreen` chip "Asignado por \<PF\>" when `trainerAssigned` | MUST |
| REQ-COACH-PLANS-020 | `_ActiveAlumnoCard` tap navigates to `AthleteDetailScreen` | MUST |
| REQ-COACH-PLANS-021 | `AthleteDetailScreen` renders athlete header and trainer's plans | MUST |
| REQ-COACH-PLANS-022 | `AthleteDetailScreen` "CREAR PLAN" navigates to `RoutineEditorScreen` | MUST |
| REQ-COACH-PLANS-023 | `RoutineEditorScreen` renders metadata section and days list | MUST |
| REQ-COACH-PLANS-024 | `RoutineEditorScreen` exercise picker bottom sheet | MUST |
| REQ-COACH-PLANS-025 | `RoutineEditorScreen` submit — success path | MUST |
| REQ-COACH-PLANS-026 | `RoutineEditorScreen` submit — validation error (empty form) | MUST |
| REQ-COACH-PLANS-027 | `RoutineEditorScreen` submit — loading state | MUST |
| REQ-COACH-PLANS-028 | `RoutineEditorScreen` submit — network error | MUST |
| REQ-COACH-PLANS-029 | Router — `/coach/athlete/:athleteId` registered | MUST |
| REQ-COACH-PLANS-030 | Router — `/workout/routine-editor/:athleteId` registered | MUST |

### SCENARIO Coverage

- **SCENARIO-444**: `MiPlanSection` shows loader while provider resolves
- **SCENARIO-445**: `MiPlanSection` shows error message on provider failure
- **SCENARIO-446**: `MiPlanSection` shows empty state text when no plans assigned
- **SCENARIO-447**: `MiPlanSection` renders single plan card with trainer name
- **SCENARIO-448**: tapping a plan card navigates to `RoutineDetailScreen`
- **SCENARIO-449**: `MiPlanSection` renders all plans newest-first when multiple plans exist
- **SCENARIO-450**: "Plan finalizado" badge appears when trainer link is terminated
- **SCENARIO-451**: no badge when trainer link is active
- **SCENARIO-452**: chip renders for trainer-assigned routine
- **SCENARIO-453**: chip is absent for non-assigned routine
- **SCENARIO-454**: tapping `_ActiveAlumnoCard` pushes the athlete detail route
- **SCENARIO-455**: `AthleteDetailScreen` renders header and empty plans list with CTA
- **SCENARIO-456**: tapping "CREAR PLAN" pushes the routine editor route
- **SCENARIO-457**: `RoutineEditorScreen` renders all form sections on load
- **SCENARIO-458**: exercise picker bottom sheet appears and filters on search
- **SCENARIO-459**: selecting an exercise from the picker assigns it to the slot
- **SCENARIO-460**: successful submit pops back and shows confirmation SnackBar
- **SCENARIO-461**: submit with no days does not call `createAssigned`
- **SCENARIO-462**: submit button is disabled while creation is in progress (SKIP — test timing issue)
- **SCENARIO-463**: network error on submit shows error SnackBar and re-enables submit
- **SCENARIO-464**: navigating to `/workout/routine-editor/athlete-5` renders `RoutineEditorScreen` (MISSING — no dedicated test)

---

## Presentation Layer: Screens and Widgets

### MiPlanSection

**Module**: `lib/features/workout/presentation/widgets/mi_plan_section.dart`

**Type**: `ConsumerWidget`

**Parent Container**: Rendered at the top of `WorkoutScreen` (above `PlantillasSection`).

**State Machine** (6 states):

| State | Condition | Display |
|-------|-----------|---------|
| **LOADING** | Provider is loading | CenteredLoadingIndicator |
| **ERROR** | Provider returns `AsyncError` | Error message + retry button |
| **EMPTY** | Provider returns `[]` | Empty state text ("No tienes planes asignados") |
| **SINGLE** | Provider returns list with 1 plan | Single `_PlanCard` |
| **MULTI** | Provider returns list with 2+ plans | `ListView` of `_PlanCard` widgets, newest-first |
| **FINALIZED** | Link is terminated | `_PlanCard` with "Plan finalizado" badge |

**Provider Reads**:
- `authStateChangesProvider` → current athlete UID
- `assignedRoutinesProvider(athleteId)` → list of assigned plans
- `currentAthleteLinkProvider` → link status (to determine if badge should show)

**Behavior**:
- Automatically refetches when link status changes.
- Tapping a plan card navigates to `RoutineDetailScreen` with that routine ID.
- Retry button on error refreshes the provider.

**Styling**:
- All colors via `AppPalette.of(context)`.
- All icons via `TreinoIcon.X`.
- Spacing uses 8 / 12 / 14 / 18 / 20 px scale.
- Copy via `CoachStrings`.

### _PlanCard Widget

**Module**: `lib/features/workout/presentation/widgets/mi_plan_section.dart` (private)

**Type**: `StatelessWidget`

**Input**: `Routine` + boolean `isLinkTerminated`

**Layout**:
- **Card wrapper**: rounded corners, shadow, padding 12px
- **Name** (primary): `routine.name` as bold headline
- **Trainer Name** (secondary): via `userPublicProfileProvider(routine.assignedBy)` (e.g., "Plan de Manuel")
- **Days Summary** (tertiary): e.g., "Lunes, Miércoles, Viernes"
- **Badge** (conditional): "Plan finalizado" if `isLinkTerminated` (green chip with strikethrough icon)

**Behavior**:
- Entire card is tappable via `InkWell`.
- On tap: `context.push('/workout/routine/:id')` with routine id.
- No button (tap the whole card).

**Styling**: Consistent with other plan tiles in the app.

### _AssignedByChip

**Module**: `lib/features/workout/presentation/routine_detail_screen.dart` (private)

**Type**: `ConsumerWidget`

**Parent Context**: Second chip in `_HeroStrip` (top section of RoutineDetailScreen), below the day/time metadata chip.

**Condition**: Only rendered if `routine.source == RoutineSource.trainerAssigned`.

**Behavior**:
1. Reads `userPublicProfileProvider(routine.assignedBy!)` to resolve trainer name.
2. While loading: displays "..." (spinner optional).
3. On error: displays "un PF" (fallback text).
4. On success: displays trainer's displayName (e.g., "Plan de Manuel").
5. No tap action (read-only attribution).

**Styling**:
- Chip with rounded corners, icon (e.g., `TreinoIcon.coachBadge`), and text.
- Color: `palette.accent` (mint).
- Font: body2 or subtitle2.

### RoutineEditorScreen

**Module**: `lib/features/workout/presentation/routine_editor_screen.dart`

**Type**: `StatefulWidget` (local mutable form state)

**Route**: Nested under `/workout` shell route → `/workout/routine-editor/:athleteId`

**Constructor Parameter**: `athleteId` (String) — the target athlete this plan will be assigned to.

**Local State**:
- Name text controller
- Split text controller
- daysPerWeek dropdown
- level dropdown
- List<_EditableDay> days (mutable classes with text controllers and slots)
- bool _submitting (for loading state)
- bool _isValid (computed)

**Mutable Local Classes**:
```dart
class _EditableDay {
  String dayName; // "Lunes", "Martes", etc.
  TextEditingController notes; // Optional rest notes
  List<_EditableSlot> slots;
}

class _EditableSlot {
  Exercise? exercise;
  int sets;
  int repsMin;
  int repsMax;
}
```

**Layout** (single scroll, Column inside AppBar + body):

1. **AppBar**: "CREAR PLAN" title + close button (X) at top
2. **Metadata Section** (collapsed by default):
   - Name TextField
   - Split TextField
   - daysPerWeek Dropdown (1-7)
   - level Dropdown
   - ExpansionTile labeled "MÁS OPCIONES"
3. **Days Section**:
   - One ExpansionTile per day
   - Each tile header shows day name (e.g., "LUNES") with slot count badge
   - Expanded view:
     - Notes TextField (optional)
     - List of slots with exercise picker rows
     - "Agregar slot" button
4. **Submit Section** (sticky at bottom):
   - ElevatedButton "CREAR PLAN"
   - Disabled when !_isValid or _submitting
   - Shows CircularProgressIndicator inside button during _submitting

**Form Validation**:
- name non-empty ✓
- split non-empty ✓
- daysPerWeek 1-7 ✓
- ≥1 day with ≥1 slot ✓
- Each slot: exercise non-null, sets ≥ 1, repsMin ≥ 1, repsMax ≥ repsMin ✓

**Exercise Picker**:
- Modal bottom sheet: `showModalBottomSheet<Exercise>()`
- isScrollControlled: true (allows sheet to grow with keyboard)
- Header: "Seleccionar ejercicio" + close (X)
- Search field: TextField that filters `exercisesProvider` results in real-time
- Results: ListView of ExerciseTile, tap to select
- Confirms selection, sheet pops, slot's exercise is set

**Submit Behavior**:
1. Validates form (early return if !_isValid).
2. Constructs immutable `Routine` with:
   - name, split, daysPerWeek, level from form
   - source: 'trainer-assigned'
   - assignedBy: currentTrainerUid
   - assignedTo: athleteId (from route param)
   - visibility: 'private' (MVP default)
   - days: deserialized from _EditableDay list
3. Calls `ref.read(routineRepositoryProvider).createAssigned(routine)`.
4. On success:
   - Invalidates `assignedRoutinesProvider(athleteId)` to refetch athlete's plans.
   - Shows SnackBar: "Plan creado" (green/success).
   - Pops back to previous screen.
5. On failure:
   - Shows SnackBar: "No pudimos crear el plan. Intentá de nuevo." (error red).
   - Re-enables submit button.
   - Preserves form state (user can retry without re-typing).

**Styling**:
- No standalone `Scaffold` (uses parent shell's scaffold).
- All copy via `CoachStrings`.
- All colors via `AppPalette.of(context)`.
- All icons via `TreinoIcon.X`.

### AthleteDetailScreen

**Module**: `lib/features/coach/presentation/athlete_detail_screen.dart`

**Type**: `ConsumerWidget`

**Route**: Nested under `/coach` shell route → `/coach/athlete/:athleteId`

**Constructor Parameter**: `athleteId` (String) — the athlete to view.

**Layout**:

1. **AppBar**: Athlete display name (from `userPublicProfileProvider`) + back arrow
2. **Header Section**:
   - Athlete avatar (32px) + displayName (headline) + gym (if exists)
   - Optional: role badge (if trainer viewing another trainer, e.g., "Co-Entrenador")
3. **Plans Section**:
   - Heading: "MIS PLANES" or "PLANES DE [ATHLETE]" (context-aware)
   - List of plans filtered by `assignedBy == currentTrainerUid` (trainer can only see plans they created)
   - Each plan: small `_PlanCard` variant (name + days summary)
   - Tap plan: navigate to detail screen
4. **CTA Section** (sticky at bottom):
   - ElevatedButton "CREAR PLAN" (high contrast, prominent)
   - On tap: navigate to `/workout/routine-editor/:athleteId`
5. **Empty State** (if no plans):
   - Icon + copy: "No has creado planes para este atleta todavía"
   - CTA button below

**Provider Reads**:
- `userPublicProfileProvider(athleteId)` → athlete name/avatar/gym
- `assignedRoutinesProvider(athleteId)` → all plans assigned to this athlete
- Current trainer filter: plans where `assignedBy == currentTrainerUid`

**Behavior**:
- If trainer viewing themselves (rare): show "MIS PLANES" (self perspective).
- If trainer viewing another athlete: show "PLANES DE [ATHLETE]" (other perspective).
- Refresh list when navigating back from editor (via invalidation in editor's success path).

**Styling**:
- All colors via `AppPalette.of(context)`.
- All icons via `TreinoIcon.X`.
- Spacing uses 8 / 12 / 14 / 18 / 20 px scale.
- Copy via `CoachStrings`.

### _ActiveAlumnoCard Modification

**Module**: `lib/features/coach/trainer_coach_view.dart`

**Change**: Wrap the card in `InkWell` with tap handler.

**Before**:
```dart
_ActiveAlumnoCard(link: link, ...)
```

**After**:
```dart
InkWell(
  onTap: () {
    context.push('/coach/athlete/${link.athleteId}');
  },
  child: _ActiveAlumnoCard(link: link, ...),
)
```

**Behavior**:
- The card is now tappable and navigates to athlete detail screen.
- Internal "TERMINAR VÍNCULO" button (if present) retains its own InkResponse; Flutter propagates to inner most responder first (correct behavior).
- Splash ripple effect on tap.

---

## Router Integration

### Routes Registered

**File**: `lib/app/router.dart`

#### Route 1: `/coach/athlete/:athleteId`

```dart
GoRoute(
  path: 'athlete/:athleteId',
  pageBuilder: (context, state) {
    final athleteId = state.pathParameters['athleteId']!;
    return NoTransitionPage(
      child: AthleteDetailScreen(athleteId: athleteId),
    );
  },
),
```

**Parent**: `/coach` ShellRoute (bottom nav visible)

**Parameters**: `athleteId` (String) — the athlete UID

**Navigation Stack**: Athlete detail pushes onto existing coach view stack.

#### Route 2: `/workout/routine-editor/:athleteId`

```dart
GoRoute(
  path: 'routine-editor/:athleteId',
  pageBuilder: (context, state) {
    final athleteId = state.pathParameters['athleteId']!;
    return NoTransitionPage(
      child: RoutineEditorScreen(athleteId: athleteId),
    );
  },
),
```

**Parent**: `/workout` ShellRoute (bottom nav visible)

**Parameters**: `athleteId` (String) — the target athlete for plan assignment

**Navigation Stack**: Editor pushes onto workout view stack.

---

## WorkoutScreen Integration

### Change: Replace `_TuRutinaSection` with `MiPlanSection`

**File**: `lib/features/workout/workout_screen.dart`

**Before**:
```dart
// ...
_TuRutinaSection(), // placeholder
PlantillasSection(),
HistorialSection(),
// ...
```

**After**:
```dart
// ...
const MiPlanSection(),
PlantillasSection(),
HistorialSection(),
// ...
```

**Behavior**: MiPlanSection replaces the placeholder and provides real athlete-assigned plan data.

---

## Invariants and Domain Rules

1. **Multi-plan latest-first**: Plans are always sorted by `createdAt DESC` via the data layer.
2. **Post-terminate visibility**: Plans persist after link termination with a "Plan finalizado" badge.
3. **Trainer-only visibility of own plans**: AthleteDetailScreen filters plans by current trainer's UID.
4. **No plan editing in MVP**: Submit creates; edit/delete deferred to Etapa 7.
5. **No cross-trainer visibility**: A trainer never sees plans created by other trainers for the same athlete.
6. **CoachStrings for all copy**: No inline string literals in widget `build` methods.

---

## Out of Scope (Deferred)

- Athlete session history in `AthleteDetailScreen` (requires `sharedWithTrainer` field in TrainerLink) → Etapa 6
- Editing/deleting assigned plans → Etapa 7
- Plan templates / cloning, plan duration tracking → out of MVP scope
- Server-side validation of days/slots structure → deferred
- Cross-collection role lookup in rules → deferred (performance tradeoff)

---

## Test Coverage

| Component | Scenarios | Fixture Type |
|-----------|-----------|--------------|
| `MiPlanSection` | SCENARIO-444..451 (8 cases) | Widget |
| `_AssignedByChip` | SCENARIO-452, 453 (2 cases) | Widget |
| `_ActiveAlumnoCard` tap | SCENARIO-454 (1 case) | Widget |
| `AthleteDetailScreen` | SCENARIO-455, 456 (2 cases) | Widget |
| `RoutineEditorScreen` | SCENARIO-457..463 (7 cases) | Widget |
| Router routes | SCENARIO-464 (MISSING — no dedicated test) | Integration |

---

## Quality Gates

| Gate | Result |
|------|--------|
| `flutter analyze` | ✅ 0 issues |
| `dart format` | ✅ clean |
| `flutter test` | ✅ 600+ passed (UI tests for this layer) |

---

## Related Artifacts

| Artifact | Path / Topic Key | Purpose |
|----------|------------------|---------|
| Proposal | sdd/coach-plans-mobile/proposal | Original intent and scope |
| Spec | sdd/coach-plans-mobile/spec | All 30 REQ + SCENARIO-432..465 |
| Design | sdd/coach-plans-mobile/design | Technical decisions (StatefulWidget local state, route design, chip patterns) |
| Tasks | sdd/coach-plans-mobile/tasks | 17 tasks for this layer (T11..T27) |
| Apply Progress | sdd/coach-plans-mobile/apply-progress | TDD evidence (RED/GREEN cycles) |
| Archive Report | sdd/coach-plans-mobile/archive-report | Cycle summary, follow-ups |

---

**Specification maintained by**: Dev A
**Last updated**: 2026-05-21
**Status**: ARCHIVED (PR #70 and #71 merged, UI layer complete)

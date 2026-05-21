# Spec: Coach Plans Mobile (Fase 5 · Etapa 4)

**Change**: `coach-plans-mobile`
**REQ namespace**: `REQ-COACH-PLANS-NNN`
**SCENARIO start**: 432
**SCENARIO end**: 462
**Capabilities touched**:
- NEW `coach-plans-mobile-data`
- NEW `coach-plans-mobile-ui`
- ANNOTATED `workout-data` (additive repo extension — no breaking change)

---

## New Capability: `coach-plans-mobile-data`

### Purpose

Extend `RoutineRepository` with two coach-aware methods — `listAssignedTo` and `createAssigned` —
that allow a trainer to persist plans and an athlete to query plans assigned to them. A Riverpod
`FutureProvider.autoDispose.family` wraps the query for UI consumption. Firestore rules are
extended to allow plan creation by trainers; a composite index is declared proactively to avoid
a silent `failed-precondition` at runtime.

---

## Requirements — `coach-plans-mobile-data`

| ID | Name | Strength |
|----|------|----------|
| REQ-COACH-PLANS-001 | `RoutineRepository.listAssignedTo` query contract | MUST |
| REQ-COACH-PLANS-002 | `RoutineRepository.createAssigned` persistence contract | MUST |
| REQ-COACH-PLANS-003 | `assignedRoutinesProvider` — success path | MUST |
| REQ-COACH-PLANS-004 | `assignedRoutinesProvider` — error propagation | MUST |
| REQ-COACH-PLANS-005 | Firestore rule — trainer can create an assigned plan | MUST |
| REQ-COACH-PLANS-006 | Firestore rule — `assignedBy` mismatch is denied | MUST |
| REQ-COACH-PLANS-007 | Firestore rule — `visibility: public` is denied on create | MUST |
| REQ-COACH-PLANS-008 | Firestore rule — wrong `source` is denied on create | MUST |
| REQ-COACH-PLANS-009 | Firestore rule — anonymous create is denied | MUST |
| REQ-COACH-PLANS-010 | Firestore rule — existing read rules remain valid | MUST |
| REQ-COACH-PLANS-011 | Composite index `assignedTo + source + createdAt` declared | MUST |

---

## REQ-COACH-PLANS-001 — `RoutineRepository.listAssignedTo` query contract

`RoutineRepository` MUST expose:

```
Future<List<Routine>> listAssignedTo(String athleteId)
```

The method MUST query the `routines` collection with:
- `where('assignedTo', isEqualTo: athleteId)`
- `where('source', isEqualTo: 'trainer-assigned')`
- `orderBy('createdAt', descending: true)`

The returned list MUST contain only documents satisfying both filters, sorted newest-first.
`listAll()` MUST remain unchanged and continue to return unfiltered results.

#### SCENARIO-432: `listAssignedTo` returns only plans assigned to the given athlete, newest first

- GIVEN the `routines` collection contains:
  plan A with `assignedTo: 'athlete-1'`, `source: 'trainer-assigned'`, `createdAt: T1`
  plan B with `assignedTo: 'athlete-1'`, `source: 'trainer-assigned'`, `createdAt: T2` (T2 > T1)
  plan C with `assignedTo: 'athlete-2'`, `source: 'trainer-assigned'`, `createdAt: T3`
  plan D with `assignedTo: 'athlete-1'`, `source: 'system'`, `createdAt: T4`
- WHEN `listAssignedTo('athlete-1')` is called
- THEN the result contains plan B and plan A (in that order)
- AND plan C is NOT in the result
- AND plan D is NOT in the result

#### SCENARIO-433: `listAssignedTo` returns empty list when athlete has no assigned plans

- GIVEN no document in `routines` has `assignedTo: 'athlete-99'`
- WHEN `listAssignedTo('athlete-99')` is called
- THEN the result is an empty list
- AND no exception is thrown

---

## REQ-COACH-PLANS-002 — `RoutineRepository.createAssigned` persistence contract

`RoutineRepository` MUST expose:

```
Future<Routine> createAssigned(Routine routine)
```

The method MUST write the routine to the `routines` collection using a Firestore-generated document
ID (`.add()` pattern or `.doc().set()`). The returned `Routine` MUST have its `id` field populated
with the generated document ID. The caller is responsible for setting `source`, `assignedBy`,
`assignedTo`, and `visibility` before calling this method — the method MUST NOT override them.

#### SCENARIO-434: `createAssigned` writes the routine and returns it with a populated id

- GIVEN a `Routine` with `source: trainerAssigned`, `assignedBy: 'trainer-1'`,
  `assignedTo: 'athlete-1'`, `visibility: private`, `name: 'Plan Fuerza'`, and at least one day
- WHEN `createAssigned(routine)` is called
- THEN the routine is persisted in Firestore
- AND the returned `Routine` has `id` set to a non-empty string matching the Firestore document ID
- AND the stored document fields match the input routine

#### SCENARIO-435: `createAssigned` does not modify `source`, `assignedBy`, or `assignedTo`

- GIVEN a `Routine` with `source: trainerAssigned`, `assignedBy: 'trainer-1'`, `assignedTo: 'athlete-1'`
- WHEN `createAssigned(routine)` is called
- THEN the stored document has `source == 'trainer-assigned'`, `assignedBy == 'trainer-1'`, `assignedTo == 'athlete-1'`
- AND those fields are NOT altered by the repository method

---

## REQ-COACH-PLANS-003 — `assignedRoutinesProvider` — success path

A `FutureProvider.autoDispose.family<List<Routine>, String>` named `assignedRoutinesProvider`
MUST exist at `lib/features/workout/application/assigned_routine_providers.dart`.

The provider MUST call `RoutineRepository.listAssignedTo(athleteId)` and expose its result as
`AsyncData<List<Routine>>`. When the repository returns an empty list the provider MUST resolve
to `AsyncData([])` (not an error state).

#### SCENARIO-436: `assignedRoutinesProvider` resolves to the repository result

- GIVEN `RoutineRepository.listAssignedTo('athlete-1')` returns `[planB, planA]`
- WHEN `assignedRoutinesProvider('athlete-1')` is read inside a `ProviderContainer`
- THEN the provider state is `AsyncData([planB, planA])`

---

## REQ-COACH-PLANS-004 — `assignedRoutinesProvider` — error propagation

When `RoutineRepository.listAssignedTo` throws, `assignedRoutinesProvider` MUST surface the error
as `AsyncError`. The error MUST NOT be swallowed or converted to an empty list.

#### SCENARIO-437: `assignedRoutinesProvider` exposes `AsyncError` when the repository throws

- GIVEN `RoutineRepository.listAssignedTo('athlete-1')` throws a `FirebaseException`
- WHEN `assignedRoutinesProvider('athlete-1')` is read
- THEN the provider state is `AsyncError` containing the original exception

---

## REQ-COACH-PLANS-005 — Firestore rule — trainer can create an assigned plan

The `routines/{routineId}` Firestore rule MUST allow `create` when ALL of the following hold:
- `request.auth != null`
- `request.resource.data.assignedBy == request.auth.uid`
- `request.resource.data.source == 'trainer-assigned'`
- `request.resource.data.visibility` is `'private'` OR `'shared'`

#### SCENARIO-438: authenticated trainer creates a plan with correct fields — allowed

- GIVEN a Firestore emulator with production rules applied
- AND user `trainer-1` is authenticated
- WHEN `trainer-1` creates a `routines` document with `assignedBy: 'trainer-1'`, `source: 'trainer-assigned'`, `visibility: 'private'`
- THEN the create is permitted

---

## REQ-COACH-PLANS-006 — Firestore rule — `assignedBy` mismatch is denied

A create where `assignedBy` does not equal `request.auth.uid` MUST be denied, even if `source`
and `visibility` are valid.

#### SCENARIO-439: create with `assignedBy` pointing to another user — denied

- GIVEN user `athlete-1` is authenticated
- WHEN `athlete-1` attempts to create a document with `assignedBy: 'trainer-1'`, `source: 'trainer-assigned'`, `visibility: 'private'`
- THEN the create is denied with PERMISSION_DENIED

---

## REQ-COACH-PLANS-007 — Firestore rule — `visibility: public` is denied on create

A create with `visibility: 'public'` MUST be denied regardless of `assignedBy` and `source` values.

#### SCENARIO-440: create with `visibility: public` — denied

- GIVEN user `trainer-1` is authenticated
- WHEN `trainer-1` creates a document with `assignedBy: 'trainer-1'`, `source: 'trainer-assigned'`, `visibility: 'public'`
- THEN the create is denied with PERMISSION_DENIED

---

## REQ-COACH-PLANS-008 — Firestore rule — wrong `source` is denied on create

A create with `source` other than `'trainer-assigned'` MUST be denied.

#### SCENARIO-441: create with `source: 'system'` — denied

- GIVEN user `trainer-1` is authenticated
- WHEN `trainer-1` creates a document with `assignedBy: 'trainer-1'`, `source: 'system'`, `visibility: 'private'`
- THEN the create is denied with PERMISSION_DENIED

---

## REQ-COACH-PLANS-009 — Firestore rule — anonymous create is denied

An unauthenticated create attempt on `routines/{routineId}` MUST be denied.

#### SCENARIO-442: anonymous create — denied

- GIVEN no authenticated user (no auth token)
- WHEN an unauthenticated client attempts to create a `routines` document
- THEN the create is denied with PERMISSION_DENIED

---

## REQ-COACH-PLANS-010 — Firestore rule — existing read rules remain valid

The `allow read` rules for `routines/{routineId}` introduced in prior etapas MUST remain intact
after this change. In particular, `request.auth.uid == resource.data.assignedTo` and
`request.auth.uid == resource.data.assignedBy` MUST continue to allow reads.

#### SCENARIO-443: `assignedTo` athlete can still read their assigned plan after rule change

- GIVEN a Firestore emulator with updated production rules applied
- AND a `routines` document with `visibility: 'private'` and `assignedTo: 'athlete-1'`
- WHEN `athlete-1` reads that document
- THEN the read is permitted

*(Mark `@Skip('requires Firestore emulator')` when emulator is unavailable in CI.)*

---

## REQ-COACH-PLANS-011 — Composite index `assignedTo + source + createdAt` declared

`firestore.indexes.json` MUST declare a composite index on the `routines` collection with fields:
`assignedTo` (ASCENDING), `source` (ASCENDING), `createdAt` (DESCENDING).

This index MUST be declared before the PR1 is merged to prevent a `failed-precondition` runtime
error when `listAssignedTo` is first called in production.

*(No runtime SCENARIO — validated by static inspection of `firestore.indexes.json` in CI.)*

---

## New Capability: `coach-plans-mobile-ui`

### Purpose

Close the trainer-to-athlete plan delivery cycle at the UI layer. The trainer gains `AthleteDetailScreen`
(accessible from `_ActiveAlumnoCard` tap) and `RoutineEditorScreen` (full-screen plan builder).
The athlete gains `MiPlanSection` replacing the `_TuRutinaSection` placeholder in `WorkoutScreen`.
`RoutineDetailScreen` gains a conditional "Asignado por <PF>" chip. Two new router entries connect
the flows. All visible copy is centralized in `CoachStrings`.

---

## Requirements — `coach-plans-mobile-ui`

| ID | Name | Strength |
|----|------|----------|
| REQ-COACH-PLANS-012 | `MiPlanSection` replaces `_TuRutinaSection` in `WorkoutScreen` | MUST |
| REQ-COACH-PLANS-013 | `MiPlanSection` loading state | MUST |
| REQ-COACH-PLANS-014 | `MiPlanSection` error state | MUST |
| REQ-COACH-PLANS-015 | `MiPlanSection` empty state | MUST |
| REQ-COACH-PLANS-016 | `MiPlanSection` single-plan data state | MUST |
| REQ-COACH-PLANS-017 | `MiPlanSection` multi-plan data state | MUST |
| REQ-COACH-PLANS-018 | `MiPlanSection` "Plan finalizado" badge when link terminated | MUST |
| REQ-COACH-PLANS-019 | `RoutineDetailScreen` chip "Asignado por <PF>" when `trainerAssigned` | MUST |
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

---

## REQ-COACH-PLANS-012 — `MiPlanSection` replaces `_TuRutinaSection` in `WorkoutScreen`

`WorkoutScreen` MUST render `MiPlanSection` in the position previously occupied by
`_TuRutinaSection`. `MiPlanSection` MUST appear above `PlantillasSection`. The private widget
`_TuRutinaSection` MUST be removed from `workout_screen.dart`.

`MiPlanSection` MUST be a `ConsumerWidget` that watches `assignedRoutinesProvider(currentUid)`.

*(Structural requirement — validated by widget tree assertion in SCENARIO-444.)*

---

## REQ-COACH-PLANS-013 — `MiPlanSection` loading state

While `assignedRoutinesProvider` is in `AsyncLoading`, `MiPlanSection` MUST display a loading
indicator. No plan cards MUST be rendered during loading.

#### SCENARIO-444: `MiPlanSection` shows loader while provider resolves

- GIVEN `assignedRoutinesProvider` is in `AsyncLoading`
- WHEN `MiPlanSection` renders inside a `ProviderScope`
- THEN a loading indicator widget is visible
- AND no plan card widgets are in the widget tree

---

## REQ-COACH-PLANS-014 — `MiPlanSection` error state

When `assignedRoutinesProvider` resolves to `AsyncError`, `MiPlanSection` MUST display an error
message. No plan cards MUST be shown.

#### SCENARIO-445: `MiPlanSection` shows error message on provider failure

- GIVEN `assignedRoutinesProvider` resolves to `AsyncError`
- WHEN `MiPlanSection` renders
- THEN an error message text is visible
- AND no plan card widgets are rendered

---

## REQ-COACH-PLANS-015 — `MiPlanSection` empty state

When `assignedRoutinesProvider` resolves to an empty list, `MiPlanSection` MUST display the
text "No tenés rutina asignada todavía." No plan cards MUST be rendered.

#### SCENARIO-446: `MiPlanSection` shows empty state text when no plans assigned

- GIVEN `assignedRoutinesProvider('uid-1')` resolves to `[]`
- WHEN `MiPlanSection` renders
- THEN the text "No tenés rutina asignada todavía." is visible
- AND no plan card widgets are present in the widget tree

---

## REQ-COACH-PLANS-016 — `MiPlanSection` single-plan data state

When `assignedRoutinesProvider` resolves to a list with exactly one plan, `MiPlanSection` MUST
render one plan card showing:
1. The routine name.
2. The trainer display name (sourced from `userPublicProfileProvider(plan.assignedBy!)`).

Tapping the card MUST navigate to `/workout/routine/:routineId`.

#### SCENARIO-447: `MiPlanSection` renders single plan card with trainer name

- GIVEN `assignedRoutinesProvider` resolves to `[planA]` where `planA.name: 'Plan Fuerza'` and `planA.assignedBy: 'trainer-1'`
- AND `userPublicProfileProvider('trainer-1')` resolves to a profile with `displayName: 'Lucas Pérez'`
- WHEN `MiPlanSection` renders
- THEN one plan card is visible
- AND the text 'Plan Fuerza' is visible
- AND the text 'Lucas Pérez' is visible

#### SCENARIO-448: tapping a plan card navigates to `RoutineDetailScreen`

- GIVEN `MiPlanSection` shows a card for `planA` with `id: 'routine-42'`
- WHEN the user taps that card
- THEN the router navigates to `/workout/routine/routine-42`

---

## REQ-COACH-PLANS-017 — `MiPlanSection` multi-plan data state

When `assignedRoutinesProvider` resolves to a list with N > 1 plans, `MiPlanSection` MUST render
N plan cards in the order returned by the provider (newest first — ordering guaranteed by
`listAssignedTo`). Each card MUST have the same fields as the single-plan case.

#### SCENARIO-449: `MiPlanSection` renders all plans newest-first when multiple plans exist

- GIVEN `assignedRoutinesProvider` resolves to `[planNew, planOld]` (newest first)
- WHEN `MiPlanSection` renders
- THEN exactly 2 plan cards are visible
- AND the card for `planNew` appears before the card for `planOld`

---

## REQ-COACH-PLANS-018 — `MiPlanSection` "Plan finalizado" badge when link terminated

When a plan's `assignedBy` trainer has a `TrainerLink` with `status == terminated` for the current
athlete, `MiPlanSection` MUST render a "Plan finalizado" badge on that plan's card. The plan MUST
remain visible and tappable — it is NOT hidden or removed.

#### SCENARIO-450: "Plan finalizado" badge appears when trainer link is terminated

- GIVEN `assignedRoutinesProvider` resolves to `[planA]` with `planA.assignedBy: 'trainer-1'`
- AND `currentAthleteLinkProvider` returns a `TrainerLink` with `trainerId: 'trainer-1'` and `status: terminated`
- WHEN `MiPlanSection` renders
- THEN the badge text "Plan finalizado" is visible on the plan card
- AND the card remains tappable

#### SCENARIO-451: no badge when trainer link is active

- GIVEN `planA.assignedBy: 'trainer-1'` and the link has `status: active`
- WHEN `MiPlanSection` renders
- THEN no "Plan finalizado" badge is visible

---

## REQ-COACH-PLANS-019 — `RoutineDetailScreen` chip "Asignado por <PF>" when `trainerAssigned`

When `RoutineDetailScreen` renders a routine with `source == RoutineSource.trainerAssigned`,
it MUST display a chip containing the text "Asignado por <displayName>" where `<displayName>` is
retrieved from `userPublicProfileProvider(routine.assignedBy!)`. The chip MUST be rendered in the
hero area alongside the existing day chip badge. When `source != trainerAssigned`, NO such chip
MUST be rendered.

#### SCENARIO-452: chip renders for trainer-assigned routine

- GIVEN `routineByIdProvider('r-1')` resolves to a `Routine` with `source: trainerAssigned`, `assignedBy: 'trainer-1'`
- AND `userPublicProfileProvider('trainer-1')` resolves to a profile with `displayName: 'Lucas Pérez'`
- WHEN `RoutineDetailScreen` renders for route `/workout/routine/r-1`
- THEN a chip containing the text 'Asignado por Lucas Pérez' is visible

#### SCENARIO-453: chip is absent for non-assigned routine

- GIVEN a `Routine` with `source: system`
- WHEN `RoutineDetailScreen` renders
- THEN no chip containing 'Asignado por' is present in the widget tree

---

## REQ-COACH-PLANS-020 — `_ActiveAlumnoCard` tap navigates to `AthleteDetailScreen`

`_ActiveAlumnoCard` in `TrainerCoachView` MUST be tappable. Tapping it MUST call
`context.push('/coach/athlete/${link.athleteId}')`. The "TERMINAR VÍNCULO" button MUST remain
functional (its tap handler MUST NOT be affected).

#### SCENARIO-454: tapping `_ActiveAlumnoCard` pushes the athlete detail route

- GIVEN `TrainerCoachView` renders an active alumno card with `athleteId: 'athlete-5'`
- WHEN the user taps the card body (not the terminate button)
- THEN the router pushes `/coach/athlete/athlete-5`

---

## REQ-COACH-PLANS-021 — `AthleteDetailScreen` renders athlete header and trainer's plans

`AthleteDetailScreen` MUST render:
1. An athlete header (reusing `_UserHeader`) showing the athlete's display info.
2. A list of `Routine` cards filtered to plans where `assignedBy == currentTrainerUid`, sourced
   via `assignedRoutinesProvider(athleteId)` with client-side filter.
3. A "CREAR PLAN" button (always visible, even when the list is empty).

The screen MUST be accessible via `/coach/athlete/:athleteId`.

#### SCENARIO-455: `AthleteDetailScreen` renders header and empty plans list with CTA

- GIVEN `assignedRoutinesProvider('athlete-5')` resolves to `[]`
- AND the current trainer uid is `'trainer-1'`
- WHEN `AthleteDetailScreen` renders for `athleteId: 'athlete-5'`
- THEN the athlete header is visible
- AND a "CREAR PLAN" button is visible
- AND no plan cards are rendered

---

## REQ-COACH-PLANS-022 — `AthleteDetailScreen` "CREAR PLAN" navigates to `RoutineEditorScreen`

Tapping "CREAR PLAN" in `AthleteDetailScreen` MUST navigate to
`/workout/routine-editor/${athleteId}`.

#### SCENARIO-456: tapping "CREAR PLAN" pushes the routine editor route

- GIVEN `AthleteDetailScreen` renders for `athleteId: 'athlete-5'`
- WHEN the user taps "CREAR PLAN"
- THEN the router pushes `/workout/routine-editor/athlete-5`

---

## REQ-COACH-PLANS-023 — `RoutineEditorScreen` renders metadata section and days list

`RoutineEditorScreen` MUST render a single-scroll form containing:
1. A name `TextField`.
2. A split `TextField`.
3. A days-per-week field accepting values 1–7.
4. A level picker.
5. A list of day entries, each displayed as an `ExpansionTile` with slot rows inside.
6. An "Agregar día" control to add a new day entry.
7. A submit button at the bottom.

#### SCENARIO-457: `RoutineEditorScreen` renders all form sections on load

- GIVEN `RoutineEditorScreen` is rendered for `athleteId: 'athlete-5'`
- WHEN the screen renders
- THEN a name TextField is visible
- AND a split TextField is visible
- AND a submit button is visible
- AND an "Agregar día" control is visible

---

## REQ-COACH-PLANS-024 — `RoutineEditorScreen` exercise picker bottom sheet

Tapping a slot's exercise selector MUST open a `showModalBottomSheet` containing:
1. A search `TextField`.
2. A `ListView` of exercises from `exercisesProvider`.

Typing in the search field MUST filter the visible exercise list in memory. Tapping an exercise
MUST assign it to the slot with `exerciseName` and `muscleGroup` denormalized from the selected
`Exercise` document. The bottom sheet MUST dismiss after selection.

#### SCENARIO-458: exercise picker bottom sheet appears and filters on search

- GIVEN `RoutineEditorScreen` has at least one day with one slot
- AND `exercisesProvider` resolves to a list containing "Press Banca" (muscleGroup: pecho) and "Sentadilla" (muscleGroup: piernas)
- WHEN the user taps the exercise selector for that slot
- THEN a bottom sheet is visible containing a search TextField and both exercises
- WHEN the user types "Press" in the search field
- THEN only "Press Banca" is visible in the list
- AND "Sentadilla" is NOT visible

#### SCENARIO-459: selecting an exercise from the picker assigns it to the slot

- GIVEN the exercise picker bottom sheet is open for a slot
- WHEN the user taps "Press Banca"
- THEN the bottom sheet is dismissed
- AND the slot now shows "Press Banca" as the selected exercise

---

## REQ-COACH-PLANS-025 — `RoutineEditorScreen` submit — success path

When the form has at least 1 day with at least 1 slot, pressing submit MUST:
1. Disable the submit button and show a loading spinner.
2. Call `RoutineRepository.createAssigned` with a `Routine` constructed from the form state,
   `source = trainerAssigned`, `assignedBy = currentUid`, `assignedTo = athleteId`, `visibility = private`.
3. On success, pop back to `AthleteDetailScreen` and show a `SnackBar` with
   "Plan creado y asignado."

#### SCENARIO-460: successful submit pops back and shows confirmation SnackBar

- GIVEN `RoutineEditorScreen` has a valid plan (1 day, 1 slot)
- AND `createAssigned` completes without error
- WHEN the user taps the submit button
- THEN the screen pops back to `AthleteDetailScreen`
- AND a SnackBar with text "Plan creado y asignado." is visible

---

## REQ-COACH-PLANS-026 — `RoutineEditorScreen` submit — validation error (empty form)

Pressing submit when there are zero days OR any day has zero slots MUST NOT call
`createAssigned`. The submit button MUST remain enabled after the validation rejection so the
user can correct and resubmit.

#### SCENARIO-461: submit with no days does not call `createAssigned`

- GIVEN `RoutineEditorScreen` has no days added (empty days list)
- WHEN the user taps the submit button
- THEN `createAssigned` is NOT called
- AND the user remains on `RoutineEditorScreen`

---

## REQ-COACH-PLANS-027 — `RoutineEditorScreen` submit — loading state

While `createAssigned` is in-flight, the submit button MUST be disabled and a loading indicator
MUST be visible. No duplicate submission MUST be possible during this window.

#### SCENARIO-462: submit button is disabled while creation is in progress

- GIVEN the user has tapped submit and `createAssigned` has not yet resolved
- WHEN the widget is in the loading state
- THEN the submit button widget is disabled (or has `onPressed: null`)
- AND a loading indicator is visible

---

## REQ-COACH-PLANS-028 — `RoutineEditorScreen` submit — network error

When `createAssigned` throws, `RoutineEditorScreen` MUST display a `SnackBar` with
"No pudimos crear el plan. Intentá de nuevo." The user MUST remain on `RoutineEditorScreen`
and the submit button MUST be re-enabled.

#### SCENARIO-463: network error on submit shows error SnackBar and re-enables submit

- GIVEN `RoutineEditorScreen` has a valid plan
- AND `createAssigned` throws a `FirebaseException`
- WHEN the user taps the submit button
- THEN a SnackBar with text "No pudimos crear el plan. Intentá de nuevo." is visible
- AND the user remains on `RoutineEditorScreen`
- AND the submit button is re-enabled

---

## REQ-COACH-PLANS-029 — Router — `/coach/athlete/:athleteId` registered

The GoRoute `/coach/athlete/:athleteId` MUST be registered as a sub-route under the `/coach`
ShellRoute. It MUST instantiate `AthleteDetailScreen(athleteId: state.pathParameters['athleteId']!)`.
The `TreinoBottomBar` MUST remain visible (ShellRoute shell persists).

*(No dedicated SCENARIO — validated by SCENARIO-454 tap navigation and SCENARIO-455 screen render.)*

---

## REQ-COACH-PLANS-030 — Router — `/workout/routine-editor/:athleteId` registered

The GoRoute `/workout/routine-editor/:athleteId` MUST be registered under the appropriate
ShellRoute branch. It MUST instantiate `RoutineEditorScreen(athleteId: state.pathParameters['athleteId']!)`.

#### SCENARIO-464: navigating to `/workout/routine-editor/athlete-5` renders `RoutineEditorScreen`

- GIVEN the router has the `/workout/routine-editor/:athleteId` route registered
- WHEN the router resolves `/workout/routine-editor/athlete-5`
- THEN `RoutineEditorScreen` is rendered with `athleteId: 'athlete-5'`

---

## Annotated Capability: `workout-data`

### Extension note

`RoutineRepository` is extended with two new public methods (`listAssignedTo`, `createAssigned`)
that operate on the existing `routines` Firestore collection. `listAll()` and `getById()` are
unchanged. A composite Firestore index is added to `firestore.indexes.json`. These changes are
additive — no existing behavior is removed or modified.

| ID | Name | Strength |
|----|------|----------|
| REQ-COACH-PLANS-001 | `listAssignedTo` query contract | (see above) |
| REQ-COACH-PLANS-002 | `createAssigned` persistence contract | (see above) |
| REQ-COACH-PLANS-011 | Composite index declared | (see above) |

---

## Domain Rules / Invariants

1. **Multi-plan latest-first ordering**: when a trainer creates a second plan for the same athlete,
   BOTH plans remain visible in `MiPlanSection`, ordered by `createdAt DESC`. No "active plan"
   field exists. The newest plan is always first. This is a deliberate MVP decision — no `status`
   or `archivedAt` field is introduced.

2. **`exerciseName` and `muscleGroup` denormalization at slot creation**: when the trainer selects
   an exercise in the editor, the slot MUST store `exerciseName` and `muscleGroup` copied from the
   `Exercise` document at selection time. These fields are NOT re-read from Firestore at plan
   display time. Denormalized values are immutable after creation.

3. **`visibility` default**: plans created via `RoutineEditorScreen` default to `private`. The
   rules block `public` on create. Design MAY expose a toggle for `shared` — the spec allows both
   `private` and `shared`; `public` is forbidden.

4. **No cross-collection role lookup in rules**: the Firestore `create` rule validates
   `assignedBy == request.auth.uid`, `source == 'trainer-assigned'`, and `visibility in ['private', 'shared']`
   only. Role validation (trainer vs. athlete) is enforced client-side by the `TrainerCoachView`
   role guard. This is a deliberate performance tradeoff documented in the proposal.

5. **Plan persists after link termination**: `createAssigned` documents are never deleted by this
   change. If the trainer-athlete link is terminated, the plan remains visible to the athlete with
   a "Plan finalizado" badge. `allow delete` in Firestore rules remains `if false`.

6. **`listAll()` is unaffected**: existing `routinesProvider` (plantillas públicas) continues to
   use `listAll()`. `assignedRoutinesProvider` is a separate provider on a separate query.
   There is no interaction between the two.

7. **`CoachStrings` centralization**: all user-visible copy introduced by this change MUST be
   defined as constants in `CoachStrings`. No inline string literals in widget `build` methods.

---

## Out of Scope (deferred)

| Deferred item | Target |
|---------------|--------|
| Athlete session history in `AthleteDetailScreen` | Etapa 6 (requires `sharedWithTrainer` in `TrainerLink`) |
| Editing or deleting assigned plans | Etapa 7 (Coach Hub — `allow update/delete` in rules) |
| `sharedWithTrainer` boolean in `TrainerLink` | Pre-req for Etapa 6; tech debt noted in proposal |
| Push / in-app notification when plan is assigned | Fase 6 (notifications infrastructure) |
| Plan templates / cloning | Out of MVP scope |
| Plan duration tracking (week-by-week progress) | Out of MVP scope |
| Server-side validation of `RoutineDay` / `RoutineSlot` structure in rules | Deferred — complex, fragile; client-side only |
| Cross-collection role lookup (`users/{uid}.role == 'trainer'`) in rules | Deferred — performance tradeoff documented in proposal |

---

*Generated by sdd-spec — 2026-05-21*

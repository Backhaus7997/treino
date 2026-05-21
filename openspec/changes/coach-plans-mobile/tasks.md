# Tasks: Coach Plans Mobile (Fase 5 · Etapa 4)

**Change**: `coach-plans-mobile`
**Strict TDD**: ACTIVE (`flutter test`)
**Delivery**: Chained PRs — `auto-chain`
**PR1 branch**: `feat/coach-plans-mobile-data` (base: `main`)
**PR2 branch**: `feat/coach-plans-mobile-ui` (base: `feat/coach-plans-mobile-data` after merge)

---

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines — PR1 | ~250-300 |
| Estimated changed lines — PR2 | ~350-450 |
| Estimated changed lines — total | ~600-750 |
| 400-line budget risk — PR1 | Low (within budget) |
| 400-line budget risk — PR2 | At-the-edge — monitor during apply; split candidate if LOC exceeds 420 |
| 400-line budget risk — single PR | High |
| Chained PRs recommended | Yes |
| Suggested split | PR1 (`feat/coach-plans-mobile-data`) → PR2 (`feat/coach-plans-mobile-ui`) |
| Delivery strategy | `auto-chain` |
| Chain strategy | `feature-branch-chain` |
| Decision needed before apply | No — `auto-chain` locked by orchestrator |

### PR2 split contingency

If PR2 exceeds 420 LOC during apply, split into:
- **PR2a**: `MiPlanSection` + `RoutineDetailScreen` chip + `workout_screen.dart` mod (athlete-side)
- **PR2b**: `AthleteDetailScreen` + `RoutineEditorScreen` + `trainer_coach_view.dart` tap + router (trainer-side)

Each sub-PR is independently testable. Base PR2b on PR2a.

### Suggested Work Units

| Unit | Goal | Branch | Base | Likely PR |
|------|------|--------|------|-----------|
| PR1 | Data: repo + provider + rules + index | `feat/coach-plans-mobile-data` | `main` | PR1 |
| PR2 | UI: all screens + widgets + router | `feat/coach-plans-mobile-ui` | `feat/coach-plans-mobile-data` (or `main` after merge) | PR2 |

---

## PR1: Coach Plans Mobile — Data Layer

> Branch `feat/coach-plans-mobile-data` from `main`. Self-contained; no UI consumer. Fully mergeable standalone.

---

### T01 [1] [CHORE] Branch creation from `main`

- **Files**: none (git only)
- **Description**: Checkout `feat/coach-plans-mobile-data` from `main`. Confirm `flutter test` baseline green. Create test directory mirrors if absent: `test/features/workout/data/` and `test/features/workout/application/`.
- **Acceptance**: `git branch` shows `feat/coach-plans-mobile-data`; `flutter test` exits 0.

---

### T02 [1] [RED] Unit tests — `RoutineRepository.listAssignedTo`

- **Files**: `test/features/workout/data/routine_repository_assigned_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-432, SCENARIO-433
- **REQs**: REQ-COACH-PLANS-001
- **Description**: Using `fake_cloud_firestore`. Write failing tests:
  1. `listAssignedTo('athlete-1')` with 4 seeded docs (plan A and B: `assignedTo: 'athlete-1'`, `source: 'trainer-assigned'`, createdAt T1/T2; plan C: `assignedTo: 'athlete-2'`, plan D: `assignedTo: 'athlete-1'`, `source: 'system'`) → returns [planB, planA] only, ordered newest-first — SCENARIO-432.
  2. `listAssignedTo('athlete-99')` with no matching docs → returns `[]` without throwing — SCENARIO-433.
  3. `listAll()` call still returns ALL seeded docs (regression guard — REQ-COACH-PLANS-001 last clause).
  4. `listAssignedTo` applies `limit(20)` — seed 21 docs for same athlete and assert result has exactly 20.
  Method `listAssignedTo` is undefined → tests fail with `Error`.
- **Acceptance**: `flutter test test/features/workout/data/routine_repository_assigned_test.dart` exits non-zero; 4 test cases declared.

---

### T03 [1] [GREEN] Implement `RoutineRepository.listAssignedTo`

- **Files**: `lib/features/workout/data/routine_repository.dart` (MODIFIED)
- **REQs**: REQ-COACH-PLANS-001
- **Description**: Add method:
  ```dart
  Future<List<Routine>> listAssignedTo(String athleteId) async {
    final snap = await _collection
        .where('assignedTo', isEqualTo: athleteId)
        .where('source', isEqualTo: 'trainer-assigned')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    return snap.docs.map(_fromDoc).whereType<Routine>().toList();
  }
  ```
  No changes to `listAll()`, `getById()`, or any existing method.
- **Acceptance**: All 4 tests in `routine_repository_assigned_test.dart` green; existing repo tests remain green.

---

### T04 [1] [RED] Unit tests — `RoutineRepository.createAssigned`

- **Files**: `test/features/workout/data/routine_repository_assigned_test.dart` (MODIFIED — add test group)
- **SCENARIOs**: SCENARIO-434, SCENARIO-435
- **REQs**: REQ-COACH-PLANS-002
- **Description**: Add failing tests:
  1. `createAssigned(routine)` where routine has `source: trainerAssigned`, `assignedBy: 'trainer-1'`, `assignedTo: 'athlete-1'`, `visibility: private`, `name: 'Plan Fuerza'`, id: '' → verifies doc is persisted in Firestore AND returned Routine has non-empty `id` matching the Firestore doc id — SCENARIO-434.
  2. Stored doc has `source == 'trainer-assigned'`, `assignedBy == 'trainer-1'`, `assignedTo == 'athlete-1'` unchanged — SCENARIO-435.
  3. CRITICAL: stored doc does NOT contain key `'id'` (json.remove('id') guard) — verify via `snap.data()!.containsKey('id') == false`.
  4. `createAssigned` does NOT mutate the input routine's `source`, `assignedBy`, or `assignedTo` fields.
  Method `createAssigned` is undefined → tests fail.
- **Acceptance**: New test group exits non-zero; 4 test cases declared.

---

### T05 [1] [GREEN] Implement `RoutineRepository.createAssigned`

- **Files**: `lib/features/workout/data/routine_repository.dart` (MODIFIED)
- **REQs**: REQ-COACH-PLANS-002
- **Description**: Add method:
  ```dart
  Future<Routine> createAssigned(Routine routine) async {
    final json = routine.toJson();
    json.remove('id');                        // CRITICAL: strip id before .add()
    json['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _collection.add(json);
    return routine.copyWith(id: ref.id);
  }
  ```
  CRITICAL invariants: (1) `json.remove('id')` MUST happen before `.add()` — Firestore generates the id; (2) `FieldValue.serverTimestamp()` MUST be injected at this layer because `Routine` model has no `createdAt` freezed field; (3) method returns `routine.copyWith(id: ref.id)` not a re-fetch.
- **Acceptance**: All 4 new tests in `routine_repository_assigned_test.dart` green; full test file remains green.

---

### T06 [1] [RED] Unit tests — `assignedRoutinesProvider`

- **Files**: `test/features/workout/application/assigned_routine_providers_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-436, SCENARIO-437
- **REQs**: REQ-COACH-PLANS-003, REQ-COACH-PLANS-004
- **Description**: Write failing tests using `ProviderContainer` with `routineRepositoryProvider` override:
  1. `assignedRoutinesProvider('athlete-1')` with repo returning `[planB, planA]` → state is `AsyncData([planB, planA])` — SCENARIO-436.
  2. `assignedRoutinesProvider('athlete-1')` with repo throwing `FirebaseException` → state is `AsyncError` containing the original exception — SCENARIO-437.
  3. Empty list: repo returns `[]` → state is `AsyncData([])` (not an error).
  4. Provider is `FutureProvider.autoDispose.family<List<Routine>, String>` — verify via type assertion.
  Provider file does not exist → tests fail with `Error`.
- **Acceptance**: `flutter test test/features/workout/application/assigned_routine_providers_test.dart` exits non-zero; 4 test cases declared.

---

### T07 [1] [GREEN] Create `assigned_routine_providers.dart`

- **Files**: `lib/features/workout/application/assigned_routine_providers.dart` (NEW)
- **REQs**: REQ-COACH-PLANS-003, REQ-COACH-PLANS-004
- **Description**: Create file with:
  ```dart
  final assignedRoutinesProvider =
      FutureProvider.autoDispose.family<List<Routine>, String>(
    (ref, athleteId) async {
      final repo = ref.watch(routineRepositoryProvider);
      return repo.listAssignedTo(athleteId);
    },
  );
  ```
  No other providers. No error swallowing — let exceptions propagate as `AsyncError`.
- **Acceptance**: All 4 tests in `assigned_routine_providers_test.dart` green.

---

### T08 [1] [MOD] `firestore.rules` — add `allow create` for assigned plans

- **Files**: `firestore.rules` (MODIFIED)
- **SCENARIOs**: SCENARIO-438, SCENARIO-439, SCENARIO-440, SCENARIO-441, SCENARIO-442, SCENARIO-443
- **REQs**: REQ-COACH-PLANS-005, REQ-COACH-PLANS-006, REQ-COACH-PLANS-007, REQ-COACH-PLANS-008, REQ-COACH-PLANS-009, REQ-COACH-PLANS-010
- **Description**: In the `match /routines/{routineId}` block, replace `allow write: if false` with:
  ```
  allow create: if request.auth != null
    && request.resource.data.assignedBy == request.auth.uid
    && request.resource.data.source == 'trainer-assigned'
    && request.resource.data.visibility in ['private', 'shared']
    && request.resource.data.assignedTo is string
    && request.resource.data.assignedTo.size() > 0;
  allow update, delete: if false;
  ```
  Existing `allow read` rules MUST remain intact. SCENARIO-443 (read after rule change) verified by the read rule still being present.
  Add emulator-skipped stubs in `scripts/rules_test/rules.test.js` for SCENARIO-438..443 per Decision #25 pattern established in Etapa 2.
- **Acceptance**: Rules block present in file with exact conditions; `allow read` unchanged; rules.test.js stubs compile and are skipped (not failing).

---

### T09 [1] [MOD] `firestore.indexes.json` — add composite index

- **Files**: `firestore.indexes.json` (MODIFIED)
- **REQs**: REQ-COACH-PLANS-011
- **Description**: Add composite index entry on collection `routines` with fields:
  - `assignedTo` ASCENDING
  - `source` ASCENDING
  - `createdAt` DESCENDING

  JSON entry follows the existing format in the file. CRITICAL: this index MUST land in PR1 (before the rule) to prevent `failed-precondition` runtime error when `listAssignedTo` is first called. Lesson from Fase 3 Etapa 3 (mi-gym bug).
- **Acceptance**: Entry present in `firestore.indexes.json`; `firebase deploy --only firestore:indexes` dry-run succeeds (manual check); no other indexes modified.

---

### T10 [1] [QA] PR1 quality gate

- **Files**: none (command-only)
- **Description**: Run `flutter analyze` (0 issues required), then `dart format .` (no unformatted files), then `flutter test` (full suite green including all new PR1 tests). BLOCKER — do not open PR1 until all three exit 0.
- **Acceptance**: All three commands exit 0.

---

## PR2: Coach Plans Mobile — UI Layer

> PR2 tasks MUST NOT begin until PR1 is merged into `main` and `feat/coach-plans-mobile-ui` is branched from `feat/coach-plans-mobile-data` (or rebased onto merged `main`).

---

### T11 [2] [CHORE] Branch from merged PR1

- **Files**: none
- **Description**: After PR1 merges to `main`: checkout `main`, pull, create `feat/coach-plans-mobile-ui` from `main`. Confirm `flutter test` baseline green (PR1 tests pass). Create directory `lib/features/coach/presentation/` if absent; create test mirrors `test/features/workout/presentation/widgets/`, `test/features/coach/presentation/`, `test/app/`.
- **Acceptance**: `git log --oneline -1` shows PR1 merge commit; `flutter test` green.

---

### T12 [2] [CHORE] Add plan-related strings to `CoachStrings`

- **Files**: `lib/features/coach/presentation/coach_strings.dart` (MODIFIED)
- **REQs**: REQ-COACH-PLANS-015, REQ-COACH-PLANS-018, REQ-COACH-PLANS-019, REQ-COACH-PLANS-025, REQ-COACH-PLANS-026, REQ-COACH-PLANS-028
- **Description**: Add string constants to the existing `CoachStrings` abstract class:
  ```
  miPlanTitle = 'MI PLAN'
  miPlanEmpty = 'No tenés rutina asignada todavía.'
  miPlanError = 'Error al cargar tu plan.'
  miPlanFinalizado = 'Plan finalizado'
  assignedByPrefix = 'Asignado por '
  assignedByLoading = 'Asignado por …'
  assignedByError = 'Asignado por un PF'
  createPlanCta = 'CREAR PLAN'
  createPlanSuccess = 'Plan creado y asignado.'
  createPlanError = 'No pudimos crear el plan. Intentá de nuevo.'
  athleteDetailNoPlans = 'Todavía no le asignaste planes.'
  editorTitle = 'Crear plan'
  editorNameLabel = 'NOMBRE'
  editorSplitLabel = 'SPLIT (e.g. PPL)'
  editorAddDay = 'Agregar día'
  editorAddSlot = 'Agregar ejercicio'
  editorSubmit = 'ASIGNAR PLAN'
  exercisePicker = 'Buscar ejercicio'
  ```
  No inline string literals in widget `build` methods — all copy from `CoachStrings`.
- **Acceptance**: File compiles; `flutter analyze` 0 issues.

---

### T13 [2] [RED] Widget tests — `MiPlanSection` (loading / error / empty / data states)

- **Files**: `test/features/workout/presentation/widgets/mi_plan_section_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-444, SCENARIO-445, SCENARIO-446, SCENARIO-447, SCENARIO-448, SCENARIO-449, SCENARIO-450, SCENARIO-451
- **REQs**: REQ-COACH-PLANS-013, REQ-COACH-PLANS-014, REQ-COACH-PLANS-015, REQ-COACH-PLANS-016, REQ-COACH-PLANS-017, REQ-COACH-PLANS-018
- **Description**: Define `_pumpMiPlanSection(WidgetTester, {required overrides})` helper using `ProviderScope`. Override `assignedRoutinesProvider(uid)`, `currentAthleteLinkProvider`, `authStateChangesProvider`, and `userPublicProfileProvider(trainerUid)` directly. Write failing tests:
  1. `AsyncLoading` → loading indicator visible, no plan card — SCENARIO-444.
  2. `AsyncError` → error text visible, no plan card — SCENARIO-445.
  3. `AsyncData([])` → text `'No tenés rutina asignada todavía.'` visible, no plan card — SCENARIO-446.
  4. `AsyncData([planA])` with `planA.name: 'Plan Fuerza'`, `assignedBy: 'trainer-1'`, trainer profile `displayName: 'Lucas Pérez'` → one card showing 'Plan Fuerza' and 'Lucas Pérez' — SCENARIO-447.
  5. Tapping card for `planA.id: 'routine-42'` → router navigates to `/workout/routine/routine-42` — SCENARIO-448.
  6. `AsyncData([planNew, planOld])` → exactly 2 cards, planNew before planOld — SCENARIO-449.
  7. `planA.assignedBy: 'trainer-1'` with `currentAthleteLinkProvider` returning link `{trainerId: 'trainer-1', status: terminated}` → badge text `'Plan finalizado'` visible on card, card remains tappable — SCENARIO-450.
  8. Same plan but link `status: active` → no badge text `'Plan finalizado'` — SCENARIO-451.
  Widget undefined → all tests fail with `Error`.
- **Acceptance**: `flutter test test/features/workout/presentation/widgets/mi_plan_section_test.dart` exits non-zero; 8 test cases declared.

---

### T14 [2] [GREEN] Implement `MiPlanSection`

- **Files**: `lib/features/workout/presentation/widgets/mi_plan_section.dart` (NEW)
- **REQs**: REQ-COACH-PLANS-012, REQ-COACH-PLANS-013, REQ-COACH-PLANS-014, REQ-COACH-PLANS-015, REQ-COACH-PLANS-016, REQ-COACH-PLANS-017, REQ-COACH-PLANS-018
- **Description**: Implement `MiPlanSection extends ConsumerWidget`. Key details:
  - Read `uid` from `authStateChangesProvider.valueOrNull?.uid`; return `SizedBox.shrink()` if null.
  - Watch `assignedRoutinesProvider(uid)` and `currentAthleteLinkProvider`.
  - States: `AsyncLoading` → spinner; `AsyncError` → error text + retry; `AsyncData(empty)` → empty text; `AsyncData(plans)` → `Column` of `_PlanCard` widgets.
  - Private `_PlanCard(ConsumerWidget)`: watches `userPublicProfileProvider(routine.assignedBy)` for trainer name; shows `_FinalizadoChip` when `_isLinkTerminated(linkAsync, routine)`; `InkWell.onTap` → `context.push('/workout/routine/${routine.id}')`.
  - Private `_isLinkTerminated`: `link?.status == LinkStatus.terminated && link.trainerId == routine.assignedBy`.
  - All copy from `CoachStrings`. Use `AppPalette.of(context)` — never HEX literals. Use `TreinoIcon.X` — never `PhosphorIcons.X` directly.
- **Acceptance**: All 8 tests in `mi_plan_section_test.dart` green.

---

### T15 [2] [RED] Widget tests — `RoutineDetailScreen` `_AssignedByChip`

- **Files**: `test/features/workout/presentation/routine_detail_screen_assigned_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-452, SCENARIO-453
- **REQs**: REQ-COACH-PLANS-019
- **Description**: Override `routineByIdProvider('r-1')` and `userPublicProfileProvider('trainer-1')`. Write failing tests:
  1. Routine with `source: trainerAssigned`, `assignedBy: 'trainer-1'`, profile `displayName: 'Lucas Pérez'` → chip with text `'Asignado por Lucas Pérez'` visible in widget tree — SCENARIO-452.
  2. Routine with `source: system` → no widget containing text `'Asignado por'` in tree — SCENARIO-453.
  Widget modification does not exist yet → tests fail.
- **Acceptance**: `flutter test test/features/workout/presentation/routine_detail_screen_assigned_test.dart` exits non-zero; 2 test cases declared.

---

### T16 [2] [GREEN] Add `_AssignedByChip` to `RoutineDetailScreen`

- **Files**: `lib/features/workout/presentation/routine_detail_screen.dart` (MODIFIED)
- **REQs**: REQ-COACH-PLANS-019
- **Description**: In `_RoutineDetailContent`'s `_HeroStrip`, add conditional chip below the existing `_DayChipBadge`:
  ```dart
  if (routine.source == RoutineSource.trainerAssigned && routine.assignedBy != null)
    _AssignedByChip(assignedBy: routine.assignedBy!)
  ```
  New private `_AssignedByChip(ConsumerWidget)`: watches `userPublicProfileProvider(assignedBy)`:
  - `AsyncLoading` → text `CoachStrings.assignedByLoading`
  - `AsyncError` → text `CoachStrings.assignedByError`
  - `AsyncData(profile)` → text `'${CoachStrings.assignedByPrefix}${profile.displayName}'`
  Chip style consistent with existing `_DayChipBadge`. No other changes to `RoutineDetailScreen`.
- **Acceptance**: Both tests in `routine_detail_screen_assigned_test.dart` green; existing `RoutineDetailScreen` tests remain green.

---

### T17 [2] [RED] Widget tests — `AthleteDetailScreen`

- **Files**: `test/features/coach/presentation/athlete_detail_screen_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-455, SCENARIO-456
- **REQs**: REQ-COACH-PLANS-020, REQ-COACH-PLANS-021, REQ-COACH-PLANS-022
- **Description**: Override `assignedRoutinesProvider('athlete-5')`, `userPublicProfileProvider('athlete-5')`, `authStateChangesProvider` (currentTrainerUid = 'trainer-1'). Write failing tests:
  1. `assignedRoutinesProvider` returns `[]`, trainer uid `'trainer-1'` → athlete header visible, `'CREAR PLAN'` button visible, no plan cards — SCENARIO-455.
  2. `assignedRoutinesProvider` returns `[planA, planB]` both with `assignedBy: 'trainer-1'` → 2 plan cards visible; `planC` with `assignedBy: 'trainer-2'` NOT rendered (client-side filter).
  3. Tapping `'CREAR PLAN'` button → router pushes `/workout/routine-editor/athlete-5` — SCENARIO-456.
  Screen undefined → tests fail.
- **Acceptance**: `flutter test test/features/coach/presentation/athlete_detail_screen_test.dart` exits non-zero; 3 test cases declared.

---

### T18 [2] [GREEN] Implement `AthleteDetailScreen`

- **Files**: `lib/features/coach/presentation/athlete_detail_screen.dart` (NEW)
- **REQs**: REQ-COACH-PLANS-021, REQ-COACH-PLANS-022
- **Description**: Implement `AthleteDetailScreen extends ConsumerWidget` with `required String athleteId`. Key details:
  - Read `currentTrainerUid` from `authStateChangesProvider.valueOrNull?.uid`.
  - Watch `userPublicProfileProvider(athleteId)` for header.
  - Watch `assignedRoutinesProvider(athleteId)` → client-side filter `where(r.assignedBy == currentTrainerUid)`.
  - Inline athlete header (`Row(avatar + Column(name + subtitle))`) — do NOT extract or reuse private `_UserHeader` from `trainer_coach_view.dart` (Decision #13: duplication acceptable).
  - Plans list: `AsyncLoading` → spinner; `AsyncError` → error text; `AsyncData(empty)` → `CoachStrings.athleteDetailNoPlans`; `AsyncData(plans)` → `ListView` of plan cards.
  - Fixed "CREAR PLAN" button: `onPressed: () => context.push('/workout/routine-editor/$athleteId')`.
  - NO Scaffold (lives inside ShellRoute). Use `Column` with custom `AppBar`-equivalent header or standard `Scaffold` with awareness of ShellRoute — follow the same pattern as `RoutineDetailScreen`. CRITICAL: test that bottom bar remains visible.
  - All copy from `CoachStrings`. Use `AppPalette.of(context)`, `TreinoIcon.X`.
- **Acceptance**: All 3 tests in `athlete_detail_screen_test.dart` green.

---

### T19 [2] [RED] Widget tests — `_ActiveAlumnoCard` tap navigation

- **Files**: `test/features/coach/trainer_coach_view_tap_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-454
- **REQs**: REQ-COACH-PLANS-020
- **Description**: Write failing test:
  1. `TrainerCoachView` (or isolated `_ActiveAlumnoCard`) with `athleteId: 'athlete-5'` → tap card body (not "TERMINAR VÍNCULO" button) → router pushes `/coach/athlete/athlete-5` — SCENARIO-454.
  2. "TERMINAR VÍNCULO" button tap still fires its own `onPressed` handler (regression guard).
  Tap not wired yet → test fails.
- **Acceptance**: `flutter test test/features/coach/trainer_coach_view_tap_test.dart` exits non-zero; 2 test cases declared.

---

### T20 [2] [GREEN] Make `_ActiveAlumnoCard` tappable in `trainer_coach_view.dart`

- **Files**: `lib/features/coach/trainer_coach_view.dart` (MODIFIED)
- **REQs**: REQ-COACH-PLANS-020
- **Description**: Wrap `_ActiveAlumnoCard` body in `InkWell(onTap: () => context.push('/coach/athlete/${link.athleteId}'))`. The `OutlinedButton` "TERMINAR VÍNCULO" internal to the card retains its own `onPressed` handler — Flutter propagates tap to the innermost `InkWell`/button first, so the outer `InkWell` only fires in zones without a child tap target. Do NOT use `GestureDetector.behavior: opaque` nor `StatefulBuilder`.
- **Acceptance**: Both tests in `trainer_coach_view_tap_test.dart` green; existing `trainer_coach_view` tests remain green.

---

### T21 [2] [RED] Widget tests — `RoutineEditorScreen` (render + exercise picker + submit flows)

- **Files**: `test/features/workout/presentation/routine_editor_screen_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-457, SCENARIO-458, SCENARIO-459, SCENARIO-460, SCENARIO-461, SCENARIO-462, SCENARIO-463
- **REQs**: REQ-COACH-PLANS-023, REQ-COACH-PLANS-024, REQ-COACH-PLANS-025, REQ-COACH-PLANS-026, REQ-COACH-PLANS-027, REQ-COACH-PLANS-028
- **Description**: Override `exercisesProvider`, `routineRepositoryProvider` (capture fake), `authStateChangesProvider` (trainerUid = 'trainer-1'). Write failing tests:
  1. Screen renders with name `TextField`, split `TextField`, submit button, `'Agregar día'` control — SCENARIO-457.
  2. With 1 day and 1 slot: tapping exercise selector opens bottom sheet with search `TextField` and exercise list; typing 'Press' filters to only 'Press Banca' — SCENARIO-458.
  3. Tapping 'Press Banca' in picker → sheet dismisses → slot shows 'Press Banca' — SCENARIO-459.
  4. Valid form (1 day, 1 slot, exercise set) + `createAssigned` completes successfully → screen pops + SnackBar text `'Plan creado y asignado.'` — SCENARIO-460.
  5. Zero days → tap submit → `createAssigned` NOT called, user remains on screen — SCENARIO-461.
  6. Submit in-flight → submit button is disabled (`onPressed == null`) + loading indicator visible — SCENARIO-462.
  7. `createAssigned` throws `FirebaseException` → SnackBar text `'No pudimos crear el plan. Intentá de nuevo.'` + user on screen + submit re-enabled — SCENARIO-463.
  Screen undefined → tests fail.
- **Acceptance**: `flutter test test/features/workout/presentation/routine_editor_screen_test.dart` exits non-zero; 7 test cases declared.

---

### T22 [2] [GREEN] Implement `RoutineEditorScreen`

- **Files**: `lib/features/workout/presentation/routine_editor_screen.dart` (NEW)
- **REQs**: REQ-COACH-PLANS-023, REQ-COACH-PLANS-024, REQ-COACH-PLANS-025, REQ-COACH-PLANS-026, REQ-COACH-PLANS-027, REQ-COACH-PLANS-028
- **Description**: Implement `RoutineEditorScreen extends StatefulWidget` with `required String athleteId` and `_RoutineEditorScreenState extends ConsumerState`. Key details:

  **State**:
  ```dart
  final _nameController = TextEditingController();
  final _splitController = TextEditingController();
  int _daysPerWeek = 3;
  ExperienceLevel _level = ExperienceLevel.beginner;
  final List<_EditableDay> _days = [];
  bool _submitting = false;
  ```

  **Local mutable classes** (file-private):
  - `_EditableDay`: `String name`, `List<_EditableSlot> slots`
  - `_EditableSlot`: `Exercise? exercise`, `int targetSets = 3`, `int repsMin = 8`, `int repsMax = 12`

  **`_canSubmit` getter**: `_nameController.text.isNotEmpty && _splitController.text.isNotEmpty && _days.isNotEmpty && _days.every((d) => d.slots.isNotEmpty && d.slots.every((s) => s.exercise != null && s.targetSets >= 1 && s.repsMin >= 1 && s.repsMax >= s.repsMin))`

  **`_pickExercise`**: `Future<Exercise?> _pickExercise(BuildContext ctx)` → `showModalBottomSheet<Exercise>(isScrollControlled: true, builder: (_) => _ExercisePickerSheet(ref: ref))`. `_ExercisePickerSheet` ConsumerStatefulWidget: watches `exercisesProvider`, `TextField` search → filters by `exercise.name.toLowerCase().contains(query)` or `exercise.muscleGroup.toLowerCase().contains(query)`, `ListView.builder` → tap → `Navigator.pop(context, exercise)`.

  **`_submit`**:
  ```dart
  if (!_canSubmit || _submitting) return;
  setState(() => _submitting = true);
  try {
    final routine = Routine(id: '', name: ..., source: RoutineSource.trainerAssigned,
                            assignedBy: currentUid, assignedTo: widget.athleteId,
                            visibility: RoutineVisibility.private, ...);
    await ref.read(routineRepositoryProvider).createAssigned(routine);
    ref.invalidate(assignedRoutinesProvider(widget.athleteId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(CoachStrings.createPlanSuccess)));
      context.pop();
    }
  } catch (_) {
    if (mounted) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(CoachStrings.createPlanError)));
    }
  }
  ```

  CRITICAL: NO `Scaffold` wrapping (lives inside ShellRoute shell — potential `_ShellScaffold` conflict). Use `Column` + custom `AppBar`-equivalent at top. Follow same pattern as other screens under `/workout` ShellRoute. Exercise picker uses `viewInsets.bottom` padding (`isScrollControlled: true`).
  All copy from `CoachStrings`. Use `AppPalette.of(context)`, `TreinoIcon.X`.
- **Acceptance**: All 7 tests in `routine_editor_screen_test.dart` green.

---

### T23 [2] [MOD] Replace `_TuRutinaSection` with `MiPlanSection` in `workout_screen.dart`

- **Files**: `lib/features/workout/workout_screen.dart` (MODIFIED)
- **REQs**: REQ-COACH-PLANS-012
- **Description**: (1) Remove the private `_TuRutinaSection` class entirely. (2) Add `import 'presentation/widgets/mi_plan_section.dart'`. (3) Replace the `_TuRutinaSection()` call with `MiPlanSection()`. (4) Reorder the three sections: `MiPlanSection` FIRST, `PlantillasSection` SECOND, `HistorialSection` THIRD. No other changes.
- **Acceptance**: `flutter test` on existing `workout_screen_test.dart` green after updating any assertion that referenced `_TuRutinaSection`; `find.byType(MiPlanSection)` found in tree above `PlantillasSection`.

---

### T24 [2] [MOD] Add 2 routes to `router.dart`

- **Files**: `lib/app/router.dart` (MODIFIED)
- **REQs**: REQ-COACH-PLANS-029, REQ-COACH-PLANS-030
- **Description**:
  1. Under `GoRoute(path: '/coach')` ShellRoute: add sub-route `GoRoute(path: 'athlete/:athleteId', pageBuilder: (context, state) => _noAnim(AthleteDetailScreen(athleteId: state.pathParameters['athleteId']!)))`.
  2. Under `GoRoute(path: '/workout')` ShellRoute branch: add sub-route `GoRoute(path: 'routine-editor/:athleteId', pageBuilder: (context, state) => _noAnim(RoutineEditorScreen(athleteId: state.pathParameters['athleteId']!)))`.
  Add imports for `AthleteDetailScreen` and `RoutineEditorScreen` in alphabetical order among their respective feature imports. Bottom bar MUST remain visible for both (ShellRoute shell persists).
- **Acceptance**: App compiles; `flutter analyze` 0 issues; no existing routes broken.

---

### T25 [2] [RED] Router tests — new routes resolve + bottom bar visible

- **Files**: `test/app/router_coach_plans_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-464 (and implicit REQ-COACH-PLANS-029 + REQ-COACH-PLANS-030)
- **REQs**: REQ-COACH-PLANS-029, REQ-COACH-PLANS-030
- **Description**: Write failing tests in `ProviderScope` wrapping the router, overriding providers with stubs:
  1. Navigate to `/coach/athlete/athlete-5` → `find.byType(AthleteDetailScreen)` visible + `find.byType(TreinoBottomBar)` visible (ShellRoute shell persists).
  2. Navigate to `/workout/routine-editor/athlete-5` → `find.byType(RoutineEditorScreen)` visible with `athleteId == 'athlete-5'` + `find.byType(TreinoBottomBar)` visible — SCENARIO-464.
  3. Path parameters extracted correctly: `AthleteDetailScreen.athleteId == 'athlete-5'`.
  Routes exist but test stubs for screens are missing → tests written as failing.
- **Acceptance**: `flutter test test/app/router_coach_plans_test.dart` exits non-zero; 3 test cases declared.

---

### T26 [2] [GREEN] Router tests pass

- **Files**: `test/app/router_coach_plans_test.dart` (confirm passing — T24 delivered the impl)
- **REQs**: REQ-COACH-PLANS-029, REQ-COACH-PLANS-030
- **Description**: With routes added in T24, confirm all 3 router tests pass. If any fail, fix the `router.dart` registration — no other files should need modification.
- **Acceptance**: `flutter test test/app/router_coach_plans_test.dart` all 3 green.

---

### T27 [2] [QA] PR2 quality gate

- **Files**: none (command-only)
- **Description**: Run `flutter analyze` (0 issues required), then `dart format .` (no unformatted files), then `flutter test` (full suite green including all PR1 + PR2 tests). BLOCKER — do not open PR2 until all three exit 0.
- **Acceptance**: All three commands exit 0.

---

## Goal-Backward Coverage

### REQ → SCENARIO → Task mapping

| REQ | Strength | SCENARIO(s) | RED task | GREEN task | Gap |
|-----|----------|-------------|----------|------------|-----|
| REQ-COACH-PLANS-001 | MUST | 432, 433 | T02 | T03 | None |
| REQ-COACH-PLANS-002 | MUST | 434, 435 | T04 | T05 | None |
| REQ-COACH-PLANS-003 | MUST | 436 | T06 | T07 | None |
| REQ-COACH-PLANS-004 | MUST | 437 | T06 | T07 | None |
| REQ-COACH-PLANS-005 | MUST | 438 | T08 (emulator) | T08 | Emulator-deferred (intentional per Decision #25) |
| REQ-COACH-PLANS-006 | MUST | 439 | T08 (emulator) | T08 | Emulator-deferred (intentional per Decision #25) |
| REQ-COACH-PLANS-007 | MUST | 440 | T08 (emulator) | T08 | Emulator-deferred (intentional per Decision #25) |
| REQ-COACH-PLANS-008 | MUST | 441 | T08 (emulator) | T08 | Emulator-deferred (intentional per Decision #25) |
| REQ-COACH-PLANS-009 | MUST | 442 | T08 (emulator) | T08 | Emulator-deferred (intentional per Decision #25) |
| REQ-COACH-PLANS-010 | MUST | 443 | T08 (structural) | T08 | None (read rule unchanged; verified statically) |
| REQ-COACH-PLANS-011 | MUST | (static — no runtime scenario) | T09 (static) | T09 | None |
| REQ-COACH-PLANS-012 | MUST | (structural — 444 tree) | T23 | T23 | None |
| REQ-COACH-PLANS-013 | MUST | 444 | T13 | T14 | None |
| REQ-COACH-PLANS-014 | MUST | 445 | T13 | T14 | None |
| REQ-COACH-PLANS-015 | MUST | 446 | T13 | T14 | None |
| REQ-COACH-PLANS-016 | MUST | 447, 448 | T13 | T14 | None |
| REQ-COACH-PLANS-017 | MUST | 449 | T13 | T14 | None |
| REQ-COACH-PLANS-018 | MUST | 450, 451 | T13 | T14 | None |
| REQ-COACH-PLANS-019 | MUST | 452, 453 | T15 | T16 | None |
| REQ-COACH-PLANS-020 | MUST | 454 | T19 | T20 | None |
| REQ-COACH-PLANS-021 | MUST | 455 | T17 | T18 | None |
| REQ-COACH-PLANS-022 | MUST | 456 | T17 | T18 | None |
| REQ-COACH-PLANS-023 | MUST | 457 | T21 | T22 | None |
| REQ-COACH-PLANS-024 | MUST | 458, 459 | T21 | T22 | None |
| REQ-COACH-PLANS-025 | MUST | 460 | T21 | T22 | None |
| REQ-COACH-PLANS-026 | MUST | 461 | T21 | T22 | None |
| REQ-COACH-PLANS-027 | MUST | 462 | T21 | T22 | None |
| REQ-COACH-PLANS-028 | MUST | 463 | T21 | T22 | None |
| REQ-COACH-PLANS-029 | MUST | (454 implicit + router test) | T25 | T24 + T26 | None |
| REQ-COACH-PLANS-030 | MUST | 464 | T25 | T24 + T26 | None |

### SCENARIO → Task mapping

| SCENARIO | Task(s) |
|----------|---------|
| 432 | T02 (RED), T03 (GREEN) |
| 433 | T02 (RED), T03 (GREEN) |
| 434 | T04 (RED), T05 (GREEN) |
| 435 | T04 (RED), T05 (GREEN) |
| 436 | T06 (RED), T07 (GREEN) |
| 437 | T06 (RED), T07 (GREEN) |
| 438 | T08 (emulator-skipped stub) |
| 439 | T08 (emulator-skipped stub) |
| 440 | T08 (emulator-skipped stub) |
| 441 | T08 (emulator-skipped stub) |
| 442 | T08 (emulator-skipped stub) |
| 443 | T08 (structural — read rule unchanged) |
| 444 | T13 (RED), T14 (GREEN) |
| 445 | T13 (RED), T14 (GREEN) |
| 446 | T13 (RED), T14 (GREEN) |
| 447 | T13 (RED), T14 (GREEN) |
| 448 | T13 (RED), T14 (GREEN) |
| 449 | T13 (RED), T14 (GREEN) |
| 450 | T13 (RED), T14 (GREEN) |
| 451 | T13 (RED), T14 (GREEN) |
| 452 | T15 (RED), T16 (GREEN) |
| 453 | T15 (RED), T16 (GREEN) |
| 454 | T19 (RED), T20 (GREEN) |
| 455 | T17 (RED), T18 (GREEN) |
| 456 | T17 (RED), T18 (GREEN) |
| 457 | T21 (RED), T22 (GREEN) |
| 458 | T21 (RED), T22 (GREEN) |
| 459 | T21 (RED), T22 (GREEN) |
| 460 | T21 (RED), T22 (GREEN) |
| 461 | T21 (RED), T22 (GREEN) |
| 462 | T21 (RED), T22 (GREEN) |
| 463 | T21 (RED), T22 (GREEN) |
| 464 | T25 (RED), T24 + T26 (GREEN) |

All SCENARIOs 432..464 land in specific tasks. No orphan SCENARIOs found.

**SCENARIO-438..443 (Firestore rules)**: covered by emulator-skipped stubs in `scripts/rules_test/rules.test.js` per Decision #25. This is intentional — emulator tests are the only reliable way to validate rules. Stubs compile and are skipped (not failing) in `flutter test`.

---

## Task Summary

| Section | Tasks | Focus |
|---------|-------|-------|
| PR1 — CHORE | T01 | Branch + dirs |
| PR1 — RED/GREEN (listAssignedTo) | T02–T03 | Repo query test cycle |
| PR1 — RED/GREEN (createAssigned) | T04–T05 | Repo create test cycle |
| PR1 — RED/GREEN (provider) | T06–T07 | `assignedRoutinesProvider` test cycle |
| PR1 — MOD (rules) | T08 | `firestore.rules` allow create + emulator stubs |
| PR1 — MOD (index) | T09 | `firestore.indexes.json` composite index |
| PR1 — QA | T10 | analyze + format + full suite |
| **PR1 total** | **10** | |
| PR2 — CHORE | T11–T12 | Branch + `CoachStrings` additions |
| PR2 — RED/GREEN (MiPlanSection) | T13–T14 | Widget test cycle (8 scenarios) |
| PR2 — RED/GREEN (chip RoutineDetail) | T15–T16 | Widget test cycle (2 scenarios) |
| PR2 — RED/GREEN (AthleteDetailScreen) | T17–T18 | Screen test cycle (3 scenarios) |
| PR2 — RED/GREEN (AlumnoCard tap) | T19–T20 | Tap test cycle (1 scenario) |
| PR2 — RED/GREEN (RoutineEditorScreen) | T21–T22 | Screen test cycle (7 scenarios, incl. picker + submit) |
| PR2 — MOD (WorkoutScreen replace) | T23 | Replace `_TuRutinaSection` |
| PR2 — MOD (router) | T24 | 2 new routes |
| PR2 — RED/GREEN (router tests) | T25–T26 | Router test cycle (3 scenarios) |
| PR2 — QA | T27 | analyze + format + full suite |
| **PR2 total** | **17** | |
| **Grand total** | **27** | |

Execution order within each PR is strictly sequential. Each RED MUST be observed failing before its GREEN. Each GREEN MUST be confirmed passing before the next RED.

---

## Dependency Notes

- PR2 tasks are BLOCKED until PR1 is merged to `main` and `feat/coach-plans-mobile-ui` is branched.
- Within PR1: T02→T03→T04→T05→T06→T07→T08→T09→T10 (sequential).
- Within PR2: T11→T12→T13→T14→T15→T16→T17→T18→T19→T20→T21→T22→T23→T24→T25→T26→T27 (sequential).
- T24 (router impl) MUST precede T25 (router RED) because T25 tests routes that T24 registers. Exception to the strict RED-before-GREEN TDD order: router RED tests are written in T25 AFTER the impl in T24 lands. If strict TDD ordering is required, write T25 as failing stubs BEFORE T24, then confirm passing after T24.
- T22 (`RoutineEditorScreen`) calls `ref.invalidate(assignedRoutinesProvider(athleteId))` on submit success — requires PR1's `assigned_routine_providers.dart` to be present (guaranteed by PR1 merge before PR2 branch).

---

*Generated by sdd-tasks — 2026-05-21*

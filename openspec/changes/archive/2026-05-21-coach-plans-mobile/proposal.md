# ARCHIVED: Proposal: Coach Plans Mobile

**Change**: `coach-plans-mobile`
**Fase / Etapa**: Fase 5 · Etapa 4
**Status**: ARCHIVED (2026-05-21)
**PRs Merged**: #64 (data), #70 (athlete UI), #71 (trainer UI + hotfix)

This is an archived artifact. The original proposal is below for historical reference.

---

# Proposal: Coach Plans Mobile

**Change**: `coach-plans-mobile`
**Fase / Etapa**: Fase 5 · Etapa 4
**Branch (target)**: chained PRs — `feat/coach-plans-mobile-data` (PR1) + `feat/coach-plans-mobile-ui` (PR2)
**Owner**: Dev A (reasignable)
**Project**: treino
**Artifact store**: hybrid
**Strict TDD**: ACTIVE (`flutter test`)
**SCENARIO start**: 432
**REQ namespace**: `REQ-COACH-PLANS-NNN`

## Intent

Cerrar el ciclo "Personal Trainer crea un plan → Atleta lo ve y lo ejecuta" sobre la infra ya provista por Fase 5 Etapa 1 (campos `source`, `assignedBy`, `assignedTo`, `visibility` en `Routine`) y los vínculos confirmados de Etapa 3. El PF necesita una pantalla de detalle de alumno con CTA "CREAR PLAN" que despache a un editor full-screen para construir un `Routine` con días y slots; el atleta necesita una sección "MI PLAN" en `WorkoutScreen` que reemplace el placeholder `_TuRutinaSection` con la lista de planes asignados (multi-plan latest-first). Además, `RoutineDetailScreen` agrega un chip condicional "Asignado por <PF>" cuando `source == trainerAssigned`. La data layer extiende `RoutineRepository` con `listAssignedTo` + `createAssigned`, abre `allow create` en `firestore.rules` para PFs autenticados con validación `assignedBy == request.auth.uid`, e introduce un composite index proactivo. No se introduce campo `status` en `Routine` — la semántica de "plan activo" se resuelve ordenando por `createdAt DESC`.

## Scope

### In Scope

**PR1 — Data layer (`feat/coach-plans-mobile-data`)**:
- `RoutineRepository.listAssignedTo(String athleteId)`: query `where('assignedTo', isEqualTo, uid).where('source', isEqualTo, 'trainer-assigned').orderBy('createdAt', descending: true)`.
- `RoutineRepository.createAssigned(Routine routine)`: persiste un nuevo plan via `_collection.doc().set(routine.toJson())`.
- `firestore.rules`: abrir `allow create` en `routines/{routineId}` con validación de `assignedBy == request.auth.uid`, `source == 'trainer-assigned'`, `visibility in ['private', 'shared']`. NO se hace cross-collection lookup del rol.
- `firestore.indexes.json`: composite index `assignedTo (ASC) + source (ASC) + createdAt (DESC)` para evitar `failed-precondition` silencioso en runtime.
- `lib/features/workout/application/assigned_routine_providers.dart`: nuevo `assignedRoutinesProvider(athleteId)` como `FutureProvider.autoDispose.family<List<Routine>, String>`.
- Tests SCENARIO-432..~445 (data + rules + provider).

**PR2 — UI consumers (`feat/coach-plans-mobile-ui`)**:
- `lib/features/workout/presentation/widgets/mi_plan_section.dart`: `MiPlanSection` ConsumerWidget que reemplaza `_TuRutinaSection` en `WorkoutScreen`. Watch `assignedRoutinesProvider(currentUid)`. Estados: loading skeleton, empty ("No tenés rutina asignada todavía."), populated (lista de `RoutineCard` ordenada latest-first). Si el `TrainerLink` del `assignedBy` está terminated, se renderiza un chip "Plan finalizado" sobre la card del plan.
- `lib/features/workout/presentation/routine_editor_screen.dart`: pantalla full-screen single-scroll form. Header con metadata (name, split, daysPerWeek, level). Lista de días editables via `ExpansionTile`. Slots por día con selector de ejercicio via `showModalBottomSheet` que muestra `exercisesProvider` con `TextField` de search inline. Submit valida y llama `RoutineRepository.createAssigned(...)` con `source = trainerAssigned`, `assignedBy = currentUid`, `assignedTo = athleteId`, `visibility = private`.
- `lib/features/coach/presentation/athlete_detail_screen.dart`: drill-down del PF accesible al tap de `_ActiveAlumnoCard` en `TrainerCoachView`. Muestra header del atleta (reusing `_UserHeader`), lista de planes asignados que él creó (filtrado adicional por `assignedBy == currentTrainerUid`) y CTA "CREAR PLAN" → `RoutineEditorScreen`.
- `RoutineDetailScreen` (modificación): chip "Asignado por <NombrePF>" condicional cuando `routine.source == RoutineSource.trainerAssigned`, leyendo el nombre del PF via `userPublicProfileProvider(routine.assignedBy!)`. Posición: junto al `_DayChipBadge` en `_HeroStrip`.
- `TrainerCoachView`: hacer `_ActiveAlumnoCard` tappable. Tap → `context.push('/coach/athlete/${alumno.athleteId}')`.
- `lib/app/router.dart`: rutas `/coach/athlete/:athleteId` (AthleteDetailScreen) y `/workout/routine-editor/:athleteId` (RoutineEditorScreen).
- Tests SCENARIO-~446..~465 (widgets + screens + router).

## Capabilities

### New Capabilities

- **`coach-plans-mobile-data`**: documenta `RoutineRepository.listAssignedTo` + `createAssigned`, el provider `assignedRoutinesProvider(athleteId)`, las Firestore rules `allow create` en `routines/{routineId}` y el composite index `assignedTo + source + createdAt`.
- **`coach-plans-mobile-ui`**: documenta `MiPlanSection`, `RoutineEditorScreen`, `AthleteDetailScreen`, el chip "Asignado por <PF>" en `RoutineDetailScreen`, la navegación tap-through desde `_ActiveAlumnoCard` y las rutas nuevas (`/coach/athlete/:athleteId`, `/workout/routine-editor/:athleteId`).

### Modified Capabilities

- **`workout-data`**: anotación documental — `RoutineRepository` ahora expone dos métodos coach-aware (`listAssignedTo`, `createAssigned`) sobre la colección `routines`. La semántica de `listAll()` se mantiene (sin breaking change); los nuevos métodos coexisten. Se añade el composite index documentado a `firestore.indexes.json`.

## Chained PR Plan

Estimación bruta del explore: ~600-800 líneas totales. Excede el budget de 400 → **Chained PRs (`auto-chain`)** confirmado por delivery strategy.

### PR1: `feat/coach-plans-mobile-data` (~250-300 líneas)

**Status**: ✅ MERGED (PR #64)

### PR2: `feat/coach-plans-mobile-ui` (~350-450 líneas)

**Status**: ✅ MERGED (PR #70, PR #71 hotfix bundle)

## Success Criteria

- [x] PR1 mergeado: `listAssignedTo` + `createAssigned` + rule create + composite index + provider, todos con tests verdes.
- [x] PR2 mergeado: `MiPlanSection` reemplaza `_TuRutinaSection` en `WorkoutScreen`, `RoutineEditorScreen` y `AthleteDetailScreen` accesibles vía rutas nuevas, chip "Asignado por <PF>" visible en `RoutineDetailScreen` cuando aplica.
- [x] Flow end-to-end PF: `TrainerCoachView` → tap `_ActiveAlumnoCard` → `AthleteDetailScreen` → tap "CREAR PLAN" → llena `RoutineEditorScreen` → submit → plan persistido en Firestore con campos coach correctos.
- [x] Flow end-to-end Atleta: `WorkoutScreen` → `MiPlanSection` muestra el plan recién asignado → tap → `RoutineDetailScreen` con chip "Asignado por <NombrePF>".
- [x] Multi-plan: si el PF crea dos planes para el mismo atleta, ambos aparecen en `MiPlanSection` ordenados por `createdAt DESC`.
- [x] Post-terminate: si el `TrainerLink` del `assignedBy` queda en `terminated`, el plan sigue visible pero con chip "Plan finalizado".
- [x] Firestore rules: PF puede crear plan; atleta NO puede crear plan ajeno; cualquier user NO puede crear con `visibility = public`; anon NO puede crear.
- [x] Composite index funcionando: `listAssignedTo` no devuelve `failed-precondition` en runtime.
- [x] `flutter analyze` 0 issues, `dart format .` clean, `flutter test` green en ambos PRs.

**Archive Status**: All criteria met. Change ready for closure.

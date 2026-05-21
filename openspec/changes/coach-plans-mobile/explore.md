# Exploration: coach-plans-mobile (Fase 5 · Etapa 4)

**Change**: coach-plans-mobile
**Fase/Etapa**: Fase 5 · Etapa 4
**Branch target**: feat/coach-plans-mobile (not created yet)
**Owner**: Dev A (reasignado — el que tenga bandwidth)
**Project**: treino
**Artifact store**: hybrid (openspec + engram)
**Engram key**: sdd/coach-plans-mobile/explore
**SCENARIO start**: 432

---

## Estado actual del codebase

### Modelo Routine (lib/features/workout/domain/routine.dart)
- Campos coach añadidos en Fase 5 Etapa 1: `source: RoutineSource` (default `system`), `assignedBy: String?`, `assignedTo: String?`, `visibility: RoutineVisibility` (default `public`).
- `RoutineSource` enum: `system | trainerAssigned | userCreated`
- `RoutineVisibility` enum: `public | private | shared`
- Modelos `RoutineDay` y `RoutineSlot` completos (freezed). RoutineSlot tiene: exerciseId, exerciseName (denorm), muscleGroup (denorm), targetSets, targetRepsMin, targetRepsMax, restSeconds, targetWeightKg?, notes?.

### RoutineRepository (lib/features/workout/data/routine_repository.dart)
- Solo tiene `listAll()` y `getById(id)`.
- **GAPS**:
  1. Falta `listAssignedTo(athleteId)` — query `where('assignedTo', isEqualTo, uid).where('source', isEqualTo, 'trainer-assigned')`.
  2. Falta `createAssigned(Routine)` — para que el PF pueda persistir nuevos planes.

### routine_providers.dart
- `routinesProvider`: usa `listAll()` — devuelve plantillas públicas.
- **GAP**: No existe `assignedRoutinesProvider` para el atleta actual.

### Firestore Rules (firestore.rules líneas 43-58)
- `allow read` YA soporta planes asignados: `request.auth.uid == resource.data.assignedTo` y `assignedBy`.
- `allow write: if false` — falta abrir `create` para PFs.

### WorkoutScreen
- Contiene `PlantillasSection`, `_TuRutinaSection` (placeholder actual — "No tenés rutina asignada todavía."), y `HistorialSection`.
- `_TuRutinaSection` es exactamente donde va la nueva "MI PLAN" section.

### RoutineDetailScreen
- ConsumerStatefulWidget usando `routineByIdProvider(routineId)`.
- Badge "Asignado por <PF>": insertar chip condicional en `_RoutineDetailContent` cuando `routine.source == RoutineSource.trainerAssigned`.

### TrainerCoachView
- `_ActiveAlumnoCard` NO tappable. Hay que agregar tap → `AthleteDetailScreen`.

### TrainerLink model
- SIN campo `sharedWithTrainer` (la decisión arquitectónica #4 lo mencionaba pero no llegó al modelo). NO es bloqueante para Etapa 4 (solo afecta Etapa 6).

### Tests existentes
- Último SCENARIO usado: 431.
- Próximo disponible: **432**.

---

## Decisiones resueltas

1. **"MI PLAN" section reemplaza `_TuRutinaSection`**: el placeholder ya existe en `workout_screen.dart`. Convertirlo en `MiPlanSection` ConsumerWidget que watchea `assignedRoutinesProvider(currentUid)`. Reutilizar el copy del placeholder como empty state.

2. **Query `assignedTo`**: `RoutineRepository.listAssignedTo(String athleteId)`. Firestore rules YA permiten este read sin cambios.

3. **Multi-plan latest-first (MVP)**: NO agregar campo `status` ni archive logic. El query ordena por `createdAt DESC`; si hay > 1 plan, se muestran como lista. Si en futuro se decide archivar, se agrega `archivedAt`.

4. **`RoutineRepository.createAssigned(Routine)`**: nuevo método explícito. Semántica clara consistente con el patrón de `request/accept/decline/terminate` del trainer link repo.

5. **Firestore rules — write**: agregar
   ```
   allow create: if request.auth != null
                 && request.resource.data.assignedBy == request.auth.uid
                 && request.resource.data.source == 'trainer-assigned'
                 && request.resource.data.visibility in ['private', 'shared'];
   ```
   Solo PF (assignedBy) crea. Update/delete defer a Etapa 7.

6. **Badge "Asignado por <PF>" en RoutineDetailScreen**: chip condicional en `_RoutineDetailContent` que aparece cuando `source == trainerAssigned`. Necesita `userPublicProfileProvider(routine.assignedBy!)` para el nombre.

7. **AthleteDetailScreen (trainer-side)**: nueva pantalla accesible desde `_ActiveAlumnoCard` tap. Muestra header del atleta + lista de planes asignados + botón "CREAR PLAN" → `RoutineEditorScreen`. **Scope MVP**: NO historial, NO sesiones (requiere `sharedWithTrainer` → Etapa 6). Ruta: `/coach/athlete/:athleteId`.

8. **RoutineEditorScreen**: nueva pantalla full-screen single-scroll form. Metadata (name/split/daysPerWeek/level) + días con slots editables. Submit → `createAssigned`. Selector de ejercicio via `showModalBottomSheet` con `exercisesProvider` y search inline. Ruta: `/workout/routine-editor/:athleteId`.

9. **Plan después de link terminated**: el plan PERMANECE visible en el tab del atleta. Si el link del `assignedBy` está terminated, se muestra badge visual "Plan finalizado" pero no se borra el plan.

10. **`sharedWithTrainer` ausente**: NO bloquea Etapa 4 (PF accede solo a sus propios planes via `assignedBy`). Anotar como deuda técnica a resolver antes de Etapa 6.

---

## Áreas afectadas

### Nuevos archivos
- `lib/features/workout/presentation/widgets/mi_plan_section.dart`
- `lib/features/workout/presentation/routine_editor_screen.dart`
- `lib/features/coach/presentation/athlete_detail_screen.dart`
- `lib/features/workout/application/assigned_routine_providers.dart`
- `test/features/workout/data/routine_repository_assigned_test.dart`
- `test/features/workout/presentation/widgets/mi_plan_section_test.dart`
- `test/features/workout/presentation/routine_editor_screen_test.dart`
- `test/features/coach/presentation/athlete_detail_screen_test.dart`
- `scripts/rules_test/rules.test.js` — nuevos casos para create en routines (cuando se corra el rules emulator)

### Archivos modificados
- `lib/features/workout/data/routine_repository.dart` — agregar `listAssignedTo()` + `createAssigned()`
- `lib/features/workout/presentation/routine_detail_screen.dart` — badge condicional "Asignado por <PF>"
- `lib/features/workout/workout_screen.dart` — reemplazar `_TuRutinaSection` con `MiPlanSection`
- `lib/features/coach/trainer_coach_view.dart` — `_ActiveAlumnoCard` tappable
- `lib/app/router.dart` — agregar 2 rutas (athlete detail + routine editor)
- `firestore.rules` — abrir `allow create` en `routines/{routineId}` para PFs
- `firestore.indexes.json` — composite index `assignedTo + source + createdAt` para evitar `failed-precondition` runtime

### Sin tocar
- Modelos Routine/RoutineDay/RoutineSlot/RoutineSource/RoutineVisibility — sin cambios
- `session_player_screen.dart` — locked por decisión #3
- `post_workout_summary_screen.dart` — sin cambios
- `trainer_link.dart`, `trainer_link_repository.dart`, `trainer_link_providers.dart` — sin cambios (sharedWithTrainer defer)

---

## Aproximaciones

### A. Plan activo único vs multi-plan por pareja

| Enfoque | Pros | Cons |
|---|---|---|
| Single active (campo status) | UX clara — UN plan | Schema extra + lógica de archivado + rules más complejas |
| **Multi-plan latest-first (recomendado)** | Sin schema changes, history natural | Si hay 2-3 planes, UI con scroll |
| Single per trainer + replace | Simple UI | Batch write atomic + rules complejas |

**Decisión: Multi-plan latest-first.**

### B. RoutineEditorScreen — single-scroll vs wizard

| Enfoque | Pros | Cons |
|---|---|---|
| **Single-scroll form (recomendado)** | Patrón CreatePostScreen, sin nav extra | Form largo para 5+ días |
| Step wizard (metadata → días) | Más guiado | Navegación + state bridge |
| Bottom sheet per step | Sin nuevas rutas | Estado complejo, no idiomático |

**Decisión: single-scroll con `ExpansionTile` por día.**

### C. Selección de ejercicio en slot editor

| Enfoque | Pros | Cons |
|---|---|---|
| **Bottom sheet + lista filtrable (recomendado)** | Reutiliza exercisesProvider, search inline | Filtro manual del catálogo |
| Pantalla full-screen separada | Más espacio | Nueva ruta + state |
| Dropdown inline | Trivial | Mala UX si crece el catálogo |

**Decisión: `showModalBottomSheet` con `TextField` search.**

---

## Riesgos

1. **PR size HIGH (~600-800 líneas)**: dividir en 2 chained PRs:
   - **PR1 (data layer)**: `listAssignedTo` + `createAssigned` + rules + composite index + `assignedRoutinesProvider` + tests (SCENARIO-432..~445).
   - **PR2 (UI)**: `MiPlanSection` + `RoutineEditorScreen` + `AthleteDetailScreen` + badge en RoutineDetailScreen + router + tests (SCENARIO-~446..~465).

2. **RoutineEditorScreen complexity**: estado local mutable (lista de días, lista de slots por día) requiere `StatefulWidget`, no Riverpod inmutable. Es el componente más complejo del sprint.

3. **Firestore rules — `create` para PF**: validamos `assignedBy == request.auth.uid` + `source == 'trainer-assigned'`. NO hacemos cross-collection lookup del role del usuario (anti-pattern por performance/complejidad). El client-side guard via `TrainerCoachView` previene que un athlete pueda ver el `RoutineEditorScreen`.

4. **`sharedWithTrainer` ausente del TrainerLink model**: deuda técnica anotada, no bloquea esta etapa.

5. **Composite index proactivo**: la query `where('assignedTo').where('source').orderBy('createdAt DESC')` requiere composite index en `firestore.indexes.json`. Agregar desde el inicio para evitar el síntoma de "query devuelve vacío silentemente" en runtime.

---

## SCENARIO start

**432** (último usado: 431 en trainer_specialty_chips_test.dart y trainer_discovery_providers_test.dart)

---

## Listo para Proposal

**Sí.** Todas las preguntas críticas resueltas. Recomendación: chained PRs (data + UI) para mitigar PR-size risk.

Deuda técnica anotada: `sharedWithTrainer` en TrainerLink (relevant para Etapa 6).

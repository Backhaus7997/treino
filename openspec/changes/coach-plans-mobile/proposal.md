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

### Out of Scope (DELIBERATELY STUBBED — documentar en QA)

- **Historial / drill-down de sesiones del atleta en `AthleteDetailScreen`**: el PF no ve las sesiones ejecutadas por el atleta. Esto requiere el campo `sharedWithTrainer` en `TrainerLink` (ver "Tech Debt" abajo) y un consumer dedicado de `SessionRepository.listForAthlete(athleteId)` con autorización. **Diferido a Etapa 6 (Coach Hub)**. `AthleteDetailScreen` MVP solo muestra header + planes + CTA.
- **Edición y eliminación de planes asignados**: el PF no puede editar ni borrar un plan ya creado en esta etapa. `RoutineDetailScreen` "EDITAR" sigue disabled. Update/delete rules en Firestore quedan en `if false`. **Diferido a Etapa 7 (advanced editing)**.
- **Archive / status flag de planes**: NO se agrega campo `status` a `Routine`. La semántica de "plan activo" es "el más reciente" (latest-first). Si el PF crea un segundo plan, ambos quedan visibles ordenados por `createdAt DESC`.
- **Cross-collection role check en rules**: las Firestore rules NO leen `users/{uid}.role == 'trainer'` para validar creación. La validación de rol queda client-side (`TrainerCoachView` guard impide athletes accedan al `RoutineEditorScreen`). Trade-off: simplicidad + performance vs defense-in-depth. Si un athlete tiene token forjado podría escribir un doc con `source='trainer-assigned'` y `assignedBy = su propio uid` — pero el doc resulta inocuo (no es visible a otros athletes porque `assignedTo` apunta a su propio uid).
- **Validación server-side de la estructura completa del `Routine`** (días, slots, exerciseIds existentes): rules solo validan los campos top-level (`assignedBy`, `source`, `visibility`). La integridad de days/slots queda del lado client.
- **Notificación al atleta cuando recibe un plan nuevo**: no hay push/in-app notification. El atleta lo descubre al abrir `WorkoutScreen`. **Diferido a Fase 6 (notifications)**.
- **`sharedWithTrainer` en `TrainerLink`**: ver "Tech Debt" — anotado pero no resuelto en esta etapa.

## Approach

### Problema central: el atleta y el PF ya tienen schema, falta la cadena entre ellos

La Fase 5 Etapa 1 introdujo los campos coach en `Routine` (`source`, `assignedBy`, `assignedTo`, `visibility`) y un patrón `RoutineSource.trainerAssigned`. La Etapa 3 confirmó los vínculos PF↔atleta. Las Firestore rules YA permiten read de planes asignados (`request.auth.uid == resource.data.assignedTo`). Sin embargo:

- El PF no tiene UI para crear un plan ni para llegar al atleta vinculado.
- El atleta no tiene UI para ver el plan asignado (placeholder estático).
- El `RoutineRepository` no expone `listAssignedTo` ni `createAssigned`.
- Las rules tienen `allow write: if false` — el PF no puede persistir un nuevo plan.

Esta etapa resuelve **la cadena completa**: trainer abre `AthleteDetailScreen` → tap "CREAR PLAN" → llena `RoutineEditorScreen` → submit → `createAssigned` → el atleta abre `WorkoutScreen` → `MiPlanSection` muestra el plan vía `assignedRoutinesProvider` → tap → `RoutineDetailScreen` con badge "Asignado por <PF>".

### Data extension (PR1)

- **Query**: `listAssignedTo` filtra por `assignedTo + source` y ordena por `createdAt DESC`. Composite index proactivo en `firestore.indexes.json` para evitar el síntoma "query devuelve vacío silenciosamente" si Firestore exige el índice.
- **Persistencia**: `createAssigned` recibe un `Routine` ya construido en el editor (con `source = trainerAssigned`, `assignedBy = currentUid`, `assignedTo = athleteId`, `visibility = private | shared`). El método explícito (no genérico `create`) sigue el patrón semántico del `TrainerLinkRepository` (request/accept/decline/terminate).
- **Rules**: `allow create` con validación mínima top-level. La carga útil del `Routine` (days/slots) queda del lado client porque rules complejas de structure validation son frágiles y caras.
- **Provider**: `assignedRoutinesProvider(athleteId)` como `FutureProvider.autoDispose.family`. Auto-dispose para no retener resultados huérfanos cuando el atleta abandona `WorkoutScreen`.

### UI consumers (PR2)

- **MiPlanSection**: reemplazo limpio del placeholder. Multi-plan latest-first: si hay 1 plan, una sola card; si hay > 1, lista con scroll vertical mínima (probablemente 1-3 en la práctica). Empty state reutiliza el copy actual.
- **AthleteDetailScreen**: ruta `/coach/athlete/:athleteId`. Header reusable + lista filtrada de planes asignados (por `assignedBy == currentTrainerUid`) + CTA destacado. MVP intencionalmente delgado para mantener PR2 bajo el budget.
- **RoutineEditorScreen**: la complejidad de este sprint. Single-scroll form con `ExpansionTile` por día. Estado local mutable (`List<RoutineDay>`) en un `StatefulWidget` — Riverpod no se usa para el estado del form (es local efímero). Submit construye el `Routine` final y llama `createAssigned`. Selector de ejercicios via bottom sheet con `exercisesProvider` y filter inline.
- **Badge en RoutineDetailScreen**: chip condicional en `_HeroStrip` que aparece solo cuando `source == trainerAssigned`. Lee el nombre del PF via `userPublicProfileProvider(routine.assignedBy!)`.

### Plan después de link terminated

El plan permanece visible en la sección "MI PLAN" del atleta. `MiPlanSection` cruza el `assignedRoutinesProvider` con `currentAthleteLinkProvider`: si el link del `assignedBy` está terminated, se renderiza un chip visual "Plan finalizado" pero no se borra el doc. Mantenemos el historial. Update/delete del plan permanece bloqueado en rules.

## Capabilities

### New Capabilities

- **`coach-plans-mobile-data`**: documenta `RoutineRepository.listAssignedTo` + `createAssigned`, el provider `assignedRoutinesProvider(athleteId)`, las Firestore rules `allow create` en `routines/{routineId}` y el composite index `assignedTo + source + createdAt`.
- **`coach-plans-mobile-ui`**: documenta `MiPlanSection`, `RoutineEditorScreen`, `AthleteDetailScreen`, el chip "Asignado por <PF>" en `RoutineDetailScreen`, la navegación tap-through desde `_ActiveAlumnoCard` y las rutas nuevas (`/coach/athlete/:athleteId`, `/workout/routine-editor/:athleteId`).

### Modified Capabilities

- **`workout-data`**: anotación documental — `RoutineRepository` ahora expone dos métodos coach-aware (`listAssignedTo`, `createAssigned`) sobre la colección `routines`. La semántica de `listAll()` se mantiene (sin breaking change); los nuevos métodos coexisten. Se añade el composite index documentado a `firestore.indexes.json`.

## Affected Areas

| Area | Impact | PR | Description |
|------|--------|-----|-------------|
| `lib/features/workout/data/routine_repository.dart` | Modified | PR1 | `listAssignedTo` + `createAssigned`. |
| `lib/features/workout/application/assigned_routine_providers.dart` | New | PR1 | `assignedRoutinesProvider(athleteId)`. |
| `firestore.rules` | Modified | PR1 | `allow create` en `routines/{routineId}` para PFs. |
| `firestore.indexes.json` | Modified | PR1 | Composite index `assignedTo + source + createdAt`. |
| `test/features/workout/data/routine_repository_assigned_test.dart` | New | PR1 | Tests de query + persistencia. |
| `test/features/workout/application/assigned_routine_providers_test.dart` | New | PR1 | Tests del provider. |
| `scripts/rules_test/rules.test.js` | Modified | PR1 | Test cases de la nueva rule de create. |
| `lib/features/workout/presentation/widgets/mi_plan_section.dart` | New | PR2 | Sección "MI PLAN" para atleta. |
| `lib/features/workout/presentation/routine_editor_screen.dart` | New | PR2 | Form full-screen para PF. |
| `lib/features/coach/presentation/athlete_detail_screen.dart` | New | PR2 | Drill-down de alumno para PF. |
| `lib/features/workout/presentation/routine_detail_screen.dart` | Modified | PR2 | Chip condicional "Asignado por <PF>". |
| `lib/features/workout/workout_screen.dart` | Modified | PR2 | Reemplazar `_TuRutinaSection` con `MiPlanSection`. |
| `lib/features/coach/trainer_coach_view.dart` | Modified | PR2 | `_ActiveAlumnoCard` tappable. |
| `lib/app/router.dart` | Modified | PR2 | Rutas `/coach/athlete/:athleteId` y `/workout/routine-editor/:athleteId`. |
| `test/features/workout/presentation/widgets/mi_plan_section_test.dart` | New | PR2 | Tests widget. |
| `test/features/workout/presentation/routine_editor_screen_test.dart` | New | PR2 | Tests widget + submit flow. |
| `test/features/coach/presentation/athlete_detail_screen_test.dart` | New | PR2 | Tests drill-down. |

## Rollback Plan

### Rollback de PR2 (UI) — bajo riesgo

Revert del commit de `feat/coach-plans-mobile-ui`. La rama vuelve al estado post-PR1: `WorkoutScreen` muestra el placeholder `_TuRutinaSection` nuevamente, `_ActiveAlumnoCard` deja de ser tappable, `RoutineDetailScreen` sin chip "Asignado por". Las rutas nuevas se quitan del router. La infra (repo methods + provider + rules + index) queda en main pero queda dormida — sin consumidores UI. Sin migraciones, sin impacto en producción. Los planes ya creados en Firestore (si hubo seed o uso en alfa) permanecen y siguen siendo leíbles por la rule de read existente.

### Rollback de PR1 (data) — requiere revertir PR2 primero

Si PR2 ya está mergeado, revertir PR1 sin PR2 ROMPERÍA la app (`MiPlanSection` importa `assignedRoutinesProvider`, `RoutineEditorScreen` importa `createAssigned`). Orden obligatorio: revert PR2 → revert PR1. El revert de PR1 quita `listAssignedTo`, `createAssigned`, la rule de create y el composite index. Los docs ya creados en Firestore permanecen pero quedan sin escritores nuevos (read sigue funcionando por la rule existente).

### Riesgo de rollback

- **PR2 revert**: nulo. `WorkoutScreen` vuelve al placeholder, `TrainerCoachView` vuelve al estado actual sin tap.
- **PR1 revert** (con PR2 ya revertido): bajo. La rule de create se quita atómicamente; el index queda en Firestore (no es problemático tener un índice no usado). Sin impacto en datos existentes.

## Chained PR Plan

Estimación bruta del explore: ~600-800 líneas totales. Excede el budget de 400 → **Chained PRs (`auto-chain`)** confirmado por delivery strategy.

### PR1: `feat/coach-plans-mobile-data` (~250-300 líneas)

**Scope**:
- `RoutineRepository.listAssignedTo` + `createAssigned`.
- `firestore.rules` `allow create` en `routines/{routineId}`.
- `firestore.indexes.json` composite index.
- `assignedRoutinesProvider(athleteId)`.
- Tests: repo (query + create), provider (fixture, error), rules emulator.
- Target branch: `main`.

**Estado intermedio post-PR1 (entre merges)**: la data layer queda lista y testeada pero ningún consumer UI la usa. El `WorkoutScreen` del atleta sigue mostrando el placeholder estático "No tenés rutina asignada todavía." y el PF en `TrainerCoachView` sigue viendo `_ActiveAlumnoCard` sin tap. **Es deliberado**: PR1 es self-contained y mergeable independientemente sin romper nada en producción. La rule `allow create` queda activa pero solo se podrá ejercitar via el editor que llega en PR2 — un atleta no puede triggear creación porque ni siquiera tiene `assignedBy == request.auth.uid` que valga para sí mismo (es semánticamente incorrecto que un atleta se asigne un plan a sí mismo via esta rule, y el flujo client-side lo previene).

### PR2: `feat/coach-plans-mobile-ui` (~350-450 líneas)

**Scope**:
- `MiPlanSection` widget + tests.
- `RoutineEditorScreen` + tests (incluye submit flow contra `createAssigned`).
- `AthleteDetailScreen` + tests.
- Chip "Asignado por <PF>" en `RoutineDetailScreen`.
- `TrainerCoachView`: `_ActiveAlumnoCard` tappable.
- Router: rutas nuevas.
- Target branch: `feat/coach-plans-mobile-data` (chain).

**Entrega**: UI completa end-to-end. Cierra la Etapa 4.

### Caveat del estado intermedio

Mientras PR1 está mergeado y PR2 no, ningún usuario nota cambio en la UI. La comunicación al equipo / QA debe ser explícita: "PR1 es data-only, la UI llega en PR2". No hay path de usuario que rompa.

### Justificación del split

- PR1 puede mergearse independientemente sin romper producción (la data layer queda dormida).
- PR2 depende mecánicamente de PR1 (importa los nuevos métodos y el provider) pero su rebase es trivial.
- Cada PR cierra una unidad lógica testeable.
- Tamaño individual queda dentro del budget de 400 LOC (PR2 al filo — monitorear en `sdd-apply`).
- Patrón ya validado en Etapa 2 (`coach-discovery`).

## SCENARIO Range Expected

- **PR1**: SCENARIO-432 → ~445 (≈14 scenarios: repo query, repo create, provider OK/error, rules create OK/denied por assignedBy mismatch, denied por visibility public, denied por source distinto, denied por anon).
- **PR2**: SCENARIO-~446 → ~465 (≈20 scenarios: MiPlanSection empty/populated/loading/error/badge-terminated, RoutineEditorScreen render/add-day/remove-day/add-slot/select-exercise/submit/validation, AthleteDetailScreen render/CTA-nav, RoutineDetailScreen chip cuando trainerAssigned, TrainerCoachView tap-nav, router test x2).
- **Total esperado**: SCENARIO-432 → ~465. Rango sujeto a ajuste fino en `sdd-tasks`.

## REQ Namespace

`REQ-COACH-PLANS-NNN` (e.g. `REQ-COACH-PLANS-001` = `listAssignedTo` filtra por `assignedTo + source`, `REQ-COACH-PLANS-002` = `createAssigned` persiste con campos coach obligatorios, etc.). Numeración secuencial definida en `sdd-spec`.

## Dependencies

### Hard dependencies (must be merged before)

- **Fase 5 Etapa 1** — ya mergeada en main. Provee campos `source`, `assignedBy`, `assignedTo`, `visibility` en `Routine` + enums `RoutineSource`, `RoutineVisibility`.
- **Fase 5 Etapa 2** (`coach-discovery`) — ya mergeada en main. Provee `TrainerPublicProfile` (necesario para futuros enrichments del chip "Asignado por <PF>", aunque hoy se usa `userPublicProfileProvider`).
- **Fase 5 Etapa 3** (`coach-links`) — ya mergeada en main. Provee `TrainerLink` + `TrainerLinkRepository` + `currentAthleteLinkProvider` (necesario para el badge "Plan finalizado" en `MiPlanSection`).

### Soft dependencies (parallel, no conflict)

Ninguna. No hay otras feature branches en flight que toquen `RoutineRepository`, `firestore.rules` de `routines/`, `WorkoutScreen`, `TrainerCoachView` ni `router.dart`.

### Downstream consumers (informativo)

- **Etapa 6 (Coach Hub)**: agrega el historial / drill-down de sesiones del atleta en `AthleteDetailScreen`. Requiere `sharedWithTrainer` en `TrainerLink`.
- **Etapa 7 (advanced editing)**: permite al PF editar y borrar planes ya asignados (`allow update/delete` en rules).
- **Fase 6 (notifications)**: notifica al atleta cuando recibe un plan nuevo.

## Open Questions (surface to design / tasks)

1. **Mínimo de días para submit válido en `RoutineEditorScreen`**: ¿se exige ≥ 1 día con ≥ 1 slot? ¿Se permite plan "vacío" como borrador? **Recomendación**: ≥ 1 día con ≥ 1 slot. Validar client-side antes de habilitar el botón submit. **Diferido a design**.
2. **Mínimo de slots por día**: ¿0 slots es válido (día de descanso) o se exige ≥ 1? **Recomendación**: permitir 0 (día de descanso explícito). **Diferido a design**.
3. **Comportamiento si `visibility` queda en blanco**: ¿default `private` o forzar `shared`? Las rules aceptan ambos. **Recomendación**: `private` por default + toggle UI para `shared` (opcional MVP). **Diferido a design**.
4. **Tiebreaker cuando dos planes tienen el mismo `createdAt`** (improbable pero posible si seed): por `name` o por doc id. **Diferido a design**.
5. **Empty state del PF en `AthleteDetailScreen`**: ¿qué muestra cuando el atleta no tiene planes? Copy + ilustración. **Diferido a design**.
6. **Selector de ejercicio — orden de la lista**: ¿alfabético por `name` o por `muscleGroup` agrupado? **Recomendación**: agrupado por `muscleGroup` con headers. **Diferido a design**.
7. **Confirmación al PF antes de submit**: ¿modal de confirmación "¿Asignar este plan a <Atleta>?" o submit directo? **Recomendación**: confirmación con resumen (N días, M ejercicios totales). **Diferido a design**.
8. **Badge "Plan finalizado" — formato exacto**: chip vs banner sobre la card. **Diferido a design**.
9. **Should PR2 split further?**: si `sdd-tasks` proyecta > 400 LOC en PR2, evaluar split (e.g. PR2a = `MiPlanSection` + badge en `RoutineDetailScreen`, PR2b = `AthleteDetailScreen` + `RoutineEditorScreen` + router). **Diferido a tasks**.

## Tech Debt Note

**`sharedWithTrainer` ausente del modelo `TrainerLink`**: la decisión arquitectónica original de Etapa 3 contemplaba un campo booleano `sharedWithTrainer` en `TrainerLink` que el atleta toggle-ea para autorizar al PF a ver sus sesiones ejecutadas. **No llegó al modelo en Etapa 3** (confirmado por lectura de `lib/features/coach/domain/trainer_link.dart`). Para Etapa 4 **no es bloqueante** porque el PF accede solo a planes que él mismo creó (filtra por `assignedBy == currentUid`), no a sesiones del atleta.

**Acción**: agregar `sharedWithTrainer: bool` (default `false`) al modelo `TrainerLink` y un toggle UI para el atleta **antes de Etapa 6 (Coach Hub)**. La rule de read de `sessions/` del atleta debe contemplar `sharedWithTrainer == true && trainerLink.status == 'active'` para permitir lectura desde el PF. Documentar en el roadmap como pre-req de Etapa 6.

## Success Criteria

- [ ] PR1 mergeado: `listAssignedTo` + `createAssigned` + rule create + composite index + provider, todos con tests verdes.
- [ ] PR2 mergeado: `MiPlanSection` reemplaza `_TuRutinaSection` en `WorkoutScreen`, `RoutineEditorScreen` y `AthleteDetailScreen` accesibles vía rutas nuevas, chip "Asignado por <PF>" visible en `RoutineDetailScreen` cuando aplica.
- [ ] Flow end-to-end PF: `TrainerCoachView` → tap `_ActiveAlumnoCard` → `AthleteDetailScreen` → tap "CREAR PLAN" → llena `RoutineEditorScreen` → submit → plan persistido en Firestore con campos coach correctos.
- [ ] Flow end-to-end Atleta: `WorkoutScreen` → `MiPlanSection` muestra el plan recién asignado → tap → `RoutineDetailScreen` con chip "Asignado por <NombrePF>".
- [ ] Multi-plan: si el PF crea dos planes para el mismo atleta, ambos aparecen en `MiPlanSection` ordenados por `createdAt DESC`.
- [ ] Post-terminate: si el `TrainerLink` del `assignedBy` queda en `terminated`, el plan sigue visible pero con chip "Plan finalizado".
- [ ] Firestore rules: PF puede crear plan; atleta NO puede crear plan ajeno; cualquier user NO puede crear con `visibility = public`; anon NO puede crear.
- [ ] Composite index funcionando: `listAssignedTo` no devuelve `failed-precondition` en runtime.
- [ ] `flutter analyze` 0 issues, `dart format .` clean, `flutter test` green en ambos PRs.
- [ ] Tech debt anotado en roadmap: `sharedWithTrainer` en `TrainerLink` antes de Etapa 6.
- [ ] Sin tocar: modelo `Routine` / `RoutineDay` / `RoutineSlot` / enums, `session_player_screen.dart`, `post_workout_summary_screen.dart`, `TrainerLinkRepository`.

## Ready for spec + design

**Sí** — todas las decisiones arquitectónicas críticas resueltas en explore (multi-plan latest-first sin `status`, query `assignedTo + source + orderBy createdAt`, rule create con validación mínima top-level, composite index proactivo, single-scroll form con `ExpansionTile`, selector de ejercicios via bottom sheet, badge "Asignado por <PF>" como chip en hero, `AthleteDetailScreen` MVP sin historial, plan persiste post-terminate). Tradeoffs abiertos delegados a design: validación mínima del form, default `visibility`, tiebreaker de ordering, empty states, formato exacto del badge "Plan finalizado", confirmación pre-submit, posible split adicional de PR2. `sdd-spec` y `sdd-design` pueden correr en paralelo.

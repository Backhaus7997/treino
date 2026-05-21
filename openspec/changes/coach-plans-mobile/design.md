# Design: Coach Plans Mobile (Fase 5 · Etapa 4)

**Change**: `coach-plans-mobile` · **Branches**: `feat/coach-plans-mobile-data` (PR1) + `feat/coach-plans-mobile-ui` (PR2)
**SCENARIOs**: 432..~465 · **REQs**: `REQ-COACH-PLANS-NNN`
**Owner**: Dev A · **Project**: treino
**Artifact store**: hybrid · **Strict TDD**: ACTIVE (`flutter test`)
**Delivery**: chained PRs (PR1 data, PR2 UI)

## Technical Approach

Cierro el ciclo "PF crea plan → atleta lo ve" sobre la infra ya presente: campos `source/assignedBy/assignedTo/visibility` en `Routine` (Etapa 1), `TrainerLink` y `currentAthleteLinkProvider` (Etapa 3), `userPublicProfileProvider` (Etapa 2). NO toco el modelo `Routine`/`RoutineDay`/`RoutineSlot` — sólo extiendo el repo, abro `allow create` con validación top-level y consumo todo desde la UI.

**Dos PRs encadenados**:

- **PR1 (data)** entrega `RoutineRepository.listAssignedTo` + `createAssigned`, el provider `assignedRoutinesProvider`, la rule `allow create` sobre `routines/{routineId}` con validación `assignedBy == request.auth.uid` (sin cross-collection role lookup), y el composite index proactivo `assignedTo + source + createdAt`. Toda la infra queda probada pero dormida — `WorkoutScreen` sigue mostrando el placeholder `_TuRutinaSection`.
- **PR2 (UI)** monta los consumers: `MiPlanSection` reemplaza el placeholder en `WorkoutScreen`, `RoutineEditorScreen` (form local con `StatefulWidget` mutable) construye el `Routine` y dispara `createAssigned`, `AthleteDetailScreen` es el drill-down accesible al tap del `_ActiveAlumnoCard`, `RoutineDetailScreen` suma chip "Asignado por <PF>" condicional cuando `source == trainerAssigned`, y `router.dart` agrega 2 rutas bajo el ShellRoute.

**Decisión arquitectónica central**: el state del form en `RoutineEditorScreen` vive en `StatefulWidget` local con clases mutables `_EditableDay` / `_EditableSlot`, NO en Riverpod. Riverpod gestiona providers de datos remotos (`exercisesProvider`, `userPublicProfileProvider`), el form es state efímero que se descarta al pop. Esto evita la complejidad de un Notifier para un editor que se usa una sola vez por sesión.

**Multi-plan latest-first**: el ordering lo resuelve Firestore (`orderBy('createdAt', descending: true)`), sin campo `status`/`archivedAt` ni lógica de archivado en cliente. Si el PF crea un segundo plan, ambos aparecen en `MiPlanSection` ordenados por fecha. Tiebreaker: doc id (default Firestore — determinístico).

**Persistencia post-terminate**: el plan persiste aunque el `TrainerLink` quede en `terminated`. `MiPlanSection` cruza `assignedRoutinesProvider` con `currentAthleteLinkProvider` para renderizar chip "Plan finalizado" sobre la card. NO se borra el doc.

## Data Flow — PF crea plan

    TrainerCoachView (ALUMNOS tab)
        └── _ActiveAlumnoCard(link)               ← ahora InkWell tappable (PR2)
                │ onTap: context.push('/coach/athlete/${link.athleteId}')
                ▼
    AthleteDetailScreen(athleteId)                ← nueva pantalla (PR2)
        │
        ├──(watch)── userPublicProfileProvider(athleteId) ──► header
        │
        ├──(watch)── assignedRoutinesProvider(athleteId)  ──► AsyncValue<List<Routine>>
        │                  │
        │                  └── filtered client-side: where(r.assignedBy == currentTrainerUid)
        │                          │
        │                          ├── empty   → _EmptyState ("Todavía no le asignaste planes.")
        │                          └── non-empty → ListView de _PlanCard
        │
        └── CTA "CREAR PLAN"
                │ context.push('/workout/routine-editor/${athleteId}')
                ▼
        RoutineEditorScreen(athleteId)             ← nueva pantalla (PR2)
            │
            │  StatefulWidget — state local mutable:
            │    String name, split
            │    int daysPerWeek
            │    ExperienceLevel level
            │    List<_EditableDay> _days
            │      └── List<_EditableSlot> slots
            │            └── Exercise? exercise, int targetSets, ...
            │
            │  Construye Routine via build_routine_from_state():
            │    Routine(
            │      id: '',                                 ← Firestore generates
            │      name, split, level,
            │      days: _days.map((d) => d.toRoutineDay()).toList(),
            │      source: RoutineSource.trainerAssigned,
            │      assignedBy: currentTrainerUid,
            │      assignedTo: athleteId,
            │      visibility: RoutineVisibility.private,
            │    )
            │
            │  Submit:
            │    final saved = await ref.read(routineRepositoryProvider)
            │                       .createAssigned(routine);
            │    if (mounted) {
            │      ScaffoldMessenger.of(context).showSnackBar(
            │        SnackBar(content: Text('Plan creado y asignado.')));
            │      ref.invalidate(assignedRoutinesProvider(athleteId));
            │      context.pop();   ← vuelve a AthleteDetailScreen ya refrescada
            │    }
            │
            ▼
        RoutineRepository.createAssigned(routine)         ← nuevo método (PR1)
            │ final ref = await _collection.add(routine.toJson());
            │ return routine.copyWith(id: ref.id);
            ▼
        Firestore routines/{auto-id}                       ← rule `allow create` (PR1)

## Data Flow — Atleta ve plan

    WorkoutScreen
        ├── PlantillasSection                              ← unchanged
        ├── MiPlanSection                                  ← reemplaza _TuRutinaSection (PR2)
        │     │
        │     │ ConsumerWidget (sin state local)
        │     │ final uid = ref.watch(authStateChangesProvider).valueOrNull?.uid;
        │     │
        │     ├──(watch)── assignedRoutinesProvider(uid)  ──► AsyncValue<List<Routine>>
        │     │                  ├── loading → _LoadingSkeleton
        │     │                  ├── error   → _ErrorState (retry → ref.invalidate)
        │     │                  ├── empty   → Text("No tenés rutina asignada todavía.")
        │     │                  └── data    → ListView de _PlanCard (latest-first)
        │     │
        │     └──(watch)── currentAthleteLinkProvider     ──► AsyncValue<TrainerLink?>
        │                          │
        │                          └── usado SOLO para evaluar el badge
        │                              "Plan finalizado" por plan:
        │                              link?.status == terminated
        │                              && link.trainerId == plan.assignedBy
        │
        │     _PlanCard(routine)
        │           ├── Row(routineName + trainer name via userPublicProfileProvider(routine.assignedBy))
        │           ├── (opcional) chip "Plan finalizado" si link.terminated && match
        │           └── onTap → context.push('/workout/routine/${routine.id}')
        │
        └── HistorialSection                                ← unchanged

    RoutineDetailScreen(routineId)                        ← MODIFICADO (PR2)
        │
        ├──(watch)── routineByIdProvider(routineId)       ← unchanged
        │
        └── inside _RoutineDetailContent._HeroStrip:
              ├── _DayChipBadge(split · día N)            ← unchanged
              └── if (routine.source == trainerAssigned)
                    └── _AssignedByChip(assignedBy: routine.assignedBy!)
                          ├──(watch)── userPublicProfileProvider(assignedBy)
                          ├── loading → "Asignado por …"
                          ├── error   → "Asignado por un PF"
                          └── data    → "Asignado por ${profile.displayName}"

## Data Flow — `assignedRoutinesProvider`

    assignedRoutinesProvider(athleteId)
      FutureProvider.autoDispose.family<List<Routine>, String>
        │
        │ final repo = ref.watch(routineRepositoryProvider);
        │ return repo.listAssignedTo(athleteId);
        ▼
    RoutineRepository.listAssignedTo(athleteId)
        │ final snap = await _collection
        │   .where('assignedTo', isEqualTo: athleteId)
        │   .where('source', isEqualTo: 'trainer-assigned')
        │   .orderBy('createdAt', descending: true)
        │   .limit(20)
        │   .get();
        │ return snap.docs.map(_fromDoc).whereType<Routine>().toList();

**autoDispose**: el provider se libera cuando ningún widget lo observa. Volver a `WorkoutScreen` re-dispara la query. Acceptable porque (a) la query es chica (limit 20), (b) Firestore cachea en memoria, (c) evita stale data si el PF acaba de crear un plan en otro device.

## Architecture Decisions

| # | Decision | Choice | Rejected | Rationale |
|---|----------|--------|----------|-----------|
| 1 | `listAssignedTo` query shape | `where('assignedTo', isEqualTo: uid).where('source', isEqualTo: 'trainer-assigned').orderBy('createdAt', descending: true).limit(20)` | (a) Sin `source` filter (filtra todo); (b) Sin `limit`; (c) Server-side `orderBy` por `name` | El filtro doble (`assignedTo + source`) es necesario porque un atleta podría tener una rutina con `assignedTo == uid` pero `source == userCreated` en el futuro (Etapa 7). Sin el filtro de source contaminaría la lista. `limit 20` es ceiling defensivo — en la práctica un atleta tiene 1-2 planes; 20 cubre acumulación histórica sin pagar cost de scan completo. `orderBy('createdAt', desc)` resuelve "latest-first" sin lógica client-side. |
| 2 | `createAssigned` signature | `Future<Routine> createAssigned(Routine routine)` — recibe Routine ya validado por la UI con `id` vacío, devuelve el mismo Routine con `id` poblado por Firestore | (a) `Future<String> createAssigned(...)` — devuelve solo el id; (b) `Future<void>` y leer back via watcher; (c) Genérico `create(Routine)` sin validación semántica | Devolver el Routine completo permite al editor mostrar instantáneamente el resultado y navegar a `RoutineDetailScreen` sin re-fetch. Patrón espejo de `TrainerLinkRepository.request → TrainerLink`. La validación de campos requeridos (assignedBy, assignedTo, source, visibility) sucede en la UI antes del call — el repo solo persiste; si alguno es null, las rules de Firestore rechazan (defensa en profundidad). |
| 3 | `assignedRoutinesProvider` shape | `FutureProvider.autoDispose.family<List<Routine>, String>` donde `String = athleteId` | (a) `StreamProvider` para real-time updates; (b) NO autoDispose (KeepAlive); (c) Plain `FutureProvider` con read del uid actual desde otro provider | `FutureProvider` con autoDispose es suficiente para MVP: la creación del plan invalida explícitamente el provider (`ref.invalidate`); el atleta refresca al pull-to-refresh o volver al tab. `Stream` agregaría costo Firestore innecesario para datos que cambian muy de tarde en tarde. Family pasa el `athleteId` explícito — el mismo provider sirve para `MiPlanSection` (uid del atleta logueado) y `AthleteDetailScreen` (uid del alumno seleccionado). |
| 4 | Multi-plan ordering tiebreaker | Doc id (default Firestore cuando dos docs comparten `createdAt`) | (a) Por `name` ASC; (b) Por `daysPerWeek` ASC | Doc id es determinístico y gratis. Que dos planes compartan exactamente el mismo `createdAt` (UTC millis) en un mismo trainer es prácticamente imposible — pero si pasa, el doc id ordena de forma estable. No agrega lógica client-side. |
| 5 | Firestore rule `allow create` para `routines/{routineId}` | Validación top-level: `auth != null`, `assignedBy == auth.uid`, `source == 'trainer-assigned'`, `visibility in ['private', 'shared']`, `assignedTo is string && size > 0`. NO `update`/`delete`. NO cross-collection role lookup. | (a) Cross-collection check `get(/users/$(auth.uid)).data.role == 'trainer'`; (b) Validar estructura completa (days/slots) en rules; (c) Permitir `visibility == 'public'` para planes asignados | Cross-collection lookups en rules son costosos (1 read extra por write) y frágiles (race con actualización de role). El proyecto sigue la convención "no role check en rules" desde Etapa 2 (trainerPublicProfiles). Si un athlete tiene token forjado podría crear un doc con `assignedBy = su propio uid` y `assignedTo = otro uid` — pero el doc resulta inocuo: él mismo no podría verlo (no es ni assignedBy ni assignedTo del lado contrario) y el atleta receptor lo vería como "plan basura" sin trainer válido. El client-side guard (`TrainerCoachView` solo accesible si `role == 'trainer'`) previene el caso normal. Validación completa de days/slots en rules sería frágil — defer al client. |
| 6 | Composite index proactivo | `assignedTo (ASC) + source (ASC) + createdAt (DESC)` en `firestore.indexes.json` | (a) Esperar runtime `failed-precondition` y crear via link de Firebase Console; (b) Sin `orderBy` server-side (sort client-side) | Lección de Fase 3 Etapa 3 (mi-gym bug): omitir índices proactivos lleva a queries que devuelven vacío silenciosamente en producción. Agregar el index desde PR1 — sin cost de runtime, deploy junto con rules. |
| 7 | `MiPlanSection` widget kind | `ConsumerWidget` sin state local | `ConsumerStatefulWidget` con `_expanded`/`_collapsed` | Sin acciones expand/collapse (PlantillasSection sí tiene "Ver más" porque maneja > 3 plantillas; MiPlan típicamente tiene 1-2). Si llega a haber > 3 planes, mostrar todos en lista vertical sin truncar — multi-plan es escenario raro. |
| 8 | Lectura del uid del atleta en `MiPlanSection` | `ref.watch(authStateChangesProvider).valueOrNull?.uid` (provider existente de `auth_providers.dart`) | (a) Crear nuevo `currentUidProvider` derivado; (b) Pasar uid como param desde `WorkoutScreen` | El provider `authStateChangesProvider` ya está usado en otras zonas (`auth_notifier`); evita introducir helper redundante. Si `uid == null` (anonymous gate antes de redirect), `MiPlanSection` renderiza empty state — no es código alcanzable en producción pero defensivo. |
| 9 | Badge "Plan finalizado" — condición y formato | Chip pequeño dentro de `_PlanCard` (estilo similar al `_DayChipBadge` de hero). Condición: `currentAthleteLinkProvider.valueOrNull?.status == LinkStatus.terminated && link.trainerId == routine.assignedBy`. Una sola lectura del link suficiente (MVP allows only 1 active trainer at a time). | (a) Banner sobre la card; (b) Tinte gris en toda la card; (c) Borrar la card del listado | Chip es no-intrusivo y consistente con el patrón visual del `RoutineDetailScreen` hero. Banner es overkill — el plan sigue siendo válido (el atleta puede ejecutarlo), sólo cambia el contexto trainer. Borrar la card sería un anti-patrón histórico (vio el plan, ahora desaparece). La condición single-link es válida MVP — Etapa 7 podría agregar multi-trainer y cruzar por listForAthlete. |
| 10 | Chip "Asignado por <PF>" — ubicación y loading | Segundo chip en `_RoutineDetailContent`, debajo del `_DayChipBadge` existente dentro del hero. Loading state: `"Asignado por …"` con ellipsis. Error state: `"Asignado por un PF"`. | (a) Banner debajo de `_StatRow`; (b) Banner full-width arriba del hero; (c) Solo cuando `userPublicProfileProvider` ya cargó (no render hasta entonces) | Mantener el chip dentro del hero preserva la composición visual existente (badge + título). Render condicional con placeholder durante loading evita layout shift. Si el profile no carga (error o profile borrado), el fallback "Asignado por un PF" comunica la info sin romper UX. Condicional al outer level: solo se monta cuando `routine.source == RoutineSource.trainerAssigned && routine.assignedBy != null` — los planes seedeados (system) no muestran el chip. |
| 11 | `AthleteDetailScreen` route shape | `/coach/athlete/:athleteId` bajo el `GoRoute('/coach')` que vive dentro del ShellRoute (mantiene bottom bar visible) | (a) Top-level outside ShellRoute (immersive); (b) Bajo `/feed/profile/:uid` (reutilizar) | Consistencia con `/coach/trainer/:uid` (Etapa 2 Decision #17). El drill-down de alumno es navegable, no immersive — el PF puede volver al tab. `/feed/profile/:uid` es el public profile del feed; semánticamente distinto (acá vemos el alumno como cliente, no como autor de posts). |
| 12 | `AthleteDetailScreen` widget kind | `ConsumerWidget` stateless (no local state) | `ConsumerStatefulWidget` | El screen solo lee dos providers (`userPublicProfileProvider`, `assignedRoutinesProvider`). Sin acciones que requieran state local (sin pull-to-refresh manual: `ref.invalidate` cubre). |
| 13 | `AthleteDetailScreen` body composition | Header del atleta (inline simple — NO se extrae `_UserHeader` desde `trainer_coach_view.dart`) + lista de `_PlanCard` filtrados por `assignedBy == currentTrainerUid` + botón fijo "CREAR PLAN" arriba de `BottomAppBar` o como FAB inferior | (a) Exportar `_UserHeader` (es `private _UserHeader` en `trainer_coach_view.dart`); (b) FAB material en lugar de bottom button | El `_UserHeader` actual es private (prefix `_`). Exportarlo + adaptarlo agregaría costo. Inline header (`Row(avatar + Column(name + subtitle))`) es ~20 LOC — duplicación aceptable. Botón fijo en la parte inferior comunica acción primaria y es consistente con `_StartSessionCTABar` de `RoutineDetailScreen`. FAB material no es el patrón visual del proyecto (TREINO usa botones outlined / filled rectangulares). |
| 14 | `RoutineEditorScreen` state architecture | `StatefulWidget` local con clases mutables `_EditableDay` / `_EditableSlot`. NO Riverpod para form state. Submit construye el `Routine` inmutable al final. | (a) `ConsumerStatefulWidget` con `StateNotifier<RoutineDraft>` en Riverpod; (b) Form library (`flutter_form_builder`); (c) Mutar directamente lista de `RoutineDay` freezed (imposible) | Riverpod para form state agrega ceremonia para algo efímero. Las clases freezed son inmutables — copiar un slot para cambiar `targetSets` requiere `slot.copyWith` y `day.copyWith(slots: ...)` y `_days[i] = ...` — ergonómicamente torpe. Las clases locales mutables permiten `slot.targetSets = newValue + setState(() {})` directo. Al submit, `_days.map((d) => RoutineDay(name: d.name, slots: d.slots.map((s) => RoutineSlot(...)).toList()))` construye los freezed. Patrón validado en `_CreatePostBodyState` (form state local). |
| 15 | `RoutineEditorScreen` layout | Single-scroll `Scaffold + AppBar(title: 'Crear plan') + ListView` con secciones: (a) metadata form fields, (b) `ExpansionTile` por día (collapsible), (c) botón "+ Agregar día", (d) botón submit | (a) Step wizard 2 pantallas; (b) `PageView` paginado por día | Single-scroll permite revisar todo el plan antes de submit. `ExpansionTile` colapsa días para evitar scroll overwhelming en planes con 5-6 días. Botones agregar día / agregar slot inline son affordances naturales. Wizard fragmenta el flujo innecesariamente. |
| 16 | Form validation strategy | Validación inline en `_canSubmit` getter: name non-empty, split non-empty, daysPerWeek 1-7, ≥ 1 day, cada día ≥ 1 slot, cada slot tiene exercise + sets >= 1 + repsMin >= 1 + repsMax >= repsMin. Submit button disabled cuando `!_canSubmit`. | (a) `Form` widget + `FormField` validators (mostrar errores inline en cada campo); (b) Modal de validación al submit | `Form`+`FormField` es más Material/Flutter-idiomático pero requiere `GlobalKey<FormState>` y `validator: (v) => ...` per campo — overkill para MVP. Disabling submit + inline error banner ("Completá todos los slots") es suficiente para alfa. Si en QA piden detalle field-by-field, se migra. |
| 17 | Exercise picker | `Future<Exercise?> _pickExercise(BuildContext, WidgetRef)` que abre `showModalBottomSheet<Exercise>` con `isScrollControlled: true`. Body: `Column(TextField search + Expanded(ListView.builder de exercises filtered))`. Tap → `Navigator.pop(context, exercise)`. | (a) Nueva ruta `/workout/exercise-picker`; (b) Dropdown inline; (c) Bottom sheet sin search | Bottom sheet con search es UX estándar mobile + reusa `exercisesProvider` ya cargado (sin red extra). Search filtra en memoria sobre `Exercise.name` y `Exercise.muscleGroup`. Tap devuelve el `Exercise` completo — el slot denormaliza `exerciseName` y `muscleGroup` al asignar. |
| 18 | Default `visibility` para planes creados | `RoutineVisibility.private` (no se exhibe toggle en MVP) | (a) Toggle UI public/private/shared; (b) Default `shared` | `private` cumple la regla `visibility in ['private', 'shared']` y es la opción más conservadora (sólo `assignedBy` y `assignedTo` leen). Toggle no aporta valor MVP — el PF crea planes para UN alumno; "shared" implica un caso de uso (multi-atleta) que no existe en Fase 5. |
| 19 | `_ActiveAlumnoCard` tap UX preservando "TERMINAR VÍNCULO" | Wrap la card en `InkWell(onTap: () => context.push('/coach/athlete/${link.athleteId}'))`. Mantener el `OutlinedButton` "TERMINAR VÍNCULO" interno — el `GestureDetector`/`InkWell` interno del botón intercepta el tap antes que llegue al outer InkWell. NO usar `GestureDetector.behavior: opaque` ni `StatefulBuilder`. | (a) `Stack` con `GestureDetector` separados; (b) Tap area limitada al header solamente | Flutter propaga el tap al child más interno primero (`OutlinedButton` consume); el outer `InkWell` solo recibe taps en zonas sin botón. Patrón validado en `RoutineCard` (tile tap navigates, action button inside stops propagation). Más simple y sin `StatefulBuilder` extra. |
| 20 | Router insertion points | Dos nuevas rutas: (a) bajo `GoRoute('/coach')`: sub-route `'athlete/:athleteId'` → ruta resultante `/coach/athlete/:athleteId`. (b) bajo `GoRoute('/workout')`: sub-route `'routine-editor/:athleteId'` → ruta resultante `/workout/routine-editor/:athleteId`. Ambas dentro del ShellRoute (bottom bar visible). | (a) RoutineEditor top-level outside ShellRoute (immersive); (b) RoutineEditor bajo `/coach` también | El editor mantiene bottom bar — el PF puede tener que pausar y volver. Consistencia con `RoutineDetailScreen` que también vive bajo `/workout`. Path semántico: el editor crea un Routine, vive en /workout. AthleteDetailScreen vive en /coach (es vista trainer-side). |
| 21 | Workout screen replacement | Eliminar el private `_TuRutinaSection` widget completamente de `workout_screen.dart`. Importar `MiPlanSection` desde `presentation/widgets/`. Reordenar para que `MiPlanSection` quede ARRIBA de `PlantillasSection` (la rutina asignada es prioritaria sobre el catálogo). | (a) Mantener `_TuRutinaSection` como fallback si no hay uid; (b) Dejar `MiPlanSection` debajo de `PlantillasSection` | El placeholder ya no tiene razón de existir — `MiPlanSection` cubre todos los estados (empty / loading / error / data) con copy más rico. Reordenar prioriza la sección útil al usuario logueado. `HistorialSection` queda al final (es secundaria). |
| 22 | PR1 vs PR2 boundary — file list locked | PR1: `routine_repository.dart` (extend), `assigned_routine_providers.dart` (new), `firestore.rules`, `firestore.indexes.json`, 2 archivos de tests. PR2: `mi_plan_section.dart`, `routine_editor_screen.dart`, `athlete_detail_screen.dart`, `workout_screen.dart` (mod), `routine_detail_screen.dart` (mod), `trainer_coach_view.dart` (mod), `router.dart` (mod), tests widget + router. | (a) Mezclar UI con data en un solo PR; (b) Splittear PR2 en 2 sub-PRs (UI atleta vs UI trainer) | El boundary data/UI es atómico y testeable. Cada PR cierra unidad lógica. Split adicional de PR2 (atleta vs trainer) es viable si LOC > 400, pero MVP target ~350-450 — monitorear en apply. |
| 23 | Test override strategy | Tests de widget PR2 override `assignedRoutinesProvider` y `userPublicProfileProvider` DIRECTAMENTE en `ProviderScope.overrides` con fakes/fixtures. NO se mockea `RoutineRepository` ni `FirebaseFirestore` para tests de widget — esos quedan cubiertos en PR1 con `fake_cloud_firestore`. | (a) Override de bajo nivel (`firestoreProvider`) en cada widget test; (b) Mocks completos `mockito` | Provider-level mocking aísla la UI de la data layer — mismo patrón que `coach-discovery` Decision #23. Tests son rápidos, focused, no requieren build de freezed routine completo. Fixtures simples (1-2 Routine objects) cubren happy/empty/error/terminated. |
| 24 | Tech debt `sharedWithTrainer` | NO se agrega en esta etapa. Documentar en roadmap como pre-req de Etapa 6. `AthleteDetailScreen` MVP solo muestra header + planes + CTA — no historial / sesiones. | (a) Agregar `sharedWithTrainer: bool` ahora (default false); (b) Stub UI toggle ya | El PF en Etapa 4 solo necesita acceso a sus propios planes (filtra por `assignedBy`). `sharedWithTrainer` es campo del modelo `TrainerLink` que habilita Etapa 6 (PF ve sesiones del atleta) — agregarlo prematuro sin consumer es noise. Anotar en roadmap "antes de Etapa 6". |
| 25 | Strict TDD test isolation: Firestore rules | Tests de la nueva rule `allow create` se cubren en `scripts/rules_test/rules.test.js` (emulator-based). Tests del repo (`listAssignedTo`, `createAssigned`) usan `fake_cloud_firestore` que NO enforza rules — verifican query shape y persistence, no autorización. | (a) Marcar SCENARIOs de rules como skip; (b) Stub rules en fake | Mismo patrón establecido en Etapa 2 (Decision #21). El rules.test.js corre en CI con emulator + es la única forma fiable de validar la rule. Repo tests cubren happy path data layer. |

## File Layout per PR

### PR1 — `feat/coach-plans-mobile-data` (~250-300 LOC)

**New files**:

| Path | Description |
|------|-------------|
| `lib/features/workout/application/assigned_routine_providers.dart` | `assignedRoutinesProvider(athleteId)` (FutureProvider.autoDispose.family). Depends on `routineRepositoryProvider` existente. |
| `test/features/workout/data/routine_repository_assigned_test.dart` | Tests de `listAssignedTo` (query shape, ordering, limit, empty result) y `createAssigned` (persistencia, id devuelto, payload shape). `fake_cloud_firestore`. SCENARIO-432..~438. |
| `test/features/workout/application/assigned_routine_providers_test.dart` | Tests del provider: happy path (devuelve lista), error propagado, autoDispose recompute al re-watch. SCENARIO-~439..~441. |

**Modified files**:

| Path | Change |
|------|--------|
| `lib/features/workout/data/routine_repository.dart` | Agregar `Future<List<Routine>> listAssignedTo(String athleteId)` + `Future<Routine> createAssigned(Routine routine)`. Sin breaking change en `listAll()`/`getById()`. |
| `firestore.rules` | En el bloque `match /routines/{routineId}`: cambiar `allow write: if false` por `allow create: if [conditions]` + `allow update, delete: if false`. Ver bloque exacto abajo. |
| `firestore.indexes.json` | Agregar entrada `routines` collection con fields `assignedTo (ASC) + source (ASC) + createdAt (DESC)`. |
| `scripts/rules_test/rules.test.js` | Casos: PF crea OK (assignedBy == auth.uid, source == 'trainer-assigned', visibility ∈ {private, shared}); athlete crea para sí mismo NO (assignedBy != auth.uid); PF crea con visibility 'public' NO; anon crea NO; PF intenta update (denied); PF intenta delete (denied). SCENARIO-~442..~445. |

**NOT modified in PR1**:
- Modelos `Routine` / `RoutineDay` / `RoutineSlot` / enums — sin cambios.
- `routine_providers.dart` — sin cambios (los providers existentes no se tocan; el nuevo provider vive en `assigned_routine_providers.dart`).
- Cualquier archivo UI.

### PR2 — `feat/coach-plans-mobile-ui` (~350-450 LOC)

**New files**:

| Path | Description |
|------|-------------|
| `lib/features/workout/presentation/widgets/mi_plan_section.dart` | `MiPlanSection` ConsumerWidget + private `_PlanCard` + estados loading/error/empty. |
| `lib/features/workout/presentation/routine_editor_screen.dart` | `RoutineEditorScreen` StatefulWidget con state local (`_EditableDay`, `_EditableSlot`). Submit → `createAssigned`. Exercise picker via `showModalBottomSheet`. |
| `lib/features/coach/presentation/athlete_detail_screen.dart` | `AthleteDetailScreen` ConsumerWidget. Header inline + lista planes + CTA "CREAR PLAN". |
| `test/features/workout/presentation/widgets/mi_plan_section_test.dart` | Widget tests: loading, empty, populated (1 plan), populated (multi-plan latest-first), chip "Plan finalizado" cuando link terminated, tap navega a /workout/routine/:id. SCENARIO-~446..~451. |
| `test/features/workout/presentation/routine_editor_screen_test.dart` | Widget tests: render inicial, agregar día, agregar slot, abrir exercise picker, seleccionar exercise, validation disabled submit hasta válido, submit dispara `createAssigned`, SnackBar success + pop. SCENARIO-~452..~459. |
| `test/features/coach/presentation/athlete_detail_screen_test.dart` | Widget tests: header renderiza, lista filtrada por assignedBy, CTA navega a editor. SCENARIO-~460..~462. |
| `test/app/router_coach_plans_test.dart` (extiende existente o nuevo) | Router tests: `/coach/athlete/:athleteId` resuelve, `/workout/routine-editor/:athleteId` resuelve, bottom bar visible en ambas. SCENARIO-~463..~465. |

**Modified files**:

| Path | Change |
|------|--------|
| `lib/features/workout/workout_screen.dart` | Reemplazar `_TuRutinaSection` con `MiPlanSection`. Reordenar: `MiPlanSection` arriba, `PlantillasSection` debajo, `HistorialSection` al final. Eliminar el private `_TuRutinaSection` class. |
| `lib/features/workout/presentation/routine_detail_screen.dart` | En `_RoutineDetailContent` agregar `_AssignedByChip` condicional dentro del `_HeroStrip`, debajo del `_DayChipBadge`. Nuevo private widget `_AssignedByChip` que watchea `userPublicProfileProvider`. |
| `lib/features/coach/trainer_coach_view.dart` | Wrap `_ActiveAlumnoCard` body en `InkWell(onTap: ...)`. Botón "TERMINAR VÍNCULO" interno mantiene su propio tap area (no propaga). |
| `lib/app/router.dart` | Agregar sub-route `'athlete/:athleteId'` bajo `GoRoute('/coach')` y sub-route `'routine-editor/:athleteId'` bajo `GoRoute('/workout')`. Imports de los 2 nuevos screens. |

**NOT modified in PR2**:
- Cualquier archivo de data layer (entregado en PR1).
- `firestore.rules` / `firestore.indexes.json` (entregado en PR1).
- Modelos / enums / `session_player_screen.dart` / `post_workout_summary_screen.dart`.
- `TrainerLinkRepository` / `trainer_link.dart`.

## Provider Design

    ┌─────────────────────────────────────────────────────────────┐
    │ assigned_routine_providers.dart (PR1)                       │
    │                                                             │
    │ assignedRoutinesProvider                                    │
    │   FutureProvider.autoDispose.family<List<Routine>, String>  │
    │     (athleteId)                                             │
    │   ↓ ref.watch(routineRepositoryProvider) [existente]        │
    │                                                             │
    │   ← invalidated by RoutineEditorScreen tras createAssigned  │
    │   ← consumed by MiPlanSection (uid del atleta logueado)     │
    │   ← consumed by AthleteDetailScreen (uid del alumno target) │
    └─────────────────────────────────────────────────────────────┘

**No nuevos providers privados al feature**. `userPublicProfileProvider` y `currentAthleteLinkProvider` son existentes (Etapas 2 y 3) — se consumen como están.

### Widget test override strategy

```dart
ProviderScope(
  overrides: [
    // Happy path:
    assignedRoutinesProvider(athleteId).overrideWith((ref) async => _fakePlans),
    userPublicProfileProvider(trainerUid).overrideWith((ref) async => _fakeTrainerProfile),
    currentAthleteLinkProvider.overrideWith((ref) async => _activeLink),
    // Error path (selectively):
    // assignedRoutinesProvider(athleteId).overrideWith((ref) => throw Exception('boom')),
    // Terminated path:
    // currentAthleteLinkProvider.overrideWith((ref) async => _terminatedLink),
  ],
  child: MaterialApp(home: MiPlanSection()),
)
```

**Key rule**: tests overriden `assignedRoutinesProvider` DIRECTAMENTE (Provider-level mocking) en vez de mockear `routineRepositoryProvider`. Esto aísla widget tests del data layer. Para `RoutineEditorScreen` submit test, se override `routineRepositoryProvider` con un fake que captura el Routine pasado a `createAssigned` y lo verifica.

## Widget Tree — `MiPlanSection`

    MiPlanSection (ConsumerWidget)
    └── build:
        final uid = ref.watch(authStateChangesProvider).valueOrNull?.uid;
        if (uid == null) return SizedBox.shrink();

        final plansAsync = ref.watch(assignedRoutinesProvider(uid));
        final linkAsync = ref.watch(currentAthleteLinkProvider);

        Column(crossAxis: start)
        ├── Text('MI PLAN', titleMedium)               ← mismo style que PlantillasSection
        ├── SizedBox(height: 12)
        └── switch (plansAsync):
            │
            loading → _LoadingSkeleton (Center + spinner palette.accent)
            error   → _ErrorState (Text muted + retry button → ref.invalidate)
            data    → plans.isEmpty
                          ? Text('No tenés rutina asignada todavía.', muted)
                          : Column(children: plans.map((p) => _PlanCard(
                                routine: p,
                                isTerminated: _isLinkTerminated(linkAsync, p),
                              )))

    bool _isLinkTerminated(AsyncValue<TrainerLink?> linkAsync, Routine p) {
      final link = linkAsync.valueOrNull;
      return link != null
          && link.status == LinkStatus.terminated
          && link.trainerId == p.assignedBy;
    }

    _PlanCard (ConsumerWidget)
    └── InkWell(onTap: () => context.push('/workout/routine/${routine.id}'))
        └── Container(decoration: card style — palette.bgCard + border)
            └── Padding(EdgeInsets.all(14))
                └── Row
                    ├── Expanded(Column crossAxis: start
                    │     ├── Text(routine.name, titleMedium)
                    │     ├── SizedBox(height: 4)
                    │     ├── _TrainerByline(uid: routine.assignedBy)   ← watch userPublicProfileProvider
                    │     └── if (isTerminated) [
                    │            SizedBox(height: 6),
                    │            _FinalizadoChip(),                       ← chip muted
                    │         ]
                    │   )
                    └── Icon(TreinoIcon.chevronRight, muted)

## Widget Tree — `RoutineEditorScreen`

    RoutineEditorScreen extends StatefulWidget
      final String athleteId;
    │
    └── _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen>
        │
        │ State local:
        │   final _nameController = TextEditingController();
        │   final _splitController = TextEditingController();
        │   int _daysPerWeek = 3;
        │   ExperienceLevel _level = ExperienceLevel.beginner;
        │   final List<_EditableDay> _days = [_EditableDay.initial(1)];
        │   bool _submitting = false;
        │   String? _errorMessage;
        │
        ├── _canSubmit getter (validation: name + split + ≥1 day + cada día ≥1 slot + cada slot con exercise + sets/reps válidos)
        │
        └── build:
            Scaffold(
              appBar: AppBar(title: 'Crear plan', backgroundColor: palette.bg),
              body: ListView(
                padding: EdgeInsets.all(20),
                children: [
                  // ── Metadata ────────────────────────────────────────
                  _LabeledField(label: 'NOMBRE', child: TextField(_nameController)),
                  SizedBox(height: 16),
                  _LabeledField(label: 'SPLIT (e.g. PPL)', child: TextField(_splitController)),
                  SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _DaysPerWeekStepper(value: _daysPerWeek, onChange: ...)),
                    SizedBox(width: 12),
                    Expanded(child: _LevelDropdown(value: _level, onChange: ...)),
                  ]),
                  SizedBox(height: 24),

                  // ── Días ─────────────────────────────────────────────
                  Text('DÍAS', titleMedium),
                  SizedBox(height: 12),
                  ..._days.asMap().entries.map((entry) => _EditableDayTile(
                    day: entry.value,
                    onAddSlot: () => _addSlotTo(entry.key),
                    onRemoveSlot: (slotIdx) => _removeSlotFrom(entry.key, slotIdx),
                    onPickExercise: (slotIdx) => _pickExerciseFor(entry.key, slotIdx),
                    onSlotFieldChange: (slotIdx, field, value) => _updateSlot(...),
                    onRemoveDay: () => _removeDay(entry.key),
                  )),
                  SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _addDay,
                    child: Text('+ AGREGAR DÍA'),
                  ),

                  // ── Submit ──────────────────────────────────────────
                  SizedBox(height: 32),
                  if (_errorMessage != null) _InlineError(_errorMessage),
                  ElevatedButton(
                    onPressed: _canSubmit && !_submitting ? _submit : null,
                    child: _submitting
                        ? CircularProgressIndicator()
                        : Text('CREAR Y ASIGNAR'),
                  ),
                ],
              ),
            )

    _EditableDayTile (StatelessWidget)
    └── ExpansionTile(
          title: Text('DÍA ${day.dayNumber} — ${day.name}'),
          children: [
            TextField(controller: day.nameController),  ← edita day.name
            ...day.slots.asMap().entries.map((slotEntry) => _EditableSlotRow(
              slot: slotEntry.value,
              onPickExercise: () => onPickExercise(slotEntry.key),
              onRemove: () => onRemoveSlot(slotEntry.key),
            )),
            OutlinedButton(onPressed: onAddSlot, child: Text('+ AGREGAR EJERCICIO')),
            if (day.dayNumber > 1) TextButton(onPressed: onRemoveDay, child: Text('Quitar día')),
          ],
        )

    _EditableSlotRow (StatelessWidget)
    └── Column(
          children: [
            InkWell(onTap: onPickExercise, child: Text(slot.exercise?.name ?? 'Elegir ejercicio...')),
            Row(
              children: [
                _NumberField(label: 'SETS', value: slot.targetSets),
                _NumberField(label: 'REPS MIN', value: slot.targetRepsMin),
                _NumberField(label: 'REPS MAX', value: slot.targetRepsMax),
                _NumberField(label: 'REST (s)', value: slot.restSeconds),
              ],
            ),
            IconButton(icon: TreinoIcon.trash, onPressed: onRemove),
          ],
        )

### Submit logic

    Future<void> _submit() async {
      setState(() {
        _submitting = true;
        _errorMessage = null;
      });

      try {
        final uid = ref.read(authStateChangesProvider).valueOrNull?.uid;
        if (uid == null) throw Exception('No auth');

        final routine = Routine(
          id: '',                                                // Firestore generates
          name: _nameController.text.trim(),
          split: _splitController.text.trim(),
          level: _level,
          days: _days.map((d) => d.toRoutineDay()).toList(),
          source: RoutineSource.trainerAssigned,
          assignedBy: uid,
          assignedTo: widget.athleteId,
          visibility: RoutineVisibility.private,
        );

        final saved = await ref.read(routineRepositoryProvider).createAssigned(routine);

        if (!mounted) return;
        ref.invalidate(assignedRoutinesProvider(widget.athleteId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Plan creado y asignado.')),
        );
        context.pop();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _errorMessage = 'No pudimos crear el plan. Probá de nuevo.';
        });
      }
    }

### Exercise picker bottom sheet

    Future<Exercise?> _pickExercise() async {
      return await showModalBottomSheet<Exercise>(
        context: context,
        isScrollControlled: true,
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (sheetCtx) {
          return _ExercisePickerSheet();  // Consumer widget that watches exercisesProvider
        },
      );
    }

    _ExercisePickerSheet (ConsumerStatefulWidget)
    └── State con String _searchQuery = ''
    └── build:
        final exercisesAsync = ref.watch(exercisesProvider);
        Column(
          children: [
            _DragHandle,
            Padding(child: TextField(onChanged: (v) => setState(() => _searchQuery = v))),
            Expanded(
              child: exercisesAsync.when(
                loading: ...,
                error: ...,
                data: (all) {
                  final filtered = all.where((e) =>
                    _searchQuery.isEmpty
                    || e.name.toLowerCase().contains(_searchQuery.toLowerCase())
                    || e.muscleGroup.toLowerCase().contains(_searchQuery.toLowerCase())
                  ).toList();
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(filtered[i].name),
                      subtitle: Text(filtered[i].muscleGroup),
                      onTap: () => Navigator.pop(context, filtered[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        )

### `_EditableDay` / `_EditableSlot` mutable classes

```dart
class _EditableDay {
  _EditableDay({
    required this.dayNumber,
    required String initialName,
    List<_EditableSlot>? initialSlots,
  })  : nameController = TextEditingController(text: initialName),
        slots = initialSlots ?? [_EditableSlot.initial()];

  factory _EditableDay.initial(int dayNumber) =>
      _EditableDay(dayNumber: dayNumber, initialName: 'Día $dayNumber');

  int dayNumber;
  final TextEditingController nameController;
  final List<_EditableSlot> slots;

  String get name => nameController.text.trim();

  RoutineDay toRoutineDay() => RoutineDay(
        dayNumber: dayNumber,
        name: name,
        slots: slots.map((s) => s.toRoutineSlot()).toList(),
      );

  void dispose() {
    nameController.dispose();
    for (final s in slots) {
      s.dispose();
    }
  }
}

class _EditableSlot {
  _EditableSlot({
    this.exercise,
    this.targetSets = 3,
    this.targetRepsMin = 8,
    this.targetRepsMax = 12,
    this.restSeconds = 60,
  });

  factory _EditableSlot.initial() => _EditableSlot();

  Exercise? exercise;
  int targetSets;
  int targetRepsMin;
  int targetRepsMax;
  int restSeconds;

  bool get isValid =>
      exercise != null
      && targetSets >= 1
      && targetRepsMin >= 1
      && targetRepsMax >= targetRepsMin;

  RoutineSlot toRoutineSlot() => RoutineSlot(
        exerciseId: exercise!.id,
        exerciseName: exercise!.name,
        muscleGroup: exercise!.muscleGroup,
        targetSets: targetSets,
        targetRepsMin: targetRepsMin,
        targetRepsMax: targetRepsMax,
        restSeconds: restSeconds,
      );

  void dispose() {/* no controllers — los NumberField son StatefulWidgets autocontenidos */}
}
```

## Widget Tree — `AthleteDetailScreen`

    AthleteDetailScreen extends ConsumerWidget
      final String athleteId;
    │
    └── build:
        final pubAsync = ref.watch(userPublicProfileProvider(athleteId));
        final plansAsync = ref.watch(assignedRoutinesProvider(athleteId));
        final trainerUid = ref.watch(authStateChangesProvider).valueOrNull?.uid;

        return Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 100),  ← bottom inset para el CTA fijo
              children: [
                _BackBar,                                       ← reusa pattern de RoutineDetailScreen
                SizedBox(height: 8),
                _AthleteHeader(pubAsync: pubAsync),              ← inline, no reusa _UserHeader private
                SizedBox(height: 24),
                Text('PLANES ASIGNADOS', titleMedium),
                SizedBox(height: 12),
                plansAsync.when(
                  loading: () => _LoadingSkeleton,
                  error: (_, __) => _ErrorState(retry: ...),
                  data: (allPlans) {
                    final myPlans = allPlans.where((p) => p.assignedBy == trainerUid).toList();
                    if (myPlans.isEmpty) {
                      return Text('Todavía no le asignaste planes.', muted);
                    }
                    return Column(children: myPlans.map((p) => _PlanCard(routine: p)).toList());
                  },
                ),
              ],
            ),
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: ElevatedButton(
                onPressed: () => context.push('/workout/routine-editor/$athleteId'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  minimumSize: Size.fromHeight(52),
                ),
                child: Text('CREAR PLAN'),
              ),
            ),
          ],
        );

    _AthleteHeader (StatelessWidget)
    └── Row(
          children: [
            // Avatar 56x56 (placeholder TreinoIcon.user si avatarUrl null)
            Container(width: 56, height: 56, decoration: ..., child: ...),
            SizedBox(width: 14),
            Expanded(Column crossAxis: start
              ├── Text(pubAsync.valueOrNull?.displayName ?? '...', titleLarge)
              └── Text('Tu alumno', muted)
            ),
          ],
        )

## Firestore Rule Block (PR1)

Reemplaza el `allow write: if false` actual en `firestore.rules` líneas 56-57:

```javascript
match /routines/{routineId} {
  // Read rule existente (Etapa 1) — sin cambios.
  allow read: if request.auth != null
              && (!('visibility' in resource.data)
                  || resource.data.visibility == 'public'
                  || resource.data.visibility == 'shared'
                  || request.auth.uid == resource.data.assignedTo
                  || request.auth.uid == resource.data.assignedBy);

  // Create: solo PF crea planes asignados.
  // - assignedBy DEBE ser el caller (no se puede crear plan a nombre de otro).
  // - source DEBE ser 'trainer-assigned' (planes system/user-created van por seed).
  // - visibility DEBE ser 'private' o 'shared' (no se crea 'public' desde cliente).
  // - assignedTo DEBE ser un string no-vacío.
  // NO se valida estructura completa del Routine (days/slots) — defer al cliente.
  // NO se valida rol del caller — defer al cliente vía TrainerCoachView guard.
  allow create: if request.auth != null
                && request.resource.data.assignedBy == request.auth.uid
                && request.resource.data.source == 'trainer-assigned'
                && request.resource.data.visibility in ['private', 'shared']
                && request.resource.data.assignedTo is string
                && request.resource.data.assignedTo.size() > 0;

  // Update / Delete defer a Etapa 7 (advanced editing).
  allow update, delete: if false;
}
```

## Firestore Composite Index (PR1)

Agregar al array `indexes` en `firestore.indexes.json`:

```json
{
  "collectionGroup": "routines",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "assignedTo", "order": "ASCENDING" },
    { "fieldPath": "source", "order": "ASCENDING" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```

Deploy con `firebase deploy --only firestore:indexes`. Coordinar timing con la rule (`firestore:rules`) — el index puede tardar 1-10 min en propagarse. Si la rule se deploya antes que el index, la primera query `listAssignedTo` puede devolver `failed-precondition` hasta que el index esté ready. **Acción mitigación**: deploy index PRIMERO, esperar status "ready" en Firebase Console, deploy rule después. Documentar en PR1 description.

## `createdAt` field convention

El modelo `Routine` actual NO tiene un campo `createdAt` explícito en su definición (`lib/features/workout/domain/routine.dart`). El query usa `orderBy('createdAt', descending: true)` que asume el campo presente en el documento Firestore.

**Decisión operativa para `createAssigned`**: el método REPO agrega `createdAt: FieldValue.serverTimestamp()` al JSON antes de hacer `_collection.add(...)`. NO se modifica el modelo (no se agrega field a freezed) — `createdAt` queda como un campo "side metadata" que vive solo en Firestore y NO se deserializa en `Routine.fromJson` (freezed `fromJson` ignora campos no declarados).

```dart
Future<Routine> createAssigned(Routine routine) async {
  // Validations (defensa client-side — rules son la fuente de verdad):
  if (routine.assignedBy == null || routine.assignedBy!.isEmpty) {
    throw ArgumentError('assignedBy is required');
  }
  if (routine.assignedTo == null || routine.assignedTo!.isEmpty) {
    throw ArgumentError('assignedTo is required');
  }
  if (routine.source != RoutineSource.trainerAssigned) {
    throw ArgumentError('source must be trainerAssigned');
  }

  final json = {
    ...routine.toJson(),
    'createdAt': FieldValue.serverTimestamp(),
  };
  // Remove the empty 'id' field (Firestore generates the id).
  json.remove('id');

  final ref = await _collection.add(json);
  return routine.copyWith(id: ref.id);
}
```

**Tradeoff**: `createdAt` no es leíble desde el modelo `Routine` en Dart. Esto está OK porque la única consumer del field es la query (`orderBy`). Si en una etapa futura se necesita exhibir "creado el X" en UI, se agrega el campo a freezed entonces (sin breaking — los docs viejos lo tendrán; los más viejos seedeados sin `createdAt` se ordenarán juntos al final). **Para PR1**: `listAssignedTo` puede devolver docs sin `createdAt` (legacy o seed) en orden indeterminado — aceptable porque ningún plan legacy tiene `source == trainer-assigned`.

## Router Insertions (PR2)

En `lib/app/router.dart`:

```dart
// Sub-route bajo GoRoute('/workout') — junto a routine/:routineId y exercise/:exerciseId.
GoRoute(
  path: 'routine-editor/:athleteId',
  pageBuilder: (context, state) {
    final athleteId = state.pathParameters['athleteId']!;
    return _noAnim(RoutineEditorScreen(athleteId: athleteId));
  },
),

// Sub-route bajo GoRoute('/coach') — junto a trainer/:uid.
GoRoute(
  path: 'athlete/:athleteId',
  pageBuilder: (context, state) {
    final athleteId = state.pathParameters['athleteId']!;
    return _noAnim(AthleteDetailScreen(athleteId: athleteId));
  },
),
```

Imports: `routine_editor_screen.dart` y `athlete_detail_screen.dart`.

## Testing Strategy

| Layer | What | Approach | PR |
|-------|------|----------|-----|
| Repo | `listAssignedTo` returns plans filtered + ordered | `fake_cloud_firestore` seed 3-4 docs (mix de source y assignedTo), assert resultado | PR1 |
| Repo | `listAssignedTo` empty cuando no hay matches | `fake_cloud_firestore` con docs irrelevantes | PR1 |
| Repo | `listAssignedTo` respeta limit 20 | `fake_cloud_firestore` con 25 docs, assert length 20 | PR1 |
| Repo | `createAssigned` persiste y devuelve Routine con id no-vacío | `fake_cloud_firestore` | PR1 |
| Repo | `createAssigned` rechaza si `assignedBy == null` | unit assertion | PR1 |
| Repo | `createAssigned` rechaza si `source != trainerAssigned` | unit assertion | PR1 |
| Repo | `createAssigned` agrega `createdAt` serverTimestamp al JSON | inspect doc post-add | PR1 |
| Provider | `assignedRoutinesProvider` happy path devuelve list | container override repo | PR1 |
| Provider | `assignedRoutinesProvider` error propaga | container override repo throw | PR1 |
| Provider | `assignedRoutinesProvider` autoDispose reset | container.refresh, watch | PR1 |
| Rules | PF crea plan OK (emulator) | rules.test.js | PR1 |
| Rules | athlete intenta crear plan con assignedBy = su uid (denied) | rules.test.js | PR1 |
| Rules | PF crea con visibility 'public' (denied) | rules.test.js | PR1 |
| Rules | anon intenta crear (denied) | rules.test.js | PR1 |
| Rules | PF intenta update (denied) | rules.test.js | PR1 |
| Widget | `MiPlanSection`: loading | override provider AsyncLoading | PR2 |
| Widget | `MiPlanSection`: empty | override provider AsyncData([]) | PR2 |
| Widget | `MiPlanSection`: error | override provider AsyncError | PR2 |
| Widget | `MiPlanSection`: 1 plan render con trainer name | overrides | PR2 |
| Widget | `MiPlanSection`: multi-plan latest-first | overrides, assert orden | PR2 |
| Widget | `MiPlanSection`: chip "Plan finalizado" cuando link terminated && matchea trainerId | overrides | PR2 |
| Widget | `MiPlanSection`: tap navega a /workout/routine/:id | router test wrapper | PR2 |
| Widget | `RoutineEditorScreen`: render inicial 1 día con 1 slot | sin override | PR2 |
| Widget | `RoutineEditorScreen`: agregar día incrementa lista | tap button, assert | PR2 |
| Widget | `RoutineEditorScreen`: agregar slot al día N | tap button, assert | PR2 |
| Widget | `RoutineEditorScreen`: exercise picker abre + filter funciona | tap, type, assert filtered count | PR2 |
| Widget | `RoutineEditorScreen`: seleccionar exercise denormaliza name+muscleGroup en slot | tap exercise, assert state | PR2 |
| Widget | `RoutineEditorScreen`: submit disabled cuando inválido | initial state, assert disabled | PR2 |
| Widget | `RoutineEditorScreen`: submit dispara createAssigned con Routine correcto | mock repo, tap submit, assert call | PR2 |
| Widget | `RoutineEditorScreen`: submit success → SnackBar + pop | router test, assert pop | PR2 |
| Widget | `RoutineEditorScreen`: submit error → SnackBar + state restored | mock repo throw | PR2 |
| Widget | `AthleteDetailScreen`: header renderiza con displayName | override pub provider | PR2 |
| Widget | `AthleteDetailScreen`: lista filtrada por assignedBy == trainerUid | overrides | PR2 |
| Widget | `AthleteDetailScreen`: CTA navega a editor | router test | PR2 |
| Router | `/coach/athlete/:athleteId` resuelve | router test | PR2 |
| Router | `/workout/routine-editor/:athleteId` resuelve | router test | PR2 |
| Router | `_ActiveAlumnoCard` tap → /coach/athlete/:athleteId | wrap TrainerCoachView en router | PR2 |

Total esperado: ~34 SCENARIOs split ~14/PR1 + ~20/PR2 — alineado con proposal range 432..~465.

## Strict TDD Plan

### PR1 — RED → GREEN order

1. **RED**: `routine_repository_assigned_test.dart` — write tests para `listAssignedTo` (query shape, ordering, limit) y `createAssigned` (persist + return + validation).
2. **GREEN**: extender `routine_repository.dart` con los dos métodos.
3. **RED**: `assigned_routine_providers_test.dart` — write tests para el provider (happy/error/autoDispose).
4. **GREEN**: crear `assigned_routine_providers.dart`.
5. **RED**: `scripts/rules_test/rules.test.js` — write cases para la nueva rule (PF OK, athlete denied, visibility public denied, anon denied, update denied, delete denied).
6. **GREEN**: modificar `firestore.rules` con el nuevo bloque `allow create` y `allow update, delete: if false`.
7. Modificar `firestore.indexes.json` con el composite index.
8. Gate: `flutter analyze` 0 issues + `dart format .` + `flutter test` green + `rules_test/rules.test.js` green (emulator). Deploy del index ANTES del deploy de la rule (manual; documentar en PR description).

### PR2 — RED → GREEN order (asume PR1 merged & rebased)

9. **RED**: `mi_plan_section_test.dart` — write tests todos los estados.
10. **GREEN**: implementar `mi_plan_section.dart` + private `_PlanCard`.
11. **RED**: `routine_editor_screen_test.dart` — write tests render, add day/slot, picker, validation, submit.
12. **GREEN**: implementar `routine_editor_screen.dart` + clases mutables `_EditableDay`/`_EditableSlot` + `_ExercisePickerSheet`.
13. **RED**: `athlete_detail_screen_test.dart` — write tests header, lista filtrada, CTA nav.
14. **GREEN**: implementar `athlete_detail_screen.dart`.
15. **RED**: router tests para las 2 rutas nuevas.
16. **GREEN**: agregar sub-routes en `router.dart`.
17. **RED**: test para `_ActiveAlumnoCard` tap (extender `trainer_coach_view_test.dart` o nuevo).
18. **GREEN**: wrap `_ActiveAlumnoCard` con `InkWell` en `trainer_coach_view.dart`.
19. **RED**: test para chip "Asignado por <PF>" en `routine_detail_screen_test.dart` (extender existente).
20. **GREEN**: agregar `_AssignedByChip` en `_HeroStrip`.
21. **RED**: actualizar `workout_screen_test.dart` (si existe) — esperar `MiPlanSection` en lugar de placeholder.
22. **GREEN**: reemplazar `_TuRutinaSection` con `MiPlanSection` en `workout_screen.dart`.
23. Gate: `flutter analyze` 0 issues + `dart format .` + `flutter test` green.

Strict TDD: ningún production code antes que su test rojo correspondiente.

## Risks (incluyendo NUEVOS descubiertos en design)

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| (explore) PR sizing total ~600-800 LOC | Med | Chained PRs locked en este design. PR2 target ~350-450 — si supera 400, considerar split adicional (atleta-side vs trainer-side) — decisión a tomar en apply. |
| (explore) `RoutineEditorScreen` complexity con mutable state | Med | Clases locales `_EditableDay`/`_EditableSlot` documentadas + Strict TDD obliga test-first. Patrón validado en `_CreatePostBodyState`. |
| (explore) Rules sin cross-collection role lookup | Low (atleta forging tokens es escenario marginal) | Documentado en Decision #5. Defensa client-side via `TrainerCoachView` role guard. |
| (explore) Composite index `failed-precondition` | High si se olvida | Index proactivo en `firestore.indexes.json` (Decision #6). Documentar en PR1 description: deploy index ANTES de deploy de rule. |
| **NEW**: `createdAt` ausente en el modelo `Routine` freezed — query `orderBy('createdAt')` puede romper en docs legacy | Med | Documentado en "createdAt field convention". Legacy docs (system/seed) NO tienen `source == 'trainer-assigned'`, por lo que `listAssignedTo` nunca los devuelve. Si en el futuro se reusa el query para otros source, se debe agregar `createdAt` al modelo. |
| **NEW**: `Routine.toJson()` incluye `'id': ''` (string vacío) — Firestore lo persiste como campo `id == ''` en el doc | Med | `createAssigned` hace `json.remove('id')` antes del `add()`. El doc id real lo provee Firestore. `routine.copyWith(id: ref.id)` se devuelve al caller. |
| **NEW**: Si el atleta tiene dos trainers activos en el futuro (Etapa 7), el badge "Plan finalizado" basado en `currentAthleteLinkProvider` (un solo link) puede mostrar info inconsistente | Low (MVP es 1 trainer activo) | Mitigación: documentar en Decision #9 como MVP-only. Etapa 7 deberá refactor a `listLinksByAthlete` y cruzar por `trainerId`. |
| **NEW**: `_ActiveAlumnoCard` tap propagation vs button click — falla en algunos materials sin `behavior: opaque` | Low | Decision #19: `InkWell` outer + `OutlinedButton` inner ya tiene su propio ink response que captura el tap. Si en QA aparece edge case, agregar `GestureDetector(behavior: opaque)` al botón interno. Validar con test específico en PR2. |
| **NEW**: `RoutineEditorScreen` `Scaffold` propio choca con `_ShellScaffold` de la ShellRoute (doble Scaffold) | Med | El editor vive bajo `/workout/routine-editor/:athleteId` (sub-route bajo ShellRoute). El `_ShellScaffold` provee bottom bar; el `Scaffold` del editor puede vivir DENTRO porque Flutter permite Scaffolds anidados (es válido aunque atípico). Alternativa: NO usar `Scaffold` propio (igual que `RoutineDetailScreen` que NO usa Scaffold local — usa Stack + SafeArea del shell). Decisión: NO usar `Scaffold` propio, hacer `Column(AppBar custom + ListView Expanded)` para evitar conflicto. Actualizar Decision #15 en apply si testing falla. |
| **NEW**: Exercise picker bottom sheet sobre teclado puede recortar el TextField search | Low | `isScrollControlled: true` permite que el sheet ocupe full screen. Padding bottom con `MediaQuery.of(context).viewInsets.bottom` push del teclado. Patrón estándar Flutter. |
| **NEW**: `assignedRoutinesProvider(athleteId)` con autoDispose se invalida cada vez que el atleta vuelve al WorkoutScreen — re-fetch innecesario en cada navegación | Low | Acceptable cost MVP (1 query Firestore por mount). Si QA detecta lag, considerar `keepAlive: true` en una etapa posterior. |
| **NEW**: `userPublicProfileProvider` para el `assignedBy` puede no estar cargado en MiPlanSection — chip "Asignado por" muestra `'...'` extendido | Low | Acceptable — el provider resuelve en <500ms. Si UX request, prefetch en `AthleteDetailScreen` antes de navigate. Defer a etapa siguiente. |
| **NEW**: Multi-language: si el atleta no es authenticado (race en redirect), `MiPlanSection` recibe uid==null → empty state confuso | Low | El redirect `authRedirect` en `router.dart` previene que un anon llegue a `/workout`. `MiPlanSection` con uid==null renderiza `SizedBox.shrink()` defensivo (Decision #8). |
| **NEW**: `fake_cloud_firestore` no implementa server-side `FieldValue.serverTimestamp()` igual que prod | Low | En el test, asserts sobre la presencia del field (`expect(json.containsKey('createdAt'), true)`) no sobre su valor exacto. Patrón usado en `user_repository_test.dart` (createdAt en users). |
| **NEW**: PR2 supera 400 LOC fácilmente | Med | Monitorear en apply. Si supera, candidato split: PR2a = MiPlanSection + badge en RoutineDetailScreen + tap en TrainerCoachView (atleta-side + chico trainer-side); PR2b = RoutineEditorScreen + AthleteDetailScreen + router (trainer-side grande). Decision en review workload forecast de `sdd-tasks`. |

## Open Questions

Todas las open questions del proposal resueltas en este design:

- **Q1 (mínimo de días)**: ≥ 1 día con ≥ 1 slot por día. Submit disabled si no se cumple. Locked en Decision #16.
- **Q2 (mínimo de slots por día)**: cada día requiere ≥ 1 slot (Decision #16). Sin "día de descanso" en MVP — un día sin slots es semánticamente "el día no aporta" y el atleta no lo ejecutaría.
- **Q3 (default visibility)**: `RoutineVisibility.private`. Sin toggle UI en MVP. Locked en Decision #18.
- **Q4 (tiebreaker createdAt)**: doc id (default Firestore). Locked en Decision #4.
- **Q5 (empty state PF en AthleteDetailScreen)**: copy "Todavía no le asignaste planes." sin ilustración (parity con copy actual del placeholder workout).
- **Q6 (orden lista ejercicios en picker)**: orden del `exercisesProvider` (que por convención del repo viene alfabético). Sin agrupación por muscleGroup en MVP — search filter cubre. Si UX feedback en alfa, agregar sticky headers.
- **Q7 (confirmación pre-submit)**: NO en MVP — submit directo con SnackBar success. Confirmación modal "¿Seguro?" agrega friction sin valor claro para el primer plan; defer si feedback indica.
- **Q8 (formato badge Plan finalizado)**: chip pequeño dentro de `_PlanCard` (NO banner). Locked en Decision #9.
- **Q9 (PR2 split adicional)**: monitorear en `sdd-tasks` review workload forecast. Si LOC > 400, dividir atleta-side / trainer-side. Default: PR2 single.

## Review Workload Forecast

- **400-line budget risk**: High en una sola unidad — RESUELTO con chained PRs (PR1 + PR2).
- **Chained PRs recommended**: Yes (PR1 data + PR2 UI).
- **Decision needed before apply**: No — el split y boundaries quedan locked en este design.
- **Estimated changed lines**: PR1 ~250-300 / PR2 ~350-450 / total ~600-750.
- **Delivery strategy**: chained PRs (already cached at orchestrator level).
- **Watch for in apply**: si PR2 proyecta > 400 LOC en `sdd-tasks`, considerar split adicional atleta-side (MiPlan + badge + tap) vs trainer-side (AthleteDetail + Editor + router).

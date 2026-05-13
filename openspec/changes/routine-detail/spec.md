# Spec — routine-detail

**Change**: `routine-detail`
**Fase / Etapa**: Fase 2 · Etapa 4
**Artifact store**: `hybrid`
**TDD**: Strict — cada test se escribe ANTES del widget correspondiente en la fase apply.
**Depende de**: `routine-model-seed` (modelos, repos y providers ya existen en `lib/features/workout/`)

---

## Overview

Este spec define los requisitos verificables para las dos pantallas read-only de Etapa 4: `RoutineDetailScreen` (paridad con `expandir-plantilla.png`) y `ExerciseDetailScreen` (paridad con `detalle-ejercicio.png`, modo Fase 2), más las dos sub-rutas GoRouter y el único icono nuevo.

**Sin cambios de dominio**: `Routine`, `RoutineDay`, `RoutineSlot` y `Exercise` no se modifican. `routineByIdProvider.family` y `exerciseByIdProvider.family` ya existen. `pubspec.yaml` no se toca. El diff es 100% presentation + tests + 2 sub-rutas.

Convención de test helper (igual que en `home-shell`):

```dart
Widget _wrap(Widget w) => MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w));

Widget _wrapProvider(Widget w, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w)),
);
```

**Numeración de scenarios**: inicia en SCENARIO-075 (SCENARIO-020–074 usados en `home-shell` y `routine-model-seed`).

---

## Modelos de dominio — sin cambios

No se agrega, modifica ni elimina ningún campo en `Routine`, `RoutineDay`, `RoutineSlot` ni `Exercise`. Los revisores NO deben buscar cambios en `lib/features/workout/domain/` ni en repositorios ni providers existentes.

---

## Requirements

---

### REQ-RDT-001 — RoutineDetailScreen es un ConsumerStatefulWidget que observa routineByIdProvider

`RoutineDetailScreen` DEBE ser un `ConsumerStatefulWidget`. Su método `build` DEBE llamar `ref.watch(routineByIdProvider(routineId))` exactamente una vez y resolver el estado con `.when(data:, loading:, error:)`. El estado `selectedDayIndex` (índice del día seleccionado actualmente) DEBE ser un `int` local en el `State` — NO un `StateProvider` de Riverpod.

#### Scenarios

- **SCENARIO-075**: DADO un `ProviderScope` con `routineByIdProvider('test-id')` sobreescrito con `AsyncData(routine)` (rutina con al menos 1 día y 2 slots) CUANDO `RoutineDetailScreen(routineId: 'test-id')` se hace pump ENTONCES la pantalla renderiza sin excepción, `find.byType(ExerciseSlotRow)` encuentra al menos 2 widgets, y `find.byType(TreinoBottomBar)` (o el scaffold wrapper equivalente) está presente en el árbol.

- **SCENARIO-076**: DADO un `ProviderScope` con `routineByIdProvider('test-id')` sobreescrito con `AsyncLoading()` CUANDO `RoutineDetailScreen` se hace pump (un solo `pump()`, no `pumpAndSettle`) ENTONCES se encuentra un widget de tipo skeleton/shimmer y NO se encuentra `ExerciseSlotRow`.

- **SCENARIO-077**: DADO un `ProviderScope` con `routineByIdProvider('test-id')` sobreescrito con `AsyncError(Exception(), StackTrace.empty)` CUANDO `RoutineDetailScreen` se hace pump ENTONCES no se lanza excepción, se muestra un banner de error con opción de retry, y NO se muestra `ExerciseSlotRow`.

- **SCENARIO-078**: DADO un `ProviderScope` con `routineByIdProvider('test-id')` sobreescrito con `AsyncData(null)` (ID no encontrado) CUANDO `RoutineDetailScreen` se hace pump ENTONCES se muestra el texto `"Rutina no encontrada"` y un botón de volver, y no se muestra la lista de ejercicios.

---

### REQ-RDT-002 — Hero strip del RoutineDetailScreen

La zona superior de `RoutineDetailScreen` DEBE renderizar un strip de hero. Cuando `routine.imageUrl == null` (todos los seeds son null), el strip DEBE mostrar un gradient placeholder usando tokens de paleta (`palette.accent` y `palette.highlight`). No DEBE usar `Image.network` ni `CachedNetworkImage` cuando `imageUrl` es null.

#### Scenarios

- **SCENARIO-079**: DADO `RoutineDetailScreen` con una `Routine` cuyo `imageUrl == null` CUANDO se renderiza ENTONCES NO se encuentra `CachedNetworkImage` en el árbol y se encuentra al menos un `DecoratedBox` o `Container` con `decoration` que contiene un `LinearGradient` o `RadialGradient` cuyas colors incluyen `AppPalette.mintMagenta.accent`.

---

### REQ-RDT-003 — Badge de split/día en RoutineDetailScreen

`RoutineDetailScreen` DEBE mostrar un badge con el texto `"{routine.split} · DÍA {selectedDay.dayNumber}"` en `Barlow Condensed` weight 600 (~11px) con color de fondo `palette.accent`. El badge DEBE actualizarse cuando cambia el `selectedDayIndex`.

#### Scenarios

- **SCENARIO-080**: DADO una `Routine` con `split: 'PPL'` y un día con `dayNumber: 1` CUANDO `RoutineDetailScreen` se renderiza con ese día seleccionado ENTONCES `find.text('PPL · DÍA 1')` o `find.textContaining('PPL')` junto con `find.textContaining('DÍA 1')` encuentra exactamente un widget.

---

### REQ-RDT-004 — Título del día en RoutineDetailScreen

`RoutineDetailScreen` DEBE mostrar `selectedDay.name` en UPPERCASE con `Barlow Condensed` weight 700 (~36–40px) en color `palette.textPrimary`.

#### Scenarios

- **SCENARIO-081**: DADO un `RoutineDay` con `name: 'Push'` CUANDO `RoutineDetailScreen` renderiza ese día ENTONCES se encuentra texto que, en uppercase, es `'PUSH'` y el estilo usa `GoogleFonts.barlowCondensed` con `FontWeight.w700`.

---

### REQ-RDT-005 — Stat row derivada del modelo en RoutineDetailScreen

`RoutineDetailScreen` DEBE mostrar exactamente 3 `StatTile`s derivados del día seleccionado:
1. Cantidad de ejercicios: `selectedDay.slots.length`.
2. Total de series: suma de `slot.targetSets` para todos los slots del día.
3. Minutos estimados: `selectedDay.estimatedMinutes` si no es null; dash `"—"` si es null.

#### Scenarios

- **SCENARIO-082**: DADO un `RoutineDay` con 3 slots cuyos `targetSets` son `[4, 3, 3]` y `estimatedMinutes: 45` CUANDO `RoutineDetailScreen` renderiza ese día ENTONCES `find.text('3')` (ejercicios) encuentra un widget dentro de un `StatTile`, `find.text('10')` (total sets) encuentra un widget dentro de un `StatTile`, y `find.text('45')` o `find.text('45 min')` encuentra un widget dentro de un `StatTile`.

- **SCENARIO-083**: DADO un `RoutineDay` con `estimatedMinutes: null` CUANDO `RoutineDetailScreen` renderiza ese día ENTONCES el tercer `StatTile` muestra el texto `"—"` y no lanza excepción.

---

### REQ-RDT-006 — Selector de días (solo cuando hay más de 1 día)

`RoutineDetailScreen` DEBE mostrar el selector de días ÚNICAMENTE cuando `routine.days.length > 1`. Cuando solo hay un día, el selector NO DEBE aparecer. Al tocar un chip de día, `selectedDayIndex` DEBE actualizarse al índice correspondiente y la pantalla debe re-renderizar con el nuevo día.

#### Scenarios

- **SCENARIO-084**: DADO una `Routine` con un solo día CUANDO `RoutineDetailScreen` se renderiza ENTONCES no se encuentra ningún widget de tipo day-selector (chip, tab, u otro control de selección de días).

- **SCENARIO-085**: DADO una `Routine` con 3 días CUANDO `RoutineDetailScreen` se renderiza ENTONCES se encuentran exactamente 3 chips/tabs de selección de días. Al hacer `tester.tap` en el chip del tercer día y `pumpAndSettle`, el contenido cambia al tercer día (el nombre del día visible en pantalla corresponde a `routine.days[2].name.toUpperCase()`).

---

### REQ-RDT-007 — Sección "EJERCICIOS" y lista de ExerciseSlotRow

`RoutineDetailScreen` DEBE mostrar un section header con el texto `"EJERCICIOS"`. Debajo DEBE renderizar una `ExerciseSlotRow` por cada `RoutineSlot` del día seleccionado. Cuando `selectedDay.slots` está vacío, DEBE mostrar el empty state `"No hay ejercicios en este día"` en lugar de la lista.

#### Scenarios

- **SCENARIO-086**: DADO un `RoutineDay` con 4 slots CUANDO `RoutineDetailScreen` renderiza ese día ENTONCES `find.text('EJERCICIOS')` encuentra exactamente un widget y `find.byType(ExerciseSlotRow)` encuentra exactamente 4 widgets.

- **SCENARIO-087**: DADO un `RoutineDay` con `slots: []` CUANDO `RoutineDetailScreen` renderiza ese día ENTONCES `find.byType(ExerciseSlotRow)` encuentra cero widgets y `find.text('No hay ejercicios en este día')` encuentra exactamente un widget.

---

### REQ-RDT-008 — ExerciseSlotRow renderiza datos del slot

`ExerciseSlotRow` DEBE renderizar, por cada `RoutineSlot`:
- Un thumb cuadrado con icon placeholder (`TreinoIcon.tabWorkout` u equivalente) — no hay foto por slot en el modelo.
- `slot.exerciseName` como texto principal.
- La cadena `"{slot.targetSets} · {slot.targetRepsMin}–{slot.targetRepsMax}"` (ej. `"4 · 8–12"`).
- `slot.muscleGroup` como texto secundario.
- Un badge derecho con el texto `"ÚLTIMO"` y un dash placeholder `"—"` (session history es Fase 4).

No DEBE hacer ningún `ref.watch` ni `ref.read` — recibe todos sus datos por parámetros del constructor.

#### Scenarios

- **SCENARIO-088**: DADO un `RoutineSlot` con `exerciseName: 'Press de Banca'`, `targetSets: 4`, `targetRepsMin: 8`, `targetRepsMax: 12`, `muscleGroup: 'Pecho'` CUANDO `ExerciseSlotRow(slot: slot)` se hace pump ENTONCES `find.text('Press de Banca')` encuentra uno, `find.text('4 · 8–12')` encuentra uno, y `find.text('Pecho')` encuentra uno.

- **SCENARIO-089**: DADO cualquier `RoutineSlot` válido CUANDO `ExerciseSlotRow` se renderiza ENTONCES `find.text('ÚLTIMO')` encuentra un widget y `find.text('—')` encuentra al menos un widget (badge placeholder).

---

### REQ-RDT-009 — CTAs "EDITAR" y "EMPEZAR" como stubs deshabilitados

El bottom bar de `RoutineDetailScreen` DEBE renderizar exactamente dos CTAs:
- `"EDITAR"` — estilo ghost (borde `palette.border`, sin fill), `onPressed: null`, opacidad al 40%.
- `"EMPEZAR"` — estilo pill `palette.accent` (r-full), `onPressed: null`, opacidad al 40%.

Ningún CTA DEBE ser tappeable (no navega, no ejecuta callback). El layout del bottom bar DEBE ser idéntico al mockup `expandir-plantilla.png` — los CTAs NO se ocultan.

#### Scenarios

- **SCENARIO-090**: DADO `RoutineDetailScreen` con una rutina válida CUANDO se inspecciona el widget tree ENTONCES se encuentran exactamente dos widgets de CTA: uno con texto `"EDITAR"` y uno con texto `"EMPEZAR"`. Ambos tienen `onPressed == null`.

- **SCENARIO-091**: DADO los dos CTAs con `onPressed: null` CUANDO `tester.tap` se llama sobre cada uno y se hace `pumpAndSettle` ENTONCES no se lanza ninguna excepción y el widget tree no cambia (no hay navegación).

- **SCENARIO-092**: DADO los dos CTAs CUANDO se inspecciona su `Opacity` wrapper o `AnimatedOpacity` ENTONCES el valor de opacity es `0.4` (o `kDisabledOpacity` si se define como constante con ese valor).

---

### REQ-RDT-010 — Tap en ExerciseSlotRow navega a /workout/exercise/:exerciseId

Al tocar un `ExerciseSlotRow`, `RoutineDetailScreen` DEBE invocar `context.push('/workout/exercise/${slot.exerciseId}')`. No DEBE usar `context.go` (que rompería el historial de navegación dentro del shell).

#### Scenarios

- **SCENARIO-093**: DADO `RoutineDetailScreen` montado dentro de un `MaterialApp.router` con `GoRouter` configurado con el path `/workout/exercise/:exerciseId` CUANDO `tester.tap(find.byType(ExerciseSlotRow).first)` y `pumpAndSettle` ENTONCES el router navega a la ruta `/workout/exercise/{slot.exerciseId}` (verificado via `GoRouter.of(context).location` o un mock de `GoRouter`).

---

### REQ-RDT-011 — RoutineDetailScreen no introduce Scaffold, AppBackground ni SafeArea propios

`RoutineDetailScreen.build` NO DEBE contener `Scaffold`, `AppBackground`, ni `SafeArea` en su propio subtree. El `ShellRoute` ya los aplica — duplicarlos produce bugs visuales.

#### Scenarios

- **SCENARIO-094**: DADO `RoutineDetailScreen` montado dentro de un `MaterialApp(home: Scaffold(body: ...))` mínimo (no el shell real) CUANDO el árbol se inspecciona ENTONCES `find.byType(Scaffold)` encuentra exactamente uno (el del wrapper de test) y `find.byType(AppBackground)` encuentra cero y `find.byType(SafeArea)` encuentra cero dentro del subtree de `RoutineDetailScreen`.

---

### REQ-RDT-012 — StatTile renderiza label y value correctamente

`StatTile` DEBE ser un `StatelessWidget` que acepta `label` y `value` como `String`. DEBE renderizar ambos como texto visible. Cuando `value` es `"—"`, DEBE renderizarlo sin excepción.

#### Scenarios

- **SCENARIO-095**: DADO `StatTile(label: 'EJERCICIOS', value: '6')` CUANDO se hace pump ENTONCES `find.text('EJERCICIOS')` encuentra uno y `find.text('6')` encuentra uno.

- **SCENARIO-096**: DADO `StatTile(label: 'DURACIÓN', value: '—')` CUANDO se hace pump ENTONCES `find.text('—')` encuentra uno y no se lanza excepción.

---

### REQ-RDT-013 — ExerciseDetailScreen es un ConsumerWidget que observa exerciseByIdProvider

`ExerciseDetailScreen` DEBE ser un `ConsumerWidget`. Su método `build` DEBE llamar `ref.watch(exerciseByIdProvider(exerciseId))` exactamente una vez y resolver con `.when(data:, loading:, error:)`.

#### Scenarios

- **SCENARIO-097**: DADO un `ProviderScope` con `exerciseByIdProvider('ex-id')` sobreescrito con `AsyncData(exercise)` (exercise con `techniqueInstructions` no vacías) CUANDO `ExerciseDetailScreen(exerciseId: 'ex-id')` se hace pump ENTONCES la pantalla renderiza sin excepción y se encuentra el nombre del ejercicio en pantalla.

- **SCENARIO-098**: DADO un `ProviderScope` con `exerciseByIdProvider('ex-id')` sobreescrito con `AsyncLoading()` CUANDO `ExerciseDetailScreen` se hace pump ENTONCES se encuentra un widget skeleton/shimmer y NO se muestra el nombre del ejercicio ni instrucciones de técnica.

- **SCENARIO-099**: DADO un `ProviderScope` con `exerciseByIdProvider('ex-id')` sobreescrito con `AsyncError(Exception(), StackTrace.empty)` CUANDO `ExerciseDetailScreen` se hace pump ENTONCES no se lanza excepción y se muestra un banner de error con opción de retry.

- **SCENARIO-100**: DADO un `ProviderScope` con `exerciseByIdProvider('ex-id')` sobreescrito con `AsyncData(null)` CUANDO `ExerciseDetailScreen` se hace pump ENTONCES se muestra el texto `"Ejercicio no encontrado"` y un botón de volver.

---

### REQ-RDT-014 — Hero y breadcrumb de ExerciseDetailScreen

`ExerciseDetailScreen` DEBE mostrar:
- Un strip hero de imagen con gradient placeholder (no hay `photoUrl` en el modelo `Exercise`). No usa `Image.network` ni `CachedNetworkImage` para el hero.
- Un breadcrumb con `"{exercise.muscleGroup.toUpperCase()} · {exercise.category.toUpperCase()}"` en `Barlow Condensed`.
- El nombre `exercise.name` en UPPERCASE con `Barlow Condensed` weight 700 (tamaño grande).

#### Scenarios

- **SCENARIO-101**: DADO un `Exercise` con `muscleGroup: 'Pecho'`, `category: 'compound'`, `name: 'Press de Banca'` CUANDO `ExerciseDetailScreen` renderiza ENTONCES se encuentra el texto `'PECHO · COMPOUND'` y se encuentra texto `'PRESS DE BANCA'` en el árbol.

---

### REQ-RDT-015 — Stat row placeholder en ExerciseDetailScreen

`ExerciseDetailScreen` DEBE mostrar exactamente 3 `StatTile`s con `value: '—'` representando 1RM, sesiones totales y progreso%. Estos valores son placeholder hasta Fase 4 (session history).

#### Scenarios

- **SCENARIO-102**: DADO cualquier `Exercise` válido CUANDO `ExerciseDetailScreen` renderiza ENTONCES se encuentran exactamente 3 instancias de `StatTile` y todas muestran el valor `"—"`.

---

### REQ-RDT-016 — Sección "TÉCNICA" con instrucciones numeradas en ExerciseDetailScreen

`ExerciseDetailScreen` DEBE mostrar un section header `"TÉCNICA"`. Si `exercise.techniqueInstructions` no es null y no está vacío, DEBE renderizar una `TechniqueInstructionItem` numerada por cada instrucción. Si `techniqueInstructions == null` o está vacío, DEBE mostrar el empty state `"No hay instrucciones de técnica todavía"`.

#### Scenarios

- **SCENARIO-103**: DADO un `Exercise` con `techniqueInstructions: ['Cue 1', 'Cue 2', 'Cue 3']` CUANDO `ExerciseDetailScreen` renderiza ENTONCES `find.text('TÉCNICA')` encuentra uno y se encuentran 3 widgets `TechniqueInstructionItem` (o 3 textos que contienen `'Cue 1'`, `'Cue 2'`, `'Cue 3'` respectivamente).

- **SCENARIO-104**: DADO un `Exercise` con `techniqueInstructions: null` CUANDO `ExerciseDetailScreen` renderiza ENTONCES `find.text('No hay instrucciones de técnica todavía')` encuentra uno y `find.byType(TechniqueInstructionItem)` encuentra cero.

- **SCENARIO-105**: DADO un `Exercise` con `techniqueInstructions: []` CUANDO `ExerciseDetailScreen` renderiza ENTONCES se muestra el mismo empty state `"No hay instrucciones de técnica todavía"`.

---

### REQ-RDT-017 — Sección "HISTORIAL" con empty state en ExerciseDetailScreen

`ExerciseDetailScreen` DEBE mostrar un section header `"HISTORIAL"` con el texto `"Aún no entrenaste este ejercicio"`. Esta sección siempre está en empty state en Fase 2 — no hay datos de sesión hasta Fase 4. La sección DEBE renderizarse aunque `techniqueInstructions` sea null.

#### Scenarios

- **SCENARIO-106**: DADO cualquier `Exercise` válido CUANDO `ExerciseDetailScreen` renderiza ENTONCES `find.text('HISTORIAL')` encuentra uno y `find.text('Aún no entrenaste este ejercicio')` encuentra uno.

---

### REQ-RDT-018 — videoUrl null manejado sin crash en ExerciseDetailScreen

Cuando `exercise.videoUrl == null` (todos los seeds son null), `ExerciseDetailScreen` NO DEBE crashear. Puede mostrar un placeholder `"Video próximamente"` o simplemente omitir la sección de video. Cuando `videoUrl != null`, DEBE mostrar el texto `"Video próximamente"` (reproducción real es Fase 4).

#### Scenarios

- **SCENARIO-107**: DADO un `Exercise` con `videoUrl: null` CUANDO `ExerciseDetailScreen` renderiza ENTONCES no se lanza ninguna excepción y no se intenta cargar ninguna URL de video.

- **SCENARIO-108**: DADO un `Exercise` con `videoUrl: 'https://example.com/video.mp4'` CUANDO `ExerciseDetailScreen` renderiza ENTONCES se muestra el texto `"Video próximamente"` y no se usa ningún reproductor de video real.

---

### REQ-RDT-019 — ExerciseDetailScreen no introduce Scaffold, AppBackground ni SafeArea propios

Mismo contrato que `REQ-RDT-011`: `ExerciseDetailScreen.build` NO DEBE contener `Scaffold`, `AppBackground`, ni `SafeArea`.

#### Scenarios

- **SCENARIO-109**: DADO `ExerciseDetailScreen` montado en un wrapper mínimo `MaterialApp(home: Scaffold(...))` CUANDO el árbol se inspecciona ENTONCES `find.byType(Scaffold)` encuentra exactamente uno y `find.byType(AppBackground)` y `find.byType(SafeArea)` encuentran cero dentro del subtree propio.

---

### REQ-RDT-020 — Router: dos GoRoutes bajo /workout dentro del ShellRoute

`lib/app/router.dart` DEBE agregar exactamente 2 sub-`GoRoute`s anidados bajo `/workout` **dentro del `ShellRoute` existente**:

```
/workout/routine/:routineId   → RoutineDetailScreen(routineId: state.pathParameters['routineId']!)
/workout/exercise/:exerciseId → ExerciseDetailScreen(exerciseId: state.pathParameters['exerciseId']!)
```

`WorkoutScreen` (placeholder actual de `/workout`) NO DEBE ser modificado. La bottom bar (`TreinoBottomBar` o su equivalente en `_ShellScaffold`) DEBE permanecer visible en ambas nuevas rutas.

#### Scenarios

- **SCENARIO-110**: DADO un `MaterialApp.router` con el `GoRouter` de producción configurado CUANDO se hace deep-link a `/workout/routine/ppl-beginner` con `routineByIdProvider` sobreescrito con `AsyncData(routine)` ENTONCES `find.byType(RoutineDetailScreen)` encuentra uno y `find.byType(TreinoBottomBar)` (o el widget de bottom navigation correspondiente) encuentra uno en el árbol.

- **SCENARIO-111**: DADO un `MaterialApp.router` con el `GoRouter` de producción CUANDO se hace deep-link a `/workout/exercise/bench-press` con `exerciseByIdProvider` sobreescrito con `AsyncData(exercise)` ENTONCES `find.byType(ExerciseDetailScreen)` encuentra uno y el widget de bottom navigation está presente.

---

### REQ-RDT-021 — TreinoIcon.timer añadido a treino_icon.dart

`lib/core/widgets/treino_icon.dart` DEBE agregar la constante `TreinoIcon.timer` mapeando al icono Phosphor `timer` (o equivalente). DEBE ser la única adición a este archivo en este PR. Si ya existiera una constante con ese nombre en la rama al momento del apply, se reutiliza sin agregar duplicado.

#### Scenarios

- **SCENARIO-112**: DADO el archivo `lib/core/widgets/treino_icon.dart` tras aplicar el cambio CUANDO se hace `grep 'timer'` ENTONCES existe exactamente una línea con `TreinoIcon.timer` y no hay referencias directas a `PhosphorIcons.timer` en ningún archivo nuevo del PR.

---

## Constraint summary

| Restricción | Aplicada por |
|---|---|
| Sin `Scaffold`/`AppBackground`/`SafeArea` en pantallas nuevas | REQ-RDT-011, REQ-RDT-019 |
| Sin HEX literals en archivos nuevos | Todos los REQs de color (grep en review) |
| Sin `PhosphorIcons.*` directo | REQ-RDT-021 + grep en review |
| Sin `Theme.of(context).textTheme.*` con sizes custom | REQ-RDT-004, REQ-RDT-014 |
| Spacing solo en `{8, 12, 14, 18, 20}` px | Design review gate — grep por `16` y `24` en archivos nuevos |
| Radii: cards `r-lg=20`, CTAs `r-full=9999` | REQ-RDT-009 |
| `selectedDayIndex` como state local, no Riverpod | REQ-RDT-001 |
| CTAs con `onPressed: null` y 40% opacity, no ocultos | REQ-RDT-009 |
| `ExerciseSlotRow` sin `ref.watch`/`ref.read` | REQ-RDT-008 |
| `WorkoutScreen` no se toca | REQ-RDT-020 |
| Sin cambios en domain models, repos, providers, `firestore.rules`, `pubspec.yaml` | Overview — "Sin cambios de dominio" |
| Tests escritos BEFORE cada widget (Strict TDD) | Enforced por tasks phase |

---

## Out of scope (explícito)

Lo siguiente NO entra en este PR. Si aparece en un diff, el reviewer DEBE rechazarlo.

- **`detalle-rutina.png`** (rutina asignada con progress bar semanal, lista de días con chevron, CTA "EMPEZAR DÍA X") → Fase 5 (assignment) + Fase 4 (session data). **Este PR cubre `expandir-plantilla.png` únicamente.**
- **"Iniciar entrenamiento" / session player real** → Fase 4.
- **"ÚLTIMO" peso real** por slot → Fase 4 (depende de session history).
- **Stats 1RM / sesiones / progreso%** en `ExerciseDetailScreen` → Fase 4.
- **Reproducción de video** en `ExerciseDetailScreen` → Fase 4.
- **Wire desde Home / Plantillas → Detalle de Rutina** → Etapa 5 de Fase 2 (Dev B, `feat/home-wire-routines`). Este PR solo expone la ruta.
- **Botón "EDITAR" funcional** → Fase 5 (creación/edición de rutinas por PF).
- **Cambios en `Routine`, `RoutineDay`, `RoutineSlot`, `Exercise`** (domain models) → ninguno necesario.
- **Cambios en `RoutineRepository`, `ExerciseRepository`** o sus providers → ninguno necesario.
- **`firestore.rules`** → sin cambios.
- **`pubspec.yaml`** → sin cambios, cero dependencias nuevas.
- **Dev-only entry button** temporal en `WorkoutScreen` → no se ship.
- **Filtros, búsqueda, edición** en pantallas de detalle → fuera.
- **Routine creation / assignment** → Fase 5.
- **Ranking, Retos, Missions, Bets, Gamificación** → fuera del producto (ver `AGENTS.md`).

---

## Archivos que cubre este spec

| Archivo | REQs |
|---|---|
| `lib/features/workout/presentation/routine_detail_screen.dart` | RDT-001, RDT-002, RDT-003, RDT-004, RDT-005, RDT-006, RDT-007, RDT-009, RDT-010, RDT-011 |
| `lib/features/workout/presentation/exercise_detail_screen.dart` | RDT-013, RDT-014, RDT-015, RDT-016, RDT-017, RDT-018, RDT-019 |
| `lib/features/workout/presentation/widgets/exercise_slot_row.dart` | RDT-008 |
| `lib/features/workout/presentation/widgets/stat_tile.dart` | RDT-012 |
| `lib/features/workout/presentation/widgets/technique_instruction_item.dart` | RDT-016 |
| `lib/app/router.dart` | RDT-020 |
| `lib/core/widgets/treino_icon.dart` | RDT-021 |
| `test/features/workout/presentation/routine_detail_screen_test.dart` | RDT-001..011 |
| `test/features/workout/presentation/exercise_detail_screen_test.dart` | RDT-013..019 |
| `test/features/workout/presentation/widgets/exercise_slot_row_test.dart` | RDT-008 |
| `test/features/workout/presentation/widgets/stat_tile_test.dart` | RDT-012 |

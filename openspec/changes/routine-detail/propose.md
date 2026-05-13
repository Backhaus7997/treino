# Proposal — routine-detail

**Change**: `routine-detail`
**Fase / Etapa**: Fase 2 · Etapa 4
**Branch**: `feat/routine-detail`
**Owner**: Dev C
**Artifact store**: `hybrid` · **Execution mode**: `interactive` · **Delivery**: `ask-on-risk`
**TDD**: Strict (per `docs/workflow.md`) — tests first en apply
**Depends on**: `explore.md` (en esta carpeta — ver `openspec/changes/routine-detail/explore.md` y/o engram `sdd/routine-detail/explore`)

---

## 1. Why

Fase 2 entrega el catálogo de plantillas que el atleta explora antes de poder asignarse una rutina. Etapas 2 (modelo + seed) y 3 (lista de plantillas) hacen visible el catálogo; sin Etapa 4, cuando el usuario tappea una card de plantilla no pasa nada: la app no tiene forma de mostrar qué ejercicios trae ese día, cuántas series, qué reps, ni qué cues de técnica corresponden a cada ejercicio. Este PR cierra el loop "ver catálogo → explorar contenido" en modo read-only, y deja el route hook (`/workout/routine/:routineId`) listo para que Etapa 3 (`feat/routines-list`, Dev B) lo invoque sin que ninguna de las dos PRs tenga que coordinarse fuera del path.

La decisión clave es **tratar esta etapa como UI puro sobre infra existente**: los modelos, repos y providers ya viven en `lib/features/workout/` desde Etapa 2; las dos pantallas se construyen como composers delgados sobre `routineByIdProvider.family` y `exerciseByIdProvider.family` (lookups O(1) en memoria). Cero Firestore reads nuevos, cero providers nuevos, cero cambios en domain/data. El diff es 100% presentation + tests + 1 sub-tree de rutas en `router.dart`.

---

## 2. What — deliverables visibles

Un reviewer que corra `flutter run` y haga deep-link a `/workout/routine/<seed-id>` (o que tappee desde Etapa 3 cuando ésta mergee) debe ver:

### 2.1 `RoutineDetailScreen` — paridad con `expandir-plantilla.png`

- Hero strip con placeholder de gradient (todos los `imageUrl` del seed son `null`).
- Badge `accent` con `SPLIT · DÍA N` (`Barlow Condensed` 600 ~11px).
- Título: nombre del día UPPERCASE (`Barlow Condensed` 700 ~36–40px, `textPrimary`).
- Stat row de 3 tiles derivados del modelo: `slots.length`, suma de `targetSets`, `day.estimatedMinutes`.
- Section header `EJERCICIOS`.
- Lista de filas (`ExerciseSlotRow`) — una por `RoutineSlot`:
  - Thumb cuadrado con icon placeholder (`TreinoIcon.tabWorkout` o similar — no hay foto por slot en el modelo).
  - `slot.exerciseName` (denormalizado, sin segundo round-trip).
  - `targetSets · repsMin–repsMax` (ej. "4 · 8–12").
  - `slot.muscleGroup` (denormalizado).
  - Badge `ÚLTIMO` right-aligned con dash placeholder (session history es Fase 4).
- Bottom bar con 2 CTAs **stubs deshabilitados al 40% opacity, `onPressed: null`**: "EDITAR" (ghost) y "EMPEZAR" (pill `accent`). Layout idéntico al mockup; Fase 4 wirea con un cambio de una línea.
- Estados explícitos: `loading` → skeleton/shimmer; `error` → banner con retry; `data(null)` (ID no encontrado) → "Rutina no encontrada" + back; `slots` vacíos → empty state "No hay ejercicios en este día".

### 2.2 `ExerciseDetailScreen` — paridad con `detalle-ejercicio.png` (modo Fase 2)

- Hero con placeholder gradient (no hay `photoUrl` por exercise en el modelo).
- Breadcrumb `MUSCLE GROUP · CATEGORY`.
- Título hero con `exercise.name` UPPERCASE.
- Stat row de 3 tiles **placeholder con dash** (1RM, sesiones, progreso — todos requieren session history → Fase 4).
- Section `TÉCNICA` con `techniqueInstructions` numeradas (todos los exercises del seed traen 3 cues).
- Section `HISTORIAL` como empty state: "Todavía no entrenaste este ejercicio." (Fase 4).
- Si `videoUrl != null` → placeholder "Video próximamente" (todos los seed values son `null`; manejar el caso `null` sin crash).
- Sin CTA inferior.
- Estados: `loading`, `error`, `data(null)` ("Ejercicio no disponible"), `techniqueInstructions == null` ("Sin instrucciones disponibles").

### 2.3 Routing

`lib/app/router.dart` — agregar 2 `GoRoute` anidados bajo `/workout` **dentro del `ShellRoute`** (la bottom bar permanece visible):

```
/workout
  /workout/routine/:routineId   → RoutineDetailScreen
  /workout/exercise/:exerciseId → ExerciseDetailScreen
```

`WorkoutScreen` (placeholder actual) **no se toca** — Etapa 3 lo reemplaza.

### 2.4 Iconografía

`lib/core/widgets/treino_icon.dart` — agregar `TreinoIcon.timer` (Phosphor `timer`) para descanso/duración. Resto se reusa.

### 2.5 Tests (Strict TDD, SCENARIO-071 en adelante)

| Archivo | Scenarios | Cobertura |
|---|---|---|
| `routine_detail_screen_test.dart` | 071–074 | loading, render con day+slots, slots vacíos, not-found |
| `exercise_detail_screen_test.dart` | 075–078 | loading, render técnica, técnica nula, not-found |
| `exercise_slot_row_test.dart` | 079–080 | render de nombre, sets×reps, muscle group |
| `stat_tile_test.dart` | 081–082 | render de label + value, valor placeholder dash |

---

## 3. How — arquitectura (Approach A confirmado)

**Approach A — Screen + `widgets/` decomposition** (del explore §"Approaches"). Cada pantalla es un composer delgado y los building blocks viven en `widgets/` testables aislados — espeja el patrón ya validado en `home-shell` (Etapa 1).

```
lib/features/workout/presentation/
├── routine_detail_screen.dart       // ConsumerStatefulWidget — selectedDayIndex local
├── exercise_detail_screen.dart      // ConsumerWidget — lee exerciseByIdProvider
└── widgets/
    ├── exercise_slot_row.dart       // una fila por RoutineSlot
    ├── stat_tile.dart               // tile reusable (count/sets/min/placeholder)
    └── technique_instruction_item.dart  // cue numerada
```

**State flow**:

- `RoutineDetailScreen` recibe `routineId` por path param → `ref.watch(routineByIdProvider(routineId))` → pattern matching `.when(data, loading, error)`. `selectedDayIndex` es **state local del `ConsumerStatefulWidget`** — es pura presentation state, no hace falta provider (decisión 4.3).
- `ExerciseDetailScreen` recibe `exerciseId` por path param → `ref.watch(exerciseByIdProvider(exerciseId))` → `.when(...)`.
- Los providers `*ByIdProvider.family` ya derivan de los `FutureProvider` lista cacheados → **0 Firestore reads adicionales** en cualquier navegación dentro de la sesión.

**Theme y tokens**: todo vía `AppPalette.of(context)`, `GoogleFonts.barlowCondensed` (headings/labels UPPERCASE) y `GoogleFonts.barlow` (body). Spacing del set permitido `{8, 12, 14, 18, 20}`. Radii `r-md=16` / `r-lg=20` para cards, `r-full` para CTAs. Sin HEX literals, sin `PhosphorIcons.X` directo.

**Dependencias nuevas**: ninguna. `pubspec.yaml` no se toca.

---

## 4. Trade-offs aceptados

| # | Decisión | Por qué |
|---|---|---|
| 4.1 | **Approach A (screen + `widgets/`)** sobre B (monolítico) o C (promover a `core/widgets/` desde el día 1) | Espeja `home-shell`, cada widget testeable aislado, Fase 4 wirea sobre widgets individuales (badge ÚLTIMO, stat tiles 1RM/sessions). C es YAGNI hasta que aparezca un 2do consumer. |
| 4.2 | **Sub-rutas bajo `/workout` dentro del `ShellRoute`** | La bottom bar permanece visible — coherente con modo "exploración/catálogo" de Fase 2. La pantalla in-session de Fase 4 puede pushear full-screen sobre el shell como decisión deliberada de UX cuando llegue. |
| 4.3 | **`selectedDayIndex` como state local** del `ConsumerStatefulWidget`, no Riverpod | Es pure presentation state, no se comparte, no sobrevive a navegación. Introducir un `StateProvider.family` agrega ceremony sin beneficio. |
| 4.4 | **CTAs "EDITAR" y "EMPEZAR" como stubs deshabilitados al 40% opacity** | Preserva paridad visual con el mockup (`expandir-plantilla.png`) y deja Fase 4 wireando con un cambio de una línea (`onPressed: () => …`). Ocultarlos rompe la jerarquía visual del bottom bar. |
| 4.5 | **Cero Firestore reads nuevos** — reusar `routineByIdProvider.family` y `exerciseByIdProvider.family` | Los providers ya están cacheados via `routinesProvider` / `exercisesProvider`. Cualquier provider derivado adicional sería YAGNI y multiplica superficie de test. |
| 4.6 | **No agregar dev-only entry button al `WorkoutScreen` placeholder** (Etapa 3 todavía no merged) | Reviewers validan vía widget tests + deep-link manual (`go_router.push('/workout/routine/<seed-id>')` desde un test harness). Meter un botón temporal contamina el diff y obliga a un revert PR. Documentar el deep-link en la PR description. |
| 4.7 | **`detalle-rutina.png` queda fuera de scope** aunque viva en la misma carpeta de mockups | Esa pantalla muestra rutina **asignada** con progress bar semanal — eso es Fase 5 (assignment) + Fase 4 (session data). Confundirla con `expandir-plantilla.png` ya pasó internamente; el explore lo deja documentado y este propose lo reafirma para evitar que un futuro dev lo levante por error. |
| 4.8 | **`videoUrl` / `imageUrl` / "ÚLTIMO" peso renderizan como placeholders** | Todos los seed values son `null`; la UI tiene que manejarlos sin crash. Cuando Fase 4 traiga session history y media real, los widgets ya están preparados — sólo cambia el data binding. |

---

## 5. Out-of-scope (explícito)

Lo que **NO** entra y dónde sí entra:

- **"Iniciar entrenamiento" / session player real** → Fase 4 (Workout++).
- **`docs/app-alumno/screens/detalle-rutina/detalle-rutina.png`** (rutina asignada, weekly progress bar, lista de días con chevron, CTA "EMPEZAR DÍA X") → Fase 5 (assignment) + Fase 4 (session data). **Esta etapa cubre `expandir-plantilla.png` únicamente.**
- **"ÚLTIMO" peso real por slot** → Fase 4 (depende de session history).
- **Stats 1RM / sesiones / progreso% en `ExerciseDetailScreen`** → Fase 4.
- **Reproducción de video** en `ExerciseDetailScreen` → Fase 4.
- **Wire desde Home / Plantillas → Detalle de Rutina** → Etapa 5 de Fase 2 (Dev B, `feat/home-wire-routines`). Esta PR sólo expone la ruta.
- **Botón "EDITAR" funcional** → Fase 5 (creación/edición de rutinas por PF).
- **Filtros, búsqueda, edición** desde la pantalla de detalle → fuera.
- **Routine creation / assignment** → Fase 5.
- **Cambios en domain models, repositorios, providers existentes, `firestore.rules`, `pubspec.yaml`** → no hacen falta.
- **Dev-only entry button** temporal en `WorkoutScreen` → no se ship (ver decisión 4.6).
- **Ranking, Retos, Missions, Bets, Gamification** → fuera del producto (ver `CLAUDE.md`).

---

## 6. Success criteria

El PR está "done" cuando:

1. **Visual parity**: comparación lado-a-lado contra `docs/app-alumno/screens/entrenamiento/expandir-plantilla.png` y `docs/app-alumno/screens/detalle-rutina/detalle-ejercicio.png` muestra fidelidad de layout, tipografía, colores, radios y spacing — módulo los placeholders declarados (CTAs deshabilitados, stats Fase 4 con dash, hero gradients).
2. **Deep-link funciona**: `context.push('/workout/routine/ppl-beginner')` aterriza en `RoutineDetailScreen` con día 1 seleccionado, bottom bar visible. Tappear un `ExerciseSlotRow` navega a `/workout/exercise/:exerciseId` con la técnica renderizada.
3. **4 estados de cada provider manejados sin crash**: `loading`, `error`, `data(null)`, `data(presente)`. Cubierto por tests.
4. **CTAs "EDITAR" y "EMPEZAR"** se renderizan con 40% opacity, `onPressed: null`. No son tappables.
5. **Tests verdes**: 4 archivos nuevos (12+ scenarios desde SCENARIO-071) pasan. Tests escritos **antes** del código de cada widget (Strict TDD).
6. **`flutter analyze`**: 0 issues nuevos.
7. **`dart format .`**: árbol limpio.
8. **Sin HEX literals, sin `PhosphorIcons.X` directo, sin `Theme.of(context).textTheme.X`** con sizes custom.
9. **`router.dart`** suma exactamente 2 sub-`GoRoute`s anidados bajo `/workout` dentro del `ShellRoute`. `WorkoutScreen` no se toca.
10. **`treino_icon.dart`** suma `TreinoIcon.timer` (única adición). El resto reusa lo existente.
11. **No se rompe el shell**: navegar entre tabs sigue funcionando; back desde detail vuelve al tab `/workout`; no aparece doble `Scaffold` ni doble `SafeArea`.

---

## 7. Risks (priorizados, con mitigación para apply)

| # | Riesgo | Severidad | Mitigación en apply |
|---|---|---|---|
| 1 | **Confusión `expandir-plantilla.png` vs `detalle-rutina.png`** durante apply (el segundo es de Fase 5) | Alta | Decisión 4.7 + sección 5 lo dejan explícito. `tasks.md` debe referenciar el mockup correcto por filename. Code review verifica que el screenshot del PR matchea `expandir-plantilla.png`. |
| 2 | **`routineByIdProvider` / `exerciseByIdProvider` devuelven `null`** por bad deep-link o seed incompleto y la pantalla crashea | Alta | Tests SCENARIO-074 / SCENARIO-078 cubren el caso `data(null)` **antes** de escribir el widget. Fallback explícito con back button. |
| 3 | **Re-aplicar `Scaffold` / `SafeArea`** en las nuevas pantallas (el `ShellRoute` ya los aplica) | Media | Comentario en el header del archivo + test que envuelva con `MaterialApp + Scaffold` mínimo y verifique que la screen no introduce `Scaffold` propio. Mismo patrón que `home-shell`. |
| 4 | **Etapa 3 (`feat/routines-list`) mergea antes** y asume que el path es `/workout/routine/:id` cuando este PR lo define de otra forma | Media | El path está locked en este propose (decisión 2.3). Cualquier cambio de path en review de este PR obliga a sync con Dev B. Documentar en la PR description. |
| 5 | **Spacing no canónico (16, 24)** se cuela en padding/gaps | Media | Code review checklist + grep de constantes `16` y `24` en los archivos nuevos antes de merge. |
| 6 | **CTAs deshabilitados pero clickeables por accidente** (`onPressed: () {}` en lugar de `null`) | Baja | Tests visuales del bottom bar verifican `onPressed == null` y `opacity == 0.4`. |
| 7 | **`test/features/workout/presentation/` no existe** y Strict TDD requiere tests primero | Baja | Tarea explícita en `tasks.md`: crear el directorio antes del primer widget. Apply agent escribe test rojo → ve fallar → escribe widget verde. |
| 8 | **`TreinoIcon.timer` choca con un nombre existente** o duplica un icon ya añadido en otra rama | Baja | Verificar `treino_icon.dart` actual antes de agregar (1 grep). Si ya existe, reusar. |

---

## 8. Open questions

Ninguna bloqueante. El explore resolvió todas las dudas estructurales (routes, providers, state, mockup correcto, manejo de placeholders, dev entry point). Las decisiones pendientes que el orchestrator pidió confirmar quedan **lockeadas** en este propose:

- CTAs como stubs deshabilitados al 40% opacity → **sí** (decisión 4.4).
- Dev-only entry button temporal → **no** (decisión 4.6).
- `detalle-rutina.png` queda fuera → **sí** (decisión 4.7).

---

**Next recommended**: `sdd-spec` y `sdd-design` (pueden correr en paralelo).

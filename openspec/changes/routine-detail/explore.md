# Explore — routine-detail

**Change**: `routine-detail`
**Fase / Etapa**: Fase 2 · Etapa 4
**Branch**: `feat/routine-detail`
**Owner**: Dev C
**Scope**: Pantallas read-only de Detalle de Rutina (lista de ejercicios con series/repes) y Detalle de Ejercicio (instrucciones de técnica). Sin "iniciar entrenamiento" — eso es Fase 4.

---

## Current state

**Modelos** (`lib/features/workout/domain/`, todos con freezed + json_serializable, tests SCENARIO-043 a 070):

- `Routine` — `id`, `name`, `split`, `level`, `days: List<RoutineDay>`, `estimatedMinutesPerDay?`, `imageUrl?`
- `RoutineDay` — `dayNumber`, `name`, `slots: List<RoutineSlot>`, `estimatedMinutes?`
- `RoutineSlot` — `exerciseId` (FK), `exerciseName` + `muscleGroup` (denormalizado per ADR-2 de Etapa 2), `targetSets`, `targetRepsMin`, `targetRepsMax`, `restSeconds`, `targetWeightKg?`, `notes?`
- `Exercise` — `id`, `name`, `muscleGroup`, `category`, `techniqueInstructions: List<String>?`, `videoUrl?`, `defaultRestSeconds?`

**Repositorios** — `RoutineRepository` y `ExerciseRepository` con `listAll`, `getById`, `getByIds`. Tests con `FakeFirebaseFirestore`.

**Providers** — `routineByIdProvider.family` y `exerciseByIdProvider.family` ya existen como lookups in-memory O(1). **Cero Firestore reads nuevos** para las dos pantallas.

**Router** — `lib/app/router.dart` usa `go_router` con un `ShellRoute` que envuelve las 5 tabs. `/workout` no tiene sub-rutas hoy. La bottom bar queda visible en cualquier ruta anidada dentro del `ShellRoute`.

**Seed data** — 6 rutinas + ~25 ejercicios. Todos los exercises tienen `techniqueInstructions` (3 cues típicas). Todos los `videoUrl` y `imageUrl` son `null` — la UI tiene que manejar placeholders.

**Scenario ceiling** — último test scenario en main es SCENARIO-070. Los tests nuevos arrancan en SCENARIO-071.

---

## Mockup analysis

### `expandir-plantilla.png` → **RoutineDetailScreen**

Hero photo strip (imageUrl o gradient placeholder) + chip de split/day + day-name hero + stats row (cantidad de ejercicios, total de sets, minutos estimados — **todo derivable del model, no hace falta data de sesión**) + sección "EJERCICIOS" + lista de slots (`exerciseName`, `sets×reps`, `muscleGroup`) + CTA "EDITAR" disabled + CTA "EMPEZAR" disabled (stub Fase 4).

### `detalle-rutina.png` → **OUT OF SCOPE**

Esta otra pantalla muestra una rutina ASIGNADA con barra de progreso semanal e historial de sesiones. Eso es Fase 5 (planes asignados por PF) — **no es este PR**.

### `detalle-ejercicio.png` → **ExerciseDetailScreen**

Hero photo (placeholder, no hay `photoUrl` en el modelo todavía) + breadcrumb "MUSCULO · CATEGORÍA" + nombre del ejercicio hero + stats row (1RM, sessions, progress — todos placeholder Fase 4 mostrando "—") + sección "TÉCNICA" con cues numeradas (`techniqueInstructions`) + sección "HISTORIAL" empty state (Fase 4).

---

## Approach options

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| **A — Screen + `widgets/` (★ recomendado)** | Mirrors home-shell, widgets unit-testables, Fase 4 wirea sobre leafs | Más archivos | Med |
| B — Pantallas monolíticas | Rápido | Untestable granularmente, Fase 4 lo va a romper para refactor | Low |
| C — Promover widgets a `core/widgets/` ya | DRY long-term | Prematuro, agranda scope | High |

**Recomendado: A.** Widget decomposition dentro de `lib/features/workout/presentation/widgets/`. Promover a `core/widgets/` solo cuando otra feature adopte los mismos widgets.

**Routing**: agregar dos sub-`GoRoute`s bajo `/workout` adentro del `ShellRoute` actual:
- `/workout/routine/:routineId` → RoutineDetailScreen
- `/workout/exercise/:exerciseId` → ExerciseDetailScreen

Así la bottom bar queda visible (correcto para browsing de catálogo en Fase 2). Fase 4 con su "session player" hará push como overlay full-screen cuando llegue el momento.

**State**: `routineByIdProvider` + `exerciseByIdProvider` ya están. El único state local es `selectedDayIndex` en `RoutineDetailScreen` — `ConsumerStatefulWidget` con `int` local es la herramienta correcta.

**CTAs disabled** (no hidden): 40% opacity. Preserva el layout del mockup y wirearlas en Fase 4 es one-line change.

---

## Files to create / modify

**Crear**:
- `lib/features/workout/presentation/routine_detail_screen.dart`
- `lib/features/workout/presentation/exercise_detail_screen.dart`
- `lib/features/workout/presentation/widgets/exercise_slot_row.dart`
- `lib/features/workout/presentation/widgets/stat_tile.dart`
- `lib/features/workout/presentation/widgets/technique_instruction_item.dart`
- `test/features/workout/presentation/routine_detail_screen_test.dart`
- `test/features/workout/presentation/exercise_detail_screen_test.dart`
- `test/features/workout/presentation/widgets/exercise_slot_row_test.dart`
- `test/features/workout/presentation/widgets/stat_tile_test.dart`

**Modificar**:
- `lib/app/router.dart` — agregar las 2 sub-rutas.
- `lib/core/widgets/treino_icon.dart` — agregar `TreinoIcon.timer` para el rest indicator.

---

## Risks

1. **`detalle-rutina.png` confusión de scope**: el mockup con barra de progreso semanal es Fase 5 (rutina asignada). Hay que ser explícito en el spec para que ningún dev lo confunda con expandir-plantilla.
2. **Sin `photoUrl` en Exercise**: el hero de ExerciseDetail necesita imagen. Placeholder (gradient o icono de mancuerna). Si en el futuro queremos imágenes reales, agregar `photoUrl: String?` al modelo — additive change, no breaking.
3. **`Routine.imageUrl` null en seed**: mismo problema en RoutineDetail. Placeholder required.
4. **Etapa 3 (`feat/routines-list`) no mergeada todavía**: este PR no tiene entry-point desde un user flow. Documentar shortcut de dev (push temporal desde WorkoutScreen para testing) en el PR description, pero NO shipearlo.
5. **`RoutineDay.slots` puede ser vacío** (válido per SCENARIO-046). Empty state obligatorio.
6. **`Exercise.techniqueInstructions` puede ser null** (ADR-1: "todavía no se autoreó"). Empty state obligatorio.

---

## Out of scope

- "Iniciar entrenamiento" / session tracking → Fase 4.
- Filtros, búsqueda, edición → fuera de este PR.
- Crear rutinas → Fase 5.
- Rutina asignada con progreso semanal (mockup `detalle-rutina.png`) → Fase 5.
- Wire desde Home / Plantillas → Etapa 5 de Fase 2 (Dev B).

---

## Ready for proposal

Sí. Modelos, repositorios y providers existen. Rutas claras. Tests scenario range conocido (071+). No hay bloqueantes — la exploración termina recomendando la Approach A con la modificación de router para sub-rutas y disabled CTAs.

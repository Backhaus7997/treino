# Propose — routine-model-seed

**Change**: `routine-model-seed`
**Fase / Etapa**: Fase 2 · Etapa 2
**Branch**: `feat/routine-model-seed`
**Owner**: Dev B
**Artifact store**: openspec
**Depends on**: explore.md (in this folder)

---

## 1. Why

Fase 2 entrega el catálogo de plantillas de entrenamiento que el atleta podrá explorar. La Etapa 2 es la base de datos del catálogo: sin modelos, repositorio, reglas y seed de Firestore, las Etapas 3 (lista de plantillas), 4 (detalle de día y de ejercicio) y 5 (asignar rutina al usuario) no tienen de dónde leer. Este PR es el cimiento sobre el que se levantan tres etapas más, por lo que cualquier deuda de modelo se paga tres veces. Por eso lo estamos resolviendo bien de entrada y no embebiendo lo que vamos a tener que separar después.

La decisión clave — y la única que se aparta del explore — es **modelo normalizado** (colección `exercises/{id}` separada de `routines/{id}`, referenciada por `RoutineSlot.exerciseId`). El explore recomendaba embebido por simplicidad de lectura, pero el dueño confirmó: "en algún momento lo vamos a tener que hacer". La razón es Fase 4 (Entreno IA): la búsqueda de ejercicios necesita una colección consultable de ejercicios canónicos con `muscleGroup`/`category` indexables. Si embebemos hoy, Fase 4 requiere migración + script de extracción + reescritura de modelos + invalidación de cachés en clientes. Aceptamos un costo upfront (~+25% LOC, una colección extra, un join in-memory) para no pagar migración con datos ya en producción.

---

## 2. What — scope delivered

Un reviewer debe poder verificar lo siguiente como entregado:

### 2.1 Modelos (4, freezed)
- `Exercise` — catálogo canónico. Campos: `id`, `name`, `muscleGroup`, `category` ("compuesto"/"aislamiento"), `techniqueInstructions: List<String>?`, `videoUrl: String?`, `defaultRestSeconds: int?`.
- `Routine` — plantilla. Campos: `id`, `name`, `split`, `level: ExperienceLevel` (reusado), `days: List<RoutineDay>`, `estimatedMinutesPerDay: int?`, `imageUrl: String?`.
- `RoutineDay` — día embebido en `Routine`. Campos: `dayNumber`, `name`, `slots: List<RoutineSlot>`, `estimatedMinutes: int?`.
- `RoutineSlot` — slot embebido en `RoutineDay`, referencia a `Exercise` por ID. Campos: `exerciseId`, `targetSets`, `targetRepsMin`, `targetRepsMax`, `restSeconds`, `targetWeightKg: double?`, `notes: String?`.

Cada modelo en su par `*.dart` / `*.freezed.dart` / `*.g.dart` (limitación de freezed con múltiples clases por archivo).

### 2.2 Repositorios (read-only, concrete classes)
- `ExerciseRepository` — `listAll()` → `Future<List<Exercise>>`, `getById(String id)` → `Future<Exercise?>`.
- `RoutineRepository` — `listAll()` → `Future<List<Routine>>`, `getById(String id)` → `Future<Routine?>`.
- Constructor injection de `FirebaseFirestore` (mismo patrón que `UserRepository`).
- Sin interface/abstract — concrete directo.

### 2.3 Firestore rules
- Bloque `match /exercises/{exerciseId}` → `allow read: if request.auth != null; allow write: if false;`
- Bloque `match /routines/{routineId}` → mismas reglas.
- Catálogo writeable solo via Admin SDK (seed). Cliente nunca escribe.

### 2.4 Providers (Riverpod 2 manual)
- `exerciseRepositoryProvider: Provider<ExerciseRepository>` — singleton.
- `routineRepositoryProvider: Provider<RoutineRepository>` — singleton.
- `exercisesProvider: FutureProvider<List<Exercise>>` — eager load del catálogo completo (≈30 docs).
- `routinesProvider: FutureProvider<List<Routine>>` — eager load del catálogo completo (≈6 docs).
- `exerciseByIdProvider: FutureProvider.family<Exercise?, String>` — lookup individual (deriva de `exercisesProvider` para no refetchar).
- `routineByIdProvider: FutureProvider.family<Routine?, String>` — idem, deriva de `routinesProvider`.

### 2.5 Seed (Node.js + Admin SDK)
- `scripts/seed_workout_catalog.js` — **un solo script** que siembra ambas colecciones en orden: primero `exercises/`, después `routines/` (para que las referencias `exerciseId` ya existan). Justificación en §3.4.
- `scripts/package.json` con `firebase-admin: ^12.x`.
- `scripts/.env.example` documentando `GOOGLE_APPLICATION_CREDENTIALS`.
- Datos: ~25-30 ejercicios únicos + ~6 plantillas (PPL, Full Body, Upper/Lower, etc.).
- Idempotente: usa `set()` con doc ID determinístico (slug del nombre), no `add()`.

### 2.6 `.gitignore`
- `scripts/treino-dev-service-account*.json`
- `scripts/node_modules/`
- `scripts/.env`

### 2.7 Tests (target 21+, scenarios desde SCENARIO-020)
- Roundtrip `toJson` / `fromJson` × 4 modelos.
- Raw-map deserialization tests (nested `List<dynamic>` desde Firestore).
- Enum boundary tests (`ExperienceLevel` reusado en `Routine`).
- Nullable fields tests (`videoUrl`, `imageUrl`, `targetWeightKg`, `notes`).
- Empty `days` array, empty `slots` array.
- `ExerciseRepository.listAll()`, `getById(existing)`, `getById(missing)`.
- `RoutineRepository.listAll()`, `getById(existing)`, `getById(missing)`.

---

## 3. How — architectural approach

### 3.1 Relación de modelos

```
exercises/{id}                       routines/{id}
┌──────────────────┐                 ┌───────────────────────────────┐
│ Exercise         │                 │ Routine                       │
│  id              │◄────────┐       │  id, name, split, level       │
│  name            │         │       │  days: List<RoutineDay>       │
│  muscleGroup     │         │       │   └─ RoutineDay               │
│  category        │         │       │       slots: List<RoutineSlot>│
│  techniqueInstr  │         │       │        └─ RoutineSlot         │
│  videoUrl        │         └───────┤            exerciseId ────────┘
│  defaultRestSec  │     reference   │            targetSets/reps/rest
└──────────────────┘                 └───────────────────────────────┘
   ≈30 docs                              ≈6 docs (days + slots embebidos)
```

`Routine` es self-contained para todo lo estructural (días, slots, sets/reps/rest). El único campo que requiere lookup externo es `RoutineSlot.exerciseId` → `Exercise`. Las dos colecciones son flat (sin subcollections), una sola query por colección las trae enteras.

### 3.2 Provider composition — ejemplo de consumo (Etapa 3)

```dart
// Hipotético en Etapa 3: Card de routine en la lista
final routinesAsync = ref.watch(routinesProvider);
final exercisesAsync = ref.watch(exercisesProvider);

return routinesAsync.when(
  data: (routines) => exercisesAsync.when(
    data: (exercises) {
      final byId = {for (final e in exercises) e.id: e};
      return ListView(
        children: routines.map((r) {
          final totalExercises =
              r.days.expand((d) => d.slots).length;
          // muscleGroups derivados del join in-memory
          final groups = r.days
              .expand((d) => d.slots)
              .map((s) => byId[s.exerciseId]?.muscleGroup)
              .whereType<String>()
              .toSet();
          return RoutineCard(routine: r, exerciseCount: totalExercises, muscleGroups: groups);
        }).toList(),
      );
    },
    loading: () => const _Loading(),
    error: (e, st) => _Error(e),
  ),
  // ...
);
```

### 3.3 Dónde vive el join — decisión

**Resolved: el join se hace en el widget**, vía `ref.watch(routineByIdProvider(id))` + `ref.watch(exerciseByIdProvider(slot.exerciseId))` (o el patrón de mapa local mostrado arriba). NO se introduce un `hydratedRoutineByIdProvider` en esta PR.

Justificación:
- `exerciseByIdProvider` y `routineByIdProvider` se derivan de los `FutureProvider` lista, por lo que el join es O(1) en memoria una vez cargado el catálogo (un solo `Map` cacheable).
- Crear un modelo "hydratado" (e.g. `HydratedRoutine` con `RoutineSlot` reemplazado por `Slot + Exercise`) duplica tipos y agrega serialization que nadie necesita.
- Etapas 3/4 son las que consumen — que decidan cuándo necesitan un provider derivado. YAGNI para este PR.

### 3.4 Estructura del seed — decisión

**Resolved: un solo script** `scripts/seed_workout_catalog.js`. Justificación (KISS + reviewability):
- Las referencias `exerciseId` requieren orden estricto: ejercicios primero. Dos scripts obligan a documentar y enforce ese orden externamente.
- ~30 + 6 docs cabe en un archivo legible (~250 líneas con datos inline). Un solo PR review.
- Idempotencia: doc IDs determinísticos (`bench-press`, `push-pull-legs-beginner`) + `set()` upserts. Re-ejecutar es seguro.
- Estructura del archivo:
  1. `const exercises = [{ id: 'bench-press', ... }, ...]`
  2. `const routines = [{ id: 'ppl-beginner', days: [{ slots: [{ exerciseId: 'bench-press', ... }] }] }]`
  3. `async function seed() { await seedExercises(); await seedRoutines(); }`

### 3.5 File organization — mirror de `lib/features/profile/`

```
lib/features/workout/
├── domain/
│   ├── exercise.dart            (+ .freezed.dart + .g.dart)
│   ├── routine.dart             (+ .freezed.dart + .g.dart)
│   ├── routine_day.dart         (+ .freezed.dart + .g.dart)
│   └── routine_slot.dart        (+ .freezed.dart + .g.dart)
├── data/
│   ├── exercise_repository.dart
│   └── routine_repository.dart
└── application/
    ├── exercise_providers.dart
    └── routine_providers.dart
```

NOTA: el explore mencionaba `RoutineExercise` — por el cambio a normalized se renombra a `RoutineSlot` para que el nombre comunique "slot en el día que referencia un ejercicio" en lugar de "ejercicio embebido". Decision §4.7.

---

## 4. Trade-offs aceptados

| # | Decisión | Rationale (una línea) |
|---|---|---|
| 4.1 | **Modelo normalizado** (locked) | Evita migración cuando Fase 4 agrega AI search sobre `exercises`. |
| 4.2 | **Node.js para seed** (locked) | SDK oficial maduro; Node ya requerido por Firebase CLI. |
| 4.3 | **Reusar `ExperienceLevel`** de `profile/domain/` (locked) | Mismo wire value, mismo significado de UI; duplicar viola DRY. |
| 4.4 | **Eager load del catálogo** vía `FutureProvider` (locked) | ~30 ejercicios + 6 routines = payload trivial; lazy per-routine introduce N+1 sin beneficio. |
| 4.5 | **Join en widget**, no `HydratedRoutine` provider | YAGNI; consumidores de Etapas 3/4 decidirán si necesitan un derivado. |
| 4.6 | **Seed en un solo script** | Orden estricto exercises→routines + 30+6 docs caben legibles en un archivo. |
| 4.7 | **Rename `RoutineExercise` → `RoutineSlot`** | "Slot" comunica referencia + override de sets/reps; "Exercise" embebido era ambiguo en el modelo normalizado. |
| 4.8 | **Sin validación de orphan refs** en repo (ver §7) | Trust en el seed; validación es Fase 4 cuando haya CRUD de routines. |

---

## 5. Out-of-scope (explícito, reproducido del explore)

- Session execution / workout logging (`sesion-dia.png`) → Fase 4
- "Último peso" por exercise → Fase 4 (session history)
- Routines asignadas a usuarios (`users/{uid}/routines/{id}`) → Fase 5
- Crear/editar/eliminar routines desde la app → Fase 5
- Excel import → Fase 5.5
- Entreno IA exercise search → Fase 4
- Video playback UI → Fase 4
- UI de lista, detalle de día, detalle de ejercicio → Etapas 3 y 4 de Fase 2
- Cambios en `lib/app/router.dart`, `lib/features/profile/`, `lib/features/home/`, `lib/features/auth/`
- `route guards` / redirect logic → fuera

---

## 6. Success criteria (observables)

1. Los 4 modelos compilan con `dart run build_runner build --delete-conflicting-outputs` sin errores.
2. Roundtrip `toJson`/`fromJson` × 4 modelos pasan (incluye raw-map nested case).
3. `ExerciseRepository` + `RoutineRepository` pasan con `fake_cloud_firestore`: `listAll`, `getById` (hit + miss).
4. `flutter analyze` 0 issues.
5. `dart format .` clean (sin diff).
6. Suite completa de tests verde (`flutter test`).
7. `scripts/seed_workout_catalog.js` corre exitoso contra el proyecto Firebase con service account JSON; deja ~30 docs en `exercises/` y ~6 en `routines/`.
8. Firestore rules deployadas: lectura con auth funciona; escritura sin Admin SDK rechazada (`firebase emulators:exec` o test manual con el cliente).
9. Coverage cuantitativa: **21+ tests** nuevos pasando (4 roundtrip + 4 raw-map + 4 nullable/empty edge + 3 enum boundary + 6 repo + 0 extra de buffer; ajustable).
10. `.gitignore` excluye service account JSON y `scripts/node_modules/`; `git status` después de instalar Node deps no muestra secrets.

---

## 7. Risks (priority-ordered)

### P0 — Service account JSON leak
- **Riesgo**: Un `git add .` antes del update de `.gitignore` stagea el secret irreversiblemente; rotación + audit de repo.
- **Mitigación**: La **primera task** del apply phase es agregar las líneas a `.gitignore` y commitearlas. Recién después se baja el JSON de la consola de Firebase. Documentar en `scripts/.env.example`.

### P1 — Orphan `exerciseId` references
- **Riesgo**: `RoutineSlot.exerciseId` apunta a un `Exercise.id` que no existe (seed mal escrito, ejercicio renombrado).
- **Mitigación**: NO se valida en el repo (decisión 4.8 — trust del seed). El seed script incluye una validación local antes de escribir: itera los `slots` de cada routine y verifica que cada `exerciseId` esté en `const exercises[]`. Falla con error claro antes de tocar Firestore. Esto vive en el script, no en el modelo Dart.

### P2 — Nested `List<dynamic>` deserialization
- **Riesgo**: Firestore devuelve `List<dynamic>` para `days` y `slots`; `json_serializable` casteea pero hay edge cases con mapas anidados.
- **Mitigación**: Test raw-map estilo SCENARIO-004: armar un `Map<String, dynamic>` literal que mimetice el wire format de Firestore y pasarlo por `Routine.fromJson`. Cubrir caso con `days` vacío, `slots` vacío, y campos opcionales `null`.

### P3 — Seed idempotency
- **Riesgo**: Re-correr el seed duplica docs.
- **Mitigación**: Doc IDs determinísticos (`bench-press`, `ppl-beginner`) + `set()` (upsert) en lugar de `add()` (autogenerated ID). Documentar en `scripts/README` o en comentario del script.

### P4 — Cross-feature import `workout → profile`
- **Riesgo**: `routine.dart` importa `experience_level.dart` de `features/profile/domain/`. Acoplamiento entre features.
- **Mitigación**: Aceptado. `ExperienceLevel` es un value enum sin behavior (no depende de Firestore ni de UI). Duplicarlo crea divergencia de wire values. Si en el futuro se vuelve pesado, se mueve a `lib/core/domain/` — refactor mecánico.

### P5 — Provider join performance
- **Riesgo**: 6 routines × ~6 days × ~6 slots = ~216 lookups in-memory en el peor caso.
- **Mitigación**: 216 lookups sobre un `Map<String, Exercise>` de tamaño 30 es ~µs. Documentar en docstring del provider. No optimizar prematuramente.

### P6 — LOC budget — **decision point**
- **Riesgo**: Estimado ~400 LOC production + ~600 LOC tests = ~1000 LOC across ~25 files. Production está justo en el threshold de 400.
- **Mitigación / Recomendación**: ver §8.

---

## 8. Review Workload Forecast

| Métrica | Valor |
|---|---|
| Estimated production LOC | ~400 (≈110 modelos + freezed gen out-of-diff, ~120 repos, ~80 providers, ~30 rules + gitignore + script wiring, ~60 seed JS no generated) |
| Estimated test LOC | ~600 (4 model files × ~80 + 2 repo files × ~120 + helpers) |
| Estimated total diff | ~1000 LOC across ~25 files (incluye `*.freezed.dart` / `*.g.dart` generados — ~12 archivos) |
| Production budget (400) risk | **High** (justo en el threshold) |
| Chained PRs recommended | **YES** |
| Decision needed before apply | **YES** |

### Chained PR proposal

Si el delivery strategy del orchestrator es `ask-on-risk` (configurado para esta sesión), recomendamos chained PRs:

- **PR 1 — `routine-model-seed/exercises`** (~180 prod + ~250 test)
  - `.gitignore` update (FIRST task de apply, mitiga P0)
  - `Exercise` model + freezed/g
  - `ExerciseRepository`
  - `exerciseRepositoryProvider`, `exercisesProvider`, `exerciseByIdProvider`
  - `firestore.rules` → bloque `exercises/{id}`
  - `scripts/seed_workout_catalog.js` (solo función `seedExercises()` + datos)
  - `scripts/package.json`, `scripts/.env.example`
  - Tests: Exercise roundtrip + ExerciseRepository

- **PR 2 — `routine-model-seed/routines`** (~220 prod + ~350 test)
  - `Routine`, `RoutineDay`, `RoutineSlot` models + freezed/g
  - `RoutineRepository`
  - `routineRepositoryProvider`, `routinesProvider`, `routineByIdProvider`
  - `firestore.rules` → bloque `routines/{id}`
  - `scripts/seed_workout_catalog.js` (agrega función `seedRoutines()` + datos + validación de orphan refs)
  - Tests: Routine/Day/Slot roundtrips + RoutineRepository

PR 1 entrega un slice autónomo: el catálogo de ejercicios queda consultable desde el cliente, lo que ya habilita feature flags de exploración. PR 2 lo conecta a las plantillas.

### Si el usuario prefiere single PR
- Requiere `size:exception` con justificación: change foundational + ~50% del diff son archivos generados.
- Trade-off: review más pesado, pero atómico (los modelos de routine son inútiles sin Exercise existiendo).

**Recomendación final**: chained (PR 1 + PR 2). El orchestrator debe pausar y consultar al usuario antes de lanzar `sdd-apply`.

---

**Next recommended**: `sdd-spec` y `sdd-design` (pueden correr en paralelo).

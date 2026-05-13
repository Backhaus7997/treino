# Explore — routine-model-seed

**Change**: `routine-model-seed`
**Fase / Etapa**: Fase 2 · Etapa 2
**Branch**: `feat/routine-model-seed`
**Owner**: Dev B (shifted from A — A y C bloqueados en otra cosa)
**Scope**: Models (`Routine`, `RoutineDay`, `RoutineExercise`), `RoutineRepository` (read-only), `routines/{id}` Firestore rules, seed script Node.js, Riverpod providers.

---

## Patrones existentes a copiar

### Models (`lib/features/profile/domain/`)
- `@freezed` + `json_serializable`, single `const factory` constructor, `fromJson`/`toJson` via `part` files generados.
- Enums: plain Dart enum + `@JsonValue` + extension con `_wireMap`. Pattern en `user_role.dart`, `gender.dart`, `experience_level.dart`.
- Timestamps: `@TimestampConverter()` en `DateTime` — converter en `lib/features/profile/data/timestamp_converter.dart` (no aplica acá, `Routine` no tiene timestamps).

### Repository (`lib/features/profile/data/user_repository.dart`)
- Constructor injection de `FirebaseFirestore` — testeable con `FakeFirebaseFirestore`.
- Private collection getter: `get _collection => _firestore.collection('routines')`.
- Read methods retornan `Future<T?>` para single doc, `Future<List<T>>` para colección.
- Sin interface/abstract — concrete class directo.

### Providers (`lib/features/profile/application/user_providers.dart`)
- Manual Riverpod 2 — sin `@riverpod` codegen.
- `firestoreProvider` ya existe (singleton) — reusable.
- Pattern auth-gated: watch `authStateChangesProvider`, return empty/null si no auth.

### Firestore rules (`firestore.rules`)
- Hoy solo `match /users/{uid}`. Sin wildcard catch-all — colecciones nuevas implícitamente denied.
- Agregar `match /routines/{routineId}` es clean, no conflicto.

### Tests
- `fake_cloud_firestore: ^3.0.3` ya en dev deps.
- Pattern: `setUp` crea `FakeFirebaseFirestore` + repo, helper siembra data directo, tests llaman repo.
- Domain tests: roundtrip `toJson()`/`fromJson()` + enum boundary.
- Scenario range existente: SCENARIO-001 → SCENARIO-019. Nuevos arrancan en **SCENARIO-020**.
- Strict TDD activo — tests antes que código en apply.

### Feature folder decision
El stub existente es `lib/features/workout/` (sin "s") — coincide con `workout_screen.dart`. Todo nuevo va bajo `lib/features/workout/`.

---

## Mockup analysis

### `plantillas.png` — campos por card de la lista (Etapa 3)
- `name` (UPPERCASE)
- `level` (ExperienceLevel)
- Total ejercicios (derivado: `days.expand((d) => d.exercises).length`)
- Icon/category identifier

### `expandir-plantilla.png` — campos por day detail (Etapa 4)
- `dayNumber`, `name`, `estimatedMinutesPerDay`
- Total exercise count + total sets (derivados)
- Por ejercicio: `exerciseName`, `targetSets × targetRepsMin–targetRepsMax`, `muscleGroup`
- "ÚLTIMO" weight = user session history (Fase 4) — **NO** en el template model

### `detalle-ejercicio.png` — campos por exercise detail (Etapa 4)
- `exerciseName`, `muscleGroup`, `category` ("compuesto"/"aislamiento")
- `techniqueInstructions: List<String>` (cues numerados)
- `videoUrl: String?` (nullable, player es Fase 4)
- Stats (1RM, sessions, progress %) = computados de session history — **NO** en template

### `tu-rutina.png` — campos por routine card (asignada, Fase 5)
- `name`, day count (derivado), exercise count (derivado), `split`

---

## Proposed model shape (Option A — Fully Embedded)

```dart
// lib/features/workout/domain/routine.dart
@freezed
class Routine with _$Routine {
  const factory Routine({
    required String id,
    required String name,
    required String split,            // "PPL", "Full Body", "Upper/Lower"
    required ExperienceLevel level,   // reusa el enum de profile/domain
    required List<RoutineDay> days,
    int? estimatedMinutesPerDay,
    String? imageUrl,
  }) = _Routine;

  factory Routine.fromJson(Map<String, Object?> json) => _$RoutineFromJson(json);
}

@freezed
class RoutineDay with _$RoutineDay {
  const factory RoutineDay({
    required int dayNumber,
    required String name,
    required List<RoutineExercise> exercises,
    int? estimatedMinutes,
  }) = _RoutineDay;

  factory RoutineDay.fromJson(Map<String, Object?> json) =>
      _$RoutineDayFromJson(json);
}

@freezed
class RoutineExercise with _$RoutineExercise {
  const factory RoutineExercise({
    required String exerciseId,
    required String exerciseName,
    required String muscleGroup,
    required String category,
    required int targetSets,
    required int targetRepsMin,
    required int targetRepsMax,
    required int restSeconds,
    List<String>? techniqueInstructions,
    double? targetWeightKg,
    String? videoUrl,
  }) = _RoutineExercise;

  factory RoutineExercise.fromJson(Map<String, Object?> json) =>
      _$RoutineExerciseFromJson(json);
}
```

Documento Firestore: `routines/{id}` — un doc por routine, `days` es array embebido, cada day tiene `exercises` array embebido. **UNA sola lectura** trae todo. Sin subcollections.

---

## Approaches

### a) Model shape

| Approach | Pros | Cons | Esfuerzo |
|---|---|---|---|
| **A — Fully embedded** ★ | 1 read, rules simples, seed simple | Data denormalizada cross-routines | Bajo |
| B — Normalized (`exercises` collection separada) | Reusable para AI search Fase 4 | 2-layer reads, join logic, más rules | Alto |
| C — Subcollections por day | Escala a routines gigantes | Multi reads, complejo, overkill para catálogo | Alto |

### d) Admin SDK language

| Approach | Pros | Cons | Esfuerzo |
|---|---|---|---|
| **A — Node.js** ★ | SDK maduro, documentado, Firebase CLI ya requiere Node | Runtime extra (ya está) | Bajo |
| B — Dart + `googleapis_auth` REST | Stack match | No hay SDK oficial Dart, auth manual, frágil | Alto |
| C — `dart_firebase_admin` (unofficial) | Dart native | No oficial, problemas auth históricos | Medio |
| D — Console manual | Sin código | No reproducible, error-prone para 6 routines × N exercises | One-time |

### g) Provider type

| Approach | Pros | Cons | Esfuerzo |
|---|---|---|---|
| **A — FutureProvider** ★ | One-shot, sin listener, semántica correcta para catálogo estático | Sin live updates | Bajo |
| B — StreamProvider | Live updates | Listener persistente innecesario para data inmutable | Bajo |

---

## Recommendations

1. **Model**: Option A (fully embedded). 6-10 plantillas escala perfecto.
2. **Admin SDK**: Node.js — única opción production-safe.
3. **Providers**: `FutureProvider<List<Routine>>` + `FutureProvider.family<Routine?, String>`.
4. **Feature folder**: `lib/features/workout/`.
5. **ExperienceLevel**: importar de `profile/domain/experience_level.dart` — same wire values, same UI.

---

## File map

### Nuevos

| Path | Descripción |
|---|---|
| `lib/features/workout/domain/routine.dart` | Model |
| `lib/features/workout/domain/routine.freezed.dart` | Generated |
| `lib/features/workout/domain/routine.g.dart` | Generated |
| `lib/features/workout/domain/routine_day.dart` | Model |
| `lib/features/workout/domain/routine_day.freezed.dart` | Generated |
| `lib/features/workout/domain/routine_day.g.dart` | Generated |
| `lib/features/workout/domain/routine_exercise.dart` | Model |
| `lib/features/workout/domain/routine_exercise.freezed.dart` | Generated |
| `lib/features/workout/domain/routine_exercise.g.dart` | Generated |
| `lib/features/workout/data/routine_repository.dart` | `listAll()` + `getById(id)` |
| `lib/features/workout/application/routine_providers.dart` | `routinesProvider` + `routineByIdProvider` |
| `scripts/seed_routines.js` | Seed Node.js con 6 plantillas |
| `scripts/package.json` | `{ "dependencies": { "firebase-admin": "^12.x" } }` |
| `scripts/.env.example` | Doc del var `GOOGLE_APPLICATION_CREDENTIALS` |
| `test/features/workout/domain/routine_test.dart` | Roundtrip tests, SCENARIO-020+ |
| `test/features/workout/domain/routine_day_test.dart` | Day model tests |
| `test/features/workout/domain/routine_exercise_test.dart` | Exercise model tests |
| `test/features/workout/data/routine_repository_test.dart` | Repo tests con FakeFirebaseFirestore |

### Modificados

| Path | Cambio |
|---|---|
| `firestore.rules` | Agregar `match /routines/{routineId}` block |
| `.gitignore` | Agregar `scripts/treino-dev-service-account.json` + `scripts/node_modules/` |

### Sin cambios

`pubspec.yaml` — todos los packages necesarios (`freezed_annotation`, `json_annotation`, `cloud_firestore`) ya están. **Cero deps nuevas de Flutter**.

---

## Risks

1. **Service account leak** — `.gitignore` update debe ser la **PRIMERA** task del apply. Un `git add .` antes de eso stage-aría el secret irreversiblemente.
2. **Deserialización de `List<dynamic>` anidados** — Firestore devuelve `List<dynamic>` para arrays. `json_serializable` lo casteea para `List<RoutineDay>`, pero hay que cubrir con un test raw-map (estilo SCENARIO-004 de UserProfile) para cazar edge cases.
3. **Archivos freezed separados obligatorios** — Freezed no soporta múltiples `@freezed` classes compartiendo el mismo par de `part`. Cada uno de `Routine`/`RoutineDay`/`RoutineExercise` necesita su trío `*.dart` + `*.freezed.dart` + `*.g.dart`. Apply tiene que correr `dart run build_runner build --delete-conflicting-outputs` después de crear los 3.
4. **Node.js dependency** — Dev tiene que tener Node. Firebase CLI ya lo requiere, así que safe assumption. Documentar en CONTRIBUTING.md.
5. **Scenario numbering** — Nuevos tests arrancan en SCENARIO-020.
6. **Cross-feature import** `workout → profile` — `routine.dart` va a importar `experience_level.dart` de `profile/domain/`. Es un value enum sin behavior — acceptable. Alternativa: duplicar enum (rejected, viola DRY).

---

## Out-of-scope (explícito)

- Session execution / workout logging (`sesion-dia.png`) → Fase 4
- "Último peso" por exercise → Fase 4 session history
- Routines asignadas a usuarios (`users/{uid}/routines/{id}`) → Fase 5
- Crear/editar/eliminar routines desde app → Fase 5
- Excel import → Fase 5.5
- Entreno IA exercise search → Fase 4
- Video playback UI → Fase 4

---

## Decisiones abiertas para propose

a. **Model shape**: Option A (embedded) ★ recomendado
b. **Models en archivos separados**: ★ obligatorio por limitación de freezed
c. **`ExperienceLevel` reuse vs duplicar**: ★ reuse recomendado
d. **Admin SDK language**: Node.js ★ recomendado
e. **Seed format**: inline JS objects ★ recomendado
f. **`.gitignore` pattern**: `scripts/treino-dev-service-account.json` ★ específico recomendado
g. **Provider type**: FutureProvider ★ recomendado
h. **`estimatedMinutesPerDay` storage**: campo en RoutineDay ★ recomendado
i. **Feature folder**: `lib/features/workout/` ★ confirmado

---

**Next recommended**: `sdd-propose`

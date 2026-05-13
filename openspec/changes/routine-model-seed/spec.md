# Spec — routine-model-seed

**Change**: `routine-model-seed`
**Fase / Etapa**: Fase 2 · Etapa 2
**Artifact store**: openspec
**Depends on**: propose.md, explore.md

---

## Overview

This spec defines the delta that must be true after `routine-model-seed` is merged. It covers two
Firestore collections (`exercises/{id}` and `routines/{id}`), four Dart models, two read-only
repositories, Riverpod providers, Firestore security rules, a Node.js seed script, and associated
bootstrap files. No UI code is delivered. The change is split into two chained PRs; each section
below corresponds to one PR slice.

**Test scenario numbering**: starts at SCENARIO-020 (project range 001–019 already used).
**Strict TDD**: apply phase writes each test scenario BEFORE the corresponding production code.

---

## PR 1 — Exercise collection

### REQ-EX-MODEL-001 — Exercise model shape

The file `lib/features/workout/domain/exercise.dart` MUST declare a `@freezed` class `Exercise`
with the following field contract:

| Field | Type | Required |
|---|---|---|
| `id` | `String` | yes |
| `name` | `String` | yes |
| `muscleGroup` | `String` | yes |
| `category` | `String` | yes |
| `techniqueInstructions` | `List<String>?` | no |
| `videoUrl` | `String?` | no |
| `defaultRestSeconds` | `int?` | no |

`category` wire values are `"compound"` / `"isolation"` (English, consistent with seed data).
The model MUST have a `fromJson` factory and a `toJson()` method generated via `json_serializable`.
Generated part files MUST be `exercise.freezed.dart` and `exercise.g.dart`.
No `@TimestampConverter` — `Exercise` has no DateTime fields.

#### Scenarios

- **SCENARIO-020**: GIVEN an `Exercise` with all required fields and all nullable fields null,
  WHEN `toJson()` is called and the result is passed to `Exercise.fromJson()`,
  THEN the decoded instance equals the original and all nullable fields are null.

- **SCENARIO-021**: GIVEN an `Exercise` with all 7 fields populated (including
  `techniqueInstructions: ['cue1', 'cue2']`, `videoUrl: 'https://v.example.com/1'`,
  `defaultRestSeconds: 90`),
  WHEN roundtrip (`toJson` → `fromJson`),
  THEN all fields are equal, `techniqueInstructions` has length 2 and preserves order.

- **SCENARIO-022**: GIVEN a raw `Map<String, dynamic>` that mimics the Firestore wire format
  (with `techniqueInstructions` as a `List<dynamic>` containing plain `String` values),
  WHEN `Exercise.fromJson(rawMap)` is called,
  THEN the resulting `techniqueInstructions` is of type `List<String>` with correct values.

- **SCENARIO-023**: GIVEN a raw map where `techniqueInstructions`, `videoUrl`, and
  `defaultRestSeconds` are all absent (keys missing, not explicitly null),
  WHEN `Exercise.fromJson(rawMap)`,
  THEN those fields are `null` and no exception is thrown.

---

### REQ-EX-MODEL-002 — Exercise model isolation

`Exercise` MUST NOT import any file from `lib/features/profile/` or any other feature domain.
`Exercise` MUST NOT redefine `ExperienceLevel` — that enum does not apply to `Exercise`.

#### Scenarios

- **SCENARIO-024**: GIVEN the compiled `exercise.dart` source,
  WHEN `flutter analyze` is run,
  THEN zero issues are reported on that file and its generated parts.

---

### REQ-EX-REPO-001 — ExerciseRepository public API

The class `ExerciseRepository` in `lib/features/workout/data/exercise_repository.dart` MUST expose:

```dart
ExerciseRepository({required FirebaseFirestore firestore})
Future<List<Exercise>> listAll()
Future<Exercise?> getById(String id)
Future<List<Exercise>> getByIds(List<String> ids)
```

It MUST read from the Firestore collection `exercises` (path: `exercises/{exerciseId}`).
It MUST NOT have write methods. It MUST NOT define an abstract interface — concrete class only.
Constructor injection of `FirebaseFirestore` is required (same pattern as `UserRepository`).

#### Scenarios

- **SCENARIO-025**: GIVEN an empty `exercises` collection in `FakeFirebaseFirestore`,
  WHEN `exerciseRepo.listAll()` is called,
  THEN it returns an empty `List<Exercise>`.

- **SCENARIO-026**: GIVEN 5 exercise documents seeded into `FakeFirebaseFirestore`,
  WHEN `exerciseRepo.listAll()` is called,
  THEN it returns a `List<Exercise>` of length 5 and each item deserializes correctly.

- **SCENARIO-027**: GIVEN an exercise with id `'bench-press'` seeded into `FakeFirebaseFirestore`,
  WHEN `exerciseRepo.getById('bench-press')` is called,
  THEN it returns a non-null `Exercise` with `id == 'bench-press'`.

- **SCENARIO-028**: GIVEN no document with id `'nonexistent'` in `FakeFirebaseFirestore`,
  WHEN `exerciseRepo.getById('nonexistent')` is called,
  THEN it returns `null`.

- **SCENARIO-029**: GIVEN 3 exercises seeded (`'squat'`, `'deadlift'`, `'bench-press'`),
  WHEN `exerciseRepo.getByIds(['squat', 'deadlift'])` is called,
  THEN it returns exactly 2 exercises and `'bench-press'` is not included.

- **SCENARIO-030**: GIVEN `getByIds` is called with an empty list,
  WHEN the call completes,
  THEN it returns an empty list without querying Firestore.

---

### REQ-EX-REPO-002 — ExerciseRepository uses correct collection path

The internal collection reference MUST use `'exercises'` as the collection name.
No subcollections. Flat collection.

#### Scenarios

- **SCENARIO-031**: GIVEN a document manually inserted at `exercises/push-up` in
  `FakeFirebaseFirestore`,
  WHEN `exerciseRepo.getById('push-up')` is called,
  THEN the repository finds the document (confirming collection path is `'exercises'`).

---

### REQ-EX-RULES-001 — Firestore rules for exercises collection

`firestore.rules` MUST contain a `match /exercises/{exerciseId}` block with exactly:

```
allow read: if request.auth != null;
allow write: if false;
```

No other permissions on this collection. The block MUST be added without modifying any existing
`match /users/{uid}` block. The rules file MUST still compile (`firebase deploy --only firestore:rules`
dry-run or equivalent emulator validation passes).

#### Scenarios

- **SCENARIO-032**: GIVEN the deployed `firestore.rules` and an authenticated client,
  WHEN a GET request is made to `exercises/{anyId}`,
  THEN the read is allowed.

- **SCENARIO-033**: GIVEN the deployed `firestore.rules` and an authenticated client,
  WHEN a WRITE request is made to `exercises/{anyId}` from the client SDK,
  THEN the write is denied (only Admin SDK can write).

- **SCENARIO-034**: GIVEN the deployed `firestore.rules` and an unauthenticated client,
  WHEN a GET request is made to `exercises/{anyId}`,
  THEN the read is denied.

---

### REQ-EX-PROVIDERS-001 — Exercise providers

The file `lib/features/workout/application/exercise_providers.dart` MUST declare:

| Provider | Type | Description |
|---|---|---|
| `exerciseRepositoryProvider` | `Provider<ExerciseRepository>` | Singleton; reads `firestoreProvider` from `user_providers.dart` |
| `exercisesProvider` | `FutureProvider<List<Exercise>>` | Eager-loads full catalogue; auth-gated (returns `[]` if not authenticated) |
| `exerciseByIdProvider` | `FutureProvider.family<Exercise?, String>` | Derives from `exercisesProvider`; O(1) lookup via in-memory map |

`firestoreProvider` MUST be imported from `lib/features/profile/application/user_providers.dart`
(not redeclared).
`exercisesProvider` MUST watch `authStateChangesProvider`; if user is null it returns `[]`
(same auth-gate pattern as `userProfileProvider`).
`exerciseByIdProvider` MUST NOT re-fetch from Firestore — it filters the already-loaded list.

#### Scenarios

- **SCENARIO-035**: GIVEN a `ProviderContainer` with `authStateChangesProvider` overridden to
  return `null` (unauthenticated),
  WHEN `exercisesProvider` is read,
  THEN it resolves to an empty `List<Exercise>` without error.

- **SCENARIO-036**: GIVEN a `ProviderContainer` with `authStateChangesProvider` overridden to
  return a mock `User` and `exerciseRepositoryProvider` overridden to return a repo backed by
  `FakeFirebaseFirestore` with 3 exercises seeded,
  WHEN `exercisesProvider` is awaited,
  THEN it resolves to a list of 3 exercises.

- **SCENARIO-037**: GIVEN `exercisesProvider` resolves with a list containing an exercise with
  id `'deadlift'`,
  WHEN `exerciseByIdProvider('deadlift')` is awaited,
  THEN it returns that exercise (non-null, correct id).

- **SCENARIO-038**: GIVEN `exercisesProvider` resolves with a list that does not contain
  id `'ghost'`,
  WHEN `exerciseByIdProvider('ghost')` is awaited,
  THEN it returns `null`.

---

### REQ-EX-SEED-001 — seedExercises function

The file `scripts/seed_workout_catalog.js` MUST export (or define at module scope) an async
function `seedExercises()` that writes exercise documents to the `exercises` Firestore collection
using the Firebase Admin SDK. Requirements:

- Minimum 25 exercises, covering at least 6 distinct `muscleGroup` values.
- Each document ID is a deterministic kebab-case slug (e.g. `'bench-press'`, `'back-squat'`).
- Uses `set()` (upsert), not `add()` — re-running produces the same result (idempotent).
- Each document MUST include: `id`, `name`, `muscleGroup`, `category`, and `techniqueInstructions`
  (at least one cue per exercise). `videoUrl` and `defaultRestSeconds` are optional.

#### Scenarios

- **SCENARIO-039**: GIVEN the script is run twice against an empty Firestore project,
  WHEN both runs complete,
  THEN the `exercises` collection has the same document count as after a single run (idempotency).

- **SCENARIO-040**: GIVEN the script has finished,
  WHEN all exercise documents are read from Firestore,
  THEN every document has `id`, `name`, `muscleGroup`, `category`, and `techniqueInstructions`
  fields present and non-empty.

---

### REQ-EX-BOOT-001 — Bootstrap files

The following files MUST exist after PR 1 is merged:

| File | Content requirement |
|---|---|
| `scripts/package.json` | MUST declare `"firebase-admin": "^12.x"` in `dependencies` |
| `scripts/.env.example` | MUST document `GOOGLE_APPLICATION_CREDENTIALS=./treino-dev-service-account.json` with a comment |
| `.gitignore` | MUST exclude `scripts/treino-dev-service-account*.json`, `scripts/node_modules/`, and `scripts/.env` |

The `.gitignore` update is the FIRST task in apply — it MUST be committed before any service
account JSON is downloaded.

#### Scenarios

- **SCENARIO-041**: GIVEN `scripts/.env.example` is present,
  WHEN it is read,
  THEN it contains `GOOGLE_APPLICATION_CREDENTIALS` and an explanation comment.

- **SCENARIO-042**: GIVEN `.gitignore` has been updated and a file matching
  `scripts/treino-dev-service-account.json` exists locally,
  WHEN `git status` is run,
  THEN that file does NOT appear as untracked or staged.

---

## PR 2 — Routine collection

### REQ-RT-MODEL-001 — RoutineSlot model shape and denormalization contract

The file `lib/features/workout/domain/routine_slot.dart` MUST declare a `@freezed` class
`RoutineSlot`. Field contract:

| Field | Type | Required | Denorm? |
|---|---|---|---|
| `exerciseId` | `String` | yes | — (FK, canonical reference) |
| `exerciseName` | `String` | yes | YES — denorm for compact list display |
| `muscleGroup` | `String` | yes | YES — denorm for compact list display |
| `targetSets` | `int` | yes | — |
| `targetRepsMin` | `int` | yes | — |
| `targetRepsMax` | `int` | yes | — |
| `restSeconds` | `int` | yes | — |
| `targetWeightKg` | `double?` | no | — |
| `notes` | `String?` | no | — |

**Explicit denormalization rule** (locked decision from propose.md §3.3 and §4.8):
- `exerciseName` and `muscleGroup` ARE denormalized in `RoutineSlot` because Etapa 3/4 screens
  display them in compact cards WITHOUT joining to `Exercise` on every render.
- `techniqueInstructions` and `videoUrl` are NOT stored in `RoutineSlot`. Those fields exist
  exclusively in `Exercise` and MUST be fetched via `exerciseByIdProvider(slot.exerciseId)` when
  the detail screen requires them (Etapa 4).
- There is NO `exerciseName` / `muscleGroup` field on `RoutineSlot` that could diverge silently
  from `Exercise`; the seed script is the single point of truth for their initial values.

#### Scenarios

- **SCENARIO-043**: GIVEN a `RoutineSlot` with all required fields and all nullable fields null,
  WHEN roundtrip `toJson` → `fromJson`,
  THEN decoded instance equals original and nullable fields are null.

- **SCENARIO-044**: GIVEN a `RoutineSlot` with `targetWeightKg: 80.5` and `notes: 'tempo 3-1-1'`,
  WHEN roundtrip `toJson` → `fromJson`,
  THEN `targetWeightKg == 80.5` and `notes == 'tempo 3-1-1'`.

- **SCENARIO-045**: GIVEN a raw `Map<String, dynamic>` for a `RoutineSlot` with `targetWeightKg`
  and `notes` keys absent,
  WHEN `RoutineSlot.fromJson(rawMap)`,
  THEN both nullable fields are `null` with no exception.

---

### REQ-RT-MODEL-002 — RoutineDay model shape

The file `lib/features/workout/domain/routine_day.dart` MUST declare a `@freezed` class
`RoutineDay`. Field contract:

| Field | Type | Required |
|---|---|---|
| `dayNumber` | `int` | yes |
| `name` | `String` | yes |
| `slots` | `List<RoutineSlot>` | yes |
| `estimatedMinutes` | `int?` | no |

The `slots` field serializes the embedded array of `RoutineSlot` objects. Empty list is valid.

#### Scenarios

- **SCENARIO-046**: GIVEN a `RoutineDay` with `slots: []` and `estimatedMinutes: null`,
  WHEN roundtrip `toJson` → `fromJson`,
  THEN `slots` is an empty list and `estimatedMinutes` is null.

- **SCENARIO-047**: GIVEN a `RoutineDay` with 3 `RoutineSlot` entries,
  WHEN roundtrip `toJson` → `fromJson`,
  THEN `slots` has length 3 and each slot's `exerciseId` is preserved.

- **SCENARIO-048**: GIVEN a raw Firestore wire map where `slots` is `List<dynamic>` containing
  raw slot maps,
  WHEN `RoutineDay.fromJson(rawMap)`,
  THEN `slots` is `List<RoutineSlot>` and each slot deserializes correctly.

---

### REQ-RT-MODEL-003 — Routine model shape

The file `lib/features/workout/domain/routine.dart` MUST declare a `@freezed` class `Routine`.
Field contract:

| Field | Type | Required |
|---|---|---|
| `id` | `String` | yes |
| `name` | `String` | yes |
| `split` | `String` | yes |
| `level` | `ExperienceLevel` | yes |
| `days` | `List<RoutineDay>` | yes |
| `estimatedMinutesPerDay` | `int?` | no |
| `imageUrl` | `String?` | no |

`ExperienceLevel` MUST be imported from
`lib/features/profile/domain/experience_level.dart` — NOT redefined.
`split` wire values are free-form strings (e.g. `"PPL"`, `"Full Body"`, `"Upper/Lower"`).
`days` can be empty (valid for a newly created routine template with no days yet — not used in
seed, but MUST not crash).

#### Scenarios

- **SCENARIO-049**: GIVEN a `Routine` with all required fields and nullable fields null,
  WHEN roundtrip `toJson` → `fromJson`,
  THEN decoded equals original.

- **SCENARIO-050**: GIVEN a `Routine` with `imageUrl: 'https://img.example.com/r.jpg'` and
  `estimatedMinutesPerDay: 60`,
  WHEN roundtrip `toJson` → `fromJson`,
  THEN `imageUrl` and `estimatedMinutesPerDay` are preserved.

- **SCENARIO-051**: GIVEN a fully-nested Firestore wire map
  (Routine → 2 RoutineDays → 3 RoutineSlots each, all as `List<dynamic>`),
  WHEN `Routine.fromJson(rawMap)`,
  THEN `days.length == 2`, `days[0].slots.length == 3`, and each slot's `exerciseId` is correct.

- **SCENARIO-052**: GIVEN a `Routine` with `days: []`,
  WHEN roundtrip `toJson` → `fromJson`,
  THEN `days` is an empty list without error.

---

### REQ-RT-MODEL-004 — ExperienceLevel enum boundary in Routine

`Routine.level` serializes/deserializes using the existing `ExperienceLevel` `@JsonValue`
annotations (`'beginner'`, `'intermediate'`, `'advanced'`).

#### Scenarios

- **SCENARIO-053**: GIVEN a `Routine` with `level: ExperienceLevel.beginner`,
  WHEN `toJson()`,
  THEN `json['level'] == 'beginner'`.

- **SCENARIO-054**: GIVEN a `Routine` with `level: ExperienceLevel.intermediate`,
  WHEN roundtrip,
  THEN decoded `level == ExperienceLevel.intermediate`.

- **SCENARIO-055**: GIVEN a raw map with `level: 'advanced'`,
  WHEN `Routine.fromJson(rawMap)`,
  THEN `level == ExperienceLevel.advanced`.

- **SCENARIO-056**: GIVEN a raw map with an unknown `level` value (`'elite'`),
  WHEN `Routine.fromJson(rawMap)`,
  THEN an `ArgumentError` (or equivalent) is thrown (delegated to `ExperienceLevelX.fromJson`).

---

### REQ-RT-MODEL-005 — Generated files per model

Each of the 4 models (`Exercise`, `RoutineSlot`, `RoutineDay`, `Routine`) MUST have its own
dedicated pair of generated files (`*.freezed.dart`, `*.g.dart`). No two `@freezed` classes may
share a `part` file. `dart run build_runner build --delete-conflicting-outputs` MUST complete
without error after all 4 model files are created.

#### Scenarios

- **SCENARIO-057**: GIVEN all 4 model source files are present,
  WHEN `dart run build_runner build --delete-conflicting-outputs` is executed,
  THEN it exits with code 0 and generates exactly 8 part files
  (`exercise.freezed.dart`, `exercise.g.dart`, `routine_slot.freezed.dart`,
  `routine_slot.g.dart`, `routine_day.freezed.dart`, `routine_day.g.dart`,
  `routine.freezed.dart`, `routine.g.dart`).

---

### REQ-RT-REPO-001 — RoutineRepository public API

The class `RoutineRepository` in `lib/features/workout/data/routine_repository.dart` MUST expose:

```dart
RoutineRepository({required FirebaseFirestore firestore})
Future<List<Routine>> listAll()
Future<Routine?> getById(String id)
```

It MUST read from `routines/{routineId}`. No write methods. Concrete class, no abstract interface.
Constructor injection of `FirebaseFirestore`.

#### Scenarios

- **SCENARIO-058**: GIVEN an empty `routines` collection in `FakeFirebaseFirestore`,
  WHEN `routineRepo.listAll()` is called,
  THEN it returns an empty list.

- **SCENARIO-059**: GIVEN 3 routine documents seeded into `FakeFirebaseFirestore` (each with
  nested `days` and `slots` arrays),
  WHEN `routineRepo.listAll()` is called,
  THEN it returns a `List<Routine>` of length 3 and each routine deserializes completely
  (including nested days and slots).

- **SCENARIO-060**: GIVEN a routine with id `'ppl-beginner'` seeded into `FakeFirebaseFirestore`,
  WHEN `routineRepo.getById('ppl-beginner')` is called,
  THEN it returns a non-null `Routine` with `id == 'ppl-beginner'`.

- **SCENARIO-061**: GIVEN no document with id `'nonexistent-routine'`,
  WHEN `routineRepo.getById('nonexistent-routine')`,
  THEN it returns `null`.

---

### REQ-RT-REPO-002 — RoutineRepository nested array deserialization

`RoutineRepository` MUST correctly deserialize `List<dynamic>` payloads from Firestore into
typed `List<RoutineDay>` and `List<RoutineSlot>`.

#### Scenarios

- **SCENARIO-062**: GIVEN a raw Firestore document for a routine where `days` contains one day
  with 2 slots (all stored as `List<dynamic>` at wire level),
  WHEN `routineRepo.getById(id)` is called,
  THEN `routine.days.length == 1` and `routine.days[0].slots.length == 2` with correct
  field values.

- **SCENARIO-063**: GIVEN a routine document with `days: []` (empty array),
  WHEN `routineRepo.getById(id)`,
  THEN `routine.days` is an empty `List<RoutineDay>` without error.

---

### REQ-RT-RULES-001 — Firestore rules for routines collection

`firestore.rules` MUST contain a `match /routines/{routineId}` block with exactly:

```
allow read: if request.auth != null;
allow write: if false;
```

The rules MUST continue to compile after both exercise and routine blocks are added.
No client-side write path to `routines/` is permitted.

#### Scenarios

- **SCENARIO-064**: GIVEN the deployed `firestore.rules` and an authenticated client,
  WHEN a GET on `routines/{anyId}`,
  THEN read is allowed.

- **SCENARIO-065**: GIVEN the deployed `firestore.rules` and an authenticated client,
  WHEN a WRITE on `routines/{anyId}` from the client SDK,
  THEN the write is denied.

- **SCENARIO-066**: GIVEN the deployed `firestore.rules` and an unauthenticated client,
  WHEN a GET on `routines/{anyId}`,
  THEN the read is denied.

---

### REQ-RT-PROVIDERS-001 — Routine providers

The file `lib/features/workout/application/routine_providers.dart` MUST declare:

| Provider | Type | Description |
|---|---|---|
| `routineRepositoryProvider` | `Provider<RoutineRepository>` | Singleton; reads `firestoreProvider` |
| `routinesProvider` | `FutureProvider<List<Routine>>` | Eager-loads full catalogue; auth-gated (returns `[]` if not authenticated) |
| `routineByIdProvider` | `FutureProvider.family<Routine?, String>` | Derives from `routinesProvider`; O(1) lookup |

Same auth-gate pattern as `exercisesProvider` and `userProfileProvider`.
`routineByIdProvider` MUST NOT re-fetch from Firestore.
`firestoreProvider` MUST be imported from `user_providers.dart` (not redeclared).

#### Scenarios

- **SCENARIO-067**: GIVEN a `ProviderContainer` with `authStateChangesProvider` overridden to
  return `null`,
  WHEN `routinesProvider` is read,
  THEN it resolves to an empty list without error.

- **SCENARIO-068**: GIVEN a `ProviderContainer` with a mock authenticated user and
  `routineRepositoryProvider` overridden to return a repo backed by `FakeFirebaseFirestore`
  with 2 routines seeded,
  WHEN `routinesProvider` is awaited,
  THEN it resolves to a list of 2 routines.

- **SCENARIO-069**: GIVEN `routinesProvider` resolves with a list containing a routine with
  id `'full-body-beginner'`,
  WHEN `routineByIdProvider('full-body-beginner')` is awaited,
  THEN it returns that routine (non-null, correct id).

- **SCENARIO-070**: GIVEN `routinesProvider` resolves with a list that does not contain
  id `'missing'`,
  WHEN `routineByIdProvider('missing')` is awaited,
  THEN it returns `null`.

---

### REQ-RT-SEED-001 — seedRoutines function

The file `scripts/seed_workout_catalog.js` MUST also export (or define at module scope) an async
function `seedRoutines()` that writes routine documents to the `routines` Firestore collection.
Requirements:

- Minimum 6 routines covering: PPL (3-day), Full Body principiante (3-day), Upper/Lower (4-day),
  plus at least one additional variety.
- Each document ID is deterministic kebab-case (e.g. `'ppl-beginner'`, `'full-body-3day'`).
- Uses `set()` (upsert) — idempotent.
- Each routine MUST have at least 1 `RoutineDay`, each day at least 1 `RoutineSlot`.
- `seedRoutines()` MUST be called AFTER `seedExercises()` (order enforced in the top-level
  `seed()` function).

#### Scenarios

- **SCENARIO-071**: GIVEN the full script is run against a seeded `exercises` collection,
  WHEN `seedRoutines()` completes,
  THEN the `routines` collection contains at least 6 documents, each with a non-empty `days`
  array where every day has a non-empty `slots` array.

- **SCENARIO-072**: GIVEN the script is run twice,
  WHEN both runs complete,
  THEN the `routines` collection has the same document count as after a single run (idempotency).

---

### REQ-RT-SEED-002 — Orphan reference validation in seed script

The `seedRoutines()` function MUST validate that every `exerciseId` referenced in every
`RoutineSlot` exists in the `exercises` array defined in the same script. This validation happens
IN MEMORY before any Firestore writes. If an orphan reference is found, the script MUST exit with
a non-zero code and log a clear error message identifying the offending `exerciseId` and the
routine that references it. The Dart repositories do NOT perform this check (see propose.md §4.8).

#### Scenarios

- **SCENARIO-073**: GIVEN the seed data as-written (no orphan refs),
  WHEN the script's orphan validation logic runs,
  THEN no error is thrown and execution proceeds to Firestore writes.

- **SCENARIO-074**: GIVEN the seed data is modified to include a `RoutineSlot` with
  `exerciseId: 'does-not-exist'`,
  WHEN the script's orphan validation runs,
  THEN it throws/logs an error naming `'does-not-exist'` and the containing routine id,
  and no Firestore writes are performed.

---

## Cross-cutting constraints

The following apply to both PRs and MUST be satisfied before either PR is merged:

1. **No new Flutter/Dart dependencies** — `pubspec.yaml` MUST NOT add any new packages. All
   required packages (`freezed_annotation`, `json_annotation`, `cloud_firestore`,
   `flutter_riverpod`, `fake_cloud_firestore`, `mocktail`) are already in `pubspec.yaml`.

2. **Feature folder name** — ALL Dart files MUST be under `lib/features/workout/` (no "s").
   Mirrors the existing `workout_screen.dart`.

3. **File structure** — Mirrors `lib/features/profile/`:
   - `lib/features/workout/domain/` — models
   - `lib/features/workout/data/` — repositories
   - `lib/features/workout/application/` — providers

4. **`ExperienceLevel` import** — `routine.dart` MUST import from
   `lib/features/profile/domain/experience_level.dart`. The enum MUST NOT be redefined or
   duplicated. This cross-feature import is explicitly accepted (see propose.md §4.3 / Risk P4).

5. **`flutter analyze` 0 issues** — Across all new and modified files.

6. **`dart format .` clean** — No formatting diff.

7. **Test file mirroring** — Test files mirror `lib/`:
   - `test/features/workout/domain/exercise_test.dart`
   - `test/features/workout/domain/routine_slot_test.dart`
   - `test/features/workout/domain/routine_day_test.dart`
   - `test/features/workout/domain/routine_test.dart`
   - `test/features/workout/data/exercise_repository_test.dart`
   - `test/features/workout/data/routine_repository_test.dart`
   - `test/features/workout/application/exercise_providers_test.dart`
   - `test/features/workout/application/routine_providers_test.dart`

8. **Scenario numbering** — Test functions named `test('SCENARIO-NNN: ...', ...)` starting from
   SCENARIO-020. No gaps or duplicates within this change.

9. **Minimum test count** — 21+ new passing tests across both PRs (target per propose.md §2.7).
   This spec defines 55 scenarios (SCENARIO-020 through SCENARIO-074); apply phase implements
   all of them.

10. **No UI changes** — No modifications to `lib/app/router.dart`, `lib/features/home/`,
    `lib/features/auth/`, or `lib/features/profile/` (except the `ExperienceLevel` import path
    already exists).

11. **No subcollections** — Both `exercises` and `routines` are flat top-level collections.
    No subcollections in either.

12. **Provider manual style** — All providers use manual Riverpod 2 syntax (no `@riverpod` codegen
    annotations). Matches existing `user_providers.dart`.

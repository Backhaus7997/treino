# Design — routine-model-seed

**Change**: `routine-model-seed`
**Fase / Etapa**: Fase 2 · Etapa 2
**Artifact store**: openspec
**Depends on**: `propose.md`, `spec.md`, `explore.md`
**PR strategy**: chained — PR 1 (Exercise) → PR 2 (Routine)

This document is the technical contract that `sdd-apply` reads. Two developers implementing
from this design must produce nearly identical code. It is split top-level by PR slice because
`tasks.md` will produce one task batch per PR and apply will execute PR 1 alone first.

---

## Cross-cutting (applies to both PRs)

### Architectural pattern

Feature-sliced layered architecture mirroring `lib/features/profile/`:

```
lib/features/workout/
├── domain/          ← freezed models, plain Dart, no Firestore types in API
├── data/            ← concrete repositories, take FirebaseFirestore by ctor
└── application/     ← manual Riverpod 2 providers, auth-gated
```

Test mirror under `test/features/workout/` (same three subfolders).

### Reused infrastructure (no redefinitions)

| Symbol | Source | Why reused |
|---|---|---|
| `firestoreProvider` | `lib/features/profile/application/user_providers.dart` | Singleton; redeclaring violates Riverpod identity (two providers, two `FirebaseFirestore.instance` references = N+1) |
| `authStateChangesProvider` | `lib/features/auth/application/auth_providers.dart` | Single source of truth for auth gating |
| `ExperienceLevel` | `lib/features/profile/domain/experience_level.dart` | Same wire values; duplicate would diverge |

### Strict TDD ordering

Apply executes test-first per artifact:
1. write the test file (failing)
2. write the production file (test passes)
3. run `dart run build_runner build --delete-conflicting-outputs` after each new freezed model
4. `flutter analyze`, `dart format .`, `flutter test` at end of each PR slice

### Cross-feature import policy (propose §4.3, REQ-RT-MODEL-003)

`lib/features/workout/domain/routine.dart` imports
`package:treino/features/profile/domain/experience_level.dart`. This is the ONLY allowed
`workout → profile` import. It is for a pure value enum (no Firestore, no UI). If the
profile→workout edge ever needs to exist, `ExperienceLevel` moves to `lib/core/domain/` —
mechanical refactor, out of scope for this PR.

---

## PR 1 — Exercise collection

### 1. File map (PR 1)

| PR | Action | Path | Notes |
|---|---|---|---|
| 1 | Modified | `.gitignore` | **FIRST commit**, mitigates P0 secret leak |
| 1 | Created | `scripts/package.json` | `firebase-admin: ^12.x` only |
| 1 | Created | `scripts/.env.example` | `GOOGLE_APPLICATION_CREDENTIALS` |
| 1 | Created | `lib/features/workout/domain/exercise.dart` | freezed model |
| 1 | Generated | `lib/features/workout/domain/exercise.freezed.dart` | `build_runner` output |
| 1 | Generated | `lib/features/workout/domain/exercise.g.dart` | `build_runner` output |
| 1 | Created | `lib/features/workout/data/exercise_repository.dart` | `listAll`, `getById`, `getByIds` |
| 1 | Created | `lib/features/workout/application/exercise_providers.dart` | 3 providers |
| 1 | Modified | `firestore.rules` | add `match /exercises/{exerciseId}` block |
| 1 | Created | `scripts/seed_workout_catalog.js` | `seedExercises()` + CLI arg dispatch |
| 1 | Created | `test/features/workout/domain/exercise_test.dart` | SCENARIO-020..024 |
| 1 | Created | `test/features/workout/data/exercise_repository_test.dart` | SCENARIO-025..031 |
| 1 | Created | `test/features/workout/application/exercise_providers_test.dart` | SCENARIO-035..038 |

PR 1 is fully autonomous: the catalogue of exercises is queryable from the client after merge.

### 2. Model API surface — `Exercise` (PR 1)

```dart
// lib/features/workout/domain/exercise.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'exercise.freezed.dart';
part 'exercise.g.dart';

@freezed
class Exercise with _$Exercise {
  const factory Exercise({
    required String id,
    required String name,
    required String muscleGroup,
    required String category,            // 'compound' | 'isolation' (free-form String, validated in seed)
    List<String>? techniqueInstructions, // nullable — null means "not yet authored" (decision §9.1)
    String? videoUrl,
    int? defaultRestSeconds,
  }) = _Exercise;

  factory Exercise.fromJson(Map<String, Object?> json) =>
      _$ExerciseFromJson(json);
}
```

**Field rationale**:
- `id` — duplicated in the doc body in addition to being the doc ID. Mirrors `UserProfile.uid`.
  Lets `fromJson` work standalone without `DocumentSnapshot.id` injection.
- `name` — display label, e.g. "Bench Press".
- `muscleGroup` — free-form String. Future Fase 4 AI search will index this. Examples:
  `"chest"`, `"back"`, `"quads"`, `"hamstrings"`, `"shoulders"`, `"biceps"`, `"triceps"`,
  `"glutes"`, `"calves"`, `"core"`. No enum — flexibility for seed authoring.
- `category` — `"compound"` or `"isolation"` (English wire values, locked by spec REQ-EX-MODEL-001).
- `techniqueInstructions` — nullable `List<String>?` (decision §9.1). Null signals "not authored
  yet"; an empty list would be ambiguous.
- `videoUrl` — nullable, populated when promo video is uploaded (Fase 4).
- `defaultRestSeconds` — nullable; if absent, `RoutineSlot.restSeconds` is the source of truth.

**No `@TimestampConverter`** — `Exercise` has no DateTime fields, so no converter import.

### 3. Repository API — `ExerciseRepository` (PR 1)

```dart
// lib/features/workout/data/exercise_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../domain/exercise.dart';

class ExerciseRepository {
  ExerciseRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('exercises');

  Future<List<Exercise>> listAll() async {
    final snap = await _collection.get();
    return snap.docs.map(_fromDoc).whereType<Exercise>().toList();
  }

  Future<Exercise?> getById(String id) async {
    final snap = await _collection.doc(id).get();
    return _fromDoc(snap);
  }

  /// Eager batch lookup. Used by Etapa 4 detail screens and any future
  /// orphan-ref-validation path. Empty input short-circuits without I/O.
  Future<List<Exercise>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    // `whereIn` is capped at 30 values per query in Firestore; chunk if needed.
    // For the seeded catalogue (~30 docs total) this never trips, but the
    // chunking is defensive for Fase 4 routines that may reference many.
    const chunkSize = 30;
    final out = <Exercise>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        i + chunkSize > ids.length ? ids.length : i + chunkSize,
      );
      final snap = await _collection
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      out.addAll(snap.docs.map(_fromDoc).whereType<Exercise>());
    }
    return out;
  }

  Exercise? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Exercise.fromJson(data);
  }
}
```

**Decision: `getByIds` is in scope for PR 1.** Spec REQ-EX-REPO-001 requires it; propose §2.2
omits it but does not forbid it. We include it now because:
- The eager-load + in-memory join described in propose §3.2 reads from
  `exercisesProvider` (one bulk fetch); `getByIds` is the imperative escape hatch for code
  paths that bypass providers (the seed validation, future scripts, integration tests).
- Cost: ~15 LOC. Zero risk of misuse — read-only.
- Adding it later means a follow-up PR to a "frozen" data layer.

`whereIn` chunking is defensive: PR 1 routines never exceed 30 unique exerciseIds, but future
Fase 4 routines could.

`FieldPath` needs to be imported — adjust the import line accordingly:
```dart
import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FieldPath, FirebaseFirestore;
```

### 4. Providers — `exercise_providers.dart` (PR 1)

```dart
// lib/features/workout/application/exercise_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/exercise_repository.dart';
import '../domain/exercise.dart';

final exerciseRepositoryProvider = Provider<ExerciseRepository>(
  (ref) => ExerciseRepository(firestore: ref.watch(firestoreProvider)),
);

/// Eager-loads the full exercise catalogue (~25-30 docs). Auth-gated:
/// returns an empty list when unauthenticated, mirroring `userProfileProvider`'s
/// behaviour (but as `FutureProvider`, not `StreamProvider`).
final exercisesProvider = FutureProvider<List<Exercise>>((ref) async {
  final authState = ref.watch(authStateChangesProvider);
  final user = authState.valueOrNull;
  if (user == null) return const [];
  return ref.watch(exerciseRepositoryProvider).listAll();
});

/// O(1) in-memory lookup. Derives from [exercisesProvider] — never re-fetches
/// from Firestore. If the catalogue is not yet loaded, this provider awaits
/// the underlying [exercisesProvider] (Riverpod handles this naturally because
/// `ref.watch` on a `FutureProvider` returns `AsyncValue` and `future` is
/// awaitable).
final exerciseByIdProvider = FutureProvider.family<Exercise?, String>(
  (ref, id) async {
    final exercises = await ref.watch(exercisesProvider.future);
    for (final e in exercises) {
      if (e.id == id) return e;
    }
    return null;
  },
);
```

**Auth-gate pattern (different from `userProfileProvider`)**:
`userProfileProvider` is a `StreamProvider` that maps `authState.when(...)` to nested streams.
`FutureProvider` is one-shot — there is no inner stream to switch to. The right pattern is:
1. `ref.watch(authStateChangesProvider)` to subscribe (Riverpod will re-run this provider when
   auth changes).
2. Read `.valueOrNull` — when auth is still loading, this is `null`, which we treat the same
   as "not authenticated" → return `[]`. This is intentional: the home shell already gates
   navigation by auth state, so this provider being read while unauthenticated is an
   edge case (test only) and we want it to resolve cleanly, not hang.
3. When auth resolves to a real user, the provider re-runs and calls `listAll()`.

**`exerciseByIdProvider` decision**:
Spec REQ-EX-PROVIDERS-001 mandates "MUST NOT re-fetch from Firestore — it filters the
already-loaded list". Implemented by `await ref.watch(exercisesProvider.future)` — this
reuses the cached `Future` from `exercisesProvider`, so all family instances share one
Firestore round-trip. Calling `exerciseByIdProvider('a')` and `exerciseByIdProvider('b')`
results in exactly one `listAll()` call.

### 5. Firestore rules — `exercises` block (PR 1)

Add INSIDE the existing `service cloud.firestore { match /databases/{database}/documents { ... } }`,
AFTER the `match /users/{uid} { ... }` block (no whitespace surgery on existing block):

```
    match /exercises/{exerciseId} {
      // Catálogo público para usuarios autenticados.
      allow read: if request.auth != null;
      // Catálogo writeable solo via Admin SDK (seed script).
      allow write: if false;
    }
```

Exact resulting file shape:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /users/{uid} { ... existing ... }

    match /exercises/{exerciseId} {
      allow read: if request.auth != null;
      allow write: if false;
    }
  }
}
```

### 6. Seed script architecture (PR 1)

**File**: `scripts/seed_workout_catalog.js`. Single Node.js file. CLI-dispatched:

```js
// scripts/seed_workout_catalog.js
'use strict';

const admin = require('firebase-admin');
admin.initializeApp(); // uses GOOGLE_APPLICATION_CREDENTIALS env var
const db = admin.firestore();

// -- DATA ------------------------------------------------------------------
const exercises = [
  {
    id: 'bench-press',
    name: 'Bench Press',
    muscleGroup: 'chest',
    category: 'compound',
    techniqueInstructions: [
      'Acostate en banco plano con los pies firmes en el piso.',
      'Tomá la barra con agarre poco más ancho que los hombros.',
      'Bajá controlado al pecho, empujá hasta extensión completa.',
    ],
    defaultRestSeconds: 90,
  },
  // ...~24-29 more exercises across 6+ muscleGroup values
];

// PR 2 will add: const routines = [ ... ];

// -- SEEDERS ---------------------------------------------------------------
async function seedExercises() {
  console.log(`Seeding ${exercises.length} exercises...`);
  for (const ex of exercises) {
    await db.collection('exercises').doc(ex.id).set(ex);
  }
  console.log('Exercises seeded.');
}

// PR 2 will add: async function seedRoutines() { ... }

// -- ENTRYPOINT ------------------------------------------------------------
async function main() {
  const args = process.argv.slice(2);
  const doExercises = args.includes('--exercises') || args.includes('--all');
  // PR 2 will add: const doRoutines = args.includes('--routines') || args.includes('--all');

  if (!doExercises /* && !doRoutines */) {
    console.error('Usage: node seed_workout_catalog.js [--exercises|--routines|--all]');
    process.exit(1);
  }

  if (doExercises) await seedExercises();
  // PR 2: if (doRoutines) await seedRoutines();
}

main().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
```

**`scripts/package.json`**:
```json
{
  "name": "treino-seed",
  "version": "1.0.0",
  "private": true,
  "description": "Treino workout catalog seed scripts.",
  "scripts": {
    "seed:exercises": "node seed_workout_catalog.js --exercises",
    "seed:all": "node seed_workout_catalog.js --all"
  },
  "dependencies": {
    "firebase-admin": "^12.0.0"
  }
}
```
PR 2 adds `"seed:routines"`.

**`scripts/.env.example`**:
```
# Service account JSON for Firebase Admin SDK.
# Download from Firebase Console → Project settings → Service accounts.
# Save the file as scripts/treino-dev-service-account.json (it is gitignored).
GOOGLE_APPLICATION_CREDENTIALS=./treino-dev-service-account.json
```

**`.gitignore` additions** (append to the existing file, after the `.claude/` block):
```
# Treino seed scripts — secrets and Node deps
scripts/treino-dev-service-account*.json
scripts/node_modules/
scripts/.env
```

**Idempotency**: `db.collection('exercises').doc(id).set(data)` is upsert — re-running with
the same `id` produces the same document. No `add()` (would auto-generate IDs and duplicate).

**Manual run**:
```
cd scripts
npm install
export GOOGLE_APPLICATION_CREDENTIALS=./treino-dev-service-account.json
node seed_workout_catalog.js --exercises
```
Expected output:
```
Seeding 28 exercises...
Exercises seeded.
```

### 7. Test architecture (PR 1)

Test files mirror `lib/features/workout/`. Scenario IDs as defined in spec:

| Test file | Scenarios | Notes |
|---|---|---|
| `test/features/workout/domain/exercise_test.dart` | 020, 021, 022, 023, 024 | Roundtrip + raw-map deserialization + analyze sanity |
| `test/features/workout/data/exercise_repository_test.dart` | 025, 026, 027, 028, 029, 030, 031 | `FakeFirebaseFirestore` + seedDoc helper |
| `test/features/workout/application/exercise_providers_test.dart` | 035, 036, 037, 038 | `ProviderContainer` + auth override |

**Repo test seed helper shape** (mirrors `user_repository_test.dart`):
```dart
late FakeFirebaseFirestore firestore;
late ExerciseRepository repo;

setUp(() {
  firestore = FakeFirebaseFirestore();
  repo = ExerciseRepository(firestore: firestore);
});

Future<void> seedExercise({
  required String id,
  String name = 'Test Exercise',
  String muscleGroup = 'chest',
  String category = 'compound',
}) async {
  await firestore.collection('exercises').doc(id).set({
    'id': id,
    'name': name,
    'muscleGroup': muscleGroup,
    'category': category,
  });
}
```

**Provider test pattern** (mirrors `user_providers_test.dart`):
```dart
ProviderContainer makeContainer({
  required Stream<User?> authStream,
  required ExerciseRepository repo,
}) =>
    ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => authStream),
        exerciseRepositoryProvider.overrideWithValue(repo),
      ],
    );
```

Provider tests are kept for PR 1 because the auth-gate semantics for `FutureProvider` differ
from the existing `userProfileProvider` (StreamProvider) and we want explicit coverage of the
`valueOrNull == null → []` branch.

### 8. Rules-related scenarios (SCENARIO-032..034)

The three rules scenarios in spec REQ-EX-RULES-001 are NOT Flutter unit tests — they require
either Firebase Emulator + `firebase emulators:exec` or manual validation against the live
project. They are documented in `spec.md` for completeness and verified out-of-test-suite during
the apply phase manual checklist. Apply phase records: `manual rules validation: PASS` in
apply-progress.

---

## PR 2 — Routine collection

### 1. File map (PR 2)

| PR | Action | Path | Notes |
|---|---|---|---|
| 2 | Created | `lib/features/workout/domain/routine_slot.dart` | freezed |
| 2 | Generated | `lib/features/workout/domain/routine_slot.freezed.dart` | |
| 2 | Generated | `lib/features/workout/domain/routine_slot.g.dart` | |
| 2 | Created | `lib/features/workout/domain/routine_day.dart` | freezed |
| 2 | Generated | `lib/features/workout/domain/routine_day.freezed.dart` | |
| 2 | Generated | `lib/features/workout/domain/routine_day.g.dart` | |
| 2 | Created | `lib/features/workout/domain/routine.dart` | freezed; imports ExperienceLevel |
| 2 | Generated | `lib/features/workout/domain/routine.freezed.dart` | |
| 2 | Generated | `lib/features/workout/domain/routine.g.dart` | |
| 2 | Created | `lib/features/workout/data/routine_repository.dart` | `listAll`, `getById` |
| 2 | Created | `lib/features/workout/application/routine_providers.dart` | 3 providers |
| 2 | Modified | `firestore.rules` | add `match /routines/{routineId}` block |
| 2 | Modified | `scripts/seed_workout_catalog.js` | adds `seedRoutines()` + orphan validation + `--routines` flag |
| 2 | Modified | `scripts/package.json` | adds `seed:routines` script |
| 2 | Created | `test/features/workout/domain/routine_slot_test.dart` | SCENARIO-043..045 |
| 2 | Created | `test/features/workout/domain/routine_day_test.dart` | SCENARIO-046..048 |
| 2 | Created | `test/features/workout/domain/routine_test.dart` | SCENARIO-049..057 |
| 2 | Created | `test/features/workout/data/routine_repository_test.dart` | SCENARIO-058..063 |
| 2 | Created | `test/features/workout/application/routine_providers_test.dart` | SCENARIO-067..070 |

### 2. Model API surfaces (PR 2)

#### `RoutineSlot`
```dart
// lib/features/workout/domain/routine_slot.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'routine_slot.freezed.dart';
part 'routine_slot.g.dart';

@freezed
class RoutineSlot with _$RoutineSlot {
  const factory RoutineSlot({
    required String exerciseId,    // FK → exercises/{id} (canonical reference)
    required String exerciseName,  // denormalized for compact card display (decision §9.2)
    required String muscleGroup,   // denormalized for compact card display
    required int targetSets,
    required int targetRepsMin,
    required int targetRepsMax,
    required int restSeconds,
    double? targetWeightKg,
    String? notes,
  }) = _RoutineSlot;

  factory RoutineSlot.fromJson(Map<String, Object?> json) =>
      _$RoutineSlotFromJson(json);
}
```

**Field rationale**:
- `exerciseId` — single source of truth for which Exercise this slot points to.
- `exerciseName`, `muscleGroup` — denormalization (decision §9.2). Seed script keeps them in
  sync; client never writes routines.
- `targetReps{Min,Max}` — int range (e.g. 8–12). Display: "8–12".
- `restSeconds` — slot-level override of `Exercise.defaultRestSeconds`. Always required.
- `targetWeightKg` — nullable; `null` means "user picks" or "no target set" (most beginner
  routines). `double` because plate math.
- `notes` — nullable free-form coaching notes (e.g. "tempo 3-1-1").

NOT included: `techniqueInstructions`, `videoUrl`. Those live exclusively on `Exercise` and are
fetched via `exerciseByIdProvider` at the detail screen.

#### `RoutineDay`
```dart
// lib/features/workout/domain/routine_day.dart
import 'package:freezed_annotation/freezed_annotation.dart';

import 'routine_slot.dart';

part 'routine_day.freezed.dart';
part 'routine_day.g.dart';

@freezed
class RoutineDay with _$RoutineDay {
  const factory RoutineDay({
    required int dayNumber,
    required String name,
    required List<RoutineSlot> slots,
    int? estimatedMinutes,
  }) = _RoutineDay;

  factory RoutineDay.fromJson(Map<String, Object?> json) =>
      _$RoutineDayFromJson(json);
}
```

**Field rationale**:
- `dayNumber` — int (1, 2, 3…). Stable ordering inside a routine. Display "Día 1".
- `name` — e.g. "Push", "Upper A". Free-form.
- `slots` — embedded array; empty list is valid (spec SCENARIO-046).
- `estimatedMinutes` — nullable; UI may fall back to `Routine.estimatedMinutesPerDay`.

#### `Routine`
```dart
// lib/features/workout/domain/routine.dart
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/domain/experience_level.dart';
import 'routine_day.dart';

part 'routine.freezed.dart';
part 'routine.g.dart';

@freezed
class Routine with _$Routine {
  const factory Routine({
    required String id,
    required String name,
    required String split,            // 'PPL' | 'Full Body' | 'Upper/Lower' | ... (free-form)
    required ExperienceLevel level,
    required List<RoutineDay> days,
    int? estimatedMinutesPerDay,
    String? imageUrl,                 // nullable (decision §9.3) — null for seed PR 2
  }) = _Routine;

  factory Routine.fromJson(Map<String, Object?> json) =>
      _$RoutineFromJson(json);
}
```

**Field rationale**:
- `id` — duplicated in body for `fromJson` standalone use.
- `split` — free-form `String` because future splits may differ (e.g. "Bro Split"). No enum.
- `level` — reused enum, see cross-feature import policy above. JsonValue annotations on the
  enum handle serialization automatically.
- `days` — embedded; empty list valid (spec SCENARIO-052).
- `estimatedMinutesPerDay` — fallback when `RoutineDay.estimatedMinutes` is null.
- `imageUrl` — null for seed (decision §9.3); future Storage URL.

### 3. Repository API — `RoutineRepository` (PR 2)

```dart
// lib/features/workout/data/routine_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../domain/routine.dart';

class RoutineRepository {
  RoutineRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _collection =>
      _firestore.collection('routines');

  Future<List<Routine>> listAll() async {
    final snap = await _collection.get();
    return snap.docs.map(_fromDoc).whereType<Routine>().toList();
  }

  Future<Routine?> getById(String id) async {
    final snap = await _collection.doc(id).get();
    return _fromDoc(snap);
  }

  Routine? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return Routine.fromJson(data);
  }
}
```

Same shape as `ExerciseRepository` minus `getByIds` (not in spec for routines; only ~6 docs,
caller can `listAll().where`).

### 4. Providers — `routine_providers.dart` (PR 2)

```dart
// lib/features/workout/application/routine_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/routine_repository.dart';
import '../domain/routine.dart';

final routineRepositoryProvider = Provider<RoutineRepository>(
  (ref) => RoutineRepository(firestore: ref.watch(firestoreProvider)),
);

final routinesProvider = FutureProvider<List<Routine>>((ref) async {
  final authState = ref.watch(authStateChangesProvider);
  final user = authState.valueOrNull;
  if (user == null) return const [];
  return ref.watch(routineRepositoryProvider).listAll();
});

final routineByIdProvider = FutureProvider.family<Routine?, String>(
  (ref, id) async {
    final routines = await ref.watch(routinesProvider.future);
    for (final r in routines) {
      if (r.id == id) return r;
    }
    return null;
  },
);
```

Identical pattern to `exercise_providers.dart`. Same auth-gate, same in-memory lookup.

### 5. Firestore rules — `routines` block (PR 2)

Append AFTER the `exercises` block (which PR 1 already added):

```
    match /routines/{routineId} {
      allow read: if request.auth != null;
      allow write: if false;
    }
```

Final file shape after both PRs:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /users/{uid} { ... }

    match /exercises/{exerciseId} {
      allow read: if request.auth != null;
      allow write: if false;
    }

    match /routines/{routineId} {
      allow read: if request.auth != null;
      allow write: if false;
    }
  }
}
```

### 6. Seed script extension (PR 2)

Add to `scripts/seed_workout_catalog.js`:

```js
// -- DATA (appended) -------------------------------------------------------
const routines = [
  {
    id: 'ppl-beginner',
    name: 'Push Pull Legs — Principiante',
    split: 'PPL',
    level: 'beginner',
    estimatedMinutesPerDay: 60,
    imageUrl: null,
    days: [
      {
        dayNumber: 1,
        name: 'Push',
        estimatedMinutes: 60,
        slots: [
          {
            exerciseId: 'bench-press',
            exerciseName: 'Bench Press',
            muscleGroup: 'chest',
            targetSets: 4,
            targetRepsMin: 8,
            targetRepsMax: 12,
            restSeconds: 90,
            targetWeightKg: null,
            notes: null,
          },
          // ...more slots
        ],
      },
      // ...days 2 and 3
    ],
  },
  // ...5+ more routines (≥6 total)
];

// -- VALIDATION ------------------------------------------------------------
function validateRoutineRefs() {
  const exerciseIds = new Set(exercises.map((e) => e.id));
  const errors = [];
  for (const routine of routines) {
    for (const day of routine.days) {
      for (const slot of day.slots) {
        if (!exerciseIds.has(slot.exerciseId)) {
          errors.push(
            `Routine '${routine.id}' day ${day.dayNumber} references ` +
            `unknown exerciseId '${slot.exerciseId}'.`
          );
        }
      }
    }
  }
  if (errors.length > 0) {
    console.error('Orphan reference validation FAILED:');
    for (const e of errors) console.error('  - ' + e);
    throw new Error(`${errors.length} orphan reference(s) found. Aborting before any Firestore writes.`);
  }
}

// -- SEEDER ----------------------------------------------------------------
async function seedRoutines() {
  validateRoutineRefs();
  console.log(`Seeding ${routines.length} routines...`);
  for (const r of routines) {
    await db.collection('routines').doc(r.id).set(r);
  }
  console.log('Routines seeded.');
}
```

And `main()` updated:
```js
async function main() {
  const args = process.argv.slice(2);
  const doExercises = args.includes('--exercises') || args.includes('--all');
  const doRoutines = args.includes('--routines') || args.includes('--all');

  if (!doExercises && !doRoutines) {
    console.error('Usage: node seed_workout_catalog.js [--exercises|--routines|--all]');
    process.exit(1);
  }

  if (doExercises) await seedExercises();
  if (doRoutines) await seedRoutines();
}
```

`scripts/package.json` adds:
```json
"seed:routines": "node seed_workout_catalog.js --routines",
```

**Orphan validation flow** (decision §9.4):
1. `validateRoutineRefs()` runs FIRST inside `seedRoutines()`.
2. Builds `Set<exerciseId>` from `const exercises`.
3. Iterates every slot across every day of every routine.
4. Accumulates errors (does not fail-fast on first — surfaces ALL orphans in one report).
5. If errors > 0: log each error, throw — `main().catch` exits non-zero. ZERO Firestore writes.
6. If errors === 0: proceed to `set()` upserts.

This guarantees the script is all-or-nothing on the routines side: either the entire `routines/`
collection is consistent with `exercises/`, or nothing is written. The `--routines` flag alone
without `--exercises` is safe because validation uses the in-script `const exercises` array,
not Firestore reads (offline-safe).

### 7. Test architecture (PR 2)

| Test file | Scenarios | Notes |
|---|---|---|
| `test/features/workout/domain/routine_slot_test.dart` | 043, 044, 045 | Roundtrip + nullable absent keys |
| `test/features/workout/domain/routine_day_test.dart` | 046, 047, 048 | Empty slots + populated slots + raw-map nested |
| `test/features/workout/domain/routine_test.dart` | 049, 050, 051, 052, 053, 054, 055, 056, 057 | Roundtrip, enum boundary, build_runner sanity, deeply nested raw map |
| `test/features/workout/data/routine_repository_test.dart` | 058, 059, 060, 061, 062, 063 | `FakeFirebaseFirestore` + nested-map seed helper |
| `test/features/workout/application/routine_providers_test.dart` | 067, 068, 069, 070 | `ProviderContainer` + auth override |

**SCENARIO-057 (build_runner sanity)** is verified by the apply phase command output, not a
Dart `test(...)` call. The test "exists" as a checklist item: after writing all 4 models,
running `dart run build_runner build --delete-conflicting-outputs` MUST produce exactly the
8 generated files listed in spec. Apply phase records this in apply-progress.

**Repo test seed helper for nested data**:
```dart
Future<void> seedRoutine({
  required String id,
  required List<Map<String, dynamic>> days, // raw nested maps mimicking Firestore wire
}) async {
  await firestore.collection('routines').doc(id).set({
    'id': id,
    'name': 'Test Routine',
    'split': 'PPL',
    'level': 'beginner',
    'days': days,
    'estimatedMinutesPerDay': null,
    'imageUrl': null,
  });
}
```

**SCENARIO-064..066** (rules) — same out-of-suite manual validation as PR 1.

### 8. Out-of-suite manual validation (PR 2)

After PR 2 code merges and CI is green:
1. Run `node seed_workout_catalog.js --all` against the dev Firebase project.
2. Expected: `Seeding 28 exercises...` `Exercises seeded.` `Seeding 6 routines...` `Routines seeded.`
3. Re-run the same command. Expected: same counts, no duplicates (idempotency check).
4. Modify a routine slot's `exerciseId` to `'does-not-exist'`, run again. Expected: non-zero
   exit, error message naming the orphan, zero changes in Firestore (SCENARIO-074).
5. Record outcomes in apply-progress.

---

## ADR-style decisions log

The 4 decisions called out in the design phase prompt §9, plus reaffirmations of locked
decisions from propose.md:

### ADR-1 — `techniqueInstructions` empty state is `null`, not `[]`

- **Decision**: `Exercise.techniqueInstructions` is `null` when not authored. Empty list is
  not used as a sentinel.
- **Rationale**: `null` reads as "unknown / not yet authored"; `[]` reads as "explicitly no
  instructions" (deliberate authorial intent). The seed always populates the list (≥1 cue per
  exercise per REQ-EX-SEED-001), so the only `null` cases are legacy/orphan docs. Easier to
  reason about: `if (instructions == null) showEmptyState` vs `if (instructions == null || instructions.isEmpty)`.
- **Rejected alternative**: default to `[]` in factory. Loses the "unknown vs deliberate empty"
  distinction; forces all consumers to dual-check.

### ADR-2 — `RoutineSlot` denormalizes `exerciseName` and `muscleGroup`

- **Decision**: `RoutineSlot` stores `exerciseName` and `muscleGroup` alongside `exerciseId`.
  `Exercise` collection remains the source of truth; the seed is the single sync point.
- **Rationale**: Etapa 3 (routine list cards) and Etapa 4 (day detail) display name + muscle
  group on every slot row. Without denormalization, every list render does N joins to
  `exercisesProvider`. With ~6 routines × ~3 days × ~6 slots = ~108 cells per cold render,
  that's 108 in-memory lookups for data that never changes for the duration of the catalogue.
  Denormalization keeps the simple cells purely declarative.
- **Cost**: ~2 fields × ~36 slots × 6 routines = ~432 extra bytes on the wire. Negligible.
- **Risk**: Future re-authoring of `Exercise.name` requires re-running the seed (overwrites
  `routines/` upserts). Acceptable: catalogue is curated, not user-generated.
- **Out-of-scope**: A future refactor (Fase 4 or later) MAY remove these fields once an eager-loaded
  client-side join provider is established. Spec REQ-RT-MODEL-001 marks them explicitly as
  denormalized.
- **Rejected alternative**: only store `exerciseId`. Forces all routine UI to await
  `exercisesProvider` AND `routinesProvider` jointly. Adds skeleton-state complexity to compact
  cards.

### ADR-3 — `Routine.imageUrl` is `null` for the seed

- **Decision**: PR 2 seeds all routines with `imageUrl: null`. No Storage uploads, no external
  URLs.
- **Rationale**: No designed routine illustrations exist yet. Etapa 3 will fall back to a
  placeholder (mirrors the "Esta semana" pattern from `home-shell`). When real images land
  (Fase 4 or later), they'll be uploaded to Firebase Storage and the seed will be re-run with
  the new URLs.
- **Storage decision**: when populated, `imageUrl` is a Firebase Storage URL (consistent with
  future avatar/profile assets). NOT a local asset path — those don't survive over-the-air
  catalogue updates.
- **Rejected alternative**: embed placeholder URLs in the seed. Pollutes git diff when the
  real URLs land.

### ADR-4 — Seed validation runs in memory before any Firestore writes

- **Decision**: `seedRoutines()` runs `validateRoutineRefs()` first; on any orphan it throws
  and the script exits non-zero with ZERO Firestore writes performed for routines.
- **Error message format**:
  ```
  Orphan reference validation FAILED:
    - Routine 'ppl-beginner' day 1 references unknown exerciseId 'bnch-press'.
    - Routine 'full-body-3day' day 2 references unknown exerciseId 'leg-prss'.
  Error: 2 orphan reference(s) found. Aborting before any Firestore writes.
  ```
- **Rationale**: partial writes leave the routines collection inconsistent with `exercises/`,
  which is exactly what we're trying to prevent (P1 risk). The seed must be transactional in
  spirit even if Firestore admin writes aren't truly transactional across N docs.
- **Implementation detail**: validation surfaces ALL orphans in one report (does not stop at
  first). The dev can fix everything in one pass rather than running-failing-fixing N times.
- **Rejected alternative**: validate on Firestore (check `exercises/` collection exists for
  each id). Requires online state; slower; doesn't catch typos in the seed data file before
  uploading; breaks `--routines` running alone after `--exercises` already ran.

---

## Implementation order (apply phase contract)

**PR 1 batch** (strict TDD — test → code per artifact):
1. `.gitignore` update + commit. **Mitigates P0 BEFORE any service account JSON exists locally.**
2. `scripts/package.json` + `scripts/.env.example`. Node env bootstrapped.
3. `test/features/workout/domain/exercise_test.dart` (SCENARIO-020..024) — failing.
4. `lib/features/workout/domain/exercise.dart` + `dart run build_runner build --delete-conflicting-outputs` → tests pass.
5. `test/features/workout/data/exercise_repository_test.dart` (SCENARIO-025..031) — failing.
6. `lib/features/workout/data/exercise_repository.dart` → tests pass.
7. `test/features/workout/application/exercise_providers_test.dart` (SCENARIO-035..038) — failing.
8. `lib/features/workout/application/exercise_providers.dart` → tests pass.
9. `firestore.rules` — add `exercises` block. Deploy/dry-run validate.
10. `scripts/seed_workout_catalog.js` — `seedExercises()` + data (≥25 across ≥6 muscleGroups).
11. **Manual**: run `node seed_workout_catalog.js --exercises` against dev project. Verify in
    Firebase Console: ~28 docs in `exercises/`. Re-run, confirm count unchanged.
12. Quality gates: `flutter analyze` (0 issues), `dart format .` (no diff), `flutter test`
    (full suite green).
13. PR 1 review + merge.

**PR 2 batch** (after PR 1 is merged to main):
14. `test/features/workout/domain/routine_slot_test.dart` (SCENARIO-043..045) — failing.
15. `lib/features/workout/domain/routine_slot.dart` + build_runner.
16. `test/features/workout/domain/routine_day_test.dart` (SCENARIO-046..048) — failing.
17. `lib/features/workout/domain/routine_day.dart` + build_runner.
18. `test/features/workout/domain/routine_test.dart` (SCENARIO-049..057) — failing.
19. `lib/features/workout/domain/routine.dart` + build_runner.
    Verify 8 generated files exist (SCENARIO-057).
20. `test/features/workout/data/routine_repository_test.dart` (SCENARIO-058..063) — failing.
21. `lib/features/workout/data/routine_repository.dart` → tests pass.
22. `test/features/workout/application/routine_providers_test.dart` (SCENARIO-067..070) — failing.
23. `lib/features/workout/application/routine_providers.dart` → tests pass.
24. `firestore.rules` — add `routines` block.
25. Augment `scripts/seed_workout_catalog.js` with `routines` data, `seedRoutines()`,
    `validateRoutineRefs()`, and `--routines` / `--all` flag wiring. Update
    `scripts/package.json` scripts.
26. **Manual**: `node seed_workout_catalog.js --all`. Verify ≥6 docs in `routines/`. Re-run,
    confirm idempotency. Temporarily plant an orphan ref, re-run, confirm non-zero exit and
    no partial writes; revert the orphan.
27. Quality gates: `flutter analyze`, `dart format .`, `flutter test`.
28. PR 2 review + merge.

**Total expected**: ~21+ Dart tests across both PRs (spec defines 55 scenarios; rules + build_runner +
seed scenarios are out-of-suite manual checks; the in-suite count lands around 35-40).

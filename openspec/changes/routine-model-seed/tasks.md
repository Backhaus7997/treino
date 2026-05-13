# Tasks — routine-model-seed

**Change**: `routine-model-seed`
**Fase / Etapa**: Fase 2 · Etapa 2
**Artifact store**: openspec
**Depends on**: `spec.md`, `design.md`, `propose.md`
**Delivery**: Chained PRs — PR 1 (Exercise) merges first, PR 2 (Routine) follows on a new branch.

---

## PR 1 — Exercise collection

Branch: `feat/routine-model-seed`

---

- [x] **TASK-001 — Update `.gitignore` to exclude service account secrets and Node deps**
  - **REQ refs**: REQ-EX-BOOT-001
  - **Files**: `.gitignore`
  - **Done when**: `git status` does not show `scripts/treino-dev-service-account*.json`, `scripts/node_modules/`, or `scripts/.env` as untracked or staged after those paths exist locally. SCENARIO-042 passes (manual verification).
  - **Notes**: MUST be the first commit in the branch. Mitigates P0 (service account JSON leak). Append the three lines AFTER the existing `.claude/` block. Do not reformat the rest of the file.

---

- [x] **TASK-002 — Create `scripts/package.json` and `scripts/.env.example`**
  - **REQ refs**: REQ-EX-BOOT-001
  - **Files**: `scripts/package.json`, `scripts/.env.example`
  - **Done when**: `scripts/package.json` declares `"firebase-admin": "^12.0.0"` in `dependencies` and the `seed:exercises` and `seed:all` npm scripts. `scripts/.env.example` contains the `GOOGLE_APPLICATION_CREDENTIALS` key with an explanation comment. SCENARIO-041 passes (manual read).
  - **Notes**: `scripts/.env` (the real file) must already be gitignored by TASK-001 before this task runs. `node_modules/` must not be committed (also gitignored by TASK-001).

---

- [x] **TASK-003a — Write `exercise_test.dart` (RED — model does not exist yet)**
  - **REQ refs**: REQ-EX-MODEL-001, REQ-EX-MODEL-002
  - **Files**: `test/features/workout/domain/exercise_test.dart`
  - **Done when**: File exists with five named tests covering SCENARIO-020, SCENARIO-021, SCENARIO-022, SCENARIO-023, SCENARIO-024. Running `flutter test test/features/workout/domain/exercise_test.dart` fails with compile errors (model missing). Test names follow the `test('SCENARIO-NNN: ...', ...)` convention.
  - **Notes**: SCENARIO-024 is the `flutter analyze` sanity check — implement it as a test that calls `Exercise.fromJson({...})` without error (the actual analyze run is a quality-gate step, not a `test()` call). Depends on TASK-001 and TASK-002 only for branch readiness; no production code dependency yet.

---

- [x] **TASK-003b — Implement `exercise.dart` and run `build_runner` (GREEN)**
  - **REQ refs**: REQ-EX-MODEL-001, REQ-EX-MODEL-002, REQ-RT-MODEL-005
  - **Files**: `lib/features/workout/domain/exercise.dart`, `lib/features/workout/domain/exercise.freezed.dart` (generated), `lib/features/workout/domain/exercise.g.dart` (generated)
  - **Done when**: `dart run build_runner build --delete-conflicting-outputs` exits 0. `flutter test test/features/workout/domain/exercise_test.dart` passes all 5 tests (SCENARIO-020..024 green). `flutter analyze lib/features/workout/domain/exercise.dart` reports 0 issues.
  - **Notes**: Depends on TASK-003a. No `@TimestampConverter` — `Exercise` has no DateTime fields. Do NOT import anything from `lib/features/profile/`. Field signature must match design.md §2 exactly.

---

- [x] **TASK-004a — Write `exercise_repository_test.dart` (RED)**
  - **REQ refs**: REQ-EX-REPO-001, REQ-EX-REPO-002
  - **Files**: `test/features/workout/data/exercise_repository_test.dart`
  - **Done when**: File exists with seven named tests covering SCENARIO-025, SCENARIO-026, SCENARIO-027, SCENARIO-028, SCENARIO-029, SCENARIO-030, SCENARIO-031. Uses `FakeFirebaseFirestore` and the `seedExercise` helper defined in design.md §7. Running `flutter test test/features/workout/data/exercise_repository_test.dart` fails with compile or missing-symbol errors (repository not yet created).
  - **Notes**: Depends on TASK-003b (model must compile). `seedExercise` helper is local to the test file — copy the signature from design.md §7. SCENARIO-030 verifies the empty-list short-circuit (no Firestore query issued).

---

- [x] **TASK-004b — Implement `exercise_repository.dart` (GREEN)**
  - **REQ refs**: REQ-EX-REPO-001, REQ-EX-REPO-002
  - **Files**: `lib/features/workout/data/exercise_repository.dart`
  - **Done when**: `flutter test test/features/workout/data/exercise_repository_test.dart` passes all 7 tests (SCENARIO-025..031 green). `flutter analyze lib/features/workout/data/exercise_repository.dart` reports 0 issues.
  - **Notes**: Depends on TASK-004a. Use the exact class and method signatures from design.md §3. Import `FieldPath` from `cloud_firestore` for `getByIds`. The `whereIn` chunking logic (chunk size 30) is required by spec REQ-EX-REPO-001. No write methods, no abstract interface.

---

- [x] **TASK-005a — Write `exercise_providers_test.dart` (RED)**
  - **REQ refs**: REQ-EX-PROVIDERS-001
  - **Files**: `test/features/workout/application/exercise_providers_test.dart`
  - **Done when**: File exists with four named tests covering SCENARIO-035, SCENARIO-036, SCENARIO-037, SCENARIO-038. Uses `ProviderContainer` with overrides following the `makeContainer` helper pattern from design.md §7. Running `flutter test test/features/workout/application/exercise_providers_test.dart` fails with compile/symbol errors (providers not yet created).
  - **Notes**: Depends on TASK-004b. Auth override pattern must mirror `user_providers_test.dart`. SCENARIO-035 tests the unauthenticated → `[]` path; SCENARIO-036 tests authenticated + real repo → list; SCENARIO-037/038 test `exerciseByIdProvider` hit/miss.

---

- [x] **TASK-005b — Implement `exercise_providers.dart` (GREEN)**
  - **REQ refs**: REQ-EX-PROVIDERS-001
  - **Files**: `lib/features/workout/application/exercise_providers.dart`
  - **Done when**: `flutter test test/features/workout/application/exercise_providers_test.dart` passes all 4 tests (SCENARIO-035..038 green). `flutter analyze lib/features/workout/application/exercise_providers.dart` reports 0 issues.
  - **Notes**: Depends on TASK-005a. Import `firestoreProvider` from `user_providers.dart` (do NOT redeclare). Import `authStateChangesProvider` from `auth_providers.dart`. Auth-gate uses `.valueOrNull` on the `AsyncValue` from `authStateChangesProvider` (FutureProvider pattern — not StreamProvider). `exerciseByIdProvider` must use `ref.watch(exercisesProvider.future)` — no direct Firestore calls.

---

- [x] **TASK-006 — Add `exercises` block to `firestore.rules`**
  - **REQ refs**: REQ-EX-RULES-001
  - **Files**: `firestore.rules`
  - **Done when**: `firestore.rules` contains `match /exercises/{exerciseId}` with `allow read: if request.auth != null;` and `allow write: if false;` inside the existing `service cloud.firestore { match /databases/{database}/documents { ... } }` wrapper. The existing `match /users/{uid}` block is unchanged. Manual emulator or dry-run validation confirms SCENARIO-032, SCENARIO-033, SCENARIO-034 pass.
  - **Notes**: Depends on TASK-005b only for branch ordering. Insert the new block AFTER the `users` block. Do not modify any existing rule. Record `manual rules validation: PASS` in apply-progress after emulator run.

---

- [x] **TASK-007 — Create `scripts/seed_workout_catalog.js` with `seedExercises()` and exercise data**
  - **REQ refs**: REQ-EX-SEED-001
  - **Files**: `scripts/seed_workout_catalog.js`
  - **Done when**: File exists with `const exercises = [...]` array of ≥25 objects covering ≥6 distinct `muscleGroup` values. Each object has `id` (kebab-case slug), `name`, `muscleGroup`, `category` (`"compound"` or `"isolation"`), and `techniqueInstructions` (≥1 cue). `seedExercises()` function uses `db.collection('exercises').doc(ex.id).set(ex)` (upsert). `main()` function handles `--exercises` and `--all` CLI flags. SCENARIO-039 and SCENARIO-040 are manually verifiable against the dev project.
  - **Notes**: Depends on TASK-002 (package.json must exist). Use the exact script architecture from design.md §6. Include PR-2 placeholder comments (`// PR 2 will add: ...`) so the diff in PR 2 is clean. `node seed_workout_catalog.js --exercises` with no flags must print a usage error and exit(1).

---

- [x] **TASK-008 — Manual seed run against dev Firebase project (exercises)**
  - **REQ refs**: REQ-EX-SEED-001
  - **Files**: none (manual verification step)
  - **Done when**: `node seed_workout_catalog.js --exercises` completes successfully against the dev Firebase project. Firebase Console shows ≥25 documents in `exercises/`. Re-running the command produces the same document count (idempotency). SCENARIO-039 and SCENARIO-040 are confirmed. Result recorded in apply-progress as `seed exercises: PASS, count: N`.
  - **Notes**: Requires service account JSON at `scripts/treino-dev-service-account.json` (gitignored by TASK-001). Must run AFTER TASK-007. If the Firebase project is not available, mark as `SKIP (offline)` in apply-progress and unblock TASK-009.

---

- [x] **TASK-009 — PR 1 quality gates**
  - **REQ refs**: REQ-EX-MODEL-002, cross-cutting constraints §5 and §6
  - **Files**: none (verification step; may patch formatting drift)
  - **Done when**: `flutter analyze` exits 0 with no issues across all new and modified Dart files. `dart format . --output=none --set-exit-if-changed` exits 0 (no formatting diff). `flutter test` runs the full suite and all new tests are green (SCENARIO-020..031 + SCENARIO-035..038, minimum 16 passing tests for PR 1). Results recorded in apply-progress.
  - **Notes**: This is the merge gate for PR 1. Must run after all TASK-003b through TASK-007 are complete. Fix any analyzer or formatting issue found before marking done.

---

## PR 2 — Routine collection

Branch: `feat/routine-model-seed-routines` (created after PR 1 merges to main)

> All TASK-010 and later tasks execute AFTER PR 1 is merged. The new branch is created from the updated `main`.

---

- [x] **TASK-010a — Write `routine_slot_test.dart` (RED)**
  - **REQ refs**: REQ-RT-MODEL-001
  - **Files**: `test/features/workout/domain/routine_slot_test.dart`
  - **Done when**: File exists with three named tests covering SCENARIO-043, SCENARIO-044, SCENARIO-045. Running `flutter test test/features/workout/domain/routine_slot_test.dart` fails with compile errors (model not yet created).
  - **Notes**: TASK-010a is the first task in PR 2. File name is `routine_slot_test.dart` (not `routine_exercise_test.dart` — the rename from `RoutineExercise` to `RoutineSlot` is locked per propose.md §4.7). SCENARIO-045 tests missing nullable keys (`targetWeightKg`, `notes`) — raw map with those keys absent.

---

- [x] **TASK-010b — Implement `routine_slot.dart` and run `build_runner` (GREEN)**
  - **REQ refs**: REQ-RT-MODEL-001, REQ-RT-MODEL-005
  - **Files**: `lib/features/workout/domain/routine_slot.dart`, `lib/features/workout/domain/routine_slot.freezed.dart` (generated), `lib/features/workout/domain/routine_slot.g.dart` (generated)
  - **Done when**: `dart run build_runner build --delete-conflicting-outputs` exits 0. `flutter test test/features/workout/domain/routine_slot_test.dart` passes all 3 tests (SCENARIO-043..045 green).
  - **Notes**: Depends on TASK-010a. Exact field contract from design.md §2 (`RoutineSlot`). `targetWeightKg` is `double?` (not `int?`) — plate math. `restSeconds` is required (not nullable).

---

- [x] **TASK-011a — Write `routine_day_test.dart` (RED)**
  - **REQ refs**: REQ-RT-MODEL-002
  - **Files**: `test/features/workout/domain/routine_day_test.dart`
  - **Done when**: File exists with three named tests covering SCENARIO-046, SCENARIO-047, SCENARIO-048. Running `flutter test test/features/workout/domain/routine_day_test.dart` fails (model not yet created).
  - **Notes**: Depends on TASK-010b (RoutineSlot must compile — RoutineDay embeds it). SCENARIO-046 tests empty `slots: []` + null `estimatedMinutes`. SCENARIO-048 tests raw `List<dynamic>` deserialization of nested slot maps.

---

- [x] **TASK-011b — Implement `routine_day.dart` and run `build_runner` (GREEN)**
  - **REQ refs**: REQ-RT-MODEL-002, REQ-RT-MODEL-005
  - **Files**: `lib/features/workout/domain/routine_day.dart`, `lib/features/workout/domain/routine_day.freezed.dart` (generated), `lib/features/workout/domain/routine_day.g.dart` (generated)
  - **Done when**: `dart run build_runner build --delete-conflicting-outputs` exits 0. `flutter test test/features/workout/domain/routine_day_test.dart` passes all 3 tests (SCENARIO-046..048 green).
  - **Notes**: Depends on TASK-011a. Imports `routine_slot.dart`. `slots` field is `required List<RoutineSlot>` — empty list is valid, not nullable.

---

- [x] **TASK-012a — Write `routine_test.dart` (RED)**
  - **REQ refs**: REQ-RT-MODEL-003, REQ-RT-MODEL-004, REQ-RT-MODEL-005
  - **Files**: `test/features/workout/domain/routine_test.dart`
  - **Done when**: File exists with nine named tests covering SCENARIO-049 through SCENARIO-057. Running `flutter test test/features/workout/domain/routine_test.dart` fails (model not yet created). SCENARIO-056 tests unknown `level` value throws. SCENARIO-057 is documented as a checklist note (not a `test()` call — verified by build_runner exit code).
  - **Notes**: Depends on TASK-011b (RoutineDay must compile). SCENARIO-051 tests a fully-nested raw wire map (Routine → 2 RoutineDays → 3 RoutineSlots each). SCENARIO-056 uses `ExperienceLevel` parsing — `ArgumentError` or equivalent expected on unknown value `'elite'`. The build_runner sanity (SCENARIO-057) is verified when TASK-012b completes.

---

- [x] **TASK-012b — Implement `routine.dart` and run `build_runner` (GREEN)**
  - **REQ refs**: REQ-RT-MODEL-003, REQ-RT-MODEL-004, REQ-RT-MODEL-005
  - **Files**: `lib/features/workout/domain/routine.dart`, `lib/features/workout/domain/routine.freezed.dart` (generated), `lib/features/workout/domain/routine.g.dart` (generated)
  - **Done when**: `dart run build_runner build --delete-conflicting-outputs` exits 0 and produces all 8 generated files (`exercise.freezed.dart`, `exercise.g.dart`, `routine_slot.freezed.dart`, `routine_slot.g.dart`, `routine_day.freezed.dart`, `routine_day.g.dart`, `routine.freezed.dart`, `routine.g.dart`). `flutter test test/features/workout/domain/routine_test.dart` passes all 9 tests. SCENARIO-057 is confirmed (8 generated files present). Record in apply-progress.
  - **Notes**: Depends on TASK-012a. MUST import `ExperienceLevel` from `lib/features/profile/domain/experience_level.dart` — do NOT redefine the enum. This is the only allowed `workout → profile` import (cross-feature import policy from design.md §Cross-cutting). `days` field is `required List<RoutineDay>` (empty list valid).

---

- [x] **TASK-013a — Write `routine_repository_test.dart` (RED)**
  - **REQ refs**: REQ-RT-REPO-001, REQ-RT-REPO-002
  - **Files**: `test/features/workout/data/routine_repository_test.dart`
  - **Done when**: File exists with six named tests covering SCENARIO-058, SCENARIO-059, SCENARIO-060, SCENARIO-061, SCENARIO-062, SCENARIO-063. Uses `FakeFirebaseFirestore` and the `seedRoutine` helper from design.md §7 (PR 2). Running `flutter test test/features/workout/data/routine_repository_test.dart` fails (repository not yet created).
  - **Notes**: Depends on TASK-012b. SCENARIO-062 specifically tests nested `List<dynamic>` (1 day, 2 slots). SCENARIO-063 tests `days: []`. The `seedRoutine` helper takes `days` as `List<Map<String, dynamic>>` — raw wire-format maps, not Dart model objects.

---

- [x] **TASK-013b — Implement `routine_repository.dart` (GREEN)**
  - **REQ refs**: REQ-RT-REPO-001, REQ-RT-REPO-002
  - **Files**: `lib/features/workout/data/routine_repository.dart`
  - **Done when**: `flutter test test/features/workout/data/routine_repository_test.dart` passes all 6 tests (SCENARIO-058..063 green). `flutter analyze lib/features/workout/data/routine_repository.dart` reports 0 issues.
  - **Notes**: Depends on TASK-013a. Use exact signature from design.md §3 (PR 2). No `getByIds` — only `listAll()` and `getById(String id)`. No abstract interface. Same `_fromDoc` helper shape as `ExerciseRepository`.

---

- [x] **TASK-014a — Write `routine_providers_test.dart` (RED)**
  - **REQ refs**: REQ-RT-PROVIDERS-001
  - **Files**: `test/features/workout/application/routine_providers_test.dart`
  - **Done when**: File exists with four named tests covering SCENARIO-067, SCENARIO-068, SCENARIO-069, SCENARIO-070. Uses `ProviderContainer` with auth and repository overrides. Running `flutter test test/features/workout/application/routine_providers_test.dart` fails (providers not yet created).
  - **Notes**: Depends on TASK-013b. Same auth-override `makeContainer` pattern as exercise providers test (design.md §7 PR 1). SCENARIO-067 tests unauthenticated → `[]`. SCENARIO-069/070 test `routineByIdProvider` hit/miss.

---

- [x] **TASK-014b — Implement `routine_providers.dart` (GREEN)**
  - **REQ refs**: REQ-RT-PROVIDERS-001
  - **Files**: `lib/features/workout/application/routine_providers.dart`
  - **Done when**: `flutter test test/features/workout/application/routine_providers_test.dart` passes all 4 tests (SCENARIO-067..070 green). `flutter analyze lib/features/workout/application/routine_providers.dart` reports 0 issues.
  - **Notes**: Depends on TASK-014a. Exact code from design.md §4 (PR 2). Import `firestoreProvider` from `user_providers.dart`. `routineByIdProvider` uses `ref.watch(routinesProvider.future)` — no direct Firestore calls. Manual Riverpod 2 style (no `@riverpod` codegen).

---

- [x] **TASK-015 — Add `routines` block to `firestore.rules`**
  - **REQ refs**: REQ-RT-RULES-001
  - **Files**: `firestore.rules`
  - **Done when**: `firestore.rules` contains `match /routines/{routineId}` with `allow read: if request.auth != null;` and `allow write: if false;` AFTER the `exercises` block (which PR 1 already added). The existing `users` and `exercises` blocks are unchanged. Manual emulator or dry-run validation confirms SCENARIO-064, SCENARIO-065, SCENARIO-066 pass. Result recorded in apply-progress.
  - **Notes**: Depends on TASK-014b for branch ordering. Insert AFTER the `exercises` block — see final file shape in design.md §5 (PR 2). Record `manual rules validation (routines): PASS` in apply-progress.

---

- [x] **TASK-016 — Extend `seed_workout_catalog.js` with `seedRoutines()`, orphan validation, and `--routines` flag**
  - **REQ refs**: REQ-RT-SEED-001, REQ-RT-SEED-002
  - **Files**: `scripts/seed_workout_catalog.js`, `scripts/package.json`
  - **Done when**: `scripts/seed_workout_catalog.js` contains `const routines = [...]` with ≥6 routine objects (PPL beginner, Full Body 3-day, Upper/Lower 4-day, plus ≥1 extra variety). Each routine has ≥1 `RoutineDay`, each day has ≥1 `RoutineSlot`. `validateRoutineRefs()` function iterates all slots and verifies each `exerciseId` against `const exercises`. `seedRoutines()` calls `validateRoutineRefs()` first. `main()` handles `--routines` and `--all` flags. `scripts/package.json` includes `"seed:routines"` script. SCENARIO-071, SCENARIO-072, SCENARIO-073, SCENARIO-074 are manually verifiable.
  - **Notes**: Depends on TASK-015. Validation must accumulate ALL orphan errors (not fail-fast) and log each one before throwing. Error message format from design.md §6 (ADR-4). `--routines` alone is safe because validation uses in-script `const exercises`, not Firestore reads. Uses `set()` upsert — idempotent.

---

- [x] **TASK-017 — Manual seed run against dev Firebase project (full catalog)**
  - **REQ refs**: REQ-RT-SEED-001, REQ-RT-SEED-002
  - **Files**: none (manual verification step)
  - **Done when**: `node seed_workout_catalog.js --all` completes successfully. Firebase Console shows ≥25 docs in `exercises/` and ≥6 docs in `routines/`. Re-running produces same counts (idempotency — SCENARIO-072). Orphan validation test: temporarily set a slot's `exerciseId` to `'does-not-exist'`, re-run, confirm non-zero exit + error message naming the orphan + zero Firestore writes for routines (SCENARIO-074). Revert the change. Results recorded in apply-progress.
  - **Notes**: Requires service account JSON (gitignored). Must run AFTER TASK-016. Record `seed all: PASS, exercises: N, routines: M` in apply-progress.

---

- [x] **TASK-018 — PR 2 quality gates**
  - **REQ refs**: Cross-cutting constraints §5 and §6
  - **Files**: none (verification step; may patch formatting drift)
  - **Done when**: `flutter analyze` exits 0 with no issues across all new and modified Dart files (PR 2 additions: `routine_slot.dart`, `routine_day.dart`, `routine.dart`, `routine_repository.dart`, `routine_providers.dart`, `firestore.rules`). `dart format . --output=none --set-exit-if-changed` exits 0. `flutter test` runs the full suite and all new tests are green. Total new passing tests across both PRs: ≥35 (SCENARIO-020..031, SCENARIO-035..038 from PR 1, plus SCENARIO-043..063, SCENARIO-067..070 from PR 2). Results recorded in apply-progress.
  - **Notes**: This is the merge gate for PR 2. Run after all TASK-010b through TASK-017 are complete. Confirm SCENARIO-057 (8 generated files) is also confirmed here.

---

## Dependency graph

```
PR 1 (sequential):
TASK-001 → TASK-002 → TASK-003a → TASK-003b → TASK-004a → TASK-004b
                                                              ↓
                                 TASK-005a → TASK-005b → TASK-006
                                                              ↓
                                                         TASK-007 → TASK-008 → TASK-009

PR 2 (sequential, starts after PR 1 merges):
TASK-010a → TASK-010b → TASK-011a → TASK-011b → TASK-012a → TASK-012b
                                                                  ↓
                                               TASK-013a → TASK-013b
                                                                  ↓
                                               TASK-014a → TASK-014b → TASK-015
                                                                             ↓
                                                                        TASK-016 → TASK-017 → TASK-018
```

All tasks within each PR are **sequential** (each RED test depends on the prior GREEN production code). No tasks within a PR can be parallelized — this is inherent to Strict TDD ordering.

The two PR batches are themselves sequential: PR 2 cannot start until PR 1 is merged to `main`.

---

## Review Workload Forecast

### PR 1 — Exercise collection

| Metric | Value |
|---|---|
| Estimated production LOC | ~180 (`exercise.dart` ~30, `exercise_repository.dart` ~55, `exercise_providers.dart` ~35, `firestore.rules` delta ~8, `scripts/seed_workout_catalog.js` ~120 with data, `scripts/package.json` ~15, `scripts/.env.example` ~5, `.gitignore` delta ~4) |
| Estimated test LOC | ~250 (`exercise_test.dart` ~70, `exercise_repository_test.dart` ~120, `exercise_providers_test.dart` ~60) |
| Estimated generated LOC (out of review diff) | ~200 (`exercise.freezed.dart` ~100, `exercise.g.dart` ~30; reviewers skip generated files) |
| Total meaningful diff | ~430 LOC |
| 400-LOC budget risk | **Low-Medium** (generated files inflate the raw count; production + test = ~430, well-scoped) |
| Chained PRs | **YES** — confirmed per propose.md §8 |
| Decision needed before apply | **NO** — proceed with PR 1 batch |

### PR 2 — Routine collection (deferred)

| Metric | Value |
|---|---|
| Estimated production LOC | ~220 (`routine_slot.dart` ~25, `routine_day.dart` ~20, `routine.dart` ~25, `routine_repository.dart` ~40, `routine_providers.dart` ~35, `firestore.rules` delta ~6, seed extension ~70 with data) |
| Estimated test LOC | ~350 (`routine_slot_test.dart` ~60, `routine_day_test.dart` ~70, `routine_test.dart` ~100, `routine_repository_test.dart` ~80, `routine_providers_test.dart` ~40) |
| Estimated generated LOC (out of review diff) | ~300 (3 model pairs × ~100 each) |
| Total meaningful diff | ~570 LOC |
| 400-LOC budget risk | **Medium** (meaningful diff exceeds 400; generated files are excluded from review per convention) |
| Decision | **Defer to after PR 1 merges** — evaluate at that point whether to split further or proceed as-is |

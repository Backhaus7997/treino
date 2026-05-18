# Tasks: session-model-seed

**Fase / Etapa**: Fase 4 · Etapa 1
**TDD**: STRICT — every implementation task preceded by a RED test
**Branch**: `feat/session-model-seed`

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 500–650 (models + .freezed/.g + repo + providers + rules + tests) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1: domain models + tests → PR 2: data layer + providers + rules + seed |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Domain layer (models + enum) + tests | PR 1 | Base = `feat/session-model-seed`; includes codegen |
| 2 | Data layer (repo + providers + rules + seed) + tests | PR 2 | Base = PR 1 branch; depends on Unit 1 |

---

## Phase 1 — Setup

- [ ] 1.1 [CHORE] Verify branch is `feat/session-model-seed` and `flutter test` passes green (baseline ~547 tests). Note failing count if any — do NOT proceed if baseline is red.
- [ ] 1.2 [CHORE] Confirm `test/features/workout/domain/`, `test/features/workout/data/`, `test/features/workout/application/` directories exist (already present per Fase 2). No mkdirs needed.

## Phase 2 — Domain Layer (RED → GREEN)

- [ ] 2.1 [RED] Create `test/features/workout/domain/session_status_test.dart` — SCENARIO-235 (`fromJson('active')` → `SessionStatus.active`) + SCENARIO-236 (`SessionStatus.finished.toJson()` → `'finished'`). Run `flutter test` — expect compile error (file does not exist).
- [ ] 2.2 [GREEN] Create `lib/features/workout/domain/session_status.dart` — `enum SessionStatus` with `@JsonValue('active')`/`@JsonValue('finished')` + extension `SessionStatusX` with `_wireMap`, `fromJson(String)`, `toJson()` switch. Mirror pattern of `UserRole`/`PostPrivacy`.
- [ ] 2.3 [RED] Create `test/features/workout/domain/session_test.dart` — SCENARIO-234 (all fields set + `finishedAt` null → JSON round-trip equality) + SCENARIO-239 (`status: active` → `finishedAt` is null). Expect compile error.
- [ ] 2.4 [GREEN] Create `lib/features/workout/domain/session.dart` — `@freezed class Session` with factory signature from D1: `id`, `uid`, `routineId`, `routineName`, `startedAt`, `finishedAt?`, `@Default(0.0) totalVolumeKg`, `@Default(0) durationMin`, `status`. Use `@TimestampConverter()` from `lib/features/profile/data/timestamp_converter.dart`.
- [ ] 2.5 [RED] Create `test/features/workout/domain/set_log_test.dart` — SCENARIO-237 (`rpe` omitted → round-trip, `rpe` is null) + SCENARIO-238 (`rpe: 8` → round-trip, `rpe == 8`). Expect compile error.
- [ ] 2.6 [GREEN] Create `lib/features/workout/domain/set_log.dart` — `@freezed class SetLog` with factory signature from D2: `id`, `exerciseId`, `exerciseName`, `setNumber`, `reps`, `weightKg`, `rpe?`, `completedAt`. Use `@TimestampConverter()`.
- [ ] 2.7 [GREEN] Run `dart run build_runner build --delete-conflicting-outputs` — generates `session.freezed.dart`, `session.g.dart`, `set_log.freezed.dart`, `set_log.g.dart`. (`session_status` is plain enum — no generated files.)
- [ ] 2.8 [QA] `flutter analyze lib/features/workout/domain/ test/features/workout/domain/` → 0 issues. Fix any before proceeding.
- [ ] 2.9 [QA] `flutter test test/features/workout/domain/` → all green (SCENARIO-234, 235, 236, 237, 238, 239 passing).

## Phase 3 — Data Layer (RED → GREEN)

- [ ] 3.1 [RED] Create `test/features/workout/data/session_repository_test.dart` — SCENARIO-240 (`create` writes doc with `status: 'active'`, `totalVolumeKg: 0`, `durationMin: 0`, `finishedAt` absent) + SCENARIO-241 (returned `Session.id` is non-empty and matches Firestore doc id). Use `FakeFirebaseFirestore` pattern from `post_repository_test.dart`. Expect compile error.
- [ ] 3.2 [GREEN] Create `lib/features/workout/data/session_repository.dart` — constructor `SessionRepository({required FirebaseFirestore firestore})` + private `_sessions(uid)` + `_setLogs(uid, sessionId)` getters + `create({uid, routineId, routineName, startedAt})` method (D5, D11).
- [ ] 3.3 [RED] Add tests to `session_repository_test.dart` — SCENARIO-242 (`finish(...)` → doc has `status: 'finished'`, `finishedAt` non-null, `totalVolumeKg: 95.5`, `durationMin: 45`). Run — expect RED (method missing).
- [ ] 3.4 [GREEN] Add `finish({uid, sessionId, finishedAt, totalVolumeKg, durationMin})` to `SessionRepository` using `update()` partial write (D6).
- [ ] 3.5 [RED] Add tests — SCENARIO-243 (two sessions, `listByUid` returns newer first) + SCENARIO-244 (`listByUid` returns empty list when no sessions). Run — expect RED.
- [ ] 3.6 [GREEN] Add `listByUid(uid)` to `SessionRepository` — `orderBy('startedAt', descending: true)` (D8).
- [ ] 3.7 [RED] Add tests — SCENARIO-245 (`getActive` returns session with `status: active`) + SCENARIO-246 (`getActive` returns null when none active). Run — expect RED.
- [ ] 3.8 [GREEN] Add `getActive(uid)` to `SessionRepository` — `where('status', isEqualTo: 'active').orderBy('startedAt', descending: true).limit(1)` returning `null` on empty (D7).
- [ ] 3.9 [RED] Add tests — SCENARIO-247 (`addSetLog` writes doc at nested sub-path) + SCENARIO-248 (returned `SetLog.id` is non-empty and matches sub-collection doc id). Run — expect RED.
- [ ] 3.10 [GREEN] Add `addSetLog({uid, sessionId, setLog})` to `SessionRepository` — `_setLogs(uid, sessionId).doc()`, overwrite `id` via `copyWith`, call `set(toJson())` (D9).
- [ ] 3.11 [RED] Add tests — SCENARIO-249 (`listSetLogs` returns logs ordered `setNumber` ASC with 3 logs inserted out of order) + SCENARIO-250 (`listSetLogs` returns empty list when no logs) + SCENARIO-251 (logs accessible after session `finish`). Run — expect RED.
- [ ] 3.12 [GREEN] Add `listSetLogs(uid, sessionId)` to `SessionRepository` — `orderBy('setNumber', ascending: true)` (D10). SCENARIO-251 passes without extra code (sub-collection independent of parent state).
- [ ] 3.13 [QA] `flutter analyze lib/features/workout/data/ test/features/workout/data/` → 0 issues.
- [ ] 3.14 [QA] `flutter test test/features/workout/data/` → all green (SCENARIO-240..251).

## Phase 4 — Providers Riverpod

- [ ] 4.1 [GREEN] Create `lib/features/workout/application/session_providers.dart` — `sessionRepositoryProvider` (`Provider<SessionRepository>` consuming `firestoreProvider`), `sessionsByUidProvider` (`FutureProvider.family<List<Session>, String>`), `activeSessionProvider` (`FutureProvider.family<Session?, String>`). SetLog providers deferred to Etapa 4 (D12).
- [ ] 4.2 [GREEN] Create `test/features/workout/application/session_providers_test.dart` — smoke test: `sessionRepositoryProvider` resolves without error using `ProviderContainer` with `firestoreProvider` override (`FakeFirebaseFirestore`).

## Phase 5 — Firestore Rules

- [ ] 5.1 [GREEN] Edit `firestore.rules` — add nested `match /users/{uid}/sessions/{sessionId}` block with `match /setLogs/{setLogId}` inside, after the `friendships` block. Rule: `allow read, write: if request.auth != null && request.auth.uid == uid` on both levels (D13).
- [ ] 5.2 [NOTE] SCENARIO-252..255 (rules tests via `@firebase/rules-unit-testing` + emulator) — DEFERRED to `sdd-verify` phase. Not a task for apply.

## Phase 6 — Seed Script (optional, non-blocking)

- [ ] 6.1 [GREEN][OPTIONAL] Create `scripts/seed_sessions.js` — writes 5 Sessions (`status: finished`, `finishedAt: now-1d`, `totalVolumeKg: 2500`, `durationMin: 45`) with deterministic IDs `seed_session_001..005`, no SetLogs (D14). Skip if time-boxed.

## Phase 7 — Quality Gates

- [ ] 7.1 [QA][BLOCKER] `flutter analyze` → 0 issues across entire project.
- [ ] 7.2 [QA][BLOCKER] `dart format --output=none --set-exit-if-changed .` → exit 0 (no unformatted files).
- [ ] 7.3 [QA][BLOCKER] `flutter test` full suite → green (~569 passing: 547 baseline + 22 new scenarios). Verify SCENARIO-234..251 are all present.

---

## Dependency Notes

- 2.7 (codegen) MUST run after both 2.4 AND 2.6 — both models must exist before `build_runner`.
- Phase 3 depends entirely on Phase 2 (domain types must compile first).
- Phase 4 depends on Phase 3 (`SessionRepository` must exist).
- Phase 5 is independent — can be applied in parallel with Phases 2–4.
- Phase 6 is fully optional and independent — no Dart dependency.
- 7.1–7.3 MUST be the final gate; nothing proceeds to PR after a failing QA task.

## REQ Coverage

| REQ | Tasks |
|-----|-------|
| REQ-SMS-001 | 2.3, 2.4 |
| REQ-SMS-002 | 2.1, 2.2 |
| REQ-SMS-003 | 2.5, 2.6 |
| REQ-SMS-004 | 2.4, 2.6 (denorm at write — enforced by repo in 3.2, 3.10) |
| REQ-SMS-005 | 3.1, 3.2 |
| REQ-SMS-006 | 3.2 (path `users/{uid}/sessions/`) |
| REQ-SMS-007 | 3.10 (_setLogs sub-collection) |
| REQ-SMS-008 | 3.1, 3.2 |
| REQ-SMS-009 | 3.3, 3.4 |
| REQ-SMS-010 | 3.5, 3.6 |
| REQ-SMS-011 | 3.7, 3.8 |
| REQ-SMS-012 | 3.9, 3.10 |
| REQ-SMS-013 | 3.11, 3.12 |
| REQ-SMS-014 | 5.1 (SCENARIO-252..255 deferred to verify) |

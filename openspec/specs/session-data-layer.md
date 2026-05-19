# Session Data Layer — Specification

**Domain**: Workout Session Management
**Changes**: `session-model-seed` (Fase 4 · Etapa 1) + `session-player` amendment (Etapa 2) + `post-workout-summary` amendment (Etapa 3)
**Status**: ACTIVE (source of truth)
**Last updated**: 2026-05-19
**Merged**: PR #34 (commit 83cd63b); PR #39 (squash commit c23c80c)

---

## Purpose

Define the workout session data layer: models, repositories, Riverpod providers, and Firestore security rules for tracking active and completed training sessions. This spec is the authoritative reference for all session-related backend components. All items in this spec are NEW (no existing spec to delta against).

---

## Requirements

| ID | Name | Strength | Status |
|----|------|----------|--------|
| REQ-SMS-001 | Session model fields | MUST | ✅ IMPLEMENTED |
| REQ-SMS-001b | Session.dayNumber (added in Etapa 2 amendment) | MUST | ✅ IMPLEMENTED |
| REQ-SMS-001c | Session.wasFullyCompleted (added in Etapa 2 amendment) | MUST | ✅ IMPLEMENTED |
| REQ-SMS-002 | SessionStatus enum wire format | MUST | ✅ IMPLEMENTED |
| REQ-SMS-003 | SetLog model fields | MUST | ✅ IMPLEMENTED |
| REQ-SMS-004 | Denormalized names at write time | MUST | ✅ IMPLEMENTED |
| REQ-SMS-005 | Session id is Firestore auto-id | MUST | ✅ IMPLEMENTED |
| REQ-SMS-006 | Session Firestore path | MUST | ✅ IMPLEMENTED |
| REQ-SMS-007 | SetLog Firestore path (sub-collection) | MUST | ✅ IMPLEMENTED |
| REQ-SMS-008 | SessionRepository.create initializes active session | MUST | ✅ IMPLEMENTED |
| REQ-SMS-009 | SessionRepository.finish transitions to finished | MUST | ✅ IMPLEMENTED |
| REQ-SMS-010 | SessionRepository.listByUid ordered startedAt DESC | MUST | ✅ IMPLEMENTED |
| REQ-SMS-011 | SessionRepository.getActive returns active or null | MUST | ✅ IMPLEMENTED |
| REQ-SMS-012 | SessionRepository.addSetLog appends to sub-collection | MUST | ✅ IMPLEMENTED |
| REQ-SMS-013 | SessionRepository.listSetLogs ordered setNumber ASC | MUST | ✅ IMPLEMENTED |
| REQ-SMS-014 | Firestore rules enforce owner-only access | MUST | ✅ IMPLEMENTED |
| REQ-PWS-013 | SessionRepository.getById returns Session or null | MUST | ✅ IMPLEMENTED |

---

## Detailed Requirements

### REQ-SMS-001 — Session model fields

The `Session` model MUST have fields: `id`, `uid`, `routineId`, `routineName`, `startedAt`, `finishedAt?`, `totalVolumeKg`, `durationMin`, `status`, plus `dayNumber` (REQ-SMS-001b) and `wasFullyCompleted` (REQ-SMS-001c) added by the Etapa 2 amendment. All fields MUST round-trip through JSON without data loss.

#### SCENARIO-234: Session default values and JSON round-trip

- GIVEN a `Session` with all required fields set and `finishedAt` null
- WHEN serialized to JSON and deserialized back
- THEN all fields are equal to the originals and `finishedAt` is null

---

### REQ-SMS-001b — Session.dayNumber

`Session.dayNumber: int` MUST identify which day of a multi-day routine the session targets (1-based). Defaults to `1` to allow Etapa 1 seed docs and legacy Firestore documents to deserialize without backfill. New sessions created during the player flow MUST pass the real day number selected by the user.

#### SCENARIO-234e: dayNumber defaults to 1 when absent in JSON

- GIVEN a Firestore document without `dayNumber`
- WHEN decoded via `Session.fromJson`
- THEN `dayNumber` equals `1`

---

### REQ-SMS-001c — Session.wasFullyCompleted

`Session.wasFullyCompleted: bool` MUST signal whether the user completed every target set and explicitly tapped TERMINAR SESIÓN. Defaults to `false`. Abandon paths and back-out paths MUST leave this field `false`. This is the canonical analytics signal that distinguishes completed sessions from abandoned ones — `status: finished` alone does not differentiate.

#### SCENARIO-234f: wasFullyCompleted defaults to false when absent in JSON

- GIVEN a Firestore document without `wasFullyCompleted`
- WHEN decoded via `Session.fromJson`
- THEN `wasFullyCompleted` equals `false`

---

### REQ-SMS-002 — SessionStatus enum wire values

The `SessionStatus` enum MUST have exactly two values — `active` and `finished` — with lowercase JSON wire representation.

#### SCENARIO-235: SessionStatus.fromJson('active') decodes correctly

- GIVEN the JSON string `'active'`
- WHEN decoded via `SessionStatus.fromJson`
- THEN the result is `SessionStatus.active`

#### SCENARIO-236: SessionStatus.toJson encodes to lowercase wire

- GIVEN `SessionStatus.finished`
- WHEN serialized via `toJson`
- THEN the result is the string `'finished'`

---

### REQ-SMS-003 — SetLog model fields

The `SetLog` model MUST have fields: `id`, `exerciseId`, `exerciseName`, `setNumber`, `reps`, `weightKg`, `rpe?`, `completedAt`. All fields MUST round-trip through JSON without data loss.

#### SCENARIO-237: SetLog JSON round-trip with optional rpe null

- GIVEN a `SetLog` with `rpe` omitted
- WHEN serialized to JSON and deserialized back
- THEN all fields are equal to the originals and `rpe` is null

#### SCENARIO-238: SetLog JSON round-trip with rpe present

- GIVEN a `SetLog` with `rpe: 8`
- WHEN serialized to JSON and deserialized back
- THEN `rpe` equals `8`

---

### REQ-SMS-004 — Denormalized names at write time

`Session.routineName` MUST be captured at session creation time from the provided routine name. `SetLog.exerciseName` MUST be captured at set-log creation time from the provided exercise name. Neither field SHALL be recomputed on read.

(Consistency with ADR-2 denormalization pattern — `Post.authorGymId`, `RoutineSlot.exerciseName`.)

---

### REQ-SMS-005 — Session id is Firestore auto-id

`Session.id` MUST be assigned by Firestore after the document is created. The caller SHALL NOT provide an id to `SessionRepository.create`.

#### SCENARIO-239: Session.finishedAt is null when status is active

- GIVEN a `Session` with `status: SessionStatus.active`
- WHEN the model is inspected
- THEN `finishedAt` is null

---

### REQ-SMS-006 — Session Firestore path

Sessions MUST be persisted at `users/{uid}/sessions/{sessionId}`.

---

### REQ-SMS-007 — SetLog Firestore path (sub-collection)

SetLogs MUST be persisted at `users/{uid}/sessions/{sessionId}/setLogs/{setLogId}`. This is the first sub-collection use in the codebase; all atomic updates are per-set.

---

### REQ-SMS-008 — SessionRepository.create initializes active session

`SessionRepository.create` MUST write a Session document with `status: active`, `startedAt: now`, `finishedAt: null`, `totalVolumeKg: 0`, `durationMin: 0`. It MUST return the created `Session` with a Firestore-generated `id`.

#### SCENARIO-240: create writes doc with status active and zero totals

- GIVEN a Firestore instance with no sessions for `uid`
- WHEN `create(uid, routineId, routineName, startedAt)` is called
- THEN a session document exists at `users/{uid}/sessions/{newId}` with `status: 'active'`, `totalVolumeKg: 0`, `durationMin: 0`, and `finishedAt` absent

#### SCENARIO-241: create returns Session with Firestore-generated id

- GIVEN `create(uid, routineId, routineName, startedAt)` is called
- WHEN the Future resolves
- THEN the returned `Session.id` is a non-empty string and matches the document id in Firestore

---

### REQ-SMS-009 — SessionRepository.finish transitions to finished

`SessionRepository.finish(uid, sessionId, finishedAt, totalVolumeKg, durationMin)` MUST update `status` to `finished`, set `finishedAt` to the provided timestamp, and persist `totalVolumeKg` and `durationMin`.

#### SCENARIO-242: finish transitions status and persists totals

- GIVEN an active session with `sessionId` for `uid`
- WHEN `finish(uid, sessionId, finishedAt, totalVolumeKg: 95.5, durationMin: 45)` is called
- THEN the Firestore doc has `status: 'finished'`, `finishedAt` is non-null, `totalVolumeKg: 95.5`, `durationMin: 45`

---

### REQ-SMS-010 — SessionRepository.listByUid returns sessions ordered startedAt DESC

`SessionRepository.listByUid(uid)` MUST return all sessions for the user ordered by `startedAt` descending.

#### SCENARIO-243: listByUid returns sessions newest-first

- GIVEN two sessions for `uid` — one started earlier, one later
- WHEN `listByUid(uid)` is called
- THEN the later-started session appears first in the returned list

#### SCENARIO-244: listByUid returns empty list when user has no sessions

- GIVEN a `uid` with no session documents
- WHEN `listByUid(uid)` is called
- THEN an empty list is returned

---

### REQ-SMS-011 — SessionRepository.getActive returns active session or null

`SessionRepository.getActive(uid)` MUST return the session with `status: active` for the user, or `null` if none exists.

#### SCENARIO-245: getActive returns the active session when one exists

- GIVEN a session with `status: active` for `uid`
- WHEN `getActive(uid)` is called
- THEN the returned session has `status: SessionStatus.active`

#### SCENARIO-246: getActive returns null when no active session

- GIVEN no sessions with `status: active` for `uid`
- WHEN `getActive(uid)` is called
- THEN `null` is returned

---

### REQ-SMS-012 — SessionRepository.addSetLog appends to sub-collection

`SessionRepository.addSetLog(uid, sessionId, setLog)` MUST write a new document under `users/{uid}/sessions/{sessionId}/setLogs/` with a Firestore auto-id. It MUST return the `SetLog` with the assigned `id`.

#### SCENARIO-247: addSetLog writes to nested sub-path

- GIVEN an existing session at `users/{uid}/sessions/{sessionId}`
- WHEN `addSetLog(uid, sessionId, setLog)` is called
- THEN a document exists at `users/{uid}/sessions/{sessionId}/setLogs/{newId}` with matching fields

#### SCENARIO-248: addSetLog returns SetLog with auto-id

- GIVEN `addSetLog(uid, sessionId, setLog)` is called
- WHEN the Future resolves
- THEN the returned `SetLog.id` is a non-empty string and matches the sub-collection document id

---

### REQ-SMS-013 — SessionRepository.listSetLogs ordered setNumber ASC

`SessionRepository.listSetLogs(uid, sessionId)` MUST return all SetLogs for the session ordered by `setNumber` ascending.

#### SCENARIO-249: listSetLogs returns logs ordered setNumber ASC

- GIVEN three SetLogs with `setNumber` 3, 1, 2 added in any order
- WHEN `listSetLogs(uid, sessionId)` is called
- THEN the list is ordered `[1, 2, 3]` by `setNumber`

#### SCENARIO-250: listSetLogs returns empty list when session has no logs

- GIVEN a session with no SetLog documents
- WHEN `listSetLogs(uid, sessionId)` is called
- THEN an empty list is returned

#### SCENARIO-251: SetLogs are accessible after session is finished

- GIVEN a session with two SetLogs that is then finished via `finish(...)`
- WHEN `listSetLogs(uid, sessionId)` is called
- THEN both SetLogs are returned unchanged

---

### REQ-SMS-014 — Firestore rules enforce owner-only access

Firestore security rules MUST block read and write to `users/{uid}/sessions/**` for any authenticated user whose `uid` does not match the path `uid`. Unauthenticated requests MUST be denied.

#### SCENARIO-252: Rules block cross-user read of sessions

- GIVEN user A is authenticated and user B has sessions
- WHEN user A attempts to read `users/{uid_B}/sessions`
- THEN the request is denied (permission-denied)

#### SCENARIO-253: Rules block cross-user write to setLogs

- GIVEN user A is authenticated
- WHEN user A attempts to write to `users/{uid_B}/sessions/{sid}/setLogs/{lid}`
- THEN the request is denied (permission-denied)

#### SCENARIO-254: Rules allow own-user read

- GIVEN user A is authenticated
- WHEN user A reads `users/{uid_A}/sessions`
- THEN the request is allowed

#### SCENARIO-255: Rules allow own-user write to setLogs

- GIVEN user A is authenticated
- WHEN user A writes to `users/{uid_A}/sessions/{sid}/setLogs/{lid}`
- THEN the request is allowed

---

### REQ-PWS-013 — SessionRepository.getById returns Session or null

`SessionRepository.getById(uid, sessionId)` MUST return `Future<Session?>`. If a document exists at `users/{uid}/sessions/{sessionId}`, it MUST be returned as a `Session`. If the document does not exist, it MUST return `null`.

#### SCENARIO-334: getById returns Session when document exists

- GIVEN a session document exists at `users/{uid}/sessions/{sessionId}`
- WHEN `getById(uid, sessionId)` is called
- THEN a `Session` is returned with `id == sessionId`

#### SCENARIO-335: getById returns null when document does not exist

- GIVEN no session document exists at `users/{uid}/sessions/{unknownId}`
- WHEN `getById(uid, unknownId)` is called
- THEN `null` is returned

#### SCENARIO-336: getById reads from correct Firestore sub-path

- GIVEN a Firestore instance with a session at `users/u1/sessions/s1`
- WHEN `getById('u1', 's1')` is called
- THEN the read targets the path `users/u1/sessions/s1`

---

## Implementation Summary

**File locations**:
- Models: `lib/features/workout/domain/{session_status.dart, session.dart, set_log.dart}`
- Repository: `lib/features/workout/data/session_repository.dart`
- Providers: `lib/features/workout/application/session_providers.dart`
- Rules: `firestore.rules` (lines 91–99)
- Indexes: `firestore.indexes.json`
- Seed: `scripts/seed_sessions.js` (optional)
- Tests: `test/features/workout/{domain,data,application}/*.dart`

**Test coverage**: 26 automated scenarios (SCENARIO-234..260) + 4 deferred (SCENARIO-252..255 via emulator, design decision).

---

## Notes for Future Etapas

- **Etapa 2** (Session Player): Calls `SessionRepository.create()` + `addSetLog()` during workout
- **Etapa 3** (Post-Workout Summary): Calls `SessionRepository.getById()` (REQ-PWS-013) for summary screen; calls `SessionRepository.finish()` before `PostRepository.create()`
- **Etapa 4** (Historial): Calls `listByUid()` + lazy-loads `listSetLogs()`
- **Etapa 5** (Insights): Calls `listByUid()` for aggregates
- **Etapa 6** (Wire Stats): Calls `listByUid()` for Home/Profile widgets

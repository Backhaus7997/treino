# session-data-layer Specification

**Change**: `session-model-seed`
**Fase / Etapa**: Fase 4 · Etapa 1
**SCENARIO start**: 234 (last real SCENARIO in codebase: 233 — compound test `SCENARIO-231/232/233` at `test/features/feed/presentation/public_profile_screen_test.dart:151`)

## Purpose

Establish the workout session data layer: `Session` + `SetLog` models, `SessionRepository`, Riverpod providers, and Firestore security rules for `users/{uid}/sessions/**`.

---

## Requirements

### REQ-SMS-001: Session model fields

The `Session` model MUST have fields: `id`, `uid`, `routineId`, `routineName`, `startedAt`, `finishedAt?`, `totalVolumeKg`, `durationMin`, `status`. All fields MUST round-trip through JSON without data loss.

#### SCENARIO-234: Session default values and JSON round-trip

- GIVEN a `Session` with all required fields set and `finishedAt` null
- WHEN serialized to JSON and deserialized back
- THEN all fields are equal to the originals and `finishedAt` is null

---

### REQ-SMS-002: SessionStatus enum wire values

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

### REQ-SMS-003: SetLog model fields

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

### REQ-SMS-004: Denormalized names at write time

`Session.routineName` MUST be captured at session creation time from the provided routine name. `SetLog.exerciseName` MUST be captured at set-log creation time from the provided exercise name. Neither field SHALL be recomputed on read.

(Consistency with ADR-2 denormalization pattern — `Post.authorDisplayName`, `RoutineSlot.exerciseName`.)

---

### REQ-SMS-005: Session id is Firestore auto-id

`Session.id` MUST be assigned by Firestore after the document is created. The caller SHALL NOT provide an id to `SessionRepository.create`.

#### SCENARIO-239: Session.finishedAt is null when status is active

- GIVEN a `Session` with `status: SessionStatus.active`
- WHEN the model is inspected
- THEN `finishedAt` is null

---

### REQ-SMS-006: Session Firestore path

Sessions MUST be persisted at `users/{uid}/sessions/{sessionId}`.

---

### REQ-SMS-007: SetLog Firestore path

SetLogs MUST be persisted at `users/{uid}/sessions/{sessionId}/setLogs/{setLogId}`.

---

### REQ-SMS-008: SessionRepository.create initializes active session

`SessionRepository.create` MUST write a Session document with `status: active`, `startedAt: now`, `finishedAt: null`, `totalVolumeKg: 0`, `durationMin: 0`. It MUST return the created `Session` with a Firestore-generated `id`.

#### SCENARIO-240: create writes doc with status active and zero totals

- GIVEN a Firestore instance with no sessions for `uid`
- WHEN `create(uid, routineId, routineName)` is called
- THEN a session document exists at `users/{uid}/sessions/{newId}` with `status: 'active'`, `totalVolumeKg: 0`, `durationMin: 0`, and `finishedAt` absent

#### SCENARIO-241: create returns Session with Firestore-generated id

- GIVEN `create(uid, routineId, routineName)` is called
- WHEN the Future resolves
- THEN the returned `Session.id` is a non-empty string and matches the document id in Firestore

---

### REQ-SMS-009: SessionRepository.finish transitions to finished

`SessionRepository.finish(uid, sessionId, totalVolumeKg, durationMin)` MUST update `status` to `finished`, set `finishedAt` to the current timestamp, and persist `totalVolumeKg` and `durationMin`.

#### SCENARIO-242: finish transitions status and persists totals

- GIVEN an active session with `sessionId` for `uid`
- WHEN `finish(uid, sessionId, totalVolumeKg: 95.5, durationMin: 45)` is called
- THEN the Firestore doc has `status: 'finished'`, `finishedAt` is non-null, `totalVolumeKg: 95.5`, `durationMin: 45`

---

### REQ-SMS-010: SessionRepository.listByUid returns sessions ordered startedAt DESC

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

### REQ-SMS-011: SessionRepository.getActive returns active session or null

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

### REQ-SMS-012: SessionRepository.addSetLog appends to sub-collection

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

### REQ-SMS-013: SessionRepository.listSetLogs returns logs ordered setNumber ASC

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

### REQ-SMS-014: Firestore rules enforce owner-only access

Firestore security rules MUST block read and write to `users/{uid}/sessions/**` for any authenticated user whose `uid` does not match the path `uid`. Unauthenticated requests MUST be denied.

#### SCENARIO-252: Rules block — authenticated user cannot read another user's sessions

- GIVEN user A is authenticated and user B has sessions
- WHEN user A attempts to read `users/{uid_B}/sessions`
- THEN the request is denied (permission-denied)

#### SCENARIO-253: Rules block — authenticated user cannot write another user's setLogs

- GIVEN user A is authenticated
- WHEN user A attempts to write to `users/{uid_B}/sessions/{sid}/setLogs/{lid}`
- THEN the request is denied (permission-denied)

#### SCENARIO-254: Rules allow — user reads own sessions

- GIVEN user A is authenticated
- WHEN user A reads `users/{uid_A}/sessions`
- THEN the request is allowed

#### SCENARIO-255: Rules allow — user writes own setLogs

- GIVEN user A is authenticated
- WHEN user A writes to `users/{uid_A}/sessions/{sid}/setLogs/{lid}`
- THEN the request is allowed

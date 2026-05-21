# Spec: Coach Plans Mobile — Data Layer

**Capability**: coach-plans-mobile-data
**Layer**: workout data (routine repository extension)
**Fase / Etapa**: 5 / 4
**SDD Cycle**: 2026-05-21
**Delivered by**: PR #64 (`feat/coach-plans-mobile-data`)
**Status**: ARCHIVED
**Related Specs**: workout-application.md, firestore-schema.md

---

## Overview

The coach-plans-mobile-data layer extends `RoutineRepository` with two coach-aware methods — `listAssignedTo` and `createAssigned` — that enable a trainer to persist plans and an athlete to query plans assigned to them. A Riverpod `FutureProvider.autoDispose.family` wraps the query for UI consumption. Firestore rules are extended to allow plan creation by trainers; a composite index is declared proactively to avoid a silent `failed-precondition` at runtime.

### Motivation

Fase 5 Etapa 1 introduced coach-related fields to `Routine` (source, assignedBy, assignedTo, visibility). Etapa 3 confirmed TrainerLink infrastructure. The read rules already permit athletes to see their assigned plans. This phase closes the gap by adding write capability: trainers can create and persist plans for athletes.

### Capabilities

| Capability | Provided by |
|------------|-------------|
| Query assigned plans by athlete UID | `RoutineRepository.listAssignedTo(athleteId)` |
| Create and persist a plan as trainer | `RoutineRepository.createAssigned(routine)` |
| Provider wrapper for UI consumption | `assignedRoutinesProvider` (FutureProvider.autoDispose.family) |
| Firestore rule: trainer can create | firestore.rules allow create block |
| Firestore rule: validation on create | assignedBy == auth.uid, source == 'trainer-assigned', visibility in ['private', 'shared'] |
| Composite index for efficient queries | firestore.indexes.json — assignedTo + source + createdAt |

---

## Requirements

| ID | Name | Strength |
|----|------|-------------|
| REQ-COACH-PLANS-001 | `RoutineRepository.listAssignedTo` query contract | MUST |
| REQ-COACH-PLANS-002 | `RoutineRepository.createAssigned` persistence contract | MUST |
| REQ-COACH-PLANS-003 | `assignedRoutinesProvider` — success path | MUST |
| REQ-COACH-PLANS-004 | `assignedRoutinesProvider` — error propagation | MUST |
| REQ-COACH-PLANS-005 | Firestore rule — trainer can create an assigned plan | MUST |
| REQ-COACH-PLANS-006 | Firestore rule — `assignedBy` mismatch is denied | MUST |
| REQ-COACH-PLANS-007 | Firestore rule — `visibility: public` denied on create | MUST |
| REQ-COACH-PLANS-008 | Firestore rule — wrong `source` denied on create | MUST |
| REQ-COACH-PLANS-009 | Firestore rule — anonymous create denied | MUST |
| REQ-COACH-PLANS-010 | Firestore rule — existing read rules remain valid | MUST |
| REQ-COACH-PLANS-011 | Composite index `assignedTo + source + createdAt` declared | MUST |

### SCENARIO Coverage

- **SCENARIO-432**: `listAssignedTo` returns only plans assigned to the given athlete, newest first
- **SCENARIO-433**: `listAssignedTo` returns empty list when athlete has no assigned plans
- **SCENARIO-434**: `createAssigned` writes the routine and returns it with a populated id
- **SCENARIO-435**: `createAssigned` does not modify `source`, `assignedBy`, or `assignedTo`
- **SCENARIO-436**: `assignedRoutinesProvider` resolves to the repository result
- **SCENARIO-437**: `assignedRoutinesProvider` exposes `AsyncError` when the repository throws
- **SCENARIO-438**: authenticated trainer creates a plan with correct fields — allowed (emulator-deferred)
- **SCENARIO-439**: create with `assignedBy` pointing to another user — denied (emulator-deferred)
- **SCENARIO-440**: create with `visibility: public` — denied (emulator-deferred)
- **SCENARIO-441**: create with `source: system` — denied (emulator-deferred)
- **SCENARIO-442**: anonymous create — denied (emulator-deferred)
- **SCENARIO-443**: `assignedTo` athlete can still read their assigned plan after rule change (emulator-deferred)

---

## API Layer: Repositories and Providers

### RoutineRepository Extensions

**Module**: `lib/features/workout/data/routine_repository.dart`

**New Public Methods**:

#### `listAssignedTo(String athleteId)`

**Signature**:
```dart
Future<List<Routine>> listAssignedTo(String athleteId)
```

**Query Contract**:
```
where('assignedTo', isEqualTo, athleteId)
.where('source', isEqualTo, 'trainer-assigned')
.orderBy('createdAt', descending: true)
.limit(20)
```

**Semantics**:
- Filters plans assigned to the given athlete, newest first.
- Applies a double-filter (assignedTo AND source) to avoid future contamination if `userCreated` plans are added.
- Returns up to 20 results (defensive limit).
- Returns empty list when no plans match.
- Throws `FirebaseException` on network/auth failure.

#### `createAssigned(Routine routine)`

**Signature**:
```dart
Future<Routine> createAssigned(Routine routine)
```

**Behavior**:
1. Accepts a `Routine` with `assignedBy`, `assignedTo`, and `source == 'trainer-assigned'` populated.
2. Defensive client-side validation: non-null assignedBy/assignedTo, source must equal 'trainer-assigned'.
3. Serializes to JSON, removes the 'id' field (if present), adds `createdAt: FieldValue.serverTimestamp()`.
4. Calls `routinesCollection.add(json)` to generate a new document ID.
5. Returns the result as a `Routine` with the generated ID populated (copyWith(id: docRef.id)).
6. Throws `FirebaseException` on network/auth failure.

**Invariants**:
- Input `routine.id` must be empty or ignored (output id comes from Firestore).
- `source`, `assignedBy`, `assignedTo` are never modified (immutable after creation).
- `createdAt` is server-set; client `createdAt` (if present) is discarded.

### assignedRoutinesProvider

**Module**: `lib/features/workout/application/assigned_routine_providers.dart`

**Type**: `FutureProvider.autoDispose.family<List<Routine>, String>`

**Family Key**: athleteId (String)

**Semantics**:
- Watches `authStateChangesProvider` to get current user UID.
- If athleteId is empty or blank, short-circuits to empty `AsyncValue.data([])`.
- Otherwise, delegates to `RoutineRepository.listAssignedTo(athleteId)`.
- Automatically disposes when the widget is unmounted (autoDispose).
- Propagates repository errors as `AsyncError`.

**Callers**:
- `MiPlanSection` — passes logged-in athlete's UID.
- `AthleteDetailScreen` — passes the drilled-in athlete UID (may differ from logged-in user if trainer viewing).

---

## Firestore Rules and Indexes

### Rules Extension: allow create

**File**: `firestore.rules`

**New Block** (under `match /routines/{routineId}`):

```firestore-rules
allow create: if request.auth != null
              && request.resource.data.assignedBy == request.auth.uid
              && request.resource.data.source == 'trainer-assigned'
              && request.resource.data.visibility in ['private', 'shared']
              && request.resource.data.assignedTo is string
              && request.resource.data.assignedTo != '';
```

**Semantics**:
- `auth != null`: only authenticated users can create.
- `assignedBy == auth.uid`: creator must be the trainer (prevents spoofing).
- `source == 'trainer-assigned'`: enforces the semantic flag (prevents accidental userCreated writes).
- `visibility in ['private', 'shared']`: forbids public plans (public plans are deferred to future phases).
- `assignedTo is string && != ''`: basic structure validation (athlete UID required).

**Non-Validated** (client-side responsibility):
- Days/slots structure, exercise references, sets/reps ranges → no server-side validation (anti-pattern for MVP).
- Role lookup (is assignedBy user actually a trainer?) → NO cross-collection rule check (deferred, anti-pattern).

### Composite Index

**File**: `firestore.indexes.json`

**New Index**:
```json
{
  "collectionGroup": "routines",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "assignedTo", "order": "ASCENDING" },
    { "fieldPath": "source", "order": "ASCENDING" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```

**Rationale**:
- Lessons from Fase 3 Etapa 3 (mi-gym bug): without this index, the query in `listAssignedTo` triggers a `failed-precondition` error at runtime.
- Proactive declaration ensures the index is deployed BEFORE rule changes go live.
- Order: assignedTo ascending (filter), source ascending (filter), createdAt descending (sort).

---

## Invariants and Domain Rules

1. **Multi-plan latest-first**: No `status` or `archivedAt` field. Newest plan (highest createdAt) is first.
2. **createdAt field**: Not present in Routine freezed model. Populated server-side via `FieldValue.serverTimestamp()` in `createAssigned`. Routine.fromJson ignores unknown fields.
3. **Immutability post-creation**: `source`, `assignedBy`, `assignedTo` never change. Trainer who created the plan is immutable.
4. **listAll() unaffected**: The existing `listAll()` method (used by athletes to see their own routines) is unaffected by new rules or indexes.
5. **No cross-collection role check**: Rules do not validate that `assignedBy` user has the trainer role. This is a client-side gate only.

---

## Out of Scope (Deferred)

- Editing/deleting assigned plans (allow update/delete remain `if false`) → Etapa 7
- Server-side validation of days/slots structure → deferred
- Cross-collection role lookup in rules → deferred (performance concern)
- Push/in-app notification when plan assigned → Fase 6
- `sharedWithTrainer` in `TrainerLink` (pre-req for Etapa 6 athlete session history) → Etapa 6 pre-work

---

## Test Coverage

| Layer | Module | Scenarios | Fixture Type |
|-------|--------|-----------|--------------|
| Repository | RoutineRepository.listAssignedTo | SCENARIO-432, 433 | Unit (fake_cloud_firestore) |
| Repository | RoutineRepository.createAssigned | SCENARIO-434, 435 | Unit (fake_cloud_firestore) |
| Provider | assignedRoutinesProvider | SCENARIO-436, 437 | Unit (ProviderContainer) |
| Rules | firestore.rules allow create | SCENARIO-438..443 | Manual (emulator, deferred) |
| Index | firestore.indexes.json | Static verification | N/A |

---

## Quality Gates

| Gate | Result |
|------|--------|
| `flutter analyze` | ✅ 0 issues |
| `dart format` | ✅ clean |
| `flutter test` | ✅ 434 passed (repo + provider tests for this layer) |

---

## Firestore Rules Audit

| Query | Caller | Rule Grant | Verdict |
|-------|--------|-----------|---------|
| where(assignedTo) + where(source) + orderBy(createdAt DESC) | listAssignedTo | allow read: if visibility check | ✅ PASS |
| add(routine) with assignedBy/source/visibility | createAssigned | allow create: if assignedBy == auth.uid && source == 'trainer-assigned' && visibility in [private, shared] | ✅ PASS |

---

## Related Artifacts

| Artifact | Path / Topic Key | Purpose |
|----------|------------------|---------|
| Proposal | sdd/coach-plans-mobile/proposal | Original intent and scope |
| Spec | sdd/coach-plans-mobile/spec | All 30 REQ + SCENARIO-432..465 |
| Design | sdd/coach-plans-mobile/design | Technical decisions (listAssignedTo, createAssigned, index deployment) |
| Tasks | sdd/coach-plans-mobile/tasks | 10 tasks for this layer (T01..T10) |
| Apply Progress | sdd/coach-plans-mobile/apply-progress | TDD evidence (RED/GREEN cycles) |
| Archive Report | sdd/coach-plans-mobile/archive-report | Cycle summary, follow-ups |

---

**Specification maintained by**: Dev A
**Last updated**: 2026-05-21
**Status**: ARCHIVED (PR #64 merged, data layer complete)

# Design: session-model-seed

**Fase / Etapa**: Fase 4 · Etapa 1
**Branch**: `feat/session-model-seed`
**SCENARIO start**: 234

## Technical Approach

Three `@freezed` models (`Session`, `SetLog`, `SessionStatus` enum) plus a `SessionRepository` con 6 métodos contra `users/{uid}/sessions/{sessionId}/setLogs/{setLogId}` (primera sub-colección del codebase). Patrón idéntico a `PostRepository`/`UserRepository`: inyección de `FirebaseFirestore`, collection getters privados, denormalización de nombres at-write-time (ADR-2). `DateTime` siempre via `@TimestampConverter()` desde `lib/features/profile/data/timestamp_converter.dart`. Enums plain Dart con `@JsonValue` lowercase + `extension` con `_wireMap` y `fromJson`/`toJson` switch — espejo exacto de `UserRole`/`PostPrivacy`. Providers Riverpod mínimos para Etapa 1 (repo + listByUid + getActive); SetLog providers se difieren a Etapa 4. TDD strict, fechas inyectadas para determinismo.

## Architecture Decisions

### D1 — `Session` factory signature
**Choice**: orden y tipos exactos:
```dart
const factory Session({
  required String id,
  required String uid,
  required String routineId,
  required String routineName,
  @TimestampConverter() required DateTime startedAt,
  @TimestampConverter() DateTime? finishedAt,
  @Default(0.0) double totalVolumeKg,
  @Default(0) int durationMin,
  required SessionStatus status,
}) = _Session;
```
**Rationale**: `totalVolumeKg` es `double` para soportar pesos fraccionarios; `durationMin` es `int` (UX sin segundos); `@Default` permite write inicial sin pasar los totals; `finishedAt` nullable (active sessions); `id` lo asigna `create()` con `doc().id`.

### D2 — `SetLog` factory signature
**Choice**:
```dart
const factory SetLog({
  required String id,
  required String exerciseId,
  required String exerciseName,
  required int setNumber,
  required int reps,
  required double weightKg,
  int? rpe,
  @TimestampConverter() required DateTime completedAt,
}) = _SetLog;
```
**Rationale**: `setNumber` 1-indexed (UX-friendly); `rpe` nullable (1-10 cuando se reporta); `weightKg` double; `id` asignado en `addSetLog()`. No es append-only desde el modelo (no enforcement runtime) pero por convención **no se edita** — si Etapa 2/3 necesita edición, se introduce un método explícito.

### D3 — `SessionStatus` enum
**Choice**: `enum SessionStatus { @JsonValue('active') active, @JsonValue('finished') finished }` + extensión `SessionStatusX` con `_wireMap`, `fromJson(String)` y `toJson()` switch. Idéntico patrón a `UserRole`.
**Rationale**: consistencia con el resto del codebase; el switch garantiza exhaustividad en compile-time.

### D4 — `SessionRepository` constructor
**Choice**: `SessionRepository({required FirebaseFirestore firestore})`.
**Rationale**: paridad con `PostRepository`/`UserRepository`/`RoutineRepository`. Sin DI de Clock — el caller pasa `DateTime` cuando hace falta determinismo.

### D5 — Time injection en `create()` y `finish()`
**Choice**: el caller pasa `DateTime` como parámetro; el repo NO llama `DateTime.now()`.
```dart
Future<Session> create({
  required String uid,
  required String routineId,
  required String routineName,
  required DateTime startedAt,
});

Future<void> finish({
  required String uid,
  required String sessionId,
  required DateTime finishedAt,
  required double totalVolumeKg,
  required int durationMin,
});
```
**Alternatives**: `DateTime.now()` dentro del repo (rechazado — tests indeterministas, ya pisamos esa piedra en `UserRepository`).
**Rationale**: SCENARIO-242 valida `finishedAt` non-null; con inyección el test fija el timestamp y assertiona igualdad. Etapa 2 (UI) pasará `DateTime.now().toUtc()` desde el caller.

### D6 — `finish()` write strategy
**Choice**: `_sessions(uid).doc(sessionId).update({...})` con los 4 campos (`status`, `finishedAt`, `totalVolumeKg`, `durationMin`).
**Alternatives**: `set(merge: true)` (rechazado — `update()` falla si el doc no existe, lo cual es la semántica correcta: no se debe finalizar una sesión inexistente).
**Rationale**: match con `UserRepository.update()` que usa partial update.

### D7 — `getActive()` query
**Choice**: `where('status', isEqualTo: 'active').orderBy('startedAt', descending: true).limit(1)`.
**Rationale**: si quedó más de una activa (crash), devolver la más reciente. Etapa 2 decide UX para huérfanas.

### D8 — `listByUid()` query
**Choice**: `orderBy('startedAt', descending: true)` sin paginación.
**Rationale**: MVP. Etapa 4 (historial) puede agregar cursor-based si N>100.

### D9 — `addSetLog()` signature y `id`
**Choice**:
```dart
Future<SetLog> addSetLog({
  required String uid,
  required String sessionId,
  required SetLog setLog,
});
```
El repo hace `doc()` para generar id, luego `set(setLog.copyWith(id: ref.id).toJson())`. Caller pasa `SetLog` con `id: ''` (placeholder); repo lo reemplaza. **`SetLog.id` SÍ existe en el modelo** (per spec REQ-SMS-003 + SCENARIO-248).
**Rationale**: paridad con `PostRepository.create`. Spec REQ-SMS-012 requiere retornar `SetLog` con id asignado.

### D10 — `listSetLogs()` query
**Choice**: `orderBy('setNumber', ascending: true)`.

### D11 — Sub-collection access pattern (`fake_cloud_firestore`)
**Choice**: collection getters privados parametrizados por uid/sessionId:
```dart
CollectionReference<Map<String, Object?>> _sessions(String uid) =>
    _firestore.collection('users').doc(uid).collection('sessions');

CollectionReference<Map<String, Object?>> _setLogs(String uid, String sessionId) =>
    _sessions(uid).doc(sessionId).collection('setLogs');
```
**Rationale**: `fake_cloud_firestore` soporta nested collections con la misma API que prod. Sin gimnasia adicional.

### D12 — Providers Riverpod (Etapa 1 scope)
**Choice**:
```dart
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(firestore: ref.watch(firestoreProvider)),
);

final sessionsByUidProvider =
    FutureProvider.family<List<Session>, String>((ref, uid) {
  return ref.watch(sessionRepositoryProvider).listByUid(uid);
});

final activeSessionProvider =
    FutureProvider.family<Session?, String>((ref, uid) {
  return ref.watch(sessionRepositoryProvider).getActive(uid);
});
```
SetLog providers se **difieren a Etapa 4** (lazy-load en historial).
**Rationale**: Etapa 1 sólo necesita el repo y dos lecturas read-only para wire de Home stats (Etapa 6). El player (Etapa 2) llamará el repo directamente desde su Notifier.

### D13 — `firestore.rules` shape
**Choice**: top-level match anidado, en este orden:
```
match /users/{uid}/sessions/{sessionId} {
  allow read, write: if request.auth != null && request.auth.uid == uid;

  match /setLogs/{setLogId} {
    allow read, write: if request.auth != null && request.auth.uid == uid;
  }
}
```
Insertar dentro del bloque `match /databases/{database}/documents`, después de `match /friendships/{friendshipId}`.
**Alternatives**: dos matches top-level separados (rechazado — el anidado lee mejor y agrupa la jerarquía visualmente).
**Rationale**: el `uid` del path es el dueño absoluto; cualquier mutación válida sólo si autenticado y match exacto. No hay validación de campos (a diferencia de `users/{uid}`) porque no hay campos inmutables.

### D14 — Seed script (`scripts/seed_sessions.js`)
**Choice**: opcional, no bloquea merge. Genera 2-3 Sessions vacías (`status: finished`, `finishedAt: now - 1d`, `totalVolumeKg: 2500`, `durationMin: 45`) per user, **sin SetLogs**. Etapa 3+ ampliará con detalle cuando exista UI que los visualice.
**Rationale**: Etapa 1 sólo necesita data para validar el wire de Home stats (Etapa 6). SetLogs requieren más cuidado (denormalización de exerciseName) que se hace mejor cuando la UI existe.

## Data Flow

```
            create(uid, routineId, routineName, startedAt)
                        │
                        ▼
      ┌─────────────────────────────────┐
      │ SessionRepository.create        │
      │  1. ref = _sessions(uid).doc()  │
      │  2. session = Session(id: ref.id, status: active, totals: 0)
      │  3. ref.set(session.toJson())   │
      │  4. return session              │
      └─────────────────────────────────┘
                        │
                        ▼
                  users/{uid}/sessions/{newId}

  (during workout) addSetLog(uid, sessionId, setLog) ──→ setLogs sub-collection

            finish(uid, sessionId, finishedAt, totals)
                        │
                        ▼
      _sessions(uid).doc(sessionId).update({
        status: 'finished', finishedAt, totalVolumeKg, durationMin
      })

  (later reads)
  listByUid(uid)  → orderBy startedAt DESC
  getActive(uid)  → where status=active, limit 1
  listSetLogs(uid, sessionId) → orderBy setNumber ASC
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `lib/features/workout/domain/session_status.dart` | Create | Enum + `SessionStatusX` extension |
| `lib/features/workout/domain/session.dart` | Create | `@freezed` model + `part` files |
| `lib/features/workout/domain/session.freezed.dart` | Generated | `build_runner` output |
| `lib/features/workout/domain/session.g.dart` | Generated | `build_runner` output |
| `lib/features/workout/domain/set_log.dart` | Create | `@freezed` model + `part` files |
| `lib/features/workout/domain/set_log.freezed.dart` | Generated | `build_runner` output |
| `lib/features/workout/domain/set_log.g.dart` | Generated | `build_runner` output |
| `lib/features/workout/data/session_repository.dart` | Create | Repo Firestore con 6 métodos |
| `lib/features/workout/application/session_providers.dart` | Create | `sessionRepositoryProvider`, `sessionsByUidProvider`, `activeSessionProvider` |
| `firestore.rules` | Modify | + bloque anidado sessions/setLogs |
| `scripts/seed_sessions.js` | Create (optional) | Seed contra emulator |
| `test/features/workout/domain/session_test.dart` | Create | SCENARIO-234, 239 |
| `test/features/workout/domain/session_status_test.dart` | Create | SCENARIO-235, 236 |
| `test/features/workout/domain/set_log_test.dart` | Create | SCENARIO-237, 238 |
| `test/features/workout/data/session_repository_test.dart` | Create | SCENARIO-240..251 |

Rules tests (SCENARIO-252..255): differred to verify phase via emulator (no Flutter unit-test path). Will be marked `// TODO(rules-test): Etapa 1 verify` in repo test file header.

## Interfaces / Contracts

### `SessionRepository` public API

```dart
class SessionRepository {
  SessionRepository({required FirebaseFirestore firestore});

  Future<Session> create({
    required String uid,
    required String routineId,
    required String routineName,
    required DateTime startedAt,
  });

  Future<void> finish({
    required String uid,
    required String sessionId,
    required DateTime finishedAt,
    required double totalVolumeKg,
    required int durationMin,
  });

  Future<List<Session>> listByUid(String uid);

  Future<Session?> getActive(String uid);

  Future<SetLog> addSetLog({
    required String uid,
    required String sessionId,
    required SetLog setLog,
  });

  Future<List<SetLog>> listSetLogs({
    required String uid,
    required String sessionId,
  });
}
```

## Testing Strategy

| Layer | What | Approach |
|-------|------|----------|
| Unit (model) | `Session` round-trip + `finishedAt` null | `Session(...).toJson()` → `fromJson(...)` equality |
| Unit (model) | `SetLog` round-trip con/sin rpe | idem, 2 tests |
| Unit (enum) | `SessionStatus.fromJson('active')`, `toJson()` para `finished` | switch + map assertion |
| Repo | 6 métodos × happy path + edge (empty list, null active, sub-coll order) | `FakeFirebaseFirestore` patron de `post_repository_test.dart` |
| Rules | 4 SCENARIOs (block A→B read, write; allow A→A read, write) | `firebase emulators:exec` con `@firebase/rules-unit-testing` — verify phase |

## Migration / Rollout

No data migration (greenfield collection). Deploy de rules tras merge: `firebase deploy --only firestore:rules`. Rollback en proposal.md.

## Open Questions

None — todas las decisiones estructurales se resolvieron en explore y proposal. El design fija las firmas exactas para que apply no improvise.

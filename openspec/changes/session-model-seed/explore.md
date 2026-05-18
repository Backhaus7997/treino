# Explore — session-model-seed

**Change**: `session-model-seed`
**Fase / Etapa**: Fase 4 · Etapa 1
**Branch (target)**: `feat/session-model-seed`
**Owner**: Dev A
**Project**: treino
**Artifact store**: hybrid
**Engram key**: `sdd/session-model-seed/explore`

## Estado actual del codebase

Patrones estables Fase 1-3 a seguir:

- **Modelos**: `@freezed` + `json_serializable` con generated pairs. Ref: `lib/features/feed/domain/post.dart:13`, `lib/features/workout/domain/routine.dart:9`.
- **Enums**: plain Dart + `@JsonValue('lowercase')` + extension con `_wireMap`. Ref: `lib/features/feed/domain/post_privacy.dart:3`.
- **Timestamps**: `@TimestampConverter()` sobre `DateTime`. Ref: `lib/features/profile/data/timestamp_converter.dart:4`.
- **Repos**: `FirebaseFirestore` injection, collection getter privado, clase concreta. Ref: `lib/features/feed/data/post_repository.dart:7`.
- **Providers**: Riverpod 2 manual, `Provider<Repo>` + `FutureProvider` auth-gated. Ref: `lib/features/workout/application/routine_providers.dart:9`.
- **Rules**: `firestore.rules` flat structure, 5 collections actuales. `users/{uid}/sessions` sería la PRIMERA sub-colección del codebase.
- **Tests**: `fake_cloud_firestore` confirmado soporta sub-colecciones.
- **SCENARIO actual max**: SCENARIO-231 en `test/features/feed/presentation/public_profile_screen_test.dart:151`. Nuevos arrancan en **SCENARIO-232**.
- **Sin colisión**: zero refs a `session`/`SetLog`/player stubs en `lib/`.

## Decisiones resueltas

1. **`SetLog` en sub-colección** `users/{uid}/sessions/{sessionId}/setLogs/{setLogId}` (NO embedded list).
2. **`Session.routineName` denormalizado** — sigue ADR-2 (igual que `RoutineSlot.exerciseName`, `Post.authorDisplayName`). Evita join a `routines/{id}` en historial.
3. **`SetLog.exerciseName` denormalizado** — para Insights (Etapa 5) sin join.
4. **`totalVolumeKg` y `durationMin`**: storage at finish time (no compute on read).
5. **API completo de `SessionRepository`**: `create`, `finish`, `listByUid`, `getActive`, `addSetLog`, `listSetLogs`.
6. **`getActive(uid)` mandatory** — Etapa 2 (player) lo necesita para detectar sesiones huérfanas tras crash.
7. **Feature folder**: `lib/features/workout/` — `Session` y `SetLog` son workout domain (coherente con `Routine`, `Exercise`).
8. **`Session.id`**: Firestore auto-id, asignado post-create (mismo patrón que `Post.id`).

## Áreas afectadas

**Nuevos archivos — domain** (`lib/features/workout/domain/`):
- `session_status.dart` (enum `active` | `finished`)
- `session.dart` + `.freezed.dart` + `.g.dart`
- `set_log.dart` + `.freezed.dart` + `.g.dart`

**Nuevos archivos — data** (`lib/features/workout/data/`):
- `session_repository.dart`

**Nuevos archivos — application** (`lib/features/workout/application/`):
- `session_providers.dart`

**Nuevos archivos — scripts** (opcional, MVP):
- `scripts/seed_sessions.js`

**Nuevos archivos — tests** (SCENARIO-232+):
- `test/features/workout/domain/session_status_test.dart`
- `test/features/workout/domain/session_test.dart`
- `test/features/workout/domain/set_log_test.dart`
- `test/features/workout/data/session_repository_test.dart`

**Modificados**:
- `firestore.rules` — agregar bloques `users/{uid}/sessions/{sessionId}` + `users/{uid}/sessions/{sessionId}/setLogs/{setLogId}`

**Sin tocar**:
- `pubspec.yaml`, UI screens, `scripts/package.json`

## Aproximaciones

| Aproximación | Pros | Cons | Esfuerzo |
|---|---|---|---|
| **A: `SetLog` sub-colección** | Atomic write por set (live player Etapa 2 lo necesita). Rules limpias via path uid. Lazy-load en historial. Patrón natural Firestore para owned child records. | 2 queries para leer sesión completa. Primera sub-colección del codebase. Repo necesita `addSetLog` + `listSetLogs`. | Medio |
| **B: `SetLog` embedded en `Session`** | Single doc read. Mismo patrón que `Routine.days`. API repo más simple. | Rewrites doc entera en cada set check → race conditions en player. `arrayUnion` mitiga pero complica writes. Doc crece sin bound. | Bajo |

**Recomendación**: **A** — el factor decisivo es Etapa 2 (player) que escribe SetLog por cada set completado. Atomic independent writes es el patrón Firestore correcto. El costo de 2 queries en historial se mitiga con lazy-load (la card del historial solo necesita data session-level: `routineName`, `totalVolumeKg`, `durationMin`, `startedAt`).

## Riesgos

1. **Sesiones huérfanas tras crash**: si la app crashea entre `create` y `finish`, queda una sesión `active`. `getActive()` la expone y Etapa 2 maneja la lógica de resume/cancel.
2. **N+1 en historial**: `listByUid` retorna sessions sin setLogs. Etapa 4 hace lazy-load de `listSetLogs` cuando expandís una row.
3. **Rules nested vs flat**: Firestore rules soporta ambos. Flat (top-level `match /users/{uid}/sessions/...`) más consistente con el archivo actual.
4. **PR size**: ~250-300 líneas (impl + tests). Bajo riesgo, dentro del budget de 400.

## Listo para Proposal

Sí — todas las decisiones resueltas, sin forks abiertos. Proceder a `sdd-propose`.

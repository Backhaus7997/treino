# Proposal: session-model-seed

**Fase / Etapa**: Fase 4 · Etapa 1
**Owner**: Dev A (Martín)
**Branch**: `feat/session-model-seed`
**Engram key**: `sdd/session-model-seed/proposal`

## Intent

Establecer la capa de datos de sesiones de entrenamiento (modelos `Session` + `SetLog`, repo Firestore, providers Riverpod, rules) que habilita las 5 etapas restantes de Fase 4 (player, post-entreno, historial, insights, wire stats reales).

## Scope

### In Scope
- 3 modelos `@freezed`: `Session`, `SetLog`, enum `SessionStatus` (`active` | `finished`)
- `SessionRepository` con 6 métodos: `create`, `finish`, `listByUid`, `getActive`, `addSetLog`, `listSetLogs`
- 1 provider Riverpod (`session_providers.dart`): `Provider<SessionRepository>` + `FutureProvider.family<List<Session>, String>` para `listByUid`
- `firestore.rules`: bloques `users/{uid}/sessions/{sessionId}` + `users/{uid}/sessions/{sessionId}/setLogs/{setLogId}` con `request.auth.uid == uid`
- Seed script opcional (`scripts/seed_sessions.js`) contra emulator
- Tests SCENARIO-232+ (4 archivos: unit modelos + repo con `fake_cloud_firestore`)

### Out of Scope
- UI del player / pantalla de sesión activa (Etapa 2)
- Resumen post-entreno + compartir post (Etapa 3)
- Historial + expandir rows (Etapa 4)
- Insights screen (Etapa 5)
- Wire stats reales en Home/Profile (Etapa 6)
- Auto-discard de sesiones huérfanas (Fase 6 / polish)
- Cloud Function `auto-finish` con timeout (Fase 6 / polish)
- UX de "Retomar o descartar" sesión huérfana — `getActive()` expone, Etapa 2 decide UX

## Capabilities

### New Capabilities
- `session-data-layer`: modelos de sesión + repo Firestore + providers + rules para `users/{uid}/sessions/**`

### Modified Capabilities
- None

## Approach

- **Modelos** siguen patrón Fase 1-3: `@freezed` + `json_serializable` + `@TimestampConverter()` sobre `DateTime`. Enum plain Dart + `@JsonValue('lowercase')` + extensión con `_wireMap`.
- **`Session`**: `id`, `uid`, `routineId`, `routineName` (denormalized, ADR-2), `startedAt`, `finishedAt?`, `totalVolumeKg`, `durationMin`, `status`. `id` Firestore auto-id post-create.
- **`SetLog`**: `id`, `exerciseId`, `exerciseName` (denormalized para Insights), `setNumber`, `reps`, `weightKg`, `rpe?`, `completedAt`.
- **Sub-colección** `users/{uid}/sessions/{sessionId}/setLogs/{setLogId}` (NO embedded) — atomic writes por set, lazy-load en historial. Primera sub-colección del codebase.
- **Storage at finish time**: `totalVolumeKg` + `durationMin` se calculan y persisten en `finish()`, no on-read.
- **Repo** sigue patrón `PostRepository`: `FirebaseFirestore` injection, collection getters privados, clase concreta.
- **TDD strict**: cada modelo + repo arranca con RED tests. Round-trip JSON por enum/modelo. `fake_cloud_firestore` para los 6 métodos del repo.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/workout/domain/session_status.dart` | New | Enum + extension |
| `lib/features/workout/domain/session.dart` (+ `.freezed.dart`, `.g.dart`) | New | Modelo |
| `lib/features/workout/domain/set_log.dart` (+ `.freezed.dart`, `.g.dart`) | New | Modelo |
| `lib/features/workout/data/session_repository.dart` | New | Repo Firestore |
| `lib/features/workout/application/session_providers.dart` | New | Providers Riverpod |
| `firestore.rules` | Modified | + bloques sessions/setLogs |
| `scripts/seed_sessions.js` | New (optional) | Seed contra emulator |
| `test/features/workout/{domain,data}/**` | New | SCENARIO-232+ |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Sesiones huérfanas tras crash | Med | `getActive()` las expone; Etapa 2 resuelve UX |
| N+1 en historial (Etapa 4) | Med | Lazy-load `listSetLogs` solo al expandir row |
| Primera sub-colección del codebase | Low | `fake_cloud_firestore` ya confirmado; rules flat consistentes con archivo actual |
| PR size > 400 LOC | Low | Estimado 250-300 líneas (impl + tests) |

## Rollback Plan

Revertir el PR. Borrar `lib/features/workout/{domain/session*,domain/set_log*,data/session_repository.dart,application/session_providers.dart}`. Restaurar `firestore.rules` al estado previo y `firebase deploy --only firestore:rules`. Datos seedeados en emulator/dev son descartables; producción no tiene sesiones aún.

## Dependencies

- `fake_cloud_firestore` ya en `pubspec.yaml` (Fase 1-3).
- `freezed`, `json_serializable`, `riverpod` ya en uso.
- Sin nuevas deps.

## Success Criteria

- [ ] 3 modelos compilan y pasan tests (round-trip JSON, `copyWith`, serialization)
- [ ] `SessionRepository` con 6 métodos públicos, cada uno con test verde
- [ ] `firestore.rules` actualizado y deployable (auth uid match)
- [ ] Seed script ejecutable contra emulator (opcional, no bloquea merge)
- [ ] `flutter analyze` 0 issues, `dart format .` clean, `flutter test` green
- [ ] PR mergeado a `main` (no sandbox)

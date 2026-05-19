# Proposal: Post-Workout Summary

**Change**: `post-workout-summary`
**Fase / Etapa**: Fase 4 · Etapa 3
**Branch**: `feat/post-workout-summary`
**Owner**: Dev A (Martín)
**Project**: treino
**Artifact store**: hybrid
**SCENARIO start**: 334

## Intent

Reemplazar el stub `'Resumen — próximamente'` del route `/workout/session-summary/:sessionId` con la pantalla real de resumen post-entreno: stats finales (duración, volumen, sets, PRs stub), CTA "Compartir" que publica un Post en el feed, y CTA "Listo" que vuelve al hub `/workout`. El player (PR #36/#37/#38) ya navega a este route al terminar/abandonar; consumir el contrato fijo en main sin coordination con Dev B.

## Scope

### In Scope
- `PostWorkoutSummaryScreen(sessionId: String)` — pantalla con header, 2x2 grid de stats, PRs section stub, emoji row stub y dos CTAs.
- `PostWorkoutNotifier` (`AsyncNotifier<void>`) — `shareWorkout(Session)` arma `Post` y llama `PostRepository.create`.
- `WorkoutStrings` abstract class — strings centralizados para esta feature.
- `SessionRepository.getById(uid, sessionId)` — nuevo método (~5 líneas) que retorna `Future<Session?>`.
- Reemplazo del stub en `lib/app/router.dart` para `/workout/session-summary/:sessionId`.
- Tests SCENARIO-334+: widget (golden + interacciones + snackbars + loading/error), notifier (happy + error rethrow), repo (`getById` happy + not found).

### Out of Scope
- IA buscador de ejercicios (Fase 4 Etapa 4.5 / Insights).
- Videos de ejercicios (Fase 4 Etapa 4.5).
- Bloques + super series complejos (Fase 4 Etapa 4.5).
- PRs reales con agregados (Etapa 5 — la sección queda como stub visual).
- Emoji mood persistido — render visual-only sin store.
- Privacy selector en el Post — hardcoded `PostPrivacy.friends`.
- Edit Post después de compartir — futuro scope.

## Capabilities

### New Capabilities
- `post-workout-summary`: pantalla post-entreno que muestra stats finales de la sesión y permite compartir como Post.

### Modified Capabilities
- `workout-data`: extender `SessionRepository` con `getById(uid, sessionId)` para fetch puntual.

## Approach

- Pantalla top-level (sin ShellRoute, sin bottom bar) hereda el comportamiento immersive del player.
- Carga: `ref.watch(sessionByIdProvider((uid: uid, sessionId: sessionId)))` con estados loading / error / not-found.
- Stats derivan del `Session` cargado: `durationMin`, `totalVolumeKg`, `setsCount` (derivado de `listSetLogs`).
- "Compartir": `PostWorkoutNotifier.shareWorkout(session)` arma `Post` con `authorDisplayName` desde `userProfileProvider.valueOrNull`, `routineTag` desde session, `privacy: friends`, `text` desde `WorkoutStrings.postAutoCompleteText`. Llama `PostRepository.create`.
- Success → `context.go('/workout')` + SnackBar "¡Post compartido!". Error → SnackBar de error, no navega.
- "Listo" → `context.go('/workout')` sin crear Post.
- `wasFullyCompleted == false` puede cambiar el header copy ("Sesión interrumpida" vs "BUEN ENTRENO") — decisión final en design.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/workout/presentation/post_workout_summary_screen.dart` | New | Pantalla principal. |
| `lib/features/workout/application/post_workout_notifier.dart` | New | AsyncNotifier para share. |
| `lib/features/workout/presentation/workout_strings.dart` | New | Strings centralizados. |
| `lib/features/workout/data/session_repository.dart` | Modified | + `getById(uid, sessionId)`. |
| `lib/app/router.dart` | Modified | Reemplaza stub del summary route. |
| `test/features/workout/**` | New/Modified | Widget + notifier + repo tests (SCENARIO-334+). |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Loading state UX no especificado en mockup | Med | Skeleton/loader neutro con paleta default; cubrir en design. |
| `sessionId` inválido / doc borrado | Low | Estado not-found con mensaje + botón "Volver a Entrenar". |
| `authorDisplayName` denormalization sin profile cargado | Low | Fallback `''` + null avatarUrl; test cubre caso. |
| `wasFullyCompleted` UX no decidido | Low | Resolver en design phase; default al copy actual del mockup. |
| PR size excede 400 LOC | Low | Estimado ~280-340 LOC; bajo budget. |

## Rollback Plan

Revert del único commit del feature branch — el stub original (`Center(Text('Resumen — próximamente'))`) vuelve a estar activo. Sin migraciones de datos, sin cambios en `firestore.rules`, sin cambios en `pubspec.yaml`. El player sigue navegando al mismo route — solo cambia qué renderiza.

## Dependencies

- Player ya mergeado (PR #36/#37/#38) — contrato del route `/workout/session-summary/:sessionId` fijo en main.
- `Session.dayNumber` y `Session.wasFullyCompleted` ya disponibles (PR #36).
- `PostRepository.create`, `Post`, `RoutineTag`, `PostPrivacy.friends` disponibles.

## Success Criteria

- [ ] Stub del route `/workout/session-summary/:sessionId` reemplazado con `PostWorkoutSummaryScreen`.
- [ ] `SessionRepository.getById(uid, sessionId)` agregado + provider expuesto + cubierto por test.
- [ ] Botón "Compartir" crea un Post válido en Firestore (verificado con `fake_cloud_firestore`).
- [ ] Botón "Listo" vuelve a `/workout` sin crear Post.
- [ ] Estados loading / error / not-found cubiertos por tests.
- [ ] `flutter analyze` 0 issues, `dart format .` clean, `flutter test` green (+~10-15 tests nuevos).
- [ ] Target merge a `main` vía PR estándar (single PR, sin chain).

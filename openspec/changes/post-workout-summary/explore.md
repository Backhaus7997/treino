# Explore — post-workout-summary

**Change**: `post-workout-summary`
**Fase / Etapa**: Fase 4 · Etapa 3
**Branch (target)**: `feat/post-workout-summary`
**Owner**: Dev A (Martín)
**Project**: treino
**Artifact store**: hybrid
**Engram key**: `sdd/post-workout-summary/explore`

> **Update 2026-05-19**: re-escrito post-merge de PRs #36/#37/#38 (player full). Los contratos de navegación ahora están **fijos en main** y mi etapa reemplaza el stub existente del summary route. Mi explore anterior (con `extra: session` + sub-route bajo ShellRoute) quedó obsoleto.

## Estado actual del codebase

**Data layer disponible:**
- `Session` model: `lib/features/workout/domain/session.dart:12` — ahora incluye `dayNumber: int` (default 1) y `wasFullyCompleted: bool` (default false) que agregó PR #36.
- `SessionRepository`: `lib/features/workout/data/session_repository.dart` — create/finish/listByUid/getActive/addSetLog/listSetLogs. **NO existe `getById` todavía** — mi etapa lo agrega.
- `Post` model: `lib/features/feed/domain/post.dart:13` — listo para usar.
- `RoutineTag`: `lib/features/feed/domain/routine_tag.dart:7` — `routineId` + `routineName`.
- `PostRepository.create()`: `lib/features/feed/data/post_repository.dart:18` — listo.

**Player ya mergeado (PR #36/#37/#38):**
- `SessionPlayerScreen`: `lib/features/workout/presentation/session_player_screen.dart` (720 líneas)
- `SetEntrySheet`: `lib/features/workout/presentation/widgets/set_entry_sheet.dart` (433 líneas)
- `SessionNotifier`, `SessionState`, `SessionInit`: `lib/features/workout/application/`
- `ResumeSessionModal` integrado a `HomeScreen`

**Rutas ya registradas en `lib/app/router.dart` (TOP-LEVEL, fuera de ShellRoute)**:

```
GoRoute(path: '/workout/session/:routineId/:dayNumber', ...)   // nueva sesión
GoRoute(path: '/workout/session/resume/:sessionId', ...)        // retomar
GoRoute(path: '/workout/session-summary/:sessionId',            // ← STUB
  pageBuilder: (_, __) => _noAnim(const Scaffold(
    body: Center(child: Text('Resumen — próximamente')),
  )),
),
```

**El stub del summary route es lo que mi etapa reemplaza.** Contrato fijo en main, sin necesidad de coordination con Dev B.

**Player navigation al terminar/abandonar**: el player navega a `/workout/session-summary/${session.id}` (REQ-SESSION-NAV-001 y REQ-SESSION-NAV-002 del session-player spec). Sin params extra — solo el sessionId.

**Mockup confirmado**: `docs/app-alumno/screens/detalle-rutina/post-entreno.png`
- Checkmark verde + "BUEN ENTRENO" + routineName subtitle
- 2×2 grid: DURACIÓN · VOLUMEN · SETS · PRs HOY
- Lista "PRS DE LA SESIÓN" (stub esta etapa)
- Emoji row "¿CÓMO TE SENTISTE?" (visual-only stub)
- Botones: COMPARTIR (outlined) + LISTO (filled accent)

**UI blocks reutilizables**:
- `StatTile` widget: `lib/features/workout/presentation/widgets/stat_tile.dart:9` — label+value, null → "—".
- `AppPalette.of(context)` para colores. `palette.accent` para CTA.
- `TreinoIcon.back`, `TreinoIcon.close` para back/close.
- Auth pattern: `ref.watch(authStateChangesProvider).valueOrNull?.uid ?? ''`.

**Strings**: `AuthStrings` abstract class en `lib/features/auth/presentation/auth_strings.dart`. No existe `WorkoutStrings` aún (ni siquiera lo creó PR #38).

**SCENARIO max actual**: 333. Próximo bloque: **SCENARIO-334**.

## Decisiones resueltas (alineadas al contrato del player)

1. **Navigation pattern**: path param `:sessionId` (FIJO por contrato del player). NO usar `extra: session`.
2. **Route registration**: **REEMPLAZAR el stub** en `lib/app/router.dart` que actualmente devuelve `Scaffold(...Center(Text('Resumen — próximamente')))`. Top-level, sin ShellRoute, sin bottom bar — el summary hereda el comportamiento immersive del player.
3. **Data loading**: pantalla hace lookup vía `SessionRepository.getById(uid, sessionId)`. Necesita estados loading + error.
4. **`SessionRepository.getById(uid, sessionId)`**: nuevo método del repo (~5 líneas). Retorna `Future<Session?>`. Tests con `fake_cloud_firestore`.
5. **Post creation**: `AsyncNotifier<void>` en `application/post_workout_notifier.dart`. `shareWorkout(Session session)` arma el Post y llama `PostRepository.create()`.
6. **Autocomplete text del Post**: `WorkoutStrings.postAutoCompleteText = 'Terminé mi entrenamiento de hoy'` (MVP hardcoded).
7. **PRs section**: stub vacío. Etapa 5 (Insights) wirea datos reales con agregados.
8. **Emoji mood row**: visual-only, sin persistencia. Parity cosmética.
9. **Privacy del Post**: `PostPrivacy.friends` hardcoded, sin selector.
10. **Error handling**: en error de `PostRepository.create` → SnackBar de error, NO navegar. En success → `context.go('/workout')` + SnackBar "¡Post compartido!".
11. **`wasFullyCompleted` visual handling**: si `session.wasFullyCompleted == false` (abandoned), el header puede decir "Sesión interrumpida" o similar en vez de "BUEN ENTRENO". Decisión a confirmar en design — el mockup actual no diferencia, pero semánticamente ayuda al usuario.

## Áreas afectadas

**Nuevos archivos:**
- `lib/features/workout/presentation/post_workout_summary_screen.dart`
- `lib/features/workout/application/post_workout_notifier.dart`
- `lib/features/workout/presentation/workout_strings.dart`
- `test/features/workout/presentation/post_workout_summary_screen_test.dart` (SCENARIO-334+)
- `test/features/workout/application/post_workout_notifier_test.dart`

**Modificados:**
- `lib/app/router.dart` — reemplazar el stub `GoRoute` del summary route con `PostWorkoutSummaryScreen(sessionId: sessionId)`.
- `lib/features/workout/data/session_repository.dart` — agregar `getById(uid, sessionId)` (~5 líneas).
- `test/features/workout/data/session_repository_test.dart` — tests para el nuevo `getById`.

**Sin tocar:**
- Player (mergeado por Dev B, contrato respetado)
- Domain models (`Session` ya tiene los fields que necesito)
- `firestore.rules` (read auth-only ya permite getById)
- `pubspec.yaml`

## Aproximaciones

Solo una aproximación real ahora porque el contrato del player está fijo. No hay fork técnico.

| Aproximación | Pros | Cons |
|---|---|---|
| **Path param + getById** (única opción válida) | Compatible con player (contrato fijo). Top-level immersive. Deep-linkable. | 1 Firestore read al entrar a la pantalla — aceptable (es 1 doc). |

## Riesgos

1. **Cero coordination con Dev B** — el contrato está fijo, mi PR reemplaza un stub que YA existe en main.
2. **Loading state**: la pantalla tiene que mostrar un skeleton/loader mientras `getById` resuelve. Diseño tiene que considerarlo. Mockup no lo muestra explícitamente; usar paleta neutra default.
3. **Session not found**: si `getById` retorna null (sessionId inválido o doc borrado), mostrar mensaje de error + botón "Volver a Entrenar". Edge case raro pero hay que manejarlo.
4. **`authorDisplayName` denormalization en el Post**: leer de `userProfileProvider.valueOrNull`. Fallback graceful si no cargó.
5. **PR size**: ~280-340 líneas estimadas (1 screen ~150 + 1 notifier ~50 + 1 strings file ~20 + router edit +5 + getById +5 + 2 test files ~140). LOW risk vs budget 400.
6. **`wasFullyCompleted` UX**: si abandonan, el copy del summary debería reflejarlo. Decisión final en design.

## SCENARIO start

**SCENARIO-334**

## Listo para Proposal

Sí — todas las decisiones de arquitectura resueltas, contrato del player consumido directo. Proceder a `sdd-propose`.

# Explore — historial

**Change**: `historial`
**Fase / Etapa**: Fase 4 · Etapa 4
**Branch (target)**: `feat/historial`
**Owner**: Dev A (Martín) — reasignado de Dev C
**Project**: treino
**Artifact store**: hybrid
**Engram key**: `sdd/historial/explore`

## Corrección crítica de paths en el scope brief

El brief mencionaba `docs/app-alumno/screens/detalle-rutina/historial.png` y `docs/app-alumno/screens/detalle-rutina/expandir-historial.png`. Esos archivos NO existen. Los mockups reales están en:
- `docs/app-alumno/screens/entrenamiento/historial.png`
- `docs/app-alumno/screens/entrenamiento/expandir-historial.png`

`design-decisions.md:99-104` los indexa bajo la sección Entrenamiento, no bajo Detalle Rutina.

## Estado actual del codebase

**Placeholder ya existente:**
- `lib/features/workout/workout_screen.dart:55-77` — `_HistorialSection` (private widget) renders el heading "HISTORIAL" + texto placeholder. Mi etapa reemplaza esta clase.

**Data layer disponible (sin tocar):**
- `Session`: `lib/features/workout/domain/session.dart:12` — campos relevantes: `routineName`, `dayNumber`, `startedAt`, `finishedAt?`, `totalVolumeKg`, `durationMin`, `wasFullyCompleted`, `status`.
- `SetLog`: `lib/features/workout/domain/set_log.dart:11` — `exerciseName`, `setNumber`, `reps`, `weightKg`, `rpe?`.
- `SessionRepository.listByUid(uid)` newest-first. `lib/features/workout/data/session_repository.dart:85`.
- `SessionRepository.listSetLogs(uid, sessionId)` ordered by setNumber. `lib/features/workout/data/session_repository.dart:118`.
- `SessionRepository.getById(uid, sessionId)`. `lib/features/workout/data/session_repository.dart:75`.
- `sessionsByUidProvider` (FutureProvider.family): `lib/features/workout/application/session_providers.dart:21`.
- `sessionSummaryProvider` (FutureProvider.autoDispose.family, record key {uid, sessionId}): `lib/features/workout/application/session_providers.dart:53`.
- `currentUidProvider`: `lib/features/workout/application/session_providers.dart:37`.

**UI blocks reutilizables:**
- `StatTile`: `lib/features/workout/presentation/widgets/stat_tile.dart:9`.
- `AppPalette.of(context)`, `TreinoIcon.X`, `WorkoutStrings` (extender).

**Router:**
- ShellRoute en `lib/app/router.dart:167`. Sub-routes /workout anidados en líneas 178-194.
- Rutas top-level fuera de ShellRoute: session player + session-summary (líneas 133-160).
- SCENARIO máximo = 354 (router test). Próximo bloque: SCENARIO-355.

**Date formatting:**
- No hay `intl` en pubspec.yaml. El proyecto usa helpers inline (`post_card.dart:171` — `_relativeTime`). El mockup muestra "Mié 27 nov" (abbrev. dow + day + abbrev. month en español). Implementable con Map lookup sin nueva dependencia.

## Decisiones resueltas

1. **Ubicación de Historial**: sección dentro de WorkoutScreen (reemplaza el placeholder `_HistorialSection`). NO es ruta separada dentro del ShellRoute.
2. **Historial es global (no filtrado por rutina)**: el mockup muestra sesiones de distintas rutinas sin filtro. Provider: `sessionsByUidProvider(uid)`. Path `detalle-rutina/` en el brief era incorrecto.
3. **UX de expansión**: ruta top-level `/workout/historial/:sessionId` fuera de ShellRoute (sin bottom bar). El mockup `expandir-historial.png` es una pantalla full-screen con back arrow — patrón idéntico al session player/summary, no un accordion.
4. **Campos del card en lista**: checkmark (wasFullyCompleted), routineName, fecha (Mié 27 nov), kg, min. Sin set count → sin N+1.
5. **N+1 inexistente**: sets se cargan solo al abrir el detalle (sessionSummaryProvider). La lista usa solo Session fields.
6. **Filtros/paginación**: no aplica en esta etapa. Lista plana newest-first.
7. **Empty state**: "Todavía no entrenaste." + CTA "Empezar entrenamiento". Constantes en WorkoutStrings.
8. **Filtro de status**: `listByUid` retorna todas las sesiones; filtrar client-side por `status == SessionStatus.finished`. Sin nuevo método en repo.
9. **Detalle (expandir)**: header fecha+hora+routineName, 4 StatTiles (MIN/SETS/KG/PRS), ejercicios agrupados por exerciseName con tabla SET/REPS/KG. Indicador PR = stub visual sin lógica real (Insights/Etapa 5 lo wirea). Agrupado client-side sobre setLogs ya ordenados.
10. **wasFullyCompleted**: checkmark verde = true, icono distinto (gris) = false/abandoned. Ambos visibles en la lista.
11. **Date formatting**: Map lookup inline (sin intl). Patrón ya establecido en post_card.dart.

## Áreas afectadas

**Nuevos archivos:**
- `lib/features/workout/presentation/widgets/historial_section.dart`
- `lib/features/workout/presentation/session_detail_screen.dart`
- `test/features/workout/presentation/widgets/historial_section_test.dart` (SCENARIO-355..36x)
- `test/features/workout/presentation/session_detail_screen_test.dart` (SCENARIO-36x..37x)

**Modificados:**
- `lib/features/workout/workout_screen.dart` — reemplazar `_HistorialSection` con `HistorialSection` import; eliminar clase placeholder.
- `lib/app/router.dart` — agregar `/workout/historial/:sessionId` top-level fuera de ShellRoute.
- `lib/features/workout/presentation/workout_strings.dart` — agregar constantes de historial.
- `test/features/workout/presentation/workout_screen_test.dart` — actualizar test del placeholder text.
- `test/app/router_workout_routes_test.dart` — agregar SCENARIO para la nueva ruta.

**Sin tocar:**
- Todos los domain models, SessionRepository, session_providers.dart, firestore.rules, pubspec.yaml.

## Aproximaciones

| Aproximación | Pros | Cons | Esfuerzo |
|---|---|---|---|
| **Ruta top-level `/workout/historial/:sessionId`** (recomendada) | Match exacto con mockup. Deep-linkable. Consistente con player/summary. Testeable aislado. | +1 GoRoute en router (~5 líneas). | Bajo |
| **ExpansionTile / accordion inline** | Sin cambio en router. | Incumple diseño. Contenido demasiado denso. No deep-linkeable. | Bajo (pero incorrecto) |

## Riesgos

1. **Conflict con feat/inline-set-rows (Dev B)**: ese PR agrega `updateSetLog`. No toca `listByUid`, `listSetLogs`, ni `getById`. Sin conflicto de merge.
2. **workout_screen_test.dart rompe**: test actual verifica el placeholder text `'Tus entrenamientos completados aparecerán acá.'`. Baja complejidad de fix.
3. **Agrupación de SetLogs**: riesgo bajo — exerciseName es denormalizado del modelo Exercise (constante en el seed).
4. **PR size**: estimación ~505 líneas brutas. Supera budget de 400. Candidato a chained PR: PR-A (HistorialSection + list cards) → PR-B (SessionDetailScreen + router). Decidir en proposal.
5. **Date formatting**: sin intl, implementar Map lookup. Helper candidato a `lib/core/utils/date_format_helpers.dart` o inline en el widget.

## SCENARIO start

**SCENARIO-355**

## Listo para Proposal

Sí — todas las decisiones arquitectónicas resueltas con evidencia directa en mockups reales y codebase. Punto abierto para proposal: definir si el PR se parte en 2 dado el PR size risk.

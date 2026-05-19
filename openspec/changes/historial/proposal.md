# Proposal: Historial

**Change**: `historial`
**Fase / Etapa**: Fase 4 · Etapa 4
**Branch (target)**: `feat/historial`
**Owner**: Dev A (Martín)
**Project**: treino
**Artifact store**: hybrid
**Strict TDD**: ACTIVE (`flutter test`)
**SCENARIO start**: 355
**REQ namespace**: `REQ-HIST-NNN`

## Intent

Reemplazar el placeholder `_HistorialSection` dentro de `WorkoutScreen` con la sección Historial real: una lista global newest-first de las sesiones finalizadas del usuario, y un detalle full-screen `/workout/historial/:sessionId` que muestra header (fecha + rutina), 4 StatTiles (MIN/SETS/KG/PRS) y la tabla SET/REPS/KG agrupada por ejercicio. La feature consume el data layer ya existente (`SessionRepository`, `sessionsByUidProvider`, `sessionSummaryProvider`) sin tocar dominio, repos, providers, `firestore.rules` ni `pubspec.yaml`. El indicador PR del detalle queda como stub visual — la lógica real se wirea en Insights (Etapa 5).

## Scope

### In Scope

- `HistorialSection` widget público en `lib/features/workout/presentation/widgets/historial_section.dart` que reemplaza el privado `_HistorialSection`.
- List cards con: `wasFullyCompleted` indicator (checkmark verde / icono gris), `routineName`, fecha relativa (formato "Mié 27 nov"), `totalVolumeKg` y `durationMin`. Sin set count → sin N+1.
- Filtro client-side `status == SessionStatus.finished` sobre `sessionsByUidProvider(uid)`.
- Empty state: `Todavía no entrenaste.` + CTA `Empezar entrenamiento`.
- Tap en card → `context.push('/workout/historial/:sessionId')`.
- `SessionDetailScreen(sessionId: String)` full-screen (top-level route, sin ShellRoute, sin bottom bar) en `lib/features/workout/presentation/session_detail_screen.dart`.
- Detail header: fecha + hora + `routineName` + back arrow.
- 4 StatTiles: MIN (`durationMin`), SETS (count de setLogs), KG (`totalVolumeKg`), PRS (stub visual = 0 hasta Etapa 5).
- Agrupación client-side de `List<SetLog>` por `exerciseName`, render tabla SET / REPS / KG por ejercicio.
- PR badge por ejercicio = stub visual (sin lógica de comparación con sesiones previas).
- `WorkoutStrings` extendida con constantes de historial (heading, empty, CTA, labels).
- Date formatting via Map lookup inline (NO se agrega `intl` al pubspec).
- Estados loading / error / not-found cubiertos por tests.
- Tests SCENARIO-355+: widget tests para `HistorialSection` (lista, empty, tap nav), widget tests para `SessionDetailScreen` (header, stats, agrupación, loading/error), router test para la nueva ruta.

### Out of Scope

- Filtros (por rutina, por rango de fechas) — futuro scope.
- Paginación — lista plana newest-first; volúmenes esperados en alfa son chicos.
- PRs reales (cálculo de personal records) — Etapa 5 / Insights.
- Editar / borrar sesiones del historial — sin scope en alfa.
- Compartir desde el detalle (Post auto) — ya existe en post-workout-summary.
- Métricas agregadas (gráfico de volumen semanal, racha, etc.) — Insights.
- Cambios en `SessionRepository`, `session_providers.dart`, dominio, `firestore.rules` o `pubspec.yaml`.
- Helper `lib/core/utils/date_format_helpers.dart` extraído — si el formato queda contenido en un solo widget, se mantiene inline (decidir en design).

## Approach

- **Lista**: `HistorialSection` consume `sessionsByUidProvider(currentUidProvider)`. Sobre el `AsyncValue<List<Session>>`, filtra `status == SessionStatus.finished` y renderiza cards. Si la lista filtrada es vacía → empty state. Loading → skeleton/spinner neutral con la paleta default. Error → mensaje + retry.
- **Detalle**: `SessionDetailScreen` recibe `sessionId` por path param, lee `currentUidProvider` y consume `sessionSummaryProvider(uid: uid, sessionId: sessionId)` (ya existente — retorna `(Session, List<SetLog>)`). Agrupa los `SetLog` por `exerciseName` preservando el orden de `setNumber` que ya viene del repo. Renderiza header, 4 StatTiles, y un bloque por ejercicio con tabla.
- **Router**: agregar `GoRoute('/workout/historial/:sessionId')` top-level fuera del ShellRoute, junto a las rutas de session player / session-summary. Patrón idéntico a las immersive routes ya existentes.
- **WorkoutScreen**: eliminar la clase privada `_HistorialSection`, importar y usar el widget público `HistorialSection`. Actualizar `workout_screen_test.dart` que verificaba el placeholder text.
- **Date formatting**: Map<int, String> para días de semana y meses en español abreviado (Mié, Nov, etc.). Inline en el widget que lo necesita; si aparece duplicación entre lista y detalle, extraer a un helper privado del feature.
- **PR badge stub**: render visual con valor hardcoded `0` (o flag `false`). Se documenta como dependencia explícita a Insights/Etapa 5.

## Capabilities

### New Capabilities

- `historial-ui`: presentación del historial de entrenamientos. Lista global newest-first dentro de WorkoutScreen + detalle full-screen por sessionId.

### Modified Capabilities

- `workout-data`: anotación documental — sin cambios de código. Se documenta que `sessionsByUidProvider` y `sessionSummaryProvider` son consumidos por la sección Historial. NO se agregan métodos al repo. NO se agregan providers nuevos. Filtro `status == finished` queda client-side y se anota como consumer-side concern.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/workout/presentation/widgets/historial_section.dart` | New | Widget público que reemplaza el privado. |
| `lib/features/workout/presentation/session_detail_screen.dart` | New | Pantalla full-screen del detalle. |
| `lib/features/workout/workout_screen.dart` | Modified | Elimina `_HistorialSection`, usa `HistorialSection`. |
| `lib/features/workout/presentation/workout_strings.dart` | Modified | Constantes de historial. |
| `lib/app/router.dart` | Modified | + GoRoute top-level `/workout/historial/:sessionId`. |
| `test/features/workout/presentation/widgets/historial_section_test.dart` | New | SCENARIO-355..36x. |
| `test/features/workout/presentation/session_detail_screen_test.dart` | New | SCENARIO-36x..37x. |
| `test/features/workout/presentation/workout_screen_test.dart` | Modified | Actualiza assertion del placeholder. |
| `test/app/router_workout_routes_test.dart` | Modified | SCENARIO para la nueva ruta. |

## Rollback Plan

Revert de los dos PRs en orden inverso (PR-B primero, luego PR-A). El placeholder `_HistorialSection` original vuelve activo y la ruta `/workout/historial/:sessionId` deja de existir. Sin migraciones, sin cambios en `firestore.rules`, sin cambios en `pubspec.yaml`, sin nuevas dependencias. Riesgo de rollback: nulo — la feature es 100% UI sobre data layer ya productivo.

## Chained PR Plan

Estimación bruta del explore: ~505 líneas. Excede el budget de 400. Se parte en dos PRs encadenados siguiendo el patrón usado por Dev B en el session player (PRs #36/#37/#38 split por concern).

### PR-A: `feat/historial-list` (~250 líneas)

**Scope**:
- `HistorialSection` widget público + list cards.
- `WorkoutScreen` swap (`_HistorialSection` privado → import del widget público).
- `WorkoutStrings` extensions para la lista (heading, empty, CTA, labels de fecha/kg/min).
- Date formatting Map lookup inline.
- Tests del widget de lista: render loading / empty / con sesiones / filtro `status == finished` / tap navega a `/workout/historial/:sessionId`.
- Router: GoRoute top-level `/workout/historial/:sessionId` con cuerpo stub `Center(Text('Detalle — próximamente'))` para que el tap de la lista sea testeable en aislamiento.

**Entrega**: lista funcional con navegación verificable. El detalle es stub explícito.

### PR-B: `feat/historial-detail` (~255 líneas)

**Scope**:
- `SessionDetailScreen` full-screen completo: header (back + fecha + rutina), 4 StatTiles, agrupación de SetLogs por `exerciseName`, tabla SET/REPS/KG, PR badge stub.
- Reemplazo del stub `Detalle — próximamente` en `router.dart` por el screen real.
- `WorkoutStrings` extensions para el detalle (labels de stats, PR, etc.).
- Tests del screen: loading / error / not-found / happy path con setLogs agrupados / PR stub visible / back nav.
- SCENARIO para la ruta en `router_workout_routes_test.dart`.

**Entrega**: detalle funcional + cierre de la etapa.

### Justificación del split

- Cada PR cierra valor end-to-end testeable.
- PR-A es mergeable de manera independiente sin dejar la app en estado roto: la lista funciona y el tap muestra un stub claro.
- PR-B depende mecánicamente de PR-A (rebase trivial) pero no de su lógica.
- Tamaño individual queda dentro de budget.
- Coincide con el patrón ya validado en main (Dev B / session player).

## SCENARIO Range Expected

- **PR-A**: SCENARIO-355 → ~366 (≈12 scenarios entre widget + router stub).
- **PR-B**: SCENARIO-367 → ~378 (≈12 scenarios entre detail screen + router replacement).
- **Total esperado**: SCENARIO-355 → ~378. Rango sujeto a ajuste fino en `sdd-tasks`.

## REQ Namespace

`REQ-HIST-NNN` (e.g. `REQ-HIST-001` lista renderiza sesiones, `REQ-HIST-002` filtra por `status == finished`, etc.). Numeración secuencial definida en `sdd-spec`.

## Dependencies

### Hard dependencies (must be merged before)

Ninguna. Todo el data layer requerido ya está en main:
- `Session`, `SetLog`, `SessionRepository` (con `listByUid`, `listSetLogs`, `getById`).
- `sessionsByUidProvider`, `sessionSummaryProvider`, `currentUidProvider`.
- `StatTile`, `AppPalette`, `TreinoIcon`, `WorkoutStrings`.

### Soft dependencies (parallel, no conflict)

- `feat/inline-set-rows` (Dev B): agrega `updateSetLog`. No toca `listByUid`, `listSetLogs` ni `getById`. Sin conflicto de merge.

### Downstream consumers (informativo)

- Insights (Etapa 5) wirea el cálculo real de PRs sobre el badge stub que entrega este change.

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Loading UX no especificado en mockup | Med | Skeleton/spinner neutral con paleta default — decidir en design. |
| `workout_screen_test.dart` rompe por cambio del placeholder text | High | Actualizar assertion como parte de PR-A. |
| Agrupación de SetLogs por `exerciseName` falla si el nombre cambia entre sesiones | Low | `exerciseName` es denormalizado y constante en el seed. Cubrir con test. |
| PR-A queda mergeada y PR-B se demora → stub visible en prod | Low | PR-B se abre inmediatamente al mergear PR-A. Stub copy "Detalle — próximamente" es explícito. |
| Date formatting Map lookup queda duplicado entre lista y detalle | Low | Extraer a helper privado del feature si se duplica. Decisión final en design. |
| PR-A excede 400 LOC al sumar SCENARIOs | Low | Estimado 250 con margen — monitorear en `sdd-apply`. |

## Success Criteria

- [ ] Placeholder `_HistorialSection` reemplazado por `HistorialSection` público en `WorkoutScreen`.
- [ ] Lista renderiza sesiones finalizadas newest-first con todos los campos del card.
- [ ] Empty state visible cuando no hay sesiones finalizadas; CTA navega a empezar entrenamiento.
- [ ] Tap en card abre `/workout/historial/:sessionId` full-screen (sin bottom bar).
- [ ] Detalle muestra header + 4 StatTiles + ejercicios agrupados con tabla SET/REPS/KG.
- [ ] PR badge stub visible sin lógica real (documentado como dependencia a Insights).
- [ ] `flutter analyze` 0 issues, `dart format .` clean, `flutter test` green.
- [ ] PR-A y PR-B mergeados en orden, cada uno dentro de budget de 400 LOC.
- [ ] Sin cambios en dominio, repos, providers, `firestore.rules` ni `pubspec.yaml`.

## Ready for spec + design

Sí — todas las decisiones arquitectónicas resueltas en el explore (paths corregidos, ubicación de la sección, ruta del detalle, contrato de cards, agrupación client-side, empty state, date formatting sin `intl`). Tradeoff abierto y delegado a design: si el formato de fecha se extrae a helper compartido o se mantiene inline. `sdd-spec` y `sdd-design` pueden correr en paralelo.

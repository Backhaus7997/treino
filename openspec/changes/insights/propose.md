# Proposal: insights

**Change**: Fase 4 · Etapa 5 — Pantalla de Insights (volumen + actividad semanal por grupo muscular)
**Branch**: `feat/insights`
**Owner**: Dev B (originalmente Dev C en roadmap; team reshuffle)
**Date**: 2026-05-19
**Depends on**: Etapa 1 (`SessionRepository.listByUid` + `SessionRepository.listSetLogs`) ✅ ya en main desde #34

---

## 1. Why

La app ya permite entrenar end-to-end (#37/#38), pero el usuario no tiene ninguna superficie para VER su actividad agregada. Sin Insights:

- No sabe qué grupos musculares trabajó esta semana
- No sabe cuántos sets hizo por grupo
- No tiene retroalimentación visual de progreso

Insights cierra ese gap. Es la pantalla que el usuario abre al final de la semana para ver "qué hice".

---

## 2. What

Nueva pantalla full-screen dentro del flow de Workout. Accesible desde un futuro entry point (TBD: probablemente desde Home o tab Coach — fuera de scope acá).

### Estructura visual (per `insights.png`)

```
┌─────────────────────────────────────┐
│  ←  INSIGHTS                        │  ← header con back
├─────────────────────────────────────┤
│  SEMANA · 27 OCT – 2 NOV       4/5  │  ← week strip card
│  L  M  M  J  V  S  D                │
│  ✓  ✓  ✓  30 31* 32 33              │  ← días con check / día actual outlined
├─────────────────────────────────────┤
│  MÚSCULOS DE LA SEMANA              │  ← muscle map card (silueta DIFERIDA)
│  [silueta placeholder]   PECHO   14 │
│                          ESPALDA 10 │
│                          PIERNAS 16 │  ← lista de sets por grupo
│                          BRAZOS   8 │
│                          HOMBROS  6 │
│                          CORE     4 │
├─────────────────────────────────────┤
│  VOLUMEN POR GRUPO                  │
│  PECHO    [████████░░] 14 / 16 sets │
│  ESPALDA  [██████░░░░] 10 / 16 sets │  ← progress bars con target
│  PIERNAS  [██████████] 16 / 16 sets │
│  HOMBROS  [█████░░░░░]  6 / 12 sets │
├─────────────────────────────────────┤
│  [ VOLVER ]   [  EMPEZAR (diferido)]│
└─────────────────────────────────────┘
```

### Deliverables

**Feature folder NEW**: `lib/features/insights/`

```
domain/
  muscle_group.dart           // enum/extension con las 6 categorías display + mapping
  weekly_insights.dart        // DTO inmutable con week range + sets-per-group + days trained
application/
  insights_providers.dart     // weeklyInsightsProvider (FutureProvider.autoDispose)
presentation/
  insights_screen.dart        // pantalla + private widgets (_WeekStripCard, _MusclesCard, _VolumeCard)
  widgets/
    body_silhouette_placeholder.dart   // placeholder visual reusable en home + insights
```

**Router**: agregar `/workout/insights` como ruta nested (decisión 4).

**Home card refresh (scope mínimo de Etapa 6)**: rehacer `lib/features/home/widgets/esta_semana_card.dart` para:
- Mostrar título "ESTA SEMANA"
- Mostrar `BodySilhouettePlaceholder` (el mismo widget que usa Insights — reuso)
- Tap en la card → `context.push('/workout/insights')`
- **NO** trae todavía streak real / muscle map coloreado / dots por día / stats reales — todo eso queda para Etapa 6 completa

**Test coverage**: domain pure tests + provider tests + widget tests + smoke test del tap-to-insights.

---

## 3. How

### `MuscleGroup` enum/extension

Mapping de los `muscleGroup` granulares del catálogo (chest, back, quads, glutes, etc.) a las 6 categorías display (PECHO, ESPALDA, PIERNAS, BRAZOS, HOMBROS, CORE).

```dart
enum MuscleGroupDisplay { pecho, espalda, piernas, brazos, hombros, core }

extension MuscleGroupMapping on String {
  MuscleGroupDisplay? toDisplayGroup() => switch (toLowerCase()) {
    'chest' => MuscleGroupDisplay.pecho,
    'back' => MuscleGroupDisplay.espalda,
    'shoulders' => MuscleGroupDisplay.hombros,
    'quads' || 'hamstrings' || 'glutes' || 'calves' => MuscleGroupDisplay.piernas,
    'biceps' || 'triceps' => MuscleGroupDisplay.brazos,
    'core' => MuscleGroupDisplay.core,
    _ => null,  // unknown muscle group → skip (defensivo)
  };
}
```

### `WeeklyInsights` DTO

```dart
@immutable
class WeeklyInsights {
  final DateTime weekStart;  // lunes 00:00 local
  final DateTime weekEnd;    // domingo 23:59 local
  final List<bool> daysTrained; // longitud 7: lun..dom — true si hubo al menos 1 sesión
  final int sessionsCount;
  final int plannedSessionsCount;  // para "4/5" — viene del routine asignado, default 5
  final Map<MuscleGroupDisplay, int> setsByGroup;     // sets logueados esta semana
  final Map<MuscleGroupDisplay, int> targetByGroup;   // sets target esta semana (del routine)
}
```

### `weeklyInsightsProvider`

```dart
final weeklyInsightsProvider = FutureProvider.autoDispose<WeeklyInsights?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;

  final repo = ref.read(sessionRepositoryProvider);
  final exerciseRepo = ref.read(exerciseRepositoryProvider);

  // 1. Calcular semana actual (lunes-domingo)
  final now = DateTime.now();
  final weekStart = _mondayOf(now);
  final weekEnd = weekStart.add(Duration(days: 7));

  // 2. Sessions de esta semana
  final allSessions = await repo.listByUid(uid);
  final weekSessions = allSessions.where((s) =>
    s.startedAt.isAfter(weekStart) &&
    s.startedAt.isBefore(weekEnd) &&
    s.status == SessionStatus.finished
  ).toList();

  // 3. Días entrenados (boolean por día)
  final daysTrained = List<bool>.filled(7, false);
  for (final s in weekSessions) {
    final dayIndex = s.startedAt.toLocal().weekday - 1;  // 0=lun..6=dom
    daysTrained[dayIndex] = true;
  }

  // 4. Sets por grupo (de los SetLogs de la semana)
  final exercises = await exerciseRepo.listAll();
  final byId = {for (final e in exercises) e.id: e};
  final setsByGroup = <MuscleGroupDisplay, int>{};
  for (final s in weekSessions) {
    final logs = await repo.listSetLogs(uid: uid, sessionId: s.id);
    for (final log in logs) {
      final exercise = byId[log.exerciseId];
      final group = exercise?.muscleGroup.toDisplayGroup();
      if (group != null) {
        setsByGroup[group] = (setsByGroup[group] ?? 0) + 1;
      }
    }
  }

  // 5. Target por grupo (del routine assigned al user)
  // Si no hay routine asignado → targetByGroup = vacío y las progress bars
  //                              quedan en estado "sin objetivo".
  // Si hay routine → sumar targetSets por slot, agrupado por muscleGroup,
  //                  multiplicado por días planeados (cuántas veces se hace el slot por semana).
  //                  POR SIMPLICIDAD INICIAL: target = suma de slot.targetSets en TODOS
  //                  los routine.days (semana entera = 1 ciclo de la rutina).
  // ... (logic detallada en design.md / código)

  return WeeklyInsights(...);
});
```

### Pantalla (`InsightsScreen`)

`ConsumerWidget` que `ref.watch(weeklyInsightsProvider)`:
- `loading` → Center con CircularProgressIndicator
- `error` → mensaje "No pudimos cargar tus insights" + retry
- `data(null)` → estado vacío "Empezá a entrenar para ver tus insights"
- `data(insights)` → 3 cards apiladas en scroll

### Private widgets

- `_WeekStripCard(insights)`: header del rango de semana + tira de 7 chips
- `_MusclesCard(insights)`: placeholder rectangular para la silueta + lista right-side con sets por grupo
- `_VolumeBarCard(insights)`: lista de progress bars con `LinearProgressIndicator`

### Botones bottom

- `VOLVER`: `OutlinedButton` → `context.go('/home')` o `context.pop()` según from-context
- `EMPEZAR`: diferido — placeholder con `Opacity(0.4)` y `onPressed: null` para mantener visual parity con mockup, pero sin función

---

## 4. Trade-offs aceptados (5 decisiones lockeadas)

| # | Decisión | Rationale |
|---|---|---|
| 1 | **Silueta muscular = placeholder (Container con texto "💪")** este PR | No tenemos asset SVG con regiones nombradas. Hacerlo en este PR demora 1-2 días. Mejor un placeholder visual con la lista de sets a la derecha y revisitar en iteración polish. |
| 2 | **Semana = lunes a domingo, hora local del dispositivo** | Convención latinoamericana. `DateTime.weekday` ya retorna 1=lun..7=dom. |
| 3 | **Mapping muscleGroup granular → display fijo en código** | Los 10 grupos granulares del catálogo (chest/back/quads/etc.) no van a cambiar pronto. Un switch en una extension es suficiente, no merece tabla en Firestore. |
| 4 | **Ruta NESTED dentro de /workout** (`/workout/insights`) | Insights es accesible desde el flow de Workout y Home. Ponerlo nested mantiene la jerarquía. Top-level innecesario porque no es immersive (sí tiene bottom bar). |
| 5 | **`plannedSessionsCount` = 5 hardcoded** este PR | El "4/5" del mockup implica que el user tiene un plan de 5 días/semana. Hardcoded en 5 hasta que Coach (Fase 5) configure plannedDays por usuario. Decisión transparente. |

---

## 5. Out of scope

| Item | Por qué afuera |
|---|---|
| Silueta muscular SVG coloreable | Requiere asset propio. Polish iteration. |
| Botón EMPEZAR funcional (shortcut a iniciar sesión) | No es core de Insights. Wire después si el usuario lo pide. |
| Vista mensual / cambio de semana | Mockup solo muestra "semana actual". Iteración futura. |
| Racha de días consecutivos | Roadmap lo menciona pero el mockup no lo muestra. Diferido. |
| PRs por ejercicio | Idem — roadmap sí, mockup no. |
| Volumen en kg | Mockup mide por SETS no por kg. Volumen en kg sería iteración futura. |
| Comparación con semanas anteriores | Out — solo semana actual este PR. |
| Server-side aggregation | Pendiente App Check + Cloud Functions (Fase 6). Client-side agg suficiente para usuarios MVP. |

---

## 6. Success criteria

Cada uno testeable.

- [ ] Pantalla accesible vía `/workout/insights`
- [ ] Week strip muestra rango de fecha correcto (lun-dom de la semana actual) + chips con ✓ en días entrenados
- [ ] Día actual outlined con accent border en la tira
- [ ] Card "MÚSCULOS DE LA SEMANA" muestra placeholder + lista de 6 grupos con conteos correctos
- [ ] Card "VOLUMEN POR GRUPO" muestra progress bar por grupo con `done/target`
- [ ] Botón VOLVER navega de vuelta (pop o go a /home)
- [ ] Estado vacío cuando el usuario nunca entrenó: mensaje + sin cards de stats
- [ ] `flutter analyze` 0 issues
- [ ] Tests: domain (mapping), provider (agregados con mocks de repo), widget (3 cards en data state)
- [ ] Theme: `AppPalette.of(context)` en todo; íconos via `TreinoIcon.X`; spacing en `{8,12,14,18,20}`

---

## 7. Risks

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | Si Dev A introduce `recentSessionsProvider` en Etapa 4, podríamos duplicar lógica | Por ahora cada feature define lo suyo. Al mergear Etapa 4 evaluamos si vale unificar en una refactor PR. |
| 2 | `listSetLogs` por sesión = N queries Firestore para una semana con N entrenos | Acceptable hasta que App Check + Cloud Functions agreguen aggregation server-side (Fase 6). 5-7 queries por semana es ok. |
| 3 | Sin routine asignado el targetByGroup queda vacío → progress bars sin barra | Estado válido — la card simplemente no se muestra (o muestra "Asignate una rutina" hint). Decisión 1 polish. |
| 4 | Día actual outlined puede saltar a la columna equivocada si timezone difiere | Usar `DateTime.now().toLocal()` consistentemente. Test cubre. |

---

## 8. LOC estimate

| Bucket | LOC aprox |
|---|---|
| `domain/muscle_group.dart` | ~50 |
| `domain/weekly_insights.dart` | ~70 |
| `application/insights_providers.dart` | ~130 |
| `presentation/insights_screen.dart` (screen + 3 private cards) | ~280 |
| Router addition | ~15 |
| Tests (domain + provider + widget) | ~350 |
| **Total** | **~895** |

Dentro del budget de 400 LOC producción (~545 production). Test LOC empuja a single-PR con `size:exception` o split en 2 chained (domain+provider PR1 + UI PR2).

Recomendación inicial: **single PR** con `size:exception` justificado por cohesión interna. Si en el camino se ve que se infla, splitear.

# Tasks — insights

**Change**: `insights`
**Fase / Etapa**: Fase 4 · Etapa 5
**Date**: 2026-05-19

Estilo: SDD lite. Sin TDD estricto pero cada bloque cierra con `flutter analyze` + tests verdes antes de avanzar.

---

## 1. Domain

- [ ] **TASK-101**: `lib/features/insights/domain/muscle_group.dart`
  - Enum `MuscleGroupDisplay` con 6 valores: pecho, espalda, piernas, brazos, hombros, core
  - Extension `MuscleGroupMapping on String` con `toDisplayGroup()` switch para mapear los 10 valores granulares del catálogo
  - Helper `displayLabel` (PECHO, ESPALDA, …)

- [ ] **TASK-102**: `lib/features/insights/domain/weekly_insights.dart`
  - Clase inmutable con: `weekStart`, `weekEnd`, `daysTrained: List<bool>` (longitud 7), `sessionsCount`, `plannedSessionsCount`, `setsByGroup: Map<MuscleGroupDisplay, int>`, `targetByGroup: Map<MuscleGroupDisplay, int>`
  - Manual `==`, `hashCode`, `copyWith`

- [ ] **TASK-103**: tests para ambos
  - `test/features/insights/domain/muscle_group_test.dart`
  - `test/features/insights/domain/weekly_insights_test.dart`

## 2. Provider

- [ ] **TASK-201**: `lib/features/insights/application/insights_providers.dart`
  - `weeklyInsightsProvider: FutureProvider.autoDispose<WeeklyInsights?>`
  - Lee `currentUidProvider`, `sessionRepositoryProvider`, `exerciseRepositoryProvider`, `userProfileProvider` (para `currentRoutineId` cuando esté disponible — fallback a `null`)
  - Calcula semana actual (lunes-domingo, hora local)
  - Filtra sessions por week range + status finished
  - Agrupa SetLogs por muscleGroup → setsByGroup
  - Calcula targetByGroup desde routine asignado (o vacío si no hay)
  - `plannedSessionsCount` = 5 (hardcoded — decisión 5)

- [ ] **TASK-202**: tests del provider con mocks de repositorios
  - `test/features/insights/application/insights_providers_test.dart`

## 3. Body silhouette placeholder

- [ ] **TASK-301**: `lib/features/insights/presentation/widgets/body_silhouette_placeholder.dart`
  - StatelessWidget con `width`/`height` requeridos
  - Visual: un container con `palette.bg`, border `palette.border`, ícono o emoji centrado (💪 o `TreinoIcon.tabWorkout` grande)
  - Reusable entre InsightsScreen y EstaSemanaCard

## 4. Insights screen

- [ ] **TASK-401**: `lib/features/insights/presentation/insights_screen.dart`
  - `ConsumerWidget` que `ref.watch(weeklyInsightsProvider)`
  - Header con back + título "INSIGHTS"
  - 3 cards en ListView (con ClampingScrollPhysics + overscroll false como aprendimos en session-player):
    - `_WeekStripCard(insights)` — rango fecha + tira L-D con chips
    - `_MusclesCard(insights)` — `BodySilhouettePlaceholder` + lista right con sets por grupo
    - `_VolumeBarCard(insights)` — progress bars por grupo con `done/target`
  - Botón VOLVER al final → `context.pop()` con fallback `context.go('/home')`
  - Estados async: loading (spinner mint), error (texto + retry), data null (empty state "Empezá a entrenar")

- [ ] **TASK-402**: widget tests
  - `test/features/insights/presentation/insights_screen_test.dart`
  - Cubre: render 3 estados async, render 3 cards en data, week strip muestra día actual outlined, tap en VOLVER navega

## 5. Router

- [ ] **TASK-501**: agregar ruta `/workout/insights` en `lib/app/router.dart`
  - NESTED dentro del ShellRoute > /workout (bottom bar visible)
  - `pageBuilder` con `_noAnim` y `InsightsScreen()`
  - Auth-gated via `authRedirect` (ya cubre todo /workout)

## 6. Home wire-up (Esta Semana → Insights)

- [ ] **TASK-601**: rehacer `lib/features/home/widgets/esta_semana_card.dart`
  - Sigue siendo StatelessWidget
  - Layout: título "ESTA SEMANA" + `BodySilhouettePlaceholder` + tap en toda la card → `context.push('/workout/insights')`
  - **No** trae todavía streak / muscle map / stats reales (Etapa 6 completa lo va a llenar)

- [ ] **TASK-602**: actualizar `test/features/home/widgets/esta_semana_card_test.dart` (si existe) o agregar widget test que verifique el tap-to-push

## 7. Final gate

- [ ] **TASK-701**: `flutter analyze` 0 issues
- [ ] **TASK-702**: `dart format . --set-exit-if-changed` exits 0
- [ ] **TASK-703**: `flutter test` full suite verde
- [ ] **TASK-704**: smoke manual (vos) — entrar al home, tap en card, ver insights con datos reales/empty, volver

# Tasks: coach-hub-hoy-web (W4.1 — Coach Hub WEB dashboard "Hoy")

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | PR1 ~350, PR2 ~230, PR3 ~280 net (−600 deletions offset) |
| 400-line budget risk | High (total gross; each PR ≤ 400) |
| Chained PRs recommended | Yes |
| Suggested split | PR1 → PR2 → PR3 (feature-branch-chain) |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | dashboardDayCounts lift + scaffold + banner + welcome card + KPI strip | PR1 | Base = feature/coach-hub-hoy-web; mobile must stay green |
| 2 | Right column: próximas sesiones + vencimientos + inactivos placeholder | PR2 | Base = PR1 branch |
| 3 | Left column pendientes + adherencia placeholder + remove old lists + test migration | PR3 | Base = PR2 branch; net-negative diff |

---

## PR1 — dashboardDayCounts lift + scaffold + welcome card + banner + KPI strip

> REQ-HOY-01, REQ-HOY-03, REQ-HOY-04, REQ-HOY-05, REQ-HOY-10, REQ-HOY-11
> Breakpoint: `constraints.maxWidth >= 900 && constraints.maxHeight.isFinite` (mirrors agenda_web_screen.dart:107-108)

### Phase 1 — Shared Code Lift (foundation; mobile must not regress)

- [ ] 1.1 **RED** — Add a direct-import test in `test/features/coach/application/dashboard_day_counts_test.dart` importing `DashboardDayCounts` + `dashboardDayCounts` from `lib/features/coach/application/dashboard_day_counts.dart`; assert the same cases as `trainer_dashboard_day_counts_test.dart`. Confirm it FAILS (file not created yet). Covers SCENARIO-HOY-04A (sesiones hoy count).
- [ ] 1.2 **GREEN** — Create `lib/features/coach/application/dashboard_day_counts.dart` exporting `DashboardDayCounts({pending, done, cancelled})` and `dashboardDayCounts(List<Appointment> all, DateTime now)` with inlined `_isSameLocalDay`. Exact logic copied from `trainer_dashboard_tab.dart` lines ~1537-1578.
- [ ] 1.3 **MODIFY** `lib/features/coach/presentation/trainer_dashboard_tab.dart` — delete the local `DashboardDayCounts`, `dashboardDayCounts`, and `_isSameLocalDay` declarations (lines ~1537-1578, ~1649-1651); add `import` from the new file; add `export 'package:treino/features/coach/application/dashboard_day_counts.dart' show dashboardDayCounts, DashboardDayCounts;` so `trainer_dashboard_day_counts_test.dart` (which imports via trainer_dashboard_tab.dart) keeps compiling unchanged.
- [ ] 1.4 **GATE** — `flutter test test/features/coach/ --name dashboardDayCounts` must be green (both test files pass). `flutter analyze lib/features/coach/application/dashboard_day_counts.dart lib/features/coach/presentation/trainer_dashboard_tab.dart` → 0 issues.

### Phase 2 — AppL10n Keys (PR1 strings)

- [ ] 2.1 Add new keys to `lib/l10n/intl_es_AR.arb` (and `intl_es.arb`, `intl_en.arb`):
  - `dashboardGreeting` ("BUENAS, {name}"), `dashboardDate` (date label key)
  - `dashboardSummary` ("Tenés {sessions} sesiones hoy, {pending} para revisar, {overdue} pagos pendientes")
  - `dashboardQuickActionAlumno` ("+ Nuevo alumno"), `dashboardQuickActionRutina` ("Crear rutina"), `dashboardQuickActionMensajes` ("Mensajes ({n})")
  - `dashboardQuickActionImportar` ("IMPORTAR PLAN DESDE EXCEL")
  - `dashboardAlertBannerPlaceholder` ("Próximamente: resumen de atención")
  - `dashboardKpiActivos` ("Alumnos activos"), `dashboardKpiIngreso` ("Ingreso del mes"), `dashboardKpiAdherencia` ("Adherencia promedio"), `dashboardKpiPorCobrar` ("Por cobrar")
  - `dashboardKpiAdherenciaPlaceholder` ("—"), `dashboardPlaceholderSoon` ("Próximamente"), `dashboardAdherenceRingPlaceholder` ("--")
- [ ] 2.2 Run `flutter gen-l10n` (or equivalent) and confirm generated `AppL10n` compiles — 0 analyze issues.

### Phase 3 — Layout Scaffold + Banner + Welcome Card + KPI Strip (widget implementation)

- [ ] 3.1 **RED** — In `test/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen_test.dart` add a test group `'PR1 — layout + banner + welcome + KPI'` with failing tests for:
  - SCENARIO-HOY-01A: wide (≥900) renders two `Expanded` columns (find by key or structure).
  - SCENARIO-HOY-01B: narrow (<900) renders single stacked column.
  - SCENARIO-HOY-03A: `_AlertBanner` visible, contains `dashboardAlertBannerPlaceholder` text, no crash.
  - SCENARIO-HOY-04A: greeting shows "BUENAS, JOACO" given displayName "Joaco Trainer"; summary line correct counts.
  - SCENARIO-HOY-04B: adherence ring shows "--".
  - SCENARIO-HOY-04C: Mensajes label shows "(7)" given `totalUnreadCountProvider` = 7.
  - SCENARIO-HOY-05A: Alumnos activos tile = 28 given 28 active links.
  - SCENARIO-HOY-05B: Ingreso tile shows $412.000.
  - SCENARIO-HOY-05C: Adherencia tile = "—".
  - SCENARIO-HOY-05D: Por cobrar tile shows $86.000 + "(3 vencimientos)".
  - SCENARIO-HOY-05E: KPI tile in loading state renders CircularProgressIndicator (or equivalent).
  - SCENARIO-HOY-10A: tapping "IMPORTAR PLAN DESDE EXCEL" calls `context.push('/upload-plan')`.
  All these must FAIL before implementation.
- [ ] 3.2 **GREEN** — Rewrite `CoachHubDashboardScreen.build` in `lib/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart`:
  - `Center > ConstrainedBox(maxWidth: 1280) > SingleChildScrollView`
  - Finite-height guard per agenda_web_screen.dart:107-108.
  - Add `_AlertBanner` (stateless `ConsumerWidget`): styled `AppPalette.of(context).bgCard` container, `AppL10n.of(context).dashboardAlertBannerPlaceholder` text, no notification provider call.
  - Add `_WelcomeCard` (`ConsumerWidget`): reads `userProfileProvider.displayName` (split, take first token, `.toUpperCase()`), `trainerAppointmentsStreamProvider(key)` + `dashboardDayCounts().pending` for today-count, `trainerLinksStreamProvider.where(pending).length` for M, `pagosBucketsProvider.vencidos.length` for K, `totalUnreadCountProvider` for messages badge. Quick actions: Nuevo alumno (`/alumnos`), Crear rutina (`/upload-plan`), Mensajes(N), Importar plan (`/upload-plan`). `_AdherenceRing` placeholder shows "--". All strings via AppL10n. No Scaffold/SafeArea.
  - Add file-private `_PlaceholderCard({required String title, required String hint})`: bordered bgCard + muted title + "Próximamente" hint.
  - Add `_KpiStrip` (`ConsumerWidget`) wrapping 4 `KpiTile` reused from `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_kpi_row.dart`. Tile 1: Alumnos activos (trainerLinksStreamProvider.where(active).length). Tile 2: Ingreso del mes (pagosBucketsProvider.pagados filter by monthStart UTC, sum amountArs). Tile 3: Adherencia = `_PlaceholderCard` or KpiTile with "--". Tile 4: Por cobrar (vencidos count + fold amountArs). Each tile handles loading/error. NO delta values on any tile.
  - Add `LayoutBuilder` body: wide ≥900 → `Row([Expanded(flex:55, LEFT_PLACEHOLDER), Expanded(flex:45, RIGHT_PLACEHOLDER)])` — LEFT and RIGHT are `_PlaceholderCard` stubs for PR1 (real content lands in PR2 and PR3). Narrow → `Column` with both placeholders.
- [ ] 3.3 **GATE** — `flutter test test/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen_test.dart` (PR1 group) green. `flutter analyze lib/features/coach_hub/presentation/sections/dashboard/` → 0 issues. `dart format .` → no diffs.

### Phase 4 — In-shell regression guard (PR1 update)

- [ ] 4.1 `coach_hub_dashboard_in_shell_test.dart`: Add overrides for new providers needed (e.g. `pagosBucketsProvider`, `totalUnreadCountProvider`, `userProfileProvider` if not already overridden). Confirm existing assertions still pass: `find.byType(Scaffold)` findsOneWidget, no brand header. Do NOT change the `find.text('IMPORTAR PLAN DESDE EXCEL')` assertion — it must already pass because the CTA is now in the welcome card quick actions.
- [ ] 4.2 Run full in-shell test: `flutter test test/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_in_shell_test.dart` → green.

---

## PR2 — Right Column (real lists)

> REQ-HOY-07, REQ-HOY-08, REQ-HOY-09, REQ-HOY-11
> Base branch: PR1 branch.

### Phase 5 — AppL10n Keys (PR2 strings)

- [ ] 5.1 Add keys to all `.arb` files:
  - `dashboardProximasSesionesTitle` ("Próximas sesiones"), `dashboardProximasEmpty` ("Sin sesiones próximas")
  - `dashboardVencimientosTitle` ("Vencimientos — 7 días"), `dashboardVencimientosEmpty` ("Sin vencimientos"), `dashboardVencimientosVerTodos` ("VER TODOS LOS PAGOS")
  - `dashboardInactivosTitle` ("Alumnos inactivos")
  - Run `flutter gen-l10n`, confirm 0 analyze issues.

### Phase 6 — Right Column Widget Implementation

- [ ] 6.1 **RED** — In `coach_hub_dashboard_screen_test.dart` add group `'PR2 — right column'` with failing tests for:
  - SCENARIO-HOY-07A: `_ProximasSesiones` shows first 4 upcoming confirmed appointments (time HH:MM, athlete name, modality).
  - SCENARIO-HOY-07B: empty state message visible when no upcoming sessions.
  - SCENARIO-HOY-08A: `_Vencimientos7d` shows 4 entries with athlete name + overdue indicator.
  - SCENARIO-HOY-08B: empty state message visible when vencidos is empty.
  - SCENARIO-HOY-09A: `_InactivosSection` shows placeholder text, no provider call.
- [ ] 6.2 **GREEN** — Implement in `coach_hub_dashboard_screen.dart`:
  - `_ProximasSesiones` (`ConsumerWidget`): reads `trainerAppointmentsStreamProvider(key)` → filter `status == confirmed && startsAt.isAfter(now)` → sort by startsAt asc → take(4). Each row: `Text(HH:MM)`, athlete name lookup, modality label. Loading state: CircularProgressIndicator. Empty state: `AppL10n.of(context).dashboardProximasEmpty`. No Scaffold/SafeArea.
  - `_Vencimientos7d` (`ConsumerWidget`): reads `pagosBucketsProvider.vencidos`. Each row: athlete name + overdue indicator `TreinoIcon`. "VER TODOS LOS PAGOS" `TextButton` navigating to pagos route. Loading/empty states. No Scaffold/SafeArea.
  - `_InactivosSection`: `_PlaceholderCard(title: l10n.dashboardInactivosTitle, hint: l10n.dashboardPlaceholderSoon)`. No provider call.
  - Replace the RIGHT column `_PlaceholderCard` stub from Phase 3 with `Column([_ProximasSesiones, _Vencimientos7d, _InactivosSection])`.
- [ ] 6.3 **GATE** — `flutter test test/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen_test.dart` (PR2 group) green. `flutter analyze lib/features/coach_hub/presentation/sections/dashboard/` → 0 issues. `dart format .` → no diffs.

---

## PR3 — Left Column + Pendientes + Adherencia + Remove Old Lists + Test Migration

> REQ-HOY-02, REQ-HOY-06, REQ-HOY-11
> Base branch: PR2 branch. Net-negative diff (~−600 deletions, +280 additions).

### Phase 7 — AppL10n Keys (PR3 strings)

- [ ] 7.1 Add keys to all `.arb` files:
  - `dashboardPendientesTitle` ("Pendientes de HOY")
  - `dashboardAdherenceChartTitle` ("ADHERENCIA · ÚLTIMOS 28 DÍAS")
  - Run `flutter gen-l10n`, confirm 0 analyze issues.

### Phase 8 — Left Column Widget Implementation

- [ ] 8.1 **RED** — In `coach_hub_dashboard_screen_test.dart` add group `'PR3 — left column + solicitudes'` with failing tests for:
  - SCENARIO-HOY-06A: tapping `accept_{id}` calls `TrainerLinkRepository.accept()` and `logLinkAccepted`; solicitud disappears after stream refresh.
  - SCENARIO-HOY-06B: tapping `decline_{id}` shows `showDialog`; `TrainerLinkRepository.decline()` called only after confirm.
  - SCENARIO-HOY-06C: placeholder text visible in place of notification board; no aggregation provider called.
  - SCENARIO-HOY-06D: adherencia section renders placeholder text "Próximamente"; no time-series provider called.
  - SCENARIO-HOY-02A: no `find.text('ACTIVOS')` / `find.text('PAUSADOS')` / `find.text('HISTORIAL')`; no FilterChip present.
- [ ] 8.2 **GREEN** — Implement in `coach_hub_dashboard_screen.dart`:
  - `_PendingTodaySection` (`ConsumerWidget`): section header `dashboardPendientesTitle`. Contains existing `_PendingRequestsList` and `_PendingRequestTile` lifted UNCHANGED — preserve widget keys `pending_request_{id}`, `accept_{id}`, `decline_{id}`. Preserve `_confirmAction`, busy-guard, `logLinkAccepted`, accept/decline mutations. Placeholder card for deferred notification board above the list (SCENARIO-HOY-06C). No Scaffold/SafeArea.
  - `_AdherenceChart`: `_PlaceholderCard(title: l10n.dashboardAdherenceChartTitle, hint: l10n.dashboardPlaceholderSoon)`. No provider call. Covers SCENARIO-HOY-06D.
  - Replace the LEFT column `_PlaceholderCard` stub from Phase 3 with `Column([_PendingTodaySection, _AdherenceChart])`.
- [ ] 8.3 **REMOVE** from `coach_hub_dashboard_screen.dart` — delete all of: `_statusFilterProvider`, `_FilterChipRow`, `_ActiveStudentsList`, `_PausedStudentsList`, `_HistorialList`, `_StudentTile`, `_PausedStudentTile`, `_TerminatedStudentTile`, `_SectionLabel`, `_reasonDisplay`, `_formatPauseDate`. Remove any now-unused imports these widgets depended on exclusively. Covers REQ-HOY-02.

### Phase 9 — Test Migration

- [ ] 9.1 In `coach_hub_dashboard_screen_test.dart` **DELETE** all test cases asserting presence of: ACTIVOS/PAUSADOS/HISTORIAL list headers or FilterChip, Pausar/Terminar/Reanudar action buttons, `_statusFilterProvider`, `_StudentTile`, `_PausedStudentTile`, `_TerminatedStudentTile`. Count: confirm ~10 test cases removed.
- [ ] 9.2 Confirm the accept/decline test cases (now in group `'PR3 — left column + solicitudes'`) pass and their widget keys (`accept_`, `decline_`, `pending_request_`) are still found.
- [ ] 9.3 In `coach_hub_dashboard_in_shell_test.dart` — the `find.text('IMPORTAR PLAN DESDE EXCEL')` assertion was already updated in Phase 4. Confirm it still passes after PR3 changes. No other in-shell assertion needs changing.

### Phase 10 — Final Gate (full suite)

- [ ] 10.1 Run `flutter test test/features/coach_hub/presentation/sections/dashboard/` (all files in the group) → all green.
- [ ] 10.2 Run `flutter test test/features/coach/` → `trainer_dashboard_day_counts_test.dart` still green (re-export intact).
- [ ] 10.3 Run `flutter analyze` from repo root → 0 issues (SCENARIO-HOY-11B).
- [ ] 10.4 Run `dart format .` → no diffs.
- [ ] 10.5 Confirm no hardcoded es-AR strings remain in `coach_hub_dashboard_screen.dart` (SCENARIO-HOY-11A): `rg "['\"]Tenés|['\"]Alumnos|['\"]Próximas|['\"]Pendientes" lib/features/coach_hub/presentation/sections/dashboard/` → 0 matches.

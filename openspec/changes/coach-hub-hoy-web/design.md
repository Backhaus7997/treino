# Design: coach-hub-hoy-web (W4.1 — Coach Hub WEB dashboard "Hoy")

## Technical Approach

In-place rewrite of `CoachHubDashboardScreen.build` into an adaptive KPI dashboard matching the mockup. Presentation-only reuse: every data-ready section wires an EXISTING provider; the 3 gaps (adherencia aggregate/ring/chart, alumnos inactivos, rich notification board) render a shared `_PlaceholderCard`. Only ONE shared-code change: lift `dashboardDayCounts` + `_isSameLocalDay` out of `trainer_dashboard_tab.dart` (mobile) into a pure `lib/features/coach/application/dashboard_day_counts.dart` so mobile + web share it. Section contract preserved (ADR-CHW-005: no Scaffold/SafeArea, `AppPalette`, `TreinoIcon`, `showDialog`, AppL10n). Breakpoint mirrors `agenda_web_screen.dart` (`maxWidth >= 900 && maxHeight.isFinite`).

## Widget Tree (top → bottom)

```
CoachHubDashboardScreen (ConsumerWidget, no Scaffold)
└ Center > ConstrainedBox(maxWidth: 1280) > SingleChildScrollView
  ├ _AlertBanner              PLACEHOLDER  "N alumnos necesitan atención" + Revisar todo (disabled)
  ├ _WelcomeCard             REAL greeting + adherencia ring PLACEHOLDER
  │   ├ date line            DateTime.now (local _formatHeaderDate style)
  │   ├ "BUENAS, {NAME}"      userProfileProvider.displayName
  │   ├ subtitle             sesiones hoy (real) · "N cosas para revisar" (pending real) · pagos pendientes (real)
  │   ├ QuickActions Row     [+ Nuevo alumno→/alumnos] [Crear rutina→/upload-plan REAL] [Mensajes(N) totalUnreadCountProvider]
  │   └ _AdherenceRing        PLACEHOLDER 84%
  ├ _KpiStrip (Wrap/Row of 4 KpiTile — reused from pagos_kpi_row.dart)
  │   ├ Alumnos activos        trainerLinksStreamProvider.where(active).length          REAL
  │   ├ Ingreso del mes        pagosBucketsProvider.pagados paid-this-month sum          REAL
  │   ├ Adherencia promedio    PLACEHOLDER "—"
  │   └ Por cobrar             pagosBucketsProvider.vencidos count + amountArs           REAL
  └ LayoutBuilder → wide(≥900): Row[ Left 55% | Right 45% ]; narrow: Column stacked
    ├ LEFT
    │   ├ _PendingTodaySection  header "PENDIENTES DE HOY" + REAL _PendingRequestsList (preserved verbatim)
    │   └ _AdherenceChart       PLACEHOLDER "ADHERENCIA · ÚLTIMOS 28 DÍAS"
    └ RIGHT
        ├ _ProximasSesiones     trainerAppointmentsStreamProvider confirmed&&future, take(3)  REAL
        ├ _Vencimientos7d       pagosBucketsProvider.vencidos                                  REAL
        └ _InactivosSection     PLACEHOLDER "N alumnos inactivos"
```

## Data Source Map (each confirmed vs source)

| Section | Provider / source | Status |
|---|---|---|
| Greeting name | `userProfileProvider` (`user_providers.dart:19`) → `.valueOrNull?.displayName` | REAL |
| Mensajes (N) | `totalUnreadCountProvider` (`chat_providers.dart:127`, plain `int`) | REAL |
| Sesiones hoy | `trainerAppointmentsStreamProvider(key)` + `dashboardDayCounts().pending` | REAL (needs lift) |
| Próximas sesiones | same stream → `status==confirmed && startsAt.isAfter(now)` sorted, `.take(3)` | REAL |
| Alumnos activos | `trainerLinksStreamProvider.where(active).length` | REAL |
| Por cobrar / Vencimientos 7d | `pagosBucketsProvider.vencidos` (count + `fold amountArs`) | REAL |
| Ingreso del mes | reuse PagosKpiRow logic: `pagados` where `(paidAt??createdAt).toUtc() >= monthStart` sum | REAL |
| trainerId | `currentUidProvider` (`session_providers.dart`, as agenda/mobile do) | REAL |
| Adherencia tile+ring+28d chart | none | PLACEHOLDER |
| Alumnos inactivos | none (no `lastSessionAt`) | PLACEHOLDER |
| Rich notification rows (msg/report/fotos) | none (new notification domain) | PLACEHOLDER |

Note: Vencimientos "7 días" label is cosmetic — `vencidos` = pending before month start; V1 reuses it unchanged (no date-window filter added).

## Architecture Decisions

| Decision | Choice | Alternatives rejected | Rationale |
|---|---|---|---|
| dashboardDayCounts lift | New pure `lib/features/coach/application/dashboard_day_counts.dart` exporting `DashboardDayCounts`, `dashboardDayCounts()`, and inlined `_isSameLocalDay`. `trainer_dashboard_tab.dart` deletes its copies and `import`s+re-exports (`export '...dashboard_day_counts.dart' show dashboardDayCounts, DashboardDayCounts;`) so the existing mobile test import (`trainer_dashboard_day_counts_test.dart:7`) keeps compiling | (a) re-derive inline on web → logic drift, 2 sources of truth; (b) move test import to new path → touches mobile test unnecessarily | Single source of truth; mobile keeps working via re-export; `_appointmentsKey` STAYS mobile-private (web builds its own key) |
| Placeholder pattern | Shared file-private `_PlaceholderCard({title, hint})` in the dashboard file: bordered `bgCard` container + muted title + "Próximamente" hint. Named DISTINCT from mobile's `_PlaceholderCard` (different file scope, no clash) | Feature-flag hidden sections | Mockup parity without inventing providers; clearly signals V1.1 work; zero provider cost |
| Solicitudes preservation | Lift `_PendingRequestsList`/`_PendingRequestTile`/`_confirmAction` UNCHANGED into `_PendingTodaySection`. Keep keys `pending_request_`,`accept_`,`decline_`, accept/decline mutations, `logLinkAccepted`, busy-guard | Rewrite as new widget | Behavior + analytics + 0 test churn; these are the ONLY home for accept/decline |
| Adaptive breakpoint | `constraints.maxWidth >= 900 && constraints.maxHeight.isFinite` → Row(55/45); else stacked Column | 1200px (mockup native) | Mirrors `agenda_web_screen.dart:107-108`; finite-height guard prevents unbounded-height crash inside scroll |
| maxWidth cap | 1280 (up from 800) | keep 800 | 800 can't fit 2 columns; 1280 matches mockup desktop |
| Strings | AppL10n new keys (file already migrated) | hardcoded es-AR (pagos pattern) | This file's contract is AppL10n — do NOT copy pagos' hardcoded style |

## File Changes

| File | Action | Description |
|---|---|---|
| `lib/features/coach/application/dashboard_day_counts.dart` | Create | Pure lift: `DashboardDayCounts`, `dashboardDayCounts()`, `_isSameLocalDay` |
| `lib/features/coach/presentation/trainer_dashboard_tab.dart` | Modify | Delete local `DashboardDayCounts`/`dashboardDayCounts`/`_isSameLocalDay` (1537-1578,1649-1651); import + re-export from new file. `_appointmentsKey` unchanged |
| `lib/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart` | Modify | Rewrite `build`; add banner/welcome/KPI strip/2-col body + `_PlaceholderCard`; KEEP `_PendingRequestsList`/`_PendingRequestTile`/`_confirmAction`; REMOVE `_statusFilterProvider`,`_FilterChipRow`,`_ActiveStudentsList`,`_PausedStudentsList`,`_HistorialList`,`_StudentTile`,`_PausedStudentTile`,`_TerminatedStudentTile`,`_SectionLabel`,`_reasonDisplay`,`_formatPauseDate` (relocate Importar-plan as quick action) |
| `lib/l10n/*.arb` (+ generated) | Modify | New AppL10n keys (greeting, KPI labels, section headers, placeholder/"Próximamente", quick actions) |
| `test/.../coach_hub_dashboard_screen_test.dart` | Modify | DELETE ACTIVOS/PAUSADOS/HISTORIAL + Pausar/Terminar/Reanudar + FilterChip tests (widgets removed). ADD: KPI strip, próximas sesiones, vencimientos, placeholder render, preserved-solicitudes accept/decline (keys) |
| `test/.../coach_hub_dashboard_in_shell_test.dart` | Modify | "IMPORTAR PLAN DESDE EXCEL" assertion → new quick-action label; Scaffold/no-brand-header asserts stay |

## Interfaces / Contracts

```dart
// lib/features/coach/application/dashboard_day_counts.dart
class DashboardDayCounts {
  const DashboardDayCounts({required this.pending, required this.done, required this.cancelled});
  final int pending; final int done; final int cancelled;
}
DashboardDayCounts dashboardDayCounts(List<Appointment> all, DateTime now); // now MUST be UTC
```

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Unit | `dashboardDayCounts` post-lift | Existing `trainer_dashboard_day_counts_test.dart` passes unchanged via re-export; optionally add direct import to new path |
| Widget | KPI values, próximas/vencimientos, placeholders | Stub `trainerLinksStreamProvider`, `trainerAppointmentsStreamProvider(key)`, `pagosBucketsProvider`/`trainerPaymentsProvider`, `userProfileProvider`, `totalUnreadCountProvider` |
| Widget | Preserved solicitudes | Reuse existing accept/decline verify tests keyed `accept_`/`decline_`/`pending_request_` |
| Widget | Shell contract | in-shell test: one Scaffold, no brand header, quick-action present |

## Migration / Rollout

No data migration. Mobile risk = the lift only; re-export keeps `trainer_dashboard_tab.dart` API stable so `trainer_dashboard_day_counts_test.dart` and mobile UI are untouched. Removed student-list bulk view: PAUSADOS/HISTORIAL now only in `/alumnos` (V1 tradeoff, accepted in proposal).

## PR Split (chained, ≤400 lines each)

| PR | Scope | Est. lines |
|---|---|---|
| PR1 | Lift `dashboardDayCounts` (new file + re-export) + layout scaffold (maxWidth 1280, LayoutBuilder) + `_AlertBanner` placeholder + `_WelcomeCard` (greeting, quick actions incl. relocated Importar-plan, ring placeholder) + `_KpiStrip` (3 real tiles + adherencia placeholder) + `_PlaceholderCard` | ~330–390 |
| PR2 | RIGHT column: `_ProximasSesiones` (real) + `_Vencimientos7d` (real) + `_InactivosSection` placeholder | ~200–260 |
| PR3 | LEFT column: `_PendingTodaySection` wrapping preserved solicitudes + `_AdherenceChart` placeholder + REMOVE old student-list/tile/filter code (~600 net-negative lines) + test migration | ~250–320 net (mostly deletions) |

Removing ~600 lines of student-list/tile/filter code offsets the new layout; each slice has autonomous scope + rollback. PR3 is net-negative — safe.

## Open Questions

- [ ] KPI deltas (mockup -3/+3%): ship VALUES ONLY (no time-series provider) — confirm in tasks.
- [ ] `_InactivosSection`/`_AdherenceChart` placeholder copy: exact AppL10n strings finalized in tasks.

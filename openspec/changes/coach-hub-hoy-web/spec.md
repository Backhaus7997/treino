# Delta Spec: coach-hub-hoy-web

**Change**: `coach-hub-hoy-web` — W4.1 Coach Hub WEB dashboard "Hoy" (/dashboard)
**Type**: Pure presentation re-layout. No new providers, no new backend.
**Primary file**: `lib/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart`

---

## MODIFIED Requirements

### Requirement: REQ-HOY-01 — Dashboard Layout

`CoachHubDashboardScreen` MUST replace the current `Center > ConstrainedBox(maxWidth:800) > Column` with a `LayoutBuilder`-driven two-column adaptive layout. At `constraints.maxWidth >= 900` the screen MUST render two columns (left ~60%, right ~40%). Below 900px it MUST stack all sections vertically in a scrollable column. The screen MUST guard against unbounded height (finite-height guard identical to `agenda_web_screen.dart`). The screen MUST NOT add a Scaffold or SafeArea (ADR-CHW-005 — shell provides chrome).

(Previously: single-column `maxWidth:800` ConstrainedBox.)

#### Scenario: SCENARIO-HOY-01A — Wide layout renders two columns

- GIVEN the Coach Hub shell renders `/dashboard` with available width >= 900px
- WHEN `CoachHubDashboardScreen` builds
- THEN the left column is visible containing the alert banner, welcome card, KPI strip, and pendientes section
- AND the right column is visible containing próximas sesiones, vencimientos, and alumnos inactivos sections

#### Scenario: SCENARIO-HOY-01B — Narrow layout stacks columns

- GIVEN the available width is < 900px
- WHEN `CoachHubDashboardScreen` builds
- THEN all sections render in a single scrollable vertical column in the order: alert banner, welcome card, KPI strip, pendientes, próximas sesiones, vencimientos, alumnos inactivos

---

### Requirement: REQ-HOY-02 — Student-Management Lists REMOVED

The ACTIVOS / PAUSADOS / HISTORIAL student lists, their per-athlete mutation actions (Pausar, Terminar, Reanudar), the `_FilterChipRow`, and `_statusFilterProvider` MUST be removed from the dashboard screen. Per-athlete management is canonical to the `/alumnos` section.

(Previously: three student lists with Pausar/Terminar/Reanudar actions occupied the majority of the screen.)

#### Scenario: SCENARIO-HOY-02A — Student lists absent

- GIVEN a trainer navigates to `/dashboard`
- WHEN the screen renders
- THEN no ACTIVOS / PAUSADOS / HISTORIAL list is present
- AND no filter chip row (ACTIVOS / PAUSADOS / HISTORIAL chips) is rendered

---

## ADDED Requirements

### Requirement: REQ-HOY-03 — Alert Banner (Placeholder V1)

The screen MUST render an alert banner at the top of the content area styled per the mockup (dark/accent card). In V1 the banner content MUST be a styled placeholder — it MUST NOT render a real notification-aggregation feed. The banner MUST display a fixed placeholder copy (e.g. "Próximamente: resumen de atención") clearly marked as coming soon. The rich aggregation (messages, photos, pain, pagos) is explicitly OUT OF SCOPE for V1.

#### Scenario: SCENARIO-HOY-03A — Alert banner renders as placeholder

- GIVEN a trainer is on `/dashboard`
- WHEN the alert banner section builds
- THEN a styled banner widget is visible at the top of the content
- AND it does NOT attempt to read a notification-aggregation provider
- AND it displays a clearly-marked placeholder label

---

### Requirement: REQ-HOY-04 — Welcome Card

The screen MUST render a welcome card showing: (a) the current date formatted via `AppL10n`, (b) a greeting "BUENAS, {firstName}" where `firstName` is derived from `userProfileProvider.displayName` (split on whitespace, first token), (c) a summary line "Tenés N sesiones hoy, M para revisar, K pagos pendientes" where N comes from `trainerAppointmentsStreamProvider` + `dashboardDayCounts()`, M comes from `trainerLinksStreamProvider.where(pending).length`, and K comes from `pagosBucketsProvider.vencidos.length`, (d) quick actions: "+ Nuevo alumno", "Crear rutina", and "Mensajes (N)" where N is REAL from `totalUnreadCountProvider`, (e) an adherencia ring showing PLACEHOLDER "--" (no aggregate provider exists in V1). All copy MUST use AppL10n keys. The card MUST be a `ConsumerWidget`.

#### Scenario: SCENARIO-HOY-04A — Welcome card shows real greeting and summary

- GIVEN `userProfileProvider` emits a profile with `displayName: "Joaco Trainer"`
- AND `trainerAppointmentsStreamProvider` has 6 confirmed appointments today
- AND `trainerLinksStreamProvider` has 5 pending solicitudes
- AND `pagosBucketsProvider.vencidos` has 3 entries
- WHEN the welcome card builds
- THEN the greeting displays "BUENAS, JOACO"
- AND the summary line shows "Tenés 6 sesiones hoy, 5 para revisar, 3 pagos pendientes"

#### Scenario: SCENARIO-HOY-04B — Adherencia ring shows placeholder

- GIVEN any state of providers
- WHEN the welcome card renders the adherencia ring
- THEN the ring displays "--" and does NOT call any aggregate adherencia provider

#### Scenario: SCENARIO-HOY-04C — Mensajes count is real

- GIVEN `totalUnreadCountProvider` emits 7
- WHEN the welcome card quick actions render
- THEN the "Mensajes" action label shows "(7)"

---

### Requirement: REQ-HOY-05 — KPI Strip (4 tiles, no deltas)

The screen MUST render 4 KPI tiles in a horizontal strip using the existing `KpiTile` widget from `pagos_kpi_row.dart`. V1 MUST NOT show week-over-week deltas (no time-series provider exists). The 4 tiles and their data sources are:

| Tile | Provider | Derivation |
|------|----------|-----------|
| Alumnos activos | `trainerLinksStreamProvider` | `.where(status == active).length` |
| Ingreso del mes | `pagosBucketsProvider` | `pagados` where `(paidAt ?? createdAt) >= monthStart UTC`, sum of `amountArs` |
| Adherencia promedio | none | PLACEHOLDER: "--" |
| Por cobrar | `pagosBucketsProvider` | `vencidos.fold(amountArs)` ARS + `vencidos.length` count |

Each tile MUST handle loading state gracefully (spinner or skeleton). Each tile MUST handle error state (error label, no crash). No tile MUST show delta values (no +N%, −N).

#### Scenario: SCENARIO-HOY-05A — Alumnos activos tile shows correct count

- GIVEN `trainerLinksStreamProvider` emits 28 active links and 3 paused links
- WHEN the KPI strip renders
- THEN the "Alumnos activos" tile shows 28
- AND it does NOT show a delta value

#### Scenario: SCENARIO-HOY-05B — Ingreso del mes tile shows paid-this-month total

- GIVEN `pagosBucketsProvider` has 5 pagos with `paidAt` in the current UTC month totaling $412.000 ARS
- WHEN the KPI strip renders
- THEN the "Ingreso del mes" tile shows $412.000

#### Scenario: SCENARIO-HOY-05C — Adherencia tile shows placeholder

- GIVEN any provider state
- WHEN the KPI strip renders
- THEN the "Adherencia promedio" tile shows "--"
- AND it does NOT call any aggregate adherencia provider

#### Scenario: SCENARIO-HOY-05D — Por cobrar tile shows vencidos sum and count

- GIVEN `pagosBucketsProvider.vencidos` has 3 entries totaling $86.000 ARS
- WHEN the KPI strip renders
- THEN the "Por cobrar" tile shows "$86.000" and "(3 vencimientos)"

#### Scenario: SCENARIO-HOY-05E — KPI tile handles loading state

- GIVEN a provider is in loading state
- WHEN the corresponding KPI tile builds
- THEN it renders a loading indicator, not an error or empty value

---

### Requirement: REQ-HOY-06 — Pendientes de HOY (Left Column — Real Solicitudes, Deferred Board)

The left column MUST contain a "Pendientes de HOY" section. In V1 its content MUST be the REAL solicitudes pendientes: the existing `_PendingRequestsList` and `_PendingRequestTile` widgets, lifted UNCHANGED into the new layout. The rich notification-aggregation board (messages, workout completions, photos, pain reports) is DEFERRED and MUST NOT be implemented in V1. The section MUST render a placeholder label for the deferred notification board (e.g. "Próximamente"). Widget keys `accept_*`, `decline_*`, and `pending_request_*` MUST be preserved exactly. The accept mutation MUST call `TrainerLinkRepository.accept()`, trigger `logLinkAccepted` analytics, and hold a busy-guard during the async operation. The decline mutation MUST call `TrainerLinkRepository.decline()` with a confirm dialog. On mutation error the section MUST surface an error message. After mutation the stream MUST auto-refresh via `trainerLinksStreamProvider`. The left column MUST also contain an adherencia 28-day chart section rendered as a PLACEHOLDER (no real chart data in V1).

#### Scenario: SCENARIO-HOY-06A — Solicitudes accept mutation fires correctly

- GIVEN a pending solicitud from athlete "Ana"
- AND the trainer taps "Aceptar" (key `accept_{id}`)
- WHEN the busy-guard releases
- THEN `TrainerLinkRepository.accept()` was called
- AND `logLinkAccepted` analytics was called
- AND the solicitud disappears from the list (stream auto-refreshes)

#### Scenario: SCENARIO-HOY-06B — Solicitudes decline shows confirm dialog

- GIVEN a pending solicitud from athlete "Bob"
- WHEN the trainer taps "Rechazar" (key `decline_{id}`)
- THEN a confirm `showDialog` appears
- AND only after confirmation does `TrainerLinkRepository.decline()` execute

#### Scenario: SCENARIO-HOY-06C — Deferred notification board renders as placeholder

- GIVEN the trainer is on `/dashboard`
- WHEN the "Pendientes de HOY" section builds
- THEN a clearly-marked placeholder is shown in place of the notification aggregation board
- AND no notification-aggregation provider is called

#### Scenario: SCENARIO-HOY-06D — Adherencia chart placeholder renders

- GIVEN any provider state
- WHEN the left column renders the adherencia section
- THEN a placeholder (e.g. "Próximamente") is visible
- AND no 28-day adherencia time-series provider is called

---

### Requirement: REQ-HOY-07 — Próximas Sesiones (Right Column)

The right column MUST contain a "Próximas sesiones" section. It MUST read `trainerAppointmentsStreamProvider` and show confirmed appointments where `startsAt.isAfter(now)`, limited to ~4 rows. Each row MUST show: time (HH:MM), athlete name, modality. The section MUST handle loading and empty states gracefully.

#### Scenario: SCENARIO-HOY-07A — Próximas sesiones shows upcoming confirmed appointments

- GIVEN `trainerAppointmentsStreamProvider` has 6 upcoming confirmed appointments
- WHEN the right column renders
- THEN the próximas sesiones section shows the next 4 (earliest by `startsAt`)
- AND each row shows time, athlete name, and modality

#### Scenario: SCENARIO-HOY-07B — Empty state when no upcoming sessions

- GIVEN there are no upcoming confirmed appointments
- WHEN the right column renders
- THEN an empty state message is shown (no crash, no blank space)

---

### Requirement: REQ-HOY-08 — Vencimientos 7 días (Right Column)

The right column MUST contain a "Vencimientos — 7 días" section reading from `pagosBucketsProvider.vencidos`. Each row MUST show the athlete name and an overdue indicator. A "VER TODOS LOS PAGOS" link MUST navigate to the `/pagos` route. The section MUST handle loading and empty states.

#### Scenario: SCENARIO-HOY-08A — Vencimientos section shows overdue entries

- GIVEN `pagosBucketsProvider.vencidos` has 4 entries
- WHEN the right column renders
- THEN the vencimientos section shows all 4 entries with athlete name and overdue indicator

#### Scenario: SCENARIO-HOY-08B — Empty vencimientos shows empty state

- GIVEN `pagosBucketsProvider.vencidos` is empty
- WHEN the right column renders
- THEN an empty state message is shown (no crash)

---

### Requirement: REQ-HOY-09 — Alumnos Inactivos (Right Column — Placeholder V1)

The right column MUST contain an "Alumnos inactivos" section. In V1 it MUST be a PLACEHOLDER (no derived provider for session-inactivity exists). It MUST display a clearly-marked placeholder label (e.g. "Próximamente"). It MUST NOT call any new derived provider.

#### Scenario: SCENARIO-HOY-09A — Alumnos inactivos renders as placeholder

- GIVEN any provider state
- WHEN the right column renders the alumnos inactivos section
- THEN a placeholder label is visible
- AND no session-inactivity provider is called

---

### Requirement: REQ-HOY-10 — Preserved: Importar Plan CTA

The "Importar plan" CTA MUST remain present in the redesigned dashboard. It MUST navigate to `/upload-plan` via `context.push('/upload-plan')` when tapped. It MAY live in the welcome card quick actions row or in a dedicated header area.

#### Scenario: SCENARIO-HOY-10A — Importar plan CTA navigates correctly

- GIVEN the trainer is on `/dashboard`
- WHEN they tap the "Importar plan" button
- THEN `context.push('/upload-plan')` is called

---

### Requirement: REQ-HOY-11 — Section Contract and String Convention

All new widgets in this change MUST be `ConsumerWidget` (or `ConsumerStatefulWidget` only when local mutation-guard state is required). No widget in this change MUST add a `Scaffold` or `SafeArea`. Colors MUST use `AppPalette.of(context)` — no HEX literals. Icons MUST use `TreinoIcon`. Confirm dialogs MUST use `showDialog`. All user-visible strings MUST use `AppL10n.of(context)` keys (consistent with the existing dashboard file — NOT the pagos hardcoded es-AR pattern). `flutter analyze` MUST report 0 issues and `dart format .` MUST produce no diffs after this change.

#### Scenario: SCENARIO-HOY-11A — No hardcoded strings

- GIVEN the spec-compliant implementation
- WHEN a reviewer searches for hardcoded es-AR strings in the dashboard file
- THEN none are found (all copy goes through AppL10n)

#### Scenario: SCENARIO-HOY-11B — Static analysis passes

- GIVEN the implementation is complete
- WHEN `flutter analyze` is run
- THEN it reports 0 issues

---

## Out of Scope (explicit record)

The following MUST NOT be implemented in this change:

| Deferred Item | Reason |
|---|---|
| Adherencia aggregate provider | Requires per-athlete fan-out of `ResumenMetrics` across all shared athletes — new data derivation, not presentation |
| Alumnos inactivos derived provider | Requires session-scan per active athlete + day threshold — new provider, new domain decision |
| Rich notification-aggregation board ("Pendientes de HOY") | Aggregates messages, workouts, photos, pain reports — new notification domain, no existing provider |
| 28-day adherencia line chart real data | Per-athlete time-series aggregation, highest complexity |
| KPI tile week-over-week deltas | No time-series/snapshot provider exists |

Domain-capability deltas: **None** — this change is pure presentation reuse. No new providers, repositories, or Firestore reads are introduced.

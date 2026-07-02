# Proposal: coach-hub-hoy-web

**Change**: `coach-hub-hoy-web`
**Phase**: W4.1 — Coach Hub WEB dashboard "Hoy" (route `/dashboard`, RESUMEN group)
**Type**: Pure presentation re-layout (zero backend, zero new providers)
**Scope**: LOCKED to **V1 ready-data**

---

## Problem

The Coach Hub web dashboard (`coach_hub_dashboard_screen.dart`, 953 lines) is today a **link-management screen**, not a dashboard. When a trainer lands on `/dashboard` they see: an "Importar plan" CTA, a solicitudes-pendientes queue, and three student lists (ACTIVOS / PAUSADOS / HISTORIAL) with per-athlete Pausar/Terminar/Reanudar actions gated by a filter-chip row.

This is a mismatch on three axes:

1. **Purpose**: "Hoy" should answer *"what needs my attention today?"* at a glance (active roster size, sessions today, money owed, income). Instead it forces the trainer to scan raw link lists.
2. **Duplication**: per-athlete management (Terminar, etc.) already lives in the **/alumnos** section (`alumno_detail`). The dashboard re-hosts that surface with no unique value beyond the bulk view.
3. **Layout**: a single `maxWidth: 800` column wastes the horizontal space of a desktop-first web shell. The agenda section (`agenda_web_screen.dart`) already established a responsive two-column pattern the dashboard should mirror.

## Why now

W4.1 is the scheduled dashboard redesign. All the data needed for a genuine KPI dashboard **already exists** in shipped providers (links, appointments, pagos buckets) — this is a presentation reuse, not a data project. Doing it now converts a low-value screen into the daily landing surface with essentially zero backend risk.

## Goal / Success

A trainer landing on `/dashboard` sees a **KPI dashboard**: a 4-tile strip summarizing the state of their business, plus two secondary lists (upcoming sessions, upcoming/overdue payments), while the two behaviors that have **no other home** — the solicitudes accept/decline queue and the "Importar plan" CTA — are preserved exactly. The layout is **adaptive** (two columns wide, stacked narrow). No new provider, repository, or Firestore read is introduced. All KPI values come from providers already mounted elsewhere in Coach Hub.

Success is measured by acceptance criteria (below): correct KPI values from existing data, preserved mutations, responsive layout at the breakpoint, and each delivery PR under the 400-line budget.

---

## Scope

### In scope (V1 ready-data)

1. **KPI strip — 4 tiles**, all from existing providers:
   - **Alumnos activos** — `trainerLinksStreamProvider.where(status == active).length`.
   - **Sesiones hoy** — `trainerAppointmentsStreamProvider` + `dashboardDayCounts()` (count of today's confirmed appointments).
   - **Por cobrar / Vencimientos** — `pagosBucketsProvider.vencidos` (count + ARS total), reusing the Pagos section's provider.
   - **Ingreso del mes** — the paid-this-month logic already in `PagosKpiRow` (`pagosBucketsProvider.pagados` filtered to `(paidAt ?? createdAt) >= monthStart UTC`).
2. **Secondary lists (reuse)**:
   - **Próximas sesiones** — `trainerAppointmentsStreamProvider.where(confirmed && startsAt.isAfter(now)).take(3)`.
   - **Vencimientos** list — from `pagosBucketsProvider.vencidos`.
3. **Preserve exactly**:
   - **Solicitudes pendientes** accept/decline queue (`_PendingRequestsList` + `_PendingRequestTile`, `TrainerLinkRepository.accept()/.decline()`, analytics `logLinkAccepted`, busy-guard, error-surfacing). This is its **only home** today — the Actividad section is still a placeholder.
   - **"Importar plan" CTA** → `context.push('/upload-plan')`.
4. **Adaptive two-column layout** via `LayoutBuilder`, replacing the `maxWidth: 800` single column. Mirrors `agenda_web_screen.dart`'s pattern (`constraints.maxWidth >= 900` → two columns; else stacked/scrollable).
5. **Strings via AppL10n** — the dashboard file is already fully migrated to `AppL10n.of(context)`. New KPI copy follows AppL10n (NOT the pagos section's hardcoded `es-AR + // i18n` pattern) to stay consistent with the file it lives in.
6. **Section contract** (unchanged): `ConsumerWidget`, no Scaffold/SafeArea (ADR-CHW-005 — shell provides chrome), `AppPalette.of(context)`, `TreinoIcon`, `showDialog` for confirms.

### Out of scope (each its own future SDD)

| Deferred item | Why out |
|---|---|
| **"Pendientes de HOY" notification board** | Aggregates messages + workouts + photos + pain + pagos into one feed. No provider exists — this is a **new notification/activity domain**, not a re-layout. |
| **Adherencia promedio (aggregate)** | Requires per-athlete fan-out of `ResumenMetrics.compute()` across all shared athletes + averaging against each active routine's weeklyTarget. Cross-athlete aggregation, no aggregate provider. |
| **Alumnos inactivos** | "Active link, no session in N days" needs a session-scan derivation per athlete + a day threshold. New derived provider + a policy decision on the threshold. |
| **Adherencia 28-day line chart** | Per-athlete time-series aggregation + charting. Highest visual + data complexity of the mockup. |

These four are explicitly acknowledged as valuable but **NOT** part of a "pure presentation, zero backend" cut. Each needs its own exploration/proposal because each introduces new data derivation.

---

## KPI + reuse map (verified against source)

| Surface | Provider (existing) | Derivation | Status |
|---|---|---|---|
| KPI: Alumnos activos | `trainerLinksStreamProvider` | `.where(status == active).length` | READY |
| KPI: Sesiones hoy | `trainerAppointmentsStreamProvider` | `dashboardDayCounts(all, now).pending + .done` | READY (see note) |
| KPI: Por cobrar / Vencimientos | `pagosBucketsProvider` | `vencidos.length` + `vencidos.fold(amountArs)` | READY |
| KPI: Ingreso del mes | `pagosBucketsProvider` | paid `(paidAt ?? createdAt) >= monthStart UTC` sum (as in `PagosKpiRow`) | READY |
| List: Próximas sesiones | `trainerAppointmentsStreamProvider` | `.where(confirmed && startsAt.isAfter(now)).take(3)` | READY |
| List: Vencimientos | `pagosBucketsProvider` | `vencidos` (optionally ≤7 days) | READY |
| Preserve: Solicitudes | `trainerLinksStreamProvider` + `trainerLinkRepositoryProvider` | `.where(pending)` + accept/decline | READY (keep as-is) |
| Preserve: Importar plan | — | `context.push('/upload-plan')` | READY (keep as-is) |

**Note on `dashboardDayCounts` (slicing gotcha)**: it currently lives in `trainer_dashboard_tab.dart` (mobile, lines 1556-1578) and depends on the file-private `_isSameLocalDay`. Reusing it on web means either (a) lifting `dashboardDayCounts` + its helper into a shared location (e.g. `lib/features/coach/application/`), or (b) re-deriving the today-count inline in the web tile. Recommendation: **lift it to a shared, testable location** — it is already a pure function and mobile keeps consuming it. Flag for the spec/design phase; it is a small refactor, not new data.

**Reuse leverage**: `KpiTile` (public widget in `pagos_kpi_row.dart`) is a ready label+value tile — the KPI strip can compose it directly instead of re-inventing tile chrome.

---

## Design tension to RESOLVE: the student-management lists

The current dashboard hosts ACTIVOS / PAUSADOS / HISTORIAL lists with Pausar/Terminar/Reanudar actions. The KPI mockup does **not** include them, and per-athlete management already lives in **/alumnos** (`alumno_detail` has Terminar, etc.).

**Recommendation: (a) REMOVE these lists from the dashboard for V1.**

Rationale:
- **Matches the mockup** — the redesign is a KPI dashboard, not a roster manager.
- **De-duplicates** — /alumnos is the canonical per-athlete management surface; keeping a second copy on /dashboard invites drift and split responsibility.
- **The "Alumnos activos" KPI tile already answers the roster-size question** at a glance, which is the dashboard-appropriate framing.

**Tradeoff (the cost of removing)**: the dashboard is currently the **only bulk view of PAUSADOS and HISTORIAL** on web. Removing the lists drops that bulk view unless /alumnos exposes paused/terminated filtering. If /alumnos does not yet surface paused/historial, option (a) creates a temporary gap.

**Alternative (b) — keep the lists below the KPI dashboard**: additive and safe (no behavior lost), but does not fully match the redesign and re-introduces the duplication the redesign is meant to remove.

**This is a DECISION for the orchestrator to confirm.** Recommendation stands at **(a) REMOVE**, conditional on a quick check that /alumnos covers paused/terminated states; if it does not, fall back to **(b) keep HISTORIAL/PAUSADOS as a collapsed section** until /alumnos closes the gap. The `_statusFilterProvider` and filter-chip row are superseded under either option.

---

## Approach (adaptive layout)

**In-place rewrite** of `CoachHubDashboardScreen` (Approach A from exploration), keeping the same file and route, delivered as **chained PRs** to respect the 400-line budget.

Layout: replace `Center > ConstrainedBox(maxWidth: 800) > SingleChildScrollView > Column` with a `LayoutBuilder`:
- **Wide** (`constraints.maxWidth >= 900`): two columns. Left = KPI strip + primary content (solicitudes queue, próximas sesiones); Right = vencimientos list. Column split follows the agenda precedent.
- **Narrow** (`< 900`): stacked, scrollable — KPI strip (wrap/2×2), then sections in vertical order. Robust against unbounded height (same guard the agenda uses: only fill-height when `maxHeight.isFinite`).

The "Importar plan" CTA sits above the KPI strip (primary action). Loading/error states per section stay graceful (existing `_SectionLoading` / `_SectionError` helpers are reusable).

Rationale: one file keeps routing and the section contract untouched; the agenda already proved this responsive pattern in the same shell, so we reuse a known-good breakpoint rather than inventing one.

---

## Delivery plan (2 chained PRs)

Current file is ~953 lines; a full rewrite must be sliced. Two chained PRs, each targeting ≤400 changed lines, each leaving `/dashboard` in a working state.

**PR1 — Adaptive layout scaffold + KPI strip + preserved behaviors** (~330-390 lines)
- New `LayoutBuilder` two-column/stacked structure replacing `maxWidth: 800`.
- KPI strip with the 4 tiles wired to existing providers (activos, sesiones hoy, por cobrar, ingreso del mes) — reusing `KpiTile`.
- **Preserve** solicitudes queue + "Importar plan" CTA verbatim inside the new layout.
- Remove (or collapse, per the decision) the ACTIVOS/PAUSADOS/HISTORIAL lists + filter chips.
- `dashboardDayCounts` lift-to-shared refactor if that path is chosen.

**PR2 — Secondary lists** (~180-260 lines)
- Próximas sesiones panel (`trainerAppointmentsStreamProvider`, next 3 confirmed).
- Vencimientos list panel (`pagosBucketsProvider.vencidos`).
- Right-column composition finalized; narrow-mode ordering.

Net line count drops substantially versus today (the ~700 lines of student-list/tile/filter code are removed under option (a)), which eases the budget. If the orchestrator's Review Workload Guard still flags risk, PR1 can be split (layout scaffold; then KPI wiring), but two PRs is the target.

---

## Risks

1. **Layout breakpoint** — a single `>= 900` breakpoint may look awkward at intermediate widths inside the Coach Hub shell (sidebar eats horizontal space). Mitigation: reuse the agenda's exact breakpoint + finite-height guard; verify visually in the shell, not in isolation.
2. **Preserving solicitudes mutations** — the accept/decline flow has a busy-guard, analytics call, error-surfacing, and stream-driven auto-refresh (ADR-CHLM-03). Rewriting the surrounding layout risks dropping one of these. Mitigation: lift the existing `_PendingRequestsList`/`_PendingRequestTile` widgets **unchanged** into the new layout rather than rewriting them; keep their widget keys (`accept_`, `decline_`, `pending_request_`) so existing widget tests still pass.
3. **PR budget** — the rewrite touches a 953-line file. Mitigation: the removal of student lists shrinks the file; chained PRs with a working state each; PR1 splittable if flagged.
4. **`dashboardDayCounts` reuse** — pulling a mobile file-private helper to web. Mitigation: lift to shared application layer (pure function, already unit-testable); mobile keeps consuming it — no behavior change.
5. **Student-list removal gap** — if /alumnos does not surface paused/terminated, option (a) removes the only bulk view. Mitigation: the decision resolves to (b) collapsed-section fallback if the gap is confirmed.

---

## Acceptance criteria

1. `/dashboard` renders a KPI strip of 4 tiles with **correct values** derived from existing providers (no new provider added):
   - Alumnos activos = count of active links.
   - Sesiones hoy = today's confirmed appointments count.
   - Por cobrar = vencidos ARS total + count.
   - Ingreso del mes = paid-this-month ARS total.
2. **Próximas sesiones** shows up to 3 upcoming confirmed appointments; **Vencimientos** shows overdue payments — both from existing providers.
3. **Solicitudes pendientes** accept/decline still work end-to-end: mutations fire, analytics logs, busy-guard holds, errors surface, stream auto-refreshes. Existing widget keys preserved.
4. **"Importar plan"** CTA still navigates to `/upload-plan`.
5. Layout is **adaptive**: two columns at `>= 900` width, stacked below, no overflow at either mode inside the Coach Hub shell.
6. All new copy uses **AppL10n** (consistent with the existing file); no hardcoded es-AR strings introduced in this file.
7. Section contract holds: `ConsumerWidget`, no Scaffold/SafeArea, `AppPalette`, `TreinoIcon`, `showDialog` confirms.
8. `flutter analyze` 0 issues, `dart format .` clean, existing dashboard widget tests pass (adjusted only for removed student-list sections).
9. Each delivery PR ≤ 400 changed lines with a working `/dashboard` at merge.
10. The four out-of-scope items are **not** implemented (no notification board, no aggregate/inactivos/chart).

---

## Open questions for spec/design

1. **Student-lists decision** — confirm (a) REMOVE vs (b) keep-collapsed. Depends on whether /alumnos surfaces paused/terminated. (Recommendation: REMOVE, fallback to collapsed.)
2. **`dashboardDayCounts` reuse strategy** — lift to shared application layer vs re-derive inline. (Recommendation: lift.)
3. **Vencimientos window** — show all `vencidos` or filter to a 7-day horizon as the mockup implies.
4. **KPI tile deltas** — the mockup shows week-over-week deltas (−3, +3%). No historical snapshot provider exists; V1 should ship **values only, no deltas** (deltas would need a time-series — out of scope). Confirm.

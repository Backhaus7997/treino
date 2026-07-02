# Exploration: coach-hub-hoy-web

## Phase
W4.1 — Dashboard "Hoy" web redesign (RESUMEN group, route `/dashboard`).

---

## Current Dashboard State

**File**: `lib/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart`

### What it shows today

The current screen (`CoachHubDashboardScreen`, `ConsumerWidget`, lines 100-156) is a **link-management dashboard**, not a KPI summary. It renders:

1. **"Importar plan" CTA button** (line 119-139) — `context.push('/upload-plan')` — must be PRESERVED in the redesign (it is a primary action).
2. **`_PendingRequestsList`** (line 142) — solicitudes pendientes from `trainerLinksStreamProvider` where `status == pending`. Shows avatar + name + Aceptar/Rechazar (accept/decline) with full mutation logic — `TrainerLinkRepository.accept()` / `.decline()`. **Must be preserved exactly.**
3. **`_FilterChipRow`** (line 144) — 3 chips: ACTIVOS / PAUSADOS / HISTORIAL. Drives local `_statusFilterProvider` (autoDispose `Set<TrainerLinkStatus>`).
4. **`_ActiveStudentsList`** (lines 241-283) — active links with Pausar + Terminar actions.
5. **`_PausedStudentsList`** (lines 287-329) — paused links with Reanudar + Terminar actions.
6. **`_HistorialList`** (lines 333-376) — terminated links (read-only, shows termination reason).

### Section contract compliance (lines 1-9, 104-112)
- `ConsumerWidget` (no `ConsumerStatefulWidget`) ✅ — outer; inner tiles use `ConsumerStatefulWidget` for mutation guards.
- No Scaffold / SafeArea (ADR-CHW-005) ✅ — comment on line 1.
- Uses `AppPalette.of(context)` ✅, `TreinoIcon` ✅, `AppL10n` ✅ (already migrated to i18n).
- `showDialog` via `_confirmAction` helper (lines 54-78) ✅.
- MaxWidth 800 constraint (line 113) ✅.

### What must be PRESERVED vs REPLACED

| Element | Action |
|---|---|
| Importar plan CTA | PRESERVE — primary quick action |
| `_PendingRequestsList` with accept/decline mutations | PRESERVE — move to KPI strip "Pendientes" card's detail panel or keep inline |
| `_ActiveStudentsList` with Pausar/Terminar actions | REPLACE view — actions move to alumno detail; or keep as section below KPI strip |
| `_PausedStudentsList` with Reanudar/Terminar actions | Same as above |
| `_HistorialList` (terminated, read-only) | Can collapse or move to Alumnos section |
| `_FilterChipRow` | Superseded by KPI strip + 5 cards layout |
| `_statusFilterProvider` (autoDispose) | Superseded — no longer needed as primary filter |

---

## 5-KPI Data Source Map

### 1. Sesiones Hoy

**Status: READY**

- Provider: `trainerAppointmentsStreamProvider(TrainerAppointmentsKey)` — `lib/features/coach/application/agenda_providers.dart` lines 80-87.
- Usage pattern: exact same as mobile `_ResumenDelDiaCard` (trainer_dashboard_tab.dart lines 382-450). Uses `dashboardDayCounts(all, now)` helper (lines 1556-1578) that returns `pending`, `done`, `cancelled`.
- For web KPI: count of today's confirmed appointments (`pending + done`). The `trainedTodayProvider` (`lib/features/coach/application/trained_today_provider.dart`) gives a richer list of athletes who FINISHED a session today (not just booked).
- Decision needed: mockup shows "sesiones de hoy" as a count + a list (PRÓXIMAS SESIONES panel in `resto-cards.png`). Two providers available: `trainerAppointmentsStreamProvider` (scheduled appointments) + `trainedTodayProvider` (completed sessions).

### 2. Pendientes (solicitudes)

**Status: READY**

- Provider: `trainerLinksStreamProvider` — `lib/features/coach/application/trainer_link_providers.dart` lines 60-65.
- Derivation: `.where((l) => l.status == TrainerLinkStatus.pending).length` — already done in current `_PendingRequestsList` (line 770).
- Mobile reference: `_SolicitudesPendientesSection` in `trainer_dashboard_tab.dart` lines 226-252 — shows count in header badge + individual tiles.
- Accept/decline mutations must remain wired — the "Pendientes" card needs to link to the solicitudes list or expand inline.

### 3. Vencimientos (pagos vencidos)

**Status: READY**

- Primary provider: `pagosBucketsProvider` — `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart` lines 50-86.
- KPI value: `buckets.vencidos.length` (count) or `buckets.vencidos.fold(0, (s,p) => s+p.amountArs)` (amount).
- Mockup (`resto-cards.png`) shows "VENCIMIENTOS - 7 DÍAS" panel as a LIST of individual athletes with days overdue tags (−3 días, −1 día, mañana). Needs per-athlete vencimiento details.
- Alternative provider already computing this: `PagosKpiRow` widget in pagos section already shows `vencidoTotal` (pagos_kpi_row.dart line 94).
- The `pagosBucketsProvider` composes `trainerPaymentsProvider` (all trainer payments as stream).

### 4. Activos / Inactivos

**Status: PARTIALLY READY — definition gap**

- "Activos" = `trainerLinksStreamProvider.where(status == active).length` — trivial derivation.
- "Inactivos" definition: NO dedicated provider. In `alumnos_screen.dart`, `AlumnoEstado.inactivo` maps to `terminated` and `pending` link statuses — NOT a session-inactivity concept. The mockup shows "3 ALUMNOS INACTIVOS" with copy "Sin entrenamiento desde hace 71 días" — this implies a DIFFERENT definition: active links with last session > N days ago.
- **GAP**: No `lastSessionAt` field on `TrainerLink`. Computing "inactive active links" requires scanning `finishedTodayByUidProvider` or `sessionsByUidProvider` per athlete AND `sharedWithTrainer == true`. The `trainedTodayProvider` pattern (lib/features/coach/application/trained_today_provider.dart) shows how to do per-athlete session scans — but for "last N days" it would need `finishedTodayByUidProvider` generalized to a window, or a new provider.
- **Recommendation for V1**: Show count of active links where athlete has `sharedWithTrainer == true` and no finished session in last 14 days. Requires new derived provider (low complexity, pure client-side derivation — same pattern as `trainedTodayProvider`). If `sharedWithTrainer == false`, athlete is excluded (cannot see their sessions).

### 5. Adherencia

**Status: PARTIALLY READY — no aggregate provider**

- `ResumenMetrics.adherencia30dPct` exists in `lib/features/coach_hub/presentation/sections/alumnos/resumen_metrics.dart` (lines 22-119) and computes per-athlete adherence (sessions in 30d / planned sessions from routine weeklyTarget).
- **GAP**: No AGGREGATE adherencia across ALL athletes. Computing it requires: for each active athlete with `sharedWithTrainer == true`, run `ResumenMetrics.compute()`, then average `adherencia30dPct` — but this also requires knowing each athlete's active routine's `weeklyTarget`. That needs `routinesByTraineeProvider` or similar for each athlete.
- The mockup (`welcome-card.png`) shows "84% ADHER. PROMEDIO" as a circular chart. The `resto-cards.png` shows "74% · -2%" with label "Cayó en últimos 7 días".
- **Recommendation for V1**: Compute aggregate as: sum of sessions completed in last 30d / sum of planned sessions across all athletes with sharedWithTrainer + active routine. This is multi-provider fan-out (N athletes × 2 providers each). Show "--" if no athletes with shared sessions or no routines.
- **Alternative for V1**: Defer aggregate adherencia chart (it's the most complex) and show a simple "sessions this week" count instead. The chart is VISUAL COMPLEXITY but the data is already available per-athlete.

---

## Mobile Reference

**File**: `lib/features/coach/presentation/trainer_dashboard_tab.dart` (1689 lines)

### Mobile KPIs + data patterns

| Section | Provider | Notes |
|---|---|---|
| Header: date + greeting | `userProfileProvider` | `displayName`, split on whitespace for firstName |
| Bell badge: pending count | `trainerLinksStreamProvider` | `.where(pending).length` |
| Resumen del día: PENDIENTES / COMPLETADAS / CANCELADAS | `trainerAppointmentsStreamProvider` + `dashboardDayCounts()` helper | Counts today's confirmed appointments by time of day |
| Próximas sesiones (next 3) | `trainerAppointmentsStreamProvider` | `.where(confirmed && startsAt.isAfter(now)).take(3)` |
| Entrenaron hoy | `trainedTodayProvider` | Per athlete, most-recent finished session today (UTC) |
| Actividad reciente | PLACEHOLDER — `dashboardProximamente` | Not yet implemented |
| Pagos por cobrar | `pagosPorCobrarProvider` | Full list with "COBRADO" action + "Add suelto" sheet |
| Bottom CTAs | Static | Invitar alumno (snackbar stub) + Asignar rutina → `/coach?tab=alumnos` |

**Key patterns to mirror for web**:
- `_appointmentsKey(trainerId)` helper (lines 1679-1688): builds `TrainerAppointmentsKey` with a 2-month window.
- `dashboardDayCounts()` pure function (lines 1556-1578): testable, can be reused as-is.
- All sections handle loading/error states gracefully before showing data.
- `trainerLinksStreamProvider` provides pending badge count AND solicitudes list simultaneously.

---

## Mockup Layout (from images)

### `welcome-card.png`
Top row — **alert banner** (dark card): "3 ALUMNOS NECESITAN TU ATENCIÓN HOY" with subtitle naming athletes and issues (pago vencido, molestia, baja adherencia). Action: "Revisar todo".

**Welcome card**: date in accent color (VIERNES · 30 ABR 2026), greeting "BUENAS, JOACO" (Barlow Condensed 700), summary line: "Tenés 6 sesiones hoy, 5 cosas para revisar y 3 pagos pendientes."

Quick actions row: `+ Nuevo alumno` (accent filled) · `⌁ Crear rutina` (text) · `□ Mensajes (5)` (text).

Adherence circular ring on the right: "84%" + "ADHER. PROMEDIO".

### `resto-cards.png` — Full dashboard layout

**KPI Strip (4 large tiles, top row)**:
- `ALUMNOS ACTIVOS: 28 (−3)` [change vs last week in negative/positive]
- `INGRESO DEL MES: $412.000 (+3%)` [ARS amount + delta]
- `ADHERENCIA PROMEDIO: 74% (−2%)` [percent + delta over last 7 days]
- `POR COBRAR: $86.000 (3 vencimientos)` [ARS + count alert]

**Left column (main content area)**:
- "PENDIENTES DE HOY" section header with "MARCAR TODO REVISADO" trailing action. 4-5 notification rows, each with avatar + description + action button (RESPONDER / REVISAR / VER DETALLE / VER PAGO). Types: message, completed workout (2 alumnos completaron), photos, pain report, vencimiento warning.
- "ADHERENCIA — ÚLTIMOS 28 DÍAS" section: line chart spanning full left column width, with two lines (Tus alumnos / Más alumnos — comparison?). Data has month-scale x-axis.

**Right column (sidebar)**:
- "PRÓXIMAS SESIONES" section header + "AHORA →" trailing link. List of upcoming sessions: time (HH:MM) + athlete avatar + name + modality (Presencial · Smart Fit / Online). Shows 4 rows.
- "VENCIMIENTOS — 7 DÍAS" section: list of athletes with overdue tags (accent-colored badges: "−5 días", "−1 día", "mañana"). Shows 4 rows + "VER TODOS LOS PAGOS" link.
- "3 ALUMNOS INACTIVOS" section header with alert icon. Copy: "Sin entrenamiento desde hace 71 días. Considerá enviarle un mensaje." Action button: "REVISAR".

**Layout structure**: Left column ~60% width, right column ~40% width. Two-column grid layout replaces current single-column + MaxWidth 800 constraint.

---

## Collision Assessment

### Git log check
No prior SDD artifact exists for `coach-hub-hoy-web` in openspec. The dashboard directory currently has only 2 files: `coach_hub_dashboard_screen.dart` and `routes.dart`. No active branches touching this path were detected from the openspec archive.

### i18n Collision Risk
- The **current dashboard** (`coach_hub_dashboard_screen.dart`) already uses `AppL10n` (line 15: `import '...app_l10n.dart'`; line 108: `final l10n = AppL10n.of(context)`).
- The pagos section (`pagos_web_screen.dart`) uses hardcoded es-AR + `// i18n` comments (constraint C-6 per file comment on line 8).
- **Active i18n deferred work**: Roadmap line 14 notes "Deferred: i18n Coach Hub web (~55 keys, 5 archivos) — mini-SDD futuro cuando W1.x estabilice copy." The dashboard is ALREADY on AppL10n (migrated earlier). New KPI copy should follow the same convention: hardcoded es-AR + `// i18n` comment on each string (matching pagos pattern for new web files), OR continue with AppL10n since the existing dashboard already uses it.
- **Recommendation**: For the new KPI strip + cards file(s), follow the EXISTING dashboard's AppL10n pattern (not pagos's hardcoded pattern), since the dashboard already has l10n plumbing. The i18n mini-SDD is deferred and would migrate both files together later.
- **Risk**: If the i18n mini-SDD lands concurrently (unlikely — marked as future), it would touch the same file. Low collision risk.

---

## Approaches

| Approach | Pros | Cons | Complexity |
|---|---|---|---|
| **A — In-place replacement** (rewrite `CoachHubDashboardScreen`, keep same file) | One file, no routing changes, section contract unchanged | Large diff (750+ lines replaced) — may exceed 400-line PR budget | Medium |
| **B — KPI screen + keep link-management** (new `_KpiStrip` widget + `_SesionesHoyCard` etc. at top; existing link sections stay below) | Smaller diff, additive, existing behavior not disturbed | Doesn't match the mockup (which replaces the link list with a two-column layout) | Low |
| **C — New file + delegate** (extract `_KpiStrip` + `_DashboardHoyCard` widgets to separate files; `CoachHubDashboardScreen` becomes composition root) | Clean separation, reviewable PR slices | Needs extra file coordination; no functional change justifies the structure | Medium |

**Recommendation: Approach A with chained PRs.**
- PR1: KPI strip + two-column layout scaffold (new layout structure, no data wired yet).
- PR2: Wire the 4 data-ready KPIs (sesiones hoy, pendientes, vencimientos, activos count).
- PR3: Adherencia + inactivos (with new derived providers if approved for V1).

This keeps each PR under the 400-line budget and preserves a working state at each merge.

---

## V1 Scope Recommendation

### Ship in V1 (data-ready, no new providers needed)
1. **KPI strip tile — Alumnos activos**: `trainerLinksStreamProvider.where(active).length` — trivial.
2. **KPI strip tile — Ingreso del mes**: already in `PagosKpiRow` via `pagosBucketsProvider` — reuse.
3. **KPI strip tile — Por cobrar (ARS + vencimientos count)**: `pagosBucketsProvider.vencidos.length` + `pagosPorCobrarProvider` total — ready.
4. **Pendientes card**: `trainerLinksStreamProvider.where(pending)` — ready + keep mutation logic.
5. **Sesiones hoy card (count + PRÓXIMAS list)**: `trainerAppointmentsStreamProvider` + `dashboardDayCounts()` + `trainedTodayProvider` — all ready.
6. **Vencimientos card (7-day list)**: `pagosBucketsProvider.vencidos` filtered to ≤7 days — ready.
7. **Two-column layout**: pure layout change, no data dependency.
8. **Welcome card header**: `userProfileProvider` — ready.

### Defer to V1.1 (requires new derived providers)
1. **Adherencia promedio (aggregate)**: No aggregate provider. Requires per-athlete fan-out of `ResumenMetrics` + averaging. The circular chart and trend line add visual complexity. **Flag as GAP.**
2. **Inactivos card**: Requires "no session in last N days" derivation per active athlete. New provider needed (low complexity, mirrors `trainedTodayProvider` pattern but with a configurable day window). **Flag as NEW PROVIDER needed.**
3. **Pendientes de HOY alert board**: The mockup's notification-style rows (messages, workout completions, pain reports) imply a notification/activity feed aggregator — no existing provider for this composite. The current dashboard has no equivalent. **Flag as COMPLEX GAP — defer to separate SDD.**
4. **Adherencia line chart (28-day trend)**: Needs per-athlete time-series aggregation. **Defer.**

---

## Open Questions for Proposal

1. **Two-column layout breakpoint**: The current dashboard uses `maxWidth: 800`. The mockup's two-column layout looks designed for 1200+ px. Should the redesign be responsive (stacked on narrow web) or desktop-only?
2. **Preserve link-management sections?**: The active/paused/historial student tiles with mutation actions (Pausar, Terminar, Reanudar) currently live in this screen. Does the redesign REMOVE them entirely (user goes to Alumnos section for management) or keep them below the KPI strip?
3. **Inactivos definition**: What is the day threshold for "inactivo"? Mockup copy says 71 days but that looks like demo data. Is 14 days a reasonable default? Should it be configurable?
4. **Adherencia scope for V1**: Accept "--" placeholder for adherencia aggregate (deferred), or ship V1 without the adherencia tile entirely?
5. **"Pendientes de HOY" alert board**: Is this the mockup's LEFT column notification list (aggregate of messages + workouts + pain reports + pagos)? If so, this is a major feature requiring a new notification/activity aggregation system — not a "pure presentation re-layout". Needs separate SDD.

---

## Affected Files

- `lib/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart` — primary rewrite target
- `lib/features/coach_hub/presentation/sections/dashboard/routes.dart` — no change expected
- `lib/features/coach/application/trained_today_provider.dart` — read-only; reused for sesiones hoy detail list
- `lib/features/coach/application/agenda_providers.dart` — read-only; `trainerAppointmentsStreamProvider` reused
- `lib/features/coach/application/trainer_link_providers.dart` — read-only; `trainerLinksStreamProvider` reused
- `lib/features/payments/application/pagos_por_cobrar_provider.dart` — read-only; reused for por cobrar KPI
- `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart` — read-only; reused for vencimientos KPI
- `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_kpi_row.dart` — pattern reference (KpiTile widget can be extracted/reused)
- NEW (if V1.1 scope approved): a `inactivos_provider.dart` or similar derived provider

---

## Recommendation

Execute Approach A with 3 chained PRs. V1 scope ships 6 of the 8 mockup sections with zero new providers. Defer adherencia aggregate and inactivos to V1.1 (each needs a new derived provider). Defer the "Pendientes de HOY" notification board entirely — it is NOT a pure re-layout, it is a new notification aggregation system.

### Ready for Proposal
Yes — with scope clearly split between V1 (data-ready) and V1.1 (new derivations needed). The proposal should document the inactivos provider design and decide on the adherencia strategy before spec.

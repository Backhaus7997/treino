# Proposal: Coach Hub Web — Pagos Section (W4.2)

## Intent

The `/pagos` route (NEGOCIO group) is a `ProximamenteScreen` placeholder. Trainers manage billing today only from each athlete's detail; there is no trainer-wide payment view on web. This change ships a manual payment-tracking section with a WhatsApp reminder, closing Fase W4.2 of the master web plan. No payment gateway.

## Scope

### In Scope
- `/pagos` section screen replacing the placeholder — trainer-wide payments grouped in 4 tabs.
- Tabs: **Vencidos** (`status==pending AND createdAt < current-period start`), **Por vencer** (`pagosPorCobrarProvider`), **Pagados** (`status==paid`), **Todos** (all).
- KPI row: Ingreso del mes (paid this month), Pendiente cobrar (Por vencer sum), Vencido (Vencidos sum). Proyectado only if trivially client-side.
- Row actions: **Marcar pagado** (writes Firestore) and **Recordar** (WhatsApp).
- WhatsApp reminder via `url_launcher` → `wa.me/?text=<monto + concepto + paymentAlias>`; trainer picks contact manually.
- Extract reusable private widgets/formatters from `alumno_detail_screen.dart` into a shared `pagos/widgets/` location with NO behavior change.
- Register `pagosSidebarItems` in `sections/pagos/routes.dart`, replacing the ProximamenteScreen route.

### Out of Scope
- Mercado Pago / any payment gateway.
- Storing athlete phone number.
- Auto-detecting missed recurring charges (needs a Cloud Function).
- Month selector (V2).
- CSV "Exportar" (V2).

## Capabilities

### New Capabilities
None — this is a presentation-layer feature reusing existing domain/data providers. No new spec-level behavior.

### Modified Capabilities
None — `Payment` domain, providers, repository, and Firestore rules are unchanged.

## Approach

Reuse-first, zero new backend. `trainerPaymentsProvider` (all payments for the current trainer) is the primary stream; `pagosPorCobrarProvider` feeds "Por vencer". **Vencido derivation (Approach B, data-driven)**: a payment is Vencido when `status==pending AND createdAt < start of current period` — no `dueDate` field, no Cloud Function, no composite index.

**Reuse via extraction** (from `alumno_detail_screen.dart`, all `_`-prefixed → moved, `alumno_detail` re-imports):

| Item | Lines |
|------|-------|
| `_RegistrarPagoDialog` | 1311-1401 |
| `_EstadoCuentaCard` | 1073-1194 |
| `_PagosTable` | 1403-1485 |
| `_marcarPagado` | 1221-1276 |
| `_registrarPago` | 1278-1309 |
| `_fmtArs` / `nextDueDate` / `fmtDayMonth` | 934-986 |

**Section contract (ADR-CHW-005)**: `ConsumerStatefulWidget`, NO Scaffold/SafeArea (shell provides), showDialog/AlertDialog only, es-AR strings hardcoded + `// i18n`, `AppPalette.of(context)`.

**Delivery = 2 chained PRs** (ask-on-risk; total likely >400 lines):
- **PR1** — widget-extraction refactor: pure move to `pagos/widgets/`, `alumno_detail_screen.dart` stays green, tests pass. ~250-350 lines (mostly moves).
- **PR2** — `/pagos` screen + KPI row + 4 tabs + WhatsApp + sidebar registration. ~300-400 lines.

Each slice targets ≤400 changed lines.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `sections/pagos/pagos_web_screen.dart` | New | Section screen: KPIs + tabs + table (PR2) |
| `sections/pagos/widgets/` | New | Extracted dialog/table/helpers + KPI row (PR1+PR2) |
| `sections/pagos/routes.dart` | Modified | Replace ProximamenteScreen with real screen (PR2) |
| `sections/alumnos/alumno_detail_screen.dart` | Modified | Import extracted widgets; no behavior change (PR1) |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Extraction regresses `alumno_detail` | Med | Pure move, no logic change; run existing tests + `flutter analyze` before PR1 merges |
| Vencido derivation misses uncharged recurring periods | Med | Documented out-of-scope (needs CF); V1 only surfaces existing pending docs |
| PR2 exceeds 400 lines | Med | Chained delivery; split KPI/table widgets already extracted in PR1 |

## Rollback Plan

Per-PR revert. PR2 revert restores the ProximamenteScreen route (placeholder returns). PR1 revert restores private widgets inline in `alumno_detail_screen.dart`. No data migration, no backend change — nothing to roll back server-side.

## Dependencies

- `url_launcher: ^6.3.0` (already in pubspec).
- Existing providers: `trainerPaymentsProvider`, `pagosPorCobrarProvider`. No new dependency.

## Success Criteria

- [ ] `/pagos` renders the trainer's payments grouped in 4 tabs (Vencidos, Por vencer, Pagados, Todos).
- [ ] Marcar pagado writes to Firestore and the mobile app reflects the change.
- [ ] Registrar pago opens the extracted dialog and persists via `repo.add`.
- [ ] Recordar opens `wa.me/?text=` with templated monto + concepto + paymentAlias.
- [ ] Sidebar item is live (placeholder route replaced).
- [ ] `flutter analyze` returns 0 issues and existing tests are green after both PRs.
- [ ] `alumno_detail_screen.dart` behaves identically after PR1 (no regression).

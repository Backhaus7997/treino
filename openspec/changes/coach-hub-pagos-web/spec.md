# Spec — coach-hub-pagos-web

**Change**: `coach-hub-pagos-web`
**Fase / Etapa**: Fase W4.2
**Artifact store**: `hybrid`
**TDD**: Strict — widget tests written BEFORE each widget in the apply phase.

---

## Overview

Pure **presentation-layer** change. The Payment domain (`Payment`, `PaymentStatus`), `trainerPaymentsProvider`, `pagosPorCobrarProvider`, `payment_repository.dart`, and Firestore rules are NOT modified. This spec captures only what must be true in the UI after the change lands: the `/pagos` section screen, its KPI row, its 4-tab payment table, row actions, and the sidebar wire.

Domain capability delta: **None**.

---

## Requirements

---

### REQ-PAGW-ROUTE-001 — `/pagos` route renders `PagosWebScreen`, not `ProximamenteScreen`

`sections/pagos/routes.dart` MUST register `PagosWebScreen` as the widget for the `/pagos` route. `ProximamenteScreen` MUST NOT appear in the pagos route definition after this change.

#### Scenarios

- GIVEN the router is built WHEN the `/pagos` route is resolved THEN the widget tree contains `PagosWebScreen` and no `ProximamenteScreen`.
- GIVEN a trainer navigates via the sidebar Pagos item WHEN the route resolves THEN `PagosWebScreen` is rendered (no placeholder).

---

### REQ-PAGW-SHELL-001 — `PagosWebScreen` honors the section contract (no Scaffold, no SafeArea)

`PagosWebScreen` MUST be a `ConsumerStatefulWidget`. It MUST NOT introduce `Scaffold`, `SafeArea`, or `AppBackground` anywhere in its subtree. The shell provides those layers (ADR-CHW-005). It MUST use `AppPalette.of(context)` for all colors. No HEX literal color constants in any new file under `sections/pagos/`.

#### Scenarios

- GIVEN `PagosWebScreen` is pumped inside `MaterialApp(home: Scaffold(body: PagosWebScreen()))` WHEN the tree is inspected THEN `find.byType(Scaffold)` finds exactly one (the outer test wrapper) and `find.byType(SafeArea)` finds zero inside `PagosWebScreen`'s subtree.
- GIVEN any new file under `sections/pagos/` WHEN `grep` for HEX literals (`#[0-9A-Fa-f]{3,8}`) is run on source THEN zero matches.

---

### REQ-PAGW-SHELL-002 — Section header and "Registrar pago" action

`PagosWebScreen` MUST render a section header with text `"PAGOS"` and a primary action button labeled `"+ Registrar pago"`. Tapping `"+ Registrar pago"` MUST open the `RegistrarPagoDialog` via `showDialog`/`AlertDialog`. No bottom sheets.

#### Scenarios

- GIVEN `PagosWebScreen` is pumped with `trainerPaymentsProvider` overridden to `AsyncData([])` WHEN the tree is inspected THEN `find.text('PAGOS')` finds at least one widget and `find.text('+ Registrar pago')` finds one widget.
- GIVEN the screen is pumped WHEN `tester.tap(find.text('+ Registrar pago'))` and `pumpAndSettle()` THEN `find.byType(AlertDialog)` finds one widget.

---

### REQ-PAGW-KPI-001 — KPI row shows Ingreso del mes, Pendiente cobrar, Vencido

The screen MUST render a KPI row containing exactly three tiles: **"Ingreso del mes"** (sum of `amountArs` for `status==paid` payments in the current calendar month), **"Pendiente cobrar"** (sum of `amountArs` for Por vencer payments from `pagosPorCobrarProvider`), and **"Vencido"** (sum of `amountArs` for Vencidos payments). Values MUST be formatted as `$X.XXX` (es-AR, no decimals). All derivations are client-side; no new Firestore query or Cloud Function.

#### Scenarios

- GIVEN payments `[paid($10000, thisMonth), paid($5000, lastMonth), pending-vencido($3000), pending-por-vencer($8000)]` WHEN KPI row is rendered THEN "Ingreso del mes" shows `$10.000`, "Pendiente cobrar" shows `$8.000`, "Vencido" shows `$3.000`.
- GIVEN `trainerPaymentsProvider` emits `AsyncData([])` WHEN KPI row is rendered THEN all three tiles show `$0`.

---

### REQ-PAGW-TAB-001 — 4 tabs with mutually exclusive grouping

The screen MUST render exactly 4 tabs: **Vencidos**, **Por vencer**, **Pagados**, **Todos**. A `Payment` MUST belong to exactly one of the first three groups — no overlap between Vencidos and Por vencer.

| Tab | Filter rule |
|-----|-------------|
| Vencidos | `status == pending` AND `createdAt < currentPeriodStart` |
| Por vencer | `pagosPorCobrarProvider` current-period pending (status == pending AND createdAt >= currentPeriodStart) |
| Pagados | `status == paid` |
| Todos | all payments |

#### Scenarios

- GIVEN payments `[A: pending+old, B: pending+current, C: paid]` WHEN tabs are inspected THEN Vencidos tab contains only A, Por vencer tab contains only B, Pagados tab contains only C, Todos tab contains A+B+C.
- GIVEN payment X with `status==pending` AND `createdAt < currentPeriodStart` THEN X appears in Vencidos and NOT in Por vencer (mutual exclusion).
- GIVEN `trainerPaymentsProvider` emits `AsyncData([])` WHEN any tab is selected THEN an empty-state widget (non-crashing, descriptive text) is rendered for that tab.

---

### REQ-PAGW-TAB-002 — Tab badge shows payment count

Each tab label MUST display the count of payments belonging to that group as a badge or parenthetical (e.g. `"Vencidos · 3"`). Count updates reactively as the provider stream changes.

#### Scenarios

- GIVEN 2 vencidos, 5 por vencer, 16 pagados WHEN tabs render THEN tab labels show `"Vencidos · 2"`, `"Por vencer · 5"`, `"Pagados · 16"`, `"Todos · 23"` (or equivalent count display).

---

### REQ-PAGW-TABLE-001 — Payments table columns

Each active tab MUST render a `PagosTable` widget with exactly 6 columns: **Alumno** (athlete display name), **Concepto/Plan** (payment `concept`), **Monto** (`amountArs` formatted es-AR), **Vencimiento** (formatted date — `fmtDayMonth(createdAt)` or next-due derivation via `nextDueDate`), **Estado** (chip: `"Pagado"` / `"Pendiente"` / `"Vencido"`), **Acciones** (row action buttons).

#### Scenarios

- GIVEN a `PagosTable` pumped with one paid payment (Alumno: "Ana", Concept: "Plan mensual", Amount: 15000, paid this month) WHEN inspected THEN `find.text('Ana')` finds one, `find.text('Plan mensual')` finds one, `find.text('$15.000')` finds one, `find.text('Pagado')` finds one.
- GIVEN a payment with `status==pending` WHEN Estado cell is inspected THEN it shows either `"Pendiente"` or `"Vencido"` (not `"Pagado"`).

---

### REQ-PAGW-ACTION-001 — "Marcar pagado" persists via repository and updates UI reactively

Each row with `status == pending` MUST show a `"Marcar pagado"` action button. Tapping it MUST open an `AlertDialog` for confirmation. On confirm, it MUST call `paymentRepository.markManyPaid` (or `markPaid`) for that payment. On success, the payment's `status` becomes `paid` and the row moves from Por vencer/Vencidos to Pagados reactively via the provider stream. `showDialog`/`AlertDialog` only — no bottom sheets.

#### Scenarios

- GIVEN a Por vencer payment row WHEN `"Marcar pagado"` is tapped and the dialog is confirmed THEN `paymentRepository.markManyPaid` is called with that payment's ID, the row disappears from Por vencer, and appears in Pagados.
- GIVEN a Vencidos payment row WHEN `"Marcar pagado"` is tapped and the dialog is confirmed THEN the row disappears from Vencidos and appears in Pagados.
- GIVEN the confirmation dialog is dismissed (cancel) THEN no repository call is made and the row remains in its original tab.

---

### REQ-PAGW-ACTION-002 — "Recordar" opens WhatsApp `wa.me/?text=` with templated message

Each payment row MUST show a `"Recordar"` action button. Tapping it MUST call `url_launcher.launchUrl` with a URL of the form `https://wa.me/?text=<encoded message>`. The message MUST include: the payment `amountArs` (formatted es-AR), the payment `concept`, and the trainer's `paymentAlias` (from `UserProfile`). The trainer selects the recipient manually in WhatsApp. No athlete phone number is included or stored.

#### Scenarios

- GIVEN a payment (amount: 12000, concept: "Plan semanal") and trainer paymentAlias "alias.trainer" WHEN `"Recordar"` is tapped THEN `launchUrl` is called with a URL starting `https://wa.me/?text=` containing `"$12.000"`, `"Plan semanal"`, and `"alias.trainer"`.
- GIVEN trainer `paymentAlias` is null WHEN `"Recordar"` is tapped THEN the URL is still valid (omits alias or substitutes empty string); no crash.
- GIVEN the URL is launched THEN the trainer sees WhatsApp with the pre-filled message and selects the contact themselves.

---

### REQ-PAGW-REGISTRAR-001 — "Registrar pago" dialog adds a payment via repository

`RegistrarPagoDialog` (extracted from `alumno_detail_screen.dart`) MUST collect `amount` (int, ARS) and `concept` (String). On confirm, it MUST call `paymentRepository.add(...)` with the provided values and the current trainer ID. The new payment appears in the appropriate tab reactively via `trainerPaymentsProvider`. On cancel, no write occurs.

#### Scenarios

- GIVEN the dialog is open WHEN amount=20000 and concept="Plan mensual" are entered and confirm is tapped THEN `paymentRepository.add` is called with `amountArs=20000`, `concept="Plan mensual"`, `trainerId=<currentTrainerId>`, `status=pending`.
- GIVEN the dialog is open WHEN cancel is tapped THEN no repository call is made.
- GIVEN the dialog completes successfully WHEN the payments stream updates THEN the new payment appears in the Por vencer or Vencidos tab according to grouping rules.

---

### REQ-PAGW-EMPTY-001 — Empty state per tab

When a tab has zero payments, a non-crashing, informative empty-state widget MUST be displayed. The empty-state text MUST be tab-specific (e.g., `"No hay pagos vencidos"`, `"No hay pagos pendientes"`, `"No hay pagos registrados"`, `"No hay pagos"` for Todos).

#### Scenarios

- GIVEN `trainerPaymentsProvider` emits `AsyncData([])` WHEN the Vencidos tab is selected THEN `find.text('No hay pagos vencidos')` (or equivalent) finds one widget and no exception is thrown.
- GIVEN same empty state WHEN each of the 4 tabs is selected THEN a non-empty text widget is found in each (no blank white space).

---

### REQ-PAGW-ROLE-001 — Non-trainer roles do not access `/pagos`

The `/pagos` route MUST remain gated to the `trainer` role. Athletes navigating to `/pagos` MUST receive the same not-allowed treatment as the existing role gate (no change to existing gate logic — this requirement documents the invariant).

#### Scenarios

- GIVEN an authenticated user with `role == athlete` WHEN `/pagos` is navigated to THEN `PagosWebScreen` is NOT rendered and the existing role-gate widget or redirect is shown.
- GIVEN an authenticated user with `role == trainer` WHEN `/pagos` is navigated to THEN `PagosWebScreen` is rendered.

---

### REQ-PAGW-EXTRACT-001 — Widget extraction from `alumno_detail_screen.dart` is behavior-preserving (PR1)

The widgets and helpers extracted from `alumno_detail_screen.dart` (`RegistrarPagoDialog`, `EstadoCuentaCard`, `PagosTable`, `_marcarPagado`, `_registrarPago`, `_fmtArs`, `nextDueDate`, `fmtDayMonth`) to `sections/pagos/widgets/` MUST NOT change the behavior of `alumno_detail_screen.dart`. After extraction, `alumno_detail_screen.dart` MUST re-import them; all existing tests and `flutter analyze` MUST pass unchanged.

#### Scenarios

- GIVEN PR1 is applied (extraction only) WHEN `flutter analyze` runs THEN 0 issues.
- GIVEN PR1 is applied WHEN all existing tests for `alumno_detail_screen` run THEN all pass (green).
- GIVEN `alumno_detail_screen.dart` after extraction WHEN pumped in its existing test harness THEN the rendered output is pixel/semantically identical to pre-extraction.

---

## Out of Scope (recorded for traceability)

| Item | Reason |
|---|---|
| Mercado Pago / any payment gateway | Out of scope for W4.2 |
| Storing athlete phone number | Not in `UserPublicProfile`; V2 decision |
| Auto-detecting uncharged recurring periods | Requires Cloud Function; V2 |
| Month selector | V2 |
| CSV export | V2 |
| `Proyectado mes` KPI | V2 (non-trivial derivation) |

---

## Coverage Matrix

| REQ | Happy path | Edge / empty | Error / cancel |
|---|---|---|---|
| ROUTE-001 | Scenario 1 | — | — |
| SHELL-001 | Scenario 1 | — | — |
| SHELL-002 | Scenario 1+2 | — | — |
| KPI-001 | Scenario 1 | Scenario 2 (empty) | — |
| TAB-001 | Scenario 1 | Scenario 3 (empty state) | — |
| TAB-002 | Scenario 1 | — | — |
| TABLE-001 | Scenario 1 | Scenario 2 (pending states) | — |
| ACTION-001 | Scenario 1+2 | — | Scenario 3 (cancel) |
| ACTION-002 | Scenario 1 | Scenario 2 (null alias) | — |
| REGISTRAR-001 | Scenario 1+3 | — | Scenario 2 (cancel) |
| EMPTY-001 | — | Scenario 1+2 | — |
| ROLE-001 | Scenario 2 (trainer) | — | Scenario 1 (athlete) |
| EXTRACT-001 | Scenario 1+2+3 | — | — |

---

## Files this spec covers

| File | REQs |
|---|---|
| `sections/pagos/routes.dart` | ROUTE-001 |
| `sections/pagos/pagos_web_screen.dart` | SHELL-001, SHELL-002, KPI-001, TAB-001, TAB-002, ROLE-001 |
| `sections/pagos/widgets/pagos_kpi_row.dart` | KPI-001 |
| `sections/pagos/widgets/pagos_table.dart` | TABLE-001 |
| `sections/pagos/widgets/registrar_pago_dialog.dart` | REGISTRAR-001 |
| `sections/pagos/widgets/marcar_pagado_helpers.dart` | ACTION-001 |
| `sections/alumnos/alumno_detail_screen.dart` | EXTRACT-001 |
| `test/features/coach_hub/pagos/pagos_web_screen_test.dart` | SHELL-001, SHELL-002, TAB-001, TAB-002, KPI-001, ROLE-001 |
| `test/features/coach_hub/pagos/widgets/pagos_kpi_row_test.dart` | KPI-001 |
| `test/features/coach_hub/pagos/widgets/pagos_table_test.dart` | TABLE-001 |
| `test/features/coach_hub/pagos/widgets/registrar_pago_dialog_test.dart` | REGISTRAR-001 |
| `test/features/coach_hub/pagos/widgets/marcar_pagado_test.dart` | ACTION-001 |

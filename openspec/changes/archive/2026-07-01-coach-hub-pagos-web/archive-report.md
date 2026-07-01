# Archive Report: coach-hub-pagos-web

**Date Archived**: 2026-07-01
**Change**: coach-hub-pagos-web (Fase W4.2)
**Project**: treino
**Status**: COMPLETE — 3 PRs merged to main, all requirements shipped

---

## Executive Summary

The `/pagos` section for Coach Hub web is fully implemented and merged. Trainers now have a trainer-wide payment tracking interface with 4 tabs (Vencidos, Por vencer, Pagados, Todos), KPI row, per-row actions to mark payments as paid, and chat-based payment reminders (via in-app chat, not WhatsApp). All 13 requirements from the spec are shipping. The change has been delivered as 3 chained PRs: PR1 (widget extraction, #224), PR2a (screen + data, #226), PR2b (table + actions, #231). Zero code files touched outside the presentation layer. Implementation aligns with the Coach Hub section contract (no Scaffold/SafeArea, AppPalette colors, es-AR strings, showDialog only).

---

## Artifact Traceability

### Engram Observations (SDD Artifacts)

| Artifact | ID | Status | Notes |
|---|---|---|---|
| `sdd/coach-hub-pagos-web/proposal` | #127 | Complete | Proposal: Coach Hub Web — Pagos Section (W4.2); intent, scope, approach, risks |
| `sdd/coach-hub-pagos-web/spec` | #128 | Complete | 13 requirements (REQ-PAGW-*) covering route, shell, KPI, tabs, table, actions, extraction |
| `sdd/coach-hub-pagos-web/design` | #129 | Complete | Architectural decisions: widget extraction location, Vencido boundary, provider wiring, KPI formulas, chat reminder, 3-PR delivery |
| `sdd/coach-hub-pagos-web/tasks` | #130 | Complete | Work breakdown: PR1 extraction, PR2a screen+data, PR2b table+actions; all tasks done |
| `sdd/coach-hub-pagos-web/apply-progress` | #131 | Complete | Implementation log: 3 PRs merged (#224, #226, #231); 134 tests passing; learn: chat reminder superseded WhatsApp |

---

## Merged Pull Requests

### PR #224 — Widget Extraction (PR1)
- **Scope**: Pure refactor; extracted `_RegistrarPagoDialog`, `_EstadoCuentaCard`, `_PagosTable`, `_marcarPagado`, `_registrarPago`, `_fmtArs`, `nextDueDate`, `fmtDayMonth` from `alumno_detail_screen.dart` to `sections/pagos/widgets/`
- **Files Created**: 5 new widget files
- **Files Modified**: `alumno_detail_screen.dart` (imports added, 5 call-site renames); test import path updated
- **Tests**: All `alumno_detail_screen_test.dart` tests remained green (37+ widget tests, 2 public function tests)
- **Quality**: `flutter analyze` 0 issues, `dart format` applied, zero behavior change

### PR #226 — Section Shell + Data (PR2a)
- **Scope**: `/pagos` screen shell, KPI row (3 cards: Ingreso del mes / Pendiente cobrar / Vencido), 4-tab bucketing provider, routes wiring
- **Files Created**: 3 new widgets + 1 provider
  - `pagos_web_screen.dart` — main screen widget with tab controller, KPI row, section header
  - `pagos_buckets_provider.dart` — `PagosBuckets` class + `pagosBucketsProvider` (Vencido boundary: `createdAt < first-of-month-UTC`)
  - `pagos_kpi_row.dart` — 3-card KPI display widget
  - `routes.dart` — replaced `ProximamenteScreen` with real `PagosScreen`
- **Tests**: All new tests green, existing tests (including `sidebar_registry_test`) green (no badge added to sidebar item)
- **Quality**: `flutter analyze` 0 issues, `dart format` applied

### PR #231 — Rich Table + Row Actions (PR2b)
- **Scope**: Payments table widget with 6 columns (Alumno, Concepto, Monto, Vencimiento, Estado, Acciones), per-row actions:
  - "Marcar pagado" — calls `paymentRepository.markManyPaid`, moves row to Pagados tab
  - "Recordar" — opens in-app chat message dialog (Supersedes WhatsApp wa.me approach); message = monto + concepto + trainer's paymentAlias; delivered via `ChatRepository.sendMessage`; `notifyOnChatMessage` Cloud Function sends push
- **Files Created**: 1 new table widget
  - `pagos_web_table.dart` — rich table with athlete name resolution (batch provider), per-row actions
- **Files Modified**: `marcar_pagado_actions.dart` — added `marcarPagadoDoc`, `reminderText`, `recordar` functions
- **Tests**: 134 new tests (including chat message scenarios, Marcar pagado writes, empty states); all passing
- **Quality**: `flutter analyze` 0 issues, `dart format` applied; sidebar test trap verified (no badge)

---

## Spec Surface — Final Requirements

All 13 requirements shipped:

| REQ | Title | Status | Implementation Notes |
|---|---|---|---|
| REQ-PAGW-ROUTE-001 | `/pagos` route wired | Shipped | `PagosScreen` registered in `routes.dart`; `ProximamenteScreen` removed |
| REQ-PAGW-SHELL-001 | Section contract (no Scaffold/SafeArea) | Shipped | `ConsumerStatefulWidget`; no Scaffold/SafeArea in subtree; `AppPalette.of(context)` colors only; no HEX literals |
| REQ-PAGW-SHELL-002 | Section header + "Registrar pago" button | Shipped | Header "PAGOS" rendered; button opens `RegistrarPagoDialog` via `showDialog`/`AlertDialog` |
| REQ-PAGW-KPI-001 | KPI row (3 tiles: Ingreso/Pendiente/Vencido) | Shipped | Client-side: Ingreso (paid this month), Pendiente (from `pagosPorCobrarProvider`), Vencido (pending with old `createdAt`) |
| REQ-PAGW-TAB-001 | 4 tabs, mutually exclusive grouping | Shipped | Vencidos (pending < period-start), Por vencer (pending >= period-start), Pagados (paid), Todos (all); exactly-one-of partition |
| REQ-PAGW-TAB-002 | Tab count badges | Shipped | Each tab shows count (e.g., "Vencidos · 2") via `pagosBucketsProvider` |
| REQ-PAGW-TABLE-001 | Payments table (6 columns) | Shipped | ALUMNO·CONCEPTO·MONTO·VENCIMIENTO·ESTADO·ACCIONES |
| REQ-PAGW-ACTION-001 | "Marcar pagado" action | Shipped | Per-pending-row button; calls `repo.markManyPaid([id], now)`; row moves to Pagados reactively |
| REQ-PAGW-ACTION-002 | "Recordar" in-app chat reminder | Shipped (CHANGED) | Originally proposed WhatsApp `wa.me/?text=`; implemented as in-app chat message (trainer picks athlete in chat interface); message = monto + concepto + paymentAlias; `notifyOnChatMessage` CF sends push |
| REQ-PAGW-REGISTRAR-001 | "Registrar pago" dialog | Shipped | Extracted dialog; collects amount + concept; calls `repo.add(...)`; new payment appears in appropriate tab reactively |
| REQ-PAGW-EMPTY-001 | Empty state per tab | Shipped | Non-crashing empty-state widget with tab-specific text (e.g., "No hay pagos vencidos") |
| REQ-PAGW-ROLE-001 | Non-trainer role gate (invariant) | Shipped | `/pagos` remains gated to `trainer` role; no gate logic changed |
| REQ-PAGW-EXTRACT-001 | Widget extraction (PR1, behavior-preserving) | Shipped | Pure move; `alumno_detail` re-imports from `sections/pagos/widgets/`; all tests green; zero behavior change |

---

## Key Decision: Chat vs WhatsApp

**Original Proposal**: Recordar button → WhatsApp via `wa.me/?text=<message>` (trainer picks contact manually).

**W4.2 Implementation (PR2b)**: Recordar button → in-app chat message via `ChatRepository.sendMessage` + `notifyOnChatMessage` Cloud Function.

**Rationale**: 
- No athlete phone number required (not in `UserPublicProfile`)
- Trainer stays in-app ecosystem
- Chat message sent deterministically to trainer↔athlete chat
- Notification delivered via existing Cloud Function
- History preserved for future reference
- Zero new backend infrastructure required

**Impact on REQ-PAGW-ACTION-002**: Updated in `openspec/specs/coach-hub/spec.md` (delta spec merged to main); the delta requirement now reflects in-app chat, not WhatsApp.

---

## Known Limits & Future Upgrades

### No `dueDate` Field
- **Vencido boundary**: `status==pending AND createdAt < first-of-current-calendar-month(UTC)`
- **Gap**: Does NOT surface athletes on recurring cadences (mensual/semanal) who were never explicitly charged for a past period (because no Payment doc exists for missing periods)
- **V2 solution**: Cloud Function `generateDuePayments` to synthesize missing recurring invoices

### No Real `dueDate` or `generateDuePayments` Cloud Function
- Recurring charges are derived (not persisted as pending docs)
- Web section surfaces only explicitly-created payment docs (via "Registrar pago")
- V1 is correct for manual billing workflows; auto-generation deferred

### Tab Badge on Sidebar (Not Implemented)
- Spec requirement: "Badge wiring ... deferred to W2; Chat badge to W5; Pagos badge to W4; ..." (from coach-hub spec)
- W4.2 implements the `/pagos` section with tab counts; sidebar badge wiring is still deferred
- Tab counts live in `TabBar` inside the screen, not on the sidebar item (sidebar_registry_test.dart invariant: `badgeProvider == null`)

---

## Files Merged into Main Spec

**File**: `openspec/specs/coach-hub/spec.md`

**Merged**: Delta spec from `openspec/changes/coach-hub-pagos-web/spec.md` (13 REQ-PAGW-* requirements)

**Merge Method**: Appended as new section "Change: coach-hub-pagos-web" following the same pattern as the already-merged coach-hub-agenda-web section. All existing W1 requirements (REQ-CHW-*) and agenda requirements (REQ-AGW-*) preserved intact.

**Merged Requirements**:
- REQ-PAGW-ROUTE-001 through REQ-PAGW-EXTRACT-001 (13 total)
- Coverage matrix, file list, cross-cutting constraints, out-of-scope items, all preserved from delta spec
- Chat reminder requirement (REQ-PAGW-ACTION-002) updated to reflect in-app chat instead of WhatsApp

---

## Archive Folder Structure

**Path**: `openspec/changes/archive/2026-07-01-coach-hub-pagos-web/`

**Contents**:
- `explore.md` — Exploration artifact (gap analysis, approaches, risks)
- `proposal.md` — Proposal artifact (intent, scope, approach, delivery plan)
- `spec.md` — Spec artifact (13 requirements, scenarios, coverage matrix)
- `design.md` — Design artifact (architectural decisions, provider wiring, code-level details; updated to reflect chat vs WhatsApp)
- `tasks.md` — Tasks artifact (3 work units, all marked complete; implementation notes)
- `archive-report.md` — This file

**Original Change Folder**: `openspec/changes/coach-hub-pagos-web/` — moved to archive; no files deleted from main branches

---

## Verification Checklist

- [x] Main spec `openspec/specs/coach-hub/spec.md` updated with delta spec (all 13 REQ-PAGW-* requirements merged)
- [x] All existing coach-hub requirements (W1 + agenda) preserved in main spec
- [x] Change folder moved to archive with date prefix (2026-07-01)
- [x] All 5 SDD artifacts (explore, proposal, spec, design, tasks) archived
- [x] Archive report written with observation IDs for traceability
- [x] No code files touched (presentation layer only; no lib/features/payments/* changes)
- [x] 3 PRs verified merged (#224, #226, #231)
- [x] 134 tests passing (including regression suite for `alumno_detail`)
- [x] `flutter analyze` 0 issues (all PRs)
- [x] Section contract honored (ConsumerStatefulWidget, no Scaffold/SafeArea, AppPalette, es-AR + // i18n, showDialog)

---

## Next Steps

**None**. The change is complete and archived. The SDD cycle for `coach-hub-pagos-web` is closed.

For future work:
- V2 features (month selector, CSV export, Proyectado KPI, `generateDuePayments` CF) will be tracked in separate `/sdd-new` proposals
- Pagos badge wiring deferred per W4 plan

---

## Engram Archive Observation IDs

These artifact IDs are preserved here for historical reference and cross-session recovery:

- #127: Proposal
- #128: Spec
- #129: Design
- #130: Tasks
- #131: Apply progress

Archive report saved as Engram topic `sdd/coach-hub-pagos-web/archive-report` (this session).

# Tasks: Coach Hub Web — Pagos (W4.2)

**Change**: `coach-hub-pagos-web` · **TDD**: Strict (test task precedes its implementation task)

---

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | PR1 ~280 · PR2a ~390 · PR2b ~160 · Total ~830 |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR1 → PR2a → PR2b |
| Delivery strategy | ask-on-risk |
| Chain strategy | stacked-to-main |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| 1 | Pure widget extraction, zero behavior change | PR1 | base = main; gates: analyze 0 + format + alumno_detail tests green |
| 2a | Screen shell + buckets provider + KPI row + routes wiring | PR2a | base = PR1; gates: analyze 0 + format + new tests green |
| 2b | Rich table + row actions (Marcar pagado / Recordar) | PR2b | base = PR2a; gates: analyze 0 + format + action tests green |

---

## PR1 — Widget Extraction (pure refactor, ZERO behavior change)

Satisfies: REQ-PAGW-EXTRACT-001

### Phase 1.1 — Locate stray helpers

- [ ] 1.1.1 In `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` locate `_fmtDate` (~line 1450 context) and confirm its exact signature and whether it is used exclusively by `_PagosTable`. Record line numbers for extraction.

### Phase 1.2 — Create new widget files (empty stubs first)

- [ ] 1.2.1 Create `lib/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart` — empty library file with correct package declaration (no logic yet).
- [ ] 1.2.2 Create `lib/features/coach_hub/presentation/sections/pagos/widgets/registrar_pago_dialog.dart` — empty stub.
- [ ] 1.2.3 Create `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_table.dart` — empty stub.
- [ ] 1.2.4 Create `lib/features/coach_hub/presentation/sections/pagos/widgets/estado_cuenta_card.dart` — empty stub.
- [ ] 1.2.5 Create `lib/features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_actions.dart` — empty stub.

### Phase 1.3 — Move logic into widget files

- [ ] 1.3.1 Move `_fmtArs`(934-943) → `fmtArs`, `fmtDayMonth`(969), `nextDueDate`(974-986), `_kMesesLargos`(952-966) → `kMesesLargos`, and the resolved `_fmtDate` helper into `payment_format.dart`. No logic change.
- [ ] 1.3.2 Move `_RegistrarPagoDialog`(1313-1401) → `RegistrarPagoDialog` (public const ctor, returns `({int amount, String concept})?`) into `registrar_pago_dialog.dart`.
- [ ] 1.3.3 Move `_PagosTable`(1403-1485) → `PagosTable` into `pagos_table.dart`; ensure it imports `fmtArs` and `_fmtDate`/`fmtDate` from `payment_format.dart`.
- [ ] 1.3.4 Move `_EstadoCuentaCard`+`_EstadoCuentaCardState`(1073-1194) → `EstadoCuentaCard` into `estado_cuenta_card.dart`; preserve `_inFlight` double-tap guard verbatim (critical correctness).
- [ ] 1.3.5 Move `_marcarPagado`(1221-1276), `_paidPaymentFor`(1203-1219), `_pagoSnack`(1196-1198), `_registrarPago`(1278-1309) → `marcarPagado`, `paidPaymentFor`, `pagoSnack`, `registrarPago` into `marcar_pagado_actions.dart`; re-import `isoWeekPeriodKey` from `pagos_por_cobrar_provider.dart` (do NOT duplicate).

### Phase 1.4 — Update alumno_detail_screen.dart

- [ ] 1.4.1 Add imports for all 5 new widget files to `alumno_detail_screen.dart` using relative path `../pagos/widgets/...`.
- [ ] 1.4.2 Delete the moved definitions from `alumno_detail_screen.dart`.
- [ ] 1.4.3 Rename all call sites: `_fmtArs`→`fmtArs`, `_RegistrarPagoDialog`→`RegistrarPagoDialog`, `_PagosTable`→`PagosTable`, `_EstadoCuentaCard`→`EstadoCuentaCard`, `_marcarPagado`→`marcarPagado`, `_registrarPago`→`registrarPago`. `_PagosTab` stays.

### Phase 1.5 — Update test import path (REQ-PAGW-EXTRACT-001, SCENARIO 2)

- [ ] 1.5.1 In `test/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen_test.dart`, update the import for `nextDueDate` and `fmtDayMonth` (public group lines 1189-1244) to point to `payment_format.dart`. No assertion change.

### Phase 1.6 — Gate: analyze + format + tests (REQ-PAGW-EXTRACT-001, SCENARIO 1+2+3)

- [ ] 1.6.1 Run `flutter analyze` — must report 0 issues.
- [ ] 1.6.2 Run `dart format .` — must produce no diff.
- [ ] 1.6.3 Run `flutter test test/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen_test.dart` — all 37+ tests must pass (green).

---

## PR2a — Section Shell + Data (~365 lines)

Satisfies: REQ-PAGW-ROUTE-001, REQ-PAGW-SHELL-001, REQ-PAGW-SHELL-002, REQ-PAGW-KPI-001, REQ-PAGW-TAB-001, REQ-PAGW-TAB-002, REQ-PAGW-EMPTY-001, REQ-PAGW-REGISTRAR-001 (dialog reuse), REQ-PAGW-ROLE-001

**Base branch: PR1 merged to main.**

### Phase 2a.1 — Write pagosBucketsProvider tests FIRST (Strict TDD — RED)

- [ ] 2a.1.1 Create `test/features/coach_hub/pagos/widgets/pagos_buckets_provider_test.dart`. Write unit tests covering: (a) empty list → all buckets empty (REQ-PAGW-TAB-001 SCENARIO 3); (b) `[pending-old, pending-current, paid]` → Vencidos=[old], PorVencer=[current], Pagados=[paid], Todos=[all 3] (REQ-PAGW-TAB-001 SCENARIO 1); (c) boundary: `createdAt == periodStart` lands in PorVencer not Vencidos (mutual exclusion, REQ-PAGW-TAB-001 SCENARIO 2); (d) no payment appears in both Vencidos and PorVencer.

### Phase 2a.2 — Implement pagosBucketsProvider (GREEN)

- [ ] 2a.2.1 Create `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart` with `PagosBuckets` class and `pagosBucketsProvider` (autoDispose Provider composing `trainerPaymentsProvider` via `whenData`). Boundary: `Vencido = pending && createdAt.toUtc().isBefore(DateTime.utc(now.year, now.month, 1))`. Sort each bucket DESC by `createdAt`.

### Phase 2a.3 — Write PagosKpiRow tests FIRST (RED)

- [ ] 2a.3.1 Create `test/features/coach_hub/pagos/widgets/pagos_kpi_row_test.dart`. Test: (a) `[paid($10k, thisMonth), paid($5k, lastMonth), vencido($3k), porVencer($8k)]` → tiles show `$10.000`, `$8.000`, `$3.000` (REQ-PAGW-KPI-001 SCENARIO 1); (b) empty provider → all tiles show `$0` (REQ-PAGW-KPI-001 SCENARIO 2); (c) exactly 3 tile widgets rendered; (d) no HEX literals in source.

### Phase 2a.4 — Implement PagosKpiRow (GREEN)

- [ ] 2a.4.1 Create `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_kpi_row.dart`. Three `KpiTile` widgets: Ingreso del mes (`paidAt ?? createdAt` in current calendar month), Pendiente cobrar (`pagosPorCobrarProvider` total), Vencido (`buckets.vencidos` sum). Use `AppPalette.of(context)`, `fmtArs` from `payment_format.dart`. No HEX literals.

### Phase 2a.5 — Write PagosScreen smoke tests FIRST (RED)

- [ ] 2a.5.1 Create `test/features/coach_hub/pagos/pagos_web_screen_test.dart`. Write tests: (a) `find.text('PAGOS')` and `find.text('+ Registrar pago')` present (REQ-PAGW-SHELL-002 SCENARIO 1); (b) tap `+ Registrar pago` → `find.byType(AlertDialog)` finds one (REQ-PAGW-SHELL-002 SCENARIO 2); (c) `find.byType(Scaffold)` finds exactly 1 outer wrapper, `find.byType(SafeArea)` finds 0 inside screen (REQ-PAGW-SHELL-001); (d) 4 tabs rendered with count labels (REQ-PAGW-TAB-002 SCENARIO 1); (e) empty state text present per tab on empty provider (REQ-PAGW-EMPTY-001 SCENARIO 1+2). Override `trainerPaymentsProvider` with `AsyncData([])`. Use `desktop_pumper` helper if `test/helpers/desktop_pumper.dart` exists, otherwise inline `MaterialApp(home: Scaffold(body: screen))`.

### Phase 2a.6 — Implement PagosScreen shell (GREEN)

- [ ] 2a.6.1 Create `lib/features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart`. `ConsumerStatefulWidget` + `SingleTickerProviderStateMixin`. Tree: section header `PAGOS` + `+ Registrar pago` button (opens `RegistrarPagoDialog` via `showDialog`) + `PagosKpiRow` + `TabBar` (4 tabs with count: `Vencidos·n`, `Por vencer·n`, `Pagados·n`, `Todos`) + tab body per `IndexedStack` (tab bodies are placeholder `PagosWebTable` stubs calling empty-state in 2a, rich table wired in 2b). No `Scaffold`, no `SafeArea`, no HEX literals. Athlete names via `userPublicProfilesBatchProvider(ids.join(','))`.

### Phase 2a.7 — Wire route (REQ-PAGW-ROUTE-001)

- [ ] 2a.7.1 Edit `lib/features/coach_hub/presentation/sections/pagos/routes.dart`: replace `ProximamenteScreen` builder with `const PagosScreen()`. Add import `pagos_web_screen.dart`; drop unused `proximamente_screen.dart` import. **Do NOT add `badgeProvider` to `pagosSidebarItems`** (sidebar_registry_test invariant).

### Phase 2a.8 — Gate

- [ ] 2a.8.1 Run `flutter analyze` — 0 issues.
- [ ] 2a.8.2 Run `dart format .` — no diff.
- [ ] 2a.8.3 Run `flutter test` — `pagos_buckets_provider_test`, `pagos_kpi_row_test`, `pagos_web_screen_test` green. `sidebar_registry_test` must remain green (assert badgeProvider==null).

---

## PR2b — Rich Table + Row Actions (~160 lines)

Satisfies: REQ-PAGW-TABLE-001, REQ-PAGW-ACTION-001, REQ-PAGW-ACTION-002, REQ-PAGW-EMPTY-001 (per-tab text)

**Base branch: PR2a merged to main.**

### Phase 2b.1 — Write PagosWebTable + marcar pagado tests FIRST (RED)

- [ ] 2b.1.1 Create `test/features/coach_hub/pagos/widgets/pagos_web_table_test.dart`. Tests: (a) 6 columns present for a paid payment row: Alumno=Ana, Concepto=Plan mensual, Monto=$15.000, Vencimiento, Estado=Pagado, Acciones (REQ-PAGW-TABLE-001 SCENARIO 1); (b) pending row Estado shows `Pendiente` or `Vencido` but not `Pagado` (REQ-PAGW-TABLE-001 SCENARIO 2); (c) empty bucket → tab-specific empty-state text rendered, no exception (REQ-PAGW-EMPTY-001 SCENARIO 1+2).
- [ ] 2b.1.2 Create `test/features/coach_hub/pagos/widgets/marcar_pagado_test.dart`. Tests: (a) tap `Marcar pagado` on Por vencer row → `AlertDialog` appears; confirm → `paymentRepository.markManyPaid` called with payment id (REQ-PAGW-ACTION-001 SCENARIO 1); (b) same flow for Vencidos row (SCENARIO 2); (c) cancel dialog → repo NOT called, row remains (SCENARIO 3).

### Phase 2b.2 — Write WhatsApp URL builder tests FIRST (RED)

- [ ] 2b.2.1 Create `test/features/coach_hub/pagos/widgets/recordar_test.dart`. Tests: (a) `reminderText` with amount=12000, concept="Plan semanal", alias="alias.trainer" → string contains `$12.000`, `Plan semanal`, `alias.trainer` (REQ-PAGW-ACTION-002 SCENARIO 1); (b) null alias → string still valid, no "null" substring, no crash (SCENARIO 2); (c) empty alias → alias sentence omitted.

### Phase 2b.3 — Write RegistrarPagoDialog tests FIRST (RED)

- [ ] 2b.3.1 Create `test/features/coach_hub/pagos/widgets/registrar_pago_dialog_test.dart`. Tests: (a) enter amount=20000 + concept="Plan mensual" → confirm → `paymentRepository.add` called with correct args (REQ-PAGW-REGISTRAR-001 SCENARIO 1); (b) tap cancel → repo NOT called (SCENARIO 2); (c) invalid/empty fields → confirm disabled or validation error shown.

### Phase 2b.4 — Implement PagosWebTable (GREEN)

- [ ] 2b.4.1 Create `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_web_table.dart`. `StatelessWidget`, props: `payments`, `profiles` (map athleteId→displayName), `palette`, `onMarcarPagado`, `onRecordar`, `showActions`, `emptyLabel`. 6 columns: Alumno (name from profiles, fallback `'Alumno'`), Concepto, Monto (`fmtArs`), Vencimiento (`fmtDayMonth(createdAt)` or `nextDueDate` derivation), Estado chip (`Pagado`/`Pendiente`/`Vencido`), Acciones. Empty state: show `emptyLabel` text widget when `payments` is empty. Uses `AppPalette`, no HEX.

### Phase 2b.5 — Implement recordar helper and marcar pagado doc action (GREEN)

- [ ] 2b.5.1 Add `reminderText(Payment p, String? paymentAlias) → String` and `recordar(BuildContext, Payment, String?)` to `lib/features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_actions.dart` (or a new `recordar_action.dart`). Message template: `'Hola! Te recuerdo el pago de {concept} por {fmtArs(amount)}.'` + alias clause when non-null/non-empty. `launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication)` + try/catch + snackbar `'No pudimos abrir WhatsApp.'`.
- [ ] 2b.5.2 Add `marcarPagadoDoc(BuildContext, WidgetRef, Payment)` function (thin new action, distinct from cadence-aware `marcarPagado`): show `AlertDialog` for confirmation → on confirm call `paymentRepositoryProvider.markManyPaid([p.id], now)`.

### Phase 2b.6 — Wire PagosWebTable into PagosScreen tab bodies

- [ ] 2b.6.1 In `pagos_web_screen.dart`, replace tab-body stubs with `PagosWebTable` per tab, passing the correct bucket, `profilesMap`, `palette`, `onMarcarPagado: (p) => marcarPagadoDoc(context, ref, p)`, `onRecordar: (p) => recordar(context, p, alias)`, `showActions: tab != Pagados`, and tab-specific `emptyLabel` (`'No hay pagos vencidos'` / `'No hay pagos pendientes'` / `'No hay pagos registrados'` / `'No hay pagos'`).

### Phase 2b.7 — Gate

- [ ] 2b.7.1 Run `flutter analyze` — 0 issues.
- [ ] 2b.7.2 Run `dart format .` — no diff.
- [ ] 2b.7.3 Run `flutter test` — `pagos_web_table_test`, `marcar_pagado_test`, `recordar_test`, `registrar_pago_dialog_test` green. Full suite must remain green.

---

## Parallel vs Sequential Summary

- **1.2.1–1.2.5** can run in parallel (empty file creation).
- **1.3.1–1.3.5** must run sequentially after 1.2.x (depend on stubs existing).
- **2a.1+2a.3+2a.5** (RED tests) can be written in parallel before their GREEN tasks.
- **2a.2, 2a.4, 2a.6** must follow their respective RED tasks.
- **2a.7** can run in parallel with 2a.4–2a.6 (routes edit is independent of widget internals).
- **2b.1–2b.3** (RED tests) can be written in parallel.
- **2b.4+2b.5** (GREEN impl) can run in parallel after their tests.
- **2b.6** must follow 2b.4+2b.5.

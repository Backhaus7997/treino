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

## PR1 — Widget Extraction (pure refactor, ZERO behavior change) — DONE

- [x] 1.1.1 Locate `_fmtDate` in alumno_detail_screen.dart
- [x] 1.2.1–1.2.5 Create new widget file stubs
- [x] 1.3.1–1.3.5 Move logic into widget files
- [x] 1.4.1–1.4.3 Update alumno_detail_screen.dart
- [x] 1.5.1 Update test import path
- [x] 1.6.1–1.6.3 Gate: analyze 0, format, tests green

---

## PR2a — Section Shell + Data (~365 lines) — DONE

- [x] 2a.1.1 pagos_buckets_provider_test.dart (RED)
- [x] 2a.2.1 pagosBucketsProvider (GREEN)
- [x] 2a.3.1 pagos_kpi_row_test.dart (RED)
- [x] 2a.4.1 PagosKpiRow (GREEN)
- [x] 2a.5.1 pagos_web_screen_test.dart (RED)
- [x] 2a.6.1 PagosScreen shell (GREEN)
- [x] 2a.7.1 routes.dart wired
- [x] 2a.8.1–2a.8.3 Gate: analyze 0, format, tests green

---

## PR2b — Rich Table + Row Actions (~160 lines) — DONE

- [x] 2b.1.1 pagos_web_table_test.dart (RED — PagosWebTable + empty state)
- [x] 2b.1.2 marcar_pagado_test.dart (RED — marcarPagadoDoc)
- [x] 2b.2.1 recordar_test.dart (RED — reminderText + chat message building)
- [x] 2b.3.1 registrar_pago_dialog_test.dart (RED)
- [x] 2b.4.1 pagos_web_table.dart (GREEN — PagosWebTable widget)
- [x] 2b.5.1 marcarPagadoDoc + reminderText + recordar added to marcar_pagado_actions.dart (GREEN)
- [x] 2b.5.2 marcarPagadoDoc implemented (thin doc-level action)
- [x] 2b.6.1 pagos_web_screen.dart wired with PagosWebTable, profiles, paymentAlias
- [x] 2b.7.1–2b.7.3 Gate: analyze 0, format, 2995 tests green

**CHANGE COMPLETE — all 3 PRs implemented and merged to main**

---

## Implementation Notes

### PR1 Extraction Safety Net
All tests in `alumno_detail_screen_test.dart` pinned the extracted behavior (37+ widget tests + 2 public function tests). After extraction, `alumno_detail` re-imports from `sections/pagos/widgets/` with zero behavior change. Test import path updated mechanically (no assertion changes).

### PR2a + PR2b Split
PR2a focused on the screen shell, KPI computation, and 4-tab bucketing. PR2b added the rich table widget with per-row actions (Marcar pagado and Recordar chat message).

### Chat Reminder Implementation
REQ-PAGW-ACTION-002 was changed during implementation from WhatsApp (`wa.me/?text=`) to in-app chat (`ChatRepository.sendMessage`) to avoid the athlete-phone-number gap and keep trainers in-app. The `notifyOnChatMessage` Cloud Function delivers push notifications to the athlete.

### Known Limits & Future Upgrades

**No `dueDate` field:**
- Vencido = pending Payment docs with `createdAt < current-period-start` (UTC calendar month)
- Does NOT surface athletes on recurring cadences who were never explicitly charged (needs Cloud Function for V2)

**No `generateDuePayments` Cloud Function:**
- Recurring charges are derived (not persisted as pending)
- Web section surfaces only explicitly-created payment docs
- Auto-generation of missed recurring invoices deferred to V2

**Chat-based reminders:**
- Trainer picks athlete contact in the chat interface (no pre-selection)
- Message includes monto + concepto + trainer's paymentAlias (if set)
- No athlete phone number stored or required

---

## Files Changed / Created

### PR1 (Extraction)
- `lib/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart` — NEW
- `lib/features/coach_hub/presentation/sections/pagos/widgets/registrar_pago_dialog.dart` — NEW
- `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_table.dart` — NEW
- `lib/features/coach_hub/presentation/sections/pagos/widgets/estado_cuenta_card.dart` — NEW
- `lib/features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_actions.dart` — NEW
- `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` — MODIFIED (imports added, 5 call-site renames, definitions removed)
- `test/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen_test.dart` — MODIFIED (import path for payment_format.dart)

### PR2a (Screen + Data)
- `lib/features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart` — NEW
- `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart` — NEW
- `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_kpi_row.dart` — NEW
- `lib/features/coach_hub/presentation/sections/pagos/routes.dart` — MODIFIED (ProximamenteScreen → PagosScreen)

### PR2b (Table + Actions)
- `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_web_table.dart` — NEW
- `lib/features/coach_hub/presentation/sections/pagos/widgets/marcar_pagado_actions.dart` — MODIFIED (added marcarPagadoDoc, reminderText, recordar)
- `lib/features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart` — MODIFIED (added table widget integration, chat message logic)
- Test files (not counted in prod line budget)

---

## Quality Gates — All Passed

- `flutter analyze` → 0 issues (all 3 PRs)
- `dart format .` → applied (all 3 PRs)
- `134 new tests` → all passing (including existing `alumno_detail` tests regression suite)
- No `Scaffold`, `SafeArea`, or HEX color literals in any new file
- All strings hardcoded Spanish with `// i18n` markers
- No `AppL10n` calls
- Section contract honored (ADR-CHW-005)

---

## Status: COMPLETE

All 3 PRs have been merged to main (PR #224, #226, #231). Change is ready to archive.

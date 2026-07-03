# Proposal: Payments — Real Due Dates & First Scheduled CF (`payments-vencimientos`)

## Intent

"Vencido" is a **client-side lie today**. `pagos_buckets_provider.dart` marks any `pending` payment as overdue when `createdAt < currentMonthStart` — wrong for weekly cadence and old one-off charges, and blind to periods that were **never charged at all** (a charge that lives only in memory can never be "vencido"). We need a **real due-date model** plus the project's **first scheduled Cloud Function** to persist period charges, so overdue detection is authoritative instead of heuristic.

## Scope

### In Scope
- **Domain**: add `dueAt` (DateTime, nullable) to `Payment` + Freezed/JSON regen. Client reads it; CF sets it.
- **Vencido fix**: `pagos_buckets_provider.dart` → `pending && dueAt != null && dueAt < now`; legacy null-`dueAt` docs fall back to today's `createdAt < currentMonthStart` rule.
- **Coexistence gate**: `pagos_por_cobrar_provider.dart` skips deriving a virtual `CobroPendiente` when a persisted doc exists for `(athleteId, periodKey)` — no double-count.
- **CF `generateDuePayments`**: `onSchedule` ~03:00 ART, `southamerica-east1`. Pure handler extracted from wrapper (jest + emulator). For each active trainer↔athlete link with **mensual/semanal** billing, upsert a pending Payment (deterministic id `${trainerId}_${athleteId}_${periodKey}`, `dueAt`). Idempotent via **field** check `(trainerId, athleteId, periodKey)`; never overwrites a `paid` doc.
- **Rules**: tighten `payments` update (firestore.rules ~758) to field-level — clients cannot set/alter CF-managed `dueAt`.
- **Indexes**: `(trainerId,status,dueAt ASC)`, `(trainerId,paidAt DESC)`, `(athleteId,status,dueAt ASC)`.
- Optional `PaymentRepository.upsert(id, payment)` — design decides client-need vs CF-only.

### Out of Scope (each a future SDD)
- `notifyOverduePayments` FCM push · `dailyBillingDigest` · `waived` status · CF auto-gen for **porSesion/suelto** · backfilling `dueAt` on legacy docs.

## Capabilities

### New Capabilities
- `due-payment-generation`: scheduled CF that persists deterministic pending period charges for recurring cadences.

### Modified Capabilities
- `payments`: `Payment` gains `dueAt`; overdue derivation and update rule change behavior.

## Approach

Exploration **Approach 2**. Two chained PRs, each ≤400 lines & independently reviewable:
- **PR1 (client + infra)**: `dueAt` on `Payment` + regen · buckets Vencido fix · coexistence gate · rules tightening · 3 indexes. Ships safe with legacy fallback before any CF exists.
- **PR2 (CF + tests)**: `functions/src/payments/generate-due-payments.ts` (pure handler + `onSchedule` wrapper) · export in `index.ts` · jest emulator tests.

CF writes via Admin SDK (bypasses rules). Idempotency keyed on fields, not doc id, to catch legacy auto-id docs. First run creates **current period only** — no backfill.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/payments/domain/payment.dart` | Modified | add `dueAt` + regen |
| `.../pagos/widgets/pagos_buckets_provider.dart` | Modified | `dueAt`-based Vencido + fallback |
| `lib/features/payments/application/pagos_por_cobrar_provider.dart` | Modified | `periodKey` coexistence gate |
| `lib/features/payments/data/payment_repository.dart` | Modified? | optional `upsert` |
| `firestore.rules` (~758) | Modified | field-level payments update |
| `firestore.indexes.json` | Modified | 3 composite indexes |
| `functions/src/payments/generate-due-payments.ts` | New | scheduled CF + pure handler |
| `functions/src/index.ts` | Modified | export CF |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Double-count (virtual + real) | Med | gate on `(athleteId, periodKey)` |
| First `onSchedule` in repo | Med | pure handler + emulator tests |
| Idempotency vs legacy auto-id | Med | field check, not doc-id; never overwrite `paid` |
| Rules break `markPaid`/`markManyPaid` | Med | PR1 audits those flows before tightening |
| Deploy dependency (login expiry) | Med | user deploys manually from canonical repo |
| Legacy null-`dueAt` docs | Low | explicit fallback branch |

## Rollback Plan

- PR2: remove CF export from `index.ts`, redeploy `--only functions`; deployed docs are harmless (buckets read `dueAt`; gate suppresses dup).
- PR1: revert commit; `dueAt` nullable and additive, no migration; drop indexes optional.

## Dependencies

- User runs `firebase deploy --only functions,firestore:rules,firestore:indexes` from canonical `treino/` repo (CFs → `southamerica-east1`). DRS does **not** block scheduled CFs (only `allUsers` callables).

## Success Criteria

- [ ] CF creates deterministic pending docs with `dueAt` for **mensual + semanal** active links; excludes porSesion/suelto.
- [ ] Re-running the CF is idempotent (no dupes) and **never overwrites a `paid` doc**.
- [ ] Vencido bucket derives from `dueAt < now`; legacy null-`dueAt` docs use fallback.
- [ ] No double-count: provider suppresses virtual charge when a real period doc exists.
- [ ] jest + emulator tests green; `flutter analyze` 0 issues; rules block clients writing `dueAt`.

# Spec: payments-vencimientos

## Capability Index

| Capability | Type | Spec Location | Requirements | Scenarios |
|---|---|---|---|---|
| `due-payment-generation` | New | `specs/due-payment-generation/spec.md` | REQ-VENC-01 to REQ-VENC-08 | SCENARIO-VENC-01 to SCENARIO-VENC-07 |
| `payments` | Modified (delta) | `specs/payments/spec.md` | REQ-VENC-10 to REQ-VENC-13 | SCENARIO-VENC-08 to SCENARIO-VENC-15 |

## Out of Scope (recorded)

- FCM `notifyOverduePayments`
- `dailyBillingDigest`
- `waived` payment status
- CF auto-generation for porSesion / suelto cadences
- Backfilling `dueAt` on legacy docs
- Adding `dueDayOfMonth` to `AthleteBilling`

## PR Delivery Plan

| PR | Scope | Budget |
|---|---|---|
| PR1 | `dueAt` on Payment + Freezed regen + Vencido fix + coexistence gate + rules + 3 indexes | ≤400 lines |
| PR2 | `generateDuePayments` CF + `index.ts` export + jest/emulator tests | ≤400 lines |

Each PR is independently reviewable and shippable.

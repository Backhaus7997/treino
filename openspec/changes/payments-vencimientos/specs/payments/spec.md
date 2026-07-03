# Delta for Payments

## ADDED Requirements

### REQ-VENC-10: Payment.dueAt Field

The `Payment` domain model MUST include a nullable `dueAt` field of type `DateTime`. This field is set exclusively by the `generateDuePayments` CF via Admin SDK. Clients MUST read `dueAt` but MUST NOT write or modify it. Legacy Payment documents where `dueAt` is `null` are valid and MUST be handled by the fallback overdue rule (see REQ-VENC-12).

## MODIFIED Requirements

### REQ-VENC-11: Overdue (Vencido) Derivation

A Payment MUST be considered "Vencido" (overdue) when ALL of the following hold:
- `status == pending`
- `dueAt != null`
- `dueAt < now` (current UTC instant)

When `dueAt == null` (legacy documents), the legacy fallback MUST apply: a Payment is "Vencido" when `status == pending && createdAt < start-of-current-month`.
(Previously: Vencido used `createdAt < currentMonthStart` for all documents, ignoring actual due dates.)

#### SCENARIO-VENC-08: Vencido uses dueAt when present

- GIVEN a Payment with `status == pending`, `dueAt` set to a past date
- WHEN the overdue bucket is computed
- THEN the Payment appears in the "Vencido" bucket

#### SCENARIO-VENC-09: On-time pending payment is not Vencido

- GIVEN a Payment with `status == pending`, `dueAt` set to a future date
- WHEN the overdue bucket is computed
- THEN the Payment does NOT appear in the "Vencido" bucket

#### SCENARIO-VENC-10: Legacy null-dueAt doc uses createdAt fallback

- GIVEN a Payment with `status == pending` and `dueAt == null`, created before the start of the current month
- WHEN the overdue bucket is computed
- THEN the Payment appears in the "Vencido" bucket (legacy fallback)

#### SCENARIO-VENC-11: Legacy null-dueAt doc created this month is not Vencido

- GIVEN a Payment with `status == pending`, `dueAt == null`, `createdAt` within the current month
- WHEN the overdue bucket is computed
- THEN the Payment does NOT appear in the "Vencido" bucket

### REQ-VENC-12: Coexistence Gate — No Double-Count

`pagosPorCobrarProvider` MUST NOT derive a virtual `CobroPendiente` entry for a period when a persisted Payment document already exists for `(athleteId, periodKey)`. The check MUST use the `periodKey` field to match periods across all cadences.
(Previously: virtual charges were always derived in-memory regardless of persisted documents, risking double-count once the CF lands.)

#### SCENARIO-VENC-12: Provider skips period when real doc exists

- GIVEN a persisted Payment document exists with `athleteId == A`, `periodKey == "2026-07"`, `status == pending`
- WHEN `pagosPorCobrarProvider` computes pending charges for athlete A
- THEN no virtual `CobroPendiente` is derived for period `"2026-07"`
- AND the real Payment document is used as the authoritative charge

#### SCENARIO-VENC-13: Provider derives virtual charge when no real doc exists

- GIVEN no persisted Payment document exists for `(athleteId == A, periodKey == "2026-07")`
- WHEN `pagosPorCobrarProvider` computes pending charges for athlete A
- THEN a virtual `CobroPendiente` is derived for period `"2026-07"` as before

### REQ-VENC-13: Firestore Rules — dueAt Write Protection

The `payments` Firestore security rule for `update` MUST prevent clients from setting or altering the `dueAt` field. The existing `markPaid` and `markManyPaid` flows (which do NOT touch `dueAt`) MUST continue to succeed.
(Previously: the update rule checked trainerId + athleteId immutability only, with no field-level restriction on dueAt.)

#### SCENARIO-VENC-14: Client update that sets dueAt is rejected

- GIVEN a client is authenticated as the trainer who owns the Payment
- WHEN the client submits an update request that includes a change to `dueAt`
- THEN Firestore rejects the write with a permission-denied error

#### SCENARIO-VENC-15: markPaid update is still allowed

- GIVEN a client is authenticated as the trainer who owns the Payment
- WHEN the client submits an update request that changes only `status` to `paid` and sets `paidAt` (the standard markPaid flow)
- THEN Firestore accepts the write

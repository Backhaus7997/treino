# Exploration: payments-vencimientos

_SDD Phase: explore | Change: payments-vencimientos | Project: treino_

---

## Current State

### Payment domain (Dart)

**`lib/features/payments/domain/payment.dart` (lines 22-36)**

```dart
@freezed
class Payment with _$Payment {
  const factory Payment({
    required String id,
    required String trainerId,
    required String athleteId,
    required int amountArs,
    required String concept,
    required PaymentStatus status,   // pending | paid
    String? periodKey,               // nullable — only set on manual charges with period context
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() DateTime? paidAt,
  }) = _Payment;
}
```

Key gaps:
- NO `dueAt` / `dueDate` field. "Vencido" is entirely client-derived.
- NO `waived` status.
- NO `paymentMethodNote`, `commercialPlanId`, or `reminderSentAt`.
- `id` is always an **auto-generated Firestore ID** — not deterministic.
- `periodKey` is nullable (only set when the trainer manually includes it).

**`lib/features/payments/domain/athlete_billing.dart` (lines 27-38)**

```dart
@freezed
class AthleteBilling with _$AthleteBilling {
  const factory AthleteBilling({
    required String trainerId,
    required String athleteId,
    required int amountArs,
    required BillingCadence cadence,  // mensual | semanal | porSesion | suelto
    @TimestampConverter() required DateTime updatedAt,
  }) = _AthleteBilling;
}
```

Key gaps for CF needs:
- NO `dueDayOfMonth` — the CF will need to know which day of the month to set `dueAt` for `mensual`. Without it the CF must default (e.g. day 1).
- NO `nextDueDate` field to let the CF fast-forward without re-reading billing history.
- NO `commercialPlanId` FK.
- No `billingActiveFrom` — CF cannot know when billing started for an athlete, which affects the first period.

Doc ID for `athlete_billing` is already deterministic: `${trainerId}_${athleteId}` (per comment on line 24 and confirmed in `firestore.rules` line 701).

**BillingCadence enums**: `mensual`, `semanal`, `porSesion`, `suelto`.

### Current "Vencido" derivation

**`lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart`**

The Vencidos bucket (line 68):
```dart
if (p.createdAt.toUtc().isBefore(periodStart)) {
  vencidos.add(p);
}
```
Where `periodStart = DateTime.utc(now.year, now.month, 1)`.

This means: **any `pending` payment whose `createdAt` predates the current month start is "vencido"**. This is a best-effort heuristic — it's wrong for:
- Weekly cadence athletes (a payment created 3 weeks ago and still pending is "vencido" only because `createdAt` crossed the month boundary, not because the billing week elapsed).
- Manual one-off charges created months ago that were never paid.
- No distinction between "just created, not due yet" vs "genuinely past-due".

**`lib/features/payments/application/pagos_por_cobrar_provider.dart`** (the mobile dashboard provider)

For `mensual`: checks `any payment with status==paid && periodKey==monthKey` — if none found, surfaces a `CobroPendiente` (a virtual charge, NOT a Firestore doc). The current-period charge exists ONLY in memory; it's never persisted until the trainer manually creates a payment doc.

For `semanal`: same logic with `weekKey` (ISO week format `YYYY-Www`).

Period key formats (defined at lines 44-45):
- Monthly: `'$currentYear-${currentMonth.toString().padLeft(2, '0')}'` → e.g. `2026-07`
- Weekly: `'${_isoWeekYear(date)}-W${_isoWeekNumber(date).toString().padLeft(2, '0')}'` → e.g. `2026-W27`

For `porSesion`: counts unpaid sessions since `link.acceptedAt` or last `paidAt`. No period key — requires session history access.

For `suelto`: shows only existing `pending` payment docs.

**`lib/features/payments/application/payment_providers.dart`**

`trainerPaymentsProvider` streams ALL payments for the trainer via a single `where('trainerId', isEqualTo: trainerId)` query — no `dueAt` filter. The entire trainer payment set loads into memory for client-side partitioning.

### Payment repository

**`lib/features/payments/data/payment_repository.dart`**

- `add()` uses `_collection.doc()` → **auto-generated ID**. No deterministic-ID path exists today.
- Two stream queries: `watchForTrainer(trainerId)` and `watchForAthlete(athleteId)` — both single-field equality, no composite indexes needed today.
- No `upsert` / `set with merge` method — would need to be added to support deterministic IDs.

### Cloud Functions structure

Functions root: `treino/functions/` (sibling of `treino/lib/`)

**`functions/src/index.ts`** — registration pattern: named exports from domain-scoped files.

**Existing CF patterns found**:

1. **`onDocumentWritten`** — the dominant pattern, used by `reviewAggregate`, `cleanupAssignedPlansOnUnlink`, `notifyOnAppointment`, `notifyOnLinkChange`, `notifyOnReview`.

2. **Pattern for testability** (from `cleanup-assigned-plans.ts` and `review-aggregate.ts`):
   - Pure handler function exported separately: `export async function handlerName(app, before, after)`.
   - CF trigger is a thin wrapper calling the handler.
   - Tests use `firebase-functions-test` + Firestore emulator (FIRESTORE_EMULATOR_HOST=127.0.0.1:8080, GCLOUD_PROJECT=treino-dev).
   - Jest config: `testMatch: ["**/src/__tests__/**/*.test.ts"]`, ts-jest transform.

3. **NO scheduled CF exists yet** — `onSchedule` from `firebase-functions/v2/scheduler` has never been used in this project. It is the target primitive for `generateDuePayments`.

4. **Region**: `southamerica-east1` on every single CF. Non-negotiable.

5. **Admin SDK init pattern** (canonical, used in all CFs):
   ```typescript
   function getApp(): admin.app.App {
     try { return admin.app(); }
     catch { return admin.initializeApp(); }
   }
   ```

6. **Batch writes** for bulk deletes (BATCH_SIZE = 500 constant, from `cleanup-assigned-plans.ts`).

**File layout convention**: `functions/src/<domain>/<cf-name>.ts` for multi-file domains (e.g. `notifications/notify-appointment.ts`), single file for standalone (e.g. `review-aggregate.ts`). The payments CF should go to `functions/src/payments/generate-due-payments.ts`.

**`functions/package.json`**: `firebase-functions: ^5.0.0`, `firebase-admin: ^12.0.0`, Node 20, TypeScript 5.4, jest 29, ts-jest 29.

**`functions/tsconfig.json`**: `strict: true`, `noUnusedLocals: true`, `noImplicitReturns: true`, target ES2022, outDir `lib/`.

### Firestore rules — payments collection (lines 758-771)

```
match /payments/{paymentId} {
  allow read: if request.auth != null
              && (request.auth.uid == resource.data.trainerId
                  || request.auth.uid == resource.data.athleteId);
  allow create: if request.auth != null
              && request.resource.data.trainerId == request.auth.uid
              && request.resource.data.athleteId is string
              && request.resource.data.athleteId.size() > 0;
  allow update: if request.auth != null
              && resource.data.trainerId == request.auth.uid
              && request.resource.data.trainerId == resource.data.trainerId
              && request.resource.data.athleteId == resource.data.athleteId;
  allow delete: if request.auth != null && resource.data.trainerId == request.auth.uid;
}
```

**CF writes bypass Firestore rules entirely** — Admin SDK writes are always privileged. The `create` rule above only gates client-originated creates. This means `generateDuePayments` can write with any shape it needs, but we must still keep the rules consistent for client reads/updates.

**Critical gap**: the current `update` rule does NOT restrict which fields can change. With `dueAt` and `waived` status incoming, the proposal should tighten the update to enumerate valid transitions (pending→paid, pending→waived, any→any for non-status fields) to prevent a client from pre-marking a CF-generated doc as waived without going through the intended flow.

### Firestore indexes — current state

No `payments` index exists in `firestore.indexes.json`. Today the two queries (`trainerId ==` and `athleteId ==`) are single-field, which Firestore auto-indexes. Once we add `dueAt` + `status` composite queries (needed for the Vencidos tab and the CF's existence check), new composite indexes are required.

**Needed new indexes** (from domain plan Domain E):
```json
{ "collectionGroup": "payments", "fields": [
  { "fieldPath": "trainerId", "order": "ASCENDING" },
  { "fieldPath": "status", "order": "ASCENDING" },
  { "fieldPath": "dueAt", "order": "ASCENDING" }
]}
{ "collectionGroup": "payments", "fields": [
  { "fieldPath": "trainerId", "order": "ASCENDING" },
  { "fieldPath": "paidAt", "order": "DESCENDING" }
]}
{ "collectionGroup": "payments", "fields": [
  { "fieldPath": "athleteId", "order": "ASCENDING" },
  { "fieldPath": "status", "order": "ASCENDING" },
  { "fieldPath": "dueAt", "order": "ASCENDING" }
]}
```

### Domain plan reference (tmp/media-research/domain-plan.md, Domain E, lines 556-714)

The domain plan confirms and extends the above. Key additions from it:

- New `Payment` fields: `dueAt` (Timestamp), `waived` status, `paymentMethodNote`, `commercialPlanId`, `commercialPlanNameSnapshot`, `reminderSentAt`.
- New `AthleteBilling` fields: `dueDayOfMonth` (int, 1..28), `nextDueDate` (Timestamp), `commercialPlanId` (FK), `paymentLink` (string).
- Deterministic payment ID: `${trainerId}_${athleteId}_${periodKey}`.
- CF signature: `generateDuePayments` scheduled `0 3 * * *` ART, iterates `athlete_billing`, creates missing `payments` docs.
- `notifyOverduePayments` scheduled `0 9-21 * * *` ART, FCM push to athlete.
- `syncBillingPlanSnapshot` onWrite `athlete_billing` trigger.

### Deploy constraints

- Rules and functions deploy from `treino/` repo only (not the monorepo parent).
- The user runs `firebase deploy` with their own credentials; login can expire. All deploys are manual.
- GCP project: `treino-dev`. Org: `code-assurance.com`.
- Domain-Restricted-Sharing policy blocks publicly-invokable CFs (`allUsers` principal). Scheduled CFs are NOT publicly invokable — they are triggered by Cloud Scheduler (service account), so they are NOT blocked by DRS. This is confirmed by the shelved `resolveGymPlace` comment in `index.ts` (that one was blocked because it was callable by unauthenticated users via `allUsers`).
- `notifyOverduePayments` (FCM) involves reading athlete FCM tokens — the existing `send-fcm.ts` pattern reads from `users/{uid}.fcmToken` using Admin SDK.

---

## Affected Areas

- `lib/features/payments/domain/payment.dart` — add `dueAt`, `waived` status enum value, optional new fields; regenerate Freezed/JSON.
- `lib/features/payments/domain/athlete_billing.dart` — add `dueDayOfMonth`, `nextDueDate`, `paymentLink`, optionally `commercialPlanId`; regenerate.
- `lib/features/payments/data/payment_repository.dart` — add `upsert(Payment, id)` / `set(id, data)` method for deterministic-ID writes from client (for manual charges that should also be idempotent). Also new query methods: `watchOverdue`, `watchUpcoming`.
- `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart` — replace `createdAt < periodStart` heuristic with `dueAt != null && dueAt < now` once CF-generated docs exist. Needs a migration/coexistence strategy during rollout.
- `lib/features/payments/application/pagos_por_cobrar_provider.dart` — needs to stop emitting a `CobroPendiente` for recurring cadences WHEN a CF-generated `Payment` doc already exists for that period (to avoid double-counting).
- `firestore.rules` — extend `payments` update rule to enumerate valid status transitions; add `dueAt` + `waived` to allowed fields.
- `firestore.indexes.json` — add 3 composite indexes for `payments`.
- `functions/src/payments/generate-due-payments.ts` — new scheduled CF.
- `functions/src/payments/notify-overdue-payments.ts` — new scheduled CF (scope decision pending).
- `functions/src/index.ts` — export new CFs.

---

## Approaches

### Approach 1 — Minimal: `dueAt` field + `generateDuePayments` only

Add `dueAt` to `Payment` domain, update `pagos_buckets_provider` to use it, deploy one scheduled CF that creates period Payment docs. The client-side `pagosPorCobrarProvider` keeps running for now; the CF docs become the authoritative source and the provider skips generating a `CobroPendiente` when a CF doc already exists for that period.

- **Pros**: Smallest delta. Single CF to deploy and test. No FCM complexity. Doesn't require `commercialPlanId` FK (deferred). Idempotent by design (deterministic ID + `set({ merge: false })` or `create`).
- **Cons**: "Vencido" still partially depends on client derivation during rollout. No athlete push notification (trainer has to check manually). `pagosPorCobrarProvider` deduplication logic is subtle and risky (double-count if not carefully gated). `suelto` and `porSesion` cadences are still not covered by the CF.
- **Effort**: Medium. Dart model change + Freezed regen + repo update + 1 CF + index + rules.

### Approach 2 — Recommended: `dueAt` + `generateDuePayments` + `pagos_buckets_provider` migration + clean coexistence gate in `pagosPorCobrarProvider`

Same as Approach 1 PLUS: explicit coexistence gate in `pagosPorCobrarProvider` (skip recurring charge derivation for `mensual`/`semanal` if a Payment doc with that `periodKey` already exists), and update `pagos_buckets_provider` to use `dueAt` instead of `createdAt`.

- **Pros**: Correct separation. Client derivation becomes a fallback for `porSesion`/`suelto` only (which the CF cannot easily auto-generate anyway). Vencido bucket becomes accurate. No double-counting risk.
- **Cons**: More files touched. The coexistence gate in `pagosPorCobrarProvider` needs careful testing (mobile). Requires 2 chained PRs to be safe (Dart model + CF in one; UI + provider gate in second).
- **Effort**: Medium-High. Same as Approach 1 plus provider refactoring on mobile.

### Approach 3 — Full Domain E: Approach 2 + `notifyOverduePayments` + `AthleteBilling` extensions + `waived` status

Everything from Approach 2 PLUS FCM notifications to athletes, `dueDayOfMonth` field on billing, `waived` status, `paymentMethodNote`, `commercialPlanId` FK (if `commercial-plans` SDD has already landed).

- **Pros**: Closes the full Domain E spec. FCM notifications drive athlete action. `waived` status allows trainers to explicitly skip a period without deleting the doc.
- **Cons**: Significantly larger surface. FCM testing requires emulator setup with messaging mock (existing `send-fcm.ts` pattern). `commercialPlanId` is a hard dependency on `commercial-plans` SDD. Largest PR size — almost certainly needs chained PRs.
- **Effort**: High. Recommend splitting into Approach 2 first, then Approach 3 as a follow-up SDD.

---

## Comparison Table

| Dimension | Approach 1 | Approach 2 (Rec.) | Approach 3 |
|---|---|---|---|
| `dueAt` field + Freezed regen | Yes | Yes | Yes |
| `generateDuePayments` CF | Yes | Yes | Yes |
| Deterministic payment ID | Yes | Yes | Yes |
| Composite indexes | Yes | Yes | Yes |
| `pagos_buckets_provider` migration | No | Yes | Yes |
| `pagosPorCobrarProvider` coexistence gate | Partial | Full | Full |
| `notifyOverduePayments` CF | No | No | Yes |
| `waived` status | No | No | Yes |
| `AthleteBilling` extensions | No | No | Yes |
| `commercialPlanId` FK | No | No | Optional |
| PR size risk | Low | Medium | High |
| Chained PRs needed | Probably not | Probably 2 | 3+ |

---

## Recommendation

**Approach 2** — ship `dueAt` + `generateDuePayments` + the full provider coexistence gate as one change, split across 2 chained PRs:

- **PR 1**: Dart domain changes (`Payment`, `AthleteBilling` minimal extensions), `PaymentRepository.upsert()`, `firestore.rules` update, `firestore.indexes.json` update.
- **PR 2**: `functions/src/payments/generate-due-payments.ts` + export in `index.ts` + `pagos_buckets_provider` migration + `pagosPorCobrarProvider` coexistence gate + tests.

Defer `notifyOverduePayments` and `waived` to a follow-up SDD (`payments-notifications`). Defer `commercialPlanId` until `commercial-plans` SDD is done.

---

## Risks

1. **Double-counting during rollout**: while the CF has not yet generated docs for a given period, `pagosPorCobrarProvider` still derives a `CobroPendiente`. After the CF creates the doc, the provider must detect and suppress the derived entry. The gate must check `periodKey` match, not just `status==pending` — wrong gate = two charges shown for same period.

2. **`porSesion` and `suelto` cadences NOT covered by CF**: the CF can only auto-create docs for `mensual` and `semanal`. `porSesion` remains event-driven (tied to session count) and `suelto` is ad-hoc. These two cadences should be explicitly excluded from `generateDuePayments` to avoid creating zero-amount docs.

3. **`onSchedule` is new to this codebase**: no existing pattern, no existing test. The handler must be extracted as a pure function (matching `reviewAggregate`/`cleanup-assigned-plans` pattern) so it can be tested against the Firestore emulator without the scheduler trigger.

4. **Firestore rules tightening**: the current `payments` update rule is too permissive (any field can change as long as `trainerId` + `athleteId` are immutable). Tightening to explicit status transitions may break existing client flows if the client sends unexpected fields — needs audit of `markPaid` and `markManyPaid` in `PaymentRepository`.

5. **Idempotency edge case**: if `generateDuePayments` runs while a trainer manually creates a Payment for the same period (with the same `periodKey` but auto-id), there will be TWO docs for the same period — the manual one (auto-id) and the CF one (deterministic id). The provider and UI must tolerate duplicates gracefully, OR the manual-create flow must be migrated to use the deterministic ID format.

6. **DRS policy does not block scheduled CFs** (confirmed from `index.ts` comment — only publicly-invokable/`allUsers` CFs are blocked). But the user's Firebase login credential expiry is a deploy risk — all deploys remain manual.

7. **`dueDayOfMonth` default**: without the field on `AthleteBilling`, the CF must hardcode day 1 for mensual vencimientos. This is acceptable for v1 but creates a migration cost if trainers later want a different billing day.

---

## Scope Questions for Proposal

1. **Minimal viable vs full Domain E**: Should `payments-vencimientos` scope to Approach 2 (dueAt + CF + provider gate) and defer notifications + waived status? Or ship Domain E fully in one change?

2. **`pagosPorCobrarProvider` fate**: once CF docs exist for all active athletes, the provider's recurring-charge derivation becomes redundant for `mensual`/`semanal`. Long-term plan: keep the provider as fallback (shows derived charge if no CF doc exists yet) or remove the derivation entirely? The safest path is a permanent coexistence gate.

3. **Deterministic ID migration**: existing manual `Payment` docs all have auto-ids. Should the CF write its docs with the deterministic ID format `${trainerId}_${athleteId}_${periodKey}` while leaving old docs untouched? Yes — but the duplicate detection logic in the CF must query by `(trainerId, athleteId, periodKey)` fields, not by doc ID, to catch pre-existing auto-id docs for the same period.

4. **First period**: when `generateDuePayments` first runs, it should create docs for the CURRENT period (not historical). Should it also backfill overdue periods? Recommendation: no backfill — only create for the current and next period on first run.

5. **`notifyOverduePayments` dependency**: this CF reads athlete FCM tokens. Does the notification belong in this SDD or in a future `payments-notifications` change?

---

## Ready for Proposal

Yes — the codebase is well-understood. Approach 2 is the clear recommendation. Open questions above need a quick scope decision from the user before the proposal can be written (primarily: full Domain E vs Approach 2 slice, and notification deferral).

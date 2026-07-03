# Design: Payments — Real Due Dates & First Scheduled CF (`payments-vencimientos`)

## Technical Approach

Add a nullable `dueAt` to `Payment`, make the Vencido bucket derive from it (legacy-safe fallback), suppress virtual/real double-counting, and introduce the repo's FIRST `onSchedule` Cloud Function to persist deterministic period charges. Ships as 2 chained PRs (Exploration Approach 2): PR1 = Dart + rules + indexes (safe with legacy fallback, no CF yet); PR2 = the CF + jest emulator tests + `index.ts` export. The CF follows the EXISTING project CF convention verbatim (v5 v2-API, `southamerica-east1`, lazy `getApp()`, pure handler over `admin.app.App`, catch+log+no-rethrow) — no new style is invented.

## Cloud Function structure (load-bearing — first `onSchedule`)

New file `functions/src/payments/generate-due-payments.ts`. Mirrors `cleanup-assigned-plans.ts` (query/logic split) and `sync-session-share.ts` (Admin write). Two-layer split for testability:

```ts
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentWritten } // pattern ref only
// getApp() lazy, logger from "firebase-functions", admin from "firebase-admin"

export interface GenerateDueResult { created: number; skipped: number; scanned: number; }

// PURE, emulator-testable. Takes app (project convention — NOT raw Firestore).
export async function generateDuePaymentsHandler(
  app: admin.app.App,
  now: Date,
): Promise<GenerateDueResult>
```

Algorithm (inside the handler, `db = admin.firestore(app)`):
1. Query active links: `db.collection("trainer_links").where("status","==","active").get()` (equality-only → no composite index).
2. For each link `(trainerId, athleteId)`: read `athlete_billing/${trainerId}_${athleteId}`; skip if absent.
3. Branch on `cadence`: only `mensual` and `semanal` proceed; `por_sesion`/`suelto` → `skipped++`, continue.
4. Compute `periodKey` REPLICATING the client exactly (`isoWeekPeriodKey` / month key from `pagos_por_cobrar_provider.dart`), on `now` as UTC:
   - mensual: `${y}-${String(m).padStart(2,"0")}`
   - semanal: `${isoWeekYear(now)}-W${String(isoWeekNumber(now)).padStart(2,"0")}` (port the exact Thursday/jan4 math).
5. Compute `dueAt`:
   - mensual: **last day of the current month, 23:59:59 UTC** (`new Date(Date.UTC(y, m, 0, 23,59,59))`).
   - semanal: end of the ISO week (Sunday 23:59:59 UTC of `now`'s week).
6. Deterministic id `id = ${trainerId}_${athleteId}_${periodKey}`.
7. **Field-based existence check** (catches legacy auto-id docs): `db.collection("payments").where("trainerId","==",trainerId).where("athleteId","==",athleteId).where("periodKey","==",periodKey).limit(1).get()`. If ANY doc exists (pending OR paid, auto-id OR deterministic) → `skipped++`, continue.
8. Else `db.collection("payments").doc(id).create({...})` a pending doc: `{ id, trainerId, athleteId, amountArs: billing.amountArs, concept, status:"pending", periodKey, dueAt: Timestamp.fromDate(dueAt), createdAt: FieldValue.serverTimestamp() }`. `create()` (not `set`) so a concurrent run losing the race throws `ALREADY_EXISTS` → catch per-item, log, `skipped++`. Never touches paid docs.

`index.ts` export line: `export { generateDuePayments } from "./payments/generate-due-payments";`

Wrapper:
```ts
export const generateDuePayments = onSchedule(
  { schedule: "0 3 * * *", timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1" },
  async () => { await generateDuePaymentsHandler(getApp(), new Date()); },
);
```

## Architecture Decisions

| Decision | Choice | Rejected | Rationale |
|---|---|---|---|
| CF handler shape | Pure `generateDuePaymentsHandler(app, now)` + thin `onSchedule` wrapper | Logic inside wrapper | Matches every existing CF (`recomputeAggregate`, `cleanupAssignedPlansOnUnlinkHandler`); emulator-testable without scheduler harness. `now` injected for deterministic period tests. |
| Handler param type | `admin.app.App` | `Firestore` (as prompt suggested) | PROJECT CONVENTION wins (skill rule): all handlers take `app`, call `admin.firestore(app)` inside. Consistency > the suggested signature. |
| Idempotency | Field check `(trainerId, athleteId, periodKey)` + `.create()` on deterministic id | doc-id `.get()` only | Field check also catches LEGACY auto-id docs for the same period (manual "+ Cobro"); `create()` closes the concurrent-run race. |
| mensual due day | **Last day of month, 23:59:59 UTC** | Day 10; configurable field | `athlete_billing` has NO `dueDayOfMonth` (confirmed). "Overdue only after the month ends" is the least surprising, never-early default; no schema change. Configurability is a future SDD. |
| Coexistence gate | Suppress virtual `CobroPendiente` when ANY persisted Payment exists for `(athleteId, periodKey)` | Keep paid-only check | Once the CF persists a pending doc, the memory-only charge would double-count. Extend the existing `alreadyPaid` check to "any doc for the period". |
| Rules tightening | `keys().hasOnly([...])` + per-field equality (block `dueAt` client writes) | Leave loose; validate only `dueAt` | Follows the `reviews` update rule pattern already in the repo. Audited: `markPaid`/`markManyPaid` send only `{status, paidAt}` → still pass. |
| Slicing | 2 chained PRs (Dart+rules+indexes, then CF+tests) | Single PR | PR1 ships safe behind legacy fallback with zero CF dependency; keeps each PR ≤400 lines and independently reviewable/revertible. |

## Data Flow

```
[onSchedule 03:00 ART] → generateDuePaymentsHandler(app, now)
   trainer_links(status=active) ──> athlete_billing/{tid}_{aid}
        │ mensual|semanal                    │ porSesion|suelto → skip
        ▼                                     
   periodKey + dueAt ──> payments field-check (tid,aid,periodKey)
        │ exists → skip                 │ none → payments/{tid_aid_periodKey}.create(pending, dueAt)
                                              │
   Client: trainerPaymentsProvider ──> pagosBucketsProvider (dueAt<now ? vencido)
                                   └──> pagosPorCobrarProvider (gate: real doc suppresses virtual)
```

## File Changes

| File | Action | Description |
|---|---|---|
| `functions/src/payments/generate-due-payments.ts` | Create | `onSchedule` wrapper + pure handler + ISO-week helpers |
| `functions/src/index.ts` | Modify | export `generateDuePayments` |
| `functions/src/__tests__/generate-due-payments.test.ts` | Create | emulator jest tests |
| `lib/features/payments/domain/payment.dart` | Modify | add `@TimestampConverter() DateTime? dueAt` |
| `lib/features/payments/domain/payment.freezed.dart` / `.g.dart` | Regen | `dart run build_runner build --delete-conflicting-outputs` |
| `.../coach_hub/.../pagos/widgets/pagos_buckets_provider.dart` | Modify | Vencido = dueAt-based + legacy fallback |
| `lib/features/payments/application/pagos_por_cobrar_provider.dart` | Modify | coexistence gate (any doc for period) |
| `firestore.rules` | Modify | tighten payments `update` to field-level |
| `firestore.indexes.json` | Modify | +3 composite indexes |

## Interfaces / Contracts

**Domain** — `payment.dart`: add `@TimestampConverter() DateTime? dueAt,` after `paidAt`. json key `dueAt`, Firestore `Timestamp` (converter already handles null). Freezed regen required. Additive + nullable → no migration.

**Buckets fix** — `pagos_buckets_provider.dart`, partition loop:
```dart
final vencido = p.dueAt != null
    ? p.dueAt!.toUtc().isBefore(now)                 // authoritative
    : p.createdAt.toUtc().isBefore(periodStart);     // legacy null-dueAt fallback
(vencido ? vencidos : porVencer).add(p);
```

**Coexistence gate** — `pagos_por_cobrar_provider.dart`, mensual/semanal branches: replace `alreadyPaid` (paid-only) with
```dart
final hasDocForPeriod = athletePayments.any((p) => p.periodKey == key); // any status
if (!hasDocForPeriod) { results.add(CobroPendiente(...)); }
```
(`key` = `monthKey`/`weekKey`, already computed at lines 141-142.)

**Rules** — payments `update` becomes (audited against `markPaid`/`markManyPaid` = `{status, paidAt}` only):
```
allow update: if request.auth != null
  && resource.data.trainerId == request.auth.uid
  && request.resource.data.keys().hasOnly(
       ['id','trainerId','athleteId','amountArs','concept',
        'status','periodKey','createdAt','paidAt','dueAt'])
  && request.resource.data.trainerId == resource.data.trainerId
  && request.resource.data.athleteId == resource.data.athleteId
  && request.resource.data.amountArs == resource.data.amountArs
  && request.resource.data.concept   == resource.data.concept
  && request.resource.data.createdAt == resource.data.createdAt
  && request.resource.data.get('periodKey', null) == resource.data.get('periodKey', null)
  && request.resource.data.get('dueAt', null) == resource.data.get('dueAt', null);
```
`dueAt` pinned equal-to-existing → clients cannot set/alter it; CF writes via Admin SDK (bypasses rules).

**Indexes** — add to `firestore.indexes.json`:
```json
{ "collectionGroup":"payments","queryScope":"COLLECTION","fields":[
  {"fieldPath":"trainerId","order":"ASCENDING"},{"fieldPath":"status","order":"ASCENDING"},{"fieldPath":"dueAt","order":"ASCENDING"}]},
{ "collectionGroup":"payments","queryScope":"COLLECTION","fields":[
  {"fieldPath":"trainerId","order":"ASCENDING"},{"fieldPath":"paidAt","order":"DESCENDING"}]},
{ "collectionGroup":"payments","queryScope":"COLLECTION","fields":[
  {"fieldPath":"athleteId","order":"ASCENDING"},{"fieldPath":"status","order":"ASCENDING"},{"fieldPath":"dueAt","order":"ASCENDING"}]}
```
(The CF's field-existence check uses 3 equality filters → served by automatic single-field indexes, no composite needed.)

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Unit (jest, emulator) | pure handler | seed `trainer_links`+`athlete_billing`, call `generateDuePaymentsHandler(testApp, fixedNow)` |
| Integration | idempotency / rules | re-run handler; rules-test that a client `update` setting `dueAt` is denied |
| Manual | deploy | user runs `firebase deploy --only functions,firestore:rules,firestore:indexes` |

jest cases (SCENARIO-style, `functions/src/__tests__/generate-due-payments.test.ts`, mirroring `notify-link-change.test.ts`): (1) mensual active → creates pending w/ periodKey + last-day dueAt; (2) semanal active → creates pending w/ `YYYY-Www` + week-end dueAt; (3) idempotent: second run → `created:0`; (4) skip when a PAID doc exists for the period; (5) skip when a LEGACY auto-id pending doc exists for the period; (6) skip porSesion + suelto cadences; (7) skip when `athlete_billing` absent; (8) non-active link ignored.

## Migration / Rollout

No data migration. `dueAt` nullable + additive. First CF run = current period only (no backfill). Rollback: PR2 → drop `index.ts` export, redeploy `--only functions` (persisted docs harmless: buckets read `dueAt`, gate suppresses dup); PR1 → revert commit, indexes optional to drop.

## Open Questions

- [ ] semanal `dueAt` = Sunday-end confirmed as the intended week boundary (ISO week ends Sunday)? Assumed yes.
- [ ] `concept` text for CF-generated docs — reuse the client strings (`Mensual {Mes} {year}` / `Semana {ww}`)? Recommend yes for UI consistency.

# Spec: paywall-pr4-enforcement (Fase 7, PR4 — server-side promotion gate)

**Change**: `paywall-pr4-enforcement`
**REQ namespaces**: `REQ-PAYWALL-GATE-NNN` (new), `REQ-COACH-LINK-NNN` (new siblings, 015-018)
**SCENARIO range**: 900-922
**Capabilities touched**:
- NEW `paywall-link-promotion-gate`
- MODIFIED `coach-link-lifecycle` (new sibling requirements only — 001-014 untouched)

---

## New Capability: `paywall-link-promotion-gate`

### Purpose

Server-side, transactional enforcement of the paywall weighted-load limit on the only two
weight-raising `trainer_links` transitions: `accept` (pending→active) and `resume` (paused→active).
Replaces the unenforced client Firestore write path. The gate never trusts the denormalized
`users/{trainerId}.weightedLoad` field — it always recomputes live from `trainer_links` inside its
own transaction, and a reconciliation trigger keeps that denormalized field accurate afterward for
display only.

### Requirements — `paywall-link-promotion-gate`

| ID | Name | Strength |
|----|------|----------|
| REQ-PAYWALL-GATE-001 | Gate predicate is a live projection, not delta arithmetic | MUST |
| REQ-PAYWALL-GATE-002 | Projection deduplicates by `athleteId` | MUST |
| REQ-PAYWALL-GATE-003 | Blocked-entitlement links excluded from the load computation | MUST |
| REQ-PAYWALL-GATE-004 | Target link's own blocked entitlement rejects promotion | MUST |
| REQ-PAYWALL-GATE-005 | Transactional concurrency serializes on `users/{trainerId}` | MUST |
| REQ-PAYWALL-GATE-006 | `weightedLoad` is display-only, never a gate input | MUST |
| REQ-PAYWALL-GATE-007 | Error contract on quota block | MUST |
| REQ-PAYWALL-GATE-008 | Error contract for non-quota failures (authz/precondition) | MUST |
| REQ-PAYWALL-GATE-009 | Reconciliation trigger is idempotent, full-recompute, error-safe | MUST |

---

### REQ-PAYWALL-GATE-001 — Gate predicate is a live projection, not delta arithmetic

`acceptTrainerLink` and `resumeTrainerLink` MUST decide by projecting the target link's `status`
to `active` inside the trainer's current `trainer_links` set, recomputing
`computeWeightedLoad(projectedLinks)`, and comparing the result to
`effectiveWeightLimit(subscription, now)`. The gate MUST NOT decide by adding a fixed weight delta
to a previously stored total (that is `canAccept(load, delta, limit)`, rejected — see
REQ-PAYWALL-GATE-002). At-limit (`==`) MUST pass; over-limit (`>`) MUST block.

#### SCENARIO-900: accept passes exactly at the boundary

- GIVEN a trainer with current weighted load `6.0` and effective limit `7`
- WHEN `acceptTrainerLink` is called on a pending link (weight `1.0`)
- THEN the projected load is `7.0`
- AND the call succeeds (`7.0 <= 7`)

#### SCENARIO-901: accept blocks over the boundary

- GIVEN a trainer with current weighted load `7.0` and effective limit `7`
- WHEN `acceptTrainerLink` is called on a pending link
- THEN the projected load is `8.0`
- AND the call is rejected (`8.0 > 7`)

#### SCENARIO-902: resume passes exactly at the boundary

- GIVEN a trainer with one paused link and current weighted load `6.5` (includes that link at `0.5`), limit `7`
- WHEN `resumeTrainerLink` is called on the paused link
- THEN the projected load is `7.0`
- AND the call succeeds

#### SCENARIO-903: resume blocks with two paused links

- GIVEN a trainer with two paused links, current weighted load `7.0` (includes both at `0.5` each), limit `7`
- WHEN `resumeTrainerLink` is called on one of the paused links
- THEN the projected load is `7.5`
- AND the call is rejected

---

### REQ-PAYWALL-GATE-002 — Projection deduplicates by `athleteId`

`computeWeightedLoad` MUST deduplicate by `athleteId` before summing weight, so a trainer holding
two `trainer_links` to the same athlete counts that athlete once. This is the exact reason
`canAccept(load, delta, limit)` was rejected as the gate mechanism: delta arithmetic double-counts
a second link to an already-counted athlete, while the projection inherits dedup for free.

#### SCENARIO-904: same-athlete duplicate links are not double-counted

- GIVEN a trainer has `linkA` (athlete X, `active`, weight `1.0`) and `linkB` (athlete X, `pending`)
- WHEN `acceptTrainerLink` is called on `linkB`
- THEN `computeWeightedLoad` counts athlete X once in the projection
- AND the projected total does NOT add a second full weight for athlete X

---

### REQ-PAYWALL-GATE-003 — Blocked-entitlement links excluded from the load computation

Links with `entitlement == 'blocked'` MUST be excluded from `computeWeightedLoad` regardless of
`status` (ADR-5, PR1).

#### SCENARIO-905: a blocked-entitlement link is excluded from both totals

- GIVEN a trainer's link set includes one link with `entitlement: 'blocked'` that would contribute `1.0` if counted
- WHEN the gate projects load for a different link's promotion
- THEN the blocked link's weight is excluded from both the current and the projected total

---

### REQ-PAYWALL-GATE-004 — Target link's own blocked entitlement rejects promotion

Promoting a link whose OWN `entitlement == 'blocked'` MUST be rejected with
`failed-precondition` / `link-blocked`, independent of the weighted-load boundary. Promoting parked
excess belongs to the (unbuilt) reactivation flow — out of scope here.

#### SCENARIO-906: promoting a blocked-entitlement link is rejected before the boundary check

- GIVEN a pending link with `entitlement: 'blocked'`
- WHEN `acceptTrainerLink` is called on it
- THEN the call fails with `failed-precondition` / `link-blocked`
- AND no weighted-load comparison result is part of the rejection reason

---

### REQ-PAYWALL-GATE-005 — Transactional concurrency serializes on `users/{trainerId}`

Each gate call MUST run inside one Firestore transaction that both reads `users/{trainerId}`
(for `subscription`) AND writes it (`weightedLoad`). That read-write pair on the single shared
document IS the serialization point for two concurrent gate calls on the same trainer — it does not
rely on query-lock semantics. The losing transaction MUST retry, re-read the winner's committed
state, and re-evaluate the predicate against it. An over-limit committed state MUST be unreachable.

#### SCENARIO-907: two concurrent accepts — exactly one wins

- GIVEN a trainer at weighted load `6.0`, limit `7`, with two distinct pending links
- WHEN two `acceptTrainerLink` calls fire concurrently, one per link
- THEN exactly one transaction commits, bringing the load to `7.0`
- AND the other retries, re-reads `7.0`, projects `8.0`, and is rejected with `resource-exhausted`
- AND no committed state ever exceeds `7.0`

---

### REQ-PAYWALL-GATE-006 — `weightedLoad` is display-only, never a gate input

`users/{trainerId}.weightedLoad` MUST NEVER be read as gate input. The gate MUST always recompute
from `trainer_links` inside its own transaction, regardless of the denormalized field's value.

#### SCENARIO-908: gate ignores a stale or absent denormalized field

- GIVEN `users/{uid}.weightedLoad` is stale (`3.0`) or the field is absent, while the true recomputed load from `trainer_links` is `7.0`, limit `7`
- WHEN `acceptTrainerLink` is called on a link that would project to `8.0`
- THEN the gate rejects the call based on the recomputed `8.0`
- AND the stale/absent denormalized value has no effect on the decision

---

### REQ-PAYWALL-GATE-007 — Error contract on quota block

On rejection due to the weighted-load boundary, the callable MUST throw
`HttpsError('resource-exhausted', message, details)` with
`details = { reason: 'plan-limit', tier, limit, currentLoad, projectedLoad }`, where `tier` is the
nominal `subscription.tier`.

#### SCENARIO-909: block error carries the exact details contract

- GIVEN a trainer with `subscription.tier: 'free'`, limit `7`, current load `7.0`
- WHEN `acceptTrainerLink` projects `8.0` and rejects
- THEN the thrown error has `code: 'resource-exhausted'`
- AND `details` equals `{ reason: 'plan-limit', tier: 'free', limit: 7, currentLoad: 7.0, projectedLoad: 8.0 }`

---

### REQ-PAYWALL-GATE-008 — Error contract for non-quota failures (authz/precondition)

The callables MUST distinguish paywall rejections from other failures with distinct codes:
- `not-found` when `linkId` does not exist.
- `permission-denied` when the caller is not the link's `trainerId`.
- `failed-precondition` when the link's current `status` does not match the expected source status
  (`acceptTrainerLink` requires `pending`; `resumeTrainerLink` requires `paused`).

#### SCENARIO-910: link not found

- GIVEN no `trainer_links` document exists at the given `linkId`
- WHEN `acceptTrainerLink` is called with that `linkId`
- THEN it fails with `not-found` (not `resource-exhausted`)

#### SCENARIO-911: caller is not the link's trainer

- GIVEN the authenticated caller's uid is not `resource.data.trainerId` on the link
- WHEN `acceptTrainerLink` or `resumeTrainerLink` is called
- THEN it fails with `permission-denied`

#### SCENARIO-912: acceptTrainerLink on a non-pending link

- GIVEN a link with `status: 'active'`
- WHEN `acceptTrainerLink` (expects `pending`) is called on it
- THEN it fails with `failed-precondition`

#### SCENARIO-913: resumeTrainerLink on a non-paused link

- GIVEN a link with `status: 'pending'` (or `'active'`, or `'terminated'`)
- WHEN `resumeTrainerLink` (expects `paused`) is called on it
- THEN it fails with `failed-precondition`

---

### REQ-PAYWALL-GATE-009 — Reconciliation trigger is idempotent, full-recompute, error-safe

The `weightedLoad` reconciliation trigger MUST recompute the trainer's weighted load from scratch
on every `trainer_links` write event (no increments), through the SAME transactional
`computeWeightedLoad` helper the gate uses. It MUST be idempotent — running twice for the same
underlying state produces the same value. It MUST catch and log errors without rethrowing (no
retry storm), mirroring `link-aggregate.ts`.

#### SCENARIO-914: `weightedLoad` decreases after a client-side pause or terminate

- GIVEN `users/{trainerId}.weightedLoad` denormalized to `7.0`
- WHEN a link is paused (client-side) or terminated (client-side)
- THEN the trigger recomputes `weightedLoad` down to the correct lower value (e.g. `6.5` after pause, `6.0` after terminate)

#### SCENARIO-915: running the trigger twice is idempotent

- GIVEN the trigger has already reconciled `weightedLoad` to `6.5`
- WHEN the trigger runs again for an equivalent event (retry or duplicate delivery)
- THEN `weightedLoad` remains `6.5` (no double-decrement, no drift)

#### SCENARIO-916: missing target user document is error-safe

- GIVEN the `users/{trainerId}` document referenced by the event does not exist
- WHEN the trigger fires
- THEN it logs a warning and completes without throwing
- AND no retry storm is triggered

---

## Modified Capability: `coach-link-lifecycle` — new sibling requirements

### Purpose of the delta

Requirements 001-014 in `openspec/specs/coach-link-lifecycle.md` are UNCHANGED. This adds four new
sibling requirements to the SAME `trainer_links/{linkId}` update rule those requirements already
describe (`firestore.rules:517-541`), locking the two weight-raising transitions to CF-only and
closing a side-effect gap found during exploration.

### Requirements — new siblings

| ID | Name | Strength |
|----|------|----------|
| REQ-COACH-LINK-015 | `trainer_links` promotion to `active` is CF-only (client-denied) | MUST |
| REQ-COACH-LINK-016 | `pause`/`terminate` remain client-side (regression guard) | MUST |
| REQ-COACH-LINK-017 | Reversion to `pending` is denied (new hardening) | MUST |
| REQ-COACH-LINK-018 | CF-write-only pins on `entitlement`/`blockedAt`/`blockedReason` remain enforced | MUST |

---

### REQ-COACH-LINK-015 — `trainer_links` promotion to `active` is CF-only (client-denied)

The `trainer_links/{linkId}` update rule MUST deny any client write that changes `status` to
`active`, for every actor including the trainer. Only `acceptTrainerLink` / `resumeTrainerLink`
(Admin SDK, bypasses rules) may set `status: 'active'`.

#### SCENARIO-917: client accept is denied even for the trainer

- GIVEN a pending link
- WHEN the trainer attempts a direct client write `status: pending → active`
- THEN the write is denied (`assertFails`)

#### SCENARIO-918: client resume is denied even for the trainer

- GIVEN a paused link
- WHEN the trainer attempts a direct client write `status: paused → active`
- THEN the write is denied (`assertFails`)

---

### REQ-COACH-LINK-016 — `pause`/`terminate` remain client-side (regression guard)

Trainer-initiated `pause` (`active → paused`) and either-member `terminate` (`→ terminated`) MUST
continue to succeed as direct client writes. This change MUST NOT affect them.

#### SCENARIO-919: trainer pause still succeeds

- GIVEN an active link
- WHEN the trainer writes `status: active → paused`
- THEN the write succeeds (`assertSucceeds`)

#### SCENARIO-920: terminate by either member still succeeds

- GIVEN an active or paused link
- WHEN the trainer OR the athlete writes `status: → terminated`
- THEN the write succeeds (`assertSucceeds`)

---

### REQ-COACH-LINK-017 — Reversion to `pending` is denied (new hardening)

The update rule MUST deny any client write that changes `status` back to `pending` from any other
status, for any actor. Previously, the clause `!(status in ['active','paused'])` allowed this
implicitly — any member could overwrite a live link back to `pending` (or un-terminate it). This
requirement closes that gap. Intentional hardening, discovered during exploration, pinned here by a
test rather than left for review to find.

#### SCENARIO-921: any member reverting a link to pending is denied

- GIVEN a link with `status: active` (or `paused`, or `terminated`)
- WHEN any member (trainer or athlete) attempts a client write `status: → pending`
- THEN the write is denied (`assertFails`)

---

### REQ-COACH-LINK-018 — CF-write-only pins remain enforced

The PR1 field pins on `entitlement`, `blockedAt`, `blockedReason` (equal-to-existing via
`get(field, null)`) MUST remain unaffected by the split-clause change in REQ-COACH-LINK-015/017.

#### SCENARIO-922: entitlement cannot be changed alongside an allowed status write

- GIVEN a client update to a `trainer_links` doc that changes only `status` within an allowed transition (e.g. `pause`)
- WHEN the same write also attempts to change `entitlement`
- THEN the write is denied

---

## Out of Scope (deferred)

| Deferred item | Reason |
|---|---|
| `subscription-inactive` reason code (nominal tier ≠ effective entitlement) | Billing not live pre-launch; unreachable today (D3 accepted limitation) |
| Migrating `pause`/`terminate`/`decline`/`cancel` to CFs | Option B, own change |
| Subscription reactivation CF | Unbuilt, unrelated to link status |

---

*Generated by sdd-spec — 2026-08-12*

# Proposal: paywall-pr4-enforcement (Fase 7, PR4 — server-side promotion gate)

## Intent

PR1-PR3 shipped the paywall math (`tier-config`, `weighted-load`, `effective-limit`) but **nothing calls it**. `accept` (pending→active) and `resume` (paused→active) are plain client Firestore writes, so a PF exceeds their tier limit at will — reproducible: pause 2 → accept 1 → resume 2 = 8.0 load on a limit of 7. PR4 makes the limit real: enforced server-side, transactionally, with a typed error the client routes to `showPlanLimitPaywall`.

## Decisions

### D1 — `weightedLoad` source of truth: **hybrid (Option C), with a sharper rationale than the explore's**

**Rule**: `users/{trainerId}.weightedLoad` is a **display denormalization and is NEVER a gate input**. The gate always recomputes live from `trainer_links` inside its transaction.

| Option | Fails how |
|---|---|
| A — trigger-only, gate reads the field | Two concurrent accepts at 6.0 both read stale 6.0, both compute 7.0 ≤ 7, both pass → 8.0. The brief's bug, moved server-side. Rejected. |
| B — only gate CFs write the field | `pause`/`terminate`/`decline`/`cancel` stay client-side and never decrement → the counter only rises → permanent false lockout. Rejected. |
| C — live transactional recompute + idempotent reconciliation trigger | Adopted. |

**Why C is correct under concurrency (the load-bearing detail)**: every gate transaction *must* read `users/{trainerId}` (it needs `subscription`) **and must write it** (`weightedLoad`). That read-write pair on a single shared document is the serialization point — it does not depend on Firestore's subtler in-transaction query-lock semantics. Two concurrent promotions on the same trainer contend on that doc; the loser retries, re-reads, and re-evaluates against the winner's committed state.

**Improvement over the explore**: the trigger uses the **same transactional helper** as the gate, differing only by a projection argument. `computeWeightedLoad` therefore has **one** TS caller path, not two — the triple-implementation risk collapses to TS-vs-Dart.

**Gate predicate (exact)** — projection, not delta arithmetic:

```
computeWeightedLoad(links.map(l => l.id === targetId ? {...l, status:'active'} : l)) <= effectiveWeightLimit(sub, now)
```

Projection (not `canAccept(load, 1.0, limit)`) because it inherits `dedupeByAthlete` and blocked-link exclusion for free; delta arithmetic double-counts a trainer holding two links with the same athlete. `canAccept` stays as the **non-authoritative** UI pre-flight helper.

**Boundary**: `7.0 <= 7` passes (at-limit is allowed), `7.5 > 7` blocks. Under two concurrent accepts on a trainer at 6.5: the first commits 7.5? No — 6.5 + 1.0 = 7.5 > 7, both blocked. At 6.0: first commits 7.0; second retries, projects 8.0 > 7, **blocked**. Exactly one winner, no over-limit state is ever reachable.

**Extra**: a target link with `entitlement == 'blocked'` is rejected with `failed-precondition` / `link-blocked` — promoting parked excess belongs to the (unbuilt) reactivation flow.

### D2 — Gate scope: **two callables, one shared helper**

`accept` and `resume` are the only two weight-raising transitions (confirmed: `reactivate()` does not exist). Ship `acceptTrainerLink` and `resumeTrainerLink` as separate `onCall`s over one `promoteLinkToActive(tx, {linkId, expectedFromStatus})` helper.

Rationale: matches the codebase's one-callable-per-operation convention (`deleteAccount`, `addAlias`); preconditions differ by source status; and — decisive — it keeps slice 3 **purely additive**, so shipping resume does not re-open slice 2's already-reviewed callable for diff churn. A transition parameter would turn a nonexistent-function error into a runtime enum error and couple the two slices.

### D3 — Error contract

`HttpsError('resource-exhausted', msg, details)` (`resource-exhausted` is unused elsewhere in this codebase — no collision), with

```
details: { reason: 'plan-limit', tier: 'free'|'plan1'|'plan2', limit, currentLoad, projectedLoad }
```

`tier` is the **nominal** `subscription.tier`, because `showPlanLimitPaywall(context, currentTier:)` takes a `SubscriptionTier` and renders `nextTier` as the upsell. Dart maps `FirebaseFunctionsException.code == 'resource-exhausted'` → sealed `PlanLimitReached` failure (plain Dart, Hard Constraint #3) → callsite shows the paywall.

**Accepted limitation, flagged for sdd-design**: when nominal tier ≠ effective entitlement (subscription `pending`/`paused` → free limit), the paywall upsells a plan the PF nominally already has. Billing is not live pre-launch, so this is unreachable today; a `subscription-inactive` reason code is deferred.

### D4 — Rules: split the clause, delete the `active` branch

Replace `firestore.rules:531-533` with:

```
&& (request.resource.data.status == resource.data.status
    || request.resource.data.status == 'terminated'
    || (request.resource.data.status == 'paused'
        && request.auth.uid == resource.data.trainerId))
```

| Target | Before | After |
|---|---|---|
| unchanged | allowed | allowed |
| `terminated` | any member | any member (decline/cancel/terminate) |
| `paused` | trainer only | trainer only (`pause` stays client-side) |
| `active` | **trainer allowed** | **impossible for everyone → CF only** |
| `pending` | **allowed (any member!)** | **denied** |

Client transitions that become impossible and therefore MUST live in a CF: `accept`, `resume`. Nothing else.

**Newly found side effect**: the old `!(status in ['active','paused'])` branch let either member overwrite a live link back to `pending` (or un-terminate it). The split clause closes that too. Intentional hardening — must be spec'd and test-pinned, not discovered in review.

### D5 — Slicing: 4 chained PRs, **re-cut** vs. the explore

The explore bundled the rules lock into slice 2 alongside new code. That violates "each slice leaves the system consistent": the lock is the one **irreversible, production-breaking** edit and must not ride along with 500 lines of new TS.

| # | Slice | Deliverable | ~LOC | Depends on |
|---|---|---|---|---|
| 1 | Weighted-load transactional core + reconciliation trigger + index export + TS golden fixture | `weightedLoad` becomes accurate and self-healing (billing tab correct). Nothing depends on it yet. | 350-450 | — |
| 2 | `acceptTrainerLink` CF + Dart service/provider + **both** accept callsites + paywall error routing | Accept is gated end-to-end for new builds. Rules unchanged → old builds keep working. | 450-550 | 1 |
| 3 | `resumeTrainerLink` CF + service method + `alumnos_screen` callsite | The brief's confirmed gap closed. Purely additive. | 250-350 | 2 |
| 4 | Rules split-clause + test flips + new resume/pending coverage + `test:rules` regex fix + comment rewrites + dead client `accept`/`resume` removal + `facturacion_tab` → denormalized field | The hole is actually closed. **Only slice touching `firestore.rules`.** | 250-350 | 2, 3 |

Strictly linear. Feature Branch Chain: PR #1 → tracker branch, each child → previous child. Each slice is one deliverable work unit; Strict TDD → tests in the same commit as the code.

**Honest tradeoff**: between slice 2 merge and slice 4 deploy, a hand-crafted client write still bypasses the gate. That hole is already open today, so there is no regression — only a bounded window before it closes.

## Scope

### In Scope
- `promoteLinkToActive` transactional gate helper + `weightedLoad` reconciliation trigger
- `acceptTrainerLink` / `resumeTrainerLink` callables (`southamerica-east1`, `enforceAppCheck: true`)
- `firestore.rules` split-clause lock on `status == 'active'` (+ `pending` hardening) and comment rewrite
- Dart CF service(s), provider, 3 callsite migrations, `resource-exhausted` → `showPlanLimitPaywall` routing
- Rules tests (flip accept, add resume + pending), CF unit tests incl. boundary + concurrency, TS/Dart parity fixture
- `functions/package.json` `test:rules` regex fix

### Out of Scope
- Migrating `pause`/`terminate`/`decline`/`cancel` to CFs (Option B — its own change)
- Subscription reactivation CF (`users/{uid}.subscription` cancelled→active) — unbuilt, unrelated to link status
- Promoting `entitlement: 'blocked'` links (belongs to the downgrade/reactivation flow)
- Minimum-app-version enforcement (does not exist; see risks)
- Mercado Pago / billing-cycle work

## Capabilities

### New Capabilities
- `paywall-link-promotion-gate`: server-side weighted-load enforcement on trainer_link promotions to `active` — gate predicate, transactional concurrency contract, `weightedLoad` denormalization, and the over-limit error contract.

### Modified Capabilities
- `coach-link-lifecycle`: `pending→active` and `paused→active` become CF-only (client-denied); update-to-`pending` becomes denied. REQ-COACH-LINK-012..014 rule requirements gain new sibling requirements.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `functions/src/subscriptions/` | New | Gate helper, two callables, reconciliation trigger |
| `functions/src/index.ts` | Modified | 3 exports |
| `firestore.rules` (517-541, comments 494-530) | Modified | Split clause; PR4-referencing comments rewritten |
| `functions/src/__tests__/trainer-links-paywall-rules.test.ts` | Modified | Comment #4 assert flips `assertSucceeds` → `assertFails` |
| `functions/package.json` | Modified | `test:rules` allow-list → suffix pattern |
| `lib/features/coach_hub/application/cf_providers.dart` | Modified | New service providers |
| `lib/features/coach/data/trainer_link_repository.dart` | Modified | `accept`/`resume` client writes removed (slice 4) |
| `trainer_dashboard_tab.dart:423`, `coach_hub_dashboard_screen.dart:1218`, `alumnos_screen.dart:711` | Modified | Callsite migration |
| `lib/features/coach/domain/weighted_load.dart` | Modified | Marked non-authoritative; pinned by parity fixture |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Rules split-clause re-opens the hole or breaks `pause()` | High | Isolated in slice 4 (only rules edit in the change); pinned by tests written first (Strict TDD): accept fails, resume fails, pause succeeds, terminate succeeds, →pending fails |
| **No min-app-version enforcement exists** (verified: no `minVersion`/Remote Config in `lib/`). Deploying the rules lock breaks `accept`/`resume` on old builds | High | Deploy order is a manual runbook (CI does **not** auto-deploy — verified, no `firebase deploy` in `.github/workflows/`): **(1) functions, (2) app release with CF callsites, (3) rules lock only after adoption**. Slice 4's *merge* does not deploy; the rules deploy is a separately scheduled step |
| `computeWeightedLoad` divergence TS ↔ Dart | Med | Shared helper collapses TS to one path; a committed golden fixture (link-set → expected load) is asserted by both the TS and Dart suites; Dart mirror explicitly demoted to non-authoritative pre-flight |
| New rules test files silently skipped by `test:rules` regex allow-list | High | Replace the 15-name alternation with the `-rules` suffix pattern (every existing entry already ends in `-rules`); verify suite names appear in jest output |
| One of the two `accept()` callsites missed | Med | Both live in slice 2's definition of done; slice 4 **deletes** `TrainerLinkRepository.accept`, so a missed callsite becomes a compile error, not a silent break |
| Trigger and gate write `weightedLoad` concurrently | Low | Both go through the same transaction helper; the value is display-only and never gates, so worst case is bounded staleness that the next event reconciles |
| Stale `firestore.rules` comments naming "PR4" | Med | Rewritten in slice 4 as a definition-of-done item |
| Concurrent-promotion test needs the emulator (Java 21, not runnable locally) | Med | Run in CI `functions-test`; keep `--runInBand` and the `treino-rules-test` projectId — do not introduce a second project ID |

## Rollback Plan

Per slice, in reverse dependency order:
1. **Rules lock (slice 4)**: redeploy the previous `firestore.rules` — single-file, instant, restores client `accept`/`resume`. This is why it ships alone.
2. **Callables (slices 2-3)**: `firebase functions:delete acceptTrainerLink resumeTrainerLink`, or revert the client release. Safe **only while the rules lock is not deployed** — which is exactly why the lock deploys last.
3. **Trigger (slice 1)**: delete the trigger; `weightedLoad` freezes at its last value. Display-only, so no gate impact.

## Dependencies

- PR1-PR3 merged (`tier-config.ts`, `weighted-load.ts`, `effective-limit.ts`, field-pins, `plan_limit_paywall.dart`) — all confirmed present
- `cloud_functions ^5.2.0` — already a dependency
- CI emulator job (Node 20 + Java 21) — already configured

## Success Criteria

- [ ] Two concurrent promotions on a trainer at limit-1: exactly one succeeds, the other gets `resource-exhausted`; final load never exceeds the limit
- [ ] Boundary pinned: `7.0` passes, `7.5` blocks; blocked-entitlement links excluded; same-athlete duplicates deduped
- [ ] Repro from the brief (pause 2 → accept 1 → resume 2) blocks at the resume with the paywall shown
- [ ] Client-side `pending→active`, `paused→active` and `→pending` all `assertFails`; `pause`/`terminate`/`decline`/`cancel`/`sharedWithTrainer` still `assertSucceeds`
- [ ] `weightedLoad` decreases after a client-side `pause`/`terminate` (trigger reconciliation)
- [ ] TS and Dart `computeWeightedLoad` agree on every golden-fixture case
- [ ] All new rules suites appear in `npm run test:rules` output
- [ ] `flutter analyze` 0 issues, `dart format .` clean, `flutter test` + `npm --prefix functions test` green
- [ ] No slice exceeds ~550 changed lines; each merges leaving production consistent

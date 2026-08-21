# Exploration: paywall-pr4-enforcement (PF→TREINO paywall, Fase 7, PR4 — server-side enforcement)

## Current State

PR1-PR3 shipped: tier config, weighted-load math, effective-limit resolver (all pure, `functions/src/subscriptions/`), Firestore field-pins for `subscription`/`weightedLoad` (users) and `entitlement`/`blockedAt`/`blockedReason` (trainer_links), and a read-only billing tab. **No trigger or callable in `subscriptions/` is wired up yet** — confirmed, the directory only has `tier-config.ts`, `weighted-load.ts`, `effective-limit.ts`, zero imports of them outside their own tests. The gate does not exist anywhere in the deployed system today. `accept()` and `resume()` are plain client Firestore writes gated only by `firestore.rules`, which does NOT check quota — it only prevents the athlete from self-promoting a link (QA-SEC-002).

## 1. Transition Inventory — `TrainerLinkRepository` (`lib/features/coach/data/trainer_link_repository.dart`, read in full)

| Method | Transition | Weight delta | Caller today | Needs server gate? |
|---|---|---|---|---|
| `request` | (create) → `pending` | 0.0 | athlete | No — pending doesn't count (`STATUS_WEIGHT.pending = 0`) |
| `accept` | `pending` → `active` | **0.0 → 1.0** | trainer (`trainer_dashboard_tab.dart:423`, `coach_hub_dashboard_screen.dart:1218`) | **YES** — already known scope |
| `decline` | `pending` → `terminated` | 0.0 → 0.0 | trainer (`trainer_dashboard_tab.dart:412`, `coach_hub_dashboard_screen.dart:1241`) | No |
| `cancel` | `pending` → `terminated` | 0.0 → 0.0 | athlete (`athlete_coach_view.dart:389`) | No |
| `terminate` | `active`/`paused` → `terminated` | 1.0/0.5 → 0.0 | trainer AND athlete (`alumnos_screen.dart:724`, `trainer_coach_view.dart:376`, `athlete_coach_view.dart:430`) | No — always a demotion |
| `pause` | `active` → `paused` | **1.0 → 0.5** | trainer (`alumnos_screen.dart:707`) | No — demotion |
| `resume` | `paused` → `active` | **0.5 → 1.0** | trainer (`alumnos_screen.dart:711`) | **YES — this is the confirmed hole** |
| `setSharedWithTrainer` | (no status change) | 0.0 | athlete | No |

**Correction to the task brief**: there is no `reactivate()` method on `TrainerLinkRepository`, and no client path takes a link from `terminated` back to `active` — a new relationship always goes through `request()` → fresh `pending` doc. The word "reactivation" that appears in `firestore.rules:83` and `users-subscription-rules.test.ts` comments refers to a **different, not-yet-built concept**: reactivating a *cancelled subscription* (users/{uid}.subscription.status `cancelled`→`active` after Mercado Pago payment resumes), not a trainer_link status transition. That CF is out of scope for PR4 (it's a Fase 2/billing-cycle concern, no code exists for it either). I flag this because the task brief treated it as a third weight-raising transition — it is not; there are exactly **two**: `accept` and `resume`.

So the real scope-closing requirement is: **both `accept` and `resume` must move behind server-side gating**, not just `accept`. This matches the concrete repro in the brief (pause 2 → accept 1 → resume 2 → 8.0/7).

## 2. CF Patterns to Copy

Read `delete-account.ts` (callable, complex cascade), `add-alias.ts` (callable, simple trainer-gated write), `link-aggregate.ts` (trigger, denormalization).

- **Pattern**: pure handler function (`runX`) exported separately + thin `onCall`/`onDocumentWritten` wrapper that just extracts request data and delegates. Every file has a lazy `getApp()` helper (try `admin.app()`, catch → `admin.initializeApp()`) so the module is importable in tests with a named emulator app.
- **Region**: `southamerica-east1` everywhere (LATAM latency). PR4 CFs must use the same region — the Dart client already has a pattern for this (see §3).
- **App Check**: both `deleteAccountHandler` and `addAlias` set `enforceAppCheck: true` on the `onCall` options, with a comment that it's a release prerequisite (QA-SEC-006). `acceptTrainerLink`/`resumeTrainerLink` should follow the same convention.
- **Error typing to the client**: `HttpsError(code, message)` from `firebase-functions/v2/https`, e.g. `"permission-denied"`, `"invalid-argument"`, `"not-found"`. `add-alias.ts` validates guards in BOTH the wrapper and the pure handler (defense in depth / independent testability) — PR4's gate should do the same, and needs a NEW dedicated error code for "over limit" (e.g. `resource-exhausted` — not used anywhere yet in this codebase, no collision) so the Dart client can distinguish "blocked by quota" from generic failure and route to `showPlanLimitPaywall`.
- **Trigger idempotency pattern** (`link-aggregate.ts`, mirrors `review-aggregate.ts`): re-derive the aggregate from scratch on every event (no increments), catch-all try/catch that logs and never rethrows (avoids infinite retry storms), no-op + `logger.warn` when the target doc is missing. This is the template for a `weightedLoad` denormalization trigger if PR4 keeps one.
- **Export convention**: `functions/src/index.ts` re-exports each CF by name in a flat list with a one-line PR/phase comment above the block (e.g. `export { deleteAccountHandler as deleteAccount } from "./delete-account";`). New exports: `acceptTrainerLink`, `resumeTrainerLink`, and (if kept) the weightedLoad trigger.

## 3. Dart → Callable Pattern (confirmed to exist, not a scope risk)

`cloud_functions: ^5.2.0` is already a dependency (`pubspec.yaml:35`), and there is a real, working pattern to copy: `lib/features/profile/data/account_deletion_service.dart` + `lib/features/coach_hub/application/cf_providers.dart`.

- `cloudFunctionsProvider` = `FirebaseFunctions.instanceFor(region: 'southamerica-east1')` (must match the CF's deployed region — the default client region is `us-central1` and would 404).
- Thin service class wrapping exactly one callable (`_functions.httpsCallable('deleteAccount')`), typed request/response, `try { ... } on FirebaseFunctionsException catch (e) { throw Failure$Server(code: e.code, message: e.message) } catch (e) { throw Failure$Unknown(cause: e) }`.
- Sealed, NOT-freezed failure classes per call (explicit codebase convention: "Hard Constraint #3" — CF response/failure DTOs are plain Dart, not freezed).

PR4 should add `AcceptTrainerLinkService`/`ResumeTrainerLinkService` (or one service with two methods) following this exact shape, and a Riverpod provider. No new package or pattern needed — this de-risks the "front minimum" item in the known scope.

## 4. Rules Change — precise mechanics

`firestore.rules:517-541`, the `allow update` on `trainer_links/{linkId}`. The OR clause at 531-533 is:

```
(request.resource.data.status == resource.data.status
  || !(request.resource.data.status in ['active', 'paused'])
  || request.auth.uid == resource.data.trainerId)
```

This currently means: **any status change is allowed unless the target is `active` or `paused`, in which case only the trainer may do it.** Closing the "PR4 lock" is NOT simply deleting the trainer escape — that would also break the *legitimate* trainer `pause()` (target `paused`, a demotion, weight-safe, and correctly client-side forever). The two targets need different treatment:

- **`paused` target**: keep exactly as-is (trainer-only). `pause()` (active→paused, demotion) must keep working client-side — it is not a scope target for CF migration, and the existing rules test `"pause: PF can transition active -> paused"` must keep passing unchanged.
- **`active` target**: must become **unconditionally blocked for every client**, trainer included — both `pending→active` (accept) and `paused→active` (resume) go through the CF from now on. Concretely, the OR needs to split into two independent clauses instead of one array-membership check, e.g. (illustrative, not final syntax):
  ```
  && (request.resource.data.status == resource.data.status
      || (request.resource.data.status == 'paused' && request.auth.uid == resource.data.trainerId)
      || (request.resource.data.status == 'terminated'))
  ```
  i.e. delete the `active` branch entirely rather than widen the block set. Getting this wrong (e.g. leaving `'active'` reachable via the trainerId branch, or accidentally blocking `paused`) is the single highest-risk line in this PR — it is exactly the kind of change `trainer-links-paywall-rules.test.ts` exists to pin down, and that file's own comment #4 ("PR1 explicitly does NOT lock the pending→active promotion yet ... a plain client accept() write must still succeed here, or PR4's sequencing note is violated") is a test that must be **updated to assert the opposite** in PR4 (`assertFails`, not `assertSucceeds`) plus a new case for `resume` (`paused`→`active` must now fail client-side too — today there is no test for `resume` failing, only one proving it succeeds).
- Client transitions that become impossible after the lock (must move to CF, confirmed complete list): `accept` (pending→active) and `resume` (paused→active). Nothing else. `pause`, `terminate`, `decline`, `cancel`, `setSharedWithTrainer` are all untouched by the lock and stay client-side.
- QA-SEC-002 (athlete cannot self-promote) becomes redundant for the `active` target once the lock is unconditional, but should stay for `paused` (still relevant: an athlete must never be able to write `status: 'paused'` directly either — currently already blocked by the trainer-only branch, unaffected by this change).

## 5. Existing Tests + CI

- `trainer-links-paywall-rules.test.ts` — covers only the PR1 field-pin (`entitlement`/`blockedAt`/`blockedReason` CF-write-only) + a regression suite proving decline/terminate/pause/resume/sharedWithTrainer/accept still work under PR1's rules. It explicitly does NOT yet test the PR4 lock (see comment #4, quoted above) — this file needs both a flipped assertion and new resume-blocked coverage.
- `users-subscription-rules.test.ts` — covers only the PR1 field-pin on `users/{uid}.subscription`/`weightedLoad` (CF-write-only) + regression on unrelated field edits and the pre-existing uid/role/email/createdAt pins. No gate logic tested here at all — this is the natural home for "Admin SDK can write weightedLoad" but the actual gate CF tests will live in new dedicated test files (mirroring `delete-account`'s own test file, not found here but implied by the pattern — I did not locate a `delete-account.test.ts`; confirm during propose whether CF handler tests get a dedicated file or extend an existing one).
- New tests needed: (a) rules — lock flip + resume-blocked, both am + trainer must fail; (b) `runAcceptTrainerLink`/`runResumeTrainerLink` unit tests against `weighted-load.ts`/`effective-limit.ts` boundary cases (7.0 passes, 7.5 blocks, blocked-entitlement links excluded); (c) integration test for the concurrency race (two simultaneous accepts against a trainer at the boundary) — this is the test that will force the architecture decision in §6.
- `functions/package.json` `test:rules` script is an explicit regex allow-list of rules test filenames — any NEW rules test file must be added to that regex or CI will silently skip it (`"(user-public-profiles-rules|trainer-public-profiles-rules|trainer-links-paywall-rules|users-subscription-rules|...)"`). This is a real risk: adding a new file without touching that regex means the file exists, compiles, and never runs in `npm run test:rules`, though it likely still runs under the broader plain `npm test` used by `functions-test` CI job (which runs everything via `jest --forceExit`, no filter) — need to verify this doesn't silently pass locally-but-differently.
- CI (`.github/workflows/ci.yml`, job `functions-test`): Node 20, installs Java 21 (Firestore emulator requirement, not runnable locally per the test files' own comments — "Requires Java 21+ ... NOT runnable locally in this environment"), `firebase emulators:exec --only firestore,auth,storage "npm --prefix functions test -- --runInBand"`. `--runInBand` is REQUIRED because 3+ rules-test suites share the `treino-rules-test` projectId and call `clearFirestore()` in `afterEach` — running in parallel causes intermittent `PERMISSION_DENIED` cross-talk. Any new rules test file must also run serially in this same suite (automatic, since it's the same `jest --runInBand` invocation) — no separate CI wiring needed, just don't introduce a second project ID.

## 6. Open Architecture Decision — source of truth for the gate (needs sdd-propose to resolve)

This is the central design question and it has a real correctness trap, not just a style choice.

**The trap**: if `weightedLoad` is maintained ONLY by an async `onDocumentWritten` trigger (linkAggregate-style, eventually consistent) and the gate CF just *reads* that field to decide, two concurrent `acceptTrainerLink` calls at the boundary (trainer at 6.0, two students accepted "simultaneously") can both read the same stale `weightedLoad: 6.0`, both compute `6.0 + 1.0 = 7.0 <= 7`, both pass, both write `active` — the trigger then reconciles to `8.0` only after both already got in. This is exactly the race the brief asked me to think about, and the current denormalization pattern in this codebase (`linkAggregate` for `athleteCount`) is NOT safe to copy verbatim for a value that gates a write — `athleteCount` is read-only display data with no correctness requirement, `weightedLoad`-as-gate is not the same shape of problem.

**Second trap the brief didn't mention but is real**: if instead `weightedLoad` becomes a value that ONLY the gate CFs (`accept`/`resume`) write transactionally, it will only ever go UP — because `pause`, `terminate`, `decline`, `cancel` remain plain client Firestore writes (rules-only enforced, no CF, confirmed in §1/§4) and never touch `weightedLoad`. Without a reconciling trigger, a trainer who pauses students would see the CF-maintained counter never decrease, eventually permanently locking them out even when genuinely under their real limit.

**Three options for sdd-propose**:

| Option | Mechanism | Pros | Cons | Effort |
|---|---|---|---|---|
| A — pure live recompute | Gate CF ignores the denormalized field; queries `trainer_links` for the trainerId live, inside its own Firestore transaction, computes weight from scratch, gates, then writes `status` + `weightedLoad` in the same transaction. No trigger needed at all for correctness (could still keep one for UI freshness). | Simplest correctness story — single writer during the promotion path, transaction's optimistic concurrency naturally serializes concurrent accepts on the same trainer (both transactions read-then-write `users/{trainerId}`, second one retries and sees the first one's result). | Extra read cost per gate call (bounded — a trainer has at most 15 links); still needs the trigger (or another mechanism) to keep `weightedLoad` accurate after demotions, or the UI-facing field drifts stale between promotions. | Medium |
| B — CF owns all transitions | Migrate `pause`/`terminate`/`decline`/`cancel` to CF too, so `weightedLoad` has exactly one writer (all CFs, all transactional). | Fully consistent, no drift, no dual-writer race. | Massively expands scope beyond what PR4's own code comments define (`firestore.rules` PR1 comment explicitly scopes PR4 to "acceptTrainerLink CF" only); contradicts the "narrower gate" framing already committed to in PR1's QA-SEC-002 comment. | High — likely its own PR, not PR4 |
| C — hybrid (recommended starting point for propose) | Gate CFs (`accept`/`resume`) do the live transactional recompute from `trainer_links` (like A) AND write `weightedLoad` as part of that same transaction. A `linkAggregate`-style async trigger keeps running afterward as a pure reconciliation pass (idempotent full-recompute, same pattern as today) to correct `weightedLoad` after demotions that don't go through a CF. Two writers to `weightedLoad` is safe here specifically because BOTH are idempotent full-recomputes converging to the same value from the same source of truth (`trainer_links`), not increments — last-write-wins is harmless. | Keeps PR4 scoped to the two known transitions; solves both traps; reuses the existing trigger pattern instead of inventing a new one. | Two code paths compute "weighted load from links" — must literally share the same pure function (`computeWeightedLoad` — but note this lives in `functions/src/subscriptions/weighted-load.ts` in TS only; there's a client-side Dart mirror in `lib/features/coach/domain/weighted_load.dart` used by `facturacion_tab.dart` — a THIRD implementation to keep in lock-step, same "LOAD-BEARING port" risk pattern already established by `add-alias.ts`'s `normalize()` comment). | Medium |

I recommend **C** as the framing to hand to sdd-propose, but this is an architecture call, not something to lock in exploration — flagging it explicitly as the #1 open decision.

## 7. Size Forecast

Rough LOC estimate (additions + deletions), based on sibling files already read as size references (`delete-account.ts` ~230 lines, `add-alias.ts` ~170 lines, `link-aggregate.ts` ~155 lines, `account_deletion_service.dart` ~100 lines):

| Area | Estimate |
|---|---|
| `functions/src/subscriptions/` — gate transaction helper + `acceptTrainerLink` + `resumeTrainerLink` onCall wrappers | ~350-450 |
| `functions/src/` — weightedLoad reconciliation trigger (if kept, Option C) | ~120-150 |
| `functions/src/index.ts` exports | ~5 |
| `firestore.rules` edit + updated comments (PR1 comments at 506-516 explicitly reference "PR4" and need rewriting, not just the rule body) | ~40-60 |
| `functions/src/__tests__/` — rules test updates + new CF unit/integration tests (Strict TDD active — tests land in the same commit as the code they cover, typically ≥1:1 with prod LOC in this codebase's existing style) | ~500-700 |
| Dart: new CF service(s) + provider (mirrors `account_deletion_service.dart`) | ~120-160 |
| Dart: 3 callsite migrations (`trainer_dashboard_tab.dart`, `coach_hub_dashboard_screen.dart` ×1 accept, `alumnos_screen.dart` ×1 resume) + `showPlanLimitPaywall` wiring + error mapping | ~100-150 |
| Dart: repository cleanup (deprecate/remove now-dead client `accept`/`resume` Firestore writes) + widget/repo tests | ~150-250 |
| **Total** | **~1400-1900 lines** |

This is well over the 400-line review budget — **chained PRs are required**, not optional. Suggested slices for `sdd-tasks`:
1. Foundation: `weightedLoad` reconciliation trigger + Dart `computeWeightedLoad` already exists client-side (no new work there) — smallest, most isolated, unblocks nothing else visibly but de-risks the denormalization pattern first.
2. Core gate: `acceptTrainerLink` CF + the `firestore.rules` lock (the split-clause change from §4) + accept() callsite migration ×2 + rules test flips — this is the PR that actually closes the originally-scoped hole.
3. Resume gate: `resumeTrainerLink` CF (shares the transactional gate helper from slice 2) + resume() callsite migration + its own rules test coverage — this is the PR that closes the brief's identified gap.
4. Cleanup (optional, could fold into 2 or 3): remove dead `accept`/`resume` write paths from `TrainerLinkRepository`, switch `facturacion_tab.dart` to read the denormalized `weightedLoad` instead of computing client-side.

## Approaches (gate placement — summary, see §6 for full table)

1. **Live transactional recompute per gate call (A)** — Pros: simplest correctness. Cons: needs a separate mechanism for demotions. Effort: Medium.
2. **All transitions behind CF (B)** — Pros: fully consistent. Cons: scope explosion beyond PR4's own documented boundary. Effort: High.
3. **Hybrid — transactional gate + idempotent reconciliation trigger (C)** — Pros: scoped, reuses existing pattern, solves both correctness traps. Cons: shared pure-function duplication across TS/Dart to manage. Effort: Medium. **Recommended.**

## Recommendation

Scope PR4 as: `acceptTrainerLink` + `resumeTrainerLink` CFs sharing one transactional gate helper (Option C architecture), the split-clause `firestore.rules` lock on `status == 'active'` only (leaving `paused` trainer-writable), and the two corresponding Dart callsite migrations + `showPlanLimitPaywall` error routing. Recommend splitting into the 4 chained-PR slices above given the ~1400-1900 line forecast. The `weightedLoad` source-of-truth decision (§6) must be resolved explicitly in `sdd-propose` before `sdd-design`/`sdd-tasks` — it changes the shape of the gate helper.

## Risks

- **Rules regression risk**: the split-clause change in §4 is the highest-risk single edit in this PR — getting it wrong either re-opens the hole (leaving `active` reachable) or breaks legitimate `pause()` (blocking `paused` unintentionally). Must be pinned by tests before merge.
- **Concurrency correctness**: naive "read denormalized field, gate, write status" without a transaction reproduces the exact over-limit race described in the brief, just moved server-side instead of closed. See §6.
- **Triple implementation of `computeWeightedLoad`** (TS gate, TS trigger, Dart UI) — same class of risk the codebase already flags explicitly for `normalize()` in `add-alias.ts` (ADR-CXP-006, "LOAD-BEARING port"). Needs an explicit parity contract/test, not just three copies.
- **CI regex allow-list drift**: new rules test files must be added to `functions/package.json`'s `test:rules` regex or they silently don't run under that script (the broader `functions-test` CI job uses unfiltered `jest`, so likely still covered there — needs confirming, not assumed).
- **Stale comments become misleading if not updated**: `firestore.rules:494-497` ("Business rules ... enforce client-side in the repository; the rules give structural defense") and the PR1 comment block at 506-530 both describe the current, soon-to-be-obsolete state and reference "PR4" by name — must be rewritten as part of this change, not left dangling.
- **Two accept() callsites, easy to miss one**: `trainer_dashboard_tab.dart:423` and `coach_hub_dashboard_screen.dart:1218` both call `.accept()` independently (no shared widget) — both must migrate or one screen silently breaks post-rules-lock.
- **Size**: ~1400-1900 line forecast demands chained PRs; `sdd-tasks` must apply the Review Workload Guard.

## Ready for Proposal

Yes — scope, transition inventory, rules mechanics, and CF/client patterns are all concrete and verified against real code. The one item `sdd-propose` MUST decide before `sdd-design` proceeds is the weightedLoad source-of-truth architecture (§6, recommend Option C as the starting point). Everything else in this document is copy-a-pattern work, not open design.

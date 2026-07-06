# Verify Report: rankings-integrity

**Scope**: both phases at ship tip — `feat/rankings-integrity-p2` (`2242051`), chained on `feat/rankings-integrity-p1` (`79587fe`, `a2da778`, `936cd77`), off `origin/main`.
**Verdict**: **PASS WITH WARNINGS**

## Summary

CRITICAL: 0. WARNING: 2. SUGGESTION: 2.

The security fix is real and well-engineered: the server-side trigger is deployed live, all 14 Jest trigger tests pass against a real emulator (including the load-bearing forged-value-overwrite and loop-termination assertions), `flutter analyze`/`flutter test` are green with zero new issues/regressions, and the tightened `firestore.rules` correctly closes the forged-gymId/forged-metrics vulnerability under adversarial re-reading. Both implementer deviations from the design (`getAfter()` instead of `get()`; the disable-transition exception to the metric pins) are correct, narrowly scoped, and well-documented — I traced the exact call sites and rule logic and found no gap. The main WARNING is the one the task explicitly asked me to weigh: **the rules layer itself has zero automated enforcement test** — the Dart stub file is 100% `skip:`, and no `@firebase/rules-unit-testing` harness exists in this repo. This is a pre-existing, honestly-documented gap (not a regression), but for a security-hardening change it means the actual rule text has never been executed against a real client write.

## Completeness (tasks.md)

35 of 37 tasks `[x]`. The only 2 unchecked (`1.23`, `2.14`) are non-code manual deploy steps by design. I independently confirmed via `firebase functions:list --project treino-dev` that `rankingAggregateOnSession`/`rankingAggregateOnOptIn` are live in `southamerica-east1` (v2, nodejs20) — task 1.23's precondition for 2.14 is genuinely satisfied. Task 2.14 (`firebase deploy --only firestore:rules`) remains the user's pending manual step; I did not run it.

## Gates I ran myself

| Gate | Result |
|---|---|
| `npm --prefix functions run build` | Clean, 0 errors |
| `npm --prefix functions test -- ranking-aggregate` (real Firestore emulator, Java 21 via `openjdk@21`) | **14/14 GREEN**, including forged-value-overwrite and the 6 AD-1 transition-guard cases |
| `npm --prefix functions test` (full suite, emulator) | 149 passed, 6 failed / 2 suites failed — `cascade/storage.test.ts`, `delete-account.smoke.test.ts`. Confirmed by diff (`git diff origin/main..feat/rankings-integrity-p2 -- <those files>`) that **neither file is touched by this change** (0 lines) — pre-existing, unrelated. 0 regressions from this change. |
| `flutter analyze lib test` | 36 issues, 0 new vs. baseline. The 6 issues touching rankings-integrity files are all `duplicate_ignore` warnings in the auto-generated `user_public_profile.freezed.dart` — codegen noise, not new. |
| `flutter test` (full suite) | 3316 passed, 66 skipped (51 pre-existing + 15 new rules stub), 0 failures, "All tests passed!" |
| `firebase deploy --only firestore:rules --dry-run --project treino-dev` | "rules file firestore.rules compiled successfully" — real compiler validation of `getAfter()`/`keys().hasOnly()`/`resource.data.get()` syntax |
| `firebase functions:list --project treino-dev` | Confirmed `rankingAggregateOnOptIn`/`rankingAggregateOnSession` live, v2, southamerica-east1 — AD-9 precondition genuinely met |
| Commit hygiene | 4 commits, all conventional (`feat`/`refactor`/`docs`), zero AI-attribution strings found in `git log` |

## Deviation #1 — `getAfter()` instead of `get()` for the gymId pin

**Verdict: correct, necessary, no regression.**

- Traced `UserRepository.update` (`lib/features/profile/data/user_repository.dart:334-370`): confirmed it dual-writes `users/{uid}` and `userPublicProfiles/{uid}` in a single `WriteBatch` whenever the partial contains `gymId` (also true of `getOrCreate`/`createIfAbsent`, lines 258-313). Firestore rules' `get()` only observes pre-batch committed state and cannot see a sibling write in the same batch — a naive `get(users/{uid})` pin would have denied every real gym change the instant rules deployed. `getAfter()` is the purpose-built fix.
- Re-derived the rule logic by hand (`firestore.rules:369-392` create, `402-430` update): `gymId` pin only fires `if ('gymId' in request.resource.data)`, comparing against `getAfter(...).data.gymId`. Traced `enableRankingOptIn` (`ranking_optin_controller.dart:72-77`): its `gymId` write goes through `UserRepository.update` (dual-batch, covered); its LATER `setRankingOptIn(uid, true)` call is a separate standalone write with no `gymId` key in the payload, so the pin's `!('gymId' in ...)` guard correctly skips it — no interaction/edge-case there.
- Legit gym change (rule ALLOWS): `getAfter()` sees the post-batch value of `users/{uid}.gymId`, which is exactly the value the client just wrote in the same batch — matches, write proceeds.
- Forged gym change (rule DENIES): if a client tried to write `userPublicProfiles/{uid}.gymId = "gym-B"` WITHOUT also writing `users/{uid}.gymId = "gym-B"` in the same batch (i.e. bypassing `UserRepository.update`, writing `userPublicProfiles` directly), `getAfter()` would see the athlete's real (unforged) `users/{uid}.gymId`, which would NOT equal the forged value — denied correctly.
- Edge case (users doc absent on create): traced every public-profile-creating call path (`getOrCreate`, `createIfAbsent`, `profile_setup_notifier.dart`'s self-heal) — all go through `UserRepository`, which always writes `users/{uid}` in the same or an earlier batch/call. No client code path creates `userPublicProfiles/{uid}` standalone without a sibling/prior `users/{uid}` write, so `getAfter()` never hits an absent-doc failure in the normal write order, consistent with the rule's own comment.
- Secondary finding I independently confirmed (not a new gap, but worth restating): `users/{uid}.gymId` itself is fully self-reported with no gym-membership-authority document anywhere in the system, so this pin's real guarantee is "public/private gymId consistency," not "proof of attendance" — this is accurately scoped in both the design and the rule's own comments, not oversold.

## Deviation #2 — disable-transition exception to CF-write-only metric pins

**Verdict: correct, narrowly scoped, not a forgery vector.**

I manually traced the boolean logic in `firestore.rules:445-468` for all 4 metric fields. For `bestSquatKg` (representative):

```
(!('bestSquatKg' in request.resource.data)
 || request.resource.data.bestSquatKg == resource.data.get('bestSquatKg', null)
 || (request.resource.data.get('rankingOptIn', true) == false
     && resource.data.get('rankingOptIn', false) == true
     && request.resource.data.bestSquatKg == null))
```

Adversarial probes:
- **Forge + disable in one write** (`{rankingOptIn:false, bestSquatKg:999}`, before `rankingOptIn:true`): branch 1 fails (field present), branch 2 fails (999 ≠ stored), branch 3 fails because it requires `bestSquatKg == null` exactly, not any value — **denied**. The exception only tolerates the fixed default, never an arbitrary value.
- **Re-enable + forge in one write** (`{rankingOptIn:true, bestSquatKg:999}`): branch 3's first clause requires `request.resource.data.get('rankingOptIn', true) == false` — false when re-enabling — **denied**, falls through to branch 2 (equality pin).
- **Disable+re-enable round trip**: the disable branch can only ever land the metric at its fixed default (`null`/`0`); a subsequent re-enable write can only reassert that same default (branch 2) or wait for the trigger. No laundering path to an arbitrary forged value.
- Cross-checked `UserPublicProfileRepository.clearRankingMetrics` (`user_public_profile_repository.dart:103-114`): writes exactly `{rankingOptIn:false, lifetimeVolumeKg:0, bestSquatKg:null, bestBenchKg:null, bestDeadliftKg:null}` via a standalone `.set(merge:true)` — precisely the shape the exception permits and nothing broader.
- The `gym-rankings` spec's "Opt-In Disable — Unchanged, Client-Initiated" requirement explicitly mandates this behavior continue working ("deflating one's own stats is not a forgery vector") — the implementer correctly followed the spec over the design's informal AD-6 prose when the two conflicted, and documented the conflict at length in the rule comments (lines 434-444). This is the right call: spec is the higher-authority artifact.
- The `resource.data.get(field, default)` / `request.resource.data.get('rankingOptIn', true)` idiom is a **pre-existing pattern already used elsewhere in this ruleset** (`firestore.rules:654-655`, `977-978`), not a novel risk.

## THE KEY QUESTION — is this genuinely test-enforced?

**No — and this is the most important finding.** Answering explicitly, as asked:

- The Jest `ranking-aggregate.test.ts` suite (14/14 green) uses the Admin SDK against a real Firestore emulator. Admin SDK **bypasses Firestore rules entirely** — these tests prove the trigger's aggregation logic is correct and idempotent, but they say **nothing** about whether a client write is denied.
- The new `test/firestore/user_public_profiles_rules_test.dart` (15 tests) is a **100% `skip:` documentation stub** — I confirmed 15 `test()` calls and 16 `skip:` occurrences, and confirmed `@firebase/rules-unit-testing` is absent from `functions/package.json` (no match). `fake_cloud_firestore` (used by all other Dart repository tests) does not enforce rules at all.
- Therefore: **there is no executable test anywhere in this repo that asserts "an authenticated client write forging `bestSquatKg` is DENIED by the rules."** The only evidence for the rule's correctness is (a) my own hand-derived boolean-logic trace above, (b) the `firebase deploy --dry-run` compile check (syntax only, not semantics), and (c) the implementer's manual reasoning captured in apply-progress.
- This gap is **pre-existing** — the two files this mirrors (`payments_rules_test.dart`, `reviews_rules_test.dart`) are also CI-skipped stubs, never enforced. It is not a regression introduced by this change, and the new stub file explicitly self-documents this limitation and directs `sdd-verify` to flag it (which this report does).
- **Severity assessment**: for a change whose entire purpose is closing a security hole in Firestore rules, shipping without a single real rules-enforcement test is a genuine, material gap — not a blocker for THIS PR (the gap predates it and reversing it is a larger, separate undertaking), but it means confidence in the fix rests on manual logic tracing (which I did, and it holds up), not automation.
- **Recommendation**: install `@firebase/rules-unit-testing` and wire a real emulator-backed JS rules-assertion suite (same emulator infra already used by the Jest trigger tests) as a **required follow-up**, ideally before or shortly after `firebase deploy --only firestore:rules` (task 2.14) ships to production. This should be tracked as its own change, not bolted onto this one.

## Scenario → Test Coverage Matrix

Both spec files, 21 scenarios total.

### `user-public-profiles-layer` (12 scenarios)

| Scenario | Status | Evidence |
|---|---|---|
| Write containing unknown field denied | Documented-only | Rule: `keys().hasOnly([15])`, `firestore.rules:372-379,405-412`. Stub test `skip:`. |
| Write containing only known fields succeeds | Documented-only | Same rule block. Stub test `skip:`. |
| Non-owner write denied regardless of allowlist | Documented-only | Rule: `request.auth.uid == uid`, unchanged. Stub test `skip:`. |
| uid cannot be changed on update | Documented-only | Rule: `request.resource.data.uid == resource.data.uid`, unchanged. Stub test `skip:`. |
| Athlete cannot self-assign to a gym they don't attend | Documented-only (manually verified via logic trace above) | Rule: `getAfter()` pin, `firestore.rules:428-430`. Stub test `skip:`. |
| Athlete can write their own real gymId | Documented-only (manually verified) | Same rule. Stub test `skip:`. |
| Client raw-write of forged metric denied | Documented-only (manually verified) | Rule: equality pin, `firestore.rules:445-468`. Stub test `skip:`. |
| Client write re-asserting existing metric not rejected | Documented-only (manually verified) | Same rule, branch 2. Stub test `skip:`. |
| Server-side recompute writes via Admin SDK (bypasses rules) | **Executed** | `ranking-aggregate.test.ts` "forged-value overwrite" — 14/14 green, Admin SDK confirmed to write successfully against the tightened rules (via 2.12's re-run). |
| Out-of-range numeric metric rejected | Documented-only | Rule: AD-8 bounds, `firestore.rules:477-495`. Stub test `skip:`. |
| Non-boolean rankingOptIn rejected | Documented-only | Rule: `is bool`, `firestore.rules:432-433`. Stub test `skip:`. |
| Read access unchanged | Documented-only | Rule: `allow read: if request.auth != null`, unchanged, `firestore.rules:343`. Stub test `skip:`. |

### `gym-rankings` (9 scenarios)

| Scenario | Status | Evidence |
|---|---|---|
| Forged client value does not appear on leaderboard | **Executed** | `ranking-aggregate.test.ts` "forged-value overwrite" — seeds `bestSquatKg:999`, asserts overwrite to real value `110`. Core security assertion, GREEN. |
| Leaderboard values trace to real session data | **Executed** | `ranking-aggregate.test.ts` "first-finish recompute" / "second-session recompute" — GREEN. |
| Opting in with real history eventually shows real metrics | **Executed** | `ranking-aggregate.test.ts` "no-session opt-in" + AD-1 transition-guard tests (via `recomputeMetrics` + `shouldRecomputeOnOptInTransition`) — GREEN. |
| Opting in with zero qualifying sessions shows zero, not stale/forged | **Executed** | `ranking-aggregate.test.ts` "recomputeMetrics: no-session opt-in" — GREEN. |
| enableRankingOptIn no longer computes metrics client-side | **Executed** | `ranking_optin_controller_test.dart` (Phase 1, `verifyNever` on metric writes) — part of the 3316-test green `flutter test` run; confirmed no residual metric-write code via `rg` grep of `session_repository.dart`/`ranking_optin_controller.dart` (comments only). |
| Disabling opt-in clears metrics and removes from leaderboards | **Executed** | Pre-existing SCENARIO-RANK-5c, unmodified, still green in the full `flutter test` run. |
| Disable remains direct client write, no server round-trip | **Executed** | Same test; `clearRankingMetrics` unmodified by this change, confirmed by reading the file. |
| Finishing session updates metrics via server path | **Executed** | `ranking-aggregate.test.ts` "first/second-finish recompute" (trigger side) + `session_repository_test.dart` SCENARIO-RANK-3g (metrics untouched by `finish()`, client side) — both green. |
| workoutsCount and racha still update as before | **Executed** | `session_repository_test.dart` SCENARIO-RANK-3h — green. |

**Honest tally**: 9 of 21 scenarios executed by a real, rules-bypassing-aware test (trigger logic + client non-write assertions). 12 of 21 (all rules-layer scenarios in `user-public-profiles-layer`) are documented-only / CI-skipped — I independently re-verified their correctness by hand-tracing the actual rule text (not just trusting the apply-progress claim), and found no discrepancy, but this is manual verification, not automated enforcement.

## Design coherence (design.md AD-1..AD-9)

| AD | Status |
|---|---|
| AD-1 (two triggers, loop-proof) | Implemented exactly as designed; loop-termination guard exhaustively unit-tested (6 cases), including the critical true→true re-fire case returning `false`. |
| AD-2 (client write restructure) | Implemented; verified no residual metric-write code remains. |
| AD-3 (CF-write-only mechanics) | Implemented with the documented disable-exception (spec-mandated, verified above). |
| AD-4 (gymId pin) | Implemented with `getAfter()` deviation (verified necessary and correct above). |
| AD-5 (eventual-consistency UX) | Not directly re-verified (UI-level, no new test targets this) — accepted per reviewAggregate precedent, consistent with existing patterns. |
| AD-6 (clearRankingMetrics under new rules) | Implementer's resolution (spec over design prose) verified correct via logic trace. |
| AD-7 (test plan) | Trigger side fully executed; Dart rules side is documented-only (see KEY QUESTION above). |
| AD-8 (range bounds) | Implemented, `firestore.rules:477-495`, bounds match design exactly (`<=1000`, `<=100_000_000`), plus an added `>=0` lower bound (reasonable defense-in-depth, not a deviation of concern). |
| AD-9 (ship order) | Verified independently via `firebase functions:list` — both triggers confirmed live in `southamerica-east1` before rules deploy, satisfying the hard dependency. |

## Issues

**CRITICAL**: none.

**WARNING**:
1. Zero automated test enforces the actual Firestore rules text for a client write (see KEY QUESTION section). Recommend a follow-up change to install `@firebase/rules-unit-testing` and wire a real emulator-backed rules-assertion suite before or shortly after the rules deploy ships.
2. Task 2.14 (`firebase deploy --only firestore:rules`) has not yet been run — the hardened rules are not yet live in production. Until it ships, the vulnerability described in audit obs #390 (forged gymId/metrics via direct client write) remains open in production, even though the server-side trigger is already live and correcting forged values on every recompute.

**SUGGESTION**:
1. Consider adding a lightweight comment/README note in `test/firestore/` pointing at this verify report or a tracked follow-up ticket, so the "install rules-unit-testing" recommendation doesn't get lost once this branch merges.
2. The `AD-5` eventual-consistency UX claim (leaderboard row shows loading/empty state for ~1-3s after opt-in) has no dedicated widget-level test — low risk given the query-level `rankingOptIn==true` filter already prevents others from observing a stale row, but worth a follow-up UI test if this becomes a support-ticket source.

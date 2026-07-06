# Proposal: Rankings Integrity — close the forged-metrics vulnerability

## Intent

Close a **HIGH** security finding (audit 2026-07-03, obs #390, confidence 0.9): the `userPublicProfiles/{uid}` update rule (`firestore.rules:312-334`) checks only owner + `uid` immutability — no field allowlist, no per-field validation. An authenticated athlete can `set(merge:true)` a forged doc and (a) self-assign to any `gymId` they don't attend and (b) fabricate ranking metrics (`bestSquatKg`, `lifetimeVolumeKg`, …). `leaderboard()` is world-readable → forger tops any gym's board instantly. Exploit confirmed. Premise corrected (obs #392): the org blocks public **callables** only — Firestore **triggers are deployed** (`reviewAggregate` et al.), so a full server-side closure IS available.

## Scope

### In Scope
- **Rules hardening** (`firestore.rules` userPublicProfiles): `keys().hasOnly([...15 fields...])` on create+update; type/range checks on numerics; `gymId == get(users/$(uid)).data.gymId` cross-doc pin (proven pattern in this ruleset); the 4 ranking metrics (`lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, `bestDeadliftKg`) become **CF-write-only** (rules pin `== resource.data.<field>` on client writes; Admin SDK bypasses rules); fix the stale header comment (says 5 fields, doc has 15).
- **Recompute trigger** (`functions/src/`): new `onDocumentWritten` mirroring `review-aggregate.ts` — fires on `users/{uid}/sessions/{sessionId}` (cross-collection target avoids self-trigger loop), idempotent full-requery, catch-log-never-rethrow, no-op if profile absent. Recomputes the 4 metrics from real sessions/setLogs via Admin SDK (logic ports from `SessionRepository.finish()` + `familyMaxWeight`), gated on `rankingOptIn`, overwriting any forged value.
- **Client restructure**: `enableRankingOptIn` writes only `rankingOptIn:true` intent (stops client-computing metrics); `SessionRepository.finish()` metric recompute moves server-side (keeps `workoutsCount`/`racha`); `gymId`/`gymName` stay client-written but rules-`get()`-pinned; `clearRankingMetrics` (disable) stays client-writable — deflation is not a forgery vector.

### Out of Scope
- `workoutsCount` / `racha` / follower-count forgery (allowlisted, unchanged — separate risk).
- `trainerPublicProfiles.averageRating/reviewCount` latent gap (ADR-RV-005 adjacent) — unless pulled in (see Q4).
- CI emulator wiring for Dart rules tests (pre-existing gap, all collections) — decision only (see Q5).

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `user-public-profiles-layer`: `userPublicProfiles` update rule gains a field allowlist, cross-doc `gymId` pin, and CF-write-only enforcement for the 4 ranking metrics (security-boundary change).
- `gym-rankings`: ranking metrics become server-authoritative — computed by a Firestore trigger, not client code; opt-in enable no longer client-computes metrics.

## Approach

Approach B (full closure) in one change, sliced into **2 chained PRs**: **PR#1 rules-hardening** (allowlist + gymId pin + CF-write-only pins + comment fix — ships the HIGH gym-forgery fix fast, no client/CF changes) → **PR#2 recompute trigger + client restructure** (authoritative metric closure, strictly additive on PR#1). Trigger mirrors the proven `reviewAggregate` shape; CF-write-only follows ADR-RV-005 (rules deny client, Admin SDK bypasses).

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `firestore.rules` (userPublicProfiles ~312-334) | Modified | allowlist, gymId get()-pin, metric CF-write-only pins, comment fix |
| `functions/src/ranking-aggregate.ts` (new) | New | recompute trigger on `users/{uid}/sessions/{sessionId}` |
| `functions/src/index.ts` | Modified | export the new trigger |
| `functions/src/__tests__/ranking-aggregate.test.ts` (new) | New | Jest + emulator, mirrors `review-aggregate.test.ts` |
| `ranking_optin_controller.dart` | Modified | `enableRankingOptIn` writes intent only, stops computing metrics |
| `session_repository.dart` | Modified | `finish()` metric recompute removed (server owns it) |
| `user_public_profile_repository.dart` | Modified | metric writes removed from client path; gymId stays get()-pinned (not trigger-owned) |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Trigger self-retrigger loop | Low | Fire on `sessions` subcollection, write to parent profile (cross-collection, reviewAggregate precedent) |
| Eventual-consistency window on opt-in (metrics ~1-3s late) | Med | Accepted per reviewAggregate precedent; interim loading state (see Q3) |
| Range bounds reject legit elite lifts | Med | Product-set bounds (see Q1); trigger is authoritative regardless of bound |
| Rules test not CI-enforced | High (pre-existing) | Real coverage via Jest trigger test; document Dart-rules gap (Q5) |

## Rollback Plan
PR#1: revert `firestore.rules` block to restore prior (permissive) rule — no data migration. PR#2: revert the trigger export + Dart changes; client resumes computing metrics. Both additive and independently reversible; no schema change, no index change.

## Dependencies
- Firestore emulator for the Jest trigger test (already used by `review-aggregate.test.ts`).
- Region `southamerica-east1` for the new function.

## Open Questions (for spec / design)
1. **Range bounds** for lifts/volume — product/domain call. *Lean*: generous caps (e.g. 1000kg/lift, 100M volume) as a plausibility floor; trigger is the real authority, so bounds only stop absurd client values.
2. **Trigger event source** — `users/{uid}/sessions/{sessionId}` vs a `rankingOptIn`-transition trigger on `userPublicProfiles`. *Lean*: sessions subcollection — the profile-doc trigger risks self-trigger loops. Flag the tradeoff (opt-in enable produces no session write, so metrics populate on next `finish()` — confirm interim state, see Q3).
3. **Eventual consistency on opt-in enable** — metrics appear ~1-3s after the trigger runs, not synchronously. *Lean*: interim empty/loading row on the just-opted-in user's own leaderboard row is acceptable (matches reviewAggregate UX); spec the loading state.
4. **Also pin `trainerPublicProfiles.averageRating/reviewCount`?** *Lean*: NO — out of stated scope; track as separate follow-up (ADR-RV-005 is convention-only, same latent gap).
5. **Wire real CI emulator rules tests?** *Lean*: NO — separate change; this change gets real coverage via the Jest trigger test. Document the Dart-rules CI gap as a known limitation.

## Success Criteria
- [ ] Client `set(merge:true)` forging `gymId`/metrics is DENIED by rules (allowlist + gymId pin + metric CF-write-only pins).
- [ ] Trigger recomputes the 4 metrics from real sessions and overwrites any forged value (Jest + emulator test green).
- [ ] `enableRankingOptIn` writes intent only; `finish()` no longer client-computes metrics; `flutter analyze` 0, `flutter test` green.
- [ ] Stale header comment corrected to reflect 15 fields.

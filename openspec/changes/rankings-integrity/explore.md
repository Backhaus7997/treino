# Exploration — rankings-integrity

Fix for the HIGH security finding (audit 2026-07-03): `userPublicProfiles/{uid}` update rule has no field allowlist/validation, letting an authenticated athlete forge ranking metrics + self-assign to any gym via a raw `set(merge:true)`.

Premise correction (verified 2026-07-06): org blocks public CALLABLES only — Firestore TRIGGERS are allowed and deployed (`reviewAggregate` et al.). Full server-side fix IS available.

---

## The vulnerability (confirmed)

`firestore.rules:312-334` — update rule checks only owner + `uid` immutability. No `keys().hasOnly()`, no per-field checks on the other 14 fields. Header comment is STALE ("Contains ONLY the 5 public fields" — doc now has 15: `uid, displayName, displayNameLowercase, avatarUrl, gymId, gymName, workoutsCount, racha, followersCount, followingCount, sharedTemplatesWithAthletes, rankingOptIn, lifetimeVolumeKg, bestSquatKg, bestBenchKg, bestDeadliftKg`).

Exploit: `set(userPublicProfiles/{ownUid}, {rankingOptIn:true, gymId:'<any>', bestSquatKg:400, lifetimeVolumeKg:999999}, merge:true)` passes the rule; `leaderboard()` (repo:129-144) surfaces it; world-readable → visible to all immediately.

## Approach A — rules-only

`keys().hasOnly([...15...])` + type/range checks + **`gymId == get(/databases/$(db)/documents/users/$(uid)).data.gymId`** (cross-doc `get()` is proven in this ruleset: `gyms` reads `users.role`, `routines` reads `userPublicProfiles.sharedTemplatesWithAthletes`).

| Vector | Coverage |
|---|---|
| gymId self-assignment to a gym you don't attend | **CLOSED** (get() pin) |
| rankingOptIn / type / shape tampering | **CLOSED** |
| Implausible metric values | **BOUNDED** (range cap) |
| Plausible forged metrics (realistic fake PRs) | **NOT closed** — rules can't aggregate over sessions subcollection |

Effort: Low. No client/CF changes.

## Approach B — recompute trigger + CF-write-only rules (reviewAggregate pattern)

`reviewAggregate` findings: `onDocumentWritten("reviews/{id}")`, idempotent full-requery, writes to a DIFFERENT collection (`trainerPublicProfiles`) — that's how it avoids infinite retrigger; catch-log-never-rethrow; no-op if target absent. CF-write-only for `averageRating`/`reviewCount` is enforced by CLIENT convention + allowlist + test (ADR-RV-005), NOT by a rules mechanism — because Admin SDK writes bypass rules entirely; rules just DENY the client from writing those fields.

Design: trigger off `users/{uid}/sessions/{sessionId}` writes (cross-collection shape, no loop), recompute `lifetimeVolumeKg`/`best*Kg` from real sessions+setLogs via Admin SDK (logic ports directly from `SessionRepository.finish()` + `familyMaxWeight`), overwrite forged values. Rules pin the 4 metrics client-immutable.

Restructuring impact: `RankingOptInController.enableRankingOptIn` stops client-computing metrics (only writes `rankingOptIn:true` intent, ~40 lines removed); `SessionRepository.finish()` metric recompute moves server-side; `clearRankingMetrics` (disable) can stay client-writable (deflating your own stats isn't a forgery vector). gymId stays get()-pinned (simpler than trigger-owned). Latency: ~1-3s eventual consistency on leaderboard after finish (accepted per reviewAggregate precedent). Effort: Medium-High (new TS trigger + Jest/emulator test + rules + 2 Dart files).

## Approach C — hybrid, phased (RECOMMENDED)

PR#1 = Approach A (ships the HIGH-severity gym-forgery fix fast, no client/CF changes). PR#2 = Approach B trigger (authoritative closure of metric forgery). Rationale: gym self-assignment (appearing on a gym you have zero connection to) is arguably worse than an inflated number on your own real gym's board; A closes it completely and immediately. B is strictly additive, can land without blocking A. Do NOT ship A alone silently — document the residual plausible-metric-forgery risk as an explicit tracked follow-up.

## Testing reality (important)

`test/firestore/*_rules_test.dart` are ALL permanently-skipped stubs (`skip: 'emulator required'`) — ZERO CI enforcement; `.github/workflows/ci.yml` only runs `flutter analyze`/`flutter test`, never the emulator. The REAL working test infra is `functions/src/__tests__/` (Jest + `firebase-admin` + `FIRESTORE_EMULATOR_HOST`, e.g. `review-aggregate.test.ts`). So: a new Dart rules test documents intent but won't enforce in CI unless CI is also wired for the emulator (pre-existing gap, all collections). Approach B's trigger gets REAL coverage via a `functions/src/__tests__/` Jest test mirroring `review-aggregate.test.ts`.

## Write-path impact map

| Field(s) | Current writer | A | B |
|---|---|---|---|
| gymId/gymName | UserRepository.update, enableRankingOptIn/syncGymIfDesynced | rules pin `== get(users/uid).gymId` | unchanged (stays get()-pinned) |
| rankingOptIn | setRankingOptIn/clearRankingMetrics | type/shape checked | unchanged (intent signal, client-writable) |
| lifetimeVolumeKg, bestSquat/Bench/DeadliftKg | finish(), enableRankingOptIn, updateCounters | range-bounded only (plausible forgery passes) | CF-write-only; finish()+enableRankingOptIn stop computing them |
| workoutsCount, racha | finish() | allowlisted, unchanged (out of scope) | unchanged |
| followersCount/followingCount, sharedTemplatesWithAthletes | FriendshipRepository, setShared… | included in allowlist | unchanged |

## Relevant files
- `firestore.rules:312-334` (vuln + stale comment); `:385-425` gyms get(users.role) proof; `:43-65` routines get() proof; `:786-855` payments/reviews hasOnly() pattern
- `functions/src/review-aggregate.ts` (pattern to mirror); `functions/src/index.ts` (deployed triggers, org-policy comment); `functions/src/__tests__/review-aggregate.test.ts` (real emulator test)
- `lib/features/profile/application/ranking_optin_controller.dart` (enableRankingOptIn 80-119, syncGymIfDesynced 140-164)
- `lib/features/profile/data/user_public_profile_repository.dart` (updateCounters/setRankingOptIn/clearRankingMetrics/leaderboard)
- `lib/features/workout/data/session_repository.dart:79-174` (finish recompute); `lib/features/gym_rankings/domain/main_lift_family_map.dart` (familyMaxWeight, portable server-side)
- `lib/features/profile/data/user_repository.dart:27-65` (ADR-RV-005 precedent); `test/firestore/*` (skipped stubs); `.github/workflows/ci.yml` (no emulator)

## Open decisions for propose
1. Scope: A alone (fast, residual metric-forgery tracked) vs A+B phased in one change.
2. Also rules-pin `trainerPublicProfiles.averageRating/reviewCount` (same latent gap, ADR-RV-005 is convention-only)? Adjacent, out of stated scope.
3. Range bounds for lift/volume caps — product/domain call.
4. Trigger event source for B: `users/{uid}/sessions/{sessionId}` (recommended).
5. `clearRankingMetrics` client-writability under B (recommend keep — deflation isn't forgery).
6. Wire real CI-enforced emulator rules tests (pre-existing gap) — in scope or separate?

Engram: `sdd/rankings-integrity/explore`.

# Delta for User Public Profiles Layer

## MODIFIED Requirements

### Requirement: Opt-In Toggle Lifecycle

The system MUST provide an athlete-facing toggle for `rankingOptIn`. Enabling it MUST backfill the athlete's current lifetime volume and best-lift PRs from their own session/SetLog history in a single client-side, one-time operation, AND MUST denormalize the athlete's current `gymId` and resolved `gymName` onto `userPublicProfiles/{uid}`, reading `gymId` from `users/{uid}` as the source of truth. Disabling it MUST clear all ranking-metric fields on the athlete's own `UserPublicProfile` (unchanged from v1; `gymId`/`gymName` are NOT cleared on disable).

(Previously: enabling only backfilled `lifetimeVolumeKg`/`best<Lift>Kg` and flipped `rankingOptIn`; it never wrote `gymId`/`gymName`, leaving opt-in dependent on a prior, possibly-stale dual-write.)

#### Scenario: Enabling opt-in backfills historical metrics

- GIVEN an athlete with `rankingOptIn == false` and a training history containing sessions with a 110kg squat PR and 3,400kg total lifetime volume
- WHEN they enable `rankingOptIn`
- THEN `rankingOptIn` becomes `true`
- AND `lifetimeVolumeKg` is set to `3400`, `bestSquatKg` to `110`, `bestBenchKg`/`bestDeadliftKg` analogously (0 if no matching lifts)

#### Scenario: Enabling opt-in syncs gymId and gymName from the source of truth

- GIVEN an athlete whose `users/{uid}.gymId == "gym-123"` but whose `userPublicProfiles/{uid}.gymId` is `null` (desynced, gym chosen before the dual-write existed)
- WHEN they enable `rankingOptIn`
- THEN `userPublicProfiles/{uid}.gymId` is written as `"gym-123"`
- AND `userPublicProfiles/{uid}.gymName` is written to the resolved display name for `"gym-123"`
- AND the athlete subsequently appears in `"gym-123"`'s leaderboards without re-selecting a gym

#### Scenario: Disabling opt-in clears ranking metrics but not gym fields

- GIVEN an athlete with `rankingOptIn == true`, `lifetimeVolumeKg == 3400`, `bestSquatKg == 110`, `gymId == "gym-123"`
- WHEN they disable `rankingOptIn`
- THEN `rankingOptIn` becomes `false`
- AND `lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, `bestDeadliftKg` are cleared
- AND `gymId`/`gymName` remain unchanged (not part of the ranking-metric clear)

#### Scenario: Streak is not backfilled on enable

- GIVEN an athlete enabling `rankingOptIn`
- WHEN the backfill runs
- THEN `racha` is NOT recomputed by the backfill — it reuses the value already denormalized by session-finish streak logic

#### Scenario: Opt-in succeeds for an athlete with no gym

- GIVEN an athlete with `users/{uid}.gymId == null` (or `kNoGymId`)
- WHEN they enable `rankingOptIn`
- THEN `rankingOptIn` becomes `true` and metric backfill completes normally
- AND `userPublicProfiles/{uid}.gymId` is written as `null`/`kNoGymId` and `gymName` as `null`
- AND the opt-in call does NOT fail or throw due to the missing gym
- AND the athlete does not appear in any leaderboard until they select a gym (per `gym-rankings` Gym Scoping), which is expected — leaderboard visibility, not opt-in success, requires a gym

#### Scenario: gymName resolution failure does not abort opt-in

- GIVEN an athlete with a valid `gymId` whose gym-name resolution (the same lookup `UserRepository._resolveGymName` performs) throws or times out
- WHEN they enable `rankingOptIn`
- THEN `rankingOptIn` still becomes `true` and `gymId` and all ranking metrics are still written
- AND `gymName` is written as `null` (or left unset) rather than blocking the rest of the opt-in write
- AND the failure is tolerated the same way `_resolveGymName` failures are tolerated in the existing `UserRepository` dual-write path

---

### Requirement: Firestore Rules — Ranking Fields

The existing owner-write rule on `userPublicProfiles/{uid}` (`allow update: if request.auth != null && request.auth.uid == uid && request.resource.data.uid == resource.data.uid`) MUST cover writes to `rankingOptIn`, all ranking-metric fields, AND the `gymId`/`gymName` write performed as part of `enableRankingOptIn` — no new rule is required. `read`/`list` MUST remain open to any authenticated user, unchanged. An athlete MUST only be able to write their OWN `userPublicProfiles` document; this invariant MUST NOT be weakened by the opt-in `gymId`/`gymName` denormalization.

(Previously: rule text unchanged; ranking fields existed under the owner-update surface but `gymId`/`gymName` writes from the opt-in flow specifically were not yet part of that flow's write set.)

#### Scenario: Owner writes their own gymId/gymName via opt-in

- GIVEN an authenticated athlete with uid `U`
- WHEN `enableRankingOptIn` writes `gymId`/`gymName` to `userPublicProfiles/U` alongside ranking fields
- THEN the write succeeds under the existing owner-update rule (no rule change needed)

#### Scenario: Non-owner cannot trigger a gymId/gymName write on another athlete's doc

- GIVEN an authenticated athlete with uid `A`
- WHEN any client attempts to write `gymId`/`gymName` to `userPublicProfiles/B` (a different athlete) via the opt-in write path
- THEN the write is rejected by the existing owner-only update rule

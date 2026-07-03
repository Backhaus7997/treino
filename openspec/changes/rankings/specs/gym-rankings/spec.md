# Gym Rankings Specification

## Purpose

Per-gym, opt-in leaderboards on three dimensions — streak (racha), lifetime training volume, and main-lift PRs (squat/bench/deadlift) — computed with zero Cloud Functions by querying denormalized fields on `UserPublicProfile`, scoped to `gymId`.

## Requirements

### Requirement: Opt-In Toggle Lifecycle

The system MUST provide an athlete-facing toggle for `rankingOptIn`. Enabling it MUST backfill the athlete's current lifetime volume and best-lift PRs from their own session/SetLog history in a single client-side, one-time operation. Disabling it MUST clear all ranking-metric fields on the athlete's own `UserPublicProfile`.

#### Scenario: Enabling opt-in backfills historical metrics

- GIVEN an athlete with `rankingOptIn == false` and a training history containing sessions with a 110kg squat PR and 3,400kg total lifetime volume
- WHEN they enable `rankingOptIn`
- THEN `rankingOptIn` becomes `true`
- AND `lifetimeVolumeKg` is set to `3400` (computed from their own session history)
- AND `bestSquatKg` is set to `110` (computed from their own SetLog history)
- AND `bestBenchKg`/`bestDeadliftKg` are set analogously from their own history (0 if no matching lifts)

#### Scenario: Disabling opt-in clears ranking metrics

- GIVEN an athlete with `rankingOptIn == true`, `lifetimeVolumeKg == 3400`, `bestSquatKg == 110`
- WHEN they disable `rankingOptIn`
- THEN `rankingOptIn` becomes `false`
- AND `lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, `bestDeadliftKg` are cleared (reset to `0`/absent)

#### Scenario: Streak is not backfilled on enable

- GIVEN an athlete enabling `rankingOptIn`
- WHEN the backfill runs
- THEN `racha` is NOT recomputed by the backfill — the ranking reuses the value already denormalized by the existing session-finish streak logic

---

### Requirement: Streak Leaderboard

The system MUST provide a per-gym streak leaderboard as a Firestore query: `userPublicProfiles where gymId == <athlete's gym> and rankingOptIn == true order by racha desc limit N`.

#### Scenario: Streak leaderboard ranks opted-in athletes by racha

- GIVEN a gym with 3 opted-in athletes with `racha` values 5, 12, and 8
- WHEN the streak leaderboard is queried for that gym
- THEN the results are ordered `12, 8, 5`

---

### Requirement: Volume Leaderboard

The system MUST provide a per-gym lifetime-volume leaderboard as a Firestore query: `userPublicProfiles where gymId == <athlete's gym> and rankingOptIn == true order by lifetimeVolumeKg desc limit N`.

#### Scenario: Volume leaderboard ranks opted-in athletes by lifetime volume

- GIVEN a gym with 2 opted-in athletes with `lifetimeVolumeKg` values 3400 and 5200
- WHEN the volume leaderboard is queried for that gym
- THEN the results are ordered `5200, 3400`

---

### Requirement: Main-Lift Leaderboards

The system MUST provide three per-gym leaderboards, one per main lift, each as a Firestore query: `userPublicProfiles where gymId == <athlete's gym> and rankingOptIn == true order by best<Lift>Kg desc limit N`, for `<Lift>` in `{Squat, Bench, Deadlift}`. Values MUST derive exclusively from training-log SetLogs (never from `PerformanceTest` trainer-entered 1RMs).

#### Scenario: Squat leaderboard ranks opted-in athletes by bestSquatKg

- GIVEN a gym with 2 opted-in athletes with `bestSquatKg` values 100 and 140
- WHEN the squat leaderboard is queried for that gym
- THEN the results are ordered `140, 100`

#### Scenario: Main-lift value never derives from PerformanceTest

- GIVEN an athlete with a trainer-entered `PerformanceTest.squat1rmKg == 150` but no matching squat SetLog in their training log
- WHEN their `bestSquatKg` is computed (on finish or backfill)
- THEN `bestSquatKg` is unaffected by the `PerformanceTest` value and reflects only training-log SetLog data

---

### Requirement: Privacy — Opt-In Enforcement

A non-opted-in athlete's ranking metrics MUST NOT appear in any leaderboard and MUST NOT be publicly exposed through ranking queries, regardless of their underlying training activity.

#### Scenario: Non-opted-in athlete is excluded from all leaderboards

- GIVEN an athlete in a gym with `rankingOptIn == false` and a real training history (streak, volume, PRs)
- WHEN any of the three leaderboards is queried for that gym
- THEN the athlete does not appear in any of them

#### Scenario: Toggling opt-in off mid-session removes athlete from future queries

- GIVEN an athlete who appears in leaderboards with `rankingOptIn == true`
- WHEN they disable `rankingOptIn`
- THEN subsequent leaderboard queries for their gym no longer include them

---

### Requirement: Gym Scoping and No-Gym Exclusion

Rankings MUST be scoped to `UserPublicProfile.gymId`. Athletes whose `gymId` is `null` or equals `kNoGymId` MUST be excluded from every leaderboard, even if `rankingOptIn == true`.

#### Scenario: Athlete without a gym never appears in a leaderboard

- GIVEN an athlete with `rankingOptIn == true` and `gymId == null` (or `kNoGymId`)
- WHEN any leaderboard is queried for any gym
- THEN the athlete does not appear in the results

#### Scenario: Leaderboard only includes athletes from the queried gym

- GIVEN two gyms, A and B, each with opted-in athletes
- WHEN gym A's leaderboard is queried
- THEN only athletes with `gymId == A` appear in the results

---

### Requirement: Read Access

Any authenticated athlete MUST be able to read their own gym's leaderboards. No additional Firestore rule is required beyond the existing `allow read: if request.auth != null` on `userPublicProfiles`.

#### Scenario: Authenticated athlete reads their gym's leaderboard

- GIVEN an authenticated athlete belonging to gym G
- WHEN they request any of the three leaderboards for gym G
- THEN the query succeeds and returns opted-in athletes from gym G

---

### Requirement: Empty States

A gym with no opted-in athletes MUST return an empty leaderboard rather than an error, for all three dimensions.

#### Scenario: Gym with zero opted-in athletes shows empty leaderboard

- GIVEN a gym where no athlete has `rankingOptIn == true`
- WHEN any leaderboard is queried for that gym
- THEN the query returns an empty result set (not an error)

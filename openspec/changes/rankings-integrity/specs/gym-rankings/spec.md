# Delta for Gym Rankings

## MODIFIED Requirements

### Requirement: Metric Authority — Server-Computed, Not Client-Asserted

Ranking metrics (`lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, `bestDeadliftKg`) displayed on any gym leaderboard MUST reflect values computed server-side (Admin SDK recompute trigger) from the athlete's real sessions/SetLogs, never a value a client asserted directly. A forged client value MUST NOT be observable on a leaderboard, either because the rules layer denied the write outright or because the server-side recompute overwrites it.

(Previously: metric values were computed and written entirely client-side — by `SessionRepository.finish()` and `RankingOptInController.enableRankingOptIn` — with no independent server-side authority; a client capable of bypassing the (then-missing) field checks could set any value directly.)

#### Scenario: Forged client value does not appear on the leaderboard

- GIVEN an athlete who attempts to set `bestSquatKg: 999` directly on their own `userPublicProfiles` document
- WHEN the write is attempted
- THEN either the write is denied by the CF-write-only rule pin (the client value never lands), OR — if it had landed under a prior rule state — the next server-side recompute overwrites it with the value derived from the athlete's real SetLog history
- AND at no point does `999` appear as that athlete's `bestSquatKg` on any gym leaderboard

#### Scenario: Leaderboard values trace to real session data

- GIVEN an opted-in athlete whose real training history yields a computed `lifetimeVolumeKg` of `620` via the server-side recompute
- WHEN their gym's volume leaderboard is queried
- THEN the displayed value for that athlete is `620`, matching the server-computed value, not any client-asserted value

---

### Requirement: Opt-In Enable — Metrics Populate via Server-Side Recompute

Enabling `rankingOptIn` MUST make the athlete eligible for leaderboard inclusion; their ranking-metric values MUST become populated and authoritative through the server-side recompute path (not through a client-side backfill write, as in the pre-existing v1/v2 behavior). The exact triggering event and eventual-consistency window are design-owned. A just-opted-in athlete with zero qualifying sessions MUST show zero/empty ranking metrics, never stale or forged data.

(Previously: `enableRankingOptIn` client-code computed `lifetimeVolumeKg`/`best<Lift>Kg` directly from the athlete's own session/SetLog history and wrote them in the same call. This requirement replaces that client-computed backfill with server-side computation as the authority; `enableRankingOptIn` itself now writes only the `rankingOptIn: true` intent.)

#### Scenario: Opting in with real training history eventually shows real metrics

- GIVEN an athlete with a training history containing a 110kg squat PR and 3,400kg total lifetime volume, currently `rankingOptIn == false`
- WHEN they enable `rankingOptIn`
- THEN after the server-side recompute completes, their `userPublicProfiles` document reflects `bestSquatKg == 110` and `lifetimeVolumeKg == 3400`
- AND these values are visible on their gym's leaderboards

#### Scenario: Opting in with zero qualifying sessions shows zero, not stale or forged data

- GIVEN an athlete who has never completed a qualifying session, currently `rankingOptIn == false` with all ranking-metric fields at their default (`0`/absent)
- WHEN they enable `rankingOptIn`
- THEN their ranking-metric fields remain `0`/absent (zero/empty) after opt-in
- AND no stale, previously-cleared, or forged value is ever displayed for them on any leaderboard

#### Scenario: enableRankingOptIn no longer computes metrics client-side

- GIVEN an athlete calling `enableRankingOptIn`
- WHEN the call completes
- THEN it has written `rankingOptIn: true` as the eligibility intent
- AND it has NOT computed or written `lifetimeVolumeKg`/`best<Lift>Kg` values directly from client-side session/SetLog reads

---

### Requirement: Opt-In Disable — Unchanged, Client-Initiated

Disabling `rankingOptIn` (`clearRankingMetrics`) MUST remain a client-initiated write that clears all ranking-metric fields on the athlete's own `UserPublicProfile` and removes them from all gym leaderboards. This behavior is unchanged by the server-side recompute closure — deflating one's own stats is not a forgery vector and does not require server-side authority.

(Previously: same behavior, same requirement — restated here because the opt-in ENABLE path changes in this proposal while disable does not, and both live under the same toggle lifecycle.)

#### Scenario: Disabling opt-in clears metrics and removes the athlete from leaderboards

- GIVEN an athlete with `rankingOptIn == true` and non-zero ranking metrics
- WHEN they disable `rankingOptIn` via `clearRankingMetrics`
- THEN `rankingOptIn` becomes `false`, all ranking-metric fields are cleared
- AND the athlete no longer appears in any gym leaderboard

#### Scenario: Disable remains a direct client write, no server round-trip required

- GIVEN an athlete disabling `rankingOptIn`
- WHEN `clearRankingMetrics` executes
- THEN the clearing write is performed directly by the client (as before this change), with no dependency on the server-side recompute trigger

---

### Requirement: Session Finish — No Longer the Client Authority for Metrics

Finishing a qualifying session MUST continue to update the athlete's leaderboard-visible metrics (via the server-side recompute path, not client computation) and MUST continue to update `workoutsCount`/`racha` exactly as before. `SessionRepository.finish()` MUST NOT itself compute or write `lifetimeVolumeKg`/`best<Lift>Kg` directly.

(Previously: `SessionRepository.finish()` computed and wrote `lifetimeVolumeKg`/`best<Lift>Kg` directly in the same best-effort block that writes `racha`/`workoutsCount`. This requirement moves the metric computation server-side; `workoutsCount`/`racha` denormalization is unaffected and stays client-written as before.)

#### Scenario: Finishing a qualifying session updates leaderboard metrics via the server path

- GIVEN an opted-in athlete finishing a session with a new squat PR
- WHEN the session finish completes and the server-side recompute runs
- THEN the athlete's `bestSquatKg` on their gym's leaderboard reflects the new PR
- AND `SessionRepository.finish()` itself did not compute or write that value directly

#### Scenario: workoutsCount and racha still update as before

- GIVEN an athlete (opted in or not) finishing a qualifying session
- WHEN `SessionRepository.finish()` completes
- THEN `workoutsCount` and `racha` are updated exactly as before this change, independent of the ranking-metric server-side recompute

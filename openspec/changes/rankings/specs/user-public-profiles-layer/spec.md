# Delta for User Public Profiles Layer

## MODIFIED Requirements

### Requirement: Collection Schema — `userPublicProfiles/{uid}`

The `userPublicProfiles/{uid}` document SHALL contain the public-identity fields (`uid`, `displayName`, `displayNameLowercase`, `avatarUrl`, `gymId`) plus a per-athlete opt-in ranking flag and ranking metrics. Ranking fields MUST be nullable/absent-friendly and MUST only ever hold a non-default value while `rankingOptIn == true`.

New fields:

| Field | Type | Default | Privacy | Written when |
|-------|------|---------|---------|---------------|
| `rankingOptIn` | bool | `false` | public-soft | Always present; owner-writable via settings toggle |
| `lifetimeVolumeKg` | num | `0` | public-soft | Only while `rankingOptIn == true` |
| `bestSquatKg` | num | `0` | public-soft | Only while `rankingOptIn == true` |
| `bestBenchKg` | num | `0` | public-soft | Only while `rankingOptIn == true` |
| `bestDeadliftKg` | num | `0` | public-soft | Only while `rankingOptIn == true` |

(Previously: schema had only `uid`, `displayName`, `displayNameLowercase`, `avatarUrl`, `gymId` — no ranking fields existed.)

#### Scenario: Opted-out athlete has no ranking metrics

- GIVEN a `UserPublicProfile` with `rankingOptIn == false`
- WHEN the document is read by any authenticated user
- THEN `lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, `bestDeadliftKg` are absent or `0`
- AND they MUST NOT reflect any of the athlete's real training history

#### Scenario: Opted-in athlete exposes ranking metrics

- GIVEN a `UserPublicProfile` with `rankingOptIn == true`
- WHEN the athlete finishes a session
- THEN `lifetimeVolumeKg` and the relevant `best<Lift>Kg` fields are updated per the session-finish requirement below
- AND the updated values are readable by any authenticated user via the existing `allow read: if request.auth != null` rule

---

### Requirement: Session-Finish Denormalization

On every successful `Session.finish()`, the system MUST extend the existing best-effort counter block (the same call site that already writes `racha` and `workoutsCount`) with ranking-metric updates, gated entirely on the athlete's current `rankingOptIn` value.

The system MUST:
- Read `rankingOptIn` from the athlete's own `UserPublicProfile` before writing any ranking metric.
- When `rankingOptIn == false`, skip all ranking-metric writes (no `lifetimeVolumeKg`/`best<Lift>Kg` mutation).
- When `rankingOptIn == true`:
  - Increment `lifetimeVolumeKg` by the finishing `Session.totalVolumeKg` using `FieldValue.increment` (or equivalent atomic increment).
  - For each lift family (squat, bench, deadlift) with at least one matching SetLog in the finishing session, compute this session's max weight over that family and merge `best<Lift>Kg = max(storedValue, thisSessionMax)`.
  - Perform these writes in the same best-effort try/catch block as racha/workoutsCount (failures MUST NOT block session finish).

The write MUST be idempotent with respect to session-finish retries: re-processing the same finished session MUST NOT double-count volume or corrupt best-lift values.

(Previously: the best-effort block only wrote `racha` and `workoutsCount`; there was no volume or best-lift denormalization.)

#### Scenario: Session finish increments volume for opted-in athlete

- GIVEN an athlete with `rankingOptIn == true` and `lifetimeVolumeKg == 500`
- WHEN they finish a session with `totalVolumeKg == 120`
- THEN their `UserPublicProfile.lifetimeVolumeKg` becomes `620`

#### Scenario: Session finish updates best lift only when it's a new max

- GIVEN an athlete with `rankingOptIn == true` and `bestSquatKg == 100`
- WHEN they finish a session whose max squat-family weight is `90`
- THEN `bestSquatKg` remains `100` (max merge, not overwrite)

#### Scenario: Session finish raises best lift on new PR

- GIVEN an athlete with `rankingOptIn == true` and `bestBenchKg == 80`
- WHEN they finish a session whose max bench-family weight is `85`
- THEN `bestBenchKg` becomes `85`

#### Scenario: Session finish is a no-op for ranking fields when opted out

- GIVEN an athlete with `rankingOptIn == false`
- WHEN they finish a session with `totalVolumeKg == 120` and a new squat PR
- THEN `lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, `bestDeadliftKg` are NOT written or changed

#### Scenario: Session-finish retry does not double-count

- GIVEN an athlete with `rankingOptIn == true` whose session-finish ranking write already succeeded once for session S
- WHEN the finish path for session S is retried (e.g. due to an unrelated best-effort failure elsewhere in the block)
- THEN `lifetimeVolumeKg` reflects `Session.totalVolumeKg` from session S exactly once
- AND `best<Lift>Kg` fields are unchanged by the retry (max-merge is naturally idempotent)

---

### Requirement: Firestore Rules — Ranking Fields

The existing owner-write rule on `userPublicProfiles/{uid}` (`allow update: if request.auth != null && request.auth.uid == uid && request.resource.data.uid == resource.data.uid`) MUST cover writes to `rankingOptIn` and all ranking-metric fields — no new rule is required. `read`/`list` MUST remain open to any authenticated user, unchanged.

(Previously: rule text unchanged, but ranking fields did not exist as part of the "owner can update own doc" surface.)

#### Scenario: Owner writes their own ranking fields

- GIVEN an authenticated athlete with uid `U`
- WHEN they update `userPublicProfiles/U` to set `rankingOptIn`, `lifetimeVolumeKg`, or `best<Lift>Kg`
- THEN the write succeeds under the existing owner-update rule (no rule change needed)

#### Scenario: Non-owner cannot write another athlete's ranking fields

- GIVEN an authenticated athlete with uid `A`
- WHEN they attempt to update `userPublicProfiles/B` (a different athlete) ranking fields
- THEN the write is rejected by the existing owner-only update rule

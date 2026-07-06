# Delta for User Public Profiles Layer

## MODIFIED Requirements

### Requirement: Firestore Rules — Field Allowlist

The `userPublicProfiles/{uid}` create/update rules MUST reject any write whose document contains a field outside the known 15-field set (`uid`, `displayName`, `displayNameLowercase`, `avatarUrl`, `gymId`, `gymName`, `workoutsCount`, `racha`, `followersCount`, `followingCount`, `sharedTemplatesWithAthletes`, `rankingOptIn`, `lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, `bestDeadliftKg`), via `request.resource.data.keys().hasOnly([...])`. The header comment documenting the field set MUST be corrected to list all 15 fields (previously stale at 5).

(Previously: no `keys().hasOnly()` check existed; any additional field on a `set(merge:true)` passed the rule as long as owner + `uid` immutability held.)

#### Scenario: Write containing an unknown field is denied

- GIVEN an authenticated athlete with uid `U`
- WHEN they write `userPublicProfiles/U` with `set(merge:true)` including a field not in the known 15-field set (e.g. `isAdmin: true`)
- THEN the write is denied

#### Scenario: Write containing only known fields succeeds

- GIVEN an authenticated athlete with uid `U`
- WHEN they write `userPublicProfiles/U` with `set(merge:true)` containing only fields from the known 15-field set
- THEN the write is evaluated by the remaining rule clauses (owner check, `gymId` pin, metric pins) and is NOT rejected for field-shape reasons

---

### Requirement: Firestore Rules — Owner-Only and UID Immutability

The `userPublicProfiles/{uid}` update rule MUST continue to require `request.auth.uid == uid` and `request.resource.data.uid == resource.data.uid` (unchanged invariant, restated as the allowlist and other pins are added alongside it — none of the new checks weaken owner-only write or `uid` immutability).

(Previously: this was the entire content of the update rule; it remains true but is no longer sufficient on its own.)

#### Scenario: Non-owner write is denied regardless of allowlist compliance

- GIVEN an authenticated user with uid `A`
- WHEN they attempt to write `userPublicProfiles/B` (a different uid), even with a document containing only allowlisted fields and valid values
- THEN the write is denied

#### Scenario: uid field cannot be changed on update

- GIVEN an authenticated athlete with uid `U` and an existing `userPublicProfiles/U` document
- WHEN they attempt to update the document with `uid` set to a different value than `resource.data.uid`
- THEN the write is denied

---

### Requirement: Firestore Rules — gymId Integrity

A client write to `userPublicProfiles/{uid}` that sets `gymId` MUST be denied unless the written value equals `users/{uid}.gymId` (a cross-doc `get()` pin against the athlete's own private document, mirroring the existing `gyms`/`routines` cross-doc-read pattern in this ruleset).

#### Scenario: Athlete cannot self-assign to a gym they don't attend

- GIVEN an athlete with uid `U` whose `users/U.gymId == "gym-A"`
- WHEN they write `userPublicProfiles/U` with `gymId: "gym-B"`
- THEN the write is denied

#### Scenario: Athlete can write their own real gymId

- GIVEN an athlete with uid `U` whose `users/U.gymId == "gym-A"`
- WHEN they write `userPublicProfiles/U` with `gymId: "gym-A"`
- THEN the write is NOT rejected by the gymId-integrity check

---

### Requirement: Firestore Rules — CF-Write-Only Ranking Metrics

A client write to `userPublicProfiles/{uid}` that changes `lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, or `bestDeadliftKg` to a value different from the currently stored value (`resource.data.<field>`) MUST be denied. These four fields become client-immutable via rules; they can only change through an Admin SDK write, which bypasses rule evaluation entirely (ADR-RV-005 precedent: rules deny the client, they do not — and cannot — "allow" the trigger).

(Previously: these 4 fields were writable by the owner like any other field, with only a range/type check per Open Question 1 — no equality pin against the stored value existed.)

#### Scenario: Client raw-write of a forged metric value is denied

- GIVEN an athlete with uid `U` and `userPublicProfiles/U.bestSquatKg == 100`
- WHEN they write `userPublicProfiles/U` with `bestSquatKg: 999`
- THEN the write is denied

#### Scenario: Client write that re-asserts the existing metric value is not rejected by the pin

- GIVEN an athlete with uid `U` and `userPublicProfiles/U.lifetimeVolumeKg == 3400`
- WHEN they write `userPublicProfiles/U` with `lifetimeVolumeKg: 3400` (unchanged) alongside other allowlisted field updates
- THEN the write is NOT rejected by the CF-write-only pin on that field (value equals `resource.data.lifetimeVolumeKg`)

#### Scenario: Server-side recompute writes new metric values via Admin SDK

- GIVEN the recompute trigger runs with Admin SDK credentials after an athlete finishes a qualifying session
- WHEN it writes new values for `lifetimeVolumeKg`/`best<Lift>Kg` to `userPublicProfiles/{uid}`
- THEN the write succeeds because Admin SDK writes bypass Firestore rule evaluation entirely
- AND this is NOT a rule "allowing" the write — no rule path exists that would allow a client to make the same write

---

### Requirement: Firestore Rules — Type and Range Validation

Numeric ranking-related fields (`lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, `bestDeadliftKg`) MUST be rejected on client writes if their value is not a number within a product-defined plausibility bound (exact bounds are a design/product decision; this requirement asserts only that out-of-range or wrong-typed values are rejected). `rankingOptIn` MUST be rejected on client writes if its value is not a boolean.

#### Scenario: Out-of-range numeric metric value is rejected

- GIVEN an athlete writing `userPublicProfiles/{uid}` with one of the 4 ranking-metric fields set to a value above the product-defined plausibility bound (e.g. an absurd `bestSquatKg`)
- WHEN the write is evaluated
- THEN the write is denied

#### Scenario: Non-boolean rankingOptIn value is rejected

- GIVEN an athlete writing `userPublicProfiles/{uid}` with `rankingOptIn` set to a non-boolean value (e.g. a string or number)
- WHEN the write is evaluated
- THEN the write is denied

---

### Requirement: Read Access Unchanged

`read`/`list` on `userPublicProfiles/{uid}` MUST remain open to any authenticated user, unchanged by the allowlist, gymId pin, metric CF-write-only pins, or range/type validation added by this change.

#### Scenario: Authenticated user reads any profile after the rules hardening

- GIVEN an authenticated user (any uid)
- WHEN they read any `userPublicProfiles/{otherUid}` document
- THEN the read succeeds, exactly as before this change

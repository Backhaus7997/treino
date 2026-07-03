# Proposal: Per-Gym Rankings (rachas / volumen / main lifts)

## Why

The user reversed the long-standing "Ranking = out of scope" decision (`docs/product.md:55`). We now want opt-in, per-gym leaderboards on three dimensions — **rachas** (streak), **volumen histórico** (lifetime training volume), and **main lifts** (best PR on squat / bench / deadlift). Rankings scope off `UserPublicProfile.gymId` (a Google `place_id` from the just-merged gym-google-places feature), giving a canonical, deduplicated per-gym identity.

Locked product constraints: (1) **opt-in privacy** — an athlete appears ONLY if they enable it; (2) **main-lift source = training-log PRs only** (never trainer-entered PerformanceTest 1RMs); (3) **near-real-time** updates.

## Intent

Deliver useful, private-by-default gym leaderboards WITHOUT any Cloud Function. The org `code-assurance.com` blocks public/callable functions, and the opt-in + near-real-time choices let us denormalize each athlete's metrics onto their OWN `UserPublicProfile` from their OWN data on session finish — then serve all three rankings as plain gym-scoped Firestore queries.

## Scope

### In Scope

- **UserPublicProfile ranking fields**: `rankingOptIn: bool`, `lifetimeVolumeKg: num`, `bestSquatKg` / `bestBenchKg` / `bestDeadliftKg: num`.
- **Session-finish denormalization**: extend the existing best-effort counter block in `session_repository.dart` `finish()` (same call site as racha/workoutsCount) — `FieldValue.increment` for volume, `max()` merge for best-lifts, **all gated on `rankingOptIn`**.
- **Opt-in lifecycle**: a profile/settings toggle. On ENABLE → one-time client backfill of volume + best-lifts from the athlete's own session/setLog history. On DISABLE → clear ranking fields (metrics stop being publicly readable).
- **Main-lift family map** (DART-only constant): `{'squat': [...], 'bench': [...], 'deadlift': [...]}` built from the 793-exercise catalog via name/alias matching.
- **Ranking queries + composite indexes**: `userPublicProfiles where gymId == X and rankingOptIn == true order by <metric> desc limit N` — one composite index per dimension in `firestore.indexes.json` (analogous to existing `posts` composite). Streak reuses the already-denormalized `racha` field.
- **Rankings UI screen**: 3 tabs/sections (rachas, volumen, lifts). Placement flagged as a design decision.
- **Docs**: remove "Ranking" from OUT OF SCOPE in `docs/product.md:55`; mark in-scope.

### Out of Scope

- Any Cloud Function (public, scheduled, or triggered) — the denormalization approach avoids all of them.
- A `gymRankings/{gymId}` doc or rankings subcollection — no new collection.
- Global / national rankings (per-gym only).
- Blending PerformanceTest 1RMs into main-lift PRs.
- Gamification / levels / XP.
- Backfill/migration for existing users (feature is new; everyone starts opted-out).

## Capabilities

### New Capabilities
- `gym-rankings`: opt-in per-gym leaderboards on rachas, lifetime volume, and main-lift PRs — the ranking queries, the main-lift family map, and the Rankings UI.

### Modified Capabilities
- `user-public-profiles-layer`: adds ranking fields (`rankingOptIn`, `lifetimeVolumeKg`, `bestSquatKg`/`bestBenchKg`/`bestDeadliftKg`) and the opt-in-gated dual-write from session finish.

## Approach

**No function. Denormalize onto the athlete's own public profile, then query.**

1. **Racha** — already denormalized+updated on finish (`computeStreak`); reuse as-is with a new `gymId + racha desc` composite index.
2. **Volume** — increment `lifetimeVolumeKg` by `Session.totalVolumeKg` on finish (`FieldValue.increment`), gated on opt-in. Query with `gymId + lifetimeVolumeKg desc`.
3. **Main lifts** — on finish, for each lift family compute this session's max weight over its exercise family and merge `max(stored, thisSession)` into `bestSquatKg`/etc. (reuse `aggregateExerciseProgression` PR logic), gated on opt-in. Query with `gymId + best<Lift>Kg desc`.
4. **Family map** — curated Dart constant. Built from the catalog by matching lift names/aliases (e.g. all "Sentadilla (…)" variants → squat). Client-side only, so no TS parity needed (unlike `normalize()`). This is the trickiest data piece.
5. **Opt-in lifecycle** — ENABLE backfills from own history; DISABLE clears fields. Non-opted-in users never have ranking metrics written to their public doc.
6. **Reads** — any authenticated athlete queries their gym's leaderboard (just a `userPublicProfiles` query; existing `allow read: if auth != null` covers it). Exclude `gymId == kNoGymId` / null.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/profile/domain/user_public_profile.dart` | Modified | Add 5 ranking fields (freezed → build_runner) |
| `lib/features/workout/data/session_repository.dart` | Modified | Extend finish() best-effort block: opt-in-gated volume increment + best-lift merge |
| `lib/features/workout/domain/` (new family-map const) | New | Curated `{squat,bench,deadlift}` exercise-family map (Dart-only) |
| `lib/features/profile/` (settings toggle + backfill) | New/Modified | `rankingOptIn` toggle + enable-backfill / disable-clear logic |
| `lib/features/gym_rankings/` (new feature) | New | Ranking query providers + Rankings UI (3 tabs) |
| `firestore.indexes.json` | Modified | 3 composite indexes (gymId + each metric desc) |
| `firestore.rules` | Verify | Confirm owner can write ranking fields on own public profile (existing dual-write path) |
| `docs/product.md` | Modified | Remove Ranking from OUT OF SCOPE (line ~55) |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Family-map membership wrong/incomplete → miscounted PRs | High | Curate against full 793-catalog; treat exact membership as an open decision resolved in spec/design |
| Privacy leak: metrics readable while opted-out | Med | Fields written ONLY when `rankingOptIn == true`; DISABLE clears them; query filters `rankingOptIn == true` |
| Backfill on ENABLE is heavy (reads all own sessions/setLogs) | Med | One-time, client-side, own-data only, with progress UX; best-effort |
| `FieldValue.increment` double-counts on finish retry | Low | Guard with the existing idempotent finish path; volume increment inside same best-effort block as racha |
| Missing composite index → query fails at runtime | Low | Ship all 3 indexes with the change; mirror `posts` precedent |

## Rollback Plan

Feature is additive and opt-in. To revert: remove the Rankings UI route, stop the opt-in-gated writes in `finish()`, and (optionally) drop the 5 fields + 3 indexes. Existing opted-out users are unaffected (no ranking data written). Reverting `docs/product.md` restores prior scope wording. No data migration required.

## Dependencies

- gym-google-places (merged) — provides `gymId = place_id`.
- Existing racha/`workoutsCount` denormalization pattern in `session_repository.dart`.
- `aggregateExerciseProgression` PR logic; `computeStreak`.

## Success Criteria

- [ ] Opting in makes the athlete appear in all 3 gym leaderboards; opting out removes them and clears fields.
- [ ] A non-opted-in athlete's PRs/volume are NEVER publicly readable via `userPublicProfiles`.
- [ ] Volume and best-lifts update on session finish without a Cloud Function.
- [ ] Each ranking is a single indexed `userPublicProfiles` query filtered by gym; `kNoGymId`/null excluded.
- [ ] Main-lift PRs derive from training-log SetLogs only (no PerformanceTest 1RMs).
- [ ] `docs/product.md` no longer lists Ranking as out of scope.
- [ ] `flutter analyze` 0 issues, formatted, tests + build_runner pass.

## Open Decisions (for spec / design)

1. **Exact family-map membership** — which catalog exercise IDs/aliases map to squat/bench/deadlift (equipment variants: Barra, Multipower, Hack, etc.). Trickiest data piece; resolve with the catalog.
2. **Rankings UI placement** — new dedicated screen vs. the `/coach` "En tu gym" area (note: existing "carrusel En tu gym" is coach DISCOVERY, a different feature — do not conflate).
3. **Volume unit / tie-breaking display** — how ties and units render (kg) in the leaderboard rows.

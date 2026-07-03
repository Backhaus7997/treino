# Design: Per-Gym Rankings (rachas / volumen / main lifts)

## Technical Approach

No Cloud Function. Each opted-in athlete denormalizes their OWN metrics onto their OWN `userPublicProfiles/{uid}` doc from their OWN data at session finish; rankings are then plain gym-scoped indexed Firestore queries. Racha already denormalizes on finish — we add `lifetimeVolumeKg` (recompute-from-window, idempotent) and `bestSquat/Bench/DeadliftKg` (max-merge, idempotent), all gated on `rankingOptIn`. Main-lift PRs derived from `SetLog.weightKg` via a curated Dart const family map. Opt-in toggle lives in the profile sub-tree; ENABLE backfills, DISABLE clears. See proposal `sdd/rankings/proposal`.

## Architecture Decisions

| Decision | Choice | Alternatives rejected | Rationale |
|----------|--------|----------------------|-----------|
| Volume idempotency (finish retry) | RECOMPUTE `lifetimeVolumeKg = Σ totalVolumeKg` over the same bounded completed-session window already read in `finish()` (`_counterRecomputeWindow=365`) | (a) `FieldValue.increment(session.totalVolumeKg)` — NOT idempotent, double-counts on retry; (c) transactional guard flag | The recompute list is ALREADY fetched for racha/workoutsCount — zero extra reads. Self-healing like the existing counters. Increment risks silent drift on the best-effort retry path. Window bound matches existing invariant (finish already caps lifetime counters to 365 sessions). |
| Best-lift idempotency | `max(stored, thisSessionMax)` merge per family, computed over the SAME window (recompute, not increment) | Increment/append | `max` is naturally idempotent AND recompute-over-window self-heals if a family map entry changes. Needs SetLogs per session (see Data Flow). |
| Family membership | BARBELL-canonical per lift (one catalog id each) — user-confirmable | All-equipment variants | Apples-to-apples PR: dumbbell/machine/Multipower weights are NOT comparable to a barbell 1RM. Barbell is the universal main-lift benchmark. OPEN QUESTION flagged below. |
| Family map shape | Dart `const Map<Lift, Set<String>>` of catalog ids + a normalize()-based name fallback | Runtime catalog fetch; TS parity | Client-side only, no TS port (matcher precedent ADR-CXP-006 normalize()). Ids are stable; a name fallback covers legacy SetLogs with missing/renamed ids. |
| Rankings placement | `/profile/rankings` sub-route (sibling of `edit-personal`, `gym`, `routines`) | New `/coach` sub-route | Opt-in toggle already lives in profile; "En tu gym" coach carousel is DISCOVERY (different feature — do not conflate). Rankings are a self/social stat surface → profile tree. |
| Opt-in write | `rankingOptIn` on `userPublicProfiles` via existing `updateCounters` merge path | New collection/subcollection | Reuses owner-only update rule + dual-write. No new rule surface. Query filter `rankingOptIn == true` enforces privacy. |

## Data Flow

```
session finish ──> _sessions(uid).update(...)          (primary, unchanged)
       │
       └─ best-effort block (if rankingOptIn == true):
            read recent completed sessions (already read for racha)
            read setLogs for those sessions ──> familyMax(squat/bench/deadlift)
            recompute: lifetimeVolumeKg = Σ totalVolumeKg
                       bestXKg = max over window per family
            updateCounters(uid, {rankingOptIn-gated fields})

rankings read ──> userPublicProfiles
                    .where(gymId == myGym).where(rankingOptIn == true)
                    .orderBy(<metric> desc).limit(N)      (exclude kNoGymId/null)
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `lib/features/profile/domain/user_public_profile.dart` | Modify | +`rankingOptIn @Default(false)`, `lifetimeVolumeKg @Default(0)`, `bestSquatKg/bestBenchKg/bestDeadliftKg num?`; build_runner regen |
| `lib/features/gym_rankings/domain/main_lift_family_map.dart` | Create | `const` family map (barbell ids) + `familyMaxWeight(logs)` helper reusing normalize() |
| `lib/features/workout/data/session_repository.dart` | Modify | `finish()` best-effort block: opt-in-gated volume recompute + best-lift max-merge (reads setLogs for window) |
| `lib/features/profile/data/user_public_profile_repository.dart` | Modify | `setRankingOptIn(uid, bool)`; clear helper for DISABLE |
| `lib/features/profile/application/ranking_optin_controller.dart` | Create | ENABLE backfill (reuse `aggregateExerciseProgression` per family + Σ volume) / DISABLE clear |
| `lib/features/gym_rankings/application/ranking_providers.dart` | Create | Per-dimension Riverpod query providers (gymId+rankingOptIn ordered by metric, limit N) |
| `lib/features/gym_rankings/presentation/rankings_screen.dart` | Create | 3-dimension screen (rachas / volumen / lifts→squat/bench/deadlift); reuse list/card + AppPalette/TreinoIcon |
| `lib/app/router.dart` | Modify | `/profile/rankings` GoRoute + opt-in toggle entry in ProfileScreen |
| `firestore.indexes.json` | Modify | 5 composite indexes: `gymId ASC, rankingOptIn ASC, <metric> DESC` |
| `docs/product.md` | Modify | Remove/flip "Ranking" out-of-scope line (~55) |

## Interfaces / Contracts

```dart
enum MainLift { squat, bench, deadlift }
// BARBELL-canonical — CONFIRM before locking:
const kMainLiftFamilies = <MainLift, Set<String>>{
  MainLift.squat:    {'squat-barra'},        // "Sentadilla (Barra)"
  MainLift.bench:    {'bench-press-barra'},  // "Press de banca (Barra)"
  MainLift.deadlift: {'deadlift-barra'},     // "Peso muerto (Barra)" (convencional)
};
double? familyMaxWeight(MainLift lift, List<SetLog> logs); // null if none
```

## Testing Strategy (Strict TDD — tests with code, per slice)

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | family map: id + name-fallback match; excludes dumbbell/Multipower/rumano/sumo-if-excluded; `familyMaxWeight` | pure fn tests |
| Unit | `finish()` denorm: opt-in ON writes volume+lifts; OFF writes neither; **retry idempotency** (finish twice → same values, no double) | `fake_cloud_firestore` |
| Unit | backfill-on-ENABLE computes from own history; clear-on-DISABLE sets 0/null | `fake_cloud_firestore` |
| Widget | ranking providers loading/error/empty; Rankings screen 3 dimensions + lift sub-split | `ProviderScope.overrides` + pump |

## Migration / Rollout

No migration. Additive + opt-in; all existing users start `rankingOptIn=false` (field absent decodes to default). Rollback: remove route, stop opt-in-gated writes, optionally drop 5 fields + 5 indexes.

## Chained-PR Slices (each ≤~400 LOC, tests with code)

1. **model+indexes**: 5 profile fields + build_runner + 5 composite indexes.
2. **family-map+finish-denorm**: family map + `finish()` volume recompute + best-lift max-merge (idempotency tests).
3. **opt-in toggle+backfill**: repo opt-in write + ENABLE backfill / DISABLE clear + controller.
4. **queries+UI**: ranking providers + Rankings screen + `/profile/rankings` route.
5. **docs**: flip `docs/product.md` out-of-scope line.

## Open Questions

- [ ] **Family membership (BLOCKING product call)**: barbell-canonical only (`squat-barra`/`bench-press-barra`/`deadlift-barra`) vs include all equipment variants. RECOMMEND barbell-only for comparable PRs. Also: is deadlift = convencional (`deadlift-barra`) only, or include `deadlift-sumo`? (Sumo is a competition-legal variant → arguably same lift.) Rumano/stiff-leg → EXCLUDE (assistance, not a max-PR lift). Confirm before locking slice 2.
- [ ] Volume unit + tie-break display in leaderboard rows (proposal Open Decision 3) — deferred to UI slice.
- [ ] `familyMaxWeight` name-fallback: match on `SetLog.exerciseName` normalize() for legacy logs whose `exerciseId` predates catalog ids? Recommend yes (defensive), test both paths.

# Design: Rankings Integrity — close the forged-metrics vulnerability

## Technical Approach

Two mechanisms, in the safe order **trigger+client FIRST, rules-tightening SECOND**:

1. **`rankingAggregate` trigger** (`functions/src/ranking-aggregate.ts`) mirrors `review-aggregate.ts` verbatim: `onDocumentWritten`, `southamerica-east1`, idempotent full-requery, catch-log-never-rethrow, no-op if profile absent. It becomes the SOLE writer of the 4 metric fields (`lifetimeVolumeKg`, `bestSquatKg`, `bestBenchKg`, `bestDeadliftKg`).
2. **Client restructure**: `finish()` and `enableRankingOptIn` stop computing metrics; they write intent + identity only.
3. **Rules hardening**: `keys().hasOnly([...15])`, `gymId` `get()`-pin, and the 4 metrics pinned client-immutable (CF-write-only per ADR-RV-005). Ships AFTER the trigger exists (see AD-9).

Reads spec `user-public-profiles-layer` (rule allowlist) and `gym-rankings` (server-authoritative metrics).

## Architecture Decisions

### AD-1 — Trigger topology: TWO triggers, cross-collection targets only

The recompute must fire on both (a) qualifying session finish (writes a session) and (b) opt-in enable (writes NO session). A session-only trigger leaves a just-opted-in athlete with empty metrics until their next workout.

| Option | Loop risk | Opt-in populates | Decision |
|---|---|---|---|
| (i) sessions-only + opt-in touches a dummy session | Low | Hacky | Rejected — pollutes session history |
| (ii) trigger on `userPublicProfiles` + self-loop diff-guard | **HIGH** — writes its own trigger collection | Yes | Rejected — needs fragile before/after equality short-circuit |
| **(iii) TWO triggers: `sessions/{id}` + `userPublicProfiles` gated on `rankingOptIn` false→true** | **None** | Yes | **CHOSEN** |

**Choice**: Trigger A on `users/{uid}/sessions/{sessionId}` → writes parent `userPublicProfiles/{uid}` (cross-collection, exactly reviewAggregate's loop-avoidance property). Trigger B on `userPublicProfiles/{uid}`, but it **short-circuits unless `before.rankingOptIn != true && after.rankingOptIn == true`** (the enable transition) — it does NOT write on its own metric write because that write does not flip the opt-in transition. Both call one shared `recomputeMetrics(app, uid)`.

**Loop proof for Trigger B**: `recomputeMetrics` writes the 4 metrics with `merge:true`; that re-fires Trigger B, but on the re-fire `before.rankingOptIn == after.rankingOptIn == true` → transition guard is false → immediate return, zero writes. The loop terminates after exactly one metric write. This is a hard idempotency stop by transition-equality, not value-equality.

### AD-2 — What the client writes post-restructure

| Writer | Before | After |
|---|---|---|
| `enableRankingOptIn` | computes 4 metrics + gymId + optIn | writes `gymId`/`gymName` (via `UserRepository.update`) then `rankingOptIn:true` ONLY; ~40 lines of metric compute removed |
| `finish()` | writes `workoutsCount`, `racha` + 4 metrics | writes `workoutsCount`, `racha` ONLY; metric block (lines 117–162) removed |
| `disableRankingOptIn` | `clearRankingMetrics` (optIn:false + metrics→0/null) | unchanged (AD-6) |

Trigger reads the SAME bounded window as Dart: `users/{uid}/sessions` `orderBy('startedAt','desc').limit(365)`, filter `status=='finished' && wasFullyCompleted==true`; sum `totalVolumeKg`; per session read `setLogs`, apply the TS port of `familyMaxWeight`/`kMainLiftFamilies`. Gated on `rankingOptIn==true` (else writes metrics→0/null so a stale forged value cannot survive an opt-out race).

### AD-3 — CF-write-only rule mechanics

Client UPDATE pins each metric `== resource.data.<field>` (see reviews/payments precedent). Client CREATE requires the 4 metrics ABSENT or fixed defaults (`lifetimeVolumeKg==0`, `best*Kg==null`) — a create cannot seed forged values. Delete is already `if false`, and `getOrCreate` seeds defaults, so the delete-then-recreate forgery path is closed. Admin SDK (trigger) bypasses all of this.

### AD-4 — gymId pin

`request.resource.data.gymId == get(/databases/$(database)/documents/users/$(uid)).data.gymId` (proven pattern, gyms/routines). Cost: 1 doc read per profile write. If `users/{uid}` is absent (onboarding), `get()` errors → write denied; onboarding already writes `users/{uid}` before the public profile, so order is safe. Allow `gymId` null/`kNoGymId` when private is likewise blank.

### AD-5 — Eventual-consistency UX

Opt-in → metrics appear ~1–3s later (Trigger B). The athlete's own leaderboard row shows a loading/empty state until `watch(uid)` sees populated metrics; the leaderboard query already filters `rankingOptIn==true`, and `setRankingOptIn(true)` runs LAST, so OTHERS never observe a forged/stale row. Accepted per reviewAggregate precedent.

### AD-6 — `clearRankingMetrics` under new rules

**Choice**: disable flips `rankingOptIn:false` ONLY; it does NOT zero the metrics client-side (rules pin them). The leaderboard query filters `rankingOptIn==true`, so stale metrics on a disabled doc are invisible. Rejected: a special rule branch allowing metric→0 when optIn→false (adds attack surface, unnecessary since query already hides them). Trigger B also does not fire on disable (transition is true→false).

### AD-7 — Test plan

Jest+emulator `ranking-aggregate.test.ts` mirroring `review-aggregate.test.ts`: first-finish recompute, second-session recompute, **forged-value overwrite**, idempotent re-fire, no-op if profile absent, opt-out (optIn false → metrics 0/null), no-session opt-in (Trigger B path). Dart rules test documented (CI-skipped per pre-existing gap, obs from explore).

### AD-8 — Range bounds (defense-in-depth)

Rules cap `best*Kg <= 1000` and `lifetimeVolumeKg <= 100_000_000` (generous elite floor). The trigger is the real authority; bounds only reject absurd client values before the trigger corrects them.

### AD-9 — Ship ordering

Rules PR#2 (metrics CF-write-only) MUST NOT ship before the trigger exists, or opt-in breaks (client can no longer write metrics, nothing else does). **Order**: PR#1 = trigger + client restructure (client stops writing metrics; trigger owns them). PR#2 = tighten rules. Between PRs the metrics are unwritten-but-authoritative — safe.

## Data Flow

```
SESSION FINISH:
finish() ─writes─> users/{uid}/sessions/{id}
                        │ (onDocumentWritten, cross-collection)
                        ▼
   Trigger A ─recomputeMetrics(uid)─> userPublicProfiles/{uid}  [merge 4 metrics]

OPT-IN ENABLE:
enableRankingOptIn ─> gymId/gymName ─> rankingOptIn:false→true
                        │ (onDocumentWritten, transition guard)
                        ▼
   Trigger B ─recomputeMetrics(uid)─> userPublicProfiles/{uid}  [merge 4 metrics]
                        │ re-fires on that write
                        ▼
   Trigger B: before.optIn==after.optIn==true → RETURN (loop stops)
```

## File Changes

| File | Action | Description |
|---|---|---|
| `functions/src/ranking-aggregate.ts` | Create | Triggers A+B + shared `recomputeMetrics`; TS port of `familyMaxWeight`/`kMainLiftFamilies` |
| `functions/src/index.ts` | Modify | export `rankingAggregateOnSession`, `rankingAggregateOnOptIn` |
| `functions/src/__tests__/ranking-aggregate.test.ts` | Create | Jest+emulator, AD-7 scenarios |
| `firestore.rules` (312–334) | Modify | `hasOnly([15])`, gymId `get()`-pin, metric CF-write-only pins, bounds, fix stale comment |
| `ranking_optin_controller.dart` | Modify | `enableRankingOptIn` intent-only; remove metric compute |
| `session_repository.dart` (117–162) | Modify | remove metric block; keep `workoutsCount`/`racha` |
| `user_public_profile_repository.dart` | Modify | `clearRankingMetrics`→optIn:false only (AD-6) |
| `test/firestore/user_public_profiles_rules_test.dart` | Create | documents rule intent (CI-skipped) |

## Interfaces / Contracts

```ts
// ranking-aggregate.ts
export async function recomputeMetrics(app: admin.app.App, uid: string): Promise<void>;
const K_MAIN_LIFT_FAMILIES = {
  squat: ["squat-barra"], bench: ["bench-press-barra"],
  deadlift: ["deadlift-barra", "sumo-deadlift-barra"],
} as const;
```

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Integration | Trigger recompute overwrites forged value; idempotent; opt-in-no-session; opt-out | Jest + Firestore emulator |
| Unit (Dart) | `finish()`/`enableRankingOptIn` no longer write metrics | `flutter test`, fake_cloud_firestore |
| Rules (Dart) | allowlist + gymId pin + metric immutability | emulator stub, CI-skipped (documented gap) |

## Migration / Rollout

No data migration, no index change. PR#1 rollback: revert trigger export + Dart (client resumes computing). PR#2 rollback: revert rules block to permissive. Both additive and independently reversible.

## Open Questions

- [ ] Confirm range-bound caps (AD-8) with product — trigger authoritative regardless.

# Proposal: Rankings v2 — gating, no-data fix, relocation to Entrenar

## Why

Rankings v1 ships and works (per-gym opt-in leaderboards on rachas / `lifetimeVolumeKg` / main lifts, `gymId = place_id`, no Cloud Function). But three UX/correctness defects remain:

1. `/profile/rankings` is reachable while opted-out — no gate (router.dart:531-535, profile_screen.dart:232, rankings_screen.dart never reads `rankingOptIn`).
2. An opted-in athlete saw an empty leaderboard. Root cause confirmed empirically: his `userPublicProfiles/{uid}.gymId` was null/desynced (gym chosen before the dual-write existed). `enableRankingOptIn` backfills metrics but never writes `gymId`, so opting-in is not self-sufficient.
3. Rankings sit buried in Profile; the user wants them as a first-class second screen in the Entrenar tab.

## What Changes

### 1. Opt-in gating
`RankingsScreen` watches `userPublicProfileProvider(myUid)`. When `rankingOptIn == false` → render an "enable rankings" invitation state (icon + copy + CTA → `enableRankingOptIn`). When `true` → current leaderboards. Reuses the existing controller; no new abstraction.

### 2. No-data fix (gymId denormalization at opt-in)
`enableRankingOptIn` (ranking_optin_controller.dart:51-79) ALSO denormalizes the athlete's current `gymId` + `gymName` onto `userPublicProfiles/{uid}`, read from `users/{uid}.gymId`, via the existing dual-write path (`UserRepository` / `UserPublicProfileRepository`). No new write path, NO Cloud Function. Opting-in becomes self-sufficient.

### 3. Relocation to Entrenar
`_AthleteWorkout` (workout_screen.dart) becomes 2 swipeable pages — "Tu entreno" (current content) ↔ "Rankings" — via a `DefaultTabController`/`PageView` mirroring the `TrainerCoachView` `?tab=` precedent. ATHLETE-ONLY; `TrainerWorkoutView` untouched. The opt-in toggle MOVES onto the Rankings page; `_RankingsTile` is removed from ProfileScreen. `rankingOptIn` persistence in Firestore is unchanged.

## Scope

### In Scope
- Opt-in gate + invitation state on the rankings surface.
- `gymId`/`gymName` denormalization inside `enableRankingOptIn`.
- Two-page swipe layout in `_AthleteWorkout`; toggle relocated onto the Rankings page.
- Remove `_RankingsTile` from ProfileScreen; retire or redirect `/profile/rankings`.

### Out of Scope
- Any Cloud Function (org constraint) or new collection/query — v1 queries + 5 deployed indexes stay as-is.
- Changes to `TrainerWorkoutView` or the trainer branch.
- Session-finish denormalization logic (unchanged).
- New ranking dimensions, XP/gamification.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `gym-rankings`: opt-in gating on the rankings surface; screen relocated into the Entrenar tab as a swipeable second page; toggle moves onto that page.
- `user-public-profiles-layer`: `enableRankingOptIn` now also denormalizes `gymId`/`gymName` onto `userPublicProfiles/{uid}` at opt-in time.

## Approach

Compose all three on the existing v1 base — no query, index, or write-path changes. Gate via the provider already watched by `_RankingsTile`. Fix no-data at its source (opt-in as the single self-sufficient entry point that syncs gymId). Relocate using the proven in-tab `DefaultTabController`/`PageView` precedent, athlete-branch only.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/workout/workout_screen.dart` | Modified | `_AthleteWorkout` → 2 swipeable pages (Tu entreno ↔ Rankings); athlete-only |
| `lib/features/gym_rankings/presentation/rankings_screen.dart` | Modified | Read `rankingOptIn`; invitation state; host relocated toggle |
| `lib/features/profile/application/ranking_optin_controller.dart` | Modified | `enableRankingOptIn` also denormalizes `gymId`/`gymName` |
| `lib/features/profile/profile_screen.dart` | Modified | Remove/reduce `_RankingsTile` |
| `lib/app/router.dart` | Modified | Retire or redirect `/profile/rankings`; deep-link `?tab=rankings` support (TBD) |
| `lib/features/profile/data/user_public_profile_repository.dart` / `user_repository.dart` | Verify | Reuse existing dual-write for gymId; no new method if reusable |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| TabController index math collides with no-gym / loading branches in `_AthleteWorkout` | Med | Keep page structure fixed (2 pages); branch inside each page, not the PageView |
| Already-opted-in users keep a desynced gymId (opt-in fix only helps future opt-ins) | Med | Open question: one-time repair vs. rely on next gym-select/opt-in (dev has few users) |
| Removing `/profile/rankings` breaks a bookmark/deep-link | Low | Prefer redirect over hard removal (open question) |
| Toggle relocation creates two opt-in entry points | Low | Single source of truth = same controller + `userPublicProfileProvider` |

## Rollback Plan
Additive and reversible. Revert the gate to restore unconditional access, revert the gymId write in `enableRankingOptIn`, restore `_RankingsTile` + `/profile/rankings`, and collapse `_AthleteWorkout` back to one page. No data migration; no schema change; indexes untouched.

## Dependencies
- Rankings v1 (shipped): providers, queries, 5 deployed composite indexes.
- Existing gymId dual-write path (`UserRepository` / `UserPublicProfileRepository`).
- `TrainerCoachView` `DefaultTabController`/`?tab=` precedent.

## Success Criteria
- [ ] Opted-out athlete sees the invitation state (with toggle), never the leaderboards.
- [ ] Enabling opt-in writes `gymId`/`gymName` to the public doc; the athlete appears in his gym's leaderboards without re-selecting a gym.
- [ ] Rankings reachable by swiping in the Entrenar tab (athlete only); trainer branch unchanged.
- [ ] `_RankingsTile` gone from Profile; opt-in toggle lives on the Rankings page.
- [ ] `flutter analyze` 0 issues, `dart format .`, `flutter test` pass.

## Open Questions (for spec / design)
1. **Already-desynced opted-in users** — one-time gymId repair/backfill, or rely on next gym-select / next opt-in? (dev has few users — weigh migration cost.)
2. **Invitation-state UX** — exact copy, toggle vs. single CTA button, and behavior after enabling (auto-advance to leaderboards?).
3. **Deep link** — support `?tab=rankings` on the Entrenar route (mirroring `?tab=` precedent), and does the removed `/profile/rankings` redirect there?
4. **Old route** — hard-remove `/profile/rankings` or keep as a redirect to the Entrenar rankings page?
5. **Nav affordance** — beyond swipe, is a TabBar/segmented indicator shown at the top of `_AthleteWorkout` to signal the second page exists?

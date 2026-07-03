# Delta for Gym Rankings

## ADDED Requirements

### Requirement: Opt-In Gate on the Rankings Surface

The rankings surface MUST read the athlete's own `rankingOptIn` (via `userPublicProfileProvider(myUid)`) BEFORE rendering leaderboards. While `rankingOptIn != true`, the surface MUST render an invitation state instead of any leaderboard data. While `rankingOptIn == true`, the surface MUST render the 3 leaderboards (Rachas/Volumen/Lifts). Both states MUST live-transition without renavigation when the underlying provider value changes.

#### Scenario: Opted-out athlete sees the invitation state, never leaderboards

- GIVEN an athlete with `rankingOptIn != true` (false or absent)
- WHEN they reach the rankings surface
- THEN they see the invitation state (copy + enable CTA)
- AND no leaderboard data (streak/volume/lift) is rendered

#### Scenario: Opted-in athlete sees leaderboards directly

- GIVEN an athlete with `rankingOptIn == true`
- WHEN they reach the rankings surface
- THEN the 3 leaderboards render (no invitation state)

#### Scenario: Enabling opt-in flips the surface live, without renavigation

- GIVEN an athlete on the invitation state
- WHEN they tap the enable CTA and `enableRankingOptIn` succeeds, setting `rankingOptIn = true`
- THEN the surface re-renders to the leaderboards state via the existing provider stream
- AND the athlete is NOT required to navigate away and back

#### Scenario: Disabling opt-in returns the surface live to the invitation state

- GIVEN an athlete viewing leaderboards with `rankingOptIn == true`
- WHEN they disable opt-in from the rankings surface
- THEN the surface re-renders to the invitation state via the existing provider stream
- AND no leaderboard data remains visible

---

### Requirement: No-Gym Precedence Over Opt-In Gate

When an athlete has no gym (`gymId` is `null`, empty, or `kNoGymId`), the rankings surface MUST show the no-gym guidance state, taking precedence over the opt-in invitation state, regardless of `rankingOptIn` value.

#### Scenario: No-gym athlete sees no-gym guidance even if opted in

- GIVEN an athlete with `gymId == null` and `rankingOptIn == true`
- WHEN they reach the rankings surface
- THEN they see the no-gym guidance state
- AND neither the invitation state nor leaderboards render

#### Scenario: No-gym athlete sees no-gym guidance when opted out

- GIVEN an athlete with `gymId == null` and `rankingOptIn != true`
- WHEN they reach the rankings surface
- THEN they see the no-gym guidance state (not the opt-in invitation)

---

### Requirement: Opt-In Toggle Lives on the Rankings Surface

The enable/disable affordance for `rankingOptIn` MUST be present directly on the rankings surface in both states: as the primary CTA in the invitation state, and as an accessible disable affordance in the leaderboards state. `ProfileScreen` MUST NOT host a separate rankings entry point or toggle.

#### Scenario: Invitation state exposes a prominent enable CTA

- GIVEN an athlete on the invitation state
- WHEN the state renders
- THEN a prominent CTA that calls `enableRankingOptIn` is visible

#### Scenario: Leaderboards state exposes a disable affordance

- GIVEN an athlete viewing leaderboards with `rankingOptIn == true`
- WHEN the state renders
- THEN an affordance to call `disableRankingOptIn` is accessible on the same surface

#### Scenario: Disabling from the rankings surface preserves v1 clearing behavior

- GIVEN an athlete with `rankingOptIn == true` and non-zero ranking metrics
- WHEN they disable opt-in from the rankings surface
- THEN `rankingOptIn` becomes `false` and all ranking-metric fields are cleared (unchanged from v1 `disableRankingOptIn` behavior)
- AND the athlete no longer appears in any gym leaderboard

---

### Requirement: Rankings Placement — Second Page of the Athlete Entrenar Tab

For the athlete role, rankings MUST be reachable as the second page of the Entrenar tab (alongside "Tu entreno"), reachable by horizontal swipe and/or a top tab control. The trainer role MUST NEVER see the rankings page in any form. `ProfileScreen` MUST NOT retain a rankings entry point.

#### Scenario: Athlete reaches rankings by swiping the Entrenar tab

- GIVEN an athlete on the Entrenar tab, first page ("Tu entreno")
- WHEN they swipe horizontally (or select the "Rankings" tab control)
- THEN the rankings surface (gated per the Opt-In Gate requirement) renders as the second page
- AND the bottom navigation bar and Entrenar tab selection remain unchanged

#### Scenario: Trainer role never sees a rankings page

- GIVEN an authenticated user with role `trainer`
- WHEN they view the Entrenar tab
- THEN only `TrainerWorkoutView` renders — no rankings page, tab, or swipe target exists

#### Scenario: ProfileScreen no longer exposes a rankings entry point

- GIVEN any athlete viewing `ProfileScreen`
- WHEN the screen renders
- THEN no tile, toggle, or link to rankings is present on `ProfileScreen`

---

### Requirement: `rankingOptIn` Persistence Across Restarts

`rankingOptIn` MUST remain persisted in Firestore (`userPublicProfiles/{uid}.rankingOptIn`), unchanged from v1. Reopening the app MUST land the athlete on the rankings state matching the persisted value, with no re-derivation from local/session state.

#### Scenario: App restart preserves the opted-in leaderboards state

- GIVEN an athlete who opted in during a previous session (`rankingOptIn == true` persisted in Firestore)
- WHEN they restart the app and reach the rankings surface
- THEN leaderboards render directly, without re-showing the invitation state

#### Scenario: App restart preserves the opted-out invitation state

- GIVEN an athlete who never opted in (`rankingOptIn != true` persisted in Firestore)
- WHEN they restart the app and reach the rankings surface
- THEN the invitation state renders

## REMOVED Requirements

### Requirement: Rankings Reachable via Profile Tile and `/profile/rankings`

(Reason: rankings relocate to the Entrenar tab as a swipeable second page; `ProfileScreen._RankingsTile` and the `/profile/rankings` route are removed as the primary entry point. Route disposition — hard removal vs redirect to the new Entrenar location — is a DESIGN-OWNED decision per proposal Open Question 4; this spec only fixes that `ProfileScreen` MUST NOT retain the entry point, not the exact routing mechanics.)

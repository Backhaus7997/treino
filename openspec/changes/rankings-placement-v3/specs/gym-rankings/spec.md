# Delta for Gym Rankings

Supersedes two requirements from `rankings-v2`. Everything not listed here — the opt-in gate,
no-gym precedence, `rankingOptIn` persistence, and the `ProfileScreen MUST NOT` clauses — stands
unchanged.

## MODIFIED Requirements

### Requirement: Rankings Placement — Second Page of the Athlete Feed Tab

For the athlete role, rankings MUST be reachable as the second page of the **Feed** tab, reachable
by horizontal swipe and/or a top tab control. The trainer role MUST NEVER see the rankings page in
any form. `ProfileScreen` MUST NOT retain a rankings entry point.

The deep-link `/feed?tab=rankings` MUST land on that page. Two legacy paths MUST keep resolving
there and MUST NOT be hard-removed, because live bookmarks and notifications point at them:
`/workout?tab=rankings` (rankings' previous host) and `/profile/rankings` (its host before that).

> Replaces `rankings-v2` — "Rankings Placement — Second Page of the Athlete Entrenar Tab".
> That requirement described the Entrenar tab; rankings were relocated to Feed afterwards and the
> relocation shipped without a spec change. This records the placement the app has actually had
> since, and changes no behaviour.

#### Scenario: Athlete reaches rankings by swiping the Feed tab

- GIVEN an athlete on the Feed tab, first page (the social feed)
- WHEN they swipe horizontally (or select the "RANKINGS" tab control)
- THEN the rankings surface (gated per the Opt-In Gate requirement) renders as the second page
- AND the bottom navigation bar and Feed tab selection remain unchanged

#### Scenario: Trainer role never sees a rankings page

- GIVEN an authenticated user with role `trainer`
- WHEN they view the Feed tab
- THEN only the feed body renders — no pill, no rankings page, no swipe target
- AND a trainer deep-linking `?tab=rankings` still lands on the feed

#### Scenario: Legacy rankings deep-links keep resolving

- GIVEN a bookmark or notification pointing at `/workout?tab=rankings` or `/profile/rankings`
- WHEN it is opened
- THEN it resolves to `/feed?tab=rankings`
- AND the athlete lands on the rankings page in whichever state the Opt-In Gate dictates

#### Scenario: ProfileScreen still exposes no rankings entry point

- GIVEN any athlete viewing `ProfileScreen`
- WHEN the screen renders
- THEN no tile, toggle, or link to rankings is present

---

### Requirement: Opt-In Toggle Lives on the Rankings Surface

The enable/disable affordance for `rankingOptIn` MUST be present directly on the rankings surface
in both states: as the enable CTA in the invitation state, and as an accessible disable affordance
in the leaderboards state. `ProfileScreen` MUST NOT host a separate rankings entry point or toggle.

The invitation CTA MUST be visible and unambiguously a control. It MUST NOT be full-bleed.

Rankings is opt-in, and the invitation state is what the athlete who declined it still lands on
every time they reach the surface. An edge-to-edge accent CTA reads there as the app re-selling a
feature the athlete already turned down (issue #642). Reducing it to a text link or removing it was
rejected: issue #646 found participants do not recognise these controls as tappable at all, so
lowering the affordance would trade one reported defect for another.

> Replaces `rankings-v2` — "Opt-In Toggle Lives on the Rankings Surface", whose invitation
> scenario required a "prominent" CTA. Only the CTA's visual weight changes; the `ProfileScreen
> MUST NOT` clause is carried over verbatim and remains in force.

#### Scenario: Invitation state exposes a visible, unambiguous enable CTA

- GIVEN an athlete on the invitation state
- WHEN the state renders
- THEN a CTA that calls `enableRankingOptIn` is visible and reads as a button
- AND it does not span the full width of the surface
- AND its tap target is at least 44pt tall

#### Scenario: The enable CTA meets WCAG AA in both themes

- GIVEN the invitation state rendered under either `AppTheme.dark()` or `AppTheme.light()`
- WHEN the CTA renders
- THEN its label contrasts with its accent background at no less than 4.5:1

> `palette.bg` MUST NOT be used as the foreground on an accent CTA: the token inverts between
> themes, resolving to paper50 over mint accent on light (1.57:1). `TreinoButtonTokens.foreground`
> returns ink950 invariantly (12.10:1).

#### Scenario: Leaderboards state exposes a disable affordance

- GIVEN an athlete viewing leaderboards with `rankingOptIn == true`
- WHEN the state renders
- THEN an affordance to call `disableRankingOptIn` is accessible on the same surface

#### Scenario: Disabling from the rankings surface preserves v1 clearing behavior

- GIVEN an athlete with `rankingOptIn == true` and non-zero ranking metrics
- WHEN they disable opt-in from the rankings surface
- THEN `rankingOptIn` becomes `false` and all ranking-metric fields are cleared
- AND the athlete no longer appears in any gym leaderboard

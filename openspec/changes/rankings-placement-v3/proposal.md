# Proposal: Rankings placement v3 — reconcile the spec with the shipped Feed placement, soften the opt-out pitch

## Why

Issue #642 (UX/UI audit, point 7) reports that RANKINGS holds 50% of the Feed tab's segmented pill
while 3 of 5 interviewees rejected rankings as a motivator, and asks to reduce its prominence
without removing the feature (AGENTS.md rule 4 keeps rankings in scope).

Three things blocked acting on it as written.

**1. The governing spec no longer describes the app.** `rankings-v2` fixed rankings as "the second
page of the athlete **Entrenar** tab" (`specs/gym-rankings/spec.md` — Requirement "Rankings
Placement"). Rankings was later relocated to the **Feed** tab and now lives at `/feed?tab=rankings`
(`feed_screen.dart` `_AthleteFeed`, `router.dart` `/feed`), with `/workout?tab=rankings` and
`/profile/rankings` both redirecting there. That relocation shipped without an openspec change:
`grep "feed?tab=rankings" openspec/` returns nothing. Every option #642 proposes therefore collides
with a contract that describes a placement the app abandoned.

**2. The data #642 blocks itself on is only half obtainable.** It asks for opt-in adoption AND tab
traffic before implementing. Adoption is queryable and this change ships the script for it
(`scripts/audit_ranking_optin.js`). Traffic is not measurable at all today:
`lib/core/analytics/analytics_service.dart` defines seven events, none navigational; there is no
`FirebaseAnalyticsObserver`, `logScreenView` or `setCurrentScreen` anywhere in `lib/`; and Feed
page 0 and page 1 are the same go_router route, so Firebase's auto-collected `screen_view` cannot
separate them. Neither retroactively nor going forward, without shipping instrumentation first.

**3. The pill is no longer what the issue describes, and another issue owns it.** The pill is now
capped at `maxWidth: 176` and shares a fixed row with four action icons (commits `6074e675`,
`9be146e4`), landed after the audit was written. And issue #646 — "los pills de sub-navegación no
se leen como botones" — declares itself a prerequisite of #642 and proposes extracting a shared
`TreinoSegmentedPill`, pulling the same widget toward *more* visual weight while #642 pulls it
toward less.

What is left, once those three are accounted for, is the part of #642 that is both unambiguous and
unblocked: **an opt-in feature should not pitch itself to the athlete who declined it.** The
athlete who never opted in still lands on `_InvitationState` and gets a 56pt edge-to-edge accent
button selling a feature they already turned down, with no way to dismiss it. That is a product
defect independent of how many people use rankings, and independent of how wide the pill is.

## What Changes

### 1. Reconcile the placement requirement with reality
"Rankings Placement — Second Page of the Athlete Entrenar Tab" is rewritten as the Feed placement
that actually shipped, including the three live entry points. No behaviour changes; this is spec
debt being paid.

### 2. Relax "prominent" on the invitation CTA
The invitation scenario currently requires "a **prominent** CTA". It becomes "a visible,
unambiguous CTA", which is what lets the CTA stop being full-bleed without violating the contract.
The CTA does not disappear and does not become a text link — issue #646 found participants fail to
recognise these controls as tappable at all, so lowering the affordance would trade one reported
defect for another.

### 3. Fix a WCAG AA failure on that same CTA
`rankings_screen.dart` styles the CTA `foregroundColor: palette.bg` over `backgroundColor:
palette.accent`. `palette.bg` inverts between themes: on dark it is ink950 (12.10:1 over mint —
fine), on light it is paper50 (**1.57:1** — fails AA). `TreinoButtonTokens.foreground(context)`
already exists and returns ink950 invariantly. Pre-existing defect, fixed while the widget is open.

### 4. Ship the adoption query
`scripts/audit_ranking_optin.js` — read-only, zero writes. Global share plus a **per-gym**
breakdown, because rankings are gym-scoped and a global percentage hides that an athlete in a gym
where nobody opted in sees an empty board regardless.

## Scope

### In Scope
- Rewrite the placement requirement: Entrenar → Feed.
- Relax the invitation CTA from "prominent" to "visible, unambiguous"; reduce it to a compact
  button in `_InvitationState`.
- Fix the CTA's light-theme contrast via `TreinoButtonTokens.foreground`.
- `scripts/audit_ranking_optin.js`.
- Record the open questions #642 raises, so the next person does not re-litigate them from zero.

### Out of Scope
- **Removing rankings.** AGENTS.md rule 4.
- **The pill's visual treatment** (option A of #642). Owned by #646, which declares itself a
  prerequisite. Touching it now guarantees rework.
- **Gating the RANKINGS tab on opt-in** (option B) and **moving rankings out of the Feed**
  (option C). Both need the adoption number this change makes obtainable, and B additionally needs
  the Profile-toggle question below resolved first.
- **A rankings toggle on `ProfileScreen`.** Three separate `MUST NOT` clauses forbid it
  (Requirements "Opt-In Toggle Lives on the Rankings Surface" and "Rankings Placement", plus the
  scenario "ProfileScreen no longer exposes a rankings entry point"), guarded by
  `test/features/profile/presentation/profile_rankings_tile_test.dart`, whose header records that
  rankings-v2 Phase 3 deliberately flipped it from asserting presence to asserting absence.
  #642 calls moving the toggle "unconditional"; it is not — it reverses a documented decision.
  Left standing here, recorded as an open question.
- Leaderboard logic, gym scoping, ranking dimensions, `rankingAggregateOnOptIn`.
- The 5-tab bar (AGENTS.md rule 5). Any Feed redesign.
- Navigation analytics. Real, and the reason half of #642's data gate is unanswerable, but it is a
  separate concern from rankings and belongs in its own issue.

## Affected Areas

| Area | File | Change |
|---|---|---|
| Invitation CTA | `lib/features/gym_rankings/presentation/rankings_screen.dart` | compact button + AA-safe foreground |
| Tests | `test/features/gym_rankings/presentation/rankings_screen_test.dart` | +2 geometry assertions; existing 40 untouched |
| Adoption query | `scripts/audit_ranking_optin.js` | new, read-only |
| Spec | `openspec/changes/rankings-placement-v3/specs/gym-rankings/spec.md` | this change |
| Docs (separate commit, reviewer approval per AGENTS.md rule 8) | `AGENTS.md`, `docs/product.md` | both still say `/workout?tab=rankings` |

Not touched: `feed_screen.dart`, `profile_screen.dart`, `router.dart`, `firestore.rules`,
`functions/`, the three rankings deep-links.

## Risks

- **The CTA reduction is a judgment call on n=5.** Mitigated by keeping it a real button rather
  than a text link, and by it being reversible in one commit. The AA fix stands on its own
  regardless.
- **#646 will rebuild the pill.** This change deliberately does not touch it, so there is no
  collision — but #642 cannot be fully closed until #646 lands and the adoption number exists.
- **The adoption script may return a meaningless number.** `.firebaserc` declares only
  `treino-dev`; run there it measures seed accounts. The script says so in its header and in its
  output. If no project with real athletes exists yet, options A/B/C stay blocked and the honest
  next step is instrumentation, not a guess.

## Success Criteria

- The spec describes where rankings actually live.
- The athlete who declined rankings is no longer sold them by a full-bleed CTA.
- The CTA passes WCAG AA in both themes.
- The adoption number is one command away.
- `flutter analyze` 0 issues, `dart format .` clean, `flutter test` green, no existing assertion
  modified to make it pass.

## Open Questions

Recorded rather than resolved. Each needs the adoption number, #646, or both.

1. **Should the RANKINGS tab be hidden for opted-out athletes (#642 option B)?** Needs adoption
   data. Also needs Q2 answered first: hiding the tab without another entry point makes the
   feature unreachable. Note `feed_screen.dart` already swaps whole subtrees by role rather than
   varying `TabController.length`, and the trainer path (`showTitle: true`, no pill) is a
   ready-made template — but `_resolveInitialIndex` returns 1 for `?tab=rankings`, and three
   routes funnel into it, so the deep-link resolution has to be designed, not improvised.
2. **Should the opt-in toggle also live on `ProfileScreen`?** Currently forbidden three times over.
   The argument for revisiting is real: the control for an opt-in feature living only inside that
   feature is a genuine coupling defect, and it is what makes option B impossible today. Requires
   an explicit spec reversal, not a test edit.
3. **Should the pill give FEED more weight than RANKINGS (#642 option A)?** Blocked on #646. Note
   Flutter's `TabBar` renders equal-width tabs under `TabBarIndicatorSize.tab`, so asymmetry is
   not a styling tweak on the current widget — another reason to let #646's shared component own it.
4. **Is there a Firebase project with real athletes?** If not, #642's data gate is unsatisfiable
   and every option above stays blocked indefinitely.

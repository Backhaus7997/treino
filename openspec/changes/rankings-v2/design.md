# Design — Rankings v2 (gating, no-data fix, relocation to Entrenar)

Builds strictly on the shipped v1 base (5 deployed composite indexes, gym-scoped
queries, `userPublicProfiles` denormalization, `RankingOptInController`). No new
collection, no new query, no new index, and — per the org infra constraint — NO
Cloud Function anywhere. Everything below is client-side composition.

Read dependency: `proposal.md` (approved), `explore.md`, v1 design (engram
`sdd/rankings/design`). Source verified: `workout_screen.dart`,
`rankings_screen.dart`, `ranking_optin_controller.dart`, `user_repository.dart`,
`user_public_profile_repository.dart`, `router.dart`, `trainer_coach_view.dart`,
`coach_screen.dart`, `profile_screen.dart`, `user_public_profile_providers.dart`.

---

## Technical Approach

Three orthogonal fixes composed on the v1 base:

1. **Gate** the rankings surface on `rankingOptIn` (read from the provider the
   old `_RankingsTile` already watched), rendering an **invitation state** when
   opted-out and the existing leaderboards when opted-in.
2. **Fix no-data at the source** by making `enableRankingOptIn` self-sufficient:
   it now also denormalizes `gymId` + `gymName` onto `userPublicProfiles/{uid}`,
   read from `users/{uid}.gymId`, reusing the exact v1 dual-write name-resolution
   tolerance. Opting-in becomes the single entry point that syncs everything.
3. **Relocate** rankings into the Entrenar tab as a swipeable second page for
   athletes only, mirroring the proven `TrainerCoachView` `?tab=` + tab-control
   precedent; the opt-in toggle moves onto that page; `_RankingsTile` and the
   `/profile/rankings` route are retired.

The rankings leaderboard body (`_RankingsBody`, `_DimensionSection`,
`_LeaderboardList`, all query providers) is REUSED byte-for-byte. Only its host,
its gating wrapper, and the toggle placement change.

---

## Architecture Decisions

### AD-1 — Two-page structure: `DefaultTabController` + `TabBar`/`TabBarView`, fixed 2-page shape

**Decision.** `_AthleteWorkout` becomes a `DefaultTabController(length: 2)` with
a compact segmented `TabBar` pill at the top and a `TabBarView` of two pages:
page 0 = **"Tu entreno"** (the existing `ListView` of sections, extracted intact
into a private `_TuEntrenoPage`), page 1 = **"Rankings"** (the gated rankings
surface). The 2-page structure is **fixed and unconditional**; all branching
(loading / no-gym / opted-out / leaderboards) happens INSIDE page 1, never in the
`TabBarView` child list. `TabBarView` uses swipe (default physics) so the pages
are genuinely swipeable, matching the proposal's "2 swipeable pages" intent.

**Where the controller lives.** `DefaultTabController` (inherited), NOT a manual
`TabController` in a `State`. This is exactly the `TrainerCoachView` precedent
(`trainer_coach_view.dart:42`) — no dispose plumbing, no index desync, and it
lets the router pass `initialIndex` via a resolver (AD-2). `_AthleteWorkout` can
stay `StatelessWidget`.

**Keep-alive semantics.** Page 0 ("Tu entreno") is wrapped in an
`AutomaticKeepAliveClientMixin` (or the existing `ListView`'s natural rebuild is
cheap — see below) so swiping to Rankings and back does NOT tear down and refetch
the whole Entrenar list (MiPlan, TrainerTemplates, MisRutinas, Plantillas,
Historial each own live providers). Page 1 (Rankings) is NOT kept alive — its
Firestore leaderboard listeners are `autoDispose` and should release when the
user swipes away, per the project standard "cancel Firestore streams in
dispose()". Net: entering Rankings starts 3-5 short-lived leaderboard reads;
leaving Rankings disposes them; returning to Tu entreno finds it warm.

**Rebuild-safety on the high-traffic Entrenar screen (critical).** The section
widgets are `const` and each watches its own provider. Wrapping them in a
`TabBarView` page does not add rebuilds as long as the `TabBar`'s selection
change does not rebuild page 0. `DefaultTabController` only rebuilds listeners of
the `TabController`; the `TabBarView` pages are built lazily and the inactive page
is offstage. The `TabBar` itself is the only widget that must rebuild on tab
change. We keep the `TabBar` isolated (its own subtree) so the section list is
untouched by swipes. ZERO added rebuilds to the section providers.

**Alternatives considered.**
- *`PageView` + custom dot indicator.* Rejected: reimplements what `TabBar`
  gives free (label sync, a11y, index math), and the repo already has a proven
  `TabBar` pill (`TrainerCoachView`). Consistency > novelty.
- *Shell sub-route `/workout/rankings` + entry card (explore Option 1).* Rejected
  by the settled proposal decision — the product wants a first-class second
  screen reachable by swipe, not a bottom-of-list card. (Kept as the documented
  rollback path.)
- *Branch the `TabBarView` children on state (e.g. hide page 1 when no gym).*
  Rejected explicitly per the proposal risk note: a variable-length
  `TabBarView`/`TabBar` makes `initialIndex` and swipe math collide with
  loading/no-gym branches. Fixed length + internal branching is the mitigation.

### AD-2 — Deep-link: support `?tab=rankings` on `/workout` (mirror `?tab=` precedent)

**Decision.** YES. The `/workout` `GoRoute` reads `state.uri.queryParameters['tab']`
and passes it to `WorkoutScreen(initialTab: ...)`, which forwards to
`_AthleteWorkout(initialTab: ...)`, which resolves it to `DefaultTabController.
initialIndex` via a static `_resolveInitialIndex` (identical shape to
`TrainerCoachView._resolveInitialIndex`: `'rankings' -> 1`, anything else / null
-> `0`). Accepted values: `'rankings'` (page 1). Missing/unknown -> page 0.

**Mechanics.** `router.dart:387-389` changes from
`pageBuilder: (_, __) => _noAnim(const WorkoutScreen())` to a `pageBuilder` that
reads the query param (exactly the `/coach` builder at `router.dart:467-472`).
The trainer branch ignores `initialTab` (same as `CoachScreen` ignores it for the
athlete view) — `TrainerWorkoutView` is untouched.

**Why.** (a) It is the repo's established deep-link idiom, zero new concept.
(b) It gives the old `/profile/rankings` a redirect target (AD-3). (c) A future
notification / home card can deep-link straight to the leaderboard.

**Alternative rejected.** No deep-link (swipe-only). Rejected: leaves no
redirect target for the retired route and no programmatic entry for future
surfaces — a strictly worse position for one line of resolver code.

### AD-3 — Old route `/profile/rankings`: **redirect** to `/workout?tab=rankings`, do not hard-remove

**Decision.** Replace the `/profile/rankings` `GoRoute` builder
(`router.dart:531-535`) with a `redirect: (_, __) => '/workout?tab=rankings'`
(keeping the path registered so any lingering `context.push('/profile/rankings')`
or external bookmark lands correctly), and remove the `RankingsScreen` import
usage from that route. The `_RankingsTile` that pushed it is removed anyway
(AD-6), so in practice the only callers left are none — but the redirect is a
one-line safety net that costs nothing.

**Weighing honestly (pre-release/dev).** The app is pre-release with very few
users, so a hard removal would be defensible. But a `redirect` is strictly
cheaper to reason about than a removal: it cannot leave a dangling `push` target,
it needs no audit of every call site, and it self-documents the move. The cost is
one line. Given the trivial cost and the non-zero benefit (safety + traceability
during the transition PR), redirect wins. It can be deleted in a later cleanup
once we're confident nothing references it.

**Alternative rejected.** Hard-remove the route + `RankingsScreen` import from
router. Rejected on cost/benefit: saves nothing meaningful, adds call-site audit
risk during the same PR that's already moving the screen.

### AD-4 — Desynced opted-in users: **one-time idempotent client-side self-heal on rankings-page mount**

**Decision.** Implement a silent, idempotent, client-side repair. On the rankings
page (page 1) mount, a small controller compares the athlete's PUBLIC
`userPublicProfiles/{uid}.gymId` against the PRIVATE `users/{uid}.gymId`. If the
athlete is `rankingOptIn == true` AND the public `gymId` is null/empty/`kNoGymId`
OR differs from the private `gymId`, it re-runs the same `gymId`+`gymName`
denormalization used at opt-in (AD-5's write) — once, fire-and-forget, no UI
blocking, no error surfaced (best-effort, like `finish()`'s counters, because the
user did not explicitly request it).

**Why repair (not "rely on re-opt-in").** The reporter's empty-leaderboard bug is
exactly this desync. Relying on re-opt-in means every already-opted-in user with
a stale public `gymId` stays invisible until they happen to toggle off/on or
re-select a gym — a silent, unactionable failure. The repair is ~15 lines, reuses
the AD-5 write path verbatim, is idempotent (writing the same gymId is a no-op
merge), and self-limits (it only fires when a real mismatch exists, which after
one successful run never recurs). Dev has few users, so the read cost is
negligible; correctness is worth it.

**Idempotency & safety.**
- Guarded by `rankingOptIn == true` — never touches opted-out users.
- Compares before writing — a matching gymId issues zero writes.
- Best-effort try/catch — a failure logs and is swallowed (does not break the
  leaderboard render). The next mount retries.
- Reuses `_resolveGymName` tolerance — a bad/stale gym id resolves `gymName:
  null` without throwing (same guarantee as v1 dual-write).
- NO Cloud Function, NO batch migration — pure per-user, per-mount, on-read heal.

**Alternatives considered.**
- *No repair, rely on next gym-select / re-opt-in.* Rejected: leaves the exact
  reported bug latent for existing users; the fix (AD-5) only helps FUTURE
  opt-ins.
- *One-shot backfill script / admin migration.* Rejected: needs privileged
  access or a Cloud Function (blocked), overkill for a handful of dev users.

**Placement.** The self-heal lives in the same controller that hosts the
denormalization write (AD-5), invoked once from the rankings page's
`initState`/first-build via `ref.read` (not `watch`, so it fires once, not on
every rebuild). It reads `userProfileProvider` (private) + `userPublicProfileProvider`
(public) snapshots at call time.

### AD-5 — `gymId` denormalization mechanics inside `enableRankingOptIn`

**Decision.** Extend the controller's dependencies and fold the gymId/gymName
write into the existing `updateCounters` merge, preserving the error-surfacing
contract.

**How the controller obtains `gymId`.** Inject `UserRepository` into
`RankingOptInController` (constructor + provider wiring). Inside
`enableRankingOptIn(uid)`, read the athlete's current private profile via
`UserRepository.get(uid)` -> `profile.gymId`. Rationale: the controller already
does async I/O (session reads); one more `get` is consistent and keeps the method
self-contained and testable with a `FakeFirebaseFirestore` (the existing test
already builds a real `UserRepository` against the fake).

- *Rejected: pass `gymId` as a parameter from the call site.* Widens the
  `RankingOptInControllerBase` interface and pushes the "where does gymId come
  from" concern into every caller (the toggle widget) — leakier.
- *Rejected: read `userProfileProvider` snapshot at the widget call site and pass
  it in.* Same interface-widening problem; also couples the controller's
  correctness to whatever the widget happened to have cached.

**How `gymName` is resolved.** REUSE the v1 tolerance. The cleanest reuse without
duplicating `_resolveGymName` (which is private to `UserRepository`) is to route
the gymId write THROUGH `UserRepository.update(uid, {'gymId': gymId})`. That path
already: (a) resolves `gymName` via `_resolveGymName` (null/kNoGymId/unknown ->
`null`, never throws), (b) dual-writes `gymId`+`gymName`+`uid` onto
`userPublicProfiles/{uid}` via the merge batch, (c) satisfies the create rule
(uid folded in). This is the SINGLE canonical denormalization path — we do not
reimplement it. The write is a no-op-safe merge (re-writing the same gymId does
nothing harmful).

- *Rejected: add a new `UserPublicProfileRepository.setGym(uid, gymId, gymName)`
  and resolve gymName in the controller.* Duplicates `_resolveGymName`, creates a
  second denormalization path that can drift from `UserRepository.update`. The
  proposal explicitly says "reuse existing dual-write; no new method if reusable"
  — and it IS reusable.

**Write ordering & the error contract.** The v1 method surfaces errors on purpose
(explicit user action deserves an explicit error — unlike `finish()`'s
best-effort block). We preserve that. Ordering:
1. Backfill metrics (existing session/setlog reads -> `updateCounters` with the 4
   metric fields) — unchanged.
2. Denormalize gym: `await _userRepository.update(uid, {'gymId': profile.gymId})`
   — resolves+writes gymId/gymName; errors propagate.
3. `setRankingOptIn(uid, true)` — unchanged, LAST, so the athlete only becomes
   visible after both metrics AND gym are on the public doc (no window where a
   query returns them with a stale gym).

If `profile.gymId` is null (athlete truly has no gym), step 2 still runs and
writes `gymId: null` / `gymName: null` — harmless, and the rankings page's no-gym
state handles it. The gymName resolution failure path is already swallowed inside
`_resolveGymName`, so it can never abort the opt-in.

**Not a single merge write.** We keep the two existing writes (metrics via
`updateCounters`, flag via `setRankingOptIn`) and ADD the gym write via
`UserRepository.update`. Collapsing all into one write would mean reimplementing
the dual-write + gymName resolution inline — rejected for the same drift reason.
Three awaits, sequential, error-propagating: acceptable for an explicit,
infrequent user action.

### AD-6 — Invitation state (opted-out) UI

**Decision.** When `userPublicProfileProvider(myUid).rankingOptIn == false`, page
1 renders a centered invitation block instead of `_RankingsBody`:

- Icon: `TreinoIcon.ranking` (the same icon the old tile used), muted accent.
- Heading: Barlow Condensed 700 UPPERCASE, e.g. `SUMATE A LOS RANKINGS`.
- Body copy (es-AR, motivating, NO gamification/XP framing per project voice):
  something like *"Compará tus rachas, tu volumen y tus levantamientos con la
  gente de tu gym. Activá los rankings para aparecer."* Tone = invitation to
  compare within your gym, not "earn points / win".
- CTA: a primary button `ACTIVAR RANKINGS` (accent, pill, Barlow Condensed 700)
  that calls `enableRankingOptIn(myUid)` via `rankingOptInControllerProvider`.

**Loading / error during enable (the N-read backfill).** `enableRankingOptIn`
does N session reads + N setlog reads + the gym write — it can take a beat. The
invitation block owns a local `_enabling` bool (mirroring the old
`_RankingsTileState._pending` pattern):
- While enabling: CTA shows an inline `CircularProgressIndicator` (accent), button
  disabled, copy unchanged. Keyed for tests
  (`Key('rankings_optin_enabling')`).
- On error: a `SnackBar` (es-AR: *"No pudimos activar los rankings. Probá de
  nuevo."*) and the button returns to enabled — the method surfaces errors
  (AD-5), so we catch at the widget boundary. `if (mounted)` guarded.
- On success: no manual navigation needed. `enableRankingOptIn` writes
  `rankingOptIn: true` to the public doc; `userPublicProfileProvider` is a live
  stream, so the page **reactively swaps** from invitation to leaderboards the
  instant the write lands. This is the "same page transitions live to
  leaderboards on success" mechanic — declarative, no imperative page push.

**Gating wrapper.** A thin `_RankingsPage` `ConsumerWidget` watches
`userPublicProfileProvider(myUid).select((p) => p?.rankingOptIn ?? false)` (via
`select` so it rebuilds ONLY on the opt-in bit, not on every counter tick) and
branches: `false` -> invitation; `true` -> the existing `RankingsScreen` body
(minus its own header/back — see AD-7). Loading of the public profile shows the
existing `_LoadingBlock`.

### AD-7 — Toggle placement in the enabled state

**Decision.** In the enabled (leaderboards) state, the disable affordance lives as
a **trailing action in a slim page header** on the rankings page, NOT inline in
the scrolling leaderboard. Concretely: the rankings page gets a compact top row
(replacing the old `RankingsScreen` back-button header, which is obsolete now that
it's a tab page, not a pushed route) containing the `RANKINGS` title on the left
and a small settings/toggle affordance on the right — a `Switch` (or an overflow
`⋯` menu with "Desactivar rankings") that calls `disableRankingOptIn(myUid)`.

Rationale: the leaderboard is the content; the toggle is a rare, destructive-ish
control (disable clears metrics). Putting it in the header keeps it discoverable
but out of the way, and avoids cluttering the per-dimension cards. It also gives a
natural home for the disable confirmation.

**Disable confirmation.** Because `disableRankingOptIn` CLEARS the 4 metric fields
(not just flips a flag), turning it off is lossy. Show a confirm dialog (repo has
the `_confirmAndRun` pattern in `trainer_coach_view.dart`) — es-AR: *"Si desactivás
los rankings, tus métricas se borran de los tableros. ¿Seguro?"* On confirm ->
`disableRankingOptIn` -> the live stream swaps the page back to the invitation
state automatically (same reactive mechanic as enable).

**Alternative rejected.** Toggle as the first row of the leaderboard list.
Rejected: mixes a control into scrollable content, and an accidental scroll-tap
could disable + wipe metrics. Header placement is safer.

**Header obsolescence.** The current `RankingsScreen` header (`rankings_screen.dart:46-66`)
is a back-button that `context.pop()`s — meaningful for a pushed route, meaningless
for a tab page. It is replaced by the AD-7 header (title + toggle). The `TabBar`
pill (AD-1) already signals "you're on the Rankings page", so the header can be
minimal.

### AD-8 — Testing approach

**Unit-tested (fake Firestore, no widgets).**
- `RankingOptInController.enableRankingOptIn` now ALSO writes gymId/gymName:
  extend `ranking_optin_controller_test.dart` to assert the public doc gets
  `gymId` + `gymName` after enable, that a null-gym athlete gets `gymId: null`
  without throwing, and that a gymName-resolution failure does NOT abort opt-in.
  Inject a real `UserRepository` against `FakeFirebaseFirestore` (the test file
  already constructs repos against the fake).
- The AD-4 self-heal: a controller-level test that a `rankingOptIn == true` user
  with a stale/null public gymId gets it re-synced from the private doc, and that
  a matching gymId issues zero writes (idempotency).

**Widget-tested (fake providers via overrides).**
- Gating: `_RankingsPage` renders the invitation block when
  `userPublicProfileProvider` yields `rankingOptIn == false`, and the leaderboards
  when `true`. Override the provider with an in-memory value.
- Invitation CTA: tapping `ACTIVAR RANKINGS` invokes a **fake**
  `RankingOptInControllerBase` (override `rankingOptInControllerProvider`) —
  `RankingOptInControllerBase` exists PRECISELY for this test double; assert
  `enableRankingOptIn` is called with the right uid and the enabling spinner
  shows.
- Two-page / deep-link: `_AthleteWorkout` with `initialTab: 'rankings'` starts on
  page 1; default starts on page 0; swiping switches pages. Extend
  `workout_screen_test.dart`. Assert `TrainerWorkoutView` still renders for the
  trainer role (unchanged branch).
- Router: `router_workout_routes_test.dart` — `/workout?tab=rankings` builds
  `WorkoutScreen` on page 1; `/profile/rankings` redirects to
  `/workout?tab=rankings`.

**Reused as-is.** `rankings_screen_test.dart` (leaderboard body), the query
provider tests, `main_lift_family_map` tests — none of the leaderboard internals
change.

---

## File-Level Change Map

| File | Change |
|------|--------|
| `lib/features/workout/workout_screen.dart` | `WorkoutScreen` gains `initialTab` param (from router). `_AthleteWorkout` -> `DefaultTabController(length:2)` + segmented `TabBar` pill + `TabBarView`. Existing `ListView` body extracted into private `_TuEntrenoPage` (with keep-alive). New private `_RankingsPage` (gating wrapper, AD-6). `_resolveInitialIndex('rankings'->1)`. `TrainerWorkoutView` branch untouched. |
| `lib/features/gym_rankings/presentation/rankings_screen.dart` | Header (`_RankingsScreenState` back-button, l.46-66) replaced by tab-page header with title + disable toggle (AD-7). `_RankingsBody`/`_DimensionSection`/`_LeaderboardList`/query wiring UNCHANGED. May be recomposed so the leaderboard body is a reusable widget consumed by `_RankingsPage`. Add invitation-state widget + disable-confirm. |
| `lib/features/profile/application/ranking_optin_controller.dart` | Inject `UserRepository`. `enableRankingOptIn`: read `users/{uid}.gymId`, then `await userRepository.update(uid, {'gymId': gymId})` BEFORE `setRankingOptIn(true)` (AD-5). Add idempotent `syncGymIfDesynced(uid)` for the AD-4 self-heal (best-effort). Widen constructor + base interface if self-heal is exposed. |
| `lib/features/profile/application/ranking_optin_controller_provider.dart` | Wire `userRepository: ref.watch(userRepositoryProvider)` into `RankingOptInController`. |
| `lib/features/profile/profile_screen.dart` | Remove `const _RankingsTile()` from the ENTRENAMIENTO group (l.109) and delete the `_RankingsTile`/`_RankingsTileState` classes (l.183-253). ENTRENAMIENTO group keeps its other tiles. |
| `lib/app/router.dart` | `/workout` `pageBuilder` reads `?tab=` -> `WorkoutScreen(initialTab: tab)` (mirror `/coach`, l.467-472). `/profile/rankings` GoRoute -> `redirect: '/workout?tab=rankings'` (AD-3); drop the now-unused `RankingsScreen` builder there (import may remain if still referenced). |

No changes to: `user_repository.dart` (reused as-is), `user_public_profile_repository.dart`
(reused), `user_public_profile.dart` model, `ranking_providers.dart`,
`main_lift_family_map.dart`, `firestore.indexes.json`, `firestore.rules`.

---

## Riverpod Provider Graph Deltas

No new providers. Rewiring only:

- `rankingOptInControllerProvider` — dependency edge added:
  `RankingOptInController(sessionRepository, publicProfileRepository, userRepository)`.
  New watch: `userRepositoryProvider` (already exists in `user_providers.dart:15`).
- `_RankingsPage` (new widget) watches
  `userPublicProfileProvider(myUid).select((p) => p?.rankingOptIn ?? false)` —
  `select` so only the opt-in bit triggers rebuilds (not counter ticks). Existing
  provider, no new declaration.
- Invitation CTA and disable toggle `ref.read(rankingOptInControllerProvider)` —
  existing.
- AD-4 self-heal reads `userProfileProvider` (private, existing) +
  `userPublicProfileProvider` (public, existing) snapshots once via `ref.read`.
- No change to the 5 leaderboard query providers or `userPublicProfileProvider`
  itself.

Rebuild budget on the high-traffic Entrenar screen: page 0 (Tu entreno) section
providers are UNAFFECTED — the `TabBar` selection lives in a sibling subtree, and
`select`-gated opt-in watching is confined to page 1. ZERO added rebuilds to the
Entrenar list.

---

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `TabController` index math collides with loading/no-gym branches | Med | AD-1: fixed 2-page `TabBarView`; ALL state branching inside page 1, never in the child list. |
| Swiping to Rankings and back tears down + refetches the Entrenar list | Med | AD-1 keep-alive on page 0; page 1 leaderboard listeners are `autoDispose` and released on swipe-away. |
| Opt-in enable is slow (N session + N setlog reads + gym write) with no feedback | Med | AD-6: `_enabling` spinner on the CTA, disabled button, SnackBar on error, live reactive swap on success. |
| Disable wipes metrics on an accidental tap | Med | AD-7: toggle in header (not in scroll list) + confirm dialog before `disableRankingOptIn`. |
| Already-desynced users stay invisible (fix only helps future opt-ins) | Med | AD-4: idempotent client-side self-heal on rankings-page mount. |
| Second denormalization path drifts from `UserRepository.update` | Low | AD-5: route the gym write THROUGH `UserRepository.update` — single canonical path, no new method. |
| Removing `/profile/rankings` breaks a lingering push/bookmark | Low | AD-3: redirect, not hard-remove. |
| gymName resolution failure aborts opt-in | Low | AD-5: reuses `_resolveGymName` which swallows + returns null; can't throw. |
| Trainer branch accidentally affected | Low | `WorkoutScreen` role-branch unchanged; `initialTab` ignored for trainers (mirrors `CoachScreen`); `TrainerWorkoutView` untouched. Widget test asserts it. |

**Assumption requiring validation:** the empirical root cause (reporter's public
`gymId` was null/desynced) is confirmed in `explore.md`. AD-4 + AD-5 address it. If
runtime inspection also shows the `racha` field absent (explore's cause #1), that
is an ORTHOGONAL v1 gap NOT in this change's scope — flag it, don't fix it here.

---

## Chained-PR Slices

v1 shipped as 5 slices; v2 is smaller and naturally splits into **3** reviewable
slices, each `<~400 LOC` with tests alongside:

**Slice 1 — Fix + gating (correctness first).**
`enableRankingOptIn` gymId/gymName denormalization via `UserRepository.update`
(AD-5) + provider rewiring; the AD-4 self-heal; opt-in gate + invitation state
(AD-6) rendered on the *existing* `RankingsScreen` surface (still at
`/profile/rankings` for now). Tests: controller unit tests (gym denorm,
idempotent self-heal, no-abort-on-gymName-failure) + gating widget tests. Ships
the two bug fixes immediately, independent of relocation.

**Slice 2 — Relocation into Entrenar (the move).**
`_AthleteWorkout` -> 2-page `DefaultTabController`/`TabBar`/`TabBarView` (AD-1),
`_TuEntrenoPage` extraction + keep-alive, `_RankingsPage` host, `?tab=rankings`
deep-link on `/workout` (AD-2), toggle relocated into the rankings page header
(AD-7). Tests: two-page/deep-link/keep-alive widget tests + trainer-branch
regression. Depends on Slice 1's invitation+gate widgets.

**Slice 3 — Cleanup (remove the old entry points).**
Remove `_RankingsTile` from `ProfileScreen`; redirect `/profile/rankings` ->
`/workout?tab=rankings` (AD-3); drop the obsolete `RankingsScreen` back-button
header. Tests: router redirect test + profile screen no-longer-has-tile test.
Trivial, low-risk, closes the loop. Can fold into Slice 2 if the reviewer prefers
2 PRs — but keeping cleanup separate keeps each diff small and the move reviewable
in isolation.

Review Workload Forecast: 3 slices, each well under the 400-line budget; no single
slice is high-risk. Chained PRs recommended: Yes (natural, low-friction chain).

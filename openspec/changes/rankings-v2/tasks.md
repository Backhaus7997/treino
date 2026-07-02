# Tasks: Rankings v2 (gating, no-data fix, relocation to Entrenar)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~950-1150 total (3 slices) |
| 400-line budget risk | Low |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 → PR 2 → PR 3 (see Suggested Work Units) |
| Delivery strategy | chained PRs, work-unit commits (tests+code+docs together) |
| Decision needed before apply | No |

### Suggested Work Units

| Unit | Goal | Likely PR | Est. LOC | Notes |
|------|------|-----------|----------|-------|
| 1 | Fix + gating: gymId/gymName denorm on enable, self-heal, opt-in gate/invitation state on existing `/profile/rankings` surface | PR 1 | ~380-450 | Base: `main`/`feat/rankings`. Ships both bug fixes immediately, independent of relocation. Controller unit tests are the heaviest part (3 new scenario groups). |
| 2 | Relocation into Entrenar: 2-page `TabBarView`, deep-link, toggle moved into rankings-page header | PR 2 | ~400-500 | Base: PR 1. Depends on Slice 1's invitation+gate widgets existing. Largest slice — mostly widget tests (two-page/deep-link/keep-alive/trainer-regression). |
| 3 | Cleanup: remove `_RankingsTile`, redirect old route, drop obsolete header | PR 3 | ~80-120 | Base: PR 2. Trivial, low-risk, closes the loop. Includes the docs flip (no doc change needed beyond the URL reference — see Phase 3 note). |

---

## Phase 1: Fix + Gating (Slice 1 — PR 1)

Traceability: `[user-public-profiles-layer: Opt-In Toggle Lifecycle]`, `[gym-rankings: Opt-In Gate on the Rankings Surface]`, `[gym-rankings: No-Gym Precedence]`, `[AD-4]`, `[AD-5]`, `[AD-6]`.

- [x] 1.1 RED: `test/features/profile/application/ranking_optin_controller_test.dart` — extend with cases per `[user-public-profiles-layer: Opt-In Toggle Lifecycle]`: (a) enabling opt-in writes `gymId`+`gymName` onto `userPublicProfiles/{uid}` sourced from `users/{uid}.gymId` (desynced-doc scenario); (b) a null/`kNoGymId` private `gymId` writes `gymId: null`/`gymName: null` on the public doc WITHOUT throwing; (c) a `_resolveGymName` failure/timeout does NOT abort opt-in — `rankingOptIn` still becomes `true`, metrics and `gymId` still write, `gymName` ends up `null`; (d) disabling opt-in leaves `gymId`/`gymName` unchanged (only the 4 ranking-metric fields clear). Inject a real `UserRepository` against `FakeFirebaseFirestore` (existing pattern in this test file).
- [x] 1.2 GREEN: Modify `lib/features/profile/application/ranking_optin_controller.dart` — inject `UserRepository` into `RankingOptInController`'s constructor. In `enableRankingOptIn(uid)`: after the existing metrics backfill, read `profile.gymId` via `UserRepository.get(uid)`, then `await _userRepository.update(uid, {'gymId': profile.gymId})` (reuses the canonical `_resolveGymName` + dual-write path — AD-5, no new repository method), THEN `setRankingOptIn(uid, true)` last. Preserve the existing error-propagation contract (explicit user action).
- [x] 1.3 Modify `lib/features/profile/application/ranking_optin_controller_provider.dart` — wire `userRepository: ref.watch(userRepositoryProvider)` into the `RankingOptInController` constructor call.
- [x] 1.4 RED: `test/features/profile/application/ranking_optin_controller_test.dart` — add self-heal cases per `[AD-4]`: a `rankingOptIn == true` athlete whose public `gymId` is null/empty/`kNoGymId` OR differs from the private `gymId` gets it re-synced on `syncGymIfDesynced(uid)`; a matching `gymId` issues ZERO writes (idempotency assertion, e.g. via a write-counting fake or `FakeFirebaseFirestore` write-log); an opted-out athlete is never touched by the self-heal (guard assertion).
- [x] 1.5 GREEN: Modify `lib/features/profile/application/ranking_optin_controller.dart` (and `RankingOptInControllerBase` if the self-heal must be exposed to the widget layer) — add `syncGymIfDesynced(uid)`: compare public vs private `gymId`, reuse the AD-5 write path (`UserRepository.update`) when mismatched, best-effort try/catch (log + swallow on failure, matching `finish()`'s counters tolerance), no-op when they already match.
- [x] 1.6 Quality gate (controller layer): `flutter analyze` 0 issues, `dart format .`, `flutter test test/features/profile/application/ranking_optin_controller_test.dart` green.
- [x] 1.7 RED: `test/features/gym_rankings/presentation/rankings_screen_test.dart` — extend with gating cases per `[gym-rankings: Opt-In Gate on the Rankings Surface]` and `[gym-rankings: No-Gym Precedence Over Opt-In Gate]`: (a) `rankingOptIn != true` renders the invitation state, no leaderboard data; (b) `rankingOptIn == true` renders the 3 leaderboards, no invitation state; (c) `gymId == null`/`kNoGymId` renders the no-gym guidance state regardless of `rankingOptIn` (both `true` and `false` sub-cases), taking precedence over the invitation state; (d) toggling the overridden `userPublicProfileProvider` value live-transitions the rendered state without any navigation call (use `ProviderScope.overrides` + `container.pump`/rebuild, no `pumpAndSettle` on a pushed route).
- [x] 1.8 GREEN: Modify `lib/features/gym_rankings/presentation/rankings_screen.dart` — add the gating wrapper: watch `userPublicProfileProvider(myUid).select((p) => p?.rankingOptIn ?? false)` (per `[AD-6]`, `select`-scoped to avoid rebuilds on counter ticks); branch no-gym guidance (highest precedence) → invitation state → leaderboards (`_RankingsBody`, unchanged). Keep the surface mounted at the EXISTING `/profile/rankings` route for this slice — relocation is Phase 2.
- [x] 1.9 RED: `test/features/gym_rankings/presentation/rankings_screen_test.dart` — invitation-state widget cases per `[gym-rankings: Opt-In Toggle Lives on the Rankings Surface]`: prominent `ACTIVAR RANKINGS` CTA visible and wired to `enableRankingOptIn` via an overridden fake `RankingOptInControllerBase`; tapping it shows the `Key('rankings_optin_enabling')` spinner (button disabled) while pending; a thrown error surfaces a `SnackBar` and re-enables the button (`if (mounted)` guarded); success requires no manual navigation — the overridden provider value flipping to `true` re-renders leaderboards on the same widget tree.
- [x] 1.10 GREEN: Modify `lib/features/gym_rankings/presentation/rankings_screen.dart` — add the invitation-state widget per `[AD-6]`: `TreinoIcon.ranking` icon, Barlow Condensed 700 uppercase heading, es-AR invitation copy (no gamification/XP framing), primary `ACTIVAR RANKINGS` CTA calling `rankingOptInControllerProvider.enableRankingOptIn(myUid)`, local `_enabling` bool + `Key('rankings_optin_enabling')` spinner, error `SnackBar`.
- [x] 1.11 Quality gate (gating + invitation widgets): `flutter analyze` 0 issues, `dart format .`, `flutter test test/features/gym_rankings/presentation/rankings_screen_test.dart` green.
- [x] 1.12 Phase gate: `flutter analyze` 0 issues (full project), `dart format .` (full project), `flutter test` (full suite) green. Commit as a single work unit (tests + code together) per delivery strategy.

## Phase 2: Relocation into Entrenar (Slice 2 — PR 2)

Traceability: `[gym-rankings: Rankings Placement — Second Page of the Athlete Entrenar Tab]`, `[AD-1]`, `[AD-2]`, `[AD-7]`. Depends on Phase 1's gating + invitation widgets existing on the reusable leaderboard body.

- [x] 2.1 RED: `test/features/workout/workout_screen_test.dart` — extend with two-page/deep-link/trainer-regression cases per `[gym-rankings: Rankings Placement]`: (a) default (`initialTab` absent/unknown) starts `_AthleteWorkout` on page 0 ("Tu entreno"); (b) `initialTab: 'rankings'` starts on page 1 (Rankings); (c) swiping the `TabBarView` switches pages (drag gesture assertion); (d) a `trainer`-role user still renders ONLY `TrainerWorkoutView` — no `TabBar`, no rankings page, no swipe target exists (regression per `[gym-rankings: Trainer role never sees a rankings page]`); (e) page 0's section providers (e.g. `MiPlanSection`'s underlying provider) are NOT rebuilt when swiping to page 1 and back (keep-alive assertion, per `[AD-1]` rebuild-safety).
- [x] 2.2 GREEN: Modify `lib/features/workout/workout_screen.dart` — `WorkoutScreen` gains `initialTab` param (nullable string, from router). `_AthleteWorkout` becomes `DefaultTabController(length: 2)` wrapping a compact segmented `TabBar` pill + `TabBarView` of exactly 2 fixed children (`[AD-1]`: fixed 2-page shape, ALL branching stays inside page 1, never in the child list). Extract the existing `ListView` body intact into a private `_TuEntrenoPage` wrapped with `AutomaticKeepAliveClientMixin`. Add a static `_resolveInitialIndex(String? tab) => tab == 'rankings' ? 1 : 0` (mirrors `TrainerCoachView._resolveInitialIndex`). `TrainerWorkoutView` branch untouched.
- [x] 2.3 RED: `test/features/workout/workout_screen_test.dart` — case: page 1 hosts the gated rankings surface (the `_RankingsPage`/leaderboard body from Phase 1, now embedded here rather than pushed) — assert invitation state and leaderboards state both render correctly when swiped/deep-linked to, reusing the Phase 1 override pattern.
- [x] 2.4 GREEN: Modify `lib/features/workout/workout_screen.dart` — add private `_RankingsPage` (the gating wrapper from Phase 1, or a thin host that composes the Phase 1 leaderboard-body widget) as `TabBarView` page 1. Page 1 is NOT kept alive — its Firestore leaderboard listeners are `autoDispose` and release on swipe-away, per `[AD-1]`.
- [x] 2.5 RED: `test/app/router_workout_routes_test.dart` (new or extended) — `/workout?tab=rankings` builds `WorkoutScreen` with page 1 selected; `/workout` (no query param) builds page 0; per `[AD-2]`.
- [x] 2.6 GREEN: Modify `lib/app/router.dart` — `/workout` `GoRoute.pageBuilder` (`router.dart:387-389`) reads `state.uri.queryParameters['tab']` and passes `WorkoutScreen(initialTab: tab)`, mirroring the `/coach` builder (`router.dart:467-472`). Trainer branch ignores `initialTab` (unchanged `WorkoutScreen` role-branch logic from Phase 2.2).
- [x] 2.7 RED: `test/features/gym_rankings/presentation/rankings_screen_test.dart` — header/toggle-placement case per `[AD-7]`: in the leaderboards state, a disable affordance (`Switch` or overflow menu item) is accessible in a slim top header (title `RANKINGS` + trailing control), tapping it opens a confirm dialog (es-AR copy), confirming calls `disableRankingOptIn(myUid)` and the surface reactively swaps back to the invitation state (no navigation).
- [x] 2.8 GREEN: Modify `lib/features/gym_rankings/presentation/rankings_screen.dart` — replace the old back-button header (`rankings_screen.dart:46-66`, obsolete now that this is a tab page, not a pushed route) with the `[AD-7]` header: `RANKINGS` title + trailing disable control, `_confirmAndRun`-style confirm dialog (es-AR: *"Si desactivás los rankings, tus métricas se borran de los tableros. ¿Seguro?"*) before calling `disableRankingOptIn`.
- [x] 2.9 Quality gate: `flutter analyze` 0 issues, `dart format .`, `flutter test test/features/workout/workout_screen_test.dart test/app/router_workout_routes_test.dart test/features/gym_rankings/presentation/rankings_screen_test.dart` green.
- [x] 2.10 Phase gate: `flutter analyze` 0 issues (full project), `dart format .` (full project), `flutter test` (full suite) green. Commit as a single work unit.

## Phase 3: Cleanup — Remove Old Entry Points (Slice 3 — PR 3)

Traceability: `[gym-rankings: Rankings Placement — ProfileScreen no longer exposes a rankings entry point]`, `[gym-rankings: REMOVED Requirement — Rankings Reachable via Profile Tile and /profile/rankings]`, `[AD-3]`.

- [ ] 3.1 RED: `test/features/profile/presentation/profile_rankings_tile_test.dart` — flip existing assertions (or replace file content) to assert `ProfileScreen` does NOT render any rankings tile/toggle/link in the ENTRENAMIENTO section, per `[gym-rankings: ProfileScreen no longer exposes a rankings entry point]`.
- [ ] 3.2 GREEN: Modify `lib/features/profile/profile_screen.dart` — remove `const _RankingsTile()` from the ENTRENAMIENTO group (`profile_screen.dart:109`) and delete the `_RankingsTile`/`_RankingsTileState` classes (`profile_screen.dart:183-253` per design's file map). ENTRENAMIENTO group keeps its remaining tiles unchanged.
- [ ] 3.3 RED: `test/app/router_workout_routes_test.dart` (or a new `router_profile_rankings_redirect_test.dart`) — `/profile/rankings` redirects to `/workout?tab=rankings` per `[AD-3]` (assert via `GoRouter.routeInformationProvider`/`redirect` test pattern, not a full navigation pump).
- [ ] 3.4 GREEN: Modify `lib/app/router.dart` — replace the `/profile/rankings` `GoRoute` builder (`router.dart:531-535`) with `redirect: (_, __) => '/workout?tab=rankings'`; drop the now-unused `RankingsScreen` builder usage at that route (remove the `RankingsScreen` import at `router.dart:41` only if no longer referenced elsewhere in the file — it is still referenced by nothing else post-relocation, confirm before removing).
- [ ] 3.5 Quality gate: `flutter analyze` 0 issues, `dart format .`, `flutter test test/features/profile/presentation/profile_rankings_tile_test.dart test/app/router_workout_routes_test.dart` green.
- [ ] 3.6 Docs check (no change required): `docs/product.md:55` references `/profile/rankings` as example copy inside an out-of-scope clarification bullet ("ranking por gym, opt-in, ya está implementado — ver `/profile/rankings`..."). Since `[AD-3]` keeps `/profile/rankings` registered as a redirect (not hard-removed), the reference remains technically valid (it still resolves, now via redirect to `/workout?tab=rankings`). Leave as-is UNLESS the reviewer wants the canonical path called out — if so, update the bullet to read `.../workout?tab=rankings (redirect from /profile/rankings)`. No code/test impact either way; this task is a judgment call, not a gate blocker.
- [ ] 3.7 Phase gate: `flutter analyze` 0 issues (full project), `dart format .` (full project), `flutter test` (full suite) green. Commit as a single work unit.

## Rules Applied

- Every impl (GREEN) task preceded by its RED (failing test) task in the same slice — Strict TDD, mirroring `rankings` v1's structure exactly.
- No Cloud Function anywhere — all changes are client-side (controller, widgets, router), per the org infra constraint and `design.md`'s explicit confirmation.
- No `@freezed`/`@Default` model changes in this change — no `build_runner` regen task required (unlike v1 Phase 1).
- No new Firestore composite indexes, no `firestore.rules` changes — v1's 5 indexes and existing owner-write rule already cover every field touched here (confirmed by `user-public-profiles-layer` spec's Firestore Rules requirement, unchanged besides prose).
- Each phase ends with a full-project quality gate (`flutter analyze` + `dart format .` + `flutter test`) in addition to the scoped gate right after the relevant RED/GREEN pair, matching the chained-PR review discipline.
- Work-unit commits: tests + implementation + doc updates for a given task pair are committed together, not split across commits, per delivery strategy.

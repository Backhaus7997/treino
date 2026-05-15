# Proposal: Feed Segments — MI GYM + PÚBLICO (Etapa 3)

## Intent

Wire the MI GYM and PÚBLICO segments of the Feed tab. Today both pills are inert (`isActive: false, onTap: null`) and the `switch` over `FeedSegment` collapses non-AMIGOS cases to `SizedBox.shrink()`. Users can see the pills but cannot navigate between feed sources. This change activates the existing `feedForGymProvider` / `feedPublicProvider` data layer, sources `gymId` from `userProfileProvider`, and ships the no-gym empty state. Success = pills navigate, each segment renders its own data, and the no-gym path is explicit.

## Scope

### In Scope

- Activate MI GYM and PÚBLICO pills in `feed_segment_pills.dart` (remove hardcoded `false` / `null`, wire to `feedSegmentProvider`).
- New `_MiGymBody` and `_PublicoBody` `ConsumerWidget`s inside `feed_screen.dart`, mirroring `_AmigosBody`.
- New `myGymFeedProvider` wrapper in `feed_screen_providers.dart` that resolves `userProfileProvider → gymId → feedForGymProvider(gymId)` with explicit null-gym guard.
- Parameterize `FeedEmptyState` with required `message` and optional `icon` (default `TreinoIcon.users`). Update existing AMIGOS caller to pass explicit copy.
- Distinct empty-state copy per segment: MI GYM (has gym), MI GYM (no gym), PÚBLICO.
- Unit test for `myGymFeedProvider` null-gym branch (Strict TDD active).
- `// TODO(pagination)` markers at `ListView.separated` call sites in both new bodies.
- `PostCard.onAuthorTap` callback with `// TODO: navigate to /feed/profile/${post.authorUid} — route added in feat/public-profile`.

### Out of Scope (HARD constraints — coordinated with Etapa 4 dev)

- `lib/features/feed/data/friendship_repository.dart` — DO NOT TOUCH.
- `lib/features/feed/presentation/widgets/post_card.dart` — use only via public API (`Post post`, `VoidCallback? onAuthorTap`). DO NOT MODIFY.
- `lib/app/router.dart` — DO NOT TOUCH. Etapa 4 owns `/feed/profile/:uid`.
- Pagination implementation (TODO markers only).
- Likes, comments, reactions, post creation, search icon, Firestore rules.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `feed`: extend the Feed surface so MI GYM and PÚBLICO segments are interactive and source-bound. Adds `myGymFeedProvider` wrapper, parameterized `FeedEmptyState`, and per-segment empty-state copy. AMIGOS behavior unchanged.

## Approach

Approach **B** from explore §6: composable per-segment body widgets (`_MiGymBody`, `_PublicoBody`) inside `feed_screen.dart`, mirroring `_AmigosBody` exactly. PÚBLICO consumes `feedPublicProvider` directly (no wrapper needed). MI GYM consumes a new `myGymFeedProvider` wrapper that returns `FutureProvider<List<Post>?>` where `null` = "user has no gym" and `[]` = "gym exists, no posts" — single signal, no parallel boolean provider. Pills wired by removing `const` from `_Pill(...)` constructors and binding `isActive` / `onTap` to `feedSegmentProvider`. `FeedEmptyState` gains additive `message` + `icon` params (backwards-compat).

## Decisions Locked (closes explore §11)

| # | Question | Decision | Rationale |
|---|---|---|---|
| Q1 | `myGymFeedProvider` return type | `FutureProvider<List<Post>?>` — `null` = no gym | Single signal, simpler than two providers |
| Q2 | `FeedEmptyState` parameterization | Parameterize: required `message`, optional `icon` | Additive, backwards-compat, no widget duplication |
| Q3 | MI GYM pill when `gymId == null` | Always tappable + show empty state | Hiding adds reactive complexity; empty state surprises no one |
| Q4 | `myGymFeedProvider` wrapper vs inline | Wrapper in `feed_screen_providers.dart` | Mirrors `myFriendsFeedProvider`, isolates null guard, testable |
| Q5 | Error state copy | Generic for all 3 segments | Reuse `"No pudimos cargar tu feed. Intentá de nuevo."` |
| Q6 | File placement of new bodies | Stay in `feed_screen.dart` next to `_AmigosBody` | Consistency over premature extraction |
| Q7 | `// TODO(pagination)` markers | Add at both new `ListView.separated` sites | Documents deferred work explicitly |
| Q8 | `myGymFeedProvider` provider type | `FutureProvider` | Consistent with `myFriendsFeedProvider`; `userProfileProvider` stream invalidates downstream |
| Q9 | Test coverage for null-gym guard | YES — unit test in this PR | Strict TDD active; null-gym is the riskiest branch |

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `lib/features/feed/feed_screen.dart` | Modified | Add `_MiGymBody`, `_PublicoBody`; replace `SizedBox.shrink()` cases |
| `lib/features/feed/application/feed_screen_providers.dart` | Modified | Add `myGymFeedProvider` wrapper |
| `lib/features/feed/presentation/widgets/feed_segment_pills.dart` | Modified | Wire MI GYM + PÚBLICO pills (`isActive`, `onTap`) |
| `lib/features/feed/presentation/widgets/feed_empty_state.dart` | Modified | Add `message` (required) + `icon` (optional) params |
| `test/features/feed/application/my_gym_feed_provider_test.dart` | New | Null-gym guard unit test |
| `lib/features/feed/data/friendship_repository.dart` | NONE (HARD) | Etapa 4 ownership |
| `lib/features/feed/presentation/widgets/post_card.dart` | NONE (HARD) | Public API only |
| `lib/app/router.dart` | NONE (HARD) | Etapa 4 ownership |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `userProfileProvider` `loading` state mishandled → blank/empty flash on MI GYM | Med | Explicit `AsyncValue.when(loading: spinner, ...)` in `_MiGymBody` |
| Removing `const` from `_Pill` regresses const-correctness on parent `FeedSegmentPills` | Low | Verified in explore §10.4 — parent stays `const`, only inner `_Pill` calls are non-const |
| Coordination conflict with Etapa 4 in `feed_screen_providers.dart` (concurrent imports) | Low | Etapa 4 works on different files; communicate before merge |
| `FeedEmptyState` parameterization breaks AMIGOS visual parity | Low | Same default icon, AMIGOS caller updated in same PR with explicit string |

## Rollback Plan

Single PR, single revert. Files to revert if shipped and broken:

1. `lib/features/feed/feed_screen.dart` — remove `_MiGymBody` / `_PublicoBody`, restore `SizedBox.shrink()` cases.
2. `lib/features/feed/application/feed_screen_providers.dart` — remove `myGymFeedProvider`.
3. `lib/features/feed/presentation/widgets/feed_segment_pills.dart` — restore hardcoded `isActive: false, onTap: null`.
4. `lib/features/feed/presentation/widgets/feed_empty_state.dart` — revert to hardcoded `_kCopy`.
5. Delete `test/features/feed/application/my_gym_feed_provider_test.dart`.

`git revert <merge-sha>` covers all five. No data migration, no Firestore changes, no router changes — safe revert.

## Dependencies

- None blocking. `feedForGymProvider` and `feedPublicProvider` already exist (explore §3).
- Etapa 4 is parallel and independent; this PR must not touch its files.

## Owner

Dev C.

## Review Workload Forecast

| Metric | Value |
|---|---|
| Estimated changed lines | ~200–350 (mostly wiring + composition; one new test) |
| 400-line budget risk | **Low** |
| Chained PRs recommended | **No** |
| Decision needed before apply | **No** |
| Delivery strategy | `single-pr` |

## Success Criteria

- [ ] Tapping MI GYM pill switches feed to gym posts; tapping PÚBLICO switches to public posts.
- [ ] User without `gymId` sees `"Todavía no estás en un gym"` empty state on MI GYM (not error, not crash).
- [ ] User with `gymId` but no gym posts sees `"Tu gym todavía no tiene posts"`.
- [ ] PÚBLICO segment with no public posts shows `"Aún no hay posts públicos"`.
- [ ] AMIGOS segment behavior and copy unchanged.
- [ ] `flutter analyze` returns 0 issues; `dart format .` clean; tests pass.
- [ ] `myGymFeedProvider` null-gym unit test exists and passes.
- [ ] No diff in `friendship_repository.dart`, `post_card.dart`, or `router.dart`.

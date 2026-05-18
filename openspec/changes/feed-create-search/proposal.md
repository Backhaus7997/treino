# Proposal: feed-create-search (Fase 3 · Etapa 5)

**Change**: `feed-create-search`
**Branch**: `feat/feed-create-search` (off `main` at `a4780d4`) — used as integration/tracker branch
**Owner**: Dev C
**Artifact store**: hybrid
**Predecessor**: `sdd/feed-create-search/explore` (engram #47)

---

## Intent

Close Fase 3 with the two remaining social primitives: a create-post form (`/feed/create`) and a search-users screen (`/feed/search`). Both are wired from the existing `_FeedHeader` (plus + search icon are STATIC today). MVP only — no workout attach, no posts search, no inline follow in results.

Success = a user can (1) tap the plus button, write a post with privacy, publish, and see it in the feed; and (2) tap the search icon, type a name, tap a result, and land on that user's public profile (Etapa 4 screen).

---

## Decisions Locked (10/10 open questions from explore §10)

| # | Question | Decision | Rationale |
|---|---|---|---|
| Q1 | Add `displayNameLowercase` to UserProfile? | YES — add field, normalize at write | User greenlit. Required for usable case-insensitive prefix search. |
| Q2 | Real routine tag picker? | NO — stub affordance only (chip disabled, `onTap: null`) | Real picker needs cross-feature dep to workout. Defer to Fase 4. Matches `_MessageButtonStub` precedent. |
| Q3 | Privacy selector default? | `PostPrivacy.friends` | Most conservative. User opts UP to broader visibility. |
| Q4 | Gym pill when no gymId? | DISABLED (opacity 0.4, no-op) + helper text "Asociate a un gym para postear acá" | Hidden surprises; disabled communicates the gate. |
| Q5 | Inline follow button on search results? | NO — tap tile → navigates to public profile (Etapa 4 follow lives there) | Avoids N+1 `friendshipByPair` queries per result. |
| Q6 | Post text char limit? | 280 chars | Twitter parity, well-known UX. |
| Q7 | Search min query length? | 2 chars | Single-letter queries are expensive and rarely useful. |
| Q8 | Post creation success UX? | `context.pop()` + invalidate 3 feed providers (`myFriendsFeedProvider`, `feedPublicProvider`, `myGymFeedProvider`). No toast. | New post appearing in feed IS the success signal. |
| Q9 | Write `displayNameLowercase` in ProfileSetupFlow? | YES — write it in `ProfileSetupFlow`, `UserRepository.getOrCreate`, `createIfAbsent`. Lazy backfill on next `update`. | Profile setup is canonical source for `displayName`; both must stay in sync. |
| Q10 | PR split strategy? | CHAINED PRs (PR#1 create-post → PR#2 search-users) | ~597 prod LOC exceeds 400-line budget. Two reviewable slices > one `size:exception`. |

---

## Scope

### PR#1 — `feat/feed-create-post` (in scope)

- New `CreatePostScreen` (form: text 280 max, privacy pills with default `friends`, routine tag STUB chip, PUBLICAR / CANCELAR CTAs).
- New `createPostNotifier` (Riverpod 2 AsyncNotifier) — manages form state + submit + 3-feed-provider invalidation.
- Wire plus button in `_FeedHeader` (`lib/features/feed/feed_screen.dart` line 64-76) → `context.push('/feed/create')`.
- Add `GoRoute(path: 'create')` under `/feed` in `lib/app/router.dart`.
- Gym-pill disabled state when `userProfileProvider.gymId == null`.
- Keyboard handling via `SingleChildScrollView` (no Scaffold available — handled by `_ShellScaffold`).
- Tests: notifier (submit success / submit error / gym-pill gating), screen widget (form, validation, CTAs).

### PR#2 — `feat/feed-search-users` (in scope, depends on PR#1)

- New `SearchUsersScreen` (header search bar, debounced 300ms, 2-char min query).
- New `UserSearchResultTile` widget (avatar + name + gym, tap → `context.push('/feed/profile/$uid')`). No follow button.
- New `searchUsersProvider` (`FutureProvider.family<List<UserProfile>, String>`).
- Add `UserRepository.searchByDisplayName(String q)` — prefix range query on `displayNameLowercase`, limit 20.
- Add `displayNameLowercase` field to `UserProfile` (`lib/features/profile/domain/user_profile.dart`) — `fromJson` / `toJson` / `copyWith`.
- Write `displayNameLowercase` in `UserRepository.getOrCreate`, `createIfAbsent`, and lazy-backfill on `update`.
- Write `displayNameLowercase` in `ProfileSetupFlow` (`lib/features/profile_setup/presentation/profile_setup_flow.dart`) when displayName is committed.
- Wire search icon in `_FeedHeader` (line 62) → `context.push('/feed/search')`.
- Add `GoRoute(path: 'search')` under `/feed` in `lib/app/router.dart`.
- Empty / loading / no-results / error states via `FeedEmptyState`.
- Tests: repo search (3 cases: matches / no matches / empty query), provider (debounce + 2-char gate), screen widget (states), tile widget.

### Out of Scope (explicit, deferred)

- Workout attach in create form (Fase 4)
- Real routine picker (Fase 4)
- Edit / delete posts
- Likes / comments
- Trending users / suggested follows
- Search posts (only users)
- Inline follow / unfollow from search tiles
- `@handle` field
- Algolia / Typesense / Meilisearch external search
- Notification on follow request
- Deep links to `/feed/create` or `/feed/search`
- Backfill script for existing UserProfile docs (lazy strategy only)

---

## Capabilities

### New Capabilities

- `feed-create-post`: Authenticated user creates a text post with selectable privacy (friends/gym/public) from a dedicated route, with the new post appearing in the relevant feed segment immediately after publish.
- `feed-search-users`: Authenticated user finds other users by case-insensitive display-name prefix (min 2 chars) and navigates to their public profile.

### Modified Capabilities

- `user-profile` (if a spec exists for it): adds `displayNameLowercase` normalized field — written at every `displayName` write site (ProfileSetup commit, `getOrCreate`, `createIfAbsent`, `update`).

If no `user-profile` spec exists in `openspec/specs/`, `sdd-spec` should treat the displayNameLowercase change as part of the `feed-search-users` spec (the consumer) and document the model-field addition there.

---

## Approach

**Approach A from explore** — two dedicated GoRoute sub-routes under `/feed/` (`/feed/create`, `/feed/search`), mirroring the `/feed/profile/:uid` pattern from Etapa 4. Rationale: consistent router pattern, natural back navigation, testable in isolation, no modal/animation complexity.

**Search Option 2 from explore** — `displayNameLowercase` normalized field on UserProfile. Range query: `where('displayNameLowercase', isGreaterThanOrEqualTo: q.toLowerCase()).where('displayNameLowercase', isLessThan: '${q.toLowerCase()}~').limit(20)`. Rationale: case-insensitive prefix UX is usable; Option 1 (case-sensitive) is broken UX; Option 3 (external) overkill for MVP; Option 4 (client-side) scale bomb.

**State management**: Riverpod 2. `AsyncNotifier` for create-post form (built-in submit lifecycle). `FutureProvider.family` for search keyed by query string with debounce in the screen layer.

**Visual language** (no mockups): match existing feed pattern — `AppPalette.of(context)` (mint magenta), `GoogleFonts.barlowCondensed` (headers/labels) + `GoogleFonts.barlow` (body), `TreinoIcon.X` throughout, spacing scale 8/12/14/18/20 only, no Scaffold (relies on `_ShellScaffold`). Reference: `PublicProfileScreen`, `PostCard`, `FeedSegmentPills` for pill pattern, `FeedEmptyState` for empty/error.

---

## PR Chain Plan

```
PR#1: feat/feed-create-post → targets main
  Branch: feat/feed-create-post (cut from main)
  Delivers: CreatePostScreen, notifier, plus-button wire, /feed/create route
  Estimated diff: ~272 prod LOC + ~280 test LOC = ~552 changed lines
  Budget: within 400 prod LOC ✓ — single PR, no exception needed
  Merge gate: green CI + reviewer approval

PR#2: feat/feed-search-users → targets main (AFTER PR#1 merges)
  Branch: feat/feed-search-users (cut from main once PR#1 merged)
  Delivers: SearchUsersScreen, UserSearchResultTile, searchUsersProvider,
            UserRepository.searchByDisplayName, displayNameLowercase model field,
            ProfileSetupFlow write, search-icon wire, /feed/search route
  Estimated diff: ~325 prod LOC + ~320 test LOC = ~645 changed lines
  Budget: 325 prod LOC slightly over 400 ALSO with tests — may request size:exception
          if reviewer agrees the model + repo + screen + tests cohere as one unit.
          Otherwise can split further (model+repo first, screen+tile second).
  Merge gate: green CI + reviewer approval + PR#1 already on main
```

**Dependency**: PR#2 cannot start integration until PR#1 is on main, because both touch `_FeedHeader` and `router.dart`. Working on PR#2 in parallel before PR#1 merges risks textual conflicts in the same wire lines.

**After both PRs merge**: `sdd-archive` consolidates the change.

---

## Affected Areas

| Area | Impact | PR | Description |
|---|---|---|---|
| `lib/features/feed/presentation/create_post_screen.dart` | New | PR#1 | Form screen ~180 LOC |
| `lib/features/feed/application/create_post_notifier.dart` | New | PR#1 | AsyncNotifier ~80 LOC |
| `lib/features/feed/feed_screen.dart` | Modified | PR#1 + PR#2 | Wire plus button (PR#1) + search icon (PR#2) |
| `lib/app/router.dart` | Modified | PR#1 + PR#2 | Add `/feed/create` (PR#1) + `/feed/search` (PR#2) |
| `lib/features/feed/presentation/search_users_screen.dart` | New | PR#2 | Search screen ~160 LOC |
| `lib/features/feed/presentation/widgets/user_search_result_tile.dart` | New | PR#2 | Result row ~90 LOC |
| `lib/features/feed/application/search_users_provider.dart` | New | PR#2 | FutureProvider.family ~40 LOC |
| `lib/features/profile/data/user_repository.dart` | Modified | PR#2 | +`searchByDisplayName` + write `displayNameLowercase` in 3 sites |
| `lib/features/profile/domain/user_profile.dart` | Modified | PR#2 | +`displayNameLowercase` field |
| `lib/features/profile_setup/presentation/profile_setup_flow.dart` | Modified | PR#2 | Write `displayNameLowercase` on commit |
| `test/features/feed/**` | New | PR#1 + PR#2 | Notifier, screen, tile, provider tests |
| `test/features/profile/data/user_repository_search_test.dart` | New | PR#2 | Repo search tests |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Existing UserProfile docs lack `displayNameLowercase` → invisible in search until they edit profile | High | Medium | Lazy backfill on next `UserRepository.update`. Document the gap in spec. Accept that legacy users need one profile edit to become searchable — acceptable for MVP scale. |
| PR#2 prod LOC exceeds 400 budget | Medium | Medium | Two options at PR open time: (a) request reviewer `size:exception` justified by the cohesive model+repo+screen unit, or (b) split into PR#2a (model+repo+ProfileSetup) and PR#2b (screen+tile+wire). `sdd-tasks` must surface this decision. |
| Prefix-only search misses substring matches ("artin" won't find "Martin") | High | Low | Documented Firestore limitation. Locked as MVP trade-off. Out-of-scope to fix without external search service. |
| Cross-dev conflict on `UserProfile` model (owned by profile team) | Low | High | User already greenlit + notified other devs via handoff. Confirm no in-flight branch touches `user_profile.dart` before opening PR#2. |
| Gym-privacy post with null gymId silently invisible | Low | Medium | Gym pill DISABLED when `gymId == null` — user cannot reach the invalid state. Add notifier-side guard as defense-in-depth. |
| Keyboard overlaps PUBLICAR button on small screens | Medium | Low | Wrap form in `SingleChildScrollView`. Verified via widget test with `tester.binding.window.physicalSizeTestValue`. |
| Feed providers not actually `FutureProvider` (assumed in explore) | Low | Medium | Verify in `sdd-spec` / `sdd-design`. If any is `StreamProvider`, `ref.invalidate` semantics differ — adjust create-post notifier accordingly. |

---

## Rollback Plan

### PR#1 rollback (`feat/feed-create-post`)

`git revert <merge-commit>`. Safe — purely additive code (new screen + new notifier + new route + 2 modified lines wiring plus button). No data model changes, no Firestore writes outside the existing `PostRepository.create()` path. Users lose the ability to create posts via UI; the underlying repository call is untouched.

### PR#2 rollback (`feat/feed-search-users`)

`git revert <merge-commit>`. Slightly more complex because PR#2 adds `displayNameLowercase` to UserProfile. Revert behavior:

- `UserProfile.fromJson` will no longer parse the field — existing Firestore docs that have it written stay valid (extra field is ignored).
- `UserRepository` write paths revert to not writing it — newly written docs after revert won't have the field, but the field on existing docs stays orphaned (harmless).
- Search route + screen disappear.

**No data migration required for either revert.** Both PRs are forward-compatible reverts.

---

## Dependencies

- **Etapas 1-4 merged** (confirmed in explore — public profile, follow, feed list already on `main`).
- **No Firebase/Firestore rule changes** — read paths use existing auth check (HARD constraint).
- **No mockups** — visual MVP matches existing feed primitives. Refinement is post-MVP if mockups arrive.
- **Other devs notified** about `displayNameLowercase` touching profile model — user confirmed handoff.
- **Strict TDD active** — sdd-apply MUST follow strict-tdd.md.

---

## Success Criteria

### PR#1

- [ ] Plus button in `_FeedHeader` navigates to `/feed/create`.
- [ ] Form validates: text non-empty, max 280 chars, privacy required.
- [ ] PUBLICAR creates a post via `PostRepository.create()` and pops back to feed.
- [ ] After publish, the 3 feed providers are invalidated and the new post is visible on the appropriate segment.
- [ ] CANCELAR pops without writing.
- [ ] Gym pill is disabled (opacity 0.4) when user has no `gymId`.
- [ ] Routine tag chip renders disabled with stub copy.
- [ ] All tests pass; `flutter analyze` 0 issues; `dart format` clean.

### PR#2

- [ ] Search icon in `_FeedHeader` navigates to `/feed/search`.
- [ ] Search bar with 2-char min + 300ms debounce.
- [ ] Results show avatar + name + gym; tap navigates to `/feed/profile/$uid`.
- [ ] Empty / no-results / error states render via `FeedEmptyState`.
- [ ] `UserProfile.displayNameLowercase` written on ProfileSetup commit + `getOrCreate` + `createIfAbsent` + lazy on `update`.
- [ ] `UserRepository.searchByDisplayName` returns ≤20 results, case-insensitive prefix.
- [ ] All tests pass; `flutter analyze` 0 issues; `dart format` clean.

### Combined (after both merge)

- [ ] User journey end-to-end: feed → plus → write post → publish → see in feed; feed → search → type name → tap result → land on public profile.
- [ ] `sdd-archive` consolidates both PRs.
- [ ] Fase 3 closed.

---

## Review Workload Forecast

| PR | Prod LOC | Test LOC | Total Changed | Budget Risk | Decision needed before apply | Chained PRs recommended | Delivery strategy |
|---|---|---|---|---|---|---|---|
| PR#1 `feat/feed-create-post` | ~272 | ~280 | ~552 | Low (prod within 400) | No | N/A (already chained) | Single chain slice, no exception |
| PR#2 `feat/feed-search-users` | ~325 | ~320 | ~645 | Medium (prod near 400) | Yes — at PR open: request `size:exception` OR split into PR#2a model+repo / PR#2b screen+wire | Yes (further split possible) | `ask-on-risk` resolves to `size:exception` if cohesive, or sub-chain |

`sdd-tasks` must surface PR#2's split-or-exception decision explicitly with the cached delivery strategy.

# Exploration: feed-create-search (Fase 3 · Etapa 5)

**Change**: `feed-create-search`
**Fase / Etapa**: Fase 3 · Etapa 5 (LAST etapa of Fase 3)
**Branch**: `feat/feed-create-search` (off `main` at `a4780d4`)
**Owner**: Dev C
**Artifact store**: hybrid (openspec + engram)
**Depends on**: Etapas 1-4 all merged

---

## 1. Goal

Deliver the plus-button create-post form (`/feed/create`) and the search-users screen (`/feed/search`) as the final social primitives of Fase 3, without attaching workouts (deferred to Fase 4).

---

## 2. Mockup Check

**No mockups exist** for `/feed/create` or `/feed/search` in `docs/app-alumno/screens/feed/`.

The design-decisions.md feed section references only:
- `docs/app-alumno/screens/feed/feed.png` — main feed list (shows the Q icon and mint circle plus button in the header at top-right)
- `docs/app-alumno/screens/feed/feed-publico.png` — this is actually the public profile mockup (Mateo Quintero with SEGUIR/MENSAJE buttons)

FLAGGED: Both sub-screens must be designed minimally, matching the visual language of the existing feed (`PublicProfileScreen`, `PostCard`, `FeedEmptyState` as reference).

Minimalist approach for each:
- **Create post**: Dark-background form card, `TextField` for text, `SegmentedControl`-style privacy selector (3 pills matching `FeedSegmentPills` pattern), optional routine tag selector (dropdown or pill), submit button in mint accent. No Scaffold header — use a custom `_CreatePostHeader` with CANCELAR + PUBLICAR CTAs at the top in the same style as other screens.
- **Search users**: Header with `TextField` search bar (no bottom bar search — dedicated screen), result list of `UserSearchResultTile` widgets mirroring the `PostCard` avatar+name pattern. Empty/loading/error states via `FeedEmptyState`.

---

## 3. Codebase Mapping

### `lib/features/feed/feed_screen.dart`

| Symbol | Line | Notes |
|---|---|---|
| `_FeedHeader` | 41 | Has `TreinoIcon.search` (tappable but not wired — no `onTap`) at line 62; plus button at lines 64-76 (mint `BoxDecoration` circle with `TreinoIcon.plus`) — both are STATIC, no navigation wired |
| Plus button | 64-76 | `Container` with no `GestureDetector` — must be wrapped |
| Search icon | 62 | `Icon(TreinoIcon.search)` — must be wrapped with `GestureDetector` |
| `PostCard` instantiations | 99, 154, 200 | All three body variants already wire `onAuthorTap` (merged from Etapa 4) |

### `lib/features/feed/data/post_repository.dart`

| Method | Signature | Notes |
|---|---|---|
| `create` | `Future<Post> create(Post input)` | Already exists. Reads `users/{uid}.gymId` for denorm. Accepts `Post` with empty `id` → auto-assigns. All fields except `authorGymId` must be supplied by caller. |
| `byAuthor` | `Future<List<Post>> byAuthor(String uid)` | No limit/order — raw collection scan |
| `feedPublic`, `feedForFriends`, `feedForGym` | — | Feed queries, not relevant for create |

`PostRepository.create()` is fully ready — no changes needed. The create-post form will build a `Post` object and call this method.

### `lib/features/profile/data/user_repository.dart`

**No search method exists.** Current methods: `getOrCreate`, `createIfAbsent`, `get`, `update`, `watch`, `delete`.

The `users` collection has these indexed fields (from `UserProfile`): `uid`, `email`, `displayName`, `gymId`. There is NO `handle` field and NO `displayNameLowercase` normalized field. Search by `displayName` is the only practical path unless we add a normalized field.

**Must design new search method** — see §7 for strategy.

### `lib/features/feed/presentation/public_profile_screen.dart`

Reference screen for sub-screen style:
- `ConsumerWidget` pattern (no `Scaffold` / `AppBackground` / `SafeArea` — provided by `_ShellScaffold`)
- Data: `ref.watch(someProvider).when(data, loading, error)`
- Loading: `Center(child: CircularProgressIndicator(color: palette.accent))`
- Error: `Padding(horizontal: 20, child: Center(child: Text(..., style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted))))`
- All colors: `AppPalette.of(context)`
- All fonts: `GoogleFonts.barlowCondensed` (labels/headers) + `GoogleFonts.barlow` (body)

### `lib/app/router.dart`

Current `/feed` routes (lines 161-171):
```
GoRoute(path: '/feed', ...)
  GoRoute(path: 'profile/:uid', ...)  ← already exists (Etapa 4)
```

New routes to add:
- `GoRoute(path: 'create', ...)` → `CreatePostScreen`
- `GoRoute(path: 'search', ...)` → `SearchUsersScreen`

Both nested under `/feed` ShellRoute. `_kTabs` already uses `startsWith` — `/feed/create` and `/feed/search` resolve to Feed tab index automatically. No changes to `_kTabs`.

---

## 4. Re-use vs. New

### Reusable (no modification needed)

| Widget / Class | Where used | How reused |
|---|---|---|
| `PostAvatar` | `post_avatar.dart` | Search result tiles use same avatar component (same API: `authorDisplayName`, `authorAvatarUrl`, `size`) |
| `FeedEmptyState` | `feed_empty_state.dart` | Empty search results, empty create confirmation — exact same widget |
| `PostRepository.create()` | `post_repository.dart` | Called by the new `createPostProvider` notifier |
| `postRepositoryProvider` | `post_providers.dart` | Watched by new create-post notifier |
| `authStateChangesProvider` | `auth_providers.dart` | Used to get `viewerUid`, `authorDisplayName`, `authorAvatarUrl` for post creation |
| `userProfileProvider` | `user_providers.dart` | Gets `gymId` for denorm (already done inside `PostRepository.create`, but needed for privacy selector gym validation) |
| `PublicProfileFollowButton` pattern | Etapa 4 | Search result tiles may show a follow button — follow the exact same 4-state pattern, possibly reusing the widget directly |
| `AppPalette.of(context)` | everywhere | All colors |
| `TreinoIcon.X` | everywhere | All icons |
| `_ProfilePill` pattern | `public_profile_screen.dart` | Privacy selector pills can mirror this exact shape |

### New (must create)

| File | Purpose | Approx LOC |
|---|---|---|
| `lib/features/feed/presentation/create_post_screen.dart` | Form screen with text + privacy + optional routine tag | ~180 |
| `lib/features/feed/presentation/search_users_screen.dart` | Search bar + result list | ~160 |
| `lib/features/feed/presentation/widgets/user_search_result_tile.dart` | Result row: avatar + name + gym + follow button | ~90 |
| `lib/features/feed/application/create_post_notifier.dart` (or inline) | `AsyncNotifier` managing form state + submit | ~80 |
| `lib/features/feed/application/search_users_provider.dart` | `FutureProvider.family<List<UserProfile>, String>` keyed on query string | ~40 |
| `lib/features/profile/data/user_repository.dart` | Add `searchByDisplayName(String q)` method | +20 LOC |
| `test/features/feed/data/...` | Tests for new repo method | ~60 |
| `test/features/feed/application/...` | Tests for create notifier + search provider | ~120 |
| `test/features/feed/presentation/...` | Widget + screen tests | ~300 |
| `lib/app/router.dart` | 2 new routes | +14 LOC |
| `lib/features/feed/feed_screen.dart` | Wire plus button + search icon with navigation | +8 LOC |

---

## 5. Sub-Feature Scope

### 5a. Crear Post

**Entry point**: Plus button in `_FeedHeader` (line 64 in `feed_screen.dart`) → `context.push('/feed/create')`.

**Form fields**:
1. `text` (required) — multiline `TextField`, min 1 char, max 280 chars. Validation: non-empty.
2. `privacy` (required, default: `PostPrivacy.friends`) — 3-pill selector: AMIGOS / MI GYM / PÚBLICO. The gym pill should be disabled (with opacity 0.4) if the user has no `gymId`.
3. `routineTag` (optional) — "Etiquetar rutina" chip/button. Opens a simple picker (dropdown or modal) showing the user's routines. Tapping clears or sets the `RoutineTag`. **Complexity note**: requires reading `postsByAuthorProvider` or a new `myRoutinesProvider` — likely out of full scope for this etapa unless routines already exist in Firestore. **Recommendation**: include the UI affordance (a chip stub that shows "ETIQUETAR RUTINA" tappable, navigates to nothing yet) but defer real picker to Fase 4. This matches the `_MessageButtonStub` pattern from Etapa 4.

**Validation**: text non-empty. Privacy valid. No server-side validation needed (Firestore rules cover auth).

**Navigation flow**:
```
FeedScreen (_FeedHeader plus button tap)
  → context.push('/feed/create')
    → CreatePostScreen
      → [user fills form] → tap PUBLICAR → createPostNotifier.submit()
        → on success: context.pop() → back to FeedScreen
          [invalidate feed providers so new post appears]
        → on error: show snackbar/inline error
      → tap CANCELAR → context.pop()
```

**State management**: `AsyncNotifier` (Riverpod 2) managing `{text, privacy, routineTag, isSubmitting}`. On submit: build a `Post` with `authorUid` from auth, `authorDisplayName`/`authorAvatarUrl` from auth user (or userProfileProvider), then call `postRepositoryProvider.create(post)`. After success: `ref.invalidate` the relevant feed providers.

**Which feed providers to invalidate after create**: `myFriendsFeedProvider`, `feedPublicProvider`, and `myGymFeedProvider` — all three may be stale. This is safe with `autoDispose: false` default of those providers.

### 5b. Search Users

**Entry point**: Search icon in `_FeedHeader` (line 62) → `context.push('/feed/search')`.

**Query**: See §7.

**Result display**: List of `UserSearchResultTile` — avatar (via `PostAvatar`) + display name + gym name (via `gymNameFromId`) + follow button. Tapping the tile navigates to `/feed/profile/:uid`.

**States**:
- Empty query → empty state with "Buscá usuarios por nombre" copy.
- Typing (debounced 300ms) → loading spinner.
- Results: list of tiles.
- No results: `FeedEmptyState(message: 'Sin resultados para "$query"')`.
- Error: inline error text.

**Navigation**: `SearchUsersScreen` → tap tile → `context.push('/feed/profile/$uid')`. Back button → `context.pop()` → back to FeedScreen.

---

## 6. Approaches

| Approach | Description | Pros | Cons | Complexity |
|---|---|---|---|---|
| **A — Two dedicated sub-routes** (`/feed/create` + `/feed/search`) | Both screens are full GoRoute children under `/feed`, matching the `/feed/profile/:uid` pattern from Etapa 4. | Consistent with existing router pattern; back navigation is natural; bottom bar stays visible; testable in isolation; no modal complexity | Slightly more boilerplate per screen (need GoRoute entries) | Low-Medium |
| **B — Modal bottom sheet for create + dedicated route for search** | Create post opens as `showModalBottomSheet`; search uses a dedicated route | Create feels more "quick entry" (common social app pattern); no route needed for create | Modal bottom sheets are harder to test in Flutter widget tests; form state management is trickier (no GoRouter context); keyboard handling in modals needs extra work; inconsistent with Etapa 4 pattern | Medium-High |
| **C — Inline panel (AnimatedContainer) in FeedScreen** | Create post slides up as an animated panel within the feed shell | Zero navigation cost | Breaks the established push/pop navigation model; cannot be deep-linked; very hard to test; would require significant `FeedScreen` refactoring | High |

**Recommendation: Approach A** — two dedicated sub-routes under `/feed/`. It mirrors exactly what Etapa 4 did with `/feed/profile/:uid`, keeps tests straightforward, and is consistent with the team's established pattern.

---

## 7. Search Query Strategy

Firestore does NOT support free-text search. Options ranked:

| Option | Approach | Complexity | Accuracy | Cost |
|---|---|---|---|---|
| **1. Prefix range on `displayName`** | `where('displayName', isGreaterThanOrEqualTo: q).where('displayName', isLessThan: q + '')` | Low | Prefix only, case-sensitive | Minimal reads |
| **2. Normalized `displayNameLowercase` field** | Add `displayNameLowercase` to `UserProfile`, normalize at write time, range query on lowercase field | Low-Medium (requires data migration + `UserRepository.update` change) | Prefix, case-insensitive | Minimal reads, 1 index |
| **3. External search (Algolia/Typesense/Meilisearch)** | Full-text search service | High (infra setup, Cloud Function sync) | Excellent | $$ / complexity |
| **4. Client-side filter (load all users)** | `_users.get()` then filter in Dart | Trivial | Full substring | Dangerous at scale |

**Recommendation: Option 2 — `displayNameLowercase` normalized field.**

Rationale:
- Option 1 (case-sensitive prefix) is nearly useless UX — "Martin" won't find "martin" or vice versa.
- Option 4 is a scale bomb — unacceptable even at 100 users.
- Option 3 is overengineering for an MVP with low user count.
- Option 2 requires adding `displayNameLowercase` to `UserProfile.fromJson/toJson` and writing it when `displayName` is set in `ProfileSetup`. The field can be backfilled via a one-time migration script or written lazily (first write on next ProfileSetup update). The Firestore index on `displayNameLowercase` is a single composite-free single-field index (auto-indexed by default). The query:

```dart
_users
  .where('displayNameLowercase', isGreaterThanOrEqualTo: q.toLowerCase())
  .where('displayNameLowercase', isLessThan: '${q.toLowerCase()}')
  .limit(20)
```

**Important constraint**: This adds `displayNameLowercase` to `UserProfile` — which touches a model owned by the `profile` feature. The propose phase must lock this decision explicitly.

**Alternative if the model change is rejected**: Prefix on `displayName` (case-sensitive, Option 1) as a degraded fallback — still useful for users who type exact-case prefixes.

---

## 8. PR Size Analysis

### Create Post sub-feature

| File | Action | Est. LOC |
|---|---|---|
| `create_post_screen.dart` | new | ~180 |
| `create_post_notifier.dart` | new | ~80 |
| `feed_screen.dart` | modify (wire plus button) | +5 |
| `router.dart` | modify (add route) | +7 |
| `test/...create_post_notifier_test.dart` | new | ~100 |
| `test/...create_post_screen_test.dart` | new | ~180 |
| **Sub-total production** | | ~272 |
| **Sub-total test** | | ~280 |

### Search Users sub-feature

| File | Action | Est. LOC |
|---|---|---|
| `search_users_screen.dart` | new | ~160 |
| `user_search_result_tile.dart` | new | ~90 |
| `search_users_provider.dart` | new | ~40 |
| `user_repository.dart` | modify (add searchByDisplayName) | +20 |
| `user_profile.dart` | modify (add displayNameLowercase) | +5 |
| `feed_screen.dart` | modify (wire search icon) | +3 |
| `router.dart` | modify (add route) | +7 |
| `test/...user_repository_search_test.dart` | new | ~60 |
| `test/...search_users_screen_test.dart` | new | ~180 |
| `test/...user_search_result_tile_test.dart` | new | ~80 |
| **Sub-total production** | | ~325 |
| **Sub-total test** | | ~320 |

### Combined totals

| Metric | Value |
|---|---|
| Total production LOC | ~597 |
| Total test LOC | ~600 |
| Total diff | ~1197 |
| 400-line production budget | **EXCEEDED (~597 > 400)** |
| Decision needed before apply | **Yes** |
| Chained PRs recommended | **Yes** |
| 400-line budget risk | **High** |

**Recommendation: Chained PRs.**

- **PR #1** (`feat/feed-create-post`): create-post form only. ~272 prod LOC + ~280 test LOC. Well within budget.
- **PR #2** (`feat/feed-search-users`): search screen + `displayNameLowercase` model change. ~325 prod LOC + ~320 test LOC. Slightly over 400 prod — may need `size:exception` or split further.
- PR #2 depends on PR #1 being merged (uses same `_FeedHeader` wire pattern + router).

---

## 9. Failure Modes / Risks

1. **`displayNameLowercase` migration gap**: existing `UserProfile` docs in Firestore won't have the field. Search will return empty results for any user who hasn't gone through ProfileSetup since the field was added. Mitigation: write the field lazily on next `UserRepository.update` + add `displayNameLowercase: displayName?.toLowerCase()` to `getOrCreate` and `createIfAbsent`. Still, users who haven't touched their profile since launch won't appear in search until they update.

2. **Feed invalidation after create post**: after `PostRepository.create()` succeeds, the app must invalidate `myFriendsFeedProvider`, `feedPublicProvider`, and `myGymFeedProvider`. If any of these is a `StreamProvider` instead of `FutureProvider`, invalidation works differently. Currently they are `FutureProvider` — invalidation is a single `ref.invalidate` call. Risk: if a user creates a `PostPrivacy.gym` post but their `gymId` is null (gym pill was disabled), the post writes with `authorGymId: null` and won't appear in gym feed — this is correct behavior, but the privacy selector must validate and disable the gym option when `gymId == null`.

3. **Prefix search UX limitation**: even with `displayNameLowercase`, the range query is prefix-only. A user searching "artin" won't find "Martin". This is a known Firestore limitation — the explore should flag it explicitly so propose can lock the trade-off.

4. **Routine tag picker scope creep**: the `RoutineTag` field in `Post` expects `{routineId, routineName}`. To populate this, the form needs to list the user's routines. Routines live in the `workout` feature — importing them from the `feed` feature creates a cross-feature dependency. The safe path is a stub affordance (like `_MessageButtonStub`) with `onTap: null` until Fase 4.

5. **`PostPrivacy.gym` + no gym guard**: if the user selects gym privacy but `userProfileProvider` returns `gymId == null`, `PostRepository.create()` will still succeed but denormalize `authorGymId: null` — making the post invisible in gym feed. The form must read `userProfileProvider` and disable the gym pill if no gym.

6. **Keyboard overlap on create form**: a full-screen form with `TextField` + submit button risks the submit being obscured by the soft keyboard. The form needs `SingleChildScrollView` or `resizeToAvoidBottomInset: true` — but since there's no `Scaffold` here (handled by `_ShellScaffold`), `resizeToAvoidBottomInset` may not apply. Solution: wrap form body in `SingleChildScrollView`.

---

## 10. Open Questions for `sdd-propose`

1. **displayNameLowercase field**: Add to `UserProfile` + backfill strategy? Or accept case-sensitive prefix search (Option 1)? This touches `profile` feature owned by another dev.
2. **Routine tag picker**: Full implementation (requires workout feature cross-dep) OR stub affordance (like `_MessageButtonStub`) for this etapa? STRONG recommendation: stub it.
3. **Privacy selector default**: `PostPrivacy.friends` or `PostPrivacy.public`? The roadmap says "privacy selector" without specifying a default.
4. **Gym pill disabled state**: If user has no gym, should the gym option be hidden entirely or shown as disabled (opacity-reduced, no-op)? Hidden is cleaner; disabled communicates the option exists but is gated.
5. **Search result follow button**: Should `UserSearchResultTile` include a `PublicProfileFollowButton`? If so, it needs the same `friendshipByPairProvider` — adds Firestore reads per result. Alternative: tap tile to navigate to profile (where the follow button already exists). Recommendation: no inline follow button in search results — just tap to profile.
6. **Character limit for post text**: 280 chars (Twitter parity) or different? The `Post` domain model has no `maxLength` constraint — propose should lock it.
7. **Search minimum query length**: Show results starting from 1 char or 2+ chars? 1 char = many results; 2 chars = more useful. Recommend: 2 chars minimum before querying, to avoid expensive prefix scans on single-letter queries.
8. **Post creation success UX**: After creating a post, pop back to feed (and scroll to top to see the new post)? Or show a success toast then pop? The `myFriendsFeedProvider` invalidation will trigger a reload — but the new post may not be at the top if createdAt ordering differs.
9. **`displayNameLowercase` scope**: Does it need to be written in `ProfileSetupFlow` as well? Profile setup is the canonical source for `displayName` — the field must also be written there, touching `profile_setup` feature.
10. **Chained PR strategy**: Lock PR split as `feat/feed-create-post` → `feat/feed-search-users`? Or accept `size:exception` on a single PR?

---

## 11. Out of Scope (explicit)

- Attachment de workout en post (Fase 4)
- Editar / borrar posts
- Likes / comments
- Trending users / suggested follows
- Search posts (only users)
- Real routine picker in create form (Fase 4)
- Unfollow from search results
- Notification on follow request
- Deep links to create or search screens
- `@handle` field (does not exist in any model — documented in Etapa 4 as deferred)
- Stats reales en perfiles de búsqueda

---

## Recommendation

**Approach A + Search Option 2** (dedicated routes + `displayNameLowercase` normalized prefix search) with **chained PRs**: create-post first, search-users second.

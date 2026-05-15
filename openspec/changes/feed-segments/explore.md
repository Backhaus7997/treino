# Exploration: Feed Segments — MI GYM + PÚBLICO (Etapa 3)

## 1. Goal

Wire the MI GYM and PÚBLICO segments of the Feed tab by connecting existing `feedForGymProvider` and `feedPublicProvider` to new body widgets, sourcing `gymId` from `userProfileProvider`, enabling the pills, and handling the no-gymId empty state.

---

## 2. Mockup Analysis

**Source**: `docs/app-alumno/screens/feed/feed.png` (only one Feed mockup exists).
`docs/design-decisions.md` also references `feed-publico.png` under "Card Público" — inspection confirms it is the *public profile* screen (Etapa 4), NOT a dedicated segment view.

**Visual findings from `feed.png`:**
- Header: "FEED" (Barlow Condensed 700 UPPERCASE) + search icon (muted) + green circle `+` button (accent fill)
- Three pills: AMIGOS (active, accent fill, dark text) | MI GYM (inactive) | PÚBLICO (inactive)
- Post cards are identical in structure across segments: avatar + display name + gym · timestamp + overflow `...` + body text + optional routine tag chip + stats row (stub)
- No segment-specific visual differentiation: MI GYM and PÚBLICO render the same `PostCard` layout

**Implication**: No new widget design needed for MI GYM or PÚBLICO bodies — they are structurally identical to AMIGOS body, differing only in data source.

---

## 3. Codebase Mapping

### Anchor table

| File | Line(s) | What it anchors |
|---|---|---|
| `lib/features/feed/feed_screen.dart` | 28–31 | Switch on `FeedSegment` — GYM+PUBLIC collapse to `SizedBox.shrink()` (stub to replace) |
| `lib/features/feed/feed_screen.dart` | 76–114 | `_AmigosBody` — pattern to replicate for new body widgets |
| `lib/features/feed/feed_screen.dart` | 82 | `ref.watch(myFriendsFeedProvider)` — provider call pattern |
| `lib/features/feed/feed_screen.dart` | 99–113 | Error text in Spanish inline — pattern to replicate or extract |
| `lib/features/feed/application/feed_screen_providers.dart` | 9–11 | `feedSegmentProvider` (StateProvider\<FeedSegment\>) |
| `lib/features/feed/application/feed_screen_providers.dart` | 13–21 | `myFriendsFeedProvider` — the wrapper pattern: resolves uid → friendUids → posts |
| `lib/features/feed/application/post_providers.dart` | 13–15 | `feedPublicProvider` — raw, no auth dependency, ready to consume directly |
| `lib/features/feed/application/post_providers.dart` | 27–29 | `feedForGymProvider` — FutureProvider.family\<List\<Post\>, String\>; needs gymId |
| `lib/features/feed/presentation/widgets/feed_segment_pills.dart` | 29–38 | MI GYM pill hardcoded `isActive: false, onTap: null` (must be wired) |
| `lib/features/feed/presentation/widgets/feed_segment_pills.dart` | 40–44 | PÚBLICO pill hardcoded `isActive: false, onTap: null` (must be wired) |
| `lib/features/feed/presentation/widgets/feed_empty_state.dart` | 11 | `_kCopy` hardcoded as `'Aún no hay posts de tus amigos'` — not parameterizable |
| `lib/features/feed/data/post_repository.dart` | 42–46 | `feedPublic()` — simple query, no params |
| `lib/features/feed/data/post_repository.dart` | 73–80 | `feedForGym(gymId)` — filters `privacy=gym AND authorGymId==gymId` |
| `lib/features/profile/domain/user_profile.dart` | 25 | `String? gymId` — nullable; user may not have a gym |
| `lib/features/profile/application/user_providers.dart` | 18–28 | `userProfileProvider` — StreamProvider\<UserProfile?\>, reactive to auth |
| `lib/features/feed/domain/feed_segment.dart` | 1 | `enum FeedSegment { amigos, gym, public }` — names exactly match |

---

## 4. Stub vs. Real Provider Analysis

### `feedPublicProvider`
- **Status**: Ready as-is. No auth dependency required (public posts = all posts with `privacy=public`).
- **Can be consumed directly** in `_PublicoBody` via `ref.watch(feedPublicProvider)`.
- No wrapper needed.

### `feedForGymProvider`
- **Status**: Ready as raw provider. Requires a `gymId` String argument.
- **Needs a wrapper** analogous to `myFriendsFeedProvider` that:
  1. Watches `authStateChangesProvider` to get current user uid
  2. Watches `userProfileProvider` to get `profile.gymId`
  3. Handles the `gymId == null` case explicitly (not delegatable to the repo)
  4. Calls `feedForGymProvider(gymId)` only when gymId is non-null
- **Proposed name**: `myGymFeedProvider` — FutureProvider\<List\<Post\>?\> where `null` means "user has no gym" (distinct from empty list = "gym exists but no posts").

### `myFriendsFeedProvider` pattern (AMIGOS)
- References `authStateChangesProvider` (uid) → `acceptedFriendsProvider(uid)` → `feedForFriendsProvider(friendUids)`
- Has two guard clauses: `auth == null → []` and `friendUids.isEmpty → []`
- MI GYM wrapper should follow this pattern with its own guards.

---

## 5. gymId Source

### Where it lives
- `UserProfile.gymId` — `String?`, nullable (line 25, `user_profile.dart`)
- `userProfileProvider` — `StreamProvider<UserProfile?>` in `user_providers.dart` (reactive to auth)
- `PostRepository.create()` reads `users/{uid}.gymId` at write time to denormalize `authorGymId` into the post document (post_repository.dart line 21)

### What happens if gymId is null?
- The user has not been assigned to a gym (nullable by design, no default set).
- `feedForGym(gymId)` would need a non-null value — if null, skip the Firestore query entirely.
- **Decision needed**: show empty state with distinct copy ("Todavía no estás en un gym") OR hide the pill entirely for gym-less users?
- Recommendation: show empty state (not hide pill) — hiding a pill based on profile state creates reactive complexity and surprises users who later join a gym. An empty state is simpler and consistent.

### AuthStateChangesProvider return type
- Returns `User?` from Firebase Auth — provides `uid` but NOT `gymId`.
- Must compose: `auth → uid → userProfileProvider(uid)` or just `userProfileProvider` (already watches auth internally).

---

## 6. Approaches

| | **A: Inline switch in feed_screen.dart** | **B: Per-segment body widgets (_MiGymBody, _PublicoBody)** |
|---|---|---|
| **Description** | Add MI GYM and PÚBLICO logic directly inside the `switch` in `FeedScreen.build()`, inline with AMIGOS | Extract `_MiGymBody` and `_PublicoBody` as private `ConsumerWidget`s alongside `_AmigosBody` |
| **Consistency with existing code** | No — breaks pattern (AMIGOS is already a widget) | Yes — mirrors `_AmigosBody` exactly |
| **Testability** | Low — screen test must render full screen to test segment logic | High — each body can be golden-tested or provider-overridden independently |
| **Readability** | Degrades fast — build() grows to 150+ lines | Stays clean — each body is 30-40 lines |
| **Effort** | Low (fewer files) | Low-Medium (2 extra classes, same file or separate files) |
| **Complexity** | Low initially, high at maintenance | Low, consistent |
| **Merge risk** | `feed_screen.dart` grows, increases diff surface | Same file but modular — smaller diffs per widget |

**Recommendation: Approach B.** Etapa 2 deliberately established `_AmigosBody` as the pattern. MI GYM and PÚBLICO follow the same data → async → list/empty-state structure. Deviating from the pattern in the same file would be inconsistent and would hurt the next PR reviewer. The extra two classes add ~80 lines but keep `FeedScreen.build()` to <40 lines.

---

## 7. FeedEmptyState — Parameterization

**Current widget**: `FeedEmptyState` has `_kCopy` hardcoded as `'Aún no hay posts de tus amigos'` and uses `TreinoIcon.users` as the icon. Not parameterizable without modification.

**Since `post_card.dart` CANNOT be modified** (constraint from other dev), but `feed_empty_state.dart` has no such constraint.

### Options

| | **Option 1: Parameterize FeedEmptyState** | **Option 2: Inline Text in body widgets** |
|---|---|---|
| Adds `message` + `icon` params to `FeedEmptyState` | Yes | No |
| Reuses existing widget | Yes | No — duplicates layout |
| Requires touching existing widget | Yes (non-breaking, additive) | No |
| Preferred | **Yes** | No |

**Proposed parameterization**: add `final String message` (required) and `final IconData icon` (optional, default `TreinoIcon.users`). Mark existing callers as passing explicit strings. This is additive and backwards-compatible.

### Proposed copy

| Segment | Empty state copy (Spanish) | Icon |
|---|---|---|
| MI GYM (has gymId, no posts) | `'Tu gym todavía no tiene posts'` | `TreinoIcon.users` or a gym-themed icon |
| MI GYM (no gymId) | `'Todavía no estás en un gym'` | `TreinoIcon.users` |
| PÚBLICO | `'Aún no hay posts públicos'` | `TreinoIcon.globe` or `TreinoIcon.users` |

These use the same tone as the existing AMIGOS copy.

---

## 8. Pills Enablement

### Current state (`feed_segment_pills.dart` lines 29–44)
Both MI GYM and PÚBLICO pills have:
- `isActive: false` — hardcoded const, not driven by provider
- `onTap: null` — hardcoded null, disables GestureDetector

### Required changes
1. Remove `const` from both `_Pill(...)` constructors (they're currently `const` widgets — can't be reactive)
2. Wire `isActive` to `segment == FeedSegment.gym` / `segment == FeedSegment.public`
3. Wire `onTap` to set `feedSegmentProvider.notifier.state = FeedSegment.gym/public`

This is a 6-line change to `feed_segment_pills.dart`. The `_Pill` widget itself is already fully generic — `isActive` and `onTap` are both parameters.

---

## 9. Pagination Decision

**Recommendation: NO pagination in this PR.**

Rationale:
- Seed data is 6–10 posts total (roadmap line 161: "6-10 posts manuales de prueba"). Even with full seed, a single Firestore query returning 10 posts renders instantly.
- Firestore cursor-based pagination requires a `startAfterDocument` + `limit` query, which means breaking the current `feedPublic()` / `feedForGym()` repository signatures from simple `Future<List<Post>>` to a stream- or page-aware API. That is a data layer change with non-trivial scope.
- The roadmap explicitly says "Paginación **si entra en scope**" — the qualifier signals this is optional.
- Adding pagination now would balloon this PR well above the 400-line budget and require coordinating with the data layer (Etapa 1 owner).
- Deferral path: open a `// TODO(pagination): add cursor-based pagination` comment in both body widgets at the ListView call site.

---

## 10. Failure Modes

1. **gymId is null at runtime**: User profile loads without `gymId` — the `myGymFeedProvider` wrapper must guard this and return a distinct signal (null vs empty list) so the UI shows the correct empty state copy. If unguarded, `feedForGymProvider(null)` will crash or return wrong data.

2. **`userProfileProvider` is in loading state**: The MI GYM body must handle the AsyncValue loading case from `userProfileProvider`. If the profile stream hasn't emitted yet, show a spinner — not an error. Failure to handle `loading` produces a blank screen or premature empty state.

3. **`feedForGymProvider` query returns posts from other gyms**: Not a code bug but a Firestore security rules concern — the repo filters by `authorGymId == gymId` client-side and Firestore rules must enforce the same. If rules are misconfigured, users see other gyms' posts. No code change needed here, but a note for QA.

4. **Pills stay inert after removing `const`**: Removing `const` from `_Pill` constructors in `FeedSegmentPills` requires verifying that `FeedSegmentPills` itself is NOT declared as `const` at its call site in `feed_screen.dart` (line 25). It is `const FeedSegmentPills()` — that const must remain since the widget itself is stateless and the const call site doesn't block internal reactivity as long as the widget reads from the ref.

   Actually: `FeedSegmentPills` is a `ConsumerWidget` that already calls `ref.watch(feedSegmentProvider)`. So the `const FeedSegmentPills()` at the call site is valid — the constructor is const, but `build()` is reactive. The child `_Pill` constructors just need `isActive` and `onTap` to be non-const expressions (computed from segment), which is fine.

5. **Merge conflicts on `feed_screen_providers.dart`**: Adding `myGymFeedProvider` requires importing `userProfileProvider` from the profile layer. Dev C (Etapa 4) may also add imports there. Low probability but worth coordinating.

6. **Empty FeedSegment switch case exhaustion**: After enabling MI GYM and PÚBLICO, the switch at `feed_screen.dart:30` must be exhaustive. Dart will warn at analysis time if a case is missing. The current `FeedSegment.gym || FeedSegment.public => SizedBox.shrink()` will change to two distinct cases — must verify the enum has exactly {amigos, gym, public} and no new values are added in this PR.

---

## 11. Open Questions for sdd-propose

1. Should `myGymFeedProvider` return `List<Post>?` (null = no gym) or `List<Post>` (empty = no gym) with a separate `hasGymProvider` boolean? What's the cleanest API for the body widget?
2. Should `FeedEmptyState` be parameterized (breaking existing callers) or should we create `_GymEmptyState`/`_PublicoEmptyState` private widgets? Which is the team's preference?
3. Should the MI GYM pill be visually disabled/grayed when `gymId == null`, or always tappable (then shows "no gym" empty state)?
4. Do we need a `myGymFeedProvider` wrapper in `feed_screen_providers.dart` or should `_MiGymBody` read `userProfileProvider` directly and call `feedForGymProvider(gymId)` inline?
5. Error state copy: should MI GYM and PÚBLICO use the same generic error copy as AMIGOS ("No pudimos cargar tu feed. Intentá de nuevo.") or segment-specific strings?
6. File placement: should `_MiGymBody` and `_PublicoBody` stay inside `feed_screen.dart` (same file as `_AmigosBody`) or be extracted to separate files in `presentation/widgets/`?
7. Do we add `// TODO(pagination)` markers or leave them out entirely?
8. Should the new `myGymFeedProvider` be a `StreamProvider` (for live updates) or `FutureProvider` (consistent with `myFriendsFeedProvider`)? The user profile uses a `StreamProvider` — does the gym feed need live updates?
9. Test coverage: does the team want unit tests for `myGymFeedProvider` logic (gymId null guard) in this PR, or defer to Etapa integration tests?

---

## 12. Out of Scope (HARD constraints)

- `lib/features/feed/data/friendship_repository.dart` — DO NOT TOUCH (Etapa 4 ownership)
- `lib/features/feed/presentation/widgets/post_card.dart` — DO NOT TOUCH (public API only: `Post post`, `VoidCallback? onAuthorTap`)
- `lib/app/router.dart` — DO NOT TOUCH (Etapa 4 adds `/feed/profile/:uid`)
- `onAuthorTap` on `PostCard`: pass `null` or a callback with `// TODO: navigate to /feed/profile/${post.authorUid} — route added in feat/public-profile`
- Pagination implementation
- Likes, comments, reactions
- Post creation (`+` button is stub in header)
- Search icon (stub)
- Any Firestore security rule changes

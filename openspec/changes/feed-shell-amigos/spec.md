# Spec — feed-shell-amigos

**Change**: `feed-shell-amigos`
**Fase / Etapa**: Fase 3 · Etapa 2
**Artifact store**: `openspec`
**TDD**: Strict — tests are written BEFORE each widget/provider in the apply phase.
**Scenario numbering**: continues from SCENARIO-132 (highest after Etapa 1 per explore phase)

---

## Overview

This spec defines verifiable requirements for the Feed shell: the `Post` model amendment (2 new denormalized fields), the `FeedSegment` enum + `feedSegmentProvider`, the derived `myFriendsFeedProvider`, `FeedScreen` (orchestrator), and four presentation widgets (`FeedSegmentPills`, `PostCard`, `PostAvatar`, `FeedEmptyState`).

After this change a logged-in user who navigates to `/feed` sees a fully functional AMIGOS tab: segment pills, `PostCard` list (or empty state or loading indicator), with tap-through to routine detail. MI GYM and PÚBLICO are visually present but disabled.

**Delta only**: this spec does NOT re-describe the existing `Post`, `Friendship`, or repository layer. It only adds or amends what must be true after this change is applied.

Test helper convention (mirrors `test/features/auth/` and existing feed tests):

```dart
Widget _wrap(Widget w) => MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w));

Widget _wrapProvider(Widget w, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w)),
);
```

All provider override tests use `ProviderScope.overrides`. Mocks via `mocktail`.

---

## Requirements

---

### REQ-FEED-POST-001 — Post model gains authorDisplayName and authorAvatarUrl fields

The `Post` freezed class MUST include two new fields:
- `authorDisplayName: String` — required, non-nullable
- `authorAvatarUrl: String?` — optional, nullable

The existing fields (`id`, `authorUid`, `authorGymId?`, `text`, `routineTag?`, `privacy`, `createdAt`) MUST remain unchanged in name, type, and `required`/nullable status. The final field count is 9.

A one-line comment MUST appear in `post.dart` above the two new fields explaining the denormalization trade-off:
> "// Author display fields denormalized at write time (same ADR as authorGymId). Stale-on-update is accepted — standard social-media pattern."

#### Scenarios

**SCENARIO-133** — Roundtrip serialization preserves all 9 fields
- GIVEN a `Post` instance with all 9 fields populated (including `authorDisplayName: 'Tincho'`, `authorAvatarUrl: 'https://example.com/av.jpg'`, non-null `routineTag`, `privacy: PostPrivacy.friends`)
- WHEN `Post.fromJson(post.toJson())` is called
- THEN the result equals the original instance (deep equality via freezed `==`)

**SCENARIO-134** — fromJson resilience: missing authorDisplayName defaults to 'Anónimo'
- GIVEN a JSON map that represents a valid Firestore post document but DOES NOT contain the key `authorDisplayName` (simulating an old doc written before the amendment)
- WHEN `Post.fromJson(map)` is called
- THEN no exception is thrown AND the resulting `Post.authorDisplayName` equals `'Anónimo'`

**SCENARIO-135** — fromJson resilience: null authorAvatarUrl in map → null on model
- GIVEN a JSON map that contains `authorAvatarUrl: null`
- WHEN `Post.fromJson(map)` is called
- THEN `Post.authorAvatarUrl` is null and no exception is thrown

**SCENARIO-136** — fromJson resilience: missing authorAvatarUrl key → null on model
- GIVEN a JSON map that does NOT contain the key `authorAvatarUrl`
- WHEN `Post.fromJson(map)` is called
- THEN `Post.authorAvatarUrl` is null and no exception is thrown

**SCENARIO-137** — All existing Post fixture calls updated to include new required field
- GIVEN the entire test suite runs after the Post model amendment
- WHEN `flutter analyze` is executed
- THEN zero analyzer errors related to missing required named parameter `authorDisplayName` exist in any test file

*Note: SCENARIO-137 is a compile-time gate, not a runtime test. The apply phase MUST update all `Post(...)` constructors in existing test fixtures in the same work-unit commit as the freezed regeneration.*

---

### REQ-FEED-ENUM-001 — FeedSegment enum with 3 values and a default provider

A new file `lib/features/feed/domain/feed_segment.dart` MUST define:

```dart
enum FeedSegment { amigos, gym, public }
```

A new file `lib/features/feed/application/feed_screen_providers.dart` MUST define:

```dart
final feedSegmentProvider = StateProvider<FeedSegment>(
  (ref) => FeedSegment.amigos,
);
```

No other providers may be placed in `feed_screen_providers.dart` at this stage except `feedSegmentProvider` and `myFriendsFeedProvider` (REQ-FEED-PROVIDER-001).

#### Scenarios

**SCENARIO-138** — feedSegmentProvider initial state is FeedSegment.amigos
- GIVEN a fresh `ProviderContainer` with no overrides
- WHEN `container.read(feedSegmentProvider)` is called
- THEN the result is `FeedSegment.amigos`

**SCENARIO-139** — feedSegmentProvider state can be updated
- GIVEN a `ProviderContainer`
- WHEN `container.read(feedSegmentProvider.notifier).state = FeedSegment.gym` is called
- THEN `container.read(feedSegmentProvider)` returns `FeedSegment.gym`

---

### REQ-FEED-PROVIDER-001 — myFriendsFeedProvider composes auth → friends → posts correctly

`myFriendsFeedProvider` MUST be a plain `FutureProvider<List<Post>>` (no family) defined in `lib/features/feed/application/feed_screen_providers.dart`. It MUST NOT be defined in `post_providers.dart` or `friendship_providers.dart`. Internally it MUST compose the chain: `authStateChangesProvider` → `acceptedFriendsProvider(uid)` → `feedForFriendsProvider(friendUids)`.

The existing providers `post_providers.dart` and `friendship_providers.dart` MUST NOT be modified.

#### Scenarios

**SCENARIO-140** — Provider returns posts when user is authenticated and has friends with posts
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(MockUser(uid: 'u1'))`
- AND `acceptedFriendsProvider('u1')` overridden to return `['u2', 'u3']`
- AND `feedForFriendsProvider(['u2', 'u3'])` overridden to return a list of 5 `Post` objects
- WHEN `container.read(myFriendsFeedProvider.future)` is awaited
- THEN the result is a `List<Post>` of length 5 matching the overridden posts

**SCENARIO-141** — Provider returns empty list when user has no friends
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(MockUser(uid: 'u1'))`
- AND `acceptedFriendsProvider('u1')` overridden to return `[]`
- WHEN `container.read(myFriendsFeedProvider.future)` is awaited
- THEN the result is an empty `List<Post>` (length 0) and no exception is thrown

*Implementation note: the design phase MAY choose to short-circuit (skip calling `feedForFriendsProvider` when friends list is empty) or pass the empty list through. Either is acceptable — the observable contract is an empty result with no crash.*

**SCENARIO-142** — Provider returns empty list when user is unauthenticated
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(null)` (null user)
- WHEN `container.read(myFriendsFeedProvider.future)` is awaited
- THEN the result is an empty `List<Post>` (length 0) and no exception is thrown

**SCENARIO-143** — Provider does not trigger infinite rebuild from List equality
- GIVEN `myFriendsFeedProvider` is watched in a `ProviderContainer`
- WHEN the container is rebuilt multiple times (e.g. parent provider notifies)
- THEN no new provider instance is created on each rebuild; `feedForFriendsProvider` is not called with a new `List<String>` instance per tick
- *This is verified structurally: `myFriendsFeedProvider` is a plain `FutureProvider` (not a family), so `List<String>` equality is never used as a cache key.*

---

### REQ-FEED-SCREEN-001 — FeedScreen is a ConsumerWidget that composes header, pills, and segment body

`FeedScreen` MUST be a `ConsumerWidget`. Its `build` method MUST:
1. Read `feedSegmentProvider` exactly once via `ref.watch`
2. Render a `FeedHeader` row inline (title + action icons)
3. Render a `FeedSegmentPills` widget
4. Render an `Expanded` segment body that switches on the current `FeedSegment` value

`FeedScreen` MUST NOT introduce a `Scaffold`, `AppBackground`, or `SafeArea` — the shell route already applies them.

#### Scenarios

**SCENARIO-144** — FeedScreen renders header title "FEED"
- GIVEN `feedSegmentProvider` and `myFriendsFeedProvider` overridden (any valid values)
- WHEN `FeedScreen` is pumped inside `_wrapProvider(...)`
- THEN `find.text('FEED')` finds exactly one widget

**SCENARIO-145** — FeedScreen renders search and plus icon buttons
- GIVEN same pump as SCENARIO-144
- WHEN the widget tree is inspected
- THEN `find.byIcon(TreinoIcon.search)` finds at least one widget AND `find.byIcon(TreinoIcon.plus)` finds at least one widget

**SCENARIO-146** — FeedScreen renders FeedSegmentPills exactly once
- GIVEN same pump as SCENARIO-144
- WHEN the widget tree is inspected
- THEN `find.byType(FeedSegmentPills)` finds exactly one widget

**SCENARIO-147** — FeedScreen does not introduce Scaffold, AppBackground, or SafeArea
- GIVEN `FeedScreen` pumped inside `MaterialApp(home: Scaffold(body: FeedScreen()))` (plain wrapper, not shell)
- WHEN the widget tree is inspected
- THEN `find.byType(Scaffold)` finds exactly one (the outer test wrapper) AND `find.byType(AppBackground)` finds zero AND `find.byType(SafeArea)` finds zero inside FeedScreen's own subtree

**SCENARIO-148** — FeedScreen in gym segment renders SizedBox.shrink (unreachable from UI but safe)
- GIVEN `feedSegmentProvider` overridden to `FeedSegment.gym`
- AND `myFriendsFeedProvider` overridden with `AsyncData([])`
- WHEN `FeedScreen` is pumped
- THEN no exception is thrown AND no `PostCard` or `FeedEmptyState` is rendered

**SCENARIO-149** — FeedScreen in public segment renders SizedBox.shrink (unreachable from UI but safe)
- GIVEN `feedSegmentProvider` overridden to `FeedSegment.public`
- AND `myFriendsFeedProvider` overridden with `AsyncData([])`
- WHEN `FeedScreen` is pumped
- THEN no exception is thrown AND no `PostCard` or `FeedEmptyState` is rendered

---

### REQ-FEED-SCREEN-002 — FeedScreen AMIGOS segment — data state with posts

When the active segment is `FeedSegment.amigos` and `myFriendsFeedProvider` emits `AsyncData` with a non-empty list, `FeedScreen` MUST render a scrollable `ListView` with exactly one `PostCard` per post in the list, in the same order.

#### Scenarios

**SCENARIO-150** — AMIGOS data state: list of PostCards rendered in order
- GIVEN `feedSegmentProvider` overridden to `FeedSegment.amigos`
- AND `myFriendsFeedProvider` overridden with `AsyncData([post1, post2, post3])` (3 distinct posts)
- WHEN `FeedScreen` is pumped
- THEN `find.byType(PostCard)` finds exactly 3 widgets AND the order matches `[post1, post2, post3]` (first PostCard's post equals `post1`, etc.)

**SCENARIO-151** — AMIGOS data state: no FeedEmptyState when posts are present
- GIVEN same overrides as SCENARIO-150
- WHEN the widget tree is inspected
- THEN `find.byType(FeedEmptyState)` finds zero widgets

**SCENARIO-152** — AMIGOS data state: no CircularProgressIndicator when data is resolved
- GIVEN same overrides as SCENARIO-150
- WHEN the widget tree is inspected
- THEN `find.byType(CircularProgressIndicator)` finds zero widgets

---

### REQ-FEED-SCREEN-003 — FeedScreen AMIGOS segment — empty data state

When `myFriendsFeedProvider` emits `AsyncData([])` (empty list), `FeedScreen` MUST render `FeedEmptyState` and MUST NOT render any `PostCard`.

#### Scenarios

**SCENARIO-153** — AMIGOS empty state: FeedEmptyState rendered
- GIVEN `feedSegmentProvider` overridden to `FeedSegment.amigos`
- AND `myFriendsFeedProvider` overridden with `AsyncData<List<Post>>([])`
- WHEN `FeedScreen` is pumped
- THEN `find.byType(FeedEmptyState)` finds exactly one widget

**SCENARIO-154** — AMIGOS empty state: no PostCard rendered
- GIVEN same overrides as SCENARIO-153
- WHEN the widget tree is inspected
- THEN `find.byType(PostCard)` finds zero widgets

---

### REQ-FEED-SCREEN-004 — FeedScreen AMIGOS segment — loading state

When `myFriendsFeedProvider` is `AsyncLoading`, `FeedScreen` MUST render a centered `CircularProgressIndicator` with color `palette.accent` and MUST NOT render any `PostCard` or `FeedEmptyState`.

#### Scenarios

**SCENARIO-155** — AMIGOS loading state: spinner rendered
- GIVEN `feedSegmentProvider` overridden to `FeedSegment.amigos`
- AND `myFriendsFeedProvider` overridden with `AsyncLoading<List<Post>>()`
- WHEN `FeedScreen` is pumped (single `pump()`, no `pumpAndSettle`)
- THEN `find.byType(CircularProgressIndicator)` finds exactly one widget

**SCENARIO-156** — AMIGOS loading state: no PostCard or FeedEmptyState
- GIVEN same overrides as SCENARIO-155
- WHEN the widget tree is inspected
- THEN `find.byType(PostCard)` finds zero widgets AND `find.byType(FeedEmptyState)` finds zero widgets

---

### REQ-FEED-SCREEN-005 — FeedScreen AMIGOS segment — error state

When `myFriendsFeedProvider` is `AsyncError`, `FeedScreen` MUST render a graceful error message and MUST NOT propagate the exception or crash.

The error copy MUST be: `"No pudimos cargar tu feed. Intentá de nuevo."` styled with `palette.textMuted`.

#### Scenarios

**SCENARIO-157** — AMIGOS error state: graceful fallback rendered, no FlutterError
- GIVEN `feedSegmentProvider` overridden to `FeedSegment.amigos`
- AND `myFriendsFeedProvider` overridden with `AsyncError<List<Post>>(Exception('net'), StackTrace.empty)`
- WHEN `FeedScreen` is pumped
- THEN no `FlutterError` is reported AND `find.text('No pudimos cargar tu feed. Intentá de nuevo.')` finds one widget

**SCENARIO-158** — AMIGOS error state: no PostCard or FeedEmptyState
- GIVEN same overrides as SCENARIO-157
- WHEN the widget tree is inspected
- THEN `find.byType(PostCard)` finds zero widgets AND `find.byType(FeedEmptyState)` finds zero widgets

---

### REQ-FEED-PILLS-001 — FeedSegmentPills renders 3 pills in correct order

`FeedSegmentPills` MUST render exactly 3 pill labels in this order: `'AMIGOS'`, `'MI GYM'`, `'PÚBLICO'`. Labels MUST be uppercase. The widget reads `feedSegmentProvider` to determine which pill is active.

#### Scenarios

**SCENARIO-159** — Three pills rendered in correct order
- GIVEN `feedSegmentProvider` overridden to any value
- WHEN `FeedSegmentPills` is pumped inside `_wrapProvider(...)`
- THEN `find.text('AMIGOS')` finds one widget AND `find.text('MI GYM')` finds one widget AND `find.text('PÚBLICO')` finds one widget
- AND the render order (left to right) is AMIGOS → MI GYM → PÚBLICO

---

### REQ-FEED-PILLS-002 — FeedSegmentPills active pill style uses accent fill

The pill whose label matches the current `feedSegmentProvider` state MUST be rendered with background color `palette.accent` and text color `palette.bg`. Inactive pills MUST use `palette.bgCard` background and `palette.textMuted` text color.

#### Scenarios

**SCENARIO-160** — Active pill (AMIGOS) has accent background decoration
- GIVEN `feedSegmentProvider` overridden to `FeedSegment.amigos`
- WHEN `FeedSegmentPills` is pumped
- THEN the `Container` or `DecoratedBox` backing the AMIGOS pill has `color == palette.accent`
- AND the `Container` or `DecoratedBox` backing the MI GYM pill has `color == palette.bgCard`

---

### REQ-FEED-PILLS-003 — MI GYM and PÚBLICO pills are visually disabled

MI GYM and PÚBLICO pills MUST be rendered with `Opacity(opacity: 0.4)` applied to their widget subtree (or equivalent). This communicates their disabled state without removing them from the layout.

#### Scenarios

**SCENARIO-161** — MI GYM pill has opacity 0.4
- GIVEN `FeedSegmentPills` is pumped with any `feedSegmentProvider` state
- WHEN the widget subtree containing the MI GYM pill label is inspected
- THEN an `Opacity` widget with `opacity == 0.4` wraps it (or an `AnimatedOpacity`/`Opacity` ancestor with that value is present)

**SCENARIO-162** — PÚBLICO pill has opacity 0.4
- GIVEN same pump as SCENARIO-161
- THEN an `Opacity` widget with `opacity == 0.4` wraps the PÚBLICO pill subtree

---

### REQ-FEED-PILLS-004 — Only AMIGOS pill is tappable; MI GYM and PÚBLICO are no-ops

Tapping the AMIGOS pill MUST update `feedSegmentProvider` to `FeedSegment.amigos` (when it was not already active). Tapping MI GYM or PÚBLICO MUST NOT change `feedSegmentProvider` state.

#### Scenarios

**SCENARIO-163** — Tapping AMIGOS when active: no state change, no error
- GIVEN `feedSegmentProvider` overridden to `FeedSegment.amigos`
- WHEN `tester.tap(find.text('AMIGOS'))` and `pumpAndSettle()` are called
- THEN `feedSegmentProvider` state remains `FeedSegment.amigos` and no exception is thrown

**SCENARIO-164** — Tapping MI GYM: feedSegmentProvider state unchanged
- GIVEN `feedSegmentProvider` overridden to `FeedSegment.amigos`
- WHEN `tester.tap(find.text('MI GYM'))` and `pumpAndSettle()` are called
- THEN `feedSegmentProvider` state is still `FeedSegment.amigos`

**SCENARIO-165** — Tapping PÚBLICO: feedSegmentProvider state unchanged
- GIVEN `feedSegmentProvider` overridden to `FeedSegment.amigos`
- WHEN `tester.tap(find.text('PÚBLICO'))` and `pumpAndSettle()` are called
- THEN `feedSegmentProvider` state is still `FeedSegment.amigos`

---

### REQ-FEED-POSTCARD-001 — PostCard renders author name, gym info, and timestamp

`PostCard` MUST render:
- The value of `post.authorDisplayName` as visible text
- A relative timestamp string (e.g. `'Hace 2h'`) derived from `post.createdAt`
- The value of `post.authorGymId` as a gym identifier (displayed as uppercased gym ID or a formatted label — design determines exact format; spec requires the value is present and non-empty when `authorGymId != null`)

#### Scenarios

**SCENARIO-166** — Author display name is rendered
- GIVEN `PostCard(post: post)` where `post.authorDisplayName == 'Tincho'`
- WHEN pumped inside `_wrap(...)`
- THEN `find.text('Tincho')` finds exactly one widget

**SCENARIO-167** — Gym ID is rendered when non-null
- GIVEN `PostCard(post: post)` where `post.authorGymId == 'gym-la-fuerza'`
- WHEN pumped
- THEN a text widget containing `'gym-la-fuerza'` (case-insensitive match) or a formatted equivalent is found in the tree AND it is non-empty

**SCENARIO-168** — Timestamp is rendered as relative string
- GIVEN `PostCard(post: post)` where `post.createdAt` is 2 hours before `DateTime.now()`
- WHEN pumped
- THEN a text widget with text matching `RegExp(r'[Hh]ace\s+\d+\s*h')` or similar relative-time format is found

---

### REQ-FEED-POSTCARD-002 — PostCard renders post body text

`PostCard` MUST render the value of `post.text` as visible text content in the card body.

#### Scenarios

**SCENARIO-169** — Body text is rendered
- GIVEN `PostCard(post: post)` where `post.text == 'Gran sesión hoy'`
- WHEN pumped
- THEN `find.text('Gran sesión hoy')` finds exactly one widget

---

### REQ-FEED-POSTCARD-003 — PostCard renders RoutineTag chip when routineTag is non-null

When `post.routineTag != null`, `PostCard` MUST render a tappable chip that displays `routineTag.routineName`. Tapping the chip MUST navigate via `context.push('/workout/routine/${routineTag.routineId}')`.

When `post.routineTag == null`, no chip widget of any kind MUST be rendered.

#### Scenarios

**SCENARIO-170** — Routine tag chip rendered when routineTag is present
- GIVEN `PostCard(post: post)` where `post.routineTag == RoutineTag(routineId: 'r1', routineName: 'Push · Día 4')`
- WHEN pumped inside a navigable `_wrap(...)`
- THEN `find.text('Push · Día 4')` finds exactly one widget AND a tappable widget wrapping that text is present in the tree

**SCENARIO-171** — Tapping routine tag chip navigates to /workout/routine/:id
- GIVEN same pump as SCENARIO-170 with a `GoRouter` or `MockNavigator` that captures `push` calls
- WHEN `tester.tap(find.text('Push · Día 4'))` and `pumpAndSettle()` are called
- THEN the captured route is `'/workout/routine/r1'` (pushed, not replaced)

**SCENARIO-172** — No chip rendered when routineTag is null
- GIVEN `PostCard(post: post)` where `post.routineTag == null`
- WHEN pumped
- THEN `find.byType(RoutineTagChip)` (or whatever chip widget is used) finds zero widgets AND no text matching the routine name pattern is found

---

### REQ-FEED-POSTCARD-004 — PostCard renders stats stub row

`PostCard` MUST render a stats row as a placeholder for Fase 4 real data. The row MUST contain at minimum three stub values styled in `palette.textMuted`. The stub values MUST use em-dashes (`—`) rather than `0` to avoid misleading testers.

The stats row MUST include a code comment: `// Stub: real stats wired in Fase 4.`

#### Scenarios

**SCENARIO-173** — Stats row is present in card
- GIVEN `PostCard(post: post)` with any valid post
- WHEN pumped
- THEN the card contains a `Row` widget in the lower section containing text with `'—'` characters (at least one such text widget)

**SCENARIO-174** — Stats row contains no real numeric data
- GIVEN same pump as SCENARIO-173
- WHEN the stats row area is inspected
- THEN no text widget with text matching `RegExp(r'\d+ kg|\d+ min|\d+ ej')` is found (confirming stubs only)

---

### REQ-FEED-POSTCARD-005 — PostCard uses bgCard fill, r-lg radius, 1px border, padding 18

`PostCard`'s outermost container MUST have:
- Background color `palette.bgCard`
- Border radius `BorderRadius.circular(20)` (r-lg)
- A 1px border using `palette.border`
- Internal padding `EdgeInsets.all(18)`

No HEX literal color constants appear in the `post_card.dart` source file.

#### Scenarios

**SCENARIO-175** — Card container decoration is correct
- GIVEN `PostCard(post: post)` is pumped inside `_wrap(...)`
- WHEN the outermost `Container` or `DecoratedBox` is inspected
- THEN `decoration.borderRadius` equals `BorderRadius.circular(20)` AND `decoration.color` equals `AppPalette.mintMagenta.bgCard` AND `decoration.border` is non-null (1px solid `palette.border`)

---

### REQ-FEED-POSTCARD-006 — PostCard overflow button is a no-op stub

`PostCard` MUST render a `TreinoIcon.dotsThree` icon button in the top-right corner of the header row. Tapping it MUST NOT navigate, open a bottom sheet, or throw an exception (it is an explicit stub for Etapa 5).

#### Scenarios

**SCENARIO-176** — dotsThree icon is present in card
- GIVEN `PostCard(post: post)` is pumped
- WHEN the widget tree is inspected
- THEN `find.byIcon(TreinoIcon.dotsThree)` finds exactly one widget

**SCENARIO-177** — Tapping dotsThree does nothing
- GIVEN same pump as SCENARIO-176
- WHEN `tester.tap(find.byIcon(TreinoIcon.dotsThree))` and `pumpAndSettle()` are called
- THEN no exception is thrown AND the widget tree is unchanged (no new routes, no overlays)

---

### REQ-FEED-POSTCARD-007 — PostCard author tap is a no-op in Etapa 2

`PostCard` MUST accept an optional `VoidCallback? onAuthorTap` constructor parameter (default null). Tapping the avatar or author name area MUST invoke `onAuthorTap` if non-null, or be a no-op if null. In Etapa 2, `FeedScreen` passes null. No navigation to any profile route may occur.

#### Scenarios

**SCENARIO-178** — Author tap no-op when onAuthorTap is null
- GIVEN `PostCard(post: post, onAuthorTap: null)` is pumped
- WHEN `tester.tap(find.text(post.authorDisplayName))` and `pumpAndSettle()` are called
- THEN no exception is thrown AND no navigation occurs

**SCENARIO-179** — onAuthorTap callback fires when provided
- GIVEN `PostCard(post: post, onAuthorTap: () => tapped = true)` is pumped
- WHEN the avatar or author name area is tapped
- THEN `tapped` is `true`

---

### REQ-FEED-AVATAR-001 — PostAvatar renders CachedNetworkImage when authorAvatarUrl is non-null

`PostAvatar` MUST be a standalone `StatelessWidget` in `lib/features/feed/presentation/widgets/post_avatar.dart`. When `authorAvatarUrl` is non-null, it MUST render a `CachedNetworkImage` clipped to a circle of diameter 40. It MUST NOT use `Image.network` directly.

#### Scenarios

**SCENARIO-180** — CachedNetworkImage rendered when URL is present
- GIVEN `PostAvatar(authorAvatarUrl: 'https://example.com/av.jpg', authorDisplayName: 'Tincho', size: 40)` is pumped
- WHEN the widget tree is inspected
- THEN `find.byType(CachedNetworkImage)` finds at least one widget AND no direct `Image.network` widget is found at the avatar subtree root

---

### REQ-FEED-AVATAR-002 — PostAvatar renders initials fallback when authorAvatarUrl is null

When `authorAvatarUrl` is null, `PostAvatar` MUST render a circular widget with:
- Background: gradient from `palette.accent` to `palette.highlight`
- Content: a single uppercase character — the first letter of `authorDisplayName` when `displayName` is non-null, non-empty, and not equal to `'Anónimo'`; `'?'` otherwise

#### Scenarios

**SCENARIO-181** — Initials fallback renders first letter of displayName
- GIVEN `PostAvatar(authorAvatarUrl: null, authorDisplayName: 'Tincho', size: 40)` is pumped
- WHEN inspected
- THEN `find.text('T')` finds one widget AND `find.byType(CachedNetworkImage)` finds zero widgets

**SCENARIO-182** — Initials fallback shows '?' for 'Anónimo'
- GIVEN `PostAvatar(authorAvatarUrl: null, authorDisplayName: 'Anónimo', size: 40)` is pumped
- WHEN inspected
- THEN `find.text('?')` finds one widget

**SCENARIO-183** — Initials fallback shows '?' for empty displayName
- GIVEN `PostAvatar(authorAvatarUrl: null, authorDisplayName: '', size: 40)` is pumped
- WHEN inspected
- THEN `find.text('?')` finds one widget

**SCENARIO-184** — Initials fallback uses accent→highlight gradient
- GIVEN `PostAvatar(authorAvatarUrl: null, authorDisplayName: 'Tincho', size: 40)` is pumped
- WHEN the outermost circular container is inspected
- THEN its decoration contains a `LinearGradient` (or `RadialGradient`) whose colors list includes `palette.accent` and `palette.highlight`

---

### REQ-FEED-EMPTY-001 — FeedEmptyState renders icon and message in textMuted

`FeedEmptyState` MUST be a `StatelessWidget` in `lib/features/feed/presentation/widgets/feed_empty_state.dart`. It MUST render:
- The text `'Aún no hay posts de tus amigos'` (exact copy)
- An icon (any semantically appropriate `TreinoIcon` constant — design picks `TreinoIcon.users` as default)
- Both icon and text styled with `palette.textMuted`
- The layout MUST be centered (both axes) within available space

No HEX literal color constants appear in `feed_empty_state.dart`.

#### Scenarios

**SCENARIO-185** — Empty state renders correct copy
- GIVEN `FeedEmptyState()` is pumped inside `_wrap(...)`
- WHEN the widget tree is inspected
- THEN `find.text('Aún no hay posts de tus amigos')` finds exactly one widget

**SCENARIO-186** — Empty state renders an icon
- GIVEN same pump as SCENARIO-185
- WHEN the widget tree is inspected
- THEN `find.byType(Icon)` finds at least one widget

**SCENARIO-187** — Empty state has no PostCard or CircularProgressIndicator
- GIVEN same pump as SCENARIO-185
- WHEN the widget tree is inspected
- THEN `find.byType(PostCard)` finds zero AND `find.byType(CircularProgressIndicator)` finds zero

---

### REQ-FEED-ICON-001 — TreinoIcon gains dotsThree and verified constants

`lib/core/widgets/treino_icon.dart` MUST define two new constants:
- `TreinoIcon.dotsThree` — mapped to `PhosphorIconsRegular.dotsThreeVertical` (or equivalent phosphor regular variant)
- `TreinoIcon.verified` — mapped to `PhosphorIconsFill.sealCheck`

No `PhosphorIcons.*` direct usage appears in any new feed widget file.

#### Scenarios

**SCENARIO-188** — TreinoIcon.dotsThree is a valid IconData
- GIVEN the constant `TreinoIcon.dotsThree` is referenced
- WHEN `Icon(TreinoIcon.dotsThree)` is pumped
- THEN no exception is thrown

**SCENARIO-189** — TreinoIcon.verified is a valid IconData
- GIVEN the constant `TreinoIcon.verified` is referenced
- WHEN `Icon(TreinoIcon.verified)` is pumped
- THEN no exception is thrown

---

### REQ-FEED-SEED-001 — seed_posts.js includes authorDisplayName and authorAvatarUrl

`scripts/seed_posts.js` MUST be updated so that every seed post document includes:
- `authorDisplayName` — a realistic human name string (non-empty)
- `authorAvatarUrl` — either a valid URL string or `null` (some posts may omit the avatar)

Running the seed script fresh MUST result in Firestore post documents where `PostCard` can display real author names (no `'Anónimo'` fallback triggered under normal conditions).

*This REQ has no automated Flutter test scenario — it is verified during smoke test (success criterion #13 in the proposal). The apply phase MUST update the seed script in the same work-unit commit as the Post model amendment.*

---

## Constraint Summary

| Constraint | Enforced by |
|---|---|
| No `Scaffold` / `AppBackground` / `SafeArea` in `FeedScreen` | REQ-FEED-SCREEN-001 (SCENARIO-147) |
| No HEX literals in any new feed file | REQ-FEED-POSTCARD-005, REQ-FEED-EMPTY-001 (source-level grep before merge) |
| No `PhosphorIcons.*` direct usage in new files | REQ-FEED-ICON-001 (scenarios use `TreinoIcon` constants only) |
| `CachedNetworkImage` for avatar, never `Image.network` | REQ-FEED-AVATAR-001 (SCENARIO-180) |
| Spacing only in `{8, 12, 14, 18, 20}` | Design review gate — grep for `16` and `24` literals in new files |
| Radii: cards r-lg=20, pills r-full=9999 | REQ-FEED-POSTCARD-005 (SCENARIO-175) + design review |
| `myFriendsFeedProvider` in `feed_screen_providers.dart` only | REQ-FEED-PROVIDER-001 (file location) |
| Existing `post_providers.dart` + `friendship_providers.dart` NOT modified | REQ-FEED-PROVIDER-001 (file immutability) |
| Stats row as stub with `—`, not `0` | REQ-FEED-POSTCARD-004 (SCENARIO-173, SCENARIO-174) |
| `onAuthorTap` null by default — no profile navigation in Etapa 2 | REQ-FEED-POSTCARD-007 (SCENARIO-178) |
| `Post.fromJson` defaults missing `authorDisplayName` to `'Anónimo'` | REQ-FEED-POST-001 (SCENARIO-134) |
| All 418 pre-existing tests remain green after Post model amendment | REQ-FEED-POST-001 (SCENARIO-137) |
| TDD order: test file BEFORE production widget in every work-unit commit | Enforced by tasks phase |

---

## Files this spec covers

| File | REQs |
|---|---|
| `lib/features/feed/domain/post.dart` | POST-001 |
| `lib/features/feed/domain/feed_segment.dart` (new) | ENUM-001 |
| `lib/features/feed/application/feed_screen_providers.dart` (new) | ENUM-001, PROVIDER-001 |
| `lib/features/feed/feed_screen.dart` | SCREEN-001..005 |
| `lib/features/feed/presentation/widgets/feed_segment_pills.dart` (new) | PILLS-001..004 |
| `lib/features/feed/presentation/widgets/post_card.dart` (new) | POSTCARD-001..007 |
| `lib/features/feed/presentation/widgets/post_avatar.dart` (new) | AVATAR-001..002 |
| `lib/features/feed/presentation/widgets/feed_empty_state.dart` (new) | EMPTY-001 |
| `lib/core/widgets/treino_icon.dart` | ICON-001 |
| `scripts/seed_posts.js` | SEED-001 |
| `test/features/feed/domain/post_test.dart` (updated) | POST-001 (SCENARIO-133..137) |
| `test/features/feed/application/feed_screen_providers_test.dart` (new) | ENUM-001, PROVIDER-001 (SCENARIO-138..143) |
| `test/features/feed/presentation/feed_screen_test.dart` (new) | SCREEN-001..005 (SCENARIO-144..158) |
| `test/features/feed/presentation/widgets/feed_segment_pills_test.dart` (new) | PILLS-001..004 (SCENARIO-159..165) |
| `test/features/feed/presentation/widgets/post_card_test.dart` (new) | POSTCARD-001..007 (SCENARIO-166..179) |
| `test/features/feed/presentation/widgets/post_avatar_test.dart` (new) | AVATAR-001..002 (SCENARIO-180..184) |
| `test/features/feed/presentation/widgets/feed_empty_state_test.dart` (new) | EMPTY-001 (SCENARIO-185..187) |
| `test/features/feed/core/treino_icon_test.dart` (updated or new) | ICON-001 (SCENARIO-188..189) |

---

## Out of scope (explicit)

The following items are NOT requirements for this change. They MUST NOT appear in the apply phase.

- MI GYM or PÚBLICO segment functional content (Etapa 3)
- Pull-to-refresh / `ref.invalidate` wiring (Etapa 3+)
- Author profile navigation via `/profile/:uid` (Etapa 4)
- Real stats data (Fase 4) — stats row MUST remain a stub
- Muscle group label from `Post` (Fase 4 — `Post` has no such field)
- Post likes, comments, or reactions (Fase 3.5)
- Skeleton loading shimmer (post-MVP polish)
- `/feed/search` and `/feed/create` routes (Etapa 5)
- `users_public` Firestore collection (decision A chose denormalization instead)
- Any change to `firestore.rules`
- Any change to `lib/features/workout/`, `lib/features/home/`, `lib/features/auth/`, `lib/features/profile/`, `lib/features/coach/`

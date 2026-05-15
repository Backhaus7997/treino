# Design: Feed Segments — MI GYM + PÚBLICO (Etapa 3)

## TL;DR

Mirror `_AmigosBody` to add `_MiGymBody` and `_PublicoBody` inside `feed_screen.dart`. Wrap `feedForGymProvider` with a new `myGymFeedProvider` (`FutureProvider<List<Post>?>`) where `null` = "no gym" and `[]` = "gym, no posts" — single signal, no parallel boolean. Parameterize `FeedEmptyState` additively with `message` (required) + `icon` (default `TreinoIcon.users`). Wire MI GYM and PÚBLICO `_Pill`s by removing `const` and binding to `feedSegmentProvider`. Defer pagination behind `// TODO(pagination)`. Pass an `onAuthorTap` callback that targets `/feed/profile/${uid}` with a `// TODO: route added in feat/public-profile (Etapa 4)` comment — `PostCard` and `router.dart` are NOT touched.

- 4 files modified, 0 created (1 test file added in tasks phase, not a `lib/` artifact)
- 8 ADRs
- Pattern preserved: per-segment `ConsumerWidget` body (Approach B from explore §6)

---

## 1. File Map

Order matters for Strict TDD: tests first, then impl, then call-site rewires.

| # | Path | Change | Reason |
|---|---|---|---|
| 1 | `test/features/feed/application/my_gym_feed_provider_test.dart` | **CREATE** (test) | TDD: lock the null-gym branch BEFORE provider exists. Drives `FutureProvider<List<Post>?>` shape. |
| 2 | `lib/features/feed/application/feed_screen_providers.dart` | MODIFY | Add `myGymFeedProvider` wrapper (after `myFriendsFeedProvider`). Imports `userProfileProvider` and `feedForGymProvider`. |
| 3 | `lib/features/feed/presentation/widgets/feed_empty_state.dart` | MODIFY | Replace `_kCopy` constant with required `message` param + optional `icon` (default `TreinoIcon.users`). |
| 4 | `lib/features/feed/feed_screen.dart` | MODIFY | (a) Update existing `_AmigosBody` to pass explicit `message` to `FeedEmptyState`. (b) Add `_MiGymBody` + `_PublicoBody`. (c) Replace `SizedBox.shrink()` switch arm with two arms. |
| 5 | `lib/features/feed/presentation/widgets/feed_segment_pills.dart` | MODIFY | Remove `const` from MI GYM + PÚBLICO `_Pill`s; wire `isActive` and `onTap` to `feedSegmentProvider` (mirroring AMIGOS). |

**Rationale for ordering**: changes 2 and 3 are pure additive infrastructure that downstream changes consume. Change 4 depends on 2 + 3. Change 5 is independent of 2/3/4 but is best applied last because it makes the segments user-reachable — premature wiring before bodies exist would crash on tap.

### Hard Constraints (NOT modified — verified in proposal §Out of Scope)

| Path | Why |
|---|---|
| `lib/features/feed/data/friendship_repository.dart` | Etapa 4 ownership |
| `lib/features/feed/presentation/widgets/post_card.dart` | Public API only (`Post`, `VoidCallback? onAuthorTap`) |
| `lib/app/router.dart` | Etapa 4 adds `/feed/profile/:uid` |

---

## 2. API Signatures

### 2.1 `myGymFeedProvider` (NEW in `feed_screen_providers.dart`)

```dart
/// Posts from the current user's gym.
///
/// Returns:
/// - `null`  → user has no `gymId` (not assigned to a gym)
/// - `[]`    → user has a gym, gym has no posts
/// - `[...]` → user has a gym with posts
///
/// Loading and error states are surfaced via the AsyncValue wrapper.
final myGymFeedProvider = FutureProvider<List<Post>?>((ref) async {
  final profile = await ref.watch(userProfileProvider.future);
  final gymId = profile?.gymId;
  if (gymId == null) return null;
  return ref.watch(feedForGymProvider(gymId).future);
});
```

**Imports added** to `feed_screen_providers.dart`:
```dart
import '../../profile/application/user_providers.dart';
```
`feedForGymProvider` is already importable via `post_providers.dart` (already imported).

**`.future` semantics check**: `userProfileProvider` is `StreamProvider<UserProfile?>`; `.future` resolves on the first non-loading emission. `userProfileProvider`'s implementation returns `Stream.empty()` while auth is loading, then `Stream.value(null)` if no user, then a real stream once authenticated — so `.future` will block until auth resolves AND the profile repo emits at least once. This is desired: the wrapper does not race against unresolved auth.

### 2.2 `FeedEmptyState` modified constructor

**Before:**
```dart
class FeedEmptyState extends StatelessWidget {
  const FeedEmptyState({super.key});
  static const _kCopy = 'Aún no hay posts de tus amigos';
  // ...
}
```

**After:**
```dart
class FeedEmptyState extends StatelessWidget {
  const FeedEmptyState({
    super.key,
    required this.message,
    this.icon = TreinoIcon.users,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: palette.textMuted),
          const SizedBox(height: 12),
          Text(
            message,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: palette.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
```

`_kCopy` is deleted. `_AmigosBody` (the only existing caller) is updated in the same change to pass `message: 'Aún no hay posts de tus amigos'` — visual parity preserved.

**Backwards-compat note**: this is a **breaking** change for any caller using `const FeedEmptyState()`. Codebase has exactly one such caller (`_AmigosBody`); updated atomically in the same PR.

### 2.3 `_MiGymBody` (NEW `ConsumerWidget` in `feed_screen.dart`)

```dart
class _MiGymBody extends ConsumerWidget {
  const _MiGymBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final asyncPosts = ref.watch(myGymFeedProvider);

    return asyncPosts.when(
      data: (posts) {
        if (posts == null) {
          return const FeedEmptyState(message: 'Todavía no estás en un gym');
        }
        if (posts.isEmpty) {
          return const FeedEmptyState(message: 'Tu gym todavía no tiene posts');
        }
        return ListView.separated(
          // TODO(pagination): cursor-based pagination deferred (see explore §9)
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) => PostCard(
            post: posts[i],
            // TODO: navigate to /feed/profile/${posts[i].authorUid}
            //       — route added in feat/public-profile (Etapa 4)
            onAuthorTap: () {},
          ),
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No pudimos cargar tu feed. Intentá de nuevo.',
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
```

**Note on `onAuthorTap`**: per ADR-005, we pass a no-op closure with a TODO comment instead of `null`. This avoids touching `PostCard` (CONSTRAINT) and surfaces the integration point clearly for Etapa 4.

### 2.4 `_PublicoBody` (NEW `ConsumerWidget` in `feed_screen.dart`)

```dart
class _PublicoBody extends ConsumerWidget {
  const _PublicoBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final asyncPosts = ref.watch(feedPublicProvider);

    return asyncPosts.when(
      data: (posts) {
        if (posts.isEmpty) {
          return const FeedEmptyState(message: 'Aún no hay posts públicos');
        }
        return ListView.separated(
          // TODO(pagination): cursor-based pagination deferred (see explore §9)
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) => PostCard(
            post: posts[i],
            // TODO: navigate to /feed/profile/${posts[i].authorUid}
            //       — route added in feat/public-profile (Etapa 4)
            onAuthorTap: () {},
          ),
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No pudimos cargar tu feed. Intentá de nuevo.',
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
```

**Imports added** to `feed_screen.dart`:
```dart
import 'application/post_providers.dart' show feedPublicProvider;
```
(`myGymFeedProvider` comes from the already-imported `feed_screen_providers.dart`.)

### 2.5 `feed_screen.dart` switch (line 28–31, current) — replacement

**Before:**
```dart
Expanded(
  child: switch (segment) {
    FeedSegment.amigos => const _AmigosBody(),
    FeedSegment.gym || FeedSegment.public => const SizedBox.shrink(),
  },
),
```

**After:**
```dart
Expanded(
  child: switch (segment) {
    FeedSegment.amigos => const _AmigosBody(),
    FeedSegment.gym    => const _MiGymBody(),
    FeedSegment.public => const _PublicoBody(),
  },
),
```

Switch is exhaustive — Dart analyzer enforces it.

### 2.6 `_AmigosBody` `FeedEmptyState` call (line 87, current)

**Before:**
```dart
return const FeedEmptyState();
```

**After:**
```dart
return const FeedEmptyState(message: 'Aún no hay posts de tus amigos');
```

### 2.7 `feed_segment_pills.dart` `_Pill` rewires (lines 29–39, current)

**Before:**
```dart
const _Pill(
  label: 'MI GYM',
  isActive: false,
  onTap: null,
),
const SizedBox(width: 12),
const _Pill(
  label: 'PÚBLICO',
  isActive: false,
  onTap: null,
),
```

**After:**
```dart
_Pill(
  label: 'MI GYM',
  isActive: segment == FeedSegment.gym,
  onTap: () => ref.read(feedSegmentProvider.notifier).state =
      FeedSegment.gym,
),
const SizedBox(width: 12),
_Pill(
  label: 'PÚBLICO',
  isActive: segment == FeedSegment.public,
  onTap: () => ref.read(feedSegmentProvider.notifier).state =
      FeedSegment.public,
),
```

**Const-correctness check**: the parent `FeedSegmentPills()` call site at `feed_screen.dart:25` stays `const` because `FeedSegmentPills` constructor is `const` — its `build()` is reactive. The inner `_Pill` widgets must be non-const since they hold non-const `onTap` closures. The intermediate `SizedBox(width: 12)` separators stay `const`. This matches the existing AMIGOS pill pattern at lines 22–27.

---

## 3. Provider Composition Tree

```
authStateChangesProvider (StreamProvider<User?>)
  └─ userProfileProvider (StreamProvider<UserProfile?>)
       └─ myGymFeedProvider (FutureProvider<List<Post>?>)         ← NEW
            ├─ profile == null OR profile.gymId == null  → null
            └─ else → feedForGymProvider(gymId).future            ← existing
                       └─ postRepositoryProvider.feedForGym(gymId)

(separately, no auth dependency)
feedPublicProvider (FutureProvider<List<Post>>)                   ← existing
  └─ postRepositoryProvider.feedPublic()
```

`myGymFeedProvider` invalidates downstream whenever `userProfileProvider` re-emits (e.g., user joins a gym → `gymId` flips from `null` to a value → wrapper re-runs → `feedForGymProvider(newGymId)` is fetched). No manual invalidation needed.

---

## 4. Widget Composition

```
FeedScreen (ConsumerWidget)
  └─ Column
       ├─ _FeedHeader (const StatelessWidget)
       ├─ FeedSegmentPills (const ConsumerWidget)
       │    └─ Row
       │         ├─ _Pill AMIGOS  (existing, reactive)
       │         ├─ _Pill MI GYM  (rewired: isActive + onTap)        ← MODIFIED
       │         └─ _Pill PÚBLICO (rewired: isActive + onTap)        ← MODIFIED
       └─ Expanded
            └─ switch (segment)
                 ├─ amigos → _AmigosBody (existing ConsumerWidget)
                 │    └─ FeedEmptyState(message: '...')               ← param updated
                 ├─ gym    → _MiGymBody (NEW ConsumerWidget)          ← NEW
                 │    ├─ data null     → FeedEmptyState('no estás en un gym')
                 │    ├─ data []       → FeedEmptyState('gym sin posts')
                 │    └─ data [...]    → ListView.separated of PostCard
                 └─ public → _PublicoBody (NEW ConsumerWidget)        ← NEW
                      ├─ data []       → FeedEmptyState('sin posts públicos')
                      └─ data [...]    → ListView.separated of PostCard
```

---

## 5. AsyncValue Routing

### 5.1 `_MiGymBody` — `ref.watch(myGymFeedProvider)`

| AsyncValue case | Render | Notes |
|---|---|---|
| `loading` | `CircularProgressIndicator(color: palette.accent)` centered | Covers BOTH "auth loading" and "profile loading" and "gym posts loading" — the wrapper collapses these into one loading state via `await ref.watch(...future)`. |
| `error(_, __)` | Centered generic copy `'No pudimos cargar tu feed. Intentá de nuevo.'` | Reused from `_AmigosBody` (ADR-006). |
| `data(null)` | `FeedEmptyState(message: 'Todavía no estás en un gym')` | The "no gym" sentinel. ADR-001. |
| `data([])` | `FeedEmptyState(message: 'Tu gym todavía no tiene posts')` | Gym exists, no posts yet. |
| `data([...])` | `ListView.separated(PostCard...)` with `// TODO(pagination)` | Padding 20h, separator 14h — matches `_AmigosBody`. |

### 5.2 `_PublicoBody` — `ref.watch(feedPublicProvider)`

| AsyncValue case | Render | Notes |
|---|---|---|
| `loading` | `CircularProgressIndicator(color: palette.accent)` centered | `feedPublicProvider` has no auth dependency → fast resolution typically. |
| `error(_, __)` | Centered generic copy | Same string as above. |
| `data([])` | `FeedEmptyState(message: 'Aún no hay posts públicos')` | Single empty branch (no null sentinel — public has no per-user gating). |
| `data([...])` | `ListView.separated(PostCard...)` with `// TODO(pagination)` | Same layout as MI GYM. |

### 5.3 `_AmigosBody` (UNCHANGED behaviorally)

Only the `FeedEmptyState()` call gains an explicit `message` argument. AsyncValue routing identical.

---

## 6. ADRs

### ADR-001 — `myGymFeedProvider` returns `List<Post>?` (null = no gym), not a separate `hasGymProvider`

**Status**: Accepted (locks proposal Q1).

**Context**: We need to surface three states for MI GYM: loading, no-gym, gym-with-no-posts, gym-with-posts. The body widget needs a single signal it can switch on.

**Decision**: One `FutureProvider<List<Post>?>` where `null` semantically means "no gym".

**Alternatives rejected**:
- `(FutureProvider<List<Post>>, Provider<bool> hasGym)` pair: forces the body widget to combine two AsyncValues, doubles the `ref.watch` surface, and creates a race window where `hasGym` and posts can disagree mid-transition. Rejected.
- Throwing on `gymId == null` and routing via the `error` branch: conflates "user has no gym" (expected, empty-state UX) with "Firestore failure" (error UX). Rejected — semantically wrong.
- Returning a sealed class `MiGymState`: cleaner for >2 states, overkill for one nullable distinction. Rejected — premature.

**Tradeoff**: callers MUST `if (posts == null)` before `posts.isEmpty` — easy to forget. Mitigated by ADR-008 test coverage and by colocating the comment block on the provider.

### ADR-002 — `FutureProvider`, not `StreamProvider`, for `myGymFeedProvider`

**Status**: Accepted (locks proposal Q8).

**Context**: `userProfileProvider` upstream is a `StreamProvider`. Riverpod allows downstream `FutureProvider` to await `.future` of an upstream stream.

**Decision**: `FutureProvider<List<Post>?>`.

**Why**:
- Consistency with `myFriendsFeedProvider` (existing pattern in same file, lines 13–21).
- `feedForGymProvider` is itself a `FutureProvider.family` — wrapping it in a `StreamProvider` would be an impedance mismatch.
- Live-update reactivity is preserved: when `userProfileProvider` re-emits (e.g., gymId changes), the `FutureProvider` wrapper re-runs because `.watch(.future)` re-subscribes. We get reactivity without the API complexity of streams.

**Alternative rejected**: `StreamProvider<List<Post>?>` would require a custom `async*` body merging two streams (profile + posts). More code, no UX benefit for this PR (post creation is out of scope).

### ADR-003 — Parameterize `FeedEmptyState`, do not duplicate the widget

**Status**: Accepted (locks proposal Q2).

**Context**: We need 3 distinct empty-state messages (AMIGOS, MI GYM no-gym, MI GYM no-posts, PÚBLICO no-posts → 4 actually). Current `FeedEmptyState` hardcodes a single string.

**Decision**: Replace `_kCopy` with a required `message` parameter and an optional `icon` (default `TreinoIcon.users`).

**Alternatives rejected**:
- `_GymEmptyState`, `_PublicoEmptyState` private widgets per body: 4× the code for an icon + text pair. Violates DRY. Rejected.
- Inline `Center(Column(Icon, Text))` per body: same duplication, 30+ lines per body. Rejected.
- Make `message` optional with the AMIGOS string as default: hides the requirement and makes the AMIGOS callsite implicit. Required is clearer. Rejected.

**Migration cost**: 1 callsite (`_AmigosBody`) updated atomically in the same change.

### ADR-004 — MI GYM bodies stay in `feed_screen.dart`, not extracted

**Status**: Accepted (locks proposal Q6).

**Context**: `_AmigosBody` lives inside `feed_screen.dart` as a private class (lines 76–114). The new bodies could mirror this OR be extracted to `presentation/widgets/`.

**Decision**: Stay in `feed_screen.dart` next to `_AmigosBody`.

**Why**:
- Consistency with the pattern Etapa 2 established.
- All three bodies are private to the screen — they have no other consumer.
- Keeps the diff tight (one file gains ~60 lines of bodies) and makes review easier than "switch arm changes here, body widgets created there".
- Total file size after change: ~180 lines — well under any reasonable file-size threshold.

**Alternative rejected**: Extracting to `presentation/widgets/feed_my_gym_body.dart` and `feed_publico_body.dart` adds 2 files for no testability gain (private widgets are tested via screen widget tests anyway).

### ADR-005 — `onAuthorTap` is a no-op closure with TODO, not `null`

**Status**: Accepted.

**Context**: `PostCard` declares `final VoidCallback? onAuthorTap` — passing `null` is type-valid. But this PR establishes the integration point for Etapa 4 (`/feed/profile/:uid`). If we pass `null`, Etapa 4 must search-and-wire 2+ callsites later.

**Decision**: Pass `onAuthorTap: () {}` with a `// TODO: navigate to /feed/profile/${post.authorUid} — route added in feat/public-profile (Etapa 4)` comment.

**Why**:
- Integration seam is documented in code, not just in chat/PR.
- Etapa 4 dev finds both callsites by `rg "TODO: navigate to /feed/profile"`.
- We do NOT touch `PostCard` (CONSTRAINT) — only the call site.
- We do NOT touch `router.dart` (CONSTRAINT) — the closure is intentionally a no-op so the route doesn't need to exist yet.

**Alternative rejected**: Pass `null` — loses the integration breadcrumb. Rejected.

**Note**: AMIGOS body does NOT change its `PostCard` call (currently passes no `onAuthorTap`) because `_AmigosBody` is unchanged behaviorally; adding the TODO callback there would expand scope unnecessarily and could conflict with Etapa 4. Etapa 4 will add it when the route lands.

### ADR-006 — Generic error copy across all 3 segments

**Status**: Accepted (locks proposal Q5).

**Context**: AMIGOS uses `'No pudimos cargar tu feed. Intentá de nuevo.'`. We could craft segment-specific copy.

**Decision**: Reuse the same string for MI GYM and PÚBLICO.

**Why**:
- The user typically does not know what failed (network? Firestore? auth?). Generic copy is honest.
- Localization / future i18n: 1 string is cheaper than 3.
- Visual + tone consistency across segments.

**Alternative rejected**: Per-segment error copy (`'No pudimos cargar el feed de tu gym'`) — adds nothing actionable, multiplies translation work.

### ADR-007 — MI GYM pill stays tappable when user has no gym

**Status**: Accepted (locks proposal Q3).

**Context**: When `gymId == null`, the user can still tap MI GYM and land on the no-gym empty state.

**Decision**: Pill is always tappable; the "no gym" state surfaces via empty state.

**Why**:
- Hiding/disabling the pill based on profile state introduces a reactive dependency in `FeedSegmentPills` (it would need to watch `userProfileProvider` too) — extra coupling for marginal UX value.
- An empty state explaining "you're not in a gym yet" is more discoverable than a missing pill (users wonder where it went).
- Once Etapa join-a-gym ships, the pill behavior auto-updates without needing to revisit the pill widget.

**Alternative rejected**: Hide the pill when `gymId == null` — adds reactive coupling, hurts discoverability.

### ADR-008 — Pagination deferred behind `// TODO(pagination)` markers

**Status**: Accepted.

**Context**: `feedForGym` and `feedPublic` return all matching documents (no `limit`, no cursor). Roadmap marks pagination as "if in scope".

**Decision**: NO pagination in this PR. Add `// TODO(pagination): cursor-based pagination deferred (see explore §9)` at both new `ListView.separated` callsites.

**Why** (from explore §9):
- Seed data is 6–10 posts total — instant render.
- Pagination would require breaking `Future<List<Post>>` repository signatures into stream/page-aware APIs — non-trivial scope, would touch the data layer (Etapa 1 owner).
- Would push this PR over the 400-line budget.
- Comment leaves a code-anchored breadcrumb for the future.

**Alternative rejected**: Implement pagination now — out of budget, out of scope, blocks coordination.

---

## 7. Test Design

Strict TDD is active — all tests are RED before any impl line is written. Tests pair with REQ-FSG-* requirements (numbering will be locked by `sdd-spec`).

| Requirement (placeholder) | Test file | Type | Description |
|---|---|---|---|
| REQ-FSG-001 (provider null-gym branch) | `test/features/feed/application/my_gym_feed_provider_test.dart` | **Unit (provider)** | `ProviderContainer` with `userProfileProvider` overridden to emit `UserProfile(gymId: null)` → assert `myGymFeedProvider.future` resolves to `null`. |
| REQ-FSG-002 (provider gym-present branch) | same file | Unit (provider) | Override `userProfileProvider` to emit `UserProfile(gymId: 'gym-1')` AND override `feedForGymProvider('gym-1')` to return a fake list → assert wrapper returns that exact list. |
| REQ-FSG-003 (provider re-runs on gymId change) | same file | Unit (provider) | Override profile with a `StreamController`; emit profile with `gymId: null`, assert null; emit `gymId: 'gym-1'`, assert non-null result. (Optional — covers reactivity.) |
| REQ-FSG-004 (pill MI GYM activates segment) | `test/features/feed/presentation/widgets/feed_segment_pills_test.dart` (new or extend existing) | Widget | Pump `FeedSegmentPills`, tap MI GYM, assert `feedSegmentProvider` value flips to `FeedSegment.gym`. |
| REQ-FSG-005 (pill PÚBLICO activates segment) | same file | Widget | Same as above for `FeedSegment.public`. |
| REQ-FSG-006 (MI GYM body shows no-gym empty state) | `test/features/feed/feed_screen_test.dart` (new or extend) | Widget | Override `myGymFeedProvider` → `null`, set segment to `gym`, pump `FeedScreen`, assert finds text `'Todavía no estás en un gym'`. |
| REQ-FSG-007 (MI GYM body shows no-posts empty state) | same file | Widget | Override `myGymFeedProvider` → `[]`, assert finds text `'Tu gym todavía no tiene posts'`. |
| REQ-FSG-008 (MI GYM body renders posts) | same file | Widget | Override `myGymFeedProvider` → `[fakePost]`, assert finds `PostCard` widget. |
| REQ-FSG-009 (PÚBLICO body shows empty state) | same file | Widget | Override `feedPublicProvider` → `[]`, set segment to `public`, assert finds `'Aún no hay posts públicos'`. |
| REQ-FSG-010 (PÚBLICO body renders posts) | same file | Widget | Override `feedPublicProvider` → `[fakePost]`, assert finds `PostCard`. |
| REQ-FSG-011 (FeedEmptyState message param) | `test/features/feed/presentation/widgets/feed_empty_state_test.dart` (new) | Widget | Pump `FeedEmptyState(message: 'X')`, assert text `'X'` is present. |
| REQ-FSG-012 (AMIGOS visual parity preserved) | extend feed_screen_test | Widget | Override friends provider → `[]`, assert text `'Aún no hay posts de tus amigos'` still visible (regression guard for ADR-003 migration). |

**Provider override pattern** (canonical for unit tests):

```dart
final container = ProviderContainer(overrides: [
  userProfileProvider.overrideWith((ref) =>
      Stream.value(UserProfile(uid: 'u1', gymId: null, /* ... */))),
]);
addTearDown(container.dispose);
final result = await container.read(myGymFeedProvider.future);
expect(result, isNull);
```

**Widget override pattern**:

```dart
await tester.pumpWidget(ProviderScope(
  overrides: [
    myGymFeedProvider.overrideWith((ref) => Future.value(null)),
    feedSegmentProvider.overrideWith((ref) => FeedSegment.gym),
  ],
  child: const MaterialApp(home: Scaffold(body: FeedScreen())),
));
```

**Note**: REQ numbering is provisional — `sdd-spec` will assign final IDs.

---

## 8. TDD Order (Test Files BEFORE Impl Files)

Strict TDD pairing:

| Step | Action | File |
|---|---|---|
| 1 | RED: write provider test (null-gym + gym-present branches) | `test/features/feed/application/my_gym_feed_provider_test.dart` |
| 2 | GREEN: add `myGymFeedProvider` | `lib/features/feed/application/feed_screen_providers.dart` |
| 3 | RED: write `FeedEmptyState` param test | `test/features/feed/presentation/widgets/feed_empty_state_test.dart` |
| 4 | GREEN: parameterize `FeedEmptyState` + update AMIGOS callsite | `lib/features/feed/presentation/widgets/feed_empty_state.dart` + `lib/features/feed/feed_screen.dart` (line 87 only) |
| 5 | RED: write widget tests for `_MiGymBody` (null / [] / [post]) and `_PublicoBody` ([] / [post]) | `test/features/feed/feed_screen_test.dart` |
| 6 | GREEN: add `_MiGymBody`, `_PublicoBody`, replace switch arm | `lib/features/feed/feed_screen.dart` |
| 7 | RED: write pill activation tests (MI GYM + PÚBLICO) | `test/features/feed/presentation/widgets/feed_segment_pills_test.dart` |
| 8 | GREEN: rewire MI GYM + PÚBLICO `_Pill`s | `lib/features/feed/presentation/widgets/feed_segment_pills.dart` |
| 9 | REFACTOR (if needed): extract shared "loading"/"error" Centers if duplication is painful | `feed_screen.dart` (judgment call — likely skip; 3 copies is below the rule-of-three threshold for the inline error/loading widgets) |
| 10 | Final: `flutter analyze` (0 issues), `dart format .`, full test pass | — |

**Refactor note (step 9)**: After GREEN, three copies of the loading center and three copies of the error center exist (one per body). Rule of three suggests extracting a `_FeedLoadingState` and `_FeedErrorState` private widget. Defer this to a follow-up if it becomes painful — it is not blocking and adds 2 widgets that could complicate review.

---

## 9. Risks (Architectural)

| Risk | Severity | Mitigation |
|---|---|---|
| `userProfileProvider` `Stream.empty()` during auth-loading blocks `myGymFeedProvider.future` indefinitely | Med | The wrapper's `loading` AsyncValue handles this — body shows spinner. Test coverage for the loading branch is recommended (extend REQ-FSG-001 with a "stays loading while profile not emitted" case). |
| `_AmigosBody` `FeedEmptyState` callsite migration introduces typo → empty-state copy regression | Low | REQ-FSG-012 regression test pins the exact string. |
| Removing `const` on inner `_Pill`s creates a perf-sensitive review flag | Low | Documented in ADR (parent stays const, only inner reactive widgets lose const) — matches AMIGOS pill, no actual perf delta. |
| `feedPublicProvider` returns posts from any user (no Firestore rule check at this layer) — security concern surfaces in MI GYM too | Low (out of scope) | Repository + Firestore rules enforce access. UI layer trusts the data layer. Noted in explore §10.3 — QA item, not a code change here. |
| Etapa 4 lands `onAuthorTap` wiring concurrently and conflicts with the no-op closures + TODOs | Low | TODO comment uses unique substring `route added in feat/public-profile (Etapa 4)` — Etapa 4 dev can `rg` for it. Coordination noted in proposal. |
| `myGymFeedProvider` test uses a fake `UserProfile` that drifts from the real domain class | Low | Test imports the real `UserProfile` class — drift would break compilation, not silent behavior. |

---

## 10. Open Questions

None blocking. All proposal Q1–Q9 are locked.

Pre-spec note: `sdd-spec` should assign canonical `REQ-FSG-NNN` IDs and may collapse REQ-FSG-002 + REQ-FSG-003 into one if the team prefers fewer requirements per branch.

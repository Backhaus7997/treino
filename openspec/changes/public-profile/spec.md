# Spec — public-profile

**Change**: `public-profile`
**Fase / Etapa**: Fase 3 · Etapa 4
**Artifact store**: `openspec`
**TDD**: Strict — tests are written BEFORE each widget/provider/repo method in the apply phase.
**Scenario numbering**: continues from SCENARIO-189 (highest after feed-shell-amigos). Starts at SCENARIO-190.
**REQ namespace**: `REQ-PROFILE-*` (first time public-profile screen has requirements)

---

## Overview

This spec defines verifiable requirements for the public profile screen reachable at `/feed/profile/:uid`. The change covers:

1. A new `getByPair` method on `FriendshipRepository`
2. Three new Riverpod providers (`friendshipByPairProvider`, `firstPostByAuthorProvider`, `publicProfileViewProvider`)
3. A `PublicProfileView` DTO (freezed)
4. `PublicProfileScreen` orchestrator widget
5. Three presentation widgets: `PublicProfileHero`, `PublicProfileStatsRow`, `PublicProfileFollowButton`
6. A local pill-tab widget `_ProfileTabPills` + tab-content placeholders (inline in screen or extracted as needed by design)
7. A new nested GoRoute `/feed/profile/:uid` inside the existing `/feed` ShellRoute
8. A conditional wire of `PostCard.onAuthorTap` in `feed_screen.dart` (deferred if Etapa 3 has not yet merged)

**Delta only**: this spec does NOT re-describe existing `Post`, `Friendship`, `FeedScreen`, or existing providers. It only specifies what must be true AFTER this change is applied.

**Coordination note**: Dev C owns `feed_screen.dart`, `feed_segment_pills.dart`, and `feed_screen_providers.dart` in Etapa 3. The wire of `PostCard.onAuthorTap` from `feed_screen.dart` (REQ-PROFILE-WIRE-001) is explicitly marked conditional — it is applied at rebase time if Etapa 3 has merged, or deferred to a follow-up commit otherwise.

Test helper convention (mirrors `feed-shell-amigos`):

```dart
Widget _wrap(Widget w) =>
    MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w));

Widget _wrapProvider(Widget w, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w)),
);

Widget _wrapRouter({
  required Widget Function(BuildContext) builder,
  required List<RouteBase> routes,
  List<Override> overrides = const [],
}) {
  final router = GoRouter(routes: routes);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
    ),
  );
}
```

All provider-override tests use `ProviderScope.overrides`. Mocks via `mocktail`. Firestore isolation via `FakeFirebaseFirestore`.

---

## Requirements

---

### REQ-PROFILE-REPO-001 — `FriendshipRepository.getByPair` returns existing friendship or null

`FriendshipRepository` MUST gain a new method `getByPair(String uidA, String uidB) → Future<Friendship?>`.

The method MUST:
- Derive the doc ID using `Friendship.sortedDocId(uidA, uidB)` — the same helper already used by `request()`.
- Perform a single `_friendships.doc(id).get()` call.
- Return a fully hydrated `Friendship` (via `_fromDoc`) when the document exists.
- Return `null` when the document does not exist (`.exists == false`).

The method MUST NOT introduce a new Firestore query (i.e., no `where()` clause). It MUST NOT modify the behavior or signature of any existing `FriendshipRepository` method.

No new Firestore security rules are required because the viewer is always a `member` of any doc that exists between `(uidA, uidB)`, and a non-existent doc returns `null` from `get()` without a permission error.

#### Scenarios

**SCENARIO-190** — `getByPair` returns the `Friendship` when the document exists
- GIVEN a `FakeFirebaseFirestore` instance with a `friendships` document at ID `Friendship.sortedDocId('alice', 'bob')`
- AND the document contains `status: 'pending'`, `requesterId: 'alice'`, `members: ['alice', 'bob']`
- WHEN `repo.getByPair('alice', 'bob')` is awaited
- THEN the result is a non-null `Friendship` with `friendship.requesterId == 'alice'` AND `friendship.status == FriendshipStatus.pending`

**SCENARIO-191** — `getByPair` returns `null` when no document exists
- GIVEN a `FakeFirebaseFirestore` with NO `friendships` document for `('alice', 'bob')`
- WHEN `repo.getByPair('alice', 'bob')` is awaited
- THEN the result is `null` and no exception is thrown

**SCENARIO-192** — `getByPair` respects sorted doc ID regardless of argument order
- GIVEN a `FakeFirebaseFirestore` with a friendship doc at `Friendship.sortedDocId('alice', 'bob')` (i.e., `'alice_bob'`)
- WHEN `repo.getByPair('bob', 'alice')` is awaited (reversed order)
- THEN the result is the same non-null `Friendship` as if called with `('alice', 'bob')`

---

### REQ-PROFILE-PROVIDER-001 — `friendshipByPairProvider` is auth-gated and calls `getByPair`

A new provider MUST be defined in `lib/features/feed/application/public_profile_providers.dart`:

```dart
final friendshipByPairProvider = FutureProvider.autoDispose
    .family<Friendship?, ({String viewerUid, String targetUid})>(
  (ref, args) async { ... }
);
```

The `FriendshipPair` record type `({String viewerUid, String targetUid})` is used as the family argument (Dart record / named tuple — no separate class needed).

The provider MUST:
- Return `null` immediately when `authStateChangesProvider.valueOrNull` is `null` (unauthenticated — no Firestore call).
- Call `friendshipRepositoryProvider.getByPair(args.viewerUid, args.targetUid)` when authenticated.
- Be declared as `autoDispose` to prevent unbounded family caching.

This provider MUST NOT be defined in `friendship_providers.dart` (that file is Dev C's territory and must not be modified).

#### Scenarios

**SCENARIO-193** — Provider returns `Friendship` when doc exists and user is authenticated
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(MockUser(uid: 'viewer1'))`
- AND `friendshipRepositoryProvider` overridden with a mock that returns a `Friendship` (status: accepted) for `('viewer1', 'target1')`
- WHEN `container.read(friendshipByPairProvider((viewerUid: 'viewer1', targetUid: 'target1')).future)` is awaited
- THEN the result is the non-null `Friendship` with `status == FriendshipStatus.accepted`

**SCENARIO-194** — Provider returns `null` when no friendship doc exists
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(MockUser(uid: 'viewer1'))`
- AND `friendshipRepositoryProvider` overridden with a mock that returns `null` for `('viewer1', 'target1')`
- WHEN the provider future is awaited
- THEN the result is `null` and no exception is thrown

**SCENARIO-195** — Provider returns `null` when unauthenticated (no Firestore call made)
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(null)` (null user)
- AND `friendshipRepositoryProvider` overridden with a mock that tracks calls
- WHEN the provider future is awaited
- THEN the result is `null` AND `getByPair` was NOT called on the mock repository

---

### REQ-PROFILE-PROVIDER-002 — `firstPostByAuthorProvider` queries posts with `limit 1`

A new provider MUST be defined in `public_profile_providers.dart`:

```dart
final firstPostByAuthorProvider =
    FutureProvider.autoDispose.family<Post?, String>(
  (ref, targetUid) async { ... }
);
```

The provider MUST:
- Return `null` immediately when `authStateChangesProvider.valueOrNull` is `null` (unauthenticated).
- Query `posts` where `authorUid == targetUid`, ordered by `createdAt` descending, with a limit of 1.
- Return the first `Post` in the result, or `null` if the result is empty.
- Be `autoDispose`.

The provider MUST NOT perform a collection-group query or query across any collection other than `posts`.

#### Scenarios

**SCENARIO-196** — Provider returns the most recent `Post` when target has posts
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(MockUser(uid: 'v1'))`
- AND a `FakeFirebaseFirestore` with two posts authored by `'target1'` — one created at `T-1h`, another at `T-10min`
- WHEN `container.read(firstPostByAuthorProvider('target1').future)` is awaited
- THEN the result is non-null AND `result.authorUid == 'target1'` AND `result.createdAt` matches the more recent post (`T-10min`)

**SCENARIO-197** — Provider returns `null` when target has no posts
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(MockUser(uid: 'v1'))`
- AND a `FakeFirebaseFirestore` with zero posts authored by `'target1'`
- WHEN the provider future is awaited
- THEN the result is `null` and no exception is thrown

**SCENARIO-198** — Provider returns `null` when unauthenticated
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(null)`
- WHEN the provider future is awaited
- THEN the result is `null` and no Firestore call is made

---

### REQ-PROFILE-DTO-001 — `PublicProfileView` is a freezed DTO with 5 fields

A new file `lib/features/feed/domain/public_profile_view.dart` MUST define a `@freezed` class:

```dart
@freezed
class PublicProfileView with _$PublicProfileView {
  const factory PublicProfileView({
    required String authorDisplayName,
    required String? authorAvatarUrl,
    required String? authorGymId,
    required Friendship? friendship,
    required bool isSelf,
  }) = _PublicProfileView;
}
```

Rules:
- `authorDisplayName` — MUST default to `'Anónimo'` when the upstream `Post` is null (enforced by the provider, not the DTO itself).
- `fromJson`/`toJson` are NOT required — this is a pure in-memory view-model.
- Freezed equality and `hashCode` are required (auto-generated by freezed).
- No `part '*.g.dart'` unless the design phase opts in for serialization. Default: `part '*.freezed.dart'` only.

#### Scenarios

**SCENARIO-199** — `PublicProfileView` equality is structural (freezed `==`)
- GIVEN two `PublicProfileView` instances constructed with identical field values (including `friendship: null`, `isSelf: false`)
- WHEN compared with `==`
- THEN the result is `true`

**SCENARIO-200** — `PublicProfileView` instances with different `isSelf` are NOT equal
- GIVEN instance A with `isSelf: false` and instance B with `isSelf: true` (all other fields identical)
- WHEN compared with `==`
- THEN the result is `false`

---

### REQ-PROFILE-PROVIDER-003 — `publicProfileViewProvider` composes post + friendship into a DTO

A new provider MUST be defined in `public_profile_providers.dart`:

```dart
final publicProfileViewProvider =
    FutureProvider.autoDispose.family<PublicProfileView, String>(
  (ref, targetUid) async { ... }
);
```

Composition rules:
1. Read `authStateChangesProvider.valueOrNull` for the viewer's `User?`.
2. Await `firstPostByAuthorProvider(targetUid)` to obtain `Post?`.
3. Derive `isSelf` as `viewer?.uid == targetUid` (false when viewer is null).
4. When `isSelf == true` OR `viewer == null`: set `friendship = null` and skip the `friendshipByPairProvider` call.
5. Otherwise: await `friendshipByPairProvider((viewerUid: viewer!.uid, targetUid: targetUid))`.
6. Construct and return `PublicProfileView` with:
   - `authorDisplayName: post?.authorDisplayName ?? 'Anónimo'`
   - `authorAvatarUrl: post?.authorAvatarUrl`
   - `authorGymId: post?.authorGymId`
   - `friendship:` the result from step 5
   - `isSelf:` from step 3

A code comment MUST appear above the `authorDisplayName` assignment:
`// Approach A: denormalized from Post. If target has never posted, falls back to 'Anónimo'. See proposal §4 decision 1.`

#### Scenarios

**SCENARIO-201** — Provider composes correctly when target has a post and friendship is accepted
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(MockUser(uid: 'viewer1'))`
- AND `firstPostByAuthorProvider('target1')` overridden to return `Post(authorDisplayName: 'Mateo', authorAvatarUrl: 'https://ex.com/av.jpg', authorGymId: 'gym-la-fuerza', ...)`
- AND `friendshipByPairProvider((viewerUid: 'viewer1', targetUid: 'target1'))` overridden to return an accepted `Friendship`
- WHEN `container.read(publicProfileViewProvider('target1').future)` is awaited
- THEN `view.authorDisplayName == 'Mateo'` AND `view.authorAvatarUrl == 'https://ex.com/av.jpg'` AND `view.friendship?.status == FriendshipStatus.accepted` AND `view.isSelf == false`

**SCENARIO-202** — Provider returns `'Anónimo'` when target has no posts
- GIVEN `authStateChangesProvider` overridden to emit authenticated user
- AND `firstPostByAuthorProvider('target1')` overridden to return `null`
- AND `friendshipByPairProvider(...)` overridden to return `null`
- WHEN the provider future is awaited
- THEN `view.authorDisplayName == 'Anónimo'` AND `view.authorAvatarUrl == null`

**SCENARIO-203** — Provider sets `isSelf: true` and skips friendship lookup when viewer == target
- GIVEN `authStateChangesProvider` overridden to emit `AsyncData(MockUser(uid: 'viewer1'))`
- AND `firstPostByAuthorProvider('viewer1')` overridden with any `Post?`
- AND `friendshipByPairProvider(...)` overridden with a mock that tracks calls
- WHEN `container.read(publicProfileViewProvider('viewer1').future)` is awaited (targetUid == viewerUid)
- THEN `view.isSelf == true` AND `view.friendship == null` AND `friendshipByPairProvider` was NOT called

---

### REQ-PROFILE-SCREEN-001 — `PublicProfileScreen` orchestrates 3 async states

`lib/features/feed/presentation/public_profile_screen.dart` MUST export a `ConsumerWidget` named `PublicProfileScreen` that accepts a `targetUid: String` constructor parameter.

The widget MUST:
- Watch `publicProfileViewProvider(targetUid)`.
- Route `AsyncData<PublicProfileView>` → render the full profile composition (hero + buttons + stats + tabs).
- Route `AsyncLoading` → render a centered `CircularProgressIndicator` with color `palette.accent`.
- Route `AsyncError` → render centered text `'No pudimos cargar este perfil.'` in `palette.textMuted`.

The widget MUST NOT introduce a `Scaffold`, `AppBackground`, or `SafeArea` — the ShellRoute parent already applies them.

#### Scenarios

**SCENARIO-204** — Screen renders hero when data is available
- GIVEN `publicProfileViewProvider('t1')` overridden with `AsyncData(view)` where `view.authorDisplayName == 'Mateo'`
- WHEN `PublicProfileScreen(targetUid: 't1')` is pumped inside `_wrapProvider(...)`
- THEN `find.byType(PublicProfileHero)` finds exactly one widget

**SCENARIO-205** — Screen renders spinner when loading
- GIVEN `publicProfileViewProvider('t1')` overridden with `AsyncLoading<PublicProfileView>()`
- WHEN `PublicProfileScreen(targetUid: 't1')` is pumped (single `pump()`)
- THEN `find.byType(CircularProgressIndicator)` finds exactly one widget AND `find.byType(PublicProfileHero)` finds zero widgets

**SCENARIO-206** — Screen renders graceful error text on `AsyncError`
- GIVEN `publicProfileViewProvider('t1')` overridden with `AsyncError<PublicProfileView>(Exception('net'), StackTrace.empty)`
- WHEN `PublicProfileScreen(targetUid: 't1')` is pumped
- THEN `find.text('No pudimos cargar este perfil.')` finds one widget AND no `FlutterError` is reported

**SCENARIO-207** — Screen does not introduce `Scaffold`, `AppBackground`, or `SafeArea`
- GIVEN `PublicProfileScreen` pumped inside `MaterialApp(home: Scaffold(body: PublicProfileScreen(targetUid: 't1')))` with provider overrides
- WHEN the widget tree is inspected
- THEN `find.byType(Scaffold)` finds exactly one (the outer test wrapper) AND `find.byType(AppBackground)` finds zero AND `find.byType(SafeArea)` finds zero inside `PublicProfileScreen`'s own subtree

---

### REQ-PROFILE-SCREEN-002 — Self-visit guard hides SEGUIR and MENSAJE buttons

When `view.isSelf == true`, `PublicProfileScreen` MUST NOT render `PublicProfileFollowButton` or the MENSAJE stub button. The `PublicProfileHero`, `PublicProfileStatsRow`, and tabs MUST still render normally.

#### Scenarios

**SCENARIO-208** — Follow and message buttons absent on self-visit
- GIVEN `publicProfileViewProvider('self1')` overridden with `AsyncData(PublicProfileView(..., isSelf: true))`
- WHEN `PublicProfileScreen(targetUid: 'self1')` is pumped
- THEN `find.byType(PublicProfileFollowButton)` finds zero widgets AND `find.text('MENSAJE')` finds zero widgets

**SCENARIO-209** — Hero and stats still render on self-visit
- GIVEN same overrides as SCENARIO-208
- WHEN the widget tree is inspected
- THEN `find.byType(PublicProfileHero)` finds one widget AND `find.byType(PublicProfileStatsRow)` finds one widget

---

### REQ-PROFILE-HERO-001 — `PublicProfileHero` renders avatar, display name, and gym subtitle

`lib/features/feed/presentation/widgets/public_profile_hero.dart` MUST export a `StatelessWidget` named `PublicProfileHero` that accepts a `view: PublicProfileView` parameter.

The widget MUST:
- Render a `PostAvatar` with `size: 96`, `authorDisplayName: view.authorDisplayName`, `authorAvatarUrl: view.authorAvatarUrl`.
- Render the display name as UPPERCASE text in `GoogleFonts.barlowCondensed` weight 700.
- Render the gym subtitle resolved via `gymNameFromId(view.authorGymId)`:
  - If `gymNameFromId` returns a non-empty string: render it as a subtitle in `palette.textMuted`.
  - If it returns an empty string (i.e., `null` or `'no-gym'` gymId): render no subtitle widget.
- Use a gradient background `LinearGradient` from `palette.accent` to `palette.bg` (same pattern as `RoutineDetailScreen`). No hero background photo.
- All colors MUST use `AppPalette.of(context)`. No HEX literals. No `PhosphorIcons.*` direct usage.

The `gymNameFromId(String? gymId) → String` utility function MUST be defined in `lib/features/feed/domain/gym_name.dart` (new file) and MUST:
- Look up `gymId` in the same hardcoded list used by `profile_setup_providers.dart`.
- Return the resolved gym name if found.
- Return `''` when `gymId` is `null` or equals `'no-gym'`.
- Return the raw `gymId` string for any unrecognized non-null, non-`'no-gym'` value.

#### Scenarios

**SCENARIO-210** — Hero renders avatar with correct size
- GIVEN `PublicProfileHero(view: view)` where `view.authorDisplayName == 'Mateo'` and `view.authorAvatarUrl == null`
- WHEN pumped inside `_wrap(...)`
- THEN `find.byType(PostAvatar)` finds one widget AND the `PostAvatar` has `size == 96`

**SCENARIO-211** — Hero renders display name in UPPERCASE
- GIVEN `PublicProfileHero(view: view)` where `view.authorDisplayName == 'Mateo Quintero'`
- WHEN pumped
- THEN a text widget containing `'MATEO QUINTERO'` is found (or the `Text` widget's `text` is `'Mateo Quintero'` with `TextStyle` that makes it uppercase via `toUpperCase()` transform — either is acceptable; the rendered text must appear uppercase)

**SCENARIO-212** — Hero renders resolved gym subtitle when gymId is known
- GIVEN `view.authorGymId == 'megatlon-recoleta'` AND `gymNameFromId('megatlon-recoleta')` returns `'Megatlon Recoleta'`
- WHEN `PublicProfileHero(view: view)` is pumped
- THEN a text widget containing `'Megatlon Recoleta'` is found

**SCENARIO-213** — Hero renders no subtitle when gymId is `null`
- GIVEN `view.authorGymId == null`
- WHEN `PublicProfileHero(view: view)` is pumped
- THEN no text widget with an empty string is rendered as a gym subtitle (the gym subtitle widget is absent from the tree)

**SCENARIO-214** — Hero renders `'?'` as initials when `authorDisplayName == 'Anónimo'`
- GIVEN `view.authorDisplayName == 'Anónimo'` AND `view.authorAvatarUrl == null`
- WHEN `PublicProfileHero(view: view)` is pumped
- THEN the `PostAvatar` subtree renders `find.text('?')` (verified via the existing SCENARIO-182 behavior of `PostAvatar`)

**SCENARIO-215** — `gymNameFromId` returns empty string for `null` and `'no-gym'`
- GIVEN the `gymNameFromId` utility function
- WHEN called with `null` → THEN returns `''`
- WHEN called with `'no-gym'` → THEN returns `''`
- WHEN called with `'megatlon-recoleta'` → THEN returns a non-empty resolved name

---

### REQ-PROFILE-STATS-001 — `PublicProfileStatsRow` renders 4 hardcoded zero stats

`lib/features/feed/presentation/widgets/public_profile_stats_row.dart` MUST export a `StatelessWidget` named `PublicProfileStatsRow` that accepts no parameters.

The widget MUST render exactly 4 stat tiles in a `Row`, evenly distributed, in this order:
1. `WORKOUTS` — value `'0'`
2. `RACHA` — value `'0'` colored `palette.accent`
3. `SEGUIDORES` — value `'0'`
4. `SIGUIENDO` — value `'0'`

Each tile MUST render:
- The numeric value in `GoogleFonts.barlow` weight 700, larger font size.
- The label in `GoogleFonts.barlowCondensed` UPPERCASE in `palette.textMuted`.

The `RACHA` value MUST use `palette.accent` color. The other three values MUST use `palette.text` (or `palette.textPrimary`).

A source comment MUST appear: `// Stub: real stats wired in Fase 4.`

No HEX literals in this file.

#### Scenarios

**SCENARIO-216** — Stats row renders all 4 labels
- GIVEN `PublicProfileStatsRow()` is pumped inside `_wrap(...)`
- WHEN the widget tree is inspected
- THEN `find.text('WORKOUTS')` finds one widget AND `find.text('RACHA')` finds one widget AND `find.text('SEGUIDORES')` finds one widget AND `find.text('SIGUIENDO')` finds one widget

**SCENARIO-217** — Stats row renders `'0'` for all 4 values
- GIVEN same pump as SCENARIO-216
- WHEN the widget tree is inspected
- THEN `find.text('0')` finds exactly 4 widgets

**SCENARIO-218** — Stats row contains exactly 4 tile children in the row
- GIVEN same pump as SCENARIO-216
- WHEN the top-level `Row` of the stats widget is inspected
- THEN the `Row` has exactly 4 direct logical children (or 4 evenly-spaced `Expanded`/`Flexible` tiles — design determines the spacer approach; the stat count must be 4)

---

### REQ-PROFILE-FOLLOW-001 — `PublicProfileFollowButton` implements the 4-state machine

`lib/features/feed/presentation/widgets/public_profile_follow_button.dart` MUST export a `ConsumerWidget` named `PublicProfileFollowButton` that accepts:
- `friendship: Friendship?`
- `viewerUid: String`
- `targetUid: String`

The widget MUST render one of four states based on `friendship`:

| State | Condition | Label | Style | `onTap` |
|---|---|---|---|---|
| A — not following | `friendship == null` | `'SEGUIR'` | Mint filled pill | `repo.request(viewerUid, targetUid)` then `ref.invalidate(friendshipByPairProvider(...))` |
| B — request sent | `friendship.status == pending && friendship.requesterId == viewerUid` | `'SOLICITUD ENVIADA'` | Outlined, `Opacity(0.6)`, not tappable | `null` |
| C — request received | `friendship.status == pending && friendship.requesterId == targetUid` | `'ACEPTAR'` | Mint filled pill | `repo.accept(friendship.id, viewerUid)` then `ref.invalidate(...)` |
| D — following | `friendship.status == accepted` | `'SIGUIENDO'` | Outlined pill + `TreinoIcon.check` icon | no-op tap (unfollow deferred to Fase 5) |

State D MUST render `TreinoIcon.check` to the left of the label text.

After a successful `request()` or `accept()` call, the widget MUST call `ref.invalidate(friendshipByPairProvider((viewerUid: viewerUid, targetUid: targetUid)))` to trigger a provider re-fetch.

All button styles MUST use `AppPalette.of(context)`. No HEX literals. No `PhosphorIcons.*` direct usage.

#### Scenarios

**SCENARIO-219** — State A: renders `'SEGUIR'` when `friendship == null`
- GIVEN `PublicProfileFollowButton(friendship: null, viewerUid: 'v1', targetUid: 't1')` pumped inside `_wrapProvider` with `friendshipRepositoryProvider` mocked
- WHEN the widget tree is inspected
- THEN `find.text('SEGUIR')` finds exactly one widget AND no `'SOLICITUD ENVIADA'` or `'ACEPTAR'` or `'SIGUIENDO'` text exists

**SCENARIO-220** — State A: tapping `'SEGUIR'` calls `repo.request(viewerUid, targetUid)`
- GIVEN same setup as SCENARIO-219 with a mock repo that records calls
- WHEN `tester.tap(find.text('SEGUIR'))` and `pumpAndSettle()` are called
- THEN `repo.request('v1', 't1')` was invoked exactly once

**SCENARIO-221** — State B: renders `'SOLICITUD ENVIADA'` when pending and viewer is requester
- GIVEN a `Friendship` with `status: pending` and `requesterId == 'v1'` (viewer)
- AND `PublicProfileFollowButton(friendship: friendship, viewerUid: 'v1', targetUid: 't1')` pumped
- WHEN the widget tree is inspected
- THEN `find.text('SOLICITUD ENVIADA')` finds one widget AND an `Opacity` widget with `opacity == 0.6` (or equivalent visual disabled state) wraps the button

**SCENARIO-222** — State B: tapping `'SOLICITUD ENVIADA'` is a no-op
- GIVEN same setup as SCENARIO-221
- WHEN `tester.tap(find.text('SOLICITUD ENVIADA'))` and `pumpAndSettle()` are called
- THEN `repo.request` was NOT called AND no exception is thrown

**SCENARIO-223** — State C: renders `'ACEPTAR'` when pending and target is requester
- GIVEN a `Friendship` with `status: pending` and `requesterId == 't1'` (target, not viewer)
- AND `PublicProfileFollowButton(friendship: friendship, viewerUid: 'v1', targetUid: 't1')` pumped
- WHEN the widget tree is inspected
- THEN `find.text('ACEPTAR')` finds one widget

**SCENARIO-224** — State C: tapping `'ACEPTAR'` calls `repo.accept(friendship.id, viewerUid)`
- GIVEN same setup as SCENARIO-223 with a mock repo that records calls
- WHEN `tester.tap(find.text('ACEPTAR'))` and `pumpAndSettle()` are called
- THEN `repo.accept(friendship.id, 'v1')` was invoked exactly once

**SCENARIO-225** — State D: renders `'SIGUIENDO'` with check icon when accepted
- GIVEN a `Friendship` with `status: accepted`
- AND `PublicProfileFollowButton(friendship: friendship, viewerUid: 'v1', targetUid: 't1')` pumped
- WHEN the widget tree is inspected
- THEN `find.text('SIGUIENDO')` finds one widget AND `find.byIcon(TreinoIcon.check)` finds at least one widget

**SCENARIO-226** — State D: tapping `'SIGUIENDO'` is a no-op
- GIVEN same setup as SCENARIO-225
- WHEN `tester.tap(find.text('SIGUIENDO'))` and `pumpAndSettle()` are called
- THEN `repo.request` was NOT called AND `repo.accept` was NOT called AND no exception is thrown

---

### REQ-PROFILE-FOLLOW-002 — MENSAJE button is a disabled stub

`PublicProfileScreen` MUST render a MENSAJE button adjacent to the follow button when `view.isSelf == false`.

The MENSAJE button MUST:
- Be labeled `'MENSAJE'` (uppercase).
- Be rendered as an outlined pill.
- Have `Opacity(opacity: 0.6)` applied (visually disabled).
- Have `onTap: null` or equivalent no-op.
- Contain a source comment: `// Stub: wired in Fase 5 (Coach chat).`

#### Scenarios

**SCENARIO-227** — MENSAJE button renders with label when `isSelf == false`
- GIVEN `publicProfileViewProvider('t1')` overridden with `AsyncData(PublicProfileView(..., isSelf: false))`
- WHEN `PublicProfileScreen(targetUid: 't1')` is pumped
- THEN `find.text('MENSAJE')` finds exactly one widget

**SCENARIO-228** — MENSAJE button tap is a no-op
- GIVEN same pump as SCENARIO-227
- WHEN `tester.tap(find.text('MENSAJE'))` and `pumpAndSettle()` are called
- THEN no exception is thrown AND no navigation occurs AND no new overlay appears

---

### REQ-PROFILE-TABS-001 — 2 pill-based tabs with `_ProfileTabPills`

`PublicProfileScreen` MUST include an inline (private) pill-tab widget `_ProfileTabPills` with exactly 2 tabs:
1. `'RUTINAS PÚBLICAS'` (active by default)
2. `'ACTIVIDAD'`

The pill style MUST visually mirror `FeedSegmentPills._Pill` (mint active fill + `palette.bgCard` inactive fill). `_ProfileTabPills` MUST be a private widget local to `public_profile_screen.dart`. It MUST NOT import from `feed_segment_pills.dart`.

A `StateProvider<ProfileTab>` MUST be defined locally (scoped to the screen's `ProviderScope` or defined at file scope with `.autoDispose`). The `ProfileTab` enum MUST have two values: `routines` and `activity`.

The `ProfileTab` enum MUST be defined in the same file as `PublicProfileScreen` or in `lib/features/feed/domain/profile_tab.dart` (new file). It MUST NOT be defined in any shared domain file that other features import.

#### Scenarios

**SCENARIO-229** — Two tab labels are rendered
- GIVEN `publicProfileViewProvider('t1')` overridden with any `AsyncData`
- WHEN `PublicProfileScreen(targetUid: 't1')` is pumped
- THEN `find.text('RUTINAS PÚBLICAS')` finds one widget AND `find.text('ACTIVIDAD')` finds one widget

**SCENARIO-230** — `'RUTINAS PÚBLICAS'` tab is active by default
- GIVEN same pump as SCENARIO-229
- WHEN the widget tree is inspected
- THEN the pill backing `'RUTINAS PÚBLICAS'` has background color `palette.accent` (active style) AND the pill backing `'ACTIVIDAD'` has background color `palette.bgCard` (inactive style)

**SCENARIO-231** — Tapping `'ACTIVIDAD'` makes it active
- GIVEN same pump as SCENARIO-229
- WHEN `tester.tap(find.text('ACTIVIDAD'))` and `pumpAndSettle()` are called
- THEN the `'ACTIVIDAD'` pill now has active style (background `palette.accent`) AND `'RUTINAS PÚBLICAS'` has inactive style

---

### REQ-PROFILE-TABS-002 — Tab content shows placeholder empty state

Both tab bodies MUST render a placeholder widget when selected. Neither tab MUST perform any Firestore query in this etapa.

Empty state copy:
- `'RUTINAS PÚBLICAS'` tab: `'Aún no hay rutinas públicas.'`
- `'ACTIVIDAD'` tab: `'Aún no hay actividad reciente.'`

The empty state widget MUST render the copy centered with `palette.textMuted` color. The implementation MUST include a source comment: `// Placeholder: real content wired in Fase 5 (routines) / Fase 4 (activity).`

#### Scenarios

**SCENARIO-232** — `'RUTINAS PÚBLICAS'` tab body shows correct empty state text
- GIVEN `PublicProfileScreen` pumped with the default tab (routines)
- WHEN the widget tree is inspected
- THEN `find.text('Aún no hay rutinas públicas.')` finds one widget

**SCENARIO-233** — `'ACTIVIDAD'` tab body shows correct empty state text after switching
- GIVEN `PublicProfileScreen` pumped
- WHEN `tester.tap(find.text('ACTIVIDAD'))` and `pumpAndSettle()` are called
- THEN `find.text('Aún no hay actividad reciente.')` finds one widget AND `find.text('Aún no hay rutinas públicas.')` finds zero widgets

---

### REQ-PROFILE-ROUTE-001 — `/feed/profile/:uid` route added inside ShellRoute

`lib/app/router.dart` MUST be amended to add a new nested `GoRoute` under the existing `/feed` `GoRoute`:

```dart
GoRoute(
  path: 'profile/:uid',
  builder: (context, state) => PublicProfileScreen(
    targetUid: state.pathParameters['uid']!,
  ),
),
```

Rules:
- The route MUST be a child of the `/feed` `GoRoute` (not a top-level route).
- The `authRedirect` guard already covers all routes under the ShellRoute — no new redirect logic is required.
- The `_kTabs` index detection (already using `startsWith`) MUST resolve `/feed/profile/:uid` to the Feed tab index automatically. No changes to `_kTabs` detection logic are required.
- A `PublicProfileScreen` import MUST be added to `router.dart`.

#### Scenarios

**SCENARIO-234** — Route resolves `pathParameters['uid']` and passes it to `PublicProfileScreen`
- GIVEN a `GoRouter` configured with the ShellRoute containing the `/feed` route and the nested `profile/:uid` route
- AND `publicProfileViewProvider('user42')` overridden to return `AsyncData(view)`
- WHEN the router navigates to `'/feed/profile/user42'`
- THEN `PublicProfileScreen` is rendered AND the `targetUid` passed to the screen equals `'user42'`

---

### REQ-PROFILE-NAV-001 — Navigation from `PostCard` fires `/feed/profile/:uid`

When `PostCard.onAuthorTap` is wired with `(uid) => context.push('/feed/profile/$uid')` AND the `/feed/profile/:uid` route exists, tapping the author area in `PostCard` MUST navigate to `PublicProfileScreen`.

This test MUST use the `_wrapRouter(...)` helper with a real `GoRouter` instance so that `context.push` is a real navigation call, not a mock.

#### Scenarios

**SCENARIO-235** — Tapping author area in `PostCard` navigates to profile route
- GIVEN a `PostCard(post: post, onAuthorTap: () => context.push('/feed/profile/${post.authorUid}'))` rendered inside `_wrapRouter(routes: [GoRoute(path: '/feed/profile/:uid', builder: (_, __) => const Text('PROFILE_DESTINATION'))])`
- WHEN `tester.tap(find.text(post.authorDisplayName))` and `pumpAndSettle()` are called
- THEN `find.text('PROFILE_DESTINATION')` finds one widget (the route was pushed and the destination rendered)

---

### REQ-PROFILE-WIRE-001 — CONDITIONAL: `PostCard.onAuthorTap` wired in `feed_screen.dart`

**This requirement is CONDITIONAL on rebase state.**

In the apply phase, the implementor MUST check whether Etapa 3 (`feed-segments`) has already merged into `main`:

- **If Etapa 3 HAS merged**: rebase `feat/public-profile` onto `main` and add `onAuthorTap: (uid) => context.push('/feed/profile/$uid')` to every `PostCard(...)` instantiation in `lib/features/feed/feed_screen.dart`. This change MUST be committed as a separate work-unit commit labeled `wire: PostCard.onAuthorTap → /feed/profile/:uid`.

- **If Etapa 3 has NOT merged**: mark this requirement as `DEFERRED-WIRE` in `apply-progress`. The wire MUST be implemented in a follow-up commit immediately after Etapa 3 merges, before the `feat/public-profile` PR is marked Ready for Review.

In both cases, after the wire is applied, the behavior specified by REQ-PROFILE-NAV-001 (SCENARIO-235) MUST be satisfied.

No automated test covers the `feed_screen.dart` wire itself — REQ-PROFILE-NAV-001 (SCENARIO-235) is the integration-level gate for this wiring behavior.

---

### REQ-PROFILE-ICON-001 — `TreinoIcon.check` constant exists

`lib/core/widgets/treino_icon.dart` MUST define the constant `TreinoIcon.check` mapped to an appropriate Phosphor icon (e.g., `PhosphorIconsRegular.check` or `PhosphorIconsFill.check`).

If the constant already exists under a different name, the apply phase MUST use the existing constant and document the mapping; it MUST NOT add a duplicate.

No `PhosphorIcons.*` direct usage appears in any new `public_profile_*` widget file.

#### Scenarios

**SCENARIO-236** — `TreinoIcon.check` is a valid `IconData`
- GIVEN the constant `TreinoIcon.check` is referenced
- WHEN `Icon(TreinoIcon.check)` is pumped inside `_wrap(...)`
- THEN no exception is thrown

---

## Constraint Summary

| Constraint | Enforced by |
|---|---|
| No `Scaffold` / `AppBackground` / `SafeArea` in `PublicProfileScreen` | REQ-PROFILE-SCREEN-001 (SCENARIO-207) |
| No HEX literals in any new file | Design review — grep before merge |
| No `PhosphorIcons.*` direct usage in new widget files | REQ-PROFILE-ICON-001 + design review |
| `PostAvatar` reused (not duplicated) with `size: 96` in hero | REQ-PROFILE-HERO-001 (SCENARIO-210) |
| All new providers in `public_profile_providers.dart` — NOT in `friendship_providers.dart` or `feed_screen_providers.dart` | REQ-PROFILE-PROVIDER-001, 002, 003 (file location) |
| `friendship_providers.dart`, `feed_screen_providers.dart`, `post_card.dart` NOT modified (except `post_card.dart` if `onAuthorTap` wire is needed at apply time — but the prop already exists) | Scope boundary from proposal |
| `_ProfileTabPills` does NOT import from `feed_segment_pills.dart` | REQ-PROFILE-TABS-001 |
| Stats row values are hardcoded `0` (not `--`) with stub comment | REQ-PROFILE-STATS-001 (SCENARIO-217) |
| `isSelf: true` hides follow/message row entirely | REQ-PROFILE-SCREEN-002 (SCENARIO-208) |
| `getByPair` uses `Friendship.sortedDocId` — not a custom ID | REQ-PROFILE-REPO-001 (SCENARIO-192) |
| `PublicProfileView` has no `fromJson`/`toJson` (internal view-model) | REQ-PROFILE-DTO-001 |
| No new Flutter/Dart deps in `pubspec.yaml` | Global constraint (proposal §3) |
| `gymNameFromId` utility extracted to `lib/features/feed/domain/gym_name.dart` | REQ-PROFILE-HERO-001 |
| TDD order: test file committed BEFORE production code in every work-unit | Enforced by tasks phase |
| All pre-existing tests remain green | Scope boundary — no existing contracts changed |

---

## Deferred / Out of scope

The following items are explicitly NOT requirements for this change:

- `@handle` field — does not exist in any model; omitted per locked decision 7
- Real stats data — hardcoded `0` is the contract; real values are Fase 4
- RUTINAS PÚBLICAS tab with real routine data — Fase 5
- ACTIVIDAD tab with real activity data — Fase 4
- MENSAJE button functional — Fase 5 (Coach chat)
- Unfollow action — Fase 5
- `users_public/{uid}` sidecar collection — Approach B, not in scope
- Hero background photo — no data source in model; gradient is the contract
- Verified badge — `Post.authorVerified` does not exist
- Bio field — does not exist in `UserProfile`
- `@handle` in hero subtitle — not in any model
- Skeleton loading shimmer
- Deep link / share profile
- Block / report user
- Changes to `firestore.rules`
- Changes to `lib/features/workout/`, `lib/features/home/`, `lib/features/auth/`, `lib/features/coach/`
- Ranking, Retos, Missions, Bets, Gamification (global out-of-scope per `CLAUDE.md`)

---

## Files this spec covers

### New files

| File | REQs |
|---|---|
| `lib/features/feed/domain/public_profile_view.dart` | DTO-001 |
| `lib/features/feed/domain/gym_name.dart` | HERO-001 |
| `lib/features/feed/application/public_profile_providers.dart` | PROVIDER-001, 002, 003 |
| `lib/features/feed/presentation/public_profile_screen.dart` | SCREEN-001, 002, TABS-001, 002, FOLLOW-002, WIRE-001 |
| `lib/features/feed/presentation/widgets/public_profile_hero.dart` | HERO-001 |
| `lib/features/feed/presentation/widgets/public_profile_stats_row.dart` | STATS-001 |
| `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` | FOLLOW-001 |
| `test/features/feed/data/friendship_repository_get_by_pair_test.dart` | REPO-001 (SCENARIO-190..192) |
| `test/features/feed/application/public_profile_providers_test.dart` | PROVIDER-001..003 (SCENARIO-193..203) |
| `test/features/feed/presentation/public_profile_screen_test.dart` | SCREEN-001..002, TABS-001..002, FOLLOW-002, NAV-001 (SCENARIO-204..233, 235) |
| `test/features/feed/presentation/widgets/public_profile_hero_test.dart` | HERO-001 (SCENARIO-210..215) |
| `test/features/feed/presentation/widgets/public_profile_stats_row_test.dart` | STATS-001 (SCENARIO-216..218) |
| `test/features/feed/presentation/widgets/public_profile_follow_button_test.dart` | FOLLOW-001 (SCENARIO-219..226) |

### Modified files

| File | Change | REQs |
|---|---|---|
| `lib/features/feed/data/friendship_repository.dart` | Add `getByPair` method | REPO-001 |
| `lib/app/router.dart` | Add nested `GoRoute(path: 'profile/:uid', ...)` under `/feed` | ROUTE-001 |
| `lib/core/widgets/treino_icon.dart` | Add `TreinoIcon.check` if not present | ICON-001 |
| `lib/features/feed/feed_screen.dart` | CONDITIONAL wire of `onAuthorTap` callback | WIRE-001 |

### NOT modified (scope boundary)

- `lib/features/feed/application/friendship_providers.dart`
- `lib/features/feed/application/feed_screen_providers.dart`
- `lib/features/feed/presentation/widgets/post_card.dart` (the `onAuthorTap` prop already exists; no structural change)
- `lib/features/feed/presentation/widgets/feed_segment_pills.dart`
- `lib/features/feed/domain/post.dart`
- `lib/features/feed/domain/friendship.dart`
- `firestore.rules`
- `pubspec.yaml`

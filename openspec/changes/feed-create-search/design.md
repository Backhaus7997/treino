# Design — feed-create-search (Fase 3 · Etapa 5)

**Change**: `feed-create-search`
**Branch**: `feat/feed-create-search` (integration tracker; PRs chain off `main`)
**Owner**: Dev C
**Artifact store**: `hybrid`
**Predecessors**: `sdd/feed-create-search/explore` (#47), `sdd/feed-create-search/proposal` (#48)
**Sister precedent**: `openspec/changes/public-profile/design.md`
**TDD**: Strict — tests precede implementation in apply phase

This document is the implementation contract for two chained PRs. Each PR is a self-contained design with its own file map, API surface, widget tree, and ADRs. Cross-cutting decisions (branch chain, pattern reuse, style consistency) live in Section C.

Read order before apply: `proposal.md` → `spec.md` → this file.

---

## TL;DR

- **PR#1 (create-post)**: 1 new screen, 1 new notifier (`AsyncNotifier<CreatePostState>`), 2 modified files (`feed_screen.dart`, `router.dart`). State shape `{text, privacy, isSubmitting, errorMessage}`. Success = `pop()` + invalidate 3 feed providers. Gym pill DISABLED (not hidden) when `userProfile.gymId == null`. Routine chip is `onTap: null` stub.
- **PR#2 (search-users)**: 1 new screen, 1 new tile widget, 1 new `FutureProvider.family` (debounced in screen, 300ms), 1 new repo method, 1 freezed field addition (`displayNameLowercase`), 4 write-site updates (`UserRepository.getOrCreate`/`createIfAbsent`/`update` + `ProfileSetupNotifier.submit`). Search = case-insensitive prefix range, `limit(20)`, 2-char minimum.
- **ADR count**: 6 (PR#1) + 6 (PR#2) + 3 (cross-cutting) = **15**.

---

# SECTION A — Create Post Design (PR#1)

## A.1 File map

All paths absolute from repo root. Source under `lib/features/feed/`, tests mirror under `test/features/feed/`.

### New files (PR#1)

| Path | Action | Purpose | Approx LOC |
|---|---|---|---|
| `lib/features/feed/application/create_post_notifier.dart` | new | `CreatePostState` value + `CreatePostNotifier` (`AsyncNotifier<CreatePostState>`) + `createPostNotifierProvider` | ~110 |
| `lib/features/feed/presentation/create_post_screen.dart` | new | `CreatePostScreen` (`ConsumerWidget`) + private `_CreatePostHeader`, `_PrivacyPills`, `_RoutineTagStubChip` | ~190 |
| `test/features/feed/application/create_post_notifier_test.dart` | new | SCENARIO-CREATE-001..010 — initial state, setters, submit success, submit error, gym-privacy gate when gymId null | ~210 |
| `test/features/feed/presentation/create_post_screen_test.dart` | new | SCENARIO-CREATE-011..025 — render, char counter, validation, CANCELAR pop, PUBLICAR success path, error display, gym-pill disabled state | ~280 |

### Modified files (PR#1)

| Path | Action | Purpose | LOC delta |
|---|---|---|---|
| `lib/features/feed/feed_screen.dart` | modify | Wrap the plus `Container` (lines 64-76) in `GestureDetector` → `context.push('/feed/create')`. No structural change to `_FeedHeader`'s row. | +5 |
| `lib/app/router.dart` | modify | Add `GoRoute(path: 'create', ...)` nested under `/feed` + import `CreatePostScreen` | +7 |

### Explicitly NOT modified (PR#1)

- `lib/features/feed/data/post_repository.dart` — `create()` already exists and is sufficient.
- `lib/features/feed/domain/post.dart` — model already carries all required fields.
- `lib/features/feed/domain/post_privacy.dart` — enum already covers friends/gym/public.
- `lib/features/feed/application/post_providers.dart` — invalidations target existing providers; no new provider lives here.
- `lib/features/feed/application/feed_screen_providers.dart` — `myFriendsFeedProvider`, `myGymFeedProvider` already exist; we only invalidate them.

**Estimated PR#1 diff**: ~300 production LOC + ~490 test LOC ≈ ~790 total LOC. Production well within the 400-LOC PR budget.

---

## A.2 API signatures (PR#1)

### A.2.1 `CreatePostState` (immutable value)

```dart
import 'package:flutter/foundation.dart' show immutable;

import '../domain/post_privacy.dart';

@immutable
class CreatePostState {
  const CreatePostState({
    this.text = '',
    this.privacy = PostPrivacy.friends,
    this.isSubmitting = false,
    this.errorMessage,
  });

  final String text;
  final PostPrivacy privacy;
  final bool isSubmitting;
  final String? errorMessage;

  /// Derived: form is publishable.
  bool get canSubmit =>
      text.trim().isNotEmpty &&
      text.characters.length <= kMaxPostChars &&
      !isSubmitting;

  CreatePostState copyWith({
    String? text,
    PostPrivacy? privacy,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) =>
      CreatePostState(
        text: text ?? this.text,
        privacy: privacy ?? this.privacy,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );

  @override
  bool operator ==(Object other) => /* tuple equality on all 4 fields */;
  @override
  int get hashCode => Object.hash(text, privacy, isSubmitting, errorMessage);
}

/// 280-char Twitter parity (proposal Q6).
const int kMaxPostChars = 280;
```

Rationale: a hand-written `@immutable` class (not freezed) avoids a generated `.freezed.dart` for a UI-only ephemeral DTO. The notifier exposes only the fields needed by the screen; no Firestore serialization is needed.

### A.2.2 `CreatePostNotifier`

```dart
class CreatePostNotifier extends AsyncNotifier<CreatePostState> {
  @override
  Future<CreatePostState> build() async => const CreatePostState();

  // ---- Setters (sync; mutate state.value only) ----

  void setText(String value) {
    final current = state.valueOrNull ?? const CreatePostState();
    state = AsyncData(current.copyWith(text: value, clearError: true));
  }

  void setPrivacy(PostPrivacy value) {
    final current = state.valueOrNull ?? const CreatePostState();
    state = AsyncData(current.copyWith(privacy: value, clearError: true));
  }

  // ---- Submit ----

  /// Returns `true` if the post was created and feeds were invalidated.
  /// Returns `false` on validation error or write failure (state carries the message).
  Future<bool> submit() async {
    final current = state.valueOrNull ?? const CreatePostState();
    if (!current.canSubmit) return false;

    // Resolve viewer + profile defensively (auth-gate).
    final viewer = ref.read(authStateChangesProvider).valueOrNull;
    if (viewer == null) {
      state = AsyncData(current.copyWith(
        errorMessage: 'Necesitás estar autenticado.',
      ));
      return false;
    }
    final profile = ref.read(userProfileProvider).valueOrNull;

    // Defense-in-depth: gym-privacy without gym → reject inline (gym pill is
    // disabled in the UI, but a stale state could slip through).
    if (current.privacy == PostPrivacy.gym && (profile?.gymId == null)) {
      state = AsyncData(current.copyWith(
        errorMessage: 'Asociate a un gym para postear acá.',
      ));
      return false;
    }

    state = AsyncData(current.copyWith(isSubmitting: true, clearError: true));

    try {
      final input = Post(
        id: '',
        authorUid: viewer.uid,
        authorDisplayName: profile?.displayName ?? 'Anónimo',
        authorAvatarUrl: profile?.avatarUrl,
        authorGymId: profile?.gymId,
        text: current.text.trim(),
        routineTag: null,                 // stub in this etapa
        privacy: current.privacy,
        createdAt: DateTime.now().toUtc(),
      );
      await ref.read(postRepositoryProvider).create(input);

      // Invalidate the 3 feed providers so the new post shows on next read.
      ref.invalidate(myFriendsFeedProvider);
      ref.invalidate(feedPublicProvider);
      ref.invalidate(myGymFeedProvider);

      // Reset form state — next time the screen mounts it starts clean.
      state = const AsyncData(CreatePostState());
      return true;
    } catch (e) {
      state = AsyncData(current.copyWith(
        isSubmitting: false,
        errorMessage: 'No pudimos publicar tu post. Intentá de nuevo.',
      ));
      return false;
    }
  }
}

final createPostNotifierProvider =
    AsyncNotifierProvider<CreatePostNotifier, CreatePostState>(
  CreatePostNotifier.new,
);
```

Rationale: `AsyncNotifier` (not `Notifier`) because `submit()` is naturally async — the state surface needs `isSubmitting` AND the framework already gives us `AsyncValue` semantics for free. We do NOT use `AsyncValue.guard` because we want to surface a Spanish-localized error string (not the raw exception) and return a boolean to the caller for navigation.

### A.2.3 `CreatePostScreen`

```dart
class CreatePostScreen extends ConsumerWidget {
  const CreatePostScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref);
}
```

Rationale: no constructor params. State is owned by `createPostNotifierProvider`. The screen is the only consumer of the notifier — no need to family-key it.

### A.2.4 `_FeedHeader` wire change

The current `_FeedHeader` plus button is a `Container` with no `GestureDetector` (line 64-76). Wrap it:

```dart
// Replace lines 64-76 with:
GestureDetector(
  onTap: () => context.push('/feed/create'),
  behavior: HitTestBehavior.opaque,
  child: Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: palette.accent,
      shape: BoxShape.circle,
    ),
    child: Icon(TreinoIcon.plus, size: 20, color: palette.bg),
  ),
),
```

Add `import 'package:go_router/go_router.dart';` if not present (it already is — line 3 of `feed_screen.dart`). `_FeedHeader` becomes a `StatelessWidget` that uses `context.push` — no need to make it a `ConsumerWidget`.

### A.2.5 `router.dart` GoRoute addition

```dart
// Inside the /feed GoRoute's `routes:` list, alongside the existing
// 'profile/:uid' nested route:
GoRoute(
  path: 'create',
  pageBuilder: (_, __) => _noAnim(const CreatePostScreen()),
),
```

Plus the import: `import '../features/feed/presentation/create_post_screen.dart';`.

The route uses `_noAnim` to match the rest of the app's instant-transition convention. `/feed/create` resolves to the Feed tab index via the existing `_kTabs.indexWhere((t) => location.startsWith(t))` logic in `_ShellScaffold` (no `_kTabs` change needed).

---

## A.3 Widget composition tree (PR#1)

Notation: `[shell]` = produced by `_ShellScaffold` in `router.dart`. `[screen]` = produced inside `CreatePostScreen.build`. Spacing values use the allowed set `{8, 12, 14, 18, 20}` only.

### A.3.1 `CreatePostScreen` tree

```
[shell] Scaffold
[shell]   body: AppBackground
[shell]     SafeArea
[screen]       Column(crossAxisAlignment: stretch)
[screen]         _CreatePostHeader()                      // CANCELAR · NUEVO POST · PUBLICAR
[screen]         SizedBox(height: 14)
[screen]         Expanded(
[screen]           child: SingleChildScrollView(           // keyboard-safe
[screen]             padding: EdgeInsets.symmetric(horizontal: 20),
[screen]             child: Column(crossAxisAlignment: stretch, children: [
[screen]               _PostTextField(),                   // multiline, 280 max
[screen]               SizedBox(height: 8)
[screen]               _CharCounter()                      // "123 / 280" muted, right-aligned
[screen]               SizedBox(height: 20)
[screen]               _PrivacyLabel()                     // "VISIBILIDAD" Barlow Condensed muted
[screen]               SizedBox(height: 12)
[screen]               _PrivacyPills()                     // AMIGOS · MI GYM · PÚBLICO
[screen]               SizedBox(height: 8)
[screen]               if (gymId == null) _PrivacyHelperText()  // muted helper
[screen]               SizedBox(height: 20)
[screen]               _RoutineTagStubChip()               // ETIQUETAR RUTINA (disabled)
[screen]               SizedBox(height: 20)
[screen]               if (state.errorMessage != null) _InlineError(state.errorMessage!)
[screen]             ]),
[screen]           ),
[screen]         )
```

### A.3.2 `_CreatePostHeader` tree

```
Padding(EdgeInsets.symmetric(horizontal: 20, vertical: 18))
  Row(
    children: [
      _HeaderTextButton(label: 'CANCELAR', onTap: () => context.pop()),
      Spacer(),
      Text('NUEVO POST', style: titleStyle),     // Barlow Condensed 18 w700
      Spacer(),
      _HeaderPublishButton(
        label: 'PUBLICAR',
        isEnabled: state.canSubmit,
        isLoading: state.isSubmitting,
        onTap: () async {
          final ok = await ref.read(createPostNotifierProvider.notifier).submit();
          if (ok && context.mounted) context.pop();
        },
      ),
    ],
  )
```

Visual parity: header mirrors the shape of `_FeedHeader` (same horizontal 20 / vertical 18 padding, same uppercase Barlow Condensed) but with two CTAs flanking a centered title — establishes the modal-edit visual idiom.

### A.3.3 `_PrivacyPills` tree

```
Row(mainAxisSize: max)
  Expanded(child: _PrivacyPill(
    label: 'AMIGOS',
    isActive: privacy == PostPrivacy.friends,
    isEnabled: true,
    onTap: () => notifier.setPrivacy(PostPrivacy.friends),
  ))
  SizedBox(width: 12)
  Expanded(child: _PrivacyPill(
    label: 'MI GYM',
    isActive: privacy == PostPrivacy.gym,
    isEnabled: gymId != null,                  // KEY DISABLED LOGIC
    onTap: gymId == null ? null : () => notifier.setPrivacy(PostPrivacy.gym),
  ))
  SizedBox(width: 12)
  Expanded(child: _PrivacyPill(
    label: 'PÚBLICO',
    isActive: privacy == PostPrivacy.public,
    isEnabled: true,
    onTap: () => notifier.setPrivacy(PostPrivacy.public),
  ))
```

`_PrivacyPill` mirrors `FeedSegmentPills._Pill` shape EXACTLY (mint active fill + `palette.bgCard` inactive fill + `BorderRadius.circular(20)` + padding `horizontal: 18, vertical: 8`). When `isEnabled == false`, wrap the inner pill in `Opacity(opacity: 0.4)` (matches the `MENSAJE` button posture from Etapa 4). The widget is privately declared — does NOT import `feed_segment_pills.dart` (same isolation principle as `_ProfilePill` in Etapa 4).

### A.3.4 `_RoutineTagStubChip` tree

```
Opacity(opacity: 0.4)
  Container(
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: palette.bgCard,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: palette.border, width: 1),
    ),
    child: Row(mainAxisSize: min, children: [
      Icon(TreinoIcon.dumbbell, size: 14, color: palette.textMuted),
      SizedBox(width: 8),
      Text('ETIQUETAR RUTINA', style: chipLabelStyle),
    ]),
  )
```

`onTap` is `null` (not even wrapped in `GestureDetector`). Source comment: `// Stub: real routine picker wired in Fase 4 (workout cross-feature dep).`

---

## A.4 State management — submit flow

```
User taps PUBLICAR
  → notifier.submit()
    → if (!canSubmit) return false                    // text empty / too long / already submitting
    → if (viewer == null) errorMessage + return false  // auth-gate
    → if (privacy == gym && gymId == null) errorMessage + return false  // defense-in-depth
    → state = isSubmitting: true, clearError: true   // UI disables PUBLICAR, shows spinner
    → build Post(id: '', authorUid, authorDisplayName, ...)
    → postRepository.create(input)                    // existing method; returns persisted Post
    → invalidate myFriendsFeedProvider, feedPublicProvider, myGymFeedProvider
    → state = CreatePostState()                       // form resets
    → return true                                     // screen pops
  → if (ok && context.mounted) context.pop()         // back to /feed
```

The notifier owns ALL business logic. The screen's only job after tap is `await notifier.submit()` → branch on result. No `try/catch` in the screen — the notifier puts errors in `state.errorMessage`.

`PostRepository.create()` internally reads `users/{uid}.gymId` and overrides `authorGymId` with that value (see `post_repository.dart` lines 19-32). We still pass `authorGymId: profile?.gymId` from the notifier so the in-memory `Post` matches what gets persisted — defensive, in case the read fails.

---

## A.5 Provider invalidation list

Explicit invalidation after a successful `create()`:

| Provider | Why | Affects |
|---|---|---|
| `myFriendsFeedProvider` | Friends-privacy posts authored by the viewer go into their friends' feeds. The viewer ALSO sees their own friends-privacy posts in `myFriendsFeedProvider` if `feedForFriends(friendUids)` includes self. | `_AmigosBody` |
| `feedPublicProvider` | Public posts appear in `_PublicoBody` regardless of friendship. | `_PublicoBody` |
| `myGymFeedProvider` | Gym-privacy posts (and only gym-privacy) appear here for users whose `gymId` matches. | `_MiGymBody` |

We invalidate ALL THREE unconditionally (not just the one matching `privacy`) because:
1. Cheap — invalidation just marks dirty; the actual refetch is lazy when the segment becomes visible.
2. Defensive — if the user later switches segments, the data is fresh.
3. Matches the proposal Q8 decision: "No toast. New post appearing in feed IS the success signal."

---

## A.6 Edge cases (PR#1)

### A.6.1 Empty text

`text.trim().isEmpty` → `canSubmit == false` → PUBLICAR button is visually disabled (opacity 0.4) + `onTap: null`. No error message displayed (validation is silent — the disabled state is the signal).

### A.6.2 Char limit

`text.characters.length > 280` → `canSubmit == false`. The counter (`_CharCounter`) renders the count in `palette.accent` while ≤ 280, switches to `palette.danger` when > 280. We use `text.characters.length` (grapheme cluster count) not `text.length` (UTF-16 code unit count) so emoji and combined characters count correctly.

There is NO hard `maxLength` on the `TextField` — we count and display; the limit is enforced by `canSubmit`. This lets users see they're over and edit down rather than getting silently truncated.

### A.6.3 No-gym privacy guard

Two layers:
- **UI**: `_PrivacyPill(MI GYM)` has `isEnabled: gymId != null` → `onTap: null` + `Opacity(0.4)`. Helper text "Asociate a un gym para postear acá" renders ONLY when `gymId == null`. This is the proposal Q4 decision.
- **Notifier**: `submit()` checks `if (privacy == gym && gymId == null)` and rejects with the same Spanish error string. Defense-in-depth in case a stale state survives (e.g., gym deselected after privacy chosen).

### A.6.4 Error display

`state.errorMessage` renders inline at the bottom of the form body (NOT a snackbar — keeps the error scoped to the screen, dismissed on next input via `clearError: true` in setters).

```
Container(
  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  decoration: BoxDecoration(
    color: palette.danger.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: palette.danger.withValues(alpha: 0.4)),
  ),
  child: Text(errorMessage, style: errorTextStyle),  // palette.danger, Barlow 14
)
```

If `palette.danger` does not exist as a token, use `palette.accent` with adjusted alpha — verify the token in apply phase.

### A.6.5 Keyboard overlap

`SingleChildScrollView` wrapping the body lets the user scroll past the soft keyboard. The header (CANCELAR · NUEVO POST · PUBLICAR) stays anchored at the top (outside the scrollable) — so PUBLICAR is always reachable. Because `_ShellScaffold` already supplies the `Scaffold`, we cannot use `resizeToAvoidBottomInset` — `SingleChildScrollView` is the correct path.

### A.6.6 Double-tap PUBLICAR

`isSubmitting: true` → `canSubmit: false` → PUBLICAR `onTap` is null. The user cannot fire `create()` twice. The submit guard `if (!current.canSubmit) return false` is the second line of defense.

### A.6.7 CANCELAR with unsaved text

No confirmation dialog. Tapping CANCELAR pops immediately. The state is `autoDispose: false` on the notifier by default, so re-entering `/feed/create` later restores prior text — but since the notifier rebuilds the state to `const CreatePostState()` on successful submit, and the route disposes on pop... actually, the screen calls `ref.invalidate(createPostNotifierProvider)` on dispose to force a clean state next mount. Add this to `CreatePostScreen.build` via `ref.listen` or document the expectation that the user accepts loss-on-cancel.

**Decision**: do NOT auto-clear on cancel. The notifier persists state across navigations within the app lifetime — this is consistent with Riverpod's default. A user who taps CANCELAR by accident can reopen the screen and find their draft intact. This is a small UX win and matches the proposal Q8 minimalism ("the new post appearing IS the success signal").

---

## A.7 ADRs (PR#1)

### ADR-CP-001 — `AsyncNotifier<CreatePostState>` not `Notifier<CreatePostState>`

**Decision**: Use `AsyncNotifier`.
**Why**: `submit()` is naturally async (Firestore write + provider invalidations). `AsyncNotifier` gives us `AsyncValue` semantics for free, and the `isSubmitting` boolean inside state is a screen-level UI concern that maps cleanly to `state = AsyncData(state.value.copyWith(isSubmitting: true))`.
**Rejected**: `Notifier<CreatePostState>` would have required wiring a separate `isLoading` flag and manual error capture without `AsyncValue.guard`. More boilerplate, no win.
**Rejected**: `StateNotifier` — legacy API; this codebase already uses `AsyncNotifier` (see `AuthNotifier`).

### ADR-CP-002 — No confirmation dialog on CANCELAR

**Decision**: CANCELAR pops immediately. No "Discard draft?" dialog.
**Why**: Proposal Q8 explicitly minimizes success/feedback UX. Symmetric minimalism on the discard side. The state is not auto-cleared, so a user who taps CANCELAR by accident finds their text intact on next mount.
**Rejected**: AlertDialog confirmation — friction tax on the 99% of cancellations that are intentional, for a marginal recovery benefit (which we provide anyway via state persistence).

### ADR-CP-003 — No toast/snackbar on success

**Decision**: Success path is silent: `pop()` + invalidate. The new post visible in the feed IS the success signal.
**Why**: Proposal Q8 locked this. Toasts add overlay complexity, accessibility concerns (announce-or-not), and timing bugs (dismiss-during-navigation). The "post appears in list" pattern is universal in social apps and self-evident.
**Rejected**: `ScaffoldMessenger.of(context).showSnackBar(...)` — would require shell-aware messenger plumbing (we're inside `_ShellScaffold`, snackbars attach to the nearest Scaffold = the shell), plus async dismiss-vs-navigate races.

### ADR-CP-004 — Routine tag = `onTap: null` stub chip

**Decision**: Render a disabled chip (`Opacity(0.4)`, no `GestureDetector`) labelled "ETIQUETAR RUTINA". No picker, no behaviour.
**Why**: Proposal Q2. Real routine picker requires the `workout` feature, which is owned by another dev. Cross-feature dependency is deferred to Fase 4. The disabled chip signals "this is coming" without breaking the form.
**Rejected**: Hide entirely — misses the affordance, surprises users in Fase 4 when it appears.
**Rejected**: Real picker — out of scope; would push PR#1 past the budget and create coordination drag.

### ADR-CP-005 — Gym pill DISABLED (not HIDDEN) when no gymId

**Decision**: When `userProfile.gymId == null`, the MI GYM pill renders with `Opacity(0.4)` + `onTap: null` + helper text "Asociate a un gym para postear acá" below the pill row.
**Why**: Proposal Q4. Hidden pill = surprise; disabled pill = explicit gate with a CTA toward resolution. Mirrors the `MENSAJE` stub posture from Etapa 4 (visible, opacity-reduced, no-op).
**Rejected**: Hide pill — saves space but loses discoverability. Users would not realize gym posts exist as a category.
**Rejected**: Throw on submit — bad UX; the user already filled the form. Block at the input.

### ADR-CP-006 — Invalidate ALL THREE feed providers unconditionally

**Decision**: After every successful `create()`, invalidate `myFriendsFeedProvider`, `feedPublicProvider`, AND `myGymFeedProvider` regardless of the post's privacy.
**Why**: Invalidation is cheap (lazy refetch). The user may switch segments after publishing — fresh data on switch is the right default. Branching on privacy ("only invalidate matching") adds complexity for negligible gain.
**Rejected**: Invalidate only the matching provider — saves 2 lazy refetches but couples the notifier to privacy-routing logic that belongs in the providers themselves.

---

# SECTION B — Search Users Design (PR#2)

## B.1 File map

PR#2 depends on PR#1 being merged into `main` (both touch `_FeedHeader` and `router.dart`).

### New files (PR#2)

| Path | Action | Purpose | Approx LOC |
|---|---|---|---|
| `lib/features/feed/presentation/search_users_screen.dart` | new | `SearchUsersScreen` (`ConsumerStatefulWidget`, owns `TextEditingController` + debounce `Timer`) + private `_SearchUsersHeader` | ~170 |
| `lib/features/feed/presentation/widgets/user_search_result_tile.dart` | new | `UserSearchResultTile` (`StatelessWidget`) — avatar + name + gym subtitle | ~95 |
| `lib/features/feed/application/search_users_provider.dart` | new | `searchUsersProvider` (`FutureProvider.autoDispose.family<List<UserProfile>, String>`) + private `searchActiveQueryProvider` (`StateProvider<String>`) | ~50 |
| `test/features/profile/data/user_repository_search_test.dart` | new | SCENARIO-SEARCH-001..006 — prefix match, case-insensitive, limit 20, no matches, empty query, displayNameLowercase missing | ~120 |
| `test/features/feed/application/search_users_provider_test.dart` | new | SCENARIO-SEARCH-007..012 — debounce, 2-char min, family caching, error propagation | ~140 |
| `test/features/feed/presentation/widgets/user_search_result_tile_test.dart` | new | SCENARIO-SEARCH-013..017 — avatar, name, gym subtitle (3 branches), tap nav | ~110 |
| `test/features/feed/presentation/search_users_screen_test.dart` | new | SCENARIO-SEARCH-018..028 — initial empty state, typing-below-min, loading, results render, empty-results, error, tap → push | ~210 |

### Modified files (PR#2)

| Path | Action | Purpose | LOC delta |
|---|---|---|---|
| `lib/features/profile/domain/user_profile.dart` | modify | Add `String? displayNameLowercase` freezed field. Re-run build_runner. | +1 (model) + ~40 (regen) |
| `lib/features/profile/data/user_repository.dart` | modify | Add `searchByDisplayName(String q) → Future<List<UserProfile>>`. Modify `getOrCreate` + `createIfAbsent` + `update` to write `displayNameLowercase`. | +30 |
| `lib/features/profile_setup/application/profile_setup_notifier.dart` | modify | In `submit()`, include `'displayNameLowercase': draft.username?.trim().toLowerCase()` in the partial map. | +1 |
| `lib/features/feed/feed_screen.dart` | modify | Wrap `Icon(TreinoIcon.search)` (line 62) in `GestureDetector` → `context.push('/feed/search')`. | +5 |
| `lib/app/router.dart` | modify | Add `GoRoute(path: 'search', ...)` nested under `/feed` + import `SearchUsersScreen`. | +7 |
| `test/features/profile/data/user_repository_test.dart` | modify (if exists) | Add assertions: existing methods now also write `displayNameLowercase`. | +20 |

### Explicitly NOT modified (PR#2)

- `lib/features/feed/data/post_repository.dart` — search is on users, not posts.
- `lib/features/feed/presentation/widgets/post_avatar.dart` — reused as-is in the tile.
- `lib/features/feed/presentation/widgets/feed_empty_state.dart` — reused for empty/no-results states.
- `lib/app/theme/app_palette.dart` — no new tokens needed.

**Estimated PR#2 diff**: ~365 production LOC + ~600 test LOC ≈ ~965 total LOC.

**Budget warning**: production LOC slightly over 400 (~365 + generated ~40 = ~405). The proposal Review Workload Forecast flagged this; the cross-cutting Section C.1 below documents the chained-PR resolution. If at apply time the diff exceeds 400, sdd-tasks will sub-split into PR#2a (model + repo + ProfileSetup write) and PR#2b (screen + tile + provider + wire).

---

## B.2 API signatures (PR#2)

### B.2.1 `UserProfile.displayNameLowercase` (freezed addition)

```dart
@freezed
class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String uid,
    required String email,
    required String? displayName,
    String? displayNameLowercase,                  // NEW — nullable for backward compat
    required UserRole role,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() required DateTime updatedAt,
    String? gymId,
    // ...rest unchanged
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, Object?> json) =>
      _$UserProfileFromJson(json);
}
```

Notes:
- Nullable — legacy docs in Firestore lack the field; `fromJson` will hydrate it as `null`. The search query returns no rows for those users until they update (lazy backfill — proposal Q9).
- Field is placed AFTER `displayName` in the parameter list (not `required`) so it does not break existing `UserProfile(...)` calls in tests. Re-run `dart run build_runner build --delete-conflicting-outputs` after the change.

### B.2.2 `UserRepository.searchByDisplayName`

```dart
/// Case-insensitive prefix search on `displayNameLowercase`.
///
/// Returns up to 20 users whose lowercased display name starts with [q].
/// Empty list when [q] is empty or whitespace-only (caller is expected to
/// gate at the screen; this is defense-in-depth).
///
/// Uses the Unicode high-codepoint trick (``) to bound the prefix range:
/// `[lower, lower + '')`. Firestore's lexicographic range matches any
/// string starting with `lower`.
Future<List<UserProfile>> searchByDisplayName(String q) async {
  final lower = q.trim().toLowerCase();
  if (lower.isEmpty) return const [];

  final snap = await _users
      .where('displayNameLowercase', isGreaterThanOrEqualTo: lower)
      .where('displayNameLowercase', isLessThan: '$lower')
      .limit(20)
      .get();

  return snap.docs
      .map((d) => UserProfile.fromJson({...d.data(), 'uid': d.id}))
      .toList();
}
```

Notes:
- `` is the Unicode Private Use Area highest reliably-supported codepoint and is the canonical Firestore prefix-range trick.
- We use `{...d.data(), 'uid': d.id}` because the `users/{uid}` docs DO carry `uid` in the body (current `getOrCreate` writes it via `profile.toJson()`), but injecting `'uid': d.id` is defensive — same posture as `PostRepository._fromDoc`.
- Filter on `displayNameLowercase` requires a single-field index, which Firestore creates automatically. No `firestore.indexes.json` change.

### B.2.3 Write-site updates for `displayNameLowercase`

**`UserRepository.getOrCreate`** (currently lines 21-38):
```dart
final profile = UserProfile(
  uid: uid,
  email: email,
  displayName: null,
  displayNameLowercase: null,                    // NEW (explicit)
  role: UserRole.athlete,
  // ...
);
```
No-op for the initial doc because `displayName` is null. When ProfileSetup runs `update()` later, the lowercased value is written then.

**`UserRepository.createIfAbsent`** (currently lines 43-59): same addition as `getOrCreate`.

**`UserRepository.update`** (currently lines 70-75): add lazy backfill on every update:
```dart
Future<void> update(String uid, Map<String, Object?> partial) async {
  final sanitized = Map<String, Object?>.fromEntries(
    partial.entries.where((e) => !_immutableFields.contains(e.key)),
  )..['updatedAt'] = Timestamp.fromDate(DateTime.now().toUtc());

  // Lazy backfill: if caller writes displayName, derive displayNameLowercase.
  // Caller may also pass `displayNameLowercase` explicitly (e.g. from ProfileSetup
  // submit) — explicit value wins.
  if (partial.containsKey('displayName') &&
      !partial.containsKey('displayNameLowercase')) {
    final dn = partial['displayName'] as String?;
    sanitized['displayNameLowercase'] = dn?.trim().toLowerCase();
  }

  await _users.doc(uid).set(sanitized, SetOptions(merge: true));
}
```

**`ProfileSetupNotifier.submit`** (currently line 134-142): add to the partial map:
```dart
final partial = <String, Object?>{
  'displayName': draft.username?.trim(),
  'displayNameLowercase': draft.username?.trim().toLowerCase(),  // NEW
  'gymId': draft.gymId == kNoGymId ? null : draft.gymId,
  // ...rest unchanged
};
```

This means the field is written from **both** ProfileSetup (explicit) and `UserRepository.update` (lazy derive). The derive is a no-op when ProfileSetup writes explicitly (the `containsKey` guard in `update` skips it). For ANY other caller that ever updates `displayName` without computing the lowercase variant, the repo handles it automatically. Future-proof.

### B.2.4 `searchUsersProvider`

```dart
/// Returns up to 20 users matching the trimmed lowercased prefix [query].
/// Empty query or trimmed length < 2 → returns const [] WITHOUT calling
/// the repo. Caller is the screen, which already gates on length — this is
/// defense-in-depth.
final searchUsersProvider = FutureProvider.autoDispose
    .family<List<UserProfile>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.length < kSearchMinChars) return const [];
  return ref.watch(userRepositoryProvider).searchByDisplayName(trimmed);
});

const int kSearchMinChars = 2;
```

`autoDispose` because the family key (query string) grows unbounded as the user types — without `autoDispose`, every keystroke leaves a stale cache entry. The screen's debounce mechanism (see B.4.2) limits how often a NEW query string is read, so the cache churn is bounded by debounce frequency, not keystroke frequency.

### B.2.5 `SearchUsersScreen`

```dart
class SearchUsersScreen extends ConsumerStatefulWidget {
  const SearchUsersScreen({super.key});

  @override
  ConsumerState<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends ConsumerState<SearchUsersScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _activeQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _activeQuery = value);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) { /* … */ }
}
```

Rationale for `ConsumerStatefulWidget` (not `ConsumerWidget`): the debounce `Timer` and `TextEditingController` need a lifecycle. We could use `useEffect` from flutter_hooks but the codebase does not use hooks elsewhere — stay consistent with `StatefulWidget`.

### B.2.6 `UserSearchResultTile`

```dart
class UserSearchResultTile extends StatelessWidget {
  const UserSearchResultTile({
    super.key,
    required this.user,
    required this.onTap,
  });

  final UserProfile user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context);
}
```

Rationale: passes the full `UserProfile` (we need `uid`, `displayName`, `avatarUrl`, `gymId`). `onTap` is required and resolved by the parent (`SearchUsersScreen`) to `() => context.push('/feed/profile/${user.uid}')` — the tile itself does not import `go_router`, keeping it trivially testable in isolation.

### B.2.7 `_FeedHeader` wire change (PR#2)

Wrap the search icon (line 62 in current `feed_screen.dart`):

```dart
GestureDetector(
  onTap: () => context.push('/feed/search'),
  behavior: HitTestBehavior.opaque,
  child: Icon(TreinoIcon.search, size: 20, color: palette.textMuted),
),
```

### B.2.8 `router.dart` GoRoute addition (PR#2)

Inside the `/feed` GoRoute's `routes:`, alongside `'create'` (from PR#1) and `'profile/:uid'`:

```dart
GoRoute(
  path: 'search',
  pageBuilder: (_, __) => _noAnim(const SearchUsersScreen()),
),
```

Plus import `import '../features/feed/presentation/search_users_screen.dart';`.

---

## B.3 Widget composition tree (PR#2)

### B.3.1 `SearchUsersScreen` tree

```
[shell] Scaffold > AppBackground > SafeArea
[screen]   Column(crossAxisAlignment: stretch)
[screen]     _SearchUsersHeader()                       // VOLVER · BUSCAR USUARIOS · (spacer)
[screen]     SizedBox(height: 14)
[screen]     Padding(horizontal: 20)
[screen]       _SearchTextField(controller, onChanged)  // pill-shaped, mint border on focus
[screen]     SizedBox(height: 14)
[screen]     Expanded(
[screen]       child: _SearchBody(activeQuery)          // switches on state machine (B.5)
[screen]     )
```

### B.3.2 `_SearchUsersHeader` tree

```
Padding(EdgeInsets.symmetric(horizontal: 20, vertical: 18))
  Row(children: [
    GestureDetector(
      onTap: () => context.pop(),
      behavior: HitTestBehavior.opaque,
      child: Row(mainAxisSize: min, children: [
        Icon(TreinoIcon.chevronLeft, size: 18, color: palette.textPrimary),
        SizedBox(width: 8),
        Text('VOLVER', style: navLabelStyle),         // Barlow Condensed 14 w600
      ]),
    ),
    Spacer(),
    Text('BUSCAR USUARIOS', style: titleStyle),       // Barlow Condensed 18 w700
    Spacer(),
    SizedBox(width: 70),                              // visual balance vs VOLVER block
  ])
```

### B.3.3 `_SearchBody` tree (state machine — see B.5)

```
switch (state) {
  initial             → FeedEmptyState(message: 'Buscá usuarios por nombre.')
  typing-below-min    → FeedEmptyState(message: 'Escribí al menos 2 caracteres.')
  loading             → Center(child: CircularProgressIndicator(color: palette.accent))
  data (list)         → ListView.separated(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          itemCount: results.length,
                          separatorBuilder: (_, __) => SizedBox(height: 14),
                          itemBuilder: (_, i) => UserSearchResultTile(
                            user: results[i],
                            onTap: () => context.push('/feed/profile/${results[i].uid}'),
                          ),
                        )
  empty-results       → FeedEmptyState(message: 'Sin resultados para "$query".')
  error               → Padding(horizontal: 20, child: Text('No pudimos buscar. Intentá de nuevo.', errorStyle))
}
```

### B.3.4 `UserSearchResultTile` tree

```
GestureDetector(onTap: onTap, behavior: opaque)
  Container(
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: palette.bgCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: palette.border, width: 1),
    ),
    child: Row(children: [
      PostAvatar(
        authorDisplayName: user.displayName ?? 'Anónimo',
        authorAvatarUrl: user.avatarUrl,
        size: 40,
      ),
      SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: start, children: [
          Text(
            (user.displayName ?? 'Anónimo').toUpperCase(),
            style: nameStyle,                       // Barlow Condensed 16 w700
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          if (gymNameFromId(user.gymId).isNotEmpty) ...[
            SizedBox(height: 8),
            Text(
              gymNameFromId(user.gymId),
              style: gymStyle,                       // Barlow 12 muted
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ],
        ]),
      ),
      Icon(TreinoIcon.chevronRight, size: 16, color: palette.textMuted),
    ]),
  )
```

Note: `gymNameFromId` was introduced in Etapa 4 (`lib/features/feed/domain/gym_name.dart`). Reused as-is — same return contract (`''` for null/empty/`'no-gym'`).

---

## B.4 Query strategy details

### B.4.1 Firestore range query exact code

See `searchByDisplayName` in B.2.2. The two `.where()` clauses bound the prefix range; `` is the canonical end-marker. Firestore requires a single-field index on `displayNameLowercase` — auto-created on first query.

### B.4.2 Debounce mechanism

**Choice: Approach B — `Timer` inside the screen widget**, which calls `setState` to update `_activeQuery`. The screen `ref.watch`es `searchUsersProvider(_activeQuery)`. Each NEW `_activeQuery` value is a new family key → new fetch.

```dart
void _onChanged(String value) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 300), () {
    if (!mounted) return;
    setState(() => _activeQuery = value);
  });
}
```

**Why Approach B over Approach A** (debounce inside the provider via `Future.delayed` + `ref.onDispose`):
- Approach A would require the provider to know about debounce timing, which couples a presentation concern (rapid typing) to a data concern (fetching users).
- Approach A cancellation depends on `ref.onDispose` firing when the family key changes — which it does (`autoDispose` family), but the firing happens DURING the dispose phase, which makes timer cancellation in tests harder to reason about (you have to simulate provider key changes).
- Approach B's `Timer` is plain Dart, trivially testable with `tester.pump(Duration(milliseconds: 300))`.
- Approach B keeps the provider pure and family-cacheable: hitting the same query twice (e.g., user types "ma" then "mar" then "ma" again) returns the cached `searchUsersProvider('ma')` result without re-fetching.

### B.4.3 Min query length guard

Two layers (matches the create-post gym-pill posture — UI + notifier):

1. **Screen**: `_activeQuery.trim().length < 2` → don't watch the provider, render `typing-below-min` state directly.
2. **Provider**: `if (trimmed.length < kSearchMinChars) return const []` — defense-in-depth in case some other caller triggers the family directly.

The screen renders the user-friendly empty state ("Escribí al menos 2 caracteres"). The provider just returns empty silently.

### B.4.4 Limit 20 results

Hardcoded in `searchByDisplayName.limit(20)`. No paging UI in this etapa. If the user has 21+ matches, the 21st onward is silently dropped — they refine the query. This is a deliberate MVP trade-off (proposal §4 implicit; explore §7).

---

## B.5 State machine — search states

The screen renders one of six states based on `(_activeQuery, asyncResults)`:

| State | Condition | Render |
|---|---|---|
| `initial` | `_activeQuery.trim().isEmpty` | `FeedEmptyState(message: 'Buscá usuarios por nombre.')` |
| `typing-below-min` | `0 < _activeQuery.trim().length < 2` | `FeedEmptyState(message: 'Escribí al menos 2 caracteres.')` |
| `loading` | `_activeQuery.trim().length >= 2 && async.isLoading` | spinner |
| `data` (non-empty) | `async.hasValue && async.value!.isNotEmpty` | `ListView` of tiles |
| `empty-results` | `async.hasValue && async.value!.isEmpty && _activeQuery.trim().length >= 2` | `FeedEmptyState(message: 'Sin resultados para "$query".')` |
| `error` | `async.hasError` | inline Text in `palette.textMuted` |

Resolution code sketch (inside `_SearchBody.build`):

```dart
final query = activeQuery.trim();
if (query.isEmpty) return _initial();
if (query.length < kSearchMinChars) return _belowMin();

final async = ref.watch(searchUsersProvider(query));
return async.when(
  loading: () => _loading(),
  error: (_, __) => _error(),
  data: (users) => users.isEmpty ? _emptyResults(query) : _resultsList(users),
);
```

Note: the spinner only appears while the active query is >= 2 chars AND the provider has not yet resolved. Because the debounce is in the screen layer, the spinner does NOT flash on every keystroke — only after 300ms of inactivity at >= 2 chars.

---

## B.6 Migration plan for `displayNameLowercase`

### B.6.1 Write sites

| Site | When | What it writes |
|---|---|---|
| `UserRepository.getOrCreate` | First-time signup (called by `AuthService.signUpWithEmail`) | `displayNameLowercase: null` (because `displayName: null`) |
| `UserRepository.createIfAbsent` | Sign-in backfill if doc missing | `displayNameLowercase: null` |
| `UserRepository.update` (lazy derive) | ANY caller updating the partial map | If partial contains `displayName` and not `displayNameLowercase`, derive `.toLowerCase()` automatically |
| `ProfileSetupNotifier.submit` (explicit) | When user completes Step 1 of ProfileSetup | `displayNameLowercase: draft.username?.trim().toLowerCase()` (explicit; redundant with the lazy derive but defensive) |

### B.6.2 Backfill strategy

**No script.** Existing users in production (if any — this is Etapa 5 of Fase 3 of a pre-launch app) without `displayNameLowercase` will:
- Have `null` on read (`fromJson` resolves missing field to `null` via the nullable type).
- Not appear in search results (the range query excludes documents where the field is null or doesn't exist).
- Backfill themselves the next time `update()` is called for them — e.g., when they edit any profile field.

The proposal accepted this trade-off (Q9 + Risks row 1). No Cloud Function, no admin script, no offline migration.

### B.6.3 Test fixtures

All tests that seed `users` collections with a `UserProfile` MUST also populate `displayNameLowercase`. Where the constructor is called directly:

```dart
UserProfile(
  uid: 'u1',
  email: 'u1@test.com',
  displayName: 'Martin',
  displayNameLowercase: 'martin',                  // REQUIRED in test seeds
  role: UserRole.athlete,
  createdAt: now,
  updatedAt: now,
)
```

Existing test fixture files that construct `UserProfile` (find via `rg 'UserProfile\(' test/`) must be updated to add the new field. Because the field is nullable, the changes are non-breaking — tests that don't search by name can pass `null` or omit it (it defaults to absent). Tests that ASSERT search behavior MUST populate it.

A test helper would be ideal:

```dart
// test/_support/user_profile_factory.dart (NEW — optional, only if many fixtures collide)
UserProfile fakeUser({
  required String uid,
  required String displayName,
  String? gymId,
}) => UserProfile(
  uid: uid,
  email: '$uid@test.com',
  displayName: displayName,
  displayNameLowercase: displayName.toLowerCase(),
  role: UserRole.athlete,
  createdAt: DateTime.utc(2025, 1, 1),
  updatedAt: DateTime.utc(2025, 1, 1),
  gymId: gymId,
);
```

sdd-tasks will decide whether to add this helper based on actual collision count during apply.

---

## B.7 Edge cases (PR#2)

### B.7.1 Empty query

Initial mount: `_activeQuery == ''` → `initial` state. Provider is not watched. No Firestore read.

### B.7.2 Whitespace-only query

`'   '.trim().isEmpty == true` → falls into `initial` state. The trim happens both in `_SearchBody` (for state classification) AND inside `searchUsersProvider` (defensive). Spaces in the middle of a query (e.g., `"ana m"`) are preserved (the prefix query still works against `displayNameLowercase` which is the user's full display name lowercased).

### B.7.3 Network error

Provider throws → `async.hasError` → render `error` state. The Spanish text is generic ("No pudimos buscar. Intentá de nuevo.") because Firestore errors do not have user-facing equivalents in this codebase's vocabulary.

### B.7.4 No results

`async.hasValue && async.value!.isEmpty && query.length >= 2` → render `empty-results` with the query echoed back. The echo helps users realize a typo (e.g., `"Marfin"` returning nothing tells them to check).

### B.7.5 User taps a result tile

`onTap` → `context.push('/feed/profile/${user.uid}')`. Navigates to the public profile screen (Etapa 4). On `pop()`, returns to the search screen with the query intact (state preserved on the controller).

### B.7.6 User searches, then opens a profile, then comes back

The `SearchUsersScreen` is NOT auto-disposed (it's pushed, not popped, when navigating to profile). Its state (`_activeQuery`, `_controller`) is preserved. `searchUsersProvider(activeQuery)` is `autoDispose.family` — the cache entry for that exact query is released when no consumers remain. When the user returns, the screen re-watches → re-fetches. This is acceptable — a stale-then-fresh refetch on return is good UX.

### B.7.7 User who never set displayName

A user whose `UserProfile.displayName == null` (post-signup, pre-ProfileSetup) has `displayNameLowercase == null`. They do NOT appear in search. This is correct behavior — they have nothing to be found by.

### B.7.8 Case-sensitive collision

Two users `"Martin"` and `"martin"` both produce `displayNameLowercase == 'martin'`. Both appear in search. Display order is Firestore's natural insertion order (no explicit `orderBy` in the query). MVP — no de-dup, no merge.

---

## B.8 ADRs (PR#2)

### ADR-SR-001 — `displayNameLowercase` is nullable, written on every `displayName` mutation

**Decision**: Add `String? displayNameLowercase` to `UserProfile`. Write it in 4 sites (3 repo methods + 1 ProfileSetup submit). Lazy backfill via `UserRepository.update` whenever `displayName` is in the partial.
**Why**: Case-sensitive prefix search is unusable UX. Adding a normalized field is the cheapest path with Firestore's query model. Nullable for backward compatibility — existing docs that lack the field still hydrate; they just don't appear in search until they update their profile.
**Rejected**: Required + backfill script — coordination cost across devs + production deploy concerns + we're pre-launch.
**Rejected**: Use `displayName` directly (case-sensitive prefix) — fails the "Martin" vs "martin" test; explored and rejected (explore §7, Option 1).
**Rejected**: Algolia/Typesense — infra overhead unjustified at MVP scale (explore §7, Option 3).

### ADR-SR-002 — Debounce in screen (`Timer`), not in provider (`Future.delayed`)

**Decision**: Debounce 300ms inside `_SearchUsersScreenState` via `Timer`. The provider has NO debounce.
**Why**: Keeps the provider pure (a function of query string → results). The provider's family cache works correctly (repeated queries are memoized). Tests can pump time forward predictably.
**Rejected**: `Future.delayed` inside the provider — couples presentation timing to data layer; makes the provider non-deterministic in tests.
**Rejected**: `useDebounced` hook — would require adding `flutter_hooks` to the project. Not used elsewhere in this codebase.

### ADR-SR-003 — Limit 20 results, no paging

**Decision**: Hardcoded `.limit(20)` in `searchByDisplayName`. No infinite scroll, no "load more" CTA.
**Why**: MVP scope. With prefix-only search, 20 results is plenty for refining a query — if a prefix matches 21+ users, the user types more characters. Paging adds notable complexity (cursor management + UI affordance) for marginal value at current scale.
**Rejected**: Unlimited — read cost explodes if a popular prefix matches hundreds. Bad client perf.
**Rejected**: Cursor pagination with sentinel scroll — out of scope; defer.

### ADR-SR-004 — `` for prefix range end-marker

**Decision**: `where('displayNameLowercase', isLessThan: '$lower')`.
**Why**: Canonical Firestore pattern. `` is in the Private Use Area near the top of the BMP — any normal display name lowercased will sort BEFORE it. Matches Firebase community documentation and prior art in similar Flutter Firestore apps.
**Rejected**: `'$lower~'` (the proposal's tilde example) — fails for names containing characters that sort after `~` (any non-ASCII letter — e.g., `ñ`, accented chars in Spanish names). `` is safer for an i18n-realistic dataset.
**Rejected**: Suffix-OR query — not supported by Firestore.

### ADR-SR-005 — No inline follow button in result tiles

**Decision**: `UserSearchResultTile` has NO follow button. Tap → navigate to public profile (where the follow button lives).
**Why**: Proposal Q5. Each follow button requires a `friendshipByPair` lookup → N Firestore reads per result page. For a 20-result page, that's 20 extra round-trips. The public profile already surfaces the action — one extra tap, no read explosion.
**Rejected**: Inline button with batched `friendshipByPair` — Firestore `whereIn` is limited to 10 + needs the deterministic doc IDs; doable but complex for marginal UX gain.
**Rejected**: Cached follow-state in user doc — denormalization across N-N relationships is the wrong model.

### ADR-SR-006 — Wait for PR#1 to merge before opening PR#2

**Decision**: Chained PRs. PR#2 branch (`feat/feed-search-users`) is created off `main` AFTER `feat/feed-create-post` merges.
**Why**: Both PRs touch `_FeedHeader` (`feed_screen.dart`) and `router.dart`. Parallel branches will conflict on these exact lines. Chaining serializes the conflict away.
**Rejected**: Stacked PRs (PR#2 off PR#1's branch) — possible but adds rebase pain when PR#1 receives review feedback. Cost > benefit for a 2-PR chain.
**Rejected**: Single combined PR with `size:exception` — proposal Q10 rejected this (~597 prod LOC > 400 budget; "two reviewable slices > one size:exception").

---

# SECTION C — Cross-cutting Design Decisions

## C.1 Branch chain mechanics

```
main (a4780d4)
  │
  ├─ feat/feed-create-post     ← PR#1 (Section A)
  │     └─ merges to main
  │
  ├─ feat/feed-search-users    ← PR#2 (Section B) — created AFTER PR#1 lands
  │     └─ merges to main
  │
  └─ feat/feed-create-search   ← integration tracker (this branch);
                                  used for sdd-archive consolidation only
```

Mechanics:
1. **PR#1**: Create `feat/feed-create-post` off `main` at the current `a4780d4`. Implement Section A. Open PR. Merge.
2. **PR#2**: After PR#1 lands on `main`, create `feat/feed-search-users` off the NEW `main` HEAD. Implement Section B. Open PR. Merge.
3. **Archive**: After both PRs merge, `sdd-archive` runs against the integration tracker branch (`feat/feed-create-search`) to consolidate the change record. The tracker branch never directly produces a PR.

If reviewer feedback on PR#1 changes the `_FeedHeader` wire pattern: PR#2 must rebase on the post-merge `main` and adjust its own wire to match. This is normal serialized-chain mechanics.

## C.2 TDD order per PR

Both PRs run under Strict TDD. Per artifact, the test file is committed RED first; production code follows and turns it GREEN.

### PR#1 order

| # | Step | Test | Production |
|---|---|---|---|
| 1 | `CreatePostState` value + `CreatePostNotifier` (setters only) | `create_post_notifier_test.dart` (initial + setters) | `create_post_notifier.dart` |
| 2 | `CreatePostNotifier.submit` (success path) | `create_post_notifier_test.dart` (submit + invalidate) | `create_post_notifier.dart` (+ submit) |
| 3 | `CreatePostNotifier.submit` (error + auth-gate + gym-gate) | `create_post_notifier_test.dart` (3 error branches) | `create_post_notifier.dart` (+ guards) |
| 4 | `CreatePostScreen` render + char counter | `create_post_screen_test.dart` (render, counter, gym-disabled) | `create_post_screen.dart` |
| 5 | `CreatePostScreen` CANCELAR / PUBLICAR flows | `create_post_screen_test.dart` (nav, error display) | `create_post_screen.dart` (+ wires) |
| 6 | Router + `_FeedHeader` wire | (covered by screen integration test in step 5) | `router.dart` + `feed_screen.dart` |
| 7 | Quality gates | — | `flutter analyze`, `dart format .`, `flutter test` |

### PR#2 order

| # | Step | Test | Production |
|---|---|---|---|
| 1 | `UserProfile.displayNameLowercase` field | (covered indirectly by repo test) | `user_profile.dart` + `dart run build_runner build --delete-conflicting-outputs` |
| 2 | `UserRepository.searchByDisplayName` | `user_repository_search_test.dart` (5 scenarios) | `user_repository.dart` (+ method) |
| 3 | `UserRepository` write-site updates (`getOrCreate`, `createIfAbsent`, `update` lazy derive) | `user_repository_test.dart` (add 3 assertions) | `user_repository.dart` (+ writes) |
| 4 | `ProfileSetupNotifier.submit` writes `displayNameLowercase` | `profile_setup_notifier_test.dart` (add assertion) | `profile_setup_notifier.dart` (+ partial map) |
| 5 | `searchUsersProvider` (2-char gate + family caching) | `search_users_provider_test.dart` | `search_users_provider.dart` |
| 6 | `UserSearchResultTile` | `user_search_result_tile_test.dart` (3 gym branches + tap) | `user_search_result_tile.dart` |
| 7 | `SearchUsersScreen` (6 state machine cases + debounce) | `search_users_screen_test.dart` | `search_users_screen.dart` |
| 8 | Router + `_FeedHeader` wire | (covered by screen integration test in step 7) | `router.dart` + `feed_screen.dart` |
| 9 | Quality gates | — | `flutter analyze`, `dart format .`, `flutter test` |

Each numbered step is a work-unit commit. If `delivery_strategy == 'auto-chain'` is in effect for PR#2 (see proposal Review Workload Forecast), apply phase implements ONLY the next autonomous slice per run.

## C.3 Pattern reuse from Etapa 4

| Pattern | Etapa 4 source | Reused in this etapa |
|---|---|---|
| Private `_ProfilePill` style | `public_profile_screen.dart` | `_PrivacyPill` in `CreatePostScreen` (same shape, mint active / `bgCard` inactive) |
| `Opacity(0.4)` for disabled affordance | `_MessageButtonStub` | `_PrivacyPill(isEnabled: false)` for MI GYM when no gym; `_RoutineTagStubChip` |
| `PostAvatar` reuse with `size:` param | `PublicProfileHero` (size 96) | `UserSearchResultTile` (size 40) |
| `gymNameFromId` utility | `lib/features/feed/domain/gym_name.dart` | `UserSearchResultTile` gym subtitle |
| Async data branching pattern (`when(data, loading, error)`) | `PublicProfileScreen` | `SearchUsersScreen._SearchBody`, `CreatePostScreen` (via state.isLoading) |
| `ConsumerWidget` screen + `ref.watch` + branch | `PublicProfileScreen` | `CreatePostScreen` |
| `ConsumerStatefulWidget` for controller + timer | (new pattern in this etapa) | `SearchUsersScreen` — first introduction; document for future search-shaped screens |
| Provider invalidation after mutation | `PublicProfileFollowButton` invalidates `friendshipByPairProvider` | `CreatePostNotifier.submit` invalidates 3 feed providers |

The `gymNameFromId` reuse is critical — both Etapa 4's `PublicProfileHero` and this etapa's `UserSearchResultTile` rely on the SAME mapping, which lives in a single file. When the gym catalog migrates to Firestore in Fase 4+, the change is one place.

## C.4 Style consistency

| Aspect | Convention |
|---|---|
| Header pattern | Each screen has its own header (`_CreatePostHeader`, `_SearchUsersHeader`) following the `_FeedHeader` posture: horizontal 20 / vertical 18 padding, uppercase Barlow Condensed title, optional left+right action affordances. NO `AppBar`. |
| Loading state | `Center(child: CircularProgressIndicator(color: palette.accent))` — copied verbatim from Etapa 3/4. |
| Error state | Inline `Text` in `palette.textMuted`, horizontal padding 20, Barlow 14 w400. Centered when standalone, left-aligned when within a tile. |
| Empty state | `FeedEmptyState(message: 'Spanish copy.')` — reused as-is from Etapa 3. `icon` defaults to `TreinoIcon.users`; we can override for search-specific (e.g., `TreinoIcon.search`) if needed. |
| Palette tokens | `AppPalette.of(context)` everywhere. NO HEX literals. NO `Theme.of(context).textTheme.X` with custom sizes — always compose via `GoogleFonts.barlow*(...)` + explicit color/size/weight/letter-spacing. |
| Icons | `TreinoIcon.X` only. NO direct `PhosphorIcons.X`. Verify icons exist (`TreinoIcon.dumbbell`, `TreinoIcon.chevronLeft`, `TreinoIcon.chevronRight`, `TreinoIcon.search`, `TreinoIcon.plus`) during apply — add to `treino_icon.dart` if missing. |
| Spacing | Allowed set `{8, 12, 14, 18, 20}` only. NO 16, NO 24. |
| Route `pageBuilder` | Always `_noAnim(const ...)` for shell-nested routes (matches the codebase convention to avoid the iOS slide). |

---

## C.5 Cross-cutting ADRs

### ADR-XC-001 — Two PRs, chained (not stacked, not single)

**Decision**: Sequence two PRs off `main`, with PR#2 created AFTER PR#1 merges.
**Why**: ~597 production LOC exceeds the 400 budget. Both PRs touch `_FeedHeader` and `router.dart` — parallel branches conflict. Chained serializes the conflict.
**Rejected**: Single PR with `size:exception` — proposal Q10 rejected; two slices each fit a reviewer's mental cache.
**Rejected**: Stacked (PR#2 off PR#1) — rebase pain on PR#1 feedback.
**Rejected**: Three PRs (split PR#2 into model + screen) — premature; do only if PR#2 actually exceeds 400 at PR-open time.

### ADR-XC-002 — Tracker branch (`feat/feed-create-search`) never produces a PR

**Decision**: The integration tracker branch exists only for sdd-archive consolidation. All implementation PRs use dedicated sub-branches.
**Why**: Keeps the artifact-store (engram + openspec) coupling clean — one change name, one tracker branch, two PR branches.
**Rejected**: Use the tracker branch as the PR branch — couples archiving to PR merge mechanics; complicates rebases.

### ADR-XC-003 — Defense-in-depth at every gate

**Decision**: Every UI gate (gym-pill disabled, 2-char search min, char limit) has a corresponding notifier/provider-level guard.
**Why**: UI state can drift (e.g., user changes gym after privacy chosen, family key races with debounce). Cheap to add the second check; high cost when it's missing and a race occurs.
**Pattern**: UI is the user-friendly signal; logic-layer guard is the safety net. Both must return the same Spanish-localized error string for consistency.

---

## C.6 Quality gate checklist (per PR, pre-merge)

- [ ] `flutter analyze` — 0 issues (new + pre-existing).
- [ ] `dart format .` — tree clean.
- [ ] `flutter test` — all green; new tests cover all SCENARIO-CREATE-* (PR#1) or SCENARIO-SEARCH-* (PR#2).
- [ ] No HEX literals in any new file: grep `0x[0-9A-Fa-f]{8}` and `Color\(0x` across changed files → 0 matches.
- [ ] No `PhosphorIcons.*` direct usage in new widget files: grep `PhosphorIcons` → 0 matches.
- [ ] No `print(` or `debugPrint(` left in changed files: grep → 0 matches.
- [ ] PR#1 only: `_PrivacyPill` does NOT import `feed_segment_pills.dart`: grep → 0 matches.
- [ ] PR#2 only: `displayNameLowercase` written at all 4 sites (verify with grep across `user_repository.dart` and `profile_setup_notifier.dart`).
- [ ] PR#2 only: `freezed` regen complete (`user_profile.freezed.dart` updated; `user_profile.g.dart` updated).
- [ ] Total changed lines (production only) ≤ 400, OR `size:exception` requested with rationale.
- [ ] Reviewer notes the change in the test fixtures for `UserProfile` (PR#2) and asks whether to introduce the `fakeUser` helper.

---

## C.7 Risks (forwarded from proposal §Risks)

| Risk | Mitigation in this design |
|---|---|
| Existing UserProfile docs lack `displayNameLowercase` | Nullable field + lazy backfill on next `update()` (B.6.2). Documented. |
| PR#2 prod LOC exceeds 400 | sdd-tasks may sub-split into PR#2a (model+repo+ProfileSetup write) and PR#2b (screen+tile+provider+wire). Decision deferred to sdd-tasks based on actual diff at task generation. |
| Prefix-only search misses substring | Locked MVP trade-off (proposal Risks row 3). Documented in ADR-SR-001. |
| Cross-dev conflict on `UserProfile` model | Proposal Q1 + Q9 cleared by user. PR#2 must verify no in-flight branch before open. |
| Gym-privacy post with null `gymId` invisible | UI gate (disabled pill) + notifier guard (B.6 of A; ADR-CP-005). |
| Keyboard overlaps PUBLICAR | `SingleChildScrollView` (A.6.5) + header anchored outside scrollable. |
| Feed providers might be StreamProvider | Verified: `myFriendsFeedProvider` and `feedPublicProvider` are `FutureProvider`; `myGymFeedProvider` is `FutureProvider<List<Post>?>`. `ref.invalidate` works on all three. |
| `palette.danger` token may not exist | Verify in apply; fall back to `palette.accent` with `withValues(alpha: 0.12)` per A.6.4 if missing. |
| Icon names may not exist (`TreinoIcon.chevronLeft`, `chevronRight`, `dumbbell`) | Verify `lib/core/widgets/treino_icon.dart` in apply; add as needed mapping to `PhosphorIcons*` constants. |

---

## C.8 Tokens used (no new ones introduced)

Existing palette + icon tokens consumed by this change (verify all exist in apply):

- Colors: `palette.bg`, `palette.bgCard`, `palette.accent`, `palette.highlight`, `palette.border`, `palette.textPrimary`, `palette.textMuted`, (optional) `palette.danger`.
- Fonts: `GoogleFonts.barlowCondensed`, `GoogleFonts.barlow`.
- Icons: `TreinoIcon.plus`, `TreinoIcon.search`, `TreinoIcon.users`, `TreinoIcon.dumbbell`, `TreinoIcon.chevronLeft`, `TreinoIcon.chevronRight`.
- Spacing set: `{8, 12, 14, 18, 20}`.

If `palette.danger`, `TreinoIcon.dumbbell`, `TreinoIcon.chevronLeft`, or `TreinoIcon.chevronRight` are missing, sdd-tasks will add a small subtask "add missing token" before the screen tasks.

---

## C.9 Out of scope (forwarded, unchanged)

Workout attach (Fase 4), real routine picker (Fase 4), edit/delete posts, likes/comments, trending users, search posts, inline follow in tiles, `@handle`, Algolia/Typesense/Meilisearch, notifications, deep links, backfill script, stats reales en perfiles de búsqueda.

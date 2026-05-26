# Exploration: feed-providers-stream-conversion

## Goal

Convert three `FutureProvider` instances (`friendshipByPairProvider`, `acceptedFriendsProvider`, `userPublicProfileProvider`) to `StreamProvider` so User A's app reflects cross-device mutations made by User B without requiring a restart or manual invalidation. Simultaneously delete the already-orphaned `pendingRequestsProvider` (Future variant, line 18 of `friendship_providers.dart`) that was superseded by `pendingRequestsStreamProvider` in the inbox SDD but never removed.

## Background

- **ADR-FRI-013** in `feed-friend-requests-inbox/design.md` established targeted `ref.invalidate()` calls to close _on-device_ staleness. That ADR explicitly deferred cross-device staleness to this SDD.
- §7 of the inbox archive report names this follow-up: "SDD `feed-providers-stream-conversion` — converts the 3 providers to `StreamProvider` for cross-device live updates."

---

## Current State Audit

### 1. `friendshipByPairProvider`
- **File**: `lib/features/feed/application/public_profile_providers.dart:22`
- **Signature**: `FutureProvider.family<Friendship?, FriendshipPair>` (no autoDispose)
- **Repo method**: `FriendshipRepository.getByPair(uidA, uidB)` — single `.get()` on `sortedDocId`
- **Consumers (production)**: `publicProfileViewProvider` (composed), `PublicProfileFollowButton` (invalidate), `FriendRequestInboxTile` (invalidate)
- **Consumers (test)**: `test/features/feed/application/public_profile_providers_test.dart` — 3 scenarios reading `.future` directly; no overrideWith mocks

### 2. `acceptedFriendsProvider`
- **File**: `lib/features/feed/application/friendship_providers.dart:12`
- **Signature**: `FutureProvider.family<List<String>, String>` (no autoDispose)
- **Repo method**: `FriendshipRepository.acceptedFriendsOf(uid)` — `.where(...).get()`
- **Consumers (production)**: `myFriendsFeedProvider` (composed), `PublicProfileFollowButton` (invalidate ×2), `FriendRequestInboxTile` (invalidate)
- **Consumers (test)**: `test/features/feed/application/feed_screen_providers_test.dart` — SCENARIO-140/141 use `overrideWith((ref) => Future.value([...]))` → needs updating

### 3. `userPublicProfileProvider`
- **File**: `lib/features/profile/application/user_public_profile_providers.dart:22`
- **Signature**: `FutureProvider.family<UserPublicProfile?, String>` (no autoDispose)
- **Repo method**: `UserPublicProfileRepository.get(uid)` — single `.get()` on `userPublicProfiles/{uid}`
- **Consumers (production)**: `publicProfileViewProvider` (composed), `FriendRequestInboxTile` (watch valueOrNull), `PublicProfileFollowButton._showUnfriendSheet` (read AsyncValue)
- **Consumers (test)**: 3 scenarios reading `.future` directly; no overrideWith mocks

---

## Repository Method Changes Required

### FriendshipRepository — 2 new methods (mirror existing `watchPendingRequestsFor`)

```dart
Stream<Friendship?> watchByPair(String uidA, String uidB) {
  final id = Friendship.sortedDocId(uidA, uidB);
  return _friendships.doc(id).snapshots().map(_fromDoc);
}

Stream<List<String>> watchAcceptedFriendsOf(String uid) {
  return _friendships
      .where('members', arrayContains: uid)
      .where('status', isEqualTo: FriendshipStatus.accepted.toJson())
      .snapshots()
      .map((snap) => snap.docs.map((doc) {
            final members = (doc.data()['members'] as List).cast<String>();
            return members.firstWhere((m) => m != uid, orElse: () => '');
          }).where((m) => m.isNotEmpty).toList());
}
```

### UserPublicProfileRepository — 1 new method

```dart
Stream<UserPublicProfile?> watch(String uid) {
  return _col.doc(uid).snapshots().map((snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return UserPublicProfile.fromJson(data);
  });
}
```

---

## Downstream Composition Trap

`publicProfileViewProvider` (line 63) composes both `userPublicProfileProvider` + `friendshipByPairProvider` via `.future`. With stream upstreams, `.future` only resolves to the FIRST emission — live update semantics lost at this seam.

### Options

| Approach | Description | Pros | Cons | Effort |
|---|---|---|---|---|
| **A — rxdart `Rx.combineLatest2`** | Convert `publicProfileViewProvider` to `StreamProvider.family`, combine both upstreams via rxdart | Cleanest 5-line solution; idiomatic for multi-stream merge | Requires `rxdart` dep (zero today) | Medium |
| **B — `.future` only** | Keep `publicProfileViewProvider` as FutureProvider, just switch upstream signature | Smallest diff | Loses live-update semantics — defeats the SDD purpose | Low |
| **C — `AsyncNotifier` + `ref.listen`** | Convert to `AsyncNotifier.family` subscribing to both upstreams manually, emit combined | Zero new deps; idiomatic Riverpod 2 | More boilerplate; careful cancellation | Medium-High |

**`myFriendsFeedProvider` also has this trap** — covered separately below.

---

## Invalidation Calls Disposition

After conversion, these `ref.invalidate()` calls in production code become redundant:
- `friendshipByPairProvider(...)` in `PublicProfileFollowButton` + `FriendRequestInboxTile`
- `acceptedFriendsProvider(...)` in same 2 widgets
- `myFriendsFeedProvider` in those widgets (ONLY if `myFriendsFeedProvider` is also converted)

**Recommendation: hybrid** — remove invalidations for the 3 converted providers. Keep `myFriendsFeedProvider` invalidations (its scope is deferred — see next section). The `CreatePostNotifier.submit()` invalidation of `myFriendsFeedProvider` stays regardless (post creation isn't a friendship mutation).

---

## `myFriendsFeedProvider` — Defer

**Current**: `FutureProvider<List<Post>>` composing auth → `acceptedFriendsProvider` → `feedForFriendsProvider`.

After `acceptedFriendsProvider` becomes a Stream, `myFriendsFeedProvider` awaits first emission only — same composition trap.

**Cost analysis**: `feedForFriendsProvider` uses `whereIn` on friend UIDs. A stream listener fires on EVERY Firestore write to any matching post. With 10-50 friends posting actively, this is a meaningful Firestore reads cost.

**Recommendation: DEFER `myFriendsFeedProvider` conversion** — separate cost-tradeoff decision that shouldn't bundle with the social-graph metadata streaming. The invalidation calls for `myFriendsFeedProvider` remain.

---

## Test Impact Estimate

| File | Impact |
|---|---|
| `test/features/feed/application/feed_screen_providers_test.dart` | **High** — SCENARIO-140/141 override `acceptedFriendsProvider` with `Future.value(...)` → must change to `Stream.value(...)` |
| `test/features/feed/application/public_profile_providers_test.dart` | **Low** — reads `.future` directly via FakeFirebaseFirestore; works with StreamProvider's first emission |
| `test/features/profile/application/user_public_profile_providers_test.dart` | **Low** — same pattern as above |
| **NEW** `test/features/feed/data/friendship_repository_watch_test.dart` | New tests for `watchByPair` + `watchAcceptedFriendsOf` (SCENARIOs TBD) |
| **NEW** `test/features/profile/data/user_public_profile_repository_watch_test.dart` | New test for `watch` |
| **NEW** `test/features/feed/application/stream_providers_test.dart` (or extend existing) | New StreamProvider integration tests |

---

## Orphan Deletion Confirmation

`pendingRequestsProvider` (line 18) grep results:
- **lib/**: zero references
- **test/**: zero direct usage (friendship_providers_test.dart only tests the stream variant + count derived)

**Verdict**: safe to delete.

---

## Affected Files

- `lib/features/feed/application/friendship_providers.dart` — remove `pendingRequestsProvider`; convert `acceptedFriendsProvider` to stream
- `lib/features/feed/application/public_profile_providers.dart` — convert `friendshipByPairProvider`; restructure `publicProfileViewProvider`
- `lib/features/profile/application/user_public_profile_providers.dart` — convert `userPublicProfileProvider`
- `lib/features/feed/data/friendship_repository.dart` — add `watchByPair` + `watchAcceptedFriendsOf`
- `lib/features/profile/data/user_public_profile_repository.dart` — add `watch`
- `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` — remove obsolete invalidate calls
- `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` — remove obsolete invalidate calls
- Tests: 1 file substantive update + ~3 new test files

---

## Out of Scope

- `myFriendsFeedProvider` conversion (Firestore read-cost risk; deferred)
- Push notifications (FCM) — Fase 6
- Removing `myFriendsFeedProvider` invalidations in `CreatePostNotifier`
- Any other FutureProvider conversion (`routinesProvider`, `userProfileProvider`)
- Ranking, Retos, Missions, Bets, Gamification

---

## Open Questions for sdd-propose

1. **Composition pattern for `publicProfileViewProvider`**: rxdart `Rx.combineLatest2` (requires dep) or `AsyncNotifier` with `ref.listen` (zero deps, more boilerplate)?
2. **Invalidation cleanup scope**: remove ALL redundant invalidate calls (cleanest) or keep defensive belt-and-suspenders on first deployment?
3. **`autoDispose` on new StreamProviders**: yes (drops Firestore listener when off-screen — prevents leak per visited profile) or keep non-autoDispose like the Future versions?
4. **Naming convention**: drop-in replacement (keep existing names — zero consumer refactor) or `watchX`/`*StreamProvider` prefix (more explicit)?

---

## Recommendation

Convert all 3 providers to `StreamProvider` using the existing `watchPendingRequestsFor` pattern as template. Compose `publicProfileViewProvider` via **AsyncNotifier + ref.listen** (zero new deps preferred over rxdart). Add **autoDispose** to all 3. **Drop-in replacement** (same names). Delete `pendingRequestsProvider`. Do NOT convert `myFriendsFeedProvider`. Remove invalidation calls only for the 3 converted providers; keep `myFriendsFeedProvider` invalidations.

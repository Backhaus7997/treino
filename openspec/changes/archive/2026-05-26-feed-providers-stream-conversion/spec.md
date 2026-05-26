# Spec: feed-providers-stream-conversion

**Change**: feed-providers-stream-conversion
**Phase/Etapa**: Fase 3 / Etapa 6 (follow-up to feed-friend-requests-inbox)
**Owner**: Backhaus
**PR**: single PR against `main` — `feat/feed-providers-stream-conversion`
**SCENARIO range**: 473–493
**REQ count**: 10

---

## REQ Matrix

| ID | Section | Strength | Description |
|---|---|---|---|
| REQ-FPS-001 | A — Repository: FriendshipRepository | MUST | `FriendshipRepository` gains `watchByPair(uidA, uidB)` returning `Stream<Friendship?>` that emits the current doc (or null when absent) and re-emits on every Firestore snapshot |
| REQ-FPS-002 | A — Repository: FriendshipRepository | MUST | `FriendshipRepository` gains `watchAcceptedFriendsOf(uid)` returning `Stream<List<String>>` with the same query shape as `acceptedFriendsOf` but using `.snapshots()` |
| REQ-FPS-003 | B — Repository: UserPublicProfileRepository | MUST | `UserPublicProfileRepository` gains `watch(uid)` returning `Stream<UserPublicProfile?>` using `.snapshots()` on the single doc; emits null when doc does not exist |
| REQ-FPS-004 | C — Providers: StreamProvider conversions | MUST | `friendshipByPairProvider` is declared as `StreamProvider.family.autoDispose<Friendship?, FriendshipPair>` — drop-in name, `AsyncValue<Friendship?>` surface unchanged for consumers |
| REQ-FPS-005 | C — Providers: StreamProvider conversions | MUST | `acceptedFriendsProvider` is declared as `StreamProvider.family.autoDispose<List<String>, String>` — drop-in name, `AsyncValue<List<String>>` surface unchanged for consumers |
| REQ-FPS-006 | C — Providers: StreamProvider conversions | MUST | `userPublicProfileProvider` is declared as `StreamProvider.family.autoDispose<UserPublicProfile?, String>` — drop-in name, `AsyncValue<UserPublicProfile?>` surface unchanged for consumers |
| REQ-FPS-007 | D — Provider: publicProfileViewProvider composition | MUST | `publicProfileViewProvider` is declared as `AsyncNotifier.family<PublicProfileView, String>` and composes `userPublicProfileProvider` and `friendshipByPairProvider` via `ref.watch(…​.future)`; re-emits on every upstream change; uses NO rxdart |
| REQ-FPS-008 | E — Invalidation cleanup | MUST | All `ref.invalidate(...)` and `container.invalidate(...)` calls for `friendshipByPairProvider` and `acceptedFriendsProvider` are removed from production code; all `myFriendsFeedProvider` invalidations are preserved |
| REQ-FPS-009 | F — Orphan deletion | MUST | `pendingRequestsProvider` (Future variant at `friendship_providers.dart`) is deleted; the symbol MUST NOT be importable after this change |
| REQ-FPS-010 | G — autoDispose lifecycle | MUST | All three `StreamProvider.family.autoDispose` providers MUST drop their Firestore listeners when the last consumer widget unmounts; no persistent listener remains for orphaned `(viewerUid, targetUid)` pairs |

---

## Section A — Repository Layer: REQ-FPS-001, REQ-FPS-002

### Requirement: watchByPair Stream (REQ-FPS-001)

`FriendshipRepository` MUST expose `Stream<Friendship?> watchByPair(String uidA, String uidB)`. The stream MUST subscribe to `friendships/{sortedDocId}` via `.snapshots()` using the same `sortedDocId` logic as `getByPair`. Each snapshot MUST be mapped to `Friendship.fromJson(data)` when the doc exists and to `null` when the doc does not exist or has been deleted.

#### SCENARIO-473: watchByPair emits null when no friendship doc exists

- GIVEN the `friendships` collection has no doc for the given `(uidA, uidB)` pair
- WHEN `watchByPair(uidA, uidB)` is subscribed to
- THEN the stream emits `null`

#### SCENARIO-474: watchByPair re-emits with the new friendship after Firestore write commits

- GIVEN `watchByPair(uidA, uidB)` is active and has emitted `null`
- WHEN a friendship doc for `(uidA, uidB)` is written to Firestore with `status: pending`
- THEN the stream emits a non-null `Friendship` with `status == pending`

#### SCENARIO-475: watchByPair re-emits null after friendship deletion

- GIVEN `watchByPair(uidA, uidB)` is active and has emitted a non-null `Friendship`
- WHEN the corresponding Firestore doc is deleted
- THEN the stream emits `null`

---

### Requirement: watchAcceptedFriendsOf Stream (REQ-FPS-002)

`FriendshipRepository` MUST expose `Stream<List<String>> watchAcceptedFriendsOf(String uid)`. The query MUST be identical to `acceptedFriendsOf` (`members arrayContains uid` AND `status == accepted`) but MUST use `.snapshots()`. Each snapshot MUST be mapped to the list of peer UIDs (the member that is NOT `uid`).

#### SCENARIO-476: watchAcceptedFriendsOf emits empty list for user with no accepted friendships

- GIVEN the `friendships` collection has no accepted doc for `uid`
- WHEN `watchAcceptedFriendsOf(uid)` is subscribed to
- THEN the stream emits `[]`

#### SCENARIO-477: watchAcceptedFriendsOf re-emits with new peer uid after accept commits

- GIVEN `watchAcceptedFriendsOf(uid)` is active and has emitted `[]`
- WHEN a friendship doc is written with `status: accepted` and `members: [uid, peerUid]`
- THEN the stream emits `[peerUid]`

#### SCENARIO-478: watchAcceptedFriendsOf re-emits without the peer uid after friendship deletion

- GIVEN `watchAcceptedFriendsOf(uid)` is active and has emitted `[peerUid]`
- WHEN the accepted friendship doc is deleted from Firestore
- THEN the stream emits `[]`

---

## Section B — Repository Layer: REQ-FPS-003

### Requirement: UserPublicProfileRepository.watch Stream (REQ-FPS-003)

`UserPublicProfileRepository` MUST expose `Stream<UserPublicProfile?> watch(String uid)`. The stream MUST subscribe to `userPublicProfiles/{uid}` via `.snapshots()` using the same collection reference as `get`. Each snapshot MUST be mapped to `UserPublicProfile.fromJson(data)` when the doc exists and to `null` when it does not exist.

#### SCENARIO-479: watch emits null when the profile doc does not exist

- GIVEN the `userPublicProfiles` collection has no doc for `uid`
- WHEN `watch(uid)` is subscribed to
- THEN the stream emits `null`

#### SCENARIO-480: watch re-emits updated profile on Firestore doc update

- GIVEN `watch(uid)` is active and has emitted a profile with `followersCount: 0`
- WHEN the Firestore doc for `uid` is updated to `followersCount: 5`
- THEN the stream emits a `UserPublicProfile` with `followersCount == 5`

---

## Section C — Providers: REQ-FPS-004, REQ-FPS-005, REQ-FPS-006

### Requirement: friendshipByPairProvider as StreamProvider (REQ-FPS-004)

`friendshipByPairProvider` MUST be declared as `StreamProvider.family.autoDispose<Friendship?, FriendshipPair>` wrapping `watchByPair`. The provider name and its `AsyncValue<Friendship?>` consumer surface MUST be identical to the previous `FutureProvider.family` — zero consumer signature change.

#### SCENARIO-481: friendshipByPairProvider exposes .snapshots() stream via StreamProvider.family.autoDispose

- GIVEN `friendshipRepositoryProvider` returns a repository whose `watchByPair` emits Friendship values
- WHEN `ref.watch(friendshipByPairProvider(pair))` is called by a consumer
- THEN the consumer receives `AsyncValue<Friendship?>` and rebuilds on each upstream emit

#### SCENARIO-482: friendshipByPairProvider drops Firestore listener when no widget watches (autoDispose contract)

- GIVEN a `ProviderContainer` with `friendshipByPairProvider(pair)` subscribed
- WHEN the last listener on the provider is removed (widget unmounts)
- THEN the provider is disposed and the underlying Firestore stream subscription is cancelled

---

### Requirement: acceptedFriendsProvider as StreamProvider (REQ-FPS-005)

`acceptedFriendsProvider` MUST be declared as `StreamProvider.family.autoDispose<List<String>, String>` wrapping `watchAcceptedFriendsOf`. Existing consumers using `ref.watch(acceptedFriendsProvider(uid))` MUST continue to receive `AsyncValue<List<String>>` without any signature change.

#### SCENARIO-483: acceptedFriendsProvider drop-in — consumer ref.watch still returns AsyncValue<List<String>>

- GIVEN a consumer widget that calls `ref.watch(acceptedFriendsProvider(uid))`
- WHEN `acceptedFriendsProvider` is a `StreamProvider.family.autoDispose`
- THEN the consumer receives `AsyncValue<List<String>>` — identical surface to the former `FutureProvider.family`
- AND no import, cast, or `.future` access change is required in the consumer

---

### Requirement: userPublicProfileProvider as StreamProvider (REQ-FPS-006)

`userPublicProfileProvider` MUST be declared as `StreamProvider.family.autoDispose<UserPublicProfile?, String>` wrapping `watch`. Existing consumers using `ref.watch(userPublicProfileProvider(uid)).valueOrNull` MUST continue to work without any signature change.

#### SCENARIO-484: userPublicProfileProvider drop-in — valueOrNull pattern in FriendRequestInboxTile still works

- GIVEN `FriendRequestInboxTile.build` calls `ref.watch(userPublicProfileProvider(uid)).valueOrNull`
- WHEN `userPublicProfileProvider` is a `StreamProvider.family.autoDispose`
- THEN `valueOrNull` resolves to `UserPublicProfile?` — identical to the former FutureProvider behavior
- AND no change to `FriendRequestInboxTile` source is required for this access pattern

---

## Section D — publicProfileViewProvider: REQ-FPS-007

### Requirement: publicProfileViewProvider as AsyncNotifier (REQ-FPS-007)

`publicProfileViewProvider` MUST be declared as `AsyncNotifier.family<PublicProfileView, String>` (parameterized by `targetUid`). Its `build` method MUST compose `userPublicProfileProvider(targetUid)` and `friendshipByPairProvider(pair)` via `ref.watch(…​.future)` so that each upstream re-emit triggers a new `build` execution and consumers receive an updated `PublicProfileView`. The `isSelf` branch (when `viewerUid == targetUid`) MUST NOT subscribe to `friendshipByPairProvider` and MUST pass `null` as the friendship. No `rxdart` dependency is permitted.

#### SCENARIO-485: publicProfileViewProvider emits combined view-model when both upstreams provide data

- GIVEN `userPublicProfileProvider(targetUid)` emits `AsyncData(profile)` and `friendshipByPairProvider(pair)` emits `AsyncData(friendship)`
- WHEN `ref.watch(publicProfileViewProvider(targetUid))` is resolved
- THEN the provider emits `AsyncData(PublicProfileView(profile: profile, friendship: friendship))`

#### SCENARIO-486: publicProfileViewProvider reflects upstream userPublicProfileProvider re-emission

- GIVEN `publicProfileViewProvider(targetUid)` has emitted a view-model with `profile.followersCount == 0`
- WHEN `userPublicProfileProvider(targetUid)` re-emits with `followersCount: 5`
- THEN `publicProfileViewProvider(targetUid)` re-emits with the updated profile within the same instance

#### SCENARIO-487: publicProfileViewProvider reflects upstream friendshipByPairProvider re-emission

- GIVEN `publicProfileViewProvider(targetUid)` has emitted a view-model with `friendship.status == pending`
- WHEN `friendshipByPairProvider(pair)` re-emits with `status == accepted`
- THEN `publicProfileViewProvider(targetUid)` re-emits with `friendship.status == accepted`

#### SCENARIO-488: publicProfileViewProvider emits AsyncLoading while either upstream is still loading

- GIVEN `userPublicProfileProvider(targetUid)` is in `AsyncLoading` state (and friendshipByPairProvider may or may not have data)
- WHEN `ref.watch(publicProfileViewProvider(targetUid))` is resolved
- THEN the provider is in `AsyncLoading` state until both upstreams have emitted their first value

#### SCENARIO-489: publicProfileViewProvider propagates error from either upstream

- GIVEN `userPublicProfileProvider(targetUid)` emits `AsyncError(e, st)` (or `friendshipByPairProvider` does)
- WHEN `ref.watch(publicProfileViewProvider(targetUid))` is resolved
- THEN the provider emits `AsyncError` containing the upstream error
- AND no uncaught exception is thrown in the widget tree

#### SCENARIO-490: publicProfileViewProvider isSelf branch returns null friendship without subscribing to friendshipByPairProvider

- GIVEN `viewerUid == targetUid` (user is viewing their own public profile)
- WHEN `publicProfileViewProvider(targetUid)` builds
- THEN `friendshipByPairProvider` is NOT subscribed
- AND the emitted `PublicProfileView` has `friendship == null`

---

## Section E — Invalidation Cleanup: REQ-FPS-008

### Requirement: Removal of obsolete invalidate calls (REQ-FPS-008)

All production call sites MUST NOT call `ref.invalidate(friendshipByPairProvider(...))`, `ref.invalidate(acceptedFriendsProvider(...))`, `container.invalidate(friendshipByPairProvider(...))`, or `container.invalidate(acceptedFriendsProvider(...))`. All production call sites MUST STILL call `ref.invalidate(myFriendsFeedProvider)` / `container.invalidate(myFriendsFeedProvider)` wherever they did before this change.

#### SCENARIO-491b: PublicProfileFollowButton SEGUIR onTap does NOT call ref.invalidate for the 3 converted providers

- GIVEN `PublicProfileFollowButton.onTap` executes the SEGUIR (follow) action
- WHEN the action completes
- THEN `ref.invalidate(friendshipByPairProvider(...))` is NOT called
- AND `ref.invalidate(acceptedFriendsProvider(...))` is NOT called

#### SCENARIO-492: PublicProfileFollowButton onTap preserves myFriendsFeedProvider invalidation

- GIVEN `PublicProfileFollowButton.onTap` executes the ACEPTAR or unfriend action
- WHEN the action completes
- THEN `ref.invalidate(myFriendsFeedProvider)` IS called (preserved from before the change)

#### SCENARIO-493: FriendRequestInboxTile._onAceptar does NOT call container.invalidate for converted providers but DOES invalidate myFriendsFeedProvider

- GIVEN `FriendRequestInboxTile._onAceptar` executes
- WHEN the accept action completes
- THEN `container.invalidate(acceptedFriendsProvider(...))` is NOT called
- AND `container.invalidate(friendshipByPairProvider(...))` is NOT called
- AND `container.invalidate(myFriendsFeedProvider)` IS called

---

## Section F — Orphan Deletion: REQ-FPS-009

### Requirement: pendingRequestsProvider removed from codebase (REQ-FPS-009)

The `pendingRequestsProvider` symbol (the `FutureProvider.family<List<Friendship>, String>` at line 18 of `friendship_providers.dart`, superseded by `pendingRequestsStreamProvider`) MUST be deleted. After the change, any Dart file that imports and references `pendingRequestsProvider` MUST fail to compile.

#### SCENARIO-491: pendingRequestsProvider symbol is absent from friendship_providers.dart after the change

- GIVEN `friendship_providers.dart` is compiled after this change is applied
- WHEN any file attempts to import and use `pendingRequestsProvider`
- THEN the Dart compiler emits an `Undefined name` error (compile-time failure)

---

## Section G — autoDispose Lifecycle: REQ-FPS-010

### Requirement: Firestore listener lifecycle bounded by consumer lifetime (REQ-FPS-010)

Each `StreamProvider.family.autoDispose` provider MUST dispose its underlying Firestore `.snapshots()` subscription when the last consumer widget unmounts. No persistent listener SHOULD survive beyond the widget that requested it.

*(Note: Firestore client-side cache ensures near-instant re-connection on rapid navigate-away-and-back, making the autoDispose tradeoff safe.)*

*(See SCENARIO-482 under REQ-FPS-004 — the autoDispose lifecycle contract is demonstrated there and applies equally to REQ-FPS-005 and REQ-FPS-006.)*

---

## REQ → SCENARIO Traceability

| REQ | SCENARIOs |
|---|---|
| REQ-FPS-001 | 473, 474, 475 |
| REQ-FPS-002 | 476, 477, 478 |
| REQ-FPS-003 | 479, 480 |
| REQ-FPS-004 | 481, 482 |
| REQ-FPS-005 | 483 |
| REQ-FPS-006 | 484 |
| REQ-FPS-007 | 485, 486, 487, 488, 489, 490 |
| REQ-FPS-008 | 491b, 492, 493 |
| REQ-FPS-009 | 491 |
| REQ-FPS-010 | 482 (shared) |

---

## Cross-Cutting Requirements

| ID | Strength | Rule |
|---|---|---|
| REQ-FPS-CX-001 | MUST | Strict TDD — tests written RED before implementation (GREEN) for every work unit |
| REQ-FPS-CX-002 | MUST | No `rxdart` added to `pubspec.yaml` |
| REQ-FPS-CX-003 | MUST | `flutter analyze` reports 0 issues; `dart format .` is clean before PR is opened |
| REQ-FPS-CX-004 | MUST | Consumer widget source is NOT modified to accommodate the provider type change (drop-in guarantee) |

---

## Non-Functional Requirements

- **Listener leak prevention**: Without `autoDispose`, each visited public profile leaves a permanent Firestore listener on `friendships/{sortedDocId}` and `userPublicProfiles/{uid}`. Over a browsing session of 20+ profiles, this creates 40+ live listeners — a measurable memory and read-cost leak. `autoDispose` on all 3 providers MUST be verified in integration tests (dispose the container; assert no surviving listener via `fake_cloud_firestore` listener tracking or mocktail spy).
- **Composite index**: The `watchAcceptedFriendsOf` query shape (`members arrayContains uid` AND `status == accepted`) is identical to the existing `acceptedFriendsOf` `.get()` query. The same Firestore composite index applies — no new index creation is required. Design phase MUST confirm via `firestore.indexes.json` audit.
- **Loading flicker on rapid navigate-back**: Brief re-loading on rapid navigate-away-and-back is acceptable. Riverpod family cache combined with Firestore client-side cache makes second-visit re-subscription near-instant. If observable in smoke testing, escalate to a `keepAlive` follow-up; do NOT block this change.

---

## Excluded Behaviors (out of scope)

The following are explicitly NOT covered by this spec and MUST NOT be implemented in this change:

- `myFriendsFeedProvider` stream conversion — Firestore read-cost concern; deferred indefinitely (see proposal §locked decision 5).
- Removing `myFriendsFeedProvider` invalidations in `CreatePostNotifier.submit()` or any other call site.
- Conversion of any other `FutureProvider` in the codebase (`routinesProvider`, `userProfileProvider`, etc.).
- Push notifications (FCM) — Fase 6.
- Changes to `firestore.rules` or `firestore.indexes.json` (no new rules or indexes expected; design phase confirms).
- Schema changes, Freezed model modifications, or `build_runner` regeneration.
- UI redesign of `PublicProfileScreen`, `PublicProfileFollowButton`, or `FriendRequestInboxTile`.
- Changes to `TreinoBottomBar`, `_FeedHeader`, or routing beyond existing provider wiring.
- Ranking, Retos, Missions, Bets, Gamification.

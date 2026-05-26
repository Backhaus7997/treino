# Proposal: feed-providers-stream-conversion

## TL;DR

Convert three `FutureProvider` instances (`friendshipByPairProvider`, `acceptedFriendsProvider`, `userPublicProfileProvider`) into `StreamProvider.family.autoDispose` so User A's app reflects cross-device mutations made by User B without restart or manual invalidation. Closes the cross-device staleness limitation explicitly deferred in ADR-FRI-013 of `feed-friend-requests-inbox`, and bundles deletion of the orphan `pendingRequestsProvider` flagged in the same SDD. Single PR (~150-200 LOC) on `feat/feed-providers-stream-conversion` against `main`, no `size:exception` needed.

---

## Intent

### Problem

After the friend-requests inbox shipped (SDD `feed-friend-requests-inbox`), three social-graph providers remain `FutureProvider` and are kept "fresh" only via on-device `ref.invalidate(...)` calls. This works for the actor's own device but does **NOT** propagate cross-device:

- User B accepts User A's friend request from device B → User A's `friendshipByPairProvider` on device A still shows `pending` until manual restart.
- User B changes their displayName → User A's `userPublicProfileProvider` keeps the stale value indefinitely.
- User B unfriends User A → User A's `acceptedFriendsProvider` still includes B.

The inbox SDD's **ADR-FRI-013** explicitly named this limitation and deferred the fix to this SDD. The inbox archive report §7 reiterates: _"SDD `feed-providers-stream-conversion` — converts the 3 providers to `StreamProvider` for cross-device live updates."_

Additionally, the orphan `pendingRequestsProvider` (Future variant at `friendship_providers.dart:18`, superseded by `pendingRequestsStreamProvider` in the inbox SDD but never removed — zero consumers in `lib/` and `test/`) is bookkeeping debt that fits cleanly here.

### Why now

- Closes a known, documented cross-device staleness bug from the previous SDD.
- Pre-Fase 6 push-notifications: when FCM lands, push will signal "something changed", but the providers must already be streams to re-emit the new state. Doing the conversion now de-risks Fase 6.
- Low blast radius — internal refactor, no Firestore rules, no model changes, no UI redesign.

### Success criteria

- User B's friendship/profile/friends-list mutations propagate to User A's app within Firestore snapshot latency (~1-2s) with NO restart and NO manual invalidation.
- All consumer widgets continue to compile and behave identically — `ref.watch(provider)` still returns `AsyncValue<T>`.
- All Firestore stream listeners drop when their consumer widgets unmount (verified via `autoDispose`).
- Zero new dependencies (no `rxdart`).
- 0 `flutter analyze` issues, `dart format .` clean, all new + existing tests green.

---

## Scope

### In scope — locked decisions (2026-05-26)

| # | Decision | Locked answer |
|---|---|---|
| 1 | `publicProfileViewProvider` composition | **AsyncNotifier.family<PublicProfileView, String>** subscribing to both upstream stream providers via `ref.listen` / `ref.watch`. **Zero new dependencies — NO rxdart.** |
| 2 | Invalidation cleanup | Remove ALL `ref.invalidate(...)` / `container.invalidate(...)` calls in production code for the 3 converted providers. **KEEP** all `myFriendsFeedProvider` invalidations (that provider stays a `FutureProvider`). |
| 3 | `autoDispose` on new StreamProviders | **YES on all 3.** Prevents Firestore listener leak per visited public profile (one listener stays alive forever per `(viewerUid, targetUid)` pair without autoDispose). |
| 4 | Naming convention | **Drop-in replacement.** Keep existing provider names; only the type changes (`FutureProvider.family` → `StreamProvider.family.autoDispose`). Consumers using `ref.watch(provider)` get `AsyncValue<T>` either way — zero consumer signature refactor. |
| 5 | `myFriendsFeedProvider` | **OUT OF SCOPE** per explore §5 cost analysis (streaming friends-feed posts would multiply Firestore reads). Its invalidations stay. |

### Capabilities

#### New Capabilities

None — this change does not introduce any new product capability.

#### Modified Capabilities

- `feed-friendships`: existing requirements for friendship state lookup and friend-list listing change from "snapshot on read" to "live snapshot stream"; on-device invalidation requirements are removed for the 3 converted providers. (Capability name based on file structure; design phase confirms the canonical spec file location.)
- `profile-public`: existing requirement for public-profile lookup changes from "snapshot on read" to "live snapshot stream"; consumers re-render automatically on remote profile updates.

### Out of scope (explicit)

- `myFriendsFeedProvider` conversion — Firestore read-cost concern; separate cost-tradeoff decision deferred indefinitely.
- Removing `myFriendsFeedProvider` invalidations in `CreatePostNotifier.submit()` or elsewhere.
- Conversion of any other `FutureProvider` (`routinesProvider`, `userProfileProvider`, etc.).
- Push notifications (FCM) — Fase 6.
- Changes to `firestore.rules` — existing rules already cover `.snapshots()` reads (verify in design).
- Schema / freezed model changes — none required, no `build_runner` regen.
- New Firestore collections.
- UI redesigns — widget surface contract unchanged.
- Ranking, Retos, Missions, Bets, Gamification.

---

## Touch list

### Modified files

| Path | Change |
|---|---|
| `lib/features/feed/application/friendship_providers.dart` | Delete `pendingRequestsProvider` (orphan, zero consumers). Convert `acceptedFriendsProvider` from `FutureProvider.family<List<String>, String>` to `StreamProvider.family.autoDispose<List<String>, String>`. |
| `lib/features/feed/application/public_profile_providers.dart` | Convert `friendshipByPairProvider` to `StreamProvider.family.autoDispose<Friendship?, FriendshipPair>`. Rewrite `publicProfileViewProvider` as `AsyncNotifier.family<PublicProfileView, String>` subscribing to both upstream stream providers and emitting combined `AsyncValue<PublicProfileView>` on each upstream change. |
| `lib/features/profile/application/user_public_profile_providers.dart` | Convert `userPublicProfileProvider` to `StreamProvider.family.autoDispose<UserPublicProfile?, String>`. |
| `lib/features/feed/data/friendship_repository.dart` | Add `Stream<Friendship?> watchByPair(String uidA, String uidB)` and `Stream<List<String>> watchAcceptedFriendsOf(String uid)` mirroring the existing `watchPendingRequestsFor` pattern (`.snapshots().map(...)`). |
| `lib/features/profile/data/user_public_profile_repository.dart` | Add `Stream<UserPublicProfile?> watch(String uid)` using `.snapshots()` on the single doc. |
| `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` | Remove obsolete `ref.invalidate(friendshipByPairProvider(...))` and `ref.invalidate(acceptedFriendsProvider(...))` calls in SEGUIR `onTap`, ACEPTAR `onTap`, and unfriend `onConfirm`. **KEEP** `ref.invalidate(myFriendsFeedProvider)` calls. |
| `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` | Remove obsolete `container.invalidate(friendshipByPairProvider(...))` and `container.invalidate(acceptedFriendsProvider(...))` calls in `_onAceptar` and `_onRechazar`. **KEEP** `container.invalidate(myFriendsFeedProvider)` calls AND the dispose-safe `ProviderScope.containerOf(context)` capture pattern (still needed for the surviving `myFriendsFeedProvider` invalidation). |
| `test/features/feed/application/feed_screen_providers_test.dart` | Update SCENARIO-140/141 `acceptedFriendsProvider` overrides from `Future.value([...])` to `Stream.value([...])`. |

### New / extended test files

| Path | Purpose |
|---|---|
| `test/features/feed/data/friendship_repository_test.dart` (extend) | New SCENARIOs covering `watchByPair` and `watchAcceptedFriendsOf` stream contracts: initial emit, post-write re-emit, deletion re-emit. |
| `test/features/profile/data/user_public_profile_repository_test.dart` (extend or create) | New SCENARIO covering `watch` stream contract: initial emit, post-update re-emit, deletion → null emit. |
| `test/features/feed/application/stream_providers_test.dart` (NEW) | Integration tests for the 3 new StreamProviders proving live re-emit on Firestore change (not just `Stream.first` consumption). Includes `publicProfileViewProvider` AsyncNotifier composition tests covering loading / data / error states on both upstreams. |

### NOT touched (sanity guards for reviewers)

- `lib/features/feed/data/friendship_repository.dart` — existing `accept()`, `delete()`, `getByPair()`, `acceptedFriendsOf()`, `pendingRequestsFor()`, `watchPendingRequestsFor()` left untouched; only the two new `watch*()` methods are added.
- `lib/features/profile/data/user_public_profile_repository.dart` — existing `get()` and any other methods left untouched; only the new `watch()` is added.
- `lib/features/feed/application/friendship_providers.dart` — `myFriendsFeedProvider`, `friendshipRepositoryProvider`, `pendingRequestsStreamProvider`, `pendingRequestCountProvider` are untouched.
- `lib/features/feed/application/public_profile_providers.dart` — `FriendshipPair` value object and `PublicProfileView` model untouched.
- `lib/features/feed/presentation/notifiers/create_post_notifier.dart` — `myFriendsFeedProvider` invalidation in `submit()` stays as-is.
- `firestore.rules`, `scripts/rules_test/rules.test.js` — untouched. No new query shape (the `where members arrayContains + where status ==` composite is identical to the existing `acceptedFriendsOf` `.get()` query, and the single-doc `.snapshots()` reads on `friendships/{id}` and `userPublicProfiles/{uid}` reuse existing rules).
- `lib/features/feed/domain/friendship.dart`, `lib/features/profile/domain/user_public_profile.dart` — Freezed models not modified, no `build_runner` regen needed.
- All other `FutureProvider` declarations in the codebase.

---

## Architecture sketch

### Repository layer (3 new `watch*()` methods)

```
FriendshipRepository
  + watchByPair(uidA, uidB) → _friendships.doc(sortedDocId).snapshots().map(_fromDoc)
  + watchAcceptedFriendsOf(uid) →
      _friendships
        .where('members', arrayContains: uid)
        .where('status', isEqualTo: accepted.toJson())
        .snapshots()
        .map(... pluck the other member uid ...)

UserPublicProfileRepository
  + watch(uid) → _col.doc(uid).snapshots().map(UserPublicProfile.fromJson | null)
```

All three mirror the established `watchPendingRequestsFor` pattern from the inbox SDD — same shape, same testability, same `fake_cloud_firestore` compatibility.

### Provider layer

```
acceptedFriendsProvider          : FutureProvider.family       → StreamProvider.family.autoDispose
friendshipByPairProvider         : FutureProvider.family       → StreamProvider.family.autoDispose
userPublicProfileProvider        : FutureProvider.family       → StreamProvider.family.autoDispose

publicProfileViewProvider        : FutureProvider.family       → AsyncNotifier.family<PublicProfileView, String>
  build(targetUid):
    final viewerUid = ref.watch(currentUidProvider);
    final pair = FriendshipPair(viewerUid, targetUid);
    final profile = await ref.watch(userPublicProfileProvider(targetUid).future);
    final friendship = await ref.watch(friendshipByPairProvider(pair).future);
    return PublicProfileView(profile, friendship);
  // ref.watch on a StreamProvider's .future re-builds the notifier on each upstream emit,
  // so PublicProfileScreen re-renders live.
```

Widget surface UNCHANGED — `ref.watch(provider)` still returns `AsyncValue<T>`. `select`, `AsyncValue.when`, `whenData`, `valueOrNull` all work identically.

### Data flow (live cross-device example)

```
User B (device B): friendshipRepository.accept(id, uidB)
       ↓
Firestore: friendships/{id}.status = accepted
       ↓ snapshot
Device A: friendshipByPairProvider((uidA, uidB)) re-emits Friendship(status: accepted)
       ↓
publicProfileViewProvider(uidB) AsyncNotifier listens, re-emits PublicProfileView
       ↓
PublicProfileFollowButton on device A re-renders → SOLICITUD ENVIADA → SIGUIENDO
       ↓ (no restart, no pull-to-refresh, no invalidation)
```

### `autoDispose` rationale

Without `autoDispose`, every visited public profile leaves a permanent Firestore listener on `friendships/{sortedDocId}` and `userPublicProfiles/{targetUid}`. Over a session of browsing 20+ profiles, that's 40+ live listeners — a measurable memory + read-cost leak. `autoDispose` drops each stream when the last consumer widget unmounts.

### No new collections, no rules changes

The `watchAcceptedFriendsOf` composite query (`members arrayContains + status ==`) is **identical** to the existing `acceptedFriendsOf` `.get()` query — same Firestore composite index applies. The single-doc `.snapshots()` reads on `friendships/{id}` and `userPublicProfiles/{uid}` use the same read permissions as the existing `.get()` reads. **Design phase MUST confirm** via a `firestore.indexes.json` audit, but no rules or index changes are expected.

---

## Approach (rationale)

### Why AsyncNotifier over rxdart (locked decision #1)

- **Zero new dependencies**. TREINO has no `rxdart` today; adding it for one composition site is dependency creep.
- AsyncNotifier with `ref.watch(streamProvider.future)` is idiomatic Riverpod 2 — same pattern used elsewhere in the codebase.
- `ref.watch(streamProvider.future)` re-runs the `build` on each upstream emit, giving us live composition for free without manual `Rx.combineLatest2` plumbing.
- More test-friendly: AsyncNotifier subclass is mockable via `overrideWith`, whereas combined `Stream`s require fake `StreamController`s.

### Why drop-in naming (locked decision #4)

- Zero consumer signature refactor — `ref.watch(provider)` returns `AsyncValue<T>` regardless of whether the provider is `FutureProvider` or `StreamProvider`.
- All 6 consumer widgets work unchanged after the type swap.
- Renaming would force a churn diff across `PublicProfileFollowButton`, `FriendRequestInboxTile`, `_PublicProfileBody`, `_FollowControls`, and tests — pure noise.
- The `*StreamProvider` suffix convention is already used for the inbox (`pendingRequestsStreamProvider`) because that one is a **new** provider; here we're **replacing** the existing semantics in place, so the existing name correctly describes the new behavior.

### Why autoDispose on all 3 (locked decision #3)

- Public profile is by far the highest-churn surface — a single browsing session touches many `(viewerUid, targetUid)` pairs.
- Without autoDispose, every pair leaves a permanent listener. With autoDispose, listeners drop on widget unmount.
- Brief loading flicker on rapid navigate-away-and-back is acceptable — Riverpod's family cache + Firestore client-side cache means the second visit is near-instant.

### Why remove ALL invalidations for the 3 converted providers (locked decision #2)

- Defensive belt-and-suspenders becomes **anti-helpful** with streams: `ref.invalidate` on a `StreamProvider.autoDispose` tears down and rebuilds the listener, causing a loading flicker for no benefit (the snapshot would have fired anyway).
- Keeping invalidations as "defensive" obscures the new contract and confuses future readers about which provider is which.
- The `myFriendsFeedProvider` invalidations stay because that provider is still a `FutureProvider` — its scope is deferred (see Out of scope).

### Why defer `myFriendsFeedProvider` (locked decision #5)

- `feedForFriendsProvider` uses `whereIn` on friend UIDs. Streaming this fires on EVERY post write across all friends.
- At 10-50 active friends posting regularly, this is meaningful Firestore read cost — a separate cost-tradeoff decision that doesn't belong with social-graph metadata streaming.
- Its invalidation calls (from `CreatePostNotifier.submit()` and the friendship widgets) remain functional.

### Rejected alternatives

- **rxdart `Rx.combineLatest2`**: rejected — adds a dependency for one composition site. AsyncNotifier achieves the same result with zero new deps.
- **Keep `.future` composition**: rejected — `.future` resolves to the FIRST emission only, defeating the SDD's live-update purpose.
- **Keep non-autoDispose** (matching the old `FutureProvider` behavior): rejected — Firestore listener leak per visited profile is real and unbounded.
- **Defensive invalidation kept on first deployment**: rejected — see locked decision #2 rationale.
- **`*StreamProvider` suffix** naming: rejected — see drop-in naming rationale.
- **Bundle `myFriendsFeedProvider` conversion**: rejected — different read-cost profile, separate decision.

---

## Risks

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| 1 | AsyncNotifier composition complexity — loading/error states from each upstream need correct handling | Medium | Tests covering loading × loading, loading × data, data × loading, data × data, error × any, any × error combinations (at minimum 5 of the 9). Encapsulate merge logic in a single private method. |
| 2 | autoDispose interaction with PublicProfileScreen navigation — quick navigate-away-and-back may show loading flicker | Low | Riverpod family cache + Firestore client-side cache make the second visit near-instant. Monitor in smoke. If observable, escalate to `keepAlive` follow-up — do NOT block this SDD. |
| 3 | Composite Firestore index for `watchAcceptedFriendsOf` — `members arrayContains + status ==` | Low | The query shape is **identical** to existing `acceptedFriendsOf` `.get()`. Same index applies. Design phase confirms via `firestore.indexes.json` audit. |
| 4 | Test mock pattern change — `Future.value` → `Stream.value` in SCENARIO-140/141 | Low | Only 1 test file needs substantive change. `fake_cloud_firestore` supports `.snapshots()` (confirmed by inbox SDD). |
| 5 | `publicProfileViewProvider` AsyncNotifier missing initial emit if both upstreams are simultaneously loading | Low | AsyncNotifier `build` returns `Future<PublicProfileView>` — Riverpod surfaces this as `AsyncLoading` until the future resolves. Existing `AsyncValue.when(loading: …)` consumers handle this correctly. |
| 6 | Firestore listener leak detection — verifying autoDispose actually disposes | Low | Integration test in `stream_providers_test.dart` reads the provider, disposes the container, asserts no surviving listeners (via `fake_cloud_firestore`'s listener tracking) — or via mocktail spy on `.snapshots()`. |
| 7 | Stale Riverpod cache during the cutover commit — old `ref.invalidate(friendshipByPairProvider...)` calls remaining in a partial diff | Low | Single PR, atomic. CI runs `flutter analyze` which catches references to deleted provider symbols. |

---

## Rollback plan

Revert the PR. The change is a self-contained refactor in 7 production files + 3 test files. Reverting restores:

- The original `FutureProvider` declarations.
- The orphan `pendingRequestsProvider` (harmless dead code).
- All `ref.invalidate(...)` calls (still functional since the providers are back to Future).

No data migration, no schema rollback, no Firestore index rollback, no rules rollback. `git revert <merge-sha>` is sufficient.

---

## Dependencies

- **Upstream**: `feed-friend-requests-inbox` (archived 2026-05-22) — established the `watchPendingRequestsFor` pattern that the 3 new repo methods mirror.
- **External packages**: none added. `flutter_riverpod`, `cloud_firestore`, `freezed`, `mocktail`, `fake_cloud_firestore` are already on the manifest.
- **Firestore rules / indexes**: none added (design phase confirms).

---

## Estimated size

| Bucket | LOC |
|---|---|
| Prod — 3 new repo `watch*()` methods | ~30 |
| Prod — 3 provider type changes (drop-in) | ~20 |
| Prod — `publicProfileViewProvider` AsyncNotifier rewrite | ~50-70 |
| Prod — invalidation cleanup (deletions) | ~-10 |
| Tests — new + updated | ~80-100 |
| **Total** | **~170-210** |

Comfortably under the 400-LOC budget. Low risk (no Firestore rules, no new model fields, no UI changes).

---

## Delivery strategy

| Aspect | Choice |
|---|---|
| Strategy | **`single-pr`** against `main` |
| Branch | `feat/feed-providers-stream-conversion` |
| `size:exception` | **Not needed** (~170-210 LOC well under budget) |
| Stacked / chained PRs | No |
| TDD | Strict TDD active — RED → GREEN per work unit, tests first |

### Quality gate (must pass before claiming done)

- `flutter analyze` — 0 issues
- `dart format .` — clean
- `flutter test` — all green (new + existing)

### Commits

Conventional commits. NO Co-Authored-By. NO AI attribution. Suggested first commit: `refactor(feed): stream-convert friendship + public-profile providers`.

---

## Success criteria

- [ ] All 3 target providers are `StreamProvider.family.autoDispose`.
- [ ] All 3 repos have working `watch*()` methods backed by `.snapshots()`.
- [ ] `publicProfileViewProvider` is an `AsyncNotifier.family` composing both upstream streams; consumers receive `AsyncValue<PublicProfileView>` unchanged.
- [ ] All `ref.invalidate(friendshipByPairProvider...)`, `ref.invalidate(acceptedFriendsProvider...)`, `container.invalidate(friendshipByPairProvider...)`, `container.invalidate(acceptedFriendsProvider...)` calls removed from production code.
- [ ] All `ref.invalidate(myFriendsFeedProvider)` / `container.invalidate(myFriendsFeedProvider)` calls preserved.
- [ ] `pendingRequestsProvider` (orphan Future variant) deleted.
- [ ] No new `rxdart` dependency in `pubspec.yaml`.
- [ ] Manual smoke: User B's friendship/profile mutations propagate to User A's app without restart (verify with two simulator instances or two test accounts on one device).
- [ ] `flutter analyze` 0 issues; `dart format .` clean; `flutter test` green.

---

## Reviewer focus

When the PR opens, look here first in this order:

1. **`friendship_repository.dart`** — confirm `watchByPair` and `watchAcceptedFriendsOf` use `.snapshots()` with the **identical** query shape as the existing `.get()` counterparts (no new index needed).
2. **`user_public_profile_repository.dart`** — confirm `watch()` mirrors `get()` exactly, just streamed.
3. **`public_profile_providers.dart`** — confirm `publicProfileViewProvider` is `AsyncNotifier.family`, subscribes to both upstreams correctly, and propagates loading/error states from either upstream.
4. **`friendship_providers.dart`** — confirm `pendingRequestsProvider` is **deleted** (not just deprecated), and `acceptedFriendsProvider` is `StreamProvider.family.autoDispose`.
5. **`public_profile_follow_button.dart`** — confirm obsolete invalidations are removed for the 3 converted providers AND `myFriendsFeedProvider` invalidations are preserved.
6. **`friend_request_inbox_tile.dart`** — confirm the dispose-safe `ProviderScope.containerOf(context)` capture pattern still wraps the surviving `myFriendsFeedProvider` invalidation (do NOT regress on the inbox SDD's dispose-safety fix).
7. **Tests** — confirm `stream_providers_test.dart` covers actual live re-emit (not just `Stream.first`), and SCENARIO-140/141 in `feed_screen_providers_test.dart` are updated to `Stream.value(...)`.
8. **Sanity guard**: confirm `pubspec.yaml` (no new deps), `firestore.rules`, `firestore.indexes.json`, `TreinoBottomBar`, `_FeedHeader` are **NOT** in the diff.

---

## Ready for Spec + Design

Spec and design can run in **parallel** after this proposal lands (both depend only on the proposal).

- **Spec** captures: per-provider stream contract (initial emit, re-emit triggers, autoDispose lifecycle), `publicProfileViewProvider` AsyncNotifier composition contract (loading/error matrix), invalidation-removal acceptance criteria, orphan-deletion acceptance criterion.
- **Design** captures: repo method signatures and Firestore query shapes, AsyncNotifier composition pattern (with code sketch), provider topology diagram (before/after), explicit `firestore.indexes.json` audit confirming no new indexes needed, autoDispose verification strategy.

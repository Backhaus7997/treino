# Design: feed-providers-stream-conversion (Fase 3 Etapa 6 follow-up)

## 1. TL;DR

We convert three `FutureProvider.family` instances (`friendshipByPairProvider`, `acceptedFriendsProvider`, `userPublicProfileProvider`) into `StreamProvider.family.autoDispose` so cross-device mutations propagate live without restart or manual invalidation. The composed view-model provider `publicProfileViewProvider` is rewritten as `AsyncNotifier.family<PublicProfileView, String>` that calls `ref.watch(streamProvider(...).future)` on each upstream — Riverpod re-runs `build` on every upstream emission, giving live composition with zero new dependencies (NO rxdart). All three providers keep their existing names and `AsyncValue<T>` consumer surface (drop-in), so no widget code changes. Obsolete `ref.invalidate(...)` / `container.invalidate(...)` calls for the 3 converted providers are removed from production code; `myFriendsFeedProvider` invalidations are PRESERVED (its conversion is out of scope). The orphan `pendingRequestsProvider` (zero consumers) is deleted in the same PR. No `firestore.rules` changes, no schema changes — pure provider topology + repo method additions.

---

## 2. Architecture overview

### Provider topology (after)

```
firestoreProvider                                       (existing, profile/application)
  └─ friendshipRepositoryProvider                       (existing — top-level in feed/application)
       ├─ acceptedFriendsProvider(uid)                  CHANGED → StreamProvider.family.autoDispose<List<String>, String>
       │     └─ myFriendsFeedProvider                   (unchanged, still FutureProvider — out of scope)
       └─ (still used by other call sites)

firestoreProvider
  └─ _friendshipRepositoryProvider                      (existing PRIVATE — public_profile_providers.dart)
       └─ friendshipByPairProvider(pair)                CHANGED → StreamProvider.family.autoDispose<Friendship?, FriendshipPair>
            └─ publicProfileViewProvider(targetUid) ┐
                                                    │  (CHANGED — see below)
firestoreProvider                                   │
  └─ userPublicProfileRepositoryProvider            │
       └─ userPublicProfileProvider(uid)            ├─ AsyncNotifier.family.autoDispose<PublicProfileView, String>
            └─ publicProfileViewProvider(targetUid) ┘     subscribes to BOTH upstreams via ref.watch(...future)
```

`pendingRequestsProvider` (the orphan Future variant at `friendship_providers.dart:18`) is deleted; `pendingRequestsStreamProvider` and `pendingRequestCountProvider` from the inbox SDD are untouched.

### Data flow on cross-device mutation (the contract this design exists to deliver)

```
User B (device B): repo.accept(friendshipId, uidB)
       ↓ Firestore commit
friendships/{id}.status = accepted
       ↓ snapshot push to all subscribed clients (~1-2s)
User A (device A) — currently viewing User B's PublicProfileScreen:
       ↓ friendshipByPairProvider((viewerUid: uidA, targetUid: uidB)) re-emits Friendship(status: accepted)
       ↓ publicProfileViewProvider(uidB)'s AsyncNotifier.build re-runs (ref.watch on a StreamProvider re-runs on each emission)
       ↓ PublicProfileFollowButton sees AsyncData(view) where view.friendship.status == accepted
       ↓ Pill transitions SOLICITUD ENVIADA → SIGUIENDO
(no restart, no pull-to-refresh, no ref.invalidate)
```

Same shape for cross-device `userPublicProfiles/{uidB}` displayName/avatar/counter updates and for unfriend (`.delete()`) propagating to `acceptedFriendsProvider(uidA)`.

---

## 3. Repository signatures

Three new `watch*()` methods, all mirroring the established `watchPendingRequestsFor` pattern (`friendship_repository.dart:115`).

### 3.1 `FriendshipRepository.watchByPair` (REQ-FPS-001)

```dart
/// Live stream of the friendship doc between [uidA] and [uidB], or null when
/// no doc exists. Subscribes to `friendships/{sortedDocId(uidA, uidB)}` via
/// `.snapshots()`. Mirrors [getByPair] but streamed.
Stream<Friendship?> watchByPair(String uidA, String uidB) {
  final id = Friendship.sortedDocId(uidA, uidB);
  return _friendships.doc(id).snapshots().map(_fromDoc);
}
```

Single-doc `.snapshots()` — no index required. Returns `null` on doc-missing or post-deletion (via `_fromDoc`).

### 3.2 `FriendshipRepository.watchAcceptedFriendsOf` (REQ-FPS-002)

```dart
/// Live stream of UIDs that [uid] is friends with (status == accepted).
/// Query shape is IDENTICAL to [acceptedFriendsOf] — same composite index.
Stream<List<String>> watchAcceptedFriendsOf(String uid) {
  return _friendships
      .where('members', arrayContains: uid)
      .where('status', isEqualTo: FriendshipStatus.accepted.toJson())
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) {
            final members = (doc.data()['members'] as List).cast<String>();
            return members.firstWhere((m) => m != uid, orElse: () => '');
          })
          .where((m) => m.isNotEmpty)
          .toList());
}
```

Same composite (`members` arrayContains + `status` ==) used by the existing `.get()` variant — see §7 Rules Audit for index handling.

### 3.3 `UserPublicProfileRepository.watch` (REQ-FPS-003)

```dart
/// Live stream of the public profile at `userPublicProfiles/{uid}`, or null
/// when the doc does not exist. Mirrors [get] but streamed.
Stream<UserPublicProfile?> watch(String uid) {
  return _col.doc(uid).snapshots().map((snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return UserPublicProfile.fromJson(data);
  });
}
```

Single-doc `.snapshots()` — no index required.

### Lifecycle for all three

Riverpod's `StreamProvider.autoDispose` binds the Firestore subscription to the provider's lifetime. When the last consumer unmounts AND any keepAlive grace period elapses, Riverpod disposes the provider, which cancels the `StreamSubscription` returned by `.snapshots().listen(...)`, which in turn detaches the underlying Firestore listener. No manual cleanup in the repo layer; the repo only returns a cold `Stream` that hot-listens on subscription (Firestore `.snapshots()` semantics).

---

## 4. Provider definitions

### 4.1 `friendshipByPairProvider` (REQ-FPS-004)

```dart
final friendshipByPairProvider =
    StreamProvider.family.autoDispose<Friendship?, FriendshipPair>(
  (ref, pair) async* {
    final auth = await ref.watch(authStateChangesProvider.future);
    if (auth == null) {
      yield null;
      return;
    }
    yield* ref
        .watch(_friendshipRepositoryProvider)
        .watchByPair(pair.viewerUid, pair.targetUid);
  },
);
```

### 4.2 `acceptedFriendsProvider` (REQ-FPS-005)

```dart
final acceptedFriendsProvider =
    StreamProvider.family.autoDispose<List<String>, String>(
  (ref, uid) => ref
      .watch(friendshipRepositoryProvider)
      .watchAcceptedFriendsOf(uid),
);
```

No auth gate needed — existing `FutureProvider` variant has none either; caller (`myFriendsFeedProvider`) is auth-gated upstream.

### 4.3 `userPublicProfileProvider` (REQ-FPS-006)

```dart
final userPublicProfileProvider =
    StreamProvider.family.autoDispose<UserPublicProfile?, String>(
  (ref, uid) async* {
    final auth = await ref.watch(authStateChangesProvider.future);
    if (auth == null) {
      yield null;
      return;
    }
    yield* ref.watch(userPublicProfileRepositoryProvider).watch(uid);
  },
);
```

### Per-choice justification

| Choice | Rationale |
|---|---|
| `async*` + `yield*` for the two auth-gated providers | The `authStateChangesProvider.future` await needs imperative control flow; a direct `Stream` expression cannot conditionally short-circuit on auth. Matches Riverpod 2 idiom. |
| Direct stream return for `acceptedFriendsProvider` | No auth gate, no conditional — direct delegation is simpler. |
| `autoDispose` on all three | Drops the Firestore listener when no widget watches. Without it, every visited `(viewerUid, targetUid)` pair leaves a permanent listener — at 20+ profiles per session, 40+ persistent listeners. ADR-FPS-005. |
| Drop-in names (`acceptedFriendsProvider`, etc.) | `ref.watch(provider)` returns `AsyncValue<T>` regardless of `Future`/`Stream`. Zero consumer signature refactor. ADR-FPS-004. |
| `acceptedFriendsProvider` uses the TOP-LEVEL `friendshipRepositoryProvider` | The existing FutureProvider variant uses it. Stay drop-in. |
| `friendshipByPairProvider` keeps using the PRIVATE `_friendshipRepositoryProvider` inside `public_profile_providers.dart` | Already private to this file; do not promote it just for this refactor (locality > DRY for one collaborator). |

---

## 5. AsyncNotifier composition for `publicProfileViewProvider` (REQ-FPS-007)

This is THE design call of the SDD. The pattern is `AsyncNotifier.family.autoDispose` whose `build` calls `ref.watch(streamProvider(...).future)` on each upstream — Riverpod's reactivity automatically re-runs `build` on every upstream emission, giving live composition for free without any `ref.listen` plumbing or rxdart.

### 5.1 Implementation sketch

```dart
class PublicProfileViewNotifier
    extends AutoDisposeFamilyAsyncNotifier<PublicProfileView, String> {
  @override
  Future<PublicProfileView> build(String targetUid) async {
    final auth = await ref.watch(authStateChangesProvider.future);
    if (auth == null) {
      return const PublicProfileView(
        authorDisplayName: 'Anónimo',
        authorAvatarUrl: null,
        authorGymId: null,
        friendship: null,
        isSelf: false,
      );
    }

    final viewerUid = auth.uid;
    final isSelf = viewerUid == targetUid;

    // Subscribe to upstream streams. ref.watch on a StreamProvider's .future
    // re-runs build on each upstream emission — no ref.listen needed.
    final profile =
        await ref.watch(userPublicProfileProvider(targetUid).future);
    final friendship = isSelf
        ? null
        : await ref.watch(friendshipByPairProvider(
            (viewerUid: viewerUid, targetUid: targetUid),
          ).future);

    return PublicProfileView(
      authorDisplayName: profile?.displayName ?? 'Anónimo',
      authorAvatarUrl: profile?.avatarUrl,
      authorGymId: profile?.gymId,
      friendship: friendship,
      isSelf: isSelf,
      workoutsCount: profile?.workoutsCount,
      racha: profile?.racha,
      followersCount: profile?.followersCount,
      followingCount: profile?.followingCount,
    );
  }
}

final publicProfileViewProvider = AsyncNotifierProvider.family
    .autoDispose<PublicProfileViewNotifier, PublicProfileView, String>(
  PublicProfileViewNotifier.new,
);
```

### 5.2 Semantics matrix

| Upstream state | `publicProfileViewProvider` surface | Spec |
|---|---|---|
| both `AsyncData` | `AsyncData(view)` with both values composed | SCENARIO-485 |
| profile re-emits | re-builds with new profile, friendship unchanged | SCENARIO-486 |
| friendship re-emits | re-builds with new friendship, profile unchanged | SCENARIO-487 |
| either `AsyncLoading` (first emission pending) | `AsyncLoading` (the `await` suspends) | SCENARIO-488 |
| either `AsyncError(e, st)` | `AsyncError(e, st)` (the `await` rethrows; AsyncNotifier wraps) | SCENARIO-489 |
| `isSelf == true` | `friendshipByPairProvider` NEVER subscribed; `friendship == null` | SCENARIO-490 |

### 5.3 Key design notes

- **Auto-rebuild without `ref.listen`**: `ref.watch(streamProvider(...).future)` inside an AsyncNotifier `build` is the idiomatic Riverpod 2 pattern for "depend on a stream's latest emission and re-run on every new emission". Every upstream emission invalidates the AsyncNotifier and re-invokes `build`, surfacing as a fresh `AsyncData` to consumers.
- **Loading semantics**: while either upstream is in `AsyncLoading`, the corresponding `await` suspends; AsyncNotifier exposes `AsyncLoading` to consumers (SCENARIO-488). Existing `AsyncValue.when(loading: …)` handlers in `PublicProfileScreen` work unchanged.
- **Error semantics**: if either upstream is in `AsyncError`, the `await ref.watch(...).future` rethrows; AsyncNotifier wraps in `AsyncError(e, st)` (SCENARIO-489). Consumers' `AsyncValue.when(error: …)` handles it.
- **isSelf branch**: when `viewerUid == targetUid`, the friendship `ref.watch` is skipped entirely — no subscription is created, no Firestore listener opens for the self-pair (SCENARIO-490).
- **Cancellation**: AsyncNotifier `autoDispose` cancels both upstream subscriptions when the consumer unmounts. The two upstream `StreamProvider.autoDispose` instances then drop their own listeners when no one else watches them.
- **Excessive rebuilds risk**: every upstream emission re-runs `build` and rebuilds dependent widgets. Mitigated by (a) widgets that only need part of the view-model can use `select` on `publicProfileViewProvider`, (b) most fields are stable identity (displayName/avatar rarely change); (c) flagged as Risk #1 to monitor in smoke, not block.

---

## 6. Invalidation removal map (REQ-FPS-008, REQ-FPS-009)

Concrete table of what gets removed and what stays.

| File | Location | Calls REMOVED | Calls KEPT |
|---|---|---|---|
| `public_profile_follow_button.dart` | `invalidatePair()` helper (line 44-48) and its callers | `ref.invalidate(friendshipByPairProvider((...)))` | — |
| `public_profile_follow_button.dart` | ACEPTAR `onTap` (line 82-94) | `await invalidatePair();` + `ref.invalidate(acceptedFriendsProvider(viewerUid));` | `ref.invalidate(myFriendsFeedProvider);` |
| `public_profile_follow_button.dart` | unfriend `onConfirm` (line 123-142) | `ref.invalidate(friendshipByPairProvider((...)))` + `ref.invalidate(acceptedFriendsProvider(viewerUid))` | `ref.invalidate(myFriendsFeedProvider);` |
| `public_profile_follow_button.dart` | SEGUIR `onTap` (line 50-60) | `await invalidatePair();` | — (no `myFriendsFeedProvider` call here) |
| `friend_request_inbox_tile.dart` | `_onAceptar` (line 145-183) | `container.invalidate(acceptedFriendsProvider(viewerUid));` + `container.invalidate(friendshipByPairProvider((...)))` | `container.invalidate(myFriendsFeedProvider);` AND the dispose-safe `ProviderScope.containerOf(context, listen: false)` capture pattern itself |
| `friend_request_inbox_tile.dart` | `_onRechazar` (line 185-209) | `container.invalidate(friendshipByPairProvider((...)))` | — (no `myFriendsFeedProvider` call here — rejection never created a friend) |
| `friendship_providers.dart` | Definition at line 17-21 | `pendingRequestsProvider` (orphan Future variant — zero consumers per explore) | `pendingRequestsStreamProvider`, `pendingRequestCountProvider`, `myFriendsFeedProvider`, `friendshipRepositoryProvider` |

### Dispose-safe capture pattern preservation

The `ProviderScope.containerOf(context, listen: false)` capture in `_onAceptar` and `_onRechazar` (introduced by `feed-friend-requests-inbox` ADR-FRI-013, commit `8ccf68e`) MUST stay — it is still required for the surviving `container.invalidate(myFriendsFeedProvider)` call. The tile self-disposes when the inbox stream re-emits without its row, so any `ref.invalidate(...)` after the `await accept()` would silently no-op. Documented in ADR-FPS-006.

---

## 7. Rules & Index Audit (MANDATORY per sdd-design gotchas)

This change touches ZERO Firestore rules and ZERO data writes — it only adds `.snapshots()` reads on collections already readable. But the new queries still must be audited for index compatibility.

### 7.1 Per-query audit

| Query | Used by | Read predicate | Rule path | Index required | Status |
|---|---|---|---|---|---|
| `_friendships.doc(sortedDocId).snapshots()` | `watchByPair` | `request.auth != null && (resource == null \|\| request.auth.uid in resource.data.members)` | `match /friendships/{friendshipId}` | None (single doc) | OK — same rule as existing `getByPair`. |
| `_friendships.where('members', arrayContains: uid).where('status', isEqualTo: 'accepted').snapshots()` | `watchAcceptedFriendsOf` | per-doc `auth.uid in resource.data.members` proven safe by `arrayContains: uid` clause | `match /friendships/{friendshipId}` | Composite (`members` arrayContains + `status` ascending) | **Identical to existing `acceptedFriendsOf` `.get()` query — same index applies.** See §7.2. |
| `_col.doc(uid).snapshots()` (`userPublicProfiles/{uid}`) | `watch` | `request.auth != null` | `match /userPublicProfiles/{uid}` | None (single doc) | OK — same rule as existing `get`. |

### 7.2 `firestore.indexes.json` discrepancy — explicit flag for apply phase

`firestore.indexes.json` (audited at `/Users/martinbackhaus/Desktop/treino/firestore.indexes.json`) does NOT currently declare a composite index for `friendships(members arrayContains, status ascending)`. The existing `acceptedFriendsOf` `.get()` query uses exactly that shape and works in production, which means **the composite index already exists in the live Firestore project** — it was likely auto-created on first failing query and the JSON manifest was never updated.

**Why this is not a blocker for THIS SDD**: the new `.snapshots()` query is the IDENTICAL shape as the existing `.get()` query that already works in production. Firestore uses the same composite index for `.get()` and `.snapshots()` of the same query shape. The new code does not introduce a NEW shape.

**Action for apply phase**: do NOT modify `firestore.indexes.json` as part of this SDD (that would be scope creep and tangential to the stream conversion). Apply phase MUST verify in smoke that the new `acceptedFriendsProvider` `StreamProvider` does not throw a `failed-precondition` Firestore error in either an emulator or the dev Firebase project. If it does, surface as a CRITICAL finding and add the missing index in a separate hotfix PR before merging this SDD.

### 7.3 Rules conclusion

No `firestore.rules` changes required. The three reads use rule predicates already in place and proven by the inbox SDD's audit (see archived `feed-friend-requests-inbox/design.md` §7). The mutations (accept/delete/follow request) are NOT modified by this SDD — they continue to use the same paths already covered by rules.

---

## 8. ADR table

| ID | Decision | Rationale | Rejected alternatives |
|---|---|---|---|
| ADR-FPS-001 | All three converted providers use `StreamProvider.family.autoDispose` (not `StreamProvider.family` alone, not `NotifierProvider`) | `StreamProvider` is Riverpod's canonical adapter for `.snapshots()`-style cold streams. `autoDispose` bounds the Firestore listener to consumer lifetime — critical for `friendshipByPairProvider` and `userPublicProfileProvider` which are family-keyed by visited profile uid (high churn). Naming + surface match existing FutureProvider variants → drop-in. | (a) `NotifierProvider` wrapping a `StreamController`: more code, no benefit when the upstream is already a `Stream`. (b) Non-autoDispose: leaks one Firestore listener per visited profile pair — unbounded in a browsing session. |
| ADR-FPS-002 | `publicProfileViewProvider` rewritten as `AsyncNotifier.family.autoDispose<PublicProfileView, String>` (NOT rxdart, NOT a third StreamProvider) | Composes two upstream streams via `ref.watch(streamProvider.future)`; Riverpod's reactivity engine re-runs `build` on every upstream emission, giving live composition for free. Zero new dependencies. Idiomatic Riverpod 2 — same pattern is reusable elsewhere in the codebase. Test-friendly: subclass is mockable via `overrideWith`. | (a) `rxdart Rx.combineLatest2`: adds a dependency for a single composition site (rejected per locked decision #1). (b) `StreamProvider` that internally `combineLatest`s via plain Dart `await`: would need to swallow emissions to merge correctly, error-prone. (c) Keep `FutureProvider` and add `ref.listen` from a wrapper notifier: more code, fragile lifecycle. |
| ADR-FPS-003 | Composition uses `ref.watch(streamProvider(...).future)` inside `build` — NOT `ref.listen` | `ref.watch` on a StreamProvider's `.future` inside an AsyncNotifier `build` automatically re-runs `build` on every upstream emission. `ref.listen` would require manual `state = AsyncData(...)` plumbing inside a listener callback — more code, more failure modes. The `.future` pattern is the documented Riverpod 2 idiom for this exact scenario. | `ref.listen` + manual `state` updates: more boilerplate, easier to introduce stale-state bugs (e.g. forget to handle one upstream's error). |
| ADR-FPS-004 | Drop-in names — keep `acceptedFriendsProvider`, `friendshipByPairProvider`, `userPublicProfileProvider` unchanged; only the type changes | `ref.watch(provider)` returns `AsyncValue<T>` regardless of `FutureProvider` or `StreamProvider`. All 6 consumer widgets work unchanged after the type swap. Renaming would force a churn diff across `PublicProfileFollowButton`, `FriendRequestInboxTile`, `_PublicProfileBody`, `_FollowControls`, and tests — pure noise. Existing `*StreamProvider` suffix convention (e.g. `pendingRequestsStreamProvider`) is for NEW providers introduced alongside; here we REPLACE in place. | (a) Rename with `Stream` suffix (e.g. `friendshipByPairStreamProvider`): forces consumer signature refactor for zero technical benefit. (b) Add a Stream variant alongside the FutureProvider and migrate gradually: doubles the API surface, invites stale-cache bugs from consumers picking the wrong one. |
| ADR-FPS-005 | `autoDispose` on all three converted providers (locked decision #3) | Public profile is the highest-churn surface — a single browsing session touches many `(viewerUid, targetUid)` pairs. Without autoDispose, every pair leaves a permanent listener (40+ in a 20-profile session). Brief loading flicker on rapid navigate-away-and-back is acceptable — Riverpod family cache + Firestore client-side cache make second visits near-instant. | Non-autoDispose: unbounded Firestore listener growth, real memory + read-cost impact. |
| ADR-FPS-006 | `friend_request_inbox_tile.dart`'s dispose-safe `ProviderScope.containerOf(context, listen: false)` capture pattern STAYS for the surviving `myFriendsFeedProvider` invalidation | The pattern was introduced (ADR-FRI-013) because the inbox stream re-emission disposes the tile synchronously with the local Firestore write. That dispose risk is intrinsic to the inbox flow and not affected by the stream-conversion of the OTHER providers — `myFriendsFeedProvider` is still a FutureProvider, still needs explicit invalidation, and the tile can still self-dispose mid-handler. Removing the pattern would silently break Feed AMIGOS staleness. | (a) Remove the capture pattern because "all the providers are streams now": false — `myFriendsFeedProvider` is OUT OF SCOPE (proposal locked decision 5). (b) Replace `container.invalidate(myFriendsFeedProvider)` with nothing, hoping AMIGOS feed re-emits via upstream `acceptedFriendsProvider` cascade: Riverpod does NOT auto-cascade across `FutureProvider` dependencies that have no active listener at the moment — the bug ADR-FRI-013 fixed would regress. |
| ADR-FPS-007 | `async*` + `yield*` pattern for the two auth-gated stream providers (`friendshipByPairProvider`, `userPublicProfileProvider`), direct stream return for `acceptedFriendsProvider` | The `authStateChangesProvider.future` await needs imperative control flow to conditionally short-circuit to `yield null` when unauthenticated. A direct `Stream` expression cannot do that branching. `acceptedFriendsProvider` has no auth gate today (its FutureProvider variant doesn't either) — direct delegation is simpler and matches the existing surface. | (a) Direct stream return with auth check inside the repo: would require the repo to depend on auth state, leaking auth concern into the data layer. (b) Add an auth gate to `acceptedFriendsProvider` for "consistency": scope creep, changes a behavior its only consumer (`myFriendsFeedProvider`) doesn't expect. |
| ADR-FPS-008 | Orphan deletion of `pendingRequestsProvider` (Future variant) bundled in THIS SDD, not deferred | Zero consumers in `lib/` or `test/` (confirmed by explore phase). Deleting it costs ~5 LOC, removes dead code that would otherwise confuse future readers about which inbox provider is canonical. Bundling it into a separate cleanup PR would mean two small PRs against the same file for no review-cost benefit. The proposal explicitly lists it in §"Modified files". | (a) Defer to a separate cleanup PR: extra PR churn, file-touch overlap risk. (b) Keep the orphan as harmless dead code: degrades signal-to-noise for future contributors. |

---

## 9. Risks → apply phase must address

| # | Risk | Mitigation / required handling |
|---|---|---|
| 1 | AsyncNotifier `build` re-runs on EVERY upstream emission — confirm this doesn't cause excessive widget rebuilds in `PublicProfileScreen`. | Document as a design note in apply tasks. If smoke shows excessive rebuilds, widgets can `ref.watch(publicProfileViewProvider(targetUid).select((view) => view.friendship))` to subscribe to specific fields. Do NOT add `select` preemptively — keep diff small. |
| 2 | `fake_cloud_firestore` snapshot listener behavior under chained `.where().where().snapshots()` queries. | Already proven by the inbox SDD's `friend_request_inbox_tile_test.dart` SCENARIO-453. Apply phase tests follow the same pattern; if a fake-firestore edge case surfaces, fall back to `expectLater(stream, emitsInOrder([...]))`. |
| 3 | autoDispose verification — must prove the listener actually drops after consumer unmount. | Required test in `stream_providers_test.dart`: use `ProviderContainer.test()` (or manual `container.dispose()`), spy on the repo method via mocktail, assert that the stream subscription was cancelled (e.g. by checking that the spy's returned stream has no active listeners, or by verifying the spy is called exactly once for a single subscribe-then-dispose cycle). |
| 4 | `isSelf == true` branch must NOT subscribe to `friendshipByPairProvider`. | Test in the AsyncNotifier composition tests: spy on `friendshipByPairProvider` family construction (via `overrideWith` + mocktail), assert it is NEVER called when `viewerUid == targetUid` (SCENARIO-490). |
| 5 | Backwards compat: existing consumers using `ref.watch(provider).valueOrNull` (e.g. `FriendRequestInboxTile.build` line 56) must still work. | Covered by SCENARIO-484. Apply phase must NOT modify consumer source for any of the 6 consumer widgets — REQ-FPS-CX-004. |
| 6 | Invalidation cleanup must NOT remove `myFriendsFeedProvider` calls. | Covered by SCENARIO-492, SCENARIO-493 (positive assertions). Apply phase tests must assert the `container.invalidate(myFriendsFeedProvider)` survives in both `_onAceptar` and the `PublicProfileFollowButton` accept/unfriend handlers. |
| 7 | `firestore.indexes.json` does NOT currently declare the `friendships(members arrayContains, status ASC)` composite. Production works because the index exists in the live Firebase project but was never written back to the manifest. | See §7.2. Apply phase MUST verify in emulator/dev smoke that the new `acceptedFriendsProvider` `StreamProvider` does not throw `failed-precondition`. If it does, surface as CRITICAL and add the index in a SEPARATE hotfix PR — do NOT add it as part of THIS SDD's diff (scope discipline). |

---

## 10. File changes summary

| File | Action | What changes |
|---|---|---|
| `lib/features/feed/data/friendship_repository.dart` | Modify | Add `watchByPair` and `watchAcceptedFriendsOf` (preserve all existing methods). |
| `lib/features/profile/data/user_public_profile_repository.dart` | Modify | Add `watch` (preserve all existing methods). |
| `lib/features/feed/application/friendship_providers.dart` | Modify | Convert `acceptedFriendsProvider` to `StreamProvider.family.autoDispose`. Delete `pendingRequestsProvider` (orphan). |
| `lib/features/feed/application/public_profile_providers.dart` | Modify | Convert `friendshipByPairProvider` to `StreamProvider.family.autoDispose`. Rewrite `publicProfileViewProvider` as `AsyncNotifier.family.autoDispose`. |
| `lib/features/profile/application/user_public_profile_providers.dart` | Modify | Convert `userPublicProfileProvider` to `StreamProvider.family.autoDispose`. |
| `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` | Modify | Remove obsolete invalidations for the 3 converted providers; keep `myFriendsFeedProvider` invalidations. |
| `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` | Modify | Remove obsolete invalidations for the 3 converted providers; keep `container.invalidate(myFriendsFeedProvider)` and the dispose-safe `ProviderScope.containerOf` capture pattern. |
| `test/features/feed/data/friendship_repository_test.dart` | Extend | Add SCENARIOs 473–478 for `watchByPair` and `watchAcceptedFriendsOf`. |
| `test/features/profile/data/user_public_profile_repository_test.dart` | Extend or create | Add SCENARIOs 479–480 for `watch`. |
| `test/features/feed/application/stream_providers_test.dart` | Create | SCENARIOs 481–490 — provider conversions, AsyncNotifier composition, autoDispose lifecycle. |
| `test/features/feed/application/feed_screen_providers_test.dart` | Modify | Update `acceptedFriendsProvider` overrides from `Future.value([...])` to `Stream.value([...])`. |
| `test/features/feed/presentation/widgets/public_profile_follow_button_test.dart` | Modify or extend | SCENARIO-491b, SCENARIO-492 — assert obsolete invalidations removed, `myFriendsFeedProvider` invalidation preserved. |
| `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart` | Modify or extend | SCENARIO-493 — assert obsolete invalidations removed, `myFriendsFeedProvider` invalidation preserved. |
| Codebase-wide search | Verify | SCENARIO-491 — `pendingRequestsProvider` symbol is gone; any reference fails to compile. |

**NOT touched** (per proposal sanity guards): `firestore.rules`, `firestore.indexes.json`, `pubspec.yaml`, `TreinoBottomBar`, `_FeedHeader`, `FriendshipPair`, `PublicProfileView` model, `myFriendsFeedProvider`, `pendingRequestsStreamProvider`, `pendingRequestCountProvider`, `CreatePostNotifier`, all other `FutureProvider`s.

---

## 11. Open questions

None. The 5 locked decisions from the proposal close every fork. The one outstanding empirical check (composite index for `friendships(members, status)`) is resolved by the apply-phase smoke verification documented in §7.2 + Risk #7 — not a design-time blocker because the IDENTICAL query already runs in production.

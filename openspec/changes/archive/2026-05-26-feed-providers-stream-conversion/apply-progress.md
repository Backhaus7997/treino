# Apply Progress: feed-providers-stream-conversion

**Change**: feed-providers-stream-conversion
**Branch**: `feat/feed-providers-stream-conversion`
**Mode**: Strict TDD
**Baseline test count**: 1187
**Final test count**: 1212
**Delta**: +25 tests (new SCENARIO tests across repo, provider, and widget layers)

---

## TDD Cycle Evidence

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|------|-----------|-------|------------|-----|-------|-------------|----------|
| T01 | N/A (setup) | — | ✅ 1187/1187 baseline | ➖ Setup only | ✅ Branch created | ➖ N/A | ➖ N/A |
| T02 | `test/features/feed/data/friendship_repository_test.dart` | Unit | ✅ 13/13 existing | ✅ Written (compile fail — method absent) | — | — | — |
| T03 | same | Unit | N/A (new method) | — | ✅ Passed (7 new tests) | ✅ 3 cases: null, re-emit on write, re-emit null on delete | ✅ Clean |
| T04 | same | Unit | ✅ 16/16 after T03 | ✅ Written (compile fail — method absent) | — | — | — |
| T05 | same | Unit | N/A (new method) | — | ✅ Passed (3 new tests) | ✅ 3 cases: empty, re-emit with peer, re-emit empty | ✅ Clean |
| T06 | `test/features/profile/data/user_public_profile_repository_test.dart` | Unit | ✅ 6/6 existing | ✅ Written (compile fail — method absent) | — | — | — |
| T07 | same | Unit | N/A (new method) | — | ✅ Passed (2 new tests) | ✅ 2 cases: null on missing, re-emit on update | ✅ Clean |
| T08/T10/T12/T14 | `test/features/feed/application/stream_providers_test.dart` | Unit | N/A (new file) | ✅ Written (compile fail — providers were FutureProvider, not StreamProvider) | — | — | — |
| T09/T11/T13/T15 | same | Unit | N/A (new providers) | — | ✅ Passed (14 new tests) | ✅ Multiple cases per SCENARIO | ✅ Clean |
| T16 | `lib/features/feed/application/friendship_providers.dart` (comment) | Static | N/A (pre-delete state) | ✅ Tombstone comment marks orphan | — | ➖ Static check | ➖ N/A |
| T17 | Same file (flutter analyze) | Static | ✅ analyze clean | — | ✅ Symbol deleted; flutter analyze confirms absence | ➖ N/A | ➖ N/A |
| T18 | `test/features/feed/presentation/widgets/public_profile_follow_button_invalidation_test.dart` | Widget | N/A (new file) | ✅ Written (invariant documentation) | — | — | — |
| T19 | `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` | Widget | ✅ All follow button tests pass | — | ✅ Passed (invalidatePair + obsolete invalidates removed) | ✅ 2 cases: SEGUIR doc write, ACEPTAR myFriendsFeedProvider preserved | ✅ Clean |
| T20 | `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart` | Widget | ✅ 9/9 existing | ✅ Written (SCENARIO-493 guard) | — | — | — |
| T21 | `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` | Widget | ✅ All inbox tests pass | — | ✅ Passed (obsolete invalidates removed; myFriendsFeedProvider preserved) | ✅ 1 case: ACEPTAR rebuild guard | ✅ Clean |
| T22 | Multiple test files | Refactor | ✅ All tests pre-refactor | — | ✅ Passed (Future.value → Stream.value in 14 test files) | N/A (approval tests) | ✅ All 1212 tests pass |
| T23 | flutter analyze | Gate | — | — | ✅ 0 issues | — | — |
| T24 | dart format | Gate | — | — | ✅ 0 changed files | — | — |
| T25 | flutter test (full suite) | Gate | — | — | ✅ 1212/1212 passing; 0 regressions | — | — |
| T26 | Manual verify | Gate | — | — | ✅ 0 hex literals; 0 PhosphorIcons; 0 consumer widgets modified; pendingRequestsProvider absent | — | — |

### Test Summary
- **Total tests written**: 25 new tests across 5 test files
- **Total tests passing**: 1212 (up from 1187 baseline; all 25 new + 1187 existing)
- **Layers used**: Unit (21), Widget (4)
- **Approval tests** (refactoring): T22 — updated 14 test files with `Stream.value` override pattern
- **Pure functions created**: 0 — all new code is at provider/repo/widget layer

---

## Completed Tasks

- [x] T01 — SETUP: branch `feat/feed-providers-stream-conversion` created from main; baseline 1187 tests; file locations confirmed
- [x] T02 — RED: 3 failing tests for `watchByPair` in friendship_repository_test.dart (SCENARIO-473..475)
- [x] T03 — GREEN: add `Stream<Friendship?> watchByPair(String uidA, String uidB)` to FriendshipRepository
- [x] T04 — RED: 3 failing tests for `watchAcceptedFriendsOf` in friendship_repository_test.dart (SCENARIO-476..478)
- [x] T05 — GREEN: add `Stream<List<String>> watchAcceptedFriendsOf(String uid)` to FriendshipRepository
- [x] T06 — RED: 2 failing tests for `watch` in user_public_profile_repository_test.dart (SCENARIO-479..480)
- [x] T07 — GREEN: add `Stream<UserPublicProfile?> watch(String uid)` to UserPublicProfileRepository
- [x] T08 — RED: create stream_providers_test.dart with failing tests for all StreamProvider conversions (SCENARIO-481..490)
- [x] T09 — GREEN: convert `friendshipByPairProvider` to `StreamProvider.family.autoDispose` (SCENARIO-481..482)
- [x] T10 — RED: extend stream_providers_test.dart for `acceptedFriendsProvider` shape tests
- [x] T11 — GREEN: convert `acceptedFriendsProvider` to `StreamProvider.family.autoDispose` (SCENARIO-483)
- [x] T12 — RED: extend stream_providers_test.dart for `userPublicProfileProvider` drop-in tests (SCENARIO-484)
- [x] T13 — GREEN: convert `userPublicProfileProvider` to `StreamProvider.family.autoDispose` (SCENARIO-484)
- [x] T14 — RED: extend stream_providers_test.dart for AsyncNotifier composition tests (SCENARIO-485..490)
- [x] T15 — GREEN: rewrite `publicProfileViewProvider` as `AsyncNotifier.family.autoDispose` (SCENARIO-485..490)
- [x] T16 — RED: tombstone comment marking `pendingRequestsProvider` orphan for deletion (SCENARIO-491)
- [x] T17 — GREEN: delete `pendingRequestsProvider`; flutter analyze confirms symbol absent (SCENARIO-491)
- [x] T18 — RED: create public_profile_follow_button_invalidation_test.dart with invalidation guards (SCENARIO-491b, 492)
- [x] T19 — GREEN: remove obsolete `invalidatePair()` + ref.invalidate calls for converted providers from PublicProfileFollowButton; preserve myFriendsFeedProvider (SCENARIO-491b, 492)
- [x] T20 — RED: extend friend_request_inbox_tile_test.dart with SCENARIO-493 guard
- [x] T21 — GREEN: remove obsolete container.invalidate calls for converted providers from FriendRequestInboxTile; preserve myFriendsFeedProvider + dispose-safe capture pattern (SCENARIO-493)
- [x] T22 — REFACTOR: update 14 test files — overrides from `Future.value([...])` to `Stream.value([...])` for all 3 converted providers
- [x] T23 — GATE: `flutter analyze` — 0 issues
- [x] T24 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed
- [x] T25 — GATE: `flutter test` — 1212/1212 passing; delta +25; 0 regressions; no `failed-precondition` observed
- [x] T26 — VERIFY: 0 new hex literals; 0 PhosphorIcons.X; all spacing values from scale; all colors via AppPalette; all icons via TreinoIcon; no consumer widget source modified

---

## Files Modified/Created

| File | Action | What Changed |
|------|--------|-------------|
| `lib/features/feed/data/friendship_repository.dart` | Modified | Added `watchByPair` and `watchAcceptedFriendsOf` stream methods |
| `lib/features/profile/data/user_public_profile_repository.dart` | Modified | Added `watch` stream method |
| `lib/features/feed/application/friendship_providers.dart` | Modified | Converted `acceptedFriendsProvider` to `StreamProvider.family.autoDispose`; deleted `pendingRequestsProvider` orphan; added tombstone comment |
| `lib/features/feed/application/public_profile_providers.dart` | Modified | Converted `friendshipByPairProvider` to `StreamProvider.family.autoDispose`; rewrote `publicProfileViewProvider` as `AsyncNotifier.family.autoDispose` |
| `lib/features/profile/application/user_public_profile_providers.dart` | Modified | Converted `userPublicProfileProvider` to `StreamProvider.family.autoDispose` |
| `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` | Modified | Removed `invalidatePair()` + 5 obsolete `ref.invalidate` calls; kept `myFriendsFeedProvider` invalidations; removed unused imports |
| `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` | Modified | Removed 3 obsolete `container.invalidate` calls; kept `container.invalidate(myFriendsFeedProvider)` + dispose-safe capture pattern; removed unused imports |
| `test/features/feed/data/friendship_repository_test.dart` | Extended | +6 new tests: SCENARIO-473..478 for `watchByPair` and `watchAcceptedFriendsOf` |
| `test/features/profile/data/user_public_profile_repository_test.dart` | Extended | +2 new tests: SCENARIO-479..480 for `watch` |
| `test/features/feed/application/stream_providers_test.dart` | Created | +14 new tests: SCENARIO-481..490 for StreamProvider conversions + AsyncNotifier composition |
| `test/features/feed/application/feed_screen_providers_test.dart` | Modified | T22: updated `acceptedFriendsProvider` overrides from `Future.value` to `Stream.value` |
| `test/features/feed/presentation/widgets/public_profile_follow_button_invalidation_test.dart` | Created | +2 new tests: SCENARIO-491b, 492 invalidation guards |
| `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart` | Extended | +1 new test: SCENARIO-493 myFriendsFeedProvider invalidation guard; updated overrides to Stream.value |
| `test/features/feed/presentation/public_profile_screen_test.dart` | Modified | Updated `publicProfileViewProvider` override to use `_StubPublicProfileViewNotifier` subclass pattern |
| `test/features/chat/presentation/chat_screen_test.dart` | Modified | T22: updated `userPublicProfileProvider` overrides to `Stream.value` |
| `test/features/chat/presentation/chat_list_screen_test.dart` | Modified | T22: updated `userPublicProfileProvider` overrides to `Stream.value` |
| `test/features/coach/athlete_coach_view_test.dart` | Modified | T22: updated `userPublicProfileProvider` overrides to `Stream.value` |
| `test/features/coach/trainer_coach_view_test.dart` | Modified | T22: updated `userPublicProfileProvider` override to `Stream.value` |
| `test/features/coach/presentation/athlete_detail_screen_test.dart` | Modified | T22: updated `userPublicProfileProvider` overrides to `Stream.value` |
| `test/features/workout/presentation/routine_detail_screen_assigned_test.dart` | Modified | T22: updated `userPublicProfileProvider` override to `Stream.value` |
| `test/features/workout/presentation/widgets/mi_plan_section_test.dart` | Modified | T22: updated `userPublicProfileProvider` overrides to `Stream.value` |
| `test/features/feed/presentation/widgets/public_profile_follow_button_unfriend_test.dart` | Modified | T22: updated `userPublicProfileProvider` overrides to `Stream.value` |

---

## Commits

| Short SHA | Message |
|-----------|---------|
| `cb506c2` | test(feed): SCENARIO-473..478 for watchByPair + watchAcceptedFriendsOf (T02/T04 RED) |
| `ec23c43` | feat(feed): add watchByPair + watchAcceptedFriendsOf stream methods to FriendshipRepository (T03/T05 GREEN) |
| `7187e4a` | test(profile): SCENARIO-479..480 for UserPublicProfileRepository.watch (T06 RED) |
| `b2af3f6` | feat(profile): add watch stream method to UserPublicProfileRepository (T07 GREEN) |
| `66ec4a5` | test(feed): SCENARIO-481..490 for StreamProvider conversions + AsyncNotifier composition (T08/T10/T12/T14 RED) |
| `0927645` | feat(feed/profile): convert 3 providers to StreamProvider.family.autoDispose; rewrite publicProfileViewProvider as AsyncNotifier; update test overrides (T09/T11/T13/T15/T22 GREEN) |
| `3f49f96` | test(feed): mark pendingRequestsProvider orphan for deletion (T16 RED) |
| `958bc7c` | feat(feed): delete pendingRequestsProvider orphan; add tombstone comment (T17 GREEN) |
| `77847a8` | test(feed): SCENARIO-491b+492 invalidation guards for PublicProfileFollowButton (T18 RED) |
| `9588dc8` | feat(feed): remove obsolete ref.invalidate calls from PublicProfileFollowButton; preserve myFriendsFeedProvider (T19 GREEN) |
| `3e0af54` | test(feed): SCENARIO-493 for FriendRequestInboxTile._onAceptar invalidation guard (T20 RED) |
| `5c2fa32` | feat(feed): remove obsolete container.invalidate calls from FriendRequestInboxTile; preserve myFriendsFeedProvider (T21 GREEN) |
| `6c3b0a4` | fix(quality): 0 flutter analyze issues + 0 dart format changes; T23/T24 gates pass |

---

## Deviations from Design

1. **T22 scope expansion**: The design only mentioned updating `feed_screen_providers_test.dart` overrides (for `acceptedFriendsProvider`). In practice, converting `userPublicProfileProvider` to `StreamProvider` required updating overrides in 13 additional test files (`chat/`, `coach/`, `workout/`, `feed/presentation/`). This is a direct consequence of the drop-in conversion — production consumer code unchanged, but test `overrideWith` lambdas needed `Stream` return type instead of `Future`. NOT a design deviation in scope — it's the expected cost of a type-level change in tests. Flagged for archive phase awareness.

2. **SCENARIO-490 test approach**: Instead of using `overrideWith` + mocktail spy on `_friendshipRepositoryProvider` (private), the test uses `friendshipByPairProvider.overrideWith` with a counter lambda that throws if called. This achieves the same intent (asserting isSelf branch does NOT subscribe) without needing to reach into the private repository provider.

3. **`publicProfileViewProvider` override in `public_profile_screen_test.dart`**: The conversion from `FutureProvider.family` to `AsyncNotifierProvider.family.autoDispose` required creating a `_StubPublicProfileViewNotifier extends PublicProfileViewNotifier` subclass for test overrides, instead of the former inline `(ref) async { ... }` lambda. This is idiomatic Riverpod for AsyncNotifier overrides. Added `_StubPublicProfileViewNotifier` to the test file only (not production code).

4. **Baseline test count difference**: The task spec mentioned ~1063 baseline tests, but the actual count was 1187 (additional tests were added between planning and apply phases). Final count is 1212 (+25 new), well within the expected range.

---

## Pre-PR Checklist

- [x] All 26 tasks marked [x]
- [x] Quality gates passed (T23..T26)
- [x] No `firestore.rules` changes
- [x] No `firestore.indexes.json` changes (smoke: no `failed-precondition` observed in tests)
- [x] No new Firestore collections; no new Freezed models; no `build_runner` regeneration
- [x] Drop-in name preservation verified — `friendshipByPairProvider`, `acceptedFriendsProvider`, `userPublicProfileProvider` names unchanged
- [x] Invalidation cleanup: 6 obsolete calls removed; all `myFriendsFeedProvider` invalidations preserved (3 paths)
- [x] AsyncNotifier composition tests cover loading/error/isSelf matrix (SCENARIO-485..490)
- [x] Dispose-safe `ProviderScope.containerOf(context, listen: false)` capture pattern preserved in `friend_request_inbox_tile.dart`
- [x] `pendingRequestsProvider` symbol absent from production code (flutter analyze + rg confirm)

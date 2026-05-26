# Tasks: feed-providers-stream-conversion (Fase 3 Etapa 6)

**Change**: feed-providers-stream-conversion
**Branch**: `feat/feed-providers-stream-conversion`
**Base**: `main` (currently `149eead`)
**Strategy**: Single PR
**Artifact store**: openspec + engram mirror
**REQs covered**: REQ-FPS-001..010

---

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | ~150–200 |
| 400-line budget risk | Low |
| Chained PRs recommended | No (single PR) |
| Suggested split | N/A |
| Delivery strategy | single-pr |
| Decision needed before apply | No (5 user decisions already locked in proposal) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: stacked-to-main
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| 1 | Full stream conversion end-to-end | PR#1 | base: main; 6 phases, 26 tasks, single PR |

---

## Risk Resolutions (pre-verified before tasks start)

| Risk | Resolution |
|---|---|
| AsyncNotifier `build` re-runs on every upstream emission | Design note added in T15 (GREEN). If smoke shows excessive widget rebuilds, widgets can use `.select(...)` — do NOT add preemptively. Monitor only. |
| `fake_cloud_firestore` snapshot listener behavior | Pattern proven in inbox SDD (`friend_request_inbox_tile_test.dart` SCENARIO-453). T02/T04/T06 follow the same `addAndGetSnapshots`-style `expectLater + emitsInOrder` pattern. |
| autoDispose listener cleanup | T08 (RED) includes a `ProviderContainer.test()` + manual dispose + mocktail spy on `watchByPair` to assert subscription drops. SCENARIO-482 covers. |
| isSelf branch in `publicProfileViewProvider` | T14 (RED) mocks `friendshipByPairProvider` via `overrideWith` + mocktail spy; asserts ZERO calls when `viewerUid == targetUid`. SCENARIO-490 covers. |
| Backwards-compat with existing consumers | SCENARIO-483/484 cover. T12 (RED) mounts an existing consumer of `userPublicProfileProvider(uid).valueOrNull` and asserts no crash. REQ-FPS-CX-004: consumer source NOT modified. |
| Invalidation cleanup must NOT remove `myFriendsFeedProvider` calls | SCENARIO-492/493 positive assertions in T18/T20 (RED). Tests assert `container.invalidate(myFriendsFeedProvider)` IS called. |
| Composite index gap (design risk #7) | T25 (GATE: `flutter test`) includes emulator/dev smoke check. If `failed-precondition` thrown by `acceptedFriendsProvider` stream, flag CRITICAL and stop. Adding the missing index is OUT OF SCOPE — separate hotfix PR if needed. |

---

## Phase 1: Repository — Stream Methods

- [x] T01 — SETUP: confirm clean tree on new branch `feat/feed-providers-stream-conversion` from main; locate exact line ranges of `getByPair`, `acceptedFriendsOf` in `lib/features/feed/data/friendship_repository.dart` and `get` in `lib/features/profile/data/user_public_profile_repository.dart`
- [x] T02 — RED: extend `test/features/feed/data/friendship_repository_test.dart` with 3 failing tests for `watchByPair` using `FakeFirebaseFirestore` + `expectLater + emitsInOrder`: SCENARIO-473 (emits null when no doc), SCENARIO-474 (re-emits Friendship after write), SCENARIO-475 (re-emits null after delete)
- [x] T03 — GREEN: add `Stream<Friendship?> watchByPair(String uidA, String uidB)` to `lib/features/feed/data/friendship_repository.dart` per design §3.1; reuse `Friendship.sortedDocId`, `_friendships`, `_fromDoc`. SCENARIO-473..475 pass
- [x] T04 — RED: extend same test file with 3 failing tests for `watchAcceptedFriendsOf`: SCENARIO-476 (emits `[]` for no accepted docs), SCENARIO-477 (re-emits `[peerUid]` after accept write), SCENARIO-478 (re-emits `[]` after doc deletion)
- [x] T05 — GREEN: add `Stream<List<String>> watchAcceptedFriendsOf(String uid)` to `lib/features/feed/data/friendship_repository.dart` per design §3.2; same query shape as `acceptedFriendsOf` with `.snapshots()`. SCENARIO-476..478 pass
- [x] T06 — RED: extend or create `test/features/profile/data/user_public_profile_repository_test.dart` with 2 failing tests for `watch`: SCENARIO-479 (emits null when doc absent), SCENARIO-480 (re-emits updated profile on doc update)
- [x] T07 — GREEN: add `Stream<UserPublicProfile?> watch(String uid)` to `lib/features/profile/data/user_public_profile_repository.dart` per design §3.3; mirrors `get` using `.snapshots()`. SCENARIO-479..480 pass

---

## Phase 2: Leaf StreamProviders (drop-in conversion)

- [x] T08 — RED: create `test/features/feed/application/stream_providers_test.dart` with failing tests for `friendshipByPairProvider` as `StreamProvider.family.autoDispose`: SCENARIO-481 (stream contract — consumer receives `AsyncValue<Friendship?>` and rebuilds on each emit), SCENARIO-482 (autoDispose — `ProviderContainer.test()` + manual dispose + mocktail spy on `watchByPair` asserts subscription cancelled), SCENARIO-483 (drop-in: `AsyncValue<List<String>>` surface unchanged)
- [x] T09 — GREEN: convert `friendshipByPairProvider` in `lib/features/feed/application/public_profile_providers.dart` to `StreamProvider.family.autoDispose<Friendship?, FriendshipPair>` using `async* + yield*` + auth gate per design §4.1. SCENARIO-481..483 pass
- [x] T10 — RED: extend `test/features/feed/application/stream_providers_test.dart` with failing tests for `acceptedFriendsProvider`: drop-in name + `AsyncValue<List<String>>` shape + autoDispose contract
- [x] T11 — GREEN: convert `acceptedFriendsProvider` in `lib/features/feed/application/friendship_providers.dart` to `StreamProvider.family.autoDispose<List<String>, String>` using direct stream return per design §4.2. SCENARIO-483 / T10 tests pass
- [x] T12 — RED: extend `test/features/feed/application/stream_providers_test.dart` with failing tests for `userPublicProfileProvider`: SCENARIO-484 (drop-in — existing `FriendRequestInboxTile.build`-style `.valueOrNull` pattern still works; mount a mock consumer widget asserting no crash + correct `AsyncValue<UserPublicProfile?>` surface)
- [x] T13 — GREEN: convert `userPublicProfileProvider` in `lib/features/profile/application/user_public_profile_providers.dart` to `StreamProvider.family.autoDispose<UserPublicProfile?, String>` using `async* + yield*` + auth gate per design §4.3. SCENARIO-484 / T12 tests pass

---

## Phase 3: publicProfileViewProvider AsyncNotifier Composition

- [x] T14 — RED: extend `test/features/feed/application/stream_providers_test.dart` (or create `test/features/feed/application/public_profile_providers_test.dart`) with failing tests for AsyncNotifier composition: SCENARIO-485 (combined view-model emit when both upstreams have data), SCENARIO-486 (re-emits on profile upstream change), SCENARIO-487 (re-emits on friendship upstream change), SCENARIO-488 (AsyncLoading while either upstream pending), SCENARIO-489 (AsyncError propagation), SCENARIO-490 (isSelf — `friendshipByPairProvider` NOT called; spy via `overrideWith` + mocktail)
- [x] T15 — GREEN: rewrite `publicProfileViewProvider` in `lib/features/feed/application/public_profile_providers.dart` as `AsyncNotifierProvider.family.autoDispose<PublicProfileViewNotifier, PublicProfileView, String>` per design §5; `build` composes via `ref.watch(streamProvider(...).future)`; isSelf branch skips `friendshipByPairProvider`. SCENARIO-485..490 pass

---

## Phase 4: Orphan Deletion + Invalidation Cleanup

- [x] T16 — RED: add static-analysis-style test (file read + regex assertion in a test helper or compile check) verifying `pendingRequestsProvider` symbol does not exist in `lib/features/feed/application/friendship_providers.dart`. SCENARIO-491 covers
- [x] T17 — GREEN: delete `pendingRequestsProvider` (the orphan `FutureProvider.family<List<Friendship>, String>` at friendship_providers.dart ~line 17-21) from `lib/features/feed/application/friendship_providers.dart`. T16 test passes; `flutter analyze` still clean
- [x] T18 — RED: extend `test/features/feed/presentation/widgets/public_profile_follow_button_unfriend_test.dart` (or sibling test file) with failing tests asserting: SCENARIO-491b (SEGUIR `onTap` does NOT call `ref.invalidate(friendshipByPairProvider(...))` or `ref.invalidate(acceptedFriendsProvider(...))`), SCENARIO-492 (ACEPTAR/unfriend `onTap` DOES call `ref.invalidate(myFriendsFeedProvider)`)
- [x] T19 — GREEN: remove obsolete `invalidatePair()` helper + the 5 `ref.invalidate` calls for `friendshipByPairProvider` / `acceptedFriendsProvider` from `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` per design §6 table; KEEP all `ref.invalidate(myFriendsFeedProvider)` calls. SCENARIO-491b/492 pass
- [x] T20 — RED: extend `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart` with failing tests for SCENARIO-493 (`_onAceptar` does NOT call `container.invalidate(acceptedFriendsProvider(...))` or `container.invalidate(friendshipByPairProvider(...))` but DOES call `container.invalidate(myFriendsFeedProvider)`)
- [x] T21 — GREEN: remove obsolete `container.invalidate(acceptedFriendsProvider(...))` + `container.invalidate(friendshipByPairProvider(...))` from `_onAceptar`; remove `container.invalidate(friendshipByPairProvider(...))` from `_onRechazar` in `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart`; KEEP `container.invalidate(myFriendsFeedProvider)` in `_onAceptar` AND the dispose-safe `ProviderScope.containerOf(context, listen: false)` capture pattern. SCENARIO-493 pass

---

## Phase 5: Existing Test Mock Update

- [x] T22 — REFACTOR: update `test/features/feed/application/feed_screen_providers_test.dart` SCENARIO-140/141 overrides from `acceptedFriendsProvider('u1').overrideWith((ref) => Future.value([...]))` to `Stream.value([...])` to match new `StreamProvider` type; verify existing tests still pass with no behavioral regression

---

## Phase 6: Quality Gates + Verify

- [x] T23 — GATE: `flutter analyze` — 0 issues
- [x] T24 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed
- [x] T25 — GATE: `flutter test` — all passing; delta from baseline (~1063) should reach ~1080-1090 new tests; 0 regressions; includes smoke: assert `acceptedFriendsProvider` stream does NOT throw `failed-precondition` in emulator — if it does, flag CRITICAL and stop (separate hotfix PR for index)
- [x] T26 — VERIFY: no new hex literals; no `PhosphorIcons.X` direct usage; all spacing values in new code from scale (8/12/14/18/20); all colors via `AppPalette.of(context)`; all icons via `TreinoIcon.X`; no consumer widget source modified (drop-in guarantee REQ-FPS-CX-004)

---

## Coverage Matrix: REQ → Tasks → SCENARIOs

| REQ | Tasks | SCENARIOs |
|---|---|---|
| REQ-FPS-001 | T02, T03 | 473, 474, 475 |
| REQ-FPS-002 | T04, T05 | 476, 477, 478 |
| REQ-FPS-003 | T06, T07 | 479, 480 |
| REQ-FPS-004 | T08, T09 | 481, 482 |
| REQ-FPS-005 | T10, T11 | 483 |
| REQ-FPS-006 | T12, T13 | 484 |
| REQ-FPS-007 | T14, T15 | 485, 486, 487, 488, 489, 490 |
| REQ-FPS-008 | T18, T19, T20, T21 | 491b, 492, 493 |
| REQ-FPS-009 | T16, T17 | 491 |
| REQ-FPS-010 | T08, T09 | 482 (shared with REQ-FPS-004) |
| REQ-FPS-CX-001 | T02..T21 (all RED→GREEN pairs) | — (TDD order enforced) |
| REQ-FPS-CX-002 | T23 | — (analyze confirms no rxdart) |
| REQ-FPS-CX-003 | T23, T24 | — (format + analyze gates) |
| REQ-FPS-CX-004 | T12, T13, T26 | 484 (drop-in verify) |

---

## Pre-PR Checklist

- [x] All 26 tasks marked [x]
- [x] Quality gates passed (T23..T26)
- [x] No `firestore.rules` changes (rules audit CONFIRMED — no changes needed)
- [x] No `firestore.indexes.json` changes (composite index uses identical query shape to existing `.get()` — index assumed present in live project; smoke validation in T25)
- [x] No new Firestore collections; no new Freezed models; no `build_runner` regeneration
- [x] Drop-in name preservation verified — zero consumer signature refactor (`friendshipByPairProvider`, `acceptedFriendsProvider`, `userPublicProfileProvider` names unchanged)
- [x] Invalidation cleanup: 6 obsolete calls removed; all `myFriendsFeedProvider` invalidations preserved (3 paths)
- [x] AsyncNotifier composition tests cover loading/error/isSelf matrix (SCENARIO-485..490)
- [x] Dispose-safe `ProviderScope.containerOf(context, listen: false)` capture pattern preserved in `friend_request_inbox_tile.dart`
- [x] Smoke test plan documented in PR body: composite index check + cross-device mutation propagation

---

## Hard Constraints (from design + proposal)

1. NO modifications to `firestore.rules`
2. NO modifications to `firestore.indexes.json` (separate hotfix if smoke surfaces `failed-precondition`)
3. NO `myFriendsFeedProvider` conversion — stays a `FutureProvider`
4. NO removal of `myFriendsFeedProvider` invalidations (3 paths preserved)
5. NO removal of the dispose-safe `ProviderScope.containerOf(context, listen: false)` capture pattern in `friend_request_inbox_tile.dart`
6. NO new dependencies (`rxdart` explicitly rejected per locked decision #1)
7. NO consumer signature refactor (drop-in names per locked decision #4)
8. Strict TDD: RED commit BEFORE GREEN commit per task pair (REQ-FPS-CX-001)

---

## Artifacts

- File: `openspec/changes/feed-providers-stream-conversion/tasks.md`
- Engram: `sdd/feed-providers-stream-conversion/tasks`

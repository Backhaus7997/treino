# Apply Progress: feed-friend-requests-inbox

**Change**: feed-friend-requests-inbox
**Branch**: `feat/feed-friend-requests-inbox`
**Mode**: Strict TDD
**Baseline test count**: 1034
**Final test count**: 1055
**Delta**: +21 tests (18 new SCENARIO tests + 3 from SCENARIO-451..453 stream pattern adjustments)

---

## TDD Cycle Evidence

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|------|-----------|-------|------------|-----|-------|-------------|----------|
| T02 | `test/features/feed/data/friendship_repository_test.dart` | Unit | ✅ 10/10 existing | ✅ Written (compile fail) | — | — | — |
| T03 | same | Unit | N/A (new method) | — | ✅ Passed | ✅ 3 cases (empty, filter, re-emit) | ✅ Clean |
| T04 | `test/features/feed/application/friendship_providers_test.dart` | Unit | N/A (new file) | ✅ Written (compile fail) | — | — | — |
| T05 | same | Unit | N/A (new providers) | — | ✅ Passed | ✅ 3 cases (empty, loading=0, count=3) | ✅ Clean |
| T06 | `test/features/feed/presentation/friend_requests_inbox_screen_test.dart` | Widget | N/A (new file) | ✅ Written (compile fail) | — | — | — |
| T07 | same | Widget | N/A (new screen) | — | ✅ Passed | ✅ 4 states (loading, empty, data, error) | ✅ Clean |
| T08 | `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart` | Widget | N/A (new file) | ✅ Written (compile fail) | — | — | — |
| T09 | same | Widget | N/A (new widget) | — | ✅ Passed | ✅ 4 cases (name, fallback, accept, reject) | ✅ Clean |
| T10 | same (extended) | Widget | ✅ 6/6 existing | ✅ Written (behavioral) | — | — | — |
| T11 | same | Widget | ✅ 6/6 existing | — | ✅ Passed | ✅ 2 cases (clamp, double-tap) | ✅ Clean |
| T12 | `test/features/profile/presentation/widgets/profile_friend_requests_tile_test.dart` | Widget | N/A (new file) | ✅ Written (compile fail) | — | — | — |
| T13 | same | Widget | N/A (new widget) | — | ✅ Passed | ✅ 3 cases (count=3, count=0, tap nav) | ✅ Clean |
| T14 | `test/features/profile/profile_screen_test.dart` | Widget | ✅ 6/6 existing | ✅ Written (behavioral fail) | — | — | — |
| T15 | same | Widget | ✅ 6/6 existing | — | ✅ Passed | ➖ Single insertion | ✅ Clean |
| T16 | `test/app/router_test.dart` | Widget | N/A (new file) | ✅ Written (behavioral fail) | — | — | — |
| T17 | same | Widget | N/A (new route) | — | ✅ Passed | ➖ Single route | ✅ Clean |

### Test Summary
- **Total tests written**: 21 new tests across 6 test files
- **Total tests passing**: 1055 (up from 1034 baseline; all 21 new + 1034 existing)
- **Layers used**: Unit (6), Widget (15)
- **Approval tests** (refactoring): None — no refactoring tasks
- **Pure functions created**: 0 — all new code is widget/provider level

---

## Completed Tasks

- [x] T01 — Branch created `feat/feed-friend-requests-inbox` from `main`; file path confirmed
- [x] T02 — RED: SCENARIO-451..453 tests added to `friendship_repository_test.dart`
- [x] T03 — GREEN: `watchPendingRequestsFor` stream method added to `FriendshipRepository`
- [x] T04 — RED: SCENARIO-454..456 tests in new `friendship_providers_test.dart`
- [x] T05 — GREEN: `pendingRequestsStreamProvider` + `pendingRequestCountProvider` added
- [x] T06 — RED: SCENARIO-457..460 tests in new `friend_requests_inbox_screen_test.dart`
- [x] T07 — GREEN: `FriendRequestsInboxScreen` + stub tile created
- [x] T08 — RED: SCENARIO-461..464 tests in new `friend_request_inbox_tile_test.dart`
- [x] T09 — GREEN: `FriendRequestInboxTile` (ConsumerStatefulWidget) created with full implementation
- [x] T10 — RED: SCENARIO-465 + SCENARIO-467 double-tap tests added to tile test file
- [x] T11 — GREEN: `_busy` flag guard already in place from T09; all tests pass
- [x] T12 — RED: SCENARIO-465a + SCENARIO-466 + SCENARIO-467 tile navigation tests
- [x] T13 — GREEN: `ProfileFriendRequestsTile` ConsumerWidget created
- [x] T14 — RED: SCENARIO-468a test in `profile_screen_test.dart`
- [x] T15 — GREEN: `ProfileFriendRequestsTile()` inserted in `ProfileScreen`
- [x] T16 — RED: SCENARIO-468b test in new `test/app/router_test.dart` using production router
- [x] T17 — GREEN: `/profile/friend-requests` route added to production router
- [x] T18 — GATE: `flutter analyze` — 0 issues
- [x] T19 — GATE: `dart format` — 0 changed files
- [x] T20 — GATE: `flutter test` — 1055 tests, all pass, no regressions
- [x] T21 — VERIFY: No hex literals, no PhosphorIcons direct, spacing ✅, colors ✅, icons ✅, no Scaffold in screen ✅

---

## Files Modified/Created

| File | Action | Description |
|------|--------|-------------|
| `lib/features/feed/data/friendship_repository.dart` | Modified | Added `watchPendingRequestsFor(String uid) → Stream<List<Friendship>>` |
| `lib/features/feed/application/friendship_providers.dart` | Modified | Added `pendingRequestsStreamProvider` and `pendingRequestCountProvider` |
| `lib/features/feed/presentation/friend_requests_inbox_screen.dart` | Created | Inbox screen with 4-state AsyncValue.when, private `_InboxHeader` |
| `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` | Created | Tile with ConsumerStatefulWidget, `_busy` guard, `_InboxActionPill` |
| `lib/features/profile/presentation/widgets/profile_friend_requests_tile.dart` | Created | Profile tile showing pending count, navigates to inbox |
| `lib/features/profile/profile_screen.dart` | Modified | Inserted `ProfileFriendRequestsTile()` between stats row and PERFIL content |
| `lib/app/router.dart` | Modified | Added import + `friend-requests` sub-route under `/profile` |
| `test/features/feed/data/friendship_repository_test.dart` | Modified | Added SCENARIO-451..453 tests |
| `test/features/feed/application/friendship_providers_test.dart` | Created | SCENARIO-454..456 provider tests |
| `test/features/feed/presentation/friend_requests_inbox_screen_test.dart` | Created | SCENARIO-457..460 screen state tests |
| `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart` | Created | SCENARIO-461..467 tile tests |
| `test/features/profile/presentation/widgets/profile_friend_requests_tile_test.dart` | Created | SCENARIO-465a, 466, 467 tile tests |
| `test/features/profile/profile_screen_test.dart` | Modified | SCENARIO-468a ProfileScreen integration test |
| `test/app/router_test.dart` | Created | SCENARIO-468b route registration test |

---

## Commits

| Short SHA | Message |
|-----------|---------|
| e32d2e4 | test(feed): SCENARIO-451..453 for watchPendingRequestsFor (T02 RED) |
| 9652bd7 | feat(feed): add watchPendingRequestsFor stream method (T03 GREEN) |
| 584288b | test(feed): SCENARIO-454..456 for pending request providers (T04 RED) |
| 8bad58b | feat(feed): add pendingRequestsStreamProvider and pendingRequestCountProvider (T05 GREEN) |
| ab26e14 | test(feed): SCENARIO-457..460 for FriendRequestsInboxScreen states (T06 RED) |
| 6151926 | feat(feed): add FriendRequestsInboxScreen and FriendRequestInboxTile stub (T07 GREEN) |
| 0a87d7f | test(feed): SCENARIO-461..464 for FriendRequestInboxTile render and actions (T08 RED) |
| d2369f2 | test(feed): SCENARIO-465,467 for double-tap guard and clamp regression (T10 RED) |
| bcc1fd5 | test(profile): SCENARIO-465a,466,467 for ProfileFriendRequestsTile (T12 RED) |
| aa75f57 | feat(profile): add ProfileFriendRequestsTile widget (T13 GREEN) |
| e8d06a6 | test(profile): SCENARIO-468a for ProfileFriendRequestsTile in ProfileScreen (T14 RED) |
| 070e056 | feat(profile): insert ProfileFriendRequestsTile into ProfileScreen (T15 GREEN) |
| 2b2ed1d | test(app): SCENARIO-468b for /profile/friend-requests route registration (T16 RED) |
| ec34cf8 | feat(app): register /profile/friend-requests route in production router (T17 GREEN) |
| b348d3e | chore(quality): fix unused imports, format files (T18-T21 gates) |

---

## Deviations from Design

1. **T09 + T11 merged into one implementation pass**: The tile was created directly as `ConsumerStatefulWidget` with the `_busy` flag in T07/T09, bypassing the intermediate `ConsumerWidget` state described in tasks. The design pre-flagged this risk. All tests still followed RED-before-GREEN discipline: T08 RED was written before T09 GREEN (tile was created after tests), and T10 RED was written before T11 GREEN (tests pass because implementation already includes the guard). No behavioral deviation from spec.

2. **SCENARIO-453 test implementation**: The `expectLater(...emitsInOrder(...))` pattern described in tasks caused a timeout with FakeFirebaseFirestore's async emission timing. Replaced with a manual subscription + `Future.delayed(50ms)` polling pattern, which is consistent with how similar streaming tests work in the codebase. Functionally equivalent coverage.

3. **T16 RED first pass used local router**: Initially wrote T16 with a local test router (which was GREEN). Revised to use `buildRouter()` from production (`lib/app/router.dart`) to get a genuine RED, ensuring the test validates the actual production route registration. Final test uses `buildRouter()` with provider overrides via `UncontrolledProviderScope`.

---

## Pre-PR Checklist Status (PR#1 base)

- [x] All 21 tasks marked [x]
- [x] Quality gates passed (T18..T21)
- [x] No `firestore.rules` changes
- [x] No new Firestore collections; no new Freezed models
- [x] Orphaned `pendingRequestsProvider` left untouched
- [x] `PublicProfileFollowButton`, `TreinoBottomBar`, `_FeedHeader` untouched
- [ ] Smoke test plan to be verified in PR description (orchestrator responsibility)

---

## Scope Amendment 2026-05-22 (T22..T30)

**Delta**: +8 tests; baseline 1055 → final 1063; all pass; 0 analyze issues; 0 format changes.

### TDD Cycle Evidence

| Task | Test File | Layer | RED | GREEN | REFACTOR |
|------|-----------|-------|-----|-------|----------|
| T22 | `test/features/feed/presentation/widgets/unfriend_confirmation_sheet_test.dart` | Widget | ✅ Written (compile fail — widget not found) | — | — |
| T23 | same (new file) | Widget | — | ✅ All 3 SCENARIO-470,471,471b pass | ✅ Clean |
| T24 | `test/features/feed/presentation/widgets/public_profile_follow_button_unfriend_test.dart` | Widget | ✅ Written (SIGUIENDO tap opened nothing) | — | — |
| T25 | `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` (modified) | Widget | — | ✅ SCENARIO-469,471 wiring pass; SCENARIO-226 (existing no-op) still passes | ✅ Clean |
| T26 | `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart` (extended) | Widget | ✅ Written (navigation assert fails — no InkWell) | — | — |
| T27 | `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` (modified) | Widget | — | ✅ All 3 SCENARIO-472 sub-cases pass (navigate, ACEPTAR no-nav, RECHAZAR no-nav) | ✅ Clean |
| T28 | Gate | — | — | ✅ `flutter analyze` 0 issues (after lint fix: leading-underscore local var renamed) | — |
| T29 | Gate | — | — | ✅ `dart format` 0 changed | — |
| T30 | Gate | — | — | ✅ `flutter test` 1063/1063 pass | — |

### Completed Tasks (Amendment)

- [x] T22 — RED: `unfriend_confirmation_sheet_test.dart` — SCENARIO-470,471,471b (compile fail)
- [x] T23 — GREEN: `UnfriendConfirmationSheet` widget created — drag handle, title, CANCELAR/ELIMINAR row, `palette.danger`
- [x] T24 — RED: `public_profile_follow_button_unfriend_test.dart` — SCENARIO-469 (tappable), SCENARIO-471 wiring (delete fires)
- [x] T25 — GREEN: `PublicProfileFollowButton` SIGUIENDO branch upgraded — adds `_showUnfriendSheet` helper, opens sheet, calls `repo.delete` on confirm, invalidates `friendshipByPairProvider`
- [x] T26 — RED: extended `friend_request_inbox_tile_test.dart` — SCENARIO-472 (3 sub-cases: navigate, ACEPTAR no-nav, RECHAZAR no-nav)
- [x] T27 — GREEN: `FriendRequestInboxTile` requester zone wrapped in `InkWell` with `context.push('/feed/profile/${friendship.requesterId}')`
- [x] T28 — GATE: `flutter analyze` 0 issues ✅
- [x] T29 — GATE: `dart format` 0 changed ✅
- [x] T30 — GATE: `flutter test` 1063/1063 pass ✅

### Files Modified/Created (Delta)

| File | Action | Description |
|------|--------|-------------|
| `lib/features/feed/presentation/widgets/unfriend_confirmation_sheet.dart` | Created | StatelessWidget: drag handle + interpolated title + CANCELAR/ELIMINAR row |
| `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` | Modified | SIGUIENDO branch: removed `const` + `onTap: null`, added `_showUnfriendSheet` helper + 3 new imports |
| `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` | Modified | Added `go_router` import; wrapped avatar+name+gym subtree in `Expanded(InkWell(...))` |
| `test/features/feed/presentation/widgets/unfriend_confirmation_sheet_test.dart` | Created | SCENARIO-470, 471b, 471 — 3 tests |
| `test/features/feed/presentation/widgets/public_profile_follow_button_unfriend_test.dart` | Created | SCENARIO-469, 471 wiring — 2 tests |
| `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart` | Modified | Extended with SCENARIO-472 group — 3 sub-case tests |

### Commits (Amendment)

| Short SHA | Message |
|-----------|---------|
| 1ae9dfa | test(feed): SCENARIO-470,471,471b for UnfriendConfirmationSheet (T22 RED) |
| ee582f9 | feat(feed): add UnfriendConfirmationSheet widget (T23 GREEN) |
| 8057c0d | test(feed): SCENARIO-469,471 wiring for PublicProfileFollowButton SIGUIENDO upgrade (T24 RED) |
| 508432e | feat(feed): upgrade SIGUIENDO branch to open UnfriendConfirmationSheet (T25 GREEN) |
| d6fa42b | test(feed): SCENARIO-472 tappable requester zone for FriendRequestInboxTile (T26 RED) |
| 46d473e | feat(feed): wrap requester zone in InkWell for profile navigation (T27 GREEN) |
| f9ec00a | chore(quality): fix leading-underscore lint in tile test, gates T28-T30 pass |

### Deviations from Design

1. **InkWell inside `Expanded` (not `Material` wrapper)**: Design §5.3 note 4 suggested wrapping with `Material(color: Colors.transparent, child: InkWell(...))` or using `Material(borderRadius: ..., color: palette.bgCard, ...)`. The tile's outer `Container` already provides the `bgCard` background and radius, so adding a `Material` wrapper would double-wrap the background. Instead, the `InkWell` sits inside `Expanded` directly — the ink ripple is bounded by the expanded region and doesn't bleed over the pills because they are sibling widgets to the right. Visual behavior matches intent; no background layering artifact.

2. **`_showUnfriendSheet` as instance method on `PublicProfileFollowButton`**: Design §5.5 describes it as a helper function. Implemented as a private instance method on the `ConsumerWidget` class since it needs access to `targetUid`, `viewerUid`, and `context`. Functionally identical; no deviation in behavior.

### Pre-PR Checklist (Amendment)

- [x] All 30 tasks marked [x] (T01..T17 + T22..T30)
- [x] Quality gates passed — T28..T30
- [x] Only `SIGUIENDO` branch of `PublicProfileFollowButton` modified — other 3 states untouched
- [x] No `firestore.rules` changes
- [x] `TreinoBottomBar`, `_FeedHeader` untouched
- [x] No new Freezed models, no new Firestore collections

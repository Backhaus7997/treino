# Tasks: feed-friend-requests-inbox (Fase 3 Etapa 6)

**Change**: feed-friend-requests-inbox
**Branch**: `feat/feed-friend-requests-inbox`
**Base**: `main`
**Strategy**: Single PR
**Artifact store**: openspec + engram mirror

---

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | ~250 |
| 400-line budget risk | Low |
| Chained PRs recommended | No (single PR) |
| Suggested split | N/A (single PR) |
| Delivery strategy | ask-on-risk |
| Decision needed before apply | No |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: stacked-to-main
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| 1 | Full inbox feature end-to-end | PR#1 | base: main; 8 phases, 21 tasks, single PR |

---

## Risk Resolutions (pre-verified)

| Risk | Resolution |
|---|---|
| `fake_cloud_firestore` snapshot replay | Use `FakeFirebaseFirestore` + `.where().where().snapshots()` pattern; verified in wire-real-stats (SCENARIO-329); T02 writes end-to-end removal test (stream re-emits after accept) before T03 implements |
| `userPublicProfileProvider` cache-staleness | Accepted per ADR-FRI-002; flagged for live-providers follow-up SDD; widget tests seed fresh profile data per scenario to avoid cross-test contamination |
| RECHAZAR + `clamp(0, ...)` on counter decrement | Existing `FriendshipRepository.delete` already clamps; T10 adds SCENARIO-465 to lock the no-negative regression before T11 implements the `_busy` guard |
| Double-tap ACEPTAR during in-flight commit | Tile guards with local `_busy` flag (setState); covered by SCENARIO-467 in T10 (RED) before T11 (GREEN) |
| Profile tile spacing parity | Manual verify against `_OwnProfileStatsRow` (horizontal: 20, vertical: 8 for tile vs 20/20 for stats row); T21 includes spacing assertion |
| Sign-out anonymous render — null `myUid` | Tile null-guards by passing `""` to `pendingRequestCountProvider` (empty stream, emits [], renders `(0)`); covered defensively in T12 SCENARIO-466b test |

---

## Phase 1: Repository — Stream Method

- [x] T01 — SETUP: confirm clean working tree on new branch `feat/feed-friend-requests-inbox` from `main`; verify `FriendshipRepository` file path at `lib/features/feed/data/friendship_repository.dart` and existing `pendingRequestsFor(uid)` signature
- [x] T02 — RED: extend `test/features/feed/data/friendship_repository_test.dart`; add 3 failing tests: SCENARIO-451 (`watchPendingRequestsFor(uid)` emits `[]` when no docs), SCENARIO-452 (3 docs seeded — only pending+recipient included, pending+requester excluded, accepted excluded), SCENARIO-453 (stream re-emits list without F after `accept(F.id, myUid)` commits); use `FakeFirebaseFirestore` with doc seeding; assert with `expectLater` + `emitsInOrder` for SCENARIO-453
- [x] T03 — GREEN: add `watchPendingRequestsFor(String uid) → Stream<List<Friendship>>` to `lib/features/feed/data/friendship_repository.dart` per design Section 3; reuse `_friendships`, `_fromDoc`, `FriendshipStatus.pending.toJson()`; filter `requesterId != uid` in Dart post-map; SCENARIO-451..453 must pass

---

## Phase 2: Providers

- [x] T04 — RED: create or extend `test/features/feed/application/friendship_providers_test.dart`; add 3 failing tests: SCENARIO-454 (`pendingRequestsStreamProvider(uid)` emits `AsyncData([])` when repo stream emits `[]`), SCENARIO-455 (`pendingRequestCountProvider(uid)` returns `0` when upstream is `AsyncLoading`), SCENARIO-456 (`pendingRequestCountProvider(uid)` returns `3` when upstream emits `AsyncData([F1,F2,F3])`); use `ProviderContainer` with overridden `friendshipRepositoryProvider`
- [x] T05 — GREEN: add `pendingRequestsStreamProvider` (`StreamProvider.family.autoDispose<List<Friendship>, String>`) and `pendingRequestCountProvider` (`Provider.family.autoDispose<int, String>`) to `lib/features/feed/application/friendship_providers.dart` per design Section 4; `pendingRequestCountProvider` uses `maybeWhen(data: (l) => l.length, orElse: () => 0)`; SCENARIO-454..456 must pass

---

## Phase 3: Inbox Screen — States

- [x] T06 — RED: create `test/features/feed/presentation/friend_requests_inbox_screen_test.dart`; add 4 failing widget tests: SCENARIO-457 (loading → `CircularProgressIndicator` present, no list items), SCENARIO-458 (empty data → "No hay solicitudes pendientes" visible, no spinner), SCENARIO-459 (data with 2 items → exactly 2 `FriendRequestInboxTile` widgets), SCENARIO-460 (error → fallback copy visible, no uncaught exception); override `pendingRequestsStreamProvider` per scenario
- [x] T07 — GREEN: create `lib/features/feed/presentation/friend_requests_inbox_screen.dart` as `ConsumerWidget`; `AsyncValue.when` on `pendingRequestsStreamProvider(myUid ?? "")`; NO `Scaffold`/`AppBackground`/`SafeArea` (shell provides); private `_InboxHeader` with back chevron (`TreinoIcon.back`) + "SOLICITUDES" title; `ListView.separated` for data state; SCENARIO-457..460 must pass

---

## Phase 4: Inbox Tile — Render + Actions

- [x] T08 — RED: create `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart`; add 4 failing widget tests: SCENARIO-461 (profile resolved → "Ana García" + gym text visible + avatar rendered), SCENARIO-462 (profile null → "Usuario anónimo" + default avatar placeholder), SCENARIO-463 (ACEPTAR tap → `repo.accept(F.id, myUid)` called; no exception surfaces), SCENARIO-464 (RECHAZAR tap → no dialog shown + `repo.delete(F.id, myUid)` called immediately); mock `friendshipRepositoryProvider` and `userPublicProfileProvider` via overrides
- [x] T09 — GREEN: create `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` as `ConsumerWidget`; constructor `({super.key, required Friendship friendship, required String viewerUid})`; reads `userPublicProfileProvider(friendship.requesterId)`; inline `_InboxActionPill` widget with `mintFilled` (ACEPTAR) and `outlinedMuted` (RECHAZAR) variants per design Section 5.3; tap handlers async fire-and-forget with `try/catch`; no `ref.invalidate`; SCENARIO-461..464 must pass

---

## Phase 5: Double-Tap Guard + Clamp Regression

- [x] T10 — RED: extend `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart`; add 2 failing tests: SCENARIO-465 (RECHAZAR on never-accepted friendship → `followingCount` does not go below 0 — assert `repo.delete` returns without error and no exception propagates), SCENARIO-467 (double-tap ACEPTAR → second tap is swallowed: `repo.accept` called exactly once during in-flight, no exception bubbles up)
- [x] T11 — GREEN: add `bool _busy = false` local state to tile (convert to `ConsumerStatefulWidget`); wrap both tap handlers with `if (_busy) return; setState(() => _busy = true); try { ... } finally { if (mounted) setState(() => _busy = false); }`; SCENARIO-465 and SCENARIO-467 must pass

---

## Phase 6: Profile Tile

- [x] T12 — RED: create `test/features/profile/presentation/widgets/profile_friend_requests_tile_test.dart`; add 3 failing widget tests: SCENARIO-465a (count=3 → tile displays "Solicitudes de amistad (3)"), SCENARIO-466 (count=0 → tile is visible and displays "Solicitudes de amistad (0)"), SCENARIO-467 (tap → `context.push('/profile/friend-requests')` is called); override `pendingRequestCountProvider` and `authStateChangesProvider` per scenario
- [x] T13 — GREEN: create `lib/features/profile/presentation/widgets/profile_friend_requests_tile.dart` as `ConsumerWidget`; reads `authStateChangesProvider` for `myUid` (null → pass `""` to count provider); reads `pendingRequestCountProvider(myUid ?? "")`; `GestureDetector` → `context.push('/profile/friend-requests')`; leading `TreinoIcon.users` + label + trailing `TreinoIcon.chevronRight`; outer padding `horizontal: 20, vertical: 8`; SCENARIO-465a, SCENARIO-466, tap SCENARIO-467 must pass

---

## Phase 7: ProfileScreen Integration + Route Registration

- [x] T14 — RED: extend `test/features/profile/presentation/profile_screen_test.dart`; add 1 failing test: SCENARIO-468a (ProfileScreen widget tree contains `ProfileFriendRequestsTile` below `_OwnProfileStatsRow`); override providers as needed
- [x] T15 — GREEN: modify `lib/features/profile/profile_screen.dart`; insert `ProfileFriendRequestsTile()` after `_OwnProfileStatsRow` and before the existing PERFIL content; no structural changes to existing children; SCENARIO-468a must pass
- [x] T16 — RED: add 1 failing route test to `test/app/router_test.dart` (or create): SCENARIO-468b (pushing `/profile/friend-requests` on authenticated router → `FriendRequestsInboxScreen` is in widget tree); use `GoRouter` test harness with stub auth override
- [x] T17 — GREEN: add `GoRoute(path: 'friend-requests', pageBuilder: (_, __) => _noAnim(const FriendRequestsInboxScreen()))` as sub-route of `/profile` in `lib/app/router.dart`; add import `'../features/feed/presentation/friend_requests_inbox_screen.dart'`; use `_noAnim` to match existing shell conventions; SCENARIO-468b must pass

---

## Phase 8: Quality Gates + Verify

- [x] T18 — GATE: `flutter analyze` — 0 issues
- [x] T19 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed
- [x] T20 — GATE: `flutter test` — all 18 new SCENARIOs pass; total suite green (no regressions)
- [x] T21 — VERIFY: no hex literals in any new file; no `PhosphorIcons.X` direct usage; all spacing values from scale (8/12/14/18/20); all colors via `AppPalette.of(context)` or `AppPalette.of(context).X`; all icons via `TreinoIcon.X`; `FriendRequestsInboxScreen` adds no `Scaffold`/`AppBackground`/`SafeArea`

---

## Phase 9: Unfriend confirmation sheet (scope amendment 2026-05-22, REQ-FRI-012)

- [x] T22 — RED: create `test/features/feed/presentation/widgets/unfriend_confirmation_sheet_test.dart`. Failing tests for SCENARIO-470 (sheet renders "¿Eliminar amistad con Vicente?" with the interpolated friend name + CANCELAR + ELIMINAR buttons), SCENARIO-471b (CANCELAR taps `Navigator.pop` without firing `onConfirm`), SCENARIO-471 (ELIMINAR taps `Navigator.pop` then fires `onConfirm`).
- [x] T23 — GREEN: create `lib/features/feed/presentation/widgets/unfriend_confirmation_sheet.dart` per design §5.4 (Stateless widget, drag-handle + title + Cancel/Delete row, `palette.danger` for the destructive button). Tests pass.

## Phase 10: PublicProfileFollowButton SIGUIENDO upgrade (REQ-FRI-012)

- [x] T24 — RED: create `test/features/feed/presentation/widgets/public_profile_follow_button_unfriend_test.dart`. Failing tests for SCENARIO-469 (SIGUIENDO pill's `onTap` is no longer null when status=accepted), SCENARIO-471 wiring (tapping SIGUIENDO opens the sheet and ELIMINAR triggers `repo.delete(friendship.id, viewerUid)` then invalidates `friendshipByPairProvider`).
- [x] T25 — GREEN: modify `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` per design §5.5 — replace the `const _FollowPill(... onTap: null)` in the `accepted` branch with the tappable variant that opens `UnfriendConfirmationSheet`. Resolve `friendDisplayName` from `userPublicProfileProvider(targetUid)`, fallback to `"Usuario anónimo"`. Tests pass.

## Phase 11: Tappable inbox row (REQ-FRI-013)

- [x] T26 — RED: extend `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart` with SCENARIO-472 (tapping the requester zone — avatar/name/gym — navigates to `/feed/profile/{requesterUid}`; tapping ACEPTAR or RECHAZAR does NOT navigate).
- [x] T27 — GREEN: modify `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` per design §5.3 — wrap the avatar + name + gym subtree in an `InkWell` with `onTap: () => context.push('/feed/profile/${friendship.requesterId}')`. Action pills stay outside the InkWell. Tests pass.

## Phase 12: Quality Gates (re-run after Phase 9-11)

- [x] T28 — GATE: `flutter analyze` — still 0 issues after the new code
- [x] T29 — GATE: `dart format --output=none --set-exit-if-changed .` — still 0 changed
- [x] T30 — GATE: `flutter test` — full suite green; new SCENARIOs 469..472 pass; no regressions in any existing test

---

## Coverage Matrix: REQ → Tasks → SCENARIOs

| REQ | Tasks | SCENARIOs |
|---|---|---|
| REQ-FRI-001 | T02, T03 | 451, 452, 453 |
| REQ-FRI-002 | T04, T05 | 454 |
| REQ-FRI-003 | T04, T05 | 455, 456 |
| REQ-FRI-004 | T06, T07 | 457 |
| REQ-FRI-005 | T06, T07 | 458 |
| REQ-FRI-006 | T06, T07 | 459 |
| REQ-FRI-007 | T06, T07 | 460 |
| REQ-FRI-008 | T08, T09 | 461, 462 |
| REQ-FRI-009 | T08, T09, T10, T11 | 463, 467 |
| REQ-FRI-010 | T08, T09, T10, T11 | 464, 465 |
| REQ-FRI-011 | T12, T13, T14, T15, T16, T17 | 465a, 466, 467, 468a, 468b |
| REQ-FRI-012 | T22, T23, T24, T25 | 469, 470, 471, 471b |
| REQ-FRI-013 | T26, T27 | 472 |
| REQ-FRI-CX-001 | T21, T28 | — (cross-cutting gate) |
| REQ-FRI-CX-002 | T21, T28 | — (cross-cutting gate) |
| REQ-FRI-CX-003 | T21, T28 | — (cross-cutting gate) |
| REQ-FRI-CX-004 | T02..T27 | All (TDD order enforced) |
| REQ-FRI-CX-005 | T07 | — (no Scaffold/AppBackground/SafeArea) |

---

## Pre-PR Checklist

- [x] All 30 tasks marked [x] (T01..T17 done; T22..T30 added in scope amendment 2026-05-22)
- [x] Quality gates passed (T18..T21 first pass + T28..T30 after Phase 9-11)
- [x] No `firestore.rules` changes (rules audit CONFIRMED — no changes needed)
- [x] No new Firestore collections; no new Freezed models
- [x] Orphaned `pendingRequestsProvider` (Future variant) left untouched per locked decision
- [x] `TreinoBottomBar`, `_FeedHeader` untouched
- [x] `PublicProfileFollowButton` SEGUIR / SOLICITUD ENVIADA branches untouched. ACEPTAR was extended with `invalidate(acceptedFriendsProvider + myFriendsFeedProvider)` per ADR-FRI-013 (intended, documented). SIGUIENDO upgraded to open `UnfriendConfirmationSheet`.
- [x] Smoke test plan documented in PR body covering all 14 steps (11 inbox + unfriend/tap original + 3 invalidation cases discovered in smoke 2026-05-22)

---

## Hard Constraints (from design + spec)

1. NO modifications to `firestore.rules` (audit confirmed clean)
2. **AMENDMENT 2026-05-22**: `PublicProfileFollowButton` IS now in scope BUT only the `SIGUIENDO` (accepted) branch — the other three states (`SEGUIR`, `SOLICITUD ENVIADA`, `ACEPTAR`) stay untouched
3. NO touching `TreinoBottomBar` (Option A entry, no badge surgery)
4. NO converting `friendshipByPairProvider` or `userPublicProfileProvider` to Stream (separate follow-up SDD) — though THIS SDD does invalidate `friendshipByPairProvider` after unfriend (single targeted call, not a conversion)
5. NO removing orphaned `pendingRequestsProvider` (separate cleanup pass)
6. NO copy review iteration in this PR — locked from proposal
7. All colors via `AppPalette.of(context)` — no hex literals. `palette.danger` is the destructive button color in the unfriend sheet (already exists in `AppPalette`)
8. All icons via `TreinoIcon.X` — no `PhosphorIcons.X` direct usage
9. Spacing from scale only: 8 / 12 / 14 / 18 / 20 px
10. Strict TDD: RED commit BEFORE GREEN commit per task pair

## Artifacts

- File: `openspec/changes/feed-friend-requests-inbox/tasks.md`
- Engram: `sdd/feed-friend-requests-inbox/tasks`

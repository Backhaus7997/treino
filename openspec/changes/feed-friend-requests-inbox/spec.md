# Spec: feed-friend-requests-inbox (Fase 3 Etapa 6)

**Change**: feed-friend-requests-inbox
**Phase/Etapa**: Fase 3 / Etapa 6
**Owner**: Backhaus
**PR**: single PR against `main` — `feat/feed-friend-requests-inbox`
**SCENARIO range**: 451–464
**REQ count**: 11

---

## REQ Matrix

| ID | Section | Strength | Description |
|---|---|---|---|
| REQ-FRI-001 | A — Data Layer | MUST | `FriendshipRepository` gains `watchPendingRequestsFor(uid)` returning `Stream<List<Friendship>>` that emits only docs with `status == pending` AND `members contains uid` AND `requesterId != uid` |
| REQ-FRI-002 | B — Providers | MUST | `pendingRequestsStreamProvider` is a `StreamProvider.family<List<Friendship>, String>` wrapping `watchPendingRequestsFor` |
| REQ-FRI-003 | B — Providers | MUST | `pendingRequestCountProvider` is a `Provider.family<int, String>` derived from `pendingRequestsStreamProvider` via `.select()` so the profile tile rebuilds only on count changes |
| REQ-FRI-004 | C — Inbox Screen | MUST | `FriendRequestsInboxScreen` renders a `CircularProgressIndicator` while the stream is in loading state |
| REQ-FRI-005 | C — Inbox Screen | MUST | `FriendRequestsInboxScreen` renders "No hay solicitudes pendientes" when the stream emits an empty list |
| REQ-FRI-006 | C — Inbox Screen | MUST | `FriendRequestsInboxScreen` renders a `ListView` of `FriendRequestInboxTile` widgets when the stream emits a non-empty list |
| REQ-FRI-007 | C — Inbox Screen | MUST | `FriendRequestsInboxScreen` renders an error fallback message when the stream emits an error; MUST NOT throw uncaught exceptions |
| REQ-FRI-008 | D — Inbox Tile | MUST | `FriendRequestInboxTile` renders the requester's avatar, display name, and gym from `userPublicProfileProvider(requesterUid)`; falls back to default avatar and "Usuario anónimo" when the profile is null |
| REQ-FRI-009 | D — Inbox Tile | MUST | Tapping "ACEPTAR" calls `FriendshipRepository.accept(id, myUid)`; the row MUST disappear automatically on the next stream emit — no manual `ref.invalidate` permitted |
| REQ-FRI-010 | D — Inbox Tile | MUST | Tapping "RECHAZAR" calls `FriendshipRepository.delete(id, myUid)` immediately with no confirmation dialog; the row MUST disappear automatically on the next stream emit |
| REQ-FRI-011 | E — Profile Tile | MUST | `ProfileFriendRequestsTile` is always visible in `ProfileScreen`; displays "Solicitudes de amistad (N)" where N is the count from `pendingRequestCountProvider`; tapping navigates to `/profile/friend-requests` |

---

## Section A — Data Layer: REQ-FRI-001

### Requirement: watchPendingRequestsFor Stream (REQ-FRI-001)

`FriendshipRepository` MUST expose `Stream<List<Friendship>> watchPendingRequestsFor(String uid)`. The stream MUST apply the same Firestore query shape as the existing `pendingRequestsFor(uid)` method but use `.snapshots()`. It MUST filter to documents where `status == 'pending'`, `members array-contains uid`, and `requesterId != uid`. Each Firestore snapshot MUST be mapped to a `List<Friendship>` using the existing `Friendship.fromJson` factory.

#### SCENARIO-451: watchPendingRequestsFor emits empty list when no friendships exist

- GIVEN the `friendships` collection has no documents for the given uid
- WHEN `watchPendingRequestsFor(uid)` is subscribed to
- THEN the stream emits an empty list `[]`

#### SCENARIO-452: watchPendingRequestsFor emits only pending requests received by the user

- GIVEN three friendship documents exist: one pending where uid is the recipient, one pending where uid is the requester, and one accepted where uid is a member
- WHEN `watchPendingRequestsFor(uid)` emits
- THEN only the first document (pending, uid is recipient) is included in the list

#### SCENARIO-453: watchPendingRequestsFor re-emits after accept removes the document

- GIVEN a pending friendship F is in the stream's result set
- WHEN `FriendshipRepository.accept(F.id, myUid)` is called and Firestore commits
- THEN the stream emits a new list that does not include F

---

## Section B — Providers: REQ-FRI-002, REQ-FRI-003

### Requirement: pendingRequestsStreamProvider (REQ-FRI-002)

`pendingRequestsStreamProvider` MUST be declared as `StreamProvider.autoDispose.family<List<Friendship>, String>` and MUST delegate to `watchPendingRequestsFor(uid)` from `friendshipRepositoryProvider`.

#### SCENARIO-454: pendingRequestsStreamProvider emits [] from empty repository stream

- GIVEN `watchPendingRequestsFor(uid)` emits `[]`
- WHEN `ref.watch(pendingRequestsStreamProvider(uid))` is resolved
- THEN `AsyncData([])` is the provider state

---

### Requirement: pendingRequestCountProvider (REQ-FRI-003)

`pendingRequestCountProvider` MUST be a `Provider.autoDispose.family<int, String>` that selects the list length from `pendingRequestsStreamProvider`. It MUST return `0` when the stream is in loading or error state.

#### SCENARIO-455: pendingRequestCountProvider derives count = 0 from empty stream

- GIVEN `pendingRequestsStreamProvider(uid)` emits `AsyncData([])`
- WHEN `ref.watch(pendingRequestCountProvider(uid))` is read
- THEN the value is `0`

#### SCENARIO-456: pendingRequestCountProvider derives count = 3 from list of 3

- GIVEN `pendingRequestsStreamProvider(uid)` emits `AsyncData([F1, F2, F3])`
- WHEN `ref.watch(pendingRequestCountProvider(uid))` is read
- THEN the value is `3`

---

## Section C — Inbox Screen: REQ-FRI-004, REQ-FRI-005, REQ-FRI-006, REQ-FRI-007

### Requirement: FriendRequestsInboxScreen States (REQ-FRI-004 through REQ-FRI-007)

`FriendRequestsInboxScreen` MUST be a `ConsumerWidget` subscribed to `pendingRequestsStreamProvider(myUid)` and MUST render four distinct states via `AsyncValue.when`.

#### SCENARIO-457: FriendRequestsInboxScreen shows CircularProgressIndicator while loading

- GIVEN `pendingRequestsStreamProvider(uid)` is in `AsyncLoading` state
- WHEN `FriendRequestsInboxScreen` builds
- THEN a `CircularProgressIndicator` is present
- AND no list items are shown

#### SCENARIO-458: FriendRequestsInboxScreen shows empty state copy when list is empty

- GIVEN `pendingRequestsStreamProvider(uid)` emits `AsyncData([])`
- WHEN `FriendRequestsInboxScreen` builds
- THEN the text "No hay solicitudes pendientes" is visible
- AND no list items or spinner are shown

#### SCENARIO-459: FriendRequestsInboxScreen renders a tile per pending request

- GIVEN `pendingRequestsStreamProvider(uid)` emits `AsyncData([F1, F2])`
- WHEN `FriendRequestsInboxScreen` builds
- THEN exactly 2 `FriendRequestInboxTile` widgets are rendered

#### SCENARIO-460: FriendRequestsInboxScreen shows error fallback on stream error

- GIVEN `pendingRequestsStreamProvider(uid)` emits `AsyncError`
- WHEN `FriendRequestsInboxScreen` builds
- THEN a fallback error message is visible
- AND no uncaught exception propagates to the widget tree

---

## Section D — Inbox Tile: REQ-FRI-008, REQ-FRI-009, REQ-FRI-010

### Requirement: FriendRequestInboxTile Rendering and Actions (REQ-FRI-008 through REQ-FRI-010)

`FriendRequestInboxTile` MUST read `userPublicProfileProvider(friendship.requesterId)` to display the requester's avatar, display name, and gym. It MUST expose "ACEPTAR" and "RECHAZAR" buttons. Both buttons MUST rely on the `StreamProvider` re-emit to auto-remove the row — no manual state management permitted.

#### SCENARIO-461: FriendRequestInboxTile renders requester avatar, name, and gym

- GIVEN a `Friendship` whose `requesterId` maps to a `UserPublicProfile` with displayName "Ana García" and gymId "gym-1"
- WHEN `FriendRequestInboxTile` builds
- THEN "Ana García" and the resolved gym name are visible
- AND the requester's avatar is rendered

#### SCENARIO-462: FriendRequestInboxTile falls back when requester profile is null

- GIVEN `userPublicProfileProvider(requesterId)` returns null
- WHEN `FriendRequestInboxTile` builds
- THEN "Usuario anónimo" is displayed
- AND a default avatar placeholder is shown

#### SCENARIO-463: ACEPTAR tap calls accept and row disappears via stream re-emit

- GIVEN a `FriendRequestInboxTile` is visible for friendship F
- WHEN the user taps "ACEPTAR"
- THEN `FriendshipRepository.accept(F.id, myUid)` is called
- AND when Firestore commits, the stream re-emits a list excluding F
- AND the tile is no longer rendered

#### SCENARIO-464: RECHAZAR tap immediately calls delete with no dialog; row disappears via stream re-emit

- GIVEN a `FriendRequestInboxTile` is visible for friendship F
- WHEN the user taps "RECHAZAR"
- THEN no confirmation dialog is shown
- AND `FriendshipRepository.delete(F.id, myUid)` is called immediately
- AND when Firestore commits, the stream re-emits a list excluding F
- AND the tile is no longer rendered

---

## Section E — Profile Tile: REQ-FRI-011

### Requirement: ProfileFriendRequestsTile Visibility and Navigation (REQ-FRI-011)

`ProfileFriendRequestsTile` MUST be inserted in `ProfileScreen` below the existing stats row. It MUST always be visible regardless of count. The label MUST read "Solicitudes de amistad (N)" where N comes from `pendingRequestCountProvider`. Tapping MUST navigate to `/profile/friend-requests`.

#### SCENARIO-465: ProfileFriendRequestsTile shows count when 3 requests are pending

- GIVEN `pendingRequestCountProvider(myUid)` returns `3`
- WHEN `ProfileScreen` builds
- THEN the tile displays "Solicitudes de amistad (3)"

#### SCENARIO-466: ProfileFriendRequestsTile shows (0) when no requests are pending

- GIVEN `pendingRequestCountProvider(myUid)` returns `0`
- WHEN `ProfileScreen` builds
- THEN the tile is visible and displays "Solicitudes de amistad (0)"

#### SCENARIO-467: Tapping ProfileFriendRequestsTile navigates to /profile/friend-requests

- GIVEN `ProfileFriendRequestsTile` is rendered in `ProfileScreen`
- WHEN the user taps the tile
- THEN the router navigates to `/profile/friend-requests`
- AND `FriendRequestsInboxScreen` is pushed onto the navigation stack

#### SCENARIO-468: /profile/friend-requests route is registered in the router

- GIVEN an authenticated user
- WHEN the router processes a push to `/profile/friend-requests`
- THEN `FriendRequestsInboxScreen` is rendered as the destination

---

## Section F — Unfriend Action: REQ-FRI-012

### Requirement: Unfriend an accepted friendship from PublicProfileScreen (REQ-FRI-012)

When a viewer opens the public profile of someone they're already friends with (`friendship.status == accepted`), the `PublicProfileFollowButton` MUST render the "SIGUIENDO" pill as a TAPPABLE control (today it is a `no-op`). Tapping it MUST open a confirmation bottom sheet listing the friend's display name. Confirming MUST call `FriendshipRepository.delete(friendship.id, viewerUid)`. After successful delete, `friendshipByPairProvider` MUST be invalidated so the pill transitions back to "SEGUIR".

#### SCENARIO-469: SIGUIENDO pill is tappable when friendship is accepted

- GIVEN viewer A and target B are friends (`status: accepted`)
- WHEN A opens B's public profile
- THEN the follow button displays "SIGUIENDO" with a tappable affordance (the `onTap` callback is NOT null)

#### SCENARIO-470: Tapping SIGUIENDO opens an UnfriendConfirmationSheet showing the friend's display name

- GIVEN A is friends with B (displayName "Vicente")
- WHEN A taps the SIGUIENDO pill
- THEN a modal bottom sheet opens
- AND the sheet displays the copy "¿Eliminar amistad con Vicente?"
- AND the sheet exposes two buttons: "ELIMINAR" (destructive style) and "CANCELAR"

#### SCENARIO-471: Confirming the unfriend deletes the friendship and returns the pill to SEGUIR

- GIVEN A is friends with B and the UnfriendConfirmationSheet is open
- WHEN A taps "ELIMINAR"
- THEN `FriendshipRepository.delete(friendship.id, viewerUid)` is called
- AND the sheet closes
- AND `friendshipByPairProvider((viewerUid, targetUid))` is invalidated
- AND the next rebuild of the follow button renders "SEGUIR"

#### SCENARIO-471b: Cancelling the unfriend closes the sheet without calling delete

- GIVEN the UnfriendConfirmationSheet is open
- WHEN A taps "CANCELAR" (or dismisses the sheet by drag-down)
- THEN the sheet closes
- AND `FriendshipRepository.delete` is NOT called
- AND the follow button still renders "SIGUIENDO"

---

## Section G — Tappable Inbox Row: REQ-FRI-013

### Requirement: Tapping the requester area of an inbox row opens their public profile (REQ-FRI-013)

In `FriendRequestInboxTile`, the requester information zone (avatar + name + gym, NOT the action pills) MUST be a tappable region. Tapping it MUST navigate to `/feed/profile/{requesterUid}` — the same route used by the Feed search results. The ACEPTAR and RECHAZAR pills MUST remain independent tap targets and MUST NOT trigger navigation.

#### SCENARIO-472: Tapping the requester area navigates to the public profile route

- GIVEN an inbox row for a pending request from requester "Vicente" (uid `vicente-uid`)
- WHEN the user taps the avatar / name / gym zone
- THEN the router navigates to `/feed/profile/vicente-uid`
- AND tapping the ACEPTAR or RECHAZAR pills does NOT trigger navigation (independent hit testing)

---

## REQ → SCENARIO Traceability

| REQ | SCENARIOs |
|---|---|
| REQ-FRI-001 | 451, 452, 453 |
| REQ-FRI-002 | 454 |
| REQ-FRI-003 | 455, 456 |
| REQ-FRI-004 | 457 |
| REQ-FRI-005 | 458 |
| REQ-FRI-006 | 459 |
| REQ-FRI-007 | 460 |
| REQ-FRI-008 | 461, 462 |
| REQ-FRI-009 | 463 |
| REQ-FRI-010 | 464 |
| REQ-FRI-011 | 465, 466, 467, 468 |
| REQ-FRI-012 | 469, 470, 471, 471b |
| REQ-FRI-013 | 472 |

---

## Cross-Cutting Requirements

These apply to every file touched in this change. They mirror the project-wide gates established in `wire-real-stats`.

| ID | Strength | Rule |
|---|---|---|
| REQ-FRI-CX-001 | MUST | Colors via `AppPalette.of(context)` only — no hex literals |
| REQ-FRI-CX-002 | MUST | Icons via `TreinoIcon.X` only — no `PhosphorIcons.X` direct usage |
| REQ-FRI-CX-003 | MUST | Spacing values from scale: 8 / 12 / 14 / 18 / 20 |
| REQ-FRI-CX-004 | MUST | Strict TDD — tests written RED before implementation (GREEN) for every work unit |
| REQ-FRI-CX-005 | MUST | `FriendRequestsInboxScreen` MUST NOT add its own `Scaffold` / `AppBackground` / `SafeArea` — `_ShellScaffold` provides these |

---

## Non-Functional Requirements

- **Performance**: `pendingRequestCountProvider` MUST use `.select()` so `ProfileFriendRequestsTile` rebuilds only when the count integer changes, not on every list reference equality check. At realistic inbox sizes (0–10 rows), 1 cached `userPublicProfileProvider` read per row is acceptable.
- **Accessibility**: "ACEPTAR" and "RECHAZAR" buttons MUST be tappable targets of at least 44×44 logical pixels.

---

## Excluded Behaviors (out of scope)

The following are explicitly NOT covered by this spec and MUST NOT be implemented in this change:

- `StreamProvider` conversion of `friendshipByPairProvider` or `userPublicProfileProvider` — separate follow-up SDD.
- Push notifications (FCM) for incoming friend requests — Fase 6 polish.
- REQ-WRX-004 dual-side counter updates (`followersCount` / `followingCount`) on accept/delete — deferred to Fase 6 or a dedicated SDD.
- Confirmation dialog on "RECHAZAR" — explicitly rejected (locked decision #4).
- Hiding the profile tile when count is zero — explicitly rejected (locked decision #3).
- Changes to `TreinoBottomBar`, `_FeedHeader`, or `firestore.rules`.
- Removal of the orphaned `pendingRequestsProvider` (Future variant) — cleanup for a separate bookkeeping SDD.

**Amendment 2026-05-22 (scope expansion)**: `public_profile_follow_button.dart` and the "SIGUIENDO" no-op are NOW in scope — see Section F (REQ-FRI-012). `FriendRequestInboxTile` requester-area tap-to-profile is NOW in scope — see Section G (REQ-FRI-013).

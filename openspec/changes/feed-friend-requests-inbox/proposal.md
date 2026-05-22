# Proposal: feed-friend-requests-inbox (Fase 3 Etapa 6)

## TL;DR

Ship an in-app **friend requests inbox** so the athlete who receives a friend request can actually see and act on it. Single PR (~250 LOC) on `feat/feed-friend-requests-inbox` against `main`, no `size:exception` needed. Closes the UX gap discovered during the smoke of `wire-real-stats` PR#3 (2026-05-21): the receiver had no in-app surface for incoming requests.

---

## Intent

### Problem

Until today, an athlete who receives a friend request has **no in-app way to see it**. The only path to accept was to navigate from search into the requester's `PublicProfileScreen` and tap the SEGUIR button (which doubles as an accept). In practice, most requests would sit unattended forever because the receiver is unaware.

The data layer is fully in place — `FriendshipRepository.pendingRequestsFor(uid)`, `accept(id, myUid)`, `delete(id, myUid)` all work and are tested (SCENARIO-127). What's missing is the **UI surface** plus a live `StreamProvider` wrapper.

### Why now

- Documented as an open follow-up in `openspec/changes/wire-real-stats/archive-report.md` §7 and engram observation `decision/follow-up-friend-requests-inbox-screen-own-sdd-after-wire-real-stats-archive`.
- Decision 2026-05-21: do this as its own SDD post-`wire-real-stats`, not bundled into that cycle.
- The Fase 3 social loop is functionally broken without it: requests fire and disappear into a void.

### Success criteria

- A tappable tile labeled "Solicitudes de amistad (N)" appears in `ProfileScreen` and remains visible even when N=0.
- Tapping the tile navigates to `/profile/friend-requests` and renders an inbox listing all pending requests received by the current user.
- Each row shows requester avatar + display name + gym, with `ACEPTAR` and `RECHAZAR` buttons.
- `ACEPTAR` calls `FriendshipRepository.accept(id, myUid)`; `RECHAZAR` calls `FriendshipRepository.delete(id, myUid)`. Both immediately drop the row from the inbox via the underlying `StreamProvider`.
- Empty state copy "No hay solicitudes pendientes" renders inside the inbox screen when count is zero.
- 0 `flutter analyze` issues, `dart format .` clean, all new tests green.

---

## Scope

### In scope — locked decisions (2026-05-22)

| # | Decision | Locked answer |
|---|---|---|
| 1 | Scope | **Option I — inbox-only**. Do NOT bundle the StreamProvider conversion of `friendshipByPairProvider` / `userPublicProfileProvider` (separate ~30-min follow-up SDD). |
| 2 | Entry point | **A — Profile tile**. Tappable row in `ProfileScreen` below the existing stats row, opens `/profile/friend-requests`. NOT a Feed header icon, NOT a bottom-bar badge. |
| 3 | Tile visibility | **Always visible**, including count "(0)" when empty. Discoverability beats minimalism. |
| 4 | RECHAZAR UX | **Immediate tap**, no confirmation dialog. Row disappears from inbox on tap. Consistent with iOS native patterns. |
| 5 | Dismiss-without-action | **Accepted**. If user opens and closes the inbox without acting, requests stay pending indefinitely. No TTL, no auto-expire. |
| 6 | Empty state copy | **"No hay solicitudes pendientes"** rendered inside the inbox screen when count is zero. The Profile tile stays visible regardless. |
| 7 | RECHAZAR vs ELIMINAR copy semantics | Repo op is the same (`friendshipRepository.delete`), but UI copy MUST differentiate by context. **Inbox button reads "RECHAZAR"**. Unfriend an accepted friendship is **"ELIMINAR"** inside a confirmation bottom sheet (see #8 below). |

### Scope amendment (2026-05-22)

After the initial scope was locked, smoke discussion surfaced two related gaps that fit cleanly within the same PR. Added as locked decisions #8 and #9:

| # | Decision | Locked answer |
|---|---|---|
| 8 | Unfriend from PublicProfileScreen | **In scope**. Today the SIGUIENDO pill in `PublicProfileFollowButton` is a no-op — there is NO way to remove a friend from the UI. Make SIGUIENDO tappable → opens `UnfriendConfirmationSheet` (modal bottom sheet, NOT AlertDialog) with copy "¿Eliminar amistad con {name}?" + destructive "ELIMINAR" button + "CANCELAR". On confirm: `friendshipRepository.delete(id, viewerUid)` + invalidate `friendshipByPairProvider`. See spec REQ-FRI-012 / SCENARIO-469..471b and design §5.4-5.5, ADR-FRI-011. |
| 9 | Tappable inbox row | **In scope**. The requester area (avatar + name + gym) of `FriendRequestInboxTile` becomes a single tap target via `InkWell` → `context.push('/feed/profile/{requesterUid}')`. Action pills stay independent tap targets. Same UX as tapping a search result. See spec REQ-FRI-013 / SCENARIO-472 and design ADR-FRI-012. |

Estimated incremental scope: ~130 LOC, brings PR total from ~250 to ~380 LOC (still under the 400-line budget; no `size:exception` needed).

### Out of scope (explicit)

- StreamProvider conversion of `friendshipByPairProvider` / `userPublicProfileProvider` — **separate follow-up SDD** (~30 min).
- Push notifications (FCM) — Fase 6 polish.
- Inbox surfaces for other social events (post likes, comments) — friend requests only here.
- REQ-WRX-004 dual-side counter updates — still deferred to Fase 6 Cloud Function or a future SDD.
- Modifying the `SEGUIR` / `ACEPTAR` / `SOLICITUD ENVIADA` states of `PublicProfileFollowButton` — only the `SIGUIENDO` branch is upgraded (per amendment #8). The other three states are untouched.
- Changes to `TreinoBottomBar`, `_FeedHeader`, or any other shared widget outside the explicit touch list below.
- New Firestore collections or any change to `firestore.rules` — existing `friendships` rules already cover read + update + delete for members. (Verify in design phase.)

---

## Touch list

### New files

| Path | Purpose |
|---|---|
| `lib/features/feed/presentation/friend_requests_inbox_screen.dart` | Inbox screen (`ConsumerWidget`). Subscribes to `pendingRequestsStreamProvider(myUid)`, renders empty state or list of `FriendRequestInboxTile`. |
| `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` | Per-row widget: avatar + displayName + gym + ACEPTAR/RECHAZAR buttons. Reads `userPublicProfileProvider(requesterUid).family` for the visible fields. |
| `lib/features/profile/presentation/widgets/profile_friend_requests_tile.dart` | Entry tile rendered inside `ProfileScreen`. Factored out into its own widget for testability and to avoid bloating `profile_screen.dart`. |
| `lib/features/feed/presentation/widgets/unfriend_confirmation_sheet.dart` | **(amendment)** Modal bottom sheet for confirming unfriend action. Stateless, takes `friendDisplayName` + `onConfirm` callback. |
| `test/features/feed/presentation/widgets/unfriend_confirmation_sheet_test.dart` | **(amendment)** Widget tests: sheet renders friend name, CANCELAR closes without firing callback, ELIMINAR fires callback then closes. |
| `test/features/feed/presentation/widgets/public_profile_follow_button_unfriend_test.dart` | **(amendment)** Widget tests: SIGUIENDO state now tappable, opens sheet, ELIMINAR triggers delete + invalidation, button reverts to SEGUIR. |
| `test/features/feed/data/friendship_repository_test.dart` | New tests for `watchPendingRequestsFor(uid)` stream contract (initial emit, pending-only filter, requester-not-self filter, accept/delete-driven re-emit). |
| `test/features/feed/application/friendship_providers_test.dart` | Tests for `pendingRequestsStreamProvider` and `pendingRequestCountProvider`. |
| `test/features/feed/presentation/friend_requests_inbox_screen_test.dart` | Widget tests: empty state, populated list, ACEPTAR removes row, RECHAZAR removes row. |
| `test/features/feed/presentation/widgets/friend_request_inbox_tile_test.dart` | Widget tests: renders requester fields, buttons wired correctly. |
| `test/features/profile/presentation/widgets/profile_friend_requests_tile_test.dart` | Widget tests: count display, tap navigates to `/profile/friend-requests`, visible when count is zero. |

### Modified files

| Path | Change |
|---|---|
| `lib/features/feed/data/friendship_repository.dart` | Add `Stream<List<Friendship>> watchPendingRequestsFor(String uid)` using Firestore `.snapshots()`. Same query shape as existing `pendingRequestsFor(uid)`, just streamed. |
| `lib/features/feed/application/friendship_providers.dart` | Add `pendingRequestsStreamProvider` (`StreamProvider.family<List<Friendship>, String>`) wrapping the new repo method. Add `pendingRequestCountProvider` (`Provider.family<int, String>`) derived via `select()` for fine-grained count subscription. |
| `lib/features/profile/profile_screen.dart` | Insert `ProfileFriendRequestsTile()` below the existing stats row. No structural change beyond the insert. |
| `lib/app/router.dart` | Register `/profile/friend-requests` route pointing to `FriendRequestsInboxScreen`. |
| `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` | **(amendment)** Upgrade the `SIGUIENDO` branch from no-op `onTap: null` to an `onTap` that opens `UnfriendConfirmationSheet`. The other three states (`SEGUIR`, `SOLICITUD ENVIADA`, `ACEPTAR`) are untouched. |
| `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` | **(amendment)** Wrap the requester zone (avatar + name + gym) in an `InkWell` whose `onTap` does `context.push('/feed/profile/${friendship.requesterId}')`. Action pills stay outside the `InkWell` as independent tap targets. |

### NOT touched (sanity guards for reviewers)

- `lib/features/feed/data/friendship_repository.dart` — `accept()`, `delete()`, `pendingRequestsFor()` left as-is; only the new `watch*()` method is added.
- `lib/features/feed/application/friendship_providers.dart` — existing `pendingRequestsProvider` stays (zero consumers but harmless; removal is bookkeeping for a different SDD).
- `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` — **only the `SIGUIENDO` branch is upgraded**; the other 3 states (`SEGUIR`, `SOLICITUD ENVIADA`, `ACEPTAR`) are untouched.
- `lib/shared/widgets/treino_bottom_bar.dart`, `_FeedHeader` — untouched.
- `firestore.rules`, `scripts/rules_test/rules.test.js` — untouched.
- `lib/features/feed/domain/friendship.dart` — Freezed model not modified, no `build_runner` regen needed.

---

## Architecture sketch

### Data flow

```
ProfileScreen
  └─ ProfileFriendRequestsTile
        ├─ ref.watch(pendingRequestCountProvider(myUid))   // derived int via select()
        └─ onTap → push('/profile/friend-requests')

FriendRequestsInboxScreen
  └─ ref.watch(pendingRequestsStreamProvider(myUid))       // StreamProvider.family
        ├─ AsyncValue.when:
        │     loading  → spinner
        │     error    → error state
        │     data([]) → "No hay solicitudes pendientes"
        │     data([F1, F2, …]) → ListView of FriendRequestInboxTile

FriendRequestInboxTile(friendship)
  ├─ ref.watch(userPublicProfileProvider(friendship.requesterId))  // family-cached
  │     → displayName, avatarUrl, gymId
  ├─ ACEPTAR → ref.read(friendshipRepositoryProvider).accept(friendship.id, myUid)
  └─ RECHAZAR → ref.read(friendshipRepositoryProvider).delete(friendship.id, myUid)
                  ↓
            Firestore snapshot fires → pendingRequestsStreamProvider re-emits without F
                  ↓
            Row disappears from UI on next frame
```

### Why a StreamProvider from day one

- **Live updates without pull-to-refresh debt**. As soon as `accept` or `delete` commits to Firestore, `snapshots()` re-emits and the inbox auto-prunes the row. No manual `ref.invalidate(...)` needed.
- The legacy `pendingRequestsProvider` (`FutureProvider`) has **zero consumers** in the codebase, so adding the streaming sibling is non-breaking. (Removing the unused Future variant is bookkeeping for a follow-up.)

### N+1 read pattern (per-row `userPublicProfileProvider.family`)

For each visible inbox row: 1 cached `userPublicProfileProvider(requesterUid)` read. At realistic inbox sizes (0–10 pending requests), this is acceptable. Riverpod's family cache deduplicates if the same requester appears across surfaces. Flagged as a risk to monitor if/when bulk-invite features land.

### No new collections, no rules changes

The existing `/friendships/{id}` rules already permit `read`, `update`, `delete` for both members of the friendship pair (`requesterId`, `recipientId`). The inbox only reads pending docs and calls existing `accept`/`delete` mutations. **Design phase must confirm** this with a quick rules-file audit, but no rules changes are expected.

---

## Approach (rationale)

### Reuse over rebuild

The data layer is already done. This SDD adds **one repo method** (`watchPendingRequestsFor`), **two providers** (stream + derived count), and **three widgets** (inbox screen, inbox row, profile tile). Plus the route. That's it.

### Why Option I (inbox-only) over Option II (inbox + live providers)

- The pair/profile-provider conversion is a real cache-staleness fix but it's isolated to `PublicProfileScreen`. It's not data-loss-critical and doesn't block the inbox.
- Bundling it would push the PR to ~350 LOC and add coupling to a screen that has nothing to do with the inbox UX gap.
- A 30-min follow-up SDD after this one verifies in production is the cleaner sequencing.

### Why Profile-tile entry (Option A) over Feed-header icon / bottom-bar badge

- **Semantically correct**: friend requests belong to "my stuff" → Profile. Feed is content, not relationships.
- **Zero structural risk**: a `ListTile`-shaped row in `ProfileScreen` requires no changes to `TreinoBottomBar` or `_FeedHeader`. Bottom-bar badges would require new infrastructure that doesn't exist.
- **Always-visible "(0)"** keeps the surface discoverable even before the user has any requests, which matters for onboarding.

### Why immediate RECHAZAR (no dialog)

- iOS native pattern: friend requests, follow requests, message requests all dismiss on a single tap.
- Mistap recovery is minor: the requester can re-send if needed; no data is destroyed (the `friendships` doc is simply deleted, identical to unfriending).
- A dialog would add UI complexity and friction for the most common action (decline) without proportional safety value.

### Why "RECHAZAR" copy differs from "ELIMINAR AMISTAD"

The same Firestore op (`friendshipRepository.delete`) means two different things to the user depending on context:

- **Inbox row** (`status == pending`, viewer is the recipient): the user is **declining an unsolicited request**. Copy: **"RECHAZAR"**.
- **Public profile of an accepted friend** (`status == accepted`): the user is **ending an existing relationship**. Copy: **"ELIMINAR AMISTAD"**.

Same destructive op, different semantic weight. This SDD only adds the inbox copy; the public-profile copy stays out of scope.

### Rejected alternatives

- **Bundle live-provider conversion** (Option II): pushes PR over budget without UX benefit for the inbox itself. Rejected — separate follow-up.
- **Bundle REQ-WRX-004 counters** (Option III): high risk, touches rules tests, ~430 LOC. Rejected — deferred to Fase 6.
- **Bottom-bar badge** entry point: requires new badge infrastructure in `TreinoBottomBar`. Rejected — out of proportion to the value.
- **Feed-header icon** entry point: 3rd icon in a 2-icon header, semantically misplaced. Rejected.
- **Confirmation dialog on RECHAZAR**: friction without safety value. Rejected.
- **Hide tile when count is zero**: hurts discoverability for first-time users. Rejected.

---

## Risks

1. **N+1 reads at inbox scale**: 1 cached profile read per row. Acceptable for MVP at 0–10 requests. Flag to revisit if bulk-invite-friends ever ships.
2. **`userPublicProfileProvider` cache staleness**: the inbox stream is fresh, but per-row displayName/avatar/gym are Future-cached. If a requester updates their profile mid-inbox-view, the row may show stale data until the cache invalidates. Acceptable edge case for this feature — the follow-up live-providers SDD will eliminate it.
3. **Spanish copy locked but unreviewed by design**: "RECHAZAR", "ELIMINAR AMISTAD", "No hay solicitudes pendientes", "Solicitudes de amistad". Should be reconfirmed in design if any UX writer review exists.
4. **`pendingRequestsProvider` (Future variant) remains orphaned**: zero consumers after this ships. Not a functional risk, just dead code; removal belongs to a separate cleanup pass.
5. **Rules audit assumption**: design phase must explicitly confirm `/friendships/{id}` rules already cover the inbox read pattern. Expected pass with no rules changes.

---

## Estimated size

| Bucket | LOC |
|---|---|
| Prod (new + modified) | ~180 |
| Test | ~70 |
| **Total** | **~250** |

Single PR, comfortably under the 400-LOC budget. Low risk.

---

## Delivery strategy

| Aspect | Choice |
|---|---|
| Strategy | **`single-pr`** against `main` |
| Branch | `feat/feed-friend-requests-inbox` |
| `size:exception` | **Not needed** (~250 LOC well under budget) |
| Stacked / chained PRs | No |
| TDD | Strict TDD active for this project — RED → GREEN per work unit, tests first |

### Quality gate (must pass before claiming done)

- `flutter analyze` — 0 issues
- `dart format .` — clean
- `flutter test` — all green (new + existing)

### Commits

Conventional commits. NO Co-Authored-By. NO AI attribution. Suggested first commit: `feat(feed): add friend requests inbox screen`.

---

## Reviewer focus

When the PR opens, look here first in this order:

1. **`friendship_repository.dart`** — confirm `watchPendingRequestsFor` uses `.snapshots()` and replicates the existing pending+requester-not-self filter logic from `pendingRequestsFor` exactly.
2. **`friendship_providers.dart`** — confirm `pendingRequestCountProvider` uses `.select()` so the Profile tile rebuilds only on count changes, not on every list change.
3. **`profile_friend_requests_tile.dart`** — confirm it's visible at count zero and uses `AppPalette.of(context)` + `TreinoIcon.X` (no HEX, no `PhosphorIcons.X` direct).
4. **`friend_request_inbox_tile.dart`** — confirm `RECHAZAR` is immediate (no dialog) and copy reads **"RECHAZAR"** (not "ELIMINAR").
5. **`router.dart`** — confirm `/profile/friend-requests` is registered and reachable.
6. **Tests** — confirm SCENARIO coverage for stream emit on accept/delete, empty state render, RECHAZAR removes row, tile visible at count zero.
7. **Sanity guard**: confirm `firestore.rules`, `TreinoBottomBar`, `_FeedHeader`, `public_profile_follow_button.dart` are **NOT** in the diff.

---

## Ready for Spec + Design

Spec and design can run in **parallel** after this proposal lands.

- **Spec** captures: per-screen behavior, ACEPTAR/RECHAZAR acceptance criteria, empty-state contract, tile-visibility contract, navigation contract.
- **Design** captures: provider topology (`pendingRequestsStreamProvider`, `pendingRequestCountProvider`, derived selectors), repo method signature + Firestore query shape, widget composition, **explicit rules audit confirming no `firestore.rules` changes needed**, copy table (RECHAZAR vs ELIMINAR vs ACEPTAR vs empty-state), navigation route registration.

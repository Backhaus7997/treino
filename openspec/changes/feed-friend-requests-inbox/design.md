# Design: feed-friend-requests-inbox (Fase 3 Etapa 6)

## 1. TL;DR

We are adding a live, screen-scoped **friend-requests inbox** plus a Profile entry tile, layered on top of the existing `FriendshipRepository` without touching its current methods. The architecture turns the existing one-shot `pendingRequestsFor(uid)` into a streaming sibling `watchPendingRequestsFor(uid)` exposed via a `StreamProvider.family<List<Friendship>, String>` and a derived `Provider.family<int, String>` count, both `autoDispose`. The UI is three small `ConsumerWidget`s: a Profile tile that watches the count, an inbox screen that routes the stream's `AsyncValue.when`, and a per-row tile that resolves the requester's display fields through the existing `userPublicProfileProvider.family`. RECHAZAR / ACEPTAR are fire-and-forget mutations that rely on `.snapshots()` re-emission to remove the row — no manual invalidation, no optimistic UI. **Rules audit conclusion: no `firestore.rules` changes needed** — the existing `/friendships/{id}` block already permits the list query, the accept (`update`), and the reject (`delete`).

---

## 2. Architecture overview

### Provider topology

```
firestoreProvider                                  (existing, profile/application)
  └─ friendshipRepositoryProvider                  (existing, feed/application)
       └─ pendingRequestsStreamProvider(uid)       NEW — StreamProvider.family.autoDispose
            └─ pendingRequestCountProvider(uid)    NEW — Provider.family.autoDispose<int>

userPublicProfileRepositoryProvider                (existing)
  └─ userPublicProfileProvider(uid).family         (existing) — resolved per-row
```

No new repositories. No new domain types. The `FriendshipRepository` constructor stays untouched (the optional `publicProfileRepository` collaborator already wired for cross-feature counters in `accept`/`delete` continues to work). The two new providers are additive in `friendship_providers.dart`; the legacy `pendingRequestsProvider` (`FutureProvider`) stays as-is per the proposal touch list — orphaned but harmless.

### Widget tree sketch

```
ProfileScreen (existing — modify: insert tile)
  ├─ _OwnProfileStatsRow                            (existing, unchanged)
  ├─ ProfileFriendRequestsTile                      NEW
  │     └─ watches pendingRequestCountProvider(myUid)
  │     └─ onTap → context.push('/profile/friend-requests')
  └─ Expanded(... existing PERFIL placeholder + signOut ...)

FriendRequestsInboxScreen (NEW — TOP-LEVEL route inside ShellRoute)
  └─ Column
        ├─ _InboxHeader  (caretLeft back + "SOLICITUDES" title — mirrors SearchUsersScreen)
        └─ Expanded
              └─ AsyncValue.when on pendingRequestsStreamProvider(myUid)
                    ├─ loading → CircularProgressIndicator(palette.accent)
                    ├─ error   → centered error copy (palette.textMuted)
                    ├─ data([]) → centered "No hay solicitudes pendientes"
                    └─ data(list) → ListView.separated of FriendRequestInboxTile

FriendRequestInboxTile (NEW)
  ├─ watches userPublicProfileProvider(friendship.requesterId)
  ├─ PostAvatar + name (UPPERCASE Barlow Condensed) + gym (Barlow muted)
  └─ Row of two pills: RECHAZAR (outlined-muted) + ACEPTAR (mint-filled)
        ↓ tap
        ref.read(friendshipRepositoryProvider).accept(id, myUid)  OR  .delete(id, myUid)
        ↓ Firestore commits
        snapshots() re-emits new list (no row F)
        ↓ Riverpod rebuild
        Row disappears from UI on next frame — no manual invalidate, no optimistic UI
```

### Data flow on ACEPTAR / RECHAZAR

The mutation handlers are intentionally minimal. Because `watchPendingRequestsFor(uid)` returns `.snapshots()`, every Firestore commit that affects the query (status flip to `accepted`, or doc deletion) triggers a fresh emission. Riverpod's `StreamProvider` propagates it, the inbox `ListView` rebuilds, and the removed row is gone. There is **no optimistic UI** and **no `ref.invalidate`** — this avoids double-fire races where the optimistic removal and the real snapshot disagree.

The same Firestore commits also trigger the existing best-effort `userPublicProfiles.followingCount` self-refresh inside `FriendshipRepository.accept` / `.delete`. That side-effect is out of scope for this SDD and is preserved as-is (try/catch, no rethrow — ADR-WRS-12 from `wire-real-stats`).

---

## 3. Repository signature

Add **one method** to `FriendshipRepository`. Same query shape as the existing one-shot `pendingRequestsFor(uid)`, just streamed and with the requester-not-self filter applied inside the `.map`:

```dart
/// Live stream of pending friendships where [uid] is the recipient
/// (not the requester). This is the inbox feed for the friend-requests
/// inbox screen. Emits an empty list when none exist.
///
/// Same shape as [pendingRequestsFor], but uses `.snapshots()` so the
/// inbox auto-prunes rows when `accept` or `delete` commits without
/// requiring manual provider invalidation.
Stream<List<Friendship>> watchPendingRequestsFor(String uid) {
  return _friendships
      .where('members', arrayContains: uid)
      .where('status', isEqualTo: FriendshipStatus.pending.toJson())
      .snapshots()
      .map((snap) => snap.docs
          .map(_fromDoc)
          .whereType<Friendship>()
          .where((f) => f.requesterId != uid)
          .toList());
}
```

### Notes

- `_friendships`, `_fromDoc`, and `FriendshipStatus.pending.toJson()` are already in scope — no new imports.
- The requester-not-self filter must run in Dart, not Firestore, because there is no `where requesterId !=` operator in Firestore queries. (The existing `pendingRequestsFor` already does it this way; we replicate exactly.)
- Keep **both** `pendingRequestsFor` (one-shot Future) and `watchPendingRequestsFor` (Stream). The Future variant has zero consumers after this ships but its removal is bookkeeping for a separate cleanup pass per the proposal's locked decision (Out-of-scope section).
- Errors on the underlying Firestore stream propagate to `StreamProvider` as `AsyncError`. The inbox UI handles it in its `AsyncValue.when` `error` branch — no try/catch in the repo layer.

---

## 4. Provider definitions

Add to `lib/features/feed/application/friendship_providers.dart`:

```dart
/// Live stream of pending friendship requests received by [uid]
/// (status=pending, requesterId != uid). Backs the inbox screen.
///
/// `autoDispose` because the inbox is screen-scoped — no need to hold a
/// Firestore listener open when the user is on another tab.
final pendingRequestsStreamProvider =
    StreamProvider.family.autoDispose<List<Friendship>, String>((ref, uid) {
  return ref.watch(friendshipRepositoryProvider).watchPendingRequestsFor(uid);
});

/// Count of pending requests received by [uid]. Derived synchronously from
/// [pendingRequestsStreamProvider] — returns 0 during loading/error so the
/// Profile tile renders "(0)" without flicker.
///
/// `autoDispose` matches the upstream stream provider's lifecycle.
final pendingRequestCountProvider =
    Provider.family.autoDispose<int, String>((ref, uid) {
  return ref.watch(pendingRequestsStreamProvider(uid)).maybeWhen(
        data: (list) => list.length,
        orElse: () => 0,
      );
});
```

### Justification per choice

| Choice | Rationale |
|---|---|
| `StreamProvider` (not `FutureProvider`) | Inbox must auto-prune on accept/delete commit. `.snapshots()` is the only way to get that without manual `ref.invalidate` boilerplate in every button handler. ADR-FRI-001. |
| `family<String>` keyed on viewer uid | Tests and multi-account scenarios need to pass arbitrary uids. Matches the convention used by `acceptedFriendsProvider` and `pendingRequestsProvider`. |
| `autoDispose` on both providers | Inbox is opened transiently. Without `autoDispose` the Firestore listener leaks for the rest of the session even when the user is on `/workout` or `/feed`. The Profile tile only renders the count when ProfileScreen is mounted, and ShellRoute keeps `/profile` alive via `_ShellScaffold`, so subscription churn is acceptable on tab switches. ADR-FRI-006. |
| Count provider is `Provider` not `FutureProvider` | The derivation is synchronous on the upstream `AsyncValue`. Wrapping it in `FutureProvider` would force consumers into a second `AsyncValue.when` for no real loading state. |
| `maybeWhen` with `0` fallback during loading/error | Profile tile must render `"Solicitudes de amistad (0)"` immediately on first paint, not `"..."` or a spinner. Keeps the tile visually stable regardless of upstream state. ADR-FRI-007. |
| **NOT** using `.select()` on the count | Riverpod `StreamProvider` doesn't expose `.select()` ergonomically for AsyncValue → derived primitives. The dedicated `pendingRequestCountProvider` is the canonical pattern and gives consumers the same fine-grained rebuild semantics — the tile only rebuilds when `count` actually changes, not on every list emission. (Note: proposal mentioned `select()` — this design keeps the proposal's *intent* of fine-grained subscription while using the idiomatic Riverpod pattern.) |

---

## 5. Widget specs

### 5.1 `ProfileFriendRequestsTile`

**Path**: `lib/features/profile/presentation/widgets/profile_friend_requests_tile.dart`
**Type**: `ConsumerWidget`
**Constructor**: `const ProfileFriendRequestsTile({super.key})`

**Subscriptions**:
- `ref.watch(authStateChangesProvider).valueOrNull?.uid` → `myUid` (defensive: if null, render the tile in disabled/zero state)
- `ref.watch(pendingRequestCountProvider(myUid))` → `int count`

**Render**:
- `GestureDetector` (behavior: opaque) wrapping a `Container` styled like `UserSearchResultTile` (`palette.bgCard`, `BorderRadius.circular(14)`, `palette.textMuted.withValues(alpha: 0.12)` border, `EdgeInsets.symmetric(horizontal: 14, vertical: 12)`).
- Inside: `Row` of:
  1. `Icon(TreinoIcon.users, size: 20, color: palette.accent)` — leading icon
  2. `SizedBox(width: 14)`
  3. `Expanded(child: Text("Solicitudes de amistad (${count})", style: GoogleFonts.barlowCondensed(fontWeight: w700, fontSize: 16, color: palette.textPrimary)))`
  4. `Icon(TreinoIcon.chevronRight, size: 16, color: palette.textMuted)`
- Outer padding: `EdgeInsets.symmetric(horizontal: 20, vertical: 8)` to align with the existing stats row at `horizontal: 20`.

**Tap**: `context.push('/profile/friend-requests')` — uses `push` (not `go`) so the inbox slides over the profile tab and `pop` returns to it.

**Visibility**: Always rendered, even when `count == 0` and even when `myUid` is null (count = 0). Per locked decision #3.

### 5.2 `FriendRequestsInboxScreen`

**Path**: `lib/features/feed/presentation/friend_requests_inbox_screen.dart`
**Type**: `ConsumerWidget`
**Constructor**: `const FriendRequestsInboxScreen({super.key})`

**Router context**: registered as a **TOP-LEVEL route inside the `ShellRoute`** (i.e. as a `routes:` child of `/profile`, not a top-level route outside the shell). This means the shell's `_ShellScaffold` provides the `AppBackground`, `SafeArea`, and `TreinoBottomBar` — the screen returns a plain widget (NOT its own `Scaffold`). This matches the convention used by every other in-shell screen (`SearchUsersScreen`, `PublicProfileScreen`, `CreatePostScreen`).

**Subscriptions**:
- `ref.watch(authStateChangesProvider).valueOrNull?.uid` → `myUid`
- `ref.watch(pendingRequestsStreamProvider(myUid))` → `AsyncValue<List<Friendship>>`

**Render**: `Column(crossAxisAlignment: stretch, children: [header, Expanded(body)])`

- Header: private `_InboxHeader` widget — `Padding(horizontal: 20, vertical: 18)` with `Row` of:
  - `GestureDetector(onTap: context.pop, child: Icon(TreinoIcon.back, size: 20, color: palette.textPrimary))`
  - `SizedBox(width: 14)`
  - `Text("SOLICITUDES", style: GoogleFonts.barlowCondensed(fontWeight: w700, fontSize: 20, letterSpacing: 1.2, color: palette.textPrimary))`

- Body: `AsyncValue.when`:
  - `loading` → `Center(child: CircularProgressIndicator(color: palette.accent))`
  - `error(_, __)` → `Center(child: Padding(horizontal: 20, child: Text("No pudimos cargar las solicitudes. Intentá de nuevo.", style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted), textAlign: center)))`
  - `data([])` → `Center(child: Padding(horizontal: 20, child: Text("No hay solicitudes pendientes", style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted), textAlign: center)))`
  - `data(list)` → `ListView.separated(physics: ClampingScrollPhysics, padding: EdgeInsets.symmetric(horizontal: 20), itemCount, separator: SizedBox(height: 8), itemBuilder → FriendRequestInboxTile(friendship: list[i], viewerUid: myUid))`

**Defensive `myUid` handling**: if `myUid` is null (anonymous race during sign-out), short-circuit to the empty-state copy. The router guard would normally redirect, but defensive rendering avoids a frame of broken state.

### 5.3 `FriendRequestInboxTile`

**Path**: `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart`
**Type**: `ConsumerWidget`
**Constructor**: `const FriendRequestInboxTile({super.key, required this.friendship, required this.viewerUid})`

**Fields**:
- `final Friendship friendship`
- `final String viewerUid` — passed in by the parent to keep the tile pure (no `auth` lookup)

**Subscriptions**:
- `ref.watch(userPublicProfileProvider(friendship.requesterId))` → `AsyncValue<UserPublicProfile?>`

**Render**: `Container` styled like `UserSearchResultTile` (same `palette.bgCard`, radius 14, border, padding `horizontal: 14, vertical: 12`).

Inside, `Row`:
1. `PostAvatar(authorDisplayName: displayName, authorAvatarUrl: avatarUrl, size: 40)`
2. `SizedBox(width: 14)`
3. `Expanded(child: Column(crossAxisAlignment: start, mainAxisSize: min, children: [name text, if (gymName.isNotEmpty) gym text]))`
4. `SizedBox(width: 8)`
5. Action buttons `Row(mainAxisSize: min, children: [RECHAZAR pill, SizedBox(width: 8), ACEPTAR pill])`

**Field resolution from `userPublicProfileProvider`**:
- `displayName` = `profile?.displayName ?? "Usuario anónimo"` (note: "Usuario anónimo" not just "Anónimo" — see Copy table §8)
- `avatarUrl` = `profile?.avatarUrl`
- `gymName` = `gymNameFromId(profile?.gymId)` from `lib/features/feed/domain/gym_name.dart`; empty string if null
- During `loading` or `error` on the public profile: render with the same fallbacks so the row never shows a spinner — the inbox is about the action, not the requester preview.

**Buttons**: Two pills, sized identically (`Expanded` is NOT used — they sit at the right edge as fixed-content pills, mirroring the visual density of the search results tile). Use the same `_FollowPill`-style aesthetic but local to this file (do not import from `public_profile_follow_button.dart` — that file's `_FollowPill` is private). Inline a small `_InboxActionPill` widget with two variants:

| Variant | bg | border | text color | usage |
|---|---|---|---|---|
| `mintFilled` | `palette.accent` | `palette.accent` | `palette.bg` | ACEPTAR |
| `outlinedMuted` | transparent | `palette.border` | `palette.textMuted` | RECHAZAR |

Pill geometry: `padding(horizontal: 14, vertical: 8)`, `BorderRadius.circular(18)`, label `GoogleFonts.barlowCondensed(fontWeight: w700, fontSize: 12, letterSpacing: 1.0)`.

**Tap handlers** (both async, fire-and-forget — UI auto-updates from `.snapshots()`):

```dart
final repo = ref.read(friendshipRepositoryProvider);

// ACEPTAR
onTap: () async {
  try {
    await repo.accept(friendship.id, viewerUid);
  } catch (_) {
    // Swallow — stream will not emit a removal, so row stays.
    // No SnackBar in MVP (out of proposal scope).
  }
}

// RECHAZAR — immediate, no confirmation dialog (locked decision #4)
onTap: () async {
  try {
    await repo.delete(friendship.id, viewerUid);
  } catch (_) {
    // Swallow — stream will not emit a removal, so row stays.
  }
}
```

**No optimistic UI**: rely on snapshot re-emission. If the mutation fails, the row stays visible — which is the correct UX, not a regression.

---

## 6. Route registration

Add to `lib/app/router.dart`, **inside the `ShellRoute` block, as a sub-route of `/profile`** (the existing `/profile` `GoRoute` currently has no `routes:` child — we add the list):

```dart
GoRoute(
  path: '/profile',
  pageBuilder: (_, __) => _noAnim(const ProfileScreen()),
  routes: [
    GoRoute(
      path: 'friend-requests',
      pageBuilder: (_, __) => _noAnim(const FriendRequestsInboxScreen()),
    ),
  ],
),
```

### Placement rationale

- The other in-shell sub-routes (`/feed/profile/:uid`, `/feed/search`, `/workout/routine/:routineId`, etc.) all sit inside the `ShellRoute` and inherit the bottom bar — that matches the proposal's locked decision that this is a "Profile tile" UX, not an immersive screen.
- The path is `friend-requests` (no leading slash) so `go_router` composes it as `/profile/friend-requests` per the parent `/profile` route. This matches the existing `routine/:routineId` → `/workout/routine/:routineId` pattern.
- Using `_noAnim(...)` matches every other route in the shell — keeps transitions consistent (zero animation, immediate).
- `context.push('/profile/friend-requests')` from the tile navigates with the standard iOS push transition (provided by `go_router` defaults) since `pageBuilder` only suppresses the *shell entry* animation, not nested push transitions.

**Import to add** at the top of `router.dart`:
```dart
import '../features/feed/presentation/friend_requests_inbox_screen.dart';
```

---

## 7. Rules Audit (MANDATORY — lesson from wire-real-stats / #66 hotfix)

Audited `firestore.rules` lines 171–200, the `match /friendships/{friendshipId}` block:

| Op | Inbox usage | Rule predicate | Pass? |
|---|---|---|---|
| `read` (list query) | `where('members', arrayContains: myUid).where('status', isEqualTo: 'pending').snapshots()` | `request.auth != null && (resource == null \|\| request.auth.uid in resource.data.members)` | **YES** — every doc the query returns has `myUid` in `members`, so the per-doc predicate holds for every result. Firestore can prove rule satisfaction at query-validation time because the `arrayContains: myUid` clause guarantees it. This is the exact pattern that passed for `acceptedFriendsOf` and `pendingRequestsFor`. |
| `update` (ACEPTAR — flip status to `accepted`) | `repo.accept(id, myUid)` does `update({'status': 'accepted'})` | `request.auth.uid in resource.data.members && request.auth.uid != resource.data.requesterId && request.resource.data.status == 'accepted' && requesterId preserved && members preserved` | **YES** — inbox only shows rows where `requesterId != myUid` (we filter in Dart), so the non-requester predicate is guaranteed. The update payload only sets `status`; `requesterId` and `members` are preserved by Firestore's partial-update semantics. |
| `delete` (RECHAZAR) | `repo.delete(id, myUid)` does `.doc(id).delete()` | `request.auth != null && request.auth.uid in resource.data.members` | **YES** — `myUid` is in members (verified by the query) so the delete is authorized. This is the same path used by ELIMINAR AMISTAD on `PublicProfileScreen` — already in production. |
| Side-effect `update` on `userPublicProfiles/{myUid}` (followingCount delta inside `accept`/`delete`) | self-write to own doc | Lines 140–142: `request.auth.uid == uid && request.resource.data.uid == resource.data.uid` | **YES** — owner-only self-write, already proven by `wire-real-stats` PR#3. Best-effort try/catch already in place. |

### Conclusion

**No `firestore.rules` changes needed.** The existing block is sufficient for the inbox flow end-to-end. The proposal's "no rules changes" assumption (§"No new collections, no rules changes") is **CONFIRMED** by this audit.

This avoids the trap of the `wire-real-stats` #66 hotfix, where a missing rule for `routines` create surfaced only at runtime — here we explicitly verified every op against every rule.

---

## 8. Copy table

All strings are Rioplatense Spanish, UPPERCASE only where the design system uses Barlow Condensed labels (button pills, screen titles, section headers). Body copy stays sentence case.

| Context | String | Notes |
|---|---|---|
| `ProfileFriendRequestsTile` label | `"Solicitudes de amistad (${count})"` | Always shown including `(0)`. Sentence case in Barlow Condensed bold (matches the search results tile naming convention). |
| Inbox screen title | `"SOLICITUDES"` | Short form, mirrors `"BUSCAR USUARIOS"` header style in `SearchUsersScreen`. Full "SOLICITUDES DE AMISTAD" would wrap on iPhone SE; the back chevron + screen context disambiguate. |
| Inbox empty state | `"No hay solicitudes pendientes"` | Exact copy from proposal locked decision #6. |
| Inbox error state | `"No pudimos cargar las solicitudes. Intentá de nuevo."` | Mirrors `SearchUsersScreen` error copy ("No pudimos buscar usuarios. Intentá de nuevo.") for consistency. Voseo: "Intentá". |
| ACEPTAR button | `"ACEPTAR"` | UPPERCASE Barlow Condensed, identical to the SEGUIR/ACEPTAR pill in `PublicProfileFollowButton`. |
| RECHAZAR button | `"RECHAZAR"` | UPPERCASE Barlow Condensed. **NOT** "ELIMINAR" — locked decision #7. |
| Row name fallback when `userPublicProfile?.displayName == null` | `"Usuario anónimo"` | Sentence case here, NOT UPPERCASE — names render in display style. Differs from `UserSearchResultTile`'s `"Anónimo"` because in the inbox context "Usuario anónimo" reads more naturally as a placeholder identity in a list of social actions, vs the search-results "Anónimo" which sits beside a clickable chevron. Acceptable minor inconsistency; flagged for design review if a UX writer audits later. |
| Row gym fallback when `userPublicProfile?.gymId == null` | `""` (omitted) | No placeholder. The row collapses to single-line name when gym is missing — same pattern as `UserSearchResultTile` (`if (gymName.isNotEmpty) ...`). |

### Deviations from proposal copy

- Proposal §"Estimated size" and §"Reviewer focus" reference `"Solicitudes de amistad (N)"` — we render it with literal interpolation `(${count})`. Semantically identical.
- Proposal didn't pin the inbox screen title; we picked `"SOLICITUDES"` for layout safety. If a designer reviews and prefers `"SOLICITUDES DE AMISTAD"`, the change is a one-line copy edit with no architectural impact.
- Proposal didn't pin the row-name fallback; we picked `"Usuario anónimo"` to disambiguate from the search context.

---

## 9. ADR table

| ID | Decision | Rationale | Rejected alternatives |
|---|---|---|---|
| ADR-FRI-001 | Use `StreamProvider.family` (not `FutureProvider.family`) for the inbox source from day one | Inbox must auto-prune rows the instant ACEPTAR/RECHAZAR commits, without manual `ref.invalidate` plumbing in every button handler. `.snapshots()` + Riverpod's `StreamProvider` give us this with zero boilerplate. Aligns with the project's drift toward streaming providers (insights, sessions). | (a) `FutureProvider` + manual invalidation: requires hand-wiring `ref.invalidate(pendingRequestsStreamProvider(myUid))` in both button handlers, easy to forget, error-prone. (b) `FutureProvider` + pull-to-refresh: shifts the UX burden to the user for a one-tap action; rejected as anti-pattern. |
| ADR-FRI-002 | Resolve per-row requester profile via existing `userPublicProfileProvider.family` (N+1 reads) | Inbox sizes are realistically 0–10 rows. Riverpod's family cache deduplicates if the same requester appears across surfaces (search → public profile → inbox), so the marginal cost is one cached doc read per visible row. Reuse over rebuild — no new repository, no new joined query, no new view-model DTO. | (a) Denormalize requester fields onto the `friendships` doc at request time: fast read but introduces stale-data risk and a write path change for SDD scope creep. Rejected. (b) Server-side join via Cloud Function: out of proposal scope, defers shipping. Rejected. |
| ADR-FRI-003 | Add `watchPendingRequestsFor(uid)` **alongside** existing one-shot `pendingRequestsFor(uid)`; do NOT remove the orphan | Removing the orphan is bookkeeping that has nothing to do with the inbox UX gap. Bundling it would pollute the diff and risk unexpected test fallout. The proposal explicitly schedules removal as a separate cleanup pass. | (a) Remove `pendingRequestsFor` in this PR: out of locked scope, adds diff noise. Rejected. (b) Refactor the one-shot to delegate to the stream's `.first`: introduces an unnecessary collaboration path on a method with zero consumers. Rejected. |
| ADR-FRI-004 | Immediate fire on RECHAZAR (no confirmation dialog) | iOS native pattern across friend/follow/message request surfaces. Mistap recovery is minor — the requester can re-send. A dialog adds friction without proportional safety value. Locked decision #4. | (a) Confirmation dialog: friction for the most common action (decline). Rejected. (b) Undo SnackBar (5s window): out of MVP scope, adds state machine complexity. Deferred to a possible follow-up. |
| ADR-FRI-005 | `ProfileFriendRequestsTile` is **always visible**, including `(0)` | Discoverability beats minimalism — first-time users need to find the surface even before they receive any requests. Locked decision #3. The `(0)` count is unobtrusive and consistent with `SESIONES: 0` patterns elsewhere. | Hide tile when count is zero: hurts discoverability, creates a "where is it?" UX bug for new users who haven't received a request yet. Rejected. |
| ADR-FRI-006 | Both new providers use `autoDispose` | The inbox is screen-scoped — opening it once for 5 seconds should not leak a Firestore listener for the rest of the session. ShellRoute keeps `/profile` mounted, so the tile's count subscription re-establishes within one frame on tab switch. Listener churn is negligible. | Persistent (non-`autoDispose`) subscriptions: cleaner UI updates across tab switches but leaks a snapshot listener per signed-in user for the entire session. Not worth it for an inbox-grade flow. Rejected. |
| ADR-FRI-007 | `pendingRequestCountProvider` returns `0` during loading/error (via `maybeWhen` + `orElse: () => 0`) | The Profile tile must render `"Solicitudes de amistad (0)"` on first paint — flickering between `"..."`, a spinner, and `(0)` on every cold start would be visually jarring for a piece of UI the user encounters every time they open Profile. `0` is also the correct semantic when the source is unknown — we cannot truthfully claim there are unseen requests. | Forward the `AsyncValue` to the tile and let it render `"..."` during loading: causes visible flicker, requires the tile to handle loading/error states. Rejected. |
| ADR-FRI-008 | Inbox screen is registered as a **sub-route of `/profile` inside the ShellRoute** (not a top-level immersive route) | The inbox is a relationship-management surface, semantically owned by `/profile`. Keeping the bottom bar visible matches the proposal's "Profile tile → /profile/friend-requests" intent and lets the user tab away mid-decision without losing context. | (a) Top-level immersive route (like `/workout/session/...`): hides the bottom bar, treats the inbox as a deep action — overkill for a list-with-buttons. Rejected. (b) Modal bottom sheet: hard to test, doesn't deep-link, doesn't paginate cleanly. Rejected. |
| ADR-FRI-009 | No optimistic UI on ACEPTAR/RECHAZAR | The snapshot re-emission round-trip is fast enough (sub-second on warm connections) and avoids double-fire races between the optimistic local removal and the real stream emission. If the mutation fails (offline, rules failure), the row correctly stays visible — which is honest UX, not a regression. | Optimistic removal with rollback on error: state machine adds complexity for negligible perceived latency win. Rejected. |
| ADR-FRI-010 | Inline a local `_InboxActionPill` widget rather than reusing `_FollowPill` from `public_profile_follow_button.dart` | `_FollowPill` is a private class — exporting it would force a public API extraction with no other consumer. The inbox pill needs a smaller geometry (12px font, 18px radius vs 13/20) anyway to fit two pills in a single row. Cheaper to inline 30 LOC than to refactor a shared pill abstraction with one and a half consumers. | (a) Extract `TreinoPill` to `core/widgets/`: premature abstraction, would need to absorb 4 style variants without proof of a third consumer. Rejected — revisit if a third pill surface appears. (b) Use Material `OutlinedButton` + `FilledButton`: doesn't match the project's hand-rolled pill aesthetic. Rejected. |

---

## 10. Risks → tasks must address

Risks for the apply phase to handle explicitly. None are CRITICAL — the rules audit closed the only blocker risk surfaced by the proposal.

1. **Stream test setup with `fake_cloud_firestore`**: confirm the package's `snapshots()` listening works with `.where().where().snapshots()` chained queries. It does (used heavily in `wire-real-stats` tests), but the apply phase MUST write at least one end-to-end test that verifies a row disappears after `accept()` commits — that's the contract this whole architecture exists to deliver. If the fake doesn't replay deletes correctly, fall back to a per-emit assertion sequence (`expectLater(stream, emitsInOrder([...]))`).

2. **`userPublicProfileProvider` cache staleness mid-view**: if requester X updates their displayName/avatar while the viewer has the inbox open, the row shows stale data until the cached future expires. Acceptable for MVP — flagged for the follow-up live-providers SDD already scheduled. **Apply phase action**: no special handling; ensure widget tests use freshly seeded profile data per scenario so this stale-cache window doesn't pollute test isolation.

3. **Cross-counter side-effect on RECHAZAR**: `FriendshipRepository.delete` increments-decrements `userPublicProfiles.followingCount` for the caller (`myUid`). For the inbox, `myUid` is the **recipient** declining a request — they were never "following" the requester (acceptance is the trigger for that), so the decrement clamps to 0 and is a no-op for fresh accounts but **decrements correctly** if `myUid` had already followed the requester elsewhere. **Apply phase action**: add a test that verifies RECHAZAR on a never-accepted friendship does NOT push `followingCount` below 0 (the existing `.clamp(0, double.maxFinite)` should hold, but explicit coverage protects against regressions).

4. **`autoDispose` + rapid tap interaction**: when the user taps ACEPTAR, the row's `FriendRequestInboxTile` is rebuilt-out as the new list emits without it. If the user taps a second time during the in-flight Firestore commit, the second tap's `repo.accept` call will hit a non-existent (already-flipped) doc. Current `FriendshipRepository.accept` reads the doc first and throws `StateError` on missing — the swallowed-error pattern in the tile handles this gracefully. **Apply phase action**: add a widget test that simulates a double-tap on ACEPTAR and asserts no exception bubbles up and the row is gone.

5. **Profile tile alignment with existing stats row**: the stats row uses `EdgeInsets.symmetric(horizontal: 20, vertical: 20)`. The new tile uses `horizontal: 20, vertical: 8` to sit visually closer. **Apply phase action**: verify by golden test or manual mockup parity (per the workflow we just shipped in #21) that the spacing matches the design system's 8/12/14/18/20 scale and doesn't bunch up with the stats row's existing 20px bottom padding.

6. **Anonymous `myUid` defensive render**: during sign-out, there's a one-frame window where `authStateChangesProvider` emits null before the router redirects. The tile must not throw on `pendingRequestCountProvider(null)`. **Apply phase action**: handle `myUid == null` by passing an empty string `""` to the family (which will produce an empty stream — no doc has `""` in `members`) OR by guarding the `ref.watch` with a null check and rendering `(0)`. The second is cleaner.

---

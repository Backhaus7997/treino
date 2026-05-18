# Exploration: public-profile

**Change:** Fase 3 · Etapa 4 — `/profile/:uid` public profile screen for OTHER users
**Branch:** `feat/public-profile`
**Date:** 2026-05-15

---

## Current State

### What exists today

- `/profile` — `ProfileScreen` (own profile stub, Fase 1 Etapa 6). Currently renders only a "PERFIL" title + sign-out button. Not a real profile; no avatar, no stats, no layout.
- `Post` model — fully denormalized author fields: `authorUid`, `authorDisplayName` (`@Default('Anónimo')`), `authorAvatarUrl`, `authorGymId`.
- `Friendship` model — `uidA`, `uidB`, `status (pending|accepted)`, `requesterId`, `members[]`.
- `FriendshipRepository` — `request()`, `accept()`, `delete()`, `acceptedFriendsOf()`, `pendingRequestsFor()` (inbox only — no outbox query today).
- `friendship_providers.dart` — `acceptedFriendsProvider` (FutureProvider.family) and `pendingRequestsProvider` (inbox FutureProvider.family).
- `PostAvatar` widget — already handles `avatarUrl` (CachedNetworkImage) + initials fallback. Reusable as-is.
- `FeedSegmentPills` — pill-based segment switcher pattern. Direct reuse candidate for profile tabs.
- `RoutineDetailScreen` — hero strip + back button + CustomScrollView with SliverToBoxAdapter. Closest structural cousin for the profile hero layout.
- Firestore rules — `users/{uid}` is **owner-only read**. No public profile collection exists.
- Gyms — **hardcoded list** in `profile_setup_providers.dart`. No `gyms/` Firestore collection exists yet. The code explicitly says: "Cuando llegue Firestore, este modelo se hidrata desde la colección `gyms/`."
- `TreinoIcon.verified` — exists (`PhosphorIconsFill.sealCheck`).
- Test conventions — feed tests live under `test/features/feed/`. Profile tests don't exist yet (ProfileScreen is a stub).

---

## Mockup Analysis — `feed-publico.png`

Full field inventory (left to right, top to bottom):

| Field | Value in mockup | Source available |
|---|---|---|
| Hero background photo | Blurred gym background | Not in data model — placeholder gradient needed |
| Avatar | Circular photo (real image) | `Post.authorAvatarUrl` or `UserProfile.avatarUrl` |
| Display name | "MATEO QUINTERO" (uppercase, large) | `Post.authorDisplayName` |
| Handle + gym | "@mateoq · Megatlon Recoleta" | Handle: NOT in any model. GymId raw only (no resolved name). |
| SEGUIR button | Mint, full-width left half | New — calls `FriendshipRepository.request()` |
| MENSAJE button | Outlined, disabled, right half | Stub only |
| WORKOUTS stat | "89" | Placeholder — no data source in scope |
| RACHA stat | "23" (accent/mint color) | Placeholder |
| SEGUIDORES stat | "412" | Placeholder |
| SIGUIENDO stat | "284" | Placeholder |
| Tab: RUTINAS PÚBLICAS | Active (mint pill style) | Placeholder list with COPIAR button stub |
| Tab: ACTIVIDAD | Inactive | Placeholder |
| Routine list items | "PHUL CUSTOM · 4 días · pública" + COPIAR button | Placeholder items |

### Critical findings from mockup

1. **Handle field** (`@mateoq`) — does NOT exist in `UserProfile`, `Post`, or any model. `displayName` in `UserProfile` is a free-text name, not a handle/username. `Post.authorDisplayName` matches. There is NO `@handle` field anywhere in the codebase. This is a net-new field OR we display `displayName` only and omit the `@` handle entirely until a future etapa adds it.

2. **Gym name resolution** ("Megatlon Recoleta") — `Post.authorGymId` stores the raw gym ID (e.g. `"megatlon-recoleta"`). The gym NAME cannot be resolved from Firestore because no `gyms/` collection exists yet. The hardcoded list in `profile_setup_providers.dart` contains 3 gyms. We can do a client-side lookup from that hardcoded list, OR display the raw `gymId` string, OR hide it if `null`/`"no-gym"`.

3. **Hero background** — no photo source in any model. Use a gradient (same accent→bg pattern as RoutineDetailScreen).

4. **Conclusion on data approach**: The mockup needs `displayName` + `avatarUrl` + `gymId`. All three are available from `Post.author*` fields. The `@handle` field does not exist in any model — display the handle row as `displayName` only (no `@` prefix) or display raw `gymId` label. This means **Approach A (denormalized from Post) is sufficient for the mockup's actual data needs**.

---

## Affected Areas

- `lib/app/router.dart` — add `/profile/:uid` route inside ShellRoute under `/feed`
- `lib/features/feed/feed_screen.dart` — wire `PostCard` `onAuthorTap` to `context.push('/feed/profile/$uid')`
- `lib/features/feed/application/friendship_providers.dart` — add outbox provider + single-friendship-by-pair lookup provider
- `lib/features/feed/data/friendship_repository.dart` — add `getByPair(myUid, otherUid)` method
- NEW `lib/features/feed/presentation/public_profile_screen.dart` — main screen
- NEW `lib/features/feed/presentation/widgets/public_profile_header.dart` — hero + avatar + name + gym + buttons
- NEW `lib/features/feed/presentation/widgets/profile_stats_row.dart` — 4-stat row (all placeholder)
- NEW `lib/features/feed/presentation/widgets/profile_tab_content.dart` — RUTINAS PÚBLICAS / ACTIVIDAD tabs
- NEW `test/features/feed/presentation/public_profile_screen_test.dart`

---

## Architectural Question: Data Approach

### Approach A — Denormalized fields from `Post` only

Read author fields from the latest post by `authorUid == targetUid`, or from whichever post the user tapped from. No new Firestore reads for the user document.

- **Pros**: Zero infra. Firestore rules already allow any auth user to read posts. `authorDisplayName`, `authorAvatarUrl`, `authorGymId` are all denormalized. Works immediately. Stale-on-update is the accepted social media pattern (same ADR already documented in `Post` model). Completely consistent with the existing codebase contract.
- **Cons**: If target user has no posts at all, fall back to "Anónimo" + initials avatar (acceptable per roadmap). No access to `bio`, `email`, or any field not in `Post`. Cannot get verified status from a post (not denormalized there currently).
- **Effort**: Low. No new collections, no Cloud Functions, no migration.
- **Verdict for this etapa**: Sufficient. Mockup needs only name + avatar + gymId. All present in `Post`.

### Approach B — New `users_public/{uid}` sidecar collection

Writable by Cloud Function triggered on `users/{uid}` write. Readable by any auth user. Contains: `displayName`, `avatarUrl`, `gymId`, `bio?`, `handle?`, `verified?`.

- **Pros**: Clean separation. Future-proof. Supports bio, handle, verified badge from a single authoritative source. No stale denorm risk.
- **Cons**: Requires Cloud Functions infra — net-new dependency that does NOT exist in this project. Requires a Firestore migration to backfill existing users. Adds Firebase billing complexity. Blocks Etapa 4 on infra work that is not in scope for Fase 3.
- **Effort**: High. New infra layer, new collection, trigger function, migration script.
- **Verdict**: Overengineered for Etapa 4. The mockup does not need bio or handle. Leave for Fase 4+ when real profile richness is required.

### Approach C — Split `users/{uid}` into private + public subcollection

`users/{uid}/public/profile` as a readable subcollection. Requires splitting the current doc and migrating existing data.

- **Pros**: Uses existing Firebase infra.
- **Cons**: Firestore does not support field-level rules — the subcollection approach is architecturally cleaner but requires migration of existing writes in `UserRepository`, `AuthService`, and `ProfileSetup` notifier. High risk of regression. No Cloud Functions needed but still a significant migration.
- **Effort**: High.
- **Verdict**: Not recommended. Migration risk outweighs benefit for this etapa.

### Recommendation: Approach A

**Rationale**: The mockup's data needs are exactly covered by `Post.author*` fields. Approach A requires zero infra changes. The "no posts" fallback (Anónimo + initials) is already handled by `PostAvatar`. Document the forward path to Approach B in code comments for Fase 4.

One addition needed: a `FriendshipRepository.getByPair(myUid, otherUid)` method to read the current friendship doc (if any) for the SEGUIR button state. This uses `Friendship.sortedDocId()` (already exists) + a single `get()` call — no new rules needed because the viewer is a member of that doc.

---

## Router Analysis

Current structure:
```
ShellRoute
  /workout → WorkoutScreen
    /workout/routine/:routineId → RoutineDetailScreen
  /feed → FeedScreen
  /home → HomeScreen
  /coach → CoachScreen
  /profile → ProfileScreen
```

Options:

**Option R1 — Nested under `/feed`:**
```
/feed → FeedScreen
  feed/profile/:uid → PublicProfileScreen   ← push navigation
```
- Bottom bar stays visible. User can tap another tab without losing back-stack.
- `context.push('/feed/profile/$uid')` from `PostCard`.
- `_kTabs` index detection already uses `startsWith` — `/feed/profile/xxx` still resolves to index 1 (Feed tab). Bottom bar works correctly with no changes.
- Back button: `context.pop()` returns to Feed.

**Option R2 — Standalone top-level inside ShellRoute:**
```
/profile/:uid → PublicProfileScreen   ← separate path
```
- Conflicts naming with `/profile` (own profile). Would require care to not accidentally redirect to `/profile-setup`.
- `authRedirect` checks `location.startsWith('/profile-setup')` — safe. But adding `/profile/:uid` at the same level as `/profile` is ambiguous in go_router path matching.
- Cleaner route path but introduces naming collision risk.

**Recommendation: Option R1** — nest under `/feed` as `/feed/profile/:uid`. Avoids naming collision with `/profile`. Bottom bar works automatically. Clean back navigation. Consistent with `/workout/routine/:routineId` pattern already established.

---

## Friendship / SEGUIR Button States

The mockup shows SEGUIR (active mint) and MENSAJE (outlined disabled). Four logical states must be handled:

| State | Condition | Button label | Button style |
|---|---|---|---|
| Not following | No friendship doc exists | "SEGUIR" | Mint filled |
| Request sent | Doc exists, status=pending, requesterId==viewer | "SOLICITUD ENVIADA" | Outlined disabled |
| Request received | Doc exists, status=pending, requesterId==target | "ACEPTAR" | Mint filled |
| Following | Doc exists, status=accepted | "SIGUIENDO" | Outlined (with check icon) |

**Current gap in providers**: `friendship_providers.dart` has inbox (`pendingRequestsFor`) but NO single-pair lookup. Need:
- `FriendshipRepository.getByPair(myUid, otherUid)` — reads the deterministic doc at `sortedDocId(myUid, otherUid)`. Returns `Friendship?`.
- New Riverpod provider: `friendshipByPairProvider = FutureProvider.family<Friendship?, ({String myUid, String targetUid})>`.
- Firestore rules: viewer IS a member of the friendship doc (or the doc doesn't exist), so the existing member-only read rule is satisfied on existing docs. A non-existent doc returns null from `get()` without a permission error.

---

## Gym Name Resolution

`Post.authorGymId` stores the raw gym ID (e.g. `"megatlon-recoleta"`, `"no-gym"`, or `null`).

No `gyms/` Firestore collection exists. The hardcoded gym list in `profile_setup_providers.dart` has 3 entries. Resolution strategy:

1. Look up `gymId` in `_kHardcodedGyms` (same constant). If found → display gym name. If `"no-gym"` or `null` → hide the gym label entirely. If unrecognized ID → display raw ID as-is (edge case from seed data or future gyms).
2. Extract the lookup into a `gymNameFromId(String? gymId)` utility function — callable from both `ProfileSetup` and `PublicProfileScreen` without duplication.

No Firestore reads needed for gym name in this etapa.

---

## Tabs: RUTINAS PÚBLICAS / ACTIVIDAD

Mockup uses pill-style tabs identical to `FeedSegmentPills`. Each pill is wide enough to span half the row. Not a `TabBar` widget — use the same pill pattern already established.

Both tabs: placeholder content this etapa.
- RUTINAS PÚBLICAS: static list of 2 placeholder routine rows (matching mockup) with disabled COPIAR buttons.
- ACTIVIDAD: empty state or single "Próximamente" text.

Use a local `StateProvider<ProfileTab>` (scoped to the screen) rather than a global provider — the tab state is ephemeral and screen-local.

---

## Stats Placeholder

All four stats (`workouts`, `racha`, `seguidores`, `siguiendo`) are "todos placeholder hasta Fase 4" per roadmap.

Display as numeric literal `0` with their labels. Mockup shows real numbers — the visual design is for illustration. Using `0` (not `--`) is less confusing for users and easier to replace with real data in Fase 4 without layout changes. `racha` value rendered in `palette.accent` color per mockup.

---

## Feature Folder Decision

**Option F1 — `lib/features/feed/`**: semantically correct (public profile is reached from Feed; it's part of the social graph). All social providers live here. Tests already follow `test/features/feed/` pattern. No cross-feature imports needed — friendship repo, post repo, and the new providers are all in `features/feed/`.

**Option F2 — `lib/features/profile/`**: structurally correct (it's a profile screen). But the OWN profile screen (`ProfileScreen`) is a stub with zero substance. Moving social functionality here would create a dependency from `features/profile/` on `features/feed/` (for friendship providers), inverting the current import direction.

**Recommendation: `lib/features/feed/`** — avoids cross-feature import inversion, co-locates with all relevant domain models, and mirrors the test conventions already established.

---

## Decisions Summary for Propose

| # | Decision | Recommendation | Rationale |
|---|---|---|---|
| a | Data approach | **A — denorm from Post** | Mockup needs only name+avatar+gymId; all present in Post. No infra overhead. |
| b | Feature folder | **`lib/features/feed/`** | Avoids import inversion; all social models live here. |
| c | Router placement | **Nested under `/feed`** as `/feed/profile/:uid` | Consistent with `/workout/routine/:id` pattern; avoids `/profile` naming collision; bottom bar free. |
| d | Tabs implementation | **Pill-based segments** (reuse `_Pill` pattern from `FeedSegmentPills`) | Consistent with existing Feed UI; no native TabBar needed. |
| e | SEGUIR button states | **4 states** (not following / request sent / request received / following) | Covers all Friendship status × requester combinations. |
| f | Stats placeholder | **`0`** for all four values | Cleaner than `--`; easy substitution in Fase 4. |
| g | Gym name resolution | **Client-side lookup from hardcoded list** + `gymNameFromId()` utility | No Firestore collection exists; no new infra needed. |
| h | Handle field | **Omit `@handle`** — display `displayName` only, gym in subtitle | `@handle` field does not exist in any model. Mockup shows it as nice-to-have; omit until Fase 4. |

---

## Risks

1. **`@handle` gap** — The mockup shows `@mateoq` below the display name. No handle/username field exists in `UserProfile` or `Post`. Either the mockup is aspirational, or we need to add a `handle` field to `UserProfile` (and denormalize into `Post.authorHandle`) before this etapa can be 100% mockup-faithful. **Proposal should call this out explicitly** and decide: omit handle for now (recommended) vs. add `handle` to `UserProfile` (requires data migration for existing users + ProfileSetup update).

2. **`pendingRequestsProvider` covers INBOX only** — No outbox provider exists. To know if the viewer ALREADY sent a request to the target, we need `getByPair()` (new method). This is small but must be in scope.

3. **`PostCard.onAuthorTap` is a stub** — `FeedScreen` renders `PostCard` without `onAuthorTap`. Wiring it requires passing the handler from `FeedScreen` down to `PostCard`. Low risk but touches existing production widget.

4. **Own profile collision** — If a user navigates to `/feed/profile/{their own uid}`, the public profile screen renders for them as a viewer. The SEGUIR button must be hidden/disabled for self-visits. Add `viewerUid == targetUid` guard.

5. **No posts for target user** — If target has never posted, we have no `Post` to read `authorDisplayName` from. Need a fallback data strategy: either query `posts` collection for `authorUid == targetUid limit 1`, or accept that "Anónimo" + initials is the fallback display. Approach A's primary weakness.

6. **Gym name resolution coverage** — The hardcoded list has only 3 gyms. Users with other gym IDs (from seed data or future gym additions) will show the raw gym ID string or nothing. Acceptable for now.

---

## Ready for Proposal

Yes. All architectural questions have clear answers. The proposal should:
1. Confirm Approach A + document forward path to Approach B in Fase 4.
2. Define the new `getByPair()` repository method and its provider.
3. Confirm feature folder as `lib/features/feed/`.
4. Confirm router placement.
5. Decide on `@handle` omission explicitly.
6. Specify the "no posts" fallback strategy (query with limit 1 is cleanest).

# Explore — feed-shell-amigos

**Change**: `feed-shell-amigos`
**Fase / Etapa**: Fase 3 · Etapa 2
**Branch (target)**: `feat/feed-shell-amigos`
**Owner**: Dev B (visual owner of all Feed screens)
**Project**: treino
**Artifact store**: openspec
**Date**: 2026-05-15

---

## Current State

### Data layer (Etapa 1 — fully merged, PR #22, commit 5058cb6)

- `lib/features/feed/domain/post.dart` — `Post` freezed: `id`, `authorUid`, `authorGymId?`, `text`, `routineTag?` (`RoutineTag`), `privacy` (`PostPrivacy`), `createdAt`
- `lib/features/feed/domain/routine_tag.dart` — `RoutineTag`: `routineId`, `routineName` (denormalized)
- `lib/features/feed/domain/post_privacy.dart` — enum: `friends` | `gym` | `public`
- `lib/features/feed/domain/friendship.dart` + `friendship_status.dart`
- `lib/features/feed/data/post_repository.dart` — `feedForFriends(List<String>)`, `feedPublic()`, `feedForGym(String)`, `byAuthor(String)`, `create(Post)`
- `lib/features/feed/data/friendship_repository.dart` — `acceptedFriendsOf(String uid)` returns `List<String>`
- `lib/features/feed/application/post_providers.dart` — `feedForFriendsProvider.family<List<Post>, List<String>>`, `feedPublicProvider`, `feedForGymProvider.family`
- `lib/features/feed/application/friendship_providers.dart` — `acceptedFriendsProvider.family<List<String>, String>` (takes UID, returns friend UIDs)
- `lib/features/feed/feed_screen.dart` — placeholder (`Center` with "FEED" text + "Amigos · Comunidad · Público"), zero provider coupling

### Router (confirmed)

`lib/app/router.dart` line 23: `const _kTabs = ['/workout', '/feed', '/home', '/coach', '/profile']` — Feed is index 1. GoRoute at `/feed` renders `FeedScreen`. No sub-routes under `/feed` yet. ShellRoute wraps with `_ShellScaffold` → `AppBackground` + `SafeArea` + `TreinoBottomBar`. No Scaffold in screen.

### UI patterns (canonical references)

- **Screen layout**: `WorkoutScreen` + `HomeScreen` — `Padding(horizontal: 20)` + `ListView(padding: vertical:20, physics: ClampingScrollPhysics)`, no Scaffold, no AppBackground (shell handles it).
- **Segment pills**: `LevelFilterPills` (`lib/features/workout/presentation/widgets/level_filter_pills.dart`) — `SingleChildScrollView` + `Row` + `_Pill` widgets; active pill uses `palette.accent` bg + `palette.bg` text; inactive uses `palette.bgCard` bg + `border` outline. Border radius 20 (r-lg). Padding `h:14 v:8`. Font: `labelMedium` 600.
- **Card pattern**: `RoutineCard` — `Container` with `bgCard` bg, `r-lg` (20) border radius, 1px `border`, optional accent/highlight glow `BoxShadow`. Padding: `all: 18`. Uses `GestureDetector` with `HitTestBehavior.opaque`.
- **Header pattern**: `HomeHeader` — `Row` with `GoogleFonts.barlowCondensed` title (700, UPPERCASE) + right-side action widget. Avatar uses `CachedNetworkImage` with initials fallback.
- **Loading state**: `PlantillasSection` — `CircularProgressIndicator(color: palette.accent)` centered inside `Padding(vertical:20)`.
- **Empty state**: `PlantillasSection` — single `Text` with `palette.textMuted`, body style. No illustration at this level.
- **Section title**: `Text` with `titleMedium` style (Barlow Condensed 700 UPPERCASE from theme).
- **Section spacing**: `SizedBox(height: 12)` after title, `SizedBox(height: 14)` after pills.

### Theme tokens available

`AppPalette`: `accent` (#2CE5A2 mint), `highlight` (#C123E0 magenta), `bg` (#0A0A0A ink), `bgCard` (#0F1513), `border` (rgba white 0.10), `textPrimary` (#FFF), `textMuted` (rgba white 0.55), `sage` (#4F6358), `espresso` (#3C3534). No feed-specific tokens — reuse existing set.

### TreinoIcon inventory (relevant to Feed)

Already defined: `search` (magnifyingGlass), `plus`, `users`, `globe`, `check` (checkCircle fill), `bell`, `clock`, `chartBar`. Missing: `dotsThree` (post overflow menu) — needs to be added if used. Verified badge in mockup is a small filled checkmark — `check` icon or a separate `verified` semantic constant needed.

### Test baseline

Highest SCENARIO number after Etapa 1: **SCENARIO-132** (friendship delete, `test/features/feed/data/friendship_repository_test.dart`). New feed UI scenarios start at **SCENARIO-133**.

Test patterns in use: `FakeFirebaseFirestore`, `mocktail`, `ProviderScope.overrides`, `flutter_test`. Widget tests follow `test/features/<feature>/presentation/<screen>_test.dart` mirroring `lib/`.

---

## Mockup Analysis (`docs/app-alumno/screens/feed/feed.png`)

### Layout decomposition

```
┌─────────────────────────────────┐
│  FEED                 [🔍] [➕] │  ← Header row: title left, search+FAB right
├─────────────────────────────────┤
│ [AMIGOS] [MI GYM] [PÚBLICO]     │  ← Segment pills (horizontal scroll not needed at 3)
├─────────────────────────────────┤
│  ┌──────────────────────────┐   │
│  │ [ML] Martin L.   Hace 2h │   │  ← PostCard
│  │      La Fuerza      [···]│   │    avatar | name | gym + timestamp | overflow
│  │  [↗ Push · Día 4]        │   │    routine tag chip (optional)
│  │  PECHO · HOMBROS         │   │    muscle group label
│  │  6,420 kg  58 min  7 ej. │   │    stats row (stub)
│  └──────────────────────────┘   │
│  ┌──────────────────────────┐   │
│  │ [SR] Sofia R. ✓  Hace 4h │   │    Second card — verified badge visible
│  │      La Fuerza      [···]│   │
│  │  [↗ Legs]                │   │
│  │  PECHO · HOMBROS         │   │
│  │  6,420 kg  58 min  7 ej. │   │
│  └──────────────────────────┘   │
└─────────────────────────────────┘
```

### Element-by-element analysis

**Header**:
- Title: "FEED" — `barlowCondensed` 700 UPPERCASE (matches other screen headers)
- Right side: search icon button + FAB (plus) icon button — both present in mockup
- Search navigates to `/feed/search` (Etapa 5, stub for now)
- Plus navigates to `/feed/create` (Etapa 5, stub for now)
- Header is NOT sticky — scrolls with content (same as WorkoutScreen pattern)
- No `AppBar` widget — inline `Row` in list header (matches HomeHeader pattern)

**Segment pills**:
- Three pills: "AMIGOS" (active, accent bg) · "MI GYM" (inactive) · "PÚBLICO" (inactive)
- Style: identical to `LevelFilterPills._Pill` — border-radius 20, padding h:14 v:8
- Active: `palette.accent` bg, `palette.bg` text
- Inactive: `palette.bgCard` bg + `palette.border` outline, `palette.textPrimary` text
- Disabled appearance for MI GYM + PÚBLICO: either visually greyed (opacity ~0.4) OR same inactive style but not tappable
- No horizontal scroll needed for 3 items on a phone screen

**PostCard** (key reusable widget):
- Avatar: 40×40 circle — initials fallback (ML = "Martin L.", SR = "Sofia R.") with accent→highlight gradient (same as HomeHeader._AvatarFallback)
- Name: `bodyMedium` or `labelMedium` 600 — `textPrimary`
- Verified badge: small filled checkmark icon (`TreinoIcon.check`) in `palette.accent`, ~12px — only visible on second card (Sofia R.). Need `verified` semantic constant in `TreinoIcon`
- Timestamp: "Hace 2h" — `bodySmall` `textMuted` — relative time formatting needed
- Gym name: below name row — "La Fuerza" — `bodySmall` `textMuted`
- Overflow: `···` button (three dots) — top right of card — needs `dotsThree` icon in `TreinoIcon`
- Routine tag chip (optional): pill-shaped chip, accent-tinted — "Push · Día 4" or "Legs" — shown when `routineTag != null`
- Muscle group label: "PECHO · HOMBROS" — `bodySmall` or `labelSmall` UPPERCASE `textMuted` — where does this come from? Post has no muscle group field. This is a STUB label — either hardcoded placeholder or derived from the routine tag (not from `Post` model). Mark as stub for Fase 4.
- Stats row: "6,420 kg  58 min  7 ej." — three values — no fields in `Post`. These are stats stubs. Render as placeholder numbers or zeroes for now. Fase 4 adds real data.
- Card container: `bgCard` bg, 1px `border`, `r-lg` (20) radius — matches `RoutineCard` pattern
- Card internal padding: `all: 18` — matches `RoutineCard`

**Author info gap** (critical — see Q1 below):
- Mockup shows author `displayName` and `avatarUrl` per card
- `Post` only has `authorUid` — NO `displayName`, NO `avatarUrl` in the model
- `users/{uid}` Firestore rule: **owner-only read** (`request.auth.uid == uid`) — other users CANNOT read each other's profile docs
- There is NO `users_public` collection in `firestore.rules`
- There is NO `userPublicInfoProvider` in the codebase
- The `UserProfile.displayName` and `UserProfile.avatarUrl` are in `users/{uid}` which is blocked for cross-user reads

**`feed-publico.png`** — Public profile view (Etapa 4 scope, NOT Etapa 2):
- Shows: hero photo, avatar, name, handle "@mateoq", gym name "Megatlon Recoleta"
- SEGUIR + MENSAJE buttons; stats grid (workouts, racha, seguidores, siguiendo); RUTINAS PÚBLICAS / ACTIVIDAD tabs
- Post cards in ACTIVIDAD tab do NOT appear in this mockup — this confirms PostCard is used in the main feed, not in public profile detail (for now)

---

## Open Questions — Resolved by Investigation

### Q1: How does PostCard render author info?

**Finding**: BLOCKED — there is NO mechanism to read another user's `displayName` or `avatarUrl` from the current codebase. `firestore.rules` restricts `users/{uid}` to owner-only reads. No public user collection exists.

**Impact**: This is the #1 architectural blocker for the propose phase. `PostCard` CANNOT render author names/avatars without either:
1. A new `users_public/{uid}` Firestore collection with relaxed rules (all-auth read), OR
2. Denormalizing `displayName` and `avatarUrl` into the `Post` document itself (at write time), OR
3. A Cloud Function that materializes public profiles, OR
4. Accepting initials-only / UID-based display for MVP (no name resolution)

Option 1 is the cleanest architecturally and aligns with the Etapa 4 public profile screen (`/profile/:uid`) that will also need this. Option 2 requires adding fields to `Post` (model change, freezed regen). Option 4 degrades UX significantly. This decision must be made in the propose phase.

### Q2: How does AMIGOS resolve friend UIDs?

**Finding**: `acceptedFriendsProvider` in `friendship_providers.dart` is `FutureProvider.family<List<String>, String>` — takes a UID and returns the list of accepted friend UIDs. The composition chain in the UI is:

```
1. Watch authStateChangesProvider → User?.uid (currentUid)
2. Watch acceptedFriendsProvider(currentUid) → List<String> (friendUids)
3. Watch feedForFriendsProvider(friendUids) → List<Post>
```

Step 3 has a key constraint: `feedForFriendsProvider.family` takes `List<String>` as the family key. Riverpod uses `==` on the parameter to decide whether to rebuild. Two different `List<String>` instances with the same content are NOT equal by default in Dart. This means every rebuild will create a new provider instance — **potential infinite rebuild loop**.

**Solutions**:
- Option A: Compose a single derived `myFriendsFeedProvider` that does all three steps internally, using `ref.watch` + `ref.read` carefully
- Option B: Create an intermediate `myFriendUidsProvider` that returns an immutable/stable value
- Option C: Override `==` or use sorted joined string as key (already supported — `post_providers.dart` comment notes "stable for small sets")

Option A (single derived provider) is the cleanest and avoids the `List` equality problem entirely.

---

## Affected Files

### Files to create (new)

- `lib/features/feed/feed_screen.dart` — full replacement of placeholder
- `lib/features/feed/presentation/widgets/post_card.dart` — reusable PostCard widget
- `lib/features/feed/presentation/widgets/feed_segment_pills.dart` — AMIGOS/MI GYM/PÚBLICO pills (OR reuse `LevelFilterPills` pattern with local enum)
- `lib/features/feed/presentation/widgets/feed_empty_state.dart` — empty state for no posts
- `lib/features/feed/application/feed_providers.dart` — derived `myFriendsFeedProvider` (and later `selectedSegmentProvider`)
- `test/features/feed/presentation/feed_screen_test.dart` — widget tests SCENARIO-133+
- `test/features/feed/presentation/widgets/post_card_test.dart` — widget tests

### Files to modify

- `lib/app/router.dart` — add `/feed/search` and `/feed/create` stub routes (stubs for Etapa 5); tap targets in header need routes to exist even if screens are placeholder
- `lib/core/widgets/treino_icon.dart` — add `dotsThree` (overflow menu) and optionally `verified` semantic constant
- `firestore.rules` — **only if Q1 is resolved via Option 1** (new `users_public` collection)

### Files NOT touched (scope boundary)

- Any file under `lib/features/workout/`, `lib/features/home/`, `lib/features/auth/`, `lib/features/profile/`, `lib/features/coach/` — visual ownership convention in `docs/workflow.md` requires consulting other owners before touching their UI
- `lib/features/feed/data/` — data layer is complete, no changes needed
- `lib/features/feed/domain/` — domain models complete; changes only if Q1 resolved via denormalization (Option 2)
- `lib/features/feed/application/post_providers.dart` + `friendship_providers.dart` — existing providers untouched; only new derived providers added to new `feed_providers.dart`

---

## Approaches Comparison

### Approach 1: Author info via `users_public/{uid}` collection

Add a `users_public/{uid}` Firestore collection with public-safe fields only (`displayName`, `avatarUrl`, `gymName`). Firestore rule: `allow read: if request.auth != null`. Populated by Cloud Function trigger on `users/{uid}` write.

| Dimension | Assessment |
|---|---|
| Pros | Clean separation of private vs public profile data; no Post model changes; enables Etapa 4 public profile; aligns with Firestore best practice |
| Cons | Requires new Firestore collection + rule change + Cloud Function or Admin SDK sync; more infra; out of scope for a single etapa |
| Effort | High — touches infra (rules, functions), not just UI |
| Risk | Cloud Function sync delay (eventual consistency between users/ and users_public/) |

### Approach 2: Denormalize `authorDisplayName` + `authorAvatarUrl` into `Post`

Add two nullable fields to `Post` freezed model. `PostRepository.create()` reads them at write time (like `authorGymId` pattern already does). For existing seed posts, fields are null → fallback to initials.

| Dimension | Assessment |
|---|---|
| Pros | Zero new infrastructure; follows existing ADR pattern (`authorGymId` denormalization); single read at write time; works with current Firestore rules |
| Cons | Model change requires freezed regen + migration; stale data if user updates name/avatar (acceptable for social MVP — posts reflect authorship at time of posting); seed script needs update |
| Effort | Medium — model change + freezed regen + `PostRepository.create()` update + seed script + test updates |
| Risk | Seed posts already in Firestore have null for these fields — UI must handle null gracefully with initials fallback |

### Approach 3: Initials-only / UID-based display (no name resolution)

`PostCard` shows initials derived from UID (first char), no display name. Avatar always initials fallback.

| Dimension | Assessment |
|---|---|
| Pros | Zero changes to data layer; quickest path to visible UI |
| Cons | Poor UX — "f3aB92..." as user identifier; mockup explicitly shows names; unacceptable for a social app demo |
| Effort | Low |
| Risk | Wrong product signal — would not match mockup at all |

### Approach 4: Read `users/{uid}` client-side via admin bypass / unsafe rule

Relax `users/{uid}` rule to allow all-auth reads.

| Dimension | Assessment |
|---|---|
| Pros | Simple (no new collection) |
| Cons | Exposes private user data (email, role, weight, height, etc.) to all authenticated users — security violation |
| Effort | Trivial |
| Risk | CRITICAL security risk — ruled out |

### Recommendation for Q1

**Approach 2 (denormalization)** for MVP because it follows the established ADR pattern (`authorGymId` precedent), requires no new infra, and keeps Etapa 2 self-contained. The propose phase should formally confirm this and document the ADR. The `Post` model grows to 9 fields. Null fallback (initials avatar + "Unknown" name) handles the seed data gap gracefully.

If the team prefers future-proofing, Approach 1 is architecturally superior but is a larger scope bump that could be its own etapa.

### Approach for Q2: AMIGOS friend UID composition

**Recommended: Single derived `myFriendsFeedProvider`** (no family, no List equality issue):

```dart
final myFriendsFeedProvider = FutureProvider<List<Post>>((ref) async {
  final auth = await ref.watch(authStateChangesProvider.future);
  if (auth == null) return [];
  final friendUids = await ref.watch(acceptedFriendsProvider(auth.uid).future);
  return ref.watch(postRepositoryProvider).feedForFriends(friendUids);
});
```

This is a plain `FutureProvider` (no family), eliminates the `List<String>` equality problem, and is easily testable via `ProviderScope.overrides`.

### Approach for segments UI: Reuse `_Pill` pattern, new `FeedSegmentPills` widget

`LevelFilterPills` is tightly coupled to `routinesLevelFilterProvider`. A new `FeedSegmentPills` widget with its own `selectedSegmentProvider` (StateProvider<FeedSegment>) decouples cleanly. The `_Pill` widget visual pattern (Container + BoxDecoration) is copied, not shared, to avoid cross-feature import. This is consistent with visual ownership conventions — Feed owns its own pill visual component.

### Approach for disabled segments (MI GYM + PÚBLICO)

**Recommended: visually greyed (opacity 0.4) AND not tappable.** "Coming soon" empty state adds complexity. A greyed-out pill is immediately communicative without requiring a new screen or state branch. Tapping does nothing (null `onTap`). This is the simplest implementation consistent with the mockup (which shows them as clearly non-selected but visible).

### Approach for tap on author (avatar/name)

**Recommended: stub no-op (`onPressed: null` / no `GestureDetector`)** for Etapa 2. The route `/profile/:uid` (Etapa 4) does not exist yet. Adding a stub route now would require a router change AND a placeholder screen. Better to wire it in Etapa 4 when the profile screen exists. PostCard author tap is defined as `VoidCallback? onAuthorTap` parameter — null by default, wired by `FeedScreen` or left null.

### Approach for tap on RoutineTag chip

**Recommended: navigate to `/workout/routine/:routineId`** — this route already exists (added in Etapa 3/4 of Fase 2). `RoutineTag.routineId` is available on the `Post`. This is zero extra work and delivers a useful UX. `PostCard` receives an `onTagTap: VoidCallback?` parameter.

### Loading state

**Recommended: centered spinner** (`CircularProgressIndicator(color: palette.accent)`) — consistent with `PlantillasSection` pattern. Skeleton cards are a future polish item (not in mockup).

### Pull-to-refresh

**Out of scope for Etapa 2.** Mockup does not show a refresh indicator. All feeds are `FutureProvider` (one-time load). Refresh via `ref.invalidate` can be added in Etapa 3 when segments are functional. No `RefreshIndicator` wrapper needed.

### Post detail screen

**None.** The mockup shows no post detail screen. Cards are not tappable as a whole. Author tap → profile (stub). Tag tap → routine detail. Stats/overflow → out of scope.

---

## Design Decisions to Surface for Propose

| ID | Decision | Recommended resolution |
|---|---|---|
| D1 | How PostCard renders author name/avatar | Denormalize `authorDisplayName?` + `authorAvatarUrl?` into `Post` at write time (Approach 2) — follows ADR pattern of `authorGymId` |
| D2 | Derived provider for AMIGOS feed composition | Single `myFriendsFeedProvider` (FutureProvider, no family) to avoid `List<String>` equality issue |
| D3 | Feed segments state | `StateProvider<FeedSegment>` with `FeedSegment.amigos / miGym / publico` enum; `FeedSegmentPills` widget owns visual |
| D4 | MI GYM + PÚBLICO state | Visually greyed (opacity 0.4), not tappable — no "Coming soon" state needed |
| D5 | Author tap | Null/no-op in Etapa 2; wire to `/profile/:uid` in Etapa 4 |
| D6 | Routine tag tap | Navigate to existing `/workout/routine/:routineId` via `context.push` |
| D7 | Stats row in PostCard | Stub with zeroes or em-dashes (`—`); no `Post` fields back them for now |
| D8 | Muscle group in PostCard | Stub text (e.g. from `RoutineTag` if present, else hidden); Fase 4 wires real data |
| D9 | Missing TreinoIcon constants | Add `dotsThree` (PhosphorIconsRegular.dotsThreeOutline or similar) + `verified` (PhosphorIconsFill.sealCheck) to `treino_icon.dart` |
| D10 | New routes `/feed/search` + `/feed/create` | Add stub GoRoutes returning placeholder `Scaffold` now so header icon buttons can navigate without crashing |
| D11 | Relative time formatting | `timeago` package (already used elsewhere?) or manual `Duration` formatting; no external dependency added if done inline |

---

## Out-of-Scope Items (surface for propose to acknowledge)

- MI GYM segment functional → Etapa 3
- PÚBLICO segment functional → Etapa 3
- Crear post UI (`/feed/create`) → Etapa 5
- Search usuarios UI (`/feed/search`) → Etapa 5
- Public profile screen `/profile/:uid` → Etapa 4
- Post likes / comments / reactions → Fase 3.5 (not in current mockup)
- Stats reales en PostCard (`kg`, `min`, `ej.`) → Fase 4
- Pull-to-refresh → Etapa 3+
- Skeleton loading → polish (not required)
- Post detail screen → not in roadmap / mockup
- `users_public` collection infrastructure → only if team rejects D1 in propose

---

## Constraints and Risks

| Risk | Severity | Notes |
|---|---|---|
| **Firestore rules block cross-user reads** | CRITICAL | `users/{uid}` is owner-only. `Post` has no author name/avatar. Propose must resolve D1 before spec can write author-display requirements. Without resolution, PostCard cannot match mockup. |
| `List<String>` equality in `feedForFriendsProvider.family` | HIGH | If FeedScreen passes a new List instance on every rebuild, Riverpod creates a new provider instance each time → infinite rebuild loop. Resolved by derived `myFriendsFeedProvider`. |
| Freezed regen required if Post model changes (D1) | MEDIUM | `dart run build_runner build --delete-conflicting-outputs` + update generated files. Adds ~30s to CI. Test baseline (418) must stay green. |
| `timeago` or relative time formatting | LOW | Check if `timeago` package is in `pubspec.yaml`. If not, implement inline `Duration.since(createdAt)` formatter — straightforward for "Hace 2h" display. |
| Stats stub UX | LOW | Showing `0 kg  0 min  0 ej.` for stub data could confuse testers. Consider showing em-dash `—` instead until Fase 4 wires real data. |
| Router change (D10) touches shared file | LOW | `router.dart` is listed as a coordination-required file in `docs/workflow.md`. Notify other 2 devs before PR. |

---

## Test Scenario Planning

New scenarios start at **SCENARIO-133** (baseline was 418 passing after Etapa 1).

| # | Area | Type | Description |
|---|---|---|---|
| 133 | `FeedScreen` | Widget | AMIGOS segment selected by default; MI GYM + PÚBLICO pills rendered |
| 134 | `FeedScreen` | Widget | MI GYM + PÚBLICO pills are not tappable (disabled state) |
| 135 | `FeedScreen` | Widget | AMIGOS shows `CircularProgressIndicator` while loading |
| 136 | `FeedScreen` | Widget | AMIGOS shows empty state widget when post list is empty |
| 137 | `FeedScreen` | Widget | AMIGOS shows list of `PostCard` widgets when posts are loaded |
| 138 | `PostCard` | Widget | Renders author name, avatar initials fallback, timestamp, gym |
| 139 | `PostCard` | Widget | Shows routine tag chip when `routineTag != null` |
| 140 | `PostCard` | Widget | Hides routine tag chip when `routineTag == null` |
| 141 | `PostCard` | Widget | Stats row renders stub values |
| 142 | `myFriendsFeedProvider` | Unit | Returns empty list when user has no friends |
| 143 | `myFriendsFeedProvider` | Unit | Returns friends' posts when friends list is non-empty |

---

## Ready for Proposal

**Yes — with one caveat**: the propose phase MUST formally resolve Decision D1 (author info strategy) before the spec can write testable requirements for `PostCard` author display. All other decisions have clear recommendations. If the team confirms Approach 2 (denormalization), the spec adds `authorDisplayName?` + `authorAvatarUrl?` to `Post` model requirements and the design phase documents the updated API contract.

The data layer is solid. The UI patterns are well-established. The main unknowns are D1 (author info) and the exact copy for the empty state, which the propose phase can nail down with a quick mockup check.

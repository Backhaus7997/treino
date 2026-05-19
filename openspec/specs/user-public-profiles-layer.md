# Spec: User Public Profiles Layer

**Layer**: user-public-profiles (identity + search)
**Fase / Etapa**: 3 / 5.5
**SDD Cycle**: 2026-05-15 to 2026-05-19
**Delivered by**: PR #40 (`feat/user-public-profiles`) + PR #44 (`feat/user-public-profiles-search`)
**Status**: ARCHIVED
**Related Specs**: feed-data-layer.md, profile-layer.md

---

## Overview

The user-public-profiles layer provides a **schema-level privacy boundary** for user identity, enabling authenticated discovery (search) and public profile rendering without exposing the owner-only `users/{uid}` collection. It replaces a fragile Etapa 4 workaround (`firstPostByAuthorProvider` → "Anónimo" fallback) with a canonical identity source: the `userPublicProfiles` collection.

### Motivation

The deprecated `feed-search-users` branch crashed at runtime with `permission-denied` errors when attempting to read `users/{uid}` from an authenticated-only rule. Rather than widening privacy on sensitive user data (email, role, createdAt, password), we create a separate public-identity collection containing ONLY public and public-soft fields. This is the architectural decision boundary that prevents future privacy regressions.

### Capabilities

| Capability | Provided by |
|------------|-------------|
| Public user identity (uid, displayName, avatar, gym) | UserPublicProfile model + userPublicProfiles collection |
| Atomic user identity maintenance | WriteBatch dual-write in UserRepository |
| Authenticated user discovery | searchUsersProvider + SearchUsersScreen |
| Public profile rendering | publicProfileViewProvider (refactored) |

---

## Collection Schema: `userPublicProfiles/{uid}`

### Document Structure

```json
{
  "uid": "string (required)",
  "displayName": "string (nullable)",
  "displayNameLowercase": "string (nullable)",
  "avatarUrl": "string (nullable)",
  "gymId": "string (nullable)"
}
```

### Field Definitions

| Field | Type | Nullable | Source | Privacy |
|-------|------|----------|--------|---------|
| `uid` | String | Required | User UID from auth | public |
| `displayName` | String | Nullable | users/{uid}.displayName | public |
| `displayNameLowercase` | String | Nullable | derived from displayName (trim + toLowerCase) | public-soft |
| `avatarUrl` | String | Nullable | users/{uid}.avatarUrl | public |
| `gymId` | String | Nullable | users/{uid}.gymId | public-soft |

### Invariants

1. `uid` is the document ID and MUST match the field value.
2. `displayNameLowercase` is ALWAYS derived by server/repository logic; callers MUST NOT provide it.
3. `displayNameLowercase` equals `displayName?.trim().toLowerCase()` when displayName is present.
4. All fields other than `uid` are **nullable**; they reflect the current state of the user's profile.
5. There is NO `createdAt` or `updatedAt` in the public collection (private metadata lives only in `users/{uid}`).

### Firestore Rules

```firestore-rules
match /userPublicProfiles/{uid} {
  allow read: if request.auth != null;
  allow create: if request.auth != null
                && request.auth.uid == uid
                && request.resource.data.uid == uid;
  allow update: if request.auth != null
                && request.auth.uid == uid
                && request.resource.data.uid == resource.data.uid;
  allow delete: if false;
}
```

**Rule Semantics**:
- `read` is granted to any authenticated user (enables UserPublicProfileRepository.get + profile rendering)
- `list` is covered by `read` per Firestore semantics (enables prefix range query for search)
- `create` requires auth.uid == document uid and explicit uid field assertion (prevents spoofing)
- `update` requires auth.uid == document uid and uid immutability (owner can modify, cannot change uid)
- `delete` is forbidden (soft-delete only; doc remains as anchor for firestore indexes)

---

## API Layer: Repositories and Providers

### UserPublicProfileRepository

**Module**: `lib/features/profile/data/user_public_profile_repository.dart`

**Dependency**: `FirebaseFirestore` instance (injected via Riverpod)

**Public Methods**:

```dart
// Fetch a single profile by uid
Future<UserPublicProfile?> get(String uid)

// Write or update a profile (merge: true for idempotency)
Future<void> set(UserPublicProfile profile)

// Prefix search on displayNameLowercase field
// Returns up to 20 results sorted by displayName.
// Returns empty list if query is empty or blank after trim().
Future<List<UserPublicProfile>> searchByDisplayName(
  String query, {
  int limit = 20,
})
```

**Implementation Notes**:
- `get(uid)` returns `null` when the document does not exist (no exception thrown).
- `set(profile)` uses `SetOptions(merge: true)` for idempotency.
- `searchByDisplayName(query)` executes a prefix range query:
  ```
  query >= query
  && query <= query + ''  (or similar suffix for Firestore)
  ```
  The query is automatically normalized to lowercase by the caller (searchUsersProvider).
- The repository DOES NOT enforce the 2-character minimum or debouncing; those are provider/presentation concerns.

### userPublicProfileRepositoryProvider

**Module**: `lib/features/profile/application/user_public_profile_providers.dart`

**Type**: `Provider<UserPublicProfileRepository>`

**Semantics**: Singleton repository instance, injected across the app.

### userPublicProfileProvider

**Module**: `lib/features/profile/application/user_public_profile_providers.dart`

**Type**: `FutureProvider.family<UserPublicProfile?, String>`

**Family Key**: uid (String)

**Semantics**:
- Fetches the profile for a given uid.
- Returns `null` when no document exists or the user is unauthenticated (auth gates the read).
- Used by `publicProfileViewProvider` to render public profile names.
- Used by `SearchUsersScreen` to display result details.

---

## Application Layer: Search Provider

### searchUsersProvider

**Module**: `lib/features/feed/application/search_users_provider.dart`

**Type**: `FutureProvider.autoDispose.family<List<UserPublicProfile>, String>`

**Family Key**: normalized query string (lowercase)

**Behavior**:
1. Accepts raw query input from SearchUsersScreen (e.g., "MAR", "Mar", "mar").
2. Normalizes to lowercase for consistent family keying.
3. Returns empty list if query is empty or has fewer than 2 characters after normalization.
4. Delegates to `UserPublicProfileRepository.searchByDisplayName(normalizedQuery)` for the actual search.
5. Returns up to 20 results.
6. Automatically disposes when the screen is unmounted (autoDispose).

**Callers**:
- `SearchUsersScreen` — passes raw input, provider normalizes internally.

---

## Presentation Layer: Search UI

### SearchUsersScreen

**Module**: `lib/features/feed/presentation/search_users_screen.dart`

**Type**: `ConsumerStatefulWidget`

**Route**: Nested under `/feed` shell route at path `search` → `/feed/search`

**State Machine** (6 states):

| State | Condition | Display |
|-------|-----------|---------|
| **INITIAL** | Query is empty | FeedEmptyState("Buscá usuarios por nombre") |
| **BELOW_MIN** | Query is 1 character | FeedEmptyState("Buscá usuarios por nombre") |
| **LOADING** | Query is 2+ chars, provider is loading | Centered CircularProgressIndicator |
| **DATA** | Provider returns non-empty list | ListView.separated of UserSearchResultTile |
| **EMPTY_RESULTS** | Query is 2+ chars, provider returns [] | FeedEmptyState("Sin resultados para \"$query\"") |
| **ERROR** | Provider returns AsyncError | Centered text "No pudimos buscar usuarios. Intentá de nuevo." |

**UI Components**:
- **Header**: Back arrow + title "BUSCAR USUARIOS"
- **Search Field**: TextField with placeholder "Buscar por nombre" + inline clear (X) button (visible when non-empty)
- **Results Area**: State-dependent rendering per table above
- **Separators**: 8px between tiles (ListView.separated)

**Behavior**:
- Input is debounced 300ms before triggering search.
- Pressing clear (X) resets field and returns to INITIAL state.
- Pressing back arrow pops the screen.
- Tapping a tile calls `context.push('/feed/profile/$uid')`.

**Styling**:
- All colors via `AppPalette.of(context)`.
- All icons via `TreinoIcon.X`.
- Spacing uses 8 / 12 / 14 / 18 / 20 px scale.
- Loading spinner uses `palette.accent` color.
- Text content in Spanish (Rioplatense Spanish per project conventions).

### UserSearchResultTile

**Module**: `lib/features/feed/presentation/widgets/user_search_result_tile.dart`

**Type**: `StatelessWidget`

**Input**: `UserPublicProfile` + local `gymName` (resolved via helper function)

**Layout**:
- **Avatar** (32px): PostAvatar widget with user's avatarUrl
- **Name** (primary text): displayName (or empty/placeholder if null)
- **Gym** (secondary text): gymNameFromId result (or empty if gymId is null)
- **Tap Region**: Entire tile is tappable

**Behavior**:
- On tap: `context.push('/feed/profile/$profile.uid')`
- NO follow button (friendship state machine belongs on the profile screen, not in search results)

**Styling**:
- Colors via `AppPalette.of(context)`.
- Icons via `TreinoIcon.X`.
- 8/12/14/18/20 px spacing scale.

---

## Integration: Feed Layer

### _FeedHeader Search Icon

**File**: `lib/features/feed/feed_screen.dart`

**Change**: Wrapped search icon in `GestureDetector` that calls `context.push('/feed/search')`.

**Behavior**: Tapping search icon navigates to SearchUsersScreen.

### Router Registration

**File**: `lib/app/router.dart`

**Addition**:
```dart
GoRoute(
  path: 'search',
  pageBuilder: (context, state) => const NoTransitionPage(
    child: SearchUsersScreen(),
  ),
),
```

**Nesting**: Registered under the `/feed` `ShellRoute` so SearchUsersScreen appears within the same shell (with consistent app bar, bottom nav, etc.).

---

## Integration: Profile Layer

### publicProfileViewProvider Refactor

**File**: `lib/features/feed/application/public_profile_providers.dart`

**Change**: Source swap from `firstPostByAuthorProvider` to `userPublicProfileProvider(targetUid)`.

**Old Code**:
```dart
final firstPost = await ref.watch(firstPostByAuthorProvider(targetUid).future);
return PublicProfileView(
  authorDisplayName: firstPost?.author ?? 'Anónimo',
  ...
);
```

**New Code**:
```dart
final publicProfile = await ref.watch(userPublicProfileProvider(targetUid).future);
return PublicProfileView(
  authorDisplayName: publicProfile?.displayName ?? 'Anónimo',
  authorAvatarUrl: publicProfile?.avatarUrl,
  authorGymId: publicProfile?.gymId,
  ...
);
```

**Invariant**: `PublicProfileView` shape is unchanged; only the source of name/avatar/gym fields changes. Existing downstream consumers (profile screens, post tiles) are unaffected.

**firstPostByAuthorProvider**: Remains in the file; its existing scenarios (SCENARIO-200..202) are unchanged and remain green. Future consumers may exist.

---

## Data Consistency: WriteBatch Dual-Write Contract

### Pattern

Whenever user identity (displayName, avatarUrl, gymId) is modified, both `users/{uid}` and `userPublicProfiles/{uid}` are written in the same `WriteBatch.commit()` to ensure atomicity.

### Sites of Dual-Write

#### 1. UserRepository.getOrCreate()

**Trigger**: New user sign-up
**Pattern**:
```
WriteBatch {
  batch.set(users/{uid}, {...private fields...})
  batch.set(userPublicProfiles/{uid}, {uid, displayName?, displayNameLowercase?, avatarUrl?, gymId?})
  await batch.commit()
}
```

#### 2. UserRepository.createIfAbsent()

**Trigger**: Lazy user creation
**Pattern**: Same as getOrCreate.

#### 3. UserRepository.update()

**Trigger**: User edits profile
**Pattern**:
```
if (partial contains displayName || avatarUrl || gymId) {
  WriteBatch {
    batch.update(users/{uid}, private-only subset)
    batch.set(userPublicProfiles/{uid}, {uid, displayName?, ..., displayNameLowercase?}, merge: true)
    await batch.commit()
  }
} else {
  // Update only users/{uid}
  batch.update(users/{uid}, partial)
}
```

#### 4. ProfileSetupNotifier.submit()

**Trigger**: Profile setup wizard completion
**Pattern**: Calls `UserRepository.update()` → dual-write inherited from site 3 above.

### Invariants

- `displayNameLowercase` is ALWAYS derived (never user-provided).
- Public subset is a strict 5-field mask; no private fields leak.
- Both documents are created/updated in a single batch commit (zero window for partial state).
- Rollback of dual-write is atomic: either both docs commit or neither commits.

### Migration Strategy

**Lazy Migration** (MVP): Only users who sign-in after PR #40 merges get `userPublicProfiles/{uid}` created. Existing users remain invisible in search until their next sign-in (when UserRepository.update is called).

**Backfill Script** (optional, ops-triggered): `scripts/backfill_user_public_profiles.js` is committed and documented but NOT executed in the SDD cycle. Ops may execute it later to make existing users immediately visible in search.

---

## Quality and Testing

### Test Coverage

| Layer | Module | Scenarios | Fixture Type |
|-------|--------|-----------|--------------|
| Model | UserPublicProfile | SCENARIO-252..253 (serialization, derivation) | Unit (no mocks) |
| Repository | UserPublicProfileRepository | SCENARIO-254..258 (CRUD, search, bounds) | Unit (fake_cloud_firestore) |
| Provider | userPublicProfileProvider | SCENARIO-254..258 inherited; auth-gate verified | Unit (ProviderContainer) |
| Provider | searchUsersProvider | SCENARIO-275..280 (normalization, delegation) | Unit |
| Tile | UserSearchResultTile | SCENARIO-281..285 (render, tap) | Widget |
| Screen | SearchUsersScreen | SCENARIO-286..295 (state machine, debounce, clear) | Widget |
| Integration | publicProfileViewProvider refactor | SCENARIO-271..274 (provider swap, fallback, old scenarios) | Widget/Provider |
| Rules | firestore.rules | SCENARIO-268..270 (auth != null read, uid-keyed write) | Manual T35 emulator test (DEFERRED pre-merge) |

### Quality Gates

| Gate | Result |
|------|--------|
| `flutter analyze` | 0 issues |
| `dart format` | 0 changed files |
| `flutter test` | 733 passing (46 new tests for this layer) |
| Code pattern checks | 0 forbidden references (PhosphorIcons, hex colors, UserProfile type leaks) |
| Manual rules test (T35) | DEFERRED (pre-merge for PR #40 reviewer) |

### Strict TDD Discipline

All new test files committed to git history BEFORE their corresponding production files. Commit order enforced:
1. RED test commit
2. GREEN production commit
3. REFACTOR / cleanup commit (if needed)

---

## Cross-Layer Dependencies

### Upstream Dependencies

- `feed-data-layer.md`: Post creation logic reads `users/{uid}` to determine post.authorGymId (unchanged; pre-existing)
- `profile-layer.md`: User profile storage (users/{uid} private collection) provides the source data
- `friendship-layer.md` (implicit): Friendship rules (userPublicProfiles/{uid} read is open to any authenticated user)

### Downstream Dependents

- `feed-ui-layer.md`: Post tiles render author names/avatars via `publicProfileViewProvider` (now sourced from userPublicProfiles)
- **Future**: Comments/likes/reactions (Etapa 6) will reference userPublicProfiles for interaction author rendering

---

## Migration and Backward Compatibility

### Lazy Migration

**When**: Every time UserRepository.update is called (e.g., during sign-in, profile edits).

**What**: `userPublicProfiles/{uid}` is created/updated alongside `users/{uid}`.

**Window**: New users (signed-in after PR #40 merge) are visible in search immediately. Existing users become visible only after their next sign-in.

**Risk**: Existing users may be missing from search results until they sign in again. Mitigated by:
1. Empty-state UX copy ("Buscá usuarios por nombre").
2. Backfill script available for ops to manually populate all existing users.

### No Breaking Changes

- `UserProfile` model is unchanged; all downstream code still reads it.
- `publicProfileViewProvider` is unchanged in signature; only source swaps internally.
- Firestore rules on `users/{uid}` are unchanged (owner-only read).
- `firstPostByAuthorProvider` remains available for future consumers.

---

## Lessons Learned (Design Standards)

### 1. Rules Audit Section (Now Mandatory)

Every SDD that touches Firestore MUST include a "Rules Audit" section (design.md Section C) listing:
- Each query (caller + operation)
- The rule that grants it
- Explicit verdict (PASS / GAP)
- Mitigation for any gaps (new rules block)

This caught 3 gaps in the initial design (userPublicProfiles/{uid} read/list/write) before code was written.

### 2. Field Privacy Classification (Now Mandatory)

Any SDD adding model fields MUST classify each as private | public-soft | public (design.md Section D). This prevents schema creep and forces explicit privacy decisions at design time.

### 3. Sidecar Fixes (Formalized Process)

If a pre-existing bug is discovered and fixed during own feature smoke test:
1. Document it explicitly in apply-progress (section "Sidecar Fixes").
2. Add test scenario for it (e.g., SCENARIO-271 for friendship rule fix).
3. List it in PR description before requesting review.

This surfaces sidecar changes to reviewers instead of hiding them.

---

## Related Artifacts

| Artifact | Path / Topic Key | Purpose |
|----------|------------------|---------|
| Proposal | sdd/user-public-profiles/proposal | Original 10 questions + Option B.2 locked decision |
| Spec | sdd/user-public-profiles/spec | 46 REQ + 46 SCENARIO (252..297) |
| Design | sdd/user-public-profiles/design | 12 ADRs + Rules Audit (Section C) + Field Classification (Section D) |
| Tasks | sdd/user-public-profiles/tasks | 37+ work units across PR#A (A1..A10) and PR#B (B1..B9) |
| Apply Progress | sdd/user-public-profiles/apply-progress | TDD evidence for both PRs; deviations documented |
| Archive Report | sdd/user-public-profiles/archive-report | This layer spec summary + lessons + follow-ups |

---

## Roadmap

### Completed (Etapa 5)

- ✅ UserPublicProfile collection + dual-write contract (PR #40)
- ✅ SearchUsersScreen + provider (PR #44)
- ✅ publicProfileViewProvider refactor (PR #40)
- ✅ Rules Audit and Field Privacy Classification (design standards)

### Deferred (Future)

- ⏳ T35-style manual rules test (pre-merge gate; user must run before PR #40 review)
- ⏳ Backfill script execution (ops decision; optional for existing users)
- ⏳ Rules CI automation (integration with Firestore Rules Testing library)
- ⏳ "Load more" pagination (future enhancement; current 20-result limit intentional)
- ⏳ UX consolidation for SEGUIR vs SOLICITUD-ENVIADA (separate SDD)

### Blocked

- (none)

---

**Specification maintained by**: Dev C
**Last updated**: 2026-05-19
**Status**: ARCHIVED (both PRs merged, cycle complete)

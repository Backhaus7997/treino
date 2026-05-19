# Exploration: user-public-profiles

## Goal

Introduce a `userPublicProfiles` Firestore collection to enable authenticated user discovery (search) and public profile rendering without exposing the owner-only `users/{uid}` collection.

## Context

### The Bug That Led Here

The deprecated branch `wip/feed-search-users-deprecated` implemented search against `users/{uid}` using `displayNameLowercase` prefix-range queries. The Firestore rule `allow read: if request.auth != null && request.auth.uid == uid` is owner-only — a user cannot read another user's doc. `fake_cloud_firestore` (used in tests) does NOT enforce Firestore security rules, so all 639 tests passed green, but the smoke test on a real simulator failed with `permission-denied` at runtime.

### Decision: Option B.2

After evaluating four options, the team chose **Option B.2**: create a dedicated `userPublicProfiles` collection containing only the fields that are safe to expose publicly (`uid`, `displayName`, `displayNameLowercase`, `avatarUrl`, `gymId`). The rule on this collection is `allow read: if request.auth != null` (any authenticated user can read/list), resolving the permission-denied bug at the architecture level rather than by widening the sensitive `users/{uid}` rule.

---

## Current State Mapping

### How Etapa 4 Gets User Data (the Workaround)

`publicProfileViewProvider` in `lib/features/feed/application/public_profile_providers.dart` fetches the **most recent post** by `targetUid` (`firstPostByAuthorProvider`), then pulls `authorDisplayName`, `authorAvatarUrl`, and `authorGymId` from that post's denormalized fields. This works because `posts` are readable by any authenticated user (`allow read: if request.auth != null`). The fallback is the string `'Anónimo'` when the user has zero posts.

Problems with the workaround:
- Users who have never posted appear as "Anónimo" — a factual misrepresentation once they complete `ProfileSetup`.
- The query requires at least one post document to be present; it's a side-effect of a separate collection.
- Semantic mismatch: a "Post" document is not the canonical source of identity data.

### How the Deprecated Branch Attempted Search (Failed Approach)

The deprecated branch added `displayNameLowercase` to `UserProfile` and queried `users` collection with a prefix range (`>= query`, `<= query + ''`). The `searchByDisplayName` method was in `UserRepository` and returned `List<UserProfile>`. This exposed private fields (`email`, `bodyWeightKg`, `heightCm`, `gender`, `role`) to any authenticated user in the search result set — a privacy violation — and failed at runtime due to the owner-only read rule.

### Reusables From the Deprecated Branch

The following pieces from `wip/feed-search-users-deprecated` can be cherry-picked at ~60-70% reuse rate (all need adapting from `UserProfile` → `UserPublicProfile`):

| Component | Reuse % | Required Adaptation |
|---|---|---|
| `SearchUsersScreen` widget | ~80% | Remove `UserProfile`-specific fields; use `UserPublicProfile` |
| `UserSearchResultTile` widget | ~90% | Swap model type; keep `PostAvatar` + displayName + gymName layout |
| Search `FutureProvider.family` (debounce + 2-char gate) | ~70% | Change return type; point to new repo method |
| Router wire (`/feed/search` route) | ~100% | Direct copy |
| Feed header search-icon → `context.push('/feed/search')` | ~100% | Direct copy |

Note: `displayNameLowercase` field on `UserProfile` (REQ-FSU-008 from deprecated spec) does NOT go on `UserProfile` in this implementation — it lives only on `UserPublicProfile`. The `UserProfile` model stays untouched.

---

## Affected Components

### Foundation Layer (PR#A)

| File | Action | Rationale |
|---|---|---|
| `lib/features/profile/domain/user_public_profile.dart` | CREATE | New Freezed model: `{uid, displayName, displayNameLowercase, avatarUrl, gymId}` |
| `lib/features/profile/domain/user_public_profile.freezed.dart` | GENERATE | build_runner output |
| `lib/features/profile/domain/user_public_profile.g.dart` | GENERATE | json_serializable output |
| `lib/features/profile/data/user_public_profile_repository.dart` | CREATE | `get(uid)`, `set(profile)`, `searchByDisplayName(query)` — targets `userPublicProfiles` collection |
| `lib/features/profile/application/user_public_profile_providers.dart` | CREATE | `userPublicProfileRepositoryProvider`, `userPublicProfileProvider(uid)` |
| `lib/features/profile/data/user_repository.dart` | MODIFY | Dual-write via WriteBatch: `getOrCreate`, `createIfAbsent`, `update` (when displayName changes) all sync to `userPublicProfiles` |
| `lib/features/profile_setup/application/profile_setup_notifier.dart` | MODIFY | `submit()` syncs to `userPublicProfiles` after writing to `users/{uid}` |
| `firestore.rules` | MODIFY | Add `userPublicProfiles/{uid}` block: `read/list: auth != null`, `write: auth.uid == uid` |
| `lib/features/feed/application/public_profile_providers.dart` | MODIFY | Replace `firstPostByAuthorProvider` usage with `userPublicProfileProvider(uid)` in `publicProfileViewProvider` |
| `lib/features/feed/domain/public_profile_view.dart` | POSSIBLY MODIFY | Field rename deferred to cleanup PR; map in provider instead |
| `test/features/profile/data/user_repository_test.dart` | MODIFY | Add scenarios for dual-write: getOrCreate, createIfAbsent, update with displayName all verify `userPublicProfiles` doc exists |
| `test/features/profile/data/user_public_profile_repository_test.dart` | CREATE | searchByDisplayName prefix query tests, get/set tests |
| `test/features/profile/application/user_public_profile_providers_test.dart` | CREATE | Provider tests |
| `test/features/feed/application/public_profile_providers_test.dart` | MODIFY | SCENARIO-203..205 fixtures change from `posts` docs to `userPublicProfiles` docs |

### Search UI (PR#B)

| File | Action | Rationale |
|---|---|---|
| `lib/features/feed/presentation/search_users_screen.dart` | CREATE (cherry-pick + adapt) | Screen from deprecated branch; adapt to `UserPublicProfile` |
| `lib/features/feed/presentation/widgets/user_search_result_tile.dart` | CREATE (cherry-pick + adapt) | Tile from deprecated branch; adapt model type |
| `lib/features/feed/application/search_users_provider.dart` | CREATE | `FutureProvider.family<List<UserPublicProfile>, String>` |
| `lib/features/feed/feed_screen.dart` | MODIFY | Wire search icon → `context.push('/feed/search')` (cherry-pick) |
| `lib/app/router.dart` | MODIFY | Add `GoRoute(path: 'search', ...)` under `/feed` |
| `test/features/feed/presentation/search_users_screen_test.dart` | CREATE | SCENARIO-234..251 adapted for `UserPublicProfile` result type |
| `test/features/feed/application/search_users_provider_test.dart` | CREATE | Provider tests against `userPublicProfiles` collection |

---

## Field Selection: Public vs Private

Current `UserProfile` fields and their disposition:

| Field | Type | Privacy | Goes to UserPublicProfile? | Rationale |
|---|---|---|---|---|
| `uid` | `String` | Required for identity | YES | Document ID + query target |
| `email` | `String` | PRIVATE | NO | PII — never expose |
| `displayName` | `String?` | Public identity | YES | Core display + search |
| `displayNameLowercase` | (not on UserProfile) | Search index | YES (only here) | Prefix range query |
| `role` | `UserRole` | PRIVATE | NO | Not relevant to discovery |
| `createdAt` | `DateTime` | PRIVATE | NO | Audit field |
| `updatedAt` | `DateTime` | PRIVATE | NO | Audit field |
| `gymId` | `String?` | Soft-public | YES | Shown on public profile + search tile |
| `bodyWeightKg` | `double?` | PRIVATE | NO | Health data |
| `heightCm` | `int?` | PRIVATE | NO | Health data |
| `gender` | `Gender?` | PRIVATE | NO | Sensitive |
| `experienceLevel` | `ExperienceLevel?` | Optional future | NO (for now) | Not in current UI |
| `avatarUrl` | `String?` | Public identity | YES | Shown on public profile + search tile |
| `bornAt` | `DateTime?` | PRIVATE | NO | PII |

**Proposed `UserPublicProfile` shape**: `{uid, displayName, displayNameLowercase, avatarUrl, gymId}` (all fields nullable except `uid`).

---

## Sync Strategy

**Recommendation: Option A — Client-side WriteBatch (atomic dual-write in UserRepository)**

| Approach | Privacy | Latency | Cost | Complexity | Failure Mode |
|---|---|---|---|---|---|
| A: Client WriteBatch | Low risk | Negligible overhead | 2x writes | LOW | Batch atomicity — both or neither |
| B: Cloud Function | Best | Eventual (seconds lag) | CF invocations | HIGH | CF failures opaque; retry logic needed |
| C: Hybrid (batch + CF) | Best | Immediate + backstop | Highest | HIGHEST | Two systems to maintain |

Using `WriteBatch` makes both `users/{uid}` and `userPublicProfiles/{uid}` writes atomic. If the batch fails, neither collection is written — no partial state.

---

## Migration Strategy

**Recommendation: Lazy migration via `getOrCreate`/`createIfAbsent` + `update` sync. Backfill script documented but not executed.**

- `getOrCreate` and `createIfAbsent` write `userPublicProfiles` doc on sign-in → existing users self-heal on next login.
- `update` syncs whenever displayName/avatarUrl/gymId changes.
- Users who never sign in again remain invisible in search — accepted MVP tradeoff.
- Backfill script (Admin SDK, Node.js) is documented as an ops option for post-MVP cleanup.

---

## Etapa 4 Refactor Scope

**Before:**
`publicProfileViewProvider` → `firstPostByAuthorProvider` (reads `posts` collection, returns `Post?`, pulls author fields from denormalized post data). Fallback: 'Anónimo'.

**After:**
`publicProfileViewProvider` → `userPublicProfileProvider(uid)` (reads `userPublicProfiles` single doc). Fallback when doc absent: 'Anónimo' (migration gap window).

Field mapping in the provider (no `PublicProfileView` rename in PR#A):
- `PublicProfileView.authorDisplayName ← userPublicProfile?.displayName ?? 'Anónimo'`
- `PublicProfileView.authorAvatarUrl ← userPublicProfile?.avatarUrl`
- `PublicProfileView.authorGymId ← userPublicProfile?.gymId`

Test impact:
- SCENARIO-200..202 (`firstPostByAuthorProvider` tests): preserved unchanged if `firstPostByAuthorProvider` stays in the file.
- SCENARIO-203..205 (`publicProfileViewProvider` tests): fixtures change from seeding `posts` to seeding `userPublicProfiles`. SCENARIO-204 ("no posts → Anónimo") becomes "no `userPublicProfile` doc → Anónimo" — same assertion, different setup.

---

## Firestore Rules Design

```
match /userPublicProfiles/{uid} {
  // Any authenticated user may read single docs or run prefix-range list queries.
  allow read: if request.auth != null;

  // Only the profile owner may write their own public profile.
  allow write: if request.auth != null
               && request.auth.uid == uid;
}
```

Privacy audit: `email`, `bodyWeightKg`, `heightCm`, `gender`, `bornAt`, `role` are NOT fields on `UserPublicProfile` — they cannot leak. `displayName`, `avatarUrl`, `gymId` are intentionally public (same data already visible via `PostCard` denormalization). `displayNameLowercase` is a search index field, not sensitive.

---

## PR Split Analysis

### PR#A — Foundation + Etapa 4 Refactor
Estimated: ~220 prod LOC + ~270 test LOC = **~490 total LOC**. Within budget.

Files touched: ~9 (2 new domain files + 2 new repo/provider + 5 modifications).

### PR#B — Search UI
Estimated: ~245 prod LOC + ~360 test LOC = **~605 total LOC**. Within budget.

Files touched: ~7 (3 new + 2 modify + 2 test).

---

## Failure Modes

1. **Partial dual-write state** → mitigated by `WriteBatch` atomicity (both collections or neither).
2. **Migration gap (existing users invisible in search)** → mitigated by lazy sync on sign-in + documented backfill script.
3. **Etapa 4 tests break on refactor** → SCENARIO-203..205 fixtures must be rewritten before touching the provider (strict TDD gate).
4. **Cherry-pick from deprecated branch introduces stale model imports** (`UserProfile` instead of `UserPublicProfile`) → design doc adaptation checklist + PR review gate.
5. **`UserPublicProfile.displayName` is null before ProfileSetup** → `searchByDisplayName` prefix query naturally skips null `displayNameLowercase` values (empty-prefix range won't match null).
6. **Firestore index for `userPublicProfiles`** → single-field queries are auto-indexed; no composite index needed for basic prefix range. Must verify in smoke test.
7. **`PostRepository.create()` still reads `users/{uid}` for gymId** → this is an owner-read (author reads their own doc), no permission issue. Optimization (read from `userPublicProfiles` instead) is out of scope.

---

## Open Questions for sdd-propose

1. **WriteBatch vs sequential write**: Lock in `WriteBatch` for UserRepository dual-write atomicity?
2. **`PublicProfileView` field rename**: Rename `authorDisplayName/Url/GymId` → `displayName/Url/GymId` in PR#A (cascades to presentation) or defer to cleanup PR?
3. **`firstPostByAuthorProvider` fate**: Keep file (preserve SCENARIO-200..202 tests) or delete with migrated test scenarios?
4. **`displayNameLowercase` null policy**: Explicit Firestore `!= null` filter or rely on prefix query behavior?
5. **`userPublicProfiles` as top-level vs sub-collection**: Lock in top-level (required for collection-group list queries).
6. **Backfill script scope**: In-scope for documentation in PR#A or strictly out of scope?
7. **`ProfileSetupNotifier.submit()` batch timing**: Batch both writes together or write `users/{uid}` first then `userPublicProfiles`?
8. **`userPublicProfileProvider(uid)` stream vs future**: `StreamProvider` (real-time updates) or `FutureProvider` (matches current `publicProfileViewProvider`)? StreamProvider is architecturally superior but requires refactoring `publicProfileViewProvider` from `FutureProvider.family` to `StreamProvider.family`.
9. **Search result limit**: Confirm 20-result limit from deprecated spec carries over.
10. **Gym divergence post-update**: If user updates gym, `userPublicProfiles.gymId` updates but existing posts still carry old `authorGymId`. Stale-on-update accepted? Needs explicit ADR.

---

## Out of Scope

- Cloud Functions setup (sync strategy is client-side WriteBatch)
- Backfill script execution (documented, not run)
- MI GYM index bug (separate follow-up PR)
- T35 manual Firestore rules test (separate follow-up)
- `PublicProfileView` field rename cleanup (`authorDisplayName` → `displayName`)
- Replacing `PostRepository.create()` gymId source from `users/{uid}` to `userPublicProfiles/{uid}`

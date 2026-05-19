# Design: user-public-profiles

**Phase**: sdd-design
**Change**: user-public-profiles
**Branch (PR#A)**: `feat/user-public-profiles`
**Branch (PR#B)**: `feat/user-public-profiles-search`
**Predecessor**: [proposal.md](./proposal.md) (engram `sdd/user-public-profiles/proposal`, #56)
**Strategy**: Chained PRs, both target `main`. PR#B rebases after PR#A merges.

---

## Executive Summary

PR#A introduces `userPublicProfiles` as a dedicated public-identity collection and refactors Etapa 4's `publicProfileViewProvider` to read from it. PR#B cherry-picks the search UI from the deprecated branch and re-targets it at the new collection. Each Firestore mutation that touches user identity is upgraded to an atomic `WriteBatch` so `users/{uid}` and `userPublicProfiles/{uid}` stay in lockstep. The design is locked behind a mandatory **Rules Audit** (Section C) and **Field Privacy Classification** (Section D) — both added in direct response to the deprecated branch's runtime `permission-denied`.

---

## Section A — Foundation + Etapa 4 Refactor (PR#A)

### A.1 File map

#### CREATE

| Path | Reason |
|---|---|
| `lib/features/profile/domain/user_public_profile.dart` | Freezed model for the public-identity collection (5 fields). |
| `lib/features/profile/domain/user_public_profile.freezed.dart` | `build_runner` output (do not hand-edit). |
| `lib/features/profile/domain/user_public_profile.g.dart` | `json_serializable` output (do not hand-edit). |
| `lib/features/profile/data/user_public_profile_repository.dart` | `get`, `set`, `searchByDisplayName` against `userPublicProfiles`. |
| `lib/features/profile/application/user_public_profile_providers.dart` | `userPublicProfileRepositoryProvider` + `userPublicProfileProvider(uid)` family. |
| `scripts/backfill_user_public_profiles.js` | Documented Node.js Admin SDK script. NOT executed in PR#A. |
| `test/features/profile/data/user_public_profile_repository_test.dart` | Repo tests against `fake_cloud_firestore`. |
| `test/features/profile/application/user_public_profile_providers_test.dart` | Provider tests against `ProviderContainer`. |

#### MODIFY

| Path | Reason |
|---|---|
| `lib/features/profile/data/user_repository.dart` | Dual-write via `WriteBatch` in `getOrCreate`, `createIfAbsent`, `update`. |
| `lib/features/profile_setup/application/profile_setup_notifier.dart` | `submit()` switches from `userRepository.update(...)` to a single `WriteBatch.commit()`. |
| `lib/features/feed/application/public_profile_providers.dart` | `publicProfileViewProvider` swaps `firstPostByAuthorProvider` for `userPublicProfileProvider(uid)`. `firstPostByAuthorProvider` stays. |
| `firestore.rules` | Add new `userPublicProfiles/{uid}` block (read auth, write owner-only). |
| `test/features/profile/data/user_repository_test.dart` | Add dual-write scenarios for `getOrCreate`, `createIfAbsent`, `update`. |
| `test/features/feed/application/public_profile_providers_test.dart` | SCENARIO-203..205 fixtures move from seeding `posts` to seeding `userPublicProfiles`. SCENARIO-200..202 unchanged. |

#### EXPLICITLY NOT MODIFIED IN PR#A

- `lib/features/profile/domain/user_profile.dart` (private model untouched — proposal §"Out of Scope").
- `lib/features/feed/domain/public_profile_view.dart` (field rename deferred — ADR-UPP-7).
- `lib/features/feed/data/post_repository.dart` (gym-source change out of scope — ADR-UPP-12).

### A.2 API signatures

#### A.2.1 `UserPublicProfile` (Freezed model)

```dart
@freezed
class UserPublicProfile with _$UserPublicProfile {
  const factory UserPublicProfile({
    required String uid,
    String? displayName,
    String? displayNameLowercase,
    String? avatarUrl,
    String? gymId,
  }) = _UserPublicProfile;

  factory UserPublicProfile.fromJson(Map<String, Object?> json) =>
      _$UserPublicProfileFromJson(json);
}
```

Notes:
- Only `uid` is required — every other field is nullable to support pre-`ProfileSetup` users.
- No `createdAt`/`updatedAt` — audit lives only in the private `users/{uid}` doc (ADR-UPP-1).
- No `TimestampConverter` needed (no DateTime fields).

#### A.2.2 `UserPublicProfileRepository`

```dart
class UserPublicProfileRepository {
  UserPublicProfileRepository({required FirebaseFirestore firestore})
      : _profiles = firestore.collection('userPublicProfiles');

  final CollectionReference<Map<String, Object?>> _profiles;

  Future<UserPublicProfile?> get(String uid);
  Future<void> set(UserPublicProfile profile);
  Future<List<UserPublicProfile>> searchByDisplayName(
    String query, {
    int limit = 20,
  });
}
```

`set` uses `SetOptions(merge: true)` so partial updates from `UserRepository.update` (which only carries the changed fields) do not erase unrelated fields.

`searchByDisplayName` performs a single-collection prefix range over `displayNameLowercase`. Null-valued docs are naturally excluded by the range filter (Q4 in proposal; ADR-UPP-11).

#### A.2.3 Riverpod providers

```dart
// lib/features/profile/application/user_public_profile_providers.dart
final userPublicProfileRepositoryProvider =
    Provider<UserPublicProfileRepository>(
  (ref) => UserPublicProfileRepository(firestore: ref.watch(firestoreProvider)),
);

final userPublicProfileProvider =
    FutureProvider.family<UserPublicProfile?, String>((ref, uid) async {
  final auth = await ref.watch(authStateChangesProvider.future);
  if (auth == null) return null;
  return ref.watch(userPublicProfileRepositoryProvider).get(uid);
});
```

Auth-gated to match the defensive pattern in `firstPostByAuthorProvider` and `publicProfileViewProvider`.

#### A.2.4 `UserRepository` — before / after

**Before** (`getOrCreate`):
```dart
final profile = UserProfile(uid: uid, email: email, displayName: null, ...);
await _users.doc(uid).set(profile.toJson());
return profile;
```

**After** (`getOrCreate`):
```dart
final profile = UserProfile(uid: uid, email: email, displayName: null, ...);
final batch = _firestore.batch();
batch.set(_users.doc(uid), profile.toJson());
batch.set(
  _userPublicProfiles.doc(uid),
  _publicSubsetFromProfile(profile),
  SetOptions(merge: true),
);
await batch.commit();
return profile;
```

`createIfAbsent` follows the same pattern with `SetOptions(merge: true)` on both writes.

**Before** (`update`):
```dart
final sanitized = ...;
sanitized['updatedAt'] = Timestamp.fromDate(DateTime.now().toUtc());
await _users.doc(uid).set(sanitized, SetOptions(merge: true));
```

**After** (`update`):
```dart
final sanitized = ...;
sanitized['updatedAt'] = Timestamp.fromDate(DateTime.now().toUtc());

final batch = _firestore.batch();
batch.set(_users.doc(uid), sanitized, SetOptions(merge: true));

final publicPartial = _publicSubsetFromPartial(sanitized); // {} when nothing public changed
if (publicPartial.isNotEmpty) {
  publicPartial['uid'] = uid; // re-assert identity
  batch.set(
    _userPublicProfiles.doc(uid),
    publicPartial,
    SetOptions(merge: true),
  );
}
await batch.commit();
```

`_publicSubsetFromProfile` and `_publicSubsetFromPartial` are private helpers (one-line implementations) that pick out `{displayName, displayNameLowercase, avatarUrl, gymId}` from the source and derive `displayNameLowercase = displayName?.trim().toLowerCase()`. They centralize the public-vs-private boundary (ADR-UPP-11).

`_userPublicProfiles` is a new private getter symmetric to `_users`:
```dart
CollectionReference<Map<String, Object?>> get _userPublicProfiles =>
    _firestore.collection('userPublicProfiles');
```

#### A.2.5 `ProfileSetupNotifier.submit()` — before / after

**Before**:
```dart
final partial = <String, Object?>{ 'displayName': ..., 'gymId': ..., ... };
await ref.read(userRepositoryProvider).update(uid, partial);
```

**After** (no change to `submit` signature — the batching lives inside `UserRepository.update`):
```dart
final partial = <String, Object?>{ 'displayName': ..., 'gymId': ..., ... };
await ref.read(userRepositoryProvider).update(uid, partial);
```

Decision: `ProfileSetup.submit()` does NOT compose its own batch — it delegates to `UserRepository.update`, which already produces a single atomic batch covering both collections. This keeps `submit` simple, keeps the batching contract owned by `UserRepository` (single source of truth), and satisfies Q7 ("single WriteBatch.commit() in ProfileSetupNotifier") at the layer below.

#### A.2.6 `publicProfileViewProvider` — before / after

**Before**:
```dart
final post = await ref.watch(firstPostByAuthorProvider(targetUid).future);
return PublicProfileView(
  authorDisplayName: post?.authorDisplayName ?? 'Anónimo',
  authorAvatarUrl: post?.authorAvatarUrl,
  authorGymId: post?.authorGymId,
  friendship: friendship,
  isSelf: isSelf,
);
```

**After**:
```dart
final publicProfileFuture =
    ref.watch(userPublicProfileProvider(targetUid).future);
final friendshipFuture = isSelf
    ? Future<Friendship?>.value(null)
    : ref.watch(friendshipByPairProvider(
        (viewerUid: viewerUid, targetUid: targetUid),
      ).future);

final publicProfile = await publicProfileFuture;
final friendship = await friendshipFuture;

return PublicProfileView(
  authorDisplayName: publicProfile?.displayName ?? 'Anónimo',
  authorAvatarUrl: publicProfile?.avatarUrl,
  authorGymId: publicProfile?.gymId,
  friendship: friendship,
  isSelf: isSelf,
);
```

`firstPostByAuthorProvider` STAYS in the file (ADR-UPP-6). The only dependency that moves is `publicProfileViewProvider`'s author-data source.

### A.3 WriteBatch dual-write pattern (canonical)

```dart
final batch = _firestore.batch();

// 1) Private doc — full or partial set, owner-only by rules.
batch.set(_users.doc(uid), userDocData, SetOptions(merge: true));

// 2) Public doc — strict 5-field subset, any-auth read by rules.
final publicData = <String, Object?>{
  'uid': uid,                                              // identity assertion
  'displayName': displayName,                              // null pre-ProfileSetup
  'displayNameLowercase': displayName?.trim().toLowerCase(),
  'avatarUrl': avatarUrl,
  'gymId': gymId,
};
batch.set(
  _userPublicProfiles.doc(uid),
  publicData,
  SetOptions(merge: true),
);

await batch.commit(); // atomic: both or neither.
```

Three invariants enforced by this pattern:
1. The public subset NEVER includes `email`, `role`, `bodyWeightKg`, `heightCm`, `gender`, `bornAt`, `createdAt`, `updatedAt`, `experienceLevel` (Section D classification).
2. `displayNameLowercase` is ALWAYS derived from `displayName` — never user-provided (ADR-UPP-11).
3. `uid` is re-asserted in the public doc data so the rule `request.resource.data.uid == uid` is satisfiable.

### A.4 Firestore rules block (exact text to add)

Insert AFTER the `match /users/{uid}` block (between users and exercises):

```
match /userPublicProfiles/{uid} {
  // Any authenticated user may read single docs OR list with prefix range.
  // Rationale: enables user discovery (search) and public profile rendering
  // without exposing the owner-only users/{uid} private doc.
  allow read: if request.auth != null;

  // Create: only the profile owner; doc id must equal authenticated uid;
  // body.uid must equal authenticated uid (defense-in-depth vs identity spoof).
  allow create: if request.auth != null
                && request.auth.uid == uid
                && request.resource.data.uid == uid;

  // Update: only the profile owner; uid identity field is immutable.
  allow update: if request.auth != null
                && request.auth.uid == uid
                && request.resource.data.uid == resource.data.uid;

  // Delete: forbidden from client (account-deletion path is privileged CF).
  allow delete: if false;
}
```

Three rules (read, create, update) — `list` is covered by `read` per Firestore semantics. Audit in Section C.

### A.5 Backfill script — `scripts/backfill_user_public_profiles.js`

Documented-only in PR#A; execution is an ops decision (Q6).

Header comments document:
- Purpose: one-shot Admin SDK migration to populate `userPublicProfiles` for legacy users who do not sign in again post-deploy.
- Prereqs: `firebase-admin` installed, service-account JSON path in env.
- Idempotency: uses `set(..., {merge: true})` — safe to re-run.
- Manual trigger only.

Code structure:
```js
// scripts/backfill_user_public_profiles.js
//
// Lazy migration backstop: re-creates the userPublicProfiles/{uid} doc for
// every existing users/{uid} doc, mapping the 5 public fields. Safe to re-run.
//
// USAGE
//   GOOGLE_APPLICATION_CREDENTIALS=./service-account.json \
//     node scripts/backfill_user_public_profiles.js
//
// SAFETY
//   - Uses SetOptions(merge: true). Idempotent.
//   - Never writes to users/{uid}.
//   - Logs progress every 100 docs; halts on first error for ops review.

const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function main() {
  const snapshot = await db.collection('users').get();
  let count = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const displayName = data.displayName ?? null;
    const publicData = {
      uid: doc.id,
      displayName,
      displayNameLowercase:
        typeof displayName === 'string' ? displayName.trim().toLowerCase() : null,
      avatarUrl: data.avatarUrl ?? null,
      gymId: data.gymId ?? null,
    };
    await db
      .collection('userPublicProfiles')
      .doc(doc.id)
      .set(publicData, { merge: true });
    count += 1;
    if (count % 100 === 0) console.log(`Migrated ${count} docs`);
  }
  console.log(`Done. Migrated ${count} userPublicProfile docs.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
```

### A.6 Test design per REQ

> Convention reminder: `fake_cloud_firestore` does NOT enforce Firestore security rules. Permission-denied behavior is verified by the **manual T35-style rules test** below, not by unit tests.

| REQ family | Layer | Strategy | Fixture |
|---|---|---|---|
| `REQ-UPP-MODEL-*` | model | Plain Dart tests on `UserPublicProfile.fromJson/toJson` | hand-crafted maps |
| `REQ-UPP-REPO-{get,set}` | repo | `fake_cloud_firestore` | seed via `fake.collection('userPublicProfiles').doc(uid).set(...)` |
| `REQ-UPP-REPO-search` | repo | `fake_cloud_firestore` | seed 3-5 docs with varying `displayNameLowercase`; assert prefix range + 20 limit + null-skip |
| `REQ-UPP-PROVIDER-get` | provider | `ProviderContainer` with `firestoreProvider`/`authStateChangesProvider` overrides | `MockFirebaseAuth` + `FakeFirebaseFirestore` |
| `REQ-UPP-DUALWRITE-*` | repo | `fake_cloud_firestore` | call `userRepository.{getOrCreate,createIfAbsent,update}`; assert BOTH collections written; assert public subset matches |
| `REQ-UPP-SUBMIT-dualwrite` | notifier | `ProviderContainer` with `userRepositoryProvider` real + fake firestore | drive `ProfileSetupNotifier.submit()`; assert both docs |
| `REQ-UPP-ETAPA4-*` (SCENARIO-203..205) | provider | `ProviderContainer` | seed `userPublicProfiles/{targetUid}` (NOT `posts`); assert `publicProfileViewProvider` returns expected fields |
| `REQ-UPP-RULES-*` (SCENARIO-268..270) | rules | **Manual T35-style** with Firestore Emulator | see below |

#### Manual Rules Test (T35-style) — MANDATORY pre-merge for PR#A

The deprecated branch's bug was: `fake_cloud_firestore` returned green on 639 tests; real Firestore returned `permission-denied`. To prevent recurrence:

| ID | Setup | Action (as auth user B) | Expected |
|---|---|---|---|
| SCENARIO-268 | Seed `userPublicProfiles/A` via Admin SDK | Read `userPublicProfiles/A` | OK |
| SCENARIO-269 | (same) | Run prefix list `displayNameLowercase >= "j" < "k"` | OK |
| SCENARIO-270 | (same) | Write `userPublicProfiles/A` (B != A) | DENIED |

Procedure:
1. `firebase emulators:start --only firestore,auth`
2. Deploy current `firestore.rules` to emulator
3. Seed test data via Admin SDK script (one-off)
4. Use Firebase JS SDK signed in as user B to attempt the three operations
5. Document results in PR description (screenshot or terminal log)

Cost ~10 minutes. Mandatory before requesting review on PR#A.

### A.7 Etapa 4 refactor migration order (STRICT TDD)

To prevent silent regression of SCENARIO-203..205:

1. **RED** — Rewrite `test/features/feed/application/public_profile_providers_test.dart` SCENARIO-203..205 to seed `userPublicProfiles` (not `posts`). All three should FAIL because `publicProfileViewProvider` still reads from `firstPostByAuthorProvider`.
2. **GREEN** — Modify `publicProfileViewProvider` to depend on `userPublicProfileProvider(uid)` instead. All three should PASS.
3. **REFACTOR** — Verify SCENARIO-200..202 (`firstPostByAuthorProvider` direct tests) remain green.

This order is non-negotiable. Reversing it (GREEN-then-test-rewrite) re-introduces the deprecated branch's failure mode.

---

## Section B — Search UI Design (PR#B)

### B.1 File map

#### CREATE

| Path | Source |
|---|---|
| `lib/features/feed/presentation/search_users_screen.dart` | Cherry-pick from `wip/feed-search-users-deprecated`, then adapt per B.2 |
| `lib/features/feed/presentation/widgets/user_search_result_tile.dart` | Cherry-pick + adapt |
| `lib/features/feed/application/search_users_provider.dart` | Cherry-pick + adapt |
| `test/features/feed/presentation/search_users_screen_test.dart` | Adapt (SCENARIO-234..251) |
| `test/features/feed/application/search_users_provider_test.dart` | Adapt |

#### MODIFY

| Path | Reason |
|---|---|
| `lib/features/feed/feed_screen.dart` | Wire search icon → `context.push('/feed/search')` (cherry-pick) |
| `lib/app/router.dart` | Add `GoRoute(path: 'search', ...)` under `/feed` |

### B.2 Cherry-pick adaptation checklist

For EVERY file copied from `wip/feed-search-users-deprecated`, run this checklist before committing:

| # | Check | Required action |
|---|---|---|
| 1 | `UserProfile` import present | Replace with `UserPublicProfile` import |
| 2 | `userRepositoryProvider.searchByDisplayName` call | Replace with `userPublicProfileRepositoryProvider.searchByDisplayName` |
| 3 | `userRepositoryProvider` import in feed presentation files | Remove (feed must NOT import the private user repo) |
| 4 | Any field access to `bodyWeightKg`, `heightCm`, `gender`, `email`, `role`, `bornAt`, `createdAt`, `updatedAt` | Remove — these fields do NOT exist on `UserPublicProfile` and would be a privacy regression |
| 5 | `result.uid`, `result.displayName`, `result.avatarUrl`, `result.gymId` references | Keep — these fields exist on both models |
| 6 | Test fixtures use `UserProfile(...)` factory | Replace with `UserPublicProfile(uid: ..., displayName: ..., ...)` |
| 7 | Test seeding via `users/...` collection | Change to `userPublicProfiles/...` collection |
| 8 | `displayNameLowercase` field reference | Confirm it lives on `UserPublicProfile` (it does) |

Enforcement gate before opening PR#B: run `rg "UserProfile|userRepositoryProvider|bodyWeightKg|heightCm|\bgender\b|\bemail\b|\brole\b|\bbornAt\b" lib/features/feed/presentation/search_users_screen.dart lib/features/feed/presentation/widgets/user_search_result_tile.dart lib/features/feed/application/search_users_provider.dart` and confirm zero matches that would re-introduce the bug.

### B.3 API signatures

#### B.3.1 `searchUsersProvider`

```dart
final searchUsersProvider =
    FutureProvider.family<List<UserPublicProfile>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.length < 2) return const [];
  // Optional 250ms debounce handled inside the screen via a Timer + setState;
  // this provider performs the actual query without debouncing on its own
  // (Riverpod cache + family already deduplicates identical queries).
  return ref
      .read(userPublicProfileRepositoryProvider)
      .searchByDisplayName(trimmed, limit: 20);
});
```

Two-character gate (ADR-UPP-8 corollary) and 20-result limit (ADR-UPP-8) live in this provider.

#### B.3.2 `SearchUsersScreen`

```dart
class SearchUsersScreen extends ConsumerStatefulWidget {
  const SearchUsersScreen({super.key});
  @override
  ConsumerState<SearchUsersScreen> createState() => _SearchUsersScreenState();
}
```

Local widget state owns the `TextEditingController`, debounce `Timer`, and the current `query` string. The provider is watched via `ref.watch(searchUsersProvider(query))`.

#### B.3.3 `UserSearchResultTile`

```dart
class UserSearchResultTile extends StatelessWidget {
  const UserSearchResultTile({
    super.key,
    required this.profile,
    required this.onTap,
  });

  final UserPublicProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) { ... }
}
```

Layout (per AGENTS.md §6 + design tokens): `PostAvatar` (32-px) + displayName text + gymName subtext, spacing 12. Uses `AppPalette.of(context)`, never HEX literals. No inline follow button (ADR-UPP-10).

### B.4 State machine for `SearchUsersScreen`

```
                  ┌───────────────────────────────────────┐
                  │              INITIAL                   │
                  │ "Buscá usuarios" empty-state copy      │
                  └─────────────┬─────────────────────────┘
                                │ user types
                                ▼
            ┌──────────────────────────────────┐
            │       TYPING_BELOW_MIN           │
            │ query.length < 2                 │
            │ Empty-state: "Escribí 2+ letras" │
            └─────────────┬────────────────────┘
                          │ query.length >= 2
                          ▼
                    ┌──────────────┐
                    │   LOADING    │ (AsyncLoading)
                    │ Spinner      │
                    └──────┬───────┘
                           │
            ┌──────────────┼───────────────┬───────────────┐
            │              │               │               │
            ▼              ▼               ▼               ▼
       ┌─────────┐   ┌─────────┐   ┌──────────────┐  ┌─────────┐
       │  DATA   │   │  EMPTY  │   │ EMPTY_RESULTS│  │  ERROR  │
       │ List of │   │ list==0 │   │ list==0 +    │  │ Async   │
       │ tiles   │   │ AND no  │   │ query !=     │  │ error   │
       │         │   │ search  │   │ previous     │  │ banner  │
       └─────────┘   └─────────┘   └──────────────┘  └─────────┘
```

Note: `EMPTY` and `EMPTY_RESULTS` collapse into a single state in code (just check `query.length >= 2 && list.isEmpty`). The split here is for UX clarity (different copy: "Sin resultados para 'xyz'" vs "Escribí 2+ letras").

### B.5 Test design per REQ-UPS-*

| REQ family | Layer | Strategy |
|---|---|---|
| `REQ-UPS-PROVIDER-gate-2char` | provider | `ProviderContainer`; query="a" → returns `[]` without hitting repo |
| `REQ-UPS-PROVIDER-limit-20` | provider | seed 25 docs; assert returned `.length == 20` |
| `REQ-UPS-PROVIDER-prefix` | provider | seed "Juan", "Julia", "Marco"; query="ju" → 2 results |
| `REQ-UPS-PROVIDER-null-skip` | provider | seed 1 doc with `displayNameLowercase == null`; query="a" → not in results |
| `REQ-UPS-SCREEN-initial` | widget | pump screen; expect "Buscá usuarios" empty-state |
| `REQ-UPS-SCREEN-typing-below-min` | widget | enter "a"; expect "Escribí 2+ letras" |
| `REQ-UPS-SCREEN-loading` | widget | enter "ju"; expect `CircularProgressIndicator` while provider resolves |
| `REQ-UPS-SCREEN-data` | widget | enter "ju" with 2 seeded matches; expect 2 `UserSearchResultTile`s |
| `REQ-UPS-SCREEN-empty-results` | widget | enter "zz" with no matches; expect "Sin resultados" copy |
| `REQ-UPS-SCREEN-error` | widget | override provider with `AsyncError`; expect error banner |
| `REQ-UPS-SCREEN-tap-nav` | widget | tap tile → expect `GoRouter` navigates to `/feed/profile/{uid}` |
| `REQ-UPS-ROUTER-search-route` | router | `goRouter.push('/feed/search')` → assert `SearchUsersScreen` mounted |
| `REQ-UPS-FEED-search-icon` | widget | tap search icon on `FeedScreen` → expect navigation to `/feed/search` |

All widget tests use `ProviderScope(overrides: [...])` with fake providers; no real Firestore.

---

## Section C — Rules Audit (MANDATORY)

> Lesson learned: the deprecated branch passed 639 tests and died at runtime with `permission-denied`. Every Firestore query introduced or modified by this change is enumerated below with its required-vs-current rule. **GAPs are closed by the rules block in A.4.**

| # | Query (collection + filter) | Caller (method) | Required rule | Current rule (`firestore.rules`) | Verdict |
|---|---|---|---|---|---|
| 1 | `users/{uid}` read | `UserRepository.get`, `UserRepository.watch` | `auth.uid == uid` | `auth != null && auth.uid == uid` (line 8-9) | PASS |
| 2 | `users/{uid}` create | `UserRepository.getOrCreate`, `UserRepository.createIfAbsent` | `auth.uid == uid` + role-in-set + uid match | `auth != null && auth.uid == uid && resource.uid == uid && role in [...]` (line 13-16) | PASS |
| 3 | `users/{uid}` update | `UserRepository.update`, `ProfileSetupNotifier.submit` (indirect) | `auth.uid == uid` + immutable fields preserved | `auth != null && auth.uid == uid && uid/role/email/createdAt unchanged` (line 21-30) | PASS |
| 4 | `userPublicProfiles/{uid}` read (single doc) | `UserPublicProfileRepository.get`, `userPublicProfileProvider`, `publicProfileViewProvider` (transitive) | `auth != null` | NONE — collection does not exist in rules yet | **GAP-1 → closed by A.4** |
| 5 | `userPublicProfiles` list with prefix range on `displayNameLowercase` | `UserPublicProfileRepository.searchByDisplayName`, `searchUsersProvider` (PR#B) | `auth != null` (covered by `read`) | NONE — collection does not exist in rules yet | **GAP-2 → closed by A.4** (Firestore `list` is governed by `read`) |
| 6 | `userPublicProfiles/{uid}` create | `UserRepository.getOrCreate`, `UserRepository.createIfAbsent` (batched alongside users write) | `auth.uid == uid` + body uid matches | NONE | **GAP-3 → closed by A.4** |
| 7 | `userPublicProfiles/{uid}` update (merge) | `UserRepository.update`, `ProfileSetupNotifier.submit` (transitive) | `auth.uid == uid` + uid immutable | NONE | **GAP-3 → closed by A.4** (same block) |
| 8 | `posts/{postId}` read (existing) | `firstPostByAuthorProvider` (unchanged) | `auth != null` | `auth != null` (line 53) | PASS |
| 9 | `friendships/{friendshipId}` read (existing) | `friendshipByPairProvider` (unchanged) | `auth.uid in members` | `auth != null && auth.uid in resource.data.members` (line 68-69) | PASS |

**Summary**: 3 GAPs identified (read, create, update for the new collection). All 3 are closed by the single rule block in A.4. The `users/{uid}` rules are NOT widened — that was the architectural choice in Option B.2.

### Special cases verified

- **`PostRepository.create()` reads `users/{uid}.gymId`** (line 22 of `post_repository.dart`): the caller is always the post author reading their OWN doc → satisfied by rule line 8-9 (`auth.uid == uid`). PASS. ADR-UPP-12 captures why we do NOT change this to read from `userPublicProfiles` (out of scope).
- **`WriteBatch` rule evaluation**: each operation in a batch is evaluated independently against rules. The dual-write batch satisfies (Q2 PASS) AND (Q6/Q7 PASS) simultaneously because the caller is always `auth.uid == uid` on both writes.

---

## Section D — Field-level Privacy Classification (MANDATORY)

> Lesson learned: the deprecated branch added `displayNameLowercase` to `UserProfile` without auditing exposure. Every `UserProfile` field is reclassified below.

Legend:
- **private**: never exposable; security/PII risk if leaked.
- **public-soft**: intentionally exposable via a specific feature; documented surface.
- **public**: intentionally public; already visible elsewhere in the product.

| Field | Type | Classification | Rationale | In `UserPublicProfile`? |
|---|---|---|---|---|
| `uid` | `String` | public | Document identity; already visible in `posts.authorUid`, friendships members | YES |
| `email` | `String` | private | PII; authentication identifier | NO |
| `displayName` | `String?` | public | Already visible in PostCard, friend requests, public profile | YES |
| `displayNameLowercase` | (new) | public-soft | Search-index field; not surfaced in UI but readable via list query | YES (only here — NOT on `UserProfile`) |
| `role` | `UserRole` | private | Authorization signal; leaking enables targeted role-escalation probes | NO |
| `createdAt` | `DateTime` | private | Audit field; enables timing-based analytics that should stay internal | NO |
| `updatedAt` | `DateTime` | private | Audit field; same reasoning | NO |
| `gymId` | `String?` | public-soft | Already denormalized into `posts.authorGymId`; visible on PostCard. ADR-UPP-9 captures the staleness tradeoff. | YES |
| `bodyWeightKg` | `double?` | private | Health data; sensitive | NO |
| `heightCm` | `int?` | private | Health data; sensitive | NO |
| `gender` | `Gender?` | private | Sensitive demographic | NO |
| `experienceLevel` | `ExperienceLevel?` | not exposed yet | Future filter target; out of scope this change | NO |
| `avatarUrl` | `String?` | public | Already visible in PostCard, friend requests, public profile | YES |
| `bornAt` | `DateTime?` | private | PII (age computation) | NO |

**Confirmation**: `UserPublicProfile` contains ONLY fields classified as **public** or **public-soft**. No **private** field can leak via the new collection.

**Forward guard**: any future PR adding a field to `UserPublicProfile` must update this table and re-run the rules audit (Section C). This is enforced by the `sdd-design` Firestore-touching trigger captured in the proposal's "Lessons Learned" §3.

---

## Section E — ADRs

### ADR-UPP-1: Separate `userPublicProfiles` collection vs widening `users/{uid}` rules

**Decision**: Create a dedicated collection.

**Context**: The deprecated branch tried to enable cross-user search against `users/{uid}` and failed at runtime with `permission-denied` because the rule is `auth.uid == uid` (owner-only).

**Alternatives considered**:
- Widen `users/{uid}` read rule to `auth != null` → leaks `email`, `bodyWeightKg`, `gender`, etc. (privacy violation, see Section D).
- Field-level rules with `resource.data.keys()` filtering → Firestore rules cannot project documents; the full doc is returned to the client.
- Cloud Function as data broker → high latency, opaque failure modes (Option B in explore).

**Rationale**: A separate collection enforces the public/private boundary at the schema level instead of relying on field-by-field discipline. The 5-field public subset is auditable in one place (Section D).

**Tradeoff accepted**: dual-write cost (2 docs per identity mutation) — mitigated by `WriteBatch` atomicity.

### ADR-UPP-2: `WriteBatch` over sequential writes

**Decision**: Every dual-write goes through `firestore.batch()` → `batch.commit()`.

**Rationale**: Sequential writes (`await users.set(); await publicProfiles.set();`) can fail between the two calls and leave the two collections out of sync — a partial-state bug that's hard to diagnose months later.

**Alternatives considered**:
- Cloud Function trigger on `users/{uid}` write → eventual consistency window; CF cold-start cost; failure logs require a separate observability path.
- Two-phase commit via transaction → unnecessary; `WriteBatch` already provides atomicity for non-read-dependent writes.

**Tradeoff accepted**: batch failure surfaces as one exception (vs two) — caller can retry the whole batch.

### ADR-UPP-3: Client-side sync vs Cloud Function

**Decision**: Client-side `WriteBatch` in `UserRepository`.

**Rationale**: Client batch is atomic, immediate, and free (no CF invocation cost). The team has no CF infrastructure in place; adding it for this single use case is over-engineering. ProGuard against partial state is the rule audit (Section C) + batch semantics (ADR-UPP-2).

**Tradeoff accepted**: a malicious client that bypasses `UserRepository` could write `users/{uid}` without `userPublicProfiles/{uid}` — but rules limit them to their own UID and the public collection is best-effort discoverability, not a security boundary. The privacy boundary is enforced by the public-subset schema, not by the write path.

### ADR-UPP-4: Lazy migration vs proactive backfill

**Decision**: Lazy migration on next sign-in (via `getOrCreate`/`createIfAbsent`) + documented backfill script (NOT executed).

**Rationale**: MVP has a small user base; users who sign in within the migration window self-heal. The cost of an Admin SDK run is operational, not architectural.

**Tradeoff accepted**: legacy users who never sign in again remain invisible in search until ops runs `scripts/backfill_user_public_profiles.js`. Documented in the proposal Success Criteria and the script's header comment.

### ADR-UPP-5: `FutureProvider` over `StreamProvider` for `userPublicProfileProvider`

**Decision**: `FutureProvider.family<UserPublicProfile?, String>`.

**Rationale**: `publicProfileViewProvider` is already `FutureProvider.family`. Using `StreamProvider` would force a cascade refactor of `publicProfileViewProvider` and its widget consumers. The use case (public profile screen render) does not require real-time updates — a user opening another user's profile and seeing them rename in real-time is not a current requirement.

**Tradeoff accepted**: a viewer holding the screen open while the target user renames will see the stale name until they re-open. Acceptable for MVP; can upgrade to `StreamProvider` in a follow-up without breaking the API (Riverpod's `.future` adapter).

### ADR-UPP-6: Keep `firstPostByAuthorProvider` in the file

**Decision**: `firstPostByAuthorProvider` stays in `lib/features/feed/application/public_profile_providers.dart`. Only `publicProfileViewProvider` swaps its data source.

**Rationale**: Q3 in the proposal. The provider may be reused by future features (e.g., "show user's latest post on hover"); SCENARIO-200..202 already cover it. Deleting it would force a test rewrite without a benefit.

**Tradeoff accepted**: one unused-import-style code-smell warning if no consumer remains. Acceptable; `flutter analyze` does not flag unused top-level providers.

### ADR-UPP-7: Defer `PublicProfileView` field rename

**Decision**: Keep `authorDisplayName` / `authorAvatarUrl` / `authorGymId` field names in `PublicProfileView`. Map values in the provider.

**Rationale**: Renaming cascades to every widget that consumes `PublicProfileView` (presentation layer). PR#A is already at the budget ceiling (~490 LOC). The rename is cosmetic — defer to a dedicated cleanup PR (out of scope per proposal).

**Tradeoff accepted**: temporary semantic mismatch ("author" prefix on fields that now come from a profile, not a post). Documented.

### ADR-UPP-8: Search result limit at 20

**Decision**: `searchByDisplayName(query, {int limit = 20})`.

**Rationale**: Carried from the deprecated spec. Twenty fits comfortably in a single Firestore page (default limit is 100), keeps the UI scannable, and leaves room for a "Load more" affordance in a future iteration.

**Tradeoff accepted**: users searching a very common prefix may not see all matches. Acceptable; the search is for discovery, not exhaustive listing.

### ADR-UPP-9: Accept stale-on-update `gymId` in `posts`

**Decision**: When a user updates their gym, `userPublicProfiles/{uid}.gymId` updates but existing `posts.authorGymId` values remain at the old gym.

**Rationale**: `Post.authorGymId` is the author's gym AT THE TIME the post was created (denormalization for `feedForGym` query performance). `UserPublicProfile.gymId` is the author's CURRENT gym. Backfilling all historical posts is a write-amplification disaster and rewrites history.

**Tradeoff accepted**: a user moving gyms sees their old posts attributed to the old gym in MI GYM feed. This is correct: those posts were authored in that gym context.

### ADR-UPP-10: No inline follow button in search tile

**Decision**: `UserSearchResultTile` shows avatar + displayName + gymName only. Tapping navigates to the public profile, where follow/friend actions live.

**Rationale**: Adding a follow button inline requires `friendshipByPairProvider(viewerUid, targetUid)` per tile (N+1 reads). The public profile already has the full friendship state machine.

**Tradeoff accepted**: one extra tap to follow. Acceptable.

### ADR-UPP-11: `displayNameLowercase` is derived, never user-provided

**Decision**: `displayNameLowercase = displayName?.trim().toLowerCase()`, computed in `UserRepository`'s `_publicSubsetFromProfile`/`_publicSubsetFromPartial` helpers. Never accepted from client input or from the `partial` map passed to `UserRepository.update`.

**Rationale**: If callers could provide `displayNameLowercase` independently, the search index could drift from the display name (typos, capitalization bugs, malicious indexing). Centralizing the derivation in one place ensures consistency.

**Tradeoff accepted**: callers cannot set a custom search index. Not a real loss — there's no use case for that.

### ADR-UPP-12: No `PostRepository.create()` refactor

**Decision**: `PostRepository.create()` continues to read `users/{uid}.gymId` for denormalization. Do NOT change it to read from `userPublicProfiles/{uid}`.

**Rationale**: The caller is the post author reading their OWN doc — rule `auth.uid == uid` is satisfied. No permission issue. Changing the source would be a "while we're here" optimization with non-zero risk (test rewrites, behavioral parity verification) for zero benefit.

**Tradeoff accepted**: `PostRepository` retains a read from `users/{uid}`. Acceptable; it's an owner-read.

---

## Engram Persistence

This design is saved to engram at:
- **topic_key**: `sdd/user-public-profiles/design`
- **project**: `treino`
- **type**: `architecture`

File path: `openspec/changes/user-public-profiles/design.md`.

---

## Next Recommended Phase

`sdd-tasks` — once `sdd-spec` artifact is also ready, mechanically break this design into ordered task batches respecting the strict-TDD migration order in A.7 and the cherry-pick checklist in B.2.

# Design: Post + Friendship Data Layer

## Technical Approach

Mirror the Fase 1/2 model+repo+provider pattern (`UserProfile`/`UserRepository`/`userProviders`, `Routine`/`RoutineRepository`/`routineProviders`). All new code lives under `lib/features/feed/`. Freezed models with `@TimestampConverter()`, lowercase-wire enums, concrete repos with `FirebaseFirestore` injection, manual Riverpod providers (no codegen). Friends-privacy stays soft (engram `fase3-friends-privacy-enforcement`).

## Architecture Decisions

### Decision: Denormalize `authorGymId` onto `Post`
**Choice**: Add `String? authorGymId` to `Post`; `PostRepository.create()` reads `users/{uid}.gymId` once before write.
**Alternatives**: Join via `UserProfile` at read time (2 round-trips); query `posts where authorUid in sameGymUids` (requires loading gym roster first — O(N) reads).
**Rationale**: `feedForGym(gymId)` becomes a single `where('privacy','==','gym').where('authorGymId','==',gymId)` query. Same denormalization precedent as `RoutineSlot.exerciseName` (ADR-2). Stale data on gym change is acceptable — gym is slow state, rarely mutates.

### Decision: `Friendship.sortedDocId(a, b)` as static method on the model
**Choice**: `static String sortedDocId(String a, String b) => (a.compareTo(b) <= 0) ? '${a}_$b' : '${b}_$a';` on `Friendship`. Reused by repo, tests, and any future rule-mock seed.
**Alternatives**: Private helper inside `FriendshipRepository`.
**Rationale**: Pure, testable from `friendship_test.dart` without spinning up a repo. Asserts deterministic order in SCENARIO-123.

### Decision: `Friendship.members` ordered lex
**Choice**: `members = [min(uidA,uidB), max(uidA,uidB)]`. `uidA = members[0]`, `uidB = members[1]`.
**Rationale**: Deterministic — tests can assert without sort. `array-contains` query works regardless of order, but ordering keeps the doc canonical.

### Decision: `request()` idempotency returns existing `Friendship`
**Choice**: `FriendshipRepository.request(myUid, otherUid)` reads `friendships/{sortedId}` first; if present, returns the existing `Friendship`. If absent, writes pending and returns the new one.
**Alternatives**: Throw on duplicate; silent no-op returning void.
**Rationale**: Safe-to-call sans pre-check at call sites. SCENARIO-129 already validates no duplicate. Status of returned doc tells caller what state it landed in.

### Decision: `Post.id` from Firestore auto-id
**Choice**: `final ref = _posts.doc(); final post = input.copyWith(id: ref.id); await ref.set(post.toJson());`. Returned `Post.id` is the Firestore-assigned id.
**Alternatives**: Client UUID v4.
**Rationale**: Matches existing pattern (`RoutineRepository` reads `doc.id` from snapshot). No extra dep.

### Decision: Manual Riverpod with `FutureProvider.family<T, String>`
**Choice**: `postRepositoryProvider`, `friendshipRepositoryProvider` (Provider). User-scoped reads as `FutureProvider.family<List<Post>, String>` (uid param) — `feedForFriends`, `feedForGym`, `byAuthor`, `acceptedFriendsOf`, `pendingRequestsFor`. Public feed as plain `FutureProvider<List<Post>>`.
**Rationale**: Follows `routineByIdProvider` family pattern. Repo methods stay pure; providers compose them with `authStateChangesProvider`.

### Decision: Single `build_runner build` after all 5 freezed files exist
**Choice**: Write all 5 model files in TDD order (test-red, model-stub, run codegen once, test-green). `build_runner build --delete-conflicting-outputs` once at end of domain phase.
**Rationale**: Faster (~30 s vs ~30 s × 5). Avoids intermediate broken `.freezed.dart`/`.g.dart` states.

### Decision: Rules tests stay manual via `scripts/test_rules.sh`
**Choice**: New script invokes `firebase emulators:exec` with a small JS suite covering SCENARIO-130, 131, 132. Not wired into CI for this etapa.
**Rationale**: Emulator-on-CI is its own etapa of work. Manual run before merge is enforceable as a PR checklist item. Reconsider in Fase 6.

### Decision: Idempotent seed via deterministic doc IDs
**Choice**: `scripts/seed_posts.js` uses `seed_post_001..010` as doc IDs.
**Rationale**: Matches `seed_workout_catalog.js` convention. Re-runs overwrite, never duplicate.

## Data Flow

    UI (Etapa 2+) ──→ Riverpod provider ──→ Repository ──→ Firestore
                          │                      │
                          └── auth-gated ────────┘
    feedForGym(gymId):  posts where privacy=gym AND authorGymId=gymId  (1 query)
    feedForFriends(friendUids): posts where privacy=friends AND authorUid in friendUids  (1 query, max 10 in clause — split client-side if >10)

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `lib/features/feed/domain/post.dart` | Create | `Post` freezed model (incl. `authorGymId`) |
| `lib/features/feed/domain/post_privacy.dart` | Create | `PostPrivacy` enum + wire map |
| `lib/features/feed/domain/routine_tag.dart` | Create | `RoutineTag` embed (freezed) |
| `lib/features/feed/domain/friendship.dart` | Create | `Friendship` model + `sortedDocId` static |
| `lib/features/feed/domain/friendship_status.dart` | Create | `FriendshipStatus` enum + wire map |
| `lib/features/feed/data/post_repository.dart` | Create | CRUD + 4 feed queries |
| `lib/features/feed/data/friendship_repository.dart` | Create | request/accept/list/delete |
| `lib/features/feed/application/post_providers.dart` | Create | repo + feed providers |
| `lib/features/feed/application/friendship_providers.dart` | Create | repo + family providers |
| `firestore.rules` | Modify | Add `/posts` and `/friendships` blocks |
| `scripts/seed_posts.js` | Create | 6–10 posts mixed privacy |
| `scripts/test_rules.sh` | Create | Manual emulator rules runner |
| `test/features/feed/**` | Create | SCENARIO-112+ |

## Interfaces (load-bearing)

```dart
class Friendship {
  static String sortedDocId(String a, String b) =>
      a.compareTo(b) <= 0 ? '${a}_$b' : '${b}_$a';
}

class PostRepository {
  Future<Post> create(Post input);          // assigns id, reads authorGymId
  Future<List<Post>> byAuthor(String uid);
  Future<List<Post>> feedPublic();
  Future<List<Post>> feedForFriends(List<String> friendUids); // chunks >10
  Future<List<Post>> feedForGym(String gymId);
}

class FriendshipRepository {
  Future<Friendship> request(String myUid, String otherUid); // idempotent
  Future<void> accept(String friendshipId, String myUid);     // throws if requester
  Future<List<String>> acceptedFriendsOf(String uid);
  Future<List<Friendship>> pendingRequestsFor(String uid);
  Future<void> delete(String friendshipId);
}
```

## Testing Strategy

| Layer | What | Approach |
|-------|------|----------|
| Domain | Model round-trip, enum wire, `sortedDocId` order | `flutter_test` pure |
| Data | Repo methods on `FakeFirebaseFirestore` | `fake_cloud_firestore`, seed via direct `.set()` (mirrors `user_repository_test.dart`) |
| Rules | SCENARIO-130/131/132 | `scripts/test_rules.sh` manual |
| Seed | Doc IDs deterministic, 6–10 docs | Run against emulator, assert count |

## Migration / Rollout
No migration. Feature-isolated branch; rollback = `git revert`. Rules redeploy previous version.

## Open Questions
- None. All decisions resolved.

## Risks (inherited)
1. Soft friends-privacy leak via devtools (MVP-accepted, revisit Fase 6).
2. `gym` privacy still requires 2 `get()` per read at rule-eval time (accepted; mitigated by `authorGymId` denorm reducing client cost).
3. Race accept+delete — no transaction, idempotent outcome.
4. `feedForFriends` `in` clause Firestore limit = 10 — repo splits the friend list into chunks and merges results client-side.

# Feed Data Layer — Specification

**Domain**: Social Posts and Friendships
**Change**: `post-friendship-model` (Fase 3 · Etapa 1)
**Status**: ACTIVE (source of truth)
**Last updated**: 2026-05-14
**Merged**: PR #22 (commit 5058cb6)

---

## Purpose

Define the social data layer: models, repositories, Firestore security rules, and seed script for Posts and Friendships. This spec is the authoritative reference for all feed-related backend components. All items in this spec are NEW (no existing spec to delta against).

---

## Requirements

| ID | Name | Strength | Status |
|----|------|----------|--------|
| REQ-PFM-001 | Post model fields | MUST | ✅ IMPLEMENTED |
| REQ-PFM-002 | PostPrivacy enum wire format | MUST | ✅ IMPLEMENTED |
| REQ-PFM-003 | RoutineTag embed | MUST | ✅ IMPLEMENTED |
| REQ-PFM-004 | Friendship model fields | MUST | ✅ IMPLEMENTED |
| REQ-PFM-005 | FriendshipStatus enum wire format | MUST | ✅ IMPLEMENTED |
| REQ-PFM-006 | Friendship doc ID composite sorted | MUST | ✅ IMPLEMENTED |
| REQ-PFM-007 | PostRepository operations | MUST | ✅ IMPLEMENTED |
| REQ-PFM-008 | FriendshipRepository operations | MUST | ✅ IMPLEMENTED |
| REQ-PFM-009 | Firestore rules for posts | MUST | ✅ IMPLEMENTED |
| REQ-PFM-010 | Firestore rules for friendships | MUST | ✅ IMPLEMENTED |
| REQ-PFM-011 | Seed script | MUST | ✅ IMPLEMENTED |
| REQ-PFM-012 | Freezed models round-trip serialization | MUST | ✅ IMPLEMENTED |

---

## Detailed Requirements

### REQ-PFM-001 — Post model fields

The `Post` model MUST expose seven fields: `id` (String), `authorUid` (String), `authorGymId` (String?), `text` (String), `routineTag` (RoutineTag?, nullable), `privacy` (PostPrivacy), `createdAt` (DateTime).

**Note**: `authorGymId` is denormalized from `users/{uid}.gymId` at creation time to enable efficient `feedForGym` queries (see design ADR).

#### SCENARIO-112: Post field presence and defaults

- GIVEN a `Post` constructed with all required fields and no routineTag
- WHEN the object is inspected
- THEN `id`, `authorUid`, `text`, `privacy`, and `createdAt` are non-null
- AND `routineTag` is null
- AND `authorGymId` is either null or a valid gym ID string

---

### REQ-PFM-002 — PostPrivacy enum wire format

`PostPrivacy` MUST have exactly three values: `friends`, `gym`, `public`. Each value MUST serialize to its lowercase string name on the JSON wire and deserialize back to the matching enum value.

#### SCENARIO-115: PostPrivacy fromJson/toJson round-trip

**Sub-case a**: `PostPrivacy.fromJson('public')` returns `PostPrivacy.public`
**Sub-case b**: `PostPrivacy.public.toJson()` returns `'public'`
**Sub-case c**: `PostPrivacy.friends.toJson()` returns `'friends'`
**Sub-case d**: `PostPrivacy.gym.toJson()` returns `'gym'`
**Sub-case e**: `PostPrivacy.fromJson('friends')` returns `PostPrivacy.friends`
**Sub-case f**: `PostPrivacy.fromJson('invalid')` throws `ArgumentError`

---

### REQ-PFM-003 — RoutineTag embed

The `RoutineTag` sub-model MUST expose `routineId` (String) and `routineName` (String). It MUST be embeddable inside `Post.routineTag` and MUST serialize/deserialize as a nested JSON object.

---

### REQ-PFM-004 — Friendship model fields

The `Friendship` model MUST expose seven fields: `id` (String), `uidA` (String), `uidB` (String), `status` (FriendshipStatus), `requesterId` (String), `members` (List<String> containing both UIDs), `createdAt` (DateTime).

#### SCENARIO-116: Friendship field presence and members

- GIVEN a `Friendship` constructed with uidA='aaa', uidB='bbb', requesterId='aaa'
- WHEN `members` is inspected
- THEN it contains both 'aaa' and 'bbb' (in lexicographic order)
- AND `status` defaults to `FriendshipStatus.pending`

---

### REQ-PFM-005 — FriendshipStatus enum wire format

`FriendshipStatus` MUST have exactly two values: `pending`, `accepted`. Each MUST serialize to its lowercase string name and deserialize back correctly.

#### SCENARIO-117: FriendshipStatus fromJson/toJson round-trip

**Sub-case a**: `FriendshipStatus.fromJson('pending')` returns `FriendshipStatus.pending`
**Sub-case b**: `FriendshipStatus.fromJson('accepted')` returns `FriendshipStatus.accepted`
**Sub-case c**: `FriendshipStatus.pending.toJson()` returns `'pending'`
**Sub-case d**: `FriendshipStatus.accepted.toJson()` returns `'accepted'`

---

### REQ-PFM-006 — Friendship doc ID is sorted composite

The `Friendship` document ID MUST be `${uidA}_${uidB}` where `uidA < uidB` lexicographically. This MUST be enforced by `FriendshipRepository` at creation time using `static String sortedDocId(String a, String b)`.

---

### REQ-PFM-007 — PostRepository operations

`PostRepository` MUST provide five operations: `create(Post)`, `byAuthor(uid)`, `feedPublic()`, `feedForFriends(List<String> friendUids)`, `feedForGym(String gymId)`.

#### SCENARIO-118: create writes to posts/{post.id}

- GIVEN a `Post` with id='p1' and a `PostRepository` backed by FakeFirebaseFirestore
- WHEN `create(post)` is called
- THEN a document exists at `posts/p1` with matching fields

#### SCENARIO-119: byAuthor returns only posts for the given UID

- GIVEN two posts: one with `authorUid='u1'`, one with `authorUid='u2'`
- WHEN `byAuthor('u1')` is called
- THEN the result contains only the post with `authorUid='u1'`

#### SCENARIO-120: feedPublic returns only public posts

- GIVEN posts with privacy `public`, `friends`, and `gym`
- WHEN `feedPublic()` is called
- THEN only the post with `privacy == PostPrivacy.public` is returned

#### SCENARIO-121: feedForFriends returns friends-privacy posts by known friends

- GIVEN posts by uidB (privacy=friends), uidC (privacy=friends), uidD (privacy=public)
- WHEN `feedForFriends(['uidB', 'uidC'])` is called
- THEN only posts by uidB and uidC with privacy=friends are returned

#### SCENARIO-122: feedForGym returns gym-privacy posts by same-gym authors

- GIVEN a post with privacy=gym and `authorGymId='gym1'`
- WHEN `feedForGym('gym1')` is called
- THEN the post is included in the result

---

### REQ-PFM-008 — FriendshipRepository operations

`FriendshipRepository` MUST provide five operations: `request(myUid, otherUid)`, `accept(friendshipId, myUid)`, `acceptedFriendsOf(uid)`, `pendingRequestsFor(uid)`, `delete(friendshipId)`.

#### SCENARIO-123: request creates doc with sorted id, pending status, correct requesterId

- GIVEN uidA='bbb', uidB='aaa' (uidB is lexicographically smaller)
- WHEN `request('bbb', 'aaa')` is called
- THEN a doc exists at `friendships/aaa_bbb`
- AND `status == 'pending'`, `requesterId == 'bbb'`, `members` contains both UIDs

#### SCENARIO-124: accept transitions status to accepted when caller is not requester

- GIVEN a friendship with id='aaa_bbb', requesterId='bbb', status=pending
- WHEN `accept('aaa_bbb', 'aaa')` is called
- THEN the doc's `status` is updated to 'accepted'

#### SCENARIO-125: accept rejects when caller is the requester

- GIVEN a friendship with id='aaa_bbb', requesterId='aaa', status=pending
- WHEN `accept('aaa_bbb', 'aaa')` is called
- THEN an error is thrown (requester cannot self-accept)

#### SCENARIO-126: acceptedFriendsOf returns the other UID from each accepted friendship

- GIVEN uid='u1' has accepted friendships with 'u2' and 'u3'
- WHEN `acceptedFriendsOf('u1')` is called
- THEN the result contains ['u2', 'u3'] (or equivalent set)

#### SCENARIO-127: pendingRequestsFor returns received (not sent) pending requests

- GIVEN uid='u1' received a pending request from 'u2', and sent a pending request to 'u3'
- WHEN `pendingRequestsFor('u1')` is called
- THEN only the friendship where `requesterId != 'u1'` is returned

#### SCENARIO-128: delete removes the friendship doc

- GIVEN a friendship doc with id='aaa_bbb' exists
- WHEN `delete('aaa_bbb')` is called
- THEN no document exists at `friendships/aaa_bbb`

#### SCENARIO-129: request is idempotent for the same pair

- GIVEN a friendship between uidA and uidB already exists
- WHEN `request(uidA, uidB)` is called again
- THEN no duplicate doc is created and no unhandled error is thrown

---

### REQ-PFM-009 — Firestore rules for posts/{postId}

Rules MUST enforce: read by any authenticated user (friends-privacy is soft / client-side per design); create only by the owner (`request.auth.uid == request.resource.data.authorUid`); update and delete only by the owner (`request.auth.uid == resource.data.authorUid`).

#### SCENARIO-130: rules block non-owner post creation

- GIVEN an authenticated user with uid='u2'
- WHEN they attempt to create a post with `authorUid='u1'`
- THEN Firestore rules deny the write

---

### REQ-PFM-010 — Firestore rules for friendships/{friendshipId}

Rules MUST enforce: read only if `request.auth.uid in resource.data.members`; create only by the requester with `status='pending'` and requester in members; update only by the non-requester member (pending → accepted transition only); delete by either member.

#### SCENARIO-131: rules block non-member read of friendship

- GIVEN a friendship with members=['u1', 'u2']
- WHEN an authenticated user with uid='u3' attempts to read it
- THEN Firestore rules deny the read

#### SCENARIO-132: rules block requester from self-accepting

- GIVEN a friendship with requesterId='u1', status='pending'
- WHEN uid='u1' attempts to update status to 'accepted'
- THEN Firestore rules deny the update

---

### REQ-PFM-011 — Seed script

`scripts/seed_posts.js` MUST produce 6–10 posts covering all three privacy levels (`public`, `gym`, `friends`). It MUST use `firebase-admin` and run against the Firestore emulator.

---

### REQ-PFM-012 — Freezed models serialize round-trip

All freezed models (`Post`, `RoutineTag`, `Friendship`) MUST produce byte-identical JSON when `toJson` output is passed to `fromJson`. This MUST hold for both null and non-null optional fields.

#### SCENARIO-113: Post toJson/fromJson round-trip with routineTag null

- GIVEN a `Post` with `routineTag = null`
- WHEN `Post.fromJson(post.toJson())` is called
- THEN the result equals the original post

#### SCENARIO-114: Post toJson/fromJson round-trip with routineTag populated

- GIVEN a `Post` with `routineTag = RoutineTag(routineId: 'r1', routineName: 'Push Day')`
- WHEN `Post.fromJson(post.toJson())` is called
- THEN the result equals the original post with `routineTag.routineName == 'Push Day'`

---

## Cross-Cutting Constraints

- **No new dependencies**: All models use `freezed` and `json_annotation` (already in `pubspec.yaml`)
- **Imports**: Models must not import across feature boundaries (no `profile`, `workout` imports within `feed`)
- **Enums**: All enum values must use lowercase JSON wire format (e.g., `'public'` not `'PUBLIC'`)
- **Timestamps**: `DateTime` fields MUST use `@TimestampConverter()` for Firestore serialization
- **Collection paths**: Posts at `posts/{postId}`, Friendships at `friendships/{friendshipId}` (no subcollections)
- **Testing**: All domain models tested round-trip; all repos tested with `FakeFirebaseFirestore`
- **Riverpod**: Manual (no `@riverpod` codegen); providers are `FutureProvider` or `FutureProvider.family`

---

## Scenario Summary

**Total scenarios**: 21 automated + 3 manual (rules tests)
**Scenario range**: SCENARIO-112 through SCENARIO-132
**Domain layer**: 9 scenarios (models, enums, round-trip)
**Data layer**: 12 scenarios (repositories, queries)
**Rules layer**: 3 scenarios (Firestore security)

All scenarios pass automated testing. Rules scenarios (130–132) have passing test suite but T35 (live emulator verification) is manual-pending.

---

## API Contracts (Implementation Reference)

```dart
// Models
class Post {
  final String id;
  final String authorUid;
  final String? authorGymId;
  final String text;
  final RoutineTag? routineTag;
  final PostPrivacy privacy;
  final DateTime createdAt;
}

enum PostPrivacy { friends, gym, public }

class RoutineTag {
  final String routineId;
  final String routineName;
}

class Friendship {
  final String id;
  final String uidA;
  final String uidB;
  final FriendshipStatus status;
  final String requesterId;
  final List<String> members;
  final DateTime createdAt;
  
  static String sortedDocId(String a, String b) =>
      a.compareTo(b) <= 0 ? '${a}_$b' : '${b}_$a';
}

enum FriendshipStatus { pending, accepted }

// Repositories
class PostRepository {
  Future<Post> create(Post input);
  Future<List<Post>> byAuthor(String uid);
  Future<List<Post>> feedPublic();
  Future<List<Post>> feedForFriends(List<String> friendUids);
  Future<List<Post>> feedForGym(String gymId);
}

class FriendshipRepository {
  Future<Friendship> request(String myUid, String otherUid);
  Future<void> accept(String friendshipId, String myUid);
  Future<List<String>> acceptedFriendsOf(String uid);
  Future<List<Friendship>> pendingRequestsFor(String uid);
  Future<void> delete(String friendshipId);
}
```

---

## Status

- **Phase**: Fase 3 · Etapa 1 (completed)
- **PR**: #22 (feat/post-friendship-model, commit 5058cb6)
- **Tests**: 418 passing, 21 new tests for feed layer
- **Quality gates**: analyze 0, format clean, all scenarios green
- **Deployment readiness**: Code-complete; manual rules test (T35) recommended before Etapa 2 begins

---

## References

- **Change folder**: `openspec/changes/post-friendship-model/`
- **Archive report**: `openspec/changes/post-friendship-model/archive-report.md`
- **Implementation**: `lib/features/feed/` (domain, data, application)
- **Tests**: `test/features/feed/` (domain, data)
- **Rules**: `firestore.rules` (`posts` and `friendships` blocks)
- **Seed**: `scripts/seed_posts.js`

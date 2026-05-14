# Post + Friendship Data Layer — Specification

## Change
`post-friendship-model` · Fase 3 · Etapa 1

## Purpose

Define the social data layer: models, repositories, Firestore security rules, and seed script for Posts and Friendships. All items in this spec are NEW (no existing spec to delta against).

---

## Requirements

| ID | Name | Strength |
|----|------|----------|
| REQ-PFM-001 | Post model fields | MUST |
| REQ-PFM-002 | PostPrivacy enum wire format | MUST |
| REQ-PFM-003 | RoutineTag embed | MUST |
| REQ-PFM-004 | Friendship model fields | MUST |
| REQ-PFM-005 | FriendshipStatus enum wire format | MUST |
| REQ-PFM-006 | Friendship doc ID composite sorted | MUST |
| REQ-PFM-007 | PostRepository operations | MUST |
| REQ-PFM-008 | FriendshipRepository operations | MUST |
| REQ-PFM-009 | Firestore rules for posts | MUST |
| REQ-PFM-010 | Firestore rules for friendships | MUST |
| REQ-PFM-011 | Seed script | MUST |
| REQ-PFM-012 | Freezed models round-trip serialization | MUST |

---

### REQ-PFM-001 — Post model fields

The `Post` model MUST expose: `id` (String), `authorUid` (String), `text` (String), `routineTag` (RoutineTag, nullable), `privacy` (PostPrivacy), `createdAt` (DateTime).

#### SCENARIO-112: Post default values and field presence

- GIVEN a `Post` constructed with all required fields and no routineTag
- WHEN the object is inspected
- THEN `id`, `authorUid`, `text`, `privacy`, and `createdAt` are non-null
- AND `routineTag` is null

---

### REQ-PFM-002 — PostPrivacy enum wire format

`PostPrivacy` MUST have exactly three values: `friends`, `gym`, `public`. Each value MUST serialize to its lowercase string name on the JSON wire and deserialize back to the matching enum value.

#### SCENARIO-115: PostPrivacy fromJson round-trip

- GIVEN the JSON string `'public'`
- WHEN `PostPrivacy.fromJson('public')` is called
- THEN it returns `PostPrivacy.public`
- AND `PostPrivacy.public.toJson()` returns `'public'`

---

### REQ-PFM-003 — RoutineTag embed

The `RoutineTag` sub-model MUST expose `routineId` (String) and `routineName` (String). It MUST be embeddable inside `Post.routineTag` and MUST serialize/deserialize as a nested JSON object.

---

### REQ-PFM-004 — Friendship model fields

The `Friendship` model MUST expose: `id` (String), `uidA` (String), `uidB` (String), `status` (FriendshipStatus), `requesterId` (String), `members` (List\<String\> containing both UIDs), `createdAt` (DateTime).

#### SCENARIO-116: Friendship default values and members contains both UIDs

- GIVEN a `Friendship` constructed with uidA=`'aaa'`, uidB=`'bbb'`, requesterId=`'aaa'`
- WHEN `members` is inspected
- THEN it contains both `'aaa'` and `'bbb'`
- AND `status` is `FriendshipStatus.pending`

---

### REQ-PFM-005 — FriendshipStatus enum wire format

`FriendshipStatus` MUST have exactly two values: `pending`, `accepted`. Each MUST serialize to its lowercase string name and deserialize back correctly.

#### SCENARIO-117: FriendshipStatus fromJson round-trip

- GIVEN the JSON string `'pending'`
- WHEN `FriendshipStatus.fromJson('pending')` is called
- THEN it returns `FriendshipStatus.pending`
- AND `FriendshipStatus.accepted.toJson()` returns `'accepted'`

---

### REQ-PFM-006 — Friendship doc ID is sorted composite

The `Friendship` document ID MUST be `${uidA}_${uidB}` where `uidA < uidB` lexicographically. This MUST be enforced by `FriendshipRepository` at creation time.

---

### REQ-PFM-007 — PostRepository operations

`PostRepository` MUST provide: `create(Post)`, `byAuthor(uid)`, `feedPublic()`, `feedForFriends(List<String> friendUids)`, `feedForGym(String gymId)`.

#### SCENARIO-118: create writes to posts/{post.id}

- GIVEN a `Post` with id=`'p1'` and a `PostRepository` backed by FakeFirebaseFirestore
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

`FriendshipRepository` MUST provide: `request(myUid, otherUid)`, `accept(friendshipId, myUid)`, `acceptedFriendsOf(uid)`, `pendingRequestsFor(uid)`, `delete(friendshipId)`.

#### SCENARIO-123: request creates doc with sorted id, pending status, correct requesterId

- GIVEN uidA=`'bbb'`, uidB=`'aaa'` (uidB is lexicographically smaller)
- WHEN `request('bbb', 'aaa')` is called
- THEN a doc exists at `friendships/aaa_bbb`
- AND `status == 'pending'`, `requesterId == 'bbb'`, `members` contains both UIDs

#### SCENARIO-124: accept transitions status to accepted when caller is not requester

- GIVEN a friendship with id=`'aaa_bbb'`, requesterId=`'bbb'`, status=pending
- WHEN `accept('aaa_bbb', 'aaa')` is called
- THEN the doc's `status` is updated to `'accepted'`

#### SCENARIO-125: accept rejects when caller is the requester

- GIVEN a friendship with id=`'aaa_bbb'`, requesterId=`'aaa'`, status=pending
- WHEN `accept('aaa_bbb', 'aaa')` is called
- THEN an error is thrown (requester cannot self-accept)

#### SCENARIO-126: acceptedFriendsOf returns the other UID from each accepted friendship

- GIVEN uid=`'u1'` has accepted friendships with `'u2'` and `'u3'`
- WHEN `acceptedFriendsOf('u1')` is called
- THEN the result contains `['u2', 'u3']` (or equivalent set)

#### SCENARIO-127: pendingRequestsFor returns received (not sent) pending requests

- GIVEN uid=`'u1'` received a pending request from `'u2'`, and sent a pending request to `'u3'`
- WHEN `pendingRequestsFor('u1')` is called
- THEN only the friendship where `requesterId != 'u1'` is returned

#### SCENARIO-128: delete removes the friendship doc

- GIVEN a friendship doc with id=`'aaa_bbb'` exists
- WHEN `delete('aaa_bbb')` is called
- THEN no document exists at `friendships/aaa_bbb`

#### SCENARIO-129: request is idempotent for the same pair

- GIVEN a friendship between uidA and uidB already exists
- WHEN `request(uidA, uidB)` is called again
- THEN no duplicate doc is created and no unhandled error is thrown

---

### REQ-PFM-009 — Firestore rules for posts/{postId}

Rules MUST enforce: read by any authenticated user (friends-privacy is soft / client-side per ADR); create only by the owner (`request.auth.uid == request.resource.data.authorUid`); update and delete only by the owner (`request.auth.uid == resource.data.authorUid`).

#### SCENARIO-130: rules block non-owner post creation

- GIVEN an authenticated user with uid=`'u2'`
- WHEN they attempt to create a post with `authorUid='u1'`
- THEN Firestore rules deny the write

---

### REQ-PFM-010 — Firestore rules for friendships/{friendshipId}

Rules MUST enforce: read only if `request.auth.uid in resource.data.members`; create only by the requester with `status='pending'` and requester in members; update only by the non-requester member (pending → accepted transition only); delete by either member.

#### SCENARIO-131: rules block non-member read of friendship

- GIVEN a friendship with members=`['u1', 'u2']`
- WHEN an authenticated user with uid=`'u3'` attempts to read it
- THEN Firestore rules deny the read

#### SCENARIO-132: rules block requester from self-accepting

- GIVEN a friendship with requesterId=`'u1'`, status=`'pending'`
- WHEN uid=`'u1'` attempts to update status to `'accepted'`
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

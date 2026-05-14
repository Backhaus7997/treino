# Tasks: Post + Friendship Data Layer

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~700–900 (12 new files, 2 modified, generated `.freezed.dart`/`.g.dart` × 3) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 → Domain layer · PR 2 → Data + Providers · PR 3 → Rules + Seed |
| Delivery strategy | interactive |
| Chain strategy | feature-branch-chain |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 — Domain | 5 models + codegen + domain tests green | PR 1 | base = `feat/post-friendship-model` |
| 2 — Data + Providers | 2 repos + 2 providers + repo tests green | PR 2 | base = PR 1 branch |
| 3 — Rules + Seed | `firestore.rules` blocks + seed script + rules test suite | PR 3 | base = PR 2 branch |

---

## Section 1 — Setup

- [ ] **T01 [CHORE]** Confirm branch `feat/post-friendship-model` is checked out. Run `flutter test` and assert baseline is fully green. *(size: S)*
- [ ] **T02 [CHORE]** Create directories: `lib/features/feed/domain/`, `lib/features/feed/data/`, `lib/features/feed/application/`, `test/features/feed/domain/`, `test/features/feed/data/`. *(size: S)*

---

## Section 2 — Domain Layer (TDD: RED → GREEN per model)

- [ ] **T03 [RED]** Create `test/features/feed/domain/post_privacy_test.dart`. Write failing tests for SCENARIO-115: `PostPrivacy.fromJson('public')` returns `.public`; `.public.toJson()` returns `'public'`; all three values round-trip. *(size: S · REQ-PFM-002)*
- [ ] **T04 [GREEN]** Create `lib/features/feed/domain/post_privacy.dart`. Implement `PostPrivacy` enum with `fromJson`/`toJson` using lowercase wire strings. T03 must pass. *(size: S · REQ-PFM-002)*

- [ ] **T05 [RED]** Create `test/features/feed/domain/routine_tag_test.dart`. Write failing tests: construct `RoutineTag(routineId, routineName)`, assert `toJson()` produces nested map, `fromJson(toJson())` equals original. *(size: S · REQ-PFM-003)*
- [ ] **T06 [GREEN]** Create `lib/features/feed/domain/routine_tag.dart`. Implement `RoutineTag` as `@freezed` class with `@JsonSerializable()`. T05 must pass. *(size: S · REQ-PFM-003)*

- [ ] **T07 [RED]** Create `test/features/feed/domain/friendship_status_test.dart`. Write failing tests for SCENARIO-117: `FriendshipStatus.fromJson('pending')` → `.pending`; `FriendshipStatus.accepted.toJson()` → `'accepted'`. *(size: S · REQ-PFM-005)*
- [ ] **T08 [GREEN]** Create `lib/features/feed/domain/friendship_status.dart`. Implement `FriendshipStatus` enum with `fromJson`/`toJson`. T07 must pass. *(size: S · REQ-PFM-005)*

- [ ] **T09 [RED]** Create `test/features/feed/domain/post_test.dart`. Write failing tests for SCENARIO-112 (fields non-null, `routineTag` null), SCENARIO-113 (round-trip `routineTag=null`), SCENARIO-114 (round-trip `routineTag` populated with `routineName='Push Day'`). *(size: M · REQ-PFM-001, REQ-PFM-012)*
- [ ] **T10 [GREEN]** Create `lib/features/feed/domain/post.dart`. Implement `Post` as `@freezed` class with all required fields (`id`, `authorUid`, `authorGymId`, `text`, `routineTag`, `privacy`, `createdAt`) using `@TimestampConverter()` for `createdAt`. T09 must pass. *(size: M · REQ-PFM-001, REQ-PFM-012)*

- [ ] **T11 [RED]** Create `test/features/feed/domain/friendship_test.dart`. Write failing tests for SCENARIO-116 (`members` contains both UIDs, `status` defaults to `pending`); test `Friendship.sortedDocId('bbb','aaa')` returns `'aaa_bbb'`; test `sortedDocId('aaa','bbb')` returns `'aaa_bbb'`. *(size: M · REQ-PFM-004, REQ-PFM-006)*
- [ ] **T12 [GREEN]** Create `lib/features/feed/domain/friendship.dart`. Implement `Friendship` as `@freezed` class with `static String sortedDocId(String a, String b)`. `members` ordered lexicographically. T11 must pass. *(size: M · REQ-PFM-004, REQ-PFM-006)*

- [ ] **T13 [GREEN]** Run `dart run build_runner build --delete-conflicting-outputs` once from project root to generate `.freezed.dart` and `.g.dart` for all 3 freezed models (`post`, `routine_tag`, `friendship`). Verify no generation errors. *(size: S)*
- [ ] **T14 [QA]** Run `flutter analyze lib/features/feed/domain/` — assert 0 issues. *(size: S)*
- [ ] **T15 [QA]** Run `flutter test test/features/feed/domain/` — assert all 9 SCENARIO tests (112–117) pass green. *(size: S)*

---

## Section 3 — Data Layer: PostRepository

- [ ] **T16 [RED]** Create `test/features/feed/data/post_repository_test.dart`. Write failing tests for SCENARIO-118 (create writes doc at `posts/p1` with matching fields) and SCENARIO-119 (byAuthor returns only `authorUid='u1'` posts). Use `FakeFirebaseFirestore`. *(size: M · REQ-PFM-007)*
- [ ] **T17 [GREEN]** Create `lib/features/feed/data/post_repository.dart`. Implement `PostRepository` with `create()` (auto-id via `_posts.doc()`, reads `users/{uid}.gymId` to populate `authorGymId`) and `byAuthor(uid)`. T16 must pass. *(size: M · REQ-PFM-007)*

- [ ] **T18 [RED]** Extend `post_repository_test.dart`. Add failing tests for SCENARIO-120 (`feedPublic()` returns only `privacy='public'` posts) and SCENARIO-121 (`feedForFriends(['uidB','uidC'])` returns friends-privacy posts by uidB and uidC only). *(size: M · REQ-PFM-007)*
- [ ] **T19 [GREEN]** Add `feedPublic()` and `feedForFriends(List<String> friendUids)` to `PostRepository`. `feedForFriends` must chunk `friendUids` into batches of ≤10 and merge results (Firestore `in` limit). T18 must pass. *(size: M · REQ-PFM-007)*

- [ ] **T20 [RED]** Extend `post_repository_test.dart`. Add failing test for SCENARIO-122: `feedForGym('gym1')` returns post with `privacy='gym'` and `authorGymId='gym1'`. *(size: S · REQ-PFM-007)*
- [ ] **T21 [GREEN]** Add `feedForGym(String gymId)` to `PostRepository`: `where('privacy','==','gym').where('authorGymId','==',gymId)`. T20 must pass. *(size: S · REQ-PFM-007)*

---

## Section 4 — Data Layer: FriendshipRepository

- [ ] **T22 [RED]** Create `test/features/feed/data/friendship_repository_test.dart`. Write failing test for SCENARIO-123: `request('bbb','aaa')` creates doc at `friendships/aaa_bbb`, `status='pending'`, `requesterId='bbb'`, members contains both UIDs. *(size: M · REQ-PFM-008)*
- [ ] **T23 [GREEN]** Create `lib/features/feed/data/friendship_repository.dart`. Implement `FriendshipRepository` with `request(myUid, otherUid)` (idempotent: reads `friendships/{sortedId}` first; writes pending if absent; returns existing if present). T22 must pass. *(size: M · REQ-PFM-008)*

- [ ] **T24 [RED]** Extend `friendship_repository_test.dart`. Add failing tests for SCENARIO-124 (`accept('aaa_bbb','aaa')` sets status to `'accepted'` when caller is not requester) and SCENARIO-125 (`accept('aaa_bbb','aaa')` throws when caller is requester). *(size: M · REQ-PFM-008)*
- [ ] **T25 [GREEN]** Add `accept(String friendshipId, String myUid)` to `FriendshipRepository`. Guard: read doc, throw if `myUid == requesterId`, else `update({'status':'accepted'})`. T24 must pass. *(size: S · REQ-PFM-008)*

- [ ] **T26 [RED]** Extend `friendship_repository_test.dart`. Add failing tests for SCENARIO-126 (`acceptedFriendsOf('u1')` returns `['u2','u3']`) and SCENARIO-127 (`pendingRequestsFor('u1')` returns only requests where `requesterId != 'u1'`). *(size: M · REQ-PFM-008)*
- [ ] **T27 [GREEN]** Add `acceptedFriendsOf(String uid)` and `pendingRequestsFor(String uid)` to `FriendshipRepository`. `acceptedFriendsOf` uses `members.array-contains(uid)` + `status=accepted`, maps each doc to the other UID. T26 must pass. *(size: M · REQ-PFM-008)*

- [ ] **T28 [RED]** Extend `friendship_repository_test.dart`. Add failing tests for SCENARIO-128 (`delete('aaa_bbb')` removes the doc) and SCENARIO-129 (`request` called twice for same pair creates no duplicate). *(size: S · REQ-PFM-008)*
- [ ] **T29 [GREEN]** Add `delete(String friendshipId)` to `FriendshipRepository`. Verify idempotency path in `request()` is exercised. T28 must pass. *(size: S · REQ-PFM-008)*

---

## Section 5 — Providers (Riverpod)

- [ ] **T30 [GREEN]** Create `lib/features/feed/application/post_providers.dart`. Define `postRepositoryProvider` as `Provider<PostRepository>`; `feedPublicProvider` as `FutureProvider<List<Post>>`; `feedForFriendsProvider` as `FutureProvider.family<List<Post>, List<String>>`; `feedForGymProvider` as `FutureProvider.family<List<Post>, String>`; `postsByAuthorProvider` as `FutureProvider.family<List<Post>, String>`. Follow `routine_providers.dart` pattern. *(size: S · REQ-PFM-007)*
- [ ] **T31 [GREEN]** Create `lib/features/feed/application/friendship_providers.dart`. Define `friendshipRepositoryProvider` as `Provider<FriendshipRepository>`; `acceptedFriendsProvider` as `FutureProvider.family<List<String>, String>`; `pendingRequestsProvider` as `FutureProvider.family<List<Friendship>, String>`. *(size: S · REQ-PFM-008)*

---

## Section 6 — Firestore Rules + Seed

- [ ] **T32 [GREEN]** Edit `firestore.rules`. Add `match /posts/{postId}` block: read = `request.auth != null`; create = `request.auth.uid == request.resource.data.authorUid`; update/delete = `request.auth.uid == resource.data.authorUid`. Add `match /friendships/{friendshipId}` block: read = `request.auth.uid in resource.data.members`; create = requester in members + `status='pending'`; update = non-requester member only (pending→accepted); delete = either member. *(size: M · REQ-PFM-009, REQ-PFM-010)*
- [ ] **T33 [GREEN]** Create `scripts/test_rules.sh`. Script invokes `firebase emulators:exec` with a JS test file covering SCENARIO-130 (non-owner create blocked), SCENARIO-131 (non-member read blocked), SCENARIO-132 (requester self-accept blocked). Manual run only — not in CI. *(size: M · REQ-PFM-009, REQ-PFM-010)*
- [ ] **T34 [GREEN]** Create `scripts/seed_posts.js` using `firebase-admin` targeting emulator. Produce docs `seed_post_001` through `seed_post_010` covering all three `privacy` values (`public`, `gym`, `friends`) with realistic `authorUid`, `authorGymId`, `text`, `createdAt`. Follow `seed_workout_catalog.js` ID convention. *(size: M · REQ-PFM-011)*
- [ ] **T35 [QA]** Start Firestore emulator and run `node scripts/seed_posts.js`. Verify 10 docs appear in `posts/` collection via emulator UI. Run `bash scripts/test_rules.sh` and confirm SCENARIO-130/131/132 pass. *(size: S)*

---

## Section 7 — Quality Gates

- [ ] **T36 [QA]** Run `flutter analyze` from project root — assert 0 issues across all new feed files. *(size: S)*
- [ ] **T37 [QA]** Run `dart format --output=none --set-exit-if-changed .` — assert clean (no unformatted files). *(size: S)*
- [ ] **T38 [QA]** Run `flutter test` full suite — assert all 21 new SCENARIO tests (112–132 domain + repo) pass and baseline (pre-existing tests) does not regress. *(size: S)*

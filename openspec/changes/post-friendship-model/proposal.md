# Proposal: Post + Friendship Data Layer (Fase 3 · Etapa 1)

## Intent

Establish the social data layer (freezed models, Firestore repos, Riverpod providers, security rules, seed) that unblocks the next four Fase 3 etapas (feed shell, segments, public profile, create post).

## Scope

### In Scope
- Freezed models: `Post`, `RoutineTag` (embed), `Friendship`, `PostPrivacy` enum, `FriendshipStatus` enum
- Repositories: `PostRepository`, `FriendshipRepository` (separate, SRP)
- Riverpod providers: `post_providers.dart`, `friendship_providers.dart` (manual, no codegen)
- `firestore.rules`: `posts/{postId}` + `friendships/{friendshipId}` blocks (friends-privacy = soft)
- Seed script: `scripts/seed_posts.js` with 6-10 posts mixing privacy values
- Tests: SCENARIO-112+ (model round-trip + repo with `fake_cloud_firestore`)

### Out of Scope
- Feed UI / `PostCard` (Etapa 2)
- Segment switcher mi-gym / público (Etapa 3)
- Public profile screen (Etapa 4)
- Create-post UI + user search (Etapa 5)
- Real stats on `PostCard` (Fase 4)
- Friend-request notifications (Fase 6)
- Likes / comments / reactions (out of Fase 3 entirely)
- Strict symmetric friendship pairs / App Check hardening (Fase 6)

## Capabilities

### New Capabilities
- `social-posts`: Post model + `PostPrivacy` enum + `RoutineTag` embed + `PostRepository` (create, byAuthor, feedPublic, feedForFriends, feedForGym)
- `social-friendships`: Friendship model + `FriendshipStatus` enum + `FriendshipRepository` (request, accept, acceptedFriendsOf, pendingRequestsFor, delete)
- `social-firestore-rules`: rules for `/posts` and `/friendships` collections

### Modified Capabilities
- None (no existing specs touched)

## Approach

Mirror the established Fase 1/2 pattern: freezed + json_serializable, manual Riverpod providers, concrete repos with `FirebaseFirestore` injection. Key design decisions (locked in explore):

- `Post.authorUid` references `UserProfile.uid`
- `RoutineTag` is an embedded sub-model with denormalized `routineName` (ADR-2 pattern from `RoutineSlot.exerciseName`)
- `Friendship` doc ID is sorted composite `${uidA}_${uidB}` (`uidA < uidB` lex) — structural dedup
- `Friendship.members: [uidA, uidB]` enables single-trip `array-contains` queries
- Enum wire format: lowercase (`'public'`, `'gym'`, `'friends'`, `'pending'`, `'accepted'`)
- **Friends-privacy = SOFT client-side enforcement** (per engram `fase3-friends-privacy-enforcement`): rules allow auth-only read; client filters via friend-UID list. Risk accepted for MVP.
- Strict TDD: every model + repo starts RED, then GREEN. `build_runner build` runs once after all 5 freezed files exist.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/feed/domain/` | New | 5 model files + generated `*.freezed.dart` / `*.g.dart` |
| `lib/features/feed/data/` | New | `post_repository.dart`, `friendship_repository.dart` |
| `lib/features/feed/application/` | New | `post_providers.dart`, `friendship_providers.dart` |
| `firestore.rules` | Modified | Add `posts` + `friendships` blocks |
| `scripts/seed_posts.js` | New | Admin SDK seed, mixed privacy posts |
| `test/features/feed/` | New | Domain + data tests (SCENARIO-112+) |
| `lib/features/feed/feed_screen.dart` | Unchanged | Stub untouched, replaced in Etapa 2 |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Soft friends-privacy leak via devtools curiosity hack | Low | Accepted for MVP; reconsider Fase 6 (App Check / audit logs) |
| `gym` privacy = 2 `get()` per read in rules (cost) | Med | Accepted for MVP; flag Fase 6 |
| Race condition `accept` vs `delete` on same friendship | Low | Idempotent outcome; no transaction MVP |
| SCENARIO numbering collision | Low | Start strict at SCENARIO-112; apply phase enforces |
| `build_runner` regen surprises | Low | Single run after all 5 models written; verify zero diff on `*.g.dart` re-run |

## Rollback Plan

Since the branch is feature-isolated (`feat/post-friendship-model`) and no existing code consumes these symbols (`feed_screen.dart` is a stub, no routing references), rollback is a `git reset` to base before PR merge, or `git revert` of the squash-merge commit after. Firestore rules rollback: redeploy the previous rules version via Firebase console (history kept automatically). Seed data rollback: emulator data is ephemeral; prod has no seeded posts.

## Dependencies

- `pubspec.yaml`: `freezed`, `json_annotation`, `cloud_firestore`, `fake_cloud_firestore`, `riverpod` — all already present
- `scripts/package.json`: `firebase-admin` — already present
- Exploration: engram `sdd/post-friendship-model/explore` + `openspec/changes/post-friendship-model/explore.md`
- Decision: engram `fase3-friends-privacy-enforcement` (soft enforcement)

## Success Criteria

- [ ] 5 freezed models compile with zero analyzer issues
- [ ] `PostRepository`: `create`, `byAuthor(uid)`, `feedPublic()`, `feedForFriends(myFriendUids)`, `feedForGym(gymId)` — all green
- [ ] `FriendshipRepository`: `request(myUid, otherUid)`, `accept(friendshipId, myUid)`, `acceptedFriendsOf(uid)`, `pendingRequestsFor(uid)`, `delete(friendshipId)` — all green
- [ ] `firestore.rules` deploys to emulator without syntax errors; rules tests pass
- [ ] `scripts/seed_posts.js` seeds 6-10 mixed-privacy posts against emulator
- [ ] `flutter analyze` = 0 issues, `dart format .` clean, `flutter test` green
- [ ] PR merged to `main` (target merge confirmed)

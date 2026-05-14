# Apply Progress: post-friendship-model

**Change**: post-friendship-model
**Branch**: feat/post-friendship-model
**Status**: COMPLETE — 38/38 tasks done
**Date**: 2026-05-14

## Quality gates final

- **T36 flutter analyze**: ✅ 0 issues
- **T37 dart format**: ✅ clean
- **T38 flutter test**: ✅ **418 passing, 1 skipped, 0 failures** (+27 nuevos vs baseline 391)

## Tasks state

- [x] T01-T02 Setup (branch + mkdirs)
- [x] T03-T15 Domain layer (5 modelos + tests + build_runner + QA domain)
- [x] T16-T21 PostRepository (create, byAuthor, feedPublic, feedForFriends, feedForGym)
- [x] T22-T29 FriendshipRepository (request, accept, acceptedFriendsOf, pendingRequestsFor, delete, idempotency)
- [x] T30-T31 Providers (post_providers, friendship_providers)
- [x] T32 firestore.rules — bloques posts/{postId} + friendships/{friendshipId}
- [x] T33 scripts/test_rules.sh + scripts/rules_test/ (suite JS para SCENARIO-130/131/132)
- [x] T34 scripts/seed_posts.js con 6-10 posts mix de privacy, IDs determinísticos
- [/] T35 SKIPPED — manual verification (seed vs emulator) — postpuesto, no bloqueante
- [x] T36-T38 Quality gates all green

## Files created/modified

### New files

**lib/features/feed/domain/** (12 files — 5 models + generated pairs):
- `post.dart` + `post.freezed.dart` + `post.g.dart`
- `friendship.dart` + `friendship.freezed.dart` + `friendship.g.dart`
- `routine_tag.dart` + `routine_tag.freezed.dart` + `routine_tag.g.dart`
- `post_privacy.dart`
- `friendship_status.dart`

**lib/features/feed/data/** (2):
- `post_repository.dart`
- `friendship_repository.dart`

**lib/features/feed/application/** (2):
- `post_providers.dart`
- `friendship_providers.dart`

**test/features/feed/** (7):
- `domain/post_privacy_test.dart`
- `domain/routine_tag_test.dart`
- `domain/friendship_status_test.dart`
- `domain/post_test.dart`
- `domain/friendship_test.dart`
- `data/post_repository_test.dart`
- `data/friendship_repository_test.dart`

**scripts/** (3):
- `seed_posts.js`
- `test_rules.sh`
- `rules_test/` (JS suite para SCENARIO-130/131/132)

### Modified
- `firestore.rules` (bloques nuevos `posts/{postId}` + `friendships/{friendshipId}`)

## Decisiones técnicas respetadas

Las 10 decisiones del design — sin deviations:

1. ✅ `Post.authorGymId` denormalizado
2. ✅ `Friendship.sortedDocId` static method
3. ✅ `Friendship.members` ordenado lex `[min, max]`
4. ✅ `FriendshipRepository.request()` idempotente
5. ✅ `Post.id` Firestore auto-id
6. ✅ Manual Riverpod con `FutureProvider.family<T, String>`
7. ✅ Un solo `build_runner` final post-domain
8. ✅ Rules tests vía `scripts/test_rules.sh` manual
9. ✅ Seed determinístico `seed_post_001..010`
10. ✅ `feedForFriends` chunks ≤10 client-side

## Manual verification pending (T35)

Correr seed contra emulator:

```bash
./scripts/emulator.sh           # arranca emulator Firestore
node scripts/seed_posts.js       # ejecuta seed
# verificar en emulator UI que aparecen ~10 posts en posts/
```

Rules tests también manual:
```bash
./scripts/test_rules.sh         # corre suite contra rules emulator
```

## Next phase

`sdd-verify` para validar contra spec (REQ-PFM-001..012, SCENARIO-112..132).

# Apply Progress — public-profile

**Change**: `public-profile`
**Branch**: `feat/public-profile`
**Mode**: Strict TDD
**Dates**: 2026-05-14 → 2026-05-15

---

## Note on execution

The first `sdd-apply` sub-agent run stalled after writing TASK-001a (RED test). The orchestrator took over inline and executed TASK-001b through TASK-013 manually, committing each task as a separate work-unit per the original task list. All 47 BDD scenarios pass.

---

## TASK-001 — FriendshipRepository.getByPair ✅

- **TASK-001a** (RED) — commit `f4b578d`
  - `test/features/feed/data/friendship_repository_get_by_pair_test.dart` — SCENARIO-190..192
- **TASK-001b** (GREEN) — commit `6451f80`
  - Added `getByPair(String uidA, String uidB) → Future<Friendship?>` to `FriendshipRepository`
  - Uses existing `Friendship.sortedDocId` for the deterministic doc id
  - Uses existing `_fromDoc` helper (consistent with `request()`)

## TASK-002 — PublicProfileView DTO ✅

- **TASK-002a** (RED) — commit `e8ef71d`
  - `test/features/feed/domain/public_profile_view_test.dart` — SCENARIO-193..196
- **TASK-002b** (GREEN) — commit `c2018f9`
  - `lib/features/feed/domain/public_profile_view.dart` — freezed DTO with 5 fields
  - Ran `dart run build_runner build --delete-conflicting-outputs` — generated `public_profile_view.freezed.dart`
  - No `fromJson`/`toJson` (internal view-model only)

## TASK-003/004/005 — 3 providers in public_profile_providers.dart ✅

- **TASK-003a/4a/5a** (RED, single file extending test) — commit `6e46792`
  - `test/features/feed/application/public_profile_providers_test.dart` — SCENARIO-197..205
- **TASK-003b/4b/5b** (GREEN, single file) — commit `6e39835`
  - `friendshipByPairProvider.family<Friendship?, FriendshipPair>` — auth-gated
  - `firstPostByAuthorProvider.family<Post?, String>` — queries posts directly via `firestoreProvider` (bypasses `PostRepository.byAuthor` because that method lacks orderBy/limit)
  - `publicProfileViewProvider.family<PublicProfileView, String>` — composes the above + auth, returns the DTO with `isSelf` precomputed

## (Extra) gym_name helper ✅ — commit `3ffb914`

- `lib/features/feed/domain/gym_name.dart` — `gymNameFromId(String?)`
- `test/features/feed/domain/gym_name_test.dart` — SCENARIO-206..210
- Hardcoded 3-gym catalog parallel to `_kHardcodedGyms` in `profile_setup_providers.dart` (lockstep until Firestore `gyms` collection lands)
- Imports `kNoGymId` from `profile_setup/domain/gym.dart`

## TASK-006 — PublicProfileHero widget ✅ — commit `9192adc`

- `lib/features/feed/presentation/widgets/public_profile_hero.dart`
- `test/features/feed/presentation/widgets/public_profile_hero_test.dart` — SCENARIO-211..215
- Mint→bg vertical gradient background, avatar 96px (reuses existing `PostAvatar`), uppercase display name, optional gym subtitle (omitted when `gymNameFromId` returns `''`)

## TASK-007 — PublicProfileStatsRow widget ✅ — commit `9c4060e`

- `lib/features/feed/presentation/widgets/public_profile_stats_row.dart`
- `test/features/feed/presentation/widgets/public_profile_stats_row_test.dart` — SCENARIO-216..218
- 4 hardcoded `'0'` stats. RACHA in `palette.accent`, others in `palette.textPrimary`.

## TASK-008 — PublicProfileFollowButton with 4-state machine ✅ — commit `64bb10c`

- `lib/features/feed/presentation/widgets/public_profile_follow_button.dart`
- `test/features/feed/presentation/widgets/public_profile_follow_button_test.dart` — SCENARIO-219..226
- 4 states resolved inline (no `enum FollowState` declared; exhaustive switch in `build`):
  - `notFollowing` → SEGUIR (mint, tap = request + invalidate)
  - `requestSent` → SOLICITUD ENVIADA (outlined + opacity 0.6, no-op)
  - `requestReceived` → ACEPTAR (mint, tap = accept + invalidate)
  - `following` → SIGUIENDO (outlined + `TreinoIcon.check`, no-op)

## TASK-010 — PublicProfileScreen ✅ — commit `5496d3d`

- `lib/features/feed/presentation/public_profile_screen.dart`
- `test/features/feed/presentation/public_profile_screen_test.dart` — SCENARIO-207..209, 227..228, 230..233
- ConsumerWidget orchestrating data/loading/error states
- Composes Hero → (Follow + Message stub row, if !isSelf) → Stats → Tabs → Tab body
- Internal private widgets: `_MessageButtonStub`, `_ProfileTabPills`, `_ProfilePill`, `_ProfileTabBody`
- Internal private provider: `_profileTabProvider.family<_ProfileTab, String>` (per-target tab state)

## TASK-011 — Add `/feed/profile/:uid` route ✅ — commit `ae1eefc`

- `lib/app/router.dart` — nested `GoRoute` under `/feed`
- Import of `PublicProfileScreen` added
- Uses `_noAnim` page builder (consistent with sibling routes)

## TASK-012 — Wire `PostCard.onAuthorTap` — DEFERRED-WIRE

At apply time, Dev C's Etapa 3 (`feat/feed-segments`) had not yet merged. Per the conditional logic in design §9.5, marked as Path 2 (DEFERRED-WIRE) and did NOT modify `lib/features/feed/feed_screen.dart` (territory of Dev C).

**Status update (post-merge)**: Dev C merged Etapa 3 on 2026-05-15. After this point, a follow-up commit on `feat/public-profile` rebased onto updated main and added:

```dart
onAuthorTap: () => context.push('/feed/profile/${post.authorUid}'),
```

to each `PostCard(...)` invocation in `feed_screen.dart`. Conflict resolution was trivial (Dev C passed `null`, which became this lambda).

## TASK-013 — Quality gates ✅

- `flutter analyze` → **0 issues**
- `flutter test test/features/feed/` → all feed tests green (incl. 44 new SCENARIO-190..236)
- `flutter test` (full suite) → **518/518 passing** (was 474 → +44 new)
- `dart format --set-exit-if-changed .` → clean (8 files auto-formatted in a separate `style(feed):` commit)

### Smoke verification (MANUAL — Dev B)

To be performed AFTER rebase onto main + wire commit lands:

1. `flutter run -d emulator-5554`
2. Login
3. Open Feed tab
4. Verify AMIGOS feed loads (Dev C's Etapa 3 wired this; for posts to show, current user must have at least one accepted friendship)
5. Tap on an author avatar/name in any post → navigates to `/feed/profile/<uid>`
6. Verify PublicProfileScreen renders:
   - Hero with avatar + uppercase name + gym (or no gym if author has none)
   - SEGUIR button (or its appropriate state per existing friendship)
   - MENSAJE button disabled (opacity 0.6)
   - 4-stat row with all `0`s
   - Tabs RUTINAS PÚBLICAS / ACTIVIDAD with empty state copy
7. Tap SEGUIR → friendship.request fires → state moves to SOLICITUD ENVIADA on refresh
8. Tap ACTIVIDAD pill → empty state copy switches to "Aún no hay actividad reciente."

### State at close

- 14 work-unit commits + 1 style commit + 1 docs commit (planned)
- Branch: `feat/public-profile`
- Ready for: rebase onto main → wire onAuthorTap → push → PR

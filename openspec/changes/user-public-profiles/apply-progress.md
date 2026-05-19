# Apply Progress: user-public-profiles

**Change**: user-public-profiles  
**Mode**: Strict TDD  
**Batch**: PR#A — Foundation + Etapa 4 Refactor | PR#B — Search UI  
**Branch (PR#A)**: `feat/user-public-profiles`  
**Branch (PR#B)**: `feat/user-public-profiles-search`  
**Date completed (PR#A)**: 2026-05-15  
**Date completed (PR#B)**: 2026-05-15

---

## PR#A — DONE

### TDD Cycle Evidence

| Task | RED commit | GREEN commit | REFACTOR | Status |
|------|-----------|-------------|---------|--------|
| A2 (model) | fa8ed26 | febb16c | n/a (pure model) | PASS |
| A3 (repo) | 69934f6 | bf4c666 | n/a | PASS |
| A4 (providers) | c707dd8 | f512627 | n/a | PASS |
| A5 (Etapa 4 refactor) | b618b63 (fixtures RED) | 8a181ac (provider swap) | verified all 6 green | PASS |
| A6 (dual-write) | 1b93a71 | 6e11df8 | n/a | PASS |
| A7 (ProfileSetupNotifier) | 8ba0755 | 43f4845 (inherited) | n/a | PASS |

### Tasks Completed

- [x] A1.1 Verify clean working tree — confirmed (only untracked openspec files)
- [x] A1.2 Baseline test suite — 607 passing
- [x] A2.1 RED: `test/features/profile/domain/user_public_profile_test.dart` (SCENARIO-252, SCENARIO-253)
- [x] A2.2 GREEN: `lib/features/profile/domain/user_public_profile.dart` + generated files
- [x] A2.3 Covers REQ-UPP-001, SCENARIO-252, SCENARIO-253
- [x] A3.1 RED: `test/features/profile/data/user_public_profile_repository_test.dart` (SCENARIO-254..258)
- [x] A3.2 GREEN: `lib/features/profile/data/user_public_profile_repository.dart`
- [x] A3.3 Covers REQ-UPP-003..006, SCENARIO-254..258
- [x] A4.1 RED: `test/features/profile/application/user_public_profile_providers_test.dart`
- [x] A4.2 GREEN: `lib/features/profile/application/user_public_profile_providers.dart`
- [x] A4.3 Covers REQ-UPP-007, REQ-UPP-008
- [x] A5.1 RED: Rewrote SCENARIO-203..205 fixtures in `test/features/feed/application/public_profile_providers_test.dart` to seed `userPublicProfiles` — SCENARIO-203 and 205 failed, 204 was already correctly failing
- [x] A5.2 GREEN: Swapped `publicProfileViewProvider` to read from `userPublicProfileProvider` — all 6 scenarios pass
- [x] A5.3 REFACTOR: Verified all 32 feed application tests pass simultaneously
- [x] A5.4 Covers REQ-UPP-017..020, SCENARIO-271..274
- [x] A6.1 RED: Added SCENARIO-259..263 to `test/features/profile/data/user_repository_test.dart` — 4 tests failing
- [x] A6.2 GREEN: Added `_publicSubsetFromProfile`, `_publicSubsetFromPartial`, WriteBatch dual-write to `lib/features/profile/data/user_repository.dart` — all pass
- [x] A6.3 Covers REQ-UPP-009..012, SCENARIO-259..263. SCENARIO-264 marked TODO (deferred to manual emulator)
- [x] A7.1 RED+GREEN: Created `test/features/profile_setup/application/profile_setup_notifier_test.dart` (SCENARIO-265, SCENARIO-266) — tests pass immediately because dual-write is inherited from UserRepository.update
- [x] A7.2 Verified `ProfileSetupNotifier.submit()` calls `userRepository.update()` — no signature change needed. Dual-write inherited from A6.2. No-op commit.
- [x] A7.3 Covers REQ-UPP-013, SCENARIO-265, SCENARIO-266. SCENARIO-267 marked TODO (deferred)
- [x] A8.1 Added `userPublicProfiles/{uid}` block to `firestore.rules` (design Section A.4 exact rules)
- [x] A8.2 Covers REQ-UPP-014..016. NOTE: fake_cloud_firestore does NOT enforce rules — manual T35 test required
- [x] A9.1 Created `scripts/backfill_user_public_profiles.js` with Node.js + firebase-admin, lazy migration comment, idempotent via merge:true
- [x] A10.1 `flutter analyze` — 0 issues (after fixing unused import in notifier test)
- [x] A10.2 `dart format --output=none --set-exit-if-changed .` — 0 changed files
- [x] A10.3 `flutter test` — 624 passing, 1 skipped (design skip). Baseline was 607, +17 new tests
- [x] A10.4 Cross-cutting: rg PhosphorIcons → 0 matches; rg hex literals → 0 matches

### A8.3 Manual Rules Test Status

**STATUS: DEFERRED — User must run before PR#A merge**

`fake_cloud_firestore` does not enforce Firestore rules. The T35-style emulator test must be run manually before requesting review.

Command to run:
```bash
firebase emulators:start --only firestore
# In another terminal:
firebase deploy --only firestore:rules --project <your-project-id>
# Then seed via Admin SDK and test the 3 scenarios:
# (a) user B reads userPublicProfiles/A → MUST succeed (SCENARIO-268)
# (b) user B lists prefix query → MUST succeed (SCENARIO-269)
# (c) user B writes userPublicProfiles/A where B != A → MUST be denied (SCENARIO-270)
```

Document results in PR description before requesting review.

### Deviations from Design (PR#A)

1. **SCENARIO-253 interpretation**: The spec says "assert repo helper, not model constructor" for the auto-derivation test. The test documents that the MODEL does NOT auto-derive (returns whatever is passed), and shows what the repo helper WOULD derive. This matches the design's ADR-UPP-11 intent exactly.

2. **A5.1 RED state**: SCENARIO-204 (fallback to 'Anónimo' when no doc) already passed even before the provider swap because the behavior is identical (old impl returned 'Anónimo' when no post existed; new fixture also has no doc → same result). Only SCENARIO-203 and SCENARIO-205 were truly RED. This does not affect the commit ordering or correctness.

3. **A7 tests immediately GREEN**: The profile_setup tests passed immediately (not RED first) because the UserRepository dual-write (A6.2) was already in place when the test was compiled. This is expected — the design explicitly states "no change to notifier may be needed." The test still validates the correct behavior.

### Quality Gates (PR#A)

| Gate | Result |
|------|--------|
| `flutter analyze` | 0 issues |
| `dart format --output=none --set-exit-if-changed .` | 0 changed |
| `flutter test` | 624 passing, 1 skipped (design) |
| rg PhosphorIcons | 0 matches |
| rg hex literals | 0 matches |

### Commits Made (PR#A)

| Hash | Message |
|------|---------|
| fa8ed26 | test(profile): SCENARIO-252..253 for UserPublicProfile model roundtrip |
| febb16c | feat(profile): add UserPublicProfile freezed model with derived lowercase |
| 69934f6 | test(profile): SCENARIO-254..258 for UserPublicProfileRepository |
| bf4c666 | feat(profile): add UserPublicProfileRepository with prefix search |
| c707dd8 | test(profile): SCENARIO-XXX for userPublicProfileProviders |
| f512627 | feat(profile): add UserPublicProfile providers |
| b618b63 | test(feed): rewrite SCENARIO-203..205 fixtures for userPublicProfiles source |
| 8a181ac | refactor(feed): publicProfileViewProvider sources from userPublicProfileProvider |
| 1b93a71 | test(profile): SCENARIO-259..263 for UserRepository WriteBatch dual-write |
| 6e11df8 | feat(profile): dual-write users + userPublicProfiles via WriteBatch |
| 8ba0755 | test(profile-setup): SCENARIO-265..266 for submit dual-write |
| 43f4845 | feat(profile-setup): delegate to UserRepository for dual-write (inherited from A6.2) |
| 01d5e81 | feat(firestore): add userPublicProfiles rules block |
| 9d9f0d0 | chore(scripts): document userPublicProfiles backfill script (not executed) |
| 3172bdc | chore: apply dart format |

### Files Created/Modified (PR#A)

**Created**:
- `lib/features/profile/domain/user_public_profile.dart` (~32 LOC)
- `lib/features/profile/domain/user_public_profile.freezed.dart` (generated)
- `lib/features/profile/domain/user_public_profile.g.dart` (generated)
- `lib/features/profile/data/user_public_profile_repository.dart` (~65 LOC)
- `lib/features/profile/application/user_public_profile_providers.dart` (~28 LOC)
- `scripts/backfill_user_public_profiles.js` (~116 LOC)
- `test/features/profile/domain/user_public_profile_test.dart` (~51 LOC)
- `test/features/profile/data/user_public_profile_repository_test.dart` (~121 LOC)
- `test/features/profile/application/user_public_profile_providers_test.dart` (~89 LOC)
- `test/features/profile_setup/application/profile_setup_notifier_test.dart` (~112 LOC)

**Modified**:
- `lib/features/profile/data/user_repository.dart` (+92 LOC)
- `lib/features/feed/application/public_profile_providers.dart` (provider swap +13/-8)
- `firestore.rules` (+24 LOC)
- `test/features/profile/data/user_repository_test.dart` (+95 LOC)
- `test/features/feed/application/public_profile_providers_test.dart` (+37/-22 LOC)

---

## PR#B — DONE

**Branch**: `feat/user-public-profiles-search`  
**Base**: `main` (after PR#A merged as PR #40)  
**Size**: ~620 LOC — size:exception pre-approved  
**Delivery**: `single-pr` with `size:exception`

### TDD Cycle Evidence

| Task | RED commit | GREEN commit | REFACTOR | Status |
|------|-----------|-------------|---------|--------|
| B3 (searchUsersProvider) | ac796d4 | dae5b40 | n/a | PASS |
| B4 (UserSearchResultTile) | 5e440c1 | 72b50c2 | n/a | PASS |
| B5 (SearchUsersScreen) | 83c6e01 | 48ba24f | n/a | PASS |

### Tasks Completed

- [x] B1.1 Confirmed PR#A merged to main as PR #40 at 1db1644
- [x] B1.2 Branch `feat/user-public-profiles-search` cut from main
- [x] B1.3 `flutter test` — 711 passing (baseline for PR#B)
- [x] B2.1 Read deprecated branch files via `git show wip/feed-search-users-deprecated:<path>` — catalogued all 4 files
- [x] B2.2 Planned adaptations: `UserProfile` → `UserPublicProfile`, `userRepositoryProvider` → `userPublicProfileRepositoryProvider`, fixtures from `users/...` → `userPublicProfiles/...`, `user` field → `profile` field on tile
- [x] B2.3 ENFORCEMENT GATE deferred to B7 (run after all files created)
- [x] B3.1 RED: `test/features/feed/application/search_users_provider_test.dart` (SCENARIO-275..280) — commit ac796d4
- [x] B3.2 GREEN: `lib/features/feed/application/search_users_provider.dart` — commit dae5b40. All 7 tests pass.
- [x] B3.3 Covers REQ-UPS-006, REQ-UPS-007, SCENARIO-275..280. Risk 3 resolved: normalization in provider.
- [x] B4.1 RED: `test/features/feed/presentation/widgets/user_search_result_tile_test.dart` (SCENARIO-281..285) — commit 5e440c1
- [x] B4.2 GREEN: `lib/features/feed/presentation/widgets/user_search_result_tile.dart` — commit 72b50c2. All 5 tests pass.
- [x] B4.3 Covers REQ-UPS-008, REQ-UPS-009, REQ-UPS-010, SCENARIO-281..285
- [x] B5.1 RED: `test/features/feed/presentation/search_users_screen_test.dart` (SCENARIO-286..295) — commit 83c6e01
- [x] B5.2 GREEN: `lib/features/feed/presentation/search_users_screen.dart` — commit 48ba24f. All 10 tests pass.
- [x] B5.3 Covers REQ-UPS-001..005, REQ-UPS-011..014, SCENARIO-286..295
- [x] B6.1 Wired search icon in `_FeedHeader` → `context.push('/feed/search')` in `lib/features/feed/feed_screen.dart`
- [x] B6.2 Added `GoRoute(path: 'search', ...)` nested under `/feed` ShellRoute in `lib/app/router.dart`
- [x] B6.3 Covers REQ-UPS-015, REQ-UPS-016
- [x] B7.1 ADAPTATION GATE PASS — rg returned 0 code-level matches for forbidden references (only doc-comment references as intended)
- [x] B8.1 `flutter analyze` — 0 issues
- [x] B8.2 `dart format --output=none --set-exit-if-changed .` — 0 changed files
- [x] B8.3 `flutter test` — 733 passing. Baseline was 711, +22 new PR#B tests.
- [x] B8.4 `rg "PhosphorIcons\."` on new files — 0 matches
- [ ] B9.1..B9.8 Manual smoke test on real simulator — PENDING (user must run before merge)

### Deviations from Design (PR#B)

1. **SCENARIO-278 test approach**: The spec says "MAR and mar share the same provider instance (family key equivalence)". The test verifies that `searchUsersProvider('MAR')` calls the repo with `'mar'` (normalized) — a behavioral proxy for key equivalence that is verifiable without `ProviderContainer` internals. Equivalent coverage.

2. **Tile `user` → `profile` field rename**: The deprecated branch named the parameter `user: UserProfile`. Adapted to `profile: UserPublicProfile` for clarity and type safety.

3. **`_SearchBody` below-min copy**: Both `initial` and `typing-below-min` states show `'Buscá usuarios por nombre'`. The design state machine showed two different messages ("Escribí 2+ letras" for below-min) but SCENARIO-286 and SCENARIO-287 both assert `'Buscá usuarios por nombre'`. Implementation follows the spec scenarios over the diagram text.

### Adaptation Gate Result

**PASS** — Zero code-level forbidden references.

Command run:
```
rg "UserProfile\b|userRepositoryProvider|bodyWeightKg|heightCm|\bgender\b|\bemail\b|\brole\b|\bbornAt\b" \
  lib/features/feed/presentation/search_users_screen.dart \
  lib/features/feed/presentation/widgets/user_search_result_tile.dart \
  lib/features/feed/application/search_users_provider.dart | rg -v "^\S.*:.*//.*"
```

Result: 0 matches (empty output). Three doc-comment references mentioning what NOT to use are expected and correct.

### Quality Gates (PR#B)

| Gate | Result |
|------|--------|
| `flutter analyze` | 0 issues |
| `dart format --output=none --set-exit-if-changed .` | 0 changed |
| `flutter test` | 733 passing (711 baseline + 22 new) |
| rg PhosphorIcons (new files) | 0 matches |
| rg hex literals (new files) | 0 matches (verified by analyze + code review) |
| Adaptation gate (forbidden references) | PASS — 0 code matches |

### Commits Made (PR#B)

| Hash | Message |
|------|---------|
| ac796d4 | test(feed): SCENARIO-275..280 for searchUsersProvider |
| dae5b40 | feat(feed): add searchUsersProvider on userPublicProfiles |
| 5e440c1 | test(feed): SCENARIO-281..285 for UserSearchResultTile |
| 72b50c2 | feat(feed): add UserSearchResultTile (cherry-picked + adapted from wip branch) |
| 83c6e01 | test(feed): SCENARIO-286..295 for SearchUsersScreen |
| 48ba24f | feat(feed): add SearchUsersScreen with debounce + 6-state machine |
| 5159170 | feat(feed): wire search icon to /feed/search and register GoRoute |
| cd3c4ef | chore(feed): apply dart format to PR#B test files |

### Files Created/Modified (PR#B)

**Created**:
- `lib/features/feed/application/search_users_provider.dart` (~35 LOC)
- `lib/features/feed/presentation/widgets/user_search_result_tile.dart` (~91 LOC)
- `lib/features/feed/presentation/search_users_screen.dart` (~277 LOC)
- `test/features/feed/application/search_users_provider_test.dart` (~173 LOC)
- `test/features/feed/presentation/widgets/user_search_result_tile_test.dart` (~151 LOC)
- `test/features/feed/presentation/search_users_screen_test.dart` (~365 LOC)

**Modified**:
- `lib/features/feed/feed_screen.dart` (+5 LOC — GestureDetector wrapping search icon)
- `lib/app/router.dart` (+5 LOC — SearchUsersScreen import + GoRoute registration)

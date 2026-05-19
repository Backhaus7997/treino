# Tasks: user-public-profiles

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines (PR#A) | ~510 (new files ~340 + modified files ~170) |
| Estimated changed lines (PR#B) | ~620 (new files ~470 + wiring ~150) |
| 400-line budget risk (PR#A) | Medium — size:exception needed |
| 400-line budget risk (PR#B) | High — size:exception needed |
| Chained PRs recommended | Yes |
| Suggested split | PR#A (foundation) → PR#B (search UI) |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | UserPublicProfile model + repo + providers + dual-write + Etapa 4 refactor + rules | PR#A | base = `feat/user-public-profiles`; ~510 LOC; size:exception |
| 2 | Search provider + tile widget + screen + routing wiring | PR#B | base = `main` after PR#A merges; `feat/user-public-profiles-search`; ~620 LOC; size:exception |

### Spec Risk Resolutions

**Risk 1 — REQ-UPP-002/012 auto-derive enforcement**
Resolved: Use `UserRepository` write-path discipline only. Private helpers `_publicSubsetFromProfile` and `_publicSubsetFromPartial` inside `user_repository.dart` centralize derivation (`displayName?.trim().toLowerCase()`). No sealed constructor or factory override needed — the Freezed model keeps `displayNameLowercase` as a nullable field (valid for JSON roundtrips), enforcement is at the single write-path chokepoint. This is the simplest option; it avoids Freezed constructor gymnastics and maintains test coverage via SCENARIO-263.

**Risk 2 — SCENARIO-264 atomicity**
Resolved: Marked as **manual integration test only — not blocking automated CI**. Faking a mid-commit batch failure is not reliably reproducible with `fake_cloud_firestore`. Document as a deferred test with a TODO comment in `user_repository_test.dart`. Automated test covers the happy path only. SCENARIO-264 is gated behind the T35-style manual emulator session.

**Risk 3 — SCENARIO-278 normalization site**
Resolved: Query normalization (toLowercase) happens INSIDE `searchUsersProvider`, NOT in `SearchUsersScreen`. The family key is the lowercased query string. The screen passes raw input; the provider normalizes. This is per design ADR and prevents the screen from duplicating business logic.

---

## PR#A Tasks — Foundation + Etapa 4 Refactor

**Branch**: `feat/user-public-profiles`
**Base**: `main`
**Size**: ~510 LOC — size:exception required

### Phase A1: Setup + Precondition

- [ ] A1.1 Verify clean working tree (`git status` — no uncommitted changes) before any code generation.
- [ ] A1.2 Confirm existing test suite baseline: run `flutter test` and record count (~677 passing). Commit baseline note.

### Phase A2: Domain — UserPublicProfile Model (RED → GREEN)

- [ ] A2.1 **RED**: Create `test/features/profile/domain/user_public_profile_test.dart`. Tests: SCENARIO-252 (JSON roundtrip), SCENARIO-253 (displayNameLowercase auto-derivation at write-path layer — assert repo helper, not model constructor). Commit test file. `flutter test` MUST fail at this point.
- [ ] A2.2 **GREEN**: Create `lib/features/profile/domain/user_public_profile.dart` (Freezed, 5 fields: `uid` required, `displayName?`, `displayNameLowercase?`, `avatarUrl?`, `gymId?`, all String). Run `dart run build_runner build --delete-conflicting-outputs`. Commit generated files. `flutter test` target tests MUST pass.
- [ ] A2.3 Covers: REQ-UPP-001, SCENARIO-252, SCENARIO-253.

### Phase A3: Repository — UserPublicProfileRepository (RED → GREEN)

- [ ] A3.1 **RED**: Create `test/features/profile/data/user_public_profile_repository_test.dart`. Tests: SCENARIO-254 (get null for missing), SCENARIO-255 (set + get roundtrip), SCENARIO-256 (prefix match), SCENARIO-257 (20-result limit), SCENARIO-258 (empty/blank query returns []). Commit test file. Tests MUST fail.
- [ ] A3.2 **GREEN**: Create `lib/features/profile/data/user_public_profile_repository.dart`. Implement `get(uid)`, `set(profile)` with `SetOptions(merge: true)`, `searchByDisplayName(query, {int limit = 20})` using prefix range on `displayNameLowercase`. Commit. Tests MUST pass.
- [ ] A3.3 Covers: REQ-UPP-003, REQ-UPP-004, REQ-UPP-005, REQ-UPP-006, SCENARIO-254..258.

### Phase A4: Providers — userPublicProfileRepositoryProvider + userPublicProfileProvider (RED → GREEN)

- [ ] A4.1 **RED**: Create `test/features/profile/application/user_public_profile_providers_test.dart`. Tests: `userPublicProfileProvider` resolves to null when no doc (SCENARIO-254 via provider), returns profile when doc exists (SCENARIO-255 via provider). Commit test file. Tests MUST fail.
- [ ] A4.2 **GREEN**: Create `lib/features/profile/application/user_public_profile_providers.dart`. Implement `userPublicProfileRepositoryProvider` (singleton `Provider`) and `userPublicProfileProvider` (`FutureProvider.family<UserPublicProfile?, String>` — auth-gated, returns null when unauthenticated). Commit. Tests MUST pass.
- [ ] A4.3 Covers: REQ-UPP-007, REQ-UPP-008.

### Phase A5: Etapa 4 Fixture Rewrite — CRITICAL, must precede A5.2 (RED → GREEN → REFACTOR)

- [ ] A5.1 **RED**: In `test/features/feed/application/public_profile_providers_test.dart`, rewrite SCENARIO-203..205 fixtures to seed `userPublicProfiles` collection instead of `posts`. Assertions remain behaviorally equivalent. Commit. Tests SCENARIO-203..205 MUST fail (provider still reads from old source). SCENARIO-200..202 MUST remain green.
- [ ] A5.2 **GREEN**: Modify `lib/features/feed/application/public_profile_providers.dart` — `publicProfileViewProvider` now reads `userPublicProfileProvider(targetUid)` instead of `firstPostByAuthorProvider`. Implement fallback to `'Anónimo'` when provider returns null. `firstPostByAuthorProvider` STAYS in the file untouched. Commit. SCENARIO-203..205 MUST pass. SCENARIO-200..202 MUST remain green.
- [ ] A5.3 **REFACTOR**: Run `flutter test test/features/feed/application/` — all 6 scenarios (200..205) must be green simultaneously.
- [ ] A5.4 Covers: REQ-UPP-017, REQ-UPP-018, REQ-UPP-019, REQ-UPP-020, SCENARIO-271..274.

### Phase A6: UserRepository Dual-Write (RED → GREEN)

- [ ] A6.1 **RED**: In `test/features/profile/data/user_repository_test.dart`, add tests for SCENARIO-259 (getOrCreate writes both), SCENARIO-260 (createIfAbsent writes both), SCENARIO-261 (update with displayName propagates), SCENARIO-262 (update without name/avatar/gym leaves public profile untouched), SCENARIO-263 (displayNameLowercase auto-derived, caller override ignored). Add TODO comment for SCENARIO-264 (atomicity — deferred, manual emulator only). Commit tests. Tests MUST fail.
- [ ] A6.2 **GREEN**: Modify `lib/features/profile/data/user_repository.dart`. Add private helpers `_publicSubsetFromProfile(...)` and `_publicSubsetFromPartial(...)` that derive `displayNameLowercase = displayName?.trim().toLowerCase()`. Replace sequential writes in `getOrCreate`, `createIfAbsent`, and `update` with `WriteBatch` dual-write pattern per design Section A.3. Commit. Tests MUST pass.
- [ ] A6.3 Covers: REQ-UPP-009, REQ-UPP-010, REQ-UPP-011, REQ-UPP-012, SCENARIO-259..263. SCENARIO-264 marked deferred.

### Phase A7: ProfileSetupNotifier Dual-Write Verification (RED → GREEN)

- [ ] A7.1 **RED**: In `test/features/profile_setup/application/profile_setup_notifier_test.dart` (or appropriate existing test file), add test for SCENARIO-265 (submit writes both docs), SCENARIO-266 (displayNameLowercase derived). Add TODO for SCENARIO-267 (commit failure — deferred, manual). Commit tests. Tests MUST fail.
- [ ] A7.2 **GREEN**: Verify `lib/features/profile_setup/application/profile_setup_notifier.dart` calls `userRepository.update(uid, partial)` without signature change. Since A6.2 already made UserRepository batch-aware, no change to notifier may be needed. If `submit()` calls `UserRepository.update`, the dual-write is inherited. Confirm and commit (no-op or minimal fix). Tests MUST pass.
- [ ] A7.3 Covers: REQ-UPP-013, SCENARIO-265, SCENARIO-266. SCENARIO-267 marked deferred.

### Phase A8: Firestore Rules

- [ ] A8.1 Add the `userPublicProfiles/{uid}` block to `firestore.rules` per design Section A.4 (read for auth != null; create with uid check; update with uid immutability; delete: false). Commit.
- [ ] A8.2 Covers: REQ-UPP-014, REQ-UPP-015, REQ-UPP-016. AUTOMATED TESTS NOT APPLICABLE — `fake_cloud_firestore` does not enforce rules.
- [ ] A8.3 **MANDATORY MANUAL GATE (pre-merge)**: Run T35-style emulator test. Start `firebase emulators:start`, deploy updated rules, seed via Admin SDK, attempt: (a) user B reads `userPublicProfiles/A` — MUST succeed (SCENARIO-268); (b) user B lists prefix query — MUST succeed (SCENARIO-269 semantics); (c) user B writes `userPublicProfiles/A` where B != A — MUST be denied (SCENARIO-269/270). Document results in PR description before requesting review.

### Phase A9: Backfill Script

- [ ] A9.1 Create `scripts/backfill_user_public_profiles.js`. Node.js + firebase-admin skeleton. Comment block explains: lazy migration is primary strategy (dual-write catches new profiles); script is ops escape hatch for existing users. Script logs every 100 docs, halts on error, uses `{merge: true}` for idempotency. NOT executed in PR#A. Commit.
- [ ] A9.2 Covers: REQ-UPP-021.

### Phase A10: Quality Gates

- [ ] A10.1 Run `flutter analyze` → 0 issues. Fix any lint violations before this step.
- [ ] A10.2 Run `dart format --output=none --set-exit-if-changed .` → 0 changed files.
- [ ] A10.3 Run `flutter test` → all passing. Expected: ~677 baseline + ~22 new PR#A tests = ~699 total.
- [ ] A10.4 Verify cross-cutting constraints: `rg "PhosphorIcons\." lib/features/profile/ lib/features/feed/application/public_profile_providers.dart` → 0 matches. `rg "#[0-9a-fA-F]{6}" lib/features/profile/ lib/features/feed/application/public_profile_providers.dart` → 0 matches.

### PR#A Coverage Matrix

| REQ | Covered by task(s) |
|-----|-------------------|
| REQ-UPP-001 | A2.2, A2.3 |
| REQ-UPP-002 | A2.1 (test), A6.2 (helper enforces derivation) |
| REQ-UPP-003 | A3.2 |
| REQ-UPP-004 | A3.1, A3.2 |
| REQ-UPP-005 | A3.1, A3.2 |
| REQ-UPP-006 | A3.1, A3.2 |
| REQ-UPP-007 | A4.2 |
| REQ-UPP-008 | A4.2 |
| REQ-UPP-009 | A6.1, A6.2 |
| REQ-UPP-010 | A6.1, A6.2 |
| REQ-UPP-011 | A6.1, A6.2 |
| REQ-UPP-012 | A6.2 (private helpers centralize derivation) |
| REQ-UPP-013 | A7.1, A7.2 |
| REQ-UPP-014 | A8.1 |
| REQ-UPP-015 | A8.3 (manual) |
| REQ-UPP-016 | A8.1 (no change to existing block) |
| REQ-UPP-017 | A5.2 |
| REQ-UPP-018 | A5.2 |
| REQ-UPP-019 | A5.3 |
| REQ-UPP-020 | A5.1, A5.2 |
| REQ-UPP-021 | A9.1 |
| REQ-UPP-022 | A10.4 |
| REQ-UPP-023 | A10.4 |
| REQ-UPP-024 | A10.2 (format) + code review |
| REQ-UPP-025 | Enforced by RED-before-GREEN commit discipline throughout A2–A7 |
| REQ-UPP-026 | A1.1 + `rg` gate in A10.4 |

---

## PR#B Tasks — Search UI

**Branch**: `feat/user-public-profiles-search`
**Base**: `main` (after PR#A merges)
**Size**: ~620 LOC — size:exception required

### Phase B1: Setup + Branch Cut

- [ ] B1.1 Confirm PR#A is merged to `main`. Pull latest main: `git checkout main && git pull`.
- [ ] B1.2 Cut new branch: `git checkout -b feat/user-public-profiles-search`.
- [ ] B1.3 Run `flutter test` to confirm clean baseline (expect ~699 from PR#A).

### Phase B2: Cherry-Pick Adaptation Checklist

- [ ] B2.1 Read deprecated branch files: `git show wip/feed-search-users-deprecated:lib/features/feed/presentation/search_users_screen.dart`, same for tile and provider. Do NOT checkout — read only.
- [ ] B2.2 Plan adaptations: `UserProfile` → `UserPublicProfile`, `userRepositoryProvider` → `userPublicProfileRepositoryProvider`, fixtures from `users/...` → `userPublicProfiles/...`.
- [ ] B2.3 **ENFORCEMENT GATE**: After creating all new PR#B files (B3–B5), run: `rg "UserProfile\b|userRepositoryProvider|bodyWeightKg|heightCm|\bgender\b|\bemail\b|\brole\b|\bbornAt\b" lib/features/feed/presentation/search_users_screen.dart lib/features/feed/presentation/widgets/user_search_result_tile.dart lib/features/feed/application/search_users_provider.dart` → MUST return 0 matches. Block PR#B merge if any match found.

### Phase B3: searchUsersProvider (RED → GREEN)

- [ ] B3.1 **RED**: Create `test/features/feed/application/search_users_provider_test.dart`. Tests: SCENARIO-275 (delegates to repo), SCENARIO-276 (blank query → []), SCENARIO-277 (1 char → []), SCENARIO-278 (normalization in provider — 'MAR' and 'mar' normalize to same key), SCENARIO-279 (no matches → []), SCENARIO-280 (repo error → AsyncError). Commit tests. Tests MUST fail.
- [ ] B3.2 **GREEN**: Create `lib/features/feed/application/search_users_provider.dart`. `FutureProvider.autoDispose.family<List<UserPublicProfile>, String>`. Normalize key to lowercase INSIDE provider. 2-char minimum gate. Delegate to `userPublicProfileRepositoryProvider.searchByDisplayName`. Commit. Tests MUST pass.
- [ ] B3.3 Covers: REQ-UPS-006, REQ-UPS-007, SCENARIO-275..280. Risk 3 resolved: normalization in provider, not screen.

### Phase B4: UserSearchResultTile (RED → GREEN)

- [ ] B4.1 **RED**: Create `test/features/feed/presentation/user_search_result_tile_test.dart`. Tests: SCENARIO-281 (renders avatar + displayName + gymName), SCENARIO-282 (null displayName no crash), SCENARIO-283 (tap → context.push('/feed/profile/u1')), SCENARIO-284 (no follow button), SCENARIO-285 (null gymId → blank, no crash). Commit tests. Tests MUST fail.
- [ ] B4.2 **GREEN**: Create `lib/features/feed/presentation/widgets/user_search_result_tile.dart`. StatelessWidget. Avatar 32px via `PostAvatar`. Display `displayName` and gym name via `gymNameFromId`. Tap calls `context.push('/feed/profile/$uid')`. `AppPalette.of(context)` for colors. `TreinoIcon.*` for icons. No follow button. Commit. Tests MUST pass.
- [ ] B4.3 Covers: REQ-UPS-008, REQ-UPS-009, REQ-UPS-010, SCENARIO-281..285.

### Phase B5: SearchUsersScreen (RED → GREEN)

- [ ] B5.1 **RED**: Create `test/features/feed/presentation/search_users_screen_test.dart`. Tests: SCENARIO-286 (initial empty prompt), SCENARIO-287 (1-char still shows empty prompt), SCENARIO-288 (loading → CircularProgressIndicator with palette.accent color), SCENARIO-289 (data → ListView with 3 tiles), SCENARIO-290 (empty results message contains query), SCENARIO-291 (error text visible), SCENARIO-292 (clear button appears when non-empty), SCENARIO-293 (clear resets field), SCENARIO-294 (back arrow pops navigator), SCENARIO-295 (header shows 'BUSCAR USUARIOS'). Commit tests. Tests MUST fail.
- [ ] B5.2 **GREEN**: Create `lib/features/feed/presentation/search_users_screen.dart`. `ConsumerStatefulWidget`. Local state: `TextEditingController`, debounce `Timer` (300 ms), `query` string. State machine: INITIAL → TYPING_BELOW_MIN → LOADING → {DATA, EMPTY_RESULTS, ERROR}. Header with back arrow + 'BUSCAR USUARIOS'. `FeedEmptyState` for initial and below-min states. `CircularProgressIndicator` (palette.accent) for loading. `ListView.separated` with 8 px separators for data. `FeedEmptyState` for empty results. Error text for error state. Does NOT add its own `Scaffold` (uses `_ShellScaffold`). Commit. Tests MUST pass.
- [ ] B5.3 Covers: REQ-UPS-001, REQ-UPS-002, REQ-UPS-003, REQ-UPS-004, REQ-UPS-005, REQ-UPS-011, REQ-UPS-012, REQ-UPS-013, REQ-UPS-014, SCENARIO-286..295.

### Phase B6: Integration — Feed Header + Router

- [ ] B6.1 Wrap search icon in `_FeedHeader` inside a `GestureDetector` that calls `context.push('/feed/search')` in `lib/features/feed/feed_screen.dart`. Commit.
- [ ] B6.2 Add `GoRoute(path: 'search', builder: (_, __) => const SearchUsersScreen())` nested under the `/feed` `ShellRoute` in `lib/app/router.dart`. Commit.
- [ ] B6.3 Covers: REQ-UPS-015, REQ-UPS-016, SCENARIO-296, SCENARIO-297.

### Phase B7: Privacy Enforcement Gate

- [ ] B7.1 Run the `rg` enforcement command from B2.3 against all three new PR#B production files. MUST return 0 matches. Document result. Block merge if any match found.

### Phase B8: Quality Gates

- [ ] B8.1 Run `flutter analyze` → 0 issues.
- [ ] B8.2 Run `dart format --output=none --set-exit-if-changed .` → 0 changed files.
- [ ] B8.3 Run `flutter test` → all passing. Expected: ~699 (PR#A) + ~24 new PR#B tests = ~723 total.
- [ ] B8.4 Cross-cutting constraints: `rg "PhosphorIcons\." lib/features/feed/presentation/search_users_screen.dart lib/features/feed/presentation/widgets/user_search_result_tile.dart lib/features/feed/application/search_users_provider.dart` → 0 matches.

### Phase B9: Manual Smoke Test (MANDATORY pre-merge)

- [ ] B9.1 Launch app on real simulator (iOS or Android). Login as a test athlete.
- [ ] B9.2 Navigate to feed. Tap search icon. Verify `SearchUsersScreen` opens with 'BUSCAR USUARIOS' header.
- [ ] B9.3 Type 1 character — verify empty prompt still shows (2-char minimum enforced).
- [ ] B9.4 Type 2+ characters — verify debounce fires, loading spinner appears, results show as `UserSearchResultTile` items.
- [ ] B9.5 Tap a result tile — verify navigation to `/feed/profile/$uid` (public profile screen).
- [ ] B9.6 Tap clear (X) — verify field clears and empty prompt reappears.
- [ ] B9.7 Tap back arrow — verify navigator pops.
- [ ] B9.8 Document smoke test results in PR description before requesting review.

### PR#B Coverage Matrix

| REQ | Covered by task(s) |
|-----|-------------------|
| REQ-UPS-001 | B5.2 |
| REQ-UPS-002 | B5.1, B5.2 |
| REQ-UPS-003 | B5.1, B5.2 |
| REQ-UPS-004 | B5.1, B5.2 |
| REQ-UPS-005 | B5.1, B5.2 |
| REQ-UPS-006 | B3.1, B3.2 |
| REQ-UPS-007 | B3.1, B3.2 |
| REQ-UPS-008 | B4.1, B4.2 |
| REQ-UPS-009 | B4.1, B4.2 |
| REQ-UPS-010 | B4.1, B4.2 |
| REQ-UPS-011 | B5.1, B5.2 |
| REQ-UPS-012 | B5.1, B5.2 |
| REQ-UPS-013 | B5.1, B5.2 |
| REQ-UPS-014 | B5.1, B5.2 |
| REQ-UPS-015 | B6.1 |
| REQ-UPS-016 | B6.2 |
| REQ-UPS-017 | B8.4 |
| REQ-UPS-018 | B8.4 |
| REQ-UPS-019 | B8.2 (format) + code review |
| REQ-UPS-020 | Enforced by RED-before-GREEN commit discipline throughout B3–B5 |

---

## Hard Constraint Checklist (both PRs)

| Constraint | Enforced by |
|-----------|------------|
| NO modify `UserProfile` model | A1.1 + rg gate in A10.4 |
| NO Firebase rule changes outside new `userPublicProfiles/{uid}` block | A8.1 reviewer check |
| NO Cloud Functions | architecture (no CF files created) |
| Colors via `AppPalette.of(context)` — no hex literals | A10.4, B8.4 rg gates |
| Icons via `TreinoIcon.X` — no `PhosphorIcons.X` | A10.4, B8.4 rg gates |
| Spacing 8/12/14/18/20 px only | code review at each PR |
| Strict TDD — test commits precede production commits | RED-before-GREEN discipline throughout |
| Manual rules test pre-merge (PR#A) | A8.3 |
| Cherry-pick rg enforcement gate (PR#B) | B2.3, B7.1 |
| Manual smoke test pre-merge (PR#B) | B9.1..B9.8 |

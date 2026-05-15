# Tasks: public-profile

**Change**: `public-profile`
**Fase / Etapa**: Fase 3 · Etapa 4
**Branch**: `feat/public-profile`
**TDD**: Strict — test file committed RED before production file in every step
**Delivery**: Single PR (production LOC well within 400-line budget)

---

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated production LOC | ~370 |
| Estimated test LOC | ~1345 |
| Estimated total diff | ~1715 LOC across 18 files |
| 400-line production budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | single-pr |
| Chain strategy | size-exception (test LOC only; production stays under 400) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | All 13 work-unit commits in `feat/public-profile` | PR #1 | Single PR — production LOC ≤ 400; total test LOC is expected but reviewable as widget/test pairs |

---

## Phase 1: Repository Layer (TASK-001)

### TASK-001a — `friendship_repository_get_by_pair_test.dart` RED
- [ ] Create `test/features/feed/data/friendship_repository_get_by_pair_test.dart`
- [ ] Write failing tests for SCENARIO-190 (returns Friendship when doc exists), SCENARIO-191 (returns null when no doc), SCENARIO-192 (order-invariant via sortedDocId)
- [ ] Use `FakeFirebaseFirestore`; verify RED before committing
- Commit: `test(friendship-repo): SCENARIO-190..192 — getByPair exists/null/sorted-id`
- Satisfies: REQ-PROFILE-REPO-001

### TASK-001b — `friendship_repository.dart` GREEN
- [ ] Add `Future<Friendship?> getByPair(String uidA, String uidB)` method to `lib/features/feed/data/friendship_repository.dart`
- [ ] Implement using `Friendship.sortedDocId(uidA, uidB)` + `_friendships.doc(id).get()` + `_fromDoc(snap)`
- [ ] Run TASK-001a tests → GREEN
- Commit: `test+feat(friendship-repo): add getByPair for deterministic doc lookup`
- Satisfies: REQ-PROFILE-REPO-001

---

## Phase 2: DTO + Domain Utilities (TASK-002, TASK-003-domain)

### TASK-002a — `public_profile_view_test.dart` RED
- [ ] Create `test/features/feed/domain/public_profile_view_test.dart`
- [ ] Write failing tests for SCENARIO-199 (structural equality) and SCENARIO-200 (isSelf inequality)
- Commit: `test(public-profile): SCENARIO-199..200 — PublicProfileView DTO equality`
- Satisfies: REQ-PROFILE-DTO-001

### TASK-002b — `public_profile_view.dart` GREEN + build_runner
- [ ] Create `lib/features/feed/domain/public_profile_view.dart` with `@freezed` class (5 fields, no `fromJson`/`toJson`, `part '*.freezed.dart'` only)
- [ ] Run `dart run build_runner build --delete-conflicting-outputs` to generate `.freezed.dart`
- [ ] Run TASK-002a tests → GREEN
- Commit: `test+feat(public-profile): add PublicProfileView freezed DTO`
- Satisfies: REQ-PROFILE-DTO-001

### TASK-003-domain-a — `gym_name_test.dart` RED
- [ ] Create `test/features/feed/domain/gym_name_test.dart`
- [ ] Write failing tests for SCENARIO-215: null→`''`, `'no-gym'`→`''`, known id→resolved name
- Commit: `test(public-profile): SCENARIO-215 — gymNameFromId null/no-gym/known`
- Satisfies: REQ-PROFILE-HERO-001

### TASK-003-domain-b — `gym_name.dart` GREEN
- [ ] Create `lib/features/feed/domain/gym_name.dart` with `gymNameFromId(String? gymId)` using `const _kGymNames` map + `kNoGymId` import from `gym.dart`
- [ ] Run TASK-003-domain-a tests → GREEN
- Commit: `test+feat(public-profile): add gymNameFromId utility`
- Satisfies: REQ-PROFILE-HERO-001

### TASK-004-domain — `profile_tab.dart` (no separate test)
- [ ] Create `lib/features/feed/domain/profile_tab.dart` with `enum ProfileTab { rutinas, actividad }`
- [ ] No test file — enum is exercised by screen tests in Phase 5
- Commit: `feat(public-profile): add ProfileTab enum`
- Satisfies: REQ-PROFILE-TABS-001

---

## Phase 3: Providers (TASK-003a..005b)

All three tasks extend the SAME test file (`public_profile_providers_test.dart`). Run only the relevant test group after each subtask.

### TASK-003a — `public_profile_providers_test.dart` RED — `friendshipByPairProvider`
- [ ] Create `test/features/feed/application/public_profile_providers_test.dart`
- [ ] Write failing tests for SCENARIO-193 (returns Friendship when authenticated), SCENARIO-194 (returns null when no doc), SCENARIO-195 (returns null when unauthenticated, repo NOT called)
- Commit: `test(public-profile): SCENARIO-193..195 — friendshipByPairProvider auth-gated`
- Satisfies: REQ-PROFILE-PROVIDER-001

### TASK-003b — `public_profile_providers.dart` GREEN — `friendshipByPairProvider`
- [ ] Create `lib/features/feed/application/public_profile_providers.dart`
- [ ] Add `typedef FriendshipPair` record + `friendshipByPairProvider` (autoDispose family, auth-gate, calls `repo.getByPair`)
- [ ] Run SCENARIO-193..195 group → GREEN
- Commit: `test+feat(public-profile): add friendshipByPairProvider (auth-gated)`
- Satisfies: REQ-PROFILE-PROVIDER-001

### TASK-004a — extend `public_profile_providers_test.dart` RED — `firstPostByAuthorProvider`
- [ ] Add failing tests for SCENARIO-196 (returns most recent Post), SCENARIO-197 (returns null when no posts), SCENARIO-198 (returns null when unauthenticated)
- Commit: `test(public-profile): SCENARIO-196..198 — firstPostByAuthorProvider auth-gated`
- Satisfies: REQ-PROFILE-PROVIDER-002

### TASK-004b — `public_profile_providers.dart` GREEN — `firstPostByAuthorProvider`
- [ ] Add `firstPostByAuthorProvider` to existing providers file (autoDispose family, auth-gate, Firestore query `where+orderBy+limit(1)` via `firestoreProvider`)
- [ ] Run SCENARIO-196..198 group → GREEN
- Commit: `test+feat(public-profile): add firstPostByAuthorProvider (auth-gated)`
- Satisfies: REQ-PROFILE-PROVIDER-002

### TASK-005a — extend `public_profile_providers_test.dart` RED — `publicProfileViewProvider`
- [ ] Add failing tests for SCENARIO-201 (full composition), SCENARIO-202 (Anónimo when no posts), SCENARIO-203 (isSelf skips friendship lookup)
- Commit: `test(public-profile): SCENARIO-201..203 — publicProfileViewProvider composition`
- Satisfies: REQ-PROFILE-PROVIDER-003

### TASK-005b — `public_profile_providers.dart` GREEN — `publicProfileViewProvider`
- [ ] Add `publicProfileViewProvider` with composition logic (isSelf derivation, friendship skip, required comment above `authorDisplayName` assignment)
- [ ] Run SCENARIO-201..203 group → GREEN
- Commit: `test+feat(public-profile): compose publicProfileViewProvider`
- Satisfies: REQ-PROFILE-PROVIDER-003

---

## Phase 4: Presentation Widgets (TASK-006..010)

### TASK-006a — `public_profile_hero_test.dart` RED
- [ ] Create `test/features/feed/presentation/widgets/public_profile_hero_test.dart`
- [ ] Write failing tests for SCENARIO-210 (avatar size 96), SCENARIO-211 (UPPERCASE name), SCENARIO-212 (gym subtitle when known), SCENARIO-213 (no subtitle when gymId null), SCENARIO-214 (PostAvatar '?' fallback for 'Anónimo')
- Commit: `test(public-profile): SCENARIO-210..214 — PublicProfileHero widget`
- Satisfies: REQ-PROFILE-HERO-001

### TASK-006b — `public_profile_hero.dart` GREEN
- [ ] Create `lib/features/feed/presentation/widgets/public_profile_hero.dart`
- [ ] Implement: gradient container (accent→bg), PostAvatar size:96, UPPERCASE display name (Barlow Condensed 700 size 24), conditional gym subtitle, `AppPalette.of(context)` tokens only
- [ ] Run TASK-006a tests → GREEN
- Commit: `test+feat(public-profile): add PublicProfileHero widget`
- Satisfies: REQ-PROFILE-HERO-001

### TASK-007a — `public_profile_stats_row_test.dart` RED
- [ ] Create `test/features/feed/presentation/widgets/public_profile_stats_row_test.dart`
- [ ] Write failing tests for SCENARIO-216 (4 labels rendered), SCENARIO-217 (exactly 4 `'0'` text widgets), SCENARIO-218 (4 tile children in Row)
- Commit: `test(public-profile): SCENARIO-216..218 — PublicProfileStatsRow widget`
- Satisfies: REQ-PROFILE-STATS-001

### TASK-007b — `public_profile_stats_row.dart` GREEN
- [ ] Create `lib/features/feed/presentation/widgets/public_profile_stats_row.dart`
- [ ] Implement: Row + 4 Expanded `_StatTile`s (WORKOUTS, RACHA in accent, SEGUIDORES, SIGUIENDO), all values `'0'`, stub comment `// Stub: real stats wired in Fase 4.`
- [ ] Run TASK-007a tests → GREEN
- Commit: `test+feat(public-profile): add PublicProfileStatsRow widget`
- Satisfies: REQ-PROFILE-STATS-001

### TASK-008a — `public_profile_follow_button_test.dart` RED
- [ ] Create `test/features/feed/presentation/widgets/public_profile_follow_button_test.dart`
- [ ] Write failing tests for SCENARIO-219..226 (all 4 states: SEGUIR, SOLICITUD ENVIADA, ACEPTAR, SIGUIENDO) + tap behaviors + no-ops
- Commit: `test(public-profile): SCENARIO-219..226 — PublicProfileFollowButton 4-state machine`
- Satisfies: REQ-PROFILE-FOLLOW-001

### TASK-008b — `public_profile_follow_button.dart` GREEN
- [ ] Create `lib/features/feed/presentation/widgets/public_profile_follow_button.dart`
- [ ] Implement ConsumerWidget with `_FollowPill` private widget, 4-state resolution, `ref.invalidate(friendshipByPairProvider(...))` after request/accept, `TreinoIcon.check` in SIGUIENDO state
- [ ] Run TASK-008a tests → GREEN
- Commit: `test+feat(public-profile): add PublicProfileFollowButton 4-state machine`
- Satisfies: REQ-PROFILE-FOLLOW-001

### TASK-009a — `public_profile_screen_test.dart` RED (tabs portion)
- [ ] Create `test/features/feed/presentation/public_profile_screen_test.dart`
- [ ] Write failing tests for SCENARIO-204..209 (3 async states + self-visit guard), SCENARIO-227..233 (MENSAJE + tabs + empty state), SCENARIO-235 (nav integration via `_wrapRouter`)
- Commit: `test(public-profile): SCENARIO-204..209,227..233,235 — PublicProfileScreen integration`
- Satisfies: REQ-PROFILE-SCREEN-001, REQ-PROFILE-SCREEN-002, REQ-PROFILE-TABS-001, REQ-PROFILE-TABS-002, REQ-PROFILE-FOLLOW-002, REQ-PROFILE-NAV-001

### TASK-009b — `public_profile_screen.dart` GREEN
- [ ] Create `lib/features/feed/presentation/public_profile_screen.dart`
- [ ] Implement: ConsumerWidget watching `publicProfileViewProvider`, AsyncData/Loading/Error routing, private `_ProfileTabPills` + `_ProfileTabBody` + `_MessageButtonStub`, `profileTabProvider.autoDispose.family`, no Scaffold/AppBackground/SafeArea
- [ ] Run TASK-009a tests → GREEN
- Commit: `test+feat(public-profile): assemble PublicProfileScreen with tabs + nav`
- Satisfies: REQ-PROFILE-SCREEN-001, REQ-PROFILE-SCREEN-002, REQ-PROFILE-TABS-001, REQ-PROFILE-TABS-002, REQ-PROFILE-FOLLOW-002

---

## Phase 5: Routing + Conditional Wire (TASK-010..012)

### TASK-010 — Router: add `/feed/profile/:uid` nested GoRoute
- [ ] Amend `lib/app/router.dart`: add `GoRoute(path: 'profile/:uid', builder: (ctx, state) => PublicProfileScreen(targetUid: state.pathParameters['uid']!))` as child of `/feed` GoRoute
- [ ] Add import for `PublicProfileScreen`
- [ ] Verify SCENARIO-234 passes (covered by screen integration test)
- Commit: `feat(router): add /feed/profile/:uid route`
- Satisfies: REQ-PROFILE-ROUTE-001

### TASK-011 — CONDITIONAL: wire `PostCard.onAuthorTap` in `feed_screen.dart`
- [ ] Check if Etapa 3 (`feed-segments`) has merged into `main`
- [ ] **Path 1 (merged)**: rebase `feat/public-profile` onto `main`; add `onAuthorTap: (uid) => context.push('/feed/profile/$uid')` to every `PostCard(...)` in `lib/features/feed/feed_screen.dart`; commit `wire: PostCard.onAuthorTap → /feed/profile/:uid`; verify SCENARIO-235 green
- [ ] **Path 2 (not merged)**: record `DEFERRED-WIRE` in `apply-progress`; do NOT modify `feed_screen.dart`; file applies after Etapa 3 merges before PR is marked Ready for Review
- Commit (Path 1 only): `wire: PostCard.onAuthorTap → /feed/profile/:uid`
- Satisfies: REQ-PROFILE-WIRE-001

---

## Phase 6: Quality Gates (TASK-012)

### TASK-012 — Quality gates (no commit)
- [ ] `flutter analyze` → 0 issues
- [ ] `dart format .` → tree clean
- [ ] `flutter test` → all green; SCENARIO-190..235 covered (SCENARIO-236 trivially satisfied — `TreinoIcon.check` already exists per design §1 note)
- [ ] Grep `0x[0-9A-Fa-f]{8}` and `Color\(0x` in changed files → 0 matches in new code
- [ ] Grep `PhosphorIcons` in `lib/features/feed/presentation/public_profile_*.dart` and `widgets/public_profile_*.dart` → 0 matches
- [ ] Grep `feed_segment_pills` in `public_profile_screen.dart` → 0 matches
- [ ] `git diff main -- lib/features/feed/application/friendship_providers.dart lib/features/feed/application/feed_screen_providers.dart` → empty
- [ ] `git diff main -- lib/features/feed/presentation/widgets/post_card.dart` → empty
- [ ] `git diff --stat main -- lib/` → production LOC ≤ 400
- [ ] If Path 1: `git log --oneline main..HEAD` includes `wire: PostCard.onAuthorTap` commit; if Path 2: `apply-progress` has `DEFERRED-WIRE` marker
- Satisfies: REQ-PROFILE-SCREEN-001 (SCENARIO-207), REQ-PROFILE-ICON-001, global quality constraint

---

## Task Summary

| Phase | Tasks | Strict TDD | Key artifact |
|-------|-------|-----------|--------------|
| 1 — Repository | TASK-001a/b | Yes | `friendship_repository.dart` |
| 2 — Domain | TASK-002a/b, 003-domain-a/b, 004-domain | Yes (except enum) | `public_profile_view.dart`, `gym_name.dart`, `profile_tab.dart` |
| 3 — Providers | TASK-003a/b, 004a/b, 005a/b | Yes | `public_profile_providers.dart` |
| 4 — Widgets | TASK-006a/b, 007a/b, 008a/b, 009a/b | Yes | `public_profile_hero/stats_row/follow_button/screen.dart` |
| 5 — Routing | TASK-010, TASK-011 (conditional) | No | `router.dart`, `feed_screen.dart` (optional) |
| 6 — Quality | TASK-012 | — | (verification only) |
| **Total** | **26 subtasks** | — | **18 new files, 2-3 modified** |

Sequential dependencies: Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6.
Within Phase 3, TASK-003a/b → TASK-004a/b → TASK-005a/b (each extends the same test file).
TASK-011 (conditional) is independent of Phase 4 widgets but requires TASK-010 (route must exist first).

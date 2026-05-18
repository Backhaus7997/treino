# Tasks: feed-create-search (Fase 3 · Etapa 5)

**Change**: `feed-create-search`
**Artifact store**: hybrid
**TDD mode**: Strict (test commit BEFORE implementation commit, per `strict-tdd.md`)

---

## Review Workload Forecast

### PR#1 Forecast — `feat/feed-create-post`

| Field | Value |
|---|---|
| Estimated changed lines | ~300 prod + ~490 test ≈ 790 LOC total |
| Production-only LOC | ~305 (incl. token precursors ~5 LOC) |
| 400-line budget risk | **Low** (prod diff well within budget; test files inflate total but are expected) |
| Suggested split | Single PR — no sub-split needed |
| Decision needed before apply | No |

### PR#2 Forecast — `feat/feed-search-users`

| Field | Value |
|---|---|
| Estimated changed lines | ~370 prod + ~600 test ≈ 970 LOC total |
| Production-only LOC | ~370 (model +5, repo +35, profileSetup +2, screen +170, tile +95, provider +50, wire +13) |
| 400-line budget risk | **Medium** (prod diff near 400; reviewable in ~60 min as a single pass given small files) |
| Suggested split | Single PR — no sub-split recommended (see rationale below) |
| Decision needed before apply | No |

**PR#2 sub-split rationale**: The design estimated 365-405 prod LOC. Refined estimate lands at ~370 prod LOC — just under 400. The files are small and cohesive (model field + 4 write sites + 1 provider + 1 tile + 1 screen). Sub-splitting into PR#2a/PR#2b would produce an orphaned model/repo PR that cannot be demo'd in isolation. Single PR with `size:exception` pre-approved if reviewer flags it; expected review time ~55 min.

```
Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Low
```

_(PR#1 is Low; PR#2 is Medium. Guard lines reflect the riskier PR. Both PRs are chained — PR#2 cannot start until PR#1 lands on main.)_

### Suggested Work Units

| Unit | Goal | PR | Notes |
|---|---|---|---|
| 1 | Token precursors (danger + dumbbell + chevronLeft/Right) | PR#1 | Unblocks both PRs; committed as `chore:` before RED |
| 2 | CreatePostNotifier (RED → GREEN) | PR#1 | Notifier tests then impl |
| 3 | CreatePostScreen (RED → GREEN) | PR#1 | Screen tests then impl |
| 4 | Wire + route + quality gates | PR#1 | Completes PR#1 |
| 5 | UserProfile field + repo (RED → GREEN) | PR#2 | Model, search, write sites |
| 6 | ProfileSetup write site (RED → GREEN) | PR#2 | Depends on Unit 5 |
| 7 | SearchUsersProvider (RED → GREEN) | PR#2 | Depends on Unit 5 |
| 8 | UserSearchResultTile (RED → GREEN) | PR#2 | Depends on Unit 5+7 |
| 9 | SearchUsersScreen (RED → GREEN) | PR#2 | Depends on all above |
| 10 | Wire + route + quality gates | PR#2 | Completes PR#2 |

---

## Design Risk Resolutions

### Risk 1 — PR#2 sub-split decision
**Resolution**: NO sub-split. Refined prod LOC estimate is ~370, just under 400. Files are small and self-contained. Single PR is reviewable in ~55 min. If reviewer flags size, apply `size:exception`. Tasks are organized as a single Batch 2.

### Risk 2 — Token verification
**Resolution**: Three tokens are MISSING from existing files:
- `palette.danger` — NOT in `AppPalette` (fields: accent, highlight, bg, bgCard, border, textPrimary, textMuted, sage, espresso). **Precursor task T01 added** to add `danger: Color(0xFFE53935)` to `AppPalette`.
- `TreinoIcon.dumbbell` — NOT in `TreinoIcon`. Closest is `tabWorkout = barbell`. **Precursor task T02 added** to add `dumbbell = PhosphorIconsRegular.barbell` as a semantic alias for the routine chip context.
- `TreinoIcon.chevronLeft` / `TreinoIcon.chevronRight` — NOT in `TreinoIcon`. Has `back = caretLeft` and `forward = caretRight` but not these semantic names. **Precursor task T02 extended** to add both aliases.
Both precursor tasks ship in PR#1 batch so PR#2 can consume them.

### Risk 3 — Test fixtures for `displayNameLowercase`
**Resolution**: Audited all test files. `UserProfile(` appears in 2 files:
- `test/features/profile/domain/user_profile_test.dart` — 4 calls (all use named params; nullable optional field = 0 broken sites)
- `test/features/profile/data/user_repository_test.dart` — 1 call inside `seedDoc()` helper
Adding `String? displayNameLowercase` as a nullable optional field to the freezed factory is **non-breaking** — existing constructors need no modification (freezed treats absent optional named params as null). **No `fakeUser()` helper needed.** Task T23 notes this and asks the apply agent to confirm zero compilation errors after `build_runner` regen.

---

## Batch 1 — PR#1: `feat/feed-create-post` (targets `main`)

### SETUP tasks

| ID | Phase | File | Action | REQ | SCENARIO | Est. LOC | Deps |
|---|---|---|---|---|---|---|---|
| ~~T01~~ | SETUP | `lib/app/theme/app_palette.dart` | **[x] DONE** Add `final Color danger` field to `AppPalette`; set to `Color(0xFFE53935)` in `mintMagenta`; add to `copyWith`, `lerp`, constructor | REQ-FCP-012, REQ-FCP-015 | SCENARIO-229, SCENARIO-233 | ~10 | — |
| ~~T02~~ | SETUP | `lib/core/widgets/treino_icon.dart` | **[x] DONE** Add `dumbbell`, `chevronLeft`, `chevronRight` entries as Phosphor aliases under `// Feed / social` | REQ-FCP-008, REQ-FCP-015, REQ-FSU-003 | SCENARIO-226, SCENARIO-236 | ~4 | — |
| ~~T03~~ | SETUP | `test/features/feed/application/create_post_notifier_test.dart` | **[x] DONE** Create file with full test suite (12 tests) | REQ-FCP-009, REQ-FCP-016 | SCENARIO-227..231 | ~15 | T01 |

### RED tasks (failing tests first)

| ID | Phase | File | Action | REQ | SCENARIO | Est. LOC | Deps |
|---|---|---|---|---|---|---|---|
| ~~T04~~ | RED | `test/features/feed/application/create_post_notifier_test.dart` | **[x] DONE** setText/setPrivacy/canSubmit/char limit tests | REQ-FCP-004, REQ-FCP-005, REQ-FCP-009 | SCENARIO-221..223 | ~60 | T03 |
| ~~T05~~ | RED | `test/features/feed/application/create_post_notifier_test.dart` | **[x] DONE** submit success + gym-gate tests | REQ-FCP-010, REQ-FCP-011, REQ-FCP-007 | SCENARIO-227, SCENARIO-231 | ~60 | T04 |
| ~~T06~~ | RED | `test/features/feed/application/create_post_notifier_test.dart` | **[x] DONE** submit error path + isSubmitting guard tests | REQ-FCP-012, REQ-FCP-014 | SCENARIO-228, SCENARIO-229 | ~50 | T05 |
| ~~T07~~ | RED | `test/features/feed/presentation/create_post_screen_test.dart` | **[x] DONE** form structure widget tests | REQ-FCP-003, REQ-FCP-016 | SCENARIO-220 | ~40 | T03 |
| ~~T08~~ | RED | `test/features/feed/presentation/create_post_screen_test.dart` | **[x] DONE** PUBLICAR enabled/disabled + char counter + privacy default | REQ-FCP-004, REQ-FCP-005, REQ-FCP-006 | SCENARIO-221..224 | ~50 | T07 |
| ~~T09~~ | RED | `test/features/feed/presentation/create_post_screen_test.dart` | **[x] DONE** gym pill disabled + routine stub chip tests | REQ-FCP-007, REQ-FCP-008 | SCENARIO-225, SCENARIO-226 | ~40 | T08 |
| ~~T10~~ | RED | `test/features/feed/presentation/create_post_screen_test.dart` | **[x] DONE** CANCELAR pops + spinner + error inline tests | REQ-FCP-012, REQ-FCP-013, REQ-FCP-014 | SCENARIO-228..230 | ~50 | T09 |

### GREEN tasks (implementation)

| ID | Phase | File | Action | REQ | SCENARIO | Est. LOC | Deps |
|---|---|---|---|---|---|---|---|
| ~~T11~~ | GREEN | `lib/features/feed/application/create_post_notifier.dart` | **[x] DONE** CreatePostState + CreatePostNotifier + createPostNotifierProvider | REQ-FCP-009, REQ-FCP-010 | SCENARIO-221..231 | ~110 | T06 |
| ~~T12~~ | GREEN | `lib/features/feed/presentation/create_post_screen.dart` | **[x] DONE** CreatePostScreen with all widgets | REQ-FCP-003..008, REQ-FCP-012..015 | SCENARIO-220..226, SCENARIO-229..233 | ~190 | T11, T10 |

### INTEGRATE tasks

| ID | Phase | File | Action | REQ | SCENARIO | Est. LOC | Deps |
|---|---|---|---|---|---|---|---|
| ~~T13~~ | INTEGRATE | `lib/features/feed/feed_screen.dart` | **[x] DONE** Plus button wired to /feed/create | REQ-FCP-002 | SCENARIO-219 | ~5 | T12 |
| ~~T14~~ | INTEGRATE | `lib/app/router.dart` | **[x] DONE** GoRoute(path: 'create') added under /feed | REQ-FCP-001 | SCENARIO-218 | ~7 | T13 |

### GATE tasks

| ID | Phase | File | Action | REQ | SCENARIO | Est. LOC | Deps |
|---|---|---|---|---|---|---|---|
| ~~T15~~ | GATE | — | **[x] DONE** flutter analyze → 0 issues (added `characters: ^1.3.0` to pubspec) | REQ-FCP-015 | — | 0 | T14 |
| ~~T16~~ | GATE | — | **[x] DONE** dart format → 0 changed files | REQ-FCP-015 | — | 0 | T15 |
| ~~T17~~ | GATE | — | **[x] DONE** flutter test → 565 tests passing (+27 new) | REQ-FCP-016 | SCENARIO-218..233 | 0 | T16 |

**PR#1 task count**: 17 tasks (T01–T17)
**PR#1 estimated prod LOC**: ~326 (T01~10 + T02~4 + T11~110 + T12~190 + T13~5 + T14~7)
**PR#1 estimated test LOC**: ~365 (T04~60 + T05~60 + T06~50 + T07~40 + T08~50 + T09~40 + T10~50 + T03~15)

---

## Batch 2 — PR#2: `feat/feed-search-users` (targets `main`, after PR#1 merged)

> **Prerequisite**: PR#1 merged to `main`. Pull `main`, cut `feat/feed-search-users` from `main`.

### SETUP tasks

| ID | Phase | File | Action | REQ | SCENARIO | Est. LOC | Deps |
|---|---|---|---|---|---|---|---|
| T18 | SETUP | — | Confirm PR#1 merged: `git pull origin main` → `git checkout -b feat/feed-search-users` | — | — | 0 | PR#1 merged |

### RED tasks

| ID | Phase | File | Action | REQ | SCENARIO | Est. LOC | Deps |
|---|---|---|---|---|---|---|---|
| T19 | RED | `test/features/profile/domain/user_profile_test.dart` | Add test group: `displayNameLowercase` roundtrip (field present → parsed correctly; field absent → null; confirm existing tests still compile without passing the param) | REQ-FSU-008 | SCENARIO-244 | ~25 | T18 |
| T20 | RED | `test/features/profile/data/user_repository_test.dart` | Add test group: `searchByDisplayName` — prefix match returns ≤20; case-insensitive lowercase match; empty query returns []; ≥21 docs returns exactly 20 | REQ-FSU-007, REQ-FSU-008 | SCENARIO-242, SCENARIO-243 | ~70 | T18 |
| T21 | RED | `test/features/profile/data/user_repository_test.dart` | Add tests: `getOrCreate` writes `displayNameLowercase: null`; `createIfAbsent` writes `displayNameLowercase: null`; `update({'displayName': 'X'})` auto-derives `displayNameLowercase: 'x'` | REQ-FSU-009, REQ-FSU-010 | SCENARIO-245, SCENARIO-246 | ~50 | T20 |
| T22 | RED | `test/features/profile_setup/application/profile_setup_notifier_test.dart` | Create file (if not exists) or add group: `submit()` includes `displayNameLowercase: draft.username.trim().toLowerCase()` in Firestore write partial | REQ-FSU-011 | SCENARIO-247 | ~35 | T18 |
| T23 | RED | `test/features/feed/application/search_users_provider_test.dart` | Create file: failing tests for `searchUsersProvider` — query < 2 chars returns []; query ≥ 2 chars delegates to `UserRepository.searchByDisplayName`; provider is autoDispose family | REQ-FSU-006 | SCENARIO-241 | ~40 | T18 |
| T24 | RED | `test/features/feed/presentation/widgets/user_search_result_tile_test.dart` | Create file: failing widget tests — renders PostAvatar + display name + gym name; NO follow button; tap calls onTap | REQ-FSU-012, REQ-FSU-013 | SCENARIO-248, SCENARIO-249 | ~50 | T18 |
| T25 | RED | `test/features/feed/presentation/search_users_screen_test.dart` | Create file: failing widget tests — screen structure (back arrow + TextField + placeholder); clear button absent when empty, present when non-empty, clears on tap; initial state shows empty-state widget; typing <2 chars shows threshold message | REQ-FSU-003, REQ-FSU-005 | SCENARIO-236..239 | ~50 | T18 |
| T26 | RED | `test/features/feed/presentation/search_users_screen_test.dart` | Add failing tests: debounce suppresses intermediate queries; ≥2 chars after 300ms fires searchUsersProvider; loading state shows spinner; empty results shows empty-state; error state shows inline text | REQ-FSU-004, REQ-FSU-014, REQ-FSU-015, REQ-FSU-016 | SCENARIO-239..241, SCENARIO-250, SCENARIO-251 | ~60 | T25 |

### GREEN tasks

| ID | Phase | File | Action | REQ | SCENARIO | Est. LOC | Deps |
|---|---|---|---|---|---|---|---|
| T27 | GREEN | `lib/features/profile/domain/user_profile.dart` | Add `String? displayNameLowercase` optional field after `displayName` in freezed factory; run `dart run build_runner build --delete-conflicting-outputs` | REQ-FSU-008 | SCENARIO-244 | ~5 (+regen) | T19 |
| T28 | GREEN | `lib/features/profile/data/user_repository.dart` | Add `searchByDisplayName(String q)` with range query (`isGreaterThanOrEqualTo: lower`, `isLessThan: lower + ''`, `limit(20)`); update `getOrCreate` + `createIfAbsent` to write `displayNameLowercase: null`; update `update()` to auto-derive `displayNameLowercase` when `displayName` key is present in partial | REQ-FSU-007, REQ-FSU-009, REQ-FSU-010 | SCENARIO-242..246 | ~35 | T27, T21 |
| T29 | GREEN | `lib/features/profile_setup/application/profile_setup_notifier.dart` | In `submit()` partial map, add `'displayNameLowercase': draft.username?.trim().toLowerCase()` | REQ-FSU-011 | SCENARIO-247 | ~2 | T28, T22 |
| T30 | GREEN | `lib/features/feed/application/search_users_provider.dart` | Create file: `searchUsersProvider = FutureProvider.autoDispose.family<List<UserProfile>, String>` + `kSearchMinChars = 2` guard; delegates to `userRepositoryProvider.searchByDisplayName` | REQ-FSU-006 | SCENARIO-241 | ~50 | T28, T23 |
| T31 | GREEN | `lib/features/feed/presentation/widgets/user_search_result_tile.dart` | Create file: `UserSearchResultTile` (`StatelessWidget`, params: `user: UserProfile, onTap: VoidCallback`); Row: PostAvatar(size:40) + name (Barlow Condensed 16 w700 uppercase) + gym via `gymNameFromId` + `TreinoIcon.chevronRight`; no follow button | REQ-FSU-012, REQ-FSU-013 | SCENARIO-248, SCENARIO-249 | ~95 | T30, T24 |
| T32 | GREEN | `lib/features/feed/presentation/search_users_screen.dart` | Create file: `SearchUsersScreen` (`ConsumerStatefulWidget`); `_SearchUsersHeader` (back + title); `_SearchTextField` (controller + clear X button); Timer debounce 300ms; 6-state `_SearchBody` (`initial`/`typing-below-min`/`loading`/`data`/`empty-results`/`error`); all tokens via `AppPalette.of(context)` + `TreinoIcon.X` | REQ-FSU-003..005, REQ-FSU-014..017 | SCENARIO-236..241, SCENARIO-250, SCENARIO-251 | ~170 | T31, T26 |

### INTEGRATE tasks

| ID | Phase | File | Action | REQ | SCENARIO | Est. LOC | Deps |
|---|---|---|---|---|---|---|---|
| T33 | INTEGRATE | `lib/features/feed/feed_screen.dart` | Wrap `Icon(TreinoIcon.search)` (line 62) in `GestureDetector(onTap: () => context.push('/feed/search'), hitTestBehavior: HitTestBehavior.opaque)` | REQ-FSU-002 | SCENARIO-235 | ~5 | T32 |
| T34 | INTEGRATE | `lib/app/router.dart` | Add `GoRoute(path: 'search', pageBuilder: (_, __) => _noAnim(const SearchUsersScreen()))` nested under `/feed` ShellRoute + import | REQ-FSU-001 | SCENARIO-234 | ~7 | T33 |

### GATE tasks

| ID | Phase | File | Action | REQ | SCENARIO | Est. LOC | Deps |
|---|---|---|---|---|---|---|---|
| T35 | GATE | — | Run `flutter analyze` → expect 0 issues | REQ-FSU-017 | — | 0 | T34 |
| T36 | GATE | — | Run `dart format --output=none --set-exit-if-changed .` → expect 0 changed files | REQ-FSU-017 | — | 0 | T35 |
| T37 | GATE | — | Run `flutter test` → all tests passing (all existing + new profile + feed search tests) | REQ-FSU-018 | SCENARIO-234..251 | 0 | T36 |

**PR#2 task count**: 20 tasks (T18–T37)
**PR#2 estimated prod LOC**: ~369 (T27~5 + T28~35 + T29~2 + T30~50 + T31~95 + T32~170 + T33~5 + T34~7)
**PR#2 estimated test LOC**: ~380 (T19~25 + T20~70 + T21~50 + T22~35 + T23~40 + T24~50 + T25~50 + T26~60)

---

## REQ Coverage Matrix

### PR#1 — REQ-FCP-* Coverage

| REQ | Tasks |
|---|---|
| REQ-FCP-001 (route) | T14 |
| REQ-FCP-002 (plus nav) | T13 |
| REQ-FCP-003 (form composition) | T07, T12 |
| REQ-FCP-004 (char limit) | T04, T08, T11, T12 |
| REQ-FCP-005 (PUBLICAR enabled) | T04, T08, T11, T12 |
| REQ-FCP-006 (privacy default) | T08, T11, T12 |
| REQ-FCP-007 (gym pill disabled) | T09, T11, T12 |
| REQ-FCP-008 (routine stub) | T02, T09, T12 |
| REQ-FCP-009 (notifier) | T04..T06, T11 |
| REQ-FCP-010 (post construction) | T05, T11 |
| REQ-FCP-011 (success UX) | T05, T11 |
| REQ-FCP-012 (error UX) | T01, T06, T10, T11, T12 |
| REQ-FCP-013 (CANCELAR) | T10, T12 |
| REQ-FCP-014 (submitting state) | T06, T10, T11, T12 |
| REQ-FCP-015 (design constraints) | T01, T02, T12, T15, T16 |
| REQ-FCP-016 (TDD) | T03..T10, T17 |

### PR#2 — REQ-FSU-* Coverage

| REQ | Tasks |
|---|---|
| REQ-FSU-001 (route) | T34 |
| REQ-FSU-002 (search nav) | T33 |
| REQ-FSU-003 (screen composition) | T02, T25, T32 |
| REQ-FSU-004 (debounce + min query) | T26, T32 |
| REQ-FSU-005 (initial state) | T25, T32 |
| REQ-FSU-006 (searchUsersProvider) | T23, T30 |
| REQ-FSU-007 (searchByDisplayName) | T20, T28 |
| REQ-FSU-008 (displayNameLowercase) | T19, T27 |
| REQ-FSU-009 (write on create) | T21, T28 |
| REQ-FSU-010 (write on update) | T21, T28 |
| REQ-FSU-011 (write on ProfileSetup) | T22, T29 |
| REQ-FSU-012 (UserSearchResultTile) | T24, T31 |
| REQ-FSU-013 (no inline follow) | T24, T31 |
| REQ-FSU-014 (no-results state) | T26, T32 |
| REQ-FSU-015 (loading state) | T26, T32 |
| REQ-FSU-016 (error state) | T26, T32 |
| REQ-FSU-017 (design constraints) | T02, T32, T35, T36 |
| REQ-FSU-018 (TDD) | T19..T26, T37 |

---

## SCENARIO Coverage Matrix

| SCENARIO | PR | Task(s) |
|---|---|---|
| 218 (route create) | PR#1 | T14 |
| 219 (plus nav) | PR#1 | T13 |
| 220 (form structure) | PR#1 | T07, T12 |
| 221 (char counter) | PR#1 | T04, T08, T11, T12 |
| 222 (PUBLICAR disabled) | PR#1 | T04, T08, T11, T12 |
| 223 (PUBLICAR enabled) | PR#1 | T04, T08, T11, T12 |
| 224 (privacy default) | PR#1 | T08, T11, T12 |
| 225 (gym pill disabled) | PR#1 | T09, T11, T12 |
| 226 (routine stub) | PR#1 | T02, T09, T12 |
| 227 (success) | PR#1 | T05, T11 |
| 228 (submitting state) | PR#1 | T06, T10, T11, T12 |
| 229 (submit error) | PR#1 | T01, T06, T10, T11, T12 |
| 230 (CANCELAR) | PR#1 | T10, T12 |
| 231 (gym guard) | PR#1 | T05, T11 |
| 232 (keyboard scroll) | PR#1 | T12 (ScrollView impl) |
| 233 (design tokens) | PR#1 | T01, T02, T12, T15 |
| 234 (route search) | PR#2 | T34 |
| 235 (search nav) | PR#2 | T33 |
| 236 (screen structure) | PR#2 | T25, T32 |
| 237 (clear button appears) | PR#2 | T25, T32 |
| 238 (clear button clears) | PR#2 | T25, T32 |
| 239 (initial state <2 chars) | PR#2 | T25, T26, T32 |
| 240 (debounce) | PR#2 | T26, T32 |
| 241 (search at 2 chars) | PR#2 | T23, T26, T30, T32 |
| 242 (result limit 20) | PR#2 | T20, T28 |
| 243 (case-insensitive match) | PR#2 | T20, T28 |
| 244 (displayNameLowercase model) | PR#2 | T19, T27 |
| 245 (write on create) | PR#2 | T21, T28 |
| 246 (write on update) | PR#2 | T21, T28 |
| 247 (write on ProfileSetup) | PR#2 | T22, T29 |
| 248 (tile structure) | PR#2 | T24, T31 |
| 249 (tile navigation) | PR#2 | T24, T31 |
| 250 (empty results) | PR#2 | T26, T32 |
| 251 (error state) | PR#2 | T26, T32 |

---

## Out-of-Scope Reminders

- NO Firebase security rules changes
- NO real routine picker (stub only — T02 + T12)
- NO inline follow button in search tiles (REQ-FSU-013)
- NO toast/snackbar on success (ADR-CP-003)
- NO confirmation dialog on CANCELAR (ADR-CP-002)
- NO pagination in search (ADR-SR-003)
- NO @handle field on UserProfile
- NO explicit backfill script for `displayNameLowercase` (lazy on next update — accepted trade-off)
- NO mockup fidelity audit (decision: avanzar sin mockups)

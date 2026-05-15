# Apply Progress: Feed Segments — MI GYM + PÚBLICO (Etapa 3)

**Status**: DONE
**Mode**: Strict TDD (RED → GREEN per task pair)
**Batch**: 1 of 1 (all tasks completed)

---

## Task Completion

- [x] **T01** | RED | `test/features/feed/application/my_gym_feed_provider_test.dart` | Created 5 failing tests (SCENARIO-190..194)
- [x] **T02** | GREEN | `lib/features/feed/application/feed_screen_providers.dart` | Added `myGymFeedProvider` as `FutureProvider<List<Post>?>` wrapping `userProfileProvider.future` + delegating to `feedForGymProvider(gymId).future`
- [x] **T03** | RED | `test/features/feed/presentation/widgets/feed_empty_state_test.dart` | Added 3 failing tests (SCENARIO-195..197) + updated SCENARIO-185..187 to use `message:` param
- [x] **T04** | GREEN | `lib/features/feed/presentation/widgets/feed_empty_state.dart` + `lib/features/feed/feed_screen.dart` | Parameterized `FeedEmptyState` with `required message` + optional `icon` (default `TreinoIcon.users`); updated `_AmigosBody` callsite atomically
- [x] **T05** | RED | `test/features/feed/presentation/feed_screen_test.dart` | Added failing tests for `_MiGymBody` (SCENARIO-202..206, 213) and `_PublicoBody` (SCENARIO-208..211); updated SCENARIO-148/149 to new expected behavior; updated all groups to include `myGymFeedProvider` + `feedPublicProvider` overrides
- [x] **T06** | GREEN | `lib/features/feed/feed_screen.dart` | Added `_MiGymBody` ConsumerWidget with full AsyncValue routing (loading/error/null/[]/[...])
- [x] **T07** | GREEN | `lib/features/feed/feed_screen.dart` | Added `_PublicoBody` ConsumerWidget (no null branch); empty copy `'Aún no hay posts públicos'`
- [x] **T08** | GREEN | `lib/features/feed/feed_screen.dart` (switch expression) | Replaced `gym || public => SizedBox.shrink()` with separate arms `gym => _MiGymBody()`, `public => _PublicoBody()`
- [x] **T09** | RED | `test/features/feed/presentation/widgets/feed_segment_pills_test.dart` | Added failing tests (SCENARIO-198..201); updated SCENARIO-164/165 to assert new wired behavior
- [x] **T10** | GREEN | `lib/features/feed/presentation/widgets/feed_segment_pills.dart` | Replaced `const _Pill(isActive: false, onTap: null)` for MI GYM + PÚBLICO with non-const wired to `feedSegmentProvider`
- [x] **T11** | GATE | `flutter analyze` → 0 issues (fixed 2 unused imports)
- [x] **T12** | GATE | `dart format --output=none --set-exit-if-changed .` → 0 changed
- [x] **T13** | GATE | `flutter test` → 494 passing, 1 skip (was 474 → +20 new test cases)

---

## TDD Cycle Evidence

| Task | RED commit | GREEN commit | Evidence |
|------|-----------|-------------|---------|
| T01/T02 | `698d8f1` test(feed): add SCENARIO-190..194 | `cac5c22` feat(feed): add myGymFeedProvider wrapper | Compile error on `myGymFeedProvider` (undefined) |
| T03/T04 | `b316f9f` test(feed): add SCENARIO-195..197 | `2dece03` feat(feed): parameterize FeedEmptyState | No named parameter `message` error |
| T05/T06+T07+T08 | `7602b24` test(feed): add SCENARIO-202..213 | `2784763` feat(feed): add _MiGymBody + _PublicoBody | 12 tests failed (SizedBox.shrink gave no FeedEmptyState/PostCard) |
| T09/T10 | `1490bbe` test(feed): add SCENARIO-198..201 | `d1bc017` feat(feed): enable MI GYM + PÚBLICO pills | 2 tests failed (onTap:null prevented state change) |

---

## Quality Gates

| Gate | Result | Notes |
|------|--------|-------|
| `flutter analyze` | PASSED — 0 issues | Fixed 2 unused imports (routine_tag in test, post.dart in impl) |
| `dart format --output=none --set-exit-if-changed .` | PASSED — 0 changed | Applied format in `chore(feed)` commit |
| `flutter test` | PASSED — 494 passing, 1 skip | Baseline 474 → +20 test cases |

---

## Files Modified

| File | Action | LOC delta |
|------|--------|-----------|
| `test/features/feed/application/my_gym_feed_provider_test.dart` | CREATED | +143 |
| `lib/features/feed/application/feed_screen_providers.dart` | MODIFIED | +15 |
| `test/features/feed/presentation/widgets/feed_empty_state_test.dart` | MODIFIED | +38 |
| `lib/features/feed/presentation/widgets/feed_empty_state.dart` | MODIFIED | +5 net (removed hardcoded copy, added params) |
| `lib/core/widgets/treino_icon.dart` | MODIFIED | +3 (added TreinoIcon.gym) |
| `test/features/feed/presentation/feed_screen_test.dart` | MODIFIED | +253 |
| `lib/features/feed/feed_screen.dart` | MODIFIED | +90 net |
| `test/features/feed/presentation/widgets/feed_segment_pills_test.dart` | MODIFIED | +65 |
| `lib/features/feed/presentation/widgets/feed_segment_pills.dart` | MODIFIED | +6 net |

---

## Deviations from Spec/Design

1. **`TreinoIcon.gym` not in icon registry**: The spec used `TreinoIcon.gym` as the custom icon example in SCENARIO-197. The icon didn't exist in `treino_icon.dart`. Added `static const IconData gym = PhosphorIconsRegular.buildings;` to `TreinoIcon`. This is additive and does not violate any constraint.

2. **SCENARIO-207/212 scroll position tests**: Not added as widget tests — the design explicitly pins "SCENARIO-207/212 scroll: preserved (default ListView, no ScrollController manual)". The default `ListView` behavior preserves scroll within the same widget instance but resets when the widget is destroyed and recreated (segment switch). This is the stated acceptable behavior. Tests verifying layout correctness cover the ListView cases.

3. **Test count**: Tasks estimated ~28 new scenarios. Actual: +20. SCENARIO-164 and SCENARIO-165 were updated (not new tests), and SCENARIO-207/212/215/216/217 are handled by sdd-verify (static checks) rather than widget tests.

4. **SCENARIO-213/214 test approach**: Used `_wrapProviderRouter` with a GoRouter stub route `/feed/profile/:uid` to verify navigation. The test navigates and checks the stub screen renders `profile-u-xyz`, confirming the route path format is correct.

---

## Commits Made

| SHA | Message |
|-----|---------|
| `698d8f1` | test(feed): add SCENARIO-190..194 for myGymFeedProvider |
| `cac5c22` | feat(feed): add myGymFeedProvider wrapper with null-gym guard |
| `b316f9f` | test(feed): add SCENARIO-195..197 for FeedEmptyState parameterization |
| `2dece03` | feat(feed): parameterize FeedEmptyState with message + icon, update AMIGOS callsite |
| `7602b24` | test(feed): add SCENARIO-202..213 for _MiGymBody + _PublicoBody |
| `2784763` | feat(feed): add _MiGymBody + _PublicoBody, wire switch arms, navigate onAuthorTap |
| `1490bbe` | test(feed): add SCENARIO-198..201 for FeedSegmentPills MI GYM + PÚBLICO enable |
| `d1bc017` | feat(feed): enable MI GYM + PÚBLICO pills with feedSegmentProvider wiring |
| `a7d2a0b` | chore(feed): fix unused imports and apply dart format |

---

## Notes for Verify Phase

- Forbidden files (`friendship_repository.dart`, `post_card.dart`, `router.dart`) were NOT modified. Verify with `git diff main -- lib/features/feed/data/friendship_repository.dart lib/features/feed/presentation/widgets/post_card.dart lib/app/router.dart`.
- REQ-FSG-026 (TDD audit): test commits precede implementation commits in git log. Run `git log --oneline feat/feed-segments` to verify ordering.
- `// TODO: route added in feat/public-profile (Etapa 4)` comment is present in both `_MiGymBody` and `_PublicoBody` at the `onAuthorTap` call site.
- `// TODO(pagination): cursor-based pagination deferred (see explore §9)` is present in both `_MiGymBody` and `_PublicoBody` at the `ListView.separated` call sites.
- All colors via `AppPalette.of(context)`. No hex literals introduced.
- All icons via `TreinoIcon.X`. Added `TreinoIcon.gym` to the registry.
- All spacing values: 8/12/14/18/20 px only.

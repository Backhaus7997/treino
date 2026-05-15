# Tasks: Feed Segments — MI GYM + PÚBLICO (Etapa 3)

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | ~370 (additions + deletions) |
| 400-line budget risk | Medium |
| Chained PRs recommended | No |
| Suggested split | single PR |
| Delivery strategy | single-pr (LOCKED) |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: Medium

Rationale: 5 files touched, ~370 lines total. Under 400-line budget. Most lines are test bodies
(~230 test LOC, ~140 impl LOC). No exceptional complexity requiring PR split.

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | All tasks T01–T11 as single PR | PR 1 | feature/feed-segments → main |

---

## Open Questions Resolved (from spec)

- **SCENARIO-207/212 scroll position**: PINNED → preserved by default `ListView` behavior; no manual
  `ScrollController` or explicit reset. Flutter reuses scroll position when the widget subtree is
  kept alive inside the `switch` expression. No code change required beyond the default.
- **SCENARIO-193 auth=null behavior**: PINNED → `myGymFeedProvider` uses `.future` on
  `userProfileProvider` (a `StreamProvider<UserProfile?>`). While auth is loading the stream has
  not emitted, so `.future` is pending → provider is `AsyncLoading`. If the user is signed out,
  `userProfileProvider` emits `null` → `profile?.gymId` is `null` → provider returns `null` data
  (no-gym path). No error is emitted. Consistent with `myFriendsFeedProvider`.
- **REQ-FSG-026 TDD audit**: PINNED → this is a git history constraint, not a runtime test.
  `sdd-verify` will inspect `git log --oneline` commit order; `sdd-apply` must commit RED tasks
  before their paired GREEN tasks.

---

## Phase 1 — Provider Foundation

- [ ] **T01** | RED | `test/features/feed/application/my_gym_feed_provider_test.dart` | CREATE failing
  tests for `myGymFeedProvider`: null-gym branch (SCENARIO-190), gym-present branch (SCENARIO-191),
  AsyncLoading propagation (SCENARIO-192), auth-null no-error (SCENARIO-193), upstream error
  propagation (SCENARIO-194). Use `ProviderContainer` + overrides for `userProfileProvider` and
  `feedForGymProvider`. | REQ-FSG-001..005 | SCENARIO-190..194 | ~70 LOC | deps: none

- [ ] **T02** | GREEN | `lib/features/feed/application/feed_screen_providers.dart` | ADD
  `myGymFeedProvider` as `FutureProvider<List<Post>?>` wrapping `userProfileProvider.future` and
  delegating to `feedForGymProvider(gymId).future` when `gymId != null`; return `null` otherwise.
  Import `post_providers.dart` for `feedForGymProvider`. | REQ-FSG-001..005 | SCENARIO-190..194 |
  ~12 LOC | deps: T01

---

## Phase 2 — Widget Parameter (FeedEmptyState)

- [ ] **T03** | RED | `test/features/feed/presentation/widgets/feed_empty_state_test.dart` | CREATE
  (or extend) failing tests: message renders (SCENARIO-195), default icon is `TreinoIcon.users`
  (SCENARIO-196), custom icon overrides default (SCENARIO-197). Use `ProviderScope` + `pumpWidget`.
  | REQ-FSG-006 | SCENARIO-195..197 | ~40 LOC | deps: T02

- [ ] **T04** | GREEN | `lib/features/feed/presentation/widgets/feed_empty_state.dart` AND
  `lib/features/feed/feed_screen.dart` (line 87) | PARAMETERIZE `FeedEmptyState` with
  `required String message` + `IconData icon = TreinoIcon.users`; remove `_kCopy` constant; update
  the single `_AmigosBody` call site to
  `FeedEmptyState(message: 'Aún no hay posts de tus amigos')`. Atomic pair — do not split.
  | REQ-FSG-006, REQ-FSG-007 | SCENARIO-195..197 | ~18 LOC changed | deps: T03

---

## Phase 3 — New Body Widgets

- [ ] **T05** | RED | `test/features/feed/feed_screen_test.dart` | ADD failing widget tests for
  `_MiGymBody`: loading spinner (SCENARIO-206), error copy (SCENARIO-205), null → no-gym empty
  state (SCENARIO-202), empty-list → no-posts empty state (SCENARIO-203), non-empty → ListView of
  PostCards (SCENARIO-204). ADD failing widget tests for `_PublicoBody`: loading (SCENARIO-211),
  error (SCENARIO-210), empty (SCENARIO-208), non-empty (SCENARIO-209). Override
  `myGymFeedProvider` and `feedPublicProvider` via `ProviderScope`. Verify
  `onAuthorTap` callback fires and TODO comment present (SCENARIO-213..215).
  | REQ-FSG-010..016, REQ-FSG-020 | SCENARIO-202..215 | ~90 LOC | deps: T04

- [ ] **T06** | GREEN | `lib/features/feed/feed_screen.dart` | ADD `_MiGymBody` as
  `ConsumerWidget`: `ref.watch(myGymFeedProvider).when(loading → spinner, error → generic copy,
  data → null/[]/[...] routing)`. Use `ListView.separated` with `// TODO(pagination)` comment and
  `PostCard(post: posts[i], onAuthorTap: () { context.go('/feed/profile/${post.authorUid}'); })`
  with `// TODO: route added in feat/public-profile (Etapa 4)` comment. Spacing: padding 20h,
  separator 14h. Colors from `AppPalette.of(context)`, icons from `TreinoIcon`.
  | REQ-FSG-010..013, REQ-FSG-016, REQ-FSG-020..025 | SCENARIO-202..207, 213..215 | ~50 LOC |
  deps: T05

- [ ] **T07** | GREEN | `lib/features/feed/feed_screen.dart` | ADD `_PublicoBody` as
  `ConsumerWidget` mirroring `_MiGymBody` but consuming `feedPublicProvider` (no null branch).
  Empty copy: `'Aún no hay posts públicos'`. Same spacing, colors, icon, TODO comments as T06.
  | REQ-FSG-014..016, REQ-FSG-020..025 | SCENARIO-208..212, 213..215 | ~35 LOC | deps: T06

- [ ] **T08** | GREEN | `lib/features/feed/feed_screen.dart` (switch expression lines 28–31) |
  REPLACE `FeedSegment.gym || FeedSegment.public => const SizedBox.shrink()` with two separate
  arms: `FeedSegment.gym => const _MiGymBody()`, `FeedSegment.public => const _PublicoBody()`.
  | REQ-FSG-008, REQ-FSG-009 | SCENARIO-202..212 | ~5 LOC | deps: T07

---

## Phase 4 — Pills Wiring

- [ ] **T09** | RED | `test/features/feed/presentation/widgets/feed_segment_pills_test.dart` | ADD
  failing widget tests: tapping MI GYM sets `feedSegmentProvider` to `FeedSegment.gym`
  (SCENARIO-198), tapping PÚBLICO sets to `FeedSegment.public` (SCENARIO-199), `isActive` reflects
  current provider value (SCENARIO-200), no pill has `onTap: null` or `Opacity` wrapper
  (SCENARIO-201). | REQ-FSG-017..019 | SCENARIO-198..201 | ~45 LOC | deps: T08

- [ ] **T10** | GREEN | `lib/features/feed/presentation/widgets/feed_segment_pills.dart` | REPLACE
  `const _Pill(label: 'MI GYM', isActive: false, onTap: null)` and `const _Pill(label: 'PÚBLICO',
  isActive: false, onTap: null)` with non-const `_Pill` instances wired to `feedSegmentProvider`:
  `isActive: segment == FeedSegment.gym`, `onTap: () => ref.read(feedSegmentProvider.notifier).state = FeedSegment.gym`
  (and `.public` equivalent). Remove `const` keyword only from those two `_Pill` calls; `SizedBox`
  spacers keep `const`. | REQ-FSG-017..019, REQ-FSG-021..023 | SCENARIO-198..201 | ~15 LOC |
  deps: T09

---

## Phase 5 — Quality Gates

- [ ] **T11** | GATE | repository root | RUN `flutter analyze` → must exit 0 with no issues.
  | REQ-FSG-021..024 | SCENARIO-216 | 0 LOC | deps: T10

- [ ] **T12** | GATE | repository root | RUN `dart format --output=none --set-exit-if-changed .`
  → must exit 0. | REQ-FSG-021 | — | 0 LOC | deps: T11

- [ ] **T13** | GATE | repository root | RUN `flutter test` → all tests green, including ~28 new
  scenarios added in T01, T03, T05, T09. | REQ-FSG-001..025 | SCENARIO-190..215 | 0 LOC | deps: T12

---

## Parallelism Notes

All tasks are strictly sequential (RED → GREEN pairs enforce TDD order). No task can run in parallel
because:
1. T01→T02 provider pair must commit in order (REQ-FSG-026 git history constraint).
2. T03→T04 depends on T02 (FeedEmptyState is used inside bodies introduced in T06).
3. T05→T08 depends on T04 (FeedEmptyState signature is final).
4. T09→T10 depends on T08 (pills reference `FeedSegment.gym/public` which must be wired first to
   see meaningful widget test outcomes).
5. Gates T11–T13 must follow all implementation.

---

## REQ-FSG Coverage Matrix

| REQ-FSG | Description (short) | Tasks |
|---------|---------------------|-------|
| REQ-FSG-001 | myGymFeedProvider exists as FutureProvider | T01, T02 |
| REQ-FSG-002 | Returns null when gymId == null | T01, T02 |
| REQ-FSG-003 | Delegates to feedForGymProvider when gymId != null | T01, T02 |
| REQ-FSG-004 | Propagates AsyncLoading | T01, T02 |
| REQ-FSG-005 | auth=null treated as no-data | T01, T02 |
| REQ-FSG-006 | FeedEmptyState accepts message + icon params | T03, T04 |
| REQ-FSG-007 | AMIGOS caller updated with explicit message | T04 |
| REQ-FSG-008 | FeedScreen renders _MiGymBody for gym segment | T05, T08 |
| REQ-FSG-009 | FeedScreen renders _PublicoBody for public segment | T05, T08 |
| REQ-FSG-010 | _MiGymBody consumes myGymFeedProvider, all 3 AsyncValue states | T05, T06 |
| REQ-FSG-011 | _MiGymBody null → no-gym empty state | T05, T06 |
| REQ-FSG-012 | _MiGymBody [] → no-posts empty state | T05, T06 |
| REQ-FSG-013 | _MiGymBody non-empty → ListView + TODO(pagination) | T05, T06 |
| REQ-FSG-014 | _PublicoBody consumes feedPublicProvider, all 3 states | T05, T07 |
| REQ-FSG-015 | _PublicoBody [] → empty-state copy | T05, T07 |
| REQ-FSG-016 | All bodies use shared generic error copy | T05, T06, T07 |
| REQ-FSG-017 | FeedSegmentPills MI GYM pill wired | T09, T10 |
| REQ-FSG-018 | FeedSegmentPills PÚBLICO pill wired | T09, T10 |
| REQ-FSG-019 | Pills match AMIGOS style, no opacity/disabled | T09, T10 |
| REQ-FSG-020 | PostCard onAuthorTap wired with TODO comment | T05, T06, T07 |
| REQ-FSG-021 | Colors from AppPalette only | T06, T07, T11 |
| REQ-FSG-022 | Icons from TreinoIcon only | T06, T07, T11 |
| REQ-FSG-023 | Spacing in design scale | T06, T07, T11 |
| REQ-FSG-024 | Forbidden files not modified | T11 (verify phase) |
| REQ-FSG-025 | TODO(pagination) at ListView sites | T06, T07 |
| REQ-FSG-026 | TDD audit — test commits precede impl commits | sdd-verify (git log check) |

---

## Out-of-Scope Hard Constraints (apply must enforce)

- `friendship_repository.dart` — NOT touched (Etapa 4)
- `post_card.dart` — NOT touched; `onAuthorTap` is existing public API
- `router.dart` — NOT touched; TODO comment documents the Etapa 4 seam
- No pagination implementation — `// TODO(pagination)` comment only
- No Riverpod codegen — manual provider style consistent with existing codebase
- No extraction of shared `_FeedLoadingState`/`_FeedErrorState` widgets (below rule-of-three)

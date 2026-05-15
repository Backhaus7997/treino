# Feed Segments Specification — MI GYM + PÚBLICO (Etapa 3)

**Change**: feed-segments
**Domain**: feed (Modified Capability)
**Scenario range**: SCENARIO-190..SCENARIO-217

---

## ADDED Requirements

### REQ-FSG-001 — myGymFeedProvider exists as FutureProvider

The system MUST expose `myGymFeedProvider` in `lib/features/feed/application/feed_screen_providers.dart` typed as `FutureProvider<List<Post>?>`.

#### Acceptance criteria
- Provider is importable from the declared file.
- Return type annotation is `FutureProvider<List<Post>?>` (nullable list).

---

### REQ-FSG-002 — myGymFeedProvider returns null when gymId is null

The system MUST return `null` (not an error, not an empty list) when the current user's profile has `gymId == null`.

#### Acceptance criteria
- Test receives `null` data when `userProfileProvider` yields a profile with `gymId: null`.

---

### REQ-FSG-003 — myGymFeedProvider delegates to feedForGymProvider when gymId is non-null

The system MUST return `List<Post>` (possibly empty) by delegating to `feedForGymProvider(gymId)` when `gymId` is non-null.

#### Acceptance criteria
- When `gymId` is non-null, the provider value equals the value produced by `feedForGymProvider(gymId)`.

---

### REQ-FSG-004 — myGymFeedProvider propagates profile loading state

The system MUST propagate `AsyncLoading` to all consumers while `userProfileProvider` is in the loading state.

#### Acceptance criteria
- Consumers observe `AsyncLoading` before the profile resolves.

---

### REQ-FSG-005 — myGymFeedProvider treats auth=null as no-data

When the auth state yields `null` (unauthenticated), the system MUST treat this identically to no-profile — returning a loading or null value — consistent with `myFriendsFeedProvider`.

#### Acceptance criteria
- No error is surfaced to the consumer; provider either stays loading or resolves null.

---

### REQ-FSG-006 — FeedEmptyState accepts parameterized message and icon

`FeedEmptyState` MUST accept a required `String message` parameter and an optional `IconData icon` parameter (default: `TreinoIcon.users`).

#### Acceptance criteria
- Widget compiles without `message` argument causes a compile error.
- Omitting `icon` renders `TreinoIcon.users` by default.

---

### REQ-FSG-007 — Existing AMIGOS caller updated with explicit message

The existing `FeedEmptyState` call site for the AMIGOS segment MUST pass `message: 'Aún no hay posts de tus amigos'` explicitly.

#### Acceptance criteria
- No positional copy string hardcoded inside `FeedEmptyState` itself; all copy at call sites.

---

### REQ-FSG-008 — FeedScreen renders _MiGymBody for gym segment

`FeedScreen` MUST render `_MiGymBody` when `feedSegmentProvider` value equals `FeedSegment.gym`.

#### Acceptance criteria
- Switching to `FeedSegment.gym` causes `_MiGymBody` to be present in the widget tree.

---

### REQ-FSG-009 — FeedScreen renders _PublicoBody for public segment

`FeedScreen` MUST render `_PublicoBody` when `feedSegmentProvider` value equals `FeedSegment.public`.

#### Acceptance criteria
- Switching to `FeedSegment.public` causes `_PublicoBody` to be present in the widget tree.

---

### REQ-FSG-010 — _MiGymBody consumes myGymFeedProvider and routes AsyncValue

`_MiGymBody` MUST consume `myGymFeedProvider` and handle all three `AsyncValue` states: loading, error, and data.

#### Acceptance criteria
- Loading → spinner/indicator is shown.
- Error → error copy is shown.
- Data → data routing per REQ-FSG-011..013.

---

### REQ-FSG-011 — _MiGymBody null result shows no-gym empty state

When `myGymFeedProvider` resolves to `null`, `_MiGymBody` MUST display `FeedEmptyState` with `message: 'Todavía no estás en un gym'`.

#### Acceptance criteria
- Widget tree contains `FeedEmptyState` with that exact string.

---

### REQ-FSG-012 — _MiGymBody empty list shows gym-no-posts empty state

When `myGymFeedProvider` resolves to `[]`, `_MiGymBody` MUST display `FeedEmptyState` with `message: 'Tu gym todavía no tiene posts'`.

#### Acceptance criteria
- Widget tree contains `FeedEmptyState` with that exact string.

---

### REQ-FSG-013 — _MiGymBody non-empty list shows PostCard list

When `myGymFeedProvider` resolves to a non-empty `List<Post>`, `_MiGymBody` MUST display a `ListView.separated` of `PostCard` widgets.

#### Acceptance criteria
- One `PostCard` per post in the list.
- A `// TODO(pagination)` comment is present at the `ListView.separated` call site.

---

### REQ-FSG-014 — _PublicoBody consumes feedPublicProvider and routes AsyncValue

`_PublicoBody` MUST consume `feedPublicProvider` and handle loading, error, and data states.

#### Acceptance criteria
- Loading → spinner.
- Error → error copy.
- Data → routing per REQ-FSG-015.

---

### REQ-FSG-015 — _PublicoBody empty result shows empty-state copy

When `feedPublicProvider` resolves to `[]`, `_PublicoBody` MUST display `FeedEmptyState` with `message: 'Aún no hay posts públicos'`.

#### Acceptance criteria
- Widget tree contains `FeedEmptyState` with that exact string.

---

### REQ-FSG-016 — All body widgets use shared generic error copy

All three body widgets (`_AmigosBody`, `_MiGymBody`, `_PublicoBody`) MUST use `'No pudimos cargar tu feed. Intentá de nuevo.'` as the error message.

#### Acceptance criteria
- No body widget uses a different error string.

---

### REQ-FSG-017 — FeedSegmentPills enables MI GYM pill

`FeedSegmentPills` MUST render the MI GYM pill with `isActive` driven by `feedSegmentProvider == FeedSegment.gym` and `onTap` setting `feedSegmentProvider` to `FeedSegment.gym`.

#### Acceptance criteria
- Pill is active when segment is `gym`; inactive otherwise.
- Tapping sets provider to `FeedSegment.gym`.

---

### REQ-FSG-018 — FeedSegmentPills enables PÚBLICO pill

`FeedSegmentPills` MUST render the PÚBLICO pill with `isActive` driven by `feedSegmentProvider == FeedSegment.public` and `onTap` setting `feedSegmentProvider` to `FeedSegment.public`.

#### Acceptance criteria
- Pill is active when segment is `public`; inactive otherwise.
- Tapping sets provider to `FeedSegment.public`.

---

### REQ-FSG-019 — Active and inactive pill styles match AMIGOS pill

Both new pills MUST apply the same visual treatment as the AMIGOS pill: accent fill + dark text when active; `AppPalette.bgCard` + border when inactive.

#### Acceptance criteria
- No opacity or disabled wrapper added in Etapa 3 (was addressed in Etapa 2 fix).

---

### REQ-FSG-020 — PostCard onAuthorTap wired with TODO comment

`PostCard` calls in `_MiGymBody` and `_PublicoBody` MUST pass `onAuthorTap` as a callback invoking `context.go('/feed/profile/${post.authorUid}')` accompanied by a `// TODO: route added in feat/public-profile (Etapa 4)` comment.

#### Acceptance criteria
- Callback fires when author is tapped.
- TODO comment is present at the call site.
- `router.dart` is NOT modified.

---

### REQ-FSG-021 — Colors from AppPalette only

All color references in changed files MUST use `AppPalette.of(context)`. Hex literals MUST NOT appear.

---

### REQ-FSG-022 — Icons from TreinoIcon only

All icon references MUST use `TreinoIcon.X`. Direct `PhosphorIcons.X` references MUST NOT appear.

---

### REQ-FSG-023 — Spacing in design scale

All spacing values MUST be from the set {8, 12, 14, 18, 20} pixels. Arbitrary spacing values MUST NOT be introduced.

---

### REQ-FSG-024 — Forbidden files not modified

The files `friendship_repository.dart`, `post_card.dart`, and `router.dart` MUST NOT appear in the diff for this change.

---

### REQ-FSG-025 — TODO(pagination) markers at ListView sites

Both `_MiGymBody` and `_PublicoBody` MUST contain a `// TODO(pagination)` comment at their `ListView.separated` call sites.

---

### REQ-FSG-026 — Strict TDD — tests before implementation in git history

For each new widget and provider introduced, the corresponding test file MUST exist in a commit that precedes the implementation commit in git history.

---

## Scenarios

| ID | Summary | REQs |
|----|---------|------|
| SCENARIO-190 | myGymFeedProvider — profile with gymId null returns null | REQ-FSG-002 |
| SCENARIO-191 | myGymFeedProvider — profile with gymId non-null returns delegated list | REQ-FSG-003 |
| SCENARIO-192 | myGymFeedProvider — profile loading propagates AsyncLoading | REQ-FSG-004 |
| SCENARIO-193 | myGymFeedProvider — auth null treated as no-data | REQ-FSG-005 |
| SCENARIO-194 | myGymFeedProvider — underlying provider error is propagated | REQ-FSG-001, REQ-FSG-003 |
| SCENARIO-195 | FeedEmptyState — renders provided message string | REQ-FSG-006 |
| SCENARIO-196 | FeedEmptyState — omitting icon defaults to TreinoIcon.users | REQ-FSG-006 |
| SCENARIO-197 | FeedEmptyState — custom icon overrides default | REQ-FSG-006 |
| SCENARIO-198 | FeedSegmentPills — tapping MI GYM sets feedSegmentProvider to gym | REQ-FSG-017 |
| SCENARIO-199 | FeedSegmentPills — tapping PÚBLICO sets feedSegmentProvider to public | REQ-FSG-018 |
| SCENARIO-200 | FeedSegmentPills — isActive reflects current feedSegmentProvider value | REQ-FSG-017, REQ-FSG-018 |
| SCENARIO-201 | FeedSegmentPills — no opacity/disabled wrapper on any pill | REQ-FSG-019 |
| SCENARIO-202 | _MiGymBody — gymId null → FeedEmptyState "Todavía no estás en un gym" | REQ-FSG-011 |
| SCENARIO-203 | _MiGymBody — gym with no posts → FeedEmptyState "Tu gym todavía no tiene posts" | REQ-FSG-012 |
| SCENARIO-204 | _MiGymBody — gym with posts → ListView of PostCards | REQ-FSG-013 |
| SCENARIO-205 | _MiGymBody — error state → generic error copy | REQ-FSG-010, REQ-FSG-016 |
| SCENARIO-206 | _MiGymBody — loading state → spinner shown | REQ-FSG-010 |
| SCENARIO-207 | _MiGymBody — scroll position preserved across segment switches | REQ-FSG-008, REQ-FSG-013 |
| SCENARIO-208 | _PublicoBody — empty list → FeedEmptyState "Aún no hay posts públicos" | REQ-FSG-015 |
| SCENARIO-209 | _PublicoBody — non-empty list → ListView of PostCards | REQ-FSG-014 |
| SCENARIO-210 | _PublicoBody — error state → generic error copy | REQ-FSG-014, REQ-FSG-016 |
| SCENARIO-211 | _PublicoBody — loading state → spinner shown | REQ-FSG-014 |
| SCENARIO-212 | _PublicoBody — scroll position preserved across segment switches | REQ-FSG-009, REQ-FSG-014 |
| SCENARIO-213 | PostCard onAuthorTap callback fires on author tap | REQ-FSG-020 |
| SCENARIO-214 | PostCard onAuthorTap navigates with correct uid in path | REQ-FSG-020 |
| SCENARIO-215 | TODO comment present at PostCard onAuthorTap call site | REQ-FSG-020 |
| SCENARIO-216 | Forbidden files diff check — friendship_repository, post_card, router unchanged | REQ-FSG-024 |
| SCENARIO-217 | TDD audit — test commits precede implementation commits in git log | REQ-FSG-026 |

---

## Scenario Definitions

### SCENARIO-190

- GIVEN `userProfileProvider` resolves to a `UserProfile` where `gymId == null`
- WHEN `myGymFeedProvider` is watched
- THEN the provider data value is `null`
- AND no error is emitted

### SCENARIO-191

- GIVEN `userProfileProvider` resolves to a `UserProfile` where `gymId == 'gym-abc'`
- AND `feedForGymProvider('gym-abc')` returns `[PostA, PostB]`
- WHEN `myGymFeedProvider` is watched
- THEN the provider data value equals `[PostA, PostB]`

### SCENARIO-192

- GIVEN `userProfileProvider` is in `AsyncLoading` state
- WHEN `myGymFeedProvider` is watched
- THEN `myGymFeedProvider` is also in `AsyncLoading` state
- AND no data or error is emitted

### SCENARIO-193

- GIVEN the auth user is `null` (signed out)
- WHEN `myGymFeedProvider` is watched
- THEN the provider does not emit an error
- AND behavior is consistent with `myFriendsFeedProvider` under the same auth condition

### SCENARIO-194

- GIVEN `userProfileProvider` resolves with `gymId == 'gym-abc'`
- AND `feedForGymProvider('gym-abc')` emits an error
- WHEN `myGymFeedProvider` is watched
- THEN `myGymFeedProvider` is in `AsyncError` state

### SCENARIO-195

- GIVEN `FeedEmptyState` is rendered with `message: 'Test message'`
- WHEN the widget builds
- THEN the text `'Test message'` is visible in the widget tree

### SCENARIO-196

- GIVEN `FeedEmptyState` is rendered with `message: 'Test'` and no `icon` argument
- WHEN the widget builds
- THEN `TreinoIcon.users` is used as the icon

### SCENARIO-197

- GIVEN `FeedEmptyState` is rendered with `message: 'Test'` and `icon: TreinoIcon.gym`
- WHEN the widget builds
- THEN `TreinoIcon.gym` is displayed, not `TreinoIcon.users`

### SCENARIO-198

- GIVEN `feedSegmentProvider` is `FeedSegment.amigos`
- WHEN the user taps the MI GYM pill
- THEN `feedSegmentProvider` updates to `FeedSegment.gym`

### SCENARIO-199

- GIVEN `feedSegmentProvider` is `FeedSegment.amigos`
- WHEN the user taps the PÚBLICO pill
- THEN `feedSegmentProvider` updates to `FeedSegment.public`

### SCENARIO-200

- GIVEN `feedSegmentProvider` is `FeedSegment.gym`
- WHEN `FeedSegmentPills` renders
- THEN MI GYM pill has `isActive: true`
- AND AMIGOS and PÚBLICO pills have `isActive: false`

### SCENARIO-201

- GIVEN any `feedSegmentProvider` value
- WHEN `FeedSegmentPills` renders
- THEN no pill is wrapped in an `Opacity` widget or has `onTap: null`

### SCENARIO-202

- GIVEN `myGymFeedProvider` resolves to `null`
- WHEN `_MiGymBody` renders
- THEN `FeedEmptyState` is in the widget tree with message `'Todavía no estás en un gym'`

### SCENARIO-203

- GIVEN `myGymFeedProvider` resolves to `[]`
- WHEN `_MiGymBody` renders
- THEN `FeedEmptyState` is in the widget tree with message `'Tu gym todavía no tiene posts'`

### SCENARIO-204

- GIVEN `myGymFeedProvider` resolves to `[PostA, PostB]`
- WHEN `_MiGymBody` renders
- THEN a `ListView.separated` containing two `PostCard` widgets is in the widget tree

### SCENARIO-205

- GIVEN `myGymFeedProvider` is in `AsyncError` state
- WHEN `_MiGymBody` renders
- THEN the text `'No pudimos cargar tu feed. Intentá de nuevo.'` is visible

### SCENARIO-206

- GIVEN `myGymFeedProvider` is in `AsyncLoading` state
- WHEN `_MiGymBody` renders
- THEN a loading indicator (spinner) is visible

### SCENARIO-207

- GIVEN the user scrolled down in `_MiGymBody` then tapped AMIGOS
- WHEN the user taps MI GYM again
- THEN scroll position is either preserved or reset to top (behavior is explicit, not accidental)

### SCENARIO-208

- GIVEN `feedPublicProvider` resolves to `[]`
- WHEN `_PublicoBody` renders
- THEN `FeedEmptyState` is in the widget tree with message `'Aún no hay posts públicos'`

### SCENARIO-209

- GIVEN `feedPublicProvider` resolves to `[PostA]`
- WHEN `_PublicoBody` renders
- THEN a `ListView.separated` containing one `PostCard` is in the widget tree

### SCENARIO-210

- GIVEN `feedPublicProvider` is in `AsyncError` state
- WHEN `_PublicoBody` renders
- THEN the text `'No pudimos cargar tu feed. Intentá de nuevo.'` is visible

### SCENARIO-211

- GIVEN `feedPublicProvider` is in `AsyncLoading` state
- WHEN `_PublicoBody` renders
- THEN a loading indicator is visible

### SCENARIO-212

- GIVEN the user scrolled down in `_PublicoBody` then switched segments
- WHEN the user returns to PÚBLICO
- THEN scroll behavior is explicit and consistent (preserved or reset to top)

### SCENARIO-213

- GIVEN `_MiGymBody` or `_PublicoBody` renders with a post
- WHEN the user taps the author area of a `PostCard`
- THEN the `onAuthorTap` callback is invoked

### SCENARIO-214

- GIVEN a post with `authorUid: 'user-xyz'`
- WHEN `onAuthorTap` fires
- THEN the navigation target is `/feed/profile/user-xyz`

### SCENARIO-215

- GIVEN the source file for `_MiGymBody` or `_PublicoBody`
- WHEN reviewing the `onAuthorTap` call site
- THEN a `// TODO: route added in feat/public-profile (Etapa 4)` comment is present

### SCENARIO-216

- GIVEN the completed PR diff for `feed-segments`
- WHEN checking changed files
- THEN `friendship_repository.dart`, `post_card.dart`, and `router.dart` are NOT in the diff

### SCENARIO-217

- GIVEN the git log for `feat/feed-segments`
- WHEN inspecting commits for `myGymFeedProvider`
- THEN the test file commit SHA is older than (precedes) the implementation commit SHA

---

## Cross-Cutting Constraints

| Constraint | Rule |
|------------|------|
| Colors | `AppPalette.of(context)` only — no hex literals |
| Icons | `TreinoIcon.X` only — no direct `PhosphorIcons.X` |
| Spacing | Must be from {8, 12, 14, 18, 20} px |
| Forbidden files | `friendship_repository.dart`, `post_card.dart`, `router.dart` — no diff |
| Pagination | `// TODO(pagination)` comment at each `ListView.separated` in new bodies |
| TDD | Test commit precedes implementation commit in git history |
| Error copy | All 3 bodies use `'No pudimos cargar tu feed. Intentá de nuevo.'` |
| Pill const | `_Pill` calls are non-const; parent `FeedSegmentPills` const annotation unaffected |

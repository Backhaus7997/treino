# Feed UI Layer — Specification

**Domain**: Feed Segments and Interaction (Etapa 2–3)  
**Changes**: `feed-shell-amigos` (Etapa 2) + `feed-segments` (Etapa 3)  
**Status**: ACTIVE (source of truth)  
**Last updated**: 2026-05-15  
**Merged**: PR #24 (Etapa 2, commit ede3270) + PR #26 (Etapa 3, commit 8ae066f)

---

## Purpose

Define the feed UI layer: widgets, providers, and interaction patterns for displaying posts across three segments (AMIGOS, MI GYM, PÚBLICO). This spec is the authoritative reference for all feed UI components in Etapa 2–3 and will be referenced by Etapa 4 (public profile) and Etapa 5 (create post). Depends on the data layer spec (`feed-data-layer.md`).

---

## Requirements: Etapa 2 (feed-shell-amigos)

All requirements from Etapa 2 are preserved and remain active. Etapa 3 extends but does not modify existing Etapa 2 requirements.

### REQ-FEED-001 — Feed screen structure with header, pills, body

The `FeedScreen` MUST display: header with title and action icons, segment pills row (3 pills), and segment-switched body area.

#### SCENARIO-133: FeedScreen renders header with title

- GIVEN `FeedScreen` is mounted
- WHEN the widget builds
- THEN a text widget with "Feed" is visible

#### SCENARIO-134: Post.fromJson defaults missing authorDisplayName to 'Anónimo'

- GIVEN a JSON map with missing `authorDisplayName`
- WHEN `Post.fromJson(...)` is called
- THEN `authorDisplayName` defaults to `'Anónimo'`

#### SCENARIO-135–145: Pill rendering, AMIGOS functional, MI GYM + PÚBLICO visually disabled

(See Etapa 2 spec in `openspec/changes/feed-shell-amigos/spec.md` for details)

---

## Requirements: Etapa 3 (feed-segments) — NEW

All 26 new requirements from Etapa 3 activate MI GYM and PÚBLICO segments.

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

## Scenarios: Etapa 2

(Reference `openspec/changes/feed-shell-amigos/spec.md` for SCENARIO-133..189)

---

## Scenarios: Etapa 3

| ID | Summary | REQs |
|----|---------|------|\
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
| SCENARIO-207 | _MiGymBody — scroll position preserved across segment switches (DEFERRED) | REQ-FSG-008, REQ-FSG-013 |
| SCENARIO-208 | _PublicoBody — empty list → FeedEmptyState "Aún no hay posts públicos" | REQ-FSG-015 |
| SCENARIO-209 | _PublicoBody — non-empty list → ListView of PostCards | REQ-FSG-014 |
| SCENARIO-210 | _PublicoBody — error state → generic error copy | REQ-FSG-014, REQ-FSG-016 |
| SCENARIO-211 | _PublicoBody — loading state → spinner shown | REQ-FSG-014 |
| SCENARIO-212 | _PublicoBody — scroll position preserved across segment switches (DEFERRED) | REQ-FSG-009, REQ-FSG-014 |
| SCENARIO-213 | PostCard onAuthorTap callback fires on author tap | REQ-FSG-020 |
| SCENARIO-214 | PostCard onAuthorTap navigates with correct uid in path | REQ-FSG-020 |
| SCENARIO-215 | TODO comment present at PostCard onAuthorTap call site | REQ-FSG-020 |
| SCENARIO-216 | Forbidden files diff check — friendship_repository, post_card, router unchanged | REQ-FSG-024 |
| SCENARIO-217 | TDD audit — test commits precede implementation commits in git log | REQ-FSG-026 |

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
| Empty states | Distinct copy per segment; parameterized via `FeedEmptyState.message` |

---

## API Contracts (Implementation Reference)

### Providers

```dart
// Etapa 2 (feed-shell-amigos)
final feedSegmentProvider = StateProvider<FeedSegment>((ref) => FeedSegment.amigos);
final myFriendsFeedProvider = FutureProvider<List<Post>>((ref) async { ... });

// Etapa 3 (feed-segments) — NEW
final myGymFeedProvider = FutureProvider<List<Post>?>((ref) async {
  final profile = await ref.watch(userProfileProvider.future);
  final gymId = profile?.gymId;
  if (gymId == null) return null;
  return ref.watch(feedForGymProvider(gymId).future);
});
```

### Widgets

```dart
// Etapa 2
class FeedScreen extends ConsumerWidget { ... }
class FeedSegmentPills extends ConsumerWidget { ... }
class PostCard extends StatelessWidget { ... }
class PostAvatar extends StatelessWidget { ... }
class FeedEmptyState extends StatelessWidget {
  const FeedEmptyState({
    super.key,
    required this.message,
    this.icon = TreinoIcon.users,
  });
  final String message;
  final IconData icon;
}

// Etapa 3 — NEW
class _MiGymBody extends ConsumerWidget { ... }
class _PublicoBody extends ConsumerWidget { ... }
```

---

## Status

- **Phase**: Fase 3 (Etapa 2–3 complete)
- **PR #24** (Etapa 2): `feat/feed-shell-amigos` (commit ede3270)
- **PR #26** (Etapa 3): `feat/feed-segments` (commit 8ae066f)
- **Tests**: 494 passing (418 baseline + 58 Etapa 2 + 20 Etapa 3)
- **Quality gates**: analyze 0, format clean, all scenarios green
- **Next phase**: Etapa 4 (public profile, parallel development)

---

## References

- **Etapa 2 artifacts**: `openspec/changes/feed-shell-amigos/`
- **Etapa 3 artifacts**: `openspec/changes/feed-segments/`
- **Data layer spec**: `openspec/specs/feed-data-layer.md`
- **Implementation**: `lib/features/feed/` (domain, data, application, presentation)
- **Tests**: `test/features/feed/`

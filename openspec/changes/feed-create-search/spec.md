# Specification: feed-create-search (Fase 3 · Etapa 5)

**Change**: `feed-create-search`
**Branch**: `feat/feed-create-search`
**Artifact store**: hybrid
**Scenario range**: SCENARIO-218..SCENARIO-251

---

## Section A — REQ-FCP-* (Create Post · PR#1)

| REQ | Name | Strength | Summary |
|-----|------|----------|---------|
| REQ-FCP-001 | CreatePostScreen route | MUST | `/feed/create` GoRoute nested under `/feed` ShellRoute |
| REQ-FCP-002 | Plus-button navigation | MUST | Plus in `_FeedHeader` → `context.push('/feed/create')` |
| REQ-FCP-003 | Form composition | MUST | Header (CANCELAR + title + PUBLICAR) + multiline TextField + 3-pill privacy selector + routine tag stub chip |
| REQ-FCP-004 | Char limit enforcement | MUST | Text field enforces max 280 chars; char counter visible at all times |
| REQ-FCP-005 | PUBLICAR enabled state | MUST | PUBLICAR is DISABLED when text is empty/whitespace-only; ENABLED when ≥1 non-whitespace char present |
| REQ-FCP-006 | Privacy selector default | MUST | Privacy defaults to `PostPrivacy.friends`; user MAY toggle to `gym` or `public` |
| REQ-FCP-007 | Gym pill disabled state | MUST | When `userProfileProvider.gymId == null`, gym pill renders at opacity 0.4 with helper text "Asociate a un gym para postear acá" and `onTap: null` |
| REQ-FCP-008 | Routine tag stub | MUST | Routine chip renders with label "ETIQUETAR RUTINA" at opacity 0.4, `onTap: null` (Fase 4 stub) |
| REQ-FCP-009 | createPostNotifier | MUST | `AsyncNotifier` manages `{text, privacy, isSubmitting}` form state |
| REQ-FCP-010 | Post construction | MUST | On submit, Post is built with: `authorUid` from auth, `authorDisplayName`/`authorAvatarUrl` from `userProfileProvider`, `text`, `privacy`, `createdAt: now`; `authorGymId` is denormalized by `PostRepository.create()` |
| REQ-FCP-011 | Success UX | MUST | On success: invalidate `myFriendsFeedProvider`, `feedPublicProvider`, `myGymFeedProvider`; then `context.pop()` |
| REQ-FCP-012 | Error UX | MUST | On error: show inline error text + re-enable submit; no snackbar |
| REQ-FCP-013 | CANCELAR behavior | MUST | CANCELAR calls `context.pop()` without confirmation dialog and without writing |
| REQ-FCP-014 | Submitting state | MUST | While `isSubmitting == true`, PUBLICAR shows loading spinner and is disabled; CANCELAR remains enabled |
| REQ-FCP-015 | Design constraints | MUST | All colors via `AppPalette.of(context)`; all icons via `TreinoIcon.X`; spacing scale 8/12/14/18/20 only; no own Scaffold (relies on `_ShellScaffold`) |
| REQ-FCP-016 | TDD requirement | MUST | A test for every widget and notifier MUST exist in git history BEFORE the corresponding implementation commit |

---

## Section B — REQ-FSU-* (Search Users · PR#2)

| REQ | Name | Strength | Summary |
|-----|------|----------|---------|
| REQ-FSU-001 | SearchUsersScreen route | MUST | `/feed/search` GoRoute nested under `/feed` ShellRoute |
| REQ-FSU-002 | Search-icon navigation | MUST | Search icon in `_FeedHeader` → `context.push('/feed/search')` |
| REQ-FSU-003 | Screen composition | MUST | Back arrow + TextField search bar (placeholder "Buscar por nombre") + clear (X) button visible when text is non-empty |
| REQ-FSU-004 | Debounce + min query | MUST | Query is debounced 300ms; search triggers ONLY when input ≥ 2 chars |
| REQ-FSU-005 | Initial state | MUST | Below 2 chars, screen shows `FeedEmptyState(message: 'Buscá usuarios por nombre')` |
| REQ-FSU-006 | searchUsersProvider | MUST | `FutureProvider.family<List<UserProfile>, String>` keyed on lowercased query string |
| REQ-FSU-007 | UserRepository.searchByDisplayName | MUST | Firestore prefix range query on `displayNameLowercase`; returns at most 20 results |
| REQ-FSU-008 | displayNameLowercase field | MUST | `UserProfile` MUST have `String? displayNameLowercase` field (nullable for legacy doc resilience); Freezed-generated with `fromJson`/`toJson`/`copyWith` |
| REQ-FSU-009 | Write on create | MUST | `UserRepository.getOrCreate` and `createIfAbsent` MUST write `displayNameLowercase: displayName?.toLowerCase()` |
| REQ-FSU-010 | Write on update | MUST | `UserRepository.update` MUST include `displayNameLowercase: displayName?.toLowerCase()` when `displayName` is updated |
| REQ-FSU-011 | Write on ProfileSetup | MUST | `ProfileSetupFlow` MUST write `displayNameLowercase` when `displayName` is committed for the first time |
| REQ-FSU-012 | UserSearchResultTile | MUST | Results rendered as `UserSearchResultTile`: `PostAvatar` + display name + gym name (via `gymNameFromId`); tapping navigates to `context.push('/feed/profile/$uid')` |
| REQ-FSU-013 | No inline follow | MUST NOT | Search result tiles MUST NOT include a follow/unfollow button |
| REQ-FSU-014 | No-results state | MUST | `FeedEmptyState(message: 'Sin resultados para "$query"')` when search returns empty list |
| REQ-FSU-015 | Loading state | MUST | `CircularProgressIndicator(color: palette.accent)` centered while provider is loading |
| REQ-FSU-016 | Error state | MUST | Inline `Text('No pudimos buscar usuarios. Intentá de nuevo.')` styled with error color when provider errors |
| REQ-FSU-017 | Design constraints | MUST | All colors via `AppPalette.of(context)`; all icons via `TreinoIcon.X`; spacing scale 8/12/14/18/20 only; no own Scaffold (relies on `_ShellScaffold`) |
| REQ-FSU-018 | TDD requirement | MUST | A test for every widget and provider MUST exist in git history BEFORE the corresponding implementation commit |

---

## Section C — Scenarios (SCENARIO-218..SCENARIO-251)

### Create Post (SCENARIO-218..SCENARIO-233)

#### SCENARIO-218 — Route registration (REQ-FCP-001)
- GIVEN the app router is initialized
- WHEN the route tree for `/feed` is inspected
- THEN a `GoRoute(path: 'create')` child exists under the `/feed` ShellRoute
- AND navigating to `/feed/create` renders `CreatePostScreen`

#### SCENARIO-219 — Plus-button navigation (REQ-FCP-002)
- GIVEN the feed screen is visible
- WHEN the user taps the plus button in `_FeedHeader`
- THEN the router pushes `/feed/create`
- AND `CreatePostScreen` appears in the navigation stack

#### SCENARIO-220 — Form structure (REQ-FCP-003)
- GIVEN `CreatePostScreen` is rendered
- WHEN the widget tree is inspected
- THEN a CANCELAR button, a title widget, a PUBLICAR button, a multiline `TextField`, a 3-option privacy selector, and a routine-tag chip are all present

#### SCENARIO-221 — Char counter and limit (REQ-FCP-004)
- GIVEN the text field is empty
- WHEN the user types 280 characters
- THEN the char counter shows "280/280"
- AND the field rejects any additional input
- AND the counter is visible throughout

#### SCENARIO-222 — PUBLICAR disabled when empty (REQ-FCP-005)
- GIVEN the text field is empty or contains only whitespace
- WHEN the screen renders
- THEN the PUBLICAR button is disabled

#### SCENARIO-223 — PUBLICAR enabled with content (REQ-FCP-005)
- GIVEN the text field contains at least one non-whitespace character
- WHEN the screen renders
- THEN the PUBLICAR button is enabled

#### SCENARIO-224 — Privacy default (REQ-FCP-006)
- GIVEN `CreatePostScreen` is first rendered
- WHEN no privacy option has been tapped
- THEN the `friends` privacy pill is selected

#### SCENARIO-225 — Gym pill disabled (REQ-FCP-007)
- GIVEN the authenticated user's `userProfileProvider.gymId` is `null`
- WHEN `CreatePostScreen` renders
- THEN the gym privacy pill has opacity 0.4
- AND displays helper text "Asociate a un gym para postear acá"
- AND `onTap` is null

#### SCENARIO-226 — Routine tag stub (REQ-FCP-008)
- GIVEN `CreatePostScreen` is rendered
- WHEN the routine tag chip is inspected
- THEN it shows the label "ETIQUETAR RUTINA" at opacity 0.4 with `onTap: null`

#### SCENARIO-227 — Successful post creation (REQ-FCP-010, REQ-FCP-011)
- GIVEN the user has typed non-empty text and selected privacy
- WHEN the user taps PUBLICAR
- THEN `PostRepository.create()` is called with the correct author fields
- AND on completion `myFriendsFeedProvider`, `feedPublicProvider`, and `myGymFeedProvider` are invalidated
- AND `context.pop()` is called

#### SCENARIO-228 — Submitting state (REQ-FCP-014)
- GIVEN the user taps PUBLICAR and the submit is in progress
- WHEN `isSubmitting == true`
- THEN the PUBLICAR button shows a loading spinner and is disabled
- AND the CANCELAR button remains enabled

#### SCENARIO-229 — Submit error (REQ-FCP-012)
- GIVEN the user taps PUBLICAR and `PostRepository.create()` throws an error
- WHEN the error is caught
- THEN an inline error message is displayed
- AND the PUBLICAR button is re-enabled
- AND no snackbar is shown

#### SCENARIO-230 — CANCELAR without write (REQ-FCP-013)
- GIVEN the user has typed text into the form
- WHEN the user taps CANCELAR
- THEN `context.pop()` is called
- AND no post is written to the repository

#### SCENARIO-231 — Gym-pill guard in notifier (REQ-FCP-007, REQ-FCP-010)
- GIVEN `gymId == null` and gym privacy is somehow selected programmatically
- WHEN submit is triggered
- THEN the notifier MUST NOT call `PostRepository.create()` with `privacy == gym`
- AND instead falls back to `PostPrivacy.friends` or returns an error

#### SCENARIO-232 — Keyboard scroll (REQ-FCP-015)
- GIVEN the virtual keyboard is open
- WHEN the form is scrolled
- THEN the PUBLICAR button remains reachable via scroll without being obscured

#### SCENARIO-233 — Design token compliance (REQ-FCP-015)
- GIVEN `CreatePostScreen` is rendered
- WHEN the widget tree is inspected
- THEN no hard-coded color values or `PhosphorIcons.X` references exist
- AND all spacing values are within {8, 12, 14, 18, 20}

---

### Search Users (SCENARIO-234..SCENARIO-251)

#### SCENARIO-234 — Route registration (REQ-FSU-001)
- GIVEN the app router is initialized
- WHEN the route tree for `/feed` is inspected
- THEN a `GoRoute(path: 'search')` child exists under the `/feed` ShellRoute
- AND navigating to `/feed/search` renders `SearchUsersScreen`

#### SCENARIO-235 — Search-icon navigation (REQ-FSU-002)
- GIVEN the feed screen is visible
- WHEN the user taps the search icon in `_FeedHeader`
- THEN the router pushes `/feed/search`
- AND `SearchUsersScreen` appears in the navigation stack

#### SCENARIO-236 — Screen structure (REQ-FSU-003)
- GIVEN `SearchUsersScreen` is rendered with empty input
- WHEN the widget tree is inspected
- THEN a back arrow, a `TextField` with placeholder "Buscar por nombre", and no clear button are present

#### SCENARIO-237 — Clear button appears (REQ-FSU-003)
- GIVEN `SearchUsersScreen` is rendered
- WHEN the user types any text into the search bar
- THEN a clear (X) button appears

#### SCENARIO-238 — Clear button clears input (REQ-FSU-003)
- GIVEN text is present in the search bar
- WHEN the user taps the clear (X) button
- THEN the text field is emptied

#### SCENARIO-239 — Initial state below threshold (REQ-FSU-004, REQ-FSU-005)
- GIVEN `SearchUsersScreen` is rendered
- WHEN the user types fewer than 2 characters
- THEN `FeedEmptyState(message: 'Buscá usuarios por nombre')` is displayed
- AND no search query is fired

#### SCENARIO-240 — Debounce suppresses rapid queries (REQ-FSU-004)
- GIVEN the user is typing
- WHEN characters are entered faster than 300ms apart
- THEN only the query present 300ms after the last keystroke triggers a search

#### SCENARIO-241 — Search triggers at 2 chars (REQ-FSU-004, REQ-FSU-006)
- GIVEN the user has typed 2 or more characters
- WHEN 300ms have elapsed since the last keystroke
- THEN `searchUsersProvider` is called with the lowercased query
- AND `UserRepository.searchByDisplayName` is invoked

#### SCENARIO-242 — Search result limit (REQ-FSU-007)
- GIVEN the Firestore collection has 50 users matching a prefix
- WHEN `UserRepository.searchByDisplayName` executes the range query
- THEN at most 20 `UserProfile` documents are returned

#### SCENARIO-243 — Case-insensitive prefix match (REQ-FSU-007, REQ-FSU-008)
- GIVEN a user with `displayName: "Martin"` and `displayNameLowercase: "martin"`
- WHEN a search is performed with query `"mar"`
- THEN the user appears in results

#### SCENARIO-244 — displayNameLowercase field model (REQ-FSU-008)
- GIVEN a Firestore document has `displayNameLowercase` present
- WHEN `UserProfile.fromJson` parses it
- THEN `userProfile.displayNameLowercase` equals the stored value
- AND GIVEN the field is absent
- THEN `userProfile.displayNameLowercase` is `null`

#### SCENARIO-245 — Write on create (REQ-FSU-009)
- GIVEN `UserRepository.getOrCreate` or `createIfAbsent` is called with a `displayName`
- WHEN the Firestore write is executed
- THEN the document includes `displayNameLowercase: displayName.toLowerCase()`

#### SCENARIO-246 — Write on update (REQ-FSU-010)
- GIVEN `UserRepository.update` is called with a new `displayName`
- WHEN the Firestore write is executed
- THEN the document includes `displayNameLowercase: displayName.toLowerCase()`

#### SCENARIO-247 — Write in ProfileSetupFlow (REQ-FSU-011)
- GIVEN the user completes the profile setup and commits a `displayName`
- WHEN `ProfileSetupFlow` writes the profile document
- THEN `displayNameLowercase: displayName.toLowerCase()` is included in the write payload

#### SCENARIO-248 — Result tile structure (REQ-FSU-012, REQ-FSU-013)
- GIVEN search returns a non-empty list
- WHEN `UserSearchResultTile` is rendered
- THEN it shows `PostAvatar`, display name, and gym name
- AND contains no follow or unfollow button

#### SCENARIO-249 — Result tile navigation (REQ-FSU-012)
- GIVEN search results are visible
- WHEN the user taps a `UserSearchResultTile`
- THEN the router pushes `/feed/profile/$uid` for that user

#### SCENARIO-250 — Empty results state (REQ-FSU-014)
- GIVEN a query of ≥2 chars returns zero results
- WHEN the provider completes successfully
- THEN `FeedEmptyState(message: 'Sin resultados para "$query"')` is displayed

#### SCENARIO-251 — Error state (REQ-FSU-016)
- GIVEN the search provider throws an error
- WHEN the widget rebuilds
- THEN inline text "No pudimos buscar usuarios. Intentá de nuevo." is displayed in error color

---

## Cross-Cutting Constraints

| Constraint | Rule |
|---|---|
| Colors | ALL colors via `AppPalette.of(context)`. No hex literals anywhere. |
| Icons | ALL icons via `TreinoIcon.X`. No direct `PhosphorIcons.X` references. |
| Spacing | Only values from {8, 12, 14, 18, 20}. No arbitrary spacing. |
| Scaffold | `_ShellScaffold` provides Scaffold/AppBackground/SafeArea. New screens MUST NOT add their own. |
| TDD | Strict TDD active. Tests MUST precede implementation in git history (per `strict-tdd.md`). |
| Legacy users | `displayNameLowercase` backfill is lazy (on next `UserRepository.update`). Explicit backfill script is out of scope. Legacy users without the field are invisible in search until their next profile edit — this is an accepted MVP trade-off. |
| Feed providers | If any of the 3 invalidated providers is `StreamProvider` (not `FutureProvider`), `ref.invalidate` semantics differ — confirm in design before apply. |

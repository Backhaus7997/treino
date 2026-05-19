# Spec: user-public-profiles

**Change**: user-public-profiles
**PRs**: PR#A (Foundation + Etapa 4 refactor) → PR#B (Search UI)
**Scenario range**: SCENARIO-252..SCENARIO-297
**REQ-UPP count**: 26 | **REQ-UPS count**: 20

---

## SECTION A — PR#A: UserPublicProfile Foundation + Etapa 4 Refactor

### REQ-UPP Requirements

| ID | Area | Requirement |
|----|------|-------------|
| REQ-UPP-001 | Model | `UserPublicProfile` MUST be a Freezed model with fields `{uid, displayName?, displayNameLowercase?, avatarUrl?, gymId?}`. `uid` is non-nullable. All other fields are nullable. The model MUST be JSON-serializable. |
| REQ-UPP-002 | Model | `displayNameLowercase` MUST equal `displayName?.toLowerCase()`. It MUST NOT be set independently by callers. |
| REQ-UPP-003 | Repository | `UserPublicProfileRepository` MUST expose `get(uid)`, `set(profile)`, and `searchByDisplayName(query, {int limit})` methods. |
| REQ-UPP-004 | Repository | `searchByDisplayName` MUST issue a Firestore prefix range query on the `displayNameLowercase` field (range `[query, query + '']`). |
| REQ-UPP-005 | Repository | `searchByDisplayName` MUST return at most 20 results. |
| REQ-UPP-006 | Repository | `searchByDisplayName` MUST return an empty list when the query string is empty after `.trim()`. |
| REQ-UPP-007 | Provider | `userPublicProfileRepositoryProvider` MUST expose a singleton `UserPublicProfileRepository` via Riverpod `Provider`. |
| REQ-UPP-008 | Provider | `userPublicProfileProvider(uid)` MUST be a `FutureProvider.family<UserPublicProfile?, String>` that fetches a single profile by `uid`. |
| REQ-UPP-009 | Sync — UserRepository | `UserRepository.getOrCreate` MUST write both `users/{uid}` AND `userPublicProfiles/{uid}` in the same `WriteBatch` (single atomic commit). |
| REQ-UPP-010 | Sync — UserRepository | `UserRepository.createIfAbsent` MUST write both `users/{uid}` AND `userPublicProfiles/{uid}` in the same `WriteBatch`. |
| REQ-UPP-011 | Sync — UserRepository | `UserRepository.update` MUST include a `userPublicProfiles/{uid}` write in the `WriteBatch` whenever `displayName`, `avatarUrl`, or `gymId` are present in the update partial. If none of those fields are in the partial, the `userPublicProfiles` doc MUST NOT be touched. |
| REQ-UPP-012 | Sync — UserRepository | The dual-write in all `UserRepository` methods MUST derive `displayNameLowercase` automatically. Callers MUST NOT pass `displayNameLowercase`. |
| REQ-UPP-013 | Sync — ProfileSetupNotifier | `ProfileSetupNotifier.submit()` MUST write both `users/{uid}` AND `userPublicProfiles/{uid}` in a single `WriteBatch.commit()` call. |
| REQ-UPP-014 | Firestore Rules | A `match /userPublicProfiles/{uid}` block MUST be added to `firestore.rules` permitting: `read` and `list` for `auth != null`; `write` only for `auth.uid == uid`. |
| REQ-UPP-015 | Firestore Rules | Non-owner write to `userPublicProfiles/{uid}` MUST be denied by rules. |
| REQ-UPP-016 | Firestore Rules | `users/{uid}` rules MUST remain unchanged (owner-only read). |
| REQ-UPP-017 | Etapa 4 | `publicProfileViewProvider` MUST source `displayName`, `avatarUrl`, and `gymId` from `userPublicProfileProvider(uid)`, NOT from `firstPostByAuthorProvider`. |
| REQ-UPP-018 | Etapa 4 | `publicProfileViewProvider` MUST fall back to the string `'Anónimo'` when `userPublicProfileProvider` returns `null`. |
| REQ-UPP-019 | Etapa 4 | `firstPostByAuthorProvider` MUST remain in its file. Its existing SCENARIOs (SCENARIO-200..202) MUST remain unchanged and green. |
| REQ-UPP-020 | Etapa 4 | SCENARIO-203..205 fixtures MUST seed `userPublicProfiles` instead of `posts`. Assertions MUST remain behaviorally equivalent. |
| REQ-UPP-021 | Backfill | `scripts/backfill_user_public_profiles.js` MUST exist with Node.js Admin SDK code and a comment block explaining lazy migration as the primary strategy and script execution as an ops escape hatch. |
| REQ-UPP-022 | Cross-cutting | All color usage in PR#A code MUST use `AppPalette.of(context)`. HEX literals MUST NOT appear. |
| REQ-UPP-023 | Cross-cutting | All icon usage in PR#A code MUST use `TreinoIcon.X`. Direct `PhosphorIcons.X` references MUST NOT appear. |
| REQ-UPP-024 | Cross-cutting | Spacing MUST use the scale 8 / 12 / 14 / 18 / 20 px. |
| REQ-UPP-025 | Cross-cutting | Strict TDD applies: test files MUST exist in git history BEFORE their corresponding production files for every new widget, repository, and provider in PR#A. |
| REQ-UPP-026 | Cross-cutting | The `UserProfile` model MUST NOT be modified in PR#A or any descendant PR. |

---

## SECTION B — PR#B: Search UI

### REQ-UPS Requirements

| ID | Area | Requirement |
|----|------|-------------|
| REQ-UPS-001 | Screen | `SearchUsersScreen` MUST be a `ConsumerStatefulWidget` registered at route path `search` nested under the `/feed` `ShellRoute`. |
| REQ-UPS-002 | Screen | The screen header MUST contain a back arrow and the title `"BUSCAR USUARIOS"`. |
| REQ-UPS-003 | Screen | A `TextField` with placeholder `"Buscar por nombre"` MUST be present. A clear (X) button MUST appear when the field is non-empty and MUST clear the field when tapped. |
| REQ-UPS-004 | Screen | User input MUST be debounced 300 ms before triggering a search. Search MUST NOT trigger for fewer than 2 characters. |
| REQ-UPS-005 | Screen | When the query has fewer than 2 characters the screen MUST display `FeedEmptyState(message: 'Buscá usuarios por nombre', icon: TreinoIcon.users)`. |
| REQ-UPS-006 | Provider | `searchUsersProvider` MUST be `FutureProvider.autoDispose.family<List<UserPublicProfile>, String>` keyed on the lowercase query string. |
| REQ-UPS-007 | Provider | `searchUsersProvider` MUST delegate to `UserPublicProfileRepository.searchByDisplayName`. |
| REQ-UPS-008 | Result tile | `UserSearchResultTile` MUST render a `PostAvatar`, the user's `displayName`, and the gym name resolved via `gymNameFromId`. |
| REQ-UPS-009 | Result tile | `UserSearchResultTile` MUST be tappable and MUST call `context.push('/feed/profile/$uid')` on tap. |
| REQ-UPS-010 | Result tile | `UserSearchResultTile` MUST NOT contain an inline follow button. |
| REQ-UPS-011 | States | When results are available the screen MUST render a `ListView.separated` of `UserSearchResultTile` items with 8 px separators. |
| REQ-UPS-012 | States | While the search `FutureProvider` is loading the screen MUST display a centered `CircularProgressIndicator` using `palette.accent` color. |
| REQ-UPS-013 | States | When the search returns zero results the screen MUST display `FeedEmptyState(message: 'Sin resultados para "$query"', ...)`. |
| REQ-UPS-014 | States | On provider error the screen MUST display centered text `'No pudimos buscar usuarios. Intentá de nuevo.'`. |
| REQ-UPS-015 | Integration | The search icon in `_FeedHeader` MUST be wrapped in a `GestureDetector` that calls `context.push('/feed/search')`. |
| REQ-UPS-016 | Integration | `router.dart` MUST register `GoRoute(path: 'search', ...)` nested under the `/feed` shell route. |
| REQ-UPS-017 | Cross-cutting | All color usage in PR#B code MUST use `AppPalette.of(context)`. HEX literals MUST NOT appear. |
| REQ-UPS-018 | Cross-cutting | All icon usage in PR#B code MUST use `TreinoIcon.X`. Direct `PhosphorIcons.X` references MUST NOT appear. |
| REQ-UPS-019 | Cross-cutting | Spacing MUST use the scale 8 / 12 / 14 / 18 / 20 px. |
| REQ-UPS-020 | Cross-cutting | Strict TDD applies: test files MUST exist in git history BEFORE their corresponding production files for every new widget and provider in PR#B. |

---

## SECTION C — Scenarios (SCENARIO-252..297)

### UserPublicProfile model + repository (SCENARIO-252..258)

#### SCENARIO-252: Model round-trip serialization

- GIVEN a `UserPublicProfile` with `uid='u1'`, `displayName='Martín'`, `displayNameLowercase='martín'`, `avatarUrl=null`, `gymId='g1'`
- WHEN serialized to JSON and deserialized back
- THEN the resulting object equals the original

#### SCENARIO-253: displayNameLowercase auto-derivation

- GIVEN `displayName = 'Martín Backhaus'`
- WHEN a `UserPublicProfile` is constructed with that `displayName`
- THEN `displayNameLowercase == 'martín backhaus'`

#### SCENARIO-254: Repository get returns null for missing doc

- GIVEN no document exists at `userPublicProfiles/u99`
- WHEN `UserPublicProfileRepository.get('u99')` is called
- THEN it returns `null` without throwing

#### SCENARIO-255: Repository set round-trip

- GIVEN a `UserPublicProfile` with `uid='u1'`
- WHEN `set(profile)` is called and then `get('u1')` is called
- THEN the returned profile equals the original

#### SCENARIO-256: searchByDisplayName prefix match

- GIVEN `userPublicProfiles` contains `{uid:'a', displayNameLowercase:'martín'}` and `{uid:'b', displayNameLowercase:'marta'}`
- WHEN `searchByDisplayName('mar')` is called
- THEN both records are returned

#### SCENARIO-257: searchByDisplayName respects 20-result limit

- GIVEN 25 documents whose `displayNameLowercase` starts with `'test'`
- WHEN `searchByDisplayName('test')` is called
- THEN exactly 20 results are returned

#### SCENARIO-258: searchByDisplayName returns empty list for blank query

- GIVEN any collection state
- WHEN `searchByDisplayName('   ')` is called (whitespace only)
- THEN an empty list is returned and no Firestore query is issued

---

### UserRepository dual-write (SCENARIO-259..264)

#### SCENARIO-259: getOrCreate writes both collections atomically

- GIVEN no document at `users/u1` or `userPublicProfiles/u1`
- WHEN `UserRepository.getOrCreate` is called for `uid='u1'`
- THEN both `users/u1` AND `userPublicProfiles/u1` documents exist after a single batch commit

#### SCENARIO-260: createIfAbsent writes both collections atomically

- GIVEN no document at `users/u1` or `userPublicProfiles/u1`
- WHEN `UserRepository.createIfAbsent` is called for `uid='u1'`
- THEN both `users/u1` AND `userPublicProfiles/u1` documents exist after a single batch commit

#### SCENARIO-261: update with displayName change propagates to public profile

- GIVEN `users/u1` and `userPublicProfiles/u1` exist
- WHEN `UserRepository.update` is called with `{displayName: 'Nueva'}` for `uid='u1'`
- THEN `userPublicProfiles/u1.displayName == 'nueva'` (lowercased) and `userPublicProfiles/u1.displayNameLowercase == 'nueva'`

#### SCENARIO-262: update without name/avatar/gym does not touch public profile

- GIVEN `userPublicProfiles/u1` exists with `displayName='Original'`
- WHEN `UserRepository.update` is called with a partial that does NOT contain `displayName`, `avatarUrl`, or `gymId`
- THEN `userPublicProfiles/u1.displayName` remains `'Original'` unchanged

#### SCENARIO-263: displayNameLowercase auto-derived — caller cannot override

- GIVEN `UserRepository.getOrCreate` is called with `displayName='Alice'`
- WHEN the batch commits
- THEN `userPublicProfiles/{uid}.displayNameLowercase == 'alice'` regardless of any caller-supplied value

#### SCENARIO-264: Partial batch failure leaves neither doc written (atomicity)

- GIVEN a simulated Firestore batch failure mid-commit
- WHEN `getOrCreate` attempts the dual-write
- THEN neither `users/{uid}` nor `userPublicProfiles/{uid}` is modified (WriteBatch atomicity guarantee)

---

### ProfileSetupNotifier.submit dual-write (SCENARIO-265..267)

#### SCENARIO-265: submit writes both docs in one commit

- GIVEN authenticated user `uid='u1'` completing profile setup
- WHEN `ProfileSetupNotifier.submit()` completes successfully
- THEN both `users/u1` AND `userPublicProfiles/u1` documents are created/updated in a single `WriteBatch.commit()` call

#### SCENARIO-266: submit derives displayNameLowercase automatically

- GIVEN `submit()` is called with `displayName='Carlos'`
- WHEN the batch commits
- THEN `userPublicProfiles/u1.displayNameLowercase == 'carlos'`

#### SCENARIO-267: submit failure leaves both docs unchanged

- GIVEN a simulated commit failure
- WHEN `ProfileSetupNotifier.submit()` is called
- THEN neither the `users` nor `userPublicProfiles` document is partially written

---

### Firestore rules (SCENARIO-268..270)

#### SCENARIO-268: Authenticated user can read any userPublicProfiles doc

- GIVEN an authenticated user who does NOT own `userPublicProfiles/u2`
- WHEN a read on `userPublicProfiles/u2` is attempted
- THEN the read succeeds

#### SCENARIO-269: Non-owner cannot write userPublicProfiles doc

- GIVEN an authenticated user `uid='u1'` attempting to write `userPublicProfiles/u2` (different uid)
- WHEN the write is attempted
- THEN it is denied (permission-denied)

#### SCENARIO-270: Owner can write their own userPublicProfiles doc

- GIVEN an authenticated user `uid='u1'`
- WHEN a write on `userPublicProfiles/u1` is attempted
- THEN the write succeeds

---

### publicProfileViewProvider refactor (SCENARIO-271..274)

#### SCENARIO-271: publicProfileViewProvider sources displayName from userPublicProfileProvider

- GIVEN `userPublicProfiles/u1` contains `displayName='Ana'` and `firstPostByAuthorProvider` is NOT seeded for `u1`
- WHEN `publicProfileViewProvider('u1')` is evaluated
- THEN the returned `PublicProfileView.authorDisplayName == 'Ana'`

#### SCENARIO-272: publicProfileViewProvider falls back to 'Anónimo' when profile missing

- GIVEN no document at `userPublicProfiles/u1`
- WHEN `publicProfileViewProvider('u1')` is evaluated
- THEN the returned `PublicProfileView.authorDisplayName == 'Anónimo'`

#### SCENARIO-273: SCENARIO-203 rewrite — fixture uses userPublicProfiles

- GIVEN `userPublicProfiles/u1` is seeded (NOT posts)
- WHEN `publicProfileViewProvider('u1')` resolves
- THEN the view reflects the seeded public profile data (equivalent behavior to previous SCENARIO-203)

#### SCENARIO-274: firstPostByAuthorProvider scenarios 200..202 remain unchanged

- GIVEN the existing SCENARIO-200..202 test fixtures (seeding posts)
- WHEN `firstPostByAuthorProvider` is evaluated
- THEN all three scenarios pass without modification

---

### searchUsersProvider (SCENARIO-275..280)

#### SCENARIO-275: Provider delegates to repository

- GIVEN a query string `'mar'`
- WHEN `searchUsersProvider('mar')` is evaluated
- THEN it calls `UserPublicProfileRepository.searchByDisplayName('mar')` and returns the result

#### SCENARIO-276: Provider returns empty list for blank query

- GIVEN query `'  '` (whitespace)
- WHEN `searchUsersProvider('  ')` is evaluated
- THEN it returns an empty list without calling the repository

#### SCENARIO-277: Provider enforces 2-char minimum

- GIVEN query `'m'` (1 character)
- WHEN `searchUsersProvider('m')` is evaluated
- THEN it returns an empty list without issuing a Firestore call

#### SCENARIO-278: Provider is keyed on lowercase query

- GIVEN queries `'MAR'` and `'mar'`
- WHEN both are evaluated
- THEN they share the same provider instance (family key equivalence)

#### SCENARIO-279: Provider returns empty list when no matches found

- GIVEN no documents match query `'xyz123'`
- WHEN `searchUsersProvider('xyz123')` resolves
- THEN it returns an empty list

#### SCENARIO-280: Provider surfaces repository error as AsyncError

- GIVEN the repository throws on `searchByDisplayName`
- WHEN `searchUsersProvider` is evaluated
- THEN the provider transitions to `AsyncError`

---

### UserSearchResultTile (SCENARIO-281..285)

#### SCENARIO-281: Tile renders avatar, displayName, and gym name

- GIVEN a `UserPublicProfile` with `displayName='Ana'`, `gymId='g1'`
- WHEN `UserSearchResultTile` is built
- THEN it renders a `PostAvatar`, the text `'Ana'`, and the gym name returned by `gymNameFromId('g1')`

#### SCENARIO-282: Tile renders gracefully when displayName is null

- GIVEN a `UserPublicProfile` with `displayName=null`
- WHEN `UserSearchResultTile` is built
- THEN it renders without throwing and shows a fallback (empty or placeholder)

#### SCENARIO-283: Tile tap navigates to public profile

- GIVEN a `UserSearchResultTile` for `uid='u1'`
- WHEN the tile is tapped
- THEN `context.push('/feed/profile/u1')` is called

#### SCENARIO-284: Tile contains no follow button

- GIVEN any `UserSearchResultTile`
- WHEN the widget tree is inspected
- THEN no follow button widget is present

#### SCENARIO-285: Tile renders gym name as empty when gymId is null

- GIVEN a `UserPublicProfile` with `gymId=null`
- WHEN `UserSearchResultTile` is built
- THEN no exception is thrown and the gym name area is blank or omitted

---

### SearchUsersScreen (SCENARIO-286..295)

#### SCENARIO-286: Initial state shows empty prompt

- GIVEN the screen is opened with no query entered
- WHEN the widget tree is inspected
- THEN `FeedEmptyState` is displayed with message `'Buscá usuarios por nombre'`

#### SCENARIO-287: Query below 2 chars shows empty prompt

- GIVEN the user types `'a'` in the search field
- WHEN the widget tree is inspected
- THEN `FeedEmptyState` with message `'Buscá usuarios por nombre'` is still displayed

#### SCENARIO-288: Loading state shows spinner

- GIVEN a query of 3+ chars and the provider is in loading state
- WHEN the widget tree is inspected
- THEN a centered `CircularProgressIndicator` is present

#### SCENARIO-289: Data state renders result list

- GIVEN the provider returns 3 `UserPublicProfile` records
- WHEN the widget tree is inspected
- THEN a `ListView` with 3 `UserSearchResultTile` items is displayed

#### SCENARIO-290: Empty results state shows no-results message

- GIVEN a query of 3+ chars and the provider returns an empty list
- WHEN the widget tree is inspected
- THEN `FeedEmptyState` is displayed with a message containing the query string

#### SCENARIO-291: Error state shows error text

- GIVEN the provider returns an error
- WHEN the widget tree is inspected
- THEN the text `'No pudimos buscar usuarios. Intentá de nuevo.'` is visible

#### SCENARIO-292: Clear button appears when field is non-empty

- GIVEN the search field contains `'mart'`
- WHEN the widget tree is inspected
- THEN a clear (X) button is visible

#### SCENARIO-293: Clear button resets field and shows empty prompt

- GIVEN the clear button is visible
- WHEN it is tapped
- THEN the field is cleared and `FeedEmptyState` with `'Buscá usuarios por nombre'` is displayed

#### SCENARIO-294: Back arrow navigates away

- GIVEN `SearchUsersScreen` is on the navigation stack
- WHEN the back arrow is tapped
- THEN the screen is popped from the navigator

#### SCENARIO-295: Header title is "BUSCAR USUARIOS"

- GIVEN `SearchUsersScreen` is rendered
- WHEN the widget tree is inspected
- THEN the text `'BUSCAR USUARIOS'` is visible in the header

---

### Integration (SCENARIO-296..297)

#### SCENARIO-296: Feed search icon pushes /feed/search route

- GIVEN the feed screen is displayed
- WHEN the search icon in `_FeedHeader` is tapped
- THEN `context.push('/feed/search')` is called

#### SCENARIO-297: /feed/search route is registered in router

- GIVEN the application router
- WHEN the route tree is inspected
- THEN a `GoRoute` with `path: 'search'` exists nested under the `/feed` shell route

---

## Cross-Cutting Constraints

| Constraint | Applies to |
|------------|-----------|
| All colors via `AppPalette.of(context)` — NO hex literals | PR#A + PR#B |
| All icons via `TreinoIcon.X` — NO `PhosphorIcons.X` direct | PR#A + PR#B |
| Spacing scale: 8 / 12 / 14 / 18 / 20 px only | PR#A + PR#B |
| `_ShellScaffold` provides Scaffold/AppBackground/SafeArea — new screens MUST NOT add their own | PR#B (`SearchUsersScreen`) |
| Strict TDD: test commits precede production commits in git history | PR#A + PR#B |
| `UserProfile` model MUST NOT be modified | PR#A + PR#B |
| `firestore.rules` audit MUST list every query + rule that grants it (from proposal lesson learned) | PR#A |
| T35-style manual rules test required before PR#A merge | PR#A |

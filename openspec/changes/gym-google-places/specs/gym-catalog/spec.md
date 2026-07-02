# Delta for Gym Catalog

## ADDED Requirements

### Requirement: Gym docs may originate from Google Places

The system MUST support `gyms/{gymId}` docs whose `id` is a Google Places `place_id` (New API) rather than a curated/seeded id, and MUST add `GymSource.googlePlaces` to `gym_source.dart` alongside the existing `seed`/`selfService` values so provenance stays queryable.

For a Google-Places-sourced doc, `brandId`, `brandName`, and `branchName` MUST be `null`. `lat`, `lng`, and `geohash` MUST be populated (derived from the Place's location). `name` MUST hold the Place's `displayName` and `address` MUST hold the Place's `formattedAddress`.

#### Scenario: Places-sourced doc has no brand/branch grouping

- GIVEN a `gyms/{place_id}` doc created from a Google Places selection
- WHEN inspecting the doc
- THEN `brandId`, `brandName`, and `branchName` are all `null`
- AND `source` is `googlePlaces`

#### Scenario: Places-sourced doc still has coordinates

- GIVEN a `gyms/{place_id}` doc created from a Google Places selection
- WHEN inspecting `lat`, `lng`, and `geohash`
- THEN all three are non-null

### Requirement: Gym doc creation is on-demand via a Cloud Function upsert

The system MUST create a `gyms/{place_id}` doc on first selection of that Place, performed server-side by a Cloud Function using the Admin SDK (bypassing the athlete-facing `create` rule). The Function MUST first read `gyms/{place_id}`; if the doc already exists, it MUST return the existing doc and MUST NOT call Place Details again (read-through cache, avoids duplicate Places billing).

#### Scenario: First selection of a new Place creates the doc

- GIVEN a Google Place has never been selected by any user before
- WHEN a user selects it in the gym picker
- THEN the Cloud Function calls Place Details, upserts `gyms/{place_id}` via Admin SDK, and returns the created doc

#### Scenario: Repeated selection reuses the existing doc

- GIVEN `gyms/{place_id}` already exists from a prior selection
- WHEN another user selects the same Place
- THEN the Cloud Function returns the existing doc without calling Place Details again

## MODIFIED Requirements

### Requirement: Unified gym model

The system MUST use `lib/features/gyms/domain/gym.dart` (`Gym`, freezed) as the only gym model in the codebase. The system MUST NOT retain `lib/features/profile_setup/domain/gym.dart` or any duplicate gym model.

The system MUST require `lat`, `lng`, and `geohash` on every `Gym` (no relaxation to optional), whether the doc originates from curated seed data or from a Google Places selection.

The system MUST treat `brandName`, `brandId`, and `branchName` as optional (nullable) on `Gym`, since Google-Places-sourced docs never populate them and no grouping UI consumes them (brand/branch grouping is retired — see "Gym catalog is two-level" below).

The system MUST preserve the sentinel `kNoGymId = 'no-gym'` as the "no gym" selection option.

The system MAY include optional `city` and `province` string fields on `Gym` to support future nationwide filtering. These fields, when absent, MUST NOT break deserialization of existing docs.

(Previously: required non-null `brandName`/`brandId`/`branchName` on every `Gym`; now optional because Places-sourced docs never populate them.)

#### Scenario: Legacy model and duplicated maps are removed

- GIVEN the codebase after this change is applied
- WHEN searching for `profile_setup/domain/gym.dart`, `_kHardcodedGyms`, `gymSearchQueryProvider`, or `filteredGymsProvider`
- THEN none of these symbols or files exist anymore

#### Scenario: Existing seed docs decode without city/province

- GIVEN a `gyms/{gymId}` doc seeded before `city`/`province` existed
- WHEN the app deserializes it via `Gym.fromJson`
- THEN deserialization succeeds and `city`/`province` are `null`

#### Scenario: Curated gym always has coordinates

- GIVEN any gym returned by `GymRepository`
- WHEN inspecting its `lat`, `lng`, and `geohash` fields
- THEN all three are non-null, regardless of whether the doc is curated-seed or Places-sourced

### Requirement: Athlete gym selection is a single debounced search

The system MUST replace the two-step brand-then-branch picker in `step_2_gym.dart` (onboarding) and `profile_gym_screen.dart` (profile edit) with a single debounced search-as-you-type box whose results are Google Places Autocomplete predictions (name + address per suggestion).

The system MUST NOT require location permission to search: if location permission is denied or unavailable, the search MUST run unbiased (no `locationBias`) rather than erroring or blocking input.

The system MUST expose distinct loading, error, and retry states for the search call.

The system MUST preserve the "no gym" (`kNoGymId`) option, selectable without performing a search.

On selecting a suggestion, the system MUST resolve it (Cloud Function call) and set the user's `gymId` to the returned `place_id`.

(Previously: two-step brand→branch flow backed by the full `gyms/` catalog via `gymsProvider`, with no location involvement at all.)

#### Scenario: Athlete searches and selects a gym

- GIVEN an athlete opens the gym picker during onboarding or profile editing
- WHEN they type a gym name into the search box
- THEN debounced Autocomplete suggestions appear, each showing a name and address
- AND tapping a suggestion resolves it and sets the athlete's `gymId` to the selected Place's `place_id`

#### Scenario: Search works without location permission

- GIVEN an athlete has never granted location permission
- WHEN they type into the gym search box
- THEN suggestions are still returned (unbiased, not location-restricted), with no permission prompt blocking the search

#### Scenario: Search is biased when location is available

- GIVEN an athlete has granted location permission
- WHEN they type into the gym search box
- THEN suggestions are biased toward their current location

#### Scenario: Empty query shows no suggestions

- GIVEN the search box is empty
- WHEN the picker is idle
- THEN no suggestion list is shown and no search call is made

#### Scenario: No results for a query

- GIVEN an athlete types a query that matches no Places
- WHEN the Autocomplete call completes
- THEN an empty-results state is shown, distinct from the loading and error states

#### Scenario: Search call fails and athlete retries

- GIVEN the Autocomplete or resolve call fails (e.g. network error)
- WHEN the picker renders
- THEN an error state with a retry action is shown
- AND tapping retry re-issues the search

#### Scenario: Athlete selects "no gym" without searching

- GIVEN an athlete opens the gym picker
- WHEN they choose the "OTRO GYM / SIN GYM" (`kNoGymId`) option
- THEN their `gymId` is set to `kNoGymId` without any Places search being required

#### Scenario: Onboarding and profile-edit pickers share behavior

- GIVEN the onboarding picker (`step_2_gym.dart`) and the standalone profile picker (`profile_gym_screen.dart`)
- WHEN comparing their search/loading/error/retry/no-gym behavior
- THEN both exhibit the same single-search-box contract described above

## REMOVED Requirements

### Requirement: Curated-only catalog, no athlete self-service creation

(Reason: gym docs are now created on-demand by the Cloud Function on first Places selection — the "no write path for athletes" premise no longer applies. Server-side upsert via Admin SDK is the new creation path, documented under "Gym doc creation is on-demand via a Cloud Function upsert" above.)

### Requirement: Gym catalog is two-level (brand → sucursal)

(Reason: brand/branch grouping is dropped for v1 — each Google Places result already IS a canonical, deduplicated physical location, so there is no multi-branch tree to group. `GymBrand` and its grouping providers are retired.)

### Requirement: Curated Córdoba catalog on a nationwide-capable base

(Reason: the curated seed catalog is no longer the coverage mechanism — Google Places provides nationwide coverage directly. `scripts/seed_gyms.js` becomes dormant/historical, not deleted; existing seeded docs are left untouched as orphans.)

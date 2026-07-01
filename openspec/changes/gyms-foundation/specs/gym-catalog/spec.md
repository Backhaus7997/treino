# Gym Catalog Specification

## Purpose

Establish `gyms/` as the single, curated source of truth for gym data across the app, replacing the legacy hardcoded athlete-facing catalog. Athletes discover and select gyms from this catalog; they cannot self-service add one.

## Requirements

### Requirement: Unified gym model

The system MUST use `lib/features/gyms/domain/gym.dart` (`Gym`, freezed) as the only gym model in the codebase. The system MUST NOT retain `lib/features/profile_setup/domain/gym.dart` or any duplicate gym model.

The system MUST require `lat`, `lng`, and `geohash` on every `Gym` (no relaxation to optional) because only curated, team-seeded gyms exist — every seeded doc has coordinates.

The system MUST require `brandName`, `brandId`, and `branchName` on every `Gym` (see "Gym catalog is two-level" requirement), consistent with curated-only seeding — every seeded doc carries brand/branch grouping from creation.

The system MUST preserve the sentinel `kNoGymId = 'no-gym'` as the "no gym" selection option.

The system MAY include optional `city` and `province` string fields on `Gym` to support future nationwide filtering. These fields, when absent, MUST NOT break deserialization of existing docs.

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
- THEN all three are non-null, because curated seed data always includes coordinates

### Requirement: Curated-only catalog, no athlete self-service creation

The system MUST NOT expose any write/create path for athletes to add a gym to `gyms/`. The system MUST NOT modify `firestore.rules` to grant athletes `create` permission on `gyms/`. Only the existing team-controlled seed process may add gym docs.

#### Scenario: Athlete cannot find a way to add a missing gym

- GIVEN an athlete searches the gym catalog and their gym is not listed
- WHEN they finish searching
- THEN the UI offers no "add new gym" action; the athlete may only pick an existing entry or select "no gym"

#### Scenario: Firestore rules remain unchanged for gym creation

- GIVEN the deployed `firestore.rules` before this change
- WHEN comparing to `firestore.rules` after this change
- THEN the `gyms/{gymId}` `create` rule is unchanged (trainer self-service rule untouched; no new athlete branch added)

### Requirement: Gym catalog is two-level (brand → sucursal)

The system MUST model the catalog as two conceptual levels: brand/chain (marca — e.g. "SportClub") and branch (sucursal — e.g. "Belgrano"). A `Gym` doc (the finest-grained, storable unit) MUST represent a single sucursal and MUST carry `brandName` (display label for the chain) and a stable `brandId` (slug, deterministic from `brandName`, used for grouping) and `branchName` (the branch-specific label, e.g. "Belgrano").

The system MUST treat an independent single-location gym as its own brand with exactly ONE branch (its `brandId` groups to a single `Gym` doc).

The value stored on a user/profile (`gymId`) MUST remain the sucursal doc id — the finest granularity — unchanged from the prior single-level model.

#### Scenario: Chain gym carries brand and branch fields

- GIVEN a `gyms/{gymId}` doc for a branch of a multi-location chain (e.g. SportClub Belgrano)
- WHEN inspecting the doc
- THEN `brandName` ("SportClub"), `brandId` (stable slug), and `branchName` ("Belgrano") are all present and non-null

#### Scenario: Independent gym is a single-branch brand

- GIVEN a `gyms/{gymId}` doc for an independent, single-location gym
- WHEN grouping all `gyms/` docs by `brandId`
- THEN this gym's `brandId` maps to exactly one `Gym` doc (itself)

#### Scenario: gymId still points to the sucursal

- GIVEN an athlete has selected a specific branch of a chain gym
- WHEN their profile's `gymId` is inspected
- THEN it references that exact sucursal's `Gym` doc id, not a brand-level identifier

### Requirement: Athlete gym selection is a two-step brand-then-branch flow

The system MUST load the athlete-facing gym picker (onboarding `step_2_gym.dart` and standalone `profile_gym_screen.dart`) from `gymsProvider` (async, backed by `gyms/`), replacing the synchronous `filteredGymsProvider`.

The system MUST present selection in two steps for multi-branch brands: **Step 1** — the athlete searches/browses distinct brands (grouped by `brandId`) and picks one; each brand entry MUST show its branch count. **Step 2** — the athlete searches/filters branches within the chosen brand (by `branchName` or city) and picks the exact sucursal.

The system MUST skip Step 2 when the chosen brand has exactly one branch (independent gyms): selecting the brand directly resolves and selects that lone sucursal, with no second step shown.

The system MUST expose distinct loading, error, and retry states, mirroring the `_GymsSection` pattern in `profile_edit_trainer_screen.dart` (retry via `ref.invalidate(gymsProvider)`).

The system MUST preserve the "no gym" (`kNoGymId`) option, selectable without entering the brand/branch flow.

The system MUST allow browsing and selecting a gym at both steps without requesting or requiring location permission (full-catalog fetch, no geo query).

#### Scenario: Athlete browses and selects a gym without location permission

- GIVEN an athlete has never granted location permission
- WHEN they open the gym picker during onboarding or profile editing
- THEN the full curated catalog loads and displays without any location permission prompt
- AND the athlete can select a brand, then a branch (or "no gym")

#### Scenario: Athlete picks a chain brand then its branch

- GIVEN the gym catalog has loaded and contains a multi-branch brand (e.g. "SportClub" with 5 branches)
- WHEN the athlete searches and selects "SportClub" in Step 1
- THEN Step 2 shows only SportClub's branches, filterable by branch name or city
- AND selecting a branch sets the athlete's `gymId` to that sucursal's doc id

#### Scenario: Athlete picks an independent single-branch gym without a second step

- GIVEN the gym catalog contains an independent gym that is its own brand with one branch
- WHEN the athlete searches and selects that brand in Step 1
- THEN no Step 2 is shown
- AND the athlete's `gymId` is set directly to that gym's single sucursal doc id

#### Scenario: Athlete searches by brand name

- GIVEN the gym catalog has loaded successfully
- WHEN the athlete types part of a brand name into the Step 1 search field
- THEN only distinct brands whose `brandName` matches the query are shown, each with its branch count

#### Scenario: Catalog fails to load and athlete retries

- GIVEN the gym catalog fetch fails (e.g. network error)
- WHEN the picker renders
- THEN an error state with a retry action is shown instead of an empty or misleading list
- AND tapping retry invalidates `gymsProvider` and re-fetches

#### Scenario: Onboarding and profile-edit pickers share behavior

- GIVEN the onboarding picker (`step_2_gym.dart`) and the standalone profile picker (`profile_gym_screen.dart`)
- WHEN comparing their loading/error/retry/search/two-step behavior
- THEN both exhibit the same async, two-step contract described above (per existing `ADR-PSR-011` shared-widget precedent)

### Requirement: Curated Córdoba catalog on a nationwide-capable base

The system MUST seed Córdoba Capital's main gyms into `gyms/` via `scripts/seed_gyms.js`, in addition to the existing Buenos Aires (CABA/GBA) gyms already seeded — neither set is dropped. Seeded chain gyms with multiple Córdoba/BA locations MUST share the same `brandId`; seeded independent gyms MUST each be their own single-branch brand.

The system MUST NOT hard-limit the gym model, picker, or search to Córdoba geographically; the catalog is nationwide-capable by design even though Córdoba is the initial curation focus.

Each seeded gym MUST include `name`, `brandName`, `brandId`, `branchName`, `lat`, `lng`, `geohash`, `source: 'seed'`, and MAY include `city`/`province`.

#### Scenario: Seed includes both Córdoba and existing Buenos Aires gyms

- GIVEN `scripts/seed_gyms.js` has been run
- WHEN querying all docs in `gyms/`
- THEN the result includes the curated Córdoba Capital gyms AND the pre-existing Buenos Aires (CABA/GBA) gyms

#### Scenario: Picker is not geographically restricted

- GIVEN the seeded catalog contains gyms from multiple provinces
- WHEN an athlete outside Córdoba opens the gym picker
- THEN gyms from all seeded cities/provinces are browsable and selectable, not just Córdoba

#### Scenario: Seeded chain branches share a brandId

- GIVEN `scripts/seed_gyms.js` seeds a chain with branches in both Córdoba and Buenos Aires
- WHEN querying all `gyms/` docs for that chain
- THEN every branch doc shares the same `brandId` and each has a distinct `branchName`

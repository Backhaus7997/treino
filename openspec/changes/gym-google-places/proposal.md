# Proposal: gym-google-places

Replace the curated gym catalog + two-step (brand -> sucursal) picker with a Google Places (New) Autocomplete search that stores each gym under its Google `place_id`.

## Why

The gym catalog just merged (gyms-foundation Slices 1-4) was seeded with **placeholder curated data** (22 hand-picked Cordoba + Buenos Aires gyms in `scripts/seed_gyms.js`). That approach has two structural problems:

1. **No coverage.** A gym absent from the 22 seeded docs simply has no id — a user can't select it, and there's no id space for it to ever get one without manual seeding.
2. **No canonical identity.** Curated ids (`smart-fit-palermo`, ...) are ours to invent; two records that mean "the same physical gym" have no guaranteed shared key.

Google's Place `id` solves both: it's Google's own canonical, **deduplicated** identifier for a physical place. Multiple users searching for "the same gym" independently resolve to the identical id — Google does the entity-resolution. This is the cleanest possible key for the future **"rankings by gym"** feature. (We do NOT design the ranking here — this change only lays the identity foundation.)

Two facts make this change notable beyond a picker swap:
- The app renders maps with **flutter_map (OpenStreetMap)**, not the Google Maps SDK. Places is a **NEW Google API dependency** — but it's a plain HTTP API for text Autocomplete, so no map-renderer migration is needed.
- This is the **FIRST external paid-API call from `functions/`**. It establishes the Secret Manager pattern for this codebase (no `.env` or existing secret convention exists today).

## What Changes

### 1. Cloud Function (server-side Places proxy + gym upsert)

- New Cloud Function file (e.g. `functions/src/places-search.ts`) following the **locked `add-alias.ts` pattern**: pure handler(s) + thin `onCall` wrapper(s), `getApp()` lazy Admin init, region `southamerica-east1`, `HttpsError` guards (`unauthenticated` -> input validation), re-export by name from `functions/src/index.ts`.
- Handles **Place Details** + **upsert of `gyms/{place_id}`**. Key is read from **Secret Manager** via `onCall({ secrets: ['PLACES_API_KEY'], region: 'southamerica-east1' }, ...)`.
- **Read-through cache**: the Function `get()`s `gyms/{place_id}` first; if the doc already exists, it returns it and **skips the Place Details call** (no extra Places billing). If absent, it calls Place Details with an `X-Goog-FieldMask` requesting only `id`, `displayName`, `formattedAddress`, `location`, `types`, then upserts the doc via Admin SDK (which bypasses Firestore rules — no rules change needed for the write).
- New Jest tests mirroring `add-alias.test.ts` conventions, with the Places HTTP call mocked.

### 2. Places client (Flutter, Autocomplete)

- **Autocomplete runs client-side** with a **bundle-id-restricted** API key, using **session tokens** (one token spans the full keystroke sequence + the single Place Details call the selection triggers — flat per-session pricing instead of per-keystroke).
- **Location bias** via the user's `geolocator` position (reuse the permission flow from `trainer_advanced_filter_chips.dart`), with a graceful **no-location fallback**: if permission is denied/unavailable, call Autocomplete unbiased rather than erroring.
- On selection, the client calls the Cloud Function (Place Details + upsert) and writes the resulting `place_id` as `gymId`.

### 3. Picker rework (single debounced search box)

- Replace the two-step brand/branch UI in `step_2_gym.dart` (onboarding) and `profile_gym_screen.dart` (profile edit) with a **single debounced search-as-you-type list** (results = Autocomplete predictions).
- **Reuse unchanged**: `GymCard` (name + address subtitle still fits), the `kNoGymId` sentinel + "OTRO GYM / SIN GYM" option, and the loading / `_ErrorRetry` + location-permission patterns.

### 4. Model + enum

- **Reuse the existing `Gym` model** (all needed fields are already nullable). Add `GymSource.googlePlaces` to `gym_source.dart`, mirroring the existing `seed` / `selfService` pattern so provenance stays queryable.
- Field mapping from Places: `id` <- `place_id`, `name` <- `displayName`, `address` <- `formattedAddress`, `lat`/`lng` <- `location`. `brandId` / `brandName` / `branchName` are left **null** (brand grouping is DROPPED for v1). `geohash` can be derived server-side via the existing `lib/core/utils/geohash.dart` port used in `seed_gyms.js`.
- **Soft gym-type check**: bias by Places `types`, do NOT hard-reject a selection.

### 5. Retirements

Retire the now-dead two-step machinery:
- Domain: `GymBrand` model (+ its freezed/test files).
- Providers: `gymBrandsProvider`, `branchesForBrandProvider`.
- Widgets: the two-step `_BrandList` / `_BranchList` (and view) classes, the "VOLVER A MARCAS" back-nav.
- Tests: `gym_picker_parity_test.dart` (parity for a two-step shape that no longer exists).

**No migration of existing data** (locked): leave stale curated `gymId`s as-is — `_resolveGymName` already degrades gracefully to `null`. The 22 orphaned curated `gyms/` docs stay untouched. `scripts/seed_gyms.js` + the backfill scripts become dormant/historical (NOT deleted in this change).

**Reuse unchanged** (locked, provenance-agnostic): `Gym` model, `GymRepository.getById/getByIds`, `gymByIdProvider`, the gym display-name helpers, and `UserRepository`'s dual-write of `gymName`. They don't care about doc provenance, so `gymName` denormalization keeps working with `place_id`-keyed docs.

## Impact

### Prerequisite (external, user's action — BLOCKS end-to-end testing)

GCP setup on the project backing `treino-dev`:
1. Enable **Places API (New)** (distinct from legacy "Places API").
2. Confirm **Blaze billing** is active on the Firebase project (near-certain given Functions + Firestore already run).
3. Create a **server-only key** in **Secret Manager**: `firebase functions:secrets:set PLACES_API_KEY`.
4. Create a **bundle-id-restricted client key** for Autocomplete (separate from the server key).
5. Set a **Cloud Billing budget alert** (Places is metered per-call; guards against a debounce bug).
6. **Provide the `treino-dev` GCP project id / number** — not found in scanned files; needed to enable the API + billing.

### Files touched

- **New**: `functions/src/places-search.ts` (+ Jest test), Flutter Places-search provider(s) + Autocomplete client.
- **Modified**: `functions/src/index.ts` (re-export), `lib/features/gyms/domain/gym_source.dart` (enum case + mapping), `step_2_gym.dart`, `profile_gym_screen.dart`, `firestore.rules` (document the new `source` value in a comment — no logic change since Admin SDK bypasses rules).
- **Retired**: `GymBrand` (+ freezed/test), `gymBrandsProvider`, `branchesForBrandProvider`, `_BrandList`/`_BranchList` widgets, `gym_picker_parity_test.dart`.
- **Dormant (not deleted)**: `scripts/seed_gyms.js` + backfill scripts; 22 curated `gyms/` docs.

### Cost

- Session tokens make Autocomplete flat-per-session, not per-keystroke.
- The read-through cache skips Place Details billing whenever `gyms/{place_id}` already exists.
- Field-masking requests only the 5 fields we need, minimizing the New API's per-field-group SKU cost.
- Low-QPS feature (gym selection is infrequent). Budget alert is the runaway-cost safety net.

### Security of the key

- **Server key** never ships to the client — lives only in Secret Manager, referenced via `onCall({ secrets: [...] })`. Used for Place Details + upsert.
- **Client key** is bundle-id-restricted and scoped to Places API (New) Autocomplete only. Even if extracted from the binary, its blast radius is limited to Autocomplete calls under our billing (mitigated by the budget alert).
- This split establishes the Secret Manager convention for the whole `functions/` codebase.

### Risks

- **Places API (New) REST contract churn.** Field names (`id` vs `place_id`, `displayName`, `location`) have changed historically — verify against current Google docs during sdd-design, do NOT assume from training data.
- **First external paid-API call from `functions/`** — no in-repo precedent for the HTTP client wrapper or Secret Manager wiring. This change sets the pattern.
- **GCP prerequisite is external** — blocks end-to-end testing until the user completes it (and provides the project id).
- **Two keys to manage** (server + client) — see open decision below; the alternative is proxying Autocomplete through the Function too.

## Open Decisions (flag for product owner)

1. **Autocomplete call path.** LOCKED here as client-side (bundle-restricted key + session tokens) with Details/upsert through the Function. The exploration's alternative was proxy-everything (one key, simpler security story, per-keystroke Function cost). If the team prefers a single-key story over client-side speed, revisit before sdd-design.
2. **Gym sanity-check strictness.** LOCKED as soft bias by `types`. Confirm the product owner accepts that a user *can* select a non-gym Place (e.g. a coffee shop) without a hard block.
3. **Migration volume.** LOCKED as "leave stale ids until re-pick." Confirm the number of athletes who already picked a seed-catalog gym is low enough that no backfill is warranted.
4. **GCP project identity.** The exact `treino-dev` GCP project id / number must be provided by the user (external prerequisite above).

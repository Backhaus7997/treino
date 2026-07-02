# Design: gym-google-places

## Technical Approach

Split-trust Places integration mirroring the existing `add-alias.ts` pure-handler + thin-`onCall` pattern. **Autocomplete runs client-side** (Dart data-layer service, bundle-restricted key, session tokens, geolocator location bias). **Place Details + `gyms/{place_id}` upsert run server-side** in a new callable `resolveGymPlace` (server key in Secret Manager, region `southamerica-east1`, Admin SDK upsert = read-through cache). The picker becomes a single debounced search box; `Gym` gains `GymSource.googlePlaces`; the two-step brand/branch machinery is retired. No data migration. See proposal (`#346`) and exploration (`#345`).

> **Places API (New) field-name churn — VERIFY AT APPLY TIME.** Every endpoint URL, JSON field, and field-mask token below is stated explicitly but MUST be re-checked against current Google Places API (New) docs during `sdd-apply`. Do NOT treat these as authoritative from training data.

## Architecture Decisions

| Decision | Choice | Rejected | Rationale |
|---|---|---|---|
| Autocomplete location | Client-side Dart service | Proxy-everything through CF | LOCKED. Session-token flat pricing + no per-keystroke CF cost; key is bundle-restricted. |
| Details + upsert location | Server CF `resolveGymPlace` | Client-side Details | Server key never ships; Admin SDK bypasses Firestore `create` rule (athletes can trigger gym-doc creation). |
| Cache | Read-through: CF `get()`s `gyms/{id}`, skips Details on hit | Always call Details | Zero Places billing on repeat selections. |
| Model | Reuse `Gym` + add `GymSource.googlePlaces` | New doc type | All needed fields already nullable; every read path is `Gym`-shaped. |
| Brand grouping | Dropped for v1 (`brandId/brandName/branchName` = null) | Heuristic brand deriver | Each Places result IS one canonical branch; no tree to climb. |
| geohash | Computed server-side in CF (port `geohash5` from `seed_gyms.js`) | Client-computed | Keeps upsert self-contained; Node CF already has no HTTP-client precedent, geohash is pure. |
| HTTP client | Node 20 global `fetch` | Add axios/node-fetch dep | No new dep; `functions/` currently has zero external-API precedent — establish minimal. |
| Firestore rules | NO logic change (comment only) | Add athlete-create rule | Admin SDK bypasses rules; athletes only READ `gyms/`. |

## Data Flow

    [Flutter picker] --debounced query--> PlacesAutocompleteService
         |  (client key + session token + optional locationBias from geolocator)
         v
    Places Autocomplete (New) REST  -->  suggestions [{placeId, primaryText, secondaryText}]
         |  user taps a suggestion
         v
    selectGymActionProvider --> resolveGymPlace CF (onCall, sa-east1, secret PLACES_API_KEY)
         |                              |
         |                    get gyms/{place_id}? --HIT--> return existing (no Places call)
         |                              |--MISS--> Place Details (New) --> map+geohash --> upsert
         v
    UserRepository.update(uid, {gymId: place_id})  (dual-writes gymName via _resolveGymName)

## File Changes

| File | Action | Description |
|---|---|---|
| `functions/src/places-search.ts` | Create | `runResolveGymPlace(app, placeId, sessionToken?)` pure handler + `resolveGymPlace` thin `onCall`. |
| `functions/src/__tests__/places-search.test.ts` | Create | Handler unit test: mock `fetch`, `fake`/emulator upsert, read-through hit/miss, bad place_id, Places error. |
| `functions/src/index.ts` | Modify | Add `export { resolveGymPlace } from "./places-search";`. |
| `lib/features/gyms/data/places_autocomplete_service.dart` | Create | Dart service: Autocomplete (New) REST via `http`, client key + session token + optional bias. |
| `lib/features/gyms/data/resolve_gym_place_service.dart` | Create | Thin `httpsCallable('resolveGymPlace')` wrapper (mirror `account_deletion_service.dart`). |
| `lib/features/gyms/application/places_providers.dart` | Create | Debounced `placesSuggestionsProvider(query)` + `selectGymActionProvider`. |
| `lib/features/gyms/domain/gym_source.dart` | Modify | Add `googlePlaces` enum + `'google-places'` wire mapping. |
| `lib/features/gyms/domain/gym_suggestion.dart` | Create | Plain value class `{placeId, primaryText, secondaryText}` (NOT freezed — simple DTO). |
| `lib/features/profile_setup/presentation/steps/step_2_gym.dart` | Modify | Replace two-step with single search box + suggestion list + `kNoGymId`. |
| `lib/features/profile/presentation/profile_gym_screen.dart` | Modify | Same rework; keep save bar + `UserRepository.update`. |
| `lib/features/gyms/domain/gym_brand.dart` | Delete | Grouping model retired. |
| `lib/features/gyms/application/gym_providers.dart` | Modify | Remove `gymBrandsProvider`, `branchesForBrandProvider`, `gymBrandSearchQueryProvider`; keep repo/`gymByIdProvider`. |
| `test/features/gyms/domain/gym_brand_test.dart` | Delete | Model deleted. |
| `test/features/profile_setup/presentation/gym_picker_parity_test.dart` | Delete | Two-step shape gone; replaced by new search-box widget test. |
| `firestore.rules` | Modify | Comment only: document `source: 'google-places'`; note Admin-SDK upsert bypasses the trainer-only `create` rule. |
| `lib/firebase_config` / build env | Modify | Add bundle-restricted client key via `--dart-define` (NOT committed). |

## Interfaces / Contracts

**CF callable** `resolveGymPlace` (sa-east1, `secrets: ['PLACES_API_KEY']`):
- Input: `{ placeId: string, sessionToken?: string }`. Guards: `unauthenticated` if no auth; `invalid-argument` if `placeId` empty.
- Place Details (New): `GET https://places.googleapis.com/v1/places/{placeId}` with headers `X-Goog-Api-Key: <secret>`, `X-Goog-FieldMask: id,displayName,formattedAddress,location,types` *(VERIFY tokens: `displayName.text`, `location.latitude/longitude`)*.
- Read-through: `db.collection('gyms').doc(placeId).get()` → hit returns existing doc (skip Details).
- Upsert (Admin SDK) maps: `id←id`, `name←displayName.text`, `address←formattedAddress`, `lat←location.latitude`, `lng←location.longitude`, `geohash←geohash5(lat,lng)`, `source:'google-places'`, `createdAt` server ts; `brandId/brandName/branchName:null`. Soft type check: log a warning if `types` lacks `gym`/`health`; never reject.
- Returns: `{ gymId, name, address, source }`. Errors: bad `placeId`→`not-found`; Places non-200→`internal` (never leak key); quota/429→`resource-exhausted`.

**Autocomplete (New)**: `POST https://places.googleapis.com/v1/places:autocomplete`, body `{ input, sessionToken, locationBias?: {circle:{center:{latitude,longitude}, radius}} }`, `X-Goog-FieldMask: suggestions.placePrediction.(placeId,text,structuredFormat)` *(VERIFY field/mask names)*. No-permission fallback: omit `locationBias`.

**Providers**: `placesSuggestionsProvider = FutureProvider.autoDispose.family<List<GymSuggestion>, String>` fed by a debounced (300 ms) query `StateProvider`; empty query → `[]`. `selectGymActionProvider` calls `resolveGymPlace` then `UserRepository.update`; exposes loading/error.

## Testing Strategy (Strict TDD)

| Layer | What | Approach |
|---|---|---|
| CF unit | `runResolveGymPlace`: read-through hit (no fetch), miss→Details→upsert, bad placeId→not-found, Places error→internal | Emulator app (as `add-alias.test.ts`) + `jest.spyOn(global,'fetch')` mock. |
| CF wrapper | `unauthenticated` / `invalid-argument` guards, exported + region | `firebase-functions-test` `fft.wrap`, index re-export assert. |
| Dart service | Autocomplete request shape (bias present/absent) + response parse | inject mock `http.Client`. |
| Dart action | `selectGymActionProvider` calls CF then `UserRepository.update({gymId})` | override CF service + fake firestore. |
| Widget | search box: type→debounced suggestions, tap→select, `kNoGymId`, loading/error/empty, works w/o location | `ProviderScope.overrides` + pump. |

## Migration / Rollout

No data migration. Stale curated `gymId`s resolve to `null` via `_resolveGymName` (graceful). 22 seed docs + `seed_gyms.js` stay dormant. **External prerequisite (BLOCKS e2e):** enable Places API (New), Blaze billing, `firebase functions:secrets:set PLACES_API_KEY`, bundle-restricted client key, budget alert, and provide the `treino-dev` GCP project id.

## Chained-PR Slices (each ≤~400 LOC, tests with code)

1. **CF + secret** — `places-search.ts` + test + `index.ts` re-export + `firestore.rules` comment. Autonomous, deployable, testable via emulator.
2. **Client Autocomplete + resolve services + providers** — `places_autocomplete_service.dart`, `resolve_gym_place_service.dart`, `places_providers.dart`, `gym_suggestion.dart`, `GymSource.googlePlaces` + build_runner. Unit-testable, no UI yet.
3. **Picker rework + retirements** — rewrite both screens to single search box; delete `GymBrand` + 3 providers + 2 tests; new widget test. Depends on #2.

## Open Questions

- [ ] Places API (New) exact field/mask tokens (`displayName.text`, `location.latitude`, `suggestions.placePrediction.*`) — VERIFY at apply time.
- [ ] `treino-dev` GCP project id/number (external, user-provided).
- [ ] Debounce = 300 ms and location-bias radius default (propose 30 km) — confirm during apply.

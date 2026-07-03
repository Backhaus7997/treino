# Proposal: gym-selection-v2 — nearby-gyms list + gym-selection screen redesign

## Why

Two user-reported problems on the gym-selection flow, one with a verified root cause:

1. **Real gyms never appear in search.** The user's own gym (QIVOX Villa Warcalde) does not surface when searching, even with the location bias centered on it. **Root cause (verified empirically via curl against `places:autocomplete` with the client key):** Places Autocomplete (New) returns a HARD MAX of 5 suggestions and ranks them by *prominence* (popularity/reviews), NOT distance. The gym exists in Google Places and passes the `includedPrimaryTypes: ['gym']` filter — the filter is not the problem. With a 30km bias circle centered exactly on Villa Warcalde, plain "qivox" still returns the same 5 more-prominent branches (Vélez / Colectora / Rondeau / Colón / Ambrosio); the user's branch never cracks the top 5. This affects ANY chain with >5 branches and any low-review neighborhood gym competing with similar names. The bias circle influences but does NOT override prominence ranking — `searchNearby` is the distance-ranked tool that fixes this.

2. **No indication of the current gym.** Once enrolled, tapping the gym row in Profile goes straight to the search screen with zero indication of which gym is currently selected. `ProfileGymScreen` watches `currentGymId` but never surfaces it visually — the body is `GymSearchBox` only. Confirmed in code shape.

The fix converges both problems: add a distance-ranked "nearby gyms" list via `places:searchNearby` (New) — up to 20 results, `rankPreference: DISTANCE`, `includedTypes: ['gym']` — reusing the location-permission patterns that already exist for coach discovery. Autocomplete stays for manual text search. Redesign the screen so the current gym is pinned and marked at the top.

## What Changes

### 1. New `PlacesNearbySearchService` (client-side REST)
Mirror the existing `PlacesAutocompleteService` raw-REST pattern (org blocks Cloud Functions; client key with App restriction = None per the gym-google-places bundle-key gotcha). `POST https://places.googleapis.com/v1/places:searchNearby` with body `{ includedTypes: ['gym'], maxResultCount, rankPreference: 'DISTANCE', locationRestriction: { circle: { center, radius } } }`. Headers: `X-Goog-Api-Key` + **`X-Goog-FieldMask` (REQUIRED — no default; the call errors if omitted)**. Constructor-injected `http.Client` for test-doubling from day one. Parses into the existing `GymSuggestion` DTO (`places[].id` is the same Place ID namespace as Autocomplete's `placePrediction.placeId`).

### 2. New nearby provider with mandatory cost gating
A new provider in `places_providers.dart` that fires `searchNearby` **at most once per screen-open (never per rebuild)** plus caching. **Cost gating is a hard requirement, not an optimization:** `searchNearby` bills as "Places API Nearby Search Pro" (~$32/1000 requests at volume tier) with NO free session model — categorically more expensive than Autocomplete (New) sessions, which are free/Essentials tier, and billed regardless of how minimal the field mask is. The provider must resolve location first (reusing an existing location pattern); `locationRestriction.circle` is REQUIRED, so no-location is a distinct graceful-degradation path (hide the section or show a location CTA), unlike Autocomplete's null-safe bias. Zero matches returns an empty `places` array (not an error) → hide the section.

### 3. `ProfileGymScreen` / `GymSearchBox` restructure to a 4-part composition
Approach (a) from exploration, single screen, top→bottom:
- **Pinned current-gym card** at the top, visually marked/bordered. Reuses `gymByIdProvider(currentGymId)` + `gymDisplayNameFromGym` — the exact 5-line pattern already used in `profile_cuenta_section.dart`. Zero new plumbing.
- **Nearby-gyms list** when the query is empty (default state, `searchNearby` DISTANCE-ranked, gated behind available location), replaced by **Autocomplete search results** when the user types. `GymSearchBox` needs a "default content when query empty" slot (today it renders `SizedBox.shrink()`).
- **"No tengo gimnasio"** option kept pinned at the bottom.

### 4. Nearby-tap feeds the existing selection path (drop-in)
A nearby-list tap calls the same `selectGymActionProvider.select(uid, placeId)` used by Autocomplete taps — no new action. `ResolveGymPlaceService.call(placeId, sessionToken?)` treats `sessionToken` as optional (`String?`, omitted from the Details GET when null); a searchNearby-originated placeId with no Autocomplete session token resolves fine. The read-through cache on `gyms/{placeId}` means already-resolved gyms cost nothing. The write path already replaces `gymId` on change (dual-writes `gymName`) — this is a UI-only concern.

## Scope

### In Scope
- New `PlacesNearbySearchService` (client-side raw REST, injected `http.Client`, required field mask).
- New nearby provider with call-gating + caching (fire once per screen-open).
- `ProfileGymScreen` / `GymSearchBox` restructure to the 4-part composition.
- Pinned current-gym card reusing `gymByIdProvider` + `gymDisplayNameFromGym`.
- Client-side "X km" distance labels via `haversineKm()` (searchNearby has no distance field, only distance-sorted order).

### Out of Scope
- **Changing Autocomplete behavior** — it stays exactly as-is for text search (the 5-cap is worked around, not fixed).
- **Any server-side work** — no Cloud Functions, no new collection, no new query/index. Org blocks Cloud Functions; all Places work is client-side raw REST.
- **The resolve / write path** — `ResolveGymPlaceService`, `GymRepository`, `SelectGymAction`, and the `gymId`/`gymName` dual-write are untouched and compatible as-is.
- **Gym detail pages / gym metadata** — no gym profile, hours, photos, or map screens.
- Onboarding-only flows beyond the shared `GymSearchBox` slot change.

## Capabilities

### New Capabilities
- `gym-nearby-search`: distance-ranked nearby-gyms list via Places `searchNearby` (New), client-side, cost-gated, feeding the existing selection path.

### Modified Capabilities
- `gym-selection`: `ProfileGymScreen` restructured to a 4-part composition (pinned current gym → nearby/search body → "no tengo gimnasio"); `GymSearchBox` gains a default-content slot.

## Approach

Compose entirely on the existing base — no changes to resolution, write path, indexes, or Autocomplete. Fix problem 1 by *adding* a distance-ranked source (`searchNearby`) rather than fighting Autocomplete's prominence ranking. Fix problem 2 by surfacing the already-available `currentGymId` through the existing `gymByIdProvider` + display-name helper. Reuse an existing location pattern for permission handling, and make cost gating structural (fire-once-per-open + cache) since `searchNearby` has no free tier.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/gyms/data/places_nearby_search_service.dart` | New | Client-side raw-REST `searchNearby`; required `X-Goog-FieldMask`; injected `http.Client` |
| `lib/features/gyms/application/places_providers.dart` | Modified | New nearby provider with call-gating + caching; location resolution |
| `lib/features/profile/presentation/profile_gym_screen.dart` | Modified | Restructure to 4-part composition; pinned current-gym card |
| `lib/features/profile_setup/presentation/widgets/gym_search_box.dart` | Modified | Add default-content slot (nearby list when query empty) |
| `lib/features/gyms/domain/gym_suggestion.dart` | Verify | Reuse DTO as-is for nearby results |
| `lib/features/gyms/data/places_autocomplete_service.dart` | Reference | REST pattern to mirror; behavior unchanged |
| `lib/features/gyms/application/gym_providers.dart` / `lib/features/gyms/domain/gym_display_name.dart` | Reuse | `gymByIdProvider` + `gymDisplayNameFromGym` for the pinned card |
| `lib/features/gyms/data/resolve_gym_place_service.dart` / `gym_repository.dart` | Untouched | Resolution + write path compatible as-is |
| `lib/features/coach/application/trainer_discovery_providers.dart` + `location_permission_rationale_sheet.dart` | Reference | Location-prompt pattern candidate |
| `lib/core/utils/haversine.dart` | Reuse | `haversineKm()` for "X km" labels |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `searchNearby` cost balloons (fires per rebuild / per visit) | High impact | Structural gate: fire once per screen-open + cache; provider owns the guard, not the widget. HARD requirement (see What Changes §2) |
| `Geolocator.checkPermission()` hangs forever under `testWidgets` (confirmed gotcha, `gym_search_box_test.dart:279-287`) | High | New nearby provider MUST be test-double-friendly from day one — injected `http.Client`, provider override points; tests never hit the platform channel |
| Missing/denied location → `searchNearby` cannot be called (`locationRestriction` mandatory) | Med | Distinct graceful-degradation path: hide the nearby section or show a location CTA; Autocomplete search still fully works |
| Field mask omitted or wrong → API error (no default mask) | Med | Field mask is REQUIRED and explicit in the service; covered by service tests |
| Current gym duplicated in the nearby list | Low | Dedup decision carried to spec/design (Open Question 5) |

## Rollback Plan
Additive and reversible. Remove the nearby provider + service, drop the default-content slot back to `SizedBox.shrink()`, and collapse `ProfileGymScreen` back to the search-only body. No data migration, no schema change, no index change, no write-path change. Autocomplete and resolution are untouched throughout.

## Dependencies
- Existing client-side Places raw-REST pattern + bundle-key gotcha (client key App restriction = None).
- Existing selection/resolution path: `selectGymActionProvider` → `ResolveGymPlaceService` (optional `sessionToken`) → `gyms/{placeId}` read-through cache → `gymId`/`gymName` dual-write.
- `gymByIdProvider` + `gymDisplayNameFromGym` for the pinned card.
- An existing location pattern (`gymSearchLocationBiasProvider` silent-check vs `athleteLocationProvider` rationale-sheet prompt) — which one is Open Question 1.
- `haversineKm()` for distance labels.

## Success Criteria
- [ ] The user's own gym (QIVOX Villa Warcalde) is reachable — appears in the nearby list when location is available, without depending on Autocomplete prominence.
- [ ] The current gym is pinned and visually marked at the top of the selection screen.
- [ ] `searchNearby` fires at most once per screen-open (verifiable in tests via a call-counting fake), never per rebuild.
- [ ] Tapping a nearby gym selects it through the existing `select(uid, placeId)` path and replaces the previous gym.
- [ ] Autocomplete text search, resolution, and the write path behave exactly as before.
- [ ] `flutter analyze` 0 issues, `dart format .`, `flutter test` pass.

## Open Questions (for spec / design)
1. **Location pattern on this screen** — silent `checkPermission()`-only (reuse `gymSearchLocationBiasProvider` style, hide section when not granted) vs an explicit rationale-sheet prompt (reuse `athleteLocationProvider` / `location_permission_rationale_sheet.dart`). *Lean: silent check first; if not granted, show an inline "Activar ubicación para ver gyms cercanos" affordance that reuses the rationale-sheet pattern — no blind OS prompt.*
2. **Caching strategy** — fire-once-per-open only, geohash-bucket + TTL cache, or both. *Lean: fire-once-per-open is the mandatory floor; add geohash-bucket + TTL if the same location repeats across opens (both, layered).*
3. **Radius** — fixed 5km vs expanding retry (e.g. 5km → 15km when <3 results). *Lean: start fixed ~5km ("nearby" should be tight; 30km is too wide for this list); revisit expanding retry only if empty results are common in testing.*
4. **Nearby list cap** — 20 (searchNearby max) vs 5–8 with a "ver más" affordance. *Lean: cap the visible list to 5–8 for scannability; `maxResultCount` can still request more for dedup headroom — exact number a design call.*
5. **Dedup of current gym** — suppress the pinned current gym from the nearby list, or allow it to appear in both. *Lean: suppress from the nearby list (it is already pinned at top).*
6. **Field mask `places.location`** — include it (enables client-side haversine "X km" labels). *Lean: yes — same Essentials tier, free, and required for distance labels; there is no per-result distance field otherwise.*

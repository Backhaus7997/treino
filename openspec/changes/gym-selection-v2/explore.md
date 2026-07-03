# Exploration — gym-selection-v2

Scope: (1) nearby-gyms list via Places `searchNearby` (fixes chain-branch invisibility: Autocomplete hard-caps 5 results ranked by prominence — verified empirically with QIVOX Villa Warcalde), (2) gym-selection screen redesign (pinned current gym, nearby, search, no-gym).

Infra constraint: org blocks Cloud Functions — all Places work client-side raw REST (client key with App restriction = None).

---

## Current flow map

- Screen: `lib/features/profile/presentation/profile_gym_screen.dart` — watches `userProfileProvider` → `currentGymId` (line 87); `_pendingGymId` never surfaced visually (only `saveEnabled`). Body = `GymSearchBox` only. **No "current gym" section exists — confirms the UX bug.**
- `_save()` (line 39): gym → `selectGymActionProvider.select(uid, placeId)`; no-gym → `userRepository.update(uid, {'gymId': kNoGymId})`. **Write path already replaces — UI-only concern.**
- Current gym renders ONLY in `profile_cuenta_section.dart:36-49` via `gymByIdProvider` + `gymDisplayNameFromGym` — the exact 5-line pattern to reuse for the pinned card. Zero new plumbing.
- Location bias today: `gymSearchLocationBiasProvider` (`places_providers.dart:84-96`) — silent `checkPermission()` only, NEVER prompts, null on denied/error. 30km bias for Autocomplete.
- Session token: `gymSearchSessionTokenProvider`, invalidated on select. Autocomplete-only concept.
- Selection→resolution: `SelectGymAction.select()` → `ResolveGymPlaceService.call(placeId, sessionToken?)` — read-through cache on `gyms/{placeId}`, Details GET on miss, upsert, then `userRepository.update` (dual-writes gymName).

## searchNearby (New) mechanics + cost

- `POST https://places.googleapis.com/v1/places:searchNearby` — body: `includedTypes:["gym"]`, `maxResultCount` (1-20), `rankPreference:"DISTANCE"`, `locationRestriction.circle` (center+radius ≤50km, **REQUIRED** — hard filter, not a bias). Headers: `X-Goog-Api-Key` + **`X-Goog-FieldMask` (REQUIRED, no default)**.
- Minimal field mask: `places.id,places.displayName,places.formattedAddress` (+ `places.location` same Essentials tier, free — enables client-side haversine "X km" labels; recommend including).
- **COST FLAG (loudest risk)**: bills as **Nearby Search Pro** — NO free session model (Autocomplete sessions are free/Essentials). ~$32/1000 requests at volume tier. MUST be call-gated (fire once per screen-open, cache per geohash-bucket/TTL) — never per rebuild.
- No location → endpoint cannot be called at all (locationRestriction mandatory) → distinct graceful-degradation path (hide section / CTA), unlike Autocomplete's null-safe bias.
- Zero matches → empty `places` array (not an error) → hide section.
- Radius: 30km (Autocomplete bias) is too wide for a "nearby" list — recommend ~5km.

## Location reuse + test gotcha

Two existing patterns:
1. `gymSearchLocationBiasProvider` — silent check, never prompts (gym search today).
2. `athleteLocationProvider` (`trainer_discovery_providers.dart:95-149`) — explicit `requestPermission()` gated behind `location_permission_rationale_sheet.dart` (coach discovery, design D8). The "real" prompting flow.

**CONFIRMED GOTCHA**: `Geolocator.checkPermission()` hangs forever under `testWidgets` (comment at `gym_search_box_test.dart:279-287`). Every widget test overrides the location provider — any new nearby provider MUST be test-double-friendly from day one (constructor-injected `http.Client`, provider override points).

## Resolution path compatibility — drop-in ✅

`places[].id` (searchNearby) = same Place ID namespace as Autocomplete's `placePrediction.placeId`. Nearby tap → same `select(uid, placeId)` — no new action needed. `ResolveGymPlaceService.sessionToken` is optional (`String?`, omitted from the Details GET when null) — nothing assumes Autocomplete origin. Read-through cache means already-resolved gyms cost nothing. Only NEW code: fetch service + provider (+ DTO — `GymSuggestion` likely reusable as-is).

## Approaches

- **(a) One screen, 3 sections** — pinned current-gym card; below it, nearby list when query empty / search results when typing; no-gym pinned at bottom. Matches requested composition; `GymSearchBox` needs a "default content when query empty" slot (today: `SizedBox.shrink()` at `gym_search_box.dart:122`). Effort: Medium. **[RECOMMENDED]**
- (b) Unified list (nearby = default data source, search replaces on typing) — structural variant of (a), same outcome.
- (c) Separate nearby tab/screen — isolates cost behind explicit tap, but contradicts single-screen composition. Medium-High.

Recommendation: **(a)** + cost gating: nearby fires once per screen-open (not per rebuild); silent location check first; if not granted, inline "Activar ubicación para ver gyms cercanos" affordance reusing the rationale-sheet pattern — no blind OS prompt.

## Relevant files

- `lib/features/profile/presentation/profile_gym_screen.dart` — screen to restructure
- `lib/features/gyms/application/places_providers.dart` — new nearby service/provider live here
- `lib/features/gyms/data/places_autocomplete_service.dart` — REST pattern to mirror (`PlacesNearbySearchService`)
- `lib/features/gyms/data/resolve_gym_place_service.dart`, `gym_repository.dart` — compatible as-is
- `lib/features/gyms/application/gym_providers.dart:18-22` (`gymByIdProvider`), `lib/features/gyms/domain/gym_display_name.dart:24` — reuse for pinned card
- `lib/features/gyms/domain/gym_suggestion.dart` — DTO likely reusable
- `lib/features/profile_setup/presentation/widgets/gym_search_box.dart` — needs default-content slot
- `lib/features/coach/application/trainer_discovery_providers.dart:95-149` + `location_permission_rationale_sheet.dart` — prompting pattern candidates
- `lib/core/utils/haversine.dart` — distance labels
- `test/features/profile_setup/presentation/gym_search_box_test.dart:264-305`, `test/features/coach/application/trainer_discovery_providers_test.dart` — test-double patterns

## Open decisions for propose

1. Location pattern for nearby: silent-check-only vs explicit rationale-sheet prompt on this screen.
2. Cost-control caching: fire-once-per-open, geohash-bucket TTL cache, or both.
3. Radius: fixed 5km vs expanding retry (5→15km if <3 results).
4. Nearby section cap: 20 vs 5-8 with "ver más".
5. Dedup: pinned current gym suppressed from nearby list or duplicated.
6. Field mask: include `places.location` for "X km" labels (free, same tier — recommended).

Engram: `sdd/gym-selection-v2/explore`.

# Design: gym-selection-v2 — nearby-gyms list + gym-selection screen redesign

## Technical Approach

Purely additive composition on the existing Places base. Two problems, one converging fix:

1. **Chain-branch invisibility** (Autocomplete hard-caps 5, ranks by prominence) → add a *second, distance-ranked source*: `places:searchNearby` (New), client-side raw REST, mirroring `PlacesAutocompleteService` exactly. It does NOT replace Autocomplete — Autocomplete stays untouched for text search; searchNearby only backs the default (empty-query) state.
2. **Invisible current gym** → surface the already-available `currentGymId` through the existing `gymByIdProvider` + `gymDisplayNameFromGym` as a pinned card at the top of `ProfileGymScreen` — the same 5-line pattern `profile_cuenta_section.dart` already uses.

The resolution/write path (`selectGymActionProvider` → `ResolveGymPlaceService` → `gyms/{placeId}` read-through cache → `gymId`/`gymName` dual-write) is a verified drop-in: `places[].id` from searchNearby is the same Place-ID namespace as Autocomplete, and `sessionToken` is already `String?`-optional and omitted from the Details GET when null. Zero write-path changes.

**Cost is the governing constraint.** `searchNearby` bills as Nearby Search Pro (~$32/1000, no free-session model), unlike Autocomplete's free/Essentials sessions. Cost gating is therefore *structural and provider-owned*, verifiable by a call-counting fake `http.Client`/service — never a widget-level "please don't rebuild too much" convention.

**Seam choice (the load-bearing decision).** `GymSearchBox` is shared by BOTH `step_2_gym.dart` (onboarding) and `profile_gym_screen.dart` (profile edit). Onboarding has no current gym and must NOT show a nearby list (fresh-setup flow, no location prompting mid-onboarding). So:
- The **pinned current-gym card** lives in `ProfileGymScreen` ONLY (above the search box) — never in the shared widget.
- `GymSearchBox` gains ONE optional slot: `emptyQueryContent` (a `Widget?`, default `null` → today's `SizedBox.shrink()`). Onboarding passes nothing → byte-for-byte unchanged behavior. `ProfileGymScreen` passes the nearby-list widget. This is the smallest possible seam and keeps profile-setup working *by construction* (the default preserves the exact current code path).

## Architecture Decisions

### AD-1 — Location pattern: HYBRID (silent check first, inline opt-in affordance that triggers the explicit rationale flow)
**Decision.** Reuse `gymSearchLocationBiasProvider`'s silent `checkPermission()` for the first attempt (no surprise OS dialog on screen-open). When permission is not yet granted, render an inline affordance — "Activar ubicación para ver gyms cercanos" — that, on tap, runs the *explicit* rationale sheet (`showLocationPermissionRationaleSheet`) and, only on acceptance, calls `Geolocator.requestPermission()` (the `athleteLocationProvider.requestPermission()` sequence). No blind OS prompt is ever fired.

**Rationale.** Screen-open must never trigger an OS dialog (that is the coach-discovery lesson encoded in D8). But silent-only would permanently hide the nearby list for users who simply haven't granted yet, defeating the feature's entire purpose (making QIVOX Villa Warcalde reachable). Hybrid gets both: quiet by default, discoverable and consent-gated on demand.

**Rejected.**
- *Silent-only* (`gymSearchLocationBiasProvider` style): no path to recover a denied/undetermined state → nearby list invisible forever for the exact users who need it. Rejected.
- *Explicit rationale-sheet on screen-open* (`athleteLocationProvider` style, prompt immediately): fires a permission flow the user didn't ask for while they may just want to type a search → hostile, and wastes a searchNearby call if they deny. Rejected.

### AD-2 — Caching: LAYERED — mandatory fire-once-per-open floor + geohash-bucket TTL cache across opens
**Decision.** Two layers, both provider-owned:
1. **Floor (mandatory):** the nearby fetch is a `FutureProvider.autoDispose.family` keyed by a *screen-open-scoped location bucket*, not by raw lat/lng. It fires exactly once per distinct bucket value and is memoized by Riverpod for the life of the screen — never per rebuild.
2. **Cross-open TTL cache:** results are stored in a tiny in-memory `Map<String /*geohashBucket*/, _CachedNearby>` inside a `keepAlive` provider (`nearbyGymsCacheProvider`), with a TTL (10 min). The family provider consults the cache first; on hit-within-TTL it returns cached results with ZERO network call. `geohash5` (~4.9km cell) is the bucket key — it aligns almost exactly with the 5km radius (AD-3), so "same neighborhood, second visit" is free.

**Rationale.** Fire-once-per-open is the non-negotiable floor from the proposal. But users re-open this screen (mis-tap, back-navigation, re-check); a 10-min geohash-bucketed cache eliminates the most common repeat-cost with trivial complexity (a Map + timestamp) and bounded staleness (gyms don't move; new gyms appearing within 10 min is irrelevant). Verifiable: the call-counting fake service asserts `.called(1)` across two screen opens in the same bucket.

**Rejected.** *Fire-once-per-open only:* leaves the cheapest, most-frequent repeat (same user, same place, minutes later) fully billed. The added complexity of a Map+TTL is negligible against ~$32/1000. Rejected in favor of layering.

### AD-3 — Radius: FIXED 5km, no expanding retry
**Decision.** `locationRestriction.circle.radius = 5000` (meters), fixed. No auto-retry at a wider radius.

**Rationale.** Each retry is a *separate billed Nearby Search Pro request* — an expanding 5→15km retry doubles cost precisely in the sparse-area case where the feature is least valuable. 5km is the right semantic for a "nearby" list (30km is a metro-wide bias appropriate for Autocomplete, not a scannable list). If empty-result complaints surface in real testing, revisit as a *separate, measured* change — do not pre-pay for a hypothetical.

**Rejected.** *Expanding retry (5→15km if <3 results):* multiplies the most expensive call in the system on a guess. Empty nearby is already handled gracefully (hide section; Autocomplete text search still fully works). Rejected.

### AD-4 — Nearby cap: request `maxResultCount: 20`, render 8, "ver más" reveals already-fetched rows (zero extra calls)
**Decision.** `maxResultCount: 20` in the request (headroom for dedup, AD-5). UI shows the first **8** distance-ranked rows. If more than 8 remain after dedup, a "Ver más" affordance expands the list to reveal the *already-fetched* rows — it is a pure local state toggle, NEVER a re-request.

**Rationale.** One request already returns up to 20 at no extra cost (billing is per-request, not per-result). Capping the *visible* list at 8 keeps it scannable; "Ver más" that re-requests would be a second billed call — forbidden. Requesting 20 also gives dedup headroom so suppressing the current gym (AD-5) never leaves a short list.

**Rejected.** *Cap request at 8:* loses dedup headroom. *"Ver más" that re-fetches:* a billed call for a free operation. Both rejected.

### AD-5 — Dedup: SUPPRESS the current gym from the nearby list (pinned card is the single source of truth)
**Decision.** Filter out the row whose `placeId == currentGymId` from the nearby results before rendering. The pinned card at the top is the one and only representation of the current gym.

**Rationale.** Showing it twice (pinned + in-list) is visually redundant and invites a confusing double-selected state. Suppression is a one-line `.where()` on the fetched list; the `maxResultCount: 20` headroom (AD-4) absorbs the removed row. The pinned card already carries selection affordance implicitly (it IS the current selection).

**Rejected.** *Show it marked in the list too:* duplication, ambiguous selection highlight, no user benefit. Rejected.

### AD-6 — Field mask: INCLUDE `places.location` (free, same Essentials tier); exact mask string specified
**Decision.** `X-Goog-FieldMask: places.id,places.displayName,places.formattedAddress,places.location`

**Rationale.** searchNearby returns NO per-result distance field — the only way to render "a X km" labels is client-side `haversineKm(userLat, userLng, place.lat, place.lng)`. `places.location` is in the same Essentials tier as id/displayName/formattedAddress, so it adds ZERO cost. Omitting the mask entirely errors the call (no default) — the mask is a required, explicit constant on the service, covered by a service test. The distance labels also require the DTO to carry `lat`/`lng` (see DTO decision below).

**Rejected.** *Omit `places.location`:* no distance labels possible, no free-tier cost saved (it's already free). Rejected.

### AD-7 — `PlacesNearbySearchService` API shape (mirror `PlacesAutocompleteService`)
**Decision.** New `lib/features/gyms/data/places_nearby_search_service.dart`:
- Constructor: `PlacesNearbySearchService({required http.Client httpClient, required String clientApiKey})` — identical injection to Autocomplete, test-double-friendly from day one.
- `POST https://places.googleapis.com/v1/places:searchNearby`, headers `X-Goog-Api-Key` + `X-Goog-FieldMask` (the AD-6 constant) + `Content-Type: application/json`.
- Body: `{ includedTypes: ['gym'], maxResultCount: 20, rankPreference: 'DISTANCE', locationRestriction: { circle: { center: {latitude, longitude}, radius: 5000 } } }`.
- Signature: `Future<List<NearbyGym>> search({required double latitude, required double longitude, int radiusMeters = 5000, int maxResultCount = 20})`.
- Error split mirroring Autocomplete: `PlacesNearbySearchConfigError` (empty key) vs `PlacesNearbySearchError(message, {statusCode})` (non-200 / network). NEVER leak the key in any message.
- Zero matches → empty `places` array → returns `const []` (not an error).

**Rationale.** Consistency with the established, tested Autocomplete pattern minimizes reviewer surprise and reuses the codebase's config-vs-request error convention. `locationRestriction.circle` is REQUIRED, so the service takes non-nullable `latitude`/`longitude` — the "no location" case is handled *upstream* in the provider (a distinct branch), never by passing nulls into the service.

### AD-8 — DTO: NEW `NearbyGym` (carries location) — do NOT overload `GymSuggestion`
**Decision.** Introduce `lib/features/gyms/domain/nearby_gym.dart`:
```
class NearbyGym {
  final String placeId;
  final String name;
  final String? address;
  final double lat;
  final double lng;
}
```
`GymSuggestion` stays exactly as-is (no `lat`/`lng` — Autocomplete has none).

**Rationale.** `GymSuggestion` is an Autocomplete-shaped DTO (`primaryText`/`secondaryText`, no coordinates). searchNearby has coordinates and needs them for haversine labels (AD-6). Bolting nullable `lat`/`lng` onto `GymSuggestion` would pollute the Autocomplete path with fields that are always null there, and force every Autocomplete consumer to reason about coordinates it never has. A dedicated `NearbyGym` keeps each source's DTO honest. Both feed the SAME `select(uid, placeId)` — the placeId is all the write path needs, so this DTO split costs nothing downstream.

**Rejected.** *Reuse `GymSuggestion` with nullable lat/lng:* leaks searchNearby concerns into the Autocomplete DTO; nullable coordinates everywhere. Rejected.

### AD-9 — Nearby provider graph (screen-open-scoped, geohash-bucketed, location-gated)
**Decision.** New providers in `places_providers.dart`:

1. `placesNearbySearchServiceProvider` — `Provider<PlacesNearbySearchService>`, mirrors `placesAutocompleteServiceProvider` (shares `httpClientProvider` + `_placesClientKey`). Overridable in tests.
2. `nearbyGymsCacheProvider` — `Provider` returning a small mutable holder (`Map<String, _CachedNearby>` where `_CachedNearby = (List<NearbyGym> results, DateTime fetchedAt)`), `keepAlive` (survives screen-open churn) for the cross-open TTL cache (AD-2 layer 2).
3. `nearbyGymsProvider` — `FutureProvider.autoDispose.family<List<NearbyGym>, String /*geohashBucket*/>`. Given a bucket key: consult `nearbyGymsCacheProvider` (hit-within-TTL → return cached, no network); on miss, call the service ONCE, store in cache, return. This is the fire-once-per-open floor (AD-2 layer 1) — Riverpod memoizes the family entry for the screen's lifetime.
4. `nearbyLocationProvider` — resolves the position for nearby (the hybrid AD-1 flow). Silent `checkPermission()` first; exposes a "not granted" state the UI reads to show the opt-in affordance, plus a method to run the rationale-sheet→`requestPermission()` escalation. Modeled as a `StateNotifierProvider` (like `athleteLocationProvider`) so the UI can drive the escalation and re-read a granted position — and so widget tests override it with a `setForTest(position)`/`setDeniedForTest()` seam, NEVER touching `Geolocator`.

**Data flow (empty query, profile screen open):**
```
ProfileGymScreen opens
  → nearbyLocationProvider (silent checkPermission)
      ├─ granted   → Position → geohashBucket = geohash5(lat,lng)
      │                → nearbyGymsProvider(bucket)
      │                    ├─ cache hit (<TTL) → cached List<NearbyGym>  [0 calls]
      │                    └─ cache miss → service.search(...) once → cache+return  [1 call]
      │                → dedup currentGymId, haversine labels, cap 8 (+ver más)
      └─ not granted → inline "Activar ubicación" affordance
                          → rationale sheet → requestPermission()
                          → on grant, re-drive the granted branch above
```

**Rationale.** Keying the family by `geohash5` bucket (not raw lat/lng) is what makes the fire-once + cross-open cache both testable and cheap: two opens in the same ~4.9km cell resolve to the same key → same memoized/cached entry. `keepAlive` on the cache holder lets it outlive the `autoDispose` family entries. Location is a distinct provider because searchNearby cannot run without it (unlike Autocomplete's null-safe bias) — the gate is explicit, not smuggled through nullable params.

### AD-10 — `GymSearchBox` restructure: add optional `emptyQueryContent` slot (default null)
**Decision.** `GymSearchBox` gains `final Widget? emptyQueryContent;` (constructor-optional, default `null`). In `_SuggestionsList`, the `if (query.isEmpty) return const SizedBox.shrink();` short-circuit (line 122) becomes `if (query.isEmpty) return emptyQueryContent ?? const SizedBox.shrink();`. Everything else in the widget is untouched.

**Rationale.** This is the minimal, non-breaking seam (see Technical Approach). Onboarding (`step_2_gym.dart`) constructs `GymSearchBox` without the new param → `null` → `SizedBox.shrink()` → *identical current behavior, no test churn*. `ProfileGymScreen` passes the nearby-list widget as `emptyQueryContent`. The pinned card is NOT part of this widget — it sits above it in `ProfileGymScreen`, so onboarding never renders it. The slot is passed through `GymSearchBox` down into `_SuggestionsList` (add the field to both).

**Rejected.** *Move nearby into `GymSearchBox` unconditionally:* breaks onboarding (would show a nearby list + fire searchNearby mid-onboarding). *Fork a second widget:* duplicates the debounce/search/error/retry logic the shared widget exists to unify. Both rejected.

### AD-11 — Pinned current-gym card widget (reuse `gymByIdProvider` + `gymDisplayNameFromGym`)
**Decision.** A small presentational widget in `ProfileGymScreen` (private `_PinnedCurrentGym` or a dedicated file under `profile/presentation/widgets/`) that watches `gymByIdProvider(currentGymId)` and renders the resolved `Gym` name via `gymDisplayNameFromGym`, visually marked/bordered (accent border, distinct from `GymCard`). Hidden when `currentGymId == null || currentGymId == kNoGymId` (user has no gym) — nothing to pin. It is display-only; it does NOT re-trigger selection (it IS the current selection).

**Rationale.** Exact reuse of the `profile_cuenta_section.dart` pattern — zero new data plumbing. The pinned card and the nearby list share the `Gym`'s `lat`/`lng` (from `gymByIdProvider`) so the card can optionally show its own "a X km" label too, consistent with the list — but that is a nicety, not required.

## File-Level Change Map

| File | Change | Notes |
|------|--------|-------|
| `lib/features/gyms/data/places_nearby_search_service.dart` | **New** | Raw-REST searchNearby; injected `http.Client`; required field mask (AD-6); config/request error split (AD-7) |
| `lib/features/gyms/domain/nearby_gym.dart` | **New** | `NearbyGym` DTO with `lat`/`lng` (AD-8) |
| `lib/features/gyms/application/places_providers.dart` | **Modified** | `placesNearbySearchServiceProvider`, `nearbyGymsCacheProvider`, `nearbyGymsProvider`, `nearbyLocationProvider` (AD-9) |
| `lib/features/profile_setup/presentation/widgets/gym_search_box.dart` | **Modified** | Add optional `emptyQueryContent` slot; thread into `_SuggestionsList` (AD-10) |
| `lib/features/profile/presentation/profile_gym_screen.dart` | **Modified** | Pinned card above search box; pass nearby-list widget as `emptyQueryContent`; wire location opt-in affordance (AD-1, AD-11) |
| `lib/features/profile/presentation/widgets/nearby_gyms_list.dart` (or inline) | **New/inline** | The `emptyQueryContent` widget: renders `nearbyGymsProvider`, dedup (AD-5), haversine labels (AD-6), cap 8 + "ver más" (AD-4), loading/error/empty/opt-in states |
| `lib/features/profile_setup/presentation/steps/step_2_gym.dart` | **Untouched** | Constructs `GymSearchBox` without the new slot → unchanged behavior (verify only) |
| `lib/features/gyms/data/resolve_gym_place_service.dart`, `gym_repository.dart` | **Untouched** | Write/resolution path compatible as-is |
| `lib/features/gyms/domain/gym_suggestion.dart` | **Untouched** | Autocomplete DTO stays as-is (AD-8) |
| `l10n` (app strings) | **Modified** | es-AR copy: "Activar ubicación para ver gyms cercanos", "Ver más", nearby empty/error labels |

## Riverpod Provider Graph Deltas

```
httpClientProvider  (existing, singleton http.Client)
  ├─ placesAutocompleteServiceProvider   (existing, untouched)
  ├─ resolveGymPlaceServiceProvider       (existing, untouched)
  └─ placesNearbySearchServiceProvider    (NEW — mirrors autocomplete provider)

nearbyLocationProvider  (NEW, StateNotifier — silent check → escalation; test seam: setForTest/setDeniedForTest)

nearbyGymsCacheProvider (NEW, keepAlive — Map<geohashBucket, (results, fetchedAt)>)

nearbyGymsProvider (NEW, FutureProvider.autoDispose.family<List<NearbyGym>, String bucket>)
   watches → placesNearbySearchServiceProvider
   reads   → nearbyGymsCacheProvider (TTL hit → 0 calls; miss → 1 call, then cache)

gymByIdProvider (existing) ← pinned card reuse (AD-11)
selectGymActionProvider (existing) ← nearby tap reuses select(uid, placeId), no change
```
No changes to: `placesSuggestionsProvider`, `gymSearchSessionTokenProvider`, `gymSearchLocationBiasProvider`, `selectGymActionProvider`, `resolveGymPlaceServiceProvider`.

## Loading / Error / Empty / Opt-in states (nearby section)

| State | Render |
|-------|--------|
| Location not-granted | Inline "Activar ubicación para ver gyms cercanos" affordance (AD-1) → rationale sheet on tap |
| Location loading (escalation in flight) | Small spinner in the affordance slot |
| Fetch loading | `CircularProgressIndicator` (matches `_SuggestionsList` loading) |
| Fetch error | Retry affordance mirroring `_ErrorRetry` (invalidate `nearbyGymsProvider(bucket)`) |
| Empty (0 matches after dedup) | Hide the section (no "sin resultados" noise — this is a default view, not a query) |
| Data | Up to 8 `GymCard`s with "a X km" labels; "Ver más" if >8 remain |

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| searchNearby cost balloons (per-rebuild / per-open) | High impact | Structural: `nearbyGymsProvider` is the sole caller, keyed by geohash bucket, memoized per open + TTL-cached across opens (AD-2/AD-9). Verified by call-counting fake asserting `.called(1)` across rebuilds AND across same-bucket re-opens |
| `Geolocator.checkPermission()` hangs under `testWidgets` (confirmed gotcha) | High | `nearbyLocationProvider` is a `StateNotifier` with `setForTest`/`setDeniedForTest` seams (AD-9); ALL widget tests override it — never a real `Geolocator` call. Service is `http.Client`-injected |
| Field mask omitted/wrong → API error (no default) | Med | Mask is a required explicit constant (AD-6); dedicated service test asserts the exact header value |
| No/denied location → searchNearby cannot run | Med | Distinct provider gate (AD-9): hide section + opt-in affordance; Autocomplete text search fully works regardless |
| Breaking onboarding via the shared widget | Med | `emptyQueryContent` defaults to `null` → identical current behavior; `step_2_gym.dart` untouched (AD-10). Existing `gym_search_box_test.dart` / `step_2_gym_test.dart` must stay green unchanged |
| Current gym duplicated in list | Low | Suppress by `placeId == currentGymId` (AD-5), `maxResultCount: 20` headroom absorbs the removal |
| Stale cache shows a since-removed gym | Low | 10-min TTL; gyms are near-static; resolution path self-heals on tap (read-through cache) |

## Chained-PR Slices

Natural 2-way split, each under the 400-line review budget:

**Slice 1 — Data + application layer (no UI).** `PlacesNearbySearchService` + `NearbyGym` DTO + the four new providers (`placesNearbySearchServiceProvider`, `nearbyGymsCacheProvider`, `nearbyGymsProvider`, `nearbyLocationProvider`). Tests: service unit tests (config error, non-200, empty array, field-mask header, body shape) with a fake `http.Client`; provider tests proving fire-once-per-open AND cross-open TTL cache via a **call-counting fake service** (`.called(1)` across rebuilds and same-bucket re-opens). No `lib/` UI touched → independently reviewable and mergeable. Est. ~300 lines incl. tests.

**Slice 2 — Screen redesign (UI).** `GymSearchBox` `emptyQueryContent` slot (AD-10); `ProfileGymScreen` pinned card (AD-11) + nearby-list widget wired as `emptyQueryContent` + location opt-in affordance (AD-1); es-AR l10n strings. Tests: widget tests for each nearby state (not-granted/loading/error/empty/data, ver-más) with `nearbyGymsProvider` and `nearbyLocationProvider` overridden — **NEVER real Geolocator**; a regression test that onboarding (`step_2_gym`) still renders unchanged with no nearby list. Depends on Slice 1's providers. Est. ~350 lines incl. tests.

Slicing rationale: Slice 1 is pure additive infra with zero UI risk and its own cost-gating tests — the highest-risk part (billing) is verified before any UI exists. Slice 2 is presentation-only against a proven provider surface. The seam (`emptyQueryContent` default null) means Slice 2 can't regress onboarding.

## Test Plan

**Slice 1 (unit):**
- Service: empty key → `PlacesNearbySearchConfigError`; non-200 → `PlacesNearbySearchError` with statusCode; empty `places` → `[]`; correct field-mask header; correct body (`includedTypes:['gym']`, `rankPreference:'DISTANCE'`, `radius:5000`, `maxResultCount:20`); key never in error messages. Fake `http.Client`.
- Providers: call-counting fake service → `nearbyGymsProvider(bucket)` fires exactly once across N rebuilds (floor); returns cached with 0 calls on same-bucket re-open within TTL, 1 call after TTL expiry / different bucket (cache). `nearbyLocationProvider` denied/granted transitions via `setForTest`/`setDeniedForTest`.

**Slice 2 (widget, all providers overridden):**
- Pinned card renders current gym name; hidden for `kNoGymId`/null.
- Nearby states: not-granted → affordance; data → 8 rows + "a X km"; >8 → "Ver más" reveals rest with no extra service call; empty → section hidden; error → retry.
- Dedup: current gym absent from the nearby rows.
- Nearby tap → `select(uid, placeId)` invoked (mock `selectGymActionProvider`).
- Regression: `step_2_gym` unchanged (no nearby list, existing tests green).
- Location: ALWAYS override `nearbyLocationProvider` — never touch `Geolocator`.

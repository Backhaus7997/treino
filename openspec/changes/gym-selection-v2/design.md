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

## Addendum — Phase 3 (post-verify device-testing fixes)

**Trigger.** gym-selection-v2 shipped (31/31 tasks, verify PASS-WITH-WARNINGS) but device testing surfaced two real-world usability failures Slice 1/2's synthetic tests couldn't catch: (1) Autocomplete's typed search — even location-biased to the user's own zone — never surfaced his real gym (QIVOX Villa Warcalde) in 5 tries; empirically, a raw `searchText` call for "qivox" biased to the same zone returned 15 results, all QIVOX branches, closest first. (2) The nearby list's 8-row cap buried his gym at rank #14 in a yoga/pilates-dense neighborhood, so it was invisible even though it was one of the 20 already-fetched, already-paid-for results.

Both fixes are approved and settled (not reopened here) — this section records the two new Architecture Decisions and updates the affected requirements.

### AD-12 — Typed search backend swap: Autocomplete → Text Search (New), with structural cost gating and session-token removal

**Decision.** `GymSearchBox`'s typed (non-empty-query) search moves from `PlacesAutocompleteService`/`places:autocomplete` to a new `PlacesTextSearchService` calling `POST https://places.googleapis.com/v1/places:searchText`.
- Body: `{ textQuery, pageSize: 20, locationBias: {circle: {center, radius}} }` — `locationBias` is OMITTED (not just null-valued) when no location is available, mirroring Autocomplete's existing all-or-nothing bias contract exactly (no regression to the "search works with no location permission" invariant).
- Headers: `X-Goog-Api-Key`, REQUIRED `X-Goog-FieldMask: places.id,places.displayName,places.formattedAddress`, `Content-Type: application/json`.
- Response mapping: `places[].{id, displayName.text, formattedAddress}` → the EXISTING `GymSuggestion(placeId, primaryText, secondaryText)` DTO — zero changes to `GymCard`, the suggestions list rendering, or the selection callback signature. `GymSuggestion` is reused as-is; no new DTO (unlike `NearbyGym` in AD-8, which needed coordinates Text Search results don't require here).
- **Cost gating is structural, not incidental** (Text Search Pro bills ~$32/1000, same tier as `searchNearby`): debounce ~600ms after typing stops (widened from the prior 300ms — a slower, cost-bearing backend needs a wider settle window; this lives in the PROVIDER layer via an injectable/fake-clock-controllable debounce mechanism, not a widget `Timer`, so tests never sleep real wall-clock time), a 3-character minimum before any request fires, and a cache keyed by `(normalized query, geohash5-of-bias-center-or-null)` with a ~10-minute TTL — mirroring `NearbyGymsCache`'s shape (`Map<key, (results, fetchedAt)>`, `get(key, {now})`/`put(key, results, {fetchedAt})`). One request per settled query; a call-counting fake service proves rapid keystrokes within the debounce window and a repeat of the same settled query within TTL both cost zero extra calls.
- **Session tokens are removed from the search path.** Text Search has no session-token concept (unlike Autocomplete, which bundles keystroke-level Autocomplete calls + the eventual Details call into one billed "session"). Every selection made from `GymSearchBox`'s typed results — like every nearby-list selection since AD-9 shipped — now calls `selectGymActionProvider.select(..., useSessionToken: false)`. This makes the ENTIRE gym-selection surface (typed search + nearby list) session-token-free, not just nearby. `gymSearchSessionTokenProvider` and `PlacesAutocompleteService` become dead code with this change (their only production caller, `placesSuggestionsProvider`, is deleted) — both are DELETED, along with their dedicated tests; git history preserves them if ever needed again. `resolveGymPlaceServiceProvider`/`ResolveGymPlaceService` are UNCHANGED (already accept a nullable `sessionToken`, already used null-session for nearby).
- `gymSearchLocationBiasProvider` (the `checkPermission()`-only, never-prompts bias lookup) is UNCHANGED and now feeds the new `placesTextSearchProvider`'s `locationBias` the same way it fed Autocomplete's `locationBias`.
- `GymSearchBox`/onboarding (`step_2_gym.dart`) share the same `_SuggestionsList` internals, so onboarding automatically gets the fixed search — no separate onboarding-specific change, same as AD-10's seam already guaranteed for the nearby list.

**Rationale.** The empirical result is unambiguous: prominence-ranked Autocomplete systematically hides chain-branch/low-review-count gyms behind well-known "flagship" locations even when location-biased to the exact same query and zone (this was ALREADY the documented root cause the whole gym-selection-v2 change was built to address for the nearby list — Phase 3 closes the gap by applying the same distance/relevance-oriented backend to typed search too). Text Search (New) ranks by relevance-to-query with an optional bias circle, which in this case behaved like a closest-first ranking for a branded query — a direct fix with no new architecture pattern (mirrors `PlacesNearbySearchService`'s shape exactly, per Project Standards). Reusing `GymSuggestion` (not inventing a new DTO) keeps the fix contained to the data-fetching layer; every downstream consumer (list rendering, tap-to-select, `ResolveGymPlaceService`) is untouched.

**Rejected.**
- *Hybrid: keep Autocomplete, add a "ver todos los resultados" button that triggers a one-off Text Search fallback.* Adds a second interaction step and a visible "why are there two search modes" seam for the user, to save fractions of a cent per query at TREINO's current scale (a handful of onboarding/profile-edit searches per day). The UX friction is not justified by the marginal cost delta between Autocomplete Essentials and Text Search Pro at this volume. Rejected.
- *Keep `searchNearby`'s `includedPrimaryTypes`-style filter (`includedType: 'gym'`) on a Nearby-Search-shaped typed query instead of swapping to Text Search.* Empirically tested during exploration — filtering by `gym` type on a Nearby-shaped request does NOT clean up the branded-query noise; QIVOX branches still lost to prominent competitors because the ranking signal (not the type filter) was the actual defect. Rejected — doesn't fix the observed problem.
- *Lower the character minimum below 3 / drop the debounce widening.* Both would materially increase billed-call volume on a backend with no free tier, for marginal UX gain (a 1-2 character query rarely narrows to a useful result set anyway). Rejected.

### AD-13 — Nearby list: render all fetched (drop the 8-cap and "Ver más")

**Decision.** `NearbyGymsList` renders ALL results returned by `nearbyGymsProvider` (up to the existing `maxResultCount: 20` request cap from AD-4/AD-7 — that request-side cap is UNCHANGED), not just the first 8. The `_kVisibleCap` constant, the `_expanded` toggle state, and the "Ver más" affordance (including the `gymNearbyShowMore` render path) are REMOVED. The list becomes scrollable (it already sits inside `ProfileGymScreen`'s `SingleChildScrollView`, so no new scroll container is needed — same composition, more rows).

**Rationale.** The 20 results are already fetched and already billed for (AD-4's entire rationale for requesting 20-not-8 was "one request already returns up to 20 at no extra cost… gives dedup headroom"); artificially hiding 12 of them behind a manual expand step actively worked against the feature's purpose in the field. The user's real gym ranked #14 in a neighborhood saturated with yoga/pilates studios also tagged `gym` — a dense, plausible real-world scenario, not an edge case — and sat invisible behind "Ver más" during device testing. Rendering all fetched rows costs zero additional API calls (pure render-more-of-what-you-already-have) and directly fixes the observed failure.

**Rejected.**
- *Keep the cap but raise it to e.g. 12 or 15.* Same class of bug at a different threshold — a sufficiently dense area still buries results, just less often. Doesn't address the root cause (artificial UI limiting of already-paid-for data). Rejected.
- *Add `includedPrimaryTypes`/stricter type filtering to `searchNearby` to suppress yoga/pilates studios before rendering.* Explored and rejected for the same empirical reason as AD-12's rejected alternative: Google's `gym` type tagging is broad enough in practice (density-tagged wellness studios) that a type filter does not reliably separate "real gym" from "yoga studio tagged gym" — it would require heuristics beyond what the Places API's type taxonomy supports, and risks false-negatives (hiding legitimate small gyms). Rendering all 20 and letting the user scroll/scan is simpler, costs nothing extra, and doesn't risk hiding a real gym. Rejected.

### File-Level Change Map (Addendum)

| File | Change | Notes |
|------|--------|-------|
| `lib/features/gyms/data/places_text_search_service.dart` | **New** | Raw-REST `searchText`; mirrors `PlacesNearbySearchService`'s injection/error-split shape (AD-12) |
| `lib/features/gyms/data/places_autocomplete_service.dart` | **Deleted** | Dead — `placesSuggestionsProvider` (its only caller) is deleted (AD-12) |
| `lib/features/gyms/application/places_providers.dart` | **Modified** | Remove `placesAutocompleteServiceProvider`, `gymSearchSessionTokenProvider`, `placesSuggestionsProvider`; add `placesTextSearchServiceProvider`, `textSearchCacheProvider`, `placesTextSearchProvider` (debounced, cost-gated, cache-first) (AD-12) |
| `lib/features/profile_setup/presentation/widgets/gym_search_box.dart` | **Modified** | `_SuggestionsList` reads the new text-search provider instead of `placesSuggestionsProvider`; debounce moves to the provider layer (AD-12) |
| `lib/features/profile/presentation/widgets/nearby_gyms_list.dart` | **Modified** | Remove `_kVisibleCap`/`_expanded`/"Ver más" — render all fetched rows (AD-13) |
| `lib/features/gyms/domain/gym_suggestion.dart` | **Untouched** | Reused as-is for Text Search results too (AD-12) |
| `lib/features/gyms/data/resolve_gym_place_service.dart` | **Untouched** | Already accepts nullable `sessionToken`; no change needed |

### Risks & Mitigations (Addendum)

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Text Search cost balloons per-keystroke | High impact | Structural: debounce (provider-layer, fake-clock-testable) + 3-char minimum + query/bias-keyed TTL cache, verified by a call-counting fake asserting one call per settled query |
| Deleting `gymSearchSessionTokenProvider`/`PlacesAutocompleteService` breaks an undiscovered consumer | Med | Grepped ALL consumers before deletion (test files only, all rewritten in this same slice); `resolveGymPlaceServiceProvider` already accepts nullable token independently |
| Removing the 8-cap causes a very-dense-area list to feel overwhelming | Low | Explicit product tradeoff accepted: findability of the user's actual gym outweighs list length: the list already scrolls inside the existing `SingleChildScrollView` |
| `locationBias` omission logic diverges from Autocomplete's, causing a subtle no-location regression | Low | Body-construction mirrors Autocomplete's exact `if (lat != null && lng != null) 'locationBias': {...}` conditional-inclusion pattern; covered by an explicit no-location test scenario |

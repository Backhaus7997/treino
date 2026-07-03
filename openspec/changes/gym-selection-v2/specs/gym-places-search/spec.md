# Delta for Gym Places Search

## ADDED Requirements

### Requirement: Nearby gyms list is distance-ranked and fetched via searchNearby

The system MUST offer a distance-ranked list of nearby gyms, retrieved client-side via the Places `searchNearby` (New) endpoint with `includedTypes: ['gym']`, a `locationRestriction` circle centered on the athlete's resolved location, and the required `X-Goog-FieldMask` header. The list MUST be bounded to a fixed, reasonable size (design owns the exact cap). Unlike Autocomplete's prominence ranking, distance ranking surfaces low-prominence/chain-branch gyms Autocomplete's 5-result cap hides.

#### Scenario: Nearby list ranks results by distance, not prominence

- GIVEN an athlete opens the gym-selection screen with location available
- WHEN the nearby gyms list is fetched
- THEN results are ordered by distance from the athlete's location
- AND the list contains at most the configured bounded count of gyms

### Requirement: Nearby fetch is cost-gated to at most once per screen-open

The system MUST fire the `searchNearby` request AT MOST ONCE per screen-open. Widget rebuilds, re-renders, or state changes that do not represent a new screen-open MUST NOT trigger an additional `searchNearby` call.

#### Scenario: Repeated rebuilds do not re-fetch nearby gyms

- GIVEN the gym-selection screen has already fetched the nearby list once for the current screen-open
- WHEN the screen rebuilds multiple times (e.g. due to unrelated state changes, such as typing in the search box and clearing it)
- THEN no additional `searchNearby` request is made
- AND this is verifiable with a call-counting test double asserting exactly one invocation

#### Scenario: Reopening the screen allows a new fetch

- GIVEN an athlete leaves the gym-selection screen after the nearby list was fetched once
- WHEN they navigate to the gym-selection screen again (a new screen-open)
- THEN a new `searchNearby` request MAY be fired

### Requirement: Nearby list degrades gracefully without location permission

The system MUST NOT block or error the gym-selection screen when location permission is unavailable, denied, or restricted. When location cannot be resolved, the nearby-gyms section MUST be absent or replaced by an affordance, while text search MUST remain fully functional.

#### Scenario: No location permission hides the nearby section without breaking search

- GIVEN an athlete has denied location permission
- WHEN they open the gym-selection screen
- THEN no `searchNearby` request is attempted
- AND the nearby-gyms section is either absent or replaced by a location affordance
- AND Autocomplete text search still returns results normally

### Requirement: Zero nearby results hides the section without an error

The system MUST treat an empty `searchNearby` result set as a normal, non-error outcome.

#### Scenario: No gyms nearby hides the section silently

- GIVEN an athlete's location resolves successfully but no gyms exist within the search radius
- WHEN the nearby list is fetched
- THEN the nearby-gyms section is hidden
- AND no error message is shown to the athlete

### Requirement: Selecting a nearby gym uses the same selection path as Autocomplete

The system MUST route a tap on a nearby-list gym through the same selection/resolve/write path used for an Autocomplete suggestion tap. A nearby-originated selection MUST resolve correctly even without an Autocomplete session token.

#### Scenario: Tapping a nearby gym selects and persists it

- GIVEN an athlete taps a gym in the nearby list
- WHEN the selection is processed
- THEN it is resolved and written to the athlete's profile through the identical path used for an Autocomplete selection
- AND the absence of a session token does not cause an error or a degraded resolution

## MODIFIED Requirements

### Requirement: Place Details resolution happens client-side with a bundle-restricted key

The system MUST perform Place Details resolution directly from the client using the same bundle-id-restricted API key used for Autocomplete, reading through the `gyms/{placeId}` cache before issuing a Details request. The system MUST NOT depend on a Cloud Function for resolution (org policy blocks public Cloud Function invokers).

(Previously: required a Cloud Function with a server-side key, no client Details calls. Corrected to match the shipped client-side architecture — already inaccurate before this change; fixed here since this change extends the same resolution path.)

#### Scenario: Selecting a suggestion resolves via a direct client-side Details call

- GIVEN a user taps an Autocomplete suggestion or a nearby-list gym
- WHEN the app resolves that selection
- THEN resolution happens via a client-side Details request using the bundle-restricted key
- AND a cache hit on `gyms/{placeId}` skips the Details request entirely

#### Scenario: One session token spans a full search-to-selection flow

- GIVEN a user opens the gym picker and starts typing
- WHEN multiple Autocomplete requests fire across keystrokes and the user then selects a suggestion
- THEN every Autocomplete request and the resulting Details resolution share the same session token

#### Scenario: A new search starts a new session token

- GIVEN a user has just completed a gym selection (session token consumed)
- WHEN they reopen the gym picker and start a new search
- THEN a new session token is generated; it is not the same value as the previous session's token

#### Scenario: A nearby-originated selection resolves without a session token

- GIVEN a user selects a gym from the nearby list (no Autocomplete session in progress)
- WHEN the selection is resolved
- THEN the Details request omits the session token parameter entirely
- AND the resolution succeeds identically to a tokened request

## Unchanged Invariants (restated for continuity)

### Requirement: Selection performs a soft gym-type check

The system MUST bias/prioritize but MUST NOT hard-reject a selected Place based on its Google `types`. UNCHANGED by this delta.

#### Scenario: Non-gym Place can still be selected

- GIVEN a user selects a Place whose `types` do not include a gym-related category
- WHEN the selection is resolved
- THEN the gym is still created/assigned; no hard validation error blocks it

## Phase 3 Addendum — Typed search backend swap + nearby render cap removal

Device testing after the initial gym-selection-v2 ship revealed the typed search still could not find the user's own gym even with location bias — a 5-result Autocomplete list, prominence-ranked, never surfaced a real, nearby, correctly-typed Place across repeated tries. This addendum replaces the Autocomplete-based typed search with Text Search (New) and removes the nearby list's render cap. Design AD-12/AD-13 own the implementation decisions (cost gating, debounce, cache shape, session-token removal); this section restates the resulting behavior contract.

### MODIFIED Requirement: Typed gym search is performed via Places Text Search (New), not Autocomplete

The system MUST perform the athlete's typed (non-empty-query) gym search via the Places `searchText` (New) endpoint, bounded to a reasonable page size (design owns the exact bound), optionally biased toward the athlete's location when available, and MUST return results ranked closer-to-relevant/closest-first for a query rather than by generic prominence. The system MUST NOT call the Autocomplete endpoint for typed search. The system MUST fire at most one `searchText` request per settled query (debounce-gated) and MUST NOT re-fetch for a query already served within the cache TTL.

(Previously: typed search ran via Places Autocomplete (New), prominence-ranked, hard-capped to Google's default suggestion count, with a session-token-bundled Details resolution. Superseded here — device testing showed prominence ranking systematically hid a real, correctly-typed, nearby Place across repeated tries; Text Search's relevance/bias-oriented ranking fixed this empirically. Nearby-list `searchNearby` behavior from the original delta above is UNCHANGED by this addendum — only typed search moves.)

#### Scenario: Typed search finds a real nearby gym that Autocomplete missed

- GIVEN an athlete's location is biased to their own neighborhood
- WHEN they type a query matching their gym's brand/name
- THEN the results include that gym, ranked at or near the top by closeness/relevance to the query
- AND this holds even when multiple same-brand branches exist in the wider metro area

#### Scenario: Typed search is debounced and cost-gated

- GIVEN an athlete is actively typing a query
- WHEN they type multiple characters in rapid succession
- THEN no `searchText` request fires until typing settles for the configured debounce window
- AND queries under the configured minimum character count never trigger a request

#### Scenario: Repeating a settled query within the cache TTL does not re-fetch

- GIVEN an athlete's typed query has already been fetched once and settled
- WHEN the same query (with the same location-bias bucket, or the same query with no location) is issued again within the cache TTL
- THEN no additional `searchText` request is made and the cached results are returned

#### Scenario: Typed search still works with no location permission

- GIVEN an athlete has denied or not granted location permission
- WHEN they perform a typed gym search
- THEN the `searchText` request omits the location-bias parameter entirely
- AND results are still returned, without bias and without a permission error

### MODIFIED Requirement: Selecting a typed-search result requires no session token

The system MUST route a tap on a typed-search result through the same selection/resolve/write path as a nearby-list tap, WITHOUT an Autocomplete-style session token — Text Search has no session concept. A typed-search selection MUST resolve correctly with no session token present.

(Previously: one Autocomplete session token spanned every keystroke's suggestion request and the eventual Details resolution, and a new token was minted after each completed selection or new search. Superseded here — Text Search never participates in a session, so this bookkeeping is removed for the entire typed-search path along with the underlying Autocomplete service and its session-token provider.)

#### Scenario: Tapping a typed-search result selects and persists it without a session token

- GIVEN an athlete taps a gym in the typed-search results
- WHEN the selection is processed
- THEN it is resolved and written to the athlete's profile through the identical path used for a nearby-list selection
- AND the absence of a session token does not cause an error or a degraded resolution

### MODIFIED Requirement: Nearby gyms list renders every fetched result, not a fixed visible cap

The system MUST render every gym returned by the nearby fetch (bounded only by the existing fetch-side cap from the ADDED "Nearby gyms list is distance-ranked" requirement above), not a smaller fixed visible-count subset. The system MUST NOT require an additional user action ("ver más"/"show more") to reveal already-fetched results.

(Previously: the nearby list requested up to a bounded count but rendered only a smaller fixed subset by default, revealing the rest via a "ver más" affordance with zero additional fetches. Superseded here — device testing showed a real gym ranked outside the smaller visible subset in a dense area, staying invisible behind the affordance; rendering everything already fetched removes that failure mode at no additional cost, since the larger bound was already being paid for.)

#### Scenario: A nearby gym ranked outside the old visible-cap is now visible without extra interaction

- GIVEN the nearby fetch returns more results than the previous fixed visible cap
- WHEN the nearby list renders
- THEN every fetched result is shown without requiring a "ver más"/"show more" tap
- AND no additional `searchNearby` request is made to render the additional rows

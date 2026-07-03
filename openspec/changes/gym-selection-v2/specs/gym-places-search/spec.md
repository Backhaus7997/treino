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

### Requirement: Autocomplete search is location-biased when available, unbiased otherwise

The system MUST bias Autocomplete results toward the user's current location when permission is granted, and MUST fall back to an unbiased search otherwise — without blocking or erroring. UNCHANGED; `searchNearby`'s mandatory-location requirement does not alter Autocomplete's null-safe bias.

#### Scenario: Search succeeds with no location permission

- GIVEN a user has denied location permission
- WHEN they perform a gym search
- THEN Autocomplete results are still returned, without bias and without a permission error

### Requirement: Selection performs a soft gym-type check

The system MUST bias/prioritize but MUST NOT hard-reject a selected Place based on its Google `types`. UNCHANGED by this delta.

#### Scenario: Non-gym Place can still be selected

- GIVEN a user selects a Place whose `types` do not include a gym-related category
- WHEN the selection is resolved
- THEN the gym is still created/assigned; no hard validation error blocks it

# Gym Places Search Specification

## Purpose

Define the observable contract of Google Places (New) Autocomplete-backed gym search: client-side Autocomplete with session tokens and a bundle-restricted key, server-side Place Details + `gyms/{place_id}` upsert via a Cloud Function, and a soft (non-blocking) gym-type check.

## Requirements

### Requirement: Autocomplete runs client-side with a session token

The system MUST issue Google Places Autocomplete requests directly from the client using a bundle-id-restricted API key. The system MUST generate one session token per search session and reuse it across every keystroke's Autocomplete request within that session, and MUST include the same token in the one Place Details request triggered by the eventual selection. The system MUST start a new session token after a selection completes (or the picker is reopened), never reusing a token across sessions.

#### Scenario: One session token spans a full search-to-selection flow

- GIVEN a user opens the gym picker and starts typing
- WHEN multiple Autocomplete requests fire across keystrokes and the user then selects a suggestion
- THEN every Autocomplete request and the resulting Details resolution share the same session token

#### Scenario: A new search starts a new session token

- GIVEN a user has just completed a gym selection (session token consumed)
- WHEN they reopen the gym picker and start a new search
- THEN a new session token is generated; it is not the same value as the previous session's token

### Requirement: Place Details resolution happens server-side only

The system MUST NOT call the Google Places Details endpoint from the client. The system MUST perform Place Details resolution exclusively inside a Cloud Function, which holds the Places server API key via Secret Manager and is never exposed to the client bundle.

#### Scenario: Selecting a suggestion triggers a server-side resolve, not a client Details call

- GIVEN a user taps an Autocomplete suggestion
- WHEN the app resolves that selection
- THEN the resolution happens via a Cloud Function call, and no Places Details HTTP request originates from the client

### Requirement: Autocomplete search is location-biased when available, unbiased otherwise

The system MUST bias Autocomplete results toward the user's current location when location permission has been granted, and MUST fall back to an unbiased (global) search when permission is denied, restricted, or unavailable — without blocking or erroring the search.

#### Scenario: Search succeeds with no location permission

- GIVEN a user has denied location permission
- WHEN they perform a gym search
- THEN Autocomplete results are still returned, without location bias and without a permission-denied error blocking the search

### Requirement: Selection performs a soft gym-type check

The system MUST bias/prioritize but MUST NOT hard-reject a selected Place based on its Google `types`. A user MAY select and be assigned a Place whose types do not clearly indicate a gym.

#### Scenario: Non-gym Place can still be selected

- GIVEN a user selects a Place whose `types` do not include a gym-related category
- WHEN the selection is resolved
- THEN the gym is still created/assigned; no hard validation error blocks the selection based on type alone

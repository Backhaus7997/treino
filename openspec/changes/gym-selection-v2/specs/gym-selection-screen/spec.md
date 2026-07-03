# Gym Selection Screen Specification

## Purpose

Define the observable behavior of the athlete-facing gym-selection screen (`ProfileGymScreen`, reached from the Gimnasio tile): a pinned current-gym indicator, a nearby/search body that switches source based on query state, and a persistent no-gym option. Supersedes the shallow "search + select" contract in REQ-PROFILE-019 of `openspec/specs/profile/spec.md` with a full composition contract.

## Requirements

### Requirement: Current gym is pinned and visually distinguished at the top

When the athlete has a gym assigned (`gymId` is non-null and not `kNoGymId`), the screen MUST display a pinned card showing the current gym at the top, visually distinguished from any nearby or search result item, and MUST remain visible regardless of query state or list contents below it.

#### Scenario: Athlete with a gym sees it pinned on screen open

- GIVEN an athlete's profile has a resolved `gymId`
- WHEN they open the gym-selection screen
- THEN a pinned card showing that gym's name appears at the top
- AND the card is visually distinguished (e.g. bordered/marked) from nearby and search result cards

#### Scenario: Pinned card shows a loading state while the gym name resolves

- GIVEN an athlete's profile has a `gymId` whose gym document has not yet loaded
- WHEN the screen renders
- THEN the pinned card shows a loading state instead of a blank or incorrect name

### Requirement: No pinned card when the athlete has no gym

When the athlete's `gymId` is null or equals `kNoGymId`, the screen MUST NOT show a pinned current-gym card, and MUST go directly to the nearby/search body.

#### Scenario: Athlete without a gym sees no pinned card

- GIVEN an athlete's profile has `gymId` equal to null or `kNoGymId`
- WHEN they open the gym-selection screen
- THEN no pinned current-gym card is rendered
- AND the nearby/search body (or its degraded state) is the first visible content

### Requirement: Body content switches between nearby list and search results based on query state

When the search query is empty, the screen MUST show the nearby-gyms list (or its graceful-degradation affordance). When the query is non-empty, the screen MUST replace that content with Autocomplete search results. Clearing the query back to empty MUST restore the nearby list.

#### Scenario: Empty query shows the nearby list

- GIVEN an athlete opens the gym-selection screen with an empty search query
- WHEN the screen renders
- THEN the nearby-gyms list (or its no-location/no-results affordance) is shown
- AND no Autocomplete search results are shown

#### Scenario: Typing a query replaces the nearby list with search results

- GIVEN the nearby list is currently shown
- WHEN the athlete types a non-empty search query
- THEN the nearby list is replaced by Autocomplete search results matching the query

#### Scenario: Clearing the query restores the nearby list

- GIVEN the athlete has typed a query and is viewing search results
- WHEN they clear the query back to empty
- THEN the nearby list (or its graceful-degradation affordance) reappears in place of the search results

### Requirement: "No tengo gimnasio" option persists at the bottom in all states

The system MUST keep a "No tengo gimnasio" (or equivalent no-gym) option visible at the bottom of the screen regardless of query state, pinned-card presence, or nearby/search content.

#### Scenario: No-gym option remains visible across query states

- GIVEN the gym-selection screen is showing the nearby list with an empty query
- WHEN the athlete types a search query and views results
- THEN the "No tengo gimnasio" option stays visible at the bottom in both states

### Requirement: Selecting a different gym updates the screen to reflect the new selection

When the athlete selects a gym (from the pinned card's alternative, the nearby list, search results, or the no-gym option), the screen MUST reflect that new selection as the active/highlighted choice, replacing any previously active selection.

#### Scenario: Selecting a new gym replaces the prior selection in the UI

- GIVEN an athlete currently has Gym A selected and visible in the pinned card
- WHEN they select Gym B from the nearby list or search results
- THEN Gym B becomes the active/highlighted selection
- AND Gym A is no longer shown as the active selection

#### Scenario: Selecting "No tengo gimnasio" clears the active gym selection

- GIVEN an athlete currently has a gym selected
- WHEN they select "No tengo gimnasio"
- THEN no gym is shown as the active selection

### Requirement: Selected gym persists across app restarts

The athlete's gym selection MUST persist by reading `users/{uid}.gymId` on subsequent app opens. UNCHANGED invariant — restated for continuity with the resolution/write path this screen depends on.

#### Scenario: Gym selection survives an app restart

- GIVEN an athlete has selected and saved a gym
- WHEN the app is fully restarted and the athlete reopens the gym-selection screen
- THEN the previously selected gym is shown as the current gym, read from `users/{uid}.gymId`

# Tasks: Gym Selection v2 (nearby-gyms list + gym-selection screen redesign)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~650 total (2 slices) |
| 400-line budget risk | Low |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 → PR 2 |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Data + application layer: `PlacesNearbySearchService`, `NearbyGym` DTO, 4 new providers, cost-gating + location-seam tests | PR 1 | Base: feature/tracker branch. No UI touched. ~300L incl. tests. |
| 2 | Screen redesign: `emptyQueryContent` seam, pinned card, nearby-list widget, location opt-in affordance, onboarding regression guard | PR 2 | Base: PR 1 branch. Depends on Slice 1 providers. ~350L incl. tests. |

## Phase 1: Data + Providers (Slice 1 — PR 1)

Traceability: `[gym-places-search: Nearby list ranked by distance]`, `[gym-places-search: cost-gated fetch]`, `[gym-places-search: graceful degradation]`, `[gym-places-search: zero results]`, `[gym-places-search: nearby selection path]`, `[AD-2]`, `[AD-3]`, `[AD-6]`, `[AD-7]`, `[AD-8]`, `[AD-9]`.

- [x] 1.1 RED: `test/features/gyms/domain/nearby_gym_test.dart` — `NearbyGym` DTO construction/equality with `placeId`, `name`, `address`, `lat`, `lng` per `[AD-8]`.
- [x] 1.2 GREEN: `lib/features/gyms/domain/nearby_gym.dart` — implement `NearbyGym` per `[AD-8]`.
- [x] 1.3 RED: `test/features/gyms/data/places_nearby_search_service_test.dart` — fake `http.Client` cases per `[AD-6]`/`[AD-7]`: empty key → `PlacesNearbySearchConfigError`; non-200 → `PlacesNearbySearchError(statusCode)`; empty `places` array → `const []`; exact `X-Goog-FieldMask` header (`places.id,places.displayName,places.formattedAddress,places.location`); exact body (`includedTypes:['gym']`, `rankPreference:'DISTANCE'`, `radius:5000`, `maxResultCount:20`); API key never present in any thrown error message.
- [x] 1.4 GREEN: `lib/features/gyms/data/places_nearby_search_service.dart` — implement `PlacesNearbySearchService` per `[AD-7]` mirroring `PlacesAutocompleteService`'s injection/error-split pattern.
- [x] 1.5 Quality gate (service+DTO): `flutter analyze lib test` 0 new issues, `dart format lib/features/gyms/domain/nearby_gym.dart lib/features/gyms/data/places_nearby_search_service.dart test/features/gyms/domain/nearby_gym_test.dart test/features/gyms/data/places_nearby_search_service_test.dart`, `flutter test test/features/gyms/domain/nearby_gym_test.dart test/features/gyms/data/places_nearby_search_service_test.dart` green.
- [x] 1.6 RED: `test/features/gyms/application/nearby_gyms_provider_test.dart` (new file, not `places_providers_test.dart` — kept the new provider's tests isolated from the existing Autocomplete-suite file) — build a call-counting fake `PlacesNearbySearchService` (increments a counter on `search()`); assert `nearbyGymsProvider(bucket)` fires the fake **exactly once** across N forced rebuilds of the same bucket (fire-once-per-open floor, `[AD-2]` layer 1, `[gym-places-search: cost-gated fetch]` scenario "Repeated rebuilds do not re-fetch").
- [x] 1.7 RED: same file — extend the call-counting assertion across a **simulated re-open within the same `ProviderContainer`** (`container.invalidate` on the `autoDispose` family entry — matches the real app's single root `ProviderScope`; a second separate `ProviderContainer` would have its own empty cache and not exercise the cache at all) requesting the **same geohash bucket within TTL**: still exactly 1 total call (cross-open TTL cache hit, `[AD-2]` layer 2, `[gym-places-search: cost-gated fetch]` scenario "Reopening the screen allows a new fetch" — verified TTL-hit path returns 0 extra calls, and a **different** bucket or **expired TTL** (via `nearbyGymsCacheProvider.overrideWithValue` pre-seeded with a past `fetchedAt`) triggers call #2).
- [x] 1.8 GREEN: `lib/features/gyms/application/places_providers.dart` — added `placesNearbySearchServiceProvider` (mirrors `placesAutocompleteServiceProvider`) and `nearbyGymsCacheProvider` (`keepAlive` by default, wraps `NearbyGymsCache`/`Map<String, _CachedNearby>` with `nearbyGymsCacheTtl` = 10min) per `[AD-9]` items 1-2.
- [x] 1.9 GREEN: same file — added `nearbyGymsProvider` (`FutureProvider.autoDispose.family<List<NearbyGym>, String>`) implementing the cache-first/fire-once logic that makes 1.6 and 1.7 pass, per `[AD-9]` item 3. Bucket string is decoded back to an approximate lat/lng center via a local `_decodeGeohashBucketCenter` (inverse of `geohash5`) since `searchNearby` needs real coordinates.
- [x] 1.10 Quality gate (nearby fetch + cache): `flutter analyze lib test` 0 new issues, `dart format` touched paths only, `flutter test test/features/gyms/application/nearby_gyms_provider_test.dart test/features/gyms/application/places_providers_test.dart` green — confirmed call-counting assertions (1.6, 1.7) pass.
- [x] 1.11 RED: `test/features/gyms/application/nearby_location_provider_test.dart` — `nearbyLocationProvider` (StateNotifier) exposes `setForTest(position)` and `setDeniedForTest()` seams; asserted: initial silent-check state (`AsyncData(null)`, `isPermissionDenied == false`, reading alone never checks); `setForTest(position)` transitions to granted-with-position; `setDeniedForTest()` transitions to not-granted; **no real `Geolocator` call occurs in any of these paths** (all 5 tests run under plain `test()` and complete instantly — would hang under the confirmed gotcha if the plugin channel fired).
- [x] 1.12 GREEN: `lib/features/gyms/application/places_providers.dart` — implemented `NearbyLocationNotifier`/`nearbyLocationProvider` per `[AD-9]` item 4 / `[AD-1]`. Design note: `build()` starts at neutral `AsyncData(null)` (like `AthleteLocationNotifier`) and performs NO Geolocator call — the silent check is a separate `checkSilently()` method the UI calls once on screen-open (Phase 2). This keeps merely constructing/reading the provider safe in ALL test contexts while still satisfying AD-1's "silent check first" as a capability. `requestPermission()` (escalation, rationale-sheet-gated) and `setForTest`/`setDeniedForTest` test seams also implemented.
- [x] 1.13 Quality gate (location provider): `flutter analyze lib test` 0 new issues, `dart format` touched paths only, `flutter test test/features/gyms/application/nearby_location_provider_test.dart` green — confirmed zero real-Geolocator invocations.
- [x] 1.14 Phase gate: `flutter analyze lib test` 0 NEW issues (33 pre-existing baseline), `dart format` touched paths only (full-repo format causes drift — not run on whole repo), full `flutter test` green. Committed as one work unit (tests + code together), on `feat/gym-selection-v2-data`.

## Phase 2: Screen Redesign (Slice 2 — PR 2)

Traceability: `[gym-selection-screen: pinned current gym]`, `[gym-selection-screen: no pinned card]`, `[gym-selection-screen: body switches on query state]`, `[gym-selection-screen: no-gym option persists]`, `[gym-selection-screen: selection updates screen]`, `[gym-places-search: nearby selection path]`, `[AD-1]`, `[AD-4]`, `[AD-5]`, `[AD-10]`, `[AD-11]`. Depends on Phase 1's providers (`nearbyGymsProvider`, `nearbyLocationProvider`).

- [x] 2.1 RED: `test/features/profile_setup/presentation/widgets/gym_search_box_test.dart` — extend with `emptyQueryContent` seam cases per `[AD-10]`: default (`null`) empty-query render is byte-for-byte the existing `SizedBox.shrink()` output; a non-null `emptyQueryContent` widget renders in its place when query is empty; non-empty query still shows Autocomplete results regardless of `emptyQueryContent`.
- [x] 2.2 GREEN: `lib/features/profile_setup/presentation/widgets/gym_search_box.dart` — add `final Widget? emptyQueryContent;` field, thread into `_SuggestionsList`, replace the empty-query short-circuit with `emptyQueryContent ?? const SizedBox.shrink()` per `[AD-10]`. No other lines touched.
- [x] 2.3 RED: `test/features/profile_setup/presentation/steps/step_2_gym_test.dart` — regression guard per design's onboarding-safety risk: existing suite still green unchanged, AND add an explicit assertion that `step_2_gym.dart`'s `GymSearchBox` instantiation has no `emptyQueryContent` argument / renders no nearby list / triggers **zero** `nearbyGymsProvider`/`nearbyLocationProvider` reads during onboarding (override both providers with call-counting fakes asserting 0 invocations). Passed immediately (GREEN on first run) — confirms task 2.4's isolation holds, no unintended coupling found.
- [x] 2.4 Verify (no GREEN needed): confirmed `lib/features/profile_setup/presentation/steps/step_2_gym.dart` requires no code change — it already constructs `GymSearchBox` without the new param. 2.3 passed on first run — no unexpected coupling, no fix needed.
- [x] 2.5 Quality gate (shared widget + onboarding regression): `flutter analyze lib test` 0 new issues, `dart format` touched paths only, `flutter test test/features/profile_setup/presentation/gym_search_box_test.dart test/features/profile_setup/presentation/steps/step_2_gym_test.dart` green.
- [x] 2.6 RED: `test/features/profile/presentation/widgets/pinned_current_gym_test.dart` (new) — pinned card renders resolved gym name via overridden `gymByIdProvider`; shows loading state while unresolved (`[gym-selection-screen: loading state]`); hidden entirely when `currentGymId` is null or `kNoGymId` (`[gym-selection-screen: no pinned card]`).
- [x] 2.7 GREEN: new widget `lib/features/profile/presentation/widgets/pinned_current_gym.dart` implementing the pinned card per `[AD-11]`, reusing `gymByIdProvider` + `gymDisplayNameFromGym`.
- [x] 2.8 RED: `test/features/profile/presentation/widgets/nearby_gyms_list_test.dart` (new) — override `nearbyGymsProvider`/`nearbyLocationProvider`, assert every state per design's state table: not-granted → "Activar ubicación" affordance; loading (escalation in flight) → spinner; fetch loading → `CircularProgressIndicator`; fetch error → retry affordance that invalidates `nearbyGymsProvider(bucket)`; empty (0 after dedup) → section hidden, no error text (`[gym-places-search: zero nearby results hides section]`); data → up to 8 rows with "a X km" haversine labels, current gym absent from rows (`[AD-5]` dedup); >8 remaining → "Ver más" reveals rest with **zero additional provider/service calls** (assert call count unchanged after tap).
- [x] 2.9 GREEN: new widget `lib/features/profile/presentation/widgets/nearby_gyms_list.dart` implementing all states from 2.8 per `[AD-4]`, `[AD-5]`, `[AD-6]` (haversine label), `[AD-1]` (opt-in affordance → rationale sheet → `requestPermission()`).
- [x] 2.10 RED: `test/features/profile/presentation/widgets/nearby_gyms_list_test.dart` — tap-to-select case per `[gym-places-search: nearby selection path]`: tapping a nearby row invokes the same `select(uid, placeId)` path as Autocomplete (mock/spy `selectGymActionProvider`), with no session token required and no error/degradation.
- [x] 2.11 GREEN: wired the nearby row tap in `nearby_gyms_list.dart` to `selectGymActionProvider.select(uid, placeId, useSessionToken: false)`. DEVIATION from the literal task text: `SelectGymAction.select()` unconditionally read `gymSearchSessionTokenProvider` (minting a real token) with no way to omit it — the design's "no change" claim (line 162) was inaccurate for a true no-token nearby flow per spec "A nearby-originated selection resolves without a session token". Added an optional `useSessionToken` param (default `true`, preserves Autocomplete's exact existing behavior byte-for-byte — verified by full regression run of `places_providers_test.dart`/`profile_gym_screen_test.dart`/`step_2_gym_test.dart`); nearby passes `false` so no token is minted, read, or sent, and `gymSearchSessionTokenProvider` is left untouched.
- [x] 2.12 Quality gate (pinned card + nearby list widgets): `flutter analyze lib test` 0 new issues, `dart format` touched paths only, `flutter test test/features/profile/presentation/widgets/pinned_current_gym_test.dart test/features/profile/presentation/widgets/nearby_gyms_list_test.dart` green.
- [ ] 2.13 RED: `test/features/profile/presentation/profile_gym_screen_test.dart` — extend with composition cases per `[gym-selection-screen]` spec: pinned card at top when `gymId` resolved, absent when null/`kNoGymId`; empty query shows nearby-list (as `emptyQueryContent`), non-empty query shows Autocomplete results, clearing restores nearby list; "No tengo gimnasio" visible at bottom across both query states; selecting a new gym (pinned-alt/nearby/search/no-gym) replaces the active selection in the UI.
- [ ] 2.14 GREEN: `lib/features/profile/presentation/profile_gym_screen.dart` — wire `PinnedCurrentGym` above `GymSearchBox`, pass `NearbyGymsList` as `emptyQueryContent`, preserve existing "No tengo gimnasio" and selection-highlight logic per `[AD-1]`, `[AD-11]`.
- [ ] 2.15 l10n: add es-AR strings ("Activar ubicación para ver gyms cercanos", "Ver más", nearby empty/error copy) to the app's l10n source; regenerate if the project uses codegen for l10n (check existing `l10n.yaml`/arb pattern before adding a codegen task).
- [ ] 2.16 Quality gate (screen composition): `flutter analyze lib test` 0 new issues, `dart format` touched paths only, `flutter test test/features/profile/presentation/profile_gym_screen_test.dart` green.
- [ ] 2.17 Phase gate: `flutter analyze lib test` 0 NEW issues (33 pre-existing baseline), `dart format` touched paths only, full `flutter test` green (confirm no regression in `step_2_gym_test.dart` or any onboarding suite). Commit as one work unit, target Phase 1's PR branch.

## Rules Applied

- Every GREEN task preceded by its RED task in the same slice — Strict TDD, no exceptions.
- No Cloud Function anywhere — resolution stays client-side per design's corrected spec delta; infra constraint confirmed.
- `nearbyLocationProvider` MUST expose `setForTest`/`setDeniedForTest`; no test in either slice may touch real `Geolocator` (known hang gotcha under `testWidgets`).
- Cost gating (the system's highest-impact risk) is verified twice: once at the provider layer (1.6/1.7, call-counting) and implicitly reinforced by the "Ver más" no-extra-call assertion (2.8).
- Onboarding isolation is verified explicitly (2.3) with a zero-invocation assertion on both new providers, not just "existing tests still pass."
- `dart format` scoped to touched paths only per this repo's known 62-file full-format drift gotcha.
- `flutter analyze lib test` baseline is 33 pre-existing issues; gate is 0 NEW issues, not 0 total.
- Work-unit commits: tests + implementation + l10n for a given task group committed together, not split, per delivery strategy.
- Docs check: no `docs/*.md` file references the gym-search flow's implementation details (`ProfileGymScreen`, `GymSearchBox`, `searchNearby`) — grep confirmed no doc-flip tasks needed.

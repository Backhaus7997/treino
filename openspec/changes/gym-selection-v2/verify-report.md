# Verify Report — gym-selection-v2 (re-verify, ship tip)

**Branch**: `feat/gym-selection-v2-search` (chain: `origin/main` → `feat/gym-selection-v2-data` → `feat/gym-selection-v2-ui` → `feat/gym-selection-v2-search`)
**Tip commit**: `995278a`
**Prior verify**: PASS WITH WARNINGS (engram #383, run against `-ui` tip) — CRITICAL-1 flagged, since fixed.
**Verdict**: **PASS WITH WARNINGS**

## Scope of this pass

Re-verification after the Phase 3 addendum (Text Search backend swap for typed search, AD-12; nearby-list render-cap removal, AD-13) and the CRITICAL-1 test fix. No `lib/` changes were made in this verification session — evidence only.

## Gates (live-run evidence, this session)

| Gate | Result |
|---|---|
| `flutter analyze lib test` | 33 issues, all pre-existing baseline, 0 new, none in touched files |
| `flutter test` (full suite) | 3194 passed, 49 skipped, 0 failed |
| 12 targeted gym-selection-v2 test files, standalone | 85/85 passing |
| Grep for dangling `PlacesAutocompleteService` / `placesAutocompleteServiceProvider` / `gymSearchSessionTokenProvider` / `placesSuggestionsProvider` in `lib/`+`test/` | Zero live references — all remaining hits are doc-comments/historical mentions of the retired name, not code |
| AI attribution in commits `2fadb59..995278a` | None found |

Diffstat `2fadb59..995278a` (Phase 3 + fix, `lib/` only): 10 files, 415 insertions / 326 deletions. No HEX color literals, no direct `PhosphorIcons.*` usage, no new hardcoded UI-facing strings introduced in this range.

## CRITICAL-1 resolution — confirmed genuine

`test/features/profile/presentation/profile_gym_screen_test.dart` (commit `995278a`) replaces the fixed `Stream.value(profile)` override with a `StreamController<UserProfile>.broadcast()`. The mocked `userRepo.update(...)` call is wired to push a new profile (`gymId: 'nearby-1'`) onto that stream, mirroring how the real Firestore-backed `userProfileProvider` re-emits after a write. After tap + `pumpAndSettle`, the test asserts both `find.text('Nearby Gym')` present AND `find.text('Current Gym')` absent — i.e. it proves `PinnedCurrentGym` re-renders from the updated `currentGymId`, not just that the repo write happened. This is not vacuous; it is a materially different assertion from the original test's write-only check. **CRITICAL-1 is resolved.**

## Focus area 1 — Phase 3 scenarios

### Text Search service shape (`lib/features/gyms/data/places_text_search_service.dart`)
- `POST places:searchText`, field mask `places.id,places.displayName,places.formattedAddress`, `X-Goog-Api-Key` + `Content-Type` headers — matches AD-12 exactly.
- Config error (`PlacesTextSearchConfigError`, empty key) vs runtime error (`PlacesTextSearchError`, non-200/network) correctly split; neither error message ever includes the key (verified by source read + `places_text_search_service_test.dart` assertions).
- `locationBias` is conditionally included only `if (biasLatitude != null && biasLongitude != null)` — omitted entirely (not null-valued) otherwise. Test asserts `body.containsKey('locationBias') == false` for the no-location case, matching the stricter assertion style the apply-progress "Learned" note called for.
- Maps to the existing `GymSuggestion` DTO — no new type, zero downstream changes. Confirmed.

### Debounce + min-3-chars + cache cost gating — call-counting test verified
`test/features/gyms/application/places_text_search_provider_test.dart`, group "debounce collapses rapid changes": simulates 5 progressively-longer partial queries (`q`, `qi`, `qiv`, `qivo`, `qivox`), switching the listened family entry on each "keystroke" (which triggers `autoDispose` teardown of superseded entries — the actual cancellation signal). Asserts `fake.callCount == 1` and `fake.queriesReceived == ['qivox']` — i.e. exactly one request for the settled query across all keystrokes. This is the call-counting proof required by the brief, not just an isolated single-query test.
Additional coverage: sub-3-char queries never call the service (0 calls, 2 cases); a 3-char query does call it; same-query-within-TTL is a cache hit (0 extra calls); different query text, different bias bucket (no-location vs biased, same query text), and expired TTL each independently trigger a second call. All 4(a-d) scenarios from the brief are covered with dedicated tests, all green.

### No-location → unbiased search still works
- Provider level: `gymSearchLocationBiasProvider.overrideWith((ref) async => null)` used across the debounce/cache tests; `_textSearchCacheKey` correctly buckets on empty string when `position == null`.
- Widget level: `gym_search_box_test.dart:281` — dedicated `'works without location permission — no bias, no crash'` test.

### Selection from search uses `useSessionToken: false`
`SelectGymAction.select()` default flipped `true`→`false` (`places_providers.dart:128`); the method body now hardcodes `sessionToken: null` in the `ResolveGymPlaceService.call` regardless of the parameter value — `useSessionToken` is effectively vestigial (kept only because `ResolveGymPlaceService.call` still accepts a nullable token and a future session-backed source isn't architecturally precluded, per the doc comment). Both callers (`step_2_gym.dart:50`, `profile_gym_screen.dart:50`) call `select(uid:, placeId:)` with no explicit `useSessionToken` argument, so both inherit the new `false` default — confirms the design's claim that the entire surface (typed search + nearby) is now session-token-free. `nearby_gyms_list.dart:90` explicitly passes `useSessionToken: false` too (redundant with the new default, but explicit and correct).

### `PlacesAutocompleteService` + session-token providers deletion — zero dangling references
Grep-confirmed (see Gates table). `lib/features/gyms/data/places_autocomplete_service.dart` and its test are deleted; `placesAutocompleteServiceProvider`, `gymSearchSessionTokenProvider`, `placesSuggestionsProvider` are removed from `places_providers.dart`. All remaining textual hits across `lib/`+`test/` are doc-comments referencing the retired name for historical/traceability context (e.g. "replaces the retired `PlacesAutocompleteService`"), not live code paths.

### Nearby list renders ALL fetched (no 8-cap, no "Ver más")
`nearby_gyms_list.dart` — `_kVisibleCap`, `_expanded` state, and the "Ver más" `TextButton` are gone; the `data` branch renders every deduped row directly in a `Column`. Test coverage is genuine, not relabeled: a 14-gym case (the exact device-testing scenario — user's gym at rank #14) and a full 20-gym case, both asserting `find.text('Ver más')` is absent (`nearby_gyms_list_test.dart:171-231`). A separate test confirms rendering more rows costs zero additional provider/service calls.

### Onboarding (profile-setup) still works with the new backend
`step_2_gym.dart`'s diff in the Phase 3 + fix range is doc-comment only (zero functional lines changed) — it still constructs `GymSearchBox` with no `emptyQueryContent`, inheriting the Text Search swap automatically via the shared `_SuggestionsList` internals (design's stated AD-12 guarantee). The onboarding-isolation regression guard (task 2.3, extended for Phase 3) is intact: `step_2_gym_test.dart:299-325` asserts zero `nearbyGymsProvider`/`nearbyLocationProvider` invocations during onboarding via a call-counting fake, `callCount == 0`. `gym_search_box_test.dart` and `step_2_gym_test.dart` were rewritten in place to mock `PlacesTextSearchService`/`placesTextSearchProvider` instead of the retired Autocomplete stack, all scenarios preserved.

## Focus area 2 — regression (Phase 1/2's 31 original scenarios)

All 12 targeted test files (spanning Phase 1 domain/data/application, Phase 2 widgets/composition, and Phase 3 rewrites) pass standalone: 85/85. Full suite is 3194 passed / 49 skipped / 0 failed, consistent with apply-progress's claimed net +5 tests vs Phase 1+2's 3189. No regression detected.

## Focus area 3 — full scenario → test coverage

| Spec scenario (capability) | Covering test | Status |
|---|---|---|
| Nearby list ranks by distance | `places_nearby_search_service_test.dart` (body/rankPreference) | PASS |
| Cost-gated fetch (fire-once, cross-open TTL) | `nearby_gyms_provider_test.dart` (call-counting) | PASS |
| No-location hides nearby, search unaffected | `nearby_gyms_list_test.dart` (not-granted case) + `gym_search_box_test.dart:281` | PASS |
| Zero nearby results hides section silently | `nearby_gyms_list_test.dart` (empty-after-dedup) | PASS |
| Nearby selection uses same path, no session token | `nearby_gyms_list_test.dart` (task 2.10 case) | PASS |
| Place Details resolves client-side, cache-first | pre-existing `resolve_gym_place_service_test.dart` (untouched, doc-comment diff only) | PASS |
| Nearby-originated selection resolves without session token | `nearby_gyms_list_test.dart` + `places_providers_test.dart` | PASS |
| Soft gym-type check (unchanged invariant) | pre-existing coverage, untouched | PASS |
| Pinned card shown/loading/hidden | `pinned_current_gym_test.dart` | PASS |
| Body switches nearby ↔ search on query state | `profile_gym_screen_test.dart` composition group | PASS |
| No-gym option persists across states | `profile_gym_screen_test.dart` | PASS |
| Selecting new gym replaces active selection in UI | `profile_gym_screen_test.dart` (995278a fix) | PASS — CRITICAL-1 resolved |
| Selection persists across app restart | pre-existing coverage, untouched | PASS |
| **Phase 3**: Typed search via Text Search, closest/relevant ranking | `places_text_search_service_test.dart` + `gym_search_box_test.dart` | PASS |
| **Phase 3**: Typed search debounced + cost-gated (call-counting) | `places_text_search_provider_test.dart` (debounce-collapse group) | PASS |
| **Phase 3**: Repeat query within TTL doesn't re-fetch | `places_text_search_provider_test.dart` (cache group) | PASS |
| **Phase 3**: Typed search works with no location | `places_text_search_service_test.dart` (`containsKey` assertion) + `gym_search_box_test.dart:281` | PASS |
| **Phase 3**: Typed-search selection needs no session token | `places_providers_test.dart` + `profile_gym_screen_test.dart` | PASS |
| **Phase 3**: Nearby renders every fetched result, no cap | `nearby_gyms_list_test.dart` (14-gym + 20-gym cases) | PASS |

## Findings

### CRITICAL
None. CRITICAL-1 from the prior verify is resolved (see above).

### WARNING

**W-1 (new, this pass)**: `openspec/changes/gym-selection-v2/specs/gym-selection-screen/spec.md` was NOT amended by the Phase 3 addendum and still references the retired backend by name in 3 places (lines 39, 46, 52 — "Autocomplete search results"). The underlying behavior contract (query-state-driven body switching between nearby list and search results) is correctly implemented and tested regardless of which backend powers the search — this is spec-doc staleness, not a functional gap. Same class of issue as the prior verify's WARNING-2 (design.md line 162 staleness, since fixed by the AD-12 addendum text). Recommend a small spec patch (s/Autocomplete/Text Search/ or genericize to "search results") before archive.

**W-2 (carried forward, unresolved)**: Prior verify's WARNING-2 — design.md line 162's original "nearby tap reuses select(uid, placeId), no change" claim is now doubly stale: not only did `useSessionToken` become a real (if now-default) optional param as WARNING-2 originally noted, but AD-12 subsequently made `sessionToken: null` unconditional inside `select()`, so `useSessionToken` itself is now vestigial. This is documented candidly in the current code's own doc comment (`places_providers.dart:116-124`), so the deviation is self-disclosed and low-risk, but the original design.md line 162 was never patched. Recommend folding into the same doc pass as W-1.

**W-3 (new, this pass, out-of-scope hygiene)**: Untracked file `scripts/places.local.json` in the working tree contains what appear to be live Google API keys and is NOT covered by any `.gitignore` pattern (`.gitignore` has a specific `scripts/sa-key.json` entry but no generic `*.local.json`/`scripts/*.local.json` rule). This predates this branch's diff and was not introduced by any gym-selection-v2 commit, so it does not block this change, but it is a live secrets-leak risk if `git add -A`/`git add .` is ever run in this tree. Recommend adding a `.gitignore` rule for `scripts/*.local.json` as a follow-up, unrelated to this SDD change.

### SUGGESTION

**S-1**: `placesTextSearchProvider`'s `disposed` supersession check (`places_providers.dart:522-531`) is only re-checked immediately after the debounce `Future.delayed` wait — not after the subsequent `gymSearchLocationBiasProvider.future` await or the `service.search()` network call. A very-late supersession (user keeps typing while a network call from an earlier settled query is still in flight) won't abort that in-flight request; it will complete, get cached, and simply have no listener by the time it resolves. This is a minor cost/latency nit, not a correctness bug (Riverpod's `autoDispose` already prevents any UI effect from the stale future), and is consistent with the existing `nearbyGymsProvider` pattern this mirrors. No action required; noting for awareness only.

**S-2**: `gym_search_box.dart:178`'s `'Sin resultados para "$query"'` string is hardcoded Spanish rather than routed through `AppL10n`. Confirmed via range-scoped diff that this predates the Phase 3 + fix window (`2fadb59..995278a` shows no touch to this line) — not introduced by this change, so not flagged as a regression, but noted since l10n discipline was a named focus area for this pass.

**S-3 (carried forward from prior verify, still valid)**: `nearbyLocationProvider` performing no permission check on construction (only via UI-driven `checkSilently()`) remains a safer-than-literal-wording choice satisfying AD-1's intent. No action needed.

**S-4 (carried forward)**: The manual `disposed`/`ref.onDispose` flag workaround for riverpod 2.6.1's missing `ref.mounted` (documented gotcha, used identically in both `nearbyGymsProvider`'s pattern and the new `placesTextSearchProvider`) is sound: `ref.onDispose` fires synchronously on teardown, and checking the flag after each `await` gap correctly detects supersession before proceeding to the next side-effecting step. Confirmed via source read and the dedicated debounce-collapse test.

## AD compliance

AD-1 through AD-11 (previously verified) — no regression, all still hold per this session's source re-read of the touched files. AD-12 (Text Search swap) and AD-13 (render-all) — both fully implemented as specified, source-confirmed against design.md's exact body/header/field-mask/cache-key contracts, and covered by dedicated call-counting/render tests as detailed above.

## Task truthfulness spot-check

All 47/47 tasks in `tasks.md` are checked `[x]`. Spot-checked Phase 3 tasks 3.1–3.16 against actual commits/diffs/test files — each GREEN task's claimed file and behavior matches the corresponding source; each RED task's claimed test file and scenario matches the actual test content (verified directly, not just by task-list text). No falsely-checked tasks found.

## Where (evidence files)

- `openspec/changes/gym-selection-v2/specs/gym-places-search/spec.md`, `specs/gym-selection-screen/spec.md`, `design.md` (AD-12/AD-13 addendum), `tasks.md`
- `lib/features/gyms/data/places_text_search_service.dart` (new)
- `lib/features/gyms/application/places_providers.dart` (`placesTextSearchProvider`, `TextSearchCache`, `SelectGymAction.select`)
- `lib/features/profile_setup/presentation/widgets/gym_search_box.dart`
- `lib/features/profile/presentation/widgets/nearby_gyms_list.dart`
- `lib/features/profile/presentation/profile_gym_screen.dart`, `lib/features/profile_setup/presentation/steps/step_2_gym.dart`
- `test/features/gyms/data/places_text_search_service_test.dart`, `test/features/gyms/application/places_text_search_provider_test.dart`
- `test/features/profile/presentation/profile_gym_screen_test.dart` (CRITICAL-1 fix at `995278a`)
- `test/features/profile/presentation/widgets/nearby_gyms_list_test.dart` (AD-13 coverage)

## Next

Recommend `sdd-archive`. No CRITICAL issues block archive. W-1/W-2 (spec/design doc staleness) and W-3 (unrelated repo hygiene) can be folded into the archive pass as follow-up notes, or patched in a small doc-only commit first if the user prefers a clean spec trail before archiving.

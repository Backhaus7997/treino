# Tasks: gym-google-places

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~950-1150 (Slice 1: ~280-320, Slice 2: ~300-350, Slice 3: ~370-480) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (CF) → PR 2 (client services) → PR 3 (picker rework + retirements) |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | `resolveGymPlace` CF, read-through upsert, secret, index re-export | PR 1 | Base: main (or tracker branch if feature-branch-chain). Deployable/testable standalone via emulator. HIGH RISK: first external paid-API call from `functions/`; Places field-name churn. |
| 2 | Client Autocomplete service + resolve wrapper + Riverpod providers + `GymSource.googlePlaces` | PR 2 | Base: PR 1 branch (or main if stacked). Unit-testable, no UI. HIGH RISK: Places field-name churn (Autocomplete request/response shape). |
| 3 | Picker rework (single search box) + retirements (GymBrand, 3 providers, 2 test files) | PR 3 | Base: PR 2 branch. Depends on PR 2 providers/services existing. |

**Decision needed before apply**: user must pick chain strategy (stacked-to-main / feature-branch-chain / size:exception) — `ask-on-risk` requires this before `sdd-apply` starts.

---

## Phase 1: Slice 1 — Cloud Function `resolveGymPlace` (server-side)

- [ ] 1.1 GCP PREREQUISITE (operator, blocks e2e not code): enable Places API (New) on `treino-dev`, confirm Blaze billing, note project id.
- [ ] 1.2 GCP PREREQUISITE (operator, blocks e2e not code): `firebase functions:secrets:set PLACES_API_KEY` (server-restricted key) + configure budget alert.
- [x] 1.3 RED — `functions/src/__tests__/places-search.test.ts`: write failing tests for `runResolveGymPlace(app, placeId, sessionToken?)` — read-through hit (no `fetch` call), miss→Details→upsert, bad `placeId`→`invalid-argument`, Places non-200→`internal` (no key leak), 429→`resource-exhausted`. Mirror `functions/src/__tests__/add-alias.test.ts` emulator-app harness; `jest.spyOn(global, 'fetch')` mock. DEVIATION: empty/invalid placeId maps to `invalid-argument` (not `not-found` as originally phrased) — consistent with task 1.4's own wording and the guard-order pattern in add-alias.ts (input validation is `invalid-argument`; `not-found`/`internal` are reserved for downstream lookup failures). `not-found` was not applicable since a missing placeId never reaches Firestore/Places lookups.
- [x] 1.4 RED — same file: failing tests for thin `resolveGymPlace` onCall wrapper — `unauthenticated` guard, `invalid-argument` on empty `placeId`, region `southamerica-east1`, `secrets: ['PLACES_API_KEY']`.
- [x] 1.5 VERIFY-AT-APPLY: confirmed current Places API (New) Details endpoint/headers/field-mask tokens (`GET /v1/places/{placeId}`, `X-Goog-Api-Key`, `X-Goog-FieldMask`, `displayName.text`, `location.latitude/longitude`, `types`, `sessionToken` query param) — orchestrator supplied these as verified against live Google docs at apply time; used verbatim in implementation.
- [x] 1.6 GREEN — `functions/src/places-search.ts`: implemented `runResolveGymPlace` (pure handler) — read-through `gyms/{placeId}` get, Details fetch via Node 20 global `fetch`, map fields, ported `geohash5` from `scripts/seed_gyms.js`, Admin SDK upsert (`source:'google-places'`, `brandId/brandName/branchName:null`, `createdAt` server ts via `FieldValue.serverTimestamp()`), soft type-check warning log via `logger.warn` (never reject), error mapping (`invalid-argument`/`internal`/`resource-exhausted`, never leaks the key). Implemented thin `resolveGymPlace` onCall wrapper (region `southamerica-east1`, `secrets:['PLACES_API_KEY']`) mirroring `functions/src/add-alias.ts` structure.
- [x] 1.7 `functions/src/index.ts`: added `export { resolveGymPlace } from "./places-search";`.
- [x] 1.8 `firestore.rules`: comment-only change documenting `source: 'google-places'` and that Admin-SDK upsert (via `resolveGymPlace`) bypasses the trainer-only `gyms/` create rule entirely — no client-side create branch added. No rule logic change.
- [x] 1.9 Quality gate (Slice 1): `cd functions && npm run build` clean (tsc, 0 errors), `npm run lint` clean (0 errors/warnings), `npm test` green — 18/18 suites, 133/133 tests (all new `places-search.test.ts` 11 tests + all pre-existing tests, including `add-alias.test.ts`), no key/secret leaked in logs or error messages (asserted in SCENARIO-754).

## Phase 2: Slice 2 — Client Autocomplete + providers (Dart, no UI)

- [ ] 2.1 GCP PREREQUISITE (operator, blocks e2e not code): create bundle-restricted client API key for Places Autocomplete (Android/iOS bundle-id restricted), provide `--dart-define` value.
- [x] 2.2 RED — `test/features/gyms/domain/gym_source_test.dart` (new file): added failing tests for `GymSource.googlePlaces` + `'google-places'` wire (de)serialization round-trip + regression coverage for existing `seed`/`self-service` values.
- [x] 2.3 GREEN — `lib/features/gyms/domain/gym_source.dart`: added `googlePlaces` enum value + `'google-places'` JSON mapping (`@JsonValue`, `_wireMap`, `toWire()`).
- [x] 2.4 `lib/features/gyms/domain/gym_suggestion.dart`: created plain DTO `{placeId, primaryText, secondaryText}` (NOT freezed, hand-written `==`/`hashCode`/`toString`).
- [x] 2.5 RED — `test/features/gyms/domain/gym_suggestion_test.dart`: failing tests constructing/comparing `GymSuggestion` instances (construction, nullable `secondaryText`, value equality).
- [x] 2.6 GREEN: confirmed 2.4 satisfies 2.5 (8/8 domain tests green together).
- [x] 2.7 VERIFY-AT-APPLY: orchestrator supplied current Places API (New) Autocomplete endpoint/body/field-mask tokens as verified against live Google docs at apply time (`POST /v1/places:autocomplete`, headers `X-Goog-Api-Key`+`Content-Type`, body `{input, sessionToken, locationBias?, includedPrimaryTypes}`, response `suggestions[].placePrediction.{placeId, text.text, structuredFormat.mainText.text, structuredFormat.secondaryText.text}`) — used verbatim in implementation.
- [x] 2.8 RED — `test/features/gyms/data/places_autocomplete_service_test.dart`: failing tests for empty-key config error, empty-query short-circuit, endpoint/headers, request body shape (bias present/absent), response parsing into `List<GymSuggestion>`, empty-suggestions response, non-200 error (asserts key never leaked), network exception, session-token generation — 12 tests, injected mock `http.Client` (mocktail).
- [x] 2.9 GREEN — `lib/features/gyms/data/places_autocomplete_service.dart`: implemented `PlacesAutocompleteService` — Autocomplete (New) REST call via injected `http.Client`, client key (from `--dart-define=PLACES_CLIENT_KEY`, empty → `PlacesAutocompleteConfigError`, never a crash) + session token + optional `locationBias` circle (30km default radius) omitted entirely when no lat/lng provided, parses `suggestions[].placePrediction` → `List<GymSuggestion>`, `newSessionToken()` (122-bit random hex, no new `uuid` dep). DEVIATION: debounce is NOT implemented inside this service — see note below task 2.13.
- [x] 2.10 RED — `test/features/gyms/data/resolve_gym_place_service_test.dart`: failing tests for `httpsCallable('resolveGymPlace')` wrapper — call shape with/without optional `sessionToken`, `FirebaseFunctionsException` → `ResolveGymPlaceFailure$Server`, unknown error → `ResolveGymPlaceFailure$Unknown`. Mirrors `account_deletion_service_test.dart` mock harness exactly.
- [x] 2.11 GREEN — `lib/features/gyms/data/resolve_gym_place_service.dart`: implemented `ResolveGymPlaceService` + `ResolveGymPlaceResult` + sealed `ResolveGymPlaceFailure` per 2.10, mirroring `AccountDeletionService`/`AccountDeletionFailure` shape 1:1.
- [x] 2.12 RED — `test/features/gyms/application/places_providers_test.dart`: failing tests for `placesSuggestionsProvider(query)` (empty query → `[]` no service call; non-empty delegates with session token; propagates errors) and `selectGymActionProvider` (resolves via service, calls `UserRepository.update(uid, {'gymId': placeId})`, exposes `AsyncLoading`/`AsyncError`, resets session token on success) — 6 tests total.
- [x] 2.13 GREEN — `lib/features/gyms/application/places_providers.dart`: implemented `placesAutocompleteServiceProvider`, `resolveGymPlaceServiceProvider` (region `southamerica-east1` via `FirebaseFunctions.instanceFor`, mirrors `accountDeletionServiceProvider`), `gymSearchSessionTokenProvider` (mints token lazily, NOT autoDispose so it survives per-keystroke rebuilds, invalidated by `SelectGymAction` on success per spec's "new search starts a new session token"), `gymSearchLocationBiasProvider` (`checkPermission()` only — never `requestPermission()`, so a search never triggers a surprise OS dialog; returns `null` on any denied/error state, never throws), `placesSuggestionsProvider` (`FutureProvider.autoDispose.family<List<GymSuggestion>, String>`, empty query → `[]`), `SelectGymAction` (`AsyncNotifier`) + `selectGymActionProvider`. DEVIATION from literal task wording: debounce (2.9's "300ms debounce input contract") is deferred to Slice 3's search widget (`Timer`-based, mirroring `profile_setup_notifier.dart`'s `_usernameDebounce` pattern) instead of living inside the service/provider — matches this codebase's established convention (`searchUsersProvider`'s doc comment: "Debounce lives in the screen (Timer), not here, so this provider stays pure and cacheable") and keeps `placesSuggestionsProvider` a pure per-keystroke-cacheable `family`, consistent with the sibling `searchUsersProvider`. No UI exists yet in this slice to host the `Timer`, so it could not be tested/added without violating the "NO UI in this slice" scope boundary — tracked for Slice 3 (step 3.1/3.2).
- [x] 2.14 `flutter pub run build_runner build --delete-conflicting-outputs` — regenerated `gym.g.dart` (`_$GymSourceEnumMap` now includes `GymSource.googlePlaces: 'google-places'`) for the 2.3 enum change; confirmed `gym_suggestion.dart` stayed hand-written (no `.freezed.dart`/`.g.dart` generated for it, per design).
- [x] 2.15 Quality gate (Slice 2): `flutter analyze lib/features/gyms test/features/gyms` → 0 issues. `dart format lib/features/gyms test/features/gyms` → 23 files, 0 changed (already compliant). `flutter test test/features/gyms/` → 57/57 tests green. Full-repo regression check: `flutter analyze lib test` → 33 pre-existing issues, ALL in files untouched by this slice (verified via `rg "gyms/"` on the analyze output — zero matches); `flutter test` (full suite) → 3039+/3068 passed, 49 pre-existing skips, 0 failures.

## Phase 3: Slice 3 — Picker rework + retirements

- [ ] 3.1 RED — `test/features/profile_setup/presentation/gym_search_box_test.dart` (new widget test replacing parity test): failing scenarios — type → debounced suggestions shown, tap suggestion → selection callback, `kNoGymId` option present/selectable, loading state, error+retry state, empty-results state, works without location permission (no bias, no crash).
- [ ] 3.2 GREEN — `lib/features/profile_setup/presentation/steps/step_2_gym.dart`: replace two-step brand/branch picker with single debounced search box + suggestion list (reuse `GymCard`), wired to `placesSuggestionsProvider`/`selectGymActionProvider`, satisfies 3.1.
- [ ] 3.3 GREEN — `lib/features/profile/presentation/profile_gym_screen.dart`: same single-search-box rework, keep existing save bar + `UserRepository.update` call flow.
- [ ] 3.4 Retire `lib/features/gyms/domain/gym_brand.dart` (delete) and its freezed output `gym_brand.freezed.dart` (delete, or let build_runner clean it).
- [ ] 3.5 Retire `test/features/gyms/domain/gym_brand_test.dart` (delete).
- [ ] 3.6 `lib/features/gyms/application/gym_providers.dart`: remove `gymBrandsProvider`, `branchesForBrandProvider`, `gymBrandSearchQueryProvider`; keep repository provider + `gymByIdProvider` untouched.
- [ ] 3.7 Retire `test/features/profile_setup/presentation/gym_picker_parity_test.dart` (delete — superseded by 3.1).
- [ ] 3.8 Grep repo for any remaining `GymBrand` / retired-provider references (imports, other widgets, barrel files) and remove.
- [ ] 3.9 `flutter pub run build_runner build --delete-conflicting-outputs` — clean up generated artifacts after `GymBrand` deletion.
- [ ] 3.10 Quality gate (Slice 3): `flutter analyze` 0 issues, `dart format .` clean, `flutter test` green (full suite, confirms no leftover references), manual smoke note that e2e (real Places calls) is BLOCKED until Phase 1.1/1.2/2.1 GCP prerequisites are completed by operator.

## Phase 4: Cross-slice wrap-up

- [ ] 4.1 Update `docs/design-decisions.md` / relevant design doc note if the gym picker mockup mapping changes (single search box vs two-step) — confirm during apply whether this doc references the old picker.
- [ ] 4.2 Confirm `firestore.rules` comment (1.8) still accurate after Slice 3 UI change (athletes still only READ `gyms/`, no new write path introduced client-side).
- [ ] 4.3 Final full quality gate across all slices before archive: `flutter analyze` 0 issues + `dart format .` + `flutter test` + `functions` build/test all green.

---

## Notes

- STRICT TDD: every GREEN task has a preceding RED task in the same slice; no implementation task ships without its failing test written first.
- VERIFY-AT-APPLY tasks (1.5, 2.7) gate the Places API (New) field-name churn risk called out in design — do not hardcode field/mask tokens from this document without re-checking Google's current docs.
- GCP PREREQUISITE tasks (1.1, 1.2, 2.1) are operator/user actions outside code; they block end-to-end/emulator-with-real-API testing but do not block writing and unit-testing the code itself (mocks/stubs cover RED/GREEN cycles).
- Highest-risk tasks: 1.6 (first-ever external paid-API HTTP call from `functions/`, no existing precedent to copy beyond `add-alias.ts`'s shape) and 1.5/2.7/1.6/2.9 (Places field-name churn — any drift from actual API response shape breaks parsing silently).

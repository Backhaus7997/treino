# Tasks: Gyms Foundation (two-level brand→sucursal catalog)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~1450-1650 total (4 slices) |
| 400-line budget risk | High (overall) — each slice individually Low-Med |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 → PR 2 → PR 3 (parallel-safe with PR2) → PR 4 |
| Delivery strategy | ask-on-risk (orchestrator default; confirm with user) |
| Chain strategy | pending (ask user: stacked-to-main vs feature-branch-chain) |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Gym model + brand fields + seed rewrite | PR 1 | Base: tracker/main. ~350-400 LOC. Foundation for 2 and 3. |
| 2 | Brand grouping + two-step picker UI | PR 2 | Base: PR 1 branch. ~350-400 LOC. Independent of PR 3. |
| 3 | Name resolution (gymName denorm + 7 call sites) | PR 3 | Base: PR 1 branch (parallel to PR 2). ~350-400 LOC. Highest risk task inside. |
| 4 | Legacy id + gymName backfills (dev-first) | PR 4 | Base: PR 2 + PR 3 merged. ~150-200 LOC. Touches prod data path — verify dev counts first. |

Dependency: 1 → (2 ∥ 3) → 4.

---

## Phase 1: Gym Model + Brand Fields + Seed (PR 1)

Start: no dependency (first slice). End: `Gym` model decodes old+new docs, legacy model removed, seed script produces grouped brand/branch docs.

- [x] 1.1 (RED) Write test: `Gym.fromJson` decodes doc WITH `brandId`/`brandName`/`branchName` (spec req 1, 3) — `test/features/gyms/domain/gym_test.dart`
- [x] 1.2 (RED) Write test: `Gym.fromJson` decodes OLD doc WITHOUT brand fields (backward-compat, nullable) — same file
- [x] 1.3 (RED) Write test: `Gym.fromJson` still requires `lat`/`lng`/`geohash` (unchanged) — same file
- [x] 1.4 (GREEN) Add `String? brandId`, `String? brandName`, `String? branchName` to `lib/features/gyms/domain/gym.dart` (freezed, nullable) — also added optional `String? city`/`String? province` per design's file-change table, with matching RED/GREEN decode tests
- [x] 1.5 Regenerate: `dart run build_runner build --delete-conflicting-outputs`
- [x] 1.6 **PARTIAL — see deviation note below.** Re-homed `kNoGymId` constant into `lib/features/gyms/domain/gym.dart`. Did NOT delete legacy `lib/features/profile_setup/domain/gym.dart` model — its `Gym` class is still the return type of `filteredGymsProvider`/`_kHardcodedGyms` in `profile_setup_providers.dart`, which Phase 2 (task 2.6) explicitly owns deleting. Deleting the legacy model now would break that file before Phase 2 lands.
- [x] 1.7 Updated all `kNoGymId` imports across codebase to new location (`check_in_providers.dart`, `feed/domain/gym_name.dart`, `profile_setup_notifier.dart`, `step_2_gym.dart`, `profile_gym_screen.dart`, plus `test/features/check_in/application/check_in_no_gym_sentinel_test.dart`)
- [x] 1.8 (RED) Write test: `GymBrand.groupFrom` groups correctly (multi-branch count, single-branch `singleBranchGymId`, null `brandId` fallback to `id`) — `test/features/gyms/domain/gym_brand_test.dart`
- [x] 1.9 (GREEN) Create `lib/features/gyms/domain/gym_brand.dart` — `@freezed GymBrand { brandId, brandName, branchCount, singleBranchGymId? }`, no json (pure view model), plus a static `groupFrom(List<Gym>)` helper (pure Dart grouping logic; the *provider* wiring around it is Phase 2's `gymBrandsProvider`, task 2.3)
- [x] 1.10 Regenerate freezed for `gym_brand.dart`
- [x] 1.11 Rewrote `scripts/seed_gyms.js`: grouped by brand→branches, added `brandId`/`brandName`/`branchName`/`city`/`province`/`source:'seed'` per doc (22 docs total, 9 brands), KEPT existing Buenos Aires (CABA/GBA) gyms, ADDED Córdoba Capital gyms, chain branches across cities share `brandId`, independent gyms are single-branch brands. Added `smart-fit-palermo` (under SmartFit) and `sportclub-belgrano` (under SportClub) as new real sucursal docs — the two legacy hardcoded ids without a prior catalog match. `megatlon-recoleta` kept its id, gained brand fields, no new doc (1:1, matches Phase 4's plan).
- [ ] 1.12 **BLOCKED — see deviation note below.** (RED) Write test: `feed/domain/gym_name.dart` fallback removed — NOT done, deletion breaks 7 live call sites that Phase 3 (tasks 3.9-3.10) is responsible for migrating to real name resolution first.
- [ ] 1.13 **BLOCKED — same reason as 1.12.** (GREEN) Delete `lib/features/feed/domain/gym_name.dart` — deferred to Phase 3, must happen together with/after the 7 call-site migrations.
- [x] 1.14 Quality gate: `flutter analyze` 0 issues (touched files), `dart format .`, `flutter test` green for this slice (see apply-progress for full command output)

### Deviations from tasks.md / design.md (flagged, not silent)

1. **Legacy `Gym` model NOT deleted (task 1.6).** `design.md`'s PR-slices section groups "delete legacy model" into PR 1, but its own file-changes table (and task 2.6) assigns deleting `_kHardcodedGyms`/`filteredGymsProvider` — the legacy `Gym`'s only remaining consumer — to Phase 2. Deleting the class in Phase 1 would have broken `profile_setup_providers.dart` and, transitively, `step_2_gym.dart`/`profile_gym_screen.dart` (both still read `filteredGymsProvider` until Phase 2's two-step picker rewrite lands). Resolved by re-homing only `kNoGymId` now and leaving the legacy `Gym` class + its two consumers alone until Phase 2 replaces them atomically.
2. **`gym_name.dart` NOT deleted (tasks 1.12-1.13).** Same class of issue: `_kGymNames`/`gymNameFromId` are still imported by 7 live call sites (`feed_screen.dart`, `user_search_result_tile.dart`, `friend_request_inbox_tile.dart`, `session_player_screen.dart`, `profile_cuenta_section.dart`, `profile_avatar_card.dart`, `public_profile_hero.dart`) that Phase 3 (tasks 3.9-3.10) is explicitly responsible for migrating to `profile.gymName`/`gymByIdProvider`. Deleting the file now would have broken all 7. Left untouched except for its `kNoGymId` import path, which was fixed to the new location so it keeps compiling.
3. **`GymBrand` grouping logic added as a static `groupFrom` helper, not just a bare data class.** Task 1.8 says "GymBrand groups correctly," which implies grouping behavior exists somewhere; task set 2.1-2.4 (Phase 2) is the *Riverpod provider* wrapping around a grouping algorithm (`gymBrandsProvider`), not the algorithm itself. Interpreted "groups correctly" as requiring the pure algorithm in Phase 1, with Phase 2 only adding the `Provider.autoDispose` wiring on top.
4. **Added optional `city`/`province` fields to `Gym`** even though tasks.md's Phase 1 task list doesn't call them out explicitly — the user's Slice-1 scope instructions listed them as already-existing fields to preserve, and design.md's file-changes table lists them under the same `gym.dart` edit. Added with backward-compat decode tests to keep the seed script (which now writes them) and the model in sync.

## Phase 2: Brand Grouping Providers + Two-Step Picker (PR 2)

Start: depends on Phase 1 (`Gym`, `GymBrand` models exist). End: athlete can browse brands, drill into branches, single-branch brands skip step 2, in both onboarding and profile-edit flows.

- [x] 2.1 (RED) Write test: `gymBrandsProvider` groups `gymsProvider` results by `(brandId ?? id)` correctly — `test/features/gyms/application/gym_providers_test.dart`
- [x] 2.2 (RED) Write test: `branchesForBrandProvider.family(brandId)` returns only that brand's sucursales
- [x] 2.3 (GREEN) Add `gymBrandsProvider` (`FutureProvider.autoDispose<List<GymBrand>>`) to `lib/features/gyms/application/gym_providers.dart`
- [x] 2.4 (GREEN) Add `branchesForBrandProvider` (`FutureProvider.autoDispose.family<List<Gym>, String>`) to same file
- [x] 2.5 (GREEN) Add `gymBrandSearchQueryProvider` (`StateProvider.autoDispose<String>`) — shared search state for both steps
- [x] 2.6 Delete `lib/features/profile_setup/application/profile_setup_providers.dart` legacy: `_kHardcodedGyms`, `gymSearchQueryProvider`, `filteredGymsProvider`. **Also deleted the legacy `profile_setup/domain/gym.dart` model + its generated `.freezed.dart`** — after this migration it had zero remaining consumers (previously only `filteredGymsProvider`), so it was safe to remove in this same unit per design.md's PR-slices intent.
- [x] 2.7 (RED) Write widget test: two-step picker — browse brands without location permission (spec scenario) — `test/features/profile_setup/presentation/steps/step_2_gym_test.dart`
- [x] 2.8 (RED) Write widget test: pick chain brand → shows branch list → pick branch → resolves sucursal id
- [x] 2.9 (RED) Write widget test: pick independent (single-branch) brand → SKIPS step 2 → resolves lone sucursal directly
- [x] 2.10 (RED) Write widget test: search by brand name filters step 1 list
- [x] 2.11 (RED) Write widget test: error + retry mirrors `_GymsSection` pattern (`ref.invalidate(gymsProvider)`)
- [x] 2.12 (GREEN) Convert `step_2_gym.dart` from `ConsumerWidget` to `ConsumerStatefulWidget`; add `_selectedBrandId` local state; implement two-step UI (brand list → branch list → back nav)
- [x] 2.13 (GREEN) Convert `profile_gym_screen.dart` similarly: `_selectedBrandId`, `_pendingGymId` local state; back-from-branch returns to brand list (header back button doubles as brand-list-back when in step 2)
- [x] 2.14 Verify "no gym" option still present outside the two-step flow in both screens
- [x] 2.15 (RED) Write widget test: onboarding vs profile-edit parity (ADR-PSR-011) — same two-step behavior in both entry points — `test/features/profile_setup/presentation/gym_picker_parity_test.dart`
- [x] 2.16 Quality gate: `flutter analyze` 0 issues, `dart format .`, `flutter test` green for this slice

## Phase 3: Gym Name Resolution + Denormalization (PR 3, parallel to PR 2)

Start: depends on Phase 1 only (not Phase 2). End: `UserPublicProfile.gymName` dual-written with composed brand-branch label at save time; all 7 call sites resolve real names; safe fallback for unresolvable ids.

- [ ] 3.1 (RED) Write test: `UserPublicProfile.fromJson`/`toJson` round-trips new `gymName` field — `test/features/profile/domain/user_public_profile_test.dart`
- [ ] 3.2 (GREEN) Add `String? gymName` to `lib/features/profile/domain/user_public_profile.dart`
- [ ] 3.3 Regenerate: `dart run build_runner build --delete-conflicting-outputs`
- [ ] 3.4 **[HIGHEST RISK]** (RED) Write test using `fake_cloud_firestore`: `UserRepository.update({'gymId': validId})` dual-writes `gymName` = resolved sucursal's composed name into `users/{uid}` AND `userPublicProfiles/{uid}` — `test/features/profile/data/user_repository_test.dart`
- [ ] 3.5 **[HIGHEST RISK]** (RED) Write test: `UserRepository.update({'gymId': kNoGymId})` writes `gymName: null` (no resolution attempted)
- [ ] 3.6 **[HIGHEST RISK]** (RED) Write test: `UserRepository.update({'gymId': unknownId})` does not crash, writes safe fallback (null/empty), async resolution failure handled gracefully
- [ ] 3.7 **[HIGHEST RISK]** (GREEN) Inject `GymRepository` into `UserRepository`; in `update()`, when `partial.containsKey('gymId')`, resolve `gym.name` async via `getById` and add `gymName` to `_publicFields` write payload (mirrors `CheckIn.gymName` pattern)
- [ ] 3.8 (RED) Write test: name fallback for unknown/no-gym/null id renders empty (replaces deleted `gym_name_test.dart`) — covers spec req 3
- [ ] 3.9 (GREEN) Update 7 call sites to resolve real names — LIST contexts read `profile.gymName` denormalized field: `feed_screen.dart`, `user_search_result_tile.dart`, `friend_request_inbox_tile.dart`
- [ ] 3.10 (GREEN) Update DETAIL contexts to use `gymByIdProvider` (Riverpod-cached), composing label from resolved `Gym`: `session_player_screen.dart`, `profile_cuenta_section.dart`, `profile_avatar_card.dart`, `public_profile_hero.dart`
- [ ] 3.11 (RED) Write test: chain gym displays "Brand - Branch"; independent gym displays brand name only (composed label logic) — cover in provider or widget test per call site touched
- [ ] 3.12 Quality gate: `flutter analyze` 0 issues, `dart format .`, `flutter test` green for this slice

## Phase 4: Legacy Backfills (PR 4 — dev-first, verified before prod)

Start: depends on Phase 2 AND Phase 3 merged (needs real gym docs + gymName field live). End: existing `treino-dev` users remapped from legacy ids to real sucursal docs, and `gymName` populated for all profiles with a `gymId`.

- [ ] 4.1 **[TOUCHES PRODUCTION DATA — dev-first]** Write `scripts/backfill_gym_ids.js`: map `smart-fit-palermo`, `sportclub-belgrano` → newly seeded real `gyms/` docs; `megatlon-recoleta` reused as-is (1:1 identity, no new doc)
- [ ] 4.2 Idempotency check built into script: re-run is a no-op (skip already-migrated users)
- [ ] 4.3 Dual-write `users/{uid}` + `userPublicProfiles/{uid}` in the same script run
- [ ] 4.4 **[DEV-FIRST]** Run `backfill_gym_ids.js` against `treino-dev`; manually verify affected-user count before considering prod
- [ ] 4.5 Write `scripts/backfill_gym_names.js`: fills `UserPublicProfile.gymName` (composed label) where `gymId` exists but `gymName` is missing, resolved from `gyms/` — MUST run AFTER 4.1/4.4 (order: ids then names)
- [ ] 4.6 Idempotency check: re-run of `backfill_gym_names.js` is a no-op for already-filled profiles
- [ ] 4.7 **[DEV-FIRST]** Run `backfill_gym_names.js` against `treino-dev`; manually verify count of profiles updated
- [ ] 4.8 Document verified dev counts (ids migrated, names filled) in PR description before requesting prod run approval
- [ ] 4.9 **[PROD — separate approval gate, not part of this PR's automated steps]** Run both scripts against `treino-prod` only after dev verification and maintainer sign-off; silent, no user notice (per locked decision)
- [ ] 4.10 Quality gate: `flutter analyze` 0 issues (scripts are Node.js, no analyze impact), confirm no `firestore.rules` diff introduced anywhere in the full change

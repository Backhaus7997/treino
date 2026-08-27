# Design: gyms-foundation

**Change**: `gyms-foundation` · **Engram**: `sdd/gyms-foundation/design` · Reads proposal (id 336) + explore (id 335).

> ## 🚨 `treino-dev` es PRODUCCIÓN — el "dev-first" de este change apuntaba a un proyecto que no existe
>
> `treino-dev` es el **único** proyecto Firebase de TREINO. **`treino-prod` no
> existe** y nunca existió. Las versiones anteriores de este change decían
> *"correr contra `treino-dev`, verificar el conteo, después contra
> `treino-prod`"*: el paso 1 de ese ensayo **ya era la escritura a producción**,
> y el paso 2 apuntaba a la nada. Quien lo siguiera creía estar ensayando
> mientras remapeaba el `gymId` de usuarios reales.
>
> El ensayo real es el **emulador**, que es el único entorno descartable
> (`./scripts/emulator.sh`; ambos backfills ya lo soportan con
> `FIRESTORE_EMULATOR_HOST=localhost:8080`, sin service-account key). Contra
> `treino-dev` se corre **después**, con OK explícito de un humano, sabiendo que
> es producción.
>
> Ojo con el guard de los scripts: refuerza `/dev/i.test(projectId)`, y contra
> `treino-dev` ese test **pasa** — no hay refusal, no hay `--allow-prod`. La
> única protección visible es el banner de `scripts/lib/firebase_projects.js`.
> Ver [AGENTS.md § Entornos](../../../AGENTS.md#-entornos--leer-antes-de-correr-cualquier-comando),
> [openspec/AGENTS.md](../../AGENTS.md), [#826](https://github.com/Backhaus7997/treino/issues/826)
> y [#845](https://github.com/Backhaus7997/treino/issues/845).

## Technical Approach

Collapse two gym systems into ONE rich `gyms/` collection as sole source of truth, now modeled as a **two-level catalog: brand/chain (marca) → branch (sucursal)**. Each `gyms/{gymId}` doc IS a sucursal and carries `brandId`/`brandName` for grouping. The picker is a two-step drill-down (brand → branch) derived client-side from `gymsProvider`. Name resolution goes HYBRID: denormalize a composed `gymName` ("Brand - Branch") on `UserPublicProfile` (dual-write, mirrors `CheckIn.gymName`) for lists; `gymByIdProvider` for detail. Legacy model + hardcoded providers + `gymNameFromId` map retire. Two Admin-SDK backfills (emulator-first, idempotent). NO rules change, geo stays required.

## Architecture Decisions

| Decision | Choice | Rejected | Rationale |
|---|---|---|---|
| Catalog shape | Flat `gyms/` where each doc = sucursal + `brandId`/`brandName`/`branchName` | Nested `brands/{b}/branches/{s}` subcollections | Keeps `gymId` a single stable doc id (user `gymId` unchanged, `whereIn`/`getById` intact); brand is a denormalized grouping key, not a doc. Ranking can group by `brandId` OR key on `gymId` without schema change. |
| Brand fields nullability | `String? brandId`, `String? brandName`, `String? branchName` (all nullable) | Required brand fields | Backward-compat decode for the 20 existing seed docs (no `brandId`) — `Gym.fromJson` tolerates absent keys via nullable freezed. Seed rewrite backfills real values; independents legitimately have `branchName == null`. |
| `name` field | KEEP `name` as canonical full display; brand/branch are structured extras | Compose display purely from brand+branch, drop `name` | `name` already denormalized everywhere (7 call sites, seed, `CheckIn`); keeping it is the backward-compat anchor. For grouped brands `name = "Brand - Branch"`; independents `name = brandName`. `_fromDoc` needs no fallback logic. |
| Brand derivation | `gymBrandsProvider` = `Provider.autoDispose<AsyncValue<List<GymBrand>>>` grouping `gymsProvider` by `brandId` (fallback key = `id` when `brandId` null) | Separate Firestore query / brands collection | Catalog ~20-100 docs, group in memory. `GymBrand{brandId, brandName, branchCount, singleBranchGymId}`. `branchCount==1` → `singleBranchGymId` set → step 2 skipped. |
| Picker navigation | TWO-STEP drill-down: brand list → branch list, both `GymCard`s, shared search | Single flat list of all sucursales | Locked decision. Reduces scroll for chains (one "SportClub" row vs 12). Single-branch brand selects directly (skip step 2). |
| Picker step/selection state | ProfileSetup: local `selectedBrandId` in `Step2Gym` (StatefulWidget) + `updateGymId` on final pick. Standalone: local `_step`/`_selectedBrandId`/`_pendingGymId` in `_ProfileGymScreenState` | New StateNotifier for picker nav | Nav state is ephemeral UI, dies with the screen; matches existing `_pendingGymId` local pattern. `gymBrandSearchQueryProvider` (autoDispose) shared for both steps' search text. |
| Name resolution / denorm | HYBRID: composed `gymName` on `UserPublicProfile` (lists) + `gymByIdProvider` (detail). `gymName` = selected sucursal doc's `name` | Compose in every widget / pure `gymByIdProvider` | Avoids N+1 in feed/inbox/search; `name` already holds the "Brand - Branch" string so dual-write just copies `gym.name`. |
| Unknown/no-gym fallback | Empty string (hide subtitle) | `id.toUpperCase()` | Curated catalog ⇒ unknown id is a bug. Unchanged from prior design. |

## Data Flow

```
Picker step1: gymsProvider ─► gymBrandsProvider (group by brandId) ─► gymBrandSearchQueryProvider ─► BrandCard
Picker step2: pick brand ─► branchesFor(brandId) = gyms.where(brandId==) ─► search ─► BranchCard ─► updateGymId(sucursalId)
             (branchCount==1 ⇒ skip step2, updateGymId(singleBranchGymId) directly)
Save:  update({gymId}) ─► _publicSubsetFromPartial resolves gymName = gyms[gymId].name ─► batch: users + userPublicProfiles
Read:  list  → UserPublicProfile.gymName (denormalized "Brand - Branch", 0 fetch)
       detail→ gymByIdProvider(gymId)
```

## File Changes

| File | Action | Description |
|---|---|---|
| `gyms/domain/gym.dart` | Modify | Add `String? brandId`, `String? brandName`, `String? branchName`; keep id/name/address/lat/lng/geohash/source/city/province; build_runner regen |
| `gyms/domain/gym_brand.dart` | Create | `@freezed GymBrand{brandId, brandName, branchCount, singleBranchGymId?}` (no json; pure grouping view model) |
| `gyms/application/gym_providers.dart` | Modify | Add `gymBrandsProvider` (grouped), `gymBrandSearchQueryProvider`, `branchesForBrandProvider.family` (or inline filter); keep `gymsProvider`/`gymByIdProvider` |
| `profile_setup/domain/gym.dart` | Modify | Delete legacy `Gym`; KEEP `kNoGymId` (re-home const) |
| `profile_setup/application/profile_setup_providers.dart` | Modify | Delete `_kHardcodedGyms`, `gymSearchQueryProvider`, `filteredGymsProvider` |
| `feed/domain/gym_name.dart` | Delete | Remove `_kGymNames` + `gymNameFromId` |
| `profile_setup/.../steps/step_2_gym.dart` | Modify | ConsumerWidget→ConsumerStatefulWidget; two-step brand/branch + async loading/error/retry (mirror `_GymsSection`) |
| `profile/presentation/profile_gym_screen.dart` | Modify | Two-step nav (`_step`, `_selectedBrandId`), back-from-branch returns to brands; async states |
| `profile/domain/user_public_profile.dart` | Modify | Add `String? gymName`; regen |
| `profile/data/user_repository.dart` | Modify | Add `gymName` to public dual-write; resolve from sucursal doc on `gymId` change (inject GymRepository) |
| 7 call sites (feed_screen, session_player, user_search_result_tile, friend_request_inbox_tile, public_profile_hero, profile_avatar_card, profile_cuenta_section) | Modify | Lists→`profile.gymName`; detail→`gymByIdProvider`. (check_in_dialog reads own `profile.gymName`) |
| `scripts/seed_gyms.js` | Rewrite | Grouped by brand→branches: `brandId/brandName/branchName` + coords + `city/province`. Córdoba + KEEP BA; `smart-fit-palermo`/`sportclub-belgrano`/`megatlon-recoleta` as real sucursal docs under their brand |
| `scripts/backfill_gym_ids.js` | Create | Legacy→real id map (1:1 identity, 3 legacy ids now real docs), idempotent, dual-write, verified count, emulator-first |
| `scripts/backfill_gym_names.js` | Create | Populate `userPublicProfiles.gymName` from `gyms[gymId].name`; run AFTER id backfill |

## Interfaces / Contracts

```dart
// Gym.fromJson backward-compat: brandId/brandName/branchName nullable → 20 old docs decode.
// UserRepository: resolve composed gymName from the sucursal doc (needs GymRepository dep)
if (partial.containsKey('gymId')) {
  final id = partial['gymId'] as String?;
  result['gymName'] = (id == null || id == kNoGymId) ? null : (await _gyms.getById(id))?.name;
}
// gymBrandsProvider: group by (brandId ?? id); branchCount==1 ⇒ singleBranchGymId = that gym.id
```
`gymBrandSearchQueryProvider` = `StateProvider.autoDispose<String>`. `branchesForBrandProvider` = `Provider.autoDispose.family<List<Gym>, String>` filtering `gymsProvider.value` by `brandId`.

## Testing Strategy (Strict TDD)

| Layer | Test | Approach |
|---|---|---|
| Unit | `Gym.fromJson` WITH brand fields AND WITHOUT (old 20 docs) | pure decode, no Firestore |
| Unit | `gymBrandsProvider` grouping: multi-branch count, single-branch `singleBranchGymId`, null brandId fallback | container overrides mock `gymsProvider` |
| Unit | `UserRepository.update({gymId})` writes composed `gymName` from sucursal | fake_cloud_firestore + fake gym, verify dual-write batch |
| Widget | Two-step picker: brand list → branch list → back; single-branch skip; loading/error/retry; search each step | mock `gymsProvider` overrides |
| Unit | name fallback: unknown/`no-gym`/null → hidden | replaces deleted `gym_name_test.dart` |
| Rules | NONE — `firestore.rules` unchanged (confirmed) | NO emulator work |

Backfill idempotency verified manually vs the local Firestore emulator (not unit-tested; mirrors `migrate_trainer_locations.js`). Not vs `treino-dev` — that is production, and "verifying" there means the write already happened.

## Migration / Rollout

Order: seed (real sucursal docs w/ brand fields) → `backfill_gym_ids.js` (1:1, no-op for legacy since now real) → `backfill_gym_names.js`. Each one is rehearsed on the **local emulator** to a verified count, and only then run against `treino-dev` — which is production, and is the end of the line: there is no `treino-prod` to promote to. Silent backfill (locked); the production run needs explicit maintainer sign-off.

## Ranking flexibility (note only — not designed here)

Stored `gymId` = sucursal id. Each doc carries `brandId`. Future ranking can be **per-sucursal** (default, key on `gymId`) OR **per-brand** (group by `brandId`) with no schema change. This design only preserves the foundation; ranking logic is out of scope.

## PR Slices (>400 LOC — chained, tests-with-code, ≤~400 LOC each)

1. **Model + seed foundation**: `Gym` +brand fields (+city/province), `GymBrand`, seed rewrite grouped by brand, delete legacy model, re-home `kNoGymId`, `gym_name.dart` delete + fallback test, decode tests.
2. **Brand grouping + two-step picker**: `gymBrandsProvider`/`branchesForBrandProvider`/search providers, providers move, `step_2_gym` + `profile_gym_screen` two-step async, widget tests.
3. **Name resolution**: `UserPublicProfile.gymName` + `UserRepository` dual-write (composed name) + 7 call sites + tests.
4. **Backfills**: `backfill_gym_ids.js` + `backfill_gym_names.js`.

Dependency: 1 → (2 ∥ 3) → 4.

## Open Questions

- [ ] Prod silent remap vs user notice (product).
- [ ] Córdoba v1 catalog size + which chains are single-branch vs multi (product/data).

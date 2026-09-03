# Gym Name Resolution Specification

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
> Ver [AGENTS.md § Entornos](../../../../../AGENTS.md#-entornos--leer-antes-de-correr-cualquier-comando),
> [openspec/AGENTS.md](../../../../AGENTS.md), [#826](https://github.com/Backhaus7997/treino/issues/826)
> y [#845](https://github.com/Backhaus7997/treino/issues/845).

## Purpose

Replace the stale hardcoded gym-name lookup (`gymNameFromId`) with real, resolvable names sourced from the curated `gyms/` catalog, using a denormalization strategy for list contexts and a cached provider for detail contexts. Includes backfilling legacy gym-id references and existing profile docs so no user-facing name regresses.

## Requirements

### Requirement: Real gym names replace the hardcoded name map

The system MUST remove `_kGymNames` and `gymNameFromId` (`lib/features/feed/domain/gym_name.dart`) and MUST NOT reintroduce a hardcoded id-to-name map.

The system MUST resolve gym names at all 7 existing call sites (`feed_screen.dart`, `session_player_screen.dart`, `user_search_result_tile.dart`, `profile_cuenta_section.dart`, `friend_request_inbox_tile.dart`, `profile_avatar_card.dart`, `public_profile_hero.dart`) using real data from `gyms/`, not string transformation of the id.

The displayed/denormalized gym name MUST be the combined brand-branch label ("`{brandName} - {branchName}`", e.g. "SportClub - Belgrano") for multi-branch brands. For an independent, single-branch brand, the displayed name MUST be just the brand name (no redundant branch suffix).

#### Scenario: Hardcoded name map is gone

- GIVEN the codebase after this change is applied
- WHEN searching for `_kGymNames` or `gymNameFromId`
- THEN neither symbol exists anymore

#### Scenario: All call sites resolve names from real data

- GIVEN any of the 7 listed screens/widgets renders a user's gym name
- WHEN the underlying user has a valid `gymId`
- THEN the displayed name matches the resolved brand-branch label of the corresponding `gyms/{gymId}` doc, not an uppercased id

#### Scenario: Chain gym displays as "Brand - Branch"

- GIVEN a user's `gymId` resolves to a multi-branch chain's sucursal (e.g. brandName "SportClub", branchName "Belgrano")
- WHEN any call site renders that user's gym name
- THEN the displayed text is "SportClub - Belgrano"

#### Scenario: Independent gym displays as just the brand name

- GIVEN a user's `gymId` resolves to an independent, single-branch gym
- WHEN any call site renders that user's gym name
- THEN the displayed text is only the brand name, with no branch suffix

### Requirement: List contexts use denormalized gym name; detail contexts use cached lookup

The system MUST denormalize a `gymName` field onto `UserPublicProfile`, written at the same time `gymId` is written (dual-write in the profile save path), mirroring the existing `CheckIn.gymName` denormalization pattern. `gymName` MUST hold the composed brand-branch label described above (not just `branchName` or a raw doc field).

The system MUST use the denormalized `UserPublicProfile.gymName` for list/feed contexts (feed, friend-request inbox, search results) to avoid N+1 gym lookups.

The system MUST use `gymByIdProvider` (single-id lookup, Riverpod-cached) for single-user detail contexts (profile screens, session player) instead of denormalization, composing the same brand-branch label from the resolved `Gym`.

#### Scenario: Saving a profile's gym keeps name and id in sync

- GIVEN an athlete selects a specific sucursal in the two-step picker and saves their profile
- WHEN the write completes
- THEN `UserPublicProfile.gymId` (the sucursal doc id) and `UserPublicProfile.gymName` (the composed brand-branch label) are written together in the same operation and refer to the same gym

#### Scenario: Feed list does not trigger per-row gym fetches

- GIVEN a feed screen renders N users with different gyms
- WHEN the list loads
- THEN gym names are read directly from each user's denormalized `gymName` field, with no additional per-row gym fetch

#### Scenario: Profile detail screen resolves name via provider

- GIVEN a single user's profile detail screen is opened
- WHEN the screen needs to display that user's gym name
- THEN it resolves the name via `gymByIdProvider(gymId)`, which Riverpod caches by id

### Requirement: Safe fallback when a gym id cannot be resolved

The system MUST render a safe, non-crashing fallback (e.g. empty subtitle or generic label) when a `gymId` does not resolve to any known `gyms/` doc, instead of throwing or displaying a raw id.

The system MUST treat `null`, empty string, and `kNoGymId` as "no gym" and MUST NOT attempt resolution for these values.

#### Scenario: Unknown gym id does not break rendering

- GIVEN a user profile references a `gymId` that has no matching `gyms/` doc
- WHEN a screen attempts to render that user's gym name
- THEN the UI shows a safe fallback (not a crash, not a raw id string) and the rest of the screen renders normally

#### Scenario: "No gym" sentinel and empty values render nothing

- GIVEN a user's `gymId` is `null`, empty, or `kNoGymId`
- WHEN a screen renders that user's gym label
- THEN no gym-name subtitle is shown (empty/hidden), consistent with current behavior

### Requirement: Legacy gymId backfill maps hardcoded ids to real gym docs

The system MUST provide an emulator-first, idempotent script (`scripts/migrate_legacy_gym_ids.js`) that maps the 3 legacy hardcoded ids (`smart-fit-palermo`, `sportclub-belgrano`, `megatlon-recoleta`) to real `gyms/` docs.

The system MUST reuse `megatlon-recoleta` as-is (already exists in `gyms/` with that exact id — no new doc created) and MUST create real `gyms/` docs for `smart-fit-palermo` and `sportclub-belgrano`.

The script MUST dual-write both `users/{uid}` and `userPublicProfiles/{uid}` for every migrated user, consistent with the runtime write path.

The script MUST be idempotent: running it multiple times MUST NOT change already-migrated docs or duplicate writes.

The script MUST run silently with no end-user notice.

The script MUST be verified against the local Firestore emulator (`FIRESTORE_EMULATOR_HOST=localhost:8080`, launched by `./scripts/emulator.sh`) — reaching a verified count there — before it is run against `treino-dev`.

`treino-dev` is TREINO's only Firebase project and holds real user data. A run against it is a production write and MUST NOT proceed without explicit maintainer sign-off recorded in the PR. There is no second project to promote to: **`treino-prod` does not exist**, and any requirement phrased as "dev before prod" describes an environment this repo does not have.

#### Scenario: megatlon-recoleta requires no new doc

- GIVEN a user with legacy `gymId = 'megatlon-recoleta'`
- WHEN the migration script runs
- THEN no new `gyms/` doc is created for this id, since it already exists in the catalog with the same id

#### Scenario: smart-fit-palermo and sportclub-belgrano map to real docs

- GIVEN users with legacy `gymId` of `smart-fit-palermo` or `sportclub-belgrano`
- WHEN the migration script runs
- THEN each user's `gymId` is updated to point to a real, existing `gyms/` doc created or designated for that legacy id
- AND both `users/{uid}` and `userPublicProfiles/{uid}` reflect the updated `gymId`

#### Scenario: Re-running the migration is a no-op for migrated users

- GIVEN the migration script has already run successfully for a user
- WHEN the script is run again
- THEN that user's docs are not modified a second time (skip-if-already-migrated)

#### Scenario: Migration is rehearsed on the emulator before it touches production

- GIVEN the migration script is executed
- WHEN it targets the local Firestore emulator
- THEN it completes and reports a verified count before any run against `treino-dev` is considered
- AND no in-app notice or prompt is shown to affected athletes

#### Scenario: A run against treino-dev is a production run

- GIVEN the emulator rehearsal has produced a verified count
- WHEN the script is pointed at `treino-dev`
- THEN that run is treated as a production write against real user data, gated on explicit maintainer sign-off
- AND no further "promotion to prod" step exists, because `treino-dev` is the only Firebase project

### Requirement: Backfill of denormalized gymName for existing profiles

The system MUST provide a backfill that populates `UserPublicProfile.gymName` for existing docs that have a `gymId` but no `gymName`, resolving the name from `gyms/`.

The backfill MUST run after the legacy gymId backfill (id migration first, name backfill second) so names resolve against already-corrected ids.

The backfill MUST be idempotent and emulator-first, consistent with the legacy gymId migration's operational discipline: verified against the emulator, then run against `treino-dev` (production) only with explicit maintainer sign-off.

#### Scenario: Existing profile gets gymName filled in

- GIVEN an existing `UserPublicProfile` doc has `gymId` set but `gymName` absent
- WHEN the backfill runs
- THEN `gymName` is populated with the name resolved from the corresponding `gyms/{gymId}` doc

#### Scenario: Backfill order is ids before names

- GIVEN both backfills need to run for the same dataset
- WHEN executing the migration
- THEN the legacy gymId backfill completes before the gymName backfill begins, so gymName resolution reads already-migrated ids

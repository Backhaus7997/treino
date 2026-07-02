# Delta for Gym Name Resolution

## MODIFIED Requirements

### Requirement: Real gym names replace the hardcoded name map

The system MUST remove `_kGymNames` and `gymNameFromId` (`lib/features/feed/domain/gym_name.dart`) and MUST NOT reintroduce a hardcoded id-to-name map.

The system MUST resolve gym names at all 7 existing call sites (`feed_screen.dart`, `session_player_screen.dart`, `user_search_result_tile.dart`, `profile_cuenta_section.dart`, `friend_request_inbox_tile.dart`, `profile_avatar_card.dart`, `public_profile_hero.dart`) using real data from `gyms/`, not string transformation of the id.

The displayed/denormalized gym name MUST be the combined brand-branch label ("`{brandName} - {branchName}`") when both `brandName` and `branchName` are present on the resolved `Gym`. When either is absent (including all Google-Places-sourced gyms, where both are `null`), the displayed name MUST be just `name` (the Place's display name), with no separator or suffix.

(Previously: assumed every `Gym` always carried `brandName`/`branchName`, so the combined label was unconditional. Now conditional because Places-sourced gyms have neither.)

#### Scenario: Hardcoded name map is gone

- GIVEN the codebase after this change is applied
- WHEN searching for `_kGymNames` or `gymNameFromId`
- THEN neither symbol exists anymore

#### Scenario: All call sites resolve names from real data

- GIVEN any of the 7 listed screens/widgets renders a user's gym name
- WHEN the underlying user has a valid `gymId`
- THEN the displayed name matches the resolved label of the corresponding `gyms/{gymId}` doc, not an uppercased id

#### Scenario: Chain gym displays as "Brand - Branch"

- GIVEN a user's `gymId` resolves to a curated multi-branch chain's sucursal (e.g. brandName "SportClub", branchName "Belgrano")
- WHEN any call site renders that user's gym name
- THEN the displayed text is "SportClub - Belgrano"

#### Scenario: Places-sourced gym displays as just its name

- GIVEN a user's `gymId` resolves to a Google-Places-sourced gym (`brandName` and `branchName` both `null`)
- WHEN any call site renders that user's gym name
- THEN the displayed text is only the gym's `name`, with no separator or brand/branch suffix

## Requirements (unchanged, restated for continuity)

### Requirement: List contexts use denormalized gym name; detail contexts use cached lookup

The system MUST denormalize a `gymName` field onto `UserPublicProfile`, written at the same time `gymId` is written (dual-write in the profile save path), mirroring the existing `CheckIn.gymName` denormalization pattern. `gymName` MUST hold the resolved display label described above, computed identically regardless of the gym's `source`.

The system MUST use the denormalized `UserPublicProfile.gymName` for list/feed contexts to avoid N+1 gym lookups.

The system MUST use `gymByIdProvider` (single-id lookup, Riverpod-cached) for single-user detail contexts instead of denormalization, composing the same display label from the resolved `Gym`.

This requirement's dual-write and lookup mechanics are unaffected by this change; only the label composition (see MODIFIED requirement above) changes.

#### Scenario: Saving a profile's gym keeps name and id in sync

- GIVEN an athlete selects a gym (curated or Google-Places-sourced) and saves their profile
- WHEN the write completes
- THEN `UserPublicProfile.gymId` and `UserPublicProfile.gymName` are written together in the same operation and refer to the same gym

### Requirement: Safe fallback when a gym id cannot be resolved

The system MUST render a safe, non-crashing fallback (e.g. empty subtitle or generic label) when a `gymId` does not resolve to any known `gyms/` doc, instead of throwing or displaying a raw id. This applies unchanged to stale curated `gymId`s left un-migrated by this change (see "No migration of existing selections" in the new Places-search delta).

The system MUST treat `null`, empty string, and `kNoGymId` as "no gym" and MUST NOT attempt resolution for these values.

#### Scenario: Unknown or stale gym id does not break rendering

- GIVEN a user profile references a `gymId` that has no matching `gyms/` doc (including a stale pre-migration curated id)
- WHEN a screen attempts to render that user's gym name
- THEN the UI shows a safe fallback (not a crash, not a raw id string) and the rest of the screen renders normally

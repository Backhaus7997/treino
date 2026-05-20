# Spec: Coach Discovery (Fase 5 · Etapa 2)

**Change**: `coach-discovery`
**REQ namespace**: `REQ-COACH-DISC-NNN`
**SCENARIO start**: 407
**SCENARIO end**: 432
**Capabilities touched**:
- NEW `coach-discovery-data`
- NEW `coach-discovery-ui`
- ANNOTATED `user-data` (dual-write extension — additive, no breaking change)

---

## New Capability: `coach-discovery-data`

### Purpose

Expose a public Firestore collection `trainerPublicProfiles/{uid}` that allows any authenticated
user to query trainer profiles by geohash prefix and specialty. The collection is populated via
atomic dual-write from `UserRepository.update()` whenever trainer-owned fields change. A pure
`haversineKm` utility computes client-side distances in km. The Firestore security rule enforces
that only authenticated users can read, and only the document owner can write.

This capability resolves the critical blocker identified in explore: querying `users/{uid}` for
trainer discovery **fails at runtime** because `users/{uid}` is owner-only. The solution replicates
the battle-tested pattern from Fase 3 Etapa 5.5 (`userPublicProfiles`).

---

## Requirements — `coach-discovery-data`

| ID | Name | Strength |
|----|------|----------|
| REQ-COACH-DISC-DATA-001 | `TrainerPublicProfile` model fields | MUST |
| REQ-COACH-DISC-DATA-002 | `TrainerPublicProfile` JSON roundtrip | MUST |
| REQ-COACH-DISC-DATA-003 | `TrainerSpecialty` enum — 10 predefined values | MUST |
| REQ-COACH-DISC-DATA-004 | `TrainerPublicProfileRepository.listByGeohashPrefix` | MUST |
| REQ-COACH-DISC-DATA-005 | `listByGeohashPrefix` specialty filter | MUST |
| REQ-COACH-DISC-DATA-006 | `TrainerPublicProfileRepository.listAll` | MUST |
| REQ-COACH-DISC-DATA-007 | `TrainerPublicProfileRepository.getById` | MUST |
| REQ-COACH-DISC-DATA-008 | Firestore rule — read requires auth | MUST |
| REQ-COACH-DISC-DATA-009 | Firestore rule — write restricted to owner | MUST |
| REQ-COACH-DISC-DATA-010 | `haversineKm` — pure function contract | MUST |
| REQ-COACH-DISC-DATA-011 | `geohash5` helper — 5-char base32 encoding | MUST |

---

## REQ-COACH-DISC-DATA-001 — `TrainerPublicProfile` model fields

The system MUST define an immutable, freezed model `TrainerPublicProfile` with the following fields:

| Field | Type | Nullable | Notes |
|-------|------|----------|-------|
| `uid` | `String` | No | Document ID |
| `displayName` | `String` | No | Trainer display name |
| `displayNameLowercase` | `String` | No | Lowercase of `displayName` for case-insensitive search |
| `avatarUrl` | `String?` | Yes | Profile photo URL |
| `trainerSpecialty` | `TrainerSpecialty?` | Yes | One predefined specialty |
| `trainerGeohash` | `String?` | Yes | Geohash5 string (5 chars) |
| `trainerLatitude` | `double?` | Yes | WGS-84 latitude |
| `trainerLongitude` | `double?` | Yes | WGS-84 longitude |
| `trainerHourlyRate` | `int?` | Yes | Rate in ARS per hour/session |

The model MUST be generated via `freezed` (immutable, `copyWith`, structural equality) and
`json_serializable` (`fromJson` / `toJson`).

`displayNameLowercase` MUST equal `displayName.toLowerCase()`. It is stored as a field (not computed
at read time) to enable server-side case-insensitive prefix queries in future.

#### SCENARIO-407: `TrainerPublicProfile` with all fields roundtrips through JSON

- GIVEN a `TrainerPublicProfile` constructed with `uid: 'u1'`, `displayName: 'Ana García'`,
  `displayNameLowercase: 'ana garcía'`, `avatarUrl: 'https://example.com/a.jpg'`,
  `trainerSpecialty: TrainerSpecialty.hipertrofia`, `trainerGeohash: 'p0qh2'`,
  `trainerLatitude: -34.603`, `trainerLongitude: -58.381`, `trainerHourlyRate: 5000`
- WHEN `profile.toJson()` is called and the result is passed to `TrainerPublicProfile.fromJson()`
- THEN the reconstructed instance equals the original (all fields match)

#### SCENARIO-408: `TrainerPublicProfile` with nullable fields as null roundtrips through JSON

- GIVEN a `TrainerPublicProfile` with `uid: 'u2'`, `displayName: 'Juan'`,
  `displayNameLowercase: 'juan'`, and all nullable fields as `null`
- WHEN `profile.toJson()` is called and the result is passed to `TrainerPublicProfile.fromJson()`
- THEN the reconstructed instance equals the original
- AND `trainerSpecialty`, `trainerGeohash`, `trainerLatitude`, `trainerLongitude`, `trainerHourlyRate`
  are all `null`

---

## REQ-COACH-DISC-DATA-002 — `TrainerPublicProfile` JSON roundtrip

`TrainerPublicProfile.fromJson(map)` MUST correctly parse a Firestore document map. Fields absent
from the map MUST be treated as `null` (nullable fields) or cause a parse error (non-nullable fields).
`TrainerPublicProfile.toJson()` MUST produce a map compatible with `FirebaseFirestore` writes.

*(Covered by SCENARIO-407 and SCENARIO-408 above.)*

---

## REQ-COACH-DISC-DATA-003 — `TrainerSpecialty` enum — 10 predefined values

The system MUST define a `TrainerSpecialty` enum (or equivalent sealed construct) with exactly the
following 10 values, in the order listed:

`powerlifting`, `crossfit`, `bodybuilding`, `hipertrofia`, `wellness`, `kinesiologia`, `funcional`,
`running`, `yoga`, `calistenia`

The enum MUST expose a `fromString(String value)` factory that performs case-insensitive matching.
When the input does not match any known value, `fromString` MUST return `null` (not throw).

This list is closed for this change. New specialties require a spec amendment.

#### SCENARIO-409: `TrainerSpecialty` covers all 10 values

- GIVEN the `TrainerSpecialty` enum
- WHEN `TrainerSpecialty.values` is accessed
- THEN it contains exactly 10 elements: `powerlifting`, `crossfit`, `bodybuilding`, `hipertrofia`,
  `wellness`, `kinesiologia`, `funcional`, `running`, `yoga`, `calistenia`

#### SCENARIO-410: `TrainerSpecialty.fromString` is case-insensitive and returns null for unknown

- GIVEN `TrainerSpecialty.fromString('Hipertrofia')` (capital H)
- WHEN the factory is called
- THEN it returns `TrainerSpecialty.hipertrofia`

- GIVEN `TrainerSpecialty.fromString('spinning')` (not in list)
- WHEN the factory is called
- THEN it returns `null` (no exception thrown)

---

## REQ-COACH-DISC-DATA-004 — `TrainerPublicProfileRepository.listByGeohashPrefix`

The repository MUST expose:

```
Future<List<TrainerPublicProfile>> listByGeohashPrefix(
  String prefix5, {
  TrainerSpecialty? specialty,
}) 
```

This method MUST query the `trainerPublicProfiles` Firestore collection for documents whose
`trainerGeohash` field satisfies a prefix range:
- `isGreaterThanOrEqualTo: prefix5`
- `isLessThan: prefix5 + ''`

Results MUST be ordered by `displayName` ascending (deterministic order; distance sort is
client-side after haversine computation).

Documents whose `trainerGeohash` is `null` or does not start with `prefix5` MUST NOT appear in
the result.

When `specialty` is non-null, results MUST be filtered to include only documents where
`trainerSpecialty == specialty`. This filter is applied **client-side** on the result set to
avoid requiring a compound Firestore index on `trainerGeohash + trainerSpecialty`.

#### SCENARIO-411: `listByGeohashPrefix` returns trainers matching the prefix

- GIVEN the `trainerPublicProfiles` collection contains:
  trainer A with `trainerGeohash: 'p0qh2'` and `displayName: 'Ana'`
  trainer B with `trainerGeohash: 'p0qh3'` and `displayName: 'Bruno'`
  trainer C with `trainerGeohash: 'xyz99'` and `displayName: 'Carlos'`
- WHEN `listByGeohashPrefix('p0qh')` is called
- THEN the result contains trainer A and trainer B
- AND trainer C is NOT in the result

#### SCENARIO-412: `listByGeohashPrefix` with specialty filter excludes non-matching specialties

- GIVEN the collection contains:
  trainer A with `trainerGeohash: 'p0qh1'`, `trainerSpecialty: TrainerSpecialty.yoga`
  trainer B with `trainerGeohash: 'p0qh2'`, `trainerSpecialty: TrainerSpecialty.crossfit`
- WHEN `listByGeohashPrefix('p0qh', specialty: TrainerSpecialty.yoga)` is called
- THEN the result contains trainer A only
- AND trainer B is NOT in the result

#### SCENARIO-413: `listByGeohashPrefix` returns empty list when no prefix matches

- GIVEN the collection contains trainers only with geohash prefix `'xyz'`
- WHEN `listByGeohashPrefix('p0qh')` is called
- THEN the result is an empty list (no error thrown)

---

## REQ-COACH-DISC-DATA-005 — `listByGeohashPrefix` specialty filter

*(Defined inline in REQ-COACH-DISC-DATA-004 — SCENARIO-412 covers this requirement.)*

---

## REQ-COACH-DISC-DATA-006 — `TrainerPublicProfileRepository.listAll`

The repository MUST expose:

```
Future<List<TrainerPublicProfile>> listAll({
  TrainerSpecialty? specialty,
})
```

This method MUST return all documents in `trainerPublicProfiles`, ordered by `displayName`
ascending, with no geohash filter applied.

It is the fallback used when the athlete has not granted location permission or when device GPS
is unavailable.

When `specialty` is non-null, results MUST be filtered client-side to include only documents where
`trainerSpecialty == specialty`.

#### SCENARIO-414: `listAll` returns all trainers ordered by displayName when no specialty filter

- GIVEN the collection contains trainer A (`displayName: 'Zara'`) and trainer B (`displayName: 'Ana'`)
- WHEN `listAll()` is called
- THEN the result is `[trainer B, trainer A]` (ascending by displayName)

---

## REQ-COACH-DISC-DATA-007 — `TrainerPublicProfileRepository.getById`

The repository MUST expose:

```
Future<TrainerPublicProfile?> getById(String uid)
```

This method MUST return the `TrainerPublicProfile` for the given `uid` if the document exists,
or `null` if the document does not exist. It MUST NOT throw when the document is absent.

#### SCENARIO-415: `getById` returns null when document does not exist

- GIVEN no document with `uid: 'nonexistent'` exists in `trainerPublicProfiles`
- WHEN `getById('nonexistent')` is called
- THEN the return value is `null`
- AND no exception is thrown

---

## REQ-COACH-DISC-DATA-008 — Firestore rule — read requires auth

The `trainerPublicProfiles/{uid}` collection rule MUST allow read operations for any authenticated
user (`request.auth != null`). Anonymous (unauthenticated) requests MUST be denied.

#### SCENARIO-416: authenticated user can read `trainerPublicProfiles`

- GIVEN a Firestore emulator with the production rules applied
- AND a user is authenticated
- WHEN the user reads `trainerPublicProfiles/any-uid`
- THEN the read is permitted (no PERMISSION_DENIED error)

#### SCENARIO-417: unauthenticated request to `trainerPublicProfiles` is denied

- GIVEN a Firestore emulator with the production rules applied
- AND the request has no auth token
- WHEN an unauthenticated client reads `trainerPublicProfiles/any-uid`
- THEN the read is denied with PERMISSION_DENIED

---

## REQ-COACH-DISC-DATA-009 — Firestore rule — write restricted to owner

Write operations on `trainerPublicProfiles/{uid}` MUST be permitted only when
`request.auth.uid == uid`. A write attempt by a different authenticated user MUST be denied.

#### SCENARIO-418: owner can write their own `trainerPublicProfiles` document

- GIVEN a Firestore emulator with production rules
- AND user `uid: 'trainer-1'` is authenticated
- WHEN that user writes to `trainerPublicProfiles/trainer-1`
- THEN the write is permitted

#### SCENARIO-419: non-owner cannot write another trainer's `trainerPublicProfiles` document

- GIVEN a Firestore emulator with production rules
- AND user `uid: 'other-user'` is authenticated
- WHEN that user attempts to write to `trainerPublicProfiles/trainer-1`
- THEN the write is denied with PERMISSION_DENIED

---

## REQ-COACH-DISC-DATA-010 — `haversineKm` — pure function contract

A pure function `haversineKm(double lat1, double lon1, double lat2, double lon2) → double` MUST
exist at `lib/core/utils/haversine.dart`.

The function MUST:
- Return distance in kilometers using the haversine formula with Earth radius = 6371.0 km.
- Be deterministic: same inputs always produce the same output.
- Have no side effects and no I/O calls.
- Return `0.0` when both points are identical.

The function MUST NOT be a method on any class. It MUST be a top-level function.

#### SCENARIO-420: `haversineKm` returns approximately correct distance for known reference points

- GIVEN `lat1: -34.6037, lon1: -58.3816` (Buenos Aires) and
  `lat2: -33.4489, lon2: -70.6693` (Santiago de Chile)
- WHEN `haversineKm(lat1, lon1, lat2, lon2)` is called
- THEN the result is between 1140.0 and 1160.0 km (reference: ~1150 km)

#### SCENARIO-421: `haversineKm` returns 0.0 for identical coordinates

- GIVEN `lat1 == lat2 == -34.6037` and `lon1 == lon2 == -58.3816`
- WHEN `haversineKm(lat1, lon1, lat2, lon2)` is called
- THEN the result is `0.0`

---

## REQ-COACH-DISC-DATA-011 — `geohash5` helper — 5-char base32 encoding

A pure function `geohash5(double lat, double lon) → String` MUST exist, accessible from
`lib/core/utils/haversine.dart` or a co-located file.

The function MUST return a 5-character base32 geohash string for the given coordinates.
The output MUST be deterministic and consistent with the standard Geohash encoding (base32 alphabet:
`0123456789bcdefghjkmnpqrstuvwxyz`).

This function is used when an athlete grants location permission to compute the prefix for
`listByGeohashPrefix`.

#### SCENARIO-422: `geohash5` returns a 5-character string for Buenos Aires coordinates

- GIVEN `lat: -34.6037, lon: -58.3816`
- WHEN `geohash5(lat, lon)` is called
- THEN the result is a String of exactly 5 characters
- AND all characters belong to the base32 geohash alphabet (`0-9, b-h, j-n, p-z`, no `a/i/l/o`)
- AND the result starts with `'p0q'` (known prefix for Buenos Aires area)

---

## Annotated Capability: `user-data` — dual-write extension

### Purpose

`UserRepository.update()` is extended to detect changes in trainer-owned fields and execute an
atomic `WriteBatch` that writes to both `users/{uid}` and `trainerPublicProfiles/{uid}`.
This extension is **additive**: non-trainer field updates are unaffected.

### Requirements — dual-write

| ID | Name | Strength |
|----|------|----------|
| REQ-COACH-DISC-DUAL-001 | Atomic dual-write on trainer field change | MUST |
| REQ-COACH-DISC-DUAL-002 | Non-trainer updates do NOT touch `trainerPublicProfiles` | MUST |

---

## REQ-COACH-DISC-DUAL-001 — Atomic dual-write on trainer field change

When `UserRepository.update(uid, data)` is called and `data` contains at least one trainer field
(`displayName`, `avatarUrl`, `trainerSpecialty`, `trainerGeohash`, `trainerLatitude`,
`trainerLongitude`, `trainerHourlyRate`), the method MUST execute a single `WriteBatch` that
atomically writes:

1. The full `data` map to `users/{uid}` (existing behavior preserved).
2. The trainer-field subset of `data` to `trainerPublicProfiles/{uid}` (new write).

If the batch fails, neither write is committed. The error MUST propagate to the caller.
No partial state (one write committed without the other) is permissible.

#### SCENARIO-423: dual-write commits both documents atomically when trainer field changes

- GIVEN a Firestore emulator with `users/trainer-1` existing
- WHEN `UserRepository.update('trainer-1', {'trainerSpecialty': 'yoga', 'trainerLatitude': -34.6})`
  is called
- THEN `users/trainer-1` contains `trainerSpecialty: 'yoga'` and `trainerLatitude: -34.6`
- AND `trainerPublicProfiles/trainer-1` contains `trainerSpecialty: 'yoga'` and
  `trainerLatitude: -34.6`
- AND both writes were committed in the same batch (atomically)

---

## REQ-COACH-DISC-DUAL-002 — Non-trainer updates do NOT touch `trainerPublicProfiles`

When `UserRepository.update(uid, data)` is called and `data` contains no trainer fields
(e.g. only `gymId` or `bio`), the method MUST write only to `users/{uid}`.
`trainerPublicProfiles/{uid}` MUST NOT be touched.

#### SCENARIO-424: non-trainer field update does not write to `trainerPublicProfiles`

- GIVEN `users/athlete-1` exists and `trainerPublicProfiles/athlete-1` does NOT exist
- WHEN `UserRepository.update('athlete-1', {'gymId': 'gym-42'})` is called
- THEN `users/athlete-1` is updated with `gymId: 'gym-42'`
- AND `trainerPublicProfiles/athlete-1` is NOT created and does NOT exist after the call

---

## New Capability: `coach-discovery-ui`

### Purpose

`TrainersListScreen` replaces the `AthleteCoachView` stub in the Coach tab for athletes.
It presents a filterable list of trainers sourced from `trainerPublicProfiles`, ordered by
ascending distance (haversine, client-side) when device location is available, or by
`displayName` ascending when location is denied or unavailable.

`TrainerPublicProfileScreen` is a full-detail screen accessible via `/coach/trainer/:uid`
(sub-route under ShellRoute), displaying trainer hero, placeholder stats, bio, and the CTA
"PEDIR VÍNCULO" stub.

Both screens delegate data loading to Riverpod providers and follow existing `AsyncValue.when()`
patterns for loading / error / data states.

---

## Requirements — `coach-discovery-ui`

| ID | Name | Strength |
|----|------|----------|
| REQ-COACH-DISC-UI-001 | `TrainersListScreen` replaces `AthleteCoachView` stub | MUST |
| REQ-COACH-DISC-UI-002 | `TrainersListScreen` loading state | MUST |
| REQ-COACH-DISC-UI-003 | `TrainersListScreen` error state | MUST |
| REQ-COACH-DISC-UI-004 | `TrainersListScreen` empty state | MUST |
| REQ-COACH-DISC-UI-005 | `TrainersListScreen` renders `TrainerListTile` per trainer | MUST |
| REQ-COACH-DISC-UI-006 | `TrainerListTile` fields rendered | MUST |
| REQ-COACH-DISC-UI-007 | Specialty filter chips | MUST |
| REQ-COACH-DISC-UI-008 | Specialty filter changes visible list | MUST |
| REQ-COACH-DISC-UI-009 | Tile tap navigates to trainer profile | MUST |
| REQ-COACH-DISC-UI-010 | Map view toggle — stub | MUST |
| REQ-COACH-DISC-UI-011 | Location fallback to `listAll` | MUST |
| REQ-COACH-DISC-UI-012 | `TrainerPublicProfileScreen` — loading state | MUST |
| REQ-COACH-DISC-UI-013 | `TrainerPublicProfileScreen` — not-found state | MUST |
| REQ-COACH-DISC-UI-014 | `TrainerPublicProfileScreen` — error state | MUST |
| REQ-COACH-DISC-UI-015 | `TrainerPublicProfileScreen` — data: all sections rendered | MUST |
| REQ-COACH-DISC-UI-016 | `TrainerPublicProfileScreen` — CTA stub SnackBar | MUST |
| REQ-COACH-DISC-UI-017 | `TrainerPublicProfileScreen` — back navigation | MUST |
| REQ-COACH-DISC-UI-018 | Router sub-route `/coach/trainer/:uid` | MUST |

---

## REQ-COACH-DISC-UI-001 — `TrainersListScreen` replaces `AthleteCoachView` stub

`AthleteCoachView` MUST render `TrainersListScreen` instead of its current static stub text.
`CoachScreen` MUST continue dispatching to `AthleteCoachView` when `role == athlete` — no changes
to `coach_screen.dart` are permitted.

The bottom navigation bar (ShellRoute shell) MUST remain visible when `TrainersListScreen` is
shown — it is NOT a full-screen immersive route.

*(No dedicated SCENARIO — structural requirement validated by widget tree presence of
`TrainersListScreen` inside the `Coach` tab in SCENARIO-425.)*

---

## REQ-COACH-DISC-UI-002 — `TrainersListScreen` loading state

While the trainer discovery provider is in an `AsyncLoading` state, `TrainersListScreen` MUST
display a loading indicator (`CircularProgressIndicator` with `palette.accent` color).
No trainer tiles MUST be rendered during loading.

#### SCENARIO-425: `TrainersListScreen` shows loader while provider resolves

- GIVEN `trainerSearchProvider` is in the `AsyncLoading` state
- WHEN `TrainersListScreen` renders inside a `ProviderScope`
- THEN a `CircularProgressIndicator` is visible
- AND no `TrainerListTile` widgets are in the widget tree

---

## REQ-COACH-DISC-UI-003 — `TrainersListScreen` error state

When `trainerSearchProvider` resolves to an `AsyncError`, `TrainersListScreen` MUST display an
error message text. A retry mechanism (button or gesture) MUST be present.

#### SCENARIO-426: `TrainersListScreen` shows error message on provider failure

- GIVEN `trainerSearchProvider` resolves to an `AsyncError`
- WHEN `TrainersListScreen` renders
- THEN an error message text is visible in the widget tree
- AND no `TrainerListTile` widgets are rendered

---

## REQ-COACH-DISC-UI-004 — `TrainersListScreen` empty state

When `trainerSearchProvider` resolves to an empty list (no trainers in the geohash radius, or no
matches for the active specialty filter), `TrainersListScreen` MUST display an empty state message.
No trainer tiles MUST be rendered.

#### SCENARIO-427: `TrainersListScreen` shows empty state when provider returns no trainers

- GIVEN `trainerSearchProvider` resolves to an empty `List<TrainerPublicProfile>`
- WHEN `TrainersListScreen` renders
- THEN an empty state message is visible (e.g. "No hay entrenadores en tu zona")
- AND no `TrainerListTile` widgets are in the widget tree

---

## REQ-COACH-DISC-UI-005 — `TrainersListScreen` renders `TrainerListTile` per trainer

When `trainerSearchProvider` resolves to a non-empty list, `TrainersListScreen` MUST render one
`TrainerListTile` per `TrainerPublicProfile` in the list, in the order returned by the provider.

#### SCENARIO-428: `TrainersListScreen` renders one tile per trainer in provider result

- GIVEN `trainerSearchProvider` resolves to a list of 3 `TrainerPublicProfile` instances with
  `displayName` values `'Ana'`, `'Bruno'`, `'Carla'`
- WHEN `TrainersListScreen` renders
- THEN exactly 3 `TrainerListTile` widgets are present in the widget tree
- AND the texts 'Ana', 'Bruno', 'Carla' are each visible

---

## REQ-COACH-DISC-UI-006 — `TrainerListTile` fields rendered

Each `TrainerListTile` MUST display all of the following:

1. A `PostAvatar` widget with the trainer's `avatarUrl` (or initials fallback when `null`).
2. `displayName` as title text.
3. Specialty chip displaying the trainer's `trainerSpecialty` label (or omitted when `null`).
4. Hourly rate text in the format `"$X / hr"` (or omitted when `trainerHourlyRate` is `null`).
5. Distance text in the format `"X km"` when `distanceKm` is known, or `"—"` when location
   is unavailable.

No rating value or star widget MUST be displayed (rating is deferred — see Out of Scope).

*(Covered structurally by SCENARIO-428 and SCENARIO-429 below.)*

#### SCENARIO-429: `TrainerListTile` renders specialty chip and distance when data is present

- GIVEN a `TrainerListTile` with `displayName: 'Ana'`, `trainerSpecialty: TrainerSpecialty.yoga`,
  `trainerHourlyRate: 5000`, `distanceKm: 3.2`
- WHEN the tile renders
- THEN the specialty text `'yoga'` (or its display label) is visible
- AND a text containing `'3.2'` or `'3'` (distance representation) is visible
- AND a text containing `'5000'` (or formatted rate) is visible
- AND NO star or rating widget is present in the tile subtree

---

## REQ-COACH-DISC-UI-007 — Specialty filter chips

`TrainersListScreen` MUST render a horizontal scrollable row of filter chips containing:
- One chip per `TrainerSpecialty` value (10 chips) labeled with the specialty name.
- One "Todos" chip (no filter applied).

At most one chip MUST be selected at a time. `"Todos"` is selected by default.

#### SCENARIO-430: specialty filter chip row contains 11 chips including "Todos"

- GIVEN `TrainersListScreen` renders with `trainerSearchProvider` in any data state
- WHEN the chip row renders
- THEN there are 11 selectable chip widgets visible (10 specialties + "Todos")
- AND the "Todos" chip is in the selected state by default

---

## REQ-COACH-DISC-UI-008 — Specialty filter changes visible list

Tapping a specialty chip MUST update the visible trainer list to show only trainers whose
`trainerSpecialty` matches the selected chip. Tapping "Todos" MUST show all trainers.

This filter MAY be applied client-side on the already-loaded result set (re-querying the provider
with a `specialty` parameter is also acceptable; the spec does not mandate one approach).

#### SCENARIO-431: tapping a specialty chip filters the visible trainer list

- GIVEN `TrainersListScreen` shows 3 trainers: Ana (yoga), Bruno (crossfit), Carla (yoga)
- WHEN the user taps the "yoga" specialty chip
- THEN only Ana and Carla are visible
- AND Bruno is NOT in the visible widget tree

---

## REQ-COACH-DISC-UI-009 — Tile tap navigates to trainer profile

Tapping a `TrainerListTile` MUST push the route `/coach/trainer/:uid` where `:uid` is the
trainer's `uid`.

#### SCENARIO-432: tapping a tile pushes the trainer profile route

- GIVEN `TrainersListScreen` renders a tile for trainer with `uid: 'trainer-99'`
- WHEN the user taps that tile
- THEN the router navigates to `/coach/trainer/trainer-99`

---

## REQ-COACH-DISC-UI-010 — Map view toggle — stub

`TrainersListScreen` MUST render a toggle button labeled `"MAPA"` in the header area.
Tapping `"MAPA"` MUST display a "Próximamente" message (via `SnackBar` or inline placeholder).
The map view MUST NOT render any actual map widget. The toggle MUST remain visible.

*(No dedicated SCENARIO — validated as part of smoke-test widget assertions in the UI test suite.)*

---

## REQ-COACH-DISC-UI-011 — Location fallback to `listAll`

When device location permission is denied or when the GPS fix fails, `trainerSearchProvider` (or
`currentLocationProvider`) MUST fall back to calling `TrainerPublicProfileRepository.listAll()`
instead of `listByGeohashPrefix`. The screen MUST render normally with this fallback list —
no error state is shown purely because location is unavailable.

Distance column MUST show `"—"` for all tiles when location is not available.

*(Validated as a provider unit test — GIVEN permission denied WHEN trainerSearchProvider resolves
THEN result comes from `listAll`. Covered in provider test suite, not a standalone SCENARIO number.)*

---

## REQ-COACH-DISC-UI-012 — `TrainerPublicProfileScreen` — loading state

While `trainerProfileProvider(uid)` is in `AsyncLoading`, `TrainerPublicProfileScreen` MUST render
a `CircularProgressIndicator`. No hero, stats, or CTA MUST be shown during loading.

*(Covered by widget tests analogous to SCENARIO-376 in historial spec — no dedicated number
assigned to avoid over-numbering. Counted in total SCENARIO range via test file.)*

---

## REQ-COACH-DISC-UI-013 — `TrainerPublicProfileScreen` — not-found state

When `trainerProfileProvider(uid)` resolves to `null`, `TrainerPublicProfileScreen` MUST display:
- A "Perfil no encontrado" message (or `CoachStrings` constant equivalent).
- A button that navigates back.

*(Covered by widget test — no dedicated SCENARIO number.)*

---

## REQ-COACH-DISC-UI-014 — `TrainerPublicProfileScreen` — error state

When `trainerProfileProvider(uid)` resolves to an `AsyncError`, `TrainerPublicProfileScreen`
MUST display an error message and a retry CTA.

*(Covered by widget test — no dedicated SCENARIO number.)*

---

## REQ-COACH-DISC-UI-015 — `TrainerPublicProfileScreen` — data: all sections rendered

When `trainerProfileProvider(uid)` resolves to a non-null `TrainerPublicProfile`,
`TrainerPublicProfileScreen` MUST render all of the following sections:

1. **Hero** (`TrainerProfileHero`): full-bleed area with `PostAvatar` (or avatar image),
   `displayName`, and `trainerSpecialty` chip. `TrainerProfileHero` is a NEW widget —
   `PublicProfileHero` (feed) MUST NOT be reused (incompatible view-model coupling).
2. **Stats row** (`TrainerStatsRow`): exactly 3 stat tiles with labels `RESEÑAS`, `AÑOS EXP`,
   `ALUMNOS`, all showing placeholder value `"–"`. `PublicProfileStatsRow` (feed) MUST NOT be
   reused (different columns).
3. **Bio text**: `trainerBio` rendered when non-null and non-empty. When null or empty, the bio
   section MUST be omitted (not shown as blank space).
4. **Hourly rate**: displays `"$X / hr"` when `trainerHourlyRate` is non-null; omitted otherwise.
5. **CTA** (`TrainerContactCtaStub`): button labeled `"PEDIR VÍNCULO"` — always rendered (not
   hidden or disabled), even when the action is a stub.

#### SCENARIO-433: `TrainerPublicProfileScreen` renders hero, stats, bio, rate, and CTA

- GIVEN `trainerProfileProvider('t1')` resolves to a `TrainerPublicProfile` with
  `uid: 't1'`, `displayName: 'Ana García'`, `trainerSpecialty: TrainerSpecialty.yoga`,
  `trainerHourlyRate: 5000`, and `trainerBio: 'Especialista en yoga terapéutico.'` (sourced from
  `UserProfile.trainerBio` via the provider — see Domain Rules)
- WHEN `TrainerPublicProfileScreen` renders
- THEN the text 'Ana García' is visible
- AND a specialty chip with text 'yoga' (or display label) is visible
- AND the text 'RESEÑAS' is visible with value '–'
- AND the text 'AÑOS EXP' is visible with value '–'
- AND the text 'ALUMNOS' is visible with value '–'
- AND the text 'Especialista en yoga terapéutico.' is visible
- AND a button with text 'PEDIR VÍNCULO' is visible

---

## REQ-COACH-DISC-UI-016 — `TrainerPublicProfileScreen` — CTA stub SnackBar

Tapping the `"PEDIR VÍNCULO"` button MUST display a `SnackBar` with the text
`"Próximamente — Etapa 3"`. No call to `TrainerLinkRepository` MUST be made.

#### SCENARIO-434: tapping "PEDIR VÍNCULO" shows SnackBar stub

- GIVEN `TrainerPublicProfileScreen` is rendered with a valid trainer profile
- WHEN the user taps the "PEDIR VÍNCULO" button
- THEN a `SnackBar` with text `"Próximamente — Etapa 3"` is displayed
- AND no `TrainerLinkRepository` method is invoked

---

## REQ-COACH-DISC-UI-017 — `TrainerPublicProfileScreen` — back navigation

The screen MUST provide a back navigation control. Tapping it MUST invoke `context.pop()`.
The bottom navigation bar MUST remain visible (the route is under ShellRoute).

*(Covered by router navigation test — no dedicated SCENARIO number.)*

---

## REQ-COACH-DISC-UI-018 — Router sub-route `/coach/trainer/:uid`

The GoRoute for `/coach/trainer/:uid` MUST be registered as a sub-route under the existing
`/coach` GoRoute (which is itself inside the ShellRoute).

The route MUST instantiate `TrainerPublicProfileScreen(uid: state.pathParameters['uid']!)`.
The `TreinoBottomBar` MUST remain visible when this route is active (ShellRoute shell persists).

This follows the identical structural pattern as `/feed/profile/:uid`.

*(No dedicated SCENARIO — covered by SCENARIO-432 tap navigation and SCENARIO-433 profile render.)*

---

## Domain Rules / Invariants

1. **No direct query on `users/{uid}`**: discovery queries MUST target `trainerPublicProfiles`
   only. Querying `users` collection for trainer fields is forbidden — the Firestore rule is
   owner-only and any such query will fail at runtime.

2. **Geohash5 prefix**: the geohash prefix passed to `listByGeohashPrefix` MUST be exactly 5
   characters. Using fewer characters increases result set size unpredictably; using more may miss
   trainers near cell boundaries. The 5-char prefix is the defined contract.

3. **Client-side specialty filter**: specialty filtering happens on the Dart result set, NOT via
   a Firestore compound index on `trainerGeohash + trainerSpecialty`. This avoids index creation
   overhead. The consequence is that the full geohash result set is loaded before filtering.

4. **Client-side distance sort**: the list is returned from Firestore ordered by `displayName`
   (deterministic, Firestore-native). After haversine computation, the provider MAY re-sort by
   `distanceKm` ascending. Distance sort is consumer responsibility — the repository contract
   specifies `displayName` order only.

5. **Dual-write atomicity**: `UserRepository.update()` MUST use `WriteBatch` for any update that
   touches trainer fields. A partial write (one collection updated, the other not) is an
   invariant violation.

6. **Trainer fields detection**: the dual-write is triggered by the presence of any of these keys
   in the `data` map: `displayName`, `avatarUrl`, `trainerSpecialty`, `trainerGeohash`,
   `trainerLatitude`, `trainerLongitude`, `trainerHourlyRate`. This check is a key-presence
   check on the incoming map — not a value-change diff.

7. **`trainerBio` is NOT in `trainerPublicProfiles`**: bio is stored only in `users/{uid}`.
   `TrainerPublicProfileScreen` requires a separate read of `users/{uid}` (or a combined
   provider) to display the bio. The `trainerPublicProfiles` document deliberately excludes bio
   to keep the public document small and scoped to discovery fields only.
   **Spec assumption**: the `trainerProfileProvider` for `TrainerPublicProfileScreen` reads from
   `users/{uid}` (owner-readable for the trainer; athlete-readable if `trainerBio` is moved to
   `trainerPublicProfiles`). Design phase MUST resolve whether bio is served from
   `trainerPublicProfiles` or from a separate `users/{uid}` read. Until resolved, this spec
   treats bio as available to the screen via the provider (source is design's choice).

8. **Rating/reviews placeholder**: `TrainerStatsRow` shows `"–"` for all 3 stats. No stats
   computation or reads beyond the profile document are permitted in this change.

9. **CTA is always rendered**: `"PEDIR VÍNCULO"` button MUST be visible and tappable regardless
   of trainer-athlete relationship state. It is not conditional on any link status. The conditional
   CTA logic arrives in Etapa 3.

10. **`CoachStrings` centralization**: all user-visible copy introduced by this change (empty
    states, CTA labels, SnackBar messages, specialty display labels, section headings) MUST be
    defined as constants in `CoachStrings` — no inline string literals in widget `build` methods.

11. **`PostAvatar` reuse**: `PostAvatar` from the existing widget library MUST be used for avatar
    rendering in both `TrainerListTile` and `TrainerProfileHero`. New avatar widgets are not
    permitted.

12. **`trainerSpecialty` free-form fallback**: existing `UserProfile.trainerSpecialty` is stored
    as a freeform string. `TrainerSpecialty.fromString()` returns `null` for unrecognized values.
    When `null`, the specialty chip is omitted from the tile and hero — no sentinel/fallback label
    is displayed.

---

## Out of Scope

The following are explicitly deferred and MUST NOT be implemented in this change:

- **Map view (radar/Google Maps integration)**: the "MAPA" toggle is a visible stub only.
  Actual map rendering (radar, pins, Google Maps SDK) is deferred to Etapa 5.5 or Fase 6.

- **Rating / reviews system**: `TrainerStatsRow` shows `"–"` placeholders. The underlying data
  model, Firestore collection, and UI for reviews are deferred to Fase 5.5 / Fase 6.

- **Real "PEDIR VÍNCULO" action**: `TrainerLinkRepository.request()` is NOT called in this change.
  The real CTA wiring arrives in Etapa 3 (`coach-link-lifecycle`).

- **Trainer profile editing UI**: the dual-write infrastructure is ready, but the UI screen where
  a trainer edits their specialty, location, and hourly rate is NOT delivered here. Trainers are
  seeded manually for testing.

- **Sort by distance as repository contract**: the repository returns results ordered by
  `displayName`. Distance-based reordering is a client/provider concern deferred to implementation
  (not a repo-level contract in this spec).

- **Pagination**: the list is flat (no cursor-based pagination). Firestore pagination is a
  future concern.

- **Trainer profile editing from the profile screen**: no edit button or navigation to
  profile-edit flow is part of `TrainerPublicProfileScreen`.

- **Payment / subscription flows**: `trainerHourlyRate` is informational display only.

- **Changes to `userPublicProfiles`**: privacy boundary is preserved. Trainer discovery fields
  are NOT added to `userPublicProfiles`.

- **Changes to `TrainerLinkRepository`**: read-only consumer in future etapa.

- **Changes to `coach_screen.dart`** and **`trainer_coach_view.dart`**: these files are untouched.

---

*Generated by sdd-spec — 2026-05-20*

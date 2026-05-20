# Spec: wire-real-stats (Fase 4 Etapa 6)

**Change**: wire-real-stats
**PRs**: 4 chained (Home → Own Profile → Public Profile → Check-in)
**SCENARIO range**: 298–338

---

## REQ Matrix

| ID | Section | PR | Strength | Description |
|---|---|---|---|---|
| REQ-WRH-001 | A — Home | PR#1 | MUST | WeeklyInsights DTO gains `streak: int` and `monthSessionsCount: int` (additive, default 0) |
| REQ-WRH-002 | A — Home | PR#1 | MUST | `weeklyInsightsProvider` computes `streak` via the canonical streak algorithm |
| REQ-WRH-003 | A — Home | PR#1 | MUST | `weeklyInsightsProvider` computes `monthSessionsCount` for the current calendar month |
| REQ-WRH-004 | A — Home | PR#1 | MUST | `EstaSemanaCard` is a `ConsumerWidget` reading `weeklyInsightsProvider` |
| REQ-WRH-005 | A — Home | PR#1 | SHOULD | Loading state renders skeleton indicator |
| REQ-WRH-006 | A — Home | PR#1 | MUST | Data state renders: streak + "DÍAS" + copy + day strip + SEMANA count + MES count + muscle map placeholder |
| REQ-WRH-007 | A — Home | PR#1 | MUST | Error state renders minimal fallback text |
| REQ-WRH-008 | A — Home | PR#1 | MUST | Card tap navigates to `/home/insights` |
| REQ-WRH-009 | A — Home | PR#1 | MUST | Streak copy follows mockup: trained-today vs not-yet-trained variants |
| REQ-WRP-001 | B — Own Profile | PR#2 | MUST | New `userSessionStatsProvider` (FutureProvider) returns `{totalSessions, totalVolumeKg, streak}` |
| REQ-WRP-002 | B — Own Profile | PR#2 | MUST | Provider computes `totalSessions` as count of all finished sessions |
| REQ-WRP-003 | B — Own Profile | PR#2 | MUST | Provider computes `totalVolumeKg` as sum of `session.totalVolumeKg` for all finished sessions |
| REQ-WRP-004 | B — Own Profile | PR#2 | MUST | Provider reuses the canonical streak algorithm (shared helper or identical logic) |
| REQ-WRP-005 | B — Own Profile | PR#2 | MUST | New `kFormat(num v)` helper: returns `"Xk"` when v >= 1000, else integer string |
| REQ-WRP-006 | B — Own Profile | PR#2 | MUST | `ProfileScreen` renders 3-stat row: SESIONES / VOLUMEN KG / RACHA above existing PERFIL scaffold |
| REQ-WRP-007 | B — Own Profile | PR#2 | MUST | SESIONES and VOLUMEN KG use `palette.accent`; RACHA uses `palette.highlight` |
| REQ-WRP-008 | B — Own Profile | PR#2 | MUST | Loading state shows `'--'` for each value |
| REQ-WRP-009 | B — Own Profile | PR#2 | MUST | Error state shows `'--'` for each value |
| REQ-WRP-010 | B — Own Profile | PR#2 | MUST | Sign-out button and PERFIL text are preserved |
| REQ-WRX-001 | C — Public Profile | PR#3 | MUST | `UserPublicProfile` gains 4 nullable int fields: `workoutsCount?`, `racha?`, `followersCount?`, `followingCount?` |
| REQ-WRX-002 | C — Public Profile | PR#3 | MUST | `UserPublicProfileRepository` supports partial updates to these counter fields |
| REQ-WRX-003 | C — Public Profile | PR#3 | MUST | `SessionRepository.finish()` updates `userPublicProfiles/{uid}` with `workoutsCount` + `racha` after session finalization; wrapped in try/catch |
| REQ-WRX-004 | C — Public Profile | PR#3 | MUST | `FriendshipRepository.accept()` updates both members' `followersCount` / `followingCount`; wrapped in try/catch |
| REQ-WRX-005 | C — Public Profile | PR#3 | MUST | `FriendshipRepository.delete()` updates both members' counts; wrapped in try/catch |
| REQ-WRX-006 | C — Public Profile | PR#3 | MUST | `PublicProfileView` DTO gains `workoutsCount`, `racha`, `followersCount`, `followingCount` (all nullable int) |
| REQ-WRX-007 | C — Public Profile | PR#3 | MUST | `publicProfileViewProvider` sources the 4 stats from `userPublicProfileProvider(uid)` |
| REQ-WRX-008 | C — Public Profile | PR#3 | MUST | `PublicProfileStatsRow` is parameterized with the 4 stat values; displays WORKOUTS / RACHA / SEGUIDORES / SIGUIENDO |
| REQ-WRX-009 | C — Public Profile | PR#3 | MUST | Null values render as `'0'` |
| REQ-WRX-010 | C — Public Profile | PR#3 | MUST | Cross-feature write failures MUST be logged; MUST NOT propagate upstream as thrown exceptions |
| REQ-WRC-001 | D — Check-in | PR#4 | MUST | New Freezed model `CheckIn` with fields: `uid`, `date` (YYYY-MM-DD local), `checkedInAt`, `gymId?`, `gymName?` |
| REQ-WRC-002 | D — Check-in | PR#4 | MUST | `CheckInRepository` exposes `getTodayForUser(uid)` and `createTodayCheckIn(uid, {inGym, gymId?, gymName?})` |
| REQ-WRC-003 | D — Check-in | PR#4 | MUST | `todayCheckInProvider` (FutureProvider) returns today's check-in for the current user or null |
| REQ-WRC-004 | D — Check-in | PR#4 | MUST | Firestore rules restrict `users/{uid}/checkIns/{date}` to owner read/write only |
| REQ-WRC-005 | D — Check-in | PR#4 | MUST | `CheckInDialog` renders: location icon + "¿ESTÁS EN EL GYM HOY?" header + contextual subtext + "NO" / "SÍ, ENTRÉ" buttons |
| REQ-WRC-006 | D — Check-in | PR#4 | MUST | `FeedScreen` shows `CheckInDialog` on mount IFF today's check-in is absent AND dialog has not been shown this session |
| REQ-WRC-007 | D — Check-in | PR#4 | MUST | "SÍ, ENTRÉ" creates check-in with `inGym: true` and the user's `gymId` / looked-up `gymName`, then dismisses dialog |
| REQ-WRC-008 | D — Check-in | PR#4 | MUST | "NO" creates check-in with `inGym: false`, null gym fields, then dismisses dialog (records dismissal to prevent re-trigger) |
| REQ-WRC-009 | D — Check-in | PR#4 | MUST | Dialog gym name lookup MUST use existing `gymNameFromId` helper |
| REQ-WRC-010 | D — Check-in | PR#4 | MUST | `rules.test.js` gains 3 new scenarios for checkIn owner-write, non-owner-read-blocked, non-owner-write-blocked |
| REQ-WRA-001 | Cross-cutting | All | MUST | All colors via `AppPalette.of(context)` — no hex literals |
| REQ-WRA-002 | Cross-cutting | All | MUST | All icons via `TreinoIcon.X` — no `PhosphorIcons.X` direct usage |
| REQ-WRA-003 | Cross-cutting | All | MUST | Spacing values restricted to scale: 8 / 12 / 14 / 18 / 20 |
| REQ-WRA-004 | Cross-cutting | All | MUST | Strict TDD across all 4 PRs |
| REQ-WRA-005 | Cross-cutting | All | MUST | New screens MUST NOT add their own Scaffold/AppBackground/SafeArea — `_ShellScaffold` provides these |
| REQ-WRA-006 | Cross-cutting | All | MUST | `UserPublicProfile` field additions MUST be nullable and additive (no breaking changes to existing reads) |

---

## Section A — Home (PR#1): REQ-WRH-*

### Requirement: WeeklyInsights DTO Extension (REQ-WRH-001)

`WeeklyInsights` MUST gain `streak: int` and `monthSessionsCount: int` as additive fields, both defaulting to `0`. Existing fields MUST remain unchanged.

#### SCENARIO-298: DTO serializes with new fields

- GIVEN a `WeeklyInsights` JSON payload that omits `streak` and `monthSessionsCount`
- WHEN the model is deserialized
- THEN `streak` defaults to `0` and `monthSessionsCount` defaults to `0`
- AND all pre-existing fields retain their values

#### SCENARIO-299: DTO serializes new fields when present

- GIVEN a `WeeklyInsights` JSON payload containing `streak: 7` and `monthSessionsCount: 12`
- WHEN the model is deserialized
- THEN `streak` equals `7` and `monthSessionsCount` equals `12`

---

### Requirement: Streak Algorithm (REQ-WRH-002)

`weeklyInsightsProvider` MUST compute `streak` by: (1) building a Set of local calendar dates from all finished sessions; (2) if today is in the set, counting backwards from today until a gap; (3) if today is NOT in the set, counting backwards from yesterday until a gap. The result is the count of consecutive trained days.

#### SCENARIO-300: Streak when trained today

- GIVEN the user has finished sessions on the last 5 consecutive days including today (local date)
- WHEN `weeklyInsightsProvider` resolves
- THEN `streak` equals `5`

#### SCENARIO-301: Streak when not yet trained today

- GIVEN the user trained the 4 days before today but NOT today
- WHEN `weeklyInsightsProvider` resolves
- THEN `streak` equals `4` (gap-check starts from yesterday)

#### SCENARIO-302: Streak resets after a missed day

- GIVEN the user trained today and 3 days ago but NOT yesterday
- WHEN `weeklyInsightsProvider` resolves
- THEN `streak` equals `1` (only today is consecutive)

#### SCENARIO-303: Streak is zero for a user with no finished sessions

- GIVEN the user has no finished sessions
- WHEN `weeklyInsightsProvider` resolves
- THEN `streak` equals `0`

---

### Requirement: Month Session Count (REQ-WRH-003)

`weeklyInsightsProvider` MUST compute `monthSessionsCount` as the count of finished sessions whose `startedAt.toLocal()` falls in the same calendar month and year as `DateTime.now().toLocal()`.

#### SCENARIO-304: Count includes only current-month sessions

- GIVEN 4 finished sessions this month and 6 from prior months
- WHEN `weeklyInsightsProvider` resolves
- THEN `monthSessionsCount` equals `4`

---

### Requirement: EstaSemanaCard States (REQ-WRH-004 through REQ-WRH-009)

`EstaSemanaCard` MUST be a `ConsumerWidget` reading `weeklyInsightsProvider`. It MUST render three distinct states based on provider async state.

#### SCENARIO-305: Loading state shows skeleton

- GIVEN `weeklyInsightsProvider` is in loading state
- WHEN `EstaSemanaCard` builds
- THEN a progress indicator or shimmer is visible
- AND no numeric stats are shown

#### SCENARIO-306: Data state renders all stats

- GIVEN `weeklyInsightsProvider` resolves with data
- WHEN `EstaSemanaCard` builds
- THEN streak count and "DÍAS" label are visible
- AND the day strip shows filled dots for `daysTrained` days
- AND SEMANA count (`sessionsCount`) is displayed
- AND MES count (`monthSessionsCount`) is displayed
- AND muscle map placeholder is shown

#### SCENARIO-307: Streak copy — trained today

- GIVEN `weeklyInsightsProvider` data has `streak >= 1` AND today is in the trained set
- WHEN `EstaSemanaCard` builds
- THEN motivational copy reads "No rompas la racha — entrenaste hoy."

#### SCENARIO-308: Streak copy — not yet trained today

- GIVEN `weeklyInsightsProvider` data has `streak >= 0` AND today is NOT in the trained set
- WHEN `EstaSemanaCard` builds
- THEN motivational copy reads "No rompas la racha — ¿hoy entrenás?"

#### SCENARIO-309: Error state shows fallback

- GIVEN `weeklyInsightsProvider` emits an error
- WHEN `EstaSemanaCard` builds
- THEN fallback text "No pudimos cargar Esta Semana" is visible
- AND no stats values are shown

#### SCENARIO-310: Card tap navigates to insights

- GIVEN `EstaSemanaCard` is rendered in any state
- WHEN the user taps the card
- THEN the router navigates to `/home/insights`

---

## Section B — Own Profile (PR#2): REQ-WRP-*

### Requirement: userSessionStatsProvider (REQ-WRP-001 through REQ-WRP-004)

A new `userSessionStatsProvider` (FutureProvider) MUST return `{totalSessions, totalVolumeKg, streak}` for the authenticated user, computing each value from finished sessions.

#### SCENARIO-311: Provider returns correct totals

- GIVEN the user has 143 finished sessions with a combined `totalVolumeKg` of 92000
- WHEN `userSessionStatsProvider` resolves
- THEN `totalSessions` equals `143`
- AND `totalVolumeKg` equals `92000`

#### SCENARIO-312: Provider returns zero totals for new user

- GIVEN the user has no finished sessions
- WHEN `userSessionStatsProvider` resolves
- THEN `totalSessions` equals `0`, `totalVolumeKg` equals `0`, and `streak` equals `0`

---

### Requirement: kFormat Helper (REQ-WRP-005)

A `kFormat(num v)` function MUST return `"${(v/1000).toStringAsFixed(0)}k"` when `v >= 1000`, and `"${v.toInt()}"` otherwise.

#### SCENARIO-313: kFormat for value >= 1000

- GIVEN `v = 92000`
- WHEN `kFormat(v)` is called
- THEN the result is `"92k"`

#### SCENARIO-314: kFormat for value < 1000

- GIVEN `v = 750`
- WHEN `kFormat(v)` is called
- THEN the result is `"750"`

#### SCENARIO-315: kFormat boundary at exactly 1000

- GIVEN `v = 1000`
- WHEN `kFormat(v)` is called
- THEN the result is `"1k"`

---

### Requirement: ProfileScreen 3-stat Row (REQ-WRP-006 through REQ-WRP-010)

`ProfileScreen` MUST render a 3-stat row above the existing content. Loading and error states show `'--'`. Existing sign-out button and PERFIL text MUST be preserved.

#### SCENARIO-316: Stats row renders with data

- GIVEN `userSessionStatsProvider` resolves with data
- WHEN `ProfileScreen` builds
- THEN "SESIONES" label + totalSessions value in `palette.accent` is shown
- AND "VOLUMEN KG" label + kFormat(totalVolumeKg) in `palette.accent` is shown
- AND "RACHA" label + streak value in `palette.highlight` is shown

#### SCENARIO-317: Stats row shows dashes while loading

- GIVEN `userSessionStatsProvider` is in loading state
- WHEN `ProfileScreen` builds
- THEN each stat value displays `'--'`

#### SCENARIO-318: Stats row shows dashes on error

- GIVEN `userSessionStatsProvider` emits an error
- WHEN `ProfileScreen` builds
- THEN each stat value displays `'--'`
- AND no exception propagates to the UI

#### SCENARIO-319: Existing ProfileScreen content is preserved

- GIVEN `ProfileScreen` renders (any stats state)
- WHEN the screen builds
- THEN the PERFIL label and sign-out button remain visible and functional

---

## Section C — Public Profile (PR#3): REQ-WRX-*

### Requirement: UserPublicProfile Field Extension (REQ-WRX-001 through REQ-WRX-002)

`UserPublicProfile` MUST gain `workoutsCount?`, `racha?`, `followersCount?`, `followingCount?` as nullable int fields. Existing documents without these fields MUST still deserialize correctly.

#### SCENARIO-320: Legacy document without new fields deserializes safely

- GIVEN a Firestore `userPublicProfiles` document that has no counter fields
- WHEN `UserPublicProfile.fromJson()` is called
- THEN all 4 new fields are `null`
- AND no exception is thrown

---

### Requirement: Cross-Feature Counter Writes (REQ-WRX-003 through REQ-WRX-005)

`SessionRepository.finish()` MUST update `userPublicProfiles/{uid}` with computed `workoutsCount` and `racha`. `FriendshipRepository.accept()` and `FriendshipRepository.delete()` MUST update both members' follower/following counts. All cross-feature writes MUST be wrapped in try/catch and MUST NOT block the primary operation.

#### SCENARIO-321: Session finish updates public counters

- GIVEN a user completes and finalizes a session
- WHEN `SessionRepository.finish()` executes
- THEN `userPublicProfiles/{uid}` is updated with the new `workoutsCount` and `racha`
- AND if the Firestore update fails, the session is still marked finished
- AND the error is logged

#### SCENARIO-322: Friendship accept updates follower counts

- GIVEN user A accepts a friendship request from user B
- WHEN `FriendshipRepository.accept()` executes
- THEN `userPublicProfiles/{uidA}.followersCount` is incremented
- AND `userPublicProfiles/{uidB}.followingCount` is incremented
- AND a write failure does not throw upstream

#### SCENARIO-323: Friendship delete decrements counts

- GIVEN an accepted friendship between user A and user B is deleted
- WHEN `FriendshipRepository.delete()` executes
- THEN both users' `followersCount` / `followingCount` in `userPublicProfiles` are decremented
- AND a write failure does not throw upstream

---

### Requirement: PublicProfileStatsRow Parameterization (REQ-WRX-006 through REQ-WRX-009)

`PublicProfileView` DTO MUST expose `workoutsCount?`, `racha?`, `followersCount?`, `followingCount?`. `publicProfileViewProvider` MUST source them from `userPublicProfileProvider`. `PublicProfileStatsRow` MUST accept these as parameters and render null as `'0'`.

#### SCENARIO-324: Stats row renders real values

- GIVEN a public profile with `workoutsCount: 89`, `racha: 23`, `followersCount: 412`, `followingCount: 284`
- WHEN `PublicProfileStatsRow` builds
- THEN it displays "89", "23", "412", "284" in the correct columns

#### SCENARIO-325: Stats row renders null values as zero

- GIVEN a legacy public profile where all 4 counter fields are null
- WHEN `PublicProfileStatsRow` builds
- THEN each stat displays `'0'`

---

## Section D — Check-in (PR#4): REQ-WRC-*

### Requirement: CheckIn Model (REQ-WRC-001)

A new Freezed model `CheckIn` MUST have: `uid: String`, `date: String` (YYYY-MM-DD local), `checkedInAt: Timestamp`, `gymId: String?`, `gymName: String?`.

#### SCENARIO-326: CheckIn serializes and deserializes correctly

- GIVEN a Firestore document at `users/{uid}/checkIns/{date}` with all fields populated
- WHEN `CheckIn.fromJson()` is called
- THEN all fields are correctly mapped
- AND `gymId` and `gymName` may be null without error

---

### Requirement: CheckInRepository (REQ-WRC-002 through REQ-WRC-003)

`CheckInRepository` MUST expose `getTodayForUser(uid)` returning today's `CheckIn` or `null`, and `createTodayCheckIn(uid, {inGym, gymId?, gymName?})` upserting today's doc. `todayCheckInProvider` MUST return the current user's check-in for today or null.

#### SCENARIO-327: getTodayForUser returns null when no check-in exists

- GIVEN no document at `users/{uid}/checkIns/{today}`
- WHEN `getTodayForUser(uid)` is called
- THEN the result is `null`

#### SCENARIO-328: getTodayForUser returns existing check-in

- GIVEN a document exists at `users/{uid}/checkIns/{today}`
- WHEN `getTodayForUser(uid)` is called
- THEN the result is a `CheckIn` with matching fields

#### SCENARIO-329: createTodayCheckIn upserts the document

- GIVEN `createTodayCheckIn(uid, inGym: true, gymId: "gym1", gymName: "Smart Fit")` is called
- WHEN the operation completes
- THEN a document exists at `users/{uid}/checkIns/{today}` with `gymId: "gym1"` and `gymName: "Smart Fit"`

---

### Requirement: Firestore Rules (REQ-WRC-004)

`users/{uid}/checkIns/{date}` MUST restrict read and write to the authenticated owner only.

#### SCENARIO-330: Owner can write own checkIn

- GIVEN an authenticated user with uid "user1"
- WHEN they write to `users/user1/checkIns/2026-05-15`
- THEN the write is permitted

#### SCENARIO-331: Non-owner cannot read another user's checkIn

- GIVEN an authenticated user with uid "user2"
- WHEN they attempt to read `users/user1/checkIns/2026-05-15`
- THEN the read is denied

#### SCENARIO-332: Non-owner cannot write another user's checkIn

- GIVEN an authenticated user with uid "user2"
- WHEN they attempt to write to `users/user1/checkIns/2026-05-15`
- THEN the write is denied

---

### Requirement: CheckInDialog (REQ-WRC-005)

`CheckInDialog` MUST render: a `TreinoIcon.location` pin in accent color, "¿ESTÁS EN EL GYM HOY?" as header, contextual subtext based on whether `gymId` is present, "NO" (outline) and "SÍ, ENTRÉ" (accent fill) buttons.

#### SCENARIO-333: Dialog renders with gym context

- GIVEN `gymId` is non-null and `gymName` is "Smart Fit"
- WHEN `CheckInDialog` builds
- THEN subtext includes the gym name and "Detectamos que estás cerca..."

#### SCENARIO-334: Dialog renders without gym context

- GIVEN `gymId` is null
- WHEN `CheckInDialog` builds
- THEN subtext reads "Confirma tu entrenamiento de hoy"

---

### Requirement: FeedScreen Trigger (REQ-WRC-006 through REQ-WRC-009)

`FeedScreen` MUST trigger `CheckInDialog` on mount only if `todayCheckInProvider` returns null AND a session-scoped flag has not been set. Both buttons MUST create a check-in doc and dismiss the dialog. "SÍ, ENTRÉ" uses `gymId` from `userProfile`; "NO" uses null gym fields.

#### SCENARIO-335: Dialog shown only once per session

- GIVEN `todayCheckInProvider` returns null and dialog has not been shown this session
- WHEN `FeedScreen` mounts
- THEN `CheckInDialog` is displayed

#### SCENARIO-336: Dialog not shown if check-in already exists today

- GIVEN `todayCheckInProvider` returns an existing `CheckIn`
- WHEN `FeedScreen` mounts
- THEN `CheckInDialog` is NOT displayed

#### SCENARIO-337: "SÍ, ENTRÉ" creates check-in and dismisses

- GIVEN `CheckInDialog` is showing and the user's profile has `gymId: "gym1"`
- WHEN the user taps "SÍ, ENTRÉ"
- THEN `createTodayCheckIn(inGym: true, gymId: "gym1", gymName: <from gymNameFromId>)` is called
- AND the dialog is dismissed

#### SCENARIO-338: "NO" creates check-in with null gym and dismisses

- GIVEN `CheckInDialog` is showing
- WHEN the user taps "NO"
- THEN `createTodayCheckIn(inGym: false, gymId: null, gymName: null)` is called
- AND the dialog is dismissed
- AND `FeedScreen` will not show the dialog again this session

---

## Cross-Cutting Requirements (All PRs): REQ-WRA-*

These apply to every file touched across all 4 PRs.

| ID | Rule |
|---|---|
| REQ-WRA-001 | Colors via `AppPalette.of(context)` only |
| REQ-WRA-002 | Icons via `TreinoIcon.X` only |
| REQ-WRA-003 | Spacing from scale: 8 / 12 / 14 / 18 / 20 |
| REQ-WRA-004 | Every new or modified unit of logic has a corresponding test |
| REQ-WRA-005 | New screens do not add Scaffold / AppBackground / SafeArea |
| REQ-WRA-006 | `UserPublicProfile` additions are nullable and backwards-compatible |

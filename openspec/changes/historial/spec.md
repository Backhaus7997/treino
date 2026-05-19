# Spec: Historial (Fase 4 · Etapa 4)

**Change**: `historial`
**REQ namespace**: `REQ-HIST-NNN`
**SCENARIO start**: 355
**SCENARIO end**: 378
**Domains touched**: NEW `historial-ui` · ANNOTATED `workout-data` (read-only consumer — no code changes)

---

## New Capability: `historial-ui`

### Purpose

`HistorialSection` replaces the private placeholder `_HistorialSection` inside `WorkoutScreen`.
It renders a global newest-first list of finished sessions with session cards.
Tapping a card navigates to `SessionDetailScreen` at `/workout/historial/:sessionId`, a full-screen
immersive route (outside ShellRoute, no `TreinoBottomBar`) showing header, 4 StatTiles, and a
per-exercise set table.

---

## Requirements

| ID | Name | Strength |
|----|------|----------|
| REQ-HIST-001 | HistorialSection widget contract | MUST |
| REQ-HIST-002 | List renders sessions newest-first | MUST |
| REQ-HIST-003 | Client-side filter: status == finished | MUST |
| REQ-HIST-004 | Card fields rendered | MUST |
| REQ-HIST-005 | Empty state | MUST |
| REQ-HIST-006 | Loading state — list | MUST |
| REQ-HIST-007 | Error state — list | MUST |
| REQ-HIST-008 | Card tap navigation | MUST |
| REQ-HIST-009 | SessionDetailScreen widget contract | MUST |
| REQ-HIST-010 | SessionDetailScreen header | MUST |
| REQ-HIST-011 | SessionDetailScreen 4 StatTiles | MUST |
| REQ-HIST-012 | SessionDetailScreen exercise grouping | MUST |
| REQ-HIST-013 | SessionDetailScreen set table rows | MUST |
| REQ-HIST-014 | SessionDetailScreen PR badge stub | MUST |
| REQ-HIST-015 | SessionDetailScreen back navigation | MUST |
| REQ-HIST-016 | SessionDetailScreen not-found state | MUST |
| REQ-HIST-017 | SessionDetailScreen loading state | MUST |
| REQ-HIST-018 | SessionDetailScreen error state | MUST |
| REQ-HIST-019 | Router — immersive route top-level | MUST |
| REQ-HIST-020 | WorkoutScreen swaps placeholder | MUST |
| REQ-HIST-021 | Date formatting helper | MUST |

---

## REQ-HIST-001 — HistorialSection widget contract

The system MUST expose a public widget `HistorialSection` (not `_HistorialSection`) that is
importable by `WorkoutScreen`.
It MUST render a section heading using the `WorkoutStrings.historialHeading` constant.
It MUST NOT require parameters — it reads providers internally.

#### SCENARIO-355: HistorialSection is public and renderable without parameters

- GIVEN the app mounts `HistorialSection()` with a ProviderScope that supplies `sessionsByUidProvider`
- WHEN the widget tree builds
- THEN no compile-time error occurs and the widget renders without assertion failures

---

## REQ-HIST-002 — List renders sessions newest-first

When `sessionsByUidProvider` resolves to a non-empty list with at least one `SessionStatus.finished`
session, `HistorialSection` MUST render those sessions in descending `startedAt` order (newest first).
Ordering is guaranteed by `SessionRepository.listByUid`, which returns Firestore docs ordered
descending by `startedAt`. The widget MUST NOT re-sort; it renders in the order received after
client-side filtering.

#### SCENARIO-356: sessions appear in newest-first order

- GIVEN `sessionsByUidProvider` returns two finished sessions: session A (`startedAt: t1`, older)
  and session B (`startedAt: t2`, newer, t2 > t1), in that order from the provider
- WHEN `HistorialSection` renders
- THEN session B's `routineName` appears before session A's `routineName` in the widget tree

---

## REQ-HIST-003 — Client-side filter: finished AND wasFullyCompleted

`HistorialSection` MUST filter the list returned by `sessionsByUidProvider` and render ONLY sessions
where `session.status == SessionStatus.finished` AND `session.wasFullyCompleted == true`.

Sessions with any other status (e.g. `inProgress`) MUST NOT appear in the list, AND sessions that
were finalized by the user without completing all sets (`wasFullyCompleted: false`) MUST NOT appear
in the list either. They remain in Firestore (not deleted) but are not surfaced to the user as
historial entries. This is an explicit product decision (2026-05-19): users want a clean record of
completed sessions, not partial/interrupted ones.

No new repository method is added; filtering is entirely client-side.

#### SCENARIO-357: non-finished sessions are excluded from the list

- GIVEN `sessionsByUidProvider` returns three sessions:
  one with `status: SessionStatus.finished` and `routineName: 'Push'`,
  one with `status: SessionStatus.inProgress` and `routineName: 'Pull'`,
  one with `status: SessionStatus.active` and `routineName: 'Legs'`
- WHEN `HistorialSection` renders
- THEN only 'Push' is visible
- AND 'Pull' and 'Legs' are not present in the widget tree

#### SCENARIO-358: all-unfinished sessions triggers empty state

- GIVEN `sessionsByUidProvider` returns sessions where none have `status == finished`
- WHEN `HistorialSection` renders
- THEN the empty state text "Todavía no entrenaste." is visible
- AND no session card is rendered

---

## REQ-HIST-004 — Card fields rendered

Each session card MUST display all of the following fields:

1. A completed visual indicator (e.g. filled checkmark icon). Since the list only shows
   `wasFullyCompleted == true` sessions (per REQ-HIST-003), the indicator is constant — no
   distinct "abandoned" variant is rendered in this etapa.
2. `routineName` as card title text.
3. Relative date in the format produced by `formatSessionDate` (e.g. `"Mié 27 nov"`).
4. `totalVolumeKg` numeric value with unit label.
5. `durationMin` numeric value with unit label.

The card MUST NOT display set count (avoids N+1 load on the list).

#### SCENARIO-359: card renders all required fields

- GIVEN `sessionsByUidProvider` returns one finished session with
  `wasFullyCompleted: true`, `routineName: 'Push A'`, `startedAt: DateTime(2025, 11, 26, 10, 0)`,
  `totalVolumeKg: 4.5`, `durationMin: 48`
- WHEN `HistorialSection` renders
- THEN the text 'Push A' is visible in the widget tree
- AND the text '4.5' (or equivalent formatted string) is visible
- AND the text '48' (or equivalent formatted string) is visible
- AND a completed indicator widget is present

#### SCENARIO-360: abandoned sessions are filtered out

- GIVEN a finished session with `wasFullyCompleted: true` AND a finished session with `wasFullyCompleted: false`
- WHEN `HistorialSection` renders
- THEN only the `wasFullyCompleted: true` card appears
- AND the `wasFullyCompleted: false` card is absent from the widget tree

---

## REQ-HIST-005 — Empty state

When the filtered list of finished sessions is empty (either the provider returns an empty list or
all sessions fail the `status == finished` filter), `HistorialSection` MUST display:

- Text: `WorkoutStrings.historialEmptyMessage` (value: `"Todavía no entrenaste."`)
- A CTA button with text `WorkoutStrings.historialEmptyCta` (value: `"Empezar entrenamiento"`)
  that navigates to `/workout` (or triggers the workout-start flow via the existing route).

#### SCENARIO-361: empty state renders copy and CTA

- GIVEN `sessionsByUidProvider` returns an empty list
- WHEN `HistorialSection` renders
- THEN text "Todavía no entrenaste." is visible
- AND a button with text "Empezar entrenamiento" is visible

#### SCENARIO-362: empty state CTA navigates away from historial

- GIVEN the empty state is rendered
- WHEN the user taps "Empezar entrenamiento"
- THEN the router navigates to `/workout` (or the equivalent workout start entry point)

---

## REQ-HIST-006 — Loading state — list

While `sessionsByUidProvider` is in a loading state, `HistorialSection` MUST display a loading
indicator (e.g. `CircularProgressIndicator` or skeleton). No session cards are shown during loading.

#### SCENARIO-363: list shows loader while provider resolves

- GIVEN `sessionsByUidProvider` is in the loading state (AsyncLoading)
- WHEN `HistorialSection` renders
- THEN a `CircularProgressIndicator` (or loading skeleton) is visible
- AND no session card widgets are rendered

---

## REQ-HIST-007 — Error state — list

When `sessionsByUidProvider` resolves to an `AsyncError`, `HistorialSection` MUST display an error
message and a retry CTA that re-triggers the provider.

#### SCENARIO-364: list shows error message and retry CTA on provider failure

- GIVEN `sessionsByUidProvider` resolves to an `AsyncError`
- WHEN `HistorialSection` renders
- THEN an error message text is visible
- AND a retry button or CTA is present in the widget tree

---

## REQ-HIST-008 — Card tap navigation

Tapping a session card MUST navigate to `/workout/historial/:sessionId` where `:sessionId` is the
`id` of the tapped session.

#### SCENARIO-365: tapping a card pushes historial detail route

- GIVEN `HistorialSection` renders a card for a session with `id: 'session-abc'`
- WHEN the user taps that card
- THEN the router navigates to `/workout/historial/session-abc`

---

## REQ-HIST-009 — SessionDetailScreen widget contract

The system MUST expose a top-level widget `SessionDetailScreen({required String sessionId})`.
It MUST render without a bottom navigation bar (top-level GoRoute, outside ShellRoute).
It MUST NOT be nested inside the ShellRoute that renders `TreinoBottomBar`.

#### SCENARIO-366: SessionDetailScreen renders for historial detail path

- GIVEN the app is navigated to `/workout/historial/sess-1`
- WHEN the route resolves
- THEN `SessionDetailScreen` is rendered with `sessionId == 'sess-1'`
- AND `TreinoBottomBar` is not visible in the widget tree

---

## REQ-HIST-010 — SessionDetailScreen header

The header MUST display:

1. The session date formatted as `"Mié 27 nov"` style (using `formatSessionDate`).
2. The session start time formatted as `"10:30"` (or similar `HH:mm` format).
3. `session.routineName` as a subtitle or secondary text.
4. A back arrow/button that triggers back navigation (see REQ-HIST-015).

#### SCENARIO-367: header shows date, time, and routineName

- GIVEN `sessionSummaryProvider` resolves to a session with
  `startedAt: DateTime(2025, 11, 26, 10, 30)` and `routineName: 'Push A'`
- WHEN `SessionDetailScreen` renders
- THEN the formatted date text (e.g. "Mié 26 nov") is visible
- AND the time text (e.g. "10:30") is visible
- AND the text 'Push A' is visible

---

## REQ-HIST-011 — SessionDetailScreen 4 StatTiles

`SessionDetailScreen` MUST render exactly 4 `StatTile` widgets with the following labels and values:

| Label | Value source |
|-------|-------------|
| `DURACIÓN` | `session.durationMin` |
| `SETS` | count of `List<SetLog>` from `sessionSummaryProvider` |
| `VOLUMEN` | `session.totalVolumeKg` |
| `PRS HOY` | Stub — displays `"—"` (no computation this etapa) |

#### SCENARIO-368: 4 StatTiles render with correct values

- GIVEN `sessionSummaryProvider` resolves to a session with `durationMin: 52`,
  `totalVolumeKg: 3.2`, and a set-log list of 22 items
- WHEN `SessionDetailScreen` renders
- THEN a StatTile with label "DURACIÓN" and value "52" (or equivalent) is visible
- AND a StatTile with label "SETS" and value "22" is visible
- AND a StatTile with label "VOLUMEN" and value "3.2" (or equivalent) is visible
- AND a StatTile with label "PRS HOY" and value "—" is visible

#### SCENARIO-369: SETS stat derives from setLog count, not session field

- GIVEN `sessionSummaryProvider` resolves to any session with exactly 7 set-log items
- WHEN `SessionDetailScreen` renders
- THEN the SETS StatTile displays "7"

---

## REQ-HIST-012 — SessionDetailScreen exercise grouping

`SessionDetailScreen` MUST group the `List<SetLog>` by `exerciseName` and render one block per
distinct exercise. The order of exercise blocks MUST preserve the insertion order of the first
appearance of each `exerciseName` in the set-log list (which is ordered by `setNumber ASC` as
returned by `SessionRepository.listSetLogs`).

No re-sorting or alphabetical ordering is applied. The grouping is purely client-side.

#### SCENARIO-370: set logs grouped by exerciseName in insertion order

- GIVEN `sessionSummaryProvider` returns set logs in this order:
  [SetLog(exerciseName: 'Press Banca', setNumber: 1),
   SetLog(exerciseName: 'Press Banca', setNumber: 2),
   SetLog(exerciseName: 'Sentadilla', setNumber: 1)]
- WHEN `SessionDetailScreen` renders
- THEN a block headed "Press Banca" appears before a block headed "Sentadilla"
- AND the "Press Banca" block contains 2 set rows

#### SCENARIO-371: single exercise with multiple sets renders one block

- GIVEN set logs contain 3 sets all with `exerciseName: 'Peso Muerto'`
- WHEN `SessionDetailScreen` renders
- THEN exactly one block headed "Peso Muerto" exists
- AND it contains exactly 3 set rows

---

## REQ-HIST-013 — SessionDetailScreen set table rows

Within each exercise block, each `SetLog` MUST render a table row with three columns:

- `SET` (set number: `setLog.setNumber`)
- `REPS` (`setLog.reps`)
- `KG` (`setLog.weightKg`)

Column headers `SET`, `REPS`, `KG` MUST be visible at the top of each exercise block.

#### SCENARIO-372: set row displays setNumber, reps, and weightKg

- GIVEN a set log: `SetLog(exerciseName: 'Press Banca', setNumber: 2, reps: 10, weightKg: 80.0)`
- WHEN `SessionDetailScreen` renders the exercise block
- THEN the value "2" appears in the SET column
- AND "10" appears in the REPS column
- AND "80" (or "80.0") appears in the KG column

---

## REQ-HIST-014 — SessionDetailScreen PR badge stub

Each set row MUST render a PR badge widget as a visual stub.
The stub MUST be visible (not hidden or zero-opacity).
The stub MUST NOT compute or compare against historical session data.
The stub MUST NOT trigger any repository read beyond `sessionSummaryProvider`.

The actual PR detection logic is deferred to Insights / Etapa 5. This stub is the explicit
integration point for that downstream work.

#### SCENARIO-373: PR badge stub is visible on each set row

- GIVEN `SessionDetailScreen` renders a session with at least one set log
- WHEN the exercise block renders
- THEN each set row contains a PR badge widget (stub placeholder)
- AND no `SessionRepository` method other than those called by `sessionSummaryProvider` is invoked

---

## REQ-HIST-015 — SessionDetailScreen back navigation

The screen MUST provide a back navigation control (arrow button or equivalent).
Tapping it MUST invoke `context.pop()` if a previous route is in the stack, or navigate to
`/workout` otherwise. The screen MUST NOT close the app or navigate to an unrelated route.

#### SCENARIO-374: back button pops the route

- GIVEN `SessionDetailScreen` was pushed from `/workout` (card tap)
- WHEN the user taps the back button
- THEN the router pops to the previous route (i.e. `WorkoutScreen` is visible again)

---

## REQ-HIST-016 — SessionDetailScreen not-found state

When `sessionSummaryProvider` resolves to a value where the session is `null` (or the record
cannot be found), `SessionDetailScreen` MUST display:

- Text: `"Sesión no encontrada"` (or `WorkoutStrings` equivalent)
- A button that navigates to `/workout`

#### SCENARIO-375: not-found state renders message and back CTA

- GIVEN `sessionSummaryProvider` returns a null session (or equivalent not-found state)
- WHEN `SessionDetailScreen` renders
- THEN text "Sesión no encontrada" is visible
- AND a button that navigates to `/workout` is present

---

## REQ-HIST-017 — SessionDetailScreen loading state

While `sessionSummaryProvider` is in a loading state, `SessionDetailScreen` MUST display a
`CircularProgressIndicator`. No header or stats are shown during loading.

#### SCENARIO-376: loading indicator shown while sessionSummaryProvider resolves

- GIVEN `sessionSummaryProvider` is in the loading state (AsyncLoading)
- WHEN `SessionDetailScreen` renders
- THEN a `CircularProgressIndicator` is visible
- AND no StatTile widgets are rendered

---

## REQ-HIST-018 — SessionDetailScreen error state

When `sessionSummaryProvider` resolves to an `AsyncError`, `SessionDetailScreen` MUST display an
error message and a retry CTA.

#### SCENARIO-377: error state renders message and retry on provider failure

- GIVEN `sessionSummaryProvider` resolves to an `AsyncError`
- WHEN `SessionDetailScreen` renders
- THEN an error message is visible
- AND a retry button or CTA is present

---

## REQ-HIST-019 — Router — immersive route top-level

The GoRoute for `/workout/historial/:sessionId` MUST be registered as a top-level route in
`router.dart`, outside the ShellRoute that renders `TreinoBottomBar`.
It MUST follow the same structural pattern as the existing `/workout/session/:sessionId` and
`/workout/session-summary/:sessionId` routes.

In PR-A, the route body MAY be a stub `Center(Text('Detalle — próximamente'))`.
In PR-B, the stub MUST be replaced with `SessionDetailScreen(sessionId: state.pathParameters['sessionId']!)`.

#### SCENARIO-378: router resolves historial detail route outside ShellRoute

- GIVEN the app navigates to `/workout/historial/s1`
- WHEN the GoRouter resolves the path
- THEN the matched route is a top-level GoRoute (not nested inside ShellRoute)
- AND `TreinoBottomBar` is absent from the widget tree

---

## REQ-HIST-020 — WorkoutScreen swaps placeholder

`WorkoutScreen` MUST import and use the public `HistorialSection` widget.
The private `_HistorialSection` class MUST be removed from `workout_screen.dart`.
The existing `workout_screen_test.dart` assertion that verifies the placeholder text
`'Tus entrenamientos completados aparecerán acá.'` MUST be updated or removed in PR-A.

*(No dedicated SCENARIO — covered by REQ-HIST-001 SCENARIO-355 and the updated test file.)*

---

## REQ-HIST-021 — Date formatting helper

A pure function `formatSessionDate(DateTime dt)` MUST exist within the `historial` feature scope.
It MUST return a `String` in the format `"Ddd DD mmm"` where:

- `Ddd` is a 3-letter Spanish day-of-week abbreviation (e.g. `"Lun"`, `"Mar"`, `"Mié"`, `"Jue"`, `"Vie"`, `"Sáb"`, `"Dom"`).
- `DD` is the day number without leading zero.
- `mmm` is a 3-letter Spanish month abbreviation (e.g. `"ene"`, `"feb"`, `"mar"`, `"abr"`, `"may"`, `"jun"`, `"jul"`, `"ago"`, `"sep"`, `"oct"`, `"nov"`, `"dic"`).

The function MUST be implemented via `Map<int, String>` lookups (no `intl` dependency added).
It MUST be deterministic and pure — same `DateTime` always produces the same string.
It MAY be an inline private function if used in only one widget, or extracted to a feature-scoped
helper if used in both `historial_section.dart` and `session_detail_screen.dart`.

No changes to `pubspec.yaml` are permitted.

#### SCENARIO-379: formatSessionDate returns correct Spanish abbreviated format

- GIVEN `dt = DateTime(2025, 11, 26, 10, 30)` (Wednesday, 26 November 2025)
- WHEN `formatSessionDate(dt)` is called
- THEN the result is `"Mié 26 nov"`

#### SCENARIO-380: formatSessionDate handles each weekday correctly

- GIVEN `dt = DateTime(2025, 11, 24)` (Monday)
- WHEN `formatSessionDate(dt)` is called
- THEN the result starts with `"Lun"`

---

## Annotated Capability: `workout-data`

**No code changes.** This etapa is a read-only consumer of the existing data layer.

The following existing symbols are consumed by `historial-ui` and MUST NOT be modified:

| Symbol | Location | Used by |
|--------|----------|---------|
| `sessionsByUidProvider` | `session_providers.dart:21` | `HistorialSection` |
| `sessionSummaryProvider` | `session_providers.dart:53` | `SessionDetailScreen` |
| `currentUidProvider` | `session_providers.dart:37` | both |
| `Session` fields: `routineName`, `startedAt`, `totalVolumeKg`, `durationMin`, `wasFullyCompleted`, `status` | `session.dart:12` | cards + detail |
| `SetLog` fields: `exerciseName`, `setNumber`, `reps`, `weightKg` | `set_log.dart:11` | detail table |
| `SessionRepository.listByUid` | `session_repository.dart:85` | via provider |
| `SessionRepository.listSetLogs` | `session_repository.dart:118` | via provider |
| `StatTile` | `stat_tile.dart:9` | detail stats |

The `status == SessionStatus.finished` filter is a consumer-side concern applied in `HistorialSection`.
No new repository method, no new provider, no Firestore rule change, no `pubspec.yaml` change.

---

## Domain Rules / Invariants

1. **Ordering**: sessions are displayed newest-first. The order is guaranteed by
   `SessionRepository.listByUid` (Firestore `orderBy startedAt DESC`). The widget must not re-sort.

2. **Filter scope**: `HistorialSection` renders only `SessionStatus.finished` sessions. Sessions
   with status `inProgress` or `abandoned` are silently excluded from the rendered list.

3. **Grouping determinism**: `SetLog` grouping by `exerciseName` in `SessionDetailScreen` must
   preserve the order in which each `exerciseName` first appears in the list returned by
   `sessionSummaryProvider`. The list is already ordered by `setNumber ASC` from the repository.
   No alphabetical or secondary sort is applied.

4. **N+1 absence**: the list view MUST NOT load set logs. Set logs are loaded exclusively inside
   `SessionDetailScreen` via `sessionSummaryProvider`.

5. **Date formatting purity**: `formatSessionDate` is a pure function — no side effects, no locale
   system calls, no `intl` dependency.

6. **PR badge is a stub**: PR badge widgets in set rows MUST display a static placeholder value.
   Any logic that reads or compares historical sessions to compute personal records is out of scope
   and reserved for Insights / Etapa 5.

7. **WorkoutStrings constants**: all user-visible copy introduced by this change MUST be defined
   as constants in `WorkoutStrings` — no inline string literals in widget build methods.

---

## Out of Scope

The following are explicitly deferred and MUST NOT be implemented in this change:

- **PR detection / computation**: real personal-record calculation against prior sessions.
- **PR badge logic**: badge shows `true`/`false` based on historical data — Etapa 5 / Insights.
- **Filters**: filter by routine, date range, or any other dimension.
- **Pagination**: the list is flat; Firestore pagination is a future concern.
- **Edit / delete sessions**: no mutation UI in this etapa.
- **Share from detail**: already handled by `post-workout-summary` (Etapa 3).
- **Aggregate metrics**: weekly volume charts, streaks, personal bests dashboard — Insights.
- **New repository methods**: no additions to `SessionRepository`.
- **New providers**: no additions to `session_providers.dart`.
- **`pubspec.yaml` changes**: no new dependencies (especially not `intl`).
- **`firestore.rules` changes**: none required.
- **`lib/core/utils/date_format_helpers.dart`**: this shared helper is NOT created unless
  design phase decides to extract it. Spec is agnostic on the exact file location of `formatSessionDate`.

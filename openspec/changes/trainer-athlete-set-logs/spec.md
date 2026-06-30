# Spec: trainer-athlete-set-logs

> This is a **full spec** (no prior domain spec exists). It covers two domains:
> **Security** (Firestore rules) and **UI** (web + mobile read-only set-log views).
> Requirements REQ-SETLOGS-001 through 004 are emulator-only; 005 onward are
> unit/widget testable.

---

## Domain: Security — Firestore setLogs Rules

### Requirement: REQ-SETLOGS-001 — Linked sharing trainer MAY read athlete setLogs

The `setLogs` subcollection at `users/{uid}/sessions/{sessionId}/setLogs/{setLogId}`
MUST allow `read` when the authenticated request matches EITHER the owner condition
OR the trainer condition: a document exists at `session_shares/{uid}` whose `trainerId`
field equals `request.auth.uid`.

> Test type: **emulator-only**

#### Scenario: Linked trainer reads setLog

- GIVEN athlete A has `session_shares/{A}` with `trainerId: T`
- WHEN trainer T requests `users/{A}/sessions/{S}/setLogs/{L}`
- THEN the request is **allowed**

#### Scenario: Linked trainer lists all setLogs for a session

- GIVEN athlete A has `session_shares/{A}` with `trainerId: T`
- WHEN trainer T lists `users/{A}/sessions/{S}/setLogs`
- THEN the list succeeds and returns all documents

---

### Requirement: REQ-SETLOGS-002 — Non-linked trainer is DENIED setLogs

A trainer whose uid does NOT appear in `session_shares/{athleteId}.trainerId` MUST
receive `permission-denied` on any `setLogs` read.

> Test type: **emulator-only**

#### Scenario: Unrelated trainer is denied

- GIVEN athlete A has `session_shares/{A}` with `trainerId: T1`
- WHEN trainer T2 (T2 ≠ T1) requests `users/{A}/sessions/{S}/setLogs/{L}`
- THEN the request is **denied** (permission-denied)

#### Scenario: Trainer with no share doc is denied

- GIVEN NO `session_shares/{A}` document exists
- WHEN any authenticated trainer T requests `users/{A}/sessions/{S}/setLogs/{L}`
- THEN the request is **denied**

---

### Requirement: REQ-SETLOGS-003 — Owner retains read+write; trainer is write-denied

The athlete (owner) MUST retain read and write on their own `setLogs`. The trainer
(even when linked+sharing) MUST NOT be allowed to write any `setLog` document.

> Test type: **emulator-only**

#### Scenario: Athlete reads own setLogs

- GIVEN authenticated user A
- WHEN A requests `users/{A}/sessions/{S}/setLogs/{L}`
- THEN the request is **allowed**

#### Scenario: Athlete writes own setLogs

- GIVEN authenticated user A
- WHEN A creates or updates `users/{A}/sessions/{S}/setLogs/{L}`
- THEN the request is **allowed**

#### Scenario: Trainer cannot write athlete setLogs

- GIVEN athlete A has `session_shares/{A}` with `trainerId: T`
- WHEN trainer T attempts to write `users/{A}/sessions/{S}/setLogs/{L}`
- THEN the request is **denied**

---

### Requirement: REQ-SETLOGS-004 — Unauthenticated request is denied

Any unauthenticated request to `setLogs` MUST be denied, regardless of the athlete's
share state.

> Test type: **emulator-only**

#### Scenario: Unauthenticated read is denied

- GIVEN no authenticated session
- WHEN an unauthenticated client requests `users/{A}/sessions/{S}/setLogs/{L}`
- THEN the request is **denied**

---

## Domain: Data — coachSessionSetLogsProvider

### Requirement: REQ-SETLOGS-005 — Provider returns setLogs for a given (athleteUid, sessionId)

A `coachSessionSetLogsProvider` (FutureProvider.autoDispose.family keyed on
`({athleteUid, sessionId})`) MUST delegate to `SessionRepository.listSetLogs` and
return the resulting `List<SetLog>`. It MUST return an empty list (not throw) when
either key field is empty.

> Test type: **unit**

#### Scenario: Provider returns setLogs for valid keys

- GIVEN a stubbed repo returning N SetLog objects for (athleteUid: A, sessionId: S)
- WHEN `coachSessionSetLogsProvider((athleteUid: A, sessionId: S))` is resolved
- THEN the result is a `List<SetLog>` of length N

#### Scenario: Provider guards empty athleteUid

- GIVEN athleteUid is empty string
- WHEN the provider is resolved
- THEN the result is `[]` without calling the repository

#### Scenario: Provider guards empty sessionId

- GIVEN sessionId is empty string
- WHEN the provider is resolved
- THEN the result is `[]` without calling the repository

---

## Domain: UI — Shared SessionExerciseBlock Widget

### Requirement: REQ-SETLOGS-006 — Extracted widget renders exercise name and set rows

`SessionExerciseBlock` MUST accept `exerciseName: String` and `sets: List<SetLog>`,
render the exercise name, and render exactly one row per set showing reps and
weightKg. It MUST NOT include any provider reads or edit/delete affordances.

> Test type: **widget**

#### Scenario: Widget shows exercise name

- GIVEN exerciseName: "Sentadilla" and a non-empty sets list
- WHEN `SessionExerciseBlock` is pumped
- THEN the text "Sentadilla" is visible

#### Scenario: Widget renders one row per set

- GIVEN sets with N items
- WHEN `SessionExerciseBlock` is pumped
- THEN exactly N set rows are rendered

#### Scenario: Widget renders reps and weight per set

- GIVEN a set with reps: 10, weightKg: 80.0
- WHEN `SessionExerciseBlock` is pumped
- THEN "10" and "80.0" (or locale-equivalent) are visible in the same row

---

## Domain: UI — Web: Entrenamientos Tab Session Expansion

### Requirement: REQ-SETLOGS-007 — Finished session rows expand to show setLogs grouped by exercise

Each finished-session row in `_HistorialTable` MUST be tappable. On tap, the row
MUST expand and load setLogs via `coachSessionSetLogsProvider`. While loading, a
progress indicator MUST be shown. On success, sets MUST be grouped by exercise using
`SessionExerciseBlock`.

> Test type: **widget**

#### Scenario: Tap triggers loading state

- GIVEN a rendered `_HistorialTable` with at least one finished session
- WHEN the user taps that session row
- THEN a loading indicator is visible

#### Scenario: Loaded sets are shown grouped by exercise

- GIVEN `coachSessionSetLogsProvider` returns sets for exercises E1 and E2
- WHEN the expansion completes
- THEN both E1 and E2 headers and their respective set rows are visible

#### Scenario: Empty setLogs shows empty-state copy

- GIVEN `coachSessionSetLogsProvider` returns `[]`
- WHEN the expansion completes
- THEN `AppL10n.coachSessionSetLogsEmpty` text is visible
- AND no set rows are rendered

#### Scenario: Load error shows error copy (not generic crash)

- GIVEN `coachSessionSetLogsProvider` throws a non-permission-denied error
- WHEN the expansion completes
- THEN `AppL10n.coachSessionSetLogsLoadError` text is visible
- AND no unhandled exception propagates

---

### Requirement: REQ-SETLOGS-008 — No-share state shows friendly placeholder

When `coachSessionSetLogsProvider` fails with `permission-denied` (athlete has not
shared OR share was revoked), both web and mobile surfaces MUST display
`AppL10n.coachAthleteNoSharePlaceholder` (or equivalent key) and MUST NOT display a
generic error widget or crash.

> Test type: **widget**

#### Scenario: Web expansion handles permission-denied

- GIVEN the provider throws a FirebaseException with code `permission-denied`
- WHEN the expansion renders
- THEN the no-share placeholder text is visible

#### Scenario: Mobile athlete detail handles permission-denied

- GIVEN the provider throws `permission-denied` in the mobile detail view
- WHEN the set-log section renders
- THEN the no-share placeholder text is visible

---

### Requirement: REQ-SETLOGS-009 — Trainer view has no edit or delete affordances

The setLogs expansion on both web and mobile MUST NOT render any button, icon, swipe
gesture, or any other interactive affordance that could create, update, or delete a
setLog document.

> Test type: **widget**

#### Scenario: No edit affordance in web expansion

- GIVEN a rendered setLogs expansion with at least one set row
- WHEN the widget tree is inspected
- THEN no edit or delete button/icon is found within the setLogs expansion

#### Scenario: No edit affordance in mobile set-log section

- GIVEN a rendered mobile setLog detail section
- WHEN the widget tree is inspected
- THEN no edit or delete button/icon is found

---

## Domain: UI — Mobile: Athlete Detail Session History

### Requirement: REQ-SETLOGS-010 — Mobile athlete detail shows finished-session history and set detail

`athlete_detail_screen.dart` MUST display a finished-session history section backed
by `sessionsByUidProvider(athleteId)` filtered to finished sessions. Each session
entry MUST be tappable to reveal setLogs via `coachSessionSetLogsProvider`, rendered
with `SessionExerciseBlock`.

> Test type: **widget**

#### Scenario: Session list renders finished sessions

- GIVEN `sessionsByUidProvider` returns sessions [S1(finished), S2(in-progress)]
- WHEN the mobile athlete detail screen is rendered
- THEN S1 appears in the history section and S2 does not

#### Scenario: Tap on session loads setLogs

- GIVEN session S1 is visible in the history section
- WHEN the user taps S1
- THEN `coachSessionSetLogsProvider((athleteUid: A, sessionId: S1))` is invoked

---

## Domain: Regression — session_detail_screen.dart Post-Extraction

### Requirement: REQ-SETLOGS-011 — Athlete's own session detail is unchanged after widget extraction

After `_ExerciseBlock` and `_SetRow` are extracted to `SessionExerciseBlock`,
`session_detail_screen.dart` MUST render identically to its pre-extraction behavior.
No provider wiring, routing, or user-facing behavior MAY change.

> Test type: **widget**

#### Scenario: Existing session detail renders exercise and sets as before

- GIVEN a session with exercises E1 (3 sets) and E2 (2 sets) in the athlete's own data
- WHEN `session_detail_screen.dart` is rendered
- THEN E1 and E2 headers are visible, total 5 set rows rendered, matching pre-extraction snapshot

---

## I18n Requirements (all requirements)

All user-visible strings added by this change MUST use `AppL10n` exclusively. The
following keys MUST be defined in `intl_es_AR.arb`, `intl_es.arb`, and `intl_en.arb`:

| Key | Purpose |
|-----|---------|
| `coachSessionSetLogsTitle` | Section heading in expansion |
| `coachSessionTapToExpand` | CTA hint on session row |
| `coachSessionSetLogsEmpty` | Empty state: session has no logged sets |
| `coachSessionSetLogsLoadError` | Generic load error (non-permission-denied) |
| `coachAthleteNoSharePlaceholder` | Athlete has not shared their history |

No hardcoded strings in any widget file are permitted.

---

## Test Classification Summary

| REQ | Description | Test Type |
|-----|-------------|-----------|
| REQ-SETLOGS-001 | Linked trainer reads setLogs | emulator-only |
| REQ-SETLOGS-002 | Non-linked trainer denied | emulator-only |
| REQ-SETLOGS-003 | Owner read/write; trainer write denied | emulator-only |
| REQ-SETLOGS-004 | Unauthenticated denied | emulator-only |
| REQ-SETLOGS-005 | Provider returns setLogs / guards empty keys | unit |
| REQ-SETLOGS-006 | SessionExerciseBlock renders correctly | widget |
| REQ-SETLOGS-007 | Web expansion: loading / data / empty / error states | widget |
| REQ-SETLOGS-008 | No-share placeholder (not generic error) | widget |
| REQ-SETLOGS-009 | No edit/delete affordance | widget |
| REQ-SETLOGS-010 | Mobile session history + set detail | widget |
| REQ-SETLOGS-011 | Athlete's own session detail regression | widget |

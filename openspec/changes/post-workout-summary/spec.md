# Spec: Post-Workout Summary (Fase 4 · Etapa 3)

**Change**: `post-workout-summary`
**REQ namespace**: `REQ-PWS-NNN`
**SCENARIO start**: 334
**Domains touched**: NEW `post-workout-summary` · MODIFIED `workout-data` (SessionRepository)

---

## New Capability: `post-workout-summary`

### Purpose

`PostWorkoutSummaryScreen` replaces the stub route `/workout/session-summary/:sessionId`.
It displays final stats for a completed or abandoned session and lets the user share it as a Post or exit to `/workout`.

---

## Requirements

| ID | Name | Strength |
|----|------|----------|
| REQ-PWS-001 | PostWorkoutSummaryScreen widget contract | MUST |
| REQ-PWS-002 | Screen loads session on boot | MUST |
| REQ-PWS-003 | Not-found state when session absent | MUST |
| REQ-PWS-004 | Error state on getById failure | MUST |
| REQ-PWS-005 | Header reflects completion status | MUST |
| REQ-PWS-006 | 2×2 stat grid with session metrics | MUST |
| REQ-PWS-007 | PRs section rendered as stub | MUST |
| REQ-PWS-008 | Emoji mood row — visual only | MUST |
| REQ-PWS-009 | LISTO button navigates to /workout | MUST |
| REQ-PWS-010 | COMPARTIR button triggers shareWorkout | MUST |
| REQ-PWS-011 | shareWorkout creates Post on success | MUST |
| REQ-PWS-012 | shareWorkout shows error SnackBar on failure | MUST |
| REQ-PWS-013 | SessionRepository.getById returns Session or null | MUST |
| REQ-PWS-014 | Router replaces stub with PostWorkoutSummaryScreen | MUST |

---

## REQ-PWS-001 — PostWorkoutSummaryScreen widget contract

The system MUST expose a top-level widget `PostWorkoutSummaryScreen({required String sessionId})`.
It MUST render without a bottom navigation bar (top-level GoRoute, outside ShellRoute).

#### SCENARIO-354: router renders PostWorkoutSummaryScreen for summary path

- GIVEN the app is navigated to `/workout/session-summary/abc123`
- WHEN the route resolves
- THEN `PostWorkoutSummaryScreen` is rendered with `sessionId == 'abc123'`
- AND no bottom navigation bar is visible

---

## REQ-PWS-002 — Screen loads session on boot

On mount, the screen MUST call `SessionRepository.getById(uid, sessionId)` and display a `CircularProgressIndicator` while the Future is pending.

#### SCENARIO-342: shows CircularProgressIndicator while getById loads

- GIVEN the screen is mounted with a valid `sessionId`
- WHEN `getById` has not yet resolved
- THEN a `CircularProgressIndicator` is visible in the widget tree

---

## REQ-PWS-003 — Not-found state when session absent

If `getById` returns `null`, the screen MUST display a "Sesión no encontrada" message and a button that navigates to `/workout`.

#### SCENARIO-353: shows not-found message when getById returns null

- GIVEN `getById(uid, sessionId)` returns `null`
- WHEN the screen renders
- THEN text "Sesión no encontrada" is visible
- AND tapping the back button navigates to `/workout`

---

## REQ-PWS-004 — Error state on getById failure

If `getById` throws, the screen MUST display an error message and a "Reintentar" button that re-triggers the load.

#### SCENARIO-IMPLICIT: error state rendered on getById exception

- GIVEN `getById(uid, sessionId)` throws an exception
- WHEN the screen renders
- THEN an error message is visible
- AND a "Reintentar" button is present

---

## REQ-PWS-005 — Header reflects completion status

When `session.wasFullyCompleted == true`, the header MUST display "BUEN ENTRENO".
When `session.wasFullyCompleted == false`, the header MUST display "SESIÓN INTERRUMPIDA".
Both states MUST display `session.routineName` as a subtitle.

#### SCENARIO-343: shows "BUEN ENTRENO" header when wasFullyCompleted is true

- GIVEN a session with `wasFullyCompleted: true` and `routineName: 'Push'`
- WHEN the screen renders
- THEN text "BUEN ENTRENO" is visible
- AND text "Push" is visible as subtitle

#### SCENARIO-344: shows "SESIÓN INTERRUMPIDA" header when wasFullyCompleted is false

- GIVEN a session with `wasFullyCompleted: false` and `routineName: 'Push'`
- WHEN the screen renders
- THEN text "SESIÓN INTERRUMPIDA" is visible
- AND text "Push" is visible as subtitle

---

## REQ-PWS-006 — 2×2 stat grid with session metrics

The screen MUST render a 2×2 grid with four `StatTile` widgets: DURACIÓN (`durationMin`), VOLUMEN (`totalVolumeKg`), SETS (count derived from `listSetLogs`), PRs HOY (stub "—").

#### SCENARIO-345: renders 2×2 stat grid with correct values

- GIVEN a session with `durationMin: 52`, `totalVolumeKg: 3.2`, and 22 set logs
- WHEN the screen renders
- THEN tiles for DURACIÓN, VOLUMEN, and SETS display "52", "3.2", and "22" respectively
- AND the PRs HOY tile displays "—"

#### SCENARIO-346: SETS stat uses count from listSetLogs

- GIVEN a session where `listSetLogs` returns 5 items
- WHEN the screen renders
- THEN the SETS tile displays "5"

---

## REQ-PWS-007 — PRs section rendered as stub

The screen MUST render a "PRS DE LA SESIÓN" section. This etapa MUST display a placeholder (empty list or "Próximamente" text). No real PR data is wired.

#### SCENARIO-347: renders PRs section with placeholder content

- GIVEN any loaded session
- WHEN the screen renders
- THEN a PRs section header or placeholder text is visible
- AND no real PR items are displayed

---

## REQ-PWS-008 — Emoji mood row — visual only

The screen MUST render a row of 5 emoji representing mood options. The row MUST be visual-only: no selection state, no persistence, no interaction behavior.

#### SCENARIO-348: renders emoji mood row with 5 non-interactive emojis

- GIVEN any loaded session
- WHEN the screen renders
- THEN exactly 5 emoji widgets are visible in the mood row
- AND tapping any emoji produces no state change

---

## REQ-PWS-009 — LISTO button navigates to /workout

The LISTO button (filled) MUST call `context.go('/workout')` without creating a Post.

#### SCENARIO-349: LISTO button navigates to /workout without Post

- GIVEN the session is loaded
- WHEN the user taps LISTO
- THEN the router navigates to `/workout`
- AND `PostRepository.create` is never called

---

## REQ-PWS-010 — COMPARTIR button triggers shareWorkout

The COMPARTIR button (outlined) MUST call `PostWorkoutNotifier.shareWorkout(session)`.

#### SCENARIO-350: COMPARTIR button triggers shareWorkout on notifier

- GIVEN the session is loaded
- WHEN the user taps COMPARTIR
- THEN `PostWorkoutNotifier.shareWorkout(session)` is called once

---

## REQ-PWS-011 — shareWorkout creates Post on success

`PostWorkoutNotifier.shareWorkout(session)` MUST:
1. Build a `Post` with `text: WorkoutStrings.postAutoCompleteText`, `routineTag` from session, `privacy: PostPrivacy.friends`, and `authorDisplayName` from `userProfileProvider.valueOrNull` (fallback `''` if not loaded).
2. Call `PostRepository.create(post)`.
3. On success: navigate to `context.go('/workout')` and show SnackBar "¡Post compartido!".

#### SCENARIO-337: shareWorkout builds Post with denormalized authorDisplayName

- GIVEN `userProfileProvider` has loaded a profile with `displayName: 'Ana'`
- WHEN `shareWorkout(session)` is called
- THEN the Post passed to `PostRepository.create` has `authorDisplayName: 'Ana'`

#### SCENARIO-338: shareWorkout falls back to empty string when userProfile not loaded

- GIVEN `userProfileProvider` has not yet loaded (returns null)
- WHEN `shareWorkout(session)` is called
- THEN the Post passed to `PostRepository.create` has `authorDisplayName: ''`

#### SCENARIO-339: shareWorkout calls PostRepository.create with privacy=friends and routineTag

- GIVEN a session with `routineId: 'r1'` and `routineName: 'Push'`
- WHEN `shareWorkout(session)` is called
- THEN `PostRepository.create` is called with `privacy: PostPrivacy.friends`
- AND `routineTag.routineId == 'r1'` and `routineTag.routineName == 'Push'`

#### SCENARIO-341: shareWorkout autocomplete text matches WorkoutStrings.postAutoCompleteText

- GIVEN any session
- WHEN `shareWorkout(session)` is called
- THEN the Post `text` equals `WorkoutStrings.postAutoCompleteText`

#### SCENARIO-351: success SnackBar appears after shareWorkout completes

- GIVEN `PostRepository.create` succeeds
- WHEN `shareWorkout(session)` completes
- THEN a SnackBar with "¡Post compartido!" is shown
- AND the router navigates to `/workout`

---

## REQ-PWS-012 — shareWorkout shows error SnackBar on failure

If `PostRepository.create` throws, `shareWorkout` MUST surface the error as a SnackBar "No pudimos compartir tu post" and MUST NOT navigate.

#### SCENARIO-340: shareWorkout rethrows when PostRepository fails

- GIVEN `PostRepository.create` throws an exception
- WHEN `shareWorkout(session)` is called
- THEN the exception propagates (or is captured as error state on the notifier)

#### SCENARIO-352: error SnackBar shown on shareWorkout failure without navigation

- GIVEN `PostWorkoutNotifier.shareWorkout` fails
- WHEN the screen handles the error
- THEN a SnackBar with "No pudimos compartir tu post" is visible
- AND the router does NOT navigate away from the summary screen

---

## Modified Capability: `workout-data`

### REQ-PWS-013 — SessionRepository.getById returns Session or null

`SessionRepository.getById(uid, sessionId)` MUST return `Future<Session?>`. If a document exists at `users/{uid}/sessions/{sessionId}`, it MUST be returned as a `Session`. If the document does not exist, it MUST return `null`.

#### SCENARIO-334: getById returns Session when document exists

- GIVEN a session document exists at `users/{uid}/sessions/{sessionId}`
- WHEN `getById(uid, sessionId)` is called
- THEN a `Session` is returned with `id == sessionId`

#### SCENARIO-335: getById returns null when document does not exist

- GIVEN no session document exists at `users/{uid}/sessions/{unknownId}`
- WHEN `getById(uid, unknownId)` is called
- THEN `null` is returned

#### SCENARIO-336: getById reads from correct Firestore sub-path

- GIVEN a Firestore instance with a session at `users/u1/sessions/s1`
- WHEN `getById('u1', 's1')` is called
- THEN the read targets the path `users/u1/sessions/s1`

---

## REQ-PWS-014 — Router replaces stub with PostWorkoutSummaryScreen

The GoRoute for `/workout/session-summary/:sessionId` MUST be replaced so it constructs `PostWorkoutSummaryScreen(sessionId: state.pathParameters['sessionId']!)`.
The route MUST remain top-level (outside ShellRoute).

*(See SCENARIO-354 under REQ-PWS-001.)*

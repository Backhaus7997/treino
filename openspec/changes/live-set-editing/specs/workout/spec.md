# Delta for Workout (Live Session — Set Editing)

No existing spec file for `workout` — this is a new capability area. Written as ADDED requirements scoped to live add/remove-set behavior during an active session.

## ADDED Requirements

### Requirement: Add Set During Live Session

The system MUST allow the athlete to add an extra set to the current/reachable exercise during an active session, beyond the plan's prescribed set count.

#### Scenario: Add button renders an extra loggable row

- GIVEN the athlete is on the current/reachable exercise with all planned sets visible
- WHEN the athlete taps "+ agregar serie"
- THEN a new set row renders below the last row, numbered sequentially
- AND the row is empty (bare free-entry, no prefilled target)

#### Scenario: Logging the added set persists a new document

- GIVEN an added set row exists and is unlogged
- WHEN the athlete logs reps/weight for that row
- THEN a new `setLog` document is created in Firestore for that exercise/set
- AND no existing `setLog` document is modified or overwritten

#### Scenario: Adding a set is only available on the current/reachable exercise

- GIVEN the athlete is viewing a completed or past (collapsed) block
- WHEN the block is not the current/reachable exercise
- THEN "+ agregar serie" MUST NOT be shown for that block

### Requirement: Remove Set During Live Session

The system MUST allow the athlete to remove a set from the current/reachable exercise during an active session.

#### Scenario: Removing an unlogged set requires no confirmation

- GIVEN a set row exists and has not been logged yet
- WHEN the athlete taps the row's delete icon
- THEN the row is removed immediately without a confirmation dialog
- AND the session-local set count for that exercise decreases by one

#### Scenario: Removing a logged set surfaces a confirmation

- GIVEN a set row has been logged (has a `setLog` document)
- WHEN the athlete taps the row's delete icon
- THEN a confirmation dialog MUST appear warning of data loss
- AND the delete only proceeds if the athlete confirms

#### Scenario: Confirmed removal deletes the underlying document

- GIVEN the athlete confirms removal of a logged set
- WHEN the deletion is executed
- THEN the corresponding `setLog` document MUST be permanently deleted (hard delete)
- AND the document MUST NOT be soft-deleted, flagged, or retained in any form

#### Scenario: Removing a set renumbers surviving sets

- GIVEN an exercise has sets numbered 1, 2, 3 and set 2 is removed
- WHEN the removal completes
- THEN surviving sets MUST renumber sequentially (set 3 becomes set 2)
- AND no gap in set numbering MUST be visible to the athlete

#### Scenario: Removing a set is only available on the current/reachable exercise

- GIVEN the athlete is viewing a completed or past (collapsed) block
- WHEN the block is not the current/reachable exercise
- THEN the per-row delete icon MUST NOT be shown for that block

### Requirement: Session-Local Set Count Drives Completion Gating

Completion and gating logic (`isFullyCompleted`, block-completion status, next-incomplete navigation) MUST be computed from the session-local set count (plan count adjusted by live add/remove), not the plan's static count.

#### Scenario: Added set keeps the exercise incomplete until logged

- GIVEN a 3-set exercise where all 3 planned sets are logged and one extra set was added (session-local count = 4)
- WHEN completion status is evaluated
- THEN the exercise MUST NOT report fully completed while the 4th set is unlogged
- AND the block MUST NOT collapse and the 4th row MUST remain reachable

#### Scenario: Removed set allows completion at the reduced count

- GIVEN a 3-set exercise where one set was removed (session-local count = 2) and both remaining sets are logged
- WHEN completion status is evaluated
- THEN the exercise MUST report fully completed
- AND the progress ring MUST NOT wait for a 3rd set that no longer exists

#### Scenario: Next-incomplete navigation respects the session-local count

- GIVEN an exercise with a session-local count different from the plan count
- WHEN the app determines the next incomplete set/exercise to navigate to
- THEN the calculation MUST use the session-local count, not the plan's static count

### Requirement: Server-Side Recompute Reads Surviving SetLogs Only

On session finish, the server-side ranking recompute MUST derive metrics from whatever `setLog` documents exist at that time, with no client-side metric write and no reliance on a static or cached set count.

#### Scenario: Finish recompute reflects added and removed sets

- GIVEN a session finished with one added set (extra `setLog` doc) and one removed set (deleted `setLog` doc)
- WHEN the server-side finish trigger recomputes ranking metrics
- THEN the recompute MUST read the current surviving `setLog` documents for that session
- AND the client MUST NOT write any aggregate/metric value directly

## Non-Goals (Out of Scope)

- Editing a logged set's reps/weight — already supported via `updateSet`/`updateSetLog`; unaffected by this change.
- Add/remove on completed or past (collapsed) blocks — reach is limited to the current/reachable exercise only.
- RPE or any per-set metadata beyond existing set fields.
- Cloud Function / `ranking-aggregate.ts` code changes — verification only that mid-session deletes are tolerated.

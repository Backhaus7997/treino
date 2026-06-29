# Exploration: trainer-athlete-set-logs

## Current State

### Data Model

`SetLog` (`lib/features/workout/domain/set_log.dart`) is a freezed model with:
- `id`, `exerciseId`, `exerciseName`, `setNumber`, `reps`, `weightKg`, `rpe?`, `completedAt`

Stored at: `users/{athleteUid}/sessions/{sessionId}/setLogs/{setLogId}`

`SessionRepository` (`lib/features/workout/data/session_repository.dart`) already has a fully-generic `listSetLogs({required String uid, required String sessionId})` method that accepts any `uid` — it is not scoped to the current user at the Dart level. The constraint is purely in Firestore rules.

### Firestore Rules (verified, `firestore.rules`)

```
# lines 501-511
match /users/{uid}/sessions/{sessionId} {
  allow read: if request.auth != null
              && (request.auth.uid == uid
                  || (exists(/databases/$(database)/documents/session_shares/$(uid))
                      && get(/databases/$(database)/documents/session_shares/$(uid)).data.trainerId == request.auth.uid));
  allow write: if request.auth != null && request.auth.uid == uid;

  match /setLogs/{setLogId} {
    allow read, write: if request.auth != null && request.auth.uid == uid;  # OWNER-ONLY
  }
}
```

**Key finding**: Sessions are already readable by the named trainer when `session_shares/{athleteId}.trainerId == request.auth.uid`. The `setLogs` subcollection rule at line 509 is **owner-only** — the trainer read gate was intentionally deferred (confirmed by comment in `alumno_detail_screen.dart` line 1450: "La evolución por ejercicio se difiere: depende de `setLogs`, que es owner-only en firestore.rules").

### Share Grant Mechanism

- `session_shares/{athleteId}` doc: `{ trainerId: "<uid>" }` — written by the athlete only.
- The toggle "Compartir historial con mi PF" (`athlete_coach_view.dart` `_ShareToggle`) sets `trainer_links.sharedWithTrainer` AND calls `SessionShareRepository.grant/revoke`.
- The rule on `session_shares` allows: read by owner (athleteId) or the named trainerId. Write: only the athlete.
- **Important**: The share gate uses `session_shares`, NOT `trainer_links` directly. One athlete can share with only ONE trainer at a time (doc id == athleteId, one trainerId field). This is already the model in production.

### What the PF Sees Today

**Mobile** (`lib/features/coach/presentation/athlete_detail_screen.dart`):
- Planes, Antropometría, Rendimiento, Cobro, Nota del alumno. NO sessions, NO setLogs.

**Web** (`lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart`):
- `_EntrenamientoTab`: shows active routine + session history table (date, session name, duration, volume) via `sessionsByUidProvider(athleteId)` — sessions ARE readable (rule allows it when shared).
- Comment at line 1508: `'Próximamente: evolución por ejercicio (PR, volumen, frecuencia).'`
- `_ResumenTab` at line 587: comment says "La última-sesión por ejercicio, ... se difieren (dependen de setLogs owner-only...)"

### Providers (current)

- `sessionsByUidProvider(uid)` — calls `SessionRepository.listByUid(uid)`. Already usable cross-user. Used by web _EntrenamientoTab.
- `sessionSummaryProvider({uid, sessionId})` — fetches session + setLogs. Accepts any uid/sessionId pair. Blocked only by rules.
- `lastWeightByExerciseProvider(uid)` — scans last 15 sessions + their setLogs. Currently used athlete-own only. Would need rules fix to work cross-user.

---

## Affected Areas

- `firestore.rules` — `setLogs` subcollection rule at line 509
- `lib/features/workout/application/session_providers.dart` — needs a new provider `sessionSetLogsForAthleteProvider` scoped to trainer reads (or reuse existing providers with cross-uid)
- `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` — `_EntrenamientoTab._HistorialTable` rows need to be tappable, and the "Próximamente" placeholder for exercise evolution needs replacing
- `lib/features/coach/presentation/athlete_detail_screen.dart` — optionally add a session history section (mobile view)
- `lib/features/workout/presentation/session_detail_screen.dart` — reusable widgets (`_ExerciseBlock`, `_SetRow`) could be extracted or referenced
- `lib/l10n/intl_es_AR.arb` + `intl_es.arb` + `intl_en.arb` — new i18n keys needed for trainer-side setLog views
- `test/features/workout/data/session_repository_test.dart` — `listSetLogs` is already tested; cross-uid behavior needs coverage
- `test/features/coach/data/firestore_rules_test.dart` — emulator-deferred setLogs rule tests

---

## Decision 1: Security Rules — How to let the PF read setLogs

### Current rule (line 509)
```
match /setLogs/{setLogId} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}
```

### Option A — Extend setLogs read to mirror the session rule (recommended)
```
match /setLogs/{setLogId} {
  allow read: if request.auth != null
              && (request.auth.uid == uid
                  || (exists(/databases/$(database)/documents/session_shares/$(uid))
                      && get(/databases/$(database)/documents/session_shares/$(uid)).data.trainerId == request.auth.uid));
  allow write: if request.auth != null && request.auth.uid == uid;
}
```
- Pros: minimal change; reuses the existing `session_shares` gate (same pattern as parent session rule); no new collection or denormalization; the trainer can only read setLogs if the athlete explicitly shared AND the trainer is the named one.
- Cons: adds one `get()` call per setLog read (Firestore pricing; but reads are batched per session so the cost is bounded by `listSetLogs` being one query + one `get()` for the session_shares doc, not N per document).
- Effort: Low — 3-line rule change + emulator test.

### Option B — Denormalize setLogs into the session doc
Write a `setsSnapshot: [...]` array field into the session document when the session finishes.
- Pros: single read for session + sets; no rule complexity for subcollections.
- Cons: session doc size grows proportionally to sets logged (Firestore 1MB doc limit; realistic sessions have ~30-60 sets so ~3-6KB, fine); requires a migration for existing sessions or only works for new ones; changes `finish()` flow; breaks the clean subcollection pattern already working for athletes.
- Effort: High — repo changes, migration script, rule change, existing test rework.

**Recommendation: Option A.** It mirrors exactly the parent rule, preserves the existing data model and privacy contract, and requires zero data migration. The `get()` cost is negligible: the PF fetches setLogs for one session at a time (not all sessions in parallel).

---

## Decision 2: Data Access Layer — How the PF reads setLogs

`SessionRepository.listSetLogs({uid, sessionId})` is already cross-user capable at the Dart level. The only change needed is the Firestore rule.

No new repository method is needed. What IS needed:

### New Riverpod provider: `coachSessionSetLogsProvider`

```dart
// In session_providers.dart or a new coach_session_providers.dart
final coachSessionSetLogsProvider = FutureProvider.autoDispose
    .family<List<SetLog>, ({String athleteUid, String sessionId})>(
  (ref, key) async {
    if (key.athleteUid.isEmpty || key.sessionId.isEmpty) return const [];
    return ref
        .watch(sessionRepositoryProvider)
        .listSetLogs(uid: key.athleteUid, sessionId: key.sessionId);
  },
);
```

This is separate from `sessionSummaryProvider` (which also reads the session doc) because the trainer's detail view already has the session data from `sessionsByUidProvider` — it only needs the setLogs for a session the user taps.

**No new provider for exercise progression at MVP.** `lastWeightByExerciseProvider` scans N sessions' setLogs in parallel — usable cross-user once rules are fixed, but deferred to a post-MVP phase because it makes N Firestore reads (up to 15) per load and the UX value of "per-exercise progression chart" is higher effort to build than a per-session set detail view.

---

## Decision 3: UI — Where and What

### Option A (MVP — recommended): Per-session set detail in Web _EntrenamientoTab
- Make the session rows in `_HistorialTable` tappable.
- On tap, load setLogs for that session via `coachSessionSetLogsProvider` and show an expandable or modal/bottom-sheet that renders the same `_ExerciseBlock` / `_SetRow` building blocks from `session_detail_screen.dart`.
- The athlete's own `SessionDetailScreen` uses `currentUidProvider` hardcoded — the PF view cannot reuse it directly, but the private inner widgets `_ExerciseBlock` and `_SetRow` are pure presentational (only receive `exerciseName` and `List<SetLog>`) and CAN be extracted to a shared location or duplicated read-only.
- Scope: one new modal widget (or inline expand), one new provider, one rule change, no new route.
- Effort: Medium (2-3 days). Most of the complexity is extracting/duplicating widgets.

### Option B: Per-exercise progression in Web _EntrenamientoTab
- Replace "Próximamente: evolución por ejercicio" with a chart showing last N weights per exercise (like `lastWeightByExerciseProvider` extended to cross-user).
- Much higher UX value for a PF who programs progressive overload.
- Requires: rules fix + scanning up to 15 sessions worth of setLogs + a per-exercise chart widget.
- Effort: High (chart, aggregation logic, UX for exercise selection).

### Option C: Add session history to Mobile `athlete_detail_screen.dart`
- Currently the mobile view has no sessions at all. Adding a collapsible history section would require a new section widget and a tappable route.
- Mobile already has the session share rule benefits but the UX surface is constrained.
- Effort: Medium — but lower priority since Web Coach Hub is the primary PF tool.

**Recommendation: Option A (MVP) + note Option B for next phase.**

The smallest valuable slice is: the PF's web `_EntrenamientoTab` already shows the session table. Making each row tappable to reveal that session's setLogs (grouped by exercise, read-only) delivers the PT's core need (see what weight/reps the athlete actually did) with minimum new code. Mobile can follow later as a parallel or next change.

---

## Decision 4: Widget Reuse

`_ExerciseBlock` and `_SetRow` in `session_detail_screen.dart` are private (`_`-prefixed) and not exported. They take `exerciseName: String` and `sets: List<SetLog>` — purely presentational.

Options:
1. **Extract to shared widget file** — move to e.g. `lib/features/workout/presentation/widgets/session_exercise_block.dart` and make public. Both `session_detail_screen.dart` and the new trainer view import it. Clean, DRY.
2. **Duplicate for trainer view** — create a local read-only copy inside the coach feature. Simpler short-term but violates DRY.
3. **Inline expansion in `_HistorialTable`** — expand the row in place using an `AnimatedSize` / `ExpansionTile`. No shared widget needed. Slightly worse UX (table layout breaks) but least code.

**Recommendation: Option 1 (extract).** The widgets are small, pure, and already correct. Extracting them creates a reusable `SessionExerciseBlock` widget that both views share. This also sets up for the mobile view later.

---

## Decision 5: i18n Keys Needed

The `intl_*.arb` files (es_AR / es / en) will need:

| Key | es_AR value | Context |
|-----|-------------|---------|
| `coachSessionSetLogsLoadError` | `'No pudimos cargar los sets de esta sesión.'` | Error state in setLogs expansion |
| `coachSessionSetLogsEmpty` | `'Esta sesión no tiene sets registrados.'` | Empty state |
| `coachSessionSetLogsTitle` | `'SETS'` or `'DETALLE DE SESIÓN'` | Section label |
| `coachSessionTapToExpand` | `'Ver sets'` | CTA hint in table row |

Note: `session_detail_screen.dart` already has `sessionDetailNoSets` in arb. The trainer-side key should be different (different feature context) to avoid coupling.

---

## Risks

1. **Security correctness (critical)**: The `setLogs` rule extension must EXACTLY mirror the session parent rule. A bug here would expose athlete set data to wrong trainers. The rule uses `session_shares/{uid}` (athleteId as doc id), same as the existing session rule — this is correct. Verification is emulator-only (no harness).

2. **Only ONE trainer can be the share recipient**: `session_shares/{athleteId}` stores a single `trainerId`. If the athlete switches trainers, the old trainer loses access automatically (revoke is called on terminate/re-share). This is by design but must be reflected in UX copy.

3. **No share = no setLog access**: The rule correctly returns permission-denied if the athlete hasn't shared. The trainer's UI must handle this gracefully (show a placeholder like "El alumno no ha compartido su historial" rather than a generic error).

4. **Read cost**: `listSetLogs` per session is one Firestore query. Loading all sessions' setLogs at once (as `lastWeightByExerciseProvider` does) is N queries — fine for N=15 per athlete but must not be done on the session list render. The per-session tap-to-expand pattern naturally avoids this.

5. **`session_detail_screen.dart` is athlete-only** (hardcoded `currentUidProvider`): The PF cannot be routed to it as-is. Creating a cross-uid `CoachSessionDetailScreen` or extracting the widgets is required. Do not reuse the existing screen by pushing to it — the read will fail with rules denial because the screen uses the current user's uid.

6. **`lastWeightByExerciseProvider` is NOT MVP scope**: It scans 15 sessions' setLogs in parallel. Using it cross-user for the PF's exercise progression tab is correct but is a separate phase. Exclude from this change.

7. **Mobile (`athlete_detail_screen.dart`)**: No sessions provider is wired in the mobile coach view today. Adding it would require session share check + sessions provider + setLogs provider — possible but higher scope. Defer to post-MVP or a parallel change.

---

## Files to Touch

### Must touch (MVP scope):
| File | Change |
|------|--------|
| `firestore.rules` (line 509) | Extend `setLogs` read rule to allow trainer via `session_shares` |
| `lib/features/workout/application/session_providers.dart` | Add `coachSessionSetLogsProvider` |
| `lib/features/workout/presentation/session_detail_screen.dart` | Extract `_ExerciseBlock` + `_SetRow` to public widget file |
| `lib/features/workout/presentation/widgets/session_exercise_block.dart` | NEW — public extracted widget |
| `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` | Make `_HistorialTable` rows tappable; add inline setLogs expansion via `coachSessionSetLogsProvider`; replace "Próximamente" text for setLogs |
| `lib/l10n/intl_es_AR.arb` + `intl_es.arb` + `intl_en.arb` | Add 4 new i18n keys |
| `test/features/workout/data/session_repository_test.dart` | Add cross-uid `listSetLogs` scenario (with FakeFirebaseFirestore — no rule enforcement) |
| `test/features/coach/data/firestore_rules_test.dart` | Add emulator-deferred scenarios for setLogs trainer read (allow) + non-linked trainer read (deny) |

### Out of scope (next phase):
- `lib/features/coach/presentation/athlete_detail_screen.dart` (mobile) — deferred
- Per-exercise progression chart / `lastWeightByExerciseProvider` cross-user — deferred

---

## Strict-TDD Test Plan

### Unit tests (FakeFirebaseFirestore — no rules enforcement)

**File**: `test/features/workout/data/session_repository_test.dart`

| Scenario | Description | Assertion |
|----------|-------------|-----------|
| `SCENARIO-SET-COACH-001` | `listSetLogs` for a different uid (cross-user call) returns correct docs | Given setLogs written for `athleteUid`, when called with `uid: athleteUid` from any caller, returns all SetLog objects ordered by setNumber |
| `SCENARIO-SET-COACH-002` | `listSetLogs` for non-existent session returns empty list | Given no session, returns `[]` |

These test the REPOSITORY behavior. Rule enforcement cannot be tested with FakeFirebaseFirestore.

**File**: `test/features/workout/application/coach_session_set_logs_provider_test.dart` (NEW)

| Scenario | Description | Assertion |
|----------|-------------|-----------|
| `SCENARIO-SET-COACH-003` | `coachSessionSetLogsProvider` returns setLogs for athleteUid/sessionId | Provider correctly calls repo and returns list |
| `SCENARIO-SET-COACH-004` | `coachSessionSetLogsProvider` returns empty when athleteUid is empty | Returns `[]` guard |
| `SCENARIO-SET-COACH-005` | `coachSessionSetLogsProvider` returns empty when sessionId is empty | Returns `[]` guard |

**File**: `test/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen_test.dart` (extend or NEW)

| Scenario | Description | Assertion |
|----------|-------------|-----------|
| `SCENARIO-SET-COACH-010` | `_HistorialTable` row is tappable and triggers setLog load | Widget test: tap session row, verify `coachSessionSetLogsProvider` is called and expansion shows exercise blocks |
| `SCENARIO-SET-COACH-011` | When setLogs list is empty, shows empty-state text | `sessionDetailNoSets` equivalent copy displayed |
| `SCENARIO-SET-COACH-012` | When setLog load errors, shows error text | Error copy displayed; no crash |
| `SCENARIO-SET-COACH-013` | While loading setLogs shows progress indicator | `CircularProgressIndicator` visible |

### Widget extraction tests

**File**: `test/features/workout/presentation/widgets/session_exercise_block_test.dart` (NEW)

| Scenario | Description | Assertion |
|----------|-------------|-----------|
| `SCENARIO-SET-COACH-020` | `SessionExerciseBlock` renders exercise name | Finds `exerciseName` text |
| `SCENARIO-SET-COACH-021` | `SessionExerciseBlock` renders one row per SetLog | N rows for N sets |
| `SCENARIO-SET-COACH-022` | `SessionExerciseBlock` renders weight and reps | '80.0 kg' / '10 reps' visible |

### Firestore rules (emulator-deferred)

**File**: `test/features/coach/data/firestore_rules_test.dart` (extend)

| Scenario | Run condition | Description |
|----------|---------------|-------------|
| `SCENARIO-SET-COACH-030` | emulator required | Trainer named in `session_shares` CAN read athlete's `setLogs` |
| `SCENARIO-SET-COACH-031` | emulator required | Trainer NOT in `session_shares` gets permission-denied on `setLogs` |
| `SCENARIO-SET-COACH-032` | emulator required | Athlete can still read/write own `setLogs` |
| `SCENARIO-SET-COACH-033` | emulator required | Trainer cannot WRITE athlete's `setLogs` (read-only grant) |
| `SCENARIO-SET-COACH-034` | emulator required | Unauthenticated request denied |

All emulator scenarios follow the existing pattern in `firestore_rules_test.dart`: marked with `skip: 'emulator required — run with firebase emulators:exec'`.

---

## Recommendation

**Proceed to proposal.** The exploration surfaces a clean path:

1. One 3-line rule change (high confidence, exact shape known).
2. One new Riverpod provider (mechanical, low risk).
3. Extract two private widgets to a shared file (surgical refactor).
4. Wire expansion in the existing `_EntrenamientoTab._HistorialTable` (web only, MVP).
5. 4 new i18n keys.

Total estimated scope: ~200-280 changed lines across 8 files. Fits comfortably within the 400-line PR budget in one slice. The security risk is the highest-priority item to verify via emulator before merge.

## Ready for Proposal

Yes. The decision space is clear, options have been weighed, and the recommended approach has no open blockers.

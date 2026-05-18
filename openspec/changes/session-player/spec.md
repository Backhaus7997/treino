# Spec — session-player

**Change**: `session-player`
**Fase / Etapa**: Fase 4 · Etapa 2 — Active workout session player
**Artifact store**: `openspec`
**TDD**: Strict — tests are written BEFORE each widget/notifier/provider method in the apply phase.
**Scenario numbering**: continues from SCENARIO-236 (last used in `public-profile` spec). Starts at SCENARIO-250 (safe gap confirmed by inspecting `test/features/feed/` and `test/features/workout/`).
**REQ namespace**: `REQ-SESSION-*`
**Last updated**: 2026-05-18 — Decision 12 (resume-on-reopen) incorporated; 5 new resume REQs added (RESUME-001 through RESUME-005); NOTIFIER-001 updated with resume path; scenarios continue from SCENARIO-318.

---

## Overview

This spec defines verifiable requirements for the active workout session player introduced in Fase 4 · Etapa 2.

**APPLY IS DEFERRED** until `feat/session-model-seed` (Etapa 1) merges and all pre-apply gating conditions in `propose.md §Pre-apply gating conditions` are satisfied. This spec is written against the Etapa 1 contract defined in `propose.md §Etapa 1 contract`.

The change covers:

1. `SessionState` — immutable state class with derived fields (`isFullyCompleted`, `totalVolumeKg`)
2. `SessionNotifier` — `AsyncNotifier<SessionState>` family: session creation OR resume, timer, `logSet`, `abandonSession`, `finishSession`
3. `session_providers.dart` — provider wiring (`sessionRepositoryProvider`, `sessionNotifierProvider`, `activeSessionForUidProvider`)
4. `SessionPlayerScreen` — `ConsumerStatefulWidget`, full-screen, outside `ShellRoute`
5. Private widgets inline in `session_player_screen.dart`: `_SessionHeader`, `_AttendanceCard`, `_SessionStatsCard`, `_ExerciseListRow`, `_TerminarSessionButton`
6. `SetEntrySheet` — modal bottom sheet: reps + weight steppers + check button
7. `_AbandonConfirmDialog` — shared dialog for ABANDONAR button and system back gesture
8. Router additions: `/workout/session/:routineId/:dayNumber` (top-level, new session) + `/workout/session/resume/:sessionId` (top-level, resume path) + `/workout/session-summary/:sessionId` (stub)
9. Wire-up: `RoutineDetailScreen._DisabledCTABar` replaced with a live `_StartSessionCTABar`
10. **Resume flow** (Decision 12): `activeSessionForUidProvider`, app-boot active-session check on `/home`, `ResumeSessionPrompt` modal, `SessionNotifier` dual-path `build()`

**Delta only**: this spec does NOT re-describe existing `Routine`, `RoutineDay`, `RoutineSlot`, `Session`, `SetLog`, or `SessionRepository` (all from Etapa 1 contract). It only specifies what must be true AFTER this change is applied.

**File placement**: all new production files in `lib/features/workout/` (NOT a new `lib/features/session/` directory — see propose.md §Critical constraints). Test files mirror under `test/features/workout/`.

Test helper convention (mirrors `public-profile`):

```dart
Widget _wrap(Widget w) =>
    MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w));

Widget _wrapProvider(Widget w, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w)),
);

Widget _wrapRouter({
  required Widget Function(BuildContext) builder,
  required List<RouteBase> routes,
  List<Override> overrides = const [],
}) {
  final router = GoRouter(routes: routes);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
    ),
  );
}
```

All notifier tests use `ProviderContainer` with mock overrides. Presentation tests use `_wrapProvider`. `SessionRepository` mocked with `mocktail` (FakeFirebaseFirestore is not usable because the model does not exist at test-writing time).

---

## Requirements

---

### REQ-SESSION-STATE-001 — `SessionState` is an immutable class with 7 fields and 2 derived getters

`lib/features/workout/application/session_state.dart` MUST define an immutable class `SessionState`.

Required fields:
- `final Session session` — the active session document (from Etapa 1)
- `final RoutineDay day` — looked up from `Routine.days` by `dayNumber`
- `final List<SetLog> setLogs` — in-memory, append-only mirror of subcollection writes
- `final int currentExerciseIndex` — index into `day.slots` pointing to the "Ahora" row; 0-based
- `final int elapsedSeconds` — recomputed each tick; never persisted
- `final bool isFullyCompleted` — derived (see formula below); may also be stored as a field
- `final double totalVolumeKg` — derived; sum of `reps × weightKg` over all `setLogs`

Derived getters (may be computed in `copyWith` or stored as fields updated on every mutation):

```dart
// isFullyCompleted:
bool get isFullyCompleted => day.slots.every((slot) {
  final count = setLogs.where((l) => l.exerciseId == slot.exerciseId).length;
  return count >= slot.targetSets;
});

// totalVolumeKg:
double get totalVolumeKg =>
    setLogs.fold(0.0, (sum, l) => sum + (l.reps * l.weightKg));
```

`SessionState` MUST expose a `copyWith` method (manual or via `@freezed`) that accepts all 7 fields as named optional parameters.

No `fromJson`/`toJson` required — this is a pure in-memory state class.

#### Scenarios

**SCENARIO-250** — `isFullyCompleted` is `false` when `setLogs` is empty
- GIVEN a `SessionState` with `day.slots` containing 2 slots (each `targetSets: 3`) and `setLogs: []`
- WHEN `isFullyCompleted` is evaluated
- THEN the result is `false`

**SCENARIO-251** — `isFullyCompleted` is `false` when slots are partially covered
- GIVEN a `SessionState` with 2 slots (each `targetSets: 3`) and `setLogs` containing 3 entries for slot A and 2 for slot B
- WHEN `isFullyCompleted` is evaluated
- THEN the result is `false`

**SCENARIO-252** — `isFullyCompleted` is `true` when all slots reach their target
- GIVEN a `SessionState` with 2 slots (each `targetSets: 3`) and `setLogs` containing exactly 3 entries for each slot's `exerciseId`
- WHEN `isFullyCompleted` is evaluated
- THEN the result is `true`

**SCENARIO-253** — `isFullyCompleted` is `true` when a slot is over-completed (more sets than target)
- GIVEN slot A with `targetSets: 2` and slot B with `targetSets: 2`; `setLogs` has 3 entries for A and 2 for B
- WHEN `isFullyCompleted` is evaluated
- THEN the result is `true` (over-completing one slot still satisfies the condition)

**SCENARIO-254** — `totalVolumeKg` accumulates correctly across multiple set logs
- GIVEN `setLogs` = `[SetLog(reps: 10, weightKg: 60.0, ...), SetLog(reps: 8, weightKg: 40.0, ...)]`
- WHEN `totalVolumeKg` is evaluated
- THEN the result is `920.0` (10×60 + 8×40)

**SCENARIO-255** — `totalVolumeKg` is `0.0` when `setLogs` is empty
- GIVEN `setLogs: []`
- WHEN `totalVolumeKg` is evaluated
- THEN the result is `0.0`

---

### REQ-SESSION-NOTIFIER-001 — `SessionNotifier.build` supports two paths: new session and resume

`lib/features/workout/application/session_notifier.dart` MUST define:

```dart
class SessionNotifier
    extends AsyncNotifier<SessionState> {
  // family parameter: (routineId: String, dayNumber: int) for new sessions
}
```

The notifier MUST be declared as a family:
```dart
final sessionNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<SessionNotifier, SessionState, ({String routineId, int dayNumber})>(
  SessionNotifier.new,
);
```

#### Path A — New session (default)

`build((routineId, dayNumber))` MUST:
1. Await `routineByIdProvider(routineId)` to resolve the `Routine`.
2. Look up `day = routine.days.firstWhere((d) => d.dayNumber == dayNumber)`.
3. Call `repo.create(uid: currentUid, routineId: routineId, dayNumber: dayNumber)` to create the `Session` in Firestore.
4. Start a `Stream.periodic(const Duration(seconds: 1))` subscription that calls `_onTick()` each second.
5. Register `ref.onDispose(() => _timerSub.cancel())` to guarantee no leak.
6. Return a `SessionState` with `setLogs: []`, `currentExerciseIndex: 0`, `elapsedSeconds: 0`, `isFullyCompleted: false`, `totalVolumeKg: 0.0`.

#### Path B — Resume existing session

A separate notifier variant (or a `resumeSessionNotifierProvider` family — design phase finalizes the exact provider name) MUST:
1. Accept `sessionId: String` as its family parameter.
2. Call `repo.findActiveForUid(currentUid)` to retrieve the `({Session session, List<SetLog> setLogs})?` record.
3. Look up the `Routine` and `RoutineDay` from the recovered `session.routineId` and `session.dayNumber`.
4. Recompute `currentExerciseIndex` from the recovered `setLogs` — find the first slot index where the set count is below `targetSets`.
5. Recompute `elapsedSeconds` from `DateTime.now().difference(session.startedAt).inSeconds`.
6. Start the `Stream.periodic` timer (same as Path A).
7. Register `ref.onDispose(() => _timerSub.cancel())`.
8. Return a `SessionState` with the recovered `session`, `day`, `setLogs`, and recomputed derived fields.

`_onTick()` MUST update `elapsedSeconds` by computing `DateTime.now().difference(state.value!.session.startedAt).inSeconds` — this auto-corrects after foreground resume in BOTH paths.

#### Scenarios

**SCENARIO-256** — Path A: `build` creates a `Session` via `repo.create` on initialization
- GIVEN a `ProviderContainer` with `sessionRepositoryProvider` overridden by a `MockSessionRepository` that returns a stub `Session`
- AND `routineByIdProvider(routineId)` overridden to return a stub `Routine` with a matching day
- AND `currentUidProvider` overridden to return `'uid-test'`
- WHEN `container.read(sessionNotifierProvider((routineId: 'r1', dayNumber: 1)).future)` is awaited
- THEN `repo.create(uid: 'uid-test', routineId: 'r1', dayNumber: 1)` was called exactly once

**SCENARIO-257** — Path A: `build` returns `SessionState` with empty `setLogs` and `currentExerciseIndex: 0`
- GIVEN same setup as SCENARIO-256
- WHEN the provider future resolves
- THEN `state.setLogs` is empty AND `state.currentExerciseIndex == 0` AND `state.elapsedSeconds == 0` AND `state.isFullyCompleted == false`

**SCENARIO-258** — `ref.onDispose` cancels the timer subscription
- GIVEN a `ProviderContainer` with the notifier initialized and resolved
- WHEN `container.dispose()` is called
- THEN no further emissions from the internal `Stream.periodic` reach `_onTick` (verified by asserting the subscription's `cancel` was invoked — use a fake stream in the test)

**SCENARIO-318** — Path B: resume notifier calls `repo.findActiveForUid` and does NOT call `repo.create`
- GIVEN a `ProviderContainer` with `sessionRepositoryProvider` overridden by a `MockSessionRepository` that returns a non-null `({Session, List<SetLog>})` record from `findActiveForUid`
- AND `routineByIdProvider(routineId)` overridden to return a stub `Routine`
- AND `currentUidProvider` overridden to return `'uid-test'`
- WHEN the resume notifier provider is read and its future is awaited
- THEN `repo.findActiveForUid('uid-test')` was called exactly once AND `repo.create(...)` was NOT called

**SCENARIO-319** — Path B: resume notifier restores `setLogs` from repo result
- GIVEN `findActiveForUid` returns a record with `setLogs` containing 2 entries
- WHEN the resume notifier future resolves
- THEN `state.setLogs.length == 2` AND `state.setLogs` equals the entries returned by the repo

**SCENARIO-320** — Path B: resume notifier recomputes `currentExerciseIndex` from recovered set logs
- GIVEN a `Routine` with 3 slots (each `targetSets: 2`) and recovered `setLogs` containing 2 entries for slot 0's `exerciseId` (slot 0 complete) and 0 entries for slots 1 and 2
- WHEN the resume notifier future resolves
- THEN `state.currentExerciseIndex == 1` (first incomplete slot)

**SCENARIO-321** — Path B: resume notifier recomputes `elapsedSeconds` from `session.startedAt`
- GIVEN `session.startedAt` is 5 minutes before `DateTime.now()`
- WHEN the resume notifier future resolves
- THEN `state.elapsedSeconds` is approximately `300` (±2 seconds tolerance for test execution time)

---

### REQ-SESSION-NOTIFIER-002 — `logSet` appends a `SetLog`, persists via repo, and recomputes derived fields

`SessionNotifier.logSet(SetLog setLog)` MUST:
1. Call `repo.logSet(session.id, setLog)`.
2. Append `setLog` to `state.setLogs` (immutable copy — `[...current, setLog]`).
3. Recompute `isFullyCompleted` and `totalVolumeKg`.
4. Advance `currentExerciseIndex` to the next non-fully-completed slot if the current slot just reached its `targetSets` count.
5. Emit the updated `SessionState` via `state = AsyncData(newState)`.

`currentExerciseIndex` advancement rule: after `logSet`, find the first slot index in `day.slots` such that `setLogs.where((l) => l.exerciseId == slot.exerciseId).length < slot.targetSets`. Set `currentExerciseIndex` to that index. If no such slot exists (all complete), `currentExerciseIndex` stays at its last position (clamped to `day.slots.length - 1`).

#### Scenarios

**SCENARIO-259** — `logSet` calls `repo.logSet` with the session id and the provided `SetLog`
- GIVEN a notifier in a resolved state with `session.id == 'sess-1'`
- AND a mock repo that records calls
- WHEN `notifier.logSet(setLog)` is awaited
- THEN `repo.logSet('sess-1', setLog)` was called exactly once

**SCENARIO-260** — `logSet` appends the new `SetLog` to the in-memory list
- GIVEN a notifier with `state.setLogs` initially empty
- WHEN `notifier.logSet(setLog)` is called
- THEN `state.setLogs` has length 1 AND `state.setLogs.first == setLog`

**SCENARIO-261** — `currentExerciseIndex` advances when current slot reaches `targetSets`
- GIVEN a `SessionState` with 3 slots (each `targetSets: 2`); `currentExerciseIndex: 0`
- AND `setLogs` already contains 1 entry for slot 0's `exerciseId`
- WHEN `logSet` is called with a new `SetLog` for slot 0 (bringing its count to 2 == `targetSets`)
- THEN `state.currentExerciseIndex == 1` (advanced to next incomplete slot)

**SCENARIO-262** — `currentExerciseIndex` does NOT advance when current slot still has sets remaining
- GIVEN the same setup but `setLogs` starts empty
- WHEN `logSet` is called with 1 `SetLog` for slot 0 (count = 1 < targetSets = 2)
- THEN `state.currentExerciseIndex == 0` (unchanged)

**SCENARIO-263** — `isFullyCompleted` becomes `true` after the last required set of the last slot
- GIVEN a `SessionState` with 1 slot (`targetSets: 1`) and `setLogs: []`
- WHEN `logSet` is called once for that slot
- THEN `state.isFullyCompleted == true`

**SCENARIO-264** — `totalVolumeKg` accumulates correctly after two `logSet` calls
- GIVEN `setLogs` starts empty
- WHEN `logSet(SetLog(reps: 10, weightKg: 60.0, ...))` then `logSet(SetLog(reps: 8, weightKg: 40.0, ...))` are called sequentially
- THEN `state.totalVolumeKg == 920.0`

---

### REQ-SESSION-NOTIFIER-003 — `abandonSession` finalizes with `wasFullyCompleted: false`

`SessionNotifier.abandonSession()` MUST:
1. Compute `totalVolumeKg` and `durationMin` from current `state`.
2. Call `repo.finish(session.id, wasFullyCompleted: false, totalVolumeKg: <computed>, durationMin: <computed>)`.
3. Emit a terminal state (the `AsyncData` with finalized `Session`, or a dedicated `isFinished` flag — design phase decides representation; the spec only requires that the notifier no longer emits timer ticks after this call).

`durationMin` is computed as `(elapsedSeconds / 60).ceil()` (rounded up to nearest minute, minimum 1).

The notifier MUST NOT call `repo.finish` more than once. If `abandonSession` is called on an already-finished session, it MUST be a no-op or throw an assertion error (design decides).

#### Scenarios

**SCENARIO-265** — `abandonSession` calls `repo.finish` with `wasFullyCompleted: false`
- GIVEN a notifier with `state.elapsedSeconds == 90` and `state.totalVolumeKg == 500.0`
- AND a mock repo that records calls
- WHEN `notifier.abandonSession()` is awaited
- THEN `repo.finish(session.id, wasFullyCompleted: false, totalVolumeKg: 500.0, durationMin: 2)` was called exactly once

**SCENARIO-266** — Timer stops emitting after `abandonSession`
- GIVEN a notifier whose internal `Stream.periodic` is controlled by a fake timer
- WHEN `notifier.abandonSession()` is awaited
- THEN no further tick reaches `_onTick` (the subscription is cancelled or no longer emits)

---

### REQ-SESSION-NOTIFIER-004 — `finishSession` is only allowed when `isFullyCompleted` is `true`

`SessionNotifier.finishSession()` MUST:
1. Assert (or throw `StateError`) when `state.value!.isFullyCompleted == false`. This guards the bottom CTA at the business-logic level, not just the UI level.
2. Compute `totalVolumeKg` and `durationMin` from current state.
3. Call `repo.finish(session.id, wasFullyCompleted: true, totalVolumeKg: <computed>, durationMin: <computed>)`.
4. Same post-call behavior as `abandonSession` (no more timer ticks).

#### Scenarios

**SCENARIO-267** — `finishSession` calls `repo.finish` with `wasFullyCompleted: true` when complete
- GIVEN a notifier where `state.isFullyCompleted == true` (all slots at target sets)
- AND a mock repo
- WHEN `notifier.finishSession()` is awaited
- THEN `repo.finish(session.id, wasFullyCompleted: true, ...)` was called exactly once

**SCENARIO-268** — `finishSession` throws `StateError` when `isFullyCompleted` is `false`
- GIVEN a notifier where `state.isFullyCompleted == false`
- WHEN `notifier.finishSession()` is called
- THEN a `StateError` is thrown AND `repo.finish` was NOT called

---

### REQ-SESSION-PROVIDERS-001 — `sessionRepositoryProvider`, `sessionNotifierProvider`, and `activeSessionForUidProvider` defined in `session_providers.dart`

`lib/features/workout/application/session_providers.dart` MUST define:

1. `sessionRepositoryProvider` — passthrough `Provider<SessionRepository>` reading from the underlying implementation (e.g., `FirebaseSessionRepository`). Annotated with a comment: `// Etapa 1 — implementation injected here when feat/session-model-seed merges.`

2. `sessionNotifierProvider` — the family provider declared in `REQ-SESSION-NOTIFIER-001`.

3. `activeSessionForUidProvider` — see `REQ-SESSION-RESUME-001` for its full contract.

No other providers may be defined in this file in this etapa (Historial-related providers belong to Etapa 4).

#### Scenarios

**SCENARIO-269** — `sessionNotifierProvider` family key distinguishes calls by `(routineId, dayNumber)` pair
- GIVEN a `ProviderContainer` with two notifier instances:
  - `sessionNotifierProvider((routineId: 'r1', dayNumber: 1))`
  - `sessionNotifierProvider((routineId: 'r1', dayNumber: 2))`
- WHEN both are read
- THEN they are distinct provider instances (each creates its own `Session` via `repo.create`) AND `repo.create` was called twice with different `dayNumber` values

---

### REQ-SESSION-SCREEN-001 — `SessionPlayerScreen` orchestrates 3 async states

`lib/features/workout/presentation/session_player_screen.dart` MUST export a `ConsumerStatefulWidget` named `SessionPlayerScreen` accepting:
- `routineId: String`
- `dayNumber: int`

The widget MUST watch `sessionNotifierProvider((routineId: routineId, dayNumber: dayNumber))`.

State routing:
- `AsyncData<SessionState>` → render full player UI (header + cards + exercise list + bottom CTA)
- `AsyncLoading` → render a centered `CircularProgressIndicator` with color `palette.accent`
- `AsyncError` → render centered text `'No pudimos iniciar la sesión.'` in `palette.textMuted`

The widget MUST wrap its full-player subtree in `PopScope(canPop: false, onPopInvoked: (_) => _showAbandonConfirm(context))`.

The widget MUST introduce its own `Scaffold` with `backgroundColor: palette.bgPrimary` and `resizeToAvoidBottomInset: true`. (This screen is outside the `ShellRoute` so there is no parent scaffold.) The route builder in `router.dart` wraps it as `Scaffold(body: SessionPlayerScreen(...))` — the screen itself does NOT add a second `Scaffold`.

#### Scenarios

**SCENARIO-270** — Screen renders header when data resolves
- GIVEN `sessionNotifierProvider(...)` overridden with `AsyncData(state)` (stub `SessionState` with a valid `day`)
- WHEN `SessionPlayerScreen(routineId: 'r1', dayNumber: 1)` is pumped inside `_wrapProvider`
- THEN `find.byType(_SessionHeader)` finds exactly one widget (or `find.text('ABANDONAR')` finds one — implementation may export or keep private)

**SCENARIO-271** — Screen renders spinner when loading
- GIVEN `sessionNotifierProvider(...)` overridden with `AsyncLoading<SessionState>()`
- WHEN the screen is pumped (single `pump()`)
- THEN `find.byType(CircularProgressIndicator)` finds one widget AND no exercise list is visible

**SCENARIO-272** — Screen renders graceful error text on `AsyncError`
- GIVEN `sessionNotifierProvider(...)` overridden with `AsyncError<SessionState>(Exception('net'), StackTrace.empty)`
- WHEN the screen is pumped
- THEN `find.text('No pudimos iniciar la sesión.')` finds one widget AND no `FlutterError` is reported

**SCENARIO-273** — Screen is wrapped in `PopScope(canPop: false)`
- GIVEN the screen pumped with `AsyncData(state)` override
- WHEN `find.byType(PopScope)` is inspected
- THEN a `PopScope` with `canPop == false` is present in the widget tree

---

### REQ-SESSION-SCREEN-002 — `_SessionHeader` renders title and ABANDONAR button

The private `_SessionHeader` widget inside `session_player_screen.dart` MUST:
- Show the session title in format `'${routine.split.toUpperCase()} · DÍA ${dayNumber}'` (e.g., `'PUSH · DÍA 4'`).
- Render an ABANDONAR button (red outlined pill) at the top right with label `'ABANDONAR'`.
- Render a back/close button at the top left (circular icon).
- Both the ABANDONAR button and the back button MUST invoke `_showAbandonConfirm` when tapped.

#### Scenarios

**SCENARIO-274** — Header renders title in correct format
- GIVEN a `_SessionHeader` pumped with `routineSplit: 'PUSH'` and `dayNumber: 4`
- WHEN the widget tree is inspected
- THEN `find.text('PUSH · DÍA 4')` finds one widget

**SCENARIO-275** — Header renders ABANDONAR button
- GIVEN `_SessionHeader` pumped with any values
- WHEN the widget tree is inspected
- THEN `find.text('ABANDONAR')` finds exactly one widget

**SCENARIO-276** — Tapping ABANDONAR invokes the abandon callback
- GIVEN `_SessionHeader` pumped with an `onAbandon` callback that records invocations
- WHEN `tester.tap(find.text('ABANDONAR'))` and `pumpAndSettle()` are called
- THEN the `onAbandon` callback was called exactly once

---

### REQ-SESSION-SCREEN-003 — `_AttendanceCard` is a visual placeholder

The private `_AttendanceCard` widget MUST:
- Render a gym-building icon (`TreinoIcon.gym` or equivalent) in `palette.accent`.
- Render the text `'Asistencia marcada'`.
- Render the gym name resolved via `userProfileProvider.gymId` → `gymNameFromId()` helper. When the user has no gym (`gymId == null` or `'no-gym'`), render `'Sin gimnasio asignado'` instead.
- Render the current local time in `HH:mm` format at the time the widget is built.
- Render a check icon at the right.
- NO real check-in logic — this card is visual only (Etapa 6).
- Source comment MUST appear: `// Placeholder: real check-in wired in Etapa 6.`

#### Scenarios

**SCENARIO-277** — Attendance card renders `'Asistencia marcada'`
- GIVEN `_AttendanceCard` pumped with `userProfileProvider` overridden (any profile)
- WHEN the widget tree is inspected
- THEN `find.text('Asistencia marcada')` finds one widget

**SCENARIO-278** — Attendance card renders `'Sin gimnasio asignado'` when user has no gym
- GIVEN `userProfileProvider` overridden to return a profile where `gymId == null`
- WHEN `_AttendanceCard` is pumped
- THEN `find.text('Sin gimnasio asignado')` finds one widget (or the card subtitle contains that text)

---

### REQ-SESSION-SCREEN-004 — `_SessionStatsCard` renders SESIÓN ACTIVA badge, progress, and live timer

The private `_SessionStatsCard` widget MUST:
- Render the label `'SESIÓN ACTIVA'` in `palette.accent` color, UPPERCASE, `GoogleFonts.barlowCondensed`.
- Render progress text in format `'X / Y ejercicios · Z kg vol.'` where:
  - `X` = count of `day.slots` where `setLogCount(slot.exerciseId) >= slot.targetSets`
  - `Y` = `day.slots.length`
  - `Z` = `state.totalVolumeKg` formatted with 1 decimal (e.g., `'0.0'`) or as integer when `.0` (design decides format; the spec requires it is derived from `state.totalVolumeKg`)
- Render the elapsed timer as `'MM:SS'` (e.g., `'01:23'`) derived from `state.elapsedSeconds`. Updates live as `state.elapsedSeconds` changes.
- Render a `LinearProgressIndicator` with `value: X / Y` where X and Y are the completed/total exercise counts.
- All colors via `AppPalette.of(context)`. No HEX literals.

#### Scenarios

**SCENARIO-279** — Stats card renders `'SESIÓN ACTIVA'` label
- GIVEN `_SessionStatsCard` pumped with any `SessionState`
- WHEN the widget tree is inspected
- THEN `find.text('SESIÓN ACTIVA')` finds one widget

**SCENARIO-280** — Timer renders `'00:00'` when `elapsedSeconds` is 0
- GIVEN `state.elapsedSeconds == 0`
- WHEN `_SessionStatsCard` is pumped
- THEN `find.text('00:00')` finds one widget

**SCENARIO-281** — Timer renders `'01:03'` when `elapsedSeconds` is 63
- GIVEN `state.elapsedSeconds == 63`
- WHEN `_SessionStatsCard` is pumped
- THEN `find.text('01:03')` finds one widget

**SCENARIO-282** — Progress text reflects correct exercise counts
- GIVEN a `SessionState` with 3 slots, 1 fully completed (all its target sets logged)
- WHEN `_SessionStatsCard` is pumped
- THEN a text widget containing `'1 / 3 ejercicios'` is found

---

### REQ-SESSION-SCREEN-005 — `_ExerciseListRow` renders 3 visual states

The private `_ExerciseListRow` widget MUST accept:
- `slot: RoutineSlot`
- `status: ExerciseRowStatus` (enum with values `done`, `current`, `pending`)
- `completedSets: int` (for subtitle display)
- `onTap: VoidCallback?`

An `ExerciseRowStatus` enum MUST be defined (may be in `session_player_screen.dart` or `lib/features/workout/domain/exercise_row_status.dart`).

Visual states:
- **done**: filled mint check circle icon + exercise name with `TextDecoration.lineThrough` + muted text color + no chevron + `onTap: null`
- **current**: empty circle with accent border + exercise name bold + `'Ahora'` pill badge (mint background) at right + no chevron + `onTap` wired
- **pending**: empty circle + exercise name default weight + chevron-right icon at right + `onTap` wired

In all states, the subtitle MUST display `'${slot.targetSets} × ${slot.targetRepsMin}–${slot.targetRepsMax} · ${slot.targetWeightKg ?? '–'} kg'`. When `targetRepsMin == targetRepsMax`, show `'N × M reps'` (single value, design decides exact format; the value must derive from slot fields).

#### Scenarios

**SCENARIO-283** — Done row renders strikethrough exercise name and check circle
- GIVEN `_ExerciseListRow` pumped with `status: ExerciseRowStatus.done` and `slot.exerciseName: 'Squat'`
- WHEN the widget tree is inspected
- THEN a `Text` widget with `decoration: TextDecoration.lineThrough` containing `'Squat'` is found AND a filled check circle icon is present

**SCENARIO-284** — Current row renders `'Ahora'` badge
- GIVEN `_ExerciseListRow` pumped with `status: ExerciseRowStatus.current`
- WHEN the widget tree is inspected
- THEN `find.text('Ahora')` finds one widget

**SCENARIO-285** — Pending row renders chevron-right and tapping calls `onTap`
- GIVEN `_ExerciseListRow` pumped with `status: ExerciseRowStatus.pending` and a recorded `onTap` callback
- WHEN `tester.tap` on the row and `pumpAndSettle()` are called
- THEN `onTap` was called exactly once

**SCENARIO-286** — Done row `onTap` is `null` (not tappable)
- GIVEN `_ExerciseListRow` pumped with `status: ExerciseRowStatus.done` and `onTap: null`
- WHEN `tester.tap` on the row is attempted
- THEN no exception is thrown AND no callback is fired

---

### REQ-SESSION-SCREEN-006 — `_TerminarSessionButton` is mint/enabled when `isFullyCompleted` and muted/disabled otherwise

The private `_TerminarSessionButton` widget MUST accept:
- `enabled: bool`
- `onPressed: VoidCallback?`

Visual contract:
- **enabled (`true`)**: `palette.accent` background fill, white text `'TERMINAR SESIÓN'`, full opacity (`1.0`), full-width pill shape, `onPressed` wired.
- **disabled (`false`)**: `palette.bgCard` fill, `palette.textMuted` text, `Opacity(0.4)` wrapper, `onPressed: null` (NOT tappable).

No HEX literals. Matches `FollowButton.outlinedMuted` opacity treatment for the disabled state.

#### Scenarios

**SCENARIO-287** — Button renders enabled style when `isFullyCompleted` is `true`
- GIVEN `_TerminarSessionButton(enabled: true, onPressed: () {})` pumped
- WHEN the widget tree is inspected
- THEN `find.text('TERMINAR SESIÓN')` finds one widget AND no `Opacity` widget with `opacity < 1.0` wraps the button

**SCENARIO-288** — Button renders disabled style when `isFullyCompleted` is `false`
- GIVEN `_TerminarSessionButton(enabled: false, onPressed: null)` pumped
- WHEN the widget tree is inspected
- THEN `find.text('TERMINAR SESIÓN')` finds one widget AND an `Opacity` widget with `opacity == 0.4` wraps the button

**SCENARIO-289** — Tapping the disabled button is a no-op
- GIVEN `_TerminarSessionButton(enabled: false, onPressed: null)` pumped
- WHEN `tester.tap(find.text('TERMINAR SESIÓN'))` and `pumpAndSettle()` are called
- THEN no exception is thrown AND no navigation occurs

**SCENARIO-290** — Tapping the enabled button calls `onPressed`
- GIVEN `_TerminarSessionButton(enabled: true, onPressed: recordingCallback)` pumped
- WHEN `tester.tap(find.text('TERMINAR SESIÓN'))` and `pumpAndSettle()` are called
- THEN `recordingCallback` was invoked exactly once

---

### REQ-SESSION-SHEET-001 — `SetEntrySheet` shows current set info and target hint

`lib/features/workout/presentation/widgets/set_entry_sheet.dart` MUST export a `StatefulWidget` named `SetEntrySheet` accepting:
- `slot: RoutineSlot`
- `setNumber: int` (1-based — the set being entered, e.g., 2 of 3)
- `onCheck: void Function(int reps, double weightKg)`

The sheet MUST render:
- Exercise name in UPPERCASE (`slot.exerciseName.toUpperCase()`) as the title.
- Subtitle `'SET ${setNumber} DE ${slot.targetSets}'`.
- Target hint: `'Objetivo: ${slot.targetRepsMin}–${slot.targetRepsMax} reps · ${slot.targetWeightKg ?? '–'} kg'`. When `slot.targetWeightKg == null`, render `'–'` in the weight slot.
- A reps stepper (see REQ-SESSION-SHEET-002).
- A weight stepper (see REQ-SESSION-SHEET-003).
- A CHECK button (see REQ-SESSION-SHEET-004).

#### Scenarios

**SCENARIO-291** — Sheet renders exercise name in UPPERCASE
- GIVEN `SetEntrySheet` pumped with `slot.exerciseName: 'Bench Press'`, `setNumber: 1`
- WHEN the widget tree is inspected
- THEN `find.text('BENCH PRESS')` finds one widget

**SCENARIO-292** — Sheet renders set progress subtitle
- GIVEN `SetEntrySheet` pumped with `setNumber: 2` and `slot.targetSets: 4`
- WHEN the widget tree is inspected
- THEN `find.text('SET 2 DE 4')` finds one widget

**SCENARIO-293** — Sheet renders `'–'` in target hint when `targetWeightKg` is `null`
- GIVEN `slot.targetWeightKg == null`
- WHEN `SetEntrySheet` is pumped
- THEN the target hint text contains `'–'` (as rendered)

---

### REQ-SESSION-SHEET-002 — Reps stepper clamps between 0 and 50

Inside `SetEntrySheet`, the reps stepper MUST:
- Default to `slot.targetRepsMin ?? 0`.
- Step by `1` per tap of `+` or `–`.
- Clamp: minimum `0`, maximum `50`.
- The current value MUST be displayed as a large number widget between the two buttons.

#### Scenarios

**SCENARIO-294** — Reps stepper defaults to `slot.targetRepsMin`
- GIVEN `SetEntrySheet` pumped with `slot.targetRepsMin: 10`
- WHEN the widget tree is inspected
- THEN the reps value displayed is `'10'`

**SCENARIO-295** — Tapping `+` increments reps by 1
- GIVEN `SetEntrySheet` pumped with `slot.targetRepsMin: 5`
- WHEN `tester.tap` on the reps `'+'` button and `pumpAndSettle()` are called
- THEN the displayed reps value is `'6'`

**SCENARIO-296** — Reps cannot exceed 50
- GIVEN the reps stepper is at value `50`
- WHEN `tester.tap` on `'+'` is called
- THEN the displayed value remains `'50'` (clamped)

**SCENARIO-297** — Reps cannot go below 0
- GIVEN the reps stepper is at value `0`
- WHEN `tester.tap` on `'–'` is called
- THEN the displayed value remains `'0'` (clamped)

---

### REQ-SESSION-SHEET-003 — Weight stepper clamps between 0 and 500 kg in 2.5 steps

Inside `SetEntrySheet`, the weight stepper MUST:
- Default to `slot.targetWeightKg ?? 0.0`.
- Step by `2.5 kg` per tap of `+` or `–`.
- Clamp: minimum `0.0`, maximum `500.0`.
- The current value MUST be displayed as a large number widget between the two buttons.

#### Scenarios

**SCENARIO-298** — Weight stepper defaults to `slot.targetWeightKg`
- GIVEN `SetEntrySheet` pumped with `slot.targetWeightKg: 60.0`
- WHEN the widget tree is inspected
- THEN the weight value displayed is `'60.0'` (or `'60'` — implementation decides format, but the value must be 60)

**SCENARIO-299** — Tapping `+` increments weight by 2.5
- GIVEN `SetEntrySheet` pumped with `slot.targetWeightKg: 60.0`
- WHEN `tester.tap` on the weight `'+'` button and `pumpAndSettle()` are called
- THEN the displayed weight value is `'62.5'`

**SCENARIO-300** — Weight cannot exceed 500
- GIVEN the weight stepper is at value `500.0`
- WHEN `tester.tap` on `'+'` is called
- THEN the displayed value remains `'500.0'` (or `'500'` — clamped)

**SCENARIO-301** — Weight cannot go below 0
- GIVEN the weight stepper is at value `0.0`
- WHEN `tester.tap` on `'–'` is called
- THEN the displayed value remains `'0.0'` (clamped)

---

### REQ-SESSION-SHEET-004 — CHECK button submits the set and calls `onCheck`

Inside `SetEntrySheet`, the CHECK button MUST:
- Be labeled `'CHECK'` (uppercase).
- Be styled as a mint filled pill, full-width, at the bottom of the sheet.
- On tap: call `onCheck(currentReps, currentWeightKg)` with the stepper values AT the time of tap.
- After `onCheck` is called, the sheet MUST dismiss (Navigator.pop or equivalent).

The sheet does NOT call `notifier.logSet` directly — the caller is responsible for the `onCheck` callback wiring. This decouples the widget from the notifier in tests.

#### Scenarios

**SCENARIO-302** — CHECK button renders with label `'CHECK'`
- GIVEN `SetEntrySheet` pumped with any slot and `setNumber: 1`
- WHEN the widget tree is inspected
- THEN `find.text('CHECK')` finds one widget

**SCENARIO-303** — CHECK button calls `onCheck` with current stepper values
- GIVEN `SetEntrySheet` pumped with `slot.targetRepsMin: 8`, `slot.targetWeightKg: 50.0`, and a recording `onCheck`
- WHEN `tester.tap(find.text('CHECK'))` and `pumpAndSettle()` are called
- THEN `onCheck(8, 50.0)` was called exactly once

**SCENARIO-304** — CHECK button calls `onCheck` with modified values after stepper interactions
- GIVEN same setup as SCENARIO-303
- AND reps `+` tapped once (bringing reps to 9) and weight `+` tapped once (bringing weight to 52.5)
- WHEN `tester.tap(find.text('CHECK'))` and `pumpAndSettle()` are called
- THEN `onCheck(9, 52.5)` was called exactly once

---

### REQ-SESSION-DIALOG-001 — `_AbandonConfirmDialog` renders confirmation text and two buttons

An `_AbandonConfirmDialog` (private or exported, design decides) MUST render:
- Body text: `'¿Seguro que querés abandonar? Se va a guardar tu progreso hasta acá.'`
- Button `'Cancelar'` (outlined) — tapping dismisses the dialog and returns to the player.
- Button `'Abandonar'` (destructive — red/`palette.error` fill or outlined in `palette.error`) — tapping calls the provided `onConfirm` callback and dismisses.

Neither button may have `onPressed: null`.

#### Scenarios

**SCENARIO-305** — Dialog renders confirmation text
- GIVEN `_AbandonConfirmDialog` shown via `showDialog` inside a test
- WHEN the widget tree is inspected
- THEN `find.text('¿Seguro que querés abandonar? Se va a guardar tu progreso hasta acá.')` finds one widget

**SCENARIO-306** — Tapping `'Cancelar'` dismisses the dialog without calling `onConfirm`
- GIVEN `_AbandonConfirmDialog` shown with a recording `onConfirm`
- WHEN `tester.tap(find.text('Cancelar'))` and `pumpAndSettle()` are called
- THEN the dialog is no longer in the tree AND `onConfirm` was NOT called

**SCENARIO-307** — Tapping `'Abandonar'` calls `onConfirm` and dismisses
- GIVEN `_AbandonConfirmDialog` shown with a recording `onConfirm`
- WHEN `tester.tap(find.text('Abandonar'))` and `pumpAndSettle()` are called
- THEN `onConfirm` was called exactly once AND the dialog is no longer in the tree

---

### REQ-SESSION-NAV-001 — ABANDONAR flow: dialog → `abandonSession` → navigate to summary stub

When the user confirms abandonment (via ABANDONAR button or back gesture):
1. `notifier.abandonSession()` is called.
2. The app navigates to `/workout/session-summary/${session.id}`.

The summary route is a stub `Scaffold` returning placeholder text `'Resumen — próximamente'` until Etapa 3.

#### Scenarios

**SCENARIO-308** — Confirming abandon navigates to summary route
- GIVEN `SessionPlayerScreen` pumped inside `_wrapRouter` with the summary stub route registered
- AND `sessionNotifierProvider(...)` overridden with a mock notifier where `abandonSession` is a no-op
- WHEN the ABANDONAR button is tapped, the dialog `'Abandonar'` button is tapped, and `pumpAndSettle()` is called
- THEN `find.text('Resumen — próximamente')` finds one widget (the stub route was pushed)

**SCENARIO-309** — System back gesture shows the abandon confirm dialog
- GIVEN `SessionPlayerScreen` pumped with `AsyncData(state)` override
- WHEN a simulated back navigation is triggered (via `tester.binding.handlePopRoute()` or equivalent)
- THEN `find.text('¿Seguro que querés abandonar?')` is found in the overlay (the dialog appeared)

---

### REQ-SESSION-NAV-002 — TERMINAR flow: `finishSession` → navigate to summary stub

When the user taps the enabled TERMINAR SESIÓN button:
1. `notifier.finishSession()` is called.
2. The app navigates to `/workout/session-summary/${session.id}`.

#### Scenarios

**SCENARIO-310** — Tapping the enabled TERMINAR button navigates to summary route
- GIVEN `SessionPlayerScreen` pumped inside `_wrapRouter` with the stub route
- AND `sessionNotifierProvider(...)` overridden with `AsyncData(state)` where `state.isFullyCompleted == true`
- AND a mock notifier where `finishSession` is a no-op
- WHEN `tester.tap(find.text('TERMINAR SESIÓN'))` and `pumpAndSettle()` are called
- THEN `find.text('Resumen — próximamente')` finds one widget

---

### REQ-SESSION-ROUTE-001 — Top-level GoRoutes for session player (new + resume) and summary stub

`lib/app/router.dart` MUST add three top-level `GoRoute`s OUTSIDE the existing `ShellRoute`:

**Route 1 — New session:**
```dart
GoRoute(
  path: '/workout/session/:routineId/:dayNumber',
  redirect: authRedirect,
  builder: (context, state) => SessionPlayerScreen(
    routineId: state.pathParameters['routineId']!,
    dayNumber: int.parse(state.pathParameters['dayNumber']!),
  ),
),
```

**Route 2 — Resume existing session:**
```dart
GoRoute(
  path: '/workout/session/resume/:sessionId',
  redirect: authRedirect,
  builder: (context, state) => ResumeSessionPlayerScreen(
    sessionId: state.pathParameters['sessionId']!,
  ),
),
```

`ResumeSessionPlayerScreen` delegates to the same player UI as `SessionPlayerScreen` but watches the resume-path notifier variant instead of `sessionNotifierProvider`. Design phase decides whether this is a separate widget or a constructor parameter on `SessionPlayerScreen`. The spec only requires the route exists and is auth-gated.

**Route 3 — Summary stub:**
```dart
GoRoute(
  path: '/workout/session-summary/:sessionId',
  redirect: authRedirect,
  builder: (context, state) => const Scaffold(
    body: Center(child: Text('Resumen — próximamente')),
  ),
),
```

Rules for all three:
- MUST be placed OUTSIDE the `ShellRoute` so the bottom navigation bar is hidden.
- `authRedirect` guard MUST be applied.
- `dayNumber` path parameter MUST be parsed to `int` in the new-session builder.
- Required screen imports MUST be added to `router.dart`.

#### Scenarios

**SCENARIO-311** — New-session route resolves `routineId` and `dayNumber` from path parameters
- GIVEN a `GoRouter` configured with the top-level session player route
- AND `sessionNotifierProvider(...)` overridden to return `AsyncLoading`
- WHEN the router navigates to `'/workout/session/routine-abc/3'`
- THEN `SessionPlayerScreen` is rendered AND `routineId == 'routine-abc'` AND `dayNumber == 3`

**SCENARIO-312** — Session player route is OUTSIDE the ShellRoute (no bottom nav)
- GIVEN the full app router pumped and navigated to `'/workout/session/r1/1'`
- WHEN the widget tree is inspected
- THEN the bottom navigation bar widget is NOT present in the tree (or its `ShellRoute` parent is not an ancestor of `SessionPlayerScreen`)

---

### REQ-SESSION-WIRE-001 — `RoutineDetailScreen._DisabledCTABar` replaced with live `_StartSessionCTABar`

`lib/features/workout/presentation/routine_detail_screen.dart` MUST be modified:
- Remove `_DisabledCTABar` and replace it with `_StartSessionCTABar` (private widget, same file).
- `_StartSessionCTABar` MUST accept `routine: Routine` and `day: RoutineDay` as parameters.
- The `EMPEZAR` button MUST have an active `onPressed`:
  ```dart
  onPressed: () => context.push('/workout/session/${routine.id}/${day.dayNumber}'),
  ```
  `day.dayNumber` (1-based model field) MUST be used — NOT `selectedDayIndex` (0-based local state).
- The `EDITAR` button MUST remain disabled (`onPressed: null`) and retain its outlined style (Fase 5 territory).
- The `Opacity(0.4)` wrapper that previously covered BOTH buttons MUST be removed from `_StartSessionCTABar`. Only `EDITAR` may retain an individual `Opacity` treatment.
- The new widget MUST NOT add a new `Scaffold`, `SafeArea`, or `AppBackground`.

#### Scenarios

**SCENARIO-313** — `EMPEZAR` button is now tappable (not wrapped in Opacity 0.4)
- GIVEN `RoutineDetailScreen` pumped with `routineByIdProvider('r1')` overridden to return a valid `Routine`
- WHEN the widget tree is inspected
- THEN `find.text('EMPEZAR')` finds one widget AND it is NOT wrapped in `Opacity(opacity: 0.4)` (SCENARIO-092 was the old contract — this replaces it)

**SCENARIO-314** — Tapping `EMPEZAR` pushes `/workout/session/:routineId/:dayNumber`
- GIVEN `RoutineDetailScreen` pumped inside `_wrapRouter` with the session player stub route registered
- AND `routineByIdProvider('r1')` overridden to return a `Routine` with `id: 'r1'` and a day with `dayNumber: 2`
- WHEN `tester.tap(find.text('EMPEZAR'))` and `pumpAndSettle()` are called
- THEN `find.text('PLAYER_STUB')` (or equivalent route destination text) finds one widget AND the navigated path contains `'r1/2'` (NOT `'r1/0'`)

**SCENARIO-315** — `EDITAR` button remains disabled
- GIVEN `RoutineDetailScreen` pumped with valid data override
- WHEN `tester.tap(find.text('EDITAR'))` and `pumpAndSettle()` are called
- THEN no navigation occurs AND no exception is thrown

---

### REQ-SESSION-THEME-001 — No HEX literals and no direct `PhosphorIcons.*` usage in any new file

All new files in this change MUST:
- Use `AppPalette.of(context)` for ALL color values — no `Color(0xFFxxx)` or named color literals.
- Use `TreinoIcon.X` constants — no `PhosphorIconsRegular.X`, `PhosphorIconsFill.X`, or `PhosphorIconsBold.X` direct usage.
- Use only spacing values from the approved set: `{8, 12, 14, 18, 20}` for padding/gap/margin.

If any required icon constant (`TreinoIcon.gym`, `TreinoIcon.checkCircleFill`, etc.) does not yet exist in `lib/core/widgets/treino_icon.dart`, the apply phase MUST add it there as a named constant before using it in any new widget. No `PhosphorIcons.*` direct usage in the new widget files regardless.

#### Scenarios

**SCENARIO-316** — `TreinoIcon.gym` (or equivalent gym-building icon constant) is a valid `IconData`
- GIVEN the constant `TreinoIcon.gym` is referenced
- WHEN `Icon(TreinoIcon.gym)` is pumped inside `_wrap(...)`
- THEN no exception is thrown

**SCENARIO-317** — `TreinoIcon.checkCircle` (or `TreinoIcon.checkCircleFill`) is a valid `IconData`
- GIVEN the constant `TreinoIcon.checkCircle` (or `...Fill`) is referenced
- WHEN `Icon(TreinoIcon.checkCircle)` is pumped
- THEN no exception is thrown

---

## Resume Flow (Decision 12)

The following REQs cover the resume-on-reopen behavior locked in Decision 12. They are NEW relative to the previous spec version.

---

### REQ-SESSION-RESUME-001 — `activeSessionForUidProvider` exposes active session lookup

`lib/features/workout/application/session_providers.dart` MUST define:

```dart
final activeSessionForUidProvider =
    FutureProvider.autoDispose<({Session session, List<SetLog> setLogs})?>(
  (ref) async {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return null;
    final repo = ref.read(sessionRepositoryProvider);
    return repo.findActiveForUid(uid);
  },
);
```

Contract:
- **Auth-gated**: MUST return `null` immediately when `currentUidProvider` is `null` (unauthenticated). MUST NOT call `repo.findActiveForUid` in this case.
- **Return type**: `Future<({Session session, List<SetLog> setLogs})?>`. Returns the record when an active session exists, `null` when none exists.
- **No caching across sessions**: declared `autoDispose` so each consumer gets a fresh check.
- Does NOT modify or call `repo.create`, `repo.finish`, or any method other than `findActiveForUid`.

#### Scenarios

**SCENARIO-322** — Provider returns non-null record when active session exists
- GIVEN `sessionRepositoryProvider` overridden with a `MockSessionRepository` where `findActiveForUid('uid-1')` returns a stub `({session: stubSession, setLogs: []})`
- AND `currentUidProvider` overridden to return `'uid-1'`
- WHEN `container.read(activeSessionForUidProvider.future)` is awaited
- THEN the result is the stub record (non-null) AND `repo.findActiveForUid('uid-1')` was called exactly once

**SCENARIO-323** — Provider returns `null` when no active session exists
- GIVEN `findActiveForUid` returns `null`
- AND `currentUidProvider` overridden to return `'uid-1'`
- WHEN the provider future is awaited
- THEN the result is `null`

**SCENARIO-324** — Provider returns `null` and skips repo call when user is unauthenticated
- GIVEN `currentUidProvider` overridden to return `null`
- WHEN the provider future is awaited
- THEN the result is `null` AND `repo.findActiveForUid` was NOT called

---

### REQ-SESSION-RESUME-002 — App boot check triggers resume prompt on `/home` when active session exists

`lib/features/home/presentation/home_screen.dart` (or the widget rendered at the `/home` route post-auth) MUST:
- Watch `activeSessionForUidProvider` on mount.
- When the provider resolves with a non-null record, show a `ResumeSessionModal` (see REQ-SESSION-RESUME-003) as a non-dismissable dialog via `showDialog(barrierDismissible: false, ...)`.
- The dialog MUST be shown at most once per app launch — once the user chooses "Continuar" or "Descartar", the check is complete and the modal MUST NOT reappear unless the user backgrounds and re-opens the app (autoDispose handles this).
- When the provider resolves with `null`, no modal is shown and the home screen renders normally.
- When the provider is in `AsyncLoading`, the home screen renders normally (no blocking UI for the check).
- When the provider is in `AsyncError`, the home screen renders normally and the error is silently swallowed (the active-session check is best-effort, non-blocking).

Implementation note: the check MUST be triggered AFTER the user is authenticated and lands on `/home`. The modal MUST NOT be shown on the login/register screens.

#### Scenarios

**SCENARIO-325** — Resume modal appears on home when active session exists
- GIVEN `activeSessionForUidProvider` overridden with `AsyncData(({session: stubSession, setLogs: []}))` (non-null)
- AND `HomeScreen` pumped inside `_wrapProvider`
- WHEN `pumpAndSettle()` is called
- THEN `find.byType(ResumeSessionModal)` (or `find.text('Entrenamiento en curso')`) finds one widget in the overlay

**SCENARIO-326** — Resume modal does NOT appear when no active session exists
- GIVEN `activeSessionForUidProvider` overridden with `AsyncData(null)`
- AND `HomeScreen` pumped
- WHEN `pumpAndSettle()` is called
- THEN `find.text('Entrenamiento en curso')` finds zero widgets

**SCENARIO-327** — Home screen renders normally when active session check is loading
- GIVEN `activeSessionForUidProvider` overridden with `AsyncLoading()`
- AND `HomeScreen` pumped (single `pump()`)
- THEN no modal is visible AND no exception is thrown AND the normal home content is rendered

**SCENARIO-328** — Home screen renders normally when active session check errors
- GIVEN `activeSessionForUidProvider` overridden with `AsyncError(Exception('net'), StackTrace.empty)`
- AND `HomeScreen` pumped
- WHEN `pumpAndSettle()` is called
- THEN no modal is visible AND no `FlutterError` is reported in the test

---

### REQ-SESSION-RESUME-003 — `ResumeSessionModal` renders prompt with correct content and two buttons

`lib/features/workout/presentation/widgets/resume_session_modal.dart` MUST export a widget `ResumeSessionModal` accepting:
- `session: Session` — the active session to resume or discard
- `onContinue: VoidCallback` — called when user taps "Continuar"
- `onDiscard: VoidCallback` — called when user taps "Descartar"

The modal MUST render:
- Title: `'Entrenamiento en curso'`
- Body: `'Tenés un entrenamiento desde HH:MM. ¿Querés continuarlo o descartarlo?'`
  - `HH:MM` MUST be the `session.startedAt` formatted as 24-hour local time (e.g., `'18:42'` for 18:42 local time).
- Button `'Continuar'` — mint filled pill — calls `onContinue` when tapped.
- Button `'Descartar'` — red outlined pill (or `palette.error` outlined) — calls `onDiscard` when tapped.
- The modal MUST be shown with `barrierDismissible: false` at the call site. The widget itself does NOT enforce this — the call site does.
- The user MUST NOT be able to dismiss via the back gesture without choosing one of the two buttons. The parent `showDialog` call MUST pass `barrierDismissible: false` and the call site MUST also wrap with `PopScope(canPop: false)` if needed.

#### Scenarios

**SCENARIO-329** — Modal renders title `'Entrenamiento en curso'`
- GIVEN `ResumeSessionModal` pumped with a stub `session` and no-op callbacks
- WHEN the widget tree is inspected
- THEN `find.text('Entrenamiento en curso')` finds one widget

**SCENARIO-330** — Modal renders `startedAt` formatted as `HH:MM` in the body
- GIVEN `session.startedAt` is `2026-05-18 18:42:00` local time
- WHEN `ResumeSessionModal` is pumped
- THEN a text widget containing `'18:42'` is found in the body

**SCENARIO-331** — Tapping `'Continuar'` calls `onContinue` callback
- GIVEN `ResumeSessionModal` pumped with a recording `onContinue` and a no-op `onDiscard`
- WHEN `tester.tap(find.text('Continuar'))` and `pumpAndSettle()` are called
- THEN `onContinue` was called exactly once AND `onDiscard` was NOT called

**SCENARIO-332** — Tapping `'Descartar'` calls `onDiscard` callback
- GIVEN `ResumeSessionModal` pumped with a no-op `onContinue` and a recording `onDiscard`
- WHEN `tester.tap(find.text('Descartar'))` and `pumpAndSettle()` are called
- THEN `onDiscard` was called exactly once AND `onContinue` was NOT called

**SCENARIO-333** — Both buttons are present simultaneously
- GIVEN `ResumeSessionModal` pumped with any session
- WHEN the widget tree is inspected
- THEN `find.text('Continuar')` finds one widget AND `find.text('Descartar')` finds one widget

---

### REQ-SESSION-RESUME-004 — `'Continuar'` navigates to the resume route with the existing session

When the user taps `'Continuar'` in the `ResumeSessionModal`:
1. The `onContinue` callback at the call site (in `HomeScreen` or its controller) MUST call `context.push('/workout/session/resume/${session.id}')`.
2. The modal MUST dismiss after navigation (Navigator.pop of the dialog before or after push — design decides order; the dialog MUST NOT remain visible once the player is pushed).
3. The resume route `/workout/session/resume/:sessionId` pushes the player screen initialized via Path B of `SessionNotifier` (REQ-SESSION-NOTIFIER-001), restoring all prior `setLogs` and resuming the timer from `session.startedAt`.

#### Scenarios

**SCENARIO-334** — Tapping `'Continuar'` pushes the resume route
- GIVEN `HomeScreen` pumped inside `_wrapRouter` with the resume route registered as a stub
- AND `activeSessionForUidProvider` overridden with a non-null `AsyncData` result where `session.id == 'sess-resume'`
- WHEN `pumpAndSettle()` is called (modal appears), then `tester.tap(find.text('Continuar'))` and `pumpAndSettle()` are called
- THEN `find.text('RESUME_STUB')` (or the resume route's destination widget) is found AND the modal is no longer in the tree

**SCENARIO-335** — Resume player screen receives the correct `sessionId` from the route
- GIVEN the router navigated to `'/workout/session/resume/sess-42'`
- AND the resume player screen (or `ResumeSessionPlayerScreen`) pumped via the route builder
- WHEN the widget tree is inspected
- THEN the resume notifier was initialized with `sessionId: 'sess-42'`

---

### REQ-SESSION-RESUME-005 — `'Descartar'` finalizes the session as abandoned and dismisses

When the user taps `'Descartar'` in the `ResumeSessionModal`:
1. The `onDiscard` callback at the call site MUST:
   a. Compute `totalVolumeKg` from the already-recovered `setLogs` (sum of `reps × weightKg`).
   b. Compute `durationMin` from `session.startedAt` to `DateTime.now()` (rounded up to nearest minute, minimum 1).
   c. Call `repo.finish(session.id, wasFullyCompleted: false, totalVolumeKg: <computed>, durationMin: <computed>)`.
2. After `repo.finish` resolves, the modal MUST dismiss (Navigator.pop of the dialog).
3. The user MUST remain on `/home` after discarding — NO navigation to the session summary route.
4. The `activeSessionForUidProvider` MUST be invalidated (or the `autoDispose` mechanism re-read on next access) so a subsequent app launch does not re-show the modal for the now-finished session.

#### Scenarios

**SCENARIO-336** — Tapping `'Descartar'` calls `repo.finish` with `wasFullyCompleted: false`
- GIVEN `HomeScreen` pumped with `activeSessionForUidProvider` overriding to return `({session: stubSession, setLogs: twoSetLogs})`
- AND `sessionRepositoryProvider` overridden with a `MockSessionRepository` that records calls
- WHEN the modal appears and `tester.tap(find.text('Descartar'))` and `pumpAndSettle()` are called
- THEN `repo.finish(stubSession.id, wasFullyCompleted: false, ...)` was called exactly once

**SCENARIO-337** — `repo.finish` receives `totalVolumeKg` computed from recovered `setLogs`
- GIVEN `setLogs` = `[SetLog(reps: 5, weightKg: 100.0, ...), SetLog(reps: 10, weightKg: 50.0, ...)]`
- WHEN the user taps `'Descartar'`
- THEN `repo.finish(...)` was called with `totalVolumeKg: 1000.0` (5×100 + 10×50)

**SCENARIO-338** — Modal dismisses after discard and user stays on `/home`
- GIVEN same setup as SCENARIO-336
- WHEN `tester.tap(find.text('Descartar'))` and `pumpAndSettle()` are called
- THEN `find.text('Entrenamiento en curso')` finds zero widgets (modal gone) AND the home screen content is still visible AND the router has NOT navigated away from `/home`

---

## Constraint Summary

| Constraint | Enforced by |
|---|---|
| All session files in `lib/features/workout/` — no new `lib/features/session/` | File placement — grep before merge |
| `SessionPlayerScreen` introduces its own `Scaffold` (outside ShellRoute) | REQ-SESSION-SCREEN-001 |
| No HEX literals in any new file | REQ-SESSION-THEME-001 + design review |
| No `PhosphorIcons.*` direct usage | REQ-SESSION-THEME-001 |
| Spacing values restricted to `{8, 12, 14, 18, 20}` | REQ-SESSION-THEME-001 |
| `dayNumber` (1-based model field) used in route push — NOT `selectedDayIndex` | REQ-SESSION-WIRE-001 (SCENARIO-314) |
| `PopScope(canPop: false)` intercepts back gesture in player | REQ-SESSION-SCREEN-001 (SCENARIO-273) |
| `finishSession` throws `StateError` when not fully completed | REQ-SESSION-NOTIFIER-004 (SCENARIO-268) |
| Timer subscription cancelled in `ref.onDispose` (both new and resume paths) | REQ-SESSION-NOTIFIER-001 (SCENARIO-258) |
| `SetEntrySheet.onCheck` decoupled from notifier (caller wires it) | REQ-SESSION-SHEET-004 |
| `_DisabledCTABar` fully removed and replaced | REQ-SESSION-WIRE-001 |
| Session player route OUTSIDE ShellRoute (no bottom nav) | REQ-SESSION-ROUTE-001 (SCENARIO-312) |
| Summary route is a stub `Scaffold` until Etapa 3 | REQ-SESSION-ROUTE-001 |
| Resume route `/workout/session/resume/:sessionId` OUTSIDE ShellRoute | REQ-SESSION-ROUTE-001 |
| `activeSessionForUidProvider` is auth-gated (returns null when uid is null) | REQ-SESSION-RESUME-001 (SCENARIO-324) |
| `ResumeSessionModal` shown with `barrierDismissible: false` | REQ-SESSION-RESUME-003 |
| Discard path calls `repo.finish` (NOT `repo.create`, NOT navigation to summary) | REQ-SESSION-RESUME-005 (SCENARIO-338) |
| Discard stays on `/home` — no navigation to summary stub | REQ-SESSION-RESUME-005 (SCENARIO-338) |
| Resume path does NOT call `repo.create` | REQ-SESSION-NOTIFIER-001 (SCENARIO-318) |
| TDD: test file committed BEFORE production code in every work-unit | Enforced by tasks phase |
| All pre-existing tests remain green | Scope boundary |
| `flutter analyze` 0 issues + `dart format .` passing | Quality gate |

---

## Deferred / Out of scope

The following items are explicitly NOT requirements for this change:

| Item | Where it lands |
|---|---|
| Post-session summary screen (Resumen) real UI | Etapa 3 |
| Attendance card real check-in logic | Etapa 6 |
| Historial / past sessions list | Etapas 4 + 5 |
| Orphaned `active` session cleanup (non-resume path) | Etapa 4 |
| Pause/resume across app restarts (background-safe) | Fase 6 |
| Background-accurate timer | Fase 6 |
| RPE input on `SetLog` | Deferred — field is nullable, no UI this etapa |
| Rest timer haptic / sound on hit zero | Polish — out of scope |
| Edit a logged set | Future — append-only this etapa |
| `'Compartir'` CTA from player | Etapa 3 |
| `EDITAR` button functional | Fase 5 |
| `SetLog.rpe` UI | Deferred — field exists in model, no UI |
| Resume prompt on screens other than `/home` | Out of scope — only `/home` post-auth landing triggers the check |
| Multiple simultaneous active sessions cleanup | Defensive — `findActiveForUid` returns most-recent; full cleanup is Etapa 4 |

---

## Files this spec covers

### New files

| File | REQs |
|---|---|
| `lib/features/workout/application/session_state.dart` | STATE-001 |
| `lib/features/workout/application/session_notifier.dart` | NOTIFIER-001 (paths A + B), 002, 003, 004 |
| `lib/features/workout/application/session_providers.dart` | PROVIDERS-001, RESUME-001 |
| `lib/features/workout/presentation/session_player_screen.dart` | SCREEN-001, 002, 003, 004, 005, 006, NAV-001, NAV-002 |
| `lib/features/workout/presentation/widgets/set_entry_sheet.dart` | SHEET-001, 002, 003, 004 |
| `lib/features/workout/presentation/widgets/resume_session_modal.dart` | RESUME-003, 004, 005 |
| `test/features/workout/application/session_notifier_test.dart` | NOTIFIER-001..004 (SCENARIO-256..268, 318..321) |
| `test/features/workout/application/session_providers_test.dart` | PROVIDERS-001 (SCENARIO-269), RESUME-001 (SCENARIO-322..324) |
| `test/features/workout/presentation/session_player_screen_test.dart` | SCREEN-001..006, DIALOG-001, NAV-001, NAV-002 (SCENARIO-270..310) |
| `test/features/workout/presentation/widgets/set_entry_sheet_test.dart` | SHEET-001..004 (SCENARIO-291..304) |
| `test/features/workout/presentation/widgets/resume_session_modal_test.dart` | RESUME-003..005 (SCENARIO-329..338) |

### Modified files

| File | Change | REQs |
|---|---|---|
| `lib/app/router.dart` | Add 3 top-level `GoRoute`s outside `ShellRoute` (new session + resume + summary stub) | ROUTE-001 |
| `lib/features/workout/presentation/routine_detail_screen.dart` | Replace `_DisabledCTABar` → `_StartSessionCTABar` | WIRE-001 |
| `lib/core/widgets/treino_icon.dart` | Add `TreinoIcon.gym`, `TreinoIcon.checkCircle` (and others) if not present | THEME-001 |
| `lib/features/home/presentation/home_screen.dart` | Watch `activeSessionForUidProvider` on mount; show `ResumeSessionModal` when non-null | RESUME-002 |

### NOT modified (scope boundary)

- `lib/features/workout/domain/routine.dart`
- `lib/features/workout/domain/routine_day.dart`
- `lib/features/workout/domain/routine_slot.dart`
- `lib/features/workout/application/routine_providers.dart`
- `lib/features/feed/` (any file)
- `lib/features/auth/` (any file)
- `firestore.rules` (covered by Etapa 1)
- `pubspec.yaml`
- Any existing test file (scenarios are additive, not modifications)

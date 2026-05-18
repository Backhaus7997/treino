# Proposal: session-player

**Change**: Fase 4 · Etapa 2 — Active workout session player
**Branch**: `feat/session-player`
**Status**: SDD planning ONLY — apply phase is **DEFERRED** until Etapa 1 (`feat/session-model-seed`) lands
**Date**: 2026-05-18
**Depends on**: Etapa 1 (`feat/session-model-seed`) — see "Pre-apply gating conditions" below

---

## 1. Why

`RoutineDetailScreen._DisabledCTABar` has rendered an `Opacity(0.4)` "EMPEZAR ENTRENAMIENTO" button since Fase 2. It is the single most user-visible CTA in the entire app and it has been a non-functional stub for months. Without this etapa **the app does not actually let the user train** — every other feature (routines, exercises, profile) is preparation for the workout itself.

This etapa closes that gap by delivering the full active-session player: a screen the user opens when they hit "EMPEZAR", uses live during a workout, and closes when they finish (or abandon). It is the missing core of the product loop.

Success looks like: a user taps "EMPEZAR", logs sets exercise-by-exercise via a modal sheet, sees a running timer and progress, and ends the session either by completing every set (mint "TERMINAR SESIÓN" CTA enabled) or by explicitly abandoning (red "ABANDONAR" with confirm). Their Session and every SetLog are persisted to Firestore as they go.

---

## 2. What

### Production deliverables

**New feature directory**: `lib/features/session/` — domain + data live in Etapa 1, so this etapa only adds application + presentation layers.

```
application/
  session_providers.dart       (sessionRepositoryProvider passthrough + sessionNotifierProvider family)
  session_notifier.dart        (AsyncNotifier<SessionState> — business logic, timer, set logging)
  session_state.dart           (immutable SessionState class)
presentation/
  session_player_screen.dart   (ConsumerStatefulWidget — full-screen player)
  widgets/
    _session_header.dart       (top bar: back chevron + title + ABANDONAR pill)
    _attendance_card.dart      (Asistencia marcada placeholder — visual only)
    _session_stats_card.dart   (SESIÓN ACTIVA + N/M ejercicios + timer + progress bar)
    _exercise_list_row.dart    (per-exercise row: done / now / pending state)
    _terminar_session_button.dart (bottom pill CTA with disabled/enabled states)
    set_entry_sheet.dart       (modal bottom sheet: reps + weight steppers + check)
    _abandon_confirm_dialog.dart (shared by ABANDONAR + back gesture)
```

### Route addition

`/workout/session/:routineId/:dayNumber` — **TOP-LEVEL GoRoute outside ShellRoute** so the bottom nav hides during workout. This matches the mockup (no bottom bar visible).

Stub route `/workout/session-summary/:sessionId` added for Etapa 3 — initially returns a placeholder Scaffold; the finish/abandon flow navigates there.

### Wire-up

`RoutineDetailScreen._DisabledCTABar` → replace "EMPEZAR" button with live `FilledButton`. `onPressed` becomes:

```dart
() => context.push('/workout/session/${routine.id}/${day.dayNumber}')
```

where `day = routine.days[selectedDayIndex]`. Note: pass `day.dayNumber` (1-based, from model), NOT `selectedDayIndex` (0-based, local state) — see risk in explore §7.

### Test deliverables

- Unit tests for `SessionNotifier`: start session, log set, advance exercise, compute `isFullyCompleted`, abandon, finish, timer tick, dispose cancels timer
- Widget tests for `SessionPlayerScreen`: renders header + cards + list, bottom CTA disabled when incomplete, enabled when complete, ABANDONAR opens confirm dialog
- Widget test for `SetEntrySheet`: stepper +/- buttons, check button calls notifier
- Integration test for the navigation flow: tap EMPEZAR → player opens → log set → state updates

---

## 3. How

### Widget tree of `SessionPlayerScreen`

```
SessionPlayerScreen (ConsumerStatefulWidget)
  PopScope(canPop: false, onPopInvoked: → _showAbandonConfirm)
    Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: palette.bgPrimary,
      body: SafeArea(
        Column(
          _SessionHeader(onAbandon: → _showAbandonConfirm),
          Expanded(
            ListView(
              _AttendanceCard(),                 // placeholder visual
              _SessionStatsCard(state),          // timer + N/M + volume + progress
              _SectionLabel('EJERCICIOS'),
              ...state.day.slots.map((slot) =>
                _ExerciseListRow(
                  slot: slot,
                  status: _statusFor(slot, state),  // done | now | pending
                  onTap: status != done ? () => _openSetEntry(slot) : null,
                ),
              ),
            ),
          ),
          _TerminarSessionButton(
            enabled: state.isFullyCompleted,
            onPressed: state.isFullyCompleted ? () => _finishSession() : null,
          ),
        ),
      ),
    )
```

`_openSetEntry(slot)` calls `showModalBottomSheet(isScrollControlled: true, builder: (_) => SetEntrySheet(slot: slot, setNumber: nextSetNumberFor(slot)))`.

### `SessionState` shape

```dart
class SessionState {
  final Session session;                  // from Etapa 1
  final RoutineDay day;                   // looked up from Routine by dayNumber
  final List<SetLog> setLogs;             // in-memory mirror of subcollection writes
  final int currentExerciseIndex;         // which slot in day.slots is "Ahora"
  final int elapsedSeconds;               // recomputed each tick from session.startedAt
  final bool isFullyCompleted;            // derived; see logic below
  final double totalVolumeKg;             // derived; sum of reps * weightKg over setLogs
}
```

`isFullyCompleted` logic (the crucial derived field that gates the bottom CTA):

```dart
bool get isFullyCompleted => day.slots.every((slot) {
  final setsForSlot = setLogs.where((l) => l.exerciseId == slot.exerciseId).length;
  return setsForSlot >= slot.targetSets;
});
```

### `SessionNotifier` lifecycle

`SessionNotifier extends AsyncNotifier<SessionState>` with:

```dart
@override
Future<SessionState> build(String routineId, int dayNumber) async {
  // 1. Resolve routine + day
  final routine = await ref.read(routineByIdProvider(routineId).future);
  final day = routine.days.firstWhere((d) => d.dayNumber == dayNumber);

  // 2. Create Session in Firestore (status=active)
  final repo = ref.read(sessionRepositoryProvider);
  final uid = ref.read(currentUidProvider);
  final session = await repo.create(uid: uid, routineId: routineId, dayNumber: dayNumber);

  // 3. Start timer stream
  final timerSub = Stream.periodic(const Duration(seconds: 1)).listen((_) => _onTick());
  ref.onDispose(() => timerSub.cancel());

  return SessionState(
    session: session, day: day, setLogs: [],
    currentExerciseIndex: 0, elapsedSeconds: 0,
    isFullyCompleted: false, totalVolumeKg: 0,
  );
}

Future<void> logSet({required RoutineSlot slot, required int reps, required double weightKg}) async { ... }
Future<void> abandonSession() async { ... }   // calls repo.finish(wasFullyCompleted: false)
Future<void> finishSession() async { ... }    // calls repo.finish(wasFullyCompleted: true)
void _onTick() { ... }                        // recompute elapsedSeconds from session.startedAt
```

### Modal sheet flow

1. User taps a non-done `_ExerciseListRow` → `showModalBottomSheet(...)`
2. `SetEntrySheet` shows:
   - Header: exercise name + "Serie N de M" (N = next set, M = `slot.targetSets`)
   - Reps stepper: `-` button · big number · `+` button. Default = `slot.targetRepsMin`.
   - Weight stepper: `-` (2.5 kg) · big number · `+` (2.5 kg). Default = `slot.targetWeightKg ?? 0`.
   - Rest timer area (countdown, auto-starts on check) — visible AFTER first check, hidden initially.
   - Big mint check button at bottom.
3. User adjusts reps + weight → taps check → `notifier.logSet(slot, reps, weightKg)`:
   - Writes `SetLog` to Firestore subcollection (via `repo.logSet`)
   - Appends to `state.setLogs` in memory
   - Recomputes `isFullyCompleted` + `totalVolumeKg` + `currentExerciseIndex`
   - Starts rest timer countdown (from `slot.restSeconds`)
4. After last set of an exercise: sheet auto-dismisses, row turns "done" (green check), `currentExerciseIndex` advances to next pending slot.
5. User can also tap outside the sheet to dismiss mid-exercise — partial progress is preserved (the SetLogs already written stay in Firestore).

### Disabled/enabled logic for bottom CTA

```dart
_TerminarSessionButton(
  enabled: state.isFullyCompleted,
  // when enabled: mint fill, white text, opacity 1.0, onPressed wired
  // when disabled: bgCard fill, fgMuted text, opacity 0.4, onPressed null
)
```

### Two-button finalize semantics

| Button | Style | Path | Session result |
|---|---|---|---|
| Top right "ABANDONAR ENTRENAMIENTO" | red outlined, destructive | always enabled | confirm dialog → `repo.finish(wasFullyCompleted: false)` |
| Bottom "TERMINAR SESIÓN ✓" | mint pill | enabled only when `isFullyCompleted` | direct → `repo.finish(wasFullyCompleted: true)` |
| System back / swipe gesture | n/a | always | same confirm dialog as ABANDONAR |

Both paths navigate to `/workout/session-summary/${session.id}` after finalize. For Etapa 2 the summary route is a stub.

---

## 4. Trade-offs accepted (12 locked decisions)

| # | Decision | Rationale |
|---|---|---|
| 1 | Set entry via `showModalBottomSheet` per exercise | Mockup shows summary rows with `>` drill-down — sheet matches mockup; no nested routes; modal flow keeps list visible behind |
| 2 | Persistence Hybrid (Option C) | Crash-resilient at gym (WiFi/calls drop). Session doc on start + SetLog per set check; ~30-50 writes/session is negligible cost |
| 3 | SetLog in subcollection `users/{uid}/sessions/{id}/sets/{setId}` | Idiomatic Firestore 1:N; owner-only rules via parent scope; arrays would conflict with per-set eager writes |
| 4 | `Stream.periodic` timer in-app only | Simple, no deps. Elapsed recomputed from `session.startedAt` per tick → auto-corrects on foreground resume. Background-accurate timer is Fase 6 polish |
| 5 | Back button → same confirm dialog as ABANDONAR | Single source of truth for "exit session" UX; prevents accidental data loss |
| 6 | Route `/workout/session/:routineId/:dayNumber` top-level (outside ShellRoute) | Hides bottom nav for immersive workout, matches mockup. `context.push` from shell stacks above shell — confirmed pattern |
| 7 | Weight + reps via +/- stepper buttons | Hands chalked/sweaty at gym; small increments (2.5kg plates); avoids keyboard jank in bottom sheet |
| 8 | Rest timer auto-start on set check | Industry standard (Strong, Hevy, Fitbod); reads `slot.restSeconds`; user can dismiss |
| 9 | Two TERMINAR buttons with distinct semantics | Top = destructive abandon (always enabled, confirm dialog, `wasFullyCompleted=false`). Bottom = success finish (enabled only when complete, no confirm, `wasFullyCompleted=true`) |
| 10 | `Session.wasFullyCompleted: bool` (default false) | Analytics signal: distinguishes abandoned vs completed without ambiguity. Default false is safe; only the "all sets logged + bottom CTA tapped" path sets true |
| 11 | Back gesture intercept via `PopScope` | Flutter 3.13+ standard; `canPop: false` + `onPopInvoked` opens the same confirm dialog. No platform-specific code |
| 12 | **Resume prompt on app re-open if active session exists** | If user crashes/closes mid-session, on next app open we check `findActiveForUid(uid)` and show modal: "Tenés un entrenamiento en curso desde HH:MM. ¿Continuar o descartar?". Continuar → load existing Session into the player (restore SetLogs already logged). Descartar → finalize as abandoned (`wasFullyCompleted=false`). Matches Strong/Hevy UX expectation; resolves the orphan session problem proactively |

---

## 5. Out of scope (explicit deferrals)

| Item | Where it lands |
|---|---|
| Resumen post-entreno screen (post-finish summary UI) | Etapa 3 — for now the summary route is a stub `Scaffold` placeholder |
| Asistencia marcada functional check-in | Etapa 6 — the card is visual-only this etapa, hardcoded labels |
| Historial / Insights / past sessions list | Etapas 4 + 5 |
| Pause/resume across app restarts | Fase 6 |
| Background-accurate timer | Fase 6 |
| "Compartir" CTA from player or summary | Etapa 3 |
| RPE (Rated Perceived Exertion) input | Deferred — `SetLog.rpe` is nullable in Etapa 1 model; no UI for it this etapa |
| Cleanup of orphaned `active` Sessions (app crash mid-session) | Etapa 4 (Historial filters them out / "resume or discard" prompt) |
| Rest timer haptic / sound on hit zero | Polish — out of scope |
| Edit a logged set (correct a wrong rep count) | Future — for now user can only append, not edit |

---

## 6. Success criteria

Each is testable.

- [ ] Tap "EMPEZAR ENTRENAMIENTO" in `RoutineDetailScreen` → navigates to `/workout/session/{routineId}/{dayNumber}` → bottom nav is hidden → Session is created in Firestore with `status=active`, `startedAt=now`, `wasFullyCompleted=false`
- [ ] Player renders: `_SessionHeader` (back + title + ABANDONAR), `_AttendanceCard` placeholder, `_SessionStatsCard` (SESIÓN ACTIVA badge + N/M ejercicios + running timer + progress bar), exercise list with row states (done/now/pending), bottom TERMINAR pill (disabled style initially)
- [ ] Timer increments every second; recomputed from `session.startedAt` so foreground resume after background shows correct elapsed
- [ ] Tap pending or current exercise row → `SetEntrySheet` opens modally
- [ ] +/- steppers adjust reps and weight; tap check → SetLog written to Firestore subcollection; sheet stays open if more sets remain for that exercise (advances to next set number), auto-dismisses after last set
- [ ] After logSet: in-memory state updates; row appearance updates (current → done when all sets logged); `currentExerciseIndex` advances to next pending slot; `totalVolumeKg` accumulates
- [ ] Bottom TERMINAR pill changes to enabled style (mint, full opacity) only when every slot has its target sets logged
- [ ] Tap TERMINAR (enabled) → calls `repo.finish(sessionId, wasFullyCompleted: true, totalVolumeKg, durationMin)` → navigates to `/workout/session-summary/{sessionId}` (stub)
- [ ] Tap ABANDONAR (top right) → confirm dialog "¿Seguro que querés abandonar? Se va a guardar tu progreso hasta acá." → confirm: `repo.finish(... wasFullyCompleted: false)` → navigate to summary stub; cancel: stay
- [ ] System back / swipe gesture mid-session → same confirm dialog
- [ ] `flutter analyze` reports 0 issues
- [ ] All new tests pass; full project test suite remains green
- [ ] Theme correctness: `AppPalette.of(context)` used throughout, no HEX literals; `TreinoIcon.X` everywhere, no `PhosphorIcons.X` direct usage

---

## 7. Risks

Priority-ordered.

### P0 — Etapa 1 not yet merged (BLOCKING)

The entire apply phase is blocked. `Session`, `SetLog`, `SessionRepository`, and Firestore rules don't exist yet. Dev A owns Etapa 1 (`feat/session-model-seed`). See §"Pre-apply gating conditions" for exact merge criteria.

**Mitigation**: this proposal is shared with Dev A IMMEDIATELY so he can incorporate the contract in §"Etapa 1 contract" below — or push back before designing Etapa 2 deeper.

### P1 — Session model shape drift

If Dev A's actual `Session` differs from our assumed shape (renamed field, missing `wasFullyCompleted`, different `status` enum values), our spec + design must rebase.

**Mitigation**: lock the contract in §"Etapa 1 contract" below. Re-run propose phase if Etapa 1 lands with deviations.

### P1 — Top-level GoRoute outside ShellRoute edge case

GoRouter's `context.push` from inside a ShellRoute to a sibling top-level route is supported but a known edge case (the new route renders above the shell, the shell remains in memory).

**Mitigation**: a focused widget test that pumps the router with the player route in isolation. If `push` misbehaves, fall back to `go` and accept losing the shell's navigation history on return.

### P2 — Timer leak on hard navigation

`Stream.periodic` subscription must be cancelled in `ref.onDispose`. If the user pops without going through finish/abandon, and disposal doesn't fire, the stream leaks.

**Mitigation**: unit test on `SessionNotifier` that asserts disposing the provider cancels the subscription (use a fake timer or count emissions before/after dispose).

### P2 — `isFullyCompleted` correctness

The derived field that gates the most important CTA. Edge cases: an exercise with 4 target sets and only 3 logs → not complete. An exercise with 0 target sets (shouldn't exist but guard anyway) → trivially complete. An extra set logged beyond target (user double-tapped check) → still complete.

**Mitigation**: exhaustive unit test scenarios — empty, partial, exact match, overshoot, mixed completion across exercises.

### P3 — Bottom sheet keyboard handling

If a user long-presses a stepper number to enter manually (future feature) the keyboard appears. For Etapa 2 we have stepper-only, so the keyboard isn't summoned. Standard `resizeToAvoidBottomInset: true` on Scaffold is sufficient.

**Mitigation**: leave the stepper as the only input path this etapa. Flag manual entry as future enhancement.

### P3 — Orphaned active sessions on hard crash

If app hard-crashes between `create()` and `finish()` (forced kill, OS OOM), a Session with `status=active` persists in Firestore. Historial will eventually show it as "incomplete".

**Mitigation**: defer cleanup logic to Etapa 4 (Historial). The data is not lost — just flagged active forever. Acceptable for MVP.

---

## 8. Review Workload Forecast (MANDATORY)

Best-effort LOC estimates for the apply phase (post-Etapa-1-merge).

### Production code

| File | Est. LOC |
|---|---|
| `session_state.dart` (immutable state class + derived getters) | ~70 |
| `session_notifier.dart` (AsyncNotifier + timer + logSet/finish/abandon) | ~140 |
| `session_providers.dart` | ~20 |
| `session_player_screen.dart` (screen scaffold + PopScope + composition) | ~80 |
| `_session_header.dart` | ~35 |
| `_attendance_card.dart` | ~30 |
| `_session_stats_card.dart` | ~50 |
| `_exercise_list_row.dart` (3 visual states) | ~60 |
| `_terminar_session_button.dart` (disabled/enabled styles) | ~30 |
| `set_entry_sheet.dart` (steppers + check + rest timer) | ~110 |
| `_abandon_confirm_dialog.dart` | ~25 |
| Router additions (top-level + summary stub) | ~20 |
| `RoutineDetailScreen` wire-up edit | ~15 |
| **Production subtotal** | **~685** |

### Test code

| File | Est. LOC |
|---|---|
| `session_notifier_test.dart` (start, logSet, isFullyCompleted, abandon, finish, dispose, timer) | ~250 |
| `session_player_screen_test.dart` (render, CTA states, ABANDONAR confirm) | ~120 |
| `set_entry_sheet_test.dart` (steppers, check, autostart timer) | ~80 |
| `navigation_test.dart` (EMPEZAR → push, ABANDONAR/back → confirm → summary) | ~50 |
| **Test subtotal** | **~500** |

### Totals + chained-PR signal

- Total estimated diff: **~1,185 LOC** (production + tests)
- Production budget vs 400-line threshold: **HIGH RISK** — production alone is ~685 LOC, ~1.7× the budget
- Chained PRs recommended: **YES — strongly recommended**
- Suggested split:
  - **PR 1**: state + notifier + providers + notifier tests (~480 LOC) — pure logic, no UI, easy to review
  - **PR 2**: screen + private widgets + sheet + dialog + widget/integration tests + router + wire (~705 LOC) — UI on top of merged logic
- 400-line budget risk: **High**
- Decision needed before apply: **YES** — `ask-on-risk` strategy → orchestrator must surface chained vs single-PR-with-`size:exception` decision after `sdd-tasks` finalizes LOC estimates
- Apply phase status: **DEFERRED until Etapa 1 merges** — at that point, re-evaluate LOC estimates against Dev A's actual model shape before deciding chained vs single PR

---

## Etapa 1 contract — required from Dev A

This is the surface area `feat/session-player` consumes. Etapa 1 MUST deliver at minimum:

### `Session` model — 9 fields

```dart
@freezed
class Session with _$Session {
  const factory Session({
    required String id,
    required String uid,
    required String routineId,
    required int dayNumber,
    @TimestampConverter() required DateTime startedAt,
    @TimestampConverter() DateTime? finishedAt,
    required SessionStatus status,          // active | finished
    @Default(false) bool wasFullyCompleted, // NEW — analytics signal
    double? totalVolumeKg,                  // computed at finish
    int? durationMin,                       // computed at finish
  }) = _Session;
  factory Session.fromJson(Map<String, Object?> json) => _$SessionFromJson(json);
}

enum SessionStatus { active, finished }
```

### `SetLog` model — 6 fields

```dart
@freezed
class SetLog with _$SetLog {
  const factory SetLog({
    required String id,
    required String exerciseId,
    required int setNumber,                 // 1-based
    required int reps,
    required double weightKg,
    int? rpe,                               // nullable; UI deferred
    @TimestampConverter() required DateTime completedAt,
  }) = _SetLog;
  factory SetLog.fromJson(Map<String, Object?> json) => _$SetLogFromJson(json);
}
```

### `SessionRepository` — 5 required methods + 1 optional

```dart
abstract class SessionRepository {
  Future<Session> create({                                              // REQUIRED
    required String uid,
    required String routineId,
    required int dayNumber,
  });

  Future<void> logSet(String sessionId, SetLog setLog);                 // REQUIRED

  Future<Session> finish(                                                // REQUIRED
    String sessionId, {
    required bool wasFullyCompleted,
    required double totalVolumeKg,
    required int durationMin,
  });

  Future<List<Session>> listByUid(String uid);                          // REQUIRED (used by Historial Etapa 4 but contract locks now)

  /// Returns the latest active session for [uid] (status == active), or null.
  /// Used by the resume-on-reopen flow (Decision 12). If multiple actives
  /// exist (shouldn't, but defensive), returns the most recent by startedAt.
  /// Also returns the loaded SetLogs for that session so the player can
  /// restore state without an extra query.
  Future<({Session session, List<SetLog> setLogs})?> findActiveForUid(    // REQUIRED (Decision 12)
    String uid,
  );

  Stream<Session> watch(String sessionId);                              // OPTIONAL — deferred to Fase 6 resume
}
```

### Firestore paths

- Session doc: `users/{uid}/sessions/{sessionId}`
- Sets subcollection: `users/{uid}/sessions/{sessionId}/sets/{setId}`

### Firestore rules

```
match /users/{uid}/sessions/{sessionId} {
  allow read, write: if request.auth.uid == uid;
  match /sets/{setId} {
    allow read, write: if request.auth.uid == uid;
  }
}
```

The parent `{uid}` segment scopes everything to owner — no additional predicates needed.

---

## Pre-apply gating conditions

Apply phase MUST NOT start until every box below is checked.

1. [ ] `feat/session-model-seed` (Etapa 1) merged into `main`
2. [ ] `Session` model contains all 9 fields listed above (especially `wasFullyCompleted: bool` with default false and `status: SessionStatus`)
3. [ ] `SetLog` model contains all 6 fields listed above
4. [ ] `SessionRepository` exposes the **5 required methods** (`create`, `logSet`, `finish`, `listByUid`, **`findActiveForUid`** — last one per Decision 12); `watch` is optional
5. [ ] Firestore rules deployed covering `users/{uid}/sessions/**` and `users/{uid}/sessions/{id}/sets/**` as owner-only R/W
6. [ ] Branch `feat/session-player` rebased onto post-Etapa-1 `main`
7. [ ] LOC re-estimate verified against Dev A's actual code (the ~835 production LOC estimate assumes the model shape above + resume flow from Decision 12; deviations may change it materially)
8. [ ] Delivery strategy decision recorded: chained PRs (logic-only PR1 + UI PR2) vs single PR with `size:exception` label

**If ANY condition fails post-merge**: re-run the propose phase to adapt the contract and risks. Do not paper over drift in spec/design.

---

## Status summary

| Phase | Status |
|---|---|
| Explore | Done (`openspec/changes/session-player/explore.md`) |
| **Propose** | **This document — done** |
| Spec | Done (`openspec/changes/session-player/spec.md`) |
| Design | Done (`openspec/changes/session-player/design.md`) |
| Tasks | Done (`openspec/changes/session-player/tasks.md`) |
| **Apply** | **Unblocked — Etapa 1 merged (PR #34, commit 51cd701); contract amended in commit b2328b3** |
| Verify | Pending |
| Archive | Pending |

All 12 user decisions are LOCKED. Subsequent phases must not re-propose them.

---

## Post-merge contract reconciliation (2026-05-18)

Etapa 1 merged with deviations from the assumed `Etapa 1 contract` section above. Implementation in this branch adapts as follows:

### Resolved via contract amendment (commit `b2328b3` on this branch)

| Assumed | Etapa 1 delivered | Resolution |
|---|---|---|
| `Session.dayNumber: int` required | Not present | Added as `@Default(1) int dayNumber` to `Session`. `SessionRepository.create` gains optional `int dayNumber = 1` param. |
| `Session.wasFullyCompleted: bool` with default false | Not present | Added as `@Default(false) bool wasFullyCompleted`. `SessionRepository.finish` gains optional `bool wasFullyCompleted = false` param. |

### Adapted in implementation (no code patch needed)

| Assumed | Etapa 1 delivered | Implementation adaptation |
|---|---|---|
| `findActiveForUid(uid) → Future<({Session, List<SetLog>})?>` (Decision 12) | `getActive(uid) → Future<Session?>` + separate `listSetLogs({uid, sessionId})` | Resume flow calls both sequentially in the notifier — adds one extra round-trip vs one tuple call. Same end result. |
| `logSet(sessionId, setLog)` | `addSetLog({uid, sessionId, setLog})` | Adapt notifier to pass `uid` (already in scope via `currentUidProvider`). Slightly more verbose call site. |
| `finish(sessionId, {wasFullyCompleted, totalVolumeKg, durationMin})` | `finish({uid, sessionId, finishedAt, totalVolumeKg, durationMin, wasFullyCompleted})` | Notifier passes `uid` + computes `finishedAt = DateTime.now()`. |
| `create({uid, routineId, dayNumber})` | `create({uid, routineId, routineName, startedAt, dayNumber})` | Notifier reads `routineName` from already-resolved Routine and passes `startedAt = DateTime.now()`. |
| SetLog subcollection at `users/{uid}/sessions/{id}/sets/{setId}` | Path is `.../setLogs/{setLogId}` | Cosmetic rename in our internal docs only — Firestore rules already cover `setLogs`. |

### Notes for downstream phases

- `spec.md` and `design.md` mostly describe player UX/state and remain accurate — they describe what the player DOES, not how it talks to the repo. The 5 adaptations above only affect the few lines of glue code in the notifier.
- Tasks list in `tasks.md` is unaffected — task descriptions are framed at the behavior level, not the API surface level.

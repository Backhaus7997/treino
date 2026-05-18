# Exploration: session-player

**Change**: Fase 4 · Etapa 2 — Active workout session player  
**Branch**: `feat/session-player`  
**Status**: Planning only — apply deferred until `feat/session-model-seed` (Etapa 1) merges  
**Date**: 2026-05-18

---

## Current State

### Entry point — "EMPEZAR" button

`lib/features/workout/presentation/routine_detail_screen.dart` renders a `_DisabledCTABar` widget (line 186) with two buttons: "EDITAR" and "EMPEZAR". Both use `onPressed: null`, wrapped in `Opacity(opacity: 0.4)`. There is no navigation wired. The data available at that point is a full `Routine` object (with `days`) and the currently selected `selectedDayIndex` (local state on `_RoutineDetailScreenState`). This means `routineId` and the selected `dayNumber` are both immediately available when the button is tapped.

### Domain models

`RoutineSlot` (the per-exercise entry in a day) contains exactly what the player needs:
- `exerciseId` + `exerciseName` (denormalized) + `muscleGroup` (denormalized)
- `targetSets`, `targetRepsMin`, `targetRepsMax`
- `restSeconds`
- `targetWeightKg?` (nullable — "user picks" or "no target")
- `notes?`

`RoutineDay` has: `dayNumber`, `name`, `slots: List<RoutineSlot>`, `estimatedMinutes?`

`Routine` has: `id`, `name`, `split`, `level`, `days: List<RoutineDay>`, `estimatedMinutesPerDay?`

All three are `@freezed` with `fromJson` / `toJson` via `json_serializable`.

### Router

`lib/app/router.dart` — the `/workout` route already has two children:
- `routine/:routineId` → `RoutineDetailScreen`
- `exercise/:exerciseId` → `ExerciseDetailScreen`

The session player needs a third child route. The ShellRoute wraps all tabs so the bottom nav remains visible — this is relevant: **the player likely wants NO bottom nav** (full-screen immersive experience). This requires either (a) placing the session route OUTSIDE the ShellRoute as a top-level GoRoute, or (b) using the existing convention of hiding the bottom bar for deep routes (currently the bottom bar is always shown for all ShellRoute children). Option (a) is cleaner.

### Existing patterns

- `RoutineDetailScreen` — `ConsumerStatefulWidget` with local `selectedDayIndex` state. Direct pattern to follow for the player (local timer state + set completion state both require `StatefulWidget`).
- `PublicProfileScreen` — `ConsumerWidget` composed via view-model providers. Good pattern when there is no local mutable state beyond what Riverpod manages.
- `UserProfile` freezed model — shows the `@TimestampConverter()` pattern for `DateTime` fields. Session + SetLog models must follow the same pattern.
- `RoutineRepository` — clean Repository pattern with `_firestore.collection('...')`, `_fromDoc`, `fromJson`. `SessionRepository` should mirror this exactly.

### No session feature exists yet

There are zero files under any `session` feature directory. Etapa 1 has not started. The contract documented in this exploration IS the proposal to Dev A.

---

## Mockup Analysis — `sesion-dia.png`

The mockup shows a single scrollable screen with these zones (top to bottom):

| Zone | Detail |
|---|---|
| **Top bar** | Back chevron (left) · title "PUSH · DÍA 4" in Barlow Condensed UPPERCASE · "TERMINAR" pill-button (right, red/magenta background) |
| **Attendance card** | Full-width card · icon · "Asistencia marcada" + "Gimnasio La Fuerza · 18:42" · green checkmark right. Auto-populated on session start. |
| **Session status card** | "SESIÓN ACTIVA" label (accent green, uppercase) · "2 / 6 ejercicios · 5,240 kg vol." · large timer "24:18" (accent green, ~48px) · progress bar below |
| **Exercise list** | Label "EJERCICIOS" section header · list of exercise rows |
| **Exercise row — completed** | Green circle check (filled) · exercise name (strikethrough text, muted) · "4 × 10 · 60 kg" sub-label · no chevron |
| **Exercise row — current** | Empty circle (unfilled) · exercise name bold white · "3 × 12 · 20 kg" sub-label · green "Ahora" pill badge on right |
| **Exercise row — upcoming** | Empty circle · exercise name white · "4 × 8 · 40 kg" sub-label · chevron right (navigate to set-entry view?) |
| **Bottom CTA** | Full-width pill button "TERMINAR SESIÓN ✓" in accent green |

**Key observations from mockup:**

1. The player is an **exercise list view**, NOT a per-set detail view. The user scrolls through exercises, sees which one is current ("Ahora" badge), taps it to enter set details (the chevron on upcoming rows implies a drill-down).
2. The **set-entry** detail (reps + weight + check per set) is likely a separate screen or a bottom sheet — NOT visible in this mockup. Need to infer from UX: a bottom sheet per exercise is cleaner (modal flow while staying on the list).
3. The timer is a **session-elapsed timer** (counting up: 24:18 shown). This is NOT a rest timer — the rest timer is per-set and would live inside the set-entry sheet.
4. "2 / 6 ejercicios" and the progress bar are computed from completed exercises vs total, NOT from sets.
5. Volume "5,240 kg vol." is accumulated as sets are completed. Computed as sum of `(completedSets × reps × weightKg)` in memory, flushed to Firestore on finish.
6. No visible navigation between exercises — the user taps the exercise row to drill into it. Upcoming exercises show a chevron.
7. "TERMINAR" in the top bar and "TERMINAR SESIÓN" at the bottom serve the same action — both should trigger the finish flow.

---

## Assumed Session + SetLog Shape (Contract for Dev A)

These are the fields the player NEEDS. Dev A must cover at minimum this surface.

### `Session` model

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
    required SessionStatus status,        // active | finished
    double? totalVolumeKg,               // computed at finish
    int? durationMin,                    // computed at finish
  }) = _Session;
  factory Session.fromJson(Map<String, Object?> json) => _$SessionFromJson(json);
}

enum SessionStatus { active, finished }
```

### `SetLog` model (subcollection preferred — see Decision B below)

```dart
@freezed
class SetLog with _$SetLog {
  const factory SetLog({
    required String id,
    required String exerciseId,
    required int setNumber,              // 1-based
    required int reps,
    required double weightKg,
    int? rpe,                            // optional 1-10 Rated Perceived Exertion
    @TimestampConverter() required DateTime completedAt,
  }) = _SetLog;
  factory SetLog.fromJson(Map<String, Object?> json) => _$SetLogFromJson(json);
}
```

### `SessionRepository` contract

```dart
abstract class SessionRepository {
  Future<Session> create({required String uid, required String routineId, required int dayNumber});
  Future<void> logSet(String sessionId, SetLog setLog);
  Future<Session> finish(String sessionId, {required double totalVolumeKg, required int durationMin});
  Stream<Session> watch(String sessionId);
  Future<List<Session>> listByUid(String uid);
}
```

Firestore path: `users/{uid}/sessions/{sessionId}` for Session doc  
Sets subcollection: `users/{uid}/sessions/{sessionId}/sets/{setId}`

---

## Affected Areas

| File / Path | Why affected |
|---|---|
| `lib/features/workout/presentation/routine_detail_screen.dart` | `_DisabledCTABar` must be replaced with live button wired to navigate to session player |
| `lib/app/router.dart` | New top-level GoRoute for `/workout/session/:routineId/:dayNumber` (outside ShellRoute to hide bottom nav) + stub route for `/workout/session-summary/:sessionId` |
| `lib/features/session/` (new feature directory) | All session domain, data, application, and presentation layers live here |
| `lib/features/workout/application/routine_providers.dart` | No direct change; player reads Routine data via existing `routineByIdProvider` |

New files needed (all under `lib/features/session/`):

```
domain/
  session.dart + session.freezed.dart + session.g.dart
  set_log.dart + set_log.freezed.dart + set_log.g.dart
  session_status.dart
data/
  session_repository.dart
application/
  session_providers.dart
  session_notifier.dart        (manages active session state + timer + set accumulation)
presentation/
  session_player_screen.dart
  widgets/
    session_status_card.dart
    exercise_session_row.dart
    set_entry_sheet.dart       (bottom sheet: reps + weight + check per set)
    rest_timer_widget.dart
```

---

## Key Decisions for Propose Phase

### Decision A — Persistence Strategy

| Option | Description | Pros | Cons | Effort |
|---|---|---|---|---|
| A — Eager | Write `SetLog` to Firestore immediately on each set completion | Crash-resilient, no data loss | ~30-50 writes/session, slightly more complex error handling per write | Medium |
| B — Lazy/Batch | Accumulate `SetLog`s in memory, batch-write only on "TERMINAR" | Minimum Firestore writes (1 transaction) | Total data loss if app crashes mid-session | Low |
| C — Hybrid | Write Session doc with `status: active` at start; write each `SetLog` to subcollection as completed; final `finish()` call updates Session status + computes totals | Crash-resilient; `watch(sessionId)` can resume; cost is O(sets) writes not O(exercises) | More complex repo + notifier; subcollection reads for resume | Medium-High |

**Recommendation: Option C.** The gym context makes crash resilience valuable (WiFi loss, phone call). The extra Firestore writes (~30-50 per session) are negligible cost. Option B is unacceptable for a workout tracker — losing an entire session is a critical UX failure.

### Decision B — SetLog Storage

| Option | Description | Pros | Cons |
|---|---|---|---|
| Subcollection `sessions/{id}/sets/{setId}` | Each set is a separate Firestore doc | Scales to 100+ sets; write is atomic per set; easy to query "all sets for session X"; aligns with Option C persistence | One read per set on resume (but we keep in-memory state during session) |
| Embedded array on Session doc | `SetLog` is a field on Session | Single read to get everything | 1MB doc limit; Firestore can't update individual array elements atomically; messy with Hybrid persistence |

**Recommendation: Subcollection.** Embedded arrays conflict with per-set eager writes. Array `arrayUnion` doesn't support structured objects cleanly. Subcollection is the idiomatic Firestore pattern for 1:N within a user-owned resource.

### Decision C — Timer Mechanics

| Option | Description | Pros | Cons |
|---|---|---|---|
| `Stream.periodic` in-app | `Stream<int>.periodic(Duration(seconds: 1))` driving a `ValueNotifier<Duration>` in `SessionNotifier` | Simple, no dependencies, cancels on dispose | Timer stops when app is backgrounded (iOS/Android suspend the Dart isolate) |
| `flutter_local_notifications` + elapsed-since-start | Store `startedAt` timestamp, compute elapsed = `now - startedAt` on each tick | Accurate after background; resume works trivially | Additional dependency; overkill for Etapa 2 |

**Recommendation: `Stream.periodic` for Etapa 2.** Store `startedAt` in `Session` and compute `elapsed = DateTime.now().difference(session.startedAt)` on each tick — this means even with background suspension the display auto-corrects on foreground resume (no stored offset needed). Mark background-accurate timers as Fase 6 polish.

**Rest timer**: `ValueNotifier<int>` (seconds countdown) inside `SetEntrySheet` or `SessionNotifier`. Starts automatically when a set is completed (auto-start is the expected UX). Default value = `slot.restSeconds`. Display countdown. When it hits 0, play a haptic/sound (optional, out of scope for Etapa 2).

### Decision D — Back Button Mid-Session

| Option | Description |
|---|---|
| Discard silently | Session doc stays `active` in Firestore; becomes orphaned until `listByUid` cleanup |
| Confirm dialog + discard | `showDialog` → "¿Salir? Perderás el progreso de esta sesión." → cancel/confirm |
| Pause (future) | Set `status: paused` — deferred to Fase 6 |

**Recommendation: Confirm dialog + discard.** If user confirms, call a `SessionRepository.abandon(sessionId)` that deletes the Session doc and its sets subcollection (or sets `status: abandoned` to avoid silent orphans). Do NOT silently leave orphaned `active` docs — they will pollute Historial in Etapa 4.

### Decision E — Route Name

Proposed: `/workout/session/:routineId/:dayNumber` (outside ShellRoute)

Rationale: the player is launched FROM the workout tab but is an immersive full-screen experience. Placing it outside ShellRoute hides the bottom nav naturally, matching the mockup (no visible bottom bar). The route carries both `routineId` (to re-fetch Routine + day data) and `dayNumber` (to select the correct `RoutineDay`).

Post-session summary (Etapa 3): `/workout/session-summary/:sessionId` — stub route returning `const SizedBox()` initially.

### Decision F — Weight + Reps Input UX

The mockup does not show the set-entry sheet explicitly. Inferring from the mockup and from fitness app conventions:

**Recommendation: `+/- stepper buttons` with a central numeric display**, NOT a keyboard `TextField`. Reasons: (1) hands may be chalked/sweaty during a workout, (2) small increments are the norm (2.5 kg plates), (3) avoids keyboard show/hide jank inside a bottom sheet. The stepper wraps a `ValueNotifier<int/double>` per field, no Riverpod needed at that granularity.

### Decision G — Rest Timer Auto-Start

**Recommendation: auto-start** when a set is marked complete. The user taps the check, the rest timer immediately starts counting down. They can dismiss/skip it. This is the standard in apps like Strong, Hevy, and Fitbod.

### Decision H — "Compartir" Hook

Compartir is Etapa 3 scope. The player screen should include no visible Compartir button. The post-session summary screen (Etapa 3) is where Compartir lives. A TODO comment in the "TERMINAR" flow suffices.

---

## Navigation Flow

```
RoutineDetailScreen (selectedDayIndex=N, routineId=X)
  │
  └─ tap "EMPEZAR" → context.push('/workout/session/X/${day.dayNumber}')
                                        │
                              SessionPlayerScreen
                                (reads Routine via routineByIdProvider(X))
                                (creates Session via sessionNotifier.start())
                                        │
                       ┌────────────────┴────────────────┐
                       │                                 │
               tap exercise row                  tap "TERMINAR"
                       │                                 │
               SetEntrySheet (bottomSheet)        confirm dialog → sessionNotifier.finish()
               reps + weight + check                     │
               → logSet + dismiss                context.pushReplacement(
               → rest timer countdown              '/workout/session-summary/${session.id}')
                                                 (Etapa 3 — stub initially)
```

Back button in `SessionPlayerScreen` → confirm dialog → if confirmed: `sessionNotifier.abandon()` → `context.pop()`

---

## Approaches

### Approach 1 — Single-screen scrollable list (matches mockup)

A `ConsumerStatefulWidget` (`SessionPlayerScreen`) that renders a `CustomScrollView` with:
- A sticky `SliverAppBar` (session title, timer, "TERMINAR" in top-right)
- A `SliverList` of `ExerciseSessionRow` items
- A bottom pinned "TERMINAR SESIÓN" button

`SetEntrySheet` is a modal bottom sheet (NOT a separate route) launched via `showModalBottomSheet` when the user taps an active or upcoming exercise row. This sheet shows per-set reps/weight steppers + check button + rest timer countdown.

- Pros: matches mockup exactly; exercise list visible throughout; natural scroll behavior; no nested navigation complexity
- Cons: set entry in a bottom sheet means limited vertical space; for exercises with 5+ sets this may feel cramped
- Effort: Medium

### Approach 2 — Per-exercise full-screen flow

Navigate to a `SetEntryScreen` for each exercise (separate route). The list is navigational, not the working surface.

- Pros: full screen for set entry; more room for weight/reps UI
- Cons: contradicts mockup; more routes to manage; user can't see overall session progress while entering sets
- Effort: High

**Recommendation: Approach 1.** The mockup is explicit. The bottom sheet for set entry follows established Flutter modal patterns and gives enough space for a 2-field (reps + weight) interaction.

---

## State Architecture

`SessionNotifier` extends `AsyncNotifier<SessionState>` where:

```dart
class SessionState {
  final Session session;
  final List<SetLog> completedSets;       // in-memory accumulation
  final int currentExerciseIndex;         // which exercise is "Ahora"
  final Duration elapsed;                 // from Stream.periodic
}
```

The notifier:
- Subscribes to `Stream<int>.periodic(const Duration(seconds: 1))` on `build()`; cancels in `dispose()`
- Computes `elapsed = DateTime.now().difference(session.startedAt)` on each tick (avoids background drift)
- Exposes `logSet(SetLog)` → writes to Firestore + appends to `completedSets` + advances `currentExerciseIndex` if all sets for current exercise are done
- Exposes `finish()` → computes `totalVolumeKg` + `durationMin` → calls `SessionRepository.finish()`
- Exposes `abandon()` → calls `SessionRepository.abandon()` (delete or mark abandoned)

This is a `StateNotifier`-style single source of truth for the entire session. No local `setState` for session business logic.

---

## Firestore Rules Needed (for Dev A)

```
match /users/{uid}/sessions/{sessionId} {
  allow read, write: if request.auth.uid == uid;

  match /sets/{setId} {
    allow read, write: if request.auth.uid == uid;
  }
}
```

The `uid` path segment already scopes these rules to the owner — no additional predicates needed.

---

## Risks

1. **Etapa 1 not started**: The entire apply phase is blocked until `Session`, `SetLog`, and `SessionRepository` exist. The risk is that Dev A's design diverges from the contract in this document — mitigate by sharing this explore doc with Dev A before they start.

2. **`SetLog` subcollection Firestore costs**: Each set completion is 1 write. A 5-exercise, 4-set-each session = 20 writes + 1 session create + 1 session finish = 22 writes. At Firestore free tier (20k writes/day), this is trivial for an MVP. Not a practical concern.

3. **Bottom sheet height constraint**: The `SetEntrySheet` must fit reps stepper + weight stepper + check button + rest timer in the bottom 50-60% of the screen. Must be designed carefully. If cramped: make it `isScrollControlled: true` with `DraggableScrollableSheet`.

4. **`Stream.periodic` lifecycle**: The timer stream must be cancelled when `SessionNotifier` is disposed. If the user pops mid-session without going through the abandon flow, the stream leaks. Must use `ref.onDispose(() => _timer.cancel())` in the notifier.

5. **Session orphan on crash**: Even with Option C (Hybrid persistence), if the app hard-crashes between `create()` and `finish()`, a Session with `status: active` persists. Historial (Etapa 4) must filter these out or display them as "incomplete". Recommend surfacing orphaned `active` sessions in Historial with a "resume or discard" prompt — defer to Etapa 4.

6. **Route placement outside ShellRoute**: Adding a top-level GoRoute for the session player means `context.push()` from within the ShellRoute will overlay the Shell. Verify GoRouter behavior with `push` vs `go` for cross-ShellRoute navigation. Using `context.push()` (not `context.go()`) should work correctly — push adds to the navigation stack on top of the shell.

7. **`dayNumber` vs `dayIndex` mismatch**: `RoutineDay.dayNumber` is 1-based (from Firestore seed). `selectedDayIndex` in `RoutineDetailScreen` is 0-based. The route must pass `day.dayNumber` (the model field), not `selectedDayIndex`. The player uses `dayNumber` to look up the correct `RoutineDay` from `routine.days.firstWhere((d) => d.dayNumber == dayNumber)`.

---

## Ready for Proposal

Yes. All architectural decisions are documented with recommendations. The proposal phase should confirm:
- Route placement strategy (outside ShellRoute)
- `SessionNotifier` as `AsyncNotifier<SessionState>` vs `StateNotifier`
- Whether `SetEntrySheet` is a bottom sheet or a sub-route
- Confirm Dev A contract alignment on Session + SetLog shape

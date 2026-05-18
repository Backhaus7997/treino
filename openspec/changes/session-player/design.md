# Design — session-player

**Change**: `session-player`
**Fase / Etapa**: Fase 4 · Etapa 2 — Active workout session player
**Branch**: `feat/session-player` (off `main`, rebased post-Etapa-1)
**Artifact store**: `openspec`
**TDD**: Strict — tests precede implementation in apply phase
**Depends on**:
- `openspec/changes/session-player/propose.md` (12 locked decisions + Etapa 1 contract including `findActiveForUid`)
- `openspec/changes/session-player/spec.md` (27 REQs · ~89 BDD scenarios from SCENARIO-250 to SCENARIO-338)
- Etapa 1 (`feat/session-model-seed`) MERGED into `main`, including `SessionRepository.findActiveForUid`
**Sister precedent**: `openspec/changes/public-profile/design.md` (multi-state widget pattern); `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` (state-driven render)
**Status**: SDD planning ONLY — apply is **DEFERRED** behind Etapa 1 + pre-apply gating (propose.md §Pre-apply gating conditions)
**Last updated**: 2026-05-18 — Decision 12 (resume on re-open) incorporated. New §11 (resume flow architecture), §12 (resume route + path), `SessionInit` sealed dispatch for the notifier, `activeSessionForUidProvider` + `ResumeSessionModal` + `HomeScreen` listener. Production LOC bumped to ~835 (+150). Implementation order reshuffled to bring resume primitives in early.

This document is the implementation contract. Two devs working from this design independently MUST produce nearly identical code. Code shapes shown below are normative.

Read order before apply: `propose.md` → `spec.md` → this file.

---

## 0. Pre-apply gating (LOCK)

Apply MUST NOT start until every condition in `propose.md §Pre-apply gating conditions` is satisfied. The four most consequential ones:

1. `feat/session-model-seed` (Etapa 1) merged into `main`.
2. `Session`, `SetLog`, `SessionRepository` exist with the exact shape declared in `propose.md §Etapa 1 contract` — including the new `findActiveForUid(uid) → Future<({Session session, List<SetLog> setLogs})?>` method (Decision 12).
3. `feat/session-player` rebased onto post-Etapa-1 `main`.
4. Delivery strategy resolved (chained PRs vs `size:exception`). See `propose.md §8 Review Workload Forecast`.

If Dev A's actual model shape differs from the contract — especially if `findActiveForUid` is missing or has a different signature — the propose phase MUST be re-run before any code is written from this design.

---

## 1. File map

All paths absolute from repo root (`c:\Users\Martin\Desktop\treino\treino\`). Source under `lib/features/workout/` (NOT `lib/features/session/` — locked by spec cross-reference fix). Tests mirror under `test/features/workout/`. The single touch outside `workout/` is `lib/features/home/home_screen.dart` (resume listener) — additive only.

### New files

| Path | Action | Purpose | Approx LOC |
|---|---|---|---|
| `lib/features/workout/application/session_init.dart` | new | `sealed class SessionInit` + `FreshSession` + `ResumeSession` — the family key dispatching the notifier between Path A and Path B (see §3.1 / §11.4) | ~30 |
| `lib/features/workout/application/session_state.dart` | new | `@freezed`-free immutable `SessionState` class (manual `copyWith`) + derived getters | ~95 |
| `lib/features/workout/application/session_notifier.dart` | new | `SessionNotifier extends FamilyAsyncNotifier<SessionState, SessionInit>` — sealed dispatch in `build()`, `logSet`/`abandon`/`finish`/timer | ~200 |
| `lib/features/workout/application/session_providers.dart` | new | `sessionRepositoryProvider` (passthrough) + `currentUidProvider` + `sessionNotifierProvider` family + **`activeSessionForUidProvider`** (Decision 12) | ~55 |
| `lib/features/workout/presentation/session_player_screen.dart` | new | `SessionPlayerScreen` (ConsumerStatefulWidget) — accepts `SessionInit` and watches `sessionNotifierProvider(init)` — + 6 private widgets (header, attendance, stats, row, terminar, dialog) + `ExerciseRowStatus` enum | ~440 |
| `lib/features/workout/presentation/widgets/set_entry_sheet.dart` | new | `SetEntrySheet` (StatefulWidget) + private `_StepperButton` widget | ~180 |
| `lib/features/workout/presentation/widgets/resume_session_modal.dart` | new | `ResumeSessionModal` — public widget — 2-button prompt (Continuar / Descartar). Decision 12 | ~95 |
| `test/features/workout/application/session_init_test.dart` | new | Equality, hashCode, pattern matching on the sealed family key | ~50 |
| `test/features/workout/application/session_state_test.dart` | new | SCENARIO-250..255 — `isFullyCompleted` + `totalVolumeKg` truth tables | ~90 |
| `test/features/workout/application/session_notifier_test.dart` | new | SCENARIO-256..268, 318..321 — build (Path A + Path B) / logSet / abandon / finish / dispose / timer / resume restoration | ~360 |
| `test/features/workout/application/session_providers_test.dart` | new | SCENARIO-269 + SCENARIO-322..324 — family key uniqueness + `activeSessionForUidProvider` auth gating | ~110 |
| `test/features/workout/presentation/session_player_screen_test.dart` | new | SCENARIO-270..290, 305..315 — orchestration + header + cards + row + button + dialog + nav | ~450 |
| `test/features/workout/presentation/widgets/set_entry_sheet_test.dart` | new | SCENARIO-291..304 — steppers + check + clamping | ~190 |
| `test/features/workout/presentation/widgets/resume_session_modal_test.dart` | new | SCENARIO-329..338 — modal renders, button callbacks, time format, dismiss behavior | ~150 |

### Modified files

| Path | Action | Purpose | LOC delta |
|---|---|---|---|
| `lib/app/router.dart` | modify | Add **3** top-level `GoRoute`s OUTSIDE the existing `ShellRoute` — `/workout/session/:routineId/:dayNumber` (fresh) + `/workout/session/resume/:sessionId` (resume) + `/workout/session-summary/:sessionId` (stub) | +35 |
| `lib/features/workout/presentation/routine_detail_screen.dart` | modify | Replace `_DisabledCTABar` (lines 442-504) with `_StartSessionCTABar` — EMPEZAR wired with `context.push`, EDITAR remains disabled | +/-30 |
| `lib/features/home/home_screen.dart` | modify | Add `ref.listen<AsyncValue<...>>(activeSessionForUidProvider, ...)` in `build()` to surface the `ResumeSessionModal` via post-frame callback. NO refactor of existing widgets; additive only. NOTE: file lives at `lib/features/home/home_screen.dart` — NOT `lib/features/home/presentation/home_screen.dart` as the spec incorrectly states. The design TREATS the real path as authoritative; the apply phase MUST place the listener in the existing file. | +25 |
| `lib/core/widgets/treino_icon.dart` | modify | Add icon constants if missing: `TreinoIcon.checkCircleEmpty`, `TreinoIcon.checkCircleFill` (alias `check` already exists), `TreinoIcon.chevronRight` (alias `forward` already exists). Audit: `gym` exists, `back` exists, `check` exists, `clock` exists | +5 (only if missing) |

### Files explicitly NOT modified (scope boundary)

- `lib/features/workout/domain/routine.dart`, `routine_day.dart`, `routine_slot.dart` — Etapa 1 / pre-existing
- `lib/features/workout/application/routine_providers.dart` — `routineByIdProvider` consumed read-only
- Any file under `lib/features/feed/`, `lib/features/auth/`, `lib/features/profile/` — except `lib/features/feed/domain/gym_name.dart` (READ-ONLY import for the attendance card; cross-feature reuse for a value-only helper, see §9.5)
- `lib/features/home/widgets/empezar_entrenamiento_card.dart`, `esta_semana_card.dart`, `home_header.dart` — untouched; the resume listener is added at the screen level only
- `firestore.rules` (deployed by Etapa 1)
- `pubspec.yaml` — no new deps (`Timer.periodic` is in `dart:async`)
- `lib/features/profile/application/user_providers.dart` — `userProfileProvider` consumed read-only

**Estimated total diff**: ~835 production LOC (was ~685 pre-Decision-12; +150 for the resume primitives: `session_init.dart`, `activeSessionForUidProvider`, `ResumeSessionModal`, `HomeScreen` listener, Path B of the notifier) + ~1290 test LOC ≈ **~2125 LOC** across 13 files. Above the 400-line single-PR budget — chained PRs **strongly** recommended (signal upgraded from "recommended" to "strongly recommended" after Decision 12). PR split locked in §10.

---

## 2. Widget API surfaces

All widgets live in the `workout` feature. `SessionPlayerScreen` is the only `ConsumerStatefulWidget` (needs `PopScope` intercept + `WidgetRef`). `SetEntrySheet` is a `StatefulWidget` (local stepper state) — it is shown via `showModalBottomSheet` from inside the screen. `ResumeSessionModal` is a `StatelessWidget` (pure presentational). The 6 private widgets inside `session_player_screen.dart` are `StatelessWidget` (or `ConsumerWidget` for `_AttendanceCard` which reads `userProfileProvider`).

### 2.1 `SessionPlayerScreen` (public)

```dart
class SessionPlayerScreen extends ConsumerStatefulWidget {
  const SessionPlayerScreen({super.key, required this.init});

  /// Sealed family key — `FreshSession(routineId, dayNumber)` for a brand-new
  /// session OR `ResumeSession(sessionId)` to rehydrate from the resume route.
  /// See §11.4 for rationale (single screen + sealed dispatch beats two
  /// parallel notifiers).
  final SessionInit init;

  @override
  ConsumerState<SessionPlayerScreen> createState() =>
      _SessionPlayerScreenState();
}
```

**Rationale**:
- ONE constructor param — `init: SessionInit`. The route builders parse path parameters and construct the appropriate subclass:
  - `/workout/session/:routineId/:dayNumber` → `FreshSession(routineId, dayNumber)`
  - `/workout/session/resume/:sessionId` → `ResumeSession(sessionId)`
- This satisfies the spec's REQ-SESSION-ROUTE-001 phrasing ("design phase decides whether this is a separate widget or a constructor parameter"). LOCKED: single widget + sealed param. See ADR-SP-11 below.
- `ConsumerStatefulWidget` (NOT `ConsumerWidget`) because the screen needs `PopScope` callback handlers (which capture `BuildContext`) AND a stable identity across rebuilds for `Navigator.pop` from the abandon dialog. The state class holds no business state — Riverpod owns everything — but the class form is required for `setState`-free callback wiring.
- No `Scaffold` introduced by the screen itself. The route builder in `router.dart` wraps with `Scaffold(body: SessionPlayerScreen(...))`. The screen renders a `PopScope > SafeArea > Column` directly. This matches spec REQ-SESSION-SCREEN-001 (cross-reference fix #2).
- Imports `userProfileProvider` for `_AttendanceCard.gymId`.
- The screen reads the routine via `routineByIdProvider(init.routineId)` for the header split (Path A: from `init.routineId` directly; Path B: from `state.session.routineId` once the notifier resolves). See §9.3.

### 2.2 `SetEntrySheet` (public)

```dart
class SetEntrySheet extends StatefulWidget {
  const SetEntrySheet({
    super.key,
    required this.slot,
    required this.setNumber,
    required this.onCheck,
  });

  final RoutineSlot slot;
  final int setNumber; // 1-based — the set being entered, e.g. 2 of 3
  final void Function(int reps, double weightKg) onCheck;

  @override
  State<SetEntrySheet> createState() => _SetEntrySheetState();
}
```

**Rationale**:
- `StatefulWidget` (NOT `ConsumerWidget`) because the steppers manage local int/double state that exists only for the duration of the modal. Lifting that state to Riverpod would couple a transient UI value to a global container — wrong.
- `onCheck` is a callback (NOT a notifier reference) per spec REQ-SESSION-SHEET-004. The caller (the screen) wires `onCheck` to `notifier.logSet(...)`. This decouples the widget from the notifier and makes unit testing trivial (`SetEntrySheet` tests pass a recording lambda).
- Reps default = `slot.targetRepsMin ?? 0`. Weight default = `slot.targetWeightKg ?? 0.0`. Clamps: reps `[0..50]`, weight `[0.0..500.0]` step 2.5 (spec REQ-SESSION-SHEET-002, REQ-SESSION-SHEET-003).

### 2.3 `ResumeSessionModal` (public — Decision 12)

```dart
class ResumeSessionModal extends StatelessWidget {
  const ResumeSessionModal({
    super.key,
    required this.session,
    required this.onContinue,
    required this.onDiscard,
  });

  final Session session;
  final VoidCallback onContinue;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hhmm = _formatHHMM(session.startedAt);
    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Text('Entrenamiento en curso', style: titleStyle),
      content: Text(
        'Tenés un entrenamiento desde $hhmm. ¿Querés continuarlo o descartarlo?',
        style: bodyStyle,
      ),
      actions: [
        OutlinedButton(
          onPressed: onDiscard,
          style: outlinedDestructiveStyle, // palette.highlight border + text
          child: const Text('Descartar'),
        ),
        ElevatedButton(
          onPressed: onContinue,
          style: mintFillStyle, // palette.accent bg, palette.bg label
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

String _formatHHMM(DateTime dt) {
  final local = dt.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
```

**Rationale**:
- `StatelessWidget` — pure presentational. The caller (`HomeScreen` via post-frame callback) owns the side effects (`context.push`, `repo.finish`).
- Callbacks are `VoidCallback` — the widget does NOT call `Navigator.pop` itself. The caller's `onContinue`/`onDiscard` handlers MUST `Navigator.of(context, rootNavigator: true).pop()` BEFORE doing their work (or after, depending on whether we want the modal to flicker during the discard's `repo.finish` await — see §11.5 for the locked order).
- `_formatHHMM` is a **file-private** helper at the top of `resume_session_modal.dart`. NOT shared with `_formatMMSS` in `session_player_screen.dart` — different concern (clock time vs elapsed duration).
- Spec REQ-SESSION-RESUME-003 (SCENARIO-329..333) verifies title, time, both buttons, and the callbacks.

### 2.4 Private widgets inside `session_player_screen.dart`

All declared as `_PrivateName extends StatelessWidget` unless noted. Kept private so the screen file is self-contained — none of these widgets has a reuse candidate outside this screen (cf. `public_profile_screen.dart`'s pattern of `_MessageButtonStub`, `_ProfileTabPills`, `_ProfileTabBody`).

#### 2.4.1 `_SessionHeader`

```dart
class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.routineSplit,
    required this.dayNumber,
    required this.onAbandon,
    required this.onBack,
  });

  final String routineSplit;
  final int dayNumber;
  final VoidCallback onAbandon;
  final VoidCallback onBack;
}
```

Rationale: receives strings + callbacks. NOT a `ConsumerWidget` — no provider reads. Header text format `'${routineSplit.toUpperCase()} · DÍA ${dayNumber}'` (spec REQ-SESSION-SCREEN-002 SCENARIO-274). Per spec REQ-SESSION-SCREEN-002 both the back button and ABANDONAR invoke the same confirm dialog — so the screen passes the same callback to both: `onAbandon == onBack == _showAbandonConfirm`. We keep two named params for readability at the call site.

#### 2.4.2 `_AttendanceCard` (`ConsumerWidget`)

```dart
class _AttendanceCard extends ConsumerWidget {
  const _AttendanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref);
}
```

Rationale: only widget here that watches a provider — `userProfileProvider` for `gymId`. Reuses `gymNameFromId` from `lib/features/feed/domain/gym_name.dart` (spec cross-ref fix #5). Renders `'Asistencia marcada'` + gym subtitle or `'Sin gimnasio asignado'` fallback + current `HH:mm` (computed via `DateTime.now()` AT widget build time — acceptable because the card never rebuilds during the session; mockup shows static time). NO real check-in logic per spec REQ-SESSION-SCREEN-003. Source comment: `// Placeholder: real check-in wired in Etapa 6.`

#### 2.4.3 `_SessionStatsCard`

```dart
class _SessionStatsCard extends StatelessWidget {
  const _SessionStatsCard({required this.state});

  final SessionState state;
}
```

Rationale: receives the whole `SessionState` (cleaner than 4 separate params: `elapsedSeconds`, `totalVolumeKg`, completed-count, total-count). Renders `'SESIÓN ACTIVA'` label + `'X / Y ejercicios · Z kg vol.'` + `MM:SS` timer + `LinearProgressIndicator(value: X/Y)`. Uses a helper `_formatMMSS(int seconds)` declared at the same file scope (see §9.4).

#### 2.4.4 `_ExerciseListRow`

```dart
class _ExerciseListRow extends StatelessWidget {
  const _ExerciseListRow({
    required this.slot,
    required this.status,
    required this.completedSets,
    required this.onTap,
  });

  final RoutineSlot slot;
  final ExerciseRowStatus status;
  final int completedSets;
  final VoidCallback? onTap;
}
```

Rationale: 3 visual states determined by `status` enum (`done | current | pending`). Spec REQ-SESSION-SCREEN-005 fixes the visual contract. Tappable when `onTap != null`. `completedSets` displayed in subtitle when status is `current` (e.g., "Set 2 de 3 hecho").

`ExerciseRowStatus` enum is declared INLINE at file scope of `session_player_screen.dart` (NOT in a separate domain file). Justification: only consumed by this file. Spec leaves placement open — `lib/features/workout/domain/exercise_row_status.dart` was offered as alternative — we pick inline because:
- One consumer → file colocation reduces cross-file noise
- Mirrors `public_profile_screen.dart`'s pattern of declaring `_ProfileTab` enum inside the screen file
- If a second consumer emerges (e.g. Historial reuse in Etapa 4), the refactor is mechanical (move 4 lines to a new file).

#### 2.4.5 `_TerminarSessionButton`

```dart
class _TerminarSessionButton extends StatelessWidget {
  const _TerminarSessionButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback? onPressed;
}
```

Rationale: parameterized by `enabled` (drives visual state) + `onPressed` (must be `null` when `enabled == false` per spec REQ-SESSION-SCREEN-006 SCENARIO-289). The screen computes `enabled = state.isFullyCompleted` and passes `onPressed: enabled ? _finishSession : null`.

#### 2.4.6 `_AbandonConfirmDialog`

```dart
class _AbandonConfirmDialog extends StatelessWidget {
  const _AbandonConfirmDialog({required this.onConfirm});

  final VoidCallback onConfirm;
}
```

Rationale: rendered via `showDialog(context: ..., builder: (_) => _AbandonConfirmDialog(onConfirm: ...))`. Body text locked by spec REQ-SESSION-DIALOG-001 (`'¿Seguro que querés abandonar? Se va a guardar tu progreso hasta acá.'`). Two buttons: `'Cancelar'` (outlined) → `Navigator.pop(context)`. `'Abandonar'` (destructive style) → `Navigator.pop(context)` then `onConfirm()`. KEPT INLINE in `session_player_screen.dart` per spec cross-reference fix #3 (same convention as `_MessageButtonStub` in `public_profile_screen.dart`).

---

## 3. `SessionNotifier` + state — exact shape

### 3.1 `SessionInit` sealed class (NEW — Decision 12)

The family key for `sessionNotifierProvider` is a **sealed Dart class**, NOT a record/tuple. This is the central refactor for resume support: the same notifier handles both paths (fresh start vs resume) by `switch`-ing on the init type inside `build()`.

```dart
// lib/features/workout/application/session_init.dart

import 'package:flutter/foundation.dart';

@immutable
sealed class SessionInit {
  const SessionInit();
}

final class FreshSession extends SessionInit {
  const FreshSession({required this.routineId, required this.dayNumber});

  final String routineId;
  final int dayNumber;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreshSession &&
          other.routineId == routineId &&
          other.dayNumber == dayNumber;

  @override
  int get hashCode => Object.hash(routineId, dayNumber);
}

final class ResumeSession extends SessionInit {
  const ResumeSession({required this.sessionId});

  final String sessionId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResumeSession && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}
```

**Rationale**:
- Riverpod's family cache uses `==` + `hashCode` to key provider instances. Two `FreshSession` constructions with identical `routineId` + `dayNumber` MUST be `==` → same notifier instance, no double-creation. Same logic for `ResumeSession` keyed by `sessionId`.
- Sealed classes give exhaustive `switch` in `build()` — no fall-through risk, compile-time check.
- Lives in `application/` (NOT `domain/`) because it is a Riverpod-family-key concern, not a domain entity. The domain layer (`session.dart` from Etapa 1) is untouched.
- See ADR-SP-11 for rejected alternatives (two separate notifiers, record key with nullable fields).

### 3.2 `SessionState` class

`SessionState` is a plain immutable class (NOT `@freezed`). Rationale: no `fromJson`/`toJson` (never serialized), no need for build_runner, manual `copyWith` is ~20 LOC and the file remains build-runner-free. This matches the spec sketch in REQ-SESSION-STATE-001.

```dart
import 'package:flutter/foundation.dart';

import '../../domain/routine_day.dart';
// Etapa 1 contract — imports resolved after feat/session-model-seed merges:
import '../domain/session.dart';
import '../domain/set_log.dart';

@immutable
class SessionState {
  const SessionState({
    required this.session,
    required this.day,
    required this.setLogs,
    required this.currentExerciseIndex,
    required this.elapsedSeconds,
  });

  final Session session;
  final RoutineDay day;
  final List<SetLog> setLogs;
  final int currentExerciseIndex;
  final int elapsedSeconds;

  // ---- Derived getters (NOT stored) -------------------------------------
  // Decision (§6 lock): isFullyCompleted and totalVolumeKg are GETTERS, not
  // fields. The DTO carries `day` (option (a) from launch prompt) so the
  // getter is self-contained — it does NOT need a Routine lookup at call
  // time. Computing on access is O(slots × logs) which is tiny (≤ 8 × 50
  // ≈ 400 cmps), well under one frame. Storing as fields would risk
  // staleness on every copyWith.

  bool get isFullyCompleted => day.slots.every((slot) {
        final count = setsLoggedFor(slot.exerciseId);
        return count >= slot.targetSets;
      });

  double get totalVolumeKg =>
      setLogs.fold<double>(0.0, (sum, l) => sum + l.reps * l.weightKg);

  // ---- UI helpers --------------------------------------------------------
  int setsLoggedFor(String exerciseId) =>
      setLogs.where((l) => l.exerciseId == exerciseId).length;

  bool isExerciseDone(String exerciseId) {
    final slot = day.slots.firstWhere((s) => s.exerciseId == exerciseId);
    return setsLoggedFor(exerciseId) >= slot.targetSets;
  }

  int get completedExerciseCount =>
      day.slots.where((s) => isExerciseDone(s.exerciseId)).length;

  // ---- Mutation ----------------------------------------------------------
  SessionState copyWith({
    Session? session,
    RoutineDay? day,
    List<SetLog>? setLogs,
    int? currentExerciseIndex,
    int? elapsedSeconds,
  }) =>
      SessionState(
        session: session ?? this.session,
        day: day ?? this.day,
        setLogs: setLogs ?? this.setLogs,
        currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionState &&
          runtimeType == other.runtimeType &&
          session == other.session &&
          day == other.day &&
          listEquals(setLogs, other.setLogs) &&
          currentExerciseIndex == other.currentExerciseIndex &&
          elapsedSeconds == other.elapsedSeconds;

  @override
  int get hashCode => Object.hash(
        session,
        day,
        Object.hashAll(setLogs),
        currentExerciseIndex,
        elapsedSeconds,
      );
}
```

Notes:
- 5 stored fields, 2 derived getters, 3 UI helpers, 1 `copyWith`, structural `==` via `listEquals`.
- Spec REQ-SESSION-STATE-001 mentions "7 fields and 2 derived getters". Our 5+2 form is functionally equivalent: `isFullyCompleted` and `totalVolumeKg` are exposed but NOT stored. The spec says: "may also be stored as a field" → we choose getter form. SCENARIO-250..255 still verify them via `state.isFullyCompleted`/`state.totalVolumeKg` calls. Locked.
- The state is identical for fresh and resume paths — the difference lives entirely in `build()`'s `switch` over `SessionInit`.

### 3.3 `SessionNotifier` class — dual-path dispatch

Riverpod's `AsyncNotifier` is parameterless. For a family with a sealed key, we use **`FamilyAsyncNotifier`** (the dedicated base class) — NOT `AsyncNotifier.family` (which does not exist in Riverpod 2.x).

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/routine_providers.dart';
import '../../domain/routine.dart';
import '../../domain/routine_day.dart';
import '../data/session_repository.dart';      // Etapa 1
import '../domain/session.dart';                // Etapa 1
import '../domain/set_log.dart';                // Etapa 1
import 'session_init.dart';
import 'session_providers.dart';                // for sessionRepositoryProvider, currentUidProvider
import 'session_state.dart';

class SessionNotifier
    extends FamilyAsyncNotifier<SessionState, SessionInit> {
  Timer? _timer;
  bool _finalized = false;

  // arg is provided automatically by FamilyAsyncNotifier — accessed via `arg`.

  @override
  Future<SessionState> build(SessionInit arg) async {
    final state = switch (arg) {
      FreshSession(routineId: final rid, dayNumber: final dn) =>
        await _buildFresh(rid, dn),
      ResumeSession(sessionId: final sid) => await _buildResume(sid),
    };

    // Timer is identical for both paths. Started AFTER state assembly so
    // _onTick can rely on state.value being non-null on the very first tick.
    _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });

    return state;
  }

  // ---- Path A — Fresh session ------------------------------------------

  Future<SessionState> _buildFresh(String routineId, int dayNumber) async {
    final routine = await ref.read(routineByIdProvider(routineId).future);
    if (routine == null) {
      throw StateError('Routine $routineId not found');
    }
    final day = routine.days.firstWhere(
      (d) => d.dayNumber == dayNumber,
      orElse: () => throw StateError(
        'Day $dayNumber not found in routine $routineId',
      ),
    );

    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      throw StateError('SessionNotifier built without an authenticated user');
    }
    final session = await repo.create(
      uid: uid,
      routineId: routineId,
      dayNumber: dayNumber,
    );

    return SessionState(
      session: session,
      day: day,
      setLogs: const [],
      currentExerciseIndex: 0,
      elapsedSeconds: 0,
    );
  }

  // ---- Path B — Resume existing session --------------------------------

  Future<SessionState> _buildResume(String sessionId) async {
    final repo = ref.read(sessionRepositoryProvider);
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      throw StateError('Resume requested without an authenticated user');
    }

    // findActiveForUid is the only repo entry point for resume — see Decision
    // 12 and the Etapa 1 contract. The returned record contains the Session
    // doc + all already-logged SetLogs in one round trip.
    final record = await repo.findActiveForUid(uid);
    if (record == null) {
      throw StateError(
        'Resume requested for $sessionId but no active session was found',
      );
    }
    final session = record.session;
    final recoveredLogs = record.setLogs;

    // Defensive: if the resumed session id does not match the requested one,
    // surface a clear error. This protects against stale resume routes.
    if (session.id != sessionId) {
      throw StateError(
        'Active session id ${session.id} does not match requested $sessionId',
      );
    }

    final routine =
        await ref.read(routineByIdProvider(session.routineId).future);
    if (routine == null) {
      throw StateError('Routine ${session.routineId} not found');
    }
    final day = routine.days.firstWhere(
      (d) => d.dayNumber == session.dayNumber,
      orElse: () => throw StateError(
        'Day ${session.dayNumber} not found in routine ${session.routineId}',
      ),
    );

    final currentIndex = _nextIncompleteIndex(day, recoveredLogs);
    final elapsed =
        DateTime.now().difference(session.startedAt).inSeconds.clamp(0, 1 << 31);

    return SessionState(
      session: session,
      day: day,
      setLogs: List<SetLog>.unmodifiable(recoveredLogs),
      currentExerciseIndex: currentIndex,
      elapsedSeconds: elapsed,
    );
  }

  // ---- Public mutations -------------------------------------------------

  Future<void> logSet(SetLog setLog) async {
    final current = state.value;
    if (current == null || _finalized) return;

    final repo = ref.read(sessionRepositoryProvider);
    await repo.logSet(current.session.id, setLog);

    final newLogs = [...current.setLogs, setLog];
    final newIndex = _nextIncompleteIndex(current.day, newLogs);

    state = AsyncData(current.copyWith(
      setLogs: newLogs,
      currentExerciseIndex: newIndex,
    ));
  }

  Future<void> abandonSession() async {
    if (_finalized) return;
    final current = state.value;
    if (current == null) return;

    _finalize();
    final repo = ref.read(sessionRepositoryProvider);
    final updated = await repo.finish(
      current.session.id,
      wasFullyCompleted: false,
      totalVolumeKg: current.totalVolumeKg,
      durationMin: _durationMin(current.elapsedSeconds),
    );
    state = AsyncData(current.copyWith(session: updated));
  }

  Future<void> finishSession() async {
    if (_finalized) return;
    final current = state.value;
    if (current == null) return;
    if (!current.isFullyCompleted) {
      throw StateError('finishSession called before isFullyCompleted == true');
    }

    _finalize();
    final repo = ref.read(sessionRepositoryProvider);
    final updated = await repo.finish(
      current.session.id,
      wasFullyCompleted: true,
      totalVolumeKg: current.totalVolumeKg,
      durationMin: _durationMin(current.elapsedSeconds),
    );
    state = AsyncData(current.copyWith(session: updated));
  }

  // ---- Private helpers --------------------------------------------------

  void _onTick(Timer _) {
    final current = state.value;
    if (current == null || _finalized) return;
    final elapsed = DateTime.now()
        .difference(current.session.startedAt)
        .inSeconds;
    state = AsyncData(current.copyWith(elapsedSeconds: elapsed));
  }

  void _finalize() {
    _finalized = true;
    _timer?.cancel();
    _timer = null;
  }

  int _nextIncompleteIndex(RoutineDay day, List<SetLog> logs) {
    for (var i = 0; i < day.slots.length; i++) {
      final slot = day.slots[i];
      final count = logs.where((l) => l.exerciseId == slot.exerciseId).length;
      if (count < slot.targetSets) return i;
    }
    return day.slots.length - 1;
  }

  int _durationMin(int elapsedSeconds) {
    if (elapsedSeconds <= 0) return 1;
    return ((elapsedSeconds + 59) ~/ 60); // ceil
  }
}
```

Notes:
- `FamilyAsyncNotifier<SessionState, SessionInit>` is the correct base class. The `build` method receives `arg` (the SessionInit). The sealed switch is exhaustive.
- Path A logic is unchanged from the pre-Decision-12 design — `repo.create` + return fresh state.
- Path B reads via `repo.findActiveForUid(uid)` (single round trip — returns session + setLogs together per the Etapa 1 contract). It recomputes `currentExerciseIndex` via `_nextIncompleteIndex` and `elapsedSeconds` from `session.startedAt`. NO `repo.create` is called — that's the central guarantee verified by SCENARIO-318.
- Logs are wrapped in `List<SetLog>.unmodifiable(...)` on the resume path to prevent accidental mutation of the repo-supplied list. The fresh path uses `const []` which is already unmodifiable.
- `_finalized` is a defensive flag: once `abandon`/`finish` runs, `logSet` becomes a no-op and timer ticks are ignored. This guards against double-tap UI bugs.
- `_timer` is `Timer?` from `dart:async`. Locked decision (propose §3 said "Stream.periodic" but `Timer.periodic` is the lower-level primitive and easier to test with fake_async).
- `currentUidProvider` is exposed from `session_providers.dart` (was file-private in the previous design — promoted to public because the resume `FutureProvider` also needs it). Tests override `authStateChangesProvider` directly (the upstream).

---

## 4. Provider declarations

`lib/features/workout/application/session_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart'; // authStateChangesProvider
import '../data/session_repository.dart';            // Etapa 1
import '../domain/session.dart';                      // Etapa 1
import '../domain/set_log.dart';                      // Etapa 1
import 'session_init.dart';
import 'session_notifier.dart';
import 'session_state.dart';

/// Passthrough — concrete `FirebaseSessionRepository` is injected by Etapa 1.
final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => throw UnimplementedError(
    'SessionRepository must be overridden by Etapa 1 wiring',
  ),
);

/// Auth-resolved uid. Returns `null` when no user is signed in.
/// Promoted from file-private to public because `activeSessionForUidProvider`
/// also depends on it (Decision 12).
final currentUidProvider = Provider<String?>((ref) {
  final user = ref.watch(authStateChangesProvider).valueOrNull;
  return user?.uid;
});

/// Per-init session player notifier. autoDispose is CRITICAL:
/// when the user leaves /workout/session/* the notifier disposes, which
/// cancels the timer via ref.onDispose. Without autoDispose the timer
/// would leak across navigation pops.
final sessionNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<SessionNotifier, SessionState, SessionInit>(
  SessionNotifier.new,
);

/// Resume-flow check (Decision 12). On `/home` mount the HomeScreen watches
/// this future. Non-null result → ResumeSessionModal. Null → no modal.
/// autoDispose so each app-foreground re-trip refreshes the check.
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

Notes:
- `AsyncNotifierProvider.autoDispose.family` is the canonical Riverpod 2.x form. Order matters: `.autoDispose.family`, NOT `.family.autoDispose`.
- `sessionRepositoryProvider` defaults to `throw UnimplementedError` so a misconfigured test fails loudly. In production it is overridden by Etapa 1's module wiring.
- `currentUidProvider` is auth-gated. `activeSessionForUidProvider` short-circuits to `null` BEFORE invoking the repo if uid is null — this is the contract verified by SCENARIO-324 ("repo NOT called when unauthenticated").
- `activeSessionForUidProvider` is `autoDispose` — the future is re-evaluated on each foreground/re-mount of `/home`. After the user discards a session, the home screen invalidates the provider explicitly (see §11.5) so subsequent boots see no active session.

---

## 5. Widget tree composition

Notation: `[route]` = produced by the GoRoute builder in `router.dart`. `[screen]` = produced by `SessionPlayerScreen.build`. Spacing values use the allowed set `{8, 12, 14, 18, 20}` only (spec REQ-SESSION-THEME-001).

### 5.1 `SessionPlayerScreen` tree (data branch — `AsyncData<SessionState>`)

```
[route] Scaffold(backgroundColor: palette.bg)
[route]   body: SessionPlayerScreen(init: ...)
[screen]     PopScope(canPop: false, onPopInvoked: (_) => _showAbandonConfirm())
[screen]       SafeArea
[screen]         Column(crossAxisAlignment: stretch)
[screen]           _SessionHeader(
[screen]             routineSplit: routine.split,                   // see §9.3
[screen]             dayNumber: state.day.dayNumber,
[screen]             onAbandon: _showAbandonConfirm,
[screen]             onBack:    _showAbandonConfirm,
[screen]           )
[screen]           Expanded
[screen]             ListView(padding: EdgeInsets.symmetric(horizontal: 20))
[screen]               SizedBox(height: 12)
[screen]               _AttendanceCard()
[screen]               SizedBox(height: 14)
[screen]               _SessionStatsCard(state: state)
[screen]               SizedBox(height: 20)
[screen]               _SectionLabel('EJERCICIOS')
[screen]               SizedBox(height: 12)
[screen]               ...state.day.slots.asMap().entries.expand((entry) => [
[screen]                 _ExerciseListRow(
[screen]                   slot: entry.value,
[screen]                   status: _statusFor(entry.key, state),
[screen]                   completedSets: state.setsLoggedFor(entry.value.exerciseId),
[screen]                   onTap: _statusFor(entry.key, state) != ExerciseRowStatus.done
[screen]                            ? () => _openSetEntry(entry.value, state)
[screen]                            : null,
[screen]                 ),
[screen]                 SizedBox(height: 12),
[screen]               ])
[screen]               SizedBox(height: 20)
[screen]           Padding(EdgeInsets.fromLTRB(20, 12, 20, 18))
[screen]             _TerminarSessionButton(
[screen]               enabled: state.isFullyCompleted,
[screen]               onPressed: state.isFullyCompleted ? _finishSession : null,
[screen]             )
```

Key invariants:
- The screen introduces its OWN `Scaffold`-style chrome through the route builder. The screen body itself starts at `PopScope`.
- `Column(crossAxisAlignment: stretch)` is the outer layout. The middle ListView is `Expanded` so the bottom CTA stays pinned.
- All vertical gaps come from the allowed set `{8, 12, 14, 18, 20}`. No `16`, no `24`.
- The tree is **identical** for fresh and resume paths — once the notifier resolves, the state shape is the same. The only difference is `state.setLogs` is non-empty on resume.

### 5.2 Loading and error branches

```
loading: Center(child: CircularProgressIndicator(color: palette.accent))
error:   Center(
           child: Padding(
             padding: EdgeInsets.symmetric(horizontal: 20),
             child: Text(
               'No pudimos iniciar la sesión.',
               style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
               textAlign: TextAlign.center,
             ),
           ),
         )
```

Loading and error branches are **OUTSIDE** the `PopScope` wrapper. Spec REQ-SESSION-SCREEN-001 (SCENARIO-273) only requires `PopScope(canPop: false)` in the data branch.

### 5.3 `SetEntrySheet` tree

```
Container(
  decoration: BoxDecoration(
    color: palette.bgCard,
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
)
  Padding(EdgeInsets.fromLTRB(20, 20, 20, 20))
    Column(mainAxisSize: min, crossAxisAlignment: stretch)
      Center(child: Container(width: 40, height: 4, color: palette.border))
      SizedBox(height: 18)
      Text(slot.exerciseName.toUpperCase(), style: titleStyle)
      SizedBox(height: 8)
      Text('SET $setNumber DE ${slot.targetSets}', style: subtitleStyle)
      SizedBox(height: 8)
      Text('Objetivo: ${slot.targetRepsMin}–${slot.targetRepsMax} reps · '
           '${slot.targetWeightKg ?? '–'} kg', style: hintStyle)
      SizedBox(height: 20)

      Row(mainAxisAlignment: center, children: [
        _StepperButton(icon: '–', onTap: _decReps),
        SizedBox(width: 20),
        Text('$_reps', style: bigNumberStyle),
        SizedBox(width: 20),
        _StepperButton(icon: '+', onTap: _incReps),
      ])
      SizedBox(height: 8)
      Text('REPS', style: stepperLabelStyle)
      SizedBox(height: 20)

      Row(mainAxisAlignment: center, children: [
        _StepperButton(icon: '–', onTap: _decWeight),
        SizedBox(width: 20),
        Text(_formatWeight(_weight), style: bigNumberStyle),
        SizedBox(width: 20),
        _StepperButton(icon: '+', onTap: _incWeight),
      ])
      SizedBox(height: 8)
      Text('KG', style: stepperLabelStyle)
      SizedBox(height: 20)

      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _onCheckTap,
          style: mintPillStyle,
          child: Text('CHECK', style: pillLabelStyle),
        ),
      )
      SizedBox(height: 8)
```

The sheet is shown via:

```dart
showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => SetEntrySheet(
    slot: effectiveSlot,  // see §9.7 — overrides defaults with last log
    setNumber: state.setsLoggedFor(slot.exerciseId) + 1,
    onCheck: (reps, weightKg) {
      ref.read(sessionNotifierProvider(widget.init).notifier).logSet(
        SetLog(
          id: '',                              // see §9.6 — repo assigns
          exerciseId: slot.exerciseId,
          setNumber: state.setsLoggedFor(slot.exerciseId) + 1,
          reps: reps,
          weightKg: weightKg,
          completedAt: DateTime.now(),
        ),
      );
    },
  ),
);
```

`_StepperButton` is a small private widget in `set_entry_sheet.dart` (same shape as previous design — unchanged).

### 5.4 `_AbandonConfirmDialog` tree

```
AlertDialog(
  backgroundColor: palette.bgCard,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  content: Text(
    '¿Seguro que querés abandonar? Se va a guardar tu progreso hasta acá.',
    style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
  ),
  actions: [
    OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text('Cancelar', style: cancelStyle),
    ),
    ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: palette.highlight),
      onPressed: () {
        Navigator.of(context).pop();
        onConfirm();
      },
      child: Text('Abandonar', style: destructiveStyle),
    ),
  ],
)
```

`palette.highlight` is the magenta token (brand destructive color). Locked.

### 5.5 `ResumeSessionModal` tree (Decision 12)

```
AlertDialog(
  backgroundColor: palette.bgCard,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  title: Text('Entrenamiento en curso', style: titleStyle),    // 18 / 700 / Barlow Cond
  content: Text(
    'Tenés un entrenamiento desde 18:42. ¿Querés continuarlo o descartarlo?',
    style: bodyStyle,                                          // 14 / 400 / Barlow
  ),
  actions: [
    OutlinedButton(
      onPressed: onDiscard,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: palette.highlight),
        foregroundColor: palette.highlight,
      ),
      child: Text('Descartar', style: destructiveOutlinedStyle),
    ),
    ElevatedButton(
      onPressed: onContinue,
      style: ElevatedButton.styleFrom(backgroundColor: palette.accent),
      child: Text('Continuar', style: mintFilledStyle),
    ),
  ],
)
```

Shown via:

```dart
showDialog<void>(
  context: context,
  barrierDismissible: false,                // spec REQ-SESSION-RESUME-003
  builder: (dialogCtx) => ResumeSessionModal(
    session: record.session,
    onContinue: () => _onResumeContinue(dialogCtx, record.session),
    onDiscard:  () => _onResumeDiscard(dialogCtx, record),
  ),
);
```

`barrierDismissible: false` is the call-site responsibility (the widget itself is a `StatelessWidget` AlertDialog). Spec REQ-SESSION-RESUME-003 explicitly defers this to the call site.

---

## 6. State transitions and side effects

Full state machine — IDENTICAL for fresh and resume paths once `build()` resolves:

```
                    +-----------------+
                    | Notifier built  |
                    | (AsyncLoading)  |
                    +--------+--------+
                             |
                       switch(arg)
                       /          \
              FreshSession      ResumeSession
                  |                 |
            _buildFresh        _buildResume
            repo.create        repo.findActiveForUid
                  \                 /
                   \               /
                    \             /
                     \           /
                      Start Timer
                      ref.onDispose(cancel)
                             |
                             v
                  +----------------------+
                  | AsyncData(state)     |
                  | elapsedSeconds++/sec |<-+ _onTick (every second)
                  +-----+----+-----+-----+  |
                        |    |     |        |
              logSet()  |    |     |        |
                        v    |     |        |
              repo.logSet()  |     |        |
              + state update |     |        |
                             |     |        |
                  abandonSession() |        |
                             v     |        |
                  repo.finish(false)        |
                  + _finalize()             |
                  + timer.cancel()          |
                  + state = finished        |
                                            |
                  finishSession()           |
                  (only if isFullyCompleted)|
                             v              |
                  repo.finish(true)         |
                  + _finalize()             |
                  + timer.cancel()          |
                  + state = finished        |
                                            |
                  ref.onDispose() ----------+
```

Side effects per action:

| Action | Firestore | In-memory state | Timer | Navigation |
|---|---|---|---|---|
| `_buildFresh` | `repo.create` | `AsyncData(SessionState(setLogs=[], idx=0, elapsed=0))` | start | — |
| `_buildResume` | `repo.findActiveForUid` | `AsyncData(SessionState(setLogs=recovered, idx=recomputed, elapsed=recomputed))` | start | — |
| `_onTick` | none | `state.copyWith(elapsedSeconds: ...)` | continues | — |
| `logSet(log)` | `repo.logSet` | append + advance `currentExerciseIndex` | continues | — |
| `abandonSession()` | `repo.finish(false)` | `state.copyWith(session: updated)` | **cancel** | screen pushes `/workout/session-summary/${session.id}` |
| `finishSession()` | `repo.finish(true)` | `state.copyWith(session: updated)` | **cancel** | screen pushes `/workout/session-summary/${session.id}` |
| `ref.onDispose` | none | n/a — notifier going away | **cancel** (defensive) | — |
| **HomeScreen resume: Continuar** | none (transitively `_buildResume` runs on the player route) | `activeSessionForUidProvider` invalidated | n/a | `context.push('/workout/session/resume/${session.id}')` |
| **HomeScreen resume: Descartar** | `repo.finish(false)` | `activeSessionForUidProvider` invalidated | n/a | dialog dismissed; user stays on `/home` |

Navigation is the **screen's** responsibility, NOT the notifier's. The notifier remains unit-testable without a router.

`isFullyCompleted` computation: option (a) is LOCKED — `SessionState` carries `day` as a field (already specified §3.2). The getter computes from `setLogs` + `day.slots` with no provider lookup needed.

---

## 7. Timer mechanics

Unchanged from pre-Decision-12 design EXCEPT the timer now starts AFTER the `switch` in `build()` so both Path A and Path B benefit from the same single timer-start path:

```dart
@override
Future<SessionState> build(SessionInit arg) async {
  final state = switch (arg) {
    FreshSession(...) => await _buildFresh(...),
    ResumeSession(...) => await _buildResume(...),
  };

  _timer = Timer.periodic(const Duration(seconds: 1), _onTick);
  ref.onDispose(() {
    _timer?.cancel();
    _timer = null;
  });

  return state;
}
```

Notes:
- `Timer.periodic` from `dart:async` — no new dep needed.
- `_onTick` recomputes elapsed from `session.startedAt` — auto-corrects on background resume AND on resume-flow rehydration (the elapsed value picks up where the original session left off without any extra logic).
- `ref.onDispose` is the safety net for both paths. SCENARIO-258 verifies dispose cancellation.
- Resume-specific test: SCENARIO-321 verifies `elapsedSeconds` is approximately `300` when `session.startedAt` is 5 minutes in the past.

Time format `MM:SS` — see §9.4.

---

## 8. Token usage table

All colors via `AppPalette.of(context)` — no HEX literals. The table from the previous design version is unchanged; new rows below for the resume modal.

| Element | Color token | Font family | Weight | Size | Letter-spacing |
|---|---|---|---|---|---|
| Screen background | `palette.bg` | — | — | — | — |
| `_SessionHeader` — title | `palette.textPrimary` | Barlow Condensed | 700 | 20 | 1.4 |
| `_SessionHeader` — ABANDONAR pill | `palette.highlight` border + label | Barlow Condensed | 700 | 12 | 1.0 |
| `_AttendanceCard` — bg | `palette.bgCard` | — | — | — | — |
| `_AttendanceCard` — icon | `palette.accent` (size 20) | — | — | — | — |
| `_AttendanceCard` — main text | `palette.textPrimary` | Barlow | 600 | 14 | — |
| `_AttendanceCard` — subtitle | `palette.textMuted` | Barlow | 400 | 12 | — |
| `_SessionStatsCard` — `'SESIÓN ACTIVA'` | `palette.accent` | Barlow Condensed | 700 | 12 | 1.2 |
| `_SessionStatsCard` — timer `MM:SS` | `palette.accent` | Barlow Condensed | 700 | 40 | — |
| `_SessionStatsCard` — progress bar | `palette.accent` (track: `palette.border`) | — | — | — | — |
| `_ExerciseListRow` — done name | `palette.textMuted` (lineThrough) | Barlow | 600 | 16 | — |
| `_ExerciseListRow` — current/pending name | `palette.textPrimary` | Barlow | 600 | 16 | — |
| `_ExerciseListRow` — Ahora pill | bg `palette.accent`, text `palette.bg` | Barlow Condensed | 600 | 12 | 0.8 |
| `_TerminarSessionButton` — enabled bg | `palette.accent` | — | — | — | — |
| `_TerminarSessionButton` — enabled label | `palette.bg` | Barlow Condensed | 700 | 16 | 1.0 |
| `_TerminarSessionButton` — disabled wrapper | `Opacity(0.4)` | — | — | — | — |
| `SetEntrySheet` — bg | `palette.bgCard` | — | — | — | — |
| `SetEntrySheet` — title | `palette.textPrimary` | Barlow Condensed | 700 | 18 | 1.2 |
| `SetEntrySheet` — subtitle | `palette.accent` | Barlow Condensed | 600 | 12 | 1.0 |
| `SetEntrySheet` — `_StepperButton` symbol | `palette.textPrimary` | Barlow Condensed | 700 | 24 | — |
| `SetEntrySheet` — big number | `palette.textPrimary` | Barlow Condensed | 700 | 40 | — |
| `SetEntrySheet` — CHECK bg | `palette.accent` | — | — | — | — |
| `_AbandonConfirmDialog` — bg | `palette.bgCard` | — | — | — | — |
| `_AbandonConfirmDialog` — body | `palette.textPrimary` | Barlow | 400 | 14 | — |
| `_AbandonConfirmDialog` — Abandonar bg | `palette.highlight` | — | — | — | — |
| **`ResumeSessionModal` — bg** | `palette.bgCard` | — | — | — | — |
| **`ResumeSessionModal` — title** | `palette.textPrimary` | Barlow Condensed | 700 | 18 | 1.2 |
| **`ResumeSessionModal` — body** | `palette.textPrimary` | Barlow | 400 | 14 | — |
| **`ResumeSessionModal` — Descartar border + label** | `palette.highlight` | Barlow Condensed | 700 | 14 | 0.8 |
| **`ResumeSessionModal` — Continuar bg** | `palette.accent` | — | — | — | — |
| **`ResumeSessionModal` — Continuar label** | `palette.bg` | Barlow Condensed | 700 | 14 | 0.8 |
| Loading spinner | `palette.accent` | — | — | — | — |
| Error text | `palette.textMuted` | Barlow | 400 | 14 | — |

---

## 9. Edge case decisions

### 9.1 Route param `dayNumber` parsing

Fresh route builder in `router.dart`:

```dart
GoRoute(
  path: '/workout/session/:routineId/:dayNumber',
  redirect: authRedirect,
  pageBuilder: (context, state) {
    final routineId = state.pathParameters['routineId']!;
    final dayNumberStr = state.pathParameters['dayNumber']!;
    final dayNumber = int.tryParse(dayNumberStr);
    if (dayNumber == null) {
      return _noAnim(Scaffold(
        body: Center(child: Text('Ruta inválida: dayNumber=$dayNumberStr')),
      ));
    }
    return _noAnim(Scaffold(
      body: SessionPlayerScreen(
        init: FreshSession(routineId: routineId, dayNumber: dayNumber),
      ),
    ));
  },
),
```

Resume route builder (NEW — §12):

```dart
GoRoute(
  path: '/workout/session/resume/:sessionId',
  redirect: authRedirect,
  pageBuilder: (context, state) {
    final sessionId = state.pathParameters['sessionId']!;
    return _noAnim(Scaffold(
      body: SessionPlayerScreen(
        init: ResumeSession(sessionId: sessionId),
      ),
    ));
  },
),
```

Rationale: `int.tryParse` (NOT `int.parse`) — defensive against malformed deep links. The resume route does NOT need parsing — `sessionId` is a string passthrough. Both routes are auth-gated via `authRedirect`.

### 9.2 Empty state — current exercise after all done

Unchanged from prior design. `_nextIncompleteIndex` returns `day.slots.length - 1` when everything is complete; `_statusFor(lastIndex, state)` returns `done`. No `"Ahora"` badge is rendered. Bottom CTA is the only next action.

### 9.3 Session title source

Spec REQ-SESSION-SCREEN-002 (SCENARIO-274) requires `'${routine.split.toUpperCase()} · DÍA ${dayNumber}'`. The screen reads `routineByIdProvider` separately:

```dart
final viewAsync = ref.watch(sessionNotifierProvider(widget.init));

// On Path A we know the routineId from init directly.
// On Path B we read it from state.session.routineId once the notifier resolves.
final routineId = switch (widget.init) {
  FreshSession(routineId: final rid) => rid,
  ResumeSession() => viewAsync.value?.session.routineId,
};

final routineAsync = routineId != null
    ? ref.watch(routineByIdProvider(routineId))
    : const AsyncLoading<Routine?>();
final routineSplit = routineAsync.valueOrNull?.split ?? '';
```

On Path B the routine lookup is deferred until the session loads (we need `session.routineId` to know which routine to look up). This is fine because the header is only rendered in the `AsyncData` branch — by then both watches have resolved.

Locked.

### 9.4 Time format `MM:SS`

```dart
String _formatMMSS(int totalSeconds) {
  final m = (totalSeconds ~/ 60).clamp(0, 99).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
```

File-scope helper in `session_player_screen.dart`. Used by `_SessionStatsCard`. Spec REQ-SESSION-SCREEN-004 SCENARIO-280/281.

A separate `_formatHHMM` lives in `resume_session_modal.dart` for the wall-clock time. Different concern, different file.

### 9.5 `gymNameFromId` cross-feature reuse

Unchanged. `_AttendanceCard` imports `gymNameFromId` from `lib/features/feed/domain/gym_name.dart`. Value-only helper, pure function. Follow-up flag if a third feature consumes it.

### 9.6 `SetLog.id` assignment

Repo-generated (pattern b). Screen constructs `SetLog(id: '', ...)`; repo overwrites with a Firestore-generated doc id. Mirrors `FriendshipRepository.request`. Apply phase verifies against Dev A's actual implementation.

The resume path is unaffected — the repo's `findActiveForUid` returns logs with their already-assigned ids.

### 9.7 Reps/weight defaults — first set vs subsequent sets

Unchanged. The screen wraps `slot` with overridden defaults (`slot.copyWith(targetRepsMin: lastLog.reps, targetWeightKg: lastLog.weightKg)`) BEFORE pumping the sheet. Friction-reduction UX. On the resume path the `setLogs` are already in `state.setLogs` — the same lookup naturally finds the most recent log.

### 9.8 Sheet close on submit

Unchanged. Sheet pops itself on CHECK tap. Locked.

### 9.9 ABANDONAR / TERMINAR navigation target

Unchanged. Both abandon and finish use `context.go('/workout/session-summary/${session.id}')`. `mounted` guard after the await.

The summary route lives OUTSIDE the ShellRoute. Locked.

### 9.10 Self-protection: double-tap on TERMINAR / ABANDONAR

Unchanged. `_finalized` flag short-circuits the second call.

### 9.11 Routine lookup on resume path (NEW)

When the resume notifier loads the session, the `session.routineId` may point at a routine the user has since deleted or unsubscribed from. In that case `routineByIdProvider(session.routineId)` returns `null` and `_buildResume` throws `StateError('Routine ... not found')`.

The screen surfaces this as an `AsyncError` branch (the error text `'No pudimos iniciar la sesión.'`). The user is NOT stuck — they can pop back to `/home` (the `PopScope` is only in the data branch).

This is acceptable for MVP. A future Etapa MAY add "the routine no longer exists — discard?" UX. For now, the error message is intentionally generic.

---

## 10. Implementation order recommendation

Strict TDD: per artifact, the test file is committed RED first; production code follows and turns it GREEN. The resume primitives land EARLY in the sequence so the notifier can be built once with both paths in place — no half-built abstractions to retrofit.

| # | Step | Test file | Production file | Notes |
|---|---|---|---|---|
| 0 | **Pre-flight** — verify Etapa 1 contract on `main` | (manual) | (none) | Inspect `lib/features/workout/domain/session.dart`, `set_log.dart`, `data/session_repository.dart`. **MUST include `findActiveForUid`** (Decision 12). If any deviation → STOP, re-run propose. |
| 0a | **Verify `findActiveForUid` contract specifically** | (manual) | (none) | Confirm the signature returns `Future<({Session session, List<SetLog> setLogs})?>`. If Dev A used a different shape (e.g. separate methods), STOP and re-run propose. |
| 1 | `SessionState` DTO + derived getters | `test/features/workout/application/session_state_test.dart` | `lib/features/workout/application/session_state.dart` | SCENARIO-250..255. Pure Dart, no Riverpod. |
| 2 | `SessionInit` sealed class | `test/features/workout/application/session_init_test.dart` | `lib/features/workout/application/session_init.dart` | Equality + hashCode + pattern match exhaustiveness. NEW per Decision 12. |
| 3 | Providers shells (`sessionRepositoryProvider`, `currentUidProvider`, `sessionNotifierProvider`, `activeSessionForUidProvider`) | `test/features/workout/application/session_providers_test.dart` | `lib/features/workout/application/session_providers.dart` | SCENARIO-269 (family key uniqueness on SessionInit subtypes) + SCENARIO-322..324 (resume provider auth gating). |
| 4 | `SessionNotifier._buildFresh` (Path A) | `test/features/workout/application/session_notifier_test.dart` (partial — Path A only) | `lib/features/workout/application/session_notifier.dart` (partial) | SCENARIO-256..258. Mock `routineByIdProvider`, `sessionRepositoryProvider`, `authStateChangesProvider`. |
| 5 | `SessionNotifier._buildResume` (Path B) — Decision 12 | same test file (add tests) | same notifier (add method) | SCENARIO-318..321. Verifies `repo.create` is NOT called and `findActiveForUid` IS called. Restores setLogs and recomputes currentExerciseIndex + elapsedSeconds. |
| 6 | `SessionNotifier.logSet` | same test file | same notifier (add method) | SCENARIO-259..264. |
| 7 | `SessionNotifier.abandonSession` | same test file | same notifier | SCENARIO-265..266. |
| 8 | `SessionNotifier.finishSession` | same test file | same notifier | SCENARIO-267..268. |
| 9 | `ResumeSessionModal` widget — Decision 12 | `test/features/workout/presentation/widgets/resume_session_modal_test.dart` | `lib/features/workout/presentation/widgets/resume_session_modal.dart` | SCENARIO-329..333. Pure presentational tests. |
| 10 | `HomeScreen` resume listener — Decision 12 | extend `test/features/home/home_screen_test.dart` (additive) | modify `lib/features/home/home_screen.dart` | SCENARIO-325..328 (modal appears / does not appear / loading / error states). |
| 11 | `SetEntrySheet` widget | `test/features/workout/presentation/widgets/set_entry_sheet_test.dart` | `lib/features/workout/presentation/widgets/set_entry_sheet.dart` | SCENARIO-291..304. |
| 12 | `SessionPlayerScreen` assembly (with private widgets) | `test/features/workout/presentation/session_player_screen_test.dart` | `lib/features/workout/presentation/session_player_screen.dart` | SCENARIO-270..290, 305..310. Pumps with both `FreshSession` and `ResumeSession` init values (different overrides). |
| 13 | Router additions (3 top-level routes) | (SCENARIO-311, 312, 334, 335 covered by integration tests in step 12) | `lib/app/router.dart` | Add 3 `GoRoute`s outside the existing `ShellRoute`: fresh + resume + summary stub. |
| 14 | `RoutineDetailScreen` wire — replace `_DisabledCTABar` with `_StartSessionCTABar` | additions to `routine_detail_screen_test.dart` | `lib/features/workout/presentation/routine_detail_screen.dart` | SCENARIO-313, 314, 315. |
| 15 | Quality gates | — | — | `flutter analyze` (0 issues), `dart format .` clean, `flutter test` green. |

Suggested commit messages (work-unit commits):

1. `test+feat(session-player): add SessionState DTO with derived getters`
2. `test+feat(session-player): add SessionInit sealed family key`
3. `test+feat(session-player): add session providers (repo + uid + notifier + activeSession)`
4. `test+feat(session-player): SessionNotifier.build(FreshSession) creates session and starts timer`
5. `test+feat(session-player): SessionNotifier.build(ResumeSession) restores from findActiveForUid`
6. `test+feat(session-player): SessionNotifier.logSet persists + advances index`
7. `test+feat(session-player): SessionNotifier.abandonSession finalizes with wasFullyCompleted=false`
8. `test+feat(session-player): SessionNotifier.finishSession asserts isFullyCompleted`
9. `test+feat(session-player): add ResumeSessionModal widget`
10. `test+feat(home): show ResumeSessionModal on active session via post-frame listener`
11. `test+feat(session-player): add SetEntrySheet with reps/weight steppers`
12. `test+feat(session-player): assemble SessionPlayerScreen with header + cards + list + CTA`
13. `feat(router): add fresh + resume + summary-stub top-level routes`
14. `feat(workout): wire EMPEZAR → SessionPlayer (replace _DisabledCTABar)`
15. (no commit) — quality gates

### Chained-PR split (delivery strategy)

Per propose.md §8 (HIGH RISK on 400-line budget) and the LOC bump from Decision 12, the **chained-PR signal is now STRONGER**:

- **PR 1 — `feat/session-player-logic-and-resume`** (steps 1-10, ~830 LOC): state, sealed init, notifier with both paths, providers (including `activeSessionForUidProvider`), `ResumeSessionModal`, and the HomeScreen listener. Pure logic + one minimal UI widget + one home-screen additive change. Reviewer can verify the state machine, both build paths, and the resume entry point in isolation. NO player screen yet — that ships in PR 2.
- **PR 2 — `feat/session-player-ui`** (steps 11-14, ~1295 LOC): the full player screen + set entry sheet + router additions + RoutineDetailScreen wire. Stacked on PR 1.

If maintainer applies `size:exception` label and selects `single-pr` delivery strategy, all steps land in one PR. The work-unit commits are independent regardless — bisectable.

Tests-first cadence: for steps 1-11 and 12, commit the test file in the RED state (failing) BEFORE the production file. If tooling requires GREEN-only commits, squash the test+impl into the single commits listed above.

---

## 11. Resume flow architecture (NEW — Decision 12)

This section describes the new resume-on-reopen infrastructure. It is the central addition relative to the pre-Decision-12 design.

### 11.1 `activeSessionForUidProvider`

Declared in `lib/features/workout/application/session_providers.dart`:

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

Properties:
- `FutureProvider` (NOT `StreamProvider`) — one-shot check on app boot or foreground re-mount. We don't need a real-time stream; the repo lookup is point-in-time.
- `autoDispose` — when no widget watches it, the cached value is discarded. This is what enables a fresh check after Descartar (the home screen invalidates explicitly — see §11.5 — and the next read re-runs the future).
- Auth-gated via `ref.watch(currentUidProvider)`. When uid is `null`, the future returns `null` immediately and does NOT touch the repo. This is critical because the repo's underlying Firestore call would otherwise hit permission-denied for unauthenticated users.
- Returns the record (session + setLogs) in one round trip. The screen's resume path consumes this same record indirectly through `repo.findActiveForUid` — there are TWO calls to `findActiveForUid` in the full discard-then-resume-someone-else's-session flow (rare), but on the common path the call is made just once at home-screen mount and then the player rehydrates via its own `_buildResume` (which calls `findActiveForUid` again). Acceptable cost — the call is a single Firestore read.

Scenarios SCENARIO-322..324 verify the three branches (non-null, null, unauthenticated).

### 11.2 `_ResumeSessionPrompt` mounting strategy on HomeScreen

The widget is publicly exported as `ResumeSessionModal` from `lib/features/workout/presentation/widgets/resume_session_modal.dart` (NOT a `HomeScreen`-private widget — different feature owns it; home merely triggers the show). See §2.3 for the widget API.

**Mounting point**: `lib/features/home/home_screen.dart`. The home screen watches `activeSessionForUidProvider` via `ref.listen` (NOT `ref.watch`) so the modal show is a SIDE EFFECT, not a build-driven render. This avoids the classic "showDialog inside build" anti-pattern.

Implementation pattern (additive to the existing `HomeScreen.build`):

```dart
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    // === Decision 12: resume-on-reopen prompt ============================
    ref.listen<AsyncValue<({Session session, List<SetLog> setLogs})?>>(
      activeSessionForUidProvider,
      (prev, next) {
        // Only react to a transition to AsyncData with a non-null payload.
        if (next is AsyncData && next.value != null) {
          // Skip duplicate fires (e.g. if listener re-runs with same data).
          if (prev is AsyncData && identical(prev.value, next.value)) return;
          _maybeShowResumePrompt(context, ref, next.value!);
        }
      },
    );
    // =====================================================================

    final Widget headerOrSkeleton = profileAsync.when(
      data: (profile) => HomeHeader(profile: profile),
      loading: () => const _HomeHeaderSkeleton(),
      error: (_, __) => const HomeHeader(profile: null),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        physics: const ClampingScrollPhysics(),
        children: [
          headerOrSkeleton,
          const SizedBox(height: 20),
          const EmpezarEntrenamientoCard(),
          const SizedBox(height: 12),
          const EstaSemanaCard(),
        ],
      ),
    );
  }
}

void _maybeShowResumePrompt(
  BuildContext context,
  WidgetRef ref,
  ({Session session, List<SetLog> setLogs}) record,
) {
  // Schedule for the next frame so the dialog is mounted AFTER the current
  // build pass completes — this is the canonical Flutter pattern for
  // showing a dialog reactively from a state change.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => ResumeSessionModal(
        session: record.session,
        onContinue: () => _onResumeContinue(dialogCtx, record.session),
        onDiscard:  () => _onResumeDiscard(dialogCtx, ref, record),
      ),
    );
  });
}
```

**Why `ref.listen` + post-frame callback, not `ref.watch`**:
- `ref.watch` inside `build` would rebuild the tree on every state change of the provider, which we don't want — the home screen content is independent of the active-session check.
- `showDialog` MUST NOT be called from inside `build` (it pushes a new route and triggers a rebuild → infinite loop). `addPostFrameCallback` defers it to after the build pass completes.
- The "dedupe on identical previous value" guard prevents re-showing the dialog if `ref.listen` fires for an unrelated reason (e.g., `currentUidProvider` re-emits the same uid). Spec REQ-SESSION-RESUME-002: "The dialog MUST be shown at most once per app launch".
- The `context.mounted` check is defensive — if the user navigates away in the single frame between scheduling and execution, we skip the show.

**Why a free function `_maybeShowResumePrompt` and not a `_HomeResumeController` private widget**: One trigger, two callbacks. A controller widget would add 30+ LOC for no testable surface beyond what `ref.listen` already gives us. Decision: keep it inline as file-scope private helpers. If a second screen ever needs the same prompt (it shouldn't — only `/home` post-auth is the entry point per spec REQ-SESSION-RESUME-002), a refactor is mechanical.

### 11.3 `HomeScreen` modifications — additive only

The change is purely additive: ONE `ref.listen` call inside `build` + ONE module-level helper (`_maybeShowResumePrompt`) + TWO module-level callback wirings (`_onResumeContinue`, `_onResumeDiscard`). No refactor of `HomeHeader`, `EmpezarEntrenamientoCard`, `EstaSemanaCard`, or `_HomeHeaderSkeleton`.

LOC delta: ~25 net (listener block ~10, helper ~15, callbacks ~15, minus a couple of `import` lines). All within the home screen file — no new files in `lib/features/home/`.

### 11.4 `SessionNotifier` dual-path dispatch (rationale recap)

**Decision**: Use the `SessionInit` sealed class as the family key. Single `SessionNotifier` with `switch` in `build()`.

**Rejected alternatives**:

(a) **Two separate notifiers** — `freshSessionNotifierProvider.family<SessionState, ({String routineId, int dayNumber})>` and `resumeSessionNotifierProvider.family<SessionState, String>`. The screen reads one or the other based on its constructor parameter.

  - Cons: ~80 LOC duplicated (logSet/abandonSession/finishSession/timer/`_onTick`/`_finalize` are identical across both). Two notifier classes to keep in sync — every future change has to land twice. The screen has to branch on which provider to watch, which proliferates if-else through state-routing code. NOT chosen.

(b) **Record key with nullable fields** — `typedef SessionKey = ({String? routineId, int? dayNumber, String? resumeSessionId})`. Notifier inspects which fields are non-null.

  - Cons: No exhaustive `switch`, no compile-time check that exactly ONE of the two cases is provided. Runtime assertions only. Records lose the type-safety benefit they're supposed to provide. NOT chosen.

(c) **Sealed class** — `sealed class SessionInit` with `FreshSession` and `ResumeSession` subclasses. **CHOSEN.**

  - Pros: Exhaustive `switch` in `build()` (compile-time guarantee). One notifier, one timer, one set of mutation methods. The screen passes the `init` opaquely; the screen file never imports `SessionInit` subclasses (only the route builders in `router.dart` do). LOC delta vs option (a): saves ~80 LOC of duplication.
  - Cons: One extra file (`session_init.dart`, ~30 LOC). Acceptable.

This is captured as ADR-SP-11 (§13).

### 11.5 Callbacks — `_onResumeContinue` and `_onResumeDiscard`

The two callbacks at the bottom of `lib/features/home/home_screen.dart` (or a sibling helper file if the home file grows too large — apply phase decides; keep inline if under 100 LOC additional):

```dart
void _onResumeContinue(BuildContext dialogCtx, Session session) {
  // Pop the dialog FIRST so the modal is gone by the time the player route mounts.
  Navigator.of(dialogCtx, rootNavigator: true).pop();
  // Use the underlying screen's GoRouter context, not the dialog context.
  // The dialog context is being torn down; we need the route context that
  // showed the dialog. Solution: capture it before the post-frame callback
  // or use the rootNavigator's context after pop.
  // Locked pattern: use dialogCtx.mounted check + dialogCtx parent's GoRouter.
  // In practice: GoRouter.of(dialogCtx) still works AFTER pop because we
  // route to a top-level route (not relative). Apply phase MUST verify with
  // a widget test (SCENARIO-334).
  GoRouter.of(dialogCtx).push('/workout/session/resume/${session.id}');
}

Future<void> _onResumeDiscard(
  BuildContext dialogCtx,
  WidgetRef ref,
  ({Session session, List<SetLog> setLogs}) record,
) async {
  final repo = ref.read(sessionRepositoryProvider);
  final totalVolumeKg = record.setLogs.fold<double>(
    0.0,
    (sum, l) => sum + l.reps * l.weightKg,
  );
  final elapsedSec = DateTime.now()
      .difference(record.session.startedAt)
      .inSeconds;
  final durationMin =
      elapsedSec <= 0 ? 1 : ((elapsedSec + 59) ~/ 60); // ceil, min 1

  // Pop the dialog before awaiting so the user is not staring at a frozen modal.
  if (dialogCtx.mounted) {
    Navigator.of(dialogCtx, rootNavigator: true).pop();
  }

  await repo.finish(
    record.session.id,
    wasFullyCompleted: false,
    totalVolumeKg: totalVolumeKg,
    durationMin: durationMin,
  );

  // Invalidate so next /home mount doesn't re-show the modal.
  ref.invalidate(activeSessionForUidProvider);
}
```

Notes:
- Continuar pops the dialog BEFORE pushing the player route. This prevents the dialog from briefly overlaying the player on slow devices.
- Descartar pops BEFORE awaiting `repo.finish`. The user gets immediate feedback; the network call completes silently in the background. If it fails, the user is still on `/home` and the next app launch may re-show the modal — acceptable degradation.
- `ref.invalidate(activeSessionForUidProvider)` is essential: without it, the provider's `autoDispose` cache would still hold the (now-stale) non-null record for the brief window the listener might re-fire. SCENARIO-338 verifies the modal does not reappear.
- The session-id assignment in `repo.finish` uses `record.session.id` directly — no `SessionState` involvement (this code path runs on the home screen, NOT through the player notifier).

Spec coverage:
- SCENARIO-334 — Continuar pushes resume route
- SCENARIO-335 — Resume player receives correct sessionId
- SCENARIO-336 — Descartar calls `repo.finish(wasFullyCompleted: false)`
- SCENARIO-337 — Descartar computes `totalVolumeKg` from recovered setLogs
- SCENARIO-338 — Modal dismisses + user stays on `/home`

### 11.6 Why no "discard then resume different" race

The repo contract states `findActiveForUid` returns the **most recent** active session if multiple exist (defensive — multiple actives shouldn't exist but the contract is explicit). After Descartar finishes one active session, a subsequent `findActiveForUid` would return the next-most-recent if any. With `ref.invalidate`, this means the modal MAY re-fire on the SAME `/home` mount with a different session — extremely unlikely in practice (would require the user to have abandoned two sessions on different devices simultaneously) but technically possible.

Decision: accept the corner case. The modal re-firing is the CORRECT behavior — the user has another active session and we should prompt them. The dedupe guard in the `ref.listen` callback (`if (prev is AsyncData && identical(prev.value, next.value)) return;`) only skips IDENTICAL data, not different records.

---

## 12. Resume route + path (NEW — Decision 12)

### 12.1 The two player routes

Two top-level `GoRoute`s in `lib/app/router.dart`, both OUTSIDE the existing `ShellRoute`:

```dart
// Route 1 — Fresh session
GoRoute(
  path: '/workout/session/:routineId/:dayNumber',
  redirect: authRedirect,
  pageBuilder: (context, state) {
    final routineId = state.pathParameters['routineId']!;
    final dayNumber = int.tryParse(state.pathParameters['dayNumber']!);
    if (dayNumber == null) {
      return _noAnim(Scaffold(
        body: Center(child: Text(
          'Ruta inválida: dayNumber=${state.pathParameters['dayNumber']}',
        )),
      ));
    }
    return _noAnim(Scaffold(
      body: SessionPlayerScreen(
        init: FreshSession(routineId: routineId, dayNumber: dayNumber),
      ),
    ));
  },
),

// Route 2 — Resume existing session
GoRoute(
  path: '/workout/session/resume/:sessionId',
  redirect: authRedirect,
  pageBuilder: (context, state) {
    final sessionId = state.pathParameters['sessionId']!;
    return _noAnim(Scaffold(
      body: SessionPlayerScreen(
        init: ResumeSession(sessionId: sessionId),
      ),
    ));
  },
),

// Route 3 — Summary stub (unchanged)
GoRoute(
  path: '/workout/session-summary/:sessionId',
  redirect: authRedirect,
  pageBuilder: (context, state) {
    final palette = AppPalette.of(context);
    return _noAnim(Scaffold(
      backgroundColor: palette.bg,
      body: Center(
        child: Text(
          'Resumen — próximamente',
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
        ),
      ),
    ));
  },
),
```

All three routes:
- OUTSIDE the `ShellRoute` (no bottom nav).
- Auth-gated via `authRedirect`.
- Use `_noAnim` page builder (consistent with the rest of the app — see `home-wire-routines` precedent).

### 12.2 Constructor choice: single screen with `init: SessionInit`

**Decision**: Single `SessionPlayerScreen` widget with ONE constructor parameter `init: SessionInit`. The route builders construct the appropriate subclass.

**Rejected alternative**: Two factory constructors on a single screen — `SessionPlayerScreen.fresh(routineId, dayNumber)` and `SessionPlayerScreen.resume(sessionId)`. Each factory would construct the appropriate `SessionInit` internally.

  - This would work and is slightly more discoverable at call sites (`SessionPlayerScreen.fresh(...)` reads better than `SessionPlayerScreen(init: FreshSession(...))`).
  - Con: requires two `final` fields on the widget (one nullable for fresh, one nullable for resume) OR a single `SessionInit init` field with two factory constructors that build it. The latter is just sugar over the chosen design with extra code. The former requires a `late` field with an assert in the constructor.
  - Net: one extra abstraction for marginal readability gain. NOT chosen.

**Rejected alternative**: Two separate screens — `SessionPlayerScreen` (fresh) and `ResumeSessionPlayerScreen` (resume). Both delegate to a shared `_SessionPlayerBody` widget.

  - This is what the spec hints at: "Design phase decides whether this is a separate widget or a constructor parameter on `SessionPlayerScreen`". The spec also names `ResumeSessionPlayerScreen` in the route 2 example.
  - Con: 60+ LOC of duplicated screen scaffolding (PopScope, SafeArea, Column, ListView, the entire build method) for no behavioral difference past the notifier read. The shared body widget either takes a `SessionInit` param (defeating the point of separation) or takes an `AsyncValue<SessionState>` directly (couples it to provider plumbing).
  - Net: more code, no real benefit. The spec's mention of `ResumeSessionPlayerScreen` is one option, NOT a lock. NOT chosen.

**Adjustment to spec language**: The spec REQ-SESSION-ROUTE-001 (Route 2) names `ResumeSessionPlayerScreen` in its example builder. The design supersedes this by using `SessionPlayerScreen(init: ResumeSession(...))` — the route builder maps the `:sessionId` path param to a `ResumeSession` subclass. SCENARIO-335 ("the resume notifier was initialized with `sessionId: 'sess-42'`") is satisfied by the screen passing `widget.init` to `sessionNotifierProvider(widget.init)` and the notifier's `_buildResume(arg.sessionId)` consuming it.

If a verification phase challenges this, the apply phase has the latitude to introduce a thin `ResumeSessionPlayerScreen` wrapper that just builds `SessionPlayerScreen(init: ResumeSession(...))`. Documented as a fallback only — primary path is single screen.

### 12.3 Why two routes, not one with a query param

Considered: `/workout/session/:routineId/:dayNumber?resumeId=sess-42` — single route with optional resume id.

Cons:
- GoRouter path params are positional; query params are NOT typed and require manual parsing.
- The semantics are different enough (fresh = create, resume = lookup) that conflating them under one route hurts readability.
- The auth-gate is identical so there's no benefit there either.

Decision: two distinct routes. Apply phase locked.

---

## 13. ADR-style decision log

Decisions surfaced specifically by this design phase (beyond the 12 locked in propose.md):

### ADR-SP-1 — `FamilyAsyncNotifier`, not `AsyncNotifier.family`

**Decision**: Use `FamilyAsyncNotifier<SessionState, SessionInit>` as the base class.
**Rationale**: Riverpod 2.x ships `AsyncNotifier` (parameterless) and `FamilyAsyncNotifier` (parameterized). `AsyncNotifierProvider.autoDispose.family<...>` correctly wires the family form.
**Rejected alternative**: `AsyncNotifier<SessionState>` with an explicit `init({required key})` method called from the screen — non-idiomatic, breaks Riverpod's family caching, complicates testing.

### ADR-SP-2 — `Timer.periodic`, not `Stream.periodic`

**Decision**: Use `Timer.periodic` from `dart:async`.
**Rationale**: Lower-level primitive, easier to cancel (`_timer.cancel()` synchronous), no `StreamSubscription` lifecycle to track.
**Rejected alternative**: `Stream<int>.periodic(...)` + `_timerSub = stream.listen(...)` — adds a Stream subscription where a Timer suffices.

### ADR-SP-3 — `isFullyCompleted` as getter, NOT stored field

**Decision**: `SessionState.isFullyCompleted` is a `bool get` computed from `day.slots` + `setLogs` on each access.
**Rationale**: Avoids staleness on `copyWith`. Computation is O(slots × logs) ≤ 400 cmps — trivially fast.
**Rejected alternative**: Store as `final bool isFullyCompleted` + recompute on every `logSet` — risks staleness.

### ADR-SP-4 — `SessionState` carries `RoutineDay`, NOT `Routine`

**Decision**: `SessionState.day` is the only routine reference in the DTO. Screen-level `_SessionHeader` reads `routine.split` separately.
**Rationale**: Day is small and self-contained. The full `Routine` adds bloat.
**Rejected alternative**: Embed `Routine` in `SessionState` — 60% larger DTO, redundant `days` array.

### ADR-SP-5 — `_AbandonConfirmDialog` inline, NOT separate file

**Decision**: Private widget inside `session_player_screen.dart`.
**Rationale**: Single consumer. Pattern matches `_MessageButtonStub` in `public_profile_screen.dart`.

### ADR-SP-6 — `ExerciseRowStatus` enum inline, NOT domain file

**Decision**: Declare `enum ExerciseRowStatus { done, current, pending }` at file scope of `session_player_screen.dart`.
**Rationale**: Single consumer. Pattern matches `_ProfileTab` in `public_profile_screen.dart`.

### ADR-SP-7 — `context.go`, NOT `context.push`, after abandon/finish

**Decision**: Navigate to summary stub via `context.go('/workout/session-summary/$sessionId')`.
**Rationale**: Clears the player from the navigation stack so the user cannot back into a finalized session.
**Rejected alternative**: `context.push` — leaves finalized state reachable via back.

### ADR-SP-8 — `context.push` from inside ShellRoute to top-level

**Decision**: From `RoutineDetailScreen` → `context.push('/workout/session/$id/$day')`.
**Rationale**: Renders ABOVE the shell (no bottom nav).
**Risk**: SCENARIO-312 mitigates. Fallback: `go` if QA observes issues.

### ADR-SP-9 — `SetLog.id` repo-generated

**Decision**: Screen constructs `SetLog(id: '', ...)`; repo overwrites with Firestore-generated id.
**Rationale**: Mirrors `FriendshipRepository.request` pattern.
**Risk**: Contract assumption on Etapa 1 implementation.

### ADR-SP-10 — `gymNameFromId` cross-feature import

**Decision**: `_AttendanceCard` imports from `lib/features/feed/domain/gym_name.dart`.
**Rationale**: Value-only helper, pure function. Spec cross-ref fix #5 approves.
**Follow-up**: Move to `lib/core/domain/` if a third feature consumes.

### ADR-SP-11 — Sealed `SessionInit`, single notifier (NEW — Decision 12)

**Decision**: Use a `sealed class SessionInit` with `FreshSession` and `ResumeSession` subclasses as the family key. ONE `SessionNotifier` dispatches via exhaustive `switch` in `build()`.
**Rationale**:
- Single source of truth for `logSet`/`abandonSession`/`finishSession`/timer — no duplication.
- Exhaustive `switch` is compile-time checked.
- The screen passes `init` opaquely — knows nothing about which subclass it holds.
- Riverpod family caching works correctly because both subclasses implement value-based `==`/`hashCode`.
**Rejected alternatives**:
- **Two separate notifiers** (`freshSessionNotifierProvider`, `resumeSessionNotifierProvider`): ~80 LOC duplicated. The screen would have to branch on which provider to watch, infecting state-routing code.
- **Record key with nullable fields**: no exhaustive `switch`, runtime assertions only. Loses Dart 3's sealed-class compile-time guarantees.
**Risk**: If Riverpod's family cache has any quirk with sealed-class keys (it shouldn't — it uses `==`), the test suite will surface it via SCENARIO-269. Apply phase MUST validate by constructing two `FreshSession(r1, 1)` and asserting they map to the same provider instance.

### ADR-SP-12 — `ResumeSessionModal` is a separate file, NOT inline (NEW — Decision 12)

**Decision**: `ResumeSessionModal` lives in `lib/features/workout/presentation/widgets/resume_session_modal.dart` as a PUBLIC widget.
**Rationale**:
- Two consumers: `HomeScreen` (via post-frame callback) AND its own widget tests.
- Cross-feature consumption: HomeScreen lives in `features/home/`; the widget lives in `features/workout/`. Inlining it in `home_screen.dart` would require workout-feature knowledge (Session/SetLog imports) to leak into home.
- Public exposure is cleaner than `home_screen.dart` re-exporting a private workout-feature widget.
**Rejected alternative**: Inline as `_ResumeSessionPrompt` private widget in `home_screen.dart`. Cons: forces `home_screen.dart` to import `Session` from workout domain — feature-coupling worse than the explicit cross-feature widget import.

### ADR-SP-13 — `ref.listen` + `addPostFrameCallback`, NOT `ref.watch` for resume trigger (NEW — Decision 12)

**Decision**: `HomeScreen` uses `ref.listen<AsyncValue<...>>(activeSessionForUidProvider, callback)` to detect non-null data, then schedules `showDialog` via `WidgetsBinding.instance.addPostFrameCallback`.
**Rationale**:
- `ref.watch` would rebuild `HomeScreen` on every state change of the provider, which is unnecessary — the home content is independent of the resume check.
- `showDialog` cannot be called from within `build` (it pushes a route → rebuilds → infinite loop). The post-frame callback defers it cleanly.
- Dedupe guard (`identical(prev.value, next.value)`) prevents re-shows on unrelated emissions.
**Rejected alternatives**:
- `ref.watch` + a wrapper widget that calls `showDialog` in `didUpdateWidget`: ~30 LOC of stateful widget for what `ref.listen` does in 8 LOC.
- `StatefulWidget` with `initState` calling `ref.read` and `showDialog`: ignores async lifecycle, fires before `activeSessionForUidProvider` has data, requires manual `Future` chaining.

### ADR-SP-14 — Discard callback owns `repo.finish`, NOT notifier (NEW — Decision 12)

**Decision**: The Descartar callback in `HomeScreen` (`_onResumeDiscard`) calls `repo.finish(wasFullyCompleted: false)` directly. The `SessionNotifier` is NOT instantiated for the discard path.
**Rationale**:
- The notifier's purpose is to drive the PLAYER screen. Instantiating it just to call `abandonSession` would:
  1. Trigger `_buildResume` (loads routine + day + starts timer) for nothing.
  2. Force the home screen to mount the player or somehow scope a ProviderContainer to access the notifier.
- The repo call is the only side effect needed; it's a direct call with known parameters (session id, computed totalVolumeKg, computed durationMin).
**Rejected alternative**: Push `/workout/session/resume/:sessionId` and immediately call `abandonSession` from the player. Cons: flashes the player screen for a moment, fires a timer briefly, runs the routine lookup unnecessarily.

### ADR-SP-15 — `currentUidProvider` promoted to public (NEW — Decision 12)

**Decision**: `currentUidProvider` (previously `_currentUidProvider` file-private) is now a public provider in `session_providers.dart`.
**Rationale**: `activeSessionForUidProvider` and `_buildFresh`/`_buildResume` BOTH need uid resolution. Keeping it file-private would force duplication.
**Rejected alternative**: Re-derive uid in each consumer from `authStateChangesProvider.valueOrNull?.uid` — verbose, duplicated, harder to mock.

---

## 14. Open questions / dependencies on Etapa 1

These items MUST be re-validated against Dev A's actual Etapa 1 code:

| # | Item | Verification step |
|---|---|---|
| 1 | `Session` field names exactly match propose.md §Etapa 1 contract | `rg 'class Session' lib/features/workout/domain/session.dart` + field-by-field diff |
| 2 | `SetLog.id` is repo-assigned (pattern b — see ADR-SP-9) | `rg 'logSet' lib/features/workout/data/session_repository.dart` |
| 3 | `SessionRepository.finish` signature matches `Future<Session> finish(String sessionId, {required bool wasFullyCompleted, required double totalVolumeKg, required int durationMin})` | Read the interface |
| 4 | `sessionRepositoryProvider` is overridden in production by Dev A's `FirebaseSessionRepository` wiring | Confirm `sessionRepositoryProvider` is wired in `main.dart` |
| 5 | `Session.startedAt` is `DateTime` (not `Timestamp`) at the Dart layer | Inspect `@TimestampConverter()` |
| 6 | Firestore rules deployed (owner-only R/W on `users/{uid}/sessions/**`) | Verify `firestore.rules` |
| 7 | **`SessionRepository.findActiveForUid` signature matches `Future<({Session session, List<SetLog> setLogs})?> findActiveForUid(String uid)` (Decision 12)** | `rg 'findActiveForUid' lib/features/workout/data/session_repository.dart` + verify return type uses a Dart 3 record exactly as declared in propose §Etapa 1 contract |
| 8 | **`findActiveForUid` returns the LATEST active session when multiple exist (defensive most-recent semantics)** | Inspect implementation — must `orderBy('startedAt', descending: true).limit(1)` or equivalent |
| 9 | **`findActiveForUid` returns `null` (not throws) when no active session exists** | Unit-test or inspect — empty query result MUST map to `null` |

If any item fails verification, the apply phase MUST pause, record the deviation in `apply-progress`, and surface it to the orchestrator for a propose-phase re-run.

---

## 15. Quality gate checklist (pre-PR)

Run before opening PR (REQ-SESSION constraints summary in spec.md):

- [ ] `flutter analyze` — 0 issues (new + pre-existing).
- [ ] `dart format .` — tree clean.
- [ ] `flutter test` — all green; new tests cover SCENARIO-250..338 (89 scenarios).
- [ ] No HEX literals in any new file: `rg '0x[0-9A-Fa-f]{8}' lib/features/workout/{application/session_*,application/session_init.dart,presentation/session_*,presentation/widgets/set_entry_sheet.dart,presentation/widgets/resume_session_modal.dart}` → 0 matches.
- [ ] No `PhosphorIcons.*` direct usage in new widget files.
- [ ] Spacing values in new files limited to `{8, 12, 14, 18, 20}`.
- [ ] `_DisabledCTABar` is fully REMOVED from `routine_detail_screen.dart`.
- [ ] `EMPEZAR` button uses `day.dayNumber` (1-based) NOT `selectedDayIndex` (0-based).
- [ ] Session player routes (fresh + resume) are OUTSIDE the `ShellRoute` block in `router.dart`.
- [ ] `home_screen.dart` listener uses `ref.listen` + post-frame callback (NOT `ref.watch` inside `build`).
- [ ] `ResumeSessionModal` is shown via `showDialog(barrierDismissible: false, ...)`.
- [ ] `_onResumeDiscard` calls `repo.finish(wasFullyCompleted: false)` and `ref.invalidate(activeSessionForUidProvider)`.
- [ ] `_onResumeContinue` calls `context.push('/workout/session/resume/${session.id}')`.
- [ ] `SessionNotifier._buildResume` calls `repo.findActiveForUid` and does NOT call `repo.create` (SCENARIO-318 verifies).
- [ ] `pubspec.yaml` unchanged.
- [ ] `firestore.rules` unchanged (Etapa 1 deliverable).
- [ ] Apply-progress records delivery strategy and any contract-verification deviations from Etapa 1.

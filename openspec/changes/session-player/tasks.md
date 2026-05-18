# Tasks — session-player

**Change**: `session-player`
**Fase / Etapa**: Fase 4 · Etapa 2 — Active workout session player
**Artifact store**: `openspec`
**TDD**: Strict — every (Xa, Xb) pair means: write the test first (Xa, must be RED), then write production code (Xb, must be GREEN). Commit each as a separate work-unit commit.
**Last updated**: 2026-05-18

---

## Pre-apply gating — DO NOT START APPLY UNTIL ALL CHECKED

1. [ ] `feat/session-model-seed` (Etapa 1) merged into main
2. [ ] `Session` model has 9 fields per propose.md §"Etapa 1 contract"
3. [ ] `SetLog` model has 6 fields
4. [ ] `SessionRepository` has 5 required methods including `findActiveForUid(uid) → Future<({Session session, List<SetLog> setLogs})?>` (Decision 12)
5. [ ] Firestore rules deployed for `users/{uid}/sessions/**`
6. [ ] Branch `feat/session-player` rebased onto post-Etapa-1 main
7. [ ] Delivery strategy confirmed (chained PRs)

If ANY fail → STOP. Re-run propose phase. Do not paper over drift.

---

## PR 1 — Logic + Resume infrastructure

Steps 1-10 of the design implementation order. Target branch: `feat/session-player-logic-and-resume`.
Estimated production LOC: ~520. Estimated test LOC: ~720. Total diff: ~1240.
All files under `lib/features/workout/application/` and `lib/features/workout/presentation/widgets/resume_session_modal.dart` plus a single additive modification to `lib/features/home/home_screen.dart`.

---

### TASK-101 — Verify Etapa 1 contract

**REQ refs**: pre-apply gate (propose.md §Pre-apply gating conditions, §Etapa 1 contract)
**Files**: read-only inspection — `lib/features/workout/domain/session.dart`, `lib/features/workout/domain/set_log.dart`, `lib/features/workout/data/session_repository.dart`
**Done when**:
- `Session` has exactly 9 fields matching propose.md (id, uid, routineId, dayNumber, startedAt, finishedAt, wasFullyCompleted, totalVolumeKg, durationMin)
- `SetLog` has exactly 6 fields (id, exerciseId, setNumber, reps, weightKg, completedAt)
- `SessionRepository` exposes: `create`, `logSet`, `finish`, `watchSession`, `findActiveForUid`
- `findActiveForUid` signature is `Future<({Session session, List<SetLog> setLogs})?>` exactly
- If ANY mismatch → STOP apply. File a deviation note and re-run propose before continuing.

**Notes**: This is a verification-only task. No code is written. Do not proceed to TASK-102 if deviations exist.
**Commit suggestion**: none (verification only)

---

### TASK-102a — `SessionState` DTO tests (RED)

**REQ refs**: REQ-SESSION-STATE-001 · SCENARIO-250..255
**Files**: `test/features/workout/application/session_state_test.dart` (new)
**Done when**: test file exists, all 6 scenarios are written, `flutter test` reports compilation errors or test failures (no production file yet)
**Notes**: Pure Dart tests — no Riverpod, no Flutter. Use `stub_factories.dart` (create if missing) for `Session`, `SetLog`, `RoutineDay`, `RoutineSlot` test factories. Verify `isFullyCompleted` truth table (SCENARIO-250..253), `totalVolumeKg` accumulation (SCENARIO-254..255), and `copyWith` immutability (not in spec but implied — add a smoke test).
**Commit suggestion**: `test(session-player): add SessionState DTO tests [RED]`

---

### TASK-102b — `SessionState` DTO implementation (GREEN)

**REQ refs**: REQ-SESSION-STATE-001 · SCENARIO-250..255
**Files**: `lib/features/workout/application/session_state.dart` (new)
**Done when**: `flutter test test/features/workout/application/session_state_test.dart` is green. Class is plain immutable (NOT `@freezed`), has 5 stored fields + 2 derived getters + 3 UI helpers (`setsLoggedFor`, `isExerciseDone`, `completedExerciseCount`) + manual `copyWith` + structural `==`/`hashCode` using `listEquals`.
**Notes**: Use `package:flutter/foundation.dart` for `@immutable` and `listEquals`. Do NOT run `build_runner`. Imports for `Session`, `SetLog`, `RoutineDay` come from Etapa 1 — these must exist after gating check. Design §3.2 is the normative reference.
**Commit suggestion**: `feat(session-player): add SessionState DTO with derived getters`

---

### TASK-103a — `SessionInit` sealed class tests (RED)

**REQ refs**: REQ-SESSION-NOTIFIER-001 (family key) · design §3.1
**Files**: `test/features/workout/application/session_init_test.dart` (new)
**Done when**: tests for equality, hashCode, and exhaustive pattern matching on `FreshSession` and `ResumeSession` are written and fail (no production file)
**Notes**: Test that two `FreshSession(routineId: 'r1', dayNumber: 1)` instances are `==`. Test that `FreshSession` and `ResumeSession` are NOT `==`. Test that a `switch` on `SessionInit` must cover both cases (compile-time — add a `final _` exhaustive switch test). Approximately 3-4 test cases, ~50 LOC.
**Commit suggestion**: `test(session-player): add SessionInit sealed class tests [RED]`

---

### TASK-103b — `SessionInit` sealed class implementation (GREEN)

**REQ refs**: REQ-SESSION-NOTIFIER-001 · design §3.1
**Files**: `lib/features/workout/application/session_init.dart` (new)
**Done when**: `flutter test test/features/workout/application/session_init_test.dart` is green. File exports `sealed class SessionInit`, `final class FreshSession` (fields: `routineId`, `dayNumber`; manual `==`/`hashCode`), `final class ResumeSession` (field: `sessionId`; manual `==`/`hashCode`). Annotated `@immutable`. No external deps beyond `package:flutter/foundation.dart`.
**Notes**: Design §3.1 contains the normative code shape verbatim. Follow it exactly — including `Object.hash(routineId, dayNumber)` for `FreshSession.hashCode`.
**Commit suggestion**: `feat(session-player): add SessionInit sealed family key`

---

### TASK-104a — Provider shells tests (RED)

**REQ refs**: REQ-SESSION-PROVIDERS-001 · REQ-SESSION-RESUME-001 · SCENARIO-269, 322..324
**Files**: `test/features/workout/application/session_providers_test.dart` (new)
**Done when**: four test groups written and failing — (1) `sessionRepositoryProvider` throws `UnimplementedError` when not overridden; (2) `sessionNotifierProvider` family key uniqueness by `SessionInit` subtype (SCENARIO-269 with `FreshSession` vs `ResumeSession` keys); (3) `activeSessionForUidProvider` returns non-null record when repo returns one (SCENARIO-322); (4) `activeSessionForUidProvider` returns `null` and skips repo when uid is null (SCENARIO-324).
**Notes**: All tests use `ProviderContainer`. Mock `SessionRepository` with `mocktail`. Override `authStateChangesProvider` to control `currentUidProvider`.
**Commit suggestion**: `test(session-player): add session providers tests [RED]`

---

### TASK-104b — Provider shells implementation (GREEN)

**REQ refs**: REQ-SESSION-PROVIDERS-001 · REQ-SESSION-RESUME-001 · SCENARIO-269, 322..324
**Files**: `lib/features/workout/application/session_providers.dart` (new)
**Done when**: `flutter test test/features/workout/application/session_providers_test.dart` is green. File declares exactly: `sessionRepositoryProvider` (throws `UnimplementedError` by default, with comment `// Etapa 1 — implementation injected here when feat/session-model-seed merges.`), `currentUidProvider` (reads `authStateChangesProvider`), `sessionNotifierProvider` (`.autoDispose.family<SessionNotifier, SessionState, SessionInit>`), `activeSessionForUidProvider` (`FutureProvider.autoDispose`, auth-gated).
**Notes**: Design §4 is the normative reference for the full file. `SessionNotifier` class is referenced but not yet complete — the import will compile once TASK-105b adds the file. Order declaration imports carefully to avoid circular references. Use `AsyncNotifierProvider.autoDispose.family` (NOT `.family.autoDispose`).
**Commit suggestion**: `feat(session-player): add session providers (repo + uid + notifier + activeSession)`

---

### TASK-105a — `SessionNotifier` Path A (fresh) tests (RED)

**REQ refs**: REQ-SESSION-NOTIFIER-001 (Path A) · SCENARIO-256..258
**Files**: `test/features/workout/application/session_notifier_test.dart` (new, partial — Path A group only)
**Done when**: three tests written and failing — `repo.create` called once (SCENARIO-256), initial state has `setLogs: []` and `currentExerciseIndex: 0` (SCENARIO-257), `ref.onDispose` cancels the timer (SCENARIO-258 — use `fake_async` or a recorded fake stream).
**Notes**: Use `ProviderContainer` with `mocktail` mocks for `SessionRepository`, `routineByIdProvider`, `authStateChangesProvider`. Stub `routineByIdProvider(routineId)` via `FutureProvider` override returning a `Routine` with a matching day. Create `MockSessionRepository` that records calls.
**Commit suggestion**: `test(session-player): add SessionNotifier.build(FreshSession) tests [RED]`

---

### TASK-105b — `SessionNotifier` Path A implementation (GREEN)

**REQ refs**: REQ-SESSION-NOTIFIER-001 (Path A) · SCENARIO-256..258
**Files**: `lib/features/workout/application/session_notifier.dart` (new, Path A only initially)
**Done when**: `flutter test ... session_notifier_test.dart` (Path A group) is green. Class extends `FamilyAsyncNotifier<SessionState, SessionInit>`. `build(SessionInit arg)` does a `switch` on `arg` — `FreshSession` branch calls `_buildFresh`. `_buildFresh` reads `routineByIdProvider`, looks up `day`, calls `repo.create`, starts `Timer.periodic`, registers `ref.onDispose`. Returns `SessionState` with empty logs and index 0. `ResumeSession` branch throws `UnimplementedError` (stub until TASK-106b).
**Notes**: `Timer.periodic` from `dart:async` — no pubspec change. `_timer` is `Timer?`. `_finalized` is `bool` initialized to `false`. Design §3.3 is the normative reference for the full class.
**Commit suggestion**: `feat(session-player): SessionNotifier.build(FreshSession) creates session and starts timer`

---

### TASK-106a — `SessionNotifier` Path B (resume) tests (RED)

**REQ refs**: REQ-SESSION-NOTIFIER-001 (Path B) · SCENARIO-318..321
**Files**: `test/features/workout/application/session_notifier_test.dart` (extend — add Path B group)
**Done when**: four tests written and failing — `repo.create` NOT called (SCENARIO-318), `setLogs` restored (SCENARIO-319), `currentExerciseIndex` recomputed (SCENARIO-320), `elapsedSeconds` approximate from `startedAt` (SCENARIO-321 ± 2s tolerance).
**Notes**: Stub `repo.findActiveForUid(uid)` to return a record with a known `Session` (set `startedAt` to `DateTime.now().subtract(const Duration(minutes: 5))` for SCENARIO-321) and a `List<SetLog>`. Verify `repo.create` was never called using `verifyNever(mockRepo.create(...))`.
**Commit suggestion**: `test(session-player): add SessionNotifier.build(ResumeSession) tests [RED]`

---

### TASK-106b — `SessionNotifier` Path B implementation (GREEN)

**REQ refs**: REQ-SESSION-NOTIFIER-001 (Path B) · SCENARIO-318..321
**Files**: `lib/features/workout/application/session_notifier.dart` (extend — add `_buildResume`)
**Done when**: `flutter test ... session_notifier_test.dart` (Path B group) is green. `_buildResume` calls `repo.findActiveForUid(uid)`, throws `StateError` if null, verifies `session.id == sessionId`, looks up `Routine` + `RoutineDay`, calls `_nextIncompleteIndex`, computes elapsed from `session.startedAt`, wraps logs in `List<SetLog>.unmodifiable`. Timer starts after `switch` (single start point for both paths).
**Notes**: `_nextIncompleteIndex` and `_durationMin` are private helpers — add them now if not already present. See design §3.3 for their implementation.
**Commit suggestion**: `feat(session-player): SessionNotifier.build(ResumeSession) restores from findActiveForUid`

---

### TASK-107a — `SessionNotifier` mutation methods tests (RED)

**REQ refs**: REQ-SESSION-NOTIFIER-002, 003, 004 · SCENARIO-259..268
**Files**: `test/features/workout/application/session_notifier_test.dart` (extend — add logSet, abandon, finish groups)
**Done when**: 10 tests written and failing covering `logSet` (SCENARIO-259..264), `abandonSession` (SCENARIO-265..266), `finishSession` (SCENARIO-267..268).
**Notes**: Each group initializes the notifier via Path A (mock `repo.create`). For `finishSession` error case (SCENARIO-268), wrap the call in `expectAsync` or verify `throwsStateError`.
**Commit suggestion**: `test(session-player): add SessionNotifier mutation tests (logSet/abandon/finish) [RED]`

---

### TASK-107b — `SessionNotifier` mutation methods implementation (GREEN)

**REQ refs**: REQ-SESSION-NOTIFIER-002, 003, 004 · SCENARIO-259..268
**Files**: `lib/features/workout/application/session_notifier.dart` (extend — add `logSet`, `abandonSession`, `finishSession`)
**Done when**: all three mutation-group tests are green. `logSet` appends immutably, calls `repo.logSet`, advances `currentExerciseIndex` via `_nextIncompleteIndex`. `abandonSession` calls `_finalize()` then `repo.finish(wasFullyCompleted: false)`. `finishSession` throws `StateError` when `!isFullyCompleted`, then calls `repo.finish(wasFullyCompleted: true)`. `_finalize` sets `_finalized = true`, cancels `_timer`.
**Notes**: `_onTick` checks `_finalized` flag — no ticks after finalize. `_durationMin` formula: `if (elapsed <= 0) return 1; return (elapsed + 59) ~/ 60`. Both `abandon` and `finish` guard `if (_finalized) return;` at the top.
**Commit suggestion**: `feat(session-player): SessionNotifier.logSet/abandonSession/finishSession`

---

### TASK-108a — `ResumeSessionModal` widget tests (RED)

**REQ refs**: REQ-SESSION-RESUME-003 · SCENARIO-329..333
**Files**: `test/features/workout/presentation/widgets/resume_session_modal_test.dart` (new)
**Done when**: 5 tests written and failing — title renders (SCENARIO-329), `startedAt` formatted as `HH:MM` (SCENARIO-330), `onContinue` callback (SCENARIO-331), `onDiscard` callback (SCENARIO-332), both buttons present (SCENARIO-333).
**Notes**: Use `_wrap(Widget)` helper. The modal is a pure `StatelessWidget` — no provider overrides needed. For SCENARIO-330, construct a `Session` stub with `startedAt: DateTime(2026, 5, 18, 18, 42)` and verify `find.textContaining('18:42')`.
**Commit suggestion**: `test(session-player): add ResumeSessionModal widget tests [RED]`

---

### TASK-108b — `ResumeSessionModal` widget implementation (GREEN)

**REQ refs**: REQ-SESSION-RESUME-003 · SCENARIO-329..333
**Files**: `lib/features/workout/presentation/widgets/resume_session_modal.dart` (new)
**Done when**: `flutter test ... resume_session_modal_test.dart` is green. Widget is `StatelessWidget`. Renders `AlertDialog` with `backgroundColor: palette.bgCard`, title `'Entrenamiento en curso'`, body containing `session.startedAt` formatted via `_formatHHMM` (file-private helper), `'Continuar'` `ElevatedButton` calling `onContinue`, `'Descartar'` `OutlinedButton` calling `onDiscard`. Colors: Continuar bg = `palette.accent`; Descartar border + label = `palette.highlight`.
**Notes**: `_formatHHMM` is file-private, NOT shared with `_formatMMSS` in the player screen — different concern. Token table: design §8. Do NOT use HEX literals. Do NOT use `PhosphorIcons.*` directly.
**Commit suggestion**: `feat(session-player): add ResumeSessionModal widget`

---

### TASK-109a — `HomeScreen` resume listener tests (RED)

**REQ refs**: REQ-SESSION-RESUME-002 · SCENARIO-325..328
**Files**: `test/features/home/home_screen_test.dart` (modify — add resume listener group, additive only)
**Done when**: 4 tests written and failing — modal appears when provider returns non-null (SCENARIO-325), modal absent when null (SCENARIO-326), home renders normally when loading (SCENARIO-327), home renders normally on error (SCENARIO-328).
**Notes**: Override `activeSessionForUidProvider` in `_wrapProvider`. For SCENARIO-325 use `AsyncData(({session: stubSession, setLogs: <SetLog>[]}))`. The modal appears via `showDialog` triggered by `ref.listen` + `addPostFrameCallback` — test must call `pumpAndSettle()` after pump to allow the post-frame callback to fire. Do NOT import `ResumeSessionModal` test details into the home test — check for `find.text('Entrenamiento en curso')` instead.
**Commit suggestion**: `test(home): add resume listener tests on HomeScreen [RED]`

---

### TASK-109b — `HomeScreen` resume listener implementation (GREEN)

**REQ refs**: REQ-SESSION-RESUME-002 · SCENARIO-325..328
**Files**: `lib/features/home/home_screen.dart` (modify — additive only)
**Done when**: all 4 resume-listener tests are green. Changes are ADDITIVE only — no existing widgets or structure modified. Adds `ref.listen<AsyncValue<...>>(activeSessionForUidProvider, ...)` at the top of `build`. Listener calls `_maybeShowResumePrompt` (file-scope function) which uses `addPostFrameCallback` to show `ResumeSessionModal` via `showDialog(barrierDismissible: false, ...)`. `onContinue` calls `Navigator.of(dialogCtx, rootNavigator: true).pop()` then `context.push('/workout/session/resume/${session.id}')`. `onDiscard` awaits `repo.finish(...)`, then pops the dialog, then invalidates `activeSessionForUidProvider`.
**Notes**: File lives at `lib/features/home/home_screen.dart` — NOT `lib/features/home/presentation/home_screen.dart`. The design §11.2 contains the normative `_maybeShowResumePrompt` snippet. Duplicate-fire guard: `if (prev is AsyncData && identical(prev.value, next.value)) return;`.
**Commit suggestion**: `feat(home): show ResumeSessionModal on active session via post-frame listener`

---

### TASK-110 — PR 1 quality gates

**REQ refs**: REQ-SESSION-THEME-001 (no HEX, no PhosphorIcons direct)
**Files**: no new files
**Done when**:
- `flutter analyze` reports 0 issues
- `dart format . --set-exit-if-changed` exits 0
- `flutter test test/features/workout/application/ test/features/home/home_screen_test.dart test/features/workout/presentation/widgets/resume_session_modal_test.dart` all green
- Manual smoke (only if Etapa 1 is in main + app has a seeded active session in Firestore): launch app, navigate to `/home`, verify `ResumeSessionModal` appears
- No commit — gate only

**Notes**: If `TreinoIcon.checkCircle`, `TreinoIcon.checkCircleFill`, or `TreinoIcon.gym` are missing from `lib/core/widgets/treino_icon.dart`, add them before this gate. This is also the moment to catch any import drift from Etapa 1 model shapes.
**Commit suggestion**: none (gate only)

---

## PR 2 — UI complete

Steps 11-14 of the design implementation order. Target branch: `feat/session-player-ui` (stacked on `feat/session-player-logic-and-resume` — rebase after PR 1 merges).
Estimated production LOC: ~315. Estimated test LOC: ~570. Total diff: ~885.
All new UI files under `lib/features/workout/presentation/` plus modifications to `lib/app/router.dart` and `lib/features/workout/presentation/routine_detail_screen.dart`.

---

### TASK-201 — Verify PR 1 is merged and callable

**REQ refs**: design §10 step 0 (continuation gate)
**Files**: read-only
**Done when**: `lib/features/workout/application/session_providers.dart` imports compile without errors (especially `activeSessionForUidProvider`) AND `lib/features/workout/presentation/widgets/resume_session_modal.dart` exists.
**Notes**: No code written. Re-check `TreinoIcon` constants from TASK-110. Rebase `feat/session-player-ui` onto merged `feat/session-player-logic-and-resume` before starting.
**Commit suggestion**: none (verification only)

---

### TASK-202a — `_SessionHeader` private widget tests (RED)

**REQ refs**: REQ-SESSION-SCREEN-002 · SCENARIO-274..276
**Files**: `test/features/workout/presentation/session_player_screen_test.dart` (new, `_SessionHeader` group)
**Done when**: 3 tests written and failing — title format `'PUSH · DÍA 4'` (SCENARIO-274), ABANDONAR button present (SCENARIO-275), ABANDONAR callback fires on tap (SCENARIO-276).
**Notes**: `_SessionHeader` is private — tests pump it by creating a thin public test-helper wrapper OR by pumping `SessionPlayerScreen` with a data override and finding the header's rendered text. Prefer the latter to stay consistent with spec test helper conventions (`_wrapProvider`).
**Commit suggestion**: `test(session-player): add _SessionHeader widget tests [RED]`

---

### TASK-202b — `_SessionHeader` private widget implementation (GREEN)

**REQ refs**: REQ-SESSION-SCREEN-002 · SCENARIO-274..276
**Files**: `lib/features/workout/presentation/session_player_screen.dart` (new, skeleton with `_SessionHeader` only)
**Done when**: `_SessionHeader` tests are green. Widget is `StatelessWidget` with params `routineSplit`, `dayNumber`, `onAbandon`, `onBack`. Title format `'${routineSplit.toUpperCase()} · DÍA $dayNumber'`. ABANDONAR button is an outlined red pill; both back and ABANDONAR invoke the same callback. Colors: design §8. Screen file is a skeleton — `SessionPlayerScreen` class defined but body not yet complete.
**Notes**: Design §2.4.1 is the API contract. Both `onAbandon` and `onBack` params map to the same callback at the call site — keep two named params for clarity.
**Commit suggestion**: `feat(session-player): add _SessionHeader widget`

---

### TASK-203a — `_AttendanceCard` widget tests (RED)

**REQ refs**: REQ-SESSION-SCREEN-003 · SCENARIO-277..278
**Files**: `test/features/workout/presentation/session_player_screen_test.dart` (extend — `_AttendanceCard` group)
**Done when**: 2 tests written and failing — `'Asistencia marcada'` text (SCENARIO-277), `'Sin gimnasio asignado'` when gymId is null (SCENARIO-278).
**Notes**: `_AttendanceCard` is a `ConsumerWidget` — tests need `_wrapProvider` with `userProfileProvider` override. The provider returns a `UserProfile` (from Etapa 1 contract). Keep the time assertion loose (it will be the wall-clock time at test execution — do not assert a specific `HH:MM`).
**Commit suggestion**: `test(session-player): add _AttendanceCard widget tests [RED]`

---

### TASK-203b — `_AttendanceCard` widget implementation (GREEN)

**REQ refs**: REQ-SESSION-SCREEN-003 · SCENARIO-277..278
**Files**: `lib/features/workout/presentation/session_player_screen.dart` (extend — add `_AttendanceCard`)
**Done when**: tests are green. Widget reads `userProfileProvider`, resolves `gymId` via `gymNameFromId` from `lib/features/feed/domain/gym_name.dart`. When no gym, renders `'Sin gimnasio asignado'`. Renders gym icon (`TreinoIcon.gym`), `'Asistencia marcada'` text, current time formatted as `HH:MM` (computed once at build time via `DateTime.now().toLocal()`), check icon at right. Source comment: `// Placeholder: real check-in wired in Etapa 6.`
**Notes**: Design §2.4.2. Import `gymNameFromId` from `lib/features/feed/domain/gym_name.dart`. No HEX, no `PhosphorIcons.*` direct usage.
**Commit suggestion**: `feat(session-player): add _AttendanceCard placeholder widget`

---

### TASK-204a — `_SessionStatsCard` widget tests (RED)

**REQ refs**: REQ-SESSION-SCREEN-004 · SCENARIO-279..282
**Files**: `test/features/workout/presentation/session_player_screen_test.dart` (extend — `_SessionStatsCard` group)
**Done when**: 4 tests written and failing — `'SESIÓN ACTIVA'` label (SCENARIO-279), `'00:00'` timer at 0 seconds (SCENARIO-280), `'01:03'` timer at 63 seconds (SCENARIO-281), progress text with correct exercise counts (SCENARIO-282).
**Notes**: Widget is `StatelessWidget` receiving `SessionState state`. Tests pump it directly via `_wrap`. Use stub `SessionState` with controlled `elapsedSeconds` and `day.slots` counts.
**Commit suggestion**: `test(session-player): add _SessionStatsCard widget tests [RED]`

---

### TASK-204b — `_SessionStatsCard` widget implementation (GREEN)

**REQ refs**: REQ-SESSION-SCREEN-004 · SCENARIO-279..282
**Files**: `lib/features/workout/presentation/session_player_screen.dart` (extend — add `_SessionStatsCard`, `_formatMMSS`)
**Done when**: tests are green. Renders `'SESIÓN ACTIVA'` label (`palette.accent`, Barlow Condensed 700 12), progress text `'X / Y ejercicios · Z kg vol.'`, elapsed timer `_formatMMSS(state.elapsedSeconds)`, `LinearProgressIndicator(value: completedCount / totalCount)`. `_formatMMSS` is a file-scope helper: pads mm and ss to 2 digits.
**Notes**: Design §2.4.3 and §9.4 for the exact tree and formatter. `Z kg vol.` format: `state.totalVolumeKg.toStringAsFixed(1)` or integer when `.0` — design says "implementation decides format"; use `toStringAsFixed(1)` for consistency.
**Commit suggestion**: `feat(session-player): add _SessionStatsCard with live timer and progress`

---

### TASK-205a — `_ExerciseListRow` widget tests (RED)

**REQ refs**: REQ-SESSION-SCREEN-005 · SCENARIO-283..286
**Files**: `test/features/workout/presentation/session_player_screen_test.dart` (extend — `_ExerciseListRow` group)
**Done when**: 4 tests written and failing — done state (strikethrough + check icon, SCENARIO-283), current state (`'Ahora'` badge, SCENARIO-284), pending state (chevron + tap fires callback, SCENARIO-285), done state is not tappable (SCENARIO-286).
**Notes**: Also declare `ExerciseRowStatus` enum (inline in `session_player_screen.dart`, file-scope). Tests pump the private widget indirectly via the screen with a controlled state, OR test helpers expose it. If private, pump `SessionPlayerScreen` with `AsyncData(state)` overrides and inspect the rendered exercise rows.
**Commit suggestion**: `test(session-player): add _ExerciseListRow widget tests [RED]`

---

### TASK-205b — `_ExerciseListRow` widget implementation (GREEN)

**REQ refs**: REQ-SESSION-SCREEN-005 · SCENARIO-283..286
**Files**: `lib/features/workout/presentation/session_player_screen.dart` (extend — add `ExerciseRowStatus` enum and `_ExerciseListRow`)
**Done when**: tests are green. `ExerciseRowStatus` enum declared at file scope: `done`, `current`, `pending`. Widget renders: done → `TreinoIcon.checkCircleFill` + strikethrough name + `onTap: null`; current → empty circle (accent border) + bold name + `'Ahora'` pill + `onTap` wired; pending → empty circle + default name + `TreinoIcon.chevronRight` + `onTap` wired. Subtitle always shows `'${slot.targetSets} × ...'` from slot fields.
**Notes**: Design §2.4.4. `onTap: null` for done rows prevents accidental interaction. Token table: design §8.
**Commit suggestion**: `feat(session-player): add _ExerciseListRow with 3 visual states`

---

### TASK-206a — `_TerminarSessionButton` widget tests (RED)

**REQ refs**: REQ-SESSION-SCREEN-006 · SCENARIO-287..290
**Files**: `test/features/workout/presentation/session_player_screen_test.dart` (extend — `_TerminarSessionButton` group)
**Done when**: 4 tests written and failing — enabled style (SCENARIO-287), disabled style with `Opacity(0.4)` (SCENARIO-288), disabled tap no-op (SCENARIO-289), enabled tap calls callback (SCENARIO-290).
**Notes**: Widget accepts `enabled: bool` and `onPressed: VoidCallback?`. Tests can pump it directly if exposed or indirectly via screen. Use `find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0.4)` for SCENARIO-288.
**Commit suggestion**: `test(session-player): add _TerminarSessionButton widget tests [RED]`

---

### TASK-206b — `_TerminarSessionButton` widget implementation (GREEN)

**REQ refs**: REQ-SESSION-SCREEN-006 · SCENARIO-287..290
**Files**: `lib/features/workout/presentation/session_player_screen.dart` (extend — add `_TerminarSessionButton`)
**Done when**: tests are green. Enabled: `palette.accent` bg fill, white label `'TERMINAR SESIÓN'`, full-width pill, `onPressed` wired, `Opacity` wrapper at 1.0 (or no wrapper). Disabled: wrapped in `Opacity(opacity: 0.4)`, `onPressed: null`.
**Notes**: Design §2.4.5. Screen computes `enabled = state.isFullyCompleted` and passes `onPressed: enabled ? _finishSession : null`. No HEX.
**Commit suggestion**: `feat(session-player): add _TerminarSessionButton with enabled/disabled states`

---

### TASK-207a — `_AbandonConfirmDialog` widget tests (RED)

**REQ refs**: REQ-SESSION-DIALOG-001 · SCENARIO-305..307
**Files**: `test/features/workout/presentation/session_player_screen_test.dart` (extend — `_AbandonConfirmDialog` group)
**Done when**: 3 tests written and failing — confirmation text (SCENARIO-305), Cancelar dismisses without callback (SCENARIO-306), Abandonar calls callback and dismisses (SCENARIO-307).
**Notes**: Show the dialog via `showDialog(context: ..., builder: (_) => _AbandonConfirmDialog(onConfirm: ...))` inside the test. Use `pumpAndSettle` to settle the animation. For SCENARIO-306, verify `find.byType(_AbandonConfirmDialog)` is absent after tap.
**Commit suggestion**: `test(session-player): add _AbandonConfirmDialog widget tests [RED]`

---

### TASK-207b — `_AbandonConfirmDialog` widget implementation (GREEN)

**REQ refs**: REQ-SESSION-DIALOG-001 · SCENARIO-305..307
**Files**: `lib/features/workout/presentation/session_player_screen.dart` (extend — add `_AbandonConfirmDialog`)
**Done when**: tests are green. `AlertDialog` with `backgroundColor: palette.bgCard`, `BorderRadius.circular(20)`, body text exactly `'¿Seguro que querés abandonar? Se va a guardar tu progreso hasta acá.'`, `'Cancelar'` outlined button → `Navigator.of(context).pop()`, `'Abandonar'` elevated button with `palette.highlight` bg → `Navigator.of(context).pop(); onConfirm()`.
**Notes**: Design §2.4.6 and §5.4. Locked text — must match exactly (used in SCENARIO-309 system-back test). `palette.highlight` is the magenta token.
**Commit suggestion**: `feat(session-player): add _AbandonConfirmDialog`

---

### TASK-208a — `SetEntrySheet` widget tests (RED)

**REQ refs**: REQ-SESSION-SHEET-001..004 · SCENARIO-291..304
**Files**: `test/features/workout/presentation/widgets/set_entry_sheet_test.dart` (new)
**Done when**: 14 tests written and failing — title uppercase (SCENARIO-291), set progress subtitle (SCENARIO-292), null weight hint (SCENARIO-293), reps default (SCENARIO-294), reps `+` (SCENARIO-295), reps clamp max (SCENARIO-296), reps clamp min (SCENARIO-297), weight default (SCENARIO-298), weight `+` (SCENARIO-299), weight clamp max (SCENARIO-300), weight clamp min (SCENARIO-301), CHECK label (SCENARIO-302), CHECK calls `onCheck` with defaults (SCENARIO-303), CHECK calls `onCheck` after stepper edits (SCENARIO-304).
**Notes**: `SetEntrySheet` is a `StatefulWidget` — tests use `_wrap`. The `_StepperButton` is private; tests tap by finding `find.text('+')` or `find.text('–')`. Disambiguate reps `+` from weight `+` using `find.ancestor` or `find.byWidgetPredicate` if needed.
**Commit suggestion**: `test(session-player): add SetEntrySheet widget tests [RED]`

---

### TASK-208b — `SetEntrySheet` widget implementation (GREEN)

**REQ refs**: REQ-SESSION-SHEET-001..004 · SCENARIO-291..304
**Files**: `lib/features/workout/presentation/widgets/set_entry_sheet.dart` (new)
**Done when**: `flutter test ... set_entry_sheet_test.dart` is green. `SetEntrySheet` is `StatefulWidget`. State holds `_reps` (int, default `slot.targetRepsMin ?? 0`) and `_weight` (double, default `slot.targetWeightKg ?? 0.0`). Private `_StepperButton` widget. Reps clamp `[0..50]`, weight clamp `[0.0..500.0]` step 2.5. CHECK button calls `onCheck(_reps, _weight)` then `Navigator.pop(context)`. Container shape: `palette.bgCard` + `BorderRadius.vertical(top: Radius.circular(20))`.
**Notes**: Design §2.2 and §5.3 for API and tree. onCheck is a pure callback — does NOT reference the notifier. `_formatWeight` helper for displaying weight values. Shown via `showModalBottomSheet(isScrollControlled: true, backgroundColor: Colors.transparent, ...)` — the sheet handles its own bottom padding.
**Commit suggestion**: `feat(session-player): add SetEntrySheet with reps/weight steppers`

---

### TASK-209a — `SessionPlayerScreen` integration tests (RED)

**REQ refs**: REQ-SESSION-SCREEN-001 · REQ-SESSION-NAV-001..002 · SCENARIO-270..290, 305..315
**Files**: `test/features/workout/presentation/session_player_screen_test.dart` (extend — main screen integration groups)
**Done when**: tests covering the 3 async states (SCENARIO-270..273), full tree in data state (SCENARIO-274..290 via the screen), navigation flows (SCENARIO-308..315) are written and failing.
**Notes**: Screen integration tests pump `SessionPlayerScreen(init: FreshSession(...))` and `SessionPlayerScreen(init: ResumeSession(...))` via `_wrapProvider` and `_wrapRouter`. Override `sessionNotifierProvider` with `AsyncData`, `AsyncLoading`, `AsyncError`. Navigation tests use `_wrapRouter` with stub routes. SCENARIO-309 (system back) uses `tester.binding.handlePopRoute()`.
**Commit suggestion**: `test(session-player): add SessionPlayerScreen integration tests [RED]`

---

### TASK-209b — `SessionPlayerScreen` full assembly (GREEN)

**REQ refs**: REQ-SESSION-SCREEN-001 · REQ-SESSION-NAV-001..002 · SCENARIO-270..290, 305..315
**Files**: `lib/features/workout/presentation/session_player_screen.dart` (complete — wire all private widgets into the full screen)
**Done when**: all screen integration tests are green. Screen watches `sessionNotifierProvider(widget.init)`. Three async branches: `AsyncData` → full player tree; `AsyncLoading` → `CircularProgressIndicator(color: palette.accent)`; `AsyncError` → error text `'No pudimos iniciar la sesión.'`. Data branch: `PopScope(canPop: false, onPopInvoked: (_) => _showAbandonConfirm())` > `SafeArea` > `Column` with `_SessionHeader`, `Expanded(ListView([_AttendanceCard, _SessionStatsCard, _ExerciseListRow...]))`, `_TerminarSessionButton`. Opening `SetEntrySheet` via `_openSetEntry` on row tap. Confirm/abandon/finish navigation to `/workout/session-summary/${session.id}` via `context.go(...)` with `mounted` guard.
**Notes**: Design §2.1 and §5.1..5.2 for the normative tree. `PopScope` is ONLY in the data branch — NOT in loading/error. Route builder wraps screen with `Scaffold` — the screen body starts at `PopScope`. Routine lookup for header: design §9.3. `SetEntrySheet` call site: design §5.3 (wrap `slot` with last-log defaults, pass `onCheck` lambda).
**Commit suggestion**: `feat(session-player): assemble SessionPlayerScreen with all private widgets`

---

### TASK-210 — Router additions (3 top-level GoRoutes)

**REQ refs**: REQ-SESSION-ROUTE-001 · SCENARIO-311..312, 334..335
**Files**: `lib/app/router.dart` (modify — add 3 GoRoutes OUTSIDE ShellRoute)
**Done when**: `flutter analyze` is clean, SCENARIO-311 (param parsing), SCENARIO-312 (outside ShellRoute), SCENARIO-334 (resume route push), SCENARIO-335 (sessionId passthrough) are green. Routes: `/workout/session/:routineId/:dayNumber` (fresh — uses `int.tryParse` defensively, passes `FreshSession` init), `/workout/session/resume/:sessionId` (resume — passes `ResumeSession` init), `/workout/session-summary/:sessionId` (stub — `Scaffold(body: Center(child: Text('Resumen — próximamente')))`). All 3 are auth-gated via `authRedirect`.
**Notes**: Design §9.1 contains the normative `pageBuilder` snippets. Use `_noAnim` wrapper (or equivalent) for instant entry. Import `SessionPlayerScreen`, `FreshSession`, `ResumeSession` at the top of `router.dart`. The resume route does NOT parse `sessionId` to `int` — it is a string passthrough.
**Commit suggestion**: `feat(router): add fresh + resume + summary-stub top-level routes`

---

### TASK-211 — Wire `RoutineDetailScreen` EMPEZAR button

**REQ refs**: REQ-SESSION-WIRE-001 · SCENARIO-313..315
**Files**: `lib/features/workout/presentation/routine_detail_screen.dart` (modify — replace `_DisabledCTABar` with `_StartSessionCTABar`)
**Done when**: SCENARIO-313 (EMPEZAR not in Opacity 0.4), SCENARIO-314 (tap pushes correct route with `routine.id`/`day.dayNumber`), SCENARIO-315 (EDITAR stays disabled) are all green. New `_StartSessionCTABar` accepts `routine: Routine` and `day: RoutineDay`. EMPEZAR `onPressed`: `context.push('/workout/session/${routine.id}/${day.dayNumber}')`. EDITAR `onPressed: null`. The `Opacity(0.4)` wrapper that covered BOTH buttons is removed — EDITAR may individually retain an opacity treatment.
**Notes**: `day.dayNumber` (1-based model field) — NOT `selectedDayIndex` (0-based local state). This is the bug SCENARIO-314 verifies. Old `_DisabledCTABar` is deleted entirely from the file. Do not add a new `Scaffold`, `SafeArea`, or `AppBackground`.
**Commit suggestion**: `feat(workout): wire EMPEZAR → SessionPlayer (replace _DisabledCTABar)`

---

### TASK-212 — PR 2 quality gates

**REQ refs**: REQ-SESSION-THEME-001 (no HEX, no direct PhosphorIcons)
**Files**: no new files
**Done when**:
- `flutter analyze` reports 0 issues
- `dart format . --set-exit-if-changed` exits 0
- `flutter test` (full suite) is green — including all session-player tests across both PRs
- Manual smoke (full happy path): tap EMPEZAR on a routine → `SessionPlayerScreen` loads → log a set → `SetEntrySheet` submits → set count increments → all sets done → TERMINAR SESIÓN enabled → tap → `'Resumen — próximamente'` stub renders
- Manual resume smoke (if Etapa 1 seeded): background app, re-open → `ResumeSessionModal` on `/home` → tap Continuar → `SessionPlayerScreen` loads with existing sets

**Notes**: If any test reveals a mismatch between the design's normative code shapes and Etapa 1's actual model (e.g. `SetLog.id` assignment, `repo.logSet` signature), STOP. Document the deviation and escalate before proceeding.
**Commit suggestion**: none (gate only)

---

## Review Workload Forecast

### PR 1 — Logic + Resume infrastructure
- Estimated production LOC: ~520
- Estimated test LOC: ~720
- Total diff: ~1240
- 400-line production budget: HIGH risk (520 > 400)
- Decision: ship as PR 1 with `size:exception` OR split further into PR 1a (logic) + PR 1b (resume). Recommend: ship as single PR 1 with `size:exception`, justified by the work being internally cohesive and untestable end-to-end without all 4 pieces (state + notifier + providers + resume modal + home wire). The resume primitives are lightweight (~150 LOC) but tightly coupled to the provider chain — splitting them would leave the provider shell incomplete.

### PR 2 — UI complete
- Estimated production LOC: ~315
- Estimated test LOC: ~570
- Total diff: ~885
- 400-line production budget: WITHIN budget for production LOC; test LOC pushes total above 400
- Decision: ship as single PR 2. Production LOC is under the 400-line budget. The test LOC is large but unavoidable (14 SetEntrySheet scenarios + 20+ screen scenarios + nav integration = ~570 LOC of test coverage). The reviewer can verify UI separately from the logic already merged in PR 1.

### Cross-PR notes
- PR 2 cannot land before PR 1; `sessionNotifierProvider`, `activeSessionForUidProvider`, `ResumeSessionModal`, and `SessionInit` are all produced by PR 1
- After both merge, `feat/session-player` is fully shipped
- `sdd-archive` runs after PR 2 merges and both manual smokes pass
- Etapa 1 (`feat/session-model-seed`) must merge before EITHER PR is applied — it is the hard dependency for all Firestore operations

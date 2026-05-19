# Tasks: Historial (Fase 4 · Etapa 4)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines — PR-A | ~250 |
| Estimated changed lines — PR-B | ~255 |
| Estimated changed lines — total | ~505 |
| 400-line budget risk — PR-A | Low (within budget) |
| 400-line budget risk — PR-B | Low (within budget) |
| 400-line budget risk — single PR | High |
| Chained PRs recommended | Yes |
| Suggested split | PR-A (`feat/historial-list`) → PR-B (`feat/historial-detail`) |
| Delivery strategy | auto-chain |
| Chain strategy | feature-branch-chain |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Branch | Base | Likely PR | Notes |
|------|------|--------|------|-----------|-------|
| PR-A | `HistorialSection` list + router stub | `feat/historial-list` | `main` | PR 1 | Fully mergeable standalone; detail is explicit stub |
| PR-B | `SessionDetailScreen` + replace stub | `feat/historial-detail` | `feat/historial-list` | PR 2 | Mechanical rebase on PR-A; depends on PR-A merge |

---

## PR-A: HistorialSection (list) — branch `feat/historial-list`

### T01 [A] [CHORE] Branch + directories

- **Files**: none (git/filesystem only)
- **Description**: Checkout `feat/historial-list` from `main`. Create directories `lib/features/workout/presentation/utils/` and `test/features/workout/presentation/utils/` if absent.
- **Acceptance**: `git branch` shows `feat/historial-list`; `flutter test` baseline green.

---

### T02 [A] [RED] Unit tests — `formatSessionDate`

- **Files**: `test/features/workout/presentation/utils/date_helpers_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-379, SCENARIO-380
- **REQs**: REQ-HIST-021
- **Description**: Write 6 failing unit tests (plain `test`, NOT `testWidgets`): (1) canonical mockup example `DateTime(2025, 11, 26)` → `"Mié 26 nov"` (SCENARIO-379); (2–8) all 7 weekday mappings Mon–Sun; (9–20) all 12 month mappings; (21) single-digit day `DateTime(2025, 3, 7)` → `"Vie 7 mar"` (no zero-padding); (22) `now` parameter does not affect output (SCENARIO-380 coverage). File compiles but `formatSessionDate` is undefined → tests fail with `Error`.
- **Acceptance**: `flutter test test/.../date_helpers_test.dart` exits non-zero; 6+ test cases visible in output.

---

### T03 [A] [GREEN] Implement `date_helpers.dart`

- **Files**: `lib/features/workout/presentation/utils/date_helpers.dart` (NEW)
- **REQs**: REQ-HIST-021
- **Description**: Implement `String formatSessionDate(DateTime date, {DateTime? now})` with `const Map<int, String> _kDow` (1..7 → Lun..Dom) and `const Map<int, String> _kMonth` (1..12 → ene..dic). Pure function, no Riverpod, no BuildContext, no `intl`. Returns `'${_kDow[date.weekday]!} ${date.day} ${_kMonth[date.month]!}'`.
- **Acceptance**: `flutter test test/.../date_helpers_test.dart` all green.

---

### T04 [A] [RED] Widget tests — `HistorialSection`

- **Files**: `test/features/workout/presentation/widgets/historial_section_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365
- **REQs**: REQ-HIST-001..008
- **Description**: Write 11 failing widget tests. Define `_pumpHistorialSection({required List<Session> sessions, String uid = 'test-uid'})` helper. Tests: (355) HistorialSection mounts without parameters; (356) two finished sessions render in newest-first order; (357) mixed list renders only finished session; (358) all-unfinished triggers empty state text; (359) card renders routineName + formatted date + kg + min; (360) `wasFullyCompleted: false` shows different indicator than `true`; (361) empty list renders empty message + CTA button; (362) tapping CTA calls `context.go('/workout')`; (363) `AsyncLoading` renders `CircularProgressIndicator`, no cards; (364) `AsyncError` renders error text + retry button; (365) tapping card navigates to `/workout/historial/session-abc`. `HistorialSection` import will not resolve → tests fail.
- **Acceptance**: `flutter test test/.../historial_section_test.dart` exits non-zero; 11 test cases declared.

---

### T05 [A] [GREEN] Implement `historial_section.dart`

- **Files**: `lib/features/workout/presentation/widgets/historial_section.dart` (NEW)
- **REQs**: REQ-HIST-001..008
- **Description**: Implement `HistorialSection extends ConsumerWidget` (no constructor parameters). Private widgets: `_ListLoadingState`, `_ListErrorState({required VoidCallback onRetry})`, `_ListEmptyState`, `_HistorialCard(session)`, `_CompletedIcon(bool wasFullyCompleted)`. Filter `status == SessionStatus.finished` in `.when(data:...)` BEFORE empty check. `ListView.builder` with `shrinkWrap: true` + `NeverScrollableScrollPhysics()`. Heading from `WorkoutStrings.historialHeading`. Tap calls `context.push('/workout/historial/${session.id}')`. Error retry calls `ref.invalidate(sessionsByUidProvider(uid))`.
- **Acceptance**: `flutter test test/.../historial_section_test.dart` all 11 green.

---

### T06 [A] [MOD] `workout_strings.dart` — lista constants

- **Files**: `lib/features/workout/presentation/workout_strings.dart` (MODIFIED)
- **REQs**: REQ-HIST-001, REQ-HIST-005, REQ-HIST-007
- **Description**: Add to `WorkoutStrings`: `historialHeading` (`'HISTORIAL'`), `historialEmptyMessage` (`'Todavía no entrenaste.'`), `historialEmptyCta` (`'Empezar entrenamiento'`), `historialErrorMessage`, `historialErrorRetry`. Add card-level suffixes if not already covered by existing `StatTile` convention: `historialCardKgSuffix` (`' kg'`), `historialCardMinSuffix` (`' min'`).
- **Acceptance**: `historial_section_test.dart` and `historial_section.dart` compile; `flutter analyze` 0 issues on these files.

---

### T07 [A] [RED] Update `workout_screen_test.dart`

- **Files**: `test/features/workout/presentation/workout_screen_test.dart` (MODIFIED)
- **REQs**: REQ-HIST-020
- **Description**: Replace the existing assertion that finds `'Tus entrenamientos completados aparecerán acá.'` with an assertion that finds the heading `'HISTORIAL'` (or `WorkoutStrings.historialHeading`). Override `sessionsByUidProvider` with a deterministic value (empty list is sufficient). Test must fail because `workout_screen.dart` still has `_HistorialSection` with old text.
- **Acceptance**: Running only this test file exits non-zero on the placeholder assertion.

---

### T08 [A] [GREEN] Swap `_HistorialSection` in `workout_screen.dart`

- **Files**: `lib/features/workout/workout_screen.dart` (MODIFIED)
- **REQs**: REQ-HIST-020
- **Description**: Remove private class `_HistorialSection` from `workout_screen.dart`. Add import `package:treino/features/workout/presentation/widgets/historial_section.dart`. Replace the `_HistorialSection()` call site with `const HistorialSection()`.
- **Acceptance**: `flutter test test/.../workout_screen_test.dart` green; `_HistorialSection` absent from file.

---

### T09 [A] [RED] Router test — `/workout/historial/:sessionId` stub

- **Files**: `test/app/router_workout_routes_test.dart` (MODIFIED)
- **SCENARIOs**: SCENARIO-378 (PR-A partial)
- **REQs**: REQ-HIST-019
- **Description**: Add a test SCENARIO: navigate to `/workout/historial/abc123`; assert `find.text('Detalle — próximamente')` is visible; assert `find.byType(TreinoBottomBar)` is absent. Test fails because the route does not exist yet.
- **Acceptance**: New test case exits non-zero before the router change.

---

### T10 [A] [GREEN] Add GoRoute stub in `router.dart`

- **Files**: `lib/app/router.dart` (MODIFIED)
- **REQs**: REQ-HIST-019
- **Description**: Insert new top-level `GoRoute(path: '/workout/historial/:sessionId', pageBuilder: (context, state) => _noAnim(const Center(child: Text('Detalle — próximamente'))))` after line 160 (closing `)` of session-summary route) and before the ShellRoute comment at line 162. No import needed for stub.
- **Acceptance**: `flutter test test/app/router_workout_routes_test.dart` new SCENARIO green; `TreinoBottomBar` assertion passes.

---

### T11 [A] [QA] PR-A quality gate

- **Files**: none (command-only)
- **Description**: Run `flutter analyze` (0 issues required), then `dart format .` (no unformatted files), then `flutter test` (full suite green). BLOCKER — do not open PR-A until all three pass.
- **Acceptance**: All three commands exit 0.

---

## PR-B: SessionDetailScreen + final route — branch `feat/historial-detail`

> PR-B tasks MUST NOT begin until PR-A is merged into `main` and `feat/historial-detail` is branched from `feat/historial-list` (or rebased onto the merged `main`).

---

### T12 [B] [CHORE] Branch from merged PR-A

- **Files**: none
- **Description**: After PR-A merges to `main`: checkout `main`, pull, create `feat/historial-detail` from `main`. Confirm `flutter test` baseline green (PR-A tests pass).
- **Acceptance**: `git log --oneline -1` shows PR-A merge commit; `flutter test` green.

---

### T13 [B] [RED] Widget tests — `SessionDetailScreen`

- **Files**: `test/features/workout/presentation/session_detail_screen_test.dart` (NEW)
- **SCENARIOs**: SCENARIO-366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, 378 (PR-B portion)
- **REQs**: REQ-HIST-009..018
- **Description**: Write failing widget tests. Define `_pumpDetailScreen({Session? session, List<SetLog>? setLogs, bool loading = false, bool error = false})` helper. Tests: (366) `SessionDetailScreen` renders without `TreinoBottomBar` (via router); (367) header shows formatted date, time "10:30", and routineName "Push A"; (368) 4 StatTiles with labels DURACIÓN/SETS/VOLUMEN/PRS HOY and correct values for durationMin=52, setLogs.length=22, totalVolumeKg=3.2, PRS="—"; (369) SETS stat equals `setLogs.length`, not a session field; (370) two exercises render in insertion order, "Press Banca" before "Sentadilla"; (371) single exercise with 3 sets renders exactly one block with 3 rows; (372) set row shows setNumber=2, reps=10, weightKg=80; (373) each set row has a PR badge stub visible; (374) back button pops when route was pushed; (375) not-found state renders "Sesión no encontrada" + CTA; (376) loading state renders `CircularProgressIndicator`, no `StatTile`; (377) error state renders message + retry button. `SessionDetailScreen` import unresolved → all fail.
- **Acceptance**: `flutter test test/.../session_detail_screen_test.dart` exits non-zero; 12+ test cases declared.

---

### T14 [B] [GREEN] Implement `session_detail_screen.dart`

- **Files**: `lib/features/workout/presentation/session_detail_screen.dart` (NEW)
- **REQs**: REQ-HIST-009..018
- **Description**: Implement `SessionDetailScreen extends ConsumerWidget` with `required String sessionId`. Private widgets: `_DetailHeader(session, onBack)`, `_StatRow(session, setLogs)`, `_ExerciseBlock(name, sets)`, `_PrBadgeStub` (no params, renders chip with text "PR"), `_DetailLoadingState`, `_DetailErrorState(onRetry)`, `_DetailNotFoundState`. Not-found guard: `data.session == null → _DetailNotFoundState`. Grouping via `LinkedHashMap<String, List<SetLog>>` populated in iteration order. Back nav: `context.canPop() ? context.pop() : context.go('/workout')`. Time format: `'${h.toString().padLeft(2, "0")}:${m.toString().padLeft(2, "0")}'` inline in `_DetailHeader`. StatTile PRS HOY value: `WorkoutStrings.detailStatPrsStub` (= `'—'`). Full-screen loading (no partial render). Error retry: `ref.invalidate(sessionSummaryProvider((uid: uid, sessionId: sessionId)))`.
- **Acceptance**: `flutter test test/.../session_detail_screen_test.dart` all green.

---

### T15 [B] [MOD] `workout_strings.dart` — detail constants

- **Files**: `lib/features/workout/presentation/workout_strings.dart` (MODIFIED)
- **REQs**: REQ-HIST-010..018
- **Description**: Add to `WorkoutStrings`: `detailNotFoundTitle` (`'Sesión no encontrada'`), `detailNotFoundCta`, `detailErrorMessage`, `detailStatMin` (`'DURACIÓN'`), `detailStatSets` (`'SETS'`), `detailStatKg` (`'VOLUMEN'`), `detailStatPrs` (`'PRS HOY'`), `detailStatPrsStub` (`'—'`), `detailExerciseSetHeader` (`'SET'`), `detailExerciseRepsHeader` (`'REPS'`), `detailExerciseKgHeader` (`'KG'`), `detailPrBadgeLabel` (`'PR'`).
- **Acceptance**: `session_detail_screen.dart` compiles with no inline string literals in build methods.

---

### T16 [B] [RED] Update router test — replace stub assertion

- **Files**: `test/app/router_workout_routes_test.dart` (MODIFIED)
- **SCENARIOs**: SCENARIO-378 (PR-B update), SCENARIO-366
- **REQs**: REQ-HIST-019
- **Description**: Update the SCENARIO added in T09 — change `find.text('Detalle — próximamente')` to `find.byType(SessionDetailScreen)`. Test fails because router still returns the stub.
- **Acceptance**: Updated test exits non-zero before the router change.

---

### T17 [B] [GREEN] Replace stub in `router.dart`

- **Files**: `lib/app/router.dart` (MODIFIED)
- **REQs**: REQ-HIST-019
- **Description**: Replace the stub `_noAnim(const Center(child: Text('Detalle — próximamente')))` with `_noAnim(SessionDetailScreen(sessionId: state.pathParameters['sessionId']!))`. Add import `import '../features/workout/presentation/session_detail_screen.dart';` in alphabetical order among existing workout presentation imports (lines 14–17).
- **Acceptance**: `flutter test test/app/router_workout_routes_test.dart` updated SCENARIO green; `find.byType(SessionDetailScreen)` found.

---

### T18 [B] [QA] PR-B quality gate

- **Files**: none (command-only)
- **Description**: Run `flutter analyze` (0 issues required), then `dart format .` (no unformatted files), then `flutter test` (full suite green). BLOCKER — do not open PR-B until all three pass.
- **Acceptance**: All three commands exit 0.

---

## Goal-Backward Coverage

| REQ | SCENARIO(s) | RED task | GREEN task | Gap |
|-----|-------------|----------|------------|-----|
| REQ-HIST-001 | 355 | T04 | T05 | None |
| REQ-HIST-002 | 356 | T04 | T05 | None |
| REQ-HIST-003 | 357, 358 | T04 | T05 | None |
| REQ-HIST-004 | 359, 360 | T04 | T05 | None |
| REQ-HIST-005 | 361, 362 | T04 | T05 | None |
| REQ-HIST-006 | 363 | T04 | T05 | None |
| REQ-HIST-007 | 364 | T04 | T05 | None |
| REQ-HIST-008 | 365 | T04 | T05 | None |
| REQ-HIST-009 | 366 | T13 | T14 | None |
| REQ-HIST-010 | 367 | T13 | T14 | None |
| REQ-HIST-011 | 368, 369 | T13 | T14 | None |
| REQ-HIST-012 | 370, 371 | T13 | T14 | None |
| REQ-HIST-013 | 372 | T13 | T14 | None |
| REQ-HIST-014 | 373 | T13 | T14 | None |
| REQ-HIST-015 | 374 | T13 | T14 | None |
| REQ-HIST-016 | 375 | T13 | T14 | None |
| REQ-HIST-017 | 376 | T13 | T14 | None |
| REQ-HIST-018 | 377 | T13 | T14 | None |
| REQ-HIST-019 | 378 | T09 (stub) + T16 (real) | T10 + T17 | None |
| REQ-HIST-020 | (covered by 355) | T07 | T08 | None |
| REQ-HIST-021 | 379, 380 | T02 | T03 | None |

All 21 REQs covered. All SCENARIOs 355–380 land in a specific test task. No orphan SCENARIOs found.

---

## Task Summary

| Section | Tasks | Focus |
|---------|-------|-------|
| PR-A — CHORE | T01 | Branch + dirs |
| PR-A — RED/GREEN (date helper) | T02–T03 | `formatSessionDate` unit test cycle |
| PR-A — RED/GREEN (widget) | T04–T05 | `HistorialSection` widget test cycle |
| PR-A — MOD | T06 | `workout_strings.dart` lista constants |
| PR-A — RED/GREEN (workout screen) | T07–T08 | `WorkoutScreen` placeholder swap |
| PR-A — RED/GREEN (router stub) | T09–T10 | GoRoute stub + router test |
| PR-A — QA | T11 | analyze + format + full suite |
| **PR-A total** | **11** | |
| PR-B — CHORE | T12 | Branch from merged PR-A |
| PR-B — RED/GREEN (detail screen) | T13–T14 | `SessionDetailScreen` widget test cycle |
| PR-B — MOD | T15 | `workout_strings.dart` detail constants |
| PR-B — RED/GREEN (router final) | T16–T17 | Replace stub + router test update |
| PR-B — QA | T18 | analyze + format + full suite |
| **PR-B total** | **7** | |
| **Grand total** | **18** | |

Execution order within each PR: strictly sequential — each RED must be observed failing before its GREEN, each GREEN confirmed passing before the next RED.

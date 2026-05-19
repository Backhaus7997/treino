# Tasks: Post-Workout Summary (Fase 4 · Etapa 3)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~280–340 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | exception-ok |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | All 33 tasks | PR 1 | Single PR to `main`; ~280–340 LOC |

---

## Phase 1: Setup

- [ ] T01 [CHORE] Confirm `feat/post-workout-summary` branch is checked out and `flutter test` baseline is green. (size: S)
- [ ] T02 [CHORE] Create `lib/features/workout/presentation/workout_strings.dart` — `abstract final class WorkoutStrings` with `static const postAutoCompleteText`. No RED test needed (pure constants). (size: S)

---

## Phase 2: Repository — getById

- [ ] T03 [RED] Create `test/features/workout/data/session_repository_get_by_id_test.dart` with 3 failing tests covering SCENARIO-334 (returns Session when doc exists), SCENARIO-335 (returns null when doc absent), SCENARIO-336 (reads correct Firestore path `users/{uid}/sessions/{sessionId}`). Uses `FakeFirebaseFirestore`. (size: S)
- [ ] T04 [GREEN] Add `Future<Session?> getById({required String uid, required String sessionId})` to `lib/features/workout/data/session_repository.dart` — reads `_sessions(uid).doc(sessionId).get()`, delegates to `_sessionFromDoc`. (~5 LOC) (size: S)
- [ ] T05 [QA] Run `flutter test test/features/workout/data/session_repository_get_by_id_test.dart` — all 3 tests green. (size: S)

---

## Phase 3: Combined Provider

- [ ] T06 [RED] Add tests to `test/features/workout/application/session_providers_test.dart` — new group `sessionSummaryProvider`: (1) returns record with Session+SetLogs when both succeed (SCENARIO-334 integrated), (2) returns session=null when getById returns null (SCENARIO-335 integrated), (3) propagates error when repo throws. Uses `ProviderContainer` with `sessionRepositoryProvider` overridden by fake repo. (size: M)
- [ ] T07 [GREEN] Add `sessionSummaryProvider` to `lib/features/workout/application/session_providers.dart` — `FutureProvider.autoDispose.family<({Session? session, List<SetLog> setLogs}), ({String uid, String sessionId})>` using `Future.wait([getById, listSetLogs])`. (size: S)
- [ ] T08 [QA] Run provider tests — new group green. (size: S)

---

## Phase 4: PostWorkoutNotifier

- [ ] T09 [RED] Create `test/features/workout/application/post_workout_notifier_test.dart` — test SCENARIO-337: `shareWorkout` builds Post with `authorDisplayName` from loaded userProfile (`displayName: 'Ana'`). Uses `ProviderContainer` overrides for `userProfileProvider` + fake `PostRepository`. (size: M)
- [ ] T10 [GREEN] Create `lib/features/workout/application/post_workout_notifier.dart` — `PostWorkoutNotifier extends AsyncNotifier<void>` + `postWorkoutNotifierProvider`. Implement `build()` (returns `AsyncData(null)`) and `shareWorkout(Session)` stub enough for SCENARIO-337. (size: M)
- [ ] T11 [RED] Add test SCENARIO-338 to notifier test file: `shareWorkout` uses `authorDisplayName: ''` when `userProfileProvider` returns null. (size: S)
- [ ] T12 [GREEN] Implement `userProfileProvider.valueOrNull?.displayName ?? ''` fallback in `shareWorkout`. (size: S)
- [ ] T13 [RED] Add tests SCENARIO-339 (`privacy: PostPrivacy.friends`, `routineTag` fields), SCENARIO-341 (`text == WorkoutStrings.postAutoCompleteText`), SCENARIO-340 (rethrows when `PostRepository.create` throws) to notifier test file. (size: M)
- [ ] T14 [GREEN] Complete `shareWorkout`: set `PostPrivacy.friends`, build `RoutineTag` from session, set `text: WorkoutStrings.postAutoCompleteText`, call `postRepositoryProvider.create(post)`, invalidate feed providers, set `AsyncData(null)`. Catch → set `AsyncError` → rethrow. (size: M)

---

## Phase 5: Screen Widget

- [ ] T15 [RED] Create `test/features/workout/presentation/post_workout_summary_screen_test.dart` — test SCENARIO-342: `CircularProgressIndicator` visible while `sessionSummaryProvider` is loading. Uses `MaterialApp` + `ProviderScope` override with never-resolving future. (size: M)
- [ ] T16 [GREEN] Create `lib/features/workout/presentation/post_workout_summary_screen.dart` — `ConsumerWidget PostWorkoutSummaryScreen({required String sessionId})`. Render loading branch: centered `CircularProgressIndicator`. (size: S)
- [ ] T17 [RED] Add SCENARIO-343 test (header shows "BUEN ENTRENO" + routineName when `wasFullyCompleted: true`) and SCENARIO-344 (shows "SESIÓN INTERRUMPIDA" when `wasFullyCompleted: false`). (size: S)
- [ ] T18 [GREEN] Implement header branch in screen — conditional ternary on `session.wasFullyCompleted`. (size: S)
- [ ] T19 [RED] Add SCENARIO-345 test (stat grid shows correct DURACIÓN/VOLUMEN/SETS/"—" values) and SCENARIO-346 (SETS count matches `setLogs.length`). (size: S)
- [ ] T20 [GREEN] Implement 2×2 `GridView` of `StatTile` widgets using `durationMin`, `totalVolumeKg`, `setLogs.length`, and stub `'—'` for PRs HOY. (size: M)
- [ ] T21 [RED] Add SCENARIO-347 test (PRs section header/placeholder visible, no real items) and SCENARIO-348 (exactly 5 emoji `Text` widgets in mood row, no interaction). (size: S)
- [ ] T22 [GREEN] Implement PRs stub section (`'PRS DE LA SESIÓN'` title + `'Próximamente'` text) and emoji mood `Row` of 5 `Text` widgets (no `GestureDetector`). (size: S)
- [ ] T23 [RED] Add SCENARIO-349 test (LISTO tap navigates to `/workout`, `PostRepository.create` never called) and SCENARIO-350 (COMPARTIR tap calls `postWorkoutNotifier.shareWorkout` once). (size: M)
- [ ] T24 [GREEN] Implement LISTO filled button (`context.go('/workout')`) and COMPARTIR outlined button (`ref.read(postWorkoutNotifierProvider.notifier).shareWorkout(session)`). (size: S)
- [ ] T25 [RED] Add SCENARIO-351 test (SnackBar "¡Post compartido!" + nav to `/workout` after success) and SCENARIO-352 (SnackBar "No pudimos compartir tu post", NO nav after failure). (size: M)
- [ ] T26 [GREEN] Add `ref.listen(postWorkoutNotifierProvider, ...)` in screen: on `AsyncData` → show success SnackBar + `context.go('/workout')`; on `AsyncError` → show error SnackBar, stay. (size: M)
- [ ] T27 [RED] Add SCENARIO-353 test (text "Sesión no encontrada" visible + back button navigates to `/workout` when `session == null`). (size: S)
- [ ] T28 [GREEN] Implement not-found state (centered column: "Sesión no encontrada" + filled CTA → `/workout`) and error state (centered column: error message + "Reintentar" button that calls `ref.invalidate(sessionSummaryProvider(...))`). (size: S)

---

## Phase 6: Router

- [ ] T29 [RED] Create `test/app/router_post_workout_summary_test.dart` — test SCENARIO-354: navigating to `/workout/session-summary/abc123` renders `PostWorkoutSummaryScreen` with `sessionId == 'abc123'`, no `BottomNavigationBar`. Uses `buildRouter` + `pumpWidget`. (size: M)
- [ ] T30 [GREEN] Edit `lib/app/router.dart` lines 153–158 — replace stub `Scaffold(body: Center(child: Text('Resumen — próximamente')))` with `PostWorkoutSummaryScreen(sessionId: state.pathParameters['sessionId']!)`. (size: S)

---

## Phase 7: Quality Gates

- [ ] T31 [QA] Run `flutter analyze` — 0 issues. BLOCKER: do not proceed to T32 if issues remain. (size: S)
- [ ] T32 [QA] Run `dart format .` — no unformatted files. BLOCKER. (size: S)
- [ ] T33 [QA] Run `flutter test` full suite — all green. Baseline ~600+; this change adds ~22 new tests (SCENARIO-334..354). BLOCKER. (size: S)

---

## Task Summary

| Phase | Tasks | Focus |
|-------|-------|-------|
| 1 — Setup | T01–T02 | Branch check + WorkoutStrings |
| 2 — Repo | T03–T05 | `getById` RED/GREEN/QA |
| 3 — Provider | T06–T08 | `sessionSummaryProvider` RED/GREEN/QA |
| 4 — Notifier | T09–T14 | `PostWorkoutNotifier` 3× RED/GREEN cycles |
| 5 — Screen | T15–T28 | Widget states 7× RED/GREEN cycles |
| 6 — Router | T29–T30 | Route wiring RED/GREEN |
| 7 — Quality | T31–T33 | analyze + format + full test suite |
| **Total** | **33** | |

Execution order: strictly sequential — each RED must fail before its GREEN, each GREEN before the next RED.

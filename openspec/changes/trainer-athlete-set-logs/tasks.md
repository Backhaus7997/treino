# Tasks: trainer-athlete-set-logs

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | PR-A ~180-240 / PR-B ~140-200 / Total ~320-440 |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR-A (foundation + web) → PR-B (mobile, stacked on PR-A) |
| Delivery strategy | ask-on-risk |
| Chain strategy | stacked-to-main |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Rule + provider + shared widget + web surface | PR-A | Base = main; independently shippable |
| 2 | Mobile athlete detail history + set detail | PR-B | Base = PR-A branch; depends on provider + SessionExerciseBlock |

---

## PR-A — Foundation + Web

### Phase 1: Security — Firestore Rules (MANUAL EMULATOR)

- [ ] **1.1** `firestore.rules` (~508-510): add `setLogs/{setLogId}` sub-match with read mirroring the session-share predicate and write owner-only. REQ-SETLOGS-001, 002, 003, 004.
  - Tests: **MANUAL EMULATOR** — 5 scenarios (linked trainer reads; linked trainer lists; unrelated trainer denied; no-share-doc denied; athlete writes; trainer write denied; unauthenticated denied). Mark with `// emulator-deferred` comment in the rules file change.
  - No automated harness to build.

### Phase 2: Provider (RED → GREEN)

- [ ] **2.1** RED: create `test/features/workout/application/coach_session_set_logs_provider_test.dart`. Write failing tests for: delegates to `listSetLogs` and returns N items; empty `athleteUid` returns `[]`; empty `sessionId` returns `[]`; `autoDispose`. Stub `sessionRepositoryProvider`. REQ-SETLOGS-005.
- [ ] **2.2** GREEN: add `coachSessionSetLogsProvider` (FutureProvider.autoDispose.family keyed on `({String athleteUid, String sessionId})`) to `lib/features/workout/application/session_providers.dart`. Guard empty keys with early `Future.value(const [])`. REQ-SETLOGS-005.
- [ ] **2.3** VERIFY: `flutter test test/features/workout/application/coach_session_set_logs_provider_test.dart` passes; `flutter analyze` 0 errors.

### Phase 3: Shared Widget — SessionExerciseBlock (RED → GREEN)

- [ ] **3.1** RED: create `test/features/workout/presentation/widgets/session_exercise_block_test.dart`. Failing tests: renders exercise name; renders N rows for N sets; renders reps + weightKg per row; no edit/delete affordance in tree. REQ-SETLOGS-006, 009.
- [ ] **3.2** GREEN: create `lib/features/workout/presentation/widgets/session_exercise_block.dart` — public `SessionExerciseBlock(exerciseName, sets)` + private `_SetRow` + `_PrBadgeStub`. No provider reads. No edit/delete affordances. REQ-SETLOGS-006, 009.
- [ ] **3.3** VERIFY widget tests pass; `flutter analyze` 0 errors; `dart format .` clean.

### Phase 4: Widget Extraction Regression (RED → GREEN)

- [ ] **4.1** RED: extend (or create) `test/features/workout/presentation/session_detail_screen_test.dart` — scenario with E1 (3 sets) + E2 (2 sets): assert both headers visible, 5 set rows total, no edit button. REQ-SETLOGS-011.
- [ ] **4.2** GREEN: modify `lib/features/workout/presentation/session_detail_screen.dart` — replace local `_ExerciseBlock`, `_SetRow`, `_PrBadgeStub` with `import` of `session_exercise_block.dart`; delete local class definitions. Behavior-preserving only. REQ-SETLOGS-011.
- [ ] **4.3** VERIFY regression test passes; existing tests still green; `flutter analyze` 0.

### Phase 5: i18n Keys

- [ ] **5.1** Add keys to `lib/l10n/intl_es_AR.arb`: `coachSessionSetLogsTitle`, `coachSessionTapToExpand`, `coachSessionSetLogsEmpty`, `coachSessionSetLogsLoadError`, `coachAthleteNoSharePlaceholder`. REQ (all UI reqs).
- [ ] **5.2** Mirror same keys in `lib/l10n/intl_es.arb` (same Spanish values) and `lib/l10n/intl_en.arb` (English values).
- [ ] **5.3** Run `flutter gen-l10n` (or project equivalent). Confirm `AppLocalizations` surfaces all new keys. `flutter analyze` 0.

### Phase 6: Web — `_HistorialTable` Tap-to-Expand (RED → GREEN)

- [ ] **6.1** RED: extend `test/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen_test.dart` — 4 widget scenarios: (a) tap session row shows loading indicator; (b) loaded sets grouped by exercise show exercise headers + set rows; (c) empty sets shows `coachSessionSetLogsEmpty` copy; (d) non-permission-denied error shows `coachSessionSetLogsLoadError`; (e) permission-denied shows `coachAthleteNoSharePlaceholder`. REQ-SETLOGS-007, 008, 009.
- [ ] **6.2** GREEN: modify `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` — wrap each `_HistorialTable` finished-session row in `ExpansionTile`; on expand, `Consumer` watches `coachSessionSetLogsProvider((athleteUid: athleteId, sessionId: s.id))`; `.when(loading: spinner, data: group-by-exercise → SessionExerciseBlock list or empty copy, error: permission-denied → placeholder, else → generic error copy)`. No edit/delete affordances. All strings via `AppL10n`. REQ-SETLOGS-007, 008, 009.
- [ ] **6.3** VERIFY widget tests pass; `flutter analyze` 0; `dart format .` clean.

### Phase 7: PR-A Quality Gate

- [ ] **7.1** `flutter analyze` 0 warnings/errors across all changed files.
- [ ] **7.2** `dart format . --set-exit-if-changed` exits 0.
- [ ] **7.3** `flutter test` full suite green (no regressions).

---

## PR-B — Mobile (stacked on PR-A)

### Phase 8: Mobile — Athlete Detail Session History (RED → GREEN)

- [ ] **8.1** RED: extend `test/features/coach/presentation/athlete_detail_screen_test.dart` — widget scenarios: (a) history section renders finished sessions only (not in-progress); (b) tap finished session invokes `coachSessionSetLogsProvider`; (c) sets render via `SessionExerciseBlock`; (d) permission-denied shows `coachAthleteNoSharePlaceholder`; (e) no edit/delete affordance in set-log section. REQ-SETLOGS-008, 009, 010.
- [ ] **8.2** GREEN: modify `lib/features/coach/presentation/athlete_detail_screen.dart` — import `sessionsByUidProvider`; add HISTORIAL section to `_AthleteDetailBody` `ListView`; filter to completed sessions; tappable rows expand detail watching `coachSessionSetLogsProvider((athleteUid: athleteId, sessionId: s.id))`; render `SessionExerciseBlock` list; permission-denied → `coachAthleteNoSharePlaceholder`; generic error → `coachSessionSetLogsLoadError`. No edit/delete affordances. All strings via `AppL10n`. REQ-SETLOGS-010.
- [ ] **8.3** VERIFY widget tests pass; `flutter analyze` 0; `dart format .` clean.

### Phase 9: PR-B Quality Gate

- [ ] **9.1** `flutter analyze` 0 warnings/errors.
- [ ] **9.2** `dart format . --set-exit-if-changed` exits 0.
- [ ] **9.3** `flutter test` full suite green.

---

## MANUAL EMULATOR Verification Checklist (deferred — no harness)

Covers REQ-SETLOGS-001 through REQ-SETLOGS-004. Run against Firebase Emulator after PR-A merges.

| # | Scenario | Expected |
|---|----------|----------|
| E1 | Linked trainer reads single setLog doc | allowed |
| E2 | Linked trainer lists setLogs collection | allowed |
| E3 | Unrelated trainer (different uid) reads setLog | permission-denied |
| E4 | No session_shares doc exists for athlete | permission-denied |
| E5 | Linked trainer attempts to write setLog | permission-denied |
| E6 | Athlete reads own setLog | allowed |
| E7 | Athlete writes own setLog | allowed |
| E8 | Unauthenticated read | permission-denied |

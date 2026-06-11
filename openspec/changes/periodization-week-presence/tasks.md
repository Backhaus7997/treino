# Tasks: periodization-week-presence

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 480–580 |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 → PR 2 → PR 3 (feature-branch-chain) |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Domain: activeWeeks field + isPresentInWeek getter + serialization + build_runner | PR 1 | Base = feat/periodization-week-presence; self-contained, pure domain + tests |
| 2 | Editor authoring: delete dialog, add-scope dialog, _isValid, _duplicateWeek mask | PR 2 | Base = PR 1 branch; tests included; no consumer changes yet |
| 3 | Consumers: detail filter, player filter, gating required-grid, superset drop + Firestore rules stub | PR 3 | Base = PR 2 branch; final integration + gate |

---

## Phase 1 — Domain Foundation (PR 1 scope)

- [x] 1.1 **[RED]** `test/features/workout/domain/routine_slot_test.dart` — add failing tests for SCENARIO-WPRES-001..008 (legacy deserialize, explicit mask deserialize, isPresentInWeek empty/non-empty, round-trip). Satisfies: REQ-WPRES-001, REQ-WPRES-002, REQ-WPRES-004.
- [x] 1.2 **[GREEN]** `lib/features/workout/domain/routine_slot.dart` — add `@Default(<int>[]) List<int> activeWeeks` field + `bool isPresentInWeek(int week)` getter. No converter needed (mirrors `targetReps`). Satisfies: REQ-WPRES-001, REQ-WPRES-002, REQ-WPRES-004.
- [x] 1.3 **[BUILD]** Run `dart run build_runner build --delete-conflicting-outputs`; commit regenerated `routine_slot.freezed.dart` + `routine_slot.g.dart`. Satisfies: REQ-WPRES-031.
- [x] 1.4 **[RED]** `test/features/workout/data/routine_rules_test.dart` — add stub tests WPRES-RULES-01/02: owner can write `activeWeeks` inside a slot nested in `days`; `activeWeeks` is NOT a top-level field. Satisfies: REQ-WPRES-005 (SCENARIO-WPRES-009, SCENARIO-WPRES-010).
- [x] 1.5 **[GREEN]** `scripts/rules_test/rules.test.js` — add Jest tests WPRES-RULES-01/02 against Firestore emulator confirming existing `hasOnly` guard already covers `activeWeeks`. No `firestore.rules` change. Satisfies: REQ-WPRES-005.
- [x] 1.6 **[GATE]** `flutter analyze lib test` 0 issues + `dart format` clean + all tests green for PR 1 scope.

## Phase 2 — Editor Authoring (PR 2 scope)

- [ ] 2.1 **[RED]** `test/features/workout/presentation/routine_editor_periodization_test.dart` — add failing tests for SCENARIO-WPRES-011..019 (delete dialogs, auto-route single-week, add-scope dialogs, no-dialog invariants) and SCENARIO-WPRES-020..021 (duplicar-semana presence copy + independence). Satisfies: REQ-WPRES-010, REQ-WPRES-011, REQ-WPRES-012, REQ-WPRES-013.
- [ ] 2.2 **[GREEN]** `lib/features/workout/presentation/routine_editor_screen.dart` — add `_deleteSlotWithPresence` handler: branch on `_numWeeks > 1`, show "solo esta semana / todas las semanas" dialog, materialize empty mask before removing current week, auto-route to structural delete when only one week remains. Preserve `FocusManager.instance.unfocus()` at affected lines. Satisfies: REQ-WPRES-010, REQ-WPRES-011 (SCENARIO-WPRES-011..015).
- [ ] 2.3 **[GREEN]** `lib/features/workout/presentation/routine_editor_screen.dart` — add `_addExerciseWithScope` handler: show scope dialog when `_numWeeks > 1 && _selectedWeek >= 1`; seed `activeWeeks = [_selectedWeek]` or `[]` accordingly; week-0 / single-week path untouched. Satisfies: REQ-WPRES-012 (SCENARIO-WPRES-016..019).
- [ ] 2.4 **[GREEN]** `lib/features/workout/presentation/routine_editor_screen.dart` — update `_duplicateWeek`/`_addWeek`/`_removeLastWeek` to propagate presence: copy mask for duplicated week; `_removeLastWeek` drops highest mask index and collapses to `[]` if emptied; `_addWeek` leaves existing masks unchanged (new week = absent until authored). Satisfies: REQ-WPRES-013 (SCENARIO-WPRES-020..021).
- [ ] 2.5 **[RED]** `test/features/workout/presentation/routine_editor_periodization_test.dart` — add tests for SCENARIO-WPRES-022..023 (`_isValid` rejects out-of-range and all-excluding mask). Satisfies: REQ-WPRES-003, REQ-WPRES-014.
- [ ] 2.6 **[GREEN]** `lib/features/workout/presentation/routine_editor_screen.dart` — extend `_isValid` / `buildRoutineSlot` to reject slots with non-empty `activeWeeks` that exclude every week in `[0..numWeeks-1]`. Satisfies: REQ-WPRES-003, REQ-WPRES-014 (SCENARIO-WPRES-005, SCENARIO-WPRES-022..023).
- [ ] 2.7 **[GATE]** `flutter analyze lib test` 0 issues + format clean + all tests green for PR 2 scope.

## Phase 3 — Consumers + Gating (PR 3 scope)

- [ ] 3.1 **[RED]** `test/features/workout/presentation/routine_detail_periodized_test.dart` — add failing tests for SCENARIO-WPRES-026..028 and SCENARIO-WPRES-024 (numWeeks==1 no filter). Satisfies: REQ-WPRES-020, REQ-WPRES-015.
- [ ] 3.2 **[GREEN]** `lib/features/workout/presentation/routine_detail_screen.dart` — filter `day.slots` by `isPresentInWeek(viewedWeek)` at top of `_buildExerciseList` when `numWeeks > 1`; add "sin ejercicios esta semana" info message for zero-present days; recompute stats on filtered list. Satisfies: REQ-WPRES-020 (SCENARIO-WPRES-026..028), REQ-WPRES-015 (SCENARIO-WPRES-024).
- [ ] 3.3 **[RED]** `test/features/workout/application/session_notifier_test.dart` — add failing tests for SCENARIO-WPRES-029..030 (player filters by weekNumber, all-empty-mask passes through unchanged). Satisfies: REQ-WPRES-021.
- [ ] 3.4 **[GREEN]** `lib/features/workout/application/session_notifier.dart` — filter `day.slots` by `isPresentInWeek(weekNumber)` inside `_buildFresh` and `_buildResume` before constructing `SessionState`. Satisfies: REQ-WPRES-021, REQ-WPRES-023 (SCENARIO-WPRES-029..030, SCENARIO-WPRES-033..034 — superset drop is downstream of filter).
- [ ] 3.5 **[RED]** `test/features/workout/application/plan_progress_test.dart` — add failing tests for SCENARIO-WPRES-031 (empty-presence day auto-satisfied; does not block week completion). Satisfies: REQ-WPRES-022.
- [ ] 3.6 **[RED]** `test/features/workout/application/plan_gating_test.dart` — add failing tests confirming empty-presence days are skipped by `isDayUnlocked`/`isStartable` required-grid logic. Satisfies: REQ-WPRES-022.
- [ ] 3.7 **[GREEN]** `lib/features/workout/application/plan_progress.dart` — add `Set<({int week, int day})> requiredPairs` parameter to `derivePlanProgress`; skip pairs absent from `requiredPairs` (auto-satisfied). Satisfies: REQ-WPRES-022 (SCENARIO-WPRES-031..032).
- [ ] 3.8 **[GREEN]** `lib/features/workout/application/plan_gating.dart` — thread `requiredPairs` into `isWeekUnlocked`/`isDayUnlocked`/`isStartable` so auto-satisfied days are invisible to unlock logic. Satisfies: REQ-WPRES-022.
- [ ] 3.9 **[GREEN]** `lib/features/workout/application/session_providers.dart` — update `planProgressProvider` to compute `requiredPairs` per-week grid (filtering slot presence) and pass to updated `derivePlanProgress`. Satisfies: REQ-WPRES-022.
- [ ] 3.10 **[RED]** `test/features/workout/presentation/session_player_screen_test.dart` — add tests for SCENARIO-WPRES-025 (numWeeks==1 player unchanged; all slots rendered). Satisfies: REQ-WPRES-015, REQ-WPRES-030.
- [ ] 3.11 **[RED]** `test/features/workout/presentation/routine_detail_screen_test.dart` — add SCENARIO-WPRES-035 regression test (single-week plan edit/save round-trip unchanged). Satisfies: REQ-WPRES-030.
- [ ] 3.12 **[GATE]** `flutter analyze lib test` 0 issues + `dart format` clean + all tests green (full suite). Satisfies: REQ-WPRES-031 (SCENARIO-WPRES-036).

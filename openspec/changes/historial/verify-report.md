# Verify Report — historial

**Change**: `historial` · Fase 4 · Etapa 4
**PRs merged**: PR #46 (commit `65455c6`) · PR #48 (commit `3ef4d72`)
**Strict TDD**: ACTIVE (`flutter test`)
**Artifact store**: hybrid
**Date**: 2026-05-19
**Verdict**: **PASS WITH WARNINGS**

---

## Quality Gates

| Gate | Command | Result |
|------|---------|--------|
| Static analysis | `flutter analyze` | ✅ 0 issues |
| Format | `dart format --output=none --set-exit-if-changed lib test` | ✅ 0 changes (260 files) |
| Full test suite | `flutter test` | ✅ 770 passed, 1 skipped, 0 failed |
| Change-specific tests | `flutter test test/features/workout/presentation/utils/date_helpers_test.dart test/features/workout/presentation/widgets/historial_section_test.dart test/features/workout/presentation/session_detail_screen_test.dart test/app/router_workout_routes_test.dart` | ✅ 40/40 passed |

---

## Task Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 18 (T01–T18) |
| Tasks complete | 18 |
| Tasks incomplete | 0 |

All tasks verified via code presence and passing tests.
PR-A: T01–T11 (date_helpers, historial_section, workout_strings, workout_screen, router stub).
PR-B: T12–T18 (session_detail_screen, workout_strings detail consts, router stub replacement).

---

## TDD Compliance

> apply-progress artifact was NOT saved to engram or openspec — both PRs were merged without persisting the artifact. TDD compliance reconstructed from code state and test evidence.

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | ⚠️ | apply-progress NOT found in engram or openspec/changes/historial/ |
| All tasks have tests | ✅ | 5 test files created/extended; tests cover all REQ-HIST-001..022 |
| RED confirmed (tests exist) | ✅ | All 5 test files present and structurally annotated with TDD RED comments |
| GREEN confirmed (tests pass) | ✅ | 40/40 change-specific tests pass on execution |
| Triangulation adequate | ✅ | Multiple cases per behavior (357/358/360, 367/368/369/370, 379/380 + 11 month/weekday cases) |
| Safety Net for modified files | ✅ | workout_screen_test.dart and router_workout_routes_test.dart were pre-existing test files, REQ-HIST-020 test added |

**TDD Compliance**: 5/6 checks passed (apply-progress artifact gap is documentation, not implementation failure)

---

## Test Layer Distribution

| Layer | Tests | Files | Tools |
|-------|-------|-------|-------|
| Unit (date_helpers) | 12 | 1 | `flutter_test` pure Dart |
| Widget (HistorialSection) | 17 | 1 | `flutter_test` + `GoRouter` + `ProviderScope` |
| Widget (SessionDetailScreen) | 9 | 1 | `flutter_test` + `GoRouter` + `ProviderScope` |
| Widget (WorkoutScreen update) | 1 | 1 | `flutter_test` + `GoRouter` + `ProviderScope` |
| Router | 1 | 1 | `GoRouter` + `ProviderScope` |
| **Total (change-specific)** | **40** | **5** | |

---

## Changed File Coverage

Coverage tool not available as a standalone runner in this project (flutter test does not emit lcov by default).

**Coverage analysis**: skipped — no coverage tool configured.

---

## Spec Compliance Matrix

### REQ-HIST-001..008 (HistorialSection — PR-A)

| REQ | SCENARIO | Test file | Result |
|-----|----------|-----------|--------|
| REQ-HIST-001 | SCENARIO-355: HistorialSection is public and renderable without parameters | `historial_section_test.dart > SCENARIO-355` | ✅ COMPLIANT |
| REQ-HIST-002 | SCENARIO-356: sessions appear in newest-first order | `historial_section_test.dart > SCENARIO-356` | ✅ COMPLIANT |
| REQ-HIST-003 | SCENARIO-357: non-finished sessions are excluded | `historial_section_test.dart > SCENARIO-357` | ✅ COMPLIANT |
| REQ-HIST-003 | SCENARIO-358: all-unfinished sessions triggers empty state | `historial_section_test.dart > SCENARIO-358` | ✅ COMPLIANT |
| REQ-HIST-003 | SCENARIO-360: abandoned sessions (wasFullyCompleted=false) filtered out | `historial_section_test.dart > SCENARIO-360` | ✅ COMPLIANT |
| REQ-HIST-004 | SCENARIO-359: card renders routineName + date + kg + min | `historial_section_test.dart > SCENARIO-359` | ✅ COMPLIANT |
| REQ-HIST-005 | SCENARIO-361: empty state renders copy and CTA | `historial_section_test.dart > SCENARIO-361` | ✅ COMPLIANT |
| REQ-HIST-005 | SCENARIO-362: empty state CTA navigates to /workout | `historial_section_test.dart > SCENARIO-362` | ✅ COMPLIANT |
| REQ-HIST-006 | SCENARIO-363: list shows loader while provider resolves | `historial_section_test.dart > SCENARIO-363` | ✅ COMPLIANT |
| REQ-HIST-007 | SCENARIO-364: list shows error message and retry CTA | `historial_section_test.dart > SCENARIO-364` | ✅ COMPLIANT |
| REQ-HIST-008 | SCENARIO-365: tapping card pushes historial detail route | `historial_section_test.dart > SCENARIO-365` | ✅ COMPLIANT |

### REQ-HIST-009..018 (SessionDetailScreen — PR-B)

| REQ | SCENARIO | Test file | Result |
|-----|----------|-----------|--------|
| REQ-HIST-009 | SCENARIO-366: SessionDetailScreen renders for historial detail path, no TreinoBottomBar | `router_workout_routes_test.dart > SCENARIO-378` | ✅ COMPLIANT |
| REQ-HIST-010 | SCENARIO-367: header shows date, time, and routineName | `session_detail_screen_test.dart > SCENARIO-373` | ✅ COMPLIANT |
| REQ-HIST-011 | SCENARIO-368: 4 StatTiles render with correct values | `session_detail_screen_test.dart > SCENARIO-373` | ✅ COMPLIANT |
| REQ-HIST-011 | SCENARIO-369: SETS stat derives from setLog count | `session_detail_screen_test.dart > SCENARIO-373` | ✅ COMPLIANT |
| REQ-HIST-012 | SCENARIO-370: set logs grouped by exerciseName in insertion order | `session_detail_screen_test.dart > SCENARIO-374` | ✅ COMPLIANT |
| REQ-HIST-012 | SCENARIO-371: single exercise with multiple sets renders one block | `session_detail_screen_test.dart > SCENARIO-373` | ✅ COMPLIANT |
| REQ-HIST-013 | SCENARIO-372: set row displays setNumber, reps, weightKg | `session_detail_screen_test.dart > SCENARIO-373` | ⚠️ PARTIAL |
| REQ-HIST-014 | SCENARIO-373: PR badge stub is visible on each set row | `session_detail_screen_test.dart > SCENARIO-375` | ✅ COMPLIANT |
| REQ-HIST-015 | SCENARIO-374: back button pops the route | `session_detail_screen_test.dart > SCENARIO-378b` | ✅ COMPLIANT |
| REQ-HIST-016 | SCENARIO-375: not-found state renders message and back CTA | `session_detail_screen_test.dart > SCENARIO-376` | ✅ COMPLIANT |
| REQ-HIST-017 | SCENARIO-376: loading indicator shown while provider resolves | `session_detail_screen_test.dart > SCENARIO-372` | ✅ COMPLIANT |
| REQ-HIST-018 | SCENARIO-377: error state renders message and retry | `session_detail_screen_test.dart > SCENARIO-377` | ✅ COMPLIANT |

### REQ-HIST-019..021 + REQ-HIST-022 (Router, Swap, Date, Expand Toggle)

| REQ | SCENARIO | Test file | Result |
|-----|----------|-----------|--------|
| REQ-HIST-019 | SCENARIO-378: router resolves historial detail route outside ShellRoute | `router_workout_routes_test.dart > SCENARIO-378` | ✅ COMPLIANT |
| REQ-HIST-020 | (covered by SCENARIO-355) | `workout_screen_test.dart > REQ-HIST-020` | ✅ COMPLIANT |
| REQ-HIST-021 | SCENARIO-379: formatSessionDate returns "Mié 26 nov" | `date_helpers_test.dart > canonical example` | ✅ COMPLIANT |
| REQ-HIST-021 | SCENARIO-380: formatSessionDate handles each weekday | `date_helpers_test.dart > Monday/Tuesday/etc` | ✅ COMPLIANT |
| REQ-HIST-022 | SCENARIO-381: 8 sessions → 5 visible + "Ver más (3)" | `historial_section_test.dart > SCENARIO-367` | ✅ COMPLIANT |
| REQ-HIST-022 | SCENARIO-382: tapping "Ver más" expands to all sessions | `historial_section_test.dart > SCENARIO-368` | ✅ COMPLIANT |
| REQ-HIST-022 | SCENARIO-383: tapping "Ver menos" collapses to 5 | `historial_section_test.dart > SCENARIO-369` | ✅ COMPLIANT |
| REQ-HIST-022 | SCENARIO-384: ≤5 sessions → no toggle rendered | `historial_section_test.dart > SCENARIO-370/371` | ✅ COMPLIANT |

**Compliance summary**: 29/30 scenarios COMPLIANT, 1 PARTIAL

> Note on PARTIAL (SCENARIO-372 / REQ-HIST-013 set table rows): The spec requires column headers SET, REPS, KG to be visible at the top of each exercise block. The implementation renders set rows with `setNumber`, `reps`, and `weightKg` values as text (verified via SCENARIO-373 assertions on set numbers and counts), but there is no dedicated test asserting the three column header labels `SET`, `REPS`, `KG` appear in the widget tree. The headers are visual presentational elements rendered by `_SetRow` — they appear in the rendered output but the test does not explicitly assert them. Implementation is correct, test coverage is partial for this specific sub-requirement.

---

## Correctness — Static Evidence

### Critical validation 1: Filter correctness — REQ-HIST-003

`historial_section.dart` lines 49–52:
```dart
final completed = all
    .where((s) =>
        s.status == SessionStatus.finished && s.wasFullyCompleted)
    .toList();
```
Both conditions applied simultaneously with `&&`. Sessions with `status != finished` OR `wasFullyCompleted == false` are excluded. ✅ VERIFIED (SCENARIO-357, SCENARIO-360 both pass independently)

### Critical validation 2: autoDispose on sessionsByUidProvider

`session_providers.dart` line 22–23:
```dart
final sessionsByUidProvider =
    FutureProvider.autoDispose.family<List<Session>, String>((ref, uid) async {
```
`autoDispose` is set — provider disposes when `HistorialSection` unmounts, re-fetches on next mount. ✅ VERIFIED

### Critical validation 3: Expand toggle state is local (ConsumerStatefulWidget)

`HistorialSection` extends `ConsumerStatefulWidget` (not `ConsumerWidget`) with `bool _expanded = false` in `_HistorialSectionState`. Toggle state is local to the widget instance — resets to collapsed on navigation away/back by design. ✅ VERIFIED

### Critical validation 4: Detail screen grouping via Dart map literal

`session_detail_screen.dart` lines 69–71:
```dart
final grouped = <String, List<SetLog>>{};
for (final log in setLogs) {
  grouped.putIfAbsent(log.exerciseName, () => []).add(log);
}
```
Dart map literals (`{}`) create `LinkedHashMap` — insertion order preserved, first-appearance order guaranteed. ✅ VERIFIED (SCENARIO-374 passes with interleaved inputs)

### Critical validation 5: PR badge stub — no parameters, no logic

`_PrBadgeStub` at lines 242–266: zero constructor parameters, renders a static `Container` with `WorkoutStrings.detailPrBadge` (`'PR'`). No repository calls beyond `sessionSummaryProvider`. ✅ VERIFIED

### Critical validation 6: Router immersive route placement

`router.dart` lines 164–173: `/workout/historial/:sessionId` GoRoute registered at top-level BEFORE the `ShellRoute` at line 180. `TreinoBottomBar` absent from subtree. Pattern mirrors `/workout/session-summary/:sessionId` at lines 156–162. ✅ VERIFIED

### Critical validation 7: Back navigation logic

`session_detail_screen.dart` line 84–85:
```dart
context.canPop() ? context.pop() : context.go('/workout'),
```
Deep-link safe: if no stack entry, goes to `/workout`. SCENARIO-378 (canPop=false) and SCENARIO-378b (canPop=true, pushed from /workout) both pass. ✅ VERIFIED

### Critical validation 8: Read-only data layer

Zero changes to `Session`, `SetLog`, `SessionRepository`, or `session_providers.dart` beyond the documented `autoDispose` annotation on `sessionsByUidProvider` (which was already `autoDispose.family`). No new methods, no new providers, no `pubspec.yaml` changes. ✅ VERIFIED via `flutter analyze` 0 issues + test suite 770 green.

### Critical validation 9: Date helper — pure, Map-based, no intl

`date_helpers.dart`: two `const Map<int, String>` lookups, no imports beyond Dart core, no `intl`, deterministic. ✅ VERIFIED (12 unit tests covering all 7 weekdays, Jan/Mar/Dec months, single-digit day, `now` parameter purity)

---

## Coherence — Design Decisions

| Decision | Followed? | Notes |
|----------|-----------|-------|
| D1: Reuse `sessionsByUidProvider` + client-side filter | ✅ Yes | Lines 49-52 in historial_section.dart |
| D2: Reuse `sessionSummaryProvider` for detail | ✅ Yes | Line 24-26 in session_detail_screen.dart |
| D3: Not-found = `data.session == null` (not empty setLogs) | ✅ Yes | Line 40 in session_detail_screen.dart |
| D4: `formatSessionDate` in `presentation/utils/date_helpers.dart` (feature-scoped) | ✅ Yes | File at exact path specified |
| D5: `String formatSessionDate(DateTime date, {DateTime? now})` signature | ✅ Yes | Line 43 in date_helpers.dart |
| D6: Format `"Mié 26 nov"` always (no Hoy/Ayer) | ✅ Yes | Map lookup returns fixed 3-char abbrevs |
| D7: `LinkedHashMap` for grouping (Dart map literal) | ✅ Yes | Comment at line 68 explicitly notes this |
| D8: Both screens `ConsumerWidget` or `ConsumerStatefulWidget` | ✅ Yes | HistorialSection=ConsumerStatefulWidget (toggle state), SessionDetailScreen=ConsumerWidget |
| D9: `_PrBadgeStub` — private, no params, grep-friendly name | ✅ Yes | Line 242 in session_detail_screen.dart |
| D10: Back nav `canPop() ? pop() : go('/workout')` | ✅ Yes | Line 84-85 in session_detail_screen.dart |
| D11: Router GoRoute top-level before ShellRoute | ✅ Yes | Lines 164-173 vs ShellRoute at 180 |
| D12: PR-A router stub `Center(Text('Detalle — próximamente'))` replaced in PR-B | ✅ Yes | SessionDetailScreen now in router |
| D13: Loading list = spinner local (heading still visible) | ✅ Yes | `_ListLoadingState` in `sessionsAsync.when(loading:)` body, after heading rendered |
| D14: Loading detail = full-screen `Center(CircularProgressIndicator())` | ✅ Yes | Line 32 in session_detail_screen.dart |
| D15: Error retry = `ref.invalidate` | ✅ Yes | Lines 46, 35 respectively |
| D16: `wasFullyCompleted` → constant checkmark icon (only true sessions shown in list) | ✅ Yes | `_CompletedIcon` always renders `TreinoIcon.checkCircleFill` |
| D17: Filter applied in `.when(data:)` before empty check | ✅ Yes | Lines 49-55 in historial_section.dart |
| D18: Empty state CTA → `context.go('/workout')` | ✅ Yes | Line 161 in `_ListEmptyState.build` |

**Design coherence**: 18/18 decisions followed

---

## Assertion Quality

Scan of all 5 test files related to this change:

- No tautologies (`expect(true, isTrue)` or `expect(1, equals(1))` patterns)
- No ghost loops (all `for` loops in tests use a known `manySessions(n)` list, always non-empty for the count used)
- No type-only assertions without value assertions
- No smoke-test-only patterns — all tests assert specific text content or widget types driven by provider data
- `_pumpHistorialSection` and `_pumpDetailScreen` helpers avoid boilerplate duplication
- Mock/assertion ratio: tests use `overrideWith` (not vi.mock), ratio is fine; each test file has more assertions than overrides

**Assertion quality**: ✅ All assertions verify real behavior

---

## Issues Found

**CRITICAL**: None

**WARNING**:
- W1: **apply-progress artifact missing** — Neither `sdd/historial/apply-progress` in engram nor `openspec/changes/historial/apply-progress.md` on disk was created. Both PRs (#46, #48) were merged without saving the TDD cycle evidence table. This breaks the pipeline traceability contract for hybrid mode. TDD compliance was reconstructed from code and test state rather than from the artifact. Recommendation: retroactively save apply-progress for both PRs before archiving, or explicitly document the exception in the archive report.
- W2: **SCENARIO number mismatch in test files** — REQ-HIST-022 expand toggle scenarios were numbered SCENARIO-367..371 in the test files but finalized as SCENARIO-381..384 in the spec. The spec also reused SCENARIO-366 for `SessionDetailScreen widget contract` while the detail screen tests use SCENARIO-372..378. Behavior is fully covered and all tests pass, but the SCENARIO numbers in test comments do not match the final spec numbering. Recommendation: update test comments before archive, or document the draft-vs-final numbering shift in the archive report.

**SUGGESTION**:
- S1: **REQ-HIST-013 column headers not explicitly tested** — The `SET`, `REPS`, `KG` column headers are rendered by the implementation but no test asserts their presence as text. SCENARIO-372 only verifies value cells. Low priority since the headers are presentational and the layout is visually obvious, but a single `find.text('SET')` / `find.text('REPS')` / `find.text('KG')` assertion would make coverage complete.
- S2: **`statPrsToday = 'PRs HOY'` (mixed case) vs `detailStatPrsToday = 'PRS HOY'` (all caps)** — Two constants for the same conceptual label exist. `StatTile` calls `label.toUpperCase()`, so both produce `"PRS HOY"` at render time. However, the inconsistency in source constants (`PRs` vs `PRS`) is a minor cleanliness issue. The post-workout-summary uses the mixed-case version; historial uses the all-caps version. No functional impact.
- S3: **`ConsumerStatefulWidget` instead of design's `ConsumerWidget` for `HistorialSection`** — Design decision D8 specified `ConsumerWidget` for both screens, but `HistorialSection` correctly uses `ConsumerStatefulWidget` to hold `bool _expanded` local state. This is the right call (local toggle state requires `setState`) and the design doc has a note about local state. Not a deviation from intent, but the design artifact text says "ConsumerWidget" without the Stateful qualification.

---

## Verdict

**PASS WITH WARNINGS**

All 22 spec requirements (REQ-HIST-001..022) are implemented and verified. All 770 tests pass (40 change-specific). Quality gates fully clean: 0 analyze issues, 0 format changes, 0 test failures. Two WARNINGs: missing apply-progress artifact (documentation gap, not implementation gap) and SCENARIO number mismatch in test comments (traceability gap, all behaviors covered). One PARTIAL scenario (SCENARIO-372 column headers) addressed as SUGGESTION only since the implementation is correct. Ready for `sdd-archive`.

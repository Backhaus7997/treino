# Apply Progress: wire-real-stats

**Change**: wire-real-stats
**Branch**: feat/wire-real-stats-home → feat/wire-real-stats-own-profile
**Strategy**: Chained PRs — stacked-to-main
**TDD Mode**: Strict TDD (RED → GREEN for every task)

---

## PR#1 — DONE

**Tasks T01-T14 — all complete**
**Baseline**: 792 tests → **Final**: 819 tests (+27 new)
**Quality gates**: PASS (analyze 0 issues, format 0 changed, 819/819 tests pass)

### TDD Cycle Evidence

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| T02 streak_calculator_test | ✅ created failing | — | — |
| T03 weekly_insights_test new fields | ✅ compile errors confirmed | — | — |
| T04 WeeklyInsights DTO | — | ✅ SCENARIO-298..299 pass | — |
| T05 insights_providers_streak_test | ✅ 7 tests failed | — | — |
| T06 insights_providers monthSessionsCount | ✅ tests in streak file | — | — |
| T07 insights_providers.dart extended | — | ✅ SCENARIO-300..304 pass | ✅ dart format |
| T08 esta_semana_card_test loading | ✅ 4 tests failed | — | — |
| T09 esta_semana_card_test tap | ✅ bundled in T08 | — | — |
| T10 EstaSemanaCard ConsumerWidget | — | ✅ SCENARIO-305..310 pass | ✅ const constructors |
| T11 Verify | — | ✅ no hex, no Phosphor direct | — |
| T12 analyze | — | ✅ 0 issues | — |
| T13 format | — | ✅ 0 changed | — |
| T14 flutter test | — | ✅ 819 pass | — |

### Completed Tasks

- [x] T01 — SETUP: clean working tree confirmed (only untracked openspec/ dir)
- [x] T02 — RED: `test/core/utils/streak_calculator_test.dart` — 7 failing tests (SCENARIO-300..303 + dedup + long + single)
- [x] T03 — RED: extended `test/features/insights/domain/weekly_insights_test.dart` — 6 new failing tests (SCENARIO-298..299 + roundtrips)
- [x] T04 — GREEN: `lib/features/insights/domain/weekly_insights.dart` — added `streak: int` + `monthSessionsCount: int` with defaults=0; extended copyWith/==/hashCode
- [x] T05 — RED: `test/features/insights/application/insights_providers_streak_test.dart` — 8 failing tests (SCENARIO-300..304 + active-excluded + multi-month)
- [x] T06 — RED: monthSessionsCount tests bundled in T05 file (SCENARIO-304 + boundaries)
- [x] T07 — GREEN: `lib/features/insights/application/insights_providers.dart` — inline `_computeStreak` + `computeStreakForTest` @visibleForTesting export + monthSessionsCount computation
- [x] T08 — RED: extended `test/features/home/widgets/esta_semana_card_test.dart` — 7 new failing tests (SCENARIO-305..310 + null insights)
- [x] T09 — RED: SCENARIO-310 tap test bundled in T08
- [x] T10 — GREEN: `lib/features/home/widgets/esta_semana_card.dart` — converted to ConsumerWidget with _Skeleton / _ErrorFallback / _Loaded subtrees; StreakSubtext (trained-today vs not-yet variants); DayStrip + _DayDot; MiniStat(SEMANA/MES); BodySilhouettePlaceholder
- [x] T11 — VERIFY: 819 tests pass; 0 hex literals; 0 PhosphorIcons direct usage
- [x] T12 — GATE: `flutter analyze` 0 issues
- [x] T13 — GATE: `dart format --output=none --set-exit-if-changed .` 0 changed
- [x] T14 — GATE: `flutter test` 819 passing

### Files Modified/Created

| File | Action | Description |
|---|---|---|
| `lib/features/insights/domain/weekly_insights.dart` | MODIFIED | +2 fields (streak, monthSessionsCount), +copyWith/==/hashCode |
| `lib/features/insights/application/insights_providers.dart` | MODIFIED | +_computeStreak inline + computeStreakForTest export + monthSessionsCount |
| `lib/features/home/widgets/esta_semana_card.dart` | MODIFIED | StatelessWidget → ConsumerWidget with full AsyncValue.when |
| `test/core/utils/streak_calculator_test.dart` | CREATED | 7 unit tests for _computeStreak |
| `test/features/insights/domain/weekly_insights_test.dart` | MODIFIED | +6 tests for SCENARIO-298..299 |
| `test/features/insights/application/insights_providers_streak_test.dart` | CREATED | 8 integration tests for SCENARIO-300..304 |
| `test/features/home/widgets/esta_semana_card_test.dart` | MODIFIED | +10 widget tests (SCENARIO-305..310) |

### Commits

| Hash | Message |
|---|---|
| 119a0d8 | test(insights): SCENARIO-300..303 for _computeStreak algorithm |
| 9135a15 | feat(insights): add _computeStreak helper (inline, lifted to shared util in PR#2) |
| affef61 | test(insights): SCENARIO-298..299 for WeeklyInsights new fields roundtrip |
| 65247b8 | feat(insights): extend WeeklyInsights with streak + monthSessionsCount |
| 56e3a3d | test(insights): SCENARIO-300..304 for weeklyInsightsProvider streak + monthSessionsCount |
| fa77972 | test(home): SCENARIO-305..310 for EstaSemanaCard ConsumerWidget states |
| 75e5d37 | feat(home): convert EstaSemanaCard to ConsumerWidget with real data wire |

### Deviations from Design

1. **T05/T06 merged**: monthSessionsCount tests co-located in `insights_providers_streak_test.dart` instead of a separate `insights_providers_month_test.dart`. Rationale: both test the same provider, merging avoids fixture duplication. No functional impact.
2. **_computeStreak param type**: Uses `List<Session>` instead of `Iterable<Session>` (consistent with repo return type). Normalized in PR#2.
3. **InsightsScreen not modified**: Per design Section A, no changes needed. Confirmed per design review.

---

## PR#2 — DONE

**Branch**: feat/wire-real-stats-own-profile
**Tasks T15-T26 — all complete**
**Baseline**: 848 tests → **Final**: 867 tests (+19 new)
**Quality gates**: PASS (analyze 0 issues, format 0 changed, 867/867 tests pass)

### TDD Cycle Evidence

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| T15 SETUP | — | ✅ clean tree, 848 baseline | — |
| T16 REFACTOR streak lift | — | ✅ 7 streak tests pass from new path | ✅ import cleanup |
| T17 RED k_formatter_test | ✅ compile error (file missing) | — | — |
| T18 GREEN k_formatter.dart | — | ✅ 9/9 kFormat tests pass | — |
| T19 CREATE UserSessionStats DTO | — | ✅ compiles, hand-written @immutable | — |
| T20 RED profile_stats_providers_test | ✅ compile error (provider missing) | — | — |
| T21 GREEN profile_stats_providers.dart | — | ✅ 4/4 provider tests pass | — |
| T22 RED profile_screen_test | ✅ 4 widget tests fail (stats row absent) | — | — |
| T23 GREEN profile_screen.dart | — | ✅ 6/6 widget tests pass | — |
| T24 GATE analyze | — | ✅ 0 issues | ✅ removed unused imports/vars |
| T25 GATE format | — | ✅ 0 changed after dart format | — |
| T26 GATE flutter test | — | ✅ 867 all pass | — |

### Completed Tasks

- [x] T15 — SETUP: branch feat/wire-real-stats-own-profile from post-PR#1 main (a47feb6), 848 baseline tests
- [x] T16 — REFACTOR: `lib/core/utils/streak_calculator.dart` (NEW) — lifted `computeStreak` from `insights_providers.dart`; updated `insights_providers.dart` to import + call lifted fn; updated `test/core/utils/streak_calculator_test.dart` to import from new location and call `computeStreak` directly (removed `computeStreakForTest`)
- [x] T17 — RED: `test/core/utils/k_formatter_test.dart` — 9 failing tests (SCENARIO-313..315 + boundary 999/1499/1500/92000 + defensive)
- [x] T18 — GREEN: `lib/core/utils/k_formatter.dart` — `String kFormat(num value)` — >= 1000 → Xk, else integer string
- [x] T19 — CREATE: `lib/features/profile/domain/user_session_stats.dart` — hand-written `@immutable UserSessionStats` DTO with totalSessions/totalVolumeKg/streak + ==/hashCode
- [x] T20 — RED: `test/features/profile/application/profile_stats_providers_test.dart` — 4 failing tests (SCENARIO-311..312 + null uid + finished-only filter)
- [x] T21 — GREEN: `lib/features/profile/application/profile_stats_providers.dart` — `FutureProvider.autoDispose<UserSessionStats>` reading `currentUidProvider` + `sessionRepositoryProvider`; guards null uid; uses `computeStreak` from shared util
- [x] T22 — RED: `test/features/profile/profile_screen_test.dart` — 6 widget tests (SCENARIO-316..319 + loading/sign-out coexistence + color semantics)
- [x] T23 — GREEN: `lib/features/profile/profile_screen.dart` — `ProfileScreen` (ConsumerWidget) now has `_OwnProfileStatsRow` above `Expanded(Center(_ExistingScaffold))`; `_StatTile` renders label + value; SESIONES/VOLUMEN KG → `palette.accent`, RACHA → `palette.highlight`; loading/error → `'--'`
- [x] T24 — GATE: `flutter analyze` 0 issues
- [x] T25 — GATE: `dart format --output=none --set-exit-if-changed .` 0 changed
- [x] T26 — GATE: `flutter test` 867 passing

### Files Modified/Created

| File | Action | Description |
|---|---|---|
| `lib/core/utils/streak_calculator.dart` | CREATED | Public `computeStreak(List<Session>, {DateTime? now})` — lifted from insights_providers |
| `lib/core/utils/k_formatter.dart` | CREATED | `String kFormat(num value)` — Xk or integer |
| `lib/features/profile/domain/user_session_stats.dart` | CREATED | Hand-written @immutable DTO (ADR-WRS-07) |
| `lib/features/profile/application/profile_stats_providers.dart` | CREATED | `userSessionStatsProvider` FutureProvider.autoDispose |
| `lib/features/profile/profile_screen.dart` | MODIFIED | Added `_OwnProfileStatsRow` + `_StatTile` above existing PERFIL/sign-out scaffold |
| `lib/features/insights/application/insights_providers.dart` | MODIFIED | Replaced inline _computeStreak + computeStreakForTest with import from streak_calculator |
| `test/core/utils/streak_calculator_test.dart` | MODIFIED | Updated import → streak_calculator; calls computeStreak directly (not computeStreakForTest) |
| `test/core/utils/k_formatter_test.dart` | CREATED | 9 unit tests for kFormat |
| `test/features/profile/domain/user_session_stats.dart` | — | No test file needed (simple DTO) |
| `test/features/profile/application/profile_stats_providers_test.dart` | CREATED | 4 provider unit tests |
| `test/features/profile/profile_screen_test.dart` | CREATED | 6 widget tests |

### Commits

| Hash | Message |
|---|---|
| 4ed46f3 | refactor(insights): lift _computeStreak to lib/core/utils/streak_calculator |
| 42e4e13 | test(core): kFormat SCENARIO-313..315 + boundary cases |
| 51946f0 | feat(core): add kFormat helper for Xk compact display |
| 2e4f10a | test(profile): userSessionStatsProvider SCENARIO-311..312 + null uid guard |
| 201d93c | feat(profile): add userSessionStatsProvider for own-profile stats |
| 1899ed2 | test(profile): ProfileScreen stats row SCENARIO-316..319 |
| 2cc8518 | feat(profile): add stats row to ProfileScreen above PERFIL scaffold |
| 47f9bae | chore: apply dart format |

### Deviations from Design

1. **File naming**: Design says `lib/core/utils/number_format.dart` for kFormat. Tasks + prompt both say `lib/core/utils/k_formatter.dart`. Used `k_formatter.dart` (matches spec function name `kFormat` and tasks.md T17/T18). No functional deviation.
2. **Loading state**: Used `Completer<UserSessionStats>` in widget tests to simulate loading without pending timers (Flutter test harness limitation). Same behavior as infinite future, correct for testing.
3. **ProfileScreen**: Design says `SafeArea > Column`. Current ProfileScreen has no SafeArea wrapper (it's rendered inside a shell that provides safe area). Did not add SafeArea to avoid breaking existing layout.

---

## PR#3 — PENDING

Tasks T27-T50 not yet implemented.

---

## PR#4 — PENDING

Tasks T51-T68 not yet implemented.

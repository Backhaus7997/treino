# Verify Report -- home-shell

**Change**: home-shell  
**Branch**: feat/home-shell  
**Verified on**: 2026-05-12  
**Artifact store**: openspec

---

## Summary

- Total REQs: 22, Pass: 19, Fail: 0, Partially covered: 3
- Total tasks: 21, Done: 20, Pending (MANUAL): 1 (TASK-009 smoke)
- Findings: CRITICAL=1, WARNING=3, SUGGESTION=2
- Ready to ship: YES with caveat

---

## Findings

### CRITICAL

**CRIT-001 -- REQ-HOME-EMPEZAR-001 spec text not updated after post-apply play-icon fix**

Files: spec.md line 119, tasks.md line 83, design.md section 3.

Spec scenario for REQ-HOME-EMPEZAR-001 has the OR-condition:
- (a) find.text(arrow-glyph + EMPEZAR ENTRENAMIENTO) finds one widget, OR
- (b) find.byType(HomeCTAButton) with label == arrow-glyph + EMPEZAR ENTRENAMIENTO

Implementation correctly moved the glyph to leadingIcon: TreinoIcon.play with
label: EMPEZAR ENTRENAMIENTO. Test was updated to match. But spec/tasks/design still
reference the old label string. Neither OR branch is satisfied by live code.

Impact: reviewer finds spec text inconsistent with code and test.

Resolution before merge:
- spec.md: assert label==EMPEZAR ENTRENAMIENTO and leadingIcon==TreinoIcon.play
- tasks.md TASK-004a done-when condition 6: same update
- design.md section 3: HomeCTAButton(label: EMPEZAR ENTRENAMIENTO, leadingIcon: TreinoIcon.play)

Implementation verdict: CODE and TEST are CORRECT. Defect is documentation-only.

---

### WARNING

**WARN-001 -- REQ-HOME-HEADER-002 missing test for UserProfile(displayName: null)**

File: test/features/home/widgets/home_header_test.dart

REQ-HOME-HEADER-002 specifies two scenarios:
1. HomeHeader(profile: null) -> HOLA! -- tested (test 3, passes).
2. HomeHeader(profile: UserProfile(displayName: null)) -> HOLA! -- NOT tested.

Implementation handles it correctly but the test is absent. Design section 8.4 and
TASK-005a both specify 6 header tests; the file has 5.

Resolution: add HomeHeader(profile: makeProfile(displayName: null)) ->
expect(find.text(HOLA!), findsOneWidget).

---

**WARN-002 -- REQ-HOME-PROVIDER-002 assertions incomplete at screen integration level**

File: test/features/home/home_screen_test.dart test 6

REQ-HOME-PROVIDER-002 for AsyncData(null) requires find.text(HOLA!) findsOneWidget
+ find.byType(CachedNetworkImage) findsNothing + no FlutterError.
Test 6 only asserts header.profile, isNull. Visual assertions absent at screen level.

Risk: Low -- null-profile visual path covered in home_header_test.dart at unit level.

Resolution: extend test 6 with find.text(HOLA!) and CachedNetworkImage assertions.

---

**WARN-003 -- TASK-009 manual smoke run is MANUAL-PENDING**

All automated criteria pass (246/246 tests green). Visual parity against mockups and
real device behavior not confirmed. Must complete before PR merge.
Steps documented in apply-progress.md TASK-009.

---

### SUGGESTION

**SUG-001 -- home_cta_button_test.dart uses legacy label with arrow glyph**

File: test/features/home/widgets/home_cta_button_test.dart lines 18-24

REQ-HOME-CTA-001 test uses arrow-glyph + EMPEZAR ENTRENAMIENTO as test label.
Production now passes EMPEZAR ENTRENAMIENTO without the glyph. Test passes but
label is inconsistent with production. Consider updating. Non-blocking.

---

**SUG-002 -- design.md section 4.1 includes unused palette line in normative shape**

File: openspec/changes/home-shell/design.md section 4.1

Normative shape has final palette = AppPalette.of(context) in HomeScreen.build.
Final impl removed this (apply-progress deviation 1). Update to match. Non-blocking.

---

## REQ Coverage Matrix

| REQ | Covering test | Status |
|---|---|---|
| REQ-HOME-SCREEN-001 data | AsyncData(profile) -> HomeHeader + cards once | PASS |
| REQ-HOME-SCREEN-001 loading | AsyncLoading -> no HomeHeader, skeleton present | PASS |
| REQ-HOME-SCREEN-001 error | AsyncError -> no FlutterError, HOLA! shown | PASS |
| REQ-HOME-SCREEN-002 | No Scaffold/AppBackground/SafeArea inside HomeScreen | PASS |
| REQ-HOME-SCREEN-003 non-null | AsyncData(profile) -> header.profile equals profile | PASS |
| REQ-HOME-SCREEN-003 null | AsyncData(null) -> header.profile is null | PASS (partial) |
| REQ-HOME-HEADER-001 named | Named greeting uppercased -- HOLA, MARTIN! | PASS |
| REQ-HOME-HEADER-001 case | Lowercase displayName uppercased -- HOLA, ANA! | PASS |
| REQ-HOME-HEADER-002 null profile | Null profile -> HOLA! fallback | PASS |
| REQ-HOME-HEADER-002 null displayName | (missing test) | WARNING WARN-001 |
| REQ-HOME-HEADER-003 | Non-null avatarUrl -> CachedNetworkImage found | PASS |
| REQ-HOME-HEADER-004 initials M | Null avatarUrl + displayName -> initials M | PASS |
| REQ-HOME-HEADER-004 initials ? | Null profile -> initials ? | PASS |
| REQ-HOME-EMPEZAR-001 strings | All 6 hardcoded strings present | PASS (spec outdated CRIT-001) |
| REQ-HOME-EMPEZAR-001 CTA | HomeCTAButton found + label + TreinoIcon.play leadingIcon | PASS |
| REQ-HOME-EMPEZAR-002 | TreinoIcon.tabWorkout and TreinoIcon.clock in stat row | PASS |
| REQ-HOME-EMPEZAR-003 | Card bgCard + r=20 + border non-null | PASS |
| REQ-HOME-EMPEZAR-004 | Tap no-op -- no exception, no navigation | PASS |
| REQ-HOME-SEMANA-001 title | Title ESTA SEMANA found | PASS |
| REQ-HOME-SEMANA-001 body | Placeholder body, no streak, no SVG | PASS |
| REQ-HOME-SEMANA-002 | Card bgCard + r=20 + border | PASS |
| REQ-HOME-CTA-001 | Renders label text | PASS |
| REQ-HOME-CTA-002 | Tap fires onPressed exactly once | PASS |
| REQ-HOME-CTA-003 | Null onPressed -- no crash on tap | PASS |
| REQ-HOME-CTA-004 | StadiumBorder + accent bg + Barlow Condensed w700 | PASS |
| REQ-HOME-CTA-005 | leadingIcon present/absent | PASS |
| REQ-HOME-PROVIDER-001 | displayName + avatarUrl -> correct greeting + CachedNetworkImage | PASS |
| REQ-HOME-PROVIDER-002 | Partial via SCREEN-003 null (no visual assertions) | PARTIAL WARN-002 |
| REQ-HOME-PROVIDER-003 | AsyncLoading -> skeleton visible, cards visible | PASS |
| REQ-HOME-PROVIDER-004 | AsyncError -> HOLA! shown, no error text | PASS |

---

## Task Completion

| Task | Marker | Files verified | Status |
|---|---|---|---|
| TASK-001 | [x] | pubspec.yaml cached_network_image, test dirs exist | DONE |
| TASK-002a | [x] | home_cta_button_test.dart exists, 5 tests | DONE |
| TASK-002b | [x] | home_cta_button.dart exists, 5/5 green | DONE |
| TASK-003a | [x] | esta_semana_card_test.dart exists, 3 tests | DONE |
| TASK-003b | [x] | esta_semana_card.dart exists, 3/3 green | DONE |
| TASK-004a | [x] | empezar_entrenamiento_card_test.dart exists, 5 tests | DONE (CRIT-001) |
| TASK-004b | [x] | empezar_entrenamiento_card.dart exists, 5/5 green | DONE |
| TASK-005a | [x] | home_header_test.dart exists, 5 tests (WARN-001) | DONE |
| TASK-005b | [x] | home_header.dart exists, 5/5 green | DONE |
| TASK-006a | [x] | home_screen_test.dart exists, 7 tests | DONE |
| TASK-006b | [x] | home_screen.dart rewritten, 7/7 green | DONE |
| TASK-007 | [x] | dart format clean -- verified | DONE |
| TASK-008 | [x] | flutter analyze No issues found -- verified | DONE |
| TASK-009 | [~] | 246/246 green, smoke run MANUAL-PENDING | PARTIAL |

---

## Convention Enforcement

| Check | Result |
|---|---|
| No HEX literals in lib/features/home/ | CLEAN |
| No PhosphorIcons.* in lib/features/home/ | CLEAN |
| No Theme.of(context).textTheme.* in lib/features/home/ | CLEAN |
| No forbidden spacing (16, 24) in lib/features/home/ | CLEAN |
| No forbidden radii in lib/features/home/ | CLEAN -- only r=20 and StadiumBorder |
| router.dart unchanged vs main | CLEAN |
| treino_bottom_bar.dart unchanged vs main | CLEAN |
| No Session/Routine imports in lib/features/home/ | CLEAN |
| profile_setup diff vs main | FORMAT-ONLY -- dart format whitespace, no logic |

---

## Out-of-Scope Leak Check

| Concern | Verdict |
|---|---|
| CTA wired to real navigation | CLEAN -- onPressed: null confirmed |
| Real Session/Routine model imports | CLEAN |
| Streak/muscle map/SVG in EstaSemanaCard | CLEAN -- SvgPicture absent (test confirms) |
| Changes to router.dart | CLEAN -- no diff vs main |
| Changes to treino_bottom_bar.dart | CLEAN -- no diff vs main |
| Changes to profile providers | CLEAN -- no logic changes |
| Modifications to domain models | CLEAN |

---

## Re-run Results

- flutter analyze: No issues found! (0 errors, 0 warnings, 0 infos)
- flutter test test/features/home/: 26/26 tests passed
- flutter test (full suite): 246/246 tests passed, 0 regressions
- dart format --output=none --set-exit-if-changed .: clean (0 files changed)

---

## Design Contract Conformance

| Element | Expected | Actual | Verdict |
|---|---|---|---|
| HomeScreen is ConsumerWidget | Yes | Yes | PASS |
| Single ref.watch(userProfileProvider) call | Yes | Yes | PASS |
| Uses .when(data: loading: error:) | Yes | Yes | PASS |
| No Scaffold/AppBackground/SafeArea | Yes | Confirmed | PASS |
| HomeHeader signature (key?, required UserProfile? profile) | Yes | Yes | PASS |
| HomeCTAButton API (label, onPressed?, leadingIcon?) | Yes | Yes | PASS |
| EmpezarEntrenamientoCard zero params StatelessWidget | Yes | Yes | PASS |
| EmpezarEntrenamientoCard uses leadingIcon: TreinoIcon.play | Deviation from original | Post-apply fix applied | PASS |
| EstaSemanaCard zero params StatelessWidget | Yes | Yes | PASS |
| _HomeHeaderSkeleton private in home_screen.dart height=56 | Yes | Yes | PASS |
| Card shell: bgCard + r=20 + border 1px | Yes | Confirmed by tests | PASS |
| CTA: StadiumBorder + accent bg + Barlow Condensed w700 | Yes | Confirmed by tests | PASS |
| Spacing values in allowed set {8,12,14,18,20} | Yes | All gaps confirmed | PASS |

---

## Conclusion

The implementation is correct, clean, and well-tested. 246 tests pass with zero regressions.
All three automated quality gates (analyze, format, tests) are green.

CRIT-001 is a documentation inconsistency -- the spec, tasks, and design still reference
the old label string with the arrow glyph. The post-apply fix correctly moved the glyph
to leadingIcon: TreinoIcon.play. Code and test are correct; only artifact text needs updating.

Before opening the PR:
1. Fix CRIT-001: update spec.md, tasks.md, design.md (~5 min).
2. Fix WARN-001: add header test for UserProfile(displayName: null) -> HOLA! (~5 min).
3. Fix WARN-002: extend screen test 6 with AsyncData(null) visual assertions (~5 min).
4. Complete WARN-003: manual smoke run on device/simulator.

**Verdict: PASS WITH WARNINGS**
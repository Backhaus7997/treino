# Tasks: i18n-localization (Fase 6 Etapa 8)

**Change**: i18n-localization  
**Phase**: Fase 6 Etapa 8  
**Date**: 2026-06-09  
**Delivery**: 3 PRs stacked-to-main (ADR-I18N-009)  
**Strict TDD**: ACTIVE — RED commit then GREEN commit, always separate  
**Total tasks**: 47  

---

## PR#1 — Infra + Auth (~200 LOC, ~14 commits)

> Scope: pubspec, l10n.yaml, ARB skeletons, MaterialApp wiring, AuthStrings migration, AuthFailure exclusion. Nothing else.  
> REQ-I18N-DELIVERY-001 · SCENARIO-786

---

### T-I18N-001 — Add flutter_localizations + intl dependencies

- **Status**: [x] DONE — intl ^0.20.0 (table_calendar requires ^0.20.0)
- **PR**: #1
- **Files**: `pubspec.yaml`
- **Acceptance criteria**: `flutter pub get` exits 0; `flutter_localizations` and `intl: ^0.19.0` appear in pubspec.lock without version conflict
- **Linked REQ**: REQ-I18N-INFRA-001
- **Linked SCENARIOs**: SCENARIO-748, SCENARIO-749
- **Commit type**: `chore(i18n)` (no RED/GREEN — config change, not code logic)

---

### T-I18N-002 — Create l10n.yaml at repo root

- **Status**: [x] DONE — synthetic-package removed (deprecated), generate: true added
- **PR**: #1
- **Files**: `l10n.yaml`
- **Acceptance criteria**: File contains exactly `arb-dir: lib/l10n`, `template-arb-file: intl_es_AR.arb`, `output-localization-file: app_l10n.dart`, `output-class: AppL10n`, `nullable-getter: false`, `synthetic-package: false`; `flutter gen-l10n` exits 0
- **Linked REQ**: REQ-I18N-INFRA-002
- **Linked SCENARIOs**: SCENARIO-750
- **Linked ADR**: ADR-I18N-004
- **Commit type**: `chore(i18n)` (config)

---

### T-I18N-003 — Create ARB skeleton files

- **Status**: [x] DONE — intl_es.arb added as required base locale fallback
- **PR**: #1
- **Files**: `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`
- **Acceptance criteria**: Both files contain only `@@locale` header (`"@@locale": "es_AR"` and `"@@locale": "en"` respectively); `flutter gen-l10n` exits 0 and produces `lib/l10n/app_l10n.dart`; `AppL10n` class is importable; `AppL10n.supportedLocales` contains both `Locale('es','AR')` and `Locale('en')`
- **Linked REQ**: REQ-I18N-INFRA-003, REQ-I18N-INFRA-006, REQ-I18N-CONTENT-007
- **Linked SCENARIOs**: SCENARIO-751, SCENARIO-752, SCENARIO-757, SCENARIO-768
- **Commit type**: `chore(i18n)` (scaffolding)

---

### T-I18N-004 — RED: locale resolution widget test

- **Status**: [x] DONE
- **PR**: #1
- **Files**: `test/l10n/locale_resolution_test.dart` (new)
- **Acceptance criteria**: Test file added; `flutter test test/l10n/locale_resolution_test.dart` FAILS (AppL10n not wired to MaterialApp yet). Test covers: es-AR device → es-AR strings (SCENARIO-755), fr-FR device → falls back to es-AR (SCENARIO-756)
- **Linked REQ**: REQ-I18N-INFRA-004, REQ-I18N-INFRA-005
- **Linked SCENARIOs**: SCENARIO-753, SCENARIO-754, SCENARIO-755, SCENARIO-756
- **Linked ADR**: ADR-I18N-005
- **Commit type**: `test(i18n): RED — locale resolution to es-AR`

---

### T-I18N-005 — GREEN: Wire MaterialApp with AppL10n delegates + localeResolutionCallback

- **Status**: [x] DONE — locale_resolver.dart pure function extracted for testability
- **PR**: #1
- **Dependencies**: T-I18N-004 must be RED first
- **Files**: `lib/app/app.dart` (or wherever `MaterialApp` lives)
- **Acceptance criteria**: `MaterialApp` registers `AppL10n.localizationsDelegates`, `AppL10n.supportedLocales`, and `localeResolutionCallback` that forces `Locale('es','AR')` for any non-supported locale; locale resolution test from T-I18N-004 passes; `flutter analyze` 0 issues
- **Linked REQ**: REQ-I18N-INFRA-004, REQ-I18N-INFRA-005
- **Linked SCENARIOs**: SCENARIO-753, SCENARIO-754, SCENARIO-755, SCENARIO-756
- **Linked ADR**: ADR-I18N-005
- **Commit type**: `feat(i18n): GREEN — MaterialApp locale wiring`

---

### T-I18N-006 — RED: AuthStrings call sites test

- **Status**: [x] DONE
- **PR**: #1
- **Dependencies**: T-I18N-005 must be GREEN
- **Files**: `test/features/auth/auth_strings_migration_test.dart` (new)
- **Acceptance criteria**: Widget tests assert that each auth string render site reads from `AppL10n.of(context)` rather than `AuthStrings`; tests FAIL because `auth_strings.dart` still exists and call sites haven't changed
- **Linked REQ**: REQ-I18N-CONTENT-001
- **Linked SCENARIOs**: SCENARIO-759, SCENARIO-760
- **Linked ADR**: ADR-I18N-010
- **Commit type**: `test(i18n): RED — AuthStrings migration`

---

### T-I18N-007 — GREEN: Migrate AuthStrings to ARB + update call sites + delete file

- **Status**: [x] DONE — 42 keys migrated, auth_strings.dart deleted, existing tests updated with AppL10n delegates
- **PR**: #1
- **Dependencies**: T-I18N-006 must be RED first
- **Files**: `lib/l10n/intl_es_AR.arb` (add auth keys), `lib/l10n/intl_en.arb` (add empty scaffold keys), `lib/features/auth/presentation/**` (all call sites), `lib/features/auth/presentation/auth_strings.dart` (DELETE)
- **Acceptance criteria**: All `AuthStrings.X` call sites replaced with `AppL10n.of(context).authX`; verbatim string values preserved; `auth_strings.dart` deleted; `flutter gen-l10n` exits 0; auth_strings_migration_test passes; existing auth widget tests unchanged; `flutter analyze` 0 issues; `const` removed where needed (REQ-I18N-REFACTOR-002)
- **Linked REQ**: REQ-I18N-CONTENT-001, REQ-I18N-REFACTOR-002, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-759, SCENARIO-760, SCENARIO-778, SCENARIO-780
- **Linked ADR**: ADR-I18N-001, ADR-I18N-006, ADR-I18N-008
- **Commit type**: `feat(i18n): GREEN — AuthStrings migration + deletion`

---

### T-I18N-008 — RED: AuthFailure.userMessage exclusion test

- **Status**: [x] DONE — kAuthFailureI18nExclusionNote sentinel makes exclusion testable
- **PR**: #1
- **Dependencies**: T-I18N-007 must be GREEN
- **Files**: `test/features/auth/auth_failure_exclusion_test.dart` (new, or assert within existing login_screen_test.dart review)
- **Acceptance criteria**: Test asserts `auth_failure.dart` contains exclusion comment `// i18n: intentional exclusion — domain layer cannot receive BuildContext`; test FAILS because comment not yet added. `login_screen_test.dart` L152 and L178 assertions remain syntactically present and referenced
- **Linked REQ**: REQ-I18N-CONTENT-008, REQ-I18N-TEST-002
- **Linked SCENARIOs**: SCENARIO-769, SCENARIO-782
- **Linked ADR**: ADR-I18N-002
- **Commit type**: `test(i18n): RED — AuthFailure exclusion comment`

---

### T-I18N-009 — GREEN: Add AuthFailure.userMessage exclusion comment

- **Status**: [x] DONE
- **PR**: #1
- **Dependencies**: T-I18N-008 must be RED first
- **Files**: `lib/features/auth/domain/auth_failure.dart`
- **Acceptance criteria**: Exclusion comment added; no ARB keys added for these strings; `login_screen_test.dart` passes unchanged; `flutter test` 100% pass; `flutter analyze` 0 issues; PR#1 LOC ≤ 200
- **Linked REQ**: REQ-I18N-CONTENT-008, REQ-I18N-TEST-001, REQ-I18N-TEST-002, REQ-I18N-TEST-004
- **Linked SCENARIOs**: SCENARIO-769, SCENARIO-781, SCENARIO-782, SCENARIO-785
- **Linked ADR**: ADR-I18N-002
- **Commit type**: `chore(i18n): GREEN — AuthFailure exclusion comment`

---

**PR#1 summary**: 9 tasks · ~14 commits (2 chore config + 3 RED + 3 GREEN + 1 chore GREEN) · LOC ≤ 200

---

## PR#2 — Coach + Agenda + Workout (~350 LOC, ~22 commits)

> Scope: agenda_formatters extraction, CoachStrings/AgendaStrings/WorkoutStrings migration, ICU plurals/interpolations, trainer_dashboard inline strings.  
> REQ-I18N-DELIVERY-002 · SCENARIO-787

---

### Sub-task 2.1 — Extract agenda_formatters.dart (ADR-I18N-003, MUST run before AgendaStrings migration)

---

### T-I18N-010 — RED: agenda_formatters.dart extraction test

- **Status**: [ ]
- **PR**: #2
- **Files**: `test/features/coach/presentation/agenda_formatters_test.dart` (new)
- **Acceptance criteria**: Tests call `AgendaFormatters.formatDate`, `AgendaFormatters.formatTime`, `AgendaFormatters.dayOfWeekLabels` — fail because class doesn't exist yet
- **Linked REQ**: REQ-I18N-REFACTOR-001
- **Linked SCENARIOs**: SCENARIO-776, SCENARIO-777
- **Linked ADR**: ADR-I18N-003
- **Commit type**: `test(i18n): RED — agenda_formatters extraction`

---

### T-I18N-011 — GREEN: Create agenda_formatters.dart + update call sites

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-010 must be RED first
- **Files**: `lib/features/coach/presentation/agenda_formatters.dart` (new), all files that import `AgendaStrings.formatDate/formatTime/dayOfWeekLabels`
- **Acceptance criteria**: `formatDate`, `formatTime`, `dayOfWeekLabels` moved to new file; all former call sites updated to import from `agenda_formatters.dart`; agenda_formatters_test passes; existing agenda widget tests pass; `flutter analyze` 0 issues. `AgendaStrings` class still exists at end of this task (deletion comes in T-I18N-016)
- **Linked REQ**: REQ-I18N-REFACTOR-001
- **Linked SCENARIOs**: SCENARIO-776, SCENARIO-777
- **Linked ADR**: ADR-I18N-003
- **Commit type**: `refactor(i18n): GREEN — extract agenda_formatters.dart`

---

### Sub-task 2.2 — Migrate CoachStrings (~30 keys)

---

### T-I18N-012 — RED: CoachStrings migration test

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-011 must be GREEN
- **Files**: `test/features/coach/presentation/coach_strings_migration_test.dart` (new)
- **Acceptance criteria**: Widget tests assert coach string render sites use `AppL10n.of(context).coachX`; FAIL because `CoachStrings` still wired
- **Linked REQ**: REQ-I18N-CONTENT-002
- **Linked SCENARIOs**: SCENARIO-761
- **Commit type**: `test(i18n): RED — CoachStrings migration`

---

### T-I18N-013 — GREEN: Migrate CoachStrings to ARB + delete file

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-012 must be RED first
- **Files**: `lib/l10n/intl_es_AR.arb` (add ~30 coach keys), `lib/l10n/intl_en.arb` (empty scaffold), `lib/features/coach/presentation/**` (call sites), `lib/features/coach/presentation/coach_strings.dart` (DELETE)
- **Acceptance criteria**: ~30 keys added to ARB (camelCase `coachX` prefix); all call sites use `AppL10n.of(context).coachX`; `coach_strings.dart` deleted; coach_strings_migration_test passes; `flutter analyze` 0 issues; `const` removed where needed
- **Linked REQ**: REQ-I18N-CONTENT-002, REQ-I18N-REFACTOR-002, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-761, SCENARIO-778, SCENARIO-780
- **Linked ADR**: ADR-I18N-006, ADR-I18N-008
- **Commit type**: `feat(i18n): GREEN — CoachStrings migration + deletion`

---

### Sub-task 2.3 — Migrate AgendaStrings string keys + ICU interpolations

---

### T-I18N-014 — RED: AgendaStrings migration test (string keys)

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-013 must be GREEN; T-I18N-011 must be GREEN (formatters already extracted)
- **Files**: `test/features/coach/presentation/agenda_strings_migration_test.dart` (new)
- **Acceptance criteria**: Tests assert string key render sites use `AppL10n.of(context).agendaX`; FAIL because `AgendaStrings` still wired for string keys
- **Linked REQ**: REQ-I18N-CONTENT-003
- **Linked SCENARIOs**: SCENARIO-762, SCENARIO-763
- **Commit type**: `test(i18n): RED — AgendaStrings string key migration`

---

### T-I18N-015 — RED: AgendaStrings ICU interpolation tests

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-014 must be RED
- **Files**: `test/features/coach/presentation/agenda_strings_migration_test.dart` (extend)
- **Acceptance criteria**: Additional test cases: `agendaBookingConfirmBody(date: someDate)` → verbatim match (SCENARIO-774); `agendaSlotBookedByLabel(name: 'María')` → contains 'María' (SCENARIO-775); FAIL because keys don't exist in ARB yet
- **Linked REQ**: REQ-I18N-ICU-004, REQ-I18N-ICU-005
- **Linked SCENARIOs**: SCENARIO-774, SCENARIO-775
- **Linked ADR**: ADR-I18N-007
- **Commit type**: `test(i18n): RED — AgendaStrings ICU interpolations`

---

### T-I18N-016 — GREEN: Migrate AgendaStrings to ARB + add ICU keys + delete file

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-015 must be RED first
- **Files**: `lib/l10n/intl_es_AR.arb` (add agenda string keys + ICU interpolation keys with `@key` blocks), `lib/l10n/intl_en.arb` (empty scaffold matching ICU shape), `lib/features/coach/presentation/**` (call sites for string keys), `lib/features/coach/presentation/agenda_strings.dart` (DELETE)
- **Acceptance criteria**: All string keys from AgendaStrings (minus formatters) in ARB; `agendaBookingConfirmBody` uses DateTime placeholder per REQ-I18N-ICU-004; `agendaSlotBookedByLabel` uses String placeholder per REQ-I18N-ICU-005; `agenda_strings.dart` deleted; all agenda tests pass; `flutter analyze` 0 issues
- **Linked REQ**: REQ-I18N-CONTENT-003, REQ-I18N-ICU-004, REQ-I18N-ICU-005, REQ-I18N-REFACTOR-002, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-762, SCENARIO-763, SCENARIO-774, SCENARIO-775, SCENARIO-778, SCENARIO-780
- **Linked ADR**: ADR-I18N-006, ADR-I18N-007, ADR-I18N-008
- **Commit type**: `feat(i18n): GREEN — AgendaStrings migration + deletion`

---

### Sub-task 2.4 — Migrate WorkoutStrings (~50 keys + ICU)

---

### T-I18N-017 — RED: WorkoutStrings ICU plural tests

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-016 must be GREEN
- **Files**: `test/features/workout/presentation/workout_strings_migration_test.dart` (new)
- **Acceptance criteria**: Tests cover: `workoutPickerAddButton(count: 1)` → "Agregar 1 ejercicio" (SCENARIO-770); `workoutPickerAddButton(count: 3)` → "Agregar 3 ejercicios" (SCENARIO-771); `workoutHistorialShowMore(n: 5)` → "Ver 5 más" (SCENARIO-772); `workoutPickerSheetApply(n: 2)` → "APLICAR (2)" (SCENARIO-773); FAIL because keys don't exist in ARB
- **Linked REQ**: REQ-I18N-ICU-001, REQ-I18N-ICU-002, REQ-I18N-ICU-003, REQ-I18N-TEST-003
- **Linked SCENARIOs**: SCENARIO-770, SCENARIO-771, SCENARIO-772, SCENARIO-773, SCENARIO-783, SCENARIO-784
- **Linked ADR**: ADR-I18N-007
- **Commit type**: `test(i18n): RED — WorkoutStrings ICU plurals + interpolations`

---

### T-I18N-018 — RED: WorkoutStrings remaining string keys test

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-017 must be RED
- **Files**: `test/features/workout/presentation/workout_strings_migration_test.dart` (extend)
- **Acceptance criteria**: Tests assert remaining ~46 static string render sites use `AppL10n.of(context).workoutX`; FAIL because `WorkoutStrings` still wired
- **Linked REQ**: REQ-I18N-CONTENT-004
- **Linked SCENARIOs**: SCENARIO-764
- **Commit type**: `test(i18n): RED — WorkoutStrings string key migration`

---

### T-I18N-019 — GREEN: Migrate WorkoutStrings to ARB + add ICU + delete file

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-018 must be RED first
- **Files**: `lib/l10n/intl_es_AR.arb` (add ~50 workout keys: ICU plural `workoutPickerAddButton`, interpolation `workoutHistorialShowMore`, interpolation `workoutPickerSheetApply`, remaining static keys), `lib/l10n/intl_en.arb` (matching empty scaffold with ICU shape), `lib/features/workout/presentation/**` (all call sites), `lib/features/workout/presentation/workout_strings.dart` (DELETE)
- **Acceptance criteria**: ICU: `workoutPickerAddButton` uses `{count, plural, =1{Agregar 1 ejercicio} other{Agregar {count} ejercicios}}`; `workoutHistorialShowMore` uses `"Ver {n} más"` with int placeholder; `workoutPickerSheetApply` uses `"APLICAR ({n})"` with int placeholder; `workout_strings.dart` deleted; all workout tests pass including ICU paths; `flutter analyze` 0 issues; `const` removed where needed
- **Linked REQ**: REQ-I18N-CONTENT-004, REQ-I18N-ICU-001, REQ-I18N-ICU-002, REQ-I18N-ICU-003, REQ-I18N-REFACTOR-002, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-764, SCENARIO-770, SCENARIO-771, SCENARIO-772, SCENARIO-773, SCENARIO-778, SCENARIO-780, SCENARIO-783, SCENARIO-784
- **Linked ADR**: ADR-I18N-006, ADR-I18N-007, ADR-I18N-008
- **Commit type**: `feat(i18n): GREEN — WorkoutStrings migration + deletion`

---

### Sub-task 2.5 — trainer_dashboard_tab inline strings

---

### T-I18N-020 — RED: trainer_dashboard_tab inline string test

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-019 must be GREEN
- **Files**: `test/features/coach/presentation/trainer_dashboard_tab_test.dart` (new or extend)
- **Acceptance criteria**: Widget test confirms `trainer_dashboard_tab.dart` renders no hardcoded Spanish literals (including `'HOLA, $name'` interpolation); FAIL because literals still present
- **Linked REQ**: REQ-I18N-CONTENT-005
- **Linked SCENARIOs**: SCENARIO-765
- **Commit type**: `test(i18n): RED — trainer_dashboard_tab inline strings`

---

### T-I18N-021 — GREEN: Migrate trainer_dashboard_tab inline strings

- **Status**: [ ]
- **PR**: #2
- **Dependencies**: T-I18N-020 must be RED first
- **Files**: `lib/features/coach/presentation/trainer_dashboard_tab.dart`, `lib/l10n/intl_es_AR.arb` (add ~15 keys including `coachDashboardGreeting` with name placeholder), `lib/l10n/intl_en.arb` (empty scaffold)
- **Acceptance criteria**: All ~15 user-visible literals replaced with `AppL10n.of(context).X`; `'HOLA, $name'` becomes ARB key with String placeholder; trainer_dashboard test passes; `flutter analyze` 0 issues; PR#2 LOC ≤ 350
- **Linked REQ**: REQ-I18N-CONTENT-005, REQ-I18N-TEST-001, REQ-I18N-TEST-004
- **Linked SCENARIOs**: SCENARIO-765, SCENARIO-781, SCENARIO-785, SCENARIO-787
- **Linked ADR**: ADR-I18N-006
- **Commit type**: `feat(i18n): GREEN — trainer_dashboard_tab inline migration`

---

**PR#2 summary**: 12 tasks · ~22 commits · LOC ≤ 350

---

## PR#3 — Inline String Batch (~250 LOC, ~26 commits)

> Scope: profile, profile_setup, reviews, plantillas, app.dart FCM SnackBar. After all 3 PRs: zero *_strings.dart files under lib/.  
> REQ-I18N-DELIVERY-003 · SCENARIO-788

---

### T-I18N-022 — RED: app.dart FCM SnackBar 'Ver' test

- **Status**: [ ]
- **PR**: #3
- **Files**: `test/app/app_snackbar_test.dart` (new)
- **Acceptance criteria**: Widget test confirms FCM SnackBar action label comes from `AppL10n.of(context).appFcmSnackBarAction`; FAIL because literal 'Ver' still hardcoded
- **Linked REQ**: REQ-I18N-CONTENT-006
- **Linked SCENARIOs**: SCENARIO-767
- **Commit type**: `test(i18n): RED — app.dart FCM SnackBar string`

---

### T-I18N-023 — GREEN: Migrate app.dart FCM SnackBar

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-022 must be RED first
- **Files**: `lib/app/app.dart`, `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`
- **Acceptance criteria**: `'Ver'` literal replaced with `AppL10n.of(context).appFcmSnackBarAction`; ARB key added; test passes; `flutter analyze` 0 issues
- **Linked REQ**: REQ-I18N-CONTENT-006, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-767, SCENARIO-780
- **Commit type**: `feat(i18n): GREEN — app.dart FCM SnackBar migration`

---

### T-I18N-024 — RED: profile_cuenta_section inline strings test

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-023 must be GREEN
- **Files**: `test/features/profile/presentation/profile_cuenta_section_test.dart` (new or extend)
- **Acceptance criteria**: Widget test asserts 6+ string render sites use `AppL10n.of(context).profileX`; FAIL because `// i18n: Fase 6 Etapa 3` literals still present
- **Linked REQ**: REQ-I18N-CONTENT-006
- **Linked SCENARIOs**: SCENARIO-766
- **Commit type**: `test(i18n): RED — profile_cuenta_section inline strings`

---

### T-I18N-025 — GREEN: Migrate profile_cuenta_section

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-024 must be RED first
- **Files**: `lib/features/profile/presentation/profile_cuenta_section.dart`, `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`
- **Acceptance criteria**: All `// i18n: Fase 6 Etapa 3` literals replaced; ARB keys added (camelCase `profileX`); test passes; `flutter analyze` 0 issues
- **Linked REQ**: REQ-I18N-CONTENT-006, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-766, SCENARIO-780
- **Linked ADR**: ADR-I18N-006
- **Commit type**: `feat(i18n): GREEN — profile_cuenta_section migration`

---

### T-I18N-026 — RED: profile_edit_personal_screen validator strings test

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-025 must be GREEN
- **Files**: `test/features/profile/presentation/profile_edit_personal_screen_test.dart` (new or extend)
- **Acceptance criteria**: Widget test triggers form validation and asserts error messages come from `AppL10n.of(context).profileX`; FAIL because 4 validator strings still hardcoded
- **Linked REQ**: REQ-I18N-CONTENT-006
- **Linked SCENARIOs**: SCENARIO-766
- **Commit type**: `test(i18n): RED — profile_edit_personal_screen validators`

---

### T-I18N-027 — GREEN: Migrate profile_edit_personal_screen

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-026 must be RED first
- **Files**: `lib/features/profile/presentation/profile_edit_personal_screen.dart`, `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`
- **Acceptance criteria**: 4 validator string literals replaced; ARB keys added; test passes; `flutter analyze` 0 issues
- **Linked REQ**: REQ-I18N-CONTENT-006, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-766, SCENARIO-780
- **Commit type**: `feat(i18n): GREEN — profile_edit_personal_screen migration`

---

### T-I18N-028 — RED: eliminar_cuenta_sheet inline strings test

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-027 must be GREEN
- **Files**: `test/features/profile/presentation/widgets/eliminar_cuenta_sheet_test.dart` (new)
- **Acceptance criteria**: Widget test asserts 7 literals in sheet use `AppL10n.of(context).profileX`; FAIL because literals still hardcoded
- **Linked REQ**: REQ-I18N-CONTENT-006
- **Linked SCENARIOs**: SCENARIO-766
- **Commit type**: `test(i18n): RED — eliminar_cuenta_sheet inline strings`

---

### T-I18N-029 — GREEN: Migrate eliminar_cuenta_sheet

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-028 must be RED first
- **Files**: `lib/features/profile/presentation/widgets/eliminar_cuenta_sheet.dart`, `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`
- **Acceptance criteria**: 7 literals replaced; ARB keys added; test passes; `flutter analyze` 0 issues
- **Linked REQ**: REQ-I18N-CONTENT-006, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-766, SCENARIO-780
- **Commit type**: `feat(i18n): GREEN — eliminar_cuenta_sheet migration`

---

### T-I18N-030 — RED: review_bottom_sheet inline strings test

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-029 must be GREEN
- **Files**: `test/features/reviews/presentation/widgets/review_bottom_sheet_test.dart` (new or extend)
- **Acceptance criteria**: Widget test asserts 5 `// i18n: Fase 6 Etapa 7` literals use `AppL10n.of(context).reviewX`; FAIL because literals still present
- **Linked REQ**: REQ-I18N-CONTENT-006
- **Linked SCENARIOs**: SCENARIO-767
- **Commit type**: `test(i18n): RED — review_bottom_sheet inline strings`

---

### T-I18N-031 — GREEN: Migrate review_bottom_sheet

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-030 must be RED first
- **Files**: `lib/features/reviews/presentation/widgets/review_bottom_sheet.dart`, `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`
- **Acceptance criteria**: 5 literals replaced; ARB keys added; test passes; `flutter analyze` 0 issues
- **Linked REQ**: REQ-I18N-CONTENT-006, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-767, SCENARIO-780
- **Commit type**: `feat(i18n): GREEN — review_bottom_sheet migration`

---

### T-I18N-032 — RED: plantillas_section inline strings test

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-031 must be GREEN
- **Files**: `test/features/workout/presentation/widgets/plantillas_section_test.dart` (new or extend)
- **Acceptance criteria**: Widget test asserts 2 literals use `AppL10n.of(context).workoutX`; FAIL because literals still hardcoded
- **Linked REQ**: REQ-I18N-CONTENT-006
- **Linked SCENARIOs**: SCENARIO-767
- **Commit type**: `test(i18n): RED — plantillas_section inline strings`

---

### T-I18N-033 — GREEN: Migrate plantillas_section

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-032 must be RED first
- **Files**: `lib/features/workout/presentation/widgets/plantillas_section.dart`, `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`
- **Acceptance criteria**: 2 literals replaced; ARB keys added; test passes; `flutter analyze` 0 issues
- **Linked REQ**: REQ-I18N-CONTENT-006, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-767, SCENARIO-780
- **Commit type**: `feat(i18n): GREEN — plantillas_section migration`

---

### T-I18N-034 — RED: profile_setup_flow title strings test

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-033 must be GREEN
- **Files**: `test/features/profile_setup/presentation/profile_setup_flow_test.dart` (new or extend)
- **Acceptance criteria**: Widget test asserts 4 title strings use `AppL10n.of(context).profileSetupX`; FAIL because literals still hardcoded
- **Linked REQ**: REQ-I18N-CONTENT-006
- **Linked SCENARIOs**: SCENARIO-766
- **Commit type**: `test(i18n): RED — profile_setup_flow title strings`

---

### T-I18N-035 — GREEN: Migrate profile_setup_flow

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: T-I18N-034 must be RED first
- **Files**: `lib/features/profile_setup/presentation/profile_setup_flow.dart`, `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`
- **Acceptance criteria**: 4 title strings replaced; ARB keys added; test passes; `flutter analyze` 0 issues
- **Linked REQ**: REQ-I18N-CONTENT-006, REQ-I18N-REFACTOR-004
- **Linked SCENARIOs**: SCENARIO-766, SCENARIO-780
- **Commit type**: `feat(i18n): GREEN — profile_setup_flow migration`

---

### T-I18N-036 — Final gate: zero *_strings.dart + analyzer + all tests

- **Status**: [ ]
- **PR**: #3
- **Dependencies**: All previous tasks in PR#3 must be GREEN
- **Files**: none (validation only)
- **Acceptance criteria**: `fd '*_strings.dart' lib/` returns empty (REQ-I18N-REFACTOR-003); `flutter analyze` exits 0 (REQ-I18N-TEST-004); `flutter test` 100% pass (REQ-I18N-TEST-001); `intl_en.arb` has identical key set to `intl_es_AR.arb` with all values `""` (REQ-I18N-CONTENT-007); PR#3 LOC ≤ 250 (SCENARIO-788)
- **Linked REQ**: REQ-I18N-REFACTOR-003, REQ-I18N-CONTENT-007, REQ-I18N-TEST-001, REQ-I18N-TEST-004
- **Linked SCENARIOs**: SCENARIO-768, SCENARIO-779, SCENARIO-781, SCENARIO-785, SCENARIO-788
- **Commit type**: none — this is a checklist gate, no commit

---

**PR#3 summary**: 15 tasks · ~26 commits · LOC ≤ 250

---

## Parallelism

All tasks within a PR are strictly sequential (each RED must precede its GREEN; sub-tasks ordered by dependency). PRs themselves are sequential (PR#2 starts from PR#1 merge; PR#3 starts from PR#2 merge) per ADR-I18N-009 stacked-to-main.

| Can run in parallel | No — all sequential within and across PRs |
|---|---|
| Exception | T-I18N-001 + T-I18N-002 (both config, no code dependency on each other) |

---

## Task count summary

| PR | Tasks | Commits (est.) | LOC (est.) |
|---|---|---|---|
| PR#1 | 9 | 14 | ~200 |
| PR#2 | 12 | 22 | ~350 |
| PR#3 | 15 | 26 | ~250 |
| **Total** | **36** | **62** | **~800** |

---

## Review Workload Forecast

| Field | Value |
|---|---|
| Chained PRs recommended | Yes (ADR-I18N-009 — stacked-to-main, all bisectable) |
| 400-line budget risk — PR#1 | Low (~200 LOC) |
| 400-line budget risk — PR#2 | Medium (~350 LOC, within budget) |
| 400-line budget risk — PR#3 | Low (~250 LOC) |
| Estimated total LOC across 3 PRs | ~800 |
| Decision needed before apply | No — ask-on-risk satisfied by 3 natural chained PRs, no single PR exceeds 400 LOC |

---

## Risks

1. **ICU codegen shape mismatch**: `intl_en.arb` ICU placeholder shape must mirror es-AR exactly (including `plural` structure) or codegen fails for English locale. Verify at T-I18N-016 and T-I18N-019.
2. **AuthFailure permanent es-AR lock-in**: ADR-I18N-002 accepted this; future devs may not know. Exclusion comment is the only guard.
3. **const cascade**: ~30 widgets will lose `const`; must verify no perf regressions in hot-path widgets (workout picker, agenda list).
4. **Locale resolution null guard**: `localeResolutionCallback` must handle null or exotic `Locale` inputs without throwing; cover in T-I18N-004/T-I18N-005.
5. **ARB key count sync**: as keys grow across PRs, intl_en.arb must stay in sync; any missed key causes codegen failure on next `flutter gen-l10n` run.

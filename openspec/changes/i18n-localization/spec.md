# i18n-localization Specification

**Change**: i18n-localization
**Phase**: Fase 6 Etapa 8
**Date**: 2026-06-09
**Artifact store**: hybrid
**Scenario range**: SCENARIO-748 – SCENARIO-791

---

## Purpose

Formal setup of `flutter_localizations` + `intl ^0.19.0` and migration of ~130 hardcoded user-facing strings to ARB files. Approach A — Replace Direct: all `*_strings.dart` classes are deleted; call sites route through `AppL10n.of(context)`. es-AR is the default and only fully-populated locale. English ships as empty scaffold. Pure refactor — zero functional delta.

---

## Closed decisions (from proposal open questions)

| # | Decision | Value |
|---|---|---|
| OQ-1 | ARB key naming | camelCase (matches Dart codegen symbols) |
| OQ-2 | Key namespacing | Flat with feature prefix (e.g. `authWelcomeTitle`, `workoutPickerAddButton`) |
| OQ-3 | ARB metadata | `@@locale` mandatory in both files; `@key` with `placeholders` block required for every parameterized key |
| OQ-4 | Const widget policy | Remove `const` at each affected call site; zero analyzer warnings at PR close |
| OQ-5 | ICU plural test strategy | One scenario per ICU key covering `=1` path and `other` path |
| OQ-6 | AuthFailure test contract | `login_screen_test.dart` assertions remain unchanged; no ARB for `AuthFailure.userMessage` |

---

## REQ-I18N-INFRA Requirements

### REQ-I18N-INFRA-001 — Dependency Setup

The project MUST add `flutter_localizations: { sdk: flutter }` to `dependencies` and `intl: ^0.19.0` to `dependencies` in `pubspec.yaml`. No other new dependencies are permitted.

**Acceptance criteria**:
- `pubspec.yaml` contains `flutter_localizations` under `flutter:` SDK dependency.
- `pubspec.yaml` contains `intl: ^0.19.0` as a package dependency.
- `flutter pub get` runs without version conflicts.

**Linked scenarios**: SCENARIO-748, SCENARIO-749

---

### REQ-I18N-INFRA-002 — l10n.yaml Configuration

The project MUST contain a `l10n.yaml` file at the repository root with exactly:

```
arb-dir: lib/l10n
template-arb-file: intl_es_AR.arb
output-localization-file: app_l10n.dart
output-class: AppL10n
```

No additional keys are required beyond those four.

**Acceptance criteria**:
- File exists at `l10n.yaml` (project root).
- All four keys are present with the exact values above.
- No `output-dir` override (output goes to `lib/l10n/` by codegen default).

**Linked scenarios**: SCENARIO-750

---

### REQ-I18N-INFRA-003 — Codegen Output

Running `flutter gen-l10n` MUST produce `lib/l10n/app_l10n.dart` containing a class named `AppL10n` with a static `of(BuildContext context)` accessor, a `localizationsDelegates` getter, and a `supportedLocales` getter.

**Acceptance criteria**:
- `lib/l10n/app_l10n.dart` exists after codegen.
- Class `AppL10n` is importable and exposes `AppL10n.of(context)`.
- `AppL10n.localizationsDelegates` is a valid `Iterable<LocalizationsDelegate>`.
- `AppL10n.supportedLocales` contains at least `Locale('es', 'AR')` and `Locale('en')`.

**Linked scenarios**: SCENARIO-751, SCENARIO-752

---

### REQ-I18N-INFRA-004 — MaterialApp Wiring

`MaterialApp` in `lib/app/app.dart` MUST register:

```dart
localizationsDelegates: AppL10n.localizationsDelegates,
supportedLocales: AppL10n.supportedLocales,
```

No `locale` override is set; the app resolves locale from the device OS.

**Acceptance criteria**:
- Both properties are present in the `MaterialApp` constructor call.
- App compiles with `flutter analyze` 0 issues.
- At runtime with a device set to es-AR (or es), `AppL10n.of(context)` resolves without throwing.

**Linked scenarios**: SCENARIO-753, SCENARIO-754

---

### REQ-I18N-INFRA-005 — Default and Fallback Locale

The system MUST default to `es-AR` when the device locale is `es-AR` or any unsupported locale. `es-AR` MUST be the first entry in `supportedLocales`.

**Acceptance criteria**:
- Device locale `es-AR` → `AppL10n.of(context)` returns es-AR strings.
- Device locale `fr` (unsupported) → Flutter falls back to the first supported locale (`es-AR`).
- Device locale `en` → `AppL10n.of(context)` returns en strings (scaffold — empty values acceptable).

**Linked scenarios**: SCENARIO-755, SCENARIO-756

---

### REQ-I18N-INFRA-006 — ARB File Structure and Metadata

Both `lib/l10n/intl_es_AR.arb` and `lib/l10n/intl_en.arb` MUST contain a `@@locale` metadata key. Keys with placeholders MUST include an `@key` metadata block with a `placeholders` map.

**Acceptance criteria**:
- `intl_es_AR.arb` begins with `"@@locale": "es-AR"`.
- `intl_en.arb` begins with `"@@locale": "en"`.
- Every parameterized key (those with `{placeholder}` or ICU plural syntax) has a matching `@keyName` block with `placeholders` defined.

**Linked scenarios**: SCENARIO-757

---

### REQ-I18N-INFRA-007 — ARB Key Naming Convention

All ARB keys MUST use camelCase with a feature prefix matching the source file. Nested namespacing (dot notation) is prohibited because ARB does not support it natively.

**Examples**: `authWelcomeTitle`, `coachClientListTitle`, `workoutPickerAddButton`, `agendaBookingConfirmBody`.

**Acceptance criteria**:
- All keys in `intl_es_AR.arb` and `intl_en.arb` follow `{featurePrefix}{DescriptiveName}` camelCase.
- `flutter gen-l10n` produces valid Dart getters matching each key name.
- No key contains a dot, underscore, or space character.

**Linked scenarios**: SCENARIO-758

---

## REQ-I18N-CONTENT Requirements

### REQ-I18N-CONTENT-001 — AuthStrings Migration

All string constants in `lib/features/auth/presentation/auth_strings.dart` MUST be migrated to `intl_es_AR.arb` with 1:1 verbatim values. `auth_strings.dart` MUST be deleted. Every call site MUST use `AppL10n.of(context).{key}`.

**Acceptance criteria**:
- `auth_strings.dart` does not exist after PR#1.
- All former `AuthStrings.X` call sites compile using `AppL10n.of(context).X`.
- String values in the ARB are character-for-character identical to the originals.
- `flutter analyze` 0 issues; `flutter test` 100% pass.

**Linked scenarios**: SCENARIO-759, SCENARIO-760

---

### REQ-I18N-CONTENT-002 — CoachStrings Migration

All string constants in `lib/features/coach/presentation/coach_strings.dart` MUST be migrated to `intl_es_AR.arb`. `coach_strings.dart` MUST be deleted.

**Acceptance criteria**:
- `coach_strings.dart` does not exist after PR#2.
- All former `CoachStrings.X` call sites compile using `AppL10n.of(context).X`.
- String values are verbatim copies.
- `flutter analyze` 0 issues; `flutter test` 100% pass.

**Linked scenarios**: SCENARIO-761

---

### REQ-I18N-CONTENT-003 — AgendaStrings Migration

All user-facing string constants in `lib/features/coach/presentation/agenda_strings.dart` MUST be migrated to `intl_es_AR.arb`. The non-string utility members (`formatDate`, `formatTime`, `dayOfWeekLabels`) MUST be extracted BEFORE deletion (see REQ-I18N-REFACTOR-001). `agenda_strings.dart` MUST be deleted.

**Acceptance criteria**:
- `agenda_strings.dart` does not exist after PR#2.
- All former `AgendaStrings.X` string call sites compile using `AppL10n.of(context).X`.
- `formatDate`, `formatTime`, `dayOfWeekLabels` are callable from their new location.
- `flutter analyze` 0 issues; `flutter test` 100% pass.

**Linked scenarios**: SCENARIO-762, SCENARIO-763

---

### REQ-I18N-CONTENT-004 — WorkoutStrings Migration

All string constants in `lib/features/workout/presentation/workout_strings.dart` MUST be migrated to `intl_es_AR.arb`, including the four parameterized methods (see REQ-I18N-ICU). `workout_strings.dart` MUST be deleted.

**Acceptance criteria**:
- `workout_strings.dart` does not exist after PR#2.
- All former `WorkoutStrings.X` call sites compile using `AppL10n.of(context).X` or the ICU-generated method.
- `flutter analyze` 0 issues; `flutter test` 100% pass.

**Linked scenarios**: SCENARIO-764

---

### REQ-I18N-CONTENT-005 — Inline String Migration (PR#2 batch)

All inline hardcoded strings in `lib/features/coach/presentation/trainer_dashboard_tab.dart` MUST be migrated to `intl_es_AR.arb` within PR#2.

**Acceptance criteria**:
- No hardcoded string literals remain in `trainer_dashboard_tab.dart` after PR#2 (excluding values already in comments or const identifiers not shown to users).
- Strings interpolating `$name` use an ARB key with a `name` placeholder.
- `flutter analyze` 0 issues.

**Linked scenarios**: SCENARIO-765

---

### REQ-I18N-CONTENT-006 — Inline String Migration (PR#3 batch)

All inline hardcoded strings in the following files MUST be migrated to `intl_es_AR.arb` within PR#3:

- `lib/features/profile/presentation/profile_cuenta_section.dart`
- `lib/features/profile/presentation/profile_edit_personal_screen.dart`
- `lib/features/profile/presentation/widgets/eliminar_cuenta_sheet.dart`
- `lib/features/reviews/presentation/widgets/review_bottom_sheet.dart`
- `lib/app/app.dart` (SnackBar 'Ver' label)
- `lib/features/workout/presentation/widgets/plantillas_section.dart`
- `lib/features/profile_setup/presentation/profile_setup_flow.dart`

**Acceptance criteria**:
- No user-visible hardcoded string literals remain in the listed files after PR#3.
- All migrated strings appear 1:1 in `intl_es_AR.arb`.
- `flutter analyze` 0 issues; `flutter test` 100% pass.

**Linked scenarios**: SCENARIO-766, SCENARIO-767

---

### REQ-I18N-CONTENT-007 — English Scaffold

`lib/l10n/intl_en.arb` MUST contain every key present in `intl_es_AR.arb` with empty string values (`""`). Codegen MUST succeed for both locales.

**Acceptance criteria**:
- `intl_en.arb` key count equals `intl_es_AR.arb` key count (excluding `@@locale` and `@key` metadata).
- All values in `intl_en.arb` are `""`.
- `flutter gen-l10n` completes without error.

**Linked scenarios**: SCENARIO-768

---

### REQ-I18N-CONTENT-008 — AuthFailure.userMessage Exclusion

`lib/features/auth/domain/auth_failure.dart` MUST NOT have its `userMessage` getter migrated to ARB. The getter MUST remain hardcoded es-AR and MUST include the comment:

```
// i18n: intentional exclusion — domain model cannot receive BuildContext.
// See: openspec/changes/i18n-localization/proposal.md — Locked decision #1.
```

**Acceptance criteria**:
- `auth_failure.dart` still contains a `userMessage` getter with hardcoded Spanish strings after all PRs.
- The exclusion comment is present on or immediately above the getter.
- No ARB key exists for any `AuthFailure.userMessage` value.

**Linked scenarios**: SCENARIO-769

---

## REQ-I18N-ICU Requirements

### REQ-I18N-ICU-001 — Picker Add Button Plural

`WorkoutStrings.pickerAddButton(int count)` MUST be replaced with an ICU plural ARB key `workoutPickerAddButton` using `{count, plural, =1{Agregar 1 ejercicio} other{Agregar {count} ejercicios}}`.

**Acceptance criteria**:
- ARB key `workoutPickerAddButton` exists with a `count` placeholder of type `int`.
- `AppL10n.of(context).workoutPickerAddButton(1)` returns `"Agregar 1 ejercicio"`.
- `AppL10n.of(context).workoutPickerAddButton(3)` returns `"Agregar 3 ejercicios"`.

**Linked scenarios**: SCENARIO-770, SCENARIO-771

---

### REQ-I18N-ICU-002 — Historial Show More Interpolation

`WorkoutStrings.historialShowMore(int n)` MUST be replaced with ARB key `workoutHistorialShowMore` using `"Ver {n} más"` with an `n` placeholder of type `int`.

**Acceptance criteria**:
- ARB key `workoutHistorialShowMore` exists with placeholder `n`.
- `AppL10n.of(context).workoutHistorialShowMore(5)` returns `"Ver 5 más"`.

**Linked scenarios**: SCENARIO-772

---

### REQ-I18N-ICU-003 — Picker Sheet Apply Interpolation

`WorkoutStrings.pickerSheetApply(int n)` MUST be replaced with ARB key `workoutPickerSheetApply` using `"APLICAR ({n})"` with an `n` placeholder of type `int`.

**Acceptance criteria**:
- ARB key `workoutPickerSheetApply` exists with placeholder `n`.
- `AppL10n.of(context).workoutPickerSheetApply(2)` returns `"APLICAR (2)"`.

**Linked scenarios**: SCENARIO-773

---

### REQ-I18N-ICU-004 — Booking Confirm Body Interpolation

`AgendaStrings.bookingConfirmBody(DateTime t)` MUST be replaced with ARB key `agendaBookingConfirmBody` using a `date` placeholder of type `DateTime` with format `MMM d, y` (or the format already used in the current implementation — verbatim copy required).

**Acceptance criteria**:
- ARB key `agendaBookingConfirmBody` exists with a `date` placeholder of type `DateTime`.
- `AppL10n.of(context).agendaBookingConfirmBody(someDate)` returns a string matching the original `AgendaStrings.bookingConfirmBody(someDate)` output.

**Linked scenarios**: SCENARIO-774

---

### REQ-I18N-ICU-005 — Slot Booked By Label Interpolation

`AgendaStrings.slotBookedByLabel(String name)` MUST be replaced with ARB key `agendaSlotBookedByLabel` with a `name` placeholder of type `String`.

**Acceptance criteria**:
- ARB key `agendaSlotBookedByLabel` exists with placeholder `name`.
- `AppL10n.of(context).agendaSlotBookedByLabel("María")` returns the string with `"María"` interpolated at the correct position.

**Linked scenarios**: SCENARIO-775

---

## REQ-I18N-REFACTOR Requirements

### REQ-I18N-REFACTOR-001 — agenda_formatters.dart Extraction

`AgendaStrings.formatDate()`, `AgendaStrings.formatTime()`, and `AgendaStrings.dayOfWeekLabels` MUST be extracted to `lib/features/coach/presentation/agenda_formatters.dart` as a separate step BEFORE `agenda_strings.dart` is deleted. This extraction is part of PR#2.

**Acceptance criteria**:
- `lib/features/coach/presentation/agenda_formatters.dart` exists after PR#2.
- All previous call sites of `AgendaStrings.formatDate`, `AgendaStrings.formatTime`, and `AgendaStrings.dayOfWeekLabels` are updated to reference `AgendaFormatters` (or equivalent top-level functions in the new file).
- No dead references to the old symbols remain.
- `flutter analyze` 0 issues.

**Linked scenarios**: SCENARIO-776, SCENARIO-777

---

### REQ-I18N-REFACTOR-002 — Const Widget Update Policy

When a widget previously declared as `const` acquires a dependency on `AppL10n.of(context)`, the `const` keyword MUST be removed from that specific instantiation. This removal MUST be applied at every affected call site within the same PR.

**Acceptance criteria**:
- No PR closes with an analyzer warning caused by an invalid `const` on a widget that reads `AppL10n.of(context)`.
- `const` is preserved on widgets that do not read localized strings.

**Linked scenarios**: SCENARIO-778

---

### REQ-I18N-REFACTOR-003 — No Dead Code Remaining

After all three PRs, no `*_strings.dart` file and no unused import of a former `*_strings.dart` file SHALL remain anywhere in the codebase.

**Acceptance criteria**:
- `fd -e dart -g '*_strings.dart' lib/` returns zero results.
- No `import` of any deleted strings file compiles (compiler enforces this).
- `flutter analyze` 0 issues on the final state.

**Linked scenarios**: SCENARIO-779

---

### REQ-I18N-REFACTOR-004 — Verbatim String Value Preservation

Every string value migrated from a `*_strings.dart` class or an inline literal to ARB MUST be character-for-character identical to the original. No corrections to phrasing, spacing, capitalization, punctuation, or Rioplatense voseo are permitted during migration.

**Acceptance criteria**:
- Widget tests using `find.text('exact string')` continue to pass without modifying the test assertions.
- Manual diff of ARB values against source strings shows 0 deviations.

**Linked scenarios**: SCENARIO-780

---

## REQ-I18N-TEST Requirements

### REQ-I18N-TEST-001 — Existing Widget Tests Remain Green

All widget tests that use `find.text('...')` with verbatim Spanish strings MUST continue to pass without modification to the test assertions.

**Acceptance criteria**:
- `flutter test` 100% pass after each PR.
- No test assertion is changed to accommodate the migration; tests pass because strings are verbatim.

**Linked scenarios**: SCENARIO-781

---

### REQ-I18N-TEST-002 — AuthFailure Test Contract Preserved

Widget tests in `login_screen_test.dart` that assert exact Spanish strings originating from `AuthFailure.userMessage` MUST pass without modification. These tests are expected to remain stable because `AuthFailure.userMessage` is excluded from ARB migration.

**Acceptance criteria**:
- `login_screen_test.dart` passes without changes.
- No test in `login_screen_test.dart` is tagged as expected-failure.

**Linked scenarios**: SCENARIO-782

---

### REQ-I18N-TEST-003 — ICU Plural Test Coverage

Each ICU key with plural behavior MUST have at least two widget or unit test scenarios: one asserting the `=1` form and one asserting the `other` form.

**Acceptance criteria**:
- At least one test asserts `workoutPickerAddButton(1)` returns the singular form.
- At least one test asserts `workoutPickerAddButton(count > 1)` returns the plural form.
- Analogous coverage exists for `workoutHistorialShowMore` and `workoutPickerSheetApply` if plurals are introduced there.

**Linked scenarios**: SCENARIO-783, SCENARIO-784

---

### REQ-I18N-TEST-004 — Analyzer Clean Gate Per PR

Each of the three PRs MUST close with `flutter analyze` reporting 0 issues. Transient warnings during active development within a PR are acceptable, but the merge-ready state MUST be clean.

**Acceptance criteria**:
- CI (or local gate) runs `flutter analyze` and reports 0 issues at PR merge commit.
- `dart format .` produces no diff at PR merge commit.

**Linked scenarios**: SCENARIO-785

---

## REQ-I18N-DELIVERY Requirements

### REQ-I18N-DELIVERY-001 — PR#1 Scope (Infra + Auth)

PR#1 MUST contain exactly: `pubspec.yaml` update, `l10n.yaml` creation, `lib/l10n/intl_es_AR.arb` and `lib/l10n/intl_en.arb` initial files, `MaterialApp` delegate wiring in `lib/app/app.dart`, and migration + deletion of `auth_strings.dart`. No other `*_strings.dart` file is deleted in PR#1.

**Acceptance criteria**:
- PR#1 diff contains the files listed above and no others outside `lib/features/auth/`.
- LOC delta is approximately ≤ 200.
- App compiles and all tests pass at the PR#1 merge commit.

**Linked scenarios**: SCENARIO-786

---

### REQ-I18N-DELIVERY-002 — PR#2 Scope (Coach + Agenda + Workout)

PR#2 MUST contain: extraction of `agenda_formatters.dart`, migration + deletion of `coach_strings.dart`, `agenda_strings.dart`, `workout_strings.dart`, ICU plural migrations, and migration of `trainer_dashboard_tab.dart` inline strings.

**Acceptance criteria**:
- PR#2 diff contains only files under `lib/features/coach/`, `lib/features/workout/`, and ARB file updates.
- LOC delta is approximately ≤ 350.
- App compiles and all tests pass at the PR#2 merge commit.

**Linked scenarios**: SCENARIO-787

---

### REQ-I18N-DELIVERY-003 — PR#3 Scope (Inline Batch)

PR#3 MUST contain: migration of inline strings in profile, profile_setup, reviews, `plantillas_section.dart`, and `app.dart` SnackBar. All `*_strings.dart` files MUST be gone by the end of PR#3.

**Acceptance criteria**:
- PR#3 diff contains only files under `lib/features/profile/`, `lib/features/profile_setup/`, `lib/features/reviews/`, `lib/features/workout/presentation/widgets/plantillas_section.dart`, `lib/app/app.dart`, and ARB file updates.
- LOC delta is approximately ≤ 250.
- `fd -e dart -g '*_strings.dart' lib/` returns zero results after PR#3.
- `flutter analyze` 0 issues; `flutter test` 100% pass.

**Linked scenarios**: SCENARIO-788

---

## Scenarios

### SCENARIO-748 — pubspec adds flutter_localizations

- GIVEN the project `pubspec.yaml` does not have `flutter_localizations`
- WHEN the developer adds the dependency and runs `flutter pub get`
- THEN `flutter pub get` exits 0 with no version conflict errors
- AND `flutter analyze` continues to report 0 issues

### SCENARIO-749 — pubspec adds intl ^0.19.0

- GIVEN `intl` is not in `pubspec.yaml`
- WHEN `intl: ^0.19.0` is added and `flutter pub get` runs
- THEN the resolved version is `0.19.x` with no override required

### SCENARIO-750 — l10n.yaml config is valid

- GIVEN `l10n.yaml` exists with the four required keys
- WHEN `flutter gen-l10n` is executed
- THEN it exits 0 and produces `lib/l10n/app_l10n.dart`

### SCENARIO-751 — AppL10n class is generated

- GIVEN `flutter gen-l10n` has been run
- WHEN a Dart file imports `package:treino/l10n/app_l10n.dart`
- THEN the `AppL10n` class is available with `AppL10n.of(context)` accessor

### SCENARIO-752 — supportedLocales contains es-AR and en

- GIVEN codegen has completed
- WHEN `AppL10n.supportedLocales` is accessed
- THEN it contains `Locale('es', 'AR')` and `Locale('en')`

### SCENARIO-753 — MaterialApp registers delegates

- GIVEN `app.dart` has been updated with `localizationsDelegates` and `supportedLocales`
- WHEN the app is built with `flutter analyze`
- THEN analyzer reports 0 issues

### SCENARIO-754 — AppL10n.of(context) resolves at runtime

- GIVEN the app runs on a device with locale es-AR
- WHEN a widget calls `AppL10n.of(context).someKey`
- THEN the call returns the es-AR string without throwing `MissingPluginException` or `FlutterError`

### SCENARIO-755 — es-AR device resolves es-AR strings

- GIVEN device locale is `es-AR`
- WHEN `AppL10n.of(context)` is called in any widget
- THEN the returned locale is `es-AR` and strings are Rioplatense Spanish

### SCENARIO-756 — Unsupported locale falls back to es-AR

- GIVEN device locale is `fr-FR` (not in `supportedLocales`)
- WHEN the app resolves the locale
- THEN Flutter selects `es-AR` as the fallback (first supported locale)

### SCENARIO-757 — ARB files contain @@locale metadata

- GIVEN `intl_es_AR.arb` and `intl_en.arb` are authored
- WHEN the files are parsed as JSON
- THEN `intl_es_AR.arb["@@locale"]` equals `"es-AR"` and `intl_en.arb["@@locale"]` equals `"en"`
- AND every parameterized key has a matching `@keyName` metadata block with `placeholders`

### SCENARIO-758 — All keys follow camelCase with feature prefix

- GIVEN `intl_es_AR.arb` is complete
- WHEN all non-metadata keys are enumerated
- THEN every key matches the pattern `[a-z]+[A-Z][a-zA-Z]+` (camelCase, starting lowercase)
- AND every key starts with a feature prefix (`auth`, `coach`, `agenda`, `workout`, `profile`, `reviews`, or `app`)

### SCENARIO-759 — AuthStrings call sites compile after deletion

- GIVEN `auth_strings.dart` is deleted and ARB keys are added
- WHEN `flutter build` runs
- THEN no `AuthStrings.` reference causes a compile error

### SCENARIO-760 — Auth string values are verbatim

- GIVEN `AuthStrings` constants have been migrated to ARB
- WHEN `AppL10n.of(context).{authKey}` is called
- THEN the returned string is character-for-character identical to the former `AuthStrings.{authKey}` value

### SCENARIO-761 — CoachStrings deletion compiles clean

- GIVEN `coach_strings.dart` is deleted and all call sites updated
- WHEN `flutter analyze` runs
- THEN 0 issues are reported and no `CoachStrings.` reference remains

### SCENARIO-762 — AgendaStrings string keys migrated

- GIVEN `agenda_strings.dart` string constants are migrated to ARB
- WHEN a widget that formerly used `AgendaStrings.X` is rendered
- THEN it displays the same Spanish text as before

### SCENARIO-763 — agenda_strings.dart deleted after extraction

- GIVEN `agenda_formatters.dart` has been created and call sites updated
- WHEN `agenda_strings.dart` is deleted
- THEN `flutter analyze` reports 0 issues

### SCENARIO-764 — WorkoutStrings deletion compiles clean

- GIVEN `workout_strings.dart` is deleted and all call sites updated
- WHEN `flutter analyze` runs
- THEN 0 issues are reported

### SCENARIO-765 — trainer_dashboard_tab inline strings migrated

- GIVEN PR#2 is applied
- WHEN `trainer_dashboard_tab.dart` is inspected
- THEN no user-visible hardcoded Spanish string literal remains

### SCENARIO-766 — Profile inline strings migrated

- GIVEN PR#3 is applied
- WHEN `profile_cuenta_section.dart`, `profile_edit_personal_screen.dart`, and `eliminar_cuenta_sheet.dart` are inspected
- THEN no user-visible hardcoded string literal remains

### SCENARIO-767 — App SnackBar and reviews inline strings migrated

- GIVEN PR#3 is applied
- WHEN `app.dart`, `review_bottom_sheet.dart`, `plantillas_section.dart`, and `profile_setup_flow.dart` are inspected
- THEN no user-visible hardcoded string literal remains

### SCENARIO-768 — intl_en.arb has matching keys with empty values

- GIVEN `intl_en.arb` is authored
- WHEN its non-metadata keys are compared to `intl_es_AR.arb` non-metadata keys
- THEN the two sets are identical
- AND every value in `intl_en.arb` is `""`

### SCENARIO-769 — AuthFailure.userMessage remains hardcoded

- GIVEN the final state of all three PRs is merged
- WHEN `lib/features/auth/domain/auth_failure.dart` is read
- THEN the `userMessage` getter contains hardcoded Spanish strings
- AND the exclusion comment is present
- AND no ARB key contains any of those Spanish strings

### SCENARIO-770 — pickerAddButton singular

- GIVEN a widget calls `AppL10n.of(context).workoutPickerAddButton(1)`
- WHEN the widget renders
- THEN the displayed text is `"Agregar 1 ejercicio"`

### SCENARIO-771 — pickerAddButton plural

- GIVEN a widget calls `AppL10n.of(context).workoutPickerAddButton(3)`
- WHEN the widget renders
- THEN the displayed text is `"Agregar 3 ejercicios"`

### SCENARIO-772 — historialShowMore interpolation

- GIVEN a widget calls `AppL10n.of(context).workoutHistorialShowMore(5)`
- WHEN the widget renders
- THEN the displayed text is `"Ver 5 más"`

### SCENARIO-773 — pickerSheetApply interpolation

- GIVEN a widget calls `AppL10n.of(context).workoutPickerSheetApply(2)`
- WHEN the widget renders
- THEN the displayed text is `"APLICAR (2)"`

### SCENARIO-774 — bookingConfirmBody interpolation

- GIVEN a specific `DateTime` value `t`
- WHEN `AppL10n.of(context).agendaBookingConfirmBody(t)` is called
- THEN the returned string matches what `AgendaStrings.bookingConfirmBody(t)` previously returned

### SCENARIO-775 — slotBookedByLabel interpolation

- GIVEN `name = "María"`
- WHEN `AppL10n.of(context).agendaSlotBookedByLabel("María")` is called
- THEN the returned string contains `"María"` at the correct position

### SCENARIO-776 — agenda_formatters.dart exists

- GIVEN PR#2 is applied
- WHEN `lib/features/coach/presentation/agenda_formatters.dart` is read
- THEN it contains `formatDate`, `formatTime`, and `dayOfWeekLabels` members

### SCENARIO-777 — Former AgendaStrings formatter call sites updated

- GIVEN `agenda_formatters.dart` is created
- WHEN all former `AgendaStrings.formatDate(...)`, `AgendaStrings.formatTime(...)`, and `AgendaStrings.dayOfWeekLabels` references are inspected
- THEN each one has been updated to reference the new file
- AND `flutter analyze` reports 0 issues

### SCENARIO-778 — No invalid const after AppL10n dependency

- GIVEN widgets have been updated to read from `AppL10n.of(context)`
- WHEN `flutter analyze` runs
- THEN no warning or error about `const` on a non-const constructor is reported

### SCENARIO-779 — No *_strings.dart files remain

- GIVEN all three PRs are merged
- WHEN the file system is searched for `*_strings.dart` under `lib/`
- THEN zero files are found

### SCENARIO-780 — Verbatim string preservation

- GIVEN a string formerly in `WorkoutStrings`, `AuthStrings`, `CoachStrings`, or `AgendaStrings`
- WHEN the ARB value for the corresponding key is read
- THEN it is byte-for-byte identical to the original Dart string constant

### SCENARIO-781 — Existing widget tests pass unchanged

- GIVEN the test suite before migration
- WHEN `flutter test` is run after any of the three PRs
- THEN 100% of tests pass with no modifications to test assertion strings

### SCENARIO-782 — login_screen_test assertions unchanged

- GIVEN `login_screen_test.dart` assertions for `AuthFailure.userMessage` strings
- WHEN `flutter test test/features/auth/presentation/login_screen_test.dart` is run after all PRs
- THEN the test file passes with 0 failures and 0 modifications

### SCENARIO-783 — ICU plural =1 path covered by test

- GIVEN `workoutPickerAddButton` is an ICU plural key
- WHEN a widget test calls `workoutPickerAddButton(1)` and asserts the singular form
- THEN the assertion passes

### SCENARIO-784 — ICU plural other path covered by test

- GIVEN `workoutPickerAddButton` is an ICU plural key
- WHEN a widget test calls `workoutPickerAddButton(5)` and asserts the plural form
- THEN the assertion passes

### SCENARIO-785 — Analyzer clean at each PR merge

- GIVEN a PR is ready to merge
- WHEN `flutter analyze` is run on the merge commit
- THEN exit code is 0 and output contains `No issues found!`

### SCENARIO-786 — PR#1 scope is isolated to infra + auth

- GIVEN PR#1 diff is reviewed
- WHEN changed files are enumerated
- THEN only `pubspec.yaml`, `l10n.yaml`, `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`, `lib/app/app.dart`, and files under `lib/features/auth/` appear
- AND LOC delta is ≤ 200

### SCENARIO-787 — PR#2 scope is isolated to coach, agenda, workout

- GIVEN PR#2 diff is reviewed
- WHEN changed files are enumerated
- THEN only files under `lib/features/coach/`, `lib/features/workout/`, and ARB updates appear
- AND `agenda_formatters.dart` is present
- AND LOC delta is ≤ 350

### SCENARIO-788 — PR#3 scope is isolated to inline batch

- GIVEN PR#3 diff is reviewed
- WHEN changed files are enumerated
- THEN only files under `lib/features/profile/`, `lib/features/profile_setup/`, `lib/features/reviews/`, `lib/features/workout/presentation/widgets/plantillas_section.dart`, `lib/app/app.dart`, and ARB updates appear
- AND `fd -e dart -g '*_strings.dart' lib/` returns zero results
- AND LOC delta is ≤ 250

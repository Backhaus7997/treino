# Design: i18n-localization (Fase 6 Etapa 8)

**Scope**: Architectural decisions for migrating ~130 strings to ARB under `flutter_localizations` + `intl ^0.19.0`. Approach **Replace Direct** confirmed in proposal. 3 chained PRs against `main`. es-AR default (Rioplatense verbatim), English scaffold-only.

**Reads**: `sdd/i18n-localization/proposal` (#170), `sdd/i18n-localization/explore` (#169).

---

## 1. Architecture Approach

**Pattern**: Single source of truth = ARB files under `lib/l10n/`. Codegen produces `AppL10n` accessor class. All UI call sites read via `AppL10n.of(context).keyName`. No adapter, no intermediary class.

**Layering**:
- **Resource layer**: `lib/l10n/intl_es_AR.arb` (template), `lib/l10n/intl_en.arb` (scaffold)
- **Generated layer**: `lib/l10n/app_l10n.dart` (codegen output — gitignored or committed per project policy; this design assumes committed for visibility, `synthetic-package: false`)
- **Consumption layer**: any widget under `lib/features/**/presentation/**` via `AppL10n.of(context)`
- **Excluded layer**: `lib/features/auth/domain/auth_failure.dart` — domain stays hardcoded es-AR (no `BuildContext` available in domain layer)

**Boundary**: ARB lives in the presentation/resource layer. Domain and data layers MUST NOT import `AppL10n`. The only exception is utility code that formats values (not text content) — extracted to `agenda_formatters.dart`.

---

## 2. ADRs

### ADR-I18N-001 — Approach: Replace Direct vs Adapter
- **Decision**: Replace Direct (Approach A).
- **Reasoning**: zero adapter debt; tests stay green because strings copy 1:1; one source of truth (ARB) matching Flutter's official i18n convention.
- **Alternatives rejected**: (B) Adapter Pattern — accumulates debt on every future feature; (C) Hybrid — splits convention, requires policy for every new feature.

### ADR-I18N-002 — `AuthFailure.userMessage` exclusion
- **Decision**: Stays hardcoded es-AR. Each branch annotated `// i18n: intentional exclusion — domain layer cannot receive BuildContext`.
- **Reasoning**: Domain getter is pure (no `BuildContext`). Injecting context violates hexagonal architecture (domain → UI dependency).
- **Trade-off**: This feature becomes es-AR-only permanently. Any future locale needs a domain refactor (resolver pattern with locale param injected at boundary).
- **Tests linked**: `test/features/auth/presentation/login_screen_test.dart` lines 152, 178 (find.text with literal Spanish from `AuthFailure.userMessage`).

### ADR-I18N-003 — `agenda_formatters.dart` extraction
- **Decision**: Extract `formatDate`, `formatTime`, `dayOfWeekLabels` from `AgendaStrings` into `lib/features/coach/presentation/agenda_formatters.dart` BEFORE deleting `AgendaStrings`.
- **Reasoning**: These are utility functions/maps, NOT user-facing strings — do NOT belong in ARB.
- **Ubicación**: `lib/features/coach/presentation/agenda_formatters.dart`.
- **Ejecución**: Sub-task 2.1 in PR#2 — runs before `AgendaStrings` migration.

### ADR-I18N-004 — `l10n.yaml` configuration
```yaml
arb-dir: lib/l10n
template-arb-file: intl_es_AR.arb
output-localization-file: app_l10n.dart
output-class: AppL10n
nullable-getter: false
synthetic-package: false
```
- **Reasoning**: `output-class: AppL10n` for brevity at call sites (`AppL10n.of(context)` vs `AppLocalizations.of(context)`). `synthetic-package: false` keeps generated file in `lib/l10n/` (visible, debuggable, IDE-navigable). `nullable-getter: false` avoids `?.` defensive chains on every call site.

### ADR-I18N-005 — Locale resolution policy
- **Default**: es-AR.
- **Fallback chain**: any non-es-AR device locale → forced to es-AR (NOT en, because en is scaffold-only with empty values).
- **Implementation**: `localeResolutionCallback` in `MaterialApp` returning `Locale('es', 'AR')` for any non-matching device locale.
- **Reasoning**: English ARB exists only to satisfy codegen contract — not user-facing.

### ADR-I18N-006 — ARB key naming convention
- **Structure**: `{feature}{Concept}` or `{feature}{Action}{Concept}` in camelCase.
- **Examples**: `authLoginButton`, `coachDiscoverySearchHint`, `workoutPickerAddButton`.
- **No underscore prefix namespacing** — codegen exposes keys as direct method names; camelCase reads naturally at call sites.
- **Reasoning**: Aligns with Flutter docs convention; produces idiomatic Dart accessors.

### ADR-I18N-007 — ICU plural authoring
- **Syntax**: ICU MessageFormat embedded in ARB values.
- **es-AR**: only `=1` and `other` (Spanish has no separate few/many).
- **Example**:
  ```json
  "workoutPickerAddButton": "Agregar {count, plural, =1{ejercicio} other{ejercicios}}",
  "@workoutPickerAddButton": {
    "placeholders": { "count": { "type": "int" } }
  }
  ```
- **English scaffold**: same ICU skeleton with empty `=1{}` / `other{}` braces — codegen requires the plural shape even when empty.
- **Reasoning**: codegen catches syntax errors at build time; semantic correctness validated by QA.

### ADR-I18N-008 — `const` widget policy
- **Decision**: When a widget loses `const` due to `AppL10n.of(context)`, remove the `const` modifier at that exact call site. No workarounds (no wrappers with hardcoded strings).
- **Trade-off**: marginal perf hit on rebuilds; mitigated because affected widgets are mostly leaves of the tree.
- **Quality gate**: each PR closes with `flutter analyze` 0 issues. Transient warnings during PR work are acceptable.

### ADR-I18N-009 — PR chaining strategy
- **3 PRs, all against `main`** (stacked-to-main, NOT stacked-to-PR).
- PR#1 merges first → PR#2 branches from updated `main` → PR#3 branches from updated `main`.
- **Reasoning**: each PR is bisectable and independent; rollback of PR#N does not break PR#N−1.
- **Strict TDD**: each PR has its own RED+GREEN commits per feature module.

### ADR-I18N-010 — Test contract policy
- **Existing tests** using `find.text('exact string')`: NOT modified. Strings copy 1:1 from `*_strings.dart` to ARB values.
- **Test breakage = bug**: any test failure indicates mismatch between original constant value and ARB value — fix the ARB value before merge.
- **New tests**: minimum 1 widget test per feature verifying `AppL10n.of(context)` resolves to expected string under es-AR locale. Plus 1 locale-resolution test covering the fallback callback.

---

## 3. Component Design

### Localization wire (PR#1)
- **File**: `lib/app/app.dart` (or wherever `MaterialApp` is instantiated).
- **Additions**:
  - `localizationsDelegates: AppL10n.localizationsDelegates`
  - `supportedLocales: AppL10n.supportedLocales`
  - `localeResolutionCallback: (deviceLocale, supported) => const Locale('es', 'AR')`
- **Flow**: device locale → `localeResolutionCallback` forces es-AR → widget tree resolves `AppL10n.of(context)` against `intl_es_AR.arb` → returns Rioplatense string.
- **Codegen trigger**: `flutter pub get` (auto-detects `l10n.yaml` and generates `lib/l10n/app_l10n.dart`).

### Migration order per PR

**PR#1 — Infra + Auth (~200 LOC)**
- 1.1: `pubspec.yaml` add `flutter_localizations` (SDK) + `intl: ^0.19.0`
- 1.2: Create `l10n.yaml` at repo root with ADR-I18N-004 config
- 1.3: Create `lib/l10n/intl_es_AR.arb` (skeleton with `@@locale: es_AR`) and `lib/l10n/intl_en.arb` (scaffold with `@@locale: en`)
- 1.4: Wire `MaterialApp` (delegates, supportedLocales, localeResolutionCallback)
- 1.5: Migrate `AuthStrings` (~30 keys) → ARB + update all call sites → delete `auth_strings.dart`
- 1.6: Add `// i18n: intentional exclusion` comments to `AuthFailure.userMessage` branches

**PR#2 — Coach + Agenda + Workout (~350 LOC)**
- 2.1: Extract `agenda_formatters.dart` (refactor preparatorio) — `formatDate`, `formatTime`, `dayOfWeekLabels`
- 2.2: Migrate `CoachStrings` (~30 keys) → ARB + update call sites + delete `coach_strings.dart`
- 2.3: Migrate `AgendaStrings` (~28 keys + 2 ICU interpolations: `bookingConfirmBody(DateTime)`, `slotBookedByLabel(String)`) → ARB + update call sites + delete `agenda_strings.dart` (formatters already extracted in 2.1)
- 2.4: Migrate `WorkoutStrings` (~50 keys + 3 ICU plurales: `pickerAddButton(int)`, `historialShowMore(int)`, `pickerSheetApply(int)` + 1 interpolation) → ARB + update call sites + delete `workout_strings.dart`
- 2.5: Migrate `trainer_dashboard_tab.dart` inline strings (~15 literals)

**PR#3 — Inline batch (~250 LOC)**
- 3.1: `profile_cuenta_section.dart` (6+ inline)
- 3.2: `profile_edit_personal_screen.dart` (4 validator strings)
- 3.3: `eliminar_cuenta_sheet.dart` (7 inline)
- 3.4: `review_bottom_sheet.dart` (5 inline)
- 3.5: `app.dart` FCM SnackBar 'Ver' label
- 3.6: `plantillas_section.dart` (2 inline)
- 3.7: `profile_setup_flow.dart` (4 inline titles)

---

## 4. Data Flow

```
[device locale]
      ↓
[MaterialApp.localeResolutionCallback]
      ↓
[forced Locale('es','AR')]
      ↓
[AppL10n.of(context)]
      ↓
[ARB lookup in intl_es_AR.arb]
      ↓
[Rioplatense string returned to widget]
```

For ICU plurals: `AppL10n.of(context).workoutPickerAddButton(count)` → ICU `=1`/`other` resolves against `count` → final string.

---

## 5. Integration Points

- **`pubspec.yaml`**: adds `flutter_localizations` (Flutter SDK) and `intl: ^0.19.0`. Triggers codegen on `flutter pub get`.
- **`MaterialApp`**: receives 3 new properties (`localizationsDelegates`, `supportedLocales`, `localeResolutionCallback`).
- **All presentation widgets**: import generated `package:treino/l10n/app_l10n.dart` and replace direct string access.
- **Domain (`auth_failure.dart`)**: NO integration. Stays decoupled.
- **Test layer**: existing `find.text(...)` assertions remain valid (strings unchanged). New tests use `AppL10n.of(tester.element(find.byType(MaterialApp)))` for resolution checks.

---

## 6. Risks (top 4, revalidated from explore)

1. **AuthFailure exclusion test contract**: any future change to `userMessage` strings is es-AR-only. Document via inline comment + this ADR. Future locale support requires domain refactor (resolver pattern at boundary).
2. **ICU semantics es-AR**: codegen catches syntax errors only — semantic correctness (plural rules, agreement, Rioplatense register) requires QA review on PR#2.
3. **Const widget cascade**: ~30 widgets lose `const`. All are leaves of the tree (minimal perf impact). Each PR closes with 0 analyzer issues; transient warnings during work are acceptable.
4. **Locale resolution edge cases**: exotic device locales never match supported — fallback callback must always return a valid `Locale` instance (never null), even if `supportedLocales` contains only es-AR + en.

---

## 7. Coupling Warnings (for spec/tasks)

- **New ARB keys MUST be bilingual**: any future feature adding to `intl_es_AR.arb` MUST also add the matching key (with empty value or ICU skeleton) to `intl_en.arb`, otherwise codegen fails.
- **No regression to `*_strings.dart`**: any future feature creating a new `_strings.dart` file is a process violation. Out of scope for this SDD, but log as follow-up: consider a custom analyzer lint or CI grep to detect new `_strings.dart` additions under `lib/features/**/presentation/`.
- **Domain-layer i18n**: any future requirement to localize domain getters (e.g. `AuthFailure.userMessage`) must NOT inject `BuildContext`. The correct pattern is a locale resolver injected at the boundary (use case / controller) — a separate SDD.

---

## 8. Ready for Tasks
Yes. Spec covers WHAT (ARB key inventory, call site map, ICU placeholder schemas). Tasks will sequence the work per PR following the migration order above.

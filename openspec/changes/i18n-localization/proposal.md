# Proposal: i18n-localization

**Change**: i18n-localization
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-09
**Phase**: Fase 6 Etapa 8 — última etapa pendiente de Fase 6
**Artifact store**: hybrid (`openspec/changes/i18n-localization/proposal.md` + Engram `sdd/i18n-localization/proposal`)
**Exploration**: `sdd/i18n-localization/explore` #169 · `openspec/changes/i18n-localization/explore.md`

---

## TL;DR

Set up formal Flutter i18n with `flutter_localizations` + `intl` and migrate ~130 hardcoded user-facing strings to ARB files under `lib/l10n/`. **es-AR is the official default**; **English is scaffold-only** (empty values, no translations shipped). Approach A — Replace Direct: delete every `*_strings.dart` class and route call sites through `AppLocalizations.of(context)`, with two deliberate exclusions (`AuthFailure.userMessage`, `agenda_formatters` utility code). Delivered as 3 chained PRs to stay under the 400-LOC review budget. Pure refactor, zero functional delta.

---

## Goals

1. Add `flutter_localizations` + `intl ^0.19.0` and configure `l10n.yaml` with codegen.
2. Migrate all UI-visible strings (currently in 4 `*_strings.dart` classes + ~10 files with inline literals) to `lib/l10n/intl_es_AR.arb`.
3. Generate matching `lib/l10n/intl_en.arb` scaffold (keys present, values empty) for future QA translation.
4. Wire `AppLocalizations.delegates` and `supportedLocales` in `MaterialApp`.
5. Translate manual plural/interpolation patterns (`WorkoutStrings.pickerAddButton`, `historialShowMore`, `pickerSheetApply`, `AgendaStrings.bookingConfirmBody`, `slotBookedByLabel`) to ICU MessageFormat.
6. Extract `AgendaStrings.formatDate` / `formatTime` / `dayOfWeekLabels` to `lib/features/coach/presentation/agenda_formatters.dart` before deleting `AgendaStrings`.
7. Close Fase 6.

## Non-goals

- Real English translation (scaffold only — QA owns translation post-merge).
- Refactoring the domain layer to receive `BuildContext` or a localization port.
- Migrating non-user-facing exception/log messages.
- Any functional/behavioral change (pure refactor).
- New dependencies beyond `flutter_localizations` + `intl`.
- Ranking / Retos / Missions / Bets / Gamification (out of project scope).

---

## Hard constraints

1. **`AuthFailure.userMessage` is excluded from ARB migration.** It is a freezed sealed domain model getter with no `BuildContext`; routing it through `AppLocalizations` would break hexagonal architecture (domain → UI dependency). Stays hardcoded es-AR with a documented comment + ADR-style note in the proposal/spec.
2. **es-AR is the default locale.** Rioplatense voseo preserved verbatim from current strings.
3. **English is scaffold-only.** `intl_en.arb` ships with empty values; codegen still produces the locale entry so QA can fill it later.
4. **No new deps** beyond `flutter_localizations` (Flutter SDK) + `intl ^0.19.0` (matches Flutter 3.22+).
5. **Project standards**: Mint Magenta theme via `AppPalette.of(context)`, `TreinoIcon.X` (no `PhosphorIcons` direct), conventional commits, no AI attribution.
6. **Quality gate**: `flutter analyze` 0 issues + `dart format .` + tests passing on each PR.
7. **Strict TDD active** — apply phase must follow strict-tdd.md.

---

## Approach: Replace Direct (Approach A)

Delete all `*_strings.dart` classes. Every call site reads strings via `AppLocalizations.of(context).keyName`. Single source of truth = ARB. Tests stay green because strings are copied 1:1 (verbatim es-AR).

**Two deliberate exclusions:**

- `AuthFailure.userMessage` (domain layer — see hard constraint #1).
- `AgendaStrings.formatDate` / `formatTime` / `dayOfWeekLabels` (utility code, not i18n strings) → relocated to `agenda_formatters.dart` as a refactor sub-task within PR#2 before `AgendaStrings` is deleted.

**Why A over B (Adapter) or C (Hybrid):** Adapter wrappers become dead weight that every future feature pays for. Replace Direct produces one canonical pattern matching Flutter's official i18n convention. The larger diff is acceptable because it's a mechanical refactor with no functional delta.

---

## PR strategy — 3 chained PRs

| PR | Scope | Files | LOC est. |
|---|---|---|---|
| **PR#1 — Infra + Auth** | `pubspec.yaml` (+deps), `l10n.yaml`, initial ARB files (es-AR template + en scaffold), `MaterialApp` delegates/supportedLocales, migrate `AuthStrings` → ARB, delete `auth_strings.dart` | `pubspec.yaml`, `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`, `l10n.yaml`, `lib/app/app.dart`, `lib/features/auth/**` | ~200 |
| **PR#2 — Coach + Agenda + Workout** | Migrate `CoachStrings`, `AgendaStrings` (extract `agenda_formatters.dart` first), `WorkoutStrings` (ICU plurals). Migrate `trainer_dashboard_tab.dart` inline strings. | `lib/features/coach/**`, `lib/features/workout/**` | ~350 |
| **PR#3 — Inline batch** | Migrate remaining inline literals: profile, profile_setup, reviews, `app.dart` SnackBar, `plantillas_section.dart` | `lib/features/profile/**`, `lib/features/profile_setup/**`, `lib/features/reviews/**`, `lib/app/app.dart`, `lib/features/workout/presentation/widgets/plantillas_section.dart` | ~250 |

Each PR is independently reviewable, isolated risk, and stays under the 400-LOC budget without needing `size:exception`.

---

## Locked decisions

1. **`AuthFailure.userMessage` exclusion** — ACCEPTED. Stays hardcoded es-AR with `// i18n: intentional exclusion — domain model, no BuildContext. See proposal.md.` comment. ADR note inline in `auth_failure.dart`. *Reason*: only viable path that keeps hex arch intact; tests assert these strings directly so a 1:1 copy is safer than a port-based refactor inside this SDD.

2. **`agenda_formatters.dart` extraction** — ACCEPTED. Move `formatDate()`, `formatTime()`, `dayOfWeekLabels` to `lib/features/coach/presentation/agenda_formatters.dart` as a sub-task of PR#2, executed BEFORE deleting `AgendaStrings`. *Reason*: they are utility code, not user-facing strings — should never have lived in a `*_strings.dart` file. Extraction is mechanical and isolated.

3. **3 chained PRs** — ACCEPTED over single PR + `size:exception`. *Reason*: cleaner review, isolated rollback per slice, no maintainer approval friction, three reviewers can work in parallel on a small diff each. PR#1 establishes infra and unblocks PR#2 / PR#3 from depending on a single huge diff.

4. **`l10n.yaml` config**:
   - `arb-dir: lib/l10n`
   - `template-arb-file: intl_es_AR.arb`
   - `output-localization-file: app_l10n.dart`
   - `output-class: AppL10n` *(recommended for brevity at call sites — `AppL10n.of(context).welcomeTitle` is shorter than `AppLocalizations.of(context).welcomeTitle`; ~138 call sites benefit). **Confirm with owner — purely stylistic.*** If owner prefers Flutter default, fall back to `output-class: AppLocalizations` and `output-localization-file: app_localizations.dart`.

5. **`intl` version**: `^0.19.0` — matches the version Flutter 3.22+ ships with via `flutter_localizations`. *Reason*: avoiding a version-pin mismatch warning when `flutter pub get` runs.

---

## Out of scope

- Real English translation (only empty scaffold ships).
- Domain-layer refactor to inject a localization port for `AuthFailure`.
- Migration of non-user-facing exception/log messages or stack traces.
- Any UI behavior, navigation, or business-logic change.
- Locale switcher UI (no runtime locale toggle in this SDD — system locale only).
- Currency / date / number formatters beyond what already exists (those stay as `intl` DateFormat helpers via `agenda_formatters.dart`).
- RTL / bidirectional support.
- Pluralization beyond simple `=1/other` (es-AR semantics are simple).

---

## Open questions for spec phase

The spec must close these as REQ/SCENARIO:

1. **ARB key naming convention**: snake_case vs camelCase. Flutter codegen default is camelCase; recommend camelCase to match generated Dart symbol style. Spec should freeze.
2. **Key namespacing**: flat (`workoutPickerAddButton`) vs nested-by-feature (`workout.pickerAddButton`). ARB doesn't support nesting natively; flat with feature prefix is the de-facto convention. Spec should freeze.
3. **`@@locale` metadata**: define exact `@@locale: "es-AR"` and `@@locale: "en"` plus `@key` metadata for placeholders. Spec should enumerate metadata requirements.
4. **Const widget breakage policy**: when widget loses `const` due to `AppL10n.of(context)` lookup, remove `const` inline. Spec should set rule explicitly.
5. **Test strategy for ICU plurals**: golden assertions on rendered strings for `=1` vs `other` paths. Spec should require a scenario per ICU key.
6. **`AuthFailure.userMessage` test contract**: spec should explicitly document that login/register tests asserting exact Spanish from `AuthFailure.userMessage` are expected to remain unchanged.

---

## LOC + scope forecast

| Slice | LOC changed | Files |
|---|---|---|
| PR#1 Infra + Auth | ~200 | ~8 |
| PR#2 Coach + Agenda + Workout | ~350 | ~12 |
| PR#3 Inline batch | ~250 | ~10 |
| **Total** | **~800** | **~30** |

400-LOC budget per PR respected on all three. No `size:exception` needed.

---

## Risks (top 3, unchanged from explore)

1. **`AuthFailure.userMessage` hex-arch constraint** — mitigated by deliberate exclusion + documented comment.
2. **ICU plural authoring** — manual ternaries → ICU `{count, plural, ...}`; codegen catches syntax errors at build time. Semantics simple in es-AR (`=1` / `other`).
3. **Const widget loss + analyzer warnings** during PR#2 / PR#3 — fixable per-call-site by removing `const` keyword; marginal build perf impact.

---

## Refs

- Exploration: `sdd/i18n-localization/explore` (Engram #169) · `openspec/changes/i18n-localization/explore.md`
- Roadmap lock: `docs/roadmap.md:454,509` (es-AR default + en scaffold-only)
- Project conventions: `AGENTS.md`, `CLAUDE.md`

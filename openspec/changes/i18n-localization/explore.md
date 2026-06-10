# Exploration: i18n-localization

**Change**: i18n-localization
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-10
**Phase**: Fase 6 Etapa 8 — última etapa pendiente de Fase 6
**Artifact store**: hybrid (file `openspec/changes/i18n-localization/explore.md` + Engram `sdd/i18n-localization/explore` #169)

---

## Scope Summary

Setup formal de i18n con `flutter_localizations` + `intl_translation` migrando todos los strings hardcoded del codebase a `.arb` files. **es-AR oficial** como default; **inglés solo scaffold** (keys vacíos para QA traducir después — locked en `docs/roadmap.md:454,509`).

Sin cambios funcionales — refactor puro. Cierra Fase 6.

---

## Current State — Inventario

### Pubspec status (clean slate)

`pubspec.yaml` confirmado SIN dependencias de i18n:
- ❌ `flutter_localizations` (no presente)
- ❌ `intl` (no presente)
- ❌ `l10n.yaml` (no existe)
- ❌ `generate: true` flag en `flutter:` section

### Archivos `*_strings.dart` existentes (4 archivos, ~138 strings)

| File | Class | LOC strings | Métodos con lógica |
|---|---|---|---|
| `lib/features/auth/presentation/auth_strings.dart` | `AuthStrings` | ~30 | — |
| `lib/features/coach/presentation/coach_strings.dart` | `CoachStrings` | ~30 | — |
| `lib/features/coach/presentation/agenda_strings.dart` | `AgendaStrings` | ~28 strings + `formatDate()`, `formatTime()`, `dayOfWeekLabels` (utility code, NO i18n) |
| `lib/features/workout/presentation/workout_strings.dart` | `WorkoutStrings` | ~50 strings + 4 métodos con plurales/interpolation |

### Strings hardcoded sueltos (no en `*_strings.dart`)

| File | Strings inline | Notas |
|---|---|---|
| `lib/features/profile/presentation/profile_cuenta_section.dart` | 6+ | Marcados `// i18n: Fase 6 Etapa 3` |
| `lib/features/profile/presentation/profile_edit_personal_screen.dart` | 4 | Validators |
| `lib/features/profile/presentation/widgets/eliminar_cuenta_sheet.dart` | 7 | — |
| `lib/features/coach/presentation/trainer_dashboard_tab.dart` | ~15 | `'HOLA, $name'`, `'PRÓXIMAS SESIONES'`, etc. |
| `lib/features/reviews/presentation/widgets/review_bottom_sheet.dart` | 5 | Marcados `// i18n: Fase 6 Etapa 7` |
| `lib/app/app.dart` | 1 | `'Ver'` en FCM SnackBar |
| `lib/features/workout/presentation/widgets/plantillas_section.dart` | 2 | — |
| `lib/features/profile_setup/presentation/profile_setup_flow.dart` | 4 | Título strings |

**Total estimado de keys ARB**: ~130 strings.

---

## 🔴 Constraint crítico: `AuthFailure.userMessage`

`lib/features/auth/domain/auth_failure.dart` es un **freezed sealed domain model** con `String get userMessage` getter que devuelve strings es-AR. **No tiene `BuildContext` y NO puede usar `AppLocalizations.of(context)`** sin romper el contrato hexagonal (domain depende de UI).

Tests en `login_screen_test.dart` (líneas 152, 178) hacen assertions directas sobre esos strings. **Único path seguro**: excluir explícitamente este getter de la migración, dejarlo es-AR-only con comentario documentando la exclusión intencional.

---

## Pluralization & interpolation existentes (necesitan ICU MessageFormat)

| Método | Patrón actual | ICU target |
|---|---|---|
| `WorkoutStrings.pickerAddButton(int count)` | ternary manual | `{count, plural, =1{ejercicio} other{ejercicios}}` |
| `WorkoutStrings.historialShowMore(int n)` | interpolation | `{n} más` |
| `WorkoutStrings.pickerSheetApply(int n)` | interpolation | `Aplicar ({n})` |
| `AgendaStrings.bookingConfirmBody(DateTime t)` | interpolation + `intl` DateFormat | needs `{date}` placeholder |
| `AgendaStrings.slotBookedByLabel(String name)` | interpolation | `Reservado por {name}` |

---

## Approach Options

| Approach | Description | LOC tocadas | Risk call sites | Test breakage | Tech debt | Effort |
|---|---|---|---|---|---|---|
| **A — Replace Direct** | Borrar `*_strings.dart`, todos los call sites → `AppLocalizations.of(context).X` | ~600 | Alto | Bajo (strings idénticos) | Bajo | Alto |
| **B — Adapter Pattern** | Mantener `*_strings.dart` como wrappers delegando a `AppLocalizations` | ~300 | Bajo | Bajo | Alto | Medio |
| **C — Híbrido** | Replace en features nuevas, adapter en legacy | ~350 | Medio | Bajo | Medio | Medio |

**Constraint común**: las 3 approaches tienen el problema `AuthFailure.userMessage`. Ninguna lo resuelve trivialmente.

### Recommendation: **Approach A (Replace Direct)** con 2 exclusiones deliberadas

1. **`AuthFailure.userMessage`** — queda hardcoded es-AR con comentario documentando exclusión intencional. Domain method, no puede recibir context sin romper hex arch.
2. **`AgendaStrings.formatDate` / `formatTime` / `dayOfWeekLabels`** — son utility/formatter code, no strings i18n. Extraer a `lib/features/coach/presentation/agenda_formatters.dart` ANTES de borrar `AgendaStrings`.

**Por qué A sobre B/C**: deuda técnica baja (los adapters se vuelven dead weight), tests no se rompen porque copiamos strings 1:1, y el codebase queda con un solo source-of-truth (las ARB).

---

## Estrategia de delivery — 3 PRs encadenados (recomendado)

PR strategy para mantenerse bajo el 400-LOC review budget:

| PR | Scope | Archivos clave | LOC est. |
|---|---|---|---|
| **PR#1 — Infra + auth** | `pubspec.yaml` + `l10n.yaml` + ARB files iniciales + `MaterialApp.localizationsDelegates` + migración de `AuthStrings` (auth feature) | `pubspec.yaml`, `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_en.arb`, `lib/main.dart` / `lib/app.dart`, `lib/features/auth/` | ~200 |
| **PR#2 — Coach + Agenda + Workout** | `CoachStrings`, `AgendaStrings` (con extracción de `agenda_formatters.dart`), `WorkoutStrings` (con ICU plurales) | `lib/features/coach/`, `lib/features/workout/` | ~350 |
| **PR#3 — Inline strings batch** | Strings hardcoded en profile, profile_setup, reviews, app.dart, plantillas, trainer_dashboard, etc. | varios `lib/features/*/presentation/` | ~250 |

---

## Riesgos técnicos

| Riesgo | Severidad | Mitigación |
|---|---|---|
| `AuthFailure.userMessage` no migrable | **HIGH** | Exclusión explícita documentada en ADR + comment en el código |
| ICU plural semantics en es-AR | MEDIUM | Codegen captura syntax errors; semántica simple (singular/other) en es-AR — verificar con QA |
| ~30 `const` widgets pierden `const` | MEDIUM | Genera analyzer warnings durante migración — fixable removiendo `const` puntual; afecta build perf marginalmente |
| Tests con `find.text('exacto')` | LOW | Strings copiados 1:1, sin cambio de valor — tests no rompen |
| `freezed` factory params con default es-AR | LOW | Si existen, audit en spec phase — escapar el default |

---

## Decisiones a tomar en propose (NO resolver acá)

1. **Exclusión de `AuthFailure.userMessage`**: confirmar que se queda hardcoded es-AR con comment de exclusión.
2. **Extracción de `agenda_formatters.dart`**: confirmar el approach (renombrar utilities antes de borrar `AgendaStrings`).
3. **PR strategy**: 3 chained PRs vs 1 PR con `size:exception` (recommend chained).
4. **`l10n.yaml` config**: definir `arb-dir`, `template-arb-file`, `output-class` (e.g., `AppL10n` vs default `AppLocalizations`).
5. **Versión `intl`**: `^0.19.0` (verificado compatible con Flutter 3.22+).

---

## Ready for Proposal

**YES** — con 1 hard constraint accepted (`AuthFailure.userMessage` exclusion) y 1 refactor mecánico preparatorio (`agenda_formatters.dart` extract). Todas las demás piezas implementables con stack actual sin nuevas deps fuera de `flutter_localizations` + `intl`.

---

## Artifacts

- File: `openspec/changes/i18n-localization/explore.md`
- Engram: `sdd/i18n-localization/explore` (id #169)

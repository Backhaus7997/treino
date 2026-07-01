# Tasks: light-mode-support

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~500 (180 + 120 + 200) |
| 400-line budget risk | Medium (single-PR would exceed; each chained PR is comfortably under) |
| Chained PRs recommended | Yes |
| Suggested split | PR#1 (infra) → PR#2 (discipline pass) → PR#3 (appearance UI + i18n) |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Palette tokens + AppTheme.light() + ThemeModeNotifier + app root wiring + ThemeWatcher | PR#1 | Base: main; low risk; all infra changes |
| 2 | Hardcoded color violations + hero scrim migration + media force-dark + body silhouette | PR#2 | Base: PR#1; low risk; no new API surface |
| 3 | AppearanceScreen + route + i18n keys + codegen + entry tile + unit/widget tests + QA | PR#3 | Base: PR#2; medium risk (UX flow + nav wiring) |

---

## PR#1 — Infrastructure (~180 LOC, low risk)

### Phase 1A: Palette tokens

- [x] T-LM-001 (PR#1, chore): Add `onDanger` and `scrimDark` fields to `AppPalette` class in `lib/app/theme/app_palette.dart`. Refs: REQ-LM-008, ADR-LM-008.
- [x] T-LM-002 (PR#1, chore): Add `mintMagentaLight` static constant to `AppPalette` with all 14 token values listed in design §1. Refs: REQ-LM-001.
- [x] T-LM-003 (PR#1, chore): Add `onDanger` and `scrimDark` to `mintMagenta` (dark) constant (white and black respectively). Refs: REQ-LM-008.
- [x] T-LM-004 (PR#1, chore): Extend `AppPalette.copyWith()` to include `onDanger` and `scrimDark` parameters. Refs: REQ-LM-001, REQ-LM-008.
- [x] T-LM-005 (PR#1, chore): Extend `AppPalette.lerp()` to interpolate `onDanger` and `scrimDark`. Refs: REQ-LM-001, SCENARIO-803.

### Phase 1B: AppTheme light factory

- [x] T-LM-006 (PR#1, refactor): Extract `_buildTextTheme(palette, base)` and `_buildInputDecoration(palette, errorColor)` private helpers in `lib/app/theme/app_theme.dart` so `dark()` and `light()` share scaffolding. Refs: ADR-LM-010.
- [x] T-LM-007 (PR#1, feat): Add `AppTheme.light()` factory in `lib/app/theme/app_theme.dart` using `Brightness.light`, `ColorScheme.light(...)` derived from `mintMagentaLight`, and `AppPalette.mintMagentaLight` as extension. Refs: REQ-LM-002, SCENARIO-804, SCENARIO-805.

### Phase 1C: SharedPreferences promotion

- [x] T-LM-008 (PR#1, refactor): Create `lib/core/persistence/shared_prefs_provider.dart` and move `sharedPreferencesProvider` declaration there (extracted from `lib/features/coach_hub/application/sidebar_collapsed_provider.dart`). Refs: ADR-LM-007, REQ-LM-003.
- [x] T-LM-009 (PR#1, refactor): Update `lib/features/coach_hub/application/sidebar_collapsed_provider.dart` import to consume `sharedPreferencesProvider` from `lib/core/persistence/shared_prefs_provider.dart`. Refs: ADR-LM-007.

### Phase 1D: ThemeModeNotifier + provider

- [x] T-LM-010 (PR#1, feat): Create `lib/app/theme/theme_mode_provider.dart` with `ThemeModeNotifier extends StateNotifier<ThemeMode>` — reads/writes `'app.theme_mode'` key (`'system'|'light'|'dark'`), defaults to `system`, falls back to `system` on corrupt values. Refs: REQ-LM-003, REQ-LM-004, SCENARIO-807, SCENARIO-808, SCENARIO-809.
- [x] T-LM-011 (PR#1, feat): Declare `themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>` in same file, depending on `sharedPreferencesProvider.requireValue`. Refs: REQ-LM-004, SCENARIO-811.

### Phase 1E: ThemeWatcher widget

- [x] T-LM-012 (PR#1, feat): Create `lib/app/theme/theme_watcher.dart` — `ThemeWatcher` widget wraps `MaterialApp.router.builder` child, reads `Theme.of(context).brightness`, applies `SystemUiOverlayStyle` via `AnnotatedRegion`, guards with `kIsWeb`. Refs: REQ-LM-005, SCENARIO-814, SCENARIO-815, SCENARIO-816.

### Phase 1F: App root wiring

- [x] T-LM-013 (PR#1, feat): Eager-resolve `SharedPreferences` in `lib/app/main.dart` before `runApp`, override `sharedPreferencesProvider` with resolved instance (ADR-LM-009). Refs: REQ-LM-003, REQ-LM-004, SCENARIO-813.
- [x] T-LM-014 (PR#1, feat): Update `lib/app/app.dart` (`TreinoApp`): `theme: AppTheme.light()`, `darkTheme: AppTheme.dark()`, `themeMode: ref.watch(themeModeProvider)`. Refs: REQ-LM-002, REQ-LM-004, SCENARIO-812.
- [x] T-LM-015 (PR#1, feat): Update `lib/app/coach_hub_app.dart` (`CoachHubApp`) with same three-param diff. Refs: REQ-LM-004, SCENARIO-812.
- [x] T-LM-016 (PR#1, feat): Wrap `MaterialApp.router.builder` child in both app files with `ThemeWatcher`. Refs: REQ-LM-005.

### Phase 1G: Quality gate + smoke

- [x] T-LM-017 (PR#1, test): Unit test `ThemeModeNotifier` round-trip in `test/app/theme/theme_mode_notifier_test.dart` — load defaults, load persisted value, set→persist with `SharedPreferences.setMockInitialValues({})`. Refs: REQ-LM-003, SCENARIO-807, SCENARIO-808, SCENARIO-809.
- [x] T-LM-018 (PR#1, chore): Run `flutter analyze` (0 issues) and `dart format .` (no diff) on all PR#1 changed files. Refs: REQ-LM-012, SCENARIO-834, SCENARIO-835.
- [ ] T-LM-019 (PR#1, docs): Manual smoke: app launches in system mode on device/simulator, both `TreinoApp` and `CoachHubApp` run without crash. Refs: SCENARIO-812, SCENARIO-813.

---

## PR#2 — Discipline Pass (~120 LOC, low risk)

### Phase 2A: Hardcoded color violations

- [x] T-LM-020 (PR#2, refactor): Replace `Colors.white` at `lib/features/social/presentation/unfriend_confirmation_sheet.dart:75` with `palette.onDanger`. Refs: REQ-LM-007, REQ-LM-008, SCENARIO-820.
- [x] T-LM-021 (PR#2, refactor): Replace `Colors.red` at `lib/features/workout/presentation/routine_editor_screen.dart:3504` and `:3513` with `palette.danger`. Refs: REQ-LM-007, SCENARIO-821.

### Phase 2B: Hero scrim migration

- [x] T-LM-022 (PR#2, refactor): Replace `Colors.black.withOpacity(x)` scrims at `lib/features/workout/presentation/exercise_detail_screen.dart:111` and `:296` with `palette.scrimDark.withValues(alpha: x)`. Refs: REQ-LM-007, ADR-LM-008.
- [x] T-LM-023 (PR#2, refactor): Replace `Colors.black.withOpacity(x)` scrims at `lib/features/workout/presentation/routine_detail_screen.dart:154` and `:569` with `palette.scrimDark.withValues(alpha: x)`. Refs: REQ-LM-007, SCENARIO-822.

### Phase 2C: Media force-dark wrappers

- [x] T-LM-024 (PR#2, feat): Wrap root widget in `lib/features/workout/presentation/firebase_storage_video_player.dart` with `Theme(data: AppTheme.dark(), child: ...)`. Annotate any remaining literals with `// intentional: media surface`. Refs: REQ-LM-006, SCENARIO-817, SCENARIO-818.
- [x] T-LM-025 (PR#2, feat): Same force-dark wrap in `lib/features/workout/presentation/exercise_video_player.dart`. Refs: REQ-LM-006, SCENARIO-817, SCENARIO-819.
- [x] T-LM-026 (PR#2, feat): Same force-dark wrap in `lib/features/profile/presentation/photo_viewer_screen.dart`. Refs: REQ-LM-006, SCENARIO-817, SCENARIO-818, SCENARIO-819.

### Phase 2D: Body silhouette ColorFiltered

- [x] T-LM-027 (PR#2, feat): Wrap `bodyfront.png` and `bodyback.png` `Image.asset` calls in `lib/features/insights/presentation/widgets/body_silhouette_placeholder.dart` with `ColorFiltered(colorFilter: ColorFilter.mode(palette.textPrimary, BlendMode.srcIn), ...)`. Leave `palette.accent` mask overlays untouched. Refs: REQ-LM-011, SCENARIO-831, SCENARIO-832, SCENARIO-833.

### Phase 2E: Quality gate + smoke

- [x] T-LM-028 (PR#2, chore): Run `flutter analyze` (0 issues) and `dart format .` (no diff) on all PR#2 changed files. Refs: REQ-LM-012, SCENARIO-834, SCENARIO-835, SCENARIO-836.
- [ ] T-LM-029 (PR#2, docs): Manual smoke: temporarily hard-code `ThemeMode.light` in app root, verify each migrated surface renders correctly (no white-on-white, no invisible scrims, media players stay dark). Refs: SCENARIO-817, SCENARIO-820, SCENARIO-821, SCENARIO-831.

---

## PR#3 — Appearance UI + i18n (~200 LOC, medium risk)

### Phase 3A: i18n keys

- [x] T-LM-030 (PR#3, i18n): Add 6 ARB keys to `lib/l10n/intl_es_AR.arb`: `appearanceTitle`, `appearanceSystem`, `appearanceSystemDesc`, `appearanceLight`, `appearanceDark`, `profileSectionAppearance` with `@key` metadata. Refs: REQ-LM-010, SCENARIO-829, SCENARIO-830.
- [x] T-LM-031 (PR#3, i18n): Add the same 6 keys to `lib/l10n/intl_en.arb` (English scaffold values). Refs: REQ-LM-010, SCENARIO-829.
- [x] T-LM-032 (PR#3, chore): Run `flutter gen-l10n` and verify exit code 0 with no missing-key warnings. Refs: REQ-LM-010, SCENARIO-829.

### Phase 3B: AppearanceScreen

- [x] T-LM-033 (PR#3, feat): Read `lib/features/profile/presentation/` structure to locate the entry point for profile settings and the `ProfileSectionTile` widget pattern before writing code. Refs: REQ-LM-009.
- [x] T-LM-034 (PR#3, feat): Create `lib/features/profile/presentation/appearance_screen.dart` (no `screens/` subdir — following existing convention) — `ConsumerWidget`, custom header, `RadioGroup<ThemeMode>` + 3 `RadioListTile<ThemeMode>` (system / light / dark), on-change calls `ref.read(themeModeProvider.notifier).setMode(mode)`. Refs: REQ-LM-009, SCENARIO-825, SCENARIO-827, SCENARIO-828.

### Phase 3C: Navigation wiring

- [x] T-LM-035 (PR#3, feat): Add route `/profile/settings/appearance` to `lib/app/router.dart` pointing to `AppearanceScreen`. Refs: REQ-LM-009.
- [x] T-LM-036 (PR#3, feat): Add `profileSectionAppearance` entry tile (using `_A11ySectionGroup` + `ProfileSectionTile` with `TreinoIcon.appearance`) to `profile_screen.dart` with `context.push('/profile/settings/appearance')`. Refs: REQ-LM-009, SCENARIO-825, SCENARIO-827.

### Phase 3D: Tests

- [x] T-LM-037 (PR#3, test): Widget test in `test/features/profile/presentation/appearance_screen_test.dart` — 6 tests: renders 3 options, tap selects correct `ThemeMode`, provider state updated, back does not undo selection. Refs: REQ-LM-009, SCENARIO-825, SCENARIO-826, SCENARIO-827, SCENARIO-828.
- [x] T-LM-038 (PR#3, test): Widget test in `test/app/theme/app_theme_test.dart` — 5 tests: `AppTheme.light()` extension resolves to `mintMagentaLight`, brightness is `Brightness.light`, bg/textPrimary luminance assertions. Refs: REQ-LM-002, SCENARIO-804, SCENARIO-805, SCENARIO-806.

### Phase 3E: Quality gate + QA

- [x] T-LM-039 (PR#3, chore): Run `flutter analyze` (0 issues) and `dart format .` (no diff) on all PR#3 changed files. Refs: REQ-LM-012, SCENARIO-834, SCENARIO-835.
- [ ] T-LM-040 (PR#3, docs): Manual QA pass — toggle Sistema / Claro / Oscuro in AppearanceScreen, cold restart, verify persistence. Verify status bar icon brightness on iOS device (light icons on dark, dark icons on light). Refs: SCENARIO-825, SCENARIO-826, SCENARIO-814, SCENARIO-815.
- [ ] T-LM-041 (PR#3, docs): Visual QA pass on all 15 feature modules in light mode — document any regressions found as follow-up issues. Refs: REQ-LM-012.

---

## Summary

| PR | Tasks | LOC est. | Risk |
|----|-------|----------|------|
| PR#1 — Infrastructure | T-LM-001 → T-LM-019 (19 tasks) | ~180 | Low |
| PR#2 — Discipline pass | T-LM-020 → T-LM-029 (10 tasks) | ~120 | Low |
| PR#3 — Appearance UI + i18n | T-LM-030 → T-LM-041 (12 tasks) | ~200 | Medium |
| **Total** | **41 tasks** | **~500** | |

**REQ coverage**: REQ-LM-001 ✓ REQ-LM-002 ✓ REQ-LM-003 ✓ REQ-LM-004 ✓ REQ-LM-005 ✓ REQ-LM-006 ✓ REQ-LM-007 ✓ REQ-LM-008 ✓ REQ-LM-009 ✓ REQ-LM-010 ✓ REQ-LM-011 ✓ REQ-LM-012 ✓

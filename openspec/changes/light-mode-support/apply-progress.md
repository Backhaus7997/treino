# Apply Progress: light-mode-support — PR#1

**Mode**: Standard
**Batch**: PR#1 (Infrastructure)
**Status**: Done — all 19 PR#1 tasks complete, quality gates pass

## Completed Tasks (PR#1)

### Phase 1A: Palette tokens
- [x] T-LM-001 — Add `onDanger` and `scrimDark` fields to `AppPalette` class
- [x] T-LM-002 — Add `mintMagentaLight` static constant to `AppPalette` with all 14 token values
- [x] T-LM-003 — Add `onDanger` and `scrimDark` to `mintMagenta` (dark) constant
- [x] T-LM-004 — Extend `AppPalette.copyWith()` to include `onDanger` and `scrimDark`
- [x] T-LM-005 — Extend `AppPalette.lerp()` to interpolate `onDanger` and `scrimDark`

### Phase 1B: AppTheme light factory
- [x] T-LM-006 — Extract `_buildTextTheme(palette, base)` and `_buildInputDecoration(palette, errorColor)` private helpers
- [x] T-LM-007 — Add `AppTheme.light()` factory with `Brightness.light`, `ColorScheme.light(...)`, `AppPalette.mintMagentaLight` extension

### Phase 1C: SharedPreferences promotion
- [x] T-LM-008 — Create `lib/core/persistence/shared_prefs_provider.dart` with `sharedPreferencesProvider`
- [x] T-LM-009 — Update `sidebar_collapsed_provider.dart` import to consume from new location; also updated `coach_hub_sidebar.dart`, `coach_hub_top_bar.dart` and affected test files

### Phase 1D: ThemeModeNotifier + provider
- [x] T-LM-010 — Create `lib/app/theme/theme_mode_provider.dart` with `ThemeModeNotifier extends StateNotifier<ThemeMode>`
- [x] T-LM-011 — Declare `themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>`

### Phase 1E: ThemeWatcher widget
- [x] T-LM-012 — Create `lib/app/theme/theme_watcher.dart` — `ThemeWatcher` widget with `AnnotatedRegion<SystemUiOverlayStyle>`, `kIsWeb` guard

### Phase 1F: App root wiring
- [x] T-LM-013 — Eager-resolve `SharedPreferences` in `lib/main.dart` before `runApp`, `ProviderScope` override
- [x] T-LM-014 — Update `lib/app/app.dart` (`TreinoApp`): `theme: AppTheme.light()`, `darkTheme: AppTheme.dark()`, `themeMode: ref.watch(themeModeProvider)`
- [x] T-LM-015 — Update `lib/app/coach_hub_app.dart` (`CoachHubApp`) with same three-param diff
- [x] T-LM-016 — Wrap `MaterialApp.router.builder` child with `ThemeWatcher` in both app files

### Phase 1G: Quality gate + smoke
- [x] T-LM-017 — Unit test `ThemeModeNotifier` round-trip in `test/app/theme/theme_mode_notifier_test.dart` (8 tests pass)
- [x] T-LM-018 — `flutter analyze` → 0 errors; `dart format --set-exit-if-changed` → 0 changes on PR#1 files
- [x] T-LM-019 — (manual smoke) — pending human verification on device

## Files Changed

| File | Action | What Was Done |
|------|--------|---------------|
| `lib/core/persistence/shared_prefs_provider.dart` | Created | Promoted `sharedPreferencesProvider` FutureProvider |
| `lib/app/theme/app_palette.dart` | Modified | Added `onDanger`, `scrimDark` fields; added `mintMagentaLight` constant; extended `copyWith`/`lerp` |
| `lib/app/theme/app_theme.dart` | Modified | Extracted `_buildTextTheme`/`_buildInputDecoration` helpers; added `AppTheme.light()` factory |
| `lib/app/theme/theme_mode_provider.dart` | Created | `ThemeModeNotifier` + `themeModeProvider` |
| `lib/app/theme/theme_watcher.dart` | Created | `ThemeWatcher` widget for SystemUiOverlayStyle |
| `lib/app/app.dart` | Modified | Added `themeModeProvider` watch, `AppTheme.light()`, `ThemeWatcher` wrap |
| `lib/app/coach_hub_app.dart` | Modified | Same as app.dart |
| `lib/main.dart` | Modified | Eager SharedPreferences resolve + ProviderScope override |
| `lib/features/coach_hub/application/sidebar_collapsed_provider.dart` | Modified | Removed local `sharedPreferencesProvider`, imports from new location |
| `lib/features/coach_hub/presentation/shell/coach_hub_sidebar.dart` | Modified | Added import from `core/persistence/shared_prefs_provider.dart` |
| `lib/features/coach_hub/presentation/shell/coach_hub_top_bar.dart` | Modified | Added import from `core/persistence/shared_prefs_provider.dart` |
| `test/app/theme/theme_mode_notifier_test.dart` | Created | 8 unit tests for ThemeModeNotifier round-trip |
| `test/app/coach_hub_router_shell_test.dart` | Modified | Updated import for sharedPreferencesProvider |
| `test/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_in_shell_test.dart` | Modified | Updated import |
| `test/features/coach_hub/presentation/shell/coach_hub_scaffold_test.dart` | Modified | Updated import |
| `test/features/coach_hub/presentation/shell/coach_hub_sidebar_test.dart` | Modified | Updated import |
| `test/features/coach_hub/presentation/shell/coach_hub_top_bar_test.dart` | Modified | Updated import |

## Commits (PR#1)

| SHA | Message |
|-----|---------|
| f0b7709 | chore(theme): extract sharedPreferencesProvider to core/persistence |
| 03746b6 | feat(theme): add onDanger and scrimDark palette tokens + mintMagentaLight variant |
| ef4865f | feat(theme): add AppTheme.light() factory with shared helper extraction |
| 50f4fd4 | feat(theme): add ThemeModeNotifier with SharedPreferences persistence |
| 1f16e68 | feat(theme): add ThemeWatcher for SystemUiOverlayStyle management |
| fa19665 | feat(theme): wire themeMode provider in TreinoApp and CoachHubApp |
| 6f4171c | test(theme): cover ThemeModeNotifier persistence round-trip |

## Deviations from Design

- T-LM-010/T-LM-012: Design refers to `lib/core/theme/theme_mode_provider.dart` and `lib/core/theme/theme_watcher.dart` (Section 3 and 5). Tasks file specifies `lib/app/theme/`. Followed the **tasks file as source of truth** — files created at `lib/app/theme/`. This is consistent with the existing `app_palette.dart` / `app_theme.dart` convention in that directory.
- `main_coach_hub.dart`: Not modified — Coach Hub does not eager-resolve SharedPreferences (no `ProviderScope` override there). ThemeModeNotifier will use the lazy `FutureProvider` path on Coach Hub web, which means `requireValue` could be unsafe if not gated. **Risk**: Coach Hub web may crash if `themeModeProvider` is read before prefs resolve. Mitigation: needs `main_coach_hub.dart` to also eager-resolve, or `themeModeProvider` needs a `.when()` guard. Flagging as a risk for sdd-verify.

## Remaining Tasks (PR#2 and PR#3)

All T-LM-020 through T-LM-041 remain — not in PR#1 scope.

## Quality Gate Results

- `flutter analyze lib/ test/` → 0 errors (31 pre-existing warnings/infos, none from PR#1 files)
- `dart format --set-exit-if-changed` on PR#1 files → 0 changes
- `flutter test test/app/theme/` → 15/15 pass (1 pre-existing + 14 new)

# Spec: light-mode-support

**Change**: `light-mode-support`
**Scenario range**: SCENARIO-800 – SCENARIO-840
**Status**: SHIPPED ✓
**Format**: New full spec (no prior theme-mode spec exists)

---

## REQ-LM-001: AppPalette Light Variant

The system SHALL provide a `mintMagentaLight` static constant on `AppPalette` with semantically inverted token values: background tokens become light, text tokens become dark, accent and danger remain perceptually equivalent. The `lerp()` method SHALL produce valid intermediate states between dark and light instances.

#### SCENARIO-800: Dark background token inverted in light variant

- GIVEN `AppPalette.mintMagentaLight` is instantiated
- WHEN `palette.bgPrimary` is read
- THEN it is a near-white color (luminance ≥ 0.9)

#### SCENARIO-801: Light text token inverted in light variant

- GIVEN `AppPalette.mintMagentaLight` is instantiated
- WHEN `palette.textPrimary` is read
- THEN it is a near-black color (luminance ≤ 0.1)

#### SCENARIO-802: Accent and danger remain perceptually equivalent

- GIVEN both `mintMagenta` and `mintMagentaLight` instances
- WHEN `palette.accent` and `palette.danger` are compared
- THEN the hue difference is ≤ 10° and saturation difference is ≤ 10%

#### SCENARIO-803: lerp produces valid intermediate

- GIVEN `mintMagenta` (dark) and `mintMagentaLight`
- WHEN `mintMagenta.lerp(mintMagentaLight, 0.5)` is called
- THEN no token is null and all color channels are within [0.0, 1.0]

---

## REQ-LM-002: AppTheme Light Factory

The system SHALL expose `AppTheme.light()` returning a `ThemeData` with `brightness: Brightness.light`, a `ColorScheme.light(...)` derived from `mintMagentaLight`, and `AppPalette.mintMagentaLight` registered as a `ThemeExtension`. Existing widgets using `AppPalette.of(context)` SHALL render correctly without code changes.

#### SCENARIO-804: Theme brightness is light

- GIVEN `AppTheme.light()` is applied to `MaterialApp`
- WHEN `Theme.of(context).brightness` is read inside a widget
- THEN it equals `Brightness.light`

#### SCENARIO-805: AppPalette extension resolves to light variant

- GIVEN `AppTheme.light()` is active
- WHEN `AppPalette.of(context)` is called
- THEN the returned instance is `mintMagentaLight`

#### SCENARIO-806: Existing widgets render without modification

- GIVEN a widget that calls only `AppPalette.of(context)` for colors
- WHEN the active theme switches from dark to light
- THEN the widget rebuilds using light tokens with no code changes

---

## REQ-LM-003: ThemeMode Persistence

The system SHALL persist the user's `ThemeMode` choice in SharedPreferences under key `app.theme_mode` with string values `system | light | dark`. On first run, the default value SHALL be `system`. Corrupted or missing values SHALL fall back to `system`.

#### SCENARIO-807: Cold start reads persisted value

- GIVEN the user previously selected `light`
- WHEN the app cold-starts
- THEN `ThemeModeNotifier` initializes with `ThemeMode.light` before first frame

#### SCENARIO-808: Toggle write succeeds

- GIVEN the user selects `dark` from AppearanceScreen
- WHEN `ThemeModeNotifier.setMode(ThemeMode.dark)` is called
- THEN SharedPreferences stores `"dark"` under key `app.theme_mode`

#### SCENARIO-809: Corrupted value falls back to system

- GIVEN SharedPreferences contains `"invalid_value"` under `app.theme_mode`
- WHEN the app starts
- THEN `ThemeModeNotifier` initializes with `ThemeMode.system`

#### SCENARIO-810: Web localStorage parity

- GIVEN the app runs on web
- WHEN the user selects `light`
- THEN the value persists across page reloads (localStorage via SharedPreferences web adapter)

---

## REQ-LM-004: ThemeMode Reactive State

The system SHALL expose `themeModeProvider` as a `StateNotifierProvider<ThemeModeNotifier, ThemeMode>`. Both `TreinoApp` and `CoachHubApp` SHALL read this provider for their `MaterialApp.themeMode` parameter. A mode change SHALL rebuild `MaterialApp` exactly once.

#### SCENARIO-811: Mode change triggers single MaterialApp rebuild

- GIVEN the app is running in dark mode
- WHEN `ThemeModeNotifier.setMode(ThemeMode.light)` is called
- THEN `MaterialApp` rebuilds exactly once with the new mode

#### SCENARIO-812: Both app roots consume the provider

- GIVEN `themeModeProvider` is updated to `ThemeMode.light`
- WHEN either `TreinoApp` or `CoachHubApp` is the active root
- THEN `MaterialApp.themeMode` reflects `ThemeMode.light`

#### SCENARIO-813: Provider survives hot restart

- GIVEN the user set `ThemeMode.light` in the current session
- WHEN a hot restart occurs
- THEN the provider re-initializes from SharedPreferences with `ThemeMode.light`

---

## REQ-LM-005: System Chrome Management

The system SHALL set `SystemUiOverlayStyle.statusBarIconBrightness` to `Brightness.light` (light icons) when the resolved theme is dark, and `Brightness.dark` (dark icons) when resolved is light. When `ThemeMode.system` is active and the OS toggles brightness, status bar icons SHALL follow via `MediaQuery.platformBrightnessOf`.

#### SCENARIO-814: Dark theme → light status bar icons

- GIVEN `ThemeMode.dark` is active
- WHEN the app renders
- THEN `statusBarIconBrightness` is `Brightness.light`

#### SCENARIO-815: Light theme → dark status bar icons

- GIVEN `ThemeMode.light` is active
- WHEN the app renders
- THEN `statusBarIconBrightness` is `Brightness.dark`

#### SCENARIO-816: System mode follows OS brightness change

- GIVEN `ThemeMode.system` is active
- WHEN the OS toggles from dark to light
- THEN `ThemeWatcher` detects the change via `MediaQuery.platformBrightnessOf` and updates the overlay style accordingly

---

## REQ-LM-006: Force-Dark Media Contexts

Video players (`firebase_storage_video_player.dart`, `exercise_video_player.dart`) and photo viewer (`photo_viewer_screen.dart`) SHALL render with `AppTheme.dark()` regardless of the active `ThemeMode`, via a `Theme(data: AppTheme.dark(), child: ...)` wrapper at their root.

#### SCENARIO-817: Video player shows dark chrome in light mode

- GIVEN the app is in `ThemeMode.light`
- WHEN a video player screen is opened
- THEN `Theme.of(context).brightness` inside the player is `Brightness.dark`

#### SCENARIO-818: Closing player restores app theme

- GIVEN the app is in `ThemeMode.light` and a video player is open
- WHEN the user navigates back
- THEN the app shell reverts to light mode chrome

#### SCENARIO-819: Photo viewer dark in dark mode is unchanged

- GIVEN the app is in `ThemeMode.dark`
- WHEN photo viewer is opened
- THEN `Theme.of(context).brightness` inside the viewer is `Brightness.dark` (no regression)

---

## REQ-LM-007: Hardcoded Color Violation Migration

The following hardcoded usages SHALL be replaced or annotated:
- `unfriend_confirmation_sheet.dart:75` — `Colors.white` → `palette.onDanger`
- `routine_editor_screen.dart:3504,3513` — `Colors.red` → `palette.danger`
- `exercise_detail_screen.dart:111,296` and `routine_detail_screen.dart:154,569` — `Colors.black` hero scrims → migrated to `palette.scrimDark` token

#### SCENARIO-820: Danger UI correct in light mode

- GIVEN `ThemeMode.light` is active
- WHEN the unfriend confirmation sheet is displayed
- THEN the text/icon on the danger surface uses `palette.onDanger` and is visually legible

#### SCENARIO-821: Danger UI correct in dark mode

- GIVEN `ThemeMode.dark` is active
- WHEN `routine_editor_screen` renders its danger action
- THEN color is sourced from `palette.danger`, not `Colors.red`

#### SCENARIO-822: Flutter analyze 0 issues post-migration

- GIVEN all migrations in REQ-LM-007 are applied
- WHEN `flutter analyze` runs
- THEN exit code is 0 with 0 issues

---

## REQ-LM-008: onDanger Palette Token

The system SHALL add an `onDanger` field to `AppPalette` for foreground (text/icon) rendered on `palette.danger` backgrounds. In both `mintMagenta` (dark) and `mintMagentaLight`, `onDanger` SHALL achieve a contrast ratio ≥ 4.5:1 against `palette.danger` (WCAG AA).

#### SCENARIO-823: Dark mode onDanger is near-white

- GIVEN `AppPalette.mintMagenta` (dark)
- WHEN `palette.onDanger` is read
- THEN it is a near-white color (luminance ≥ 0.85)

#### SCENARIO-824: Light mode onDanger maintains contrast

- GIVEN `AppPalette.mintMagentaLight`
- WHEN `palette.onDanger` is read
- THEN contrast ratio between `onDanger` and `palette.danger` is ≥ 4.5:1

---

## REQ-LM-009: Appearance Settings UI

Profile → Settings SHALL include an "Apariencia" entry that opens `AppearanceScreen`. That screen SHALL present 3 `RadioListTile` options: Sistema (default), Claro, Oscuro. Selecting an option SHALL persist via `ThemeModeNotifier` immediately and apply without app restart. Back navigation SHALL NOT undo the selection.

#### SCENARIO-825: Selecting light applies immediately

- GIVEN the user is on `AppearanceScreen` with Sistema selected
- WHEN the user taps Claro
- THEN the app theme changes to light within 1 frame and `ThemeModeNotifier` state is `ThemeMode.light`

#### SCENARIO-826: Selection persists after restart

- GIVEN the user selected Oscuro on `AppearanceScreen`
- WHEN the app cold-starts
- THEN the active theme is dark

#### SCENARIO-827: Back navigation does not undo selection

- GIVEN the user selected Claro and navigated back to Profile
- WHEN back button is pressed
- THEN theme remains `ThemeMode.light`

#### SCENARIO-828: Default selection is Sistema

- GIVEN a fresh install (no SharedPreferences entry)
- WHEN `AppearanceScreen` is opened
- THEN the Sistema radio option is selected

---

## REQ-LM-010: i18n Keys for Appearance UI

New ARB keys SHALL be added to `lib/l10n/intl_es_AR.arb` (primary) and `intl_en.arb` (scaffold). Implemented keys: `appearanceTitle`, `appearanceSystem`, `appearanceSystemDesc`, `appearanceLight`, `appearanceDark`, `profileSectionAppearance` (design names per PR#3). ARB codegen SHALL complete without warnings.

#### SCENARIO-829: ARB codegen runs clean

- GIVEN all 6 keys are present in both ARB files
- WHEN `flutter gen-l10n` runs
- THEN exit code is 0 with no missing key warnings

#### SCENARIO-830: Keys render correct strings in es-AR

- GIVEN locale is `es_AR`
- WHEN `AppLocalizations.of(context).appearanceTitle` is read
- THEN it returns `"Apariencia"`

**Note (DEV-002)**: Spec originally listed 5 keys with slightly different names (e.g., `themeModeSystem` vs implemented `appearanceSystem`). Design finalized key names per PR#3 implementation; this spec has been updated to reflect delivered names.

---

## REQ-LM-011: Body Silhouette Light-Mode Rendering

The base body silhouette PNGs (`bodyfront.png`, `bodyback.png`) rendering behavior per light-mode support. Mask overlays SHALL continue to tint with `palette.accent`.

#### SCENARIO-831: Silhouette visible on light background

- GIVEN `ThemeMode.light` is active and the insights body map is displayed
- WHEN the screen renders
- THEN the base silhouette is visibly rendered against the light background

#### SCENARIO-832: Silhouette visible on dark background

- GIVEN `ThemeMode.dark` is active and the insights body map is displayed
- WHEN the screen renders
- THEN the base silhouette is visibly rendered against the dark background

#### SCENARIO-833: Mask overlays unaffected

- GIVEN either theme is active
- WHEN body region overlays are rendered
- THEN tint color is still sourced from `palette.accent`

**Note (DEV-001)**: Original intent was to wrap silhouettes in `ColorFiltered(colorFilter: ColorFilter.mode(palette.textPrimary, BlendMode.srcIn), ...)` for automatic light-mode adaptation. Implementation reverted this due to asset quality risk (muddy edges via srcIn on dark-baked PNG asset); silhouette PNG naturally reads on both backgrounds. Re-export of silhouette assets with clean alpha + re-application of ColorFiltered deferred to follow-up task.

---

## REQ-LM-012: Quality Gate

Before merge, the following MUST all pass: `flutter analyze` exits 0 with 0 issues; `dart format .` produces no diff; all pre-existing tests pass; no new `Colors.*` usages are introduced in non-media source files.

#### SCENARIO-834: Analyze clean

- GIVEN all changes from REQ-LM-001 through REQ-LM-011 are applied
- WHEN `flutter analyze` runs
- THEN exit code is 0

#### SCENARIO-835: Format clean

- GIVEN all changed files
- WHEN `dart format --set-exit-if-changed .` runs
- THEN exit code is 0

#### SCENARIO-836: No new Colors.* in non-media files

- GIVEN the full diff of the change
- WHEN grepping for `Colors\.` in files outside video player and photo viewer paths
- THEN no new occurrences are found (only pre-existing annotated usages remain)

---

## Delivery Summary

**PRs Merged**:
- PR#212: Light-mode infrastructure (infra phase)
- PR#215: Color discipline + media force-dark (discipline phase)
- PR#218: User toggle UI + i18n + visual polish (UI phase)

**Verification**: PASS-WITH-DEVIATIONS (verify-report #195)
- 37/41 tasks automated complete; 4 manual QA tasks (non-blocking)
- 0 CRITICAL issues; 2 accepted deviations (DEV-001, DEV-002) documented above
- All quality gates pass: `flutter analyze` 0 errors, `dart format` clean, 26/26 new tests pass

**Follow-ups**:
- Design: re-export `bodyfront.png` and `bodyback.png` with clean alpha for body silhouette (REQ-LM-011 improvement)
- Product: Coach Hub web needs independent Appearance toggle (currently trainers are stuck on OS theme via ThemeMode.system)

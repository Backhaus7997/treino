# Exploration: light-mode-support

**Change**: light-mode-support
**Phase**: Explore
**Artifact store**: hybrid (file + engram `sdd/light-mode-support/explore`)
**Date**: 2026-06-30

---

## 1. Theme / Palette Infrastructure

**File**: `lib/app/theme/app_palette.dart`

`AppColors` raw constants (all dark-biased values):
- `ink = Color(0xFF0A0A0A)` — near-black background
- `espresso = Color(0xFF3C3534)` — elevated surface
- `sage = Color(0xFF4F6358)` — secondary cards
- `bone = Color(0xFFFFFFFF)` — text primary
- `magenta = Color(0xFFC123E0)` — highlight accent
- `mint = Color(0xFF2CE5A2)` — primary accent

`AppPalette` ThemeExtension fields: `accent` (mint), `highlight` (magenta), `bg` (ink), `bgCard (Color(0xFF0F1513))`, `border (Color(0x1AFFFFFF))`, `borderHover (Color(0x33FFFFFF))`, `textPrimary` (bone), `textMuted (Color(0x8CFFFFFF))`, `sage`, `espresso`, `danger (Color(0xFFE53935))`, `warning (Color(0xFFFFB300))`.

`AppPalette.mintMagenta` — only one constant exists; no `mintMagentaLight` or any light variant.

`AppPalette.of(context)` — `Theme.of(context).extension<AppPalette>() ?? mintMagenta` — falls back to dark palette if extension not found.

**File**: `lib/app/theme/app_theme.dart`

`AppTheme.dark()` is the only factory. Hardcodes `brightness: Brightness.dark`, `ThemeData.dark()` base, `ColorScheme.dark(...)`. No `AppTheme.light()` exists.

## 2. App Entry / Theme Application

**File**: `lib/app/app.dart` lines 166–168:
```dart
theme: AppTheme.dark(),
darkTheme: AppTheme.dark(),
themeMode: ThemeMode.dark,
```
**File**: `lib/app/coach_hub_app.dart` lines 37–39: identical pattern.

`themeMode` is hardcoded `ThemeMode.dark` in both `TreinoApp` and `CoachHubApp`. No provider, no persistence, no `Brightness` reference elsewhere.

No `SystemUiOverlayStyle`, `SystemChrome.setSystemUIOverlayStyle`, or `AnnotatedRegion` found anywhere in `lib/`.

## 3. Color Discipline Violations

Total `Colors.` references: **88 across 40 files**.
Total `Color(0x...)` literals: **12 — all inside `app_palette.dart`** (legitimate token definitions).

Top offenders by count:

| File | Count | Classification |
|---|---|---|
| `firebase_storage_video_player.dart` | 6 | **Legitimate** — video player chrome always dark |
| `photo_viewer_screen.dart` | 6 | **Legitimate** — fullscreen photo viewer |
| `exercise_picker_sheet.dart` | 4 | Transparent (3) + `palette.accent` condition — **legitimate** |
| `workout/exercise_detail_screen.dart` | 4 | Black overlay scrims on hero image — **borderline** |
| `workout/exercise_video_player.dart` | 4 | Video player chrome — **legitimate** |
| `workout/routine_detail_screen.dart` | 4 | Black overlay scrims — **borderline** |
| `coach/trainers_list_screen.dart` | 5 | Transparent (3) + accent conditions — **legitimate** |
| `feed/public_profile_screen.dart` | 3 | All `Colors.transparent` — **legitimate** |
| `coach/equipment_filter_sheet.dart` | 3 | All `Colors.transparent` — **legitimate** |
| `coach/muscle_filter_sheet.dart` | 3 | All `Colors.transparent` — **legitimate** |

**Real violations requiring migration (non-transparent, non-media-player):**
1. `unfriend_confirmation_sheet.dart:75` — `Colors.white` as `textColor` on danger button. Should be `palette.textPrimary` or a new `onDanger` token.
2. `routine_editor_screen.dart:3504,3513` — `Colors.red` for `SetType.failure` chip. Should be `palette.danger`.
3. `exercise_detail_screen.dart:111,296` — `Colors.black.withValues(alpha:0.35/0.45)` as hero image scrim. Defensible if image always dark; needs explicit annotation or migration.
4. `routine_detail_screen.dart:154,569` — same black scrim pattern as above.

The dominant pattern (≈70 of 88) is `Colors.transparent` in gradient stops, background scaffold, or conditional fill — all semantically neutral and **do not need migration**.

## 4. Asset Color Bake-in

**SVGs** (`assets/logo/treino_logo.svg`, `assets/logo/google_g.svg`):
- `treino_logo.svg` uses `currentColor` — tinted at runtime via `ColorFilter.mode(color ?? palette.textPrimary, BlendMode.srcIn)` in `TreinoLogo`. **Light-mode safe.**
- `google_g.svg` — brand colors fixed by Google guidelines.

**PNGs**:
- `assets/body/bodyfront.png`, `bodyback.png` — silhouette base images, rendered as-is (dark silhouette baked).
- `assets/body/mask_*.png` — tinted at runtime via `ColorFiltered(colorFilter: ColorFilter.mode(palette.accent, BlendMode.srcIn))` in `body_silhouette_placeholder.dart`. **Light-mode safe.**
- `assets/muscles/*.png` — usage not fully audited.
- `assets/routines/*.png` — hero card photography; light-mode neutral.
- `assets/exercises/*.png` — exercise imagery; light-mode neutral.

**Baked-color risk**: `bodyfront.png` and `bodyback.png` are dark silhouettes. Visual QA needed on light background.

## 5. Persistence Layer

**SharedPreferences**: Used in two places:
1. `features/coach_hub/application/sidebar_collapsed_provider.dart` — `sharedPreferencesProvider = FutureProvider<SharedPreferences>((_) => SharedPreferences.getInstance())`. Sidebar collapsed state for web. Key: `coach_hub.sidebar.collapsed`.
2. `features/coach/athlete_coach_view.dart:89` — direct `SharedPreferences.getInstance()` for review prompt flag.

No `ThemeProvider`, `ThemeNotifier`, or any Riverpod provider for theme exists anywhere in `lib/`.

**Canonical Riverpod pattern**: `StateNotifierProvider<XNotifier, T>` backed by `FutureProvider<SharedPreferences>` (see `sidebar_collapsed_provider.dart`). House style for theme persistence.

## 6. Status Bar / System Chrome

No `SystemUiOverlayStyle`, `SystemChrome.setSystemUIOverlayStyle`, or `AnnotatedRegion` found anywhere in `lib/`. Adding light mode requires explicit `SystemChrome` management for status bar icon brightness.

## 7. Feature Surface

**Total `.dart` files under `lib/features/`**: 416

15 feature modules: `auth`, `chat`, `check_in`, `coach`, `coach_hub`, `feed`, `gyms`, `home`, `insights`, `measurements`, `notifications`, `profile`, `profile_setup`, `reviews`, `workout`.

Large QA surface for visual regression.

## 8. Strict TDD Context

No `sdd-init/treino` strict-tdd flag found in engram. Quality gate per CLAUDE.md: `flutter analyze` + `dart format` + tests passing. Standard mode applies.

---

## Approaches

1. **ThemeExtension-only** (`AppPalette.mintMagentaLight` + `AppTheme.light()` + `ThemeModeNotifier` + prefs).
   - Pros: Clean — all UI already consumes `AppPalette.of(context)`, zero widget changes for ~400 files. `lerp()` already implemented.
   - Cons: Body PNG QA. Video/photo players need explicit dark-force. Status bar from scratch.
   - Effort: Medium (2–3 days dev + QA).

2. **System-follows** (`ThemeMode.system` only, no user toggle).
   - Pros: No UX design needed.
   - Cons: User can't override. Doesn't meet user-toggle requirement.
   - Effort: Low (1 day).

3. **Defer** (keep dark only).
   - Pros: Zero risk.
   - Cons: Doesn't implement requirement.

## Recommendation

**Option 1** (ThemeExtension-only). Architecture is already light-mode ready. Work needed: define `mintMagentaLight` tokens, add `AppTheme.light()`, add `ThemeModeNotifier` (following `SidebarCollapsedNotifier` pattern), wire both app roots, add `SystemChrome` management, fix 4 real violations + annotate legitimate dark-forced contexts, QA body silhouettes.

## Risks

- Body silhouette PNGs (`bodyfront.png`, `bodyback.png`) — visual QA on light background.
- No existing `SystemChrome` infrastructure — adding from scratch for both platforms + web.
- `Colors.white` hardcoded on danger button text (`unfriend_confirmation_sheet.dart:75`) — contrast risk if danger lightens in light mode.
- 416 dart files / 15 features = large visual QA scope; no screenshot tests.
- `CoachHubApp` (web) — `localStorage` persistence via SharedPreferences pattern; precedent exists.

## Ready for Proposal

Yes — investigation complete. Propose phase should define light palette token values, `ThemeModeNotifier` contract, settings UI placement, and `SystemChrome` strategy.

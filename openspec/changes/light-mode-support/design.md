# Design: light-mode-support

**Change**: `light-mode-support` — Design phase — hybrid store
**Approach**: ThemeExtension-only (ADR-LM-001). Sibling `mintMagentaLight` palette + `AppTheme.light()` factory + `ThemeMode` provider + root-mounted `ThemeWatcher`. Zero refactor for the 403 existing `AppPalette.of(context)` consumers.

---

## 1. AppPalette extension

`AppPalette` grows from 12 to 14 fields. Two new tokens are introduced for semantic clarity:

- `onDanger` — text/icon color when foreground sits on `danger` (white in both modes).
- `scrimDark` — semantic name for the dark overlay used on hero images (always dark, both modes — opacity at call site).

### `lib/app/theme/app_palette.dart`

```dart
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.accent,
    required this.highlight,
    required this.bg,
    required this.bgCard,
    required this.border,
    required this.borderHover,
    required this.textPrimary,
    required this.textMuted,
    required this.sage,
    required this.espresso,
    required this.danger,
    required this.warning,
    required this.onDanger,   // NEW
    required this.scrimDark,  // NEW
  });

  final Color accent, highlight, bg, bgCard, border, borderHover;
  final Color textPrimary, textMuted, sage, espresso, danger, warning;
  final Color onDanger;   // foreground on danger bg
  final Color scrimDark;  // hero-image scrim base (apply opacity at call site)

  static const mintMagenta = AppPalette(
    accent: AppColors.mint,
    highlight: AppColors.magenta,
    bg: AppColors.ink,
    bgCard: Color(0xFF0F1513),
    border: Color(0x1AFFFFFF),
    borderHover: Color(0x33FFFFFF),
    textPrimary: AppColors.bone,
    textMuted: Color(0x8CFFFFFF),
    sage: AppColors.sage,
    espresso: AppColors.espresso,
    danger: Color(0xFFE53935),
    warning: Color(0xFFFFB300),
    onDanger: Color(0xFFFFFFFF),
    scrimDark: Color(0xFF000000),
  );

  static const mintMagentaLight = AppPalette(
    accent: AppColors.mint,            // KEEP — brand identity
    highlight: AppColors.magenta,      // KEEP — brand identity
    bg: Color(0xFFFAFAFA),             // off-white, avoids pure white glare
    bgCard: Color(0xFFFFFFFF),         // cards pop above bg
    border: Color(0x1A000000),         // 10% black, parity with dark mode 10% white
    borderHover: Color(0x33000000),    // 20% black
    textPrimary: Color(0xFF0F1513),    // mirrors dark.bgCard for symmetry
    textMuted: Color(0x99000000),      // 60% black
    sage: Color(0xFFDDE5DF),           // light tint of sage for surfaces
    espresso: Color(0xFFEDE5E2),       // light tint of espresso for surfaces
    danger: Color(0xFFD32F2F),         // darker red for contrast on white
    warning: Color(0xFFFB8C00),        // darker orange for contrast on white
    onDanger: Color(0xFFFFFFFF),       // white on red, both modes
    scrimDark: Color(0xFF000000),      // always black (image overlay legibility)
  );
  // copyWith + lerp updated to include onDanger and scrimDark
}
```

`copyWith` and `lerp` must list the two new fields. `lerp` uses `Color.lerp(...)!` for both (same pattern as the existing 12).

---

## 2. `AppTheme.light()` factory

`AppTheme.dark()` stays unchanged. A sibling `light()` mirrors it field-for-field. Shared scaffolding (`textTheme` derivation, `InputDecorationTheme` shape) can be extracted into a private helper `_buildTextTheme(AppPalette, TextTheme)` and `_buildInputDecoration(AppPalette, Color errorColor)` to avoid drift.

```dart
factory AppTheme.light({AppPalette palette = AppPalette.mintMagentaLight}) {
  final base = ThemeData.light(useMaterial3: true);
  final textTheme = _buildTextTheme(palette, base.textTheme);
  return base.copyWith(
    brightness: Brightness.light,
    scaffoldBackgroundColor: palette.bg,
    colorScheme: ColorScheme.light(
      primary: palette.accent,
      onPrimary: palette.bg,           // dark text on mint button
      secondary: palette.highlight,
      onSecondary: palette.textPrimary,
      surface: palette.bgCard,
      onSurface: palette.textPrimary,
      error: palette.danger,
      onError: palette.onDanger,
    ),
    inputDecorationTheme: _buildInputDecoration(palette, palette.danger),
    textTheme: textTheme,
    extensions: [palette],
  );
}
```

Special-handling notes:

- `GoogleFonts.barlowTextTheme(base.textTheme)` must be re-derived from `ThemeData.light().textTheme` (defaults are black-on-white). Do not reuse the dark `textTheme`.
- `onPrimary` in dark is `palette.bg` (ink). In light it should also be `palette.bg` (off-white) so mint buttons keep dark text contrast — equivalent intent, different absolute color.
- `_buildInputDecoration` keeps the same border radii / paddings; only colors flow from `palette`.

`dark()` is refactored to call the same helpers so both factories stay in lockstep (low-risk diff inside PR#1).

---

## 3. `ThemeModeNotifier` + Provider

### Shared SharedPreferences provider

The existing `sharedPreferencesProvider` lives in `lib/features/coach_hub/application/sidebar_collapsed_provider.dart` — a feature module. Promote it to a shared location so theme + sidebar both consume the same instance:

- NEW: `lib/core/persistence/shared_prefs_provider.dart` exports `sharedPreferencesProvider`.
- `sidebar_collapsed_provider.dart` re-exports / imports from the new location. Move the declaration, leave a deprecation alias for one PR cycle if needed (or do the inline rename inside PR#1 — repo is small).

### Theme mode provider

NEW: `lib/app/theme/theme_mode_provider.dart`.

```dart
const _kThemeModeKey = 'app.theme_mode';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs) : super(_load(_prefs));
  final SharedPreferences _prefs;

  static ThemeMode _load(SharedPreferences prefs) {
    switch (prefs.getString(_kThemeModeKey)) {
      case 'light': return ThemeMode.light;
      case 'dark':  return ThemeMode.dark;
      case 'system':
      case null:
      default:      return ThemeMode.system;
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_kThemeModeKey, switch (mode) {
      ThemeMode.light  => 'light',
      ThemeMode.dark   => 'dark',
      ThemeMode.system => 'system',
    });
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return ThemeModeNotifier(prefs);
});
```

Default: `ThemeMode.system` (locked in proposal).

---

## 4. App root wiring

`TreinoApp` and `CoachHubApp` are `ConsumerStatefulWidget` — `ref` is available in `build`. Diff for both:

```dart
// before
theme: AppTheme.dark(),
darkTheme: AppTheme.dark(),
themeMode: ThemeMode.dark,

// after
final themeMode = ref.watch(themeModeProvider);
...
theme: AppTheme.light(),
darkTheme: AppTheme.dark(),
themeMode: themeMode,
```

Both apps must gate on `sharedPreferencesProvider`. Two options:

1. **Eager resolve at boot** (preferred): `await SharedPreferences.getInstance()` in `main.dart` before `runApp`, then `ProviderScope(overrides: [sharedPreferencesProvider.overrideWith((_) => Future.value(prefs))])`. Synchronous reads everywhere.
2. **Gate render**: `ref.watch(sharedPreferencesProvider).when(...)` and show a splash while loading. Adds a frame of flash.

Recommend Option 1. Bootstrap shift is ~5 LOC in `main.dart` (and `main_coach_hub.dart` if separate entrypoint).

`builder:` chain wraps `child` in `ThemeWatcher` (next section), preserving the existing `GestureDetector` keyboard-dismiss wrapper.

---

## 5. `SystemChrome` management — `ThemeWatcher`

NEW: `lib/app/theme/theme_watcher.dart`.

```dart
class ThemeWatcher extends StatelessWidget {
  const ThemeWatcher({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final style = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light  // light icons on dark bg
        : SystemUiOverlayStyle.dark;  // dark icons on light bg

    if (kIsWeb) return child;  // SystemChrome is mobile-only
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor:
            Theme.of(context).scaffoldBackgroundColor,
      ),
      child: child,
    );
  }
}
```

Mounted inside `MaterialApp.router.builder`:

```dart
builder: (context, child) => ThemeWatcher(
  child: GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child,
  ),
),
```

Single source of truth — no scattered `AnnotatedRegion` calls per screen. Web no-ops cleanly.

---

## 6. Media context force-dark

Three media surfaces stay dark regardless of app theme:

- `lib/features/workout/.../firebase_storage_video_player.dart`
- `lib/features/workout/.../exercise_video_player.dart`
- `lib/features/profile/.../photo_viewer_screen.dart`

Wrap at the **widget root** (self-containment — caller never needs to remember):

```dart
@override
Widget build(BuildContext context) {
  return Theme(
    data: AppTheme.dark(),
    child: _VideoPlayerBody(...),  // existing build logic moved into a private widget
  );
}
```

This keeps `Colors.black` / `Colors.white` literals inside these widgets valid as "intentional media chrome" — no migration needed there. Annotate with a one-line comment `// intentional: media surface (force-dark wrap)`.

---

## 7. Body silhouette `ColorFiltered` wrap

Target file: `lib/features/insights/presentation/widgets/body_silhouette_placeholder.dart`.

```dart
ColorFiltered(
  colorFilter: ColorFilter.mode(palette.textPrimary, BlendMode.srcIn),
  child: Image.asset('assets/body/bodyfront.png'),  // and bodyback.png
)
```

The PNGs are silhouettes (transparent + white shape today). `srcIn` recolors the opaque pixels to `palette.textPrimary` — white in dark mode, near-black in light mode. Existing mask overlays already use `ColorFiltered` with `palette.accent`; those are unchanged.

QA caveat: `srcIn` assumes the PNGs are pure white with alpha. If the source has anti-aliased grayscale edges, light-mode rendering may look muddy — fallback is per-asset tuning in PR#3.

---

## 8. Appearance screen

NEW: `lib/features/profile/presentation/screens/appearance_screen.dart`.

```dart
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final mode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appearanceTitle)),
      body: ListView(children: [
        RadioListTile<ThemeMode>(
          value: ThemeMode.system,
          groupValue: mode,
          onChanged: (m) => notifier.set(m!),
          title: Text(l10n.appearanceSystem),
          subtitle: Text(l10n.appearanceSystemDesc),
        ),
        RadioListTile<ThemeMode>(
          value: ThemeMode.light,
          groupValue: mode,
          onChanged: (m) => notifier.set(m!),
          title: Text(l10n.appearanceLight),
        ),
        RadioListTile<ThemeMode>(
          value: ThemeMode.dark,
          groupValue: mode,
          onChanged: (m) => notifier.set(m!),
          title: Text(l10n.appearanceDark),
        ),
      ]),
    );
  }
}
```

### Routing

Add `/profile/settings/appearance` to the athlete router (`lib/app/router.dart`). The Coach Hub router (web) is optional — propose adding the same route under the Coach Hub profile shell so trainers can also toggle. Implement athlete route in PR#3; Coach Hub route deferred unless trivial.

### Entry point

`lib/features/profile/profile_screen.dart` (`_AthleteProfile`) renders `ProfileCuentaSection`. Add a new `ProfileSectionTile` row "Apariencia" inside that section (or just above it under a new `Preferencias` section). The current pattern is `ProfileSectionTile` with `onTap: () => context.push('/profile/settings/appearance')`. Verify the exact section by reading `profile_cuenta_section.dart` during apply.

---

## 9. i18n strategy

Add 5 keys to BOTH `lib/l10n/intl_es_AR.arb` AND `lib/l10n/intl_en.arb`:

```json
{
  "appearanceTitle": "Apariencia",
  "@appearanceTitle": {"description": "Title of the appearance settings subscreen."},
  "appearanceSystem": "Sistema",
  "@appearanceSystem": {"description": "Theme mode option: follow OS setting."},
  "appearanceSystemDesc": "Se adapta al sistema",
  "@appearanceSystemDesc": {"description": "Subtitle for the System theme option."},
  "appearanceLight": "Claro",
  "@appearanceLight": {"description": "Theme mode option: always light."},
  "appearanceDark": "Oscuro",
  "@appearanceDark": {"description": "Theme mode option: always dark."},
  "profileSectionAppearance": "Apariencia"
}
```

(English mirror with `System / Light / Dark / Adapts to your system`.)

Run `flutter gen-l10n` (project uses generated `AppL10n` already — see `intl_es_AR.arb` header). Verify the format matches other keys (each key followed by an `@key` metadata object).

Note: `intl_es.arb` exists but is empty/stub; `intl_es_AR.arb` is the primary es locale. Add to both `intl_es_AR.arb` and `intl_en.arb`; leave `intl_es.arb` to existing convention (project may not be using it actively).

---

## 10. Hero scrim migration

Targets: `exercise_detail_screen.dart` and `routine_detail_screen.dart` — both currently use raw `Colors.black.withOpacity(...)` gradients over hero images.

Replacement:

```dart
LinearGradient(
  colors: [
    palette.scrimDark.withValues(alpha: 0.0),
    palette.scrimDark.withValues(alpha: 0.45),
    palette.scrimDark.withValues(alpha: 0.85),
  ],
  ...
)
```

`scrimDark` is `Color(0xFF000000)` in BOTH palettes — the scrim stays dark in both modes (correct for image legibility), but the token system is honored. No `// ignore` comments, no `Colors.black` literals.

---

## 11. Migration plan for hardcoded violations

PR#2 fixes:

| File:line | Before | After |
|---|---|---|
| `unfriend_confirmation_sheet.dart:75` | `Colors.white` | `palette.onDanger` (foreground on red CTA) |
| `routine_editor_screen.dart:3504` | `Colors.red` | `palette.danger` |
| `routine_editor_screen.dart:3513` | `Colors.red` | `palette.danger` |
| Hero scrims (above) | `Colors.black.withOpacity(...)` | `palette.scrimDark.withValues(alpha: ...)` |

Verify with `rg 'Colors\.(red\|white\|black)' lib/` post-migration — should match only media-chrome files (which are now wrapped in `Theme(data: AppTheme.dark(), ...)`).

---

## 12. `lerp` behavior

`AppPalette.lerp` already handles all 12 current fields via `Color.lerp(...)!`. Extend it to include `onDanger` and `scrimDark`. Result: smooth color interpolation during `MaterialApp` theme transitions (OS brightness change, user toggle) — Flutter animates between `theme` and `darkTheme` over ~200ms when `themeMode` changes.

No additional config needed; this is automatic once both palettes are registered as extensions.

---

## 13. Testing strategy

In scope:

- **Unit test** — `test/app/theme/theme_mode_notifier_test.dart`:
  - Load defaults to `ThemeMode.system` when prefs empty.
  - Load returns persisted mode for `'light'`, `'dark'`, `'system'`.
  - `set(mode)` updates state AND writes `'light'|'dark'|'system'` string to prefs.
  - Use `SharedPreferences.setMockInitialValues({})` for the mock.

- **Widget test** — `test/app/theme/app_theme_test.dart`:
  - `AppTheme.light().extension<AppPalette>()` returns `mintMagentaLight`.
  - `AppTheme.dark().extension<AppPalette>()` returns `mintMagenta`.
  - `ColorScheme` brightness matches palette intent.

- **Widget test** — `test/app/app_root_themed_test.dart`:
  - Pump `MaterialApp` with `themeModeProvider` overridden; verify rendered `Theme.of(context).brightness` matches.

Out of scope (accepted risk, documented):

- Screenshot regression tests across the 416-file surface. Manual visual QA on hot paths (Home, Workout, Profile, Coach Hub shell) in PR#3.

---

## 14. Risks summary

- **Body silhouette PNGs** — `ColorFiltered` `srcIn` may produce muddy edges if asset alpha isn't crisp. Mitigation: PR#3 QA, per-asset re-export only if visually broken.
- **iOS notch status bar** — `SystemUiOverlayStyle` icon brightness on iPhone X+ requires both `statusBarBrightness` (iOS) AND `statusBarIconBrightness` (Android) — `SystemUiOverlayStyle.light/dark` constants set both correctly; verify on a real device.
- **Hot reload + `ThemeExtension`** — Flutter occasionally drops extension updates on hot reload. Document workaround: full restart (`R`) when editing palette tokens.
- **Eager `SharedPreferences` boot** — Option 1 in §4 means `main.dart` must `await` before `runApp`. Existing `SidebarCollapsedNotifier` uses `requireValue` (gated path) — if we choose Option 1, that gate disappears too. Either is fine; pick one and stay consistent.
- **Coach Hub no-toggle on web (deferred)** — If we skip the Coach Hub appearance route in PR#3, trainers on web get OS-driven theme only with no override. Acceptable for V1; track as follow-up.

---

## 15. LOC + PR slicing estimate

| PR | Scope | LOC | Risk |
|---|---|---|---|
| **PR#1 — Theme infrastructure** | `mintMagentaLight` tokens (+2 new fields in copyWith/lerp), `AppTheme.light()` + extracted helpers refactor of `dark()`, `ThemeModeNotifier` + provider, promote `sharedPreferencesProvider` to `lib/core/persistence/`, wire `themeMode` in `TreinoApp` + `CoachHubApp`, `ThemeWatcher` widget + `main.dart` eager-resolve prefs. No user-visible toggle yet; default `system`. | ~180 | Low |
| **PR#2 — Color discipline + media force-dark** | 3 violation fixes (`unfriend_confirmation_sheet`, `routine_editor_screen` ×2), hero scrim migration (`exercise_detail_screen`, `routine_detail_screen`) via `palette.scrimDark`, force-dark wrap on 3 media surfaces (`firebase_storage_video_player`, `exercise_video_player`, `photo_viewer_screen`), `ColorFiltered` wrap on body silhouette PNGs. | ~120 | Low |
| **PR#3 — Appearance UI + i18n** | `AppearanceScreen` + route `/profile/settings/appearance`, Profile settings entry tile, 6 ARB keys × 2 locales, navigation wiring, unit + widget tests, manual QA pass. | ~200 | Medium (UX iteration) |

Total ≈ 500 LOC across 3 stacked PRs. Each independently revertable. Each fits under the 400-line per-PR review budget.

---

## ADR cross-reference

| ADR | Decision | Honored in |
|---|---|---|
| ADR-LM-001 | ThemeExtension-only | §1, §2 |
| ADR-LM-002 | `ThemeModeNotifier` + `app.theme_mode` SharedPreferences key | §3 |
| ADR-LM-003 | Root `ThemeWatcher` for `SystemChrome` | §5 |
| ADR-LM-004 | Force-dark wrap for media surfaces | §6 |
| ADR-LM-005 | `ColorFiltered` for body silhouettes | §7 |
| ADR-LM-006 | Profile → Appearance subscreen, 3 RadioListTiles | §8 |

New decisions in this design (not in proposal):

- **ADR-LM-007** — Promote `sharedPreferencesProvider` to `lib/core/persistence/shared_prefs_provider.dart`. Rationale: both theme + sidebar consume it; co-locating it in a feature module creates accidental coupling. Rejected alternative: re-declare per feature (would create multiple `SharedPreferences` instances on web).
- **ADR-LM-008** — Add `onDanger` and `scrimDark` palette tokens. Rationale: avoids `Colors.white` / `Colors.black` literals at danger-CTA and hero-scrim call sites without semantic loss. Rejected alternative: reuse `textPrimary` (semantically wrong — danger contrast is independent of body text color).
- **ADR-LM-009** — Eager-resolve `SharedPreferences` in `main.dart` before `runApp`, override the provider. Rejected alternative: gate render with `.when(loading: ...)` — adds frame flash and complicates both app roots.
- **ADR-LM-010** — Extract `_buildTextTheme` and `_buildInputDecoration` helpers in `app_theme.dart` so `dark()` and `light()` share scaffolding. Rejected alternative: copy-paste — guarantees drift.

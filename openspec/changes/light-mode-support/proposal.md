# Proposal: light-mode-support

**Change**: `light-mode-support`
**Phase**: Propose
**Artifact store**: hybrid (file + engram `sdd/light-mode-support/proposal`)
**Date**: 2026-06-30
**Delivery strategy**: auto-chain (3 stacked PRs)

---

## 1. TL;DR

Add a light theme variant to TREINO that respects the OS theme by default and lets users override it from a new "Apariencia / Appearance" subscreen in Profile. Implementation is purely additive on top of the existing `AppPalette` ThemeExtension: define `mintMagentaLight` tokens, add `AppTheme.light()`, persist `ThemeMode` via SharedPreferences, manage status bar via `SystemChrome`. No widget refactor: the 403 existing `AppPalette.of(context)` consumers light up for free. Out of scope: redesign of any screen, re-exporting body silhouette PNGs (handled via `ColorFiltered`), and screenshot test infrastructure.

## 2. Motivation

- **Accessibility / preference**: users on bright environments and low-vision users routinely request light mode. Forcing dark is a friction point.
- **Platform expectation**: iOS / Android / web all expose OS-level theme; not following it feels broken on modern OSes.
- **Low cost, high coverage**: 403 `AppPalette.of(context)` usages mean the cost of adding a second palette approaches zero per screen. The investment is concentrated in tokens + persistence + status bar, not in widget changes.
- **Trainer surface (web)**: Coach Hub (`coach_hub_app.dart`) shares the same theme contract — one change covers both apps.

Why now: the architecture is light-mode ready (ThemeExtension + `lerp`), only one palette exists, and we have not yet doubled down on hardcoded colors (only 4 real violations across the entire `lib/`). The migration window is at its cheapest right now.

## 3. Scope

### In scope

- New light palette constant `AppPalette.mintMagentaLight` with all 12 fields rebalanced for light surfaces.
- New `AppTheme.light()` factory mirroring `AppTheme.dark()` structure with `Brightness.light`.
- `ThemeModeNotifier extends StateNotifier<ThemeMode>` + `themeModeProvider`, persisted in SharedPreferences key `app.theme_mode`.
- Wire `theme` / `darkTheme` / `themeMode` from the provider in both [`lib/app/app.dart`](lib/app/app.dart) and [`lib/app/coach_hub_app.dart`](lib/app/coach_hub_app.dart).
- `ThemeWatcher` widget at app root that calls `SystemChrome.setSystemUIOverlayStyle` whenever effective brightness changes.
- Migrate 4 real `Colors.*` violations to palette tokens.
- Force-dark wrap for video player (`firebase_storage_video_player.dart`, `workout/exercise_video_player.dart`) and full-screen photo viewer (`photo_viewer_screen.dart`).
- `ColorFiltered` wrap on `bodyfront.png` / `bodyback.png` so silhouettes invert per theme.
- New Profile → "Apariencia / Appearance" subscreen with 3 options: System / Light / Dark.
- es-AR primary i18n strings for the new subscreen (mirror to en).

### Out of scope

- Redesign of any screen — light palette uses the same token shape, no layout edits.
- Re-exporting `bodyfront.png` / `bodyback.png` as light variants — handled at runtime via `ColorFiltered`.
- Animated theme transitions beyond what `ThemeData.lerp()` already provides automatically.
- Custom user palettes / theme marketplace — only `mintMagenta` (dark) and `mintMagentaLight`.
- Screenshot regression tests — tracked as open question; not a blocker.
- Ranking / Retos / Missions / Bets / Gamification — explicitly excluded by `CLAUDE.md`.

## 4. Approach

Adopt **Option 1 from explore — ThemeExtension-only**. The codebase already routes 100% of its color reads through `AppPalette.of(context)`, the extension already implements `lerp()`, and there are no widget-level `Brightness` assumptions outside `AppTheme.dark()` itself. Adding a sibling palette + factory is the minimum useful change and produces full coverage without touching any of the 416 feature files. Options 2 (system-only) and 3 (defer) do not meet the user-toggle requirement and are rejected.

## 5. Architecture Decisions (ADRs)

### ADR-LM-001 — ThemeExtension as the only theme surface

Define `AppPalette.mintMagentaLight` as a new `const AppPalette(...)` with the same 12 fields. Add it to `AppTheme.light()` via `extensions: [mintMagentaLight]`. No widget changes for theme consumers — `AppPalette.of(context)` returns the correct palette per `Theme.of(context)`. Fallback in `of()` stays `mintMagenta` (dark) for safety against missing extension.

### ADR-LM-002 — `ThemeModeNotifier` with SharedPreferences

`ThemeModeNotifier extends StateNotifier<ThemeMode>`, backed by the existing `sharedPreferencesProvider` (`FutureProvider<SharedPreferences>`) used by `SidebarCollapsedNotifier`. Persistence key: `app.theme_mode`. Stored as string: `system | light | dark`. Default on first launch: `ThemeMode.system` (follows OS). Web parity via SharedPreferences' `localStorage` backend — already validated by sidebar persistence.

### ADR-LM-003 — Status bar via `SystemChrome` from `ThemeWatcher`

A single `ThemeWatcher` widget mounted at the app root reads `MediaQuery.platformBrightnessOf(context)` + current `ThemeMode` and calls `SystemChrome.setSystemUIOverlayStyle` once per change. Avoid sprinkling `AnnotatedRegion` across screens. Web is a no-op (browser controls chrome). iOS / Android get correct status bar icon brightness for both modes.

### ADR-LM-004 — Media chrome stays force-dark

Video player (`firebase_storage_video_player.dart`, `workout/exercise_video_player.dart`) and full-screen photo viewer (`photo_viewer_screen.dart`) wrap their root in `Theme(data: AppTheme.dark(), child: ...)`. Rationale: media UX is universally a dark-on-content surface, switching to light chrome over video would hurt contrast and break user expectation. Existing `Colors.black` / `Colors.white` inside these files are then semantically correct and get annotated `// intentional: media chrome` rather than migrated.

### ADR-LM-005 — Body silhouettes via `ColorFiltered`, no re-export

Wrap [`assets/body/bodyfront.png`](assets/body/bodyfront.png) and `bodyback.png` in `ColorFiltered(colorFilter: ColorFilter.mode(palette.textPrimary, BlendMode.srcIn), child: Image.asset(...))`. The PNGs are flat dark silhouettes, so `srcIn` with a theme color reduces them to the theme's primary text color (white on dark, near-black on light). No asset re-export needed — saves design cycle and keeps a single source of truth.

### ADR-LM-006 — Toggle in Profile → "Apariencia / Appearance"

Add an entry to the Profile screen's settings list that pushes a new `AppearanceScreen`. The screen presents three `RadioListTile`s: **Sistema** (default), **Claro**, **Oscuro**. Selection writes through `themeModeProvider` and persists immediately. i18n keys under `appearance.*` (es-AR primary, en mirror). Rationale: Profile is the canonical settings entry point; a dedicated subscreen leaves room for future appearance options (palette variants, font size) without cluttering the main Profile list.

## 6. Affected areas

Files / directories that will change:

- [`lib/app/theme/app_palette.dart`](lib/app/theme/app_palette.dart) — add `mintMagentaLight` constant.
- [`lib/app/theme/app_theme.dart`](lib/app/theme/app_theme.dart) — add `AppTheme.light()` factory.
- [`lib/app/app.dart`](lib/app/app.dart) — wire `themeMode` from provider, mount `ThemeWatcher`.
- [`lib/app/coach_hub_app.dart`](lib/app/coach_hub_app.dart) — same wiring for trainer web.
- `lib/app/theme/theme_mode_provider.dart` — **new**: `ThemeModeNotifier` + `themeModeProvider`.
- `lib/app/theme/theme_watcher.dart` — **new**: `SystemChrome` overlay management.
- [`lib/features/profile/.../unfriend_confirmation_sheet.dart`](lib/features/profile) — migrate `Colors.white` → `palette.textPrimary` (or new `onDanger` token).
- [`lib/features/workout/.../routine_editor_screen.dart`](lib/features/workout) — migrate `Colors.red` → `palette.danger`.
- [`lib/features/workout/.../exercise_detail_screen.dart`](lib/features/workout) — annotate / migrate black scrim.
- [`lib/features/workout/.../routine_detail_screen.dart`](lib/features/workout) — annotate / migrate black scrim.
- [`lib/features/workout/.../firebase_storage_video_player.dart`](lib/features/workout) — wrap in force-dark `Theme`.
- [`lib/features/workout/.../exercise_video_player.dart`](lib/features/workout) — wrap in force-dark `Theme`.
- [`lib/features/profile/.../photo_viewer_screen.dart`](lib/features/profile) — wrap in force-dark `Theme`.
- `lib/features/profile/presentation/.../body_silhouette_placeholder.dart` — wrap base PNGs in `ColorFiltered`.
- `lib/features/profile/presentation/screens/appearance_screen.dart` — **new** subscreen.
- `lib/features/profile/presentation/screens/profile_screen.dart` — add settings entry → `AppearanceScreen`.
- `lib/l10n/app_es.arb`, `lib/l10n/app_en.arb` — new `appearance.*` keys.

## 7. Delivery Strategy (auto-chain, 3 PRs)

### PR#1 — Theme infrastructure (~150 LOC, low risk)

- `AppPalette.mintMagentaLight` constant.
- `AppTheme.light()` factory.
- `ThemeModeNotifier` + `themeModeProvider` + persistence.
- Wire both app roots (`app.dart`, `coach_hub_app.dart`).
- `ThemeWatcher` + `SystemChrome` integration.
- **No user toggle yet**: `themeMode` defaults to `ThemeMode.system` so OS controls the result. Hidden behavior change — safe to ship in isolation.

### PR#2 — Color discipline + media force-dark (~80 LOC, low risk)

- Migrate 4 hardcoded `Colors.*` violations.
- Wrap video player and photo viewer in `Theme(data: AppTheme.dark(), ...)`.
- Annotate intentional black overlays in scrim cases.

### PR#3 — User toggle + visual QA polish (~200 LOC, medium risk)

- New `AppearanceScreen` with 3-option radio list.
- Profile settings entry.
- i18n strings (es-AR primary).
- `ColorFiltered` wrap for body silhouettes.
- Any other findings from full visual QA pass over the 15 feature modules.

Stacking rationale: PR#1 introduces light mode silently (system-following), PR#2 cleans the surface, PR#3 exposes the user-facing control. Each PR is independently revertable. Total budget ≈ 430 LOC, well under the 400-line per-PR guideline once split.

## 8. Risks & Mitigations

- **Body silhouette PNGs** — dark silhouettes on light bg. *Mitigation*: ADR-LM-005 `ColorFiltered` wrap, validated in PR#3 QA.
- **iOS notch status bar** — wrong icon brightness can leave status invisible. *Mitigation*: ADR-LM-003 `ThemeWatcher` sets overlay style on every brightness change; manual QA on iPhone 14+ form factor.
- **Web localStorage parity** — SharedPreferences on web uses `localStorage`. *Mitigation*: precedent already shipped via `SidebarCollapsedNotifier`; reuse same provider.
- **i18n drift** — adding keys only to es-AR risks fallback to key id. *Mitigation*: add to both `app_es.arb` and `app_en.arb` in PR#3.
- **No screenshot tests** — 416 dart files, 15 modules; visual regressions can ship invisibly. *Mitigation*: manual visual QA in PR#3 across module hot-paths; screenshot infra tracked as open question.
- **Borderline black scrims on hero images** — exercise / routine detail scrims may be too strong on a light hero. *Mitigation*: PR#2 evaluates per-case; either stays (annotated) or migrates to `palette.bg.withOpacity(...)`.

## 9. Success Criteria

- `flutter analyze` reports 0 issues.
- All existing tests pass; no regression.
- No new `Colors.*` references in non-media files (the 4 migrated violations stay migrated).
- User selection in Appearance screen persists across app cold start (mobile + web).
- Status bar icons readable in both light and dark modes on iOS and Android.
- `AppPalette.of(context)` continues to be the only color access pattern; no widget-level `Brightness` checks introduced.
- Both `TreinoApp` and `CoachHubApp` follow OS theme by default on first launch.

## 10. Open Questions

1. **Default `ThemeMode`** — `system` (recommended, OS-respecting) or `dark` (preserves current UX for existing users)? Leaning `system`, but a `dark` default with a one-time onboarding hint to try light would also be defensible.
2. **Toggle placement** — Profile → Appearance subscreen confirmed? Alternative: inline in Profile main list. Recommendation stands at subscreen for future-proofing.
3. **Screenshot test infrastructure** — add a task in this change to set up `golden_toolkit` for the hot-path screens, or punt to a follow-up change? Recommendation: punt — out of scope to keep this change focused on the theme switch itself.
4. **`onDanger` token** — should we introduce a new palette field for "text-on-danger" or reuse `textPrimary`? Light mode danger button text contrast may force the question.

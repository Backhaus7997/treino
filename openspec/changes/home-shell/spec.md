# Spec — home-shell

**Change**: `home-shell`
**Fase / Etapa**: Fase 2 · Etapa 1
**Artifact store**: `openspec`
**TDD**: Strict — tests are written BEFORE each widget in the apply phase.

---

## Overview

This spec defines verifiable requirements for the Home shell: `HomeScreen` (orchestrator) + four widgets (`HomeHeader`, `EmpezarEntrenamientoCard`, `EstaSemanaCard`, `HomeCTAButton`). All requirements are scoped to Etapa 1 placeholder content. No domain logic, no routing wire, no real workout data.

Test helper convention (mirrors `test/features/auth/` and `test/features/profile/`):

```dart
Widget _wrap(Widget w) => MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w));

Widget _wrapProvider(Widget w, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w)),
);
```

---

## Requirements

---

### REQ-HOME-SCREEN-001 — HomeScreen is a ConsumerWidget that watches userProfileProvider exactly once

`HomeScreen` MUST be a `ConsumerWidget`. Its `build` method MUST call `ref.watch(userProfileProvider)` exactly once and use `.when(data:, loading:, error:)` to resolve the async state. No child widget may call `ref.watch` or `ref.read` on `userProfileProvider` directly — all data flows by parameter.

#### Scenarios

- GIVEN a `ProviderScope` that overrides `userProfileProvider` with `AsyncData(profile)` WHEN `HomeScreen` is pumped THEN a single `HomeHeader`, a single `EmpezarEntrenamientoCard`, and a single `EstaSemanaCard` are each found exactly once in the widget tree.
- GIVEN a `ProviderScope` that overrides `userProfileProvider` with `AsyncLoading()` WHEN `HomeScreen` is pumped THEN a skeleton/shimmer widget is found and none of the three sub-widgets are rendered (no layout jump).
- GIVEN a `ProviderScope` that overrides `userProfileProvider` with `AsyncError(Exception(), StackTrace.empty)` WHEN `HomeScreen` is pumped THEN no exception propagates, `HomeHeader`, `EmpezarEntrenamientoCard`, and `EstaSemanaCard` are each found exactly once, and no error text is visible to the user.

---

### REQ-HOME-SCREEN-002 — HomeScreen does not introduce Scaffold, AppBackground, or SafeArea

`HomeScreen.build` MUST NOT contain a `Scaffold`, `AppBackground`, or `SafeArea` widget anywhere in its subtree. The shell route (`_ShellScaffold` in `router.dart`) already wraps every tab child with those layers. Adding them again would produce a double-AppBackground / double-SafeArea visual bug.

#### Scenarios

- GIVEN `HomeScreen` is pumped inside a plain `MaterialApp(home: Scaffold(body: HomeScreen()))` wrapper (not the real shell) WHEN the widget tree is inspected THEN `find.byType(Scaffold)` finds exactly one — the outer test wrapper's — and `find.byType(AppBackground)` finds zero and `find.byType(SafeArea)` finds zero inside `HomeScreen`'s own subtree.

---

### REQ-HOME-SCREEN-003 — HomeScreen composes exactly three sub-widgets by parameter

`HomeScreen` MUST pass the resolved `UserProfile?` to `HomeHeader` as a constructor parameter. `EmpezarEntrenamientoCard` and `EstaSemanaCard` MUST be instantiated with no dynamic parameters (they are fully self-contained).

#### Scenarios

- GIVEN `userProfileProvider` overridden with `AsyncData(profile)` WHEN `HomeScreen` is pumped THEN `tester.widget<HomeHeader>(find.byType(HomeHeader)).profile` equals the overridden `profile` object.
- GIVEN `userProfileProvider` overridden with `AsyncData(null)` WHEN `HomeScreen` is pumped THEN `tester.widget<HomeHeader>(find.byType(HomeHeader)).profile` is null.

---

### REQ-HOME-HEADER-001 — HomeHeader renders "HOLA, {displayName}!" when profile has displayName

When `HomeHeader` receives a non-null `UserProfile` with a non-null `displayName`, it MUST render the text `"HOLA, {displayName}!"` in `Barlow Condensed`, weight 700, UPPERCASE.

#### Scenarios

- GIVEN `HomeHeader(profile: UserProfile(displayName: 'Martín', ...))` is pumped WHEN the widget tree is inspected THEN `find.text('HOLA, MARTÍN!')` finds exactly one widget.
- GIVEN `HomeHeader(profile: UserProfile(displayName: 'ana', ...))` is pumped WHEN inspected THEN the greeting text is uppercase: `find.text('HOLA, ANA!')` finds one widget (the widget applies `.toUpperCase()` or uses a text style with `TextCapitalization.characters` / all-caps style).

---

### REQ-HOME-HEADER-002 — HomeHeader renders "HOLA!" fallback when profile is null or displayName is null

When `HomeHeader` receives `null` for the entire profile, OR a `UserProfile` where `displayName == null`, it MUST render `"HOLA!"` as the greeting (no comma, no name).

#### Scenarios

- GIVEN `HomeHeader(profile: null)` is pumped WHEN inspected THEN `find.text('HOLA!')` finds one widget and no widget with text matching `RegExp(r'HOLA, ')` is found.
- GIVEN `HomeHeader(profile: UserProfile(displayName: null, ...))` is pumped WHEN inspected THEN `find.text('HOLA!')` finds one widget.

---

### REQ-HOME-HEADER-003 — HomeHeader renders CachedNetworkImage avatar when avatarUrl is non-null

When `HomeHeader` receives a `UserProfile` with a non-null `avatarUrl`, it MUST render a `CachedNetworkImage` widget (from `package:cached_network_image`) inside a circular clip. It MUST NOT use `Image.network` directly.

#### Scenarios

- GIVEN `HomeHeader(profile: UserProfile(avatarUrl: 'https://example.com/avatar.jpg', displayName: 'Ana', ...))` is pumped WHEN inspected THEN `find.byType(CachedNetworkImage)` finds at least one widget.
- GIVEN `HomeHeader(profile: UserProfile(avatarUrl: 'https://example.com/avatar.jpg', ...))` is pumped WHEN inspected THEN `find.byType(Image)` used standalone (not as child of CachedNetworkImage) finds zero direct `Image.network` widgets at the top of the avatar subtree.

---

### REQ-HOME-HEADER-004 — HomeHeader renders initials fallback avatar when avatarUrl is null

When `avatarUrl` is null (profile present) or profile itself is null, the avatar area MUST show a circular widget containing the initials. Initials are: first letter of `displayName` uppercased when `displayName` is non-null and non-empty, otherwise `"?"`. The circle MUST use a gradient fill from `palette.accent` to `palette.highlight`.

#### Scenarios

- GIVEN `HomeHeader(profile: UserProfile(avatarUrl: null, displayName: 'Martín', ...))` is pumped WHEN inspected THEN `find.text('M')` finds one widget and `find.byType(CachedNetworkImage)` finds zero.
- GIVEN `HomeHeader(profile: null)` is pumped WHEN inspected THEN `find.text('?')` finds one widget and `find.byType(CachedNetworkImage)` finds zero.
- GIVEN `HomeHeader(profile: UserProfile(avatarUrl: null, displayName: null, ...))` is pumped WHEN inspected THEN `find.text('?')` finds one widget.

---

### REQ-HOME-EMPEZAR-001 — EmpezarEntrenamientoCard is a StatelessWidget with all content hardcoded

`EmpezarEntrenamientoCard` MUST extend `StatelessWidget`. It MUST NOT accept any constructor parameters carrying dynamic data. It MUST NOT call `ref.watch` or `ref.read`. The following six content items MUST be present in the widget tree as-built.

#### Scenarios

- GIVEN `EmpezarEntrenamientoCard()` is pumped inside `_wrap(...)` WHEN inspected THEN `find.text('HOY · JUEVES')` finds one widget.
- GIVEN same pump WHEN inspected THEN `find.text('PUSH')` finds one widget.
- GIVEN same pump WHEN inspected THEN `find.text('Pecho · Hombros · Tríceps')` finds one widget.
- GIVEN same pump WHEN inspected THEN `find.text('6 ejercicios')` finds one widget AND `find.text('~55 min')` finds one widget.
- GIVEN same pump WHEN inspected THEN `find.text('EMPEZAR ENTRENAMIENTO')` finds one widget AND `find.byType(HomeCTAButton)` finds one widget whose `label == 'EMPEZAR ENTRENAMIENTO'` AND `leadingIcon == TreinoIcon.play` (the play glyph is rendered as a separate `Icon` widget, NOT as a Unicode `▶` inside the label string — that renders as a colored emoji on Windows).

---

### REQ-HOME-EMPEZAR-002 — EmpezarEntrenamientoCard uses correct icons in the stat row

The stat row MUST use `TreinoIcon.tabWorkout` for the exercise count icon and `TreinoIcon.clock` for the duration icon. No `PhosphorIcons.*` references appear directly in the widget source.

#### Scenarios

- GIVEN `EmpezarEntrenamientoCard()` is pumped WHEN inspected THEN `find.byIcon(TreinoIcon.tabWorkout)` finds at least one widget and `find.byIcon(TreinoIcon.clock)` finds at least one widget.

---

### REQ-HOME-EMPEZAR-003 — EmpezarEntrenamientoCard card style

The card MUST be rendered with: background color `palette.bgCard`, border radius 20 (r-lg), and a 1px border using `palette.border`. No HEX literal color constants appear in the widget source file.

#### Scenarios

- GIVEN `EmpezarEntrenamientoCard()` is pumped WHEN `find.byType(Container)` or `find.byType(DecoratedBox)` is inspected for the outermost card container THEN `decoration.borderRadius` equals `BorderRadius.circular(20)` and `decoration.color` equals `AppPalette.mintMagenta.bgCard` and `decoration.border` is non-null.

---

### REQ-HOME-EMPEZAR-004 — EmpezarEntrenamientoCard CTA onPressed is null or no-op

The `HomeCTAButton` inside `EmpezarEntrenamientoCard` MUST have `onPressed == null` or be wired to a no-op callback. Tapping it MUST NOT throw an exception or navigate anywhere.

#### Scenarios

- GIVEN `EmpezarEntrenamientoCard()` is pumped WHEN `tester.tap(find.byType(HomeCTAButton))` is called and `pumpAndSettle()` is awaited THEN no exception is thrown and the widget tree is unchanged (no navigation occurred).
- GIVEN the `HomeCTAButton` within the card is inspected WHEN `widget.onPressed` is read THEN it is either null or a void callback that does nothing (implementation detail: acceptable to be either as long as no crash and no navigation on tap).

---

### REQ-HOME-SEMANA-001 — EstaSemanaCard is a StatelessWidget with placeholder content

`EstaSemanaCard` MUST extend `StatelessWidget`. It MUST NOT accept dynamic constructor parameters, MUST NOT call `ref.watch`/`ref.read`, and MUST render exactly the title `"ESTA SEMANA"` and a placeholder message containing `"Todavía no entrenaste esta semana."` in `textMuted` color. It MUST NOT render any streak number, muscle map SVG, week dots, or SEMANA/MES stat tiles (those are Etapa 5).

#### Scenarios

- GIVEN `EstaSemanaCard()` is pumped inside `_wrap(...)` WHEN inspected THEN `find.text('ESTA SEMANA')` finds one widget.
- GIVEN same pump WHEN inspected THEN `find.text('Todavía no entrenaste esta semana.')` finds one widget.
- GIVEN same pump WHEN inspected THEN no widget with text matching `RegExp(r'\d+ DÍAS')` is found (no streak number).
- GIVEN same pump WHEN inspected THEN `find.byType(SvgPicture)` finds zero widgets (no muscle map SVG).

---

### REQ-HOME-SEMANA-002 — EstaSemanaCard card style matches EmpezarEntrenamientoCard

`EstaSemanaCard` MUST use the same card shell: background `palette.bgCard`, border radius 20 (r-lg), 1px border with `palette.border`.

#### Scenarios

- GIVEN `EstaSemanaCard()` is pumped WHEN the outermost card container's decoration is inspected THEN `decoration.borderRadius` equals `BorderRadius.circular(20)` and `decoration.color` equals `AppPalette.mintMagenta.bgCard` and `decoration.border` is non-null.

---

### REQ-HOME-CTA-001 — HomeCTAButton renders label text

`HomeCTAButton` MUST render the value of its `label` parameter as visible text.

#### Scenarios

- GIVEN `HomeCTAButton(label: 'EMPEZAR ENTRENAMIENTO', onPressed: null)` is pumped inside `_wrap(...)` WHEN inspected THEN `find.text('EMPEZAR ENTRENAMIENTO')` finds one widget.
- GIVEN `HomeCTAButton(label: 'OTRO LABEL', onPressed: () {})` is pumped WHEN inspected THEN `find.text('OTRO LABEL')` finds one widget.

---

### REQ-HOME-CTA-002 — HomeCTAButton fires onPressed when tapped and it is non-null

When `onPressed` is a non-null callback, tapping `HomeCTAButton` MUST invoke the callback exactly once.

#### Scenarios

- GIVEN `HomeCTAButton(label: 'GO', onPressed: () => counter++)` is pumped WHEN `tester.tap(find.byType(HomeCTAButton))` and `pump()` are called THEN `counter` equals 1.

---

### REQ-HOME-CTA-003 — HomeCTAButton does not crash when onPressed is null

When `onPressed` is null, `HomeCTAButton` MUST still render without throwing. Tapping MUST NOT cause an exception.

#### Scenarios

- GIVEN `HomeCTAButton(label: 'GO', onPressed: null)` is pumped WHEN `tester.tap(find.byType(HomeCTAButton))` is called THEN no exception is thrown.
- GIVEN same pump WHEN the internal `ElevatedButton` (or equivalent) is inspected THEN `button.onPressed` is null (the widget explicitly passes null, enabling the Material disabled state).

---

### REQ-HOME-CTA-004 — HomeCTAButton style: accent fill, bg text, r-full radius, Barlow Condensed 700

`HomeCTAButton` MUST render full-width with background color `palette.accent`, text color `palette.bg`, border radius 9999 (r-full), and `Barlow Condensed` weight 700 UPPERCASE. No HEX literals in source.

#### Scenarios

- GIVEN `HomeCTAButton(label: 'GO', onPressed: null)` is pumped WHEN the `ElevatedButton`/`TextButton` style is inspected THEN `shape` has `BorderRadius.circular(9999)` (or equivalent `StadiumBorder`) and background resolves to `AppPalette.mintMagenta.accent` in the default state.
- GIVEN same pump WHEN the `Text` widget inside is inspected THEN its style uses `GoogleFonts.barlowCondensed` family and `FontWeight.w700`.

---

### REQ-HOME-CTA-005 — HomeCTAButton accepts optional leadingIcon

`HomeCTAButton` MUST accept an optional `leadingIcon` parameter of type `IconData?`. When provided, the icon MUST be rendered to the left of the label text. When null, no icon widget is present.

#### Scenarios

- GIVEN `HomeCTAButton(label: 'PLAY', onPressed: null, leadingIcon: TreinoIcon.play)` is pumped WHEN inspected THEN `find.byIcon(TreinoIcon.play)` finds one widget.
- GIVEN `HomeCTAButton(label: 'PLAY', onPressed: null)` (no leadingIcon) is pumped WHEN inspected THEN `find.byType(Icon)` finds zero widgets inside the button.

---

### REQ-HOME-PROVIDER-001 — HomeScreen handles AsyncData(UserProfile) without crash

When `userProfileProvider` emits a full `UserProfile` with `displayName` and `avatarUrl`, `HomeScreen` MUST render the header with real data and both cards without any exception.

#### Scenarios

- GIVEN `userProfileProvider` overridden with `AsyncData(UserProfile(displayName: 'Martín', avatarUrl: 'https://...', ...))` WHEN `HomeScreen` is pumped THEN `find.text('HOLA, MARTÍN!')` finds one widget and `find.byType(CachedNetworkImage)` finds at least one widget and no `FlutterError` is reported.

---

### REQ-HOME-PROVIDER-002 — HomeScreen handles AsyncData(null) without crash

When `userProfileProvider` emits `AsyncData(null)`, `HomeScreen` MUST render the fallback greeting and avatar placeholder without crash.

#### Scenarios

- GIVEN `userProfileProvider` overridden with `AsyncData<UserProfile?>(null)` WHEN `HomeScreen` is pumped THEN `find.text('HOLA!')` finds one widget and `find.byType(CachedNetworkImage)` finds zero widgets and no `FlutterError` is reported.

---

### REQ-HOME-PROVIDER-003 — HomeScreen handles AsyncLoading without layout jump

When `userProfileProvider` is in `AsyncLoading` state, `HomeScreen` MUST render a skeleton/shimmer placeholder that occupies approximately the same vertical space as the header to avoid content reflow. The three sub-widgets (`HomeHeader`, `EmpezarEntrenamientoCard`, `EstaSemanaCard`) MUST NOT be rendered while loading.

#### Scenarios

- GIVEN `userProfileProvider` overridden with `AsyncLoading<UserProfile?>()` WHEN `HomeScreen` is pumped (single `pump()`, not `pumpAndSettle`) THEN `find.byType(HomeHeader)` finds zero and a shimmer or placeholder widget (e.g. `find.byType(SizedBox)` with non-zero height, or a dedicated shimmer type) is found where the header should be.
- GIVEN same loading state WHEN inspected THEN `find.byType(EmpezarEntrenamientoCard)` finds one widget and `find.byType(EstaSemanaCard)` finds one widget (cards are visible even during profile load — they are hardcoded).

---

### REQ-HOME-PROVIDER-004 — HomeScreen handles AsyncError without exposing error to user

When `userProfileProvider` emits an `AsyncError`, `HomeScreen` MUST fall back silently to the same state as `data(null)`: generic "HOLA!" greeting and placeholder avatar. No error snackbar, banner, or text is shown.

#### Scenarios

- GIVEN `userProfileProvider` overridden with `AsyncError<UserProfile?>(Exception('network'), StackTrace.empty)` WHEN `HomeScreen` is pumped THEN no `FlutterError` is reported, `find.text('HOLA!')` finds one widget, and no widget with text matching `RegExp(r'[Ee]rror|[Ee]xcepci')` is found.

---

## Constraint summary (enforced via the above REQs)

| Constraint | Enforced by |
|---|---|
| No `Scaffold`/`AppBackground`/`SafeArea` in `HomeScreen` | REQ-HOME-SCREEN-002 |
| No HEX literals in any new file | REQ-HOME-EMPEZAR-003, REQ-HOME-SEMANA-002, REQ-HOME-CTA-004 (source-level grep in CI) |
| No `PhosphorIcons.*` direct usage | REQ-HOME-EMPEZAR-002 (icon assertions use `TreinoIcon` constants) |
| No `Theme.of(context).textTheme.*` with custom sizes | REQ-HOME-CTA-004 (typography assertion checks `GoogleFonts.barlowCondensed`) |
| Spacing only in `{8, 12, 14, 18, 20}` | Design review gate — grep for literal `16` and `24` in new files before merge |
| Radii: cards r-lg=20, CTA r-full=9999 | REQ-HOME-EMPEZAR-003, REQ-HOME-SEMANA-002, REQ-HOME-CTA-004 |
| `cached_network_image` used for avatar, not `Image.network` | REQ-HOME-HEADER-003 |
| No new providers; no domain logic | REQ-HOME-EMPEZAR-001, REQ-HOME-SEMANA-001 (no `ref.watch` in cards) |
| Test files under `test/features/home/widgets/` created BEFORE widget code | Enforced by tasks phase (Strict TDD order) |

---

## Files this spec covers

| File | REQs |
|---|---|
| `lib/features/home/home_screen.dart` | SCREEN-001, SCREEN-002, SCREEN-003, PROVIDER-001..004 |
| `lib/features/home/widgets/home_header.dart` | HEADER-001..004 |
| `lib/features/home/widgets/empezar_entrenamiento_card.dart` | EMPEZAR-001..004 |
| `lib/features/home/widgets/esta_semana_card.dart` | SEMANA-001..002 |
| `lib/features/home/widgets/home_cta_button.dart` | CTA-001..005 |
| `pubspec.yaml` | implicit in HEADER-003 (`cached_network_image` must be in pubspec) |
| `test/features/home/home_screen_test.dart` | SCREEN-001..003, PROVIDER-001..004 |
| `test/features/home/widgets/home_header_test.dart` | HEADER-001..004 |
| `test/features/home/widgets/empezar_entrenamiento_card_test.dart` | EMPEZAR-001..004 |
| `test/features/home/widgets/esta_semana_card_test.dart` | SEMANA-001..002 |
| `test/features/home/widgets/home_cta_button_test.dart` | CTA-001..005 |

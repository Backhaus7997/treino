# Handoff: Onboarding (5 slides) — TREINO

## Overview
Onboarding walkthrough for the TREINO app (Flutter), 5 slides: Resumen del día (Home), Entrenar, Feed, Coach, Perfil. Each slide pairs a real-screen mockup (scaled preview of the app's actual screen) with a headline, short copy, and a "SIGUIENTE"/"EMPEZAR" CTA. Two theme variants are included — light and dark — matching the app's two shipped themes (`AppPalette.mintMagentaLight` / `AppPalette.mintMagenta`).

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes showing intended look, layout, and copy, not production code to copy directly. The task is to **recreate these onboarding screens in the Flutter codebase** (`lib/features/onboarding/` or similar, following the existing `features/<name>/presentation` structure used elsewhere in the repo — see `lib/features/profile_setup/presentation/profile_setup_flow.dart` for a comparable existing flow) using Flutter widgets, `AppPalette`, `AppTheme`, `TreinoIcon`, and the existing motion/widget primitives (`TreinoFadeSlideIn`, `TreinoTappable`, etc.) — not by embedding HTML/WebView.

## Fidelity
**High-fidelity (hifi).** Colors, typography, spacing, and the screen previews were built directly from the current repo source (`AppPalette`, `AppTheme`, `TreinoIcon`, `TreinoBottomBar`, `HomeHeader`, `EmpezarEntrenamientoCard`, `EstaSemanaCard`, `RutinasSection`, `HistorialSection`, `PostCard`, `FeedSegmentPills`, `AthleteCoachView`, `ProfileHeader`, `ProfileAvatarCard`, `ProfileSectionTile`, `ProfileCuentaSection`). Recreate pixel-perfectly using the codebase's existing widgets and tokens — do not introduce new hex colors.

## Screens / Views

Each slide shares the same shell:
- Status bar (time, signal, wifi, battery) + dynamic-island pill
- 5-segment progress bar (filled segments = current step) + "SALTAR" (hidden on the last slide)
- A scaled preview of the real app screen inside a floating white-bezel mini-device (this bezel stays **white** in both themes — it represents the physical device chassis, not app UI)
- Headline (accent-color vertical bar + Phosphor icon + Barlow Condensed 700 30px title)
- Body copy (Barlow 17px, muted color, `text-wrap: pretty`)
- Full-width pill CTA (accent bg, 56px height, Barlow Condensed 700 16px, 2px letter-spacing)
- **No iOS home-indicator bar** — deliberately removed; the real device draws its own system gesture bar, so don't render one.

### Bottom nav (updated)
The mini-device previews use the CURRENT `TreinoBottomBar` treatment — match this, it replaced an older rounded-rectangle style:
- Floating pill: inset 10px from the device edges, height 46px, radius 23px, translucent surface + blur (light: white ~92%; dark: `#181E1C` ~92%), soft drop shadow.
- 5 equal-width items: ENTRENAR, FEED, INICIO, COACH, PERFIL (Barlow Condensed 700, ~1.2× small caps label under the icon).
- **Active item** = a solid accent **circle** (40px, full radius) containing a *fill*-weight icon + its label, with an accent glow (`0 0 18px rgba(44,229,162,.60)`). Foreground uses `palette.bg`.
- **Inactive items** = *regular*-weight icon + label in `palette.textMuted`, no background.

### 1 — Resumen del día (Home)
**Purpose:** show the athlete what today's home screen looks like — today's routine card + streak/insights card.
**Preview contents:** `HomeHeader` greeting + avatar, `EmpezarEntrenamientoCard` (today's routine, exercise/duration stats, EMPEZAR ENTRENAMIENTO CTA), `EstaSemanaCard` (RACHA ACTUAL pill with pulsing dot, streak number, day strip, body-heatmap placeholder, SEMANA/MES period cards), `TreinoBottomBar`.
**Headline:** "TU RESUMEN DEL DÍA" / house icon.
**Copy:** "Acá ves qué te toca entrenar hoy, cómo venís esta semana y tu racha. Si dejaste una sesión a medias, te la ofrece para retomar."

### 2 — Entrenar
**Purpose:** show routines + history.
**Preview contents:** TU ENTRENO/PLANTILLAS segmented pill, MIS RUTINAS (active routine card with ACTIVA chip, coach-assigned routine card with DE TU COACH chip), HISTORIAL (three completed session rows with kg/min: Push A, Pull A, Legs A), a VOLUMEN SEMANAL card (label + "+8%" accent delta, 5-bar mini chart where the last two bars are accent-filled, caption "10.250 kg movidos en 3 sesiones"), `TreinoBottomBar`.
**Headline:** "ENTRENÁ CON RUTINAS" / barbell icon.
**Copy:** "Creá tus propias rutinas o entrená con el plan que te armó tu coach. Tu historial queda guardado, sesión por sesión."

### 3 — Feed
**Purpose:** show the social feed.
**Preview contents:** FEED/RANKINGS toggle + create-post button, AMIGOS/MI GYM/PÚBLICO segment pills, then three `PostCard` samples, `TreinoBottomBar`:
1. Text-only post (Lucas Ferrari) — avatar, name, gym·time, text, workout stats (kg/min/exercises), reactions row (heart/flame/clap with counts).
2. Text-only post (Sofía Núñez) — same anatomy, two reactions.
3. **Photo post (Martín Aguirre)** — same header, then a full-width **photo** (height ~190px, 14px radius, `object-fit: cover`), caption text, reactions row including a comment count, and below a hairline divider **one inline comment** (28px avatar + commenter name + comment text). This is the `PostCard` variant with an image attachment and a comment preview; the photo asset for the mock is `assets/feed-post-photo.png`.
**Headline:** "COMPARTÍ TU PROGRESO" / newspaper icon.
**Copy:** "Mirá lo que entrenan tus amigos y tu gym, reaccioná a sus sesiones y compará tu volumen en los rankings."

### 4 — Coach
**Purpose:** show the athlete↔trainer link.
**Preview contents:** active-link card ("TU PERSONAL TRAINER" label, trainer avatar/name/date, italic disclaimer, MENSAJE button, TERMINAR VÍNCULO outline button), a PLAN ASIGNADO card (SEMANA 3 highlight-colored chip, "FUERZA · BLOQUE 2" condensed title, 8px accent progress bar at 62%, caption "3 de 5 sesiones completadas esta semana"), an ÚLTIMO MENSAJE card (quoted trainer message + "Valentina · hace 1 día"), `TreinoBottomBar`.
**Headline:** "TU COACH, SIEMPRE CERCA" / chalkboard-teacher icon.
**Copy:** "Vinculate con un Personal Trainer, seguí el plan que te armó y escribile directo cuando lo necesites."

### 5 — Perfil
**Purpose:** show the profile screen (final slide — CTA reads "EMPEZAR", no SALTAR).
**Preview contents:** TU CUENTA/PERFIL header, avatar card (name, @handle, gym chip), stats row (SESIONES/VOLUMEN KG/RACHA — last one in highlight color), CUENTA tiles list with hairline dividers: Datos personales (pencil, accent-tinted circle), Gimnasio (buildings, accent-tinted), Notificaciones (bell, accent-tinted), Apariencia (moon-stars, **highlight**-tinted), each with a trailing caret, `TreinoBottomBar`.
**Headline:** "TU PERFIL, TU HISTORIA" / user icon.
**Copy:** "Tus estadísticas, tu gym y tus datos, todo en un solo lugar. Editalos cuando quieras."

## Interactions & Behavior
- SALTAR (top right) → skip onboarding, same as tapping through to the end.
- SIGUIENTE → advance to next slide; last slide's button reads EMPEZAR and dismisses onboarding.
- Progress bar segments fill left-to-right per slide index (5 segments total).
- Racha dot (green dot inside "RACHA ACTUAL" pill, slide 1) pulses continuously — a soft `box-shadow` pulse, ~1.8s loop, easing in/out. Implement as a subtle looping animation (e.g. `AnimatedContainer`/`TweenAnimationBuilder` on the dot's glow), not attention-grabbing.
- No other animation/transition requirements were specified — slide transitions can use the app's existing page-transition convention.

## State Management
Purely presentational — no async data in the onboarding flow itself (it shows *representative* sample data, not live provider data). Needed state: current slide index (0–4), typically owned by a `PageController`/`TabController` equivalent to what `profile_setup_flow.dart` already uses for its stepper.

## Design Tokens
Sourced from `lib/app/theme/app_palette.dart` — **do not hardcode hex values in the new code, reference `AppPalette.of(context)`**. For reference, the two variants used in these mocks:

**Light (`AppPalette.mintMagentaLight`)**
- accent: `#2CE5A2`, highlight: `#C123E0`
- bg: `#FAFAFA`, bgCard: `#FFFFFF`
- border: `rgba(0,0,0,.10)` (approx. `0x1A000000`)
- textPrimary: `#0F1513`, textMuted: `rgba(0,0,0,.55–.60)` (approx. `0x99000000`)

**Dark (`AppPalette.mintMagenta`)**
- accent: `#2CE5A2`, highlight: `#C123E0`
- bg: `#0A0A0A` (ink), bgCard: `#0F1513`
- border: `rgba(255,255,255,.10)` (`0x1AFFFFFF`)
- textPrimary: `#FFFFFF` (bone), textMuted: `rgba(255,255,255,.55–.60)` (`0x8CFFFFFF`)
- **Important theme-flip detail preserved in the dark mock:** any foreground drawn on an accent-colored surface (CTA button label, active tab-bar icon/label, avatar-initials text, "+" button icon) uses `palette.bg` as its color per `AppTheme`'s `onPrimary: palette.bg` — so in dark mode that text/icon is **dark ink (`#0A0A0A`)**, not white, even though it sits on the green accent. Don't default it to white.

**Typography:** Barlow (body, 400/500/600/700) + Barlow Condensed (headings/labels, 600/700), both Google Fonts, per `app_theme.dart`.
**Radii:** cards 20px, pills/buttons 999px (stadium), chips 999px, small tiles 12–18px.
**Icons:** Phosphor (`phosphor_flutter` / `TreinoIcon`), regular weight default, fill weight for active/selected states.

## Assets
- `assets/feed-post-photo.png` — the photo used in slide 3's photo post. It stands in for a **user-uploaded workout photo**; in the app this comes from the post's image URL, so wire it to the post model's image field rather than bundling it.
- All icons are Phosphor glyphs (`TreinoIcon`); regular weight for inactive, **fill** weight for active/selected. The "body heatmap" front/back boxes on slide 1 are placeholders for `BodySilhouettePlaceholder`'s real body-part PNG assets (`assets/body/bodyfront.png` / `bodyback.png` + muscle masks) — do not recreate a hand-drawn body; wire up the existing `BodySilhouettePlaceholder` widget instead.

## Files
- `onboarding-claro.dc.html` — light theme, all 5 slides.
- `onboarding-oscuro.dc.html` — dark theme, all 5 slides.

Open either file directly in a browser to view all 5 slides side by side (they're laid out as a horizontal strip, not a swipeable deck).

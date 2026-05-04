# Design System — TREINO

Tokens de diseño, tipografía, spacing y reglas de código de UI. Si vas a tocar widgets, tema o pantallas, leé esto antes.

## Workflow de diseño

1. Para saber qué screen implementar y de qué proyecto sale, consultar `docs/design-decisions.md`.
2. Para saber qué colores, tipografías, spacing y componentes usar, consultar este documento.
3. Los HTML en `docs/*/screens/full-projects/` son referencia visual de layout y composición — **NO copiar tokens de ahí**.

> En caso de discrepancia entre los HTML de referencia y este documento, **este documento manda**. Los HTML son referencia visual, no fuente de tokens.

## Paletas

La app soporta **dos paletas intercambiables**. La default es Mint Magenta. La alterna se selecciona en Perfil → Apariencia.

### Mint Magenta (default)

| Token | HEX | Uso |
|---|---|---|
| `accent` | `#2CE5A2` | CTA principal, streaks, tab activo, highlights |
| `highlight` | `#C123E0` | Achievements, avatar gradient, badge PF |
| `sage` | `#4F6358` | Cards secundarias, outlines sutiles |
| `ink` | `#0A0A0A` | Fondo global |
| `espresso` | `#3C3534` | Superficies elevadas, sheets |
| `bone` | `#FFFFFF` | Texto primario sobre ink |
| `bgCard` | `#0F1513` | Fondo de cards |
| `border` | `rgba(255,255,255,0.10)` | Borders 1px de cards |
| `textPrimary` | `#FFFFFF` | Texto principal |
| `textMuted` | `rgba(255,255,255,0.55)` | Texto secundario, captions |

### Electric Violet (alterna)

| Token | HEX |
|---|---|
| `accent` | `#34E062` |
| `highlight` | `#7C3AED` |
| (resto idéntico a Mint Magenta) | |

## Tipografía

- **Heading**: `Barlow Condensed` 700, **UPPERCASE**, letter-spacing 0.5–1.0 px. Para títulos de sección, hero numbers, CTAs.
- **Body**: `Barlow` 400 / 600 / 700, Title Case. Para microcopy, listas, párrafos.
- **Numérico hero** (streak, peso, XP): `Barlow Condensed` 700, tamaños 56–72 px.
- Source: Google Fonts via `google_fonts` package.

## Spacing scale

Sólo estos valores: `8 · 12 · 14 · 18 · 20` px. **No** usar 4 / 16 / 24.

## Radii

| Token | Valor | Uso |
|---|---|---|
| `r-sm` | `12` | Chips, inputs pequeños |
| `r-md` | `16` | Cards default |
| `r-lg` | `20` | Hero cards |
| `r-full` | `9999` (full pill) | CTAs principales |

## Tema

- **Modo oscuro siempre** (`Brightness.dark`). No hay light theme.
- Cards: fondo `bgCard`, border 1px `border`, **sin shadow** (el contraste lo da el ink).
- Hero con glow: streak card y CTA usan halo radial sutil de `accent @ 18% → 0%`.

## Reglas de código de UI (no negociables)

### 1. Nunca HEX literal en widgets
Usar tokens vía `AppPalette.of(context)`:

```dart
// ❌ MAL
Container(color: Color(0xFF2CE5A2));

// ✅ BIEN
final palette = AppPalette.of(context);
Container(color: palette.accent);
```

Tokens disponibles: `accent`, `highlight`, `bg`, `bgCard`, `border`, `textPrimary`, `textMuted`.

### 2. Nunca PhosphorIcons directo
Usar `TreinoIcon.X` como wrapper semántico:

```dart
// ❌ MAL
Icon(PhosphorIconsRegular.houseSimple);

// ✅ BIEN
Icon(TreinoIcon.tabHome);
```

Si falta un ícono, agregarlo a `lib/core/widgets/treino_icon.dart` con un nombre semántico (no el nombre Phosphor crudo).

### 3. Nunca hard-code de strings de UI
Tab labels, feature names, mensajes — centralizar en constantes o (cuando llegue Fase 6) en archivos de localización (`lib/l10n/`).

## Componentes base disponibles

Viven en `lib/core/widgets/`:

- `AppBackground` — Container con fondo `ink`.
- `TreinoIcon` — wrapper semántico sobre Phosphor (regular + fill).
- `TreinoBottomBar` — tab bar de 5 ítems.

A medida que crezca la app vamos a sumar:

- `TreinoButton` (primary / secondary / ghost / pill)
- `TreinoCard` (default / hero / elevated)
- `TreinoChip` (muscle / exercise / tag / distance)
- `TreinoInput` (text / password / email / numeric)
- `Avatar`, `Badge`, `StatTile`, `StreakHero`

Cuando necesites uno y no exista, lo creás como parte del PR — pero asegurate de poner los estados (normal / hover / pressed / disabled / focus) y reusarlo en al menos 2 lugares antes de mergear.

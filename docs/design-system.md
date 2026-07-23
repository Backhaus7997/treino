# Design System — TREINO

Tokens de diseño, tipografía, spacing y reglas de código de UI. Si vas a tocar widgets, tema o pantallas, leé esto antes.

## Workflow de diseño

1. Para saber qué screen implementar y de qué proyecto sale, consultar `docs/design-decisions.md`.
2. Para saber qué colores, tipografías, spacing y componentes usar, consultar este documento.
3. Los HTML en `docs/*/screens/full-projects/` son referencia visual de layout y composición — **NO copiar tokens de ahí**.

> En caso de discrepancia entre los HTML de referencia y este documento, **este documento manda**. Los HTML son referencia visual, no fuente de tokens.

---

## Arquitectura de tokens (3 capas)

El sistema de diseño TREINO organiza todos los valores de UI en tres capas jerárquicas. Nunca uses un valor de una capa inferior directamente en la capa de presentación: respetá la jerarquía.

```
Capa 1 — Primitivos          (lib/app/theme/tokens/primitives.dart)
    ↓  insumo exclusivo de
Capa 2 — Semánticos           (lib/app/theme/app_palette.dart)
    ↓  insumo exclusivo de
Capa 3 — Componentes          (lib/app/theme/tokens/components/)
    ↓  consumidos por
Widgets de presentación       (lib/features/**/presentation/)
```

El barrel `lib/app/theme/tokens/tokens.dart` exporta todo lo que necesita la presentación. Importá el barrel, no archivos individuales.

---

## Capa 1 — Tokens primitivos

Fuente de verdad de valores absolutos. **Ningún widget debe referenciarlos directamente** — son insumo exclusivo de `AppPalette` (capa 2).

### AppColorPrimitives

```dart
import 'package:treino/app/theme/tokens/tokens.dart';

// ❌ MAL — los primitivos son para la capa semántica, no para widgets
Container(color: AppColorPrimitives.mint500);

// ✅ BIEN — usá la capa semántica
final p = AppPalette.of(context);
Container(color: p.accent);
```

| Primitivo | HEX / Alpha | Descripción |
|---|---|---|
| `mint500` | `#2CE5A2` | Mint esmeralda — acento primario TREINO |
| `magenta500` | `#C123E0` | Magenta vibrante — destaque/highlight |
| `ink950` | `#0A0A0A` | Ink más profundo — fondo global dark |
| `ink900` | `#0F1513` | Ink con tinte mint — fondo de card dark |
| `ink800` | `#1A1A1A` | Ink medio — superficies elevadas dark |
| `bone` | `#FFFFFF` | Blanco puro — texto primario dark |
| `sage500` | `#4F6358` | Sage oscuro — superficies secundarias dark |
| `sageTint50` | `#DDE5DF` | Sage claro — superficies secundarias light |
| `espresso500` | `#3C3534` | Espresso oscuro — sheets/elevadas dark |
| `espressoTint50` | `#EDE5E2` | Espresso claro — sheets/elevadas light |
| `dangerRed` | `#E53935` | Rojo de error — estado dark |
| `dangerRedDark` | `#D32F2F` | Rojo de error — mayor contraste en light |
| `warningAmber` | `#FFB300` | Ámbar de advertencia — estado dark |
| `warningAmberDark` | `#FB8C00` | Ámbar de advertencia — estado light |
| `white` | `#FFFFFF` | Blanco absoluto — onDanger, fondo light-card |
| `black` | `#000000` | Negro absoluto — scrims |
| `white10` | `rgba(255,255,255,0.10)` | Borde de card en dark |
| `white20` | `rgba(255,255,255,0.20)` | Borde hover en dark |
| `white55` | `rgba(255,255,255,0.55)` | Texto mutado en dark |
| `black10` | `rgba(0,0,0,0.10)` | Borde de card en light |
| `black20` | `rgba(0,0,0,0.20)` | Borde hover en light |
| `black60` | `rgba(0,0,0,0.60)` | Texto mutado en light |
| `paper50` | `#FAFAFA` | Fondo de pantalla light |
| `inkText900` | `#0F1513` | Texto primario sobre fondos light |

### AppSpacing

Escala **cerrada**: `8 · 12 · 14 · 18 · 20` px. No existen `s4`, `s16` ni `s24`.

| Token | Valor | Uso típico |
|---|---|---|
| `AppSpacing.s8` | `8.0` | Gap interno de rows densas, chips |
| `AppSpacing.s12` | `12.0` | Padding interno de cards |
| `AppSpacing.s14` | `14.0` | Padding de secciones compactas |
| `AppSpacing.s18` | `18.0` | Padding horizontal de pantallas |
| `AppSpacing.s20` | `20.0` | Padding de hero cards, secciones amplias |

```dart
// ✅ BIEN
Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.s18));

// ❌ MAL — valores fuera de escala
Padding(padding: EdgeInsets.all(16));
```

### AppRadius

| Token | Valor | Uso típico |
|---|---|---|
| `AppRadius.sm` | `12.0` | Chips, inputs pequeños |
| `AppRadius.md` | `16.0` | Cards default |
| `AppRadius.lg` | `20.0` | Hero cards, bottom sheets |
| `AppRadius.full` | `9999.0` | CTAs pill, avatares |

### AppFonts

| Token | Valor | Uso |
|---|---|---|
| `AppFonts.barlow` | `'Barlow'` | Cuerpo de texto (pesos 400/600/700) |
| `AppFonts.barlowCondensed` | `'Barlow Condensed'` | Headings (700, UPPERCASE) |
| `AppFonts.w400` | `FontWeight.w400` | Regular |
| `AppFonts.w600` | `FontWeight.w600` | Semibold (labels, subtítulos) |
| `AppFonts.w700` | `FontWeight.w700` | Bold (headings, CTAs) |
| `AppFonts.headingTracking` | `0.5` | Letter-spacing de headings |

---

## Capa 2 — Tokens semánticos (AppPalette)

`AppPalette` es una `ThemeExtension<AppPalette>` que mapea intenciones de UI a primitivos de color. Es el único punto de acceso a color en widgets.

### Paleta Mint Magenta — dark (identidad de marca, default)

Dark es la identidad visual de TREINO y el tema que se aplica cuando el usuario selecciona "Sistema" en un dispositivo con tema oscuro activo, o cuando selecciona "Oscuro" explícitamente.

| Token | Valor (primitivo) | HEX efectivo | Uso |
|---|---|---|---|
| `accent` | `mint500` | `#2CE5A2` | CTA principal, tab activo, highlights, streaks |
| `highlight` | `magenta500` | `#C123E0` | Achievements, avatar gradient, badge PF |
| `bg` | `ink950` | `#0A0A0A` | Fondo global de pantalla |
| `bgCard` | `ink900` | `#0F1513` | Fondo de cards |
| `border` | `white10` | `rgba(255,255,255,0.10)` | Border 1px de cards |
| `borderHover` | `white20` | `rgba(255,255,255,0.20)` | Border en hover (web sidebar) |
| `textPrimary` | `bone` | `#FFFFFF` | Texto principal |
| `textMuted` | `white55` | `rgba(255,255,255,0.55)` | Texto secundario, captions |
| `sage` | `sage500` | `#4F6358` | Cards secundarias, outlines sutiles |
| `espresso` | `espresso500` | `#3C3534` | Sheets, superficies elevadas |
| `danger` | `dangerRed` | `#E53935` | Error inline, char-limit exceeded |
| `warning` | `warningAmber` | `#FFB300` | Advertencia no bloqueante |
| `onDanger` | `white` | `#FFFFFF` | Texto/icono sobre fondo danger |
| `scrimDark` | `black` | `#000000` | Overlay scrims (aplicar alpha en call site) |

### Paleta Mint Magenta — light

Light está soportado como alternativa al dark. Se activa cuando el usuario selecciona "Claro" en Perfil → Apariencia, o cuando el sistema está en modo claro y el usuario eligió "Sistema". Dark sigue siendo la identidad de marca y el default.

| Token | Valor (primitivo) | HEX efectivo | Uso |
|---|---|---|---|
| `accent` | `mint500` | `#2CE5A2` | CTA principal (mismo que dark) |
| `highlight` | `magenta500` | `#C123E0` | Highlights (mismo que dark) |
| `bg` | `paper50` | `#FAFAFA` | Fondo global en light |
| `bgCard` | `white` | `#FFFFFF` | Fondo de cards en light |
| `border` | `black10` | `rgba(0,0,0,0.10)` | Border 1px en light |
| `borderHover` | `black20` | `rgba(0,0,0,0.20)` | Border hover en light |
| `textPrimary` | `inkText900` | `#0F1513` | Texto principal en light |
| `textMuted` | `black60` | `rgba(0,0,0,0.60)` | Texto secundario en light |
| `sage` | `sageTint50` | `#DDE5DF` | Superficies secundarias light |
| `espresso` | `espressoTint50` | `#EDE5E2` | Sheets light |
| `danger` | `dangerRedDark` | `#D32F2F` | Error light (mayor contraste) |
| `warning` | `warningAmberDark` | `#FB8C00` | Advertencia light |
| `onDanger` | `white` | `#FFFFFF` | Texto sobre danger (igual que dark) |
| `scrimDark` | `black` | `#000000` | Scrims (igual que dark) |

> **Paleta única**: la paleta oficial de TREINO es Mint Magenta (dark + light). No existe Electric Violet — fue dropeada antes del lanzamiento.

### Cómo acceder a AppPalette

```dart
// ✅ BIEN — vía ThemeExtension
final palette = AppPalette.of(context);
Container(color: palette.accent);

// ❌ MAL — hex literal
Container(color: Color(0xFF2CE5A2));

// ❌ MAL — AppColorPrimitives desde widget
Container(color: AppColorPrimitives.mint500);
```

### API pública

```dart
// Paletas constantes
AppPalette.mintMagenta        // dark
AppPalette.mintMagentaLight   // light

// Acceso en widget tree
AppPalette.of(BuildContext context) → AppPalette

// ThemeExtension API
palette.copyWith({Color? accent, ...})
AppPalette.lerp(ThemeExtension?, double)
```

---

## Capa 3 — Tokens de componente

Clases `abstract final` con métodos `static` que leen `AppPalette.of(ctx)` o primitivos de forma (radio, padding). **Nunca usan HEX inline**.

El patrón es reproducible: cada token de componente nuevo va en `lib/app/theme/tokens/components/` sin modificar archivos existentes.

### TreinoButtonTokens

```dart
import 'package:treino/app/theme/tokens/tokens.dart';

Container(
  decoration: BoxDecoration(
    color: TreinoButtonTokens.background(context),
    borderRadius: BorderRadius.circular(TreinoButtonTokens.borderRadius),
  ),
  child: Text(
    'Guardar',
    style: TextStyle(color: TreinoButtonTokens.foreground(context)),
  ),
)
```

| Propiedad | Tipo | Valor |
|---|---|---|
| `background(ctx)` | `Color` | `AppPalette.of(ctx).accent` |
| `foreground(ctx)` | `Color` | `AppColorPrimitives.ink950` (contraste WCAG AA sobre mint) |
| `borderRadius` | `double` | `AppRadius.sm` (12.0) |

### TreinoCardTokens

```dart
Container(
  decoration: BoxDecoration(
    color: TreinoCardTokens.background(context),
    border: Border.all(color: TreinoCardTokens.border(context)),
    borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
    boxShadow: TreinoCardTokens.boxShadow, // siempre []
  ),
)
```

| Propiedad | Tipo | Valor |
|---|---|---|
| `background(ctx)` | `Color` | `AppPalette.of(ctx).bgCard` |
| `border(ctx)` | `Color` | `AppPalette.of(ctx).border` |
| `borderRadius` | `double` | `AppRadius.md` (16.0) |
| `boxShadow` | `List<BoxShadow>` | `[]` — sin sombra; el contraste lo da el ink |

### Agregar nuevos tokens de componente

```dart
// lib/app/theme/tokens/components/kpi_card_tokens.dart
abstract final class KpiCardTokens {
  static Color background(BuildContext ctx) => AppPalette.of(ctx).bgCard;
  static Color valueText(BuildContext ctx) => AppPalette.of(ctx).accent;
  static const double borderRadius = AppRadius.md;
}
```

No modificar archivos existentes. El barrel `tokens.dart` solo necesita el `export` del archivo nuevo.

---

## Motion

El movimiento vive en `AppMotion` (`lib/app/theme/app_motion.dart`) y `AppMotionTokens` (`lib/app/theme/tokens/motion_tokens.dart`). No hardcodear duraciones ni curvas en widgets.

### Cuándo usar cada componente de motion

| Situación | Componente correcto |
|---|---|
| Estado async visible (loading → data, loading → error) | `TreinoStateSwitcher` |
| Entrada one-shot de secciones en pantallas eager (`ListView(children:[...])`, `Column`) | `TreinoFadeSlideIn` |
| Feedback de presión/tap en CTAs, cards y tiles propios | `TreinoTappable` |
| Loading con layout conocido (listas, cards) | `TreinoShimmer` |
| Listas lazy (`ListView.builder`, `.separated`) | **No animar entrada** — el widget se reanima al reciclarse |

### Tokens semánticos de AppMotionTokens

`AppMotionTokens` mapea intenciones de componente a los escalones de `AppMotion`. Usalo en código nuevo; `AppMotion` sigue siendo válido en código existente.

| Token | Duración | Cuándo usarlo |
|---|---|---|
| `tapFeedback` | 120 ms (`AppMotion.micro`) | Feedback de tap-down, toggles, selección de chip |
| `cardStateChange` | 180 ms (`AppMotion.fast`) | Cambio de estado de card o container chico |
| `stateSwitch` | 240 ms (`AppMotion.base`) | `TreinoStateSwitcher` loading → data/error, switch de tab |
| `contentEnter` | 240 ms (`AppMotion.base`) | Entrada de contenido principal, expand/collapse |
| `pageTransition` | 320 ms (`AppMotion.slow`) | Transición de ruta, pill del tab bar |

### Curvas semánticas

| Token | Curva | Cuándo |
|---|---|---|
| `enter` | `easeOutCubic` | Entradas — desacelera al final |
| `reposition` | `easeInOutCubic` | Movimientos amplios o que piden atención |
| `leave` | `easeInCubic` | Salidas — acelera hacia el final |

### Distancias de slide

| Token | Px | Uso |
|---|---|---|
| `rowSlide` | 8 | Rows/chips densos |
| `cardSlide` | 12 | Entrada de card/ítem default |
| `heroSlide` | 20 | Hero cards, secciones grandes |

### Ejemplo de uso de AppMotionTokens

```dart
AnimatedContainer(
  duration: AppMotion.resolve(context, AppMotionTokens.cardStateChange),
  curve: AppMotionTokens.enter,
  color: isSelected ? palette.accent : palette.bgCard,
  child: ...,
)
```

### Política de reduce-motion

Toda animación debe respetar la preferencia del sistema. La puerta única es `AppMotion.resolve`:

```dart
// ✅ BIEN — respeta reduce-motion
AnimatedOpacity(
  duration: AppMotion.resolve(context, AppMotionTokens.contentEnter),
  opacity: visible ? 1.0 : 0.0,
  child: ...,
)

// También disponible vía AppMotionTokens:
AppMotionTokens.resolve(context, AppMotionTokens.stateSwitch)
AppMotionTokens.reduceMotion(context) // → bool
```

`TreinoStateSwitcher`, `TreinoFadeSlideIn`, `TreinoTappable` y `TreinoShimmer` ya respetan reduce-motion internamente.

### Reglas de motion (no negociables)

- Nunca hardcodear `Duration(milliseconds: N)` — usar tokens de `AppMotion` o `AppMotionTokens`.
- Nunca usar `TreinoFadeSlideIn` dentro de `ListView.builder`/`.separated` — el widget se reanima al reciclarse durante el scroll.
- No animar para decorar. Animar cambios de estado mental: aparición, selección, feedback de tap, carga, expansión, navegación especial.
- No usar loops infinitos salvo loading real o caso justificado y acotado.
- Preferir animaciones implícitas. Si usás `AnimationController`, debe vivir en un widget hoja y liberar en `dispose()`.
- Stagger máximo capado a 8 ítems — usar `AppMotion.stagger(index)` (ya lo hace automáticamente).

---

## Tipografía

- **Heading**: `Barlow Condensed` 700 (`AppFonts.barlowCondensed`), **UPPERCASE**, letter-spacing 0.5 px (`AppFonts.headingTracking`). Para títulos de sección, hero numbers, CTAs.
- **Body**: `Barlow` 400 / 600 / 700 (`AppFonts.barlow`), Title Case. Para microcopy, listas, párrafos.
- **Numérico hero** (streak, peso, XP): `Barlow Condensed` 700, tamaños 56–72 px.
- Source: Google Fonts via `google_fonts` package. Los `TextStyle` completos viven en `app_theme.dart`.

---

## Modos de tema

TREINO soporta **dark y light** de forma explícita:

| Modo | Descripción |
|---|---|
| `AppTheme.dark` | Tema oscuro con `AppPalette.mintMagenta` — **identidad de marca, default** |
| `AppTheme.light` | Tema claro con `AppPalette.mintMagentaLight` — alternativa real y soportada |

El modo activo lo gestiona `ThemeModeNotifier` (Riverpod). El usuario puede elegir Sistema/Claro/Oscuro en Perfil → Apariencia. El default del sistema es dark cuando el dispositivo está en modo oscuro; en modo claro del sistema, se aplica light salvo que el usuario haya fijado "Oscuro" explícitamente.

Cards: fondo `bgCard`, border 1px `border`, **sin shadow** (el contraste lo da el ink en dark, y el paper en light).
Hero con glow: streak card y CTA usan halo radial sutil de `accent @ 18% → 0%`.

---

## Reglas de código de UI (no negociables)

### 1. Nunca HEX literal en widgets

```dart
// ❌ MAL
Container(color: Color(0xFF2CE5A2));

// ✅ BIEN
final palette = AppPalette.of(context);
Container(color: palette.accent);
```

Tokens disponibles: `accent`, `highlight`, `bg`, `bgCard`, `border`, `borderHover`, `textPrimary`, `textMuted`, `sage`, `espresso`, `danger`, `warning`, `onDanger`, `scrimDark`.

El test `test/app/theme/tokens/no_hex_scan_test.dart` falla si se agrega un HEX fuera de la allowlist (primitives.dart + app_palette.dart). Este test corre en CI.

### 2. Nunca PhosphorIcons directo

```dart
// ❌ MAL
Icon(PhosphorIconsRegular.houseSimple);

// ✅ BIEN
Icon(TreinoIcon.tabHome);
```

Si falta un ícono, agregarlo a `lib/core/widgets/treino_icon.dart` con nombre semántico.

### 3. Nunca hard-code de strings de UI

Tab labels, feature names, mensajes — centralizar en constantes o en archivos de localización (`lib/l10n/`).

---

## Componentes base disponibles

Viven en `lib/core/widgets/`:

- `AppBackground` — Container con fondo `bg`.
- `TreinoIcon` — wrapper semántico sobre Phosphor (regular + fill).
- `TreinoBottomBar` — tab bar de 5 ítems.
- `TreinoStateSwitcher` — transición animada entre estados async (loading/error/data).
- `TreinoFadeSlideIn` — entrada one-shot fade+slide para secciones eager.
- `TreinoTappable` — feedback de presión para CTAs, cards y tiles propios.
- `TreinoShimmer` — skeleton de carga; `enabled: false` en error/null estable.

A medida que crezca la app vamos a sumar (Fases 1–12):

- `TreinoButton` (primary / secondary / ghost / pill)
- `TreinoCard` (default / hero / elevated)
- `TreinoChip` (muscle / exercise / tag / distance)
- `TreinoInput` (text / password / email / numeric)
- `Avatar`, `Badge`, `StatTile`, `StreakHero`

Cuando necesités uno y no exista, lo creás como parte del PR — pero asegurate de poner los estados (normal / hover / pressed / disabled / focus) y reusarlo en al menos 2 lugares antes de mergear.

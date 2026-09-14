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

Escala **cerrada** para separar elementos: `8 · 12 · 14 · 18 · 20` px. No existen
`s4`, `s16` ni `s24`.

| Token | Valor | Uso típico |
|---|---|---|
| `AppSpacing.s8` | `8.0` | Gap interno de rows densas, chips |
| `AppSpacing.s12` | `12.0` | Padding interno de cards |
| `AppSpacing.s14` | `14.0` | Padding de secciones compactas |
| `AppSpacing.s18` | `18.0` | Padding horizontal de pantallas |
| `AppSpacing.s20` | `20.0` | Padding de hero cards, secciones amplias |
| `AppSpacing.hairline` | `4.0` | **Excepción** — ver abajo |

```dart
// ✅ BIEN
Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.s18));

// ❌ MAL — valores fuera de escala
Padding(padding: EdgeInsets.all(16));
```

#### La excepción: `hairline`

La escala cerrada gobierna el espacio **entre elementos que compone el layout**.
No sabe expresar dos casos sub-8 que igual existen, y para esos está `hairline`:

1. **Separaciones ópticas** entre cosas que se leen como una sola unidad —
   valor-a-label, ícono-a-texto, título-a-subtítulo.
2. **Gutters internos de un componente del kit**, cuando dos capas del mismo
   control se tocan. El caso vivo es `TreinoSegmentedPill`: los 4px entre el
   contorno de la pista y el thumb.

La distinción es **de dueño del espacio**. Si lo posee un componente y nadie de
afuera puede razonar sobre él, es `hairline`. Si separa cosas que el layout
acomoda, es la escala cerrada. En la duda, escala cerrada.

```dart
// ✅ BIEN — geometría interna del control
Container(padding: EdgeInsets.all(AppSpacing.hairline), child: TabBar(...));

// ❌ MAL — esto es layout, va a la escala
Column(children: [a, SizedBox(height: AppSpacing.hairline), b]);
```

El caso 2 se agregó con #646. Antes la regla prohibía todo padding sub-8, así
que el gutter no tenía token válido y las cinco copias del control segmentado lo
resolvían con `EdgeInsets.all(4)` crudo — exactamente lo que `hairline` existe
para evitar. **No agregues más excepciones sin ampliar esta sección**: un
micro-token ad-hoc por componente es cómo se pierde una escala.

### AppRadius

| Token | Valor | Uso típico |
|---|---|---|
| `AppRadius.sm` | `12.0` | Chips, inputs pequeños |
| `AppRadius.md` | `16.0` | Cards default |
| `AppRadius.lg` | `20.0` | Hero cards, bottom sheets |
| `AppRadius.full` | `9999.0` | CTAs pill, avatares |

La escala es **cerrada**: un radio nuevo se pide como excepción, no se inventa
inline. Ver [Excepciones a la escala de radios](#excepciones-a-la-escala-de-radios).

### AppFonts

| Token | Valor | Uso |
|---|---|---|
| `AppFonts.barlow` | `'Barlow'` | Cuerpo de texto (pesos 400/600/700) |
| `AppFonts.barlowCondensed` | `'Barlow Condensed'` | Headings (700, UPPERCASE) |
| `AppFonts.w400` | `FontWeight.w400` | Regular |
| `AppFonts.w600` | `FontWeight.w600` | Semibold (labels, subtítulos) |
| `AppFonts.w700` | `FontWeight.w700` | Bold (headings, CTAs) |
| `AppFonts.headingTracking` | `0.5` | Letter-spacing de headings |

### AppTextSize

Escala **cerrada** de tamaños. Ver [regla 5](#5-nunca-fontsize-crudo-en-widgets)
y [Excepciones a la escala tipográfica](#excepciones-a-la-escala-tipográfica).

| Token | Valor | Uso |
|---|---|---|
| `AppTextSize.micro` | `10` | Contadores de badge, timestamps, legales al pie |
| `AppTextSize.caption` | `12` | Labels de campo, chips, metadatos, texto de ayuda |
| `AppTextSize.bodyDense` | `13` | Cuerpo denso: filas de tabla y listas del Coach Hub web |
| `AppTextSize.body` | `14` | **Cuerpo por defecto** — si dudás, es este |
| `AppTextSize.bodyLarge` | `16` | Cuerpo destacado y texto de input |
| `AppTextSize.title` | `18` | Título de card |
| `AppTextSize.titleLarge` | `20` | Título de sección |
| `AppTextSize.heading` | `24` | Heading de pantalla |
| `AppTextSize.display` | `28` | Número hero dentro de una card (KPI, racha) |
| `AppTextSize.displayLarge` | `32` | Número hero a nivel pantalla |

**El racimo `12 · 13 · 14` está apretado a propósito, y se cierra ahí.** TREINO
sirve una app de teléfono y un panel de escritorio desde el mismo código: un
label (`caption`), una fila de tabla del Coach Hub (`bodyDense`) y un párrafo en
un celular (`body`) son tres roles reales que se pisan justo en el rango del
texto chico. De `body` para arriba esa excusa no existe — son títulos y números
hero, y ahí todos los saltos son de 2px o más. Un escalón nuevo pegado a otro en
ese tramo es deriva, no un rol. Los dos invariantes tienen test en
`primitives_test.dart`.

`bodyLarge` es 16 y no 15 por una razón concreta: abajo de 16px los navegadores
móviles hacen zoom al enfocar un campo de texto.

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
| `borderStrong` | `white35` | `rgba(255,255,255,0.35)` | Filo de una superficie apoyada sobre `bg` (bottom bar) — ≥3:1, WCAG 1.4.11 |
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
| `borderStrong` | `black50` | `rgba(0,0,0,0.50)` | Filo de superficie sobre `bg` en light — ≥3:1, WCAG 1.4.11 |
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

Superficies translúcidas apoyadas sobre el fondo desnudo (la bottom bar) usan `borderStrong` y no `border`: `bgCard` sobre `bg` compone 1,05:1 en dark, así que el relleno no delata dónde empieza el contenedor y el filo es lo único que lo hace (#821).
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

Tokens disponibles: `accent`, `highlight`, `bg`, `bgCard`, `border`, `borderHover`, `borderStrong`, `textPrimary`, `textMuted`, `sage`, `espresso`, `danger`, `warning`, `onDanger`, `scrimDark`.

El test `test/app/theme/tokens/no_hex_scan_test.dart` falla si se agrega un HEX fuera de la allowlist (hoy: sólo `primitives.dart` — `app_palette.dart` salió de la lista en WU-02). Este test corre en CI.

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

### 4. Nunca radio crudo en widgets

```dart
// ❌ MAL
BorderRadius.circular(16);

// ✅ BIEN
BorderRadius.circular(AppRadius.md);
```

El test `test/app/theme/tokens/no_raw_radius_scan_test.dart` falla si se agrega
un `Radius.circular(<literal>)` fuera de la allowlist. Corre en CI.

A diferencia del scanner de HEX, este arranca con una allowlist grande: al
congelarse el guard había **677 literales en 150 archivos** contra ~71 usos de
`AppRadius`. La allowlist es un **registro de deuda**, no una licencia — estar
en la lista significa "pendiente de migrar", no "exento".

El guard tiene cuatro reglas, y la tercera es la que le falta al de HEX:

1. Ningún archivo fuera de la allowlist puede tener un radio crudo.
2. La allowlist nunca crece.
3. **La deuda total nunca crece** — sumar un radio crudo a un archivo que ya
   está en la lista también rompe el build. Sin esta regla, un archivo listado
   podía acumular literales sin que nadie lo viera, que es exactamente cómo se
   llegó a esa cifra.
4. Un archivo que ya no tiene radios crudos debe salir de la allowlist.

Si tocás un archivo de la allowlist, migrá sus radios y sacalo de la lista. Es
la única forma en que el número baja.

#### Excepciones a la escala de radios

Hay valores que no están en la escala y **no son un descuido**: la cola
asimétrica de la burbuja de chat (`14/14/14/4`) viene del mockup aprobado en
#339. Cambiarlos a `AppRadius` altera un diseño firmado.

Cuando necesitás un radio que no está en la escala:

1. **Verificá que no exista ya.** `AppRadius.sm` (12) y `AppRadius.md` (16)
   cubren casi todo lo que se pide como "14".
2. **Abrí un issue con la evidencia**: mockup o captura, el valor, y por qué
   un token existente no sirve. No lo resuelvas en el PR de la feature.
3. **Con el diseño aprobado, elegí una de dos** — y decidilo con el reviewer,
   no por tu cuenta:
   - **Ampliar la escala**: agregar el token a `AppRadius` en
     `lib/app/theme/tokens/primitives.dart`, documentarlo en la tabla de arriba
     y usarlo. Esta es la opción por defecto si el valor se repite.
   - **Aceptar la excepción**: dejar el literal, sumar el archivo a la
     allowlist del scanner y subir los dos techos. Requiere aprobación
     explícita del reviewer en el PR, porque va contra el ratchet.

Lo que **no** se hace: agregar el archivo a la allowlist en silencio, o subir
un techo sin que nadie lo mire. Los techos son la memoria del sistema.

### 5. Nunca `fontSize` crudo en widgets

```dart
// ❌ MAL
TextStyle(fontFamily: AppFonts.barlow, fontSize: 14);

// ✅ BIEN
TextStyle(fontFamily: AppFonts.barlow, fontSize: AppTextSize.body);
```

El test `test/app/theme/tokens/no_raw_font_size_scan_test.dart` falla si se
agrega un `fontSize: <literal>` fuera de la allowlist. Corre en CI. Mismas
cuatro reglas que el de radios, incluido el ratchet de deuda total.

**Por qué llegó tan tarde.** Color, spacing, radios, íconos y motion tuvieron
token *y* guard desde temprano, y se respetan con cero excepciones en todo el
repo. Tipografía tenía `AppFonts` —familias, pesos, tracking— pero **ningún
token de tamaño**: el dartdoc mandaba los `TextStyle` completos a
`app_theme.dart`, y ahí sólo vive el `textTheme` de Material, que ningún widget
lee. Entre "el tema define estilos" y "el widget necesita un número" quedó un
hueco, y lo llenaron **1879 literales en 271 archivos con 31 tamaños
distintos**, medios píxeles incluidos (`9.5`, `11.5`, `12.5`).

Nadie se salteó una regla. No había regla.

#### Excepciones a la escala tipográfica

`AppTextSize` cubre 1609 de esas 1879 ocurrencias **sin mover un píxel**, así
que la mayor parte de la migración es mecánica. Lo que queda:

- **Deriva migrable, con cambio visual**: `11` (146 usos, un píxel abajo de
  `caption` y haciendo el mismo trabajo), `15` (54, entre `body` y `bodyLarge`)
  y los medios píxeles. Van al escalón más cercano. Como mueven píxeles, se
  migran mirando la pantalla, no con un `sed`.
- **Tamaños de ilustración** (`features/onboarding/presentation/`): los decks
  del tour **dibujan** la app en vez de mostrarla, igual que
  `AppDecorativeRadii` para los radios. Forzarles la escala deforma el dibujo.
  Si hace falta, se les da su propio primitivo decorativo — no entran a
  `AppTextSize`.

Para cualquier otro caso, el proceso es el mismo que en la sección de radios:
issue con evidencia, y con el diseño aprobado se decide con el reviewer entre
ampliar la escala o aceptar la excepción subiendo los techos. Ampliar es la
opción por defecto si el valor se repite.

Ojo con un antipatrón particular de tipografía: **si tu tamaño nuevo queda a un
píxel de un escalón existente, casi seguro lo que necesitás es el escalón que
ya está.** El único par a 1px de la escala es `bodyDense`/`body` (13/14), y está
justificado porque TREINO sirve una app de teléfono y un panel de escritorio
desde el mismo código. Hay un test que lo verifica en `primitives_test.dart`.

### 6. Nunca spacing fuera de la escala

```dart
// ❌ MAL — 16 y 24 están prohibidos por nombre en AGENTS.md §2
SizedBox(height: 16);
EdgeInsets.all(24);

// ✅ BIEN
SizedBox(height: AppSpacing.s14);
EdgeInsets.all(AppSpacing.s20);
```

El test `test/app/theme/tokens/no_off_scale_spacing_scan_test.dart` falla si se
agrega un valor fuera de `8 · 12 · 14 · 18 · 20` (+ `4` hairline, + `0`) en un
`SizedBox` de separación o en un `EdgeInsets`. Corre en CI, mismas cuatro reglas
de ratchet que los otros tres guards.

**Este guard mira el VALOR, no el literal** — y ahí se separa de los otros tres.
`Radius.circular(16)` está mal aunque 16 sea `AppRadius.md`, porque el objetivo
de ese guard es que se use el token. Acá `SizedBox(height: 8)` **pasa**: cumple
la regla tal como está escrita. Usar `AppSpacing.s8` es mejor y se recomienda,
pero exigirlo sería inventar una regla más estricta que la acordada y convertir
1407 usos correctos en deuda. Lo que este guard persigue es el daño real: el
`16` y el `24` que se cuelan.

Al congelarse había **982 valores fuera de escala en 166 archivos**, y los tres
más usados eran `16` (192), `10` (186) y `24` (180). O sea: 372 ocurrencias de
una regla escrita en la constitución del repo, sin nadie que la mirara.

#### Excepciones a la escala de spacing

Antes de pedir una excepción, chequeá si tu número es **spacing o layout**. El
ancho de un panel, el alto de una card, el despeje de la bottom bar: eso no es
spacing, y meterlo en un `EdgeInsets` es lo que lo hace parecer una violación.
Sacalo a una constante con nombre —`_kPanelWidth`, `_kBottomBarClearance`— y
además de salir del scanner, el número pasa a decir qué es.

Si de verdad necesitás un valor de separación fuera de escala, el proceso es el
mismo que en radios y tipografía: issue con la evidencia, y con el diseño
aprobado se decide con el reviewer entre ampliar la escala o aceptar la
excepción subiendo los techos. Ampliar la escala de spacing es **la opción menos
probable de las tres**: `8 · 12 · 14 · 18 · 20` es corta a propósito, y casi
todo lo que se pide como `16` entra en `14` o en `18` sin que nadie note la
diferencia.

---

## Componentes base disponibles

Viven en `lib/core/widgets/`:

- `AppBackground` — Container con fondo `bg`.
- `TreinoIcon` — wrapper semántico sobre Phosphor (regular + fill).
- `TreinoBottomBar` — tab bar de 5 ítems.
- `TreinoSegmentedPill` — control segmentado de sub-navegación (TU ENTRENO/PLANTILLAS, FEED/RANKINGS, ALUMNOS/AGENDA, PRESENCIAL/ONLINE). Lee el `DefaultTabController` ambiente; no lo posee. Casi nada es parametrizable a propósito: las 4 copias que reemplaza habían divergido en radio, alto, tipografía y overflow. Tokens en `TreinoSegmentedPillTokens`, que documenta por qué el contorno es más fuerte que el de las cards (WCAG 1.4.11, #646).
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

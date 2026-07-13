# Design: Design System v2 — FASE 0 (arquitectura de tokens de 3 capas)

> Cambio: redesign-coach-hub-web · Fase: **0 de 0–12** · Rama: refactor/theme-design-system-v2 · Store: hybrid · TDD: estricto (test antes de código)

## TL;DR

FASE 0 formaliza una arquitectura de tokens de **3 capas + motion** en Dart bajo `lib/app/theme/tokens/`, **sin un solo cambio visual ni de API**. Es una **reestructuración aditiva**, no un rediseño.

- **Capa 1 — Primitivos** (NUEVO): valores crudos sin `BuildContext`. `color_primitives.dart` (escala tonal: `mint500`, `magenta500`, `ink950`, …), `spacing_primitives.dart` (`AppSpacing.s8/s12/s14/s18/s20`), `radius_primitives.dart` (`AppRadius.sm/md/lg/full`), `type_primitives.dart` (familias + pesos Barlow / Barlow Condensed).
- **Capa 2 — Semántica** (REFACTOR interno): `app_palette.dart` conserva **API pública idéntica** (`of(context)`, `mintMagenta`, `mintMagentaLight`, `copyWith`, `lerp`, los 14 campos). Cada constante pasa a **referenciar un primitivo** en lugar de un hex literal. Cero cambio de valor de color.
- **Capa 3 — Componente** (NUEVO): `tokens/components/` con `TreinoButtonTokens` y `TreinoCardTokens` (mínimo de esta fase) que resuelven vía `static of(BuildContext)` leyendo `AppPalette.of(ctx)` + primitivos. Nunca hex crudo.
- **Motion** (FORMALIZAR): `motion_tokens.dart` con `AppMotionTokens` semánticos de dominio de componente, reexportando `AppMotion` **sin cambiar ningún valor runtime**.
- **Barrel**: `tokens/tokens.dart` reexporta todo para import ergonómico.
- **Docs**: reescritura de `docs/design-system.md` (3 capas + Motion + light real + sin Electric Violet) y corrección de comentario en `docs/architecture.md`.
- **Enforcement**: test que escanea `lib/` fuera de `tokens/` buscando `Color(0x…)`, con allowlist explícita de archivos legacy pendientes de Fases 1–12.

**Lo que NO cambia**: comportamiento de `app_theme.dart`, `theme_mode_provider.dart`, `theme_watcher.dart`, `app_background.dart`, y la salida visual pixel-a-pixel de la app. `AppColors` se mantiene como alias de compatibilidad (deprecated), no se borra en esta fase.

- Archivos nuevos: 7 (5 en `tokens/`, 2 en `tokens/components/`) + 1 barrel. Archivos modificados: 3 (`app_palette.dart`, `design-system.md`, `architecture.md`).
- Tests nuevos: 5 suites (identidad de paleta, API-compat, resolución de tokens de componente, valores de motion, no-hex scanner).
- **9 ADRs** (ADR-DS2-001 … ADR-DS2-009).

---

## 1. Enfoque elegido (recap del análisis)

Se adopta **Opción A** de la exploración: **clases estáticas `const`** para primitivos/spacing/radios/tipografía + **tokens de componente con factory `of(ctx)`** que leen `AppPalette.of(ctx)`.

Descartadas:
- **Opción B (ThemeExtension por componente)**: soporta `lerp`/override por subtree pero exige `copyWith`+`lerp`+registro manual por cada set → boilerplate alto sin necesidad actual. La Opción A es **migrable a B sin tocar call sites** porque ambas exponen `TreinoXTokens.of(ctx)` como único punto de acceso.
- **Opción C (extension methods sobre AppPalette)**: cero boilerplate pero no acomoda spacing/radios (constantes sin `BuildContext`) ni permite futura variación por subtree.

**Principio rector de la fase**: *restructure, not redesign*. Si un test de identidad de color falla, la fase falló — no hay tolerancia visual en Fase 0 (a diferencia de Fases 1–12).

---

## 2. Layout de archivos (`lib/app/theme/`)

```
lib/app/theme/
├── tokens/                         ← NUEVO (Fase 0)
│   ├── tokens.dart                 ← barrel: reexporta todo tokens/**
│   ├── color_primitives.dart       ← AppColorPrimitives (escala tonal, const, sin ctx)
│   ├── spacing_primitives.dart     ← AppSpacing (s8/s12/s14/s18/s20)
│   ├── radius_primitives.dart      ← AppRadius (sm/md/lg/full)
│   ├── type_primitives.dart        ← AppType (familias + pesos Barlow/BarlowCondensed)
│   ├── motion_tokens.dart          ← AppMotionTokens (semántico sobre AppMotion)
│   └── components/                 ← NUEVO
│       ├── treino_button_tokens.dart   ← TreinoButtonTokens.of(ctx)
│       └── treino_card_tokens.dart     ← TreinoCardTokens.of(ctx)
├── app_palette.dart                ← MODIFICADO (referencia primitivos; API intacta)
├── app_motion.dart                 ← SIN CAMBIO (fuente de verdad de valores runtime)
├── app_theme.dart                  ← SIN CAMBIO
├── app_background.dart             ← SIN CAMBIO
├── theme_mode_provider.dart        ← SIN CAMBIO
└── theme_watcher.dart              ← SIN CAMBIO
```

### Justificación del layout

- **Un archivo por familia de primitivo** (no un mega-archivo `primitives.dart`): cada familia tiene un test de identidad propio, cambia por razones distintas, y se importa de forma granular. Un archivo monolítico obligaría a reimportar toda la escala tonal para usar solo spacing. *Nota: la exploración mencionó `primitives.dart` único; acá se decide **dividir por familia** (ADR-DS2-002), que es estrictamente más modular y no rompe nada porque el barrel unifica el import.*
- **`tokens/components/` como subcarpeta**: los tokens de componente dependen de `BuildContext` (capa distinta), y esta carpeta crecerá una clase por componente en Fases 1–12 (KpiCard, DataTable, ListRow, …). Separarlos de los primitivos deja la raíz `tokens/` como "capas fundacionales" y `components/` como "capa dependiente de contexto".
- **`app_motion.dart` NO se mueve**: sigue siendo la fuente de verdad de duraciones/curvas/distancias. `motion_tokens.dart` es una capa semántica *encima*, no un reemplazo (ADR-DS2-006).
- **`app_palette.dart` NO se mueve a `tokens/`**: es un `ThemeExtension` registrado en `AppTheme` con ~499 call sites; moverlo cambiaría todos los imports. Se queda donde está y solo cambia su *implementación interna* (ADR-DS2-003).

---

## 3. Capa 1 — Primitivos

### 3.1 `color_primitives.dart` — `AppColorPrimitives`

Clase `abstract final` con `static const Color`. Nombres **semántico-neutrales con escala tonal** (`{familia}{peso}`) para permitir tonos derivados en Fases 1–12 (dataViz mint/teal, dots de estado) sin volver a hardcodear.

```dart
import 'package:flutter/painting.dart' show Color;

/// Capa 1 — Primitivos de color. Valores CRUDOS, sin semántica ni BuildContext.
/// Ningún widget los usa directo: los consume la capa semántica (AppPalette)
/// y la capa de componente. La escala tonal permite derivar tonos en fases
/// posteriores sin re-hardcodear hex.
abstract final class AppColorPrimitives {
  const AppColorPrimitives._();

  // Marca — Mint (acento primario). 500 = valor de marca oficial.
  static const Color mint500 = Color(0xFF2CE5A2);

  // Marca — Magenta (acento secundario). 500 = valor de marca oficial.
  static const Color magenta500 = Color(0xFFC123E0);

  // Neutrales fríos — Ink (fondos dark, la base #0A0A0A a #1A1A1A).
  static const Color ink950 = Color(0xFF0A0A0A); // bg dark
  static const Color ink900 = Color(0xFF0F1513); // bgCard dark

  // Neutrales cálidos — superficies y outlines.
  static const Color espresso700 = Color(0xFF3C3534); // superficies elevadas dark
  static const Color sage600 = Color(0xFF4F6358);     // cards secundarias dark

  // Neutrales claros (light mode).
  static const Color bone = Color(0xFFFFFFFF);        // texto sobre ink / bgCard light
  static const Color paper50 = Color(0xFFFAFAFA);     // bg light
  static const Color inkText900 = Color(0xFF0F1513);  // textPrimary light
  static const Color sageTint50 = Color(0xFFDDE5DF);  // sage light
  static const Color espressoTint50 = Color(0xFFEDE5E2); // espresso light

  // Feedback — Danger / Warning (dark).
  static const Color red600 = Color(0xFFE53935);   // danger dark
  static const Color amber600 = Color(0xFFFFB300);  // warning dark
  // Feedback — Danger / Warning (light, más saturados p/ contraste sobre paper).
  static const Color red700 = Color(0xFFD32F2F);   // danger light
  static const Color amber700 = Color(0xFFFB8C00);  // warning light

  // Overlays / scrims — negro puro, constante en ambos temas.
  static const Color black = Color(0xFF000000);

  // Alphas sobre blanco/negro para borders y textos muted.
  // (Se nombran por canal+alpha para que el mapeo semántico sea explícito.)
  static const Color white10 = Color(0x1AFFFFFF); // border dark
  static const Color white20 = Color(0x33FFFFFF); // borderHover dark
  static const Color white55 = Color(0x8CFFFFFF); // textMuted dark
  static const Color black10 = Color(0x1A000000); // border light
  static const Color black20 = Color(0x33000000); // borderHover light
  static const Color black60 = Color(0x99000000); // textMuted light
}
```

**Regla de exhaustividad (crítica)**: `AppColorPrimitives` debe contener **exactamente** cada hex que hoy aparece en `app_palette.dart` (los 6 de `AppColors` + los ~16 hex inline de `mintMagenta`/`mintMagentaLight`). El test de identidad (§7.1) garantiza cobertura total: si un hex no tiene primitivo, la semántica no puede referenciarlo y el test de compilación falla.

### 3.2 `spacing_primitives.dart` — `AppSpacing`

```dart
abstract final class AppSpacing {
  const AppSpacing._();

  /// 8px — spacing mínimo (gaps densos, íconos).
  static const double s8 = 8;
  /// 12px — spacing default entre elementos relacionados.
  static const double s12 = 12;
  /// 14px — padding interno de componentes chicos.
  static const double s14 = 14;
  /// 18px — padding de card / input.
  static const double s18 = 18;
  /// 20px — spacing de sección.
  static const double s20 = 20;
}
```

Escala **cerrada** a `8·12·14·18·20`. **NO** existen `s4/s16/s24` — su ausencia es intencional y el test de spacing (§7.4) asserta que la clase no expone otros valores. Los 27 archivos con `EdgeInsets` 16/24 se corrigen en sus Fases respectivas (1–12), no en Fase 0.

### 3.3 `radius_primitives.dart` — `AppRadius`

```dart
abstract final class AppRadius {
  const AppRadius._();

  static const double sm = 12;    // chips, inputs
  static const double md = 16;    // cards default
  static const double lg = 20;    // hero cards
  static const double full = 9999; // pills, avatares
}
```

### 3.4 `type_primitives.dart` — `AppType`

Solo familias y pesos como primitivos; los `TextStyle` completos siguen construyéndose en `app_theme.dart` (que NO cambia). Esto evita duplicar la lógica de `GoogleFonts` y mantiene `app_theme.dart` como único builder de `TextTheme`.

```dart
import 'package:flutter/painting.dart' show FontWeight;

abstract final class AppType {
  const AppType._();

  static const String headingFamily = 'Barlow Condensed';
  static const String bodyFamily = 'Barlow';

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// letter-spacing de headings UPPERCASE (ver app_theme.dart).
  static const double headingTracking = 0.5;
}
```

---

## 4. Capa 2 — Semántica (`app_palette.dart`, refactor interno)

**API pública 100% intacta.** Cambia solo el lado derecho de cada asignación: `Color(0x…)` → `AppColorPrimitives.xxx`. Los `static const AppPalette` siguen siendo `const` (los primitivos son `const`, así que la expresión sigue siendo constante).

### 4.1 `AppColors` — compat deprecated (NO se borra)

`AppColors` tiene call sites externos posibles. En Fase 0 se **mantiene** pero se re-implementa como alias a primitivos y se marca `@Deprecated`. Borrarlo es trabajo de una fase futura (fuera de scope).

```dart
@Deprecated('Usar AppColorPrimitives (capa 1). Se eliminará tras Fases 1–12.')
class AppColors {
  static const ink = AppColorPrimitives.ink950;
  static const espresso = AppColorPrimitives.espresso700;
  static const sage = AppColorPrimitives.sage600;
  static const bone = AppColorPrimitives.bone;
  static const magenta = AppColorPrimitives.magenta500;
  static const mint = AppColorPrimitives.mint500;
}
```

### 4.2 `AppPalette.mintMagenta` / `.mintMagentaLight` — mapeo semántico → primitivo

Firma, campos, `of`, `copyWith`, `lerp`: **sin cambio**. Solo las dos constantes reescriben sus valores:

```dart
static const mintMagenta = AppPalette(
  accent: AppColorPrimitives.mint500,
  highlight: AppColorPrimitives.magenta500,
  bg: AppColorPrimitives.ink950,
  bgCard: AppColorPrimitives.ink900,
  border: AppColorPrimitives.white10,
  borderHover: AppColorPrimitives.white20,
  textPrimary: AppColorPrimitives.bone,
  textMuted: AppColorPrimitives.white55,
  sage: AppColorPrimitives.sage600,
  espresso: AppColorPrimitives.espresso700,
  danger: AppColorPrimitives.red600,
  warning: AppColorPrimitives.amber600,
  onDanger: AppColorPrimitives.bone,
  scrimDark: AppColorPrimitives.black,
);

static const mintMagentaLight = AppPalette(
  accent: AppColorPrimitives.mint500,
  highlight: AppColorPrimitives.magenta500,
  bg: AppColorPrimitives.paper50,
  bgCard: AppColorPrimitives.bone,
  border: AppColorPrimitives.black10,
  borderHover: AppColorPrimitives.black20,
  textPrimary: AppColorPrimitives.inkText900,
  textMuted: AppColorPrimitives.black60,
  sage: AppColorPrimitives.sageTint50,
  espresso: AppColorPrimitives.espressoTint50,
  danger: AppColorPrimitives.red700,
  warning: AppColorPrimitives.amber700,
  onDanger: AppColorPrimitives.bone,
  scrimDark: AppColorPrimitives.black,
);
```

**Invariante de identidad** (test §7.1): cada `.value` (ARGB int) de cada campo debe ser **idéntico** al hex actual documentado en la exploración §2.2. El mapeo es una sustitución de referencia, no de valor.

Los dos mapeos (dark = ink-based, light = paper-based) son las **dos vistas semánticas** del mismo set de primitivos. Dark sigue siendo default e identidad de marca.

---

## 5. Capa 3 — Componente (`tokens/components/`)

### 5.1 Patrón: `static of(BuildContext)` que resuelve desde `AppPalette` + primitivos

Cada clase de tokens de componente es `abstract final` con métodos `static` que reciben `BuildContext`, leen `AppPalette.of(ctx)` (semántica, sensible a dark/light) y componen con primitivos (spacing/radios, invariantes al tema). **Nunca** hex crudo dentro de estas clases.

Se entregan **dos** componentes en Fase 0 (mínimo del proposal): `TreinoButtonTokens` y `TreinoCardTokens`. El resto (KpiCard, DataTable, ListRow, FilterChips, …) se agregan en sus Fases 1–12 siguiendo **exactamente este patrón** (regla de extensión, ADR-DS2-005).

```dart
// treino_card_tokens.dart
import 'package:flutter/widgets.dart';
import '../../app_palette.dart';
import '../radius_primitives.dart';
import '../spacing_primitives.dart';

/// Capa 3 — Tokens de la card TREINO. Resuelve color desde AppPalette
/// (dark/light) y forma desde primitivos. Cards SIN sombra (design-system).
abstract final class TreinoCardTokens {
  const TreinoCardTokens._();

  static Color background(BuildContext ctx) => AppPalette.of(ctx).bgCard;
  static Color border(BuildContext ctx) => AppPalette.of(ctx).border;
  static Color borderHover(BuildContext ctx) => AppPalette.of(ctx).borderHover;

  // Forma — invariante al tema.
  static const double radius = AppRadius.md;      // 16
  static const double borderWidth = 1;
  static const EdgeInsets padding = EdgeInsets.all(AppSpacing.s18); // 18
  // Sin sombra: la card no expone elevation ni BoxShadow (contraste = ink).
}
```

```dart
// treino_button_tokens.dart
import 'package:flutter/widgets.dart';
import '../../app_palette.dart';
import '../radius_primitives.dart';
import '../spacing_primitives.dart';

/// Capa 3 — Tokens del botón TREINO. Variantes: primary (accent), secondary
/// (surface + border), ghost (transparente). Pill por default (radius full).
abstract final class TreinoButtonTokens {
  const TreinoButtonTokens._();

  // Primary (CTA) — fondo accent, texto sobre accent = bg de la paleta.
  static Color primaryBackground(BuildContext ctx) => AppPalette.of(ctx).accent;
  static Color primaryForeground(BuildContext ctx) => AppPalette.of(ctx).bg;

  // Secondary — superficie + borde.
  static Color secondaryBackground(BuildContext ctx) => AppPalette.of(ctx).bgCard;
  static Color secondaryForeground(BuildContext ctx) => AppPalette.of(ctx).textPrimary;
  static Color secondaryBorder(BuildContext ctx) => AppPalette.of(ctx).border;

  // Ghost — sin fondo, texto muted → primary en hover (Fases 1–12 lo consumen).
  static Color ghostForeground(BuildContext ctx) => AppPalette.of(ctx).textPrimary;

  // Forma / spacing — invariante al tema.
  static const double radius = AppRadius.full; // pill
  static const EdgeInsets padding =
      EdgeInsets.symmetric(horizontal: AppSpacing.s20, vertical: AppSpacing.s12);
}
```

**Por qué `static` y no instancias**: los tokens de componente son *stateless lookups*; una instancia por `of(ctx)` no aporta nada y agrega allocation. Si en el futuro se necesita override por subtree (Opción B), estos `static X(ctx)` se convierten en `of(ctx).x` sin cambiar el call site (que ya usa `TreinoCardTokens.background(ctx)` o migrará trivialmente).

---

## 6. Motion — formalización (`motion_tokens.dart`)

`AppMotion` (valores runtime) **no cambia**. Se agrega una capa semántica de dominio de componente que da nombres intencionales sobre los escalones existentes. Esto responde al P3 del `animation-audit-2026-07-13.md` (tokens formales + sección Motion en docs) sin tocar duraciones/curvas.

```dart
import 'package:flutter/widgets.dart';
import '../app_motion.dart';

/// Capa Motion (semántica de componente) sobre AppMotion. NO redefine valores:
/// mapea intenciones de componente a los escalones de AppMotion. Respeta
/// reduceMotion a través de AppMotion.resolve.
abstract final class AppMotionTokens {
  const AppMotionTokens._();

  // Duraciones por intención de componente.
  static const Duration tapFeedback = AppMotion.micro;   // 120
  static const Duration cardStateChange = AppMotion.fast; // 180
  static const Duration contentEnter = AppMotion.base;    // 240
  static const Duration pageTransition = AppMotion.slow;  // 320

  // Curvas por intención.
  static const Curve enter = AppMotion.standard;
  static const Curve reposition = AppMotion.emphasized;
  static const Curve leave = AppMotion.exit;

  // Distancias de slide por intención.
  static const double rowSlide = AppMotion.slideSm;  // 8
  static const double cardSlide = AppMotion.slideMd; // 12
  static const double heroSlide = AppMotion.slideLg; // 20

  /// Puerta única de reduce-motion (delega en AppMotion).
  static Duration resolve(BuildContext ctx, Duration d) =>
      AppMotion.resolve(ctx, d);
  static Duration stagger(int index, {int maxItems = 8}) =>
      AppMotion.stagger(index, maxItems: maxItems);
}
```

**Invariante** (test §7.4): cada token de `AppMotionTokens` debe ser `identical`/igual al token de `AppMotion` que mapea. Es una capa de *nombres*, no de *valores*. Fases 1–12 pueden usar cualquiera de las dos superficies; `AppMotionTokens` es preferido en componentes nuevos por legibilidad de intención.

---

## 7. Estrategia de tests (TDD estricto — test antes de código)

Orden de implementación: **cada suite se escribe y falla ROJA antes de crear el archivo de producción que la satisface**. Suite de identidad primero (bloquea cualquier deriva visual).

| # | Suite (test file) | Qué fija | Debe fallar antes de |
|---|---|---|---|
| 1 | `test/app/theme/tokens/palette_identity_test.dart` | Cada campo de `mintMagenta`/`mintMagentaLight` conserva su ARGB actual | reescribir `app_palette.dart` |
| 2 | `test/app/theme/tokens/api_compat_test.dart` | `AppPalette.of/copyWith/lerp/mintMagenta/mintMagentaLight` compilan con firma idéntica | refactor de `app_palette.dart` |
| 3 | `test/app/theme/tokens/component_tokens_test.dart` | `TreinoButtonTokens`/`TreinoCardTokens` resuelven el color correcto en dark y en light | crear `components/` |
| 4 | `test/app/theme/tokens/motion_tokens_test.dart` | Cada `AppMotionTokens.x == AppMotion.y` (valores intactos) | crear `motion_tokens.dart` |
| 5 | `test/app/theme/tokens/no_hex_scan_test.dart` | Ningún archivo de `lib/` fuera de `tokens/` (salvo allowlist) contiene `Color(0x…)` | — (guard permanente) |

### 7.1 Identidad de paleta (suite 1) — el guard anti-deriva

```dart
// Congela los ARGB actuales. Fuente: exploración §2.2 + lectura directa del archivo.
const _expectedDark = {
  'accent': 0xFF2CE5A2, 'highlight': 0xFFC123E0, 'bg': 0xFF0A0A0A,
  'bgCard': 0xFF0F1513, 'border': 0x1AFFFFFF, 'borderHover': 0x33FFFFFF,
  'textPrimary': 0xFFFFFFFF, 'textMuted': 0x8CFFFFFF, 'sage': 0xFF4F6358,
  'espresso': 0xFF3C3534, 'danger': 0xFFE53935, 'warning': 0xFFFFB300,
  'onDanger': 0xFFFFFFFF, 'scrimDark': 0xFF000000,
};
// idem _expectedLight con los valores de mintMagentaLight.

test('mintMagenta conserva cada ARGB', () {
  final p = AppPalette.mintMagenta;
  expect(p.accent.value, _expectedDark['accent']);
  // … los 14 campos, dark y light.
});
```

Se congela contra `.value` (deprecado en Flutter recientes) o su equivalente `.toARGB32()` según versión de SDK — el test elige el disponible en el `pubspec` actual. Regla: **si esta suite pasa, la app se ve idéntica**.

### 7.2 API-compat (suite 2)

Test de compilación + smoke: instancia `AppPalette.mintMagenta.copyWith(accent: …)`, invoca `AppPalette.mintMagenta.lerp(AppPalette.mintMagentaLight, 0.5)`, y `AppPalette.of(tester context)` dentro de un `MaterialApp` con el theme real. Garantiza que los ~499 call sites siguen compilando (la firma no se movió).

### 7.3 Resolución de tokens de componente (suite 3) — widget test

```dart
testWidgets('TreinoCardTokens.background = bgCard en dark y light', (t) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light(), darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.dark,
    home: Builder(builder: (ctx) {
      expect(TreinoCardTokens.background(ctx).value,
             AppPalette.of(ctx).bgCard.value);
      return const SizedBox();
    }),
  ));
  // Repetir con ThemeMode.light para verificar sensibilidad al tema.
});
```

Verifica que la capa 3 **deriva** de la capa 2 (no duplica valores) y que responde a dark/light.

### 7.4 Motion + spacing (suite 4)

`expect(AppMotionTokens.tapFeedback, AppMotion.micro)` para cada token. Más un test que `AppSpacing` no expone valores fuera de `{8,12,14,18,20}` (vía reflexión sobre los `static const` declarados o lista explícita).

### 7.5 No-hex scanner (suite 5) — enforcement

Test de Dart puro (sin `flutter test` de widgets) que lee `lib/` recursivo y regexea `Color\(0x[0-9A-Fa-f]{6,8}\)`.

- **Excluye** `lib/app/theme/tokens/**` (donde los hex SON legítimos — es la capa primitiva).
- **Excluye** `lib/app/theme/app_palette.dart` **solo hasta** que su refactor termine; una vez migrado a primitivos, se saca de la allowlist y el propio `app_palette.dart` deja de tener hex (los tiene `color_primitives.dart`).
- **Allowlist explícita** de archivos legacy de `coach_hub/` y features aún no migradas (pendientes de Fases 1–12). Vive en el test como `const _allowlist = {...}` con un `// TODO(fase-N): remover al migrar`.

**Justificación de la allowlist** (ADR-DS2-008): un scanner sin allowlist marcaría los ~cientos de hex legacy y bloquearía el merge de Fase 0, que es puramente aditiva. La allowlist convierte el scanner en un **trinquete (ratchet)**: Fase 0 lo establece verde con la deuda conocida listada; cada Fase 1–12 **remueve entradas** al migrar, y el test **falla si alguien agrega un hex nuevo** en un archivo no listado. Nunca se puede agregar deuda, solo pagarla.

---

## 8. Barrel e import ergonomics

`tokens/tokens.dart` reexporta todo:

```dart
export 'color_primitives.dart';
export 'spacing_primitives.dart';
export 'radius_primitives.dart';
export 'type_primitives.dart';
export 'motion_tokens.dart';
export 'components/treino_button_tokens.dart';
export 'components/treino_card_tokens.dart';
```

Call sites nuevos: `import 'package:treino/app/theme/tokens/tokens.dart';` trae toda la superficie. `AppPalette` y `AppMotion` mantienen sus imports actuales (no se fuerza migración de imports existentes en Fase 0). El barrel es **aditivo**: no rompe ningún import previo.

---

## 9. Reescritura de `docs/design-system.md` (outline)

Documento nuevo, mismo espíritu (cognitive-doc-design: responde primero, disclosure progresivo). Outline:

1. **TL;DR / Cómo usar** — “color vía `AppPalette.of(ctx)` o tokens de componente; nunca hex; 3 capas”.
2. **Arquitectura de 3 capas** (NUEVO): diagrama primitive → semantic → component + cuándo usar cada capa (tabla de decisión).
3. **Capa 1 — Primitivos**: tablas de `AppColorPrimitives` (escala tonal con hex), `AppSpacing`, `AppRadius`, `AppType`. Nota: "los primitivos NO se usan en widgets".
4. **Capa 2 — Paleta semántica**: los **14 tokens** (agrega los faltantes `danger/warning/onDanger/borderHover/scrimDark`), con columna dark **y** light. Corrige "modo oscuro siempre" → **dark default + light pulido real** (existe `mintMagentaLight` + `ThemeModeNotifier`).
5. **Capa 3 — Tokens de componente**: `TreinoButtonTokens`, `TreinoCardTokens`, patrón `of(ctx)`, y "cómo agregar uno en tu Fase".
6. **Tipografía / Spacing / Radii**: sin cambio de contenido, re-anclado a los primitivos.
7. **Motion** (ampliado): tabla `AppMotion` + tabla `AppMotionTokens` (intención de componente) + reglas de reduce-motion.
8. **Reglas de código de UI**: no-hex (ahora con el scanner como guard), TreinoIcon, no strings hardcodeados.
9. **Eliminar**: sección Electric Violet (paleta descartada, sin código).

`docs/architecture.md`: corregir el comentario `electricViolet` → `mintMagentaLight` (una línea).

> **Gate de reviewer** (workflow.md:126): cambios en `docs/` requieren aprobación explícita. La reescritura se propone en la misma PR de Fase 0 pero se marca para review dedicado.

---

## 10. Lo que explícitamente NO cambia

| Área | Garantía |
|---|---|
| `app_theme.dart` | Comportamiento, factories `dark()`/`light()`, `TextTheme`, `InputDecorationTheme` — intactos. |
| `theme_mode_provider.dart` / `theme_watcher.dart` | Persistencia system/light/dark en SharedPreferences — sin tocar. |
| `app_background.dart` | Sin cambio. |
| `AppMotion` | Cada duración/curva/distancia runtime — idéntica. |
| API de `AppPalette` | `of`, `copyWith`, `lerp`, `mintMagenta`, `mintMagentaLight`, los 14 campos — firma idéntica. |
| Salida visual | Pixel-a-pixel idéntica (garantizado por suite de identidad §7.1). |
| Archivos del usuario | `.gitignore`, `android/app/build.gradle.kts`, `routine_editor/*` — NO tocar. |
| `treino-coach-hub` / `treino-ajustes` | Fuera de scope para siempre. |

**Zero visual change** es el criterio de éxito no-negociable de Fase 0.

---

## 11. Migración y rollback

- **Aditiva**: la fase agrega `tokens/**` y reescribe la *implementación* de `app_palette.dart`. No hay migración de call sites (la API no se movió).
- **build_runner**: **NO se corre** en esta fase — no se toca ningún `freezed`/`json_serializable`. Esto evita el conflicto conocido con los `routine_editor` no committeados (R-02).
- **Rollback**: revert del único commit que agrega `tokens/`, restaura `app_palette.dart` a hex inline y revierte los docs. Como no hay cambio de API ni visual, el revert es limpio y no deja call sites huérfanos.
- **Gate de merge**: `flutter analyze` 0 issues + `dart format .` + `flutter test` verde (con las 5 suites nuevas) + review de `docs/`.

---

## 12. Architecture Decision Records (ADR-DS2)

| ID | Decisión | Rationale | Alternativa rechazada |
|---|---|---|---|
| **ADR-DS2-001** | Adoptar Opción A: clases `const` para primitivos + tokens de componente `of(ctx)`. | Cero ruptura de API (499 call sites), const-friendly para spacing/radios, migrable a B sin tocar call sites. | B (ThemeExtension por componente): boilerplate alto sin necesidad de override por subtree. C (extension methods): no acomoda spacing/radios sin ctx. |
| **ADR-DS2-002** | Dividir primitivos en 4 archivos por familia en vez de un `primitives.dart` único. | Granularidad de import, test de identidad por familia, cambian por razones distintas; el barrel unifica el consumo. | Mega-archivo único (mencionado en explore): fuerza reimportar toda la escala tonal para usar solo spacing. |
| **ADR-DS2-003** | `app_palette.dart` se queda en su ruta; solo cambia su implementación interna. | Mover el archivo cambiaría los imports de ~499 call sites; es un `ThemeExtension` registrado en `AppTheme`. | Mover a `tokens/`: ruptura de imports masiva sin beneficio. |
| **ADR-DS2-004** | Escala tonal con sufijo `{familia}{peso}` (`mint500`, `ink950`) aun con un solo tono hoy. | Prepara Fases 1–12 (dataViz mint/teal, dots de estado) para derivar tonos sin re-hardcodear; convención estándar de design tokens. | Nombres planos (`mint`, `ink`): obligarían a renombrar al agregar tonos. |
| **ADR-DS2-005** | Solo `TreinoButtonTokens` + `TreinoCardTokens` en Fase 0; el resto se agrega en su Fase siguiendo el mismo patrón `of(ctx)`. | Mantiene Fase 0 acotada y aprobable; evita construir tokens de componentes cuyo diseño se define recién en su Fase. | Crear los 8 componentes ahora: diseño prematuro sin mockup consumidor; PR gigante. |
| **ADR-DS2-006** | `motion_tokens.dart` es capa semántica sobre `AppMotion`, sin cambiar valores runtime. | Responde al P3 del animation-audit (tokens formales + docs) sin riesgo de regresión de timing; `AppMotion` sigue siendo la fuente de verdad. | Redefinir valores en `AppMotionTokens`: duplicaría la verdad y arriesgaría deriva de timing. |
| **ADR-DS2-007** | `AppColors` se mantiene como alias `@Deprecated` a primitivos; no se borra en Fase 0. | Puede tener call sites externos; borrar es trabajo de una fase futura y ampliaría el diff. | Borrar ahora: potencial ruptura de call sites fuera del inventario. |
| **ADR-DS2-008** | No-hex scanner con **allowlist como trinquete**: Fase 0 lista la deuda legacy conocida; cada fase remueve entradas, nunca agrega. | Un scanner sin allowlist bloquearía el merge aditivo de Fase 0 por cientos de hex legacy; el ratchet permite converger sin frenar. | Scanner estricto sin allowlist (bloquea Fase 0) o sin scanner (permite regresión silenciosa de hex). |
| **ADR-DS2-009** | `AppType` expone solo familias/pesos como primitivos; los `TextStyle` siguen en `app_theme.dart`. | Evita duplicar la lógica de `GoogleFonts`; `app_theme.dart` sigue siendo el único builder de `TextTheme` (no cambia comportamiento). | Mover construcción de `TextStyle` a `type_primitives.dart`: duplicaría `GoogleFonts` y tocaría el comportamiento de tema. |

---

## 13. Listo para tasks: SÍ (junto con la spec)

Design entrega el HOW arquitectónico. `sdd-tasks` desglosará los pasos concretos (orden TDD: suite 1 → app_palette, suite 4 → motion_tokens, etc.). Ejecutar `sdd-tasks` una vez que la spec de Fase 0 también esté lista.

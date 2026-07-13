# Exploración: redesign-coach-hub-web

> **Cambio**: Rediseño completo del Trainer Web (coach_hub) + Design System v2
> **Fecha**: 2026-07-13
> **Fase**: explore
> **Rama**: refactor/theme-design-system-v2

---

## 1. Contexto y objetivo

El objetivo es doble y secuenciado:

**FASE 0 — Design System v2** (necesita aprobación del usuario antes de continuar):
Formalizar una arquitectura de tokens de 3 capas en Dart (primitivos → semánticos → componente), sin romper los ~499 call sites de `AppPalette.of(context)`. Incluye tokens de movimiento formales y reescritura de `docs/design-system.md`.

**FASES 1–12 — Coach Hub Web (una PR por fase)**:
Rediseño visual completo de cada sección del Trainer Web usando los tokens nuevos, los componentes compartidos a crear, y los mockups PNG como north star. Criterio de éxito: pantallas "vivas y fluidas", zero widgets duplicados, soporte pulido de dark y light mode.

El sistema de diseño actual **existe y funciona** pero está incompleto: primitivos hardcodeados en `AppPalette`, tokens semánticos sin mapeo explícito a primitivos, ausencia de capa de componente, y docs desactualizados en puntos críticos.

---

## 2. Estado actual del design system

### 2.1 AppColors — capa primitiva (informal, existente)

Archivo: `lib/app/theme/app_palette.dart`

Constantes actuales (6 colores hardcodeados):
| Nombre | Hex |
|--------|-----|
| `AppColors.ink` | `#0A0A0A` |
| `AppColors.espresso` | `#3C3534` |
| `AppColors.sage` | `#4F6358` |
| `AppColors.bone` | `#FFFFFF` |
| `AppColors.magenta` | `#C123E0` |
| `AppColors.mint` | `#2CE5A2` |

Esta clase existe pero **no es la capa primitiva formal**: no tiene nombres semántico-neutrales (ej. `mint500`), no tiene escala tonal, y no hay referencia explícita desde AppPalette a estos valores.

### 2.2 AppPalette — capa semántica (existente, ~200 call sites en 46 archivos de coach_hub)

14 tokens actuales:

| Token | Semántica | Nota |
|-------|-----------|------|
| `accent` | Acción primaria (mint) | CTA, tabs activos, navegación |
| `highlight` | Acento secundario (magenta) | Énfasis, avatares, highlight |
| `bg` | Fondo scaffold | |
| `bgCard` | Superficie / card | |
| `border` | Divisores sutiles | Alpha ~10% |
| `borderHover` | Borde hover (web only) | Alpha ~20%; Coach Hub web sidebar |
| `textPrimary` | Texto foreground | |
| `textMuted` | Texto deshabilitado / secundario | |
| `sage` | Cards secundarias | |
| `espresso` | Superficies elevadas / sheets | |
| `danger` | Error / rojo inline | |
| `warning` | Alerta amber | |
| `onDanger` | Texto/ícono sobre danger | ≥4.5:1 WCAG AA |
| `scrimDark` | Overlay negro puro | Opacidad aplicada en call site |

**API pública** (no debe romperse):
- `AppPalette.of(BuildContext context)` → 499 ocurrencias en 202 archivos
- `AppPalette.mintMagenta` → paleta dark (identidad de marca)
- `AppPalette.mintMagentaLight` → paleta light (ya implementada, REQ-LM/ADR-LM)
- `copyWith({...})` → override campo a campo
- `lerp(ThemeExtension? other, double t)` → interpolación para animación de tema

### 2.3 AppTheme — builder de ThemeData

Archivo: `lib/app/theme/app_theme.dart`

- `AppTheme.dark({AppPalette palette})` → ThemeData Brightness.dark
- `AppTheme.light({AppPalette palette})` → ThemeData Brightness.light
- Fuentes: Barlow + Barlow Condensed (headers 700, letterSpacing 0.5)
- Input theme: border 12px, contentPadding 18px
- Extensión registrada: `[palette]` en ThemeData.extensions

### 2.4 AppMotion — tokens de movimiento

Archivo: `lib/app/theme/app_motion.dart`

| Categoría | Tokens |
|-----------|--------|
| Duraciones | `micro` 120ms / `fast` 180ms / `base` 240ms / `slow` 320ms / `staggerStep` 40ms |
| Curvas | `standard` (easeOutCubic) / `emphasized` (easeInOutCubic) / `exit` (easeInCubic) |
| Distancias | `slideSm` 8px / `slideMd` 12px / `slideLg` 20px |
| Helpers | `reduceMotion(ctx)` / `resolve(ctx, duration)` / `stagger(index)` |

93 ocurrencias en 24 archivos. Adopción **desigual**: sólido en mobile, escaso en Coach Hub web.

### 2.5 Light mode — ya implementado (docs desactualizados)

`docs/design-system.md` afirma "modo oscuro siempre, no hay light theme". **Esto es incorrecto**: el código tiene `mintMagentaLight`, `AppTheme.light()`, y `ThemeModeNotifier` que persiste system/light/dark en SharedPreferences. El usuario explícitamente pidió soporte pulido dark Y light. Dark es la identidad y el default; light está completo pero sin diseño web polish.

### 2.6 Paleta Electric Violet — eliminada

`docs/design-system.md` tabla Electric Violet con accent `#34E062` y highlight `#7C3AED`. El código tiene **cero** implementación de esto. `app_palette.dart:6` dice explícitamente: "El producto usa una única paleta oficial: Mint Magenta (PDF de marca Mayo 2026)". Electric Violet se trata como eliminado salvo indicación explícita del usuario.

---

## 3. Inventario Coach Hub Web

### 3.1 Shell y layout

| Archivo | Líneas | Rol |
|---------|--------|-----|
| `coach_hub_scaffold.dart` | 56 | Root: `Row[Sidebar, Column[TopBar, ContentMaxWidth(child)]]` |
| `coach_hub_sidebar.dart` | 277 | Ancho 264↔72px, `AnimatedContainer` AppMotion.base, 3 grupos + Ajustes fijo abajo |
| `coach_hub_top_bar.dart` | 82 | 64px, campana inerte + menú usuario |
| `content_max_width.dart` | — | Limita a 1240px |
| `responsive.dart` | 33 | `viewportFor(width)` → mobile(<768) / compact(768–1279) / desktop(≥1280) |
| `sidebar_registry.dart` | 49 | Data-driven: lista de `SidebarItem` por grupo |
| `section_header.dart` | 28 | Barlow Condensed 700 UPPERCASE, reutilizado por todas las secciones |
| `proximamente_screen.dart` | 35 | Placeholder para las 7 secciones sin construir |

**Comportamiento responsive**:
- `< 768px`: `MobileBanner()` (no shell, placeholder)
- `768–1279px`: sidebar colapsado forzado (`collapsedOverride=true`), sin escribir provider
- `≥ 1280px`: sidebar respeta `sidebarCollapsedProvider` (SharedPreferences-backed)

### 3.2 Secciones implementadas

| Sección | Ruta | Archivos clave | Tamaño | Estado |
|---------|------|----------------|--------|--------|
| Dashboard | `/dashboard` | `coach_hub_dashboard_screen.dart` | 1202 L | W1 COMPLETO |
| Alumnos | `/alumnos`, `/alumnos/:id` | `alumnos_screen.dart` (657L) + `alumno_detail_screen.dart` (6054L) | GRANDE | W2 PARCIAL |
| Rutinas | `/rutinas` | `rutinas_screen.dart` (152L) | pequeño | W1 COMPLETO |
| Routine Editor | `/routine-editor/:athleteId[/:routineId]` | `routine_editor_web_screen.dart` | 1546 L | W1-W5 COMPLETO |
| Biblioteca | `/biblioteca` | `biblioteca_web_screen.dart` + 8 widgets (1149L total) | mediano | W5.3 COMPLETO |
| Pagos | `/pagos` | `pagos_web_screen.dart` (254L) + 8 widgets (1312L) | mediano | W4.2 PARCIAL |
| Agenda | `/agenda` | `agenda_web_screen.dart` (301L) + 6 dialogs (3382L) | GRANDE | W5.1+ PARCIAL |
| Chat | `/chat` | `chat_section_screen.dart` (55L) + 4 panes (1038L) | mediano | W2 PARCIAL |
| Ajustes | `/ajustes` | `ajustes_screen.dart` + 5 tabs | mediano | W3.1+ PARCIAL |

### 3.3 Secciones placeholder (7)

`ProximamenteScreen` en: Actividad, Invitaciones, Cuestionario, Hábitos, Nutrición, Recetas, Suplementos.

### 3.4 Estado del manejo de estado

- Riverpod 2 con `.when()` uniforme
- **Ningún uso de `TreinoStateSwitcher`** en coach_hub (58 `CircularProgressIndicator` crudos en 24 archivos)
- `userPublicProfilesBatchProvider` para evitar N+1 en alumnos y pagos
- Streams Firestore auto-cancelados por Riverpod (no hay `StreamSubscription` manual en coach_hub)

### 3.5 Censo de duplicación — candidatos a componentes compartidos

| Patrón duplicado | Archivos afectados | Componente propuesto |
|------------------|--------------------|----------------------|
| Data tables | `pagos_web_table.dart` (312L), tabla inline alumnos (~200L), tabs alumno_detail | `CoachHubDataTable` |
| KPI cards | `pagos_kpi_row.dart` (122L), dashboard KPI strip | `KpiCard` |
| List rows | `chat_list_pane.dart`, `agenda_web_day_list.dart`, alumno roster row | `ListRow` |
| Filter chips | `biblioteca_filter_chips.dart` (218L), alumnos estado chips | `FilterChipGroup` |
| Section headers | `section_header.dart` (28L) — ya existe, necesita extensión con subtitle + actions | `SectionHeader` extendido |
| Empty states | pagos_web_table, chat_empty_pane, varios "No data" text | `EmptyState` |
| Form dialogs | 6 en agenda, 1 en exercise picker, 1 en pagos = 9+ superficies | `FormDialog` base |
| Grid cards | `exercise_grid_card.dart` (216L), `template_grid_card.dart` (131L) | `GridCard` |
| Search input | `ejercicios_tab.dart` search field, buscador alumnos | `SearchInput` |
| Status badges | `AlumnoEstado` enum + color (~36L), pagos status, agenda status | `StatusBadge` |

**Violaciones de spacing** (EdgeInsets 16/24 en lugar de la escala 8/12/14/18/20):
27 archivos del módulo coach_hub están afectados, incluyendo `routine_editor_web_screen`, `rutinas_screen`, pantallas de alumnos, dashboard, biblioteca, agenda dialogs, pagos, ajustes tabs, chat panes.

---

## 4. Lenguaje visual de los mockups

### 4.1 Síntesis por pantalla

| Pantalla | Paleta dominante | Componentes clave | Densidad |
|----------|-----------------|-------------------|----------|
| Dashboard | Mint como acción/métrica principal, magenta secundario | Hero banner asimétrico, KPI grid 4–5 col, mini line charts mint, progress ring, alert banner | Media-alta |
| Alumnos (tabla) | Avatares coloreados (mint/magenta/azul/naranja/púrpura), dots verde/amarillo/rojo | Filtro chips, tabla horizontal scrollable, status pills, buscador | Alta |
| Alumnos (cards) | Avatares grandes coloreados, % adherencia mint | Grid 4 col, card con dot de estado, datos secundarios en gris | Media |
| Alumno detalle | Magenta para avatar, mint para métricas y tabs activos | 10 tabs, KPI strip 4 métricas, line chart, timeline, heatmap semanal | Media |
| Solicitudes | Avatares de solicitante coloridos, mint para CTAs | Lista de cards con estado chip (PENDIENTE/RESUELTOS), panel de detalle 3 columnas | Media |
| Rutinas | Magenta/cyan/verde/naranja para grupos musculares (pills) | Breadcrumb, ejercicios como filas expandibles, sidebar de músculos | Alta |
| Sidebar | Near-black base, mint íconos/texto activo | Logo, nav items con íconos TreinoIcon, sección inferior con avatar de trainer | Compacta |
| Biblioteca — Ejercicios | Cards con fondos de color (verde oscuro, teal, navy, púrpura), mint badge count | Grid 4 col, search input, filter chips de categoría | Media |
| Biblioteca — Templates | Ícono de color grande, título UPPERCASE, metadatos, CTA mint | Grid 3 col, variantes nutrición y rutinas idénticas en estructura | Media |
| Chat | Split pane: lista 350px + thread 600px | Avatares coloreados, bubbles mint (trainer), timestamp, input inferior | Media |
| Nutrición | Dos paneles: lista alimentos + breakdown macros | Sliders de objetivos, pie chart mint/naranja/magenta, progress bars por macro | Media |
| Pagos | KPI strip 4 cards + tabla completa | 6 columnas, row actions (marcar/recordar), filtros por estado | Alta |
| Perfil público | Gradient header magenta→oscuro | Avatar large, tag pills, rating/reviews, toggle switch edición | Media |
| Planes comerciales | Cards con borde outline, sin fill (o fill muy oscuro) | Grid 3 col, badge tipo plan, price en mint grande, checklist features | Media |
| Ajustes | Tabbed (Cuenta/Notificaciones/Facturación) | Avatar con badge status, toggles mint on/gris off, tabla historial | Media-baja |

### 4.2 Lenguaje visual global

**Base cromática**: `#0A0A0A` a `#1A1A1A` (ink), sin light mode en los mockups (preexisten a la implementación del tema claro en código).

**Jerarquía de acentos**:
1. Mint `#2CE5A2` — CTAs, estados activos, métricas clave, navegación activa
2. Magenta `#C123E0` — avatares "femeninos"/diversidad, headers de perfil, énfasis secundario
3. Teal/Cyan — charts, dataViz secundaria
4. Naranja — labels de intensidad/energía, warnings secundarios
5. Rojo — inactivos, errores, estados urgentes
6. Amarillo — pausados, alertas medias

**Tipografía**: Barlow Condensed 700 UPPERCASE para headers y títulos de sección; Barlow 400/600/700 para cuerpo. Todo CAPS en etiquetas, botones, tabs, headers de tabla.

**Spacing observado**: 8/12/14/16/18/20px. Nota: los mockups usan 16px donde la escala del sistema dice evitar ese valor como spacing "standard" de componente (sí admitido en algunos contexts). Las cards tienen 16–20px de padding interno; rows ~40–48px de altura; gaps entre cards 12–16px.

**Bordes y radios**: Cards 12px, componentes grandes 16px, botones pill 24–32px, avatares circle (full). Sin sombras en dark theme. Borde sutil 1px ~`#2A2A2A`.

**Movimiento implícito**: Hover en cards (lighten/scale sutil), tab underline que desliza, expansión de filas (chevron), transiciones de chart (smooth curve). Todo dentro de rangos `AppMotion.fast`/`AppMotion.base`.

**Qué da vida y color**: Avatares coloreados por alumno, sistema de acento mint, dataViz con fills mint/teal, dots de estado, tipografía CAPS de alto contraste.

---

## 5. Restricciones vigentes

### 5.1 API pública irrompible
`AppPalette.of(context)` tiene 499 call sites en 202 archivos. Cualquier refactor de la capa semántica **no debe cambiar esta firma ni los nombres de los 14 tokens**. Los tokens nuevos de componente son **adicionales**, nunca reemplazos.

### 5.2 Paleta única
Mint Magenta es la única paleta oficial (PDF marca Mayo 2026). Electric Violet descartada. No implementar variantes de paleta salvo indicación explícita.

### 5.3 Escala de spacing
Solo 8/12/14/18/20px. Los 27 archivos de coach_hub con EdgeInsets de 16/24 son **violaciones** a corregir en cada fase correspondiente.

### 5.4 Íconos y colores
- `TreinoIcon.X` siempre, `PhosphorIcons.*` nunca directamente en widgets
- `AppPalette.of(context)` siempre, nunca hex literals en widgets
- `AppMotion` tokens siempre, nunca `Duration`/`Curve` hardcodeados

### 5.5 Riverpod 2
`select()`, constructores `const`, provider del tamaño mínimo. Streams Firestore cancelados en dispose. No hay providers de override de tema por feature.

### 5.6 Sin Scaffold por sección
El shell provee el `Scaffold`. Las secciones no deben incluir `Scaffold` propio (ADR-CHW-005).

### 5.7 Sin BackdropFilter sin profiling
`BackdropFilter` es "muy costoso — reservar para edge cases" (docs/performance.md:28). La sidebar actual ya eliminó `BackdropFilter` (dropped 2026-06-11 por dropped frames). Cualquier uso nuevo requiere profiling explícito.

### 5.8 Reduce-motion obligatorio
`AppMotion.reduceMotion(context)` y `AppMotion.resolve(context, duration)` deben respetarse en todo widget de animación.

### 5.9 `TreinoFadeSlideIn` prohibido en lazy builders
No usar en `ListView.builder` — los items reciclados re-animarían al hacer scroll. Solo en secciones eager.

### 5.10 `TreinoStateSwitcher` requiere keys distintas
El caller debe diferenciar estados con `ValueKey('loading')` vs `ValueKey('data')`.

### 5.11 Cambios a docs/
Toda modificación de archivos en `docs/`, `AGENTS.md`, `CONTRIBUTING.md` o specs SDD requiere aprobación explícita del reviewer sobre las reglas en sí, además del código (workflow.md:126).

### 5.12 Fuera de scope permanente
Ranking, Retos, Missions, Bets, Levels/XP, Gamification.

### 5.13 Archivos con cambios no committeados (no tocar)
`.gitignore`, `android/app/build.gradle.kts`, archivos de `routine_editor` y sus tests.

### 5.14 TDD estricto
Test antes de código en fase `sdd-apply`. Runner: `flutter test`. Quality gates: `flutter analyze` 0 issues + `dart format .` + `flutter test` + `build_runner` si se toca freezed.

### 5.15 Mockups como north star con tolerancia de tokens
Si un mockup y el design system difieren en un token, **gana el design system**. Los mockups son guía de composición y feeling, no de tokens exactos.

---

## 6. Docs desactualizados a corregir

| Documento | Sección afectada | Problema | Acción en Fase 0 |
|-----------|-----------------|----------|-------------------|
| `docs/design-system.md` | "Modo oscuro siempre" | Light mode existe y está implementado | Reescribir sección Temas |
| `docs/design-system.md` | Paletas — Electric Violet | Eliminada del código | Remover tabla EV; mantener solo Mint Magenta |
| `docs/design-system.md` | Tokens de paleta (lista de 10) | Faltan danger, warning, onDanger, borderHover, scrimDark | Agregar 5 tokens faltantes |
| `docs/design-system.md` | Sin sección de Motion | P3 del animation-audit-2026-07-13 | Agregar sección Motion con tokens de AppMotion |
| `docs/design-system.md` | Sin sección de capa de componente | No existe | Agregar sección tokens de componente |
| `docs/architecture.md` | `app_palette.dart` comentado con `electricViolet` | Incorrecto: solo existe mintMagenta + mintMagentaLight | Corregir comentario |

---

## 7. Riesgos

| ID | Riesgo | Probabilidad | Impacto | Mitigación |
|----|--------|-------------|---------|------------|
| R-01 | Ruptura de `AppPalette.of(context)` en los 499 call sites durante refactor | Media | Crítico | Mantener API pública exacta; solo agregar tokens nuevos, nunca renombrar existentes; `flutter analyze` como gate |
| R-02 | `build_runner` genera archivos `.freezed.dart`/`.g.dart` que entran en conflicto con cambios de user en routine_editor | Alta | Alto | No tocar archivos de routine_editor marcados con cambios sin commitear; gate explícito en task checklist |
| R-03 | Adopción de `TreinoStateSwitcher` rompe layout en secciones de altura variable | Media | Medio | `TreinoStateSwitcher` usa `Alignment.topCenter`; probar en pantallas con loading→data de altura diferente antes de commit |
| R-04 | Spacing violations (27 archivos con 16/24px) generan PR demasiado grande si se corrigen todos a la vez | Alta | Medio | Corregir en cada fase correspondiente (Fase 1 shell, Fase 2 dashboard, etc.) — nunca en PR de Design System v2 |
| R-05 | Light mode en web sin diseño polish — mockups son dark-only | Alta | Medio | Fase 0 define tokens duales; el polish visual de light en web se hace en cada fase (1–12) como variante, no como pantalla separada |
| R-06 | `alumno_detail_screen.dart` tiene 6054 líneas — refactor es una PR extremadamente grande | Alta | Alto | Dividir en sub-tareas por tab; delivery strategy auto-chain; cada tab como work-unit commit |
| R-07 | Agenda dialogs suman 3382 líneas — 6 archivos complejos | Media | Medio | Componentizar `FormDialog` base primero (Fase 1), luego reusar en Fase 4 (Agenda) |
| R-08 | Docs de design-system requieren aprobación explícita del reviewer sobre las reglas (workflow.md:126) — puede bloquear merge | Media | Bajo | Incluir nota en PR body pidiendo aprobación explícita de la sección de reglas |
| R-09 | `AppBackground` usa radial gradient con colores hardcoded internamente | Baja | Bajo | Verificar que usa `AppPalette.of(context)` — si no, corregir en Fase 0 |
| R-10 | Tokens de componente (capa 3) podrían volverse difíciles de mantener si no se documentan bien | Media | Medio | Definir convenio de naming desde Fase 0; doc inline con `///` comentarios en cada `*Tokens` class |

---

## 8. Enfoques posibles para la arquitectura de tokens de 3 capas en Dart

### Contexto del problema

Necesitamos:
1. **Primitivos**: valores brutos (`mint500 = Color(0xFF2CE5A2)`, `spacing8 = 8.0`, etc.) — sin semántica, sin BuildContext
2. **Semánticos**: `AppPalette` ya existe como ThemeExtension — mantener intacto
3. **Componente**: tokens por componente (`TreinoButtonTokens`, `TreinoCardTokens`, etc.) que referencian semánticos

La restricción dura: `AppPalette.of(context)` no puede cambiar de firma.

---

### Opción A — Clases estáticas const para primitivos + AppPalette semántico formalizado + component tokens como clases estáticas derivadas de BuildContext

**Descripción**:
- Capa 1: `lib/app/theme/tokens/primitives.dart` — clases estáticas con `static const Color mint500`, `static const double spacing8`, etc.
- Capa 2: `AppPalette` se reescribe internamente para referenciar `Primitives.mint500` en lugar de literals, pero la API pública no cambia en absoluto
- Capa 3: `lib/app/theme/tokens/components/` — clases (`TreinoButtonTokens`, `TreinoCardTokens`, etc.) con factory `of(BuildContext context)` que llaman `AppPalette.of(ctx)` internamente

```dart
// Capa 1 - sin BuildContext
abstract final class AppColorPrimitives {
  static const mint500 = Color(0xFF2CE5A2);
  static const magenta500 = Color(0xFFC123E0);
  static const ink950 = Color(0xFF0A0A0A);
  // ...
}

// Capa 3 - con BuildContext
abstract final class TreinoButtonTokens {
  static Color background(BuildContext ctx) => AppPalette.of(ctx).accent;
  static Color foreground(BuildContext ctx) => AppPalette.of(ctx).bg;
  static double radius = 20.0; // constante, sin ctx
}
```

| Pros | Contras |
|------|---------|
| Zero ruptura de AppPalette API | Tokens de componente con `ctx` no son constantes en compile-time |
| Fácil de entender y razonar | Acoplamiento implícito capa 3 → capa 2 (sin contrato tipado) |
| Primitivos disponibles sin BuildContext (útil en tests) | No hay ThemeExtension por componente → no hay lerp() ni override |
| Consistente con el patrón actual del codebase | Múltiples clases estáticas = namespace disperso si crecen mucho |
| Menor esfuerzo de migración | Component tokens no son inyectables (dificulta theming por feature si algún día se necesita) |

**Esfuerzo**: Bajo-Medio

---

### Opción B — ThemeExtension por componente registrada en AppTheme

**Descripción**:
- Capa 1: igual que Opción A (`AppColorPrimitives`)
- Capa 2: `AppPalette` igual (no rompe)
- Capa 3: Cada set de tokens de componente es un `ThemeExtension<T>`, registrado en `AppTheme.dark()/light()` vía `extensions: [...]`; se accede con `Theme.of(ctx).extension<TreinoButtonTokens>()!`

```dart
class TreinoButtonTokens extends ThemeExtension<TreinoButtonTokens> {
  final Color background;
  final Color foreground;
  const TreinoButtonTokens({required this.background, required this.foreground});
  // copyWith, lerp obligatorios
  static TreinoButtonTokens of(BuildContext ctx) =>
      Theme.of(ctx).extension<TreinoButtonTokens>()!;
}
```

| Pros | Contras |
|------|---------|
| Integración nativa con Flutter theming (lerp, override por subtree) | Boilerplate alto: `copyWith` + `lerp` por cada `ThemeExtension` |
| Permite override por subtree (Portal/Dialog con tema diferente) | Registro manual en `AppTheme.dark()/light()` — fácil de olvidar al agregar tokens |
| Patrón familiar para quien ya conoce AppPalette | `Theme.of(ctx).extension<T>()!` es verbose en call sites |
| Tokens lerpeables → animaciones de tema sin glitches | Más archivos a mantener |
| Tests pueden inyectar ThemeData con tokens mock | Overhead innecesario si nunca se necesita override por subtree |

**Esfuerzo**: Alto

---

### Opción C — Clases estáticas de primitivos + AppPalette semántico + component tokens como extension methods sobre AppPalette

**Descripción**:
- Capa 1: igual (AppColorPrimitives const)
- Capa 2: AppPalette igual
- Capa 3: extension methods de Dart sobre `AppPalette` que agregan getters semánticos de componente, opcionalmente en archivos separados por componente

```dart
// lib/app/theme/tokens/components/button_tokens.dart
extension TreinoButtonTokensX on AppPalette {
  Color get buttonBackground => accent;
  Color get buttonForeground => bg;
  double get buttonRadius => 20.0;
}

// En el widget:
final palette = AppPalette.of(context);
color: palette.buttonBackground,
```

| Pros | Contras |
|------|---------|
| Zero boilerplate (sin copyWith/lerp) | Extensions no son testeables en forma aislada sin crear AppPalette |
| `AppPalette.of(ctx).buttonBackground` — fluido y autodiscoverable | Risk de namespace pollution si hay muchos componentes |
| No requiere BuildContext extra — sigue el patrón `palette = AppPalette.of(ctx)` | Las constantes de spacing/radius no encajan naturalmente en extension sobre AppPalette |
| Separación en archivos sin romper API central | No hay lerp() de tokens de componente (pero rara vez se necesita) |
| Menor esfuerzo de migración que Opción B | |

**Esfuerzo**: Bajo

---

### Tabla comparativa de enfoques

| Criterio | Opción A (estáticas + ctx) | Opción B (ThemeExtension) | Opción C (extension methods) |
|----------|--------------------------|--------------------------|------------------------------|
| Ruptura de API | Ninguna | Ninguna | Ninguna |
| Boilerplate | Bajo | Alto | Muy bajo |
| Testabilidad | Buena (primitivos sin ctx) | Excelente (ThemeData inyectable) | Aceptable |
| Lerp de tokens de componente | No | Sí | No |
| Override por subtree | No | Sí | No |
| Autodiscoverability en IDE | Medio (clases separadas) | Medio (extension<T>()) | Alto (`.` sobre palette) |
| Consistencia con codebase actual | Alta | Media | Muy alta |
| Esfuerzo total | Bajo-Medio | Alto | Bajo |

---

### Recomendación

**Opción A con naming mejorado**, como paso conservador para Fase 0:

1. Crear `lib/app/theme/tokens/primitives.dart` con `AppColorPrimitives` (const, sin BuildContext)
2. Crear `lib/app/theme/tokens/spacing.dart` con `AppSpacing` (const doubles: s8, s12, s14, s18, s20)
3. Crear `lib/app/theme/tokens/radius.dart` con `AppRadius` (const doubles: sm=12, md=16, lg=20, full=9999)
4. Crear `lib/app/theme/tokens/motion.dart` — reexport semántico de `AppMotion` con nombres de componente (`AppMotionTokens.cardEntry = AppMotion.base`, etc.) — el artefacto del P3 del animation audit
5. Crear `lib/app/theme/tokens/components/` con clases `TreinoButtonTokens.of(ctx)`, `TreinoCardTokens.of(ctx)`, etc. — thin wrappers sobre `AppPalette.of(ctx)` con nombres de dominio de componente
6. **No tocar** `AppPalette` internamente (postergar la formalización de referencias primitivo en semántico para una PR de refactor menor, sin riesgo funcional)

**Por qué no Opción B**: La Opción B agrega boilerplate significativo (copyWith + lerp por cada ThemeExtension de componente) y requiere registro manual en AppTheme por cada nueva clase. Para este proyecto con palette única y sin necesidad de override por subtree en producción, el costo no justifica el beneficio.

**Por qué no Opción C pura**: Las extension methods son excelentes para tokens de color de componente, pero no para spacing/radius/motion que son constantes sin `BuildContext`. La Opción A combina lo mejor: primitivos const sin ctx + component tokens con ctx vía factory `of()`.

**Migración hacia Opción B opcional**: Si en el futuro el producto necesita theming por subtree (ej. un portal con paleta diferente), la Opción A es migrable a Opción B sin cambiar call sites, porque ambas usan `TreinoButtonTokens.of(ctx)` como punto de acceso.

---

## 9. Áreas afectadas y archivos clave

```
lib/app/theme/
├── app_palette.dart          → agregar referencia a primitivos internamente (opcional, no rompe)
├── app_motion.dart           → sin cambio (fuente de verdad)
├── app_theme.dart            → registrar nuevos ThemeExtensions si se elige Opción B
└── tokens/                   → NUEVO
    ├── primitives.dart        → AppColorPrimitives, AppSpacing, AppRadius
    ├── motion_tokens.dart     → AppMotionTokens (semántico sobre AppMotion)
    └── components/            → NUEVO
        ├── button_tokens.dart → TreinoButtonTokens
        ├── card_tokens.dart   → TreinoCardTokens
        ├── input_tokens.dart  → TreinoInputTokens
        ├── table_tokens.dart  → CoachHubDataTableTokens
        ├── kpi_tokens.dart    → KpiCardTokens
        └── badge_tokens.dart  → StatusBadgeTokens

docs/design-system.md         → reescritura completa (3 capas + Motion + light mode)
docs/architecture.md          → corrección de comentario electricViolet

lib/features/coach_hub/presentation/
├── shell/                    → Fase 1: polish shell, spacing, motion
├── widgets/                  → componentes compartidos nuevos (CoachHubDataTable, KpiCard, etc.)
└── sections/                 → Fases 2–12: cada sección
```

---

## 10. Listo para propuesta

**Sí.** La exploración revela un sistema existente sólido con APIs estables y riesgos bien caracterizados. La Fase 0 (Design System v2) tiene un scope claro y un enfoque recomendado. Las Fases 1–12 tienen inventario completo, censo de duplicación, y mockups como referencia visual.

El próximo paso es `sdd-propose`: definir el scope exacto de Fase 0, la lista definitiva de primitivos a crear, los componentes compartidos de Fases 1–12, y el plan de entrega por PR.

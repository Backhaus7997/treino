# Diseño Técnico — FASE 1: Shell Coach Hub Web + Kit de Componentes Base

> Cambio: redesign-coach-hub-web · Fase: 1 · Rama: refactor/coach-hub-shell-redesign · Store: hybrid
> Lee: proposal (#203), Fase 0 design (tokens 3 capas + motion). Diseñado contra el código real.

## Enfoque técnico

Fase 1 extiende el patrón Fase 0 (primitive→semantic→**component**) para bajar el shell a los mockups y sembrar el kit reutilizado por fases 2–12. Dos pilares:

1. **Capa de componente nueva** (`lib/app/theme/tokens/components/`): 7 clases de tokens `abstract final` con `static T method(BuildContext)` que leen `AppPalette.of(ctx)` + `AppRadius`/`AppSpacing` — cero hex, mismo molde que `TreinoCardTokens`/`TreinoButtonTokens`.
2. **Kit de widgets** en `lib/features/coach_hub/presentation/widgets/` (coach-hub-only), pilotado por un **único resolver de estado web** (`TreinoInteractiveState`) que centraliza hover/pressed/focus/disabled — 1 implementación, no 7.

Regla anti-duplicación: un componente entra en Fase 1 si tiene consumidor real en el shell **o** ships como fundación con preview+test y fase consumidora documentada. Tokens de design-system ganan sobre conflictos de token del mockup.

## Decisiones de arquitectura (ADR-SH-xxx)

### ADR-SH-001 — Ubicación del kit: `features/coach_hub/presentation/widgets/`
| Opción | Tradeoff | Decisión |
|---|---|---|
| A. `features/coach_hub/presentation/widgets/` | Acoplado a coach_hub; refactor a core si móvil lo pide | **Elegida** |
| B. `lib/core/widgets/` (app-wide) | Reuso global, pero móvil NO consume tablas/kpi/filterchips web | Rechazada |
| C. Split por componente | Fragmenta; predice reuso móvil inexistente | Rechazada |
**Rationale**: los 7 (DataTable, KpiCard, ListRow, FilterChips, SectionHeader, EmptyState, Dialog) son consumidos SOLO por el web trainer. `core/widgets/motion/` ya aloja lo verdaderamente app-wide (Tappable, StateSwitcher). Excepción: `SectionHeader` ya existe en `shell/section_header.dart` — se **reubica/renombra** a `widgets/section_header.dart` como componente tokenizado (el shell lo importa desde ahí). Promoción a `core/` es un revert-friendly move-file futuro sin cambio de API.

### ADR-SH-002 — Resolver de estado web único: `TreinoInteractiveState`
| Opción | Tradeoff | Decisión |
|---|---|---|
| A. Wrapper builder `TreinoInteractiveState` (MouseRegion+FocusableActionDetector, expone `TreinoStates` a un `builder`) | 1 impl, testeable aislada | **Elegida** |
| B. Copiar hover/focus en cada widget | 7 copias, drift garantizado | Rechazada |
| C. Material `WidgetStateController`/`InkWell` | Ripple Material choca con estética Hevy; no da pressedScale del sistema | Rechazada |
**Contrato**:
```dart
class TreinoStates { final bool hovered, pressed, focused, disabled; }
// builder-based: NO pinta, resuelve estado y delega el look a tokens.
TreinoInteractiveState({
  VoidCallback? onTap,          // null => disabled
  bool enableFeedback = true,   // false para rows no-interactivas
  required Widget Function(BuildContext, TreinoStates) builder,
});
```
Composición interna: `MouseRegion` (hover) → `FocusableActionDetector` (focus + Enter/Space) → `TreinoTappable` (pressed scale 0.97, ya reduce-motion-safe). `onTap==null` ⇒ `disabled=true`, sin gesture (respeta el gate de `TreinoTappable`). El focus ring lo pinta el consumidor con `TreinoFocusTokens.ring(ctx)` (accent a alpha) — no lo dibuja el resolver. **Cada token de componente expone variantes por estado** (ej. `TreinoListRowTokens.background(ctx, states)`).

### ADR-SH-003 — Tokens de componente (7 clases nuevas)
Naming `Treino{X}Tokens`, campos por `static method(BuildContext[, TreinoStates])`:
| Clase | Campos clave |
|---|---|
| `TreinoTableTokens` | `headerBg/rowBg(ctx,states)`, `divider(ctx)`, `rowHeight=48`, `radius=AppRadius.md` |
| `TreinoKpiCardTokens` | `background/border(ctx)`, `accentText(ctx)`, `pad=AppSpacing.s20`, `radius=AppRadius.md` |
| `TreinoListRowTokens` | `background(ctx,states)`, `borderHover`, `pad h14/v12`, `radius=AppRadius.sm` |
| `TreinoChipTokens` | `bg/fg(ctx,selected,states)`, `pad h12/v8`, `radius=AppRadius.sm` |
| `TreinoSectionHeaderTokens` | `titleStyle(ctx)` (Barlow Condensed 700 UPPERCASE), `muted(ctx)` |
| `TreinoEmptyStateTokens` | `iconColor/textColor(ctx)`, `gap=AppSpacing.s12` |
| `TreinoDialogTokens` | `surface(ctx)`, `scrim(ctx)`, `radius=AppRadius.md`, `maxWidth=480` |
Compartidos: `TreinoFocusTokens.ring(ctx)`, `TreinoBadgeTokens` (magenta `highlight`, `radius=full`). Todos van al barrel `tokens.dart`. **Conflicto mockup↔system**: mockup sugiere 240px sidebar / radios varios → se fuerza a la escala (`8·12·14·18·20`, radios `12/16/20/full`); sidebar queda en el valor actual del shell salvo que el mockup pida un múltiplo válido.

### ADR-SH-004 — Anatomía del shell: pill activa animada, badges, footer
| Aspecto | Decisión |
|---|---|
| Item activo | **Pill** (fondo `bgCard` + texto `accent` 600) con `AnimatedContainer(cardStateChange, enter)`; el "left-bar" del mockup se implementa como borde-izq accent dentro de la pill (evita segundo widget) |
| Hover | `TreinoInteractiveState` → borde `border→borderHover` animado (`tapFeedback`) |
| Badges | `TreinoBadgeTokens` magenta en Pagos/Chat vía `SidebarItem.badgeProvider` (Riverpod, `select()`); null-safe (W1 dejaba null) |
| Footer | Perfil de usuario (avatar + nombre + subtítulo) + Ajustes pinned; reusa `userProfileProvider` |
| Collapse | `AnimatedContainer` 264↔72 (`contentEnter`, `emphasized`) + `Clip.hardEdge` (ya existe); labels con `AnimatedOpacity` |
| Toggle | Se mantiene en header del primer grupo (ADR-CHW-003 intacto: compact no escribe provider) |

### ADR-SH-005 — Theme toggle en topbar (light+dark first-class)
**Elegida**: exponer toggle light/dark en el **menú de cuenta** del topbar (el mockup implica dropdown de cuenta). Escribe `themeModeProvider` (ya persiste `app.theme_mode`). Rechazado: toggle suelto en la barra (ruido visual, no está en mockup). Ambos temas son ciudadanos de primera: cada token resuelve por `AppPalette.of(ctx)`, tests smoke corren en dark **y** light.

### ADR-SH-006 — Sistema de previews (primera introducción)
El proyecto NO tiene `@Preview` aún. Se adopta `package:flutter/widget_previews.dart` (SKILL flutter-add-widget-preview). Convención: cada componente del kit expone un preview co-ubicado `*_preview.dart` con `@MultiPreview` dark+light por matriz de estados. Sin app real de preview separada — anotaciones sobre funciones top-level parameter-less. Es aditivo y no afecta runtime.

## Flujo de datos
```
AppPalette.of(ctx) ─┐
AppRadius/Spacing ──┼─→ Treino{X}Tokens.method(ctx, states) ─→ Widget del kit
TreinoInteractiveState (hover/pressed/focus/disabled) ──────┘         │
badgeProvider (Riverpod .select) ──────────────────────────→ Sidebar item ─→ Shell
themeModeProvider ─────────────────────────────────────────→ Topbar account menu
```

## Coreografía de motion (estándar Emil Kowalski)
| Momento | Técnica | Juicio |
|---|---|---|
| Entrada shell | `TreinoFadeSlideIn` staggered en partes eager (grupos sidebar, topbar) `stagger(index)` | Propósito, <400ms, NO en ListView.builder |
| Selección item | `AnimatedContainer(cardStateChange, enter)` de pill | Rápido, interrumpible |
| Hover/focus | `AnimatedContainer/Opacity(tapFeedback)` | Sutil, sin loop |
| Collapse | `AnimatedContainer(contentEnter, emphasized)` | Suave, reduce-motion → `resolve`=0 |
| Async (avatar/badges) | `TreinoStateSwitcher` en `.when`; skeleton `TreinoShimmer` | Sin spinner crudo |
Todo pasa por `AppMotion.resolve` / `AppMotionTokens` (cero Duration/Curve cruda). Cero loops decorativos.

## Cambios de archivos
| Archivo | Acción | Detalle |
|---|---|---|
| `lib/app/theme/tokens/components/treino_{table,kpi_card,list_row,chip,section_header,empty_state,dialog,badge,focus}_tokens.dart` | Create | 9 clases de tokens |
| `lib/app/theme/tokens/tokens.dart` | Modify | exports nuevos |
| `lib/features/coach_hub/presentation/widgets/treino_interactive_state.dart` | Create | resolver único |
| `lib/features/coach_hub/presentation/widgets/{coach_hub_data_table,kpi_card,list_row,filter_chips,section_header,empty_state,coach_hub_dialog}.dart` | Create | kit (7) |
| `lib/features/coach_hub/presentation/widgets/*_preview.dart` | Create | previews dark+light |
| `lib/features/coach_hub/presentation/shell/coach_hub_sidebar.dart` | Modify | pill animada, badges, footer perfil |
| `lib/features/coach_hub/presentation/shell/coach_hub_top_bar.dart` | Modify | account menu + theme toggle |
| `lib/features/coach_hub/presentation/shell/coach_hub_scaffold.dart` | Modify | entrada staggered |
| `lib/features/coach_hub/presentation/shell/mobile_banner.dart` | Modify | fix spacing 24→20 |
| `lib/features/coach_hub/presentation/shell/section_header.dart` | Delete | reubicado a widgets/ tokenizado |

## Estrategia de testing (TDD estricto — test-first)
| Capa | Qué | Cómo |
|---|---|---|
| Widget/estado | Matriz por componente: normal/hover/pressed/disabled/focus/loading/empty/error (donde aplique) | pump + `TestPointer`/`WidgetTester` gestures + Focus |
| Tokens | Cada método resuelve color sin hex; dark≠light donde corresponde | pump en ambos temas |
| Reduce-motion | Con `disableAnimations` no hay AnimatedScale/delay; snap final | `MediaQuery(disableAnimations:true)` |
| Ambos temas | Smoke render dark+light por componente y shell | `@MultiPreview` + test twin |
| Shell (update) | Actualizar los 6 tests existentes: pill activa, badges no-null, footer perfil, theme toggle presente; scenarios 748–763 se preservan | Extender los tests actuales, no reescribir |
| No-hex scanner | Gate existente sigue verde | ya corre |

## Lo que NO cambia
Routes/router (`coach_hub_router.dart`, `coach_hub_page.dart`, `NoTransitionPage`), contenido de secciones (fases 2–12), capa de datos/providers (salvo lectura de `userProfileProvider`/`themeModeProvider`/badgeProviders ya existentes), `responsive.dart` (breakpoints 768/1280 se **reusan**), `sidebar_registry.dart`/`sidebar_item.dart` (solo se **cablea** badgeProvider ya presente en el modelo), API pública de `AppPalette`.

## Slicing de PR (auto-chain recomendado)
| Slice | Contenido | Líneas est. |
|---|---|---|
| **A — Kit + tokens** | 9 clases de tokens + `TreinoInteractiveState` + 7 componentes + previews + tests de matriz | ~380–420 |
| **B — Shell redesign** | sidebar pill/badges/footer, topbar account+theme, scaffold entrada, mobile_banner fix, delete/reubicar section_header, tests shell | ~300–350 |
**Recomendación**: chained PRs (A→B). A supera fácil 400 líneas si se suma B; A es autónomo (kit con preview+test verifica solo), B consume A. B targetea la rama de A. Si A solo excede 400, sub-split por sub-grupo de tokens (tabla/kpi/chip vs. row/header/empty/dialog) manteniendo work-unit commits (componente+test en el mismo commit).

## Preguntas abiertas
- [ ] Ancho de sidebar del mockup (240) vs. actual (264): confirmar en apply — se mantiene 264 salvo mandato de mockup con múltiplo válido.
- [ ] i18n de labels sigue diferido (W1); no se resuelve en Fase 1 salvo pedido explícito.

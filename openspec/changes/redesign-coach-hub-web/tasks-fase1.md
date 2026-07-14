# Tasks: Fase 1 — Shell Coach Hub Web + Kit de Componentes Base

> Cambio: redesign-coach-hub-web · Fase 1 · Rama: refactor/coach-hub-shell-redesign
> TDD estricto activo: `flutter test` (test-first: RED → GREEN → refactor por cada work unit)

---

## Review Workload Forecast

| Campo | Valor |
|-------|-------|
| Líneas estimadas (código) | ~430–490 nuevas/modificadas |
| Líneas estimadas (tests) | ~280–320 nuevas/modificadas |
| Total estimado | **~710–810 líneas** |
| Riesgo 400-líneas Slice A | High (420–490 líneas) |
| Riesgo 400-líneas Slice B | Medium (~320–370 líneas) |
| PRs encadenados recomendados | Yes |
| Split sugerido | PR A (tokens + kit) → PR B (shell redesign) |
| Delivery strategy | auto-chain |
| Chain strategy | feature-branch-chain |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Work Units sugeridos

| Unit | Objetivo | PR | Base branch |
|------|----------|----|-------------|
| A | 9 clases de tokens + TreinoInteractiveState + 7 componentes kit + previews + tests | PR-A | refactor/coach-hub-shell-redesign |
| B | Redesign shell (sidebar/topbar/scaffold/section_header/mobile_banner) + tests shell actualizados | PR-B | branch de PR-A |

> PR-A puede sub-splitearse si excede 400 líneas: A1 = tokens + TreinoInteractiveState + tabla/kpi/chip; A2 = row/header/empty/dialog.

---

## SLICE A — Kit de Tokens + Componentes Base

### Fase A1: Infraestructura de tokens (fundación del kit)

Requirement: REQ-SH-020, REQ-SH-021, ADR-SH-003

- [ ] A1.1 **[RED]** Escribir test `test/app/theme/tokens/components/coach_hub_layout_tokens_test.dart`: verificar que `CoachHubLayoutTokens.sidebarExpandedWidth == 240`, `collapsedWidth == 72`, `topBarHeight == 64`, `contentMaxWidth == 1240`, `sidebarItemHeight == 48`, `sidebarAvatarDiameter == 44`, `sidebarBadgeSize == 16`. ~20 líneas.
  - Archivo: `test/app/theme/tokens/components/coach_hub_layout_tokens_test.dart`

- [ ] A1.2 **[GREEN]** Crear `lib/app/theme/tokens/components/coach_hub_layout_tokens.dart`: `abstract final class CoachHubLayoutTokens` con 7 constantes `static const double`. ~20 líneas.
  - Archivo: `lib/app/theme/tokens/components/coach_hub_layout_tokens.dart`

- [ ] A1.3 **[RED]** Escribir test `test/app/theme/tokens/components/coach_hub_sidebar_item_tokens_test.dart`: smoke test `pumpWidget` dark+light, verificar `borderRadius == AppRadius.sm`, `paddingH == AppSpacing.s14`, `paddingV == AppSpacing.s12`, `hoverBackground != activeBackground`. ~35 líneas.
  - Archivo: `test/app/theme/tokens/components/coach_hub_sidebar_item_tokens_test.dart`

- [ ] A1.4 **[GREEN]** Crear `lib/app/theme/tokens/components/coach_hub_sidebar_item_tokens.dart`: `abstract final class CoachHubSidebarItemTokens` con `factory of(BuildContext)` retornando instancia con activeBackground=`palette.bgCard`, activeForeground=`palette.accent`, inactiveForeground=`palette.textPrimary`, hoverBackground=`palette.accent.withOpacity(0.08)`, badgeBackground=`palette.highlight`, cero hex. ~40 líneas.
  - Archivo: `lib/app/theme/tokens/components/coach_hub_sidebar_item_tokens.dart`

- [ ] A1.5 **[RED]** Escribir tests para los 7 tokens restantes en un solo archivo `test/app/theme/tokens/components/coach_hub_kit_tokens_test.dart`: smoke dark+light por clase; verificar que valores dark ≠ light donde corresponde; verificar cero hex (scanner). Clases: `TreinoKpiCardTokens`, `TreinoSectionHeaderTokens`, `TreinoListRowTokens`, `TreinoChipTokens`, `TreinoEmptyStateTokens`, `TreinoTableTokens`, `TreinoDialogTokens`. ~90 líneas.
  - Archivo: `test/app/theme/tokens/components/coach_hub_kit_tokens_test.dart`

- [ ] A1.6 **[GREEN]** Crear los 7 archivos de tokens en `lib/app/theme/tokens/components/`: `treino_kpi_card_tokens.dart`, `treino_section_header_tokens.dart`, `treino_list_row_tokens.dart`, `treino_chip_tokens.dart`, `treino_empty_state_tokens.dart`, `treino_table_tokens.dart`, `treino_dialog_tokens.dart`. Cada uno `abstract final class` con `static T of(BuildContext)` o `static T method(BuildContext)` según aplique. Mínimo: padding, borderRadius, colores semantic via `AppPalette.of(ctx)`. Incluir también `TreinoBadgeTokens` y `TreinoFocusTokens`. ~200 líneas totales.
  - Archivos: 7 en `lib/app/theme/tokens/components/`

- [ ] A1.7 Actualizar barrel `lib/app/theme/tokens/tokens.dart`: agregar exports de los 9 nuevos archivos de tokens. ~12 líneas nuevas.
  - Archivo: `lib/app/theme/tokens/tokens.dart`

### Fase A2: TreinoInteractiveState (resolver de estado compartido)

Requirement: ADR-SH-002

- [ ] A2.1 **[RED]** Escribir test `test/features/coach_hub/presentation/widgets/treino_interactive_state_test.dart`: verificar que con `onTap==null` el builder recibe `disabled=true`; que hover sobre `MouseRegion` emite `hovered=true`; que focus emite `focused=true`; que el widget no pinta ningún color/decoración propio (solo invoca builder). ~50 líneas.
  - Archivo: `test/features/coach_hub/presentation/widgets/treino_interactive_state_test.dart`

- [ ] A2.2 **[GREEN]** Crear `lib/features/coach_hub/presentation/widgets/treino_interactive_state.dart`: `TreinoStates({hovered, pressed, focused, disabled})`, `TreinoInteractiveState` widget con `MouseRegion` + `FocusableActionDetector` + `TreinoTappable`; `builder(BuildContext, TreinoStates) → Widget`. `onTap==null ⇒ disabled`. No pinta, delega look al consumidor. ~70 líneas.
  - Archivo: `lib/features/coach_hub/presentation/widgets/treino_interactive_state.dart`

### Fase A3: Componentes del kit (test-first por componente)

Cada subtarea = commit de work-unit (test RED + implementación GREEN + preview en mismo commit).
Requirement: REQ-CK-001 a REQ-CK-007

- [ ] A3.1 **[RED+GREEN+preview] KpiCard** — Test: normal/loading/error/hover dark+light. Widget: `lib/features/coach_hub/presentation/widgets/kpi_card/kpi_card.dart`. Preview: `kpi_card_preview.dart` @MultiPreview. Usa `TreinoKpiCardTokens`, `TreinoShimmer`, `TreinoStateSwitcher`. ~80 líneas código + ~60 test.
  - Archivos: `lib/.../widgets/kpi_card/kpi_card.dart`, `kpi_card_preview.dart`, `test/.../widgets/kpi_card_test.dart`

- [ ] A3.2 **[RED+GREEN+preview] SectionHeader** — Test: normal/con-acción/disabled dark+light. Widget: `lib/features/coach_hub/presentation/widgets/section_header/section_header.dart` (nueva versión tokenizada). Preview dark+light. Usa `TreinoSectionHeaderTokens`. ~50 líneas código + ~40 test.
  - Archivos: `lib/.../widgets/section_header/section_header.dart`, `section_header_preview.dart`, `test/.../widgets/section_header_test.dart`

- [ ] A3.3 **[RED+GREEN+preview] ListRow** — Test: normal/hover/pressed/disabled/loading dark+light. Widget: `lib/features/coach_hub/presentation/widgets/list_row/list_row.dart`. Usa `TreinoInteractiveState`, `TreinoListRowTokens`, `TreinoShimmer`, `TreinoTappable`. ~70 líneas código + ~55 test.
  - Archivos: `lib/.../widgets/list_row/list_row.dart`, `list_row_preview.dart`, `test/.../widgets/list_row_test.dart`

- [ ] A3.4 **[RED+GREEN+preview] FilterChips** — Test: chip normal/selected/hover/disabled/focus; grupo multi-select; keyboard navigation. Widget: `lib/features/coach_hub/presentation/widgets/filter_chips/filter_chips.dart`. Usa `TreinoChipTokens`, `TreinoBadgeTokens`, `FocusableActionDetector`. ~80 líneas código + ~60 test.
  - Archivos: `lib/.../widgets/filter_chips/filter_chips.dart`, `filter_chips_preview.dart`, `test/.../widgets/filter_chips_test.dart`

- [ ] A3.5 **[RED+GREEN+preview] EmptyState** — Test: normal/con-CTA/loading dark+light. Widget: `lib/features/coach_hub/presentation/widgets/empty_state/empty_state.dart`. Usa `TreinoEmptyStateTokens`. Consume en shell (Fase 1) y kit-foundation (Fases 2-12). ~45 líneas código + ~35 test.
  - Archivos: `lib/.../widgets/empty_state/empty_state.dart`, `empty_state_preview.dart`, `test/.../widgets/empty_state_test.dart`

- [ ] A3.6 **[RED+GREEN+preview] CoachHubDataTable** — Test: normal/loading(shimmer)/empty(EmptyState)/error+retry/hover-fila/sorted dark+light. Widget: `lib/features/coach_hub/presentation/widgets/data_table/coach_hub_data_table.dart`. Usa `TreinoTableTokens`, `TreinoShimmer`, `TreinoStateSwitcher`, `EmptyState` embebido. ~110 líneas código + ~80 test.
  - Archivos: `lib/.../widgets/data_table/coach_hub_data_table.dart`, `data_table_preview.dart`, `test/.../widgets/data_table_test.dart`

- [ ] A3.7 **[RED+GREEN+preview] Dialog** — Test: normal/destructive/loading(spinner)/error-inline/reduceMotion dark+light. Widget: `lib/features/coach_hub/presentation/widgets/dialog/coach_hub_dialog.dart`. Usa `TreinoDialogTokens`; apertura `AppMotionTokens.resolve` reduceMotion-safe. ~65 líneas código + ~50 test.
  - Archivos: `lib/.../widgets/dialog/coach_hub_dialog.dart`, `dialog_preview.dart`, `test/.../widgets/dialog_test.dart`

### Fase A4: Barrel de widgets + gates Slice A

- [ ] A4.1 Crear barrel `lib/features/coach_hub/presentation/widgets/coach_hub_widgets.dart` exportando `TreinoInteractiveState` + 7 componentes del kit. ~15 líneas.
  - Archivo: `lib/features/coach_hub/presentation/widgets/coach_hub_widgets.dart`

- [ ] A4.2 Gate: `flutter analyze` ≤ 42 issues. `flutter test` 0 failures. No-hex scanner verde (REQ-SH-093). Anotar en PR-A description.

---

## SLICE B — Redesign del Shell

> Base branch: branch de PR-A (feature-branch-chain).

### Fase B1: Tokens de layout shell + motion (fundación Slice B)

Requirement: REQ-SH-020, REQ-SH-021 (ya en Slice A; solo verificar disponibilidad)

- [ ] B1.1 Verificar que `CoachHubLayoutTokens` y `CoachHubSidebarItemTokens` están disponibles en el branch base. (No-op si Slice A mergeado; si no, cherry-pick A1.1–A1.7.) 0 líneas nuevas.

### Fase B2: section_header.dart — migración a token (REQ-CK-002)

Requirement: REQ-SH-004, REQ-CK-002

- [ ] B2.1 **[RED]** Actualizar test `test/features/coach_hub/presentation/shell/coach_hub_scaffold_test.dart` (y cualquier test que use el `SectionHeader` de shell): referenciar el nuevo widget desde `widgets/section_header/` en vez de `shell/section_header.dart`. ~10 líneas modificadas.

- [ ] B2.2 Reemplazar `lib/features/coach_hub/presentation/shell/section_header.dart` con un re-export al nuevo `section_header.dart` del kit (para compatibilidad transitoria) O eliminar y actualizar imports. Decisión en apply: preferir eliminación y actualización directa. ~5 líneas (eliminación o re-export).
  - Archivo: `lib/features/coach_hub/presentation/shell/section_header.dart`

### Fase B3: Sidebar redesign (REQ-SH-001 a REQ-SH-006, REQ-SH-010)

- [ ] B3.1 **[RED]** Actualizar `test/features/coach_hub/presentation/shell/coach_hub_sidebar_test.dart`: agregar casos pill activa (bgCard+accent), badges non-null (Pagos/Chat), footer avatar+nombre+subtítulo, ancho expandido 240 px, ancho colapsado 72 px, entrada motion (TreinoFadeSlideIn smoke), toggle en footer deshabilitado en compact. Preservar scenarios existentes. ~80 líneas añadidas.
  - Archivo: `test/features/coach_hub/presentation/shell/coach_hub_sidebar_test.dart`

- [ ] B3.2 **[GREEN]** Refactorizar `lib/features/coach_hub/presentation/shell/coach_hub_sidebar.dart`:
  - Cambiar `expandedWidth` 264→240 usando `CoachHubLayoutTokens.sidebarExpandedWidth`.
  - Ítem activo → pill con `AnimatedContainer` (color `bgCard`, border-left accent via BoxDecoration).
  - Hover → `TreinoInteractiveState` o `MouseRegion` con `hoverBackground` de `CoachHubSidebarItemTokens`.
  - Header GESTIÓN: remover toggle (toggle va al footer — REQ-SH-006).
  - `TreinoFadeSlideIn` staggered en entrada (stagger máx 30 ms, `AppMotionTokens.contentEnter`).
  - Footer: avatar circular 44 px inicial accent, nombre (Barlow 600 14 px), subtítulo (Barlow 400 12 px textMuted), chevron-down, IconButton toggle autónomo (`CoachHubLayoutTokens.sidebarAvatarDiameter`).
  - Badges: `SidebarItem.badgeProvider` → círculo 16 px highlight Barlow 700 10 px.
  - Collapse: `AnimatedContainer` 240↔72, `AnimatedOpacity` labels, `Clip.hardEdge`.
  - Cero hex nuevos. ~130 líneas modificadas.
  - Archivo: `lib/features/coach_hub/presentation/shell/coach_hub_sidebar.dart`

### Fase B4: Top Bar redesign (REQ-SH-007)

- [ ] B4.1 **[RED]** Actualizar `test/features/coach_hub/presentation/shell/coach_hub_top_bar_test.dart`: verificar título sección (Barlow Condensed 700 24 px UPPERCASE), campo búsqueda (placeholder "Buscar alumnos, rutinas, plan...", TreinoIcon.search, alto 40-44 px), bell + avatar + chevron a la derecha, fondo `palette.bg`, sin toggle lateral. ~50 líneas añadidas.
  - Archivo: `test/features/coach_hub/presentation/shell/coach_hub_top_bar_test.dart`

- [ ] B4.2 **[GREEN]** Refactorizar `lib/features/coach_hub/presentation/shell/coach_hub_top_bar.dart`:
  - Agregar título de sección izquierda (Barlow Condensed 700 24 px UPPERCASE `textPrimary`).
  - Campo búsqueda centrado decorativo: TextField bgCard, radius 12, 40-44 px, TreinoIcon.search, Barlow 400 placeholder.
  - Derecha: bell (TreinoIcon), avatar (inicial accent), chevron-down para menú de cuenta.
  - Menú de cuenta incluye theme toggle (escribe `themeModeProvider`).
  - Altura 64 px via `CoachHubLayoutTokens.topBarHeight`. Cero hex nuevos. ~80 líneas modificadas.
  - Archivo: `lib/features/coach_hub/presentation/shell/coach_hub_top_bar.dart`

### Fase B5: Scaffold + MobileBanner (REQ-SH-008, REQ-SH-010)

- [ ] B5.1 **[RED]** Actualizar `test/features/coach_hub/presentation/shell/coach_hub_scaffold_test.dart`: verificar `contentMaxWidth == 1240`, entrance motion TreinoFadeSlideIn presente, mobile_banner spacing 20 px. ~25 líneas añadidas.
  - Archivo: `test/features/coach_hub/presentation/shell/coach_hub_scaffold_test.dart`

- [ ] B5.2 **[GREEN]** Actualizar `lib/features/coach_hub/presentation/shell/coach_hub_scaffold.dart`: reemplazar `ContentMaxWidth` hardcoded con `CoachHubLayoutTokens.contentMaxWidth` (1240). Agregar `TreinoFadeSlideIn` envolviendo el Row principal. ~15 líneas modificadas.
  - Archivo: `lib/features/coach_hub/presentation/shell/coach_hub_scaffold.dart`

- [ ] B5.3 **[GREEN]** Actualizar `lib/features/coach_hub/presentation/shell/mobile_banner.dart`: fix spacing hardcoded 24→`AppSpacing.s20` (REQ-SH-008). ~3 líneas modificadas.
  - Archivo: `lib/features/coach_hub/presentation/shell/mobile_banner.dart`

### Fase B6: Tests smoke dark+light + gates Slice B

Requirement: REQ-SH-091, REQ-SH-092, REQ-SH-094

- [ ] B6.1 Agregar smoke tests dark+light en `test/features/coach_hub/presentation/shell/coach_hub_sidebar_test.dart` y `coach_hub_top_bar_test.dart`: pump con `mintMagenta` y `mintMagentaLight`, verificar sin overflow ni hex. ~40 líneas.

- [ ] B6.2 Verificar `test/features/coach_hub/presentation/shell/responsive_breakpoints_test.dart` sin modificar assertions (REQ-SH-009): solo asegurarse que sigue verde tras cambios de Slice B.

- [ ] B6.3 Gate final: `flutter analyze` ≤ 42 issues, `flutter test` 0 failures, responsive 1440+900 sin overflow, cero hex nuevos, dark+light ambos polished.

---

## Resumen de archivos por slice

### Slice A — archivos nuevos
```
lib/app/theme/tokens/components/
  coach_hub_layout_tokens.dart         (A1.2)
  coach_hub_sidebar_item_tokens.dart   (A1.4)
  treino_kpi_card_tokens.dart          (A1.6)
  treino_section_header_tokens.dart    (A1.6)
  treino_list_row_tokens.dart          (A1.6)
  treino_chip_tokens.dart              (A1.6)
  treino_empty_state_tokens.dart       (A1.6)
  treino_table_tokens.dart             (A1.6)
  treino_dialog_tokens.dart            (A1.6)
lib/features/coach_hub/presentation/widgets/
  treino_interactive_state.dart        (A2.2)
  kpi_card/kpi_card.dart + preview     (A3.1)
  section_header/section_header.dart + preview (A3.2)
  list_row/list_row.dart + preview     (A3.3)
  filter_chips/filter_chips.dart + preview (A3.4)
  empty_state/empty_state.dart + preview (A3.5)
  data_table/coach_hub_data_table.dart + preview (A3.6)
  dialog/coach_hub_dialog.dart + preview (A3.7)
  coach_hub_widgets.dart (barrel)      (A4.1)
lib/app/theme/tokens/tokens.dart (modificado) (A1.7)

test/app/theme/tokens/components/
  coach_hub_layout_tokens_test.dart    (A1.1)
  coach_hub_sidebar_item_tokens_test.dart (A1.3)
  coach_hub_kit_tokens_test.dart       (A1.5)
test/features/coach_hub/presentation/widgets/
  treino_interactive_state_test.dart   (A2.1)
  kpi_card_test.dart                   (A3.1)
  section_header_test.dart             (A3.2)
  list_row_test.dart                   (A3.3)
  filter_chips_test.dart               (A3.4)
  empty_state_test.dart                (A3.5)
  data_table_test.dart                 (A3.6)
  dialog_test.dart                     (A3.7)
```

### Slice B — archivos modificados
```
lib/features/coach_hub/presentation/shell/
  coach_hub_sidebar.dart               (B3.2)
  coach_hub_top_bar.dart               (B4.2)
  coach_hub_scaffold.dart              (B5.2)
  mobile_banner.dart                   (B5.3)
  section_header.dart → eliminado/re-export (B2.2)

test/features/coach_hub/presentation/shell/
  coach_hub_sidebar_test.dart          (B3.1, B6.1)
  coach_hub_top_bar_test.dart          (B4.1, B6.1)
  coach_hub_scaffold_test.dart         (B2.1, B5.1)
  responsive_breakpoints_test.dart     (B6.2 — solo verificar)
```

---

## Conteo de tareas

| Fase | Tareas | Slice |
|------|--------|-------|
| A1 — Infraestructura tokens | 7 | A |
| A2 — TreinoInteractiveState | 2 | A |
| A3 — 7 componentes kit | 7 | A |
| A4 — Barrel + gates | 2 | A |
| B1 — Verificación tokens | 1 | B |
| B2 — SectionHeader migración | 2 | B |
| B3 — Sidebar redesign | 2 | B |
| B4 — TopBar redesign | 2 | B |
| B5 — Scaffold + MobileBanner | 3 | B |
| B6 — Smoke tests + gates | 3 | B |
| **Total** | **31** | **A+B** |

Orden: A1 → A2 → A3 (paralelo por componente) → A4 → B1 → B2 → B3+B4 (paralelo) → B5 → B6.

# Propuesta: Rediseño Coach Hub Web + Design System v2

> **Cambio**: redesign-coach-hub-web · **Rama**: refactor/theme-design-system-v2 · **Fecha**: 2026-07-13 · **Store**: hybrid

## Intent

El Coach Hub Web es funcional pero le falta base de sistema. Los primitivos de color están hardcodeados dentro de `AppPalette`, no hay mapeo explícito primitivo→semántico, no existe capa de componente, el motion es desparejo (0 uso de `TreinoStateSwitcher`, 58 spinners crudos) y hay ~8 patrones de widget duplicados. Los docs están stale (dicen "oscuro siempre" cuando light ya existe). El usuario quiere un look profesional, vivo y fluido, con dark y light pulidos y cero widgets duplicados. La condición previa es formalizar el sistema de tokens de 3 capas (Fase 0) para que las 12 fases de rediseño se apoyen en él.

## Scope

### In Scope
- **Fase 0 — Design System v2** (detallada abajo; requiere aprobación antes de Fase 1).
- **Fases 1–12** a nivel titular, una PR por fase (auto-chain, work-unit commits):
  1 Shell + componentes base · 2 Dashboard · 3 Alumnos · 4 Solicitudes/Invitaciones · 5 Rutinas+editor · 6 Nutrición · 7 Biblioteca · 8 Chat · 9 Pagos · 10 Planes · 11 Perfil público · 12 Ajustes.
- Componentes web compartidos (todos con estados normal/hover/pressed/disabled/focus/loading/empty/error, preview + test, reuso 2+): CoachHubDataTable, KpiCard, ListRow, FilterChips, SectionHeader, EmptyState, Dialog.

### Out of Scope
- Fases 1–12 se **proponen** acá pero se **aprueban una por una** (no se implementan en este cambio sin gate).
- Cambio visual en Fase 0: es restructure, no redesign. La app debe compilar y verse idéntica.
- Gamificación (Ranking, Retos, Missions, Bets, Levels/XP) — fuera para siempre.
- Secciones "Próximamente" sin mockup: quedan placeholder.
- Paleta Electric Violet (descartada) y variantes de mockup light (no existen).

## Fase 0 — Design System v2 (en profundidad)

| Capa | Ubicación | Contenido |
|------|-----------|-----------|
| **Primitive** (NUEVA) | `lib/app/theme/tokens/primitives.dart` | `AppColorPrimitives` const con escala tonal (mint500 `#2CE5A2`, magenta500 `#C123E0`, ink950 `#0A0A0A`, etc.), sin `BuildContext`. `AppSpacing` (s8/s12/s14/s18/s20 — NO 4/16/24). `AppRadius` (sm=12/md=16/lg=20/full). Familias tipográficas Barlow / Barlow Condensed. |
| **Semantic** (FORMALIZAR) | `lib/app/theme/app_palette.dart` | `AppPalette` mantiene API pública intacta (`of(context)`, `mintMagenta`, `mintMagentaLight`, `copyWith`, `lerp`). Cada uno de los 14 tokens pasa a **referenciar un primitivo**. Dark y light = dos mapeos semántico→primitivo. Dark sigue siendo default e identidad. |
| **Component** (NUEVA) | `lib/app/theme/tokens/components/` | Tokens por componente (`TreinoButtonTokens`, `TreinoCardTokens`, …) que referencian semántico vía `static X of(BuildContext)`. Nunca hex crudo. Cards sin sombra. |
| **Motion** (FORMALIZAR) | `lib/app/theme/tokens/motion_tokens.dart` | `AppMotionTokens` semánticos sobre `AppMotion` (ítem P3 del animation-audit). Respetan `reduceMotion`. |
| **Docs** | `docs/design-system.md`, `docs/architecture.md` | Reescritura reflejando 3 capas + sección Motion; corregir "oscuro siempre", quitar Electric Violet, agregar tokens faltantes, corregir comentario `electricViolet`→`mintMagentaLight`. |

## Approach — tokens en Dart: **Opción A**

Clases estáticas `const` para primitivos/spacing/radios + tokens de componente con factory `of(ctx)` que leen `AppPalette.of(ctx)`. Se elige sobre B (ThemeExtension por componente) y C (extension methods) porque:

- **Cero ruptura de API**: los ~499 call sites de `AppPalette.of(context)` siguen compilando sin tocarse (la referencia a primitivos es interna).
- **Const-friendly**: primitivos/spacing/radios disponibles sin `BuildContext`, cosa que C no resuelve bien.
- **Consistencia**: mismo patrón `ThemeExtension` que ya usa `AppPalette`; bajo boilerplate vs. B.
- **Testabilidad**: primitivos const testeables aislados; tokens de componente testeables con `of(ctx)`.
- **Ergonomía en call sites**: acceso uniforme `TreinoXTokens.of(ctx)`, migrable a B (override por subtree) sin cambiar call sites si algún día hace falta.

## Capabilities

### New Capabilities
- `design-tokens`: sistema de 3 capas (primitive → semantic → component) + tokens de motion en Dart, documentado.

### Modified Capabilities
- None (Fase 0 no cambia requisitos de comportamiento existentes; formaliza estructura sin alterar la salida visual).

## Affected Areas

| Área | Impacto | Descripción |
|------|---------|-------------|
| `lib/app/theme/tokens/` | New | primitives, motion_tokens, components/ |
| `lib/app/theme/app_palette.dart` | Modified | tokens referencian primitivos; API intacta |
| `docs/design-system.md` · `docs/architecture.md` | Modified | reescritura 3 capas + Motion; correcciones |
| `lib/features/coach_hub/` | Modified (Fases 1–12) | rediseño por sección |

## Risks

| Riesgo | Prob | Mitigación |
|--------|------|------------|
| Ruptura de 499 call sites `AppPalette.of` | Media | Opción A: API pública sin cambios; `flutter analyze` 0 como gate |
| build_runner choca con routine_editor no committeado | Alta | Solo correr si se toca freezed; no tocar archivos del usuario |
| Docs requieren aprobación de reviewer | Media | Gate explícito al cerrar Fase 0 |
| Tests existentes rompen por cambio de tokens | Media | TDD estricto: test antes de código; suite verde pre-merge |
| Light web sin mockup de referencia | Alta | Derivar del mapeo semántico; dark manda como identidad |

## Rollback Plan

Fase 0 es aditiva: revertir el commit que agrega `lib/app/theme/tokens/` y restaura `app_palette.dart`/docs. Como no hay cambio visual ni de API, el revert es limpio y aislado. Cada Fase 1–12 es su propia PR revertible por separado.

## Dependencies

- Exploración `sdd/redesign-coach-hub-web/explore` (leída).
- Mockups PNG en `docs/web-trainer/screens/` como north star (design system gana ante conflicto de token).

## Success Criteria

### Fase 0
- [ ] `flutter analyze` → 0 issues
- [ ] `dart format .` aplicado
- [ ] `flutter test` verde
- [ ] La app compila y se ve **idéntica** (cero cambio visual)
- [ ] `AppPalette.of(context)` sin cambios de firma (call sites intactos)
- [ ] Cada token semántico referencia un primitivo; dark y light mapeados
- [ ] `docs/design-system.md` reescrito (3 capas + Motion) y aprobado por reviewer

### Fases 1–12 (por PR)
- [ ] Gates de calidad: analyze 0, format, tests (+ build_runner si toca freezed)
- [ ] Pantalla fiel al mockup (tolerancia a diffs menores)
- [ ] Cero widgets duplicados: todo patrón repetido es componente con todos los estados, preview y test, reusado 2+
- [ ] Motion aplicado (StateSwitcher en `.when`, shimmer, fade-slide staggered, tappable) respetando reduce-motion
- [ ] Dark y light pulidos

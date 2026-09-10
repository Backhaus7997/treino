# Migración a `TreinoButton` — estado y qué falta

**Última actualización:** 2026-09-10 · rama base `211d4d77`

Este archivo existe porque la migración no entra en una sesión y el repo corre
con varios agentes a la vez (AGENTS.md §10c: lo que tiene que sobrevivir a una
sesión va a un archivo del repo, no a memoria local).

## Por qué

`presentation/widgets/` del Coach Hub tenía avatar, data_table, dialog,
empty_state, filter_chips, kpi_card, list_row, pager, section_header,
section_hero, skeleton y treino_dropdown — y ningún `button/`.
`TreinoButtonTokens` existía desde el principio pero suelto, sin widget que lo
encapsulara, así que cada pantalla se armó su
`OutlinedButton`/`TextButton`/`ElevatedButton` a mano.

Medido sobre `211d4d77`: **156 botones Material crudos en 43 archivos** de
`lib/features/coach_hub/`. Sólo en `alumno_detail_screen.dart` conviven siete
paddings distintos y seis tamaños de ícono; el botón de confirmar es a veces
`FilledButton` y a veces `ElevatedButton`; el mismo ícono de eliminar aparece
en cuatro tamaños; y de 59 botones apenas 6 acotan su tap target — los otros 53
arrastran los 48 px de Material 3, invisibles pero contando para el layout.

## El componente

`lib/features/coach_hub/presentation/widgets/button/treino_button.dart`

- `TreinoButton` — 4 variantes x 3 tamaños. `label` es opcional (un botón de
  sólo ícono que igual respeta el alto de su tamaño); `icon` y `trailing`
  también.
- `TreinoIconButton` — caja cuadrada del alto de su tamaño.

Tokens en `lib/app/theme/tokens/components/treino_button_tokens.dart`.

### Elegir variante

| variante | cuándo | ojo |
|---|---|---|
| `primary` | el CTA de la pantalla | uno por pantalla |
| `secondary` | acción secundaria neutra | «Chat» del detalle |
| `secondaryAccent` | secundaria que el diseño quiere que se note | «Pago» del detalle. Lleva `accentText` adentro — ver abajo |
| `ghost` | acciones que no compiten (cancelar, «ver más») | |

### Elegir tamaño

| tamaño | alto | dónde |
|---|---|---|
| `xs` | 24 | **sólo** dentro de una fila de `CoachHubDataTable`. No es «sm más chico»: 48 de `rowHeight` menos 12+12 de `cellPaddingV` son 24 de alto útil y no hay negociación |
| `sm` | 32 | headers, barras de acciones, densidad de fila |
| `md` | 40 | diálogos, CTA de sección |

## Tres cosas que no son obvias

1. **`accentText` no es `accent`.** El acento (mint500) como TEXTO sobre una
   card blanca mide 1,64:1 contra los 4,5 que pide WCAG AA. En tema oscuro los
   dos tokens son **el mismo color**, así que la suite —que corre en oscuro—
   nunca lo ve. Por eso la decisión vive en `secondaryAccent` y no en el
   callsite: es el arreglo de #1056, blindado.
2. **`visualDensity: compact` resta 8 px por eje.** Son 2 unidades a 4 px cada
   una. Un `IconButton` con `minimumSize: Size(32, 32)` y `compact` mide
   **24x24** efectivos. Los cuatro íconos del roster medían eso por accidente,
   no por diseño — y el PR #1062 creyó que los estaba dejando en 32.
3. **No atar los tests al tipo de widget.** El test de #1062 buscaba el
   `IconButton` que envolvía al tooltip; al migrar reventó sin que nada se
   hubiera roto en pantalla. Medí la caja renderizada
   (`tester.getSize(find.byTooltip(...))`), que es lo que el usuario ve.

## Qué falta

Cuatro PRs de migración más uno de candado. Los cuatro van a pasar las 400
líneas de AGENTS.md §8 — el maintainer aprobó `size:exception` para esta
migración el 2026-09-09.

| PR | archivos | botones | notas |
|---|---|---|---|
| **7 (empezado)** | `alumno_detail_screen.dart` | **36 restantes** | 7 pares de diálogo (cancelar + confirmar), 11 `IconButton`, 6 `TextButton.icon`. Ya migrados: header (`_ChatAction`, «Pago») y `_IconAction` del roster |
| 8 | `agenda/` (8 archivos) | 42 | `appointment_detail_dialog` 10, `availability_editor_panel` 9, el resto 2-5 |
| 9 | `routine_editor_web_screen.dart` 23, `exercise_picker_dialog.dart` 11, `biblioteca/` 8 | 42 | |
| 10 | `pagos/` 12, `ajustes/` 6, `plan_preview`+`upload_plan` 10, `dashboard/` 7, sueltos | ~30 | |
| 11 | — | — | Guard de CI que prohíbe `IconButton\|OutlinedButton\|TextButton\|ElevatedButton\|FilledButton` en `lib/features/coach_hub/`, con ratchet de allowlist + techo de ocurrencias. Calcar `test/app/theme/tokens/no_raw_font_size_scan_test.dart`. **Con control negativo**: un scanner roto también da cero infracciones |

El grueso del PR 7 son los pares de diálogo, y son mecánicos:
`TextButton` (cancelar) → `TreinoButton(variant: ghost)`, `FilledButton` /
`ElevatedButton` (confirmar) → `TreinoButton(variant: primary)`. Que el mismo
diálogo use a veces uno y a veces el otro es parte de lo que se está
arreglando.

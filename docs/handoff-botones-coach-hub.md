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

- `TreinoButton` — 6 variantes x 3 tamaños. `label` es opcional (un botón de
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
| `ghostAccent` | link de texto en acento | «+ Asignar rutina», «Exportar CSV». Mismo `accentText` |
| `danger` | la acción destruye algo | «ELIMINAR CUENTA», «CANCELAR TODA LA SERIE». Fuera de la grilla: no es un nivel de énfasis |

### Elegir tamaño

| tamaño | alto | dónde |
|---|---|---|
| `xs` | 24 | **sólo** dentro de una fila de `CoachHubDataTable`. No es «sm más chico»: 48 de `rowHeight` menos 12+12 de `cellPaddingV` son 24 de alto útil y no hay negociación |
| `sm` | 32 | headers, barras de acciones, densidad de fila |
| `md` | 40 | diálogos, CTA de sección |

## Cuatro cosas que no son obvias

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
4. **La tipografía del botón es Barlow, no Barlow Condensed.** Agenda, el
   editor de rutina y el picker usaban Condensed y por un rato parecieron
   mayoría. Pero `AGENTS.md` dice Condensed para HEADINGS, y el botón propio
   del kit que sigue esa regla es el de `TreinoDialog` (Barlow w600). El
   `CoachHubHeroAction` usa Condensed porque vive DENTRO del hero y toma su
   voz, no porque sea un botón.

## Estado: TERMINADO en `coach_hub`

`lib/features/coach_hub/` tiene **cero** botones Material crudos (eran 156 en
43 archivos). Lo blinda `test/app/guards/no_material_button_scan_test.dart`,
con allowlist y techo de ocurrencias en CERO y su propio control negativo.

Las variantes crecieron durante la migración, y ninguna es un color suelto
disfrazado — cada una salió de un caso que el producto ya tenía:

| variante | apareció en | por qué |
|---|---|---|
| `secondaryAccent` | «Pago» del detalle | lleva el arreglo de contraste de #1056 adentro |
| `ghostAccent` | «+ Asignar rutina», «Exportar CSV» | los links de texto en acento |
| `danger` | «CANCELAR TODA LA SERIE», «ELIMINAR CUENTA» | destruye algo |

Las cinco de énfasis forman una grilla (neutro/acento x con borde/sin borde)
más el CTA. `danger` queda fuera a propósito: no es un nivel, es una
advertencia.

Tamaños: `xs` (24, **sólo** dentro de una fila de `CoachHubDataTable`), `sm`
(32), `md` (40).

`loading` muestra un spinner sin achicar el botón — el label sigue montado a
opacidad cero abajo. **No lo uses cuando el label ya informa** («Guardando…»,
«ENVIANDO…», «Subiendo video — 40 %»): ahí el spinner tapa la única
información que el botón tiene.

## Lo que queda

| qué | dónde | nota |
|---|---|---|
| `_DialogActionButton` | `widgets/dialog/treino_dialog.dart` | NO es Material crudo: ya es un componente del kit sobre `TreinoInteractiveState`. Consolidarlo cambiaría la pinta de TODOS los diálogos —de link de texto a píldora rellena—. Decisión de diseño del equipo |
| El resto de la app | todo menos `coach_hub` | El guard está scopeado. Extenderlo pide su propia migración |
| `fontSize` crudos | `alumno_detail_screen.dart` (105) | Hallazgo J del diagnóstico. Bajó de 111 sólo porque los botones migrados dejaron de declarar el suyo |

## Tres lecciones de la migración

1. **Un `Row` de botones con labels traducibles desborda.** Pasó dos veces —la
   barra de la agenda y el pie del picker— y las dos veces la respuesta fue
   estructural: `Flexible` + ellipsis en la pieza de ancho libre, o `Wrap`
   cuando son varios botones. No es un ancho que se pueda fijar de antemano.
2. **Los tests atados al TIPO de widget revientan sin que nada se rompa.**
   `find.byType(ElevatedButton)`, `w is IconButton`, `find.byIcon(Icons.edit)`.
   Medí lo que el usuario ve: el label, la caja renderizada, el tooltip.
3. **`TreinoIconButton(` contiene `IconButton(`.** El primer conteo de esta
   migración se equivocó por eso, y el guard necesita el look-behind para no
   reportar como infracción cada llamada al componente que exige usar.

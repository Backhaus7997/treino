# Coach Hub Web — Especificación Fase 1 (Shell + Kit de Componentes Base)

> **Cambio**: redesign-coach-hub-web · **Fase**: 1 — Shell Redesign + Base Component Kit
> **Rama objetivo**: refactor/coach-hub-shell-redesign (encadenada sobre refactor/theme-design-system-v2)
> **Store**: hybrid
> **Dependencia**: Fase 0 (tokens 3 capas) DEBE estar mergeada antes de aplicar esta especificación.

---

## Dominio A — Shell (MODIFICADO)

Las siguientes modificaciones se aplican sobre los archivos existentes en
`lib/features/coach_hub/presentation/shell/`.

---

### REQ-SH-001: Sidebar — dimensiones y layout visual según mockup

El sidebar DEBE tener ancho expandido de 240 px (actualmente 264 px) y ancho
colapsado de 72 px (sin cambio).
El fondo DEBE usar `AppPalette.of(ctx).bg` (ink950).
La separación entre el sidebar y el área de contenido DEBE ser un borde derecho
`AppPalette.of(ctx).border` de 1 px — sin sombra.

#### Escenario: ancho expandido correcto

- DADO viewport ≥ 1280 px y sidebar en estado expandido
- CUANDO se mide el ancho del sidebar widget
- ENTONCES el ancho DEBE ser 240 px

#### Escenario: ancho colapsado correcto

- DADO viewport ≥ 1280 px y sidebar en estado colapsado
- CUANDO se mide el ancho del sidebar widget
- ENTONCES el ancho DEBE ser 72 px

#### Escenario: borde sin sombra

- DADO cualquier viewport con sidebar visible
- CUANDO se inspecciona la decoración del sidebar
- ENTONCES `boxShadow` DEBE ser `[]` y el borde derecho DEBE usar `palette.border`

---

### REQ-SH-002: Sidebar — logotipo TREINO en header

El sidebar expandido DEBE mostrar el texto "TREINO" en la cabecera con tipografía
Barlow Condensed 700 UPPERCASE en color `AppPalette.of(ctx).accent`.
El header DEBE tener altura mínima de 60 px y padding horizontal de 20 px.
En estado colapsado el texto "TREINO" DEBE ocultarse; SOLO el ícono/logo compact
MAY mostrarse si existe un asset, de lo contrario el espacio DEBE mantenerse con
la misma altura mínima.

#### Escenario: logotipo visible en expandido

- DADO sidebar expandido
- CUANDO se renderiza el header
- ENTONCES existe un widget `Text` con "TREINO", fontWeight 700, fontFamily Barlow Condensed
- Y el color del texto DEBE ser `AppPalette.of(ctx).accent`

#### Escenario: logotipo oculto en colapsado

- DADO sidebar colapsado
- CUANDO se renderiza el header
- ENTONCES NO DEBE existir ningún widget `Text` con contenido "TREINO" visible

---

### REQ-SH-003: Sidebar — items de navegación con anatomía completa

Cada `_SidebarRow` DEBE cumplir:
- Altura de ítem: 48 px (padding vertical simétrico para alcanzarla).
- Ícono: 20 px, siempre presente (izquierda).
- Label: Barlow 400, 14 px, color `palette.textPrimary` cuando inactivo.
- Estado **activo**: label Barlow 600, color `palette.accent`; indicador visual de
  píldora activa (background fill `palette.bgCard`) O barra lateral izquierda
  de 3 px en `palette.accent`. El diseño DEBE decidir UNA de las dos variantes
  y aplicarla consistentemente (ver REQ-SH-003a).
- Estado **hover** (web): wash de fondo `palette.accent.withOpacity(0.08)` animado
  con `AppMotionTokens.stateSwitch` (o equivalente semántico).
- Estado **colapsado**: ítem centrado, label oculto, ícono centrado.
- Badge numérico: si `badgeProvider` retorna valor > 0, DEBE mostrarse un círculo
  de 16 px en `palette.highlight` con texto Barlow 700, 10 px, blanco; posición
  top-right del ícono.
- Padding: 14 px horizontal, 12 px vertical (sin cambio respecto a baseline).
- Border radius: 12 px.

#### REQ-SH-003a: decisión de variante activa

El equipo DEBE elegir entre píldora completa o barra lateral antes de aplicar.
Ambas variantes DEBEN estar documentadas en un comentario en `_SidebarRow`.
Si el mockup muestra barra lateral → barra lateral; si muestra relleno completo →
píldora. **Asunción de spec**: mockup muestra fondo relleno bgCard + accent text
(píldora); la barra lateral es alternativa si el reviewer lo solicita.

#### Escenario: item activo — estilo diferenciado

- DADO sidebar expandido y el ítem "Dashboard" seleccionado
- CUANDO se renderiza `_SidebarRow` con `isActive: true`
- ENTONCES el fondo del ítem DEBE tener color `palette.bgCard`
- Y el texto DEBE tener color `palette.accent` y fontWeight 600
- Y el ícono DEBE tener color `palette.accent`

#### Escenario: item inactivo — estilo neutro

- DADO sidebar expandido y el ítem "Alumnos" no seleccionado
- CUANDO se renderiza `_SidebarRow` con `isActive: false`
- ENTONCES el fondo DEBE ser transparente
- Y el texto DEBE tener color `palette.textPrimary` y fontWeight 400

#### Escenario: hover en web

- DADO sidebar expandido y el cursor sobre un ítem inactivo
- CUANDO `MouseRegion.onEnter` se dispara
- ENTONCES el fondo del ítem DEBE transicionar a `palette.accent.withOpacity(0.08)`
  con duración y curva tomadas de `AppMotionTokens` (no hardcodeadas)
- Y CUANDO `MouseRegion.onExit` se dispara
- ENTONCES el fondo DEBE retornar a transparente con la misma animación

#### Escenario: badge numérico visible

- DADO un `SidebarItem` cuyo `badgeProvider` retorna `2`
- CUANDO se renderiza `_SidebarRow`
- ENTONCES DEBE existir un widget circular de 16 px con color `palette.highlight`
- Y DEBE contener el texto "2" en Barlow 700, 10 px

#### Escenario: item colapsado centrado

- DADO sidebar colapsado
- CUANDO se renderiza cualquier `_SidebarRow`
- ENTONCES el ícono DEBE estar centrado horizontalmente
- Y NO DEBE existir ningún widget `Text` con el label del ítem visible

---

### REQ-SH-004: Sidebar — grupos y headers de sección

Los headers de sección (GESTIÓN, RECURSOS) DEBEN mostrarse en Barlow Condensed 700,
12 px, UPPERCASE, color `palette.textMuted`.
Los headers DEBEN ocultarse completamente en estado colapsado (sin ocupar espacio).
Un divisor sutil de 1 px en `palette.border.withOpacity(0.5)` DEBE separar grupos.
El header del grupo GESTIÓN ya NO actúa como toggle del sidebar (el toggle se mueve
a un botón dedicado; ver REQ-SH-006).

#### Escenario: headers visibles en expandido

- DADO sidebar expandido
- CUANDO se renderiza la lista
- ENTONCES DEBEN existir widgets Text con "GESTIÓN" y "RECURSOS" en Barlow Condensed 700

#### Escenario: headers ausentes en colapsado

- DADO sidebar colapsado
- CUANDO se renderiza la lista
- ENTONCES NO DEBEN existir widgets Text con "GESTIÓN" ni "RECURSOS"

#### Escenario: divisor entre grupos

- DADO sidebar expandido con al menos 2 grupos
- CUANDO se renderiza el sidebar
- ENTONCES DEBE existir al menos un `Divider` o `Container` de 1 px de alto
  con color basado en `palette.border`

---

### REQ-SH-005: Sidebar — footer de perfil de usuario

El sidebar DEBE mostrar un footer fijo (fuera del área scrollable) con:
- Avatar circular de 44 px diámetro, fondo `palette.bgCard`, inicial del
  displayName en `palette.accent`, Barlow 700.
- Nombre del entrenador: Barlow 600, 14 px, `palette.textPrimary`.
- Subtítulo: plan + cantidad de alumnos (e.g. "Plan Pro · 28 alumnos"),
  Barlow 400, 12 px, `palette.textMuted`. El subtítulo MAY ser un placeholder
  "— alumnos" si el dato no está disponible en Fase 1.
- Ícono chevron-down (`TreinoIcon.chevronDown` o equivalente) a la derecha.
- Área tappable (botón/InkWell) para futura apertura de menú de cuenta.
- En estado colapsado: solo el avatar centrado, nombre y subtítulo ocultos.
- El ítem de "Ajustes" en el footer actual DEBE moverse al footer rediseñado
  como ícono independiente ENCIMA del avatar de usuario, o integrarse dentro
  del grupo GESTIÓN como último ítem scrollable. **Asunción de spec**: Ajustes
  permanece como ítem pinned en el footer pero separado del avatar, en una fila
  propia sobre el bloque de usuario.

#### Escenario: footer expandido con datos de usuario

- DADO sidebar expandido y usuario autenticado con displayName "Jésica Nadal"
- CUANDO se renderiza el footer
- ENTONCES DEBE existir un `CircleAvatar` de radius ≥ 20 (diámetro ≥ 40 px)
- Y DEBE existir un `Text` con "Jésica Nadal"
- Y DEBE existir un widget `TreinoIcon.chevronDown` o equivalente visible

#### Escenario: footer colapsado solo avatar

- DADO sidebar colapsado
- CUANDO se renderiza el footer
- ENTONCES DEBE existir el `CircleAvatar` centrado
- Y NO DEBE existir ningún `Text` con el nombre del usuario

---

### REQ-SH-006: Toggle de sidebar — botón dedicado

El toggle de expansión/colapso DEBE ser un `IconButton` autónomo ubicado en el
footer del sidebar, separado del header de grupo.
El ícono DEBE usar `TreinoIcon.menu` en estado expandido y `TreinoIcon.menu`
(o un ícono de "expandir") en estado colapsado.
El toggle DEBE estar deshabilitado cuando el viewport es compact (768–1279 px).
El toggle DEBE usar tooltip "Contraer menú" / "Expandir menú" según estado.

#### Escenario: toggle en footer, separado del header de grupo

- DADO sidebar expandido en desktop
- CUANDO se renderiza el sidebar
- ENTONCES NO DEBE existir ningún `GestureDetector` ni `InkWell` en el header
  del grupo GESTIÓN asociado al toggle del sidebar

#### Escenario: toggle deshabilitado en compact

- DADO viewport entre 768 y 1279 px
- CUANDO se renderiza el toggle
- ENTONCES el `IconButton` DEBE tener `onPressed: null`

---

### REQ-SH-007: Top Bar — rediseño con búsqueda y título de página

El top bar DEBE:
- Mantener altura de 64 px.
- Mostrar el título de la sección activa en Barlow Condensed 700, 24 px, UPPERCASE,
  color `palette.textPrimary` (izquierda, tras el borde del sidebar).
- Incluir un campo de búsqueda global centrado: placeholder "Buscar alumnos,
  rutinas, plan...", background `palette.bgCard`, border radius 12 px, altura
  40–44 px, ícono de búsqueda `TreinoIcon.search` a la izquierda. En Fase 1
  el campo MAY ser decorativo (sin lógica de búsqueda); DEBE existir el widget
  con el estado visual correcto.
- Sección derecha: ícono de notificaciones `TreinoIcon.bell` (placeholder ODQ-4
  intacto), avatar del usuario (radius 16, bgCard, accent text), chevron para
  menú de cuenta.
- Fondo: `palette.bg` (sin borde inferior en dark mode; un divisor de 1 px
  `palette.border` en light mode MAY añadirse).
- El top bar NO DEBE contener el toggle del sidebar.

#### Escenario: título de sección visible

- DADO que el router está en la ruta `/dashboard`
- CUANDO se renderiza el top bar
- ENTONCES DEBE existir un `Text` con el label "DASHBOARD" en Barlow Condensed 700

#### Escenario: campo de búsqueda presente

- DADO cualquier ruta del shell
- CUANDO se renderiza el top bar
- ENTONCES DEBE existir un widget `TextField` o `SearchBar` con placeholder
  "Buscar alumnos, rutinas, plan..."
- Y DEBE existir un ícono de búsqueda visible

#### Escenario: sin toggle en top bar

- DADO el top bar renderizado
- CUANDO se inspecciona el árbol de widgets
- ENTONCES NO DEBE existir ningún `IconButton` con `TreinoIcon.menu` dentro del top bar

---

### REQ-SH-008: Scaffold — layout y max-width

El scaffold DEBE:
- Mantener la estructura `Row [Sidebar | Expanded [Column [TopBar, content]]]`.
- Mantener `ContentMaxWidth` con 1240 px.
- Corregir la violación de spacing en `mobile_banner.dart` línea 19: cambiar 24 → 20.
- En `MobileBanner` el texto DEBE usar Barlow Condensed 700 para el heading
  y el padding horizontal DEBE ser 20 px.

#### Escenario: violación de spacing corregida

- DADO `mobile_banner.dart` después de Fase 1
- CUANDO se busca el valor numérico `24` en el archivo
- ENTONCES NO DEBE existir ningún literal `24` como argumento de padding o SizedBox

---

### REQ-SH-009: Responsive — comportamiento sin cambio en breakpoints

Los breakpoints DEBEN mantenerse: mobile < 768 px, compact 768–1279 px,
desktop ≥ 1280 px. El comportamiento de cada rango NO CAMBIA respecto al baseline.
Los tests existentes de `responsive_breakpoints_test.dart` DEBEN seguir verdes
sin modificación de sus assertions.

#### Escenario: tests de breakpoints sin regresión

- DADO `responsive_breakpoints_test.dart` sin modificar
- CUANDO se ejecuta `flutter test`
- ENTONCES todos los tests de ese archivo DEBEN pasar

---

### REQ-SH-010: Entrance motion del shell

El sidebar DEBE tener una animación de entrada (`FadeSlideIn` o `TreinoFadeSlideIn`)
al montar el scaffold por primera vez, con duración desde `AppMotionTokens.contentEnter`.
Los ítems del sidebar PUEDEN tener stagger de entrada (máximo 30 ms entre ítems).
Toda animación DEBE ser ininterrumpible y responder a `reduceMotion`:
si `MediaQuery.disableAnimations` es true, la duración DEBE resolverse a
`Duration.zero` mediante `AppMotionTokens.resolve(context, duration)`.

#### Escenario: reduce-motion respetado en entrada de sidebar

- DADO `MediaQuery.disableAnimations = true`
- CUANDO se monta `CoachHubScaffold`
- ENTONCES la duración de la animación de entrada del sidebar DEBE ser `Duration.zero`

#### Escenario: animación de entrada en duración normal

- DADO `MediaQuery.disableAnimations = false`
- CUANDO se monta `CoachHubScaffold`
- ENTONCES la animación de entrada del sidebar DEBE tener duración > 0 ms

---

### REQ-SH-011: Temas dark y light — shell visualmente correcto en ambos

El shell DEBE verse profesional en modo dark (`AppPalette.mintMagenta`) Y en modo
light (`AppPalette.mintMagentaLight`). Todos los tokens de color DEBEN pasar
por `AppPalette.of(context)` — cero hex literales nuevos.
El sidebar, top bar, badges, avatar y campo de búsqueda DEBEN adaptar colores
automáticamente al cambiar el tema.

#### Escenario: cero hex literales en archivos shell de Fase 1

- DADO los archivos modificados en `lib/features/coach_hub/presentation/shell/`
- CUANDO se ejecuta el test de lint de hex (`test/theme/no_hex_literals_test.dart`)
- ENTONCES DEBE pasar sin matches

#### Escenario: shell compila y renderiza en light mode

- DADO `MaterialApp` configurado con `AppTheme.light` (mintMagentaLight)
- CUANDO se renderiza `CoachHubScaffold`
- ENTONCES `flutter test` no arroja excepciones y el widget existe en el árbol

---

## Dominio B — Tokens de Componentes Shell (NUEVO)

Los tokens de componentes para el shell DEBEN crearse en
`lib/app/theme/tokens/components/` siguiendo el patrón de Fase 0.

### REQ-SH-020: CoachHubLayoutTokens

El sistema DEBE crear `coach_hub_layout_tokens.dart` con:
- `sidebarExpandedWidth` → `240.0`
- `sidebarCollapsedWidth` → `72.0`
- `topBarHeight` → `64.0`
- `contentMaxWidth` → `1240.0`
- `sidebarItemHeight` → `48.0`
- `sidebarAvatarDiameter` → `44.0`
- `sidebarBadgeSize` → `16.0`

Todas DEBEN ser `static const double`. Cero hex. Cero BuildContext requerido.

#### Escenario: valores de layout correctos

- DADO `CoachHubLayoutTokens`
- CUANDO se accede a sus constantes
- ENTONCES `sidebarExpandedWidth == 240.0` y `topBarHeight == 64.0`

---

### REQ-SH-021: CoachHubSidebarItemTokens

El sistema DEBE crear `coach_hub_sidebar_item_tokens.dart` con factory
`of(BuildContext ctx)` que retorne un objeto con:
- `activeBackground` → `AppPalette.of(ctx).bgCard`
- `activeForeground` → `AppPalette.of(ctx).accent`
- `inactiveForeground` → `AppPalette.of(ctx).textPrimary`
- `hoverBackground` → `AppPalette.of(ctx).accent.withOpacity(0.08)`
- `badgeBackground` → `AppPalette.of(ctx).highlight`
- `borderRadius` → `AppRadius.sm` (12.0)
- `paddingH` → `AppSpacing.s14` (14.0)
- `paddingV` → `AppSpacing.s12` (12.0)

#### Escenario: tokens de ítem en dark mode

- DADO BuildContext con tema oscuro
- CUANDO se llama `CoachHubSidebarItemTokens.of(context)`
- ENTONCES `activeBackground` DEBE coincidir con `AppPalette.of(context).bgCard`
- Y NO DEBE existir ningún literal hex en el archivo

---

## Dominio C — Kit de Componentes Base (NUEVO)

Cada componente del kit DEBE:
1. Vivir en `lib/features/coach_hub/presentation/components/<nombre>/`.
2. Tener un archivo de tokens en `lib/app/theme/tokens/components/`.
3. Cubrir TODOS los estados aplicables (ver tabla de estados por componente).
4. Incluir un widget preview (`<nombre>_preview.dart`) en el mismo directorio.
5. Tener al menos un `widgetTest` en `test/features/coach_hub/presentation/components/`.
6. Documentar su **plan de consumo** (Fase 1 real o kit-foundation con fase nombrada).
7. NUNCA usar hex literales; todos los colores vía tokens de componente.

---

### REQ-CK-001: KpiCard

**Plan de consumo**: Fase 1 shell (top del Dashboard widget y resumen de alumnos).
**Descripción**: Tarjeta métrica con título, valor principal, variación y ícono.

**Estados aplicables**:

| Estado | Descripción |
|--------|-------------|
| normal | Datos cargados y válidos |
| loading | Skeleton con `TreinoShimmer` |
| error | Mensaje de error + ícono, sin valor |
| hover (web) | Wash de fondo sutil animado |

**Tokens**: `KpiCardTokens.of(ctx)` en `lib/app/theme/tokens/components/kpi_card_tokens.dart`.
Expone: `background`, `border`, `borderRadius`, `titleColor`, `valueColor`,
`variationPositiveColor` (→ algún verde semántico o accent), `variationNegativeColor`
(→ `palette.danger`), `iconColor`.

#### Escenario: estado normal

- DADO `KpiCard(title: "Alumnos activos", value: "28", variation: "+3")` en tema oscuro
- CUANDO se renderiza
- ENTONCES DEBE existir un `Text` con "28" y un `Text` con "Alumnos activos"
- Y el fondo DEBE usar `KpiCardTokens.of(ctx).background`

#### Escenario: estado loading

- DADO `KpiCard` con `isLoading: true`
- CUANDO se renderiza
- ENTONCES DEBE existir un widget `TreinoShimmer` u otro skeleton
- Y NO DEBEN existir widgets `Text` con el valor numérico

#### Escenario: estado error

- DADO `KpiCard` con `error: "Sin datos"` e `isLoading: false`
- CUANDO se renderiza
- ENTONCES DEBE existir un widget `Text` o ícono indicando el error
- Y NO DEBE renderizarse el valor numérico principal

#### Escenario: hover web

- DADO `KpiCard` en desktop con cursor encima
- CUANDO `MouseRegion.onEnter` se dispara
- ENTONCES el fondo DEBE transicionar con animación basada en `AppMotionTokens`

#### Escenario: cero hex en tokens

- DADO `kpi_card_tokens.dart`
- CUANDO se ejecuta el test de lint hex
- ENTONCES NO DEBE existir ningún `Color(0x...)`

---

### REQ-CK-002: SectionHeader

**Plan de consumo**: Fase 1 shell (cabeceras de cada sección del contenido).
Ya existe `lib/features/coach_hub/presentation/shell/section_header.dart` como
widget básico. DEBE ser **reemplazado** por la versión del kit que añade:
estados disabled y acción opcional (botón de texto a la derecha).

**Estados aplicables**:

| Estado | Descripción |
|--------|-------------|
| normal | Título solo |
| con acción | Título + botón de texto derecha |
| disabled | Título atenuado (`textMuted`) |

**Tokens**: `SectionHeaderTokens.of(ctx)` expone `titleColor`, `actionColor`,
`disabledColor`, `fontSize`, `fontFamily`, `fontWeight`.

#### Escenario: normal — solo título

- DADO `SectionHeader(title: "GESTIÓN")`
- CUANDO se renderiza
- ENTONCES DEBE existir un `Text` con "GESTIÓN", fontWeight 700, fontFamily Barlow Condensed
- Y el color DEBE ser `SectionHeaderTokens.of(ctx).titleColor`

#### Escenario: con acción

- DADO `SectionHeader(title: "ALUMNOS", action: TextButton(...))`
- CUANDO se renderiza
- ENTONCES DEBE existir el botón de acción a la derecha del título

#### Escenario: disabled

- DADO `SectionHeader(title: "PRÓXIMAMENTE", disabled: true)`
- CUANDO se renderiza
- ENTONCES el color del texto DEBE ser `SectionHeaderTokens.of(ctx).disabledColor`

---

### REQ-CK-003: ListRow

**Plan de consumo**: Kit-foundation; consumidor directo: Fase 3 (Alumnos), Fase 7 (Biblioteca).
**Descripción**: Fila de lista horizontal con leading (avatar/ícono), título,
subtítulo opcional, trailing (badge/acción) y estados completos.

**Estados aplicables**:

| Estado | Descripción |
|--------|-------------|
| normal | Fila con datos |
| hover (web) | Wash de fondo animado |
| pressed | Feedback táctil vía `TreinoTappable` |
| disabled | Todo atenuado, no tappable |
| loading | Skeleton con `TreinoShimmer` |

**Tokens**: `ListRowTokens.of(ctx)` expone `background`, `hoverBackground`,
`titleColor`, `subtitleColor`, `disabledColor`, `borderRadius`, `height`.

#### Escenario: normal con leading y trailing

- DADO `ListRow(leading: avatar, title: "Lucía Fernández", subtitle: "Plan Pro")`
- CUANDO se renderiza
- ENTONCES DEBE existir `Text("Lucía Fernández")` y `Text("Plan Pro")`
- Y el leading widget DEBE estar a la izquierda del título

#### Escenario: disabled

- DADO `ListRow` con `disabled: true`
- CUANDO se toca el widget
- ENTONCES NO DEBE dispararse ningún callback
- Y el color de título DEBE ser `ListRowTokens.of(ctx).disabledColor`

#### Escenario: loading

- DADO `ListRow` con `isLoading: true`
- CUANDO se renderiza
- ENTONCES DEBE existir `TreinoShimmer` ocupando el espacio del contenido

#### Escenario: hover

- DADO `ListRow` en desktop con cursor encima
- CUANDO `MouseRegion.onEnter` se dispara
- ENTONCES el fondo DEBE transicionar a `ListRowTokens.of(ctx).hoverBackground`
  con animación desde `AppMotionTokens`

---

### REQ-CK-004: FilterChips

**Plan de consumo**: Kit-foundation; consumidor directo: Fase 3 (Alumnos — filtro por estado).
**Descripción**: Grupo de chips seleccionables, selección simple o múltiple.

**Estados aplicables por chip**:

| Estado | Descripción |
|--------|-------------|
| normal | No seleccionado |
| selected | Seleccionado con accent |
| hover (web) | Wash sutil |
| disabled | Atenuado, no interactivo |
| focus | Ring de foco visible (accesibilidad teclado) |

**Tokens**: `FilterChipTokens.of(ctx)` expone `defaultBackground`,
`defaultForeground`, `selectedBackground` (→ `accent.withOpacity(0.15)`),
`selectedForeground` (→ `accent`), `selectedBorder` (→ `accent`),
`disabledForeground`, `borderRadius` (→ `AppRadius.full`), `hoverBackground`.

#### Escenario: chip seleccionado

- DADO `FilterChip(label: "Activos", selected: true)`
- CUANDO se renderiza
- ENTONCES el color del label DEBE ser `FilterChipTokens.of(ctx).selectedForeground`
- Y DEBE existir un borde o fondo que indique selección

#### Escenario: chip no seleccionado

- DADO `FilterChip(label: "Inactivos", selected: false)`
- CUANDO se renderiza
- ENTONCES el fondo DEBE ser `FilterChipTokens.of(ctx).defaultBackground`

#### Escenario: foco por teclado

- DADO un `FilterChip` enfocado vía Tab
- CUANDO recibe foco
- ENTONCES DEBE ser visible un indicador de foco (ring o resaltado)
  implementado via `FocusableActionDetector` o `Focus` con `onFocusChange`

#### Escenario: chip deshabilitado

- DADO `FilterChip` con `enabled: false`
- CUANDO se toca
- ENTONCES NO DEBE dispararse el callback `onSelected`
- Y el color DEBE ser `FilterChipTokens.of(ctx).disabledForeground`

---

### REQ-CK-005: EmptyState

**Plan de consumo**: Fase 1 shell (contenido vacío en secciones placeholder)
y kit-foundation para Fases 2–12.
**Descripción**: Estado vacío con ícono, título, descripción y CTA opcional.

**Estados aplicables**:

| Estado | Descripción |
|--------|-------------|
| normal | Ícono + título + descripción |
| con CTA | normal + botón de acción |
| loading | Skeleton (raro pero posible) |

**Tokens**: `EmptyStateTokens.of(ctx)` expone `iconColor`, `titleColor`,
`descriptionColor`, `ctaColor`, `iconSize` (48.0).

#### Escenario: normal sin CTA

- DADO `EmptyState(icon: TreinoIcon.emptyBox, title: "Sin alumnos", description: "...")`
- CUANDO se renderiza
- ENTONCES DEBEN existir los widgets de ícono, título y descripción
- Y NO DEBE existir ningún botón de acción

#### Escenario: con CTA

- DADO `EmptyState(title: "...", cta: ElevatedButton(...))`
- CUANDO se renderiza
- ENTONCES DEBE existir el botón de acción debajo de la descripción

---

### REQ-CK-006: CoachHubDataTable

**Plan de consumo**: Kit-foundation; consumidor directo: Fase 3 (Alumnos — tabla de lista),
Fase 9 (Pagos), Fase 10 (Planes).
**Descripción**: Tabla de datos con cabecera ordenable, filas alternadas,
paginación y estados vacío/error/carga.

**Estados aplicables**:

| Estado | Descripción |
|--------|-------------|
| normal | Filas con datos |
| loading | Skeleton de filas con `TreinoShimmer` |
| empty | `EmptyState` embebido |
| error | Mensaje de error con retry |
| hover fila (web) | Wash de fondo en fila hovered |
| sorted | Indicador de columna activa con dirección |

**Tokens**: `CoachHubDataTableTokens.of(ctx)` expone `headerBackground`,
`headerTextColor`, `rowBackground`, `rowAltBackground`,
`rowHoverBackground`, `borderColor`, `sortIndicatorColor`,
`borderRadius`, `cellPaddingH`, `cellPaddingV`.

#### Escenario: cabecera ordenable

- DADO `CoachHubDataTable` con columna "Nombre" sorteable
- CUANDO se toca el header "Nombre"
- ENTONCES DEBE dispararse el callback `onSort` con el nombre de columna
- Y DEBE mostrarse un indicador de dirección (asc/desc)

#### Escenario: estado loading

- DADO `CoachHubDataTable` con `isLoading: true`
- CUANDO se renderiza
- ENTONCES DEBE existir al menos 3 filas skeleton con `TreinoShimmer`
- Y NO DEBEN existir filas con datos reales

#### Escenario: estado empty

- DADO `CoachHubDataTable` con `rows: []` y `isLoading: false`
- CUANDO se renderiza
- ENTONCES DEBE renderizarse un `EmptyState` dentro de la tabla

#### Escenario: estado error

- DADO `CoachHubDataTable` con `error: "Error de red"` e `isLoading: false`
- CUANDO se renderiza
- ENTONCES DEBE existir un widget con el mensaje de error y un botón de retry

#### Escenario: hover de fila en desktop

- DADO una fila de datos en desktop
- CUANDO el cursor entra en la fila
- ENTONCES el fondo de esa fila DEBE transicionar a `rowHoverBackground`
  con animación desde `AppMotionTokens`

---

### REQ-CK-007: Dialog

**Plan de consumo**: Kit-foundation; consumidor directo: Fase 3 (confirmar baja de alumno),
Fase 9 (confirmar pago).
**Descripción**: Diálogo modal reutilizable con título, contenido, acciones y
estados de confirmación/alerta.

**Estados aplicables**:

| Estado | Descripción |
|--------|-------------|
| normal | Título + contenido + acciones |
| destructive | CTA principal en color danger |
| loading | Botón CTA con spinner, no interactivo |
| error inline | Mensaje de error dentro del diálogo |

**Tokens**: `CoachHubDialogTokens.of(ctx)` expone `background`, `titleColor`,
`contentColor`, `borderRadius` (→ `AppRadius.lg`), `overlayColor`
(→ `palette.scrimDark`), `destructiveColor` (→ `palette.danger`).

#### Escenario: diálogo normal visible

- DADO `TreinoDialog(title: "Confirmar", content: Text("¿Seguro?"), actions: [...])`
- CUANDO se muestra via `showDialog`
- ENTONCES DEBEN existir widgets `Text("Confirmar")` y `Text("¿Seguro?")`
- Y el fondo DEBE ser `CoachHubDialogTokens.of(ctx).background`

#### Escenario: variante destructiva

- DADO `TreinoDialog` con `isDestructive: true` y CTA "Eliminar"
- CUANDO se renderiza
- ENTONCES el botón de acción principal DEBE tener color
  `CoachHubDialogTokens.of(ctx).destructiveColor`

#### Escenario: estado loading en CTA

- DADO `TreinoDialog` con `isLoading: true`
- CUANDO se renderiza
- ENTONCES el botón CTA DEBE estar deshabilitado y mostrar un indicador de progreso
- Y NO DEBE cerrarse el diálogo automáticamente

#### Escenario: reduce-motion en animación de apertura

- DADO `MediaQuery.disableAnimations = true`
- CUANDO se abre `TreinoDialog`
- ENTONCES la animación de apertura DEBE tener duración `Duration.zero`

---

## Dominio D — Gates de Aceptación (transversal)

### REQ-SH-090: Flutter analyze — baseline intacto

Después de todos los cambios de Fase 1, `flutter analyze` DEBE retornar
exactamente 0 issues NUEVOS sobre la baseline de 42 pre-existentes.

#### Escenario: analyze sin regresión

- DADO el codebase con Fase 1 aplicada
- CUANDO se ejecuta `flutter analyze`
- ENTONCES el número de issues DEBE ser ≤ 42 (la baseline pre-existente)

---

### REQ-SH-091: Suite de tests verde

`flutter test` DEBE pasar con 0 failures. Los tests de shell existentes
(`coach_hub_scaffold_test.dart`, `coach_hub_sidebar_test.dart`,
`coach_hub_top_bar_test.dart`, `responsive_breakpoints_test.dart`,
`sidebar_registry_test.dart`, `sidebar_collapsed_provider_test.dart`) DEBEN
actualizarse conscientemente cuando los cambios visuales o de comportamiento de
Fase 1 los rompan — NO DEBEN ignorarse ni borrarse.

#### Escenario: tests existentes actualizados

- DADO los 6 archivos de test del shell
- CUANDO se ejecuta `flutter test`
- ENTONCES todos pasan con las assertions actualizadas para Fase 1
- Y ningún archivo de test DEBE estar eliminado

---

### REQ-SH-092: Responsive verificado en desktop y narrow

El shell DEBE verse correcto a 1440 px (desktop) y a 900 px (compact).
A 900 px el sidebar DEBE estar colapsado (72 px) y el área de contenido
DEBE llenar el espacio restante sin overflow.

#### Escenario: sin overflow en compact

- DADO viewport de 900 px de ancho
- CUANDO se renderiza `CoachHubScaffold`
- ENTONCES NO DEBE existir ningún `RenderFlex` overflow
- Y el sidebar DEBE tener 72 px de ancho

---

### REQ-SH-093: Cero hex literales nuevos en scope de Fase 1

Ningún archivo nuevo ni modificado en el scope de Fase 1 DEBE introducir
literales `Color(0x...)`.

#### Escenario: lint hex pasa

- DADO todos los archivos en scope de Fase 1
- CUANDO se ejecuta `test/theme/no_hex_literals_test.dart`
- ENTONCES el test DEBE pasar sin matches en archivos de Fase 1

---

### REQ-SH-094: Ambos temas visualmente correctos

El shell y todos los componentes del kit DEBEN verse profesionales en modo dark
Y en modo light. Ningún elemento DEBE quedar invisible o sin contraste suficiente
en ninguno de los dos modos.

#### Escenario: light mode sin widgets invisibles

- DADO `MaterialApp` con `AppTheme.light`
- CUANDO se renderiza `CoachHubScaffold` con un ítem activo
- ENTONCES el ítem activo DEBE ser visible y con contraste legible
  (color de texto diferente al fondo del ítem)

---

## Resumen de artefactos nuevos / modificados (Fase 1)

| Archivo | Estado | Descripción |
|---------|--------|-------------|
| `lib/features/coach_hub/presentation/shell/coach_hub_sidebar.dart` | MODIFICADO | Ancho 240, footer usuario, toggle footer, groups headers, badge, hover |
| `lib/features/coach_hub/presentation/shell/coach_hub_top_bar.dart` | MODIFICADO | Título de sección, campo de búsqueda, sin toggle |
| `lib/features/coach_hub/presentation/shell/coach_hub_scaffold.dart` | MODIFICADO | Entrance motion |
| `lib/features/coach_hub/presentation/shell/mobile_banner.dart` | MODIFICADO | Fix spacing 24→20 |
| `lib/features/coach_hub/presentation/shell/section_header.dart` | MODIFICADO | Reemplazado por versión kit |
| `lib/app/theme/tokens/components/coach_hub_layout_tokens.dart` | NUEVO | Constantes de layout |
| `lib/app/theme/tokens/components/coach_hub_sidebar_item_tokens.dart` | NUEVO | Tokens de ítem sidebar |
| `lib/features/coach_hub/presentation/components/kpi_card/` | NUEVO | KpiCard + tokens + preview + test |
| `lib/features/coach_hub/presentation/components/section_header/` | NUEVO | SectionHeader kit + tokens + preview + test |
| `lib/features/coach_hub/presentation/components/list_row/` | NUEVO | ListRow + tokens + preview + test |
| `lib/features/coach_hub/presentation/components/filter_chips/` | NUEVO | FilterChips + tokens + preview + test |
| `lib/features/coach_hub/presentation/components/empty_state/` | NUEVO | EmptyState + tokens + preview + test |
| `lib/features/coach_hub/presentation/components/data_table/` | NUEVO | CoachHubDataTable + tokens + preview + test |
| `lib/features/coach_hub/presentation/components/dialog/` | NUEVO | TreinoDialog + tokens + preview + test |
| `test/features/coach_hub/presentation/shell/` | MODIFICADO | Tests actualizados para cambios Fase 1 |
| `test/features/coach_hub/presentation/components/` | NUEVO | Tests de cada componente del kit |

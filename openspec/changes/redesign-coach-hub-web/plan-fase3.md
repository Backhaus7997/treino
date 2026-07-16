# Plan — Fase 3: Alumnos (lista + detalle)

> **Cambio**: redesign-coach-hub-web · **Fase**: 3 — Sección Alumnos
> **Store**: hybrid · **Fecha**: 2026-07-15
> **Rama**: `feat/coach-hub-alumnos-redesign` (ya checkouteada)
> **Depende de**: Fase 0 (tokens v2) + Fase 1 (shell + kit) — COMPLETAS.
> **Evidencia**: `docs/web-trainer/evidence/fase-3/{before,after}/`

---

## 1. Anatomía objetivo (mockups)

**Lista — `view-general.png`** (tabla, default): header de sección "ALUMNOS"
(Barlow Condensed CAPS) + subtítulo "20 en total · 14 activos" + CTAs a la
derecha (Importar / Invitar / + Nuevo alumno pill mint). Fila de filtros: search
"Buscar por nombre…" + chips con badge (Todos 20 · Activos 14 · Con deuda 2 ·
Pausados 1 · Inactivos 2) + dropdown "Todos los planes" + "Más filtros" + toggle
Tabla/Cards. **Tabla**: columnas ALUMNO (avatar color + nombre + gym) · ESTADO
(dot color + label) · PLAN · OBJETIVO · ADHERENCIA (barra + %) · ÚLTIMO ENTRENO ·
VENCIMIENTO · ACCIONES (íconos). Hover de fila, header CAPS muted.

**Lista — `view-general-cards.png`** (toggle Cards): grilla de cards por alumno
(avatar, nombre, objetivo·plan, barra adherencia %, "Último: …", dot estado).

**Detalle — `resumen.png` / `view-general.png` (breadcrumb) / demás tabs**:
- **Breadcrumb** "Alumnos / Lucía Fernández" + **header de perfil**: avatar
  magenta grande, nombre CAPS, badge estado, meta-chips (Objetivo · Plan · Edad ·
  Inicio · Próximo cobro), CTAs (Chat / Pago / Editar plan pill mint) + toggle
  "Seguimiento".
- **Métricas denormalizadas** (strip tipo KPI): ADHERENCIA 30D · SESIONES/SEM ·
  VOLUMEN TOTAL · PESO CORPORAL (o STREAK/SESIONES/VENCIMIENTO/DEUDA según tab).
- **Tab bar** CAPS: Resumen · Entrenamiento(s) · Nutrición · Progreso · Pagos ·
  Historial · Chat · Notas privadas · Archivos · Seguimiento.
- **Resumen**: 4 KPI cards + "ÚLTIMA SESIÓN" card (ejercicios + deltas) +
  "ADHERENCIA · 12 SEMANAS" heatmap + columna derecha (Datos personales, Nota
  fijada, Próxima sesión).
- **Progreso** (`progreso.png`): 4 KPI cards (peso/%grasa/cintura/1RM con delta) +
  line/area chart "EVOLUCIÓN DE CARGAS" con dropdown de ejercicio.
- **Entrenamiento** (`entrenamiento.png`): card rutina activa (días) + chart
  "EVOLUCIÓN POR EJERCICIO" + tabla "HISTORIAL DE SESIONES".
- **Nutrición** (`nutricion.png`): card plan activo (kcal + macros con barras) +
  card "ADHERENCIA NUTRICIÓN · 7 DÍAS" (heatmap + cargas pendientes de revisar).
- **Historial** (`historial.png`): timeline por mes con dots mint.
- **Notas privadas** (`notas-privadas.png`): lista de notas con tag + timestamp.
- **Archivos** (`archivos.png`): lista de documentos con ícono + peso + fecha.

## 2. Estado actual del código

- **`alumnos_screen.dart`** (658 L): roster real cableado a
  `trainerLinksStreamProvider` + `userPublicProfilesBatchProvider` +
  `pagosPorCobrarProvider` + `gymsProvider` + `finishedTodayByUidProvider`.
  Columnas REALES: Alumno · Estado · Último entreno · Acciones (Plan/Objetivo/
  Adherencia/Vencimiento y el toggle Cards quedaron diferidos — dependen de data
  inexistente). Enum `AlumnoEstado` + `RosterFiltro` + `estadoForLink()` +
  `_matchesFiltro()` (lógica de negocio a PRESERVAR). Widgets bespoke:
  `_FilterBar`/`_Chip`, `_SearchField`, `_RosterHeaderRow`, `_RosterRow`,
  `_Avatar`, `_EstadoBadge`, `_RowActions`.
- **`alumno_detail_screen.dart`** (6054 L, monolito): `DefaultTabController` de 11
  tabs. Widgets privados por tab: `_Header`/`_BackLink`/`_Tabs`/`_MetricChip`
  (chrome), `_ResumenTab` (+ `_MetricCard`, `_DatosPersonalesCard`, `_NoteCard`,
  `_ProxSesionCard`, `_UltimaSessionCard`, `_AdherenciaHeatmap`), `_ProgresoTab`,
  `_MedicionesTab` (+ toggle, listas antropo/rendimiento, dialogs),
  `_EntrenamientoTab` (+ `_RutinaCard`, `_HistorialTable`), `_HistorialTab`,
  `_NutricionTab` (+ editores), `_NotasPrivadasTab`, `_ArchivosTab`,
  `_SeguimientoTab`, `_PagosTab`, `_ChatTab`.
- **`resumen_metrics.dart`** (219 L): cálculo PURO (no tocar salvo métrica nueva).
- **Violaciones/oportunidades**: **33 ocurrencias** de `CircularProgressIndicator`/
  `.when` seco en el detalle + **2** en el roster (links + perfiles) →
  `TreinoStateSwitcher` + shimmer. Cero uso de `TreinoStateSwitcher`/`TreinoShimmer`/
  `TreinoFadeSlideIn`. Chips bespoke (`_Chip`) → `TreinoFilterChips`. Tabla inline
  (`_RosterRow` ~200 L) → `CoachHubDataTable`. Cards inline → tokens/`KpiCard`.
  `showDialog(AlertDialog(...))` (`_confirmAction`) → `showTreinoDialog`.

## 3. APIs reales del kit (verificadas)

- `CoachHubDataTable({columns, rows, loading, emptyMessage/emptyIcon/emptyDescription/
  emptyCtaLabel/onEmptyCtaTap, errorMessage, onRetry, sortColumnKey, sortAscending,
  onSort, onRowTap})`. `CoachHubColumn({key,label,sortable,flex})`;
  `CoachHubRow({id, cells: Map<String,String>})`. **Skeleton shimmer, empty, error,
  sort, hover/foco/teclado ya integrados.** LIMITACIÓN: `cells` es **solo String** →
  no renderiza avatar/dot/íconos (ver ADR-A3-02).
- `KpiCard({value, label, delta?, deltaPositive?, sublabel?, loading, onTap?})` —
  skeleton `loading:true`, sin sombra, hover/foco/teclado.
- `TreinoFilterChips({options, selected, onChanged, multiSelect, disabled,
  badgeCounts})` — single/multi, badge numérico, animación selección.
- `TreinoSectionHeader`, `TreinoListRow(loading)`, `TreinoEmptyState`,
  `showTreinoDialog/TreinoDialog` (barrel `coach_hub_widgets.dart`).
- `TreinoStateSwitcher({child, childKey})` — cross-fade; **keys distintas por
  estado OBLIGATORIAS**. `TreinoShimmer({enabled, child})`.
  `TreinoFadeSlideIn({delay, distance, child})` — **prohibido en `ListView.builder`**;
  stagger `AppMotion.stagger(index)`. `TreinoTappable` reemplaza GestureDetector.

## 4. Decisiones de arquitectura (ADR)

- **ADR-A3-01 · Honestidad de datos (dura)**: el roster y los tabs YA están
  cableados a providers reales; el rediseño **NO inventa datos**. **DESCOPEADO**:
  columnas Plan/Objetivo/Adherencia/Vencimiento y el **toggle Tabla/Cards** del
  mockup (dependen de data inexistente + l10n congelado). Se rediseñan las
  columnas REALES (Alumno · Estado · Último entreno · Acciones). *Rechazado*:
  fabricar columnas/cards para pixel-match (viola la norma "todo real").
- **ADR-A3-02 · UNA sola tabla — extender `CoachHubDataTable` con celdas-widget**:
  el roster necesita celdas ricas (avatar, dot de estado, íconos de acción) que el
  `cells: Map<String,String>` no cubre. Se agrega **opcional**
  `CoachHubRow.cellWidgets: Map<String,Widget>` (override de la celda string cuando
  presente; back-compat total: consumidores string-only intactos, p. ej. pagos).
  *Rechazado*: (a) mantener `_RosterRow` bespoke = **segunda tabla** (anti-patrón
  "segundo copy-paste = extraer"); (b) crear un `RichDataTable` nuevo (duplica el
  kit). TDD en el kit; extender sus tests sin romper.
- **ADR-A3-03 · l10n congelado**: `lib/l10n/*` es de USUARIO — PROHIBIDO. Reusar
  `coachHubAlumnos*`, `coachHubAction*`, `coachHubDashboard*` existentes.
  **Cero keys nuevas**; si el mockup trae copy sin key ("Más filtros", "Importar",
  "Cards"), se reusa la más cercana o se omite el adorno.
- **ADR-A3-04 · Extracción incremental por tab**: `alumno_detail_screen.dart`
  (6054 L) se descompone **por tab** (1–2 tabs por WU), extrayendo cada widget a
  `sections/alumnos/widgets/*.dart` y dejando el screen como **raíz de
  composición**. **NO se reescribe lógica de negocio** (providers, cálculos,
  mutaciones) — sólo presentación/motion. *Rechazado*: split big-bang (PR gigante).
- **ADR-A3-05 · Harness de evidencia por fase**: nuevo
  `test/evidence/coach_hub_alumnos_evidence_test.dart` (patrón de
  `coach_hub_dashboard_evidence_test.dart`: FontLoader `test/fonts/` + Phosphor,
  providers fake POBLADOS, guard `EVIDENCE`, comparador a `fase-3/<dir>/`),
  montando el roster REAL (`/alumnos`) **y** el detalle REAL (`/alumnos/:id`) en el
  shell. Matriz dark/light × 1440×900 y 420×900. *Rechazado*: reusar el harness de
  dashboard (ruta y contenido equivocados).
- **ADR-A3-06 · Exclusiones PROHIBIDAS**: fuera de scope
  `routine_editor/routine_web_editability.dart` y `routine_editor_web_screen.dart`
  (importados por el detalle), sus tests, `exercise_picker_dialog.dart`,
  `trainer_profile_view.dart`, `lib/l10n/*`. Los CTAs "Editar plan"/"Asignar
  rutina"/"Editar" se **re-estilan in-place** en `alumno_detail_screen.dart`, pero
  su navegación y el editor destino **no se tocan**.
- **ADR-A3-07 · Honestidad de alcance / Fase 3b**: la sección tiene 11 tabs +
  roster → excede 9 WUs. Se prioriza **roster + Resumen(datos) + Mediciones +
  Progreso + Entrenamientos + Historial + Nutrición**. **Diferido a Fase 3b**
  (documentado, no rediseñado): **Notas privadas · Archivos · Seguimiento · Pagos ·
  Chat** (Pagos/Chat ya reusan kits de sus secciones; los otros 3 son de menor
  tráfico). La evidencia AFTER capturará esos tabs aún en estilo previo — aceptado
  y anotado. *Rechazado*: meter los 11 tabs en una fase (overload de reviewer,
  budget 400 líneas reventado).
  - **Actualización WU-07b**: el budget de ~400 líneas alcanzó para Historial
    (timeline por mes, `HistorialTimeline`) **+ Archivos** (`TreinoListRow`,
    ícono+peso+fecha) además de Entrenamientos (WU-07a). **Notas privadas**
    queda pendiente — no entró en el budget del WU y sigue diferida a Fase 3b
    (mismo criterio: menor tráfico, requiere anatomía nueva — lista de notas
    con tag+timestamp — que el text-area actual no cubre).
- **ADR-A3-08 · `DefaultTabController` preservado**: se conserva
  `DefaultTabController` + `TabBarView`; `_Tabs` se re-estila con tokens
  (`TreinoTappable`/foco), no se reemplaza por estado propio. *Rechazado*: tab state
  bespoke (rompe deep-link y tests existentes).
- **ADR-A3-09 · Tests existentes se EXTIENDEN**: `alumnos_screen_test`,
  `alumno_detail_screen_test`, `datos_personales_card_test`, `mediciones_tab_test`,
  `nutricion_tab_test`, `archivos_tab_test`, `historial_tab_test`,
  `notas_privadas_tab_test`, `seguimiento_tab_test` conservan TODAS sus aserciones.
  Algunos arrastran warnings del **baseline 42** — **no** arreglarlos ni
  empeorarlos; los nuevos widgets extraídos van con **cero issues nuevos**.

## 5. Mapa de motion

- `TreinoStateSwitcher` (keys por estado) en cada `.when` async visible: roster
  (links + perfiles), header del detalle (perfil/link/billing), Resumen (métricas),
  Mediciones (antropo/rendimiento), Progreso (charts), Entrenamientos, Historial,
  Nutrición.
- `TreinoShimmer` skeletons: `CoachHubDataTable(loading:true)` (roster + historial);
  `KpiCard(loading:true)` (strip de Resumen/Progreso + métricas del header);
  `TreinoListRow(loading:true)`/skeleton bespoke para listas de tab.
- `TreinoFadeSlideIn` staggered SÓLO en secciones eager top-level (bloque
  header/filtros/search del roster, grilla de cards de Resumen, headers de sección
  de cada tab). **Nunca** en filas de la `CoachHubDataTable` ni en `ListView.builder`
  (stream re-emite → re-mount → re-anima).
- `TreinoFilterChips` (animación de selección integrada) + toggle segmentado de
  Mediciones animado. `TreinoTappable` en filas (vía `onRowTap`), CTAs del header y
  cards; **no** envolver `IconButton`/`OutlinedButton` existentes (doble recognizer).
- Todo respeta `AppMotion.reduceMotion` (ya cableado en el kit).

## 6. Alcance de archivos

**En scope**:
- `lib/features/coach_hub/presentation/sections/alumnos/alumnos_screen.dart` (raíz)
- `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart` (raíz)
- `lib/features/coach_hub/presentation/sections/alumnos/widgets/*.dart` (NUEVOS, extracción)
- `lib/features/coach_hub/presentation/widgets/data_table/coach_hub_data_table.dart` (+ tokens) — WU-02
- `test/features/coach_hub/presentation/sections/alumnos/*` (TDD, extender)
- `test/features/coach_hub/presentation/widgets/data_table/*` (TDD, WU-02)
- `test/evidence/coach_hub_alumnos_evidence_test.dart` (NUEVO)

**PROHIBIDO / fuera de scope**: `lib/l10n/*`, `routine_editor/*` (incl.
`routine_web_editability.dart`, `routine_editor_web_screen.dart`) y sus tests,
`exercise_picker_dialog.dart`, `trainer_profile_view.dart`, y todo USER-file del
contrato. **Diferido a Fase 3b**: tabs Notas privadas / Seguimiento / Pagos /
Chat (Archivos se rediseñó en WU-07b, ver ADR-A3-07).

## 7. Work Units (secuenciales)

- **WU-01** Evidencia BEFORE (harness roster + detalle, providers fake, captura
  `fase-3/before/`, commit).
- **WU-02** Kit enabler: `CoachHubDataTable` celdas-widget (`CoachHubRow.cellWidgets`,
  back-compat), TDD + extender tests del data table.
- **WU-03** Roster (`alumnos_screen`): `CoachHubDataTable` (celdas ricas: avatar/dot/
  acciones) + `TreinoFilterChips` (badge counts) + search + `TreinoSectionHeader` +
  `TreinoStateSwitcher`×2 + shimmer + empty/error + stagger + dark/light/responsive.
- **WU-04** Chrome del detalle: breadcrumb + `_Header` + strip de métricas (`KpiCard`)
  + `_Tabs` tokenizado → extraer a `widgets/`; `TreinoStateSwitcher` en carga de
  perfil; `showTreinoDialog` reemplaza `_confirmAction`.
- **WU-05** Tab Resumen: 4 `KpiCard` + Última sesión + heatmap 12 sem + Datos
  personales + Nota + Próxima sesión → extraer a `widgets/`; StateSwitcher + shimmer
  + stagger.
- **WU-06** Tabs Mediciones + Progreso: toggle segmentado, listas antropo/rendimiento,
  charts con StateSwitcher/shimmer → extraer a `widgets/`.
- **WU-07** Tabs Entrenamientos + Historial + Archivos: card rutina + chart evolución +
  historial con `CoachHubDataTable` (WU-07a); timeline por mes (`HistorialTimeline`)
  + lista de archivos vía `TreinoListRow` (WU-07b) → extraer a `widgets/`. Notas
  privadas no entró en el budget del WU-07b — sigue diferida a Fase 3b
  (ADR-A3-07).
- **WU-08** Tab Nutrición: plan activo + macros (barras) + adherencia 7d + cargas
  pendientes, StateSwitcher → extraer a `widgets/`.
- **WU-09** Evidencia AFTER + gates full (regenerar `fase-3/after/`, **FULL
  `flutter test` + `flutter analyze` baseline 42**, commit final + commit de este
  `plan-fase3.md` + registrar Fase 3b pendiente).

## 8. Gates por WU

TDD estricto (`flutter test`): test que falla primero para cada comportamiento
nuevo, en el **mismo commit**. Tests targeted durante dev; **FULL `flutter test` +
`flutter analyze` (baseline 42, cero nuevos) al cierre (WU-09)**. Nunca dos comandos
flutter en paralelo. Conventional commits, work-unit commits, sin Co-Authored-By.
Tree limpio de cambios propios al retornar cada WU (commit o revert — jamás revert de
archivos de usuario).

## 9. Review Workload Forecast

- Estimación: ~9 slices encadenados; cada WU ≈ 120–380 líneas (roster y Resumen son
  los más pesados por extracción + celdas-widget).
- `400-line budget risk`: **Medium** (WU-03 y WU-05 rozan el techo por extracción).
- `Chained PRs recommended`: **Yes** (un PR por WU sobre la rama de fase).
- `Decision needed before apply`: **No** (los WUs ya vienen en slices autónomos).

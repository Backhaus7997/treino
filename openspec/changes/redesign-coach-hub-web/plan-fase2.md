# Plan — Fase 2: Dashboard ("Hoy")

> **Cambio**: redesign-coach-hub-web · **Fase**: 2 — Dashboard landing ("Hoy")
> **Store**: hybrid · **Fecha**: 2026-07-15
> **Rama**: encadenada `feat/coach-hub-dashboard-redesign` sobre la de Fase 1
> **Depende de**: Fase 0 (tokens v2) + Fase 1 (shell + kit) — ambas COMPLETAS.

> NOTA DE RESOLUCIÓN: la invocación llegó con placeholders `undefined` (nombre
> de fase, ruta de sección, ruta de mockups). Se resolvió por contexto: Fase 1
> ya tiene evidencia (`docs/web-trainer/evidence/fase-1/{before,after}`) y
> artefactos (`*-fase1`); el roadmap de `proposal.md` y la decisión #225 marcan
> **Dashboard** como la fase siguiente. Sección: `lib/features/coach_hub/presentation/sections/dashboard/`.
> Mockups: `docs/web-trainer/screens/dashboard/{welcome-card,resto-cards}.png`.
> Evidencia de esta fase: `docs/web-trainer/evidence/fase-2/{before,after}/`.

---

## 1. Anatomía objetivo (mockups)

**welcome-card.png** (zona hero, arriba):
- **Alert banner**: card oscura, caja de ícono mint (rayo), título CAPS
  "3 ALUMNOS NECESITAN TU ATENCIÓN HOY", subtexto resumido, pill "Revisar todo"
  a la derecha.
- **Welcome card**: card grande con glow mint sutil abajo. Label
  "VIERNES · 30 ABR 2026" (CAPS, muted). Heading "BUENAS, **JOACO**" (JOACO en
  mint, Barlow Condensed 700). Línea resumen con números resaltados. Fila de
  acciones: "+ Nuevo alumno" (pill mint filled), "Crear rutina" (pill outline +
  icono), "Mensajes (5)" (ghost). A la derecha: anillo adherencia 84% mint con
  labels "ADHER." / "PROMEDIO".

**resto-cards.png** (grilla dashboard):
- **KPI strip** (4 cards): "ALUMNOS ACTIVOS" 28 ↑+3 · "INGRESOS DEL MES"
  $412.000 ↑+18% · "ADHERENCIA PROMEDIO" 74% ↓-3% · "POR COBRAR" $86.000. Cada
  card: label CAPS muted (arriba), valor grande, delta (↑ mint / ↓ rojo),
  sublabel muted.
- **Columna izquierda**: card "PENDIENTES DE HOY" (feed de acciones con ícono
  color + pill de acción) y card "ADHERENCIA · ÚLTIMOS 28 DÍAS" (line/area chart
  mint vs mes anterior).
- **Columna derecha**: "PRÓXIMAS SESIONES" (hora mint + avatar inicial + nombre
  + subtítulo), "VENCIMIENTOS · 7 DÍAS" (avatar + nombre + plan/monto + badge de
  días + botón "Ver todos los pagos"), "3 ALUMNOS INACTIVOS" (header rojo +
  cluster de avatares + pill "Revisar").

## 2. Estado actual del código

`coach_hub_dashboard_screen.dart` (1202 L, monolito con widgets privados):
`_AlertBanner`, `_WelcomeCard` (+ `_QuickAction`, `_AdherenceRing`),
`_KpiStrip` (usa `KpiTile` importado de **pagos**), `_TwoColumnLayout`,
`_ProximasSesiones` (+ `_SesionRow`), `_Vencimientos7d` (+ `_VencimientoRow`),
`_InactivosSection` (+ `_InactivoRow`), `_PendingTodaySection`
(+ `_PendingRequestsList`, `_PendingRequestTile`), `_SectionError`.

Providers reales ya cableados: `trainerLinksStreamProvider`,
`pagosBucketsProvider`, `inactivosProvider`, `aggregateAdherenceProvider`,
`trainerAppointmentsStreamProvider` (family), `totalUnreadCountProvider`,
`userPublicProfileProvider` (family), `userProfileProvider`, `currentUidProvider`.

**Violaciones / oportunidades de rediseño**:
- `CircularProgressIndicator` crudo en `_ProximasSesiones`, `_Vencimientos7d`,
  `_PendingRequestTile` (busy) → `TreinoStateSwitcher` + skeleton `TreinoShimmer`.
- Cards inline `Container(bgCard + border + radius)` repetidas ~5× → tokens
  consistentes; spacing con 16/24 crudos (líneas 72,77,99,101,…) → escala
  8/12/14/18/20 (`AppSpacing`).
- Labels de sección con `GoogleFonts.barlowCondensed` inline repetidos →
  `TreinoSectionHeader`.
- KPI strip usa `KpiTile` (de pagos) → migrar a kit `KpiCard` (delta + skeleton).
- Cero motion: sin `TreinoStateSwitcher`, sin shimmer, sin `TreinoFadeSlideIn`,
  sin `TreinoTappable`.
- Empty states con `Text` plano → `TreinoEmptyState`.

## 3. APIs reales del kit (verificadas)

- `KpiCard({value, label, delta?, deltaPositive?, loading, onTap?})` — skeleton
  `loading:true`, hover/focus/teclado vía `TreinoInteractiveState`, sin sombra.
- `TreinoSectionHeader({title, count?, action? (label+onTap), disabled})` —
  título auto-UPPERCASE, acción con foco/teclado.
- `TreinoListRow({title, subtitle?, leading?, trailing?, onTap?, loading, dense})`
  — skeleton `loading:true`, hover/pressed.
- `TreinoEmptyState({icon, title, description?, ctaLabel?, onCtaTap?, loading})`
  — entra con `TreinoFadeSlideIn`.
- `TreinoStateSwitcher({child, childKey})` — cross-fade loading→data→error;
  **keys distintas por estado obligatorias**.
- `TreinoShimmer({enabled, child})` — barrido; `enabled:false` para error/null.
- `TreinoFadeSlideIn({delay, distance, child})` — one-shot; **prohibido en
  `ListView.builder`**; stagger con `AppMotion.stagger(index)`.
- `TreinoTappable({onTap, onLongPress?, child})` — **REEMPLAZA** GestureDetector/
  InkWell, nunca envuelve un botón que ya maneja taps.
- Barrel: `lib/features/coach_hub/presentation/widgets/coach_hub_widgets.dart`.

## 4. Decisiones de arquitectura (ADR)

- **ADR-D2-01 · Honestidad de datos (dura)**: el dashboard ya está cableado a
  providers reales; el rediseño **NO inventa datos**. Se **DESCOPEA de esta
  fase**: (a) el line/area chart "ADHERENCIA · ÚLTIMOS 28 DÍAS" (no existe
  provider de serie temporal; solo `aggregateAdherenceProvider` que da un valor
  único) y (b) el feed rico de "PENDIENTES DE HOY" del mockup (mensajes, fotos de
  comida, dolor, etc. — requiere agregación nueva). Se rediseña el "Pendientes"
  REAL basado en solicitudes. *Rechazado*: fabricar datos para calzar el mockup
  pixel-a-pixel (viola la norma "todo real/honesto"). El chart y el feed quedan
  anotados para una fase de datos futura.
- **ADR-D2-02 · Reuso del kit**: adoptar `KpiCard`, `TreinoListRow`,
  `TreinoSectionHeader`, `TreinoEmptyState`, `TreinoStateSwitcher`,
  `TreinoShimmer`, `TreinoFadeSlideIn`, `TreinoTappable`. *Rechazado*: crear un
  Card bespoke del dashboard (duplicaría el kit; "segundo copy-paste = extraer").
- **ADR-D2-03 · l10n congelado**: `lib/l10n/*` es de USUARIO — PROHIBIDO tocar.
  Reusar keys existentes (`dashboardProximasSesionesSectionLabel`,
  `dashboardVencimientosTitle`, `dashboardInactivosTitle`, `dashboardKpi*`, …) y
  literales ya presentes. **Cero keys nuevas.** Si el mockup introduce copy sin
  key (p. ej. "AGENDA", "Marcar todo revisado"), se reusa la key más cercana o se
  omite el adorno; **no** se agregan literales nuevos hardcodeados.
- **ADR-D2-04 · KpiCard según mockup**: el mockup ordena label→valor→delta(+sublabel).
  Antes de tocar, el ejecutor **grepea consumidores de `KpiCard`**; si no rompe a
  nadie, alinea el orden a mockup y agrega `sublabel` opcional (data-honest: solo
  se pasa cuando hay dato real, p. ej. "por cobrar" → vencidos reales). TDD en el
  kit. *Rechazado*: sublabel inline en el strip (rompe el borde de la card).
- **ADR-D2-05 · Extracción incremental**: al rediseñar cada subzona, extraer sus
  widgets a `dashboard/widgets/*.dart` dejando `coach_hub_dashboard_screen.dart`
  como raíz de composición. *Rechazado*: mantener el monolito de 1202 L o hacer
  un split big-bang (PR gigante, riesgoso).
- **ADR-D2-06 · Harness de evidencia por fase**: nuevo
  `test/evidence/coach_hub_dashboard_evidence_test.dart` con comparador a
  `docs/web-trainer/evidence/fase-2/<dir>/`, montando el dashboard REAL con
  providers fake poblados. *Rechazado*: reusar el test de shell (ruta fase-1,
  contenido equivocado).
- **ADR-D2-07 · Anillo de adherencia = gauge**: el `CircularProgressIndicator`
  del welcome card es un medidor determinado (`value: pct`), no un spinner de
  carga (degrada a "--" vía `valueOrNull`). Se conserva como gauge tokenizado; no
  cuenta como violación de "spinner seco".

## 5. Mapa de motion

- `TreinoStateSwitcher` (keys por estado) en cada `.when` async visible:
  Próximas sesiones, Vencimientos, Pendientes (solicitudes), Inactivos.
- `TreinoShimmer` skeletons: `TreinoListRow(loading:true)` para listas;
  `KpiCard(loading:true)` para el KPI strip.
- `TreinoFadeSlideIn` staggered SOLO en secciones eager de nivel superior
  (banner, welcome, KPI strip, headers de columna, cards de la derecha). **Nunca
  en filas data-driven** (se re-emiten por stream → re-mount → re-anima).
- `TreinoTappable` en las pills del welcome card (la primaria mint filled se
  arma como container tokenizado + Tappable) y en CTAs de "Ver todos"/"Revisar"
  (reemplaza el `GestureDetector` de la línea 743). Los `OutlinedButton`/
  `ElevatedButton` existentes NO se envuelven (doble recognizer).
- Todo respeta `AppMotion.reduceMotion` (ya cableado en los widgets del kit).

## 6. Alcance de archivos

**En scope**:
- `lib/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart` (raíz de composición)
- `lib/features/coach_hub/presentation/sections/dashboard/widgets/*.dart` (NUEVOS, extracción incremental)
- `lib/features/coach_hub/presentation/widgets/kpi_card/kpi_card.dart` (+ tokens) — solo si ADR-D2-04 lo requiere
- `test/features/coach_hub/presentation/sections/dashboard/*` (TDD)
- `test/evidence/coach_hub_dashboard_evidence_test.dart` (NUEVO)

**PROHIBIDO / fuera de scope**: `lib/l10n/*` (keys nuevas), cualquier archivo de
`routine_editor` (Fase 5), `exercise_picker_dialog.dart`, y todo lo listado como
USER-files en el contrato. La sección dashboard **no** contiene archivos
prohibidos, pero la congelación de l10n es la restricción activa clave.

## 7. Work Units (secuenciales)

- **WU-01** Evidencia BEFORE (harness + captura + commit).
- **WU-02** Zona hero: alert banner + welcome card (tokens, spacing, Tappable, ring).
- **WU-03** KPI strip → kit `KpiCard` (+ alineación/sublabel data-honest).
- **WU-04** Columna izquierda "Pendientes de HOY" (solicitudes) con kit + motion.
- **WU-05** Columna derecha: Próximas sesiones + Vencimientos + Inactivos.
- **WU-06** Ensamble + motion (stagger, responsive, spacing final, dark+light).
- **WU-07** Evidencia AFTER + gates full (regenerar after, flutter test + analyze 42, commit).

## 8. Gates por WU

TDD estricto (`flutter test`): test que falla primero para cada comportamiento
nuevo, en el mismo commit. Tests targeted durante dev; **FULL `flutter test` +
`flutter analyze` (baseline 42, cero nuevos) al cierre (WU-07)**. Nunca dos
comandos flutter en paralelo. Conventional commits, work-unit commits, sin
Co-Authored-By. Tree limpio de cambios propios al retornar cada WU.

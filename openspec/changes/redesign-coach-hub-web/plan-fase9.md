# Plan Fase 9 — Pagos (rediseño Coach Hub Web)

> Sección objetivo: `lib/features/coach_hub/presentation/sections/pagos/`
> Norte visual: `docs/web-trainer/screens/pagos/pagos.png` (si el mockup y el
> design system chocan en un token, MANDA el design system).
> Evidencia: `docs/web-trainer/evidence/fase-9/{before,after}/`.

## 1. Anatomía objetivo (lectura del mockup)

Pantalla única `/pagos` montada dentro del shell real (`CoachHubScaffold`, sin
Scaffold propio — ADR-CHW-005). De arriba a abajo:

1. **Header de sección**: título `PAGOS` (Barlow Condensed 700 UPPERCASE) +
   subtítulo muted "Cobros, vencimientos e ingresos". A la derecha, en el
   mockup, dos botones: `Exportar` (outline) y `Registrar pago` (accent
   filled).
2. **KPI strip** (4 cards en el mockup): INGRESOS DEL MES `$642k +8%` /
   PENDIENTE COBRAR `$96k` / VENCIDO `$82k` / PROYECTADO MES `$738k +12%`, cada
   una con sub-línea ("14 cobrados", "4 alumnos", "3 alumnos · ~$28k cv", "Si
   todos pagan").
3. **Barra de filtros**: chips `Vencidos·3`, `Por vencer·5`, `Pagados·14`,
   `Todos`, con selector de mes `Abril 2026` a la derecha.
4. **Tabla rica**: columnas ALUMNO (avatar+nombre) · PLAN (badge Premium/Básico)
   · MONTO · VENCIMIENTO (fecha) · ESTADO (dot + badge de color: "Vencido 4d"
   rojo / "En 4 días" verde) · ACCIONES (Recordar con campana + Marcar pagado).
5. **Sidebar**: item `Pagos` con badge numérico `3` (ya existe el slot de badge
   desde Fase 1; falta cablearlo).

## 2. Honestidad de datos (DURA) — qué del mockup es real y qué NO

Datos REALES disponibles (providers ya cableados):
- `trainerPaymentsProvider` → `List<Payment>` (stream Firestore). REAL.
- `pagosBucketsProvider` → vencidos / porVencer / pagados / todos (dueAt-aware,
  ADR-PGW-002 / REQ-VENC-11). REAL.
- `pagosPorCobrarProvider` → cobros pendientes cadence-aware. REAL.
- KPIs derivables: Ingreso del mes (Σ paid del mes), Pendiente cobrar (Σ cobros),
  Vencido (Σ vencidos). REAL. Conteos ("N cobrados", "N alumnos", "N vencidos")
  derivables → sublabels honestos.
- Estado relativo "Vencido {n}d" / "En {n} días" computable desde `dueAt` cuando
  existe; fallback legacy sin días cuando `dueAt == null`. REAL.
- Nombre de alumno + iniciales de avatar desde `userPublicProfilesBatchProvider`.
  REAL (avatar = iniciales, nunca foto inventada).
- Concepto = `Payment.concept`. REAL.
- Mutaciones cableadas: `marcarPagadoDoc` (markManyPaid), `recordar` (chat),
  `registrarPago`/`RegistrarPagoDialog` (add). REALES.

Datos FAKE del mockup → NO se implementan (ADR de honestidad):
- **PROYECTADO MES `$738k`**: proyección sin fuente real → SE ELIMINA. El strip
  queda con las 3 KPI reales.
- **Deltas `+8%` / `+12%`**: no hay comparación mes-contra-mes real → SIN delta.
- **Columna PLAN (Premium/Básico)**: `Payment` no tiene plan comercial ni hay
  modelo cableado → la columna real es CONCEPTO. Se conserva CONCEPTO; NO se
  inventa PLAN.
- **Botón `Exportar`**: no existe mutación/exportador → NO se agrega botón muerto.
- **Selector de mes `Abril 2026`**: `pagosBucketsProvider` no filtra por mes
  (pagados/todos son all-time) → fuera de scope; no se agrega dropdown sin
  backing. Se documenta como diferido.

## 3. Deltas de implementación (actual → objetivo)

| Subzona | Actual | Objetivo |
|--------|--------|----------|
| Header | `Text('PAGOS')` + `TextButton` accent ad-hoc | `TreinoSectionHeader` (título) + subtítulo muted + CTA accent "Registrar pago" (tokens + TreinoInteractiveState); sin Exportar |
| KPI | 3× `KpiTile` container plano (sin loading) | 3× `KpiCard` del kit (Barlow Condensed, hover, shimmer loading, sublabel real); sin Proyectado/deltas; responsive Wrap |
| Filtros | Material `TabBar`/`TabBarView` | `TreinoFilterChips` single-select + `badgeCounts`; estado en `pagosFiltroProvider` |
| Tabla | `PagosWebTable` container plano (sin hover/sort/skeleton/avatar/estado rico) | `CoachHubDataTable` + `cellWidgets` ricos (avatar+nombre, concepto, monto, vencimiento, estado dot+badge, acciones) + sort + skeleton + empty/error |
| Estados | `CircularProgressIndicator` (spinner seco) + `Text` vacío | `TreinoStateSwitcher` (loading↔data↔error) + skeleton shimmer + `TreinoEmptyState` + error con retry |
| Motion | ninguno | chip selection, KpiCard hover, `TreinoFadeSlideIn` staggered en header+KPI, cross-fade de tabla |
| Sidebar badge | `pagosSidebarItems.badgeProvider == null` | cableado a `pagosBadgeCountProvider` (int? = vencidos) — patrón Solicitudes (ADR-F4-04) |

Archivos PROHIBIDOS/intocables relevantes: NINGÚN routine_editor acá. OJO:
`test/features/payments/application/mi_cuota_provider_regression_test.dart` es
archivo de USUARIO — NO tocar; el full test del cierre lo corre pero si falla por
algo ajeno se REPORTA, no se corrige.

## 4. Decisiones (ADR de la fase)

- **ADR-F9-01 (honestidad KPI)**: strip de 3 KPI reales; se descartan Proyectado
  mes y deltas +%. Sublabels solo con conteos reales.
- **ADR-F9-02 (CONCEPTO no PLAN)**: la columna real es CONCEPTO; no se inventa
  columna PLAN comercial.
- **ADR-F9-03 (filas no navegables)**: la tabla NO usa `onRowTap` — las acciones
  viven en la celda ACCIONES (evita conflicto de gestos anidados con los botones).
- **ADR-F9-04 (sin Exportar / sin selector de mes)**: no se agregan controles sin
  backend real; diferidos.
- **ADR-F9-05 (badge = vencidos)**: el badge del sidebar cuenta vencidos (coincide
  con "Pagos · 3" del mockup), patrón `invitacionesPendingCountProvider`.

## 5. Work units (atómicos, secuenciales)

WU-01 Evidencia BEFORE · WU-02 Helpers puros + providers · WU-03 KPI strip →
KpiCard · WU-04 Header → SectionHeader + CTA + motion · WU-05 TabBar →
FilterChips · WU-06 Tabla → CoachHubDataTable (celdas ricas + estados) · WU-07
Acciones de fila (Recordar/Marcar pagado) · WU-08 Badge del sidebar · WU-09
Evidencia AFTER + gates full + commit del plan.

Detalle self-contained en el JSON adjunto al reporte de esta fase (mem
`sdd/redesign-coach-hub-web/plan-fase9`).

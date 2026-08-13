# Plan Fase 10 — Planes comerciales (redesign Coach Hub Web)

> **Cambio**: redesign-coach-hub-web · **Fase**: 10 (Planes comerciales)
> **Fecha**: 2026-07-21 · **Rama**: feat/coach-hub-planes-redesign
> **Tipo de fase**: sección placeholder (`ProximamenteScreen`) → patrón Fase 4/6
> (construir SOLO lo cableado a providers reales + descope honesto por ADR).

---

## 1. Realidad descubierta (censo de la sección)

- **Ruta actual**: `/planes` renderiza `ProximamenteScreen(label: 'Planes comerciales')`.
  Único archivo real: `lib/features/coach_hub/presentation/sections/planes/routes.dart`
  (33 L, placeholder + `SidebarItem` + `TreinoIcon.sidebarPlanes`).
- **Sin tests** en la sección (greenfield salvo el placeholder).
- **NO existe entidad de catálogo de planes comerciales.** Fase 9 ya lo dejó
  asentado: `pagos_web_table.dart` → *"ADR-F9-02: sin columna PLAN (no hay plan
  real)"*. No hay `CommercialPlan` (nombre/descr/precio/features/visibilidad/
  estrella/conversión), ni repositorio, ni colección Firestore, ni mutación.
- **Lo que SÍ es real** (fuentes cableables):
  - `AthleteBilling` (`lib/features/payments/domain/athlete_billing.dart`):
    precio POR ALUMNO — `trainerId`, `athleteId`, `amountArs` (int),
    `cadence ∈ {mensual, semanal, porSesion, suelto}`, `updatedAt`. Colección
    `athlete_billing`, doc id determinista `{trainerId}_{athleteId}`.
    `BillingRepository` solo expone `watch(trainerId, athleteId)` (doc único) y
    `setConfig` — **no hay list trainer-wide**.
  - Reglas Firestore `athlete_billing`: `allow read if uid == trainerId || uid
    == athleteId`. Una query `where('trainerId', == uid)` **está permitida sin
    tocar `firestore.rules`** (el filtro satisface la constraint de la regla).
  - `Payment` (`payments/{autoId}`, `trainerPaymentsProvider`) — registros de
    cobro reales (usados por Pagos).
  - Roster del trainer: `trainerLinksStreamProvider`
    (`lib/features/coach/application/trainer_link_providers.dart`).
  - `firestoreProvider`, `currentUidProvider`, `userProfileProvider`,
    `userPublicProfilesBatchProvider`.

## 2. Anatomía objetivo de los mockups (norte visual)

- `view-general.png`: header "PLANES COMERCIALES" + CTA "+ Nuevo" · strip de 4
  KPI (Plan estrella / Precio promedio / Conversión reciente / Crecimiento
  mensual) · "TUS PLANES" + subtítulo · filter tabs (Todos / Públicos /
  Privados / Archivados) · grid 3-col de **cards de plan** (ícono estrella
  coloreado, badge ESTRELLA/PRIVADO/10% OFF, nombre UPPERCASE, descripción,
  **precio grande Barlow Condensed** + cadencia, "N Alumnos", badge
  PÚBLICO/PRIVADO).
- `crear-plan.png`: form Crear/Editar — Información general (nombre, descr,
  duración, cobro cada, precio, moneda) · Tipo de plan (pago / prueba / gratis)
  · ¿Qué incluye? (features editables) · Precio del plan + GUARDAR · Vista
  previa.

## 3. Decisión de arquitectura (ADRs)

### ADR-F10-01 — Descope del catálogo comercial; construir "Tus tarifas" derivado de datos reales

**Contexto**: el mockup describe un catálogo de planes vendibles que el trainer
DEFINE (nombre, features, visibilidad, checkout) con KPIs de conversión/
crecimiento y un form de creación con moneda/tipo de plan/precio final. Ese
backend NO existe y crearlo implica un backend de precios/checkout — **fuera de
scope** (pasarelas = Fase 7 del roadmap general; el contrato de fase lo prohíbe
explícitamente). Precedente: ADR-F9-01 (rechazó KPIs inventados +%/-% y
"Proyectado") y ADR-F9-02 (rechazó la columna PLAN por no ser real).

**Decisión**: NO inventar catálogo/form/checkout. En su lugar, reemplazar el
placeholder por una sección **read-only honesta** que sí está cableada a
providers reales: **"Tus tarifas"**, derivada de `AthleteBilling` agrupada por
`(amountArs, cadence)` a lo largo del roster. El título de sección sigue siendo
"Planes comerciales" (label del sidebar), pero el cuerpo es honesto: son los
precios que el trainer YA cobra, agrupados, sin edición local (el precio de cada
alumno se edita en Alumnos/Pagos, donde ya vive). Un banner informa que el
catálogo de planes vendibles llega más adelante.

**Alternativas rechazadas**:
- *(A) Placeholder pulido "Próximamente"*: no cablea ningún dato real y
  desperdicia la data de billing existente. Rechazada — entrega cero valor.
- *(B) Construir el catálogo completo con un `CommercialPlan` nuevo*: inventa
  backend de precios/visibilidad/checkout. Rechazada — viola el contrato de fase.

### ADR-F10-02 — KPIs y facetas honestos (data-honest, hereda ADR-D2-04/F9-01)

Solo KPIs con fuente real derivada de `AthleteBilling`:
- **Precio promedio**: media de `amountArs` sobre alumnos con tarifa
  configurada (sublabel honesto: "N alumnos con tarifa"; comentar el caveat de
  mezcla de cadencias — definición única y documentada).
- **Alumnos con tarifa**: conteo de alumnos con doc de billing.
- **Tarifas distintas**: conteo de grupos `(amount, cadence)`.

Descartados por falta de fuente: Conversión reciente, Crecimiento mensual, "Plan
estrella / Más elegido" como métrica de marketing. Se conserva un chip honesto
**"Más usada"** sobre el grupo modal (la tarifa con más alumnos), que es
derivable de datos reales.

Facetas del filtro: **por cadencia** (Todas / Mensual / Semanal / Por sesión /
Suelto) — real. NO Públicos/Privados/Archivados (no hay campo de visibilidad).

### ADR-F10-03 — Data access section-local (sin tocar el repo compartido de payments)

El provider trainer-wide (`trainerBillingsProvider`) vive **dentro de la sección
planes** y consume `firestoreProvider` directamente para la query
`athlete_billing where trainerId == uid`, reutilizando el modelo de dominio
`AthleteBilling` (import de payments/domain) sin modificar `BillingRepository`
(archivo compartido con mobile). Fallback documentado si la query se bloqueara
por reglas: fanout por roster (`trainerLinksStreamProvider` → N reads de doc
único vía el path ya permitido por reglas). La lógica de agrupación
(`agruparTarifas`) es una función pura 100% testeable sin Firestore.

### ADR-F10-04 — Contrato de sección y kit (hereda ADR-CHW-005 / ADR-SH-002)

Sin `Scaffold`/`SafeArea` propios (los provee `CoachHubScaffold`). Reutilizar el
kit vía barrel `coach_hub_widgets.dart`: `TreinoSectionHeader`, `KpiCard`,
`TreinoFilterChips`, `TreinoEmptyState`, `TreinoInteractiveState`. La card de
tarifa es un widget nuevo section-local (segundo copy-paste ⇒ extraer, pero acá
es un patrón único de esta sección). Motion obligatorio: `TreinoStateSwitcher`
en el `.when` async, `TreinoShimmer` skeletons, `TreinoFadeSlideIn` staggered en
header/KPI/banner (NUNCA en el grid builder), animación de selección de filtro.
Dark + light pulidos, responsive vía `responsive.dart`.

## 4. Componentes y flujo de datos

```
currentUidProvider ─┐
                    ├─> trainerBillingsProvider (section-local, query athlete_billing)
firestoreProvider ──┘        │  Stream<List<AthleteBilling>>
                             ▼
                    tarifasProvider (derivación pura: agruparTarifas)
                             │  TarifasResumen { grupos:[TarifaGroup], precioPromedio,
                             │                   alumnosConTarifa, tarifasDistintas,
                             │                   cadenciaMasUsada }
                             ▼
   PlanesScreen (ConsumerWidget, sin Scaffold)
     ├─ TreinoSectionHeader "Planes comerciales" + subtítulo + banner descope
     ├─ KPI strip (KpiCard × 3, data-honest, loading→shimmer)
     ├─ TreinoFilterChips (por cadencia, badgeCounts reales)
     └─ Grid de _TarifaCard (TreinoInteractiveState hover, precio Barlow
        Condensed, badge cadencia, "N alumnos", chip "Más usada" en el modal)
        · TreinoStateSwitcher entre filtros · EmptyState honesto · error
```

## 5. Puntos de integración

- `routes.dart`: swap `ProximamenteScreen` → `PlanesScreen` (mismo `coachHubPage`
  wrapper, misma ruta `/planes`, mismo `SidebarItem`). Sin cambios en
  `coach_hub_router.dart` ni `sidebar_registry.dart`.
- Reusa dominio `AthleteBilling` + `BillingCadence` de `features/payments/domain`.
- Evidencia: nuevo harness `test/evidence/coach_hub_planes_evidence_test.dart`
  (patrón `coach_hub_pagos_evidence_test.dart`), goldens a
  `docs/web-trainer/evidence/fase-10/{before,after}/`.

## 6. Archivos PROHIBIDOS / fuera de scope

- La sección NO tiene archivos de `routine_editor` — sin prohibidos locales.
- No tocar: `firestore.rules`, `functions/`, `pubspec.yaml`, `lib/l10n/*`,
  `android/`, `BillingRepository` (compartido — se evita por ADR-F10-03).
- Fuera de scope duro: pasarelas de pago (Mercado Pago/Stripe), form de
  crear/editar plan, catálogo vendible, visibilidad pública/privada, KPIs de
  conversión/crecimiento.

## 7. Riesgos

| ID | Riesgo | Mitigación |
|----|--------|-----------|
| R-1 | La query `athlete_billing where trainerId==uid` podría dar permission-denied si el índice/regla no la cubre en runtime | Validar en apply/verify contra emulador; fallback documentado = fanout por roster (reads de doc único ya permitidos). Unit tests usan datos in-memory (sin reglas). |
| R-2 | Presentar tarifas por-alumno como "planes" puede leerse como catálogo editable → verify podría marcarlo | Cuerpo rotulado "Tus tarifas" + subtítulo + banner de descope explícito; cards read-only sin CTA de edición; sin badges de visibilidad inventados. |
| R-3 | "Precio promedio" mezcla cadencias (mensual vs por sesión) | Definición única documentada en comentario + sublabel honesto "N alumnos con tarifa". |
| R-4 | El harness de evidencia debe evolucionar con el swap de ruta (placeholder→real) sin romper el guard | WU-03 actualiza guard + overrides del harness cuando cambia la ruta; los PNGs BEFORE ya quedaron commiteados en WU-01. |
| R-5 | Corridas largas mueren a mitad | WUs finos (1 subzona c/u), commit incremental por sub-pieza verde. |

## 8. Work Units (resumen)

- **WU-01** — Evidencia BEFORE + harness fase-10 (placeholder). Commit.
- **WU-02** — Data layer: `trainerBillingsProvider` + `agruparTarifas`/
  `tarifasProvider` (TDD puro, sin UI). Commit.
- **WU-03** — `PlanesScreen` shell + KPI strip + banner descope + swap de ruta +
  actualizar guard/overrides del harness (TDD widget). Commit.
- **WU-04** — Grid de tarifas + filtro por cadencia + `_TarifaCard` + estados
  (empty/error) + motion + dark/light + responsive (TDD widget). Commit.
- **WU-05** — Evidencia AFTER + gates full (FULL `flutter test` + analyze 42) +
  commit del `plan-fase10.md`. Commit final.

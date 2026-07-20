# Plan Fase 6 — Nutrición (Coach Hub Web)

> Artefacto de diseño (design/architecture). Fase 6 EN PLANIFICACIÓN.
> Backend activo: hybrid (engram `sdd/redesign-coach-hub-web/plan-fase6` + este archivo).
> El archivo queda SIN commitear; lo commitea el WU final (WU-07).

## 1. Dirección visual (norte)

Mockups leídos como imágenes:

- `docs/web-trainer/screens/nutricion/nutricion.png` — **«EDITOR NUTRICIONAL»**: breadcrumb "Nutrición › Plan semanal" + título CAPS. Header de plan (avatar manzana magenta, "PLAN SEMANAL", subtítulo "Plan nutricional · 2.100 kcal promedio diario", acciones Vista alumno / Duplicar / Guardar). **Tabs de día** (Lunes…Domingo). Columna izquierda: lista de comidas (Desayuno/Almuerzo/Merienda/Cena) con alimentos + gramos (80 g, 30 g) + hora (08:00) + menús "…" + "Agregar alimento"/"Agregar comida". Columna derecha: **4 KPI de macros** (Calorías 2.100 kcal, Proteínas 160 g·30%, Carbohidratos 230 g·45%, Grasas 70 g·25%), **"Configuración del plan"** (objetivo dropdown, calorías diarias, inputs proteínas/carbos/grasas, recomendaciones), **"Recetas frecuentes"** (Pollo a la plancha 330 kcal…). Tab bar inferior Alumno/Nutrición/Entrenamiento.
- `docs/web-trainer/screens/nutricion/meta-diaria.png` — **«META DIARIA DEL PLAN»**: card "KCAL OBJETIVO / DÍA" con slider (1200–3500, 1900). Card "DISTRIBUCIÓN ACTUAL" con **donut de 3 macros** + leyenda (Proteína 165g 35%, Carbohidratos 100g 38%, Grasas 89g 33%). "MACROS (GRAMOS / DÍA)": 3 cards con sliders (Proteína 165 g/día, Carbos 180, Grasas 69) + hint "Sugerido: 1.8-2.2 g/kg". "PLAN ACTUAL VS. OBJETIVO": 4 barras de progreso (Kcal 1910/1900, Proteína 151/165g, Carbos 208/180g, Grasas 53/69g).

Norte visual honesto: reproducir la **estructura de una superficie de gestión de nutrición** (header CAPS + chips de filtro + lista de tarjetas por alumno con estado de plan) con el kit v2, dark+light pulidos, motion de estados y selección. **NO** reproducir el editor semanal con macros/kcal ni la meta-diaria: **no existen en el modelo** (ver ADR-F6-02). Cuando mockup y design system chocan, **MANDA el design system** (colores/spacing/radii de tokens, no los del PNG).

## 2. Realidad del código (censo de la sección)

**La sección es un placeholder puro.** `lib/features/coach_hub/presentation/sections/nutricion/` contiene SOLO `routes.dart`, que renderiza `ProximamenteScreen(label: 'Nutrición')` en `/nutricion`. La ruta está registrada en `coach_hub_router.dart` (`...nutricionRoutes`) pero el item **NO está en `sidebar_registry.dart`**: fue removido en la **reducción W2** con la justificación textual «duplicaban funcionalidad del alumno_detail (por-alumno)». Existe `nutricionSidebarItems` (grupo `SidebarGroup.wellness`) pero sin importar en el registry → la sección es alcanzable solo por URL.

**Consecuencia arquitectónica**: la sección hub NO puede ser otro editor de plan — eso sería exactamente la duplicación que W2 eliminó. La única lectura honesta y NO-duplicativa es una **vista overview cross-alumno** (ver §3).

### Capa de datos REAL (ya existe — NO se crea backend)

- `NutritionPlan(id, trainerId, athleteId, title, meals, updatedAt)` — `lib/features/coach/domain/nutrition_plan.dart` (freezed). **Un plan por par PF↔alumno**, se sobrescribe al guardar (sin historial).
- `Meal(id, name, time?, groups)` / `FoodGroup(id, name, selectionMode, options)` / `FoodOption(id, name, quantity?, unit?, notes?)`. **Modelo CUALITATIVO**: `quantity` es string libre; NO hay días, NO macros numéricos, NO kcal, NO recetas.
- `nutritionPlanProvider` — `StreamProvider.autoDispose.family<NutritionPlan?, ({String trainerId, String athleteId})>` (`lib/features/coach/application/nutrition_plan_providers.dart`). Emite `null` si no hay plan.
- `trainerLinksStreamProvider` — `StreamProvider.autoDispose<List<TrainerLink>>` (`lib/features/coach/application/trainer_link_providers.dart`): roster real-time del PF. Filtrar `status == active` para alumnos vigentes (mismo patrón que `alumnos_screen.dart`).
- `currentUidProvider` = `trainerId`. `userPublicProfileProvider(athleteId)` = `displayName`/`avatarUrl`.
- **Editor real Fase 3**: `PlanNutricionCard` (`sections/alumnos/widgets/plan_nutricion_card.dart`) + su skeleton, vive en el **tab Nutrición del detalle de alumno** (`/alumnos/:id`, `AlumnoDetailScreen`). **REUSABLE** — pero NO se re-instancia en el hub (ver ADR-F6-03); el hub deep-linkea a él.

### Referencia espejo (patrón EXACTO a seguir)

`test/evidence/coach_hub_solicitudes_evidence_test.dart` + `sections/invitaciones/` (Fase 4): sección removida en W2, re-entregada como screen real desde `trainerLinksStreamProvider`, con `TreinoStateSwitcher`/`TreinoFilterChips`/`TreinoSectionHeader`/`TreinoEmptyState`, deep-link/acciones, y re-exposición del item de sidebar vía ADR con bump del `sidebar_registry_test`. **Fase 6 es la contraparte de nutrición**: mismo esqueleto, otra fuente de estado (plan por alumno).

### `.when` con spinner seco / duplicaciones

No hay spinner seco propio (la sección es placeholder). Riesgo de duplicación: re-crear un editor de plan en el hub. Mitigación dura: NO editar en el hub — deep-link a `/alumnos/:id` (ADR-F6-03).

## 3. Arquitectura de la fase

Patrón: **screen de sección Riverpod (sin Scaffold, ADR-CHW-005) → provider agregado (links activos × plan por alumno) → StateSwitcher → lista de filas del kit → deep-link al editor real**. Capas:

```
routes.dart (/nutricion) ──► NutricionScreen (ConsumerWidget)
   │
   │  TreinoSectionHeader (NUTRICIÓN + conteo)        [FadeSlideIn stagger 0]
   │  TreinoFilterChips (Todos/Con plan/Sin plan + counts) [stagger 1]
   │  TreinoStateSwitcher (childKey por estado+filtro)
   │     ├─ loading → NutricionPlanRow(loading) x N (shimmer)
   │     ├─ empty   → TreinoEmptyState honesto (sin alumnos / filtro vacío)
   │     ├─ error   → retry (invalidate trainerLinksStreamProvider)
   │     └─ data    → Column de NutricionPlanRow (filtrados por chip)
   │
   ├─ nutricion_providers.dart
   │     ├─ NutricionFiltro { todos, conPlan, sinPlan }
   │     ├─ NutricionEntry ({ TrainerLink link, NutritionPlan? plan, bool planLoading })
   │     ├─ nutricionEntriesProvider (Provider.autoDispose<AsyncValue<List<NutricionEntry>>>)
   │     │     watch(trainerLinksStreamProvider).whenData → active → por alumno
   │     │     watch(nutritionPlanProvider((trainerId, athleteId))) → entry
   │     ├─ matchesNutricionFiltro(NutricionEntry, NutricionFiltro)  (pura)
   │     ├─ _filtroProvider (StateProvider.autoDispose, default todos)
   │     └─ conteos por filtro (derivados de la lista de entries)
   │
   └─ widgets/nutricion_plan_row.dart (ConsumerWidget presentational)
         leading avatar (userPublicProfileProvider) + nombre
         subtitle: "Con plan · N comidas · actualizado hace X" | "Sin plan todavía"
         trailing: chevron/"Ver plan"
         onTap → context.go('/alumnos/${athleteId}')  (ADR-F6-03)
```

Data flow: `trainerLinksStreamProvider` (active) → por alumno `nutritionPlanProvider` → `NutricionEntry` (plan? + loading) → partición por chip (Todos/Con plan/Sin plan) con counts reales → fila → deep-link al editor Fase 3.

Boundaries limpios (ADR-F6-01): **Nutrición hub = overview cross-alumno** (triage: quién tiene/no tiene plan, salto rápido a editar). **Alumno detalle > tab Nutrición = edición real** (Fase 3). No se duplica el editor; la overview es una lente que alumno_detail NO ofrece (multi-alumno de un vistazo), por eso NO reintroduce la redundancia que W2 removió.

### ADRs

- **ADR-F6-01 (sección = overview cross-alumno, NO editor)**: la Nutrición del hub es una vista de resumen/roster cableada a providers reales (`trainerLinksStreamProvider` + `nutritionPlanProvider`), NO un segundo editor de plan. Justificación: W2 removió el item por «duplicar alumno_detail (por-alumno)»; un editor duplicaría, una overview multi-alumno NO (alumno_detail es single-athlete). Rechazado: editor standalone a nivel hub (duplica Fase 3, viola NO-duplicar y la decisión W2).

- **ADR-F6-02 (descope macros/kcal/semanal/recetas/meta-diaria)**: el modelo real `NutritionPlan` es **cualitativo** (comidas→grupos→opciones, `quantity` string libre), SIN días, SIN macros numéricos, SIN kcal, SIN recetas. `nutricion.png` (KPI de macros, config del plan con calorías/gramos, recetas frecuentes, tabs de día) y `meta-diaria.png` (slider kcal objetivo, donut de distribución, sliders de macros, "plan actual vs objetivo") son **100% data inventada**. Se **descopean**: construirlos exige un backend cuantitativo nuevo (modelo de macros/kcal/recetas + estructura semanal), explícitamente prohibido («NO inventar backend»). Rechazado: inventar el modelo cuantitativo.

- **ADR-F6-03 (deep-link vs editor inline)**: la fila navega a `/alumnos/:id` (`AlumnoDetailScreen`), donde vive el editor real de Fase 3 (`PlanNutricionCard`, tab Nutrición). Rechazado: instanciar `PlanNutricionCard` inline en el hub (duplicaría el tab + exigiría re-cablear mutadores/save → churn y duplicación). Nota ejecución: si `AlumnoDetailScreen` soporta seleccionar tab por query param, apuntar al tab Nutrición; si no, aterrizar en el detalle es suficiente (NO agregar soporte de tab-deep-link — fuera de scope).

- **ADR-F6-04 (agregado N-streams, tradeoff conocido)**: `nutricionEntriesProvider` observa `nutritionPlanProvider` por alumno activo → N streams Firestore concurrentes (uno por alumno). Mitigación: `autoDispose` + filas livianas; cada plan resuelve su propio loading (chip/shimmer de estado). Optimización futura (fuera de scope): query `nutrition_plans where trainerId == uid` con índice. Rechazado: agregar ese query ahora (backend nuevo). Riesgo documentado para rosters grandes (>~30).

- **ADR-F6-05 (l10n congelado)**: `lib/l10n/*` PROHIBIDO. Reutilizar keys existentes donde apliquen (retry, load-error, a11y avatar); literales nuevos de UI (título "NUTRICIÓN", labels de chips, empties, estados de plan) hardcodeados en es-AR con marca `// i18n: Fase W6`, igual que el resto del hub. Rechazado: tocar `lib/l10n/*`.

- **ADR-F6-06 (motion e interacción)**: header+chips entran con `TreinoFadeSlideIn`+`AppMotion.stagger` (eager, bounded); la **lista NO** usa stagger per-item (regla dura: nunca stagger en listas potencialmente largas). Selección de chip anima (built-in `TreinoFilterChips`). Cambio de estado/filtro cross-fadea con `TreinoStateSwitcher` (childKey por estado+filtro). Carga = `NutricionPlanRow(loading:true)` (shimmer). Fila usa `TreinoInteractiveState`/`TreinoListRow` del kit (hover/pressed/focus + Semantics + teclado). Prohibido: spinner seco, stagger en lista, AnimationController fuera de hoja.

- **ADR-F6-07 (re-exposición del item de sidebar, reversible)**: para que la overview sea alcanzable por navegación, re-exponer `nutricionSidebarItems` en `sidebar_registry.dart` (simetría con ADR-F4-04). Verificar que el **grupo renderiza**: `nutricionSidebarItems` usa `SidebarGroup.wellness` — si el sidebar solo pinta GESTIÓN/RECURSOS/AJUSTES, reasignar el item a un grupo renderizado (sugerido: GESTIÓN tras Chat, o RECURSOS tras Biblioteca). Blast radius conocido: `test/features/coach_hub/presentation/shell/sidebar_registry_test.dart` afirma `length == 9` → pasa a 10 (WU-06 actualiza el test). **Fallback si el reviewer prefiere respetar la reducción W2**: entregar screen + providers pero **diferir** la re-exposición (la sección queda alcanzable por URL/deep-link); en ese caso la Fase colapsa a un landing pulido (header + EmptyState honesto que apunta a Alumnos). Rechazado: badge falso o inventar métrica de sidebar.

## 4. Data-map (mockup → real)

| Mockup | Real | Acción |
|---|---|---|
| "EDITOR NUTRICIONAL" (editor semanal) | Editor cualitativo Fase 3 en `/alumnos/:id` | Deep-link (ADR-F6-03), NO reconstruir |
| Tabs de día (Lunes…Domingo) | — (modelo sin días) | Dropear (ADR-F6-02) |
| KPI macros (Calorías/Proteínas/Carbos/Grasas) | — (sin macros numéricos) | Dropear (ADR-F6-02) |
| Config del plan (objetivo/calorías/gramos) | — | Dropear (ADR-F6-02) |
| Recetas frecuentes | — (sin modelo de recetas) | Dropear (ADR-F6-02) |
| meta-diaria.png (slider kcal/donut/sliders/vs objetivo) | — (100% inventado) | Dropear (ADR-F6-02) |
| Header "PLAN SEMANAL · 2.100 kcal" | `TreinoSectionHeader('NUTRICIÓN' + conteo)` | Construir (overview) |
| — (nuevo, valor real) | Roster de alumnos + estado de plan | Construir (ADR-F6-01) |
| avatar + nombre | `userPublicProfileProvider` | Construir |
| estado del plan | `nutritionPlanProvider` (null / title / meals.length / updatedAt) | Construir |
| chips de filtro | Todos/Con plan/Sin plan (counts reales) | Construir |
| item de sidebar "Nutricion" (activo mint) | `nutricionSidebarItems` re-expuesto | Cablear (ADR-F6-07) |

## 5. Archivos

Nuevos:
- `lib/features/coach_hub/presentation/sections/nutricion/nutricion_screen.dart`
- `lib/features/coach_hub/presentation/sections/nutricion/nutricion_providers.dart`
- `lib/features/coach_hub/presentation/sections/nutricion/widgets/nutricion_plan_row.dart`
- `test/evidence/coach_hub_nutricion_evidence_test.dart`
- Tests unit/widget bajo `test/features/coach_hub/presentation/sections/nutricion/`

Modificados:
- `lib/features/coach_hub/presentation/sections/nutricion/routes.dart` (real screen + label)
- `lib/features/coach_hub/presentation/shell/sidebar_registry.dart` (re-agregar item, ADR-F6-07)
- `test/features/coach_hub/presentation/shell/sidebar_registry_test.dart` (9→10)

PROHIBIDOS / fuera de scope (NO tocar): `lib/l10n/*`, cualquier `routine_editor/*`, `sections/alumnos/widgets/plan_nutricion_card.dart` (se reutiliza vía deep-link, NO se modifica), `lib/features/coach/domain/nutrition_plan*.dart` (modelo congelado), tests de usuario listados en el contrato. La sección `nutricion/` no contiene archivos de usuario.

## 6. Evidencia visual

Harness espejo de `test/evidence/coach_hub_solicitudes_evidence_test.dart`: monta `/nutricion` dentro de `CoachHubScaffold` real con providers fake POBLADOS: `trainerLinksStreamProvider` (≥5 active + algunos paused/terminated para verificar el filtro a active), `userPublicProfileProvider` por alumno, y `nutritionPlanProvider((trainerId, athleteId))` override por alumno — **mezcla intencional: algunos con plan (varias comidas), otros `null` (sin plan)** para poblar los 3 chips. FontLoader `test/fonts/` + Phosphor, guard `EVIDENCE`, comparator a `docs/web-trainer/evidence/fase-6/<EVIDENCE_DIR>/`. Matriz: (dark, light) × (1440x900, 420x900) = 4 goldens. Excluir `/nutricion` del loop de `otherPaths`. BEFORE captura el `ProximamenteScreen` (guard laxo: acepta "NUTRICIÓN"/"Próximamente."); AFTER captura la screen real (guard endurecido: título "NUTRICIÓN" + nombre de un alumno fake + evidencia de un estado de plan, ej. "Sin plan" o "comidas").

## 7. Work Units (atómicos, secuenciales)

- **WU-01** — Harness de evidencia + goldens BEFORE (placeholder), commit.
- **WU-02** — `nutricion_providers.dart` (filtro enum + `NutricionEntry` + agregado + predicado puro + counts) con TDD.
- **WU-03** — `NutricionPlanRow` (ConsumerWidget presentational) con TDD.
- **WU-04** — `NutricionScreen` core: header + chips + StateSwitcher (data→rows) + deep-link. Reemplaza `ProximamenteScreen`. TDD.
- **WU-05** — Estados + motion del screen: empties honestos por filtro + loading shimmer + error retry + FadeSlideIn/stagger + cross-fade + responsive/dark-light. TDD.
- **WU-06** — Re-exposición del item de sidebar (ADR-F6-07) + fix `sidebar_registry_test` (9→10). TDD.
- **WU-07** — Goldens AFTER (guard endurecido) + gates full (FULL `flutter test` + `analyze` baseline 42) + commit del plan.

Detalle ejecutable de cada WU: ver el resultado estructurado (`work_units[].scope`).

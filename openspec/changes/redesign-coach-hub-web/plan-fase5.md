# Plan Fase 5 — Rutinas (Coach Hub Web)

> Artefacto de diseño (design/architecture). Backend activo: hybrid (engram `sdd/redesign-coach-hub-web/plan-fase5` + este archivo).
> Este archivo queda SIN COMMITEAR; lo commitea el WU final (evidencia after + gates).

## 1. Dirección visual (norte)

Mockup leído como imagen: `docs/web-trainer/screens/rutina/rutina.png` — **muestra el EDITOR DE RUTINA** (dos vistas apiladas: tab LUNES y tab SÁBADO con notas técnicas expandidas), NO las pantallas de lista. Anatomía observada:

- **Header card de rutina**: ícono + "GLÚTEOS · FUERZA 5D" (Barlow Condensed CAPS) + meta ("hipertrofia de glúteos · 8 semanas · 5 días/sem · Asignada a 4 alumnos") + acciones (Vista alumno / Duplicar / Guardar template / **Guardar** píldora mint).
- **Tabs de día**: LUNES…DOMINGO con conteo de ejercicios, tab activo con subrayado mint.
- **Lista de ejercicios**: filas numeradas, nombre + grupo muscular, celdas-chip pequeñas boxed (SERIES/REPS/CARGA/DESCANSO/RIR) con valores en mint, drag handle, hint "Arrastrá para reordenar".
- **Panel derecho**: CONFIGURACIÓN (Objetivo/Duración/Inicio/Fin/Notas técnicas), ASIGNACIONES (avatares coloreados + nombre + % adherencia), "+ Asignar a alumno", callout TIP.

**TODO ese mockup es el EDITOR — zona PROHIBIDA** (`routine_editor/` con cambios sin commitear del usuario, ver ADR-F5-01). Del mockup se toma solo el **lenguaje visual** (dark, acentos mint en valores/estados activos, labels CAPS, avatares coloreados con inicial, agrupación por cards con borde sutil sin sombra, píldora mint para el CTA primario), ya validado en Fases 1-4. Cuando mockup y design system chocan en un token, **MANDA el design system**.

El scope REAL de Fase 5 son las **dos pantallas de lista/gestión** de `sections/rutinas/` (sin mockup directo → ADR-F5-02):
1. `RutinasScreen` (`/rutinas`) — **selector de alumno** (el sidebar es global, una rutina se asigna a UN alumno).
2. `AthleteRoutinesScreen` (`/rutinas/:athleteId`) — **rutinas asignadas a ese alumno**.

## 2. Realidad del código (censo de la sección)

Directorio `lib/features/coach_hub/presentation/sections/rutinas/` (solo 3 archivos, sin widgets extraídos):

- **`rutinas_screen.dart` (152L)** — `RutinasScreen` (`ConsumerWidget`). Ya consume `TreinoSectionHeader('Rutinas')` desde Fase 1 (commit 04197fb9). Watchea `trainerLinksStreamProvider`, dedup por `athleteId`, excluye `pending`. `.when` con **`CircularProgressIndicator` crudo** (spinner seco). `_AthleteRow` **stateful con hover manual** (MouseRegion + setState + Container borde `borderHover`) = duplicación del patrón que TreinoListRow ya resuelve. Empty/error vía helper `_muted` (Text plano) en vez de `TreinoEmptyState`.
- **`athlete_routines_screen.dart` (194L)** — `AthleteRoutinesScreen`. Header **manual** (IconButton back + Text Barlow Condensed + ElevatedButton "Nueva rutina") en vez de `TreinoSectionHeader` con acción. `.when` con **spinner seco**. `_RoutineRow` **stateful con hover manual** (misma duplicación). Filtra a `status==active` y **oculta archivadas**. Web-editable → trailing edit icon + tap a `/routine-editor/:id/:routineId`; periodizada → texto "Editá en la app" sin tap. Empty/error vía `_muted`. **Importa `isRoutineWebEditable` desde `routine_editor/routine_web_editability.dart` (ARCHIVO PROHIBIDO) — ver ADR-F5-06.**
- **`routes.dart` (43L)** — `rutinasRoutes` (`/rutinas`, `/rutinas/:athleteId`, ambas `coachHubPage` NoTransitionPage) + `rutinasSidebarItems` (grupo `recursos`). **No tocar la estructura de rutas** (estable, ADR-CHW-002).

Tests existentes (a mantener verdes / extender con TDD):
- `test/features/coach_hub/presentation/sections/rutinas/rutinas_screen_test.dart` — header "RUTINAS", subtítulo, dedup+exclude pending, empty, tap→navega. Patrón: `ProviderScope` + override `trainerLinksStreamProvider`/`userPublicProfileProvider(id)` + `MaterialApp.router(theme: AppTheme.dark())`, Scaffold stand-in del editor con marker text.
- `test/features/coach_hub/presentation/sections/rutinas/athlete_routines_screen_test.dart` — lista activas + resumen "3 días · 1 semana", oculta archivadas, empty, tap web-editable→EDIT, "Nueva rutina"→CREATE, periodizada view-only. Override `assignedRoutinesProvider(id)` + `userPublicProfileProvider(id)`.

### Capa de datos REAL (ya existe, no se crea backend)

- `trainerLinksStreamProvider` (`coach/application/trainer_link_providers.dart`) → `List<TrainerLink>` real-time.
- `TrainerLinkStatus`: `pending | active | paused | terminated`.
- `userPublicProfileProvider(athleteId)` → `displayName` (+ avatarUrl).
- `assignedRoutinesProvider(athleteId)` (`workout/application/assigned_routine_providers.dart`, `FutureProvider.autoDispose.family`) → `List<Routine>` (newest first).
- `Routine`: `id, name, split?, level, days[], numWeeks, status, source, assignedBy, assignedTo, visibility`. `RoutineStatus`: `active | archived` (con `.label` = "Activa"/"Archivada").
- `isRoutineWebEditable(Routine)` — función pura (numWeeks==1 && sin periodización) desde `routine_web_editability.dart` (PROHIBIDO — usar como caja negra, ADR-F5-06).
- `RoutineRepository` (`workout/data/routine_repository.dart`): `archive(routineId)` ✅ cableado; `createAssigned`, `assignTemplateToAthlete`, `deleteRoutine`, `updateAssigned`. **No hay** `duplicateRoutine` (ADR-F5-04).

### Referencia espejo (patrón exacto a seguir)

`lib/features/coach_hub/presentation/sections/alumnos/` y el harness `test/evidence/coach_hub_alumnos_evidence_test.dart`: mismo `trainerLinksStreamProvider`, `TreinoStateSwitcher` sobre `.when`, `TreinoListRow(loading:true)` shimmer, `TreinoEmptyState`, `TreinoFadeSlideIn`+`AppMotion.stagger` para elementos eager (header/chips, NUNCA listas largas). El WU de evidencia clona ese harness.

## 3. Arquitectura de la fase

Patrón: **screen de sección Riverpod (sin Scaffold, ADR-CHW-005) → `TreinoStateSwitcher` sobre `.when` → columna eager de `TreinoListRow` del kit**. No se crean widgets nuevos de kit (las dos pantallas son listas de una columna, no tablas). Capas:

```
routes.dart (/rutinas) ──► RutinasScreen (ConsumerWidget)     [SELECTOR DE ALUMNO]
   │  TreinoSectionHeader('Rutinas', count: nAlumnos)          [FadeSlideIn stagger 0]
   │  subtítulo "Elegí un alumno…"                             [stagger 1]
   │  TreinoStateSwitcher(childKey por estado)
   │     ├─ loading → Column de TreinoListRow(loading:true) xN  (shimmer)
   │     ├─ empty   → TreinoEmptyState (icon + "Todavía no tenés alumnos vinculados.")
   │     ├─ error   → TreinoEmptyState error / retry (invalidate stream)
   │     └─ data    → Column eager de TreinoListRow(
   │                     leading avatar mint inicial, title name,
   │                     trailing chevronRight, onTap push('/rutinas/:id'))
   │                   c/u en TreinoFadeSlideIn(stagger index)
   │
routes.dart (/rutinas/:athleteId) ──► AthleteRoutinesScreen    [RUTINAS DEL ALUMNO]
   │  Row: back IconButton + TreinoSectionHeader('Rutinas de $name',
   │        count, action: 'Nueva rutina' → push('/routine-editor/:athleteId'))
   │  TreinoFilterChips(Activas/Archivadas, single, badgeCounts reales) [WU-03]
   │  TreinoStateSwitcher(childKey por estado+filtro)
   │     ├─ loading → TreinoListRow(loading:true) xN
   │     ├─ empty   → TreinoEmptyState honesto por filtro (+CTA "Nueva rutina" en Activas)
   │     ├─ error   → retry (invalidate assignedRoutinesProvider)
   │     └─ data    → Column eager de TreinoListRow(
   │                     title routine.name, subtitle "N días · N semana(s)",
   │                     web-editable → trailing edit + onTap editor;
   │                     periodizada → trailing "Editá en la app" + onTap null)
   │                   c/u en TreinoFadeSlideIn(stagger index)
   │                   [WU-04 opcional] trailing menú → Archivar (TreinoDialog)
```

Data flow: `trainerLinksStreamProvider` → dedup/exclude pending → por fila `userPublicProfileProvider(athleteId)` → `push('/rutinas/:id')` → `assignedRoutinesProvider(athleteId)` → filtro por `RoutineStatus` (chips WU-03) → `isRoutineWebEditable` decide tap→editor vs view-only → "Nueva rutina"/edit navegan por **ruta string** (`/routine-editor/...`) sin importar el editor.

Boundary con la zona PROHIBIDA (ADR-F5-06): la navegación al editor es **solo por string de ruta**; el único acoplamiento de código es la llamada YA EXISTENTE a `isRoutineWebEditable(routine)` (API pública estable, tratada como caja negra). Ningún WU abre, lee para nueva lógica, modifica ni testea `routine_editor/*`.

### ADRs

- **ADR-F5-01 (editor EXCLUIDO — Fase 5b diferida)**: `routine_editor_web_screen.dart`, `routine_web_editability.dart` y `test/features/coach_hub/.../routine_editor/*` tienen cambios SIN COMMITEAR del usuario → PROHIBIDO tocarlos/leerlos-para-depender/planificarlos. El mockup `rutina.png` ES el editor, así que su rediseño (header de rutina, tabs de día, grilla de ejercicios con celdas-chip, panel Configuración/Asignaciones, drag-reorder) queda **documentado como Fase 5b pendiente**, a ejecutar cuando el usuario committee/limpie su árbol. Rechazado: rediseñar el editor ahora (bloqueado por cambios sin commitear + conflicto build_runner R-02).

- **ADR-F5-02 (sin mockup de las listas → design system + kit como norte)**: las dos pantallas de lista no tienen mockup propio. Se reusa el lenguaje visual del `rutina.png` (dark, mint, CAPS, avatares con inicial, cards borde sutil sin sombra, píldora mint del CTA) y los patrones de kit validados en Fases 1-4 (espejo Alumnos). Rechazado: inventar layouts nuevos a partir del editor (drift + deuda visual).

- **ADR-F5-03 (`TreinoListRow` sobre `CoachHubDataTable`)**: ambas pantallas son listas de UNA columna con navegación por fila (alumno → nombre; rutina → nombre+resumen), no data tabular multi-columna. `TreinoListRow` aporta leading/title/subtitle/trailing + hover/pressed/focus + Semantics + teclado + skeleton shimmer sin reinventar. Rechazado: `CoachHubDataTable` (sobre-ingeniería para 1 columna; Alumnos usa tabla porque es genuinamente multi-columna nombre/gym/estado/deuda — Rutinas no lo es).

- **ADR-F5-04 (honestidad — descope KpiCard/Duplicar/Asignar; Archivar opcional)**: sin data honesta para KPIs en estas listas → **descope KpiCard**. `duplicateRoutine` **no está cableado** (no existe método de repo; copiar vía `createAssigned` sería lógica net-new sin mockup) → **descope Duplicar**. `assignTemplateToAthlete` existe pero **no hay UI de templates en esta sección** (Templates es otra sección) → **descope Asignar**. Las acciones "Duplicar/Guardar template" del mockup viven en el toolbar del EDITOR (zona prohibida). `archive(routineId)` **SÍ está cableado** → única mutación honesta posible → **WU-04 OPCIONAL** con `TreinoDialog`. Rechazado: fabricar KPIs / duplicar con lógica ad-hoc / picker de asignación inventado.

- **ADR-F5-05 (`TreinoFilterChips` Activas/Archivadas — honesto)**: `RoutineStatus` tiene `active|archived` y las archivadas existen en data (hoy OCULTAS). Un filtro single-select Activas/Archivadas con `badgeCounts` reales es data honesta y da uso legítimo a `TreinoFilterChips`. Archivadas se muestran **view-only** (sin tap→editor). Rechazado: filtro de estado en el selector de alumno (habría que exponer `TrainerLinkStatus` fuera de la UX actual/mockup = inventar).

- **ADR-F5-06 (boundary con zona prohibida)**: `AthleteRoutinesScreen` ya importa `isRoutineWebEditable` desde `routine_web_editability.dart` (PROHIBIDO). El WU de rediseño **mantiene ese import y call site verbatim**, tratándolos como API pública estable de caja negra; NO abre el archivo para lógica nueva, NO lo modifica, NO lo testea. La navegación al editor es solo por ruta string. Si un test/harness arrastra el import transitivo (ya existe), es dependencia de compilación pre-existente, no una modificación. Rechazado: reimplementar `isRoutineWebEditable` en la sección (duplicaría lógica de periodización y divergiría de la Fase 4 real del editor).

- **ADR-F5-07 (motion e interacción)**: `TreinoStateSwitcher` con `childKey` por estado (y por filtro en la lista de rutinas) reemplaza los `CircularProgressIndicator` crudos. Carga = `TreinoListRow(loading:true)` (shimmer del kit). Header/subtítulo/chips entran con `TreinoFadeSlideIn`+`AppMotion.stagger` (eager, bounded). Las filas de datos son columnas **eager** (`for` en `Column`, no `ListView.builder`) → se permite `TreinoFadeSlideIn(stagger index)` per-item (seguro: no reciclan State). Hover/pressed/focus + Semantics + teclado los da `TreinoListRow` vía `TreinoInteractiveState` (fuente única, ADR-SH-002) — **NO** `TreinoTappable` core. `reduceMotion` lo respetan todos los widgets del kit. Selección de chip anima (built-in).

- **ADR-F5-08 (l10n congelado / strings)**: `lib/l10n/*` PROHIBIDO. Strings nuevas hardcodeadas en es-AR con `// i18n` (igual que el resto del hub). Se preservan literales existentes ("Rutinas de $name", "N días · N semana(s)", "Nueva rutina", "Editá en la app", empties actuales) para no romper los asserts de texto de los tests existentes salvo donde el WU los actualice con TDD.

## 4. Data-map (mockup/estado actual → real)

| Mockup / actual | Real | Acción |
|---|---|---|
| Header rutina "GLÚTEOS · FUERZA 5D" + toolbar (Duplicar/Guardar template/Guardar) | EDITOR — zona prohibida | Fase 5b (ADR-F5-01) |
| Tabs de día + grilla de ejercicios + panel Config/Asignaciones + drag | EDITOR — zona prohibida | Fase 5b (ADR-F5-01) |
| Selector de alumno (spinner seco + `_AthleteRow` hover manual + `_muted`) | `trainerLinksStreamProvider` + `userPublicProfileProvider` | Rediseñar con kit (WU-01) |
| Avatar coloreado + inicial | CircleAvatar mint + `displayName[0]` | Construir (leading de TreinoListRow) |
| Lista de rutinas del alumno (spinner seco + `_RoutineRow` hover manual) | `assignedRoutinesProvider(id)` | Rediseñar con kit (WU-02) |
| Resumen "N días · N semanas" | `routine.days.length` / `routine.numWeeks` | Preservar (subtitle) |
| web-editable vs periodizada | `isRoutineWebEditable` (caja negra) | Preservar gating (ADR-F5-06) |
| Filtro Activas/Archivadas | `RoutineStatus` (active/archived) + badgeCounts | Construir (WU-03, ADR-F5-05) |
| KPIs de rutina | — (sin data en listas) | Dropear (ADR-F5-04) |
| Duplicar / Asignar | — (no cableado en esta UI) | Dropear (ADR-F5-04) |
| Archivar | `RoutineRepository.archive` (cableado) | WU-04 opcional (ADR-F5-04) |

## 5. Archivos

Nuevos:
- `test/evidence/coach_hub_rutinas_evidence_test.dart` (harness espejo de alumnos → `docs/web-trainer/evidence/fase-5/{before,after}/`).
- Tests widget nuevos/extendidos bajo `test/features/coach_hub/presentation/sections/rutinas/` (estados loading/empty/error, motion keys, filtro, [archivar]).
- `docs/web-trainer/evidence/fase-5/before/*.png` y `.../after/*.png` (goldens generados).

Modificados:
- `lib/features/coach_hub/presentation/sections/rutinas/rutinas_screen.dart` (WU-01).
- `lib/features/coach_hub/presentation/sections/rutinas/athlete_routines_screen.dart` (WU-02, WU-03, [WU-04]).
- (WU-04 opcional) `lib/features/coach_hub/presentation/sections/rutinas/routine_actions_provider.dart` (nuevo, mutación archive + invalidate) y `core/widgets/treino_icon.dart` (nombre semántico de archivar si falta).

PROHIBIDOS / fuera de scope (NO tocar ni leer para depender): `routine_editor/routine_editor_web_screen.dart`, `routine_editor/routine_web_editability.dart` (solo caja negra), `test/features/coach_hub/presentation/sections/routine_editor/*`, `lib/l10n/*`, `routes.dart` estructura de rutas, `TreinoTappable` core, y los archivos de usuario del contrato.

## 6. Evidencia visual

Harness espejo de `test/evidence/coach_hub_alumnos_evidence_test.dart`: monta `/rutinas` y `/rutinas/:athleteId` dentro de `CoachHubScaffold` real con providers fake POBLADOS (links active/paused/pending/terminated → el selector muestra varios alumnos; `assignedRoutinesProvider` con rutinas activas web-editables + una periodizada + una archivada), FontLoader `test/fonts/` + Phosphor, guard `EVIDENCE`, comparator a `docs/web-trainer/evidence/fase-5/<dir>/`. Excluir `/rutinas` del loop `otherPaths` del sidebar (como alumnos excluye `/alumnos`). Rutas del editor **no** se montan (navegación no requerida para screenshot estático → cero acoplamiento con la zona prohibida). Matriz: (selector, rutinas-del-alumno) × (dark, light) × (1440x900, 420x900) = 8 goldens; a 420px se captura el `MobileBanner` desktop-only (ADR-CHW-004), con la misma rama de guard que el harness de alumnos. BEFORE captura el estado actual (spinner seco + rows manuales); AFTER captura el rediseño.

## 7. Work Units (atómicos, secuenciales)

- **WU-00** — Harness de evidencia + goldens BEFORE (nuevo `coach_hub_rutinas_evidence_test.dart`, capturar `fase-5/before/`, commit).
- **WU-01** — `RutinasScreen` (selector de alumno): `TreinoStateSwitcher`+shimmer, `TreinoListRow` (avatar mint + chevron), `TreinoEmptyState`, `TreinoSectionHeader` con count, stagger. TDD. Commit.
- **WU-02** — `AthleteRoutinesScreen` (lista de rutinas) core: header→`TreinoSectionHeader`+acción "Nueva rutina", `TreinoStateSwitcher`+shimmer, `TreinoListRow` (edit trailing / "Editá en la app"), `TreinoEmptyState` con CTA, stagger, preservar gating web-editable. TDD. Commit.
- **WU-03** — Filtro `TreinoFilterChips` Activas/Archivadas (honesto, `RoutineStatus`, badgeCounts, archivadas view-only, motion de selección + switcher por filtro). TDD. Commit.
- **WU-04** — (OPCIONAL, droppable) Acción "Archivar" vía `TreinoDialog` + mutación `RoutineRepository.archive` + `invalidate(assignedRoutinesProvider)`. TDD. Commit. Cortar si el presupuesto de PR aprieta.
- **WU-05** — Goldens AFTER + gates full (FULL `flutter test` + `analyze` baseline 42) + commit del plan `plan-fase5.md`.

Detalle ejecutable de cada WU: ver el resultado estructurado (`work_units[].scope`).

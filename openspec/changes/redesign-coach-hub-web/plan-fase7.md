# Plan — Fase 7: Biblioteca

> Cambio: redesign-coach-hub-web · Fase 7 — Sección Biblioteca · Store: hybrid · 2026-07-20
> Rama: feat/coach-hub-biblioteca-redesign · Depende de: Fase 0 (tokens v2) + Fase 1 (shell+kit) COMPLETAS
> Evidencia: docs/web-trainer/evidence/fase-7/{before,after}/
> Misión especial de la fase: ANIMACIONES DE SELECCIÓN Y FILTRO (chips + grilla + estados).

## 1. Anatomía objetivo (mockups)
4 mockups (`docs/web-trainer/screens/biblioteca/*.png`), todos header "BIBLIOTECA" CAPS + subtítulo de counts + tab bar CAPS con count por tab:
- **ejercicios.png**: tabs EJERCICIOS·402 / ALIMENTOS·86 / TEMPLATES RUTINAS·14 / TEMPLATES NUTRICIÓN·10. Search "Buscar ejercicio…" + DOS filas de chips (grupos musculares: TODOS/PECHO/ESPALDA/PIERNA/HOMBRO/BRAZO/CORE/CARDIO; equipamiento a la derecha: MANCUERNA/BARRA/MÁQUINA/PESO CORPORAL). Grilla 4-col de cards: thumbnail con gradiente + placeholder, nombre, "Músculo · grupo", pie con tag de equipamiento + "N usos". Badge CUSTOM arriba-derecha en algunas.
- **alimentos.png**: search "Buscar alimento…" + chips (TODOS/PROTEÍNAS/CARBOS/GRASAS/VEGETALES/FRUTAS). TABLA (ALIMENTO / CATEGORÍA / POR 100G / PROT / CARB / GRASA / KCAL), KCAL en mint.
- **template-rutina.png**: grilla 3-col de cards template: badge de ícono (rayo), título CAPS, "N días/sem · N semanas", pie con chip de nivel + "N ALUMNOS" mint.
- **template-nutricion.png**: grilla 3-col de cards: badge de ícono, título CAPS, macros ("180g prot · 220g carb · 60g grasa"), pie "N ALUMNOS" mint.

Regla de conflicto: si el mockup choca con un token del design system, **manda el design system** (radii 12/16/20/full, spacing 8/12/14/18/20, cards sin shadow, headings Barlow Condensed 700 UPPERCASE).

## 2. Estado actual (lib/.../sections/biblioteca — 120L screen + 8 widgets)
- **biblioteca_web_screen.dart**: TabController con **SOLO 2 tabs** (Ejercicios + Templates Rutinas). Header `Text('BIBLIOTECA')` crudo (fontSize 20/w700). TabBar crudo con labels "Ejercicios · N" / "Templates Rutinas · N" (counts reactivos reales: `bibliotecaUnfilteredCountProvider` + `trainerTemplatesStreamProvider`). Sin subtítulo. Sin Scaffold (ADR-CHW-005).
- **providers/biblioteca_providers.dart**: `bibliotecaQueryProvider` (String), `bibliotecaMuscleFilterProvider` (Set<MuscleGroup>), `bibliotecaEquipmentFilterProvider` (Set<EquipmentType>), `bibliotecaExercisesProvider` (catálogo ∪ custom, folded/filtrado — LÓGICA A PRESERVAR, solo consumir), `bibliotecaUnfilteredCountProvider`. Datos REALES: `exercisesProvider` + `customExercisesForTrainerStreamProvider`.
- **widgets/ejercicios_tab.dart**: `TextField` crudo (radius 10) → search; `BibliotecaFilterChips`; `.when(loading: CircularProgressIndicator crudo, error: Text, data: GridView.builder(ExerciseGridCard))`. Empty = Text centrado.
- **widgets/biblioteca_filter_chips.dart (218L)**: dos filas `Wrap` de `_TodosChip`/`_FilterChip` BESPOKE (GestureDetector crudo, radius 8 hardcode, sin hover/focus/teclado, sin animación de selección). Toggle sets typed (`Set<MuscleGroup>`/`Set<EquipmentType>`).
- **widgets/exercise_grid_card.dart (216L)**: `GestureDetector` crudo (sin hover), thumbnail Image.asset con fallback ícono, badge CUSTOM, chips info. GoogleFonts directo, radii 4/6/10/12.
- **widgets/exercise_detail_dialog.dart**: `AlertDialog` crudo (width 520, radius 20) con `ExerciseVideoPlayer` (workout) + `TechniqueInstructionItem`. `.when` con CircularProgressIndicator.
- **widgets/templates_tab.dart**: `.when(loading: CircularProgressIndicator, error: Text, data: GridView.builder(TemplateGridCard))`. Empty = Text.
- **widgets/template_grid_card.dart (131L)**: `GestureDetector` crudo, badge ícono, nivel chip. SIN count de alumnos (no denormalizado — REQ-BIBW-09). GoogleFonts, radii 6/10/12.
- **widgets/template_detail_dialog.dart**: `AlertDialog` read-only (nombre + nivel + cadencia + días/slots). Sin edición.
- **widgets/template_format.dart**: helper puro `routineCadenceLabel` (no tocar).
- Tests existentes (modificables, NO prohibidos): `ejercicios_tab_test.dart` (asserta `CircularProgressIndicator` en loading + `AlertDialog` al tap), `templates_tab_test.dart` (idem), `biblioteca_web_screen_test.dart`, `providers/biblioteca_providers_test.dart`.
- Violaciones: 4 `.when` con CircularProgressIndicator seco (2 ejercicios, 2 templates/dialog), cero TreinoStateSwitcher/Shimmer/FadeSlideIn, GestureDetector crudo en 2 cards + chips, chips bespoke sin animación, GoogleFonts directo, headers crudos, radii fuera de escala (4/6/8/10).

## 3. HONESTIDAD DE DATOS (verificado en código) — DESCOPE DURO
- **NO existe** provider/catálogo de **alimentos** ni de **templates de nutrición**. `FoodOption`/`FoodGroup` (`lib/features/coach/domain/nutrition_plan.dart`) son piezas del plan de nutrición **por-alumno** (sección `alumnos`), NO un catálogo global ni una biblioteca de templates.
- Por la regla dura de honestidad: los tabs **ALIMENTOS** y **TEMPLATES NUTRICIÓN** del mockup quedan **FUERA DE ALCANCE** (construirlos exigiría inventar datos). Los counts "86 alimentos / 10-24 templates nutrición" son ficción del mockup.
- La sección se rediseña con sus **2 tabs REALES**: Ejercicios (catálogo ∪ custom) + Templates Rutinas. Subtítulo honesto = solo counts reales ("N ejercicios · M templates"). Sin tab fantasma.

## 4. APIs reales del kit (verificadas)
- `TreinoFilterChips({options: List<String>, selected: Set<String>, onChanged, multiSelect, disabled, badgeCounts})` — selección animada (AnimatedContainer, AppMotion.micro) + hover/focus/pressed/teclado via `TreinoInteractiveState` + Semantics + tokens `TreinoChipTokens`. Trabaja con `Set<String>` → requiere adapter typed↔String.
- `TreinoSectionHeader({title, count?, action?})` — Barlow Condensed 700 UPPERCASE (title.toUpperCase()). SIN slot de subtítulo → el subtítulo va como `Text` aparte debajo.
- `TreinoEmptyState({icon, title, description?, ctaLabel?, onCtaTap?, loading})` — entrada `TreinoFadeSlideIn` + skeleton shimmer con `loading:true`.
- `TreinoStateSwitcher({child, childKey})` — cross-fade loading→data→error; **keys distintas por estado OBLIGATORIAS** (`ValueKey('loading'|'data'|'error'|'empty')`).
- `TreinoShimmer({enabled=true, child})` — barrido sobre skeleton; `enabled:false` para estados no-cargando.
- `TreinoFadeSlideIn({delay, distance, child})` — one-shot; **PROHIBIDO en GridView.builder/ListView.builder** (re-anima al reciclar). `delay: AppMotion.stagger(i)`.
- `TreinoInteractiveState({onTap, builder})` — hover/pressed/focus + Semantics + teclado (envuelve TreinoTappable); para hover de cards (NADA de MouseRegion crudo).
- `showTreinoDialog<T>(context, builder)` + `TreinoDialog({title, body?, primaryLabel?, onPrimaryTap?, secondaryLabel?, onSecondaryTap?, destructive, loading, errorMessage})` — fade+scale motion, tokens, Escape, dark+light, sin shadow.
- Tokens: `AppSpacing` (8/12/14/18/20 + hairline 4), `AppRadius` (sm12/md16/lg20/full), `AppFonts.barlow`/`AppFonts.barlowCondensed`.
- `CoachHubDataTable` existe pero NO se usa (tab Alimentos descopeado).

## 5. ADRs (decisiones + rechazados)
- **ADR-B7-01 Honestidad de datos (dura)**: solo 2 tabs reales. DESCOPE de tabs Alimentos + Templates Nutrición (sin providers). Subtítulo con counts reales. Rechazado: fabricar catálogo/templates para pixel-match.
- **ADR-B7-02 Filtros → kit**: reemplazar `biblioteca_filter_chips.dart` bespoke por `TreinoFilterChips`. Adapter: opciones = labels UPPERCASE de `MuscleGroup.displayOrder` / `EquipmentType.values`; mapear label→enum en onChanged; "TODOS" como opción sintética líder que limpia el set — regla de desambiguación: *si `'TODOS'` está en el nuevo set Y NO estaba en el previo → limpiar; si no → quitar `'TODOS'` y mapear el resto*. `multiSelect:true`, OR intra-dimensión, AND entre dimensiones (preservar semántica). Rechazado: mantener `_FilterChip` crudo o una 3ra variante de chip. Fallback si el mapeo resulta inviable: reconstruir el chip interno sobre `TreinoInteractiveState` + `AnimatedContainer` + `TreinoChipTokens` (nunca GestureDetector crudo).
- **ADR-B7-03 Grid lazy + motion de filtro**: `GridView.builder` se mantiene (402 ejercicios) → PROHIBIDO `TreinoFadeSlideIn` por item. Animación de filtro = cross-fade keyed del contenedor del grid (`TreinoStateSwitcher` con key = firma de estado/filtros) al cambiar la firma, + hover/press por card. `TreinoFadeSlideIn` staggered SOLO en el bloque eager (header + filas de chips). Rechazado: FadeSlideIn por card (re-anima en scroll).
- **ADR-B7-04 Cards interactivas**: `ExerciseGridCard`/`TemplateGridCard` usan `TreinoInteractiveState` (hover/pressed/focus + Semantics + teclado) reemplazando `GestureDetector`; hover sutil sobre thumbnail (AnimatedContainer + AppMotion.micro, reduceMotion). Rechazado: MouseRegion+setState bespoke.
- **ADR-B7-05 Estados**: `TreinoStateSwitcher` (keys por estado) + `TreinoShimmer` skeleton de grilla + `TreinoEmptyState` honesto reemplazan CircularProgressIndicator/Text crudos en ambos tabs. Rechazado: spinner seco.
- **ADR-B7-06 Dialogs → kit**: detail dialogs (ejercicio + template) → `showTreinoDialog`/`TreinoDialog` (tokens). `ExerciseVideoPlayer` + `TechniqueInstructionItem` se REUSAN tal cual (caja negra); el `.when` interno del detalle de ejercicio pasa a `TreinoStateSwitcher`. Template detail sigue **read-only**. Rechazado: AlertDialog crudo.
- **ADR-B7-07 Harness evidencia por fase**: nuevo `test/evidence/coach_hub_biblioteca_evidence_test.dart` (patrón `coach_hub_nutricion_evidence_test.dart`: FontLoader `test/fonts/` + Phosphor via package_config, `_ignoreKnownGoogleFontsAsyncErrors`, providers fake poblados, guard EVIDENCE, comparador a `fase-7/<dir>/`). Overrides: `exercisesProvider` (catálogo poblado), `customExercisesForTrainerStreamProvider(uid)`, `trainerTemplatesStreamProvider(uid)`, `currentUidProvider`, + shell (auth/userProfile/sharedPreferences). Excluir `/biblioteca` del loop de `sidebarRegistry` (lo aporta `bibliotecaRoutes`). Matriz dark/light × 1440x900 y 420x900 sobre tab Ejercicios (default). Rechazado: reusar harness shell/nutrición.
- **ADR-B7-08 Tests existentes se EXTIENDEN**: las aserciones `find.byType(CircularProgressIndicator)` / `find.byType(AlertDialog)` se ACTUALIZAN a skeleton/shimmer y `TreinoDialog` (comportamiento nuevo, TDD test-first). Se preservan: CUSTOM badge, dialog open/close vía "Cerrar", cadencia, nivel, no-"alumnos", read-only.
- **ADR-B7-09 Exclusiones**: `exercise_picker_dialog.dart` (presentation/widgets) INTOCABLE (caja negra si se reusa; la biblioteca NO lo reusa); `ExerciseVideoPlayer` reuse as-is; NO tocar workout domain/providers ni `bibliotecaExercisesProvider` (folding); `lib/l10n/*` congelado (strings hardcoded + `// i18n`, cero keys nuevas); `template_format.dart`, `routes.dart` sin tocar. routine_editor no aplica a esta sección.

## 6. Motion (misión especial de la fase)
- `TreinoFilterChips`: selección animada de chips (grupos musculares + equipamiento) — centro de la misión.
- Cross-fade del grid al cambiar filtros (`TreinoStateSwitcher` keyed, AppMotion, reduceMotion).
- `TreinoStateSwitcher` (keys por estado) en cada `.when` visible: ejercicios, templates y dialog de ejercicio.
- `TreinoShimmer`: skeleton de grilla de cards en carga (ambos tabs).
- `TreinoFadeSlideIn` staggered solo en bloque eager (header + filas de chips). Nunca en GridView.builder.
- `TreinoInteractiveState` hover + press en cards y CTAs. `TreinoEmptyState` honesto. reduceMotion siempre.

## 7. Alcance archivos
EN SCOPE: `sections/biblioteca/biblioteca_web_screen.dart`, `widgets/{ejercicios_tab,biblioteca_filter_chips,exercise_grid_card,exercise_detail_dialog,templates_tab,template_grid_card,template_detail_dialog}.dart`, sus tests, `test/evidence/coach_hub_biblioteca_evidence_test.dart` (NUEVO), `docs/web-trainer/evidence/fase-7/{before,after}/`.
NO TOCAR: `bibliotecaExercisesProvider`/providers (solo consumir), `exercise_picker_dialog.dart`, `ExerciseVideoPlayer`, workout domain/providers, `lib/l10n/*`, `template_format.dart`, `routes.dart`, archivos de usuario. DESCOPE: tabs Alimentos + Templates Nutrición.

## 8. Work Units (secuenciales, atómicos, finos)
- **WU-01 Evidencia BEFORE**: crear harness `coach_hub_biblioteca_evidence_test.dart`, capturar `fase-7/before/` (dark/light × 1440/420, tab Ejercicios), commit.
- **WU-02 Shell chrome**: `biblioteca_web_screen.dart` header → `TreinoSectionHeader(title:'Biblioteca')` + subtítulo honesto ("N ejercicios · M templates", counts reales) + TabBar re-estilada con tokens (mantener 2 tabs + counts). Actualizar `biblioteca_web_screen_test`.
- **WU-03 Filtros → kit (showcase)**: `biblioteca_filter_chips.dart` → `TreinoFilterChips` (adapter typed↔String, TODOS, animación de selección). TDD del adapter + TODOS + mapeo.
- **WU-04 Ejercicios · grilla + estados**: `ejercicios_tab.dart` body → `TreinoStateSwitcher` (keyed) + `TreinoShimmer` skeleton grid + `TreinoEmptyState` honesto + search field tokenizado + cross-fade de filtro. Actualizar `ejercicios_tab_test` (spinner→shimmer/empty).
- **WU-05 ExerciseGridCard · hover**: `exercise_grid_card.dart` → `TreinoInteractiveState` (hover/press/focus) + radii/spacing/fonts a tokens. Conservar thumbnail/fallback/CUSTOM/info-chips. TDD hover + CUSTOM.
- **WU-06 Ejercicios · detail dialog**: `exercise_detail_dialog.dart` → `showTreinoDialog`/`TreinoDialog` conservando `ExerciseVideoPlayer` + `TechniqueInstructionItem` + `.when` → `TreinoStateSwitcher`. Ajustar aserciones de dialog en `ejercicios_tab_test`.
- **WU-07 Templates Rutinas · tab**: `templates_tab.dart` → `TreinoStateSwitcher` + `TreinoShimmer` skeleton grid + `TreinoEmptyState`. Actualizar `templates_tab_test` (spinner→shimmer/empty).
- **WU-08 TemplateGridCard · hover**: `template_grid_card.dart` → `TreinoInteractiveState`/press + radii/spacing/fonts a tokens. Preservar nivel chip + cadencia + no-"alumnos". TDD hover.
- **WU-09 Templates · detail dialog**: `template_detail_dialog.dart` → `TreinoDialog` read-only (tokens). Ajustar aserciones en `templates_tab_test`.
- **WU-10 Evidencia AFTER + gates**: regenerar `fase-7/after/`, FULL `flutter test` + `flutter analyze` (baseline 42, cero nuevos), commit final + commit de este `plan-fase7.md`.

## 9. Gates
TDD estricto (`flutter test`): test que falla primero por comportamiento nuevo, mismo commit. Targeted en dev; FULL flutter test + analyze (baseline 42, cero nuevos) al cierre (WU-10). Nunca dos flutter en paralelo. Conventional commits, work-unit commits, sin Co-Authored-By. Cero hex/Colors crudos (scanner activo), TreinoIcon.X, spacing 8/12/14/18/20 (+hairline 4), radios 12/16/20/full, headings Barlow Condensed 700 UPPERCASE, cards sin shadow, dark+light, reduceMotion. Commit incremental obligatorio (anti-stall). Tree limpio de cambios propios al retornar cada WU.

## 10. Review Workload Forecast
~10 slices encadenados; ~60-260 líneas/WU (WU-03 chips-adapter y WU-04 grid-estados los más pesados). 400-line budget risk: Low-Medium. Chained PRs recommended: Yes (un PR/WU sobre rama de fase). Decision needed before apply: No.

# Explore — home-wire-routines

**Change**: `home-wire-routines`
**Fase / Etapa**: Fase 2 · Etapa 5 (cierre)
**Branch**: `feat/home-wire-routines`
**Owner**: Dev B (vos)
**Scope**: Wire CTA "Empezar entrenamiento" → `/workout` (Plantillas). Cleanup de docstrings stale de Etapa 5. Refactor mínimo del test que valida `onPressed: null`.

---

## Current state (post-merge de #13, #14, #15)

### `lib/features/home/widgets/empezar_entrenamiento_card.dart` (108 LOC)

Sin tocar desde el merge de PR #8. Línea relevante (96-101):

```dart
// CTA — onPressed is null until Etapa 5 wires navigation
const HomeCTAButton(
  label: _ctaLabel,
  leadingIcon: TreinoIcon.play,
  onPressed: null,
),
```

`StatelessWidget`, sin params, sin `WidgetRef`. La navegación va inline con `context.go(...)` adentro de un lambda en `onPressed`.

### `lib/features/home/widgets/home_cta_button.dart` (63 LOC)

Interface: `HomeCTAButton({ required String label, VoidCallback? onPressed, IconData? leadingIcon })`. **No hay que cambiar la signature** — solo pasar un callback real.

### `lib/features/home/widgets/esta_semana_card.dart` (50 LOC)

Placeholder OK: "ESTA SEMANA" + "Todavía no entrenaste esta semana." El mockup `esta-semana.png` muestra streak / muscle map / stats — **eso es Fase 4**, no Etapa 5. Solo se limpia el docstring.

### `lib/app/router.dart` (post-merges)

Rutas relevantes (todas dentro de un `ShellRoute` con el `_ShellScaffold` que aplica Scaffold+AppBackground+SafeArea+TreinoBottomBar):

```
/workout                              → WorkoutScreen (PlantillasSection)
/workout/routine/:routineId           → RoutineDetailScreen
/workout/exercise/:exerciseId         → ExerciseDetailScreen
/home, /feed, /coach, /profile        → resto de tabs
```

Bottom bar detecta tab activo con `_kTabs.indexWhere(location.startsWith(t))`. Hacer `context.go('/workout')` desde `/home` activa el tab Workout correctamente.

### Idioma de navegación en el proyecto

- `context.go(path)` — cross-tab / "replace stack root" (login→home, profile-setup→home, taps de bottom bar)
- `context.push(path)` — within-tab drill-down (welcome→register, RoutineCard→detalle de rutina, rutina→ejercicio)

CTA va de `/home` tab → `/workout` tab → **`context.go`** es el idioma correcto.

### `lib/features/workout/workout_screen.dart`

Renderiza `PlantillasSection()` como primer child. `/workout` es el target correcto del CTA — el usuario llega a la lista, elige una plantilla, sigue.

---

## Mockup analysis

**`empezar-entrenamiento.png`**: Card visualmente OK como está. Solo el `onPressed` necesita cambiar. **Cero cambios visuales**.

**`esta-semana.png`**: Streak + muscle map + day-of-week dots + stats — todo data-driven, todo Fase 4. **Cero cambios al EstaSemanaCard** funcionalmente, solo docstring.

---

## Affected files

| Archivo | Tipo | Qué cambia |
|---|---|---|
| `lib/features/home/widgets/empezar_entrenamiento_card.dart` | Modify | `onPressed: () => context.go('/workout')`. Quitar comentario stale línea 96. Update docstring. |
| `lib/features/home/widgets/home_cta_button.dart` | Modify (cosmético) | Quitar nota "add isLoading in Etapa 5 wire" del docstring. Sin cambio funcional. |
| `lib/features/home/widgets/esta_semana_card.dart` | Modify (cosmético) | Quitar "deferred to Etapa 5" del docstring. Sin cambio funcional. |
| `test/features/home/widgets/empezar_entrenamiento_card_test.dart` | Modify | Reemplazar `REQ-HOME-EMPEZAR-004` (tap no-op) con navigation assertion vía GoRouter mock. |
| `lib/app/router.dart` | **No change** | `/workout` ya existe. |
| `lib/features/home/home_screen.dart` | **No change** | `const EmpezarEntrenamientoCard()` sigue siendo `const`. |

**No tocar**: `WorkoutScreen`, `PlantillasSection`, `RoutineCard`, `RoutineDetailScreen`, `ExerciseDetailScreen`, `router.dart` routes, `userProfileProvider`, auth.

---

## Approaches

### Decision A — Navigation idiom

| Approach | Pros | Cons | Esfuerzo |
|---|---|---|---|
| **`context.go('/workout')`** ★ | Cross-tab idiom; bottom bar refleja tab activo; consistente con todas las otras transiciones de tab | — | Trivial |
| `context.push('/workout')` | — | Stack overflow visual; tab bar no se actualiza; semántica incorrecta | Trivial |

### Decision B — Target del CTA

| Approach | Pros | Cons | Esfuerzo |
|---|---|---|---|
| **`/workout` (PlantillasSection root)** ★ | Scope correcto de Fase 2 — el usuario explora la lista y elige; consistente con roadmap | — | Trivial |
| `/workout/routine/:someHardcodedId` | "Más directo" | ID hardcodeado frágil; semántica errónea para "Empezar" en Fase 2 | Bajo |

### Decision C — Cambios a "Esta semana"

| Approach | Pros | Cons | Esfuerzo |
|---|---|---|---|
| **Leave as-is (solo docstring cleanup)** ★ | Placeholder correcto; Fase 4 reescribe la card entera | — | Cero |
| Agregar "Ver plantillas" link | Algo de guía | No está en el mockup; agrega scope; Fase 4 la rehace igual | Bajo |

### Decision D — Dónde va la lógica de navegación

| Approach | Pros | Cons | Esfuerzo |
|---|---|---|---|
| **Inline en la card con `context.go`** ★ | Consistente con `RoutineCard` (que también self-navega); GoRouter mock pattern ya validado | Navegación acoplada a presentación | Trivial |
| Lift a `HomeScreen` como callback param | Separación de concerns | Nuevo constructor param, update del call site, test churn — desproporcionado para 1 línea | Bajo |

### Decision E — Interface de `HomeCTAButton`

**No change**. `onPressed: VoidCallback?` ya acepta cualquier callback. Solo pasar `() => context.go('/workout')`.

### Decision F — Estrategia de test

| Approach | Pros | Cons | Esfuerzo |
|---|---|---|---|
| **Widget test de `EmpezarEntrenamientoCard` con GoRouter mock** ★ | Mirroreja exactamente el pattern de `routine_card_test.dart`; foco; sin overhead de providers | — | Bajo |
| Integration test de `HomeScreen` | Más superficie cubierta | Necesita `userProfileProvider` override + más setup; más pesado | Medio |

Shape del test nuevo (espejo de `routine_card_test.dart:94-128`):

```dart
final router = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (_, __) => Scaffold(body: EmpezarEntrenamientoCard())),
    GoRoute(path: '/workout', builder: (_, __) => const Scaffold(body: Text('WORKOUT'))),
  ],
);
// tap HomeCTAButton → pumpAndSettle → expect(find.text('WORKOUT'), findsOneWidget)
```

---

## Recomendación

Wire `onPressed: () => context.go('/workout')` en `EmpezarEntrenamientoCard.build`. **Una línea funcional**. Tres docstrings cleanup. Un test reemplazado. Total: ~5 líneas cambiadas en 4 archivos. **Cero riesgo arquitectural**.

---

## Risks

1. **`REQ-HOME-EMPEZAR-004` (tap no-op) se rompe al wirearlo** — el test actual hace `tester.tap(HomeCTAButton)` sin GoRouter en el árbol. Al hacer `context.go(...)` sin GoRouter, va a tirar excepción. **Hay que reemplazar el test en el mismo commit, no después**.
2. **Tests de `homeScreen_test.dart`** usan `MaterialApp` (sin GoRouter). Como NO toquetean el CTA, están safe. Conviene un comentario en el archivo aclarando esa asunción para futuro.
3. **`const EmpezarEntrenamientoCard()` en HomeScreen** sigue siendo const después del cambio — el lambda se crea dentro de `build`, no en el constructor. Sin issue.
4. **Numbering de tests** — los tests de home usan formato `REQ-HOME-*`, no `SCENARIO-NNN`. Sin colisiones.

---

## Out-of-scope

- Reemplazar strings hardcoded ("HOY · JUEVES", "PUSH", etc.) → Fase 4
- `EstaSemanaCard` con data real (streak/muscle map/stats) → Fase 4
- `home_header.dart` → fuera de Etapa 5
- `WorkoutScreen`, `PlantillasSection`, detalle de rutina, detalle de ejercicio
- `isLoading` en `HomeCTAButton` — navegación es síncrona, YAGNI
- Cambios a `router.dart` — `/workout` ya existe

---

## Decisiones para propose

| # | Decisión | Recomendación |
|---|---|---|
| A | Navigation idiom | `context.go('/workout')` — cross-tab |
| B | Target del CTA | `/workout` (PlantillasSection root) |
| C | "Esta semana" | Solo docstring cleanup, sin cambio funcional |
| D | Dónde va `context.go` | Inline en la card |
| E | Interface `HomeCTAButton` | Sin cambio |
| F | Test approach | Widget test con GoRouter mock (reemplaza REQ-HOME-EMPEZAR-004) |

---

**Next recommended**: `sdd-propose`

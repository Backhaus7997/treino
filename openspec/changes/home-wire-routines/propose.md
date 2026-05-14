# Propose — home-wire-routines

**Change**: `home-wire-routines`
**Fase / Etapa**: Fase 2 · Etapa 5 (cierre)
**Branch**: `feat/home-wire-routines`
**Artifact store**: openspec
**Depends on**: explore.md (locked decisions A-F)

---

## Why

**Closes Fase 2.** El `EmpezarEntrenamientoCard` quedó con `onPressed: null` desde el merge de la card (PR #8) porque la rama de plantillas todavía no existía. Tras los merges de #13/#14/#15, `/workout` (PlantillasSection) ya está en `router.dart` y los tabs del shell ya rutean correctamente. Esta etapa wirea el único punto colgado: el CTA "Empezar entrenamiento" debe llevar al usuario a la lista de plantillas, dejar el tab Workout activo, y cerrar la Fase 2 sin nuevas funcionalidades.

---

## What

Entregables concretos:

- **Wire** `EmpezarEntrenamientoCard.onPressed` → `() => context.go('/workout')`.
- **Cleanup** del comentario stale en `empezar_entrenamiento_card.dart` línea 96 (`onPressed is null until Etapa 5...`).
- **Cleanup** del docstring de `home_cta_button.dart` (referencia a "add isLoading in Etapa 5").
- **Cleanup** del docstring de `esta_semana_card.dart` (referencia a "deferred to Etapa 5"). Sin cambio funcional ni visual.
- **Reemplazo** del test `REQ-HOME-EMPEZAR-004` (que asumía `onPressed: null` y tapeaba como no-op) por un widget test con `GoRouter` mock que verifica que el tap navega a `/workout`. Mismo pattern que `routine_card_test.dart:94-128`.

No se crea ningún archivo nuevo. No se modifica `router.dart`, `home_screen.dart`, providers, ni rules.

---

## How (locked decisions, per explore.md)

| # | Decisión | Resolución |
|---|---|---|
| A | Navigation idiom | `context.go('/workout')` — cross-tab, mismo idioma que login→home y bottom bar |
| B | CTA target | `/workout` (PlantillasSection root). En Fase 2 no existe "sesión activa del usuario" — el usuario aterriza en la lista y elige |
| C | "Esta semana" card | Sin cambio funcional. Solo docstring cleanup. La versión data-driven (streak / muscle map / stats) es Fase 4 |
| D | Navigation logic location | Inline en `EmpezarEntrenamientoCard.build` como lambda. Consistente con `RoutineCard` que self-navega. Liftearlo a `HomeScreen` sería desproporcionado para 1 línea |
| E | `HomeCTAButton` interface | Sin cambio. `VoidCallback? onPressed` ya acepta cualquier callback |
| F | Test strategy | Widget test de `EmpezarEntrenamientoCard` con `GoRouter` mock de dos rutas (`/home` y `/workout`). Reemplaza `REQ-HOME-EMPEZAR-004` atómicamente en el mismo commit que el wire |

Comparaciones y tradeoffs completos: ver `explore.md` §Approaches.

---

## Out-of-scope

- `EstaSemanaCard` data-driven (streak / muscle map / day-of-week dots / stats) → **Fase 4**
- Reemplazo de strings hardcoded del header ("HOY · JUEVES", "PUSH", etc.) → **Fase 4**
- `home_header.dart` cambios → **fuera de Etapa 5**
- `WorkoutScreen` / `PlantillasSection` / `RoutineCard` / detalle de rutina / detalle de ejercicio → **ya implementado en #13/#14/#15**
- `isLoading` en `HomeCTAButton` → YAGNI (navegación síncrona)
- Cambios a `router.dart` — `/workout` ya existe
- Integration test de `HomeScreen` completo → más pesado que el valor; el widget test del card cubre el contrato

---

## Success criteria

Observables tras el merge:

1. Tap en el CTA "Empezar entrenamiento" desde `HomeScreen` navega a `/workout` (PlantillasSection).
2. La `TreinoBottomBar` refleja "Workout" como tab activo después del tap (lo da `context.go` + el matcher del shell).
3. El nuevo widget test (reemplazo de `REQ-HOME-EMPEZAR-004`) pasa con `GoRouter` mock.
4. `flutter analyze` → 0 issues.
5. `dart format .` → sin cambios pendientes.
6. `home_screen_test.dart` y demás tests existentes siguen pasando (ninguno tapea el CTA, por lo que no hay riesgo de regresión).
7. Los docstrings ya no mencionan "Etapa 5" como pendiente — la etapa está cerrada.

---

## Risks

1. **Atomicidad del test swap**: Si se wirea el `onPressed` sin reemplazar `REQ-HOME-EMPEZAR-004` en el mismo commit, el test viejo se rompe — hace `tap` sin `GoRouter` en el árbol y `context.go` tira excepción. Mitigación: wire + test replacement van en el mismo commit (work-unit).
2. **GoRouter setup en test**: Hay que mirrorear el pattern exacto de `routine_card_test.dart:94-128` (router con dos rutas, `MaterialApp.router`, `pumpAndSettle` tras el tap). Mitigación: copiar el shape verificado, no inventar setup.
3. **`const EmpezarEntrenamientoCard()` en `HomeScreen`**: Sigue siendo `const` después del cambio porque el lambda se crea dentro de `build`, no en el constructor. Verificado, sin issue.

---

## Review Workload Forecast

| Métrica | Valor |
|---|---|
| Estimated production LOC | ~5-10 |
| Estimated test LOC | ~30-50 (reemplazo de un test) |
| Total diff | ~50 LOC max |
| 400-line production budget risk | **Trivial / no concern** |
| Chained PRs recommended | **No** |
| Decision needed before apply | **No — straight to apply** |
| Delivery strategy | Single PR, single commit (wire + test atomic) |

---

**Next recommended**: `sdd-spec` and `sdd-tasks` (design phase skipped — see invocation context for rationale).

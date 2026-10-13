# Workflow — TREINO

Equipo, setup, commits, branching, PRs, ciclo SDD y calidad gates. Si vas a abrir un PR, leé esto.

## Equipo

Equipo de **3 desarrolladores**. Esto implica:

- **Nadie pushea directo a `main` ni a `develop`** (ni siquiera fixes de una línea).
- Toda feature/fix entra por **PR contra `develop`**. **No se exige approve**: hoy no
  hay otro dev que pueda darlo, así que el gate es el CI, los bots (Codex, CodeQL) y
  la prueba en device sobre `develop`.
- **A `main` sólo entra `develop`** (ver [Ramas: develop y main](#ramas-develop-y-main)).
- `main` queda **siempre deployable** (verde, sin trabajo a medio terminar).
- Las decisiones de scope/arquitectura se discuten en el PR o issue antes de implementar.

Ver [`../CONTRIBUTING.md`](../CONTRIBUTING.md) §Equipo y §División de tareas para el mapa de domain ownership y la asignación de tracks paralelos.

## Setup desde una máquina nueva

```bash
git clone https://github.com/Backhaus7997/treino.git
cd treino
./scripts/bootstrap.sh        # instala Flutter, gentle-ai, engram, deps
flutter run
```

Lectura obligatoria antes de tu primer PR:

1. [`../AGENTS.md`](../AGENTS.md) — índice de reglas críticas.
2. [`../CONTRIBUTING.md`](../CONTRIBUTING.md) — onboarding técnico paso a paso.
3. Este archivo (`docs/workflow.md`).
4. `.atl/skill-registry.md` — catálogo de skills de IA. **Generado local**: `gentle-ai skill-registry refresh --force`.

## Calidad gates (antes de cada commit)

1. `flutter analyze` → **0 issues** (no warnings, no infos).
2. `dart format .` aplicado.
3. `flutter test` → verde si hay tests para lo que tocaste (Strict TDD habilitado — ver §Workflow SDD).
4. Si tocaste un freezed → `dart run build_runner build --delete-conflicting-outputs`.

### Gate de regresión visual del Coach Hub

Los cambios de UI en `lib/features/coach_hub/` pasan además por un gate de
goldens que corre **sólo en CI** (job *Visual Gate (Coach Hub)*). Localmente se
saltea a propósito: los PNGs están rasterizados por el runner ubuntu y en macOS
darían rojo por antialiasing, no por un defecto real.

Si tu cambio visual es deliberado, **no edites los PNGs a mano ni los regeneres
en tu máquina** — se regeneran en el runner con un commit marcado:

```bash
git commit --allow-empty -m "chore(gate): regenerar goldens [regen-goldens]"
```

→ Cómo funciona, qué pantallas cubre y cómo agregar una: [docs/visual-gate.md](./visual-gate.md).

## Commits

Convención **Conventional Commits**: `<tipo>(<scope>): <mensaje imperativo>` con cuerpo opcional.

- **Tipos**: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `style`, `perf`.
- **Scopes**: `auth`, `home`, `workout`, `feed`, `coach`, `profile`, `core`, `theme`, `infra`, `deps`.

Ejemplo:

```
feat(coach): add discovery screen with proximity scoring

- New CoachDiscoveryScreen with carousel "En tu gym"
- Implement geohash-based scoring (§4.5 of design doc)
- Reuse TrainerProfile model from Firestore
```

Reglas:

- Un commit = un cambio coherente. **No** mezclar varios features.
- Mensajes en imperativo (`add`, `fix`, no `added`/`fixed`).
- Cuerpo opcional con bullets explicando *qué cambió* y *por qué*.

## Branching

**Una rama por SDD change**, no por fase. Las fases son hitos lógicos (taggeados al final), no ramas long-lived.

### Naming

```
<tipo>/<scope>-<descripción-kebab>
```

Ejemplos:

- `feat/auth-firebase-init`
- `feat/coach-discovery-screen`
- `fix/workout-rest-timer-overflow`
- `chore/upgrade-go-router`
- `docs/restructure-agents-into-docs`

### Flujo

```
1. git fetch origin && git checkout -b <tipo>/<scope>-<name> origin/develop
2. /sdd-new <name>          ← arranca el ciclo SDD (cambios no triviales)
   → explore → propose → spec → design → tasks → apply → verify
3. flutter analyze && flutter test     ← gate de calidad local
4. git push -u origin <branch>
5. gh pr create --base develop         ← SIEMPRE contra develop
6. CI verde + leer bots y anotaciones (Codex, CodeQL)
7. Merge SQUASH desde GitHub
8. git branch -d <branch>
```

### Ramas: develop y main

```
feat/x ──┐
fix/y  ──┼──► develop ──(varios cambios probados)──► main ──► release
docs/z ──┘    builds de prueba        merge commit
```

- **`develop` es la rama de integración.** Todo PR de una rama va contra `develop`, y
  `develop` va normalmente por delante de `main` en commits.
- **Los builds de prueba salen de `develop`** (TestFlight, sideloads, devices). Lo que
  se prueba es lo que después sube a `main`, no cada rama suelta.
- **A `main` sólo se mergea `develop`.** Ningún PR de otra rama entra a `main`. Cuando
  `develop` junta varios cambios probados, se abre `develop → main` y ese merge es el
  release.
- **`develop → main` va con merge commit, no squash.** Un squash deja a `develop` con
  commits que `main` no tiene por SHA, las ramas divergen y el siguiente PR sale con
  «head branch is out of date».
- **Si `main` tiene algo que `develop` no** (no debería pasar con esta regla, pero
  pasa con un merge viejo): sincronizá `main → develop` con merge commit **antes** de
  abrir el próximo `develop → main`.
- **Esto lo hace cumplir GitHub, no la buena voluntad.** La ruleset «main» exige el
  check `main solo desde develop` (`.github/workflows/main-solo-desde-develop.yml`):
  un PR contra `main` desde cualquier otra rama queda rojo y no se puede mergear.
  También prohíbe push directo, force-push y borrar la rama, y sólo permite merge
  commit. La ruleset «develop» prohíbe push directo, force-push y borrarla.
  Dependabot abre sus PRs contra `develop` (`target-branch` en `.github/dependabot.yml`).
- **`develop` no se borra al mergear.** El auto-delete de GitHub borra la rama de
  origen del PR; en `develop → main` la rama de origen es `develop`. Si GitHub la
  borra, se restaura desde el botón del PR antes de seguir.

### Cierre de fase

Cuando todos los cambios de una fase están en `main`:

```bash
git tag -a v0.X.0-fase<N> -m "Fase <N>: <resumen>"
git push origin v0.X.0-fase<N>
```

No hay rama de fase. Se usa el tag como punto de referencia para `git diff v0.1.0-fase0..v0.2.0-fase1`.

### Push directo a main o develop: prohibido

Sin excepciones. Un hot-fix crítico de prod también va por PR a `develop` y sube a
`main` con un `develop → main` inmediato: así `main` nunca tiene un commit que
`develop` no tenga.

## Pull Requests

Usar el template `.github/pull_request_template.md` (se carga solo al abrir el PR).

Reglas:

- **Base `develop`** para todo PR de una rama. **Base `main`** sólo para `develop → main`.
- **No se exige approve.** Hoy no hay otro dev que pueda darlo; exigirlo dejaba todo
  PR trabado o mergeado salteando la regla. Si se suma alguien, se vuelve a exigir.
- **Strategy**: rama → `develop` con **squash and merge**; `develop → main` con
  **merge commit**.
- Branch eliminada al mergear (auto-delete activado en GitHub), salvo `develop`.
- CI verde antes de mergear, y leer bots y anotaciones: un check verde puede traer
  warnings.
- El PR debe linkear al issue (`Closes #N`) si existe.
- Si el cambio modifica `AGENTS.md`, archivos de `docs/`, `CONTRIBUTING.md` o specs SDD,
  la modificación de las reglas se aprueba explícitamente (hoy, el dueño del repo).

### Reviews

- **Conflictos de merge**: el autor del PR los resuelve.
- **Refactors grandes**: NUNCA mezclar con features. PR `refactor/<scope>` separado.

## Workflow SDD (Spec-Driven Development)

Para cualquier feature nuevo de Fase 1+ que toque más de un archivo, usar el ciclo SDD vía gentle-ai:

```
/sdd-new <change-name>
  → explore       (sdd-explore)
  → propose       (sdd-propose)
  → spec          (sdd-spec)
  → design        (sdd-design)
  → tasks         (sdd-tasks)
  → apply         (sdd-apply, código real)
  → verify        (sdd-verify)
  → archive       (sdd-archive)
```

Para cambios pequeños (bugfix de 1-2 líneas, ajuste de copy, rename, doc fix), saltar SDD y commitear directo.

Strict TDD Mode está **habilitado**: en `sdd-apply`, el agente escribe el test antes que el código.

Cada fase queda persistida en Engram bajo `--project treino`.

## Ownership visual de pantallas

Para mantener **consistencia visual** sin caer en feudos de feature, asignamos un **owner visual por pantalla principal**. El owner decide micro-detalles de UX (paleta exacta, spacing, tipografía, micro-interacciones, hierarchy visual) y revisa cualquier PR que toque la UI de esa pantalla.

| Pantalla | Owner visual |
|---|---|
| Coach (athlete view + trainer view) | Dev A |
| Feed (incluye crear post, search, perfil público) | Dev B |
| Profile (perfil propio) | Dev C |

**Lo que NO cambia**: el trabajo funcional se sigue paralelizando por etapa/fase del roadmap. Si la Etapa X de la Fase Y le toca a Dev B, Dev B la implementa — aunque toque archivos de varias pantallas. La división por fases del roadmap es la fuente de verdad para asignación de trabajo.

**Lo que SÍ cambia**: si tu etapa funcional requiere tocar la UI de una pantalla cuyo owner es otro dev, **consultá con el owner antes de tocar**. Esto puede ser un mensaje, un comentario en el issue, o una llamada — el formato no importa, sí la conversación.

Casos típicos donde aplica:
- Fase 4 (Workout++) escribe stats que el Profile muestra → el owner de Profile (Dev C) decide cómo se renderizan esos stats.
- Fase 5 (Coach) agrega chat → el owner de Coach (Dev A) decide la UX del chat.
- Fase 3 (Feed) define `PostCard` → el owner de Feed (Dev B) decide su shape final.

**Pantallas sin owner formal** (Home, Workout, Auth, Routine Detail, Exercise Detail): se tocan como históricamente — quien necesite modificarlas pide review a quien la implementó originalmente (ver `CONTRIBUTING.md` §División de tareas).

**Regla anti-conflict**: para evitar merge hell, NO modifiques archivos compartidos críticos (`router.dart`, `firestore.rules`, `theme/`, widgets compartidos) sin avisar a los otros 2 devs. Estos archivos los toca todo el equipo — coordinar el orden de los PRs evita el 90% de los conflictos.

## Reglas de oro

1. **No bloquearte esperando review**. Si nadie te ve en 48h, mergeás con review de cualquiera.
2. **PR chico**: < 400 líneas. Si crece, splittear en PRs encadenados.
3. **Si tocás un dominio ajeno**, etiquetá al primary como reviewer **obligatorio**.
4. **Refactors grandes** = PR aparte (`refactor/<scope>`). Nunca mezclar con feature.
5. **Conflictos de merge** los resuelve **el autor del PR**, no el reviewer.
6. **Decisiones técnicas** = en issue/PR público, no en chat. Trazabilidad para el dev #4 que se sume.
7. **Cuando dudes**, preguntá en el issue. No tomes decisiones unilaterales en código.
8. **Antes de cada commit**: `flutter analyze` 0 issues + `dart format .` + tests verdes.

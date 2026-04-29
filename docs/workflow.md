# Workflow — TREINO

Equipo, setup, commits, branching, PRs, ciclo SDD y calidad gates. Si vas a abrir un PR, leé esto.

## Equipo

Equipo de **3 desarrolladores**. Esto implica:

- **Nadie pushea directo a `main`** (ni siquiera fixes de una línea, salvo emergencias acordadas).
- Toda feature/fix entra por **PR con review**: mínimo 1 approve antes de mergear.
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
4. [`../.atl/skill-registry.md`](../.atl/skill-registry.md) — catálogo de skills de IA.

## Calidad gates (antes de cada commit)

1. `flutter analyze` → **0 issues** (no warnings, no infos).
2. `dart format .` aplicado.
3. `flutter test` → verde si hay tests para lo que tocaste (Strict TDD habilitado — ver §Workflow SDD).
4. Si tocaste un freezed → `dart run build_runner build --delete-conflicting-outputs`.

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
1. git checkout main && git pull
2. git checkout -b <tipo>/<scope>-<name>
3. /sdd-new <name>          ← arranca el ciclo SDD (cambios no triviales)
   → explore → propose → spec → design → tasks → apply → verify
4. flutter analyze && flutter test     ← gate de calidad local
5. git push -u origin <branch>
6. /branch-pr               ← crea el PR contra main
7. Esperar 1+ approve
8. Merge SQUASH desde GitHub
9. git checkout main && git pull && git branch -d <branch>
```

### Cierre de fase

Cuando todos los cambios de una fase están en `main`:

```bash
git tag -a v0.X.0-fase<N> -m "Fase <N>: <resumen>"
git push origin v0.X.0-fase<N>
```

No hay rama de fase. Se usa el tag como punto de referencia para `git diff v0.1.0-fase0..v0.2.0-fase1`.

### Push directo a main: prohibido

Salvo:

- Hot-fix crítico de prod (acordado en grupo, sin demora).
- Updates triviales en `README.md` por el lead del repo.

Cualquier otro push a `main` debe revertirse.

## Pull Requests

Usar el template `.github/pull_request_template.md` (se carga solo al abrir el PR).

Reglas:

- **1 approve mínimo** antes de mergear.
- **Strategy: Squash and merge** (un commit limpio en main por PR).
- Branch eliminada al mergear (auto-delete activado en GitHub).
- CI debe pasar antes del approve (cuando lo cableemos).
- El PR debe linkear al issue (`Closes #N`) si existe.
- Si el cambio modifica `AGENTS.md`, archivos de `docs/`, `CONTRIBUTING.md` o specs SDD, el reviewer debe aprobar la modificación de las reglas explícitamente en el comentario.

### Reviews — SLA del equipo

- **24 h SLA**: si nadie revisa en 24h, ping en chat.
- **48 h hard limit**: si nadie revisa en 48h, podés mergear con review de cualquier otro dev (no del owner).
- **Conflictos de merge**: el autor del PR los resuelve, no el reviewer.
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

## Reglas de oro

1. **No bloquearte esperando review**. Si nadie te ve en 48h, mergeás con review de cualquiera.
2. **PR chico**: < 400 líneas. Si crece, splittear en PRs encadenados.
3. **Si tocás un dominio ajeno**, etiquetá al primary como reviewer **obligatorio**.
4. **Refactors grandes** = PR aparte (`refactor/<scope>`). Nunca mezclar con feature.
5. **Conflictos de merge** los resuelve **el autor del PR**, no el reviewer.
6. **Decisiones técnicas** = en issue/PR público, no en chat. Trazabilidad para el dev #4 que se sume.
7. **Cuando dudes**, preguntá en el issue. No tomes decisiones unilaterales en código.
8. **Antes de cada commit**: `flutter analyze` 0 issues + `dart format .` + tests verdes.

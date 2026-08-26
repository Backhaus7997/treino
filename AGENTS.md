# AGENTS.md — TREINO

Reglas que cualquier agente de IA (Claude Code, Cursor, Codex, OpenCode, Copilot, Gemini CLI, Windsurf) y dev humano debe respetar al trabajar en este repo. **Loadeado automáticamente al inicio de cada sesión** — esto es la "constitución" del proyecto.

Este archivo es **un índice + las reglas críticas mínimas**. Para detalle completo, ir a los archivos de `docs/` linkeados.

---

## ⚠️ Entornos — leer antes de correr cualquier comando

**`treino-dev` es PRODUCCIÓN.** No existe un entorno de desarrollo separado.

El nombre dice "dev" por razones históricas: el project ID de Firebase no se puede
cambiar una vez creado. En ese proyecto viven los usuarios reales de la app — sus
pagos, turnos, mediciones, chats y perfiles comerciales publicados.

- Todo comando con `--project treino-dev` **toca datos de usuarios reales**.
- El alias `prod` de `.firebaserc` apunta ahí. En docs y runbooks va explícito:
  `--project prod`.
- **El default de `.firebaserc` ya NO puede llegar a producción** (#840). Es
  `demo-treino`: Firebase trata el prefijo `demo-` como proyecto offline del
  emulador, así que un `deploy` o un `firestore:delete` **sin `--project`
  falla** en vez de resolver a `treino-dev`. Era el agujero real — el repo vive
  en 29 directorios a la vez (raíz + `.claude/worktrees/`), cada uno con su
  copia de `.firebaserc` y un agente adentro.
  - Corolario 1: para tocar producción **hay que escribir `--project prod`**. Que
    duela un poco es el punto.
  - Corolario 2 — **esto cubre el CLI de `firebase`, NO los scripts de Node**.
    Los `scripts/backfill_*.js` (y `cleanup_*`, `restore_*`, `seed_*`) **no leen
    `.firebaserc` nunca**: resuelven el proyecto con
    `admin.initializeApp({credential: cert(require('./sa-key.json'))})` —
    o sea, el `project_id` de la key — y hardcodean `treino-dev` cuando hay
    `FIRESTORE_EMULATOR_HOST`. Verificable: los hits de
    `rg 'firebaserc' -g '*.js' scripts/` son **todos comentarios** — ni un solo
    `require`/`readFile` del archivo. **Un backfill sin `--project` no falla:
    `--project` ni siquiera existe como flag** (`backfill_gym_ids.js:102` sólo
    parsea `--dry-run` y `--allow-prod`). Para esos scripts la única barrera sigue
    siendo tener o no `scripts/sa-key.json`, y su guard `assertDevProject()`
    **no protege**: testea `/dev/i` contra el project id, y `treino-dev`
    matchea — es exactamente el bug de #826. Antes de correr cualquiera de
    ellos, leé qué proyecto imprime en la primera línea.
  - Corolario 3: los comandos del **emulador** llevan `--project treino-dev`
    explícito, y no es contradictorio. `emulators:*` no sale a la red de los
    servicios emulados; ese id es sólo el *namespace* local donde escriben la
    app (`lib/firebase_options.dart`) y las semillas
    (`scripts/seed_emulator_full.js`), y el proyecto al que
    `emulators.singleProjectMode: true` pinea el `firestore.get()`
    cross-service de las reglas de Storage. Con otro id la suite de reglas se
    pone **roja** (medido: `chat-media-storage.test.js`, 2 tests). Ya está
    resuelto en `scripts/emulator.sh` y `scripts/test_rules.sh`: **usalos** en
    vez de escribir `firebase emulators:start` a mano, que ahora resolvería
    `demo-treino` y te dejaría la UI de :4444 mirando un namespace vacío.
  - Corolario 4 — **`firebase use` le gana al default, y no deja rastro en el
    repo**. `firebase use <alias>` escribe `activeProjects` en
    `~/.config/configstore/firebase-tools.json`, que **no está versionado**. La
    precedencia real es `--project` → `activeProjects[projectRoot]` → default de
    `.firebaserc` (`firebase-tools/lib/command.js:196`, `applyRC`). Medido
    contra 13.35.1 con un configstore aislado, mismo `.firebaserc` de este repo:

    | `activeProjects[dir]` | proyecto que resuelve un comando pelado |
    | --------------------- | --------------------------------------- |
    | (ausente)             | `demo-treino` ← el default nos protege  |
    | `prod`                | **`treino-dev`** ← PRODUCCIÓN           |

    O sea: **un solo `firebase use prod` desarma el fix de #840 en ese
    directorio, para siempre y en silencio.** Dos cosas lo acotan, las dos
    medidas: la clave es el *directorio* (`projectRoot`), así que pinea un
    directorio y no los otros 28; y hoy en esta máquina la clave `activeProjects`
    **no existe** — nadie corrió nunca `firebase use`. Si vas a correr algo
    destructivo, **escribí `--project` siempre** en vez de confiar en el
    default: es lo único que gana en toda la cadena.
  - Corolario 5 — **worktrees**: `.firebaserc` está versionado, así que todo
    worktree creado después de #840 hereda el default seguro solo — no hay nada
    que regenerar. Los que ya existían siguen con el viejo hasta que rebaseen
    main, y esperar eso no es una mitigación. Para cerrarlos hoy —y para
    auditar el `activeProjects` del corolario 4— hay
    `bash scripts/sync_firebaserc_worktrees.sh` (dry-run por default, `--write`
    aplica). Al escribir esto lista **28 pendientes**.
- **Nunca** corras `firestore:delete`, un script de `scripts/backfill_*.js`, ni un
  `deploy` de rules/indexes/functions contra ese proyecto sin confirmarlo con un
  humano primero. Aplica la misma regla de "frená y confirmá" que el resto de este
  archivo.
- Los checklists de `openspec/changes/` traen comandos de escritura contra ese
  proyecto, y los npm scripts de `scripts/package.json` escriben por Admin SDK
  —saltándose las rules— sin nombrar el proyecto en pantalla. Antes de ejecutar
  un ítem de ahí: [openspec/AGENTS.md](./openspec/AGENTS.md) y
  [scripts/README.md](./scripts/README.md).
- Para desarrollo local **usá el emulador**, no el proyecto real:
  `./scripts/emulator.sh` + `flutter run --dart-define=USE_EMULATOR=true`.
- Backup: hay un schedule diario de Firestore con 28 días de retención
  (`firebase firestore:backups:schedules:list --project prod`).
  **No cubre Cloud Storage ni los usuarios de Auth.**

→ Contexto y decisión: [#826](https://github.com/Backhaus7997/treino/issues/826).

---

## Índice de la documentación

| Doc | Cuándo leerlo |
|---|---|
| [docs/product.md](./docs/product.md) | Naming (TREINO/Coach/Entreno IA), tab bar, roles, scope (in/out), tono |
| [docs/design-system.md](./docs/design-system.md) | Paletas, tipografía, spacing, radii, reglas de código UI |
| [docs/architecture.md](./docs/architecture.md) | Stack, estructura, modelos freezed, memoria persistente Engram |
| [docs/performance.md](./docs/performance.md) | State management, rebuilds, batería, multi-device, profiling |
| [docs/workflow.md](./docs/workflow.md) | Setup, equipo, commits, branching, PRs, ciclo SDD, gates de calidad |
| [docs/roadmap.md](./docs/roadmap.md) | Fases 0-6, Fase 1 desglosada en 7 etapas con owner sugerido |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Onboarding técnico paso a paso para devs nuevos |
| [.atl/skill-registry.md](./.atl/skill-registry.md) | Catálogo de las 24 skills de IA disponibles |

---

## Reglas críticas (siempre activas)

Estas son las que más fácil se olvidan o más fácil rompen el producto. Si el usuario te pide algo que las viola, **frená y confirmá** antes de implementar.

### 1. Naming (no confundir)

- **TREINO** = nombre de la marca/app.
- **Coach** = nombre del módulo y la pestaña de Personal Trainer. **No** decirle "TREINO" al tab.
- **Entreno IA** = feature de IA generadora (NO usar "Coach IA").
- Las clases del dominio del PF mantienen prefijo `Trainer*` (`TrainerProfile`, etc.) porque describen al actor-persona.

→ Detalle en [docs/product.md](./docs/product.md).

### 2. Diseño (no negociable)

- **Paleta única**: Mint Magenta (`accent #2CE5A2`, `highlight #C123E0`, `ink #0A0A0A`). No hay alterna — Electric Violet fue dropeada antes del lanzamiento.
- **Dos temas**: `AppPalette.mintMagenta` (dark) y `mintMagentaLight` (light). La app arranca en `ThemeMode.system` — el tema claro se sirve desde el primer arranque.
- **Todo par de tokens donde `accent` sea FONDO se mide en las DOS paletas.** El mint es idéntico en ambas pero `bg` no: `palette.bg` sobre `accent` da 12.10:1 en dark y **1.57:1 en light**. Para texto sobre acento va `TreinoButtonTokens.foreground` (ink invariante), nunca `palette.bg`.
- **Headings**: Barlow Condensed 700 UPPERCASE.
- **Body**: Barlow 400/600/700.
- **Spacing**: sólo `8 · 12 · 14 · 18 · 20` px para separar elementos. No 16/24. El 4 existe **sólo** como `AppSpacing.hairline`, para separaciones ópticas sub-8 y gutters internos de un componente del kit — nunca como padding de layout. Ver su dartdoc.
- **Nunca** HEX literal en widgets — usar `AppPalette.of(context).accent`.
- **Nunca** PhosphorIcons directo — usar `TreinoIcon.X`.

→ Detalle en [docs/design-system.md](./docs/design-system.md).

### 3. Roles del producto (inmutables)

- `UserProfile.role`: `"athlete" | "trainer"`. **Inmutable** post-creación.
- Signup público **siempre** crea `athlete` (forzado por regla Firestore).
- Trainers se crean **manualmente** por el equipo TREINO vía Firebase Admin SDK. Sin self-service.

→ Detalle en [docs/product.md](./docs/product.md).

### 4. Out of scope (NO implementar)

Aunque el repo viejo lo tenía, en TREINO Flutter quedan **fuera**:

Retos / Challenges · Missions · Bets · Levels / XP · Gamificación.

Si el usuario pide alguno → **frená y confirmá**.

**Rankings SÍ está en scope** y ya está implementado: ranking por gym, opt-in
explícito del atleta (rachas / volumen / main lifts). Vive en la 2da página
swipeable del tab **Feed** (`/feed?tab=rankings`). `/workout?tab=rankings` y
`/profile/rankings` son hosts anteriores y redirigen ahí — no los borres, hay
bookmarks y notificaciones vivas apuntándoles. No lo confundas con
"Gamificación" de la lista de arriba. → Detalle en [docs/product.md](./docs/product.md).

### 5. Tab bar (5 tabs, Inicio al medio)

`Entrenar · Feed · Inicio · Coach · Perfil`. Discovery de PFs vive **sólo** en la tab Coach. Feed es 100% social.

### 6. Performance (cero rebuilds innecesarios)

- Estado de negocio = **Riverpod 2** siempre. `setState` sólo para presentación local.
- `ref.watch` del provider más chico posible. Usar `select()` para granularidad.
- `const` widgets siempre que se pueda.
- `ListView.builder` para listas largas.
- Imágenes: `cached_network_image` con `memCacheWidth/Height`.
- Streams Firestore: cancelarlos en `dispose()`.

→ Detalle en [docs/performance.md](./docs/performance.md).

### 7. Calidad gates (antes de cada commit)

1. `flutter analyze` → **0 issues**.
2. `dart format .`.
3. `flutter test` (verde si hay tests del cambio).
4. Si tocaste freezed → `dart run build_runner build --delete-conflicting-outputs`.

### 8. Branching y PRs

- Equipo de **3 devs**. Nadie pushea directo a `main`.
- **Una rama por cambio** (no por fase). Naming: `<tipo>/<scope>-<descripción-kebab>`.
- PR con **1+ approve**, **squash and merge**, branch auto-delete.
- Cambios no triviales → ciclo SDD vía gentle-ai (`/sdd-new <name>`).
- Si modificás `AGENTS.md` o algo en `docs/` → reviewer aprueba **explícitamente** la modificación de las reglas.
- **Después de todo rebase y antes de todo force-push**, por cada archivo del diff:
  `diff <(git show origin/main:ARCHIVO) ARCHIVO | rg '^<'` — ver §11.

→ Detalle en [docs/workflow.md](./docs/workflow.md).

### 9. Memoria persistente

Engram MCP guarda decisiones bajo `--project treino`. **Es local por máquina** — para decisiones team-wide, escribirlas en `docs/` y commitear.

→ Detalle en [docs/architecture.md](./docs/architecture.md).

---

### 10. Trabajo en paralelo (varias herramientas, varios worktrees)

Este repo corre con varios agentes a la vez (Claude Code, Codex, Cursor…) y con
worktrees en `.claude/worktrees/`. Cuatro reglas:

**a. Antes de empezar, fijate si ya hay alguien en el mismo scope.**

```bash
./scripts/agent-ledger.sh check 826    # ¿hay otro agente en este issue?
./scripts/agent-ledger.sh list         # todo lo que está en curso
```

Si `check` sale con error, **frená y confirmá** con el usuario antes de seguir.
Dos ramas arreglando el mismo bug es la forma más cara de perder trabajo.

**b. Al arrancar, anotate. Al terminar o abandonar, borrate.**

```bash
./scripts/agent-ledger.sh claim 826 "banner de entornos en docs"
./scripts/agent-ledger.sh release
```

El ledger vive en `.git/agent-ledger.tsv` — el único directorio que comparten
todos los worktrees y que nunca se commitea. No lo edites a mano. Si tu
herramienta aparece como `unknown`, exportá `AGENT_NAME` (ej. `AGENT_NAME=codex`).

**c. Lo que tiene que sobrevivir a tu sesión va a un archivo del repo.**

Engram es **local por máquina** (regla 9): lo que guardes ahí no lo ve Codex, ni
otro worktree, ni vos mañana desde otra máquina. Las decisiones van a `docs/` o a
`openspec/changes/<name>/`, y se commitean. Ese es el formato de handoff entre
herramientas: un agente deja el SDD escrito, otro lo levanta y sigue.

**d. Una sola fuente de reglas.**

`AGENTS.md` es la única. `CLAUDE.md` es un puntero vacío **a propósito** — no le
agregues reglas ni resúmenes de conveniencia. Ya pasó una vez: el "Quick
reference" de `CLAUDE.md` se desincronizó y Claude Code y Codex quedaron leyendo
constituciones distintas.

### 11. Verificación — las dos que nos costaron caro

Estas dos salieron de una jornada entera de arreglos de seguridad (#826, #831, #838).
No son teoría: cada una tiene un incidente atrás.

#### 11.1 Una advertencia falsa es PEOR que ninguna

Un mensaje tranquilizador que miente desactiva la sospecha justo donde hacía falta.
Casos reales de este repo:

- `treino-dev` **suena** a entorno descartable. Es producción (§ Entornos).
- El guard de los backfills usaba `/dev/i.test(projectId)`. Contra `treino-dev` ese
  guard **pasaba** — la única protección contra escrituras a producción estaba, por
  construcción, apagada justo contra producción.
- `extract_exercise_thumbnails.js` imprimía **`destino: EMULADOR`** y subía a Storage
  de producción: chequeaba el emulador de Firestore y nada más.
- Un header de test decía **"SUPERSET"** y era subset: al quedarse con esa versión,
  otro test levantaba `deploy_rules.js` con la credencial real y deployaba reglas.

**La regla:** antes de escribir un mensaje que tranquiliza —"seguro", "sólo dev",
"ya cubierto", "cerrado"— verificá que sea cierto. Si no lo podés verificar, escribí
lo que sí sabés. Un "no sé si esto toca producción" honesto vale más que un "esto es
seguro" que no chequeaste.

**Corolario para PRs e issues:** una afirmación de completitud sin un comando
reproducible al lado no cuenta. Si decís "barrí todo el repo", publicá el comando —
que otro pueda correrlo y refutarte es lo que la hace valer. Un barrido de este tipo
falló cinco veces seguidas, cada una en un eje distinto: el path, la regex, la forma
del comando, el criterio de descarte y la doctrina. Ninguna se encontró leyendo el
reporte; todas, corriendo el comando.

#### 11.2 Un rebase puede borrar trabajo ajeno SIN marcar conflicto

Si tu rama sale de una base vieja y reescribe un archivo entero, git no tiene forma de
saber que estás pisando trabajo de otro: ve un archivo distinto de punta a punta y se
queda con el tuyo. `git status` limpio, cero marcadores, tests en verde, y medio PR
ajeno borrado.

Pasó con `scripts/README.md`: el rebase lo auto-mergeó sin conflicto y el resultado
reintroducía, palabra por palabra, las afirmaciones falsas que el PR pisado existía
para corregir.

**El chequeo, obligatorio antes de todo force-push post-rebase**, por cada archivo del
diff:

```bash
diff <(git show origin/main:ARCHIVO) ARCHIVO | rg '^<'
```

- Salida vacía → tu cambio es **aditivo**. Seguí.
- Cualquier salida → estás **borrando** algo que está en `main`. Que sea a propósito, y
  que quede escrito en el mensaje del commit por qué.

## Setup desde una máquina nueva

```bash
git clone https://github.com/Backhaus7997/treino.git
cd treino
./scripts/bootstrap.sh
flutter run
```

→ Onboarding completo en [CONTRIBUTING.md](./CONTRIBUTING.md).

## Estado actual del roadmap

- [x] **Fase 0** — Bootstrap + tema + 5 tabs.
- [ ] **Fase 1** — Auth + Firebase + ProfileSetup (en curso, etapa 1 ✅).
- [ ] Fases 2-6 → ver [docs/roadmap.md](./docs/roadmap.md).

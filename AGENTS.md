# AGENTS.md — TREINO

Reglas y convenciones que cualquier agente de IA (Claude Code, Cursor, Codex, OpenCode, Copilot, Gemini CLI, Windsurf) debe respetar al trabajar en este repo. **Loadeado automáticamente al inicio de cada sesión** — esto es la "constitución" del proyecto.

## Proyecto

TREINO — fitness app multiplataforma (Flutter) con tracking de entrenamientos, feed social, y módulo de Personal Trainers. Repo: https://github.com/Backhaus7997/treino

## Equipo

Equipo de **3 desarrolladores**. Esto implica:
- **Nadie pushea directo a `main`** (ni siquiera fixes de una línea, salvo emergencias acordadas).
- Toda feature/fix entra por **PR con review**: mínimo 1 approve antes de mergear.
- `main` queda **siempre deployable** (verde, sin trabajo a medio terminar).
- Las decisiones de scope/arquitectura se discuten en el PR o issue antes de implementar.

## Setup desde una máquina nueva

Si recién clonás el repo, ver [CONTRIBUTING.md](./CONTRIBUTING.md) para la guía completa. Resumen:

```bash
git clone https://github.com/Backhaus7997/treino.git
cd treino
./scripts/bootstrap.sh        # instala Flutter, gentle-ai, engram, deps
flutter run
```

Lectura obligatoria antes de tu primer PR: este archivo + [CONTRIBUTING.md](./CONTRIBUTING.md) + [.atl/skill-registry.md](./.atl/skill-registry.md).

## Stack

- **Flutter** 3.41 / **Dart** ^3.5.0
- **State**: `flutter_riverpod` 2 (`AsyncNotifier`, `Provider`)
- **Routing**: `go_router` (`ShellRoute` para tab bar)
- **Tipografía**: `google_fonts` — Barlow + Barlow Condensed
- **Íconos**: `phosphor_flutter` (regular + fill)
- **Modelos**: `freezed` + `json_serializable` + `build_runner`
- **Lints**: `flutter_lints` 4
- **Firebase** (Auth, Firestore, Storage, Functions, Messaging) — pendiente Fase 1
- **MCP locales**: Engram (memoria persistente, `engram mcp`)

## Naming (crítico — no confundir)

- **TREINO** = nombre de la marca/app. Aparece en logo, splash, App Store, plays.
- **Coach** = nombre del módulo y de la pestaña que gestiona Personal Trainers.
- **Entreno IA** (feature de IA generadora de rutinas) → **NO usar** el nombre antiguo "Coach IA". La pantalla en Flutter es `WorkoutAIView`, ruta `/workout/ai`.
- Las clases de dominio del PF mantienen el prefijo `Trainer*` (`TrainerProfile`, `TrainerStudentLink`, etc.) porque describen al actor-persona, no al feature.

## Tema y diseño

- **Paleta default**: Mint Magenta (`accent #2CE5A2`, `highlight #C123E0`, `ink #0A0A0A`).
- **Paleta alterna**: Electric Violet (`accent #34E062`, `highlight #7C3AED`). Toggle en Perfil → Apariencia.
- **Modo**: oscuro siempre (`Brightness.dark`). No hay light theme.
- **Headings**: Barlow Condensed 700, UPPERCASE, letter-spacing 0.5.
- **Body**: Barlow 400 / 600 / 700, Title Case.
- **Spacing scale**: `8 · 12 · 14 · 18 · 20` px. **No** usar 4/16/24.
- **Radii**: `12` chips, `16` cards (default), `20` hero cards, **full pill** para CTAs principales.

### Reglas de código de UI (no negociables)

- **Nunca** HEX literal en widgets. Usar `AppPalette.of(context).accent` (o `.highlight`, `.bg`, `.bgCard`, `.border`, `.textPrimary`, `.textMuted`).
- **Nunca** `PhosphorIconsRegular.X` o `PhosphorIconsFill.X` directo. Usar `TreinoIcon.tabHome`, `TreinoIcon.streak`, etc. Si falta uno, agregarlo a `lib/core/widgets/treino_icon.dart`.
- **Nunca** hard-code de strings de tab labels o feature names. Centralizar en constantes o en futuros archivos de localización.

## Estructura del repo

Feature-first en `lib/features/<name>/`. Compartido en `lib/app/` y `lib/core/`.

```
lib/
├── main.dart
├── app/                 # bootstrap + tema + routing
│   ├── app.dart
│   ├── router.dart
│   └── theme/{app_palette, app_theme, app_background}.dart
├── core/                # widgets compartidos, utils
│   └── widgets/{treino_icon, treino_bottom_bar, treino_button}.dart
└── features/
    ├── home/    workout/    feed/    coach/    profile/
    │       ├── view/<screen>.dart
    │       ├── state/<notifier>.dart
    │       └── data/<repository>.dart
```

## Roles del producto

- `UserProfile.role`: `"athlete" | "trainer"`. **Inmutable** después de la creación.
- Signup público (email / Google / Apple) **siempre** crea `role = "athlete"`. Una regla Firestore lo fuerza:
  ```
  match /users/{uid} {
    allow create: if request.auth.uid == uid
                  && request.resource.data.role == "athlete";
    allow update: if request.auth.uid == uid
                  && request.resource.data.role == resource.data.role;
  }
  ```
- Cuentas de **trainers** sólo se crean **manualmente** por el equipo TREINO vía Firebase Admin SDK. No hay UI self-service para volverse PF.
- En la app, link discreto en login: `¿Sos entrenador? Pedí tu alta` que abre form externo (Tally/Typeform).

## Tab bar (5 tabs, Inicio al medio)

| # | Tab | Ícono | Ruta |
|---|---|---|---|
| 1 | Entrenar | `TreinoIcon.tabWorkout` | `/workout` |
| 2 | Feed | `TreinoIcon.tabFeed` | `/feed` |
| 3 | **Inicio** | `TreinoIcon.tabHome` | `/home` |
| 4 | Coach | `TreinoIcon.tabCoach` | `/coach` |
| 5 | Perfil | `TreinoIcon.tabProfile` | `/profile` |

Discovery de PFs vive **sólo** en la tab Coach. El Feed es 100% social (amigos · comunidad · público), sin contenido de trainers.

## Out of scope — NO implementar

Aunque el repo viejo (`gymrankiOS` / `gymrank` Android) los tenía, en TREINO Flutter quedan **fuera**:
- Ranking (global, semanal, mensual, gym)
- Retos / Challenges
- Missions
- Bets
- Levels / XP / Puntos comparativos
- Gamificación en general

Si el usuario pide implementar alguno, **frená y confirmá** antes de hacerlo — viola scope acordado.

## Modelos

- Siempre con **freezed** + **json_serializable**:
  ```dart
  @freezed
  class UserProfile with _$UserProfile { ... }
  ```
- Después de editar un freezed file, correr:
  ```bash
  dart run build_runner build --delete-conflicting-outputs
  ```
- Compatibilidad con Firestore via `fromFirestore()` / `toFirestore()` factories.

## Calidad gates (antes de cada commit)

1. `flutter analyze` → **0 issues** (no warnings, no infos).
2. `dart format .` aplicado.
3. `flutter test` → verde si hay tests para lo que tocaste (Strict TDD habilitado — ver §Workflow).
4. Si tocaste un freezed → `dart run build_runner build --delete-conflicting-outputs`.

## Performance, batería y rebuilds (no negociables)

La app corre en mobile — cada rebuild innecesario y cada render pesado degrada la experiencia y consume batería. Reglas obligatorias:

### State management
- Todo el estado **vive en Riverpod 2** (`AsyncNotifier`, `Notifier`, `Provider`, `StateProvider` cuando aplica).
- **No** usar `setState` en widgets que tienen lógica de negocio. Reservalo sólo para estado *puramente local de presentación* (animaciones, controllers, focus) en `StatefulWidget`s pequeños.
- **No** usar `InheritedWidget` ni `ChangeNotifier` directos. Si hace falta, encapsular detrás de Riverpod.

### Evitar rebuilds innecesarios
- `Consumer` y `ref.watch` **siempre del provider más chico posible**. Nunca watchear un provider grande para leer un solo campo.
- Usar `select` para granularidad fina:
  ```dart
  final name = ref.watch(userProfileProvider.select((p) => p.fullName));
  ```
- Splittear widgets: el subtree que rebuildea cuando cambia un dato, debe ser el más chico posible (extraer a un widget hijo y watchear adentro).
- Marcar widgets como `const` siempre que se pueda. `prefer_const_constructors` está activo en lints.
- **No** anidar `Consumer` innecesariamente: uno chico cerca de la hoja > uno grande que envuelve media pantalla.
- Para listas largas: usar `ListView.builder` / `SliverList.builder` (no `ListView(children: [...])`).

### Renders pesados
- Imágenes remotas: siempre `cached_network_image` con `memCacheWidth` y `memCacheHeight` ajustados al tamaño real de pantalla. Nunca cargar 4K en una thumbnail.
- Animaciones: preferir implícitas (`AnimatedContainer`, `AnimatedOpacity`) antes que `AnimationController`. Si usás controller, **dispose** en `dispose()`.
- `Opacity` sobre subtrees grandes es caro: usar `FadeTransition` o `AnimatedOpacity` (que bypassan el repaint).
- Sombras y blurs: medir antes de dejarlos en producción. `BackdropFilter` es muy caro — reservar a casos muy puntuales.
- **No** abrir streams Firestore que nunca cierran. Cancelar suscripciones en el dispose del Notifier.

### Batería
- Timers: pausar cuando la app va a background (usar `AppLifecycleState`).
- Geolocalización: no leer pasivamente — sólo on-demand cuando el usuario toca "Buscar PFs cerca de mí" (regla del producto, ver §Cercanía PFs en `DOCUMENTACION_FLUTTER.md`).
- Polling de Firestore: usar listeners en vez de polling. Y cerrarlos al salir de la pantalla.
- Wake-lock: nunca a menos que sea explícitamente necesario (ej. Workout Player con timer corriendo). Liberar al salir.

### Testing visual / multi-device

Antes de mergear cualquier PR que toque UI:

- **Tamaños de pantalla**: probar en al menos:
  - iPhone SE (3rd gen) — ancho 375pt, pantalla chica.
  - iPhone 15 Pro Max — ancho 430pt, pantalla grande con notch dinámico.
  - iPad mini — modo retrato y landscape (responsive).
  - Android: Pixel 5 (340dp) y Pixel 7 Pro (412dp).
- **Sistemas operativos**:
  - iOS 16 mínimo (deployment target).
  - iOS 17/18 (current).
  - Android API 24 mínimo.
  - Android 14 (API 34, target).
- **Modos**: oscuro siempre (la app es dark-only, no hay light theme).
- **Orientación**: portrait por defecto. Landscape opcional excepto en Workout Player que sí debe soportarlo.
- **Densidad de texto**: probar con dynamic type / font scale grande (Settings → Display → Text Size). El layout no debe romperse.

Si no podés probar en algún device físico, usar simuladores. La skill `flutter-build-responsive-layout` ayuda a manejar `MediaQuery` y `LayoutBuilder` para que el código sea adaptive desde el primer commit.

### Profiling cuando algo se siente lento

- `flutter run --profile` en device físico (no simulator — el simulator miente para performance).
- Abrir DevTools (`d` en consola) → tab **Performance** → grabar interacción → buscar frames > 16ms.
- Tab **CPU Profiler** para encontrar funciones costosas.
- Si rebuilds son el problema: tab **Performance** → "Track Widget builds" → ver qué se está rebuildando que no debería.

## Workflow para cambios grandes

Usar **SDD** (Spec-Driven Development) vía gentle-ai. Para cualquier feature nuevo de Fase 1+:

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

Para cambios pequeños (bugfix de 1-2 líneas, ajuste de copy, rename), saltar SDD y commitear directo.

Strict TDD Mode está **habilitado**: en `sdd-apply`, el agente escribe el test antes que el código.

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

### Flujo
```
1. git checkout main && git pull
2. git checkout -b feat/<scope>-<name>
3. /sdd-new <name>          ← arranca el ciclo SDD
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
No hay rama de fase. Se usa el tag como punto de referencia.

### Push directo a main: prohibido

Salvo:
- Hot-fix crítico de prod (acordado en grupo, sin demora).
- Updates triviales en `README.md`/`CONTRIBUTING.md` por el lead del repo.

Cualquier otro push a `main` debe revertirse.

## Pull Requests

Usar el template `.github/pull_request_template.md` (se carga solo al abrir el PR).

Reglas:
- **1 approve mínimo** antes de mergear.
- **Strategy: Squash and merge** (un commit limpio en main por PR).
- Branch eliminada al mergear (auto-delete activado en GitHub).
- CI debe pasar antes del approve (cuando lo cableemos en Fase 0.5).
- El PR debe linkear al issue (`Closes #N`) si existe.
- Si el cambio cambia AGENTS.md, CONTRIBUTING.md o specs SDD, el reviewer debe aprobar la modificación de las reglas explícitamente en el comentario.

## Memoria persistente

Engram MCP guarda decisiones bajo `--project treino`. Memorias clave existentes:
- `sdd-init/treino` — contexto completo del proyecto
- `sdd/treino/testing-capabilities`
- `skill-registry`

Para recuperar contexto en una sesión nueva:
```bash
engram context treino
engram search "<query>" --project treino
```

Para guardar nuevas decisiones que tomemos:
```bash
engram save "<title>" "<content>" --type decision --project treino --topic "<unique-key>"
```

## Documentación adicional

- **Especificación completa de producto y diseño** (paletas, módulos, roadmap, mocks): `~/Desktop/TREINO-Documentacion-Flutter.{md,html}` (también en el repo gymrankiOS de planning).
- **Skills disponibles** en este proyecto: `.atl/skill-registry.md` (24 skills indexadas).
- **Brand assets**: paleta y logos del PDF `brand_palette_v2.pdf`.

## Roadmap (estado actual)

- [x] **Fase 0** — Bootstrap + tema + 5 tabs vacías + Phosphor.
- [ ] **Fase 1** — Auth (email/Google/Apple) + Firebase + ProfileSetup.
- [ ] **Fase 2** — Home (paridad con mockup) + Rutinas básicas.
- [ ] **Fase 3** — Feed social.
- [ ] **Fase 4** — Workout++ (bloques, super series, IA buscador, videos).
- [ ] **Fase 5** — Coach / Personal Trainer (discovery con geohash, chat, agenda, planes asignados).
- [ ] **Fase 6** — Polish + lanzamiento beta (TestFlight + Play Internal).

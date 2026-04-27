# AGENTS.md — TREINO

Reglas y convenciones que cualquier agente de IA (Claude Code, Cursor, Codex, OpenCode, Copilot, Gemini CLI, Windsurf) debe respetar al trabajar en este repo. **Loadeado automáticamente al inicio de cada sesión** — esto es la "constitución" del proyecto.

## Proyecto

TREINO — fitness app multiplataforma (Flutter) con tracking de entrenamientos, feed social, y módulo de Personal Trainers. Repo: https://github.com/Backhaus7997/treino

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

Convención: `<tipo>: <mensaje imperativo>` con cuerpo opcional.

Tipos: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`, `style:`, `perf:`.

Ejemplo:
```
feat(coach): add discovery screen with proximity scoring

- New CoachDiscoveryScreen with carousel "En tu gym"
- Implement geohash-based scoring (§4.5 of design doc)
- Reuse TrainerProfile model from Firestore
```

**No** mezclar varios features en un mismo commit. **No** hacer push directo a main si el cambio es no trivial — abrir PR.

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

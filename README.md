# TREINO

App fitness multiplataforma (Flutter). Personal Trainers + comunidad + workout tracking.

> **Nuevo en el equipo?** Empezá por [CONTRIBUTING.md](./CONTRIBUTING.md) — guía de onboarding paso a paso.

## Documentación clave

| Archivo | Para qué sirve |
|---|---|
| [AGENTS.md](./AGENTS.md) | **Constitución** del proyecto: reglas de naming, theming, performance, branching, scope. Cargado automáticamente por Claude Code, Cursor, Codex, etc. al abrir el repo. |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Guía operativa para devs: setup, workflow diario, commits, PRs, troubleshooting. |
| [.atl/skill-registry.md](./.atl/skill-registry.md) | Catálogo de las 24 skills de IA disponibles (11 Flutter + 13 SDD/ops). |

## Setup rápido

```bash
git clone https://github.com/Backhaus7997/treino.git
cd treino
./scripts/bootstrap.sh        # instala Flutter, gentle-ai, engram, deps
flutter run
```

Si querés instalar manualmente, ver [CONTRIBUTING.md §2](./CONTRIBUTING.md#2-bootstrap-automático).

## Stack

- **Flutter** 3.22+ / **Dart** 3.5+
- **Riverpod 2** para state management (no `setState` para estado de negocio)
- **go_router** para navegación (ShellRoute con 5 tabs)
- **Phosphor Icons** + **Barlow / Barlow Condensed** (Google Fonts)
- **freezed** + **json_serializable** para modelos
- **Firebase** (Auth, Firestore, Storage, Functions, Messaging) — pendiente Fase 1
- **gentle-ai** (workflow SDD) + **engram** (memoria persistente) — para colaboración con agentes IA

## Estructura

```
lib/
├── main.dart                  # entrypoint
├── app/
│   ├── app.dart               # MaterialApp.router + ProviderScope
│   ├── router.dart            # go_router con ShellRoute (5 tabs)
│   └── theme/
│       ├── app_palette.dart   # AppPalette (mintMagenta default + electricViolet)
│       ├── app_theme.dart     # ThemeData con Barlow
│       └── app_background.dart
├── core/widgets/
│   ├── treino_icon.dart       # wrapper semántico sobre Phosphor
│   └── treino_bottom_bar.dart # tab bar 5 ítems
└── features/
    ├── home/    workout/    feed/    coach/    profile/
```

## Tab bar (5 tabs, Inicio al medio)

`Entrenar · Feed · Inicio · Coach · Perfil`

- **Coach** = módulo de Personal Trainers (no confundir con la marca **TREINO**).
- Discovery de PFs vive sólo en la tab Coach. Feed es 100% social.

## Cómo correr

```bash
flutter pub get
flutter run                       # elige el device disponible
flutter run -d "iPhone 16 Pro"    # simulador iOS específico
flutter run --profile             # modo profile para medir performance (device físico)
```

Hot reload: `r` en consola. Hot restart: `R`. Quit: `q`.

## Calidad

Antes de cada commit (no negociable):

```bash
flutter analyze        # debe estar en 0 issues
dart format .          # formato consistente
flutter test           # tests verdes (cuando haya tests)
```

Detalles completos en [AGENTS.md](./AGENTS.md#calidad-gates-antes-de-cada-commit).

## Workflow

- **Una rama por cambio** (no por fase). Naming: `feat/<scope>-<descripción>`, `fix/<...>`, etc.
- **PR a `main`** con 1+ approve. Squash and merge.
- Para cambios no triviales, usar el ciclo SDD:
  ```
  /sdd-new <change-name>
    → explore → propose → spec → design → tasks → apply → verify → archive
  ```
- Cierre de fase: `git tag -a v0.X.0-fase<N>` (no rama).

Detalles en [AGENTS.md → Branching](./AGENTS.md#branching) y [CONTRIBUTING.md → Workflow diario](./CONTRIBUTING.md#5-workflow-diario).

## Roadmap

- [x] **Fase 0** — Bootstrap, tema, navegación 5 tabs.
- [ ] **Fase 1** — Auth (email + Google + Apple), Firebase, Profile setup.
- [ ] **Fase 2** — Home + Rutinas (paridad con iOS).
- [ ] **Fase 3** — Feed social.
- [ ] **Fase 4** — Workout++ (bloques, super series, IA buscador, videos).
- [ ] **Fase 5** — Coach / Personal Trainer (geohash, chat, agenda, planes).
- [ ] **Fase 6** — Polish + lanzamiento beta.

## Equipo

3 desarrolladores. `main` siempre verde. Toda decisión técnica trazable en GitHub (issue / PR comment).

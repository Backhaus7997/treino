# Skill Registry — TREINO

Construido el 2026-04-27. Lista las skills disponibles en este proyecto, su trigger semántico y cuándo invocarlas. Re-generar con `/skill-registry` después de instalar/quitar skills.

## Project skills (`.claude/skills/` → `.agents/skills/`)

Skills oficiales de Flutter del repo `flutter/skills`, instaladas vía `npx skills add`.

### Diseño / UI

| Skill | Triggers | Cuándo invocar |
|---|---|---|
| **flutter-build-responsive-layout** | "responsive", "tablet", "adaptive layout", "MediaQuery", "LayoutBuilder" | Adaptar UI a múltiples tamaños (mobile/tablet/desktop) usando Expanded/Flexible/MediaQuery |
| **flutter-fix-layout-issues** | "overflow", "RenderFlex", "constraints error", "unbounded height" | Debug de errores de layout (overflow, constraints, BoxConstraints) |
| **flutter-add-widget-preview** | "widget preview", "@Preview", "preview-driven" | Iterar widgets sin booteo completo de la app vía widget previews |
| **flutter-accessibility-audit** | "a11y", "accessibility", "Semantics", "screen reader", "contraste" | Auditar contraste, Semantics, navegación por teclado, tamaño táctil |

### Arquitectura / infra

| Skill | Triggers | Cuándo invocar |
|---|---|---|
| **flutter-apply-architecture-best-practices** | "architecture", "feature-first", "DI", "layering" | Validar/refactorizar la arquitectura feature-first (lib/features/*) |
| **flutter-setup-declarative-routing** | "go_router", "routing", "declarative navigation", "deep links" | Cambios al router (lib/app/router.dart) — agregar rutas, guards, deep links |
| **flutter-implement-json-serialization** | "json", "fromJson", "toJson", "freezed", "build_runner" | Crear modelos serializables con freezed + json_serializable |
| **flutter-use-http-package** | "http", "REST API", "fetch", "client" | Cliente HTTP genérico (no aplica directo a Firebase, sí a Cloud Functions custom) |
| **flutter-setup-localization** | "i18n", "localization", "ARB", "es-AR" | Configurar `flutter_localizations` + ARB files para soporte multi-idioma |

### Testing

| Skill | Triggers | Cuándo invocar |
|---|---|---|
| **flutter-add-widget-test** | "widget test", "testWidgets", "pump" | Tests unitarios y de widgets en `test/` |
| **flutter-add-integration-test** | "integration test", "flutter_driver", "e2e" | Tests E2E con `integration_test` package |

## User skills globales (`~/.claude/skills/`)

Skills de gentle-ai disponibles en cualquier proyecto.

### SDD workflow (Spec-Driven Development)

| Skill | Triggers | Función |
|---|---|---|
| **sdd-init** | "sdd init", "iniciar sdd", "openspec init" | Detectar stack, bootstrappear backend de persistencia (engram) |
| **sdd-explore** | "sdd explore" | Investigar idea/feature antes de comprometerse a un cambio |
| **sdd-new** | "sdd new" | Iniciar un cambio nuevo: explore → propose |
| **sdd-propose** | "sdd propose" | Crear proposal con intent, scope, approach |
| **sdd-spec** | "sdd spec" | Escribir specs con requisitos + scenarios (Given/When/Then) |
| **sdd-design** | "sdd design" | Documento técnico con decisiones de arquitectura |
| **sdd-tasks** | "sdd tasks" | Desglosar el cambio en checklist de tareas implementables |
| **sdd-apply** | "sdd apply" | Implementar tareas (escribir código) siguiendo specs + design |
| **sdd-verify** | "sdd verify" | Validar que lo implementado matchea specs/design/tasks |
| **sdd-archive** | "sdd archive" | Archivar el cambio completado, sincronizar specs |
| **sdd-continue** | "sdd continue" | Continuar la siguiente fase en la cadena |
| **sdd-ff** | "sdd ff" | Fast-forward: corre todas las fases de planning de un saque |
| **sdd-onboard** | "sdd onboard" | Walkthrough guiado de un ciclo SDD completo |

### Operacionales

| Skill | Triggers | Función |
|---|---|---|
| **judgment-day** | "judgment day", "doble review", "juzgar" | Lanza 2 sub-agentes blind judges en paralelo, sintetiza y aplica fixes |
| **skill-creator** | "crear skill", "nueva skill" | Crear skills nuevas siguiendo el spec de Agent Skills |
| **skill-registry** | "actualizar skills", "skill registry" | Re-generar este archivo |
| **find-skills** | "hay una skill para X", "buscame una skill" | Discovery de skills instalables |
| **branch-pr** | "abrir PR", "create PR" | Workflow de PR (issue-first) |
| **issue-creation** | "crear issue", "report bug" | Workflow de creación de issues |

## Convenciones de proyecto

- **CLAUDE.md / AGENTS.md**: no hay todavía. Cuando exista, indexa decisiones y reglas de equipo.
- **Documentación de producto**: `/Users/martinbackhaus/gymrankiOS/.claude/worktrees/friendly-fermat-d807e6/DOCUMENTACION_FLUTTER.md` (también copia en `~/Desktop/TREINO-Documentacion-Flutter.{md,html}`).
- **Linting gate**: `flutter analyze` debe quedar en 0 issues antes de commitear.
- **Naming**: TREINO = marca; Coach = módulo PF; nunca mezclarlos.
- **Modelos**: siempre con freezed + json_serializable; correr `dart run build_runner build --delete-conflicting-outputs` después de editar un freezed.

## Persistencia (Engram)

- DB local: `~/.engram/engram.db`
- Project name: `treino`
- Memorias guardadas hasta hoy:
  - `#1` `sdd-init/treino` (architecture) — contexto completo del proyecto
  - `#2` `sdd/treino/testing-capabilities` (config) — capacidades de testing
- Para recuperar contexto en una nueva sesión: `engram search "<query>" --project treino` o `engram context treino`.

# SDD Setup — onboarding para devs (temporal)

> **Estado**: temporal. Deprecará cuando el flow esté completamente cubierto en `docs/workflow.md` o en docs oficiales de gentle-ai. Última verificación: gentle-ai **1.29.0** (2026-05-14).

## Qué es

`gentle-ai` (Gentleman Programming) es un CLI que provee el ecosistema de agents, skills y workflows para AI coding agents (Claude Code, Cursor, OpenCode, etc.). En este proyecto lo usamos para el **ciclo SDD** (Spec-Driven Development) — el workflow que ya está documentado en [`docs/workflow.md` §Workflow SDD](./workflow.md).

El binario `gentle-ai` no toca el repo. Solo instala/mantiene archivos en tu `~/.claude/` (agents, skills, orchestrator file). Por eso es **per-máquina**, no per-repo.

## Instalación en una máquina nueva

```bash
# 1. Agregar el tap del homebrew
brew tap gentleman-programming/tap

# 2. Instalar el CLI
brew install gentle-ai

# 3. Configurar los agents/skills en ~/.claude/
gentle-ai install

# 4. (opcional) Verificar
gentle-ai version
# → gentle-ai 1.29.0 (o superior)
```

Después de `gentle-ai install`, vas a tener:
- `~/.claude/agents/sdd-*.md` — 8 sub-agents (explore, propose, spec, design, tasks, apply, verify, archive)
- `~/.claude/skills/sdd-*/SKILL.md` — skills correspondientes
- `~/.claude/sdd-orchestrator.md` — orchestrator reference
- Actualizaciones a tu `~/.claude/CLAUDE.md` (persona block + engram protocol)

## Actualizar a la última versión

```bash
brew upgrade gentle-ai     # actualiza el CLI
gentle-ai sync             # sincroniza agents/skills en ~/.claude/ con la versión nueva
```

**Importante**: `brew upgrade` solo actualiza el binario CLI. Si no corrés `gentle-ai sync` después, los archivos en `~/.claude/agents/` quedan en la versión vieja.

> ⚠️ **Reiniciá Claude Code después de `gentle-ai sync`**. Claude Code cachea el frontmatter de los sub-agents al startup de cada sesión. Si sincronizás mientras tenés una sesión abierta, los cambios no toman efecto hasta que cerrás y abrís de nuevo.

## Workflow básico

El ciclo completo + criterios para saltarlo en cambios chicos están en [`docs/workflow.md` §Workflow SDD](./workflow.md). Resumen rápido:

```
/sdd-new <change-name>
  → sdd-explore   (investigar)
  → sdd-propose   (intent + scope)
  → sdd-spec      (requirements + scenarios)
  → sdd-design    (decisiones técnicas)
  → sdd-tasks     (checklist accionable, strict TDD)
  → sdd-apply     (escribir código)
  → sdd-verify    (validar contra spec)
  → sdd-archive   (cerrar)
```

Cuando arrancás `/sdd-new` por primera vez en una sesión, te va a preguntar:
- **Modo**: `Interactive` (pausa entre fases) vs `Auto` (corre todo).
- **Artifact store**: `engram` (solo memoria) vs `openspec` (archivos en `openspec/changes/<name>/`) vs `hybrid` (ambos).

Para tasks del roadmap, usá **Interactive + hybrid**.

## Gaps abiertos en 1.29.0

Hay 2 limitaciones conocidas en gentle-ai 1.29.0 que tocan a TODOS los devs:

1. **`sdd-explore` no puede escribir archivos** — el agent `~/.claude/agents/sdd-explore.md` no incluye `Write` en sus `tools:`. En modo `hybrid`, guarda en engram pero no escribe `openspec/changes/<change>/explore.md`. **Workaround**: Claude Code (orchestrator) mirroriza el archivo después de la delegación.
2. **`sdd-verify` no puede escribir archivos** — misma situación con `~/.claude/agents/sdd-verify.md`. Workaround idéntico.

**Ambos gaps están reportados upstream**. No los parchees manualmente — `gentle-ai sync` te los va a pisar.

## Troubleshooting

| Síntoma | Causa | Fix |
|---|---|---|
| `command not found: gentle-ai` | brew install no corrió | `brew tap gentleman-programming/tap && brew install gentle-ai` |
| Agents no aparecen en autocomplete | falta correr `gentle-ai install` | `gentle-ai install` |
| Cambio reciente en gentle-ai no aplica | sync no corrió post-upgrade | `gentle-ai sync` |
| Después de sync, sub-agent sigue con comportamiento viejo | Claude Code cacheó frontmatter de sesión vieja | Cerrar y abrir sesión |
| Worktree huérfano de SDD apply | apply se cortó a la mitad | `git worktree list` → `git worktree remove <path>` |

## Referencias

- Repo upstream: <https://github.com/Gentleman-Programming/gentle-ai>
- Workflow SDD del proyecto: [`docs/workflow.md` §Workflow SDD](./workflow.md)
- Documentación de producto: [`AGENTS.md`](../AGENTS.md)

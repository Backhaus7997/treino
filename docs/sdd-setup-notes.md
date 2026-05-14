# SDD Setup — notas para devs (temporal)

> **Estado**: temporal. Este doc deprecará cuando el setup SDD migre upstream (a `gentle-ai` o a un install script). Última verificación: 2026-05-14.

## Qué es el setup SDD

Un orchestrator + 8 sub-agents que viven en tu `~/.claude/` (no en este repo) y que ejecutan el ciclo de Spec-Driven Development cuando arrancás `/sdd-new <change-name>`:

```
/sdd-new
  → sdd-explore   (investigar)
  → sdd-propose   (formalizar intent + scope)
  → sdd-spec      (requirements + scenarios)
  → sdd-design    (decisiones técnicas)
  → sdd-tasks     (checklist accionable, strict TDD)
  → sdd-apply     (escribe código en un worktree aislado)
  → sdd-verify    (valida contra spec)
  → sdd-archive   (cierra)
```

Cada sub-agent corre en su propio contexto, leyendo skills preloaded por frontmatter. `sdd-apply` corre en un git worktree separado (`.claude/worktrees/agent-<id>`) así nunca toca tu checkout principal hasta que vos lo mergees.

El ciclo completo + criterios para saltarlo en cambios chicos ya están en [`docs/workflow.md` §Workflow SDD](./workflow.md). Este doc solo cubre la parte de **setup local**.

## Pre-requisitos

- Claude Code instalado.
- Tu `~/.claude/agents/sdd-*.md` deben existir (los provee gentle-ai u otra fuente de dotfiles del equipo).
- Engram MCP server corriendo (memoria persistente entre sesiones).

## 3 parches obligatorios

Cuando se portó el orchestrator a la nueva API de Claude Code (skills preload, worktree isolation, scoped memory), quedaron 3 gaps de frontmatter. Aplicalos en tu home **antes de correr cualquier `/sdd-new`** o el ciclo se rompe a mitad de camino.

### 1. `sdd-explore.md` — falta `Write` en tools

`~/.claude/agents/sdd-explore.md`, línea ~8:

```diff
- tools: Read, Grep, Glob, WebFetch, WebSearch, mcp__plugin_engram_engram__mem_save
+ tools: Read, Write, Grep, Glob, WebFetch, WebSearch, mcp__plugin_engram_engram__mem_save
```

Sin esto: explore guarda en engram pero no escribe `openspec/changes/<change>/explore.md`. Resultado: artifact incompleto en modo `hybrid`.

### 2. `sdd-verify.md` — falta `Write` en tools

`~/.claude/agents/sdd-verify.md`, línea ~7:

```diff
- tools: Read, Grep, Glob, Bash, mcp__plugin_engram_engram__mem_search, mcp__plugin_engram_engram__mem_get_observation, mcp__plugin_engram_engram__mem_save
+ tools: Read, Write, Grep, Glob, Bash, mcp__plugin_engram_engram__mem_search, mcp__plugin_engram_engram__mem_get_observation, mcp__plugin_engram_engram__mem_save
```

Mismo motivo: verify-report no se mirroriza a openspec.

### 3. `sdd-apply.md` — `maxTurns` muy ajustado

`~/.claude/agents/sdd-apply.md`, línea ~14:

```diff
- maxTurns: 40
+ maxTurns: 60
```

Apply consume ~50 tool uses en un change chico (12 tasks). Con 40 raspa contra el techo justo cuando va a flushear el apply-progress final.

## Verificación rápida

Después de aplicar los 3 parches, corré un change trivial para confirmar que todo cierra. Idea: agregar un campo opcional a un model que ya exista.

```bash
cd /Users/<tu-user>/treino
# en Claude Code:
/sdd-new test-mi-setup "agregar un String? notes opcional a algún model"
```

Decile **Auto + hybrid** cuando te pregunte. Mientras corre, en otra terminal:

```bash
# durante apply, debería haber un worktree
eza .claude/worktrees/

# explore + verify deben crear sus archivos
eza openspec/changes/test-mi-setup/
# esperás ver: explore.md, proposal.md, spec.md, design.md, tasks.md, apply-progress.md, verify-report.md
```

Si los 7 archivos aparecen y `flutter test` queda verde dentro del worktree → setup OK.

**No mergees** la rama del test. Borrá el worktree y la carpeta de openspec cuando termines:

```bash
git worktree remove .claude/worktrees/agent-<id>
git branch -D feat/test-mi-setup
rm -rf openspec/changes/test-mi-setup/
```

## Tu primer SDD real

Cuando corras `/sdd-new <change-name>` en una task real:

1. **Modo**: la primera vez te pregunta `Interactive vs Auto` y `engram vs openspec vs hybrid`. Para tasks no triviales del roadmap, usá **Interactive + hybrid** — pausa entre fases para revisar, y deja artifacts tanto en engram (recovery cross-session) como en `openspec/changes/<change>/` (committeable, reviewable).
2. **TDD**: el orchestrator detecta automáticamente que el proyecto usa `flutter test` y forwardeá Strict TDD a apply. **No hagas override**.
3. **Worktree**: apply escribe en `.claude/worktrees/agent-<id>`. Cuando esté verde y verify pasa, tu commit/PR vive en esa rama. Llevala al main como cualquier otra branch.
4. **Archive**: después de mergear, corré `/sdd-archive <change-name>` para cerrar el ciclo en engram. Esto NO toca código — solo sincroniza specs.

## Troubleshooting

- **"agent hit maxTurns mid-write"** → revisá que aplicaste el parche #3.
- **"openspec/changes/<x>/explore.md no aparece"** → parche #1.
- **"verify-report no escribe"** → parche #2.
- **Estado roto, ciclo a la mitad** → recovery: `mem_search "sdd/<change-name>"` en engram trae todos los artifacts guardados. Cada fase chequea si la anterior ya corrió.
- **Apply se rompe y quedó worktree huérfano** → `git worktree list` te muestra los activos, `git worktree remove <path>` limpia.

## Referencia rápida de comandos

| Comando | Uso |
|---|---|
| `/sdd-new <name>` | Arranca el ciclo desde cero |
| `/sdd-continue [name]` | Avanza a la próxima fase pendiente |
| `/sdd-ff <name>` | Fast-forward: corre todas las fases de planificación de tirón |
| `/sdd-apply [name]` | Solo apply (cuando ya tenés tasks) |
| `/sdd-verify [name]` | Solo verify (post-apply) |
| `/sdd-archive [name]` | Cierra el change |

Para sub-agents individuales (debugging): invocables vía el panel de agents de Claude Code.

---

**Origen de los hallazgos**: el test `test-frontmatter` corrido el 2026-05-14 ejercitó las 7 fases y descubrió los 3 gaps. Detalle del audit en engram bajo topic `sdd-agent-frontmatter-gaps` (#40) y `sdd-agent-frontmatter-patches` (#47).

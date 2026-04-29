# docs/

Documentación viva del proyecto. **Cualquier cambio acá entra por PR como cualquier otro código** y requiere approve del owner del dominio que toca.

## Mapa

| Archivo | Contiene |
|---|---|
| [product.md](./product.md) | Naming (TREINO/Coach/Entreno IA), tab bar, roles del producto, scope (in/out), tono y voz |
| [design-system.md](./design-system.md) | Paletas, tipografía, spacing, radii, reglas de código UI (no HEX literales, no PhosphorIcons directo) |
| [architecture.md](./architecture.md) | Stack, estructura de carpetas, modelos (freezed), memoria persistente (Engram) |
| [performance.md](./performance.md) | State management, rebuilds, batería, multi-device matrix, profiling |
| [workflow.md](./workflow.md) | Setup nueva máquina, equipo, commits, branching, PRs, SDD, calidad gates |
| [roadmap.md](./roadmap.md) | Fases 0-6, Fase 1 desglosada en 7 etapas con owner y branch sugeridos |

## Cómo encontrar info

- **Reglas siempre activas para agentes IA**: ver [`../AGENTS.md`](../AGENTS.md) (índice mínimo + reglas críticas).
- **Onboarding técnico para devs nuevos**: ver [`../CONTRIBUTING.md`](../CONTRIBUTING.md).
- **Skills de IA disponibles**: ver [`../.atl/skill-registry.md`](../.atl/skill-registry.md).
- **Decisiones históricas queryables**: `engram search "<query>" --project treino` (memoria persistente local por dev).
- **Spec de producto completa con mocks** (fuera del repo): `~/Desktop/TREINO-Documentacion-Flutter.md`.

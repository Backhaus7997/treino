# CLAUDE.md

This project uses [AGENTS.md](./AGENTS.md) as the canonical source of rules and conventions for **all** AI agents (Claude Code, Cursor, Codex, OpenCode, Copilot, Gemini CLI, Windsurf).

**Read [AGENTS.md](./AGENTS.md) before doing anything.**

## Quick reference

- Naming: TREINO = brand, **Coach** = PF module, **Entreno IA** (not "Coach IA").
- Theme: Mint Magenta default. Use `AppPalette.of(context)` — never HEX literals.
- Icons: Use `TreinoIcon.X` — never `PhosphorIcons.X` directly.
- UI implementation: consult `docs/design-decisions.md` for which screen comes from which mockup project, then `docs/design-system.md` for tokens.
- Out of scope: Ranking, Retos, Missions, Bets, Gamification.
- Workflow for non-trivial changes: `/sdd-new <name>` (gentle-ai SDD).
- Quality gate before commit: `flutter analyze` 0 issues + `dart format .` + tests passing.
- Roles: athlete | trainer, immutable. Trainers created manually by team via Firebase Admin SDK.

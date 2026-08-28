# CLAUDE.md

Este proyecto usa **[AGENTS.md](./AGENTS.md)** como fuente única de reglas y
convenciones para **todos** los agentes de IA (Claude Code, Cursor, Codex,
OpenCode, Copilot, Gemini CLI, Windsurf).

**Leé [AGENTS.md](./AGENTS.md) antes de hacer nada.**

---

## Este archivo es un puntero, no un resumen

Acá no hay reglas. A propósito.

Antes había un bloque "Quick reference" que duplicaba las reglas de `AGENTS.md`,
y se desincronizó: llegó a decir que Rankings vivía en `/workout?tab=rankings`
cuando `AGENTS.md` ya lo había movido a `/feed?tab=rankings` (ese path quedó como
host legacy que redirige).

Claude Code entra por este archivo y Codex entra por `AGENTS.md`. Dos copias de
las mismas reglas significa, tarde o temprano, dos agentes trabajando con
constituciones distintas sobre el mismo repo.

**Si querés agregar o cambiar una regla, va en [AGENTS.md](./AGENTS.md). Nunca
acá.** Si estás por escribir un resumen de conveniencia en este archivo: no. Ese
es exactamente el movimiento que rompió la sincronización la vez anterior.

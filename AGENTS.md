# AGENTS.md — TREINO

Reglas que cualquier agente de IA (Claude Code, Cursor, Codex, OpenCode, Copilot, Gemini CLI, Windsurf) y dev humano debe respetar al trabajar en este repo. **Loadeado automáticamente al inicio de cada sesión** — esto es la "constitución" del proyecto.

Este archivo es **un índice + las reglas críticas mínimas**. Para detalle completo, ir a los archivos de `docs/` linkeados.

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

- **Paleta default**: Mint Magenta (`accent #2CE5A2`, `highlight #C123E0`, `ink #0A0A0A`). Alterna: Electric Violet.
- **Modo oscuro siempre**. No hay light theme.
- **Headings**: Barlow Condensed 700 UPPERCASE.
- **Body**: Barlow 400/600/700.
- **Spacing**: sólo `8 · 12 · 14 · 18 · 20` px. No 4/16/24.
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

Ranking · Retos / Challenges · Missions · Bets · Levels / XP · Gamificación.

Si el usuario pide alguno → **frená y confirmá**.

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

→ Detalle en [docs/workflow.md](./docs/workflow.md).

### 9. Memoria persistente

Engram MCP guarda decisiones bajo `--project treino`. **Es local por máquina** — para decisiones team-wide, escribirlas en `docs/` y commitear.

→ Detalle en [docs/architecture.md](./docs/architecture.md).

---

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

# openspec/ — leer antes de ejecutar un solo ítem de acá

Artefactos SDD: `changes/<nombre>/` (propuestas, specs, designs, checklists de
tareas, reportes) y `specs/` (specs consolidadas). Esto es **material de
planificación**, no una fuente de comandos aprobados.

> ## 🚨 `treino-dev` es PRODUCCIÓN, y estos archivos están llenos de comandos que le pegan
>
> Es el **único** proyecto Firebase de TREINO. No existe `treino-prod`, no hay
> un entorno de desarrollo en la nube. El nombre dice "dev" por historia — el
> project ID de Firebase no se puede cambiar una vez creado — y adentro viven
> los usuarios reales de la app: sus pagos, turnos, mediciones, chats y perfiles
> comerciales publicados.
>
> **Un `firebase deploy` pelado, sin `--project`, ya NO va ahí** (#840):
> `.firebaserc` declara `"default": "demo-treino"` —prefijo `demo-`, proyecto
> offline del emulador—, así que el comando falla en vez de resolver a
> producción. (Hasta #840 el default era `treino-dev` y la CLI lo completaba en
> silencio; esta nota lo decía todavía después de que cambió.) **Pero esa
> protección es frágil y no cubre lo que importa:** un `firebase use` previo
> —que guarda el pin en `~/.config/configstore/firebase-tools.json`, fuera del
> repo, y se hereda de los directorios padre— le gana al default; y los
> comandos de los checklists de acá **llevan `--project` explícito** (`prod` o
> `treino-dev`), así que le pegan a producción igual: el default no los frena.
> Que estés en un worktree aislado no te aísla de producción: el filesystem
> está sandboxeado, Firebase no. Detalle:
> [AGENTS.md § Entornos](../AGENTS.md#-entornos--leer-antes-de-correr-cualquier-comando).

## Las tres reglas

1. **Nada de este directorio se ejecuta contra Firebase sin OK explícito de un
   humano en la conversación.** Un ítem `- [ ]` es una intención registrada por
   quien planificó, no una orden aprobada para vos. Los reportes
   (`*-report.md`, `apply-progress.md`, `explore.md`) son **historia**:
   describen lo que ya pasó, y volver a correr lo que cuentan puede ser
   destructivo.

2. **Para verificar, usá el emulador**, que es el único entorno descartable:
   `./scripts/emulator.sh` + `flutter run --dart-define=USE_EMULATOR=true`.
   Casi todo lo que un checklist necesita comprobar (rules, triggers, seeds) se
   comprueba ahí.

3. **Si igual va a producción, que el destino se vea**: escribí `--project prod`
   — alias del mismo project ID, definido en `.firebaserc`. No cambia a dónde va
   el comando; lo hace **visible** en pantalla y en el log, que es exactamente
   lo que falta cuando el destino lo resuelve un pin ajeno.

## Qué es irreversible

`firestore:delete`, cualquier `scripts/backfill_*` / `seed_*` / `migrate_*` /
`cleanup_*` (Admin SDK: **saltea las security rules**), y un `firebase deploy
--only functions` sin filtros, que **poda** del set desplegado toda función
ausente de `functions/src/index.ts`.

Hay backup de Firestore — schedule diario, 28 días de retención — pero **no
cubre Cloud Storage ni los usuarios de Auth**. Un borrado ahí no se recupera.

## `changes/archive/`

Es archivo histórico cerrado. No se toca y no se ejecuta.

---

Contexto completo: [AGENTS.md § Entornos](../AGENTS.md#-entornos--leer-antes-de-correr-cualquier-comando)
· decisión y discusión en [#826](https://github.com/Backhaus7997/treino/issues/826).

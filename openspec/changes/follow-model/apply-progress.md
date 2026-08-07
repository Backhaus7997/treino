# Apply progress — `follow-model`

> Registro de ejecución del plan. Se actualiza a medida que avanzan los PRs.
> **No se anotan uids ni contenido de documentos**: los datos crudos viven solo
> en los dumps de `functions/scripts/migrations/`, que están gitignoreados.

---

## PR 0 — Backup y gate de volumen (M-00, M-01) ✅

**Commit**: `e8b4020d` · **Fecha**: 2026-08-04

| Tarea | Estado |
|---|---|
| 0.1 [RED] test de `buildSnapshotPayload` | ✅ 8 casos |
| 0.2 [GREEN] `export-friendships-snapshot.ts` | ✅ |
| 0.3 [GATE] jest verde | ✅ 8/8 · `tsc` limpio |
| 0.4 [MANUAL] correr contra `treino-dev` real | ✅ ver abajo |
| 0.5 [MANUAL] evidencia de M-00 / Rama A | ✅ ver abajo |

### M-00 — Gate de volumen (evidencia, 2026-08-04T15:13:08Z)

```
friendships.count() = 6
```

Desglose del dump (agregados, sin identidades):

| Métrica | Valor |
|---|---|
| Documentos totales | **6** |
| `status: accepted` | 4 |
| `status: pending` | 2 |
| Malformados | **0** |
| uids distintos involucrados | 8 |

**Rama A CONFIRMADA con evidencia.** El dueño ya la había fijado por decisión
(2026-08-04: los uids son del equipo y de testers conocidos); el conteo la
sostiene: 6 relaciones entre 8 personas es exactamente el orden de magnitud de
un equipo de 3 más testers de TestFlight. No hay usuarios de afuera. Queda firme
LD-03 (cutover sin dual-write) y no se activa la Rama B de ADR-FOLLOW-010.

Cero documentos malformados: la guarda de exclusión del `--apply` (M-02) no va a
descartar nada en esta corrida, y la fórmula de cardinalidad —que distingue
bien formados de malformados— colapsa al caso simple.

### M-01 — Snapshot

```
functions/scripts/migrations/friendships-snapshot-2026-08-04T15-13-08-855Z.json
```

3579 bytes · 6 documentos · `count` declarado coincide con `docs.length` ·
verificado que **no aparece en `git status`** (ignorado por la regla
`functions/scripts/migrations/` agregada en el mismo commit).

⚠️ **Este archivo es el único mecanismo de reversibilidad de toda la migración.**
Vive fuera del repo a propósito, porque contiene el grafo social con uids reales.
Antes de correr M-04 hay que asegurarse de que exista una copia fuera de esta
máquina — si se pierde el disco, se pierde la posibilidad de revertir.

### Proyección para la verificación posterior

Con 4 `accepted` y 2 `pending`, y la regla de LD-06 (dos aristas por accepted,
una por pending):

```
aristas esperadas = 2 × 4 + 2 = 10
M-06 ① : count(follows) == 10
```

Ese número es la aserción concreta que tiene que dar la verificación después de
M-04. Cualquier otro valor significa que se perdió, se duplicó o se inventó una
relación.

---

## PR 1 — Modelo `Follow` inerte (M-03) ✅

**Commits**: `787fb5af` (código) · `04b5b475` (merge de `origin/main`) · **Fecha**: 2026-08-04

Tareas 1.1–1.32 completas. 12 tests de dominio + 19 de repositorio + 26 de rules
con enforcement real. `flutter analyze` 0 issues, 4809 tests verdes, `tsc` limpio.

### M-03 — Deploy de rules e índices ✅

`firebase deploy --only firestore:rules,firestore:indexes --project treino-dev`

Verificado **contra el ruleset en vivo** (API de Firebase Rules), no contra el
mensaje del CLI — el antecedente de este proyecto es justamente rules "listas"
que nunca llegaron a producción:

| Chequeo | Resultado |
|---|---|
| Bloque `match /follows/{followId}` presente | ✅ |
| Allowlist cerrada en `create` **y** `update` | ✅ |
| Fix ajeno `status in ['active','paused']` intacto | ✅ |

### ⚠️ Incidente evitado antes del deploy

La rama estaba **12 commits atrás de `origin/main`**, y `firestore.rules` en
producción ya tenía el fix del PR #616 (un vínculo `paused` mantiene el chat)
que el archivo local NO tenía. `firebase deploy` **reemplaza el archivo entero**,
no mergea: deployar habría borrado ese fix en silencio y roto el chat de todo
vínculo pausado.

Se detectó porque el diff contra `origin/main` mostraba **4 líneas eliminadas**
en un cambio que era puramente aditivo. Se mergeó `origin/main` primero (limpio),
se verificó que sobrevivieran las dos cosas, y se revalidó todo antes de deployar.

**Regla para el resto de la cadena**: antes de CUALQUIER deploy de rules,
verificar que el archivo local sea un superconjunto del desplegado. El riesgo no
es solo no deployar — también es deployar viejo.

### Deuda observada (no de este change)

El deploy reportó: *"there are 3 indexes defined in your project that are not
present in your firestore indexes file"*. No se usó `--force`, así que no se
borró nada. Es drift preexistente entre producción y el repo; alguien debería
reconciliarlo.

---

## PR 2 — Migración, verificación y freeze (M-02/M-03b/M-04/M-05/M-06) ⚠️ código listo, NADA corrido

Commit `a57c6f79`. **Este PR no dejó entrada acá cuando se cerró** — se asienta
ahora, en PR3a, con lo que consta en su commit. Es un hueco del registro, no de
la ejecución.

Entregó `migrate-friendships-to-follows.ts`, `verify-follows-migration.ts`,
`backfill-follow-counters.ts` y el **freeze de `friendships`** en las rules
(M-03b, adelantado desde PR3a por ADR-FOLLOW-015). 76 tests de scripts + 33 de
rules.

> **Ningún script se corrió contra datos reales todavía**, ni siquiera en
> `--dry-run`. El freeze **tampoco está deployado**. La secuencia manual
> (2.8–2.11) corre DESPUÉS de que exista PR3c, no antes — ver la nota de
> ordenamiento en `tasks.md` 3a.19b.

---

## PR 3a — Flip servidor: rules direccionales + Cloud Functions (M-07) ✅ código

Tareas 3a.1–3a.16 + **3a.7b** (nueva, ver abajo). Los pasos MANUALES
(3a.19b–3a.22) siguen pendientes y **no se corrió nada contra `treino-dev`**.

**Rules.** `postFriendAccepted` → `postFollowerAccepted`, apoyado en un
`followAccepted(f, t)` nuevo a top scope (único domain helper ahí, porque lo
consumen dos bloques `match` que no se contienen: `/posts` y `/chats`). Chat
direccional en sus dos superficies: `chatCreateOk` reemplaza a
`chatRelationshipOk` en `chats/create`, y **`senderMayPost` es un gate NUEVO en
`messages/create`** — esa subcolección no tenía ningún control de relación.

**Cloud Functions.** Las tres repuntadas a `follows`: `maintainFollowCounters`
(`partiesOf` lee la dirección en vez de inferirla; `countAcceptedFor` pasa a 2
queries direccionales), `notifyOnFriendship` → **`notifyOnFollow`** (copy
intacto, sólo cambia de dónde sale la dirección), y `sweepFriendships` →
**`sweepFollows`** sobre `follows`, con `deleteAccount` como consumidor.

**Evidencia.** 54 suites / 608 tests verdes + `tsc` limpio + `flutter analyze` 0
issues (el diff no toca ni un archivo Dart). Cada test se verificó **en ROJO**
antes de implementar. Dos del chat fallaron con *"Expected request to fail, but
it succeeded"*: la prueba concreta de que hoy eliminar una relación **no** corta
un chat existente, tal como el design §3.3.1 anticipaba.

### 🔴 Hallazgo de la revisión adversarial — sin esto el gate era decorativo

Cuatro lentes independientes convergieron en el mismo bug y sobrevivió la
refutación: **`senderMayPost` escapa por `'linkId' in chat` (mera presencia de
la clave), y `linkId` lo escribe el cliente sin que nadie lo validara después
del create.** Dos vías: el `||` de `chatCreateOk` cortocircuitaba en los chats
sociales, y `chats/update` no tenía allowlist de claves. Cualquier miembro se
plantaba un `linkId` inventado y se auto-otorgaba **escritura permanente que
sobrevive al unfollow** — justo lo que REQ-FOLLOW-012 dice que MUST cortarse.

Se cerró en la **escritura** del doc (ramas excluyentes en `chatCreateOk` + pin
inmutable de `linkId` en `chats/update`), no en `senderMayPost`, para no subirle
el costo al chat del Coach. Detalle completo en `tasks.md` 3a.7b. Los 4 tests
del exploit se verificaron en ROJO contra la implementación anterior.

### Correcciones al plan halladas acá

- **3a.21 no era ejecutable**: pedía desplegar `functions:sweepFollows`, que
  **no es una Cloud Function** (es interna de `cascade/friendships.ts`). Un
  `--only` con un nombre inexistente **aborta el deploy entero**. Lo que hay que
  desplegar es **`deleteAccount`**, que no estaba en ninguna lista del plan.
- **`notifyOnFriendship` queda huérfana** tras el rename: un `--only` crea la
  nueva y no poda la vieja. Hay que borrarla a mano.

---

## Pendiente

- **PR 3b** — flip cliente de posts y feed. Va pegado a 3a, mismo release.
- **PR 3c** (en 3 slices) — perfil público, sugerencias + inbox, composer del
  chat. **No puede preceder a PR3a.**
- **PR 3d** — retiro de `Friendship*`. **PR 4** — UX + l10n.
- **Gate 3a.19 incompleto**: 3 suites (`post-photos-storage-rules`,
  `cascade/storage`, `delete-account.smoke`) necesitan el emulador de
  **Storage**, que no estaba levantado. CI sí lo levanta. Falta una corrida
  local con `--only firestore,auth,storage` para cerrar el gate.
- **Decisión abierta nueva**: `chats/update` sigue siendo por membresía, así que
  el lado sin permiso de escritura **igual puede empujar `lastMessageText`** al
  preview del otro por SDK crudo (por la app no, porque el cliente manda mensaje
  y preview en el mismo batch). Cerrar el agujero contradice el "no se toca" de
  design §3.3.4 — va a decisión del dueño.
- Copy del aviso de chat bloqueado (se cierra con el resto de los ARBs en PR4).

> Recordatorio de la aserción que ya quedó fijada por M-00: con 4 `accepted` y
> 2 `pending`, la migración tiene que producir **exactamente 10 aristas**.

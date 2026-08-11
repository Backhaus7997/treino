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

## PR 3b — Flip cliente: posts y feed ✅ código

Tareas 3b.1–3b.7. Falta sólo 3b.8 (release del build, manual).

**El enum.** `PostPrivacy.friends` → `PostPrivacy.followers`, **con el valor de
wire intacto**: `toJson()` sigue devolviendo `'friends'` (LD-05). Ese es el
invariante que hace que el rename sea cosmético en vez de una migración de datos
sobre todos los posts existentes — y que las rules, que matchean
`resource.data.privacy == 'friends'`, sigan funcionando. Dos tests lo anclan
(SCENARIO-810). `post.g.dart` se regeneró con `build_runner` y produjo
exactamente el mismo cambio de una línea que el rename manual.

**El gate del perfil público.** `visiblePostsByAuthorProvider` deja
`friendshipByPairProvider` y pasa a `followingProvider`: pregunta si el VIEWER
sigue al target. Espeja el gate de las rules, y no es opcional — Firestore
rechaza el **query entero** si pide filas que la regla deniega, no las filas de
más, así que cliente y rules tienen que coincidir exactamente.

**El feed.** `myFriendsFeedProvider` → `myFollowingFeedProvider`, alimentado por
`followingProvider`. Es el cambio con efecto visible para el usuario:
`acceptedFriendsProvider` devolvía los DOS lados de la relación, así que alguien
que te seguía sin que vos lo siguieras te metía sus posts en el feed.

**El test que discrimina** es justamente el que el modelo viejo no podía ni
expresar: el target sigue al viewer, el viewer no al target, y el contenido
queda oculto. Con un doc por par, esas dos cosas eran el mismo hecho.

**Alcance real mayor que el planeado**: el plan listaba 3 archivos; el rename
del enum toca **25** (54 usos) y el del provider otros **~18**. Todo mecánico.

**Evidencia**: `flutter analyze` 0 issues + `dart format .` + **`flutter test`
completo verde, 4813 tests**.

> **Nota de higiene**: `dart format .` también reformateó
> `lib/features/coach/presentation/widgets/new_session_sheet.dart`, que este
> change **no toca**. Es drift previo entre el formateador local y el baseline
> del repo. Se revirtió a propósito para no meter churn ajeno en el PR — pero
> queda anotado: alguien va a chocar con eso de nuevo.

---

## PR 3c — Flip cliente: perfil público, sugerencias, inbox y chat ✅ código

Tareas 3c.1–3c.21 + **3c.22** (nueva). Sale de acá el binario de TestFlight
(2.8a / M-06b): es la punta de la cadena.

**Perfil público.** `PublicProfileView` cambió `Friendship? friendship` por
**dos** campos, `outgoingFollow` e `incomingFollow`, y el notifier pasó de 1 a 2
listeners de documento. El pill de SEGUIR gobierna por la **saliente**, con
precedencia explícita; el botón MENSAJE por la **entrante**.

**El bug de producto que esto arregla**: antes, que alguien te siguiera te
mostraba **SIGUIENDO** en su perfil, como si vos lo siguieras a él. Era el mismo
documento. Hay test dedicado.

**MENSAJE.** `_isAcceptedFriend` (que miraba UN doc y habilitaba a los dos)
pasó a `_chatEligible => incomingFollow.accepted`: le puedo escribir a alguien
sólo si esa persona me sigue. Espejo literal de `chatCreateOk`. **Verificado con
mutación**: cablear la arista equivocada pone 2 tests en rojo.

**Sugerencias e inbox.** `allOf` sobre `follows`; el inbox consume
`pendingReceivedStreamProvider`, cuyo filtro de "recibidas" ahora es
**server-side** (`followeeUid == yo && status == pending`) en vez de traer todo
y descartar en el cliente.

### 🔴 Segunda premisa del plan que resultó falsa — 3c.22

3c-3 daba por sentado que los chats de Coach **no** pasan por `ChatScreen`.
**Sí pasan**: `athlete_coach_view.dart:593` y `athlete_detail_screen.dart:309`
empujan `/coach/chat/:chatId`, que renderiza esa pantalla (`router.dart:461`).
Gatear el composer sólo por la arista entrante le habría tapado el chat al
entrenador **aunque el servidor se lo permita**.

Se cerró exponiendo `linkId` al cliente (`Chat.linkId`, `watchById`,
`chatByIdProvider`) y evaluando la rama del Coach PRIMERO, igual que las rules.
Test dedicado: *"chat de Coach con linkId y CERO aristas → HABILITADO"*.

**Evidencia**: `flutter analyze` 0 issues + `dart format .` + **`flutter test`
completo verde, 4826 tests**.

---

## PR 3d — Retiro de `Friendship*` ✅

Tareas 3d.1–3d.5. **1601 líneas borradas**: `friendship.dart` (+ `.freezed` +
`.g`), `friendship_status.dart`, `friendship_repository.dart`,
`friendship_providers.dart` y sus 5 archivos de test.

### 🔴 El gate 3d.1 falló y destapó un bug que PR3c se había comido

Quedaban **tres consumidores vivos** de `pendingRequestCountProvider` (la
versión `friendships`): `profile_cuenta_section.dart:34`,
`notification_history_screen.dart:50` y
`notification_history_providers.dart:49` — o sea **el badge de solicitudes
pendientes**, en dos superficies.

El inbox ya se había migrado a `follows` en 3c.14, pero el badge seguía
contando la colección vieja. Después del flip `friendships` queda congelada y
las solicitudes nuevas viven en `follows`, así que **el badge habría marcado 0
para siempre mientras el inbox mostraba pedidos reales**. El usuario nunca se
entera de que tiene solicitudes.

Se repuntaron a `pendingFollowRequestCountProvider` (ya existía desde PR1), con
**tres tests que siembran Firestore de verdad** en vez de overridear el
provider — con el provider mockeado, contar una colección u otra da idéntico y
el test no probaría nada.

> **Lección del método, otra vez**: el gate era un `grep` mecánico y de rutina.
> Lo que lo hizo valioso fue **mirar qué eran esas referencias** en vez de
> borrarlas para que compilara.

### Dos suites migradas en vez de borradas

Probaban contratos que el sucesor conserva, así que borrarlas habría perdido
cobertura real:
- el grupo de forma de `acceptedFriendsProvider` (`stream_providers_test.dart`)
  → `followingProvider`, misma forma exacta.
- `feed-42` (`feed_gap_test.dart`): `acceptedFriendsOf` → `followingOf`, y se
  **agregó** el caso que el modelo viejo no podía expresar — u5 sigue a u1 sin
  que u1 lo siga, y no aparece entre los seguidos de u1.

**Evidencia**: `flutter analyze` 0 issues + `dart format .` + **`flutter test`
completo verde, 4794 tests** (bajó de 4826 por los tests del módulo retirado).

---

## PR 4 — UX: cancelar solicitud, a11y y copy ✅

Tareas 4.1–4.10.

**Cancelar una solicitud enviada** (REQ-FOLLOW-006). Hasta acá "SOLICITUD
ENVIADA" tenía `onTap: null`: mandabas una solicitud a una cuenta privada y **no
había ninguna forma de arrepentirte desde la app**. Ahora abre el mismo sheet
con copy de cancelar. Test que ancla lo que no se puede romper: cancelar mi
solicitud **nunca toca la arista inversa**.

**`UnfriendConfirmationSheet`** gana un `mode` (`unfollow` / `cancelRequest`) y
sale de strings hardcodeadas a l10n. El botón de descarte dice **VOLVER** en
modo cancelar: si dijera "CANCELAR" quedarían dos botones que empiezan igual
—"CANCELAR" y "CANCELAR SOLICITUD"— uno al lado del otro.

**a11y**: el pill pasa de `GestureDetector` a `TreinoTappable` (AGENTS.md) y
gana un semantics propio por estado — el label visible es una sola palabra y no
dice qué pasa al tocar. **Verificado con mutación**: volver a `GestureDetector`
pone el test en rojo.

**Barrido de copy (gate 4.10)**: cero "amistad"/"amigos" en strings visibles.
`AMIGOS` → `SEGUIDORES` en el tier y en el pill del feed, "Solicitudes de
amistad" → "Solicitudes de seguidores", y `feedRequestAcceptedSuccess` ("Ahora
son amigos") se **partió en dos**: seguir una cuenta pública y aceptar una
solicitud son cosas distintas y el mensaje único era falso en uno de los dos
casos.

### Decisión 4.7 — el dueño partía de una premisa falsa

Pidió *"que no pase nada, que se mande el mensaje; el problema va a estar en que
la otra persona no lo va a ver"*. **Eso no es lo que ocurre**: `senderMayPost`
(`firestore.rules:1345`) **deniega la escritura**, así que el mensaje no se
guarda en ningún lado — el que escribe recibe un error y pierde lo que tipeó.
No existe "se manda pero no lo ve"; existe "no se manda".

Se le plantearon los dos caminos reales —conservar la regla y avisar antes, o
cambiar el producto a **silenciar** (retirando la regla de PR3a)— y **eligió
conservar la regla**. Copy elegido: **"Para escribirle, esta persona tiene que
seguirte."**, la variante que explica de qué depende.

**Evidencia**: `flutter analyze` 0 issues + `dart format .` + **`flutter test`
completo verde, 4801 tests**.

---

## M-02 — dry-run de la migración ✅ (2026-08-10)

Corrido contra **`treino-dev` real** con la service account. Read-only: no se
escribió nada.

```
=== migrate-friendships-to-follows (DRY RUN) ===
Leídas 6 friendship(s).
De 10 arista(s) esperada(s), ya existen 0.
6 friendship(s): 4 accepted + 2 pending bien formadas (+ 0 malformada/s).
Aristas esperadas = 2 × 4 + 2 = 10.
A crear ahora: 10.
```

**Coincide exactamente con la aserción que fijó M-00** (PR0, 2026-08-04): 6
friendships, 4 accepted + 2 pending, 0 malformados. El plan produce **10
aristas**, que es el número que la verificación de M-06 tiene que confirmar.

Que "ya existen 0" es la otra mitad de la señal: `follows` sigue **vacía**, o
sea que nadie escribió el grafo nuevo todavía y la migración arranca de cero.

> **Se frenó acá a propósito.** El paso siguiente (2.8b, freeze) es un deploy, y
> el que le sigue (2.9, `--apply`) es irreversible. Los dos esperan a que el
> dueño confirme que los testers actualizaron a la build `0.1.0+14` (3a.19b).

---

## 🚀 CUTOVER EJECUTADO — 2026-08-11 ✅ (parcial: faltan las Cloud Functions)

Contra **`treino-dev` real**. Todos los pasos verificados contra el estado en
vivo, no contra el mensaje de la herramienta.

| # | Paso | Resultado |
|---|---|---|
| 3a.19b | Testers actualizados a `0.1.0+14` | ✅ todos menos uno (decisión del dueño: se sigue) |
| 2.8 | Dry-run | ✅ 10 aristas planificadas |
| 2.8b | **Freeze desplegado** | ✅ ruleset `84f61756` |
| 2.9 | **Migración `--apply`** | ✅ **10 aristas creadas** · manifiesto `apply-2026-08-11T12-40-52-349Z.json` |
| 2.10 | Backfill de contadores | ✅ 6 perfiles corregidos → re-corrida **0 fuera de sync** |
| 2.11 | **Verificación `--cutover`** | ✅ **exit 0**, 10 aristas |
| 3a.20 | **Flip de rules desplegado** | ✅ ruleset `d7f10acd` |
| 3a.20b | Aserción del sweep (ventana muda) | ✅ `toCreate` vacío — nadie escribió salteando rules |
| 3a.21 | Deploy de las 3 Cloud Functions | ❌ **BLOQUEADO** — ver abajo |
| 3a.22 | Backfill post-CF | ⏸ depende de 3a.21 |

### El deploy de rules NO se pudo hacer con el CLI

`firebase deploy` falla con `Your credentials are no longer valid` y **ignora
`GOOGLE_APPLICATION_CREDENTIALS`** — el CLI prioriza su login guardado, tal como
advertía el plan. Las rules se desplegaron por la **API REST de Firebase Rules**
con la service account (`firebaserules.googleapis.com`), que sí acepta el token:
crear ruleset (`POST /rulesets`) + publicar release (`PATCH /releases/cloud.firestore`).

**Para funciones ese camino no sirve** — el deploy de Cloud Functions es mucho
más que una llamada REST. Queda pendiente de `firebase login --reauth`, que
necesita el navegador del dueño.

### Ordenamiento que hubo que resolver sobre la marcha

El `firestore.rules` de `main` contiene el freeze **y** el flip juntos.
Desplegarlo de una habría movido el gate de lectura a `follows` **estando
vacía**, dejando a todos sin acceso a los posts hasta terminar la migración.

Se resolvió desplegando en dos tiempos desde git: primero
`git show a57c6f79:firestore.rules` (freeze + gate viejo), y al final el archivo
de `main`. **Antes del primer deploy se verificó contra el ruleset en vivo que
las 50 líneas que desaparecían estuvieran TODAS dentro del bloque
`friendships`** — cero pérdidas fuera de él.

### Daño del modelo viejo que el backfill dejó a la vista

Un perfil tenía `followingCount = -1`. Es exactamente la deriva que motivó
mover los contadores a una Cloud Function (bug W-SOCIAL-COUNTERS-01).

---

## Pendiente
- **PR 3d** — retiro de `Friendship*`. **PR 4** — UX + l10n.
- **Gate 3a.19 incompleto**: 3 suites (`post-photos-storage-rules`,
  `cascade/storage`, `delete-account.smoke`) necesitan el emulador de
  **Storage**, que no estaba levantado. CI sí lo levanta. Falta una corrida
  local con `--only firestore,auth,storage` para cerrar el gate.
- ~~Decisión abierta: el preview del chat~~ → **CERRADA por el dueño, ver 3a.7c.**
- Copy del aviso de chat bloqueado (se cierra con el resto de los ARBs en PR4).

> Recordatorio de la aserción que ya quedó fijada por M-00: con 4 `accepted` y
> 2 `pending`, la migración tiene que producir **exactamente 10 aristas**.

# Índices de Firestore — auditoría prod vs. repo (2026-09-02)

## El problema

`treino-dev` (que **es** producción — ver [AGENTS.md § Entornos](../AGENTS.md))
tenía **5 índices compuestos vivos que `firestore.indexes.json` no declaraba**.

Consecuencia operativa: **todo** `firebase deploy --only firestore:indexes
--project prod` abría un prompt ofreciendo borrarlos. Como nadie sabía qué eran,
la respuesta segura era "no" — y el prompt volvía en el deploy siguiente. Un
"y" distraído, en cambio, borraba índices sin que nadie supiera qué se llevaba
puesto.

Los cinco, obtenidos con `firebase firestore:indexes --project prod` (todos
`queryScope: COLLECTION`):

| # | colección | campos |
|---|---|---|
| 1 | `appointments` | `athleteId ASC`, `scheduledAt ASC` |
| 2 | `follows` | `members CONTAINS`, `followeeUid ASC`, `status ASC` |
| 3 | `follows` | `members CONTAINS`, `followerUid ASC`, `status ASC` |
| 4 | `posts` | `privacy ASC`, `authorGymId ASC` |
| 5 | `posts` | `privacy ASC`, `authorUid ASC` |

## Veredicto

**Los cinco están muertos. Ninguno respalda una query viva.**

Por lo tanto **`firestore.indexes.json` no necesita ningún agregado**: el archivo
ya declara exactamente los índices que las queries del repo requieren. Lo que
está de más está en prod, no en el repo, y sale con un `deploy` hecho por un
humano (§ Cómo podarlos).

| # | índice | veredicto | evidencia |
|---|---|---|---|
| 1 | `appointments (athleteId, scheduledAt)` | **muerto** — el campo no existe | el commit que lo mató lo dice textual |
| 2 | `follows (members, followeeUid, status)` | **muerto** — ninguna query combina `members` con nada | ADR-FOLLOW-002 / 003 |
| 3 | `follows (members, followerUid, status)` | **muerto** — ídem | ADR-FOLLOW-002 / 003 |
| 4 | `posts (privacy, authorGymId)` | **redundante** — las queries que lo tocarían son equality-only | `post_repository.dart:100-105` |
| 5 | `posts (privacy, authorUid)` | **redundante** — ídem | `post_repository.dart:85-90` |

"Muerto" y "redundante" no son lo mismo, y la diferencia importa al podar:

- **Muerto** = no hay ninguna query que ese índice pueda servir. Borrarlo no
  cambia nada, ni siquiera el plan de ejecución.
- **Redundante** = hay queries que *podrían* usarlo, pero **no lo necesitan**:
  Firestore las sirve igual sin él. Borrarlo no rompe nada, pero sí puede
  cambiar el plan (ver § El costo real de podar los de `posts`).

---

## 1. `appointments (athleteId, scheduledAt)` — muerto

`scheduledAt` **no es un campo del modelo**. Fue un bug: el cascade de borrado de
cuenta consultaba por un campo que ningún cliente escribe nunca, así que la query
devolvía siempre vacío y los turnos futuros del atleta borrado **nunca se
cancelaban** — se quedaban con su PII en la agenda del PF.

Lo arregló `e8eb6985` (QA-API-001), y el propio mensaje del commit nombra el
índice:

> `firestore.indexes.json`: composite index (athleteId, startsAt) — the query the
> cascade now runs (**the old (athleteId, scheduledAt) index was dead**).

El commit cambió la **declaración** en el archivo, pero el índice viejo siguió
vivo en prod porque el deploy que lo habría podado nunca se corrió (o se corrió y
alguien contestó "no" al prompt — que es exactamente el bucle que este documento
viene a cortar).

La query real de hoy es `athleteId == uid AND startsAt > now`
(`functions/src/cascade/appointments.ts:117-120`), y **sí** necesita un compuesto
—igualdad + desigualdad sobre campos distintos—: `appointments (athleteId,
startsAt)`, ya declarado.

**Verificación** — cero hits en código de producción; el único es un comentario
que dice explícitamente *NOT* `scheduledAt`:

```bash
rg -n 'scheduledAt' lib functions/src functions/scripts scripts -g '!**/__tests__/**' -g '!**/*_test.dart' -g '!**/*.test.ts' -g '!**/*.test.js'
```

Al escribir esto devuelve **1 línea**: `functions/src/cascade/appointments.ts:113`,
dentro del comentario del fix.

> **Resto que dejó el bug, fuera del alcance de esta auditoría — se arregla en
> [#933](https://github.com/Backhaus7997/treino/pull/933):**
> `functions/src/__tests__/notify-appointment.test.ts` sembraba `scheduledAt` en
> sus 5 fixtures mientras el código bajo test lee `after.startsAt`
> (`notify-appointment.ts:131,132,153,154`), así que el handler recibía
> `undefined` y el mail encolado salía con fecha y hora vacías — verde, porque
> ningún test asserteaba los params del mail. La misma clase de
> desincronización que causó QA-API-001, sobrevivida en los tests del propio
> fix.

---

## 2 y 3. `follows (members, follow{er,ee}Uid, status)` — muertos

En `follows`, `members` **existe solo para `array-contains`, y nunca se combina
con `status`**. No es una observación mía: es una decisión escrita del change
`follow-model`.

`openspec/changes/follow-model/design.md:85`:

> **Sin índices huérfanos nuevos**: no se crea `{members, status}` sobre
> `follows`. Ningún query combina `members` con `status` — ver ADR-FOLLOW-002 y
> ADR-FOLLOW-007.

ADR-FOLLOW-002 (`design.md:963-971`) explica el *por qué*: `members` es un campo
**derivado**, y un derivado puede driftear y mentir. La mitigación no es solo
validarlo en rules, es **limitar qué depende de él**. Por eso los contadores usan
queries direccionales (ADR-FOLLOW-007) y no `members`: si `members` driftea,
ningún número visible miente.

ADR-FOLLOW-003 (`design.md:975-983`) cierra el tema de los índices y hasta
anticipa el shape huérfano:

> **Enmienda al proposal.** […] `allOf` filtra **solo** por `members
> array-contains`, sin `status` — eso lo sirve el índice single-field automático.
> […] El compuesto queda huérfano y no se replica.

Los dos índices vivos en prod son, entonces, **exactamente los huérfanos que
ADR-FOLLOW-003 decidió no crear**. Nunca estuvieron declarados en el archivo
(`git log -S'members' -- firestore.indexes.json` no los muestra jamás sobre
`follows`), así que su origen más probable es la consola de Firebase: el link de
"crear índice" que Firestore ofrece en el error de una query que falló durante el
desarrollo del change.

Todas las queries vivas de `follows`, y qué las sirve:

| query | filtros | índice |
|---|---|---|
| `allOf` (`follow_repository.dart:162`) | `members array-contains` | single-field automático |
| `sweepFollows` (`cascade/friendships.ts:36-37`) | `members array-contains` | single-field automático |
| `_followingQuery` (`follow_repository.dart:166-168`) | `followerUid ==`, `status ==` | **ninguno** (equality-only) |
| `_followersQuery` (`follow_repository.dart:170-172`) | `followeeUid ==`, `status ==` | **ninguno** (equality-only) |
| `_pendingReceivedQuery` (`follow_repository.dart:174-176`) | `followeeUid ==`, `status ==` | **ninguno** (equality-only) |
| `countAcceptedFor` (`maintain-follow-counters.ts:160-167`) | ídem, las dos direcciones | **ninguno** (equality-only) |
| `backfill-follow-counters.ts:150-152` | `status ==` | single-field automático |

Un índice compuesto cuyo primer campo es un `array-contains` **solo puede servir
queries que incluyan ese `array-contains`** (es un índice fan-out, una entrada
por elemento del array; sin el filtro devolvería duplicados). O sea: estos dos
índices solo servirían a una query `members array-contains X AND follow*Uid == Y
AND status == Z`. No existe, ni existió nunca.

**Verificación** — todo filtro sobre `members`, con contexto para ver si alguno
encadena un segundo `.where`:

```bash
rg -n -A6 "where\(.members., *(arrayContains|.array-contains.)" lib functions/src functions/scripts scripts
```

Al escribir esto, los hits **sobre `follows` en código de producción** son
exactamente dos —`follow_repository.dart:162` y `cascade/friendships.ts:37`— y
los dos son `array-contains` **pelado**, sin segundo filtro. El resto de los hits
son sobre `chats` (otra colección, cuyo compuesto `{members, lastMessageAt DESC}`
**sí** está declarado y **sí** está en uso: `chat_repository.dart:221-222`) o son
tests.

> **No confundir con el huérfano de `friendships`.** El archivo declara
> `friendships (members CONTAINS, status ASC)` y ese **no se toca**:
> ADR-FOLLOW-003 lo conserva a propósito hasta M-10, porque un rollback del
> cliente reactiva exactamente esa query y un índice recién recreado tarda en
> construirse — borrarlo convierte un rollback de minutos en un incidente.

---

## 4 y 5. `posts (privacy, authorUid)` y `posts (privacy, authorGymId)` — redundantes

Inventario completo de queries sobre `posts` y qué índice requiere cada una:

| query | filtros | `orderBy` | índice requerido | ¿declarado? |
|---|---|---|---|---|
| `byAuthor` (`post_repository.dart:72`) | `authorUid ==` | — | single-field | automático |
| `byAuthorAndPrivacy` (`:85-90`) | `authorUid ==`, `privacy ==` | — | **ninguno** | — |
| `byAuthorGymTier` (`:100-105`) | `authorUid ==`, `privacy ==`, `authorGymId ==` | — | **ninguno** | — |
| `feedPublic` (`:109-118`) | `privacy ==`, `[createdAt <]` | `createdAt DESC` | `(privacy, createdAt DESC)` | ✅ |
| `feedForFriends` (`:151-160`) | `privacy ==`, `authorUid in`, `[createdAt <]` | `createdAt DESC` | `(privacy, authorUid, createdAt DESC)` | ✅ |
| `feedForGym` (`:181-196`) | `privacy ==`, `authorGymId ==`, `[createdAt <]` | `createdAt DESC` | `(privacy, authorGymId, createdAt DESC)` | ✅ |
| `firstPostByAuthorProvider` (`public_profile_providers.dart:24-27`) | `authorUid ==` | `createdAt DESC` | `(authorUid, createdAt DESC)` | ✅ |
| `sweepPosts` (`cascade/posts.ts:57-58`) | `authorUid ==` | — | single-field | automático |

Las únicas dos queries que un compuesto `(privacy, authorUid)` o `(privacy,
authorGymId)` podría servir son `byAuthorAndPrivacy` y `byAuthorGymTier`, y las
dos son **equality-only sin `orderBy`**. Ese tipo de query **no requiere índice
compuesto en absoluto**: Firestore la resuelve con un *zigzag merge join* sobre
los índices single-field automáticos.

No es una inferencia: es la razón de diseño que el propio repositorio documenta
en el dartdoc de esos dos métodos —*"Two equality filters need no composite index
(zigzag merge); results are sorted by the caller"* (`post_repository.dart:79-80`)
y *"Three equality filters need no composite index (zigzag merge)"*
(`:98-99`)— y la misma que invoca ADR-FOLLOW-003: *"Las queries de este change
son equality-only y Firestore las serviría por index merge."*

### El razonamiento del prefijo: no hace falta, y es el más flojo de los dos

Hay una tentación de justificar la redundancia diciendo *"Firestore puede servir
una query de solo igualdades desde el prefijo de un índice más largo, y los de 3
campos con `createdAt DESC` al final ya están"*. **La conclusión es correcta, el
argumento no conviene.**

Una query sin `orderBy` explícito ordena implícitamente por `__name__ ASC`. Un
compuesto `(privacy, authorUid, createdAt DESC)` lleva un `__name__` implícito al
final que **no** es ascendente. Decir "sale del prefijo" es una afirmación sobre
qué elige el planner de Firestore, que desde el repo no se puede verificar.

La regla de equality-only, en cambio, **no depende del planner**: esas queries no
requieren compuesto, punto. Es una garantía documentada, y el repo ya la usa como
base de diseño en dos lugares. Cuando hay dos argumentos para la misma
conclusión, el correcto es el que no hay que suponer.

### La precondición que sí hay que chequear: `fieldOverrides`

El zigzag merge necesita que existan los índices **single-field automáticos** de
`privacy`, `authorUid` y `authorGymId`. Firestore los crea solos… salvo que un
`fieldOverride` los desactive. Y un `fieldOverride` **reemplaza, no suma**:
declarar un solo scope para un campo borra sus índices automáticos.

Hoy el archivo tiene `"fieldOverrides": []`, o sea **ninguno desactivado**.

```bash
python3 -c "import json;print(json.load(open('firestore.indexes.json'))['fieldOverrides'])"
```

→ `[]`.

**Si alguien agrega un `fieldOverride` sobre `posts` o `follows`, esta auditoría
deja de valer** y hay que rehacerla.

### El costo real de podar los de `posts`

Es el único punto de los cinco donde borrar tiene un efecto observable, y es de
performance, no de corrección:

- **Corrección**: garantizada. Ninguna query se rompe.
- **Performance**: `byAuthorAndPrivacy` y `byAuthorGymTier` pasarían a resolverse
  por zigzag merge en vez de por un scan directo. Las dos están acotadas a *los
  posts de un solo autor* y alimentan la pantalla de perfil público — no el feed.
  `byAuthorGymTier` es el peor caso (3 igualdades, 3 índices a mergear).

Contra eso: mantener los dos índices cuesta write amplification en **cada
escritura de un post**, para siempre.

---

## Cómo podarlos

**Esto lo hace un humano.** Ningún agente corre `firebase deploy` contra `prod`
(AGENTS.md § Entornos).

1. Confirmar que el estado de prod sigue siendo el auditado:

   ```bash
   firebase firestore:indexes --project prod
   ```

   Si aparecen índices que no están en la tabla de arriba **ni** en
   `firestore.indexes.json`, esta auditoría está incompleta: no borres a ciegas,
   auditá los nuevos igual que estos cinco.

2. Correr el deploy y **leer el prompt antes de contestar**:

   ```bash
   firebase deploy --only firestore:indexes --project prod
   ```

   Debe ofrecer borrar **exactamente los cinco** de la tabla. Si ofrece borrar
   alguno que no está en esa lista → **cancelar** y volver al paso 1.

3. Solo entonces, `y`.

Después de eso, prod y `firestore.indexes.json` quedan iguales y el prompt deja
de aparecer.

## Lo que esta auditoría NO cubre

Escrito explícito porque un "ya está todo cubierto" que no es cierto es peor que
no decir nada (AGENTS.md §11.1):

- **No verifiqué el sentido inverso**: que todo índice declarado en el archivo
  exista en prod. Un declarado-pero-ausente haría que el deploy lo *cree*, que es
  inofensivo, pero significaría que hoy hay una query corriendo sin índice.
- **No corrí ningún comando contra `prod`.** La lista de los cinco es la que
  pasó el usuario. El paso 1 del runbook existe justamente para revalidarla.
- **El emulador no sirve para probar esto**: no impone índices compuestos, sirve
  cualquier query. Un test verde en emulador no dice nada sobre si un índice
  hace falta.
- **Dos huérfanos declarados a propósito quedan como están**: `friendships
  (members, status)` (ADR-FOLLOW-003, hasta M-10) y los dos `follows
  (follow*Uid, status, createdAt DESC)`, que ADR-FOLLOW-003 declaró por
  adelantado para `follow-lists` y que hoy ninguna query usa con `orderBy`
  (`follow_repository.dart:111-119` explica por qué el orden no se adoptó).
- **`routines (assignedBy, source, createdAt DESC)` estaba declarado DOS veces**
  en `firestore.indexes.json` (37 declarados, 36 únicos). Lo metió `63635ad3`,
  el commit que declaró índices huérfanos de prod: uno de los dos ya estaba.
  Es inocuo —Firebase deduplica specs idénticos— pero es un defecto de fuente de
  verdad en el mismo archivo. **Se arregla en
  [#933](https://github.com/Backhaus7997/treino/pull/933)**, aparte de esta
  auditoría para no mezclar scopes. El comando que lo detecta:

  ```bash
  python3 -c "
  import json,collections
  d=json.load(open('firestore.indexes.json'))
  k=[(i['collectionGroup'],tuple((f['fieldPath'],f.get('order') or f.get('arrayConfig')) for f in i['fields'])) for i in d['indexes']]
  print([x for x,n in collections.Counter(k).items() if n>1])"
  ```

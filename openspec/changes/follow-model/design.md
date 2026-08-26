# Design: follow-model — arquitectura del seguimiento asimétrico

Sigue a `proposal.md` (LD-01..LD-10) y a `explore.md`. Donde el design **enmienda** una decisión del proposal lo digo explícito y con la evidencia que lo fuerza — hay cinco casos: el índice compuesto huérfano (ADR-FOLLOW-003), el orden del flip (ADR-FOLLOW-010), **la forma de la migración (ADR-FOLLOW-013), que revierte LD-06 por decisión del dueño** (cada amistad `accepted` migra a DOS aristas, no a una), **el momento del freeze (ADR-FOLLOW-015)**, que se adelanta a antes de M-04 para cerrar un agujero de phantom access por borrados, y **el chat direccional (ADR-FOLLOW-005), decisión del dueño que reemplaza a LD-08** y saca de Out of Scope la elegibilidad de DMs.

> ✅ **Decisión del dueño, cerrada: el chat pasa a ser direccional. X le puede escribir a Y sólo si Y sigue a X.** Dejar de seguir a alguien le saca a esa persona la escritura hacia vos; vos podés seguir escribiéndole a ella. Desarrollo en §3.3 y en **ADR-FOLLOW-005**. **Consecuencia estructural que la decisión arrastra y que hay que leer antes que nada: el gate deja de vivir sólo en `chats/create` y pasa a evaluarse en `chats/{chatId}/messages/create`**, porque "uno puede escribir y el otro no **dentro del mismo chat**" no es expresable en una regla que corre una sola vez, al crear el doc.

## 0. Idea rectora

Hoy el sistema tiene **dos modelos mentales peleados**: las Cloud Functions y las notificaciones ya razonan en aristas dirigidas (`requesterId` sigue al otro), pero la capa de datos y el gate de acceso razonan en pares no dirigidos. `requesterId` es un campo direccional escondido adentro de un doc simétrico.

El cambio no inventa un modelo nuevo: **promueve el modelo que ya existe implícito a la estructura del documento**. `requesterId` deja de ser un campo y pasa a ser el *doc id*. Todo lo demás es consecuencia.

```
ANTES                                  DESPUÉS
friendships/{min}_{max}                follows/{follower}_{followee}
  requesterId: quién pidió  ─────────►   followerUid  (= el doc id, izquierda)
  members: [min, max]                    followeeUid  (= el doc id, derecha)
  status                                 members: [follower, followee]  (derivado)
                                         status

acceso: exists(pair) && accepted       acceso: exists(lector_autor) && accepted
        ↑ simétrico por construcción            ↑ direccional por construcción
```

**Invariante central del diseño**: la dirección nunca se calcula ni se infiere en runtime. Está en la clave del documento. Rules, CFs y cliente la leen del mismo lugar y no pueden divergir.

**Qué NO hace el cambio**: reescribir el pasado. Cada amistad `accepted` que ya existe migra a **dos aristas** — queda como follow mutuo — así que nadie pierde acceso a lo que hoy ve. La asimetría rige **desde el flip en adelante** (ADR-FOLLOW-013, decisión del dueño que revierte LD-06). Las `pending` sí migran a una sola arista: una solicitud es direccional por naturaleza.

---

## 1. Arquitectura de datos

### 1.1 Forma exacta de `follows/{followId}`

`followId == '{followerUid}_{followeeUid}'` — **NO ordenado**. La concatenación es la arista.

| Campo | Tipo Firestore | Tipo Dart | Nulo | Descripción |
|---|---|---|---|---|
| `id` | `string` | `String` | no | Igual al doc id. Redundante a propósito (paridad con `Friendship`, `toJson()` de freezed sin código custom). Rules lo pinean a `followId`. |
| `followerUid` | `string` | `String` | no | Quién sigue. Es el prefijo del doc id y el único autorizado a crear/cancelar la arista. |
| `followeeUid` | `string` | `String` | no | A quién sigue. Es el sufijo del doc id y el único autorizado a aceptar. |
| `status` | `string` | `FollowStatus` | no | `'pending'` \| `'accepted'`. **Mismos wire values que hoy** (LD-02). |
| `members` | `array<string>` | `List<String>` | no | **Derivado e inmutable**: exactamente `[followerUid, followeeUid]`, en ese orden. Existe solo para `array-contains` (ver ADR-FOLLOW-002). |
| `createdAt` | `timestamp` | `DateTime` (`@TimestampConverter`) | no | Se **preserva** del friendship de origen — en las `accepted`, las **dos** aristas del par heredan el mismo valor. V2/V3 de §7.3 lo comparan. |

Campos que **desaparecen**: `uidA` / `uidB` (eran el par ordenado, 100% redundante con `members`) y `requesterId` (ascendió a doc id).

Invariantes que rules hace cumplir en el `create` (§3.1):

1. `followId == followerUid + '_' + followeeUid`
2. `followerUid != followeeUid` (no auto-follow)
3. `members == [followerUid, followeeUid]` (comparación literal de lista)
4. `id == followId`
5. `keys().hasOnly([...])` — allowlist cerrada de las 6 keys
6. `status == 'pending'`, o `'accepted'` solo si `userPublicProfiles/{followeeUid}.isProfilePublic` (default `true`) es verdadero

**Las invariantes 3, 4 y 5 también rigen en el `update`, no solo en el `create`.** La allowlist tiene que ser cerrada en las dos operaciones o no es una allowlist: sin `hasOnly` en el `update`, el `followeeUid` puede agregar campos arbitrarios al aceptar; sin pinear `id`, puede desincronizarlo del doc id. En los dos casos el doc resultante **viola V5 de la verificación** (§7.3), que exige el key set exacto y `id == docId` — o sea que la única vía de escritura legítima podría producir un documento que la propia verificación del change marca como inválido. El bloque de §3.1 lo implementa en ambas.

### 1.2 Índices

**Nuevos, declarados en `firestore.indexes.json`:**

```json
{ "collectionGroup": "follows", "queryScope": "COLLECTION", "fields": [
  { "fieldPath": "followerUid", "order": "ASCENDING" },
  { "fieldPath": "status",      "order": "ASCENDING" },
  { "fieldPath": "createdAt",   "order": "DESCENDING" } ] },
{ "collectionGroup": "follows", "queryScope": "COLLECTION", "fields": [
  { "fieldPath": "followeeUid", "order": "ASCENDING" },
  { "fieldPath": "status",      "order": "ASCENDING" },
  { "fieldPath": "createdAt",   "order": "DESCENDING" } ] }
```

Qué sirve cada uno:

| Query | Índice | Consumidor |
|---|---|---|
| `followerUid == uid && status == 'accepted'` | #1 | `watchFollowingOf` (feed AMIGOS), CF contadores |
| `followerUid == uid && status == 'pending'` | #1 | solicitudes enviadas (`follow-lists`, futuro) |
| `followeeUid == uid && status == 'pending'` | #2 | inbox de solicitudes recibidas |
| `followeeUid == uid && status == 'accepted'` | #2 | CF contadores, lista de seguidores (`follow-lists`, futuro) |
| `members array-contains uid` | **auto** (single-field) | `allOf` (exclusión en sugerencias), `sweepFollows` |
| `follows/{id}` por doc id | **ninguno** | botón SEGUIR, gate de rules |

**Sin índices huérfanos nuevos**: no se crea `{members, status}` sobre `follows`. Ningún query combina `members` con `status` — ver ADR-FOLLOW-002 y ADR-FOLLOW-007.

**Huérfano existente**: `friendships {members CONTAINS, status ASC}` (`firestore.indexes.json:131-137`) queda sin consumidor después de M-08. **NO se borra en este change** (ADR-FOLLOW-003): borrarlo destruye el rollback, porque revertir el cliente reactiva exactamente esos queries y un índice recién recreado tarda en construirse.

---

## 2. Componentes y flujo

```
┌─ presentation ────────────────────────────────────────────────┐
│ PublicProfileScreen ──► PublicProfileFollowButton (4 estados) │
│ FriendRequestsInboxScreen ──► FriendRequestInboxTile          │
│ UnfriendConfirmationSheet (reusado: unfollow Y cancelar)      │
└───────────────┬───────────────────────────────────────────────┘
                │ ref.watch
┌─ application ─▼───────────────────────────────────────────────┐
│ follow_providers.dart                                         │
│   followRepositoryProvider                                    │
│   followEdgeProvider(String edgeId)      ← key = doc id       │
│   followingProvider(String uid)                               │
│   pendingReceivedStreamProvider(String uid)                   │
│   pendingRequestCountProvider(String uid)                     │
│ public_profile_providers.dart → PublicProfileView             │
│   (compone DOS aristas: saliente + entrante)                  │
│ feed_screen_providers.dart → myFollowingFeedProvider          │
│ post_providers.dart → visiblePostsByAuthorProvider            │
└───────────────┬───────────────────────────────────────────────┘
                │
┌─ data ────────▼───────────────────────────────────────────────┐
│ FollowRepository (collection 'follows')                       │
│ PostRepository.feedForFollowedAuthors (whereIn ≤30)           │
└───────────────┬───────────────────────────────────────────────┘
                │
┌─ domain ──────▼───────────────────────────────────────────────┐
│ Follow (freezed) · FollowStatus (enum + wire map)             │
│ Follow.edgeId(follower, followee) → '{follower}_{followee}'   │
└───────────────────────────────────────────────────────────────┘

┌─ servidor ────────────────────────────────────────────────────┐
│ firestore.rules   : follows CRUD · postFollowerAccepted        │
│                     reactionPostReadable                       │
│                     chatCreateOk (chats/create)                │
│                     senderMayPost (messages/create) ← NUEVO    │
│ maintainFollowCounters · notifyOnFollow · sweepFollows         │
└───────────────────────────────────────────────────────────────┘
```

**Flujo "SEGUIR" (cuenta privada)**
`FollowButton.onTap` → `repo.follow(me, target, targetIsPublic: false)` → `set(follows/{me}_{target}, status: pending)` → rules valida invariantes 1-6 → `followEdgeProvider('{me}_{target}')` re-emite vía `.snapshots()` → pill pasa a SOLICITUD ENVIADA (**ahora con `onTap` → cancelar**) → `notifyOnFollow` empuja "te envió una solicitud de seguidor" al followee. Contadores: **no se mueven** (pending no es follow efectivo).

**Flujo "ACEPTAR"**
`target` abre inbox o el perfil de `me` → `update(follows/{me}_{target}, status: accepted)` → rules exige `auth.uid == resource.data.followeeUid` → `maintainFollowCounters` recalcula ambos perfiles en una transacción → `notifyOnFollow` empuja "aceptó tu solicitud" al follower.

**Flujo "leer post tier followers"**
Cliente pide `posts where privacy=='friends' and authorUid in [autores que YO sigo]` → rules evalúa `postFollowerAccepted(authorUid)` = `exists(follows/{lector}_{autor}) && status=='accepted'`. El query del cliente está construido para que **cada fila devuelta ya satisface la regla** — mismo contrato que hoy (`firestore.rules:528-535`).

---

## 3. Rules

### 3.1 Bloque `follows/{followId}`

```
match /follows/{followId} {
  allow read: if request.auth != null
              && (resource == null || request.auth.uid in resource.data.members);

  allow create: if request.auth != null
                && request.auth.uid == request.resource.data.followerUid
                && followId == request.resource.data.followerUid + '_' + request.resource.data.followeeUid
                && request.resource.data.followerUid != request.resource.data.followeeUid
                && request.resource.data.id == followId
                && request.resource.data.keys().hasOnly(
                     ['id','followerUid','followeeUid','status','members','createdAt'])
                && request.resource.data.members ==
                     [request.resource.data.followerUid, request.resource.data.followeeUid]
                && request.resource.data.createdAt is timestamp
                && (
                  request.resource.data.status == 'pending'
                  || (request.resource.data.status == 'accepted'
                      && get(/databases/$(database)/documents/userPublicProfiles/$(request.resource.data.followeeUid))
                           .data.get('isProfilePublic', true) == true)
                );

  allow update: if request.auth != null
                && request.auth.uid == resource.data.followeeUid
                && request.resource.data.keys().hasOnly(
                     ['id','followerUid','followeeUid','status','members','createdAt'])
                && request.resource.data.id == followId
                && resource.data.status == 'pending'
                && request.resource.data.status == 'accepted'
                && request.resource.data.followerUid == resource.data.followerUid
                && request.resource.data.followeeUid == resource.data.followeeUid
                && request.resource.data.members == resource.data.members
                && request.resource.data.createdAt == resource.data.createdAt;

  allow delete: if request.auth != null && request.auth.uid in resource.data.members;
}
```

Dos mejoras que salen **gratis** del doc id direccional:

- El `get()` de auto-accept apunta a un uid **conocido** (`followeeUid`). Hoy hay que probar `uidA` y si no `uidB` (`firestore.rules:1072-1078`): **de ≤2 `get()` a exactamente 1**.
- **El self-accept deja de ser un check y pasa a ser un invariante estructural**: solo el `followeeUid` puede hacer `update`, y `followerUid != followeeUid` se valida en el `create`. SCENARIO-132 sigue existiendo como test, pero ya no hay una condición que alguien pueda borrar por accidente.

**El `update` lleva la misma allowlist que el `create`, y también pinea `id`.** No es simetría cosmética: el `update` es la única escritura que hace un usuario distinto del creador del doc. Sin `hasOnly`, aceptar una solicitud es una vía para inyectar campos que rules no valida; sin el pin de `id`, para desincronizar `id` del doc id. Los dos productos violan **V5** (§7.3), así que la escritura legítima podría fabricar un documento que la verificación del propio change rechaza. Los `create` y `update` de `follows` tienen que ser cerrados **los dos** o la allowlist no existe.

#### 3.1.1 Verificación explícita del caso mutuo (dos docs para el mismo par)

Con ADR-FOLLOW-013 el follow mutuo deja de ser un caso raro: **es el estado de toda la base migrada**. Reviso el bloque de arriba contra ese caso, porque un shape que asuma "un doc por par" fallaría acá.

| Situación | Qué evalúa la regla | Resultado |
|---|---|---|
| Existe `follows/{A}_{B}`; B crea `follows/{B}_{A}` | El `create` solo mira `request.resource.data` y `followId`. **Ninguna condición referencia la arista opuesta** | OK, doc independiente |
| B acepta `follows/{A}_{B}` mientras existe `follows/{B}_{A}` | El `update` pinea campos **del mismo doc** (`resource` vs `request.resource`) | OK, no toca la otra |
| A borra `follows/{A}_{B}` (unfollow) con `follows/{B}_{A}` presente | `delete` evalúa `resource.data.members` **del doc borrado**. Rules es por documento: no hay cascada ni borrado transitivo | La arista de B **sobrevive**: B sigue siguiendo a A |
| B borra `follows/{A}_{B}` ("quitar seguidor", REQ-FOLLOW-008) | Idem: `B in members` | Se corta **solo** la dirección A→B. B sigue siguiendo a A |
| Contadores tras borrar una de las dos | La CF dispara **una vez por documento escrito** y recomputa desde cero (§4.1b) | Queda `following`/`followers` correcto y asimétrico, sin doble evento |

Tres notas que salen de esta revisión y hay que dejar escritas:

1. **El doc id ya garantiza unicidad por dirección**: `{A}_{B}` y `{B}_{A}` son claves distintas y ninguna colisiona, así que "dos aristas para la misma pareja" no necesita ni un campo ni una regla nueva. Es la misma propiedad que hace idempotente a la migración (ADR-FOLLOW-014).
2. **Seguir de vuelta a una cuenta privada sigue requiriendo aprobación.** Si A sigue a B y B quiere devolver el follow, el `create` de `follows/{B}_{A}` evalúa `isProfilePublic` **de A**, no de B. Que exista la arista opuesta no auto-aprueba nada. Correcto y deliberado.
3. **"Quitar seguidor" no rompe el mutuo**, corta una dirección. La UI de `follow-lists` (LD-07) no puede asumir lo contrario cuando exista.

### 3.2 Gate de posts y reacciones

```
function postFollowerAccepted(authorUid) {
  let fid = request.auth.uid + '_' + authorUid;   // ← sin ordenar: ESA es la asimetría
  return exists(/databases/$(database)/documents/follows/$(fid))
      && get(/databases/$(database)/documents/follows/$(fid)).data.status == 'accepted';
}
```

Reemplaza a `postFriendAccepted` (`firestore.rules:536-542`) en los dos call sites: `posts/{postId}` read (línea 554) y `reactionPostReadable()` (línea 648). El literal `'friends'` de `resource.data.privacy` **no se toca** en ningún lado (LD-05): las allowlists de `create`/`update` (líneas 587, 624) quedan byte-idénticas.

El diff completo de rules para el gate es **borrar 3 líneas de cálculo de `fid` ordenado y cambiar la colección**. Esa es la medida de que el modelo estaba mal, no las reglas.

### 3.3 Chat direccional (LD-08, decisión del dueño)

**Regla de producto: X le puede escribir a Y sólo si Y sigue a X.** El permiso de escritura es una propiedad de la arista `follows/{Y}_{X}` — el destinatario tiene que estar siguiendo al remitente. Dejar de seguir es, por lo tanto, **una sola acción que corta el vínculo entrante**: el que dejo de seguir pierde la escritura hacia mí, y yo conservo la mía hacia él.

#### 3.3.1 Hallazgo que la decisión obliga a mirar primero: hoy el gate no vive donde se cree

**Verificado en el código, y contradice la premisa con la que llegó la decisión.** `chatRelationshipOk` se invoca en **un solo lugar**: `allow create` de `/chats/{chatId}` (`firestore.rules:1134`). La subcolección de mensajes gatea **sólo por membresía** (`firestore.rules:1167-1170`: `request.auth.uid in get(chats/{chatId}).data.members`), el `update` del chat también (`:1142`), y nada borra el chat cuando se borra la amistad — `friendship_repository.dart:150-151` borra el doc de `friendships` y punto; `sweepFriendships` sólo corre en el cascade de borrado de cuenta.

Conclusión, dicha sin maquillar: **hoy "eliminar amistad" NO corta los mensajes de un chat que ya existe.** Los dos siguen pudiendo escribirse indefinidamente; lo único que se rompe es abrir un chat **nuevo**. La intuición que la decisión del dueño quiere preservar —"corto el vínculo y dejo de recibir mensajes"— **no está implementada hoy**. Esto no invalida la decisión: la vuelve más ambiciosa de lo que parecía. Implementarla exige **mover el gate al envío de mensajes**, que es una restricción nueva, no la conservación de una vigente.

Es además la única forma de expresarla: la asimetría es *dentro del mismo chat* (uno escribe, el otro no), y una regla que corre una sola vez —al crear el doc— no puede producir dos permisos distintos para el mismo documento.

#### 3.3.2 Las dos reglas

```
// helper compartido con el gate de posts (§3.2) — misma forma, mismo costo
function followAccepted(f, t) {
  let id = f + '_' + t;
  return exists(/databases/$(database)/documents/follows/$(id))
      && get(/databases/$(database)/documents/follows/$(id)).data.status == 'accepted';
}

match /chats/{chatId} {

  // Abrir el chat == poder mandar el primer mensaje. Reemplaza a chatRelationshipOk.
  function chatCreateOk(members, data) {
    let me    = request.auth.uid;
    let other = members[0] == me ? members[1] : members[0];
    return followAccepted(other, me)                  // ← el DESTINATARIO me sigue
        || ( 'linkId' in data && ...rama trainer_link SIN CAMBIOS... );
  }

  allow create: if ...members.size()/orden/chatId SIN CAMBIOS...
                && chatCreateOk(request.resource.data.members, request.resource.data);

  // read + update (preview y lastRead): membresía. SIN CAMBIOS — ver 3.3.4.

  match /messages/{messageId} {

    // NUEVA. Es la que hace asimétrica la escritura dentro de un mismo chat.
    function senderMayPost(uid) {
      let chat  = get(/databases/$(database)/documents/chats/$(chatId)).data;
      let other = chat.members[0] == uid ? chat.members[1] : chat.members[0];
      return uid in chat.members
          && (
               'linkId' in chat              // chat de trainer_link: como hoy, membresía
               || followAccepted(other, uid) // social: el destinatario me sigue
             );
    }

    // read: membresía. SIN CAMBIOS.

    allow create: if request.auth != null
                  && request.auth.uid == request.resource.data.senderId
                  && senderMayPost(request.auth.uid)      // ← reemplaza al check de membresía
                  && ( ...text OR mediaUrl+mediaType, SIN CAMBIOS... )
                  && request.resource.data.createdAt is timestamp;
  }
}
```

`members[0] < members[1]` y `chatId == members[0] + '_' + members[1]` ya están garantizados por el propio `allow create` (`firestore.rules:1130-1133`) y `members` es inmutable en el `update` (`:1144`), así que derivar "el otro" del array del doc es exacto y no necesita partir el `chatId` ni ningún dato nuevo.

**`senderMayPost` absorbe el check de membresía en vez de sumarse a él**: el `get()` del chat que la regla vieja ya hacía es el mismo que la nueva usa para sacar `members`. Por eso el costo no se duplica.

**Orden de las ramas, deliberado**: `'linkId' in chat` va **primero** para que un chat de trainer_link no pague ninguna llamada extra. La rama trainer queda **exactamente** como hoy —membresía, sin re-verificar que el link siga activo— porque apretar el Coach no es parte de este change y hacerlo en silencio sería colar producto adentro de una migración.

#### 3.3.3 Costo en llamadas de acceso

| Operación | Hoy | Después | Δ |
|---|---|---|---|
| `chats/create` — rama social | `exists`+`get` sobre `friendships/{chatId}` = **2** | `exists`+`get` sobre **una** arista = **2** | **=** |
| `chats/create` — peor caso (social falla → trainer) | ≤6 | ≤6 | **=** |
| `messages/create` — chat social | `get(chats)` = **1** | `get(chats)` + `exists`+`get` de la arista = **3** | **+2** |
| `messages/create` — chat con `linkId` | 1 | **1** | **=** |
| `messages/read`, `chats/read`, `chats/update` (`lastRead`) | 1 / 0 / 0 | igual | **=** |

Se cuenta `exists(X)` + `get(X)` sobre el mismo doc como **2**, misma convención conservadora que §3.4 usa para el gate de posts.

**Efecto colateral favorable: `chats/create` deja de encarecerse.** La versión anterior de este ADR componía **dos** direcciones con un OR y subía el peor caso a ≤8 sobre 10. Un lookup direccional único cuesta lo mismo que el `exists`+`get` sobre `friendships` que reemplaza. **R5 del proposal y A2 del design se cierran**: el margen dejó de ser ajustado.

Lo que sí aparece es un costo **por mensaje enviado**: +2 llamadas, techo 3 sobre 10. Es el precio de que la asimetría sea real y no una decoración del momento de creación.

#### 3.3.4 Qué NO se toca, y por qué

- **Lectura del chat y de los mensajes: membresía, sin cambios.** El lado que perdió la escritura **sigue leyendo** la conversación entera. Bloquear también la lectura sería borrar historia que el usuario ya recibió.
- **`chats/update` (preview y `lastRead`): membresía, sin cambios.** El lado bloqueado tiene que poder marcar como leído. Atarlo al permiso de escritura dejaría el badge de no-leídos clavado para siempre.
- **`chats/delete: if false`**: sin cambios.

#### 3.3.5 Los tres casos que la decisión genera sobre el dato existente

| Caso | Estado en `follows` | Resultado |
|---|---|---|
| **Par migrado desde una `accepted`** | ambas aristas (ADR-FOLLOW-013) | **Los dos siguen escribiendo.** El chat queda exactamente como hoy. Es el caso mayoritario y el que la migración garantiza |
| **Unfollow post-flip de una sola dirección** (A deja de seguir a B) | queda `follows/{B}_{A}` | **B pierde la escritura hacia A**; A le sigue escribiendo a B. Es la semántica pedida: una sola acción corta el vínculo entrante |
| **Chat preexistente cuyo par ya no tiene amistad** (se eliminó en algún momento antes de la migración) | ninguna arista | **Los dos pierden la escritura**; los dos conservan la lectura. **Es una regresión respecto de hoy** —hoy ese chat sigue vivo porque el gate no corre en `messages`— y es una consecuencia que el dueño **evaluó y aceptó explícitamente** al cerrar la decisión, no un efecto colateral hallado después de implementarla. Se declara, no se mitiga. Riesgo **A14** |

El tercero es el que nadie pidió y hay que decir en voz alta: mover el gate a `messages/create` lo aplica **retroactivamente** a conversaciones que hoy funcionan. A volumen de equipo (M-00) son cero o un puñado de pares, y el criterio es el mismo que rige todo el change: la regla nueva es la correcta y se aplica pareja.

### 3.4 Presupuesto de `get()` por request

Límite de Firestore: **10 llamadas de acceso** (`get`/`exists`/`getAfter`) para single-document requests y query requests; **20** para multi-document reads, transacciones y batched writes.

| Operación | Hoy | Después | Δ |
|---|---|---|---|
| read post `public` / propio | 0 | 0 | = |
| read post `friends` (no autor) | 2 | 2 | **=** |
| read post `gym` | 1 | 1 | = |
| read reacción sobre post `friends` | 3 | 3 | **=** |
| read reacción sobre post `gym` | 2 | 2 | = |
| create follow `pending` | 0 | 0 | = |
| create follow `accepted` (auto) | ≤2 | **1** | **−1** |
| accept (update) | 0 | 0 | = |
| delete (unfollow/cancelar) | 0 | 0 | = |
| **create chat** — rama social OK | 2 | **2** | **=** |
| **create chat** — peor caso (social falla → trainer) | ≤6 | **≤6** | **=** |
| **enviar mensaje** — chat social | 1 | **3** | **+2** |
| **enviar mensaje** — chat con `linkId` (Coach) | 1 | **1** | **=** |
| leer mensaje / leer chat / `lastRead` | 1 / 0 / 0 | igual | = |

**El camino caliente es costo-neutro por construcción**: la asimetría cuesta cero llamadas extra porque cambia *qué doc id* se mira, no *cuántos*. Eso ahora vale también para `chats/create`: el lookup direccional único reemplaza al `exists`+`get` sobre `friendships/{chatId}` **uno a uno**, así que el peor caso vuelve a ≤6 sobre 10 y el margen deja de estar ajustado (§3.3.3; cierra R5 del proposal y A2 de §9).

El único aumento real es **+2 por mensaje enviado en un chat social**, techo 3 sobre 10 — consecuencia directa de mover el gate a `messages/create`, que es lo que hace asimétrica la escritura (§3.3.1). `chat-relationship-rules.test.ts` pasa a cubrir las dos superficies (`chats/create` y `messages/create`) contra el emulador, no contra la teoría.

**Riesgo abierto y honesto (ver ADR-FOLLOW-008)**: en un *query request* que devuelve N posts de N autores distintos, el presupuesto es de 10 llamadas. Si el conteo fuese por request y no por documento evaluado, el `feedForFriends` de hoy con `chunkSize=10` ya estaría al borde, y subirlo a 30 lo rompería. Funciona en producción hoy, así que el conteo efectivo no puede ser plano por request — pero **eso es una inferencia, no una lectura de la documentación**, y no se sube el chunk apoyado en una inferencia.

---

## 4. Cloud Functions

### 4.1 `maintainFollowCounters`

La lógica direccional (`resolveCounterDelta`, tabla before→after de `maintain-follow-counters.ts:28-36`) **no cambia**. Cambian dos cosas:

**a) `partiesOf()` deja de inferir.** Hoy (líneas 72-81) toma `requesterId`, busca en `members` el que no es el requester, y devuelve `null` si el doc está malformado. Después:

```ts
function partiesOf(data) {
  const follower = data.followerUid as string | undefined;
  const followee = data.followeeUid as string | undefined;
  if (!follower || !followee || follower === followee) return null;
  return { requesterUid: follower, otherUid: followee };
}
```

Se borra toda la búsqueda dentro de `members`. La rama "malformed parties" se conserva (defensa contra docs escritos por Admin SDK que saltean rules).

**b) `countAcceptedFor()` pasa de 1 query + split en memoria a 2 queries direccionales.**

```ts
const [followingSnap, followersSnap] = await Promise.all([
  tx.get(db.collection("follows").where("followerUid","==",uid).where("status","==","accepted")),
  tx.get(db.collection("follows").where("followeeUid","==",uid).where("status","==","accepted")),
]);
return { followingCount: followingSnap.size, followersCount: followersSnap.size };
```

Se mantiene el **recompute-from-scratch** (QA-507): idempotente ante redelivery at-least-once de Eventarc, que es exactamente por lo que no se usa `FieldValue.increment`. Costo: 4 queries por evento en vez de 2 (2 uids × 2 direcciones). Justificación en ADR-FOLLOW-007.

**Recálculo de los contadores existentes**: con la migración a dos aristas los contadores **cambian de valor** (ADR-FOLLOW-013), así que el backfill deja de ser una reconciliación opcional y pasa a ser un paso obligatorio del plan. Contrato completo, orden de ejecución y verificación en **§7.4**.

### 4.2 `notifyOnFollow`

Las 3 ramas (`request-received` / `auto-followed` / `request-accepted`) y todo el copy quedan **intactos**. Lo único que cambia es de dónde sale la dirección: `requesterId → followerUid`, "el otro" → `followeeUid`. El copy del backend ya está en clave "seguidor" (`notify-friendship.ts:141-145`), así que es la única pieza del sistema que **no necesita adaptarse** — ya estaba escrita para este modelo.

### 4.3 `sweepFollows` (cascade de borrado de cuenta)

Conserva **una sola query** gracias a `members`:

```ts
db.collection("follows").where("members", "array-contains", uid).get()
```

Idéntico a `cascade/friendships.ts:25-28` salvo la colección. Batches de 500 sin cambios. Este es el argumento fuerte a favor de LD-01 (mantener `members`): sin él, el barrido pasa a 2 queries + deduplicación, y el borrado de cuenta es justo donde un doc que se escapa es un problema de compliance, no de UX.

---

## 5. Feed y escalado

### 5.1 Qué cambia semánticamente

| Provider | Hoy | Después |
|---|---|---|
| `myFriendsFeedProvider` | posts de **todos** los accepted (simétrico) | posts de **quienes YO sigo** |
| `visiblePostsByAuthorProvider`, tier `friends` | si existe accepted en cualquier dirección | si **yo sigo** al autor |
| `PublicProfileFollowButton` | 1 doc por par | 2 aristas (saliente + entrante) |

**Qué pasa el día del flip** (reescrito por ADR-FOLLOW-013; invierte lo que decían LD-06 y la versión anterior de ADR-FOLLOW-011):

| Superficie | Efecto de la migración |
|---|---|
| **Feed SEGUIDORES** | **Neutral.** Cada amistad `accepted` migró mutua, así que el conjunto de autores visibles queda idéntico al de hoy, usuario por usuario. Un usuario con 10 relaciones aceptadas sigue viendo posts de 10 autores |
| **Posts tier seguidores (gate de rules)** | **Neutral para lo migrado.** Nadie pierde acceso a lo que ya veía |
| **`followersCount` / `followingCount`** | **Suben.** Es el único cambio visible de la migración — ver §7.4 y ADR-FOLLOW-013 |
| **Follows nuevos, post-flip** | **Asimétricos de verdad.** Seguir crea UNA arista; si el otro no devuelve el follow, no ve mis posts tier seguidores |

La tabla de arriba (`myFriendsFeedProvider` → posts de quienes yo sigo) describe el **código**, y ese cambio es real: el provider pasa a filtrar por dirección. Lo que cambia con la migración a dos aristas es que, sobre el dato migrado, ese filtro devuelve el mismo conjunto que antes. La divergencia empieza a acumularse con la actividad posterior al flip, no de golpe.

### 5.2 `feedForFollowedAuthors` (ex `feedForFriends`)

La forma no cambia: `ceil(N/chunk)` queries en paralelo con `whereIn`, resort client-side. Lo que cambia es que `N` deja de ser "amigos" y pasa a ser "seguidos".

| Seguidos (N) | chunk 10 | chunk 30 |
|---|---|---|
| ≤10 | 1 query | 1 |
| 30 | 3 | **1** |
| 100 | 10 | 4 |
| 300 | 30 | 10 |
| 1000 | 100 | 34 |

El fan-out sigue sin cap superior (R9, preexistente). Dos defectos conocidos que **este change NO arregla y no debe fingir que arregla**:

1. `limit` se aplica **por chunk**, así que se sobre-lee hasta `ceil(N/chunk) × limit` docs y el `hasMore` (`chunkReachedLimit`) es aproximado.
2. No hay tope de `N`. El arreglo real es un feed materializado (fan-out on write), que es otro change entero.

`chunkSize` 10→30 **se desacopla del flip** y se gatea con un test de emulador (ADR-FOLLOW-008). El proposal lo daba por "gratis en este diff"; no lo es, porque triplica la cantidad de documentos `follows` distintos que rules toca en un solo query request y ese presupuesto no está medido.

---

## 6. Capas Dart

Patrón **real** del repo (`domain / data / application / presentation`), no el `view/state/data` de `docs/architecture.md`, que está desactualizado.

### domain — `lib/features/feed/domain/`

- `follow.dart` — freezed `Follow` con los 6 campos de §1.1 + `static String edgeId(String follower, String followee) => '${follower}_$followee';`. Sin `sortedDocId`: **el orden es la información**.
- `follow_status.dart` — enum `pending` / `accepted` con `@JsonValue` + `_wireMap` + `toJson()`, calcado de `friendship_status.dart` y con los mismos literales (LD-02).

### data — `lib/features/feed/data/follow_repository.dart`

| Método | Query / write | Reemplaza a |
|---|---|---|
| `follow(myUid, targetUid, {targetIsPublic})` | `get` + `set` sobre `follows/{me}_{target}` (idempotente) | `request()` |
| `acceptRequest(edgeId, myUid)` | `update status: accepted`, guard `myUid == followeeUid` | `accept()` |
| `deleteEdge(edgeId)` | `delete` — unfollow, cancelar enviada, rechazar recibida | `delete()` |
| `followingOf(uid)` / `watchFollowingOf(uid)` | `followerUid == uid && status == accepted` → `List<String>` de followees | `acceptedFriendsOf()` |
| `watchPendingReceivedFor(uid)` | `followeeUid == uid && status == pending` | `watchPendingRequestsFor()` |
| `pendingReceivedFor(uid)` | idem, future | `pendingRequestsFor()` |
| `allOf(uid)` | `members array-contains uid` | `allOf()` |
| `getEdge(id)` / `watchEdge(id)` | doc get/snapshot | `getByPair()` / `watchByPair()` |

Dos cosas para notar:

- `watchPendingReceivedFor` **elimina el post-filtrado en memoria**. Hoy `watchPendingRequestsFor` trae todos los pending del par y descarta `f.requesterId == uid` en el cliente (`friendship_repository.dart:127`). Con arista dirigida el filtro es del servidor: menos datos en el cable y una regla de negocio menos duplicada en Dart.
- **No se implementa `followersOf` / `watchFollowersOf`** en este change: no tiene ningún consumidor (el perfil público lee `followersCount` del doc de perfil, mantenido por la CF). Entra en `follow-lists`. Bajo Strict TDD, un método sin consumidor es código muerto con test ceremonial (ADR-FOLLOW-009).

### application — `lib/features/feed/application/follow_providers.dart`

```dart
final followRepositoryProvider = Provider<FollowRepository>(...);

/// Key = el doc id de la arista. String, nunca record ni List.
final followEdgeProvider =
    StreamProvider.family.autoDispose<Follow?, String>((ref, edgeId) => ...);

final followingProvider =
    StreamProvider.family.autoDispose<List<String>, String>(...);

final pendingReceivedStreamProvider =
    StreamProvider.family.autoDispose<List<Follow>, String>(...);

final pendingRequestCountProvider =
    Provider.family.autoDispose<int, String>(...);   // sin cambios de forma
```

`followEdgeProvider` reemplaza a `friendshipByPairProvider`, que hoy usa un **record** `({String viewerUid, String targetUid})` como key (`public_profile_providers.dart:13`). Los records tienen igualdad estructural, así que no rompía el cache — pero la key natural ahora **es** el doc id, y usarla como `String` alinea con la convención del repo sin costo.

### presentation

`PublicProfileView` cambia el campo `friendship` por **dos**:

```dart
final Follow? outgoingFollow;  // follows/{viewerUid}_{targetUid}  → yo lo sigo
final Follow? incomingFollow;  // follows/{targetUid}_{viewerUid}  → él me sigue
```

`PublicProfileViewNotifier` pasa de 1 a 2 listeners de documento sobre la misma pantalla (barato: dos `get` por doc id, sin queries ni índices). Es el precio inevitable de la asimetría: los 4 estados del botón hoy caben en un doc porque el doc es el par.

Mapa de estados de `PublicProfileFollowButton`:

| Estado | Condición | `onTap` |
|---|---|---|
| `SEGUIR` | `outgoing == null` | `follow(...)` |
| `SIGUIENDO` | `outgoing.status == accepted` | `UnfriendConfirmationSheet` → `deleteEdge(outgoing.id)` |
| `SOLICITUD ENVIADA` | `outgoing.status == pending` | **`UnfriendConfirmationSheet` (copy cancelar) → `deleteEdge(outgoing.id)`** ← tapa el `onTap: null` de la línea 89 |
| `ACEPTAR` | `outgoing == null && incoming.status == pending` | `acceptRequest(incoming.id, viewerUid)` |

Precedencia: la arista **saliente** manda. Si yo lo sigo y él me mandó solicitud, el botón muestra mi estado saliente; la solicitud entrante se resuelve desde el inbox. Sin esta regla los dos estados compiten por el mismo pill.

Además, obligatorio por AGENTS.md en el mismo archivo: `GestureDetector` → `TreinoTappable` (línea 283), y las strings hardcodeadas de `UnfriendConfirmationSheet` (líneas 55, 69, 79) pasan a los 3 ARBs con `flutter gen-l10n` explícito.

#### 6.1 Superficies que arrastra el chat direccional (§3.3)

Una regla que puede denegar el envío **tiene que decírselo al usuario antes de que apriete enviar**. Un `permission-denied` crudo sobre un chat que se ve normal es la peor forma de comunicar una decisión de producto. Dos superficies, las dos con espejo exacto de la regla del servidor:

**a) Botón MENSAJE del perfil público** (`public_profile_screen.dart:245-246`). Hoy `_isAcceptedFriend` mira **un** doc (`friendship?.status == accepted`) y habilita a los dos. Pasa a mirar **la arista entrante**:

```dart
bool get _chatEligible => widget.incomingFollow?.status == FollowStatus.accepted;
```

Es el espejo literal de `chatCreateOk`: puedo abrirle chat a alguien **sólo si esa persona me sigue**. No es el OR de las dos direcciones — ese era el espejo de la regla vieja. La rama `trainer_link` no entra acá: los chats de Coach se abren desde el hub (`alumno_detail_screen.dart`), no desde el perfil público.

**b) Composer del chat 1-1** (`chat_screen.dart`, widget `_Composer`). El archivo ya tiene el mecanismo: `_Composer` recibe `enabled: !sending` (línea 445) y ya observa al otro usuario (`userPublicProfileProvider(widget.otherUid)`, línea 178). Se suma una condición:

```
canWrite = followEdgeProvider('{otherUid}_{myUid}')  // la arista ENTRANTE
             ?.status == accepted
```

Comportamiento definido (el copy final se resuelve en el slice de l10n, acá se fija la conducta):

| Elemento | Estado cuando `canWrite == false` |
|---|---|
| `TextField` del composer | **deshabilitado** (`enabled: false`), sin foco ni teclado |
| Botón de adjuntar (foto/video) | **deshabilitado** — si no se puede mandar texto, tampoco media |
| Botón de enviar | **deshabilitado** |
| En lugar del composer | **aviso inline persistente**, no un snackbar: el estado es permanente hasta que la otra persona vuelva a seguir, y un toast que se va no comunica algo permanente. Explica **por qué** no se puede escribir, no sólo que no se puede |
| Historial de mensajes | **intacto y scrolleable** (§3.3.4: la lectura no se toca) |
| `lastRead` / badge de no leídos | **sigue funcionando** (§3.3.4) |

Regla de consistencia, no negociable: **el cliente y las rules se mueven juntos**. Si el gate del servidor cambia, estas dos superficies cambian en el mismo slice, o el UX miente en una dirección u otra — habilitando un composer que el servidor va a rechazar, o deshabilitando uno que el servidor aceptaría.

**Estado transitorio aceptado**: entre el deploy de rules (M-07) y la instalación de la build con esta UI, un usuario en un chat sin arista entrante ve el composer habilitado y recibe un error al enviar. La build de M-06b se corta de la punta de la cadena, así que **contiene esta UI** (§7.5) y la ventana es la de instalación, no la de la cadena de PRs.

**Fuera de límites**: `session_notifier` y demás archivos grandes no se tocan. Este change no entra ahí y no hay razón para que entre. El pane de chat del Coach (`chat_detail_pane.dart`) tampoco: sus chats van por la rama `linkId`, que queda igual que hoy.

---

## 7. Coexistencia, migración y criterio de corte

> 🚨 **Todo lo que esta sección describe corre contra PRODUCCIÓN.** `treino-dev`
> es el único proyecto Firebase de TREINO: ahí viven los usuarios reales, y el
> nombre "dev" es exactamente lo que engaña. Los `--apply` escriben por Admin SDK
> —que **saltea las Firestore rules**, incluido el freeze de M-03b— y los
> `firebase deploy` cambian la app publicada al instante. Esto es el **contrato**
> de los scripts, no el runbook: los pasos ejecutables, con marca por línea, están
> en [`tasks.md`](./tasks.md). Ver [openspec/AGENTS.md](../../AGENTS.md) ·
> [#826](https://github.com/Backhaus7997/treino/issues/826).

LD-03 ya cerró: **coexistencia sí, dual-write no**. `friendships` se congela (deny-all-writes) y **no se borra**. Lo que el design agrega es el criterio de corte explícito, el contrato exacto de los dos scripts, el orden del recálculo de contadores y **el momento exacto del freeze** — porque "cuando esté verificado" no es un criterio, y porque congelar tarde abre un agujero de privacidad (ADR-FOLLOW-015).

### 7.0 El freeze de `friendships` se adelanta a **antes** de M-04

**Enmienda al proposal y a la versión anterior de este design.** El freeze dejaba de ser parte de M-07 (flip de rules) y pasa a ser un hito propio, **M-03b**, deployado **inmediatamente antes** de M-04. La secuencia operativa queda:

```
M-03 (rules aditivas)  →  M-02 (dry-run)  →  M-03b (FREEZE de friendships)
   →  M-04 (--apply)  →  M-05 (backfill)  →  M-06 (verify --cutover)
   →  M-06b (TestFlight + confirmación)  →  M-07 (flip direccional de rules)
   →  M-09 (sweep, ahora read-only)  →  M-08 (CFs + release de cliente)
   →  M-08b (backfill + V6b post-repunte, OBLIGATORIO)
```

**M-09 va entre M-07 y M-08, y ése es su único lugar posible.** No es una preferencia de secuencia: es la "ventana muda" (§7.2). Ahí las rules ya flipearon pero las CFs **todavía escuchan `friendships`**, así que si el sweep tuviera que escribir algo, no emite ni un evento. Corrido después del repunte de CFs, cada arista que escriba dispara `notifyOnFollow` —push *"empezó a seguirte"* a testers reales por relaciones de hace meses— y `maintainFollowCounters` en carrera con el backfill. Deshabilitar `notifyOnFollow` a mano antes de correrlo **mitiga** esa falla; ponerlo en la ventana muda la **elimina**, sin paso manual que se pueda olvidar y sin estado de CF que alguien pueda rehabilitar en el medio.

Justificación completa en **ADR-FOLLOW-015**. En una línea: con el freeze en M-07 había una ventana de días (la cadena de PRs es larga por diseño) en la que una build vieja podía **borrar** una amistad ya migrada, y el delta sweep — que solo crea aristas — no absorbe borrados. Las dos aristas sobrevivían al unfollow: phantom access, la falla que LD-04 declara la peor posible. Adelantar el freeze cierra la ventana de raíz en vez de agregarle un paso de reconciliación al script.

Consecuencia de scope: **el bloque de freeze de rules y su test se mueven de PR3a a PR2** (REQ-FOLLOW-017), y M-07 queda conteniendo **solo** el flip direccional del gate.

### 7.1 Compuerta de cutover

Se flipea sólo si las 6 son verdaderas:

1. **M-00**: `.count()` sobre `friendships` registrado, y el conjunto de uids ⊆ equipo. **El dueño confirmó este universo el 2026-08-04** (equipo + testers conocidos); el paso sigue corriendo igual, porque el número real —no la confirmación— es la evidencia que cierra la condición. Si el conteo real contradijera la confirmación → ADR-FOLLOW-010, rama B.
2. **M-06** exit code 0: las 6 invariantes de §7.3 (cardinalidad `2·accepted + pending`, cobertura doc-a-doc en **ambas** direcciones con `createdAt`, dirección única para pending, cero aristas inventadas, forma del doc, y triple igualdad de contadores).
3. **M-05 corrido y verificado**: los contadores almacenados son los recalculados sobre `follows` (§7.4). Sin esto, la invariante V6b de M-06 falla por construcción.
4. `follows-rules.test.ts` verde en el job `functions-test` de CI (LD-09, bloqueante).
5. `post-privacy-rules.test.ts` reescrito y verde, **incluyendo el caso negativo**: "lo sigo pero él no me sigue → él NO lee mis posts tier followers". Y `chat-relationship-rules.test.ts` verde sobre **las dos** superficies del chat direccional (`chats/create` y `messages/create`, ADR-FOLLOW-005), incluyendo el caso asimétrico dentro del mismo chat: uno escribe, el otro no.
6. **M-03b deployado**: `friendships` está en `create/update/delete: if false`. El freeze es precondición de M-04, no consecuencia de M-07.

Y, por decisión del dueño, el paso de rollout **M-06b** de §7.5 (build nueva en TestFlight + aviso a testers) ejecutado antes de M-07.

#### 7.1.1 La compuerta vence

**El exit 0 de M-06 es una foto, no un certificado.** Se toma al final de PR2 y autoriza un deploy (M-07) que ocurre varios PRs después, en la cadena encadenada. Entre una cosa y la otra pasan días y hay al menos dos escritores que no pasan por rules: el cascade de borrado de cuenta (§7.1.2) y cualquier operación admin manual.

**Regla de vencimiento, explícita:** la condición 2 se considera cumplida sólo si el exit 0 tiene **menos de 7 días** *y* no hubo ninguna actividad conocida sobre `follows`, `friendships` o `userPublicProfiles` desde entonces. Si alguna de las dos falla, se **re-verifica** inmediatamente antes del deploy de M-07, en el modo que corresponda (abajo), más `backfill --dry-run`, que debe reportar 0 perfiles fuera de sync. Es una lectura de tres colecciones a volumen de equipo: segundos. No hay ninguna razón para no re-correrla, y sí una para hacerla obligatoria — es la única red que atrapa el residuo de §7.1.2.

**Por qué 7 días y actividad, y no 24 h.** Los dos disparadores no son intercambiables: uno mide riesgo real y el otro mide reloj. Con `friendships` congelada desde M-03b (§7.0) el origen está **inmóvil**, así que el paso del tiempo por sí solo no degrada nada — lo que degrada la foto es que **alguien escriba**: el cascade de borrado de cuenta vía Admin SDK (§7.1.2), una operación manual, o los clientes ya actualizados de M-06b escribiendo aristas nuevas. El disparador que hay que vigilar es **la actividad**, y está escrito como tal. El plazo es sólo un techo para "no pasó nada y nadie miró": la cadena de PRs dura días **por diseño** (delivery = PRs encadenados, decisión cerrada del dueño), así que un vencimiento de 24 h obligaría a re-verificar en cada slice sin información nueva. Eso no agrega seguridad: **entrena al operador a re-correr por trámite en vez de por causa**, que es exactamente cómo una compuerta deja de ser una compuerta. Un deploy de rules o de CFs que repunte alguna de las tres colecciones cuenta como actividad conocida y dispara la re-verificación por la vía del primer criterio, no del segundo.

#### 7.1.1b En qué modo se re-verifica: `--cutover` deja de ser satisfacible después de distribuir la build

**Esto no es un detalle de flags: mal resuelto, la compuerta queda insatisfacible por construcción.** La re-verificación corre **después** de M-06b (§7.5) — tiene que correr ahí, porque su valor es estar fresca en el momento del deploy, y M-06b es justamente el paso que consume tiempo de reloj (procesado de App Store Connect + instalación de los testers). Pero la build de M-06b se corta de la **punta de la cadena**, así que **contiene PR3c**: ya escribe en `follows` (botón de seguir, inbox de solicitudes). En cuanto un tester sigue a alguien, `follows` **deja de ser 100% producto de la migración**, y `--cutover` —que asume exactamente eso— falla por V1 (cardinalidad), V4 (arista sin friendship de origen) y, si la arista es `accepted`, V6a. **Una corrida de `--cutover` después de distribuir la build está condenada a exit 1 por actividad legítima.**

La compuerta se re-corre entonces en el modo que corresponde al estado de `follows`:

| Estado de `follows` | Instrumento | Qué exige |
|---|---|---|
| **Sigue siendo 100% producto de la migración** (la build todavía no se distribuyó, o se confirmó que nadie escribió) | `verify-follows-migration.ts --cutover` | exit 0, las 6 invariantes |
| **Ya hay aristas nuevas legítimas** (post-distribución de M-06b) | `verify-follows-migration.ts --delta --manifest apply-{ISO}.json` — **el manifiesto de M-04**, el que emite el `--apply` (§7.2 paso 4) | exit 0: **V2/V3/V4 restringidas al manifiesto** (cada arista migrada sigue presente, con su `status`, su `createdAt` y una dirección legal para su origen), **V5 sobre toda la colección**, **V6b**. V1 y V6a **no se evalúan** — ver §7.3.1 |

En los dos casos, además: `migrate-friendships-to-follows.ts --dry-run --since <ISO de M-04>` con `toCreate` vacío, y `backfill-follow-counters.ts --dry-run` con 0 perfiles fuera de sync.

**Por qué el modo relajado sigue siendo una compuerta y no un trámite.** Lo que hay que probar antes del flip no es "`follows` es idéntica a lo que escribió la migración" —eso ya se probó en M-06 y dejó de ser cierto a propósito— sino **"nada de lo que la migración escribió se rompió, y los contadores siguen atados a la realidad"**. Eso es exactamente V2+V3+V4-sobre-manifiesto + V5 + V6b. Lo que se pierde al soltar V1 y V6a son justamente las dos invariantes que **sólo tienen sentido si nadie más escribe**, y el residuo que a esta altura importa —aristas huérfanas por el cascade de §7.1.2, contadores desincronizados— lo siguen atrapando V4 (sobre el manifiesto: la arista migrada perdió su origen) y V6b.

**Alternativas descartadas.** *Correr la re-verificación **antes** de distribuir la build*: no resuelve nada, mueve el problema — la foto vuelve a envejecer durante el paso más lento del rollout y A13 se reabre entero. *Cortar la build de M-06b de un punto de la cadena anterior a PR3c*: destruye el propósito de M-06b — una build sin PR3c sigue escribiendo el grafo social contra `friendships`, que está **congelada desde M-03b**, o sea que el tester actualiza y sigue sin poder seguir a nadie. Sería entregar una build que no arregla lo que la ventana rompió.

#### 7.1.2 Residuo conocido: el cascade de borrado de cuenta saltea el freeze

**Verificado en el código**: `sweepFriendships` (`functions/src/cascade/friendships.ts:25-28`) borra docs de `friendships` con **Admin SDK**, que ignora rules. O sea que el freeze de M-03b congela a los **clientes**, no a las Cloud Functions.

Si se borra una cuenta entre M-03b y M-08 (que es cuando `sweepFriendships` pasa a ser `sweepFollows`), pasan dos cosas: las aristas de esa cuenta en `follows` **sobreviven** al barrido, y el borrado de los `friendships` dispara la CF vieja `maintainFollowCounters`, que recalcula sobre la colección origen y **desincroniza los contadores** de ese par.

No se agrega mecanismo para esto: se lo **detecta**. V4 marca las aristas cuyo friendship de origen desapareció y V6b marca los contadores desincronizados — las dos corren en la re-verificación obligatoria de §7.1.1, antes del flip. La resolución es manual (barrer a mano las aristas de esa uid) y a volumen de equipo es cero o un caso. **Instrucción operativa**: no borrar cuentas entre M-03b y M-08; si pasa igual, la compuerta lo ve.

**Nunca se lee de las dos colecciones a la vez** (LD-04). Con el chat direccional (ADR-FOLLOW-005) **no queda ningún OR entre aristas en todo el diseño**: cada gate mira **una** arista, la que corresponde a la dirección que autoriza. El único OR que sobrevive es entre la rama social y la rama `trainer_link` del chat, que son dos fuentes de relación distintas, no dos direcciones de la misma.

### 7.2 Contrato de `migrate-friendships-to-follows.ts`

**Ubicación**: `functions/scripts/migrate-friendships-to-follows.ts`, con test en `functions/src/__tests__/` (patrón real del repo: `backfill-follow-counters.ts`, no `scripts/migrations/` como decía el proposal).

**Flags**: `--dry-run` (**default**, no escribe nada) · `--apply` · `--since <ISO>` (opcional, solo para el delta sweep M-09).

**Función pura, testeable sin Firestore:**

```ts
type Edge = {
  id: string;            // `${followerUid}_${followeeUid}`
  followerUid: string;
  followeeUid: string;
  status: 'pending' | 'accepted';
  members: [string, string];   // [followerUid, followeeUid]
  createdAt: Timestamp;        // se PRESERVA del friendship de origen
};

type Plan = {
  toCreate:   Edge[];
  skippedPair: { pairId: string; reason: 'already-migrated' }[];
  /** SOLO en corrida inicial (sin --since): par con algunas pero no todas sus
   *  aristas esperadas → se COMPLETA (las faltantes van a toCreate) y se
   *  reporta acá como warning ruidoso. Ver G1. */
  partialPair: { pairId: string; present: string[]; created: string[] }[];
  divergent:  { edgeId: string; expected: Partial<Edge>; actual: Partial<Edge> }[];
  conflicts:  { pairId: string; reason: 'no-edges-and-older-than-since' }[];
  malformed:  { docId: string; reason: string }[];
  stats: { friendships: number; accepted: number; pending: number; expectedEdges: number };
};

export function planMigration(
  friendships: Array<{ id: string; data: FriendshipData }>,
  existing: Map<string, EdgeData>,        // aristas ya presentes en `follows`, por doc id
  opts: { since?: Date },
): Plan;
```

**Expansión — la parte que cambió (ADR-FOLLOW-013):**

```
para cada doc de friendships:
  R = data.requesterId ; M = data.members
  si !R || M.length != 2 || !M.includes(R) || data.status ∉ {pending, accepted}
     → malformed(docId, motivo) ; continue        // NUNCA se adivina la dirección
  O = M.find(m => m !== R)
  si !O                → malformed(docId, 'self-pair')

  si data.status == 'accepted':
     esperado = [ edge(R, O, 'accepted'),
                  edge(O, R, 'accepted') ]        // ← DOS aristas: follow mutuo
  si data.status == 'pending':
     esperado = [ edge(R, O, 'pending') ]         // ← UNA: la solicitud es direccional

  edge(f, t, s) = { id: `${f}_${t}`, followerUid: f, followeeUid: t, status: s,
                    members: [f, t], createdAt: data.createdAt }
```

**Guardas, en este orden (esto es lo que lo hace idempotente y no destructivo):**

| # | Guarda | Efecto |
|---|---|---|
| G1 | **Guarda por par, asimétrica por modo** (se evalúa primero y decide la escritura). **Con `--since`** (delta sweep): si **alguna** de las aristas esperadas del par ya existe, el par entero va a `skippedPair` y **no se escribe nada** — ni siquiera la dirección faltante. **Sin `--since`** (corrida inicial): si están **todas** → `skippedPair`; si están **algunas pero no todas** → las faltantes van a `toCreate` y el par se reporta en `partialPair` | Ver la explicación larga abajo. La asimetría no es un detalle: el mismo estado observado ("falta una dirección") significa **cosas opuestas** antes y después del flip |
| G2 | **Divergencia** (observación, nunca escritura): sobre los pares que G1 salteó, se compara lo que hay contra lo esperado y las diferencias de `status`/`createdAt`/`members` van a `divergent`. **Nunca se pisa nada** | **Sin `--since`** (corrida inicial, nadie tocó `follows` todavía) una divergencia significa corrida anterior interrumpida o corrupta → **error, exit 1**. **Con `--since`** (delta sweep post-flip) es actividad legítima del usuario — una `pending` migrada que el followee ya aceptó — → **warning**, no error |
| G3 | **Conflicto**: par con **cero** aristas y `createdAt` del friendship anterior a `--since` → `conflicts`, no se escribe | Caso "los dos se dejaron de seguir después del flip". Necesita ojo humano, no una escritura ciega. Sin `--since` no aplica (es la corrida inicial: cero aristas es lo normal) |
| G4 | **Malformado**: nunca se escribe, se enumera nominalmente (doc id + motivo) en dry-run **antes** de cualquier `--apply` | LD-06 original ya lo exigía y sigue vigente |

**Por qué G1 tiene que ser asimétrica (corrección: la versión anterior no lo era).** La guarda estaba escrita pensando **sólo** en el delta sweep post-flip, donde "falta una de las dos direcciones de un par accepted" significa **que un usuario dejó de seguir** y recrearla revertiría una decisión de privacidad (ADR-FOLLOW-014). Eso es correcto **con `--since`**. Aplicada tal cual a la corrida inicial significa exactamente lo contrario, y produce un modo de falla silencioso:

> M-04 escribe en batches de 400. Un batch commitea `follows/A_B` y el proceso muere antes de `follows/B_A`. Se reintenta: G1 ve una arista → el par entero va a `already-migrated`; G2 no dispara (no hay divergencia: lo que está, está bien); `skippedPair` es warning → **exit 0**. El script reporta "plan sano" con la migración a medias.

Con el reintento en exit 0, la única red que queda es M-06 (V1/V2/V6a lo atrapan), pero para entonces ya se perdió la señal de qué pasó y el operador cree que el script terminó bien. Peor: la versión anterior de este documento presentaba ese comportamiento como **la prueba de idempotencia**, cuando es el modo de falla.

**Decisión: sin `--since` se completa la dirección faltante.** No es adivinar — es la propiedad que hace legítimo completar: en la corrida inicial `follows` es 100% producto de la migración y el conjunto de aristas esperadas del par está **totalmente determinado** por el friendship de origen. Además, el cliente que escribe `follows` (PR3c) todavía no está publicado, así que una dirección faltante **no puede** ser un unfollow: no existe todavía la vía para producirlo. El par se reporta en `partialPair` como warning ruidoso — el operador tiene que enterarse de que hubo una corrida interrumpida, aunque el script la resuelva.

**Qué NO cambia.** Un par con **todas** sus aristas presentes sigue yendo a `skippedPair` sin escribir nada. Por eso la propiedad de idempotencia real se conserva: segunda corrida sobre un estado **completo** → `toCreate == []`, 0 writes, exit 0.

**Por qué G1 va primero y G2 no escribe.** Son la misma decisión mirada de dos lados: si el par ya está en `follows` **y completo**, el estado de `follows` es **más nuevo** que el de `friendships` (congelada desde M-03b), así que el origen deja de ser autoridad para ese par. G2 existe para **reportar**, no para reconciliar: reconciliar sería devolverle autoridad a la colección congelada, que es justo lo que un cutover no debe hacer. Completar una dirección faltante en la corrida inicial no es reconciliar: no hay dos versiones del hecho compitiendo, hay una escritura que no llegó a ocurrir.

**Escritura (`--apply`)**

1. Leer las aristas esperadas por **doc id** con `getAll()` en chunks de 300 — lectura directa, sin queries ni índices.
2. Escribir solo `toCreate`, en batches de **400** (bajo el cap de 500), usando **`batch.create()`, no `set()`**: si la arista apareció entre el read y el write, la operación falla ruidosa en vez de pisar. Ante `ALREADY_EXISTS`, ese batch se re-planifica doc a doc y los ya presentes pasan a `skippedPair`.
3. Nunca toca `friendships` (ni un campo de marcado): la colección origen queda byte-idéntica, que es la precondición 1 del rollback (ADR-FOLLOW-012).
4. Volcar el **manifiesto** de lo efectivamente escrito a `functions/scripts/migrations/apply-{ISO}.json` (o `delta-{ISO}.json` si hubo `--since`): ids creados, pares salteados, divergentes, conflictos y malformados. Es el insumo obligatorio del modo `--delta` de la verificación (§7.3.1) y la evidencia que se adjunta al reporte de apply.

**Idempotencia — por qué correrlo dos veces no puede duplicar nada:**

- **Doc id determinístico**: el id se deriva de `(follower, followee)`. No hay ids autogenerados en ningún camino del script, así que "duplicar" es estructuralmente imposible: la segunda escritura apunta al mismo documento.
- **Prohibición de pisar** (G1+G2+`create()`): la segunda corrida **sobre un estado completo** produce `toCreate == []`, **0 writes**, exit 0.
- **Reanudabilidad ≠ idempotencia**, y las dos hacen falta. Sobre un estado **parcial** (corrida inicial interrumpida) la segunda corrida sí escribe: escribe **exactamente** las aristas que faltaban, ni una más. Es un no-op sólo cuando ya no hay nada que hacer, que es la definición útil. Sin esto, un batch a medias deja la migración incompleta reportando éxito (ver G1).
- Corolario: una re-migración después de un rollback de PR2 (borrar `follows` y volver a correr) produce **exactamente el mismo estado**, porque `createdAt` sale del origen y no del reloj del script.

**Exit codes**: `0` plan sano — aplicado o simulado; `malformed`, `skippedPair`, `partialPair` y (solo con `--since`) `divergent` son **warnings**, no error · `1` hay `conflicts`, o `divergent` en una corrida **sin** `--since` → requiere decisión humana, no se avanza a M-06 · `2` error de ejecución (credenciales, colección inaccesible).

**Restricción de orden — "regla de la ventana muda", aplica a TODA escritura administrativa sobre `follows`:**

> Ningún `--apply` de este script corre mientras `maintainFollowCounters` y `notifyOnFollow` estén repuntadas a `follows`. Ambas son `onDocumentWritten` sobre el path de la colección (`maintain-follow-counters.ts:208-210`, `notify-friendship.ts:210-212`), así que **cada arista que el script escriba es un evento**.

Lo que eso cuesta si se viola, dicho con nombre y apellido:

- **Push reales sobre relaciones viejas.** `notifyOnFollow` tiene una rama `auto-followed` que emite *"X empezó a seguirte"* (`notify-friendship.ts:142-143`). Un sweep que escriba aristas con las CFs ya repuntadas manda esa notificación a testers reales por amistades de hace meses.
- **Carrera con el backfill.** Cada write dispara `maintainFollowCounters` (4 queries + transacción) justo cuando el backfill está fijando esos mismos contadores.

Cómo se cumple, concretamente:

| Escritura admin | Cuándo corre | Por qué es muda |
|---|---|---|
| **M-04** (migración inicial) | En PR2, mucho antes de PR3a | Las CFs siguen apuntando a `friendships`. Escribir en `follows` no emite **ningún** evento |
| **M-09** (delta sweep) | En PR3a, **entre M-07 (deploy de rules) y el deploy de las CFs**, no en PR3d | Misma razón: en esa ventana las rules ya flipearon pero las CFs todavía escuchan `friendships`. Es el único punto del plan donde el sweep puede escribir sin efectos colaterales |

Los contadores posteriores a cualquiera de las dos escrituras los fija el **backfill** de §7.4, que escribe `userPublicProfiles` directo y no tiene ninguna CF encima. Nunca la CF.

Con el freeze adelantado a M-03b (§7.0), M-09 además pasa a ser **read-only por expectativa**: no debería tener nada que absorber. El detalle está en §7.3.1.

### 7.3 Contrato de `verify-follows-migration.ts`

**Solo lectura. Sin flag de escritura, ni siquiera de reparación**: si falla, se borra `follows` y se vuelve a M-02. Parchear a mano una migración es cómo se pierde la trazabilidad.

**Fuentes**: `friendships` completa · `follows` completa · `userPublicProfiles` (solo `followersCount`/`followingCount`).

**Derivados** (el predicado de "bien formado" se **importa** de `migrate-friendships-to-follows.ts`, no se reimplementa — si divergen, la verificación deja de verificar):

```
WF   = friendships bien formadas          MF = malformadas
A    = |WF con status accepted|           P  = |WF con status pending|
deg(uid) = # de friendships accepted bien formadas que contienen a uid
```

**Invariantes.** Se evalúan **todas** (no corta en la primera): el reporte enumera cada violación con su conteo y hasta 20 ids ofensores por clase.

| # | Invariante | Condición exacta |
|---|---|---|
| **V1** | Cardinalidad | `count(follows) == 2*A + P`, con `A` y `P` contadas **sólo sobre `WF`** (bien formadas) |
| **V2** | Cobertura de `accepted` | para cada accepted `{X,Y}`: existen **ambas** `follows/{X}_{Y}` y `follows/{Y}_{X}`, las dos con `status == 'accepted'` y con el `createdAt` del friendship de origen |
| **V3** | Cobertura y unicidad de `pending` | para cada pending (requester `R`, otro `O`): existe `follows/{R}_{O}` con `status == 'pending'` y el `createdAt` de origen, **y NO existe** `follows/{O}_{R}` |
| **V4** | Sin invención | para **cada** arista de `follows`: `sorted(followerUid, followeeUid)` corresponde a un doc **bien formado** de `friendships`, con el mismo `status`, y la dirección es **legal para ese origen** (accepted → ambas; pending → solo la del requester) |
| **V5** | Forma del doc | `id == docId` · `followerUid != followeeUid` · `members == [followerUid, followeeUid]` · `keys == {id, followerUid, followeeUid, status, members, createdAt}` · `status ∈ {pending, accepted}` |
| **V6** | Contadores (reemplaza al viejo M-06 ④) | `V6a`: para todo uid en alguna WF, `followingRecalc(uid) == followersRecalc(uid) == deg(uid)`<br>`V6b`: `userPublicProfiles/{uid}.followingCount == followingRecalc(uid)` y `.followersCount == followersRecalc(uid)` |

con `followingRecalc(uid) = |follows: followerUid==uid && accepted|` y `followersRecalc(uid) = |follows: followeeUid==uid && accepted|` — **exactamente las dos queries de la CF y del backfill** (ADR-FOLLOW-007), así que las tres implementaciones no pueden divergir.

**Nota sobre V1: los malformados se EXCLUYEN del universo, no se restan del resultado.** La forma `2·accepted + pending − malformados` es aritméticamente falsa y no debe aparecer en ningún lado. Desarrollando con `A = A_wf + A_mf` y `P = P_wf + P_mf`:

```
2A + P − (A_mf + P_mf)  =  2·A_wf + P_wf + A_mf      ← sobra A_mf
```

Sobre-cuenta **una arista por cada `accepted` malformada**. Y una malformada por `status` inválido no está ni en `count(accepted)` ni en `count(pending)`, pero igual se restaría: sub-cuenta. Las dos direcciones del error existen simultáneamente y se cancelan parcialmente, que es lo peor posible — la fórmula puede dar bien por casualidad. La definición correcta es la de arriba: `A` y `P` se cuentan sobre `WF` y `MF` ni entra en la ecuación.

**Correspondencia con las 5 condiciones de M-06 del proposal** (mismos chequeos, acá con los detalles de implementación):

| M-06 (proposal) | Invariante (design) |
|---|---|
| ① conteo `2 × accepted + pending`, sobre **bien formadas** | **V1** |
| ② ambas direcciones por cada `accepted`, mismo `createdAt` | **V2** |
| ③ exactamente una por `pending`, dirección `requesterId`, inversa ausente | **V3** |
| ④ `followersCount == followingCount == accepted` por usuario | **V6a** (+ **V6b**, que además ata el valor **almacenado** al recalculado) |
| ⑤ ninguna arista sin friendship de origen | **V4** |
| — | **V5** (forma del doc: `id`, `members`, allowlist de keys, no-self). El design agrega este chequeo: es gratis en la misma pasada y atrapa un `members` mal derivado, que ninguna de las otras 5 ve |

**Por qué V6a es el reemplazo legítimo del viejo ④.** El chequeo anterior era "los contadores no se mueven ni en uno", y con dos aristas se cae porque los contadores **sí** se mueven. V6a captura la misma propiedad por otro lado y es **más fuerte**: bajo follow mutuo, `followers` y `following` de cada usuario tienen que ser iguales entre sí **y** iguales al grado de amistades aceptadas. Si falta una sola de las dos direcciones de un par, `followingRecalc(Y)` cae 1 por debajo de `deg(Y)` **y** `followersRecalc(X)` cae 1 por debajo de `deg(X)`: dos violaciones por una arista faltante. El viejo ④ comparaba un agregado contra un valor almacenado; V6 compara **tres** fuentes independientes (almacenado, recalculado, derivado del origen).

**Cobertura por clase de falla** — ninguna clase depende de una sola invariante:

| Falla inyectada | Atrapada por |
|---|---|
| Falta una de las dos aristas de un `accepted` | V1, V2, V6a |
| Faltan las dos | V1, V2, V6a |
| `accepted` migrado a UNA sola arista (el criterio viejo de LD-06) | V1, V2, V6a — en toda la base |
| Dirección de un `pending` invertida | V3, V4 (los contadores **no** la ven: pending no cuenta) |
| Arista inventada, sin friendship de origen | V1, V4 |
| Arista "duplicada" | Estructuralmente imposible (doc id determinístico). Si apareciera con otro id → V4 + V5 |
| `status` alterado durante la migración | V2/V3, V4, y V6a si era `accepted` |
| `createdAt` perdido o reemplazado por `now()` | V2/V3 |
| `members` mal derivado o con orden invertido | V5 |
| Contadores no recalculados, o recálculo a medias | V6b |
| Arista sobre un friendship **malformado** (se adivinó una dirección) | V4 |

**Warnings que NO hacen fallar**: uid con aristas pero sin doc en `userPublicProfiles` (misma política que la CF y el backfill: no se resucita el perfil de una cuenta borrada) y los `MF` enumerados. Se imprimen en una sección aparte del reporte.

#### 7.3.1 Alcance: modo `--cutover` (M-06) vs modo `--delta` (M-09)

Las 6 invariantes de arriba asumen algo que **solo es cierto en M-06**: que `follows` es 100% producto de la migración y que `friendships` es la autoridad. En **M-09**, después del flip, eso ya no vale — hay follows creados por la app (sin friendship de origen, y asimétricos a propósito) y hay aristas migradas que el usuario aceptó o borró. Correr V1–V6 tal cual en M-09 marcaría como error **toda la actividad legítima**. Por eso el script tiene dos modos explícitos y el default es el estricto.

| Invariante | `--cutover` (M-06, default) | `--delta --manifest <file>` |
|---|---|---|
| **V1** cardinalidad | `count(follows) == 2A + P`, exacta | **No se evalúa.** Ver la nota de abajo |
| **V2 / V3** cobertura y dirección | Sobre **todos** los friendships | Restringidas a los pares **del manifiesto**, con dos y sólo dos desviaciones toleradas como **warning** — desarrollo debajo de la tabla —; todo lo demás sigue siendo **error** |
| **V4** sin invención | Sobre **toda** la colección | Restringida al manifiesto: una arista nueva sin friendship de origen es un follow legítimo post-flip, no una invención. Lo que sí atrapa: una arista **del manifiesto** que perdió su origen |
| **V5** forma del doc | Sobre toda la colección | **Igual: sobre toda la colección.** Es la única invariante independiente del origen, y por eso es la que sigue teniendo valor cuando las demás se relajan |
| **V6** contadores | `V6a` + `V6b` completas | **Solo `V6b`** (almacenado == recalculado sobre `follows`). `V6a` (`following == followers == deg`) deja de valer: los follows post-flip son asimétricos, que es exactamente el punto del change |

**Qué mutaciones son legítimas sobre una arista del manifiesto en la ventana 3a.19b → 3a.19c, y cuáles no — no es una lista arbitraria, la traza la propia regla de escritura.** El problema que resuelve esta sección: entre distribuir la build (3a.19b) y re-verificar (3a.19c), `follows/{followId}` ya tiene sus rules de escritura activas desde M-03 (PR1), así que un tester puede tocar cualquier arista migrada — un unfollow legítimo o un accept de una pending migrada bastan para que V2/V3, tal como estaban definidas para el caso general, marquen error. Es la misma clase de falla que esta corrección (ADR-FOLLOW-013/015) vino a eliminar, sólo que más chica: la compuerta pasó de ser insatisfacible por cualquier follow nuevo a insatisfacible por cualquier unfollow o accept.

La solución no es relajar V2/V3 a ojo: es notar que **qué puede tocarle un tester a una arista existente no es libre** — lo fija el bloque de rules de §3.1, la única vía de escritura legítima sobre el documento: `delete` (cualquiera de los dos miembros) o `update` restringido a `pending → accepted`, con `followerUid`/`followeeUid`/`members`/`createdAt` pineados y la allowlist de 6 keys cerrada. No hay una tercera vía. Por construcción, entonces, una arista del manifiesto en esa ventana sólo puede terminar en uno de tres estados:

1. **Igual que la escribió la migración** — nadie la tocó.
2. **Ausente** — alguien la borró: unfollow si el origen era `accepted`, cancelar o rechazar si era `pending`. **Warning**, no error.
3. **Presente, con `pending → accepted` y todo lo demás intacto** — el followee aceptó una solicitud migrada. **Warning**, no error, y sólo aplica a aristas que migraron `pending`: una arista que migró `accepted` no tiene a dónde transicionar, porque las rules no permiten revertir `accepted` a nada.

Cualquier otro estado observado —`createdAt` distinto en una arista que sigue presente, una arista `accepted` cuyo `status` ya no es `accepted`, cualquier combinación que no sea (2) o (3)— es **estructuralmente inalcanzable** para un cliente sujeto a rules. Si aparece, no es actividad de usuario: es un bypass de Admin SDK (§7.1.2) o un bug, y **V2/V3 lo siguen marcando error, sin excepción**.

Esto es también por qué se descarta la alternativa de resolver esto con "revisión manual en 3a.19c a criterio del operador": no hace falta criterio humano para separar actividad legítima de corrupción, porque las rules ya trazan la línea entera. Automatizarla es más confiable que pedirle a alguien, en medio de una ventana de release, que mire un diff de aristas y decida a ojo — y es exactamente el tipo de paso manual sin red que el resto de este design evita a propósito (§7.2, "regla de la ventana muda"; §7.0, freeze adelantado).

**El manifiesto es la salida de cualquier `--apply` cuya escritura se quiera verificar** — `apply-{ISO}.json` para M-04, `delta-{ISO}.json` para el sweep de M-09 (§7.2 paso 4). El modo `--delta` es "verificación **relativa a un manifiesto**", no "verificación del sweep": el mismo instrumento sirve para re-verificar la migración inicial cuando `follows` ya recibió actividad legítima de clientes (§7.1.1b). Sin manifiesto, `--delta` **no corre** (exit 2): no hay forma de distinguir una arista nueva legítima de una inventada, y adivinarlo sería exactamente lo que el resto del plan prohíbe.

**Por qué V1 se cae entera en `--delta`, y no se reemplaza por una versión débil.** La versión anterior de esta tabla definía `V1-delta` como `count(follows) == count(antes de la corrida) + |toCreate|`. Esa igualdad sólo se sostiene si **el script es el único escritor** entre las dos mediciones, y desde M-06b eso es falso por diseño: hay clientes actualizados escribiendo aristas. Peor, es falso incluso para el propio M-09, que corre después de distribuir la build. Una invariante que puede fallar por actividad legítima **no es una invariante, es ruido que enseña a ignorar el reporte**. Lo que V1 aportaba —"el `--apply` escribió exactamente lo que planificó"— ya lo cubren dos cosas más precisas: el propio `--apply`, que re-planifica doc a doc ante `ALREADY_EXISTS` y emite el manifiesto de lo efectivamente escrito, y **V2/V3 sobre ese manifiesto**, que verifican que todo lo listado está y está bien. La cardinalidad global deja de ser función del origen apenas hay un cliente escribiendo; se la suelta explícitamente en vez de fingir que se la mide.

**M-09 degrada a aserción, y eso no es un detalle de ejecución: es lo que cierra el agujero de los borrados.** El delta sweep existía para absorber escrituras sobre `friendships` ocurridas entre M-04 y el freeze. Con el freeze adelantado a **M-03b** (§7.0) esa ventana es vacía por construcción, así que:

- M-09 corre en **`--dry-run`** y su resultado esperado es `toCreate == []`. Eso es la aserción: *nadie escribió en `friendships` después del freeze*.
- Si `toCreate` **no** es vacío, alguien escribió salteando rules — en la práctica, `sweepFriendships` con Admin SDK (§7.1.2) o una operación manual. **No se aplica reflejamente**: primero se entiende qué pasó, y si corresponde aplicar, se aplica **dentro de la ventana muda** (§7.2), o sea antes del deploy de las CFs repuntadas. Sólo en ese caso se emite manifiesto y corre `--delta`.
- Con `toCreate == []` no hay manifiesto ni hace falta `--delta`: no se escribió nada que verificar. La verificación relevante en ese punto es la re-corrida **en el modo que corresponda al estado de `follows`** (§7.1.1b): `--cutover` si `follows` sigue siendo 100% producto de la migración, o `--delta --manifest apply-{ISO}.json` si la build de 3a.19b ya se distribuyó — no `--cutover` a secas, que es insatisfacible por construcción apenas hay un tester escribiendo.

**Por qué esto es mejor que reconciliar borrados dentro del script.** La alternativa era hacer que el sweep detectara pares presentes en `follows` y ausentes en `friendships`, contrastándolos contra el snapshot de M-01 para distinguir "borrado durante la ventana" de "follow nuevo post-flip". Eso es lógica nueva, con estado externo, para resolver un caso que el orden de ejecución elimina. **Un problema que se puede borrar del calendario no se resuelve con código** (ADR-FOLLOW-015). El precio es una ventana de escritura social caída para builds viejas, y está contabilizado en §7.5 y en el riesgo A11.

**Exit codes**: `0` todas las invariantes del modo verdes (warnings permitidos) · `1` ≥1 invariante violada · `2` error de ejecución (incluye `--delta` sin manifiesto).

**Costo**: 3 lecturas completas de colección. A volumen de equipo (M-00), segundos. **No hay muestreo**: es exhaustivo por diseño, igual que el chequeo que reemplaza.

### 7.4 Recálculo de contadores (M-05, ahora obligatorio)

**Los contadores cambian de valor, y eso es correcto.** Hoy `countAcceptedFor` (`maintain-follow-counters.ts:127-152`) parte los `accepted` por `requesterId == uid`, así que siempre vale:

```
ANTES:    followersCount(u) + followingCount(u) == #amistades accepted de u
DESPUÉS:  followersCount(u) == followingCount(u) == #amistades accepted de u
```

Los dos números suben. **No es un bug**: el split por `requesterId` mostraba "siguiendo 1, seguidores 0" para una relación que en los hechos era mutua — los dos se veían los posts. El número nuevo cuenta lo que realmente pasa. Es el **único** cambio visible de la migración (§5.1) y tiene que estar anunciado (ADR-FOLLOW-013).

**Herramienta**: se reusa `functions/scripts/backfill-follow-counters.ts` con dos cambios acotados.

| Qué | Antes | Después |
|---|---|---|
| Lectura | `friendships where status == 'accepted'` | `follows where status == 'accepted'` |
| Agregador puro | `tallyFollowCounters(friendships)` — parte por `requesterId`, valida `members` | `tallyFollowCountersFromEdges(edges)` — `followerUid` → `following`, `followeeUid` → `followers`. Sin split en memoria, sin tocar `members` (ADR-FOLLOW-007) |

Se conserva **tal cual**: `--dry-run` por defecto, recompute-from-scratch (no `increment`), escribe solo perfiles cuyos valores difieren, batches de 400, y la política de no crear perfiles faltantes.

**Orden exacto, no negociable:**

```
M-03b (freeze)  →  M-04 (migración --apply)  →  M-05 (backfill --dry-run, después --apply)  →  M-06 (verificación)
```

El backfill va **antes** de la verificación porque V6b compara contra lo almacenado; corrido después, V6b falla siempre en la primera pasada.

**Por qué el freeze tiene que estar antes de M-05, y no sólo antes de M-04.** `maintainFollowCounters` es `onDocumentWritten` sobre `friendships/{friendshipId}` y `countAcceptedFor` lee `friendships` (`maintain-follow-counters.ts:138, 208-210`). Esa CF sigue viva hasta el deploy de M-08. Con el freeze tarde, **cualquier** amistad creada, aceptada o borrada por una build viva después de M-05 disparaba la CF vieja, que recomputaba con el split por `requesterId` y **devolvía a ese par a los valores viejos** — pisando en silencio lo que el backfill acababa de escribir, varios PRs antes de que alguien volviera a mirar. V6b ya había pasado; la condición 3 de la compuerta (§7.1) quedaba falsa al momento del flip para cualquier usuario con actividad.

Con el freeze en M-03b eso queda **estructuralmente cerrado**: la CF vieja no puede volver a dispararse porque su colección no acepta más escrituras de cliente. Queda el residuo del cascade con Admin SDK (§7.1.2), y por eso la red no es opcional:

> **Re-verificación obligatoria antes de M-07** (§7.1.1): `backfill-follow-counters.ts --dry-run` debe reportar **0 perfiles fuera de sync**, y `verify-follows-migration.ts --cutover` debe salir **exit 0**, corridos inmediatamente antes del deploy del flip. No al final del change: **antes** de dar el flip por autorizado.

**Cómo se verifica el recálculo** — tres cosas, ninguna opcional:

1. **V6 de §7.3**, que es literalmente la aserción "almacenado == recalculado == grado de amistades aceptadas".
2. **Segunda corrida del backfill en `--dry-run`: debe reportar 0 perfiles fuera de sync.** Es la prueba de idempotencia del propio backfill y sale gratis.
3. **El delta agregado va al reporte de apply**: cuántos perfiles cambiaron y en cuánto subió cada contador. Es visible para el usuario; si no queda escrito, el primer tester que lo note lo reporta como bug de la migración.

Si **M-09** llegara a escribir algo (§7.3.1: no debería), se repite backfill → verificación en ese orden, **dentro de la ventana muda**.

#### 7.4.1 M-08b — la reconciliación posterior al repunte es obligatoria, no una red

**Corrección a la versión anterior de esta sección**, que cerraba diciendo *"a partir de M-08 la CF mantiene los contadores en vivo y el backfill queda como herramienta de reconciliación, fuera del camino normal"*. Es falso, y por un motivo que el freeze **no** toca.

El freeze de M-03b cierra una ventana concreta: que la CF vieja recompute sobre `friendships` y **pise** lo que el backfill escribió (§7.4, arriba). No cierra ésta:

```
3a.19b (M-06b)  el tester instala la build nueva y sigue a alguien
                → se escribe follows/{X}_{Y}
                → las CFs siguen apuntando a friendships (congelada): NADIE cuenta esa arista
   ... horas/días: el resto de la cadena de deploy ...
3a.21 (M-08)    se repuntan las CFs a follows
                → sólo recomputan los pares que reciban un evento NUEVO
                → el par {X,Y}, si no vuelve a moverse, queda con el contador viejo PARA SIEMPRE
```

Son dos ventanas distintas con dos mecanismos distintos: el freeze impide que **la fuente vieja escriba**; nada impide que **la fuente nueva escriba sin oyente**. La segunda no es un residuo teórico: los testers están usando la build justamente durante ese tramo, porque para eso se la distribuyó.

Por eso **M-08b es un paso obligatorio del plan**, no una herramienta disponible:

> **M-08b** — inmediatamente después del deploy de CFs (3a.21): `backfill-follow-counters.ts --dry-run` → revisar delta → `--apply` → `--dry-run` de nuevo, que **debe reportar 0 perfiles fuera de sync**. Ese último dry-run **es** la aserción V6b (almacenado == recalculado sobre `follows`), y por eso no hace falta invocar el verificador: `--delta` exige un manifiesto (§7.3.1) y acá no hubo ningún `--apply` de script que lo produzca — las aristas nuevas las escribieron clientes. **El flip no se declara cerrado sin este paso.**

Recién **después** de M-08b la CF sostiene los contadores en vivo y el backfill sale del camino normal. Riesgo asociado: R3b del proposal.

### 7.5 Rollout con testers reales en TestFlight (M-06b)

**Verificado**: la app **no tiene ningún mecanismo de versión mínima** — sin Remote Config, sin `package_info`, sin pantalla de force-update. Después del flip, una build vieja queda así:

- **Lectura: sigue funcionando** para las relaciones que existían antes de migrar — **justamente porque cada `accepted` quedó mutua**. El cliente viejo arma la lista de autores desde `friendships`, y bajo las rules nuevas el lector sigue a todos esos autores, así que el query pasa entero. **Con UNA sola arista esto se caía con `permission-denied` sobre el query completo** (feed en blanco), que era el motivo del rama B de ADR-FOLLOW-010: la decisión del dueño desactiva ese modo de falla como efecto lateral.
  - **Límite honesto**: si alguien deja de seguir después del flip, la lista del cliente viejo (que sale de `friendships`, congelada) queda con un autor que ya no sigue → `permission-denied` sobre el **query entero** → feed SEGUIDORES en blanco para ese usuario. Firestore no devuelve las filas que sí pasan. Por eso la ventana tiene que ser corta.
- **Escritura: rota, y ahora antes.** Seguir / dejar de seguir / aceptar apuntan a `friendships`, que queda `deny-all` (REQ-FOLLOW-017). El usuario ve un error. **Con el freeze adelantado a M-03b (§7.0), esa rotura empieza en M-03b y no en M-07**: la ventana de escritura social caída para builds viejas se extiende desde justo antes de la migración hasta que el tester instala la build nueva. Es el precio explícito de cerrar el agujero de los borrados (ADR-FOLLOW-015) y está anotado como riesgo A11.
  - **Mitigante operativo**: M-04 → M-05 → M-06 corren back-to-back en una sola sesión de operador (§7.3: a volumen de equipo, segundos), y la build ya está **compilada y subida** antes del freeze. La latencia real de la ventana es la instalación por parte de los testers, no el trabajo de migración.

**Decisión del dueño: no se bloquea el cambio por esto.** Paso explícito del rollout, entre M-06 y M-07:

> **M-06b — Publicar la build nueva en TestFlight y avisar a los testers.** Notificar por el canal habitual y **confirmar a mano** que actualizaron antes de correr M-07. No es un gate automatizable: no hay telemetría de versión. La confirmación queda registrada en el reporte de apply, igual que el número de M-00.

**Cómo se construye esa build sin caer en una dependencia circular.** La versión anterior de este paso decía "subir el build que incluye PR3b y PR3c" y al mismo tiempo PR3b declaraba como precondición que PR3a estuviera *mergeada y deployada* — y PR3a no se deploya sin M-06b. **Eso es un ciclo: el plan no era ejecutable como estaba escrito.** Se rompe distinguiendo dos cosas que la cadena de PRs mezcla:

| | Qué es | Qué requiere |
|---|---|---|
| **Precondición de merge/review** | El orden en que los PRs entran a `main` | La cadena lineal PR3a → PR3b → PR3c (para que el review sea legible y el diff acumulativo tenga sentido) |
| **Precondición de build** | Qué código compila el binario de TestFlight | **Nada de eso.** En una cadena encadenada, la rama de PR3c ya contiene PR3a + PR3b + PR3c por construcción |

Entonces: **la build de M-06b se compila desde la punta de la cadena (la rama de PR3c), sin mergear ni deployar nada.** El binario es el estado final; el orden de merge y el orden de deploy siguen siendo los de siempre. Dos precisiones que van con esto:

1. **Subir ≠ distribuir.** El binario se sube a TestFlight **antes** del freeze de M-03b (subir es inocuo y el procesado de App Store Connect tarda), pero **no se distribuye al grupo de testers hasta que M-06 sale exit 0**. Si un tester actualizara antes de M-06, el cliente nuevo escribiría aristas en `follows` sin friendship de origen y **V4 marcaría la migración como inválida** — la verificación de cutover asume que `follows` es 100% producto de la migración (§7.3.1).
2. El deploy de rules (M-07) sigue siendo posterior a la confirmación de instalación. Lo único que se adelantó es la **compilación y subida**, no la distribución ni el deploy.

**Recomendación de seguimiento, fuera de este change**: antes de tener usuarios de verdad conviene un gate de versión mínima (Remote Config + `package_info_plus` + pantalla de force-update). Este change lo **evidencia**, no lo resuelve, y meterlo acá sería mezclar dos problemas en un cutover.

---

## 8. ADRs

### ADR-FOLLOW-001 — `follows/{followerUid}_{followeeUid}`, un doc por arista dirigida

**Decisión.** Colección nueva `follows`, doc id direccional sin ordenar, campos de §1.1. La dirección vive en la clave, no en un campo.

**Por qué.** El doc id direccional convierte la autorización en estructura: el prefijo es el único que puede crear/cancelar, el sufijo el único que puede aceptar. No hace falta `diff().affectedKeys()` sobre un doc compartido por dos usuarios. Además el gate de acceso queda en un `get()` por doc id — sin queries, sin índices, mismo costo que hoy (§3.4).

**Alternativas descartadas.**
- *Extender `Friendship` con `statusAB`/`statusBA`* (approach C del explore): dos usuarios escribiendo campos distintos del mismo doc con aceptar/rechazar concurrente es el patrón que ya complicó `lastRead` en chat; y **igual** haría falta un campo direccional indexado para listar seguidores, o sea que paga la fragilidad sin comprar la simplicidad.
- *Subcolecciones `userPublicProfiles/{uid}/following/{otherUid}`*: obliga a escribir en dos ramas por follow (o a un collection-group query), rompe `sweepFollows` de una query, y las rules pierden el `get()` por doc id plano desde `posts` — habría que resolver el path desde el autor, que es más frágil.
- *Mantener el modelo actual*: descartado en el explore por las 4 lentes. La asimetría es matemáticamente irrepresentable con un doc por par y un solo `status`.

---

### ADR-FOLLOW-002 — `members` se conserva como campo derivado, inmutable y **desacoplado de `status`**

**Decisión.** `members == [followerUid, followeeUid]`, validado literal en el `create` y pineado en el `update`. Se usa **solo** con `array-contains` y **nunca** en combinación con `status`.

**Por qué.** Un campo derivado es deuda: puede driftear y mentir. La mitigación no es solo validarlo en rules, es **limitar qué depende de él**. `allOf` (exclusión en sugerencias) y `sweepFollows` (cascade de borrado de cuenta) toleran un `members` levemente impreciso — el peor caso es una sugerencia de más o un doc que sobrevive al barrido, ambos detectables. Los **contadores no lo tocan** (ADR-FOLLOW-007): si `members` driftea, ningún número visible miente. Ese es el mismo tipo de falla silenciosa que causó el bug de `REACTION_TYPES` (`strong`→`like` dejó un contador en cero sin error), y acá se corta por diseño.

**Alternativas descartadas.**
- *No guardar `members`*: `sweepFollows` pasa a 2 queries + dedup, y el borrado de cuenta es justo donde un doc que se escapa es compliance, no UX.
- *Guardar `members` ordenado*: rompe la validación literal en rules (habría que comparar contra dos literales posibles) sin ningún beneficio, porque nadie lo usa para reconstruir el doc id.

---

### ADR-FOLLOW-003 — Dos compuestos nuevos con `createdAt`; el compuesto de `friendships` **no se borra**

**Decisión.** Declarar `{followerUid, status, createdAt DESC}` y `{followeeUid, status, createdAt DESC}`. No crear `{members, status}` sobre `follows`. **Conservar** `friendships {members, status}` hasta M-10.

**Enmienda al proposal.** Affected Areas dice *"El compuesto `{members, status}` queda para `allOf`"*. Es incorrecto: `allOf` filtra **solo** por `members array-contains`, sin `status` (`friendship_repository.dart:107-110`) — eso lo sirve el índice single-field automático. Con los contadores en queries direccionales (ADR-FOLLOW-007), **ningún** query de `follows` combina `members` con `status`. El compuesto queda huérfano y no se replica.

**Por qué incluir `createdAt` ahora.** Las queries de este change son equality-only y Firestore las serviría por index merge. Pero `follow-lists` va a ordenar por `createdAt DESC` inmediatamente después, y un índice compuesto cuyo prefijo son las igualdades sirve **las dos formas**. Declararlo hoy evita un segundo deploy de índices y una espera de construcción en el peor momento.

**Por qué no borrar el índice viejo.** El rollback de M-08 reactiva exactamente `members array-contains + status` sobre `friendships`. Un índice recién recreado tarda en construirse y las queries fallan mientras tanto: borrarlo convierte un rollback de minutos en un incidente. Se borra en el mismo change que borra la colección (M-10).

---

### ADR-FOLLOW-004 — `postFollowerAccepted`: la asimetría cuesta cero llamadas de acceso

**Decisión.** `postFriendAccepted` pasa a `exists(follows/{lectorUid}_{autorUid}) && status == 'accepted'`, sin ordenar los uids. Mismos dos call sites, mismo literal `'friends'` en `privacy`.

**Por qué.** El cambio elimina las 3 líneas de cálculo de doc id ordenado (`firestore.rules:537-539`) y deja el gate en 2 llamadas de acceso — **exactamente las mismas que hoy**. Eso hace que el flip sea reversible sin análisis de performance: no hay que medir nada porque no cambió nada medible.

**Alternativas descartadas.**
- *Denormalizar `followerUids` en el post*: array creciente en el doc, techo de 1 MiB, y cada follow/unfollow tendría que reescribir todos los posts del autor. Absurdo.
- *Query en rules*: no existe. Rules solo hace `get`/`exists` por path.
- *Chequear ambas direcciones con OR* (preservar el comportamiento simétrico): sería no hacer el cambio.

---

### ADR-FOLLOW-005 — El chat es direccional: X le escribe a Y sólo si Y sigue a X

**Decisión del dueño, cerrada.** El permiso de escritura del chat 1-1 lo da **la arista entrante**: `followAccepted(destinatario, remitente)`. Dejar de seguir a alguien le quita a esa persona la escritura hacia mí; yo conservo la mía hacia ella. Rama `trainer_link` **sin tocar**.

**Por qué (intención declarada del dueño).** Preservar con **una sola acción** la intuición "corto el vínculo y dejo de recibir mensajes". Con follow mutuo, un OR de las dos direcciones exigía **dos** acciones para cortar (dejar de seguir *y* que el otro deje de seguirte), y la segunda no depende de vos: el vínculo entrante quedaba en manos del otro. Un modelo asimétrico con revocación simétrica es incoherente — si la relación se puede romper de un lado, el permiso que deriva de ella también.

**El hallazgo que la decisión desenterró, y que cambia su alcance.** Verificado en el código: `chatRelationshipOk` corre en **un único call site**, `allow create` de `/chats/{chatId}` (`firestore.rules:1134`). `messages/create` gatea sólo por membresía (`:1167-1170`), `chats/update` también (`:1142`), y borrar una amistad no borra ni marca el chat (`friendship_repository.dart:150-151`). Por lo tanto **hoy eliminar la amistad NO corta los mensajes de un chat existente** — sólo impide abrir uno nuevo. La conducta que la decisión quiere "preservar" no existe. Consecuencias, las dos ineludibles:

1. **El gate se muda a `messages/create`.** No es una optimización ni una elección de estilo: "uno puede escribir y el otro no dentro del mismo chat" es imposible de expresar en una regla que se evalúa una sola vez, al crear el documento. Regla completa en **§3.3.2**.
2. **Es una restricción nueva, no la conservación de una vigente**, y hay que declararla como tal en todos lados. Aplica retroactivamente a chats existentes cuyo par ya no tiene relación: hoy funcionan, después del flip quedan mudos para los dos (riesgo **A14**). Los pares que sí tenían amistad `accepted` migran a mutuo y **no cambian en nada** (§3.3.5).

**Costo, corregido a la baja.** `chats/create` pasa de `exists`+`get` sobre `friendships/{chatId}` a `exists`+`get` sobre **una** arista: **2 → 2, neutro**, peor caso ≤6 sobre 10. La versión anterior de este ADR (OR de dos direcciones) subía el peor caso a ≤8; ese margen ajustado **desaparece**, y con él R5 del proposal y A2 de §9. Lo que aparece es **+2 llamadas por mensaje enviado** en chats sociales (1 → 3 sobre 10), y **cero** en chats de trainer_link, porque `'linkId' in chat` se evalúa primero. Detalle en §3.3.3.

**Lo que NO se toca, y es deliberado (§3.3.4).** Lectura del chat, lectura de mensajes, `lastRead` y preview siguen gateados por membresía. El lado bloqueado **lee todo y marca como leído**; sólo pierde el envío. Bloquear la lectura borraría historia ya entregada, y atar `lastRead` al permiso de escritura dejaría el badge de no-leídos clavado para siempre.

**La UI tiene que decirlo (§6.1).** Un composer habilitado que el servidor rechaza es la peor forma de comunicar esto. El botón MENSAJE del perfil público pasa a mirar la arista **entrante** (`incomingFollow`), y el composer del chat se deshabilita con un aviso inline persistente —no un snackbar— cuando falta esa arista. Cliente y rules se mueven en el mismo slice, siempre.

**Alternativas descartadas.**
- *OR de las dos direcciones* (la decisión provisoria anterior): preserva la semántica sólo sobre el dato migrado y deja la revocación en manos del otro. Rechazada por el dueño, y con razón: contradice el modelo asimétrico que este change instala.
- *Exigir mutual-follow para escribir*: más restrictivo que lo decidido y **simétrico**, o sea que vuelve a necesitar dos acciones para abrir el canal y una sola para cerrarlo de los dos lados. Corta chats de pares que hoy se hablan sin agregar nada que la regla direccional no dé.
- *Dejar el gate sólo en `chats/create`* (la implementación mínima): no implementa la decisión. Un chat creado antes del unfollow seguiría vivo para siempre, que es exactamente lo que el dueño quiere terminar.
- *Desacoplar el chat del modelo social* (flag propio en el doc de chat): un estado más que mantener sincronizado con el grafo, y el primer bug de sincronización es un canal de mensajes que no debería existir.
- *Borrar el chat al dejar de seguir*: destruye historia del usuario por un cambio de permiso. Nunca.

---

### ADR-FOLLOW-006 — El self-accept pasa de check a invariante estructural

**Decisión.** El `update` solo lo permite `resource.data.followeeUid`, con transición `pending → accepted` explícita y todo lo demás pineado. El `create` prohíbe `followerUid == followeeUid`. Allowlist cerrada de 6 keys.

**Por qué.** Hoy el self-accept se bloquea con `request.auth.uid != resource.data.requesterId` (`firestore.rules:1086`) — una condición que alguien puede borrar en un refactor y que **no falla ningún test que corra en CI** (verificado: SCENARIO-132 vive en `scripts/rules_test/rules.test.js`, marcado `NOT part of CI`). Con la arista dirigida, aceptar tu propia solicitud requeriría que seas simultáneamente prefijo y sufijo del mismo doc id, cosa que el `create` ya prohíbe. La invariante deja de depender de que alguien se acuerde. El test sigue existiendo (LD-09, ahora **en CI**), pero ahora testea una propiedad estructural.

Efecto lateral valioso: el `get()` de auto-accept baja de ≤2 a 1 porque el "otro" es un campo, no una incógnita entre `uidA` y `uidB`.

---

### ADR-FOLLOW-007 — Contadores por dos queries direccionales, no por `array-contains` + split en memoria

**Decisión.** `countAcceptedFor(uid)` hace dos queries (`followerUid == uid` y `followeeUid == uid`, ambas `status == accepted`) y devuelve los dos `.size`. Se mantiene el recompute-from-scratch transaccional de QA-507.

**Por qué.** La alternativa (una query `members array-contains uid && status == accepted` y partir en memoria por `followerUid === uid`) sería un diff más chico — es literalmente la forma de hoy. Se descarta por dos razones:

1. **Acopla el número visible a un campo derivado.** Si `members` driftea, los contadores mienten sin error. Con queries direccionales, los contadores dependen solo de campos que rules valida contra el doc id. Precedente directo: el bug de `REACTION_TYPES`.
2. **Obligaría a crear el compuesto `{members, status}`** que ADR-FOLLOW-003 declara huérfano, y a mantenerlo para siempre por una optimización de 2 queries por evento de follow.

**Costo aceptado.** 4 queries por evento en vez de 2. Es un evento por follow/unfollow, no por lectura de feed. Irrelevante frente al riesgo de un contador que miente en silencio.

**Nota.** Las mismas dos queries definen la invariante **V6** de la verificación (§7.3) y el backfill de §7.4, así que las tres implementaciones comparten forma y no pueden divergir. Con follow mutuo esa forma compartida vale doble: V6a afirma `following == followers == grado de amistades`, y esa igualdad solo es chequeable si el recálculo, la CF y la verificación cuentan **igual**.

Bajo el mismo ADR: `notifyOnFollow` deja de inferir la dirección (`requesterId` + búsqueda en `members`) y la lee de `followerUid`/`followeeUid`; el copy de las 3 ramas queda intacto porque ya estaba escrito para este modelo. `sweepFollows` conserva **una** query gracias a `members` (ADR-FOLLOW-002).

---

### ADR-FOLLOW-008 — `chunkSize` 10→30 se desacopla del flip y se gatea con test de emulador

**Decisión.** El flip direccional del feed va en PR 3. El cambio de `chunkSize` de 10 a 30 (`post_repository.dart:141`) va **aparte**, y solo si un test contra el emulador demuestra que un query request de 30 autores distintos no supera el presupuesto de llamadas de acceso de rules.

**Enmienda al proposal.** Affected Areas lo da como *"gratis en este diff"*. No es gratis: `postFollowerAccepted` corre por documento evaluado, y subir el chunk triplica la cantidad de documentos `follows` **distintos** que rules toca en un solo query request. El límite documentado es 10 llamadas de acceso para query requests. Que hoy funcione con chunk 10 sugiere que el conteo efectivo no es plano por request — pero eso es una inferencia sobre el motor de rules, no una lectura de la documentación, y **no se sube un límite de fan-out apoyado en una inferencia**, menos en el mismo PR que cambia el gate de privacidad. Si el flip fallara, no habría forma de saber cuál de los dos cambios lo rompió.

**Alternativas descartadas.**
- *Subirlo igual y ver qué pasa*: el modo de falla es `permission-denied` sobre el query entero, o sea **feed AMIGOS en blanco**, no degradación parcial.
- *Cap duro de seguidos*: cambia comportamiento visible (posts que desaparecen sin explicación). Out of scope, y el arreglo real es un feed materializado.

---

### ADR-FOLLOW-009 — Capas Dart: superficie mínima consumida, key de family = doc id `String`

**Decisión.** `domain / data / application / presentation`. El repo expone **solo** los métodos con consumidor en este change; `followersOf`/`watchFollowersOf` se difieren a `follow-lists`. `followEdgeProvider` se indexa por el doc id (`String`). `PublicProfileView` pasa a tener dos aristas.

**Por qué.** Strict TDD está habilitado: cada método público arrastra tests que se escriben antes. Un método sin consumidor produce tests ceremoniales que dan cobertura falsa y hay que mantener. `followersOf` no tiene consumidor porque el perfil público lee `followersCount` del doc de perfil (mantenido por CF), no de un query.

La key `String` reemplaza al record `({viewerUid, targetUid})` de `friendshipByPairProvider`: los records tienen igualdad estructural y no rompían el cache, pero la key natural ahora **es** el doc id y alinear con la convención del repo no cuesta nada.

Los dos listeners del perfil (saliente + entrante) son el costo inevitable de la asimetría: hoy los 4 estados del botón caben en un doc porque el doc es el par. Se acepta porque son dos `.snapshots()` por doc id — sin queries, sin índices, `autoDispose` acotado a la pantalla.

**Alternativas descartadas.**
- *Un query `members array-contains` acotado al par*: usa un query donde alcanza un `get`, y necesitaría índice.
- *Denormalizar el estado del par en `userPublicProfiles`*: escritura cruzada entre usuarios, imposible de autorizar limpiamente.
- *Seguir `docs/architecture.md`* (`view/state/data`): el documento está desactualizado; el patrón real del código es el de arriba y romper la consistencia por seguir un doc viejo es peor que el doc viejo.

---

### ADR-FOLLOW-010 — Orden del flip condicionado por M-00; **dual-DELETE**, nunca dual-write

**Decisión.** El orden de M-07 (flip de rules + freeze) y M-08 (release de cliente + CFs) **depende del resultado de M-00**:

- **Rama A — M-00 confirma que la población es el equipo** (esperado): se mantiene el orden del proposal, rules primero. Los builds viejos rompen y se acepta (R3).
- **Rama B — M-00 revela usuarios reales**: se **invierte**. Primero el cliente, después las rules, con soak de adopción en el medio. Y durante la ventana, el `unfollow` del cliente nuevo hace **dual-DELETE**: borra la arista `follows` **y** el doc `friendships` legacy del par.

**Actualización 2026-08-04 — el dueño confirmó la premisa de la Rama A.** Los uids de `treino-dev` son solo del equipo y de testers conocidos, nadie de afuera. Esto fija la **Rama A** como la que corre y saca a M-00 de "decisión pendiente": pasa a ser **evidencia obligatoria, no gate abierto**. El `.count()` de M-00 (`tasks.md` 0.5) sigue corriendo igual y su número se registra en el reporte de apply, porque una confirmación verbal no reemplaza el conteo real sobre `treino-dev`. La Rama B queda documentada tal cual, como contingencia: si el conteo real alguna vez contradijera la confirmación, este ADR ya tiene el plan escrito.

**Por qué la inversión es segura (y por qué el proposal necesita esta enmienda).** LD-10 dice "rules antes que cliente, siempre", con el argumento correcto de que las rules de M-03 son aditivas. Pero eso aplica a M-03, no a M-07. En M-07 las rules se vuelven **más estrictas**, y Firestore rechaza el **query entero** con `permission-denied` cuando una sola fila no pasa la regla — no devuelve las que sí pasan. El cliente viejo pide `authorUid in [todos los accepted simétricos]`, que incluye autores a los que no sigue: bajo las rules nuevas, **el feed AMIGOS se cae entero**, no degrada. "Rules más estricta que cliente falla cerrado, nunca abierto" es cierto para seguridad y **falso para disponibilidad**.

En cambio, el query del cliente **nuevo** (solo autores que sigo) es un subconjunto estricto del viejo y por lo tanto **legal bajo los dos sets de rules**: bajo las viejas existe friendship accepted para esos pares; bajo las nuevas existe la arista. Lo mismo para leer/escribir `follows`, que M-03 ya habilitó. O sea: **el cliente nuevo es compatible hacia atrás y hacia adelante**. Por eso puede ir primero.

**El costo de la rama B, dicho sin maquillaje.** Entre el release del cliente y el flip de rules, las rules siguen siendo simétricas: la corrección de privacidad todavía no rige. No es una regresión (es el statu quo), salvo en un caso: si dejo de seguir a alguien durante esa ventana, el `friendships` legacy `accepted` le sigue dando acceso — el usuario cree que revocó y no revocó. **Exactamente el phantom access que LD-04 prohíbe.** El dual-DELETE lo cierra de raíz: es una excepción quirúrgica y unidireccional a "nada de dual-write" — solo borra, nunca crea, así que no puede resucitar la colección legacy ni ampliar acceso. Un dual-write completo compraría complejidad sin comprar la garantía (los clientes móviles no se actualizan atómicamente); un dual-delete compra exactamente la garantía que falta.

**Por qué no se elige la rama B siempre.** Con población de equipo, el dual-delete es código que se escribe para borrarse dos semanas después, y agrega un camino de escritura sobre una colección que se está congelando. La rama A es right-sized para el volumen real. M-00 es el que decide, y por eso es un paso bloqueante con un número, no una impresión.

**Enmienda por ADR-FOLLOW-015: la rama B necesita rediseño antes de ejecutarse.** El freeze se adelantó a M-03b, y la rama B se apoya en escribir (dual-DELETE sobre `friendships`) durante la ventana — con la colección congelada desde antes de M-04, ese mecanismo no puede correr tal como está escrito. Las dos son respuestas al **mismo** problema (phantom access durante la coexistencia) con costos distintos: la rama A lo cierra congelando temprano y aceptando que la escritura social caiga; la rama B lo cierra manteniendo la escritura viva y sincronizando los borrados. Si M-00 obliga a la rama B, el freeze vuelve a M-07 y el dual-DELETE lo reemplaza — **no se acumulan**. Queda anotado acá porque la rama B está en pausa (tasks 0.5) y volver a `sdd-design` con este detalle perdido sería empezar con una contradicción.

**Enmienda posterior (ADR-FOLLOW-013).** El argumento central de la rama B era de **disponibilidad**: el cliente viejo pidiendo `authorUid in [accepted simétricos]` incluía autores que no seguía → `permission-denied` sobre el query entero → feed en blanco. Con la migración a **dos aristas**, para toda relación pre-existente el lector **sí** sigue a todos esos autores, así que el query del cliente viejo **pasa entero bajo las rules nuevas**. Ese modo de falla desaparece para el dato migrado.

Lo que queda roto en una build vieja post-flip es la **escritura** (`friendships` congelada), y eso ninguna forma de migrar lo arregla. Hay además un residuo de disponibilidad: si un usuario deja de seguir después del flip, la lista del cliente viejo vuelve a incluir un autor no seguido y el feed se cae entero para él. Conclusión operativa: la rama A queda **más segura que antes**, y el mitigante es el paso de rollout M-06b (§7.5) — build nueva en TestFlight y aviso a los testers antes del flip — más una ventana corta. La rama B sigue escrita por si M-00 sorprende.

---

### ADR-FOLLOW-011 — `PostPrivacy.followers` con wire `'friends'`; lo que cambia el día del flip son los **contadores**, no el feed

**Decisión.** Renombrar el miembro del enum a `followers` conservando `@JsonValue('friends')`, el `_wireMap` y el `toJson()` (LD-05). El label visible pasa a "SEGUIDORES" vía l10n.

**Por qué.** Verificado en `post_privacy.dart:3-36`: el enum ya tiene `@JsonValue` + wire map explícito + switch exhaustivo, así que el rename es mecánico y el analyzer encuentra todos los usos. El wire queda byte-idéntico → la colección `posts` no se toca, las allowlists de rules (`firestore.rules:587,624`) no cambian, `post_repository.dart:151` sigue consultando `'friends'`. Cambiar el wire obligaría a reescribir cada post existente por un beneficio cosmético.

**Corrección al proposal — reescrita por ADR-FOLLOW-013.** LD-06 decía que la migración es "neutral en la superficie visible". Con la migración a **dos aristas** eso queda **dado vuelta**, y hay que decirlo con precisión porque la versión anterior de este ADR afirmaba lo contrario:

- **El feed SÍ es neutral.** Cada `accepted` migra mutua, así que ningún usuario ve menos posts el día del flip. El provider pasa a filtrar por dirección (el código cambia), pero sobre el dato migrado devuelve el mismo conjunto.
- **Los contadores NO son neutrales: suben.** `followersCount` y `followingCount` pasan a ser ambos iguales al número de amistades aceptadas (§7.4). Es el único cambio visible de la migración, y es el que tiene que estar en el reporte de apply — si no, el primer tester que vea su número distinto lo va a reportar como bug.
- **La asimetría se acumula después del flip**, con la actividad nueva: ahí sí un feed puede achicarse respecto de la contraparte, porque seguir pasa a crear una sola arista.

**Alternativas descartadas.**
- *Cambiar el wire a `'followers'`*: reescritura de toda la colección `posts`, 4 lugares hardcodeados a sincronizar a mano, y el antecedente `REACTION_TYPES` demuestra cómo termina eso.
- *No renombrar nada*: el código seguiría diciendo `friends` para algo que ya no lo es. Es exactamente la deuda que este change viene a pagar.

---

### ADR-FOLLOW-012 — Rollback: la reversibilidad la da el dato intacto, no el código

**Decisión.** Rollback por slice, sin ninguna operación destructiva dentro de este change. El único punto sin retorno (borrar `friendships`) queda fuera, en M-10.

| Slice | Qué se revierte | Cómo | Tiempo |
|---|---|---|---|
| PR 1 — código inerte | modelo, repo, providers, rules aditivas, índices | `git revert`. Las rules de M-03 solo **agregan** `follows`; revertirlas deja la colección vacía y sin efecto. Los índices no se borran (no molestan) | minutos |
| PR 2 — migración | `follows` poblada + contadores recalculados | borrar `follows`, volver a `--dry-run`, y **volver a correr el backfill** (que recomputa desde cero: con `follows` vacía devuelve los contadores a 0, y con `friendships` intacta se puede restaurar el valor viejo con la versión previa del agregador). `friendships` intacta | minutos |
| PR 3 — flip | rules direccionales + freeze + CFs + cliente | redeploy de la versión anterior de rules (Firebase guarda historial) → restaura lectura simétrica **y** escritura sobre `friendships`; `git revert` del release; redeploy de las CFs previas. **La app vieja vuelve a andar sin restaurar un solo dato** | horas (limitado por el release móvil) |
| PR 4 — UI/copy | cancelar solicitud, `TreinoTappable`, ARBs | `git revert`. Cero impacto en datos | minutos |

**Precondiciones del rollback que este design se compromete a mantener:**

1. `friendships` **nunca** se borra ni se modifica: el freeze es `create/update/delete: if false`, y el `read` se conserva para poder auditar (y para que un cliente revertido pueda leer).
2. El índice `friendships {members, status}` **no** se borra (ADR-FOLLOW-003) — sin él, el cliente revertido tiene rules OK e índice faltante.
3. El snapshot de M-01 vive fuera de Firestore: aunque el script tuviera un bug destructivo, el mapeo original existe en disco.
4. `createdAt` se preserva doc a doc y el doc id es determinístico, así que una re-migración después de un rollback produce **el mismo estado byte a byte** (V2/V3 de §7.3 lo verifican; la idempotencia la garantiza ADR-FOLLOW-014).
5. El script de migración **nunca escribe en `friendships`**, ni siquiera un campo de marcado de migración: el estado de "ya migrado" se deduce de `follows` (guarda G1), no del origen. Sin esto, la precondición 1 sería mentira.

**Lo que el rollback NO recupera.** Los follows creados **después** del flip viven solo en `follows`. Revertir el cliente los deja invisibles (no borrados). Si hay que revertir después de que hubo actividad real, hay que correr la migración **inversa** (`follows → friendships`), que **no está en scope** — y con follow mutuo es además **más lossy**: dos aristas colapsan a un doc y hay que elegir un `requesterId`, decisión que el dato ya no contiene (un unfollow post-flip de una de las dos direcciones es irrecuperable en el modelo viejo). El mitigante sigue siendo que la ventana entre M-08 y la confirmación es corta y la población es el equipo (M-00). Si M-00 falla, esto es un argumento más para la rama B de ADR-FOLLOW-010.

---

### ADR-FOLLOW-013 — Las amistades `accepted` migran a DOS aristas; la asimetría rige desde el flip

**Decisión.** Cada `friendship` `accepted` bien formada migra a **dos** aristas — `follows/{A}_{B}` y `follows/{B}_{A}`, ambas `status: 'accepted'` — y queda como follow mutuo. Cada `pending` migra a **una sola**, en la dirección `requesterId → otro`. De la migración en adelante, seguir crea **una** arista: la asimetría es real desde el flip, no hacia atrás.

**Revierte LD-06 del proposal. Decisión explícita del dueño**, textual: *"con los usuarios que ya están vinculados a otros con relación de amistad dejalos así, como que si se hubiesen seguido mutuamente desde el inicio, que esta nueva forma empiece desde ahora"*.

**Por qué.** Con una sola arista, en **cada** amistad existente el miembro que no fue el `requester` deja de seguir al otro y por lo tanto **pierde el acceso a sus posts tier "solo amigos"**. Es la mitad de las relaciones existentes perdiendo contenido del feed el día del flip. El proposal lo justificaba con "el acceso simétrico ERA el bug" — correcto como diagnóstico, y aun así el criterio del dueño manda y es defendible: el bug se corrige **hacia adelante**, no revocándole acceso retroactivamente a gente que nunca pidió dejar de seguir a nadie. Migrar a follow mutuo es además la lectura **fiel** del estado actual: hoy esas dos personas se ven mutuamente los posts; dos aristas es exactamente eso, escrito en el modelo nuevo. Una sola arista no preserva el estado: lo reinterpreta.

**Consecuencia asumida y visible: los contadores suben.**

```
ANTES:    followersCount(u) + followingCount(u) == #amistades accepted de u
DESPUÉS:  followersCount(u) == followingCount(u) == #amistades accepted de u
```

**No es un bug.** El split por `requesterId` de hoy (`maintain-follow-counters.ts:127-152`) ya era engañoso: mostraba "siguiendo 1, seguidores 0" para una relación que en los hechos era mutua. El número nuevo cuenta lo que realmente pasa. Es visible para el usuario, así que va anunciado en el reporte de apply y en el aviso a los testers (§7.4, §7.5).

**Consecuencia de diseño: se cae el criterio de verificación de la migración.** El viejo M-06 ④ era *"para cada usuario, los contadores recalculados son idénticos a los que ya tenía"* — el chequeo que atrapaba una inversión de dirección. Con dos aristas no aplica. Lo reemplaza el conjunto **V1–V6 de §7.3**, que es más fuerte: cardinalidad `2·A + P`, cobertura doc-a-doc en ambas direcciones con `createdAt`, unicidad direccional de las pending, ausencia de aristas inventadas, forma del doc, y **triple** igualdad de contadores (almacenado == recalculado == grado de amistades). Cada clase de falla la atrapan al menos dos invariantes; la tabla de cobertura está en §7.3.

**Efecto lateral favorable, no buscado.** Deja al cliente viejo **leyendo bien** después del flip (§7.5) y desactiva el modo de falla "feed en blanco por `permission-denied`" que motivaba la inversión de orden de la rama B de ADR-FOLLOW-010.

**Alternativas descartadas.**
- *Una arista (LD-06 original)*: rechazada por el dueño. Media base perdiendo acceso a contenido que hoy ve, sin ninguna acción del usuario.
- *Dos aristas solo si "parecen" ambos activos* (heurística por actividad reciente, chats, reacciones): el script **nunca adivina** — es la misma regla que hace que un doc malformado se enumere en vez de inferirse. Una heurística acá produce revocaciones silenciosas e irreproducibles.
- *Migrar a dos y después "limpiar" con una campaña de re-confirmación*: producto nuevo metido adentro de una migración de datos. Si el dueño lo quiere, es otro change.

---

### ADR-FOLLOW-014 — La idempotencia del script es doc id determinístico **más** prohibición de pisar

**Decisión.** El script de migración nunca usa ids autogenerados y **nunca sobrescribe** una arista existente. `--apply` lee primero las aristas esperadas por doc id y escribe solo las faltantes con `batch.create()`. La **guarda por par** es **asimétrica por modo**: con `--since` (delta sweep post-flip), si el par ya tiene al menos una arista se saltea entero; sin `--since` (corrida inicial), sólo se saltea si están **todas**, y un par incompleto se **completa** reportándose como `partialPair`. Contrato completo en §7.2.

**Corrección — la guarda no podía ser simétrica.** La versión anterior de este ADR aplicaba la guarda por par en los dos modos, y eso convertía a un batch interrumpido en una migración incompleta que reportaba exit 0 (el desarrollo está en §7.2, G1). El error de razonamiento es concreto y vale nombrarlo: se justificó la guarda con una semántica que **sólo existe después del flip** ("falta una dirección" = alguien dejó de seguir) y se la aplicó a un modo donde esa semántica es imposible, porque el cliente que produce unfollows todavía no está publicado. El mismo estado observado significa cosas opuestas a los dos lados del flip, y una guarda que no distingue los modos tiene que estar mal en uno de los dos. La asimetría ya existía para G2 y G3; faltaba para G1.

**Por qué el doc id determinístico no alcanza.** Garantiza que correr el script dos veces no pueda **duplicar** (la segunda escritura apunta al mismo documento), pero con `set()` sí puede **pisar**: una arista que el followee aceptó después de la migración volvería a `pending`, y una arista borrada por el usuario reaparecería. Duplicación e idempotencia real no son lo mismo.

**Por qué la guarda por par con `--since`, y no "crear lo que falte".** Después del flip, *"falta una de las dos direcciones de un par accepted"* ya **no** significa "la migración quedó a medias": significa **que un usuario dejó de seguir**. Un delta sweep (M-09) que crea lo que falta resucitaría ese unfollow — un cambio de privacidad revertido por un script, exactamente la clase de falla que LD-04 prohíbe. Con la guarda, M-09 solo puede tocar pares que **no existen en absoluto** en `follows`.

**El caso residual** — par sin ninguna arista porque **los dos** se dejaron de seguir post-flip — se cierra con `--since <ISO del run de M-04>`: un par sin aristas cuyo friendship es anterior al watermark se reporta como **conflicto** y no se escribe. Requiere ojo humano; a volumen de equipo son cero o un puñado. Sin `--since`, el script asume primera corrida y no aplica G3.

**Lo que la guarda por par NUNCA cubrió, y por eso hace falta ADR-FOLLOW-015.** G1 y G3 protegen contra *recrear* aristas que el usuario borró. No hacen nada contra el caso inverso: un par **migrado** cuya amistad de origen se **borra** después. El script sólo crea (`toCreate`, `batch.create()`); un borrado en `friendships` no produce ninguna entrada de plan, así que las dos aristas migradas **sobreviven al unfollow**. Ese agujero no se tapa con guardas — se tapa impidiendo que la ventana exista, que es lo que hace el freeze adelantado.

**Por qué `create()` y no `set()`.** `set()` es idempotente en el sentido débil (mismo estado final si la fuente no cambió) pero silencioso ante una carrera. `create()` falla ruidosa si el doc apareció entre el read y el write — que es exactamente lo que uno quiere de una migración: enterarse, no promediar.

**Costo aceptado.** Una lectura por arista esperada (`getAll()` por doc id en chunks de 300, sin queries ni índices) antes de escribir. A cambio: correr el script dos veces sobre un estado completo es un no-op con **0 writes** y exit 0, y el delta sweep no puede revertir una decisión de privacidad del usuario.

---

### ADR-FOLLOW-015 — El freeze de `friendships` se adelanta a antes de M-04; el delta sweep degrada a aserción

**Decisión.** El freeze (`create/update/delete: if false` sobre `friendships`, REQ-FOLLOW-017) deja de ser parte de M-07 y pasa a ser **M-03b**, deployado inmediatamente **antes** de M-04. M-07 queda conteniendo sólo el flip direccional del gate. El delta sweep M-09 pasa a correr en `--dry-run` como aserción de "la ventana está vacía", y si alguna vez tuviera que escribir, escribe **dentro de la ventana muda** (§7.2), nunca en PR3d.

**El agujero que cierra: los borrados.** El script de migración **sólo crea**. Un borrado en `friendships` es una escritura que no genera ninguna entrada de plan, así que el sweep no lo absorbe. Con el freeze en M-07 el escenario era este, y la cadena de PRs es larga **por diseño**, así que la ventana se mide en días:

```
M-04 migra el par {A,B} → dos aristas accepted
   ... días ...          (todavía pre-M-07: friendships acepta escrituras)
A, con la build vieja, ELIMINA la amistad
M-07 congela
M-09 corre: el par ya no está en friendships → no hay nada que planificar
   → las DOS aristas sobreviven
```

A y B se siguen viendo los posts tier followers **después de que A revocó**. Es phantom access — la falla que LD-04 declara "la peor posible en un cambio de privacidad" — entrando por la puerta de atrás. Y la verificación no lo veía: V4 (sin invención) lo atraparía en `--cutover`, pero M-09 corre en `--delta`, donde V4 está restringida al manifiesto justamente para no marcar como error la actividad legítima post-flip.

**Por qué esta solución y no reconciliar los borrados en el script.** La alternativa era un paso nuevo: buscar pares presentes en `follows` y ausentes en `friendships`, y contrastarlos contra el snapshot de M-01 para distinguir "borrado durante la ventana" (hay que borrar las aristas) de "follow nuevo post-flip" (hay que dejarlas). Eso es lógica nueva, con estado externo al que hay que darle autoridad, para resolver una ambigüedad que **el orden de ejecución elimina de entrada**. Adelantar un deploy de rules de 4 líneas contra escribir un reconciliador de borrados con su suite de tests: no es una comparación pareja. Un problema que se puede sacar del calendario no se resuelve con código.

**Dos findings más que se cierran de arriba, y no fue casualidad.** Todos venían del mismo error: *la fuente vieja seguía viva demasiado tiempo*.

1. **Contadores pisados entre M-05 y el deploy de las CFs.** `maintainFollowCounters` es `onDocumentWritten` sobre `friendships` y `countAcceptedFor` lee `friendships` (`maintain-follow-counters.ts:138, 208-210`). Cualquier amistad tocada por una build viva después de M-05 hacía que la CF vieja recomputara con el split por `requesterId` y **devolviera ese par a los valores viejos**, en silencio, varios PRs antes de que alguien volviera a mirar. Con `friendships` congelada desde M-03b, la CF vieja no puede volver a dispararse: no hay más escrituras de cliente sobre su colección.
2. **Notificaciones push del sweep.** Ver la "regla de la ventana muda" (§7.2): es una restricción de orden independiente, pero con M-09 degradado a `--dry-run` el caso ya no se presenta en el camino normal.

**Costo aceptado, sin maquillaje.** La escritura social (seguir / aceptar / dejar de seguir) queda **caída para builds viejas desde M-03b**, no desde M-07 — el corte se adelanta desde el flip hasta justo antes de la migración. Bajo M-00 rama A (población = equipo) es una ventana anunciada de minutos de script más la latencia de instalación de la build nueva, y la build ya está compilada y subida antes del freeze (§7.5). Riesgo A11.

**Residuo que NO cierra, y está verificado en el código.** El freeze es de **rules**, y `sweepFriendships` (`functions/src/cascade/friendships.ts:25-28`) borra con **Admin SDK**, que las ignora. Un borrado de cuenta entre M-03b y M-08 deja aristas huérfanas en `follows` y desincroniza contadores. No se agrega mecanismo: se lo detecta con V4 + V6b en la re-verificación obligatoria de §7.1.1, y se resuelve a mano. Riesgo A12.

**Alternativas descartadas.**
- *Reconciliador de borrados en el sweep*: arriba.
- *Dejar el freeze en M-07 y acortar la cadena de PRs*: la cadena es larga porque el presupuesto de review lo exige (delivery = PRs encadenados, decisión cerrada). Comprimirla para tapar un agujero de datos es pagar con lo que menos queremos gastar.
- *Dual-DELETE durante la ventana* (el mecanismo de la rama B de ADR-FOLLOW-010): resuelve el caso pero exige que el cliente nuevo ya esté publicado, y en rama A no lo está en ese momento. Sigue siendo la respuesta correcta **si M-00 obliga a la rama B**.

---

## 9. Riesgos arquitectónicos que quedan abiertos

| # | Riesgo | Estado |
|---|---|---|
| A1 | Presupuesto real de llamadas de acceso en un *query request* con N autores distintos | **Sin medir.** Gatea `chunkSize` 30 (ADR-FOLLOW-008). Se mide en el emulador antes de tocar el chunk |
| A2 | ~~`chats/create` peor caso ≤8 de 10 llamadas~~ → **cerrado** por ADR-FOLLOW-005: el lookup direccional único reemplaza uno a uno al `exists`+`get` sobre `friendships`, así que el peor caso vuelve a **≤6** | Cerrado. El costo se corrió a `messages/create`: **+2 por mensaje enviado** en chats sociales (1 → 3 sobre 10), 0 en chats de trainer_link. Cubierto por `chat-relationship-rules.test.ts` en CI, que ahora ejercita las dos superficies |
| A3 | Fan-out de feed sin cap superior | Preexistente (R9). Documentado en §5.2, no se arregla acá. El arreglo real es feed materializado |
| A4 | ~~Feed AMIGOS se achica el día del flip~~ → **cerrado** por ADR-FOLLOW-013: con follow mutuo el feed es neutral sobre el dato migrado | Cerrado. La divergencia aparece recién con la actividad post-flip |
| A5 | Orden del flip dependía de un dato que todavía no existía (M-00) | **Decisión cerrada 2026-08-04**: el dueño confirmó que `treino-dev` es equipo + testers conocidos → Rama A. M-00 sigue corriendo en producción como evidencia obligatoria (`tasks.md` 0.5), no como decisión pendiente. ADR-FOLLOW-010 mantiene la Rama B documentada como contingencia, y la Rama A quedó más segura tras ADR-FOLLOW-013 |
| A6 | Rollback post-actividad no tiene migración inversa, y con follow mutuo es **más** lossy (dos aristas → un doc, hay que elegir `requesterId`) | Aceptado bajo M-00 rama A. Si M-00 falla, se reevalúa |
| A7 | `PublicProfileView` con 2 listeners por pantalla | Aceptado: dos `.snapshots()` por doc id, `autoDispose` |
| **A8** | **Los contadores suben visiblemente el día de la migración** | Intencional (ADR-FOLLOW-013). Mitigante: queda en el reporte de apply con el delta agregado y en el aviso a testers (§7.4 punto 3) |
| **A9** | **Builds viejas post-freeze: la escritura queda rota** (seguir/aceptar/dejar de seguir contra `friendships` congelada) | Aceptado por el dueño. Mitigante: paso M-06b (§7.5) — build compilada y subida **antes** del freeze, distribuida y confirmada después de M-06 y antes del flip. **Recomendación fuera de scope**: gate de versión mínima antes de tener usuarios reales |
| **A10** | **El delta sweep podría resucitar un unfollow post-flip** | **Cerrado por diseño**: guarda por par **con `--since`** + `create()` (ADR-FOLLOW-014). Sin esas, M-09 es una máquina de revertir decisiones de privacidad. Nota: la misma guarda aplicada **sin** `--since` producía el defecto inverso (migración parcial con exit 0), por eso ahora es asimétrica por modo |
| **A11** | **Ventana de escritura social caída, adelantada a M-03b** — con el freeze antes de M-04, seguir/aceptar/dejar de seguir dejan de funcionar en builds viejas desde antes de la migración y no desde el flip | **Aceptado** (ADR-FOLLOW-015) como precio de cerrar el phantom access por borrados. Mitigantes: población = equipo (M-00 rama A), M-04→M-06 back-to-back en una sesión, build ya subida antes del freeze. Si M-00 falla, la respuesta es la rama B (dual-DELETE) y el freeze vuelve a M-07 |
| **A12** | **El cascade de borrado de cuenta saltea el freeze** — `sweepFriendships` borra con Admin SDK (`cascade/friendships.ts:25-28`), que ignora rules: entre M-03b y M-08 deja aristas huérfanas en `follows` y desincroniza contadores | **Detectado, no prevenido.** V4 + V6b en la re-verificación obligatoria antes del flip (§7.1.1, §7.1.2). Resolución manual. Instrucción operativa: no borrar cuentas en esa ventana |
| **A13** | **El exit 0 de M-06 es una foto que autoriza un deploy varios PRs después** | **Cerrado con vencimiento**: la condición 2 de la compuerta caduca a los 7 días o ante cualquier actividad conocida sobre las 3 colecciones; se re-verifica inmediatamente antes de M-07, en `--cutover` si `follows` sigue siendo 100% producto de la migración y en `--delta --manifest apply-{ISO}.json` si la build de M-06b ya se distribuyó — porque desde ahí `--cutover` es **insatisfacible por construcción** (§7.1.1, §7.1.1b). Cuesta segundos |
| **A14** | **Chats preexistentes sin arista quedan mudos para los dos lados.** Al mudar el gate a `messages/create` (ADR-FOLLOW-005), un par que chateaba y ya no tiene relación —hoy sigue pudiendo escribirse, porque el gate sólo corre al crear el chat— pierde el envío en ambas direcciones. La lectura y el `lastRead` se conservan | **Aceptado y declarado.** Es la semántica que el dueño pidió, aplicada pareja también al pasado. A volumen de equipo (M-00) son cero o un puñado de pares. Mitigante: el aviso inline del composer (§6.1) explica **por qué**, en vez de fallar con un `permission-denied` crudo. **No se mitiga borrando ni ocultando el chat**: la historia queda legible |
| **A15** | **Aristas escritas por clientes actualizados entre M-06b y el repunte de CFs no las cuenta nadie**, y la CF nueva sólo recomputa los pares que reciban un evento posterior: un par que se movió en esa ventana y después queda quieto conserva el contador viejo indefinidamente. El freeze de M-03b **no** cubre esto (cierra la ventana inversa: que la CF vieja pise el backfill) | **Cerrado con paso obligatorio**: M-08b (§7.4.1) — backfill `--dry-run` → `--apply` → `--dry-run` con 0 perfiles fuera de sync, inmediatamente después de 3a.21. El flip no se declara cerrado antes. Riesgo R3b del proposal |

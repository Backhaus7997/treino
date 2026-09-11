# Diseño

## `blocks` — copia el molde de `follows`

`follows/{followerUid}_{followeeUid}` (`firestore.rules:1789-1931`) ya resolvió
este problema: arista **dirigida**, id compuesto **sin ordenar** —si se ordenara,
las dos direcciones colisionarían en el mismo documento— y un campo `members`
redundante para poder hacer `array-contains` sin doble query.

`blocks` es todo eso y más simple: no tiene `pending → accepted`, porque
bloquear no se negocia. Sólo `create` y `delete`.

```
blocks/{blockerUid}_{blockedUid}
  blockerUid: String
  blockedUid: String
  members:    [blockerUid, blockedUid]
  createdAt:  Timestamp
```

### El oráculo de existencia (QA-SEC-010)

Los padrones de uid son listables por cualquier autenticado, así que armar el id
de un par ajeno es trivial. Si el `read` no se acota, «no existe» vuelve como
snapshot vacío y «existe pero no es tuyo» como `PERMISSION_DENIED`: **esa
diferencia de forma ya es la fuga**, y reconstruye quién bloqueó a quién sin
leer un solo campo.

`follows` (:1806-1819) y `athlete_notes` (:3732-3751) lo resuelven acotando el
disyunto a los uids del propio id. Acá se hace igual.

**Y una decisión de producto encima:** sólo el **bloqueador** lee su documento.
El bloqueado no puede confirmar que lo bloquearon. Un bloqueo verificable es un
bloqueo que invita a la represalia por otro canal.

### `notBlocked()` — el helper

A scope raíz, espejando `followAccepted()` (:103-107):

```
function notBlocked(a, b) {
  return !exists(/databases/$(database)/documents/blocks/$(a + '_' + b))
      && !exists(/databases/$(database)/documents/blocks/$(b + '_' + a));
}
```

**Las dos direcciones.** Si A bloquea a B, ninguno le puede escribir al otro. Un
bloqueo de una sola vía deja al bloqueador recibiendo interacciones de quien
bloqueó, que es justo de lo que se quería ir.

---

## Dónde se hace cumplir — y por qué NO en la lectura

### El error que casi cometo

El instinto es sumar `notBlocked()` a `posts/{postId} allow read`. **Rompería el
feed entero.**

En Firestore las reglas de `list` se evalúan contra la query, y si un solo
documento del resultado no pasa, **se rechaza la query completa en vez de
filtrar la fila**. Está documentado en este repo, en `post_providers.dart:157`:

> *«la query se emite sólo cuando la relación que la autoriza se cumple, porque
> si el cliente pidiera filas que la regla deniega, Firestore rechaza el QUERY
> ENTERO, no las filas de más»*

`feedPublic()` no filtra por autor. Con `notBlocked()` en el read, el primer post
de alguien con quien exista un bloqueo deja el feed **en blanco**, no recortado.
Y el bug aparecería recién cuando alguien bloquee a alguien: en producción.

### Entonces el corte va en la ESCRITURA

Que es donde está el daño real. A alguien acosado lo protege que el otro **no lo
pueda contactar**, no que no pueda leer un post que es público por definición.

| Vector | Dónde se corta | ¿Se puede? |
|---|---|---|
| Te escribe por chat | `senderMayPost` (`:2229-2238`) | **Sí** — es escritura |
| Te reacciona un post | `posts/{id}/reactions/{uid}` create | **Sí** |
| Te sigue | `follows` create | **Sí** |
| Te reseña | `reviews` create | **Sí** |
| Ves su contenido en el feed | Cliente | Cosmético, y se asume |

### El tier `followers` sale gratis

Acá está lo bueno: **bloquear borra las aristas de follow en las dos
direcciones.**

Con eso el tier `followers` queda protegido **por la regla que ya existe**
(`postFollowerAccepted`): sin arista no hay acceso, y no hay que tocar una sola
línea del `allow read`. El enforcement de lectura del tier que de verdad importa
sale de arrastre, sin romper nada.

Lo hace un trigger `onCreate` sobre `blocks`, siguiendo el patrón de
`social/maintain-follow-counters.ts`.

### Lo que queda cosmético, y se dice

Para `public` y `gym` el filtro es del lado del cliente y **no es un control de
seguridad**. Alguien con el SDK crudo sigue leyendo esos posts.

Se acepta a propósito, porque la alternativa es romper el feed. Y la exposición
es acotada: son posts que su autor eligió publicar a toda la app o a todo el
gimnasio. El contenido privado —chat, tier seguidores— sí queda cerrado de
verdad.

### El costo de `exists()`

Dos lecturas por evaluación. Como ahora corre sólo en **escrituras** —mandar un
mensaje, reaccionar, seguir, reseñar— y no por cada post de cada scroll, el costo
es despreciable. Es un beneficio secundario de haber movido el enforcement: la
versión que rompía el feed además pagaba dos lecturas por cada post listado.

---

## `reports` — el id previene el doble reporte

```
reports/{targetKind}_{targetId}_{reporterUid}
  reporterUid:    String
  targetKind:     'post' | 'message' | 'review' | 'profile'
  targetId:       String
  targetOwnerUid: String
  reason:         String   // taxonomía de normas-de-comunidad.md §1
  detail:         String?  // ≤ 1000
  createdAt:      Timestamp
```

Mismo truco que `posts/{postId}/reactions/{reactorUid}`: **el uid del que escribe
es parte del id**. Eso hace imposible falsificar el `reporterUid` de otro y hace
idempotente el doble reporte, sin ningún contador.

**El `read` está cerrado a todo cliente.** Los reportes se revisan por consola.
Un denunciante que puede leer reportes ajenos es un canal de acoso nuevo.

---

## Lo que NO se toca

**El borrado en cascada.** `cascade/athlete-data.ts` borra por campo `athleteId`.
`blocks` y `reports` llevan los uids en el id compuesto, así que **no los
alcanza**. Queda anotado en tasks: un bloqueo que sobrevive al borrado de cuenta
de una de las partes es un documento huérfano.

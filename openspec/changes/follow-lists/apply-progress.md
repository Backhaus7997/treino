# follow-lists — bitácora

Pantallas de SEGUIDORES y SEGUIDOS, con acceso estilo Instagram: se tocan los
contadores del perfil y se abre la lista.

Quedaron fuera de `follow-model` por LD-07 — el cambio de modelo era la parte
irreversible y había que poder verificarla sin ruido encima. Este change es
100% aditivo sobre ese modelo.

---

## 1. La decisión de visibilidad, y por qué la opción "intermedia" no existía

El bloqueo de entrada: las rules no dejaban leer la lista de otra persona. Se
le presentaron tres caminos al dueño y eligió **abrir las aristas ya
`accepted` a cualquier autenticado**, con las `pending` privadas.

Antes de preguntar hubo que corregir la opción que parecía más atractiva
—"permitir sólo si el perfil del target es público, con un `get()` sobre
`userPublicProfiles`"—: **no se puede expresar en Firestore rules.**

Las rules evalúan **el documento**, y no tienen acceso a las cláusulas `where`
de la query: no hay forma de que la regla sepa *de quién* es la lista pedida.
Y Firestore rechaza la **query entera** si una sola fila no pasa. Consecuencia:
mirar los seguidores de una cuenta pública que tenga un seguidor privado
reventaría la lista completa, de forma impredecible según a quién siga esa
persona. Las variantes AND/OR sobre los dos extremos tienen el mismo problema
o filtran datos.

`request.query` en rules expone `limit`/`offset`/`orderBy`, **nunca los
filtros**.

Un gate que dependa del *sujeto* de la lista necesita, o bien un read-model con
el sujeto en el **path** (subcolección), o bien una Cloud Function. Las dos
cosas están fuera del alcance de una pantalla aditiva.

**Trade-off aceptado**: las cuentas privadas también quedan con la lista
visible. Se puede endurecer después sin migrar datos.

---

## 2. Bug de producción encontrado en el camino

Al escribir el primer test de query apareció esto:

```
✕ el dueño lista sus propios seguidos
  Property members is undefined on object. for 'list' @ L1111
```

Una query que **la app ya hacía**. Diagnóstico en aislamiento, con estado
limpio:

| Operación | Antes |
|---|---|
| `getEdge` — por doc id | ✅ |
| `allOf` — `members array-contains uid` | ✅ |
| `followingOf` — `followerUid == uid && status == accepted` | ❌ **denegada** |
| `pendingReceivedFor` — `followeeUid == uid && status == pending` | ❌ **denegada** |

Denegadas **desde el cutover de `follow-model`**, con la build `0.1.0+14` ya en
TestFlight. Consumidores rotos:

- **feed SEGUIDORES** — `feed_screen_providers.dart:29`, `post_providers.dart:161`
- **inbox de solicitudes y su badge** — `friend_requests_inbox_screen.dart`,
  `notification_history_screen.dart`, `profile_cuenta_section.dart`

### Causa raíz

**Las rules no se evalúan documento por documento en una query.** Firestore
analiza la query contra la regla y exige poder **probar** que se cumple usando
**sólo las cláusulas `where`**, sin leer un documento. Un campo que el `where`
no menciona queda **indefinido**, y referenciarlo tira el error de arriba y
rechaza la query entera — aunque todos los documentos reales cumplieran.

`where('members','array-contains',uid)` funcionaba justamente porque el `where`
nombra `members`.

### Por qué pasó verde en CI

`follows-rules.test.ts` tenía un `describe("follows — read")` con **sólo
lecturas por doc id**. Un `assertSucceeds(db.doc(id).get())` no prueba nada
sobre `db.where(...).get()`: para Firestore son operaciones distintas (`get` vs
`list`) con análisis distinto.

**Regla para el futuro: todo `allow read` que sirva a una query necesita un
test de query. El `get` por doc id no lo cubre.**

### Fix

```
allow read: if request.auth != null
            && (resource == null
                || request.auth.uid in resource.data.members      // doc id + allOf
                || request.auth.uid == resource.data.followerUid  // followingOf
                || request.auth.uid == resource.data.followeeUid  // pendingReceivedFor
                || resource.data.status == 'accepted');           // listas ajenas
```

Las tres primeras son **redundantes a nivel de documento** (el `create`
garantiza `members == [followerUid, followeeUid]`): existen sólo para que el
planner tenga algo probable desde cada `where`. La cuarta es la apertura de
§1.

Semántica que lo hace funcionar: **`error || true == true`** en el lenguaje de
rules. Las disyunciones que el planner no puede resolver dan error y no
envenenan el OR mientras alguna otra sea probablemente verdadera. Por eso el
orden no importa.

`status == 'accepted'` protege las solicitudes sin ayuda extra: una query sin
ese filtro no se puede probar y **se cae entera** en vez de filtrar.

---

## 3. Qué se construyó

| Capa | Archivo |
|---|---|
| Rules | `firestore.rules` — bloque `follows`, `allow read` |
| Tests de rules | `functions/src/__tests__/follows-rules.test.ts` — 38 tests, 2 describes nuevos |
| Repositorio | `follow_repository.dart` — `followersOf` / `watchFollowersOf` |
| Providers | `follow_list_providers.dart` — `followListUidsProvider`, `followListProvider`, key + parseo |
| Pantalla | `follow_list_screen.dart` |
| Contadores | `stat_tile.dart` (`onTap` opcional), `public_profile_stats_row.dart` |
| Ruta | `router.dart` — `_followListRoute`, colgada de `profile/:uid` en **/feed y /home** |
| l10n | 9 claves nuevas × 3 ARBs |

### Decisiones que no son obvias leyendo el diff

**`followersOf` va sin `orderBy`, igual que `followingOf`.** Hay dos índices
compuestos desplegados (`followerUid|followeeUid + status + createdAt DESC`,
verificado con `firebase firestore:indexes`) que permitirían ordenar por más
reciente. No se usa: Firestore **excluye silenciosamente** los documentos a los
que les falta el campo del `orderBy`, y las aristas migradas se escribieron con
Admin SDK, sin pasar por la allowlist de las rules que exige `createdAt`.
Ordenar sin auditar antes esos documentos cambia "la lista está desordenada"
por "a la lista le faltan personas" — peor, y además invisible. **Pendiente:
auditar `createdAt` en las 10 aristas de producción y recién ahí ordenar.**

**El push se arma sobre `matchedLocation`, no sobre `/feed/...` fijo.** El
perfil público está registrado bajo dos ramas y `_ShellScaffold` saca la tab
resaltada del prefijo de la ruta; hardcodear `/feed` haría saltar la tab a FEED
al abrir la lista desde INICIO (mismo patrón que issue #387). Cubierto por
`public_profile_follow_list_nav_test.dart`.

**La key del `TreinoStateSwitcher` incluye la dirección.** Sin eso, pasar de una
lista vacía a la otra lista vacía no cambia de child y el texto queda clavado.

**`StatTile.onTap` es opcional y por default `null`.** Los otros seis usos de
`StatTile` en la app quedan idénticos: sin zona tappable y sin nodo de
semantics de más.

---

## 4. Deploy

| Paso | Resultado |
|---|---|
| Ruleset vivo antes | `d7f10acd-4e2b-4e5e-881d-0b8b34503682` — **byte-idéntico** al `firestore.rules` de `main` |
| Diff local vs vivo | sólo el `allow read` de `follows`; ninguna línea se pierde |
| Deploy | ruleset **`421ba136-ae02-48c4-9a1e-ec0f2e17caca`** |
| Verificación post-deploy | el ruleset vivo es byte-idéntico al archivo del worktree |

`firebase deploy` sigue sin servir: ignora `GOOGLE_APPLICATION_CREDENTIALS` y
prioriza su login guardado. Se desplegó por la API REST de
`firebaserules.googleapis.com` con `scripts/sa-key.json`, igual que en el
cutover de `follow-model`.

`scripts/deploy_rules.js` no alcanza desde un worktree: apunta fijo al
`firestore.rules` del repo principal y despliega sin mostrar diff. Se usaron
dos scripts propios que además **abortan** si el ruleset vivo no es el esperado
(otra sesión desplegó en el medio) o si alguna línea del vivo no está en el
local.

---

## 5. Revisión adversarial

Con la suite entera en verde (4836 tests) se corrió una revisión adversarial
del diff: cinco lentes independientes, y cada hallazgo juzgado por tres
escépticos con la consigna de refutarlo. Sobrevivieron cinco defectos reales.

Tres eran del código de este change y están arreglados en `835a6fa6`, cada uno
con su test verificado en rojo antes del fix:

1. **La fila de la lista hardcodeaba `/feed/profile/{uid}`.** O sea que SALIR
   de la lista reintroducía el mismo issue #387 que ENTRAR evita a propósito.
   El harness del test no lo veía porque montaba la pantalla en una ruta
   plana; ahora usa la forma real (`{rama}/profile/{uid}/follows`), sin la
   cual `matchedLocation` no se parece a producción y el defecto es invisible.
2. **Faltaba `skipLoadingOnReload`.** El provider watchea un stream de
   Firestore, que re-emite al abrir (snapshot de cache y después de servidor) y
   con cada follow/unfollow en vivo. Con el default, cada re-emisión tiraba la
   lista abajo, ponía el spinner de pantalla completa y mandaba el scroll a
   cero aunque el contenido fuera idéntico. El test lo agarra en el frame 1.
3. **El header quedaba en blanco** sin `displayName`, mientras la fila de esa
   misma pantalla dice "Anónimo".

Los otros dos son propiedades de las rules, consecuencia de la decisión de
visibilidad de §1, y **no se tocaron**: son una decisión de producto, no del
implementador. Están documentados con la evidencia completa en un **security
advisory privado**, no acá: este archivo se mergea a un repositorio público y
el detalle serviría de receta.

→ `GHSA-98rm-h7jw-vv2x` (borrador, visible sólo para el equipo).

## 6. Deuda que este change deja anotada, sin tocar

- **`scripts/seed_emulator_full.js` todavía siembra `friendships`, no
  `follows`.** Quedó desactualizado tras el cutover: el emulador arranca sin
  una sola arista, así que **ninguna feature de follows se puede verificar
  localmente** sin sembrar a mano. Es lo primero que conviene arreglar.
- `UserSearchResultTile` usa `GestureDetector` crudo en vez de
  `TreinoTappable`. Es previo a este change; arreglarlo cambia también el
  feedback táctil de la búsqueda de usuarios. El test de la pantalla excluye
  ese subárbol a propósito y lo deja dicho.
- Las listas **no paginan**. Con el volumen actual es una sola query; a escala
  de miles de seguidores hay que paginar la query de `follows` y el batch de
  perfiles. Está explícito en el doc comment de `followListProvider` en vez de
  meter un tope silencioso, que se leería como "está todo".

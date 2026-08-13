# Spec: follow-model — seguimiento asimétrico direccional

## Propósito

Define el comportamiento observable de reemplazar `friendships` (un doc simétrico por par) por `follows/{followerUid}_{followeeUid}` (un doc por arista dirigida), habilitando "A sigue a B sin que B siga a A" y volviendo direccional el gate de visibilidad del tier `PostPrivacy.followers` (ex `friends`). Deriva de `openspec/changes/follow-model/proposal.md` (Locked Decisions LD-01 a LD-10, plan de migración M-00 a M-09 con los pasos M-03a/M-03b/M-08b agregados por la auditoría).

**Fuera de alcance de este spec** (LD-07 de la propuesta): la pantalla de listado de seguidores/seguidos NO se crea en este change — queda para `follow-lists`. Por lo tanto este documento NO especifica estados vacíos ni accesibilidad de esa pantalla, ni una acción de UI dedicada "quitar seguidor" (solo el permiso subyacente, REQ-FOLLOW-008).

## Resumen de Requisitos

| REQ | Tema | Keyword |
|---|---|---|
| REQ-FOLLOW-001 | Doc `Follow` por arista dirigida | MUST |
| REQ-FOLLOW-002 | Wire values de `status` reusados | MUST |
| REQ-FOLLOW-003 | Los 4 estados de relación son representables | MUST |
| REQ-FOLLOW-004 | Seguir cuenta pública → auto-accept | MUST |
| REQ-FOLLOW-005 | Seguir cuenta privada → pending, solo followee acepta | MUST |
| REQ-FOLLOW-006 | Cancelar solicitud enviada | MUST |
| REQ-FOLLOW-007 | Dejar de seguir | MUST |
| REQ-FOLLOW-008 | Borrar arista accepted: cualquiera de los 2 miembros | MUST |
| REQ-FOLLOW-009 | Rename `PostPrivacy.friends`→`followers`, wire intacto | MUST |
| REQ-FOLLOW-010 | Visibilidad direccional de posts/reacciones tier seguidores | MUST |
| REQ-FOLLOW-011 | Feed "SEGUIDORES" filtra por dirección | MUST |
| REQ-FOLLOW-012 | Chat 1-1 direccional: X escribe a Y sólo si Y sigue a X | MUST |
| REQ-FOLLOW-021 | El chat con escritura bloqueada se declara en la UI | MUST |
| REQ-FOLLOW-013 | Contadores correctos en cada transición | MUST |
| REQ-FOLLOW-014 | Migración: cardinalidad `2×accepted + pending`, sin aristas inventadas | MUST |
| REQ-FOLLOW-015 | Migración: `accepted` → dos aristas, `pending` → una; malformados enumerados | MUST |
| REQ-FOLLOW-016 | Migración: contadores recalculados y `followers == following == accepted` | MUST |
| REQ-FOLLOW-019 | Migración idempotente: ni duplica ni pisa ni resucita | MUST |
| REQ-FOLLOW-017 | `friendships` congelada **antes** de la migración, no borrada | MUST |
| REQ-FOLLOW-020 | Ninguna escritura masiva sobre `follows` con las CFs repuntadas | MUST |
| REQ-FOLLOW-018 | Accesibilidad del botón de seguimiento | MUST |

## Requisitos

### REQ-FOLLOW-001 — Documento `Follow` por arista dirigida

La colección `follows` MUST tener un doc por arista, id `{followerUid}_{followeeUid}` (NO ordenado), con campos `followerUid`, `followeeUid`, `members: [followerUid, followeeUid]` (derivado, inmutable), `status: 'pending'|'accepted'`, `createdAt`.

#### SCENARIO-800: Crear arista genera el id determinístico correcto
- GIVEN followerUid='u1', followeeUid='u2'
- WHEN `FollowRepository.request('u1','u2')` se ejecuta
- THEN existe `follows/u1_u2` con `followerUid=='u1'`, `followeeUid=='u2'`, `members==['u1','u2']`
- Capa: unit (`follow_repository_test.dart`)

### REQ-FOLLOW-002 — Wire values de `status` reusados sin drift

`FollowStatus` MUST serializar/deserializar a los mismos strings que `FriendshipStatus` hoy: `'pending'`, `'accepted'` (LD-02).

#### SCENARIO-801: Round-trip fromJson/toJson
- GIVEN `FollowStatus.pending` y `FollowStatus.accepted`
- WHEN se serializan y deserializan
- THEN el valor recuperado es idéntico y el wire es `'pending'`/`'accepted'`
- Capa: unit

### REQ-FOLLOW-003 — Los cuatro estados de relación son representables e independientes

Dado un par de usuarios A y B, el sistema MUST poder representar y consultar de forma independiente: (a) ninguno sigue al otro, (b) A sigue a B pero B no a A, (c) B sigue a A pero A no a B, (d) ambos se siguen mutuamente (dos aristas `accepted` independientes).

#### SCENARIO-802: Asimetría representable
- GIVEN existe `follows/u1_u2` `accepted` y NO existe `follows/u2_u1`
- WHEN se consulta `getEdge('u1','u2')` y `getEdge('u2','u1')`
- THEN la primera devuelve `accepted` y la segunda `null`/ausente
- Capa: unit

#### SCENARIO-803: Mutuo son dos aristas independientes
- GIVEN `follows/u1_u2` y `follows/u2_u1` ambas `accepted`
- WHEN se borra una de las dos
- THEN la otra sigue existiendo intacta
- Capa: rules-jest

### REQ-FOLLOW-004 — Seguir a cuenta pública auto-acepta

Si `userPublicProfiles/{followeeUid}.isProfilePublic != false` (default `true` legacy), crear la arista MUST fijar `status='accepted'` directo, sin paso `pending`.

#### SCENARIO-804: Cuenta pública crea arista ya aceptada
- GIVEN `userPublicProfiles/u2.isProfilePublic == true`
- WHEN u1 sigue a u2
- THEN `follows/u1_u2.status == 'accepted'` de inmediato
- Capa: rules-jest + unit

### REQ-FOLLOW-005 — Seguir a cuenta privada requiere aprobación del followee

Si `isProfilePublic == false`, crear la arista MUST fijar `status='pending'`. Solo `followeeUid` MUST poder transicionar `pending → accepted`; `followerUid` MUST NOT poder auto-aceptarse.

#### SCENARIO-805: Cuenta privada queda pending hasta aprobación
- GIVEN `userPublicProfiles/u2.isProfilePublic == false`
- WHEN u1 sigue a u2 → `follows/u1_u2.status == 'pending'`
- AND u1 intenta transicionarla a `accepted` → rules deniegan
- AND u2 la transiciona a `accepted` → rules permiten
- Capa: rules-jest (equivalente direccional de SCENARIO-132)

### REQ-FOLLOW-006 — Cancelar una solicitud enviada

`FollowRepository` MUST exponer una operación para que `followerUid` borre su propia arista `pending`. `PublicProfileFollowButton` en estado "SOLICITUD ENVIADA" MUST tener `onTap` funcional (hoy `null`, línea 89) que la invoque.

#### SCENARIO-806: Cancelar borra la arista pending propia
- GIVEN `follows/u1_u2.status == 'pending'`, u1 es el follower
- WHEN u1 cancela
- THEN `follows/u1_u2` no existe
- Capa: rules-jest

#### SCENARIO-807: El pill cancela y vuelve a "SEGUIR"
- GIVEN el botón renderizado con edge `pending` donde el usuario actual es follower
- WHEN tapea "SOLICITUD ENVIADA"
- THEN se invoca la cancelación y el botón pasa a estado "SEGUIR"
- Capa: widget (afirmar sobre estado/label, nunca sobre ancho de texto)

### REQ-FOLLOW-007 — Dejar de seguir

`followerUid` MUST poder borrar su propia arista `accepted`. `UnfriendConfirmationSheet` (reusado) MUST mostrar copy "dejar de seguir" vía l10n en vez de "eliminar amistad" hardcodeado.

#### SCENARIO-808: Dejar de seguir borra la arista propia
- GIVEN `follows/u1_u2.status == 'accepted'`, u1 es el follower
- WHEN u1 confirma en `UnfriendConfirmationSheet`
- THEN `follows/u1_u2` no existe
- Capa: rules-jest + widget (confirmación del sheet)

### REQ-FOLLOW-008 — Borrado de arista accepted disponible para cualquiera de los dos miembros

Las rules de `follows/{followId}` MUST permitir `delete` a cualquiera de los dos miembros de una arista `accepted` (no solo al `followerUid`), habilitando a futuro "quitar un seguidor" sin cambios de schema. Este change NO agrega la UI dedicada de "quitar seguidor" (diferida a `follow-lists`, LD-07) — solo el permiso.

#### SCENARIO-809: El followee puede borrar aunque no la haya creado
- GIVEN `follows/u1_u2.status == 'accepted'` (u1 sigue a u2)
- WHEN u2 (followee) borra `follows/u1_u2`
- THEN rules permiten la operación
- Capa: rules-jest

### REQ-FOLLOW-009 — Rename del tier sin tocar el wire

`PostPrivacy.friends` MUST renombrarse a `PostPrivacy.followers` en Dart conservando `@JsonValue('friends')` y `'friends'` en `toJson()`/wire map (LD-05).

#### SCENARIO-810: Wire byte-idéntico tras el rename
- GIVEN `PostPrivacy.followers`
- WHEN se llama `toJson()`
- THEN el resultado es `'friends'` (idéntico al wire pre-rename)
- Capa: unit

### REQ-FOLLOW-010 — Visibilidad de posts y reacciones tier "seguidores" es direccional

`postFriendAccepted(authorUid)` MUST evaluar "¿el lector sigue al autor?" (`exists(follows/{lectorUid}_{authorUid}) && status=='accepted'`), no "¿existe alguna relación?". `reactionPostReadable()` MUST aplicar el mismo criterio.

**Relaciones preexistentes vs. nuevas (sin ambigüedad).** Este gate es agnóstico del origen de la arista, pero su efecto NO es el mismo sobre los dos tipos de relación: toda amistad `accepted` preexistente migra a DOS aristas (REQ-FOLLOW-015), así que el chequeo evalúa `true` en **ambas** direcciones desde el día de la migración — nadie pierde acceso al contenido que ya veía. La asimetría real que este REQ habilita solo se manifiesta en aristas creadas DESPUÉS del flip (un follow nuevo crea una sola arista) o cuando se borra una sola dirección de un par migrado (unfollow parcial). SCENARIO-811/812 prueban el gate en abstracto; SCENARIO-831 fija explícitamente el caso migrado.

#### SCENARIO-811: A sigue a B, B no sigue a A → B no lee los posts tier seguidores de A
- GIVEN `follows/b_a` NO existe (B no sigue a A)
- WHEN B intenta leer un post de A con `privacy=='friends'`
- THEN rules deniegan la lectura
- Capa: rules-jest (`post-privacy-rules.test.ts` reescrito)

#### SCENARIO-812: B sigue a A → B lee los posts tier seguidores de A
- GIVEN `follows/b_a.status=='accepted'`
- WHEN B lee un post de A con `privacy=='friends'`
- THEN rules permiten la lectura
- Capa: rules-jest

#### SCENARIO-813: Reacciones espejan el mismo gate direccional
- GIVEN el mismo par A/B de SCENARIO-811 (B no sigue a A)
- WHEN B intenta reaccionar a un post de A con `privacy=='friends'`
- THEN rules deniegan la escritura de la reacción
- Capa: rules-jest

#### SCENARIO-831: Relación preexistente migrada no pierde acceso en ninguna dirección
- GIVEN una amistad `accepted` preexistente migrada a `follows/a_b` y `follows/b_a`, ambas `status=='accepted'` (REQ-FOLLOW-015)
- WHEN A lee un post de B con `privacy=='friends'` Y B lee un post de A con `privacy=='friends'`
- THEN rules permiten ambas lecturas — el acceso mutuo que existía antes de migrar queda intacto
- Capa: rules-jest

### REQ-FOLLOW-011 — Feed "SEGUIDORES" filtra por dirección

El feed (ex "AMIGOS") MUST mostrar solo posts de cuentas que el usuario actual sigue (`accepted`), sin importar si esas cuentas lo siguen de vuelta.

**Relaciones preexistentes vs. nuevas (sin ambigüedad).** Como cada amistad `accepted` migrada aporta arista en las dos direcciones (REQ-FOLLOW-015), el feed de un usuario con relaciones preexistentes incluye, el día del flip, el mismo conjunto de autores que veía antes de migrar — cero pérdida de contenido. La asimetría de este REQ (sigo a alguien que no me sigue, o al revés) solo aparece con follows creados DESPUÉS de la migración, o cuando se rompe una sola dirección de un par migrado.

#### SCENARIO-814: Feed muestra solo posts de a quienes sigo
- GIVEN el usuario actual sigue a X e Y (`accepted`) pero no a Z, y Z lo sigue a él
- WHEN se carga el feed "SEGUIDORES"
- THEN incluye posts de X e Y y NO incluye posts de Z
- Capa: unit (provider)

#### SCENARIO-832: Post-migración, ninguna amistad preexistente desaparece del feed
- GIVEN un usuario con 3 amistades `accepted` preexistentes, las 3 migradas a follow mutuo (REQ-FOLLOW-015)
- WHEN se carga el feed "SEGUIDORES" sobre el `follows` migrado
- THEN incluye posts de los 3 autores, igual que antes de migrar
- Capa: unit (provider)

### REQ-FOLLOW-012 — El chat 1-1 es direccional: X le escribe a Y sólo si Y sigue a X

**Decisión del dueño (LD-08 / ADR-FOLLOW-005).** El permiso de **escritura** en un chat 1-1 lo da la arista **entrante**: `follows/{destinatario}_{remitente}` con `status=='accepted'`. Dejar de seguir a alguien MUST quitarle a esa persona la escritura hacia quien dejó de seguirla, con **una sola acción**, sin que haga falta ninguna acción de la contraparte.

El gate MUST evaluarse en **dos** superficies:

1. `chats/{chatId}` `create` — quien abre el chat MUST poder mandar el primer mensaje, o sea el otro miembro MUST estar siguiéndolo. Reemplaza a `chatRelationshipOk()`.
2. `chats/{chatId}/messages/{messageId}` `create` — **gate nuevo**. Hoy esta regla exige sólo membresía (`firestore.rules:1167-1170`), así que el permiso se evalúa una única vez, al crear el chat. La asimetría que este REQ define es **dentro del mismo chat** (uno escribe, el otro no) y por lo tanto MUST evaluarse por mensaje: una regla que corre una sola vez no puede producir dos permisos distintos para el mismo documento.

La rama `trainer_link` MUST quedar sin cambios: un chat cuyo doc tiene `linkId` MUST seguir gateado sólo por membresía, en las dos superficies, y `'linkId' in chat` MUST evaluarse **antes** que el lookup de la arista para que el Coach no pague llamadas de acceso extra.

**Lo que NO cambia, y es parte del requisito.** `chats` `read`, `messages` `read` y `chats` `update` (preview y `lastRead`) MUST seguir gateados por membresía. El lado sin permiso de escritura MUST conservar la lectura completa de la conversación y MUST poder marcarla como leída.

**Esta es una restricción NUEVA, no la conservación de una vigente — verificado en el código.** `friendship_repository.dart:150-151` borra el doc de `friendships` y nada más; nada borra ni marca el chat, y `messages/create` no mira la relación. Por lo tanto **hoy eliminar una amistad NO corta los mensajes de un chat ya existente**: los dos siguen escribiéndose y sólo se rompe abrir un chat nuevo. Consecuencia que el dueño **evaluó y aceptó explícitamente** al cerrar la decisión —no un efecto colateral hallado después de implementarla— y que queda declarada (riesgo R12 / A14): un chat preexistente cuyo par no tiene ninguna arista queda **mudo para los dos**, conservando la lectura. Ningún documento de este change debe describir el chat direccional como "equivalente a hoy".

#### SCENARIO-815: Dentro del mismo chat, uno escribe y el otro no
- GIVEN `follows/u1_u2.status=='accepted'` (u1 sigue a u2) y `follows/u2_u1` no existe
- WHEN u2 envía un mensaje al chat 1-1 entre ambos
- THEN rules permiten la escritura — u2 escribe porque su destinatario, u1, lo sigue
- AND cuando u1 envía un mensaje al mismo chat, rules deniegan la escritura
- AND los dos siguen pudiendo **leer** el chat y sus mensajes
- Capa: rules-jest (`chat-relationship-rules.test.ts`, expectativas nuevas — no sólo reseed)

#### SCENARIO-839: Un par migrado desde una amistad aceptada escribe en las dos direcciones
- GIVEN una amistad `accepted` preexistente migrada a `follows/u1_u2` y `follows/u2_u1`, ambas `accepted` (REQ-FOLLOW-015)
- WHEN u1 envía un mensaje Y u2 envía un mensaje en el chat entre ambos
- THEN rules permiten las dos escrituras — el chat de un par migrado queda exactamente como antes de migrar
- Capa: rules-jest

#### SCENARIO-840: Dejar de seguir corta la escritura del otro, no la propia ni la lectura
- GIVEN el par migrado de SCENARIO-839, y u1 borra `follows/u1_u2` (deja de seguir a u2)
- WHEN u2 intenta enviar un mensaje
- THEN rules deniegan la escritura de u2
- AND u1 sigue pudiendo enviar mensajes (persiste `follows/u2_u1`)
- AND u2 sigue pudiendo leer el chat y actualizar su propio `lastRead`
- Capa: rules-jest

#### SCENARIO-841: Un chat preexistente sin ninguna arista queda mudo para los dos y legible para los dos
- GIVEN un chat entre u1 y u2 que ya existe, y ninguna arista `follows` entre ellos en ninguna dirección
- WHEN cualquiera de los dos intenta enviar un mensaje
- THEN rules deniegan la escritura a ambos
- AND ambos siguen leyendo el chat y sus mensajes
- Capa: rules-jest (es la regresión aceptada de R12/A14: hoy este chat funciona)

#### SCENARIO-842: El chat de trainer_link no cambia
- GIVEN un chat cuyo doc tiene `linkId` de un `trainer_links` activo entre sus dos miembros, y ninguna arista `follows` entre ellos
- WHEN el trainer o el atleta envían un mensaje
- THEN rules permiten la escritura, igual que hoy — la rama `linkId` gatea sólo por membresía
- Capa: rules-jest

### REQ-FOLLOW-021 — Un chat donde no se puede escribir tiene que decirlo antes del intento

Consecuencia directa de REQ-FOLLOW-012: la escritura es asimétrica dentro de un mismo chat, así que la UI MUST declarar el estado en vez de dejar que el usuario descubra la restricción con un `permission-denied` al apretar enviar. Dos superficies, las dos con espejo **exacto** de la regla del servidor.

**a) Composer del chat 1-1** (`chat_screen.dart`). Cuando NO existe `follows/{otherUid}_{myUid}` en `accepted`:

- El campo de texto MUST estar deshabilitado (sin foco ni teclado), y el botón de adjuntar media y el de enviar MUST estar deshabilitados con él — si no se puede mandar texto, tampoco media.
- En lugar del composer MUST mostrarse un **aviso inline persistente** que explique **por qué** no se puede escribir. MUST NOT resolverse con un snackbar o un toast: el estado dura hasta que la otra persona vuelva a seguir, y un aviso que se va no comunica algo permanente.
- El historial de mensajes MUST seguir visible y scrolleable, y el `lastRead` MUST seguir actualizándose (REQ-FOLLOW-012: la lectura no se toca).

**b) Botón MENSAJE del perfil público** (`public_profile_screen.dart:245-246`). MUST habilitarse si y sólo si la arista **entrante** (`incomingFollow`) está `accepted`. MUST NOT usarse el OR de las dos direcciones — ése era el espejo de la regla anterior — ni la arista saliente.

El texto exacto del aviso no lo fija este REQ (se cierra con el resto de los ARBs); el comportamiento sí. Cliente y rules MUST cambiar en el mismo slice: un composer habilitado que el servidor rechaza y uno deshabilitado que el servidor aceptaría son el mismo defecto en direcciones opuestas.

#### SCENARIO-843: Sin arista entrante, el composer está bloqueado y explicado
- GIVEN el chat 1-1 con `otherUid`, y `follows/{otherUid}_{myUid}` no existe
- WHEN se renderiza la pantalla de chat
- THEN el campo de texto, el botón de adjuntar y el de enviar están deshabilitados
- AND se muestra el aviso inline explicando el motivo
- AND la lista de mensajes sigue renderizada
- Capa: widget

#### SCENARIO-844: Con arista entrante, el composer funciona normal
- GIVEN el mismo chat con `follows/{otherUid}_{myUid}.status=='accepted'`
- WHEN se renderiza la pantalla de chat
- THEN el composer está habilitado y el aviso inline no se muestra
- Capa: widget

#### SCENARIO-845: El botón MENSAJE se gatea por la arista entrante
- GIVEN un perfil público donde el viewer sigue al target (`outgoing` `accepted`) pero el target NO sigue al viewer (`incoming` ausente)
- WHEN se renderiza el perfil
- THEN el botón MENSAJE está deshabilitado
- AND con `incoming` `accepted` (aunque `outgoing` sea `null`) el botón está habilitado
- Capa: widget

### REQ-FOLLOW-013 — Contadores correctos en cada transición

`followersCount`/`followingCount` de `userPublicProfiles` MUST recalcularse desde `follows` con la misma partición direccional de hoy y MUST actualizarse tras cada transición: request, accept, cancel, unfollow, remove.

#### SCENARIO-816: Aceptar incrementa followersCount del followee y followingCount del follower
- GIVEN u1 sigue a u2 en `pending`
- WHEN u2 acepta
- THEN `followersCount` de u2 y `followingCount` de u1 incrementan en 1
- Capa: unit (Cloud Functions, `maintain-follow-counters` con emulador)

#### SCENARIO-817: Dejar de seguir decrementa ambos contadores simétricamente
- GIVEN `follows/u1_u2.status=='accepted'`
- WHEN u1 deja de seguir a u2
- THEN `followingCount` de u1 y `followersCount` de u2 decrementan en 1
- Capa: unit (Cloud Functions)

### REQ-FOLLOW-014 — Invariante de migración: cardinalidad y ausencia de aristas inventadas

`verify-follows-migration.ts` MUST fallar (exit code ≠ 0) si `count(follows) != 2 × count(accepted bien formadas) + count(pending bien formadas)`, o si existe alguna arista en `follows` cuyo par ordenado no corresponda a un friendship bien formado, o cuya dirección no sea legal para ese origen (`accepted` → ambas direcciones; `pending` → solo la del `requesterId`). *(design §7.3, invariantes V1 y V4)*

**Forma exacta de la igualdad — no admite variantes.** Los docs malformados MUST quedar **fuera del universo contado**, y MUST NOT restarse del resultado. Escribir `2 × count(accepted) + count(pending) − malformados` es aritméticamente falso por dos motivos independientes: (a) desarrollando `A = A_wf + A_mf` y `P = P_wf + P_mf`, la expresión da `2·A_wf + P_wf + A_mf`, o sea **sobrecuenta una arista por cada `accepted` malformada**; (b) un doc malformado por `status` inválido no está en `count(accepted)` ni en `count(pending)`, pero sí se restaría, con lo que **subcuenta**. Cualquier test o aserción escrita con la forma restada MUST corregirse.

**Los dos modos, y cuándo cada uno MUST usarse.** Las invariantes de arriba se evalúan enteras sólo en `--cutover`, que asume que `follows` es **100% producto de la migración**. Esa premisa deja de valer apenas se distribuye la build de M-06b: esa build se corta de la punta de la cadena, así que ya escribe en `follows`, y un solo follow nuevo de un tester hace fallar la cardinalidad y el chequeo de aristas sin origen. Por lo tanto:

- Mientras `follows` esté intacta, la verificación MUST correr en `--cutover`.
- Una vez que hay aristas nuevas legítimas, la re-verificación previa al flip MUST correr en `--delta --manifest apply-{ISO}.json` — el manifiesto que emitió el `--apply` de M-04 — que evalúa cobertura y legalidad de dirección **restringidas al manifiesto**, forma del doc sobre toda la colección, y contadores almacenados contra recalculados. La cardinalidad global y la simetría `following == followers == deg` MUST NOT evaluarse en ese modo: son exactamente las dos que dejan de ser función del origen cuando hay otro escritor.
- Sobre los pares del manifiesto, en `--delta`, **dos y sólo dos** desviaciones respecto de lo que escribió la migración MUST tratarse como **warning**, no error: que la arista **ya no exista** (el usuario la borró: unfollow si migró `accepted`, cancelar o rechazar si migró `pending`), y que una arista migrada `pending` **ahora esté `accepted`** con `followerUid`/`followeeUid`/`members`/`createdAt` sin cambios (el followee la aceptó). Son las únicas dos transiciones que las rules de `follows/{followId}` permiten sobre un documento existente (REQ-FOLLOW-005 a REQ-FOLLOW-008). Cualquier otra desviación MUST seguir siendo error: no es alcanzable por un cliente sujeto a rules, así que es evidencia de un bypass o un bug, no de actividad legítima.
- Ninguna tarea de este change MUST exigir `--cutover` en un punto posterior a la distribución de la build: ahí es **insatisfacible por construcción**, y una compuerta insatisfacible se termina salteando. *(design §7.1.1b, §7.3.1)*

#### SCENARIO-818: Verificación falla si el conteo no cierra
- GIVEN 40 friendships `accepted` bien formadas, 10 `pending` bien formadas y 2 malformadas → esperadas `2×40 + 10 == 90` aristas
- AND `count(follows)==89`
- WHEN corre `verify-follows-migration.ts`
- THEN sale con exit code ≠ 0 y reporta la discrepancia
- Capa: unit (script Node/TS)

#### SCENARIO-824: Verificación falla ante una arista inventada
- GIVEN una arista `follows/u9_u8` cuyo par no existe en `friendships`
- WHEN corre `verify-follows-migration.ts`
- THEN sale con exit code ≠ 0 e identifica la arista sin origen
- Capa: unit (script de verificación, fixture inyectada)

#### SCENARIO-846: El modo `--delta --manifest` no falla ante un unfollow o un accept legítimos, y sigue fallando ante cualquier otra mutación
- GIVEN un manifiesto de M-04 con un par migrado `accepted` (dos aristas) y un par migrado `pending` (una arista)
- WHEN, después del `--apply`, un usuario borra una de las aristas `accepted` del par mutuo (unfollow) Y el followee acepta la arista `pending` (transición `pending → accepted`, resto de campos intacto)
- AND corre `verify-follows-migration.ts --delta --manifest apply-{ISO}.json`
- THEN sale con exit code 0, y el reporte lista las dos mutaciones como warning, no error
- AND si en cambio una arista `pending` del manifiesto aparece con `createdAt` alterado estando presente, o una arista `accepted` del manifiesto sigue presente pero con `status` distinto de `accepted`, el script sale con exit code ≠ 0
- Capa: unit (script de verificación, fixture inyectada)

### REQ-FOLLOW-015 — Invariante de migración: `accepted` → dos aristas, `pending` → una, malformados enumerados

Cada `friendship` `accepted` bien formada MUST migrar a **DOS** aristas (`follows/{A}_{B}` y `follows/{B}_{A}`, ambas `status=='accepted'`, ambas con el `createdAt` del origen). Cada `pending` MUST migrar a **UNA** sola, `follows/{requesterId}_{otro}`, y la inversa MUST NOT existir (LD-06 revisada / ADR-FOLLOW-013). El script MUST NUNCA inferir dirección: docs sin `requesterId`, con `members.length != 2` o con `requesterId ∉ members` MUST listarse como malformados en `--dry-run` y excluirse del `--apply`.

#### SCENARIO-819: Friendship accepted migra a follow mutuo
- GIVEN `friendships/u1_u2` con `requesterId=='u1'`, `status=='accepted'`
- WHEN corre la migración con `--apply`
- THEN existen `follows/u1_u2` **y** `follows/u2_u1`, ambas `status=='accepted'` y con el mismo `createdAt` que el origen
- Capa: unit (script de migración)

#### SCENARIO-825: Friendship pending migra a una sola arista direccional
- GIVEN `friendships/u1_u2` con `requesterId=='u1'`, `status=='pending'`
- WHEN corre la migración con `--apply`
- THEN existe `follows/u1_u2.status=='pending'` con el mismo `createdAt`, y **NO** existe `follows/u2_u1`
- Capa: unit (script de migración)

#### SCENARIO-820: Doc malformado se reporta y se excluye
- GIVEN un doc en `friendships` sin `requesterId`
- WHEN corre la migración en `--dry-run`
- THEN aparece en la lista de malformados y no se crea arista para él en `--apply`
- Capa: unit (script de migración)

### REQ-FOLLOW-016 — Invariante de migración: contadores recalculados y simétricos sobre lo migrado

Los contadores MUST recalcularse tras la migración (M-05, obligatorio): con follow mutuo `followersCount` y `followingCount` **cambian de valor** respecto de los almacenados antes de migrar, así que la igualdad "antes == después" deja de ser el criterio.

`verify-follows-migration.ts` MUST fallar (exit code ≠ 0) si, para algún usuario presente en alguna friendship bien formada, no se cumple:
`followingRecalc(uid) == followersRecalc(uid) == count(amistades accepted bien formadas de uid)` **y** los valores almacenados en `userPublicProfiles/{uid}` MUST coincidir con los recalculados. Usuarios sin doc en `userPublicProfiles` se reportan como warning y NO hacen fallar el chequeo (misma política que la CF y el backfill). *(design §7.3 V6, §7.4)*

**Ventanas en las que el recálculo se pisa solo, y cómo se cierran (auditoría C5).** `maintainFollowCounters` es un `onDocumentWritten` sobre `friendships` hasta el deploy de CFs de M-08, y `countAcceptedFor` lee `friendships`. Por lo tanto:

- El backfill de M-05 MUST correr con `friendships` **ya congelada** (REQ-FOLLOW-017): con el origen vivo, cualquier amistad creada, aceptada o borrada después de M-05 dispara la CF vieja, que recomputa con el split por `requesterId` y **devuelve ese par a los valores previos a la migración**, sin que nadie vuelva a mirar porque la verificación ya pasó.
- El backfill MUST volver a correrse, con su verificación de contadores, **inmediatamente después del deploy de CFs** (M-08b) y antes de dar el flip por cerrado: entre la publicación de la build nueva y ese deploy, las aristas que escriben los clientes actualizados no las cuenta nadie.

**M-08b MUST existir como paso ejecutado, no como herramienta disponible.** Las dos ventanas son distintas y el freeze sólo cierra una: el freeze impide que **la fuente vieja escriba** (que la CF vieja recompute sobre `friendships` y pise el backfill); nada impide que **la fuente nueva escriba sin oyente** (aristas en `follows` mientras las CFs siguen apuntando a `friendships`). Y la CF repuntada sólo recomputa los pares que reciban un evento **posterior**, así que un par que se movió durante la ventana y después queda quieto conserva el contador viejo indefinidamente. El procedimiento MUST ser: `backfill --dry-run` → revisar delta → `--apply` → `--dry-run` de nuevo, que MUST reportar **0 perfiles fuera de sync**; ese último dry-run **es** la aserción V6b. No se invoca `verify --delta` acá porque ese modo exige un manifiesto (design §7.3.1) y las aristas nuevas las escribieron clientes, no un `--apply` de script.

#### SCENARIO-833: El recálculo se mantiene estable hasta el repunte de las CFs
- GIVEN `friendships` congelada y los contadores recalculados sobre `follows` (M-05 aplicado)
- WHEN se intenta cualquier escritura sobre `friendships` desde un cliente
- THEN la escritura es denegada, la CF vieja no se dispara y los contadores recalculados no se alteran
- Capa: rules-jest (denegación) + unit de CF (la CF no recibe evento si no hay write)

#### SCENARIO-821: Falta una de las dos direcciones y la verificación la atrapa
- GIVEN una fixture donde un `accepted {u1,u2}` migró solo a `follows/u1_u2` (falta `follows/u2_u1`)
- WHEN corre `verify-follows-migration.ts`
- THEN `followingRecalc(u2) != count(accepted de u2)` y `followersRecalc(u1) != count(accepted de u1)`, y el script sale con exit code ≠ 0
- Capa: unit (script de verificación, fixture inyectada)

#### SCENARIO-826: Una pending con la dirección invertida se atrapa aunque los contadores no se muevan
- GIVEN una fixture donde un `pending` con `requesterId=='u1'` migró como `follows/u2_u1`
- WHEN corre `verify-follows-migration.ts`
- THEN sale con exit code ≠ 0 (las pending no mueven contadores; lo detecta el chequeo direccional de REQ-FOLLOW-015)
- Capa: unit (script de verificación, fixture inyectada)

#### SCENARIO-827: Contadores no recalculados hacen fallar la verificación
- GIVEN `follows` migrada correctamente pero `userPublicProfiles` con los valores previos a la migración
- WHEN corre `verify-follows-migration.ts`
- THEN sale con exit code ≠ 0 e indica que falta correr M-05
- Capa: unit (script de verificación, fixture inyectada)

#### SCENARIO-837: M-08b reconcilia las aristas que se escribieron sin oyente
- GIVEN aristas creadas por clientes actualizados entre la distribución de la build (M-06b) y el repunte de CFs (M-08), y esos pares sin ningún evento posterior
- WHEN se corre `backfill-follow-counters.ts --dry-run` inmediatamente después del deploy de CFs
- THEN reporta perfiles fuera de sync (la CF repuntada no los recomputó: nunca recibió un evento de ellos)
- AND tras `--apply`, una segunda corrida en `--dry-run` reporta **0 perfiles fuera de sync**
- Capa: unit (backfill, fixture inyectada) + checklist de apply (evidencia de que el paso corrió)

### REQ-FOLLOW-019 — La migración es idempotente y no revierte decisiones del usuario

`migrate-friendships-to-follows.ts` MUST poder correrse más de una vez sin duplicar, pisar ni resucitar aristas: MUST usar doc ids determinísticos y MUST NOT sobrescribir una arista existente.

**La guarda por par MUST ser asimétrica por modo.** El mismo estado observado —"el par tiene algunas de sus aristas esperadas, no todas"— significa cosas **opuestas** a los dos lados del flip, así que una guarda única tiene que estar mal en uno de los dos modos:

- **Con `--since`** (delta sweep post-flip): si **alguna** arista del par ya existe, el par entero MUST saltearse como `already-migrated` y MUST NOT escribirse nada, ni siquiera la dirección faltante. Ahí "falta una dirección" significa **que un usuario dejó de seguir**, y recrearla revertiría una decisión de privacidad (LD-04).
- **Sin `--since`** (corrida inicial): sólo se saltea si están **todas**. Si están **algunas pero no todas**, las faltantes MUST irse a `toCreate` y el par MUST reportarse en `partialPair` como warning ruidoso, con exit 0. Ahí una dirección faltante **no puede** ser un unfollow: el cliente que los produce (PR3c) todavía no está publicado, y `follows` es 100% producto de la migración. Sin esta asimetría, un batch de 400 que muere a la mitad deja la migración incompleta **reportando éxito**.

*(design §7.2 G1, ADR-FOLLOW-014)*

**Qué es M-09 después de adelantar el freeze (auditoría C3).** Con `friendships` congelada antes de M-04 (REQ-FOLLOW-017) no queda ninguna escritura sobre el origen que absorber, así que en el camino normal M-09 MUST correr en `--dry-run` y MUST reportar **cero** aristas a crear. Un `toCreate` no vacío es un **incidente** —típicamente el cascade de borrado de cuenta, que usa admin SDK y por lo tanto no está sujeto a rules— y MUST investigarse a mano antes de aplicar nada. La idempotencia que este REQ exige sigue siendo obligatoria: es la red que hace inofensiva una re-corrida accidental y la que permite re-migrar tras un rollback.

#### SCENARIO-828: Segunda corrida sobre un estado COMPLETO es un no-op
- GIVEN una migración ya aplicada y **completa** — las dos aristas de cada `accepted` y la única de cada `pending` presentes
- WHEN se vuelve a correr con `--apply`
- THEN el plan tiene 0 aristas a crear, se ejecutan 0 writes y el exit code es 0
- Capa: unit (script de migración)
- **Nota**: "completo" es parte del GIVEN. Sobre un estado **parcial** la segunda corrida SÍ escribe, y debe hacerlo (SCENARIO-838): reanudabilidad e idempotencia son propiedades distintas y las dos hacen falta.

#### SCENARIO-829: El delta sweep no resucita un unfollow posterior al flip
- GIVEN un `accepted {u1,u2}` ya migrado, y `follows/u2_u1` borrada después del flip porque u2 dejó de seguir a u1
- WHEN se vuelve a correr la migración con `--apply --since <ISO del run de M-04>`
- THEN el par se reporta como `already-migrated`, `follows/u2_u1` NO se recrea y `follows/u1_u2` no se toca
- Capa: unit (script de migración)
- **Nota de contraste, deliberada**: el `--since` es parte del GIVEN, no un detalle. Sin `--since` la misma fixture produce el resultado **opuesto** por diseño — ver SCENARIO-838. Un test escrito sin el flag estaría verificando la corrida inicial y afirmando lo contrario de lo que ésta debe hacer.

#### SCENARIO-838: La corrida inicial completa un par que quedó a medias
- GIVEN una corrida inicial de M-04 interrumpida a mitad de un batch: el `accepted {u1,u2}` tiene `follows/u1_u2` pero le falta `follows/u2_u1`, y `follows` todavía es 100% producto de la migración
- WHEN se reintenta la migración con `--apply` **sin** `--since`
- THEN `follows/u2_u1` se crea, el par se reporta en `partialPair` como warning ruidoso, y el exit code es 0
- AND `follows/u1_u2` NO se toca
- Capa: unit (script de migración)

#### SCENARIO-830: Una arista divergente se reporta y no se pisa
- GIVEN `follows/u1_u2` con `status=='accepted'` y el friendship de origen en `pending`
- WHEN corre la migración con `--apply` **sin** `--since` (corrida inicial)
- THEN la arista se reporta como divergente, NO se sobrescribe, y el script sale con exit code ≠ 0
- AND corriendo con `--since` (delta sweep post-flip) la misma divergencia se reporta como **warning** con exit code 0, porque ahí es actividad legítima del usuario — `follows` es más nueva que la `friendships` congelada
- Capa: unit (script de migración)

### REQ-FOLLOW-017 — `friendships` queda congelada ANTES de la migración, y no se borra

Las rules de `friendships/{friendshipId}` MUST denegar `create`/`update`/`delete` y MUST seguir permitiendo `read`. El freeze MUST desplegarse **antes** de la primera corrida de la migración con `--apply` (M-03b, antes de M-04), **no** junto al flip del gate de lectura (M-07). Ningún paso de este change MUST borrar la colección `friendships` (LD-03).

**Por qué el orden es parte del requisito, y no un detalle operativo (auditoría C3).** El script de migración solo **crea** aristas (REQ-FOLLOW-019: doc ids determinísticos, `batch.create()`, nunca pisa ni borra). Un borrado de una amistad ya migrada, ocurrido después de `--apply` y antes del freeze, **no se propaga**: las dos aristas sobreviven al origen y los dos usuarios se siguen viendo los posts tier seguidores después de que uno revocó. Es phantom access (LD-04) y es invisible para la verificación en su modo relajado, porque el chequeo de aristas huérfanas solo es exhaustivo en `--cutover`. Congelar antes elimina la ventana en vez de intentar detectarla: no hay reconciliación de borrados en ningún script de este change, y no debe agregarse una.

Consecuencia aceptada y explícita: entre el freeze y la adopción de la build nueva, seguir / dejar de seguir / aceptar quedan fuera de servicio en **cualquier** build. El `read` sobre `friendships` no se toca, así que el gate de lectura vigente en ese momento sigue funcionando y ninguna lectura se degrada.

#### SCENARIO-822: Escritura denegada post-freeze, lectura permitida
- GIVEN las rules con el freeze desplegado
- WHEN cualquier usuario intenta crear/actualizar/borrar un doc en `friendships`
- THEN rules deniegan la operación
- AND una lectura sobre el mismo doc sigue permitida
- Capa: rules-jest

#### SCENARIO-834: El freeze precede a la primera escritura de la migración
- GIVEN el registro de deploys y el manifiesto que emite el `--apply` de la migración
- WHEN se audita el orden de ejecución
- THEN el timestamp del deploy de rules con el freeze es anterior al del primer `--apply`
- AND el gate de lectura de posts todavía apunta a `friendships` en ese momento (el freeze no arrastra el flip)
- Capa: checklist de apply (evidencia documental, no test automatizado)

#### SCENARIO-835: Un borrado en el origen no puede dejar aristas huérfanas
- GIVEN una amistad `accepted` ya migrada a sus dos aristas
- WHEN un cliente intenta borrar el doc de `friendships`
- THEN la operación es denegada, así que no existe estado en el que el origen esté borrado y las aristas vivas
- Capa: rules-jest

### REQ-FOLLOW-020 — Ninguna escritura masiva sobre `follows` ocurre con las Cloud Functions repuntadas

`notifyOnFollow` y `maintainFollowCounters` son triggers `onDocumentWritten` sobre el path de la colección. Repuntados a `follows`, **cada arista que escriba un script dispara una notificación push real** ("empezó a seguirte", por relaciones de hace meses) y una recomputación de contadores de 4 queries + transacción, en carrera con el backfill.

Toda corrida de `migrate-friendships-to-follows.ts` con `--apply` MUST ejecutarse **antes** del deploy de Cloud Functions que las repunta a `follows`. Si un incidente obligara a un `--apply` posterior, `notifyOnFollow` MUST deshabilitarse antes de la corrida y rehabilitarse después, y los contadores MUST quedar en manos del backfill, no de la CF.

La solución MUST ser de **orden de deploy**, no de marcado: agregarle a la arista un campo que las CFs ignoren rompería la allowlist cerrada de 6 keys que rules valida en el `create` y que la verificación exige literal (design V5), o sea que obligaría a cambiar schema, rules y verificación para resolver un problema de secuencia.

#### SCENARIO-836: Las escrituras de la migración no generan notificaciones ni recálculos en vivo
- GIVEN la migración corriendo con `--apply`
- WHEN se auditan los timestamps del manifiesto de escritura contra los del deploy de funciones
- THEN el manifiesto es anterior al deploy que repunta las CFs a `follows`
- AND ninguna notificación de follow se emitió durante la ventana de escritura
- Capa: checklist de apply (evidencia documental) + revisión de logs de la CF

### REQ-FOLLOW-018 — Accesibilidad del botón de seguimiento

`PublicProfileFollowButton` MUST usar `TreinoTappable` (no `GestureDetector`) en sus 4 estados (`SEGUIR`/`SIGUIENDO`/`SOLICITUD ENVIADA` cancelable/`ACEPTAR`), y cada estado MUST exponer un label semántico distinguible para lectores de pantalla, coincidente con el texto visible.

#### SCENARIO-823: Cada estado expone un semantics label distinto
- GIVEN los 4 estados posibles de la arista respecto del usuario actual
- WHEN el botón renderiza cada uno
- THEN el semantics label difiere entre los 4 estados y coincide con el texto visible
- Capa: widget (semantics finder, sin medir texto)

## Requisitos superados en `openspec/specs/feed-data-layer.md`

Este change reemplaza el dominio `Friendship` documentado en `feed-data-layer.md`. Mapeo para reconciliar en `sdd-archive`:

| REQ existente | Estado | Reemplazado por |
|---|---|---|
| REQ-PFM-004 (Friendship model fields) | REMOVED | REQ-FOLLOW-001 |
| REQ-PFM-005 (FriendshipStatus wire) | REMOVED | REQ-FOLLOW-002 |
| REQ-PFM-006 (Friendship doc ID sorted) | REMOVED | REQ-FOLLOW-001 (id direccional, no ordenado) |
| REQ-PFM-008 (FriendshipRepository ops) | REMOVED | REQ-FOLLOW-001, 004–008 |
| REQ-PFM-010 (rules friendships/{id}) | REMOVED | REQ-FOLLOW-004, 005, 008, 017 |
| REQ-PFM-002 (PostPrivacy wire, parcial) | MODIFIED | REQ-FOLLOW-009 (solo el miembro `friends`; `gym`/`public` intactos) |

(Reason: `Friendship`/`FriendshipStatus`/`FriendshipRepository` y sus rules quedan reemplazados por `Follow`/`FollowStatus`/`FollowRepository` y las rules de `follows/{followId}`. El código Dart se retira de `lib/` al final del flip (M-08). La colección `friendships` y su lectura NO se borran — ver REQ-FOLLOW-017 — solo el requisito de spec se remueve, no el dato.)

**Sobre el chat**: verificado que **ningún spec vigente de `openspec/specs/` documenta el gate de relación del chat** — `chatRelationshipOk` sólo vive en `firestore.rules` (comentario `QA-CHAT-004`) y en `chat-relationship-rules.test.ts`. Por lo tanto REQ-FOLLOW-012 y REQ-FOLLOW-021 no superan ningún REQ existente: **crean** la especificación de esa conducta, que hasta ahora estaba sólo en el código. Es un dato para `sdd-archive`: no hay nada que reconciliar, hay algo nuevo que archivar.

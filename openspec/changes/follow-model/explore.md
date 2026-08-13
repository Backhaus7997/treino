# Exploración: follow-model

Consolidado de 4 lentes independientes (modelo-datos, rules-seguridad, backend-funciones, ui-superficie). Los hallazgos citados con archivo:línea fueron reverificados contra el código actual; donde dos lentes discrepaban en la lectura de un mismo hecho, lo digo explícito en vez de elegir en silencio.

## 1. Problema

### Lo que YA funciona (no tocar)

- **Aprobación estilo Instagram**: cuenta pública → auto-accept; cuenta privada → `pending`, y solo el destinatario (no el `requesterId`) puede aceptar. Server-side lo hace cumplir `firestore.rules` con `get()` sobre `userPublicProfiles/{uid}.isProfilePublic` (default `true` para legacy). Hay test dedicado a la denegación de self-accept (SCENARIO-132).
- El toggle de privacidad (`ProfilePrivacyToggleTile`) y el campo `UserPublicProfile.isProfilePublic` están completos.
- Los contadores `followersCount`/`followingCount` (Cloud Function `maintainFollowCounters`) y las notificaciones (`notifyOnFriendship`) YA razonan en términos direccionales usando `requesterId` como "quién sigue a quién" — no necesitan reescritura de lógica para este cambio, solo de collection path si se migra el schema.

### Lo que está roto

- **El modelo de datos no puede representar asimetría post-aceptación.** `Friendship` es un doc por par (`friendships/{sortedDocId(uidA,uidB)}`) con un único `status`. Una vez `accepted`, `acceptedFriendsOf()`/`watchAcceptedFriendsOf()` devuelven la contraparte sin mirar `requesterId` (`friendship_repository.dart:87-100,173-185`). No existe "A sigue a B pero B no a A": es matemáticamente imposible con este schema, no un bug de UI. Esto es un **blocker de diseño**, no algo resoluble solo tocando pantallas.
- **El gate de lectura de posts tier `friends` es simétrico**, no direccional: `postFriendAccepted()` solo chequea `exists()+status=='accepted'`, sin mirar `requesterId` (`firestore.rules:536-542`, replicado en `reactionPostReadable()` para reacciones, `firestore.rules:643-651`). Cualquier accepted friendship habilita lectura completa en ambos sentidos.
- **No se puede cancelar una solicitud enviada**: el pill "SOLICITUD ENVIADA" tiene `onTap: null` literal (`public_profile_follow_button.dart:89`, dentro del bloque 85-90). Si mandaste una solicitud por error, no hay forma de deshacerla desde la UI.
- **No existe ninguna pantalla de seguidores/seguidos** en toda la app. Confirmado por las rutas reales bajo `/feed` (`lib/app/router.dart:604` en adelante): `post/:postId`, `create`, `profile/:uid`, `search`, `notifications`, `friend-requests` — nada de listado de conexiones. Los números SEGUIDORES/SIGUIENDO en el perfil (`PublicProfileStatsRow`) son `StatTile` puros, sin gesto alguno.
- **Copy inconsistente**: backend (`notify-friendship.ts:141-145`) ya dice "te envió una solicitud de seguidor" / "empezó a seguirte" / "aceptó tu solicitud". La UI sigue en "amistad": `UnfriendConfirmationSheet` dice literal `'¿Eliminar amistad con $friendDisplayName?'` con botones `'CANCELAR'`/`'ELIMINAR'` sin l10n (`unfriend_confirmation_sheet.dart:55,69,79`), y el inbox se titula "SOLICITUDES DE AMISTAD" (`intl_es_AR.arb`).

### Decisión de producto ya tomada (dueño)

Un post tier "solo amigos" pasa a verlo **mis seguidores** (quienes me siguen a mí). El tier se debería renombrar de `friends` a algo tipo `followers` — pero ver §4 sobre por qué NO conviene tocar el wire value.

## 2. Estado actual del sistema

### Modelo de datos

`Friendship` (`lib/features/feed/domain/friendship.dart:15-23`): `id`, `uidA`, `uidB`, `status` (`pending`|`accepted`), `requesterId`, `members: [uidA, uidB]`, `createdAt`. Doc id = `sortedDocId(uidA, uidB)` (orden lexicográfico, línea 30-31) — **un solo doc por par**, sin importar cuántas "aristas" de seguimiento existan lógicamente.

`FriendshipRepository` (`lib/features/feed/data/friendship_repository.dart`) — 9 métodos públicos:

| Método | Líneas | Qué hace |
|---|---|---|
| `request()` | 27-62 | Crea `friendships/{sortedDocId}`; `pending` o `accepted` directo según `otherIsPublic` |
| `accept()` | 71-84 | `pending→accepted`; bloquea self-accept si `requesterId==myUid` |
| `acceptedFriendsOf()` | 87-100 | `where members arrayContains uid && status==accepted` → UIDs, sin filtrar dirección |
| `allOf()` | 107-110 | Mismo query sin filtro de status — exclusión bulk (sugerencias) |
| `watchPendingRequestsFor()` | 119-129 | Stream de `pending` donde `uid` NO es requester (inbox) |
| `pendingRequestsFor()` | 133-140 | Versión future del anterior |
| `delete()` | 150-152 | Delete físico — es el MISMO método para cancelar, rechazar y dejar de seguir |
| `getByPair()`/`watchByPair()` | 157-169 | Get/stream único sobre `sortedDocId` |
| `watchAcceptedFriendsOf()` | 173-185 | Stream del mismo query que `acceptedFriendsOf()` |

8 consumidores mapeados: `friendship_providers.dart`, `public_profile_follow_button.dart`, `friend_request_inbox_tile.dart`, `suggested_users_providers.dart`, `public_profile_providers.dart`, `post_providers.dart` (gatea tier `friends` solo con `status==accepted`, sin dirección — `post_providers.dart:150-164`), `feed_screen_providers.dart` (`myFriendsFeedProvider` = posts de TODOS los accepted, sin distinguir quién sigue a quién).

### Rules

- `postFriendAccepted()` (`firestore.rules:536-542`) gatea lectura de posts `privacy=='friends'` (línea 553-554) y reacciones vía `reactionPostReadable()` (línea 643-651, +1 `get()` extra sobre el post). Costo: 2 get-type calls por post, 3 por reacción. Simétrico — no mira `requesterId`.
- `chatRelationshipOk()` (`firestore.rules:1112-1123`) exige `exists(friendships/{chatId}) && status=='accepted'` **con el mismo `chatId` determinístico** que usa el chat 1-1. `chat_repository.dart:42` (`chatIdFor`) replica byte a byte la lógica de `sortedDocId`: mismo sort + join `'_'`. Confirmado leyendo ambos archivos — es el mismo algoritmo, no una coincidencia de nombres.
- Índice compuesto único sobre `friendships`: `{members arrayContains, status ASC}` (`firestore.indexes.json:130-137`). Lo usan `acceptedFriendsOf`/`watchAcceptedFriendsOf`/`pendingRequestsFor`/`watchPendingRequestsFor` y `countAcceptedFor` en la CF. `allOf()` usa solo `members arrayContains` (single-field, autoindexado).
- Cobertura de tests de las reglas propias de `friendships/{friendshipId}` (create pending/auto-accept, SCENARIO-132 self-accept denial, delete): **verificado que NO corre en CI**. `scripts/rules_test/rules.test.js` sí las testea (SCENARIO-131, 132, 271) pero `scripts/test_rules.sh:15` lo marca explícito `'NOT part of CI'`. El job `functions-test` de `.github/workflows/ci.yml` corre `npm --prefix functions test` (jest sin filtro, TODOS los `__tests__/*.test.ts`) — eso sí incluye `chat-relationship-rules.test.ts` y `post-privacy-rules.test.ts`, pero **ambos siembran el doc `friendships` con `withSecurityRulesDisabled` (bypass admin)**, verificado leyendo ambos archivos (`chat-relationship-rules.test.ts:57-72`, `post-privacy-rules.test.ts:67-86`). O sea: las reglas de escritura/aceptación de `friendships` en sí mismas no las ejercita ningún test que corra en CI, solo tests manuales fuera del pipeline. Tampoco hay ningún job de CI que corra `firebase deploy --only firestore:rules` — el deploy es manual post-merge (confirmado: `ci.yml` solo tiene jobs `analyze-and-test`, `functions-build`, `functions-test`, ninguno con `deploy`).

### Cloud Functions

- `maintainFollowCounters` (`functions/src/social/maintain-follow-counters.ts`) — ya se autodenomina "Follow model (asymmetric)" en el header (línea 25). `countAcceptedFor()` parte `accepted` friendships en `following`/`followers` por `requesterId==uid`, recompute-from-scratch por transacción (no `FieldValue.increment`, decisión documentada como QA-507 para tolerar redelivery at-least-once). No requiere reescritura de lógica.
- `notifyOnFriendship` (`functions/src/notifications/notify-friendship.ts`) — 3 ramas direccionales (`request-received`/`auto-followed`/`request-accepted`), copy ya en clave "seguidor". No requiere reescritura.
- `sweepFriendships` (cascade de borrado de cuenta, `functions/src/cascade/friendships.ts`) — borra por `members array-contains uid`, sin filtrar dirección; con doc-ids direccionales necesitaría dos queries (`followerUid==uid` OR `followeeUid==uid`).
- `backfill-follow-counters.ts` (script one-shot, dry-run por defecto) recomputa counters con la misma regla direccional — reusable tal cual para reconciliar tras la migración.
- Antecedente de riesgo real (no de este cambio, pero mismo patrón que se repetiría): `REACTION_TYPES` en `maintain-reaction-counters.ts:29-35` debe espejar a mano el enum Dart y la allowlist de rules — ya causó un bug silencioso al renombrar `strong`→`like` (contador quedaba en cero sin error visible). El wire value `PostPrivacy.friends` está en la misma situación: hardcodeado en el enum Dart, en la allowlist create/update de rules, en `postFriendAccepted`/`reactionPostReadable`, y en la query de `post_repository.dart:151` — 4 lugares mantenidos a mano.

### UI

- `PublicProfileFollowButton` — 4 estados (`public_profile_follow_button.dart:65-99`): `SEGUIR` (sin doc) / `SIGUIENDO` (accepted) / `SOLICITUD ENVIADA` (pending, yo requester, **onTap: null línea 89**) / `ACEPTAR` (pending, yo destinatario). Usa `GestureDetector` crudo en vez de `TreinoTappable` (línea 283) — viola AGENTS.md, y este archivo se va a tocar igual en este cambio.
- Botón MENSAJE del perfil (`public_profile_screen.dart:245-246`) usa el mismo flag simétrico `status==accepted` para habilitar DMs. Sin follow asimétrico esto es correcto; con follow asimétrico deja de significar "nos seguimos mutuamente" salvo que se resuelva junto con el modelo de datos.
- `UserSearchResultTile` es deliberadamente sin botones de acción (REQ-UPS-010/ADR-UPP-10) — no extenderlo para la pantalla nueva de seguidores/seguidos, conviene un tile hermano.
- `UnfriendConfirmationSheet` es reusable tal cual para "dejar de seguir" — mismo constructor genérico, solo cambia copy.
- Marcador `i18n: Fase W2` aparece 7 veces en `public_profile_screen.dart` (líneas 195, 204, 267, 286, 434, 469, 496) dentro de la superficie que este cambio va a tocar igual.
- `intl_es.arb` está desincronizado del template (`intl_es_AR.arb`) — le faltan keys ya usadas en código (ej. las del inbox).

## 3. Blast radius

| Capa | Componente | Impacto | Evidencia |
|---|---|---|---|
| Datos | `friendships` collection + `Friendship` model | Rediseño de schema (ver §4) | `friendship.dart:15-23` |
| Datos | 9 métodos de `FriendshipRepository` | Todos requieren revisión de query shape | `friendship_repository.dart` |
| Rules | `postFriendAccepted()` / `reactionPostReadable()` | Gate de lectura debe volverse direccional | `firestore.rules:536-542,643-651` |
| Rules | `chatRelationshipOk()` | Acoplado al mismo doc-id que friendships — ver riesgo §5 | `firestore.rules:1112-1123` |
| Rules | Reglas CRUD propias de `friendships/{id}` | Sin cobertura en CI hoy; hay que migrar y **agregar** cobertura CI, no solo migrar | `scripts/test_rules.sh:15`, `functions/package.json:9` |
| Índices | `firestore.indexes.json:130-137` | Índice único queda huérfano; hacen falta nuevos compuestos por `followerUid`/`followeeUid` | — |
| Functions | `maintainFollowCounters`, `notifyOnFriendship` | Solo cambio de collection path, lógica ya es direccional | `functions/src/social/*`, `functions/src/notifications/*` |
| Functions | `sweepFriendships` | Pasa de 1 query a 2 (por dirección) | `functions/src/cascade/friendships.ts` |
| Functions | `backfill-follow-counters.ts` | Reusable para reconciliación post-migración | — |
| Cliente | `post_providers.dart`, `feed_screen_providers.dart` | Gate de tier `friends`/feed AMIGOS debe filtrar por dirección | `post_providers.dart:150-164` |
| UI | `public_profile_follow_button.dart` | Agregar cancelar solicitud; ya tiene el método (`delete`), falta wirearlo | línea 89 |
| UI | Pantalla nueva de seguidores/seguidos | No existe, hay que crearla completa (ruta, provider, tile) | — |
| UI | `unfriend_confirmation_sheet.dart`, inbox, ARBs | Copy "amistad"→"seguidor" | varios |
| Tests | `friendship_repository_test.dart` | 33 test()/group(), reescritura mayor | — |
| Tests | `chat-relationship-rules.test.ts`, `post-privacy-rules.test.ts` | Seedean friendship simétrico sin `requesterId` en el caso de post-privacy — se rompen con schema nuevo | `post-privacy-rules.test.ts:79-87` |
| Tests | `maintain-follow-counters.test.ts`, `backfill-follow-counters.test.ts`, `cascade/friendships.test.ts`, `notify-friendship.test.ts`, `user-public-profiles-rules.test.ts` | Tocan friendships directa o indirectamente | — |

## 4. Approaches considerados

**A. Colección nueva `follows/{followerUid}_{followeeUid}` con doble escritura (coexistencia sin downtime).**
Doc-id direccional (no ordenado), un doc por arista. Migración: (1) contar docs actuales con `.count()` — no hay cifra de producción disponible por exploración estática, es el paso 0 obligatorio; (2) backfill script (patrón `backfill-follow-counters.ts`) que lee TODO `friendships` y escribe los `follows` derivados con `--apply`, sin borrar `friendships`; (3) dual-write en `FriendshipRepository`/nuevo `FollowRepository` — nuevas mutaciones van a ambas colecciones; (4) deploy de rules nuevas para `follows` MANTENIENDO las de `friendships` intactas; (5) flip de lectura (providers, rules, chat) a `follows`; (6) backfill de deltas; (7) verificación de paridad; (8) recién ahí dejar de escribir en `friendships`, y borrarla como paso separado posterior.
Costo de rules idéntico (2 get-type calls, mismo patrón `exists()`-then-`get()`) — no hay riesgo de pegarle al límite de 10 get()/exists() por doc.
Pros: rollback en 3 puntos (revertir flip de lectura, revertir dual-write, o `friendships` intacta hasta el paso 8), cero downtime, ownership de escritura trivial por regla (solo el follower crea/borra su propio follow; solo el followee acepta uno dirigido a él, sin `diff().affectedKeys()` complejos sobre un doc compartido).
Contras: ventana de coexistencia con riesgo real de "phantom access" (ver §5), duplica temporalmente el volumen de escritura, requiere script de conteo previo inexistente hoy.

**B. Migración big-bang (un solo deploy, sin ventana de coexistencia).**
Mismo schema destino (`follows/{followerUid}_{followeeUid}`), pero backfill + flip de rules + flip de cliente en el mismo deploy, con `friendships` borrada inmediatamente después.
Pros: sin ventana de "phantom access" simétrico-vs-asimétrico, menos complejidad de código (no hay dual-write que mantener ni luego remover).
Contras: sin proyecto de staging separado (`firebase.json` confirma un único proyecto `treino-dev`, sin staging/prod split), cualquier bug en el backfill o en las rules nuevas rompe producción en caliente, sin rollback más que restaurar desde backup manual. Dado el antecedente ya documentado ("verde en emulador, muerta en el teléfono", `openspec/changes/routine-model-seed/verify-report.md:18,42`, mismo patrón de deploy manual sin gate de CI), este approach concentra el riesgo justo donde el repo ya demostró fragilidad.

**C. Extender `Friendship` en el lugar (agregar un segundo status/campo direccional al mismo doc, sin colección nueva).**
Ej. dos campos `statusAB`/`statusBA` o un array de estados por dirección dentro del mismo doc compartido.
Pros: no rompe el doc-id compartido con el chat (`chatRelationshipOk` seguiría funcionando sin cambios), no requiere migración de colección ni backfill de docs nuevos, cambio más chico.
Contras: mismo problema que ya identificó la lente rules-seguridad para los `lastRead` de chat pero peor — dos usuarios escribiendo campos distintos del MISMO doc compartido con concurrencia real (aceptar/rechazar simultáneo), reglas de rules más frágiles que un doc por arista, y no resuelve el índice: seguiría habiendo un solo doc por par así que "listar mis seguidores" o "listar a quién sigo" requiere igual un query direccional nuevo con field explícito, no solo leer `members`. No aísla ownership de escritura por usuario tan limpiamente como un doc-por-arista.

**Ninguna lente propuso mantener el modelo actual "tal cual" como opción viable** — las 4 coinciden en que el blocker de asimetría (§1) no es resoluble sin tocar el schema. La recomendación de 3 de las 4 lentes (modelo-datos, rules-seguridad, backend-funciones) converge en A.

**Sobre el wire value `PostPrivacy.friends`**: recomendación de NO renombrarlo a `'followers'` en el wire aunque el label visible cambie a "SEGUIDORES". Es un cambio de wire format — Firestore ya tiene posts con `privacy:'friends'` guardado literal, y aparece hardcodeado en 4 lugares (enum Dart, allowlist create/update de rules líneas 587/624, comparaciones en `postFriendAccepted`/`reactionPostReadable`, query de `post_repository.dart:151`). Cambiarlo exige reescribir cada post existente; mantenerlo y solo cambiar semántica de acceso + label visible evita tocar la colección `posts` por completo.

## 5. Riesgos

1. **[Más importante] Migración irreversible / phantom access durante la coexistencia.** Si las rules nuevas hacen OR entre `friendships` legacy (simétrico) y `follows` nueva mientras ambas están vivas, un usuario que deja de seguir (borra solo su doc `follows`) puede seguir siendo visto porque el `friendships` legacy accepted sigue resolviendo `true`. Esto no es una hipótesis: se deriva directo de la semántica actual de `postFriendAccepted` combinada con cualquier estrategia de lectura OR durante la transición. Hay que decidir en sdd-propose/design si la ventana de coexistencia lee SOLO de `follows` (con backfill previo garantizado completo) o si el OR es aceptable con un TTL corto y monitoreado.
2. **Chat 1-1 acoplado al mismo doc-id que friendships — y las lentes DISCREPAN sobre si esto es un problema a resolver o un statu-quo a preservar.** La lente modelo-datos lo marca `[blocker]`: dice que hay que resolverlo en sdd-propose antes de tocar el schema, porque con doc-ids direccionales ya no hay "un único doc por par" que el chat pueda referenciar. La lente rules-seguridad coincide en que es una pieza "no listada en los hechos verificados" que requiere decisión de producto explícita (¿el chat pasa a exigir mutual-follow, dos `exists()`, o se desacopla del modelo social?). La lente backend-funciones en cambio sostiene que **no es un problema nuevo**: dado que hoy seguir una cuenta pública ya auto-acepta y habilita chat inmediato, dejarlo simétrico sería "una decisión deliberada, no un bug a arrastrar" — y no lo marca como blocker. Verificado el código: `chatIdFor` (`chat_repository.dart:42`) replica byte a byte `sortedDocId`, así que técnicamente CUALQUIER approach con doc-ids direccionales (A o B de §4) rompe la asunción `exists(friendships/{chatId})` salvo que se resuelva explícitamente. No elijo una lectura por el otro acá — es una pregunta abierta real para el dueño (ver §6), no un hecho consolidado.
3. **Sin cifra de volumen de producción.** No hay script ni doc con el número de `friendships` existentes; el paso 0 (`.count()` aggregation query, 1 read-unit, soportado por `firebase-admin ^12.0.0`) es obligatorio antes de diseñar tiempos de backfill.
4. **Cobertura de rules de `friendships`/`follows` fuera de CI.** Verificado: hoy ningún test que corre en CI ejercita las reglas CRUD propias de `friendships/{id}` (solo `scripts/rules_test/rules.test.js`, marcado explícitamente fuera de CI). Si la migración solo traslada esa misma falta de cobertura a `follows/{id}`, se reproduce el antecedente "verde en emulador, muerta en el teléfono" con el gate MÁS crítico del cambio (quién puede crear/aceptar un follow). Este cambio debería, como mínimo, sumar esas reglas al runner de CI — no es opcional, es la superficie que más directamente controla acceso.
5. **Ningún job de CI hace `firebase deploy --only firestore:rules`.** El deploy de rules es siempre manual post-merge (confirmado en `ci.yml` y documentado en `functions/README.md:76-80`). Cualquier ventana entre "el código de la app espera rules nuevas" y "las rules se deployaron a mano" es una ventana de outage o de acceso incorrecto — hay que secuenciar el rollout (rules antes que cliente) explícitamente en tasks, no asumirlo.
6. **`REACTION_TYPES`-style drift.** El wire value `friends`/`followers` y cualquier nuevo enum de `follows.status` quedan mantenidos a mano en 3-4 lugares (Dart, rules, CF) sin nada que los sincronice — ya pasó una vez con reacciones (`strong`→`like`, contador quedó en cero silenciosamente). Vale la pena un test de paridad explícito si se toca alguno de estos enums.
7. **Fan-out sin cap.** `feedForFriends` no tiene límite superior de following y escala linealmente (`ceil(N/chunkSize)` queries en paralelo + resort client-side). No es un problema introducido por este cambio, pero la migración toca esta función igual — de paso, corregir `chunkSize=10`→`30` (el cap real de Firestore `whereIn` que ya usan `user_public_profile_repository.dart`, `exercise_repository.dart`, `gym_repository.dart`) es gratis en el mismo PR.
8. **Superficie de tests grande.** Mínimo: `friendship_repository_test.dart` (33 tests), `chat-relationship-rules.test.ts` (8 tests, uno siembra friendship accepted explícitamente), `post-privacy-rules.test.ts` (seedea SIN `requesterId`, prueba acceso bidireccional — hay que reescribirlo, no solo actualizarlo, agregando el caso "seguido pero no sigo de vuelta no debería leer"), más `maintain-follow-counters`, `backfill-follow-counters`, `cascade/friendships`, `notify-friendship`, `user-public-profiles-rules`.

## 6. Preguntas abiertas para el dueño

1. **Chat 1-1 con follow asimétrico**: ¿el chat pasa a requerir mutual-follow (ambos se siguen, dos `exists()`) o se desacopla del modelo social y usa su propio criterio de habilitación? Ver riesgo §5.2 — las lentes no coinciden en si esto ya está resuelto por la práctica actual o es una decisión pendiente.
2. **Ventana de coexistencia (approach A)**: durante la migración, ¿lectura OR entre `friendships` legacy y `follows` nueva (riesgo de phantom access), o corte limpio a lectura-solo-`follows` una vez que el backfill esté verificado al 100%?
3. **Botón MENSAJE**: hoy se habilita con `status==accepted` simétrico. Con follow asimétrico, ¿DMs requieren mutual-follow, o alcanza con que cualquiera de los dos siga al otro?
4. **Confirmación del approach**: ¿A (colección nueva + doble escritura, recomendado por 3/4 lentes) o alguna variante de C (extender el doc actual) por menor blast radius, aceptando la fragilidad de concurrencia que eso implica?
5. **Alcance de este cambio**: ¿entra la pantalla de seguidores/seguidos (inexistente hoy) en este mismo change, o se reserva para uno posterior una vez asentado el modelo de datos?

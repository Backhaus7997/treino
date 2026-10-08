# Costos de Storage y los topes de UGC

Por qué existen los topes de subida, de dónde salen los números, y por qué están
implementados en tres capas en vez de una.

Hay **dos** topes, y aunque comparten arquitectura no comparten eje:

| | `customExerciseVideos` (§3) | `chatMedia` (§7) |
|---|---|---|
| Forma del uso | Biblioteca: pocos archivos, se arma una vez | Flujo: bytes continuos, para siempre |
| Eje del tope | **Cantidad** de archivos | **Bytes totales** |
| Por archivo (free / techo) | 25 / 100 MB | video 25 / 50 MB · imagen 15 MB |
| Total (free / techo) | — (`cantidad × por-archivo` alcanza) | 250 MB / 5 GB |

La §7 explica por qué copiar el eje de la §3 habría sido un error.

Hermano de [`paywall-alumno-suelto.md`](./paywall-alumno-suelto.md) (que fija el
PRECIO) y de [`security.md`](./security.md) (que explica las reglas de Storage).
Acá se trata el COSTO.

---

## 1. La medición — 2026-09-10, bucket `treino-dev.firebasestorage.app`

**1.964 objetos, 1.135,78 MB.** Antes de proponer un tope hubo que medir, porque
la intuición sobre dónde estaban los bytes resultó equivocada.

| Prefijo | Objetos | MB | Qué es |
|---|---:|---:|---|
| `exerciseVideos` | 1.122 | 859,17 | Catálogo del sistema |
| `exercises` | 817 | 142,42 | Catálogo del sistema |
| `chatMedia` | 15 | 127,18 | UGC |
| `postPhotos` | 1 | 3,81 | UGC |
| `customExerciseVideos` | 3 | 2,84 | UGC |
| `avatars` | 3 | 0,19 | UGC |
| `athleteFiles` | 3 | 0,17 | UGC |

Usuarios: **58** (53 `athlete`, 5 `trainer`). 13 con `subscription` de PF, **0**
con `athleteSubscription` — consistente con que el webhook del alumno todavía no
existe.

Tres conclusiones, y ninguna era la esperada:

1. **El 88% del bucket es catálogo del sistema.** `exerciseVideos` + `exercises`
   son 1.001 MB de costo FIJO, que no escala con usuarios. El UGC real son
   134 MB → **2,31 MB por usuario promedio**. No hay incendio hoy.
2. **`customExerciseVideos` tiene UN dueño, y es un PF.** Tres videos, 2,84 MB.
   **Ningún alumno subió jamás uno.** La adopción del lado que el paywall
   gatearía es cero — que es exactamente la mejor hora para poner un tope,
   porque no le saca nada a nadie.
3. **`chatMedia` es 45x más grande con el mismo agujero.** 127 MB en 15 objetos
   = **8,5 MB por objeto**, y `storage.rules` le daba los mismos 100 MB/archivo
   sin tope de cantidad ni gate de paywall. Y el chat genera bytes de forma
   continua, mientras que una videoteca de tutoriales se arma una vez.
   **Cerrado el 2026-09-14 — ver §7**, con un eje distinto al de acá.

### Cómo repetir la medición

No hay `gcloud` ni ADC en las máquinas del equipo. El camino es:

1. `firebase login` (el refresh token queda en
   `~/.config/configstore/firebase-tools.json` — **no** en `%APPDATA%`).
2. Intercambiarlo en `oauth2.googleapis.com/token` con el `client_id` /
   `client_secret` públicos de `firebase-tools`.
3. Pegarle a `storage.googleapis.com/storage/v1/b/<bucket>/o` (paginado con
   `nextPageToken`) y a la REST de Firestore para cruzar uid → `role`.

El token de acceso dura una hora y el refresh pide reauth cada tanto
(`invalid_rapt`); si la medición se corta a la mitad, es eso.

---

## 2. El modelo de costo — por qué el egress manda

Precios de Firebase Storage (GCS Standard):

| Línea | Precio |
|---|---|
| Almacenamiento | USD 0,026 / GB-mes |
| **Descarga (egress)** | **USD 0,12 / GB** |

**El egress es 4,6x el precio de guardar ese mismo GB un mes entero**, y se
cobra *cada vez que alguien le da play*.

Y acá no hay nada que lo amortigüe: los videos se sirven por la URL
`?alt=media&token=` que emite `getDownloadURL()`, que es **GCS directo, sin CDN
ni capa de cache adelante** (ver [`security.md`](./security.md) §3.1 y el bloque
`customExerciseVideos` de `storage.rules`). La app siempre renderiza desde la URL
persistida en `users/{uid}/customExercises/{id}.videoUrl`.

De ahí la conclusión que ordena todo el diseño:

> **El tope POR ARCHIVO es la palanca principal, no el de cantidad.** El tamaño
> del archivo es lineal en las DOS líneas de costo; la cantidad sólo en la de
> almacenamiento. Bajar el cap de 100 a 25 MB divide por 4 el egress de cada
> reproducción, sin tocar nada más.

### El umbral que importa

Con la proporción esperada de ~70 usuarios free por pagador y un margen de
**ARS 3.833/mes por pagador**, el punto en que el costo del free anula el margen
es:

```
ARS 3.833 / 70 = ARS 54,75 por usuario free por mes
```

Es un presupuesto chico. A modo de referencia, ese monto compra del orden de
**1 a 2 GB almacenados permanentemente**, o **0,2 a 0,5 GB de descarga mensual**,
según el tipo de cambio. Un solo video de 100 MB re-mirado tres veces al mes se
lo come entero.

---

## 3. Los topes

| | Alumno free | PF / alumno que paga o está vinculado |
|---|---:|---:|
| MB por archivo | **25** | 100 |
| Videos | **3** | 50 |

**25 MB por archivo** sale de la medición, no del dedo: el archivo más grande
jamás subido pesa **2,59 MB** y la mediana es **0,13 MB**. 25 MB es 10x el máximo
real observado — headroom de sobra para un tutorial de un minuto en 720p. El cap
histórico de 100 MB era **39x** el máximo observado: un techo decorativo.

**3 videos** espeja `kFreeMaxOwnRoutines`: el free tiene «tres de lo suyo». Peor
caso 75 MB permanentes.

**No hay tope de MB TOTALES**, y es deliberado: `cantidad × por-archivo` ya acota
el total. Una tercera perilla agregaría superficie de configuración por 25 MB de
ahorro.

**50 videos** para todos los demás es techo anti-abuso, no palanca de conversión:
5 GB ≈ USD 0,13/mes. Sin él, una cuenta `trainer` —que el paywall del alumno NO
gatea, y con razón— tiene subida ilimitada de 100 MB. Nadie legítimo se acerca:
el PF con más videos del proyecto tiene 3.

---

## 4. Dónde vive el enforcement, y por qué en tres capas

Se evaluaron las tres opciones. **Ninguna alcanza sola**, y no son alternativas:
son capas con trabajos distintos.

| Capa | Qué puede | Qué NO puede |
|---|---|---|
| `storage.rules` | Cap por archivo (`request.resource.size`) y tier, preventivamente | **Contar objetos** — no hay agregación en las reglas de Storage |
| Cloud Function | Contar, y borrar el excedente | Prevenir: `onObjectFinalized` corre **después** de que los bytes entraron y se pagaron |
| Cliente | Avisar antes de gastar datos móviles | Ser ley — es evadible |

### El diseño resultante

```
subida  ──►  storage.rules          ──►  bucket  ──►  onObjectFinalized
             (preventivo: tamaño          │            (reactivo: recuenta,
              + tier + lee el contador)   │             borra el excedente,
                     ▲                    │             escribe el contador)
                     └────────────────────┴──── users/{uid}.customExerciseVideoUsage
```

- **La regla es el gate preventivo.** Atrapa el caso normal —subida secuencial,
  que es lo que hace el editor— *antes* de que los bytes entren, que es la única
  forma de no pagarlos. Lee el tier de `users/{uid}.athletePaywallEnforced` y el
  conteo de `users/{uid}.customExerciseVideoUsage.count` con **un solo**
  `firestore.get()`.
- **La CF es la red reactiva.** El contador va atrasado por construcción: el
  trigger corre después del aterrizaje. Un cliente que dispare N subidas en
  paralelo las evalúa todas contra el mismo valor viejo y se pasa por el tamaño
  de la ráfaga. La CF cierra esa carrera **borrando el excedente**, conservando
  los archivos MÁS VIEJOS (que son los que los docs `customExercises` ya
  referencian por `videoUrl`).
- **El cliente es UX.** Chequea la cantidad *antes* de abrir la galería (si ya
  está en el tope no hay nada que pueda elegir que entre) y el tamaño *después*
  de elegir (recién ahí se sabe cuánto pesa). Sin esto el alumno manda hasta
  100 MB de datos móviles para que el servidor los rechace al final.

### Por qué el contador se denormaliza

Es el mismo patrón —y el mismo motivo— que `athletePaywallEnforced`: **lo que la
regla no puede resolver, lo resuelve una CF y la regla lee la conclusión.**

El campo es **CF-write-only**, pineado en `firestore.rules` en el create *y* en
el update de `users/{uid}`. Sin ese pin el bypass es una sola escritura
—`{customExerciseVideoUsage: {count: 0}}`— y el tope de cantidad deja de existir
para quien la mande.

La CF **recuenta** el prefijo en vez de incrementar: la entrega de Eventarc es
at-least-once, y un `FieldValue.increment()` se aplicaría dos veces en una
redelivery dejando el contador desviado para siempre. Un contador de cuota
desviado hacia abajo es un tope que no existe. Mismo criterio que
`maintainReactionCounters` (W-SOCIAL-COUNTERS-01).

### La trampa del PF

`athleteEntitlementProvider` (cliente) **devuelve `free` para un PF**: no mira
`role`, y un PF no tiene ni vínculo como alumno ni `athleteSubscription`.

Eso hoy es inofensivo porque los gates del paywall viven en pantallas
athlete-only. Pero **`CustomExerciseEditorScreen` es superficie COMPARTIDA** — la
abren el alumno (`profile_screen.dart`, `exercise_picker_sheet.dart`) y el PF
(`trainer_profile_view.dart`, Coach Hub web).

Por eso el enforcement se cuelga de `athletePaywallEnforced` y **no** del
provider del cliente: `resolveAthletePaywallEnforced` corta en
`if (userData?.role !== "athlete") return false`. Colgarlo del provider le
rompería la videoteca a todos los PF el día que se prenda
`kAthletePaywallEnabled`.

---

## 5. Los cuatro números viven en cuatro lugares

No hay nada que los sincronice. Si cambiás uno, cambiá los cuatro:

| Lugar | Qué |
|---|---|
| `lib/features/paywall/domain/athlete_entitlement.dart` | Las constantes `kFreeMaxCustomExerciseVideos`, `kFreeMaxCustomExerciseVideoBytes`, `kMaxCustomExerciseVideos`, `kMaxCustomExerciseVideoBytes` |
| `storage.rules` | Los literales del ternario en `videoWriteAllowed()` |
| `functions/src/storage/custom-exercise-video-quota.ts` | `FREE_MAX_VIDEOS`, `FREE_MAX_VIDEO_BYTES`, `MAX_VIDEOS`, `MAX_VIDEO_BYTES` |
| `functions/src/__tests__/custom-exercise-video-quota.test.ts` | Escritos literales en los asserts **a propósito**, para que un tope movido sin querer dé rojo |

Si la copia de la CF fuera **más permisiva** que la regla, la CF no borraría lo
que la regla ya rebotó y no pasaría nada. Si fuera **más estricta**, borraría
videos que la regla aceptó: el usuario ve la subida exitosa y el archivo
desaparece solo. Ese es el modo de falla caro, y es mudo.

Ojo también con `lib/l10n/*.arb`: los topes de paywall en TREINO han vivido
escritos a mano dentro de las cadenas. Los mensajes de este gate se arman desde
las constantes, así que ese eje no se puede desincronizar — pero antes de mover
cualquier otro tope, `rg` el número literal en los `.arb`.

---

## 6. Qué queda pendiente

- **`postPhotos` y `athleteFiles`** no se revisaron en este pase.
- **Región del trigger**: las CFs se despliegan en **`us-east1`**, que es la
  EXCEPCIÓN a ADR-PN-005 (todo lo demás vive en `southamerica-east1`). Un
  trigger de Storage tiene que estar en la región del BUCKET o el deploy falla
  con *«A function in region X cannot listen to a bucket in region Y»* — rojo
  ruidoso, no bug silencioso.

  > ⚠️ **`treino-dev.firebasestorage.app` está en `US-EAST1`**, medido contra la
  > API de GCS el 2026-09-15. Esta misma viñeta decía `southamerica-east1`
  > citando `roadmap.md` Fase 1 Etapa 6 — **y esa línea del roadmap es falsa**.
  > De ahí lo copiaron los dos módulos de CF, y por eso el primer deploy se
  > cayó. Si algún día se migra el bucket, verificalo contra la API y no contra
  > el roadmap.
- **El tope de cantidad no tiene grandfathering**, igual que el resto del
  paywall del alumno. Hoy no hace falta (ningún alumno tiene videos), pero si
  eso cambia antes de prender `kAthletePaywallEnabled`, revisá el mismo problema
  que documenta `athlete-paywall-enforced.ts` para las rutinas de 4 y 5 días.

---

## 7. El tope de `chatMedia` — mismo agujero, otro eje

`chatMedia/{chatId}/{userId}/{file}` tenía cap de tamaño por archivo (imágenes
< 15 MB, videos < 100 MB) y **ninguno de total**, y ningún gate del paywall lo
tocaba. Es el mismo agujero de la §3 sobre el prefijo donde de verdad se acumula
el UGC.

### 7.1 La medición — 2026-09-14, bucket `treino-dev.firebasestorage.app`

**15 objetos, 127,18 MB** (45x los bytes de `customExerciseVideos`).

| | obj | MB | p50 | p90 | max |
|---|---:|---:|---:|---:|---:|
| **video** | 5 | 114,20 | 9,12 | 9,25 | **90,31** |
| **imagen** | 10 | 12,98 | 0,122 | 2,76 | 4,98 |
| total | 15 | 127,18 | 1,50 | 9,12 | 90,31 |

Tres hechos que ordenan todo el diseño, y ninguno era el esperado:

1. **Un solo archivo es el 71% del prefijo.** Un MP4 de **90,31 MB** del 18/06.
   El segundo video más grande pesa **9,25 MB**: un salto de 10x. Los videos son
   el **89,8%** de los bytes; las imágenes, el 10,2%.
2. **El chat que concentra el 94% de los bytes NO es un chat de Coach.**
   `linkId=false`, sin `kind` ⇒ rama **social**. De 17 chats del proyecto, **10
   son sociales, 3 inquiry y 4 de Coach**.
3. **Nada del lado del cliente amortigua el tamaño.** `chat_screen.dart` sube
   con `picker.pickVideo(source: ImageSource.gallery)`, **sin `maxDuration` y
   sin transcode**. Las fotos van con `imageQuality: 80`, pero `image_picker`
   **en web ignora `imageQuality`** — de ahí el PNG de 4,98 MB del Coach Hub,
   que es el máximo de imágenes.

Se repite con el mismo camino de la §1.

### 7.2 Por qué el eje NO es «por chat» ni «por cantidad»

**«Por chat» no acota nada.** `firestore.rules` (~1973) tiene **tres** ramas de
creación de chat —vínculo de Coach, social direccional (REQ-FOLLOW-012) e
inquiry (#637: cualquier atleta a cualquier PF publicado)—, así que la cantidad
de chats por usuario **no tiene techo**. N chats × tope-por-chat = sin techo. Y
no es teórico: la superficie sin vínculo ya es la mayoría de los chats, y es
donde está el 94% de los bytes.

**Contar archivos tampoco sirve.** La §3 descarta —con razón— un tope de MB
totales para la videoteca: ahí `cantidad × por-archivo` ya acota. Acá ese
argumento se da vuelta, y el motivo es la forma del uso:

> Un PF con 30 alumnos manda **cientos de archivos por año** legítimamente. El
> tope de cantidad tendría que ser enorme para no romperle el producto, y con la
> cantidad enorme el producto `cantidad × por-archivo` deja de ser un techo
> útil. **Para una biblioteca el eje es cantidad; para un flujo es bytes.**

**Retención por tiempo: descartada, y con evidencia.**

- Los mensajes son **inmutables**: `allow update, delete: if false` sobre
  `chats/{id}/messages`. Borrar el objeto deja el mensaje vivo con un `mediaUrl`
  muerto **para siempre**, sin forma de limpiarlo.
- Los datos la desmienten como tope gradual: antigüedad máxima **87 días**, 95%
  de los bytes >30 días, **0% >90 días**. Un corte a 90 días borra 0 MB hoy y
  120 MB en tres días. Es un acantilado, no una pendiente.
- En un chat PF↔alumno la conversación **es** el registro del coaching. Borrar
  el video de técnica de hace cuatro meses destruye lo que hace valioso al
  producto.

### 7.3 Los números

| | Alumno free | PF / vinculado / pagador |
|---|---:|---:|
| MB por video | **25** | **50** *(antes 100)* |
| MB por imagen | 15 | 15 |
| **MB totales en chats** | **250** | **5.120** (5 GB) |

**El múltiplo del cap por archivo se saca contra el p90, no contra el máximo**, y
ésa es la diferencia con la §3. Allá el máximo observado (2,59 MB) era un dato
sano y 25 MB era 10x eso. Acá **el máximo observado ES el problema**: contra el
p90 real de 9,12 MB, 25 MB es 2,7x y 50 MB es 5,4x. Los 100 MB históricos eran
11x el p90 — un techo decorativo, y el único archivo que lo aprovechó es el de
90,31 MB. **Bajar el techo a 50 rechaza exactamente ese archivo y ningún otro de
los que existen.**

La imagen queda en 15 MB y **no lleva variante free**, a propósito: el máximo
observado es 4,98 MB, son el 10% de los bytes, y el tope de bytes totales ya
acota lo que las fotos acumulan. Bajarlo es superficie de configuración a cambio
de nada.

**250 MB free** son 2,4x lo que acumuló en tres meses el uploader más pesado del
proyecto (104,88 MB) — y ese uploader es el **trainer**, no un atleta free. A
25 MB por video son ≥10 videos, o cientos de fotos. Cuesta USD 0,0065/mes
almacenado, sobre el presupuesto de ARS 54,75/mes por usuario free de la §2.

**5 GB de techo** cuestan USD 0,13/mes: el mismo costo exacto que el techo de 50
videos de la §3. Anti-abuso, no palanca de conversión — el usuario más pesado
del proyecto tiene 105 MB, el 2% de eso.

> ⚠️ **250 MB es un tope de POR VIDA y hoy no tiene salida.** Los mensajes no se
> borran y la app no tiene UI para liberar media de un chat, así que quien llega
> al tope no puede volver atrás. Por eso 250 y no un número más chico: un gate
> sin salida adentro tiene que ser generoso. **El día que exista «liberar
> espacio», este número se puede bajar** — y ése es el follow-up que lo habilita.

### 7.4 Las tres capas, y las dos divergencias

La arquitectura es la de la §4 —regla preventiva + CF reactiva + cliente para
UX— pero dos piezas cambian, y las dos por el mismo hecho: **en el chat, borrar
un objeto rompe un mensaje que no se puede editar.**

**Divergencia 1 — la CF NO borra por tamaño, sólo por total.** `decideQuota` de
`custom-exercise-video-quota.ts` borra cualquier archivo con `size >= maxBytes`
del cap **por archivo**. Copiar eso sería destructivo: el cap por video baja de
100 a 50 MB y el bucket **tiene** ese MP4 de 90,31 MB en una conversación real
de junio — la primera subida de ese usuario después del deploy lo habría
borrado. Por eso acá **el cap por archivo es puramente preventivo y vive sólo en
`storage.rules`**: gobierna lo que ENTRA. La CF gobierna el TOTAL, que es una
magnitud que no cambia de significado cuando se mueve el cap. Los archivos de
legado cuentan sus bytes contra el total, pero no se los señala para borrar.

Eso no deja ningún archivo legítimo huérfano: el cap por archivo (50 MB) es dos
órdenes de magnitud menor que el total (5 GB), así que un solo archivo nunca
puede exceder el total por sí mismo.

**Divergencia 2 — el uid es el TERCER segmento del path.**
`chatMedia/{chatId}/{uid}/…` no tiene un prefijo único por usuario, así que
recontar obliga a enumerar los chats del usuario primero (`chats where members
array-contains uid`) y listar `chatMedia/{chatId}/{uid}/` por cada uno. Es el
mismo camino que ya usa el cascade de borrado de cuenta, y es **completo** porque
`chats` nunca se borra (`allow delete: if false`). Cuesta N+1 llamadas con N =
chats del usuario, y el máximo real medido es 10; la alternativa —listar
`chatMedia/` entero y filtrar— es O(toda la media del producto) por subida.

**Lo que hace tolerable el borrado** es que los dos bubbles ya degradan solos:
`errorWidget` en `chat_image_bubble.dart` y `_VideoErrorPlaceholder` en
`firebase_storage_video_player.dart`. Un objeto ausente pinta un placeholder, no
rompe la pantalla. Y la CF conserva los **más viejos**, así que lo que se borra
es la ráfaga recién enviada —que el que la mandó ve al instante— y no un video
de hace seis meses que no miraría nunca.

**El gate de cliente cuelga de `athletePaywallEnforced`, no del entitlement.**
Ésta es la tercera diferencia, y es la que la §4 documenta como «la trampa del
PF». `athleteEntitlementProvider` **devuelve `free` para un PF** (no mira
`role`). En la videoteca eso es latente y sale bien de casualidad, porque el
provider devuelve el techo estructural mientras `kAthletePaywallEnabled` esté
apagado. Acá no se puede depender de esa casualidad: el chat es superficie
**compartida de uso constante**, y el día que se prenda el interruptor un gate
colgado de aquel provider le mostraría «llegaste al límite» a todos los PF del
producto. El gate lee `users/{uid}.athletePaywallEnforced`, que es **el mismo
campo que lee la regla** — cliente y servidor no pueden discrepar sobre de qué
lado del paywall está alguien. Y no cuesta una lectura extra: el contador y el
tier viven en el mismo documento.

### 7.5 Dónde viven los números

| Lugar | Qué |
|---|---|
| `lib/features/paywall/domain/athlete_entitlement.dart` | `kFreeMaxChatMediaBytes`, `kMaxChatMediaBytes`, `kFreeMaxChatVideoBytes`, `kMaxChatVideoBytes`, `kMaxChatImageBytes` |
| `storage.rules` | Los literales de `chatMediaWriteAllowed()` — los cinco |
| `functions/src/storage/chat-media-quota.ts` | `FREE_MAX_CHAT_MEDIA_BYTES`, `MAX_CHAT_MEDIA_BYTES` — **sólo los de total**, ver la divergencia 1 |
| `functions/src/__tests__/chat-media-quota.test.ts` | Escritos literales en los asserts **a propósito** |

Los `.arb` **no** los duplican: los mensajes del gate reciben los MB por
placeholder (`{maxMb}`, `{fileMb}`, `{remainingMb}`) y se arman desde las
constantes. Ese eje no se puede desincronizar — que es más de lo que se puede
decir del resto del paywall.

### 7.6 Un hallazgo de egress que NO es parte de este tope

`FirebaseStorageVideoPlayer.initState()` llama a `initialize()` **sin gate de
visibilidad ni tap-to-load**. Scrollear un chat baja los primeros bytes de cada
video que pasa por pantalla, sin que nadie le dé play. Las fotos van por
`CachedNetworkImage` y pagan egress una vez por dispositivo; los videos no
tienen esa red. Refuerza el cap por archivo, y da para issue propio.

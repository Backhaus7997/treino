# Diseño técnico: baja-de-correos-promocionales

> Que el usuario pueda dejar de recibir los correos comerciales, con un toggle
> en la app y con un link en el pie de cada uno de esos correos. Cubre tres
> PRs: functions (este documento), la app (§7) y la landing en `treino-app`
> (§8).
>
> ⚠️ Nada de acá se despliega sin OK de un humano. `treino-dev` es producción
> (ver `openspec/AGENTS.md`). El secreto de §5 se crea **antes** de mergear el
> PR de functions (§10).

---

## 1. Problema

`users/{uid}.notificationPrefs.novedades_plan.email === false` frena los mails
comerciales (`emailChannelAllowed`, `functions/src/mail/send-queued-mail.ts`).
Al 2026-10-01 **nadie escribe esa preferencia**: ni la app, ni el Coach Hub, ni
un handler del backend. El pie de los mails dice sólo «Recibís este mail porque
tenés una cuenta en TREINO».

Productores con `prefKey: "novedades_plan"`:

| Productor | Kind | Destinatario |
|---|---|---|
| `subscriptions/athlete-prospect-mail.ts` | `athlete-coverage-lost` | alumno |
| `subscriptions/free-limit-mail.ts` | `free-limit-reached` | alumno |
| `subscriptions/trainer-limit-mail.ts` | `exercise-limit-reached`, `template-limit-reached`, `student-limit-reached` | entrenador |

Y dos mails **sin** `prefKey` que llevan un bloque comercial adentro de un aviso
operativo:

| Productor | Kind | Lo operativo | Lo comercial |
|---|---|---|---|
| `subscriptions/subscription-mail.ts` (`enqueueProspectMail`) | `limit-reached` | «N alumnos quedaron en solo lectura» | «hay planes más grandes» + VER LOS PLANES |
| `auth/codigo-de-verificacion.ts` | `email-code-*` | el código | el bloque de pagos + VER LOS PLANES |

`subscription-grace` y `subscription-downgraded` también tienen CTA de plan, pero
le hablan a un cliente sobre **su** suscripción (regularizar, ampliar): son
transaccionales y no se tocan.

Lo que hoy promete la política de privacidad y no se cumple:

- §7.3 (`docs/legal/politica-de-privacidad.md:327`): «para las comunicaciones
  comerciales la oposición es absoluta».
- §9 (`:376`): «Revocar consentimiento — Desde los ajustes, o escribiéndonos».

## 2. Base legal (verificada en la fuente primaria)

- **Decreto 1558/01, Anexo I, art. 27, párrafo 3.** «En toda comunicación con
  fines de publicidad que se realice por correo, teléfono, correo electrónico,
  Internet u otro medio a distancia a conocer, se deberá indicar, en forma
  expresa y destacada, la posibilidad del titular del dato de solicitar el
  retiro o bloqueo, total o parcial, de su nombre de la base de datos. A pedido
  del interesado, se deberá informar el nombre del responsable o usuario del
  banco de datos que proveyó la información.»
- **Ley 25.326, art. 27, inc. 3.** «El titular podrá en cualquier momento
  solicitar el retiro o bloqueo de su nombre de los bancos de datos a los que se
  refiere el presente artículo.»
- **Disposición DNPDP 4/2009, art. 1.** En las comunicaciones de publicidad
  directa, un aviso con el derecho de retiro o bloqueo, **el mecanismo** para
  ejercerlo, y **la transcripción** de los dos textos de arriba.
- **Disposición DNPDP 4/2009, art. 2.** Si la comunicación **no fue requerida o
  consentida previamente**, advertir que es publicidad y poner «publicidad» en
  el encabezado del correo. **No se implementó en el PR original**: la decisión
  del 2026-10-02 y su implementación están en §9.

Fuentes: `argentina.gob.ar/normativa/nacional/norma-151221/texto` (Disp. 4/2009),
`…/ley-25326-64790/texto`, `…/decreto-1558-2001-70368/texto`.

## 3. Las tres piezas

| Pieza | Dónde | A quién llega | Cuándo es verdad |
|---|---|---|---|
| Toggle «Correos promocionales» | app, Perfil › Privacidad (§7) | alumno y entrenador con la app | con la versión publicada en las tiendas |
| Link en el pie de cada correo comercial | functions (§4-§6) | todos, también quien ya no tiene la app | con el deploy de §10 |
| Página que confirma la baja | `treino-app` (§8) | quien toca el link | antes que el pie (§10) |

El pie **no** menciona el toggle de la app: el mail sale con el deploy, el toggle
llega con la versión de las tiendas, y un pie que apunta a una opción que el
usuario todavía no tiene es una advertencia falsa (AGENTS.md §11.1).

## 4. Flujo

```
sendQueuedMail (mail con prefKey "novedades_plan", destinatario por uid)
  │ token = firmar(uid, prefKey)        ← HMAC, se calcula al enviar
  │ pie: aviso + link + transcripciones
  │   https://gettreino.com/es/correos-promocionales/baja#t=<token>
  ▼
buzón
  └─> página /es/correos-promocionales/baja   (treino-app, sin sesión)
        │ lee #t= del fragmento y lo saca de la barra
        │ muestra un botón; NO hace nada al cargar
        └─> click → bajaDeCorreosPromocionales({token})
              verificar(token) → {uid, prefKey}   o   {status:"invalido"}
              users/{uid}.notificationPrefs.<prefKey>.email = false
              → {status:"listo"}
```

### API pública

| Callable | Entrada | Salida |
|---|---|---|
| `bajaDeCorreosPromocionales` | `{token: string}` | `{status: "listo" \| "invalido"}` |

`onCall`, `southamerica-east1`, sin sesión, **sin App Check** (la llama una
página pública), `maxInstances: 5`, secreto `BAJA_PROMOCIONALES_KEY`.

## 5. Token: HMAC sin estado

```
p   = base64url(prefKey)
u   = base64url(uid)
sig = base64url(HMAC-SHA256(key, "baja-promocionales/v1/" + p + "/" + u))
token = "v1." + p + "." + u + "." + sig
```

Gramática cerrada, chequeada **antes** de calcular nada:
`^v1\.[A-Za-z0-9_-]{1,64}\.[A-Za-z0-9_-]{1,200}\.[A-Za-z0-9_-]{43}$`, y largo
total ≤ 320. Los segmentos van en base64url porque un uid de Auth importado
puede tener puntos; sin codificar, ese uid sería irrepresentable o ambiguo. El
límite de largo corta un input gigante antes de que cueste CPU (mismo criterio
que `baja-por-mail.ts:271-283`).

### 5.1 Por qué no el token guardado de `baja-por-mail`

`subscriptions/mp/token-un-solo-uso.ts` guarda `sha256(token)` con 72 h de vida
y uso único. Para una baja de correos las dos propiedades están mal:

- **Vencer.** El link tiene que funcionar en el mail que se abre dos meses
  después. La norma pide el mecanismo en *toda* comunicación, no en las recientes.
- **Uso único.** Darse de baja dos veces no es un problema; es idempotente.

Sin vencimiento, un token guardado deja un documento por mail con el `uid`
adentro, para siempre, y obliga a sumar la colección al borrado de cuenta. El
HMAC no guarda nada.

### 5.2 Decisiones

- **Secreto propio**, `BAJA_PROMOCIONALES_KEY` (`defineSecret`). No se reusa
  `RESEND_API_KEY` ni `MP_WEBHOOK_SECRET`: una clave, un propósito.
- **El propósito va firmado** (`baja-promocionales/v1/` + `prefKey`): una firma
  de este esquema no sirve para otra cosa, y una de otra cosa no sirve acá.
- **`prefKey` en allowlist**: sólo `novedades_plan`. Un token bien firmado con
  otra clave de preferencia contesta `invalido`; la callable nunca escribe un
  campo que no esté en la lista.
- **Comparación en tiempo constante** (`crypto.timingSafeEqual`, con chequeo de
  largo antes).
- **El `uid` sale del token, nunca del request.** La callable recibe `{token}` y
  nada más.
- **El `uid` tiene que servir como id de documento.** Auth acepta uids de 1 a 128
  caracteres sin mirar el contenido, y `collection("users").doc("a/b/c")` lee la
  barra como separador: apunta a `users/a/b/c`, otro documento. Se rechaza `/`,
  el vacío, `.`, `..` y los reservados por Firestore (`__algo__`) **al firmar**
  (`firmarToken` tira: en `sendQueuedMail` es el caso «el uid no entra en el
  token», ver §6.1 y §6.3) **y al verificar** (`verificarToken` devuelve `null` →
  `invalido`, aunque la firma sea válida).
- **Rotación**: cambiar la versión del secreto invalida todos los links ya
  enviados. Es aceptable sólo ante una filtración, y el prefijo `v1` deja lugar
  para convivir con un `v2`. No se rota por rutina.
- **El `uid` viaja legible en el token** (base64url no es cifrado). No da acceso
  a nada sin sesión, pero es un identificador estable: la página de §8 lo saca
  de la barra antes de cualquier otra cosa y no lo manda a telemetría (§5.3).
- **Un link viejo vuelve a apagar después de prenderlo en la app.** Es
  aceptado, no un descuido: la única acción que habilita es «no me mandes
  correos promocionales», el link sólo existe en un buzón que el dueño ya
  usó para pedirlo, y la página exige un click humano (§5.4). Invalidarlo
  pediría un epoch en el documento del usuario que la app incremente al
  prender, y un link viejo diría «no es válido» a quien quiere darse de baja
  de nuevo — peor para lo que la norma protege.

### 5.3 El token va en el fragmento (`#t=`)

Mismo criterio que `baja-por-mail` §4.2: el fragmento no viaja en el request
HTTP, no queda en los logs de Vercel ni en el `Referer`. **Sí** lo puede leer
cualquier script de la página antes de que se borre de la barra: la página lo
lee y lo borra al montar, y no carga telemetría que capture `location.hash`
(es el mismo riesgo, y la misma mitigación, que el token de `baja-por-mail`,
que es más sensible: da de baja una suscripción).

### 5.4 Click explícito

Los escáneres de correo pre-abren los links (`baja-por-mail` §4.3). Si abrir la
página diera la baja, la daría el escáner. La página muestra un botón y recién
el click llama a la callable.

### 5.5 Anti-enumeración

Una cuenta borrada contesta `listo`, igual que una viva: es cierto (no le vamos a
escribir) y no le cuenta a nadie si la cuenta existe. Nunca se **crea** el
documento: se lee primero (sin documento → `listo`, sin escribir) y la escritura
es un `update`, cuyo `NOT_FOUND` —la cuenta se borró entre la lectura y la
escritura— también se mapea a `listo`.

### 5.6 Replay

El token no vence (§5.1), así que uno válido que se filtre o se reenvíe se puede
repetir sin fin. Si cada llamada escribiera `users/{uid}`, cada una dispararía los
triggers de `users`. Por eso la callable **lee primero**: con
`notificationPrefs.<prefKey>.email === false` ya puesto contesta `listo` **sin
escribir**, y sin escritura no hay triggers. El costo de un replay es una lectura
por llamada. `maxInstances: 5` limita la concurrencia, no el total de llamadas, y
la exención de App Check (`appcheck-enforcement.test.ts`) lo dice así.

El `listo` sin escribir de la cuenta **sin `users/{uid}`** es verdad por el lado
del **envío**: `deleteAccount` borra Firestore antes que Auth, así que la identidad
puede existir sin documento, y sin documento no hay dónde registrar la oposición.
`sendQueuedMail` no manda lo comercial a quien no tiene perfil (§6.1 y §6.3).

## 6. El pie del correo

### 6.1 Cuándo

`sendQueuedMail` lo agrega cuando el documento de la cola trae un `prefKey` de
la allowlist de §5.2 **y** el destinatario es un `toUid` (no un `toAddress`
literal, que no tiene cuenta ni preferencias). El link se calcula al enviar y
**no se persiste** en `mail_queue`.

Si el mail lleva ese `prefKey` y la clave está vacía, el mail **no sale**
(`failed`, `lastError: "sin clave de baja"`, con `logger.error` para que salte
en el monitoreo): un correo comercial sin el mecanismo de baja es justo lo que
la norma prohíbe. Con `defineSecret` el deploy ya falla si el secreto no existe,
así que esto es un cinturón, no el freno principal. El mail perdido no se
reencola (`sendQueuedMail` sólo escucha creaciones): es comercial, y su
productor lo vuelve a mandar en el próximo disparo, pasado el enfriamiento.

Un mail con `prefKey` de la allowlist a un **`toAddress` literal** tampoco sale:
una dirección literal no tiene cuenta a la que apuntar la baja, y un mail con
`prefKey` es comercial de punta a punta, sin versión sin publicidad. Queda
`failed` (`lastError: "sin cuenta para la baja"`) con `logger.error`, igual que
sin clave. (Con `bloqueComercial` y literal, el mail sale sin el bloque, §6.3.)

Lo comercial exige además que **`users/{uid}` exista**: sin documento la oposición
no tiene dónde registrarse (la callable nunca lo crea, §5.5) y el mail saldría
después de que la página dijo «listo». Un mail con `prefKey` de la allowlist y el
documento ausente queda `failed` (`lastError: "sin perfil para registrar la
oposición"`, con `logger.warn`); con `bloqueComercial` sale sin el bloque y sin
pie (§6.3). Los `prefKey` no comerciales (`nueva_solicitud`, `sesion_cancelada`)
conservan su comportamiento: documento ausente → se envía. El documento se lee
una sola vez.

Este fail-closed aplica **sólo a los mails con `prefKey`**, los enteramente
comerciales. Un mail con `bloqueComercial` no falla entero por falta de link:
degrada a «sin bloque y sin pie» (§6.3). Lo mismo vale si el `uid` no entra en la
gramática del token (no pasa con los de Auth, que miden hasta 128): el mail con
`prefKey` queda `failed` (`lastError: "link de baja no representable"`) y el de
`bloqueComercial` degrada. En ningún caso se deja salir la excepción: la
plataforma reintentaría una semana un mail que falla idéntico cada vez.

### 6.2 Qué dice

`renderMail(kind, params, opciones?)` acepta `{ bajaDePromocionales?: string }`
(la URL). Con la opción, el pie lleva, en HTML **y** en texto plano:

1. **Destacado** (BONE `#FFFFFF` a 14px, el color de los titulares y de los
   valores resaltados del cuerpo; el cuerpo y el pie comparten el gris `MUTED`,
   así que «el color del cuerpo» no los distinguía; el link va en MINT y
   subrayado): «Recibís este correo promocional porque tenés una cuenta en
   TREINO. Si no querés recibir más, [dejá de recibir correos promocionales]».
   En texto plano, la URL completa. Reemplaza al «Recibís este mail porque…» del
   pie común.
2. **Chico**: «Ley 25.326, art. 27, inc. 3: "…"» y «Decreto 1558/01, Anexo I,
   art. 27, párrafo 3: "…"», con los textos exactos de §2. Y «Responsable:
   BACKHAUSTIN S.A.S. — CUIT 30-71929587-4» (lo pide la segunda oración del
   párrafo 3, y es el responsable que declara la política).

Sin la opción, el pie queda como hoy. Los mails transaccionales no cambian.

### 6.3 Mails transaccionales con bloque comercial: `bloqueComercial`

Un aviso operativo con un párrafo de venta adentro no se puede frenar entero con
`prefKey`: quien se opuso a lo comercial igual tiene que enterarse de que sus
alumnos quedaron en solo lectura. Lo que se frena es **el bloque**.

El documento de la cola acepta `bloqueComercial?: "novedades_plan"`. Al enviar,
`sendQueuedMail` lee esa preferencia (con la misma regla que `emailChannelAllowed`:
sólo `false` explícito frena) y:

- **apagada** → `renderMail(kind, params, { comercial: false })`: la plantilla
  omite las líneas y el CTA de venta. Sin pie de baja: el mail ya no tiene nada
  comercial.
- **prendida o ausente** (el perfil existe, con la preferencia prendida o sin
  ella) → el mail completo **con el pie de baja de §6.2**: tiene contenido
  comercial, y la norma pide el mecanismo en toda comunicación con fines de
  publicidad. Con el **perfil ausente** se trata como apagada (§6.1).

Se evalúa al enviar, no al encolar, por la misma razón que `prefKey`: si la
persona se opone entre que se encoló y que salió, gana la oposición.

**`prefKey` y `bloqueComercial` son excluyentes.** El tipo del documento de la
cola y el input de `enqueueMail` no admiten los dos juntos: el gate de `prefKey`
frenaría el mail **entero** y se comería justo el aviso operativo que
`bloqueComercial` existe para dejar pasar. Si un documento llega con los dos
igual (no pasó por el tipo), **gana `bloqueComercial`**: se ignora el gate de
`prefKey` y suena `logger.warn`.

**Si el link no se puede armar** (clave de baja vacía, o un `uid` que no entra en
la gramática del token) el mail con `bloqueComercial` **no falla**: sale sin el
bloque y sin pie, igual que con la preferencia apagada, y suena `logger.error`
para el monitoreo. El aviso operativo llega igual y no sale contenido comercial
sin mecanismo de baja. El fail-closed de §6.1 es sólo para los mails con
`prefKey`.

Este cambio lo cablea en `limit-reached` (`enqueueProspectMail`). El mail del
código (`email-code-*`, `auth/codigo-de-verificacion.ts`) lo adoptó en un PR de
seguimiento: cuando lleva el bloque de pagos (`showPlans: "1"`, que ahora solo
mira rol y paywall) sale con `bloqueComercial`, y su plantilla además exige la
URL de baja para mostrar el bloque. Así ese bloque nunca sale sin pie, ni
siquiera desde un documento encolado antes del deploy.

## 7. La app: toggle en Perfil › Privacidad (PR aparte)

- **Dónde**: `lib/features/profile/presentation/privacy_screen.dart`, que ya
  comparten alumno y entrenador. Una segunda tarjeta, separada de la de
  analítica (la de analítica es por dispositivo y su explicación dice «en el
  Coach Hub se configura aparte»; ésta es por cuenta y no puede heredar esa
  frase).
- **Copy** (es_AR): título «Correos promocionales»; subtítulo «Si lo apagás, no
  te mandamos más. Los avisos de tu cuenta te siguen llegando.» Sin «plan»,
  «pago», «suscripción», «oferta» ni «web» (anti-steering 3.1.3, y los scans de
  `test/features/paywall/`). «Los avisos de tu cuenta» es cierto: sólo los mails
  con `prefKey` se frenan.
- **Semántica**: ausente = prendido, igual que el server (`value !== false`).
  Mientras carga o si falla la lectura, el switch se muestra deshabilitado, no
  prendido: «no sé» no es «sí» (ver `valueOrNull` en la memoria del repo).
- **Escritura**: `set({'notificationPrefs': {'novedades_plan': {'email': v}}},
  SetOptions(merge: true))`, mapa anidado. Una clave con puntos en un `set`
  queda como nombre literal. El merge profundo no pisa la matriz del Coach Hub.
- **Reglas**: el dueño ya puede escribir `notificationPrefs` (no hay `hasOnly`
  en el update de `users`). Ningún test lo fija; se suma uno.
- **Deriva entre lenguajes**: la clave `novedades_plan` vive en TS
  (`ATHLETE_PROSPECT_PREF_KEY`) y ahora en Dart. Un test Dart lee el `.ts` y
  falla si dejan de coincidir.
- **Coach Hub**: no se toca. El entrenador ya tiene el toggle en la app y el link
  en el mail. Una fila más en `kNotifTypes` dibujaría una casilla de push que no
  hace nada.

## 8. La landing (`treino-app`, PR aparte)

Página nueva `/[locale]/correos-promocionales/baja`, calcada de
`/[locale]/baja-de-servicio/confirmar` (`ConfirmarBajaPorMail.tsx`,
`lib/bajaPorMail.ts`):

1. Lee `#t=` y lo saca de la barra con `history.replaceState`.
2. Muestra un botón «Dejar de recibir correos promocionales». No llama nada al
   cargar.
3. Al click, `bajaDeCorreosPromocionales({token})`:
   - `listo` → «Listo. No te vamos a mandar más correos promocionales. Los
     avisos de tu cuenta te siguen llegando.»
   - `invalido` o sin token → «Este link no es válido.» y el camino alternativo:
     escribir a `treino@gettreino.com`.
   - error de red o de la función → «No pudimos completar la baja. Probá de
     nuevo en un rato con este mismo link.» (el link no se gasta).

## 9. Fuera de este cambio

- **Base legal de los correos comerciales y «publicidad» en el asunto (Disp.
  4/2009, art. 2). DECIDIDO el 2026-10-02 por el titular.** Hasta acá era una
  pregunta abierta: la política decía «consentimiento, art. 6(1)(a)» para lo
  comercial (§7.1) y el código manda salvo oposición (opt-out). Se eligió la
  **opción B**: la base es el **interés legítimo con oposición absoluta**, que
  es lo que el producto ya hace (envío opt-out, link de baja en el pie de cada
  uno, toggle en la app con la próxima versión de las tiendas) y lo que ya
  describe §7.3. La opción A, pedir consentimiento explícito, apagaba los mails
  para toda la base actual y no se tomó. No hace falta re-aceptación: las
  cuentas actuales son de prueba. Consecuencias:
  - Rige la Disp. DNPDP 4/2009, art. 2: «cuando se efectúen envíos de
    comunicaciones de publicidad directa no requeridas o consentidas
    previamente por el titular del dato personal, deberá advertirse en forma
    destacada que se trata de una publicidad. En caso de realizarse dicha
    comunicación a través de un correo electrónico deberá insertarse en su
    encabezado el término único 'publicidad'.»
  - Los **cinco** kinds puramente comerciales —los que se encolan con
    `prefKey: "novedades_plan"`: `athlete-coverage-lost`, `free-limit-reached`,
    `exercise-limit-reached`, `template-limit-reached` y
    `student-limit-reached`— salen con **«Publicidad: » al frente del asunto**.
    Es `KINDS_DE_PUBLICIDAD` en `functions/src/mail/types.ts`; `renderMail` lo
    aplica en un único lugar, sólo al asunto (el cuerpo y el texto plano no
    cambian).
  - **Los dos mixtos quedan SIN prefijo, y es una consulta legal ABIERTA.**
    `limit-reached` y `email-code-*` (con `bloqueComercial`) son avisos
    operativos con un bloque de venta adentro: rotularlos «Publicidad: »
    mentiría sobre el código de verificación y sobre el aviso de solo lectura.
    Si el art. 2 alcanza al bloque comercial de un mail operativo, o alcanza el
    pie de §6.2, lo dice el abogado; hasta entonces salen como estaban.
  - El texto de la política cambia en otra rama (`docs/legal/`): §5, §7.1 y la
    fila de oposición de §9. Ahí sí se puede nombrar el link del pie, y el
    toggle recién cuando esté publicado en las tiendas.
- **Texto legal.** Cuando el pie y el toggle estén vivos, §9 puede nombrar el
  link del pie. Antes no: prometería algo que todavía no existe.
- **`List-Unsubscribe` / `List-Unsubscribe-Post` (RFC 8058).** El one-click de
  Gmail hace un POST con cuerpo de formulario, que una callable no acepta; pide
  un `onRequest` nuevo y el token en la query (en los logs). Gmail y Yahoo lo
  exigen a quien manda más de 5000 mails por día; TREINO está órdenes de
  magnitud abajo. Se revisa si el volumen cambia.

## 10. Deploy (NO ejecutar sin OK humano)

Orden, para que ningún mail salga con un link a una página que no existe:

1. **Secreto** (lo crea un humano; es una credencial):
   `openssl rand -base64 48 | tr -d '\n' | firebase functions:secrets:set BAJA_PROMOCIONALES_KEY --data-file=- --project prod`.
   Antes de esto, mergear el PR de functions **bloquea todo deploy de functions**
   («Cloud Secret Manager has no latest version»).
2. **Landing**: mergear el PR de `treino-app`. Hasta el paso 4 el botón contesta
   el mensaje de error recuperable; ningún mail apunta todavía a la página.
3. **Callable**:
   `firebase deploy --only functions:bajaDeCorreosPromocionales --project prod`.
4. **IAM** (`treino-dev` no permite `allUsers`):
   `gcloud run services update bajadecorreospromocionales --no-invoker-iam-check --region southamerica-east1 --project treino-dev`.
5. **Pie**: `firebase deploy --only functions:sendQueuedMail --project prod`.
   **Precondición**: `sendQueuedMail` sale en el MISMO deploy que
   `solicitarCodigoDeVerificacion`, o antes. El productor del mail del código le
   deja la oposición al envío (§6.3): con un `sendQueuedMail` viejo, quien se
   opuso vería los planes. Al revés no hay riesgo: con la plantilla nueva, un
   documento sin `bloqueComercial` sale sin el bloque.
6. **App**: el toggle llega con la próxima versión de las tiendas.

Con filtro siempre: un `--only functions` pelado poda toda función ausente de
`index.ts`.

## 11. Archivos (PR de functions)

| Archivo | Cambio |
|---|---|
| `functions/src/mail/baja-de-promocionales.ts` | nuevo: firmar/verificar, URL, allowlist, `run*` y la callable |
| `functions/src/mail/send-queued-mail.ts` | secreto, link al enviar, fail-closed sin clave, `bloqueComercial` |
| `functions/src/mail/templates.ts` | opciones de `renderMail`: el pie de §6.2 y `comercial: false` en `limit-reached` |
| `functions/src/mail/types.ts` · `enqueue-mail.ts` | `bloqueComercial` en el documento de la cola |
| `functions/src/subscriptions/subscription-mail.ts` | `enqueueProspectMail` marca `bloqueComercial` |
| `functions/src/index.ts` | exporta la callable |
| `functions/src/__tests__/baja-de-promocionales.test.ts` | nuevo |
| `functions/src/__tests__/mail-outbox.test.ts` (el de `sendQueuedMailHandler`; no hay `send-queued-mail*.test.ts`) · `prospect-mail.test.ts` | link sí/no según `prefKey` y destinatario; `bloqueComercial` (incluido el degradado sin link); el productor lo marca |
| `functions/src/__tests__/mail-templates.test.ts` | pie con y sin la opción, texto plano |
| `functions/src/__tests__/appcheck-enforcement.test.ts` | `EXEMPTIONS`, `EXPECTED_DEPLOYED` **y** `BASELINE` (el guard de deriva) |
| `docs/runbook-dominio-y-email.md` | baja pedida por mail; corrige «push no lee `notificationPrefs`» |

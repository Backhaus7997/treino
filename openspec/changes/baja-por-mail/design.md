# Diseño técnico: baja-por-mail

> Botón de Baja de Servicio **automático**, con verificación de identidad por
> correo. Este documento cubre el backend (este repo). La parte de la landing
> vive en `treino-app` y va en un PR aparte (§7).
>
> ⚠️ Nada de acá se despliega sin OK de un humano. `treino-dev` es producción
> (ver `openspec/AGENTS.md`). Orden: `firestore:rules` antes que `functions`.

---

## 1. Objetivo

Que quien toque «Botón de Baja de Servicio» en `gettreino.com` pueda dar de baja
su suscripción **sin que intervenga una persona**, y sin que eso le permita a un
tercero darle de baja la suscripción a otro con sólo saberle el correo.

Hoy la página existe (`/es/baja-de-servicio`, `treino-app#15`), pero termina en
un formulario que va a una planilla, y la baja la ejecuta alguien a mano —
cuando el sumidero está configurado, que al 2026-09-21 no lo estaba (ver
`docs/legal/spec-web-legal.md` §3.5).

## 2. Base legal

- **Disp. 954/2025, art. 4.** Link «BOTÓN DE BAJA DE SERVICIO» a simple vista,
  en el primer acceso, y al usarlo **no se puede exigir registración previa ni
  otro trámite adicional**.
- **Disp. 954/2025, art. 5.** Constancia al consumidor con **código de
  identificación** del trámite dentro de las 24 horas.
- **Disp. 3/2026, art. 1.** El consumidor debe cumplir los pasos que prevea el
  proveedor si son **razonables**, por **medios habituales**, y con **finalidad
  exclusiva de verificación de identidad y seguridad**. Habilita verificar
  identidad **después** del botón (el acceso sigue siendo público).

Un click en un link que llega al correo de la cuenta es el medio más habitual que
existe, no exige crear nada ni subir nada, y sólo sirve para probar que quien
pide la baja es el dueño del buzón. Es exactamente el resguardo que la 3/2026
describe.

## 3. Flujo

```
landing /es/baja-de-servicio        (público, sin sesión)
  │ la persona pone su correo; la landing emite el código BAJA-AAAA-XXXXXX
  │ (lo sigue registrando en la planilla, art. 5)
  └─> [servidor de la landing] solicitarBajaPorMail({email, code})
        │  SIEMPRE → {status:"ok"}
        │  si el correo es de una cuenta con un plan que puede cobrar:
        │    token = 32 bytes aleatorios, base64url
        │    mp_bajas_por_mail/{sha256(token)} = {uid, code, createdAt,
        │                                          expiresAt: +72h, usedAt: null}
        │    mail `service-cancel-confirm` al uid →
        │      https://gettreino.com/es/baja-de-servicio/confirmar#t=<token>
        ▼
buzón de la cuenta
  └─> página /es/baja-de-servicio/confirmar   (lee el token del fragmento)
        │ muestra un botón «Confirmar baja»; NO hace nada al cargar
        └─> click → confirmarBajaPorMail({token})
              transacción: invalido | ya-usado | vencido | reclamar (usedAt)
              runCancelMySubscription(uid DEL DOC, …)   ← la MISMA baja del Coach Hub
                dada-de-baja    → mail `service-cancel-done` {code, accesoHastaIso}
                sin-suscripcion → token queda usado
                no-disponible / cooldown 10 s → se LIBERA el reclamo
```

### API pública

| Callable | Entrada | Salida |
|---|---|---|
| `solicitarBajaPorMail` | `{email: string, code?: string}` | siempre `{status: "ok"}` |
| `confirmarBajaPorMail` | `{token: string}` | `{status: "invalido" \| "ya-usado" \| "vencido" \| "sin-suscripcion" \| "no-disponible"}` o `{status: "dada-de-baja", accesoHastaIso?: string}` |

Los dos: `onCall`, `southamerica-east1`, sin sesión, sin App Check,
`maxInstances: 5`. Sólo el segundo lleva el secreto `MP_ACCESS_TOKEN`.

`code` se acepta sólo con la forma `/^BAJA-\d{4}-[0-9A-F]{6}$/i` (se normaliza a
mayúsculas); cualquier otra cosa se descarta. Viaja al asunto de un mail: un
campo libre ahí sería un canal para escribirle texto arbitrario a un tercero
desde nuestro dominio.

## 4. Decisiones de seguridad

### 4.1 Token hasheado, de un solo uso

El id del documento es `sha256(token)` en hex. El token crudo no se guarda en
ningún documento propio: quien lea la colección (un backup, una exportación, un
operador) no puede canjear nada. 256 bits de entropía hacen innecesario un
límite de intentos en la confirmación.

El crudo viaja una sola vez, dentro del mail, en `params.actionLink`. Se eligió
ese nombre —y no un `confirmUrl` propio— porque `sendQueuedMail` ya **borra**
`params.actionLink` del documento de la cola apenas envía. Con otro nombre, el
token quedaba vivo en `mail_queue` para siempre.

Uso único con reclamo en **transacción**: dos clicks simultáneos leen
`usedAt: null`, sólo uno escribe; el otro reintenta y contesta `ya-usado`. El
reclamo lleva un `claimId` aleatorio, y la liberación sólo pisa `usedAt` si el
reclamo sigue siendo el suyo.

### 4.2 El token va en el fragmento (`#t=`)

Un fragmento no viaja en el request HTTP: no queda en los logs de Vercel, de un
proxy, ni en el `Referer`. La página lo lee con JS.

### 4.3 Click explícito en la página de confirmación

Los escáneres de correo (Outlook Safe Links, Gmail, antivirus corporativos)
**pre-abren** los links. Si abrir el link diera la baja, la daría el escáner. La
página muestra un botón y recién el click llama a `confirmarBajaPorMail`. Por eso
el mail dice «tocá el botón y confirmá en la página que se abre».

### 4.4 El uid sale del documento, nunca del request

`confirmarBajaPorMail` recibe un token y nada más. En Mercado Pago una baja no se
deshace, así que no existe ningún campo que pueda apuntar a la suscripción de
otro. Mismo criterio que `cancelMySubscription`, que no tiene body.

### 4.5 Anti-enumeración

`solicitarBajaPorMail` contesta `{status:"ok"}` para input basura, correo
desconocido, cuenta sin plan que cobre, throttle, y éxito. Nunca tira. Mismo
contrato que `requestPasswordReset` (REQ-AUTH-011) y la misma limitación
conocida: el camino que encola hace más trabajo, así que queda un canal lateral
por **tiempo de respuesta**. Mitigante propio de este diseño: lo llama el
servidor de la landing, no el navegador, y la landing puede contestarle a la
persona sin esperar la respuesta.

El mail tampoco nombra a la persona ni al plan: le sirve al dueño sin contarle
nada a quien lo haya pedido tipeando su correo.

### 4.6 Throttle

Ventana de **10 minutos** por cuenta, embebida en el `scope` del mail (el outbox
deduplica por id determinístico). Antes de acuñar el token se mira si el mail de
la ventana ya existe; si existe, no se crea nada. Si el mail no se pudo encolar
(carrera perdida o cola caída), el token recién creado se borra: no queda un
secreto vivo que nadie recibió.

10 y no 1 como el reseteo de contraseña: acá el abusador típico no es el dueño
del buzón sino alguien que le quiere llenar la casilla a un tercero, y el dueño
no pierde nada esperando porque el link que ya recibió sirve 72 horas.

### 4.7 72 horas

Lo bastante para que un pedido del viernes a la noche se confirme el lunes; lo
bastante corto para que un mail viejo en una casilla compartida no sea un botón
de baja permanente.

### 4.8 Cuando MP no contesta, el link no se quema

`no-disponible` (MP no contestó) y el cooldown de 10 s de
`runCancelMySubscription` (que devuelve `sin-suscripcion` con `enfriando`) se
mapean a `no-disponible` y **liberan** el reclamo: no pasó nada, y la persona
reintenta con el mismo link. Mapear el cooldown a `sin-suscripcion` le diría
«no tenías nada que dar de baja» con la suscripción viva y el link quemado.

Si la baja revienta con una excepción también se libera. Es seguro aunque MP ya
hubiera cancelado: el reintento no encuentra suscripción viva, no vuelve a
llamar a `cancelPreapproval`, y contesta `sin-suscripcion`.

### 4.9 Reglas

`mp_bajas_por_mail/{tokenHash}` cerrada en los cuatro verbos, igual que las otras
`mp_*`. Como allá, el `if false` es documentación (las reglas son unión
permisiva); lo que protege es `mp-collections-rules.test.ts`.

## 5. Qué sigue yendo por el canal manual

El automático sólo actúa sobre **una cuenta de TREINO cuyo correo coincide** y
que tiene **un plan de Mercado Pago que todavía puede cobrar** (mismo
`planesQueCobran` que usa la baja). Quedan en la planilla, procesados a mano:

- Correo sin cuenta en TREINO.
- Cuenta que pagó con **otro** correo, o cuya suscripción no está mapeada en
  `mp_plans`.
- Alumnos que pagan por App Store / Google Play: la baja la gestiona la tienda.

Por eso la landing **no deja de registrar** el pedido en la planilla ni de
emitir el código del art. 5: el mail automático es un camino rápido encima de
ese registro, no un reemplazo. La respuesta de `solicitarBajaPorMail` no dice
en cuál de los dos caminos cayó la persona (§4.5), así que la página tiene que
decir algo cierto en los dos casos: «si tu correo tiene una suscripción activa
con nosotros, te llega un mail para confirmar; si no te llega, procesamos tu
pedido igual dentro de las 24 horas con el código X».

## 6. Mails

| Kind | Cuándo | Params | prefKey |
|---|---|---|---|
| `service-cancel-confirm` | pedido válido | `actionLink`, `code?` | — (transaccional) |
| `service-cancel-done` | `dada-de-baja` | `code?`, `accesoHastaIso?` | — (transaccional) |

El de baja hecha espeja `docs/legal/terminos-suscripcion.md` §7: no se te vuelve
a cobrar, conservás el acceso hasta la fecha (formateada en hora de Argentina al
renderizar), no se reembolsa el período en curso, no se borra nada, y la baja es
definitiva para esa suscripción. Sin fecha, la frase se omite; nunca se inventa.

## 7. Fuera de este cambio: la landing (`treino-app`, PR aparte)

1. La ruta de `/es/baja-de-servicio` llama a `solicitarBajaPorMail` **desde el
   servidor** con el correo y el código que ya emite, además de registrarlo en
   la planilla. Nunca muestra un resultado distinto según la respuesta.
2. Página nueva `/es/baja-de-servicio/confirmar`: lee `#t=` del fragmento (y lo
   saca de la barra con `history.replaceState`), muestra un botón, y **al click**
   llama a `confirmarBajaPorMail({token})`. Mapea los seis estados a copy:
   `dada-de-baja` con la fecha; `no-disponible` con «probá de nuevo en un rato,
   con este mismo link»; `vencido`/`invalido`/`ya-usado` con el camino al
   formulario manual.
3. ⚠️ `treino-app` es el sitio público en producción y no tiene CI: avisar antes
   de tocarlo.

## 8. Archivos

| Archivo | Cambio |
|---|---|
| `functions/src/subscriptions/mp/baja-por-mail.ts` | nuevo: los dos `run*` y los dos callables |
| `functions/src/subscriptions/mp/cancel-my-subscription.ts` | exporta `planesQueCobran` |
| `functions/src/mail/types.ts` · `templates.ts` | dos `MailKind` y sus plantillas |
| `functions/src/index.ts` | exporta los dos callables |
| `firestore.rules` | `mp_bajas_por_mail` cerrada |
| `functions/src/__tests__/mp-baja-por-mail.test.ts` | nuevo |
| `functions/src/__tests__/mail-templates.test.ts` | kinds + casos de las plantillas |
| `functions/src/__tests__/appcheck-enforcement.test.ts` | exenciones declaradas |
| `functions/src/__tests__/mp-collections-rules.test.ts` | casos de `mp_bajas_por_mail` |
| `docs/legal/spec-web-legal.md` | §3.5, punto 3 apunta acá |

## 9. Deploy (NO ejecutar sin OK humano)

```bash
firebase deploy --only firestore:rules --project prod
firebase deploy --only functions:solicitarBajaPorMail,functions:confirmarBajaPorMail --project prod
```

Con filtro: un `--only functions` pelado **poda** toda función ausente de
`index.ts`. Y recién después, el PR de la landing.

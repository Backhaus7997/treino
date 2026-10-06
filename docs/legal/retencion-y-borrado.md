<!-- treino-legal
slug: retencion
title: Retención y eliminación de datos
dart: kDataRetentionSections
-->

# Política de Retención y Eliminación de Datos

**Última actualización:** <!-- fecha:auto -->
**Versión:** 1.0

> Documento de respaldo de la [Política de Privacidad](./politica-de-privacidad.md),
> secciones 8 y 10. Escrito contra el comportamiento real de
> `functions/src/delete-account.ts` y `functions/src/cascade/`, verificado el
> **2026-10-05**. Sirve además como URL de referencia para el requisito de
> eliminación de cuenta de Google Play.

---

## 1. Cómo eliminás tu cuenta

**Desde la app:** Perfil → Ajustes → Eliminar cuenta. No hace falta pedírselo a
nadie ni esperar aprobación.

**Si sos entrenador, también desde el Coach Hub:** Ajustes → Cuenta → Eliminar
cuenta. Te pedimos que vuelvas a confirmar tu identidad antes de borrar.

**Desde la web:** entrá a
[gettreino.com/es/eliminar-cuenta](https://gettreino.com/es/eliminar-cuenta) y
seguí las instrucciones. No hace falta tener la app instalada ni iniciar
sesión.

> **Requisito de Google Play.** Play exige que exista una URL **accesible desde
> un navegador, sin instalar la app**, donde se pueda solicitar la eliminación
> de la cuenta y de los datos. La página ya está publicada y lo cumple. Lo que
> queda es **declararla en Play Console**, que es un trámite de consola, no de
> producto.

**Borrado de datos puntuales, sin cerrar la cuenta:** podés pedirlo
escribiendo a treino@gettreino.com, con el correo de tu cuenta, y respondemos
dentro de los 5 días hábiles (art. 16 de la Ley 25.326, ver sección 5). Dos
casos son más rápidos porque los resolvés vos mismo desde la app: una
publicación propia, desde el menú de la publicación, y una medición que
hayas cargado vos, desde tu pantalla de medidas.

---

## 2. Qué se elimina

El borrado es **en cascada y automático**, ejecutado por una Cloud Function con
privilegios de servidor.

### 2.1 Tu perfil y todo lo que cuelga de él

`users/{uid}` se elimina recursivamente, con todas sus subcolecciones:
sesiones de entrenamiento, series registradas, check-ins diarios y molestias
reportadas. También se eliminan `userPublicProfiles/{uid}` y, si sos entrenador,
`trainerPublicProfiles/{uid}`.

### 2.2 Tus datos de salud

Se eliminan por completo:

| Dato | Colección |
|---|---|
| Medidas corporales | `measurements` |
| Tests de rendimiento | `performance_tests` |
| Planes de alimentación | `nutrition_plans` |
| Check-ins y molestias | subcolecciones de `users/{uid}` |
| **Fotos de molestias reportadas** | `sessionFeedback/{uid}/**` en Storage |

### 2.3 Los registros que tu entrenador llevaba sobre vos

Se eliminan **también**, aunque los haya escrito él:

| Dato | Colección |
|---|---|
| Notas privadas | `athlete_notes` |
| Registro de seguimiento | `follow_up_entries` |
| Archivos subidos sobre vos | `athlete_files` + el objeto en Storage |
| Configuración de facturación | `athlete_billing` |

**Decisión de producto (2026-07-17):** no hay retención legal que los ampare, y
son datos personales tuyos. Se van.

### 2.4 Tus permisos, vínculos y contenido social

`profile_shares`, `session_shares`, `trainer_links`, `follows`, tus
publicaciones (`posts`) y tus turnos (`appointments`).

### 2.5 Tus archivos

En Cloud Storage: avatar, subidas temporales, videos de ejercicios propios,
fotos de publicaciones, fotos de molestias y multimedia del chat.

### 2.6 Si sos entrenador

Podés eliminar tu cuenta de entrenador igual que cualquier otra, desde la app.
Además de todo lo anterior, se hace esto:

**Tus alumnos.** Terminamos todos tus vínculos, incluidas las solicitudes
pendientes. A cada alumno le llega una notificación avisándole que el vínculo
terminó. No les mandamos correo.

**Tus turnos.** Se cancelan los turnos futuros que estaban pendientes o
confirmados, y se borra tu disponibilidad horaria. La notificación al alumno es
la del vínculo; no recibe una por cada turno.

**Lo que escribiste sobre tus alumnos.** Se elimina todo lo que llevabas sobre
ellos: notas privadas, registro de seguimiento, archivos (y el objeto en
Storage), configuración de facturación y planes de alimentación. También los
accesos que los alumnos te habían compartido (sus perfiles y sus sesiones).

**Tu contenido profesional.** Se eliminan tus plantillas de rutina —las
privadas y las que habías publicado—, las reseñas que recibiste, tus ejercicios
propios y los videos que subiste a ellos, y tu perfil público de entrenador.

**Tu suscripción.** Antes de borrar nada damos de baja tu suscripción de
Mercado Pago. Si no podemos hacerlo, la cuenta **no se elimina** y podés
reintentar: no te dejamos pagando sin cuenta.

**Lo que se queda con tus alumnos.** Las rutinas que les asignaste siguen siendo
de ellos, con su historial. Si una de esas rutinas usaba un ejercicio propio
tuyo, conserva el nombre pero deja de tener el video y la descripción. Las copias
que un alumno haya adoptado de una plantilla tuya también siguen siendo suyas.

### 2.7 Si un paso falla a mitad de camino

El borrado son varios pasos. Salvo la baja de la suscripción, que va primero y
frena todo si falla, un error transitorio en uno de ellos no detiene el resto:
tu cuenta y tu acceso se eliminan igual, y **los datos de ese paso pueden quedar
guardados**. Esos pasos los reintentamos solos, una vez por día, hasta cinco
veces. Cada falla y cada reintento quedan registrados con tu identificador. Si
después de los cinco intentos algo sigue sin borrarse, ese borrado queda marcado
como fallido y lo terminamos a pedido tuyo: si querés que confirmemos que no
quedó nada, o que terminemos de borrarlo sin esperar, escribinos a
treino@gettreino.com con el correo de tu cuenta, y lo
tratamos como una solicitud de supresión, con el plazo de la sección 5.

---

## 3. Qué NO se elimina, y por qué

Esto es lo que hay que leer con atención. Estas cosas sobreviven, por razones
distintas.

| Dato | Qué queda | Por qué |
|---|---|---|
| **Pagos** (`payments`) | El registro, con tu `uid` a secas | Respaldo contable y fiscal del entrenador. **No contiene tu nombre**: al borrarse `userPublicProfiles/{uid}` el identificador deja de resolver a una persona |
| **Reseñas** que escribiste como alumno (`reviews`) | La puntuación numérica | Sostiene el promedio del entrenador. Borrarla alteraría retroactivamente la reputación de un tercero |
| **Chat** (`chats/messages`) | El hilo, para el otro participante. Si eliminás tu cuenta de entrenador, el hilo queda para el alumno, que ve «Usuario eliminado» | La conversación también le pertenece a la otra persona |
| **Rutinas que un entrenador asignó a un alumno** | Quedan con el alumno | Son parte del historial de entrenamiento del alumno. Si eliminás tu cuenta de entrenador, no se borran |

En los tres primeros casos, la des-identificación opera por la vía de que **ninguno de
esos documentos guarda tu nombre desnormalizado** — sólo el `uid`, que tras el
borrado ya no resuelve contra ningún perfil.

---

## 4. Copias de seguridad

Hay un **backup diario de Firestore con 28 días de retención**. Tus datos
sobreviven en esas copias hasta ese plazo tras el borrado, y se purgan solos al
rotar.

Las copias sólo se restauran ante un incidente de pérdida de datos, nunca para
recuperar una cuenta eliminada.

⚠️ **El backup no cubre Cloud Storage ni los usuarios de Firebase Auth.**

---

## 5. Plazos

| Acción | Plazo |
|---|---|
| Borrado en cascada | Inmediato al confirmar |
| Purga de copias de seguridad | Hasta 28 días |
| Solicitud de acceso (art. 14) | 10 días corridos |
| Solicitud de rectificación o supresión (art. 16) | 5 días hábiles |
| Reportes de error (Crashlytics) | Según retención de Firebase |

---

## 6. Cuentas inactivas

Si no usás tu cuenta durante **24 meses**, te avisamos por correo a la
dirección con la que te registraste. Si seguís sin usarla, **a los 36 meses de
inactividad damos de baja la cuenta** y borramos tus datos personales con el
mismo alcance que si hubieras pedido la eliminación vos (sección 3).

Usar la cuenta significa iniciar sesión o registrar cualquier actividad en la
app. Entre el aviso y la baja nunca pasan menos de 90 días, y en el caso normal
pasan doce meses, porque el aviso sale a los 24 y la baja a los 36. Alcanza con
entrar una vez para que el plazo vuelva a empezar.

**Quedan fuera de esta baja automática** las cuentas de entrenador, las que
tengan una suscripción vigente y las que mantengan un vínculo activo con un
entrenador. (Esto es sólo la baja automática: un entrenador que elimina su cuenta él mismo
la elimina como se explica en la sección 2.6.) Dar de baja a un entrenador
afecta a terceros: los vínculos con sus
alumnos, las reseñas que recibió y los chats que mantuvo con ellos. Y una cuenta
que está pagando, o que está entrenando con un profesional, no está abandonada
aunque no la abras. Esas cuentas se revisan a mano si la inactividad se
sostiene, y no reciben el aviso automático de los 24 meses.

Conservamos únicamente lo que la ley obliga a conservar, igual que en cualquier
otra baja.

Este plazo responde al principio de calidad del dato del art. 4 inc. 7 de la
Ley 25.326: los datos deben destruirse cuando dejan de ser necesarios para la
finalidad que motivó su recolección. Con datos de salud de por medio, sostener
que la retención es proporcional exige un plazo escrito y cumplido.

---

## 7. Cómo pedir tus datos

Escribinos a treino@gettreino.com con el correo de tu cuenta.
Te entregamos todo lo que consta sobre vos, **incluidos los registros privados
de tu entrenador**, dentro de los 10 días corridos. Es gratuito.

---

<!-- publish:end -->

## ANEXO INTERNO — preguntas abiertas para el abogado

**No es texto de usuario.** Vive después de `publish:end` a propósito: estaba
arriba, adentro de lo publicable, y era lo único en los nueve documentos que un
usuario habría leído como «esto no está terminado». Peor todavía, el último
párrafo le anunciaba al usuario que no se le avisa algo — decírselo así es no
avisarle igual, pero por escrito.

El esquema de la sección 3 es razonable y está pensado. Lo que sigue son las
cuatro decisiones que conviene que valide un abogado cuando llegue:

1. Si la retención del **texto de las reseñas** (no sólo el número) es
   sostenible frente a un pedido de supresión del art. 16 de la Ley 25.326.
2. Si conservar el **contenido del chat** requiere aviso previo explícito al
   momento del borrado, en vez de sólo estar escrito en el documento.
3. Cuál es el **plazo fiscal concreto** de conservación de `payments` según la
   normativa aplicable, y si corresponde purgarlos al vencerlo.
4. Si borrar **sin aviso previo** las reseñas recibidas y las plantillas
   publicadas de un entrenador que elimina su cuenta (sección 2.6) es
   razonable frente a los alumnos que las usaban, o si corresponde un plazo de
   gracia. Hoy el borrado es inmediato y el alumno conserva las rutinas que ya
   tenía asignadas.

**Resuelto (#1353):** un borrado `partial` (sección 2.7) se reintenta solo. La
función programada `retryPartialDeletions` corre todos los días a las 06:00 ART
sobre `audit_log where status == 'partial'` (hasta 50 por corrida) y vuelve a
correr los pasos de datos, sin tocar Mercado Pago y sin volver a avisar a nadie.
Cuenta los intentos en `retryCount`; completo, marca `success`; al quinto
intento sin éxito marca `failed` y deja un log de nivel error. El texto
publicado describe exactamente eso.

**Pendiente de producto, independiente del abogado:** la pantalla de
confirmación de borrado no le dice al usuario qué sobrevive. La sección 3 sí lo
dice, pero ahí llega el que va a buscarlo. Conviene decirlo en el momento.


## 8. Nota de implementación (no se publica)

**Estado del código.** El borrado en cascada está implementado y cubierto por
tests (`functions/src/__tests__/cascade/`). Cubre Firestore, Storage y Auth. No
hay hallazgos de completitud sobre él: es de las piezas mejor resueltas del
proyecto en materia de cumplimiento.

**Lo que falta, y es todo de superficie:**

| # | Tarea | Bloquea |
|---|---|---|
| 1 | Página pública `gettreino.com/eliminar-cuenta` | **Sí** — Google Play |
| 2 | Que la confirmación de borrado avise qué se conserva (sección 3) | No, pero es lo correcto |
| 3 | Procedimiento operativo para responder pedidos de acceso | No |
| 4 | ~~Definir política de cuentas inactivas~~ | **HECHO** — 24/36 meses, piso de 90 días |
| 5 | Confirmar plazo fiscal de `payments` con asesor | No |

---

### 8.1 El barrido, encendido el 2026-09-17

`RETENTION_SWEEP_DRY_RUN` pasó a `false`. La condición que el marcador pedía
—leer el backlog antes de encender— se cumplió, y el resultado fue que **no hay
backlog**.

**Medido por dos caminos independientes que coinciden:** los logs de las dos
corridas en `dryRun` (16 y 17 de septiembre) y un conteo directo contra Firebase
Auth.

```
cuentas en Auth ............ 58
inactividad máxima ......... 129 días  (4,2 meses)
mediana .................... 43 días
≥24 meses → aviso .......... 0
≥36 meses → baja ........... 0
capped ..................... false   (0 acciones contra un tope de 50)
```

**A la cuenta más inactiva le faltan 601 días para el umbral de aviso.** Y el
cero es estructural, no una casualidad: el primer commit de `lib/features/auth`
es del 2026-05-08, así que la distribución entera está donde la edad del producto
obliga. El primer aviso posible es de ~2028-05 y la primera baja de ~2029-05.

### 8.2 Esto ACTIVA el mecanismo, no lo valida

Conviene que quede escrito, porque dentro de un año el log va a inducir a error.

Encender el barrido va a producir **veinte meses de corridas en cero**, que
parecen confirmación y no confirman nada: producción no va a ejecutar ninguna
rama que no sea «cuenta activa» hasta 2028. El código que efectivamente da de
baja se estrena en 2029, contra una base que hoy no existe.

**La evidencia de que la baja funciona está en la suite, no en producción.**
`functions/src/__tests__/sweep-inactive-accounts.test.ts` tiene 27 casos y cubre
las ramas que producción no va a tocar:

- `nunca borra sin aviso previo registrado` — una cuenta de 5 años sin registro
  de aviso recibe aviso, no baja
- `NO borra a los 35 meses aunque el aviso esté maduro`
- `una cuenta del backlog NO se borra un día antes del piso`
- `borra con las DOS condiciones, y firma el audit log aparte`
- `exclusiones — sacan del barrido ENTERO, no sólo de la baja`

Si en algún momento hace falta más evidencia, el camino es **sembrar cuentas
viejas en el emulador y correr el handler ahí**, no mirar producción.

### 8.3 Cómo leer el resultado de una corrida

Tres trampas del `SweepInactiveResult`, verificadas contra el código:

| Campo | Lo que NO es |
|---|---|
| `inactive` | **No es el backlog accionable.** `r.inactive++` está en las tres ramas del switch (556, 574, 595), así que incluye las exclusiones: `inactive = excludedTrainers + excludedSubscription + excludedActiveLink + noticed + deleted`. Lo accionable es `noticed + deleted` |
| `inactive` | **Tampoco sobrevive al tope.** El chequeo hace `break` y no `continue` (530), así que cuando el tope muerde la corrida deja de mirar cuentas y `inactive` se congela con el resto. Es un piso, no un total |
| `capped` | **Está en el resultado**, no hay que inferirlo de `noticed == 50` |

Y una del flujo: **en la primera corrida real `deleted` va a ser 0**, sin
importar la edad de las cuentas. `evaluarCuenta` (381) devuelve `aviso` cuando no
hay registro de aviso previo, y el `dryRun` no lo escribe. Para caer en `baja`
hacen falta cuatro cosas a la vez: registro de aviso, con `noticeSentAt` no nulo,
≥36 meses de inactividad, y que el aviso tenga ≥90 días.

**El riesgo del encendido nunca fue un borrado masivo: era un envío masivo de
mails**, y el tope de 50 por corrida es lo que protege contra eso.

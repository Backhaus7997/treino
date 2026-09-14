<!-- treino-legal
slug: retencion
title: Retención y eliminación de datos
dart: kDataRetentionSections
-->

# Política de Retención y Eliminación de Datos

**Última actualización:** [[PENDIENTE — fecha de publicación]]
**Versión:** 1.0 (borrador)

> Documento de respaldo de la [Política de Privacidad](./politica-de-privacidad.md),
> secciones 8 y 10. Escrito contra el comportamiento real de
> `functions/src/delete-account.ts` y `functions/src/cascade/`, verificado el
> **2026-08-31**. Sirve además como URL de referencia para el requisito de
> eliminación de cuenta de Google Play.

---

## 1. Cómo eliminás tu cuenta

**Desde la app:** Perfil → Ajustes → Eliminar cuenta. No hace falta pedírselo a
nadie ni esperar aprobación.

**Desde la web:** entrá a
[gettreino.com/es/eliminar-cuenta](https://gettreino.com/es/eliminar-cuenta) y
seguí las instrucciones. No hace falta tener la app instalada ni iniciar
sesión.

> **Requisito de Google Play.** Play exige que exista una URL **accesible desde
> un navegador, sin instalar la app**, donde se pueda solicitar la eliminación
> de la cuenta y de los datos. La página ya está publicada y lo cumple. Lo que
> queda es **declararla en Play Console**, que es un trámite de consola, no de
> producto.

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

---

## 3. Qué NO se elimina, y por qué

Esto es lo que hay que leer con atención. Tres cosas sobreviven, por razones
distintas.

| Dato | Qué queda | Por qué |
|---|---|---|
| **Pagos** (`payments`) | El registro, con tu `uid` a secas | Respaldo contable y fiscal del entrenador. **No contiene tu nombre**: al borrarse `userPublicProfiles/{uid}` el identificador deja de resolver a una persona |
| **Reseñas** (`reviews`) | La puntuación numérica | Sostiene el promedio del entrenador. Borrarla alteraría retroactivamente la reputación de un tercero |
| **Chat** (`chats/messages`) | El hilo, para el otro participante | La conversación también le pertenece a la otra persona |

En los tres casos, la des-identificación opera por la vía de que **ninguno de
esos documentos guarda tu nombre desnormalizado** — sólo el `uid`, que tras el
borrado ya no resuelve contra ningún perfil.

> ⚠️ **Punto abierto para revisión legal.** Este esquema es razonable y está
> pensado, pero hay tres decisiones que conviene que valide un abogado:
>
> 1. Si la retención del **texto de las reseñas** (no sólo el número) es
>    sostenible frente a un pedido de supresión del art. 16 de la Ley 25.326.
> 2. Si conservar el **contenido del chat** requiere aviso previo explícito al
>    momento del borrado, en vez de sólo estar escrito acá.
> 3. Cuál es el **plazo fiscal concreto** de conservación de `payments` según la
>    normativa aplicable, y si corresponde purgarlos al vencerlo.
>
> Hoy el usuario no recibe ningún aviso de que esto queda. Como mínimo, la
> pantalla de confirmación de borrado debería decírselo.

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

[[PENDIENTE — ENCENDER EL BARRIDO. El plazo está resuelto y el proceso ya
existe: `sweepInactiveAccounts`, en
`functions/src/retention/sweep-inactive-accounts.ts`. Lo que falta es que
ejerza. Se despliega con `RETENTION_SWEEP_DRY_RUN = true`, o sea que cuenta,
lista y loguea, y no manda un solo mail ni borra una sola cuenta.

Ese modo no es prudencia genérica. La señal de actividad sale de los metadatos
de Firebase Auth, que YA TIENEN HISTORIA, así que la primera corrida ve de una
todas las cuentas que hoy superan los 24 meses. Encenderlo sin leer ese número
antes es mandar ese número de mails de golpe.

El marcador bloquea la publicación A PROPÓSITO, y sigue bloqueándola por el
mismo motivo de siempre: mientras el barrido no ejerza, el texto de abajo
promete una baja automática que no ocurre, y una cláusula que promete lo que el
sistema no hace es peor que no tenerla. Que el código exista no cambia eso: lo
que el usuario lee es lo que PASA, no lo que está deployado.

PARA SACARLO hacen falta tres cosas, en este orden:

  1. Leer el log de una corrida en `dryRun` y ver el tamaño del backlog.
  2. Resolver la frase «con doce meses de antelación» del párrafo de abajo. Hoy
     NO es cierta para ese backlog: el barrido borra a los 36 meses de
     inactividad con un piso de 30 días desde el aviso
     (`MIN_NOTICE_AGE_DAYS`), así que una cuenta que ya lleva 40 meses recibe el
     aviso y se da de baja un mes después, no un año. El mail que sale dice la
     fecha real y no repite esta frase, así que nadie recibe hoy una afirmación
     falsa — pero si este párrafo se publica tal cual, empieza a serlo. Las dos
     salidas son subir `MIN_NOTICE_AGE_DAYS` a 365, o acotar la frase acá.
  3. Poner `RETENTION_SWEEP_DRY_RUN = false` y deployar.]]

Si no usás tu cuenta durante **24 meses**, te avisamos por correo a la
dirección con la que te registraste. Si seguís sin usarla, **a los 36 meses de
inactividad damos de baja la cuenta** y borramos tus datos personales con el
mismo alcance que si hubieras pedido la eliminación vos (sección 3).

Usar la cuenta significa iniciar sesión o registrar cualquier actividad en la
app. El aviso de los 24 meses llega con doce meses de antelación a la baja, así
que alcanza con entrar una vez para que el plazo vuelva a empezar.

**Quedan fuera de esta baja automática** las cuentas de entrenador, las que
tengan una suscripción vigente y las que mantengan un vínculo activo con un
entrenador. Dar de baja a un entrenador afecta a terceros: los vínculos con sus
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
| 4 | Definir política de cuentas inactivas | No |
| 5 | Confirmar plazo fiscal de `payments` con asesor | No |

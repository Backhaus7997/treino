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

**Desde la web:** [[PENDIENTE — publicar en `gettreino.com/eliminar-cuenta`]]

> **Requisito de Google Play.** Play exige que exista una URL **accesible desde
> un navegador, sin instalar la app**, donde se pueda solicitar la eliminación
> de la cuenta y de los datos. Hoy el borrado in-app funciona; la URL no existe.
> Es bloqueante de publicación.

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

[[PENDIENTE — DECISIÓN DEL TITULAR.]]

Hoy **no hay política de cuentas inactivas**: una cuenta sin uso conserva sus
datos indefinidamente. El principio de calidad del dato del art. 4 inc. 7 de la
Ley 25.326 dice que los datos deben destruirse cuando dejan de ser necesarios
para la finalidad que motivó su recolección.

Con datos de salud sobre la mesa, conviene definir un plazo —por ejemplo, aviso
a los 24 meses de inactividad y baja a los 36— e implementarlo. No es urgente
para lanzar, pero sí para sostener el argumento de que la retención es
proporcional.

---

## 7. Cómo pedir tus datos

Escribinos a [[PENDIENTE — casilla bajo `gettreino.com`]] con el correo de tu cuenta.
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

<!-- treino-legal
slug: comunidad
title: Normas de Comunidad
dart: kCommunitySections
-->

# Normas de Comunidad de TREINO

**Última actualización:** [[PENDIENTE — fecha de publicación]]
**Versión:** 1.0 (borrador)

> ⚠️ **BORRADOR.** Este documento cumple doble función: es el texto que se
> publica, **y** la especificación de lo que hay que construir. La parte
> especificada —reporte y bloqueo— **hoy no existe en el código**, y sin ella
> Apple rechaza la app. Ver el anexo al final.

---

## Por qué existen estas normas

TREINO tiene tres lugares donde publicás algo que otra persona lee: el **feed**,
el **chat** con tu entrenador, y las **reseñas**. Donde hay gente hablando, hace
falta un piso.

Estas normas se aplican a todo el contenido que subas: texto, fotos, tu nombre
visible, tu foto de perfil, tu biografía y tus reseñas.

---

## 1. Lo que no se permite

### 1.1 Acoso y odio

No se permite hostigar, amenazar, intimidar ni humillar a nadie. Tampoco
contenido que ataque a personas o grupos por su origen, nacionalidad, religión,
discapacidad, edad, género, identidad de género u orientación sexual.

**En una app de entrenamiento esto tiene una forma particular:** comentar el
cuerpo de otra persona sin que te lo pida es acoso. No importa si lo decís «como
elogio».

### 1.2 Contenido sexual

Nada de contenido sexual explícito ni desnudez. Las fotos de progreso físico son
bienvenidas, pero tienen que ser eso: registro de entrenamiento, no material
sexualizado.

### 1.3 Violencia y daño

No se permite contenido violento, gráfico, ni que promueva autolesiones o
trastornos alimentarios.

**Y esto sí es específico de acá:** no se permite promover restricción calórica
extrema, purgas, ayunos prolongados como método de descenso rápido, ni
comparaciones corporales presentadas como meta de salud. Una app de fitness es
exactamente el lugar donde ese contenido hace daño.

### 1.4 Contenido peligroso para la salud

No se permite:

- Recomendar sustancias dopantes, anabólicos o medicación con receta.
- Presentarse como profesional de la salud sin serlo.
- Dar indicaciones médicas, diagnósticos o tratamientos.
- Prometer resultados garantizados.

### 1.5 Suplantación y engaño

No te hagas pasar por otra persona, entrenador, gimnasio o marca. No inventes
credenciales, matrículas ni certificaciones.

**Reseñas:** sólo podés reseñar a un entrenador con el que tuviste un vínculo
real. Nada de reseñas compradas, intercambiadas ni escritas por vos mismo o por
allegados.

### 1.6 Spam y uso comercial no autorizado

Ni publicidad no solicitada, ni venta de productos ajenos al servicio, ni
esquemas de referidos, ni derivar usuarios fuera de la plataforma de forma
sistemática.

### 1.7 Datos de terceros

No publiques datos personales de otra persona: teléfono, dirección, documento,
información de salud. **Tampoco fotos de terceros sin su consentimiento** —
incluidas las de otras personas entrenando en tu gimnasio.

### 1.8 Propiedad intelectual

No subas contenido de otros sin derecho: rutinas copiadas de material con
copyright, fotos ajenas, videos de terceros.

---

## 2. Reglas adicionales para entrenadores

Si ofrecés servicios en TREINO, además:

- **Tus credenciales tienen que ser reales y verificables.**
- **No des indicaciones médicas.** Si un alumno reporta dolor persistente o una
  lesión, corresponde derivarlo a un profesional de la salud.
- **Los datos de tus alumnos son de ellos.** Lo que ves en TREINO —medidas,
  dolores, fotos, historial— se usa para entrenarlos y para nada más. No lo
  compartas, no lo publiques, no lo uses como material promocional sin
  autorización expresa y escrita.
- **Tus notas privadas sobre un alumno son datos personales de ese alumno.** El
  alumno tiene derecho a acceder a ellas si las solicita. Escribí en
  consecuencia.
- **Tarifas y alcance claros.** Lo que cobrás y lo que incluye se acuerda de
  antemano.

---

## 3. Cómo reportar

Si ves algo que viola estas normas:

1. **Reportá el contenido** desde el menú de la publicación, mensaje o reseña.
2. **Bloqueá al usuario** desde su perfil. Al bloquearlo dejás de ver su
   contenido y él el tuyo, y no puede volver a contactarte.
3. **Escribinos** a treino@gettreino.com si es grave o urgente.

**Nos comprometemos a revisar todo reporte dentro de las 24 horas.**

Si estás en peligro inmediato, contactá a los servicios de emergencia de tu
localidad. TREINO no es un servicio de emergencia.

---

## 4. Qué hacemos con un reporte

Según la gravedad y la reincidencia:

| Medida | Cuándo |
|---|---|
| Eliminación del contenido | Incumplimiento puntual |
| Advertencia | Primera infracción leve |
| Restricción temporal de publicar | Reincidencia |
| Suspensión de la cuenta | Infracción grave o reincidencia sostenida |
| Baja definitiva | Acoso grave, contenido sexual con menores, amenazas, fraude |
| Denuncia a la autoridad | Cuando el hecho pueda constituir delito |

Contenido sexual que involucre a menores, amenazas creíbles de violencia y
fraude se sancionan con **baja inmediata**, sin advertencia previa.

Si creés que una medida fue un error, podés apelar escribiéndonos. Revisamos y
respondemos.

---

## 5. Contacto

**BACKHAUSTIN S.A.S.** — CUIT 30-71929587-4
Correo: treino@gettreino.com

---
---

<!-- publish:end -->

# Anexo — Especificación de producto (no se publica)

Lo que sigue **no es parte del documento publicado**. Es el trabajo de
implementación que estas normas exigen, y sin el cual el documento es una
promesa que la app no cumple.

## A. Estado actual: no existe nada

Se buscó `report`, `reportar`, `denunciar`, `block`, `bloquear` y `blockedUsers`
en todo `lib/` y `functions/src/`. Los únicos aciertos son
`exerciseFeedbackAction` — *«COMENTAR / REPORTAR una molestia»*, que es la
feature de dolor en un ejercicio, **no moderación de contenido**.

Confirmado: **no hay reporte de contenido ni bloqueo de usuarios.**

## B. Por qué bloquea el lanzamiento

**App Store Review Guideline 1.2 — User-Generated Content.** Para apps con
contenido generado por usuarios, Apple exige cuatro cosas:

1. Un método de filtrado de contenido objetable.
2. Un mecanismo para **reportar** contenido, con respuesta oportuna.
3. La capacidad de **bloquear usuarios** abusivos.
4. Datos de contacto publicados.

TREINO tiene tres superficies de UGC —`posts` con foto, `messages` con
multimedia, `reviews` con texto libre— y **cero** de los cuatro requisitos.
Es causal de rechazo directo en revisión.

## C. Alcance mínimo

### C.1 Reporte de contenido

Colección nueva `reports/{reportId}`:

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `String` | |
| `reporterUid` | `String` | Quien reporta |
| `targetKind` | `enum` | `post` · `message` · `review` · `profile` |
| `targetId` | `String` | Id del contenido |
| `targetOwnerUid` | `String` | Autor del contenido |
| `reason` | `enum` | Ver taxonomía abajo |
| `detail` | `String?` | Máx. 1000 caracteres |
| `status` | `enum` | `open` · `reviewing` · `actioned` · `dismissed` |
| `createdAt` | `DateTime` | |

**Taxonomía de motivos** — mapea 1:1 contra la sección 1:
`harassment`, `sexualContent`, `violenceOrSelfHarm`, `dangerousHealthAdvice`,
`impersonation`, `spam`, `thirdPartyData`, `intellectualProperty`, `other`.

**Reglas:** `create` sólo autenticado y con `reporterUid == request.auth.uid`.
**`read` cerrado a todo cliente** — se revisa por consola de administración.
Rate limit para evitar reportes en masa.

**Entrada en UI:** menú contextual en la tarjeta del feed, en la burbuja de
chat, en la reseña y en el perfil público. Es el mismo componente en los cuatro
lugares.

### C.2 Bloqueo de usuarios

Colección `users/{uid}/blocked/{blockedUid}`, o array en el perfil si el
volumen esperado es bajo.

Efectos exigidos, y hay que verificarlos uno por uno:

- El bloqueado **no ve** posts del que bloqueó, ni al revés.
- El bloqueado **no puede** iniciar chat ni enviar mensajes.
- El bloqueado **no puede** reseñar ni seguir.
- El bloqueado **no aparece** en descubrimiento ni en rankings del otro.
- El bloqueo es **unilateral y silencioso** — no se le notifica.

⚠️ El filtrado tiene que ocurrir **del lado del servidor o en las reglas**, no
sólo en la UI. Un bloqueo que se puede esquivar leyendo Firestore directamente
no es un bloqueo.

### C.3 Filtrado preventivo

Mínimo aceptable: lista de términos vetados sobre `Post.text`, `Message.text`,
`Review.comment` y campos de perfil, aplicada en Cloud Function `onCreate`.

Deseable, en segunda instancia: moderación de imágenes para `postPhotos/` y
`chatMedia/`.

### C.4 Contacto publicado

Casilla real, atendida, en la ficha de ambas stores, en el sitio y en la app.

### C.5 Consola de revisión

No hace falta panel: una vista sobre `reports` con `status: open` en el Coach
Hub web, restringida al equipo, alcanza para arrancar. Lo que **no** puede
faltar es el compromiso operativo — las 24 horas de la sección 4 son una promesa
pública, y hay que poder sostenerla.

## D. Orden sugerido

| # | Tarea | Bloquea lanzamiento |
|---|---|---|
| 1 | Bloqueo de usuarios, con filtrado en reglas | **Sí** |
| 2 | Reporte de contenido en las cuatro superficies | **Sí** |
| 3 | Contacto publicado | **Sí** |
| 4 | Publicar estas Normas y enlazarlas desde la app | **Sí** |
| 5 | Filtrado de términos vetados | Sí (mínimo de la 1.2) |
| 6 | Vista de revisión en Coach Hub | No, pero sin ella no cumplís el plazo |
| 7 | Moderación de imágenes | No |

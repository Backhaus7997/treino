# Reporte de contenido y bloqueo de usuarios

## Por qué

**App Store Review Guideline 1.2.** Una app con contenido generado por usuarios
tiene que ofrecer cuatro cosas: filtrado de material objetable, un mecanismo de
**reporte**, la capacidad de **bloquear** usuarios abusivos, y contacto
publicado.

TREINO tiene tres superficies de contenido generado —`posts` con foto,
`chats/{id}/messages` con multimedia, y `reviews` con texto libre— y **cero** de
los cuatro requisitos. Es rechazo directo en revisión, y hoy es el único
bloqueante de publicación que no depende de ninguna decisión pendiente ni de la
revisión legal en curso.

## Qué se construye

| | |
|---|---|
| `blocks/{blockerUid}_{blockedUid}` | Arista dirigida. Bloquear es unilateral: no hay `pending` ni aceptación |
| `reports/{reportId}` | Un reporte por contenido y por denunciante |
| Enforcement | **En `firestore.rules`**, no en el cliente |
| Entrada en UI | Tarjeta del feed, perfil público, burbuja de chat y reseña |

## La decisión que ordena todo

**El bloqueo se hace cumplir en la escritura, no en la lectura.**

El instinto es filtrar lo que el bloqueado puede leer. En Firestore eso rompe el
producto: las reglas de `list` se evalúan contra la query entera, y si un
documento del resultado no pasa, **se rechaza toda la query en vez de filtrar la
fila**. `feedPublic()` no filtra por autor, así que un `notBlocked()` en el read
dejaría el feed **en blanco** apenas apareciera un post de alguien con quien
existe un bloqueo. Documentado en `post_providers.dart:157`.

Lo que protege de verdad a alguien acosado es que el otro **no lo pueda
contactar**, no que no pueda leer un post público. Entonces el corte va donde
está el daño: chat, reacciones, follows y reseñas — todo escritura, todo
cerrable en reglas.

Y hay un efecto de arrastre gratis: **bloquear borra las aristas de follow en las
dos direcciones**, con lo cual el tier `followers` queda protegido por la regla
que ya existe, sin tocar una línea del `allow read`.

Para `public` y `gym` el filtro queda en el cliente y es **cosmético** — se asume
y se dice, en vez de fingir un control que no está.

## Alcance

**Entra:** modelo y reglas de `blocks` y `reports`, enforcement en lectura de
posts y en escritura de chat, entrada de reporte y bloqueo en las cuatro
superficies, y tests negativos de reglas.

**No entra, y queda anotado:** moderación de imágenes, la vista de revisión de
reportes para el equipo, y el filtrado preventivo de términos vetados. Los tres
son necesarios para cerrar 1.2 del todo, pero ninguno bloquea a los otros dos.

## Nombres que NO se pueden usar

`blockedAthleteIds`, `blocked_athletes_providers.dart` y `BlockedStudentsScreen`
ya existen y significan **otra cosa**: alumnos fuera del cupo del plan pago del
entrenador. Nada de este cambio puede reusar ese vocabulario.

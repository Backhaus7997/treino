# Play Console — *Data safety* (borrador)

Borrador para que el equipo lo revise **antes** de cargarlo en Play Console.
Cada fila sale de código verificado, no de suposiciones. La columna *Dónde*
apunta a la evidencia.

> Google audita esto contra el comportamiento real del binario. Una
> declaración incompleta es motivo de rechazo o de baja de la ficha.

Verificado contra el código el **2026-08-25**.

---

## Resumen de las tres preguntas globales

| Pregunta | Respuesta | Por qué |
|---|---|---|
| ¿La app recolecta o comparte datos de usuario? | **Sí** | Firestore, Auth, Storage, Analytics, Crashlytics |
| ¿Los datos se cifran en tránsito? | **Sí** | Todo va por HTTPS/TLS vía los SDK de Firebase |
| ¿El usuario puede pedir que se borren sus datos? | **Sí** | Borrado de cuenta en la app (`account_deletion_notifier.dart`) con borrado en cascada por Cloud Function |

---

## Tipos de datos a declarar

### Información personal

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Nombre | Sí | No | Opcional | Funcionalidad de la app | `UserProfile.firstName` / `lastName` |
| Email | Sí | No | **Obligatorio** | Funcionalidad, autenticación | `firebase_auth` |
| Teléfono | Sí | No | Opcional | Funcionalidad | `UserProfile.phone` — privado, no se propaga a `userPublicProfiles` |
| ID de usuario | Sí | No | Obligatorio | Funcionalidad, autenticación | `uid` de Firebase Auth |
| **Género** | Sí | No | Opcional | Funcionalidad | `UserProfile.gender` (`user_profile.dart:37`) — se escribe en cada profile setup completo |
| **Fecha de nacimiento** | Sí | No | Opcional | Funcionalidad | `UserProfile.bornAt` (`user_profile.dart:48`) — desde el editor de perfil personal |

Google clasifica **género** y **fecha de nacimiento** como información
personal. Los dos se escriben a Firestore desde el cliente de producción, así
que van declarados sí o sí.

### Ubicación

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Ubicación aproximada | Sí | No | **Opcional** | Funcionalidad — discovery de gimnasios cercanos | `geolocator`, `lib/core/utils/geohash.dart`, `nearby_gyms_list.dart` |
| **Ubicación precisa** | Sí | No | **Opcional** | Funcionalidad — ubicación de trabajo del PF | `TrainerLocation.lat` / `.lng` (`trainer_location.dart`), seteados desde `profile_edit_trainer_screen.dart:1049-1050` |

Para el atleta es opcional de verdad: si no da permiso, discovery cae a búsqueda
por nombre y especialidad sin orden geográfico.

⚠️ Para el **trainer** hay que declarar **ubicación precisa**: `TrainerLocation`
persiste `lat` y `lng` crudos, no sólo el geohash. Ver
[`privacy-labels.md`](./privacy-labels.md) — el mismo hallazgo aplica a Apple.

### Fotos y videos

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Fotos | Sí | No | Opcional | Funcionalidad — avatar, posts del feed, media de chat, foto adjunta al reporte de molestias | `image_picker`, `firebase_storage` |
| Videos | Sí | Sí — con el PF vinculado | Opcional | Funcionalidad — video adjunto en el chat, y videos de ejercicios propios que sube el PF | `chat_screen.dart:208` (`pickVideo`) → `storage.rules:336`; `customExerciseVideos` → `storage.rules:197` |

**Play Console trata Fotos y Videos como tipos SEPARADOS**, cada uno con su
propia casilla. Este cuadro declaraba sólo Fotos, así que quien cargara la
ficha siguiendo el documento dejaba Videos sin tildar — aunque el picker del
chat llama a `pickVideo` y la regla de Storage acepta `video/*`.

### Datos de salud y estado físico ⚠️

**El bloque más sensible de la ficha.** Google trata salud como categoría
especial y la mira con lupa.

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Info de salud | **Sí** | Sí — sólo con el PF vinculado | Opcional | Funcionalidad | `exerciseFeedback` con `kind: discomfort` = **dolor declarado**, más `photoUrl` (commit `99644ed3`, #795/#628) |
| Info de estado físico | **Sí** | Sí — sólo con el PF vinculado | **Obligatorio** | Funcionalidad | Peso, altura y **20+ medidas corporales** (`measurement.dart`) **más** el historial de sesiones |

Sobre el "Sí" de *Compartido*: los datos no salen a terceros, pero sí a **otro
usuario** — el PF vinculado. Play cuenta eso como compartir. El gate es
`sharedWithTrainer` y el predicado de `session_shares`; el PF nunca puede
escribir datos del alumno (canal one-way).

> **Por qué esta fila va con UNA sola respuesta, y por qué es «Obligatorio».**
>
> Play Console expone **un** tipo `Info de estado físico` con **una** respuesta
> de obligatorio-versus-opcional. No admite dos filas, así que partirla —como
> hacía la versión anterior de este documento— deja a quien carga la ficha
> eligiendo entre dos respuestas contradictorias, que es exactamente el
> problema que el documento existe para evitar.
>
> El dato se recolecta por dos caminos con respuestas distintas:
>
> - Las **20+ medidas corporales** se cargan a mano. Un usuario puede entrenar
>   meses sin abrir Mediciones: por sí solas serían *opcional*.
> - El **historial de sesiones** se genera por usar la función central del
>   producto. No hay forma de entrenar en TREINO sin producirlo.
>
> La regla de Google para un tipo recolectado por un camino opcional **y** uno
> no opcional es declararlo como **no opcional**: la pregunta es si el usuario
> puede usar la app sin dar el dato, y acá no puede.
>
> El desglose queda escrito igual, porque es lo que justifica la respuesta y lo
> que hay que volver a mirar si algún día el historial deja de ser obligatorio.

### Información financiera

Hay dos cosas distintas acá, y sólo una es una compra.

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Historial de compras | Sí | No | Opcional | Funcionalidad — estado de la suscripción | `users/{uid}.subscription` (entrenador) y `users/{uid}.athleteSubscription` (alumno). **Los dos por Mercado Pago**, escritos por el mismo `functions/src/subscriptions/mp/reconcile.ts`, ramificado por `producto` |
| Otra info financiera | Sí | Sí — entre el alumno y su PF | Opcional | Funcionalidad — la cuota que el alumno le paga al entrenador | `athleteBilling` (`{trainerId, athleteId, amountArs, cadence}`, `firestore.rules:3988`) y `payments/{paymentId}` (`firestore.rules:4203`) |

**La segunda fila es la que se olvida.** TREINO **no intermedia** esa plata — el
alumno le paga al entrenador por fuera— pero **sí registra cuánto es y si está
paga** (decisión D5). Que el dinero no pase por la app no cambia que el monto
esté guardado en ella, y Play pregunta por el dato, no por el flujo de fondos.

**Ningún número de tarjeta ni dato bancario toca la app.** Mercado Pago y las
compras integradas de Apple/Google resuelven el cobro en su propio checkout;
TREINO sólo recibe el estado resultante.

### Mensajes

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Otros mensajes en la app | Sí | No | Opcional | Funcionalidad — chat atleta ↔ PF | Chat del módulo Coach |

### Actividad en la app

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Interacciones | Sí | No | Obligatorio | Analytics | `firebase_analytics` |
| Contenido generado por el usuario | Sí | Sí — según privacidad del post | Opcional | Funcionalidad | Posts del feed (amigos / comunidad / público) |

### Rendimiento de la app

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Registros de fallos | Sí | No | Obligatorio | Diagnóstico | `firebase_crashlytics` |
| Diagnóstico | Sí | No | Obligatorio | Diagnóstico | `firebase_crashlytics` |

### Identificadores de dispositivo

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Token de push | Sí | No | Opcional | Notificaciones | `firebase_messaging` |

---

### Archivos y documentos

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Otros archivos y documentos | Sí | Sí — entre el PF y su alumno | Opcional | Funcionalidad — archivos que el entrenador adjunta al legajo del alumno | `alumno_detail_screen.dart:3684` (`allowedExtensions: ['pdf', …]`), `AthleteFileRepository`, `storage.rules:380` (`application/pdf`, < 10 MB) |

**Esta sección decía «NO se declara», y era falso.** El razonamiento miraba sólo
el adjunto del chat —que efectivamente es sólo imagen y video— y sacaba una
conclusión categórica sobre *todos* los caminos de subida de la app. Hay otro:
el Coach Hub deja al entrenador cargar **PDFs** en el legajo del alumno, y las
reglas de Storage los aceptan.

Un «verificado que no» sobre una categoría entera, cuando en realidad se
verificó un solo camino, es peor que no haberlo mirado: la próxima persona lee
la evidencia citada, la da por cerrada, y la categoría queda sin tildar en Play
Console.

**Lo que sí sigue siendo cierto:** el adjunto del **chat** acepta sólo imágenes
y videos, y no por el picker —eso se saltea con el SDK— sino porque
`storage.rules` lo exige por `contentType`:

```
match /chatMedia/{chatId}/{userId}/{file=**}
  request.resource.contentType.matches('image/.*')   && size < 15 MB
  || request.resource.contentType.matches('video/.*') && size < 50 MB
```

Eso acota el chat. No acota `athleteFiles`, que es otro bloque de reglas.

**Cómo verificar los caminos de subida, entero y no de a uno.** El comando que
debí correr la primera vez:

```bash
rg -n 'contentType' storage.rules | rg -v '^\s*//'
```

Cada `match` con `contentType` es un camino de subida. Al 2026-09-18 devuelve
**ocho**, y entre todos aceptan exactamente tres cosas:

| tipo | dónde |
|---|---|
| `image/*` | `avatars`, `postPhotos`, `sessionFeedback`, `chatMedia`, `athleteFiles` |
| `video/*` | `chatMedia`, `customExerciseVideos` |
| `application/pdf` | `athleteFiles` — **el único** |

Si ese comando devuelve un `contentType` que no esté en esta tabla, hay un tipo
de dato sin declarar.

## Pendientes antes de cargar

- [ ] **Política de privacidad publicada en una URL pública.** Play la exige y
      hoy no existe. Es bloqueante duro de la publicación.
- [ ] Confirmar si Analytics queda activo en el build de release o se apaga.
- [ ] Decidir si Rankings cuenta como *contenido compartido públicamente*. Es
      opt-in explícito del atleta y el scope es por gimnasio, pero el opt-in hay
      que reflejarlo acá.
- [ ] **Compras dentro de la app**: depende de #644, que está congelada. Hoy el
      binario móvil **no** tiene ningún flujo de pago — el paywall del PF vive en
      el Coach Hub **web** (`lib/features/coach_hub/`), no en la app. Con el
      código de hoy la respuesta es **no**.

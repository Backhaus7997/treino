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

### Datos de salud y estado físico ⚠️

**El bloque más sensible de la ficha.** Google trata salud como categoría
especial y la mira con lupa.

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Info de salud | **Sí** | Sí — sólo con el PF vinculado | Opcional | Funcionalidad | `exerciseFeedback` con `kind: discomfort` = **dolor declarado**, más `photoUrl` (commit `99644ed3`, #795/#628) |
| Info de estado físico — medidas | **Sí** | Sí — sólo con el PF vinculado | **Opcional** | Funcionalidad | Peso, altura y **20+ medidas corporales** (`measurement.dart`: `fatPercentage`, `muscleMassKg`, `waistCm`, `bicepsLCm`, …) |
| Info de estado físico — historial de sesiones | **Sí** | Sí — sólo con el PF vinculado | **Obligatorio** | Funcionalidad | Cada serie marcada en un entreno |

Sobre el "Sí" de *Compartido*: los datos no salen a terceros, pero sí a **otro
usuario** — el PF vinculado. Play cuenta eso como compartir. El gate es
`sharedWithTrainer` y el predicado de `session_shares`; el PF nunca puede
escribir datos del alumno (canal one-way).

> **Por qué esta fila está partida en dos.**
>
> Google pregunta si el usuario puede usar la app **sin dar el dato**, y para
> estas dos cosas la respuesta es distinta:
>
> - Las **20+ medidas corporales** se cargan a mano desde Mediciones. Un usuario
>   puede entrenar durante meses sin tocar esa pantalla. Opcional es correcto.
> - El **historial de sesiones** se genera por usar la función central del
>   producto. No hay forma de entrenar en TREINO sin producirlo, así que no es
>   opcional en el sentido que la pregunta le da a esa palabra.
>
> Una sola fila `Opcional` cubriendo las dos declara el historial como algo que
> el usuario puede no dar, y no puede. Esa clase de imprecisión es la que hace
> que Play rechace una ficha completa, no una fila.

### Información financiera

Hay dos cosas distintas acá, y sólo una es una compra.

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Historial de compras | Sí | No | Opcional | Funcionalidad — estado de la suscripción | `users/{uid}.subscription` (entrenador, Mercado Pago: `functions/src/subscriptions/mp/reconcile.ts`) y `users/{uid}.athleteSubscription` (alumno, RevenueCat: `functions/src/subscriptions/rc/`) |
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

### Archivos y documentos — **NO se declara**

Verificado, y queda anotado acá para que la próxima persona no repita el
trabajo.

El adjunto del chat acepta **sólo imágenes y videos**, y no es una restricción
del cliente que se pueda saltear con el SDK: la hacen cumplir las reglas de
Storage.

```
storage.rules — match /chatMedia/{chatId}/{userId}/{file=**}
  request.resource.contentType.matches('image/.*')  && size < 15 MB
  || request.resource.contentType.matches('video/.*') && size < 50 MB
```

Cualquier otro `contentType` se deniega del lado del servidor. Del lado del
cliente, `MediaType` (`lib/features/chat/domain/media_type.dart`) tiene
exactamente dos valores —`image` y `video`— y el picker abre `pickImage` /
`pickVideo`.

Conclusión: **queda cubierto por “Fotos y videos”.** Si alguna vez se agrega un
tercer valor a `MediaType`, o si esas dos líneas de `storage.rules` se aflojan,
esta sección hay que rehacerla.

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

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

### Ubicación

| Tipo | Recolectado | Compartido | Obligatorio | Propósito | Dónde |
|---|---|---|---|---|---|
| Ubicación aproximada | Sí | No | **Opcional** | Funcionalidad — discovery de PF y gimnasios cercanos | `geolocator`, `lib/core/utils/geohash.dart`, `nearby_gyms_list.dart` |

Es opcional de verdad: si el atleta no da permiso, discovery cae a búsqueda por
nombre y especialidad sin orden geográfico.

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
| Info de estado físico | **Sí** | Sí — sólo con el PF vinculado | Opcional | Funcionalidad | Peso, altura y **20+ medidas corporales** (`measurement.dart`: `fatPercentage`, `muscleMassKg`, `waistCm`, `bicepsLCm`, …) + historial de sesiones |

Sobre el "Sí" de *Compartido*: los datos no salen a terceros, pero sí a **otro
usuario** — el PF vinculado. Play cuenta eso como compartir. El gate es
`sharedWithTrainer` y el predicado de `session_shares`; el PF nunca puede
escribir datos del alumno (canal one-way).

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

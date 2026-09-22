# App Store Connect — *Privacy Nutrition Labels* (borrador)

Borrador para que el equipo lo revise **antes** de cargarlo en App Store
Connect. Mismo inventario que [`data-safety.md`](./data-safety.md), reordenado
según las categorías de Apple, que no son las de Google.

Verificado contra el código el **2026-09-22**. La revisión anterior era del
2026-08-25 y sus cuatro pendientes están cerrados al final del archivo.

---

## Las tres preguntas que ordenan todo

Apple clasifica cada dato en uno de tres buckets:

| Bucket | Aplica a TREINO |
|---|---|
| **Data Used to Track You** | **Ninguno.** No hay data brokers, ni ad SDKs, ni cruce con datos de terceros → **no hace falta App Tracking Transparency** |
| **Data Linked to You** | Casi todo — está atado al `uid` de Firebase Auth |
| **Data Not Linked to You** | Diagnóstico de Crashlytics |

> Que no haya tracking es una ventaja de venta y hay que sostenerla: el día que
> entre un SDK de publicidad o de atribución, esta sección cambia y aparece el
> prompt de ATT.

---

## Data Linked to You

### Contact Info
| Dato | Propósito |
|---|---|
| Email | Funcionalidad de la app |
| Nombre | Funcionalidad de la app |
| Teléfono | Funcionalidad de la app |

### Health & Fitness ⚠️
| Dato | Propósito |
|---|---|
| **Health** | Funcionalidad — `exerciseFeedback` con `kind: discomfort` es **dolor declarado**, y guarda `photoUrl` (commit `99644ed3`, #795/#628) |
| **Fitness** | Funcionalidad — peso, altura, 20+ medidas corporales (`measurement.dart`), historial de sesiones, volumen, rachas |

Apple es más estricta que Google acá. Dos cosas que importan:

1. **Guideline 5.1.3**: los datos de salud no se pueden usar para publicidad ni
   marketing, ni compartirse con data brokers. TREINO no hace ninguna de las
   dos — hay que poder sostenerlo si Review pregunta.
2. TREINO **no** usa HealthKit. Si algún día se integra, esto se reabre entero.

### Location ⚠️
| Dato | Propósito |
|---|---|
| **Precise Location** | Funcionalidad — ubicación de trabajo del PF |
| Coarse Location | Funcionalidad — discovery de gimnasios cercanos |

**Hay que declarar Precise Location, no sólo Coarse.** `TrainerLocation`
(`lib/features/coach/domain/trainer_location.dart`) tiene `required double lat`
y `required double lng`, y su propio dartdoc dice que *"`lat`, `lng` y
`geohash` SIEMPRE están seteados"*. Cuando el PF usa "Detectar ubicación",
`profile_edit_trainer_screen.dart:1049-1050` toma `pos.latitude` /
`pos.longitude` crudos y se persisten enteros — el `geohash5` se guarda
**además**, no en lugar de.

O sea: para el rol **trainer** se recolectan coordenadas exactas. Declarar sólo
Coarse sería sub-reportar.

Del lado **atleta** la ubicación sí queda en geohash para discovery. Si se
quiere declarar sólo Coarse, primero hay que dejar de persistir `lat`/`lng`
crudos en `trainerLocations` — es un cambio de código, no de formulario.

### User Content
| Dato | Propósito |
|---|---|
| Photos or Videos | Funcionalidad — avatar, posts, media de chat, foto del reporte de molestias |
| Other User Content | Funcionalidad — posts del feed, mensajes de chat, notas de rutina |

### Identifiers
| Dato | Propósito |
|---|---|
| User ID | Funcionalidad, autenticación |

### Usage Data
| Dato | Propósito |
|---|---|
| Product Interaction | Analytics |

---

## Data Not Linked to You

### Diagnostics
| Dato | Propósito |
|---|---|
| Crash Data | Diagnóstico de la app |
| Performance Data | Diagnóstico de la app |

---

## Resuelto — lo que era pendiente y ya no

- [x] **URL de política de privacidad.** **Publicada y verificada en vivo el
      2026-09-22:** `https://gettreino.com/es/privacidad`. Es la URL que va en la
      ficha.

      Este renglón decía *"hoy no existe. Bloqueante duro"*, y era el único
      bloqueante declarado del documento. Ya no lo es. La página se genera desde
      `docs/legal/politica-de-privacidad.md` —fuente única— y `app.gettreino.com`
      sirve el mismo texto desde el mismo lugar. Las dos superficies dejaron de
      poder divergir.

- [x] **In-app purchases: NO.** Y ahora es verdad.

      ⚠️ **Antes NO lo era**, y conviene que quede escrito. Este renglón decía
      que *"el binario iOS no tiene ningún flujo de pago"* mientras `pubspec.yaml`
      arrastraba `purchases_flutter`, que trae StoreKit en iOS y
      `com.android.billingclient:billing` en Android. Se declaraba una cosa y el
      binario contenía la contraria.

      Cerrado por los PRs #1201 (el SDK fuera del binario) y #1206 (el webhook y
      su backend). **Nunca procesó una compra real.** El alumno paga por Mercado
      Pago en `gettreino.com`, y el entrenador en el Coach Hub web.

      ⚠️ Lo que SIGUE valiendo: si alguna vez el atleta paga por contenido digital
      **desde la app**, aplica la **guideline 3.1.1** y hay que usar IAP de Apple,
      no Mercado Pago. Eso además reabre el Beta App Review de TestFlight. Y la
      app tampoco puede decir dónde se compra — nombrar la landing desde el
      binario es un *call to action for purchase outside of the app* y tira abajo
      la exención 3.1.3(f) del entrenador. Lo fija
      `test/features/paywall/superficie_de_cobro_alumno_test.dart`.

- [x] **Account deletion, guideline 5.1.1(v).** El borrado en cascada **sí** cubre
      Storage: `functions/src/__tests__/cascade/storage.test.ts` verifica que
      `deleteAvatar` borre `avatars/{uid}` en jpg y en heic, y que
      `deleteAthleteStorage` limpie `temp/`, `customExerciseVideos/`,
      `chatMedia/` y `athleteFiles/` del uid **sin tocar los de otros**.

- [x] **Analytics en release: SÍ, activo.** Pero con un matiz que importa para la
      ficha: pasa por `analyticsConsentFromPrefs`
      (`lib/core/analytics/analytics_consent.dart:21`), que lee
      `kAnalyticsConsentKey` con default `true`. Es **opt-out**: viene prendido y
      el usuario lo puede apagar.

      Apple no distingue obligatorio de opcional en las etiquetas, así que acá no
      cambia nada. **En Play sí** — ver `data-safety.md`.

## Pendientes antes de cargar

Ninguno bloqueante. Los cuatro de arriba están cerrados con evidencia.

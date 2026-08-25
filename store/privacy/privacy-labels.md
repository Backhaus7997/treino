# App Store Connect — *Privacy Nutrition Labels* (borrador)

Borrador para que el equipo lo revise **antes** de cargarlo en App Store
Connect. Mismo inventario que [`data-safety.md`](./data-safety.md), reordenado
según las categorías de Apple, que no son las de Google.

Verificado contra el código el **2026-08-25**.

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

## Pendientes antes de cargar

- [ ] **URL de política de privacidad.** App Store Connect la exige en la ficha.
      Hoy no existe. Bloqueante duro, igual que en Play.
- [ ] Confirmar si Analytics queda activo en release.
- [ ] Revisar que el **account deletion** cumpla la guideline 5.1.1(v) — Apple
      exige borrado de cuenta desde adentro de la app para toda app que permita
      crearla. `account_deletion_notifier.dart` existe; falta verificar que el
      borrado en cascada cubra Storage además de Firestore.
- [ ] **In-app purchases**: depende de #644 (congelada). Con el código de hoy el
      binario iOS **no** tiene ningún flujo de pago — el paywall del PF vive en
      el Coach Hub **web**. Respuesta hoy: **no**.
      ⚠️ Si alguna vez el atleta paga por contenido digital desde la app, aplica
      la **guideline 3.1.1** y hay que usar IAP de Apple, no Mercado Pago. Eso
      además reabre el Beta App Review de TestFlight.

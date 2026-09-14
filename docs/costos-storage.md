# Costos de Storage y el tope de videos de ejercicio custom

Por qué existe un tope de videos, de dónde salen los números, y por qué está
implementado en tres capas en vez de una.

Hermano de [`paywall-alumno-suelto.md`](./paywall-alumno-suelto.md) (que fija el
PRECIO) y de [`security.md`](./security.md) (que explica las reglas de Storage).
Acá se trata el COSTO.

---

## 1. La medición — 2026-09-10, bucket `treino-dev.firebasestorage.app`

**1.964 objetos, 1.135,78 MB.** Antes de proponer un tope hubo que medir, porque
la intuición sobre dónde estaban los bytes resultó equivocada.

| Prefijo | Objetos | MB | Qué es |
|---|---:|---:|---|
| `exerciseVideos` | 1.122 | 859,17 | Catálogo del sistema |
| `exercises` | 817 | 142,42 | Catálogo del sistema |
| `chatMedia` | 15 | 127,18 | UGC |
| `postPhotos` | 1 | 3,81 | UGC |
| `customExerciseVideos` | 3 | 2,84 | UGC |
| `avatars` | 3 | 0,19 | UGC |
| `athleteFiles` | 3 | 0,17 | UGC |

Usuarios: **58** (53 `athlete`, 5 `trainer`). 13 con `subscription` de PF, **0**
con `athleteSubscription` — consistente con que el webhook del alumno todavía no
existe.

Tres conclusiones, y ninguna era la esperada:

1. **El 88% del bucket es catálogo del sistema.** `exerciseVideos` + `exercises`
   son 1.001 MB de costo FIJO, que no escala con usuarios. El UGC real son
   134 MB → **2,31 MB por usuario promedio**. No hay incendio hoy.
2. **`customExerciseVideos` tiene UN dueño, y es un PF.** Tres videos, 2,84 MB.
   **Ningún alumno subió jamás uno.** La adopción del lado que el paywall
   gatearía es cero — que es exactamente la mejor hora para poner un tope,
   porque no le saca nada a nadie.
3. **`chatMedia` es 45x más grande con el mismo agujero.** 127 MB en 15 objetos
   = **8,5 MB por objeto**, y `storage.rules` le da los mismos 100 MB/archivo
   sin tope de cantidad ni gate de paywall. **Es deuda abierta, no resuelta por
   este cambio.** Y el chat genera bytes de forma continua, mientras que una
   videoteca de tutoriales se arma una vez.

### Cómo repetir la medición

No hay `gcloud` ni ADC en las máquinas del equipo. El camino es:

1. `firebase login` (el refresh token queda en
   `~/.config/configstore/firebase-tools.json` — **no** en `%APPDATA%`).
2. Intercambiarlo en `oauth2.googleapis.com/token` con el `client_id` /
   `client_secret` públicos de `firebase-tools`.
3. Pegarle a `storage.googleapis.com/storage/v1/b/<bucket>/o` (paginado con
   `nextPageToken`) y a la REST de Firestore para cruzar uid → `role`.

El token de acceso dura una hora y el refresh pide reauth cada tanto
(`invalid_rapt`); si la medición se corta a la mitad, es eso.

---

## 2. El modelo de costo — por qué el egress manda

Precios de Firebase Storage (GCS Standard):

| Línea | Precio |
|---|---|
| Almacenamiento | USD 0,026 / GB-mes |
| **Descarga (egress)** | **USD 0,12 / GB** |

**El egress es 4,6x el precio de guardar ese mismo GB un mes entero**, y se
cobra *cada vez que alguien le da play*.

Y acá no hay nada que lo amortigüe: los videos se sirven por la URL
`?alt=media&token=` que emite `getDownloadURL()`, que es **GCS directo, sin CDN
ni capa de cache adelante** (ver [`security.md`](./security.md) §3.1 y el bloque
`customExerciseVideos` de `storage.rules`). La app siempre renderiza desde la URL
persistida en `users/{uid}/customExercises/{id}.videoUrl`.

De ahí la conclusión que ordena todo el diseño:

> **El tope POR ARCHIVO es la palanca principal, no el de cantidad.** El tamaño
> del archivo es lineal en las DOS líneas de costo; la cantidad sólo en la de
> almacenamiento. Bajar el cap de 100 a 25 MB divide por 4 el egress de cada
> reproducción, sin tocar nada más.

### El umbral que importa

Con la proporción esperada de ~70 usuarios free por pagador y un margen de
**ARS 3.833/mes por pagador**, el punto en que el costo del free anula el margen
es:

```
ARS 3.833 / 70 = ARS 54,75 por usuario free por mes
```

Es un presupuesto chico. A modo de referencia, ese monto compra del orden de
**1 a 2 GB almacenados permanentemente**, o **0,2 a 0,5 GB de descarga mensual**,
según el tipo de cambio. Un solo video de 100 MB re-mirado tres veces al mes se
lo come entero.

---

## 3. Los topes

| | Alumno free | PF / alumno que paga o está vinculado |
|---|---:|---:|
| MB por archivo | **25** | 100 |
| Videos | **3** | 50 |

**25 MB por archivo** sale de la medición, no del dedo: el archivo más grande
jamás subido pesa **2,59 MB** y la mediana es **0,13 MB**. 25 MB es 10x el máximo
real observado — headroom de sobra para un tutorial de un minuto en 720p. El cap
histórico de 100 MB era **39x** el máximo observado: un techo decorativo.

**3 videos** espeja `kFreeMaxOwnRoutines`: el free tiene «tres de lo suyo». Peor
caso 75 MB permanentes.

**No hay tope de MB TOTALES**, y es deliberado: `cantidad × por-archivo` ya acota
el total. Una tercera perilla agregaría superficie de configuración por 25 MB de
ahorro.

**50 videos** para todos los demás es techo anti-abuso, no palanca de conversión:
5 GB ≈ USD 0,13/mes. Sin él, una cuenta `trainer` —que el paywall del alumno NO
gatea, y con razón— tiene subida ilimitada de 100 MB. Nadie legítimo se acerca:
el PF con más videos del proyecto tiene 3.

---

## 4. Dónde vive el enforcement, y por qué en tres capas

Se evaluaron las tres opciones. **Ninguna alcanza sola**, y no son alternativas:
son capas con trabajos distintos.

| Capa | Qué puede | Qué NO puede |
|---|---|---|
| `storage.rules` | Cap por archivo (`request.resource.size`) y tier, preventivamente | **Contar objetos** — no hay agregación en las reglas de Storage |
| Cloud Function | Contar, y borrar el excedente | Prevenir: `onObjectFinalized` corre **después** de que los bytes entraron y se pagaron |
| Cliente | Avisar antes de gastar datos móviles | Ser ley — es evadible |

### El diseño resultante

```
subida  ──►  storage.rules          ──►  bucket  ──►  onObjectFinalized
             (preventivo: tamaño          │            (reactivo: recuenta,
              + tier + lee el contador)   │             borra el excedente,
                     ▲                    │             escribe el contador)
                     └────────────────────┴──── users/{uid}.customExerciseVideoUsage
```

- **La regla es el gate preventivo.** Atrapa el caso normal —subida secuencial,
  que es lo que hace el editor— *antes* de que los bytes entren, que es la única
  forma de no pagarlos. Lee el tier de `users/{uid}.athletePaywallEnforced` y el
  conteo de `users/{uid}.customExerciseVideoUsage.count` con **un solo**
  `firestore.get()`.
- **La CF es la red reactiva.** El contador va atrasado por construcción: el
  trigger corre después del aterrizaje. Un cliente que dispare N subidas en
  paralelo las evalúa todas contra el mismo valor viejo y se pasa por el tamaño
  de la ráfaga. La CF cierra esa carrera **borrando el excedente**, conservando
  los archivos MÁS VIEJOS (que son los que los docs `customExercises` ya
  referencian por `videoUrl`).
- **El cliente es UX.** Chequea la cantidad *antes* de abrir la galería (si ya
  está en el tope no hay nada que pueda elegir que entre) y el tamaño *después*
  de elegir (recién ahí se sabe cuánto pesa). Sin esto el alumno manda hasta
  100 MB de datos móviles para que el servidor los rechace al final.

### Por qué el contador se denormaliza

Es el mismo patrón —y el mismo motivo— que `athletePaywallEnforced`: **lo que la
regla no puede resolver, lo resuelve una CF y la regla lee la conclusión.**

El campo es **CF-write-only**, pineado en `firestore.rules` en el create *y* en
el update de `users/{uid}`. Sin ese pin el bypass es una sola escritura
—`{customExerciseVideoUsage: {count: 0}}`— y el tope de cantidad deja de existir
para quien la mande.

La CF **recuenta** el prefijo en vez de incrementar: la entrega de Eventarc es
at-least-once, y un `FieldValue.increment()` se aplicaría dos veces en una
redelivery dejando el contador desviado para siempre. Un contador de cuota
desviado hacia abajo es un tope que no existe. Mismo criterio que
`maintainReactionCounters` (W-SOCIAL-COUNTERS-01).

### La trampa del PF

`athleteEntitlementProvider` (cliente) **devuelve `free` para un PF**: no mira
`role`, y un PF no tiene ni vínculo como alumno ni `athleteSubscription`.

Eso hoy es inofensivo porque los gates del paywall viven en pantallas
athlete-only. Pero **`CustomExerciseEditorScreen` es superficie COMPARTIDA** — la
abren el alumno (`profile_screen.dart`, `exercise_picker_sheet.dart`) y el PF
(`trainer_profile_view.dart`, Coach Hub web).

Por eso el enforcement se cuelga de `athletePaywallEnforced` y **no** del
provider del cliente: `resolveAthletePaywallEnforced` corta en
`if (userData?.role !== "athlete") return false`. Colgarlo del provider le
rompería la videoteca a todos los PF el día que se prenda
`kAthletePaywallEnabled`.

---

## 5. Los cuatro números viven en cuatro lugares

No hay nada que los sincronice. Si cambiás uno, cambiá los cuatro:

| Lugar | Qué |
|---|---|
| `lib/features/paywall/domain/athlete_entitlement.dart` | Las constantes `kFreeMaxCustomExerciseVideos`, `kFreeMaxCustomExerciseVideoBytes`, `kMaxCustomExerciseVideos`, `kMaxCustomExerciseVideoBytes` |
| `storage.rules` | Los literales del ternario en `videoWriteAllowed()` |
| `functions/src/storage/custom-exercise-video-quota.ts` | `FREE_MAX_VIDEOS`, `FREE_MAX_VIDEO_BYTES`, `MAX_VIDEOS`, `MAX_VIDEO_BYTES` |
| `functions/src/__tests__/custom-exercise-video-quota.test.ts` | Escritos literales en los asserts **a propósito**, para que un tope movido sin querer dé rojo |

Si la copia de la CF fuera **más permisiva** que la regla, la CF no borraría lo
que la regla ya rebotó y no pasaría nada. Si fuera **más estricta**, borraría
videos que la regla aceptó: el usuario ve la subida exitosa y el archivo
desaparece solo. Ese es el modo de falla caro, y es mudo.

Ojo también con `lib/l10n/*.arb`: los topes de paywall en TREINO han vivido
escritos a mano dentro de las cadenas. Los mensajes de este gate se arman desde
las constantes, así que ese eje no se puede desincronizar — pero antes de mover
cualquier otro tope, `rg` el número literal en los `.arb`.

---

## 6. Qué queda pendiente

- **`chatMedia` tiene el mismo agujero y 45x más bytes.** 100 MB/archivo, sin
  tope de cantidad, sin gate. Es el lugar donde hoy se acumula el UGC real.
- **`postPhotos` y `athleteFiles`** no se revisaron en este pase.
- **Región del trigger**: la CF se despliega en `southamerica-east1` porque el
  bucket está ahí (`roadmap.md`, Fase 1 Etapa 6). Un trigger de Storage en otra
  región **falla al deployar** — es un rojo ruidoso, no un bug silencioso.
- **El tope de cantidad no tiene grandfathering**, igual que el resto del
  paywall del alumno. Hoy no hace falta (ningún alumno tiene videos), pero si
  eso cambia antes de prender `kAthletePaywallEnabled`, revisá el mismo problema
  que documenta `athlete-paywall-enforced.ts` para las rutinas de 4 y 5 días.

# Paywall del alumno suelto — spec

> Estado: **propuesta, sin código**. Depende de la telemetría de forma de rutina
> (`routine_created`, `routine_day_added`, `routine_week_added`), ya mergeada en
> `main` en [#943](https://github.com/Backhaus7997/treino/pull/943). No se
> construye hasta que esos eventos hayan corrido en producción el tiempo
> suficiente para responder las preguntas de la sección 9 — el reloj arranca
> con el primer release que los incluya, no con el merge.
>
> Escrito el 2026-09-03. Toda afirmación sobre el código cita archivo y línea
> de `main` en `3edca9ce`. Las referencias externas de mercado vienen del brief
> de Martín (2026-09-03) y se re-verificaron **parcialmente** en esta sesión:
> la sección 8 dice cuál se confirmó, cuál se corrigió y cuál sigue sin fuente
> primaria. El detalle está en la sección 11.

---

## 1. Qué decide esta spec y qué no

Decide **para quién**, **qué se cobra**, **qué pasa al cancelar**, **cómo se
haría cumplir** y **cómo se cobra**. Y deja escrito qué número tiene que mostrar
la telemetría para que valga la pena construirlo.

No decide **si** se construye. Hoy TREINO está pre-lanzamiento, con 8 testers en
TestFlight. El segmento tiene cero usuarios. Construir el paywall ahora sería
optimizar la conversión de un embudo que todavía no tiene agua.

---

## 2. Segmento: solo alumnos sueltos

**Paga únicamente el alumno sin profe.** El alumno vinculado a un PF que paga no
paga nada, nunca — ni por días, ni por semanas, ni por gráficos.

Esto no es una preferencia de producto: es la norma de la categoría. Seis
plataformas de coaching lo declaran textualmente en sus páginas oficiales
(TrueCoach: *"TrueCoach is 100% free for your clients"*; Trainerize, Everfit,
My PT Hub, Kahunas, Hevy Coach — Hevy Coach incluso regala Hevy Pro a los
alumnos del coach). Y el PF ya paga por ese alumno: a capacidad llena son
ARS 1.466–1.714 por alumno-mes (brief, 2026-09-03).

### Cómo se identifica al segmento en el código

- Un alumno **vinculado** tiene rutinas `source == 'trainer-assigned'` con
  `assignedTo == uid` — `RoutineRepository.listAssignedTo`
  ([routine_repository.dart:383-391](../lib/features/workout/data/routine_repository.dart)).
- Un alumno **suelto** solo tiene rutinas `source == 'user-created'` con
  `createdBy == uid` — `RoutineRepository.listUserCreated`
  ([routine_repository.dart:131-139](../lib/features/workout/data/routine_repository.dart)).
- El vínculo en sí vive en `TrainerLinkRepository` (evento `link_accepted`,
  [analytics_service.dart](../lib/core/analytics/analytics_service.dart)).

El enforcement (sección 6) tiene que mirar el **vínculo activo**, no la
existencia de rutinas asignadas: un alumno que se desvinculó conserva las
rutinas viejas y pasa a ser suelto.

---

## 3. Tres hechos del código que fijan el encuadre

### 3.1 TREINO no tiene logging libre → "gratis entrenás, pago programás"

`SessionInit` es un `sealed class` de dos variantes y `FreshSession` exige
`routineId` no-nullable
([session_init.dart:8-34](../lib/features/workout/application/session_init.dart)).
Toda sesión nace de una rutina + día. No hay quick-log, no hay freestyle.

Por eso el encuadre "gratis = logger completo" — que sí vale para Hevy y Strong,
donde podés registrar cualquier entrenamiento sin rutina — **es falso acá**. El
encuadre honesto es: **gratis entrenás, pago programás**. Lo que se limita es la
capacidad de *diseñar* programas, nunca la de *ejecutar* el que ya tenés.

### 3.2 Un free de 1 día con periodización está roto

`nextPlanPosition` avanza la semana cuando `rolledOver`, y
`rolledOver = lastFinished.dayNumber >= numDays`
([plan_advance.dart:52](../lib/features/workout/domain/plan_advance.dart)).
Con `numDays == 1` eso es **siempre verdadero**: la semana avanza en cada sesión
terminada. Un plan de 8 semanas se quema en 8 sesiones y el módulo vuelve a 0,
en silencio.

Consecuencia: si el free fuera de 1 día, tendría que ser también de 1 semana. Con
el free de 3 días (sección 4) el problema no aparece, pero la restricción queda
documentada por si alguien vuelve a proponer 1 día.

### 3.3 Un tope bajo de días apaga el catálogo — y esto pega también con 2

Las 7 plantillas del sistema tienen **3, 3, 4, 5, 4, 3 y 3 días**
(`docs/video-catalog-audit/improved-templates.json`, sembradas por
[scripts/seed_templates.js:25](../scripts/seed_templates.js)):

| id | nombre | días |
|---|---|---|
| `ppl-beginner` | Push Pull Legs — Principiante | 3 |
| `full-body-3day` | Full Body Principiante | 3 |
| `upper-lower-intermediate` | Upper/Lower — Intermedio | 4 |
| `bro-split-intermediate` | Bro Split — Intermedio | 5 |
| `powerlifting-base` | Powerlifting Base | 4 |
| `calistenia-beginner` | Calistenia Principiante | 3 |
| `hipertrofia-intermedio` | Hipertrofia — Intermedio | 3 |

Ninguna tiene 1 ni 2 días. StrongLifts 5×5 y Starting Strength (programas A/B de
2 días) **no están en el catálogo**; si se agregaran, serían las únicas que
entraban en el free de 2 días que esta sección analizaba.

Y para seguir una plantilla hay que copiarla: `todaysRoutineProvider` resuelve
la rutina activa **solo** contra `assignedRoutinesProvider` y
`userCreatedRoutinesProvider`
([todays_routine_provider.dart:76-92](../lib/features/home/application/todays_routine_provider.dart));
una plantilla `source == 'system'` no es candidata. El único camino es "Usar
como base" (`SelfCustomizing`,
[routine_editor_mode.dart](../lib/features/workout/presentation/routine_editor_mode.dart);
ruta `/workout/customize-routine/:routineId` en
[router.dart](../lib/app/router.dart)), que termina en `createUserOwned` con
`source: 'user-created'` y **los días de la plantilla**.

**Esto es lo que el brief no había cerrado:** con un free de 2 días y el
enforcement de la sección 6 (`days.size() <= 2` en el create de `user-created`),
copiar **cualquier** plantilla del catálogo (mínimo 3 días) rebota contra el
paywall. El catálogo entero queda detrás del pago para el alumno suelto. Firestore
no puede distinguir "copia de plantilla" de "armada a mano": el documento es
idéntico. La sección 4.1 resuelve el eje de SEGUIR; la 3.4, el de la forma.

### 3.4 El tope pasó de 2 a 3 días, y el número lo fija la tabla de arriba

**Decisión de producto tomada después de escribir 3.3, y sobre su propia
evidencia.** El análisis de arriba trata el choque catálogo-vs-tope como algo a
esquivar (dejar seguir sin copiar). Pero mirando la tabla de días una vez más:
`3, 3, 4, 5, 4, 3, 3`. **Las tres plantillas que el free puede seguir gratis
tienen 3 días.** O sea que la app le mostraba al alumno free tres programas
como "esto es lo que deberías hacer" y después no lo dejaba armarse uno igual.

Eso no era un tope: era una incoherencia, y era la fuente del
`permission-denied` al guardar. Un full body 3x/semana es EL programa de
principiante estándar; dejarlo afuera del free no vendía periodización, vendía
frustración.

**Qué cambia y qué no:**

- El tope de días pasa a **3** (`kFreeMaxRoutineDays`, y `freeMaxRoutineDays()`
  en `firestore.rules` — el número vive duplicado y los dos van juntos).
- El tope de **semanas NO cambia**. Sigue en 1, y pasa a ser la palanca de
  conversión principal de la rutina propia.
- El gate de **personalizar** una plantilla del catálogo **sigue**. Es la fila
  propia de la tabla de §4 y es política, no forma: antes el gate tenía además
  una razón aritmética (copiar una de 3 días rebotaba sí o sí contra el tope de
  2), y esa razón desapareció. Que quede escrito, porque el día que el producto
  quiera abrir personalizar no hay ninguna deuda de forma escondida atrás.

**Efecto secundario buscado, sobre la población que ya tiene rutinas armadas.**
`firestore.rules` mide el documento RESULTANTE, así que con el tope en 3 una
rutina de 4 días que quedó de antes **tiene salida**: sacarle un día la deja en
3 y guarda bien. Con el tope en 2 no había ninguna —bajar de 4 a 3 seguía
rebotando— y lo único que le quedaba al alumno era archivarla. Por eso el
mensaje de límite de ese caso puede pedir una acción concreta en vez de sólo
nombrar una restricción.

No es una población chica: hoy `kAthletePaywallEnabled` está en `false` y la CF
escribe `athletePaywallEnforced: false`, así que **todas** las rutinas que
existan el día del encendido se armaron sin tope. A eso se suman los dos modos
de perder el derecho con la rutina ya guardada (se termina el vínculo con el PF,
se vence la suscripción).

---

## 4. Qué se cobra

|  | Free | Pago |
|---|---|---|
| Días por rutina propia | **3** | hasta 7 (`_kMaxDays`) |
| Semanas por rutina propia | **1** | hasta 16 (`_kMaxWeeks`) + periodización (`weeklySets`, `activeWeeks`) |
| Seguir el catálogo — nivel principiante (3 plantillas) | **sí** | sí |
| Seguir el catálogo — nivel intermedio/avanzado (4 plantillas) | no — ver 4.1.1 | sí |
| Editar / personalizar una plantilla del catálogo | no | sí |
| Gráficos históricos | 3 meses | all-time |

**Tres días, y lo fija el propio catálogo** (ver 3.4). Un full body 3x/semana es
el programa de principiante estándar y es la forma de las tres plantillas que el
free sigue gratis. Queda debajo de Hevy (4 rutinas gratis) y Strong (3), pero es
defendible; uno no lo es (3.2).

La palanca de conversión de esta tabla es la fila de SEMANAS, no la de días:
periodizar es lo que separa un programa de principiante de uno intermedio.

### 4.1 El catálogo tiene que poder correrse sin copiar

Para que el free no apague el catálogo (3.3), **seguir una plantilla del sistema
tal cual tiene que ser gratis y no consumir cupo**. Eso requiere un cambio que
hoy no existe: que `todaysRoutineProvider` pueda resolver una rutina activa
`source == 'system'`.

Costo estimado (sin implementar):

- `resolveActiveRoutineId` recibe hoy `assignedIds` y `selfCreatedIds`
  ([todays_routine_provider.dart:88-92](../lib/features/home/application/todays_routine_provider.dart));
  necesita una tercera lista o aceptar cualquier id legible. Ojo: esa función
  la reimplementa el cliente watchOS en Swift, y `conformance/routine_selection.json`
  es el contrato entre ambos (comentario en :83-87). Tocarla es tocar dos
  plataformas y el fixture.
- `SessionNotifier._buildFresh` y `derivePlanProgress` asumen que la rutina se
  puede leer por id; las plantillas del sistema ya son `visibility: 'public'`,
  así que la regla de lectura no cambia.
- El progreso del plan (`lastFinished` por rutina) hoy se calcula sobre
  sesiones que apuntan a un `routineId`; con una plantilla compartida, dos
  alumnos apuntan al mismo id. Hay que verificar que el progreso sea por
  `(uid, routineId)` y no por `routineId` solo.

La alternativa — subir el free a 5 días para que entre toda plantilla — vacía el
paywall: 5 días es más que Hevy y Strong juntos.

### 4.1.1 El catálogo también se parte: principiante gratis, intermedio+ paga

Con 4.1 construido, la restricción de días de la sección 4 deja de aplicarle
al catálogo — seguir sin copiar nunca pasa por `user-created`, así que la
regla de `days.size()` (6.2) no lo ve. Eso deja una pregunta sin responder: si
CUALQUIER plantilla se sigue gratis y sin límite, ¿qué le queda al plan pago
además de "arma la tuya"?

Decidido en esta sesión (2026-09-03): el catálogo también se parte, por
**nivel**, no por días. El campo `level` de cada plantilla, verificado contra
`docs/video-catalog-audit/improved-templates.json` — la primera vuelta de esta
conversación asumió "Powerlifting Base" intermedio por el nombre; el campo
real dice `advanced`:

| Libre | id | `level` | Días |
|---|---|---|---|
| sí | `ppl-beginner` | beginner | 3 |
| sí | `full-body-3day` | beginner | 3 |
| sí | `calistenia-beginner` | beginner | 3 |
| no | `upper-lower-intermediate` | intermediate | 4 |
| no | `bro-split-intermediate` | intermediate | 5 |
| no | `hipertrofia-intermedio` | intermediate | 3 |
| no | `powerlifting-base` | **advanced** | 4 |

Encuadre: "empezá gratis, progresá con la app paga". Pega más fuerte que el
tope de días de la sección 4, porque no depende de que el alumno quiera
diseñar algo propio — todo el que progresa sale de principiante tarde o
temprano, use catálogo o rutina propia.

> **Estado del enforcement de este eje (2026-09-10).** La UI del teléfono la
> cerró el #1066; la regla server-side sobre `sessions` y el gate del reloj
> **Wear OS**, el #1087. Falta el reloj de **Apple**, y es lo único que bloquea
> encender el paywall: [paywall-watchos-plan.md](./paywall-watchos-plan.md).

**Flag explícito, no `level` reutilizado — decisión de esta sesión.** Gatear
directo por `level` sería gratis en código (el campo ya existe), pero ata el
PRECIO a la DIFICULTAD, y son decisiones distintas: el día de mañana puede
convenir dejar "Powerlifting Base" gratis como gancho de adquisición aunque
sea `advanced`, o cobrar un principiante particularmente bien producido. Un
campo nuevo — `isPremium: bool`, default `false` — en el seed
(`docs/video-catalog-audit/improved-templates.json` +
`scripts/seed_templates.js`) desacopla las dos cosas. Costo bajo: el seed ya
es un proceso manual e infrecuente, un campo más no cambia eso.

**Dónde va el enforcement — distinto del de 6.2.** Acá no hay escritura en
`routines`: seguir sin copiar solo pisa `users/{uid}.activeRoutineId`. La
regla que hace falta es sobre ESE campo, no sobre `routines` — un `get()` a la
plantilla resuelta (mismo patrón de `firestore.rules:623`, que ya lee
`users/{uid}.role`) para leer su `isPremium`, exigiendo el mismo campo de
entitlement que 6.3 propone para `user-created`.

**La vidriera también tiene que saberlo.** El grid de Plantillas necesita un
candado o badge visible en las 4 no-gratis ANTES de que el alumno toque
"Seguir" — bloquear en silencio al tocar se siente como que la app miente.

**Telemetría que falta si esto se construye.** El día que "seguir sin copiar"
exista, seguir una plantilla deja de generar `routine_created` (no hay
create). Hace falta un evento nuevo — algo como `catalog_template_followed`
con `template_id` e `is_premium` — para no perder visibilidad de este camino.
Y uno más, de mayor señal para este eje específico: algo como
`premium_template_blocked`, que mide directo "cuánta gente quiso una
no-gratis y no pudo" — el número que de verdad justifica construir esto.
Ninguno de los dos está instrumentado; van cuando exista el gate que miden, no
antes.

### 4.2 Gráficos: el eje que convierte, pero todavía no existe la superficie

Los gráficos a 3 meses son copia exacta de Hevy (free: 4 rutinas, **3 meses de
historial**, 7 ejercicios custom — consenso de tres reseñas 2026, ver sección
8; Hevy no publica el pricing en su web) y son el eje que de verdad convierte
en esta categoría: cobran después de que generaste datos que querés ver, no
antes de dejarte crear.

Pero hoy `ChartPeriod` tiene tres valores: `last30d`, `thisWeek`, `month`
([chart_period.dart:37-40](../lib/features/insights/domain/chart_period.dart)).
**No hay ninguna vista de más de un mes.** Poner el paywall en "3 meses vs
all-time" es poner una puerta en una pared que no existe. Primero hay que
construir períodos largos (3 meses, 1 año, todo) en la progresión por ejercicio
([exercise_progression_screen.dart](../lib/features/insights/presentation/exercise_progression_screen.dart))
y en mediciones; después, gatear.

La buena noticia: el corte es barato. `SessionRepository.listFinishedInWindow`
ya filtra `finishedAt >= from` **en la query**
([session_repository.dart:318-335](../lib/features/workout/data/session_repository.dart)),
así que un piso de 3 meses para free es un `from` distinto, no un filtro en
cliente sobre datos ya bajados. El límite tampoco toca al PF: los gráficos del
Coach Hub leen sesiones del alumno con sus propias queries, y el entitlement del
alumno no debe entrar ahí.

---

## 5. Al cancelar: se congela la edición, no se borra nada

- Una rutina de 5 días **se sigue entrenando entera**. `FreshSession` y
  `nextPlanPosition` no miran entitlement.
- Lo que no se puede: **editar** esa rutina ni **crear otra** que exceda el free.
- Al reactivar, todo vuelve **sin migración**: no hay flag en el documento, no
  hay `status` nuevo, no hay downgrade de datos. El entitlement es una propiedad
  del usuario, no de la rutina.

Esto es consistente con `UPDATE path 1` de las reglas (`affectedKeys ==
['status']`, archivar/restaurar,
[firestore.rules:421-427](../firestore.rules)): archivar sigue permitido para
cualquiera, porque no es programar.

---

## 6. Enforcement (esbozo — no implementar)

### 6.1 Contar rutinas es inviable; contar días no

El cap actual de 10 rutinas es **puramente client-side**:
`userRoutines.length >= 10` en el `case SelfCreating(existingRoutineId: null) ||
SelfCustomizing()` de
[routine_editor_screen.dart](../lib/features/workout/presentation/routine_editor_screen.dart).
No hay contraparte en `firestore.rules`. Y se evade archivando:
`listUserCreated` filtra `status == 'active'`
([routine_repository.dart:136](../lib/features/workout/data/routine_repository.dart))
y `archive` solo cambia `status` a `'archived'`
([routine_repository.dart:333-335](../lib/features/workout/data/routine_repository.dart)).
Las reglas de Firestore no tienen agregación, así que esto no se puede cerrar
del lado del servidor.

Contar días **sí**: `days` es una lista en el documento que se está escribiendo
(`List<RoutineDay> days`, [routine.dart:33](../lib/features/workout/domain/routine.dart)),
y `.size()` sobre listas ya se usa en estas reglas
(`workoutSnapshot.exercises.size() <= 30`, [firestore.rules:883](../firestore.rules)).

### 6.2 Dónde va

- **CREATE** de `source == 'user-created'`
  ([firestore.rules:399-415](../firestore.rules)): agregar
  `request.resource.data.days.size() <= N && request.resource.data.numWeeks <= M`
  cuando el usuario no está entitled.
- **UPDATE path 2** (contenido, [firestore.rules:452-477](../firestore.rules)):
  la misma condición. Sin esto, se crea con 3 días y se edita a 7. El `hasOnly`
  de `affectedKeys` ya incluye `days` y `numWeeks`, así que la condición se
  suma sin romper edits parciales.
- **Nunca** en `allow read`.
- **No aplica** a `trainer-assigned` ni `trainer-template` (CREATE branch 1 y
  UPDATE path 3): el PF ya paga.

### 6.3 Cómo sabe la regla si el alumno está entitled

Las reglas ya leen documentos ajenos con `get()` **dentro del propio match de
`routines`**, así que el patrón no hay que inventarlo:

- `get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'trainer'`
  ([firestore.rules:623](../firestore.rules)).
- `get(/databases/$(database)/documents/userPublicProfiles/$(resource.data.assignedBy)).data.sharedTemplatesWithAthletes == true`
  ([firestore.rules:355](../firestore.rules)) — ya se lee un doc de OTRO usuario
  para decidir sobre una rutina.

El paywall del PF usa el mismo patrón con `users/{trainerId}.blockedAthleteIds`
(documentado en `logPaywallWriteDenied`,
[analytics_service.dart](../lib/core/analytics/analytics_service.dart)).
No hay custom claims en `functions/src` fuera de `subscriptions/` (no
verificado adentro — esa carpeta está fuera de alcance de esta spec).

Ojo con el costo: cada `get()` en una regla es una lectura facturada. Sumar dos
(entitlement + vínculo) a cada escritura de rutina es barato porque las rutinas
se escriben poco, pero **no** sirve el mismo enfoque si algún día se quiere
gatear una lectura de alto volumen.

Propuesta: un campo en `users/{uid}` escrito **solo por Cloud Functions** (el
webhook de Mercado Pago) que la regla lea con `get()`. La condición de free
aplica cuando ese campo no dice entitled **y** el alumno no tiene vínculo activo.
El segundo chequeo es un `exists()`/`get()` más por escritura de rutina; es
barato en volumen (las rutinas se escriben poco) y evita cobrarle a un alumno
vinculado.

Para el `get()` del vínculo hace falta un doc con id determinístico
(`links/{athleteId}` o similar). Verificar la colección real de
`TrainerLinkRepository` antes de diseñar la regla — no la leí en esta sesión.

---

## 7. Cobro: por IAP, no por web

> **Esta sección se dio vuelta el 2026-09-10.** Decía «por web con Mercado Pago,
> no por IAP» y la decisión se revirtió. Se reescribió entera en vez de
> parcharse porque cuatro archivos de `lib/` la citan, y una spec que dice lo
> contrario de lo construido es peor que ninguna: el que la lee trabaja con una
> constitución vieja y cree que está al día.

**El alumno paga por in-app purchase (App Store + Google Play), vía RevenueCat.**
El entrenador sigue cobrando por Mercado Pago desde la web, y eso no cambió.

### 7.1 Por qué se dio vuelta: la exención no aplicaba

La versión anterior apoyaba todo en la Guideline 3.1.3(f) de Apple. El texto
literal, verificado el 2026-09-10:

> «Free apps acting as a stand-alone companion to a **paid web based tool**
> (i.e. VoIP, Cloud Storage, Email Services, Web Hosting) do not need to use
> in-app purchase, provided there is no purchasing inside the app, or calls to
> action for purchase outside of the app.»

La exención exige una *paid web based tool* de la cual la app sea companion.

**Para el ENTRENADOR eso existe de verdad**: el Coach Hub es una herramienta web
paga donde arma rutinas, gestiona alumnos y factura. La exención le aplica, y
por eso su cobro sigue como está.

**Para el ALUMNO no existe ninguna superficie web** — lo dice la sección 7.2 de
abajo, que era el argumento de por qué había que construirla y terminó siendo el
argumento de por qué no se podía usar la exención. Sin web no hay *paid web
based tool*, sin eso no hay exención, y cae 3.1.1: la compra pasa por la tienda.

No es una preferencia. Es la única puerta que quedaba abierta.

### 7.2 Hoy no existe superficie web para el alumno

*(Sección original, sin cambios — sigue siendo cierta, y es exactamente la razón
por la que la exención no aplica.)*

`coachHubRedirect` manda a `/not-allowed` a todo `role != trainer`
([coach_hub_router.dart:84-86](../lib/app/coach_hub_router.dart)). La única ruta
pública del hub es `/login` (`_coachHubPublicRoutes`, :36); no hay `/register`
ni `/forgot-password` porque el signup vive en mobile (:41-42). El entry point
web es [main_coach_hub.dart](../lib/main_coach_hub.dart), separado de
[main.dart](../lib/main.dart).

Del lado del alumno en mobile existe `lib/features/payments/` (`mi_cuota`), pero
es **read-only**: el alumno le paga la cuota al PF *offline* y la app solo
muestra lo que debe ([mi_cuota_provider.dart:36-37](../lib/features/payments/application/mi_cuota_provider.dart)).

### 7.3 Lo que COSTÓ la decisión, dicho de frente

La sección vieja tenía razón en los números, y conviene no perderlos: **IAP es
peor para el bolsillo del alumno.** Se aceptó igual porque la alternativa no
existía.

Verificado el 2026-09-10:

- La storefront de Argentina **cotiza en USD** en las dos tiendas. No hay precio
  en pesos: la API de Apple con `country=ar` devuelve `currency: USD`, y la
  tabla oficial de Google lista `Argentina | USD`.
- Al alumno le caen **IVA 21%** (RG 4240) y **percepción 30%** (RG 5617) encima
  del precio de lista, y **ni Apple ni Google los recaudan** — Argentina no está
  en sus listas de países donde retienen. El precio en USD que ve es la BASE; la
  sorpresa llega en el resumen de la tarjeta.
- La comisión de la tienda es 15% (Small Business Program) contra ~4–6% de
  Mercado Pago.

Por cada USD 1 de lista: el alumno paga ~ARS 2.318 y a TREINO le llegan
~ARS 1.282. **Se queda el 55% de lo que el alumno gasta.**

> ⚠️ **El «+51%» NO es una constante, y esto importa para la pantalla.** La
> RG 4240 art. 4 acota la percepción de IVA a pagos de hasta USD 10 para los
> prestadores del Apartado B, y en el listado vigente de ARCA la línea de
> `APPLE` tiene exactamente ese tope mientras la de `GOOGLE PLAY` no. O sea que
> el mismo porcentaje sería falso en el plan anual de iOS.
>
> No verificado: cuál de las dos entradas de Apple del listado (`APPLE`, con
> tope, o `ITUNES.COM`, sin tope) matchea un IAP de App Store. Se resuelve
> mirando un resumen real o preguntándole al contador.

Por eso el paywall **no muestra ningún monto en pesos**: el importe final lo
define el emisor de la tarjeta al liquidar, el porcentaje no es fijo, y publicar
un número que puede salir mal es la guideline 2.3.1(a) —*promoting a false
price*— cuya pena escrita es la baja de la app y la terminación de la cuenta.
Muestra el precio de la tienda y una advertencia cualitativa.

### 7.4 Qué se construyó

| Pieza | Dónde |
|---|---|
| Capacidad de comprar (tipo sellado) | `lib/features/paywall/application/athlete_checkout.dart` |
| El puerto, sin tipos de terceros | `lib/features/paywall/application/athlete_store.dart` |
| El adaptador — **único archivo de `lib/` que importa el SDK** | `lib/features/paywall/application/revenuecat_store.dart` |
| Pantalla de paywall | `lib/features/paywall/presentation/athlete_paywall_screen.dart` |
| Webhook que escribe `athleteSubscription` | `functions/src/subscriptions/rc/webhook.ts` |
| UUID por usuario (seguro para un futuro sin RevenueCat) | `functions/src/subscriptions/store-account-token.ts` |

### 7.5 La deuda que dejó la reversión

3.1.3(f) tiene **dos** condiciones, no una: no vender adentro **y** no tener
*calls to action* hacia afuera. La app móvil tiene tres carteles que dicen dónde
se paga —«Regularizá tu suscripción desde TREINO web»— y eso ya es un call to
action.

Están declarados en `test/features/paywall/anti_steering_movil_test.dart` con su
fecha límite: **antes de la primera submission de iOS que incluya la suscripción
del alumno**, porque ése es el momento en que un revisor humano abre esas
pantallas.


## 8. Precio

> ⚠️ **La banda de abajo quedó vieja el 2026-09-10.** Se calculó asumiendo cobro
> por web, o sea **sin comisión de tienda y en pesos**. Con IAP el precio se
> fija en USD —la storefront argentina no admite pesos— y le entra un 15% de
> comisión. Las referencias de §8.1 siguen sirviendo; la banda, no.

**Propuesto: USD 2,99/mes y USD 29,90/año.** Sin confirmar por el dueño.

| | Lista | Lo que ve el alumno en el resumen | Lo que le llega a TREINO |
|---|---|---|---|
| Mensual | USD 2,99 | ~ARS 6.931 | ~ARS 3.833 |
| Anual | USD 29,90 | ~ARS 69.308 (= ARS 5.776/mes) | ~ARS 38.332 |

El múltiplo 10x no es arbitrario: es la convención de la casa, ya cobrada al
entrenador (`functions/src/subscriptions/tier-config.ts:56-58` — 12.000/120.000,
22.000/220.000, 39.000/390.000, con un test que lo fija).

**Por qué ese número y no más:** el mercado de apps de entrenamiento es
bimodal —seis apps entre USD 1,99 y 4,99, seis entre 11,99 y 15,99, y **cero en
el medio**— y la línea que separa los racimos no es la calidad: es si la app
**genera el plan**. TREINO le da al alumno el contenedor para programar; no le
programa. El piso lo fija Hevy, que cobra lo mismo con un free más ancho.

**El punto débil es el múltiplo del anual, no el nivel del mensual.** Setgraph,
que sí localizó para Argentina, cobra el anual a USD 16,49: el 29,90 está 81%
arriba, mientras que el mensual está a 11% del suyo. Si el anual no convierte,
la palanca es bajar de 10x a 8x → USD 23,99, que es exactamente el anual de Hevy.

<details>
<summary>La banda original, para referencia histórica</summary>

Banda **ARS 2.500–3.500/mes**, o **ARS 25.000 anual** (≈ 8,3 meses de 3.000: un
30% de descuento).

</details>

### 8.1 Referencias argentinas — verificadas el 2026-09-03

| Referencia | Valor | Fuente | Fuerza |
|---|---|---|---|
| SMVM desde el 1/9/2026 | **ARS 383.800** (Res. 4/2026, Boletín Oficial). Sube a 391.200 en octubre y llega a 437.000 en abril de 2027. | [Infobae, 2/9/2026](https://www.infobae.com/economia/2026/09/02/de-cuanto-es-el-salario-minimo-vital-y-movil-en-septiembre-2026/), cita literal de la resolución | fuerte |
| Spotify Premium Individual | **ARS 4.499/mes "+ impuestos aplicables"** (Duo 5.999, Familiar 7.599, Estudiantes 2.299) | [spotify.com/ar/premium](https://www.spotify.com/ar/premium/) | fuerte (oficial) |
| Plan de entrenamiento online de un PF argentino | **ARS 20.000–40.000/mes**, sin distinguir con/sin seguimiento. Contexto: clase presencial 10.000–20.000; mensual presencial (12 clases) 90.000–155.000. | [ElLaburante, abril 2026](https://ellaburante.com/blog/personal-trainer-precios-2026) | débil (agregador, sin metodología) |
| PF presencial premium (AMBA) | ARS 125.000–455.000/mes según frecuencia y tier. Solo presencial. | [ARCoach, tarifas](https://arcoachweb.com/tarifas/) | fuerte (tarifa publicada), pero no es online |
| Hevy Pro | USD 2,99/mes · 23,99/año · 74,99 lifetime. Free: 4 rutinas, 3 meses de historial, 7 ejercicios custom. | Consenso de [SensAI](https://www.sensai.fit/blog/hevy-review-2026), [RepReturn](https://repreturn.com/hevy-pro-vs-free/), [PulseSignal](https://getpulsesignal.com/pricing/hevy); `hevyapp.com` no publica pricing | débil (sin fuente oficial) |

Correcciones al brief: el SMVM de 376.600 era el valor de agosto; el vigente es
383.800. El Spotify de 4.499 se confirmó contra la página oficial. YouTube
Premium (~5.200 final) y Strava (USD 4,99 regional) **no se re-verificaron** y
quedan como referencia del brief.

A ARS 3.000/mes el plan es el **0,8% del SMVM**, dos tercios de un Spotify antes
de impuestos, y **entre el 7% y el 15% de lo que cobra un PF argentino por un
plan online**. Ese último número es el que faltaba y es el que importa: el
paywall no compite con el PF, está un orden de magnitud abajo. Y cierra el
argumento de la sección 2 desde el otro lado — el alumno vinculado no puede
pagar nada porque su PF ya le está cobrando 20–40 mil por mes.

### 8.2 Anual vs mensual: hipótesis, no dato

El brief citaba "~50% de retención a un año para anuales contra ~22% de
mensuales". **No hay fuente primaria.** El
[State of Subscription Apps 2026 de RevenueCat](https://www.revenuecat.com/state-of-subscription-apps)
define retención como *"the share of paid subscriptions that remain active
after a given time period"*, pero en la página principal no publica retención
de mensuales a 12 meses ni retención de anuales al primer renewal, y el
sub-reporte de Health & Fitness no existe en la URL del patrón de los demás
(404). Lo único que apareció — vía resumen del buscador, sin verificar en la
página — es que en Health & Fitness los anuales concentran ~60% del ingreso.

Eso no valida el número del brief. El argumento "el anual funciona como
cobertura de inflación en Argentina" es razonable y probablemente cierto, pero
hoy es una **hipótesis a testear con el propio producto**, no un benchmark. La
spec lo trata así.

---

## 9. Telemetría: qué tiene que decir para construir esto

Los tres eventos ya instrumentados, con solo contadores y un enum:

| Evento | Parámetros | Pregunta que responde |
|---|---|---|
| `routine_created` | `source`, `days_count`, `weeks_count` | ¿Qué forma tienen las rutinas que la gente arma de verdad? |
| `routine_day_added` | `source`, `days_count` (el total nuevo) | ¿Cuánta gente pasa de 2 a 3 días? Ahí mordería el paywall. |
| `routine_week_added` | `source`, `weeks_count` (el total nuevo) | Lo mismo para semanas. |

`source ∈ {self, self_from_template, trainer_assigned, trainer_template}`. El
segmento es `self` + `self_from_template`. El PF se cuenta y se filtra; no se
omite, porque omitirlo dejaría el desglose por `source` mintiendo por
subreporte.

Dos límites de lectura que hay que tener presentes:

- La app **nunca llama a `setUserId`** (documentado en `logPaywallWriteDenied`),
  así que `user_pseudo_id` identifica la **instalación**, no la persona. Los
  conteos de "usuarios" son de dispositivos.
- `routine_day_added` se emite **al agregar**, aunque la rutina nunca se guarde.
  Cruzarlo con `routine_created` dice cuánta gente arma 3 días y se arrepiente
  antes de guardar — eso es fricción propia del editor, no del paywall.

### Criterios de decisión (propuesta)

Construir el paywall si, sobre `source IN (self, self_from_template)` y con al
menos **200 instalaciones distintas** que hayan emitido `routine_created`:

1. **≥ 25%** de las `routine_created` tienen `days_count >= 4`. Debajo de eso,
   el límite de 3 días no lo toca casi nadie y el paywall no cobra.
2. **≥ 40%** de las instalaciones con `routine_day_added` llegan a
   `days_count == 4`. Es la tasa de "choque" contra el tope.

   (Los dos umbrales decían 3 cuando el tope era 2. Al subirlo, el corte que
   mide "choca contra el paywall" se corre con él — si no, la telemetría
   contaría como choque a todo el que arma un full body, que ahora es gratis, y
   el criterio diría que construir el paywall se justifica cuando no.)
3. `self_from_template` es **≥ 30%** de las `routine_created`. Si es más, el
   catálogo es el producto y la sección 4.1 pasa de "necesaria" a "urgente".

Si (1) y (2) dan bajo, la conclusión honesta es que el alumno suelto no programa
lo suficiente para que un tope de días sea un producto — y el eje a mirar es
gráficos (4.2), no días.

---

## 10. Preguntas abiertas

1. **¿El alumno suelto es un segmento o es el embudo del PF?** Según el brief,
   un alumno sin vínculo aterriza en el discovery de entrenadores y puede
   escribirle a un PF por chat sin vincularse (`trainer_contact_cta_stub.dart`
   emite `link_requested`). Un paywall ahí cobra peaje en el canal de
   adquisición del cliente que sí paga. No verifiqué el flujo de discovery en
   esta sesión; hay que trazarlo antes de decidir. Si el alumno suelto convierte
   a alumno vinculado a una tasa razonable, el paywall puede ser
   contraproducente aun con la telemetría a favor.
2. **Correr una plantilla del catálogo, ¿consume cupo?** Verificado: **hoy sí**,
   dos veces. "Usar como base" pasa por el mismo `case` que "crear de cero" y
   cuenta contra el cap de 10; y la copia hereda los días de la plantilla, así
   que también chocaría contra un tope de días. La sección 4.1 propone que
   seguir sin copiar no consuma nada. Sin eso, el free vacía el catálogo, no el
   límite. Resuelto en el diseño (4.1.1): "sin copiar" es gratis solo para las
   3 plantillas `beginner`; las 4 restantes (`intermediate`/`advanced`) quedan
   pagas, gateadas por un flag nuevo, no por `level` directo.
3. **Qué cobra un PF argentino por un plan online.** Cubierto con fuente
   débil: ARS 20.000–40.000/mes (sección 8.1). Alcanza para descartar que
   ARS 3.000 compita con el PF, pero no para afinar la banda. Vale una encuesta
   corta a los PF que ya están en TREINO — son la fuente primaria que nadie
   más tiene.
4. **¿Cómo se lee el vínculo activo desde las reglas?** Depende del esquema de
   `TrainerLinkRepository`, que no leí. Si el id del doc de vínculo no es
   determinístico por alumno, hace falta desnormalizar (`users/{uid}.trainerId`
   o similar) antes de poder escribir la regla de la sección 6.3.

---

## 11. Qué se verificó y qué no

Todo lo que cita archivo y línea se leyó del repo en `main` (`3edca9ce`)
durante esta sesión. Para lo externo, el barrido con sub-agentes murió dos
veces con `529 Overloaded`; lo que sigue se verificó a mano, fuente por fuente,
el 2026-09-03.

**Confirmado contra fuente primaria u oficial**

- Spotify Individual ARS 4.499 + impuestos (spotify.com/ar).
- SMVM ARS 383.800 desde el 1/9/2026, Res. 4/2026 (Infobae citando el BO).
  Corrige el 376.600 del brief.
- El campo `level` de las 7 plantillas del sistema, leído directo del JSON del
  seed (4.1.1). Corrige una afirmación dicha en el chat de esta misma sesión:
  "Powerlifting Base" no es `intermediate`, es `advanced`.

**Cubierto con fuente débil (agregadores o reseñas, sin metodología)**

- Plan online de PF argentino: ARS 20.000–40.000/mes (ElLaburante, abril 2026).
- Hevy: free 4 rutinas / 3 meses / 7 custom; Pro USD 2,99 / 23,99 / 74,99
  (tres reseñas coincidentes; el sitio oficial no publica pricing).

**Sin fuente primaria — tratar como hipótesis**

- "50% de retención anual vs 22% mensual". RevenueCat 2026 no lo publica en la
  página principal; el sub-reporte de Health & Fitness dio 404.

**No re-verificado en esta sesión (queda como lo trajo el brief)**

- Las declaraciones "gratis para los clientes del coach" de TrueCoach,
  Trainerize, Everfit, My PT Hub, Kahunas y Hevy Coach.
- YouTube Premium ~ARS 5.200 final; Strava USD 4,99 con pricing regional.
- Guideline 3.1.3(f) de Apple; países del External Purchase Entitlement y del
  User Choice Billing; alcance solo-EEUU del remedio *Epic*; RG 5617 y su
  alícuota del 30%. Son afirmaciones regulatorias con fecha — antes de
  construir, releerlas contra developer.apple.com, play.google.com y ARCA.
- El costo por alumno-mes del PF (ARS 1.466–1.714): sale de `subscriptions/`,
  que está fuera del alcance de esta spec.

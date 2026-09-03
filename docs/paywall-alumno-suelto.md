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
el free de 2 días (sección 4) el problema no aparece, pero la restricción queda
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
entran en un free de 2 días.

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
idéntico. La sección 4.1 resuelve esto.

---

## 4. Qué se cobra

|  | Free | Pago |
|---|---|---|
| Días por rutina propia | **2** | hasta 7 (`_kMaxDays`) |
| Semanas por rutina propia | **1** | hasta 16 (`_kMaxWeeks`) + periodización (`weeklySets`, `activeWeeks`) |
| Seguir el catálogo del sistema tal cual | **sí, entero** | sí |
| Editar / personalizar una plantilla del catálogo | no | sí |
| Gráficos históricos | 3 meses | all-time |

Dos días es el mínimo que expresa un programa de principiante real (A/B). Queda
debajo de Hevy (4 rutinas gratis) y Strong (3), pero es defendible; uno no lo es.

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
  la misma condición. Sin esto, se crea con 2 días y se edita a 7. El `hasOnly`
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

## 7. Cobro: por web con Mercado Pago, no por IAP

Argentina no está en la lista de países del External Purchase Link Entitlement
de Apple ni en el User Choice Billing de Google, y el régimen post-*Epic* es
solo storefront de EEUU. Las tiendas cobran en USD y encima cae la percepción de
Ganancias del 30% (RG 5617). Resultado: para el mismo neto, IAP haría que el
alumno pague ~ARS 7.000 contra ARS 4.000 por web (brief, 2026-09-03).

La vía limpia es la Guideline 3.1.3(f) — *Free Stand-alone App*: la app móvil no
vende nada ni linkea al checkout; el alumno paga en la web y el entitlement
llega por Firestore. Es **el mismo patrón que ya usa el entrenador**.

### 7.1 Hoy no existe superficie web para el alumno

`coachHubRedirect` manda a `/not-allowed` a todo `role != trainer`
([coach_hub_router.dart:84-86](../lib/app/coach_hub_router.dart)). La única ruta
pública del hub es `/login` (`_coachHubPublicRoutes`, :36); no hay `/register`
ni `/forgot-password` porque el signup vive en mobile (:41-42). El entry point
web es [main_coach_hub.dart](../lib/main_coach_hub.dart), separado de
[main.dart](../lib/main.dart).

Del lado del alumno en mobile existe `lib/features/payments/` (`mi_cuota`), pero
es **read-only**: el alumno le paga la cuota al PF *offline* y la app solo
muestra lo que debe ([mi_cuota_provider.dart:36-37](../lib/features/payments/application/mi_cuota_provider.dart)).
No hay checkout del alumno en ningún lado.

### 7.2 Qué habría que construir (estimación en piezas, no en horas)

| Pieza | ¿Existe algo reusable? | Riesgo |
|---|---|---|
| Entry point web del alumno (o un modo del hub que no redirija por rol) | `main_coach_hub.dart` como molde; el redirect hay que bifurcarlo, no relajarlo | medio — el hub asume trainer en 23 secciones |
| Login web del alumno | `coach_hub_login_screen.dart` (solo email/password; el hub no inicializa Google Sign-In, :47-49). El alumno mobile sí usa Google/Apple → hay que agregar OAuth web o aceptar solo email | alto — es el primer contacto |
| Pantalla de planes + botón de pago | `sections/facturacion_planes/` del PF — **fuera de alcance de esta spec**, otra sesión la está cableando; reusar cuando esté | bajo si se espera |
| Retorno del checkout + estado "pendiente" | idem | bajo si se espera |
| Webhook MP → campo de entitlement en `users/{uid}` | `functions/src/subscriptions/**` del PF — **fuera de alcance**; el del alumno sería un hermano, no una extensión | medio — dos productos en un webhook |
| Lectura del entitlement en mobile (para mostrar el paywall antes de que rebote la regla) | patrón `blockedAthleteIds` del PF | bajo |
| Deploy target y dominio | `vercel.json` / `firebase.json` — no verifiqué cuál sirve el hub hoy | bajo |

El orden importa: **nada de esto arranca hasta que el checkout del PF esté
mergeado**. Construir dos checkouts de Mercado Pago en paralelo es duplicar el
código más delicado del repo.

---

## 8. Precio

Banda **ARS 2.500–3.500/mes**, o **ARS 25.000 anual** (≈ 8,3 meses de 3.000: un
30% de descuento).

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

1. **≥ 25%** de las `routine_created` tienen `days_count >= 3`. Debajo de eso,
   el límite de 2 días no lo toca casi nadie y el paywall no cobra.
2. **≥ 40%** de las instalaciones con `routine_day_added` llegan a
   `days_count == 3`. Es la tasa de "choque" contra el tope.
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
   límite.
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

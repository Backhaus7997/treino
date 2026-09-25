# Límite de plantillas del plan Free del entrenador: plan de implementación

**25 de septiembre de 2026.** Escrito contra `origin/main` de `treino` en
`656121cd`. Los números de línea son de ese commit.

**Estado: plan revisado contra el código, sin código todavía.** Se apoya en lo
que ya dejó en `main` el límite de ejercicios propios (#1240, #1241, #1243):
`planLimits`, `effectiveTier`, el mail del tope, el aviso de estado en el móvil y
el test de paridad. Acá casi todo es **sumar una clave**, no construir de nuevo.

**Revisado el 25/09/2026** (Claude, con una revisión adversarial de Codex sobre
el enforcement). Las correcciones ya están aplicadas en el texto de abajo; la
§7 las resume con su evidencia. Si vas a implementar, leé la §7 primero.

---

## 0. En una página

| Plan | Alumnos | Ejercicios propios | **Plantillas** |
|---|---|---|---|
| Free | 2 | 20 | **3** |
| Plan 1 | 7 | 60 | sin límite |
| Plan 2 | 15 | 120 | sin límite |
| Plan 3 | sin límite | sin límite | sin límite |

**Qué se limita:** las plantillas del PF, es decir los documentos de `routines`
con `source == 'trainer-template'` y `assignedBy == uid` que **no están
archivados**. Publicadas o privadas, cuentan igual.

**Qué NO se limita:**

- **Asignar una plantilla a un alumno.** Crea un `trainer-assigned`, que no es
  plantilla. Un PF pasado de tope sigue asignando lo que ya tiene.
- **Los planes asignados**, sean creados desde cero o importados desde Excel
  (`coach_hub_plan_preview_screen.dart:207` llama a `createAssigned`, no a
  `createTemplate`). Están acotados por el tope de alumnos.
- **El catálogo del sistema y las plantillas publicadas por otros.**
- **El alumno.** El tope corta por rol.

**Cómo:** igual que los ejercicios propios. La CF escribe `planLimits.templates`
y un contador `templateUsage.count`, la regla los lee en el create y en la
restauración, y el cliente lee los mismos campos. **Un interruptor propio**,
`TRAINER_TEMPLATE_LIMITS_ENABLED`, para poder encenderlo independiente de los
ejercicios.

**Condición de encendido, la misma que los ejercicios:** tiene que estar
prendido **antes de dar de alta al primer entrenador real**. Después, es un
cambio de límites y aplica el aviso previo del §12 del contrato.

**Cinco PRs y un encendido**, más el de legales. Dentro de ~400 líneas por
review cada uno. El PR 6 (el link de pago del mail) **arregla además un bug que
ya está en `main`**, y conviene hacerlo primero: ver §3, PR 6.

---

## 1. Decisiones

| # | Decisión | Por qué |
|---|---|---|
| P1 | **3 y no 4** | Es el vocabulario de la casa para el free: el alumno free tiene 3 rutinas propias y 3 videos (`kFreeMaxOwnRoutines`, `kFreeMaxCustomExerciseVideos`). Tres alcanza para probar el flujo entero (crear, asignar, publicar) y para la estructura típica de principiante, intermedio y avanzado. Cambiarlo a 4 es un número en dos archivos |
| P2 | **Sólo el Free. Los pagos, sin límite** | La plantilla es la promesa central del producto para el PF («Armás la plantilla una vez y la asignás», landing /gym). Topearla en un plan pago pega en lo que se vende. Y no cuesta nada: son documentos chicos |
| P3 | **Cuentan las publicadas** | Si no contaran, publicar sería la forma de esquivar el tope, y el catálogo de la comunidad se llenaría de plantillas publicadas para eso |
| P4 | **Archivar libera el lugar; restaurar pide lugar** | Es la salida natural para el PF («archivá una vieja»). Sin gate en la restauración, archivar y restaurar sería un bypass |
| P5 | **Bajar de plan congela la creación y no toca nada más** | Conserva todas, las edita, las asigna, las publica y las archiva. Mismo criterio que los ejercicios (E3) |
| P6 | **Sólo el rol `trainer`** | El CREATE branch 1 de `routines` no chequea rol: un alumno puede tener un `trainer-template` forjado (comentario del UPDATE path 5). La cuota corta por rol, igual que la de ejercicios |
| P7 | **Una ráfaga fabricada puede pasarse, y no se borra nada** | Mismo criterio que E7 de los ejercicios |
| P8 | **El link de pago del mail abre el Coach Hub en el navegador, con el plan elegido. No la landing** | Ver PR 6. El PF ya tiene dónde pagar en la web, y ahí es donde el contrato dice que contrata |

### Mi opinión, en corto

Tiene sentido como **segundo empujón**, no como el principal. Con 2 alumnos, un
PF Free casi no reutiliza plantillas, así que el tope rara vez muerde. Muerde en
un momento concreto: **el PF que arma su biblioteca antes de traer alumnos**,
típicamente el que migra desde otra app. Ése es justo el que ya invirtió en la
herramienta, y casi siempre lo hace desde el Coach Hub web, donde sí se le puede
ofrecer subir de plan. El tope de alumnos sigue siendo la palanca que convierte.

---

## 2. Modelo de datos

Todo en `users/{uid}`, al lado de lo que dejó el #1240.

| Campo | Tipo | Quién lo escribe | Significado |
|---|---|---|---|
| `planLimits.templates` | `number \| null` | **Sólo la CF** | Tope vigente. `null` o ausente = sin tope |
| `templateUsage.count` | `number` | **Sólo la CF** | Plantillas no archivadas del PF |
| `trainerLimitHitKind` | `string` | El cliente | Ya existe. Suma el valor `'templates'` |
| `trainerLimitHitAt` | `Timestamp` | El cliente | Ya existe |

**`planLimits` ya está pineado** en create y update de `users` (L349 y L479).
Como es un mapa, la clave nueva viaja protegida sin tocar ese pin: es exactamente
para lo que se diseñó como mapa. **`templateUsage` es un campo nuevo y sí hay que
pinearlo**, junto a `customExerciseUsage` (L355 y L482).

---

## 3. Los PRs

### PR 1: backend apagado (functions)

**`functions/src/subscriptions/tier-config.ts`:**

```ts
export const TIER_TEMPLATE_LIMITS: Record<SubscriptionTier, number | null> = {
  free: 3,
  plan1: null,
  plan2: null,
  plan3: null,
};
```

**`functions/src/subscriptions/trainer-plan-limits.ts`:**

- Sumar `export const TRAINER_TEMPLATE_LIMITS_ENABLED = false;`.
- `TrainerPlanLimits` pasa a `{customExercises: number | null; templates: number | null}`.
- `templateLimitFor(tier)`, calcado de `customExerciseLimitFor`.
- `resolvePlanLimits` resuelve **cada clave con su interruptor**. Apagado el de
  plantillas, `templates: null`, aunque el de ejercicios esté prendido.
- `recountTemplates(app, uid)` escribe `templateUsage.count` en absoluto y sólo
  si cambió. Se calcula como **total menos archivadas**:
  - `routines where assignedBy == uid && source == 'trainer-template'` → `count()`
  - lo mismo `&& status == 'archived'` → `count()`
  - **Por qué la resta y no `status == 'active'`:** `status` tiene default
    `active` en el modelo «para retro-compat» (`routine.dart:42`). Una plantilla
    vieja sin el campo no matchea `== 'active'` y quedaría sin contar.
- ⚠️ **Adentro de una transacción, no calcado de `recountCustomExercises`.** El
  recuento de ejercicios (`trainer-plan-limits.ts:145-155`) cuenta y después
  hace un `update` suelto. Eso lo protege de la redelivery, no de dos
  invocaciones concurrentes. Contador en 1; el evento A cuenta 2 y se demora; el
  evento B cuenta 3 y escribe 3; A escribe 2. Quedan 3 plantillas con el
  contador en 2, y la regla deja crear la cuarta. Leer el doc del usuario y los
  dos `count()` en la misma transacción serializa los recuentos sobre ese doc:
  el que escribe último contó después del otro. Verificar que la versión de
  `@google-cloud/firestore` de `functions/` acepta un `AggregateQuery` en
  `transaction.get()`; si no, escribir con precondición `lastUpdateTime` y
  reintentar.

**Índices: ninguno nuevo.**

- Los dos `count()` son sólo igualdades, sin `orderBy`. Esas queries las sirve
  el merge de los índices de un campo, que `docs/firestore-indexes.md:169-220`
  documenta con un precedente de tres igualdades (`byAuthorGymTier`) y un
  compuesto equivalente catalogado como redundante. `firestore.indexes.json` no
  tiene `fieldOverrides` sobre `routines` (el único es `sessions.startedAt`).
- El compuesto `assignedBy, source, createdAt` que ya existe
  (`firestore.indexes.json:202-217`) no hace falta para el conteo; lo usa
  `watchTemplatesBy`, que sí ordena.
- ⚠️ **El emulador no valida índices.** Igual hay que correr las dos queries
  contra producción antes de encender. Pasó con el #1156: había índices vivos en
  producción que el repo no conocía.

**`functions/src/subscriptions/sync-entitlements.ts`:** nada nuevo. Ya escribe
lo que devuelve `resolvePlanLimits`, así que la clave nueva viaja sola.

**`functions/src/subscriptions/template-count.ts`** (nuevo):

- `onDocumentWritten("routines/{routineId}")` en `southamerica-east1`.
- ⚠️ **Dispara con CUALQUIER escritura de `routines`**: rutinas del alumno,
  planes asignados, el agregado de ratings que escribe
  `templateRatingAggregate` sobre el padre y lo que escriba la moderación. La
  guarda tiene que salir antes de leer nada.
- **La guarda compara pertenencia, no sólo existencia y `status`.** Un doc
  «cuenta para X» si existe, `source == 'trainer-template'`,
  `assignedBy == X` y `status != 'archived'`. Relevante si ese par
  (cuenta, dueño) cambió entre `before` y `after`. Las reglas no dejan al
  cliente cambiar `source` ni `assignedBy`, pero el Admin SDK sí
  (`scripts/backfill_routines_source_visibility.js:93-111` reescribe `source`), y
  una guarda que sólo mira existencia y `status` se saltearía ese cambio.
- Recuenta **cada dueño afectado**: `before.assignedBy` y `after.assignedBy` si
  difieren. Para cada uno lee `role`; si no es `trainer`, no escribe.
- **Ya hay otro `onDocumentWritten` sobre el mismo path:** `quarantineRoutine`
  (`functions/src/moderation/quarantine-vetted-content.ts:701-702`). Hacer la
  misma auditoría anti-loop que `custom-exercise-count.ts:17-47`. El trigger
  nuevo sólo escribe `users/{uid}`, así que no reentra, pero tiene que quedar
  escrito.

**`functions/src/subscriptions/entitlement-triggers.ts`:** en el barrido diario,
sumar `recountTemplates` al lado de `recountCustomExercises`.

**`functions/src/index.ts`:** exportar el trigger.

**Tests (jest):**

- **`tier-config.test.ts`:** la escalera de plantillas es monótona **no
  estricta** (3, sin tope, sin tope, sin tope). Ojo: el test de ejercicios pide
  estrictamente creciente; éste no puede, y tiene que decir por qué.
- **`trainer-plan-limits.test.ts`:** cada interruptor gobierna sólo su clave.
  Los cuatro casos: los dos apagados, los dos prendidos, uno y el otro.
- **`template-count.test.ts`** (emulador):
  - Crear, borrar, archivar y restaurar una plantilla recuentan.
  - Editar el contenido o recibir un rating **no** escribe.
  - Una rutina del alumno o un plan asignado no escriben.
  - Una plantilla sin `status` cuenta.
  - Un alumno con un `trainer-template` forjado no escribe.
  - Una redelivery deja el mismo valor.
  - Un cambio de `source` o de `assignedBy` por Admin SDK recuenta a los dos
    dueños.
  - Dos recuentos concurrentes terminan en el valor real.

### PR 2: reglas

**En `users/{uid}`:** pinear `templateUsage` en create (junto a L355) y en
update (junto a L482), igual que `customExerciseUsage`.

**En `routines/{routineId}`:**

```
function templateQuotaOk(u) {
  return u.get('role', '') != 'trainer'
      || u.get('planLimits', {}).get('templates', null) == null
      || u.get('templateUsage', {}).get('count', 0)
           < u.get('planLimits', {}).get('templates', null);
}
```

- **CREATE branch 1** (~L808): la cuota va **adentro de la alternativa
  `trainer-template`**, no afuera. Así el `get()` del usuario sólo se cobra al
  crear una plantilla, y crear un plan asignado sigue sin lectura extra.
- **Y sólo si la plantilla creada cuenta.** El CREATE no valida `status`, y
  `createTemplate` conserva el que recibe (`routine_repository.dart:738-742`).
  Una plantilla creada ya archivada no suma al conteo, así que no tiene por qué
  pedir lugar. Si pide lugar, el rechazo es falso:
  ```
  && (request.resource.data.get('status', 'active') == 'archived'
      || templateQuotaOk(get(/databases/$(database)/documents/users/$(request.auth.uid)).data))
  ```
  Restaurarla después pasa por el path 6, que sí pide lugar.
- **UPDATE path 6** (~L1171), archivar y restaurar: la cuota se suma sólo
  cuando se **restaura una plantilla**:
  ```
  && (resource.data.source != 'trainer-template'
      || request.resource.data.status != 'active'
      || templateQuotaOk(get(/databases/$(database)/documents/users/$(request.auth.uid)).data))
  ```
  Archivar sigue sin lectura extra. El comentario del path 6 que dice «un
  `get()` acá costaría una lectura facturada por archivada, a cambio de nada»
  hay que actualizarlo: ahora hay algo a cambio, y sólo en la restauración.
- **No se tocan** el path 4 (editar contenido), el path 5 (publicar) ni el
  DELETE. Ninguno sube la cuenta.

**Tests (emulador):** extender `template-publishing-rules.test.ts` o crear
`template-quota-rules.test.ts`, y extender `users-subscription-rules.test.ts`.

- Un PF Free con 2 plantillas crea la tercera; con 3, no crea la cuarta.
- En el tope, crear una plantilla con `status: 'archived'` pasa; restaurarla, no.
- Pasado de tope: edita, publica, asigna, archiva y borra.
- Archivar una deja restaurar sólo si hay lugar.
- Crear un plan asignado nunca mira la cuota.
- Límite `null` o ausente: crea.
- Un alumno crea su forjado como hasta hoy. La cuota no se le aplica; lo que lo
  frena al publicar es el gate de rol del path 5.
- Un cliente no puede escribir `templateUsage` ni `planLimits.templates`.
- **Control negativo obligatorio:** sacar `templateQuotaOk` del create y
  confirmar que los tests de tope se ponen rojos.

### PR 3: el gate del cliente (Dart)

**`lib/features/coach/domain/subscription_tier.dart`:** `kTierTemplateLimits`
(`Map<SubscriptionTier, int?>`) y el getter `templateLimit`.

**`test/conformance/tier_limits_parity_test.dart`:** sumar el grupo
`TIER_TEMPLATE_LIMITS` ↔ `kTierTemplateLimits`, con el mismo molde que los dos
que ya tiene.

**`lib/features/coach/application/template_quota_provider.dart`:** calcado de
`custom_exercise_quota_provider.dart`.

- `limit` sale de `planLimits.templates`.
- `count` sale del stream que el PF ya lee (`watchTemplatesBy`), **filtrando las
  archivadas**. Está fresco; el contador del servidor viene atrasado.

**El embudo:** `lib/features/coach/presentation/template_limit_gate.dart`, con
`intentarCrearPlantilla(context, ref)`, calcado de
`intentarCrearEjercicioPropio`. Anota el tope con
`registrarTopeDelPlanPf(uid, 'templates')`.

**El aviso:** conviene **generalizar** `custom_exercise_limit_notice.dart` a un
aviso de tope por `kind`, en vez de copiarlo. Son dos avisos que tienen que
decir lo mismo con otra palabra, y dos copias divergen.

**Los puntos de entrada**, que son los que llegan a `createTemplate` o a
`unarchive` sobre una plantilla:

| Superficie | Archivo | Línea | Qué |
|---|---|---|---|
| Web | `lib/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_hero.dart` | 285 | «Nueva plantilla» |
| Web | `lib/features/coach_hub/presentation/sections/routine_editor/routine_editor_web_screen.dart` | 2309 | Guardar una plantilla nueva (cubre también el deep link `/template-editor`) |
| Web | mismo archivo | 2243 | «Guardar como copia»: crea una plantilla |
| Web | `lib/features/coach_hub/presentation/sections/rutinas/routine_actions_provider.dart` | 220 | «Publicar como plantilla» desde un plan asignado: crea una plantilla |
| Web | mismo archivo | 69 | Restaurar una plantilla archivada |
| Móvil | `lib/features/workout/trainer_workout_view.dart` | 247 | «NUEVA» |
| Móvil | `lib/features/workout/presentation/routine_editor_screen.dart` | 2971 | Guardar una plantilla nueva |

- **Web:** gatear **antes de abrir el editor** cuando se crea una nueva, para
  que el PF no arme una plantilla entera y recién al guardar se entere. En
  «Guardar como copia» y «Publicar como plantilla», gatear antes de pedir el
  nombre.
- **Rebote del servidor:** en los tres `createTemplate` y en `unarchive`, un
  `permission-denied` de un PF muestra el mismo aviso, no el error genérico.
- **«Publicar como plantilla» fuerza `status: active`.** Hoy hace
  `plan.copyWith(...)` sin tocar el `status` (`routine_actions_provider.dart:220`),
  así que publicar un plan archivado crea una plantilla archivada que el PF no ve
  en su lista. Con el `status` forzado, la plantilla nueva es visible y pasa por
  la cuota como cualquier otra.
- **El texto del aviso interpola el límite**, no escribe «3» a mano: el número
  vive en `planLimits.templates`.

**Los avisos:**

- **Móvil, sólo estado:** «Llegaste a las 3 plantillas de tu plan. Podés
  editarlas, asignarlas o archivar una para hacer lugar.»
  - Sin botón, sin «web», sin «mail», sin «pasá a un plan».
  - Correr `anti_steering_movil_test.dart`. Si se pone rojo, se cambia el texto,
    no el guard.
- **Web:** el mismo estado, más el botón **VER PLANES** a facturación.

**El contador visible:** «2 de 3 plantillas» en la grilla de rutinas del Hub
(`routine_card_grid.dart`) y en la sección de plantillas de
`trainer_workout_view.dart`. Con límite `null` no se muestra.

**Tests:**

- El provider: campo ausente, `null`, un número, caché fría, y que una archivada
  no cuenta.
- El embudo: bajo, en y sobre el tope. El alumno nunca se bloquea.
- Cada punto de entrada, con un widget test.
- El rebote del servidor muestra el aviso.
- La paridad entre Dart y TypeScript.
- Ningún `null` renderizado.

**Deploy:** el Coach Hub cuando se mergea. El móvil, en el build que sale a las
tiendas; es inerte mientras el campo esté en `null`.

### PR 4: el mail

`trainer-limit-mail.ts` hoy lee **sólo** `planLimits.customExercises` y
`customExerciseUsage` (`sigueEnElTope`, ~L133). Hay que **generalizarlo por
`kind`**:

- Una tabla `kind → {clave de planLimits, campo de uso}`, con
  `customExercises` y `templates`.
- `decideTrainerLimitMail` usa el `trainerLimitHitKind` anotado para saber qué
  tope mirar.
- Kind de mail nuevo, `"template-limit-reached"`, con su template en
  `functions/src/mail/templates.ts` y su tipo en `types.ts`. Mismo CTA a
  facturación y mismo `prefKey` (`novedades_plan`).

**El enfriamiento de 14 días (`trainerLimitMailAt`) queda compartido** entre los
dos topes. Un PF que choca los dos recibe un solo mail cada 14 días. Es lo que
se quiere: el problema es el spam, no qué tope fue.

**Tests:** las cuatro cláusulas de silencio para el kind nuevo, la tabla de
kinds, y el template con el test de tildes del #1236.

### PR 5: copy de planes (Coach Hub)

- **`plan_copy.dart`:** sumar `plantillasTexto(tier)` al lado de
  `ejerciciosTexto` (L27).
- **`pricing_screen.dart`:** sumar `_tierTemplates(tier)` al lado de
  `_tierExercises` (L752) y mostrarlo donde hoy se muestra `_tierExercises`
  (L930). La otra variante de tarjeta (~L1134) muestra sólo alumnos; seguir el
  mismo criterio que usó el #1241.
- **`facturacion_tab.dart`:** una línea de uso, «Plantillas: 2 de 3», sólo en
  Free. ⚠️ **Con un provider de resumen, no con el del gate.** La línea de
  ejercicios lee `customExerciseUsageSummaryProvider`
  (`custom_exercise_quota_provider.dart:89-110`), que usa el contador
  denormalizado del doc del usuario: una lectura. El provider del gate escucha la
  colección entera. Para plantillas va un `templateUsageSummaryProvider` sobre
  `templateUsage.count` y `planLimits.templates`. Calcar el provider del gate
  para esta línea es leer todas las plantillas para mostrar un número.

### PR 6: el link de pago de los mails del PF (hacer primero)

**El bug que ya está en `main`.** Los tres mails de plata del PF mandan a
`trainerEntry({to: "facturacion"})`, o sea a
`https://app.gettreino.com/abrir/profe?to=facturacion`:

| Mail | Dónde |
|---|---|
| `subscription-grace` y `subscription-downgraded` | `subscription-mail.ts:363` |
| `limit-reached` (el que nunca pagó y chocó el cupo) | `subscription-mail.ts:513` |
| `exercise-limit-reached` | `trainer-limit-mail.ts:218` |

`/abrir/*` es un App Link (`apple-app-site-association` y el `pathPrefix` del
`AndroidManifest.xml`). **En un teléfono con la app instalada, el link abre la
app**, que lo manda a `/facturacion/planes` (`router.dart:323`). Y en la app esa
pantalla informa pero no vende: `resolvePlanCheckout` sólo da punto de compra en
el Coach Hub web (`pricing_screen.dart`, dartdoc de `PricingScreen`). El PF que
lee el mail en el teléfono, que es lo normal, **toca VER LOS PLANES y no tiene
cómo pagar**. Justo el canal que existe porque la app no puede vender.

**En la computadora, en cambio, funciona, y eso prueba el destino.** Desde el
#923, `vercel.json` redirige `/abrir/profe` en el servidor a
`https://app.gettreino.com/`, y el redirect **conserva el query**. Medido el
25/09/2026:

```bash
curl -sI "https://app.gettreino.com/abrir/profe?to=facturacion" | rg -i '^(HTTP|location)'
# HTTP/2 307
# location: https://app.gettreino.com/?to=facturacion
```

O sea que la URL que propone este PR es exactamente donde el PF de escritorio
ya aterriza hoy. El arreglo no inventa un camino: saca el desvío por el App Link
que sólo muerde en el teléfono.

⚠️ No te guíes por `web/abrir/profe.html:29`. Su meta-refresh va a la raíz
**sin** el query, pero es la red para cuando se saque el redirect: hoy el HTML
no llega a servirse (#923). Una primera versión de esta revisión lo leyó como
un bug vivo, y era falso.

**El Coach Hub lo sirve Vercel, no Firebase Hosting.** Para verificar el ruteo de
`app.gettreino.com`, el archivo es `vercel.json` (los `redirects` corren antes
que los `rewrites`), no el target `coach-hub-dev` de `firebase.json`.

**El arreglo: que el link de pago no pase por `/abrir`.**

- `apple-app-site-association` sólo reclama `/abrir/*`, con un comentario que
  dice que el resto de `app.gettreino.com` «tiene que seguir abriendo en el
  navegador». Android igual (`pathPrefix="/abrir"`).
- El Coach Hub ya lee el destino del query string de la URL inicial, en
  cualquier path, y lo respeta después del login
  (`DeepLinkDestination.fromQuery(... Uri.base.queryParameters)` en
  `coach_hub_router.dart`).
- Así que alcanza con mandar a
  `https://app.gettreino.com/?to=facturacion&plan=plan1&ciclo=monthly`: abre el
  navegador, pide login si hace falta y cae en `/facturacion/planes`.

**Por qué el Coach Hub y no la landing**, que es lo que hace el alumno:

- **El alumno paga en la landing porque no tiene ninguna superficie web.** El PF
  sí la tiene, y el checkout del PF ya existe ahí entero: precios, Mercado Pago,
  acreditación al volver (`acreditacion_al_volver.dart`) y baja.
- **Los términos dicen que el PF contrata en el Coach Hub**
  (`contrato-entrenador.md` §8.4 y `terminos-suscripcion.md` §3). Pagar en la
  landing obliga a cambiarlos.
- **La exención 3.1.3(f) del PF se apoya en que el Coach Hub es la herramienta
  web paga.** Vender ahí es la posición más fuerte; una página que sólo cobra es
  justo lo que el Anexo B de los términos señala como débil para el alumno.
- **Costo:** esto es un helper de URL, un parámetro nuevo y un preseleccionado.
  Un checkout del PF en `treino-app` es login, precios, checkout, retorno y baja
  nuevos, más un segundo lugar donde mantener los precios.

**Archivos:**

- **`functions/src/mail/templates.ts`:** `trainerWebCheckout({plan?, ciclo?})`,
  que arma `https://app.gettreino.com/?to=facturacion[&plan=…&ciclo=…]`. El
  dartdoc tiene que decir por qué **no** usa `APP_ENTRY_TRAINER`: es un App Link,
  y la app no vende.
- **Los tres mails de arriba y el nuevo `template-limit-reached`** pasan a
  `trainerWebCheckout`.
- **El plan elegido, en el mail:**
  - En los mails de tope va **el plan más barato que resuelve el tope que
    chocó**. Para plantillas, Free pasa a Plan 1. Para ejercicios, el primer
    plan cuyo tope supere el conteo actual.
  - Se muestra con su precio, que sale de `TIER_PRICES_ARS` en el servidor, y un
    botón «PASAR AL PLAN 1» que lleva ese plan en el link.
  - Abajo, un link de texto «Ver todos los planes», sin plan.
  - En `grace` y `downgraded` va el plan que ya tenía.
  - **Los precios van en el mail y nunca en la app:** Apple permite comunicar
    medios de pago fuera de la app, no adentro.
- **`lib/core/utils/deep_link_destination.dart`:** el destino `facturacion`
  suma `plan` (`plan1`, `plan2` o `plan3`) y `ciclo` (`monthly` o `annual`),
  opcionales. Un valor que no está en la lista **se ignora** y el destino sigue
  siendo facturación a secas: un link viejo o editado a mano no puede romper la
  entrada.
- **`lib/app/coach_hub_router.dart`:** `_coachHubPathFor` (L212) pasa esa
  preselección a `/facturacion/planes`.
- **`pricing_screen.dart`:** acepta la preselección. Pone el ciclo, **resalta**
  la tarjeta del plan y la lleva a la vista. **No abre Mercado Pago solo:** el PF
  confirma con un toque. Cobrar sin una acción suya en la pantalla sería peor
  que el bug.
- **La app móvil no cambia.** Estos links nunca llegan a ella.

**Tests:**

- **TypeScript:**
  - `trainerWebCheckout` nunca arma una URL bajo `/abrir`.
  - Un guard que escanea los mails de plata y falla si alguno usa
    `APP_ENTRY_TRAINER`, con el mismo molde que los guards de texto del repo.
  - Cada mail de tope elige el plan correcto en los bordes (en el tope exacto, y
    pasado por uno).
- **Dart:**
  - `fromQuery` parsea `plan` y `ciclo`, e ignora valores inválidos.
  - Después del login, el Coach Hub cae en `/facturacion/planes` con el plan
    resaltado y el ciclo puesto.
  - Sin preselección, la pantalla queda como hoy.

**Se parte en dos PRs**, y el primero ya arregla el bug solo:

- **6a, el link (bugfix):** `trainerWebCheckout()` sin parámetros, los tres
  sitios que hoy usan `trainerEntry({to: "facturacion"})` y el guard. Con esto
  el link abre el navegador y cae en `/facturacion/planes`, que es lo que ya
  pasa en la computadora (R8). Ningún cambio de copy ni de Dart.
- **6b, el plan elegido (feature):** el parámetro `{plan?, ciclo?}`, el plan y
  el precio en el cuerpo de los mails, el botón «PASAR AL PLAN 1» y el link
  «Ver todos los planes», más `DeepLinkDestination`, `_coachHubPathFor` y la
  preselección en `pricing_screen.dart`. Van juntos porque el plan en el link
  sin la preselección no le sirve a nadie.

**Antes de la prueba a mano:** mirar en el dashboard de Resend si el *click
tracking* está prendido (no aparece en `functions/src/mail/`). Si lo está, todo
link pasa primero por el dominio de tracking de Resend, que no está en el AASA:
el camino normal ya sería el navegador y no la app, y la prueba tiene que
cubrir ese redirect.

**Verificación a mano, la que importa:** en un iPhone y en un Android **con la
app instalada**, abrir el mail en la app de Gmail, tocar el botón y confirmar
que:

1. Abre el navegador y no la app.
2. Pide login y, después, cae en precios con el plan resaltado.
3. Llega a Mercado Pago (sandbox) y la acreditación al volver funciona.

**Legales:** no cambian. El PF sigue contratando en el Coach Hub web, que es lo
que dicen los dos documentos.

### Legales (PR aparte, sólo docs)

Mismo criterio que el #1243: se puede publicar antes que el código, porque no
hay entrenadores reales y, con el interruptor apagado, el texto describe un tope
más estricto que el que se aplica.

**`docs/legal/contrato-entrenador.md`:**

- **§8, primer párrafo:**
  > …cuántos alumnos podés atender simultáneamente, cuántos ejercicios propios
  > podés tener en tu biblioteca **y cuántas plantillas podés tener activas**.
- **§8.1:** la tabla suma la columna «Plantillas»: 3 / Sin límite / Sin límite /
  Sin límite.
- **§8.2.ter, nueva:**
  > **Cómo se cuentan las plantillas.** Cuentan las plantillas que creaste y no
  > archivaste, estén publicadas o no. Asignarle una plantilla a un alumno no
  > cuenta, y tampoco los planes que armás directamente para un alumno. Si
  > archivás una plantilla, liberás su lugar; para recuperarla tenés que tener
  > lugar en tu plan. Si tu plan baja y quedás por encima del límite, conservás
  > todas tus plantillas y podés seguir usándolas, editándolas, asignándolas y
  > publicándolas. Lo único que no podés es crear nuevas ni recuperar archivadas
  > hasta quedar por debajo del límite de tu plan.
- **§8.3:** sumar las plantillas a «Tus ejercicios propios tampoco se borran».

**`docs/legal/terminos-suscripcion.md`:**

- **§1:** «…para atender alumnos o tener ejercicios propios…» pasa a decir
  «…para atender alumnos, tener ejercicios propios **o más plantillas** por
  encima de los límites del plan gratuito».
- **§2.1:** la tabla suma la columna «Plantillas».
- **§9:** sumar las plantillas a la frase de los ejercicios propios.

Correr el generador y sincronizar `legal-content.json` en `treino-app`, como con
el #1243. Concretamente:

- `python3 scripts/build_legal_content.py` regenera
  `web/legal/legal-content.json` **en este repo**. Es el único archivo generado
  que cambió en el #1243.
- Después, **un PR aparte en el repo `treino-app`** que copie ese JSON a la
  landing (`docs/limite-ejercicios-pf.md:469`, «igual que #18 y #19»).
- **No hay bump de versión ni re-aceptación.** Lo que el usuario acepta en la app
  (`legal_content.dart`) lleva sólo Términos y Privacidad
  (`scripts/build_legal_content.py:342-347`). Ni el contrato del entrenador ni
  los términos de suscripción están en el binario, y el #1243 no tocó
  `legal_content.dart`.
- ⚠️ **La condición «no hay entrenadores reales» hay que confirmarla, no
  suponerla.** El #1244 enciende el tope de ejercicios en producción el mismo
  día que se escribe este plan. Si ya hay un PF real, publicar un tope nuevo es
  un cambio de límites y rige el aviso previo del §12.

---

## 4. Encendido

**Antes:** PR 1 a PR 4 deployados, las dos queries del conteo corridas contra
producción y los legales publicados. **Todo antes del primer entrenador real.**

1. Merge del PR 5 y deploy del Coach Hub.
2. `TRAINER_TEMPLATE_LIMITS_ENABLED = true` y deploy de functions.
3. Correr el barrido a mano.
4. **Verificar:**
   - Un PF Free tiene `planLimits.templates: 3` y el conteo correcto.
   - Un PF pago tiene `planLimits.templates: null`.
   - En el tope, «Nueva plantilla» en la web muestra el aviso con VER PLANES y no
     abre el editor.
   - En el tope, desde el teléfono, el aviso de estado, sin botón.
   - En el tope, **asignar una plantilla a un alumno funciona**. Es el control
     negativo más importante.
   - Archivar una libera el lugar; restaurarla con el tope lleno rebota con el
     aviso.
   - Al día siguiente sale el mail de plantillas para quien chocó el tope.

**Rollback:** el interruptor vuelve a `false`, se deploya, y en el próximo sync
`planLimits.templates` vuelve a `null`. Nada que migrar.

---

## 5. Riesgos aceptados

| Riesgo | Por qué se acepta |
|---|---|
| **El trigger dispara con toda escritura de `routines`** | Sale en la guarda, sin leer nada, salvo que sea una plantilla cuya existencia o `status` cambió. Son invocaciones, no lecturas |
| **Una ráfaga fabricada se pasa del tope** | Igual que en ejercicios (E7). Lo frena el camino de la app |
| **Un alumno puede tener un `trainer-template` forjado** | Ya pasa hoy (CREATE branch 1 no chequea rol). La cuota no lo empeora y el path 5 le impide publicarlo |
| **Un PF recién promovido queda sin tope hasta el barrido de las 04:00** | Igual que en ejercicios |
| **El enfriamiento del mail es compartido** | Un solo mail cada 14 días por PF, choque el tope que choque |

---

## 6. Checklist

**PR 1**
- [ ] `TRAINER_TEMPLATE_LIMITS_ENABLED` gobierna sólo su clave
- [ ] El conteo resta las archivadas y cuenta las plantillas sin `status`
- [ ] El recuento corre en transacción: dos concurrentes no dejan un valor viejo
- [ ] La guarda del trigger sale sin leer en rutinas del alumno, planes asignados y ratings
- [ ] La guarda ve cambios de `source` y `assignedBy`, y recuenta a los dos dueños
- [ ] Sin índices nuevos

**PR 2**
- [ ] Cuota en el create de plantilla y en la restauración, sin `get()` en los demás caminos
- [ ] Crear una plantilla ya archivada no pide lugar
- [ ] `templateUsage` pineado en create y update
- [ ] Control negativo en rojo al sacar la cuota

**PR 3**
- [ ] Siete puntos de entrada por el embudo
- [ ] «Publicar como plantilla» fuerza `status: active`
- [ ] El aviso es el mismo componente que el de ejercicios, con el límite interpolado
- [ ] Guards de anti-steering en verde sin excepciones nuevas

**PR 5**
- [ ] La línea de Facturación lee el contador denormalizado, no la colección

**PR 4**
- [ ] El mail elige el tope por `trainerLimitHitKind`

**PR 6**
- [ ] Ningún mail de plata del PF usa `APP_ENTRY_TRAINER`, y un guard lo impide
- [ ] Probado en un iPhone y un Android con la app instalada: abre el navegador, no la app
- [ ] El plan elegido llega resaltado; Mercado Pago no se abre solo

**Legales y encendido**
- [ ] Legales publicados y landing sincronizada (PR en `treino-app`)
- [ ] Las dos queries del conteo corridas contra producción
- [ ] Confirmado que no hay entrenadores reales, o aviso previo del §12 dado
- [ ] Encendido antes del primer entrenador real
- [ ] Asignar en el tope funciona

---

## 7. Revisión contra el código (25/09/2026)

Verificado contra `656121cd` (= `origin/main` al escribir el plan) por tres
revisores por área y una revisión adversarial de Codex sobre el enforcement
(hilo `01a0d8dc-c982-7400-9d0e-a794da1524cd`). **El plan se sostiene**: los
números de línea y las afirmaciones sobre el código coinciden, salvo lo que
sigue. Todo ya está corregido arriba.

### Lo que cambió el diseño

| # | Dónde | Qué estaba mal | Evidencia |
|---|---|---|---|
| R1 | PR 1 | El recuento calcado de ejercicios tiene una carrera entre invocaciones concurrentes que deja el contador bajo y habilita una plantilla de más. Va en transacción | `trainer-plan-limits.ts:145-155` |
| R2 | PR 1 | La guarda del trigger no veía cambios de `source` ni de `assignedBy`, que el Admin SDK sí hace. Compara pertenencia y recuenta a los dos dueños | `scripts/backfill_routines_source_visibility.js:93-111` |
| R3 | PR 2 | La cuota del create rechazaba también plantillas creadas ya archivadas, que no suman | `firestore.rules:808-834`, `routine_repository.dart:738-742` |
| R4 | PR 1 | El índice `assignedBy, source, status` sobra: tres igualdades sin `orderBy` las sirve el merge de índices de un campo | `docs/firestore-indexes.md:169-220`, `firestore.indexes.json:706-725` |

### Lo que faltaba

| # | Dónde | Qué |
|---|---|---|
| R5 | PR 1 | Ya existe `quarantineRoutine` sobre `routines/{routineId}`; falta la auditoría anti-loop escrita |
| R6 | PR 3 | «Publicar como plantilla» hereda el `status` del plan: uno archivado da una plantilla archivada |
| R7 | PR 5 | La línea de Facturación tiene que leer el contador denormalizado, no escuchar la colección |
| R8 | PR 6 | En la computadora el link ya llega a `/?to=facturacion` por el redirect de `vercel.json` (#923), medido con `curl`: el destino del arreglo ya está probado en producción. El meta-refresh de `profe.html:29` no cuenta, porque no se sirve |
| R9 | PR 6 | El Coach Hub lo sirve Vercel (`vercel.json`), no `firebase.json`. Y falta mirar el *click tracking* de Resend antes de la prueba a mano |
| R10 | Legales | El JSON se regenera en este repo con `scripts/build_legal_content.py`, más un PR en `treino-app`; no hay bump de versión |
| R11 | Encendido | El #1244 enciende ejercicios en producción; la condición «no hay entrenadores reales» hay que confirmarla |

### Lo que queda abierto fuera de este plan

- **La misma carrera de R1 vive en `recountCustomExercises`**, que ya corre en
  producción. La cura el barrido diario, pero hasta entonces un PF puede quedar
  con un ejercicio de más. Es un PR aparte, chico, sobre el mismo archivo.

### Confirmado sin cambios (muestra)

`tier-config.test.ts:50-56` exige estrictamente creciente · `sync-entitlements.ts:400-416`
escribe `planLimits` entero con `merge: true`, la clave nueva viaja sola ·
`trainerLimitHitKind` no tiene allowlist en reglas (`rg -n trainerLimitHitKind firestore.rules`
→ nada) · `status` sólo vale `active` o `archived` (`routine_status.dart:8-13`) ·
los 4 `createTemplate` y el único camino de `unarchive` del cliente (grilla →
`routine_actions_provider.dart:69` → repo) son los de la tabla del PR 3
(`rg -n '\.createTemplate\(|unarchive\(' lib/`) · el texto móvil pasa
`anti_steering_movil_test.dart` · `TIER_PRICES_ARS` existe (`tier-config.ts:76`) ·
el texto legal que cita el plan coincide con el actual.

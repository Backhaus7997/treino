# Límite de ejercicios propios por plan del entrenador: plan de implementación

**24 de septiembre de 2026.** Escrito contra `origin/main` de `treino` en
`15f7337e`. Los números de línea son de ese commit y se van a correr.

**Estado:** PR 0 a PR 4 y el copy del Coach Hub del PR 5 van juntos en un solo
PR, con el interruptor apagado (`TRAINER_EXERCISE_LIMITS_ENABLED = false`). Los
legales del PR 5 van en su propia rama, `docs/legal-limite-ejercicios-pf`, y se
publican antes que el código.

**Todavía no hay entrenadores reales:** todas las cuentas de PF son de prueba.
Por eso no hay aviso previo del §12 que mandar. La condición que queda es otra:
**el encendido (§4) tiene que ocurrir antes de dar de alta al primer entrenador
real.**

---

## 0. En una página

| Plan | Alumnos | Ejercicios propios |
|---|---|---|
| Free | 2 | **20** |
| Plan 1 | 7 | **60** |
| Plan 2 | 15 | **120** |
| Plan 3 | sin límite | **sin límite** |

**Qué se limita:** los documentos de `users/{uid}/customExercises` de un usuario
con `role == 'trainer'`.

**Qué NO se limita:**

- **El catálogo de TREINO** (793 ejercicios): no cuenta y se usa sin límite.
- **El alumno:** el editor de ejercicios es compartido, pero el tope corta por
  rol.
- **El import desde Excel:** no crea ejercicios propios, sólo matchea contra el
  catálogo (`plan_import_repository.dart`), así que no lo toca.
- **Los videos:** siguen con su tope actual de 50 × 100 MB, igual para todos.

**Cómo, en una línea:** el mismo patrón que ya usa la casa para
`athletePaywallEnforced` y `customExerciseVideoUsage`. Una Cloud Function
escribe la conclusión en `users/{uid}`, la regla la lee con un `get()` y el
cliente lee el mismo campo.

**Un solo interruptor, del lado del servidor.** El cliente no tiene flag propio:
si el campo dice `null`, no gatea. Encender o apagar es un deploy de functions,
no un build de tienda. Es la diferencia más importante con el paywall del
alumno, donde `kAthletePaywallEnabled` está compilado en el binario.

**Seis PRs y un encendido**, en el diseño original. En la práctica, PR 0 a PR 4
y el copy del Coach Hub van en un solo PR que se deploya apagado. Los legales
van por separado (ver Estado).

---

## 1. Decisiones

| # | Decisión | Por qué |
|---|---|---|
| E1 | **20 / 60 / 120 / sin límite** | Un programa del catálogo usa entre 14 y 35 ejercicios distintos (mediana 20). Las 7 plantillas juntas usan 54. Plan 2 duplica al 1, siguiendo la escalera de alumnos. Plan 3 sin tope, igual que con los alumnos |
| E2 | **Cuentan los que existen hoy**, no los creados en la historia | Borrar libera el lugar. Borrar no rompe rutinas: los slots denormalizan nombre y grupo al asignar (dartdoc de `delete` en `custom_exercise_repository.dart`) |
| E3 | **Bajar de plan congela la creación y no borra nada** | Editar, usar, asignar y borrar siguen permitidos siempre. Mismo criterio que los alumnos estacionados y que `noCreceLaForma` |
| E4 | **Sólo el rol `trainer`** | El alumno usa el mismo editor. Se corta por rol en la regla, en la CF y en el cliente, igual que `resolveAthletePaywallEnforced` |
| E5 | **El plan se resuelve igual que el tope de alumnos** | `active`/`grace` da el plan; `cancelled` da el plan hasta `currentPeriodEnd`; `pending`/`paused` da Free; y el piso prepago del #1203 sube el plan. Alumnos y ejercicios no pueden discrepar sobre el plan de alguien |
| E6 | **El borde es `count < limit` al crear** | Con límite 60 se pueden tener 60. El create que deja el contador en 60 pasa; el siguiente no |
| E7 | **Una ráfaga fabricada puede pasarse, y no se borra nada** | Ver §6. El tope de videos borra el excedente porque son bytes; un ejercicio es contenido que el PF armó |
| E8 | **En la web se vende; en el teléfono sólo se informa** | 3.1.3(f). En el móvil, el mensaje dice el estado y la salida es un mail. Mismo criterio que `plan_limit_paywall.dart` desde el #1141 |

---

## 2. Modelo de datos

Todo en `users/{uid}`, junto a los campos denormalizados que ya existen.

| Campo | Tipo | Quién lo escribe | Significado |
|---|---|---|---|
| `planLimits.customExercises` | `number \| null` | **Sólo la CF** | Tope vigente. `null` o ausente = sin tope |
| `customExerciseUsage.count` | `number` | **Sólo la CF** | Cuántos ejercicios propios tiene hoy |
| `trainerLimitHitKind` | `string` | El cliente | Qué tope chocó (`'customExercises'`) |
| `trainerLimitHitAt` | `Timestamp` | El cliente | Cuándo lo chocó. Lo lee el mail (PR 4) |

**Por qué `planLimits` es un mapa:** el próximo tope del PF (plantillas
públicas, espacio de archivos) suma una clave sin tocar los pins de las reglas.
Pinear un campo nuevo en `users` es justo la clase de cambio que el #563 enseñó
a hacer con cuidado.

**Por qué ausente = sin tope:** falla abierta, igual que `athletePaywallEnforced`
ausente. Mientras el interruptor esté apagado, o antes del primer sync, nadie
queda bloqueado por un dato que todavía no se escribió.

---

## 3. Los PRs

### PR 0: medición y spec (sin deploy)

**Archivos:**

- `scripts/medir_ejercicios_propios.js`, **sólo lectura**:
  - Entra por `lib/admin.js` (`inicializarAdmin`), con la credencial por
    `$TREINO_SA_KEY` y el guard `--allow-prod` de la casa.
    `treino-dev` **es** producción.
  - Por cada `users where role == 'trainer'` imprime `subscription.tier`,
    `subscription.status` y la cantidad de `customExercises`.
  - Al final imprime la mediana, el percentil 90, el máximo y **quién quedaría
    por encima de su tope**.
- `docs/limite-ejercicios-pf.md`: este documento, para que viva en el repo.

**Para qué:**

- Confirmar que los números no dejan a nadie actual pasado. Hoy hay pocos PF (el
  barrido del 16/09 daba `scanned: 5`), así que se revisa a ojo.
- Tener la lista de destinatarios del aviso (§5).

### PR 1: backend apagado (functions)

**`functions/src/subscriptions/tier-config.ts`**

```ts
export const TIER_CUSTOM_EXERCISE_LIMITS: Record<SubscriptionTier, number | null> = {
  free: 20,
  plan1: 60,
  plan2: 120,
  plan3: null, // SIN TOPE — mismo criterio y mismo motivo que TIER_WEIGHT_LIMITS
};
```

**`functions/src/subscriptions/effective-limit.ts`**: sumar
`export function effectiveTier(sub, nowMs): SubscriptionTier`.

- Tiene los mismos casos que `effectiveWeightLimit`, con el piso prepago tomado
  como el **máximo por orden de tier**.
- **No se toca `effectiveWeightLimit`.** Es el camino de la plata y ya tiene su
  red de tests. La consistencia entre los dos se prueba con un test (abajo), no
  con un refactor.

**`functions/src/subscriptions/trainer-plan-limits.ts`** (nuevo):

- `export const TRAINER_EXERCISE_LIMITS_ENABLED = false;` es el interruptor. El
  encabezado explica el orden de encendido, igual que el de
  `athlete-paywall-enforced.ts`.
- `customExerciseLimitFor(tier)` busca en la tabla.
- `resolvePlanLimits(sub, degraded, nowMs, enabled)` devuelve
  `{customExercises: number | null}`, o `null` para decir «no tocar».
  - Apagado: `{customExercises: null}` para todos. La plomería queda escrita y
    observable antes de importar, y apagar vuelve a limpiar el campo.
  - `degraded`: no se toca. Sobre un documento que sabemos que leímos mal no se
    decide nada, igual que el resto de `subscription-mail.ts`.
- `recountCustomExercises(app, uid)` usa
  `collection('users/{uid}/customExercises').count().get()` y escribe el valor
  **absoluto**, sólo si cambió. Recontar en vez de incrementar hace la escritura
  idempotente ante la entrega at-least-once, mismo motivo que el recuento de
  `custom-exercise-video-quota.ts`.
  - ⚠️ Es el primer `count()` del repo en functions. Verificarlo contra el
    emulador antes de asumirlo.

**`functions/src/subscriptions/sync-entitlements.ts`**: dentro de
`syncTrainerEntitlements` (L167), sumar `planLimits` al `tx.set` de
`users/{trainerId}` que ya existe y ya es incondicional. Usa el mismo `sub`, el
mismo `degraded` y el mismo `clock` con los que se calcula el tope de alumnos.

- **Por qué ahí y no en una función propia:** esa función ya corre en los tres
  caminos que importan: el trigger de suscripción, `linkLoadReconcile` y el
  barrido de las 04:00, que es el único que ve el vencimiento de un
  `cancelled`. Colgarse de ahí garantiza que los dos topes salen del mismo plan
  en el mismo instante. Una función aparte tendría que replicar los tres
  disparadores y su reloj.
- **Anti-loop, verificado:** `syncEntitlementsOnSubscription` compara sólo
  `subscription`, y el trigger del paywall del alumno compara sólo
  `athleteSubscription` y `role`. `planLimits` no toca ninguno.

**`functions/src/subscriptions/custom-exercise-count.ts`** (nuevo):

- `onDocumentWritten("users/{uid}/customExercises/{exId}")` en
  `southamerica-east1`.
- Sólo actúa en create o delete. Un update no cambia la cantidad y sale
  temprano.
- Lee `role`. Si no es `trainer`, no escribe nada: no se ensucia el documento
  del alumno ni se disparan sus triggers.
- Llama a `recountCustomExercises`.

**`functions/src/subscriptions/entitlement-triggers.ts`**: en el loop de
`sweepEntitlementsHandler`, llamar a `recountCustomExercises` por cada PF.

- Cura cualquier desvío del contador.
- Cubre al PF recién promovido por `scripts/promote_user_to_trainer.js`, que no
  dispara ningún trigger de suscripción.

**`functions/src/index.ts`**: exportar el trigger nuevo.

**Tests (jest):**

- **`effective-tier.test.ts`:**
  - La matriz de estados: los cinco status, el piso vigente y el vencido, el
    tier desconocido y el mapa ausente.
  - **La consistencia**, con el tope de alumnos como oráculo: para cada caso,
    `tierLimit(effectiveTier(s)) === effectiveWeightLimit(s)`.
- **`tier-config.test.ts`:** la escalera es monótona (20 < 60 < 120 < sin
  tope) y sigue el mismo orden que `TIER_WEIGHT_LIMITS`. El piso prepago toma
  el máximo, y eso sólo es correcto si las dos escaleras crecen juntas.
- **`trainer-plan-limits.test.ts`:**
  - Apagado: `null` para todos.
  - Encendido: el número que corresponde a cada plan.
  - `degraded`: no toca.
- **`custom-exercise-count.test.ts`** (emulador):
  - Create y delete recuentan; un update no escribe.
  - Una redelivery deja el mismo valor.
  - Un alumno no escribe nada.
- **`sync-entitlements`:** el `tx.set` lleva `planLimits`.

**Deploy:** functions. **Verificación en producción:** después del barrido de
las 04:00, o corriéndolo a mano, cada PF tiene
`planLimits.customExercises: null` y un `customExerciseUsage.count` que coincide
con lo que midió PR 0.

### PR 2: reglas

**`firestore.rules`, en `users/{uid}`:**

- **Create** (junto al pin de `customExerciseVideoUsage`, ~L338):
  `request.resource.data.get('planLimits', null) == null` y lo mismo para
  `customExerciseUsage`.
- **Update** (junto a ~L452): los dos quedan iguales a lo que había, con la
  misma forma que el pin de `customExerciseVideoUsage`.
- **Sin estos pins, el tope es decorativo.** El update de `users` no es una
  lista de campos permitidos, así que un cliente podría escribirse
  `{planLimits: {customExercises: null}}` y quedar sin tope. Es el mismo bypass
  de una sola escritura que documenta el pin de `athletePaywallEnforced`.

**`firestore.rules`, en `users/{uid}/customExercises/{exId}`** (~L2847), el
`allow write` se parte en dos:

```
function customExerciseQuotaOk(u) {
  return u.get('role', '') != 'trainer'
      || u.get('planLimits', {}).get('customExercises', null) == null
      || u.get('customExerciseUsage', {}).get('count', 0)
           < u.planLimits.customExercises;
}

match /users/{uid}/customExercises/{exId} {
  allow read: if request.auth != null;
  allow create: if request.auth != null
                && request.auth.uid == uid
                && customExerciseQuotaOk(
                     get(/databases/$(database)/documents/users/$(uid)).data);
  allow update, delete: if request.auth != null
                        && request.auth.uid == uid;
}
```

- El `get()` es una lectura facturada por cada create. Los ejercicios se crean
  poco, así que es barato. No aplica el mismo criterio a una lectura de alto
  volumen (ver `paywall-alumno-suelto.md` §6.3).
- Update y delete **no** miran la cuota. Es lo que hace cumplir E3.

**Tests (emulador):** uno nuevo, `custom-exercises-quota-rules.test.ts`, y
extender `users-subscription-rules.test.ts`.

- Un PF bajo el tope crea; en el tope no crea.
- Un PF **por encima** del tope (después de bajar de plan) no crea, pero edita y
  borra.
- Con límite `null` o ausente crea.
- Un alumno crea con cualquier valor en esos campos.
- Un cliente **no puede** escribir `planLimits` ni `customExerciseUsage`: en
  create y en update, cuatro casos.
- **Control negativo obligatorio:** sacar `customExerciseQuotaOk` del create y
  confirmar que los tests de tope se ponen rojos.

**Deploy:** reglas. Quedan inertes mientras `planLimits.customExercises` sea
`null`.

### PR 3: el gate del cliente (Dart)

Si no entra en 400 líneas, se parte en **3a** (provider, embudo y móvil) y
**3b** (web).

**`lib/features/coach/domain/subscription_tier.dart`:**

- `kTierCustomExerciseLimits` (`Map<SubscriptionTier, int?>`) y el getter
  `customExerciseLimit`.
- Es el espejo de `TIER_CUSTOM_EXERCISE_LIMITS`, igual que `kTierWeightLimits`
  espeja `TIER_WEIGHT_LIMITS`.

**`test/conformance/tier_limits_parity_test.dart`:** un grep sobre
`tier-config.ts` con el mismo molde que `paywall_flag_parity_test.dart`. Si el
archivo cambia de forma y no encuentra el literal, **falla**. Aprovechar para
cubrir también `TIER_WEIGHT_LIMITS`, que hoy se sincroniza a mano.

**`lib/features/coach/application/custom_exercise_quota_provider.dart`:**

- Un `StreamProvider` sobre `users/{uid}`, calcado de `chatMediaQuotaProvider`
  (`athlete_entitlement_provider.dart` ~L388), con la misma guarda de caché
  fría.
- Devuelve `{limit: int?, count: int}`.
- **El `count` sale del largo del stream de `customExercises` del PF**, que ya
  se lee entero y está fresco, no del contador denormalizado, que viene atrasado
  ~1 s. El servidor manda igual.

**El embudo único:** `lib/features/coach/presentation/custom_exercise_limit_gate.dart`.

- `Future<bool> intentarCrearEjercicioPropio(BuildContext, WidgetRef)`.
- Si `limit != null && count >= limit`: muestra el aviso de la superficie,
  anota el tope (PR 4) y devuelve `false`.
- Todos los puntos de entrada pasan por acá, igual que los ocho llamadores de
  `showFreePlanLimitSheet`.

**Los cinco puntos de entrada:**

| Superficie | Archivo | Línea |
|---|---|---|
| Móvil: «Mis ejercicios» | `lib/features/workout/presentation/my_exercises_screen.dart` | 313 |
| Móvil: picker del PF | `lib/features/coach/presentation/widgets/exercise_picker_sheet.dart` | 164 |
| Móvil: onboarding de ejercicios | `lib/features/onboarding/presentation/custom_exercise_onboarding_gate.dart` | 181 |
| Web: editor de rutinas | `lib/features/coach_hub/presentation/sections/routine_editor/routine_editor_web_screen.dart` | 382 |
| Web: picker | `lib/features/coach_hub/presentation/widgets/exercise_picker_dialog.dart` | 165 |

La Biblioteca web hoy no tiene botón de crear. Si se le agrega, pasa por el
mismo embudo.

**El rebote del servidor:**

- Dónde: `custom_exercise_editor_screen.dart:470` y
  `create_custom_exercise_dialog.dart:128`.
- Un `permission-denied` en el create de un PF muestra **el mismo aviso**, no el
  error genérico. Pasa si el contador se adelantó o si hubo una carrera.

**Los avisos:**

- **Móvil, sólo estado:**
  - En el tope: «Llegaste a los 60 ejercicios propios de tu plan. Podés editar o
    borrar los que ya tenés.»
  - Pasado de tope: «Tenés 80 ejercicios propios y tu plan incluye 60.
    Conservás todos; para crear uno nuevo, borrá 21.»
  - **Sin botón, sin «web», sin «mail», sin «pasá a un plan».** Correr
    `anti_steering_movil_test.dart` y `superficie_de_cobro_alumno_test.dart`. Si
    alguno se pone rojo, se cambia el texto, no el guard.
- **Web:**
  - En el tope: «Tu plan incluye 60 ejercicios propios y ya tenés 60.» con botón
    **VER PLANES** a facturación.
  - Pasado de tope: el mismo texto de conservación que en el móvil, más el
    botón.

**El contador visible:** «12 de 60 ejercicios propios» en «Mis ejercicios»
(móvil) y en el picker web. Es estado, y el estado está permitido. Con límite
`null` no se muestra.

**Plan 3 y `null`:** nunca se interpola el límite a mano. Va por
`plan_copy.dart` (§PR 5). Es el mismo agujero que publicó «Hasta null alumnos».

**Convenciones:**

- Strings del móvil en `intl_es_AR.arb` e `intl_en.arb`. Las del Coach Hub,
  con `// i18n: Fase W3` como el resto.
- `AppPalette`, `AppRadius` y `AppTextSize` desde el primer renglón, por los
  tres guards de ratchet.

**Tests:**

- **El provider:** campo ausente, `null`, un número y caché fría.
- **El embudo:** bajo, en y sobre el tope. El alumno nunca se bloquea.
- **Cada punto de entrada**, con un widget test.
- **El rebote del servidor:** el `permission-denied` muestra el aviso.
- **La paridad** de los topes entre Dart y TypeScript.
- **Ningún `null` renderizado** en ninguna superficie.

**Deploy:**

- El Coach Hub web sale cuando se mergea.
- El móvil entra en el próximo build de tienda, y **ese build tiene que estar
  publicado antes del encendido**. El build 52 no tiene el gate. Con el campo en
  `null` el gate es inerte, pero un móvil sin gate que choque el tope ve el
  error genérico de la regla.

### PR 4: el mail

**Por qué hace falta:** el PF que choca el tope desde el teléfono no puede
enterarse ahí de dónde se paga. Sin mail no tiene salida. Es la misma lógica que
`limit-reached` (#1149) para los alumnos.

**`lib/features/profile/data/user_repository.dart`:**

- Sumar `registrarTopeDelPlanPf(uid, kind)`, calcado de `registrarTopeTocado`
  (L499). Escribe `trainerLimitHitKind` y `trainerLimitHitAt`.
- Tiene catch silencioso: el aviso se muestra igual si la anotación falla.
- La llama el embudo del PR 3.

**`functions/src/subscriptions/trainer-limit-mail.ts`** (nuevo):

- `sweepTrainerLimitMail` diario a las **05:30 ART**. Va después del barrido de
  las 04:00 y no se pisa con los de las 05:00.
- Busca por `trainerLimitHitAt` en las últimas **36 h**, por el mismo motivo que
  documenta `free-limit-mail.ts`. No hace falta índice compuesto.
- Cuatro cláusulas de silencio, las mismas de `free-limit-mail.ts`:
  1. Sin anotación.
  2. Anotación vieja.
  3. Ya no está en el tope: `count < limit` o límite `null`.
  4. **Enfriamiento de 14 días.**

**Mail:**

- **`functions/src/mail/types.ts`:** kind nuevo `"exercise-limit-reached"`.
- **`functions/src/mail/templates.ts`:** el template.
  - El CTA es `trainerEntry({to: "facturacion"})`.
  - **Lleva `prefKey`:** ofrecerle un plan más caro a quien ya es cliente es
    comunicación comercial, y la política promete que la oposición a esas es
    absoluta. Mismo razonamiento que `athlete-prospect-mail.ts`.

**Tests:**

- La decisión pura con reloj fijo.
- Las cuatro cláusulas de silencio.
- El template pasa el test de tildes del #1236.

### PR 5: copy de planes y legales

> **Actualización:** los legales (`contrato-entrenador.md`,
> `terminos-suscripcion.md` y `web/legal/legal-content.json`) ya están hechos en
> la rama `docs/legal-limite-ejercicios-pf` (`5ad61525`) y se publican antes que
> el código. En la rama del feature queda sólo el copy del Coach Hub. Lo que
> sigue sobre los legales queda como registro de qué se pidió.

**Coach Hub:**

- **`pricing_screen.dart`:** sumar `_tierExercises(tier)` junto a
  `_tierStudents` (L723) y mostrarlo en las dos variantes de tarjeta (L905 y
  L1083).
- **`plan_copy.dart`:** sumar `ejerciciosTexto(tier)` al lado de `cupoTexto`
  (L13). Plan 3 dice «ejercicios propios sin límite», nunca `null`.
- **`lib/features/coach_hub/presentation/sections/ajustes/tabs/facturacion_tab.dart`:**
  una línea de uso, «Ejercicios propios: 12 de 60».

**`docs/legal/contrato-entrenador.md`:**

- **§8, primer párrafo:**
  > El uso profesional de TREINO requiere una suscripción, cuyo plan determina
  > cuántos alumnos podés atender simultáneamente **y cuántos ejercicios propios
  > podés tener en tu biblioteca**.
- **§8.1:** la tabla suma la columna «Ejercicios propios»: 20 / 60 / 120 / Sin
  límite.
- **§8.2.bis, nuevo:**
  > **Cómo se cuentan los ejercicios propios.** Cuentan los ejercicios que
  > creaste y tenés hoy en tu biblioteca. Los del catálogo de TREINO no cuentan y
  > los usás sin límite. Si borrás uno, liberás su lugar, y las rutinas que ya lo
  > usan no se rompen. Si tu plan baja y quedás por encima del límite,
  > conservás todos tus ejercicios y podés seguir usándolos, editarlos y
  > asignarlos; lo único que no podés es crear nuevos hasta quedar por debajo.
- **§8.3, al final:**
  > Tus ejercicios propios tampoco se borran: conservás todos y sólo se frena la
  > creación de nuevos por encima del límite del plan gratuito.

**`docs/legal/terminos-suscripcion.md`:**

- **§1:** «Los entrenadores requieren una suscripción para atender alumnos por
  encima del límite del plan gratuito.» pasa a decir:
  > Los entrenadores requieren una suscripción para atender alumnos **o tener
  > ejercicios propios** por encima de los límites del plan gratuito.
- **§2.1:** la tabla suma la columna «Ejercicios propios».
- **Debajo de la tabla:**
  > Los ejercicios del catálogo de TREINO no cuentan para el límite de
  > ejercicios propios. El detalle está en la sección 8 de los Términos para
  > Entrenadores.

**Regenerar:**

- `python3 scripts/build_legal_content.py`. El gate de CI rompe el PR si no se
  regenera.
- Estos dos documentos **no** van en `EN_EL_BINARIO`, así que no hace falta
  build de tienda ni subir `kTermsVersion`.
- **`treino-app`:** un PR que sincronice `legal-content.json`, igual que #18 y
  #19. La landing /gym no muestra precios de entrenador («contactanos»), así que
  no cambia su copy.

---

## 4. Encendido

**Cuándo:** antes de dar de alta al primer entrenador real. Hoy todos los PF son
cuentas de prueba, así que no hay aviso previo que mandar (§5).

**Antes:** el PR del feature deployado apagado y observado en producción, los
legales publicados, y un build de tienda con el gate del PR 3 publicado. El
build 52 no lo tiene.

1. `TRAINER_EXERCISE_LIMITS_ENABLED = true` y deploy de functions.
2. **Correr el barrido a mano**, sin esperar a las 04:00, para que todos los PF
   queden con su número de una vez.
3. **Verificar:**
   - Cada PF tiene el número que le corresponde según su plan.
   - Crear en el tope desde la web muestra el aviso con VER PLANES.
   - Crear en el tope desde el teléfono muestra el aviso de estado, sin botón.
   - Un alumno crea ejercicios sin fricción. **Es el control negativo.**
   - Un PF de Plan 3 no ve contador ni tope.
   - Al día siguiente sale el mail para quien chocó el tope.

**Rollback:** el interruptor vuelve a `false` y se deploya. En el próximo sync
`planLimits` vuelve a `null`, y la regla y el cliente dejan de gatear. No hay
nada que migrar.

---

## 5. El aviso a los entrenadores

`contrato-entrenador.md` §12 exige avisar con antelación cuando cambia un límite
de plan. **Hoy no aplica:** no hay entrenadores reales, todas las cuentas de PF
son de prueba, y los legales con el límite se publican antes que el código.

Aplicaría si el encendido se atrasara hasta después del alta del primer
entrenador real. Esa es justamente la condición del §4.

---

## 6. Riesgos aceptados

| Riesgo | Por qué se acepta |
|---|---|
| **Una ráfaga fabricada se pasa del tope.** Varios creates en paralelo se evalúan contra el mismo contador | Lo frena el camino de la app, por donde pasa el 100% de los usuarios reales. Es defensa en profundidad, igual que el sello del catálogo (#1155). No se borra el excedente: un ejercicio es contenido y puede estar asignado. Cerrarlo del todo exige crear por una callable con transacción, y eso cambia el camino de escritura que comparte el alumno |
| **El contador llega ~1 s tarde**, así que dos creates en el mismo segundo pueden pasar uno de más | Con el editor, crear dos ejercicios en un segundo no pasa |
| **Un PF recién promovido queda sin tope hasta el barrido de las 04:00** | Falla abierta, en una operación manual y rara. Si molesta, se suma `role` a la guarda del trigger en un cambio aparte |
| **El cliente cuenta con el stream y el servidor con el contador** | Pueden diferir un instante. El servidor manda, y el rebote se muestra con el mismo aviso |

---

## 7. Fuera de alcance

- Topes de plantillas públicas, de espacio de archivos del alumno o de videos por
  plan. `planLimits` ya deja el lugar para sumarlos.
- Cambiar los números. Se revisan después del lanzamiento contra el percentil 90
  real de cada plan (§E1).

---

## 8. Checklist

**PR 0**
- [ ] Medición corrida contra producción; nadie queda pasado, o se sabe quién
- [ ] Spec en `docs/limite-ejercicios-pf.md`

**PR 1**
- [ ] `effectiveTier` consistente con `effectiveWeightLimit` en toda la matriz
- [ ] `planLimits` escrito en `null` y contador correcto para cada PF en producción
- [ ] `count()` verificado contra el emulador

**PR 2**
- [ ] Pins de `planLimits` y `customExerciseUsage` en create y update
- [ ] Control negativo en rojo al sacar la cuota

**PR 3**
- [ ] Cinco puntos de entrada por el embudo
- [ ] Guards de anti-steering en verde sin excepciones nuevas
- [ ] Ningún `null` renderizado
- [ ] Gate incluido en el build que sale a las tiendas (el build 52 no lo tiene), publicado antes del encendido

**PR 4**
- [ ] Mail con `prefKey` y enfriamiento de 14 días

**PR 5 y encendido**
- [ ] Copy del Coach Hub (`pricing_screen.dart`, `plan_copy.dart`, `facturacion_tab.dart`)
- [ ] Legales publicados desde `docs/legal-limite-ejercicios-pf` y landing sincronizada
- [ ] Interruptor encendido **antes del alta del primer entrenador real**, barrido corrido y verificación del §4 completa

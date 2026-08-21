# Design: paywall-pr4-enforcement (Fase 7, PR4 — server-side promotion gate)

## Respuesta corta

Un solo helper transaccional (`syncTrainerLoad`) que es **dueño de su transacción**, recompone la carga desde `trainer_links` y decide. Dos callables lo invocan con una `promotion`; el trigger de reconciliación lo invoca con `promotion: null`. El error over-limit lleva un discriminador `reason` (`plan-limit` | `subscription-inactive`) para que el paywall no le venda un upsell a quien lo que necesita es regularizar el pago.

## Hallazgos previos al diseño (bloqueantes, no estaban en la propuesta)

| # | Hallazgo | Impacto |
|---|---|---|
| H1 | **Divergencia REAL TS↔Dart ya en producción.** `weighted-load.ts` deduplica y *después* filtra `blocked`; `weighted_load.dart` filtra `blocked` y *después* deduplica. Con `athleteId=a1` teniendo `{active, blocked}` + `{paused, entitled}`: TS → **0.0**, Dart → **0.5**. | El gate **sub-cuenta** → deja pasar por encima del límite. Hay que arreglar el TS (filtrar primero), no el Dart. Es la prueba viva de que los comentarios cruzados no alcanzan. |
| H2 | **Cuarto callsite.** `lib/features/coach/trainer_coach_view.dart:310-312` llama `resume()` (card del PF sobre un alumno pausado). La propuesta cuenta 3. | Slice 3 pasa de 1 a 2 migraciones de resume. |
| H3 | `template-publishing-rules.test.ts` **ya está** silenciosamente excluido del allow-list de `test:rules`. | Confirma el riesgo del regex; el fix es urgente, no preventivo. |
| H4 | `_RowActions` (`alumnos_screen.dart:692`) es `ConsumerWidget` sin estado → no puede tener flag `_busy`. | La migración exige convertirlo a `ConsumerStatefulWidget`. No es cosmético. |

## Decisiones

### D-1 — El helper es dueño de la transacción (no recibe `tx`)

```ts
// functions/src/subscriptions/promote-link.ts
export interface PromotionIntent {
  linkId: string;
  callerUid: string;
  expectedFromStatus: "pending" | "paused";
}

export interface SyncTrainerLoadInput {
  /** Requerido solo para reconciliación. En una promoción se RESUELVE del link. */
  trainerId?: string;
  /** null ⇒ reconciliación: recomputa y persiste weightedLoad, sin gate ni escritura de link. */
  promotion: PromotionIntent | null;
  nowMs?: number; // reloj inyectable (effectiveWeightLimit lo pide)
}

export interface SyncTrainerLoadResult {
  trainerId: string;
  weightedLoad: number; // valor committeado en users/{trainerId}
  limit: number;        // límite EFECTIVO aplicado
  promoted: boolean;    // false en reconciliación y en no-op idempotente
}

export async function syncTrainerLoad(
  app: admin.app.App,
  input: SyncTrainerLoadInput,
): Promise<SyncTrainerLoadResult>;
```

| Opción | Tradeoff | Decisión |
|---|---|---|
| `promoteLinkToActive(tx, {...})` recibiendo `tx` | Cada caller abre su transacción → duplica la disciplina de orden lectura/escritura y la política de retry. Es justo lo que queríamos compartir. | RECHAZADA |
| Helper dueño de la transacción, recibe `app` | Idéntico a `runDeleteAccount(app, …)` / `runAddAlias(app, …)` / `recomputeAthleteCount(app, trainerId)`. Un solo lugar donde vive el orden de lecturas. | **ADOPTADA** |

**Orden de lecturas (Firestore exige TODAS las lecturas antes de CUALQUIER escritura):**

```
1. tx.get(trainer_links/{linkId})            ← solo si promotion != null
2. validar: existe · trainerId == callerUid · status == expectedFromStatus
              · entitlement != 'blocked'      (throws → aborta antes de escribir)
3. Promise.all([ tx.get(users/{trainerId}),
                 tx.get(trainer_links where trainerId == T) ])
4. proyectar + comparar (puro, sin I/O)
   ── frontera lecturas/escrituras ──
5. tx.update(trainer_links/{linkId}, {status:'active', acceptedAt|pausedAt:…})
6. tx.set(users/{trainerId}, {weightedLoad}, {merge:true})
```

Lecturas secuenciales (1 antes de 3) son legales: la regla es *reads-before-writes*, no *reads-en-un-batch*. El paso 6 **siempre** se ejecuta, incluso en reconciliación: ese par read-write sobre `users/{trainerId}` **es el punto de serialización** que hace correcto el gate bajo concurrencia (no dependemos de la semántica de locks de queries).

**Predicado del gate** (proyección, no aritmética de delta):

```ts
const projected = computeWeightedLoad(
  links.map(l => l.id === linkId ? { ...l, status: "active" } : l));
if (projected > limit) throw new HttpsError("resource-exhausted", msg, details);
```

**Propagación de errores**: el helper lanza `HttpsError` directamente (mismo idioma que `runAddAlias`). El Admin SDK reintenta `runTransaction` solo ante `ABORTED`; un `HttpsError` corta el loop y sale tal cual. Los wrappers `onCall` no re-envuelven nada.

| Situación | Código | `details.reason` |
|---|---|---|
| sin auth / uid ausente | `unauthenticated` | — |
| `linkId` vacío | `invalid-argument` | — |
| link inexistente | `not-found` | — |
| `callerUid != link.trainerId` | `permission-denied` | — |
| status != esperado **y** != `active` | `failed-precondition` | `wrong-status` |
| status **ya** `active` | **éxito no-op** (`promoted:false`) | — |
| `entitlement == 'blocked'` | `failed-precondition` | `link-blocked` |
| proyección > límite | `resource-exhausted` | `plan-limit` \| `subscription-inactive` |

El no-op idempotente sobre `active` no es cortesía: cubre el retry del cliente tras un timeout cuyo write sí committeó, y desactiva el doble-tap (ver D-5).

### D-2 — Tier nominal vs entitlement efectivo: `reason` discriminador (RESUELVE la pregunta abierta)

| Opción | Trabajo de front | Corrección |
|---|---|---|
| A. Mandar tier **nominal** (D3 de la propuesta) | 0 | Un PF `plan2/paused` ve "PLAN A MEDIDA / CONTACTANOS". Mensaje equivocado en el peor momento. |
| B. Mandar tier **efectivo** | 0 | Peor: le dice "tu plan Free incluye 2" a alguien que **paga** plan2, y `nextTier` le ofrece plan1 (downgrade). |
| C. Mandar ambos | El diálogo decide sin señal explícita | Empuja la decisión al front sin contrato. |
| D. **`reason` discriminador + tier nominal + `subscriptionStatus`** | +1 estado en el diálogo (~80 líneas) | **ADOPTADA** |

Rationale: son **dos problemas de producto distintos**. `plan-limit` = "creciste, comprá más" (upsell). `subscription-inactive` = "tu derecho está suspendido, regularizá" (recupero). Cualquier valor de `tier` que elijamos produce una frase falsa en una de las dos ramas — la codificación vía tier es *lossy* por construcción.

**Derivación server-side** (pura, sobre funciones que ya existen; sin enum nuevo en el modelo):

```ts
const nominalLimit = TIER_WEIGHT_LIMITS[sub?.tier ?? "free"];
const reason = limit < nominalLimit ? "subscription-inactive" : "plan-limit";
```

Caso borde: `tier:'free'` → `nominalLimit === limit === 2` → siempre `plan-limit`. Correcto.

**Payload final**:

```ts
details: {
  reason: "plan-limit" | "subscription-inactive",
  tier: "free" | "plan1" | "plan2",   // NOMINAL (subscription.tier)
  subscriptionStatus: "active" | "pending" | "grace" | "paused" | "cancelled",
  limit: number,          // EFECTIVO (el que se aplicó)
  currentLoad: number,
  projectedLoad: number,
}
```

**Trabajo de front, dimensionado** (`plan_limit_paywall.dart`) — la firma se extiende **aditivamente**, no se rompe:

```dart
Future<void> showPlanLimitPaywall(
  BuildContext context, {
  required SubscriptionTier currentTier,
  PlanLimitReason reason = PlanLimitReason.planLimit,  // ← nuevo, con default
  SubscriptionStatus? subscriptionStatus,              // ← copy de la rama inactive
});
```

Los 3 callsites de `paywall_preview_screen.dart:47/55/63` siguen compilando sin tocarlos (parámetro nombrado con default). Dentro del diálogo, rama `subscriptionInactive`: título `TU SUSCRIPCIÓN NO ESTÁ ACTIVA`, cuerpo "Tu Plan X está {pausado|pendiente de pago}. Mientras tanto tenés el límite Free (2 alumnos).", caja nueva `_ReactivateBox` (hermana de `_UpsellBox`/`_CustomPlanBox`, sin precio-héroe), CTA `REGULARIZAR` → `/facturacion/planes`. **~80-100 líneas + 1 widget test.** Va en slice 2.

`nextTier` sigue anclado al tier **nominal**: en la rama `plan-limit`, nominal == efectivo por construcción del `reason`.

### D-3 — Paridad TS↔Dart: fixture golden compartido (no comentarios cruzados)

| Opción | Decisión |
|---|---|
| Comentarios cruzados (modelo `ADR-CXP-006` de `normalize()`) | RECHAZADA. `normalize()` es una transformación de string verificable a ojo; `computeWeightedLoad` tiene **semántica de conjuntos** (orden dedupe/filtro) donde la divergencia es invisible en una lectura lado a lado — H1 lo demuestra: sobrevivió a review. |
| Codegen desde un schema compartido | RECHAZADA. Sobre-ingeniería para 40 líneas. |
| **Fixture JSON único leído por ambas suites** | **ADOPTADA** |

Archivo: `functions/src/subscriptions/weighted-load-cases.json` (vive junto a la implementación autoritativa).

- TS: `weighted-load.test.ts` lo lee con `fs.readFileSync` + `JSON.parse` (evita tocar `resolveJsonModule` en tsconfig).
- Dart: `test/features/coach/domain/weighted_load_parity_test.dart` lo lee con `dart:io` + `jsonDecode` en la ruta relativa `functions/src/subscriptions/weighted-load-cases.json` (el cwd de `flutter test` es la raíz del paquete, que contiene `functions/`). Test Dart puro, sin binding de Flutter.

Forma del caso: `{ name, links: [{athleteId, status, entitlement?}], expected }`.

Tabla mínima a pinnear (12): vacío=0 · active=1 · paused=0.5 · pending=0 · terminated=0 · dedupe active+terminated=1 · dedupe active+paused=1 · blocked-active excluido=0 · **blocked-active + entitled-paused mismo atleta = 0.5 (el caso H1)** · 6a+2p=7.0 · 6a+1p=6.5 · 15 paused=7.5 (drift float).

Refuerzo: header en ambos archivos apuntando al fixture, nombre de test conteniendo `PARITY`, ítem de DoD en slice 1.

### D-4 — Capa cliente: el repository **suelta** `accept`/`resume`

| Opción | Consecuencia |
|---|---|
| Repository conserva `accept()`/`resume()` y por dentro llama a la CF | Los callsites igual tienen que cambiar (necesitan atrapar el error tipado y tienen el `BuildContext`), pero se pierde la red de seguridad "callsite olvidado = error de compilación". Lo peor de los dos mundos. RECHAZADA. |
| **Se borran del repository; los callsites usan el servicio vía provider** | Cualquier callsite olvidado **no compila**. El routing del error vive donde está el `BuildContext`. **ADOPTADA** |

- Servicio: `lib/features/coach/data/trainer_link_promotion_service.dart` (muta el dominio `coach/trainer_links`).
- Provider: agregado a `lib/features/coach_hub/application/cf_providers.dart`, reusando `cloudFunctionsProvider` (ADR-CXP-008) — un registro único y descubrible de todas las CF.

**Re-corte de D5 (mejora sobre la propuesta)**: el borrado del código muerto se hace **en la misma slice que migra sus callsites**, no en la slice 4.

- Slice 2 borra `TrainerLinkRepository.accept` + migra los 2 callsites de accept.
- Slice 3 borra `TrainerLinkRepository.resume` + migra los **3** callsites de resume (H2).
- Slice 4 queda **solo rules** (+ fix del regex + reescritura de comentarios) → la slice irreversible es la más chica y revisable.

Es seguro porque las rules todavía no están lockeadas cuando se mergean 2 y 3: un build viejo sigue funcionando por el path cliente. Costo: si hay que revertir las CFs después del release, se revierte el release del cliente (ya contemplado en el plan de rollback).

**Fallas tipadas** (Dart plano, NO freezed — Hard Constraint #3; espeja `AccountDeletionFailure`):

```dart
sealed class LinkPromotionFailure implements Exception {}
final class PlanLimitReached extends LinkPromotionFailure { … reason, tier, subscriptionStatus, limit, currentLoad, projectedLoad }
final class LinkPromotionFailure$Precondition extends LinkPromotionFailure { final String code; } // wrong-status | link-blocked | not-found | permission-denied
final class LinkPromotionFailure$Unavailable extends LinkPromotionFailure { final Object? cause; }
```

| `FirebaseFunctionsException.code` | Falla |
|---|---|
| `resource-exhausted` | `PlanLimitReached.fromDetails(e.details)` |
| `failed-precondition`, `not-found`, `permission-denied`, `invalid-argument` | `$Precondition(e.code)` |
| `unavailable`, `deadline-exceeded`, `internal`, `unauthenticated`, `unknown`, cualquier otro | `$Unavailable` |

**Gotcha a pinnear con test**: en Android `e.details` llega como `Map<Object?, Object?>` — el cast `as Map<String, dynamic>` explota. Se parsea campo por campo con fallbacks (`SubscriptionTierX.fromJson` ya cae a `free`; `reason` desconocido → `planLimit`; numéricos → 0). **El parseo nunca lanza**: preferimos mostrar el paywall con números degradados antes que convertir un over-limit en un snackbar genérico.

### D-5 — UX de falla y estados de loading (4 callsites)

| Callsite | Hoy | Después |
|---|---|---|
| `coach/presentation/trainer_dashboard_tab.dart:419` | `_busy` + `_showError` genérico | mantiene `_busy`; bifurca 3 ramas; siempre resetea `_busy` |
| `coach_hub/.../coach_hub_dashboard_screen.dart:1212` | `_busy` + snackbar l10n | ídem; +2 claves l10n |
| `coach_hub/.../alumnos_screen.dart:710` | **fire-and-forget**, sin loading ni catch, sin `BuildContext` | requiere `BuildContext` **y** convertir `_RowActions` a `ConsumerStatefulWidget` (H4) |
| `coach/trainer_coach_view.dart:310` | envuelto en `_confirmAndRun`, catch genérico | `_confirmAndRun` gana un hook `onFailure` (o se mueve el try/catch al llamador) |

Ramas en los 4: `PlanLimitReached` → `showPlanLimitPaywall(context, currentTier: f.tier, reason: f.reason, subscriptionStatus: f.subscriptionStatus)` · `$Precondition` → snackbar "Esta solicitud ya no está disponible." · `$Unavailable` → snackbar "No pudimos {aceptar|reanudar}. Revisá tu conexión y probá de nuevo."

Los 4 deben guardar `if (!mounted) return;` / `if (!context.mounted) return;` antes de mostrar nada.

**El flag de busy es correctitud, no pulido**: el round-trip a `southamerica-east1` con cold start puede tardar 3-8 s. Sin feedback, el PF vuelve a tapear → dos promociones concurrentes. El gate resuelve bien (una gana), pero la segunda devolvería `wrong-status`... salvo por el **no-op idempotente sobre `active`** de D-1, que la convierte en éxito silencioso. Las dos decisiones se sostienen mutuamente.

### D-6 — Testabilidad (Strict TDD: qué corre local vs qué exige emulador)

| Capa | Qué | Runner | ¿Emulador? |
|---|---|---|---|
| TS unit | `computeWeightedLoad` contra el fixture (12 casos), incluido el orden dedupe/filtro | `npm --prefix functions test` | **no** |
| TS unit | `promotionDenialReason(sub, limit)` — derivación `plan-limit` vs `subscription-inactive` | jest | **no** |
| TS unit | Escalera de precondiciones + frontera del gate (7.0 pasa, 7.5 bloquea) sobre **fake tx a mano** | jest | **no** |
| TS emulador | Orden reads-before-writes con Firestore real | `test:rules:emulator` | sí (CI) |
| TS emulador | **Concurrencia** | emulador | sí (CI) |
| Rules emulador | accept/resume/→pending `assertFails`; pause/terminate/decline/cancel/sharedWithTrainer `assertSucceeds` | `test:rules` | sí (CI) |
| Dart unit | Paridad contra el mismo fixture | `flutter test` | **no** |
| Dart unit | Mapeo `FirebaseFunctionsException` → sealed (mocktail sobre `FirebaseFunctions`/`HttpsCallable`), incluido `Map<Object?,Object?>` | `flutter test` | **no** |
| Dart widget | Los 4 callsites: paywall con upsell · paywall con copy inactive · snackbar de red · doble-tap bloqueado | `flutter test` + mocktail | **no** |

**El fake tx es la decisión clave** dado que Java 21 no corre local: un objeto a mano que implementa `get`/`update`/`set` y **lanza si se llama `get` después de un `update`/`set`**, replicando la regla real de Firestore. Así el invariante de orden de lecturas queda cubierto por un test **local**, y el test de emulador pasa a ser confirmación en vez de única red.

**Test de concurrencia — cómo se escribe** (emulador, CI, `--runInBand`, projectId `treino-rules-test`):

```ts
// seed: trainer plan1 (limit 7) · 6 links active · 2 links pending L1, L2
const r = await Promise.allSettled([
  syncTrainerLoad(app, { promotion: { linkId: "L1", callerUid: T, expectedFromStatus: "pending" } }),
  syncTrainerLoad(app, { promotion: { linkId: "L2", callerUid: T, expectedFromStatus: "pending" } }),
]);
expect(r.filter(x => x.status === "fulfilled")).toHaveLength(1);
expect((r.find(x => x.status === "rejected") as any).reason.code).toBe("resource-exhausted");
expect(await loadOf(T)).toBe(7);
```

**Por qué NO es flaky**: si hay contención, el Admin SDK reintenta al perdedor, que re-lee el 7.0 committeado y proyecta 8.0 > 7 → `resource-exhausted`. Si el emulador los serializa sin contención, el segundo lee 7.0 y falla igual. La aserción es **independiente del timing**.

`test:rules` (fix confirmado por H3): reemplazar la alternación de 15 nombres por el sufijo — `jest --forceExit "-rules\\.test\\.ts$"`. Verificar en la salida de jest que aparezcan **todas** las suites (hoy falta `template-publishing-rules`).

### D-7 — Runbook de deploy (`functions → release → lock de rules`)

| # | Paso | Verificación |
|---|---|---|
| 0 | `firebase deploy --only functions:linkLoadReconcile,functions:acceptTrainerLink,functions:resumeTrainerLink` — **filtros explícitos**: un `--only functions` pelado **poda** funciones ausentes de `index.ts` (el header de `index.ts` ya advierte esto por `notifyOnFriendship`) | `firebase functions:list` muestra las 3 en `southamerica-east1` |
| 1 | Smoke en build debug: aceptar 1 pending, reanudar 1 paused, pausar 1 active | `users/{T}.weightedLoad` se mueve en los 3 casos |
| 2 | Release de la app con slices 2+3 | Build en stores (iOS: 1-3 días de review) |
| 3 | **Gate de adopción** (abajo) | 7 días consecutivos |
| 4 | `firebase deploy --only firestore:rules` — guardar antes `git show HEAD~1:firestore.rules > /tmp/rules.prev` | — |
| 5 | Smoke post-deploy (<10 min): accept real por CF OK; write cliente directo a `status:'active'` → denegado | Monitorear tasa de `permission-denied` 24 h |
| R | Rollback: redeploy de `rules.prev` (un archivo, instantáneo) | Restaura accept/resume cliente |

**Criterio medible de "adopción suficiente" — sin instrumentación nueva**: el trigger de reconciliación de la slice 1 (`linkLoadReconcile`) fiirea en **todo** write a `trainer_links`. Se le agrega **una línea** que loguea `{event:'link-promoted-observed'}` cuando detecta `before.status !== 'active' && after.status === 'active'`. Cada callable loguea `{event:'link-promoted-cf'}`. En Cloud Logging:

```
adopción = 1 − (observed − cf) / observed     medido sobre ventana de 7 días
```

El delta `observed − cf` **es exactamente** el tráfico legacy del cliente. Gate: `adopción ≥ 95%` sostenido 7 días **y** ≥ 7 días desde el release del paso 2. Recién ahí, paso 4.

**Riesgo aceptado explícitamente**: no existe enforcement de versión mínima (VERIFICADO: no hay `minVersion` ni Remote Config en `lib/`). Tras el paso 4, los usuarios en builds anteriores al paso 2 pierden accept/resume **de forma permanente** hasta que actualicen. La métrica acota esa población a ≤5%. No crashea: el write cliente recibe `permission-denied` y cae en el snackbar genérico que ya existe.

## Flujo de datos

```
 [PF tapea ACEPTAR]
        │
  TrainerLinkPromotionService.accept(linkId)          ← lib/features/coach/data/
        │  httpsCallable('acceptTrainerLink')  (southamerica-east1, App Check)
        ▼
  acceptTrainerLink (onCall)  ──┐
  resumeTrainerLink (onCall)  ──┤  promotion: {linkId, callerUid, expectedFromStatus}
  linkLoadReconcile (trigger) ──┘  promotion: null
        │
        ▼
  syncTrainerLoad(app, input)          functions/src/subscriptions/promote-link.ts
        │  ┌── READS ──────────────────────────────────┐
        │  │ trainer_links/{linkId}                    │
        │  │ users/{trainerId}  ← PUNTO DE SERIALIZACIÓN
        │  │ trainer_links where trainerId == T        │
        │  └───────────────────────────────────────────┘
        │  computeWeightedLoad(proyección) vs effectiveWeightLimit(sub, now)
        │  ┌── WRITES ─────────────────────────────────┐
        │  │ trainer_links/{linkId}.status = 'active'  │
        │  │ users/{trainerId}.weightedLoad            │
        │  └───────────────────────────────────────────┘
        │
   over-limit ──► HttpsError('resource-exhausted', {reason, tier, subscriptionStatus, …})
        │
        ▼
   PlanLimitReached  ──►  showPlanLimitPaywall(reason: planLimit | subscriptionInactive)
```

## Cambios de archivos

| Archivo | Acción | Slice |
|---|---|---|
| `functions/src/subscriptions/promote-link.ts` | Crear — `syncTrainerLoad` + `promotionDenialReason` | 1 |
| `functions/src/subscriptions/link-load-reconcile.ts` | Crear — trigger `onDocumentWritten` + log `link-promoted-observed` | 1 |
| `functions/src/subscriptions/weighted-load.ts` | **Modificar — fix H1**: filtrar `blocked` ANTES de deduplicar | 1 |
| `functions/src/subscriptions/weighted-load-cases.json` | Crear — fixture golden compartido | 1 |
| `functions/src/__tests__/weighted-load.test.ts` | Modificar — leer el fixture | 1 |
| `functions/src/__tests__/promote-link.test.ts` | Crear — fake tx, precondiciones, frontera | 1 |
| `functions/src/__tests__/promote-link.emulator.test.ts` | Crear — orden de lecturas + concurrencia | 1 |
| `test/features/coach/domain/weighted_load_parity_test.dart` | Crear — paridad contra el fixture | 1 |
| `functions/src/subscriptions/accept-trainer-link.ts` | Crear — wrapper `onCall` | 2 |
| `functions/src/index.ts` | Modificar — 3 exports (1 en slice 1, 1 en 2, 1 en 3) | 1-3 |
| `lib/features/coach/data/trainer_link_promotion_service.dart` | Crear — servicio + `sealed LinkPromotionFailure` | 2 |
| `lib/features/coach_hub/application/cf_providers.dart` | Modificar — provider del servicio | 2 |
| `.../facturacion_planes/plan_limit_paywall.dart` | Modificar — `reason` + `_ReactivateBox` | 2 |
| `lib/features/coach/presentation/trainer_dashboard_tab.dart` | Modificar — callsite accept | 2 |
| `.../sections/dashboard/coach_hub_dashboard_screen.dart` | Modificar — callsite accept | 2 |
| `lib/features/coach/data/trainer_link_repository.dart` | Modificar — borrar `accept()` (s2), borrar `resume()` (s3) | 2-3 |
| `functions/src/subscriptions/resume-trainer-link.ts` | Crear — wrapper `onCall` | 3 |
| `.../sections/alumnos/alumnos_screen.dart` | Modificar — `_RowActions` → `ConsumerStatefulWidget` (H4) | 3 |
| `lib/features/coach/trainer_coach_view.dart` | Modificar — callsite resume (H2) | 3 |
| `firestore.rules` (531-533 + comentarios 494-530) | Modificar — cláusula partida, **única slice que la toca** | 4 |
| `functions/src/__tests__/trainer-links-paywall-rules.test.ts` | Modificar — flip + resume + pending | 4 |
| `functions/package.json` | Modificar — regex `test:rules` (H3) | 4 |

## Preguntas abiertas

- [ ] Copy exacto en español de la rama `subscription-inactive` (necesita revisión de producto antes de slice 2).
- [ ] ¿`grace` debe mostrar algún aviso? Hoy `grace` entrega el límite pago completo → nunca dispara `subscription-inactive`. Correcto por ADR-3; solo confirmar que es lo deseado.

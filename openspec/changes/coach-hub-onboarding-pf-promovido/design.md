# Design: Coach Hub — onboarding del PF promovido (#1331)

**Change**: `coach-hub-onboarding-pf-promovido` · **Inputs**: `proposal.md` (prevalece «Decisiones del usuario 2026-10-05»), `explore.md`
**Base leída**: worktree `strange-kirch-fcce9a` (`feat/coach-hub-onboarding-pf-promovido`, sobre `0547f3d6`).

## Technical Approach

Un predicado puro `hubOnboardingStage(UserProfile)` decide la ENTRADA y la SALIDA de un único
gate en `coachHubRedirect`. El gate va después del role gate y del gate del mail, y antes de
`/home/notifications` y de los aterrizajes (`coach_hub_router.dart:157-182`). Lleva a una sola
ruta top-level, `/completar-perfil`, fuera del shell. La pantalla dibuja el paso que dice el
predicado sobre el perfil vivo. Cada paso escribe con `UserRepository.update`, y nadie navega a
mano. La salida exige que el servidor haya confirmado la escritura. No cambian las rules, ni
`functions/`, ni MP.

## Evidencia que fija el diseño

| Hecho | Evidencia |
|---|---|
| Sin `includeMetadataChanges`, el ack del servidor sobre datos idénticos NO emite: `hasPendingWrites` se queda en `true` | `@firebase/firestore` `common-cc96d03b.node.mjs:36014-36025,36078-36093` (mismo core que el SDK web; **inferido** para la versión del Hub) |
| `watchHasPendingWrites` usa `snapshots()` a secas; `update` escribe `updatedAt` del cliente, o sea que el ack trae datos idénticos | `user_repository.dart:803-808`, `:614,648` |
| `RouterRefreshNotifier` no escucha los pending-writes | `router_refresh_notifier.dart:33-47` |
| El piso del cliente (13 años calendario) es más estricto que la rule (4745 días): el servidor sólo rechaza si el reloj del dispositivo está adelantado ≥3 días | `profile_setup_validators.dart:57,69-78`; `firestore.rules:250-254` |
| `users/{uid}` no tiene `hasOnly`. El dueño escribe nombre, términos, `trainer*` y consentimiento; `bornAtOk`/`bornAtKept` se evalúan en todo update | `firestore.rules:411-529` |
| `userPublicProfiles` sólo recibe `displayName`, `displayNameLowercase` y `uid`, y los tres están en el allowlist | `user_repository.dart:40,150-174`; `firestore.rules:1770-1781` |
| `trainerPublicProfiles` NO recibe `displayName` si el partial no trae un campo de PF | `user_repository.dart:58-81,218-232` |
| La promoción NO copia el nombre si `displayName` es null, que es justo el caso de la cuenta web | `scripts/promote_user_to_trainer.js:85-98` |
| La key de Places viene committeada; su único límite documentado es la API, no la app | `places_providers.dart:16-30`; `CONTRIBUTING.md:78-83` |
| `places-search.ts` sólo expone `resolveGymPlace` (Details por placeId), y no está exportado | `functions/src/places-search.ts:280`; `functions/src/index.ts:242-243` |
| Las callables SÍ se despliegan (≥15 `onCall`, p. ej. `auth/codigo-de-verificacion.ts`), así que la nota de DRS de `places_providers.dart:40-46` está **probablemente vieja (inferido)** | grep `onCall(` en `functions/src` |
| Precedente de una ubicación custom: `geohash5`, id `custom-<ms>` y el payload del guardado | `profile_edit_trainer_screen.dart:165-172,331-358`; `core/utils/geohash.dart:18` |
| El consentimiento de ubicación viaja en el mismo batch (`grantLocationConsent`) | `user_repository.dart:609-621`; `profile_edit_trainer_screen.dart:296-324` |
| Sólo 7 archivos de test pasan por el redirect del Hub (no 18) | grep `buildCoachHubRouter\|coachHubRedirect\|coachHubSessionResolvingProvider` en `test/` |

## Architecture Decisions

| Decisión | Elegido | Rechazado | Por qué |
|---|---|---|---|
| D1 Etapas | `enum HubOnboardingStage {age, identity, pf, done}` | `identity → age → terms → pf` | Un predicado puro no puede ver «términos solo si faltaba la identidad» DESPUÉS de escribir la identidad. Por eso los términos van en el MISMO paso y la misma escritura que el nombre. La edad va primero para no guardar el nombre ni el consentimiento de un menor de 13 (**pide confirmación**). |
| D2 Condiciones | `age`: `validateBornAt(bornAt, now:) != null`. `identity`: `displayName?.trim()` vacío. `pf`: `!trainerProfileComplete` | La identidad por `firstName`/`lastName` | Un PF legacy tiene `displayName` (el handle) y no tiene nombre ni apellido. Exigirlos bloquearía a todos el día del deploy y les pisaría el handle. Coincide con mobile (`router.dart:202`). |
| D3 Rutas | Una sola, `/completar-perfil`, con el paso derivado del perfil | Una ruta por etapa | El router sólo pregunta «¿estás en el gate o no?». Así no hay un mapeo etapa→ruta que se desincronice ni loops entre pasos. |
| D4 Salida | `done && !pendiente`, y `pendiente = p.isLoading \|\| (p.valueOrNull ?? false)`. El provider se lee SÓLO en el gate | Salida optimista | Precedente de mobile (`router.dart:254-268`). Si el servidor rechaza la escritura, el PF vuelve al paso SIN la pantalla que mostraba el error. El error del stream falla abierto. |
| D5 Señal de pendiente | `watchHasPendingWrites` → `snapshots(includeMetadataChanges: true)…distinct()`. En el Hub, `coachHubRouterRefreshProvider` = `Listenable.merge([routerRefreshNotifier, ping de pendiente])` | Sumar el listener a `RouterRefreshNotifier` | Sin el fix, el ack no emite. El merge en el Hub deja intacto el refresh de mobile, que comparte el notifier (`app.dart:92`). |
| D6 Espejo | `coachHubSessionResolvingProvider`: un trainer con etapa `!= done` cuenta como «saliendo del shell» y devuelve `true`. No mira el pendiente | Ignorarlo | Evita que se dibuje el dashboard o el `MobileBanner` debajo de la transición (doc de `:25-32`). Si mirara el pendiente, cualquier edición de un PF completo mostraría la vista de carga. |
| D7 Términos | Checkbox si `termsConsentRequiredProvider != false`. En el submit, `getFromServer` antes de estampar `termsAcceptedAt` y las dos versiones. Se extrae `terms_stamp.dart` y el notifier de mobile pasa a usarlo | Copiar el bloque | Es la escritura de evidencia (`profile_setup_notifier.dart:328-331,388-394`). Dos copias divergen en las versiones. |
| D8 Nombre público del PF | El partial del paso PF incluye `displayName: profile.displayName` | Tocar el repo por rol | Sin eso, `trainerPublicProfiles` nace sin `displayName` y el PF queda fuera de `orderBy('displayNameLowercase')`. Con el orden de D1, al llegar al paso PF el nombre ya existe. |
| D9 Ubicación | Places Text Search (New) DIRECTO desde el navegador. Servicio nuevo con fieldMask `places.displayName,places.formattedAddress,places.location`, `languageCode: 'es'`. Busca con botón o Enter, desde 3 caracteres. Key: `String.fromEnvironment('PLACES_WEB_CLIENT_KEY', defaultValue: <la key actual>)` | El proxy CF como camino principal | Que el endpoint acepte CORS es **inferido** (ver el paso 0 de la verificación). Fallback: una callable nueva `buscarLugarDelPf`, fuera de `subscriptions/`. `places-search.ts` no sirve como proxy porque no hace searchText. |
| D10 TrainerLocation | `custom`, `customLabel = displayName.text ?? formattedAddress`, lat/lng exactos, `geohash5`. Payload = el de `profile_edit_trainer_screen.dart:342-357` | Redondear coordenadas | Paridad con mobile (`location_precision.dart:34-44`). |
| D11 Consentimiento de ubicación | Hay ubicaciones y `trainerLocationConsentAt == null` ⇒ diálogo (las keys `profileEditTrainerConsentConfirm*` ya existen) ⇒ `update(..., grantLocationConsent: true)`. Si cancela, no se guarda y el form queda intacto | Un commit aparte | Mismo batch que mobile P1-d (`user_repository.dart:457-471`). |
| D12 Validadores PF | Se extraen `validarBio` (20-280) y `validarPrecio` (500-999999) a `coach_hub/domain/perfil_pf_validators.dart`, y los usan las dos cards | Montar las cards | Las cards guardan solas (`identidad_card.dart:68-92`, `especialidad_precio_card.dart:90-110`). |
| D13 UI | `ConstrainedBox(maxWidth: 560)` como `_VerifyMailEnElHub` (`:334-349`). `AuthInput`, `BornAtField`/`pickBornAt`, `TermsCheckbox`, `TreinoFilterChips` + `SpecialtyLabels`, `TreinoButton`. «Cerrar sesión» con un seam `cerrarSesion = FirebaseAuth.signOut` (`coach_hub_not_allowed_screen.dart:15,34`) | `AuthNotifier.signOut` | Cuelga en web. Sólo tokens; ninguna pantalla nueva entra a un allowlist. |

## Data Flow

    authState + profile ─→ coachHubRedirect: role → mail → [hubOnboardingStage]
         etapa != done ─→ /completar-perfil (la caja `?to=` NO se toca)
         en el gate y done && !pendiente ─→ /dashboard ─→ aterrizajes consumen `?to=`
    CompletarPerfilScreen ─watch→ etapa ─→ PasoEdad | PasoIdentidad | PasoPerfilPf
         └─ HubOnboardingController.guardar*() ─→ UserRepository.update (batch)
               users  (+ userPublicProfiles si hay displayName, + trainerPublicProfiles si hay campo PF)
    ack ─→ metadata ─→ ping de pendiente ─→ refresh ─→ salida

## Interfaces

```dart
enum HubOnboardingStage { age, identity, pf, done }
HubOnboardingStage hubOnboardingStage(UserProfile p, {DateTime? now});
const kCoachHubOnboardingRoute = '/completar-perfil';
// HubOnboardingController (Notifier<AsyncValue<void>>); uid = profile.uid
Future<void> guardarEdad(DateTime bornAt);
Future<void> guardarIdentidad({required String nombre, required String apellido, required bool aceptoTerminos});
Future<void> guardarPerfilPf(PerfilPfDraft d, {required bool otorgaConsentimientoUbicacion});
// LugarSearchService
Future<List<LugarCandidato>> buscar(String texto); // {label, direccion, lat, lng}
```

## File Changes

| Archivo | Acción | Líneas aprox. |
|---|---|---|
| `lib/features/coach_hub/domain/hub_onboarding_stage.dart` | Nuevo | +45 |
| `lib/features/coach_hub/domain/perfil_pf_validators.dart` (+ las 2 cards) | Nuevo / refactor | +40 / ±20 |
| `lib/features/coach_hub/application/hub_onboarding_controller.dart` | Nuevo | +160 |
| `lib/features/coach_hub/application/coach_hub_router_refresh.dart` | Nuevo (D5) | +40 |
| `lib/features/coach_hub/data/lugar_search_service.dart` + provider | Nuevo | +130 |
| `lib/features/coach_hub/presentation/onboarding/` (pantalla, 3 pasos, editor de ubicación) | Nuevo | +850 |
| `lib/app/coach_hub_router.dart`, `coach_hub_app.dart` | Gate, ruta, refresh, dartdoc :61-63 | +60 |
| `.../coach_hub_session_resolving_provider.dart` | Espejo D6 | +12 |
| `lib/features/profile/data/user_repository.dart` | D5 | +3 |
| `lib/features/profile_setup/application/terms_stamp.dart` + notifier | Extracción D7 | +40 / −15 |
| `lib/l10n/intl_{en,es,es_AR}.arb` + gen | ~35 keys | +210 (gen ≈ +250) |
| Tests (ver abajo) + `test/helpers/coach_hub_profiles.dart` | Nuevo / migración | ≈ +1300 |

Total ≈ 3.100 líneas, por encima de las ~1.300 del proposal. Va con `size:exception`.

## Testing Strategy (RED primero, en este orden)

| # | Test | Qué |
|---|---|---|
| 0 | `test/helpers/coach_hub_profiles.dart` | `trainerCompleto()` (`bornAt` 1990-01-01 UTC, bio de 20 o más, specialty, rate, online) y `trainerRecienPromovido()`. Migrar ANTES del gate: `coach_hub_router_redirect_test`, `_shell_test`, `_resolving_test`, `coach_hub_session_resolving_provider_test`, `coach_hub_scaffold_test`, `coach_hub_dashboard_in_shell_test` y `test/visual_gate/gate_harness.dart` (sólo corre en Linux: si no se migra, rompe goldens sin que se vea en Mac) |
| 1 | `hub_onboarding_stage_test` | Cada etapa y su orden. Handle legacy sin nombre ⇒ `done`. `displayName` en blanco ⇒ `identity`. `now` fijo, con un borde de cumpleaños barrido en día y TZ |
| 2 | `user_repository_test` | `snapshots(includeMetadataChanges: true)` con un DocumentReference mockeado |
| 3 | `coach_hub_router_redirect_test` (grupo nuevo, plantilla :671+) | Entrada por etapa desde `/login`, `/dashboard` y una ruta profunda. Quedarse en el gate. Salida bloqueada con pendiente en `true`/cargando y liberada en `false`. `?to=facturacion` sobrevive al gate. Gate del mail antes que el onboarding |
| 4 | `coach_hub_session_resolving_provider_test` | Trainer incompleto ⇒ `true`. Completo y con pendiente ⇒ `false` |
| 5 | `coach_hub_router_refresh_test` | Un cambio de pendiente notifica |
| 6 | `hub_onboarding_controller_test` (fake_cloud_firestore) | Identidad: `displayName` = «Nombre Apellido» en users y userPublicProfiles. Términos estampados sólo si el servidor dice null, sin pisar la evidencia. Moderación ⇒ error. PF: `displayName` en `trainerPublicProfiles`, consentimiento en el batch, rechazo de «sin modalidad» |
| 7 | `lugar_search_service_test` (MockClient) | Headers, fieldMask, mapeo de `location`, key vacía ⇒ config error, la key nunca en el mensaje |
| 8 | Widgets de la pantalla y los pasos | Dark + light, sign-out por seam, consentimiento cancelado ⇒ no escribe |
| 9 | Guards | Scans de tokens/botón/hover, paridad de ARB, `superficie_de_cobro_alumno_test` (sin launcher nuevo) |

**Controles negativos** (commitear antes de cada uno):
- sacar `!pendiente` ⇒ #3 en rojo;
- identidad por `firstName` ⇒ #1 en rojo;
- gate después de los aterrizajes ⇒ el test de `?to=` en rojo;
- sacar el espejo ⇒ #4 en rojo;
- sacar el `displayName` del partial PF ⇒ #6 en rojo;
- estampar siempre ⇒ #6 en rojo.

Cada uno se controla también: confirmar que la mutación entró (`git diff`). Las corridas son acotadas; `flutter analyze lib` scopeado.

## Migration / Rollout

No hay migración de datos. Deploy del Hub = 🚨 PROD.

Antes del deploy, la consola (la hace el usuario):
- confirmar que la key actual de Places tenga «Application restrictions: None»;
- **o bien** crear una key de navegador restringida a los referrers `https://app.gettreino.com/*`, `https://coach-treino-dev.web.app/*` y `http://localhost:*/*`, con la API Places (New), y pasarla como default de `PLACES_WEB_CLIENT_KEY`.

Si quiere, antes de abrir el gate, contar con una query de solo lectura cuántos trainers tienen un `bornAt` inválido o no cumplen `trainerProfileComplete`.

**Verificación manual** (cuentas del dueño, `app.gettreino.com` y después `coach-treino-dev.web.app`):

0. `curl -si -X OPTIONS https://places.googleapis.com/v1/places:searchText -H 'Origin: https://app.gettreino.com' -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type,x-goog-api-key,x-goog-fieldmask'` tiene que devolver `access-control-allow-origin`. Si no, se activa el fallback de D9 **antes** de mergear.
1. Cuenta web descartable promovida con el script ⇒ edad ⇒ nombre + términos ⇒ PF solo presencial con una dirección escrita ⇒ diálogo de consentimiento ⇒ dashboard. Entrando con `?to=facturacion`, cae en planes.
2. En la consola de Firestore: `users` con nombre, apellido, `displayName`, `bornAt`, `terms*` y `trainerLocationConsentAt`. `trainerPublicProfiles` con `displayName`, ubicación y geohash.
3. Mobile con esa cuenta: ningún gate, y aparece en el descubrimiento cerca de la dirección.
4. «Cerrar sesión» desde cada paso. Un PF completo nunca ve el gate.
5. Levantar la restricción de #1318.

## Open Questions

- [ ] **Orden y etapas (D1)**: `age → identity(+términos) → pf` en lugar del `identity → age → terms → pf` del proposal. El spec tiene que reflejarlo.
- [ ] **Key de Places (D9)**: ¿se reusa la actual o se crea una key restringida por referrer?
- [ ] **Hallazgo fuera de alcance**: `CuentaTab` cambia `displayName` sin llevarlo a `trainerPublicProfiles` (`cuenta_tab.dart:217-222` + `user_repository.dart:58-81`), así que la card del PF queda vieja. Va a una issue.
- [ ] **Hallazgo fuera de alcance (inferido)**: el gate de edad de mobile puede quedar trabado después de guardar, por la misma causa que D5 (`router.dart:264-268`). Va a una issue y se prueba en device.

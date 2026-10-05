# Exploration: onboarding en el Coach Hub para el PF promovido (#1331)

Fecha: 2026-10-05. Base: `origin/main` `3534b52f`, que ya incluye el login con Google y Apple de #1330.
Copia en engram: `sdd/coach-hub-onboarding-pf-promovido/explore`.

## Estado actual

### Router del Hub (`lib/app/coach_hub_router.dart`)

- La cadena de `coachHubRedirect` es esta:
  1. auth cargando: no redirige (L95);
  2. sin sesión: `/login` (L103);
  3. perfil cargando: no redirige (L116);
  4. sin perfil o con rol distinto de trainer: `/not-allowed` (L121-128);
  5. gate del mail (L157-166);
  6. traducción de `/home/notifications` (L182);
  7. aterrizajes (L216-247).
- **No hay ninguna condición de «perfil completo».** El código asume que el PF llega completo desde mobile (L61-63; `coach_hub_tour_gate.dart:20-23`).
- Las rutas top-level sin shell son `/login`, `/not-allowed` y `/verificar-mail` (L383-396). El precedente a copiar es `_VerifyMailEnElHub` (L334-349), que limita el ancho a 480 px.
- `coachHubSessionResolvingProvider` (`coach_hub_session_resolving_provider.dart:48-63`) espeja las esperas del redirect, así que una espera nueva hay que agregarla en los dos lugares.
- `RouterRefreshNotifier` (`router_refresh_notifier.dart:33-47`) escucha auth, perfil y `emailGateEnabled`. **No escucha los pending-writes.**

### Predicados de mobile (`lib/app/router.dart`)

- **Identidad:** `profile == null || displayName == null` → `/profile-setup` (L202-204). La salida simétrica está en L339-345.
- **Edad:** `validateBornAt(bornAt) != null` → `/birth-date` (L243-247). La salida exige que la escritura no esté pendiente (L264-266), y mientras está en el gate no lo saca nadie (L274).
- **Mail:** entrada y salida con la misma condición (L302-310).
- **PF incompleto:** `role == trainer && !trainerProfileComplete` → `/profile/edit-trainer?mode=onboarding` (L319-324).
- **El orden** es identidad → edad → mail → PF. La edad va antes porque es un requisito legal (L221-223).
- **El router mobile NO tiene un gate de `termsAcceptedAt`.** Solo `ProfileSetupFlow` lo estampa.
- **`trainerProfileComplete`** (`user_profile_trainer_completeness.dart:17-22`) exige bio, especialidad y tarifa, más ubicaciones o la opción online.

### ProfileSetup de mobile

- Tiene 5 pasos y todos son obligatorios:
  1. username y avatar;
  2. fecha de nacimiento;
  3. gym;
  4. experiencia y género;
  5. peso y altura.
- Validadores puros (`profile_setup_validators.dart`): username de 3 a 20 caracteres de `[a-zA-Z0-9_.]`; peso entre 20 y 300; altura entre 100 y 250; `kMinAgeYears = 13`.
- La unicidad del username se chequea solo en el cliente (`isDisplayNameTaken`), con un debounce y otra verificación en el submit.
- **Consentimiento:** `termsConsentRequiredProvider` devuelve `bool?`. Antes de estampar, el submit confirma contra el servidor (`profile_setup_notifier.dart:329-331`). Estampa `termsAcceptedAt`, `acceptedTermsVersion` y `acceptedPrivacyVersion` (L388-394).
- **Reusable en web:** los validadores, `ProfileSetupDraft`, `BornAtField`, `AuthInput` y `TermsCheckbox`.
- **No reusable en web:** `AvatarPickerButton` y el upload, que usan `dart:io`. La alternativa es `AvatarWebUploader`. Tampoco el paso del gym (Places y geolocator) ni el `ProfileSetupFlow` completo, que trae «Cancelar cuenta» y navega a `/welcome`.
- **Campos que ningún gate lee:** gym, experiencia, género, peso y altura. Además, `lib/features/coach_hub` no los usa (0 coincidencias).

### Edición de perfil del PF que ya existe en el Hub

- `IdentidadCard` (bio de 20 a 280 caracteres), `EspecialidadPrecioCard` (precio entre 500 y 999999) y `ConsultasCard`. En `CuentaTab` se editan nombre, apellido, teléfono y avatar, y escribe `displayName = "Nombre Apellido"`.
- **El Hub no edita la modalidad ni las ubicaciones** (`especialidad_precio_card.dart:15-18`). Por eso hoy un PF no puede completar `trainerProfileComplete` desde la web.
- **Conflicto:** en mobile, `displayName` es el `@handle` único; el Hub lo pisa con «Nombre Apellido».

### Rules

- **`users/{uid}`:** el dueño puede escribir `username`, `termsAcceptedAt` y las versiones. `bornAtOk` (L250-254) exige 13 años o más en TODO update, y `bornAtKept` impide borrar el campo.
- **`userPublicProfiles`:** tiene un allowlist con `hasOnly` (L1714-1781). Un campo nuevo que no esté en el allowlist hace que se deniegue TODO update.
- **`trainerPublicProfiles`:** exige `role == 'trainer'`.
- Ninguna rule garantiza que el handle sea único.

### Tests

- `coach_hub_router_redirect_test.dart:36-43`: `_trainerProfile()` solo tiene `displayName`. Un gate nuevo pone en rojo todo el redirect de trainer. Hay 20 `UserProfile(` en 18 tests del Hub, así que hace falta un fixture «trainer completo».
- El grupo de tests del gate del mail (L671 en adelante) sirve de plantilla.

## Enfoques

| # | Enfoque | Pros | Contras | Esfuerzo |
|---|---|---|---|---|
| a | Montar `ProfileSetupFlow` y `ProfileEditTrainerScreen` de mobile dentro del Hub | Casi nada de UI nueva | Usan `dart:io`, `/welcome`, «Cancelar cuenta», geolocator y un layout de teléfono; salen a un `/home` que en el Hub no existe | Medio, con mucho riesgo |
| b | **Stepper propio del Hub** en rutas top-level, con un predicado único `hubOnboardingStage(profile)` | Layout propio, sin `dart:io`, reusa lo que ya está testeado | Hay que hacer el editor de modalidad, resolver el avatar web y migrar los fixtures | Medio-Alto (~700-1000 líneas) |
| c | Gate legal mínimo (edad y términos) más un PF solo online | Lo más chico | No resuelve el nombre ni el handle, deja afuera al PF presencial y no cubre lo pedido | Bajo-Medio |

**Recomendación: b.**
- El gate va después del role gate y del gate del mail, y antes de los aterrizajes. Así se preserva `?to=`.
- Adentro, el orden es identidad → edad → términos → PF.
- Entrada y salida usan el mismo predicado.
- Tiene su propio «Cerrar sesión», porque fuera del shell no hay barra superior.

## Riesgos

- Si se exigen los términos a TODO PF sin `termsAcceptedAt`, el día del deploy quedan bloqueadas las cuentas legacy.
- El gate de edad le aparece a cualquier PF legacy que nunca cargó `bornAt`.
- Sin un editor de modalidad, el PF presencial no puede completar el perfil.
- Puede haber un loop de redirect si la entrada y la salida no salen de la misma función.
- Pending-writes: el refresh del router no los escucha. Es una inferencia sin probar.
- `displayName` es ambiguo: puede ser el handle o el nombre real.
- La unicidad del handle se controla solo en el cliente.
- Un campo nuevo en `userPublicProfiles` sin agregarlo al allowlist provoca permission-denied.
- El cambio rompe muchos tests del Hub por los fixtures.

## Preguntas abiertas

1. ¿Se le pide `bornAt` también al PF legacy que solo usa el Hub? Mobile ya se lo pide a todos.
2. ¿Los términos se le exigen a todo PF sin `termsAcceptedAt`, o solo a quien entra con la identidad incompleta?
3. ¿El PF carga los campos de alumno (gym, experiencia, género, peso, altura) o se omiten?
4. ¿El «nombre» es el `@handle` o el nombre y apellido reales? Si es el nombre real, ¿se pide además un handle?
5. ¿El PF puede declarar la modalidad presencial desde el Hub, o alcanza con online?
6. ¿El avatar es obligatorio, opcional o se deja para `/ajustes`?

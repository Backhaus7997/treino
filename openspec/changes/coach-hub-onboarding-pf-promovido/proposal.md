# Proposal: Coach Hub — onboarding del PF promovido (#1331)

**Change**: `coach-hub-onboarding-pf-promovido` · **Branch**: `feat/coach-hub-onboarding-pf-promovido`
**Date**: 2026-10-05 · **Entrega**: un PR con `size:exception`
**Inputs**: `explore.md` (esta carpeta) · engram `sdd/coach-hub-onboarding-pf-promovido/decisiones-usuario`

## Intent

Desde #1330 una cuenta nace en la web (popup Google/Apple → `createIfAbsent` athlete, sin
`displayName`, `bornAt` ni `termsAcceptedAt`). Si después se la promueve a trainer, el
Hub la deja pasar al dashboard sin identidad, sin edad, sin consentimiento y sin perfil
de PF: `coachHubRedirect` no tiene ningún gate de «perfil completo» (`coach_hub_router.dart:112-166`).
Éxito: un PF promovido completa en la web lo mínimo legal y profesional, sin abrir la
app, y se levanta la restricción operativa de #1318 («no promover perfiles incompletos»).

## Scope

### In Scope
- Predicado puro `hubOnboardingStage(UserProfile) → identity | age | terms | pf | done`.
  Lo usan la entrada Y la salida del gate.
- Gate en `coachHubRedirect`: después del role gate y del gate del mail, antes de los
  aterrizajes. Preserva `?to=`.
- Espera nueva espejada en `coachHubSessionResolvingProvider` si el diseño la necesita.
- Rutas top-level fuera del shell, ancho acotado (precedente `_VerifyMailEnElHub`), con
  «Cerrar sesión» propio (`FirebaseAuth.signOut` directo: `AuthService.signOut()` cuelga en web).
- Pasos: identidad (ver P1) → edad (`BornAtField`, `validateBornAt`) → términos
  (`TermsCheckbox`, confirmación contra el servidor como `profile_setup_notifier.dart:329-331`)
  → PF (bio, especialidad, tarifa, modalidad; ver P2).
- Reuso: validadores de `profile_setup`, `AuthInput`, reglas de `IdentidadCard` y
  `EspecialidadPrecioCard`.
- Fixture «trainer completo» compartido y migración de los ~18 tests del Hub
  (20 `UserProfile(`), empezando por `coach_hub_router_redirect_test.dart:36-43`.
- Strings en los 3 ARB. Light + dark.

### Out of Scope
- Campos de alumno: gym, experiencia, género, peso, altura (**decidido**).
- Avatar: opcional, queda en `/ajustes` (supuesto 3).
- Editor web de ubicaciones presenciales (geolocator + consentimiento de ubicación; ver P2).
- Unicidad del handle en el servidor y el conflicto previo `displayName` handle vs. nombre real.
- Rules, `functions/src/subscriptions/`, Mercado Pago.

## Capabilities

### New Capabilities
- None

### Modified Capabilities
- `coach-hub`: el redirect suma el gate de onboarding y las rutas del stepper.
- `trainer-profile-onboarding`: requisito equivalente a REQ-TPO-GATE-001..004 para el Hub,
  con su propio predicado (ver P2).

## Approach

Enfoque (b) de la exploración. El orden identidad → edad → términos → PF copia el de mobile
(`router.dart:202-324`; la edad antes por ser legal). Cada paso escribe con
`userRepository.update` y el predicado recalcula. Mientras el `bornAt` tenga una escritura
pendiente, la salida no se habilita (como `router.dart:264-266`). El refresh del router no
escucha pending-writes: el design decide cómo cubrirlo (inferido, sin probar).

## Supuestos a confirmar

1. **`bornAt` se pide a todo trainer sin fecha válida**, legacy incluido. Paridad con mobile;
   es legal. Costo: el PF legacy que nunca abrió la app desde el gate de edad lo ve en el Hub.
2. **Términos solo si la identidad está incompleta.** Exigirlos a todo trainer sin
   `termsAcceptedAt` bloquea a los legacy el día del deploy (mobile no tiene ese gate).
   Costo: un PF legacy sin consentimiento estampado sigue sin él.
3. **Avatar opcional, en `/ajustes`.** Evita `dart:io`; `AvatarWebUploader` ya existe ahí.

## Preguntas abiertas

**P1 — ¿Qué es «nombre»?**
- (A) `@handle` como mobile: unicidad solo en cliente, y `CuentaTab` lo pisa después igual.
- (B) **Recomendado:** nombre y apellido → `firstName`/`lastName`, con `displayName`
  derivado como `cuenta_tab.dart:211-221`. Es la convención del Hub y satisface el gate de
  identidad de mobile (`displayName != null`). El conflicto handle/nombre ya existe; issue aparte.

**P2 — ¿Modalidad presencial desde el Hub?** `trainerProfileComplete` pide ubicaciones u online.
- (A) Exigir `trainerProfileComplete` y ofrecer solo el switch online: el PF solo presencial
  queda bloqueado o tiene que mentir.
- (B) **Recomendado:** la etapa PF del Hub exige bio + especialidad + tarifa; el switch online
  es opcional. Consecuencia: el PF solo presencial entra al Hub pero no es descubrible hasta
  cargar ubicaciones en la app, cuyo gate (`router.dart:319-324`) se lo pide. Sin loop: son
  routers distintos.
- (C) Editor web de ubicaciones: geocoding + consentimiento. Otro SDD.

## Impacto en PFs existentes (inferido, sin consultar prod)

- Identidad y términos: ~0, porque mobile exige `displayName` y los legacy lo tienen.
- Edad: los PFs que no abrieron la app desde que existe el gate de edad.
- PF con (B): los que no abrieron la app desde REQ-TPO-GATE-001.
- Antes del deploy, el usuario puede contar esos casos con una query de solo lectura.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `lib/app/coach_hub_router.dart` | Modified | Gate + rutas |
| `lib/features/coach_hub/application/coach_hub_session_resolving_provider.dart` | Modified | Espejo de esperas, si aplica |
| `lib/features/coach_hub/domain/` (nuevo) | New | `hubOnboardingStage` |
| `lib/features/coach_hub/presentation/onboarding/` (nuevo) | New | Stepper y pasos |
| `lib/l10n/intl_{en,es,es_AR}.arb` | Modified | Strings |
| `test/` del Hub (~18 archivos) | Modified | Fixture trainer completo |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Loop de redirect | Med | Un solo predicado; tests de entrada y salida por etapa |
| Legacy bloqueados el día del deploy | Med | Supuesto 2 + conteo previo |
| Pending-write de `bornAt` saca del gate antes de tiempo | Med | Espera explícita; test |
| Fixtures rompen la suite del Hub | High | Fixture compartido, primera tarea |
| `hasOnly` de `userPublicProfiles` | Low | No hay campos nuevos; si aparece uno, se agrega al allowlist |

## Rollback Plan

Revertir el PR y redeployar el Hub anterior (🚨 PROD). Los datos escritos son campos que
ya existen (`firstName`, `lastName`, `displayName`, `bornAt`, `terms*`, `trainer*`), así que
no hace falta limpiar nada. Con el revert vuelve la restricción operativa de #1318.

## Dependencies

- #1330 mergeado (base `3534b52f`). Sin cambios de rules ni de consola.

## Success Criteria

- [ ] Una cuenta web nueva promovida a trainer recorre identidad → edad → términos → PF y
  llega al dashboard, o al `?to=` original.
- [ ] Un trainer completo nunca ve el stepper. Hay tests por etapa, de entrada y de salida.
- [ ] «Cerrar sesión» funciona desde cada paso.
- [ ] Suite del Hub en verde con el fixture nuevo; scans de tokens y de UI en verde.
- [ ] En prod, con una cuenta descartable del dueño: los mismos datos se ven en mobile y la
  app no le muestra ningún gate (salvo ubicaciones, si eligió solo presencial).
- [ ] Se levanta la restricción de #1318.

**Tamaño estimado:** ~900-1300 líneas (código + tests + fixture), PR con `size:exception`.

## Decisiones del usuario (2026-10-05) — PREVALECEN sobre lo anterior

1. **Modalidad:** «online» es opcional. **Se suma un editor web de ubicación presencial, sin geolocalización del dispositivo:**
   - el PF escribe la dirección del lugar donde trabaja;
   - se busca con Places Text Search (como `lib/features/gyms/data/places_text_search_service.dart`);
   - elige el resultado sugerido;
   - se guarda como `TrainerLocation` de tipo `custom`, con `customLabel` y con `lat`, `lng` y `geohash` del resultado.

   El texto libre sin coordenadas queda descartado: `TrainerLocation` exige `lat`, `lng` y `geohash` (`lib/features/coach/domain/trainer_location.dart:27-29`), y sin ellos el PF no aparece en el mapa ni en las búsquedas. Publicar una ubicación pide el consentimiento de ubicación también en la web (`trainerLocationConsentAt`, igual que mobile).

   **A verificar en design:**
   - si Places (New) acepta llamadas desde el navegador (CORS y key restringida por referrer);
   - si no las acepta, usar `functions/src/places-search.ts` como proxy;
   - cómo se calcula el geohash (reusar el helper de mobile).

   La etapa PF del onboarding pide bio, especialidad, tarifa y **al menos una modalidad**: online o una ubicación. Con eso, la salida del gate coincide con `trainerProfileComplete`.
2. **Nombre:** se piden nombre y apellido (`firstName`, `lastName`), y `displayName` se deriva como ya hace `cuenta_tab.dart:211-221`. No se pide `@handle`. El conflicto previo «`displayName` = handle en mobile» queda fuera de alcance y va a una issue aparte.
3. **Supuestos confirmados:**
   - `bornAt` es obligatorio para todo trainer que no tenga uno válido;
   - los términos se exigen solo cuando falta la identidad;
   - el avatar es opcional (se carga desde `/ajustes`).
4. **Se saltean los datos de alumno:** gym, experiencia, género, peso y altura.

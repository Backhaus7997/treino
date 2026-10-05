# Tasks: coach-hub-onboarding-pf-promovido (#1331 — onboarding del PF promovido en el Coach Hub)

Inputs: `proposal.md` (prevalece «Decisiones del usuario»), `specs/coach-hub/spec.md` (REQ-CHW-ONB-001..015),
`specs/trainer-profile-onboarding/spec.md`, `design.md` (D1..D13). Etapas CONFIRMADAS por el usuario:
`age → identity (nombre + apellido + términos, UNA escritura) → pf`. Strict TDD: RED (visto fallar por la
razón correcta) → GREEN → refactor. Si apply halla divergencia técnica gana design; de comportamiento, spec.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines (a mano) | ~+1.750 producción, ~+1.300 tests, ~+210 ARB, ~+30 docs = ~3.300 |
| Generated (no se revisa a mano) | `app_l10n*.dart` ≈ +250 |
| 400-line budget risk | High |
| Chained PRs recommended | No (decisión ya tomada) |
| Delivery strategy | exception-ok |
| Decision needed before apply: | No — un solo PR con `size:exception` |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: High

Verdict: muy por encima de 400, pero el usuario decidió un PR único con `size:exception`. Se mitiga con
9 batches obligatorios + 1 condicional + docs = work-unit commits revisables por separado.

### Decisiones pendientes del usuario antes de apply

- Key de Places (D9): ¿se reusa la actual (restricción «None») o se crea una restringida por referrer? No bloquea apply; bloquea el merge (task 0).

## Reglas para apply (todas las batches)

- Gates por batch: `flutter analyze` ACOTADO a los dirs tocados (NUNCA el completo: >600 s, cuelga al subagente); `dart format` SOLO en archivos tocados; correr SOLO tests afectados (+ `test/app/theme/tokens` y `test/app/guards` en batches de UI). Techos de ratchet: MEDIR corriendo el scan, no calcular.
- Tras editar ARB: `flutter gen-l10n`. Si se toca freezed: `build_runner` SIN `--build-filter`.
- Control negativo: commitear ANTES; revertir con commit/`git revert`, nunca `git checkout <archivo>`; confirmar con `git diff` que la mutación entró y que el control tiene su propio control (si no entra, el verde miente).
- Commits convencionales en español, sin Co-Authored-By ni atribución de IA; staging explícito por path (nunca `git add -A`).
- NO tocar `firestore.rules`, `functions/src/subscriptions/`, MP, `pubspec.yaml`, `RouterRefreshNotifier` (mobile). `terms_stamp.dart` sí toca el notifier de mobile (solo extracción).
- Trabajar en el worktree `strange-kirch-fcce9a`, con `cd` absoluto en cada comando.

## Orden y paralelismo

Secuencial por dependencia: B1 → B2 → B3. B4 (extracciones) es independiente de B2/B3 y puede ir
en paralelo a ellas, pero B5 depende de B1+B4, B6 de B5, B8 de B6+B7. B7 (Places) es independiente de
B5/B6. B9 (el gate) depende de TODO lo anterior: exige B2 (fixtures) y B3 (pendientes). B10 solo si falla
el CORS. B11 al final. Regla dura: el gate NO se mergea antes de la migración de fixtures ni del fix de pendientes.

---

## Task 0 — Pre-merge manual (USUARIO; no lo ejecuta apply)

- [ ] 0.1 `curl -si -X OPTIONS https://places.googleapis.com/v1/places:searchText -H 'Origin: https://app.gettreino.com' -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type,x-goog-api-key,x-goog-fieldmask'` debe devolver `access-control-allow-origin`. Si NO: activar B10 (callable `buscarLugarDelPf`) y registrar la excepción en design ANTES de aplicar B7/B8. (SCENARIO-055)

## Batch 1 — Predicado puro `hubOnboardingStage`

Commit: `feat(coach-hub): predicado puro de etapa del onboarding del PF`
Cubre: REQ-CHW-ONB-001; SCENARIO-001..006; SCENARIO-TPO-WEB-001.

- [x] 1.1 **RED** — `test/features/coach_hub/domain/hub_onboarding_stage_test.dart`: orden age→identity→pf→done (001), edad antes que identidad (002), legacy con handle sin términos = `done` (003), `bornAt` nulo = `age` + borde de cumpleaños 13 con `now` fijo barrido en día Y zona horaria (004), `displayName` en blanco = `identity` (005), sin campos de alumno/avatar = `done` (006), `done ⇒ trainerProfileComplete` (TPO-WEB-001). Rojo por símbolo inexistente.
- [x] 1.2 **GREEN** — `lib/features/coach_hub/domain/hub_onboarding_stage.dart`: `enum HubOnboardingStage {age, identity, pf, done}` + `hubOnboardingStage(UserProfile, {DateTime? now})` (sin Riverpod ni `DateTime.now()` oculto); usa `validateBornAt`, `displayName?.trim()`, `trainerProfileComplete`. No mira `firstName/lastName`, `termsAcceptedAt`.
- [x] 1.3 **GATE** — test del predicado; analyze acotado a `lib/features/coach_hub/domain test/features/coach_hub/domain`; format.
- [x] 1.4 **Control negativo** (tras commit): identidad por `firstName` en vez de `displayName` ⇒ 003 en rojo; revertir.

## Batch 2 — Fixture «trainer completo» y migración de la suite del Hub (ANTES del gate)

Commit: `test(coach-hub): fixture compartido de trainer completo para los tests del redirect`
Cubre: REQ-CHW-ONB-012; SCENARIO-049, 050. Depende de: B1.

- [x] 2.1 **RED** — `test/helpers/coach_hub_profiles_test.dart` (o dentro del test del predicado): `hubOnboardingStage(trainerCompleto()) == done` y `trainerProfileComplete(...)`; `trainerRecienPromovido()` ⇒ `age` (049). Rojo: helper inexistente.
- [x] 2.2 **GREEN** — `test/helpers/coach_hub_profiles.dart`: `trainerCompleto()` (`bornAt` 1990-01-01 UTC, bio ≥ 20, specialty, rate, online) y `trainerRecienPromovido()`.
- [x] 2.3 Migrar a `trainerCompleto()` SIN relajar aserciones: `test/app/coach_hub_router_redirect_test.dart` (`:36-43`), `coach_hub_router_shell_test.dart`, `coach_hub_router_resolving_test.dart`, `test/features/coach_hub/application/coach_hub_session_resolving_provider_test.dart`, `coach_hub_scaffold_test.dart`, `coach_hub_dashboard_in_shell_test.dart`, y `test/visual_gate/gate_harness.dart` (solo corre en Linux: migrar a ciegas y leer el diff dos veces; `rg 'UserProfile\(' test/visual_gate`).
- [x] 2.4 **GATE** — correr esos 6 tests (en verde antes y después, aún sin gate); analyze acotado a `test/helpers test/app test/features/coach_hub test/visual_gate`; format. Leer los paths del output.

## Batch 3 — Pendientes de escritura: repo + refresh listenable del Hub (ANTES del gate)

Commit: `fix(profile): watchHasPendingWrites emite el ack de metadatos`
Cubre: REQ-CHW-ONB-004 (parte repo/refresh); SCENARIO-019 (repo, refresh). Independiente de B2.

- [x] 3.1 **RED** — `test/features/profile/data/user_repository_test.dart`: `watchHasPendingWrites` llama `snapshots(includeMetadataChanges: true)` y emite `true` luego `false` ante ack sin cambio de datos; sin repetidos (`.distinct()`).
- [x] 3.2 **GREEN** — `lib/features/profile/data/user_repository.dart:803-808`: `includeMetadataChanges: true` + `.distinct()` (+3 líneas, único cambio del archivo).
- [x] 3.3 **RED** — `test/features/coach_hub/application/coach_hub_router_refresh_test.dart`: un cambio del ping de pendiente notifica a `coachHubRouterRefreshProvider`; `RouterRefreshNotifier` no se modificó.
- [x] 3.4 **GREEN** — `lib/features/coach_hub/application/coach_hub_router_refresh.dart`: `coachHubRouterRefreshProvider = Listenable.merge([routerRefreshNotifier, ping de pendiente])`. NO editar `router_refresh_notifier.dart`.
- [x] 3.5 **GATE** — ambos tests + tests existentes de `user_repository` y de `router_refresh_notifier`; analyze acotado; format.
- [x] 3.6 **Control negativo** (tras commit): quitar `includeMetadataChanges` ⇒ 3.1 en rojo; revertir.

## Batch 4 — Extracciones compartidas: validadores PF y `terms_stamp`

Commit: `refactor(coach-hub): validadores PF y estampado de términos compartidos`
Cubre: REQ-CHW-ONB-008 (helper), 009 (validadores); SCENARIO-062, 064. Independiente de B1-B3.

- [x] 4.1 **RED** — `test/features/coach_hub/domain/perfil_pf_validators_test.dart`: bio 19/281 falla, 20/280 pasa; precio 499/1000000 falla, 500/999999 pasa (064).
- [x] 4.2 **GREEN** — `lib/features/coach_hub/domain/perfil_pf_validators.dart` (`validarBio`, `validarPrecio`); `identidad_card.dart` y `especialidad_precio_card.dart` los usan (sin copiar constantes). Tests existentes de las cards en verde sin tocar.
- [x] 4.3 **RED** — `test/features/profile_setup/application/terms_stamp_test.dart`: el helper arma los TRES campos `termsAcceptedAt`, `acceptedTermsVersion`, `acceptedPrivacyVersion` con versiones vigentes (062).
- [x] 4.4 **GREEN** — `lib/features/profile_setup/application/terms_stamp.dart`; `profile_setup_notifier.dart` (`:328-331,388-394`) pasa a usarlo. Los tests del notifier siguen verdes SIN relajarse.
- [x] 4.5 **GATE** — validators, terms_stamp, tests de las dos cards, `profile_setup_notifier_test`; analyze acotado; format.

## Batch 5 — `HubOnboardingController` (escrituras)

Commit: `feat(coach-hub): controller del onboarding con escrituras atómicas`
Cubre: REQ-CHW-ONB-006/007/008/009/010 (escritura), 011; SCENARIO-024, 025, 027, 028 (U), 030, 031, 032, 038 (U), 039 (U), 041 (U), 042, 048, 061, 063. Depende de: B1, B4.

- [x] 5.1 **RED** — `test/features/coach_hub/application/hub_onboarding_controller_test.dart` (fake_cloud_firestore):
  - `guardarEdad`: solo `bornAt`, nada más; `permission-denied` ⇒ error visible, estado sin colgar (027, 028).
  - `guardarIdentidad`: UNA escritura con `firstName`, `lastName`, `displayName == 'Ana Pérez'`, 3 campos `terms*`; espeja `displayName` a `userPublicProfiles`; sin `username` ni `role` (024, 025, 030, 048).
  - términos: `getFromServer` null ⇒ estampa; ya con `termsAcceptedAt` T0/V0 ⇒ NO pisa y sí escribe nombre (031); `getFromServer` falla ⇒ no estampa + error (032); moderación rechaza ⇒ error, sin términos, etapa sigue (061).
  - `guardarPerfilPf`: partial incluye `displayName` ⇒ `trainerPublicProfiles/{uid}.displayName` (063); rechaza «sin modalidad»; ubicación `custom` con `lat/lng` exactos, `geohash5`, `gymId == null`, `trainerGeohashes` + espejo (038, 039); consentimiento en el MISMO batch con `grantLocationConsent: true` (041); consentimiento previo no se pisa (042).
- [x] 5.2 **GREEN** — `lib/features/coach_hub/application/hub_onboarding_controller.dart` (`Notifier<AsyncValue<void>>`; `guardarEdad`, `guardarIdentidad`, `guardarPerfilPf`; `displayName` derivado como `cuenta_tab.dart:211-221`; payload de ubicación = `profile_edit_trainer_screen.dart:342-357`, id `custom-<ms>`).
- [x] 5.3 **GATE** — test del controller; analyze acotado; format.
- [x] 5.4 **Controles negativos** (commit antes de cada uno; confirmar con `git diff`): (a) sacar `displayName` del partial PF ⇒ 063 en rojo; (b) estampar siempre ⇒ 031 en rojo; revertir cada uno.

## Batch 6 — Pantalla `/completar-perfil`: shell, sign-out, pasos edad e identidad, ARB

Commit: `feat(coach-hub): pantalla de completar perfil con pasos de edad e identidad`
Cubre: REQ-CHW-ONB-005/006/007/008/013 (parte), 011; SCENARIO-020 (W), 021, 022, 023, 026, 029, 045 (W), 047 (W), 051, 053. Depende de: B5.

- [x] 6.1 ARB — `lib/l10n/intl_en.arb`, `intl_es.arb`, `intl_es_AR.arb` (voseo): claves de título, edad, nombre, apellido, términos, continuar, errores y cerrar sesión (reusar `coachHubSignOutError`, `authInput*`/términos de mobile antes de crear). `flutter gen-l10n`.
- [x] 6.2 **RED** — `test/features/coach_hub/presentation/onboarding/completar_perfil_screen_test.dart` (light y dark, 360 y 1280 px): sin `CoachHubScaffold` y `maxWidth ≤ 560` (020); «Cerrar sesión» invoca el seam `cerrarSesion` y NO `AuthService/AuthNotifier.signOut`, error ⇒ `coachHubSignOutError` (021, en cada uno de los 3 pasos); sin «Cancelar cuenta» ni `/welcome` (022); identidad: campos vacíos/blancos no escriben (023), checkbox sin marcar deshabilita (029); edad: 12 años no escribe (026); un PF que solo falla edad ve únicamente `age` (045); ningún campo de alumno (047); sin overflow (053).
- [x] 6.3 **GREEN** — `lib/features/coach_hub/presentation/onboarding/`: `completar_perfil_screen.dart` (deriva el paso de `hubOnboardingStage` del perfil vivo, seam `cerrarSesion = FirebaseAuth.signOut`, `ConstrainedBox(maxWidth: 560)` como `_VerifyMailEnElHub`), `paso_edad.dart` (`BornAtField`/`pickBornAt`, `validateBornAt`), `paso_identidad.dart` (`AuthInput`, `TermsCheckbox` si `termsConsentRequiredProvider != false`), y el paso `pf` como placeholder hasta B8. Tokens, sin hex/Phosphor, espaciado fijo.
- [x] 6.4 **GATE** — test de la pantalla, paridad de ARB, scans (`no_raw_radius`, `no_raw_font_size`, `no_off_scale_spacing`, `no_material_button`, `no_animated_hover`, `snackbar_persist`) + `test/app/theme/tokens` + `test/app/guards`; techos MEDIDOS; analyze acotado; format.
- [x] 6.5 **Control negativo** (tras commit): `fontSize` crudo en un paso ⇒ scan rojo; revertir.

## Batch 7 — `LugarSearchService` (Places Text Search desde el navegador)

Commit: `feat(coach-hub): servicio de búsqueda de lugares para el PF`
Cubre: REQ-CHW-ONB-010 (servicio); SCENARIO-065. Independiente de B5/B6; condicionado a Task 0.

- [x] 7.1 **RED** — `test/features/coach_hub/data/lugar_search_service_test.dart` (`MockClient`): request con key, fieldMask `places.displayName,places.formattedAddress,places.location`, `languageCode: 'es'`; mapea `location.latitude/longitude` a `lat/lng`; busca solo desde 3 caracteres; key vacía ⇒ error de configuración y NINGÚN mensaje contiene la key (065).
- [x] 7.2 **GREEN** — `lib/features/coach_hub/data/lugar_search_service.dart` (`buscar(String) → List<LugarCandidato{label, direccion, lat, lng}>`, key por `String.fromEnvironment('PLACES_WEB_CLIENT_KEY', defaultValue: <key actual>)`) + provider. Sin paquetes nuevos; sin `geolocator`.
- [x] 7.3 **GATE** — test del servicio; analyze acotado; format.

## Batch 8 — Paso PF: bio, especialidad, tarifa, modalidad y editor de ubicación

Commit: `feat(coach-hub): paso de perfil profesional con ubicación presencial por dirección`
Cubre: REQ-CHW-ONB-009/010/011/013; SCENARIO-033, 034, 035, 036, 037, 038, 039, 040, 041, 042, 043, 044, 046, 047, 052, 053. Depende de: B6, B7.

- [ ] 8.1 ARB — claves del paso PF y del editor (búsqueda, resultados, vacío, error, reintentar, switch online, consentimiento: reusar `profileEditTrainerConsentConfirm*`) en los 3 ARB; `flutter gen-l10n`.
- [ ] 8.2 **RED** — `test/features/coach_hub/presentation/onboarding/paso_perfil_pf_test.dart` (light/dark; `LugarSearchService` doblado): rangos de bio y tarifa (033, 034); sin especialidad no guarda (035); sin modalidad no completa (036); solo online (037); solo presencial con consentimiento (038); dirección → resultados → elegir → guardar con `type == custom`, `lat/lng` idénticos, `geohash5` (039); texto libre sin elegir no habilita guardar (040); consentimiento: cancela ⇒ no escribe y form intacto, acepta ⇒ un batch (041), previo no se repite (042); error de Places visible con reintentar y online completa igual (044); solo falta PF ⇒ solo ese paso, precargado (046); sin campos de alumno (047).
- [ ] 8.3 **GREEN** — `presentation/onboarding/paso_perfil_pf.dart` (`TreinoFilterChips` + `SpecialtyLabels`, `validarBio`/`validarPrecio`) y `editor_ubicacion_pf.dart` (búsqueda por botón/Enter, ≥ 3 caracteres, elegir candidato, diálogo de consentimiento); reemplaza el placeholder de B6. Sin `geolocator`/`navigator.geolocation`.
- [ ] 8.4 **Scan** — SCENARIO-043: scan de texto sobre `presentation/onboarding/` y `data/lugar_search_service.dart` (sin `geolocator` ni `navigator.geolocation`).
- [ ] 8.5 **GATE** — test del paso, scan 043, paridad ARB, scans de UI + tokens + guards, `superficie_de_cobro_alumno_test` (sin launcher nuevo); techos MEDIDOS; analyze acotado; format.
- [ ] 8.6 **Control negativo** (tras commit): (a) importar `geolocator` en el editor ⇒ scan 043 rojo (el scan solo prueba ausencia de cadena, no que algo funcione); (b) habilitar guardar con texto sin elegir ⇒ 040 rojo; revertir.

## Batch 9 — El gate: `coachHubRedirect`, resolving provider, ruta y refresh

Commit: `feat(coach-hub): el Hub pide completar el perfil al PF promovido`
Cubre: REQ-CHW-ONB-002/003/004; SCENARIO-007..019, 045 (R), 046 (R), 020 (R). Depende de: B2, B3, B6, B8 (¡y de nada menos!).

- [ ] 9.1 **RED** — `test/app/coach_hub_router_redirect_test.dart` (grupo nuevo, plantilla `:671+`): entrada por etapa desde `/login`, `/dashboard` y ruta profunda, y `/completar-perfil` ⇒ `null` (007); salida con `done` + pendiente `false` ⇒ `/dashboard` (008); cambio de etapa dentro del gate ⇒ `null` (009); barrido etapas × pendiente × rutas a punto fijo en ≤ 2 saltos (010); atleta y sin doc ⇒ `/not-allowed` (011); mail antes que onboarding (012); `?to=facturacion` sobrevive (013); trainer `done` idéntico al previo (014); sin sesión ⇒ `/login` (015); loading no redirige (016, 017); salida bloqueada con pendiente cargando/`true`, error del stream falla abierto (019).
- [ ] 9.2 **RED** — `coach_hub_session_resolving_provider_test.dart`: etapa ≠ `done` ⇒ `true`; `done` con pendiente `true` ⇒ `false`; loading ⇒ `true` (016, 017, 018).
- [ ] 9.3 **GREEN** — `lib/app/coach_hub_router.dart`: `kCoachHubOnboardingRoute = '/completar-perfil'`, ruta top-level fuera del shell, gate DESPUÉS del role gate y del mail, ANTES de `/home/notifications` y los aterrizajes (`:157-182`), salida `done && !pendiente` (`pendiente = isLoading || valueOrNull ?? false`, leído solo en el gate). `lib/app/coach_hub_app.dart`: usar `coachHubRouterRefreshProvider`.
- [ ] 9.4 **GREEN** — `coach_hub_session_resolving_provider.dart`: espejo D6 (+12 líneas, sin mirar el pendiente).
- [ ] 9.5 **GATE** — redirect, shell, resolving, scaffold, dashboard_in_shell, tests de B1-B8 y `test/app/guards`; analyze acotado a `lib/app lib/features/coach_hub test/app test/features/coach_hub`; format.
- [ ] 9.6 **Controles negativos** (commit antes de cada uno; confirmar con `git diff`): (a) quitar `!pendiente` ⇒ 019 rojo; (b) gate después de los aterrizajes ⇒ 013 rojo; (c) quitar el espejo D6 ⇒ 018 rojo; revertir cada uno. Control del control: confirmar que cada mutación efectivamente entró.

## Batch 10 — CONDICIONAL: callable `buscarLugarDelPf` (SOLO si falla el CORS de Task 0)

Commit: `feat(functions): callable buscarLugarDelPf como proxy de Places`
Condición: Task 0 sin `access-control-allow-origin`. Si no, OMITIR. Registrar antes la excepción en design (REQ-CHW-ONB-014).

- [ ] 10.1 **RED** — test de la callable en `functions/` (con emulador; `npm ci` en `functions/` primero en el worktree).
- [ ] 10.2 **GREEN** — nueva callable en `functions/src/` FUERA de `functions/src/subscriptions/`, exportada en `functions/src/index.ts`; NO reutilizar `places-search.ts` como proxy (solo hace Details por placeId). Key en secret, nunca en mensajes.
- [ ] 10.3 Adaptar `lugar_search_service.dart` (+ test del 7.1) para llamar la callable en vez del endpoint directo.
- [ ] 10.4 **GATE** — jest de la callable, test del servicio; `tsc` acotado.

## Batch 11 — Docs, diff y verificación (§11.2)

Commit: `docs(coach-hub): el PF puede llegar incompleto desde la web`
Cubre: REQ-CHW-ONB-014; SCENARIO-050, 054.

- [ ] 11.1 Corregir comentario de `lib/app/coach_hub_router.dart:61-63` y dartdoc de `lib/features/coach_hub/application/coach_hub_tour_gate.dart:20-23`: hoy afirman «PF llega completo desde mobile»; ahora lo gatea `hubOnboardingStage` (citar design D1/D3, AGENTS.md §11.1: sin afirmaciones sin evidencia). `rg -i "llega completo"` en `lib/`.
- [ ] 11.2 **Verificación de diff (054)** — `git diff --stat main...HEAD`: NO aparecen `firestore.rules`, `functions/src/subscriptions/`, `pubspec.yaml`, `router_refresh_notifier.dart`; cualquier cambio en `functions/` justificado en design (solo B10).
- [ ] 11.3 **GATE final de apply** — `flutter analyze` acotado a los dirs tocados, `dart format --set-exit-if-changed` solo sobre los archivos tocados, corrida agregada SOLO de los tests de B1-B9 + `test/features/coach_hub/` + `test/app/coach_hub_router*` + `test/app/theme/tokens` + `test/app/guards` (no la suite completa de ~40 min). Leer los paths absolutos del output.
- [ ] 11.4 Los goldens del gate visual (`test/visual_gate`, solo Linux) no se verifican en Mac: dejar anotado que el CI es el que corre; si cae, bajar el artefacto y leer la imagen.

---

## Para el USUARIO (no lo ejecuta apply)

### Antes del merge

- [ ] Task 0.1: curl OPTIONS de CORS (arriba). Si falla ⇒ B10 antes de mergear.
- [ ] Decisión de la key de Places (D9): confirmar que la actual tenga «Application restrictions: None», O crear una key de navegador restringida a `https://app.gettreino.com/*`, `https://coach-treino-dev.web.app/*` y `http://localhost:*/*` con la API Places (New) y pasarla como default de `PLACES_WEB_CLIENT_KEY`. Console: Google Cloud → Credentials.
- [ ] Conteo de solo lectura de PFs legacy que verán el gate: `bornAt` nulo o inválido (etapa `age`) y `!trainerProfileComplete` (etapa `pf`), ANTES del deploy (supuestos 1 y 2 del proposal).
- [ ] Merge con `size:exception` en el PR.

### Verificación manual en producción (SOLO cuentas descartables del dueño; `treino-dev` es PROD)

Primero `app.gettreino.com`, luego `coach-treino-dev.web.app`:

1. Cuenta web descartable promovida con `scripts/promote_user_to_trainer.js` ⇒ edad ⇒ nombre + términos ⇒ PF solo presencial con una dirección escrita ⇒ diálogo de consentimiento ⇒ dashboard. Con `?to=facturacion` cae en planes (056).
2. Firestore Console: `users` con `firstName`, `lastName`, `displayName`, `bornAt`, `terms*`, bio, especialidad, tarifa, `trainerLocationConsentAt`; `trainerPublicProfiles` con `displayName`, ubicación y geohash (056).
3. Mobile con esa cuenta (mismo debug build en los dos dispositivos): ningún gate; aparece en el descubrimiento cerca de la dirección (057, 058).
4. Búsqueda real de dirección sin errores CORS ni de key en la consola del navegador (055).
5. «Cerrar sesión» desde cada paso (se cierra y vuelve a `/login`, sin colgarse) (060).
6. PF legacy del dueño: llega al dashboard sin stepper (o solo `age` si le falta `bornAt`) (059).
7. Levantar la restricción operativa de #1318 («no promover perfiles incompletos»).
8. Rollback: revertir el PR y redeployar el Hub anterior (los campos escritos ya existen; no hay limpieza).

## Trazabilidad REQ → Batch

| REQ | SCENARIOs | Batch |
|---|---|---|
| REQ-CHW-ONB-001 | 001-006 | B1 |
| REQ-CHW-ONB-002 | 007-010 | B9 |
| REQ-CHW-ONB-003 | 011-015 | B9 |
| REQ-CHW-ONB-004 | 016-019 | B3, B9 |
| REQ-CHW-ONB-005 | 020-022 | B6, B9 |
| REQ-CHW-ONB-006 | 023-025, 061 | B5, B6 |
| REQ-CHW-ONB-007 | 026-028 | B5, B6 |
| REQ-CHW-ONB-008 | 029-032, 062 | B4, B5, B6 |
| REQ-CHW-ONB-009 | 033-035, 063, 064 | B4, B5, B8 |
| REQ-CHW-ONB-010 | 036-044, 065 | B5, B7, B8, (B10) |
| REQ-CHW-ONB-011 | 045-048 | B6, B8, B9 |
| REQ-CHW-ONB-012 | 049-050 | B2 |
| REQ-CHW-ONB-013 | 051-053 | B6, B8 |
| REQ-CHW-ONB-014 | 054 | B11 |
| REQ-CHW-ONB-015 | 055-060 | Task 0, usuario |

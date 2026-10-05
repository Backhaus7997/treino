# Delta for Coach Hub (onboarding del PF promovido, #1331)

**Change**: coach-hub-onboarding-pf-promovido
**Capability**: `coach-hub` (`openspec/specs/coach-hub/spec.md`)
**Proposal ref**: `openspec/changes/coach-hub-onboarding-pf-promovido/proposal.md`
(la sección «Decisiones del usuario (2026-10-05) — PREVALECEN» manda sobre el resto)
**Numbering**: `REQ-CHW-ONB-NNN` y `SCENARIO-CHW-ONB-NNN` (familia nueva; no choca con
`REQ-CHW-AUTH-*` del login ni con `REQ-CHW-ROUTER-*`). Los REQ `REQ-CHW-ROUTER-002`
(rutas fuera del shell) y `REQ-PAGW-ROLE-001` (gate de rol trainer) siguen vigentes.
Este delta SÍ modifica el router (a diferencia de `REQ-CHW-AUTH-009`).

**Alineado con `design.md` (D1..D13)**, que prevalece en lo técnico: etapas
`age → identity(+términos) → pf`, ruta única `/completar-perfil`, salida condicionada a
escritura confirmada, `displayName` en el partial PF, Places directo desde el navegador.

**Convención de fuentes de test** (rutas orientativas; el nombre final lo fija design/tasks):
P = test unitario del predicado puro `hubOnboardingStage`
(`test/features/coach_hub/domain/`), R = `test/app/coach_hub_router_redirect_test.dart`,
V = test de `coachHubSessionResolvingProvider`, W = tests de widget de las pantallas del
onboarding (`test/features/coach_hub/presentation/onboarding/`), U = tests de escritura
contra el repositorio (fake Firestore), G = scans/guards existentes de tokens y UI,
L = gate de paridad de ARB, M = verificación manual.

## Terminología

- **Etapa** = resultado de `hubOnboardingStage(UserProfile)`:
  `age | identity | pf | done` (en ese orden; design D1). No existe una etapa `terms`
  separada: los términos viajan en el paso `identity`.
- **Identidad completa** = `displayName?.trim()` no vacío (paridad con el gate de mobile,
  `router.dart:202`). Es lo que los PFs legacy ya tienen (su handle). NO se deriva de
  `firstName`/`lastName`, que un legacy no tiene (design D2).
- **Ruta única** = `/completar-perfil` (`kCoachHubOnboardingRoute`); la pantalla dibuja el
  paso que corresponde a la etapa viva del perfil (design D3).
- **Perfil PF completo** = `trainerProfileComplete(profile)` (bio, especialidad, tarifa, y
  ubicaciones u online; `user_profile_trainer_completeness.dart:17-22`). No se redefine.

## ADDED Requirements

### Requirement: REQ-CHW-ONB-001 — Predicado puro de etapa

Debe existir `enum HubOnboardingStage { age, identity, pf, done }` y
`hubOnboardingStage(UserProfile, {DateTime? now}) → HubOnboardingStage` en
`lib/features/coach_hub/domain/hub_onboarding_stage.dart`, función pura (sin Riverpod, sin
`DateTime.now()` oculto, sin I/O; `now` entra por parámetro). Evalúa en este orden y devuelve
la PRIMERA etapa que falle:

1. `age`: `validateBornAt(profile.bornAt, now:) != null` (validador existente de
   `profile_setup_validators.dart`, 13 años o más; `kMinAgeYears = 13`). Va primero para no
   guardar nombre ni consentimiento de un menor de 13.
2. `identity`: `profile.displayName?.trim()` vacío o nulo.
3. `pf`: `!trainerProfileComplete(profile)`.
4. `done`: ninguna de las anteriores.

No existe etapa `terms`: el paso `identity` pide nombre, apellido y términos, y los guarda en
UNA sola escritura (REQ-CHW-ONB-006). Los términos MUST NOT exigirse nunca a un perfil con
`displayName` presente, tenga o no `termsAcceptedAt` (los legacy no se bloquean). El
predicado MUST NOT mirar `firstName`/`lastName`, `termsAcceptedAt`, campos de alumno (gym,
experiencia, género, peso, altura), avatar ni `@handle`.

#### Scenario: SCENARIO-CHW-ONB-001 — Orden de etapas (P)

- GIVEN un trainer sin `bornAt` y sin `displayName`
- THEN la etapa es `age`
- AND con `bornAt` válido (≥13) y `displayName` ausente la etapa es `identity`
- AND con `displayName` presente y `!trainerProfileComplete` la etapa es `pf`
- AND con `trainerProfileComplete` la etapa es `done`

#### Scenario: SCENARIO-CHW-ONB-002 — Edad es legal y va antes que la identidad (P)

- GIVEN un perfil con `displayName` ausente y `bornAt` nulo (o de menos de 13 años)
- THEN la etapa es `age`, no `identity`

#### Scenario: SCENARIO-CHW-ONB-003 — Legacy con handle y sin términos es `done` (P)

- GIVEN un trainer legacy con `displayName` (handle), sin `firstName`/`lastName`, `bornAt` válido, perfil PF completo y `termsAcceptedAt == null`
- THEN la etapa es `done` (nunca `identity`)
- AND con `displayName` presente y perfil PF incompleto la etapa es `pf`

#### Scenario: SCENARIO-CHW-ONB-004 — Legacy sin `bornAt` ve la etapa de edad (P)

- GIVEN un trainer con `displayName`, perfil PF completo y `bornAt == null`
- THEN la etapa es `age`
- AND con `now` fijo, el borde de cumpleaños (13 años menos un día vs. 13 años exactos) se barre en día y en zona horaria: el primero sigue en `age`, el segundo pasa

#### Scenario: SCENARIO-CHW-ONB-005 — `displayName` en blanco cuenta como ausente (P)

- GIVEN `displayName: '   '`, `bornAt` válido
- THEN la etapa es `identity`

#### Scenario: SCENARIO-CHW-ONB-006 — No se piden campos de alumno ni avatar ni handle (P)

- GIVEN un trainer con perfil completo según `trainerProfileComplete`, sin gym, experiencia, género, peso, altura ni avatar
- THEN la etapa es `done`

### Requirement: REQ-CHW-ONB-002 — Entrada y salida del gate salen del mismo predicado

Existe UNA sola ruta top-level, `/completar-perfil`; el router solo pregunta «¿estás en el
gate o no?» y la pantalla deriva el paso del perfil vivo (no hay ruta por etapa ni mapeo
etapa→ruta). `coachHubRedirect` MUST decidir la ENTRADA (trainer con etapa ≠ `done` fuera de
`/completar-perfil` → `/completar-perfil`; en el gate se queda, incluso al cambiar de
etapa) y la SALIDA (trainer en `/completar-perfil` con etapa `done` Y sin escritura pendiente
→ `/dashboard`, de donde los aterrizajes consumen `?to=`) llamando a `hubOnboardingStage`, sin
duplicar condiciones. No MUST haber ciclos de redirect para ninguna combinación de etapa y
ruta de partida. El error del stream de pendientes MUST fallar abierto (no encierra al PF).

#### Scenario: SCENARIO-CHW-ONB-007 — Entrada por etapa (R)

- GIVEN un trainer autenticado con perfil resuelto y etapa `E` ∈ {age, identity, pf}
- WHEN `coachHubRedirect` evalúa `/login`, `/dashboard` y una ruta profunda
- THEN el destino es `/completar-perfil`
- AND la evaluación de `/completar-perfil` devuelve `null` (sin ciclo)

#### Scenario: SCENARIO-CHW-ONB-008 — Salida con etapa `done` (R)

- GIVEN un trainer con etapa `done` y sin escritura pendiente parado en `/completar-perfil`
- WHEN `coachHubRedirect` evalúa esa ruta
- THEN sale a `/dashboard` (o el aterrizaje de REQ-CHW-ONB-003)

#### Scenario: SCENARIO-CHW-ONB-009 — Cambio de etapa dentro del gate no navega (R)

- GIVEN un trainer en `/completar-perfil` cuya etapa pasa de `age` a `identity`
- WHEN `coachHubRedirect` evalúa
- THEN devuelve `null` (se queda en la misma ruta; cambia el paso dibujado, no la URL)

#### Scenario: SCENARIO-CHW-ONB-010 — Barrido sin ciclos (R)

- GIVEN el producto cartesiano de las 4 etapas × (pendiente / no pendiente) × todas las rutas conocidas del Hub
- WHEN se aplica `coachHubRedirect` repetidamente hasta punto fijo
- THEN en todos los casos termina en ≤ 2 saltos

### Requirement: REQ-CHW-ONB-003 — Posición del gate, `?to=` y aterrizajes

El gate MUST evaluarse DESPUÉS del gate de rol trainer y del gate del mail de verificación,
y ANTES de la traducción de `/home/notifications` y de los aterrizajes. El destino original
solicitado (`?to=`) MUST preservarse a través del onboarding (el gate no toca esa caja):
tras completar, el usuario llega al `?to=` original (o al aterrizaje por defecto si no había). El gate MUST NOT correr
para usuarios sin sesión, ni para no-trainers (atleta o sin `users/{uid}` siguen en
`/not-allowed`), ni para trainers con etapa `done`: para esos tres casos el comportamiento
actual del router MUST permanecer idéntico.

#### Scenario: SCENARIO-CHW-ONB-011 — El rol gana al onboarding (R)

- GIVEN un atleta con perfil incompleto
- WHEN `coachHubRedirect` evalúa cualquier ruta
- THEN el destino es `/not-allowed` (no una ruta del onboarding)
- AND sin `users/{uid}` (perfil resuelto, doc ausente) también `/not-allowed`

#### Scenario: SCENARIO-CHW-ONB-012 — El mail gana al onboarding (R)

- GIVEN un trainer con etapa ≠ `done` y mail sin verificar con el gate del mail activo
- WHEN `coachHubRedirect` evalúa `/dashboard`
- THEN el destino es `/verificar-mail`
- AND una vez verificado el mail el destino pasa a ser `/completar-perfil`

#### Scenario: SCENARIO-CHW-ONB-013 — `?to=` se preserva y se respeta al salir (R)

- GIVEN un trainer en etapa `age` que entró con `?to=facturacion`
- WHEN recorre el onboarding hasta `done` y la escritura queda confirmada
- THEN el destino final es el de `?to=facturacion` (planes)
- AND el gate no modificó ni consumió la caja `?to=`

#### Scenario: SCENARIO-CHW-ONB-014 — Trainer completo no ve el stepper (R)

- GIVEN un trainer con etapa `done`
- WHEN `coachHubRedirect` evalúa `/dashboard`, `/agenda`, `/pagos` y `/ajustes`
- THEN el resultado es idéntico al previo al cambio (los tests existentes del redirect pasan con el fixture «trainer completo»)

#### Scenario: SCENARIO-CHW-ONB-015 — Sin sesión no entra al gate (R)

- GIVEN un usuario sin sesión
- WHEN `coachHubRedirect` evalúa una ruta protegida
- THEN el destino es `/login`

### Requirement: REQ-CHW-ONB-004 — Espera mientras auth o perfil no están resueltos

Mientras auth esté cargando, o el perfil esté cargando (`AsyncLoading`), el gate MUST NOT
redirigir: ni a una ruta del onboarding ni fuera de ella. Un `UserProfile` ausente por
«no cargó todavía» MUST NOT interpretarse como etapa `identity`. La condición de espera
MUST espejarse en `coachHubSessionResolvingProvider` (devuelve `true` en los mismos casos
en que el redirect espera) y, además, MUST devolver `true` para un trainer con etapa ≠
`done` (está «saliendo del shell»; evita dibujar el dashboard o el `MobileBanner` debajo de
la transición). El provider MUST NOT mirar el pendiente: un trainer completo con una
escritura pendiente (p. ej. editando) MUST dar `false`.

**Salida del gate = `done` Y última escritura confirmada por el servidor** (precedente
`router.dart:254-268`). La señal de pendiente es `UserRepository.watchHasPendingWrites`
con `snapshots(includeMetadataChanges: true)` y `.distinct()` (sin eso el ack del servidor
sobre datos idénticos no emite y `hasPendingWrites` queda en `true`). El pendiente se lee
SOLO en el gate; está pendiente si el stream está cargando o su valor es `true`. El Hub
tiene su propio refresh listenable (`coachHubRouterRefreshProvider` =
`Listenable.merge([routerRefreshNotifier, ping de pendiente])`); `RouterRefreshNotifier`
de mobile MUST NOT modificarse. Si el servidor rechaza la escritura, el PF vuelve al paso.

#### Scenario: SCENARIO-CHW-ONB-016 — Perfil cargando no redirige (R, V)

- GIVEN auth resuelto con sesión y `userProfileProvider` en `AsyncLoading`
- WHEN `coachHubRedirect` evalúa cualquier ruta
- THEN devuelve `null`
- AND `coachHubSessionResolvingProvider` es `true`

#### Scenario: SCENARIO-CHW-ONB-017 — Auth cargando no redirige (R, V)

- GIVEN auth en `AsyncLoading`
- THEN `coachHubRedirect` devuelve `null` y el provider de resolución es `true`

#### Scenario: SCENARIO-CHW-ONB-018 — Etapa pendiente cuenta como resolviendo; completo no (V)

- GIVEN auth y perfil resueltos
- THEN con un trainer de etapa ≠ `done` `coachHubSessionResolvingProvider` es `true`
- AND con un trainer `done` es `false`, incluso con una escritura pendiente en `true`

#### Scenario: SCENARIO-CHW-ONB-019 — Salida bloqueada mientras la escritura está pendiente (R, repo, refresh)

- GIVEN un trainer en `/completar-perfil` cuya etapa ya es `done` y el stream de pendientes está cargando o en `true`
- WHEN `coachHubRedirect` evalúa
- THEN devuelve `null` (se queda en el gate)
- AND con el pendiente en `false` devuelve `/dashboard`
- AND (repo) `watchHasPendingWrites` llama `snapshots(includeMetadataChanges: true)` y emite `true` y luego `false` ante el ack de metadatos sin cambio de datos (`.distinct()` evita repetidos)
- AND (refresh) un cambio del ping de pendiente notifica a `coachHubRouterRefreshProvider`, y `RouterRefreshNotifier` queda sin modificar
- AND si el stream de pendientes da error, el gate falla abierto (permite salir)

### Requirement: REQ-CHW-ONB-005 — Ruta del onboarding: top-level, ancho acotado, «Cerrar sesión» propio

La ruta `/completar-perfil` MUST ser top-level, fuera del shell (`CoachHubScaffold` no se
construye), con contenido de ancho acotado (`ConstrainedBox(maxWidth: 560)`, precedente
`_VerifyMailEnElHub`), en
light y dark. Cada paso MUST ofrecer «Cerrar sesión» que cierre la sesión de Firebase Auth
**directamente** (`FirebaseAuth.signOut`) y MUST NOT pasar por `AuthService.signOut()` ni
`AuthNotifier.signOut()` (cuelgan en web). El efecto MUST estar detrás de un seam
inyectable (mismo patrón que `CoachHubNotAllowedScreen.cerrarSesion`). Si falla, se muestra
el error existente `coachHubSignOutError`. Ningún paso MUST ofrecer «Cancelar cuenta» ni
navegar a `/welcome`.

#### Scenario: SCENARIO-CHW-ONB-020 — Sin shell (W, R)

- GIVEN un trainer en cualquier paso
- WHEN se bombea el árbol
- THEN no se encuentra `CoachHubScaffold`
- AND el contenido está acotado a ≤ 560 px de ancho en una ventana ancha

#### Scenario: SCENARIO-CHW-ONB-021 — Cerrar sesión directo desde cada paso (W)

- GIVEN `CompletarPerfilScreen` en cada uno de sus tres pasos (`age`, `identity`, `pf`) con un `cerrarSesion` doblado
- WHEN el usuario toca «Cerrar sesión»
- THEN se invoca `cerrarSesion`
- AND NO se invoca `AuthService.signOut()` ni `AuthNotifier.signOut()`
- AND si `cerrarSesion` lanza, se muestra `coachHubSignOutError`

#### Scenario: SCENARIO-CHW-ONB-022 — Sin salidas indebidas (W)

- GIVEN cada pantalla del onboarding
- THEN no existe «Cancelar cuenta» ni navegación a `/welcome`

### Requirement: REQ-CHW-ONB-006 — Paso de identidad: nombre, apellido y términos en una sola escritura

El paso `identity` MUST pedir `firstName` y `lastName` (ambos obligatorios, validados tras
`trim()`; reutilizando `AuthInput` y los validadores de `profile_setup` donde aplique) y,
cuando corresponda (REQ-CHW-ONB-008), el checkbox de términos. MUST NOT pedir `@handle` ni
`username`. `displayName` se deriva como `cuenta_tab.dart:211-221` (`"Nombre Apellido"`).
Nombre, apellido, `displayName` y el estampado de términos MUST ir en UNA sola escritura
(`guardarIdentidad`, vía `UserRepository.update`, un batch), que además espeja `displayName`
a `userPublicProfiles`. Con campos inválidos o vacíos, o con el checkbox requerido sin
marcar, MUST NOT escribir. Si la moderación rechaza el nombre, MUST mostrarse el error y no
avanzar.

#### Scenario: SCENARIO-CHW-ONB-023 — Validación de nombre y apellido (W)

- GIVEN el paso `identity` con ambos campos vacíos o solo espacios
- WHEN el usuario intenta continuar
- THEN no hay escritura y se muestra el error del campo
- AND con ambos válidos (y términos marcados si se piden) se habilita continuar

#### Scenario: SCENARIO-CHW-ONB-024 — Una escritura con nombres, `displayName` y términos (W, U)

- GIVEN el paso `identity` con «Ana» y «Pérez» válidos y el checkbox marcado
- WHEN continúa
- THEN en una sola escritura quedan `firstName == 'Ana'`, `lastName == 'Pérez'`, `displayName == 'Ana Pérez'` y los tres campos `terms*`
- AND `userPublicProfiles` recibe `displayName`
- AND la etapa pasa a `pf`
- AND no se escribió `username` ni `role`

#### Scenario: SCENARIO-CHW-ONB-025 — Derivación de `displayName` igual que `CuentaTab` (U)

- GIVEN nombres «Ana» y «Pérez»
- THEN `displayName == 'Ana Pérez'` con el mismo criterio que `cuenta_tab.dart:211-221`

#### Scenario: SCENARIO-CHW-ONB-061 — Moderación rechaza el nombre (U, W)

- GIVEN `UserRepository.update` falla por moderación del nombre
- WHEN confirma
- THEN se muestra el error, no se estampan términos y la etapa sigue en `identity`

### Requirement: REQ-CHW-ONB-007 — Paso de edad

El paso `age` MUST usar `BornAtField` y validar con el `validateBornAt` existente
(mínimo 13 años). Con fecha inválida o menor de 13 MUST NOT escribir. Al confirmar, MUST
escribir `bornAt` por `userRepository.update`. Las rules (`bornAtOk`, `bornAtKept`) siguen
siendo la última defensa; un `permission-denied` MUST mostrar un error al usuario y MUST NOT
dejar el paso en estado de carga.

#### Scenario: SCENARIO-CHW-ONB-026 — Menor de 13 no escribe (W)

- GIVEN el paso `age` con una fecha que da 12 años
- WHEN intenta continuar
- THEN se muestra el error de edad mínima y no hay escritura

#### Scenario: SCENARIO-CHW-ONB-027 — Fecha válida escribe `bornAt` (W, U)

- GIVEN una fecha que da ≥ 13 años
- WHEN confirma
- THEN `bornAt` queda escrito y no se tocó ningún otro campo (en particular, ni nombre ni términos)
- AND la etapa se recalcula a `identity` (o la que siga)
- AND la salida del gate espera la confirmación del servidor (REQ-CHW-ONB-004)

#### Scenario: SCENARIO-CHW-ONB-028 — Fallo de escritura es visible (W)

- GIVEN `userRepository.update` lanza (p. ej. `permission-denied`)
- WHEN confirma
- THEN se muestra un error, el botón vuelve a habilitarse y no se avanza

### Requirement: REQ-CHW-ONB-008 — Términos dentro del paso de identidad: estampa tras confirmar contra el servidor

El paso `identity` MUST mostrar `TermsCheckbox` (con los links a los textos legales
vigentes) si `termsConsentRequiredProvider != false`, y MUST NOT permitir continuar sin
marcarlo mientras se muestre. En el submit MUST: (1) consultar el servidor
(`getFromServer`, como `profile_setup_notifier.dart:328-331`) si el consentimiento sigue
siendo requerido; (2) solo si lo es, estampar los TRES campos `termsAcceptedAt`,
`acceptedTermsVersion` y `acceptedPrivacyVersion` con las versiones vigentes, en la MISMA
escritura que el nombre (REQ-CHW-ONB-006). El estampado MUST vivir en un helper compartido
(`terms_stamp.dart`) que también usa el notifier de mobile (una sola copia de la escritura de
evidencia). Si el resultado de la consulta es desconocido (error) MUST NOT estampar y MUST
informar el error. Si el servidor ya tiene `termsAcceptedAt`, MUST NOT sobrescribir
ninguno de los tres campos (la evidencia existente no se pisa), pero SÍ escribir nombre y
`displayName`.

#### Scenario: SCENARIO-CHW-ONB-029 — Sin marcar no avanza (W)

- GIVEN el paso `identity` con el checkbox sin marcar
- THEN continuar está deshabilitado y no hay escritura

#### Scenario: SCENARIO-CHW-ONB-030 — Estampa los tres campos (W, U)

- GIVEN checkbox marcado y el servidor sin `termsAcceptedAt`
- WHEN confirma
- THEN se escriben `termsAcceptedAt`, `acceptedTermsVersion` y `acceptedPrivacyVersion` (versiones vigentes), junto con nombre, apellido y `displayName`, en la misma escritura
- AND la etapa pasa a `pf`

#### Scenario: SCENARIO-CHW-ONB-031 — No sobrescribe evidencia existente (U)

- GIVEN el servidor ya tiene `termsAcceptedAt` T0 con versiones V0 (y `displayName` ausente)
- WHEN el usuario confirma el paso
- THEN `termsAcceptedAt`, `acceptedTermsVersion` y `acceptedPrivacyVersion` conservan T0/V0
- AND nombre, apellido y `displayName` quedan escritos

#### Scenario: SCENARIO-CHW-ONB-032 — Confirmación contra servidor desconocida no estampa (W, U)

- GIVEN la consulta al servidor (`getFromServer`) falla
- WHEN confirma
- THEN no se escribe ningún campo `terms*` y se muestra el error

#### Scenario: SCENARIO-CHW-ONB-062 — Helper de estampado compartido con mobile (U)

- GIVEN `terms_stamp.dart`
- THEN lo usan tanto el controller del Hub como `profile_setup_notifier` de mobile, y los tests existentes del notifier de mobile siguen en verde sin relajarse

### Requirement: REQ-CHW-ONB-009 — Paso PF: bio, especialidad y tarifa

El paso `pf` MUST pedir bio, especialidad y tarifa con los mismos rangos y mensajes de
validación que las tarjetas del Hub (`IdentidadCard`: bio de 20 a 280 caracteres;
`EspecialidadPrecioCard`: tarifa entera entre 500 y 999999; especialidad de la lista vigente),
reusando sus reglas: `validarBio` y `validarPrecio` se extraen a
`coach_hub/domain/perfil_pf_validators.dart` y las usan tanto las dos cards como el
onboarding (no se copian constantes; los tests existentes de las cards siguen en verde). Con
cualquier campo inválido MUST NOT guardar. Las escrituras MUST producir los mismos campos
que mobile (`trainerBio`, `trainerSpecialty`, `trainerRate` o los nombres vigentes del
modelo) para que mobile no muestre ningún gate al mismo usuario. El partial de
`guardarPerfilPf` MUST incluir `displayName: profile.displayName`: sin eso
`trainerPublicProfiles` nace sin `displayName` (el repo solo lo copia si el partial trae un
campo de PF) y el PF queda fuera de `orderBy('displayNameLowercase')`.

#### Scenario: SCENARIO-CHW-ONB-033 — Rangos de bio (W)

- GIVEN bio de 19 y de 281 caracteres
- THEN ambas muestran error; 20 y 280 son válidas

#### Scenario: SCENARIO-CHW-ONB-034 — Rangos de tarifa (W)

- GIVEN tarifa 499 y 1000000
- THEN ambas muestran error; 500 y 999999 son válidas

#### Scenario: SCENARIO-CHW-ONB-035 — Especialidad obligatoria (W)

- GIVEN ninguna especialidad elegida
- THEN no se puede guardar

#### Scenario: SCENARIO-CHW-ONB-063 — El guardado PF publica `displayName` en el espejo (U)

- GIVEN un trainer recién promovido que completó `identity` (`displayName == 'Ana Pérez'`) y guarda el paso `pf`
- WHEN termina `guardarPerfilPf`
- THEN `trainerPublicProfiles/{uid}` contiene `displayName == 'Ana Pérez'` (y `displayNameLowercase` si el repo lo deriva)
- AND quitar `displayName` del partial pone este test en rojo (control negativo)

#### Scenario: SCENARIO-CHW-ONB-064 — Validadores compartidos (P)

- GIVEN `validarBio` y `validarPrecio` en `perfil_pf_validators.dart`
- THEN bio 19/281 y precio 499/1000000 fallan; 20/280 y 500/999999 pasan
- AND `IdentidadCard`, `EspecialidadPrecioCard` y el onboarding usan esas mismas funciones

### Requirement: REQ-CHW-ONB-010 — Modalidad: online o al menos una ubicación presencial

La etapa `pf` MUST exigir al menos una modalidad: «online» activado, O al menos una
`TrainerLocation`. «Online» MUST ser opcional siempre que haya una ubicación. Con ninguna
modalidad MUST NOT permitir completar la etapa (la salida coincide con
`trainerProfileComplete`).

**Editor de ubicación presencial (web, sin geolocalización del dispositivo):**

1. El PF escribe la dirección del lugar donde trabaja.
2. La app MUST buscarla con Places Text Search (New) llamado DIRECTO desde el navegador, a
   través de un servicio nuevo (`LugarSearchService.buscar(texto) → List<LugarCandidato>`
   con `{label, direccion, lat, lng}`), con fieldMask
   `places.displayName,places.formattedAddress,places.location` y `languageCode: 'es'`. La
   búsqueda se dispara con botón o Enter y desde 3 caracteres. La key sale de
   `String.fromEnvironment('PLACES_WEB_CLIENT_KEY', defaultValue: <key actual>)`; key vacía
   ⇒ error de configuración, y la key MUST NOT aparecer nunca en un mensaje de error.
   `functions/src/places-search.ts` NO sirve como proxy (solo expone `resolveGymPlace`, por
   placeId). Que el endpoint acepte CORS desde el navegador es **inferido** y se verifica a
   mano ANTES de mergear (SCENARIO-CHW-ONB-055); si no lo acepta, el fallback es una callable
   nueva (`buscarLugarDelPf`, fuera de `functions/src/subscriptions/`).
3. El PF elige un resultado; el texto libre sin coordenadas MUST NOT poder guardarse.
4. Se guarda como `TrainerLocation` de tipo `custom` con `customLabel = displayName.text ??
   formattedAddress` del resultado (no vacío), `lat` y `lng` EXACTOS (sin redondear),
   `geohash` calculado con `geohash5`, `gymId == null`, con el mismo payload que arma
   `profile_edit_trainer_screen.dart` para una ubicación custom.
5. El camino de escritura MUST dejar consistentes `trainerLocations`, `trainerGeohashes` y el espejo
   `trainerPublicProfiles` igual que el flujo de mobile.
6. **Consentimiento de ubicación:** si hay ubicaciones que guardar y
   `trainerLocationConsentAt == null`, MUST mostrarse un diálogo de consentimiento (se
   reusan las keys `profileEditTrainerConsentConfirm*`). Si acepta, el guardado MUST ir por
   `update(..., grantLocationConsent: true)` en el MISMO batch (no un commit aparte). Si
   cancela, NO se guarda nada y el formulario queda intacto. Si ya hay
   `trainerLocationConsentAt`, MUST NOT volver a pedirse ni sobrescribirse.
7. El editor MUST NOT importar ni invocar geolocalización del dispositivo (`geolocator`,
   `navigator.geolocation`) y MUST NOT agregar paquetes a `pubspec.yaml`.
8. Resultados vacíos, error de red o de configuración MUST mostrar un estado de error/vacío visible y no
   bloquear la salida cuando la modalidad online está activa.

#### Scenario: SCENARIO-CHW-ONB-036 — Sin modalidad no completa (P, W)

- GIVEN bio, especialidad y tarifa válidas, online apagado y sin ubicaciones
- THEN `trainerProfileComplete` es falso, la etapa sigue en `pf` y el paso no permite finalizar

#### Scenario: SCENARIO-CHW-ONB-037 — Solo online completa (P, W)

- GIVEN bio, especialidad y tarifa válidas, online activado, sin ubicaciones
- THEN la etapa pasa a `done`

#### Scenario: SCENARIO-CHW-ONB-038 — Solo presencial completa (P, W)

- GIVEN bio, especialidad y tarifa válidas, online apagado, una ubicación guardada y consentimiento otorgado
- THEN la etapa pasa a `done`

#### Scenario: SCENARIO-CHW-ONB-039 — Dirección → resultados → elegir → guardar (W, U)

- GIVEN el servicio de Places doblado que devuelve dos resultados con lat/lng para «Av. Siempreviva 742»
- WHEN el PF escribe la dirección, busca, elige el primer resultado y confirma
- THEN se escribe una `TrainerLocation` con `type == custom`, `customLabel == displayName.text` del resultado (o `formattedAddress` si falta), `lat`/`lng` idénticos a los del resultado, `geohash == geohash5(lat, lng)` y `gymId == null`
- AND `trainerGeohashes` y el espejo público reflejan la ubicación

#### Scenario: SCENARIO-CHW-ONB-065 — Servicio de búsqueda (MockClient)

- GIVEN `LugarSearchService` con un `MockClient`
- WHEN busca «Av. Siempreviva 742»
- THEN el request lleva la key, el fieldMask `places.displayName,places.formattedAddress,places.location` y `languageCode: 'es'`
- AND mapea `location.latitude/longitude` a `lat/lng`
- AND con key vacía lanza el error de configuración y ningún mensaje contiene la key
- AND busca solo desde 3 caracteres

#### Scenario: SCENARIO-CHW-ONB-040 — Texto libre sin elegir no guarda (W)

- GIVEN texto escrito pero ningún resultado elegido (o búsqueda sin resultados)
- THEN no se habilita guardar y no hay escritura

#### Scenario: SCENARIO-CHW-ONB-041 — Consentimiento requerido antes de publicar (W, U)

- GIVEN `trainerLocationConsentAt == null` y un resultado elegido
- WHEN guarda el paso `pf` y se muestra el diálogo de consentimiento
- THEN si cancela, no se escribe nada y el formulario queda intacto
- AND si acepta, UN solo batch escribe la ubicación y estampa `trainerLocationConsentAt` y `trainerLocationConsentPromptedAt` (`grantLocationConsent: true`)

#### Scenario: SCENARIO-CHW-ONB-042 — Consentimiento previo no se repite ni se pisa (U)

- GIVEN `trainerLocationConsentAt` ya seteado
- WHEN guarda una ubicación
- THEN no se pide consentimiento y el timestamp existente queda intacto

#### Scenario: SCENARIO-CHW-ONB-043 — Sin geolocalización del dispositivo (G)

- GIVEN los archivos de `presentation/onboarding/` y sus dependencias propias
- THEN no importan `geolocator` ni referencian `navigator.geolocation` (scan de texto + test de widget que no lo invoca); recordando que un scan textual solo prueba ausencia de la cadena, no que algo funcione

#### Scenario: SCENARIO-CHW-ONB-044 — Fallo de Places es visible y no bloquea online (W)

- GIVEN el servicio de Places lanza error de red o de configuración
- THEN se muestra el estado de error con opción de reintentar
- AND si online está activado, la etapa puede completarse igual

### Requirement: REQ-CHW-ONB-011 — Salta etapas ya completas; alcance acotado

Cada paso MUST precargar lo ya existente en el perfil y la navegación MUST ir siempre a la
etapa que devuelve el predicado (un PF que solo falla la edad ve únicamente el paso `age`;
uno que solo falla el perfil PF ve únicamente `pf`). El onboarding MUST NOT pedir: gym,
experiencia, género, peso, altura (campos de alumno), avatar (queda en `/ajustes`),
`@handle`/unicidad de handle. MUST NOT modificar `role`.

#### Scenario: SCENARIO-CHW-ONB-045 — Solo falta la edad (R, W)

- GIVEN un trainer legacy completo salvo `bornAt`
- WHEN entra al Hub
- THEN ve únicamente el paso `age`, y al completarlo llega al destino original

#### Scenario: SCENARIO-CHW-ONB-046 — Solo falta el perfil PF (R, W)

- GIVEN un trainer con `displayName` y `bornAt` válidos, sin bio
- THEN ve únicamente el paso `pf`, con lo ya cargado precargado

#### Scenario: SCENARIO-CHW-ONB-047 — Nunca se piden campos de alumno (W, G)

- GIVEN recorrer los tres pasos (`age`, `identity`, `pf`)
- THEN ningún campo de gym, experiencia, género, peso, altura ni avatar aparece, y ninguna escritura los incluye

#### Scenario: SCENARIO-CHW-ONB-048 — El rol no se toca (U)

- GIVEN cualquier paso con escritura
- THEN el payload no incluye `role`

### Requirement: REQ-CHW-ONB-012 — Fixture compartido «trainer completo» y compatibilidad de la suite del Hub

Los tests existentes del Hub que pasan por el redirect (hoy 7 archivos: `coach_hub_router_redirect_test`,
`_shell_test`, `_resolving_test`, `coach_hub_session_resolving_provider_test`,
`coach_hub_scaffold_test`, `coach_hub_dashboard_in_shell_test` y
`test/visual_gate/gate_harness.dart`) MUST usar el fixture compartido
`test/helpers/coach_hub_profiles.dart` (`trainerCompleto()`: `bornAt` 1990-01-01 UTC, bio ≥ 20,
specialty, rate, online; y `trainerRecienPromovido()`), de modo que sigan verificando lo
mismo que antes. La migración MUST ocurrir ANTES de introducir el gate. `gate_harness.dart`
solo corre en Linux: si no se migra, rompe goldens sin que se vea en Mac. El fixture MUST
estar protegido por un test que asegura `hubOnboardingStage(trainerCompleto()) == done`
(si el predicado cambia, el fixture grita).

#### Scenario: SCENARIO-CHW-ONB-049 — El fixture es `done` (P)

- GIVEN el fixture compartido
- THEN `hubOnboardingStage(fixture) == HubOnboardingStage.done` y `trainerProfileComplete(fixture)` es verdadero

#### Scenario: SCENARIO-CHW-ONB-050 — Suite del Hub en verde (M/G)

- GIVEN la migración de fixtures
- WHEN corren los tests de `test/features/coach_hub/` y `test/app/coach_hub_router*`
- THEN pasan sin relajar ninguna aserción existente

### Requirement: REQ-CHW-ONB-013 — Strings en los tres ARB, tokens, light y dark

Todo string de pantalla nuevo MUST existir con la misma clave en `lib/l10n/intl_en.arb`,
`intl_es.arb` e `intl_es_AR.arb` y usarse vía `AppL10n` (sin literales); `es_AR` con voseo
rioplatense. Los mensajes de `AuthFailure.userMessage` NO se tocan (hardcodeados es-AR,
ADR-I18N-002). La UI MUST usar tokens (`AppPalette`, `TreinoIcon`, escalas de espaciado y
radio), sin hex ni Phosphor directo, con espaciado fijo (no `spaceBetween` para llenar
ancho), y verse correcta en light y dark (links con `accentText`, no `accent`). Los scans
existentes (`no_raw_radius_scan_test`, `no_raw_font_size_scan_test`,
`no_off_scale_spacing_scan_test`, `no_material_button_scan_test`,
`no_animated_hover_scan_test`, `snackbar_persist_scan_test`, tokens) MUST seguir en verde sin
agregar excepciones.

#### Scenario: SCENARIO-CHW-ONB-051 — Paridad de ARB (L)

- GIVEN las claves nuevas
- THEN las tres ARB tienen exactamente las mismas claves y `flutter gen-l10n` no reporta mensajes sin traducir

#### Scenario: SCENARIO-CHW-ONB-052 — Scans en verde (G)

- GIVEN las pantallas nuevas
- WHEN corren los scans de UI y de tokens
- THEN pasan sin nuevas excepciones

#### Scenario: SCENARIO-CHW-ONB-053 — Light y dark (W)

- GIVEN cada paso en `ThemeData` light y dark
- THEN se renderiza sin overflow en 360 y en 1280 px de ancho y sin excepciones

### Requirement: REQ-CHW-ONB-014 — Sin cambios server-side

El cambio MUST NOT modificar `firestore.rules`, `functions/src/subscriptions/` ni Mercado
Pago, y MUST NOT agregar campos al allowlist de `userPublicProfiles` (no hay campos nuevos de
modelo). `pubspec.yaml` no cambia. El único cambio posible en `functions/` es el fallback de Places
(una callable nueva `buscarLugarDelPf`, fuera de `functions/src/subscriptions/`), y solo si la
verificación manual de CORS (SCENARIO-CHW-ONB-055) falla; en ese caso MUST registrarse como
excepción explícita en design antes de aplicar. `functions/src/places-search.ts` no se usa
como proxy. El único cambio en `user_repository.dart` es `watchHasPendingWrites`
(REQ-CHW-ONB-004).

#### Scenario: SCENARIO-CHW-ONB-054 — Diff acotado (M)

- GIVEN el diff del PR
- THEN no aparecen `firestore.rules`, `functions/src/subscriptions/` ni `pubspec.yaml`
- AND cualquier cambio en `functions/` está justificado en design

### Requirement: REQ-CHW-ONB-015 — Verificación manual en navegador y con cuentas reales

Estos escenarios NO se mockean ni se dan por cubiertos por la suite (los tests de widget
no ven lo que ve el navegador). Se verifican manualmente antes del merge/deploy. `treino-dev`
es PRODUCCIÓN: solo cuentas descartables del dueño.

#### Scenario: SCENARIO-CHW-ONB-055 — Places Text Search desde el navegador (M)

- GIVEN paso 0, ANTES de mergear: `curl -si -X OPTIONS https://places.googleapis.com/v1/places:searchText -H 'Origin: https://app.gettreino.com' -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type,x-goog-api-key,x-goog-fieldmask'`
- THEN la respuesta incluye `access-control-allow-origin`; si no, se activa el fallback (callable `buscarLugarDelPf`) antes de mergear
- AND la key usada tiene «Application restrictions: None», o es una key de navegador restringida a `https://app.gettreino.com/*`, `https://coach-treino-dev.web.app/*` y `http://localhost:*/*` con la API Places (New)
- GIVEN el Hub servido en un navegador (dominio real y luego `coach-treino-dev.web.app`)
- WHEN el PF busca una dirección real en el editor de ubicación
- THEN llegan resultados reales (sin error CORS ni de key por referrer) y se puede elegir uno, sin errores de red de Places en la consola

#### Scenario: SCENARIO-CHW-ONB-056 — Cuenta nueva promovida recorre todo (M)

- GIVEN una cuenta descartable creada por popup Google/Apple en el Hub y promovida a trainer por el dueño
- WHEN entra al Hub
- THEN ve edad, luego nombre + términos, luego PF (solo presencial con una dirección escrita, diálogo de consentimiento), en ese orden, y llega al dashboard (o al `?to=facturacion` original, que cae en planes)
- AND en Firebase Console, `users` tiene `firstName`, `lastName`, `displayName`, `bornAt`, los tres campos `terms*`, bio, especialidad, tarifa, modalidad y `trainerLocationConsentAt`
- AND `trainerPublicProfiles` tiene `displayName`, la ubicación y su geohash

#### Scenario: SCENARIO-CHW-ONB-057 — Mobile no muestra ningún gate (M)

- GIVEN la misma cuenta, ya completa desde el Hub
- WHEN abre la app mobile (mismo build de debug, ver firma)
- THEN no aparece ningún gate (identidad, edad, PF) — y si eligió solo presencial, tampoco el de ubicaciones

#### Scenario: SCENARIO-CHW-ONB-058 — La ubicación aparece en el mapa/búsqueda (M)

- GIVEN la ubicación guardada desde la web con consentimiento
- THEN el PF aparece en la búsqueda de entrenadores por cercanía de la app

#### Scenario: SCENARIO-CHW-ONB-059 — Cuenta legacy real no se bloquea (M)

- GIVEN la cuenta de PF legacy del dueño (completa en mobile)
- WHEN entra al Hub
- THEN llega al dashboard sin ver el stepper, salvo que le falte `bornAt` (en ese caso solo ve la edad)

#### Scenario: SCENARIO-CHW-ONB-060 — Cerrar sesión real desde un paso (M)

- GIVEN un paso del onboarding en el navegador con sesión Google
- WHEN toca «Cerrar sesión»
- THEN la sesión se cierra y vuelve a `/login` sin colgarse

## Out of Scope (explícito)

- Avatar (opcional, queda en `/ajustes`); `@handle`, su unicidad y el conflicto
  `displayName` handle vs. nombre real (issue aparte).
- Campos de alumno: gym, experiencia, género, peso, altura.
- Geolocalización del dispositivo; edición/alta de múltiples ubicaciones o de gyms del
  catálogo desde el Hub (solo ubicación `custom` por búsqueda de dirección).
- Cambios en mobile, en `firestore.rules`, en Mercado Pago o en `functions/src/subscriptions/`.
- Exigir términos a trainers legacy con identidad completa.

## Restricción operativa que se levanta

Con este cambio desaparece la restricción de `coach-hub-login-google-apple`
(«no promover perfiles incompletos»), una vez desplegado y verificado REQ-CHW-ONB-015.

## Coverage Matrix

| REQ | SCENARIOs | Tipo de verificación |
|---|---|---|
| REQ-CHW-ONB-001 | 001-006 | unit puro (P) |
| REQ-CHW-ONB-002 | 007-010 | router (R) |
| REQ-CHW-ONB-003 | 011-015 | router (R) |
| REQ-CHW-ONB-004 | 016-019 | router (R), provider (V), repo (U), refresh |
| REQ-CHW-ONB-005 | 020-022 | widget (W), router (R) |
| REQ-CHW-ONB-006 | 023-025, 061 | widget (W), repo (U) |
| REQ-CHW-ONB-007 | 026-028 | widget (W), repo (U) |
| REQ-CHW-ONB-008 | 029-032, 062 | widget (W), repo (U) |
| REQ-CHW-ONB-009 | 033-035, 063, 064 | widget (W), unit (P), repo (U) |
| REQ-CHW-ONB-010 | 036-044, 065 | unit (P), widget (W), repo (U), servicio (MockClient), scan (G) |
| REQ-CHW-ONB-011 | 045-048 | router (R), widget (W), repo (U) |
| REQ-CHW-ONB-012 | 049-050 | unit (P), suite |
| REQ-CHW-ONB-013 | 051-053 | gate l10n (L), scans (G), widget (W) |
| REQ-CHW-ONB-014 | 054 | revisión de diff |
| REQ-CHW-ONB-015 | 055-060 | manual (M) |

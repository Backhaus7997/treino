# Delta for Coach Hub (login con Google y Apple, #1318)

**Change**: coach-hub-login-google-apple
**Capability**: `coach-hub` (`openspec/specs/coach-hub/spec.md`)
**Proposal ref**: `openspec/changes/coach-hub-login-google-apple/proposal.md`
**Numbering**: `REQ-CHW-AUTH-NNN` (nueva familia, no choca con `REQ-CHW-*` existentes) y
`SCENARIO-CHW-AUTH-NNN`. Los REQ existentes `REQ-CHW-ROUTER-002` (`/login` y
`/not-allowed` fuera del shell) y `REQ-PAGW-ROLE-001` (gate de rol trainer) **no se
modifican y siguen vigentes**; este delta no cambia el router.

Alineado con `design.md` (D1..D13). Convención de fuentes de test: S = `test/features/auth/data/auth_service_test.dart`,
N = `test/features/auth/application/auth_notifier_test.dart`,
F = `test/features/auth/domain/auth_failure_test.dart`,
L = `test/features/coach_hub/presentation/coach_hub_login_screen_test.dart`,
A = `test/features/coach_hub/presentation/coach_hub_not_allowed_screen_test.dart` (nuevo),
T = `test/features/auth/presentation/widgets/terms_notice_text_test.dart`,
G = guards existentes (`test/features/paywall/superficie_de_cobro_alumno_test.dart`, scans de tokens),
R = `test/app/coach_hub_router_redirect_test.dart`, M = verificación manual.

Nombres (design): `AuthService.signInWithGooglePopup()` / `signInWithApplePopup()`,
`AuthNotifier.signInWithGooglePopup()` / `signInWithApplePopup()`,
`AuthFailure.popupBlocked()` y `AuthFailure.providerUnavailable()`. El mapeo de errores
del popup vive en `AuthService._failureFromPopup` (acotado al camino web), con fallback a
`AuthFailure.fromFirebase`.

## ADDED Requirements

### Requirement: REQ-CHW-AUTH-001 — Popup sign-in con Google y Apple en `/login`

`/login` del Hub MUST ofrecer, además de email/password, un botón «Google» y un botón
«Apple». Cada botón MUST autenticar con `FirebaseAuth.signInWithPopup`
(`GoogleAuthProvider()` y `OAuthProvider('apple.com')` respectivamente) a través de
métodos nuevos de `AuthService` (`signInWithGooglePopup`, `signInWithApplePopup`) expuestos por
`AuthNotifier`. No MUST agregarse ningún paquete a `pubspec.yaml`. Los métodos
`signInWithGoogle` / `signInWithApple` de mobile MUST NOT ser reutilizados por el Hub.
El provider de Google MUST pedir `prompt=select_account`; el de Apple MUST ser
`OAuthProvider('apple.com')` con scopes `email` y `name`. Entre el `onPressed` y
`signInWithPopup` MUST NOT haber ningún `await` (si no, el navegador bloquea el popup).
Mientras un camino está en curso, la pantalla MUST mostrar el spinner solo en el botón
activo y deshabilitar los otros dos. Tras un sign-in exitoso, la pantalla MUST NOT
navegar por sí misma: la decisión de destino sigue siendo de `coachHubRedirect`.

#### Scenario: SCENARIO-CHW-AUTH-001 — Google popup exitoso invoca el provider correcto (S)

- GIVEN `FirebaseAuth` mockeado cuyo `signInWithPopup` devuelve un usuario
- WHEN se llama al método web de Google de `AuthService`
- THEN se invoca `signInWithPopup` con una instancia de `GoogleAuthProvider` cuyos
  custom parameters incluyen `prompt=select_account`
- AND NO se invoca `signInWithCredential`

#### Scenario: SCENARIO-CHW-AUTH-002 — Apple popup exitoso invoca el provider correcto (S)

- GIVEN `FirebaseAuth` mockeado cuyo `signInWithPopup` devuelve un usuario
- WHEN se llama al método web de Apple de `AuthService`
- THEN se invoca `signInWithPopup` con un `OAuthProvider` cuyo `providerId` es `apple.com`
  y scopes `email` y `name`
- AND NO se invoca `signInWithCredential`

#### Scenario: SCENARIO-CHW-AUTH-003 — El login muestra los tres caminos (L)

- GIVEN `CoachHubLoginScreen` montada sin sesión
- WHEN se renderiza
- THEN se encuentran el formulario email/password, un botón Google y un botón Apple
- AND tocar cada botón social llama al método correspondiente del notifier
  (`signInWithGooglePopup` / `signInWithApplePopup`)
- AND mientras uno está en curso, solo ese muestra spinner y los otros dos quedan
  deshabilitados

#### Scenario: SCENARIO-CHW-AUTH-004 — PF entra con Google/Apple y cae en su mismo uid (M)

Verificación manual en producción (no es test unitario; el proveedor real no se
mockea).

- GIVEN la cuenta del dueño, ya registrada en mobile con Google (y otra vez con Apple) y
  promovida a trainer
- WHEN entra al Hub (`app.gettreino.com`) con el mismo proveedor por popup
- THEN llega al dashboard del Hub
- AND el uid mostrado en Firebase Console → Users coincide con el de mobile (para Apple
  esto prueba la inferencia «mismo Team ⇒ mismo `sub`»)
- AND el mail del gate de código llega (también con relay de «Ocultar mi email»)
- AND se repite en `coach-treino-dev.web.app`

### Requirement: REQ-CHW-AUTH-002 — Alta athlete best-effort en los tres caminos

Los tres caminos de login del Hub (email, Google popup, Apple popup) MUST llamar a
`createIfAbsent` tras autenticar, de modo que un usuario sin `users/{uid}` quede con un
doc `role: athlete` (y su `userPublicProfiles/{uid}`). Para los dos caminos popup la
llamada MUST ser best-effort: si `createIfAbsent` falla, el fallo MUST reportarse con el
mismo mecanismo que mobile (`_reportarAltaFallida`) y el sign-in MUST NOT bloquearse ni
fallar. El backfill existente de `signInWithEmail` MUST conservarse sin cambios. El
cliente MUST NOT poder crear un doc con rol distinto de `athlete`.

#### Scenario: SCENARIO-CHW-AUTH-005 — Cuenta nueva por popup crea el doc athlete (S)

- GIVEN `signInWithPopup` devuelve un usuario sin `users/{uid}`
- WHEN el método popup (Google o Apple) completa
- THEN `createIfAbsent` se invoca una vez con ese usuario
- AND el resultado del método es el sign-in exitoso

#### Scenario: SCENARIO-CHW-AUTH-006 — Fallo de `createIfAbsent` no bloquea el sign-in (S)

- GIVEN `signInWithPopup` exitoso y `createIfAbsent` lanza una excepción
- WHEN el método popup completa
- THEN NO se propaga la excepción y el usuario queda autenticado
- AND se invoca `_reportarAltaFallida` (reporte non-fatal) con la causa

#### Scenario: SCENARIO-CHW-AUTH-007 — El camino email conserva el backfill (S)

- GIVEN un usuario sin `users/{uid}` que entra con email/password
- WHEN `signInWithEmail` completa
- THEN `createIfAbsent` se invoca igual que antes del cambio (test existente en verde,
  sin modificar)

#### Scenario: SCENARIO-CHW-AUTH-008 — Cuenta nueva por popup termina en `/not-allowed` (R)

- GIVEN un usuario autenticado cuyo `users/{uid}` recién creado es `role: athlete`
- WHEN `coachHubRedirect` evalúa cualquier ruta
- THEN el destino es `/not-allowed`

### Requirement: REQ-CHW-AUTH-003 — Cancelación del popup restaura el estado en silencio

Si el usuario cierra el popup, se cancela una solicitud concurrente o rechaza en el
proveedor (`popup-closed-by-user`, `cancelled-popup-request`, `user-cancelled`),
`AuthService` MUST traducirlo a
`signInCancelled` y `AuthNotifier` MUST restaurar el estado previo sin mostrar error,
igual que `signInWithGoogle`/`signInWithApple` de mobile. La pantalla MUST NOT mostrar
SnackBar, texto de error ni quedar en estado de carga.

#### Scenario: SCENARIO-CHW-AUTH-009 — `popup-closed-by-user` se mapea a cancelado (S, F)

- GIVEN `signInWithPopup` lanza `FirebaseAuthException(code: 'popup-closed-by-user')`
- WHEN corre el método popup
- THEN lanza/propaga `signInCancelled`
- AND NO se invoca `createIfAbsent`

#### Scenario: SCENARIO-CHW-AUTH-010 — `cancelled-popup-request` se mapea a cancelado (S, F)

- GIVEN `signInWithPopup` lanza `FirebaseAuthException(code: 'cancelled-popup-request')`
- WHEN corre el método popup
- THEN el resultado es `signInCancelled`

#### Scenario: SCENARIO-CHW-AUTH-026 — `user-cancelled` se mapea a cancelado (S)

- GIVEN `signInWithPopup` lanza `FirebaseAuthException(code: 'user-cancelled')`
- WHEN corre el método popup
- THEN el resultado es `signInCancelled` (igual que popup cerrado)
- AND NO se invoca `createIfAbsent` y NO se reporta non-fatal

#### Scenario: SCENARIO-CHW-AUTH-011 — Notifier restaura silenciosamente (N, L)

- GIVEN el notifier con estado previo `AsyncData(null)`
- WHEN el método popup termina en `signInCancelled`
- THEN el estado final es el previo (no `AsyncError`)
- AND la pantalla no muestra ningún mensaje de error

### Requirement: REQ-CHW-AUTH-004 — Copy específico por error del popup

El camino popup (`AuthService._failureFromPopup`, con fallback a
`AuthFailure.fromFirebase`) MUST mapear estos `code` de `FirebaseAuthException`
(FlutterFire web entrega el code sin el prefijo `auth/`) a mensajes distintos y
accionables. El copy MUST vivir en `AuthFailure.userMessage`, **hardcodeado en es-AR, NO
en los ARB** (ADR-I18N-002, guardado por
`test/features/auth/domain/auth_failure_exclusion_test.dart`; el dominio no tiene
`BuildContext`):

| code | Failure | Mensaje (es-AR) | Reporte |
|---|---|---|---|
| `popup-blocked` | `AuthFailure.popupBlocked()` | «Tu navegador bloqueó la ventana. Permití ventanas emergentes y probá de nuevo» | no |
| `account-exists-with-different-credential` | `accountExistsWithDifferentCredential` (existente) | «Ya tenés una cuenta con ese email. Entrá con el método que usaste al registrarte» | no |
| `unauthorized-domain`, `operation-not-allowed`, `invalid-credential` | `AuthFailure.providerUnavailable()` | «Este método no está disponible. Entrá con email o escribinos» | **sí, non-fatal** (`reason: 'AuthService.$camino: proveedor no disponible (${e.code})'`) |

El nuevo copy de `account-exists-with-different-credential` MUST ser el mismo que ve
mobile (`auth_failure.dart` es compartido); los tests de mobile que lo citen MUST
actualizarse a ese texto. `invalid-credential` en el popup indica que Firebase rechazó
la credencial del proveedor (configuración; **inferido**, se confirma en la
verificación manual): MUST NOT mostrar «La contraseña es incorrecta». El mapeo nuevo
MUST NOT alterar `fromFirebase` para los otros caminos (p. ej. `operation-not-allowed`
en el alta por email de mobile). `unauthorized-domain`, `operation-not-allowed` e
`invalid-credential` son errores de configuración nuestros, por eso MUST reportarse
non-fatal; los demás MUST NOT reportarse. (En web `reportNonFatal` solo llega a la
consola del navegador; se acepta, Analytics queda fuera de alcance.)

#### Scenario: SCENARIO-CHW-AUTH-012 — popup bloqueado muestra copy específico (F, L)

- GIVEN `signInWithPopup` lanza `popup-blocked`
- WHEN la pantalla procesa el fallo
- THEN se muestra el copy de ventanas emergentes
- AND NO se muestra el copy genérico de error
- AND NO se reporta non-fatal

#### Scenario: SCENARIO-CHW-AUTH-013 — Cuenta existente con otra credencial es accionable (F)

- GIVEN `signInWithPopup` lanza `account-exists-with-different-credential`
- WHEN se mapea a `AuthFailure`
- THEN el mensaje indica entrar con el método usado al registrarse
- AND el mismo mensaje se obtiene desde el camino mobile

#### Scenario: SCENARIO-CHW-AUTH-014 — Dominio no autorizado / operación no habilitada (S, F)

- GIVEN `signInWithPopup` lanza `unauthorized-domain` (o `operation-not-allowed`)
- WHEN se mapea
- THEN el failure es `providerUnavailable` con «Este método no está disponible...» y
  mención al email
- AND se emite un reporte non-fatal con el code
- AND el usuario NO queda autenticado

#### Scenario: SCENARIO-CHW-AUTH-027 — `invalid-credential` en popup es «método no disponible» (S, F)

- GIVEN `signInWithPopup` lanza `invalid-credential`
- WHEN corre el método popup
- THEN el failure es `providerUnavailable` (NO `wrongPassword`)
- AND se emite un reporte non-fatal con el code
- AND `AuthFailure.fromFirebase` con `invalid-credential` sigue devolviendo
  `wrongPassword` para el login por email (sin regresión)

#### Scenario: SCENARIO-CHW-AUTH-028 — El mapeo del popup no contamina otros caminos (S, F)

- GIVEN `operation-not-allowed` proveniente del alta por email
- WHEN se mapea con `AuthFailure.fromFirebase`
- THEN el resultado es el mismo que antes del cambio (no `providerUnavailable`)

### Requirement: REQ-CHW-AUTH-005 — `/not-allowed` con copy nuevo para no-entrenadores

`CoachHubNotAllowedScreen` MUST dirigirse a cualquier usuario autenticado que no pueda
usar el Hub: atleta (`role != trainer`) y autenticado sin `users/{uid}`. El copy MUST:
(a) explicar que el Hub es solo para entrenadores; (b) nombrar App Store y Play Store
como dónde está la app para atletas, **sin ningún link ni `onTap` de navegación a
stores**; (c) ofrecer un contacto «quiero ser entrenador» por `mailto:` a
`kLegalContactEmail` (`treino@gettreino.com`) con asunto, abierto con `url_launcher`
(`Uri(scheme: 'mailto', path: ..., query: 'subject=${Uri.encodeComponent(...)}')`, con
`%20` y no `+`), y la dirección MUST mostrarse también como texto visible; (d) mantener
la acción de cerrar sesión, que MUST cerrar la sesión de **Firebase Auth directamente**
y MUST NOT pasar por `AuthService.signOut()` / `AuthNotifier.signOut()` (en web
cuelgan: llaman `GoogleSignIn.signOut()`, que espera un `initialize()` que el Hub nunca
hace). Ambos efectos (abrir URL, cerrar sesión) MUST estar detrás de seams inyectables
(`CoachHubNotAllowedScreen({abrirUrl, cerrarSesion})`, con defaults `launchUrl` y el
signOut de Firebase). Los strings de esta pantalla MUST ir por ARB (REQ-CHW-AUTH-008).
Como esta pantalla pasa a abrir una URL, `test/features/paywall/superficie_de_cobro_alumno_test.dart`
MUST listar `coach_hub_not_allowed_screen.dart` en sus archivos permitidos («solo web:
`mailto:` de contacto, no compra»). Un usuario en este estado MUST NOT poder acceder a ninguna
otra ruta del Hub: toda ruta MUST redirigir a `/not-allowed` (comportamiento existente
del router, que se verifica y no se cambia). `/not-allowed` MUST seguir fuera del shell
(REQ-CHW-ROUTER-002).

#### Scenario: SCENARIO-CHW-AUTH-015 — Copy nombra las stores sin links (A)

- GIVEN `CoachHubNotAllowedScreen` montada
- WHEN se renderiza
- THEN el texto contiene «App Store» y «Play Store»
- AND no existe ningún widget de link/botón cuyo destino sea una URL de store

#### Scenario: SCENARIO-CHW-AUTH-016 — Contacto abre `mailto:` a `kLegalContactEmail` (A)

- GIVEN la pantalla montada con `url_launcher` doblado
- WHEN el usuario toca la acción de contacto
- THEN `abrirUrl` recibe un `Uri` con esquema `mailto`, path `kLegalContactEmail` y un
  asunto con espacios codificados como `%20`
- AND la dirección `kLegalContactEmail` también aparece como texto visible

#### Scenario: SCENARIO-CHW-AUTH-017 — Cerrar sesión cierra Firebase Auth sin pasar por AuthService (A)

- GIVEN la pantalla montada con un `cerrarSesion` doblado
- WHEN el usuario toca «Cerrar sesión»
- THEN se invoca `cerrarSesion` (cierre de la sesión de Firebase Auth, directo)
- AND NO se invoca `AuthService.signOut()` ni `AuthNotifier.signOut()`
- AND si `cerrarSesion` falla, se muestra el error existente (`coachHubSignOutError`)

#### Scenario: SCENARIO-CHW-AUTH-029 — El guard de superficies que abren URL conoce la pantalla (G)

- GIVEN `superficie_de_cobro_alumno_test.dart`
- WHEN corre con `coach_hub_not_allowed_screen.dart` abriendo un `mailto:`
- THEN pasa porque el archivo figura en los permitidos con su justificación

#### Scenario: SCENARIO-CHW-AUTH-018 — Atleta no accede a nada más (R)

- GIVEN un usuario autenticado con `role: athlete`
- WHEN `coachHubRedirect` evalúa `/dashboard`, `/upload-plan`, `/pagos` y `/login`
- THEN el destino de cada una es `/not-allowed` (test existente en `R:251-295`
  permanece en verde; se extiende si falta alguna ruta)

#### Scenario: SCENARIO-CHW-AUTH-019 — Autenticado sin doc no accede a nada más (R)

- GIVEN un usuario autenticado sin `users/{uid}` (perfil resuelto, doc ausente)
- WHEN `coachHubRedirect` evalúa cualquier ruta protegida
- THEN el destino es `/not-allowed` (test existente en `R:298` permanece en verde)

#### Scenario: SCENARIO-CHW-AUTH-020 — `/not-allowed` no renderiza el shell (R)

- GIVEN un usuario en `/not-allowed`
- WHEN se bombea el árbol
- THEN no se encuentra `CoachHubScaffold` (invariante de REQ-CHW-ROUTER-002, sigue verde)

### Requirement: REQ-CHW-AUTH-006 — Aviso de términos en el login del Hub

El login del Hub MUST mostrar `TermsNoticeText` de forma visible, antes de los botones de
autenticación social, porque el Hub ahora puede crear cuentas por OAuth (mismo motivo
que mobile, #434).

#### Scenario: SCENARIO-CHW-AUTH-021 — El aviso está presente en el login (L)

- GIVEN `CoachHubLoginScreen` montada
- WHEN se renderiza
- THEN se encuentra un `TermsNoticeText`
- AND aparece ubicado antes de los botones Google/Apple en el orden visual del árbol

#### Scenario: SCENARIO-CHW-AUTH-030 — Los links del aviso tienen contraste en light (T)

- GIVEN `TermsNoticeText` en tema light
- WHEN se renderiza
- THEN sus links usan `palette.accentText` (no `palette.accent`)
- AND en dark el color resultante no cambia

### Requirement: REQ-CHW-AUTH-007 — Documentación y decisión superada

Los comentarios que afirman «email/password solamente» MUST corregirse: dartdoc de
`coach_hub_login_screen.dart:18-21` y comentario de `lib/main_coach_hub.dart:46-48`. La
fila de la decisión #2 en `openspec/changes/coach-hub-bootstrap/propose.md` MUST llevar
una nota de «superada por coach-hub-login-google-apple». AGENTS.md §11.1: ninguna
afirmación nueva sin evidencia citada.

#### Scenario: SCENARIO-CHW-AUTH-022 — Ningún doc dice «solo email/password» (M)

- GIVEN el diff del PR
- WHEN se revisan los tres archivos nombrados
- THEN ninguno afirma que el Hub es solo email/password
- AND la fila #2 de `coach-hub-bootstrap/propose.md` referencia este cambio

### Requirement: REQ-CHW-AUTH-008 — Strings en los tres ARB

Todo string de **pantalla** nuevo (botones Google/Apple y divisor del login, aviso de
términos, título/cuerpo/contacto/asunto de `/not-allowed`: `coachHubNotAllowedTitle`,
`...Body`, `...ContactPrompt`, `...ContactCta`, `...MailSubject`) MUST existir en
`lib/l10n/intl_en.arb`, `intl_es.arb` e `intl_es_AR.arb` con la misma clave, y MUST usarse
vía `AppL10n` (no literales). El copy en `es_AR` MUST usar voseo rioplatense. **Excepción
(ADR-I18N-002):** los mensajes de error de REQ-CHW-AUTH-004 (`AuthFailure.userMessage`)
NO van a los ARB y MUST seguir hardcodeados en es-AR;
`auth_failure_exclusion_test.dart` MUST seguir en verde. Si `/not-allowed` queda sin
literales de tamaño/espaciado, MUST salir de las allowlists de
`no_raw_font_size_scan_test.dart` y `no_off_scale_spacing_scan_test.dart` y bajar sus
techos (medido corriendo el test, no calculado). Los scans de UI existentes
(`no_raw_radius_scan_test`, `no_raw_font_size_scan_test`, `no_material_button_scan_test`,
`no_animated_hover_scan_test`, `snackbar_persist_scan_test`) MUST seguir en verde, y la
UI nueva MUST usar tokens (`AppPalette`, `TreinoIcon`), sin hex ni Phosphor directo.

#### Scenario: SCENARIO-CHW-AUTH-023 — Paridad de claves entre ARB (test de l10n existente)

- GIVEN las claves de pantalla nuevas agregadas
- WHEN corre el test/gate de paridad de ARB del repo
- THEN las tres ARB tienen exactamente las mismas claves nuevas
- AND `flutter gen-l10n` no reporta mensajes sin traducir
- AND ningún mensaje de `AuthFailure.userMessage` aparece en los ARB
  (`auth_failure_exclusion_test.dart` en verde)

#### Scenario: SCENARIO-CHW-AUTH-024 — Scans de UI en verde

- GIVEN los botones y la pantalla nuevos
- WHEN corren los cinco scans de UI nombrados
- THEN todos pasan sin agregar excepciones

### Requirement: REQ-CHW-AUTH-009 — Sin cambios de superficie server-side ni de router

El cambio MUST NOT modificar `firestore.rules`, `functions/` (incluido
`functions/src/subscriptions/`), `coach_hub_router.dart` ni `pubspec.yaml`. El rol MUST
seguir siendo inmutable desde el cliente.

#### Scenario: SCENARIO-CHW-AUTH-025 — Diff acotado (M)

- GIVEN el diff del PR
- WHEN se listan los archivos tocados
- THEN no aparece ninguno de los archivos nombrados arriba

## Out of Scope (explícito)

- **Linking de cuentas** (`linkWithCredential`): decidido afuera por el usuario
  (2026-10-05). Un PF con «one account per email» activo en consola y proveedor distinto
  queda con el copy accionable de REQ-CHW-AUTH-004 y nada más.
- **Links a App Store / Play Store** en `/not-allowed`: la app aún no está publicada; van
  en un cambio posterior.
- **Onboarding en el Hub para un PF promovido con perfil incompleto**: SDD aparte
  (follow-up b). Restricción operativa mientras tanto: no promover perfiles incompletos.
- Consentimiento y edad en web (los cubren los gates de mobile); redirect flow;
  Cloud Functions / `beforeSignIn`; Mercado Pago.
- Configuración de consola (Firebase Auth providers, Authorized domains
  `app.gettreino.com` y `coach-treino-dev.web.app`, Services ID de Apple, cliente OAuth
  de Google): la hace el usuario; este spec no la verifica. `treino-dev` es PRODUCCIÓN:
  toda prueba con cuentas reales es solo con cuentas del dueño.

## Coverage Matrix

| REQ | SCENARIOs | Tipo de verificación |
|---|---|---|
| REQ-CHW-AUTH-001 | 001, 002, 003, 004 | unit (S), widget (L), manual (004) |
| REQ-CHW-AUTH-002 | 005, 006, 007, 008 | unit (S), router (R) |
| REQ-CHW-AUTH-003 | 009, 010, 011, 026 | unit (S, N, F), widget (L) |
| REQ-CHW-AUTH-004 | 012, 013, 014, 027, 028 | unit (F, S), widget (L); copy hardcoded (ADR-I18N-002) |
| REQ-CHW-AUTH-005 | 015, 016, 017, 018, 019, 020, 029 | widget (A), router (R), guard (G) |
| REQ-CHW-AUTH-006 | 021, 030 | widget (L, T) |
| REQ-CHW-AUTH-007 | 022 | revisión de diff |
| REQ-CHW-AUTH-008 | 023, 024 | gate l10n (solo strings de pantalla), scans |
| REQ-CHW-AUTH-009 | 025 | revisión de diff |

# Design: Coach Hub — login con Google y Apple (#1318)

**Change**: `coach-hub-login-google-apple` · **Inputs**: `proposal.md`, `explore.md`, `specs/coach-hub/spec.md`
**Base leída**: worktree `strange-wiles-11f038` (`feat/coach-hub-login-google-apple`, sobre `0547f3d6`).

## Technical Approach

Dos métodos web en `AuthService` sobre el seam que ya existe (`FirebaseAuth` inyectado,
`MockFirebaseAuth` en `auth_service_test.dart:17`): `_auth.signInWithPopup(provider)` →
`createIfAbsent` best-effort con `_reportarAltaFallida`, igual que mobile
(`auth_service.dart:305-312`). `AuthNotifier` los expone con la restauración silenciosa
ante cancelación (`auth_notifier.dart:36-64`). La pantalla sólo dispara y muestra errores;
el destino lo sigue decidiendo `coachHubRedirect` (`coach_hub_router.dart:121-128`, sin
cambios). Cero paquetes, cero CF, cero rules.

## Evidencia que fija el diseño

| Hecho | Evidencia |
|---|---|
| FlutterFire web **quita** el prefijo `auth/` | `firebase_auth_web-5.15.3/lib/src/utils/web_utils.dart:89` (`replaceFirst('auth/', '')`) |
| Codes JS: `popup-closed-by-user`, `cancelled-popup-request`, `popup-blocked`, `account-exists-with-different-credential`, `unauthorized-domain`, `operation-not-allowed`, `user-cancelled` | `functions/node_modules/@firebase/auth/dist/esm/index-d90d2ee5.js:338,360,385,390,392,393,410` (v1.13.3; runtime web = JS SDK 11.9.1, `firebase_core_web-2.24.1/lib/src/firebase_sdk_version.dart:9`) |
| `invalid-credential` hoy cae en `wrongPassword` («La contraseña es incorrecta») | `auth_failure.dart:40-42` |
| `signInWithPopup` llega a JS sin `await` previo | `firebase_auth_web-5.15.3/lib/firebase_auth_web.dart:504-510` |
| `OAuthProvider.addScope/scopes/parameters`, `GoogleAuthProvider.setCustomParameters` | `firebase_auth_platform_interface-7.7.3/lib/src/providers/oauth.dart:21-49`, `google_auth.dart:65-87` |
| **`AuthService.signOut()` cuelga en el Hub**: llama `_googleSignIn.signOut()` (`auth_service.dart:518`), y en web eso espera un `initialize()` que el Hub nunca hace (`main_coach_hub.dart:46-48`) | `google_sign_in_web-1.1.3/lib/google_sign_in_web.dart:173-174` |
| `reportNonFatal` en web es sólo `debugPrint` (Crashlytics no corre en web) | `lib/core/telemetry/non_fatal.dart:81-85` |
| Guard repo-wide de quién abre URLs | `test/features/paywall/superficie_de_cobro_alumno_test.dart:159-249` |
| `TermsNoticeText` pinta links con `palette.accent` (tinta); en light eso es 1,57:1 | `terms_notice_text.dart:68-71`; `coach_hub_login_screen_test.dart:71-80`; `app_palette.dart:183-184,212-213` |

## Architecture Decisions

| Decisión | Elegido | Rechazado | Por qué |
|---|---|---|---|
| D1 Dónde mapear errores del popup | `AuthService._failureFromPopup(e, st, camino)` privado; fallback a `AuthFailure.fromFirebase(e)` | Meter los codes en `fromFirebase` | `operation-not-allowed` sale también del alta por email en mobile; ahí «entrá con email» sería falso. El mapeo nuevo queda acotado al camino web. |
| D2 Cancelación | `{popup-closed-by-user, cancelled-popup-request, user-cancelled}` → `signInCancelled` | Sólo los dos del proposal | `user-cancelled` = el usuario rechazó en el IdP (JS :256); ya está en el set de `auth_service.dart:492-498`. |
| D3 Config rota | `unauthorized-domain`, `operation-not-allowed` **e `invalid-credential`** → `providerUnavailable` + non-fatal | Dejar `invalid-credential` en `fromFirebase` | En un botón de Google no hay contraseña: «La contraseña es incorrecta» es mentira. En popup ese code indica que Firebase rechazó la credencial del IdP, o sea configuración (**inferido**: se confirma en el paso 2 de la verificación manual). |
| D4 Variantes nuevas | `AuthFailure.popupBlocked()` y `.providerUnavailable()` (freezed); copy en `userMessage` | Reusar `unknown(code)` con switch de code | Sigue la forma del tipo. Costo: regenerar `auth_failure.freezed.dart`. |
| D5 Copy de errores | `userMessage` hardcoded es-AR (ADR-I18N-002, `auth_failure.dart:6-10`) | ARB | El dominio no tiene `BuildContext`. **Choca con REQ-CHW-AUTH-004/008 del spec** (ver Open Questions). |
| D6 Google | `GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'})` | Sin `prompt` | En escritorio el PF suele tener varias sesiones de Google; sin el selector Google elige solo, y una cuenta equivocada crea un athlete nuevo y termina en `/not-allowed`. Además `FirebaseAuth.signOut` no cierra la sesión de Google: sin selector no podés cambiar de cuenta. |
| D7 Apple | `OAuthProvider('apple.com')..addScope('email')..addScope('name')` | `AppleAuthProvider` | Los dos se convierten igual en web (`web_utils.dart:282-288` vs `:339-345`); `OAuthProvider('apple.com')` ya se usa en `auth_service.dart:352,488`. |
| D8 Notifier | Helper privado `_socialSignIn(Future<User> Function())` usado por los 4 métodos sociales | Copiar el bloque dos veces más | Cuatro copias de la misma restauración. Los tests de mobile (`auth_notifier_test.dart:238+`) blindan el refactor. |
| D9 Sign-out en `/not-allowed` | Sigue con `FirebaseAuth.instance.signOut()`, ahora por un seam inyectable | `authNotifier.signOut()` | Colgaría (ver evidencia). **Choca con SCENARIO-CHW-AUTH-017** («signOut del notifier/servicio»). |
| D10 Seams de la pantalla | `CoachHubNotAllowedScreen({abrirUrl = launchUrl, cerrarSesion = _cerrarSesionFirebase})`, tear-offs const | Provider de Riverpod | No hay helper de mailto ni launcher inyectable en el repo. El router la sigue construyendo `const`. |
| D11 Loading por botón | Estado local `_Metodo? _enCurso` (email/google/apple): spinner sólo en el activo y los tres deshabilitados | `ref.watch(authNotifierProvider)` | El test actual monta la pantalla sin overrides (`coach_hub_login_screen_test.dart:12-24`). Con un watch, el build pasaría por `authStateChangesProvider` → `FirebaseAuth.instance` (`auth_providers.dart:9-21`), que en test no existe. |
| D12 Íconos | `TreinoButton(variant: secondary, icon: TreinoIcon.googleLogo / appleLogo)` | SVG `google_g.svg` + FontAwesome como mobile (`login_screen.dart:236-257`) | `TreinoButton` sólo acepta `IconData` (`treino_button.dart:126`), y el scan exige el kit (`no_material_button_scan_test.dart:48-58`). |
| D13 `TermsNoticeText` | Reusarlo y cambiar el link a `palette.accentText` | Uno propio para el Hub | En dark no cambia nada (`accent == accentText`, `app_palette.dart:183-184`) y arregla el contraste en light, también en mobile. |

**Invariante de popup**: entre el `onPressed` y `_auth.signInWithPopup` NO puede haber ningún
`await`. Si lo hay, el navegador pierde la activación del usuario y devuelve `popup-blocked`.
Hoy la cadena es sincrónica: `setState` → `notifier` (`state = AsyncLoading` +
`AsyncValue.guard`) → `service`.

## Data Flow

    tap Google ─→ Screen(_enCurso=google) ─→ AuthNotifier._socialSignIn
        ─→ AuthService.signInWithGooglePopup ─→ _auth.signInWithPopup(provider)
              ├─ ok ─→ createIfAbsent(uid, email ?? '')  [falla ⇒ _reportarAltaFallida]
              └─ FirebaseAuthException ─→ _failureFromPopup ─→ AuthFailure
        authStateChanges ─→ coachHubRedirect ─→ trainer: /dashboard (gate de mail) | resto: /not-allowed

Cuenta nueva: puede pasar por `/not-allowed` antes de que nazca el doc. No pasa nada: después
nace athlete y se queda ahí.

Comportamiento que ya existe y no se toca: si el stream del perfil da error, `valueOrNull`
devuelve null (`coach_hub_router.dart:117-123`) y un PF termina en `/not-allowed`. Ahora va a
leer «solo para entrenadores».

Apple con la Return URL mal cargada muestra el error adentro del popup. Si el usuario lo
cierra, llega como `popup-closed-by-user`, o sea silencio. Sólo lo detecta la verificación
manual.

## Interfaces

```dart
// AuthService (web-only; dartdoc lo dice, sin assert(kIsWeb) para no romper tests)
Future<User> signInWithGooglePopup();   // camino 'signInWithGooglePopup'
Future<User> signInWithApplePopup();    // camino 'signInWithApplePopup'
// AuthNotifier
Future<void> signInWithGooglePopup();
Future<void> signInWithApplePopup();
// AuthFailure
const factory AuthFailure.popupBlocked() = _PopupBlocked;
const factory AuthFailure.providerUnavailable() = _ProviderUnavailable;
```

Copy (`userMessage`): `popupBlocked` «Tu navegador bloqueó la ventana. Permití ventanas
emergentes y probá de nuevo» · `providerUnavailable` «Este método no está disponible. Entrá
con email o escribinos» · `accountExistsWithDifferentCredential` pasa a «Ya tenés una cuenta
con ese email. Entrá con el método que usaste al registrarte» (también lo ve mobile).
Non-fatal: `reason: 'AuthService.$camino: proveedor no disponible (${e.code})'`.

Mailto: `Uri(scheme: 'mailto', path: kLegalContactEmail, query: 'subject=${Uri.encodeComponent(asunto)}')`.
`queryParameters` NO sirve porque convierte los espacios en `+` (`url_launcher-6.3.2/README.md:146-151`).
La dirección también va como texto visible, por si el navegador no tiene cliente de mail.

## File Changes

| Archivo | Acción | Líneas aprox. |
|---|---|---|
| `lib/features/auth/data/auth_service.dart` | 2 métodos + `_signInWithPopup` + `_failureFromPopup` | +70 |
| `lib/features/auth/application/auth_notifier.dart` | helper + 2 métodos | +20 / −15 |
| `lib/features/auth/domain/auth_failure.dart` (+ `.freezed.dart` regenerado) | 2 variantes, 1 copy | +10 (gen ≈ +400) |
| `lib/features/coach_hub/presentation/coach_hub_login_screen.dart` | divisor «O CONTINUÁ CON» → `TermsNoticeText` → fila Google/Apple, debajo de INGRESAR; `_enCurso`; dartdoc :18-21 | +90 |
| `lib/features/coach_hub/presentation/coach_hub_not_allowed_screen.dart` | copy por ARB, contacto, seams; tokens `AppSpacing`/`AppTextSize` | +70 / −40 |
| `lib/features/auth/presentation/widgets/terms_notice_text.dart` | `accent` → `accentText` | ±1 |
| `lib/l10n/intl_{en,es,es_AR}.arb` + `app_l10n*.dart` (gen-l10n) | `coachHubNotAllowedTitle/Body/ContactPrompt/ContactCta/MailSubject` | +60 (gen ≈ +50) |
| `lib/main_coach_hub.dart` | comentario :46-48 (popup, y por qué el sign-out no va por AuthService) | ±6 |
| `openspec/changes/coach-hub-bootstrap/propose.md` | fila #2: «Superada por #1318» | +1 |
| `test/features/paywall/superficie_de_cobro_alumno_test.dart` | sumar `coach_hub_not_allowed_screen.dart` a `permitidos` («sólo web: `mailto:` de contacto, no compra») | +4 |
| `test/app/theme/tokens/no_raw_font_size_scan_test.dart`, `no_off_scale_spacing_scan_test.dart` | si `/not-allowed` queda sin literales: sacarla de la allowlist y bajar los techos (**medir corriendo**, no calcular) | ±6 |

El código nuevo usa `AppSpacing.*`, `AppTextSize.*`, `AppPalette.of`, `TreinoIcon.*` y
`TreinoButton`. Nada de `Radius.circular(N)` ni `fontSize: N` nuevos: los literales que ya
tiene el login se quedan y cuentan para el techo. Sin `AnimatedContainer` ni SnackBar.

## Testing Strategy (RED primero, en este orden)

| # | Test | Qué |
|---|---|---|
| 1 | `auth_failure_test.dart` | variantes nuevas + copy nuevo de account-exists (actualizar :134-140) |
| 2 | `auth_service_test.dart` | `registerFallbackValue(GoogleAuthProvider())`; `captureAny` en `signInWithPopup` ⇒ Google con `prompt=select_account`, Apple `providerId=='apple.com'` y scopes `email,name`; nunca `signInWithCredential`; `createIfAbsent` una vez y su falla reportada sin romper; cada code de D2/D3 + `popup-blocked` + account-exists; non-fatal sólo en D3; cancel ⇒ sin `createIfAbsent` |
| 3 | `auth_notifier_test.dart` | cancel ⇒ `AsyncData(previo)`; error ⇒ `AsyncError`; ok ⇒ `AsyncData(user)`; los tests de mobile siguen verdes |
| 4 | `terms_notice_text_test.dart` | en light, el link usa `accentText` |
| 5 | `coach_hub_login_screen_test.dart` | override de `authNotifierProvider` con un fake; tres caminos; aviso antes de los botones; tap ⇒ método correcto, spinner sólo en ese y los otros deshabilitados; `popupBlocked` ⇒ copy; cancel ⇒ sin error; dark + light |
| 6 | `coach_hub_not_allowed_screen_test.dart` (nuevo) | «App Store» y «Play Store» sin taps; mail visible; tap ⇒ `abrirUrl` con `mailto:` y `%20`; sign-out ⇒ `cerrarSesion`; su falla ⇒ `coachHubSignOutError`; dark + light |
| 7 | Guards | `superficie_de_cobro_alumno_test`, los scans de tokens/botón/hover y la paridad de ARB |

Router: sin tests nuevos. `coach_hub_router_redirect_test.dart:251-295,298` ya cubre athlete y sin doc.
Corridas acotadas (no la suite de 40 min). `build_runner` sin combinar `--build-filter` con
`--delete-conflicting-outputs`.

## Migration / Rollout

No hay migración. Deploy del Hub = 🚨 PROD (`main_coach_hub.dart:28-35`). Antes del deploy, la
**consola** (la hace el usuario): Google y Apple habilitados; «one account per email»
revisado; Authorized domains `app.gettreino.com` y `coach-treino-dev.web.app`; en Apple,
Services ID `com.backhaus.treino.signin` con dominio `treino-dev.firebaseapp.com` y Return URL
`https://treino-dev.firebaseapp.com/__/auth/handler`; cliente OAuth web de Google con el mismo
redirect.

**Verificación manual (sólo cuentas del dueño)**, en `app.gettreino.com` y después en `coach-treino-dev.web.app`:
1. Google → dashboard; Console → Users: el uid es el de mobile. Sign-out → Google de nuevo ⇒ aparece el selector.
2. Apple → dashboard; mismo uid que mobile (prueba lo de «mismo Team ⇒ mismo `sub`»). Si es relay, ¿llega el mail del gate?
3. Cerrar el popup ⇒ sin error. Bloquear popups en el navegador ⇒ aparece el copy.
4. Cuenta descartable ⇒ `/not-allowed`: stores nombradas, el mailto abre con asunto legible, sign-out funciona.
5. Email/password sigue igual.

## Open Questions

- [ ] **Spec vs ADR-I18N-002**: REQ-CHW-AUTH-004/008 piden los errores en las 3 ARB. El design los deja en `userMessage` (D5). Reconciliar el spec.
- [ ] **SCENARIO-CHW-AUTH-017** dice «signOut del notifier/servicio». Eso cuelga en web (D9). El spec debería decir «cierra la sesión de Firebase Auth».
- [ ] D2/D3 suman `user-cancelled` e `invalid-credential` a la tabla del proposal. ¿Agregar escenarios al spec?
- [ ] El non-fatal de configuración en web sólo llega a la consola del navegador (`non_fatal.dart:81-85`). ¿Alcanza, o hace falta un evento de Analytics? (fuera de alcance hoy).

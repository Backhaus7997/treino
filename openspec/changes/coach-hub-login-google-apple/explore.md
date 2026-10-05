# Exploration: Coach Hub login con Google y Apple (#1318)

Fecha: 2026-10-05. Base: `origin/main` `40a7d628`. Copia en engram:
`sdd/coach-hub-login-google-apple/explore`.

## Estado actual

### 1. Login del Hub, de punta a punta

- `lib/features/coach_hub/presentation/coach_hub_login_screen.dart:54-57`: solo
  email/password → `authNotifierProvider.notifier.signIn`. Dartdoc `:18-21` cita la
  decisión #2.
- **Decisión #2** (`openspec/changes/coach-hub-bootstrap/propose.md:89`): «Sin Google
  Sign-In en web MVP | `google_sign_in_web` es un paquete separado con setup distinto
  (clientId via meta tag en index.html + OAuth consent). Agrega scope. MVP:
  email/password solamente.» Habla solo de Google; Apple nunca se evaluó. Su premisa
  (`google_sign_in_web` + meta tag) no aplica a `FirebaseAuth.signInWithPopup`.
- Post-login decide el router, no la pantalla: `coachHubRedirect`
  (`lib/app/coach_hub_router.dart:82-251`). Sin sesión → `/login`; perfil cargando →
  espera; sin `users/{uid}` → `/not-allowed` (`:119-123`); `role != trainer` →
  `/not-allowed` (`:125-128`); después gate del mail con código y `/dashboard`.
- **Hallazgo previo al cambio:** `AuthService.signInWithEmail`
  (`lib/features/auth/data/auth_service.dart:135-162`) llama `createIfAbsent`. Un
  usuario sin doc que entra por el Hub con email/password recibe un `users/{uid}`
  athlete sin `termsAcceptedAt`. (Lectura de código; no ejecutado.)

### 2. Google y Apple en mobile

- `signInWithGoogle` (`auth_service.dart:263-315`): `GoogleSignIn.instance.authenticate()`
  (nativo, 7.x) → `signInWithCredential` → `createIfAbsent` best-effort.
- `signInWithApple` (`auth_service.dart:330-377`): nonce sha256 → Apple, nonce crudo →
  Firebase → `createIfAbsent`. `AppleSignInGateway` es solo un seam de test.
- `createIfAbsent` crea `users/{uid}` + `userPublicProfiles/{uid}` con `role: athlete`
  y **sin** `termsAcceptedAt`. El alta por email sí estampa consentimiento
  (`auth_service.dart:100-113`, `kTermsVersion = 3`).
- Para OAuth, el consentimiento se estampa al final de ProfileSetup
  (`terms_consent_provider.dart:33-40`, `profile_setup_notifier.dart:389-392`). Gate de
  edad: `/birth-date` en el router mobile (`lib/app/router.dart:243-248`) +
  `firestore.rules:187-215`. **Ninguno de esos gates existe en el router del Hub**: asume
  que el PF llega completo desde mobile (`coach_hub_router.dart:61-62`).

### 3. Factibilidad web

- Target separado: `lib/main_coach_hub.dart` + `buildCoachHubRouter`.
- Hosting: Vercel en `app.gettreino.com` (`docs/runbook-dominio-y-email.md:169-189`,
  `vercel.json`) y Firebase Hosting `coach-treino-dev` (`firebase.json:41-88`). Cuál usan
  hoy los PFs: **no verificado** (el repo se contradice).
- Paquetes ya resueltos: `firebase_auth` 5.7.0, `google_sign_in` 7.2.0,
  `sign_in_with_apple` 7.x. `FirebaseAuth.signInWithPopup` (web-only) sirve con
  `GoogleAuthProvider()` y `OAuthProvider('apple.com')` **sin paquetes nuevos**.
- `web/index.html` sin scripts GSI/Apple. CSP de `firebase.json:81-82` es
  `Report-Only` (no bloquea). `vercel.json` sin CSP ni COOP.
- `authDomain = treino-dev.firebaseapp.com` (`lib/firebase_options.dart:75`) ≠
  `app.gettreino.com`. Popup funciona cross-origin; redirect sufre el partitioning de
  storage de terceros (doc de Firebase «redirect best practices»).

### 4. Identidad de cuenta

- No hay `linkWithCredential` / `fetchSignInMethodsForEmail` en `lib/`; solo copy para
  `account-exists-with-different-credential` (`auth_failure.dart:47-48,66-67`).
- «One account per email»: **es consola, no se ve desde el repo.**
- Mismo uid mobile/web: Firebase deriva el uid de (proveedor, id del proveedor). Apple:
  `sub` por team; Service ID `com.backhaus.treino.signin`, Team `J66AQRRM96`
  (`docs/roadmap.md:72`), bundle `com.backhaus.treino`. **Inferido, no verificado:**
  mismo team ⇒ mismo `sub` ⇒ mismo uid. Probar con cuenta real.
- El relay «Ocultar mi email» no afecta el uid. Sí puede afectar la llegada del mail del
  gate de código (dominio emisor no registrado en Apple). Inferido.
- El PF nace como athlete en mobile y se promueve con Admin SDK
  (`firestore.rules:260-266`): con el mismo proveedor cae en el mismo doc.

### 5. No-PF en el Hub

- Atleta → `/not-allowed` (test `test/app/coach_hub_router_redirect_test.dart:251-295`).
- Autenticado sin doc → `/not-allowed` (test `:298`).
- Reusar `signInWithGoogle`/`signInWithApple` en el Hub crearía un athlete sin
  consentimiento ni edad → **no reusarlos**.
- Rules (`firestore.rules:293-296`): el create de `users/{uid}` exige `role == athlete`;
  no se puede mintear un trainer desde el cliente.

### 6. Tests y ratchets

- `coach_hub_login_screen_test.dart` cubre solo marca/tema; ningún test impide agregar
  botones sociales.
- Router: `coach_hub_router_redirect_test.dart`, `_resolving_test`, `_shell_test`.
- Auth: `auth_service_test.dart`, `auth_notifier_test.dart`, `auth_failure_test.dart`.
- Scans a revisar antes de la UI: `no_raw_radius_scan_test.dart`,
  `no_raw_font_size_scan_test.dart`, `no_material_button_scan_test.dart`,
  `no_animated_hover_scan_test.dart`, `snackbar_persist_scan_test.dart` (listados por
  nombre, reglas no leídas).

### 7. Consola (lo hace el usuario)

- Firebase Auth → Sign-in method: Google y Apple habilitados; revisar «one account per
  email».
- Authorized domains: `app.gettreino.com` y el dominio de Firebase Hosting si sigue
  activo (si falta: `auth/unauthorized-domain`).
- Apple Developer, Service ID `com.backhaus.treino.signin`: dominio
  `treino-dev.firebaseapp.com` y Return URL
  `https://treino-dev.firebaseapp.com/__/auth/handler`. Inferido de `authDomain`; no
  verificado en consola.
- Google Cloud: cliente web OAuth con redirect
  `https://treino-dev.firebaseapp.com/__/auth/handler`. No verificado.

## Enfoques

| # | Enfoque | Pros | Contras |
|---|---|---|---|
| 1 | Popup + gate de rol del router (solo cliente), método nuevo sin `createIfAbsent` | Sin paquetes, sin CF, reutiliza el gate probado | Usuario Auth huérfano si entra un desconocido; popups bloqueados en algunos navegadores |
| 2 | 1 + bloqueo/limpieza server-side (`beforeSignIn` o callable) | Sin huérfanos en Auth | CF + Identity Platform; más superficie |
| 3 | Redirect | Sin popup | Rompe con authDomain cruzado (storage partitioning); exige authDomain propio |

**Recomendación:** enfoque 1. Métodos web nuevos con seam testeable, sin
`createIfAbsent`; desconocidos y no-PF caen en `/not-allowed`; copy claro para
`account-exists-with-different-credential` y para popup cerrado/bloqueado. Enfoque 2
como follow-up si los huérfanos molestan.

## Riesgos

- Apple web sin Return URL configurado → falla con error de Apple.
- Usuario Auth huérfano para desconocidos (luego mobile le arma el doc con el flujo
  normal; no probado).
- «One account per email» + proveedor distinto → PF varado sin linking.
- Gate de mail con relay de Apple puede no llegar.
- `treino-dev` es producción: probar solo con cuenta propia.
- No hace falta Cloud Function → no se toca `functions/src/subscriptions/`.

## Preguntas abiertas

1. ¿Desconocido (sin `users/{uid}`) ve el `/not-allowed` actual o un copy propio?
2. ¿El Hub deja de crear `users/{uid}` en el login por email?
3. ¿Qué dominio usan hoy los PFs: Vercel o Firebase Hosting?
4. ¿Qué PFs entran con Apple hoy, y con relay o con mail real?
5. ¿«One account per email» está activo? (consola)
6. ¿Linking de cuentas, o alcanza con usar el mismo proveedor?

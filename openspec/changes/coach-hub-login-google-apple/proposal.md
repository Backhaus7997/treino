# Proposal: Coach Hub — login con Google y Apple (#1318)

**Change**: `coach-hub-login-google-apple` · **Branch**: `feat/coach-hub-login-google-apple`
**Date**: 2026-10-05 · **Entrega**: un PR con `size:exception`
**Inputs**: `explore.md` (esta carpeta) · engram `sdd/coach-hub-login-google-apple/decisiones-usuario`

## Intent

Los PFs que se registraron en mobile con Google o Apple no tienen contraseña y hoy
**no pueden entrar al Coach Hub** (solo email/password). La decisión #2 de
`coach-hub-bootstrap` lo descartó por `google_sign_in_web`, premisa que no aplica a
`FirebaseAuth.signInWithPopup`. Éxito: un PF entra al Hub con el mismo proveedor que
usa en mobile y cae en su mismo `users/{uid}`.

## Scope

### In Scope
- Botones Google y Apple en `/login` vía `signInWithPopup` (`GoogleAuthProvider`,
  `OAuthProvider('apple.com')`). Sin paquetes nuevos.
- Los tres caminos del Hub (email, Google, Apple) hacen `createIfAbsent` (athlete). El
  backfill de `signInWithEmail` se queda.
- `TermsNoticeText` en el login del Hub (ver Approach).
- `/not-allowed` con copy nuevo en los 3 ARB. Nombra App Store y Play Store **sin links**
  (la app todavía no está publicada; los links van en un cambio posterior). Contacto por
  `mailto:` y sign-out.
- Manejo de errores del popup (tabla abajo).
- Docs viejos: dartdoc de `coach_hub_login_screen.dart:18-21`,
  `lib/main_coach_hub.dart:46-48`, y nota de «superada» en la fila #2 de
  `openspec/changes/coach-hub-bootstrap/propose.md`.

### Out of Scope
- Onboarding en el Hub para un PF promovido con perfil incompleto → **SDD aparte**
  (follow-up b). **Restricción operativa:** hasta entonces, no promover perfiles incompletos.
- Consentimiento y edad en web: los cubren los gates de mobile.
- Linking de cuentas (`linkWithCredential`). **Decidido afuera** (usuario, 2026-10-05).
- Links a las stores, hasta que la app esté publicada.
- Redirect flow, Cloud Functions, `beforeSignIn`, `functions/src/subscriptions/`, Mercado Pago.

## Capabilities

### New Capabilities
- None

### Modified Capabilities
- `coach-hub`: login acepta Google/Apple por popup y crea el doc athlete en los tres
  caminos; `/not-allowed` cambia de copy (nombra las stores sin links) y suma contacto.

## Approach

- **Dónde viven los métodos:** dos métodos web nuevos en `AuthService`, que llaman a
  `_auth.signInWithPopup(...)` y después a `createIfAbsent` con `_reportarAltaFallida`,
  igual que mobile. **El seam ya existe:** `FirebaseAuth` llega inyectado y
  `auth_service_test.dart` ya tiene `MockFirebaseAuth` (mocktail). Se testea sin
  navegador. Un gateway aparte sería un segundo seam para la misma llamada.
- **Notifier:** dos métodos con la misma restauración silenciosa ante cancelación que
  `signInWithGoogle`/`signInWithApple` (`auth_notifier.dart:36-61`).
- **Router:** sin cambios. Sin doc o con rol distinto de trainer ya van a `/not-allowed`.
- **`TermsNoticeText`: SÍ.** El Hub ahora crea cuentas por OAuth. Es el mismo motivo
  por el que mobile lo muestra (#434): el usuario tiene que saberlo antes de tocar el botón.
- **Contacto:** `kLegalContactEmail` (`treino@gettreino.com`) existe; se reusa por
  `mailto:` con `url_launcher` (ya es dependencia).

| Error (code de FlutterFire; los strings exactos se confirman en design) | Comportamiento |
|---|---|
| `popup-closed-by-user`, `cancelled-popup-request` | `signInCancelled`, restauración silenciosa |
| `popup-blocked` | Failure nueva: «Tu navegador bloqueó la ventana. Permití ventanas emergentes y probá de nuevo» |
| `account-exists-with-different-credential` | Copy accionable: «Entrá con el método que usaste al registrarte» |
| `unauthorized-domain`, `operation-not-allowed` | Failure nueva: «Este método no está disponible. Entrá con email o escribinos» + reporte non-fatal (es un error de configuración nuestro) |

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `lib/features/auth/data/auth_service.dart` | Modified | Métodos popup |
| `lib/features/auth/application/auth_notifier.dart` | Modified | Métodos con restauración ante cancelación |
| `lib/features/auth/domain/auth_failure.dart` | Modified | Codes y copy nuevos (afecta también el copy de mobile) |
| `lib/features/coach_hub/presentation/coach_hub_login_screen.dart` | Modified | Botones + aviso de términos |
| `lib/features/coach_hub/presentation/coach_hub_not_allowed_screen.dart` | Modified | Copy (stores sin links), contacto |
| `lib/l10n/intl_{en,es,es_AR}.arb` | Modified | Strings nuevos |
| `lib/main_coach_hub.dart` | Modified | Solo el comentario |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Apple web sin Return URL / Services ID en la consola | Med | Checklist de consola antes del deploy |
| uid de Apple distinto entre web y mobile (inferido: mismo Team ⇒ mismo `sub`) | Low | Verificación manual con la cuenta del dueño |
| «One account per email» deja a un PF varado sin linking | Med | Copy accionable. Linking fuera de alcance (decidido) |
| El mail del gate de código no llega al relay de Apple (inferido) | Med | Verificarlo en el plan manual |
| Desconocidos crean docs athlete desde la web | Med | Aceptado (decisión 2); mobile completa el onboarding |
| Navegador que bloquea popups | Low | Copy de `popup-blocked` |

## Rollback Plan

Revertir el PR y redeployar el build anterior del Hub (🚨 PROD). Los proveedores de la
consola quedan prendidos porque mobile ya los usa. Los docs que creó la web son athlete
comunes, iguales a los del `createIfAbsent` de mobile: no hace falta limpiar nada.

## Dependencies (consola, lo hace el usuario; nada verificado desde el repo)

- Firebase Auth: Google y Apple habilitados. En Apple, cargar el Services ID
  `com.backhaus.treino.signin`. Revisar «one account per email».
- Authorized domains: `app.gettreino.com` (el dominio principal) **y**
  `coach-treino-dev.web.app`. Los dos están vivos (lo confirmó el usuario).
- Apple Developer, Services ID: dominio `treino-dev.firebaseapp.com`, Return URL
  `https://treino-dev.firebaseapp.com/__/auth/handler`.
- Google Cloud, cliente OAuth web: el mismo redirect URI.
- Contenido: no hace falta. Las stores van sin links y el contacto es
  `kLegalContactEmail`. El usuario confirmó que el mail alcanza.

## Success Criteria

- [ ] Con la cuenta del dueño, en producción: Google y Apple entran al dashboard y el
  uid coincide con el de mobile (Firebase Console → Users).
- [ ] Cerrar el popup no muestra error. Un popup bloqueado muestra el copy.
- [ ] Tests: una cuenta nueva por popup crea `users/{uid}` athlete y llega al
  `/not-allowed` nuevo, con las stores nombradas, contacto y sign-out. En prod, solo con una cuenta
  descartable del dueño.
- [ ] El login por email sigue igual.
- [ ] Tests nuevos de service, notifier y pantallas en verde; scans de UI en verde.

## Decisiones del usuario (2026-10-05)

- Sin links a las stores: la app todavía no se puede descargar. El cartel las nombra.
- Contacto «quiero ser entrenador»: `treino@gettreino.com` por `mailto:` alcanza.
- Dominios: los dos están vivos. El plan es que los PFs entren por `app.gettreino.com`.
- Linking de cuentas: fuera de alcance.

# Tasks: coach-hub-login-google-apple (#1318 — login del Coach Hub con Google y Apple)

Inputs: `proposal.md`, `specs/coach-hub/spec.md`, `design.md` (D1..D13). Strict TDD: cada
tarea de implementación va precedida de su RED (visto fallar por la razón correcta), luego
GREEN, luego refactor si hace falta.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines (a mano) | ~+330 / −60 producción, ~+650 tests, ~+60 ARB, ~+10 docs = ~1100 |
| Generated (no se revisa a mano) | `auth_failure.freezed.dart` ≈ +400, `app_l10n*.dart` ≈ +50 |
| 400-line budget risk | High |
| Chained PRs recommended | No (decisión ya tomada) |
| Delivery strategy | exception-ok |
| Decision needed before apply: | No — un solo PR con `size:exception` |

Chained PRs recommended: No
400-line budget risk: High
Decision needed before apply: No

Verdict: supera 400 líneas, pero el usuario decidió un PR único con `size:exception`
(`delivery_strategy: exception-ok`). Se mitiga con 7 batches = 7 work-unit commits
revisables por separado dentro del mismo PR.

### Conflictos spec vs design

Ninguno bloqueante. El spec ya incorpora las reconciliaciones que el design dejaba abiertas:
errores hardcodeados en es-AR fuera de ARB (REQ-004/008 = D5), sign-out directo de Firebase
(SCENARIO-017 = D9), y escenarios 026/027 para `user-cancelled`/`invalid-credential`
(D2/D3). Si apply encuentra una divergencia técnica, gana design; si es de comportamiento,
gana spec. Pendiente aceptado: non-fatal en web solo llega a la consola (fuera de alcance).

## Reglas para apply (todas las batches)

- Gates por batch: `flutter analyze lib test` acotado (NUNCA `flutter analyze` completo desde
  un subagente), `dart format` SOLO en archivos tocados, correr SOLO los tests afectados.
- Si se toca freezed: `dart run build_runner build --delete-conflicting-outputs` SIN
  `--build-filter`. Tras editar ARB: `flutter gen-l10n`.
- Techos de scans: MEDIR corriendo el test, no calcular.
- Control negativo de guards/scans: commitear ANTES de correrlo; revertir con commit/`git
  revert`, no con `git checkout <archivo>`; confirmar que la mutación entró.
- Commits convencionales en español, sin Co-Authored-By ni atribución de IA.
- NO tocar `functions/`, `firestore.rules`, `coach_hub_router.dart`, `pubspec.yaml`
  (REQ-CHW-AUTH-009).
- Invariante de popup: ningún `await` entre `onPressed` y `signInWithPopup`.

## Orden y paralelismo

B1 → B2 → B3 (secuenciales: dominio → servicio → notifier). B4 y B5 son independientes de
B1-B3 (pueden ir en paralelo con ellos). B6 depende de B3, B4 y de las claves ARB (B5 define
las de `/not-allowed`; B6 suma las del login). B7 al final.

---

## Batch 1 — AuthFailure: variantes y copy (dominio)

Commit: `feat(auth): AuthFailure suma popupBlocked y providerUnavailable`
Cubre: REQ-CHW-AUTH-004 (copy), SCENARIO-CHW-AUTH-012 (parte F), 013, 014 (F), 027 (F), 028.

- [x] 1.1 **RED** — `test/features/auth/domain/auth_failure_test.dart`: tests de
  `AuthFailure.popupBlocked().userMessage`, `AuthFailure.providerUnavailable().userMessage`
  (copy exacto de design) y nuevo copy de `accountExistsWithDifferentCredential` (actualizar
  el test existente de ~:134-140). Agregar control: `fromFirebase('invalid-credential')`
  sigue siendo `wrongPassword` y `fromFirebase('operation-not-allowed')` NO es
  `providerUnavailable` (SCENARIO-027 parte F, SCENARIO-028). Ver rojo por símbolo/copy
  inexistente.
- [x] 1.2 **GREEN** — `lib/features/auth/domain/auth_failure.dart`: variantes freezed
  `popupBlocked()` y `providerUnavailable()`, `userMessage` hardcodeado es-AR; nuevo copy de
  account-exists («Ya tenés una cuenta con ese email. Entrá con el método que usaste al
  registrarte»). NO tocar `fromFirebase` (D1). Regenerar con
  `dart run build_runner build --delete-conflicting-outputs`.
- [x] 1.3 Buscar y actualizar cualquier test de mobile que cite el copy viejo de
  account-exists (`rg` en `test/`). Cubre SCENARIO-013 (mismo mensaje en mobile).
- [x] 1.4 **GATE** — correr `auth_failure_test.dart`, `auth_failure_exclusion_test.dart`
  (ADR-I18N-002: el copy NO va a ARB) y los tests que citaban el copy. `flutter analyze lib
  test` acotado. `dart format` solo en tocados.
- [x] 1.5 **Control negativo** (tras commit): mover el copy de `popupBlocked` a una clave ARB
  y confirmar que `auth_failure_exclusion_test.dart` se pone rojo; revertir.

## Batch 2 — AuthService: popup Google/Apple + mapeo de errores

Commit: `feat(auth): AuthService entra por popup con Google y Apple (web)`
Cubre: REQ-CHW-AUTH-001/002/003/004; SCENARIO-CHW-AUTH-001, 002, 005, 006, 007, 009, 010,
014, 026, 027, 028.
Depende de: B1.

- [x] 2.1 **RED** — `test/features/auth/data/auth_service_test.dart` (mocktail,
  `registerFallbackValue(GoogleAuthProvider())`, `captureAny` en `signInWithPopup`):
  - 001: Google ⇒ `GoogleAuthProvider` con custom param `prompt=select_account`; nunca
    `signInWithCredential`.
  - 002: Apple ⇒ `OAuthProvider` con `providerId == 'apple.com'`, scopes `email`,`name`;
    nunca `signInWithCredential`.
  - 005: éxito ⇒ `createIfAbsent` una vez con ese usuario; resultado = usuario (Google y
    Apple).
  - 006: `createIfAbsent` lanza ⇒ no propaga, usuario autenticado, se invoca
    `_reportarAltaFallida` (reporte non-fatal con la causa).
  - 007: no tocar el test existente de backfill de `signInWithEmail`; debe seguir verde.
  - 009/010/026: `popup-closed-by-user`, `cancelled-popup-request`, `user-cancelled` ⇒
    `signInCancelled`; sin `createIfAbsent`; sin non-fatal.
  - `popup-blocked` ⇒ `AuthFailure.popupBlocked`, sin reporte.
  - `account-exists-with-different-credential` ⇒ `accountExistsWithDifferentCredential`,
    sin reporte.
  - 014/027: `unauthorized-domain`, `operation-not-allowed`, `invalid-credential` ⇒
    `providerUnavailable` + non-fatal con
    `reason: 'AuthService.$camino: proveedor no disponible (${e.code})'`; usuario no
    autenticado.
  - 028: code desconocido ⇒ fallback `AuthFailure.fromFirebase`.
  Ver rojo (métodos inexistentes).
- [x] 2.2 **GREEN** — `lib/features/auth/data/auth_service.dart`: `signInWithGooglePopup()`
  y `signInWithApplePopup()` (camino `'signInWithGooglePopup'`/`'signInWithApplePopup'`),
  helper privado `_signInWithPopup`, `_failureFromPopup(e, st, camino)` con cancel set D2 y
  config set D3, `createIfAbsent(uid, email ?? '')` best-effort con `_reportarAltaFallida`.
  Google: `GoogleAuthProvider()..setCustomParameters({'prompt':'select_account'})`. Apple:
  `OAuthProvider('apple.com')..addScope('email')..addScope('name')`. Dartdoc «web-only», sin
  `assert(kIsWeb)`. Sin `await` previo a `signInWithPopup`. No reutilizar
  `signInWithGoogle`/`signInWithApple`.
- [x] 2.3 **REFACTOR** — deduplicar el try/catch entre ambos métodos solo si sigue
  legible; los tests de mobile del archivo siguen verdes.
- [x] 2.4 **GATE** — correr `auth_service_test.dart` completo; analyze acotado; format.
- [x] 2.5 **Control negativo** (tras commit): quitar `invalid-credential` del set de config
  y confirmar rojo en el test 027; revertir.

## Batch 3 — AuthNotifier: métodos popup y helper

Commit: `feat(auth): AuthNotifier expone el login por popup con restauración silenciosa`
Cubre: REQ-CHW-AUTH-001/003; SCENARIO-CHW-AUTH-011 (parte N).
Depende de: B2.

- [x] 3.1 **RED** — `test/features/auth/application/auth_notifier_test.dart`: para
  `signInWithGooglePopup` y `signInWithApplePopup`: cancel ⇒ estado final = `AsyncData(previo)`
  (no `AsyncError`); error ⇒ `AsyncError`; ok ⇒ `AsyncData(user)`.
- [x] 3.2 **GREEN** — `lib/features/auth/application/auth_notifier.dart`: helper privado
  `_socialSignIn(Future<User> Function())` (D8) usado por los 4 métodos sociales; dos
  métodos nuevos. Sin `await` previo al servicio.
- [x] 3.3 **GATE** — correr `auth_notifier_test.dart` completo (blindan el refactor de
  mobile, `:238+`); analyze acotado; format.

## Batch 4 — TermsNoticeText: contraste de links en light

Commit: `fix(auth): los links de TermsNoticeText usan accentText para contraste en light`
Cubre: SCENARIO-CHW-AUTH-030 (REQ-CHW-AUTH-006, D13). Independiente.

- [x] 4.1 **RED** — `test/features/auth/presentation/widgets/terms_notice_text_test.dart`:
  en light los links usan `palette.accentText`; en dark el color resultante no cambia.
  Ver rojo (hoy usa `accent`).
- [x] 4.2 **GREEN** — `terms_notice_text.dart:68-71`: `accent` → `accentText`.
- [x] 4.3 **GATE** — test del widget + `coach_hub_login_screen_test.dart` y el test de login
  mobile que use `TermsNoticeText` (revisar los de `coach_hub_login_screen_test.dart:71-80`
  que miden contraste); analyze acotado.

## Batch 5 — `/not-allowed`: copy por ARB, contacto, seams, guards

Commit: `feat(coach-hub): /not-allowed nombra las stores y ofrece contacto por mailto`
Cubre: REQ-CHW-AUTH-005, 008; SCENARIO-CHW-AUTH-015, 016, 017, 018, 019, 020, 023, 024, 029.
Independiente de B1-B3.

- [ ] 5.1 **RED (guard)** — `test/features/paywall/superficie_de_cobro_alumno_test.dart`:
  sumar `coach_hub_not_allowed_screen.dart` a `permitidos` («sólo web: `mailto:` de
  contacto, no compra»). Verlo pasar es trivial; el rojo real está en 5.2 (la pantalla aún
  no abre URL). SCENARIO-029 se completa en 5.6.
- [ ] 5.2 **RED** — nuevo `test/features/coach_hub/presentation/coach_hub_not_allowed_screen_test.dart`
  (dark y light):
  - 015: aparece «App Store» y «Play Store»; ningún widget tappable de link a store.
  - 016: tap en contacto ⇒ `abrirUrl` recibe `Uri` `mailto` con path `kLegalContactEmail` y
    asunto con `%20` (no `+`); `kLegalContactEmail` visible como texto.
  - 017: tap «Cerrar sesión» ⇒ se invoca `cerrarSesion` doblado; no se usa
    `AuthService.signOut`/`AuthNotifier.signOut` (sin overrides del notifier, monta limpio);
    si `cerrarSesion` falla ⇒ `coachHubSignOutError`.
  Ver rojo.
- [ ] 5.3 ARB — `lib/l10n/intl_en.arb`, `intl_es.arb`, `intl_es_AR.arb`:
  `coachHubNotAllowedTitle`, `coachHubNotAllowedBody`, `coachHubNotAllowedContactPrompt`,
  `coachHubNotAllowedContactCta`, `coachHubNotAllowedMailSubject` (es_AR en voseo). Correr
  `flutter gen-l10n`. Reusar `coachHubSignOutError` existente.
- [ ] 5.4 **GREEN** — `coach_hub_not_allowed_screen.dart`:
  `CoachHubNotAllowedScreen({abrirUrl = launchUrl, cerrarSesion = _cerrarSesionFirebase})`
  con tear-offs const (D10); mailto con
  `Uri(scheme:'mailto', path: kLegalContactEmail, query:'subject=${Uri.encodeComponent(..)}')`
  (no `queryParameters`); sign-out directo `FirebaseAuth.instance.signOut()` (D9); tokens
  `AppSpacing`/`AppTextSize`/`AppPalette.of`/`TreinoButton`/`TreinoIcon`; sin hex, sin
  Phosphor directo, sin SnackBar persistente fuera de convención. El router la sigue
  construyendo `const` (sin tocar el router).
- [ ] 5.5 **Router (verificación, sin código)** — correr
  `test/app/coach_hub_router_redirect_test.dart` sin modificar: 018 (athlete, `:251-295`),
  019 (sin doc, `:298`), 020 (sin shell) y 008 (athlete nuevo ⇒ `/not-allowed`). Si falta
  alguna ruta de 018 (`/dashboard`, `/upload-plan`, `/pagos`, `/login`), EXTENDER el test
  (no el router).
- [ ] 5.6 **Scans y paridad** — correr `superficie_de_cobro_alumno_test.dart` (029),
  `no_raw_font_size_scan_test`, `no_off_scale_spacing_scan_test`, `no_raw_radius_scan_test`,
  `no_material_button_scan_test`, `no_animated_hover_scan_test`,
  `snackbar_persist_scan_test`, test de paridad de ARB y `auth_failure_exclusion_test`
  (023, 024). Si `/not-allowed` quedó sin literales, sacarla de las allowlists de font-size
  y spacing y bajar los techos con el valor MEDIDO.
- [ ] 5.7 **Control negativo** (tras commit): (a) agregar un `fontSize: 13` crudo a
  `coach_hub_not_allowed_screen.dart` y confirmar que el scan se pone rojo; (b) sacar la
  pantalla de `permitidos` y confirmar que el guard de URLs falla (vía `launchUrl`);
  confirmar que cada mutación efectivamente entró; revertir.
- [ ] 5.8 **GATE** — tests de 5.2, router, scans; analyze acotado; format.

## Batch 6 — Login del Hub: botones, aviso de términos, estado por botón

Commit: `feat(coach-hub): el login del Hub entra con Google y Apple`
Cubre: REQ-CHW-AUTH-001/003/004/006/008; SCENARIO-CHW-AUTH-003, 011 (parte L), 012 (parte L),
021, 024.
Depende de: B3, B4 (y B5 solo por convención de ARB).

- [ ] 6.1 **RED** — `test/features/coach_hub/presentation/coach_hub_login_screen_test.dart`
  (override de `authNotifierProvider` con un fake; dark y light):
  - 003: se ven formulario email, botón Google y botón Apple; tap en cada uno llama
    `signInWithGooglePopup`/`signInWithApplePopup`; mientras uno está en curso solo ese
    muestra spinner y los otros dos (incluido INGRESAR) quedan deshabilitados.
  - 021: `TermsNoticeText` presente y antes de los botones Google/Apple en el árbol.
  - 011 (L): cancel ⇒ sin SnackBar, sin texto de error, sin spinner colgado.
  - 012 (L): `popupBlocked` ⇒ se muestra el copy de ventanas emergentes, no el genérico.
  - tras éxito la pantalla NO navega por sí misma.
  Los tests existentes (sin overrides, `:12-24`, contraste `:71-80`) siguen verdes (D11).
  Ver rojo.
- [ ] 6.2 ARB — claves de pantalla del login: botones «Google»/«Apple» (verificar si ya
  existen claves de mobile reutilizables antes de crear nuevas) y divisor «O CONTINUÁ CON»
  en los 3 ARB, misma clave; `flutter gen-l10n`.
- [ ] 6.3 **GREEN** — `coach_hub_login_screen.dart`: debajo de INGRESAR, divisor →
  `TermsNoticeText` → fila de `TreinoButton(variant: secondary, icon: TreinoIcon.googleLogo
  / appleLogo)` (D12); estado local `_Metodo? _enCurso` (email/google/apple) sin
  `ref.watch(authNotifierProvider)` en el build (D11); errores vía el mecanismo existente de
  la pantalla (sin SnackBar persistente); sin `await` entre `onPressed` y el notifier;
  tokens del kit, sin literales nuevos de `fontSize`/`Radius.circular`.
- [ ] 6.4 **GATE** — test de login completo, `terms_notice_text_test.dart`, los cinco scans
  de UI de SCENARIO-024, paridad ARB, `auth_failure_exclusion_test.dart`; si los scans
  cambiaron de conteo por literales preexistentes, medir (no calcular); analyze acotado;
  format.
- [ ] 6.5 **Control negativo** (tras commit): insertar un `await Future<void>.delayed(...)`
  entre `onPressed` y el notifier solo si el test de orden síncrono lo detecta; si el test
  no lo puede detectar, documentarlo como cubierto solo por verificación manual (paso 3 del
  checklist de usuario). Revertir.

## Batch 7 — Docs y decisión superada

Commit: `docs(coach-hub): el login del Hub ya no es solo email/password`
Cubre: REQ-CHW-AUTH-007; SCENARIO-CHW-AUTH-022, 025.

- [ ] 7.1 Dartdoc de `lib/features/coach_hub/presentation/coach_hub_login_screen.dart:18-21`:
  reemplazar «email/password solamente» por los tres caminos y el porqué del popup (sin
  afirmaciones nuevas sin evidencia; AGENTS.md §11.1: citar design/evidencia).
- [ ] 7.2 Comentario de `lib/main_coach_hub.dart:46-48`: popup, y por qué el sign-out de
  `/not-allowed` no pasa por `AuthService` (`GoogleSignIn.signOut()` espera un
  `initialize()` que el Hub nunca hace). Solo comentario, cero cambio de código.
- [ ] 7.3 `openspec/changes/coach-hub-bootstrap/propose.md:89` (fila decisión #2): agregar
  nota «Superada por coach-hub-login-google-apple (#1318)».
- [ ] 7.4 **Verificación de diff (025)** — `git diff --stat main...HEAD`: no aparecen
  `functions/`, `firestore.rules`, `coach_hub_router.dart`, `pubspec.yaml`. `rg -i "solo
  email|email/password solamente"` en los tres archivos: sin afirmaciones vigentes falsas.
- [ ] 7.5 **GATE final de apply** — `flutter analyze lib test` acotado a los directorios
  tocados, `dart format --set-exit-if-changed` solo sobre los archivos tocados, y corrida
  agregada SOLO de los tests listados en B1-B6 (no la suite completa de ~40 min).

---

## Para el USUARIO (no lo ejecuta apply)

### Checklist de consola (antes del deploy; todo en `treino-dev` = PRODUCCIÓN)

- [ ] Firebase Auth → Sign-in method: Google habilitado; Apple habilitado con el Services ID
  `com.backhaus.treino.signin`. Revisar «one account per email».
- [ ] Firebase Auth → Authorized domains: `app.gettreino.com` y `coach-treino-dev.web.app`.
- [ ] Apple Developer → Services ID: dominio `treino-dev.firebaseapp.com`, Return URL
  `https://treino-dev.firebaseapp.com/__/auth/handler`.
- [ ] Google Cloud → cliente OAuth web: el mismo redirect URI.
- [ ] Restricción operativa: no promover PFs con perfil incompleto hasta el SDD de
  onboarding en el Hub.

### Verificación manual en producción (SOLO cuentas del dueño; SCENARIO-CHW-AUTH-004, 022)

Primero `app.gettreino.com`, después `coach-treino-dev.web.app`:

1. Google ⇒ dashboard. Firebase Console → Users: el uid coincide con el de mobile. Sign-out
   y Google de nuevo ⇒ aparece el selector de cuenta.
2. Apple ⇒ dashboard; mismo uid que mobile (prueba «mismo Team ⇒ mismo `sub`»). Con relay de
   «Ocultar mi email»: ¿llega el mail del gate de código? Confirmar también el supuesto de
   `invalid-credential` (no debería aparecer; si aparece, es configuración).
3. Cerrar el popup ⇒ sin error. Bloquear popups en el navegador ⇒ aparece el copy de
   ventanas emergentes (y el popup se abre sin bloqueo en el uso normal: confirma que no hay
   `await` previo).
4. Cuenta descartable del dueño ⇒ `/not-allowed`: App Store y Play Store nombradas sin
   links, el `mailto:` abre con asunto legible, la dirección se ve como texto, «Cerrar
   sesión» funciona (no se cuelga).
5. Email/password sigue entrando igual.
6. Un PF con otro proveedor ya registrado con el mismo email ⇒ copy accionable de
   account-exists.
7. Rollback si algo falla: revertir el PR y redeployar el build anterior del Hub.

## Trazabilidad REQ → Batch

| REQ | SCENARIOs | Batch |
|---|---|---|
| REQ-CHW-AUTH-001 | 001, 002, 003, 004 | B2, B3, B6, manual |
| REQ-CHW-AUTH-002 | 005, 006, 007, 008 | B2, B5 (router) |
| REQ-CHW-AUTH-003 | 009, 010, 011, 026 | B2, B3, B6 |
| REQ-CHW-AUTH-004 | 012, 013, 014, 027, 028 | B1, B2, B6 |
| REQ-CHW-AUTH-005 | 015-020, 029 | B5 |
| REQ-CHW-AUTH-006 | 021, 030 | B4, B6 |
| REQ-CHW-AUTH-007 | 022 | B7 |
| REQ-CHW-AUTH-008 | 023, 024 | B1, B5, B6 |
| REQ-CHW-AUTH-009 | 025 | B7 |

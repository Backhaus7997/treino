# Proposal: coach-hub-bootstrap

**Change**: Fase 5 · Etapa 7 — Coach Hub web bootstrap
**Branch**: `feat/coach-hub-bootstrap`
**Owner**: Dev B (acuerdo con Dev A — handoff 2026-05-26)
**Date**: 2026-05-26
**Depends on**: Etapa 1 (✅ #54) — `UserProfile` con `role`. Auth flow de Fase 1 (✅ ya en main). No bloquea Etapa 6 (Agenda) ni Etapa 8 (Excel — viene encima de Coach Hub).

---

## 1. Why

Hasta hoy TREINO es solo mobile (Android + iOS). El Coach Hub web es el **segundo target del producto** y la pieza arquitectónica más grande de Fase 5: un Flutter Web app dedicado para PFs profesionales, con su propio entry point, routing acotado al rol trainer, y deploy a Firebase Hosting.

Esta etapa NO incluye features finales (editor de planes, uploader Excel — esos son Etapa 8). Es el **bootstrap**: habilitar el target, configurar Firebase Web, deploy inicial, gating de rol, y una landing dashboard mínima que confirme que el flujo end-to-end funciona.

Sin este bootstrap, Etapa 8 (Excel import) no puede arrancar.

---

## 2. What

### Trabajo de código (este PR)

#### Bootstrap del target Web
- Habilitar Flutter Web platform: `flutter create . --platforms=web` → genera `web/` con `index.html`, `manifest.json`, favicons, `main.dart.js` entrypoint.
- Personalizar `web/index.html`: título "TREINO Coach Hub", meta tags, splash mínimo, color de fondo `#0A0A0A` (palette.bg de la app).
- Configurar Firebase Web: nueva entrada en `firebase_options.dart` con la web app credentials (regenerado via `flutterfire configure --platforms=web`).

#### Entry point separado
- `lib/main_coach_hub.dart`: nuevo entry point. `flutter run -t lib/main_coach_hub.dart -d chrome` y `flutter build web -t lib/main_coach_hub.dart` apuntan acá.
- `lib/app/coach_hub_app.dart`: equivalente web del `TreinoApp` mobile. Mismo tema (`AppTheme.dark()`), pero router distinto (sin bottom bar, sin Coach tab, etc.).
- `lib/app/coach_hub_router.dart`: GoRouter dedicado para web. Rutas:
  - `/` → `/dashboard` (default)
  - `/login` → email/password login (sin Google Sign-In en MVP — ese es Etapa 7.5 o follow-up)
  - `/dashboard` → `CoachHubDashboardScreen` (role-guarded)
  - `/not-allowed` → info page para athletes que entraron por accidente

#### Auth + role gating
- Reusa `firestoreProvider`, `authStateChangesProvider`, `userProfileProvider` del proyecto existente — todo en `lib/features/` sigue siendo source único de verdad.
- Redirect logic en el router:
  - No auth → `/login`
  - Auth + `role != 'trainer'` → `/not-allowed`
  - Auth + `role == 'trainer'` → `/dashboard`
- El gating es **client-side** (UX). El **server-side** (Firestore rules) ya existe — las rules de `trainer_links/**`, `routines/**` con `assignedBy`, etc. son la verdadera defensa. El gating del router solo evita confusión.

#### Landing dashboard mínimo
- `lib/features/coach_hub/presentation/coach_hub_dashboard_screen.dart`: pantalla simple. Header con "BIENVENIDO, [DisplayName]" + lista placeholder "Tus alumnos" (consume `linksForTrainerProvider` del coach-foundations).
- Sin acciones complejas — solo lectura. Crear plan + uploader son Etapa 8.
- Sign-out button.

#### Firebase Hosting setup
- Agregar `hosting:` block a `firebase.json` con target `coach-treino-dev` apuntando a `build/web/`.
- Script `npm run` o doc en `scripts/deploy_coach_hub.md` con comandos:
  - `flutter build web -t lib/main_coach_hub.dart`
  - `firebase deploy --only hosting:coach-treino-dev`

### Trabajo manual (vos)

Pre-merge, necesito que ejecutes en Firebase Console:

| # | Acción | Output esperado |
|---|---|---|
| 1 | Agregar **Web app** al proyecto `treino-dev` (Settings → "Add app" → Web) | `firebaseConfig` con `apiKey, authDomain, projectId, storageBucket, messagingSenderId, appId` |
| 2 | Crear **Firebase Hosting site** llamado `coach-treino-dev` | URL deploy `https://coach-treino-dev.web.app` reservada |
| 3 | Agregar `localhost:5000` y `coach-treino-dev.web.app` a **Auth → Authorized domains** | Login en web habilitado |
| 4 | (Opcional) Instalar `firebase-tools` global si no lo tenés: `npm install -g firebase-tools` | CLI para deploy disponible |

Después de los pasos 1-3, corro `flutterfire configure --platforms=web` (o lo corrés vos, ambos sirve) — regenera `firebase_options.dart` con las web credentials.

### Tests
- Smoke test del routing: athlete entra a `/dashboard` → redirect a `/not-allowed`. Trainer entra → ve `/dashboard`.
- Smoke test del role guard provider (existe? consume userProfile?).
- NO E2E web tests — costoso y no priority MVP.

---

## 3. Trade-offs lockeados (5 decisiones)

| # | Decisión | Rationale |
|---|---|---|
| 1 | **Multi-entry-point** (`main_coach_hub.dart` separado) vs single entry con feature flag | Multi-entry es más limpio: `flutter run -t` selecciona target, build outputs distintos, dependencias separadas. Single entry con flag obligaría a meter web-specific code en el mobile bundle. Trade-off: 2 entry points a mantener. Aceptable porque el código compartido (features/) es 95% — solo cambia el shell. |
| 2 | **Sin Google Sign-In en web MVP** | `google_sign_in_web` es un paquete separado con setup distinto (clientId via meta tag en index.html + OAuth consent). Agrega scope. MVP: email/password solamente. Si hay demanda, Google Sign-In se agrega en Etapa 7.5 o follow-up. |
| 3 | **Role gating client-side via router redirect** (NO seguridad real) | Las Firestore rules ya son la fuente de verdad de seguridad. El router redirect es UX (athletes no ven menús que no pueden tocar). Si alguien bypasea el redirect, las rules deniegan al backend. |
| 4 | **`AppTheme.dark()` sin breakpoints responsivos para MVP** | El Coach Hub se diseña primero para desktop (1200+px). En MVP no tunneamos para mobile/tablet web — usamos el mismo layout que mobile (centrado, max-width 600px). Iteración futura agrega media queries si producto valida que PFs usan el hub desde tablet. |
| 5 | **Hosting site: `coach-treino-dev` (dev only)**, sin prod en este PR | Prod requiere decisión de naming + DNS de la organización. Para MVP de Etapa 7, dev hosting alcanza. Prod hosting (`coach.treino.app`?) se decide en Fase 6 cuando arme la beta. |

---

## 4. Out of scope (deferrables a Etapa 8 o Fase 6)

| Item | Lands en |
|---|---|
| Editor de planes (RoutineEditorScreen para web) | Etapa 8 |
| Uploader de Excel + preview | Etapa 8 |
| Cloud Function `parsePlan` | Etapa 8 |
| Production hosting + dominio propio | Fase 6 |
| Localización i18n del Coach Hub | Fase 6 |
| Responsive breakpoints (desktop / tablet / mobile web) | Iteración futura si producto valida la necesidad |
| Google Sign-In en web | Etapa 7.5 o follow-up |
| Analytics + Crashlytics para web | Fase 6 |

---

## 5. Risks

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | `flutterfire configure --platforms=web` puede sobrescribir `firebase_options.dart` y romper config existente de android/ios | Antes de correr: backup del file. Después: diff carefully. Si rompe, restaurar manualmente las secciones android + ios. |
| 2 | `google_sign_in` plugin actual NO soporta web → el `lib/main.dart` mobile podría fallar de forma weird si compila a web por accidente | El multi-entry-point separa esto: `main_coach_hub.dart` NO importa `google_sign_in`. `main.dart` mobile sigue funcionando. Verificar con `flutter build web -t lib/main_coach_hub.dart` que ese target compila clean. |
| 3 | Firebase Hosting deploy puede fallar la primera vez por permisos o falta de billing habilitado en GCP | Pre-flight check: pedir confirmación de billing en GCP antes del deploy. Si falla, retry con `firebase login --reauth`. |
| 4 | Bundle size del Flutter Web app puede ser grande (>5 MB) — load time lento en primer visit | Aceptable para MVP (PFs lo usan desde desktop con buena conexión). Optimization (deferred imports, tree shaking) en Fase 6. |
| 5 | Algunas dependencias mobile-only en pubspec (geolocator, image_picker, flutter_map) podrían no compilar para web | Marcarlas explícitamente en `pubspec.yaml` o aislarlas detrás de `kIsWeb` guards. La mayoría tiene fallback web — flutter_map sí funciona. geolocator también. image_picker funciona con limitaciones. |

---

## 6. Success criteria

- [ ] `flutter run -t lib/main_coach_hub.dart -d chrome` levanta el app en localhost sin errores
- [ ] No auth → router redirige a `/login`
- [ ] Email/password login funcional
- [ ] Athlete autenticado entrando a `/dashboard` → redirige a `/not-allowed` con copy explicativo
- [ ] Trainer autenticado → ve `/dashboard` con su displayName + lista placeholder de alumnos
- [ ] Sign-out funciona y devuelve a `/login`
- [ ] `flutter build web -t lib/main_coach_hub.dart` compila sin errores
- [ ] `firebase deploy --only hosting:coach-treino-dev` despliega correctamente
- [ ] `https://coach-treino-dev.web.app` carga el app
- [ ] `flutter analyze` 0 issues
- [ ] Suite full passing (incluyendo tests nuevos del routing/guard)
- [ ] `lib/main.dart` mobile sigue funcionando (no regresión)

---

## 7. LOC estimate

| Bucket | LOC aprox |
|---|---|
| `web/` boilerplate (auto-generated por `flutter create`) | ~100 (no count) |
| `lib/main_coach_hub.dart` | ~50 |
| `lib/app/coach_hub_app.dart` | ~80 |
| `lib/app/coach_hub_router.dart` | ~120 |
| `lib/features/coach_hub/presentation/*.dart` (dashboard + not-allowed) | ~250 |
| `firebase.json` hosting block + scripts | ~50 |
| Tests (router redirect smoke) | ~150 |
| **Total código nuevo** | **~700** |

PR mediano standalone. No requiere chaining.

---

## 8. Pre-flight checklist (orden de ejecución)

Antes de mergear, ejecutar **en este orden** (los manuales del usuario primero, después el deploy):

1. ☐ User: agregar Web app en Firebase Console
2. ☐ User: crear Hosting site `coach-treino-dev`
3. ☐ User: agregar `localhost:5000` + `coach-treino-dev.web.app` a Auth Authorized domains
4. ☐ Dev (yo o vos): `flutterfire configure --platforms=web` para regenerar `firebase_options.dart`
5. ☐ Dev: `flutter create . --platforms=web` para generar `web/`
6. ☐ Dev: implementar entry point + router + dashboard + tests
7. ☐ Smoke local: `flutter run -t lib/main_coach_hub.dart -d chrome` con cuenta athlete + cuenta trainer
8. ☐ `flutter analyze` 0 + tests passing
9. ☐ Smoke deploy: `flutter build web -t lib/main_coach_hub.dart && firebase deploy --only hosting:coach-treino-dev`
10. ☐ Smoke en URL real: `https://coach-treino-dev.web.app` con misma matriz de cuentas

Post-merge: documentar URL en CLAUDE.md o equivalente para que otros devs sepan dónde está la app.

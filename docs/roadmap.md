# Roadmap — TREINO

Estado de las fases y desglose detallado de Fase 1 (en curso).

## Estado por fase

- [x] **Fase 0** — Bootstrap + tema + 5 tabs vacías + Phosphor (commits `cf09068` a `c6d5fea`).
- [ ] **Fase 1** — Auth (email/Google/Apple) + Firebase + Firestore + ProfileSetup + Roles & guards. Etapa 1 ✅ mergeada (`44c40fc`). Detalle de etapas más abajo.
- [ ] **Fase 2** — Home (paridad con mockup Mobile Home) + Rutinas básicas.
- [ ] **Fase 3** — Feed social (amigos · comunidad · público).
- [ ] **Fase 4** — Workout++ (bloques, super series, IA buscador de ejercicios, videos).
- [ ] **Fase 5** — Coach / Personal Trainer (discovery con geohash, chat, agenda, planes asignados, importación de planes Excel).
- [ ] **Fase 6** — Polish + lanzamiento beta (TestFlight + Play Internal). Incluye App Check, Analytics, Crashlytics, deep links, localización, app icon final.

## Fase 1 — desglose en 7 etapas

Cada etapa es un PR separado. La filosofía: rollback granular si algo se rompe, PRs reviewables, paralelización donde no hay dependencias.

| # | Etapa | Branch | Console (manual) | Código clave | Owner sugerido |
|---|---|---|---|---|---|
| 1 | Firebase init ✅ | `feat/firebase-init` (mergeada en `44c40fc`) | Nada | `firebase_core` + `Firebase.initializeApp()` con `DefaultFirebaseOptions.currentPlatform`. iOS y Android registrados con bundle `com.treino.app`. | A |
| 2 | Auth Email/Password | `feat/auth-email-password` | Authentication → Sign-in method → habilitar Email/Password | `firebase_auth` package, `AuthService`, `AuthNotifier` (Riverpod), pantallas Login + Register + Forgot password. Validación de email + password. Loading states + error handling. | A |
| 3 | Firestore + UserProfile + reglas + emulator | `feat/firestore-user-profile` | Firestore Database ✅ ya creada (`southamerica-east1`, Production mode) | `cloud_firestore` package, modelo `UserProfile` con freezed, `UserRepository`, reglas para `users/{uid}` (read/write sólo el dueño, role inmutable post-create), `firebase.json` con config emulator + script `scripts/emulator.sh` para development local. | A |
| 4 | Auth Google | `feat/auth-google-signin` | Auth → habilitar Google + agregar SHA-1 fingerprint Android + OAuth consent screen | `google_sign_in` package, flujo en Login (botón "Continuar con Google"), credential exchange con Firebase Auth, manejo de "nuevo usuario" (redirect a ProfileSetup) vs "existente" (redirect a Home). | A o B |
| 5 | Auth Apple | `feat/auth-apple-signin` | Auth → habilitar Apple provider + Service ID + Team ID + Key ID + .p8 desde Apple Developer | `sign_in_with_apple` package, flujo en Login. Sólo iOS por ahora. Validar email aún cuando Apple lo oculte (`@privaterelay.appleid.com`). | A |
| 6 | ProfileSetup flow + Storage avatars | `feat/profile-setup-flow` | Storage → crear bucket default + reglas básicas | Multi-step flow (username, gym selector, experiencia, género, peso, altura, avatar). `firebase_storage`, `image_picker` para foto, upload con progress. Redirect post-signup automático cuando `UserProfile` está incompleto. | B |
| 7 | Roles & guards | `feat/roles-guards` | Nada | Enum `UserRole` en `UserProfile`, route guards en `go_router` que redirigen según `role`. Tab Coach renderiza vista atleta vs vista trainer (sin toggle interno — el rol es inmutable). Si rol es `null` (post-signup, pre-ProfileSetup), redirigir a `/profile-setup`. | A |

**App Check** (token verification para prevenir abuse) se mueve a **Fase 6 (Polish)** — es seguridad de prod, no MVP.

### Dependencias entre etapas

```
1 ✅ → 2 → 3 → 6 → 7
        ↓
        4 (paralelo a 3)
        ↓
        5 (paralelo a 3 y 4)
```

- **2 antes de 3**: Auth te da `uid`. Sin `uid` no podés escribir `users/{uid}`.
- **3 antes de 6**: ProfileSetup escribe en `users/{uid}`. Necesita `UserRepository`.
- **6 antes de 7**: Roles & guards lee `UserProfile.role` que se setea en ProfileSetup.
- **4 y 5 pueden ir en paralelo a 3** (no dependen entre sí).

### División entre los 3 devs (con paralelización)

| Dev | Etapas |
|---|---|
| **A** (owner infra) | 2 (email/pwd) + 3 (Firestore + emulator) + 7 (roles/guards) |
| **B** | 4 (Google) en paralelo + 6 (ProfileSetup) cuando A termine la 3 |
| **C** | 5 (Apple) en paralelo + ayuda con UI de 6 |

**Tiempo estimado**: ~1.5 semanas con 3 devs en paralelo.

### Pre-flight checklist (manual en Firebase Console por owner)

Para cada etapa, lo que tenés que dejar listo en [console.firebase.google.com/u/1/project/treino-dev](https://console.firebase.google.com/u/1/project/treino-dev) **antes** de empezar a codear:

- ✅ Etapa 1: nada (la app la registró flutterfire configure).
- ⏳ Etapa 2: habilitar Email/Password en Sign-in method.
- ✅ Etapa 3: Firestore Database creada (`(default)`, `southamerica-east1`, Production, Standard edition).
- ⏳ Etapa 4: habilitar Google + cargar SHA-1 Android + configurar OAuth consent.
- ⏳ Etapa 5: habilitar Apple + credenciales del Apple Developer team (Service ID, Team ID, Key ID, .p8).
- ⏳ Etapa 6: crear Storage bucket en `southamerica-east1`.
- (Etapa 7 no requiere acción en console.)

### Dejado para Fase 6

- App Check (enforcement de tokens para prevenir abuse).
- Analytics (Firebase Analytics + eventos custom).
- Crashlytics.
- Deep links (Firebase Dynamic Links o nativos iOS/Android).

## Fase 5 — extensión: Importación de planes desde Excel

Feature crítica para adopción de PFs reales (la mayoría trabaja con plantillas Excel históricas). Detalle de arquitectura completa pendiente de documentar como sub-fase 5.5 cuando lleguemos.

Resumen:

- Plantilla `.xlsx` estándar TREINO (parser determinístico) + modo IA (Gemini lee Excel arbitrarios).
- Web app para entrenadores ("Coach Hub") en Flutter Web (mismo stack), accesible desde browser.
- Cloud Function `parsePlan` que extrae JSON estructurado del Excel.
- Preview/edit screen antes de asignar el plan a alumnos.
- El plan asignado vive como `Routine` normal en Firestore + `source: "excel-import"` para trazabilidad.

Decisión técnica pendiente: Flutter Web vs Next.js para el Coach Hub. Resolver antes de empezar Fase 5.

## Cronograma estimado

Asumiendo dedicación full-time de los 3 devs (caso optimista):

| Fase | Duración | Fin estimado |
|---|---|---|
| Fase 1 (Auth + Firebase + ProfileSetup) | ~1.5 semanas | ~2026-05-08 |
| Fase 2 (Home + Rutinas) | ~3 semanas | ~2026-05-29 |
| Fase 3 (Feed) | ~2 semanas | ~2026-06-12 |
| Fase 4 (Workout++) | ~3 semanas | ~2026-07-03 |
| Fase 5 (Coach + Excel import + Coach Hub web) | ~5 semanas | ~2026-08-07 |
| Fase 6 (Polish + lanzamiento beta) | ~2 semanas | ~2026-08-21 |

**Total**: ~17 semanas full-time (~4 meses) o ~8-10 meses part-time (50%).

Buffer recomendado: +25% para imprevistos.

# Roadmap — TREINO

Estado de las fases y desglose detallado de Fases 5 (✅) y 6 (en curso).

## Estado por fase

- [x] **Fase 0** — Bootstrap + tema + 5 tabs vacías + Phosphor (commits `cf09068` a `c6d5fea`).
- [x] **Fase 1** — Auth (email/Google/Apple) + Firebase + Firestore + ProfileSetup + Roles & guards. ✅ **COMPLETA** — 7/7 etapas mergeadas. Cerró 2026-05-13 con Apple Sign-In (PR #10).
- [x] **Fase 2** — Home (paridad con mockup Mobile Home) + Rutinas básicas read-only. ✅ **COMPLETA** — 5/5 etapas mergeadas. Cerró ~2026-05-15 con Wire Home → Plantillas (PR #18).
- [x] **Fase 3** — Feed social (amigos · mi gym · público) + perfiles públicos. ✅ **COMPLETA** — 6/6 etapas + sub-fase 5.5 (`user-public-profiles`) mergeadas. Cerró 2026-05-22 con Etapa 6 (feed-friend-requests-inbox, PR #78).
- [x] **Fase 4** — Workout++ (session tracking, sesión activa, post-entreno, historial, insights, wire de stats). ✅ **COMPLETA** — 6/6 etapas mergeadas. Cerró 2026-05-21 con Etapa 6 (wire-real-stats, 4 PRs #56/#57/#65/#67 + archive #69) tras Etapa 5 (insights, PR #51, mergeada 2026-05-19). IA buscador y videos quedaron deferrables a Fase 4.5.
- [x] **Fase 4.5 parcial — Hevy editor rewrite** ✅ **shipped 2026-06-09 (retro)** — extensión del modelo `Routine` a per-set explícito + editor estilo Hevy + reproductor adaptado + edición simétrica trainer/alumno. 12 commits secuenciales (`24806e9..9987816`). IA buscador (Gemini) y videos en ejercicios siguen deferrables.
- [x] **Fase 5** — Coach / Personal Trainer (discovery con geohash, chat, agenda, planes asignados, importación de planes Excel + Coach Hub web). ✅ **COMPLETA** — 8/8 etapas + sub-fase `shared-with-trainer` ✅ + 2 follow-ups (#93 badge "ACTUAL", #94 accept links desde web) mergeados. Cerró 2026-05-26 con Etapa 8 (Excel import client-side, PR #92).
- [x] **Fase 6** — Producto-ready para beta. ✅ **COMPLETA (mobile)** 2026-06-12 (9 etapas core) + extensiones post-cierre = **11/11 etapas mobile**: **Trainer profile UI ✅** · **Push notifications ✅** · **Coach Hub polish ✅** · **Recurring appointments ✅** · **Excel polish + aliases dinámicos ✅** · **App Check + Crashlytics + Analytics ✅** · **Reviews/ratings de PFs ✅** · **i18n mobile ✅** (5 PRs #146/#147/#150/#152/#154) · **Athlete self-routines ✅** (+ extensión home 2026-06-18: #191 today's routine + #193 active marker) · **Chat con media ✅** (#194 data + #195 UI) · **Bidirectional trainer↔athlete data channel ✅** (SDD `trainer-athlete-set-logs`: #199 fix wiring + #200 PR#1 foundation + web + #201 PR#2 mobile athlete-detail wired — el PF ahora ve los set logs reales que cargó el athlete, complemento del chat: "chat = palabras, set-logs = números"). **Polish post-build #2 (2026-06-19)**: Insights granular 10 grupos (#196) + chat unread-count badges (#197) + body highlighting dinámico (#198, asset `mask_back_triceps.png`). **Polish post-build #2 (2026-06-29)**: SDD `exercise-notes` ✅ (#202 — PF deja notas por ejercicio en el editor; el athlete las ve durante la sesión en el player). **Deferred**: i18n Coach Hub web (~55 keys, 5 archivos) — mini-SDD futuro cuando W1.x estabilice copy. **TestFlight builds delivered**: #1 (`0.1.0+1`, 2026-06-17, 86 MB IPA, 1 ITMS-90683 location flag — non-blocking) → **#2 (`0.1.0+2`, 2026-06-18, 80 MB IPA, cero ITMS warnings)** con fix de location + extensiones home + chat-media, live en Internal Beta con 8 testers. **Build #3 pendiente** — bundle de polish post-#2 (#196 a #202) acumulado, sin entregar todavía a TestFlight.
- [ ] **Fase 7** — Monetización + Lanzamiento (TestFlight + Play Internal). Pagos (Mercado Pago/Stripe), verificación profesional automatizada, deep links, app icon final, screenshots para stores, AI Excel con Gemini (cuando GCP esté activo), group chats, video calls.

## Fase 1 — desglose en 7 etapas ✅ COMPLETA

Cada etapa fue un PR separado. La filosofía: rollback granular si algo se rompe, PRs reviewables, paralelización donde no hay dependencias.

| # | Etapa | PR / commit | Console (manual) | Código clave | Owner |
|---|---|---|---|---|---|
| 1 | Firebase init ✅ | `44c40fc` | Nada | `firebase_core` + `Firebase.initializeApp()` con `DefaultFirebaseOptions.currentPlatform`. iOS y Android registrados con bundle `com.treino.app`. | A |
| 2 | Auth Email/Password ✅ | `2648b32` (#2) | Authentication → Email/Password habilitado | `firebase_auth` + `mocktail`. `AuthService`, `AuthNotifier` (Riverpod), `AuthFailure` sealed. Splash + Welcome + Login + Register + ForgotPassword. | A |
| 3 | Firestore + UserProfile + reglas + emulator ✅ | `fa13a8d` (#3) | Firestore Database creada (`southamerica-east1`, Production) | `cloud_firestore`, modelo `UserProfile` con freezed, `UserRepository`, reglas para `users/{uid}` (role inmutable post-create), `firebase.json` con config emulator + script `scripts/emulator.sh`. | A |
| 4 | Auth Google ✅ | `dab528a` (#5) | Auth → Google + SHA-1 Android + OAuth consent | `google_sign_in` 7.x, flujo en Login, credential exchange con Firebase Auth, backfill Firestore opportunistic. | A o B |
| 5 | Auth Apple ✅ | `3a24ca9` (#10) | Auth → Apple + Service ID + Team ID + Key ID + .p8 | `sign_in_with_apple` 7.0.1. Crítico: `accessToken: authorizationCode` para que Firebase valide token server-side (sin esto: `invalid-credential`). | C |
| 6 | ProfileSetup flow + Storage avatars ✅ | `72e1947` (#4) | Storage bucket creado (`southamerica-east1`) | Multi-step de 4 pantallas: username, gym, experiencia/género, peso/altura, avatar. `firebase_storage`, `image_picker`. Redirect post-signup cuando `UserProfile` está incompleto. | B |
| 7 | Roles & guards ✅ | `c6733b7` (#7) | Nada | Enum `UserRole` en `UserProfile`, route guards en `go_router`, tab Coach renderiza vista atleta vs trainer (sin toggle — rol inmutable). | A |

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

### Pre-flight checklist (manual en Firebase Console)

Estado final (todos ✅ al cierre de Fase 1):

- ✅ Etapa 1: nada (la app la registró flutterfire configure).
- ✅ Etapa 2: Email/Password habilitado.
- ✅ Etapa 3: Firestore Database creada (`southamerica-east1`, Production).
- ✅ Etapa 4: Google habilitado + SHA-1 Android + OAuth consent.
- ✅ Etapa 5: Apple habilitado + Service ID `com.backhaus.treino.signin` + Team `J66AQRRM96` + Key `AMFUBKWHZK` + .p8.
- ✅ Etapa 6: Storage bucket creado.
- ✅ Etapa 7: sin acción en console.

### Dejado para Fase 6

- App Check (enforcement de tokens para prevenir abuse).
- Analytics (Firebase Analytics + eventos custom).
- Crashlytics.
- Deep links (Firebase Dynamic Links o nativos iOS/Android).

## Fase 2 — desglose en 5 etapas ✅ COMPLETA

Home (paridad con mockup Mobile Home) + Rutinas básicas read-only (Plantillas pre-cargadas en Firestore que el atleta puede consultar y usar como fallback cuando no tiene una rutina asignada).

**Scope explícito de Fase 2**: solo lectura. Crear rutinas (PF) va en Fase 5. Tracking de sesiones, "Esta semana" con datos reales, Historial e Insights van en Fase 4 (Workout++). En Fase 2 esas zonas quedan con estado vacío/placeholder.

| # | Etapa | PR / branch | Console (manual) | Código clave | Owner |
|---|---|---|---|---|---|
| 1 | Home shell + cards (datos placeholder) ✅ | `8ee3bc2` (#8) | Nada | Home con cards "Empezar entrenamiento" + "Esta semana" según mockup. Datos placeholders — el wire real va en Etapa 5. | B |
| 2 | Modelo `Routine` + seed Plantillas + reglas Firestore ✅ | `23c8f29` (#9) + `d5259d8` (#11) | Colección `routines` poblada por script Admin SDK | Modelos `Routine`, `RoutineDay`, `RoutineSlot`, `Exercise` con freezed + json_serializable. `RoutineRepository` + `ExerciseRepository`. Reglas `routines/{id}` y `exercises/{id}` (read auth, write false). Script `scripts/seed_workout_catalog.js`. ~6 plantillas + ~25 ejercicios seedeados. | A |
| 3 | Lista de Plantillas (tab Entrenamiento) ✅ | `2501dfa` (#14) | Nada | Tab Entrenamiento → `PlantillasSection` con cards de plantilla + filtros por nivel (`LevelFilterPills`). `routinesFilterProvider`. Navegación a `/workout/routine/:id`. | B |
| 4 | Detalle Rutina + Detalle Ejercicio (read-only) ✅ | `23b41be` (#15) | Nada | `RoutineDetailScreen` con day selector + slots con sets/reps/grupo muscular + CTAs disabled stubs ("EDITAR" → Fase 5, "EMPEZAR" → Fase 4). `ExerciseDetailScreen` con técnica numerada + historial empty state. Back button persistente. 41 tests SCENARIO-075..112. | C |
| 5 | Wire Home → Plantillas + estados vacíos ✅ | `175dcf5` (#18) | Nada | Card "Empezar entrenamiento" navega a Plantillas. Card "Esta semana" muestra estado vacío correcto. Cleanup de placeholders de Etapa 1. | B |

### Dependencias entre etapas

```
1 ✅ ─────────────► 5 ✅
                    ▲
2 ✅ ──► 3 ✅ ──────┤
   └─► 4 ✅ ───────┘
```

### División final entre los 3 devs

| Dev | Etapas que hizo |
|---|---|
| **A** | Etapa 2 (modelo + seed + reglas) |
| **B** | Etapa 1 (Home shell) + Etapa 3 (Plantillas list) + Etapa 5 (wire Home → Plantillas) |
| **C** | Etapa 4 (routine + exercise detail) |

**Tiempo real**: ~3 días desde el cierre de Fase 1 (2026-05-13 → 2026-05-15). Estimado original era ~2.5-3 semanas — se aceleró por paralelización agresiva.

### Pre-flight checklist

- ✅ Etapa 2: colección `routines` + `exercises` pobladas via `scripts/seed_workout_catalog.js`.
- (Etapas 1, 3, 4, 5 no requieren acción en console.)

## Fase 3 — desglose en 6 etapas + sub-fase 5.5 ✅ COMPLETA

Feed social con 3 segmentos (Amigos · Mi Gym · Público) + perfiles públicos de otros usuarios + creación manual de posts. Misma filosofía: PR por etapa, paralelizable.

**Scope explícito de Fase 3**:
- Posts manuales (texto + tag de rutina opcional). Posts post-entreno con stats reales **NO** entran acá — vienen con Fase 4 (Workout++). El `PostCard` ya queda preparado para renderizar stats cuando lleguen.
- Friendship/following (request + accept + list) — sin notificaciones push (eso es Fase 6).
- Perfil público de OTROS usuarios (perfil propio ya existe — Etapa 6 de Fase 1).
- "MENSAJE" en perfil público queda como stub disabled → Chat es Fase 5 (Coach).
- "Compartir" desde post-entreno queda para Fase 4.
- Likes / comments / reactions: **no aparecen en mockup actual** → fuera de scope (eventualmente Fase 3.5).

| # | Etapa | PR / branch | Console (manual) | Código clave | Owner |
|---|---|---|---|---|---|
| 1 | Modelo `Post` + `Friendship` + reglas Firestore + seed ✅ | `5058cb6` (#22) | Colecciones `posts` + `friendships` (Admin SDK seed) | Modelos `Post` (autor, texto, tag rutina opcional, privacy: friends/gym/public, createdAt) y `Friendship` (uidA, uidB, status: pending/accepted, requesterId) con freezed. Repos + reglas: post `read` según privacy + requester, `write` solo owner; friendship `read` si sos parte, `write` controlado por requester. Script `scripts/seed_posts.js` con 6-10 posts manuales de prueba. | A |
| 2 | Feed shell + segment AMIGOS + `PostCard` ✅ | `ede3270` (#24) | Nada | Tab Feed (`/feed`) según `feed.png`: header + 3 segments (AMIGOS / MI GYM / PÚBLICO). Implementar solo AMIGOS (los otros 2 disabled). `PostCard` reusable (avatar + nombre + verified + timestamp + gym + tag + stats stub para Fase 4). Empty state cuando no hay posts. | B |
| 3 | Segments MI GYM + PÚBLICO ✅ | `8ae066f` (#26) | Nada | Query por `gymId` del UserProfile para MI GYM. Query "todos posts con privacy=public" para PÚBLICO. ~~Bug pre-existente conocido: composite index `posts(privacy, authorGymId)` faltante en `firestore.indexes.json`~~ — **RESUELTO 2026-05-26 con PR #89** (audit pass que declaró 7 composite indexes faltantes incluyendo este). | B |
| 4 | Perfil público de otro usuario ✅ | `a4780d4` (#28) | Nada | Ruta `/feed/profile/:uid`. UI según `feed-publico.png`: hero + avatar + handle + stats (workouts, racha, seguidores, siguiendo — todos placeholder hasta Fase 4) + tabs RUTINAS PÚBLICAS / ACTIVIDAD + botón SEGUIR (toggleable, escribe en `friendships`). Botón MENSAJE disabled stub → Fase 5. Workaround inicial: `publicProfileViewProvider` leía del primer post del user (refactorizado en 5.5). | C |
| 5 | Crear post manual ✅ | `739bcc3` (#35) | Nada | Plus button (`/feed/create`) → form para crear post (texto max 280 + privacy selector + routine tag stub). `CreatePostNotifier` AsyncNotifier + `PostRepository.create` + invalidate feed providers post-submit. Search usuarios se movió a sub-fase 5.5 por bug de Firestore rules descubierto en smoke. | C |
| **5.5** | **`UserPublicProfile` collection + search + Etapa 4 refactor** ✅ | **`1db1644` (#40) + `9eb7399` (#44) + `275df81` (#45)** | Nueva collection `userPublicProfiles` con rule `read: auth != null` | **Chained PRs.** Reemplaza el approach fallido de search directo en `users` (owner-only rule rompía permission). Crea collection separada con 5 fields públicos (uid, displayName, displayNameLowercase, avatarUrl, gymId), `WriteBatch` atomic dual-write en `UserRepository`. Etapa 4 refactor: `publicProfileViewProvider` ahora source de `userPublicProfileProvider`. Sidecar fix: rule de `friendships` permite `resource == null` (bug pre-existente de PR #28). | C |
| 6 | Inbox de solicitudes de amistad + unfriend desde profile ✅ | `b716ee8` (#78) | Nada | Pantalla in-app `/profile/friend-requests` con `StreamProvider` para live updates; tile siempre visible en Profile con count `(N)`; `UnfriendConfirmationSheet` modal cierra la gap del SIGUIENDO no-op en `PublicProfileFollowButton`; tappable requester zone en cada inbox row → `/feed/profile/:uid`. Scope amendment mid-cycle incluyó unfriend + tap-row + invalidaciones explícitas (ADR-FRI-013) para cerrar on-device staleness sin convertir providers a Stream (cross-device queda en follow-up SDD). | C |
| **6.1** | **Follow-up: Conversión de providers a StreamProvider para cross-device live updates** ✅ | **`0f1a153` (#87)** | Nada | **SDD `feed-providers-stream-conversion`** — cierra la brecha de ADR-FRI-013 convirtiendo `friendshipByPairProvider`, `acceptedFriendsProvider`, `userPublicProfileProvider` de `FutureProvider` a `StreamProvider.family.autoDispose`. Reescribe `publicProfileViewProvider` como `AsyncNotifier.family` componiendo ambos upstreams via `ref.watch(streamProvider.future)` — live composition sin rxdart. Elimina invalidaciones obsoletas (excepto `myFriendsFeedProvider` que queda fuera de scope). Borra orphan `pendingRequestsProvider`. Zero nuevas deps, drop-in surface, 1223/1223 tests verdes. Smoke validó que mutations de User B (displayName, friendship status, friends list) se propagan a User A en vivo sin restart. | C |

### Dependencias entre etapas

```
1 ✅ ──► 2 ✅ ──► 3 ✅ ─► 5 ✅ ──► 5.5 ✅ ──► 6 ✅
            └─► 4 ✅ ───┘
```

- **Etapa 1 antes de todo**: sin modelo Post + Friendship no hay nada que mostrar ni a quién seguir.
- **Etapa 2 antes de 3 y 4**: `PostCard` se define en 2 y se reusa en 3, 4.
- **Etapa 4 paralelo a 3**: perfil público no toca segments.
- **Etapa 5 al final**: necesita PostCard + Friendship.
- **Etapa 5.5 después de 5**: descubierto que search directo en `users` rompía por Firestore rules owner-only. Solución architectural: `UserPublicProfile` collection separada con privacy boundary explícito. Incluyó refactor de Etapa 4 para usar el mismo provider (eliminando el workaround "first post").
- **Etapa 6 después de 5.5 + Fase 4 Etapa 6 (wire-real-stats)**: gap UX descubierta durante el smoke de `wire-real-stats` PR#3 — un athlete que recibe friend request no tenía cómo enterarse ni aceptarla salvo navegando al profile del requester. Re-abre Fase 3 con la pantalla in-app de inbox, entry tile en Profile, y unfriend desde public profile.

### División final entre los 3 devs

| Dev | Etapas que hizo |
|---|---|
| **A** | Etapa 1 (modelo + reglas + seed) |
| **B** | Etapa 2 (Feed shell + AMIGOS) + Etapa 3 (segments) |
| **C** | Etapa 4 (perfil público) + Etapa 5 (crear post) + Etapa 5.5 (UserPublicProfile + search + Etapa 4 refactor) |

**Tiempo real**: ~6 días desde el cierre de Fase 2 (2026-05-15 → 2026-05-19). Estimado original era ~2 semanas — el bug architectural de Etapa 5 search forzó la sub-fase 5.5 pero igual cerró rápido por paralelización con Fase 4.

### Lessons learned promovidas a SDD process

Durante 5.5 quedaron documentadas 3 mejoras para futuros SDDs que toquen Firestore:

1. **Rules Audit section** mandatory en `sdd-design` — listar todos los queries Firestore + verificar rules permiten el access pattern propuesto.
2. **Field-level Privacy Classification table** mandatory al definir nuevos schema fields — clasificar como `private / public-soft / public` ANTES del código.
3. **Sidecar fixes** ok si se descubren durante smoke propio — documentar explícitamente en apply-progress (case: friendship rule).

### Follow-ups documentados (no bloqueantes)

- ~~**Bug MI GYM feed**: composite index `posts(privacy, authorGymId)` faltante en `firestore.indexes.json` — separate PR pendiente.~~ ✅ **RESUELTO 2026-05-26 con PR #89** (audit declaró 7 composite indexes faltantes).
- **Backfill rules tests + CI automation**: extender `scripts/rules_test/rules.test.js` con tests de etapas previas + cablear GitHub Action que corra el suite on PRs que toquen `firestore.rules`.
- **Backfill script `scripts/backfill_user_public_profiles.js`**: documentado pero NO ejecutado — decisión ops para users legacy.
- **UX inconsistency botón SEGUIR**: dice "solicitud enviada" después del tap — copy mismatch con Twitter-style expectation. Path A propuesto: rename a "AGREGAR".

### Pre-flight checklist

- ✅ Etapa 1: colecciones `posts` + `friendships` pobladas via `scripts/seed_posts.js`.
- ✅ Etapa 5.5: nueva collection `userPublicProfiles` deployada + rules deployadas a `treino-dev`.

### Follow-ups post-cierre (Etapa 7 + 7.1)

Dos SDDs adicionales arrancaron post-cierre de Fase 3 para cerrar gaps no contemplados en el scope original:

| # | SDD | PRs / archive | Console (manual) | Código clave | Owner |
|---|---|---|---|---|---|
| 7 | **`profile-screen-rewrite` (Fase 3 Etapa 7)** ✅ | `644b97b` (#95) + `941902a` (#97) + `f377d8d` (#99) + `27a7918` (#101) + archive `8919f42` (2026-05-28) | Storage rule `/avatars/{uid}.{ext}` agregada live en Console durante smoke de PR#2; declarada en repo en PR#2 cascade (`storage.rules`). | Reescritura completa de `ProfileScreen` desde el placeholder Fase 1 hasta mockup parity. 4 PRs chained: scaffold (widgets + router + stub screens), Datos personales edit + avatar upload, Gimnasio change + Mis rutinas list, Settings PIVOT (los tiles "Cerrar sesión" + "Eliminar cuenta" terminan en el body del Profile en vez de pantalla aparte). Sub-fase rename: `Coach IA → Entreno IA` no aplicó acá pero quedó documentado. 4 PRs + 2 housekeeping format commits. SDD en `openspec/changes/archive/2026-05-28-profile-screen-rewrite/`. Decisiones independientes en engram: `profile/mis-rutinas-scope` (trainer-assigned only) y `profile/settings-deferred` (surface de Settings vuelve cuando haya configs reales). | C |
| 7.1 | **`account-deletion`** ✅ — Eliminar cuenta real end-to-end | `b3c8001` (#103) + `75581f8` (#106) + `9dde7a5` (#112) + archive `f2bc8aa` (2026-06-01) | Blaze plan en `treino-dev`; IAM en compute SA (`Datastore User`, `Firebase Authentication Admin`, `Storage Object Admin`, `Cloud Build Service Account`); Cloud Run `allow public access` en el service `deleteaccount`; deploy de `firebase deploy --only functions,storage,firestore:indexes --project treino-dev`. | Reemplaza el stub `EliminarCuentaStubSheet` shippeado en PR#4 v2 de Etapa 7 por flow real. 3 PRs chained: (1) **Cloud Functions bootstrap from zero** (`functions/` directory + Node 20 + TS + Jest + skeleton `deleteAccount` callable v2 en `southamerica-east1`); (2) **CF full cascade** sobre 8+ collections (friendships, posts anonimizadas, trainer_links terminated, appointments canceladas, user docs recursive, storage avatar) + `storage.rules` declarado en repo (cierra deuda Fase 3 Etapa 7); (3) **Flutter UI** + `AccountDeletionService` + `AccountDeletionNotifier` + `ReAuthBottomSheet` provider-aware (email/Google/Apple) + chat sender fallback "Usuario eliminado". 12 smoke fixes adicionales en PR#3 (root cause: errors parsing como `List<Map>` en vez de `List<String>`). Apple re-auth via `User.reauthenticateWithProvider` + sentinel para dodge del nonce-cache bug. Live smoke iOS device: ✅ los 3 providers. 1372 tests + CF jest 40/40. SDD en `openspec/changes/archive/2026-06-01-account-deletion/` + main spec `openspec/specs/account-deletion/spec.md`. | C |

**Tiempo real**: Etapa 7 cerró 2026-05-28 (~6 días desde arrancar). Etapa 7.1 cerró 2026-06-01 (~4 días, con smoke iterativo intenso por la complejidad del flow OAuth + CF + cascade orderings).

**Lessons learned promovidas a SDD process** (de Etapa 7.1):
1. **Smoke fix appendix pattern**: cuando un PR tiene smoke iterativo en device real, agregar appendix dedicado en `apply-progress.md` con tabla de commits (SHA + tipo + summary). Aplicado en `account-deletion` PR#3.
2. **In-flight cascade gate**: para features con cascade deletion (Firestore + Auth + Storage en orden), usar un `StateProvider<bool>` que el router lee para suprimir redirects durante la ventana (`accountDeletionInFlightProvider`). Patrón reusable.
3. **Apple sentinel pattern**: re-auth con Apple no debe usar el credential manual de `sign_in_with_apple` (nonce-cache bug en iOS). Usar `User.reauthenticateWithProvider(OAuthProvider('apple.com'))` + sentinel credential que el `reauthenticate` short-circuits. Patrón reusable para cualquier OAuth re-auth futuro.

**Follow-ups documentados (no bloqueantes)** de estos 2 SDDs — trackear en próximas etapas:
- 2 indexes orphan (`routines: assignedBy+source+createdAt`, `commercialPlans: trainerId+createdAt`) en producción pero no en `firestore.indexes.json` — sumar al repo.
- `gymSearchQueryProvider` no es autoDispose (workaround actual: reset en `initState`).
- CF runtime SA refactor a `firebase-adminsdk-fbsvc` (cleaner IAM, ahora corre con default compute SA).
- Node 20 → 22 + firebase-functions upgrade (deprecation warnings al deploy).
- FirebaseCore init race en cold-start (Google login stuck primera vez si tapeás <2s post-launch).
- SCENARIO-548 test mejorable (forzar Storage error real para verificar `status=partial`).

## Fase 4 — desglose en 6 etapas ✅ COMPLETA

Workout++ es donde la app deja de ser exploración read-only y se vuelve **ejecutable**: el alumno arranca un workout, marca sets en tiempo real, ve su progreso a lo largo del tiempo. Cierra los carry-overs visibles de Fases 1-3 (Home "Esta semana", Profile stats, PostCard stats stub, "Compartir post-entreno").

**Scope explícito de Fase 4**:
- Modelo `Session` + `SetLog` + reglas Firestore + repo.
- Sesión activa (player): timer, marcado de sets en vivo, persiste sesión en Firestore.
- Resumen post-entreno + opción "Compartir" que genera un Post automáticamente.
- Historial: tab Entrenamiento sección Historial + expandir-historial.
- Insights: pantalla completa con volumen semanal, racha, PRs por ejercicio, frecuencia.
- Wire de data atrasada: Home "Esta semana" con streak/muscle map/stats reales, Profile stats reales, check-in básico.

**Out of scope** (deferrables a Fase 4.5):
- IA buscador de ejercicios (Gemini). — ⏳ aún diferido
- Videos en ejercicios (asset pipeline + Firebase Storage para video). — ⏳ aún diferido
- ~~Bloques y super series complejos en la rutina (extensión del modelo `Routine`).~~ — ✅ **shipped 2026-06-09** vía Hevy editor rewrite (ver § Fase 4.5).

| # | Etapa | PR / branch | Console (manual) | Código clave | Owner |
|---|---|---|---|---|---|
| 1 | Modelo `Session` + `SetLog` + reglas Firestore + repo ✅ | `83cd63b` (#34) | Colección `users/{uid}/sessions` poblada por seed (opcional para testing) | Modelos `Session` (uid, routineId, startedAt, finishedAt, totalVolumeKg, durationMin, status: active/finished) y `SetLog` (exerciseId, setNumber, reps, weightKg, rpe?, completedAt) con freezed + json_serializable. `SessionRepository` con create/finish/listByUid. Reglas owner-only R/W bajo `users/{uid}/sessions/{sessionId}`. Sub-colección dentro del user para que los rules ya cubran. Sub-PR `feat/inline-set-rows` (#42) agrega editing inline. | A |
| 2 | Sesión activa (player) ✅ | `09680f0` (#36) + `499c2c8` (#37) + `efb1dc2` (#38) | Nada | Pantalla nueva accesible desde "EMPEZAR ENTRENAMIENTO" en RoutineDetailScreen. Timer running, marcado de sets en vivo (reps + peso + check), persiste cada `SetLog` en Firestore on-completion. Botón "TERMINAR SESIÓN" → finaliza Session + navega a resumen post-entreno. Entregado en 3 chained PRs (foundation + logic + UI). | B |
| 3 | Resumen post-entreno + compartir ✅ | `c23c80c` (#39) | Nada | Pantalla `post-entreno.png` con stats finales (volumen total, duración, PRs alcanzados). Opción "Compartir" → genera Post automáticamente con `routineTag` set + texto autocompletado + privacy default friends. Navega de vuelta a Home o Entrenamiento. | B |
| 4 | Historial + expandir ✅ | `65455c6` (#46) | Nada | Tab Entrenamiento sección Historial según `historial.png`. Lista de sesiones pasadas con día, volumen, duración. Tap expande a `expandir-historial.png` mostrando sets/reps reales de la sesión. | C |
| 5 | Insights screen ✅ | `12b7304` (#51) | Nada | Pantalla Insights (`insights.png`) con volumen semanal, racha de días, PRs por grupo muscular, frecuencia. Lee de la colección `sessions` y agrega client-side. Domain: `MuscleGroupDisplay` enum (6 grupos) + mapping desde 10 categorías granulares del catálogo. Server aggregation queda para Fase 6 cuando aparezca App Check / Cloud Functions. 47 tests nuevos. SDD en `openspec/changes/insights/`. | C |
| 6 | Wire data atrasada (Home + Profile + Public Profile + check-in) ✅ | `c48f577` (PR#1-4: #56/#57/#65/#67, archive #69) | Nada | 4 PRs encadenados. PR#1 Home "Esta Semana" (streak real + body silhouettes + day strip + SEMANA/MES cards). PR#2 Own Profile stats row (SESIONES + VOLUMEN KG via `kFormat` + RACHA magenta). PR#3 Public Profile counter denormalization (4 nullable fields en `UserPublicProfile` + cross-feature writes en `SessionRepository.finish` y `FriendshipRepository.accept/delete` con self-refresh per ADR-WRS-12, breaking change en `delete(id, myUid)` signature). PR#4 Check-in daily prompt (`check-in.png`) — dialog en Feed mount con `/users/{uid}/checkIns/{date}` collection + rules owner-only + 3 SCENARIOs en emulator. Lessons promovidas: try/catch + no-rethrow para cross-feature writes (ADR-WRS-10), container-presentational pattern (ADR-WRS-19 props-down dialog). | C |

### Dependencias entre etapas

```
1 ✅ ──► 2 ✅ ──► 3 ✅
  ├──► 4 ✅ ──► 5 ✅
  └─────────────► 6 ✅
```

- **1 bloqueante absoluto**: sin `Session` model + repo no hay nada que ejecutar, persistir, ni leer.
- **2 antes de 3**: el resumen post-entreno lee la Session que el player acaba de cerrar.
- **4 paralelo a 2 y 3**: historial solo lee `sessions` (sin escritura).
- **5 después de 4**: insights agrega data que el historial ya estructura.
- **6 al final**: wire de stats reales necesita data real en `sessions` para calcular streak/volumen.

### División entre los 3 devs (con paralelización)

| Dev | Etapas |
|---|---|
| **A** | Etapa 1 (modelo + seed + reglas) ✅ |
| **B** | Etapa 2 (player) ✅ + Etapa 3 (resumen + compartir) ✅ |
| **C** | Etapa 4 (historial) ✅ + Etapa 5 (insights) ✅ + Etapa 6 (wire-real-stats) ✅ — reasignación 2026-05-20: Etapa 6 movida de B a C porque B arrancó Fase 5 foundations |

**Tiempo real**: ~6 días desde el cierre de Fase 3 etapas paralelas hasta cerrar Fase 4. Etapa 5 (insights) cerró 2026-05-19; Etapa 6 (wire-real-stats, 4 PRs chained) cerró 2026-05-21 con archive 2026-05-21. Proyección original era ~1-2 semanas más — terminó pasando casi exacto por paralelización con Fase 5 (que arrancó foundations en paralelo).

### Trabajo paralelo entre Fase 3 y 4

Etapas 1-4 de Fase 4 corrieron en paralelo con las últimas etapas de Fase 3 (incluida 5.5). Cero conflicts notables — `lib/features/workout/` (Fase 4) y `lib/features/feed/` + `lib/features/profile/` (Fase 3) son disjuntos.

### Cambio adicional fuera de etapa formal

- **PR #47 `feat/exercise-images-per-exercise`**: reemplazó la convention "una imagen por grupo muscular" con "una imagen por ejercicio" en `assets/exercises/{exerciseId}.png` + 25 PNGs nuevas comprimidas con pngquant. Cambio de UI mecánico (~5 líneas en `_HeroStrip`).

### Pre-flight checklist

- ✅ Etapa 1: opcional poblar `users/{uid}/sessions` para testing visual de historial e insights — script disponible.
- (Etapas 2-6 no requieren acción en console.)

## Fase 4.5 — Hevy editor rewrite (retro, shipped 2026-06-09)

Cierre retroactivo del tercer deferrable de Fase 4 ("bloques y super series complejos en la rutina"). 12 commits secuenciales mergeados a `main` el 2026-06-09 reescriben el editor de rutinas al modelo per-set explícito estilo Hevy, adaptan el reproductor, y dan simetría de edición entre trainer y alumno. **Shipped en silencio sin SDD ni entrada previa en roadmap** — documentado acá vía audit el 2026-06-10.

**Scope entregado**:

- **Modelo per-set explícito** — nueva freezed class `SetSpec` (`type/weightKg/reps/repsMin/repsMax/durationSeconds`) + enums `ExerciseMode` (reps/duration) · `RepMode` (single/range) · `SetType` (warmup/normal/drop/failure). `RoutineSlot` gana `exerciseMode`/`repMode`/`sets[]` con `@Default` para zero-migration; getter `effectiveSets` sintetiza rows desde los scalars legacy (`targetSets/targetReps/durationSeconds`) cuando `sets[]` está vacío. Dual-write: el editor escribe nuevo + legacy en simultáneo (`buildRoutineSlot` helper) para no romper clientes viejos.
- **Editor estilo Hevy** — `routine_editor_screen.dart` reescrito a tabla de sets (`_SetTable` inline widget): header tappable Reps/Tiempo, chip de SetType por row (W/#/D/F), `DurationTextField` con digit-fill MM:SS, "+ Agregar set" clona el último, nombre del ejercicio full-width multi-line con menú ⋮ (Cambiar/Subir/Bajar/Eliminar). Movido a `GoRoute` top-level (full-screen, sin bottom nav). Reorder de members dentro de superserie via chevrons.
- **Reproductor adaptado** — `session_player_screen.dart` consume `effectiveSets`. Sets por tiempo se auto-completan al expirar el `Timer.periodic` con `HapticFeedback.heavyImpact()` (sin botón "Listo"). Sets futuros atenuados (`Opacity 0.4`). Indicador de ejercicio terminado pasa de círculo verde a `TreinoIcon.checkBare` (parecía botón antes).
- **Edición simétrica trainer ↔ alumno** — `TrainerAssigning` + `TrainerTemplating` ganan `existingPlanId`/`existingTemplateId`. `RoutineRepository.updateAssigned` + `updateTemplate` (solo mutan contenido; congelan identity fields). Entry points: botón editar en cada plan del alumno (`athlete_detail_screen`) y en cada plantilla (`trainer_workout_view`). `firestore.rules` gana 82 LOC con 2 nuevos `allow update` paths (trainer-assigned + trainer-template) con guards `hasOnly` sobre lista cerrada de fields (incluye `COUPLING WARNING` comment — agregar campo nuevo al modelo sin actualizar rules rompe writes con permission-denied).
- **Custom exercises** — dropdown de músculo granular (`kMuscleOptions` 18 valores es-AR estilo Hevy en lugar de free-text). Entry point "Mis ejercicios" desde el perfil del alumno (`profile_screen.dart` → `/profile/my-exercises`, screen ya existía para trainers).
- **Fix bug pre-existente** — `routine_detail_screen` pasaba `assignedBy` (null en rutinas userCreated) como `ownerId`, así que `slotExerciseProvider` no resolvía ejercicios custom del alumno. Fix: `assignedBy ?? createdBy`.

**Commits** (cronológico, oldest first):

| Commit | Scope |
|---|---|
| `24806e9` | Fase 1 — modelo per-set (SetSpec freezed + RoutineSlot extension) |
| `e63cd31` | Fase 2 — editor con tabla de sets |
| `c37f2bb` | Dropdown de músculo en ejercicio custom |
| `1345ade` | Acceso a "Mis Ejercicios" desde perfil del alumno |
| `dd69e4d` | Creación de rutina full-screen + editar ejercicio + reorder en superserie |
| `295eeba` | Editor más grande y con menos cajas |
| `53c2d94` | Rediseño de campos del editor + fix guardado |
| `8c3a43e` | Reproductor adaptado al modelo nuevo |
| `c0bc7cd` | Editar rutina propia del alumno (hidratar + guardar) |
| `5703f4e` | Fix: detalle de ejercicio custom abre en rutina propia |
| `318629a` | UX reproductor: tiempo, bloqueo de sets, check pelado |
| `9987816` | Editor + edición de planes y plantillas del coach (rules + repo) |

**Test coverage agregada** (~10 archivos nuevos, +2K LOC):
- `domain/set_spec_test.dart` (111) · `domain/routine_slot_test.dart` (241) · `domain/muscle_options_test.dart` (83)
- `presentation/routine_editor_set_table_test.dart` (401) · `routine_editor_features_test.dart` (128) · `routine_editor_trainer_edit_test.dart` (425)
- `presentation/widgets/duration_text_field_test.dart` (49)
- `data/routine_repository_trainer_edit_test.dart` (288) · `data/routine_rules_test.dart` (103, emulator-deferred)
- `presentation/session_player_screen_test.dart` (+170 LOC) — block-gating + future-set dimming + duration detection

**Sin SDD formal**: scope grande pero el patrón shipped-without-SDD se está volviendo recurrente en este proyecto (Coach Hub Etapa 3, catalog #136, ahora Fase 4.5). Documentado acá para no acumular más deuda de roadmap.

**Open questions (no bloqueantes)**:
- Tests de rules emulator-deferred — ¿corren en CI o están skipped? Si están skipped, Paths 3/4 del `allow update` no tienen cobertura automatizada.
- `SetType.warmup/drop/failure` se renderizan pero el insights/volumen no los distingue de `normal` — ¿intencional por ahora?
- Legacy scalar fields (`targetSets/targetRepsMin/Max/targetWeightKg/targetReps[]/durationSeconds`) siguen siendo dual-write — ¿hay plan de removerlos eventualmente?
- `kMuscleOptions` es es-AR; catalog usa keys en inglés — ¿partición bilingüe en `muscleGroup` que el insights tenga que normalizar?

## Fase 5 — desglose en 8 etapas ✅ COMPLETA

El módulo de Personal Trainer (PF). Esta fase introduce un segundo tipo de usuario activo — el PF profesional — y el ecosistema de discovery, vinculación, comunicación, planificación y monetización entre PF y atleta. Más grande y compleja que cualquier fase anterior. También introduce el primer target web del producto: **Coach Hub**.

**Scope explícito de Fase 5**:

- Trainer profile extendido (bio, especialidad, ubicación, tarifa por hora).
- Discovery con geohash: athletes buscan PFs cercanos en `feed-publico.png` o tab Coach.
- Trainer-Athlete link lifecycle: athlete pide vincularse, PF acepta/rechaza/termina. Mismo patrón que `friendships` pero con estados ampliados.
- Chat 1-1 real-time entre vinculados (Firestore snapshot listeners).
- Agenda: scheduling de sesiones one-off entre PF y atleta vinculado.
- Asignación de planes: el PF crea una `Routine` privada y se la asigna a un atleta. El atleta la ve junto a las plantillas en su tab Workout, y el SessionPlayer funciona con ella sin cambios.
- Importación de planes desde Excel: Cloud Function `parsePlan` extrae JSON estructurado (parser determinístico TREINO template + fallback IA con Gemini para Excel arbitrarios). Preview + edit antes de asignar.
- **Coach Hub web app**: target nuevo en Flutter Web reutilizando models/repos/providers. Trainer dashboard, lista de alumnos, editor de planes, uploader de Excel.

**Out of scope** (deferrables a Fase 5.5 o Fase 6):

- Group chats / channels.
- Read receipts, typing indicators, push notifications de chat (las notifications viven en Fase 6).
- Pagos / billing / monetización (Mercado Pago, Stripe, etc.) — la app permite contacto pero el cobro queda offline.
- Recurring appointments (sesiones semanales auto-agendadas).
- Plans con periodización compleja (mesociclos, deload weeks, %1RM auto-ajustable).
- Video calls integrado (atletas y PFs pueden coordinar por su cuenta vía chat).
- Reviews / ratings de PFs (eventualmente, pero no MVP).
- Verificación profesional automatizada (certificaciones, matrícula) — quedará como "self-declared" en MVP.

### Decisiones arquitectónicas lockeadas (2026-05-20)

| # | Decisión | Rationale |
|---|---|---|
| 1 | **Coach Hub en Flutter Web** (no Next.js) | El Coach Hub es admin tool para profesionales — no necesita SEO ni performance de SSR. Reutilizamos ~80% del código mobile (modelos, repos, providers, hasta widgets de presentación). Elegir Next ahora sería contratar deuda de modelo duplicado. |
| 2 | **Trainer-Athlete link via colección `trainer_links/{linkId}`** | Documento top-level con `{trainerId, athleteId, status, createdAt, terminatedAt?}`. Estados: `pending → active → paused → terminated`. Simétrico, queryable en ambas direcciones, paralelo a cómo manejamos `friendships`. |
| 3 | **Planes asignados = `Routine` extendido**, no entidad nueva | Misma estructura (days, slots, target sets/reps) que las plantillas — solo cambia metadata (`source`, `assignedBy`, `assignedTo`, `visibility`). Reutiliza `RoutineDetailScreen` y `SessionPlayer` tal cual. Las queries de plantillas filtran `visibility == 'public'`; las asignadas se queryean por `assignedTo == myUid`. |
| 4 | **Athlete-controlled history sharing via `sharedWithTrainer: bool` en `TrainerLink`** | El campo va en el doc de `trainer_links/{linkId}`. Default `false`. El athlete (no el PF) lo puede toggle desde su tab Coach con vínculo active. Reglas: read by both members; write only by `athleteId`. Cuando `false` el PF ve solo el plan asignado + agenda; cuando `true` el PF también ve el historial completo (sessions + insights). Para Etapa 3 (link lifecycle): se setea el campo al crear el link, y se expone un toggle en la UI del athlete. Para Etapa 6 (alumnos del trainer): la query del PF a `sessions/{athleteId}/*` se gate por este flag. Razón: privacy by default; pone el control en el athlete; matchea el modelo de la roadmap original ("requires consent explícito"). |
| 5 | **Pricing: tarifa mensual** (campo `trainerMonthlyRate: int?` en UserProfile + TrainerPublicProfile) | Mercado local cobra principalmente mensualidad (plan + check-ins + mediciones bundled). NO se cobra por hora. NO se procesa pago in-app (Pagos a Fase 6). Modelos alternativos (per-session, per-plan) se posponen al Coach Hub (Etapa 7) si la realidad lo justifica. Decisión tomada 2026-05-20 después de feedback del producto durante PR2 testing. |

### Etapas

| # | Etapa | Branch | Console (manual) | Código clave | Owner sugerido |
|---|---|---|---|---|---|
| 1 | **Foundations** ✅ — modelos + reglas + Routine extension | `0e22252` (#54, archive #55) | Reglas Firestore deployadas para `trainer_links/**` y queries de Routine | UserProfile extendido con `trainerBio?`, `trainerSpecialty?`, `trainerLocation: GeoPoint?`, `trainerGeohash?`, `trainerMonthlyRate?` (rate moved from hourly per decisión #5). Modelo `TrainerLink` (freezed) con `linkId, trainerId, athleteId, status, requestedAt, acceptedAt?, terminatedAt?`. `TrainerLinkRepository` con request/accept/decline/terminate/listForTrainer/listForAthlete. Routine extension: `source`, `assignedBy?`, `assignedTo?`, `visibility`. SDD en `openspec/changes/coach-foundations/`. | B |
| 2 | **Discovery con geohash** ✅ | `034e3d9` (#58 infra) + `760ea3b` (#59 UI); visual refresh: `d1e8833` (#82) + `ae3a1f4` (#83) + `067cdc3` (#84) | Nada (geohash query es client-side) | Pantalla `TrainersListScreen` accesible desde tab Coach (rol athlete) — lista de PFs filtrable por especialidad + distancia. Pantalla `TrainerPublicProfileScreen` (variante de `PublicProfileScreen`). **Refresh 2026-05-23..26**: 3 PRs encadenados rediseñaron la pantalla a un MAPA/Lista toggle con dark tiles + pill markers + bottom sheet + filter chips (distancia + precio). SDD original en `openspec/changes/coach-discovery/`. | C |
| 3 | **Link lifecycle (mobile)** ✅ — request / accept / decline / terminate / cancel | `2d419f4` (#61, archive #62) + sub-fase `shared-with-trainer` `fa42aa4` (#73, archive #76) | Nada | Athlete tap en CTA "PEDIR VÍNCULO" → crea doc en `trainer_links` con `status: 'pending'`. PF ve sección "Solicitudes pendientes" + "Mis alumnos activos". Botones aceptar/rechazar/cancelar. Athlete ve estado del vínculo en su tab Coach. **Sub-fase `shared-with-trainer`**: agrega el flag `sharedWithTrainer: bool` (default false) que el athlete toggle desde su side, gating del historial sharing per decisión #4. SDDs: `coach-link-lifecycle` + `archive/2026-05-22-shared-with-trainer/`. | B |
| 4 | **Plans assignment (mobile)** ✅ — visualización + creación básica desde mobile | `6642fe8` (#64 data) + `d354568` (#70 MI PLAN section) + `a864448` (#71 UI trainer), archive #72 | Reglas Firestore actualizadas para Routine privadas | Athlete ve sus planes asignados en tab Workout, sección "MI PLAN" arriba de PLANTILLAS. RoutineDetailScreen muestra badge "Asignado por <PF>" cuando `source == 'trainer-assigned'`. SessionPlayer funciona sin cambios. Trainer-side: tap en alumno → ve planes asignados; botón "CREAR PLAN" abre RoutineEditorScreen. NOTE: edición avanzada vive en Coach Hub (Etapa 7). SDD `archive/2026-05-21-coach-plans-mobile/`. | B |
| 5 | **Chat 1-1 real-time** ✅ | `705d0df` (#74, archive #75) | Reglas Firestore para `chats/**` | Colección `chats/{chatId}` (id determinístico — `sortedUids.join('_')`) + sub-colección `chats/{chatId}/messages/{messageId}` con `{senderId, text, createdAt}`. Stream provider via Firestore snapshots para real-time. UI: lista de chats (todos los vínculos activos), pantalla de chat con burbujas + scroll auto-bottom + textfield. Reglas: solo members del chat pueden leer/escribir. Sin push notifications todavía (Fase 6). SDD `openspec/changes/coach-chat/`. | C |
| 6 | **Agenda** — appointments one-off ✅ | `eb4069f` (#79 data) + `e51d257` (#81 UI athlete) | Nada | Colección `appointments/{appointmentId}` con `{trainerId, athleteId, startsAt, duration, status: 'proposed' \| 'confirmed' \| 'cancelled', notes?}`. Cualquier member del link activo puede proponer; el otro debe confirmar. Pantalla `AgendaScreen` con calendario (paquete `table_calendar`). Crear/cancelar appointment via bottom sheet. Sin recurrencia (one-off only). Plus availability rules + overrides + `compute_free_slots` para que el athlete vea solo slots disponibles. SDD `openspec/changes/coach-agenda/` — **pendiente verify + archive** (apply-progress.md existe pero archive-report.md no). | C |
| 7 | **Coach Hub bootstrap (web)** ✅ | `268b7d8` (#86) | Web app + Hosting site `coach-treino-dev` + Authorized domains en Firebase Console + `flutterfire configure --platforms=web` | Nuevo entry point `lib/main_coach_hub.dart` + `coach_hub_app.dart` + `coach_hub_router.dart` (3 rutas: `/login`, `/dashboard`, `/not-allowed`). Role gating client-side via `coachHubRedirect` pure function — athletes caen en `/not-allowed`, trainers van al dashboard. Login email/password (sin Google Sign-In en MVP). Dashboard mínimo: bienvenida + lista de alumnos activos + sign-out. Deploy a Firebase Hosting target `coach-hub-dev` → vivo en `coach-treino-dev.web.app`. 11 tests de redirect del router. | B |
| 8 | **Excel import (Coach Hub) — client-side** ✅ | `cdec262` (#92) + follow-ups: `97313b4` (#93 badge "ACTUAL" mobile) + `a459fa4` (#94 accept links desde web) | Ninguno — pivot a parser client-side eliminó la dependencia de Cloud Functions/Storage | **Pivot intencional**: originalmente diseñado con Cloud Function `parsePlan` + Gemini. El deploy se bloqueó por IAM (sin Owner en GCP no se puede dar `iam.serviceAccounts.actAs` a la compute SA, ni 1st Gen ni 2nd Gen). Se movió todo el parseo al cliente Dart con `package:excel`. Firestore rules siguen siendo la barrera de seguridad real. Catálogo `exercises` ganó campo `aliases` (5-8 sinónimos español por entrada, ej: `back-squat` matchea "Sentadilla con barra"); backfilleado en `treino-dev` via `scripts/backfill_exercise_aliases.js`. Coach Hub: `/upload-plan` (file picker + download template) → `/upload-plan/preview` (preview por día + dropdown manual para los sin match + multi-asignación a varios atletas en un paso). Loop `createAssigned` por atleta. AI generativa con Gemini queda postergada a Fase 7 (cuando GCP esté disponible). | B |

### Dependencias entre etapas

```
1 ✅ ──┬──► 2 ✅
       ├──► 3 ✅ ──┬──► 4 ✅
       │           ├──► 5 ✅
       │           └──► 6 ✅
       └──► 7 ✅ ──► 8 ✅
```

- **1 bloqueante absoluto**: sin el modelo `TrainerLink` + Routine extendida + reglas, ninguna otra etapa puede empezar.
- **2 y 3 paralelo**: discovery y link lifecycle son independientes una vez que 1 está; un dev puede agarrar 2 y otro 3.
- **4, 5, 6 dependen de 3**: planes asignados, chat y agenda solo funcionan entre pares vinculados.
- **7 paralelo a 2-6**: el bootstrap de Coach Hub web empezó apenas Etapa 1 estuvo y avanzó en paralelo con el track mobile.
- **8 depende de 7**: el Excel import vive principalmente en el Coach Hub — necesita el web target ya bootstrapeado.

### División final entre los 3 devs

| Dev | Etapas que hizo |
|---|---|
| **A** | (sin asignación en Fase 5 — Etapa 7/8 reasignadas a B durante el sprint) |
| **B** | Etapa 1 (foundations + reglas) ✅ + Etapa 3 (link lifecycle) ✅ + Etapa 4 (plans mobile) ✅ + **Etapa 7 (Coach Hub bootstrap)** ✅ + **Etapa 8 (Excel import client-side)** ✅ + follow-ups (#93 badge "ACTUAL" + #94 accept links desde web) |
| **C** | Etapa 2 (discovery + visual refresh 3 PRs encadenados) ✅ + Etapa 5 (chat) ✅ + Etapa 6 (agenda) ✅ |

**Reasignaciones durante el sprint**:
- 2026-05-20: Etapa 1 movida de A a B (B arrancó foundations mientras C cerraba Fase 4 Etapa 6).
- 2026-05-26: Etapas 7-8 absorbidas por B en handoff con A (A seguía en Etapa 6 Agenda; B + producto coordinaron tomar Coach Hub web bootstrap + Excel import).

**Estimación vs real**: ~3-4 semanas en paralelo con los 3 devs era el plan original. **Real**: 8/8 etapas cerradas entre 2026-05-19 y 2026-05-26 (**~7 días**), ~9 semanas adelantada vs proyección. Pivot técnico en Etapa 8 (Cloud Functions → client-side parser) ahorró tiempo de IAM/GCP setup pero pospuso AI generativa a Fase 7.

### Cross-cutting concerns (válidos para todas las etapas)

- **Onboarding del PF**: registro normal → tap "Soy entrenador" en ProfileSetup → setea `role: 'trainer'` + abre flow extra para `trainerBio/Specialty/Location/HourlyRate`. NO requiere validación de matrícula en MVP — self-declared. Si el feature toma tracción, agregamos verificación en Fase 6.
- **Geolocalización**: pedir permiso al PF al setear su perfil. Para athletes, ubicación opcional — si no la dan, discovery cae a búsqueda por nombre/especialidad sin orden geográfico.
- **Privacy & security**: las reglas Firestore se vuelven más complejas. Cada etapa lleva su block dedicado de reglas + tests `scripts/rules_test/`.
- **i18n**: todos los strings del Coach Hub web siguen en español Rioplatense — mismo `lib/features/.../strings.dart` pattern que mobile. Cuando salga la versión inglesa (Fase 6), se introduce localización formal.
- **Schema migrations**: Etapa 1 agrega campos opcionales (no breaking). Etapa 4 cambia las queries de Routine para filtrar por visibility — un atleta existente sin vínculo ve solo `visibility == 'public'`, ningún regression.

### Open questions a resolver durante el sprint

1. **Pricing / monetización**: ¿la app cobra al PF (subscription) o al athlete (per session/per month)? Decisión bloquea pagos pero **NO** bloquea el MVP de Fase 5 (que asume contacto sin transacción in-app). Resolver antes de Fase 6.
2. **Permisos del PF sobre el atleta**: RESUELTO 2026-05-20 → `sharedWithTrainer: bool` lockeado como decisión arquitectónica #4. Ver tabla "Decisiones arquitectónicas lockeadas".
3. **Cancellation policy**: si el PF rechaza un request o termina un vínculo, ¿se notifica al athlete? Sí, vía in-app notification (carry-over a Fase 6 push notifications). Por ahora, banner pasivo en la próxima apertura de la app.
4. **Coach Hub domain**: ¿`coach-treino.web.app` (Firebase default) o dominio propio (`coach.treino.app`)? Decisión de marketing — usar Firebase default para MVP y migrar después.
5. **AI parsing cost**: Gemini API es paga. ¿Limitamos a N parses gratuitos por PF al mes? Recomendación: límite 10/mes en MVP, sin enforcement estricto (telemetría para ver consumo real antes de poner el gate).

### Plantilla `.xlsx` oficial TREINO

Definida durante Etapa 8. Contrato implementado en `lib/features/coach_hub/data/excel_parser.dart` + `template_builder.dart`:

- Hoja 1: `Plan` → `name, daysPerWeek, durationWeeks, level` (level acepta `principiante / intermedio / avanzado`, mapeado a `beginner / intermediate / advanced` antes de serializar).
- Hoja 2..N: `Día 1`, `Día 2`, etc → columnas `Ejercicio, Series, Reps Min, Reps Max, Peso Kg, Descanso Seg, Notas`.
- Las filas vacías se ignoran. `Ejercicio` se matchea contra el catálogo `exercises` por nombre + aliases en español. Los no matcheados se resuelven via dropdown manual en el preview (sin bloquear).

**Polish entregado** (Fase 6 Etapa 5, 2026-06-09 via SDD `coach-excel-polish`): anchos de columna del template + hoja "Instrucciones" con guía de columnas y valores válidos (`principiante / intermedio / avanzado`) + ejemplo pre-cargado. Validation dropdown nativo del paquete `excel: ^4.0.6` no existe → reemplazado por texto referencial en Instrucciones (scope tradeoff documentado). Archive en `openspec/changes/archive/2026-06-09-coach-excel-polish/`.

## Fase 6 — desglose en 8 etapas

Producto-ready para beta. Fase 5 dejó el core del producto funcional end-to-end; Fase 6 cierra los gaps de UX, telemetría y configurabilidad que separan "demo que funciona" de "app que se puede usar en producción real con PFs reales".

**Scope explícito de Fase 6**:

- Onboarding del PF + UI para completar perfil público (avatar, bio, specialty, ubicación, precio) — sin scripts manuales.
- Push notifications (FCM) para chat, agenda y vínculos pending. iOS + Android.
- Coach Hub web gana historial de vínculos terminados/cancelados + manage subscriptions (pausar/terminar desde web).
- Agenda con recurring appointments (sesiones semanales auto-agendadas).
- Polish del template Excel + aliases dinámicos (PF mapea manual → suma al catálogo).
- App Check + Crashlytics + Analytics — telemetría básica para monitorear producción.
- Reviews + ratings de PFs — el atleta puntúa después de N sesiones.
- Localización formal (es-AR oficial via .arb + scaffold para inglés).

**Out of scope** (deferrables a Fase 7 — Monetización + Lanzamiento):

- Pagos / billing / monetización (Mercado Pago, Stripe).
- Verificación profesional automatizada (matrícula, certificaciones).
- AI generativa con Gemini para parsing Excel arbitrario (esperando habilitación de GCP para deployar Cloud Functions).
- Deep links + branch.io.
- App icon final + screenshots para stores.
- Group chats / channels.
- Video calls integrado.
- Beta lanzamiento formal (TestFlight + Play Internal).

### Decisiones arquitectónicas lockeadas (2026-05-27)

| # | Decisión | Rationale |
|---|---|---|
| 1 | **Fase 6 NO incluye pagos** | Empujamos pagos a Fase 7 dedicada. Pagos toca compliance (PCI/AFIP), modelo de billing (suscripción vs per-session), y procesamiento (Mercado Pago para AR + Stripe para resto). Mezclarlo con polish/telemetría/recurring complica review y blast radius. |
| 2 | **Push notifications via FCM (Firebase Cloud Messaging)** | Stack consistente con resto del backend. Soporta iOS (vía APNs) + Android nativo. No duplica infra. Alternative: OneSignal (más rico en analytics) descartado para no sumar otro vendor. |
| 3 | **Recurring appointments como "template" + materialización lazy** | Cuando el PF crea una sesión recurrente, escribimos un doc en `recurring_appointments/` con `pattern: weekly`, `dayOfWeek`, `time`, etc. Los appointments individuales se materializan al pedir slots futuros (no se pre-crean 52 docs por año). Justifica: cancellation policy + change of plans + storage cost. |
| 4 | **Aliases dinámicos: write privilege solo de Cloud Function** | Cuando un PF mapea manual en el preview, el cliente NO escribe el alias directo en `exercises/{id}` — manda una request a una function `addAlias(exerciseId, alias)` que valida + dedupes + escribe. Por qué: rules de `exercises` son read-public + write-system; abrir write a cualquier trainer es riesgoso. La function es el único privilegiado. **Caveat**: si seguimos sin GCP, este punto se queda en deuda y los aliases siguen siendo "estáticos via backfill". |
| 5 | **Reviews: rating 1-5 + comentario opcional + un único review por par PF/atleta** | Un atleta solo puede dejar UN review por PF (puede editarlo). Esto evita rating bombing y mantiene una sola fuente por relación. Trigger: cuando el atleta termina el vínculo o pasan ≥30 días desde `link.acceptedAt`. |
| 6 | **i18n via `intl_translation` + .arb files** | Setup estándar de Flutter. Eslogan: es-AR oficial primero, inglés scaffold (no traducido todavía). Cuando el producto valide internacionalización, se completa la traducción. |

### Etapas

| # | Etapa | Branch sugerida | Console (manual) | Código clave | Owner sugerido |
|---|---|---|---|---|---|
| 1 | **`trainer-profile-onboarding`** ✅ — PF completa su perfil público desde la app | `2067d5a` (#139 data + gate) + `796018b` (#141 onboarding mode + script) + archive `aaf5243` (2026-06-08) | Reglas de `trainerPublicProfiles` ya estaban deployadas. **Setup manual** documentado en `scripts/README.md` SI se usa el script CLI (service account JSON + GOOGLE_APPLICATION_CREDENTIALS env var + `cd scripts && npm install`). Alternativa equivalente: Firebase Console → editar `users/{uid}.role` de `'athlete'` a `'trainer'` directamente. | 2 PRs chained, ~250 LOC, Strict TDD. **Decisión clave**: Opción B (admin-SDK-only role flip) en vez de Opción A (self-select en ProfileSetup) — 5x menor scope, destraba TestFlight. **PR#1 #139** data layer (fix bug crítico de `uid` faltante en `_trainerPublicSubsetFromPartial` que iba a permission-deny todo first-save real + derived `trainerProfileComplete` extension getter + `trainerProfileCompleteProvider` thin wrapper + `authRedirect` trainer-incomplete gate con `startsWith('/profile/edit-trainer')` loop guard + `!isPublic` guard como improvement spec-compatible). **PR#2 #141** onboarding mode UI (`ProfileEditTrainerMode` enum inline + router `?mode=onboarding` query param mapping + AppBar título "Completá tu perfil profesional" + `PopScope(canPop: false)` para bloquear iOS swipe-back + `automaticallyImplyLeading: false` + save → `context.go('/home')` en onboarding vs `context.pop()` en edit + `scripts/promote_user_to_trainer.js` rewrite genérico role-flipper-only + delete del Mateo-specific script + `scripts/README.md` nuevo con docs operativas). 32 commits TDD (5 RED+GREEN pairs PR#1 + 5 PR#2 + housekeeping). **Hallazgo del explore**: `ProfileEditTrainerScreen` ya estaba 90% completo (form + validation + gym picker + GPS custom location + dual-write path), scope se redujo de "build wizard" a "fix bug + thin gate + mode param". **Quirk de Flutter 3.41**: `find.byType(PopScope)` returns 0 por type parametrizado — tests usan `byWidgetPredicate`. Smoke validado en device real con Firebase Console role flip + form save → `/home` → trainer discoverable en TrainersListScreen. 36 tests (25 PR#1 + 11 PR#2). SDD en `openspec/changes/archive/2026-06-08-trainer-profile-onboarding/` + main spec `openspec/specs/trainer-profile-onboarding/spec.md`. | C (originalmente asignado a B) |
| 2 | **`push-notifications-fcm`** ✅ — FCM push notifications end-to-end (chat + appointments + vínculos + reviews) | `1390393` (#126) + `4a156c5` (#127) + `fdaf460` (#128) + `6f09080` (#133) + housekeeping `dea6726` + archive `4551868` (2026-06-04) | APNs auth key configurado en Apple Developer + Firebase Console (Sandbox & Production, Team Scoped, ambos slots dev+prod bajo `com.backhaus.treino`); Xcode Push Notifications capability agregada (genera `aps-environment` en `Runner.entitlements`); `roles/cloudmessaging.editor` otorgado al Compute SA `1079774251763-compute@developer.gserviceaccount.com` (sino FCM rechaza con `messaging/mismatched-credential`). Step-by-step en `docs/setup/fcm-apns.md`. | 4 PRs chained bajo Strict TDD: **PR#1a #126** send-fcm helper compartido (multicast + stale token cleanup, ~250 LOC). **PR#1b #127** 4 CF triggers (`notifyOnChatMessage/Appointment/LinkChange/Review`) en `southamerica-east1` con guards de cascade (`after.reason == 'athlete-account-deleted'` para appointments, `'account-deleted'` para trainer_links) + iOS `UIBackgroundModes: [fetch, remote-notification]` + APNs setup doc inicial. **PR#2a #128** Flutter data + service (`FcmService` + `FcmTokenRepository` con `arrayUnion`/`arrayRemove` sobre `users/{uid}.fcmTokens` camelCase ADR-PN-001 + Riverpod `fcmLifecycleProvider` con `ref.listen(authStateChangesProvider)`). **PR#2b #133** handler (foreground SnackBar + background tap + cold-start via `addPostFrameCallback`) + `PermissionGate` (gated por `userProfile.displayName != null` ADR-PN-012, once-per-session, denial graceful) + deep-link router (`goDeepLink`) + `app.dart` wiring (`fcmLifecycleProvider` eager + 3 listeners + `scaffoldMessengerKey`). 5 bugs descubiertos durante smoke en iPhone real con sus fixes incluidos en PR#2b: (1) `FcmService.init` swallow APNS exception, (2) re-init después del grant en PermissionGate, (3) `application.registerForRemoteNotifications()` explícito en AppDelegate.swift para destrabar swizzling roto por el FlutterImplicitEngineDelegate pattern de Flutter 3.22+, (4) observability logs en sendFcm, (5) IAM grant manual al Compute SA. Smoke validado end-to-end en device real para las 4 surfaces × foreground/background/cold-start. 32 REQs, 66+2 SCENARIOs, 15 ADRs, +29 tests Flutter + 30 tests jest CF. SDD en `openspec/changes/archive/2026-06-04-push-notifications-fcm/` + main spec `openspec/specs/push-notifications-fcm/spec.md`. | C |
| 3 | **`coach-hub-link-management`** ✅ — historial vínculos + manage subscriptions | `54cb037` (#134 data layer) + `084b0c6` (#135 hard-delete assigned plans on link end) + `7926eac` (#138 UI completa) | Nada | Sección "HISTORIAL" en el dashboard del Coach Hub: vínculos terminados/cancelados con razón (declined / by-trainer / by-athlete) + fecha. Botones desde "TUS ALUMNOS" para Pausar / Terminar el vínculo (cualquier member puede). Filtros por estado. Útil para PFs con +5 alumnos donde la lista activa se llena. **Entregado en 3 PRs**: PR#134 data layer (`TrainerLink` model con `terminatedAt + terminationReason + pausedAt` + `TrainerLinkRepository.pause()/resume()/terminate()`), PR#135 CF cascade hard-deletea planes asignados al terminar vínculo (cleanup de routines orphaned), PR#138 UI completa en `CoachHubDashboardScreen` (924 LOC: `_HistorialList` widget renderiza terminated links con `_TerminatedStudentTile` + `_reasonDisplay()` helper para mapping de 3 reason values + `_StudentTile` con Pausar/Terminar buttons en activos + `_PausedStudentTile` con Reanudar en paused + 3 filter chips ACTIVOS/PAUSADOS/HISTORIAL drivendo `_statusFilterProvider` state + real-time sync via `trainerLinksStreamProvider` reemplazando el deprecated `linksForTrainerProvider` FutureProvider — architectural improvement hidden). 554 LOC widget tests cubriendo pending requests, pause/resume/terminate flows, section visibility filters. **Cierre confirmado 2026-06-09 vía audit profundo del codebase** (estaba shipped en silencio sin actualización de roadmap — sin SDD ni archive porque scope no justificaba el ritual). | B |
| 4 | **Recurring appointments** ✅ — sesiones recurrentes (entregado distinto al plan) | agenda redesign (#129) + `feat/agenda-recurring-cancel-series` (cierre de serie) | Nada — reusa índice `(trainerId,status,startsAt)` y rule Path 1 existentes | **Entregado vía el modelo trainer-driven (eager), NO el `RecurringAppointment` template + lazy del plan original.** `createRecurringByTrainer` materializa una cita por día/semana en un `WriteBatch` sobre un horizonte (N semanas); todas comparten un `recurringId`. UI: `NewSessionSheet` con toggle "Se repite" + multi-día + chips de semanas. Cancelación: por sesión (>24h) **+ toda la serie futura** vía `cancelFutureSeries` (chip "SERIE RECURRENTE" + botón "CANCELAR TODA LA SERIE" en `session_detail_sheet`). **Diferido (no bloquea beta)**: modelo `RecurringAppointment` + materialización lazy/infinita, patrón biweekly, editar-toda-la-serie. Aviso al alumno al cancelar depende de Etapa 2 (push). | C |
| 5 | **Excel polish + aliases dinámicos** ✅ — Excel template polish + `addAlias` CF end-to-end | `2bc5b14` (#136 catalog import 25→415 + es-AR técnica + dedup generics) + `3319a33` (#142 PR#1 template polish) + `6152e23` (#143 PR#2a addAlias CF + parity tests) + `63d08f9` (#144 PR#2b client wire) + housekeeping `bc8ff25` (`docs/setup/firebase-hosting-callable-functions.md`) | Cloud Function `addAlias` deployada en `southamerica-east1` con Compute SA `roles/run.invoker` (suficiente para server-to-server + mobile). **Browser CORS gap**: org policy `Domain Restricted Sharing` impide `allUsers` invoker → Coach Hub web no puede invocar la CF sin Firebase Hosting rewrites (deuda documentada, no bloquea mobile/server). | 3 PRs chained bajo Strict TDD (SDD `coach-excel-polish`): **PR#1 #142** template polish (~180 LOC) — `kColumnWidthsDay`/`kColumnWidthsPlan` constantes + hoja `Instrucciones` con guía de columnas, valores válidos de `Nivel`, ejemplo pre-cargado. Validation dropdown nativo no soportado por `excel: ^4.0.6` → reemplazado por texto referencial (scope tradeoff aceptado). **PR#2a #143** addAlias CF v2 en `southamerica-east1` (~310 LOC) — `runAddAlias(app, callerId, exerciseId, alias)` pure handler con auth gate + role gate (`users/{callerId}.role == 'trainer'`) + exercise existence check + dedup + `arrayUnion(normalized)`. TS `normalize()` literal port char-by-char del Dart `normalize()` con comentarios `// NORMALIZE-PARITY: see ADR-CXP-006` en ambos lados (R1 load-bearing). 14 jest emulator tests cubriendo auth/role/normalize/dedup/idempotency/accent parity. **PR#2b #144** client wire (~160 LOC) — `cloudFunctionsProvider` Riverpod provider + `unawaited(_addAlias(picked.id, rowName))` fire-and-forget AFTER setState BEFORE next await en `_pickExerciseFor` (ADR-CXP-009), errores silenciosos con `debugPrint`. 4 widget tests con `ProviderScope.override` del cloudFunctions provider. **Progreso 2026-06-08**: PR#136 expandió el catálogo dev de 25 → 415 ejercicios (free-exercise-db import + dedup de generics + hand-written es-AR `techniqueInstructions` para ~80 ejercicios core + nuevos muscleGroup `cardio` y `fullbody`). Verify PASS-WITH-DEVIATIONS: 27/27 REQs + 21/21 SCENARIOs (727-747) + 12/12 ADRs honored, 0 CRITICAL, 4 WARNINGs ops/docs, 2 SUGGESTIONs cosmetic. Flutter 1691/1691 + jest 14/14. Archive en `openspec/changes/archive/2026-06-09-coach-excel-polish/` + main spec `openspec/specs/coach-excel-polish/spec.md`. | B |
| 6 | **App Check + Crashlytics + Analytics** ⏳ — telemetría básica | `feat/telemetry-app-check-crashlytics-analytics` | App Check habilitado con DeviceCheck (iOS) + Play Integrity (Android); Crashlytics activado; Analytics conectado a BigQuery export | `firebase_app_check`, `firebase_crashlytics`, `firebase_analytics` packages. App Check rules en Firestore para gate de servicios. Crashlytics captura crashes + non-fatals. Analytics eventos: `session_start`, `routine_started`, `routine_finished`, `plan_assigned`, `link_requested`, `link_accepted`, `chat_message_sent`, `appointment_created`. Dashboard custom en BigQuery o sheets export. | A |
| 7 | **`trainer-reviews`** ✅ — Reviews + ratings de PFs end-to-end | `8046374` (#119) + `207bbcc` (#122) + `8557717` (#123) + archive `025fc12` (2026-06-03) | Deploy de `firebase deploy --only firestore:rules,firestore:indexes,functions --project treino-dev` (primer deploy de la CF aggregate falló por Eventarc IAM bootstrap delay; resolvió solo con retry ~5 min después). | 3 PRs chained bajo Strict TDD: **PR#1 #119** data layer (Review freezed model + ReviewRepository + providers + TrainerPublicProfile `averageRating`/`reviewCount` aggregate fields con dual-write guard `_trainerPublicFields_excludes_aggregates` ADR-RV-005 + `/reviews/{reviewId}` Firestore rules + composite index `(trainerId, createdAt)` + CF `reviewAggregate` `onDocumentWritten` en `southamerica-east1` con 8 jest emulator tests cubriendo create/update/delete/idempotency/missing-doc paths). **PR#2 #122** athlete write/edit flow (`ReviewNotifier` AsyncNotifier.family + `StarRatingInput` + `ReviewBottomSheet` con 3 trigger variants new/edit/30day + Trigger #1 post-termination con `ProviderScope.containerOf` dispose-safe + Trigger #2 30-day check con `ref.listen` + post-frame callback + `_promptCheckScheduled` guard + `SharedPreferences` key `review_prompt_shown_{linkId}` set BEFORE sheet opens para cubrir cancel path + `ReviewCta` DEJAR/EDITAR en `TrainerPublicProfileScreen`). **PR#3 #123** display layer (`StarRatingDisplay` read-only + `ReviewTile` con "Usuario eliminado" fallback ADR-RV-009 + `TrainerReviewsSection` con empty state "Sin reseñas todavía" + `TrainerListTile` star+avg+count badge oculto cuando `reviewCount==0` ADR-RV-010 + `TrainerStatsRow` refactor con `profile` param requerido + integración en `TrainerPublicProfileScreen`). 32 commits TDD (16 pairs RED+GREEN). UX gap pre-existente descubierto en smoke: `_TrainerHeader` en `AthleteCoachView` no era tappable (athletes con link activo no tenían path al perfil público del PF) — fix incluido en PR#2 con `GestureDetector` → `/coach/trainer/:uid`. Bottom sheet transparency fix también (showModalBottomSheet default es transparente). +88 tests Dart (1528 total) + 8 tests Jest CF. SDD en `openspec/changes/trainer-reviews/`. | C |
| 8 | **Localización i18n (es-AR oficial + scaffold inglés)** ✅ — Mobile 100% migrado; Coach Hub web diferido | `22fbfab` (#146 PR#1 infra + auth ~30 keys) + `1b1b18c` (#147 PR#2a agenda_formatters extract) + `a81f25c` (#150 PR#2b Coach + Agenda + Workout ~126 keys + 3 ICU plurales + 2 interpolations) + `b5e0eb8` (#152 PR#3a inline strings batch ~75 keys + `check_in_strings.dart` eliminado) + `f69c095` (#154 PR#3a2 routine_editor periodization ~24 keys + 3 test files rename + 2 fixes pre-existentes en main) | Nada — setup puro en `pubspec.yaml` (`flutter_localizations` + `intl ^0.20.0`) + `l10n.yaml` + ARBs en `lib/l10n/` | 5 PRs chained bajo Strict TDD (SDD `i18n-localization`). **Setup**: `flutter_localizations` + `intl ^0.20.0` + `l10n.yaml` con `output-class: AppL10n`, codegen via `flutter gen-l10n` produce `lib/l10n/app_l10n*.dart`. **Estrategia Replace Direct** (ADR-I18N-001): borrar las clases `*Strings.dart` (`AuthStrings`/`CoachStrings`/`AgendaStrings`/`WorkoutStrings`/`CheckInStrings`), reemplazar call sites por `AppL10n.of(context).x`. **Locale**: ADR-I18N-005 `resolveLocale` SIEMPRE devuelve `es-AR` hardcoded (inglés es scaffold-only hasta que QA traduzca) — descubierto y fixeado durante smoke de PR#1 (language-only match contra scaffold vacío rompía UI). **Exclusión documentada**: `AuthFailure.userMessage` queda hardcoded es-AR (domain layer sin BuildContext, ADR-I18N-002). **Refactor preparatorio**: `agenda_formatters.dart` extract antes de borrar `AgendaStrings` (formatters no son strings i18n, ADR-I18N-003). **ICU**: 3 plurales (pickerAddButton, historialShowMore, pickerSheetApply — solo `=1` + `other` en es-AR, ADR-I18N-007) + 3 interpolations (bookingConfirmBody, slotBookedByLabel, routineEditorIncompleteSetsLabel). **Hardening Q3**: `intl_es.arb` poblado con auth keys reales (copia defensiva de `intl_es_AR.arb`) — si alguna vez se quita el lock de `resolveLocale`, devices con locale `es` plano ven español válido en lugar de strings vacíos. **Total**: ~250 keys ARB, suite growth 2052 → 2328 (+276 tests). **Deferred a mini-SDD futuro** (audit completo + plan listo en Engram): Coach Hub web ~55 keys + `localizationsDelegates` en `CoachHubApp` — esperar a que W1.x estabilice copy antes de migrar (Coach Hub web está en infancia, migrar W1.1 hoy sería work que se reestructura). Archive SDD en `openspec/changes/i18n-localization/` + main spec `openspec/specs/i18n-localization/spec.md`. | C |
| 9 | **Athlete self-routines** ✅ — el atleta arma sus propias rutinas privadas | `feat/athlete-self-routines-pr{1,2,3}` (3 chained PRs) + `dea8cfc` (#137 supersets en self-create) + **extensión home (2026-06-18)**: `b72ca2c` (#191 PR#1 home today's routine) + `854e824` (#193 PR#2 active marker) | Deploy de `firestore.rules` + `firestore.indexes.json` a `treino-dev` (composite index `routines(createdBy, source, status, createdAt DESC)`) | **Gap del plan original** — Fase 2 línea 80 asumía que solo PFs crean rutinas. SDD `athlete-self-routines` cierra el gap con 3 PRs chained: **PR1 #114** data foundation (`Routine.createdBy` + `RoutineStatus` enum + rules + index + repo `createUserOwned/listUserCreated/archive` + provider + `listAll → listSystemTemplates` rename), **PR2 #115** editor parametrization (sealed `RoutineEditorMode { TrainerAssigning, TrainerTemplating, SelfCreating }` + sidecar `TrainerTemplating` para preservar el flow del PF), **PR3** UI section `MisRutinasSection` + wire del CTA en Workout tab. Soft-delete via `RoutineStatus.archived` (preserva integridad de `SessionLog`). Cap client-side 10. Edit de contenido post-create diferido. **Extensión 2026-06-08 (#137)**: supersets habilitados en modo `SelfCreating` — atletas pueden armar supersets con el mismo editor que los PFs. Dropped el `_isTrainerMode` gate sobre `allowSuperset/onAddSuperset`; trainer metadata (Split/Level) sigue trainer-only. Round-robin superset player ya agrupaba por `supersetGroup` sin source check, así que reproducción funciona sin cambios. SCENARIO-SS-003 flipped + RER-024 added. **Extensión 2026-06-18 — home "Empezar entrenamiento" inteligente** (2 PRs sin SDD, scope chico): **PR#1 #191** `todaysRoutineProvider` con prioridad trainer-assigned > single self-created > (marker) y day calc progress-based (Hevy-style: `lastFinished.dayNumber % numDays + 1`, skipped days no vuelven), card en home renderea datos reales del día (nombre, músculos deduped, ejercicios, duración authored vs computed con tilde), tap lleva a `RoutineDetailScreen(initialDayNumber, initialWeekIndex)` con el día pre-seleccionado vía query params `?day=N&week=M`. **PR#2 #193** active marker para multi-rutina self-created: `UserProfile.activeRoutineId: String?` (campo opcional, no requiere migración), `activeRoutineProvider` derived de `userProfileProvider + userCreatedRoutinesProvider` con stale-id silent-null, `todaysRoutineProvider` gana tier 3, UI en `MisRutinasSection` con chip "ACTIVA" + accent border + overflow menu toggle MARCAR/DESMARCAR (solo cuando hay 2+ rutinas — con una sola la activación es implícita). Sin método repo nuevo: reusa `UserRepository.update(uid, {'activeRoutineId': ...})`. +38 tests entre los dos PRs (25 PR#1 + 13 PR#2), full suite 2651/0/48. **Discovery del smoke (Vicente)**: `routine.name` puede quedar desincronizado de `routine.days` cuando un PF renombra una rutina asignada sin resetear el schedule — bug data upstream del editor del trainer, NO de los providers nuevos (follow-up #15 abierto). | C |
| 10 | **`chat-media-messages`** ✅ — chat con foto + video inline (reemplaza fallback a WhatsApp) | `047d988` (#194 PR#1 data foundation) + `8654364` (#195 PR#2 UI) | Deploy de `firestore.rules` (relajar `text.size() > 0` para permitir media-only) + `storage.rules` (path `chatMedia/{chatId}/` con bound de tamaño y tipos) + redeploy de CF `notify-chat-message` (body refleja media cuando no hay caption). | SDD `chat-media-messages` (`openspec/changes/chat-media-messages/`). Reemplaza el fallback a WhatsApp por la single highest-leverage gap entre "tenemos chat" y "el chat reemplaza WhatsApp" (research PT). **PR#1 #194 data foundation** — `Message.text` ahora nullable + `Message.media: MessageMedia?` (sealed: image/video con `storagePath`, `width`, `height`, `durationMs?`) + `MediaType` enum + Firestore rule message-create permite media-only + Storage rule `chatMedia/{chatId}/{messageId}_{filename}` (bound tamaño + tipos image/video) + `ChatRepository.uploadAndSendMedia()` con upload progress + `lastMessageText` derivado con preview "📷 Foto" / "🎥 Video" para media-only + CF `notifyOnChatMessage` actualizada para body de push reflejando media. **PR#2 #195 UI** — `image_picker` con `imageQuality: 80` para gallery pick + composer con attach button + progress bar durante upload + `ChatImageBubble` con `CachedNetworkImage` + tap-to-open fullscreen viewer (`InteractiveViewer` pinch-zoom) + `ChatVideoBubble` reusa el video player nativo de Firebase Storage del proyecto + caption opcional debajo del media + i18n keys nuevas en es-AR / es / en (scaffold) para composer/progress/error. **Out of scope explícito**: unread-count badges (futuro), read receipts, voice messages, file/PDF attachments, group chats, inline YouTube, server-side video compression/transcoding, optimistic send (se decidió upload-then-send). Strict-TDD coverage across las 5 layers (domain, repository, rules, presentation, cloud function). | C |

### Dependencias entre etapas

```
1 ──┬──► 3
    │
2 ──┴──► 4, 7
         │
         ├──► 5 (puede ser paralelo a todo, si GCP disponible)
         ├──► 6 (telemetría puede arrancar después de Etapa 1)
         └──► 8 (i18n al final — toca todo el codebase)
```

- **1 antes de 3 y 7**: el PF tiene que poder completar su perfil antes de que tenga sentido administrarse alumnos o recibir reseñas.
- **2 antes de 4 y 7**: notifications es prerequisito UX de recurring + reviews (sino los usuarios no se enteran).
- **5 paralelo**: independiente del resto.
- **6 después de 1**: telemetría puede arrancar después de tener el flow básico de onboarding del PF funcionando.
- **8 al final**: i18n toca todos los strings — mejor hacerlo cuando el codebase de Fase 6 está cerrado para no doblar el trabajo.

### División entre los 3 devs (paralelización)

| Dev | Etapas |
|---|---|
| **A** | Etapa 2 (Push notifications) ✅ (entregado por Dev C) + Etapa 6 (App Check + Crashlytics + Analytics) ⏳ — track backend + telemetría |
| **B** | Etapa 1 (Trainer profile UI) ✅ (entregada por Dev C) + **Etapa 3 (Coach Hub polish)** ✅ + **Etapa 5 (Excel polish + aliases dinámicos)** ✅ (catalog #136 + template #142 + CF #143 + wire #144) — track Coach Hub + onboarding del PF |
| **C** | **Etapa 4 (Recurring appointments) ✅** + **Etapa 7 (Reviews + ratings)** ✅ + Etapa 8 (i18n) ⏳ — track features de mobile + i18n al final |

**Estimación**: ~4-6 semanas en paralelo con los 3 devs. Push notifications (Etapa 2) es el ítem más arriesgado por la dependencia con APNs/Apple Developer setup + posible bloqueo de Cloud Functions si IAM sigue sin Owner. Recommendation: empezar 1, 2, 4 en paralelo desde el día 1.

### Cross-cutting concerns

- **GCP IAM blocker resuelto parcialmente**: Etapas 2 y 5 ya entregadas con CFs deployadas (Compute SA `roles/run.invoker` alcanza para server-to-server + mobile). **Deuda restante (no bloquea beta)**: org policy `Domain Restricted Sharing` impide `allUsers` invoker → browsers (Coach Hub web) no pueden invocar CFs callable v2 sin Firebase Hosting rewrites. Solución documentada en `docs/setup/firebase-hosting-callable-functions.md` — implementación pendiente cuando Coach Hub web se sirva desde Firebase Hosting (follow-up activo).
- **Schema migrations**: la mayoría de las etapas agregan colecciones nuevas (`reviews`, `recurring_appointments`) o campos opcionales (`fcm_tokens`) — no breaking.
- **Privacy & security**: reviews son públicos pero comments pueden moderarse (futuro). Reglas Firestore: write only by `athleteId` del review.
- **Performance**: i18n agrega ~30-50 KB al bundle por idioma — aceptable.

### Open questions a resolver durante el sprint

1. **Push notifications + GCP block**: ¿hay un proxy alternativo (Cloud Run, Vercel function, server propio) que podamos levantar sin Owner de GCP? Decisión a tomar antes de Etapa 2.
2. **Reviews — moderación**: ¿reviews con texto van con moderación previa o post-hoc? Post-hoc es más simple pero permite spam. Para MVP: post-hoc + flag para reportar.
3. **i18n — alcance del inglés**: ¿shippeamos el inglés en Fase 6 o queda solo el scaffold? Decisión a tomar antes de Etapa 8.

Actualizado a 2026-06-18.

| Fase | Estado | Estimado original | Real / proyectado |
|---|---|---|---|
| Fase 1 (Auth + Firebase + ProfileSetup) | ✅ Cerrada 2026-05-13 | ~2026-05-08 | +5 días (drama Apple Sign-In) |
| Fase 2 (Home + Rutinas) | ✅ Cerrada ~2026-05-15 | ~2026-05-29 | **Adelantada ~2 semanas** |
| Fase 3 (Feed + sub-fase 5.5 + Etapa 6 inbox + Etapa 7 profile-rewrite + Etapa 7.1 account-deletion) | ✅ Cerrada **inicialmente** 2026-05-19; re-cerrada 2026-05-22 con Etapa 6 (`feed-friend-requests-inbox`, PR #78); Etapa 7 cerrada 2026-05-28 (`profile-screen-rewrite`, 4 PRs); Etapa 7.1 cerrada 2026-06-01 (`account-deletion`, 3 PRs) | ~2026-06-12 | **Adelantada ~2 semanas** (incluyó sub-fase 5.5 + Etapa 6 + Etapa 7 + 7.1 imprevistas, todas con justificación UX o cierre de stubs) |
| Fase 4 (Workout++) | ✅ Cerrada 2026-05-21 (Etapa 5 insights el 19; Etapa 6 wire-real-stats el 21) | ~2026-07-03 | **Adelantada ~6 semanas** |
| Fase 5 (Coach + Excel + Coach Hub web) | ✅ Cerrada 2026-05-26 (8/8 etapas + 2 follow-ups #93 #94) | ~2026-08-07 | **Adelantada ~10 semanas** vs proyección original (pivot Etapa 8 a client-side ahorró tiempo de IAM/GCP setup) |
| Fase 6 (Producto-ready: trainer UI + push + agenda recurrente + telemetría + reviews + i18n + self-routines + chat-media + insights polish + bidirectional data channel + exercise notes) | ✅ **CERRADA (mobile)** 2026-06-12 core + extensiones + polish — Etapa 6 telemetría ✅ (Crashlytics #108, Analytics #109, App Check #110); Etapa 7 reviews ✅ 2026-06-02 (`trainer-reviews`); Etapa 4 recurring ✅ 2026-06-04 (trainer-driven eager + cancel-serie); Etapa 2 push notifications ✅ 2026-06-04 (`push-notifications-fcm`, 4 PRs + archive `4551868`); Etapa 1 trainer profile UI ✅ 2026-06-08 (`trainer-profile-onboarding`, 2 PRs #139 #141 + archive `aaf5243`); **Etapa 3 Coach Hub polish ✅ confirmada 2026-06-09 vía audit profundo (PR#134 data + PR#135 CF + PR#138 UI)**; **Etapa 9 self-routines ✅** + supersets en self-create (#137) + **extensión home 2026-06-18** (#191 PR#1 today's routine + #193 PR#2 active marker); **Etapa 5 Excel polish + aliases dinámicos ✅ 2026-06-09** (`coach-excel-polish` SDD: catalog #136 + template #142 + addAlias CF #143 + client wire #144); **Etapa 8 i18n mobile ✅ 2026-06-12** (5 PRs #146/#147/#150/#152/#154, ~250 keys ARB, suite 2052→2328); **Etapa 10 chat-media ✅ 2026-06-19** (`chat-media-messages` SDD, 2 PRs #194 data + #195 UI, foto/video inline en chat PT↔athlete, reemplaza fallback a WhatsApp). **Polish post-build #2 (2026-06-19)**: Insights granular ✅ (#196 — taxonomía colapsada 6→10 grupos alineada al exercise picker, cutoff 2B sin migración de data legacy), chat unread-count ✅ (#197 — cierra el out-of-scope explícito del SDD chat-media), body highlighting ✅ (#198 — masks dinámicas en Insights + Home con intensidad `done/target` clampada [0,1] + fallback 0.6 off-plan, nuevo asset `mask_back_triceps.png`). **Bug operativo descubierto** (2026-06-19): el feed estaba roto desde build #1 porque el index composite `posts (privacy, createdAt)` estaba en `firestore.indexes.json` pero nunca se había deployado a `treino-dev` — fix: `firebase deploy --only firestore:indexes`, follow-up abierto para automatizar via GitHub Action. **Polish post-build #2 (2026-06-29) — bidirectional data channel y notas por ejercicio**: SDD `trainer-athlete-set-logs` ✅ (3 PRs — `1ce1a07` #199 fix wiring de `publicProfileRepository` en `sessionRepositoryProvider` que destrabó las queries cross-user, `019073f` #200 PR#1 foundation + web — relajación de Firestore rule sobre `session_shares` para permitir que el trainer linkeado lea `setLogs/` del athlete + nuevo CF `sync-session-share` con 238 LOC de tests + extracción de widget `session_exercise_block.dart` que renderea exercise/set breakdown reutilizable entre mobile y web, + UI en Coach Hub web Alumno detail → Entrenamientos tab expandible, + 5 ADRs SDD, + 30+ tests, + 20 i18n keys en es-AR/es/en, `49bc1ca` #201 PR#2 mobile — wire en `athlete_detail_screen.dart` para que el PF mobile vea la misma session history granular que ve en web). Cierra recommendation 8.6 del research PT ("Máxima"). SDD `exercise-notes` ✅ (`7ec2af9` #202 — PF agrega notas opcionales por ejercicio en el editor; athlete las ve en el `session_player` durante el entrenamiento, widget `coach_note.dart` reutilizable + integración no-intrusive en `exercise_slot_row.dart` y `session_player_screen.dart`, 5 archivos l10n actualizados, +407 LOC tests, 5 artefactos SDD). **Coach Hub web i18n deferred a mini-SDD futuro**. **Build #3 pendiente** — bundle de polish post-#2 (#196 a #202, 7 PRs) acumulado, sin entregar todavía a TestFlight. | ✅ 2026-06-12 core / 2026-06-29 con extensiones + polish | Proyectada ~2026-06-15 — **3 días adelantada en el core** |
| Fase 7 (Monetización + Lanzamiento beta) | 🔄 **En curso — TestFlight build #2 LIVE para Internal Beta 2026-06-18** (`0.1.0+2`, 80 MB IPA, cero ITMS warnings, 8 testers internos). **Build #1 entregado 2026-06-17** (`0.1.0+1`, App ID `6781307745`, app name "TREINO Fitness" en App Store Connect porque "TREINO" estaba ocupado, primary language Spanish (Mexico), 1 ITMS-90683 location flag non-blocking) — sigue activo en paralelo por si surge regresión. **Build #2 incluye** vs #1: fix ITMS-90683 location permission (`NSLocationAlwaysAndWhenInUseUsageDescription` en Info.plist) · extensión home today's routine + tap → día correcto (#191) · active marker multi-rutina (#193) · chat con foto/video inline (#194 + #195) · Coach Hub Web W2 PR7 header detalle (#190) · W2 PR8 l10n delegates + Rendimiento (#192) · W3.4 Facturación TREINO (#189). **Build #3 candidate (acumulando, sin entregar todavía a TestFlight) — 7 PRs polish post-#2**: Insights granular #196 + chat unread #197 + body highlighting + tríceps asset #198 + fix wiring publicProfileRepository #199 + SDD `trainer-athlete-set-logs` PR#1 foundation/web #200 + PR#2 mobile #201 + SDD `exercise-notes` #202. **Pre-build #1 polish wave** (todavía vigente): bleed-through fix (#166), exercise name fallback + asset cascade con `assets/muscles/` movement patterns (#176), branded icon TR mint (#178), Info.plist permissions + Export Compliance + iOS 14.0 deployment + aps-environment production (#164), audit batches HIGH-severity findings (#171 a11y · #174/#177 usability · #179 states · #94bc049 navigation · #737cb5f error-prevention) · full-screen mis-ejercicios/mensajes (#183) · custom exercise muscle taxonomy unification con secondary muscle + equipment (#186 / `51973bc`). **Next**: smoke en device del build #2 con foco en los 7 PRs nuevos del candidate (todos visibles al usuario), decidir bump a `0.1.0+3` + delivery a TestFlight cuando smoke valide; ya hay 2 features grandes del candidate (bidirectional set-logs PT↔athlete, exercise-notes) que necesitan smoke real con cuentas linkeadas trainer↔athlete. Después: pagos (Mercado Pago/Stripe), verificación profesional, deep links, screenshots para store, Gemini Excel (cuando GCP esté activo), group chats, video calls. **Follow-ups operativos abiertos**: trainer editor data inconsistency descubierta en smoke Vicente (`routine.name` desincronizado de `routine.days`) · CI auto-deploy de `firestore.indexes.json` para no repetir el bug de feed roto · cleanup de 2 indexes huérfanos en `posts` sin `createdAt`. | 🔄 build #2 live 2026-06-18 / build #3 candidate acumulado en main 2026-06-29 | Proyectada ~2026-06-30 para TestFlight Internal estable con build #3 |

**Total**: ~17 semanas full-time originales → al ritmo actual, ~7-8 semanas reales (~1.5-2 meses) para cerrar Fases 6 + 7. El ritmo de Fase 3-5 con 3 devs en paralelo + SDD disciplinado siguió superando las proyecciones.

Buffer recomendado: +25% para imprevistos. **Riesgo principal de Fase 6**: GCP IAM sigue sin Owner — Etapas 2 (push) y 5 (aliases dinámicos) ya cerraron con CFs deployadas, pero org policy `Domain Restricted Sharing` impide `allUsers` invoker → browsers callan a CFs vía CORS preflight bloqueado. Deuda activa: implementar Firebase Hosting rewrites para Coach Hub web (`docs/setup/firebase-hosting-callable-functions.md`). Para etapas restantes, resolver Owner access seguiría siendo prerequisito para evitar acumular deuda similar.

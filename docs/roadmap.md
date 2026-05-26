# Roadmap — TREINO

Estado de las fases y desglose detallado de Fase 5 (en curso).

## Estado por fase

- [x] **Fase 0** — Bootstrap + tema + 5 tabs vacías + Phosphor (commits `cf09068` a `c6d5fea`).
- [x] **Fase 1** — Auth (email/Google/Apple) + Firebase + Firestore + ProfileSetup + Roles & guards. ✅ **COMPLETA** — 7/7 etapas mergeadas. Cerró 2026-05-13 con Apple Sign-In (PR #10).
- [x] **Fase 2** — Home (paridad con mockup Mobile Home) + Rutinas básicas read-only. ✅ **COMPLETA** — 5/5 etapas mergeadas. Cerró ~2026-05-15 con Wire Home → Plantillas (PR #18).
- [x] **Fase 3** — Feed social (amigos · mi gym · público) + perfiles públicos. ✅ **COMPLETA** — 6/6 etapas + sub-fase 5.5 (`user-public-profiles`) mergeadas. Cerró 2026-05-22 con Etapa 6 (feed-friend-requests-inbox, PR #78).
- [x] **Fase 4** — Workout++ (session tracking, sesión activa, post-entreno, historial, insights, wire de stats). ✅ **COMPLETA** — 6/6 etapas mergeadas. Cerró 2026-05-21 con Etapa 6 (wire-real-stats, 4 PRs #56/#57/#65/#67 + archive #69) tras Etapa 5 (insights, PR #51, mergeada 2026-05-19). IA buscador y videos quedaron deferrables a Fase 4.5.
- [ ] **Fase 5** — Coach / Personal Trainer (discovery con geohash, chat, agenda, planes asignados, importación de planes Excel). 🔄 **6/8 etapas hechas** (Etapas 1, 2, 3, 4, 5, 6 ✅ + sub-fase `shared-with-trainer` ✅; Etapas 7 y 8 pending).
- [ ] **Fase 6** — Polish + lanzamiento beta (TestFlight + Play Internal). Incluye App Check, Analytics, Crashlytics, deep links, localización, app icon final.

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
| 3 | Segments MI GYM + PÚBLICO ✅ | `8ae066f` (#26) | Nada | Query por `gymId` del UserProfile para MI GYM. Query "todos posts con privacy=public" para PÚBLICO. Bug pre-existente conocido: composite index `posts(privacy, authorGymId)` faltante en `firestore.indexes.json` — feed MI GYM devuelve vacío en runtime; tracked como follow-up. | B |
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

- **Bug MI GYM feed**: composite index `posts(privacy, authorGymId)` faltante en `firestore.indexes.json` — separate PR pendiente.
- **Backfill rules tests + CI automation**: extender `scripts/rules_test/rules.test.js` con tests de etapas previas + cablear GitHub Action que corra el suite on PRs que toquen `firestore.rules`.
- **Backfill script `scripts/backfill_user_public_profiles.js`**: documentado pero NO ejecutado — decisión ops para users legacy.
- **UX inconsistency botón SEGUIR**: dice "solicitud enviada" después del tap — copy mismatch con Twitter-style expectation. Path A propuesto: rename a "AGREGAR".

### Pre-flight checklist

- ✅ Etapa 1: colecciones `posts` + `friendships` pobladas via `scripts/seed_posts.js`.
- ✅ Etapa 5.5: nueva collection `userPublicProfiles` deployada + rules deployadas a `treino-dev`.

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
- IA buscador de ejercicios (Gemini).
- Videos en ejercicios (asset pipeline + Firebase Storage para video).
- Bloques y super series complejos en la rutina (extensión del modelo `Routine`).

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

## Fase 5 — desglose en 8 etapas

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
| 7 | **Coach Hub bootstrap (web)** ⏳ | `feat/coach-hub-bootstrap` (pendiente) | Build target Flutter Web configurado; Firebase hosting site creado en Console | Nuevo entry point `lib/main_coach_hub.dart` con tema propio (mismo Mint Magenta) + routing limitado a rol trainer + landing page autenticada con dashboard. Reutilizá `firestoreProvider`, `authStateChangesProvider`, `UserProfile`. Auth restringe acceso a `role == 'trainer'` — redirect a página de info para no-trainers. Web hosting via Firebase Hosting site `coach-treino.web.app` (nombre tentativo). NO incluye editor de planes ni uploader — eso es Etapa 8. | A o C |
| 8 | **Excel import (Coach Hub + Cloud Function)** ⏳ | `feat/coach-excel-import` (pendiente) | Cloud Function `parsePlan` deployada en Firebase; Storage bucket habilitado | Cloud Function HTTP onCall `parsePlan`: recibe path al archivo subido a Storage temporal + `mode: 'template' \| 'ai'`. Modo template: parser determinístico para la plantilla `.xlsx` oficial TREINO (~150 LOC Node.js). Modo AI: Gemini API extrae JSON estructurado del Excel arbitrario; key vive en secret manager. Output JSON mapea a Routine schema. Coach Hub agrega flow de upload → preview → edit → assign. Routine resultante tiene `source: 'excel-import'`. Manejo de errores: archivo inválido, schema incompleto, ambigüedad de ejercicios (Gemini debe matchear a `exercises` catalog). | A |

### Dependencias entre etapas

```
1 ✅ ──┬──► 2 ✅
       ├──► 3 ✅ ──┬──► 4 ✅
       │           ├──► 5 ✅
       │           └──► 6 ✅
       └──► 7 ⏳ ──► 8 ⏳
```

- **1 bloqueante absoluto**: sin el modelo `TrainerLink` + Routine extendida + reglas, ninguna otra etapa puede empezar.
- **2 y 3 paralelo**: discovery y link lifecycle son independientes una vez que 1 está; un dev puede agarrar 2 y otro 3.
- **4, 5, 6 dependen de 3**: planes asignados, chat y agenda solo funcionan entre pares vinculados.
- **7 paralelo a 2-6**: el bootstrap de Coach Hub web puede empezar apenas Etapa 1 está y avanzar en paralelo con todo el track mobile.
- **8 depende de 7**: el Excel import vive principalmente en el Coach Hub — necesita el web target ya bootstrapeado.

### División entre los 3 devs (paralelización)

| Dev | Etapas |
|---|---|
| **A** | Etapa 7 (Coach Hub bootstrap) ⏳ + Etapa 8 (Excel + Cloud Function) ⏳ — backend-leaning + dueño del web target |
| **B** | Etapa 1 (foundations + reglas) ✅ + Etapa 3 (link lifecycle) ✅ + Etapa 4 (plans mobile) ✅ — track de modelos + features de planes (continuidad con la familia Routine de Fase 2/4) |
| **C** | Etapa 2 (discovery) ✅ + Etapa 5 (chat) ✅ + Etapa 6 (agenda) ✅ — UI-heavy con paquetes nuevos (`table_calendar`, geohash queries) |

**Reasignación 2026-05-20**: Etapa 1 movida de A a B. B arranca foundations mientras C cierra Etapa 6 de Fase 4 y A se incorpora más tarde. La continuidad B → 1 → 3 → 4 también ayuda — el modelo de datos lo arma quien después construye los features que lo consumen.

**Estimación**: ~3-4 semanas en paralelo con los 3 devs era el plan original. **Real (parcial)**: Etapas 1-6 cerradas entre 2026-05-19 y 2026-05-26 (~7 días) — adelanto significativo. Etapas 7-8 (Coach Hub web + Excel/Cloud Function) son las más arriesgadas: primer target Flutter Web + primera Cloud Function + Gemini API. Mantener +30% buffer para esas 2 etapas finales.

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

La definimos durante Etapa 8 con Dev A. Contrato propuesto:

- Hoja 1: `Plan` → `name, daysPerWeek, durationWeeks, level`.
- Hoja 2..N: `Día 1`, `Día 2`, etc → columnas `Ejercicio, Series, Reps Min, Reps Max, Peso Kg, Descanso Seg, Notas`.
- Las filas vacías se ignoran. `Ejercicio` debe matchear un nombre del catálogo `exercises` (o se reporta como warning para edit manual).



Actualizado a 2026-05-26.

| Fase | Estado | Estimado original | Real / proyectado |
|---|---|---|---|
| Fase 1 (Auth + Firebase + ProfileSetup) | ✅ Cerrada 2026-05-13 | ~2026-05-08 | +5 días (drama Apple Sign-In) |
| Fase 2 (Home + Rutinas) | ✅ Cerrada ~2026-05-15 | ~2026-05-29 | **Adelantada ~2 semanas** |
| Fase 3 (Feed + sub-fase 5.5 + Etapa 6 inbox post-cierre) | ✅ Cerrada **inicialmente** 2026-05-19; re-cerrada 2026-05-22 con Etapa 6 (`feed-friend-requests-inbox`, PR #78) | ~2026-06-12 | **Adelantada ~3 semanas** (incluyó sub-fase 5.5 + Etapa 6 imprevistas, ambas con justificación UX) |
| Fase 4 (Workout++) | ✅ Cerrada 2026-05-21 (Etapa 5 insights el 19; Etapa 6 wire-real-stats el 21) | ~2026-07-03 | **Adelantada ~6 semanas** |
| Fase 5 (Coach + Excel + Coach Hub web) | 🔄 6/8 etapas (1-6 ✅, 7-8 ⏳) | ~2026-08-07 | Proyectada cerrar ~2026-06-05 (**~9 semanas adelantada** si se mantiene el ritmo de los 3 PRs/día visto en Coach Hub mobile track) |
| Fase 6 (Polish + lanzamiento beta) | ⏳ | ~2026-08-21 | Proyectada ~2026-06-20 |

**Total**: ~17 semanas full-time originales → al ritmo actual, ~6-7 semanas reales (~1.5 meses) para cerrar todo. El ritmo de Fase 3-5 con 3 devs en paralelo + SDD disciplinado siguió superando las proyecciones.

Buffer recomendado: +25% para imprevistos. **Atención con Fase 5 Etapa 7** — Coach Hub web es la primera fase con target Flutter Web, riesgo de configuración + curva de aprendizaje. Etapa 8 (Excel + Cloud Function) trae Gemini API y Cloud Functions por primera vez.

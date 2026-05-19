# Roadmap — TREINO

Estado de las fases y desglose detallado de Fase 4 (en curso).

## Estado por fase

- [x] **Fase 0** — Bootstrap + tema + 5 tabs vacías + Phosphor (commits `cf09068` a `c6d5fea`).
- [x] **Fase 1** — Auth (email/Google/Apple) + Firebase + Firestore + ProfileSetup + Roles & guards. ✅ **COMPLETA** — 7/7 etapas mergeadas. Cerró 2026-05-13 con Apple Sign-In (PR #10).
- [x] **Fase 2** — Home (paridad con mockup Mobile Home) + Rutinas básicas read-only. ✅ **COMPLETA** — 5/5 etapas mergeadas. Cerró ~2026-05-15 con Wire Home → Plantillas (PR #18).
- [x] **Fase 3** — Feed social (amigos · mi gym · público) + perfiles públicos. ✅ **COMPLETA** — 5/5 etapas + sub-fase 5.5 (`user-public-profiles`) mergeadas. Cerró 2026-05-19 con archive (PR #45).
- [ ] **Fase 4** — Workout++ (session tracking, sesión activa, post-entreno, historial, insights, wire de stats). 🔄 **4/6 etapas hechas** (Etapas 1, 2, 3, 4 ✅; Etapas 5 y 6 pending). IA buscador y videos quedan deferrables a Fase 4.5.
- [ ] **Fase 5** — Coach / Personal Trainer (discovery con geohash, chat, agenda, planes asignados, importación de planes Excel).
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

## Fase 3 — desglose en 5 etapas + sub-fase 5.5 ✅ COMPLETA

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

### Dependencias entre etapas

```
1 ✅ ──► 2 ✅ ──► 3 ✅ ─► 5 ✅ ──► 5.5 ✅
            └─► 4 ✅ ───┘
```

- **Etapa 1 antes de todo**: sin modelo Post + Friendship no hay nada que mostrar ni a quién seguir.
- **Etapa 2 antes de 3 y 4**: `PostCard` se define en 2 y se reusa en 3, 4.
- **Etapa 4 paralelo a 3**: perfil público no toca segments.
- **Etapa 5 al final**: necesita PostCard + Friendship.
- **Etapa 5.5 después de 5**: descubierto que search directo en `users` rompía por Firestore rules owner-only. Solución architectural: `UserPublicProfile` collection separada con privacy boundary explícito. Incluyó refactor de Etapa 4 para usar el mismo provider (eliminando el workaround "first post").

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

## Fase 4 — desglose en 6 etapas (4/6 hechas 🔄)

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
| 5 | Insights screen ⏳ | `feat/insights` (pendiente) | Nada | Pantalla Insights (`insights.png`) con volumen semanal, racha de días, PRs por grupo muscular, frecuencia. Lee de la colección `sessions` y agrega client-side (server aggregation queda para Fase 6 cuando aparezca App Check / Cloud Functions). | C |
| 6 | Wire data atrasada (Home + Profile + check-in) ⏳ | `feat/wire-real-stats` (pendiente) | Nada | Home "Esta semana" con streak real, muscle map basado en último 7d, dots de días entrenados, stats SEMANA/MES. Profile public + own: stats `workouts` y `racha` reales (seguidores/siguiendo siguen siendo de `friendships`, que ya existe). Check-in básico (`check-in.png`) — daily prompt para registrar estado. | B |

### Dependencias entre etapas

```
1 ✅ ──► 2 ✅ ──► 3 ✅
  ├──► 4 ✅ ──► 5 ⏳
  └─────────────► 6 ⏳
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
| **B** | Etapa 2 (player) ✅ + Etapa 3 (resumen + compartir) ✅ + Etapa 6 (wire stats) ⏳ |
| **C** | Etapa 4 (historial) ✅ + Etapa 5 (insights) ⏳ |

**Tiempo real (parcial)**: ~4 días desde el cierre de Fase 3 etapas paralelas. Etapas 5 y 6 pendientes — proyección ~1-2 semanas más con 2 devs en paralelo.

### Trabajo paralelo entre Fase 3 y 4

Etapas 1-4 de Fase 4 corrieron en paralelo con las últimas etapas de Fase 3 (incluida 5.5). Cero conflicts notables — `lib/features/workout/` (Fase 4) y `lib/features/feed/` + `lib/features/profile/` (Fase 3) son disjuntos.

### Cambio adicional fuera de etapa formal

- **PR #47 `feat/exercise-images-per-exercise`**: reemplazó la convention "una imagen por grupo muscular" con "una imagen por ejercicio" en `assets/exercises/{exerciseId}.png` + 25 PNGs nuevas comprimidas con pngquant. Cambio de UI mecánico (~5 líneas en `_HeroStrip`).

### Pre-flight checklist

- ✅ Etapa 1: opcional poblar `users/{uid}/sessions` para testing visual de historial e insights — script disponible.
- (Etapas 2-6 no requieren acción en console.)

## Fase 5 — extensión: Importación de planes desde Excel

Feature crítica para adopción de PFs reales (la mayoría trabaja con plantillas Excel históricas). Detalle de arquitectura completa pendiente de documentar como sub-fase 5.5 cuando lleguemos.

Resumen:

- Plantilla `.xlsx` estándar TREINO (parser determinístico) + modo IA (Gemini lee Excel arbitrarios).
- Web app para entrenadores ("Coach Hub") en Flutter Web (mismo stack), accesible desde browser.
- Cloud Function `parsePlan` que extrae JSON estructurado del Excel.
- Preview/edit screen antes de asignar el plan a alumnos.
- El plan asignado vive como `Routine` normal en Firestore + `source: "excel-import"` para trazabilidad.

Decisión técnica pendiente: Flutter Web vs Next.js para el Coach Hub. Resolver antes de empezar Fase 5.

## Cronograma — real vs estimado

Actualizado a 2026-05-19.

| Fase | Estado | Estimado original | Real / proyectado |
|---|---|---|---|
| Fase 1 (Auth + Firebase + ProfileSetup) | ✅ Cerrada 2026-05-13 | ~2026-05-08 | +5 días (drama Apple Sign-In) |
| Fase 2 (Home + Rutinas) | ✅ Cerrada ~2026-05-15 | ~2026-05-29 | **Adelantada ~2 semanas** |
| Fase 3 (Feed + sub-fase 5.5) | ✅ Cerrada 2026-05-19 | ~2026-06-12 | **Adelantada ~3.5 semanas** (incluyó sub-fase 5.5 imprevista por bug architectural) |
| Fase 4 (Workout++) | 🔄 4/6 etapas (1-4 ✅, 5-6 ⏳) | ~2026-07-03 | Proyectada cerrar ~2026-05-28 (**~5 semanas adelantada** si se mantiene el ritmo) |
| Fase 5 (Coach + Excel + Coach Hub web) | ⏳ | ~2026-08-07 | Proyectada ~2026-06-15 |
| Fase 6 (Polish + lanzamiento beta) | ⏳ | ~2026-08-21 | Proyectada ~2026-06-30 |

**Total**: ~17 semanas full-time originales → si seguimos el ritmo actual, ~7-8 semanas reales (~2 meses). El ritmo de Fase 3-4 con 3 devs en paralelo + SDD disciplinado superó las proyecciones.

Buffer recomendado: +25% para imprevistos. **No bajar la guardia con Fase 5** — el Coach Hub web es la fase más grande y arriesgada (decisión Flutter Web vs Next.js todavía pendiente).

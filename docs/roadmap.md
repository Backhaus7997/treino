# Roadmap — TREINO

Estado de las fases y desglose detallado de Fase 2 (en curso) y Fase 3 (próxima).

## Estado por fase

- [x] **Fase 0** — Bootstrap + tema + 5 tabs vacías + Phosphor (commits `cf09068` a `c6d5fea`).
- [x] **Fase 1** — Auth (email/Google/Apple) + Firebase + Firestore + ProfileSetup + Roles & guards. ✅ **COMPLETA** — 7/7 etapas mergeadas. Cerró 2026-05-13 con Apple Sign-In (PR #10).
- [ ] **Fase 2** — Home (paridad con mockup Mobile Home) + Rutinas básicas read-only. **4/5 etapas hechas** (Etapas 1, 2, 3, 4 ✅; Etapa 5 pending Dev B).
- [ ] **Fase 3** — Feed social (amigos · mi gym · público) + perfiles públicos.
- [ ] **Fase 4** — Workout++ (bloques, super series, IA buscador de ejercicios, videos, session tracking, post-entreno).
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

## Fase 2 — desglose en 5 etapas (4/5 hechas)

Home (paridad con mockup Mobile Home) + Rutinas básicas read-only (Plantillas pre-cargadas en Firestore que el atleta puede consultar y usar como fallback cuando no tiene una rutina asignada).

**Scope explícito de Fase 2**: solo lectura. Crear rutinas (PF) va en Fase 5. Tracking de sesiones, "Esta semana" con datos reales, Historial e Insights van en Fase 4 (Workout++). En Fase 2 esas zonas quedan con estado vacío/placeholder.

| # | Etapa | PR / branch | Console (manual) | Código clave | Owner |
|---|---|---|---|---|---|
| 1 | Home shell + cards (datos placeholder) ✅ | `8ee3bc2` (#8) | Nada | Home con cards "Empezar entrenamiento" + "Esta semana" según mockup. Datos placeholders — el wire real va en Etapa 5. | B |
| 2 | Modelo `Routine` + seed Plantillas + reglas Firestore ✅ | `23c8f29` (#9) + `d5259d8` (#11) | Colección `routines` poblada por script Admin SDK | Modelos `Routine`, `RoutineDay`, `RoutineSlot`, `Exercise` con freezed + json_serializable. `RoutineRepository` + `ExerciseRepository`. Reglas `routines/{id}` y `exercises/{id}` (read auth, write false). Script `scripts/seed_workout_catalog.js`. ~6 plantillas + ~25 ejercicios seedeados. | A |
| 3 | Lista de Plantillas (tab Entrenamiento) ✅ | `2501dfa` (#14) | Nada | Tab Entrenamiento → `PlantillasSection` con cards de plantilla + filtros por nivel (`LevelFilterPills`). `routinesFilterProvider`. Navegación a `/workout/routine/:id`. | B |
| 4 | Detalle Rutina + Detalle Ejercicio (read-only) ✅ | `feat/routine-detail` (PR abierto, listo para merge) | Nada | `RoutineDetailScreen` con day selector + slots con sets/reps/grupo muscular + CTAs disabled stubs ("EDITAR" → Fase 5, "EMPEZAR" → Fase 4). `ExerciseDetailScreen` con técnica numerada + historial empty state. Back button persistente. 41 tests SCENARIO-075..112. | C |
| 5 | Wire Home → Plantillas + estados vacíos | `feat/home-wire-routines` | Nada | Card "Empezar entrenamiento" navega a Plantillas. Card "Esta semana" muestra estado vacío correcto. Cleanup de placeholders de Etapa 1. | B (próximo: 2026-05-14) |

### Dependencias entre etapas

```
1 ✅ ─────────────► 5 ⏳
                    ▲
2 ✅ ──► 3 ✅ ──────┤
   └─► 4 ✅ ───────┘
```

### División final entre los 3 devs

| Dev | Etapas que hizo |
|---|---|
| **A** | Etapa 2 (modelo + seed + reglas) |
| **B** | Etapa 1 (Home shell) + Etapa 3 (Plantillas list) + Etapa 5 (wire — pendiente) |
| **C** | Etapa 4 (routine + exercise detail) |

**Tiempo real**: ~5 días desde el cierre de Fase 1 (2026-05-13). Estimado original era ~2.5-3 semanas — se aceleró por paralelización agresiva.

### Pre-flight checklist

- ✅ Etapa 2: colección `routines` + `exercises` pobladas via `scripts/seed_workout_catalog.js`.
- (Etapas 1, 3, 4, 5 no requieren acción en console.)

## Fase 3 — desglose en 5 etapas (próxima)

Feed social con 3 segmentos (Amigos · Mi Gym · Público) + perfiles públicos de otros usuarios + creación manual de posts. Misma filosofía: PR por etapa, paralelizable.

**Scope explícito de Fase 3**:
- Posts manuales (texto + tag de rutina opcional). Posts post-entreno con stats reales **NO** entran acá — vienen con Fase 4 (Workout++). El `PostCard` ya queda preparado para renderizar stats cuando lleguen.
- Friendship/following (request + accept + list) — sin notificaciones push (eso es Fase 6).
- Perfil público de OTROS usuarios (perfil propio ya existe — Etapa 6 de Fase 1).
- "MENSAJE" en perfil público queda como stub disabled → Chat es Fase 5 (Coach).
- "Compartir" desde post-entreno queda para Fase 4.
- Likes / comments / reactions: **no aparecen en mockup actual** → fuera de scope (eventualmente Fase 3.5).

| # | Etapa | Branch | Console (manual) | Código clave | Owner sugerido |
|---|---|---|---|---|---|
| 1 | Modelo `Post` + `Friendship` + reglas Firestore + seed | `feat/post-friendship-model` | Colecciones `posts` + `friendships` (Admin SDK seed) | Modelos `Post` (autor, texto, tag rutina opcional, privacy: friends/gym/public, createdAt) y `Friendship` (uidA, uidB, status: pending/accepted, requesterId) con freezed. Repos + reglas: post `read` según privacy + requester, `write` solo owner; friendship `read` si sos parte, `write` controlado por requester. Script `scripts/seed_posts.js` con 6-10 posts manuales de prueba. | A |
| 2 | Feed shell + segment AMIGOS + `PostCard` | `feat/feed-shell-amigos` | Nada | Tab Feed (`/feed`) según `feed.png`: header + 3 segments (AMIGOS / MI GYM / PÚBLICO). Implementar solo AMIGOS (los otros 2 disabled). `PostCard` reusable (avatar + nombre + verified + timestamp + gym + tag + stats stub para Fase 4). Empty state cuando no hay posts. | B |
| 3 | Segments MI GYM + PÚBLICO | `feat/feed-segments` | Nada | Query por `gymId` del UserProfile para MI GYM. Query "todos posts con privacy=public" para PÚBLICO. Paginación si entra en scope (cursor-based). | B |
| 4 | Perfil público de otro usuario | `feat/public-profile` | Nada | Ruta `/profile/:uid` (≠ `/profile` que es el propio). UI según `feed-publico.png`: hero + avatar + handle + stats (workouts, racha, seguidores, siguiendo — todos placeholder hasta Fase 4) + tabs RUTINAS PÚBLICAS / ACTIVIDAD + botón SEGUIR (toggleable, escribe en `friendships`). Botón MENSAJE disabled stub → Fase 5. | C |
| 5 | Crear post manual + search usuarios | `feat/feed-create-search` | Nada | Plus button (`/feed/create`) → form simple para crear post (texto + privacy selector + tag rutina opcional). Search icon (`/feed/search`) → buscar usuarios por handle/nombre. Sin attachment de workout — eso lo agrega Fase 4. | C |

### Dependencias entre etapas

```
1 ──► 2 ──► 3 ─► 5
       └─► 4 ─┘
```

- **Etapa 1 antes de todo**: sin modelo Post + Friendship no hay nada que mostrar ni a quién seguir.
- **Etapa 2 antes de 3 y 4**: `PostCard` se define en 2 y se reusa en 3, 4.
- **Etapa 4 paralelo a 3**: perfil público no toca segments.
- **Etapa 5 al final**: necesita PostCard + Friendship (para search results).

### División entre los 3 devs (con paralelización)

| Dev | Etapas |
|---|---|
| **A** | Etapa 1 (modelo + reglas + seed) — **arranca 2026-05-14 en paralelo a Etapa 5 de Fase 2** |
| **B** | Etapa 2 (Feed shell + AMIGOS) cuando termine Etapa 5 de Fase 2 + Etapa 3 (segments) |
| **C** | Etapa 4 (perfil público) en paralelo a Etapa 3 + Etapa 5 (create + search) al final |

**Tiempo estimado**: ~2 semanas con 3 devs en paralelo.

### Paralelización con Fase 2 pendiente

Mientras Dev B termina Etapa 5 de Fase 2 (wire Home → Plantillas) el día 2026-05-14, **Dev A puede arrancar Etapa 1 de Fase 3 (data layer) sin conflicto** — son features distintas (`lib/features/feed/` vs `lib/features/home/`).

### Pre-flight checklist

- ⏳ Etapa 1: poblar colecciones `posts` (~6-10 posts manuales con autores distintos para probar feed) y `friendships` (~3-5 conexiones aceptadas + 1-2 pending para probar el flow). Script Admin SDK.
- (Etapas 2, 3, 4, 5 no requieren acción en console.)

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

Actualizado a 2026-05-13.

| Fase | Estado | Estimado original | Real / proyectado |
|---|---|---|---|
| Fase 1 (Auth + Firebase + ProfileSetup) | ✅ Cerrada 2026-05-13 | ~2026-05-08 | +5 días (drama Apple Sign-In) |
| Fase 2 (Home + Rutinas) | 🔄 4/5 etapas — cierra ~2026-05-15 | ~2026-05-29 | **Adelantada ~2 semanas** |
| Fase 3 (Feed) | ⏳ Arranca 2026-05-14 (data layer en paralelo a F2 Etapa 5) | ~2026-06-12 | ~2026-05-28 |
| Fase 4 (Workout++) | ⏳ | ~2026-07-03 | ~2026-06-18 |
| Fase 5 (Coach + Excel + Coach Hub web) | ⏳ | ~2026-08-07 | ~2026-07-23 |
| Fase 6 (Polish + lanzamiento beta) | ⏳ | ~2026-08-21 | ~2026-08-06 |

**Total**: ~17 semanas full-time originales → si seguimos el ritmo actual, ~13-14 semanas reales (~3 meses).

Buffer recomendado: +25% para imprevistos. **No bajar la guardia con Fase 5** — el Coach Hub web es la fase más grande y arriesgada.

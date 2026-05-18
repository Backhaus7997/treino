# Proposal — public-profile

**Change**: `public-profile`
**Fase / Etapa**: Fase 3 · Etapa 4
**Branch**: `feat/public-profile` (off `main`)
**Owner**: Dev B (visual owner del feature Feed)
**Artifact store**: `openspec` · **Execution mode**: `interactive` · **Delivery**: `ask-on-risk`
**TDD**: Strict (per `docs/workflow.md`) — tests primero en apply phase
**Depends on**: `openspec/changes/public-profile/explore.md` (8 decisions LOCKED por el usuario)
**Precedente hermano**: `openspec/changes/feed-shell-amigos/` — misma forma (UI feature consumiendo data layer existente)

---

## 1. Why

Hoy un usuario que ve un `PostCard` en `/feed` no puede tapear el avatar/nombre del autor para drillear a su perfil. `PostCard.onAuthorTap` existe como prop opcional desde Etapa 2 pero está sin wirear, y `/profile/:uid` directamente no existe. La consecuencia: el feed se siente social pero el grafo es de una sola dirección — ves a tus amigos postear, no podés visitar a alguien nuevo, no podés mandar SEGUIR. Etapa 4 cierra ese loop.

**Este PR entrega la screen pública de perfil `/feed/profile/:uid`**: tap en avatar o nombre de un `PostCard` → land en el perfil público del autor, con avatar + display name + gym + 4 stats placeholder + botón SEGUIR de 4 estados + tabs RUTINAS PÚBLICAS / ACTIVIDAD (placeholder). Después de este PR, el usuario tiene un loop social mínimo viable: ver feed → tapear autor → mandar/aceptar amistad.

**Coordinación con Dev C (paralelo)**: Dev C trabaja Etapa 3 (activar segmentos MI GYM + PÚBLICO en el feed) en paralelo, también off `main`. Cero overlap de archivos confirmado: Dev C toca `feed_screen.dart` + `feed_segment_pills.dart` + `feed_screen_providers.dart`; yo toco archivos nuevos en `feed/presentation/` + `friendship_repository.dart` + `post_card.dart` (1 prop wire) + `router.dart` + `public_profile_providers.dart` nuevo. Whoever merges first gana el rebase; el merge debe ser clean.

---

## 2. What — entregables visibles

Un reviewer que ejecute `flutter run`, navegue a `/feed`, y tapee un avatar/nombre en cualquier `PostCard` debe ver:

- **Navegación**: `context.push('/feed/profile/$uid')` desde `FeedScreen` → land en `PublicProfileScreen` con bottom bar visible (la ruta es nested bajo `/feed` ShellRoute, igual que `/workout/routine/:routineId`).
- **Hero**: avatar circular grande (mismo `PostAvatar` reusado con `size: 96`), display name UPPERCASE en `Barlow Condensed 700`, subtitle con gym name resuelto del `gymId` (o vacío si `null`/`no-gym`). Background hero usa gradient accent→bg (mismo pattern que `RoutineDetailScreen`).
- **Stats row**: 4 stats hardcoded en `0` — WORKOUTS · RACHA · SEGUIDORES · SIGUIENDO. RACHA renderiza en `palette.accent`, los otros 3 en `palette.text`. Labels en `palette.textMuted`.
- **Botón SEGUIR (4 estados, driven por `friendshipByPairProvider`)**:
  - `friendship == null` → "SEGUIR" mint filled, tap llama `request(viewerUid, targetUid)`.
  - `friendship.status == pending && friendship.requesterId == viewerUid` → "SOLICITUD ENVIADA" outlined disabled.
  - `friendship.status == pending && friendship.requesterId == targetUid` → "ACEPTAR" mint filled, tap llama `accept(friendship.id)`.
  - `friendship.status == accepted` → "SIGUIENDO" outlined con check icon (no-op tap por ahora; unfollow es Fase 5).
- **Botón MENSAJE**: outlined disabled, no-op (stub hasta Coach chat en Fase 5).
- **Self-visit guard**: si `viewerUid == targetUid`, la row SEGUIR/MENSAJE se oculta. La screen sigue visible (puede ser útil para preview), pero sin acciones de relación.
- **Tabs (pill-based)**: "RUTINAS PÚBLICAS" (activa default) + "ACTIVIDAD" (inactiva). Reusan el patrón visual de `FeedSegmentPills` pero con widget propio (`_ProfileTabPills`) — semánticamente distintos, sin acoplar.
- **Tab content**: empty state "Próximamente" en ambas tabs por esta etapa. RUTINAS PÚBLICAS no consulta nada (no hay rutinas user-created hasta Fase 5). ACTIVIDAD muestra placeholder.
- **No-posts fallback**: si el target no tiene posts en el sistema (`firstPostByAuthorProvider` retorna `null`), display name cae a "Anónimo" y avatar a iniciales — exactamente el mismo fallback que `PostAvatar` ya implementa.
- **Back button**: `context.pop()` vuelve a `/feed` con estado conservado.

### Archivos nuevos

| Path | Rol |
|---|---|
| `lib/features/feed/presentation/public_profile_screen.dart` | Screen raíz; `ConsumerWidget` leyendo `targetUid` de route param |
| `lib/features/feed/presentation/widgets/public_profile_hero.dart` | Hero strip: avatar grande + display name + gym subtitle |
| `lib/features/feed/presentation/widgets/public_profile_stats_row.dart` | Row de 4 stats placeholder |
| `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` | Botón SEGUIR 4-state driven by friendship |
| `lib/features/feed/application/public_profile_providers.dart` | `publicProfileViewProvider.family` + `firstPostByAuthorProvider.family` + `friendshipByPairProvider.family` |
| `lib/features/feed/domain/public_profile_view.dart` | DTO view-model: `authorDisplayName`, `authorAvatarUrl?`, `authorGymId?`, `friendship: Friendship?` |
| `test/features/feed/presentation/public_profile_screen_test.dart` | Integration test: 4 estados SEGUIR + self-visit + no-posts fallback |
| `test/features/feed/presentation/widgets/public_profile_hero_test.dart` | Widget test |
| `test/features/feed/presentation/widgets/public_profile_stats_row_test.dart` | Widget test |
| `test/features/feed/presentation/widgets/public_profile_follow_button_test.dart` | Widget test de los 4 estados |
| `test/features/feed/application/public_profile_providers_test.dart` | Provider test del view-model compositor |
| `test/features/feed/data/friendship_repository_get_by_pair_test.dart` | Test del nuevo método de repo |

### Archivos modificados

| Path | Cambio |
|---|---|
| `lib/features/feed/data/friendship_repository.dart` | Agregar método `getByPair(String uidA, String uidB) → Future<Friendship?>` usando `buildFriendshipId(a, b)` |
| `lib/features/feed/presentation/widgets/post_card.dart` | Wire `onAuthorTap` callback en el header del card (avatar + display name tappables) — 1 prop, sin restructuring |
| `lib/features/feed/feed_screen.dart` | Pasar `onAuthorTap: () => context.push('/feed/profile/${post.authorUid}')` a cada `PostCard` |
| `lib/app/router.dart` | Agregar `GoRoute(path: 'profile/:uid', builder: ...)` anidada bajo el ShellRoute `/feed` |

### Archivos NO tocados (scope boundary)

- `lib/features/profile/` — own profile screen (stub) sigue intacta; este es un screen distinto
- `lib/features/workout/`, `lib/features/home/`, `lib/features/auth/`, `lib/features/coach/` — visual ownership de otros devs
- `lib/features/feed/feed_screen.dart`, `lib/features/feed/presentation/widgets/feed_segment_pills.dart`, `lib/features/feed/application/feed_screen_providers.dart` — **territorio Dev C (Etapa 3 paralela)**. La única excepción es `feed_screen.dart`, donde necesito pasar el `onAuthorTap` callback a `PostCard`; ese cambio se coordina con C (ver Risk #1).
- `lib/features/feed/application/friendship_providers.dart` — providers existentes intactos; los nuevos viven en `public_profile_providers.dart` para no contaminar el archivo compartido
- `lib/features/feed/domain/post.dart`, `friendship.dart` — modelos ya tienen todo lo que necesitamos
- `firestore.rules` — el doc `friendships/{id}` ya es member-only readable; `getByPair` lee con un viewer que es miembro o no existe → null sin permission error
- `pubspec.yaml` — sin nuevas deps Flutter/Dart

---

## 3. How — arquitectura

### Data flow

```
route /feed/profile/:uid
  └── PublicProfileScreen(targetUid)
        └── ref.watch(publicProfileViewProvider(targetUid))
              ├── firstPostByAuthorProvider(targetUid)         ← extrae authorDisplayName/AvatarUrl/GymId
              └── friendshipByPairProvider((viewerUid, targetUid))  ← estado del botón SEGUIR
```

`publicProfileViewProvider` es el **único punto de entrada de la UI**. Compone los dos providers internamente y expone un `PublicProfileView` DTO. La screen hace `ref.watch(publicProfileViewProvider(targetUid))` y listo — no toca providers individuales.

```dart
// lib/features/feed/application/public_profile_providers.dart

final firstPostByAuthorProvider =
    FutureProvider.family<Post?, String>((ref, targetUid) async {
  final repo = ref.watch(postRepositoryProvider);
  final posts = await repo.byAuthor(targetUid, limit: 1);
  return posts.isEmpty ? null : posts.first;
});

final friendshipByPairProvider =
    FutureProvider.family<Friendship?, ({String viewerUid, String targetUid})>(
        (ref, args) async {
  final repo = ref.watch(friendshipRepositoryProvider);
  return repo.getByPair(args.viewerUid, args.targetUid);
});

final publicProfileViewProvider =
    FutureProvider.family<PublicProfileView, String>((ref, targetUid) async {
  final viewer = ref.watch(authStateChangesProvider).valueOrNull;
  final post = await ref.watch(firstPostByAuthorProvider(targetUid).future);
  final friendship = viewer == null || viewer.uid == targetUid
      ? null
      : await ref.watch(friendshipByPairProvider(
          (viewerUid: viewer.uid, targetUid: targetUid),
        ).future);
  return PublicProfileView(
    authorDisplayName: post?.authorDisplayName ?? 'Anónimo',
    authorAvatarUrl: post?.authorAvatarUrl,
    authorGymId: post?.authorGymId,
    friendship: friendship,
    isSelfVisit: viewer?.uid == targetUid,
  );
});
```

### Repo extension (mínima)

```dart
// lib/features/feed/data/friendship_repository.dart

Future<Friendship?> getByPair(String uidA, String uidB) async {
  final id = buildFriendshipId(uidA, uidB); // already exists
  final snap = await _firestore.collection('friendships').doc(id).get();
  if (!snap.exists) return null;
  return Friendship.fromJson({...snap.data()!, 'id': snap.id});
}
```

Una sola lectura Firestore por visita al perfil. El doc existe o no — null sin permission error porque el viewer es miembro de cualquier doc que exista entre `(viewerUid, targetUid)`.

### Composition tree

```
PublicProfileScreen (ConsumerWidget)
└── Scaffold (con back button del ShellRoute padre)
    └── CustomScrollView
        ├── SliverToBoxAdapter
        │   └── PublicProfileHero(view)              ← avatar + display name + gym
        ├── SliverToBoxAdapter
        │   └── if (!view.isSelfVisit)
        │       Row(
        │         PublicProfileFollowButton(view.friendship, targetUid),
        │         MessageButtonStub(),
        │       )
        ├── SliverToBoxAdapter
        │   └── PublicProfileStatsRow()              ← 4 zeros
        ├── SliverToBoxAdapter
        │   └── _ProfileTabPills(currentTab, onTap)  ← pill pattern local
        └── SliverToBoxAdapter
            └── switch (currentTab) {
                  ProfileTab.routines => EmptyState('Próximamente'),
                  ProfileTab.activity => EmptyState('Próximamente'),
                }
```

### 4-state machine del botón SEGUIR

| Input | Label | Style | onTap |
|---|---|---|---|
| `friendship == null` | "SEGUIR" | mint filled | `repo.request(viewerUid, targetUid)` |
| `pending && requesterId == viewerUid` | "SOLICITUD ENVIADA" | outlined, disabled | `null` |
| `pending && requesterId == targetUid` | "ACEPTAR" | mint filled | `repo.accept(friendship.id)` |
| `accepted` | "SIGUIENDO" | outlined + check icon | `null` (no-op; unfollow Fase 5) |

Después de `request` o `accept`, el provider `friendshipByPairProvider((viewerUid, targetUid))` se invalida (`ref.invalidate(...)`) para que la UI refleje el nuevo estado sin refresh manual.

### Router

```dart
// lib/app/router.dart — dentro del ShellRoute existente

GoRoute(
  path: '/feed',
  builder: (context, state) => const FeedScreen(),
  routes: [
    GoRoute(
      path: 'profile/:uid',
      builder: (context, state) => PublicProfileScreen(
        targetUid: state.pathParameters['uid']!,
      ),
    ),
  ],
),
```

`_kTabs` index detection ya usa `startsWith` — `/feed/profile/xxx` resuelve a index 1 (Feed tab) automáticamente. Bottom bar funciona sin cambios. `authRedirect` ya cubre la ruta (cualquier `/feed/*` es auth-gated).

### Theme y tipografía

- Todos los colores vía `AppPalette.of(context)`. Cero HEX literals.
- Todos los iconos vía `TreinoIcon.X` (check icon = `TreinoIcon.check`; debe existir o se agrega como re-export, decisión en design).
- `GoogleFonts.barlowCondensed` para display name (UPPERCASE, weight 700), pills, labels de stats. `GoogleFonts.barlow` para el resto.
- Spacing canónico `{8, 12, 14, 18, 20}`. Radii: card `r-lg=20`, pill `r-lg=20`, avatar `r-full`.

### Cross-feature dependencies (allowed)

- `authStateChangesProvider` (auth feature) — leído dentro de `publicProfileViewProvider`. Read OK.
- `postRepositoryProvider` + `friendshipRepositoryProvider` (mismo feature). Read OK.
- No tocamos profile feature, no tocamos workout feature, no tocamos home feature.

---

## Capabilities

### New Capabilities
- `public-profile`: Screen `/feed/profile/:uid` para drillear al perfil público de otro usuario desde el feed. Incluye hero con denormalized author data, stats placeholder, botón SEGUIR de 4 estados, tabs placeholder, self-visit guard, no-posts fallback.

### Modified Capabilities
- None — `feed` capability no muta a nivel de requirements; solo wireamos un callback existente (`onAuthorTap`). `friendship` capability tampoco muta — se extiende el repo con un método nuevo (`getByPair`) sin cambiar contratos previos.

---

## 4. Trade-offs aceptados (8 decisions LOCKED por el usuario)

| # | Decisión | Por qué |
|---|---|---|
| 1 | **Data approach A — denorm desde `Post`** (sin `users_public` sidecar, sin doc split, sin Cloud Function) | El mockup necesita solo `displayName + avatarUrl + gymId`, todos presentes en `Post.author*`. Cero infra nueva. Trade-off stale-on-update ya aceptado en ADR previo (`feed-shell-amigos`). Approach B (CF + collection nueva) es una etapa propia. |
| 2 | **Feature folder `lib/features/feed/presentation/`** | Semántico: el perfil público se llega desde Feed, todos los providers sociales viven acá. Mover a `features/profile/` invertiría la dirección de imports actual y mezclaría con el stub de own-profile. |
| 3 | **Router nested `/feed/profile/:uid`** (no top-level) | Consistente con `/workout/routine/:routineId`. Evita naming collision con `/profile`. Bottom bar visible sin cambios. Back navigation natural. |
| 4 | **Tabs pill-based** (reusa patrón `_Pill` de `FeedSegmentPills`, NO `TabBar` nativo) | Consistente con feed UI. Sin acoplar widgets: este screen tiene su propio `_ProfileTabPills` aunque visualmente espeja FeedSegmentPills. |
| 5 | **SEGUIR 4 estados** (not following / request sent / request received / following) | Cubre todas las combinaciones `Friendship.status × requesterId`. Sin estado, sin caso huérfano. |
| 6 | **Stats placeholder = `0` hardcoded** para los 4 valores | Más claro que `--`. Trivial reemplazar en Fase 4 con providers reales sin cambios de layout. |
| 7 | **Omitir `@handle`** esta etapa | El campo `handle` no existe en `UserProfile`, `Post`, ni ningún modelo. El mockup lo muestra como aspirational. Agregarlo implicaría migration + denorm en `Post` + ProfileSetup update — fuera de scope. Defer a Fase 4 o Etapa 5 (search). |
| 8 | **Self-visit guard**: si `viewerUid == targetUid`, ocultar fila SEGUIR/MENSAJE | Simple y correcto. La screen sigue navegable como preview; las acciones de relación no aplican consigo mismo. |

---

## 5. Out-of-scope (explícito)

Lo que **NO** entra en este PR y dónde sí entra:

- **`@handle` field** → defer (no existe en ningún modelo; requiere migration + denorm). Fase 4 o Etapa 5 (search).
- **Stats reales** (workouts count, racha, seguidores, siguiendo derivados de `friendships`) → Fase 4. Esta etapa muestra `0`.
- **Tab RUTINAS PÚBLICAS con contenido real** → Fase 5. Las rutinas user-created no existen todavía; query `routines where authorUid == targetUid AND visibility == public` no tiene matches. Muestra empty state "Próximamente".
- **Tab ACTIVIDAD con contenido real** → Fase 4. Sin source de actividad agregada por usuario aún. Empty state.
- **Botón MENSAJE funcional** → Fase 5 (Coach chat). Stub outlined disabled.
- **Unfollow desde SIGUIENDO** → fuera de scope; SIGUIENDO es no-op tap. Fase 5 puede agregar action sheet con "Dejar de seguir".
- **Following count derivado de `friendships`** → placeholder hardcoded. Fase 4 lo deriva.
- **`users_public/{uid}` sidecar collection** → Approach B, no necesaria gracias a decisión 1. Defer.
- **Cloud Function para sincronizar perfil** → no infra change en Fase 3.
- **Bio del usuario en el hero** → no existe `bio` en `UserProfile`. Hero deja espacio visual reservado pero sin contenido.
- **Hero background photo** → no hay source en el modelo. Gradient accent→bg.
- **Verified badge en el perfil público** → no denormalizado en `Post`. Defer hasta que `Post.authorVerified` exista (Fase 4+).
- **Compartir perfil / deep link** → Fase 5.
- **Bloquear / reportar usuario** → no en roadmap actual.
- **Cambios en `firestore.rules`** → no hace falta; member-only read del doc `friendships/{id}` ya cubre `getByPair`.
- **Ranking, Retos, Missions, Bets, Gamification** → fuera del producto (`CLAUDE.md` Quick reference).

---

## 6. Success criteria

El PR está "done" cuando todas estas condiciones son verificables:

1. **Navegación**: tap en `PostAvatar` o display name de un `PostCard` en `/feed` → push a `/feed/profile/:uid` con bottom bar visible y back button funcional.
2. **Render con datos**: si el target tiene posts, la screen muestra `authorDisplayName` + avatar (foto o iniciales) + gym name resuelto del `gymId` denormalizado.
3. **No-posts fallback**: si el target no tiene posts, display name renderiza "Anónimo" e avatar cae a iniciales del fallback de `PostAvatar`.
4. **SEGUIR estado "not following"**: friendship null → botón "SEGUIR" mint filled tappable.
5. **SEGUIR estado "request sent"**: friendship pending con `requesterId == viewerUid` → botón "SOLICITUD ENVIADA" outlined disabled.
6. **SEGUIR estado "request received"**: friendship pending con `requesterId == targetUid` → botón "ACEPTAR" mint filled tappable.
7. **SEGUIR estado "following"**: friendship accepted → botón "SIGUIENDO" outlined con check.
8. **Tap SEGUIR**: invoca `FriendshipRepository.request(viewerUid, targetUid)` y la UI refleja "SOLICITUD ENVIADA" tras invalidate.
9. **Tap ACEPTAR**: invoca `FriendshipRepository.accept(friendship.id)` y la UI refleja "SIGUIENDO".
10. **Self-visit**: si `viewerUid == targetUid`, la fila SEGUIR/MENSAJE no se renderiza. El resto del screen sí.
11. **Stats placeholder**: las 4 stats muestran `0` con sus labels (`WORKOUTS`, `RACHA`, `SEGUIDORES`, `SIGUIENDO`). RACHA en color `palette.accent`.
12. **Tabs**: ambas tabs activables visualmente; ambas muestran empty state "Próximamente" en su body.
13. **Tests verdes**: los 6 archivos de test nuevos pasan. Tests se escriben **antes** del código (Strict TDD).
14. **`flutter analyze`**: 0 issues nuevos.
15. **`dart format .`**: árbol limpio.
16. **Sin HEX literals**, sin `PhosphorIcons.X` directos, sin `Theme.of(context).textTheme.X` con tamaños custom.
17. **Las tests pre-existentes siguen verdes** + los nuevos tests del public profile pasan.
18. **Coordinación con Dev C**: si C mergea Etapa 3 antes, rebase y verificar que `feed_screen.dart` sigue pasando `onAuthorTap` al `PostCard` sin colisión.

---

## 7. Risks (priorizados, con mitigación para apply)

| # | Riesgo | Severidad | Mitigación en apply |
|---|---|---|---|
| 1 | **`post_card.dart` colisión con Dev C** si C refactoriza el header para segmentos. | P1 (Alta) | Mantener mi diff en `post_card.dart` mínimo: agregar 1 callback prop `onAuthorTap` + envolver el header existente en `GestureDetector` o `InkWell`. Cero restructuring interno. Coordinar con C antes de mergear: el que llegue segundo rebasa. Si C cambia la signature del header, mi PR ajusta su único punto de contacto sin tocar otra cosa. |
| 2 | **`firstPostByAuthorProvider` retorna null para usuarios activos que aún no postearon** → display name cae a "Anónimo". | P1 (Alta) | Aceptado y documentado per Approach A (decisión 1). Fallback "Anónimo" + iniciales es la UX explícita. Fase 4 cuando exista `users_public` collection puede backfillear. Comment one-liner en `publicProfileViewProvider` referenciando este trade-off. |
| 3 | **Friendship state computation = 1 Firestore read por visita al perfil**. | P2 (Media) | Aceptable a la escala actual del producto (low-traffic, no viral). El doc id es determinístico → un solo `get()`, sin query. Cache de Riverpod (`autoDispose` o keep-alive en family) evita re-fetches en re-renders de la misma sesión. Documentar para optimización futura (in-memory cache layer) sin bloquear. |
| 4 | **Self-visit con `viewerUid` desconocido** (unauthenticated) → state raro. | P2 (Media) | La ruta `/feed/profile/:uid` está bajo el ShellRoute auth-gated por `authRedirect` en `router.dart`. Un usuario sin sesión es bounceado antes de llegar acá. El `publicProfileViewProvider` además trata `viewer == null` como no-self-visit y sin friendship lookup (el botón SEGUIR igualmente no se renderiza si no hay viewer). Test cubre el caso. |
| 5 | **Pill tabs de este screen vs `FeedSegmentPills`**: visualmente similares, semánticamente distintos. | P3 (Baja) | Widget separado `_ProfileTabPills` privado al screen. No reusamos `FeedSegmentPills` para evitar acoplar el enum y el provider entre dos features-en-una. Comment one-liner en el widget explicando la decisión consciente. |
| 6 | **`PostCard.onAuthorTap` no estaba wireado**: existe como prop opcional pero `FeedScreen` nunca lo pasa. | P2 (Media) | Agregar el callback en `FeedScreen` es ~3 LOC. Si C ya lo wireó en su rama (Etapa 3 no debería tocarlo, pero por las dudas), rebase y reemplazar el handler. Cero riesgo de regresión: el callback existente es opcional con default `null`. |
| 7 | **`getByPair` puede no respetar las reglas si el `id` no se construye igual que en `request()` / `accept()`**. | P2 (Media) | Usar exactamente `buildFriendshipId(uidA, uidB)` que ya existe en `friendship.dart` y es la fuente de verdad para todos los métodos del repo. Test del nuevo método valida que id se construye igual y que viewer-no-miembro recibe permission error (esperado, no es bug). |
| 8 | **Gym name resolution**: el hardcoded list tiene 3 gyms; un user con gymId desconocido muestra raw id o nada. | P3 (Baja) | Aceptado per decisión 7 de explore. `gymNameFromId(String? gymId)` utility devuelve nombre si está en la list, vacío si `null`/`no-gym`, raw id en otro caso. Edge cases documentados; no bloquea la etapa. |
| 9 | **Riesgo de feature creep**: el mockup muestra `@handle`, photo background del hero, badge verified, bio. | P3 (Baja) | LOCKED por decisiones 1, 7 y out-of-scope explícito. Cualquiera de los 4 (handle, hero photo, verified, bio) requiere infra adicional fuera de scope. Defer documentado. |

---

## 8. Review Workload Forecast

| Métrica | Valor |
|---|---|
| Estimated production LOC | ~280-330 (screen + 3 widgets + 1 domain DTO + 1 providers file + 1 repo method + 1 wire + 1 route) |
| Estimated test LOC | ~250-320 (screen integration test + 3 widget tests + 1 provider test + 1 repo test) |
| Estimated total diff | ~600 LOC |
| 400-line production budget | **Within budget** (~280-330 prod LOC < 400) |
| Chained PRs recommended | **No** |
| `size:exception` needed | **No** |
| Decision needed before apply | **No** — proceed directly to `sdd-spec` + `sdd-design` (paralelo) |
| Delivery strategy | Single PR, work-unit commits: (1) repo extension + provider; (2) domain DTO + view provider; (3) widgets + screen + tests; (4) router wire + `post_card` callback + `feed_screen` push |
| 400-line budget risk | Low |

---

## 9. Rollback Plan

Si algo sale mal en producción post-merge:

1. **Revert del PR** vía `git revert <merge-sha>` — restaura `/feed` al estado previo (sin drill-down a perfiles). Los datos `friendships/{id}` creados por usuarios que mandaron SEGUIR antes del revert quedan en Firestore; no son destructivos (siguen siendo válidos para Etapa 5+).
2. **No hay migration de datos** — Approach A no modifica esquema. Cero rollback de datos.
3. **No hay cambios en `firestore.rules`** — cero rollback de reglas.
4. **`pubspec.yaml` intacto** — cero deps para remover.
5. **Tests pre-existentes** se mantienen porque no modificamos contratos existentes (solo agregamos un método nuevo al repo y un prop wire al `PostCard`).

Riesgo de rollback: **muy bajo**. Es una superficie de UI nueva con un método de repo aditivo.

---

## 10. Dependencies

- **Dev C en paralelo (Etapa 3)** — no es blocker; trabajamos branches separados con cero overlap excepto `post_card.dart` (1 prop wire). Coordinación explícita documentada.
- **Etapa 1 (`feed-data`)** — `Post.author*` denormalizados ya existen. ✅
- **Etapa 2 (`feed-shell-amigos`)** — `PostCard.onAuthorTap` ya está expuesto como prop opcional. ✅
- **`FriendshipRepository` + `buildFriendshipId`** — ya existen. Solo agregamos `getByPair`. ✅
- **No nuevas deps Flutter/Dart** en `pubspec.yaml`. ✅

---

**Next recommended**: `sdd-spec` y `sdd-design` (pueden correr en paralelo).

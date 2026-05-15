# Proposal — feed-shell-amigos

**Change**: `feed-shell-amigos`
**Fase / Etapa**: Fase 3 · Etapa 2
**Branch**: `feat/feed-shell-amigos`
**Owner**: Dev B (visual owner del feature Feed)
**Artifact store**: `openspec` · **Execution mode**: `interactive` · **Delivery**: `ask-on-risk`
**TDD**: Strict (per `docs/workflow.md`) — tests primero en apply phase
**Depends on**: explore.md (9 decisions LOCKED por el usuario)

---

## 1. Why

Hoy `/feed` es un placeholder con el texto "FEED · Amigos · Comunidad · Público" (`lib/features/feed/feed_screen.dart`). Etapa 1 (PR #22) dejó el data layer completo y verde — `Post`, `Friendship`, repositorios, providers `feedForFriendsProvider` / `acceptedFriendsProvider` — pero ninguna superficie visible al usuario. La pestaña "Feed" del bottom bar abre una pantalla vacía.

**Este PR entrega la pestaña Feed visible según el mockup `docs/app-alumno/screens/feed/feed.png`**: header con título y acciones, segment pills (AMIGOS / MI GYM / PÚBLICO), y el contenido funcional del segmento AMIGOS. Después de este PR, un usuario logueado con amigos puede entrar a `/feed`, ver el feed de sus amigos posteado-por-posteado, tapear el chip de rutina de un post y caer en el detalle de esa rutina. MI GYM y PÚBLICO quedan visibles como pills deshabilitadas (etapa 3 las activa).

**Amendment explícito al data layer de Etapa 1**: el modelo `Post` actual NO tiene `displayName` ni `avatarUrl` del autor — y la regla de Firestore `users/{uid}` es **owner-only read** (otros usuarios NO pueden leer perfiles ajenos). Sin resolución, `PostCard` no puede mostrar nombre ni avatar del autor, no matchea el mockup, y la etapa queda bloqueada. La decisión **locked A** (denormalizar `authorDisplayName` + `authorAvatarUrl?` en `Post`) sigue el mismo ADR que ya aplica para `authorGymId` en Etapa 1. **No es scope creep** — es la mínima corrección de data para destrabar la UI, encontrada en explore. ~30 LOC delta.

---

## 2. What — entregables visibles

Un reviewer que ejecute `flutter run` y navegue a `/feed` debe ver:

- **Header**: título "FEED" en `Barlow Condensed` 700 UPPERCASE + iconos `TreinoIcon.search` y `TreinoIcon.plus` a la derecha (taps son no-op stubs en esta etapa — los wireamos en Etapa 5).
- **Segment pills**: 3 pills "AMIGOS" (activa por default) · "MI GYM" (deshabilitada, opacity 0.4) · "PÚBLICO" (deshabilitada, opacity 0.4). Solo AMIGOS es tappable.
- **AMIGOS feed**:
  - Si hay posts → `ListView` de `PostCard` (uno por post).
  - Si está cargando → `CircularProgressIndicator(color: palette.accent)` centrado.
  - Si la lista vino vacía o el usuario no tiene amigos → `FeedEmptyState` (texto + icono en `palette.textMuted`).
  - Si hay error → mensaje de error en `palette.textMuted` (mismo pattern que `PlantillasSection`).
- **PostCard** renderiza: avatar circular 40×40 (foto si `authorAvatarUrl != null`, fallback de iniciales con gradient accent→highlight), `authorDisplayName`, badge verified opcional (`TreinoIcon.verified` en `accent`), gym name + timestamp relativo ("Hace 2h"), botón overflow `TreinoIcon.dotsThree` (stub, no-op), texto del post, chip de rutina opcional (si `post.routineTag != null`), y stats row stub ("— kg · — min · — ej.") como placeholder para Fase 4.
- **Tap en chip de rutina** → navega a `/workout/routine/:routineId` (ruta ya existe desde Fase 2 Etapa 4).

### Archivos nuevos

| Path | Rol |
|---|---|
| `lib/features/feed/presentation/widgets/post_card.dart` | Card visual del post |
| `lib/features/feed/presentation/widgets/feed_segment_pills.dart` | 3 pills AMIGOS/MI GYM/PÚBLICO con state local |
| `lib/features/feed/presentation/widgets/feed_empty_state.dart` | Empty state cuando no hay posts |
| `lib/features/feed/presentation/widgets/post_avatar.dart` | Avatar circular 40×40 con fallback de iniciales (reusable) |
| `lib/features/feed/application/feed_screen_providers.dart` | `myFriendsFeedProvider` + `feedSegmentProvider` |
| `lib/features/feed/domain/feed_segment.dart` | Enum `FeedSegment.amigos / gym / public` |
| `test/features/feed/presentation/feed_screen_test.dart` | Integration test del shell + segmento AMIGOS |
| `test/features/feed/presentation/widgets/post_card_test.dart` | Widget tests de PostCard |
| `test/features/feed/presentation/widgets/feed_segment_pills_test.dart` | Widget tests de pills |
| `test/features/feed/presentation/widgets/feed_empty_state_test.dart` | Widget test del empty state |

### Archivos modificados

| Path | Cambio |
|---|---|
| `lib/features/feed/feed_screen.dart` | Reemplazo completo del placeholder por el shell real (header + pills + body por segmento) |
| `lib/features/feed/domain/post.dart` | Agregar `authorDisplayName: String` (required) y `authorAvatarUrl: String?` (nullable). Comentario one-liner explicando trade-off de stale-on-update. |
| `lib/features/feed/domain/post.freezed.dart` + `post.g.dart` | Regenerados por `build_runner` |
| `lib/core/widgets/treino_icon.dart` | Agregar constantes `TreinoIcon.dotsThree` (`PhosphorIcons.dotsThreeVertical`) y `TreinoIcon.verified` (`PhosphorIconsFill.sealCheck`) |
| `scripts/seed_posts.js` | Extender 6-10 seed posts con `authorDisplayName` + `authorAvatarUrl` opcional |
| `test/features/feed/domain/post_test.dart` | Actualizar fixtures + agregar test cases para los 2 nuevos fields |

### Archivos NO tocados (scope boundary)

- `lib/features/workout/`, `lib/features/home/`, `lib/features/auth/`, `lib/features/profile/`, `lib/features/coach/` — visual ownership de otros devs
- `lib/features/feed/data/` (repos completos en Etapa 1)
- `lib/features/feed/application/post_providers.dart` y `friendship_providers.dart` — providers existentes intactos; los nuevos derivan
- `firestore.rules` — la denormalización vive en el documento `posts/{id}` que ya tiene reglas adecuadas; no se introduce ninguna colección nueva
- `pubspec.yaml` — sin nuevas deps Flutter/Dart
- `lib/app/router.dart` — `/workout/routine/:routineId` ya existe; los iconos del header del Feed son no-op en esta etapa, así que no hace falta agregar `/feed/search` ni `/feed/create` todavía (Etapa 5)

---

## 3. How — arquitectura

### Composition tree

```
FeedScreen (ConsumerWidget)
├── FeedHeader (Row inline en la screen, no widget separado: título + search icon + plus icon)
├── SizedBox(height: 14)
├── FeedSegmentPills (state via feedSegmentProvider)
├── SizedBox(height: 14)
└── Expanded(
      switch (ref.watch(feedSegmentProvider)) {
        FeedSegment.amigos => ref.watch(myFriendsFeedProvider).when(
              data: (posts) => posts.isEmpty
                  ? const FeedEmptyState()
                  : ListView.separated(itemBuilder: PostCard(posts[i])),
              loading: () => CircularProgressIndicator(color: palette.accent),
              error: (e, _) => Text('No pudimos cargar tu feed', style: muted),
            ),
        FeedSegment.gym || FeedSegment.public => const SizedBox.shrink(),
      },
    )
```

### State flow

`myFriendsFeedProvider` es el **único punto de entrada de la UI** y resuelve internamente la cadena auth → friends → posts:

```dart
final myFriendsFeedProvider = FutureProvider<List<Post>>((ref) async {
  final user = ref.watch(authStateChangesProvider).valueOrNull;
  if (user == null) return const [];
  final friendUids = await ref.watch(acceptedFriendsProvider(user.uid).future);
  if (friendUids.isEmpty) return const [];
  return ref.watch(feedForFriendsProvider(friendUids).future);
});
```

Esto resuelve el problema de equality de `List<String>` en `feedForFriendsProvider.family`: el `List` se construye y se pasa **dentro** del provider, no a través del widget tree, así que no genera rebuilds infinitos. La UI hace `ref.watch(myFriendsFeedProvider)` y listo.

`feedSegmentProvider` es un `StateProvider<FeedSegment>` con default `FeedSegment.amigos`. Solo `FeedSegmentPills` lo escribe; `FeedScreen` lo lee para decidir qué body renderiza.

### PostCard composition

```
Container(bgCard, r-lg=20, border 1px palette.border, padding all 18)
└── Column(crossAxis: start)
    ├── Row(header)
    │   ├── PostAvatar(authorAvatarUrl, authorDisplayName, size: 40)
    │   ├── Expanded(
    │   │     Column(crossAxis: start)
    │   │     ├── Row(authorDisplayName + optional verified badge)
    │   │     └── Row(gym • timestamp, both palette.textMuted)
    │   │   )
    │   └── IconButton(TreinoIcon.dotsThree, onPressed: null)  // stub
    ├── SizedBox(height: 12)
    ├── Text(post.text, body)
    ├── if (post.routineTag != null) SizedBox(height: 12) + RoutineTagChip(onTap → context.push('/workout/routine/${routineTag.routineId}'))
    ├── SizedBox(height: 12)
    └── Row(stats stub: '— kg · — min · — ej.' en textMuted)  // Fase 4 reemplaza con data real
```

`PostAvatar` es un widget reusable: si `authorAvatarUrl != null` usa `CachedNetworkImage` con clip circular; si es null, fallback de iniciales con gradient `accent → highlight` (mismo pattern que `HomeHeader._AvatarFallback`).

### Theme y tipografía

- Todos los colores vía `AppPalette.of(context)`. Cero HEX literals en código nuevo.
- Todos los iconos vía `TreinoIcon.X`. Cero `PhosphorIcons.X` directos.
- `GoogleFonts.barlowCondensed` para títulos/labels (header "FEED", pills, nombre de autor en `labelMedium 600`), `GoogleFonts.barlow` para body del post.
- Spacing del set canónico `{8, 12, 14, 18, 20}`. Radii: card `r-lg=20`, pill `r-lg=20`, avatar `r-full`.

### Cross-feature dependencies (allowed)

- `authStateChangesProvider` (auth feature) — leído dentro de `myFriendsFeedProvider` en `feed/application/`. Read OK.
- `userProfileProvider` (profile feature) — **NO se usa** en esta etapa porque la denormalización elimina la dependencia.
- `/workout/routine/:routineId` (workout feature) — solo navegación, no import. Read OK.

Cross-feature **writes** quedan prohibidos. Esta etapa no escribe en ningún feature ajeno.

### Post model amendment (mínimo)

```dart
@freezed
class Post with _$Post {
  // Author display fields denormalized at write time (same ADR as authorGymId).
  // Trade-off: if the author changes their displayName/avatarUrl later, existing posts
  // keep the stale snapshot. Standard pattern for social media feeds.
  const factory Post({
    required String id,
    required String authorUid,
    required String authorDisplayName,       // NEW (required)
    String? authorAvatarUrl,                 // NEW (nullable)
    String? authorGymId,
    required String text,
    RoutineTag? routineTag,
    required PostPrivacy privacy,
    required DateTime createdAt,
  }) = _Post;
  // ... fromJson
}
```

`scripts/seed_posts.js` se extiende para incluir los 2 fields. Los seed posts existentes en Firestore se reescriben con la próxima corrida del script (idempotente).

---

## 4. Trade-offs aceptados (9 decisions LOCKED por el usuario)

| # | Decisión | Por qué |
|---|---|---|
| A | **Denormalizar `authorDisplayName` + `authorAvatarUrl?` en `Post`** (no `users_public` collection, no Cloud Function) | Sigue el ADR existente de `authorGymId`. Cero infra nueva. Trade-off stale-on-update aceptado y documentado — standard social media pattern. Alternativas (collection nueva o CF) son una etapa propia. |
| B | **`myFriendsFeedProvider` derivado (FutureProvider, no family)** | Compone auth → friends → posts internamente. Resuelve el problema de equality de `List<String>` en `.family` sin tocar `feedForFriendsProvider`. UI consume un solo punto de entrada. |
| C | **`FeedSegmentPills` widget nuevo + `StateProvider<FeedSegment>` local** | Espeja `LevelFilterPills` visual pero con su propio enum/provider — sin coupling cross-feature. Cumple visual ownership (Feed dueño de sus pills). |
| D | **MI GYM + PÚBLICO con opacity 0.4, no tappables** | Comunica "existe pero no todavía" sin agregar empty states ni rutas placeholder. Activan en Etapa 3 con cambios mínimos (solo habilitar tap + branch del switch). |
| E | **Tap en autor (avatar/nombre) = no-op** | `/profile/:uid` no existe hasta Etapa 4. Stubear ruta ahora doblaría trabajo. `PostCard` expone `onAuthorTap` como param opcional para wirearlo después sin cambios estructurales. |
| F | **Tap en `RoutineTag` chip → `context.push('/workout/routine/:id')`** | La ruta ya existe. Usamos `push` (no `go`) porque desde la perspectiva del usuario es un drill-down de detalle, no un cambio de tab — incluso cruzando features. Documentado para revisarlo en smoke test. |
| G | **Empty state: texto + icono en `palette.textMuted`** | Mismo pattern visual que `PlantillasSection` empty. Sin ilustración custom (no hay assets, y sería YAGNI). |
| H | **Loading: `CircularProgressIndicator(color: palette.accent)`** | Consistente con `PlantillasSection`. Skeleton cards son polish, no scope. |
| I | **`TreinoIcon.dotsThree` (`dotsThreeVertical`) + `TreinoIcon.verified` (`sealCheck` fill)** | Naming semántico de marca; el enum es solo re-export con nombre del producto sobre Phosphor. Mantiene la regla "nunca `PhosphorIcons.X` directo". |

**Amendment explícito** además de los 9: este PR modifica `Post` (2 fields) y `seed_posts.js`. **No es feature creep** — explore lo identificó como el bloqueante #1 para que `PostCard` pueda matchear el mockup. ~30 LOC delta y se queda contenido a la denormalización (cero nuevas reglas, cero migration jobs).

---

## 5. Out-of-scope (explícito)

Lo que **NO** entra en este PR y dónde sí entra:

- **MI GYM segment functional** → Etapa 3
- **PÚBLICO segment functional** → Etapa 3
- **Pull-to-refresh** → Etapa 3+ (no aparece en mockup)
- **`/profile/:uid` (public profile screen)** → Etapa 4. PostCard expone `onAuthorTap` listo para wirear.
- **`/feed/search` y `/feed/create` (crear post + buscar usuarios)** → Etapa 5. Los iconos del header son no-op stubs por ahora.
- **Post likes / comments / reactions** → Fase 3.5 (no en mockup actual)
- **Stats reales en PostCard** (`6,420 kg · 58 min · 7 ej.`) → Fase 4. Renderizamos `— · — · —` como placeholder.
- **Muscle group label** (`PECHO · HOMBROS` en el mockup) → Fase 4. `Post` no tiene esa data; se queda fuera.
- **Skeleton loading shimmer** → polish (no requerido)
- **Post detail screen** → no en roadmap ni mockup
- **`users_public` collection** → no necesaria gracias a decisión A
- **Cambios en `firestore.rules`** → no hace falta
- **Ranking, Retos, Missions, Bets, Gamification** → fuera del producto (`CLAUDE.md` Quick reference)

---

## 6. Success criteria

El PR está "done" cuando todas estas condiciones son verificables:

1. **Visual parity** con `docs/app-alumno/screens/feed/feed.png` en layout, tipografía, colores, radii y spacing (modulo los stubs declarados: stats row, badge verified, overflow menu).
2. **Logged-in user navega a `/feed`** y ve la pantalla con AMIGOS activo por default, MI GYM y PÚBLICO visibles pero deshabilitadas (opacity 0.4).
3. **AMIGOS con amigos posteados**: lista de `PostCard` renderizada vía `myFriendsFeedProvider`, cada uno con avatar, nombre, gym, timestamp relativo, texto, chip opcional, stats stub.
4. **AMIGOS sin amigos o sin posts**: `FeedEmptyState` visible en lugar del listado.
5. **Tap en MI GYM o PÚBLICO**: no pasa nada (visualmente clarísimo que están deshabilitadas).
6. **Tap en chip de rutina de un post**: navega a `/workout/routine/:routineId` y la rutina se renderiza correctamente (ya verificado en Fase 2 Etapa 4).
7. **Los 3 estados de `myFriendsFeedProvider` se renderizan** sin crashes (`data` / `loading` / `error`).
8. **Tests verdes**: `feed_screen_test.dart`, `post_card_test.dart`, `feed_segment_pills_test.dart`, `feed_empty_state_test.dart`, `post_test.dart` actualizado — todos pasan. Tests se escriben **antes** del código (Strict TDD).
9. **`flutter analyze`**: 0 issues nuevos.
10. **`dart format .`**: árbol limpio.
11. **Sin HEX literals**, sin `PhosphorIcons.X` directos, sin `Theme.of(context).textTheme.X` con tamaños custom.
12. **Las 418 tests pre-existentes siguen verdes** + los nuevos tests del feed pasan.
13. **`seed_posts.js` actualizado**: una corrida fresh deja los seed posts con `authorDisplayName` y, donde corresponda, `authorAvatarUrl`. PostCards renderizan nombres reales (no "Unknown").

---

## 7. Risks (priorizados, con mitigación para apply)

| # | Riesgo | Severidad | Mitigación en apply |
|---|---|---|---|
| 1 | **Modificar `Post` model rompe tests existentes** (`post_test.dart`, repo tests, provider tests que construyen `Post` fixtures) | P1 (Alta) | Tarea explícita en `tasks.md`: actualizar `test/features/feed/domain/post_test.dart` y todos los fixtures de `Post` **en el mismo work-unit commit** que la regeneración de freezed. `dart run build_runner build --delete-conflicting-outputs` corre antes de la tanda de tests. Si algún test usa `Post(...)` sin los nuevos fields, el compiler lo detecta en analyze. |
| 2 | **`myFriendsFeedProvider` composición incorrecta** (cadena auth → friends → posts) | P1 (Alta) | Integration test en `feed_screen_test.dart` que override de `authStateChangesProvider`, `acceptedFriendsProvider`, `feedForFriendsProvider`, y assert que el chain resuelve al List de Posts esperado. Casos: usuario null, usuario sin amigos (lista vacía), usuario con amigos y posts. Test escrito antes del provider. |
| 3 | **Stale author data en `Post` si user updatea displayName/avatar** | P2 (Media) | Documentado y aceptado per decision A. Comment one-liner en `Post` model explica el trade-off. Fase futura puede agregar job de re-sync si el producto lo pide. |
| 4 | **Idioma de navegación de `RoutineTag` chip (push vs go)** | P2 (Media) | Decision F: `context.push` (drill-down de detalle, no cambio de tab). Documentado en propose + design. Si en smoke test se siente raro (tab Workout se activa o no), revisitamos antes de mergear. |
| 5 | **Seed posts en Firestore tienen null en los nuevos fields** hasta correr el script | P2 (Media) | `Post.authorDisplayName` es **required** en el modelo, pero `Post.fromJson` puede recibir un doc Firestore sin ese campo. Hay que decidir si el `fromJson` falla, defaultea a "Unknown", o si el repo filtra. Tarea explícita en spec/design para resolver esto. Recomendación: `fromJson` defaultea a `'Anónimo'` para resiliencia. |
| 6 | **Nuevas constantes `TreinoIcon` conflictúan con Phosphor naming** | P3 (Baja) | El enum es re-export. `dotsThree → PhosphorIconsRegular.dotsThreeVertical`; `verified → PhosphorIconsFill.sealCheck`. Mismo pattern que las constantes existentes. |
| 7 | **`PostCard` drifta del mockup** | P3 (Baja) | Smoke test visual contra `feed.png` es **mandatory** antes de mergear. Checklist en success criteria. |
| 8 | **`FeedScreen` introduce `Scaffold` propio o `AppBackground`** (shell ya los aplica) | P3 (Baja) | Mismo guardrail que home-shell: el test envuelve `FeedScreen` con `MaterialApp + Scaffold` mínimo (no shell real), y verifica que no haya `Scaffold` propio en el árbol. |

---

## 8. Review Workload Forecast

| Métrica | Valor |
|---|---|
| Estimated production LOC | ~250-300 (FeedScreen + 4 widgets + 1 provider file + 1 enum + Post amendment + icon constants + seed update) |
| Estimated test LOC | ~250-350 (PostCard + segment pills + empty state + FeedScreen integration + post_test updates) |
| Estimated total diff | ~600 LOC |
| 400-line production budget | **Within budget** (~250-300 prod LOC < 400) |
| Chained PRs recommended | **No** |
| `size:exception` needed | **No** |
| Decision needed before apply | **No** — proceed directly to `sdd-spec` + `sdd-design` (paralelo) |
| Delivery strategy | Single PR, work-unit commits (data amendment + freezed regen como commit 1; widgets + screen + tests siguientes commits) |

---

**Next recommended**: `sdd-spec` y `sdd-design` (pueden correr en paralelo).

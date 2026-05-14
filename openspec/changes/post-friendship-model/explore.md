# Explore — post-friendship-model

**Change**: `post-friendship-model`
**Fase / Etapa**: Fase 3 · Etapa 1
**Branch (target)**: `feat/post-friendship-model`
**Owner**: Dev A
**Project**: treino
**Artifact store**: hybrid
**Engram key**: `sdd/post-friendship-model/explore`

## Estado actual del codebase

Patrones consistentes Fase 1/2 que Fase 3 debe seguir:

- **Modelos**: `@freezed` + `json_serializable`, cada clase en su archivo con `*.freezed.dart` + `*.g.dart`. Ref: `lib/features/profile/domain/user_profile.dart:14`, `lib/features/workout/domain/routine.dart:10`.
- **Enums**: plain Dart enum + `@JsonValue('snake_case')` lowercase + extension con `_wireMap` + `fromJson`/`toJson`. Ref: `lib/features/profile/domain/user_role.dart:3-28`.
- **Repos**: inyección de `FirebaseFirestore`, collection getter privado, clase concreta (sin interface), `Future<T?>` para single, `Future<List<T>>` para colección. Ref: `lib/features/profile/data/user_repository.dart:7`, `lib/features/workout/data/routine_repository.dart:6`.
- **Providers**: Riverpod 2 manual, `Provider<Repo>` + `FutureProvider` auth-gated. Ref: `lib/features/workout/application/routine_providers.dart`.
- **Firestore rules**: deny-by-default, sin wildcards. Collecciones actuales: `/users/{uid}`, `/exercises/{exerciseId}`, `/routines/{routineId}`. Ref: `firestore.rules:1-50`.
- **Seed scripts**: Node.js + `firebase-admin`, arrays inline, `GOOGLE_APPLICATION_CREDENTIALS`. Ref: `scripts/seed_workout_catalog.js:681-747`.
- **Tests**: `fake_cloud_firestore`, `FakeFirebaseFirestore` inyectado. Numeración SCENARIO actual max: **SCENARIO-111** — nuevos arrancan en **SCENARIO-112**.
- **Feed stub**: `lib/features/feed/feed_screen.dart` es UI puro, sin providers. Zero coupling risk.
- **Sin colisión**: cero refs a `posts`/`friendships` en `lib/`.

## Decisiones resueltas

1. **Naming**: `Post.authorUid` (consistencia con `UserProfile.uid` + sufijo de rol).
2. **`routineTag`**: sub-modelo `RoutineTag` freezed con `routineId: String` + `routineName: String` (denormalizado para evitar round-trip, alineado con `RoutineSlot.exerciseName` ADR-2 en `lib/features/workout/domain/routine_slot.dart:9`).
3. **`Friendship` doc ID**: composite sorted `${uidA}_${uidB}` con `uidA < uidB` lexicográficamente.
4. **`privacy` enum wire**: lowercase `'friends'`, `'gym'`, `'public'`.
5. **Query pattern Friendship**: campo `members: [uidA, uidB]` + `array-contains` para un solo round-trip vs dos queries OR.
6. **Repo architecture**: `PostRepository` + `FriendshipRepository` separados (SRP, matches existing pattern).

## Áreas afectadas

**Nuevos archivos — domain** (`lib/features/feed/domain/`):
- `post.dart` + generated
- `post_privacy.dart` (enum)
- `routine_tag.dart` + generated
- `friendship.dart` + generated
- `friendship_status.dart` (enum)

**Nuevos archivos — data** (`lib/features/feed/data/`):
- `post_repository.dart`
- `friendship_repository.dart`

**Nuevos archivos — application** (`lib/features/feed/application/`):
- `post_providers.dart`
- `friendship_providers.dart`

**Nuevos archivos — scripts**:
- `scripts/seed_posts.js`

**Nuevos archivos — tests** (SCENARIO-112+):
- `test/features/feed/domain/{post,post_privacy,routine_tag,friendship,friendship_status}_test.dart`
- `test/features/feed/data/{post_repository,friendship_repository}_test.dart`

**Modificados**:
- `firestore.rules` — agregar bloques `posts/{postId}` + `friendships/{friendshipId}`

**Sin tocar**:
- `pubspec.yaml` (deps ya presentes)
- `lib/features/feed/feed_screen.dart` (stub)
- `scripts/package.json` (`firebase-admin` ya está)

## Aproximaciones

| Aproximación | Pros | Cons | Complejidad |
|---|---|---|---|
| **A: `PostRepository` + `FriendshipRepository` separados** | SRP, testeable independiente, matches existing pattern | 2 archivos, 2 provider declarations | Baja |
| **B: `SocialRepository` unificado** | Single file, single injection | God class a medida que Fase 3 crece, harder to test, viola SRP | Baja inicial, alta mantenimiento |

**Recomendación**: A.

## Diseño de Firestore rules

**`posts/{postId}`**:
```
allow read: if request.auth != null && (
  resource.data.privacy == 'public' ||
  (resource.data.privacy == 'gym' &&
   get(/databases/$(database)/documents/users/$(request.auth.uid)).data.gymId != null &&
   get(/databases/$(database)/documents/users/$(request.auth.uid)).data.gymId ==
   get(/databases/$(database)/documents/users/$(resource.data.authorUid)).data.gymId) ||
  resource.data.privacy == 'friends'   // soft enforcement — ver RISK #1
);
allow create: if request.auth != null && request.auth.uid == request.resource.data.authorUid;
allow update, delete: if request.auth != null && request.auth.uid == resource.data.authorUid;
```

**`friendships/{friendshipId}`**:
```
allow read: if request.auth != null && request.auth.uid in resource.data.members;
allow create: if request.auth != null
              && request.auth.uid == request.resource.data.requesterId
              && request.resource.data.status == 'pending'
              && request.auth.uid in request.resource.data.members;
allow update: if request.auth != null
              && request.auth.uid in resource.data.members
              && request.auth.uid != resource.data.requesterId
              && resource.data.status == 'pending'
              && request.resource.data.status == 'accepted';
allow delete: if request.auth != null && request.auth.uid in resource.data.members;
```

## Riesgos

1. **`friends` privacy rule limitation**: Firestore rules **no soportan concatenación dinámica de strings** para construir doc paths en `exists()`. Construir el sorted friendship ID en una rule no es viable. **Opciones**:
   - **(a) Enforcement soft client-side**: rules permiten lectura a cualquier auth user; el filtro `privacy: 'friends'` se hace en el query. Riesgo: usuario con devtools puede leer posts marcados friends de gente que no es su amigo.
   - **(b) Doc pair simétrico**: cada friendship escribe DOS docs (`uidA_uidB` + `uidB_uidA`). Doble storage, pero rules pueden hacer `exists(/friendships/$(request.auth.uid + '_' + resource.data.authorUid))`.

   **Recomendación MVP**: (a) — pragmático, alineado con cómo apps en prod manejan esta limitación. **Decisión a confirmar en `sdd-propose`**.

2. **`gym` privacy — costo de doble `get()`**: cada read de post `privacy=gym` dispara 2 doc reads adicionales. Aceptable para MVP; nota para Fase 6 (optimization).

3. **Race condition accept/delete**: concurrent accept+delete en la misma friendship. Baja probabilidad, outcome aceptable (friendship desaparece). Transaction opcional para MVP.

4. **`members` field redundancy**: tanto `uidA`/`uidB` (display) como `members: [uidA, uidB]` (`array-contains` query). Duplicación menor justificada por el query benefit.

5. **SCENARIO continuity**: nuevos tests arrancan en SCENARIO-112. Apply debe respetar.

6. **`build_runner` post-domain**: 5 freezed classes nuevas = 5 pairs generated. Una corrida de `dart run build_runner build --delete-conflicting-outputs` después de crear todos los domain files.

## Listo para Proposal

Sí — con una decisión a confirmar en `sdd-propose`: **nivel de enforcement de `friends` privacy** (recomendado: soft / client-side filtering, opción (a)).

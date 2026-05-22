# Archive Report — coach-chat

**Change**: `coach-chat`
**Fase / Etapa**: Fase 5 · Etapa 5 — Chat 1-1 real-time entre PF y athlete
**Status**: ARCHIVED
**Date**: 2026-05-22
**Artifact Store**: openspec
**PR**: #74 (feat(chat): real-time 1:1 chat entre PF y athlete — Fase 5 Etapa 5)
**Merge commit**: `705d0df` — Merged to main (2026-05-22)
**Owner**: Dev B

---

## Executive Summary

`coach-chat` shipped como PR único de ~1.6k LOC (44 tests nuevos, suite 1089). Cierra la Etapa 5 de Fase 5 entregando el chat 1-1 real-time entre PF y athlete vinculados:

- **Athlete side**: card de vínculo activo (`_LinkStateCard`) gana botón "MENSAJE" filled accent. Tap resuelve `chatForLinkProvider` → push a `/coach/chat/:chatId?other=:otherUid`.
- **Trainer side**: `AthleteDetailScreen` (entregado por Dev A en Etapa 4) gana botón "MENSAJE" outlined accent en el footer. Llama directo a `chatRepositoryProvider.getOrCreate`.
- **Pantalla chat**: burbujas alineadas propias vs ajenas (accent vs surface), `ListView.reverse` con stream real-time, composer + send con loading inline.
- **Real-time**: snapshots de Firestore. Ambos lados ven mensajes nuevos sin reload, mientras la app esté abierta. Sin push notifications (Fase 6).

Internamente: `ChatRepository` con `chatId` determinístico (`sortedUids.join('_')`), `getOrCreate` idempotente, `sendMessage` batched (mensaje + denormalized preview del parent en un solo write), `watchMessages` desc + limit 50, `watchChatsForUser` (members arrayContains + lastMessageAt desc). Rules nuevas para `chats/{chatId}` con enforcement de members ordenados + `chatId == members.join('_')`; sub-collection `messages` con mensajes inmutables. Composite index `(members arrayContains, lastMessageAt desc)` para la lista de chats.

ChatListScreen (pantalla "lista de conversaciones") fue construida en Fase A pero **deliberadamente no wireada** en Fase B — el botón directo en cada card cubre 100% del flow MVP. Wire futuro si un trainer junta >5 alumnos activos y necesita un bird's-eye view.

Sidecar fix sobre `scripts/promote_user_to_trainer.js`: descubierto durante smoke que trainers promovidos via Admin SDK quedaban sin doc en `userPublicProfiles` (el script solo dual-writeaba a `trainerPublicProfiles`). Resultado: aparecían como "Usuario" en el chat. Fix: agregamos el dual-write a `userPublicProfiles` con los 5 campos del schema canónico. Idempotente.

---

## Delivery: Single PR Strategy

### PR #74 — Coach Chat (Fase A + Fase B + sidecar fix)
- **Branch**: `feat/coach-chat` (deleted post-merge)
- **Status**: Squash-merged to main as `705d0df`
- **Merge date**: 2026-05-22

**Deliverables** (~1.6k LOC):

#### Domain (`lib/features/chat/domain/`)
- **`chat.dart`** + freezed/g — Freezed `Chat`:
  - `chatId: String` (determinístico, computed via `ChatRepository.chatIdFor`)
  - `members: List<String>` (2 uids, sorted asc)
  - `createdAt: DateTime` (server timestamp)
  - `lastMessageAt: DateTime?`, `lastMessageText: String?`, `lastMessageSenderId: String?` (denormalized del último send para ordenar la lista sin N queries)
- **`message.dart`** + freezed/g — Freezed `Message`:
  - `id: String` (Firestore auto-id)
  - `senderId: String`, `text: String`, `createdAt: DateTime`

#### Data (`lib/features/chat/data/chat_repository.dart`)
- **`static String chatIdFor(String uidA, String uidB)`** — pure helper, `[a, b]..sort().join('_')`. Rechaza `uidA == uidB` con ArgumentError.
- **`Future<Chat> getOrCreate({selfId, otherId})`** — idempotente. Lee `chats/{chatId}`; si existe → devuelve; si no → set con `{chatId, members: sortedUids, createdAt: FieldValue.serverTimestamp()}`.
- **`Future<void> sendMessage({chatId, senderId, text})`** — batch atómico:
  1. Doc nuevo en `chats/{chatId}/messages/{auto}` con `{id, senderId, text, createdAt}`.
  2. Update del parent con `{lastMessageAt, lastMessageText (truncated 80 chars con …), lastMessageSenderId}`.
- **`Stream<List<Message>> watchMessages(chatId, {limit = 50})`** — orderBy `createdAt desc` limit N.
- **`Stream<List<Chat>> watchChatsForUser(uid)`** — `members arrayContains uid, lastMessageAt desc`.

#### Application (`lib/features/chat/application/chat_providers.dart`)
- `chatRepositoryProvider` — instancia única.
- `chatsForCurrentUserProvider` — `StreamProvider.autoDispose<List<Chat>>`. Lista vacía si no hay current uid.
- `messagesProvider(chatId)` — `StreamProvider.autoDispose.family<List<Message>, String>`. Lista vacía si chatId == "".
- `chatForLinkProvider(TrainerLink)` — `FutureProvider.autoDispose.family<Chat, TrainerLink>`. Resuelve el chat para un link activo (deriva `otherUid` del par del link).

#### Presentation (`lib/features/chat/presentation/`)
- **`chat_list_screen.dart`** — `ChatListScreen` ConsumerWidget. Empty state + lista de conversaciones con avatar + nombre del otro + preview + tiempo relativo. **NO wireada en router** (decisión documentada en propose-fase-b.md).
- **`chat_screen.dart`** — `ChatScreen` ConsumerStatefulWidget. AppBar con avatar + nombre del otro (lee `userPublicProfileProvider`). Body: `ListView.reverse` con burbujas `_Bubble` (accent + bg si isMine, bgCard + border si entrante). Footer: `_Composer` con textfield + IconButton send con loading inline. SnackBar de error con `developer.log`.

#### Wire-up (Fase B)
- **`lib/features/coach/athlete_coach_view.dart`** — botón MENSAJE filled accent en `_LinkStateCard` arriba de TERMINAR VÍNCULO. Solo cuando `link.status == active`. Tap → resuelve `chatForLinkProvider(link)` → `context.push('/coach/chat/$chatId?other=$trainerId')`.
- **`lib/features/coach/presentation/athlete_detail_screen.dart`** — botón MENSAJE outlined accent en el footer arriba de CREAR PLAN. Tap → `chatRepositoryProvider.getOrCreate(trainerUid, athleteId)` → mismo push pattern.
- **`lib/app/router.dart`** — nueva sub-ruta dentro de `/coach`: `chat/:chatId` con `otherUid` derivado de query param `?other=`. Vive dentro del ShellRoute (mantiene bottom bar visible — consistente con `/coach/trainer/:uid` y `/coach/athlete/:athleteId`).

#### Shared
- **`lib/core/widgets/treino_icon.dart`** — `TreinoIcon.send` (`PhosphorIconsFill.paperPlaneTilt`) + `TreinoIcon.chatEmpty` (`PhosphorIconsRegular.chatsCircle`).

#### Rules + Indexes
- **`firestore.rules`** — block nuevo para `chats/{chatId}`:
  - read: caller en `resource.data.members` (o `resource == null` para tolerar reads en getOrCreate)
  - create: `members.size() == 2`, caller en members, members ordenados (`members[0] < members[1]`), `chatId == members[0] + '_' + members[1]`
  - update: caller en members, `members` y `createdAt` inmutables
  - delete: denied
- **`firestore.rules`** — sub-collection `messages/{messageId}`:
  - read: caller en parent members (via `get(/databases/.../chats/$chatId).data.members`)
  - create: `senderId == auth.uid`, caller en parent members, `text` string non-empty, `createdAt` timestamp
  - update/delete: denied
- **`firestore.indexes.json`** — composite `(members arrayContains, lastMessageAt desc)` para `watchChatsForUser`. Deployado a `treino-dev` via `scripts/deploy_rules.js` durante el smoke.

#### Sidecar fix
- **`scripts/promote_user_to_trainer.js`** — dual-write a `userPublicProfiles/{uid}` con los 5 campos (`uid, displayName, displayNameLowercase, avatarUrl, gymId`). Idempotente.

#### Tests (44 nuevos)
- `test/features/chat/domain/chat_test.dart` — 4 tests (round-trip, nullable last*, Firestore Timestamps, equality)
- `test/features/chat/domain/message_test.dart` — 3 tests
- `test/features/chat/data/chat_repository_test.dart` — 17 tests (`fake_cloud_firestore`):
  - chatIdFor determinístico + formato + rechaza same uid
  - getOrCreate crea + idempotente + mismo chat desde ambos lados
  - sendMessage escribe mensaje + actualiza preview + truncado 80 chars + rechaza vacío + trim
  - watchMessages vacío + orderBy desc + limit
  - watchChatsForUser filter + empty + orderBy lastMessageAt desc
- `test/features/chat/application/chat_providers_test.dart` — 9 tests (auth-gated, family, error path)
- `test/features/chat/presentation/chat_list_screen_test.dart` — 3 tests
- `test/features/chat/presentation/chat_screen_test.dart` — 5 tests (empty, bubbles propias vs ajenas, AppBar name, send con persistencia, send vacío rechazado)
- `test/features/coach/athlete_coach_view_test.dart` — +2 tests (Fase B): MENSAJE visible cuando active, NO visible cuando pending
- `test/features/coach/presentation/athlete_detail_screen_test.dart` — +1 test (Fase B): MENSAJE renderiza en el footer

**Suite total: 1089 passing, 9 skipped, 0 fail.**

---

## Locked Decisions (4)

| # | Decision | Rationale | Impact |
|---|---|---|---|
| 1 | **Chat ID determinístico `sortedUids.join('_')`** vs auto-id | Evita round-trip "buscar chat existente" antes de cada send. Ambos lados resuelven al mismo doc sin coordinación. UIDs de Firebase son alfanuméricos sin `_`, así que el delimiter es seguro. | Una sola fuente de verdad para el chat doc id. `chatIdFor` es helper estático puro. |
| 2 | **`lastMessageText` denormalizado en el parent** | Mostrar la lista de chats requiere preview del último mensaje. Sin denormalización, N queries (una por chat). Trade-off: doble escritura en cada send (batch resuelve atomicidad). | `sendMessage` usa `WriteBatch`. Truncamos preview a 80 chars + Unicode `…`. |
| 3 | **Mensajes inmutables en MVP** (no edit/delete) | Edit complica rules + UX (¿mostrar "editado"?). Si surge necesidad, se agrega en iteración futura. | Rules: `allow update, delete: if false` en sub-collection messages. |
| 4 | **Paginación in-memory `limit: 50`** | Conversaciones MVP son cortas. Si crece >50, el cap visual sigue siendo razonable. Paginación real (`startAfter`) se agrega cuando hagamos histórico. | `defaultMessagesLimit` constante en repo; query con `limit(N)`. |

---

## Discoveries / Gotchas

1. **`Stream.empty()` no emite valor** — al armar el `chatsForCurrentUserProvider` con `Stream.empty()` cuando no hay current uid, `.future` quedaba colgado indefinidamente. Fix: usar `Stream.value(const <Chat>[])` que emite una vez con lista vacía y resuelve. Detectado por tests de provider con auth = null.

2. **`fake_cloud_firestore` no enforce composite indexes** — repo tests pasaron locally sin tener el index `(members arrayContains, lastMessageAt desc)`. En producción la query falla con `failed-precondition` hasta que el index existe. Aprendimos esto durante Etapa 3 también (mismo patrón) — siempre pairing nuevas queries con explicit indexes-deploy step.

3. **Inconsistencia de datos entre `userPublicProfiles` y `trainerPublicProfiles`** — descubierto durante smoke test. El script `promote_user_to_trainer.js` (de Dev A en Fase 5 Etapa 4) solo dual-writeaba a `trainerPublicProfiles`, dejando `userPublicProfiles/{uid}` sin doc para trainers promovidos directo. El chat lee de `userPublicProfiles` (collection genérica para "cualquier user"), así que mostraba "Usuario" en lugar del nombre real. Fix sidecar: agregamos el dual-write al script. Idempotente — re-correrlo sobre cuentas existentes backfilea sin romper.

4. **Decisión arquitectónica documentada: athlete-by-default** — durante el smoke surgió pregunta de "qué role usar por default ante inconsistencia". Conclusión lockeada: SIEMPRE atleta. Razones: principio de menor privilegio, estado base post-signup, estadística (athletes outnumber trainers), failure mode UX (mostrar UI más pobre es inofensivo; mostrar UI elevada es problemático). `CoachScreen` ya implementa esto implícitamente: renderiza `_CoachLoadingView` (empty surface) hasta confirmar role, nunca trainer-by-default.

5. **Rebase clean con shared-with-trainer (PR #73)** — durante el push final descubrimos que main había avanzado con `feat/shared-with-trainer` que también modificaba `athlete_coach_view.dart` (agregando un toggle `_ShareToggle` en `_LinkStateCard`). Rebase auto-mergeó sin conflicts manuales — nuestro botón MENSAJE y su toggle coexisten en el mismo widget. Tests de ambos features pasan juntos.

---

## Test Coverage

- **44 tests nuevos** en `test/features/chat/` + tests en `test/features/coach/` extendidos para Fase B
- **Suite total**: 1089 passing, 9 skipped (escenarios emulator-required pre-existentes), 0 fail
- **Quality gates**:
  - `flutter analyze` — 0 issues
  - `dart format` — clean
  - All gates green pre-merge

---

## Smoke Test Manual (Pre-merge)

Verificado end-to-end el 2026-05-22:

1. ✅ Athlete tap "PEDIR VÍNCULO" en TrainerPublicProfile de mateo → SnackBar "Solicitud enviada"
2. ✅ Sign-in como mateo (trainer) → DASHBOARD → tap ACEPTAR
3. ✅ Sign-in como athlete → `_LinkStateCard` muestra "TU PERSONAL TRAINER" + botón MENSAJE filled accent
4. ✅ Tap MENSAJE → ChatScreen abre con AppBar mostrando avatar + nombre del PF
5. ✅ Send "hola entrenador" + "como estas" → burbujas propias derecha en color accent
6. ✅ Sign-in como mateo → tab Coach → ALUMNOS → tap card del athlete → AthleteDetailScreen → tap MENSAJE outlined → ChatScreen con mensajes recibidos como burbujas entrantes
7. ✅ Reply real-time desde mateo → athlete ve la burbuja aparecer sin reload manual
8. ✅ Pop del chat → vuelve a la tab Coach con la card intacta
9. ✅ Verificado: MENSAJE ausente en estado pending (botón solo cuando `link.status == active`)
10. ✅ Verificado tras fix del script: displayName "mateo" aparece correctamente en header (antes mostraba "Usuario")

---

## NOT Delivered (intentional)

| Item | Lands en |
|---|---|
| Push notifications cuando llega un mensaje | Fase 6 |
| Read receipts ("visto") | Iteración futura |
| Typing indicator ("escribiendo…") | Iteración futura |
| Adjuntar imágenes / audio | Iteración futura (Storage + UX) |
| Editar o borrar mensajes | Iteración futura |
| Búsqueda dentro del chat | Iteración futura |
| Wire-up de `ChatListScreen` con entry point | Iteración futura si crece el load de chats per user (decisión en propose-fase-b.md) |
| Indicador "tenés mensajes nuevos" en tab Coach | Fase 6 (notifications) |
| Cloud Function trigger que sincroniza `users → userPublicProfiles → trainerPublicProfiles` | Fase 6 (requires App Check + Cloud Functions). El sidecar fix al script tapa el caso inmediato; el fix arquitectónico definitivo va a Fase 6. |

---

## Handoff to Subsequent Etapas

| Etapa | Owner | What it uses from Etapa 5 |
|---|---|---|
| **Etapa 6 — Agenda (Dev C)** | Dev C | Independiente del chat. Mismo patrón: requiere vínculo activo, vive en tab Coach. Sin conflicto. |
| **Etapa 7 — Coach Hub (Dev A)** | Dev A | Coach Hub web puede surface chats del PF — consume `chatRepository` o equivalent. Modelos `Chat`/`Message` ya están listos para reutilizarse en web. |
| **Etapa 8 — Excel + Cloud Function (Dev A)** | Dev A | Independiente. |
| **Fase 6 — Polish** | TBD | Push notifications sobre nuevos mensajes; Cloud Function de sync para resolver definitivamente la inconsistencia entre las 3 collections de profiles. |

**No blockers** para Etapas 6–8 desde este PR.

---

## Cleanup Performed

- Local branch `feat/coach-chat` deleted (2026-05-22).
- Remote branch `feat/coach-chat` deleted via `git push origin --delete` (2026-05-22).
- Rules + indexes deployados a `treino-dev` durante el smoke (`scripts/deploy_rules.js`).
- mateo's `userPublicProfiles/{uid}` doc backfilled via re-run del script `promote_user_to_trainer.js` con el fix nuevo.

---

## References

- **Proposal Fase A**: [propose.md](./propose.md)
- **Proposal Fase B**: [propose-fase-b.md](./propose-fase-b.md)
- **PR**: https://github.com/Backhaus7997/treino/pull/74
- **Merge commit**: `705d0df`
- **Prior etapas**: Etapa 4 (Plans mobile, PR #64/#70/#71), Etapa 3 (Link lifecycle, PR #61), Etapa 1 (Foundations, PR #54)

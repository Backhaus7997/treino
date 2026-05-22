# Proposal: coach-chat

**Change**: Fase 5 · Etapa 5 — Chat 1-1 real-time entre PF y athlete
**Branch**: `feat/coach-chat`
**Owner**: Dev B
**Date**: 2026-05-21
**Depends on**: Etapa 1 (✅ #54) — TrainerLink + activeLink semantics. NO depende de Etapa 4 (Plans mobile) — son features hermanas que ambas consumen el vínculo activo. Etapa 4 la está construyendo Dev A en paralelo.

---

## 1. Why

Cuando un athlete y un PF tienen un `TrainerLink` con `status == active`, hoy no hay forma in-app de comunicarse. El acuerdo está hecho pero la conversación cotidiana (cambios de horario, dudas sobre el plan, fotos de ejercicios, etc.) tiene que salir de la app.

Esta etapa entrega chat 1-1 real-time entre los dos members de un vínculo activo. **Sin push notifications** (Fase 6) — la entrega es solo polling-by-snapshot mientras la app está abierta.

---

## 2. What

### Production deliverables

#### Domain (`lib/features/chat/domain/`)
- **`chat.dart`** — Freezed model:
  - `chatId: String` — determinístico, `sortedUids.join('_')` (lo computa el repo, no se mete a mano)
  - `members: List<String>` — exactamente 2 uids, sorted asc (para rules + ordering estable)
  - `createdAt: DateTime` — server timestamp
  - `lastMessageAt: DateTime?` — actualizado en cada send (para ordering de la lista)
  - `lastMessageText: String?` — preview de 1 línea (truncado a 80 chars en el send)
  - `lastMessageSenderId: String?` — para no marcar como "tuyo" el último mensaje propio en la lista
- **`message.dart`** — Freezed model:
  - `id: String` — Firestore auto-id
  - `senderId: String`
  - `text: String`
  - `createdAt: DateTime` — server timestamp

#### Data (`lib/features/chat/data/`)
- **`chat_repository.dart`**:
  - `String chatIdFor(String uidA, String uidB)` — pure helper, `[a, b]..sort().join('_')`
  - `Future<Chat> getOrCreate({required String selfId, required String otherId})` — lee `chats/{chatId}`; si no existe lo crea con `members: sortedUids, createdAt: now`. Idempotente.
  - `Future<void> sendMessage({required String chatId, required String senderId, required String text})` — batch: doc en `messages` + update del parent con `lastMessageAt, lastMessageText, lastMessageSenderId`.
  - `Stream<List<Message>> watchMessages(String chatId, {int limit = 50})` — orderBy `createdAt desc` limit N (paginación in-memory para MVP).
  - `Stream<List<Chat>> watchChatsForUser(String uid)` — `where('members', arrayContains: uid).orderBy('lastMessageAt', desc)`. Filtra in-Dart los que tengan `lastMessageAt == null` (chat vacío recién creado — se muestra abajo).

#### Application (`lib/features/chat/application/`)
- **`chat_providers.dart`**:
  - `chatRepositoryProvider` — instancia única.
  - `chatsForCurrentUserProvider` — `StreamProvider.autoDispose<List<Chat>>` que llama `watchChatsForUser(currentUid)`.
  - `messagesProvider(chatId)` — `StreamProvider.autoDispose.family<List<Message>, String>` con sort `createdAt desc`.
  - `chatForLinkProvider(TrainerLink)` — `FutureProvider.autoDispose.family<Chat, TrainerLink>` que llama `getOrCreate` con los dos miembros del link. Usado por el entry point (Fase B).

#### Presentation (`lib/features/chat/presentation/`)
- **`chat_list_screen.dart`** — lista todas las conversaciones del current user.
  - Cada row: avatar + nombre del OTRO miembro (vía `userPublicProfileProvider(otherId)`) + preview de `lastMessageText` + tiempo relativo (`hace 2h`, etc.).
  - Empty state: "Cuando tengas un vínculo activo con un PF, podés chatear acá."
  - Tap → push `ChatScreen(chatId)`.
- **`chat_screen.dart`** — burbujas + textfield.
  - `ListView.reverse: true` con `messagesProvider(chatId)` (asc visual → desc en el provider para tener el más nuevo abajo).
  - Burbuja: alineada a la derecha si `senderId == currentUid`, izquierda si no. Color: accent para propias, surface para entrantes.
  - Textfield bottom + botón send (icon `TreinoIcon.send` o equivalente — chequear catálogo).
  - On send: `repo.sendMessage(chatId, currentUid, text.trim())`; clear field; el stream actualiza solo.
  - AppBar con avatar + nombre del otro miembro.

#### Rules (`firestore.rules`)
- Block nuevo `match /chats/{chatId}`:
  - `read` (incluye list): caller en `resource.data.members`. Branch `resource == null` para tolerar reads de chats inexistentes en `getOrCreate`.
  - `create`: caller en `request.resource.data.members`; `members.size() == 2`; `members[0] < members[1]` (sorted enforcement); `chatId == members.join('_')`; no setea `lastMessageAt` ni preview en el create.
  - `update`: caller en `resource.data.members`; `members` inmutable; `createdAt` inmutable. Permite actualizar `lastMessage*` desde el batch del send (mismo caller que mandó el mensaje).
  - `delete`: denied.
- Sub-collection `match /chats/{chatId}/messages/{messageId}`:
  - `read`: caller en `get(/databases/.../chats/{chatId}).data.members`.
  - `create`: caller en parent members; `request.resource.data.senderId == auth.uid`; `text` is string non-empty; `createdAt` is timestamp.
  - `update`, `delete`: denied (mensajes inmutables — edit/delete a futuro).

#### Indexes (`firestore.indexes.json`)
- `chats`: composite `(members ARRAY_CONTAINS, lastMessageAt DESC)` — para `watchChatsForUser`. Se deploya post-merge.
- `messages` no necesita índice (single field `createdAt` en sub-collection).

### Test deliverables
- `test/features/chat/domain/chat_test.dart` + `message_test.dart` — JSON round-trip, equality.
- `test/features/chat/data/chat_repository_test.dart` — `fake_cloud_firestore`:
  - chatIdFor determinístico (orden no importa)
  - getOrCreate idempotente (segunda llamada no crea otro doc)
  - sendMessage escribe en messages + actualiza parent
  - watchMessages ordena desc
  - watchChatsForUser solo devuelve chats donde el uid está en members
- `test/features/chat/application/chat_providers_test.dart` — mocktail sobre repo.
- `test/features/chat/presentation/chat_list_screen_test.dart` — estado vacío + lista con datos.
- `test/features/chat/presentation/chat_screen_test.dart` — render de burbujas propias vs ajenas + send.
- **Estimado**: ~30 tests nuevos.

### Out of Fase A (esperan a Dev A — Fase B)
Estos archivos NO se tocan en este PR para evitar conflicto con Etapa 4:
- `lib/features/coach/athlete_coach_view.dart` — botón "MENSAJE" en el `_LinkStateCard` activo
- `lib/features/coach/trainer_coach_view.dart` — botón "MENSAJE" en `_ActiveAlumnoCard` (tab ALUMNOS)
- `lib/app/router/router.dart` (o donde viva la config de GoRouter) — rutas `/chat` y `/chat/:chatId`

Fase B se hace en un PR separado (`feat/coach-chat-wireup` o se rebase encima si Dev A no toca esos archivos).

---

## 3. How

### Chat ID determinístico
`[uidA, uidB]..sort().join('_')`. Garantiza que ambos lados resuelvan al mismo doc sin tener que consultar primero. Ejemplo: `aaa_bbb` para par (aaa, bbb).

### getOrCreate idempotente
```dart
Future<Chat> getOrCreate({required String selfId, required String otherId}) async {
  final id = chatIdFor(selfId, otherId);
  final ref = _db.collection('chats').doc(id);
  final snap = await ref.get();
  if (snap.exists) return Chat.fromJson({...snap.data()!, 'chatId': id});
  final members = [selfId, otherId]..sort();
  final data = {
    'chatId': id,
    'members': members,
    'createdAt': FieldValue.serverTimestamp(),
  };
  await ref.set(data);
  final created = await ref.get();
  return Chat.fromJson({...created.data()!, 'chatId': id});
}
```

### sendMessage atómico
Batch para garantizar consistencia del preview:
```dart
final batch = _db.batch();
final msgRef = _db.collection('chats/$chatId/messages').doc();
batch.set(msgRef, {
  'senderId': senderId,
  'text': text,
  'createdAt': FieldValue.serverTimestamp(),
});
final preview = text.length > 80 ? '${text.substring(0, 80)}…' : text;
batch.update(_db.collection('chats').doc(chatId), {
  'lastMessageAt': FieldValue.serverTimestamp(),
  'lastMessageText': preview,
  'lastMessageSenderId': senderId,
});
await batch.commit();
```

### Real-time updates
Firestore snapshots. `watchMessages` re-emite en cada nuevo mensaje; el `ListView.reverse` mantiene el scroll en el bottom (mensajes nuevos aparecen abajo sin shift visual).

---

## 4. Trade-offs aceptados (4 decisiones)

| # | Decisión | Rationale |
|---|---|---|
| 1 | **Chat ID determinístico vs auto-id** | `sortedUids.join('_')` evita un round-trip "buscar chat existente" antes de cada send. Ambos lados resuelven al mismo doc sin coordinación. Costo: un uid raro con `_` rompería el split — UIDs de Firebase son alfanuméricos sin underscores, así que es seguro. |
| 2 | **`lastMessageText` denormalizado en el parent** | Mostrar la lista de chats requiere el preview del último mensaje. Sin denormalización, habría que hacer N queries (una por chat) para obtenerlo. Trade-off: doble escritura en cada send (batch resuelve la atomicidad). |
| 3 | **Mensajes inmutables (no edit / delete)** | MVP. Editar mensajes complica rules + UX (¿mostrar "editado"?). Si surge la necesidad, se agrega en iteración futura. |
| 4 | **Paginación in-memory con `limit: 50`** | Conversaciones típicas en MVP son cortas (PF + athlete intercambian pocos mensajes por semana). Si una conversación crece >50, el cap visual sigue siendo razonable. Paginación real (`startAfter`) se agrega cuando hagamos histórico. |

---

## 5. Out of scope

| Item | Lands en |
|---|---|
| Push notifications cuando llega un mensaje | Fase 6 |
| Indicador de "leído" / read receipts | Iteración futura |
| Indicador de "escribiendo…" (typing) | Iteración futura |
| Adjuntar imágenes / archivos / audio | Iteración futura (necesita Storage + UX) |
| Editar o borrar mensajes | Iteración futura |
| Búsqueda dentro del chat | Iteración futura |
| Wire-up del entry point desde AthleteCoachView / TrainerCoachView / GoRouter | **Fase B de esta misma etapa**, en PR separado post-merge de Etapa 4 |

---

## 6. Success criteria

- [ ] `chats/{chatId}` con id determinístico, members sorted enforcement en rules
- [ ] `messages` sub-collection con rules read/create gated por parent members
- [ ] `getOrCreate` idempotente (segunda llamada no crea doc nuevo)
- [ ] `sendMessage` actualiza preview del parent atómicamente
- [ ] `watchMessages` stream funciona real-time (ambos lados ven el mensaje al instante)
- [ ] `watchChatsForUser` ordena por `lastMessageAt desc`
- [ ] `ChatListScreen` muestra empty state cuando no hay chats
- [ ] `ChatListScreen` muestra avatar + nombre + preview + tiempo relativo
- [ ] `ChatScreen` renderiza burbujas alineadas correctamente (propias vs entrantes)
- [ ] `ChatScreen` send envía + clear field + stream actualiza
- [ ] `flutter analyze` 0 issues
- [ ] Tests pasan + suite full
- [ ] Theme correcto: `AppPalette.of(context)`, `TreinoIcon.X`, spacing `{8,12,14,18,20}`

---

## 7. Risks

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | Rule de `chatId == members.join('_')` no es trivial de expresar en Firestore Security Rules | Se enforce via `request.resource.data.members[0] + '_' + request.resource.data.members[1] == chatId`. Si rules complica, validar client-side y dejar rule simple "members.size()==2 + caller in members". |
| 2 | `arrayContains` + `orderBy lastMessageAt` necesita composite index | Lo agregamos a `firestore.indexes.json` y deployamos post-merge. Falla detectable en smoke test si nos olvidamos. |
| 3 | Fase B (entry points) puede conflictuar con Etapa 4 de Dev A | Mitigación: Fase B se hace en PR separado DESPUÉS del merge de Etapa 4. Rebase sobre main. Conflictos esperados en `athlete_coach_view.dart` + `trainer_coach_view.dart` se resuelven manualmente. |
| 4 | Sin push, los users no se enteran de mensajes nuevos si la app está cerrada | Aceptado para MVP. Banner pasivo "Tenés N mensajes sin leer" en la próxima apertura de la app sale como follow-up rápido si lo pide producto. |
| 5 | Spam / abuse (PF mandando muchos mensajes a un athlete) | Aceptado para MVP — el athlete puede terminar el vínculo (Etapa 3 ya entrega esto). Rate limiting via Cloud Function va a Fase 6. |

---

## 8. LOC estimate

| Bucket | LOC aprox |
|---|---|
| Domain (Chat + Message + freezed/g) | ~150 |
| Repository | ~120 |
| Providers | ~60 |
| ChatListScreen | ~140 |
| ChatScreen | ~180 |
| Firestore rules block | ~30 |
| Indexes | ~12 |
| Tests | ~500 |
| **Total** | **~1192** |

PR grande pero standalone (sin tocar archivos compartidos). Fase B será un PR chico (~150 LOC: entry points + routes).

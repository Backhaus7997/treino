# Technical Design: chat-unread-count

> Phase: design (the HOW — signatures, diffs, interfaces). Reads proposal (#90) + explore (#89).
> All file paths relative to repo root `treino/`. Stack: Flutter, freezed + json_serializable, Riverpod, cloud_firestore, `FakeFirebaseFirestore` tests. Quality gate: `flutter analyze` 0 + `dart format .` + `flutter test`.

---

## 0. Architecture overview

Feature-first, unidirectional layering already in place for `chat/`:

```
domain (Chat + converters)  ── pure, no Flutter/Firestore logic
   ▲
data (ChatRepository)       ── Firestore read/write, Timestamp<->DateTime via converters
   ▲
application (chat_providers)── Riverpod stream + derived pure providers
   ▲
presentation (screens)      ── ConsumerWidget/ConsumerStatefulWidget, AppPalette/TreinoIcon/AppL10n
```

The whole feature is **additive**:
- ONE new domain field (`lastRead`) + ONE new converter (sibling to `TimestampConverter`).
- ONE new repo method (`markAsRead`).
- TWO derived providers + ONE pure helper.
- THREE small presentation edits (mark-on-open trigger, feed badge, inbox dot).
- ONE Firestore rule tightening.
- TWO i18n keys × 3 arb files.

No new Firestore listeners (the chat doc and the chat list stream are already watched). No new runtime deps.

### Data-flow diagram (unread signal)

```
sendMessage (other member)
  └─> chats/{id}.lastMessageAt + lastMessageSenderId  (existing write)
        └─> watchChatsForUser stream  (existing listener)
              └─> chatsForCurrentUserProvider (StreamProvider, existing)
                    ├─> totalUnreadCountProvider ──> feed header badge
                    └─> chatHasUnread(chat, uid) ──> inbox row dot

ChatScreen open / new inbound message while open
  └─> markAsRead(chatId, uid)
        └─> chats/{id}.lastRead.{uid} = serverTimestamp()  (NEW write)
              └─> same watchChatsForUser stream re-emits
                    └─> badge + dot recompute (now read)
```

The key invariant: **everything derives from the single `chatsForCurrentUserProvider` stream that already exists.** No second source of truth, no polling.

---

## 1. Domain — `Chat` + `TimestampMapConverter`

### 1.1 New converter (sibling), `lib/features/profile/data/timestamp_converter.dart`

Add a second converter next to the existing `TimestampConverter`. Decision rationale (from proposal): the codebase already establishes the `JsonConverter` idiom for Firestore `Timestamp`; a map variant is the consistent sibling and keeps the domain type clean (`Map<String, DateTime>`) so providers/tests compare real `DateTime`s instead of raw `Timestamp`s.

```dart
// appended to lib/features/profile/data/timestamp_converter.dart

/// Converts a Firestore map of `{uid: Timestamp}` to/from `Map<String, DateTime>`.
///
/// Used for `Chat.lastRead` (per-member last-read marker). Mirrors
/// [TimestampConverter]: values are normalized to UTC on read and wrapped in
/// [Timestamp] on write.
///
/// Null / absent handling: a NULL field is left null by the generated codec
/// (the annotated field is nullable, so `fromJson` is not invoked on null).
/// An EMPTY map round-trips to an empty map. Non-Timestamp values are not
/// expected (the only writer is [markAsRead] via serverTimestamp); if a value
/// arrives non-Timestamp it will throw on cast — acceptable, indicates corrupt
/// data, surfaced by `_chatFromDoc`'s try semantics.
class TimestampMapConverter
    implements JsonConverter<Map<String, DateTime>, Map<String, Object?>> {
  const TimestampMapConverter();

  @override
  Map<String, DateTime> fromJson(Map<String, Object?> json) {
    return json.map(
      (uid, ts) => MapEntry(uid, (ts as Timestamp).toDate().toUtc()),
    );
  }

  @override
  Map<String, Object?> toJson(Map<String, DateTime> object) {
    return object.map(
      (uid, dt) => MapEntry(uid, Timestamp.fromDate(dt)),
    );
  }
}
```

Notes:
- `JsonConverter<Map<String,DateTime>, Map<String,Object?>>` — the SECOND type param is the JSON shape. json_serializable for a nullable annotated field emits `lastRead == null ? null : const TimestampMapConverter().fromJson(lastRead)` in `chat.g.dart`, so `fromJson` is never called with null. We keep the converter NON-nullable on both sides (cleaner; matches `TimestampConverter`) and let the generated null-guard handle absence.
- Reuses `Timestamp` import already at top of the file. No new import.

### 1.2 `Chat` model, `lib/features/chat/domain/chat.dart`

```dart
@freezed
class Chat with _$Chat {
  const factory Chat({
    required String chatId,
    required List<String> members,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() DateTime? lastMessageAt,
    String? lastMessageText,
    String? lastMessageSenderId,
    @TimestampMapConverter() Map<String, DateTime>? lastRead, // NEW
  }) = _Chat;

  factory Chat.fromJson(Map<String, Object?> json) => _$ChatFromJson(json);
}
```

- `lastRead` is **nullable** — legacy docs (and freshly created chats) have no `lastRead` key → `null` → "never read" (correct, see Risk 2). We do NOT default to `const {}` because a nullable field lets `_chatFromDoc` and the codec skip conversion cleanly, and the unread helper already treats null as unread.
- `TimestampMapConverter` is already imported transitively via the existing `import '../../profile/data/timestamp_converter.dart';` (same file holds both converters) — NO new import line needed.
- Field placed LAST to keep the positional/named factory diff minimal and avoid touching unrelated generated ordering.

### 1.3 Codegen — regenerate `chat.freezed.dart` + `chat.g.dart`

Run `dart run build_runner build --delete-conflicting-outputs`. Regenerates:
- `chat.freezed.dart`: adds `lastRead` to constructor, `copyWith`, `==`, `hashCode`, `toString`.
- `chat.g.dart`: `_$ChatFromJson` gains the null-guarded `const TimestampMapConverter().fromJson(...)`; `_$ChatToJson` gains the null-guarded `?.let`-style `const TimestampMapConverter().toJson(...)`.

`flutter analyze` (0 issues) is the guard against stale codegen — a missing regen breaks compilation of the named param and is caught immediately.

---

## 2. Data — `ChatRepository.markAsRead`

`lib/features/chat/data/chat_repository.dart`. Add ONE method after `sendMessage` (before `watchMessages`). Uses a **dotted-path update** so only the caller's own key is written — this is what the Firestore rule (§5) enforces server-side.

```dart
  // ─── markAsRead ─────────────────────────────────────────────────────────
  //
  // Marks the chat as read up to "now" for [uid] by writing ONLY that uid's
  // key in the `lastRead` map via a dotted-path update. Other members' keys
  // are untouched — required by the security rule (only own key may change).
  // serverTimestamp keeps the marker on the same clock as lastMessageAt so the
  // unread comparison is monotonic.
  //
  // No-op safety: if the chat doc does not exist the update throws; callers
  // (ChatScreen) only invoke this for an already-resolved chat, so existence
  // is guaranteed. We intentionally do NOT create the doc here.

  Future<void> markAsRead({
    required String chatId,
    required String uid,
  }) {
    return _chats.doc(chatId).update({
      'lastRead.$uid': FieldValue.serverTimestamp(),
    });
  }
```

- Named params to match the `sendMessage` convention in this file (the other methods use named params; only the pure `chatIdFor` is positional).
- `'lastRead.$uid'` dotted path: Firestore merges into the nested map without overwriting sibling keys. In `FakeFirebaseFirestore` this is supported and observable as a nested map — the repo test asserts on it.
- **`watchChatsForUser` already surfaces `lastRead`**: it calls `_chatFromDoc` → `Chat.fromJson({...data, 'chatId': snap.id})`, and `data` is the full doc map including the `lastRead` key once written. No change needed to `watchChatsForUser` or `_chatFromDoc`. Confirmed by reading lines 152-171.
- `FieldValue` is already imported (line 4-7 show-import list includes `FieldValue`).

---

## 3. Application — derived providers + pure helper

`lib/features/chat/application/chat_providers.dart`. Add a pure top-level helper + two providers. Keeping the boolean logic in a free function makes it unit-testable without a `ProviderContainer`.

### 3.1 Pure helper `chatHasUnread`

```dart
/// Pure: is [chat] unread for [uid]?
///
/// Unread iff there IS a last message, it was NOT sent by [uid], and either
/// [uid] never read the chat (no lastRead entry) OR the last message is strictly
/// newer than uid's last-read marker.
///
/// - Self-sent last message → always read (you don't get notified of your own).
/// - No lastMessageAt (fresh chat, no messages) → read (nothing to read).
/// - lastRead null / missing uid key → treated as never-read → unread.
bool chatHasUnread(Chat chat, String uid) {
  final lastAt = chat.lastMessageAt;
  if (lastAt == null) return false;
  if (chat.lastMessageSenderId == uid) return false;
  final readAt = chat.lastRead?[uid];
  if (readAt == null) return true;
  return lastAt.isAfter(readAt);
}
```

Boundary decisions (locked):
- Comparison is `isAfter` (strict `>`). Equal timestamps → read. serverTimestamp on the same doc makes exact equality between `lastMessageAt` and `lastRead[uid]` effectively impossible, but strict-after is the correct semantic and matches the proposal (`lastMessageAt > lastRead[uid]`).
- `uid == ''` (no current user resolved): callers pass a real uid; with `''` the senderId check and map lookup both behave (a chat is "unread" only if last message sender != '' and there's no `''` key — harmless, but presentation guards `currentUid == null` before counting, see §4).

### 3.2 `unreadCountForChatProvider` (boolean per chat)

Proposal names it `unreadCountForChatProvider` but the value is a **boolean** ("has unread"), matching Decision 2. We expose a `Provider.family<bool, Chat>` so widgets can watch a single chat. It simply delegates to the pure helper using the current uid.

```dart
/// Whether a given [chat] has unread messages for the current user.
/// Derived synchronously; returns false when there is no current uid.
final unreadCountForChatProvider =
    Provider.autoDispose.family<bool, Chat>((ref, chat) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return false;
  return chatHasUnread(chat, uid);
});
```

- `family<bool, Chat>`: keyed by the `Chat` value (freezed `==`/`hashCode` make this stable across identical rebuilds).
- Inbox rows MAY use this provider OR call `chatHasUnread` directly with the row's `currentUid`. The chosen wiring (see §4.3) is the pure helper directly inside `_ChatRow` since the row already has `chat` + `currentUid` in scope — fewer family instances, simpler. The provider is still defined for completeness/testability and any future single-chat consumer. (Tasks phase decides whether to keep both; design recommends: keep the helper + `totalUnreadCountProvider`, and make `unreadCountForChatProvider` optional. Mark in tasks.)

### 3.3 `totalUnreadCountProvider` (count over the live list)

```dart
/// Count of chats with at least one unread message for the current user.
/// Derived from the existing chatsForCurrentUserProvider stream — NO new
/// Firestore listener. Returns 0 during loading/error (mirrors
/// pendingRequestCountProvider) so the badge never flickers a stale number.
final totalUnreadCountProvider = Provider.autoDispose<int>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return 0;
  return ref.watch(chatsForCurrentUserProvider).maybeWhen(
        data: (chats) => chats.where((c) => chatHasUnread(c, uid)).length,
        orElse: () => 0,
      );
});
```

- Mirrors `pendingRequestCountProvider` EXACTLY (the established badge pattern): `Provider.autoDispose<int>`, `.maybeWhen(data: ..., orElse: () => 0)`.
- Not a `family` — there is a single "current user", so a plain `Provider` is correct (the feed header reads it once).
- `autoDispose` matches the upstream stream's lifecycle.

### 3.4 Required imports

`currentUidProvider` is already imported (line 5-6). `Chat` is already imported (line 9). No new imports.

---

## 4. Presentation

### 4.1 `chat_screen.dart` — mark-as-read on open + on new inbound message

`ChatScreen` is already a `ConsumerStatefulWidget`. Add the mark-as-read trigger. Two firing points:
1. **First frame** (`initState` → `addPostFrameCallback`) — covers "open an existing unread thread".
2. **`ref.listen(messagesProvider(chatId))`** in `build` — re-fires when a new message arrives while the screen is mounted, so an inbound message received with the chat open does not leave it unread.

```dart
class _ChatScreenState extends ConsumerState<ChatScreen> {
  // ... existing fields ...

  @override
  void initState() {
    super.initState();
    // Mark-as-read on open. Post-frame so ref is safe to read and we don't
    // block the first paint. Guard: no-op without a current uid.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAsRead());
  }

  void _markAsRead() {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    // Fire-and-forget; failures are non-critical (read marker only).
    ref.read(chatRepositoryProvider).markAsRead(
          chatId: widget.chatId,
          uid: uid,
        );
  }

  // ... existing dispose, _onSend, _onAttach unchanged ...

  @override
  Widget build(BuildContext context) {
    // Re-mark when a new message lands while the chat is open. The stream
    // re-emits on every message change; we only need to re-mark on inbound
    // ones, but re-marking on any change is cheap (one keyed write, debounced
    // server-side) and keeps the logic simple. Guarded by mounted via ref.
    ref.listen(messagesProvider(widget.chatId), (prev, next) {
      next.whenData((messages) {
        if (messages.isEmpty) return;
        final uid = ref.read(currentUidProvider);
        if (uid == null) return;
        // Only re-mark if the newest message is NOT mine — avoids a write on
        // every send. messages[0] is newest (orderBy createdAt desc).
        if (messages.first.senderId == uid) return;
        _markAsRead();
      });
    });

    // ... existing build body unchanged ...
  }
}
```

Decisions:
- `addPostFrameCallback` over calling in `initState` body directly: reading providers and triggering a Firestore write is safe post-frame and avoids "ref used during build" subtleties.
- `ref.listen` placed at the top of `build` (Riverpod requires `ref.listen` inside `build`, not `initState`). It is idempotent across rebuilds — Riverpod dedups identical listen registrations per build.
- **Guard `currentUid == null`** in both `_markAsRead` and the listener (the task explicitly requires this). Mirrors the existing `_onSend`/`_onAttach` guards (lines 56-57, 99-100).
- Skip re-mark when `messages.first.senderId == uid`: the newest message being mine means I just sent it — no unread to clear, saves a redundant write. (The first-frame mark already handled any prior inbound.)
- `WidgetsBinding` requires `import 'package:flutter/material.dart';` — already imported (line 3).
- Fire-and-forget (no `await`, no error UI): the read marker is non-critical; a transient failure self-heals on the next open or next inbound message. We do NOT show a SnackBar (unlike send), to avoid noise.

### 4.2 `feed_screen.dart` — number badge on the messages icon (`_FeedHeader`)

Reuse the **exact bell-badge pattern** (lines 130-183). The messages icon (lines 185-205) is currently a bare `Icon` inside a `Center`; wrap it in the same `Stack(clipBehavior: Clip.none)` + `Positioned(top:-4, right:-5)` + `Container(accent, radius 8)` + `Text(bg)` structure, driven by `totalUnreadCountProvider`, with a **99+** cap (bell uses 9+).

Diff to `_FeedHeader.build`:

```dart
    final uid = ref.watch(currentUidProvider);
    final pendingRequests =
        uid == null ? 0 : ref.watch(pendingRequestCountProvider(uid));
    final unreadChats = ref.watch(totalUnreadCountProvider); // NEW
```

Replace the messages `Semantics`/icon block (185-205) with:

```dart
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: unreadChats > 0
                ? l10n.feedMessagesWithUnreadA11y(unreadChats) // NEW key
                : l10n.feedMessagesA11y,                       // existing (0 case)
            child: GestureDetector(
              onTap: () => context.push('/feed/messages'),
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        TreinoIcon.chat,
                        size: 20,
                        color: palette.textMuted,
                      ),
                      if (unreadChats > 0)
                        Positioned(
                          top: -4,
                          right: -5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            constraints: const BoxConstraints(minWidth: 16),
                            decoration: BoxDecoration(
                              color: palette.accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              unreadChats > 99 ? '99+' : '$unreadChats',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.barlow(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: palette.bg,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
```

- Byte-for-byte the bell structure except: icon `TreinoIcon.chat`, count source `unreadChats`, cap `'99+'` at `> 99`, route `/feed/messages`, a11y key `feedMessagesWithUnreadA11y`.
- The existing `feedMessagesA11y` ("Mensajes"/"Messages") is reused for the zero case — exactly mirroring how the bell uses `feedFriendRequestsA11y` vs `feedFriendRequestsWithCountA11y`.
- `GoogleFonts` already imported in `feed_screen.dart` (used by the FEED title and bell badge).
- No `const` regressions: the `Container`/`Text` cannot be `const` (palette + dynamic count), same as the bell — consistent.

### 4.3 `chat_list_screen.dart` — accent dot in `_ChatRow`

`_ChatRow` already has `chat` and `currentUid` in scope and is a `ConsumerWidget`. Compute unread with the pure helper (no extra provider instance) and render an ~8px `palette.accent` dot. Place it as a trailing element so a read row is visually unchanged.

Inside `_ChatRow.build`, after `final pubAsync = ...`:

```dart
    final hasUnread =
        currentUid.isNotEmpty && chatHasUnread(chat, currentUid); // NEW
```

In the `data: (pub)` `Row` children, the dot goes at the END (after the timestamp block), wrapped so a read row renders nothing:

```dart
                if (chat.lastMessageAt != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    _relativeTime(chat.lastMessageAt!, l10n),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (hasUnread) ...[                       // NEW
                  const SizedBox(width: 10),
                  Semantics(
                    label: l10n.chatUnreadA11y,           // NEW key
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
```

- Dot is a `Container` (8×8, `BoxShape.circle`, `palette.accent`). Cannot be `const` (palette). Wrapped in `Semantics(label: chatUnreadA11y)` so screen readers announce "Sin leer"/"Unread".
- Decision: use the **pure helper directly** in the row (it already has both inputs) rather than `ref.watch(unreadCountForChatProvider(chat))`. Reason: avoids creating one autoDispose family instance per visible row, and the row already rebuilds when the chat list stream re-emits (the list is rebuilt from `chatsForCurrentUserProvider`). The helper recomputes synchronously on each rebuild — correct and cheap.
- Import: add `chatHasUnread` — it lives in `chat_providers.dart`, already imported (line 13). No new import.

### 4.4 Bottom-tab badge — OUT OF SCOPE

`TreinoBottomBar` is a pure `StatelessWidget` with no badge API; restructuring it is disproportionate (proposal "Out of scope"). The chat entry point is the feed-header icon, which now carries the total badge. No change.

---

## 5. Firestore rule — tighten `chats/{chatId}` update

`firestore.rules`, current `allow update` at lines 436-439. Add a fourth condition: a member may modify the `lastRead` map ONLY for their own uid key. Null-safe for legacy docs that lack `lastRead`.

### Current (436-439)

```
      allow update: if request.auth != null
                    && request.auth.uid in resource.data.members
                    && request.resource.data.members == resource.data.members
                    && request.resource.data.createdAt == resource.data.createdAt;
```

### New

```
      // update: caller en members; members/createdAt inmutables; y si se toca
      // `lastRead`, SOLO puede cambiar la clave propia del caller (un miembro
      // no puede marcar leído en nombre del otro). `get('lastRead', {})` es
      // null-safe para docs legacy sin el campo.
      allow update: if request.auth != null
                    && request.auth.uid in resource.data.members
                    && request.resource.data.members == resource.data.members
                    && request.resource.data.createdAt == resource.data.createdAt
                    && (
                         !request.resource.data.keys().hasAny(['lastRead'])
                         || request.resource.data.get('lastRead', {})
                              .diff(resource.data.get('lastRead', {}))
                              .affectedKeys()
                              .hasOnly([request.auth.uid])
                       );
```

Mechanics:
- `request.resource.data` = post-write doc; `resource.data` = pre-write doc.
- `!request.resource.data.keys().hasAny(['lastRead'])`: a `sendMessage` update (which touches `lastMessageAt/Text/SenderId` but NOT `lastRead`) passes via this first branch — we don't force every update to carry `lastRead`.
- Else branch: `Map.diff().affectedKeys().hasOnly([uid])` — the SET of keys whose value changed between old and new `lastRead` must be a subset of `{caller.uid}`. Writing `lastRead.{otherUid}` changes a foreign key → `affectedKeys()` contains `otherUid` → `hasOnly([uid])` false → DENIED.
- `get('lastRead', {})` on BOTH sides: defaults missing field to empty map so `diff` is null-safe on legacy docs (first-ever `markAsRead` on a doc with no prior `lastRead`).
- `members`/`createdAt` immutability is preserved (unchanged AND clauses).

### Testability (Risk 1 — IMPORTANT)

`FakeFirebaseFirestore` does **NOT** enforce security rules. `diff().affectedKeys().hasOnly` cannot be covered by the existing Dart suite. There IS a `test/features/coach/data/firestore_rules_test.dart` in the repo, but confirm whether it runs against the emulator or is a structural/string test before assuming it can host this. Plan:
- Mark the rule as **emulator-only / manual verification** (Firebase emulator + `@firebase/rules-unit-testing` OR manual console test).
- Add explicit verify-phase checklist items:
  1. Member A can write `chats/{id}.lastRead.{A}` → ALLOW.
  2. Member A attempts `chats/{id}.lastRead.{B}` → DENY.
  3. `sendMessage`-style update (no `lastRead` key) → ALLOW.
  4. Update mutating `members` or `createdAt` → DENY (regression guard).
- Do NOT introduce a new emulator harness in this change (proposal Risk 1). Document as manual in verify.

---

## 6. i18n — 2 new keys × 3 arb files

Template is **`intl_es_AR.arb`** (`l10n.yaml: template-arb-file: intl_es_AR.arb`). Only the template carries the `@key` metadata block (`description` + `placeholders`); `intl_en.arb` and `intl_es.arb` carry the value string only. Mirror the existing `feedFriendRequestsWithCountA11y` precedent exactly.

### New keys

| Key | Type | Purpose |
|---|---|---|
| `feedMessagesWithUnreadA11y` | message w/ `{count}` (int) | Feed-header messages icon a11y label when total unread > 0. Zero case keeps existing `feedMessagesA11y`. |
| `chatUnreadA11y` | plain | a11y label for the inbox-row unread dot. |

### `lib/l10n/intl_es_AR.arb` (template — value + metadata)

Insert near the existing `feedMessagesA11y` (~line 783) and the `@feedFriendRequestsWithCountA11y` block (~800) for locality:

```json
  "feedMessagesWithUnreadA11y": "Mensajes, {count} sin leer",
  "@feedMessagesWithUnreadA11y": {
    "description": "Accessibility label for the feed header messages icon when there are unread chats; announces the unread badge count to screen readers.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "chatUnreadA11y": "Sin leer",
  "@chatUnreadA11y": {
    "description": "Accessibility label for the unread dot shown on an inbox chat row that has unread messages."
  },
```

### `lib/l10n/intl_es.arb` (value only)

```json
  "feedMessagesWithUnreadA11y": "Mensajes, {count} sin leer",
  "chatUnreadA11y": "Sin leer",
```

### `lib/l10n/intl_en.arb` (value only)

```json
  "feedMessagesWithUnreadA11y": "Messages, {count} unread",
  "chatUnreadA11y": "Unread",
```

- After editing arbs, `flutter gen-l10n` (or the next `flutter test`/build, which auto-generates) regenerates `app_l10n.dart`. `AppL10n.of(context).feedMessagesWithUnreadA11y(count)` and `.chatUnreadA11y` become available.
- Verify the generated getters compile (analyze 0). A placeholder mismatch (e.g. forgetting `count` metadata in the template) surfaces as a missing/typed-wrong method.

---

## 7. Test architecture (Strict TDD)

Conventions confirmed from the repo:
- Data/App: `FakeFirebaseFirestore` + `ProviderContainer(overrides: [firestoreProvider.overrideWithValue(...), currentUidProvider.overrideWith(...)])`, `addTearDown(container.dispose)`.
- Widget: `ProviderScope(overrides: [...])` + `TestAppWrapper` + override stream providers with `Stream.value([...])` (see `chat_deleted_user_test.dart`).
- Existing files to EXTEND (do not recreate): `test/features/chat/domain/chat_test.dart`, `test/features/chat/application/chat_providers_test.dart`, `test/features/profile/data/timestamp_converter_test.dart`, `test/features/chat/presentation/widgets/chat_deleted_user_test.dart`.

Strict TDD: write the RED test for each unit BEFORE its implementation, watch it fail, then implement to GREEN, then refactor. Order below follows the dependency graph (domain → data → app → presentation).

### 7.1 Domain — `TimestampMapConverter`
**File:** `test/features/profile/data/timestamp_converter_test.dart` (extend; add a new `group`).
Assertions:
- `toJson({uid: dt})` returns `Map<String, Object?>` whose value is a `Timestamp` (`isA<Timestamp>()`).
- `fromJson({uid: Timestamp})` returns `Map<String, DateTime>` with UTC `DateTime` values.
- Round-trip `fromJson(toJson({a: dt1, b: dt2})) == {a: dt1, b: dt2}` at ms precision.
- Empty map round-trips to empty map (`{}` → `{}`).
- Multi-key preserves all entries.

### 7.2 Domain — `Chat` with `lastRead`
**File:** `test/features/chat/domain/chat_test.dart` (extend).
Assertions:
- Full record incl. `lastRead: {uid: dt}` survives `Chat.fromJson(chat.toJson())` (equality).
- Record with `lastRead: null` round-trips with `lastRead == null` (legacy/fresh).
- `fromJson` from a raw Firestore-shaped map (`lastRead: {uid: Timestamp(...)}`) decodes to `{uid: DateTime}`.
- `fromJson` of a map WITHOUT a `lastRead` key → `lastRead == null` (no crash) — the legacy-doc case.
- `copyWith(lastRead: {...})` produces a non-equal record; `==`/`hashCode` consistent.

### 7.3 Data — `ChatRepository.markAsRead`
**File:** `test/features/chat/data/chat_repository_test.dart` (NEW file; none exists today).
Setup: `FakeFirebaseFirestore`, `ChatRepository(firestore: fake)`, seed a chat via `getOrCreate` + `sendMessage`.
Assertions:
- After `markAsRead(chatId, 'aaa')`, reading the doc shows `lastRead['aaa']` is a non-null `Timestamp` (`FakeFirebaseFirestore` resolves serverTimestamp).
- `markAsRead(chatId, 'aaa')` then `markAsRead(chatId, 'bbb')` → doc has BOTH `lastRead['aaa']` and `lastRead['bbb']` (dotted-path merge does NOT clobber the sibling key). This is the key cross-member-isolation assertion at the data level.
- A subsequent `markAsRead(chatId, 'aaa')` updates `aaa`'s value without removing `bbb`'s.
- (Optional) `watchChatsForUser('aaa')` emits a `Chat` whose `lastRead['aaa']` is populated after `markAsRead` — proves the field is surfaced end-to-end through the existing stream.

### 7.4 App — `chatHasUnread` + providers
**File:** `test/features/chat/application/chat_providers_test.dart` (extend; the pure helper can also get its own pure `group` with no container).
Pure `chatHasUnread` assertions (construct `Chat` literals, no Firestore):
- last message from OTHER, `lastRead` null → `true` (unread).
- last message from OTHER, `lastRead[uid]` BEFORE `lastMessageAt` → `true`.
- last message from OTHER, `lastRead[uid]` AFTER `lastMessageAt` → `false` (read).
- last message from OTHER, `lastRead[uid] == lastMessageAt` → `false` (strict isAfter).
- last message from SELF (`lastMessageSenderId == uid`) → `false` regardless of `lastRead`.
- `lastMessageAt == null` (fresh chat) → `false`.
- `lastRead` present but missing `uid` key → `true`.

`totalUnreadCountProvider` assertions (override `chatsForCurrentUserProvider` with `Stream.value([...])` + `currentUidProvider`):
- 3 chats, 2 unread for uid → `2`.
- 0 unread → `0`.
- `currentUid == null` → `0`.
- loading/error state of the upstream → `0` (orElse path).

`unreadCountForChatProvider` assertions (if kept): true/false delegating to helper; `null` uid → `false`.

### 7.5 Presentation — `ChatScreen` mark-as-read trigger
**File:** `test/features/chat/presentation/chat_screen_test.dart` (NEW file).
Approach: pump `ChatScreen` inside `ProviderScope` + `TestAppWrapper`, override `currentUidProvider`, `userPublicProfileProvider(otherUid)` (avoid network), and inject a **fake/spy `ChatRepository`** via `chatRepositoryProvider.overrideWithValue(spy)` so we can assert `markAsRead` calls. Override `messagesProvider(chatId)` with a controllable stream (e.g. a `StreamController`) to simulate inbound messages.
Assertions:
- On first frame (`pumpAndSettle`), `spy.markAsRead(chatId, currentUid)` was called exactly once.
- Emitting a NEW message with `senderId != currentUid` via the stream → `markAsRead` called again (re-fire).
- Emitting a new message with `senderId == currentUid` (my own send) → NO additional `markAsRead` (the skip guard).
- With `currentUid == null` override → `markAsRead` NEVER called (null guard).
- Spy is a minimal hand-written class implementing the methods used, or a counter wrapper around a real `ChatRepository(FakeFirebaseFirestore())`. (No mockito in repo by default — confirm; otherwise hand-roll a spy, matching existing style.)

### 7.6 Presentation — inbox dot
**File:** `test/features/chat/presentation/widgets/chat_list_screen_test.dart` (NEW) — or extend `chat_deleted_user_test.dart` which already pumps `ChatListScreen` with overridden `chatsForCurrentUserProvider`.
Assertions (reuse the `buildChatListScreen` harness pattern):
- Chat that IS unread for currentUid → the accent dot is present. Find by the `Semantics(label: chatUnreadA11y)` (resolve the localized string via the test `AppL10n`, or match the `Semantics` finder) OR by a keyed/typed finder on the 8×8 `Container`. Prefer asserting the `Semantics` label is in the tree (`find.bySemanticsLabel`).
- Chat that is READ (e.g. `lastRead[currentUid]` after `lastMessageAt`, or last message self-sent) → NO dot (`findsNothing` for the unread semantics label).
- Self-sent last message → NO dot.

### 7.7 Presentation — feed-header badge
**File:** `test/features/feed/presentation/widgets/feed_header_badge_test.dart` (NEW) — or a focused widget test that pumps `_FeedHeader` via the public `FeedScreen`. Since `_FeedHeader` is private, pump the smallest public host that renders it (FeedScreen) inside `ProviderScope` + `TestAppWrapper`, overriding `currentUidProvider` and `totalUnreadCountProvider` (it's a plain `Provider`, override with `overrideWithValue`/`overrideWith`).
Assertions:
- `totalUnreadCountProvider` → 0: NO badge (`find.text('0')` findsNothing near the messages icon; assert the messages a11y label equals `feedMessagesA11y`).
- → 3: badge shows `'3'`; messages a11y label equals `feedMessagesWithUnreadA11y(3)`.
- → 150: badge shows `'99+'` (cap).
- Badge container uses `palette.accent` background (optional visual assertion via `Container` decoration).
- NOTE: overriding `totalUnreadCountProvider` directly is the clean seam (it's pure). If FeedScreen pulls in many other providers, prefer overriding `totalUnreadCountProvider` + minimal feed providers, or extract the badge into a small public widget in a later refactor (NOT this change — keep scope tight; document if the test proves too heavy).

### 7.8 Firestore rule — manual / emulator (Risk 1)
NOT in the automated `flutter test` suite. Add to verify-phase checklist (see §5 testability). Mark explicitly as emulator-only. Investigate whether `test/features/coach/data/firestore_rules_test.dart` is an emulator harness that could host the 4 cases; if it is purely structural, keep the rule verification manual and document the exact emulator steps in the verify report.

### Test file summary

| Layer | File | New/Extend |
|---|---|---|
| Domain converter | `test/features/profile/data/timestamp_converter_test.dart` | Extend |
| Domain model | `test/features/chat/domain/chat_test.dart` | Extend |
| Data repo | `test/features/chat/data/chat_repository_test.dart` | **New** |
| App providers/helper | `test/features/chat/application/chat_providers_test.dart` | Extend |
| ChatScreen trigger | `test/features/chat/presentation/chat_screen_test.dart` | **New** |
| Inbox dot | `test/features/chat/presentation/widgets/chat_list_screen_test.dart` (or extend `chat_deleted_user_test.dart`) | **New/Extend** |
| Feed badge | `test/features/feed/presentation/widgets/feed_header_badge_test.dart` | **New** |
| Rule | manual / emulator | Out of automated suite |

---

## 8. ADR-style decisions (with rejected alternatives)

### ADR-CUC-001 — Read state as a `lastRead: {uid: Timestamp}` map on the chat doc
- **Decision:** Store per-member last-read markers as a map field on `chats/{chatId}`.
- **Rationale:** The chat doc is ALREADY watched by `watchChatsForUser`; zero new listeners. Simplest possible storage.
- **Rejected:** (a) `chats/{id}/reads/{uid}` subcollection — adds a listener per chat or a collectionGroup query; overkill. (b) Cloud-Function-maintained unread counter — heavy infra for an MVP boolean; `notify-chat-message.ts` stays untouched.
- **Consequence:** Requires the §5 rule tightening to stop a member writing another member's key.

### ADR-CUC-002 — `TimestampMapConverter` sibling, NOT raw-map special-casing in `_chatFromDoc`
- **Decision:** A `JsonConverter<Map<String,DateTime>, Map<String,Object?>>` next to the existing `TimestampConverter`, annotated on the `lastRead` field.
- **Rationale:** The codebase already standardizes Timestamp conversion via `JsonConverter`. Keeping the domain type `Map<String,DateTime>` lets providers/tests compare real `DateTime`s; conversion is centralized in generated code, not scattered in `_chatFromDoc`.
- **Rejected:** Store `lastRead` as raw `Map<String,dynamic>` and convert ad-hoc in `_chatFromDoc` — diverges from the established converter idiom and pushes Timestamp handling into the repository.
- **Consequence:** One more converter class + build_runner regen.

### ADR-CUC-003 — Client-side boolean unread, derived from the existing stream
- **Decision:** `chatHasUnread(chat, uid)` pure helper + `totalUnreadCountProvider` counting over `chatsForCurrentUserProvider`. No exact per-conversation count.
- **Rationale:** Zero extra queries; the inbox dot is a boolean and the header badge is a count of unread CHATS (not messages). Pure logic is trivially testable.
- **Rejected:** Firestore `count()` aggregation per chat (extra reads, async, more complex) — exact per-conversation counts are explicitly out of scope and can be layered later.
- **Consequence:** The header badge counts unread conversations, not unread messages. Acceptable per proposal.

### ADR-CUC-004 — Mark-as-read on first frame + `ref.listen` re-fire
- **Decision:** `addPostFrameCallback` mark on open; `ref.listen(messagesProvider)` re-marks on inbound message while mounted (skipping self-sent).
- **Rationale:** Covers both "open unread thread" and "message arrives while reading". Fire-and-forget; no error UI for a non-critical marker.
- **Rejected:** Mark only in `initState` — would leave a thread unread if a message arrives while it's open.
- **Consequence:** Up to one extra keyed write per inbound message while the chat is open; cheap.

### ADR-CUC-005 — Reuse the bell-badge widget pattern verbatim; 99+ cap; dot for rows
- **Decision:** Feed-header messages icon gets the EXACT bell `Stack`+`Positioned`+`Container(accent,radius8)`+`Text(bg)` (cap `99+`); inbox rows get an 8px accent dot, not a number.
- **Rationale:** Visual consistency with the existing notification badge; a per-row number is noise (boolean suffices in the list).
- **Rejected:** A new bespoke badge widget — needless divergence. A number per inbox row — out of scope and visually heavy.
- **Consequence:** Two distinct UI affordances (count badge vs dot) for the same underlying signal — intentional.

### ADR-CUC-006 — Firestore rule restricts `lastRead` to the caller's own key
- **Decision:** `diff().affectedKeys().hasOnly([request.auth.uid])`, gated behind `keys().hasAny(['lastRead'])`, null-safe via `get('lastRead', {})`.
- **Rationale:** Prevents a member from marking the conversation read on the other member's behalf, while letting `sendMessage` updates (no `lastRead` key) and first-ever marks (legacy docs) pass.
- **Rejected:** No rule change — a malicious client could overwrite the peer's marker. A full field-level allowlist rewrite — larger blast radius than needed.
- **Consequence:** Not unit-testable with `FakeFirebaseFirestore`; verified manually/emulator (Risk 1).

---

## 9. Affected files (final)

| File | Change |
|---|---|
| `lib/features/profile/data/timestamp_converter.dart` | + `TimestampMapConverter` |
| `lib/features/chat/domain/chat.dart` | + `lastRead` field + `@TimestampMapConverter()` |
| `lib/features/chat/domain/chat.freezed.dart` | regen (build_runner) |
| `lib/features/chat/domain/chat.g.dart` | regen (build_runner) |
| `lib/features/chat/data/chat_repository.dart` | + `markAsRead` |
| `lib/features/chat/application/chat_providers.dart` | + `chatHasUnread`, `totalUnreadCountProvider`, (opt) `unreadCountForChatProvider` |
| `lib/features/chat/presentation/chat_screen.dart` | + initState post-frame mark + `ref.listen` re-mark, null guards |
| `lib/features/chat/presentation/chat_list_screen.dart` | + unread dot in `_ChatRow` |
| `lib/features/feed/feed_screen.dart` | + badge on messages icon in `_FeedHeader` |
| `firestore.rules` | tighten `chats/{chatId}` update (lastRead own-key) |
| `lib/l10n/intl_es_AR.arb` | + 2 keys (value + metadata) |
| `lib/l10n/intl_es.arb` | + 2 keys (value only) |
| `lib/l10n/intl_en.arb` | + 2 keys (value only) |
| `lib/l10n/app_l10n.dart` | regen (gen-l10n) |
| `test/features/profile/data/timestamp_converter_test.dart` | extend |
| `test/features/chat/domain/chat_test.dart` | extend |
| `test/features/chat/data/chat_repository_test.dart` | NEW |
| `test/features/chat/application/chat_providers_test.dart` | extend |
| `test/features/chat/presentation/chat_screen_test.dart` | NEW |
| `test/features/chat/presentation/widgets/chat_list_screen_test.dart` | NEW (or extend chat_deleted_user_test.dart) |
| `test/features/feed/presentation/widgets/feed_header_badge_test.dart` | NEW |

## 10. Build/quality steps (apply order)
1. Write RED tests per §7 (Strict TDD).
2. Add `TimestampMapConverter`; add `Chat.lastRead`.
3. `dart run build_runner build --delete-conflicting-outputs`.
4. Implement `markAsRead`, helper + providers, presentation edits, arbs (+ `flutter gen-l10n`), rule.
5. `flutter analyze` (0) → `dart format .` → `flutter test` (green).
6. Manual/emulator rule verification (verify phase) for ADR-CUC-006.

## 11. Open items for tasks/verify
- Decide whether to KEEP `unreadCountForChatProvider` or rely solely on the pure helper in `_ChatRow` (design recommends helper-only in the row, keep provider optional). Tasks should make one explicit call.
- Confirm whether `test/features/coach/data/firestore_rules_test.dart` is an emulator harness (could host the 4 rule cases) or a structural test (keep rule manual). Verify phase to confirm; do NOT add a new harness in this change.
- Confirm no `mockito` in `pubspec` before writing the ChatScreen spy; if absent, hand-roll a counter spy (matches repo style).

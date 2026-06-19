# chat-unread-count — Ordered Implementation Task Checklist

**Single PR** · Estimated changed lines: ~340 · 400-line budget risk: Low · Chained PRs recommended: No

---

## Group 1 — Domain: TimestampMapConverter (SEQUENTIAL)

### TASK-01 [RED] — Tests for TimestampMapConverter

- **File**: `test/features/profile/data/timestamp_converter_test.dart` (EXTEND existing group)
- **Add group**: `TimestampMapConverter` — tests: `toJson` value `isA<Timestamp>`; `fromJson` returns UTC DateTime; roundtrip preserves ms; empty map round-trips to empty map; multi-key map decoded correctly; non-null both sides contract.
- **REQ**: REQ-CHATUNREAD-001 (data fidelity precondition)
- **Gate**: `flutter test test/features/profile/data/timestamp_converter_test.dart` — FAILS (RED)

### TASK-02 [GREEN] — Implement TimestampMapConverter

- **File**: `lib/features/profile/data/timestamp_converter.dart` (EXTEND — append class after `TimestampConverter`)
- `class TimestampMapConverter implements JsonConverter<Map<String,DateTime>, Map<String,Object?>>` · `fromJson`: `json.map((u,ts) => MapEntry(u, (ts as Timestamp).toDate().toUtc()))` · `toJson`: inverse with `Timestamp.fromDate`. No new imports needed.
- **Gate**: TASK-01 tests GREEN · `flutter analyze` 0

---

## Group 2 — Domain: Chat.lastRead field + codegen (SEQUENTIAL, after Group 1)

### TASK-03 [RED] — Tests for Chat.lastRead JSON round-trip

- **File**: `test/features/chat/domain/chat_test.dart` (EXTEND with new group `Chat.lastRead`)
- **Cases**: `lastRead{uid:dt}` round-trips equal; `lastRead: null` round-trips null; raw Timestamp-map decode (Firestore path); NO `lastRead` key in JSON → `null` (legacy doc); `copyWith` preserves lastRead.
- **REQ**: REQ-CHATUNREAD-001, REQ-CHATUNREAD-004
- **Gate**: `flutter test test/features/chat/domain/chat_test.dart` — RED

### TASK-04 [GREEN] — Add lastRead field to Chat model + run build_runner

- **File**: `lib/features/chat/domain/chat.dart` — add last named param: `@TimestampMapConverter() Map<String,DateTime>? lastRead`. No new import (`timestamp_converter.dart` already imported).
- Run `dart run build_runner build --delete-conflicting-outputs` → regenerates `chat.freezed.dart` + `chat.g.dart`.
- **Gate**: TASK-03 tests GREEN · `flutter analyze` 0 · `dart format .`

---

## Group 3 — Data: markAsRead (SEQUENTIAL, after Group 2)

### TASK-05 [RED] — Tests for ChatRepository.markAsRead

- **File**: `test/features/chat/data/chat_repository_test.dart` (EXTEND with new group `markAsRead`)
- **Cases**: writes `lastRead[uid]` as a non-null Timestamp; calling `markAsRead(A)` then `markAsRead(B)` leaves BOTH keys present (no clobber); re-marking A does not disturb B's key; `watchChatsForUser` stream surfaces `lastRead` in the returned `Chat` objects.
- **REQ**: REQ-CHATUNREAD-001 (SCENARIO-CHATUNREAD-001)
- **Gate**: RED

### TASK-06 [GREEN] — Implement ChatRepository.markAsRead

- **File**: `lib/features/chat/data/chat_repository.dart` — add method:
  ```dart
  Future<void> markAsRead({required String chatId, required String uid}) =>
      _chats.doc(chatId).update({'lastRead.$uid': FieldValue.serverTimestamp()});
  ```
  Dotted path merges only the caller's key. `FieldValue` already imported.
- **Gate**: TASK-05 tests GREEN · `flutter analyze` 0

---

## Group 4 — Application: pure helper + totalUnreadCountProvider (PARALLEL with Group 3, after Group 2)

### TASK-07 [RED] — Tests for chatHasUnread + totalUnreadCountProvider

- **File**: `test/features/chat/application/chat_providers_test.dart` (EXTEND with two new groups)
- **chatHasUnread cases** (7):
  1. Other sender + null lastRead → unread
  2. Other sender + lastRead before lastMessageAt → unread
  3. Other sender + lastRead after lastMessageAt → read
  4. Other sender + lastRead == lastMessageAt → read (equal = read, not strictly after)
  5. Self sender → read regardless of lastRead
  6. `lastMessageAt` null → read (no message yet)
  7. uid key missing from lastRead map → unread
- **totalUnreadCountProvider cases**: 3 chats 2 unread → 2; 0 chats → 0; null uid → 0; provider in loading state → 0; provider in error state → 0.
- **REQ**: REQ-CHATUNREAD-002, -003, -004, -005 (SCENARIOS 002-007)
- **Gate**: RED

### TASK-08 [GREEN] — Implement chatHasUnread + totalUnreadCountProvider

- **File**: `lib/features/chat/application/chat_providers.dart` — append:
  ```dart
  bool chatHasUnread(Chat c, String uid) {
    if (c.lastMessageAt == null) return false;
    if (c.lastMessageSenderId == uid) return false;
    final readAt = c.lastRead?[uid];
    if (readAt == null) return true;
    return c.lastMessageAt!.isAfter(readAt);
  }

  final totalUnreadCountProvider = Provider.autoDispose<int>((ref) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return 0;
    return ref.watch(chatsForCurrentUserProvider).maybeWhen(
      data: (chats) => chats.where((c) => chatHasUnread(c, uid)).length,
      orElse: () => 0,
    );
  });
  ```
  No new imports. Drop `unreadCountForChatProvider` family — use helper directly in rows.
- **Gate**: TASK-07 tests GREEN · `flutter analyze` 0

---

## Group 5 — i18n keys (PARALLEL with Groups 3 and 4, after Group 2)

### TASK-09 — Add i18n keys to all three ARB files + gen-l10n

- **Files** (all three edited; template carries @metadata):
  - `lib/l10n/intl_es_AR.arb`: append `"feedMessagesWithUnreadA11y"` with `@` block (description + `placeholders: {count: {type: int}}`); append `"chatUnreadA11y"` with `@` block.
    - es-AR value: `"Mensajes, {count} sin leer"` / `"Sin leer"`
  - `lib/l10n/intl_es.arb`: same two keys, same values, no `@` metadata.
  - `lib/l10n/intl_en.arb`: `"Messages, {count} unread"` / `"Unread"`.
- Run `flutter gen-l10n` → regenerates `lib/l10n/app_l10n.dart`.
- **REQ**: REQ-CHATUNREAD-009 (SCENARIO-CHATUNREAD-020, -021)
- **Gate**: `flutter analyze` 0 · generated file compiles

---

## Group 6 — Presentation: _ChatRow unread dot (SEQUENTIAL, after Groups 4 + 5)

### TASK-10 [RED] — Tests for _ChatRow unread dot

- **File**: `test/features/chat/presentation/chat_list_screen_test.dart` (EXTEND with new group `_ChatRow unread dot`)
- **Cases**:
  - Chat is unread (other sender, `lastMessageAt` after null-lastRead) → `find.bySemanticsLabel(l10n.chatUnreadA11y)` findsOneWidget
  - Chat is read (other sender, lastRead > lastMessageAt) → findsNothing
  - Self-sent last message → no dot regardless of lastRead state
- Use existing `_wrap` / `_chat` helpers; extend `_chat` factory signature to accept `lastRead` if needed.
- **REQ**: REQ-CHATUNREAD-006, -009 (SCENARIOS 011-013, 021)
- **Gate**: RED

### TASK-11 [GREEN] — Implement unread dot in _ChatRow

- **File**: `lib/features/chat/presentation/chat_list_screen.dart` — in `_ChatRow.build`:
  - Compute `final hasUnread = currentUid.isNotEmpty && chatHasUnread(chat, currentUid);` (import `chatHasUnread` from `chat_providers.dart`).
  - After the timestamp block, append:
    ```dart
    if (hasUnread) ...[
      const SizedBox(width: 10),
      Semantics(
        label: l10n.chatUnreadA11y,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: palette.accent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ]
    ```
  - No number inside the dot — binary indicator only.
- **Gate**: TASK-10 tests GREEN · `flutter analyze` 0

---

## Group 7 — Presentation: feed-header messages badge (SEQUENTIAL, after Groups 4 + 5)

### TASK-12 [RED] — Tests for feed-header messages badge

- **File**: `test/features/feed/presentation/feed_screen_test.dart` (EXTEND with new group `messages badge`)
- **Cases** (override `totalUnreadCountProvider` via `overrideWithValue`):
  - 0 → no badge widget found, Semantics label matches `feedMessagesA11y`
  - 3 → `find.text('3')` findsOneWidget, Semantics label contains `feedMessagesWithUnreadA11y(3)`
  - 150 → `find.text('99+')` findsOneWidget
- **REQ**: REQ-CHATUNREAD-005, -009 (SCENARIOS 008-010, 020)
- **Gate**: RED

### TASK-13 [GREEN] — Implement messages badge in _FeedHeader

- **File**: `lib/features/feed/feed_screen.dart` — in `_FeedHeader.build`:
  - Add `final unreadChats = ref.watch(totalUnreadCountProvider);` (import `totalUnreadCountProvider`).
  - Change the chat icon `Semantics.label` to: `unreadChats > 0 ? l10n.feedMessagesWithUnreadA11y(unreadChats) : l10n.feedMessagesA11y`.
  - Wrap the chat icon `Center` in a `Stack(clipBehavior: Clip.none)` and add:
    ```dart
    if (unreadChats > 0)
      Positioned(
        top: -4,
        right: -5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          constraints: const BoxConstraints(minWidth: 16),
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            unreadChats > 99 ? '99+' : '$unreadChats',
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(fontSize: 10, fontWeight: FontWeight.w700, height: 1.2, color: palette.bg),
          ),
        ),
      ),
    ```
  - Pattern mirrors the existing bell badge exactly (lines 144-178). Cap is 99+ (not 9+ like bell).
- **Gate**: TASK-12 tests GREEN · `flutter analyze` 0

---

## Group 8 — Presentation: ChatScreen mark-as-read (SEQUENTIAL, after Groups 3 + 5)

### TASK-14 [RED] — Tests for ChatScreen mark-as-read behavior

- **File**: `test/features/chat/presentation/chat_screen_test.dart` (EXTEND with new group `mark-as-read`)
- **Setup**: hand-rolled spy class implementing the `markAsRead` method contract; inject via `chatRepositoryProvider.overrideWithValue`; control `messagesProvider(chatId)` via `StreamController<List<Message>>`. No mockito.
- **Cases**:
  1. First frame fires `markAsRead` exactly once (uid='aaa', chatId='aaa_bbb')
  2. New inbound message (sender='bbb') emitted to stream → `markAsRead` called again (total 2)
  3. New message where `sender == uid` ('aaa') emitted → `markAsRead` NOT called again (still 1)
  4. `currentUidProvider` returns null → `markAsRead` never called
- **REQ**: REQ-CHATUNREAD-007 (SCENARIOS 014-016)
- **Gate**: RED

### TASK-15 [GREEN] — Implement mark-as-read in ChatScreen

- **File**: `lib/features/chat/presentation/chat_screen.dart` — already a `ConsumerStatefulWidget`:
  - Add private `void _markAsRead()`: reads `currentUidProvider` (guard null); reads `chatRepositoryProvider`; calls `markAsRead(chatId: widget.chatId, uid: uid)` fire-and-forget (no await, no SnackBar).
  - In `initState`: `WidgetsBinding.instance.addPostFrameCallback((_) => _markAsRead());`.
  - In `build()`, before `return`: `ref.listen(messagesProvider(widget.chatId), (_, next) => next.whenData((msgs) { if (msgs.isEmpty) return; final uid = ref.read(currentUidProvider); if (uid == null) return; if (msgs.first.senderId == uid) return; _markAsRead(); }));` (msgs[0] = newest because orderBy desc).
- **Gate**: TASK-15 tests GREEN · `flutter analyze` 0

---

## Group 9 — Security rule (SEQUENTIAL, standalone)

### TASK-16 — Add lastRead own-key rule to firestore.rules

- **File**: `treino/firestore.rules` — in `match /chats/{chatId}`, extend the `allow update` clause with a 4th AND condition:
  ```
  && ( !request.resource.data.keys().hasAny(['lastRead'])
       || request.resource.data.get('lastRead', {}).diff(resource.data.get('lastRead', {})).affectedKeys().hasOnly([request.auth.uid]) )
  ```
  First branch lets `sendMessage` updates (no `lastRead` key) pass. Second branch: changed keys must be subset of `{caller.uid}`. `.get('lastRead', {})` on both sides is null-safe for legacy docs.
- **REQ**: REQ-CHATUNREAD-008 (SCENARIOS 017-019)
- **Gate**: MANUAL EMULATOR VERIFICATION (not in automated suite — FakeFirebaseFirestore does not enforce rules):
  1. uid-A writes `{ 'lastRead.uid-A': serverTimestamp() }` → **ALLOW**
  2. uid-A writes `{ 'lastRead.uid-B': serverTimestamp() }` → **DENY** (PERMISSION_DENIED)
  3. `sendMessage`-style update (no `lastRead` key) → **ALLOW**
  4. Update modifies `members` field → **DENY** (existing rule still holds)

---

## Group 10 — Quality gate (SEQUENTIAL, after all groups)

### TASK-17 — Full quality gate pass

- `flutter analyze` → 0 issues
- `dart format .` → 0 diff
- `flutter test` → all pre-existing tests still green + all 17 tasks' new tests green
- **REQ**: REQ-CHATUNREAD-010 (SCENARIO-CHATUNREAD-022)

---

## Dependency Graph

```
TASK-01 → TASK-02
               ↓
          TASK-03 → TASK-04
                        ↓
           ┌────────────┼──────────────┐
      TASK-05        TASK-07        TASK-09
      TASK-06        TASK-08         (i18n)
           └────────────┴──────────────┘
                        ↓ (all done)
           ┌────────────┼──────────────┐
      TASK-10       TASK-12        TASK-14
      TASK-11       TASK-13        TASK-15
           └────────────┴──────────────┘
                        ↓
                   TASK-16
                        ↓
                   TASK-17
```

**Parallel opportunities**:
- TASK-05/06 || TASK-07/08 || TASK-09: all unblock after TASK-04
- TASK-10/11 || TASK-12/13 || TASK-14/15: all unblock after Groups 4 + 5

---

## Review Workload Forecast

| Metric | Value |
|--------|-------|
| Estimated new/changed production lines | ~230 |
| Estimated new test lines | ~110 |
| Total estimated lines | ~340 |
| 400-line budget risk | **Low** |
| Chained PRs recommended | **No** |
| Decision needed before apply | **No** |

### Files touched — production

| File | Est. lines |
|------|-----------|
| `lib/features/profile/data/timestamp_converter.dart` | +15 |
| `lib/features/chat/domain/chat.dart` | +2 (+ codegen auto) |
| `lib/features/chat/data/chat_repository.dart` | +4 |
| `lib/features/chat/application/chat_providers.dart` | +18 |
| `lib/features/chat/presentation/chat_list_screen.dart` | +8 |
| `lib/features/feed/feed_screen.dart` | +18 |
| `lib/features/chat/presentation/chat_screen.dart` | +18 |
| `lib/l10n/intl_es_AR.arb` | +10 |
| `lib/l10n/intl_es.arb` | +4 |
| `lib/l10n/intl_en.arb` | +4 |
| `treino/firestore.rules` | +5 |

### Files touched — tests (extend existing)

| File | Est. lines |
|------|-----------|
| `test/features/profile/data/timestamp_converter_test.dart` | +20 |
| `test/features/chat/domain/chat_test.dart` | +25 |
| `test/features/chat/data/chat_repository_test.dart` | +30 |
| `test/features/chat/application/chat_providers_test.dart` | +35 |
| `test/features/chat/presentation/chat_list_screen_test.dart` | +20 |
| `test/features/feed/presentation/feed_screen_test.dart` | +25 |
| `test/features/chat/presentation/chat_screen_test.dart` | +35 |

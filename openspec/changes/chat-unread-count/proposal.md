# Proposal: chat-unread-count

## Problem / Why now

The 1:1 chat is meant to be TREINO's **frequent-use channel** between coach (PF) and athlete. The media layer already shipped (photo + video), but there is still **no signal that a new message arrived**. The feed-header chat icon is a plain icon with no badge, and inbox rows show only the last-message preview — identical whether read or unread.

Without a visible badge, users have no reason to open TREINO to check for messages, so they fall back to WhatsApp and the channel never becomes habitual. A simple, reliable unread indicator closes that loop: a number on the messages icon pulls them into the app, and a per-conversation dot tells them which thread is new.

## Intent

Ship an unread-message indicator for the 1:1 chat:
- A **total unread count badge** on the feed-header messages icon (so the user sees "you have messages" from the feed).
- A **per-conversation dot** in the inbox rows (so the user sees *which* thread is unread once inside).
- Reliable **mark-as-read** when a conversation is opened and when a message arrives while it is open.

Success = a user who receives a message sees the badge without opening the chat, the dot disappears once they read the thread, and their own sent messages never count as unread. All with **zero extra Firestore listeners** and a security rule that prevents one member from tampering with the other's read state.

## In scope

- **Storage**: `lastRead: { uid: Timestamp }` map field on the existing `chats/{chatId}` doc. No new collection, no new listener — the chat doc is already watched.
- **Repository**: `markAsRead(chatId, uid)` on `ChatRepository`, writing `lastRead.$uid = serverTimestamp()` via a keyed field update (does not touch the other member's key).
- **Computation (client-side boolean per chat)**: `hasUnread = lastMessageAt > lastRead[uid] && lastMessageSenderId != uid`. Null `lastRead[uid]` → treated as unread. Derived synchronously from the already-streamed chat list.
- **Providers**:
  - `unreadCountForChatProvider` — boolean (or 0/1) per chat.
  - `totalUnreadCountProvider` — count of chats where `hasUnread` is true, computed in pure Dart over `chatsForCurrentUserProvider`.
- **Mark-as-read triggers** in `ChatScreen`: on open (first frame), and again via `ref.listen(messagesProvider(chatId), …)` when a new message arrives while the screen is mounted.
- **Total number badge** on the feed-header messages icon — reuse the existing bell-badge pattern (`Stack` + `Positioned`, `palette.accent` background, `palette.bg` text, `BorderRadius.circular(8)`), cap at **`99+`**.
- **Per-conversation dot** (a dot, NOT a number) in `ChatListScreen` inbox rows when `hasUnread`.
- **Firestore rule** on `chats` update: a member may modify **only their own** `lastRead` key — `diff().affectedKeys().hasOnly([request.auth.uid])`.
- **i18n**: 2 new a11y keys (es-AR / es / en).
- **Strict-TDD coverage** across data, application, and presentation layers.

## Out of scope (explicit)

- Exact **per-conversation count number** (the dot is intentionally boolean; exact per-thread counts can come later via `count()`).
- **Read receipts** ("visto" / double-check ticks).
- **Typing indicators**.
- **Bottom-tab badge** — would require restructuring `TreinoBottomBar`, disproportionate for this change.
- **Cloud-Function-maintained counters** — the existing `notify-chat-message.ts` is untouched; all computation is client-side.

## Proposed approach

### Storage — map field on the chat doc
Shape: `chats/{chatId}.lastRead: { uid: Timestamp }`. Chosen over a `lastRead` subcollection (extra listeners per chat) and a CF-maintained counter (operationally heavy for an MVP). The chat doc is already streamed by `watchChatsForUser`, so unread state rides along for free.

### Computation — client-side boolean from the existing stream
`hasUnread = lastMessageAt > lastRead[uid] && lastMessageSenderId != uid`. The total badge sums booleans over the existing chat-list stream. No new Firestore query. Self-sent messages are never unread (the sender-id guard), and a missing `lastRead[uid]` (legacy or never-read) resolves to unread.

### Mark-as-read
`ChatRepository.markAsRead(chatId, uid)` issues `chats.doc(chatId).update({'lastRead.$uid': FieldValue.serverTimestamp()})`. The keyed dotted-path update mutates only the caller's entry. `ChatScreen` calls it on first frame and re-calls it from `ref.listen` on each new inbound message while mounted.

### Badge UI — reuse the bell pattern
The bell icon (`feed_screen.dart` lines 144-180) already renders `Stack(clipBehavior: Clip.none)` + `Positioned(top:-4, right:-5)` + `Container(palette.accent, radius 8)` + count text in `palette.bg`, capped `9+`. The messages icon (lines 185-205) is currently a bare `Icon` with no Stack. The change wraps it in the same Stack structure, driven by `totalUnreadCountProvider`, capped **`99+`**. The inbox row gets a small (~8px) `palette.accent` dot when `hasUnread` — no number.

### Security rule
Tighten the `chats` `allow update` to keep `members` + `createdAt` immutable AND restrict `lastRead` mutations to the caller's own key:
```
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
`resource.data.get('lastRead', {})` provides null-safety for legacy docs that have no `lastRead` field yet.

### i18n
Two new a11y strings in `intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb`:
- `feedMessagesWithUnreadA11y(count)` — messages icon label when unread > 0.
- `chatUnreadA11y` — inbox-row dot label.
The existing `feedMessagesA11y` stays for the zero-unread case (mirrors how the bell uses `feedFriendRequestsA11y` vs `feedFriendRequestsWithCountA11y`).

### Freezed map deserialization — DECISION: custom `JsonConverter`
**Recommendation: add a `TimestampMapConverter implements JsonConverter<Map<String, DateTime>, Map<String, Object?>>` and annotate the field `@TimestampMapConverter() Map<String, DateTime>? lastRead`.**

Rationale:
- The codebase **already establishes this pattern**: `lib/features/profile/data/timestamp_converter.dart` defines `TimestampConverter implements JsonConverter<DateTime, Timestamp>`, used on `Chat.createdAt` / `Chat.lastMessageAt`. A `TimestampMapConverter` is the consistent sibling — same file/location, same idiom.
- It keeps the **domain type clean** (`Map<String, DateTime>`), so providers and tests compare real `DateTime`s, not raw `Timestamp`s.
- It centralizes the conversion so `Chat.fromJson` / `toJson` round-trips correctly through `json_serializable`, instead of leaking Firestore types into `_chatFromDoc` (the alternative — manual conversion in `_chatFromDoc` — would special-case one field outside the generated codec and diverge from the existing converter approach).

The converter handles `null`/empty maps and converts each `Timestamp` value via the same `toDate().toUtc()` rule as `TimestampConverter`. Exact converter signature and null-handling to be finalized in the design phase.

## Affected surface (files)

- `lib/features/chat/domain/chat.dart` — add `lastRead` field + `@TimestampMapConverter()`.
- `lib/features/profile/data/timestamp_converter.dart` (or a sibling file) — add `TimestampMapConverter`.
- `lib/features/chat/domain/chat.freezed.dart` + `chat.g.dart` — regenerated via `build_runner`.
- `lib/features/chat/data/chat_repository.dart` — add `markAsRead(chatId, uid)`.
- `lib/features/chat/application/chat_providers.dart` — add `unreadCountForChatProvider`, `totalUnreadCountProvider`.
- `lib/features/chat/presentation/chat_screen.dart` — mark-as-read on open + `ref.listen` on new message.
- `lib/features/chat/presentation/chat_list_screen.dart` — unread dot in `_ChatRow`.
- `lib/features/feed/feed_screen.dart` — badge on messages icon in `_FeedHeader` (mirror bell).
- `firestore.rules` — tighten `chats` update rule (lines ~436-439).
- `lib/l10n/intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb` — 2 new keys.
- Tests: `chat_repository_test`, `chat_providers_test`, `chat_list_screen_test`, `chat_screen_test`, feed-header widget test.

## Risks & mitigations

1. **Firestore rule not unit-testable** — `fake_cloud_firestore` ignores security rules, so `diff().affectedKeys().hasOnly(...)` cannot be covered by the existing `FakeFirebaseFirestore` suite. **Mitigation**: verify manually in the Firebase emulator; do NOT introduce a new test harness for this change. Document the manual check in the verify phase.
2. **Legacy chat docs lack `lastRead`** — on first deploy, any existing thread whose last message was sent by the *other* member appears as unread. **This is correct and desired** (we genuinely don't know the user read it) and clears on first open. Note it so it isn't mistaken for a bug.
3. **`build_runner` regeneration** — `chat.freezed.dart` / `chat.g.dart` must be regenerated after adding the field + converter. Apply phase runs the codegen; quality gate (`flutter analyze` 0) catches stale generated code.

## Success criteria / acceptance

- A user who receives a message sees a count badge on the feed-header messages icon **without opening the chat**; the count caps at `99+`.
- The inbox row for that thread shows an accent dot; opening the thread clears both the dot and (its contribution to) the badge.
- A message the user **sent themselves** never increments any unread indicator.
- A new message arriving **while the chat is open** does not leave the thread marked unread (mark-as-read re-fires via `ref.listen`).
- A member cannot modify the other member's `lastRead` key (enforced by the Firestore rule; verified in emulator).
- No new Firestore listeners are added.
- Quality gate green: `flutter analyze` 0 issues, `dart format .`, `flutter test` passing.

## Test strategy (Strict TDD)

Layered, test-first per the explore plan:
- **Data** (`chat_repository_test`): `markAsRead` writes `lastRead.$uid`; does NOT overwrite the other member's key.
- **Application** (`chat_providers_test`): `unreadCountForChatProvider` true/false from `lastRead` vs `lastMessageAt`; self-sent → always read; null `lastRead` → unread. `totalUnreadCountProvider` = count of unread chats.
- **Presentation** (`chat_screen_test`): `ChatScreen` calls `markAsRead` on mount; `ref.listen` re-fires on new message. (`chat_list_screen_test`) dot visible iff `hasUnread`. (feed-header test) badge visible when total > 0, `99+` cap above 99, no badge at 0.
- **Security rule**: manual emulator verification (out of automated suite — see Risk 1).

## Delivery / size note

Estimated change is **well under 400 lines** and **low risk** (additive field, one repository method, two derived providers, two small UI tweaks reusing an existing pattern, one rule edit, two i18n keys). Delivery strategy `ask-on-risk`: a **single PR is appropriate** — no chained/stacked split needed. The only non-code verification (emulator rule check) is a manual step, not a sizing concern.

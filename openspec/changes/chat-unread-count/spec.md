# Chat Unread Count — Specification

**Change**: chat-unread-count
**Domain**: chat (New Capability)
**Scenario range**: SCENARIO-CHATUNREAD-001..SCENARIO-CHATUNREAD-022

---

## Purpose

Define what the system MUST do to signal unread chat state to users: a numeric badge on the feed-header messages icon and a per-conversation dot in inbox rows. Covers read-state persistence, unread computation logic, mark-as-read trigger, badge/dot display rules, security, accessibility, and non-regression. Does NOT specify implementation details or HOW anything is built.

---

## Requirements

### REQ-CHATUNREAD-001 — Read-state persistence on open

The system MUST record the current authenticated user's read position in `chats/{chatId}` when a conversation is opened. The recorded value MUST reflect the server timestamp at the moment of the write. Writes MUST be scoped to the caller's own key only.

_Testable as_: unit/widget test (data layer)

#### Scenario: SCENARIO-CHATUNREAD-001 — Mark-as-read writes caller's key

- GIVEN a conversation `chatId` exists
- AND the current user's uid is `uid-A`
- WHEN the user opens the conversation
- THEN `chats/{chatId}` contains `lastRead.uid-A` with a server timestamp value
- AND `lastRead.uid-B` (the other member) is unaffected

---

### REQ-CHATUNREAD-002 — Unread definition (boolean per chat)

The system MUST compute a chat as unread for the current user when ALL of the following are true:
1. The chat's `lastMessageAt` is strictly after `lastRead[uid]` for that user, OR `lastRead[uid]` is absent.
2. The chat's `lastMessageSenderId` is NOT equal to the current user's uid.

_Testable as_: unit test (application layer)

#### Scenario: SCENARIO-CHATUNREAD-002 — Last message is newer than lastRead

- GIVEN `lastMessageAt` is `T+10`
- AND `lastRead[uid]` is `T+0`
- AND `lastMessageSenderId` is `uid-B` (not the current user)
- WHEN unread state is computed
- THEN the chat is UNREAD

#### Scenario: SCENARIO-CHATUNREAD-003 — Last message is older than lastRead

- GIVEN `lastMessageAt` is `T+0`
- AND `lastRead[uid]` is `T+10`
- AND `lastMessageSenderId` is `uid-B`
- WHEN unread state is computed
- THEN the chat is READ

#### Scenario: SCENARIO-CHATUNREAD-004 — lastRead exactly equals lastMessageAt

- GIVEN `lastMessageAt == lastRead[uid]` (same timestamp)
- WHEN unread state is computed
- THEN the chat is READ (not strictly after means no unread)

---

### REQ-CHATUNREAD-003 — Own messages never count as unread

The system MUST NOT mark a chat as unread for the sender of the last message, regardless of `lastRead` state.

_Testable as_: unit test (application layer)

#### Scenario: SCENARIO-CHATUNREAD-005 — Sender's chat is always read

- GIVEN `lastMessageSenderId == currentUid`
- AND `lastMessageAt` is after `lastRead[currentUid]`
- WHEN unread state is computed
- THEN the chat is READ

---

### REQ-CHATUNREAD-004 — Legacy chats with no lastRead entry

The system MUST treat a chat as unread for the current user when `lastRead[uid]` is absent AND the last message was sent by the other member (REQ-CHATUNREAD-003 still applies — if the last message is mine, it is read).

_Testable as_: unit test (application layer)

#### Scenario: SCENARIO-CHATUNREAD-006 — No lastRead, other member sent last

- GIVEN `lastRead` map does not contain the current user's uid
- AND `lastMessageSenderId` is `uid-B` (not current user)
- WHEN unread state is computed
- THEN the chat is UNREAD

#### Scenario: SCENARIO-CHATUNREAD-007 — No lastRead, current user sent last

- GIVEN `lastRead` map does not contain the current user's uid
- AND `lastMessageSenderId == currentUid`
- WHEN unread state is computed
- THEN the chat is READ

---

### REQ-CHATUNREAD-005 — Total unread badge on feed-header messages icon

The system MUST display a numeric badge on the feed-header messages icon equal to the count of chats that are unread (per REQ-CHATUNREAD-002). When the count is 0, the badge MUST NOT be shown. When the count exceeds 99, the badge MUST display "99+".

_Testable as_: widget test (presentation layer)

#### Scenario: SCENARIO-CHATUNREAD-008 — Badge shows count when unread > 0

- GIVEN 3 chats are unread for the current user
- WHEN the feed header renders
- THEN the messages icon shows a badge with label "3"

#### Scenario: SCENARIO-CHATUNREAD-009 — Badge absent when count is 0

- GIVEN 0 chats are unread
- WHEN the feed header renders
- THEN no badge widget is present on the messages icon

#### Scenario: SCENARIO-CHATUNREAD-010 — Badge caps at 99+

- GIVEN 100 chats are unread
- WHEN the feed header renders
- THEN the badge label is "99+"

---

### REQ-CHATUNREAD-006 — Per-conversation unread dot in inbox row

The system MUST display a dot indicator on a `_ChatRow` when that chat is unread for the current user. When the chat is read, the dot MUST NOT be shown. The dot MUST NOT display a number — it is a binary presence indicator only.

_Testable as_: widget test (presentation layer)

#### Scenario: SCENARIO-CHATUNREAD-011 — Dot shown for unread chat

- GIVEN a chat is unread for the current user
- WHEN `_ChatRow` renders
- THEN a dot indicator is present in the widget tree

#### Scenario: SCENARIO-CHATUNREAD-012 — Dot absent for read chat

- GIVEN a chat is read for the current user
- WHEN `_ChatRow` renders
- THEN no dot indicator is present in the widget tree

#### Scenario: SCENARIO-CHATUNREAD-013 — Dot contains no text

- GIVEN a chat is unread
- WHEN the dot widget is inspected
- THEN it contains no numeric or text child

---

### REQ-CHATUNREAD-007 — Mark-as-read on open and on new inbound message while open

The system MUST call mark-as-read when the chat screen mounts (first frame). The system MUST also call mark-as-read whenever a new inbound message arrives while the chat screen is mounted, so the thread does not re-badge during an active conversation.

_Testable as_: widget test (presentation layer)

#### Scenario: SCENARIO-CHATUNREAD-014 — Mark-as-read fires on mount

- GIVEN a chat exists with unread messages
- WHEN `ChatScreen` mounts
- THEN mark-as-read is called exactly once for the current user on that chatId

#### Scenario: SCENARIO-CHATUNREAD-015 — Mark-as-read fires on new inbound message while open

- GIVEN `ChatScreen` is mounted and the chat was already marked as read
- WHEN a new message arrives from the other member (messagesProvider emits a new list)
- THEN mark-as-read is called again for the current user on that chatId

#### Scenario: SCENARIO-CHATUNREAD-016 — Mark-as-read does NOT fire for own sent message

- GIVEN `ChatScreen` is mounted
- WHEN the current user sends a message (new message, sender == currentUid)
- THEN mark-as-read is NOT called (own messages are already read per REQ-CHATUNREAD-003)

---

### REQ-CHATUNREAD-008 — Security: a member may only update their own lastRead key

The system MUST reject any Firestore update to `chats/{chatId}` that modifies a `lastRead` key other than the authenticated user's own uid, or that modifies the `members` or `createdAt` fields. This rule MUST be enforced at the Firestore security rules level.

_Testable as_: Firebase Emulator only (not automatable via FakeFirebaseFirestore)

#### Scenario: SCENARIO-CHATUNREAD-017 — Update own lastRead key is accepted

- GIVEN the authenticated user is `uid-A` and is a member of `chatId`
- WHEN the update payload is `{ 'lastRead.uid-A': serverTimestamp() }`
- THEN the write succeeds

#### Scenario: SCENARIO-CHATUNREAD-018 — Update another member's lastRead key is rejected

- GIVEN the authenticated user is `uid-A`
- WHEN the update payload is `{ 'lastRead.uid-B': serverTimestamp() }`
- THEN the write is rejected with PERMISSION_DENIED

#### Scenario: SCENARIO-CHATUNREAD-019 — Update members field is rejected

- GIVEN the authenticated user is `uid-A` and is a member of `chatId`
- WHEN the update payload modifies the `members` field
- THEN the write is rejected with PERMISSION_DENIED

---

### REQ-CHATUNREAD-009 — Accessibility: badge and dot expose meaningful semantics

The messages badge MUST expose a semantic label following the pattern `"{n} mensajes sin leer"` (localized via `AppL10n`). When count is 0 and the badge is absent, the messages icon MUST use the existing zero-count accessibility label. The unread dot in inbox rows MUST expose a semantic label `"Chat sin leer"` (localized via `AppL10n`).

_Testable as_: widget test (presentation layer)

#### Scenario: SCENARIO-CHATUNREAD-020 — Badge exposes count in semantics

- GIVEN the badge shows "3"
- WHEN the semantics tree is inspected
- THEN a `Semantics` node with label containing "3 mensajes sin leer" is present

#### Scenario: SCENARIO-CHATUNREAD-021 — Dot exposes semantic label

- GIVEN a `_ChatRow` renders with an unread dot
- WHEN the semantics tree is inspected
- THEN a `Semantics` node with label "Chat sin leer" is present

---

### REQ-CHATUNREAD-010 — No regression on existing chat behavior

Existing send, receive, and media (photo/video) behavior in `ChatScreen` and `ChatListScreen` MUST continue to function correctly after this change. No new Firestore listeners or collections MUST be introduced. `notify-chat-message.ts` MUST NOT be modified.

_Testable as_: existing test suite (must stay green) + widget test smoke

#### Scenario: SCENARIO-CHATUNREAD-022 — Existing tests remain green

- GIVEN the change is applied
- WHEN `flutter test` is run
- THEN all pre-existing passing tests continue to pass
- AND `flutter analyze` reports 0 issues
- AND `dart format .` produces no diff

---

## Cross-Cutting Constraints

| Constraint | Rule |
|------------|------|
| Colors | `AppPalette.of(context)` only — no hex literals |
| Icons | `TreinoIcon.X` only — no direct `PhosphorIcons.X` |
| Copy / i18n | All user-visible strings via `AppL10n` (2 new keys minimum) |
| Freezed model | `Chat` model changes regenerated via `build_runner` |
| No new listeners | Total Firestore listener count MUST NOT increase |
| Forbidden files | `notify-chat-message.ts` MUST NOT appear in the diff |
| Security rule | Verified manually via Firebase Emulator (not automated suite) |
| Strict TDD | Test file MUST exist in a commit preceding the implementation commit for each new provider and widget change |

---

## Scenario Index

| ID | Summary | REQ | Testable via |
|----|---------|-----|--------------|
| SCENARIO-CHATUNREAD-001 | mark-as-read writes caller key, other key unaffected | REQ-001 | unit |
| SCENARIO-CHATUNREAD-002 | lastMessageAt after lastRead → unread | REQ-002 | unit |
| SCENARIO-CHATUNREAD-003 | lastMessageAt before lastRead → read | REQ-002 | unit |
| SCENARIO-CHATUNREAD-004 | lastMessageAt == lastRead → read | REQ-002 | unit |
| SCENARIO-CHATUNREAD-005 | sender's own chat is always read | REQ-003 | unit |
| SCENARIO-CHATUNREAD-006 | no lastRead, other sender → unread | REQ-004 | unit |
| SCENARIO-CHATUNREAD-007 | no lastRead, self sender → read | REQ-004 | unit |
| SCENARIO-CHATUNREAD-008 | badge shows count > 0 | REQ-005 | widget |
| SCENARIO-CHATUNREAD-009 | badge absent at count 0 | REQ-005 | widget |
| SCENARIO-CHATUNREAD-010 | badge caps at 99+ | REQ-005 | widget |
| SCENARIO-CHATUNREAD-011 | dot shown for unread row | REQ-006 | widget |
| SCENARIO-CHATUNREAD-012 | dot absent for read row | REQ-006 | widget |
| SCENARIO-CHATUNREAD-013 | dot contains no text | REQ-006 | widget |
| SCENARIO-CHATUNREAD-014 | mark-as-read on mount | REQ-007 | widget |
| SCENARIO-CHATUNREAD-015 | mark-as-read on new inbound while open | REQ-007 | widget |
| SCENARIO-CHATUNREAD-016 | mark-as-read NOT fired on own message | REQ-007 | widget |
| SCENARIO-CHATUNREAD-017 | own lastRead update accepted (emulator) | REQ-008 | emulator |
| SCENARIO-CHATUNREAD-018 | other member's lastRead update rejected | REQ-008 | emulator |
| SCENARIO-CHATUNREAD-019 | members field update rejected | REQ-008 | emulator |
| SCENARIO-CHATUNREAD-020 | badge semantics label contains count | REQ-009 | widget |
| SCENARIO-CHATUNREAD-021 | dot semantics label present | REQ-009 | widget |
| SCENARIO-CHATUNREAD-022 | existing tests stay green, analyze 0 | REQ-010 | full suite |

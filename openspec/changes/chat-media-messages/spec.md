# Chat Media Messages — Specification

**Change**: `chat-media-messages`
**Phase**: spec
**Domains**: chat/domain, chat/data, chat/presentation, storage-rules, firestore-rules, push-notification, ios-permissions, i18n

> This is a NEW FULL SPEC — no prior chat-media spec exists.

---

## Purpose

Extend the 1:1 chat to send, store, deliver, and render photo and video messages, making the in-app chat a credible replacement for WhatsApp as the daily PT↔athlete channel.

---

## Requirements

### REQ-CHATMEDIA-001: Message model accepts optional media fields

The `Message` model MUST expose three optional media fields: `@Default('') String text`, `String? mediaUrl`, and `MediaType? mediaType`. A `Message` is valid if and only if `text.isNotEmpty OR (mediaUrl != null AND mediaType != null)`. The `text` field MUST default to `''` (empty string) so media-only messages have a valid Dart shape.

**Testability**: unit (domain layer)

#### Scenario: Media-only message serializes and deserializes correctly

- GIVEN a `Message` JSON with `text: ''`, a valid `mediaUrl`, and `mediaType: 'image'`
- WHEN `Message.fromJson` is called
- THEN the resulting model has `text == ''`, `mediaUrl` non-null, and `mediaType == MediaType.image`
- AND `toJson()` round-trips back to the same JSON

#### Scenario: Caption + media message preserves both fields

- GIVEN a `Message` JSON with non-empty `text`, a valid `mediaUrl`, and `mediaType: 'video'`
- WHEN `Message.fromJson` is called
- THEN both `text` and `mediaUrl` are non-null and non-empty in the model

#### Scenario: Text-only message remains backward compatible

- GIVEN a `Message` JSON with only `text` (no `mediaUrl`, no `mediaType`)
- WHEN `Message.fromJson` is called
- THEN `mediaUrl == null` and `mediaType == null`, and `text` is non-empty

---

### REQ-CHATMEDIA-002: MediaType enum uses established JSON serialization pattern

`MediaType` MUST be an enum with values `image` and `video`, each annotated with `@JsonValue('image')` and `@JsonValue('video')` respectively, following the same snake_case convention as `UserRole`, `Gender`, and `ExperienceLevel`.

**Testability**: unit (domain layer)

#### Scenario: MediaType.image round-trips through JSON

- GIVEN `MediaType.image`
- WHEN serialized to JSON
- THEN the resulting string is `'image'`
- AND deserializing `'image'` yields `MediaType.image`

#### Scenario: MediaType.video round-trips through JSON

- GIVEN `MediaType.video`
- WHEN serialized to JSON
- THEN the resulting string is `'video'`
- AND deserializing `'video'` yields `MediaType.video`

---

### REQ-CHATMEDIA-003: Sending a photo stores the message and updates inbox preview

The `ChatRepository.sendMessage` MUST accept `mediaUrl` and `mediaType` parameters alongside the existing `text` parameter. When `mediaType == MediaType.image` and `text` is empty, the Firestore document MUST be written with the media fields and `lastMessageText` MUST be set to `'📷 Foto'`. When a caption is provided (`text.isNotEmpty`), `lastMessageText` MUST be set to the caption (truncated at 80 chars).

**Testability**: unit/integration (repository layer, `fake_cloud_firestore`)

#### Scenario: Photo-only send writes correct document and preview

- GIVEN an authenticated user who is a member of the chat
- WHEN `sendMessage(text: '', mediaUrl: 'https://...', mediaType: MediaType.image)` is called
- THEN a Firestore message document is written with `mediaUrl`, `mediaType: 'image'`, and `text: ''`
- AND the chat document's `lastMessageText` is updated to `'📷 Foto'`

#### Scenario: Photo with caption writes caption as preview

- GIVEN an authenticated user who is a member of the chat
- WHEN `sendMessage(text: 'Great form!', mediaUrl: 'https://...', mediaType: MediaType.image)` is called
- THEN the chat document's `lastMessageText` is updated to `'Great form!'`

---

### REQ-CHATMEDIA-004: Sending a video stores the message and updates inbox preview

Behavior mirrors REQ-CHATMEDIA-003 for `MediaType.video`. `lastMessageText` for a video-only message MUST be `'🎥 Video'`.

**Testability**: unit/integration (repository layer, `fake_cloud_firestore`)

#### Scenario: Video-only send writes correct document and preview

- GIVEN an authenticated user who is a member of the chat
- WHEN `sendMessage(text: '', mediaUrl: 'https://...', mediaType: MediaType.video)` is called
- THEN a Firestore message document is written with `mediaType: 'video'`
- AND the chat document's `lastMessageText` is updated to `'🎥 Video'`

#### Scenario: Video with caption writes caption as preview

- GIVEN a video send with `text: 'Watch this rep'`
- WHEN `sendMessage` is called
- THEN `lastMessageText` is `'Watch this rep'`

---

### REQ-CHATMEDIA-005: Validation rejects empty text AND null media

The `ChatRepository.sendMessage` MUST throw an `ArgumentError` when both `text` is empty AND `mediaUrl` is null. This preserves the existing invariant that a message must carry meaningful content.

**Testability**: unit (repository layer, `fake_cloud_firestore`)

#### Scenario: Empty text with no media is rejected

- GIVEN a call to `sendMessage(text: '', mediaUrl: null, mediaType: null)`
- WHEN `sendMessage` executes
- THEN an `ArgumentError` is thrown
- AND no Firestore document is written

#### Scenario: Text-only message still passes (regression)

- GIVEN a call to `sendMessage(text: 'Hello', mediaUrl: null, mediaType: null)`
- WHEN `sendMessage` executes
- THEN the document is written with `text: 'Hello'`
- AND no `ArgumentError` is thrown

---

### REQ-CHATMEDIA-006: Firestore rule permits media-only messages from chat members

The Firestore message-create rule MUST be updated to an OR-based validity check: `text.size() > 0 OR (mediaUrl is string AND mediaUrl.size() > 0 AND mediaType is string)`. The existing checks for `senderId == request.auth.uid` and `createdAt is timestamp` MUST remain.

**Testability**: emulator-only (Firestore Rules Emulator; skipped in unit CI)

#### Scenario: Chat member creates a media-only message — permitted

- GIVEN an authenticated user who is a member of the chat
- WHEN a message document is created with `text: ''`, a valid `mediaUrl`, and `mediaType: 'image'`
- THEN the create operation succeeds

#### Scenario: Non-member is denied

- GIVEN an authenticated user who is NOT a member of the chat
- WHEN a message document is created (any payload)
- THEN the create operation is denied

#### Scenario: Empty text and null mediaUrl are denied

- GIVEN an authenticated chat member
- WHEN a message document is created with `text: ''` and no `mediaUrl`
- THEN the create operation is denied

#### Scenario: Missing createdAt is denied

- GIVEN an authenticated chat member with otherwise valid media payload
- WHEN the message document omits `createdAt`
- THEN the create operation is denied

---

### REQ-CHATMEDIA-007: Storage rule permits owner writes with size limits

The `storage.rules` MUST add a `chatMedia/{chatId}/{userId}/{file=**}` block that allows: read to any authenticated user; write only to the authenticated owner (`userId == request.auth.uid`), restricted to `image/*` content types under 15 MB and `video/*` content types under 100 MB.

**Testability**: emulator-only (Firebase Storage Rules Emulator; skipped in unit CI)

#### Scenario: Owner uploads a valid image — permitted

- GIVEN an authenticated user uploading to `chatMedia/{chatId}/{userId}/file.jpg`
- AND the file is `image/jpeg`, size < 15 MB
- WHEN the upload is attempted
- THEN it succeeds

#### Scenario: Owner uploads a valid video — permitted

- GIVEN an authenticated user uploading to `chatMedia/{chatId}/{userId}/file.mp4`
- AND the file is `video/mp4`, size < 100 MB
- WHEN the upload is attempted
- THEN it succeeds

#### Scenario: Non-owner write is denied

- GIVEN a user attempting to write to another user's path (`chatMedia/{chatId}/{otherUserId}/...`)
- WHEN the upload is attempted
- THEN it is denied

#### Scenario: Oversized image is rejected with user-facing error

- GIVEN an authenticated owner uploading an image > 15 MB
- WHEN the upload is attempted
- THEN it is denied by the Storage rule
- AND the UI surfaces a user-facing error (via `AppL10n.chatMediaUploadFailed`)

#### Scenario: Oversized video is rejected with user-facing error

- GIVEN an authenticated owner uploading a video > 100 MB
- WHEN the upload is attempted
- THEN it is denied
- AND the UI surfaces a user-facing error (via `AppL10n.chatMediaUploadFailed`)

---

### REQ-CHATMEDIA-008: Image bubble renders inline with tap-to-fullscreen

The chat message list MUST render a bubble for `MediaType.image` messages that: shows a `CachedNetworkImage` thumbnail inline; displays a loading skeleton while loading; displays an error placeholder with `AppL10n.chatMediaImageLoadError` on failure; opens `PhotoViewerScreen` (fullscreen `InteractiveViewer`) on tap.

**Testability**: widget (presentation layer)

#### Scenario: Image bubble renders thumbnail

- GIVEN a `Message` with `mediaType == MediaType.image` and a valid `mediaUrl`
- WHEN the chat message list renders
- THEN a `CachedNetworkImage` widget is present in the tree

#### Scenario: Tap on image bubble navigates to fullscreen viewer

- GIVEN an image bubble is rendered
- WHEN the user taps it
- THEN navigation pushes `PhotoViewerScreen`

#### Scenario: Caption is shown below the image when present

- GIVEN a `Message` with `mediaType == MediaType.image` and non-empty `text`
- WHEN the bubble renders
- THEN the `text` is displayed below the image

---

### REQ-CHATMEDIA-009: Video bubble renders inline with native player

The chat message list MUST render a bubble for `MediaType.video` messages that shows a `FirebaseStorageVideoPlayer` (the extracted, reused player), with play/pause on tap. Caption is shown below when `text.isNotEmpty`.

**Testability**: widget (presentation layer)

#### Scenario: Video bubble renders the native player

- GIVEN a `Message` with `mediaType == MediaType.video` and a valid `mediaUrl`
- WHEN the chat message list renders
- THEN a `FirebaseStorageVideoPlayer` widget is present in the tree

#### Scenario: Caption is shown below the video when present

- GIVEN a `Message` with `mediaType == MediaType.video` and non-empty `text`
- WHEN the bubble renders
- THEN the `text` is displayed below the player

---

### REQ-CHATMEDIA-010: Composer exposes an attach button and media picker

The `_Composer` widget MUST include an attach button rendered with `TreinoIcon` and colors from `AppPalette`. Tapping it MUST open a bottom sheet with two options labeled via `AppL10n.chatPickImageLabel` and `AppL10n.chatPickVideoLabel`. Tapping either option MUST invoke the platform image/video picker. The send and attach buttons MUST be disabled while an upload is in progress. Upload progress MUST be visible in the composer area.

**Testability**: widget (presentation layer)

#### Scenario: Attach button opens media picker bottom sheet

- GIVEN the `_Composer` is rendered
- WHEN the user taps the attach button
- THEN a bottom sheet appears with options for photo and video

#### Scenario: Controls are disabled during upload

- GIVEN an upload is in progress
- WHEN the composer is rendered
- THEN the send button and attach button are both disabled

#### Scenario: Upload failure shows error snackbar

- GIVEN an upload that fails
- WHEN the error occurs
- THEN a snackbar with `AppL10n.chatMediaUploadFailed` is shown
- AND the composer controls are re-enabled

---

### REQ-CHATMEDIA-011: Inbox preview shows media type label for media-only messages

The `Chat.lastMessageText` value MUST be `'📷 Foto'` for image-only messages and `'🎥 Video'` for video-only messages. When a caption is present, the caption (truncated at 80 chars) MUST be used instead. `ChatListScreen` requires no code change — it already renders `lastMessageText` verbatim.

**Testability**: unit/integration (repository layer)

#### Scenario: Media-only image shows photo label in inbox

- GIVEN `watchMessages` returns a message stream including a media-only image message
- WHEN the inbox list renders
- THEN `lastMessageText` for that chat is `'📷 Foto'`

#### Scenario: Media-only video shows video label in inbox

- GIVEN a video-only message
- WHEN lastMessageText is read
- THEN it equals `'🎥 Video'`

#### Scenario: Caption wins over media label

- GIVEN a photo message with `text: 'Check this'`
- WHEN lastMessageText is set
- THEN it equals `'Check this'` (not `'📷 Foto'`)

---

### REQ-CHATMEDIA-012: Push notification body reflects media type

The `notify-chat-message.ts` cloud function MUST produce a notification body of `'📷 Foto'` for image-only messages and `'🎥 Video'` for video-only messages when `text` is empty. When `text` is non-empty, the body MUST be the caption (truncated at 100 chars). An unknown or missing `mediaType` with empty text MUST produce a non-crashing degenerate string (empty string acceptable).

**Testability**: unit (Jest, cloud function layer)

#### Scenario: Image-only push body

- GIVEN a Firestore message document with `text: ''` and `mediaType: 'image'`
- WHEN `notify-chat-message` fires
- THEN the notification body is `'Sender: 📷 Foto'`

#### Scenario: Video-only push body

- GIVEN `text: ''` and `mediaType: 'video'`
- WHEN the function fires
- THEN the notification body is `'Sender: 🎥 Video'`

#### Scenario: Caption used instead of media label

- GIVEN `text: 'Look at this!'` and a valid `mediaType`
- WHEN the function fires
- THEN the body is `'Sender: Look at this!'`

#### Scenario: Unknown mediaType does not crash

- GIVEN `text: ''` and `mediaType: 'unknown'`
- WHEN the function fires
- THEN the function completes without throwing
- AND the body does not expose a crash or exception

---

### REQ-CHATMEDIA-013: iOS permission keys present before first picker invocation

`ios/Runner/Info.plist` MUST contain both `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` keys with non-empty usage description strings before any picker call is made. Absence of either key causes a crash on first picker invocation on iOS.

**Testability**: manual / static verification (no emulator test possible for plist keys)

#### Scenario: Photo library picker does not crash on first use (iOS)

- GIVEN the app is installed on an iOS device without prior camera/photo permissions granted
- WHEN the user taps the attach button and selects the photo option
- THEN the OS permission prompt appears
- AND the app does not crash

#### Scenario: Camera picker does not crash on first use (iOS)

- GIVEN the same initial state as above
- WHEN the user taps the attach button and selects the video option (which may invoke camera)
- THEN the OS permission prompt appears
- AND the app does not crash

---

### REQ-CHATMEDIA-014: i18n keys present in all supported locales

The following 9 keys MUST be present in `intl_es_AR.arb`, `intl_es.arb`, and `intl_en.arb` with non-empty values: `chatAttachMediaLabel`, `chatPickImageLabel`, `chatPickVideoLabel`, `chatMediaUploading`, `chatMediaUploadFailed`, `chatMediaPreviewPhoto`, `chatMediaPreviewVideo`, `chatMediaViewFullscreen`, `chatMediaImageLoadError`. All UI strings in this feature MUST be sourced from `AppL10n`; no hardcoded strings are permitted.

**Testability**: static (lint / golden comparison); widget tests use localized labels

#### Scenario: All keys resolve in es-AR locale

- GIVEN the app locale is `es-AR`
- WHEN any media-composer or bubble string is accessed via `AppL10n`
- THEN the resolved string is non-empty and matches the ARB definition

---

### REQ-CHATMEDIA-015: Text-only message behavior is fully preserved (regression)

All existing text-only chat behavior MUST function identically after this change. Sending a text message, receiving it, rendering it in a bubble, and displaying the inbox preview MUST produce the same results as before.

**Testability**: unit/integration/widget (all layers — regression suite)

#### Scenario: Existing text-only send is unchanged

- GIVEN a call to `sendMessage(text: 'Hello', mediaUrl: null, mediaType: null)`
- WHEN `sendMessage` executes
- THEN the document is written and `lastMessageText` is `'Hello'`
- AND the bubble renders the text without any media widget

---

## Requirement Summary Table

| ID | Area | Testability |
|----|------|-------------|
| REQ-CHATMEDIA-001 | Message model — optional media fields | unit |
| REQ-CHATMEDIA-002 | MediaType enum serialization | unit |
| REQ-CHATMEDIA-003 | Repository — send photo | unit/integration |
| REQ-CHATMEDIA-004 | Repository — send video | unit/integration |
| REQ-CHATMEDIA-005 | Validation — empty+no-media rejected | unit |
| REQ-CHATMEDIA-006 | Firestore rule — media-only permitted | emulator-only |
| REQ-CHATMEDIA-007 | Storage rule — owner-write, size limits | emulator-only |
| REQ-CHATMEDIA-008 | Image bubble — inline + fullscreen | widget |
| REQ-CHATMEDIA-009 | Video bubble — inline native player | widget |
| REQ-CHATMEDIA-010 | Composer — attach, progress, errors | widget |
| REQ-CHATMEDIA-011 | Inbox preview — media type labels | unit/integration |
| REQ-CHATMEDIA-012 | Push notification — media body | unit (Jest) |
| REQ-CHATMEDIA-013 | iOS permissions — no picker crash | manual/static |
| REQ-CHATMEDIA-014 | i18n — 9 keys in 3 locales | static/widget |
| REQ-CHATMEDIA-015 | Regression — text-only unchanged | all layers |

## Out of Scope

Unread-count badges, read receipts, typing indicators, audio/voice messages, file/document attachments, group chats, inline YouTube, server-side compression/thumbnails, optimistic send placeholders.

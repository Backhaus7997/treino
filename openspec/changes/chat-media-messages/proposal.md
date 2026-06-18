# Proposal: chat-media-messages

## Problem / Why now

PT research is unambiguous: an in-app chat is a must-have, and today the internal 1:1 chat is **text-only**. That gap is the single reason PTs and athletes still fall back to WhatsApp for the daily relationship — and the daily exchange between them is overwhelmingly **photos and videos**: form-check clips, progress pictures, exercise demos, "is this the right setup?" snapshots. A chat that cannot carry media is not a real replacement for WhatsApp; it is a notification channel.

If TREINO is going to own the PT↔athlete channel (and keep that engagement inside the product instead of leaking it to a third-party app), the chat has to carry photo and video natively. This is the highest-leverage gap between "we have a chat" and "the chat replaces WhatsApp."

The current architecture actively blocks media in three places:
- `Message.text` is a **required non-nullable `String`** — a media-only message has no valid shape.
- The Firestore message-create rule hard-requires `text.size() > 0` — any media-only message is rejected **server-side**.
- There is no `chatMedia/` Storage path and no upload path in `ChatRepository`.

## Intent

Make the existing 1:1 chat able to **send, store, deliver, and render photo and video** end to end — model, persistence, security rules, upload, inline rendering, inbox preview, and push notification — so it can credibly replace WhatsApp as the daily PT↔athlete channel. Reuse the media infrastructure the app already has (`image_picker`, `video_player`, `firebase_storage`, `CachedNetworkImage`, the existing native Storage video card) rather than introduce new dependencies or new patterns.

Success looks like: an athlete picks a photo or a short video from their gallery, sees upload progress, and the PT receives it inline in the conversation, sees a correct inbox preview ("📷 Foto" / "🎥 Video"), and gets a push notification whose body reflects the media — with full Strict-TDD coverage and a green quality gate.

## In scope

- **Send** photo and video in the 1:1 chat (gallery pick via `image_picker`, `imageQuality: 80`).
- **Receive / render inline**: images render inline in the bubble with a tap-to-open fullscreen viewer (`InteractiveViewer`); videos render via the reused native Firebase Storage player.
- **Optional caption**: a media message may carry text; a text message may carry no media (backward compatible).
- **Inbox preview**: `lastMessageText` shows "📷 Foto" / "🎥 Video" for media-only messages.
- **Push notification**: `notify-chat-message.ts` body reflects media when there is no caption.
- **Security rules**: Firestore message-create rule and Storage rules updated to permit and bound media.
- **i18n**: new keys in es-AR / es / en for the composer, progress, and error states.
- **Strict-TDD coverage** across the five layers (domain, repository, rules, presentation, cloud function).

## Out of scope (explicit)

- **Unread-count badges** — separate future change.
- Read receipts / typing indicators.
- Audio / voice messages.
- File / document attachments (PDF, etc.).
- Group chats (1:1 only).
- Inline YouTube playback inside chat.
- Server-side video compression, transcoding, or thumbnail generation.
- Optimistic send / local placeholder bubbles (decided: upload-then-send).

## Proposed approach

The approach is deliberately conservative: extend the existing flat model, reuse existing infra, add the minimum new surface. Grouped by concern:

### 1. Model + rules

- **Message model** stays flat (Decision 1, Option A): add `@Default('') String text`, `String? mediaUrl`, `MediaType? mediaType`. A message is valid iff `text.isNotEmpty || (mediaUrl != null && mediaType != null)`. Rationale: a two-field nested object is premature and a sealed-union discriminator would break every existing test and call site for no MVP benefit. Validation lives in the repository and the Firestore rule, not the model.
- **`MediaType` enum** (`image` | `video`) in `lib/features/chat/domain/media_type.dart`, using the project's established `@JsonValue('snake_case')` per-value convention (same as `UserRole`, `Gender`, `ExperienceLevel`). Stored in Firestore as the serialized string.
- **Firestore message-create rule** becomes OR-based: keep `senderId == request.auth.uid` and `createdAt is timestamp`, and require `text.size() > 0 OR (mediaUrl is string && mediaUrl.size() > 0 && mediaType is string)`. Firestore rules can only assert `is string` on `mediaType`, so server-side validity is structural, not enum-exhaustive.

### 2. Storage + upload

- **New `ChatMediaUploadService`** (`lib/features/chat/data/chat_media_upload_service.dart`), mirroring the proven `CustomExerciseVideoUploadService` structure: resolve uid, build path, `putFile`, stream progress via `snapshotEvents`, return `getDownloadURL()`. Path: `chatMedia/{chatId}/{senderUid}/{microtimestamp}.{ext}`. A dedicated service (not a forced generalization of the video-only workout uploader) keeps zero coupling with the workout feature and makes `chatId` a natural scoping parameter. Reuse the existing top-level `extractFirebaseStoragePath` helper for any future cleanup.
- **Storage rules** add a `chatMedia/{chatId}/{userId}/{file=**}` block: **authed-read, owner-write**, with `image/.*` < 15 MB and `video/.*` < 100 MB. Rationale and tradeoff (documented in the rules file): Storage rules **cannot** call `get()` on Firestore, so chat-membership cannot be enforced at the Storage layer. The path's `chatId` is organizational, not a security boundary. The actual access control is the non-guessable `?token=` in the download URL — the same posture already shipped for `customExerciseVideos`. Acceptable for an MVP PT↔athlete chat; called out as a known tradeoff.

### 3. UI render + composer

- **Extract the native Storage video card**: the private `_NativeVideoCard` in `lib/features/workout/presentation/widgets/exercise_video_player.dart` becomes a public `FirebaseStorageVideoPlayer` in `lib/core/widgets/firebase_storage_video_player.dart` (mechanical move + import update), then reused for chat video bubbles. This avoids reimplementing initialization, play/pause, scrubber, and error states.
- **Images**: inline bubble via `CachedNetworkImage` (already a dep), tap → fullscreen `PhotoViewerScreen` with `InteractiveViewer` (Flutter SDK, no new dep). Loading skeleton + error placeholder.
- **`_Bubble`** branches on `message.mediaType`: image → `chat_image_bubble.dart`, video → `chat_video_bubble.dart`, with caption text rendered below when `text.isNotEmpty`. Text-only path is unchanged.
- **`_Composer`** gains an attach button (`TreinoIcon.X`, no Phosphor direct) opening a bottom sheet (Foto / Video). **Send UX = upload-then-send** (Decision 6): show upload progress in the composer; on completion the message appears via the existing Firestore stream. No optimistic placeholder, no rollback logic — disproportionate for MVP. Send/attach disabled while uploading. Errors surface as a snackbar.
- All UI strings via `AppL10n`; all colors via `AppPalette.of(context)`.

### 4. Preview + push

- **Inbox preview**: `ChatRepository` sets `lastMessageText` to `'📷 Foto'` / `'🎥 Video'` for media-only messages (caption wins when present). These are repository string constants matching the ARB values. No `Chat` model change and no `ChatListScreen` change needed (it already renders `lastMessageText` verbatim).
- **Push body**: `notify-chat-message.ts` gains a `mediaType` fallback — `displayText = text.length > 0 ? truncate(text, 100) : (mediaType === 'image' ? '📷 Foto' : mediaType === 'video' ? '🎥 Video' : '')`. The degenerate unknown-mediaType case yields `"Sender: "` (not a crash).

### 5. i18n

- 9 new keys across `intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb`: `chatAttachMediaLabel`, `chatPickImageLabel`, `chatPickVideoLabel`, `chatMediaUploading`, `chatMediaUploadFailed`, `chatMediaPreviewPhoto`, `chatMediaPreviewVideo`, `chatMediaViewFullscreen`, `chatMediaImageLoadError`.

### 6. iOS permissions

- Add `NSCameraUsageDescription` + `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`. Text-only chat never needed these; without them the app **crashes on first picker open**. Verify/add at apply time.

## Affected surface (files)

**New (~7 source + tests):**
- `lib/features/chat/domain/media_type.dart`
- `lib/features/chat/data/chat_media_upload_service.dart`
- `lib/core/widgets/firebase_storage_video_player.dart` (extracted)
- `lib/features/chat/presentation/widgets/chat_image_bubble.dart`
- `lib/features/chat/presentation/widgets/chat_video_bubble.dart`
- `lib/features/chat/presentation/screens/photo_viewer_screen.dart`
- plus test files across the 5 layers (domain, repository, upload service, widgets, composer, cloud function).

**Modified (~6 source):**
- `lib/features/chat/domain/message.dart`
- `lib/features/chat/data/chat_repository.dart`
- `lib/features/chat/presentation/chat_screen.dart`
- `firestore.rules`
- `storage.rules`
- `functions/src/notifications/notify-chat-message.ts`
- `lib/l10n/intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb`
- `ios/Runner/Info.plist`
- `lib/features/workout/presentation/widgets/exercise_video_player.dart` (import update after extraction)

**Zero new runtime dependencies** — `image_picker`, `video_player`, `firebase_storage`, `cached_network_image` are all already present.

## Risks & mitigations

1. **iOS picker crash (high impact, easy fix)** — missing `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` crashes on first picker. Mitigation: add both to `Info.plist`; treat as a blocking apply-time task, not optional.
2. **Storage read-access tradeoff** — authed-read + token obscurity, no membership enforcement possible at the Storage layer. Mitigation: document explicitly in `storage.rules`; size + contentType allowlist; same posture as already-shipped `customExerciseVideos`. Accepted for MVP.
3. **Firestore rule only testable via emulator** — `fake_cloud_firestore` ignores security rules. Mitigation: rule scenarios go in emulator-only tests (existing pattern), kept separate from the unit suite so CI stays green without an emulator.
4. **Video player extraction regression** — moving `_NativeVideoCard` out of the workout feature could regress exercise video rendering. Mitigation: purely mechanical extraction + import update; verify exercise video playback still works (note: existing exercise-player tests are thin — a coverage gap to flag).
5. **es-AR preview literal stored in Firestore** — `'📷 Foto'` / `'🎥 Video'` is persisted as an es-AR literal in `lastMessageText`. Acceptable for Argentina-only MVP. Future i18n: derive the preview from `mediaType` at render time instead of storing the localized string.
6. **Large gallery videos** — the 100 MB cap can be hit by long clips. Mitigation: surface a clear error (e.g. on `firebase_storage/quota-exceeded` or rule rejection); document the limit. No transcoding in MVP.

## Success criteria / acceptance

- An athlete or PT can pick a **photo** or a **video** from the gallery and send it in a 1:1 chat; upload progress is visible; on completion the message appears in the conversation.
- **Images** render inline and open fullscreen on tap; **videos** play inline via the reused native player.
- A **media-only** message (empty text) is accepted by the Firestore rule and renders correctly; a **caption + media** message stores and renders both.
- The **inbox preview** shows "📷 Foto" / "🎥 Video" for media-only messages and the caption when present.
- The **push notification** body reflects media for media-only messages and the caption otherwise.
- Text-only messages behave **exactly as before** (full backward compatibility).
- Quality gate green: `flutter analyze` 0 issues, `dart format .` clean, `flutter test` passing; Jest tests for the cloud function passing.

## Test strategy (Strict TDD — 5 layers)

Tests written before production code (Red → Green → Refactor):
1. **Domain** — `MediaType` `@JsonValue` round-trips; `Message` with/without media fromJson/toJson, including empty-text + mediaUrl and caption + media.
2. **Repository** (`fake_cloud_firestore`) — media send writes correct doc and `lastMessageText`; image vs video preview; caption + media; empty-text + null-media still throws `ArgumentError`; `watchMessages` surfaces media fields; text-only regression.
3. **Firestore rules** (emulator-only, skipped in unit CI) — member media-only permitted; non-member denied; empty-text + null-media denied; missing `createdAt` denied.
4. **Presentation** — image bubble renders + tap navigates; video bubble renders the reused player; caption visibility; composer attach button + bottom sheet; send/attach disabled while uploading.
5. **Cloud function** (Jest) — media-only image → "Sender: 📷 Foto"; media-only video → "🎥 Video"; caption + media → caption body; unknown mediaType → degenerate non-crash.

## Open questions

- **Single vs chained PR** — see delivery note. The user prefers a single PR; the size note flags the budget risk for the tasks-phase decision. No blocking question for the spec/design phases.
- No other blocking unknowns: all nine decisions are resolved in the exploration.

## Delivery / size note

Rough size from the exploration: **~6 modified + ~7 new source files** plus their test files across 5 layers, 3 ARB files, 2 rules files, 1 cloud function, and `Info.plist`. Counting tests, this comfortably **exceeds the ~400-line review budget** — likely well into the 600–900 changed-line range. Delivery strategy is **ask-on-risk**, and the user has stated a preference for a **single PR** for the photo+video work. Recommendation for the orchestrator at the tasks phase: confirm the single-PR choice and record a `size:exception`, or split along the natural seam (model + rules + repository + upload as PR-1; UI render + composer + preview + push + i18n + iOS as PR-2) if a maintainer prefers chained PRs. This is a delivery decision, not a scope decision — the scope above is locked either way.

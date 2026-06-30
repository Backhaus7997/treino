# Exploration: chat-media-messages

## Current State

### Domain layer
`lib/features/chat/domain/message.dart` (lines 13–23): `Message` is a simple freezed model with four required fields — `id`, `senderId`, `text` (required `String`), `createdAt`. No nullable fields, no discriminator. `text` being `required String` (not nullable) is the central blocker for media-only messages.

`lib/features/chat/domain/chat.dart` (lines 14–25): `Chat` carries `lastMessageText` (nullable `String?`) and `lastMessageSenderId` / `lastMessageAt`. The `lastMessageText` field is shown verbatim in `ChatListScreen` — changing it to "📷 Foto" for media messages requires no Chat model change, only a `_previewOf` tweak in the repository.

### Data layer
`lib/features/chat/data/chat_repository.dart`:
- `sendMessage` (lines 80–105): writes text, sets `lastMessageText = _previewOf(trimmed)`, hard-rejects `trimmed.isEmpty`.
- `_previewOf` (lines 161–164): 80-char truncation. Works for text strings; needs extension for "📷 Foto" / "🎥 Video".
- No upload logic; no `mediaUrl` field in any write path.

### Firestore rules (firestore.rules lines 450–456)
```
allow create: if ... && request.resource.data.text is string
                       && request.resource.data.text.size() > 0
                       && request.resource.data.createdAt is timestamp;
```
`text.size() > 0` is an absolute blocker for media-only messages. ANY media message with `text = ""` is rejected server-side. Rule change is mandatory.

### Storage rules (storage.rules)
Current paths: `/avatars/`, `/temp/uploads/{uid}/`, `/customExerciseVideos/{uid}/`. All are user-scoped (owner-write) with authed-read. There is no `chatMedia/` path — it must be added.

### Upload service
`lib/features/workout/data/custom_exercise_video_upload_service.dart`: uploads to `customExerciseVideos/{uid}/{timestamp}.{ext}`, returns download URL. Pattern is: get uid from FirebaseAuth, build path, `putFile`, listen `snapshotEvents` for progress, return `getDownloadURL()`. Also has `deleteByDownloadUrl` which uses `extractFirebaseStoragePath` from `exercise_video_player.dart` — a useful top-level helper we can reuse.

### Presentation layer
`lib/features/chat/presentation/chat_screen.dart`:
- `_Composer` (lines 240–306): a `TextField` with a send `IconButton` only. No attach button, no media preview.
- `_Bubble` (lines 194–238): renders `message.text` as a `Text` widget. Fully text-only.
- `_onSend` (lines 44–79): calls `repo.sendMessage(text: text)`, guards `text.isEmpty`.

`lib/features/chat/presentation/chat_list_screen.dart` (line 137): `chat.lastMessageText ?? l10n.chatListStartConversation` — no special media handling needed if preview is a string like "📷 Foto".

### Existing video/image infrastructure
`lib/features/workout/presentation/widgets/exercise_video_player.dart`: `_NativeVideoCard` is a full StatefulWidget that initializes `VideoPlayerController.networkUrl`, shows progress while loading, plays/pauses on tap, has a scrubber. It is Firebase-Storage-URL-aware via `isFirebaseStorageVideo()`. The `_PlayOverlay` widget is public. `extractFirebaseStoragePath` is a top-level function (exported). Can be reused directly in chat video bubbles.

`pubspec.yaml`: `image_picker: ^1.1.2`, `video_player: ^2.9.0`, `file_picker: ^8.1.2`, `firebase_storage: ^12.3.0` — all already present. **Zero new runtime deps needed.**

### Push notifications
`functions/src/notifications/notify-chat-message.ts` (lines 54–56):
```ts
const text = (messageData.text as string | undefined) ?? "";
...
const body = `${senderName}: ${truncate(text, 100)}`;
```
If `text` is `""` (media-only), body becomes `"Sender Name: "` — an empty suffix that looks broken. Needs a media-type fallback label.

### Existing tests
- `test/features/chat/domain/message_test.dart` — freezed JSON round-trips + Timestamp deserialization
- `test/features/chat/domain/chat_test.dart` — Chat JSON round-trips
- `test/features/chat/data/chat_repository_test.dart` — `fake_cloud_firestore`, covers `sendMessage`, `watchMessages`, `getOrCreate`, `watchChatsForUser`
- `test/features/chat/application/chat_providers_test.dart` — Riverpod `ProviderContainer` overrides + `fake_cloud_firestore`
- `test/features/chat/presentation/widgets/chat_deleted_user_test.dart` — `TestAppWrapper` + provider overrides, widget test style
- `functions/src/__tests__/notify-chat-message.test.ts` — Jest, `notifyOnChatMessageHandler` extracted as a pure function for testability

---

## Decision Analysis

### Decision 1: Message model shape

**Option A — Optional fields: `String? mediaUrl` + `MediaType? mediaType` enum**
- `text` becomes `String` with a default of `''` (or stays `required` but the `sendMessage` signature accepts `null`).
- Validity: `text.isNotEmpty || (mediaUrl != null && mediaType != null)`.
- Firestore document: `text` field always present (empty string for media-only), `mediaUrl` and `mediaType` conditionally present.
- Pros: minimal diff from current shape, easy to understand, easy partial display (caption + media), no discriminator union complexity, straightforward JSON serialization.
- Cons: nothing prevents an invalid state (no text AND no media) at the model level; downstream code must guard.
- Effort: Low.

**Option B — Nested `ChatMedia` object: `ChatMedia? media`**
- `Message` gets `ChatMedia? media` with `url` and `type`.
- `text` stays required `String` (for media-only, caller passes `""`).
- Pros: groups media fields cleanly, extensible (thumbnailUrl, dimensions, duration).
- Cons: extra level in JSON; `text` stays a required field which is misleading for media-only messages; overkill for two fields.
- Effort: Low-Medium (extra class + json_serializable setup).

**Option C — Message `kind` discriminator (sealed class / union)**
- `Message` becomes an abstract sealed class with `TextMessage` and `MediaMessage` variants (or a `kind` enum field).
- Pros: explicit, type-safe at compile time, impossible invalid state.
- Cons: large refactor; `watchMessages` returns `List<Message>` — callers everywhere need exhaustive switches; freezed union syntax with multiple factories is heavier; all existing tests break.
- Effort: High.

**Recommendation: Option A.**
Two optional fields (`mediaUrl`, `mediaType`) are sufficient for MVP. Nest the validation in the repository and the Firestore rule. The sealed-class approach is architecturally pure but disproportionate to the scope and breaks every existing test and call site. We can always migrate to a union later if the message kinds multiply.

`text` should change to default `''` rather than `required`, or alternatively the factory keeps it required but `sendMessage` is overloaded — keeping it required-with-default is cleanest for freezed. Recommended:

```dart
@Default('') String text,   // empty string is valid iff mediaUrl != null
String? mediaUrl,
MediaType? mediaType,       // enum: image | video
```

`MediaType` enum file: `lib/features/chat/domain/media_type.dart`.

---

### Decision 2: Upload service

**Option A — New `ChatMediaUploadService` (separate class)**
- Mirrors `CustomExerciseVideoUploadService` structure exactly but targets `chatMedia/{chatId}/{uid}/{timestamp}.{ext}`.
- Pros: zero coupling with workout feature; clear ownership; `chatId` is a natural scoping parameter.
- Cons: duplicates ~50 lines of upload logic.
- Effort: Low.

**Option B — Generalize existing service into `MediaUploadService`**
- Extract a base `MediaUploadService` with configurable path-builder; `CustomExerciseVideoUploadService` and `ChatMediaUploadService` either subclass or delegate to it.
- Pros: DRY.
- Cons: adds indirection to an already-working service; the workout upload is video-only, chat upload needs to handle images too (different contentType check); forced generalization is premature.
- Effort: Medium.

**Recommendation: Option A.**
A dedicated `ChatMediaUploadService` in `lib/features/chat/data/chat_media_upload_service.dart`. It handles both images (JPEG/PNG/HEIC/WEBP) and videos (MP4/MOV/M4V). Storage path: `chatMedia/{chatId}/{senderUid}/{microtimestamp}.{ext}`. The chatId in the path is purely organizational (no security value against Firestore checks — see Decision 3). Reuse `extractFirebaseStoragePath` from `exercise_video_player.dart` (already a top-level exported function) for any future cleanup.

---

### Decision 3: Storage rules — read access model

**Option A — Authed-read (same as `customExerciseVideos`)**
```
match /chatMedia/{chatId}/{userId}/{file=**} {
  allow read: if request.auth != null;
  allow write: if request.auth != null && request.auth.uid == userId
               && request.resource.size < 15 * 1024 * 1024
               && request.resource.contentType.matches('(image|video)/.*');
}
```
- Pros: simple; works without cross-service Firestore calls in Storage rules (which are unsupported in Storage rules — unlike Firestore rules, Storage rules cannot call `get()` on Firestore docs).
- Cons: any authenticated user can read any chat media if they know or guess the URL. In practice, Firebase Storage download URLs contain a non-guessable token (`?token=...`), which provides obscurity but not true access control.
- Effort: Low.

**Option B — Path-encoded owner-only write, authed-read with URL obscurity**
Same as Option A. The "path-encoded scoping" idea — e.g. encoding `{chatId}` in the path and trying to verify membership — **is not possible in Firebase Storage rules**, which have no `get()` function for Firestore. The path can be encoded for organizational reasons but provides zero security value.

**The real security model:** Firebase Storage download URLs contain a `?token=` query parameter that makes them functionally unguessable (128-bit random UUID). The risk is an authenticated-but-not-a-member user who somehow obtains the URL (e.g. log exposure). This is the same risk as `customExerciseVideos`. For a PT↔athlete chat, this is an acceptable tradeoff for MVP.

**Recommendation: Option A — authed-read, owner-write, with size + contentType allowlist.**
- Images: `< 15 MB`, `image/.*`
- Videos: `< 100 MB`, `video/.*`
- Document both limitations explicitly in the rules file.

---

### Decision 4: Firestore message-create rule

Current rule (lines 454–456):
```
&& request.resource.data.text is string
&& request.resource.data.text.size() > 0
```

New rule — allow text-only OR media-only OR both:
```
&& request.resource.data.text is string
&& request.resource.data.createdAt is timestamp
&& request.resource.data.senderId == request.auth.uid
&& (request.resource.data.text.size() > 0
    || (request.resource.data.mediaUrl is string
        && request.resource.data.mediaUrl.size() > 0
        && request.resource.data.mediaType is string))
```

The `mediaType` is stored as a string (the enum's serialized value: `"image"` or `"video"`) — Firestore rules can only check `is string`. The `mediaUrl.size() > 0` guard prevents empty-URL media messages. Keep `senderId == request.auth.uid` explicit (already in existing rule).

**Recommendation:** Adopt the OR-based rule above. Keep it in `firestore.rules` near line 450.

---

### Decision 5: Rendering in chat bubbles

**Images:**
- Inline bubble with `CachedNetworkImage` (already a dep, used in `_YoutubeThumbCard`). Tap → push a full-screen `PhotoViewerScreen` (needs to be created). Use `InteractiveViewer` — it's in the Flutter SDK, no new dep.
- Loading: `CircularProgressIndicator` inside the bubble until image loads (same pattern as `_NativeVideoCard` loading skeleton).
- Error: a small placeholder icon with `TreinoIcon.image` (check if that icon exists, else `TreinoIcon.camera` or similar).

**Videos:**
- Reuse `_NativeVideoCard` from `exercise_video_player.dart` inside the bubble. It already handles initialization, play/pause, scrubber, error state.
- Note: `_NativeVideoCard` is a private class. Two options: (a) make it public by extracting to a separate widget, or (b) reference `ExerciseVideoPlayer` widget with the URL — but `ExerciseVideoPlayer` also handles YouTube and shows a different UI. Recommended: extract `_NativeVideoCard` as a public `FirebaseStorageVideoPlayer` widget in a new shared file `lib/core/widgets/firebase_storage_video_player.dart`.
- Aspect ratio in a chat bubble: constrain with `ConstrainedBox(maxWidth: 0.75 * screenWidth)` + `AspectRatio(16/9)` — matching the existing `_Bubble` maxWidth constraint.

**`_Bubble` changes:**
`_Bubble` must branch: if `message.mediaUrl != null` → render `_ImageBubble` or `_VideoBubble`; render caption text below if `text.isNotEmpty`. If text-only (current behavior), nothing changes.

---

### Decision 6: Send UX — upload-then-send vs optimistic

**Option A — Upload-then-send (blocking progress)**
Pick file → show upload progress in composer (CircularProgressIndicator with fraction) → on 100% → call `sendMessage` → message appears in list.
- Pros: no complex optimistic state; no rollback needed; message in Firestore is always consistent with uploaded file.
- Cons: user sees no bubble until upload finishes (can be slow on 3G); tap-away during upload is awkward.
- Effort: Low.

**Option B — Optimistic placeholder**
Immediately insert a local-only `_PendingBubble` in the list, start upload in background, replace with real message on success.
- Pros: instant feedback, WhatsApp-like feel.
- Cons: requires local state (a `StateNotifier` or similar), rollback on failure, ordering complexity in the stream-driven list, significantly more code.
- Effort: High.

**Recommendation: Option A for MVP.**
Show a bottom-sheet-style progress indicator while uploading (or a linear progress bar in the composer area). On completion, the real message appears via the existing Firestore stream — no local state management needed. Show a clear error snackbar on failure.

---

### Decision 7: Preview + push notification

**Preview (`lastMessageText`):**
In `sendMessage`, when media is present, set:
- `lastMessageText = mediaType == MediaType.image ? l10n_preview_image : l10n_preview_video`

But `ChatRepository` has no l10n context. Use hardcoded localized strings for es-AR as constants, or pass them as parameters. Cleanest: define constants in the repository:
```dart
static const String previewPhoto = '📷 Foto';
static const String previewVideo = '🎥 Video';
```
These strings are stored in Firestore (not user-facing in code), so they don't need to go through `AppL10n`. If the app becomes multilingual, these can be derived from `mediaType` at render time instead.

**Push notification body:**
In `notify-chat-message.ts`, update:
```ts
const text = (messageData.text as string | undefined) ?? "";
const mediaType = (messageData.mediaType as string | undefined) ?? "";
const fallback = mediaType === "image" ? "📷 Foto" : mediaType === "video" ? "🎥 Video" : "";
const displayText = text.length > 0 ? truncate(text, 100) : fallback;
const body = `${senderName}: ${displayText}`;
```
Empty-text + unknown-mediaType edge case: body becomes `"Sender: "` — acceptable, still shows sender.

---

### Decision 8: Compression / thumbnails — defer or include?

**Defer:**
- No compression, no thumbnail generation in MVP.
- Image: pick via `image_picker` (already a dep), upload as-is. Limit picker to gallery quality (use `ImageQuality` parameter of `image_picker` — set `imageQuality: 80` to apply JPEG recompression, reducing typical photo from ~3 MB to ~400 KB with no visible quality loss).
- Video: pick as-is, no server-side transcoding, rely on native player buffering.
- Thumbnail for video: none in MVP; show `_PlayOverlay` on a dark background as placeholder until video controller initializes.
- Storage cost: a concern at scale; acceptable at MVP with a 100 MB video cap.

**Recommendation: Defer thumbnails entirely. Apply `imageQuality: 80` at pick time — this is a single parameter, not a separate feature.**

---

### Decision 9: i18n keys needed

New keys in `intl_es_AR.arb` (and corresponding `intl_en.arb`):

| Key | Value (es-AR) | Context |
|-----|---------------|---------|
| `chatAttachMediaLabel` | `"Adjuntar"` | Tooltip for the attach button in the composer |
| `chatPickImageLabel` | `"Foto"` | Bottom sheet option |
| `chatPickVideoLabel` | `"Video"` | Bottom sheet option |
| `chatMediaUploading` | `"Subiendo…"` | Progress label while upload is in progress |
| `chatMediaUploadFailed` | `"No pudimos subir el archivo. Probá de nuevo."` | Error snackbar |
| `chatMediaPreviewPhoto` | `"📷 Foto"` | Bubble caption for image-only messages and inbox preview |
| `chatMediaPreviewVideo` | `"🎥 Video"` | Bubble caption for video-only messages and inbox preview |
| `chatMediaViewFullscreen` | `"Ver foto"` | Tooltip / semantics for fullscreen tap |
| `chatMediaImageLoadError` | `"No pudimos cargar la imagen."` | Error state inside image bubble |

Note: `chatMediaPreviewPhoto` / `chatMediaPreviewVideo` are also stored in Firestore as `lastMessageText` — the repository uses the same strings, ideally injected or matched by convention. The repository constants `previewPhoto = '📷 Foto'` and `previewVideo = '🎥 Video'` must match the ARB values.

---

## Files to Touch

### New files
| File | Why |
|------|-----|
| `lib/features/chat/domain/media_type.dart` | `MediaType` enum (image/video), json_serializable |
| `lib/features/chat/data/chat_media_upload_service.dart` | Upload images+videos to `chatMedia/{chatId}/{uid}/{ts}.{ext}` |
| `lib/core/widgets/firebase_storage_video_player.dart` | Extract `_NativeVideoCard` as public reusable widget |
| `lib/features/chat/presentation/widgets/chat_image_bubble.dart` | `CachedNetworkImage` bubble + tap-to-fullscreen |
| `lib/features/chat/presentation/widgets/chat_video_bubble.dart` | Wrapper around `FirebaseStorageVideoPlayer` |
| `lib/features/chat/presentation/screens/photo_viewer_screen.dart` | Full-screen image viewer with `InteractiveViewer` |
| `test/features/chat/domain/media_type_test.dart` | MediaType serialization tests |
| `test/features/chat/domain/message_media_test.dart` | Message with mediaUrl/mediaType round-trip |
| `test/features/chat/data/chat_repository_media_test.dart` | sendMediaMessage tests with fake_cloud_firestore |
| `test/features/chat/data/chat_media_upload_service_test.dart` | Upload service unit tests (mock FirebaseStorage) |
| `test/features/chat/presentation/widgets/chat_image_bubble_test.dart` | Widget test |
| `test/features/chat/presentation/widgets/chat_video_bubble_test.dart` | Widget test |
| `functions/src/__tests__/notify-chat-message-media.test.ts` | New test scenarios for media-only push body |

### Modified files
| File | What changes |
|------|--------------|
| `lib/features/chat/domain/message.dart` | Add `@Default('') String text`, `String? mediaUrl`, `MediaType? mediaType` |
| `lib/features/chat/data/chat_repository.dart` | `sendMessage` → accept `mediaUrl?`/`mediaType?`, update validation, update preview logic |
| `lib/features/chat/application/chat_providers.dart` | (likely no change; only if new upload provider added) |
| `lib/features/chat/presentation/chat_screen.dart` | `_Composer` adds attach button + bottom sheet; `_Bubble` adds media rendering branches |
| `firestore.rules` | Update message `allow create` to OR logic for text/media |
| `storage.rules` | Add `chatMedia/{chatId}/{userId}/{file=**}` block |
| `functions/src/notifications/notify-chat-message.ts` | Add `mediaType` fallback to push body |
| `lib/l10n/intl_es_AR.arb` | Add 9 new keys (see Decision 9) |
| `lib/l10n/intl_en.arb` | Add same 9 keys in English |
| `lib/l10n/intl_es.arb` | Add same 9 keys in neutral Spanish |
| `test/features/chat/data/chat_repository_test.dart` | Add cases for empty text on media send |
| `test/features/chat/domain/message_test.dart` | Add media fields round-trip cases |
| `functions/src/__tests__/notify-chat-message.test.ts` | Add SCENARIO for media-only message body |

### Files verified as NOT needing changes
- `lib/features/chat/presentation/chat_list_screen.dart` — `lastMessageText` is a `String?`; "📷 Foto" renders fine.
- `lib/features/chat/application/chat_providers.dart` — no stream shape changes.
- `lib/features/workout/presentation/widgets/exercise_video_player.dart` — used as-is; `_NativeVideoCard` extracted to new file.

---

## Strict-TDD Test Plan

All tests written BEFORE production code (Red → Green → Refactor). Each test file corresponds to a unit of work.

### Layer 1 — Domain (pure, no deps)

**`test/features/chat/domain/media_type_test.dart`**
- `MediaType.image.toJson()` returns `"image"`
- `MediaType.fromJson("image")` returns `MediaType.image`
- `MediaType.fromJson("video")` returns `MediaType.video`
- `MediaType.fromJson("unknown")` throws (or returns null — decide convention)

**`test/features/chat/domain/message_media_test.dart`**
- `Message` with `mediaUrl + mediaType`, empty `text` → `fromJson` round-trip
- `Message` with text + mediaUrl (caption + media) → round-trip
- `Message` with only text (backward compat) → `mediaUrl == null`, `mediaType == null`
- `Message.fromJson(rawMap)` with Firestore Timestamp on `createdAt` + media fields → correct deserialization

### Layer 2 — Data / Repository

**`test/features/chat/data/chat_repository_media_test.dart`** (uses `fake_cloud_firestore`)
- `sendMessage(mediaUrl: url, mediaType: MediaType.image)` with empty text → writes correct Firestore doc (no ArgumentError)
- `sendMessage(mediaUrl: url, mediaType: MediaType.image)` → `lastMessageText` in parent = `'📷 Foto'`
- `sendMessage(mediaUrl: url, mediaType: MediaType.video)` → `lastMessageText` = `'🎥 Video'`
- `sendMessage(text: 'caption', mediaUrl: url, mediaType: MediaType.image)` → both fields stored correctly
- `sendMessage(text: '', mediaUrl: null, mediaType: null)` → still throws `ArgumentError` (no text, no media)
- `watchMessages` emits `Message` objects with `mediaUrl`/`mediaType` populated
- Text-only `sendMessage` path unchanged (regression test)

**`test/features/chat/data/chat_media_upload_service_test.dart`** (mock FirebaseStorage / FirebaseAuth)
- `upload(imagePath, ...)` → calls `putFile` with correct contentType `image/jpeg`
- `upload(videoPath, ...)` → calls `putFile` with `video/mp4`
- `upload(...)` with no authenticated user → throws `StateError`
- `onProgress` callback fires with values in `[0..1]`
- Returned URL matches what `FirebaseStorage.ref().getDownloadURL()` returns (mock)

### Layer 3 — Firestore Rules (emulator, skip in unit CI)

**`test/features/chat/data/chat_media_rules_test.dart`** (emulator-only, `skip: 'emulator required'`)
- SCENARIO-M01: member creates media-only message (text: "", mediaUrl: "https://...", mediaType: "image") → permitted
- SCENARIO-M02: member creates text + media message → permitted
- SCENARIO-M03: non-member creates message → denied
- SCENARIO-M04: message with empty text AND null mediaUrl → denied
- SCENARIO-M05: message missing `createdAt` → denied

### Layer 4 — Presentation

**`test/features/chat/presentation/widgets/chat_image_bubble_test.dart`**
- Renders `CachedNetworkImage` (or a stub) when `message.mediaType == MediaType.image`
- Tap triggers navigation / calls `onTap` (pump, tap, verify route push)
- Shows `CircularProgressIndicator` while loading (image placeholder)
- Shows error icon when image fails

**`test/features/chat/presentation/widgets/chat_video_bubble_test.dart`**
- Renders `FirebaseStorageVideoPlayer` (or key-check) when `message.mediaType == MediaType.video`
- Caption text shown below if `message.text.isNotEmpty`
- No text widget shown if `message.text.isEmpty`

**`test/features/chat/presentation/chat_screen_composer_test.dart`** (new widget tests for `_Composer` with attach)
- Attach button is visible
- Tap attach → shows bottom sheet with Foto / Video options
- While `uploading == true`, send button and attach button are disabled

### Layer 5 — Cloud Function (Jest, emulator)

New scenarios added to `notify-chat-message.test.ts` (or a new file):
- SCENARIO-M10: media-only message (`text: ""`, `mediaType: "image"`) → push body = `"Sender Name: 📷 Foto"`
- SCENARIO-M11: media-only video → push body = `"Sender Name: 🎥 Video"`
- SCENARIO-M12: caption + media → push body uses caption text (truncated)
- SCENARIO-M13: media-only, unknown mediaType → body = `"Sender Name: "` (degenerate, not a crash)

---

## Risks and Unknowns

1. **`fake_cloud_firestore` and the updated Firestore rule** — `fake_cloud_firestore` does not enforce security rules; the media-create rule change must be validated via emulator tests only. This is the existing pattern (see `firestore_rules_test.dart`).

2. **`_NativeVideoCard` extraction** — It is currently a private class in `exercise_video_player.dart`. Extracting it to `firebase_storage_video_player.dart` requires touching the workout feature's player file. Risk: accidental regression in exercise video rendering. Mitigated by: existing exercise player tests (none found — note this as a gap); the extraction is purely mechanical (move class, update import).

3. **iOS `image_picker` permissions** — `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` must exist in `ios/Runner/Info.plist`. If not present, the app crashes on first picker open. This is NOT currently needed (text-only chat). Must verify and add if absent during apply.

4. **`video_player` on iOS — autoplay / silent mode** — Native video playback respects the iOS silent switch by default; trainer videos may play without sound on muted devices. This is existing behavior in exercise videos, so it's consistent, but should be documented.

5. **Storage URL vs. `firebase_storage` path** — `CustomExerciseVideoUploadService.deleteByDownloadUrl` uses `extractFirebaseStoragePath` which parses the `?alt=media&token=...` URL format. Chat upload service should use the same helper.

6. **`mediaType` field in Firestore vs. enum naming** — `json_annotation` on the enum needs a consistent convention. Currently the project uses `@JsonEnum(valueField: 'value')` or default snake_case? Need to check `UserRole` or similar enums in the codebase for the existing pattern before writing the enum.

7. **Preview string in Firestore** — `lastMessageText = '📷 Foto'` is stored as a literal in Firestore (not i18n). If the app eventually supports English, the stored string is always es-AR. For MVP (Argentina-only), this is acceptable. For a multilingual future, the preview should be derived from `lastMessageType` at render time rather than stored.

8. **Upload size limits** — `image_picker` with `imageQuality: 80` typically produces 200–500 KB JPEGs, well under any reasonable Storage limit. Video from gallery can be several hundred MB. The 100 MB cap in Storage rules (matching `customExerciseVideos`) may be hit by long videos. MVP policy: document the limit, show an error if `putFile` throws `firebase_storage/quota-exceeded`.

9. **No `@JsonEnum` pattern found yet** — Need to verify enum serialization convention (see risk 6) by checking an existing enum with `json_serializable` in the codebase before writing `MediaType`.

---

## Ready for Proposal

Yes. All decisions are fully analyzable from current code. The key resolved choices are:

- Model: Option A (flat optional fields `mediaUrl?` + `mediaType?`)
- Upload: dedicated `ChatMediaUploadService`
- Storage rules: authed-read (same as exercise videos)
- Firestore rule: OR-based text/media validity
- Rendering: `CachedNetworkImage` for images, extracted `FirebaseStorageVideoPlayer` for videos
- UX: upload-then-send (no optimistic placeholders)
- Preview/push: string constants in repository + mediaType fallback in CF
- Compression: `imageQuality: 80` at picker, no thumbnails
- Zero new runtime dependencies

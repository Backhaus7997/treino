# Design: chat-media-messages

## Technical Approach

Add photo/video to the existing 1:1 chat by making `Message` carry optional media fields,
relaxing the Firestore message-create rule, adding a `chatMedia/` Storage path + upload
service, branching the bubble/composer UI, and tweaking the push body. Feature-first layering
(`domain/data/presentation`) is preserved; the video player is promoted to a shared
`core/widgets` widget so chat and workout reuse it. Zero new runtime deps — all confirmed
present in `pubspec.yaml` (image_picker 1.1.2, video_player 2.9.0, firebase_storage 12.3.0,
cached_network_image 3.4.1, fake_cloud_firestore 3.0.3 dev).

## Architecture Decisions

| Decision | Choice | Rejected | Rationale |
|----------|--------|----------|-----------|
| Message shape | Flat `@Default('') text`, `String? mediaUrl`, `MediaType? mediaType` | Nested media object; sealed union | Two fields don't warrant nesting; union breaks every call site/test |
| Upload service | New `ChatMediaUploadService` | Generalize `CustomExerciseVideoUploadService` | Existing is video-only/workout-scoped; mirror its shape, don't couple features |
| Storage access | authed-read, owner-write, size+contentType allowlist | Membership check | Storage rules can't `get()` Firestore; `chatId` is organizational only, security = unguessable `?token=` (same posture as `customExerciseVideos`) |
| Rule validity | `text.size()>0 OR (mediaUrl is string & size>0 & mediaType is string)` | Drop text check | Keep senderId + createdAt + membership intact; only relax text-required |
| Send UX | Upload-then-send, blocking progress | Optimistic placeholder | Optimistic needs local ordering/rollback state — disproportionate for MVP |
| Video widget | Extract `_NativeVideoCard` → public `FirebaseStorageVideoPlayer` in `core/widgets/` | Duplicate player in chat | Mechanical move; one player, two callers |
| Preview/push | Repo writes es-AR literal `📷 Foto`/`🎥 Video` to `lastMessageText`; CF mirrors as fallback | Derive at render from `mediaType` | MVP Argentina-only; future: store type, render localized |

## Interfaces / Contracts

```dart
// domain/media_type.dart — mirrors Gender @JsonValue pattern
enum MediaType { @JsonValue('image') image, @JsonValue('video') video }

// domain/message.dart — additive, backward-compatible
const factory Message({
  required String id,
  required String senderId,
  @Default('') String text,          // was: required String
  String? mediaUrl,
  MediaType? mediaType,
  @TimestampConverter() required DateTime createdAt,
}) = _Message;
// json round-trip: old text-only docs omit mediaUrl/mediaType → both null; text always present.
// build_runner: dart run build_runner build --delete-conflicting-outputs after edit.

// data/chat_media_upload_service.dart — mirrors CustomExerciseVideoUploadService
Future<String> upload(String localPath, {
  required String chatId, required MediaType mediaType,
  void Function(double fraction)? onProgress });          // → download URL
Future<bool> deleteByDownloadUrl(String url);
// path: chatMedia/{chatId}/{uid}/{microTsRadix36}.{ext}
// images: jpg/jpeg/png/heic/webp → image/*; videos: mp4/mov/m4v → video/*
// size guard surfaced as error before putFile (img<15MB, vid<100MB) to match rules.

// data/chat_repository.dart — sendMessage new signature
Future<void> sendMessage({
  required String chatId, required String senderId,
  String text = '', String? mediaUrl, MediaType? mediaType });
// validate: trimmed.isEmpty && mediaUrl==null → throw ArgumentError (media OR text required)
// when mediaUrl!=null require mediaType!=null (else ArgumentError)
// preview: caption wins; else mediaType==image → previewPhoto '📷 Foto', video → previewVideo '🎥 Video'
// keep the atomic batch (msg set + parent update).
```

## Rule Diffs

```
# firestore.rules messages create (line 454-455) → OR-based, keep senderId+membership+createdAt
&& (request.resource.data.text is string && request.resource.data.text.size() > 0
    || (request.resource.data.mediaUrl is string && request.resource.data.mediaUrl.size() > 0
        && request.resource.data.mediaType is string))
&& request.resource.data.createdAt is timestamp;

# storage.rules — new block after customExerciseVideos. Tradeoff comment: no Firestore get();
# chatId organizational; security via unguessable token (same as customExerciseVideos).
match /chatMedia/{chatId}/{userId}/{file=**} {
  allow read: if request.auth != null;
  allow write: if request.auth != null && request.auth.uid == userId
    && ((request.resource.contentType.matches('image/.*') && request.resource.size < 15*1024*1024)
        || (request.resource.contentType.matches('video/.*') && request.resource.size < 100*1024*1024));
  allow delete: if request.auth != null && request.auth.uid == userId;
}
```

## Presentation

- `FirebaseStorageVideoPlayer` (new, `core/widgets/`): lift `_NativeVideoCard` verbatim (controller
  lifecycle, play/pause, progress, init-fail placeholder) as a public widget taking `url` + reading
  `AppPalette.of(context)`. `exercise_video_player.dart` keeps `_PlayOverlay`/helpers and delegates
  to it; update its import. Mechanical — verify exercise playback unchanged.
- `_Bubble`: branch on `message.mediaType` — null → existing text; `image` → `ChatImageBubble`
  (`CachedNetworkImage`, tap → `PhotoViewerScreen` w/ `InteractiveViewer`); `video` →
  `ChatVideoBubble` (wraps `FirebaseStorageVideoPlayer`). Caption (`text`) rendered below media when non-empty.
- `_Composer`: add attach `IconButton` (`TreinoIcon`, `AppPalette`) left of TextField → bottom sheet
  (photo/video) → `image_picker` (`imageQuality: 80`) → upload via service with `LinearProgressIndicator`
  bound to `onProgress` → `sendMessage(mediaUrl, mediaType, text: caption)`. Attach + send disabled
  while `_sending`/uploading; error → snackbar (`chatMediaUploadFailed`). Reuse `_onSend` for text path.
- All strings via `AppL10n`; no hex, no Phosphor-direct.

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `lib/features/chat/domain/media_type.dart` | Create | MediaType enum |
| `lib/features/chat/data/chat_media_upload_service.dart` | Create | Upload images+videos |
| `lib/core/widgets/firebase_storage_video_player.dart` | Create | Extracted public player |
| `lib/features/chat/presentation/widgets/chat_image_bubble.dart` | Create | Inline image + tap |
| `lib/features/chat/presentation/widgets/chat_video_bubble.dart` | Create | Inline video |
| `lib/features/chat/presentation/screens/photo_viewer_screen.dart` | Create | Fullscreen InteractiveViewer |
| `lib/features/chat/domain/message.dart` | Modify | Add media fields (+ regen .g/.freezed) |
| `lib/features/chat/data/chat_repository.dart` | Modify | sendMessage signature + preview |
| `lib/features/chat/presentation/chat_screen.dart` | Modify | _Composer + _Bubble |
| `lib/features/workout/presentation/widgets/exercise_video_player.dart` | Modify | Delegate to extracted player |
| `firestore.rules` | Modify | OR rule for text/media |
| `storage.rules` | Modify | chatMedia block |
| `functions/src/notifications/notify-chat-message.ts` | Modify | media body fallback |
| `lib/l10n/intl_es_AR.arb` / `intl_es.arb` / `intl_en.arb` | Modify | 9 keys |
| `ios/Runner/Info.plist` | Verify | Keys already present (see note) |

## Cloud Function

`notify-chat-message.ts` after line 89: read `mediaType` from `messageData`; `displayText = text.length>0 ? truncate(text,100) : mediaType==='image' ? '📷 Foto' : mediaType==='video' ? '🎥 Video' : ''`. Unknown/missing → empty → body `"Sender: "` (no crash). `body = ${senderName}: ${displayText}`.

## i18n

9 keys in all 3 ARB (`intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb`), matching `"@key": {}` shape:
`chatAttachMediaLabel`, `chatPickImageLabel`, `chatPickVideoLabel`, `chatMediaUploading`,
`chatMediaUploadFailed`, `chatMediaPreviewPhoto` (📷 Foto), `chatMediaPreviewVideo` (🎥 Video),
`chatMediaViewFullscreen`, `chatMediaImageLoadError`.

## Testing Strategy (Strict TDD — write test first per layer)

| Layer | File | Asserts |
|-------|------|---------|
| Domain enum | `test/features/chat/domain/media_type_test.dart` | JsonValue image/video round-trip |
| Domain model | `test/features/chat/domain/message_media_test.dart` | media + empty-text + caption fromJson/toJson; text-only back-compat |
| Repo | extend `test/features/chat/data/chat_repository_test.dart` | image→📷, video→🎥, caption+media, empty+null throws, watch surfaces media, text regression |
| Upload | `test/features/chat/data/chat_media_upload_service_test.dart` | ext→contentType map, size guard, path shape (no real Storage; pure helpers + injected mocks) |
| Presentation | extend `chat_screen_test.dart` + `chat_image_bubble_test.dart`, `chat_video_bubble_test.dart` | image render+tap nav, video render, caption visibility, attach sheet, disabled-while-uploading |
| CF | extend `functions/src/__tests__/notify-chat-message.test.ts` | image→📷, video→🎥, caption wins, unknown→non-crash |
| Rules | DEFERRED — see risk | emulator-only |

## Sequencing / Seam (PR-A / PR-B if split)

```
PR-A (data foundation):  media_type → message(+regen) → firestore.rules + storage.rules
                         → chat_media_upload_service → chat_repository.sendMessage + preview
                         → CF body fallback  [+ domain/repo/upload/CF tests]
                         Verifiable headless: flutter test + jest, no UI.
PR-B (UI seam):          FirebaseStorageVideoPlayer extraction → image/video bubbles
                         → photo viewer → _Bubble branch → _Composer attach+upload flow
                         → i18n keys  [+ widget tests]
                         Depends on PR-A (model + sendMessage signature).
```
Dependency order: MediaType → Message → {rules, repo, upload} → CF (uses doc shape) → UI → i18n.

## Migration / Rollout

No data migration. Old text-only message docs deserialize unchanged (`text` present, media null).
Rule relaxation is additive — existing text sends keep passing. Quality gate: `flutter analyze` 0 +
`dart format .` + `flutter test` + functions `npm test`.

## Open Questions / Corrections

- **iOS Info.plist already has** `NSCameraUsageDescription` + `NSPhotoLibraryUsageDescription`
  (lines 54-57) — proposal assumed missing. NO crash risk; step downgrades to optional copy review
  (current copy is profile/Excel-specific). Removes the "blocking apply task" framing.
- **No rules-test harness exists** in the repo (no emulator/rules test files, no `@firebase/rules-unit-testing`).
  `fake_cloud_firestore` ignores rules. Rules-layer tests are net-new infra — recommend DEFERRING to a
  follow-up or treating as manual emulator verification, not a blocking unit test. Flag at tasks phase.
- CF media test EXTENDS the existing `notify-chat-message.test.ts` (not a separate file as explore listed).
- Single vs chained PR is a delivery decision for the tasks phase (user prefers single PR; est 600-900 lines
  exceeds 400 budget → record `size:exception` or split along the PR-A/PR-B seam above).

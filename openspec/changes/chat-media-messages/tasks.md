# Tasks: Chat Media Messages

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 650–900 (6 new files + 8 modified + 3 ARB + 1 rules + 1 CF) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR-A (data foundation) → PR-B (UI layer) |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| PR-A | Data foundation — headless, CI-verifiable | PR 1 | Targets main (or feature tracker); no UI dependencies |
| PR-B | UI layer — bubbles, composer, photo viewer | PR 2 | Targets PR-A branch or main after PR-A merges; requires PR-A model + sendMessage |

> **Decision required before `sdd-apply`**: single PR with `size:exception` OR chained PR-A → PR-B. User expressed preference for single PR — confirm or choose chain strategy.

---

## PR-A — Data Foundation (headless-verifiable)

### Phase 1: Domain Layer (REQ-CHATMEDIA-001, REQ-CHATMEDIA-002)

- [ ] 1.1 **[RED]** Write `test/features/chat/domain/media_type_test.dart` — `@JsonValue` round-trip for `image` and `video` (REQ-CHATMEDIA-002 scenarios).
- [ ] 1.2 **[GREEN]** Create `lib/features/chat/domain/media_type.dart` — `MediaType` enum with `@JsonValue('image')` / `@JsonValue('video')`, mirrors `Gender` pattern.
- [ ] 1.3 **[RED]** Write `test/features/chat/domain/message_media_test.dart` — media-only, caption+media, text-only back-compat, and round-trip `fromJson`/`toJson` scenarios (REQ-CHATMEDIA-001 scenarios).
- [ ] 1.4 **[GREEN]** Modify `lib/features/chat/domain/message.dart` — add `@Default('') String text` (was required), `String? mediaUrl`, `MediaType? mediaType`; re-run `dart run build_runner build --delete-conflicting-outputs`.
- [ ] 1.5 **[VERIFY]** Run `flutter analyze` (0 issues) + `flutter test test/features/chat/domain/` (all pass).

### Phase 2: Security Rules (REQ-CHATMEDIA-006, REQ-CHATMEDIA-007)

- [ ] 2.1 Modify `firestore.rules` — update messages `create` validity check to OR-based: `text.size() > 0 || (mediaUrl is string && mediaUrl.size() > 0 && mediaType is string)`; keep `senderId == request.auth.uid`, membership check, `createdAt is timestamp` (REQ-CHATMEDIA-006).
- [ ] 2.2 Modify `storage.rules` — add `match /chatMedia/{chatId}/{userId}/{file=**}` block: read if `auth != null`; write if `auth.uid == userId && ((contentType image/.* && size < 15MB) || (contentType video/.* && size < 100MB))`; delete if owner; add comment re: no-Firestore-get tradeoff (REQ-CHATMEDIA-007).
- [ ] 2.3 **[MANUAL EMULATOR]** Verify rules scenarios against Firebase Emulator: chat member creates media-only message (permit); non-member denied; empty text+null mediaUrl denied; missing `createdAt` denied; owner image <15 MB (permit); owner video <100 MB (permit); non-owner write denied; oversized image denied (REQ-CHATMEDIA-006, REQ-CHATMEDIA-007). *(Deferred option: invest in `@firebase/rules-unit-testing` harness for CI coverage — not blocking this PR.)*

### Phase 3: Upload Service (REQ-CHATMEDIA-007)

- [ ] 3.1 **[RED]** Write `test/features/chat/data/chat_media_upload_service_test.dart` — test extension-to-contentType mapping (jpg/jpeg/png/heic/webp → image/*, mp4/mov/m4v → video/*), size guard throws before `putFile` for img >15 MB and video >100 MB, path shape `chatMedia/{chatId}/{uid}/{ts}.{ext}`, and injected mock returns download URL.
- [ ] 3.2 **[GREEN]** Create `lib/features/chat/data/chat_media_upload_service.dart` — `upload(localPath, {required chatId, required mediaType, onProgress}) → Future<String>` + `deleteByDownloadUrl(url)`; mirrors `CustomExerciseVideoUploadService` shape; no new runtime deps.
- [ ] 3.3 **[VERIFY]** Run `flutter test test/features/chat/data/chat_media_upload_service_test.dart`.

### Phase 4: Repository (REQ-CHATMEDIA-003, REQ-CHATMEDIA-004, REQ-CHATMEDIA-005, REQ-CHATMEDIA-011, REQ-CHATMEDIA-015)

- [ ] 4.1 **[RED]** Extend `test/features/chat/data/chat_repository_test.dart` — add: image-only send writes `📷 Foto` to `lastMessageText`; video-only sends `🎥 Video`; caption wins; empty+null throws `ArgumentError` with no Firestore write; mediaUrl+null mediaType throws; watch stream surfaces `mediaUrl`/`mediaType`; text-only regression still passes (REQ-CHATMEDIA-003–005, REQ-CHATMEDIA-011, REQ-CHATMEDIA-015 scenarios).
- [ ] 4.2 **[GREEN]** Modify `lib/features/chat/data/chat_repository.dart` — extend `sendMessage` signature to `({required chatId, required senderId, String text = '', String? mediaUrl, MediaType? mediaType})`; add guard (`ArgumentError` if `text.isEmpty && mediaUrl == null`); add guard (`ArgumentError` if `mediaUrl != null && mediaType == null`); set `lastMessageText` = caption (truncated 80 chars) ?? `'📷 Foto'`/`'🎥 Video'`; keep atomic batch (REQ-CHATMEDIA-003–005, REQ-CHATMEDIA-011).
- [ ] 4.3 **[VERIFY]** Run `flutter analyze` (0) + `flutter test test/features/chat/` (all pass).

### Phase 5: Cloud Function (REQ-CHATMEDIA-012)

- [ ] 5.1 **[RED]** Extend `functions/src/__tests__/notify-chat-message.test.ts` — add: image-only body `'Sender: 📷 Foto'`; video-only `'Sender: 🎥 Video'`; caption wins over label; unknown `mediaType` with empty text → no throw (REQ-CHATMEDIA-012 scenarios).
- [ ] 5.2 **[GREEN]** Modify `functions/src/notify-chat-message.ts` — after line 89: read `mediaType`; compute `displayText = text.length > 0 ? truncate(text, 100) : mediaType === 'image' ? '📷 Foto' : mediaType === 'video' ? '🎥 Video' : ''`; use `displayText` as notification body.
- [ ] 5.3 **[VERIFY]** Run `npm test` in `functions/` (all pass).

**PR-A quality gate**: `flutter analyze` 0 + `dart format .` + `flutter test` (all chat domain/data tests) + `npm test` (functions).

---

## PR-B — UI Layer (depends on PR-A)

### Phase 6: Shared Video Player Extraction (REQ-CHATMEDIA-009)

- [ ] 6.1 Create `lib/core/widgets/firebase_storage_video_player.dart` — lift `_NativeVideoCard` (controller lifecycle, play/pause, progress, init-fail) verbatim as public `FirebaseStorageVideoPlayer` widget; keep API surface minimal.
- [ ] 6.2 Modify `lib/features/workout/presentation/exercise_video_player.dart` (or equivalent) — replace inline `_NativeVideoCard` with `FirebaseStorageVideoPlayer` import; keep `_PlayOverlay`/helpers local; verify existing workout player tests still pass.
- [ ] 6.3 **[VERIFY]** Run `flutter analyze` (0) + existing workout widget tests still green.

### Phase 7: i18n Keys (REQ-CHATMEDIA-014)

- [ ] 7.1 Add 9 keys to `lib/l10n/intl_es_AR.arb`: `chatAttachMediaLabel`, `chatPickImageLabel`, `chatPickVideoLabel`, `chatMediaUploading`, `chatMediaUploadFailed`, `chatMediaPreviewPhoto` (`📷 Foto`), `chatMediaPreviewVideo` (`🎥 Video`), `chatMediaViewFullscreen`, `chatMediaImageLoadError`. Use `"@key": {}` shape.
- [ ] 7.2 Mirror all 9 keys in `lib/l10n/intl_es.arb` and `lib/l10n/intl_en.arb` with appropriate values.
- [ ] 7.3 Run `flutter gen-l10n`; confirm `AppL10n` exposes all 9 getters with no analysis errors.

### Phase 8: Image Bubble + Fullscreen Viewer (REQ-CHATMEDIA-008)

- [ ] 8.1 **[RED]** Write `test/features/chat/presentation/chat_image_bubble_test.dart` — render thumbnail (`CachedNetworkImage` present), tap navigates to `PhotoViewerScreen`, caption displayed below when `text` non-empty (REQ-CHATMEDIA-008 scenarios).
- [ ] 8.2 **[GREEN]** Create `lib/features/chat/presentation/photo_viewer_screen.dart` — `InteractiveViewer` wrapping `CachedNetworkImage`, title from `AppL10n.chatMediaViewFullscreen`.
- [ ] 8.3 **[GREEN]** Create `lib/features/chat/presentation/chat_image_bubble.dart` — `CachedNetworkImage` thumbnail + loading skeleton + error placeholder (`AppL10n.chatMediaImageLoadError`) + `GestureDetector` → push `PhotoViewerScreen`; caption below when non-empty; colors from `AppPalette`.

### Phase 9: Video Bubble (REQ-CHATMEDIA-009)

- [ ] 9.1 **[RED]** Write `test/features/chat/presentation/chat_video_bubble_test.dart` — `FirebaseStorageVideoPlayer` present in tree, caption displayed below when non-empty (REQ-CHATMEDIA-009 scenarios).
- [ ] 9.2 **[GREEN]** Create `lib/features/chat/presentation/chat_video_bubble.dart` — renders `FirebaseStorageVideoPlayer`; caption below when `text.isNotEmpty`; colors from `AppPalette`.

### Phase 10: iOS Permissions Review (REQ-CHATMEDIA-013)

- [ ] 10.1 **[OPTIONAL / STATIC]** Open `ios/Runner/Info.plist` (lines 54-57) — review `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` copy; confirm strings are generic enough to cover chat media (not profile/Excel-specific). Update copy if too narrow. No new keys required — keys already present.

### Phase 11: Bubble Branching + Composer (REQ-CHATMEDIA-010, REQ-CHATMEDIA-015)

- [ ] 11.1 **[RED]** Extend `test/features/chat/presentation/chat_screen_test.dart` — add: attach button opens bottom sheet with photo/video options; controls disabled while uploading; upload failure shows snackbar with `AppL10n.chatMediaUploadFailed`; text-only bubble regression (no media widget in tree) (REQ-CHATMEDIA-010, REQ-CHATMEDIA-015 scenarios).
- [ ] 11.2 **[GREEN]** Modify `lib/features/chat/presentation/chat_screen.dart` — update `_Bubble` widget: branch on `mediaType`: `null` → text bubble (unchanged); `image` → `ChatImageBubble`; `video` → `ChatVideoBubble`; caption below media when non-empty.
- [ ] 11.3 **[GREEN]** Modify `_Composer` in `chat_screen.dart` — add attach `IconButton` (use `TreinoIcon`, `AppPalette` colors); bottom sheet with `AppL10n.chatPickImageLabel` / `AppL10n.chatPickVideoLabel` options; call `image_picker` with `imageQuality: 80`; show `LinearProgressIndicator` during upload (via `onProgress`); disable attach + send while uploading; show error snackbar (`AppL10n.chatMediaUploadFailed`) on failure; wire `ChatMediaUploadService.upload` → `ChatRepository.sendMessage`.
- [ ] 11.4 **[VERIFY]** Run `flutter analyze` (0) + `dart format .` + `flutter test` (full suite, all pass).

**PR-B quality gate**: `flutter analyze` 0 + `dart format .` + `flutter test` (full suite) — no regressions.

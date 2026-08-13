// Widget tests for Chat web V3 (2026-07-01) — video media in the composer
// and the bubble.
//
// V3 changes covered:
//   - Composer's attach button opens a bottom sheet with "Foto" / "Video"
//     entries (V2 opened the picker directly to image).
//   - ChatMessageBubble renders a FirebaseStorageVideoPlayer inline when
//     `videoUrl` is passed (used by the detail pane when
//     `message.mediaType == video`).
//   - Message list wiring: mediaType.video → videoUrl (not a placeholder).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/firebase_storage_video_player.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/chat/domain/media_type.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/chat_section_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/chat_message_bubble.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

const _pfUid = 'pf-1';
const _athleteUid = 'athlete-1';
const _chatId = 'chat-1';

Chat _stubChat() => Chat(
      chatId: _chatId,
      members: const [_pfUid, _athleteUid],
      createdAt: DateTime(2026, 6, 1),
      lastMessageAt: DateTime(2026, 7, 1, 10),
      lastMessageText: 'hola',
    );

UserPublicProfile _stubPub() => const UserPublicProfile(
      uid: _athleteUid,
      displayName: 'Vicente',
      avatarUrl: null,
      gymId: null,
    );

Widget _wrapBubble(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(1200, 800)),
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Widget _wrapSection(ProviderContainer container) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(1200, 800)),
    child: UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: ChatSectionScreen()),
      ),
    ),
  );
}

void main() {
  group('Chat web V3 — bubble video rendering', () {
    testWidgets(
      'bubble with videoUrl renders FirebaseStorageVideoPlayer inline',
      (tester) async {
        await tester.pumpWidget(_wrapBubble(
          ChatMessageBubble(
            text: '',
            isOwn: false,
            createdAt: DateTime(2026, 7, 1, 10),
            videoUrl: 'https://firebasestorage.googleapis.com/vid.mp4',
          ),
        ));
        // pump() only — pumpAndSettle would hang on the async
        // VideoPlayerController.initialize() call which never resolves in
        // the test environment. We assert widget presence, not playback.
        await tester.pump();

        expect(find.byType(FirebaseStorageVideoPlayer), findsOneWidget);
        // No image should be rendered when only videoUrl is set.
        expect(find.byType(Image), findsNothing);
      },
    );

    testWidgets(
      'bubble with videoUrl AND text (caption) renders both',
      (tester) async {
        await tester.pumpWidget(_wrapBubble(
          ChatMessageBubble(
            text: 'mirá la técnica',
            isOwn: true,
            createdAt: DateTime(2026, 7, 1, 10),
            videoUrl: 'https://firebasestorage.googleapis.com/vid.mp4',
          ),
        ));
        await tester.pump();

        expect(find.byType(FirebaseStorageVideoPlayer), findsOneWidget);
        expect(find.text('mirá la técnica'), findsOneWidget);
      },
    );

    testWidgets(
      'bubble with imageUrl only does NOT render a video player',
      (tester) async {
        await tester.pumpWidget(_wrapBubble(
          ChatMessageBubble(
            text: '',
            isOwn: false,
            createdAt: DateTime(2026, 7, 1, 10),
            imageUrl: 'https://firebasestorage.googleapis.com/foto.jpg',
          ),
        ));
        await tester.pump();

        expect(find.byType(FirebaseStorageVideoPlayer), findsNothing);
      },
    );

    testWidgets(
      'plain text bubble (no media) does NOT render a video player',
      (tester) async {
        await tester.pumpWidget(_wrapBubble(
          ChatMessageBubble(
            text: 'hola',
            isOwn: true,
            createdAt: DateTime(2026, 7, 1, 10),
          ),
        ));
        await tester.pump();

        expect(find.byType(FirebaseStorageVideoPlayer), findsNothing);
      },
    );
  });

  group('Chat web V3 — composer attach menu', () {
    testWidgets(
      'tapping attach opens a bottom sheet with "Foto" and "Video" entries',
      (tester) async {
        final container = ProviderContainer(overrides: [
          currentUidProvider.overrideWithValue(_pfUid),
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream<List<Chat>>.value([_stubChat()]),
          ),
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
          ),
          messagesProvider(_chatId).overrideWith(
            (ref) => Stream<List<Message>>.value(const []),
          ),
        ]);
        addTearDown(container.dispose);
        container.read(selectedChatIdProvider.notifier).state = _chatId;

        await tester.pumpWidget(_wrapSection(container));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('chat_composer_attach_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('chat_composer_attach_menu_photo')),
            findsOneWidget);
        expect(find.byKey(const Key('chat_composer_attach_menu_video')),
            findsOneWidget);
        expect(find.text('Foto'), findsOneWidget);
        expect(find.text('Video'), findsOneWidget);
      },
    );
  });

  group('Chat web V3 — message list wiring', () {
    testWidgets(
      'video message reaches the bubble as videoUrl (NOT as placeholder)',
      (tester) async {
        const videoMsgUrl = 'https://firebasestorage.googleapis.com/vid.mp4';
        final container = ProviderContainer(overrides: [
          currentUidProvider.overrideWithValue(_pfUid),
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream<List<Chat>>.value([_stubChat()]),
          ),
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
          ),
          messagesProvider(_chatId).overrideWith(
            (ref) => Stream<List<Message>>.value([
              Message(
                id: 'v1',
                senderId: _athleteUid,
                text: '',
                mediaUrl: videoMsgUrl,
                mediaType: MediaType.video,
                createdAt: DateTime(2026, 7, 1, 10),
              ),
            ]),
          ),
        ]);
        addTearDown(container.dispose);
        container.read(selectedChatIdProvider.notifier).state = _chatId;

        await tester.pumpWidget(_wrapSection(container));
        // pump() only — the video player controller's async init would
        // never settle. We assert bubble wiring, not playback.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(FirebaseStorageVideoPlayer), findsOneWidget);
        // No placeholder label like "🎥 Video" should appear — V3 renders
        // the player inline instead.
        expect(find.textContaining('🎥'), findsNothing);
      },
    );
  });
}

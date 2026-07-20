// Widget tests for the Chat detail pane header (Fase 8, WU-05) — rediseño
// con tokens v2.
//
// Cubre:
//   - Con un chat seleccionado, el header resuelve y muestra el displayName
//     del otro usuario (via `chatsForCurrentUserProvider` +
//     `userPublicProfileProvider`, sin streams nuevos).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/chat_section_screen.dart';
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

void main() {
  group('ChatDetailPane — header', () {
    testWidgets(
      'shows the resolved displayName of the other user when a chat is '
      'selected',
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

        await tester.pumpWidget(
          MediaQuery(
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
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('chat_detail_header')),
            matching: find.text('Vicente'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}

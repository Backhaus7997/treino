// Widget tests for the Coach Hub web Chat section — V1 (texto only).
//
// Covers:
//   - Split-pane structure: list pane (fixed width) + detail pane (expands).
//   - Empty-state when no chat selected → "Seleccioná una conversación".
//   - Empty list state when the PF has zero chats.
//   - Tap on a chat row updates `selectedChatIdProvider`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/chat_section_screen.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

const _pfUid = 'pf-1';
const _athleteUid = 'athlete-1';
const _chatId = 'chat-1';

Chat _stubChat({String? lastMessageText, DateTime? lastMessageAt}) => Chat(
      chatId: _chatId,
      members: const [_pfUid, _athleteUid],
      createdAt: DateTime(2026, 6, 1),
      lastMessageAt: lastMessageAt,
      lastMessageText: lastMessageText,
    );

UserPublicProfile _stubPub({String displayName = 'Vicente'}) =>
    UserPublicProfile(
      uid: _athleteUid,
      displayName: displayName,
      avatarUrl: null,
      gymId: null,
    );

Widget _wrap({
  required List<Override> overrides,
  double width = 1200,
  double height = 800,
}) {
  return MediaQuery(
    data: MediaQueryData(size: Size(width, height)),
    child: ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: ChatSectionScreen(),
        ),
      ),
    ),
  );
}

void main() {
  group('ChatSectionScreen — empty states', () {
    testWidgets(
      'shows empty pane copy when no chat is selected',
      (tester) async {
        await tester.pumpWidget(_wrap(
          overrides: [
            currentUidProvider.overrideWithValue(_pfUid),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream<List<Chat>>.value(const []),
            ),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.text('Seleccioná una conversación'), findsOneWidget);
        expect(find.byType(TreinoEmptyState), findsOneWidget);
      },
    );

    testWidgets(
      'renders empty pane via TreinoEmptyState in both dark and light themes',
      (tester) async {
        for (final theme in [AppTheme.dark(), AppTheme.light()]) {
          await tester.pumpWidget(
            MediaQuery(
              data: const MediaQueryData(size: Size(1200, 800)),
              child: ProviderScope(
                overrides: [
                  currentUidProvider.overrideWithValue(_pfUid),
                  chatsForCurrentUserProvider.overrideWith(
                    (ref) => Stream<List<Chat>>.value(const []),
                  ),
                ],
                child: MaterialApp(
                  theme: theme,
                  localizationsDelegates: AppL10n.localizationsDelegates,
                  supportedLocales: AppL10n.supportedLocales,
                  locale: const Locale('es', 'AR'),
                  home: const Scaffold(
                    body: ChatSectionScreen(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(TreinoEmptyState), findsOneWidget);
          expect(find.text('Seleccioná una conversación'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'shows empty list copy when the PF has zero chats',
      (tester) async {
        await tester.pumpWidget(_wrap(
          overrides: [
            currentUidProvider.overrideWithValue(_pfUid),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream<List<Chat>>.value(const []),
            ),
          ],
        ));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Todavía no tenés conversaciones'),
          findsOneWidget,
        );
      },
    );
  });

  group('ChatSectionScreen — list rendering', () {
    testWidgets(
      'renders one row per chat with the resolved displayName',
      (tester) async {
        final chat = _stubChat(
          lastMessageText: 'Hola PF',
          lastMessageAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        await tester.pumpWidget(_wrap(
          overrides: [
            currentUidProvider.overrideWithValue(_pfUid),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream<List<Chat>>.value([chat]),
            ),
            userPublicProfileProvider(_athleteUid).overrideWith(
              (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
            ),
          ],
        ));
        await tester.pumpAndSettle();

        // Row keyed by chatId.
        expect(find.byKey(const Key('chat_row_$_chatId')), findsOneWidget);
        // Resolved name + last message preview both visible in the row.
        expect(find.text('Vicente'), findsOneWidget);
        expect(find.text('Hola PF'), findsOneWidget);
      },
    );

    testWidgets(
      '"Sin mensajes todavía" placeholder when lastMessageText is empty',
      (tester) async {
        final chat = _stubChat(lastMessageText: '');
        await tester.pumpWidget(_wrap(
          overrides: [
            currentUidProvider.overrideWithValue(_pfUid),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream<List<Chat>>.value([chat]),
            ),
            userPublicProfileProvider(_athleteUid).overrideWith(
              (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
            ),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.textContaining('Sin mensajes todavía'), findsOneWidget);
      },
    );
  });

  group('ChatSectionScreen — selection state', () {
    testWidgets(
      'tap on a chat row sets `selectedChatIdProvider` to that chatId',
      (tester) async {
        final chat = _stubChat(lastMessageText: 'Hola');
        final container = ProviderContainer(overrides: [
          currentUidProvider.overrideWithValue(_pfUid),
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream<List<Chat>>.value([chat]),
          ),
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
          ),
        ]);
        addTearDown(container.dispose);

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

        // Pre-tap: nothing selected → empty pane visible.
        expect(container.read(selectedChatIdProvider), isNull);
        expect(find.text('Seleccioná una conversación'), findsOneWidget);

        await tester.tap(find.byKey(const Key('chat_row_$_chatId')));
        await tester.pumpAndSettle();

        // Post-tap: provider holds the chatId.
        expect(container.read(selectedChatIdProvider), _chatId);
      },
    );
  });
}

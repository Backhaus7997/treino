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
import 'package:treino/app/theme/tokens/components/treino_focus_tokens.dart';
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
        // 2 TreinoEmptyState: el detail pane (sin selección) + la lista
        // (0 chats) — ambos usan el mismo componente del kit por diseño.
        expect(find.byType(TreinoEmptyState), findsWidgets);
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

          expect(find.byType(TreinoEmptyState), findsWidgets);
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

    testWidgets(
      'selected row exposes a distinct background/border from unselected',
      (tester) async {
        final chat = _stubChat(
          lastMessageText: 'Hola',
          lastMessageAt: DateTime.now(),
        );
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

        final containerFinder =
            find.byKey(const Key('chat_row_container_$_chatId'));
        final before = tester.widget<AnimatedContainer>(containerFinder);
        final beforeDecoration = before.decoration! as BoxDecoration;

        container.read(selectedChatIdProvider.notifier).state = _chatId;
        await tester.pumpAndSettle();

        final after = tester.widget<AnimatedContainer>(containerFinder);
        final afterDecoration = after.decoration! as BoxDecoration;

        expect(afterDecoration.color, isNot(equals(beforeDecoration.color)));
        expect(
          afterDecoration.border,
          isNot(equals(beforeDecoration.border)),
        );
      },
    );
  });

  group('ChatSectionScreen — list pane states', () {
    testWidgets(
      'loading state renders skeleton rows, not a raw spinner',
      (tester) async {
        await tester.pumpWidget(_wrap(
          overrides: [
            currentUidProvider.overrideWithValue(_pfUid),
            chatsForCurrentUserProvider.overrideWith(
              // Stream que nunca emite → el AsyncValue queda en loading.
              (ref) => const Stream<List<Chat>>.empty(),
            ),
          ],
        ));
        await tester.pump();

        expect(find.byKey(const Key('chat_list_skeleton')), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'empty list state still shows the preserved copy',
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
        expect(find.byType(TreinoEmptyState), findsWidgets);
      },
    );

    testWidgets(
      'error state renders a TreinoEmptyState with the error copy',
      (tester) async {
        await tester.pumpWidget(_wrap(
          overrides: [
            currentUidProvider.overrideWithValue(_pfUid),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream<List<Chat>>.error('boom'),
            ),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.text('No pudimos cargar tus chats.'), findsOneWidget);
        expect(find.byType(TreinoEmptyState), findsWidgets);
      },
    );

    testWidgets(
      'typing in the search field filters rows by resolved displayName',
      (tester) async {
        final chatVicente = _stubChat(lastMessageText: 'Hola PF');
        final chatOtro = Chat(
          chatId: 'chat-2',
          members: const [_pfUid, 'athlete-2'],
          createdAt: DateTime(2026, 6, 1),
          lastMessageText: 'Otro mensaje',
        );
        await tester.pumpWidget(_wrap(
          overrides: [
            currentUidProvider.overrideWithValue(_pfUid),
            chatsForCurrentUserProvider.overrideWith(
              (ref) => Stream<List<Chat>>.value([chatVicente, chatOtro]),
            ),
            userPublicProfileProvider(_athleteUid).overrideWith(
              (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
            ),
            userPublicProfileProvider('athlete-2').overrideWith(
              (ref) => Stream<UserPublicProfile?>.value(
                _stubPub(displayName: 'Mica'),
              ),
            ),
          ],
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('chat_row_chat-1')), findsOneWidget);
        expect(find.byKey(const Key('chat_row_chat-2')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('chat_search_field')),
          'vice',
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('chat_row_chat-1')), findsOneWidget);
        expect(find.byKey(const Key('chat_row_chat-2')), findsNothing);
      },
    );
  });

  group('ChatSectionScreen — unread badge', () {
    testWidgets(
      'renders the unread badge when the chat has an unread message',
      (tester) async {
        final chat = _stubChat(
          lastMessageText: 'Hola PF',
          lastMessageAt: DateTime.now(),
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

        expect(
          find.byKey(const Key('chat_row_unread_badge_$_chatId')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'does not render the unread badge when the chat has no messages',
      (tester) async {
        final chat = _stubChat();
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

        expect(
          find.byKey(const Key('chat_row_unread_badge_$_chatId')),
          findsNothing,
        );
      },
    );
  });

  group('ChatSectionScreen — chat row keyboard focus ring (remediación '
      'WARNING-2)', () {
    testWidgets(
      'foco de teclado en una row pinta el anillo de TreinoFocusTokens',
      (tester) async {
        final chat = _stubChat(lastMessageText: 'Hola');
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

        final rowContainerFinder =
            find.byKey(const Key('chat_row_container_$_chatId'));

        final beforeFocus =
            tester.widget<AnimatedContainer>(rowContainerFinder);
        final beforeDecoration = beforeFocus.decoration! as BoxDecoration;
        expect(
          beforeDecoration.boxShadow,
          anyOf(isNull, isEmpty),
          reason: 'sin foco no debe haber anillo pintado',
        );

        final focusTokens = TreinoFocusTokens.of(
          tester.element(rowContainerFinder),
        );

        Focus.of(tester.element(rowContainerFinder)).requestFocus();
        await tester.pump();
        await tester.pump();

        final afterFocus =
            tester.widget<AnimatedContainer>(rowContainerFinder);
        final afterDecoration = afterFocus.decoration! as BoxDecoration;
        expect(
          afterDecoration.boxShadow,
          isNotNull,
          reason: 'row enfocada por teclado debe pintar un anillo visible '
              '(ADR-SH-002, mismo patrón que filter_chips.dart)',
        );
        expect(afterDecoration.boxShadow, isNotEmpty);
        expect(
          afterDecoration.boxShadow!.first.color,
          focusTokens.ring.withValues(alpha: 0.5),
        );
      },
    );
  });
}

// Widget tests for the Chat detail pane header (Fase 8, WU-05) — rediseño
// con tokens v2.
//
// Cubre:
//   - Con un chat seleccionado, el header resuelve y muestra el displayName
//     del otro usuario (via `chatsForCurrentUserProvider` +
//     `userPublicProfileProvider`, sin streams nuevos).
//
// WU-06 agrega:
//   - Estados del stream de mensajes con TreinoStateSwitcher: loading
//     (skeleton de burbujas), thread vacío (TreinoEmptyState).
//   - Separadores de fecha ("HOY - 23 ABR") entre mensajes de días distintos.
//   - Robustez al cambiar de chat seleccionado sin desmontar el pane
//     (didUpdateWidget).

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

Message _msg({
  required String id,
  required String text,
  required DateTime createdAt,
  String senderId = _athleteUid,
}) =>
    Message(id: id, senderId: senderId, text: text, createdAt: createdAt);

Widget _appFor(Widget home) => MediaQuery(
      data: const MediaQueryData(size: Size(1200, 800)),
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: home,
      ),
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

  group('ChatDetailPane — messages stream states (WU-06)', () {
    testWidgets(
      'loading state shows bubble skeletons (key), not a bare spinner',
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
            // Stream que nunca emite → el AsyncValue queda en loading.
            (ref) => const Stream<List<Message>>.empty(),
          ),
        ]);
        addTearDown(container.dispose);
        container.read(selectedChatIdProvider.notifier).state = _chatId;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _appFor(const Scaffold(body: ChatSectionScreen())),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const Key('chat_messages_skeleton')),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets(
      'empty thread shows a TreinoEmptyState with the preserved copy',
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
          UncontrolledProviderScope(
            container: container,
            child: _appFor(const Scaffold(body: ChatSectionScreen())),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sin mensajes todavía'), findsOneWidget);
        expect(find.text('Escribí el primero abajo.'), findsOneWidget);
        expect(find.byKey(const Key('chat_messages_skeleton')), findsNothing);
      },
    );

    testWidgets(
      'messages spanning two distinct days render one date separator each',
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
            // DESC por createdAt (índice 0 = más nuevo), como devuelve
            // `watchMessages` en la app real.
            (ref) => Stream<List<Message>>.value([
              _msg(
                id: 'm-new-1',
                text: 'lo último',
                createdAt: DateTime(2026, 7, 1, 10),
              ),
              _msg(
                id: 'm-new-2',
                text: 'más temprano el mismo día',
                createdAt: DateTime(2026, 7, 1, 9),
              ),
              _msg(
                id: 'm-old',
                text: 'un día antes',
                createdAt: DateTime(2026, 6, 29, 18),
              ),
            ]),
          ),
        ]);
        addTearDown(container.dispose);
        container.read(selectedChatIdProvider.notifier).state = _chatId;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _appFor(const Scaffold(body: ChatSectionScreen())),
          ),
        );
        await tester.pumpAndSettle();

        // Un solo separador por día — arriba del mensaje más viejo de ese
        // día, no entre los dos mensajes del mismo 2026-07-01.
        expect(
          find.byKey(const ValueKey('chat_date_separator_2026-07-01')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('chat_date_separator_2026-06-29')),
          findsOneWidget,
        );
      },
    );
  });

  group('ChatDetailPane — chatId switch robustness (WU-06)', () {
    testWidgets(
      'switching the selected chat via didUpdateWidget does not throw and '
      're-subscribes cleanly',
      (tester) async {
        const chatIdB = 'chat-2';
        final chatB = Chat(
          chatId: chatIdB,
          members: const [_pfUid, _athleteUid],
          createdAt: DateTime(2026, 6, 1),
          lastMessageAt: DateTime(2026, 7, 2, 9),
          lastMessageText: 'otro chat',
        );

        final container = ProviderContainer(overrides: [
          currentUidProvider.overrideWithValue(_pfUid),
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream<List<Chat>>.value([_stubChat(), chatB]),
          ),
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
          ),
          messagesProvider(_chatId).overrideWith(
            (ref) => Stream<List<Message>>.value([
              _msg(id: 'a1', text: 'hola A', createdAt: DateTime(2026, 7, 1)),
            ]),
          ),
          messagesProvider(chatIdB).overrideWith(
            (ref) => Stream<List<Message>>.value([
              _msg(id: 'b1', text: 'hola B', createdAt: DateTime(2026, 7, 2)),
            ]),
          ),
        ]);
        addTearDown(container.dispose);
        container.read(selectedChatIdProvider.notifier).state = _chatId;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: _appFor(const Scaffold(body: ChatSectionScreen())),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('hola A'), findsOneWidget);

        container.read(selectedChatIdProvider.notifier).state = chatIdB;
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('hola B'), findsOneWidget);
        expect(find.text('hola A'), findsNothing);
      },
    );
  });
}

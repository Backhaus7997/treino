// Widget tests for ChatDetailPane's header name resolution.
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
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/chat_detail_pane.dart';
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
    );

UserPublicProfile _stubPub({String displayName = 'Agustín'}) =>
    UserPublicProfile(
      uid: _athleteUid,
      displayName: displayName,
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
  group(
      'ChatDetailPane header — peerUid/peerNameInitial known (alumno-detail Chat tab)',
      () {
    testWidgets(
      'shows the given name on the FIRST frame — never the loading placeholders',
      (tester) async {
        // Perfil vivo DELIBERADAMENTE nunca emite (cold/delayed stream) para
        // simular el hop frío que causaba el flash — el pane debe apoyarse
        // en peerNameInitial mientras tanto.
        final profileController = StreamController<UserPublicProfile?>();
        addTearDown(profileController.close);

        final container = _buildContainer(overrides: [
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => profileController.stream,
          ),
        ]);
        addTearDown(container.dispose);

        await _pumpPane(
          tester,
          container,
          const ChatDetailPane(
            chatId: _chatId,
            peerUid: _athleteUid,
            peerNameInitial: 'Agustín',
          ),
        );
        // Sin pumpAndSettle: exactamente el primer frame post-build.
        await tester.pump();

        expect(find.text('Agustín'), findsOneWidget);
        expect(find.text('Usuario eliminado'), findsNothing);
        expect(find.text('…'), findsNothing);
      },
    );

    testWidgets(
      'prefers the LIVE profile displayName over peerNameInitial once it resolves',
      (tester) async {
        final container = _buildContainer(overrides: [
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => Stream<UserPublicProfile?>.value(
              _stubPub(displayName: 'Agustín Fresco'),
            ),
          ),
        ]);
        addTearDown(container.dispose);

        await _pumpPane(
          tester,
          container,
          const ChatDetailPane(
            chatId: _chatId,
            peerUid: _athleteUid,
            peerNameInitial: 'Agustín Viejo',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Agustín Fresco'), findsOneWidget);
        expect(find.text('Agustín Viejo'), findsNothing);
      },
    );

    testWidgets(
      'never touches chatsForCurrentUserProvider when peerUid is provided',
      (tester) async {
        // chatsForCurrentUserProvider overridden to ERROR — if the header
        // fell back to the chat-derived lookup it would blow up / show the
        // error-driven placeholder. With peerUid it must never be read.
        final container = _buildContainer(overrides: [
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream<List<Chat>>.error(StateError('should not read')),
          ),
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
          ),
        ]);
        addTearDown(container.dispose);

        await _pumpPane(
          tester,
          container,
          const ChatDetailPane(
            chatId: _chatId,
            peerUid: _athleteUid,
            peerNameInitial: 'Agustín',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Agustín'), findsOneWidget);
      },
    );
  });

  group(
      'ChatDetailPane header — peerUid/peerNameInitial null (global chat section)',
      () {
    testWidgets(
      'resolves the name via chatsForCurrentUserProvider (unchanged behavior)',
      (tester) async {
        final container = _buildContainer(overrides: [
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream<List<Chat>>.value([_stubChat()]),
          ),
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
          ),
        ]);
        addTearDown(container.dispose);

        await _pumpPane(
          tester,
          container,
          const ChatDetailPane(chatId: _chatId),
        );
        await tester.pumpAndSettle();

        expect(find.text('Agustín'), findsOneWidget);
      },
    );

    testWidgets(
      'shows "Usuario eliminado" while chatsForCurrentUserProvider is still '
      'loading (documented original behavior, preserved for the '
      'peer-unknown path: otherUid stays null → pubAsync is `data(null)`, '
      'NOT `loading` → falls into the data branch with p == null)',
      (tester) async {
        final chatsController = StreamController<List<Chat>>();
        addTearDown(chatsController.close);

        final container = _buildContainer(overrides: [
          chatsForCurrentUserProvider.overrideWith(
            (ref) => chatsController.stream,
          ),
        ]);
        addTearDown(container.dispose);

        await _pumpPane(
          tester,
          container,
          const ChatDetailPane(chatId: _chatId),
        );
        await tester.pump();

        expect(find.text('Usuario eliminado'), findsOneWidget);
      },
    );

    testWidgets(
      'shows "…" once chatsForCurrentUserProvider resolves an otherUid but '
      'userPublicProfileProvider is still loading',
      (tester) async {
        final profileController = StreamController<UserPublicProfile?>();
        addTearDown(profileController.close);

        final container = _buildContainer(overrides: [
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream<List<Chat>>.value([_stubChat()]),
          ),
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => profileController.stream,
          ),
        ]);
        addTearDown(container.dispose);

        await _pumpPane(
          tester,
          container,
          const ChatDetailPane(chatId: _chatId),
        );
        await tester.pump();

        expect(find.text('…'), findsOneWidget);
      },
    );

    testWidgets(
      'shows "Usuario eliminado" when the resolved profile is null (deleted user)',
      (tester) async {
        final container = _buildContainer(overrides: [
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream<List<Chat>>.value([_stubChat()]),
          ),
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => Stream<UserPublicProfile?>.value(null),
          ),
        ]);
        addTearDown(container.dispose);

        await _pumpPane(
          tester,
          container,
          const ChatDetailPane(chatId: _chatId),
        );
        await tester.pumpAndSettle();

        expect(find.text('Usuario eliminado'), findsOneWidget);
      },
    );
  });

  // Regression coverage for the empty-string (`''`) inconsistency found in
  // adversarial review: `''` must be treated as "absent" EVERYWHERE
  // (`_usableName`), never as a usable name and never left to slip through
  // an `?? ` fallback that only catches `null`.
  group('ChatDetailPane header — empty-string (\'\') normalization', () {
    testWidgets(
      'global path (peerUid/peerNameInitial null): a live displayName == "" '
      'is treated as absent, same as a deleted user — NOT rendered blank',
      (tester) async {
        final container = _buildContainer(overrides: [
          chatsForCurrentUserProvider.overrideWith(
            (ref) => Stream<List<Chat>>.value([_stubChat()]),
          ),
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) =>
                Stream<UserPublicProfile?>.value(_stubPub(displayName: '')),
          ),
        ]);
        addTearDown(container.dispose);

        await _pumpPane(
          tester,
          container,
          const ChatDetailPane(chatId: _chatId),
        );
        await tester.pumpAndSettle();

        // `_usableName('')` is null, `peerNameInitial` is null too → falls
        // through to 'Usuario eliminado'. Deliberate normalization vs.
        // pre-fix behavior, where this rendered a blank header (a latent
        // bug, not a preserved contract) — see the code comment in
        // chat_detail_pane.dart above `resolvedName`.
        //
        // NOTE: we don't assert `find.text(''), findsNothing` globally —
        // the composer's `TextField` always has an empty-text
        // `EditableText` in the tree regardless of the header, which would
        // make that assertion meaningless/flaky. The header name Text is
        // the only thing under test here.
        expect(find.text('Usuario eliminado'), findsOneWidget);
      },
    );

    testWidgets(
      'loading with peerNameInitial == "" shows \'…\', never blank',
      (tester) async {
        final profileController = StreamController<UserPublicProfile?>();
        addTearDown(profileController.close);

        final container = _buildContainer(overrides: [
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => profileController.stream,
          ),
        ]);
        addTearDown(container.dispose);

        await _pumpPane(
          tester,
          container,
          const ChatDetailPane(
            chatId: _chatId,
            peerUid: _athleteUid,
            peerNameInitial: '',
          ),
        );
        await tester.pump();

        // Same caveat as the previous test: no global `find.text('')`
        // assertion — the composer's `EditableText` always has empty text
        // and would make that check meaningless. '…' presence is the
        // actual regression guard (Finding 2: peerNameInitial == '' must
        // not fall through as if it were a usable name).
        expect(find.text('…'), findsOneWidget);
      },
    );

    testWidgets(
      'avatar/name agree while loading with peerNameInitial == "": avatar '
      'shows no letter (SizedBox.shrink) and name shows \'…\' — both '
      '"unknown", never a mismatched \'?\' letter next to \'…\'',
      (tester) async {
        final profileController = StreamController<UserPublicProfile?>();
        addTearDown(profileController.close);

        final container = _buildContainer(overrides: [
          userPublicProfileProvider(_athleteUid).overrideWith(
            (ref) => profileController.stream,
          ),
        ]);
        addTearDown(container.dispose);

        await _pumpPane(
          tester,
          container,
          const ChatDetailPane(
            chatId: _chatId,
            peerUid: _athleteUid,
            peerNameInitial: '',
          ),
        );
        await tester.pump();

        expect(find.text('…'), findsOneWidget);
        expect(find.text('?'), findsNothing);
        // The avatar's letter Text is entirely absent (SizedBox.shrink),
        // not just an empty string — confirms the loading gate itself
        // treats '' the same as null.
        final avatarInitialFinder = find.descendant(
          of: find.byType(CircleAvatar),
          matching: find.byType(Text),
        );
        expect(avatarInitialFinder, findsNothing);
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

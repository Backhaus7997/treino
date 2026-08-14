// Widget tests for ChatDetailPane's header name resolution.
//
// Covers the name-flash fix: when the caller already knows the peer
// (`peerUid` + `peerNameInitial`, e.g. the alumno-detail Chat tab), the
// header must show the real name on the FIRST frame — never the
// "Usuario eliminado" / "…" placeholders that the cold two-hop
// `chatsForCurrentUserProvider` → `userPublicProfileProvider` derivation
// produces while loading.
//
// Also covers regression safety for the peer-unknown path (global chat
// section): with `peerUid`/`peerNameInitial` both null, the header must
// keep resolving via `chatsForCurrentUserProvider` exactly as before.

import 'dart:async';

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

/// Monta [ChatDetailPane] directamente (no vía ChatSectionScreen) para poder
/// pumpear el PRIMER frame sin `pumpAndSettle` y así detectar un flash de
/// placeholder que un `pumpAndSettle` esconde.
ProviderContainer _buildContainer({
  required List<Override> overrides,
}) {
  final container = ProviderContainer(overrides: [
    currentUidProvider.overrideWithValue(_pfUid),
    messagesProvider(_chatId).overrideWith(
      (ref) => Stream<List<Message>>.value(const []),
    ),
    ...overrides,
  ]);
  return container;
}

Future<void> _pumpPane(
  WidgetTester tester,
  ProviderContainer container,
  Widget pane,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: pane),
      ),
    ),
  );
}

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
}

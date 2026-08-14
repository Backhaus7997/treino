// Widget test for the Chat detail pane composer attach menu (Fase 8,
// remediación ronda 1 — CRITICAL-1 del verify report).
//
// Cubre:
//   - Los ListTile "Foto" y "Video" del bottom sheet de adjuntar deben usar
//     `AppFonts.barlow` vía `TextStyle` directo, NO `GoogleFonts.barlow(...)`.
//     `GoogleFonts.barlow()` resuelve a un `fontFamily` con variante de peso
//     embebida (ej. "Barlow_400") — distinto al `AppFonts.barlow` ("Barlow")
//     que ya usa el resto de la sección — y dispara un fetch de red del
//     `.ttf` en cada apertura del menú (efecto real, no solo cosmético).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
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

Widget _wrapSection(ProviderContainer container) => MediaQuery(
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

void main() {
  group('ChatDetailPane composer attach menu — tokens (remediación WU-1)', () {
    testWidgets(
      '"Foto" y "Video" usan AppFonts.barlow vía TextStyle, no '
      'GoogleFonts.barlow',
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

        final photoText = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('chat_composer_attach_menu_photo')),
            matching: find.text('Foto'),
          ),
        );
        expect(
          photoText.style?.fontFamily,
          AppFonts.barlow,
          reason: 'GoogleFonts.barlow() resuelve a un fontFamily con '
              'variante embebida, nunca exactamente "AppFonts.barlow" — '
              'esta assert solo pasa con TextStyle(fontFamily: '
              'AppFonts.barlow) directo.',
        );
        // GoogleFonts NUNCA setea `package` en el TextStyle final que
        // devuelve GoogleFonts.barlow(); pero SÍ resuelve un `fontFamily`
        // con el peso embebido, ej. "Barlow_400" (nunca la constante pura
        // "Barlow"). Confirmamos explícitamente que no matchea ese patrón.
        expect(photoText.style?.fontFamily, isNot(contains('_')));

        final videoText = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('chat_composer_attach_menu_video')),
            matching: find.text('Video'),
          ),
        );
        expect(videoText.style?.fontFamily, AppFonts.barlow);
        expect(videoText.style?.fontFamily, isNot(contains('_')));
      },
    );
  });
}

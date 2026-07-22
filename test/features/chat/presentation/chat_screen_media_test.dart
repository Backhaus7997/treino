/// Phase 11 — widget tests for _Bubble branching and _Composer attach flow.
///
/// These are SEPARATE from chat_screen_test.dart (which covers the base text
/// send path) to keep files focused and avoid modifying existing passing tests.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/firebase_storage_video_player.dart';
import 'package:treino/features/chat/application/chat_media_send_controller.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/domain/media_type.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/chat/presentation/chat_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: child,
      ),
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

Message _textMsg(String text) => Message(
      id: 'm1',
      senderId: 'bbb',
      text: text,
      createdAt: DateTime.utc(2026, 5, 21),
    );

Message _imageMsg({String text = ''}) => Message(
      id: 'm2',
      senderId: 'bbb',
      text: text,
      mediaUrl: 'https://firebasestorage.googleapis.com/img.jpg',
      mediaType: MediaType.image,
      createdAt: DateTime.utc(2026, 5, 21),
    );

Message _videoMsg({String text = ''}) => Message(
      id: 'm3',
      senderId: 'bbb',
      text: text,
      mediaUrl: 'https://firebasestorage.googleapis.com/vid.mp4',
      mediaType: MediaType.video,
      createdAt: DateTime.utc(2026, 5, 21),
    );

/// Issue #435: el estado de upload ya no vive en el State de la pantalla —
/// viene de [chatMediaSendControllerProvider]. Stub con un envío "en vuelo"
/// para verificar el cableado de la UI.
class _UploadingStubController extends ChatMediaSendController {
  @override
  ChatMediaSendState build(String chatId) =>
      const ChatMediaSendState(uploading: true, progress: 0.4);
}

void main() {
  group('_Bubble branching', () {
    testWidgets('text-only bubble renders text without any media widget',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([_textMsg('hello')]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('hello'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byType(FirebaseStorageVideoPlayer), findsNothing);
    });

    testWidgets('image message renders CachedNetworkImage bubble',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([_imageMsg()]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsWidgets);
    });

    testWidgets('video message renders FirebaseStorageVideoPlayer bubble',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([_videoMsg()]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byType(FirebaseStorageVideoPlayer), findsOneWidget);
    });

    testWidgets('image message caption displayed when text non-empty',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([_imageMsg(text: 'Great shot!')]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Great shot!'), findsOneWidget);
    });
  });

  group('_Composer attach button', () {
    testWidgets('attach button is present in composer', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value(const <Message>[]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      // Attach button has tooltip from chatAttachMediaLabel = "Adjuntar"
      expect(find.byTooltip('Adjuntar'), findsOneWidget);
    });

    testWidgets('tap attach button opens bottom sheet with Foto/Video options',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value(const <Message>[]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Adjuntar'));
      await tester.pumpAndSettle();

      // Bottom sheet shows Foto and Video options.
      expect(find.text('Foto'), findsAtLeastNWidgets(1));
      expect(find.text('Video'), findsAtLeastNWidgets(1));
    });
  });

  group('upload state wiring (issue #435)', () {
    testWidgets(
        'progress bar y composer deshabilitado vienen del provider, no del '
        'State local', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value(const <Message>[]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
          chatMediaSendControllerProvider
              .overrideWith(_UploadingStubController.new),
        ],
      ));
      // pump (no pumpAndSettle): el spinner del botón send es una animación
      // indeterminada que nunca settlea mientras sending == true.
      await tester.pump();
      await tester.pump();

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.4, 1e-9));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse,
          reason: 'Composer bloqueado mientras el envío de media está '
              'en vuelo — aunque lo haya iniciado una instancia anterior '
              'de la pantalla');
    });
  });
}
